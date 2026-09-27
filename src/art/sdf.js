// SDF sculpting DSL ("digital clay") shared by the Node baker (tools/bake/bake.mjs) and the browser.
// See docs/CHARKIT.md for the full reference. Summary:
//
//   const sd = createSculptor({ joints, materials, expr });   // joints: name -> { matrix (bind-pose world Matrix4) }
//   sd.ellipsoid({ pos, r:[rx,ry,rz], rot, mat, bone, k, op, color, noise, pframe, ... })
//   sd.sphere / box / capsule / roundCone / torus / arc / cylinder / cone / worm / plane / custom
//   sd.group({ k, op, mat, bone, pframe, name }, () => { ...children... })
//   sd.mirrorX(() => {...})         run the body twice, the second time mirrored across x=0 with L<->R bones
//   sd.bone('elbowL', () => {...})  coordinates relative to that joint's bind-pose frame, default binding = its chain
//   sd.frame({ pos, rot, scale }, () => {...})
//   sd.paint(shapeFn, { mat, color, soft, strength })   recolor/re-material the surface inside a shape
//   sd.stitch(points, { width, dash, color, mats })      shader line feature (stitching / seams) in rest space
//   sd.patternFrame({ pos, axis, ref, mode:'cyl'|'tri', radius })
//
// Ops: op 'add' (smooth union, k = blend radius in m), 'sub' (smooth subtract), 'int' (smooth intersect),
// 'paint' (attributes only). Any node takes offset (inflate, m) and shell (onion thickness, m).
// Units are meters; the character stands with feet at y=0, facing -z, in the BIND pose (A-pose arms).
// Evaluation is plain JS (no allocations in the hot path): node.fn(x,y,z) -> distance. sampleAttr() for materials.

import * as THREE from 'three';

// ---------------------------------------------------------------------------------------------------------------
// Noise (improved Perlin, deterministic)
const PERM = new Uint8Array(512);
(() => {
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;
  let s = 1337;
  for (let i = 255; i > 0; i--) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    const j = s % (i + 1);
    const t = p[i]; p[i] = p[j]; p[j] = t;
  }
  for (let i = 0; i < 512; i++) PERM[i] = p[i & 255];
})();
const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
function grad(h, x, y, z) {
  const u = (h & 15) < 8 ? x : y;
  const v = (h & 15) < 4 ? y : ((h & 15) === 12 || (h & 15) === 14 ? x : z);
  return ((h & 1) === 0 ? u : -u) + ((h & 2) === 0 ? v : -v);
}
export function noise3(x, y, z) {
  const X = Math.floor(x), Y = Math.floor(y), Z = Math.floor(z);
  x -= X; y -= Y; z -= Z;
  const xi = X & 255, yi = Y & 255, zi = Z & 255;
  const u = fade(x), v = fade(y), w = fade(z);
  const A = PERM[xi] + yi, AA = PERM[A] + zi, AB = PERM[A + 1] + zi;
  const B = PERM[xi + 1] + yi, BA = PERM[B] + zi, BB = PERM[B + 1] + zi;
  const l = (a, b, t) => a + (b - a) * t;
  return l(
    l(l(grad(PERM[AA], x, y, z), grad(PERM[BA], x - 1, y, z), u), l(grad(PERM[AB], x, y - 1, z), grad(PERM[BB], x - 1, y - 1, z), u), v),
    l(l(grad(PERM[AA + 1], x, y, z - 1), grad(PERM[BA + 1], x - 1, y, z - 1), u), l(grad(PERM[AB + 1], x, y - 1, z - 1), grad(PERM[BB + 1], x - 1, y - 1, z - 1), u), v),
    w);
}
export function fbm3(x, y, z, oct = 3) {
  let a = 0, amp = 0.5, f = 1;
  for (let i = 0; i < oct; i++) { a += amp * noise3(x * f, y * f, z * f); f *= 2.03; amp *= 0.5; }
  return a;
}

// ---------------------------------------------------------------------------------------------------------------
// Smooth operators (quadratic polynomial smin; k in meters)
export function smin(a, b, k) {
  if (k <= 0) return a < b ? a : b;
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return (a < b ? a : b) - h * h * k * 0.25;
}
const ssub = (a, b, k) => -smin(-a, b, k);
const sint = (a, b, k) => -smin(-a, -b, k);
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const smoothstep = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };

