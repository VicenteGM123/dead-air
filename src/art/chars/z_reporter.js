// Z_REPORTER — "Tuned-In" zombie variant: the lanky WZTV field reporter (GDD §8.1, STYLE_GUIDE §7,
// ref docs/ref/meshy_refs/zombie_reporter_tie.png). Tall and skinny: messy grey molded-toy hair, brown blazer with wide
// 70s lapels and a suede elbow patch, pale-blue shirt, BIG striped orange tie worn loose, blue bell-bottoms, brown shoes,
// droopy mismatched eyes, tongue out, "13 ADMIT ONE" ticket stub in the breast pocket.
// Exaggerated feature: LONG DROOPY NOSE on a tall egg head (+ the tongue).
// Shared zombie helpers live in z_crew.js (rebake this file with --force after editing them).
import { onEllipsoid } from './_sculpt.js';
import { ZOMBIE_MATS, ZSHADOW, zEyeSocket, zEyeLid, zEyePaint, zMouthLip, zMouthInside, zHand, hairClump, staticEyes, ticketStub } from './z_crew.js';

const HAIR = '#9A9BA6';
const HEAD_DY = -0.04;   // the whole head sits a bit lower on the (long) neck than the rig's head joint
// Head-local anchors (origin = head joint; y up, -z forward).
const EYES = [
  { x: 0.073, y: 0.334, z: -0.141, r: 0.056, pitch: 0.03, yaw: -0.34, lid: 0.4, droop: 0.26, depth: 0.72 },
  { x: -0.07, y: 0.34, z: -0.142, r: 0.064, pitch: 0.05, yaw: 0.32, lid: 0.3, droop: 0.2, depth: 0.72 },
];
function lipLoop(rx, ry, n = 22) {
  const pts = [];
  for (let i = 0; i <= n + 2; i++) { const a = (i / n) * Math.PI * 2; pts.push([Math.cos(a) * rx, Math.sin(a) * ry * (Math.sin(a) > 0 ? 0.9 : 1.1), 0]); }
  return pts;
}
const MOUTH = {
  pos: [0.008, 0.152, -0.158], pitch: 0.28, roll: -0.12, r: 0.0135, lipPts: lipLoop(0.047, 0.026), open: [0.04, 0.02],
  teeth: [
    { x: -0.017, y: 0.013, w: 0.0115, h: 0.012, rot: 0.1 },
    { x: 0.011, y: 0.0125, w: 0.0105, h: 0.0115, rot: -0.18 },
  ],
  tongue: { pts: [[-0.004, -0.002, 0.014], [-0.002, -0.014, -0.008], [0.004, -0.036, -0.02], [0.008, -0.056, -0.016]], r: [0.015, 0.018, 0.02, 0.016], flat: 0.45 },
};
const HM = { c: [0, 0.335, 0.006], r: [0.17, 0.226, 0.18] };

function torsoShapes(sd) {
  sd.ellipsoid({ pos: [0, 0.9, 0.012], r: [0.162, 0.108, 0.112] });
  sd.ellipsoid({ pos: [0, 0.775, 0.002], r: [0.138, 0.11, 0.108] });
  sd.ellipsoid({ pos: [0, 0.956, 0.018], r: [0.19, 0.054, 0.1] });
}
const V_TOP = { a: [0, 0.77, -0.13], b: [0, 1.0, -0.125], ra: 0.046, rb: 0.088 };
const V_BOT = { a: [0, 0.77, -0.13], b: [0, 0.6, -0.13], ra: 0.046, rb: 0.07 };

