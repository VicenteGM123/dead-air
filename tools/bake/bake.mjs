#!/usr/bin/env node
// Character baker: SDF sculpt (src/art/chars/<id>.js) -> smooth skinned mesh -> assets/baked/<id>.bin (+ .json).
//
//   node tools/bake/bake.mjs duke            bake one character (skips if the content hash is unchanged)
//   node tools/bake/bake.mjs --all           bake every src/art/chars/*.js (except _*.js and index.js)
//   options: --force (ignore cache)  --voxel <m>  --tris <n>  --quick (voxel x1.6, fast preview)  --threads <n>
//
// Pipeline (see docs/CHARKIT.md): sculpt -> block-sparse surface nets (+Newton projection, worker pool) ->
// attribute sampling -> crisp material/pattern borders (bisection cuts) -> pattern coords -> skin weights (joint
// blend + diffusion) -> meshoptimizer simplification (seams preserved) -> SDF normals, AO, cavity -> morph targets
// -> rigid parts -> write .bin/.json + assets/baked/registry.js.
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import { MeshoptSimplifier } from 'meshoptimizer';
import { makeSampler } from '../../src/art/sdf.js';
import { encodeBaked } from '../../src/art/bakedFormat.js';
import { loadDef, buildScene, CHARS, ROOT } from './scene.mjs';
import { surfaceNets } from './mesher.mjs';
import { sampleMesh, cutBorders, patternCoords } from './attrib.mjs';
import { computeSkin } from './skin.mjs';
import { triWeights, projectStitches, stitchChunks } from './finish.mjs';
import { Pool } from './pool.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(ROOT, 'assets/baked');
const VERSION = 4;

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

function hashInputs(id, extra) {
  const h = crypto.createHash('sha1');
  const files = [path.join(CHARS, id + '.js')];
  for (const f of fs.readdirSync(CHARS)) if (f.startsWith('_') && f.endsWith('.js')) files.push(path.join(CHARS, f));
  for (const f of ['src/art/sdf.js', 'src/art/rigBuild.js', 'src/art/bakedFormat.js', 'src/core/rig.js']) files.push(path.join(ROOT, f));
  for (const f of fs.readdirSync(__dirname)) if (f.endsWith('.mjs')) files.push(path.join(__dirname, f));
  for (const f of files.sort()) if (fs.existsSync(f)) h.update(f + '\n' + fs.readFileSync(f));
  h.update(JSON.stringify(extra) + VERSION);
  return h.digest('hex').slice(0, 16);
}

const toSRGB = (c) => (c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);

async function shadeParallel(pool, pos, n, opts) {
  const chunk = Math.ceil(n / (pool.n * 4));
  const jobs = [];
  for (let s = 0; s < n; s += chunk) jobs.push(pool.run({ type: 'shade', tree: 'ao', positions: pos.slice(s * 3, Math.min(n, s + chunk) * 3), opts }));
  const res = await Promise.all(jobs);
  const nrm = new Float32Array(n * 3), ao = new Float32Array(n), cav = new Float32Array(n);
  let o = 0;
  for (const r of res) { nrm.set(r.nrm, o * 3); ao.set(r.ao, o); cav.set(r.cav, o); o += r.ao.length; }
  return { nrm, ao, cav };
}