// ---------------------------------------------------------------------------------------------------------------
// Primitive distance functions in local space.
function sdEllipsoid(x, y, z, rx, ry, rz) {
  const k0 = Math.sqrt((x / rx) ** 2 + (y / ry) ** 2 + (z / rz) ** 2);
  if (k0 < 1e-9) return -Math.min(rx, ry, rz);
  const k1 = Math.sqrt((x / (rx * rx)) ** 2 + (y / (ry * ry)) ** 2 + (z / (rz * rz)) ** 2);
  return (k0 * (k0 - 1)) / k1;
}
function sdBox(x, y, z, bx, by, bz, r) {
  const qx = Math.abs(x) - bx + r, qy = Math.abs(y) - by + r, qz = Math.abs(z) - bz + r;
  const ox = Math.max(qx, 0), oy = Math.max(qy, 0), oz = Math.max(qz, 0);
  return Math.sqrt(ox * ox + oy * oy + oz * oz) + Math.min(Math.max(qx, qy, qz), 0) - r;
}
function sdCapsule(x, y, z, ax, ay, az, bx, by, bz, r) {
  const pax = x - ax, pay = y - ay, paz = z - az, bax = bx - ax, bay = by - ay, baz = bz - az;
  const h = clamp01((pax * bax + pay * bay + paz * baz) / (bax * bax + bay * bay + baz * baz || 1e-12));
  const dx = pax - bax * h, dy = pay - bay * h, dz = paz - baz * h;
  return Math.sqrt(dx * dx + dy * dy + dz * dz) - r;
}
// IQ round cone between arbitrary points (requires |r1-r2| < |b-a|).
function sdRoundCone(x, y, z, ax, ay, az, bx, by, bz, r1, r2) {
  const bax = bx - ax, bay = by - ay, baz = bz - az;
  const l2 = bax * bax + bay * bay + baz * baz;
  const rr = r1 - r2;
  if (l2 < 1e-12 || rr * rr >= l2) {
    // Degenerate: one sphere contains the other.
    const d1 = Math.hypot(x - ax, y - ay, z - az) - r1, d2 = Math.hypot(x - bx, y - by, z - bz) - r2;
    return Math.min(d1, d2);
  }
  const a2 = l2 - rr * rr, il2 = 1 / l2;
  const pax = x - ax, pay = y - ay, paz = z - az;
  const yy = pax * bax + pay * bay + paz * baz;
  const zz = yy - l2;
  const qx = pax * l2 - bax * yy, qy = pay * l2 - bay * yy, qz = paz * l2 - baz * yy;
  const x2 = qx * qx + qy * qy + qz * qz;
  const y2 = yy * yy * l2, z2 = zz * zz * l2;
  const k = Math.sign(rr) * rr * rr * x2;
  if (Math.sign(zz) * a2 * z2 > k) return Math.sqrt(x2 + z2) * il2 - r2;
  if (Math.sign(yy) * a2 * y2 < k) return Math.sqrt(x2 + y2) * il2 - r1;
  return (Math.sqrt(x2 * a2 * il2) + yy * rr) * il2 - r1;
}
function sdTorus(x, y, z, R, r) {
  const qx = Math.sqrt(x * x + z * z) - R;
  return Math.sqrt(qx * qx + y * y) - r;
}
// Arc of a torus in the XZ plane, centered on +z, half-angle `ha`.
function sdArc(x, y, z, sa, ca, R, r) {
  const px = Math.abs(x);
  const k = ca * px > sa * z ? px * sa + z * ca : Math.sqrt(px * px + z * z);
  return Math.sqrt(Math.max(px * px + y * y + z * z + R * R - 2 * R * k, 0)) - r;
}
function sdCylinder(x, y, z, r, h, rr) {
  const dx = Math.sqrt(x * x + z * z) - r + rr, dy = Math.abs(y) - h + rr;
  const ox = Math.max(dx, 0), oy = Math.max(dy, 0);
  return Math.min(Math.max(dx, dy), 0) + Math.sqrt(ox * ox + oy * oy) - rr;
}
function sdCappedCone(x, y, z, h, r1, r2) {
  const qx = Math.sqrt(x * x + z * z), qy = y;
  const k1x = r2, k1y = h, k2x = r2 - r1, k2y = 2 * h;
  const cax = qx - Math.min(qx, qy < 0 ? r1 : r2), cay = Math.abs(qy) - h;
  const t = clamp01(((k1x - qx) * k2x + (k1y - qy) * k2y) / (k2x * k2x + k2y * k2y));
  const cbx = qx - k1x + k2x * t, cby = qy - k1y + k2y * t;
  const s = cbx < 0 && cay < 0 ? -1 : 1;
  return s * Math.sqrt(Math.min(cax * cax + cay * cay, cbx * cbx + cby * cby));
}

// ---------------------------------------------------------------------------------------------------------------
// Catmull-Rom helpers for worms
function catmull(pts, t) {
  const n = pts.length - 1;
  const f = Math.min(n - 1e-9, Math.max(0, t * n));
  const i = Math.floor(f), u = f - i;
  const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(n, i + 2)];
  const out = [0, 0, 0];
  for (let c = 0; c < 3; c++) {
    const a = p1[c], b = p2[c];
    const m1 = (p2[c] - p0[c]) * 0.5, m2 = (p3[c] - p1[c]) * 0.5;
    const u2 = u * u, u3 = u2 * u;
    out[c] = (2 * u3 - 3 * u2 + 1) * a + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * b + (u3 - u2) * m2;
  }
  return out;
}
function interpProfile(r, t) {
  if (typeof r === 'number') return r;
  if (typeof r === 'function') return r(t);
  const n = r.length - 1;
  if (n <= 0) return r[0];
  const f = Math.min(n, Math.max(0, t * n));
  const i = Math.min(n - 1, Math.floor(f)), u = f - i;
  const s = u * u * (3 - 2 * u);
  return r[i] + (r[i + 1] - r[i]) * s;
}

// ---------------------------------------------------------------------------------------------------------------
const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler();
const _v = new THREE.Vector3();
const _s = new THREE.Vector3();
const MIRROR = new THREE.Matrix4().makeScale(-1, 1, 1);

function toMatrix(o = {}) {
  const m = new THREE.Matrix4();
  const pos = o.pos || [0, 0, 0];
  if (o.quat) _q.set(o.quat[0], o.quat[1], o.quat[2], o.quat[3]);
  else if (o.rot) _q.setFromEuler(_e.set(o.rot[0] || 0, o.rot[1] || 0, o.rot[2] || 0, o.order || 'XYZ'));
  else _q.identity();
  const s = o.scale || 1;   // number, or [sx, sy, sz] for a mild non-uniform squash (distance ~ cbrt(det) corrected)
  if (Array.isArray(s)) _s.set(s[0], s[1], s[2]); else _s.set(s, s, s);
  m.compose(_v.set(pos[0], pos[1], pos[2]), _q, _s);
  return m;
}

export const SWAP_LR = (name) => (typeof name === 'string' ? name.replace(/L$/, '\u0001').replace(/R$/, 'L').replace('\u0001', 'R') : name);

// Default humanoid chains used for bone binding (see CHARKIT.md "Skinning").
export const CHAINS = {
  torso: ['hips', 'spine', 'chest', 'neck'],
  head: ['head'],
  armL: ['shoulderL', 'elbowL', 'handL'],
  armR: ['shoulderR', 'elbowR', 'handR'],
  legL: ['hipL', 'kneeL', 'footL'],
  legR: ['hipR', 'kneeR', 'footR'],
};

