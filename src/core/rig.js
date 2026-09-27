// Character rig + procedural cartoon animator (ARCHITECTURE §8/§12, GDD §3.6).
//
// createRig(spec) -> { root, joints, dims, spec, attach(joint, obj) }. Feet at y=0, facing -z. Joint names:
//   hips, spine, chest, neck, head, shoulderL, elbowL, handL, shoulderR, elbowR, handR, hipL, kneeL, footL,
//   hipR, kneeR, footR. The head keeps its size (0.44 m x headScale); legs and torso are scaled to fit height.
//   Rotation conventions (radians): shoulder/hip.x > 0 swings the limb forward (-z), knee.x < 0 bends back,
//   elbow.x > 0 bends forward, spine.x < 0 leans forward, root faces -z.
// new Animator(rig, style) with style 'hero' | 'zombie' | 'puppet' | { ...params } (merged over 'hero', or over
//   STYLES[params.base]). animator.update(dt, state) with state = { speed, sprint, grounded, aimPitch, aimYaw,
//   aiming, recoil, reload, melee, hurt, climb, attack, dance, down, dead } plus optional extras:
//   back (walking backwards), turn (yaw rate rad/s), legYaw (strafe: legs turned toward movement, radians).
//   animator.override = fn(rig, dt) | null runs after the procedural pose; animator.pose(name, weight) blends a
//   named static pose from POSES (registerPose adds more); animator.kick(amount) = squash/head-spring impulse.
//   animator.headLag {x, z} exposes the head spring for hair/antenna secondary motion. Spring is exported too.

import * as THREE from 'three';

// Damped spring (GDD §3.6: k=120, damping 12). update(dt, target) -> x. Substepped for stability.
export class Spring {
  constructor(k = 120, d = 12, x = 0) {
    this.k = k; this.d = d; this.x = x; this.v = 0;
  }
  update(dt, target = 0) {
    const n = Math.max(1, Math.ceil(dt / (1 / 120)));
    const h = dt / n;
    for (let i = 0; i < n; i++) {
      this.v += (-this.k * (this.x - target) - this.d * this.v) * h;
      this.x += this.v * h;
    }
    return this.x;
  }
  kick(impulse) { this.v += impulse; }
  reset(x = 0) { this.x = x; this.v = 0; }
}

const JOINTS = ['hips', 'spine', 'chest', 'neck', 'head', 'shoulderL', 'elbowL', 'handL', 'shoulderR', 'elbowR',
  'handR', 'hipL', 'kneeL', 'footL', 'hipR', 'kneeR', 'footR'];

