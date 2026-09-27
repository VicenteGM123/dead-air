#!/usr/bin/env node
// Silhouette probe for a character definition (no bake): prints the front (max |x|) and side (min/max z) extents
// of the SDF per height, in a joint's local frame. Handy to tune big shapes (hair, collars) numerically.
//   node tools/bake/profile.mjs duke [--joint head] [--y0 0] [--y1 0.62] [--step 0.02]
import { loadDef, buildScene } from './scene.mjs';
import * as THREE from 'three';
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const id = argv.find((a) => !a.startsWith('--') && !['--joint', '--y0', '--y1', '--step'].includes(argv[argv.indexOf(a) - 1])) || 'duke';
const def = await loadDef(id, String(Date.now()));
const scene = buildScene(def);
const joint = opt('--joint', 'head');
const M = scene.ctx.J[joint].matrix;
const f = scene.sd.root.fn;
const y0 = Number(opt('--y0', 0)), y1 = Number(opt('--y1', 0.62)), st = Number(opt('--step', 0.02));
const v = new THREE.Vector3();
const inside = (x, y, z) => { v.set(x, y, z).applyMatrix4(M); return f(v.x, v.y, v.z) < 0; };
console.log(`${id} silhouette in '${joint}' frame (m): y | front half-width | side zmin..zmax`);
for (let y = y1; y >= y0 - 1e-9; y -= st) {
  let xw = -1, zmin = 9, zmax = -9;
  for (let x = 0; x <= 0.4; x += 0.004) for (let z = -0.4; z <= 0.4; z += 0.004) if (inside(x, y, z)) { if (x > xw) xw = x; if (z < zmin) zmin = z; if (z > zmax) zmax = z; }
  console.log(`${y.toFixed(3)} | ${xw < 0 ? '-' : xw.toFixed(3)} | ${zmin > 8 ? '-' : zmin.toFixed(3) + '..' + zmax.toFixed(3)}`);
}
