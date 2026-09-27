// Loads a character definition and builds its SDF trees (main thread and bake workers build identical scenes).
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { createSculptor, compileTree, indexLeaves } from '../../src/art/sdf.js';
import { buildRig, jointFrames } from '../../src/art/rigBuild.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(__dirname, '../..');
export const CHARS = path.join(ROOT, 'src/art/chars');

export async function loadDef(id, bust = '') {
  const defPath = path.join(CHARS, id + '.js');
  if (!fs.existsSync(defPath)) throw new Error(`no character definition ${defPath}`);
  return (await import(pathToFileURL(defPath).href + (bust ? '?t=' + bust : ''))).default;
}

export function buildTree(def, ctx, expr, sculptFn) {
  const sd = createSculptor({ joints: ctx.J, materials: def.materials, expr });
  (sculptFn || def.sculpt)(sd, { ...ctx, expr });
  compileTree(sd.root);
  sd.leaves = indexLeaves(sd.root);
  return sd;
}

export function buildScene(def) {
  const R = buildRig(def);
  const { frames, segments } = jointFrames(R);
  const ctx = { J: frames, dims: R.rig.dims, spec: R.rig.spec, R, segments };
  if (def.anchors) ctx.A = def.anchors(ctx);
  const sd = buildTree(def, ctx, null);
  const partSds = {};
  for (const [name, p] of Object.entries(def.parts || {})) partSds[name] = buildTree(def, ctx, null, p.sculpt);
  const aoRoot = compileTree({ kind: 'group', op: 'add', k: 0, name: 'ao', id: -1, children: [{ ...sd.root, op: 'add', k: 0 }, ...Object.values(partSds).map((s) => ({ ...s.root, op: 'add', k: 0 }))] });
  return { def, R, ctx, sd, partSds, aoRoot, segments };
}

// Tree selector by name (used by workers): 'body' | 'part:<name>' | 'ao' | 'expr:<name>'
export function treeByName(scene, name, cache) {
  if (cache.has(name)) return cache.get(name);
  let t;
  if (name === 'body') t = scene.sd.root;
  else if (name === 'ao') t = scene.aoRoot;
  else if (name.startsWith('part:')) t = scene.partSds[name.slice(5)].root;
  else if (name.startsWith('expr:')) t = buildTree(scene.def, scene.ctx, name.slice(5)).root;
  cache.set(name, t);
  return t;
}
