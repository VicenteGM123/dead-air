// chars-godot QA: Node dump of the ORIGINAL JS character runtime (charRuntime.buildCharacter) for
// tools/chars/char_compare.gd. Bundled by char_dump_build.mjs into char_dump.mjs (esbuild, .bin baked assets).
//   node char_dump.mjs <id> <out.json> <state.json>
// Canvas is stubbed (attachments' textures are irrelevant for transforms).
const ctxStub = new Proxy({}, { get: (t, k) => (k === 'createImageData' ? (w, h) => ({ data: new Uint8ClampedArray(w * h * 4), width: w, height: h }) : k === 'measureText' ? () => ({ width: 10 }) : k === 'createLinearGradient' || k === 'createRadialGradient' ? () => ({ addColorStop() {} }) : typeof k === 'string' ? (t[k] ?? (() => {})) : undefined), set: (t, k, v) => { t[k] = v; return true; } });
globalThis.document = { createElement: () => ({ width: 1, height: 1, getContext: () => ctxStub, style: {} }) };
globalThis.window = globalThis;
import * as THREE from 'three';
import { buildCharacter, getDef } from '/home/user/dead-air/src/art/charRuntime.js';
import sockDef from '/home/user/dead-air/src/art/chars/z_sock.js';
import bsDef from '/home/user/dead-air/src/art/chars/z_bigshot.js';
import fcDef from '/home/user/dead-air/src/art/chars/z_forecaster.js';
import baronDef from '/home/user/dead-air/src/art/chars/boss_baron.js';
import fs from 'fs';
const extra = { z_sock: sockDef, z_bigshot: bsDef, z_forecaster: fcDef, boss_baron: baronDef };
const [,, id, out, stateJson] = process.argv;
const def = getDef(id) || extra[id];
const c = buildCharacter(def, { merge: false, heroFade: true, animator: def.createAnimator && !def.rig.custom ? undefined : undefined });
const st = stateJson ? JSON.parse(fs.readFileSync(stateJson, 'utf8')) : { frames: [] };
const a = c.animator;
if (a && a.wob) { Object.assign(a, { seed: 1.5, phase: 0.7, t: 2.0 }); Object.assign(a.wob, { amp: 1.1, tilt: 0.05, armL: 0.1, armR: -0.08, speed: 0.95 }); }
const face = c.face;
face.auto = false; face.blinkT = 99;
for (const fr of st.frames) {
  if (fr.expr) face.setExpression(fr.expr[0], fr.expr[1]);
  if (fr.look) face.setLook(fr.look[0], fr.look[1]);
  if (fr.blink) face.blink();
  for (const [k, w] of Object.entries(fr.poses || {})) a.pose(k, w);
  c.update(fr.dt, fr.st);
}
const root = c.group;
root.position.set(0.3, 0, -0.2); root.rotation.y = 0.4;
root.updateMatrixWorld(true);
const mats = {};
root.traverse((o) => { if (o.name && !o.isMesh) mats[o.name] = Array.from(o.matrixWorld.elements); });
const mesh = c.skinnedMesh;
const n = mesh.geometry.attributes.position.count;
const verts = [];
const v = new THREE.Vector3();
const P = mesh.geometry.attributes.position;
for (let i = 0; i < n; i += 37) { mesh.getVertexPosition(i, v); v.applyMatrix4(mesh.matrixWorld); verts.push([i, v.x, v.y, v.z, P.getX(i), P.getY(i), P.getZ(i)]); }
const infl = mesh.morphTargetInfluences ? Array.from(mesh.morphTargetInfluences) : [];
const eyes = face.eyes.map((e) => ({ side: e.side, upper: e.upper.rotation.x, lower: e.lower.rotation.x, ball: [e.ball.rotation.x, e.ball.rotation.y] }));
const brows = face.brows.map((b) => ({ side: b.side, y: b.mesh.position.y, rz: b.mesh.rotation.z }));
fs.writeFileSync(out, JSON.stringify({ id, mats, verts, infl, eyes, brows, dims: c.rig.dims, hairBounds: c.hairBounds, slotNames: Object.keys(c.slots) }));
console.log('dumped', id, 'verts', verts.length, 'nodes', Object.keys(mats).length);