export function createRig(spec = {}) {
  const s = { height: 1.7, headScale: 1.0, shoulderW: 0.42, hipW: 0.26, armLen: 0.62, legLen: 0.78, torsoLen: 0.5, ...spec };
  const headH = 0.44 * s.headScale;
  const neckH = 0.05, ankle = 0.07, hipDrop = 0.03;
  const k = Math.max(0.5, (s.height - headH - neckH - ankle) / (s.legLen + s.torsoLen));
  const leg = s.legLen * k, torso = s.torsoLen * k;
  const arm = s.armLen * Math.min(1, k * 1.05);
  const dims = {
    height: s.height, headH, neckH, ankle, torso, leg, hipsY: leg + ankle,
    upperLeg: (leg - hipDrop) * 0.5, lowerLeg: (leg - hipDrop) * 0.5,
    upperArm: arm * 0.48, foreArm: arm * 0.52, shoulderW: s.shoulderW, hipW: s.hipW,
    shoulderY: torso * 0.55 - 0.06,
  };

  const j = {};
  for (const n of JOINTS) { j[n] = new THREE.Object3D(); j[n].name = n; }
  const root = new THREE.Group();
  root.name = 'rig';
  root.add(j.hips);
  j.hips.position.set(0, dims.hipsY, 0);
  j.hips.add(j.spine, j.hipL, j.hipR);
  j.spine.position.set(0, 0.02, 0);
  j.spine.add(j.chest);
  j.chest.position.set(0, torso * 0.45, 0);
  j.chest.add(j.neck, j.shoulderL, j.shoulderR);
  j.neck.position.set(0, torso * 0.55 - 0.02, 0);
  j.neck.add(j.head);
  j.head.position.set(0, neckH, 0);
  for (const side of ['L', 'R']) {
    const sx = side === 'L' ? -1 : 1;
    const sh = j['shoulder' + side], el = j['elbow' + side], ha = j['hand' + side];
    sh.position.set(sx * s.shoulderW / 2, dims.shoulderY, 0);
    sh.add(el); el.position.set(0, -dims.upperArm, 0);
    el.add(ha); ha.position.set(0, -dims.foreArm, 0);
    const hp = j['hip' + side], kn = j['knee' + side], ft = j['foot' + side];
    hp.position.set(sx * s.hipW / 2, -hipDrop, 0);
    hp.add(kn); kn.position.set(0, -dims.upperLeg, 0);
    kn.add(ft); ft.position.set(0, -dims.lowerLeg, 0);
  }

  const base = new Map();
  for (const n of JOINTS) base.set(j[n], j[n].position.clone());

  return {
    root, joints: j, dims, spec: s, base,
    attach(joint, obj) {
      (typeof joint === 'string' ? j[joint] : joint).add(obj);
      return obj;
    },
  };
}

export const STYLES = {
  hero: {
    cycle: 1.6, cycleK: 0.3, bob: 0.05, squash: 0.035, legSwing: 0.42, legRun: 0.4, knee: 0.55, arm: 0.55,
    armRun: 0.35, elbow: 0.35, lean: 0.1, twist: 0.13, sway: 0.035, breathe: 0.01, headLag: 1, arms: 'swing',
    alignHand: true, wobble: 0, randomPhase: false,
  },
  zombie: {
    cycle: 1.15, cycleK: 0.25, bob: 0.035, squash: 0.03, legSwing: 0.3, legRun: 0.32, knee: 0.3, arm: 0.12,
    armRun: 0.12, elbow: 0.12, lean: 0.22, twist: 0.06, sway: 0.13, breathe: 0.012, headLag: 1.4, arms: 'forward',
    alignHand: false, wobble: 1, randomPhase: true,
  },
  puppet: {
    cycle: 1.3, cycleK: 0.2, bob: 0.12, squash: 0.1, legSwing: 0.5, legRun: 0.3, knee: 0.8, arm: 0.9,
    armRun: 0.3, elbow: 0.6, lean: 0.05, twist: 0.15, sway: 0.08, breathe: 0.02, headLag: 2, arms: 'floppy',
    alignHand: false, wobble: 0.5, randomPhase: true,
  },
};

