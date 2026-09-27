// Bake worker: builds the character scene once, then serves tasks (surface-net blocks, sampling, shading, morphs).
import { parentPort, workerData } from 'worker_threads';
import { loadDef, buildScene, treeByName } from './scene.mjs';
import { processBlocks } from './mesher.mjs';
import { sampleBatch } from './attrib.mjs';
import { makeRegionTrees, shadeVertices, morphTarget } from './finish.mjs';
import { makeSampler } from '../../src/art/sdf.js';

const def = await loadDef(workerData.id, workerData.bust);
const scene = buildScene(def);
const cache = new Map();
const regionCache = new Map();
const sampler = makeSampler(def.materials);

parentPort.on('message', ({ id, task }) => {
  try {
    let result, transfer = [];
    const tree = task.tree ? treeByName(scene, task.tree, cache) : null;
    if (task.type === 'blocks') {
      result = processBlocks(tree, task.grid, task.blocks);
      transfer = [result.corners.buffer, result.cells.buffer, result.verts.buffer, result.counts.buffer];
    } else if (task.type === 'sample') {
      result = sampleBatch(tree, sampler, task.positions, task.voxel);
      transfer = Object.values(result).map((a) => a.buffer);
    } else if (task.type === 'shade') {
      let rt = regionCache.get(task.tree);
      if (!rt) { rt = makeRegionTrees(tree, 0.08, task.opts.aoReach ?? 0.16); regionCache.set(task.tree, rt); }
      const n = task.positions.length / 3;
      result = shadeVertices(task.positions, n, rt, task.opts);
      transfer = [result.nrm.buffer, result.ao.buffer, result.cav.buffer];
    } else if (task.type === 'morph') {
      const rt = makeRegionTrees(tree, 0.08, 0.06);
      const n = task.pos.length / 3;
      const bt = makeRegionTrees(treeByName(scene, 'body', cache), 0.08, 0.06);
      const m = morphTarget(task.pos, task.nrm, n, rt, task.mask, task.maxMove, bt, task.col || null, sampler);
      result = { ids: new Int32Array(m.ids), dp: new Float32Array(m.dp), dn: new Float32Array(m.dn), dc: new Float32Array(m.dc) };
      transfer = [result.ids.buffer, result.dp.buffer, result.dn.buffer, result.dc.buffer];
    } else throw new Error('unknown task ' + task.type);
    parentPort.postMessage({ id, result }, transfer);
  } catch (e) {
    parentPort.postMessage({ id, error: e.stack || String(e) });
  }
});
parentPort.postMessage({ ready: true });
