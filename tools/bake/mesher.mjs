// Block-sparse naive surface nets over an SDF tree (src/art/sdf.js).
//   surfaceNets(tree, { voxel, bounds, pool, treeName }) -> { positions, indices, treeAt(x,y,z), stats }
// Main thread: grid + candidate blocks (2-level pruned trees). Workers (or inline): per block, 9^3 corner values,
// sign-change cells, vertex = mean edge crossing + Newton projection (tetrahedral gradient). Main: quads.
import { pruneTree } from '../../src/art/sdf.js';

const B = 8; // cells per block edge
const C = B + 1; // corners per block edge
const SB = 4; // blocks per superblock edge

const TET = [[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]];
// Newton projection onto the surface with tetrahedral gradients (4 evals / iteration).
export function projectTet(f, x, y, z, e, iters = 2, maxMove = Infinity) {
  const x0 = x, y0 = y, z0 = z;
  for (let it = 0; it < iters; it++) {
    let gx = 0, gy = 0, gz = 0, d = 0;
    for (const k of TET) {
      const v = f(x + k[0] * e, y + k[1] * e, z + k[2] * e);
      gx += k[0] * v; gy += k[1] * v; gz += k[2] * v; d += v;
    }
    d *= 0.25;
    const g2 = gx * gx + gy * gy + gz * gz;
    if (g2 < 1e-14) break;
    const s = d / g2 * (4 * e); // grad = g/(4e)  ->  step = d * grad/|grad|^2 = d * g * 4e / |g|^2
    x -= gx * s; y -= gy * s; z -= gz * s;
    if (Math.abs(d) < e * 0.01) break;
  }
  const mx = x - x0, my = y - y0, mz = z - z0, ml = Math.sqrt(mx * mx + my * my + mz * mz);
  if (ml > maxMove) { const s = maxMove / ml; x = x0 + mx * s; y = y0 + my * s; z = z0 + mz * s; }
  return [x, y, z];
}

export function makeGrid(bounds, h) {
  const ox = bounds[0] - 3 * h, oy = bounds[1] - 3 * h, oz = bounds[2] - 3 * h;
  const NX = Math.ceil((bounds[3] - bounds[0]) / h) + 7;
  const NY = Math.ceil((bounds[4] - bounds[1]) / h) + 7;
  const NZ = Math.ceil((bounds[5] - bounds[2]) / h) + 7;
  return { ox, oy, oz, h, NX, NY, NZ, NBX: Math.ceil(NX / B), NBY: Math.ceil(NY / B), NBZ: Math.ceil(NZ / B) };
}

const blockBox = (G, bx, by, bz, n = 1) => {
  const { ox, oy, oz, h } = G;
  const x0 = ox + bx * B * h, y0 = oy + by * B * h, z0 = oz + bz * B * h;
  return [x0 - h, y0 - h, z0 - h, x0 + (B * n + 1) * h, y0 + (B * n + 1) * h, z0 + (B * n + 1) * h];
};

const EDGES = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
function cellVertex(cv, gx, gy, gz, G, f) {
  let sx = 0, sy = 0, sz = 0, n = 0;
  for (const [a, b] of EDGES) {
    const va = cv[a], vb = cv[b];
    if ((va < 0) === (vb < 0)) continue;
    const t = va / (va - vb);
    const ax = a & 1, ay = (a >> 1) & 1, az = (a >> 2) & 1;
    sx += ax + ((b & 1) - ax) * t; sy += ay + (((b >> 1) & 1) - ay) * t; sz += az + (((b >> 2) & 1) - az) * t; n++;
  }
  if (!n) { sx = sy = sz = 0.5; n = 1; }
  const { ox, oy, oz, h } = G;
  return projectTet(f, ox + (gx + sx / n) * h, oy + (gy + sy / n) * h, oz + (gz + sz / n) * h, h * 0.3, 2, h * 0.9);
}

