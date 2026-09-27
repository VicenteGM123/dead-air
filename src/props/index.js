// DEAD AIR — prop library entry (docs/PROPKIT.md). Re-exports the registry from kit.js, imports every category
// module (each registers its builders on import) and offers placeProp(), the bridge rooms use to drop a prop
// into the level with its colliders, light anchors and screens wired to the engine.
//
//   registerProp(id, build(game, opts) -> Group, meta:{category, tags, size, desc, cache, hero})
//   buildProp(id, game, opts) -> Group (PROP RESULT CONVENTION, see kit.js header)
//   listProps(category?) -> [{id, category, tags, size, desc}]     propMeta(id)
//   placeProp(game, parent, id, { pos:[x,y,z], rotY=0, opts, area, colliders=true, lights=true, screens=true,
//             tag='prop' }) -> Group   (world colliders are the AABBs of the rotated local boxes)
//   registerScene / getScene / listScenes — set-dressing test scenes for tools/propview

import * as THREE from 'three';
import { buildProp } from './kit.js';
import './broadcast.js';
import './furniture.js';
import './sets.js';
import './weapons.js';
import './machines.js';
import './sponsors.js';
import './outdoor.js';
import './_samples.js';

export { registerProp, buildProp, listProps, propMeta, registerScene, getScene, listScenes, cloneProp } from './kit.js';

const _v = new THREE.Vector3();

export function placeProp(game, parent, id, o = {}) {
  const { pos = [0, 0, 0], rotY = 0, opts = {}, area = null, colliders = true, lights = true, screens = true, tag = 'prop' } = o;
  const g = buildProp(id, game, opts);
  g.position.set(pos[0], pos[1] ?? 0, pos[2]);
  g.rotation.y = rotY;
  parent.add(g);
  g.updateMatrixWorld(true);
  const u = g.userData;
  if (colliders && game.level?.col) {
    const bb = new THREE.Box3();
    for (const c of u.colliders) {
      bb.makeEmpty();
      for (let i = 0; i < 8; i++) {
        _v.set(i & 1 ? c.max[0] : c.min[0], i & 2 ? c.max[1] : c.min[1], i & 4 ? c.max[2] : c.min[2]).applyMatrix4(g.matrixWorld);
        bb.expandByPoint(_v);
      }
      game.level.col.addBox(bb.min.toArray(), bb.max.toArray(), { tag, ...(c.opts || {}) });
    }
  }
  if (lights && game.lights?.addAnchor) {
    for (const a of u.lightAnchors) {
      _v.fromArray(a.pos).applyMatrix4(g.matrixWorld);
      game.lights.addAnchor({ ...a, pos: _v.toArray(), area: a.area ?? area });
    }
  }
  if (screens && game.screens?.register) for (const s of u.screens) game.screens.register(s.mesh, s.group || 'scr_decor', s.id ? { id: s.id } : {});
  return g;
}
