// Final per-vertex shading data on the simplified mesh: SDF-gradient normals, baked ambient occlusion
// (normal-direction samples + cone-traced hemisphere visibility), cavity/convexity (SDF Laplacian), triplanar weights,
// sparse morph targets (projection onto expression variants) and stitch-line projection.
import * as THREE from 'three';
import { pruneTree } from '../../src/art/sdf.js';
import { projectToSurface } from './attrib.mjs';

export function makeRegionTrees(tree, cell = 0.08, margin = 0.22) {
  const cache = new Map();
  return (x, y, z) => {
    const i = Math.floor(x / cell), j = Math.floor(y / cell), k = Math.floor(z / cell);
    const key = `${i},${j},${k}`;
    let t = cache.get(key);
    if (t === undefined) {
      t = pruneTree(tree, [i * cell, j * cell, k * cell, (i + 1) * cell, (j + 1) * cell, (k + 1) * cell], margin) || tree;
      cache.set(key, t);
    }
    return t;
  };
}

function gradN(f, x, y, z, e) {
  const gx = f(x + e, y, z) - f(x - e, y, z);
  const gy = f(x, y + e, z) - f(x, y - e, z);
  const gz = f(x, y, z + e) - f(x, y, z - e);
  const l = Math.hypot(gx, gy, gz) || 1;
  return [gx / l, gy / l, gz / l];
}

// Fixed hemisphere directions (cosine-ish distribution) in a local frame (z = normal).
const HEMI = (() => {
  const dirs = [];
  const N = 10;
  for (let i = 0; i < N; i++) {
    const u = (i + 0.5) / N;
    const phi = i * 2.399963;
    const r = Math.sqrt(u) * 0.92;
    dirs.push([Math.cos(phi) * r, Math.sin(phi) * r, Math.sqrt(1 - r * r)]);
  }
  return dirs;
})();