// Named static poses: joint -> [x, y, z] Euler (XYZ). Blended with animator.pose(name, weight).
// Heads are BIG (baked heroes: headScale 1.3 = 0.57 m, Roxy's afro ~0.72 m wide, Penny's hair curtains to the chest,
// arms only 0.43-0.5 m): every pose that lifts a hand keeps it OUT to the side. Shoulder z > 0 swings the RIGHT arm
// out (left arm: z < 0); with XYZ order a raised arm (x ~ PI) keeps that z lean, so a negative z on a raised right arm
// leans it in over the head (the old point / shoulder / wave went through the face). Clearance is measured per hero
// (tools/scenarios/fix3_poseview.js, surface to surface, incl. hair / afro / glasses / earrings, and through the
// menu's blend-in): point >= 6 cm, shoulder >= 8 cm, wave >= 6 cm, thumbsup >= 13 cm, fingerguns / shrug >= 10 cm.
export const POSES = {
  // disco point to the sky: right arm up and out (~48 deg from vertical, a little forward), clear of the afro; left
  // hand on the hip, hips kicked, torso and head leaning away from the arm, chin up toward the hand
  point: { shoulderR: [2.7, 0, 0.82], elbowR: [0.1, 0, 0], handR: [0, 1.3, 0], shoulderL: [-0.2, 0, -0.55], elbowL: [1.75, 0, 0],
    hips: [0, 0, 0.08], spine: [0, 0, 0.06], head: [0.25, -0.15, 0.1] },
  // double thumbs-up at chest height, hands apart (the old inward version put both hands in front of the chin)
  thumbsup: { shoulderR: [0.8, 0, 0.25], elbowR: [1.5, 0, 0], shoulderL: [0.8, 0, -0.25], elbowL: [1.5, 0, 0], head: [0.1, 0, 0.12] },
  fingerguns: { shoulderR: [1.45, 0, -0.25], elbowR: [0.25, 0, 0], shoulderL: [1.45, 0, 0.25], elbowL: [0.25, 0, 0], chest: [0, 0.2, 0] },
  // (wrench) on the shoulder: elbow out to the side at chest height, forearm folded back up, the hand resting palm-up
  // at the front of the shoulder beside the jaw (outside the hair curtain, not at the face); left hand on the hip
  shoulder: { shoulderR: [0.82, -0.53, 0.95], elbowR: [2.55, 0, 0], handR: [-0.9, 0.8, 0], shoulderL: [-0.2, 0, -0.55], elbowL: [1.75, 0, 0],
    head: [0.05, 0.1, 0.06] },
  shrug: { shoulderR: [0.4, 0, -0.9], elbowR: [1.5, 0, 0], shoulderL: [0.4, 0, 0.9], elbowL: [1.5, 0, 0], head: [0, 0, 0.2] },
  // upper arm out to the side and slightly up, forearm up: the hand waves beside the head, not over it
  wave: { shoulderR: [1.56, 0.29, 1.1], elbowR: [1.14, 0, 0] },
};
// Each hero's signature commercial pose (menu channels, the ending's freeze-frame, sponsors' double_vision).
POSES.commercial_skip = POSES.thumbsup;
POSES.commercial_roxy = POSES.point;
POSES.commercial_penny = POSES.shoulder;
POSES.commercial_duke = POSES.fingerguns;

export function registerPose(name, joints) {
  POSES[name] = joints;
}

const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _q3 = new THREE.Quaternion();
const _e = new THREE.Euler();
const easeOutBounce = (x) => {
  const n = 7.5625, d = 2.75;
  if (x < 1 / d) return n * x * x;
  if (x < 2 / d) return n * (x -= 1.5 / d) * x + 0.75;
  if (x < 2.5 / d) return n * (x -= 2.25 / d) * x + 0.9375;
  return n * (x -= 2.625 / d) * x + 0.984375;
};
const smooth = (a, b, x) => THREE.MathUtils.smoothstep(x, a, b);

export class Animator {
  constructor(rig, style = 'hero') {
    this.rig = rig;
    const custom = typeof style === 'object' ? style : null;
    const baseName = custom ? custom.base || 'hero' : style;
    this.p = { ...(STYLES[baseName] || STYLES.hero), ...(custom || {}) };
    this.seed = Math.random() * 1000;
    this.phase = this.p.randomPhase ? Math.random() * Math.PI * 2 : 0;
    this.t = this.p.randomPhase ? Math.random() * 10 : 0;
    this.move = 0;       // eased locomotion weight
    this.run = 0;        // eased run factor
    this.aimW = 0;
    this.air = 0;
    this.override = null;
    this._poses = new Map();
    this._grounded = true;
    this._hurt = 0;
    this.squash = new Spring(260, 15);
    this.headLag = { x: 0, z: 0 };
    this._lagX = new Spring(120, 12);
    this._lagZ = new Spring(120, 12);
    this._prevBob = 0;
    this._bobVel = 0;
    // Per-instance gait character (zombies shamble differently).
    this.wob = {
      amp: 1 + (Math.random() - 0.5) * 0.5 * this.p.wobble,
      tilt: (Math.random() - 0.5) * 0.35 * this.p.wobble,
      armL: (Math.random() - 0.5) * 0.4 * this.p.wobble,
      armR: (Math.random() - 0.5) * 0.4 * this.p.wobble,
      speed: 1 + (Math.random() - 0.5) * 0.3 * this.p.wobble,
    };
  }

