// Per-vertex attribute sampling + crisp material/pattern-frame borders + pattern coordinates.
// Mesh representation used through the bake ("V"): struct of plain JS arrays that can grow:
//   V.pos[3n] V.nrm[3n] V.col[3n] V.mat[n] V.frame[n] V.key[n] V.flow[3n] V.leaf[n] (leaf object) V.weld[n]
//   V.pco[3n] (pattern coords) V.pmode[n] ; I = triangle indices (JS array)
import * as THREE from 'three';
import { pruneTree } from '../../src/art/sdf.js';
import { projectTet } from './mesher.mjs';

const KEYM = 256;
export const keyOf = (mat, frame) => (mat + 1) * KEYM + frame;

export function createV() {
  return { pos: [], nrm: [], col: [], mat: [], frame: [], key: [], flow: [], leaf: [], weld: [], pco: [], pmode: [], wormT: [] };
}

function gradAt(f, x, y, z, e) {
  const gx = f(x + e, y, z) - f(x - e, y, z);
  const gy = f(x, y + e, z) - f(x, y - e, z);
  const gz = f(x, y, z + e) - f(x, y, z - e);
  const l = Math.hypot(gx, gy, gz) || 1;
  return [gx / l, gy / l, gz / l];
}

export function projectToSurface(f, p, iters = 3, e = 0.0008) {
  let [x, y, z] = p;
  for (let it = 0; it < iters; it++) {
    const d = f(x, y, z);
    if (Math.abs(d) < 2e-6) break;
    const gx = (f(x + e, y, z) - f(x - e, y, z)) / (2 * e);
    const gy = (f(x, y + e, z) - f(x, y - e, z)) / (2 * e);
    const gz = (f(x, y, z + e) - f(x, y, z - e)) / (2 * e);
    const g2 = gx * gx + gy * gy + gz * gz;
    if (g2 < 1e-10) break;
    x -= (d * gx) / g2; y -= (d * gy) / g2; z -= (d * gz) / g2;
  }
  return [x, y, z];
}

// Push one vertex sampled at p. Returns its index.
function pushSample(V, S, p, weld) {
  const { sampler, treeAt, voxel } = S;
  const t = treeAt(p[0], p[1], p[2]);
  const o = sampler(t, p[0], p[1], p[2], {});
  const n = gradAt(t.fn, p[0], p[1], p[2], voxel * 0.35);
  const i = V.mat.length;
  V.pos.push(p[0], p[1], p[2]);
  V.nrm.push(n[0], n[1], n[2]);
  V.col.push(o.r ?? 1, o.g ?? 1, o.b ?? 1);
  const mat = o.mat ?? -1;
  const frame = o.pframe ?? 0;
  V.mat.push(mat);
  V.frame.push(frame);
  V.key.push(keyOf(mat, frame));
  V.leaf.push(o.leaf || null);
  V.wormT.push(o.wormT || 0);
  const fl = flowOf(o.leaf, o.wormI, p);
  V.flow.push(fl[0], fl[1], fl[2]);
  V.weld.push(weld ?? i);
  V.pco.push(0, 0, 0);
  V.pmode.push(0);
  return i;
}

// Worker-side batch sampling: typed arrays per vertex (leaf by DFS index).
export function sampleBatch(tree, sampler, P, voxel) {
  const n = P.length / 3;
  const nrm = new Float32Array(n * 3), col = new Float32Array(n * 3), mat = new Int16Array(n), frame = new Int16Array(n);
  const leaf = new Int32Array(n), wormT = new Float32Array(n), wormI = new Int16Array(n);
  const treeAt = makeLocalTrees(tree, 0.06, voxel * 3);
  const o = {};
  for (let v = 0; v < n; v++) {
    const x = P[v * 3], y = P[v * 3 + 1], z = P[v * 3 + 2];
    const t = treeAt(x, y, z);
    sampler(t, x, y, z, o);
    const g = gradAt(t.fn, x, y, z, voxel * 0.35);
    nrm[v * 3] = g[0]; nrm[v * 3 + 1] = g[1]; nrm[v * 3 + 2] = g[2];
    col[v * 3] = o.r ?? 1; col[v * 3 + 1] = o.g ?? 1; col[v * 3 + 2] = o.b ?? 1;
    mat[v] = o.mat ?? -1; frame[v] = o.pframe ?? 0; leaf[v] = o.leaf ? o.leaf.dfs : -1;
    wormT[v] = o.wormT || 0; wormI[v] = o.wormI ?? -1;
  }
  return { nrm, col, mat, frame, leaf, wormT, wormI };
}