export default {
  id: 'z_reporter',
  name: 'Tuned-In: Field Reporter',
  kind: 'zombie',
  rig: { height: 1.68, headScale: 1.4, shoulderW: 0.4, hipW: 0.27, legLen: 0.9, torsoLen: 0.48, armLen: 0.7 },
  bake: { voxel: 0.0046, tris: 9500, aoStrength: 0.9, aoReach: 0.1 },
  armOut: 0.1,
  poseOffset: { spine: [-0.06, 0, 0], chest: [-0.06, 0, 0], head: [0.16, 0, -0.1], handL: [-0.5, 0, 0], handR: [-0.35, 0, 0] },
  rim: { color: '#8FF3FF', strength: 0.3 },
  materials: {
    ...ZOMBIE_MATS,
    hair: { color: HAIR, rough: 0.38, aniso: 0.3, spec: 0.5, wrap: 0.5, cav: 0.8 },
    shirt: { color: '#B7D2EC', rough: 0.72, fuzz: 0.3, wrap: 0.55 },
    blazer: { color: '#7A4A2A', rough: 0.72, fuzz: 0.35, wrap: 0.5, lines: true },
    lapel: { color: '#6A3F22', rough: 0.68, fuzz: 0.35, wrap: 0.5 },
    tie: { color: '#ffffff', rough: 0.55, fuzz: 0.2, spec: 0.7,
      pattern: { type: 'stripes', colors: ['#E3662B', '#F6E7C8', '#E8A92E', '#F6E7C8', '#B5472A', '#F6E7C8'], widths: [3, 0.7, 1.6, 0.7, 1.2, 0.7], scale: 0.11, soft: 0.03 } },
    pants: { color: '#ffffff', rough: 0.8, fuzz: 0.35, lines: true, pattern: { type: 'denim', color: '#3A58B8', scale: 0.05 } },
    patch: { color: '#C99A62', rough: 0.9, fuzz: 0.6, lines: true },
    shoe: { color: '#6E3F22', rough: 0.25, spec: 0.9 },
    sole: { color: '#3A2418', rough: 0.6 },
    leather: { color: '#4A2E1C', rough: 0.45, spec: 0.5 },
    gold: { color: '#E9B24A', metal: 1, rough: 0.25 },
    button: { color: '#E9D6B0', rough: 0.3, spec: 0.7 },
  },
  anchors: () => ({ EYES, MOUTH }),

  sculpt(sd) {
    // ---------------- torso: shirt, tie, blazer ----------------
    const shirtNode = sd.group({ name: 'shirt', mat: 'shirt', bone: 'torso', k: 0.05 }, () => torsoShapes(sd));
    // long skinny neck
    sd.capsule({ mat: 'skin', bone: 'torso', a: [0, 0.94, 0.02], b: [0, 1.08, 0.006], r: 0.056, k: 0.02 });
    // loose open collar: two soft flat points splayed on the shirt
    sd.group({ name: 'collar', mat: 'shirt', bone: 'torso', blend: 0.01, k: 0.016 }, () => {
      sd.torus({ pos: [0, 0.995, 0.018], rot: [0.14, 0, 0], R: 0.058, r: 0.016 });
      sd.mirrorX(() => sd.ellipsoid({ pos: [0.045, 0.975, -0.078], rot: [0.5, 0.45, 0.75], r: [0.034, 0.02, 0.01] }));
    });
    // tie: loosened knot pulled down + big striped blade, hanging a bit askew
    const tieFr = sd.patternFrame({ pos: [0.02, 0.86, -0.14], rot: [0, 0, 0.62], mode: 'tri' });
    sd.group({ name: 'tie', mat: 'tie', bone: 'chest', pframe: tieFr, blend: 0.004, k: 0.01 }, () => {
      const k0 = sd.snap(shirtNode, [0.012, 0.968, -0.2], 0.012);
      sd.box({ pos: k0, rot: [0.25, 0, 0.12], size: [0.021, 0.02, 0.013], round: 0.012 });
      const p1 = sd.snap(shirtNode, [0.016, 0.9, -0.2], 0.012), p2 = sd.snap(shirtNode, [0.024, 0.82, -0.2], 0.014), p3 = sd.snap(shirtNode, [0.032, 0.742, -0.2], 0.016);
      sd.group({ k: 0.01 }, () => {
        sd.worm({ pts: [[k0[0], k0[1] - 0.012, k0[2] - 0.002], p1, p2, p3], r: [0.018, 0.03, 0.045, 0.052], flat: 0.2, up: [0, 0.1, -1], segs: 16 });
        // pointed tip
        sd.frame({ pos: [p3[0], p3[1] - 0.012, p3[2]], rot: [0, 0, 0.07] }, () => {
          sd.plane({ op: 'int', k: 0.006, n: [0.7, -0.72, 0], d: 0.024 });
          sd.plane({ op: 'int', k: 0.006, n: [-0.7, -0.72, 0], d: 0.024 });
        });
      });
    });
    const blazer = sd.group({ name: 'blazer', mat: 'blazer', bone: 'torso', blend: 0.006, k: 0.02 }, () => {
      sd.group({ offset: 0.014, k: 0.05 }, () => {
        torsoShapes(sd);
        sd.ellipsoid({ pos: [0, 0.68, 0.004], r: [0.152, 0.1, 0.118] });   // skirt of the jacket over the hips
      });
      sd.roundCone({ op: 'sub', k: 0.012, ...V_TOP });
      sd.roundCone({ op: 'sub', k: 0.012, ...V_BOT });
      sd.capsule({ op: 'sub', k: 0.02, a: [0, 0.99, 0.03], b: [0, 1.12, 0.03], r: 0.078 });
      sd.plane({ op: 'int', k: 0.008, n: [0, -1, 0], d: -0.625 });
      sd.sphere({ op: 'sub', k: 0.006, pos: [0.1, 0.63, -0.1], r: 0.03 });    // clean rounded bite out of the hem
    });
    // wide 70s lapels: a thin raised panel that follows the blazer surface (shell over the same shapes), cut to a
    // clean lapel footprint along the V edge (flat, smooth, rounded points — no loose flaps)
    sd.group({ name: 'lapels', mat: 'lapel', bone: 'torso', blend: 0.003 }, () => {
      sd.group({ offset: 0.0175, shell: 0.0062, k: 0.05 }, () => {
        torsoShapes(sd);
        sd.ellipsoid({ pos: [0, 0.68, 0.004], r: [0.152, 0.1, 0.118] });
      });
      sd.group({ op: 'int', k: 0.008 }, () => {
        sd.mirrorX(() => {
          sd.roundCone({ a: [0.098, 0.975, -0.12], b: [0.058, 0.8, -0.14], ra: 0.05, rb: 0.012 });
          sd.sphere({ pos: [0.118, 0.985, -0.1], r: 0.036 });
        });
      });
      sd.roundCone({ op: 'sub', k: 0.004, ...V_TOP, ra: V_TOP.ra - 0.002, rb: V_TOP.rb - 0.002 });
      sd.capsule({ op: 'sub', k: 0.01, a: [0, 0.99, 0.03], b: [0, 1.12, 0.03], r: 0.08 });
    });
    const bt = sd.snap(blazer, [0.062, 0.745, -0.2], 0.002);
    sd.ellipsoid({ mat: 'button', bone: 'torso', rigid: true, pos: bt, r: [0.011, 0.011, 0.006], k: 0.002 });
    // breast pocket (character's left) + side pockets, stitched
    sd.stitch([[-0.06, 0.885, -0.2], [-0.135, 0.9, -0.2]], { mats: ['blazer'], color: '#C9956A', smooth: false });
    sd.mirrorX(() => sd.stitch([[0.06, 0.69, -0.2], [0.135, 0.7, -0.2]], { mats: ['blazer'], color: '#C9956A', smooth: false }));
    sd.stitch([[0, 0.625, 0.2], [0, 0.76, 0.2]], { mats: ['blazer'], color: '#5A3420' });

    // ---------------- head ----------------
    sd.bone('head', () => sd.frame({ pos: [0, HEAD_DY, 0] }, () => {
      const head = sd.group({ name: 'head', mat: 'skin', k: 0.02, blend: 0.03 }, () => {
        sd.group({ k: 0.07 }, () => {
          sd.ellipsoid({ pos: [0, 0.33, 0.005], r: [0.158, 0.215, 0.168] });   // tall egg skull
          sd.ellipsoid({ pos: [0, 0.175, -0.035], r: [0.122, 0.105, 0.125] }); // narrow chin
        });
        // long droopy nose (bridge + drooping bulb)
        sd.roundCone({ a: [0, 0.33, -0.152], b: [0, 0.252, -0.228], ra: 0.021, rb: 0.028, k: 0.018 });
        sd.ellipsoid({ pos: [0.004, 0.232, -0.238], r: [0.033, 0.036, 0.033], k: 0.014 });
        // ears (small, one lower)
        sd.mirrorX((m) => {
          sd.ellipsoid({ pos: [0.157, m ? 0.3 : 0.285, 0.018], rot: [0, -0.3, m ? -0.2 : 0.25], r: [0.022, 0.045, 0.032], k: 0.012 });
          sd.ellipsoid({ op: 'sub', k: 0.007, pos: [0.172, m ? 0.3 : 0.285, 0.014], rot: [0, -0.3, m ? -0.2 : 0.25], r: [0.01, 0.028, 0.018] });
        });
        for (const E of EYES) zEyeSocket(sd, E);
        zMouthLip(sd, MOUTH);
      });
      for (const E of EYES) zEyeLid(sd, E);
      zMouthInside(sd, MOUTH);
      for (const E of EYES) zEyePaint(sd, E);
      sd.paint({ color: '#8DB58A', soft: 0.02, strength: 0.6, only: ['skin'] }, () => sd.sphere({ pos: [0.004, 0.232, -0.25], r: 0.034 }));
      sd.paint({ color: ZSHADOW, soft: 0.03, strength: 0.35, only: ['skin'] }, () => sd.ellipsoid({ pos: [0, 0.08, -0.04], r: [0.14, 0.05, 0.16] }));

      // ---- hair: messy molded-toy grey mop = a pinwheel of 6 big smooth clumps flowing out of a crown whorl (each one
      //      long, wide and flat, lying on a skull cap, with a clean tapered tip that flicks out past the hairline) ----
      sd.group({ name: 'hair', mat: 'hair', blend: 0.004, k: 0.008 }, () => {
        const mass = sd.group({ name: 'hairmass', k: 0.04 }, () => {
          sd.ellipsoid({ pos: [0, 0.335, 0.006], r: [0.168, 0.224, 0.178] });
          sd.plane({ op: 'int', k: 0.05, n: [0, -0.917, -0.397], d: -0.37 });
        });
        const C = (path, r, flat = 0.5) => hairClump(sd, [head, mass], HM, path, { r, flat, k: 0.01, flow: false, segs: 22 });
        const R = (w) => [0.035, w, w * 1.02, w * 0.72, w * 0.2];
        C([[176, 72, -0.03], [120, 86, -0.002], [14, 72, 0.006], [-8, 48, 0.01], [-20, 28, 0.016]], R(0.07));     // forelock (over his left brow)
        C([[178, 70, -0.03], [70, 82, -0.002], [44, 62, 0.006], [42, 44, 0.012], [48, 30, 0.034]], R(0.064));    // front right, flicks up
        C([[180, 66, -0.03], [134, 58, -0.002], [106, 40, 0.006], [100, 20, 0.012], [106, 4, 0.034]], R(0.066)); // right side flick
        C([[172, 66, -0.03], [-136, 58, -0.002], [-106, 40, 0.006], [-100, 20, 0.012], [-108, 4, 0.034]], R(0.066)); // left side flick
        C([[176, 74, -0.03], [-80, 84, -0.002], [-50, 64, 0.006], [-46, 46, 0.012], [-54, 32, 0.03]], R(0.062));  // front left
        C([[174, 70, -0.03], [178, 48, -0.002], [172, 26, 0.008], [166, 4, 0.032]], [0.035, 0.07, 0.054, 0.014]);     // back
        C([[168, 70, -0.03], [-158, 46, -0.002], [-150, 24, 0.008], [-146, 4, 0.03]], [0.035, 0.066, 0.05, 0.013]);   // back left
        C([[182, 70, -0.03], [148, 46, -0.002], [138, 24, 0.008], [132, 6, 0.03]], [0.035, 0.066, 0.05, 0.013]);     // back right
        // crown sprig at the whorl
        const c0 = sd.snap(mass, onEllipsoid(HM, 175, 72, 0.05), 0.0);
        sd.worm({ pts: [c0, [c0[0] - 0.004, c0[1] + 0.036, c0[2] + 0.012], [c0[0] - 0.01, c0[1] + 0.06, c0[2] - 0.004], [c0[0] - 0.012, c0[1] + 0.058, c0[2] - 0.03]], r: [0.024, 0.018, 0.012, 0.005], flat: 0.72, up: [1, 0, 0], k: 0.014, segs: 14 });
      });
    }));

    // ---------------- belt + bell-bottoms ----------------
    sd.group({ name: 'pelvis', mat: 'pants', bone: 'torso', k: 0.03 }, () => {
      sd.ellipsoid({ pos: [0, 0.68, 0.004], r: [0.146, 0.092, 0.114] });
    });
    sd.group({ name: 'belt', mat: 'leather', bone: 'torso' }, () => {
      sd.ellipsoid({ pos: [0, 0.705, 0.0], r: [0.14, 0.1, 0.11], offset: 0.007 });
      sd.box({ op: 'int', k: 0.003, pos: [0, 0.708, 0], size: [0.3, 0.017, 0.3], round: 0.002 });
    });
    sd.group({ name: 'buckle', mat: 'gold', bone: 'hips', rigid: true, k: 0.003 }, () => {
      sd.ellipsoid({ pos: [0, 0.708, -0.118], r: [0.028, 0.021, 0.008] });
    });
    sd.mirrorX((m) => {
      sd.bone('hipL', () => {
        const fr = sd.patternFrame({ pos: [0, -0.3, 0], mode: 'cyl', radius: 0.08 });
        sd.group({ mat: 'pants', k: 0.04, blend: 0.03, pframe: fr }, () => {
          sd.roundCone({ a: [0.035, -0.03, 0.004], b: [0, -0.293, 0.004], ra: 0.084, rb: 0.064 });
          sd.cone({ pos: [0, -0.44, 0.006], h: 0.15, r1: 0.112, r2: 0.064, round: 0.01 });
          if (m) sd.sphere({ op: 'sub', k: 0.005, cutMat: 'skin', pos: [0.012, -0.4, -0.085], r: 0.026 });   // rounded tear (right shin)
        });
        // crease + hem stitches
        sd.stitch([[0, 0.02, -0.09], [0, -0.29, -0.07], [0, -0.58, -0.125]], { mats: ['pants'], color: '#6F8FE0' });
        sd.stitch(Array.from({ length: 25 }, (_, i) => { const a = (i / 24) * Math.PI * 2; return [Math.sin(a) * 0.13, -0.568, 0.006 + Math.cos(a) * 0.13]; }), { mats: ['pants'], smooth: false, color: '#E8A92E' });
      });
      sd.bone('footL', () => {
        const upper = () => {
          sd.ellipsoid({ pos: [0, -0.028, -0.085], r: [0.064, 0.044, 0.152] });
          sd.sphere({ pos: [0, -0.024, -0.17], r: 0.058 });
          sd.ellipsoid({ pos: [0, -0.01, 0.0], r: [0.056, 0.054, 0.064] });
        };
        sd.group({ mat: 'shoe', k: 0.035 }, upper);
        sd.group({ mat: 'sole', blend: 0.0 }, () => {
          sd.group({ offset: 0.006, k: 0.035 }, upper);
          sd.box({ op: 'int', k: 0.003, pos: [0, -0.062, -0.07], size: [0.12, 0.01, 0.28], round: 0.003 });
        });
      });
    });

    // ---------------- arms (long, blazer sleeves, shirt cuffs, suede elbow patch on the left) ----------------
    sd.mirrorX((m) => {
      sd.bone('shoulderL', () => {
        sd.group({ mat: 'blazer', k: 0.03 }, () => {
          sd.ellipsoid({ pos: [-0.01, -0.03, 0.004], r: [0.062, 0.064, 0.062] });
          sd.roundCone({ a: [0, -0.03, 0], b: [0, -0.241, 0], ra: 0.058, rb: 0.05 });
        });
      });
      sd.bone('elbowL', () => {
        sd.group({ mat: 'blazer', k: 0.02 }, () => {
          sd.roundCone({ a: [0, 0.02, 0], b: [0, -0.215, 0.002], ra: 0.05, rb: 0.047 });
        });
        if (!m) {
          sd.paint({ mat: 'patch', soft: 0.001, only: ['blazer'] }, () => sd.ellipsoid({ pos: [0, -0.02, 0.05], r: [0.034, 0.045, 0.03] }));
          const ring = Array.from({ length: 25 }, (_, i) => { const a = (i / 24) * Math.PI * 2; return [Math.sin(a) * 0.027, -0.02 + Math.cos(a) * 0.038, 0.07]; });
          sd.stitch(ring, { mats: ['patch'], color: '#7A4A2A', smooth: false });
        }
        sd.group({ mat: 'shirt', blend: 0.004, k: 0.008 }, () => {
          sd.cylinder({ pos: [0, -0.222, 0], r: 0.047, h: 0.014, round: 0.008 });
        });
        sd.roundCone({ mat: 'skin', a: [0, -0.2, 0], b: [0, -0.262, 0], ra: 0.037, rb: 0.035, k: 0.008 });
      });
      sd.bone('handL', () => zHand(sd, { scale: 1.4, curl: m ? 0.25 : 0.5 }));
    });
  },

  attachments(b) {
    staticEyes(b, EYES.map((e) => ({ ...e, y: e.y + HEAD_DY })));
    // chest joint y = 0.8535 (torso bind = rest): ticket tucked into the left lapel like a press pass
    ticketStub(b, { joint: 'chest', pos: [-0.088, 0.058, -0.112], rot: [0.12, 0.42, -0.62], w: 0.085, h: 0.047 });
  },
};
