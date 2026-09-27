// The eight purchasable/powered doors (GDD §5.3): casing, the blocker art per `look` and its opening beat.
//   glass_chained  D1 smoked glass double doors, "ACTION 13 NEWS", chained: the chain snaps, the doors swing
//   padded         D2 tufted red "EMPLOYEES ONLY" doors with brass studs: they burst open in a stuffing puff
//   debris_desk    D3 toppled desk, film-can stacks, chair and a moving blanket: everything tumbles away
//   soundstage     D4 padded plum soundstage doors with portholes and a dark ON AIR box: heavy swing
//   steel_keypad   D5 steel ENGINEERING doors + keypad: 4 keypad flashes (G4-C5-E5-G5 cue), LED green, swing
//   elephant       D6 plywood scene-dock door on a track: shudders, then rumbles sideways along the wall
//   debris_cables  D7 waterfall of patch cables over puppet crates: cables zip up, crates tumble away
//   fire_exit      DY red fire door with push bars and an EXIT sign: buzzes, then swings out to the Yard
// Door-local frame: origin at the opening centre on the floor, +x along the opening, +z toward areas[1]
// (every door opens toward areas[1]). ON AIR boxes hang over both faces of the doors flagged onAir.
//
// new Door(ctx, data) — ctx = { game, surf }; the instance carries every layout field plus:
//   open (bool), group (Object3D added by Level), pos (Vector3, opening centre at 1.3 m), approach
//   ({ areaId: Vector3 } 1.1 m in front of each face), meshes ([group]), onAirBoxes,
//   play(instant) (runs the beat; Level does colliders/nav/events), update(dt), reset(), setOnAir(on), busy.

import * as THREE from 'three';
import * as geo from '../core/geo.js';
import { WALL_T, AREAS, areaAt } from './layout.js';
import { ease, Timeline, Debris } from './anim.js';
import { labelTex, stencilTex, hazardTex, boltSignTex, newspaperTex, movingPadTex } from './decals.js';

const H = WALL_T / 2;
const HINGE_Z = H + 0.07;
const AREA_CEIL = Object.fromEntries(AREAS.map((a) => [a.id, a.ceilY]));
const OPEN = 2.9;
const _v = new THREE.Vector3();
const rnd = (a, b) => a + Math.random() * (b - a);

export class Door {
  constructor(ctx, data) {
    Object.assign(this, data);
    this.game = ctx.game;
    this.surf = ctx.surf;
    this.open = false;
    this.busy = false;
    const [cx, cz] = data.center;
    const [axis, at] = data.line;
    const n = axis === 'x' ? [1, 0] : [0, 1];
    if (areaAt(cx + n[0] * 0.5, cz + n[1] * 0.5) !== data.areas[1]) { n[0] = -n[0]; n[1] = -n[1]; }
    this.normal = new THREE.Vector3(n[0], 0, n[1]);
    this.pos = new THREE.Vector3(axis === 'x' ? at : cx, 1.3, axis === 'z' ? at : cz);
    this.approach = {
      [data.areas[0]]: new THREE.Vector3(cx - n[0] * 1.1, 0, cz - n[1] * 1.1),
      [data.areas[1]]: new THREE.Vector3(cx + n[0] * 1.1, 0, cz + n[1] * 1.1),
    };
    this.group = new THREE.Group();
    this.group.name = `door:${data.id}`;
    this.pivot = new THREE.Group();
    this.pivot.position.set(cx, 0, cz);
    this.pivot.rotation.y = Math.atan2(n[0], n[1]);
    this.frame = new THREE.Group();
    this.blocker = new THREE.Group();
    this.blocker.userData.dynamic = true;
    this.pivot.add(this.frame, this.blocker);
    this.group.add(this.pivot);
    this.meshes = [this.group];
    this.onAirBoxes = [];
    this._tl = new Timeline();
    this._debris = new Debris();
    this._resets = [];
    this._silent = false;
    LOOKS[data.look](this);
    if (data.onAir) for (const side of [-1, 1]) this._onAirBox(side);
    geo.mergeByMaterial(this.frame);
    this._rest = [];
    this.blocker.traverse((o) => {
      if (o !== this.blocker) this._rest.push([o, o.position.clone(), o.quaternion.clone(), o.scale.clone(), o.visible]);
    });
  }

  play(instant = false) {
    this._tl.clear();
    this._debris.clear();
    this._silent = instant;
    this._beat();
    if (instant) {
      this._tl.finish();
      this._debris.finish();
      this.busy = false;
      this._bake();
    } else this.busy = true;
    this._silent = false;
  }

