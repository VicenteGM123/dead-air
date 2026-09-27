// Rig construction shared by the baker (Node) and the runtime (browser).
//   buildRig(def) -> { rig, bones: [names], joints: {name: Object3D}, humanoid, bindPose, segments, skin }
//   applyBindPose(R) / resetPose(R): put the joints in the sculpt (bind) pose or back to rest.
//   jointFrames(R) -> { name: { matrix: Matrix4 (bind world), pos: [x,y,z] } }   (root at identity)
// Humanoids use src/core/rig.js createRig(def.rig) unchanged, so the engine Animator drives them. Custom rigs:
//   def.rig = { custom: true, joints: [{ name, parent, pos:[x,y,z] (relative to parent), tail:[x,y,z] (segment end,
//   relative), blend, gate }], bindPose }.
// Bind pose: Euler XYZ rotations per joint applied on top of rest (default: arms out ~35 deg = A-pose).

import * as THREE from 'three';
import { createRig } from '../core/rig.js';

export const HUMANOID_JOINTS = ['hips', 'spine', 'chest', 'neck', 'head', 'shoulderL', 'elbowL', 'handL', 'shoulderR', 'elbowR',
  'handR', 'hipL', 'kneeL', 'footL', 'hipR', 'kneeR', 'footR'];

export const DEFAULT_BIND = { shoulderL: [0, 0, -0.62], shoulderR: [0, 0, 0.62] };

// Joint blend half-width (m) with the parent bone, and gate radius for the parent-side blend (see CHARKIT.md).
const HUMANOID_SKIN = {
  hips: { blend: 0, gate: 0.3 },
  spine: { blend: 0.07, gate: 0.35 },
  chest: { blend: 0.08, gate: 0.35 },
  neck: { blend: 0.035, gate: 0.085 },
  head: { blend: 0.03, gate: 0.12 },
  shoulderL: { blend: 0.06, gate: 0.1 }, shoulderR: { blend: 0.06, gate: 0.1 },
  elbowL: { blend: 0.05, gate: 0.08 }, elbowR: { blend: 0.05, gate: 0.08 },
  handL: { blend: 0.03, gate: 0.065 }, handR: { blend: 0.03, gate: 0.065 },
  hipL: { blend: 0.07, gate: 0.13 }, hipR: { blend: 0.07, gate: 0.13 },
  kneeL: { blend: 0.06, gate: 0.1 }, kneeR: { blend: 0.06, gate: 0.1 },
  footL: { blend: 0.035, gate: 0.09 }, footR: { blend: 0.035, gate: 0.09 },
};

export function buildRig(def) {
  const spec = def.rig || {};
  let rig, bones, humanoid;
  const skin = {};
  if (!spec.custom) {
    rig = createRig(spec);
    bones = HUMANOID_JOINTS.slice();
    humanoid = true;
    Object.assign(skin, HUMANOID_SKIN, def.skin || {});
  } else {
    humanoid = false;
    const joints = {};
    const root = new THREE.Group();
    root.name = 'rig';
    bones = [];
    for (const j of spec.joints) {
      const o = new THREE.Object3D();
      o.name = j.name;
      o.position.set(...(j.pos || [0, 0, 0]));
      (j.parent ? joints[j.parent] : root).add(o);
      joints[j.name] = o;
      bones.push(j.name);
      skin[j.name] = { blend: j.blend ?? 0.05, gate: j.gate ?? 0.1 };
    }
    const base = new Map();
    for (const n of bones) base.set(joints[n], joints[n].position.clone());
    rig = { root, joints, dims: spec.dims || {}, spec, base, attach(joint, obj) { (typeof joint === 'string' ? joints[joint] : joint).add(obj); return obj; } };
  }
  const bindPose = spec.bindPose || def.bindPose || (humanoid ? DEFAULT_BIND : {});
  const R = { rig, bones, joints: rig.joints, humanoid, bindPose, skin, def };
  R.parents = {};
  for (const n of bones) {
    const p = rig.joints[n].parent;
    R.parents[n] = p && bones.includes(p.name) ? p.name : null;
  }
  return R;
}

export function applyBindPose(R) {
  for (const n of R.bones) R.joints[n].rotation.set(0, 0, 0);
  for (const [n, e] of Object.entries(R.bindPose)) if (R.joints[n]) R.joints[n].rotation.set(e[0], e[1], e[2]);
  R.rig.root.position.set(0, 0, 0);
  R.rig.root.rotation.set(0, 0, 0);
  R.rig.root.scale.set(1, 1, 1);
  R.rig.root.updateMatrixWorld(true);
}

export function resetPose(R) {
  for (const n of R.bones) R.joints[n].rotation.set(0, 0, 0);
  R.rig.root.updateMatrixWorld(true);
}

// Bind-pose world frames and bone segments [P0, P1] used for skinning.
export function jointFrames(R) {
  applyBindPose(R);
  const out = {};
  const v = new THREE.Vector3();
  for (const n of R.bones) {
    const j = R.joints[n];
    out[n] = { matrix: j.matrixWorld.clone(), pos: j.getWorldPosition(v).toArray() };
  }
  // Segments
  const seg = {};
  const P = (n) => new THREE.Vector3(...out[n].pos);
  const local = (n, t) => new THREE.Vector3(...t).applyMatrix4(out[n].matrix);
  if (R.humanoid) {
    const D = R.rig.dims;
    const hipsP = P('hips');
    seg.hips = [hipsP.clone().add(new THREE.Vector3(0, -0.1, 0)), P('spine')];
    seg.spine = [P('spine'), P('chest')];
    seg.chest = [P('chest'), P('neck')];
    seg.neck = [P('neck'), P('head')];
    seg.head = [P('head'), local('head', [0, D.headH * 0.75, 0])];
    for (const s of ['L', 'R']) {
      seg['shoulder' + s] = [P('shoulder' + s), P('elbow' + s)];
      seg['elbow' + s] = [P('elbow' + s), P('hand' + s)];
      seg['hand' + s] = [P('hand' + s), local('hand' + s, [0, -0.12, 0])];
      seg['hip' + s] = [P('hip' + s), P('knee' + s)];
      seg['knee' + s] = [P('knee' + s), P('foot' + s)];
      seg['foot' + s] = [P('foot' + s), local('foot' + s, [0, -0.05, -0.15])];
    }
  } else {
    for (const j of R.def.rig.joints) {
      const kids = R.def.rig.joints.filter((c) => c.parent === j.name);
      const tail = j.tail ? local(j.name, j.tail) : kids.length ? P(kids[0].name) : local(j.name, [0, 0.1, 0]);
      seg[j.name] = [P(j.name), tail];
    }
  }
  const segments = {};
  for (const [n, [a, b]] of Object.entries(seg)) segments[n] = { a: a.toArray(), b: b.toArray() };
  resetPose(R);
  return { frames: out, segments };
}