  pose(name, weight = 1) {
    if (weight <= 0 || !POSES[name]) this._poses.delete(name);
    else this._poses.set(name, weight);
  }

  kick(amount = 1) {
    this.squash.kick(-3.2 * amount);
    this._lagX.kick(4 * amount);
  }

  update(dt, st = {}) {
    const p = this.p, J = this.rig.joints, D = this.rig.dims;
    this.t += dt;
    const t = this.t;
    const speed = st.speed || 0;
    const grounded = st.grounded !== false;
    const dn = 1 - Math.exp(-dt * 10);

    // Reset joints to rest.
    for (const [obj, pos] of this.rig.base) { obj.position.copy(pos); obj.rotation.set(0, 0, 0); }
    this.rig.root.rotation.set(0, 0, 0);
    this.rig.root.position.set(0, 0, 0);
    J.chest.scale.set(1, 1, 1);

    // Eased blend weights.
    const moving = grounded ? THREE.MathUtils.clamp(speed / 1.2, 0, 1) : 0;
    this.move += (moving - this.move) * dn;
    this.run += (THREE.MathUtils.clamp(speed / 4.6, 0, 1.5) - this.run) * dn;
    this.aimW += ((st.aiming ? 1 : 0) - this.aimW) * (1 - Math.exp(-dt * 14));
    this.air += ((grounded ? 0 : 1) - this.air) * (1 - Math.exp(-dt * 12));
    const w = this.move, run = this.run, air = this.air;

    // Landing / takeoff squash-stretch (GDD §3.6: 0.85 y / 1.1 xz over ~120 ms).
    if (grounded && !this._grounded) this.squash.kick(-3.4);
    if (!grounded && this._grounded) this.squash.kick(1.8);
    this._grounded = grounded;
    if ((st.hurt || 0) > this._hurt + 0.3) { this.squash.kick(-2.6); this._lagX.kick(-5); }
    this._hurt = st.hurt || 0;

    // Gait phase.
    const cycle = (p.cycle + p.cycleK * speed) / this.wob.speed;
    this.phase += (st.back ? -1 : 1) * dt * (speed / cycle) * Math.PI * 2 * (grounded ? 1 : 0.25);
    const ph = this.phase;
    const sn = Math.sin(ph), cs = Math.cos(ph);

    // Legs.
    const legA = (p.legSwing + p.legRun * run) * w * this.wob.amp;
    const kneeA = (p.knee + 0.9 * run) * w;
    J.hipL.rotation.x = sn * legA;
    J.hipR.rotation.x = -sn * legA;
    J.kneeL.rotation.x = -(0.08 + Math.max(0, cs) * kneeA) - 0.06 * w;
    J.kneeR.rotation.x = -(0.08 + Math.max(0, -cs) * kneeA) - 0.06 * w;
    J.footL.rotation.x = -(J.hipL.rotation.x + J.kneeL.rotation.x) * 0.7;
    J.footR.rotation.x = -(J.hipR.rotation.x + J.kneeR.rotation.x) * 0.7;

    // Body bounce: highest when the legs pass, lowest (squashed) at footfall.
    const pass = Math.pow(Math.abs(cs), 0.7);
    const bob = w * p.bob * (0.6 + run * 0.6) * (pass - 0.5);
    J.hips.position.y += bob;
    this._bobVel = (bob - this._prevBob) / Math.max(dt, 1e-4);
    this._prevBob = bob;
    const contact = Math.pow(1 - Math.abs(cs), 5) * w;
    const sq = this.squash.update(dt, 0);
    const sy = 1 + sq - contact * p.squash;
    this.rig.root.scale.set(1 / Math.sqrt(sy), sy, 1 / Math.sqrt(sy));

    // Torso: lean, counter-twist, waddle.
    J.spine.rotation.x = -(0.03 + p.lean * (0.4 + run)) * w - (p.arms === 'forward' ? p.lean * 0.6 : 0);
    J.spine.rotation.z = THREE.MathUtils.clamp(-(st.turn || 0) * 0.05, -0.2, 0.2) + cs * p.sway * w * 0.5;
    J.hips.rotation.y = -sn * p.twist * 0.6 * w;
    J.chest.rotation.y = sn * p.twist * w * (0.5 + run);
    J.hips.rotation.z = cs * p.sway * w;
    // Strafe: legs face the movement, the upper body counter-rotates to keep facing the aim.
    const legYaw = (st.legYaw || 0) * w;
    J.hips.rotation.y += legYaw;
    J.spine.rotation.y -= legYaw;
    const breathe = 1 + p.breathe + p.breathe * Math.sin(t * Math.PI * 2 * 0.3);
    J.chest.scale.set(1 + (breathe - 1) * 0.5, breathe, 1 + (breathe - 1) * 0.7);

    // Arms.
    const armA = (p.arm + p.armRun * run) * w;
    if (p.arms === 'forward') {
      const sway = Math.sin(t * 1.4 * this.wob.speed + this.seed) * 0.12;
      J.shoulderL.rotation.set(Math.PI / 2 - 0.22 + sway + sn * armA + this.wob.armL, 0, 0.12);
      J.shoulderR.rotation.set(Math.PI / 2 - 0.22 - sway - sn * armA + this.wob.armR, 0, -0.12);
      J.elbowL.rotation.x = 0.12 + Math.sin(t * 2.1 + this.seed) * 0.08;
      J.elbowR.rotation.x = 0.12 + Math.cos(t * 2.3 + this.seed) * 0.08;
    } else {
      const flop = p.arms === 'floppy' ? Math.sin(t * 5 + this.seed) * 0.25 : 0;
      J.shoulderL.rotation.set(-sn * armA + flop, 0, 0.1 + 0.05 * (1 - w));
      J.shoulderR.rotation.set(sn * armA - flop, 0, -0.1 - 0.05 * (1 - w));
      J.elbowL.rotation.x = 0.15 + (p.elbow + run * 0.5) * w + Math.max(0, -sn) * 0.3 * w;
      J.elbowR.rotation.x = 0.15 + (p.elbow + run * 0.5) * w + Math.max(0, sn) * 0.3 * w;
      // Idle: arms drift a little.
      const idle = (1 - w) * Math.sin(t * 1.9) * 0.03;
      J.shoulderL.rotation.x += idle; J.shoulderR.rotation.x -= idle;
    }

    // Air pose: tuck legs, arms out.
    if (air > 0.01) {
      J.hipL.rotation.x += 0.55 * air; J.kneeL.rotation.x -= 0.9 * air;
      J.hipR.rotation.x += 0.15 * air; J.kneeR.rotation.x -= 0.45 * air;
      J.shoulderL.rotation.z += 0.45 * air; J.shoulderR.rotation.z -= 0.45 * air;
    }

    // Aiming: weapon forward with both hands, pitch with the view, upper-body twist.
    const pitch = st.aimPitch || 0, yaw = st.aimYaw || 0;
    J.spine.rotation.y += yaw;
    if (this.aimW > 0.001) {
      const a = this.aimW;
      const lift = pitch * 0.85;
      lerpRot(J.shoulderR, Math.PI / 2 + lift - 0.28, 0, -0.05, a);
      J.elbowR.rotation.x = THREE.MathUtils.lerp(J.elbowR.rotation.x, 0.3, a);
      lerpRot(J.shoulderL, Math.PI / 2 + lift - 0.55, 0, 0.62, a);
      J.elbowL.rotation.x = THREE.MathUtils.lerp(J.elbowL.rotation.x, 0.85, a);
      J.chest.rotation.x += pitch * 0.25 * a;
    }
    J.head.rotation.x += pitch * 0.35 + (1 - this.aimW) * 0.04;
    J.head.rotation.y += yaw * 0.25;

    // Recoil / reload / melee layers.
    const rec = st.recoil || 0;
    if (rec > 0) {
      J.chest.rotation.x += rec * 0.1;
      J.shoulderR.rotation.x += rec * 0.35;
      J.shoulderL.rotation.x += rec * 0.25;
    }
    const rl = st.reload || 0;
    const rarc = rl > 0 && rl < 1 ? Math.sin(Math.PI * rl) : 0;
    if (rarc > 0) {
      J.shoulderL.rotation.x -= rarc * 1.0;
      J.elbowL.rotation.x += rarc * 0.6;
      J.shoulderR.rotation.x -= rarc * 0.35;
      J.head.rotation.x -= rarc * 0.25;
    }
    const ml = st.melee || 0;
    if (ml > 0 && ml < 1) {
      const wind = smooth(0, 0.25, ml), strike = smooth(0.25, 0.45, ml), back = smooth(0.55, 1, ml);
      const k = wind * (1 - back);
      J.chest.rotation.y += (0.45 * wind - 0.9 * strike) * (1 - back);
      J.shoulderR.rotation.x = THREE.MathUtils.lerp(J.shoulderR.rotation.x, THREE.MathUtils.lerp(2.7, 0.9, strike), k);
      J.shoulderR.rotation.z -= 0.5 * k;
      J.elbowR.rotation.x = THREE.MathUtils.lerp(J.elbowR.rotation.x, THREE.MathUtils.lerp(1.4, 0.2, strike), k);
      J.spine.rotation.x -= 0.15 * strike * (1 - back);
    }

    // Zombie attack: arms rise (anticipation), squash, then swipe down.
    const at = st.attack || 0;
    if (at > 0 && at < 1) {
      const up = smooth(0, 0.4, at) * (1 - smooth(0.4, 0.6, at));
      const down = smooth(0.4, 0.6, at) * (1 - smooth(0.75, 1, at));
      J.shoulderL.rotation.x += 1.1 * up - 0.9 * down;
      J.shoulderR.rotation.x += 1.1 * up - 0.9 * down;
      J.spine.rotation.x += 0.2 * up - 0.35 * down;
      this.rig.root.scale.y *= 1 - 0.08 * up;
    }

    // Hurt: lean back, stagger.
    const hu = st.hurt || 0;
    if (hu > 0) {
      J.spine.rotation.x += hu * 0.28;
      J.head.rotation.x += hu * 0.3;
      J.hips.position.z += hu * 0.06;
    }

    // Climb (windows/fences): alternating reach.
    const cl = st.climb || 0;
    if (cl > 0) {
      const c = Math.sin(cl * Math.PI * 6);
      lerpRot(J.shoulderL, 2.6 + c * 0.35, 0, 0.2, 1);
      lerpRot(J.shoulderR, 2.6 - c * 0.35, 0, -0.2, 1);
      J.hipL.rotation.x += Math.max(0, c) * 1.1; J.kneeL.rotation.x -= Math.max(0, c) * 1.4;
      J.hipR.rotation.x += Math.max(0, -c) * 1.1; J.kneeR.rotation.x -= Math.max(0, -c) * 1.4;
    }

    // Dance (disco): hip sway and alternating point.
    const da = st.dance || 0;
    if (da > 0) {
      const b = Math.sin(t * Math.PI * 4);
      J.hips.rotation.z += b * 0.12 * da;
      J.hips.position.x += b * 0.04 * da;
      J.chest.rotation.z -= b * 0.1 * da;
      J.shoulderR.rotation.x += (b > 0 ? 2.6 : 0.4) * da * 0.6;
      J.shoulderR.rotation.z -= 0.3 * da;
      J.kneeL.rotation.x -= Math.max(0, b) * 0.4 * da;
      J.kneeR.rotation.x -= Math.max(0, -b) * 0.4 * da;
    }

    // Down: kneel and slump.
    if (st.down) {
      J.hips.position.y -= D.leg * 0.55;
      J.hipL.rotation.x += 1.4; J.kneeL.rotation.x -= 2.2;
      J.hipR.rotation.x += 0.3; J.kneeR.rotation.x -= 1.6;
      J.spine.rotation.x -= 0.35;
      J.head.rotation.x -= 0.3;
    }

    // Secondary motion: the head lags the torso on springs (60 ms feel) and exposes the lag for hair.
    const lx = this._lagX.update(dt, -this._bobVel * 0.06 * p.headLag);
    const lz = this._lagZ.update(dt, -(st.turn || 0) * 0.03 * p.headLag + (this.p.wobble ? Math.sin(t * 0.9 + this.seed) * 0.12 * this.p.wobble : 0));
    this.headLag.x = lx; this.headLag.z = lz;
    J.head.rotation.x += lx;
    J.head.rotation.z += lz + this.wob.tilt;

    // Dead: topple backward with a bounce.
    const de = st.dead || 0;
    if (de > 0) {
      this.rig.root.rotation.x = (Math.PI / 2) * easeOutBounce(Math.min(1, de));
      J.shoulderL.rotation.x = THREE.MathUtils.lerp(J.shoulderL.rotation.x, 2.6, de);
      J.shoulderR.rotation.x = THREE.MathUtils.lerp(J.shoulderR.rotation.x, 2.6, de);
    }

    this._applyPoses();
    if (p.alignHand && this.aimW > 0.001 && !(ml > 0 && ml < 1)) this._alignHand(pitch, yaw, rarc);
    if (this.override) this.override(this.rig, dt);
  }

