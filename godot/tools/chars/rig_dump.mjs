// chars-godot QA: reference dump for tools/chars/rig_compare.gd. Runs the ORIGINAL src/core/rig.js (three.js) on
// scripted animator states (4 styles x 3 rig specs x 240 frames) and writes joint world matrices.
//   node tools/chars/rig_dump.mjs /abs/rig_ref.json
import * as THREE from '/home/user/dead-air/node_modules/three/build/three.module.js';
import { createRig, Animator, registerPose } from '/home/user/dead-air/src/core/rig.js';

registerPose('testpose', { head: [0.3, -0.2, 0.1], shoulderL: [1.2, 0.3, -0.4], kneeR: [-0.8, 0, 0] });
let s = 12345;
const rnd = () => { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648; };
const R = (a, b) => a + (b - a) * rnd();
const rigs = [
  {},
  { height: 1.80, headScale: 1.3, shoulderW: 0.44, hipW: 0.27, legLen: 0.82, torsoLen: 0.46, armLen: 0.55 },
  { height: 1.56, headScale: 1.34, shoulderW: 0.44, hipW: 0.28, legLen: 0.7, torsoLen: 0.5 },
];
const styles = ['hero', 'zombie', 'puppet', { base: 'zombie', arms: 'swing', headLag: 1.2, cycle: 1.05, legSwing: 0.36, knee: 0.4, bob: 0.04 }];
const scenarios = [];
let id = 0;
for (let si = 0; si < styles.length; si++) for (let ri = 0; ri < rigs.length; ri++) {
  const frames = [];
  const N = 240;
  for (let f = 0; f < N; f++) {
    const ph = f / N;
    const st = { speed: Math.max(0, Math.sin(ph * 7) * 5), grounded: !(f > 60 && f < 80), turn: Math.sin(ph * 5) * 2 };
    if (f > 100 && f < 170) { st.aiming = true; st.aimPitch = Math.sin(ph * 9) * 0.6; st.aimYaw = Math.cos(ph * 4) * 0.4; }
    if (f > 110 && f < 130) st.recoil = 1 - (f - 110) / 20;
    if (f > 130 && f < 160) st.reload = (f - 130) / 30;
    if (f > 170 && f < 190) st.melee = (f - 170) / 20;
    if (f > 60 && f < 90) st.attack = (f - 60) / 30;
    if (f > 30 && f < 50) st.hurt = 1 - (f - 30) / 20;
    if (f > 190 && f < 205) st.climb = (f - 190) / 15;
    if (f > 205 && f < 220) st.dance = 1;
    if (f > 150 && f < 165) st.back = true;
    if (f > 180 && f < 200) st.legYaw = 0.5;
    if (f > 220 && f < 230) st.down = true;
    if (f >= 230) st.dead = (f - 230) / 8;
    const poses = {};
    if (f === 20) poses.point = 0.5;
    if (f === 50) poses.shoulder = 1;
    if (f === 90) { poses.point = 0; poses.testpose = 0.7; }
    if (f === 120) poses.fingerguns = 0.3;
    if (f === 200) { poses.shoulder = 0; poses.testpose = 0; poses.fingerguns = 0; }
    frames.push({ dt: f % 17 === 0 ? 0.05 : 1 / 60 + (f % 5) * 0.002, st, poses, kick: f === 40 ? 0.8 : 0, override: f >= 140 && f < 150 });
  }
  const rand = { seed: R(0, 1000), phase: R(0, 6.28), t: R(0, 10), wob: { amp: R(0.75, 1.25), tilt: R(-0.17, 0.17), armL: R(-0.2, 0.2), armR: R(-0.2, 0.2), speed: R(0.85, 1.15) } };
  scenarios.push({ id: id++, style: styles[si], rig: rigs[ri], rand, frames, groupYaw: R(-3, 3), groupPos: [R(-5, 5), 0, R(-5, 5)] });
}
const out = [];
const m = new THREE.Matrix4();
for (const sc of scenarios) {
  const rig = createRig(sc.rig);
  const group = new THREE.Group();
  group.rotation.y = sc.groupYaw;
  group.position.set(...sc.groupPos);
  group.add(rig.root);
  const a = new Animator(rig, sc.style);
  Object.assign(a, { seed: sc.rand.seed, phase: sc.rand.phase, t: sc.rand.t });
  Object.assign(a.wob, sc.rand.wob);
  const samples = [];
  sc.frames.forEach((fr, i) => {
    for (const [k, w] of Object.entries(fr.poses)) a.pose(k, w);
    if (fr.kick) a.kick(fr.kick);
    a.override = fr.override ? (r, dt) => { r.joints.head.rotation.y += 0.3; r.joints.chest.position.z += dt; } : null;
    a.update(fr.dt, fr.st);
    if (i % 3 === 0 || i > 225) {
      group.updateMatrixWorld(true);
      const mats = {};
      for (const [n, j] of Object.entries(rig.joints)) mats[n] = Array.from(j.matrixWorld.elements);
      mats.root = Array.from(rig.root.matrixWorld.elements);
      samples.push({ frame: i, mats, headLag: [a.headLag.x, a.headLag.z], phase: a.phase });
    }
  });
  out.push({ scenario: sc, samples, dims: rig.dims });
}
import fs from 'fs';
fs.writeFileSync(process.argv[2] || 'rig_ref.json', JSON.stringify(out));
console.log('scenarios', out.length, 'samples', out.reduce((a, o) => a + o.samples.length, 0));
