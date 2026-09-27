// BOSS_BARON — BARON VON STATIC's body (GDD §13 step 6 "Boss model", STYLE_GUIDE: SIMPLIFY + EXAGGERATE).
// Owner: the boss + ending engineer (src/actors/boss.js builds the rest at runtime).
//
// Sculpted here (model units; boss.js scales the character ×2.5, so 1 unit = 2.5 m and the figure reads ~6 m with
// the head and the static tornado):
//   - a chunky inverted-trapezoid TUX jacket in #1A1A2E with big rounded shoulder pads,
//   - wide PLUM satin peaked lapels (flat shells of the jacket) over a painted white shirt V, two satin buttons,
//     a red carnation on the lapel,
//   - a white frilly JABOT cascading from a white wing-collar band, and a big gold "13" MEDALLION on a gold chain,
//   - the tall stiff Dracula CAPE COLLAR rising behind the head (black outside, magenta-plum lining, two pointed
//     tips), which frames the TV head from behind,
//   - LONG arms in tux sleeves with white shirt cuffs and gold cufflinks,
//   - HUGE white four-finger cartoon GLOVES (three sausage fingers + thumb, flared gauntlet cuff with a rolled rim,
//     three stitch lines on the back).
// Built at runtime by boss.js (they animate or change every frame): the walnut console-TV head (1.6 × 1.3 × 1.2 m)
// with the bulging face screen and the rabbit-ear antenna horns, the flowing cape (cloth sheet with vertex wobble)
// and the noise-textured static tornado the body trails into.
//
// Custom skeleton: base (waist, root) -> chest -> head (the neck; charRuntime needs a 'head' joint); chest -> shoulderL/R -> elbowL/R -> handL/R.
// Bind pose = the joint positions below (relaxed A-pose, arms hanging a little out and forward). boss.js rotates
// the joints itself (hover sway, arm gestures, the grab); createAnimator is only the charview preview idle.
// Bake: node tools/bake/bake.mjs boss_baron  (the runtime imports this module + assets/baked/registry.js directly,
// it does not need src/art/chars/index.js).
import { prism } from './_sculpt.js';

// Bind joint positions (absolute, model units).
const JP = {
  base: [0, 0, 0],
  chest: [0, 0.3, 0],
  neck: [0, 0.64, 0.01],
  shoulder: [-0.31, 0.575, 0.01],
  elbow: [-0.46, 0.28, -0.02],
  hand: [-0.55, 0.0, -0.07],
};
const rel = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const neg = (p) => [-p[0], p[1], p[2]];

// Glove frame: local -y runs along the forearm (elbow -> hand), local +x is medial (toward the body), -z is front.
const GLOVE_ROT = [0.179, 0, -0.31];

const TUX = '#1A1A2E';

// Cape collar profile: (radius, height) points of a gently bell-flared surface of revolution around an axis behind
// the neck. collarShell() is its EXACT distance field (2D distance to the profile polyline) minus a half thickness:
// an open shell with no caps and an even thickness (a shelled cone primitive gave jagged rims).
const COLLAR = { axisZ: 0.14, t: 0.0105, prof: [] };
for (let i = 0; i <= 8; i++) {
  const u = i / 8;
  COLLAR.prof.push([0.15 + 0.46 * Math.pow(u, 1.35), 0.46 + 0.62 * u]);
}
function collarDist(x, y, z) {
  const rho = Math.hypot(x, z), P = COLLAR.prof;
  let best = Infinity;
  for (let i = 0; i < P.length - 1; i++) {
    const ax = P[i][0], ay = P[i][1], bx = P[i + 1][0] - ax, by = P[i + 1][1] - ay;
    const px = rho - ax, py = y - ay;
    const h = Math.max(0, Math.min(1, (px * bx + py * by) / (bx * bx + by * by)));
    const dx = px - bx * h, dy = py - by * h;
    const d = dx * dx + dy * dy;
    if (d < best) best = d;
  }
  return Math.sqrt(best) - COLLAR.t;
}
function collarShell(sd, o = {}) {
  return sd.custom({ pos: [0, 0, COLLAR.axisZ], box: [-0.64, 0.42, -0.64, 0.64, 1.12, 0.64], fn: collarDist, ...o });
}