  _applyPoses() {
    if (this._poses.size === 0) return;
    const J = this.rig.joints;
    for (const [name, weight] of this._poses) {
      const pose = POSES[name];
      if (!pose) continue;
      for (const jn in pose) {
        const obj = J[jn];
        if (!obj) continue;
        const r = pose[jn];
        _q.setFromEuler(_e.set(r[0], r[1], r[2]));
        obj.quaternion.slerp(_q, Math.min(1, weight));
      }
    }
  }

  // Orient handR so the held weapon points exactly along the aim (whatever the arm pose).
  _alignHand(pitch, yaw, reloadArc) {
    const J = this.rig.joints;
    const root = this.rig.root;
    root.updateWorldMatrix(true, false);
    root.getWorldQuaternion(_q2);
    // World quaternion of handR's parent (elbowR) through the joint chain.
    _q2.multiply(J.hips.quaternion).multiply(J.spine.quaternion).multiply(J.chest.quaternion)
      .multiply(J.shoulderR.quaternion).multiply(J.elbowR.quaternion);
    // Target: body yaw (root) + aim yaw, view pitch, with a reload roll.
    root.getWorldQuaternion(_q);
    _e.set(pitch, yaw, -reloadArc * 0.7, 'YXZ');
    _q.multiply(_q3.setFromEuler(_e));
    const target = _q2.invert().multiply(_q);
    J.handR.quaternion.slerp(target, this.aimW);
  }
}

function lerpRot(obj, x, y, z, a) {
  obj.rotation.x += (x - obj.rotation.x) * a;
  obj.rotation.y += (y - obj.rotation.y) * a;
  obj.rotation.z += (z - obj.rotation.z) * a;
}
