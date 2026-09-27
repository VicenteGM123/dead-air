// EXAMPLE (kit test, not final art): a sock puppet on a custom 5-joint chain, showing the non-humanoid path —
// custom rig, zombie kind (cyan rim, ZOMBIES layer), cylindrical stripe pattern, eyes, custom animator.
// The zombie artist replaces this with the real Sock Hopper (GDD §8.2).
import { EYE_DEFAULTS } from './_face.js';

const SEG = 0.13;
const EYE = { ...EYE_DEFAULTS, x: 0.045, y: 0.07, z: -0.08, r: 0.034, iris: '#1E1622', irisSize: 0.5, pupilSize: 0.7, lid: '#F4F1E8', lidOpen: 0.8, lowerLid: 0.1 };

export default {
  id: 'example_sock',
  name: 'Sock (kit example)',
  kind: 'zombie',
  rig: {
    custom: true,
    joints: [
      { name: 'root', parent: null, pos: [0, 0.02, 0], tail: [0, SEG, 0], blend: 0.05, gate: 0.2 },
      { name: 's1', parent: 'root', pos: [0, SEG, 0], blend: 0.05, gate: 0.2 },
      { name: 's2', parent: 's1', pos: [0, SEG, 0], blend: 0.05, gate: 0.2 },
      { name: 's3', parent: 's2', pos: [0, SEG, 0], blend: 0.05, gate: 0.2 },
      { name: 'head', parent: 's3', pos: [0, SEG, 0], tail: [0, 0.12, -0.05], blend: 0.05, gate: 0.2 },
    ],
    bindPose: {},
  },
  bake: { voxel: 0.005, tris: 3500 },
  materials: {
    sock: { color: '#ffffff', rough: 0.8, fuzz: 0.5, pattern: { type: 'stripes', colors: ['#E23B3B', '#F4F1E8', '#F4E03A', '#F4F1E8', '#3A58E4', '#F4F1E8'], widths: [1, 1, 1, 1, 1, 1], vertical: false, scale: 0.18 } },
    mouth: { color: '#3B2340', rough: 0.6 },
  },
  slots: { head: { joint: 'head', pos: [0, 0.14, 0] } },
  sculpt(sd) {
    const fr = sd.patternFrame({ pos: [0, 0.3, 0], mode: 'cyl', radius: 0.1 });
    sd.group({ mat: 'sock', k: 0.03, pframe: fr, bone: 'auto' }, () => {
      sd.worm({ pts: [[0, 0.03, 0.02], [0, 0.2, 0.0], [0, 0.4, 0.0], [0, 0.58, -0.04], [0, 0.66, -0.12]], r: [0.11, 0.1, 0.095, 0.09, 0.07], segs: 20 });
      sd.plane({ op: 'int', k: 0.01, n: [0, -1, 0], d: -0.02 });
    });
    sd.ellipsoid({ op: 'sub', k: 0.01, cutMat: 'mouth', pos: [0, 0.6, -0.14], r: [0.07, 0.02, 0.06], rot: [0.5, 0, 0] });
  },
  attachments(b) { b.eyes(EYE); },
  createAnimator(rig) {
    const J = rig.joints;
    let t = Math.random() * 10;
    return {
      update(dt, st = {}) {
        t += dt;
        const hop = Math.abs(Math.sin(t * (st.speed ? 7 : 3)));
        rig.root.position.y = hop * (st.speed ? 0.12 : 0.03);
        for (const n of ['s1', 's2', 's3', 'head']) { J[n].rotation.x = Math.sin(t * 5 + n.length) * 0.12 - (st.speed ? 0.08 : 0); J[n].rotation.z = Math.sin(t * 3.1 + n.length) * 0.06; }
      },
    };
  },
};
