// ROXY RIVERS v1 — host of "Boogie Down Saturday" (GDD §4, ref docs/ref/hero_disco.png). Same recipes and finish as
// the approved Duke (src/art/chars/duke.js, docs/CHARKIT.md, docs/STYLE_GUIDE.md): SIMPLIFY + EXAGGERATE.
//   - HUGE afro = her silhouette (~0.72 m wide): a clustered mass of round fuzzy puffs (felt-textured, no noise
//     displacement) on a big soft volume, pushed back by an orange/yellow floral headband over the forehead.
//   - Warm brown skin, big brown eyes with long lashes (lash wings ride the blinking lids), groomed arched brows,
//     rosy lips in a confident smile, gold hoops.
//   - White floral crop shirt: a real shell layer with a V neckline, flat pointed collar, puff sleeves with cuffs and a
//     front knot; bare midriff; brown belt with a gold ring buckle.
//   - Red bell-bottoms with the strongest flare of the cast, cream platform shoes with thick brown soles.
// Layout: world coords for torso/pants (feet y=0, facing -z), bone-local for limbs and head (head scaled by HS).
import { EYE_DEFAULTS } from './_face.js';
import { prism, cartoonMouth } from './_sculpt.js';

const SKIN = '#9C603F';
const AFRO = '#3B2419';
const BROW = '#24150F';
const LIPS = '#C4453F';

const HS = 1.06;
const EYE = {
  ...EYE_DEFAULTS, x: 0.064, y: 0.228, z: -0.128, r: 0.046, iris: '#8A4A22', irisSize: 0.64, pupilSize: 0.44,
  lid: '#8E5637', lash: '#160D0A', lidOpen: 0.98, lowerLid: 0.62, lidScale: 1.04, yaw: 0.07, glint: 1.15, tilt: 0.05,
};
const SKULL = { c: [0, 0.266, 0.012], r: [0.152, 0.174, 0.162] };
const MOUTH = {
  base: { y: 0.1, w: 0.042, h: 0.017, top: 0.096, R: 0.065, teeth: 0.85, roll: 0.05, clip: true },
  smile: { y: 0.099, w: 0.05, h: 0.027, top: 0.093, R: 0.062, teeth: 0.72, roll: 0.04, clip: true },
  frown: { y: 0.095, w: 0.034, h: 0.012, top: 0.103, R: -0.09, teeth: 0.4, tongue: false, roll: 0.02, clip: true },
  o_mouth: { y: 0.093, w: 0.026, h: 0.027, top: 0.12, R: null, teeth: 0.35, roll: 0.001, clip: true },
};
// Headband: the plane through the hairline at the forehead (0, 0.37, -0.13) and just in front of the ears; the afro is
// on its +n side (top / back), the face on its -n side.
const BAND = { n: [0, 0.607, 0.794], p: [0, 0.37, -0.13], half: 0.029 };
const bandD = (off) => BAND.n[0] * BAND.p[0] + BAND.n[1] * BAND.p[1] + BAND.n[2] * BAND.p[2] + off;
const AFRO_E = { c: [0, 0.395, 0.05], r: [0.33, 0.315, 0.3] };

// ------------------------------------------------------------------------------------------------------------
function torsoShapes(sd, Y) {
  sd.ellipsoid({ pos: [0, Y.sh - 0.08, 0.004], r: [0.148, 0.108, 0.098] });       // rib cage
  sd.mirrorX(() => sd.sphere({ pos: [0.052, Y.sh - 0.112, -0.05], r: 0.056, k: 0.05 }));   // modest bust
  sd.ellipsoid({ pos: [0, Y.sh - 0.012, 0.01], r: [0.165, 0.044, 0.082] });       // shoulder yoke
}
function waistShapes(sd, Y) {
  sd.ellipsoid({ pos: [0, Y.hip + 0.15, 0.008], r: [0.112, 0.105, 0.088] });      // slim waist (midriff)
}

