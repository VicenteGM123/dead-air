// Skin weights: nearest allowed bone segment (from the dominant primitive's binding) + joint blending
// (parent at the bone's origin, children near their origins, gated by limb radius) + diffusion smoothing on the
// position-welded surface graph. Output: top-4 bones per vertex.
import { CHAINS } from '../../src/art/sdf.js';

const smoothstep = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

function segDist(p, s) {
  const [ax, ay, az] = s.a, [bx, by, bz] = s.b;
  const pax = p[0] - ax, pay = p[1] - ay, paz = p[2] - az, bax = bx - ax, bay = by - ay, baz = bz - az;
  const h = Math.min(1, Math.max(0, (pax * bax + pay * bay + paz * baz) / (bax * bax + bay * bay + baz * baz || 1e-12)));
  return Math.hypot(pax - bax * h, pay - bay * h, paz - baz * h);
}

export function computeSkin(V, I, R, segments, opts = {}) {
  const bones = R.bones;
  const nb = bones.length;
  const bi = Object.fromEntries(bones.map((b, i) => [b, i]));
  const children = bones.map(() => []);
  for (const b of bones) if (R.parents[b]) children[bi[R.parents[b]]].push(bi[b]);
  const seg = bones.map((b) => segments[b]);
  const axis = seg.map((s) => {
    const d = [s.b[0] - s.a[0], s.b[1] - s.a[1], s.b[2] - s.a[2]];
    const l = Math.hypot(...d) || 1;
    return [d[0] / l, d[1] / l, d[2] / l];
  });
  const skin = bones.map((b) => R.skin[b] || { blend: 0.05, gate: 0.1 });
  const allowedCache = new Map();
  const allowed = (leaf) => {
    const b = leaf ? leaf.bone : 'auto';
    const key = Array.isArray(b) ? b.join(',') : String(b);
    let a = allowedCache.get(key);
    if (a) return a;
    let names;
    if (b == null || b === 'auto') names = bones;
    else if (Array.isArray(b)) names = b;
    else if (R.humanoid && CHAINS[b]) names = CHAINS[b];
    else if (opts.chains && opts.chains[b]) names = opts.chains[b];
    else names = [b];
    a = names.filter((n) => n in bi).map((n) => bi[n]);
    if (!a.length) a = bones.map((_, i) => i);
    allowedCache.set(key, a);
    return a;
  };

  // Welded representatives
  const n = V.mat.length;
  const rep = new Int32Array(n).fill(-1);
  const reps = [];
  for (let v = 0; v < n; v++) {
    const w = V.weld[v];
    if (rep[w] === -1) { rep[w] = reps.length; reps.push(v); }
  }
  const nw = reps.length;
  const wid = new Int32Array(n);
  for (let v = 0; v < n; v++) wid[v] = rep[V.weld[v]];

  const W = new Float32Array(nw * nb);
  const rigid = new Uint8Array(nw);
  const p = [0, 0, 0];
  for (let r = 0; r < nw; r++) {
    const v = reps[r];
    p[0] = V.pos[v * 3]; p[1] = V.pos[v * 3 + 1]; p[2] = V.pos[v * 3 + 2];
    const leaf = V.leaf[v];
    const al = allowed(leaf);
    let best = al[0], bd = Infinity;
    for (const j of al) { const d = segDist(p, seg[j]); if (d < bd) { bd = d; best = j; } }
    const o = r * nb;
    if (leaf && leaf.rigid) { W[o + best] = 1; rigid[r] = 1; continue; }
    let wh = 1;
    // (1) parent blend at the bone origin
    const par = R.parents[bones[best]];
    const sk = skin[best];
    if (par && sk.blend > 0) {
      const a = seg[best].a, ax = axis[best];
      const s = (p[0] - a[0]) * ax[0] + (p[1] - a[1]) * ax[1] + (p[2] - a[2]) * ax[2];
      const t = smoothstep(-sk.blend, sk.blend, s);
      W[o + bi[par]] += 1 - t;
      wh = t;
    }
    // (2) children blend near their origins (gated by the limb radius)
    for (const c of children[best]) {
      const kc = skin[c];
      if (!(kc.blend > 0)) continue;
      const a = seg[c].a, ax = axis[c];
      const dx = p[0] - a[0], dy = p[1] - a[1], dz = p[2] - a[2];
      const s = dx * ax[0] + dy * ax[1] + dz * ax[2];
      if (s < -kc.blend) continue;
      const rad = Math.hypot(dx - s * ax[0], dy - s * ax[1], dz - s * ax[2]);
      const g = 1 - smoothstep(kc.gate * 0.75, kc.gate * 1.35, rad);
      const tc = smoothstep(-kc.blend, kc.blend, s) * g;
      if (tc <= 0) continue;
      W[o + c] += wh * tc;
      wh *= 1 - tc;
    }
    W[o + best] += wh;
  }

  // Welded adjacency (CSR)
  const deg = new Int32Array(nw);
  const edges = [];
  for (let t = 0; t < I.length; t += 3) {
    for (let e = 0; e < 3; e++) {
      const a = wid[I[t + e]], b = wid[I[t + (e + 1) % 3]];
      if (a === b) continue;
      edges.push(a, b);
      deg[a]++; deg[b]++;
    }
  }
  const start = new Int32Array(nw + 1);
  for (let i = 0; i < nw; i++) start[i + 1] = start[i] + deg[i];
  const adj = new Int32Array(start[nw]);
  const fill = start.slice(0, nw);
  for (let e = 0; e < edges.length; e += 2) { const a = edges[e], b = edges[e + 1]; adj[fill[a]++] = b; adj[fill[b]++] = a; }

  // Diffusion smoothing
  const iters = opts.smooth ?? 8, lam = 0.5;
  let A = W, Bf = new Float32Array(W.length);
  for (let it = 0; it < iters; it++) {
    for (let r = 0; r < nw; r++) {
      const o = r * nb;
      if (rigid[r] || start[r + 1] === start[r]) { for (let j = 0; j < nb; j++) Bf[o + j] = A[o + j]; continue; }
      const cnt = start[r + 1] - start[r];
      for (let j = 0; j < nb; j++) {
        let s = 0;
        for (let q = start[r]; q < start[r + 1]; q++) s += A[adj[q] * nb + j];
        Bf[o + j] = A[o + j] * (1 - lam) + (s / cnt) * lam;
      }
    }
    const t = A; A = Bf; Bf = t;
  }

  // Top-4 per welded vertex, then expand to all vertices
  const idx4 = new Uint8Array(n * 4), w4 = new Uint8Array(n * 4);
  const tmpI = new Int32Array(4), tmpW = new Float32Array(4);
  const repI = new Uint8Array(nw * 4), repW = new Uint8Array(nw * 4);
  for (let r = 0; r < nw; r++) {
    const o = r * nb;
    tmpW.fill(-1); tmpI.fill(0);
    for (let j = 0; j < nb; j++) {
      const w = A[o + j];
      if (w <= tmpW[3]) continue;
      let k = 3;
      while (k > 0 && tmpW[k - 1] < w) { tmpW[k] = tmpW[k - 1]; tmpI[k] = tmpI[k - 1]; k--; }
      tmpW[k] = w; tmpI[k] = j;
    }
    let sum = 0;
    for (let k = 0; k < 4; k++) { if (tmpW[k] < 0.004) tmpW[k] = 0; sum += tmpW[k]; }
    let acc = 0;
    for (let k = 0; k < 4; k++) {
      const q = Math.round((tmpW[k] / sum) * 255);
      repI[r * 4 + k] = tmpI[k];
      repW[r * 4 + k] = q;
      acc += q;
    }
    repW[r * 4] += 255 - acc; // rounding remainder on the dominant bone
  }
  for (let v = 0; v < n; v++) {
    const r = wid[v];
    for (let k = 0; k < 4; k++) { idx4[v * 4 + k] = repI[r * 4 + k]; w4[v * 4 + k] = repW[r * 4 + k]; }
  }
  return { skinIndex: idx4, skinWeight: w4, welded: nw };
}