// Bake one SDF tree into a compact mesh. o.skin: { R, segments } or null (rigid part).
async function bakeTree(sd, def, o) {
  const { log, pool, treeName } = o;
  const t0 = Date.now();
  const root = sd.root;
  const voxel = o.voxel;
  const mesh = await surfaceNets(root, { voxel, bounds: root.box, pool, treeName });
  const ms = mesh.stats;
  log(`  surface nets: ${ms.verts} verts, ${ms.tris} tris, ${ms.cand} blocks, ${(ms.evals / 1e6).toFixed(2)}M evals, ${ms.ms} ms (plan ${ms.candMs}, blocks ${ms.blockMs}, lazy ${ms.lazy})`);
  const sampler = makeSampler(def.materials);
  const S = { sampler, treeAt: mesh.treeAt, voxel, tree: root };
  let t = Date.now();
  const { V, I: I0 } = await sampleMesh(mesh, S, pool, treeName, sd.leaves);
  const tS = Date.now() - t;
  const cut = cutBorders(V, I0, S);
  let I = cut.I;
  const pc = patternCoords(V, I, sd.frames, def.materials);
  log(`  attributes: ${V.mat.length} verts, ${cut.cut} border cuts, ${pc.wraps} seam wraps, ${Date.now() - t} ms (sample ${tS})`);
  t = Date.now();
  let skin = null;
  if (o.skin) {
    skin = computeSkin(V, I, o.skin.R, o.skin.segments, { smooth: def.bake?.skinSmooth ?? 10 });
    log(`  skin: ${skin.welded} welded verts, ${Date.now() - t} ms`);
  }
  // Simplify
  t = Date.now();
  const n0 = V.mat.length;
  const positions = new Float32Array(V.pos);
  const attrs = new Float32Array(n0 * 6);
  for (let v = 0; v < n0; v++) {
    attrs[v * 6] = V.nrm[v * 3]; attrs[v * 6 + 1] = V.nrm[v * 3 + 1]; attrs[v * 6 + 2] = V.nrm[v * 3 + 2];
    attrs[v * 6 + 3] = V.col[v * 3]; attrs[v * 6 + 4] = V.col[v * 3 + 1]; attrs[v * 6 + 5] = V.col[v * 3 + 2];
  }
  const idx = new Uint32Array(I);
  const target = Math.min(idx.length, Math.floor(o.tris) * 3);
  const w = def.bake?.simplifyWeights || [0.35, 0.35, 0.35, 0.6, 0.6, 0.6];
  const [simp, err] = MeshoptSimplifier.simplifyWithAttributes(idx, positions, 3, attrs, 6, w, null, target, o.error ?? 0.05, o.flags || []);
  const remap = new Int32Array(n0).fill(-1);
  const keep = [];
  for (let i = 0; i < simp.length; i++) { const v = simp[i]; if (remap[v] < 0) { remap[v] = keep.length; keep.push(v); } }
  const n = keep.length;
  const index = new Uint32Array(simp.length);
  for (let i = 0; i < simp.length; i++) index[i] = remap[simp[i]];
  log(`  simplify: ${I.length / 3} -> ${index.length / 3} tris (err ${err.toFixed(4)}), ${n} verts, ${Date.now() - t} ms`);
  // Final shading data (parallel)
  t = Date.now();
  const pos = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { const v = keep[i]; pos[i * 3] = V.pos[v * 3]; pos[i * 3 + 1] = V.pos[v * 3 + 1]; pos[i * 3 + 2] = V.pos[v * 3 + 2]; }
  const sh = await shadeParallel(pool, pos, n, { aoStrength: def.bake?.aoStrength ?? 1, aoReach: def.bake?.aoReach ?? 0.16, cavScale: def.bake?.cavScale ?? 0.005, cavGain: def.bake?.cavGain ?? 0.008 });
  const frameIds = keep.map((v) => V.frame[v]);
  const pw = triWeights(sh.nrm, frameIds, sd.frames, n);
  log(`  shade (normals/AO/cavity): ${Date.now() - t} ms`);
  const col = new Uint8Array(n * 3), aux = new Uint8Array(n * 4), pco = new Float32Array(n * 3), flow = new Int8Array(n * 4);
  const nrm8 = new Int8Array(n * 3);
  for (let i = 0; i < n; i++) {
    const v = keep[i];
    for (let c = 0; c < 3; c++) {
      col[i * 3 + c] = Math.round(Math.min(1, Math.max(0, toSRGB(V.col[v * 3 + c]))) * 255);
      pco[i * 3 + c] = V.pco[v * 3 + c];
      nrm8[i * 3 + c] = Math.round(sh.nrm[i * 3 + c] * 127);
      flow[i * 4 + c] = Math.round(V.flow[v * 3 + c] * 127);
    }
    aux[i * 4] = Math.round(sh.ao[i] * 255);
    aux[i * 4 + 1] = Math.round(128 + sh.cav[i] * 127);
    aux[i * 4 + 2] = Math.max(0, V.mat[v]);
    aux[i * 4 + 3] = V.pmode[v];
  }
  let skinIndex = null, skinWeight = null;
  if (skin) {
    skinIndex = new Uint8Array(n * 4); skinWeight = new Uint8Array(n * 4);
    for (let i = 0; i < n; i++) for (let k = 0; k < 4; k++) { skinIndex[i * 4 + k] = skin.skinIndex[keep[i] * 4 + k]; skinWeight[i * 4 + k] = skin.skinWeight[keep[i] * 4 + k]; }
  }
  const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < n; i++) for (let c = 0; c < 3; c++) { mn[c] = Math.min(mn[c], pos[i * 3 + c]); mx[c] = Math.max(mx[c], pos[i * 3 + c]); }
  const sc = [0, 1, 2].map((c) => Math.max(1e-6, mx[c] - mn[c]));
  const qpos = new Uint16Array(n * 3);
  for (let i = 0; i < n; i++) for (let c = 0; c < 3; c++) qpos[i * 3 + c] = Math.round(((pos[i * 3 + c] - mn[c]) / sc[c]) * 65535);
  return {
    n, index, pos, nrm: sh.nrm, qpos, qbox: [...mn, ...sc], nrm8, col, aux, pco, pw, flow, skinIndex, skinWeight,
    stats: { tris: index.length / 3, verts: n, rawTris: I.length / 3, ms: Date.now() - t0 },
  };
}