function headBase(sd, ex) {
  const smile = ex === 'smile' ? 1 : 0;
  sd.ellipsoid({ pos: SKULL.c, r: SKULL.r });
  sd.ellipsoid({ pos: [0, 0.212, -0.056], r: [0.134, 0.096, 0.096], k: 0.06 });                // soft face mask
  sd.ellipsoid({ pos: [0, 0.146, -0.034], r: [0.12, 0.104, 0.124], k: 0.07 });                 // soft narrow jaw
  sd.ellipsoid({ pos: [0, 0.07, -0.08], r: [0.042, 0.032, 0.04], k: 0.05 });                   // small chin
  sd.mirrorX(() => sd.sphere({ pos: [0.072, 0.146 + smile * 0.012, -0.1 - smile * 0.004], r: 0.048 + smile * 0.004, k: 0.05 }));
  // small cute nose
  sd.capsule({ a: [0, 0.226, -0.15], b: [0, 0.188, -0.176], r: 0.014, k: 0.02 });
  sd.sphere({ pos: [0, 0.174, -0.184], r: 0.021, k: 0.016 });
  sd.mirrorX(() => sd.sphere({ pos: [0.018, 0.166, -0.172], r: 0.013, k: 0.012 }));
  sd.mirrorX(() => sd.ellipsoid({ pos: [0.148, 0.19, 0.018], r: [0.024, 0.044, 0.032], rot: [0, -0.3, 0.12], k: 0.014 }));
}

function surfZ(sd, G, x, y) {
  sd.snap(G, [x, y, -0.1]);
  let a = -0.35, b = 0;
  for (let i = 0; i < 40; i++) { const m = (a + b) / 2; const w = sd.toWorld([x, y, m]); if (G.fn(w[0], w[1], w[2]) > 0) a = m; else b = m; }
  return (a + b) / 2;
}

function headShapes(sd, ex) {
  headBase(sd, ex);
  const m = MOUTH[ex] || MOUTH.base;
  const G = sd.guide({ k: 0.07 }, () => headBase(sd, ex));
  cartoonMouth(sd, { ...m, z: surfZ(sd, G, 0, m.y) });
}

// Lips: a painted rosy ring around the carved mouth, following the expression (morph colors).
function lipsPaint(sd, ex) {
  const m = MOUTH[ex] || MOUTH.base;
  sd.paint({ color: LIPS, soft: 0.004, strength: 0.95, only: ['skin'] }, () => {
    sd.frame({ pos: [0, m.y + (m.R == null ? 0 : 0.002), -0.15], rot: [0, 0, m.roll || 0] }, () => {
      sd.ellipsoid({ pos: [0, 0, 0], r: [m.w + 0.009, (m.R == null ? m.h : m.h * 0.9) + 0.011, 0.08] });
    });
  });
}

function browShape(sd, s) {
  // groomed dark arch: thick inner end, peak at the outer third, tapered tail
  sd.bone('head', () => sd.frame({ scale: HS }, () => {
    const H = sd.guide({ k: 0.07 }, () => headBase(sd, null));
    const P = [[0.026, 0.298], [0.05, 0.313], [0.078, 0.321], [0.104, 0.308]];
    // lifts = the brow's half thickness + ~1 mm: a brow part that sinks into the skin hands its sideways normals to the
    // skin vertices under it (the baker shades the body with body + parts), which shows as pale wedges on the forehead
    const pts = sd.snapAll(H, P.map(([x, y]) => [x * s, y, -0.2]), [0.0048, 0.005, 0.0042, 0.0026]);
    sd.worm({ mat: 'brow', pts, r: [0.0082, 0.0086, 0.0068, 0.0032], flat: 0.45, up: [0, 0.25, -1], segs: 14 });
  }));
}

function afroVolume(sd, inset) {
  sd.ellipsoid({ pos: AFRO_E.c, r: AFRO_E.r.map((v) => v - inset) });
  sd.plane({ op: 'int', k: 0.03, n: BAND.n.map((v) => -v), d: -bandD(0.014) });           // behind the band
  sd.ellipsoid({ op: 'sub', k: 0.04, pos: [0, 0.19, -0.22], r: [0.15, 0.23, 0.2] });       // face tunnel
  sd.plane({ op: 'int', k: 0.03, n: [0, -1, 0], d: -0.07 });                               // bottom
}