function makeLocalTrees(tree, cell, margin) {
  const cache = new Map();
  return (x, y, z) => {
    const i = Math.floor(x / cell), j = Math.floor(y / cell), k = Math.floor(z / cell);
    const key = i + ',' + j + ',' + k;
    let t = cache.get(key);
    if (t === undefined) { t = pruneTree(tree, [i * cell, j * cell, k * cell, (i + 1) * cell, (j + 1) * cell, (k + 1) * cell], margin) || tree; cache.set(key, t); }
    return t;
  };
}

function flowOf(leaf, wormI, p) {
  if (leaf && leaf.flowFn && p) { const d = leaf.flowFn(p[0], p[1], p[2]); const l = Math.hypot(d[0], d[1], d[2]) || 1; return [d[0] / l, d[1] / l, d[2] / l]; }
  if (!leaf || leaf.type !== 'worm' || leaf.flowTag === false || wormI == null || wormI < 0) return [0, 0, 0];
  const s = leaf.seg, b = wormI * 14;
  const dx = s[b + 3] - s[b], dy = s[b + 4] - s[b + 1], dz = s[b + 5] - s[b + 2];
  const l = Math.hypot(dx, dy, dz) || 1;
  return [dx / l, dy / l, dz / l];
}

// Samples every surface-net vertex (in parallel when a pool is given).
export async function sampleMesh(mesh, S, pool, treeName, leaves) {
  const V = createV();
  const P = mesh.positions;
  const n = P.length / 3;
  const chunk = Math.ceil(n / ((pool ? pool.n : 1) * 4));
  const jobs = [];
  for (let s = 0; s < n; s += chunk) {
    const part = P.slice(s * 3, Math.min(n, s + chunk) * 3);
    jobs.push(pool ? pool.run({ type: 'sample', tree: treeName, positions: part, voxel: S.voxel }) : Promise.resolve(sampleBatch(S.tree, S.sampler, part, S.voxel)));
  }
  const res = await Promise.all(jobs);
  let v = 0;
  for (const r of res) {
    const m = r.mat.length;
    for (let i = 0; i < m; i++, v++) {
      V.pos.push(P[v * 3], P[v * 3 + 1], P[v * 3 + 2]);
      V.nrm.push(r.nrm[i * 3], r.nrm[i * 3 + 1], r.nrm[i * 3 + 2]);
      V.col.push(r.col[i * 3], r.col[i * 3 + 1], r.col[i * 3 + 2]);
      V.mat.push(r.mat[i]); V.frame.push(r.frame[i]); V.key.push(keyOf(r.mat[i], r.frame[i]));
      const lf = r.leaf[i] >= 0 ? leaves[r.leaf[i]] : null;
      V.leaf.push(lf); V.wormT.push(r.wormT[i]);
      const fl = flowOf(lf, r.wormI[i], [P[v * 3], P[v * 3 + 1], P[v * 3 + 2]]);
      V.flow.push(fl[0], fl[1], fl[2]);
      V.weld.push(v); V.pco.push(0, 0, 0); V.pmode.push(0);
    }
  }
  return { V, I: Array.from(mesh.indices) };
}