let _uid = 0;

export function createSculptor(opts = {}) {
  const joints = opts.joints || {};
  const matNames = opts.materials ? Object.keys(opts.materials) : [];
  const matIndex = (name) => {
    if (name == null) return -1;
    if (typeof name === 'number') return name;
    const i = matNames.indexOf(name);
    if (i < 0) throw new Error(`sdf: unknown material '${name}'`);
    return i;
  };
  const chainOf = opts.chainOf || ((joint) => {
    for (const [c, list] of Object.entries(CHAINS)) if (list.includes(joint)) return c;
    return joint;
  });

  const root = { kind: 'group', children: [], k: 0, op: 'add', name: 'root', id: _uid++ };
  const stitches = [];
  const frames = [{ id: 0, mode: 'tri', matrix: new THREE.Matrix4(), inv: new THREE.Matrix4() }];
  let scope = { matrix: new THREE.Matrix4(), mirrored: false, bone: 'auto', mat: null, pframe: 0, group: root, k: 0, color: null };
  const push = (patch, fn) => {
    const prev = scope;
    scope = { ...scope, ...patch };
    try { fn(); } finally { scope = prev; }
  };

  function place(o) {
    // Leaf local->world matrix = scope * T R S(o)
    const W = scope.matrix.clone().multiply(toMatrix(o));
    return W;
  }

  function resolveBone(b) {
    if (b == null) return scope.bone;
    if (Array.isArray(b)) return b.map((x) => (scope.mirrored ? SWAP_LR(x) : x));
    return scope.mirrored ? SWAP_LR(b) : b;
  }

  function finalizeLeaf(leaf, o) {
    leaf.id = _uid++;
    leaf.kind = 'leaf';
    leaf.name = o.name || leaf.type;
    leaf.mat = matIndex(o.mat ?? scope.mat);
    leaf.bone = resolveBone(o.bone);
    leaf.color = o.color ?? scope.color ?? null;
    leaf.color2 = o.color2 ?? null; // worms: color at the tip (gradient along t)
    leaf.pframe = o.pframe ?? scope.pframe;
    leaf.rigid = !!(o.rigid ?? scope.rigid);
    leaf.offset = o.offset || 0;
    leaf.shell = o.shell || 0;
    leaf.noise = o.noise || null;
    leaf.flowTag = o.flow !== false;
    leaf.flowFn = typeof (o.flow ?? scope.flow) === 'function' ? (o.flow ?? scope.flow) : Array.isArray(o.flow ?? scope.flow) ? (() => { const d = o.flow ?? scope.flow; return () => d; })() : null;
    const W = leaf.W;
    // Uniform scale of the leaf matrix (distance correction); reflections allowed.
    const e = W.elements;
    leaf.s = Math.cbrt(Math.abs(W.determinant())) || 1;
    const inv = W.clone().invert().elements;
    // Row-major 3x4 world->local.
    leaf.m = new Float64Array([inv[0], inv[4], inv[8], inv[12], inv[1], inv[5], inv[9], inv[13], inv[2], inv[6], inv[10], inv[14]]);
    leaf.Wm = new Float64Array([e[0], e[4], e[8], e[12], e[1], e[5], e[9], e[13], e[2], e[6], e[10], e[14]]);
    // World AABB from the local AABB.
    const lb = leaf.lbox;
    const pad = (leaf.noise ? Math.abs(leaf.noise.amp || 0) * 1.5 : 0) + Math.max(leaf.offset, 0) + leaf.shell + (leaf.groovePad || 0);
    const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < 8; i++) {
      _v.set(i & 1 ? lb[3] : lb[0], i & 2 ? lb[4] : lb[1], i & 4 ? lb[5] : lb[2]).applyMatrix4(W);
      mn[0] = Math.min(mn[0], _v.x); mn[1] = Math.min(mn[1], _v.y); mn[2] = Math.min(mn[2], _v.z);
      mx[0] = Math.max(mx[0], _v.x); mx[1] = Math.max(mx[1], _v.y); mx[2] = Math.max(mx[2], _v.z);
    }
    leaf.box = [mn[0] - pad, mn[1] - pad, mn[2] - pad, mx[0] + pad, mx[1] + pad, mx[2] + pad];
    leaf.fn = makeLeafFn(leaf);
    return leaf;
  }

  function addNode(node, o) {
    node.op = o.op || 'add';
    node.k = o.k ?? scope.k;
    if (node.op === 'paint') {
      node.paint = {
        mat: o.paintMat != null ? matIndex(o.paintMat) : -1,
        color: o.paintColor || null,
        soft: o.soft ?? 0.004,
        strength: o.strength ?? 1,
        pframe: o.paintFrame ?? null,
        only: o.only ? o.only.map(matIndex) : null,
      };
    }
    if (o.cutMat != null) node.cutMat = matIndex(o.cutMat);
    scope.group.children.push(node);
    return node;
  }

  function leaf(type, o, lbox, params) {
    const W = place(o);
    const lf = { type, W, lbox, ...params };
    finalizeLeaf(lf, o);
    return addNode(lf, o);
  }

  const v3 = (a, d = [0, 0, 0]) => (a ? [a[0] || 0, a[1] || 0, a[2] || 0] : d);

  const api = {
    materials: matNames,
    matIndex,
    root,
    stitches,
    frames,
    joints,
    expr: opts.expr || null,
    get scope() { return scope; },

    sphere(o) {
      const r = o.r;
      return leaf('sphere', o, [-r, -r, -r, r, r, r], { r });
    },
    ellipsoid(o) {
      const [rx, ry, rz] = o.r;
      return leaf('ellipsoid', o, [-rx, -ry, -rz, rx, ry, rz], { rx, ry, rz });
    },
    box(o) {
      const [bx, by, bz] = o.size;
      return leaf('box', o, [-bx, -by, -bz, bx, by, bz], { bx, by, bz, rr: Math.min(o.round ?? 0.01, bx, by, bz) });
    },
    capsule(o) {
      const a = v3(o.a), b = v3(o.b), r = o.r;
      return leaf('capsule', o, [Math.min(a[0], b[0]) - r, Math.min(a[1], b[1]) - r, Math.min(a[2], b[2]) - r,
        Math.max(a[0], b[0]) + r, Math.max(a[1], b[1]) + r, Math.max(a[2], b[2]) + r], { a, b, r });
    },
    roundCone(o) {
      const a = v3(o.a), b = v3(o.b), ra = o.ra ?? o.r, rb = o.rb ?? o.r;
      const r = Math.max(ra, rb);
      return leaf('roundCone', o, [Math.min(a[0], b[0]) - r, Math.min(a[1], b[1]) - r, Math.min(a[2], b[2]) - r,
        Math.max(a[0], b[0]) + r, Math.max(a[1], b[1]) + r, Math.max(a[2], b[2]) + r], { a, b, ra, rb });
    },
    torus(o) {
      const R = o.R, r = o.r;
      return leaf('torus', o, [-R - r, -r, -R - r, R + r, r, R + r], { R, rt: r });
    },
    // Partial torus: arc centered on local +z, `angle` = total arc angle (radians).
    arc(o) {
      const R = o.R, r = o.r, ha = (o.angle ?? Math.PI) / 2;
      return leaf('arc', o, [-R - r, -r, -R - r, R + r, r, R + r], { R, rt: r, sa: Math.sin(ha), ca: Math.cos(ha) });
    },
    cylinder(o) {
      const r = o.r, h = o.h;
      return leaf('cylinder', o, [-r, -h, -r, r, h, r], { r, h, rr: Math.min(o.round ?? 0.005, r, h) });
    },
    cone(o) {
      const h = o.h, r1 = o.r1, r2 = o.r2, rr = o.round ?? 0.005;
      const r = Math.max(r1, r2);
      return leaf('cone', o, [-r, -h, -r, r, h, r], { h: h - rr, r1: Math.max(r1 - rr, 1e-4), r2: Math.max(r2 - rr, 1e-4), rr });
    },
    plane(o) {
      const n = new THREE.Vector3(...v3(o.n, [0, 1, 0])).normalize();
      const B = 50;
      return leaf('plane', o, [-B, -B, -B, B, B, B], { nx: n.x, ny: n.y, nz: n.z, d: o.d || 0 });
    },
    // Tube along a Catmull-Rom curve through `pts`, radius profile `r` (number | array per t | fn(t)).
    // flat: cross-section squash (0..1) along the `up` hint; grooves: { n, depth } strand ridges; twist (rad).
    worm(o) {
      const pts = o.pts.map((p) => v3(p));
      const segs = o.segs || Math.max(6, (pts.length - 1) * 5);
      const P = [], R = [], T = [];
      for (let i = 0; i <= segs; i++) {
        const t = i / segs;
        P.push(catmull(pts, t));
        R.push(Math.max(1e-4, interpProfile(o.r, t)));
        T.push(t);
      }
      // Parallel-transport frames.
      const up = new THREE.Vector3(...v3(o.up, [0, 0, -1])).normalize();
      const tan = [], nor = [], bin = [];
      for (let i = 0; i < segs; i++) {
        const t = new THREE.Vector3(P[i + 1][0] - P[i][0], P[i + 1][1] - P[i][1], P[i + 1][2] - P[i][2]).normalize();
        tan.push(t);
      }
      let n0 = up.clone().sub(tan[0].clone().multiplyScalar(up.dot(tan[0])));
      if (n0.lengthSq() < 1e-8) n0 = new THREE.Vector3(1, 0, 0).cross(tan[0]);
      n0.normalize();
      for (let i = 0; i < segs; i++) {
        if (i > 0) {
          const q = new THREE.Quaternion().setFromUnitVectors(tan[i - 1], tan[i]);
          n0 = n0.clone().applyQuaternion(q);
          n0.sub(tan[i].clone().multiplyScalar(n0.dot(tan[i]))).normalize();
        }
        if (o.ups) {
          // explicit per-control-point face normals (e.g. surface normals from sd.normalAt), interpolated along t
          const tt = (i + 0.5) / segs * (o.ups.length - 1);
          const i0 = Math.min(o.ups.length - 2, Math.floor(tt)), u = tt - i0;
          const A = o.ups[i0], B = o.ups[i0 + 1];
          const uv = new THREE.Vector3(A[0] + (B[0] - A[0]) * u, A[1] + (B[1] - A[1]) * u, A[2] + (B[2] - A[2]) * u);
          uv.sub(tan[i].clone().multiplyScalar(uv.dot(tan[i])));
          if (uv.lengthSq() > 1e-8) n0 = uv.normalize();
        }
        if (o.twist) n0.applyAxisAngle(tan[i], o.twist / segs);
        nor.push(n0.clone());
        bin.push(tan[i].clone().cross(n0).normalize());
      }
      const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
      for (let i = 0; i <= segs; i++) for (let c = 0; c < 3; c++) {
        mn[c] = Math.min(mn[c], P[i][c] - R[i]); mx[c] = Math.max(mx[c], P[i][c] + R[i]);
      }
      const seg = new Float64Array(segs * 14);
      for (let i = 0; i < segs; i++) {
        const b = i * 14;
        seg.set([...P[i], ...P[i + 1], R[i], R[i + 1], nor[i].x, nor[i].y, nor[i].z, bin[i].x, bin[i].y, bin[i].z], b);
      }
      const grooves = o.grooves || null;
      const lf = leaf('worm', { ...o, _gp: 0 }, [mn[0], mn[1], mn[2], mx[0], mx[1], mx[2]], {
        seg, segs, flat: o.flat ?? 1, grooves, tvals: T, groovePad: grooves ? Math.abs(grooves.depth) : 0,
        tips: o.tips ?? 1,
      });
      return lf;
    },
    custom(o) {
      return leaf('custom', o, o.box || [-1, -1, -1, 1, 1, 1], { cfn: o.fn });
    },

    group(o, fn) {
      if (typeof o === 'function') { fn = o; o = {}; }
      // k = smooth blend between the group's own children; blend = how the whole group joins its previous siblings.
      const g = { kind: 'group', children: [], id: _uid++, name: o.name || 'group', offset: o.offset || 0, shell: o.shell || 0 };
      addNode(g, { ...o, k: o.blend ?? 0 });
      g.gk = o.k ?? 0;
      push({ group: g, k: g.gk, mat: o.mat !== undefined ? o.mat : scope.mat, bone: o.bone !== undefined ? resolveBone(o.bone) : scope.bone,
        pframe: o.pframe ?? scope.pframe, color: o.color !== undefined ? o.color : scope.color, rigid: o.rigid ?? scope.rigid, flow: o.flow ?? scope.flow }, fn);
      return g;
    },
    // Guide: a DETACHED group (not part of the baked tree) used only as a snap / normalAt target, e.g. a proxy of
    // the head inside a rigid part (brows) or a guide surface for laying details. Same options as group().
    guide(o, fn) {
      if (typeof o === 'function') { fn = o; o = {}; }
      const g = { kind: 'group', children: [], id: _uid++, name: o.name || 'guide', offset: o.offset || 0, shell: o.shell || 0, op: 'add', k: 0 };
      g.gk = o.k ?? 0;
      push({ group: g, k: g.gk, mat: o.mat !== undefined ? o.mat : scope.mat, bone: scope.bone, pframe: scope.pframe, color: scope.color, rigid: scope.rigid, flow: scope.flow }, fn);
      return g;
    },
    // Paint: shapes created inside fn recolor the surface where they overlap (they add no volume).
    paint(o, fn) {
      if (typeof o === 'function') { const t = fn; fn = o; o = t || {}; }
      const g = { kind: 'group', children: [], id: _uid++, name: o.name || 'paint', offset: 0, shell: 0 };
      addNode(g, { op: 'paint', paintMat: o.mat, paintColor: o.color, soft: o.soft, strength: o.strength, paintFrame: o.pframe, only: o.only, k: 0 });
      g.gk = o.k ?? 0;
      push({ group: g, k: o.k ?? 0 }, fn);
      return g;
    },
    mirrorX(fn, o = {}) {
      if (!o.only) fn(false);
      push({ matrix: MIRROR.clone().multiply(scope.matrix), mirrored: !scope.mirrored }, () => fn(true));
    },
    bone(name, fn, o = {}) {
      const real = scope.mirrored ? SWAP_LR(name) : name;
      const j = joints[name];
      if (!j) throw new Error(`sdf: unknown joint '${name}'`);
      const base = scope.mirrored ? MIRROR.clone().multiply(j.matrix) : j.matrix.clone();
      push({ matrix: base, bone: o.bone !== undefined ? resolveBone(o.bone) : chainOf(real) }, fn);
    },
    frame(o, fn) {
      push({ matrix: scope.matrix.clone().multiply(toMatrix(o)) }, fn);
    },
    // Pattern frame: 'tri' = triplanar in the frame's axes; 'cyl' = cylindrical around its local y (u around,
    // v along), seam at the back (+z). radius = nominal radius used to snap stripe counts.
    patternFrame(o = {}) {
      const W = place(o);
      if (o.axis) {
        const ax = new THREE.Vector3(...o.axis).normalize();
        const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), ax);
        W.multiply(new THREE.Matrix4().makeRotationFromQuaternion(q));
      }
      const f = { id: frames.length, mode: o.mode || 'cyl', matrix: W, inv: W.clone().invert(), radius: o.radius || 0.15, mirrored: scope.mirrored };
      frames.push(f);
      return f.id;
    },
    // Stitch / seam line in rest space (projected onto the surface by the baker). points in scope frame.
    stitch(points, o = {}) {
      const pts = points.map((p) => new THREE.Vector3(...v3(p)).applyMatrix4(scope.matrix).toArray());
      stitches.push({ pts, width: o.width ?? 0.0014, dash: o.dash ?? 0.009, duty: o.duty ?? 0.6, color: o.color || '#F08A2E',
        mats: (o.mats || []).map(matIndex), smooth: o.smooth ?? true, segLen: o.segLen ?? 0.012 });
    },
    // World position of a point given in the current scope frame.
    toWorld(p) { return new THREE.Vector3(...v3(p)).applyMatrix4(scope.matrix).toArray(); },
    // Project a point (current scope coords) onto the surface of an already-built node (group/leaf), lifted
    // `lift` meters along the outward normal; returns scope coords. Use it to lay hair locks, buttons, tufts,
    // pockets on a surface. snapAll(node, pts, lift) maps a list.
    snap(node, p, lift = 0) {
      if (!node.fn || node._snapDirty !== node.children?.length) { compileTree(node); node._snapDirty = node.children?.length; }
      const f = node.fn;
      const w = new THREE.Vector3(...v3(p)).applyMatrix4(scope.matrix);
      let x = w.x, y = w.y, z = w.z;
      const e = 0.0008;
      for (let it = 0; it < 8; it++) {
        const d = f(x, y, z) - lift;
        const gx = (f(x + e, y, z) - f(x - e, y, z)) / (2 * e), gy = (f(x, y + e, z) - f(x, y - e, z)) / (2 * e), gz = (f(x, y, z + e) - f(x, y, z - e)) / (2 * e);
        const g2 = gx * gx + gy * gy + gz * gz;
        if (g2 < 1e-10) break;
        x -= (d * gx) / g2; y -= (d * gy) / g2; z -= (d * gz) / g2;
        if (Math.abs(d) < 1e-5) break;
      }
      return new THREE.Vector3(x, y, z).applyMatrix4(scope.matrix.clone().invert()).toArray();
    },
    // Outward surface normal of a built node at a point (scope coords in and out).
    normalAt(node, p) {
      if (!node.fn || node._snapDirty !== node.children?.length) { compileTree(node); node._snapDirty = node.children?.length; }
      const f = node.fn, e = 0.001;
      const w = new THREE.Vector3(...v3(p)).applyMatrix4(scope.matrix);
      const g = new THREE.Vector3(f(w.x + e, w.y, w.z) - f(w.x - e, w.y, w.z), f(w.x, w.y + e, w.z) - f(w.x, w.y - e, w.z), f(w.x, w.y, w.z + e) - f(w.x, w.y, w.z - e));
      const m = new THREE.Matrix3().setFromMatrix4(scope.matrix.clone().invert());
      return g.applyMatrix3(m).normalize().toArray();
    },
    snapAll(node, pts, lift = 0) { return pts.map((p, i) => api.snap(node, p, Array.isArray(lift) ? lift[i] : lift)); },
  };
  return api;
}