// Worker side: blocks = Int32Array [bx,by,bz, ...]
export function processBlocks(tree, G, blocks) {
  const nb = blocks.length / 3;
  const corners = new Float32Array(nb * C * C * C);
  const counts = new Int32Array(nb);
  const cells = [], verts = [];
  const cv = new Float64Array(8);
  for (let q = 0; q < nb; q++) {
    const bx = blocks[q * 3], by = blocks[q * 3 + 1], bz = blocks[q * 3 + 2];
    const t = pruneTree(tree, blockBox(G, bx, by, bz), 2 * G.h);
    const off = q * C * C * C;
    if (!t) { corners.fill(1e3, off, off + C * C * C); continue; }
    const f = t.fn;
    const x0 = G.ox + bx * B * G.h, y0 = G.oy + by * B * G.h, z0 = G.oz + bz * B * G.h;
    let n = off;
    for (let k = 0; k < C; k++) for (let j = 0; j < C; j++) for (let i = 0; i < C; i++) corners[n++] = f(x0 + i * G.h, y0 + j * G.h, z0 + k * G.h);
    let cnt = 0;
    for (let k = 0; k < B; k++) for (let j = 0; j < B; j++) for (let i = 0; i < B; i++) {
      let neg = 0;
      for (let c = 0; c < 8; c++) {
        const v = corners[off + (i + (c & 1)) + C * ((j + ((c >> 1) & 1)) + C * (k + ((c >> 2) & 1)))];
        cv[c] = v;
        if (v < 0) neg++;
      }
      if (neg === 0 || neg === 8) continue;
      const p = cellVertex(cv, bx * B + i, by * B + j, bz * B + k, G, f);
      cells.push(i + B * (j + B * k));
      verts.push(p[0], p[1], p[2]);
      cnt++;
    }
    counts[q] = cnt;
  }
  return { corners, counts, cells: new Uint16Array(cells), verts: new Float32Array(verts) };
}