// Copy vertex v (same position/weld), overriding key/material/frame and color.
function copyVertex(V, v, over = {}) {
  const i = V.mat.length;
  for (const k of ['pos', 'nrm', 'col', 'flow', 'pco']) V[k].push(V[k][v * 3], V[k][v * 3 + 1], V[k][v * 3 + 2]);
  V.mat.push(over.mat ?? V.mat[v]);
  V.frame.push(over.frame ?? V.frame[v]);
  V.key.push(keyOf(over.mat ?? V.mat[v], over.frame ?? V.frame[v]));
  V.leaf.push(over.leaf ?? V.leaf[v]);
  V.wormT.push(V.wormT[v]);
  V.weld.push(V.weld[v]);
  V.pmode.push(V.pmode[v]);
  if (over.col) { V.col[i * 3] = over.col[0]; V.col[i * 3 + 1] = over.col[1]; V.col[i * 3 + 2] = over.col[2]; }
  return i;
}

// Split triangles along material/pattern-frame borders found by bisection -> crisp, smooth borders.
export function cutBorders(V, I, S) {
  const { sampler, treeAt } = S;
  const keyAt = (p) => {
    const o = sampler(treeAt(p[0], p[1], p[2]), p[0], p[1], p[2], {});
    return keyOf(o.mat ?? -1, o.pframe ?? 0);
  };
  const edgeCache = new Map();
  const N0 = V.mat.length;
  const lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  const P = (v) => [V.pos[v * 3], V.pos[v * 3 + 1], V.pos[v * 3 + 2]];
  // crossing on edge (a,b): returns { [keyA]: idx, [keyB]: idx }
  const crossing = (a, b) => {
    const ek = a < b ? a * N0 + b : b * N0 + a;
    let c = edgeCache.get(ek);
    if (c) return c;
    const ka = V.key[a];
    const pa = P(a), pb = P(b);
    let lo = 0, hi = 1;
    for (let it = 0; it < 7; it++) {
      const m = (lo + hi) * 0.5;
      if (keyAt(lerp(pa, pb, m)) === ka) lo = m; else hi = m;
    }
    const f = treeAt(...lerp(pa, pb, 0.5)).fn;
    const e = S.voxel * 0.3, mm = S.voxel * 0.5;
    const pm = projectTet(f, ...lerp(pa, pb, (lo + hi) * 0.5), e, 2, mm);
    const weld = V.mat.length;
    const plo = projectTet(f, ...lerp(pa, pb, lo), e, 2, mm);
    const phi = projectTet(f, ...lerp(pa, pb, hi), e, 2, mm);
    const iA = pushSample(V, S, plo, weld);
    const iB = pushSample(V, S, phi, weld);
    // Same position for both copies, keys forced to the two sides.
    for (const [iv, v] of [[iA, a], [iB, b]]) {
      V.pos[iv * 3] = pm[0]; V.pos[iv * 3 + 1] = pm[1]; V.pos[iv * 3 + 2] = pm[2];
      if (V.key[iv] !== V.key[v]) {
        V.mat[iv] = V.mat[v]; V.frame[iv] = V.frame[v]; V.key[iv] = V.key[v]; V.leaf[iv] = V.leaf[v];
        V.col[iv * 3] = V.col[v * 3]; V.col[iv * 3 + 1] = V.col[v * 3 + 1]; V.col[iv * 3 + 2] = V.col[v * 3 + 2];
      }
    }
    // normals: identical (gradient at pm)
    const nn = gradAt(f, pm[0], pm[1], pm[2], S.voxel * 0.35);
    for (const iv of [iA, iB]) { V.nrm[iv * 3] = nn[0]; V.nrm[iv * 3 + 1] = nn[1]; V.nrm[iv * 3 + 2] = nn[2]; }
    c = { [V.key[a]]: iA, [V.key[b]]: iB };
    edgeCache.set(ek, c);
    return c;
  };
  const copies = new Map();
  const copyFor = (v, key, src) => {
    if (V.key[v] === key) return v;
    const ck = v * 4096 + (key % 4096);
    let c = copies.get(ck);
    if (c === undefined) {
      c = copyVertex(V, v, { mat: V.mat[src], frame: V.frame[src], leaf: V.leaf[src], col: [V.col[src * 3], V.col[src * 3 + 1], V.col[src * 3 + 2]] });
      copies.set(ck, c);
    }
    return c;
  };
  const out = [];
  let cut = 0;
  for (let t = 0; t < I.length; t += 3) {
    const a = I[t], b = I[t + 1], c = I[t + 2];
    const ka = V.key[a], kb = V.key[b], kc = V.key[c];
    if (ka === kb && kb === kc) { out.push(a, b, c); continue; }
    if (ka !== kb && kb !== kc && ka !== kc) {
      out.push(a, copyFor(b, ka, a), copyFor(c, ka, a));
      continue;
    }
    // rotate so that the lone vertex is first
    let X, Y, Z;
    if (kb === kc) { X = a; Y = b; Z = c; } else if (ka === kc) { X = b; Y = c; Z = a; } else { X = c; Y = a; Z = b; }
    const kx = V.key[X], ky = V.key[Y];
    const cxy = crossing(X, Y), cxz = crossing(X, Z);
    const mxyX = cxy[kx], mxyY = cxy[ky], mxzX = cxz[kx], mxzY = cxz[ky];
    if (mxyX === undefined || mxyY === undefined || mxzX === undefined || mxzY === undefined) { out.push(a, b, c); continue; }
    out.push(X, mxyX, mxzX);
    out.push(mxyY, Y, Z);
    out.push(mxyY, Z, mxzY);
    cut++;
  }
  return { I: out, cut };
}