async function bakeChar(id) {
  const log = (...a) => console.log(...a);
  const bust = String(Date.now());
  const def = await loadDef(id, bust);
  const quick = flag('--quick');
  const voxel = Number(opt('--voxel', 0)) || (def.bake?.voxel ?? 0.005) * (quick ? 1.6 : 1);
  const tris = Number(opt('--tris', 0)) || (def.bake?.tris ?? 20000);
  const hash = hashInputs(id, { voxel, tris });
  const jsonPath = path.join(OUT, id + '.json');
  if (!flag('--force') && fs.existsSync(jsonPath)) {
    try {
      const old = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
      if (old.hash === hash && fs.existsSync(path.join(OUT, id + '.bin'))) { log(`${id}: up to date (${old.stats.tris} tris)`); return false; }
    } catch { /* rebake */ }
  }
  const T0 = Date.now();
  log(`${id}: baking (voxel ${(voxel * 1000).toFixed(1)} mm, budget ${tris} tris)`);
  const pool = new Pool({ id, bust }, Number(opt('--threads', 0)) || undefined);
  const scene = buildScene(def);
  await pool.ready;
  log(`  scene + ${pool.n} workers ready: ${Date.now() - T0} ms`);
  try {
    const { R, sd, partSds, segments } = scene;
    const body = await bakeTree(sd, def, { voxel, tris, log, pool, treeName: 'body', skin: { R, segments }, flags: def.bake?.flags });

    // Morph targets (expressions): vertices mostly bound to the morph bone.
    const morphs = [];
    const buffers = {};
    const boneIdx = R.bones.indexOf(def.morphBone || 'head');
    if (def.expressions && def.expressions.length && boneIdx >= 0) {
      const mask = new Uint8Array(body.n);
      for (let i = 0; i < body.n; i++) {
        let w = 0;
        for (let k = 0; k < 4; k++) if (body.skinIndex[i * 4 + k] === boneIdx) w += body.skinWeight[i * 4 + k];
        mask[i] = w > 128 ? 1 : 0;
      }
      // linear base colors (exactly what the runtime decodes) for morph color deltas
      const lin = new Float32Array(body.n * 3);
      for (let i = 0; i < body.n * 3; i++) { const c = body.col[i] / 255; lin[i] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
      const res = await Promise.all(def.expressions.map((ex) => pool.run({ type: 'morph', tree: 'expr:' + ex, pos: body.pos, nrm: body.nrm, mask, col: lin, maxMove: def.bake?.morphMax ?? 0.03 })));
      def.expressions.forEach((ex, i) => {
        const mt = res[i];
        const big = body.n > 65535;
        buffers[`morph_${ex}_ids`] = big ? new Uint32Array(mt.ids) : new Uint16Array(mt.ids);
        buffers[`morph_${ex}_dp`] = { array: new Int16Array(Array.from(mt.dp, (x) => Math.round(x * 20000))), itemSize: 3 };
        buffers[`morph_${ex}_dn`] = { array: new Int8Array(Array.from(mt.dn, (x) => Math.max(-127, Math.min(127, Math.round(x * 63))))), itemSize: 3 };
        let nc = 0;
        for (let k = 0; k < mt.dc.length; k += 3) if (mt.dc[k] || mt.dc[k + 1] || mt.dc[k + 2]) nc++;
        if (nc) buffers[`morph_${ex}_dc`] = { array: new Int16Array(Array.from(mt.dc, (x) => Math.max(-32767, Math.min(32767, Math.round(x * 32767))))), itemSize: 3 };
        morphs.push(ex);
        log(`  morph '${ex}': ${mt.ids.length} verts (${nc} recolored)`);
      });
    }
    const stitches = projectStitches(sd.stitches, sd.root);
    const put = (prefix, m) => {
      buffers[prefix + 'pos'] = { array: m.qpos, itemSize: 3, normalized: true };
      buffers[prefix + 'nrm'] = { array: m.nrm8, itemSize: 3, normalized: true };
      buffers[prefix + 'col'] = { array: m.col, itemSize: 3, normalized: true };
      buffers[prefix + 'aux'] = { array: m.aux, itemSize: 4 };
      buffers[prefix + 'pco'] = { array: m.pco, itemSize: 3 };
      buffers[prefix + 'pw'] = { array: m.pw, itemSize: 4, normalized: true };
      buffers[prefix + 'flow'] = { array: m.flow, itemSize: 4, normalized: true };
      if (m.skinIndex) {
        buffers[prefix + 'skinIndex'] = { array: m.skinIndex, itemSize: 4 };
        buffers[prefix + 'skinWeight'] = { array: m.skinWeight, itemSize: 4, normalized: true };
      }
      buffers[prefix + 'index'] = m.n > 65535 ? m.index : new Uint16Array(m.index);
    };
    put('', body);
    const parts = {};
    for (const [name, p] of Object.entries(def.parts || {})) {
      log(` part '${name}':`);
      const m = await bakeTree(partSds[name], def, { voxel: p.voxel || voxel * 0.8, tris: p.tris || 600, log, pool, treeName: 'part:' + name, skin: null });
      put(`part_${name}_`, m);
      const c = [0, 1, 2].map((k) => m.qbox[k] + m.qbox[k + 3] / 2);
      parts[name] = { bone: p.bone || 'head', qbox: m.qbox, pivot: p.pivot || c, tris: m.stats.tris };
    }
    const header = {
      id, version: VERSION, hash, kind: def.kind || 'hero', bones: R.bones, parents: R.parents, bindPose: R.bindPose,
      rig: R.humanoid ? R.rig.spec : def.rig, humanoid: R.humanoid,
      materials: def.materials, matNames: Object.keys(def.materials), qbox: body.qbox, morphs, parts,
      stitches: stitches.map((s) => [...s.a, ...s.b, s.t0, s.width, s.dash, s.duty, s.color, s.mats]),
      stitchChunks: stitchChunks(stitches),
      stats: {
        tris: body.stats.tris + Object.values(parts).reduce((a, p) => a + p.tris, 0), bodyTris: body.stats.tris, verts: body.n,
        rawTris: body.stats.rawTris, voxel, bakeMs: Date.now() - T0, stitchSegs: stitches.length,
      },
    };
    const bin = encodeBaked(header, buffers);
    fs.mkdirSync(OUT, { recursive: true });
    fs.writeFileSync(path.join(OUT, id + '.bin'), bin);
    fs.writeFileSync(jsonPath, JSON.stringify({ ...header, stitches: `${stitches.length} segments` }, null, 1));
    log(`${id}: done in ${((Date.now() - T0) / 1000).toFixed(1)} s -> ${header.stats.tris} tris (${body.n} verts), ${(bin.length / 1024).toFixed(0)} KB`);
  } finally {
    pool.close();
  }
  return true;
}

function writeRegistry() {
  const bins = fs.readdirSync(OUT).filter((f) => f.endsWith('.bin')).map((f) => f.slice(0, -4)).sort();
  const js = `// GENERATED by tools/bake/bake.mjs -- do not edit. Baked character data (esbuild '.bin': 'binary' loader).\n` +
    bins.map((b) => `import ${b.replace(/\W/g, '_')} from './${b}.bin';`).join('\n') +
    `\n\nexport default { ${bins.map((b) => `${JSON.stringify(b)}: ${b.replace(/\W/g, '_')}`).join(', ')} };\n`;
  fs.writeFileSync(path.join(OUT, 'registry.js'), js);
}

(async () => {
  await MeshoptSimplifier.ready;
  let ids = argv.filter((a, i) => !a.startsWith('--') && !['--voxel', '--tris', '--threads'].includes(argv[i - 1]));
  if (flag('--all')) ids = fs.readdirSync(CHARS).filter((f) => f.endsWith('.js') && !f.startsWith('_') && f !== 'index.js').map((f) => f.slice(0, -3));
  if (!ids.length) { console.log('usage: node tools/bake/bake.mjs <id...> | --all [--force] [--quick]'); process.exit(1); }
  for (const id of ids) await bakeChar(id);
  writeRegistry();
})().catch((e) => { console.error(e); process.exit(1); });
