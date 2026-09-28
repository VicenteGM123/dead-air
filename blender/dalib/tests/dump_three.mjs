// Reference dump for blender/dalib/tests/test_three_geo.py.
// Builds a battery of geometries / curves / math results with the REAL three.js (node_modules/three, r186) and the
// game's own src/core/{geo,rng,config}.js, and writes them to JSON:
//   node blender/dalib/tests/dump_three.mjs [out.json]
// Every case name here has a twin in test_three_geo.py (SIMPLE cases are shared through the JSON itself).
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';
import { mergeGeometries, mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
import { writeFileSync } from 'node:fs';
import * as G from '../../../src/core/geo.js';
import * as R from '../../../src/core/rng.js';
import { PAL, T, LAYERS } from '../../../src/core/config.js';

const out = process.argv[2] || 'three_ref.json';
const PI = Math.PI, TAU = Math.PI * 2;
const V2 = (x, y) => new THREE.Vector2(x, y);
const V3 = (x, y, z) => new THREE.Vector3(x, y, z);

// ------------------------------------------------------------------------------------------ serialisation
function geo(g) {
  if (!g) return null;
  const attrs = {};
  for (const k in g.attributes) {
    const a = g.attributes[k];
    attrs[k] = { itemSize: a.itemSize, array: Array.from(a.array) };
  }
  return {
    kind: 'geo', type: g.type, name: g.name, attrs, index: g.index ? Array.from(g.index.array) : null,
    groups: g.groups.map((x) => ({ start: x.start, count: x.count, materialIndex: x.materialIndex })),
    parameters: g.parameters ? Object.fromEntries(Object.entries(g.parameters).filter(([, v]) => typeof v === 'number' || typeof v === 'boolean')) : null,
    bbox: (g.computeBoundingBox(), [g.boundingBox.min.toArray(), g.boundingBox.max.toArray()]),
    bsphere: (g.computeBoundingSphere(), [g.boundingSphere.center.toArray(), g.boundingSphere.radius]),
  };
}
const vec = (v) => (v === null || v === undefined ? null : v.isVector3 ? [v.x, v.y, v.z] : [v.x, v.y]);
const vecs = (a) => a.map(vec);

const results = {};

// ------------------------------------------------------------------------------------------ SIMPLE (DSL) cases
// [name, ctor, args, ops]; args: numbers/bools, {v2:[[x,y],..]} (Vector2 list), {pi:k} (k*PI)
// ops: [method, ...args] applied in order; special: ['toNonIndexed'], ['mergeVertices', tol], ['q', x,y,z,w]
// (applyQuaternion), ['m4euler', x,y,z,order] (applyMatrix4 of makeRotationFromEuler), ['m4compose', px,py,pz,
// ex,ey,ez,sx,sy,sz] (applyMatrix4 of compose), ['lookAt', x,y,z], ['warpY', k] (y += k*x*z on every vertex, then
// nothing), ['clone'].
const SIMPLE = [
  ['box_default', 'BoxGeometry', [], []],
  ['box_123', 'BoxGeometry', [1, 2, 3], []],
  ['box_seg', 'BoxGeometry', [0.5, 0.3, 0.2, 2, 3, 4], []],
  ['box_fracseg', 'BoxGeometry', [1, 1, 1, 1.5, 2.7, 1], []],
  ['box_ops', 'BoxGeometry', [0.4, 0.8, 0.04], [['rotateX', 0.06], ['translate', 0, 0.95, -0.49], ['scale', 1, -1, 2]]],
  ['box_nonindexed', 'BoxGeometry', [1, 2, 3, 2, 1, 1], [['toNonIndexed']]],
  ['box_mergev', 'BoxGeometry', [1, 2, 3, 2, 1, 1], [['toNonIndexed'], ['mergeVertices', 1e-4]]],
  ['box_mergev_nonormal', 'BoxGeometry', [1, 2, 3, 2, 1, 1], [['toNonIndexed'], ['deleteAttribute', 'normal'], ['deleteAttribute', 'uv'], ['mergeVertices', 1e-4], ['computeVertexNormals']]],
  ['plane_default', 'PlaneGeometry', [], []],
  ['plane_seg', 'PlaneGeometry', [2, 1, 4, 3], [['rotateY', { pi: 1 }]]],
  ['plane_small', 'PlaneGeometry', [0.34, 0.085], [['rotateX', { pi: -0.5 }], ['translate', 0.1, 0.2, 0.3]]],
  ['plane_warp_normals', 'PlaneGeometry', [1, 1, 6, 5], [['warpY', 0.7], ['computeVertexNormals']]],
  ['circle_default', 'CircleGeometry', [], []],
  ['circle_12', 'CircleGeometry', [0.3, 12], []],
  ['circle_arc', 'CircleGeometry', [0.2, 16, 0.5, { pi: 1 }], [['rotateY', { pi: 1 }]]],
  ['circle_min3', 'CircleGeometry', [1, 2], []],
  ['ring_default', 'RingGeometry', [], []],
  ['ring_phi', 'RingGeometry', [0.1, 0.3, 24, 3], []],
  ['ring_arc', 'RingGeometry', [0.2, 0.25, 16, 1, 0.3, 2], []],
  ['cyl_default', 'CylinderGeometry', [], []],
  ['cyl_16', 'CylinderGeometry', [0.1, 0.2, 0.5, 16], []],
  ['cyl_6', 'CylinderGeometry', [0.034, 0.04, 0.05, 6], [['translate', 0, 0.875, 0]]],
  ['cyl_cone0top', 'CylinderGeometry', [0, 0.3, 1, 8, 3], []],
  ['cyl_cone0bot', 'CylinderGeometry', [0.3, 0, 1, 8, 2, false], []],
  ['cyl_open', 'CylinderGeometry', [0.2, 0.2, 1, 12, 1, true], []],
  ['cyl_theta', 'CylinderGeometry', [1, 1, 1, 8, 1, false, 0.5, 3], [['rotateZ', 0.3]]],
  ['cyl_mirror', 'CylinderGeometry', [0.1, 0.15, 0.4, 10], [['scale', -1, 1, 1]]],
  ['cone_default', 'ConeGeometry', [], []],
  ['cone_seg', 'ConeGeometry', [0.2, 0.5, 12, 2], []],
  ['sphere_default', 'SphereGeometry', [], []],
  ['sphere_20_14', 'SphereGeometry', [0.5, 20, 14], []],
  ['sphere_hemi', 'SphereGeometry', [1, 8, 6, 0, { pi: 1 }, 0, { pi: 0.5 }], []],
  ['sphere_patch', 'SphereGeometry', [0.3, 12, 8, 0.2, 5, 0.3, 2.0], []],
  ['sphere_ops', 'SphereGeometry', [0.25, 10, 8], [['q', 0.1, 0.2, 0.3, 0.9273618495495703], ['center']]],
  ['sphere_lookat', 'SphereGeometry', [0.25, 10, 8], [['translate', 0, 0, 0.3], ['lookAt', 1, 2, 3]]],
  ['sphere_lookat_up', 'CylinderGeometry', [0.05, 0.05, 1, 6], [['lookAt', 0, 5, 0]]],
  ['torus_default', 'TorusGeometry', [], []],
  ['torus_arc', 'TorusGeometry', [0.024, 0.007, 6, 12, { pi: 1.2 }], []],
  ['torus_thin', 'TorusGeometry', [0.2, 0.006, 4, 30], [['rotateX', { pi: 0.5 }], ['translate', 0, 0.863, 0]]],
  ['torus_theta', 'TorusGeometry', [1, 0.3, 8, 24, { pi: 2 }, 0.5, 3], []],
  ['lathe_default', 'LatheGeometry', [], []],
  ['lathe_pedestal', 'LatheGeometry', [{ v2: [[0, 0.3], [0.55, 0.3], [0.5, 0.6], [0.42, 1.9], [0.5, 1.98], [0, 1.98]] }, 18], []],
  ['lathe_lamp', 'LatheGeometry', [{ v2: [[0, 0.05], [0.1, 0.05], [0.125, 0.035], [0.13, 0.0]] }, 16], [['rotateZ', { pi: 0.5 }]]],
  ['lathe_two', 'LatheGeometry', [{ v2: [[0.2, 0], [0.18, 0.4]] }, 48], []],
  ['lathe_phi', 'LatheGeometry', [{ v2: [[0.1, 0], [0.3, 0.2], [0.2, 0.5]] }, 7, 0.3, 2.5], []],
  ['lathe_phi_clamp', 'LatheGeometry', [{ v2: [[0.1, 0], [0.3, 0.2], [0.2, 0.5]] }, 5, 0, 9], []],
  ['lathe_warp_normals', 'LatheGeometry', [{ v2: [[0.12, 0], [0.2, 0.1], [0.24, 0.25], [0.1, 0.3]] }, 24], [['warpY', 0.5], ['computeVertexNormals']]],
  ['capsule_default', 'CapsuleGeometry', [], []],
  ['capsule_machines', 'CapsuleGeometry', [0.031, 0.1, 3, 9], []],
  ['capsule_geo', 'CapsuleGeometry', [0.05, 0.2, 8, 12], []],
  ['capsule_hseg', 'CapsuleGeometry', [0.5, 1, 4, 8, 3], []],
  ['capsule_zero', 'CapsuleGeometry', [0.2, 0, 2, 5], []],
  ['ico_default', 'IcosahedronGeometry', [], []],
  ['ico_d1', 'IcosahedronGeometry', [0.5, 1], []],
  ['ico_d2', 'IcosahedronGeometry', [1, 2], []],
  ['octa_0', 'OctahedronGeometry', [1, 0], []],
  ['octa_2', 'OctahedronGeometry', [0.5, 2], []],
  ['tetra_0', 'TetrahedronGeometry', [1, 0], []],
  ['tetra_1', 'TetrahedronGeometry', [0.3, 1], []],
  ['dodeca_0', 'DodecahedronGeometry', [1, 0], []],
  ['rbox_default', 'RoundedBoxGeometry', [], []],
  ['rbox_1', 'RoundedBoxGeometry', [1, 2, 3, 3, 0.05], []],
  ['rbox_2', 'RoundedBoxGeometry', [0.4, 0.8, 0.04, 2, 0.0199], []],
  ['rbox_3', 'RoundedBoxGeometry', [0.3, 0.3, 0.3, 1, 0.012], []],
  ['rbox_seg0', 'RoundedBoxGeometry', [1, 1, 1, 0, 0.1], []],
  ['rbox_clamp', 'RoundedBoxGeometry', [0.2, 0.5, 0.1, 3, 0.2], []],
  ['rbox_ops', 'RoundedBoxGeometry', [0.5, 0.2, 0.3, 2, 0.03], [['m4euler', 0.3, -0.2, 1.1, 'YXZ'], ['m4compose', 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 1, 2, -1.5]]],
  ['rbox_mergev', 'RoundedBoxGeometry', [0.5, 0.2, 0.3, 2, 0.03], [['mergeVertices', 1e-4]]],
  ['rbox_mergev5', 'RoundedBoxGeometry', [0.37, 0.21, 0.13, 3, 0.02], [['deleteAttribute', 'uv'], ['mergeVertices', 1e-5]]],
  ['rbox_normals', 'RoundedBoxGeometry', [0.5, 0.2, 0.3, 2, 0.03], [['computeVertexNormals']]],
  ['sphere_nonidx_normals', 'SphereGeometry', [0.3, 7, 5], [['toNonIndexed'], ['computeVertexNormals']]],
  ['tube_default', 'TubeGeometry', [], []],
  ['extrude_default', 'ExtrudeGeometry', [], []],
  ['shape_default', 'ShapeGeometry', [], []],
];

function arg(a) {
  if (a && typeof a === 'object' && a.v2) return a.v2.map(([x, y]) => V2(x, y));
  if (a && typeof a === 'object' && 'pi' in a) return a.pi * PI;
  return a;
}
const CTORS = { ...THREE, RoundedBoxGeometry };
function applyOps(g, ops) {
  for (const [op, ...a] of ops) {
    const A = a.map(arg);
    if (op === 'toNonIndexed') g = g.toNonIndexed();
    else if (op === 'mergeVertices') g = mergeVertices(g, A[0]);
    else if (op === 'q') g.applyQuaternion(new THREE.Quaternion(A[0], A[1], A[2], A[3]));
    else if (op === 'm4euler') g.applyMatrix4(new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(A[0], A[1], A[2], A[3])));
    else if (op === 'm4compose') g.applyMatrix4(new THREE.Matrix4().compose(V3(A[0], A[1], A[2]), new THREE.Quaternion().setFromEuler(new THREE.Euler(A[3], A[4], A[5])), V3(A[6], A[7], A[8])));
    else if (op === 'lookAt') g.lookAt(V3(A[0], A[1], A[2]));
    else if (op === 'warpY') {
      const p = g.attributes.position;
      for (let i = 0; i < p.count; i++) p.setY(i, p.getY(i) + A[0] * p.getX(i) * p.getZ(i) + 0.05 * Math.sin(p.getX(i) * 7));
    } else if (op === 'clone') g = g.clone();
    else g[op](...A);
  }
  return g;
}
results.__simple = SIMPLE;
for (const [name, ctor, args, ops] of SIMPLE) {
  const g = applyOps(new CTORS[ctor](...args.map(arg)), ops);
  results[name] = geo(g);
}