// Pattern coordinates per vertex from its frame; wraps cylindrical seams by duplicating vertices.
export function patternCoords(V, I, frames, materials) {
  const matList = Object.values(materials);
  const tmp = new THREE.Vector3();
  const n = V.mat.length;
  for (let v = 0; v < n; v++) computePco(V, v, frames, matList, tmp);
  // cyl wrap: triangles crossing the seam get copies with u + C
  const wrapCopy = new Map();
  let wraps = 0;
  for (let t = 0; t < I.length; t += 3) {
    const tri = [I[t], I[t + 1], I[t + 2]];
    if (V.pmode[tri[0]] !== 1) continue;
    const us = tri.map((v) => V.pco[v * 3]);
    const C = V.pco[tri[0] * 3 + 2];
    if (Math.max(...us) - Math.min(...us) <= C * 0.5) continue;
    for (let k = 0; k < 3; k++) {
      const v = tri[k];
      if (V.pco[v * 3] >= 0) continue;
      let c = wrapCopy.get(v);
      if (c === undefined) {
        c = copyVertex(V, v);
        V.pco[c * 3] += V.pco[c * 3 + 2];
        wrapCopy.set(v, c);
      }
      I[t + k] = c;
    }
    wraps++;
  }
  return { wraps };
}

function computePco(V, v, frames, matList, tmp) {
  const f = frames[V.frame[v]] || frames[0];
  tmp.set(V.pos[v * 3], V.pos[v * 3 + 1], V.pos[v * 3 + 2]).applyMatrix4(f.inv);
  const m = matList[V.mat[v]];
  if (f.mode === 'cyl') {
    const P = (m && m.pattern && m.pattern.scale) || 0.1;
    const N = Math.max(1, Math.round((2 * Math.PI * f.radius) / P));
    const C = N * P;
    let th = Math.atan2(tmp.x, -tmp.z);
    if (f.mirrored) th = -th;
    V.pco[v * 3] = (th / (2 * Math.PI)) * C;
    V.pco[v * 3 + 1] = tmp.y;
    V.pco[v * 3 + 2] = C;
    V.pmode[v] = 1;
  } else {
    V.pco[v * 3] = tmp.x; V.pco[v * 3 + 1] = tmp.y; V.pco[v * 3 + 2] = tmp.z;
    V.pmode[v] = 0;
  }
}