export async function surfaceNets(tree, { voxel: h, bounds, margin = 1.5, pool = null, treeName = 'body' }) {
  const t0 = Date.now();
  const G = makeGrid(bounds, h);
  const { NX, NY, NBX, NBY, NBZ } = G;
  // 1) candidates via superblock -> block pruning
  const R = Math.sqrt(3) * B * h * 0.5;
  const cand = [];
  const treeCache = new Map();
  let evals = 0;
  for (let sz = 0; sz < NBZ; sz += SB) for (let sy = 0; sy < NBY; sy += SB) for (let sx = 0; sx < NBX; sx += SB) {
    const ts = pruneTree(tree, blockBox(G, sx, sy, sz, SB), 2 * h);
    if (!ts) continue;
    for (let bz = sz; bz < Math.min(NBZ, sz + SB); bz++) for (let by = sy; by < Math.min(NBY, sy + SB); by++) for (let bx = sx; bx < Math.min(NBX, sx + SB); bx++) {
      const t = pruneTree(ts, blockBox(G, bx, by, bz), 2 * h);
      if (!t) continue;
      const d = t.fn(G.ox + (bx + 0.5) * B * h, G.oy + (by + 0.5) * B * h, G.oz + (bz + 0.5) * B * h);
      evals++;
      if (Math.abs(d) <= R * margin + h) { cand.push(bx, by, bz); treeCache.set(bx + NBX * (by + NBY * bz), t); }
    }
  }
  const tCand = Date.now() - t0;
  // 2) process blocks (parallel)
  const nC = cand.length / 3;
  const chunk = Math.max(16, Math.ceil(nC / ((pool ? pool.n : 1) * 6)));
  const jobs = [];
  for (let s = 0; s < nC; s += chunk) {
    const blocks = new Int32Array(cand.slice(s * 3, Math.min(nC, s + chunk) * 3));
    jobs.push(pool ? pool.run({ type: 'blocks', tree: treeName, grid: G, blocks }).then((r) => ({ r, blocks })) : Promise.resolve({ r: processBlocks(tree, G, blocks), blocks }));
  }
  const results = await Promise.all(jobs);
  const tBlocks = Date.now() - t0 - tCand;
  // 3) assemble
  const blockData = new Map();
  const pos = [];
  const cellList = [];
  for (const { r, blocks } of results) {
    let vo = 0;
    for (let q = 0; q < blocks.length / 3; q++) {
      const bx = blocks[q * 3], by = blocks[q * 3 + 1], bz = blocks[q * 3 + 2];
      const key = bx + NBX * (by + NBY * bz);
      const cellMap = new Map();
      for (let c = 0; c < r.counts[q]; c++, vo++) {
        const li = r.cells[vo];
        cellMap.set(li, pos.length / 3);
        pos.push(r.verts[vo * 3], r.verts[vo * 3 + 1], r.verts[vo * 3 + 2]);
        cellList.push(bx * B + (li % B), by * B + (Math.floor(li / B) % B), bz * B + Math.floor(li / (B * B)));
      }
      blockData.set(key, { corners: r.corners.subarray(q * C * C * C, (q + 1) * C * C * C), cellMap });
    }
    evals += (blocks.length / 3) * C * C * C;
  }
  // Lazy fallback for cells in non-candidate blocks (rare)
  let lazy = 0;
  const cv = new Float64Array(8);
  const cellVert = (i, j, k) => {
    const bx = i >> 3, by = j >> 3, bz = k >> 3;
    const key = bx + NBX * (by + NBY * bz);
    let bd = blockData.get(key);
    if (!bd) { bd = { corners: null, cellMap: new Map() }; blockData.set(key, bd); }
    const li = (i & 7) + B * ((j & 7) + B * (k & 7));
    let v = bd.cellMap.get(li);
    if (v !== undefined) return v;
    const t = pruneTree(tree, blockBox(G, bx, by, bz), 2 * h) || tree;
    for (let c = 0; c < 8; c++) cv[c] = t.fn(G.ox + (i + (c & 1)) * h, G.oy + (j + ((c >> 1) & 1)) * h, G.oz + (k + ((c >> 2) & 1)) * h);
    const p = cellVertex(cv, i, j, k, G, t.fn);
    v = pos.length / 3;
    pos.push(p[0], p[1], p[2]);
    bd.cellMap.set(li, v);
    lazy++;
    return v;
  };
  const idx = [];
  const P = (vi) => [pos[vi * 3], pos[vi * 3 + 1], pos[vi * 3 + 2]];
  const d2 = (a, b) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2;
  const nCells = cellList.length / 3;
  for (let c = 0; c < nCells; c++) {
    const i = cellList[c * 3], j = cellList[c * 3 + 1], k = cellList[c * 3 + 2];
    const bd = blockData.get((i >> 3) + NBX * ((j >> 3) + NBY * (k >> 3)));
    const cor = bd.corners;
    const li = i & 7, lj = j & 7, lk = k & 7;
    const v0 = cor[li + C * (lj + C * lk)];
    for (let a = 0; a < 3; a++) {
      const v1 = cor[(li + (a === 0)) + C * ((lj + (a === 1)) + C * (lk + (a === 2)))];
      if ((v0 < 0) === (v1 < 0)) continue;
      const u = (a + 1) % 3, w = (a + 2) % 3;
      const du = [0, 0, 0]; du[u] = 1;
      const dw = [0, 0, 0]; dw[w] = 1;
      if (i - du[0] - dw[0] < 0 || j - du[1] - dw[1] < 0 || k - du[2] - dw[2] < 0) continue;
      const c0 = cellVert(i, j, k);
      const c1 = cellVert(i - du[0], j - du[1], k - du[2]);
      const c2 = cellVert(i - du[0] - dw[0], j - du[1] - dw[1], k - du[2] - dw[2]);
      const c3 = cellVert(i - dw[0], j - dw[1], k - dw[2]);
      const q = v0 < 0 ? [c0, c1, c2, c3] : [c0, c3, c2, c1];
      const p = q.map(P);
      if (d2(p[0], p[2]) < d2(p[1], p[3])) idx.push(q[0], q[1], q[2], q[0], q[2], q[3]);
      else idx.push(q[0], q[1], q[3], q[1], q[2], q[3]);
    }
  }
  const out = [];
  for (let t = 0; t < idx.length; t += 3) {
    const a = idx[t], b = idx[t + 1], c = idx[t + 2];
    if (a !== b && b !== c && a !== c) out.push(a, b, c);
  }
  const treeAt = (x, y, z) => {
    const bx = Math.max(0, Math.min(NBX - 1, Math.floor((x - G.ox) / (B * h))));
    const by = Math.max(0, Math.min(NBY - 1, Math.floor((y - G.oy) / (B * h))));
    const bz = Math.max(0, Math.min(NBZ - 1, Math.floor((z - G.oz) / (B * h))));
    const key = bx + NBX * (by + NBY * bz);
    let t = treeCache.get(key);
    if (t === undefined) { t = pruneTree(tree, blockBox(G, bx, by, bz), 2 * h) || tree; treeCache.set(key, t); }
    return t;
  };
  void NX; void NY;
  return {
    positions: new Float32Array(pos), indices: new Uint32Array(out), treeAt, grid: G,
    stats: { ms: Date.now() - t0, candMs: tCand, blockMs: tBlocks, evals, cand: nC, lazy, verts: pos.length / 3, tris: out.length / 3 },
  };
}