// Fibonacci points on the afro ellipsoid, filtered to the visible puff layer (behind the band, clear of the face).
let _puffs = null;
function afroPuffs() {
  if (_puffs) return _puffs;
  const out = (_puffs = []);
  const N = 200;
  for (let i = 0; i < N; i++) {
    const y = 1 - (i + 0.5) / N * 2, rr = Math.sqrt(1 - y * y), th = i * 2.399963;
    const d = [Math.cos(th) * rr, y, Math.sin(th) * rr];
    const p = [AFRO_E.c[0] + d[0] * AFRO_E.r[0], AFRO_E.c[1] + d[1] * AFRO_E.r[1], AFRO_E.c[2] + d[2] * AFRO_E.r[2]];
    if (p[1] < 0.1) continue;                                                                  // nothing below the jaw
    const band = BAND.n[0] * p[0] + BAND.n[1] * p[1] + BAND.n[2] * p[2] - bandD(0);
    if (band < 0.012) continue;                                                                // stays behind the headband
    const fx = p[0] / 0.165, fy = (p[1] - 0.2) / 0.25;
    if (p[2] < -0.05 && fx * fx + fy * fy < 1) continue;                                       // keep the face clear
    const r = 0.052 + 0.014 * ((i * 7919) % 13) / 12;
    out.push({ p: [p[0] - d[0] * 0.028, p[1] - d[1] * 0.028, p[2] - d[2] * 0.028], r, ext: false });
  }
  // puffs over the CUT faces of the afro volume (just behind the headband, and the sides of the face tunnel), so
  // no smooth base shows there: candidates on a 1 cm grid where the cut plane / tunnel is the active surface,
  // picked greedily with the same spacing as the Fibonacci layer
  const E2 = AFRO_E.r.map((v) => v - 0.03), T = { c: [0, 0.19, -0.22], r: [0.15, 0.23, 0.2] };
  const ell = (q, c, r) => (Math.hypot((q[0] - c[0]) / r[0], (q[1] - c[1]) / r[1], (q[2] - c[2]) / r[2]) - 1) * Math.min(...r);
  const cand = [];
  for (let x = -0.34; x <= 0.34; x += 0.01) for (let y = 0.12; y <= 0.72; y += 0.01) for (let z = -0.3; z <= 0.2; z += 0.01) {
    const q = [x, y, z];
    const dE = ell(q, AFRO_E.c, E2), dP = bandD(0.014) - (BAND.n[1] * y + BAND.n[2] * z), dT = -ell(q, T.c, T.r);
    const m = Math.max(dE, dP, dT);
    if (Math.abs(m) > 0.005 || m === dE) continue;
    if (m === dT && y < 0.16) continue;                                   // leave the jaw / hoops clear
    const n = m === dP ? [0, BAND.n[1], BAND.n[2]] : (() => {           // inward normal (into the volume)
      const g = [(x - T.c[0]) / T.r[0] ** 2, (y - T.c[1]) / T.r[1] ** 2, (z - T.c[2]) / T.r[2] ** 2], l = Math.hypot(...g);
      return g.map((v) => v / l);
    })();
    const inset = m === dP ? 0.05 : 0.024;                               // behind the band: the band stays proud
    cand.push({ p: [x + n[0] * inset, y + n[1] * inset, z + n[2] * inset], r: 0.05 + 0.012 * (((x * 1000 + y * 377) | 0) % 5) / 4, ext: false });
  }
  for (const c of cand) {
    if (out.every((q) => Math.hypot(q.p[0] - c.p[0], q.p[1] - c.p[1], q.p[2] - c.p[2]) > 0.072)) out.push(c);
  }
  // outermost puffs (top, left, right, back): flagged ext (baked in the body, skipped by the part)
  const pick = (f) => out.reduce((a, q) => (f(q) > f(a) ? q : a), out[0]);
  for (const f of [(q) => q.p[1], (q) => q.p[0], (q) => -q.p[0], (q) => q.p[2]]) pick(f).ext = true;
  return out;
}