  update(dt) {
    if (!this.busy) return;
    const a = this._tl.update(dt);
    const b = this._debris.update(dt);
    this.busy = a || b;
    if (!this.busy && this.open) this._bake();
  }

  // Once open, the blocker never moves again: show a merged copy instead (one mesh per material across both
  // leaves and every remaining piece, about half the draw calls of a visible open door). reset() restores the
  // live blocker. Pieces hidden by the beat (debris) are dropped from the copy.
  _bake() {
    if (this._baked) return;
    const copy = this.blocker.clone(true);
    const dead = [];
    copy.traverse((o) => { if (o !== copy && !o.visible) dead.push(o); });
    for (const o of dead) if (o.parent) o.parent.remove(o);
    this.pivot.add(copy);
    geo.mergeByMaterial(copy);
    copy.name = 'blocker:baked';
    this.blocker.visible = false;
    this._baked = copy;
  }

  _unbake() {
    if (!this._baked) return;
    this.pivot.remove(this._baked);
    this._baked = null;
    this.blocker.visible = true;
  }

  reset() {
    this._unbake();
    this._tl.clear();
    this._debris.clear();
    this.busy = false;
    for (const [o, p, q, s, vis] of this._rest) {
      o.position.copy(p); o.quaternion.copy(q); o.scale.copy(s); o.visible = vis;
    }
    for (const fn of this._resets) fn();
    this.open = false;
  }

  setOnAir(on) {
    for (const b of this.onAirBoxes) b.face.material = on ? b.lit : b.dark;
  }

  // ---------------------------------------------------------------------------------------- beat helpers
  sound(id) {
    if (!this._silent && this.game.audio) this.game.audio.play(id, { pos: this.pos });
  }

  puff(colors) {
    const fx = this.game.fx;
    if (this._silent || !fx || !fx.burst) return;
    fx.burst(this.pos, { count: 22, colors, speed: 3.2, size: 0.28, life: 0.8, gravity: -0.6, shape: 'puff' });
  }

  // +1 / −1: the local z side away from the player (debris flies away from whoever bought the door).
  away() {
    const p = this.game.player && this.game.player.pos;
    if (!p) return 1;
    this.pivot.updateMatrixWorld(true);
    return this.pivot.worldToLocal(_v.copy(p)).z > 0 ? -1 : 1;
  }

  swing(leaf, s, start, dur, back = 1.4) {
    this._tl.span(start, dur, (k) => { leaf.rotation.y = s * OPEN * ease.outBack(k, back); });
  }

  tumble(pieces, { start = 0, spread = 0.25, up = [2.5, 5], out = [2, 4], life = [0.8, 1.2] } = {}) {
    const side = this.away();
    pieces.forEach((p, i) => {
      this._debris.launch(p, [rnd(-1.5, 1.5), rnd(up[0], up[1]), side * rnd(out[0], out[1])],
        [rnd(-8, 8), rnd(-6, 6), rnd(-8, 8)],
        { delay: start + (spread * i) / Math.max(1, pieces.length - 1), life: rnd(life[0], life[1]), radius: 0.12 });
    });
  }

  _onAirBox(side) {
    const M = this.game.mats;
    const z = side * (H + 0.12);
    // Over the head, unless that side's ceiling (minus a crown) is too low: then as high as it fits, and beside
    // the casing if it would hit the head (D4's Green Room face: the box used to sink into the ceiling).
    const top = (AREA_CEIL[this.areas[side < 0 ? 0 : 1]] ?? 99) - 0.16;
    let x = 0, y = this.height + 0.45;
    if (y + 0.21 > top) {
      y = top - 0.21;
      if (y - 0.21 < this.height + CASE_W + 0.03) { x = this.width / 2 + CASE_W + 0.56; y = Math.min(this.height - 0.1, y); }
    }
    this.frame.add(geo.mesh(geo.roundedBox(1.0, 0.42, 0.2, 0.05, 2), M.toon('#2A1A1E', { rough: 0.5 }), { pos: [x, y, z], cast: false }));
    const tex = labelTex('ON AIR', { w: 512, h: 160, fg: '#FFFFFF', bg: '#3A0E12' });
    const dark = M.toon('#8A3A3A', { map: tex, rough: 0.35, rim: 0.1 });
    const lit = M.glow('#FF3B30', 2.4, { map: tex });
    const face = geo.mesh(geo.plane(0.86, 0.3), dark, { pos: [0, y, z + side * 0.106], rot: [0, side < 0 ? Math.PI : 0, 0], cast: false });
    face.userData.noMerge = true;
    this.frame.add(face);
    this.onAirBoxes.push({ face, dark, lit });
  }
}