// ------------------------------------------------------------------------------------------ helpers (kit.js copies)
function roundRect(w, h, r = 0.02) {
  const s = new THREE.Shape();
  const x = -w / 2, y = -h / 2;
  r = Math.min(r, w / 2 - 1e-4, h / 2 - 1e-4);
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y); s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + h - r); s.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  s.lineTo(x + r, y + h); s.quadraticCurveTo(x, y + h, x, y + h - r);
  s.lineTo(x, y + r); s.quadraticCurveTo(x, y, x + r, y);
  return s;
}
function kitExtrude(s, depth, opts = {}) {
  const bevel = Math.min(opts.bevel ?? 0.008, depth / 2 - 1e-4);
  const g = new THREE.ExtrudeGeometry(s, {
    depth: Math.max(1e-4, depth - bevel * 2), bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel,
    bevelOffset: -bevel, bevelSegments: opts.bevelSeg ?? 2, curveSegments: opts.curveSeg ?? 12,
  });
  g.translate(0, 0, -(depth - bevel * 2) / 2);
  g.computeVertexNormals();
  return g;
}
function rrShape4(w, h, rads, cu = 0, cv = 0) {
  const [bl, br, tr, tl] = rads;
  const x0 = cu - w / 2, x1 = cu + w / 2, y0 = cv - h / 2, y1 = cv + h / 2;
  const s = new THREE.Shape();
  s.moveTo(x0 + bl, y0);
  s.lineTo(x1 - br, y0); s.absarc(x1 - br, y0 + br, br, -Math.PI / 2, 0, false);
  s.lineTo(x1, y1 - tr); s.absarc(x1 - tr, y1 - tr, tr, 0, Math.PI / 2, false);
  s.lineTo(x0 + tl, y1); s.absarc(x0 + tl, y1 - tl, tl, Math.PI / 2, Math.PI, false);
  s.lineTo(x0, y0 + bl); s.absarc(x0 + bl, y0 + bl, bl, Math.PI, Math.PI * 1.5, false);
  return s;
}
function gearShape() {
  const teeth = [];
  const nT = 28, rG = 0.72;
  for (let i = 0; i < nT * 2; i++) { const a = (i / (nT * 2)) * TAU, r = i % 2 ? rG : rG + 0.05; teeth.push([Math.cos(a) * r, Math.sin(a) * r]); }
  const s = new THREE.Shape(teeth.map(([x, y]) => V2(x, y)));
  const ring = [];
  for (let i = 0; i < 20; i++) { const a = (i / 20) * TAU; ring.push([Math.cos(a) * 0.4, Math.sin(a) * 0.4]); }
  s.holes.push(new THREE.Path(ring.map(([x, y]) => V2(x, y))));
  return s;
}
function circlePts(r, n, cx = 0, cy = 0, rev = false) {
  const p = [];
  for (let i = 0; i < n; i++) { const a = (i / n) * TAU * (rev ? -1 : 1); p.push(V2(cx + Math.cos(a) * r, cy + Math.sin(a) * r * 0.8)); }
  return p;
}
function cboxPts(w, h, d, c) {
  const hx = w / 2, hy = h / 2, hz = d / 2;
  const cc = Math.min(c, hx * 0.45, hy * 0.45, hz * 0.45);
  const pts = [];
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) {
    pts.push(V3(sx * hx, sy * (hy - cc), sz * (hz - cc)), V3(sx * (hx - cc), sy * hy, sz * (hz - cc)), V3(sx * (hx - cc), sy * (hy - cc), sz * hz));
  }
  return pts;
}
function cboxBroadcast(w, h, d, c = 0.004) {
  c = Math.max(1e-4, Math.min(c, w / 2 - 1e-4, h / 2 - 1e-4, d / 2 - 1e-4));
  const hx = w / 2, hy = h / 2, hz = d / 2, pts = [];
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) {
    pts.push(V3(sx * hx, sy * (hy - c), sz * (hz - c)), V3(sx * (hx - c), sy * hy, sz * (hz - c)), V3(sx * (hx - c), sy * (hy - c), sz * hz));
  }
  return pts;
}