// ------------------------------------------------------------------------------------------------------------
function mergeGeos(THREE, geos) {
  const parts = geos.map((g) => (g.index ? g.toNonIndexed() : g));
  let n = 0;
  for (const g of parts) n += g.attributes.position.count;
  const pos = new Float32Array(n * 3), nrm = new Float32Array(n * 3), uv = new Float32Array(n * 2);
  let o = 0;
  for (const g of parts) {
    if (!g.attributes.normal) g.computeVertexNormals();
    pos.set(g.attributes.position.array, o * 3);
    nrm.set(g.attributes.normal.array, o * 3);
    if (g.attributes.uv) uv.set(g.attributes.uv.array, o * 2);
    o += g.attributes.position.count;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  out.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  return out;
}
// Long lashes: 3 curved tapered wings at the outer corner of each upper lid, parented to the lid group (they blink
// with it). Uses the eye rig made by b.eyes (root children: ball, glint, glint, upper, lower).
function lashWings(b, E, color) {
  const THREE = b.THREE;
  const mat = b.mat({ color, rough: 0.5, rim: 0.05 });
  for (const side of ['L', 'R']) {
    const root = b.joint('head').getObjectByName('eye' + side);
    if (!root || root.children.length < 5) continue;
    const upper = root.children[3];
    const sx = side === 'L' ? -1 : 1;                 // outer corner direction (eye L sits at -x)
    const lr = E.r * (E.lidScale ?? 1.06), cap = Math.PI * 0.53, y0 = lr * Math.cos(cap);
    const geos = [];
    [[0.95, 0.024, 0.0], [1.25, 0.03, 0.18], [1.55, 0.026, 0.36]].forEach(([th, len, up]) => {
      const p = new THREE.Vector3(sx * lr * Math.sin(th), y0, -lr * Math.cos(th));
      const out = new THREE.Vector3(sx * Math.sin(th), 0, -Math.cos(th)).normalize();
      const pts = [];
      for (let i = 0; i <= 6; i++) {
        const t = i / 6;
        pts.push(p.clone().addScaledVector(out, len * t).add(new THREE.Vector3(0, (0.35 + up) * len * t * t + 0.004 * t, 0)));
      }
      const g = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 8, 1, 5);
      // taper: scale the ring radius along the tube (0.0026 -> 0.0004)
      const P = g.attributes.position, C = new THREE.CatmullRomCurve3(pts);
      for (let s = 0; s <= 8; s++) {
        const c = C.getPointAt(s / 8), rad = 0.0026 * (1 - s / 8) + 0.0004;
        for (let k = 0; k <= 5; k++) {
          const idx = s * 6 + k;
          const v = new THREE.Vector3(P.getX(idx), P.getY(idx), P.getZ(idx)).sub(c).multiplyScalar(rad).add(c);
          P.setXYZ(idx, v.x, v.y, v.z);
        }
      }
      g.computeVertexNormals();
      geos.push(g);
    });
    const m = new THREE.Mesh(mergeGeos(THREE, geos), mat);
    m.name = 'lashWings';
    m.castShadow = false;
    upper.add(m);
  }
}