// ---------------------------------------------------------------------------------------------------------------
// Leaf evaluation closures: fn(x,y,z) in world space -> distance (world units).
function makeLeafFn(L) {
  const m = L.m, s = L.s;
  const off = L.offset, shell = L.shell;
  const nz = L.noise;
  let local;
  switch (L.type) {
    case 'sphere': { const r = L.r; local = (x, y, z) => Math.sqrt(x * x + y * y + z * z) - r; break; }
    case 'ellipsoid': { const { rx, ry, rz } = L; local = (x, y, z) => sdEllipsoid(x, y, z, rx, ry, rz); break; }
    case 'box': { const { bx, by, bz, rr } = L; local = (x, y, z) => sdBox(x, y, z, bx, by, bz, rr); break; }
    case 'capsule': { const [ax, ay, az] = L.a, [bx, by, bz] = L.b, r = L.r; local = (x, y, z) => sdCapsule(x, y, z, ax, ay, az, bx, by, bz, r); break; }
    case 'roundCone': { const [ax, ay, az] = L.a, [bx, by, bz] = L.b, ra = L.ra, rb = L.rb; local = (x, y, z) => sdRoundCone(x, y, z, ax, ay, az, bx, by, bz, ra, rb); break; }
    case 'torus': { const R = L.R, r = L.rt; local = (x, y, z) => sdTorus(x, y, z, R, r); break; }
    case 'arc': { const R = L.R, r = L.rt, sa = L.sa, ca = L.ca; local = (x, y, z) => sdArc(x, y, z, sa, ca, R, r); break; }
    case 'cylinder': { const { r, h, rr } = L; local = (x, y, z) => sdCylinder(x, y, z, r, h, rr); break; }
    case 'cone': { const { h, r1, r2, rr } = L; local = (x, y, z) => sdCappedCone(x, y, z, h, r1, r2) - rr; break; }
    case 'plane': { const { nx, ny, nz: nnz, d } = L; local = (x, y, z) => x * nx + y * ny + z * nnz - d; break; }
    case 'worm': local = makeWormFn(L); break;
    case 'custom': local = L.cfn; break;
    default: throw new Error('sdf: bad leaf ' + L.type);
  }
  const m0 = m[0], m1 = m[1], m2 = m[2], m3 = m[3], m4 = m[4], m5 = m[5], m6 = m[6], m7 = m[7], m8 = m[8], m9 = m[9], m10 = m[10], m11 = m[11];
  let f;
  if (!nz) {
    f = (x, y, z) => local(m0 * x + m1 * y + m2 * z + m3, m4 * x + m5 * y + m6 * z + m7, m8 * x + m9 * y + m10 * z + m11) * s;
  } else {
    const amp = nz.amp || 0.003, fr = nz.freq || 40, oct = nz.oct || 2, st = nz.stretch || [1, 1, 1], sd = (nz.seed || 0) * 17.13;
    const ridge = !!nz.ridge;
    f = (x, y, z) => {
      const lx = m0 * x + m1 * y + m2 * z + m3, ly = m4 * x + m5 * y + m6 * z + m7, lz = m8 * x + m9 * y + m10 * z + m11;
      let n = fbm3(lx * fr * st[0] + sd, ly * fr * st[1] + sd * 0.7, lz * fr * st[2] - sd, oct);
      if (ridge) n = 0.5 - Math.abs(n) * 2;
      return local(lx, ly, lz) * s + amp * n;
    };
  }
  if (off === 0 && shell === 0) return f;
  return (x, y, z) => { let d = f(x, y, z) - off; if (shell) d = Math.abs(d) - shell; return d; };
}