// ------------------------------------------------------------------------------------------ COMPLEX cases
const C = {};
// tubes
C.tube_catmull = () => new THREE.TubeGeometry(new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.1, 0.3, 0), V3(0.3, 0.35, 0.1), V3(0.5, 0.2, -0.1)]), 24, 0.02, 8, false);
C.tube_closed = () => {
  const loop = []; for (let i = 0; i < 9; i++) { const a = (i / 9) * TAU; loop.push(V3(Math.cos(a) * 0.1, Math.sin(a * 2) * 0.02, Math.sin(a) * 0.08)); }
  return new THREE.TubeGeometry(new THREE.CatmullRomCurve3(loop, true, 'centripetal'), 48, 0.0082, 6, true);
};
C.tube_chordal = () => new THREE.TubeGeometry(new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.2, 0.5, 0.1), V3(0.4, 0.5, 0.3), V3(1, 0, 0), V3(1.2, -0.3, 0.2)], false, 'chordal'), 32, 0.05, 5, false);
C.tube_catmullrom = () => new THREE.TubeGeometry(new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.2, 0.5, 0.1), V3(0.4, 0.5, 0.3), V3(1, 0, 0)], false, 'catmullrom', 0.3), 20, 0.05, 7, false);
C.tube_bezier3 = () => new THREE.TubeGeometry(new THREE.CubicBezierCurve3(V3(0, 0, 0), V3(0, 0.4, 0.1), V3(0.3, 0.5, -0.2), V3(0.6, 0.1, 0)), 16, 0.01, 6, false);
C.tube_line3 = () => new THREE.TubeGeometry(new THREE.LineCurve3(V3(0, 0, 0), V3(0.3, 1, 0.2)), 4, 0.03, 8, false);
C.tube_straight_y = () => new THREE.TubeGeometry(new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0, 0.5, 0), V3(0, 1, 0)]), 6, 0.02, 6, false);
C.tube_dup_points = () => new THREE.TubeGeometry(new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0, 0, 0), V3(0.2, 0.1, 0), V3(0.4, 0.1, 0.1)]), 10, 0.02, 4, false);
// shapes
C.shape_roundrect = () => new THREE.ShapeGeometry(roundRect(0.6, 0.4, 0.05), 4);
C.shape_roundrect_rot = () => new THREE.ShapeGeometry(roundRect(0.36, 0.26, 0.1 * 0.7), 4).rotateY(Math.PI);
C.shape_holes = () => { const s = roundRect(1, 0.8, 0.1); s.holes.push(new THREE.Path(roundRect(0.6, 0.4, 0.035).getPoints(8))); s.holes.push(new THREE.Path(circlePts(0.05, 10, 0.38, 0.3, true))); return new THREE.ShapeGeometry(s, 6); };
C.shape_rr4 = () => new THREE.ShapeGeometry(rrShape4(0.8, 0.5, [0.05, 0.05, 0.2, 0.2], 0.1, 0.3), 12);
C.shape_array = () => new THREE.ShapeGeometry([roundRect(0.3, 0.2, 0.05), rrShape4(0.4, 0.4, [0.1, 0.02, 0.1, 0.02], 1, 0)], 5);
C.shape_bigcircle = () => new THREE.ShapeGeometry(new THREE.Shape(circlePts(0.5, 120)), 12);
C.shape_bigcircle_hole = () => { const s = new THREE.Shape(circlePts(0.5, 100)); s.holes.push(new THREE.Path(circlePts(0.2, 60, 0.05, 0))); s.holes.push(new THREE.Path(circlePts(0.05, 12, -0.3, 0.1))); return new THREE.ShapeGeometry(s, 12); };
C.shape_gear = () => new THREE.ShapeGeometry(gearShape(), 4);
C.shape_path_mix = () => {
  const s = new THREE.Shape();
  s.moveTo(0, 0); s.lineTo(0.5, 0); s.bezierCurveTo(0.6, 0.1, 0.6, 0.3, 0.5, 0.4); s.quadraticCurveTo(0.25, 0.6, 0, 0.4);
  s.splineThru([V2(-0.1, 0.3), V2(-0.05, 0.15), V2(-0.1, 0.05)]); s.lineTo(0, 0);
  const h = new THREE.Path(); h.absellipse(0.25, 0.2, 0.08, 0.05, 0, TAU, true, 0.3); s.holes.push(h);
  return new THREE.ShapeGeometry(s, 7);
};
C.shape_arc_rel = () => { const s = new THREE.Shape(); s.moveTo(0.1, 0); s.lineTo(0.4, 0); s.arc(0, 0.1, 0.1, -PI / 2, PI / 2, false); s.lineTo(0.1, 0.2); s.ellipse(0, -0.1, 0.1, 0.1, PI / 2, PI * 1.5, false); return new THREE.ShapeGeometry(s, 5); };
C.shape_cw_input = () => new THREE.ShapeGeometry(new THREE.Shape([V2(0, 0), V2(0, 1), V2(1, 1), V2(1, 0)]), 1);
C.shape_selfintersect = () => new THREE.ShapeGeometry(new THREE.Shape([V2(0, 0), V2(1, 1), V2(1, 0), V2(0, 1), V2(0.5, 1.5), V2(-0.2, 0.7)]), 1);
// extrudes
C.extrude_geo = () => G.extrudeShape(roundRect(0.5, 0.3, 0.04), 0.05);
C.extrude_geo_nobevel = () => G.extrudeShape(roundRect(0.5, 0.3, 0.04), 0.05, 0);
C.extrude_kit = () => kitExtrude(roundRect(0.4, 0.8, 0.03), 0.04);
C.extrude_kit_frame = () => { const s = roundRect(0.6, 0.5, 0.03); s.holes.push(new THREE.Path(roundRect(0.6 - 0.08, 0.5 - 0.08, 0.012).getPoints(4))); return kitExtrude(s, 0.03, { bevel: Math.min(0.008, 0.03 * 0.4, 0.04 * 0.35), bevelSeg: 1, curveSeg: 4 }); };
C.extrude_gear = () => { const g = kitExtrude(gearShape(), 0.1, { bevel: 0.012, bevelSeg: 1, curveSeg: 4 }); g.rotateX(-Math.PI / 2); return g; };
C.extrude_nobevel_steps = () => new THREE.ExtrudeGeometry(roundRect(0.3, 0.2, 0.02), { depth: 0.002, bevelEnabled: false, curveSegments: 6, steps: 3 });
C.extrude_penny = () => new THREE.ExtrudeGeometry(roundRect(0.2, 0.3, 0.06), { depth: 0.01, bevelEnabled: true, bevelThickness: 0.01 * 0.35, bevelSize: 0.02 * 0.22, bevelSegments: 2, curveSegments: 40 });
C.extrude_zombie = () => new THREE.ExtrudeGeometry(rrShape4(0.1, 0.06, [0.01, 0.01, 0.03, 0.03]), { depth: 0.016, bevelEnabled: true, bevelThickness: 0.006, bevelSize: 0.006, bevelSegments: 1 });
C.extrude_holes_default = () => { const s = new THREE.Shape(circlePts(0.5, 90)); s.holes.push(new THREE.Path(circlePts(0.2, 30, 0.1, 0))); return new THREE.ExtrudeGeometry(s, { depth: 0.2, bevelThickness: 0.05, bevelSize: 0.03 }); };
C.extrude_path = () => new THREE.ExtrudeGeometry(roundRect(0.1, 0.05, 0.01), { steps: 12, bevelEnabled: false, curveSegments: 3, extrudePath: new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.2, 0.3, 0), V3(0.5, 0.3, 0.2), V3(0.8, 0, 0.1)]) });
C.extrude_multi = () => new THREE.ExtrudeGeometry([roundRect(0.3, 0.2, 0.05), rrShape4(0.2, 0.2, [0.02, 0.02, 0.05, 0.05], 0.5, 0)], { depth: 0.05, bevelEnabled: true, bevelThickness: 0.01, bevelSize: 0.01, bevelSegments: 2, curveSegments: 5 });
C.extrude_dup_ends = () => new THREE.ExtrudeGeometry(new THREE.Shape([V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1), V2(0, 0)]), { depth: 0.3, bevelEnabled: false });
C.extrude_collinear = () => new THREE.ExtrudeGeometry(new THREE.Shape([V2(0, 0), V2(0.5, 0), V2(1, 0), V2(1, 1), V2(0.5, 1.0000000001), V2(0, 1)]), { depth: 0.3, bevelSegments: 2, bevelSize: 0.05, bevelThickness: 0.05 });
C.extrude_mergev = () => mergeVertices(kitExtrude(roundRect(0.3, 0.2, 0.03), 0.02), 1e-5);
// convex hulls
C.convex_cbox_furn = () => new ConvexGeometry(cboxPts(0.2, 0.03, 0.14, 0.004));
C.convex_cbox_out = () => new ConvexGeometry(cboxPts(0.41, 0.12, 0.7, 0.006));
C.convex_cbox_bc = () => new ConvexGeometry(cboxBroadcast(0.05, 0.02, 0.3));
C.convex_cbox_tiny = () => new ConvexGeometry(cboxBroadcast(0.001, 0.5, 0.004, 0.004));
C.convex_random = () => { const r = R.mulberry32(99); const p = []; for (let i = 0; i < 60; i++) p.push(V3(r() - 0.5, r() - 0.5, r() - 0.5)); return new ConvexGeometry(p); };
C.convex_sphere_pts = () => { const s = new THREE.SphereGeometry(0.4, 9, 7); const p = []; const a = s.attributes.position; for (let i = 0; i < a.count; i++) p.push(new THREE.Vector3().fromBufferAttribute(a, i)); return new ConvexGeometry(p); };
C.convex_cbox_uv = () => {
  // furniture.js cbox: UVs from normals/positions after the hull (checks the vertex order)
  const w = 0.3, h = 0.05, d = 0.2;
  const g = new ConvexGeometry(cboxPts(w, h, d, 0.004));
  const p = g.attributes.position, n = g.attributes.normal;
  const uv = new Float32Array(p.count * 2);
  for (let i = 0; i < p.count; i++) {
    const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i)), az = Math.abs(n.getZ(i));
    const x = p.getX(i) / w + 0.5, y = p.getY(i) / h + 0.5, z = p.getZ(i) / d + 0.5;
    let u, v;
    if (az >= ax && az >= ay) { u = n.getZ(i) < 0 ? 1 - x : x; v = y; } else if (ax >= ay) { u = n.getX(i) > 0 ? 1 - z : z; v = y; } else { u = x; v = n.getY(i) > 0 ? 1 - z : z; }
    uv[i * 2] = u; uv[i * 2 + 1] = v;
  }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  return g;
};
// merges
C.merge_indexed = () => mergeGeometries([new THREE.BoxGeometry(1, 1, 1), new THREE.SphereGeometry(0.5, 8, 6).translate(1, 0, 0), new THREE.CylinderGeometry(0.1, 0.1, 1, 6)], false);
C.merge_groups = () => mergeGeometries([new THREE.BoxGeometry(1, 1, 1), new THREE.PlaneGeometry(1, 1).translate(0, 0, 1)], true);
C.merge_nonindexed = () => mergeGeometries([new RoundedBoxGeometry(0.2, 0.3, 0.4, 1, 0.02), new THREE.BoxGeometry(1, 1, 1).toNonIndexed()], true);
C.merge_fail_mixed = () => mergeGeometries([new THREE.BoxGeometry(1, 1, 1), new RoundedBoxGeometry(0.2, 0.3, 0.4, 1, 0.02)], false);
C.merge_fail_attrs = () => mergeGeometries([G.withAO(new THREE.BoxGeometry(1, 1, 1)), new THREE.BoxGeometry(1, 1, 1)], false);
C.merge_colors = () => mergeGeometries([G.withAO(new THREE.BoxGeometry(1, 1, 1)), G.withAO(new THREE.SphereGeometry(0.4, 6, 4), { strength: 0.8, tint: '#102030' })], false);
C.merge_then_mergev = () => mergeVertices(mergeGeometries([new THREE.PlaneGeometry(1, 1), new THREE.PlaneGeometry(1, 1).translate(1, 0, 0)], false), 1e-4);
// geo.js helpers
C.geo_roundedBox = () => G.roundedBox(0.4, 0.3, 0.2);
C.geo_roundedBox2 = () => G.roundedBox(1.23456, 0.3, 0.2, 0.012, 2);
C.geo_box = () => G.box(0.1, 0.2, 0.3);
C.geo_capsule = () => G.capsule(0.05, 0.2);
C.geo_cylinder = () => G.cylinder(0.1, 0.12, 0.3);
C.geo_sphere = () => G.sphere(0.3);
C.geo_torus = () => G.torus(0.3, 0.05);
C.geo_torus_arc = () => G.torus(0.3, 0.05, 6, 16, Math.PI);
C.geo_plane = () => G.plane(2, 1, 2, 3);
C.geo_lathe = () => G.lathe([[0, 0], [0.2, 0], [0.25, 0.1], [0.1, 0.3], [0, 0.3]]);
C.geo_lathe_v2 = () => G.lathe([V2(0.1, 0), V2(0.2, 0.1)], 12);
C.geo_tube = () => G.tube([[0, 0, 0], [0.1, 0.2, 0], [0.3, 0.3, 0.1]], 0.02);
C.geo_tube_closed = () => G.tube([V3(0, 0, 0), V3(0.1, 0.2, 0), V3(0.3, 0.3, 0.1), V3(0.2, 0, 0.1)], 0.015, 30, 6, true);
C.geo_ao_default = () => G.withAO(G.cylinder(0.1, 0.12, 0.3));
C.geo_ao_opts = () => G.withAO(G.roundedBox(0.4, 0.3, 0.2), { y0: -0.05, y1: 0.1, strength: 0.6, tint: '#102040' });
C.geo_ao_flat = () => G.withAO(G.plane(1, 1));