// Jacket volume shared by the jacket and the lapel shells.
function jacketShapes(sd) {
  sd.ellipsoid({ pos: [0, 0.43, 0.0], r: [0.25, 0.19, 0.155] });            // chest
  sd.ellipsoid({ pos: [0, 0.18, 0.005], r: [0.172, 0.2, 0.13] });           // waist (V taper)
  sd.ellipsoid({ pos: [0, 0.548, 0.012], r: [0.3, 0.078, 0.142] });         // shoulder yoke
  sd.ellipsoid({ pos: [0, 0.42, -0.035], r: [0.2, 0.15, 0.12] });           // chest front (fills the lapel area)
  sd.ellipsoid({ pos: [0, 0.02, 0.01], r: [0.185, 0.07, 0.135] });          // hem, rounds off into the tornado
}

export default {
  id: 'boss_baron',
  name: 'Baron Von Static',
  kind: 'creature',
  rig: {
    custom: true,
    joints: [
      { name: 'base', parent: null, pos: JP.base, tail: [0, 0.3, 0], blend: 0.05, gate: 0.3 },
      { name: 'chest', parent: 'base', pos: rel(JP.chest, JP.base), tail: [0, 0.34, 0], blend: 0.08, gate: 0.3 },
      { name: 'head', parent: 'chest', pos: rel(JP.neck, JP.chest), tail: [0, 0.08, 0], blend: 0.03, gate: 0.1 },
      { name: 'shoulderL', parent: 'chest', pos: rel(JP.shoulder, JP.chest), tail: rel(JP.elbow, JP.shoulder), blend: 0.07, gate: 0.11 },
      { name: 'elbowL', parent: 'shoulderL', pos: rel(JP.elbow, JP.shoulder), tail: rel(JP.hand, JP.elbow), blend: 0.06, gate: 0.09 },
      { name: 'handL', parent: 'elbowL', pos: rel(JP.hand, JP.elbow), tail: [-0.05, -0.2, -0.03], blend: 0.04, gate: 0.08 },
      { name: 'shoulderR', parent: 'chest', pos: rel(neg(JP.shoulder), JP.chest), tail: rel(neg(JP.elbow), neg(JP.shoulder)), blend: 0.07, gate: 0.11 },
      { name: 'elbowR', parent: 'shoulderR', pos: rel(neg(JP.elbow), neg(JP.shoulder)), tail: rel(neg(JP.hand), neg(JP.elbow)), blend: 0.06, gate: 0.09 },
      { name: 'handR', parent: 'elbowR', pos: rel(neg(JP.hand), neg(JP.elbow)), tail: [0.05, -0.2, -0.03], blend: 0.04, gate: 0.08 },
    ],
    bindPose: {},
    dims: { height: 1.2, headH: 0.52 },
  },
  bake: { voxel: 0.0046, tris: 23000, aoStrength: 0.85, aoReach: 0.1 },
  rim: { color: '#C9A0FF', strength: 0.45 },
  materials: {
    tux: { color: TUX, rough: 0.42, spec: 0.55, fuzz: 0.25, wrap: 0.55, cav: 0.5 },
    lapel: { color: '#7A3F80', rough: 0.26, spec: 0.95, wrap: 0.55, cav: 0.4 },
    shirt: { color: '#F4F1E8', rough: 0.6, fuzz: 0.3, wrap: 0.6, cav: 0.45 },
    jabot: { color: '#FFFDF6', rough: 0.52, fuzz: 0.45, wrap: 0.65, cav: 0.55 },
    gold: { color: '#E8B84A', metal: 1, rough: 0.2 },
    cape: { color: '#1A1522', rough: 0.45, spec: 0.5, fuzz: 0.3, wrap: 0.5, cav: 0.45 },
    lining: { color: '#7E2250', rough: 0.28, spec: 0.9, wrap: 0.6, cav: 0.35 },
    glove: { color: '#FBF8F0', rough: 0.5, fuzz: 0.12, wrap: 0.62, spec: 0.45, cav: 0.65 },
    button: { color: '#2C2440', rough: 0.2, spec: 0.9, cav: 0.3 },
    flower: { color: '#E83A4A', rough: 0.5, fuzz: 0.4, wrap: 0.6, cav: 0.6 },
    leaf: { color: '#3E8A3A', rough: 0.5, wrap: 0.6, cav: 0.5 },
  },

  sculpt(sd) {
    // ---------------- tux jacket ----------------
    const jacket = sd.group({ name: 'jacket', mat: 'tux', bone: ['base', 'chest'], k: 0.07 }, () => {
      jacketShapes(sd);
      sd.mirrorX(() => sd.sphere({ pos: [-0.285, 0.548, 0.012], r: 0.088, k: 0.05 }));    // shoulder pads
    });
    // painted white shirt V (never carved)
    const V = [[0, 0.235], [0.088, 0.63], [-0.088, 0.63]];
    sd.paint({ mat: 'shirt', soft: 0.0015, only: ['tux'] }, () => prism(sd, V, { max: -0.03, k: 0.004 }));
    // wide peaked plum lapels: flat shells of the jacket ∩ the lapel footprint (front only)
    const LAPEL = [[0.086, 0.632], [0.212, 0.598], [0.238, 0.51], [0.034, 0.222], [0.012, 0.242]];
    sd.group({ name: 'lapels', mat: 'lapel', bone: ['chest'], k: 0, blend: 0.008 }, () => {
      sd.group({ offset: 0.009, shell: 0.0095, k: 0.07 }, () => jacketShapes(sd));
      sd.group({ op: 'int', blend: 0.006, k: 0 }, () => sd.mirrorX(() => prism(sd, LAPEL, { max: -0.03, k: 0.014 })));
    });
    sd.mirrorX(() => {
      const L = LAPEL, lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      sd.stitch([lerp(L[1], L[2], 0.15), lerp(L[2], L[3], 0.1), lerp(L[2], L[3], 0.5), lerp(L[2], L[3], 0.92)].map(([x, y]) => [x - 0.008, y, -0.3]),
        { mats: ['lapel'], color: '#B77ABD', width: 0.0016, dash: 0.011 });
    });
    // two satin buttons where the lapels meet
    for (const by of [0.21, 0.15]) {
      const p = sd.snap(jacket, [0, by, -0.2], 0.002);
      sd.ellipsoid({ mat: 'button', bone: ['base'], pos: p, r: [0.016, 0.016, 0.008], k: 0.003 });
    }
    // red carnation on the (character's) left lapel
    sd.group({ name: 'carnation', mat: 'flower', bone: ['chest'], blend: 0.004, k: 0.01 }, () => {
      const c = [-0.155, 0.505, -0.172];
      sd.sphere({ pos: c, r: 0.027 });
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * Math.PI * 2;
        sd.sphere({ pos: [c[0] + Math.cos(a) * 0.021, c[1] + Math.sin(a) * 0.021, c[2] + 0.004], r: 0.016, k: 0.008 });
      }
    });
    sd.ellipsoid({ mat: 'leaf', bone: ['chest'], pos: [-0.18, 0.478, -0.165], rot: [0, 0, -0.7], r: [0.018, 0.008, 0.006], k: 0.004 });

    // ---------------- wing collar band + frilly jabot + gold "13" medallion ----------------
    sd.group({ name: 'collarBand', mat: 'shirt', bone: ['chest', 'head'], blend: 0.012, k: 0.02 }, () => {
      sd.capsule({ a: [0, 0.57, 0.01], b: [0, 0.665, 0.012], r: 0.072 });
      sd.mirrorX(() => sd.ellipsoid({ pos: [0.046, 0.655, -0.07], rot: [0.3, 0, -0.5], r: [0.034, 0.02, 0.012] }));   // wing tips
    });
    sd.group({ name: 'jabot', mat: 'jabot', bone: ['chest'], blend: 0.01, k: 0.018 }, () => {
      const tiers = [[0.612, 0.058, 0.026, -0.104], [0.56, 0.074, 0.032, -0.13], [0.5, 0.084, 0.034, -0.143]];
      for (const [y, w, h, z] of tiers) {
        sd.ellipsoid({ pos: [0, y, z], r: [w, h, 0.026] });
        // scalloped bottom edge: a row of soft beads
        const n = 5;
        for (let i = 0; i < n; i++) {
          const u = (i / (n - 1)) * 2 - 1;
          sd.sphere({ pos: [u * w * 0.82, y - h * 0.72, z - 0.004 - (1 - u * u) * 0.006], r: h * 0.5, k: 0.01 });
        }
      }
    });
    // chain: two gold cords from the collar band down to the medallion
    sd.mirrorX(() => sd.worm({ mat: 'gold', bone: ['chest'], pts: [[0.07, 0.6, -0.06], [0.1, 0.5, -0.13], [0.07, 0.43, -0.165], [0.018, 0.418, -0.18]], r: 0.0065, segs: 14, k: 0.003 }));
    const MED = [0, 0.36, -0.184];
    sd.group({ name: 'medallion', mat: 'gold', bone: ['chest'], rigid: true, blend: 0.006, k: 0.004 }, () => {
      sd.cylinder({ pos: MED, rot: [Math.PI / 2, 0, 0], r: 0.058, h: 0.009, round: 0.006 });
      sd.torus({ pos: [MED[0], MED[1], MED[2] - 0.009], rot: [Math.PI / 2, 0, 0], R: 0.05, r: 0.0055 });
      sd.sphere({ pos: [0, 0.422, -0.182], r: 0.011 });                             // bail
    });
    // the "13": plum digits painted on the face of the medallion
    sd.paint({ color: '#4A1D5C', soft: 0.001, strength: 1, only: ['gold'] }, () => {
      // seen from the front, screen-right is -x: the '1' sits at +x and the '3' bulges toward -x
      const z = MED[2] - 0.0095, y0 = MED[1];
      sd.capsule({ a: [0.021, y0 - 0.026, z], b: [0.021, y0 + 0.026, z], r: 0.0062 });
      sd.capsule({ a: [0.021, y0 + 0.026, z], b: [0.031, y0 + 0.015, z], r: 0.0055 });
      sd.worm({ pts: [[-0.004, y0 + 0.02, z], [-0.016, y0 + 0.028, z], [-0.028, y0 + 0.018, z], [-0.018, y0 + 0.002, z]], r: 0.0058, segs: 10 });
      sd.worm({ pts: [[-0.018, y0 + 0.002, z], [-0.03, y0 - 0.012, z], [-0.018, y0 - 0.028, z], [-0.004, y0 - 0.02, z]], r: 0.0058, segs: 10 });
    });

    // ---------------- the tall stiff Dracula cape collar ----------------
    sd.group({ name: 'capeCollar', mat: 'cape', bone: ['chest'], blend: 0.01, k: 0 }, () => {
      collarShell(sd);
      sd.group({ op: 'int', k: 0.014 }, () => {
        prism(sd, [[-0.24, 0.5], [0.24, 0.5], [0.52, 1.0], [-0.52, 1.0]], { k: 0.03 });
        sd.plane({ n: [0, 0, -1], d: 0.03, op: 'int', k: 0.02 });                  // keep only the back (z > -0.03)
      });
      sd.ellipsoid({ op: 'sub', k: 0.03, pos: [0, 1.25, 0.3], r: [0.3, 0.42, 0.8] });  // dip at the back: two tips
    });
    // magenta-plum lining on the inner face: paint where the point is on the axis side of the mid-surface
    sd.paint({ mat: 'lining', soft: 0.002, only: ['cape'] }, () => sd.custom({ pos: [0, 0, COLLAR.axisZ], box: [-0.64, 0.42, -0.64, 0.64, 1.12, 0.64],
      fn: (x, y, z) => { const P = COLLAR.prof, u = Math.max(0, Math.min(1, (y - P[0][1]) / (P[8][1] - P[0][1]))); return Math.hypot(x, z) - (0.15 + 0.46 * Math.pow(u, 1.35)); } }));

    // ---------------- long arms: tux sleeves, white cuffs, gold cufflinks ----------------
    sd.mirrorX(() => {
      const S = JP.shoulder, E = JP.elbow, H = JP.hand;
      const mid = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
      sd.group({ mat: 'tux', blend: 0.035, k: 0.03 }, () => {
        sd.roundCone({ bone: ['shoulderL'], a: mid(S, E, 0.05), b: mid(S, E, 0.6), ra: 0.078, rb: 0.07 });
        sd.roundCone({ bone: ['shoulderL', 'elbowL'], a: mid(S, E, 0.55), b: E, ra: 0.071, rb: 0.066 });
        sd.roundCone({ bone: ['elbowL'], a: E, b: mid(E, H, 0.86), ra: 0.066, rb: 0.058 });
      });
      // shirt cuff (clean roll) + cufflink
      const C = mid(E, H, 0.9);
      sd.group({ mat: 'shirt', bone: ['elbowL', 'handL'], blend: 0.006, k: 0.012 }, () => {
        sd.frame({ pos: C, rot: GLOVE_ROT }, () => {
          sd.cylinder({ r: 0.06, h: 0.022, round: 0.012 });
          sd.torus({ pos: [0, -0.02, 0], R: 0.052, r: 0.014 });
        });
      });
      sd.frame({ pos: C, rot: GLOVE_ROT }, () => sd.sphere({ mat: 'gold', bone: ['elbowL'], pos: [0.0, 0.0, -0.062], r: 0.011, k: 0.003 }));

      // ---- the huge white cartoon glove ----
      sd.frame({ pos: H, rot: GLOVE_ROT, scale: 1.28 }, () => {
        sd.group({ name: 'glove', mat: 'glove', bone: ['handL'], blend: 0.008, k: 0.022 }, () => {
          // flared gauntlet cuff (opens toward the elbow) + rolled rim
          sd.cone({ pos: [0, 0.035, 0], h: 0.05, r1: 0.054, r2: 0.078, round: 0.01 });
          sd.cone({ op: 'sub', k: 0.008, pos: [0, 0.07, 0], h: 0.03, r1: 0.05, r2: 0.068 });
          sd.torus({ pos: [0, 0.084, 0], R: 0.07, r: 0.012, k: 0.01 });
          // puffy mitten palm
          sd.ellipsoid({ pos: [0, -0.07, 0], r: [0.052, 0.086, 0.082], k: 0.03 });
          // three fat sausage fingers, a little spread and curled toward the palm
          const fz = [-0.05, 0.0, 0.05], fl = [0.12, 0.13, 0.115];
          for (let i = 0; i < 3; i++) {
            const z = fz[i], l = fl[i], sp = (i - 1) * 0.012;
            sd.worm({ pts: [[0.004, -0.13, z], [0.012, -0.13 - l * 0.55, z + sp], [0.03, -0.13 - l, z + sp * 1.6]], r: [0.03, 0.029, 0.027], segs: 10, k: 0.012 });
            sd.sphere({ pos: [0.03, -0.13 - l, z + sp * 1.6], r: 0.028, k: 0.01 });
          }
          // thumb (front, pointing forward-down)
          sd.worm({ pts: [[0.012, -0.05, -0.06], [0.02, -0.085, -0.105], [0.034, -0.12, -0.12]], r: [0.03, 0.027, 0.025], segs: 10, k: 0.016 });
        });
        // three stitch lines on the back of the hand (lateral face)
        for (const z of [-0.032, 0, 0.032]) sd.stitch([[-0.06, -0.025, z], [-0.064, -0.07, z * 1.08], [-0.058, -0.112, z * 1.15]], { mats: ['glove'], color: '#B9B2C2', width: 0.0028, dash: 0.012 });
      });
    });
  },

  // charview preview only: a slow hover sway with the gloves breathing. boss.js drives the joints in game.
  createAnimator(rig) {
    const J = rig.joints;
    let t = 0;
    return {
      update(dt) {
        t += dt;
        J.chest.rotation.z = Math.sin(t * 0.9) * 0.04;
        J.chest.rotation.x = Math.sin(t * 0.7) * 0.03;
        J.shoulderL.rotation.z = -0.1 + Math.sin(t * 1.1) * 0.06;
        J.shoulderR.rotation.z = 0.1 - Math.sin(t * 1.1 + 0.6) * 0.06;
        J.elbowL.rotation.x = -0.25 + Math.sin(t * 1.3) * 0.08;
        J.elbowR.rotation.x = -0.25 + Math.sin(t * 1.3 + 0.8) * 0.08;
      },
      kick() {},
    };
  },
};