export default {
  id: 'roxy',
  name: 'Roxy Rivers',
  kind: 'hero',
  // 1.70 m (+ the afro): headScale 1.3 like Duke, long dancer legs, short torso with a bare midriff.
  rig: { height: 1.70, headScale: 1.3, shoulderW: 0.36, hipW: 0.25, legLen: 0.84, torsoLen: 0.44, armLen: 0.55 },
  bake: { voxel: 0.0042, tris: 15000, aoStrength: 0.8, aoReach: 0.1, morphMax: 0.04 },
  armOut: 0.2,
  // head costume slot on top of the afro (the puffs are a part, not counted by the runtime's hair scan)
  slots: { head: [0, 0.745, 0.05] },
  poseOffset: { hipL: [0, 0, -0.05], hipR: [0, 0, 0.05], footL: [0, 0, 0.05], footR: [0, 0, -0.05] },
  rim: { color: '#FFD9A0', strength: 0.45 },
  materials: {
    skin: { color: SKIN, rough: 0.46, sss: 0.8, wrap: 0.6, cav: 0.35, spec: 0.8 },
    afro: { color: '#ffffff', rough: 0.95, fuzz: 0.7, wrap: 0.6, spec: 0.05, cav: 0.8, bump: 0.6,
      pattern: { type: 'felt', color: AFRO, scale: 0.045 } },
    band: { color: '#ffffff', rough: 0.6, fuzz: 0.3, cav: 0.4,
      pattern: { type: 'floral', base: '#F6B21E', petal: '#E8541E', center: '#FFE27A', density: 4, scale: 0.09 } },
    brow: { color: BROW, rough: 0.45, sheen: 0.4, sheenExp: 50, wrap: 0.55, spec: 0.3, cav: 0.25 },
    shirt: { color: '#ffffff', rough: 0.66, fuzz: 0.3, lines: true, cav: 0.45,
      pattern: { type: 'floral', base: '#FBF3E4', petal: '#F28A1E', center: '#E8541E', density: 3, scale: 0.16 } },
    pants: { color: '#ffffff', rough: 0.72, fuzz: 0.3, lines: true, bump: 0.08, cav: 0.5,
      pattern: { type: 'denim', color: '#D8322B', twill: 150, scale: 0.05 } },
    leather: { color: '#6A3A1E', rough: 0.38, spec: 0.6, cav: 0.5 },
    gold: { color: '#EDB64C', metal: 1, rough: 0.2 },
    shoe: { color: '#DFCDB1', rough: 0.38, spec: 0.6, cav: 0.55 },
    sole: { color: '#8A5230', rough: 0.45, spec: 0.5, cav: 0.4 },
    mouth: { color: '#5C1C24', rough: 0.55, sss: 0.4, wrap: 0.6, cav: 0.1 },
    teeth: { color: '#FFF9F0', rough: 0.25, spec: 0.7, wrap: 0.6, cav: 0.1 },
    tongue: { color: '#E46F78', rough: 0.4, sss: 0.6, wrap: 0.6, cav: 0.1 },
  },
  anchors: () => ({ EYE }),
  expressions: ['smile', 'frown', 'o_mouth'],

  sculpt(sd, ctx) {
    const J = ctx.J;
    const Y = { hip: J.hips.pos[1], sh: J.shoulderL.pos[1], neck: J.neck.pos[1], head: J.head.pos[1] };

    // ---------------- neck + torso (skin) ----------------
    sd.group({ name: 'neck', mat: 'skin', bone: 'torso', k: 0.03 }, () => {
      sd.capsule({ a: [0, Y.sh - 0.04, 0.008], b: [0, Y.head + 0.07, 0.004], r: 0.047 });
    });
    sd.group({ name: 'body', mat: 'skin', bone: 'torso', k: 0.06, blend: 0.012 }, () => { torsoShapes(sd, Y); waistShapes(sd, Y); });
    // belly button: a soft painted dot
    sd.paint({ color: '#6E3D25', soft: 0.004, strength: 0.7, only: ['skin'] }, () => sd.ellipsoid({ pos: [0, Y.hip + 0.12, -0.08], r: [0.005, 0.008, 0.05] }));

    // ---------------- crop shirt: shell over the rib cage, V neckline, hem under the bust ----------------
    const CROP = Y.sh - 0.185;
    const shirtFrame = sd.patternFrame({ pos: [0, Y.sh - 0.08, 0], mode: 'cyl', radius: 0.13 });
    sd.group({ name: 'shirt', mat: 'shirt', bone: 'torso', blend: 0.004, k: 0, pframe: shirtFrame }, () => {
      sd.group({ offset: 0.004, shell: 0.0062, k: 0.06 }, () => { torsoShapes(sd, Y); waistShapes(sd, Y); });
      prism(sd, [[0, CROP + 0.035], [0.078, Y.sh + 0.2], [-0.078, Y.sh + 0.2]], { op: 'sub', max: -0.02, k: 0.008, blend: 0.004 });
      sd.box({ op: 'sub', k: 0.008, pos: [0, CROP - 0.2, 0], size: [0.4, 0.2, 0.4] });
    });
    // front knot: a round knot + two short tails
    const shirtG = sd.guide({ k: 0.06, offset: 0.01 }, () => { torsoShapes(sd, Y); waistShapes(sd, Y); });
    const kp = sd.snap(shirtG, [0, CROP + 0.012, -0.25], 0.004);
    sd.group({ name: 'knot', mat: 'shirt', bone: 'torso', k: 0.012, blend: 0.006, pframe: shirtFrame }, () => {
      sd.ellipsoid({ pos: kp, r: [0.024, 0.02, 0.016] });
      sd.mirrorX(() => {
        sd.ellipsoid({ pos: [kp[0] + 0.03, kp[1] - 0.014, kp[2] + 0.012], r: [0.028, 0.013, 0.01], rot: [0.2, 0.3, -0.5] });
        sd.ellipsoid({ pos: [kp[0] + 0.018, kp[1] - 0.03, kp[2] + 0.004], r: [0.012, 0.028, 0.009], rot: [0.15, 0, 0.35] });
      });
    });
    // collar: flat pointed flaps lying open along the V
    const FLAP = [[0.05, Y.sh + 0.045], [0.098, Y.sh + 0.05], [0.13, Y.sh - 0.015], [0.088, Y.sh - 0.1], [0.05, Y.sh - 0.02]];
    sd.group({ name: 'collar', mat: 'shirt', bone: 'torso', blend: 0.004, k: 0.01, pframe: shirtFrame }, () => {
      sd.group({ k: 0.004 }, () => {
        sd.frame({ pos: [0, Y.sh + 0.05, 0.012], rot: [-0.3, 0, 0] }, () => {
          sd.cylinder({ r: 0.07, h: 0.011, round: 0.005 });
          sd.cylinder({ op: 'sub', k: 0.004, r: 0.058, h: 0.04 });
        });
        prism(sd, [[0, Y.sh - 0.07], [0.075, Y.sh + 0.2], [-0.075, Y.sh + 0.2]], { op: 'sub', blend: 0.006, max: -0.01, k: 0.006 });
      });
      sd.group({ k: 0, blend: 0.01 }, () => {
        sd.group({ offset: 0.0112, shell: 0.0052, k: 0.06 }, () => torsoShapes(sd, Y));
        sd.group({ op: 'int', blend: 0.004, k: 0 }, () => sd.mirrorX(() => prism(sd, FLAP, { max: -0.01, k: 0.012 })));
      });
    });

    // ---------------- head ----------------
    sd.bone('head', () => sd.frame({ scale: HS }, () => {
      sd.group({ name: 'head', mat: 'skin', k: 0.07, blend: 0.02 }, () => headShapes(sd, sd.expr));
      lipsPaint(sd, sd.expr);
      // warm blush + highlight on the nose tip
      sd.paint({ color: '#B8694A', soft: 0.035, strength: 0.5, only: ['skin'] }, () => sd.mirrorX(() => sd.sphere({ pos: [0.084, 0.15, -0.13], r: 0.024 })));
      sd.paint({ color: '#AE6A48', soft: 0.02, strength: 0.4, only: ['skin'] }, () => sd.sphere({ pos: [0, 0.176, -0.205], r: 0.016 }));
      // eyeshadow: soft golden-brown above the eyes (shows when the lids close / on the brow bone)
      sd.paint({ color: '#7A4630', soft: 0.02, strength: 0.35, only: ['skin'] }, () => sd.mirrorX(() => sd.ellipsoid({ pos: [0.066, 0.27, -0.15], r: [0.03, 0.014, 0.05] })));

      // (the floral headband is the rigid part 'band': its own mesh keeps its edges crisp against the skin)

      // ---- afro: the puff mass is the rigid part 'afro' (own triangle budget: the face keeps its detail). Only the
      // five outermost puffs live in the body, so the runtime's hair scan gives Roxy afro-sized hair bounds. ----
      sd.group({ name: 'afroExt', mat: 'afro', blend: 0.004, k: 0.008, flow: [0, -1, 0] }, () => {
        for (const q of afroPuffs().filter((q) => q.ext)) sd.sphere({ pos: q.p, r: q.r });
      });
    }));

    // ---------------- belt + pants ----------------
    const pantFrame = sd.patternFrame({ pos: [0, Y.hip, 0], mode: 'cyl', radius: 0.14 });
    sd.group({ name: 'pelvis', mat: 'pants', bone: 'torso', k: 0.04, pframe: pantFrame, blend: 0.006 }, () => {
      sd.ellipsoid({ pos: [0, Y.hip + 0.025, 0.008], r: [0.152, 0.112, 0.114] });
      sd.ellipsoid({ pos: [0, Y.hip + 0.075, 0.008], r: [0.128, 0.05, 0.096] });
    });
    const BELT_Y = Y.hip + 0.07;
    sd.group({ name: 'belt', mat: 'leather', bone: 'torso' }, () => {
      sd.group({ offset: 0.005, k: 0.04 }, () => {
        sd.ellipsoid({ pos: [0, Y.hip + 0.025, 0.008], r: [0.152, 0.112, 0.114] });
        sd.ellipsoid({ pos: [0, Y.hip + 0.075, 0.008], r: [0.128, 0.05, 0.096] });
      });
      sd.box({ op: 'int', k: 0.004, pos: [0, BELT_Y, 0], size: [0.3, 0.017, 0.3], round: 0.002 });
    });
    sd.group({ name: 'buckle', mat: 'gold', bone: 'hips', rigid: true, k: 0.003 }, () => {
      sd.torus({ pos: [0, BELT_Y, -0.106], rot: [Math.PI / 2, 0, 0], R: 0.021, r: 0.0058 });
      sd.box({ pos: [0, BELT_Y, -0.105], size: [0.021, 0.0035, 0.004], round: 0.0025 });
    });
    const stitch = { mats: ['pants'], color: '#F4A58E', width: 0.0012 };
    sd.stitch([[0, BELT_Y - 0.02, -0.106], [0.0, Y.hip - 0.04, -0.104], [-0.026, Y.hip - 0.07, -0.096]], stitch);
    sd.mirrorX(() => sd.stitch([[0.052, BELT_Y - 0.018, -0.108], [0.086, Y.hip - 0.005, -0.096], [0.132, Y.hip - 0.02, -0.06]], stitch));
    sd.mirrorX(() => {
      sd.bone('hipL', () => {
        const fr = sd.patternFrame({ pos: [0, -0.35, 0], mode: 'cyl', radius: 0.08 });
        sd.group({ mat: 'pants', k: 0.05, pframe: fr, blend: 0.01 }, () => {
          sd.roundCone({ a: [0.012, 0.045, 0.006], b: [0, -0.31, 0.004], ra: 0.088, rb: 0.062 });
          sd.sphere({ pos: [0, -0.325, 0.002], r: 0.062 });
          // the strongest flare in the cast: a wide cone from the knee to the floor, flattened on the inner side and
          // pushed out so the two hems never touch in the bind pose (a merged hem would web between the legs)
          sd.cone({ pos: [-0.042, -0.5, 0.0], h: 0.17, r1: 0.19, r2: 0.062, round: 0.012, scale: [0.72, 1, 1.04] });
        });
        const out = [[-0.098, 0.05, 0], [-0.088, -0.15, 0], [-0.066, -0.32, 0], [-0.1, -0.46, 0], [-0.15, -0.6, 0], [-0.176, -0.66, 0]];
        sd.stitch(out, stitch);
        const hem = [];
        for (let i = 0; i <= 32; i++) { const a = (i / 32) * Math.PI * 2; hem.push([-0.042 + Math.sin(a) * 0.134, -0.655, Math.cos(a) * 0.194]); }
        sd.stitch(hem, { ...stitch, smooth: false });
      });
      sd.bone('footL', () => sd.frame({ scale: 1.14, pos: [0, 0.008, -0.01] }, () => {
        // cream platform shoe: rounded upper on a thick brown platform + chunky heel
        const upper = () => {
          sd.ellipsoid({ pos: [0, 0.002, -0.11], r: [0.062, 0.042, 0.125] });
          sd.ellipsoid({ pos: [0, 0.006, 0.012], r: [0.05, 0.044, 0.056] });
          sd.ellipsoid({ pos: [0, 0.022, -0.03], r: [0.046, 0.04, 0.07] });
        };
        sd.group({ mat: 'shoe', k: 0.035 }, upper);
        sd.group({ mat: 'sole', k: 0.012, blend: 0.004 }, () => {
          sd.box({ pos: [0, -0.046, -0.07], size: [0.064, 0.022, 0.13], round: 0.016 });     // platform
          sd.box({ pos: [0, -0.046, 0.03], size: [0.052, 0.024, 0.042], round: 0.014 });     // heel block
        });
      }));
    });

    // ---------------- arms ----------------
    sd.mirrorX(() => {
      sd.bone('shoulderL', () => {
        const slv = sd.patternFrame({ pos: [0, -0.06, 0], mode: 'cyl', radius: 0.07 });
        sd.group({ mat: 'shirt', k: 0.035, blend: 0.035, pframe: slv }, () => {
          sd.ellipsoid({ pos: [0.006, -0.055, 0], r: [0.066, 0.075, 0.066] });              // puff sleeve
        });
        sd.group({ mat: 'shirt', k: 0.006, blend: 0.004, pframe: slv }, () => {
          sd.torus({ pos: [0, -0.118, 0], R: 0.047, r: 0.012 });                           // rolled cuff
        });
        sd.roundCone({ mat: 'skin', a: [0, -0.08, 0], b: [0, -0.215, 0], ra: 0.042, rb: 0.038, k: 0.01 });
      });
      sd.bone('elbowL', () => {
        sd.roundCone({ mat: 'skin', a: [0, 0.03, 0], b: [0, -0.235, 0], ra: 0.039, rb: 0.032, k: 0.01 });
      });
      sd.bone('handL', () => sd.frame({ scale: 1.14, pos: [0, 0.006, 0] }, () => {
        sd.group({ mat: 'skin', k: 0.01, blend: 0.012 }, () => {
          sd.roundCone({ a: [0, 0.012, 0], b: [0.002, -0.03, 0], ra: 0.03, rb: 0.036, k: 0.015 });
          sd.box({ pos: [0.002, -0.055, 0], size: [0.02, 0.047, 0.044], round: 0.019, k: 0.015 });
          sd.ellipsoid({ pos: [0.012, -0.045, -0.029], r: [0.016, 0.028, 0.02], k: 0.012 });
          const fz = [-0.033, -0.011, 0.011, 0.032], fl = [0.064, 0.072, 0.068, 0.056];
          for (let i = 0; i < 4; i++) {
            const z = fz[i], l = fl[i], sp = (i - 1.5) * 0.003;
            sd.worm({ pts: [[0.002, -0.088, z], [0.008, -0.088 - l * 0.55, z + sp], [0.018, -0.088 - l, z + sp * 1.5]], r: [0.0098, 0.0094, 0.0086], k: 0.004, segs: 8 });
            sd.sphere({ pos: [-0.008, -0.088, z], r: 0.0098, k: 0.008 });
          }
          sd.worm({ pts: [[0.012, -0.028, -0.036], [0.022, -0.053, -0.058], [0.03, -0.075, -0.062]], r: [0.0142, 0.012, 0.0108], k: 0.01, segs: 8 });
        });
        // nail polish: red fingertips
        sd.paint({ color: '#D8322B', soft: 0.002, strength: 0.9, only: ['skin'] }, () => {
          const fz = [-0.033, -0.011, 0.011, 0.032], fl = [0.064, 0.072, 0.068, 0.056];
          for (let i = 0; i < 4; i++) sd.sphere({ pos: [0.024, -0.088 - fl[i] + 0.004, fz[i] + (i - 1.5) * 0.0045], r: 0.0085 });
        });
      }));
    });
  },

  parts: {
    band: { bone: 'head', tris: 900, voxel: 0.0034, sculpt(sd) {
      sd.bone('head', () => sd.frame({ scale: HS }, () => {
        sd.group({ name: 'band', mat: 'band', k: 0 }, () => {
          sd.ellipsoid({ pos: SKULL.c, r: SKULL.r.map((v) => v + 0.013), shell: 0.0095 });
          sd.plane({ op: 'int', k: 0.004, n: BAND.n, d: bandD(BAND.half) });
          sd.plane({ op: 'int', k: 0.004, n: BAND.n.map((v) => -v), d: -bandD(-BAND.half) });
          sd.plane({ op: 'int', k: 0.01, n: [0, -1, 0], d: -0.2 });
        });
      }));
    } },
    // the afro's round puffs: rigid on the head, own budget (the body keeps ~15k for the face and costume)
    afro: { bone: 'head', tris: 5300, voxel: 0.0045, sculpt(sd) {
      sd.bone('head', () => sd.frame({ scale: HS }, () => {
        sd.group({ name: 'puffs', mat: 'afro', k: 0.008, flow: [0, -1, 0] }, () => {
          sd.group({ k: 0.04 }, () => afroVolume(sd, 0.06));          // crevice floor (only exposed between puffs)
          for (const q of afroPuffs()) if (!q.ext) sd.sphere({ pos: q.p, r: q.r });
        });
      }));
    } },
    browL: { bone: 'head', tris: 380, sculpt(sd) { browShape(sd, 1); } },
    browR: { bone: 'head', tris: 380, sculpt(sd) { browShape(sd, -1); } },
  },

  attachments(b) {
    const THREE = b.THREE;
    const HG = new THREE.Group();
    HG.name = 'headScaled';
    HG.scale.setScalar(HS);
    b.joint('head').add(HG);
    const ES = { ...EYE, x: EYE.x * HS, y: EYE.y * HS, z: EYE.z * HS, r: EYE.r * HS };
    b.eyes(ES);
    lashWings(b, ES, EYE.lash);
    // big gold hoops hanging at the jaw line, just outside the afro edge
    const hoops = [];
    for (const s of [1, -1]) {
      const g = new THREE.TorusGeometry(0.036, 0.0058, 10, 36);
      g.rotateY(s * 0.6);
      g.translate(s * 0.158, 0.098, 0.004);
      hoops.push(g);
    }
    b.mesh(HG, mergeGeos(THREE, hoops), b.mat({ color: '#FFC23A', metal: 1, rough: 0.2, envIntensity: 1.2 }), { name: 'hoops' });
  },
};