export function shadeVertices(pos, n, treeAt, opts = {}) {
  const nrm = new Float32Array(n * 3);
  const ao = new Float32Array(n);
  const cav = new Float32Array(n);
  const aoScale = opts.aoStrength ?? 1;
  const reach = opts.aoReach ?? 0.16;
  const steps = [0.014, 0.038, 0.08, reach];
  for (let v = 0; v < n; v++) {
    const x = pos[v * 3], y = pos[v * 3 + 1], z = pos[v * 3 + 2];
    const f = treeAt(x, y, z).fn;
    const g = gradN(f, x, y, z, 0.0012);
    nrm[v * 3] = g[0]; nrm[v * 3 + 1] = g[1]; nrm[v * 3 + 2] = g[2];
    // 1) normal-direction occlusion (IQ style)
    let occ = 0, w = 1;
    for (let i = 1; i <= 5; i++) {
      const h = 0.008 * i * i * 0.6 + 0.004;
      const d = f(x + g[0] * h, y + g[1] * h, z + g[2] * h);
      occ += Math.max(0, h - d) * w;
      w *= 0.7;
    }
    const aoN = Math.max(0, 1 - occ * 7);
    // 2) hemisphere cone visibility
    const t = Math.abs(g[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0];
    let tx = t[1] * g[2] - t[2] * g[1], ty = t[2] * g[0] - t[0] * g[2], tz = t[0] * g[1] - t[1] * g[0];
    const tl = Math.hypot(tx, ty, tz); tx /= tl; ty /= tl; tz /= tl;
    const bx = g[1] * tz - g[2] * ty, by = g[2] * tx - g[0] * tz, bz = g[0] * ty - g[1] * tx;
    let vis = 0, wsum = 0;
    const rot = (v * 0.618034) % 1 * Math.PI * 2;
    const cr = Math.cos(rot), sr = Math.sin(rot);
    for (const [hx0, hy0, hz] of HEMI) {
      const hx = hx0 * cr - hy0 * sr, hy = hx0 * sr + hy0 * cr;
      const dx = tx * hx + bx * hy + g[0] * hz, dy = ty * hx + by * hy + g[1] * hz, dz = tz * hx + bz * hy + g[2] * hz;
      let vmin = 1;
      for (const s of steps) {
        const d = f(x + dx * s + g[0] * 0.003, y + dy * s + g[1] * 0.003, z + dz * s + g[2] * 0.003);
        const c = Math.min(1, Math.max(0, d / (s * 0.55)));
        if (c < vmin) vmin = c;
      }
      vis += vmin * hz; wsum += hz;
    }
    const aoH = vis / wsum;
    ao[v] = Math.pow(Math.max(0, Math.min(1, aoN * (0.45 + 0.55 * aoH))), aoScale);
    // 3) cavity (Laplacian at a small scale): <0 concave crease, >0 convex edge
    const e = opts.cavScale ?? 0.005;
    const d0 = f(x, y, z);
    const lap = (f(x + e, y, z) + f(x - e, y, z) + f(x, y + e, z) + f(x, y - e, z) + f(x, y, z + e) + f(x, y, z - e) - 6 * d0) / (e * e);
    cav[v] = Math.max(-1, Math.min(1, lap * (opts.cavGain ?? 0.01)));
  }
  return { nrm, ao, cav };
}

// Triplanar weights in each vertex's pattern frame (tri mode); packed 0..255.
export function triWeights(nrm, frameIds, frames, n) {
  const out = new Uint8Array(n * 4);
  const m = new THREE.Matrix3();
  const v3 = new THREE.Vector3();
  const mats = frames.map((f) => new THREE.Matrix3().setFromMatrix4(f.inv));
  for (let v = 0; v < n; v++) {
    m.copy(mats[frameIds[v]] || mats[0]);
    v3.set(nrm[v * 3], nrm[v * 3 + 1], nrm[v * 3 + 2]).applyMatrix3(m).normalize();
    let wx = Math.pow(Math.abs(v3.x), 4), wy = Math.pow(Math.abs(v3.y), 4), wz = Math.pow(Math.abs(v3.z), 4);
    const s = wx + wy + wz || 1;
    out[v * 4] = Math.round((wx / s) * 255); out[v * 4 + 1] = Math.round((wy / s) * 255); out[v * 4 + 2] = Math.round((wz / s) * 255);
  }
  return out;
}

// Sparse morph target: base vertices (mask) projected onto the variant surface. With `col` (linear base vertex
// colors) + `sampler`, the variant's surface color at the moved position is sampled too, giving color deltas `dc`
// (morph colors): a mouth can then open (dark interior appears) or close (skin covers it) cleanly.
export function morphTarget(pos, nrm, n, variantTreeAt, mask, maxMove = 0.03, baseTreeAt = null, col = null, sampler = null) {
  const ids = [], dp = [], dn = [], dc = [];
  const o = {};
  for (let v = 0; v < n; v++) {
    if (mask && !mask[v]) continue;
    const x = pos[v * 3], y = pos[v * 3 + 1], z = pos[v * 3 + 2];
    const t = variantTreeAt(x, y, z);
    const f = t.fn;
    const d = f(x, y, z);
    let mx = 0, my = 0, mz = 0;
    const same = Math.abs(d) < 1e-4 || (baseTreeAt && Math.abs(d - baseTreeAt(x, y, z).fn(x, y, z)) < 1e-4);
    if (!same) {
      const p = projectToSurface(f, [x, y, z], 5, 0.001);
      mx = p[0] - x; my = p[1] - y; mz = p[2] - z;
      const ml = Math.hypot(mx, my, mz);
      if (ml < 1e-4) { mx = my = mz = 0; } else if (ml > maxMove) { const s = maxMove / ml; mx *= s; my *= s; mz *= s; }
    }
    let cr = 0, cg = 0, cb = 0;
    const moved0 = mx !== 0 || my !== 0 || mz !== 0;
    // only MOVED vertices are recolored: static border duplicates (two copies at one position, one per material)
    // would otherwise flip to the other side's color
    if (col && sampler && moved0) {
      sampler(variantTreeAt(x + mx, y + my, z + mz), x + mx, y + my, z + mz, o);
      cr = (o.r ?? 1) - col[v * 3]; cg = (o.g ?? 1) - col[v * 3 + 1]; cb = (o.b ?? 1) - col[v * 3 + 2];
      if (Math.abs(cr) + Math.abs(cg) + Math.abs(cb) < 0.012) cr = cg = cb = 0;
    }
    const moved = mx !== 0 || my !== 0 || mz !== 0;
    if (!moved && cr === 0 && cg === 0 && cb === 0) continue;
    const g = moved ? gradN(f, x + mx, y + my, z + mz, 0.0012) : [nrm[v * 3], nrm[v * 3 + 1], nrm[v * 3 + 2]];
    ids.push(v);
    dp.push(mx, my, mz);
    dn.push(g[0] - nrm[v * 3], g[1] - nrm[v * 3 + 1], g[2] - nrm[v * 3 + 2]);
    dc.push(cr, cg, cb);
  }
  return { ids, dp, dn, dc };
}

// Stitch polylines: resample, project onto the surface, emit segments.
export function projectStitches(stitches, tree) {
  const segs = [];
  let stroke = 0;
  for (const s of stitches) {
    stroke++;
    const pts = s.pts.map((p) => new THREE.Vector3(...p));
    const curve = pts.length > 2 && s.smooth ? new THREE.CatmullRomCurve3(pts, false, 'centripetal') : new THREE.CurvePath();
    if (!(curve instanceof THREE.CatmullRomCurve3)) for (let i = 0; i < pts.length - 1; i++) curve.add(new THREE.LineCurve3(pts[i], pts[i + 1]));
    const len = curve.getLength();
    const N = Math.max(2, Math.ceil(len / s.segLen));
    const P = [];
    for (let i = 0; i <= N; i++) {
      const p = curve.getPointAt(i / N);
      P.push(projectToSurface(tree.fn, [p.x, p.y, p.z], 6, 0.001));
    }
    let acc = 0;
    for (let i = 0; i < N; i++) {
      const a = P[i], b = P[i + 1];
      const l = Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
      segs.push({ a, b, t0: acc, width: s.width, dash: s.dash, duty: s.duty, color: s.color, mats: s.mats, stroke });
      acc += l;
    }
  }
  return segs;
}

// Group consecutive segments of a stroke into chunks (<= 16) with bounding spheres for the shader.
export function stitchChunks(segs, max = 16) {
  const out = [];
  let i = 0;
  while (i < segs.length) {
    const first = i;
    const st = segs[i].stroke;
    while (i < segs.length && segs[i].stroke === st && i - first < max) i++;
    const pts = [];
    for (let k = first; k < i; k++) pts.push(segs[k].a, segs[k].b);
    const c = [0, 1, 2].map((q) => pts.reduce((a, p) => a + p[q], 0) / pts.length);
    let r = 0;
    for (const p of pts) r = Math.max(r, Math.hypot(p[0] - c[0], p[1] - c[1], p[2] - c[2]));
    out.push([...c, r + segs[first].width * 3 + 0.002, first, i - first]);
  }
  return out;
}