// Worm: min over round-cone segments; flattening and grooves use the segment frame.
function makeWormFn(L) {
  const seg = L.seg, n = L.segs, flat = L.flat, gr = L.grooves;
  const gN = gr ? gr.n || 6 : 0, gD = gr ? gr.depth || 0.002 : 0, gOff = gr ? gr.phase || 0 : 0;
  const out = { t: 0, ang: 0, i: 0 };
  L._last = out;
  // per-segment bounding spheres (center, radius) to skip far segments
  const bs = new Float64Array(n * 4);
  for (let i = 0; i < n; i++) {
    const b = i * 14;
    const cx = (seg[b] + seg[b + 3]) / 2, cy = (seg[b + 1] + seg[b + 4]) / 2, cz = (seg[b + 2] + seg[b + 5]) / 2;
    const hl = Math.hypot(seg[b + 3] - seg[b], seg[b + 4] - seg[b + 1], seg[b + 5] - seg[b + 2]) / 2;
    bs[i * 4] = cx; bs[i * 4 + 1] = cy; bs[i * 4 + 2] = cz; bs[i * 4 + 3] = hl + Math.max(seg[b + 6], seg[b + 7]);
  }
  return (x, y, z) => {
    let best = Infinity, bi = 0, bt = 0;
    for (let i = 0; i < n; i++) {
      const q = i * 4;
      const sdd = (Math.sqrt((x - bs[q]) ** 2 + (y - bs[q + 1]) ** 2 + (z - bs[q + 2]) ** 2) - bs[q + 3]) * (flat < 1 ? flat : 1);
      if (sdd > best) continue;
      const b = i * 14;
      let px = x, py = y, pz = z;
      const ax = seg[b], ay = seg[b + 1], az = seg[b + 2];
      if (flat !== 1) {
        // squash along the frame normal (= the 'up' hint = flat-face normal)
        const bx = seg[b + 8], by = seg[b + 9], bz = seg[b + 10];
        const dx = px - ax, dy = py - ay, dz = pz - az;
        const kb = (dx * bx + dy * by + dz * bz) * (1 / flat - 1);
        px += bx * kb; py += by * kb; pz += bz * kb;
      }
      let d = sdRoundCone(px, py, pz, ax, ay, az, seg[b + 3], seg[b + 4], seg[b + 5], seg[b + 6], seg[b + 7]);
      if (flat !== 1) d *= flat;
      if (d < best) { best = d; bi = i; }
    }
    // Param along the curve and the angle around it (for grooves / color gradients).
    const b = bi * 14;
    const ax = seg[b], ay = seg[b + 1], az = seg[b + 2];
    const tx = seg[b + 3] - ax, ty = seg[b + 4] - ay, tz = seg[b + 5] - az;
    const l2 = tx * tx + ty * ty + tz * tz || 1e-12;
    const dx = x - ax, dy = y - ay, dz = z - az;
    const u = Math.max(0, Math.min(1, (dx * tx + dy * ty + dz * tz) / l2));
    bt = (bi + u) / n;
    out.t = bt; out.i = bi;
    if (gr) {
      const nx = seg[b + 8], ny = seg[b + 9], nzz = seg[b + 10], bx = seg[b + 11], by = seg[b + 12], bz = seg[b + 13];
      const cu = dx * nx + dy * ny + dz * nzz, cv = dx * bx + dy * by + dz * bz;
      const ang = Math.atan2(cv, cu);
      out.ang = ang;
      const fadeTip = smoothstep(0.0, 0.15, bt) * smoothstep(1.0, 0.8, bt);
      best += gD * (0.5 - 0.5 * Math.cos(ang * gN + gOff)) * fadeTip;
    }
    return best;
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Tree evaluation. Groups combine children in order. Pruning builds a lighter tree for a box.
function combine(op, a, b, k) {
  switch (op) {
    case 'add': return smin(a, b, k);
    case 'sub': return ssub(a, b, k);
    case 'int': return sint(a, b, k);
    default: return a;
  }
}

export function makeGroupFn(g, children) {
  const ch = children.filter((c) => c.op !== 'paint');
  const n = ch.length;
  const fns = ch.map((c) => c.fn), ops = ch.map((c) => c.op), ks = ch.map((c) => c.k ?? 0);
  const off = g.offset || 0, shell = g.shell || 0;
  let f;
  if (n === 0) f = () => 1e3;
  else if (n === 1 && ops[0] === 'add') f = fns[0];
  else f = (x, y, z) => {
    let d = 1e3;
    for (let i = 0; i < n; i++) d = combine(ops[i], d, fns[i](x, y, z), ks[i]);
    return d;
  };
  if (off === 0 && shell === 0) return f;
  return (x, y, z) => { let d = f(x, y, z) - off; if (shell) d = Math.abs(d) - shell; return d; };
}

// Compute node boxes and group closures (call once after sculpting).
export function compileTree(node) {
  if (node.kind === 'leaf') return node;
  for (const c of node.children) compileTree(c);
  const pos = node.children.filter((c) => c.op === 'add');
  const box = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
  for (const c of pos) {
    const k = Math.max(c.k || 0, 0);
    for (let i = 0; i < 3; i++) { box[i] = Math.min(box[i], c.box[i] - k); box[i + 3] = Math.max(box[i + 3], c.box[i + 3] + k); }
  }
  // Intersections shrink the box.
  for (const c of node.children) if (c.op === 'int') for (let i = 0; i < 3; i++) {
    box[i] = Math.max(box[i], c.box[i] - (c.k || 0)); box[i + 3] = Math.min(box[i + 3], c.box[i + 3] + (c.k || 0));
  }
  const o = Math.max(node.offset || 0, 0) + (node.shell || 0);
  node.box = [box[0] - o, box[1] - o, box[2] - o, box[3] + o, box[4] + o, box[5] + o];
  node.fn = makeGroupFn(node, node.children);
  return node;
}

function boxDist(b, q) {
  // distance between two AABBs (0 if overlapping)
  const dx = Math.max(0, b[0] - q[3], q[0] - b[3]);
  const dy = Math.max(0, b[1] - q[4], q[1] - b[4]);
  const dz = Math.max(0, b[2] - q[5], q[2] - b[5]);
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

// Pruned copy of the tree for points inside box q (children farther than their blend radius are dropped).
// Returns a node with .fn, or null when nothing can contribute.
export function pruneTree(node, q, margin = 0) {
  if (node.kind === 'leaf') return boxDist(node.box, q) <= margin + (node.k || 0) ? node : null;
  const kept = [];
  let changed = false;
  for (const c of node.children) {
    if (c.op === 'paint') { if (boxDist(c.box || [-1e9, -1e9, -1e9, 1e9, 1e9, 1e9], q) <= margin + (c.paint ? c.paint.soft : 0)) kept.push(c); else changed = true; continue; }
    const pc = pruneTree(c, q, margin + Math.max(c.k || 0, 0));
    if (!pc) {
      if (c.op === 'int') return null; // intersect with nothing -> empty
      changed = true; continue;
    }
    if (pc !== c) changed = true;
    kept.push(pc);
  }
  if (!kept.some((c) => c.op === 'add')) return null;
  if (!changed) return node;
  const g = { ...node, children: kept };
  g.fn = makeGroupFn(g, kept);
  return g;
}

// ---------------------------------------------------------------------------------------------------------------
// Attribute sampling: distance + dominant leaf + blended color + material (with paint layers).
// out = { d, leaf, mat, r, g, b, pframe, wormT, paintW }
const _tmpCol = [0, 0, 0];
export function hexToRgb(hex, out = [0, 0, 0]) {
  if (Array.isArray(hex)) { out[0] = hex[0]; out[1] = hex[1]; out[2] = hex[2]; return out; }
  const c = new THREE.Color(hex);
  out[0] = c.r; out[1] = c.g; out[2] = c.b; // linear
  return out;
}

export function makeSampler(materials) {
  const matList = Object.values(materials);
  const baseCol = matList.map((m) => hexToRgb(m.pattern ? (m.tint || '#ffffff') : m.color || '#ffffff'));
  const colCache = new Map();
  const leafCol = (leaf, t) => {
    let c = colCache.get(leaf.id);
    if (!c) {
      c = { a: leaf.color ? hexToRgb(leaf.color) : (leaf.mat >= 0 ? baseCol[leaf.mat] : [1, 1, 1]), b: leaf.color2 ? hexToRgb(leaf.color2) : null };
      colCache.set(leaf.id, c);
    }
    if (!c.b) return c.a;
    const s = t * t * (3 - 2 * t);
    _tmpCol[0] = c.a[0] + (c.b[0] - c.a[0]) * s;
    _tmpCol[1] = c.a[1] + (c.b[1] - c.a[1]) * s;
    _tmpCol[2] = c.a[2] + (c.b[2] - c.a[2]) * s;
    return _tmpCol;
  };

  function evalNode(node, x, y, z, out) {
    if (node.kind === 'leaf') {
      const d = node.fn(x, y, z);
      out.d = d; out.leaf = node; out.mat = node.mat; out.pframe = node.pframe;
      const t = node.type === 'worm' ? node._last.t : 0;
      out.wormT = t;
      out.wormI = node.type === 'worm' ? node._last.i : null;
      const c = leafCol(node, t);
      out.r = c[0]; out.g = c[1]; out.b = c[2];
      return out;
    }
    let first = true;
    const tmp = { d: 0, leaf: null, mat: -1, r: 0, g: 0, b: 0, pframe: 0, wormT: 0, wormI: null };
    for (const c of node.children) {
      if (c.op === 'paint') continue;
      evalNode(c, x, y, z, tmp);
      if (first) {
        if (c.op !== 'add') continue;
        Object.assign(out, tmp); first = false; continue;
      }
      const k = c.k || 0;
      const a = out.d, b = tmp.d;
      if (c.op === 'add') {
        const nd = smin(a, b, k);
        const tb = k > 0 ? clamp01(0.5 + 0.5 * (a - b) / k) : (b < a ? 1 : 0);
        if (b < a) {
          const sameMat = tmp.mat === out.mat;
          const w = sameMat ? tb : 1;
          const r = out.r + (tmp.r - out.r) * w, g = out.g + (tmp.g - out.g) * w, bb = out.b + (tmp.b - out.b) * w;
          out.leaf = tmp.leaf; out.mat = tmp.mat; out.pframe = tmp.pframe; out.wormT = tmp.wormT; out.wormI = tmp.wormI;
          out.r = r; out.g = g; out.b = bb;
        } else if (tmp.mat === out.mat && tb > 0) {
          out.r += (tmp.r - out.r) * tb; out.g += (tmp.g - out.g) * tb; out.b += (tmp.b - out.b) * tb;
        }
        out.d = nd;
      } else if (c.op === 'sub') {
        const nd = ssub(a, b, k);
        if (c.cutMat != null && -b > a - k * 0.25) { out.mat = c.cutMat; out.leaf = tmp.leaf; const cc = baseCol[c.cutMat]; out.r = cc[0]; out.g = cc[1]; out.b = cc[2]; }
        out.d = nd;
      } else if (c.op === 'int') {
        out.d = sint(a, b, k);
      }
    }
    if (first) { out.d = 1e3; out.leaf = null; out.mat = -1; }
    // Group offset / shell
    if (node.offset) out.d -= node.offset;
    if (node.shell) out.d = Math.abs(out.d) - node.shell;
    // Paint layers (after geometry): blend color, maybe switch material.
    for (const c of node.children) {
      if (c.op !== 'paint') continue;
      const pd = c.fn(x, y, z);
      const P = c.paint;
      if (P.only && !P.only.includes(out.mat)) continue;
      const w = (1 - smoothstep(-P.soft, P.soft, pd)) * P.strength;
      if (w <= 0) continue;
      if (P.color) {
        const pc = hexToRgb(P.color, _tmpCol);
        out.r += (pc[0] - out.r) * w; out.g += (pc[1] - out.g) * w; out.b += (pc[2] - out.b) * w;
      }
      if (P.mat >= 0 && w >= 0.5 * P.strength) {
        out.mat = P.mat;
        if (!P.color) { const cc = baseCol[P.mat]; out.r = cc[0]; out.g = cc[1]; out.b = cc[2]; }
        if (P.pframe != null) out.pframe = P.pframe;
      }
    }
    return out;
  }
  return (node, x, y, z, out = {}) => evalNode(node, x, y, z, out);
}

// Iterate leaves (for stats / bounds).
export function forEachLeaf(node, fn) {
  if (node.kind === 'leaf') return fn(node);
  for (const c of node.children) forEachLeaf(c, fn);
}

// Deterministic leaf numbering (DFS order) so trees rebuilt in bake workers can refer to leaves by index.
export function indexLeaves(root) {
  const list = [];
  forEachLeaf(root, (l) => { l.dfs = list.length; list.push(l); });
  return list;
}