// ------------------------------------------------------------------------------------------------- helpers
function add(parent, g, mat, pos, rot, opts = {}) {
  const m = geo.mesh(g, mat, { pos, rot, cast: opts.cast ?? true });
  parent.add(m);
  return m;
}

const darkGlass = (M) => M.toon('#1C2733', { rough: 0.06, metal: 0.25, env: 1.3, rim: 0.55, rimColor: '#9FC8FF', rimPower: 3 });
const decal = (M, map, o = {}) => M.toon('#ffffff', { map, alphaTest: 0.4, rough: 0.55, rim: 0, ...o });

// Door casing: two jambs and a head that wrap the wall ends and stand CASE_PROUD proud of both faces (deeper than
// any wall trim, so baseboards and chair rails die inside it). Their inner faces sit CASE_INSET inside the
// opening, never in the plane of a wall face (architecture.js no longer draws the jamb caps and soffit they cover).
// The jambs stop under the head instead of overlapping it (no coplanar corner blocks).
const CASE_PROUD = 0.05;
const CASE_INSET = 0.005;
const CASE_W = 0.14;
function casing(d, mat) {
  const W = d.width, Hh = d.height, D = 2 * (H + CASE_PROUD), I = CASE_INSET;
  const jh = Hh - I, jw = CASE_W + I;
  for (const s of [-1, 1]) add(d.frame, geo.roundedBox(jw, jh, D, 0.02, 2), mat, [s * (W / 2 - I + jw / 2), jh / 2, 0]);
  add(d.frame, geo.roundedBox(W + 2 * CASE_W, CASE_W + I, D, 0.02, 2), mat, [0, jh + (CASE_W + I) / 2, 0]);
}

// Double leaves hinged at the jambs on the +z face; build(hinge, s, w) fills one leaf spanning x ∈ [−s·w, 0].
function leaves(d, build) {
  const w = d.width / 2;
  return [-1, 1].map((s) => {
    const hinge = new THREE.Group();
    hinge.position.set(s * w, 0, HINGE_Z);
    build(hinge, s, w);
    geo.mergeByMaterial(hinge);
    d.blocker.add(hinge);
    return hinge;
  });
}

function porthole(M, parent, x, y, r, chrome) {
  const glass = darkGlass(M);
  for (const z of [-1, 1]) {
    add(parent, geo.torus(r, 0.028, 8, 28), chrome, [x, y, z * 0.055], null, { cast: false });
    add(parent, new THREE.CircleGeometry(r, 24), glass, [x, y, z * 0.05], [0, z < 0 ? Math.PI : 0, 0], { cast: false });
  }
}

function tiledPlane(w, h, ru, rv = 1) {
  const g = new THREE.PlaneGeometry(w, h);
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * ru, uv.getY(i) * rv);
  return g;
}