for (const k in C) {
  const g = C[k]();
  results[k] = g ? geo(g) : { kind: 'geo', none: true };
}


// ------------------------------------------------------------------------------------------ FUZZ (seeded, mirrored in python)
{
  const r = R.mulberry32(20240928);
  const F = (a, b) => a + (b - a) * r();
  const I = (a, b) => a + Math.floor(r() * (b - a + 1));
  const ops = (g) => {
    const n = I(0, 3);
    for (let k = 0; k < n; k++) {
      const o = I(0, 7);
      if (o === 0) g.rotateX(F(-3, 3)); else if (o === 1) g.rotateY(F(-3, 3)); else if (o === 2) g.rotateZ(F(-3, 3));
      else if (o === 3) g.translate(F(-1, 1), F(-1, 1), F(-1, 1)); else if (o === 4) g.scale(F(-2, 2), F(0.1, 2), F(0.5, 1.5));
      else if (o === 5) g.computeVertexNormals(); else if (o === 6) g = g.index ? g.toNonIndexed() : g;
      else g = mergeVertices(g, [1e-4, 1e-5, 1e-3][I(0, 2)]);
    }
    return g;
  };
  for (let i = 0; i < 30; i++) results[`fuzz_rbox_${i}`] = geo(ops(new RoundedBoxGeometry(F(0.005, 1.5), F(0.005, 1.5), F(0.005, 1.5), I(0, 3), F(0, 0.12))));
  for (let i = 0; i < 25; i++) {
    const n = I(2, 7); const pts = []; let y = F(-0.2, 0.2);
    for (let k = 0; k < n; k++) { pts.push(V2((k === 0 || k === n - 1) && r() < 0.5 ? 0 : F(0, 0.5), y)); y += F(0, 0.3); }
    results[`fuzz_lathe_${i}`] = geo(ops(new THREE.LatheGeometry(pts, I(3, 32), r() < 0.3 ? F(0, 3) : 0, r() < 0.3 ? F(0.5, 7) : TAU)));
  }
  for (let i = 0; i < 25; i++) {
    const n = I(2, 6); const pts = [];
    for (let k = 0; k < n; k++) pts.push(V3(F(-1, 1), F(-1, 1), F(-1, 1)));
    const closed = r() < 0.3; const type = ['centripetal', 'chordal', 'catmullrom'][I(0, 2)];
    results[`fuzz_tube_${i}`] = geo(ops(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts, closed, type, F(0, 1)), I(2, 40), F(0.001, 0.1), I(3, 10), closed)));
  }
  for (let i = 0; i < 30; i++) {
    const w = F(0.05, 1), h = F(0.05, 1);
    const s = roundRect(w, h, F(0, 0.3));
    if (r() < 0.5) s.holes.push(new THREE.Path(roundRect(w * 0.5, h * 0.5, F(0, 0.1)).getPoints(I(1, 8))));
    if (r() < 0.2) s.holes.push(new THREE.Path(circlePts(Math.min(w, h) * 0.1, I(3, 20), w * 0.35, h * 0.35, r() < 0.5)));
    const bev = r() < 0.7;
    const t = F(0.001, 0.05);
    const o = { depth: F(0.001, 0.3), bevelEnabled: bev, bevelThickness: t, bevelSize: F(0.001, 0.02), bevelOffset: r() < 0.3 ? -F(0, 0.01) : 0, bevelSegments: I(1, 4), curveSegments: I(1, 16), steps: I(1, 3) };
    results[`fuzz_extrude_${i}`] = geo(ops(new THREE.ExtrudeGeometry(s, o)));
  }
  for (let i = 0; i < 20; i++) {
    const s = roundRect(F(0.05, 1), F(0.05, 1), F(0, 0.3));
    results[`fuzz_shape_${i}`] = geo(ops(new THREE.ShapeGeometry(s, I(1, 20))));
  }
  for (let i = 0; i < 20; i++) results[`fuzz_cyl_${i}`] = geo(ops(new THREE.CylinderGeometry(r() < 0.2 ? 0 : F(0, 1), r() < 0.2 ? 0 : F(0, 1), F(0.01, 2), I(3, 32), I(1, 4), r() < 0.2, r() < 0.3 ? F(0, 6) : 0, r() < 0.3 ? F(0.1, 6.28) : TAU)));
  for (let i = 0; i < 20; i++) results[`fuzz_sphere_${i}`] = geo(ops(new THREE.SphereGeometry(F(0.01, 1), I(3, 32), I(2, 20), r() < 0.3 ? F(0, 6) : 0, r() < 0.3 ? F(0.1, 6.28) : TAU, r() < 0.3 ? F(0, 3) : 0, r() < 0.3 ? F(0.1, 3.14) : PI)));
  for (let i = 0; i < 15; i++) results[`fuzz_torus_${i}`] = geo(ops(new THREE.TorusGeometry(F(0.05, 1), F(0.005, 0.2), I(3, 16), I(3, 48), r() < 0.4 ? F(0.1, 6.28) : TAU)));
  for (let i = 0; i < 15; i++) results[`fuzz_capsule_${i}`] = geo(ops(new THREE.CapsuleGeometry(F(0.01, 0.5), F(0, 1), I(1, 8), I(3, 16), I(1, 3))));
  for (let i = 0; i < 15; i++) results[`fuzz_convex_${i}`] = geo(new ConvexGeometry(cboxPts(F(0.002, 1), F(0.002, 1), F(0.002, 1), F(0.001, 0.02))));
  for (let i = 0; i < 10; i++) results[`fuzz_ico_${i}`] = geo(ops(new THREE.IcosahedronGeometry(F(0.1, 1), I(0, 3))));
  for (let i = 0; i < 10; i++) results[`fuzz_geo_ao_${i}`] = geo(G.withAO(G.roundedBox(F(0.05, 1), F(0.05, 1), F(0.05, 1), F(0.005, 0.05), I(1, 3)), r() < 0.5 ? {} : { y0: F(-0.5, 0), y1: F(0, 0.5), strength: F(0, 1) }));
}