// ---------------------------------------------------------------------------------------------------- looks
const LOOKS = {
  glass_chained(d) {
    const M = d.game.mats, S = d.surf;
    const bronze = M.toon('#6E5A44', { metal: 0.55, rough: 0.35, rimColor: '#FFC98A' });
    const chrome = S.plain('trim_chrome');
    const glass = darkGlass(M);
    const paper = M.toon('#ffffff', { map: newspaperTex(), rough: 0.9, rim: 0 });
    casing(d, bronze);
    const Hh = d.height;
    const lv = leaves(d, (g, s, w) => {
      const c = -s * w / 2;
      add(g, geo.roundedBox(0.09, Hh, 0.06, 0.02, 2), bronze, [-s * 0.045, Hh / 2, 0]);
      add(g, geo.roundedBox(0.09, Hh, 0.06, 0.02, 2), bronze, [-s * (w - 0.045), Hh / 2, 0]);
      add(g, geo.roundedBox(w, 0.12, 0.06, 0.02, 2), bronze, [c, Hh - 0.06, 0]);
      add(g, geo.roundedBox(w, 0.32, 0.06, 0.02, 2), bronze, [c, 0.17, 0]);
      add(g, geo.box(w - 0.16, Hh - 0.45, 0.012), glass, [c, 0.33 + (Hh - 0.45) / 2, 0], null, { cast: false });
      const tex = labelTex(s > 0 ? 'ACTION\n13' : 'NEWS', { w: 256, h: 256, fg: '#F4F1E8', stroke: '#E23B3B' });
      add(g, geo.plane(w - 0.3, w - 0.3), decal(M, tex), [c, 1.62, -0.012], [0, Math.PI, 0], { cast: false });
      add(g, geo.plane(0.42, 0.52), paper, [c - s * 0.12, 1.0, 0.012], [0, 0, s * 0.06], { cast: false });
      add(g, geo.cylinder(0.022, 0.022, 0.5, 10), chrome, [-s * (w - 0.35), 1.05, -0.075], [0, 0, Math.PI / 2]);
      for (const x of [w - 0.12, w - 0.58]) add(g, geo.cylinder(0.02, 0.02, 0.1, 8), chrome, [-s * x, 1.05, -0.05], [Math.PI / 2, 0, 0]);
      add(g, geo.cylinder(0.022, 0.022, 0.6, 10), chrome, [-s * (w - 0.14), 1.05, 0.07]);
    });
    // The chain: 14 elongated links looped round both push bars, and a brass padlock.
    const steel = M.toon('#9AA0A8', { metal: 0.85, rough: 0.3 });
    const brass = M.toon('#D9A520', { metal: 0.85, rough: 0.28 });
    const z = HINGE_Z - 0.075;
    // Links are merged into three chunks (the snap throws chunks, not 14 separate draw calls).
    const pieces = [0, 1, 2].map(() => new THREE.Group());
    for (let i = 0; i < 14; i++) {
      const f = (i / 14) * Math.PI * 2;
      const link = add(pieces[Math.floor(i / 5)], geo.torus(0.04, 0.011, 6, 12), steel, [0.32 * Math.cos(f), 0.1 * Math.sin(f), 0], null, { cast: false });
      link.scale.set(1.35, 1, 1);
      if (i % 2) link.rotation.set(Math.PI / 2, 0, f + Math.PI / 2, 'ZYX'); else link.rotation.set(0, 0, f + Math.PI / 2);
    }
    for (const c of pieces) {
      c.position.set(0, 1.05, z);
      geo.mergeByMaterial(c);
      d.blocker.add(c);
    }
    const lock = new THREE.Group();
    add(lock, geo.roundedBox(0.11, 0.13, 0.05, 0.02, 2), brass, [0, 0, 0], null, { cast: false });
    add(lock, geo.torus(0.035, 0.011, 6, 12, Math.PI), steel, [0, 0.065, 0], null, { cast: false });
    lock.position.set(0, 0.86, z);
    d.blocker.add(lock);
    pieces.push(lock);
    d._beat = () => {
      d.sound('door_chain_snap');
      const side = d.away();
      for (const p of pieces) {
        d._debris.launch(p, [rnd(-2.5, 2.5), rnd(1.5, 4), -side * rnd(0.6, 2)], [rnd(-14, 14), rnd(-14, 14), rnd(-14, 14)],
          { life: rnd(0.5, 0.9), radius: 0.04 });
      }
      d.swing(lv[0], -1, 0.18, 0.75, 1.2);
      d.swing(lv[1], 1, 0.22, 0.75, 1.2);
    };
  },

  padded(d) {
    const M = d.game.mats, S = d.surf;
    casing(d, S.plain('trim_chocolate'));
    const pad = S.plain('quilt_red');
    const brass = M.toon('#E0B040', { metal: 0.9, rough: 0.25 });
    const chrome = S.plain('trim_chrome');
    const Hh = d.height;
    const sign = decal(M, labelTex('EMPLOYEES ONLY', { w: 512, h: 128, fg: '#F6E7C8', bg: '#5A3A22', border: '#E8A92E' }));
    const lv = leaves(d, (g, s, w) => {
      const c = -s * w / 2;
      add(g, geo.roundedBox(w - 0.02, Hh - 0.04, 0.09, 0.035, 2), pad, [c, Hh / 2, 0]);
      const x0 = -s * 0.06, x1 = -s * (w - 0.06), y0 = 0.08, y1 = Hh - 0.08;
      const stud = (x, y) => add(g, geo.sphere(0.02, 8, 6), brass, [x, y, -0.05], null, { cast: false });
      for (let t = 0; t <= 1.0001; t += 1 / 9) { stud(x0 + (x1 - x0) * t, y0); stud(x0 + (x1 - x0) * t, y1); }
      for (let t = 1 / 20; t < 1; t += 1 / 20) { stud(x0, y0 + (y1 - y0) * t); stud(x1, y0 + (y1 - y0) * t); }
      porthole(M, g, c, 1.72, 0.15, chrome);
      add(g, geo.roundedBox(0.12, 0.36, 0.012, 0.004, 1), chrome, [-s * (w - 0.14), 1.1, -0.052], null, { cast: false });
      if (s < 0) add(g, geo.plane(0.72, 0.18), sign, [c, 1.3, -0.052], [0, Math.PI, 0], { cast: false });
    });
    d._beat = () => {
      d.sound('door_poof');
      d.swing(lv[0], -1, 0, 0.55, 1.7);
      d.swing(lv[1], 1, 0.03, 0.55, 1.7);
      d.puff(['#F6E7C8', '#FFFFFF', '#B5472A']);
    };
  },

  debris_desk(d) {
    const M = d.game.mats, S = d.surf;
    casing(d, S.plain('trim_cream'));
    const teak = M.toon('#B07A45', { map: d.game.tex.woodPanel('#B07A45'), rough: 0.4 });
    const steel = S.plain('trim_steel');
    const can = M.toon('#B9C0C8', { metal: 0.75, rough: 0.3 });
    const lids = ['#E23B3B', '#2F5BD3', '#E8A92E', '#2E8C8C'].map((c) => M.toon(c, { rough: 0.45 }));
    const vinyl = M.toon('#E3662B', { rough: 0.45 });
    const paper = M.toon('#F4F1E8', { rough: 0.9, rim: 0, side: THREE.DoubleSide });
    const pieces = [];
    // Blanket hung across the doorway behind the pile.
    const blanket = add(d.blocker, geo.plane(d.width + 0.1, d.height), M.toon('#ffffff', { map: movingPadTex(), rough: 0.95, side: THREE.DoubleSide }),
      [0, d.height / 2, 0.1], null, { cast: false });
    // Toppled desk, on its back across the opening.
    const piece = (g, x, y, z, rot) => {
      g.position.set(x, y, z);
      g.rotation.set(...rot);
      geo.mergeByMaterial(g);
      d.blocker.add(g);
      pieces.push(g);
      return g;
    };
    const desk = new THREE.Group();
    add(desk, geo.roundedBox(1.7, 0.06, 0.8, 0.02, 2), teak, [0, 0.72, 0]);
    add(desk, geo.roundedBox(0.45, 0.66, 0.74, 0.03, 2), teak, [0.55, 0.36, 0]);
    add(desk, geo.roundedBox(1.1, 0.4, 0.03, 0.01, 1), teak, [-0.25, 0.48, -0.36]);
    for (const x of [-0.8, -0.05]) for (const z of [-0.34, 0.34]) add(desk, geo.cylinder(0.025, 0.025, 0.7, 8), steel, [x, 0.35, z], null, { cast: false });
    piece(desk, 0.1, 0.4, -0.15, [-1.45, 0.08, 0.05]);
    // Film-can stacks (each stack tumbles as one piece) and a few loose cans.
    const stack = (x, z, n, lid) => {
      const g = new THREE.Group();
      for (let i = 0; i < n; i++) {
        const tw = i * 0.012 * (i % 2 ? 1 : -1);
        add(g, geo.cylinder(0.2, 0.2, 0.05, 20), can, [tw, i * 0.055, -tw], null, { cast: i === 0 });
        add(g, geo.cylinder(0.12, 0.12, 0.012, 16), lid, [tw, i * 0.055 + 0.03, -tw], null, { cast: false });
      }
      piece(g, x, 0.03, z, [0, x * 2, 0]);
    };
    stack(-0.85, -0.45, 6, lids[0]); stack(0.95, -0.5, 4, lids[1]); stack(-0.35, -0.7, 3, lids[2]);
    for (const [x, rz] of [[0.45, 1.2], [-1.05, -1.3], [0.2, 1.4]]) {
      const g = new THREE.Group();
      add(g, geo.cylinder(0.2, 0.2, 0.05, 20), can, [0, 0, 0], null, { cast: false });
      piece(g, x, 0.2, -0.75, [0.3, 0, rz]);
    }
    // Swivel chair on its side.
    const chair = new THREE.Group();
    add(chair, geo.cylinder(0.26, 0.26, 0.09, 18), vinyl, [0, 0.45, 0]);
    add(chair, geo.roundedBox(0.44, 0.4, 0.08, 0.04, 2), vinyl, [0, 0.72, -0.2]);
    add(chair, geo.cylinder(0.03, 0.03, 0.4, 8), steel, [0, 0.22, 0], null, { cast: false });
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * Math.PI * 2;
      add(chair, geo.roundedBox(0.3, 0.035, 0.05, 0.015, 1), steel, [Math.cos(a) * 0.15, 0.03, Math.sin(a) * 0.15], [0, -a, 0], { cast: false });
    }
    piece(chair, -0.55, 0.28, -0.55, [0.2, 0.6, 1.45]);
    const papers = new THREE.Group();
    for (let i = 0; i < 6; i++) {
      add(papers, geo.plane(0.3, 0.21), paper, [rnd(-1.1, 1.1), i * 0.002, rnd(-0.35, 0.35)], [-Math.PI / 2, 0, rnd(0, 3)], { cast: false });
    }
    piece(papers, 0, 0.012, -0.65, [0, 0, 0]);
    d._beat = () => {
      d.sound('door_poof');
      d.tumble(pieces, { spread: 0.3 });
      d._tl.span(0.05, 0.4, (k) => {
        const s = Math.max(0.02, 1 - k);
        blanket.scale.y = s;
        blanket.position.y = (d.height * s) / 2;
        if (k >= 1) blanket.visible = false;
      });
      d._tl.at(0.9, () => d.puff(['#C9C2B0', '#F4F1E8']));
    };
  },

  soundstage(d) {
    const M = d.game.mats, S = d.surf;
    const black = S.plain('trim_black');
    const chrome = S.plain('trim_chrome');
    casing(d, black);
    const pad = S.plain('quilt_plum');
    const Hh = d.height;
    const lv = leaves(d, (g, s, w) => {
      const c = -s * w / 2;
      for (const x of [0.05, w - 0.05]) add(g, geo.roundedBox(0.1, Hh, 0.1, 0.03, 2), black, [-s * x, Hh / 2, 0]);
      add(g, geo.roundedBox(w - 0.2, 0.14, 0.1, 0.03, 2), black, [c, Hh - 0.07, 0]);   // top rail between the stiles
      // Kick plate: 3 mm proud of the stiles and 2 mm short of the leaf edges (its ends shared the stiles' side planes).
      add(g, geo.roundedBox(w - 0.004, 0.34, 0.106, 0.02, 2), chrome, [c, 0.17, 0]);
      add(g, geo.roundedBox(w - 0.2, Hh - 0.5, 0.12, 0.05, 2), pad, [c, 0.34 + (Hh - 0.5) / 2, 0]);
      porthole(M, g, c, 2.2, 0.2, chrome);
      add(g, geo.roundedBox(0.14, 0.42, 0.014, 0.005, 1), chrome, [-s * (w - 0.16), 1.2, -0.068], null, { cast: false });
    });
    d._beat = () => {
      d.sound('door_poof');
      d.swing(lv[0], -1, 0, 0.95, 0.9);
      d.swing(lv[1], 1, 0.05, 0.95, 0.9);
    };
  },

  steel_keypad(d) {
    const M = d.game.mats, S = d.surf;
    const steelFrame = S.plain('trim_steel');
    casing(d, steelFrame);
    const steel = M.toon('#8C98A4', { metal: 0.55, rough: 0.38, rimColor: '#9FC8FF' });
    const chrome = S.plain('trim_chrome');
    const Hh = d.height;
    const lv = leaves(d, (g, s, w) => {
      const c = -s * w / 2;
      add(g, geo.roundedBox(w - 0.02, Hh - 0.03, 0.07, 0.02, 2), steel, [c, Hh / 2, 0]);
      for (const y of [0.75, 1.95]) for (const z of [-1, 1]) add(g, geo.roundedBox(w - 0.3, 0.8, 0.02, 0.01, 1), steel, [c, y, z * 0.04], null, { cast: false });
      add(g, geo.cylinder(0.022, 0.022, w - 0.3, 10), chrome, [c, 1.05, -0.09], [0, 0, Math.PI / 2]);
      if (s < 0) add(g, geo.plane(0.9, 0.24), decal(M, stencilTex('ENGINEERING', { w: 512, h: 128, ink: '#F4C21E' })), [c, 1.62, -0.056], [0, Math.PI, 0], { cast: false });
      else add(g, geo.plane(0.42, 0.42), decal(M, boltSignTex()), [c, 1.62, -0.056], [0, Math.PI, 0], { cast: false });
    });
    // Keypad on the approach face (areas[0], −z), to the viewer's right.
    const kp = new THREE.Group();
    kp.userData.noMerge = true;
    kp.position.set(-(d.width / 2 + 0.42), 1.35, -(H + 0.03));
    add(kp, geo.roundedBox(0.24, 0.36, 0.05, 0.015, 2), M.toon('#3A3F46', { rough: 0.5 }), [0, 0, 0]);
    const off = M.toon('#D8D8D0', { rough: 0.4 });
    const on = M.glow('#7CFF6A', 2.2);
    // The four buttons of the G4-C5-E5-G5 cue stay separate meshes (they flash); the other eight are merged.
    const idle = new THREE.Group();
    const buttons = [];
    for (let r = 0; r < 4; r++) {
      for (let q = 0; q < 3; q++) {
        const i = r * 3 + q;
        const flashes = i === 6 || i === 0 || i === 2 || i === 4;
        buttons[i] = add(flashes ? kp : idle, geo.roundedBox(0.05, 0.042, 0.02, 0.008, 1), off, [(1 - q) * 0.065, 0.07 - r * 0.055, -0.03], null, { cast: false });
      }
    }
    geo.mergeByMaterial(idle);
    kp.add(idle);
    const ledOff = M.toon('#C0302A', { emissive: '#C0302A', emissiveIntensity: 0.8 });
    const ledOn = M.glow('#52E04A', 2.5);
    const led = add(kp, geo.sphere(0.014, 10, 8), ledOff, [0, 0.145, -0.028], null, { cast: false });
    d.frame.add(kp);
    const seq = [buttons[6], buttons[0], buttons[2], buttons[4]];
    d._resets.push(() => { for (const b of seq) b.material = off; led.material = ledOff; });
    d._beat = () => {
      d.sound('door_keypad_motif');
      seq.forEach((b, i) => {
        d._tl.at(i * 0.2, () => { b.material = on; });
        d._tl.at(i * 0.2 + 0.16, () => { b.material = off; });
      });
      d._tl.at(0.75, () => { led.material = ledOn; });
      d.swing(lv[0], -1, 0.85, 0.6, 1.3);
      d.swing(lv[1], 1, 0.88, 0.6, 1.3);
    };
  },

  elephant(d) {
    const M = d.game.mats, S = d.surf;
    const W = d.width, Hh = d.height;
    const steel = S.plain('trim_steel');
    casing(d, S.plain('trim_black'));
    const PZ = -(H + CASE_PROUD + 0.062);   // track and panel: the panel back stays 2 mm clear of the casing
    add(d.frame, geo.roundedBox(2 * W + 0.9, 0.12, 0.16, 0.03, 2), steel, [W / 2, Hh + 0.42, PZ]);
    const ply = M.toon('#C49A6C', { map: d.game.tex.woodPanel('#C49A6C'), rough: 0.6, rim: 0.2, rimColor: '#FF4FA0' });
    const panel = new THREE.Group();
    panel.position.set(0, 0, PZ);
    add(panel, geo.roundedBox(W + 0.3, Hh + 0.25, 0.12, 0.04, 2), ply, [0, (Hh + 0.25) / 2, 0]);
    for (const x of [-(W / 2 - 0.1), W / 2 - 0.1]) add(panel, geo.roundedBox(0.14, Hh + 0.2, 0.05, 0.02, 1), ply, [x, (Hh + 0.2) / 2, -0.075]);
    add(panel, geo.plane(W * 0.82, 1.1), decal(M, stencilTex('SCENE DOCK\nKEEP CLEAR', { w: 512, h: 256 })), [0, 2.0, -0.101], [0, Math.PI, 0], { cast: false });
    const hz = hazardTex();
    hz.wrapS = THREE.RepeatWrapping;
    add(panel, tiledPlane(W + 0.3, 0.32, 3), M.toon('#ffffff', { map: hz, rough: 0.6, rim: 0 }), [0, 0.2, -0.066], [0, Math.PI, 0], { cast: false });
    for (const x of [-(W / 2 - 0.25), W / 2 - 0.25]) {
      add(panel, geo.roundedBox(0.06, 0.3, 0.04, 0.01, 1), steel, [x, Hh + 0.3, 0], null, { cast: false });
      add(panel, geo.cylinder(0.07, 0.07, 0.06, 14), steel, [x, Hh + 0.42, 0], [Math.PI / 2, 0, 0], { cast: false });
    }
    d.blocker.add(panel);
    d._beat = () => {
      d.sound('door_elephant');
      d._tl.span(0, 0.35, (k) => { panel.position.x = Math.sin(k * 42) * 0.025 * (1 - k); });
      d._tl.span(0.35, 1.8, (k) => { panel.position.x = (W + 0.2) * ease.inOutSine(k); });
    };
  },

  debris_cables(d) {
    const M = d.game.mats, S = d.surf;
    const W = d.width, Hh = d.height;
    casing(d, S.plain('trim_black'));
    // Cable waterfall hung from the head (group origin at the top so it zips up by scaling y).
    // A blackout drape in the middle of the opening with a layer of cables on each face.
    const cables = new THREE.Group();
    cables.position.set(0, Hh, 0);
    add(cables, geo.plane(W + 0.05, Hh), M.toon('#15121A', { rough: 1, rim: 0, side: THREE.DoubleSide }), [0, -Hh / 2, 0], null, { cast: false });
    const colors = ['#E23B3B', '#F4E03A', '#3A58E4', '#52D24A'].map((c) => M.toon(c, { rough: 0.35, rim: 0.2 }));
    for (let i = 0; i < 32; i++) {
      const side = i % 2 ? 1 : -1;
      const x = -W / 2 + 0.08 + ((W - 0.16) * (i >> 1)) / 15 + rnd(-0.05, 0.05);
      const z = side * rnd(0.03, 0.09);
      const pts = [[x, 0, z], [x + rnd(-0.12, 0.12), -Hh * 0.45, z + side * rnd(0, 0.06)],
        [x + rnd(-0.15, 0.15), -Hh + 0.3, z + side * rnd(0, 0.12)], [x + rnd(-0.25, 0.25), -Hh + 0.03, z + side * rnd(0.15, 0.45)]];
      add(cables, geo.tube(pts, rnd(0.016, 0.03), 18, 6), colors[(i >> 1) % colors.length], null, null, { cast: false });
    }
    geo.mergeByMaterial(cables);
    d.blocker.add(cables);
    // Puppet crates on the approach side (areas[0], −z).
    const crate = M.toon('#B98A57', { map: d.game.tex.woodPanel('#B98A57'), rough: 0.6 });
    const ink = decal(M, stencilTex('PUPPETS\nFRAGILE', { w: 256, h: 128 }));
    const pieces = [];
    for (const [sx, sy, sz, x, y, z, ry] of [
      [0.85, 0.62, 0.62, -0.55, 0.31, -0.45, 0.05], [0.8, 0.6, 0.6, 0.4, 0.3, -0.5, -0.08],
      [0.7, 0.55, 0.55, -0.1, 0.9, -0.45, 0.14], [0.5, 0.45, 0.45, 1.0, 0.225, -0.75, 0.3]]) {
      const g = new THREE.Group();
      add(g, geo.roundedBox(sx, sy, sz, 0.04, 2), crate, [0, 0, 0]);
      add(g, geo.plane(sx * 0.8, sy * 0.5), ink, [0, 0, -sz / 2 - 0.004], [0, Math.PI, 0], { cast: false });
      g.position.set(x, y, z);
      g.rotation.y = ry;
      d.blocker.add(g);
      pieces.push(g);
    }
    d._beat = () => {
      d.sound('door_poof');
      d._tl.span(0, 0.35, (k) => {
        cables.scale.y = Math.max(0.01, 1 - ease.outCubic(k));
        if (k >= 1) cables.visible = false;
      });
      d.tumble(pieces, { start: 0.1, spread: 0.2 });
      d._tl.at(0.95, () => d.puff(['#C9C2B0', '#B98A57']));
    };
  },

  fire_exit(d) {
    const M = d.game.mats, S = d.surf;
    const red = M.toon('#C0392B', { metal: 0.3, rough: 0.4, rimColor: '#FFC98A' });
    const chrome = S.plain('trim_chrome');
    casing(d, M.toon('#8E2A22', { metal: 0.3, rough: 0.45 }));
    const Hh = d.height;
    const plate = decal(M, labelTex('FIRE EXIT\nALARM WILL SOUND', { w: 512, h: 256, fg: '#F4F1E8', bg: '#9C2A20' }));
    const lv = leaves(d, (g, s, w) => {
      const c = -s * w / 2;
      add(g, geo.roundedBox(w - 0.02, Hh - 0.03, 0.07, 0.02, 2), red, [c, Hh / 2, 0]);
      add(g, geo.roundedBox(w - 0.25, 0.08, 0.06, 0.03, 2), chrome, [c, 1.0, -0.08]);
      for (const x of [0.15, w - 0.15]) add(g, geo.roundedBox(0.06, 0.12, 0.08, 0.02, 1), chrome, [-s * x, 1.0, -0.06], null, { cast: false });
      if (s < 0) add(g, geo.plane(0.62, 0.31), plate, [c, 1.6, -0.041], [0, Math.PI, 0], { cast: false });
    });
    // EXIT sign over the MC face: emergency-powered, always lit.
    const y = Hh + 0.36, z = -(H + 0.09);
    add(d.frame, geo.roundedBox(0.66, 0.28, 0.12, 0.03, 2), M.toon('#E8E4DC', { rough: 0.4 }), [0, y, z], null, { cast: false });
    const exit = add(d.frame, geo.plane(0.56, 0.2), M.glow('#52E04A', 2.2, { map: labelTex('EXIT', { w: 256, h: 96, fg: '#FFFFFF', bg: '#0E3A1A' }) }),
      [0, y, z - 0.066], [0, Math.PI, 0], { cast: false });
    exit.userData.noMerge = true;
    d._beat = () => {
      d.sound('door_buzz');
      d._tl.span(0, 0.5, (k) => {
        const j = Math.sin(k * 90) * 0.018 * (1 - k);
        lv[0].rotation.y = j; lv[1].rotation.y = -j;
      });
      d.swing(lv[0], -1, 0.5, 0.7, 1.4);
      d.swing(lv[1], 1, 0.52, 0.7, 1.4);
    };
  },
};