// ------------------------------------------------------------------------------------------ VALUE cases (curves, earcut, math, rng, color)
const V = {};
const cr = new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.1, 0.3, 0), V3(0.3, 0.35, 0.1), V3(0.5, 0.2, -0.1)]);
V.curve_cr_points = vecs(cr.getPoints(10));
V.curve_cr_spaced = vecs(cr.getSpacedPoints(10));
V.curve_cr_len = cr.getLength();
V.curve_cr_u2t = [0, 0.1, 0.33, 0.5, 0.77, 1].map((u) => cr.getUtoTmapping(u));
V.curve_cr_tan = [0, 0.25, 0.5, 1].map((u) => vec(cr.getTangentAt(u)));
V.curve_cr_tan_t = [0, 0.25, 0.5, 1].map((t) => vec(cr.getTangent(t)));
V.curve_cr_frames = (() => { const f = cr.computeFrenetFrames(8, false); return { t: vecs(f.tangents), n: vecs(f.normals), b: vecs(f.binormals) }; })();
V.curve_cr_frames_closed = (() => { const c = new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(1, 0, 0), V3(1, 1, 0.3), V3(0, 1, 0)], true); const f = c.computeFrenetFrames(12, true); return { t: vecs(f.tangents), n: vecs(f.normals), b: vecs(f.binormals) }; })();
V.curve_cr_closed_pts = vecs(new THREE.CatmullRomCurve3([V3(0, 0, 0), V3(1, 0, 0), V3(1, 1, 0.3), V3(0, 1, 0)], true).getPoints(9));
const bz = new THREE.CubicBezierCurve3(V3(0, 0, 0), V3(0, 1, 0), V3(1, 1, 0), V3(1, 0, 0.5));
V.curve_bz3 = { pts: vecs(bz.getPoints(7)), at: [0.1, 0.6].map((u) => vec(bz.getPointAt(u))), tan: vec(bz.getTangent(0.3)), len: bz.getLength() };
const qb3 = new THREE.QuadraticBezierCurve3(V3(0, 0, 0), V3(0, 1, 0), V3(1, 1, 0));
V.curve_qb3 = { pts: vecs(qb3.getPoints(5)), len: qb3.getLength() };
const ln3 = new THREE.LineCurve3(V3(0, 0, 0), V3(1, 2, 3));
V.curve_line3 = { pts: vecs(ln3.getPoints(4)), sp: vecs(ln3.getSpacedPoints(3)), len: ln3.getLength(), tan: vec(ln3.getTangentAt(0.5)) };
const el = new THREE.EllipseCurve(0.1, 0.2, 0.5, 0.3, 0.3, 2.5, true, 0.4);
V.curve_ellipse_cw = vecs(el.getPoints(8));
V.curve_ellipse_full = vecs(new THREE.EllipseCurve(0, 0, 1, 1, 0, TAU, false, 0).getPoints(6));
V.curve_ellipse_same = vecs(new THREE.EllipseCurve(0, 0, 1, 1, 1, 1, true, 0).getPoints(3));
V.curve_ellipse_neg = vecs(new THREE.EllipseCurve(0, 0, 1, 2, 5, -3, false, 0).getPoints(5));
V.curve_arc = vecs(new THREE.ArcCurve(0, 0, 2, 0, PI, true).getPoints(4));
V.curve_spline2 = vecs(new THREE.SplineCurve([V2(0, 0), V2(1, 1), V2(2, 0), V2(3, 1)]).getPoints(9));
const path = new THREE.Path(); path.moveTo(0, 0); path.lineTo(1, 0); path.quadraticCurveTo(1.5, 0.5, 1, 1); path.bezierCurveTo(0.7, 1.2, 0.3, 1.2, 0, 1); path.absarc(0, 0.5, 0.5, PI / 2, PI * 1.5, false);
V.path_points = vecs(path.getPoints());
V.path_points5 = vecs(path.getPoints(5));
V.path_spaced = vecs(path.getSpacedPoints(20));
V.path_len = path.getLength();
V.path_curvelens = path.getCurveLengths();
const path2 = new THREE.Path([V2(0, 0), V2(1, 0), V2(1, 1)]); path2.closePath(); path2.autoClose = true;
V.path_autoclose = { pts: vecs(path2.getPoints()), sp: vecs(path2.getSpacedPoints(6)) };
V.shape_extract = (() => { const s = roundRect(0.5, 0.4, 0.05); s.holes.push(new THREE.Path(circlePts(0.1, 8))); const e = s.extractPoints(6); return { shape: vecs(e.shape), holes: e.holes.map(vecs) }; })();
V.shapeutils = (() => { const pts = circlePts(1, 7); return { area: THREE.ShapeUtils.area(pts), cw: THREE.ShapeUtils.isClockWise(pts), tri: THREE.ShapeUtils.triangulateShape(circlePts(1, 7), [circlePts(0.3, 5, 0, 0, true)]) }; })();
V.earcut_square = THREE.ShapeUtils.triangulateShape([V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)], []);
V.earcut_raw_holes = (() => { const d = [0, 0, 10, 0, 10, 10, 0, 10, 2, 2, 4, 2, 4, 4, 2, 4, 6, 6, 8, 6, 8, 8, 6, 8]; return THREE.ShapeUtils.triangulateShape([0, 1, 2, 3].map((i) => V2(d[i * 2], d[i * 2 + 1])), [[4, 7, 6, 5].map((i) => V2(d[i * 2], d[i * 2 + 1])), [8, 11, 10, 9].map((i) => V2(d[i * 2], d[i * 2 + 1]))]); })();
V.earcut_hashed = (() => { const p = []; const r = R.mulberry32(5); for (let i = 0; i < 150; i++) { const a = (i / 150) * TAU; const rr = 1 + 0.3 * r(); p.push(V2(Math.cos(a) * rr, Math.sin(a) * rr)); } return THREE.ShapeUtils.triangulateShape(p, [circlePts(0.3, 40, 0.1, 0.1, true), circlePts(0.2, 12, -0.5, 0, true)]); })();
V.earcut_collinear_hole_touch = THREE.ShapeUtils.triangulateShape([V2(0, 0), V2(4, 0), V2(4, 4), V2(0, 4)], [[V2(0, 1), V2(1, 2), V2(1, 1)].reverse(), [V2(2, 2), V2(3, 2), V2(3, 3), V2(2, 3)].reverse(), [V2(2, 2), V2(2, 1), V2(3, 1)]]);
// math
const e = new THREE.Euler(0.3, -1.2, 2.1);
const orders = ['XYZ', 'YXZ', 'ZXY', 'ZYX', 'YZX', 'XZY'];
V.m4_euler = orders.map((o) => new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(0.3, -1.2, 2.1, o)).elements);
V.q_euler = orders.map((o) => new THREE.Quaternion().setFromEuler(new THREE.Euler(0.3, -1.2, 2.1, o)).toArray());
V.euler_from_q = orders.map((o) => { const eu = new THREE.Euler().setFromQuaternion(new THREE.Quaternion(0.1, 0.7, -0.3, 0.64).normalize(), o); return [eu.x, eu.y, eu.z]; });
V.euler_gimbal = orders.map((o) => { const eu = new THREE.Euler().setFromRotationMatrix(new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(PI / 2, PI / 2, 0.3, o)), o); return [eu.x, eu.y, eu.z]; });
V.m4_compose = new THREE.Matrix4().compose(V3(1, 2, 3), new THREE.Quaternion().setFromEuler(e), V3(1, -2, 0.5)).elements;
V.m4_decompose = (() => { const p = V3(), q = new THREE.Quaternion(), s = V3(); new THREE.Matrix4().compose(V3(1, 2, 3), new THREE.Quaternion().setFromEuler(e), V3(1, -2, 0.5)).decompose(p, q, s); return [p.toArray(), q.toArray(), s.toArray()]; })();
V.m4_invert = new THREE.Matrix4().compose(V3(1, 2, 3), new THREE.Quaternion().setFromEuler(e), V3(1, -2, 0.5)).invert().elements;
V.m4_det = new THREE.Matrix4().compose(V3(1, 2, 3), new THREE.Quaternion().setFromEuler(e), V3(1, -2, 0.5)).determinant();
V.m4_lookat = [new THREE.Matrix4().lookAt(V3(1, 2, 3), V3(0, 0, 0), V3(0, 1, 0)).elements, new THREE.Matrix4().lookAt(V3(0, 5, 0), V3(0, 0, 0), V3(0, 1, 0)).elements];
V.m4_axis = new THREE.Matrix4().makeRotationAxis(V3(1, 2, 3).normalize(), 0.7).elements;
V.m4_mul = new THREE.Matrix4().makeRotationX(0.3).multiply(new THREE.Matrix4().makeTranslation(1, 2, 3)).premultiply(new THREE.Matrix4().makeScale(2, 3, 4)).elements;
V.m3_normal = new THREE.Matrix3().getNormalMatrix(new THREE.Matrix4().compose(V3(1, 2, 3), new THREE.Quaternion().setFromEuler(e), V3(1, -2, 0.5))).elements;
V.q_unit = [new THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), V3(1, 2, 3).normalize()).toArray(), new THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), V3(0, -1, 0)).toArray(), new THREE.Quaternion().setFromUnitVectors(V3(1, 0, 0), V3(-1, 0, 0)).toArray()];
V.q_slerp = [0, 0.3, 1].map((t) => new THREE.Quaternion().setFromEuler(e).slerp(new THREE.Quaternion(0, 0, 0.6, 0.8), t).toArray());
V.q_slerp_close = new THREE.Quaternion(0, 0, 0.6, 0.8).slerp(new THREE.Quaternion(0, 0.0001, 0.6, 0.8).normalize(), 0.5).toArray();
V.q_axis = new THREE.Quaternion().setFromAxisAngle(V3(0, 1, 0), 1.3).multiply(new THREE.Quaternion().setFromAxisAngle(V3(1, 0, 0), -0.4)).toArray();
V.q_from_m = new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(3, 0.1, -3))).toArray();
V.v3_ops = (() => { const a = V3(1, 2, 3), b = V3(-0.5, 0.2, 4); return [a.clone().cross(b).toArray(), a.angleTo(b), a.clone().applyEuler(e).toArray(), a.clone().applyAxisAngle(V3(0, 0, 1), 0.5).toArray(), a.clone().lerp(b, 0.3).toArray(), a.clone().projectOnVector(b).toArray(), a.clone().reflect(V3(0, 1, 0)).toArray(), a.clone().setLength(2).toArray(), a.clone().transformDirection(new THREE.Matrix4().makeRotationY(1)).toArray(), a.distanceTo(b), a.clone().applyMatrix4(new THREE.Matrix4().makePerspective(-1, 1, 1, -1, 0.1, 100)).toArray()]; })();
V.v2_ops = (() => { const a = V2(1, 2), b = V2(-0.5, 0.2); return [a.angle(), a.clone().rotateAround(b, 0.8).toArray(), a.cross(b), a.clone().normalize().toArray(), a.angleTo(b)]; })();
V.box3 = (() => { const b = new THREE.Box3().setFromPoints([V3(1, 2, 3), V3(-1, 0.5, 2), V3(0, -3, 1)]); const c = b.clone().applyMatrix4(new THREE.Matrix4().makeRotationFromEuler(e)); return [b.min.toArray(), b.max.toArray(), b.getCenter(V3()).toArray(), b.getSize(V3()).toArray(), c.min.toArray(), c.max.toArray()]; })();
V.mathutils = [THREE.MathUtils.clamp(5, 0, 1), THREE.MathUtils.lerp(2, 5, 0.3), THREE.MathUtils.smoothstep(0.3, 0.1, 0.9), THREE.MathUtils.smoothstep(-1, 0, 1), THREE.MathUtils.damp(1, 5, 3, 0.016), THREE.MathUtils.degToRad(33), THREE.MathUtils.radToDeg(1.1), THREE.MathUtils.euclideanModulo(-7.5, 3), THREE.MathUtils.mapLinear(3, 0, 10, -1, 1), THREE.MathUtils.pingpong(3.7, 2), THREE.MathUtils.smootherstep(0.4, 0, 1), THREE.MathUtils.inverseLerp(2, 6, 3), THREE.MathUtils.ceilPowerOfTwo(300), THREE.MathUtils.floorPowerOfTwo(300), THREE.MathUtils.isPowerOfTwo(256), THREE.MathUtils.isPowerOfTwo(300), THREE.MathUtils.seededRandom(77), THREE.MathUtils.seededRandom(), THREE.MathUtils.seededRandom()];
// color
const COLS = ['#3A2A5A', '#FF2A1E', '#F6F1FF', '#2E2836', '#150F1C', '#000000', '#FFFFFF', '#010203', '#7FE7FF', '#abc', 'white', 'Crimson', 'rgb(10, 200, 30)', 'rgb(10%, 50%, 100%)', 'hsl(200, 40%, 60%)', 'hsla(30, 100%, 50%, 1)'];
V.color_parse = COLS.map((s) => { const c = new THREE.Color(s); return [c.r, c.g, c.b, c.getHex(), c.getHexString(), c.getStyle()]; });
V.color_ops = (() => {
  const c = new THREE.Color('#3A2A5A');
  const hsl = {}; c.getHSL(hsl);
  const shade = (hex, amt) => { const k = new THREE.Color(hex); if (amt >= 0) k.lerp(new THREE.Color(1, 1, 1), amt); else k.multiplyScalar(1 + amt); return '#' + k.getHexString(); };
  return [[hsl.h, hsl.s, hsl.l], new THREE.Color().setHSL(0.3, 0.6, 0.4).toArray(), new THREE.Color('#E8A92E').offsetHSL(0.05, -0.1, 0.1).toArray(),
    new THREE.Color(0x2F5BD3).toArray(), new THREE.Color(1, 0.5, 0.25).getHexString(), new THREE.Color(3, 3, 3).getHex(), new THREE.Color('#FF7A2E').lerpHSL(new THREE.Color('#1E5BFF'), 0.4).toArray(),
    shade('#7A4A2A', 0.3), shade('#7A4A2A', -0.4), shade('#F4F1E8', 0.12), new THREE.Color('#8C9A3A').convertLinearToSRGB().toArray(), new THREE.Color().setRGB(0.5, 0.5, 0.5, 'srgb').toArray(), new THREE.Color('#123456').getStyle()];
})();
// rng
V.rng_mulberry = [0, 1, 42, 123456789, 4294967295, -5, 3.7, 2 ** 40 + 7, 0x6D2B79F5].map((s) => { const r = R.mulberry32(s); return Array.from({ length: 12 }, () => r()); });
const HS = ['', 'a', 'rbox|0.4|0.3', 'tex:crt|512|256', 'Ümlaut ñ 日本', '\u{1F600}emoji', 'wood_grain|walnut|0.35'];
V.rng_hashstr = HS.map((s) => { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619); return h >>> 0; });
V.rng_seeded = HS.map((s) => { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619); const r = R.mulberry32(h >>> 0); return [r(), r(), r()]; });
V.rng_helpers = (() => { const r = R.mulberry32(1234); return [R.range(2, 5, r), R.rangeInt(1, 6, r), R.pick(['a', 'b', 'c', 'd'], r), R.chance(0.5, r), R.shuffle([1, 2, 3, 4, 5, 6, 7], r), R.weighted({ b: 1, a: 3, 10: 2, 2: 1 }, r), R.weighted({ x: 0 }, r), R.hash1(3.3), R.noise1(7.25), R.noise1(-2.7)]; })();
// JS formatting (cache keys)
V.js_str = [0.1 + 0.2, 1 / 3, 1e-7, 5e-7, 123456789.123, 1e21, 1.5e21, -0.0, 100, 2.5e-6, 0.000001, 1234.5678e10].map((x) => `${x}`);
V.js_json = JSON.stringify([[0, 0], [0.2, 0.1], [1 / 3, -0.0], [1e-7, 1e21]]);
V.js_fixed = [[0.125, 2], [1.005, 2], [-0.001, 2], [2.5, 0], [-2.5, 0], [1234.5678, 4], [0.1 + 0.2, 10], [1e-10, 3]].map(([x, d]) => x.toFixed(d));
V.js_round = [2.5, -2.5, 0.49999999999999994, -0.5, 1.4999999999999998, 123.5, -123.5].map((x) => Math.round(x));
// config
V.config = { PAL, T, LAYERS };

for (const k in V) results[k] = { kind: 'value', value: V[k] };

// ------------------------------------------------------------------------------------------ write
writeFileSync(out, JSON.stringify(results));
console.log(`wrote ${Object.keys(results).length - 1} cases to ${out}`);
