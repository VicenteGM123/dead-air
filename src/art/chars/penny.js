// PENNY WATTS v1 — night-shift broadcast engineer (GDD §4, ref docs/ref/hero_glasses.png). Same recipes and finish as
// the approved Duke (src/art/chars/duke.js, docs/CHARKIT.md, docs/STYLE_GUIDE.md): SIMPLIFY + EXAGGERATE.
//   - Long wavy brown molded-toy hair: crown + a big side-swept fringe + two face-framing side curtains + a back curtain
//     ending in wavy S-locks with flicked tips; orange headband behind the fringe.
//   - Big brown eyes with lashes behind round chunky black glasses, rosy cheeks, gentle smile, gold hoops.
//   - Orange ribbed turtleneck (knit pattern, folded neck roll, ribbed cuffs), gold medallion on a chain.
//   - Brown corduroy A-line mini skirt with 4 gold buttons and stitching, wide brown belt + round gold buckle,
//     dark brown tights, cream knee-high go-go boots with brown heels and soles.
// Layout: world coords for torso/skirt/back hair (feet y=0, facing -z), bone-local for limbs and head (head scaled by HS).
import { EYE_DEFAULTS } from './_face.js';
import { cartoonMouth, prism } from './_sculpt.js';

const SKIN = '#F5C3A2';
const HAIR = '#6B3A22';
const BROW = '#553020';

const HS = 1.06;
const EYE = {
  ...EYE_DEFAULTS, x: 0.064, y: 0.228, z: -0.128, r: 0.045, iris: '#9A5626', irisSize: 0.66, pupilSize: 0.44,
  lid: '#F0B08E', lash: '#1E120E', lidOpen: 1.0, lowerLid: 0.62, lidScale: 1.04, yaw: 0.07, glint: 1.15, tilt: 0.03,
};
const SKULL = { c: [0, 0.266, 0.012], r: [0.152, 0.174, 0.162] };
const MOUTH = {
  base: { y: 0.1, w: 0.039, h: 0.013, top: 0.097, R: 0.07, teeth: 0.9, roll: -0.04, clip: true },
  smile: { y: 0.099, w: 0.048, h: 0.025, top: 0.093, R: 0.06, teeth: 0.75, roll: -0.03, clip: true },
  frown: { y: 0.095, w: 0.033, h: 0.012, top: 0.103, R: -0.09, teeth: 0.4, tongue: false, roll: 0.0, clip: true },
  o_mouth: { y: 0.093, w: 0.025, h: 0.026, top: 0.12, R: null, teeth: 0.35, roll: 0.001, clip: true },
};
const CROWN = { c: [0, 0.29, 0.02], r: [0.172, 0.186, 0.186] };
// headband plane: over the top of the head from ear to ear, just behind the fringe
const HB = { n: [0, 0.371, 0.928], p: [0, 0.45, -0.1], half: 0.019 };
const hbD = (off) => HB.n[1] * HB.p[1] + HB.n[2] * HB.p[2] + off;

// ------------------------------------------------------------------------------------------------------------
function torsoShapes(sd, Y) {
  sd.ellipsoid({ pos: [0, Y.sh - 0.08, 0.004], r: [0.148, 0.11, 0.1] });          // rib cage
  sd.mirrorX(() => sd.sphere({ pos: [0.05, Y.sh - 0.112, -0.05], r: 0.054, k: 0.05 }));   // modest bust
  sd.ellipsoid({ pos: [0, Y.hip + 0.14, 0.008], r: [0.12, 0.11, 0.092] });        // waist
  sd.ellipsoid({ pos: [0, Y.sh - 0.012, 0.01], r: [0.165, 0.044, 0.082] });       // shoulder yoke
}

function headBase(sd, ex) {
  const smile = ex === 'smile' ? 1 : 0;
  sd.ellipsoid({ pos: SKULL.c, r: SKULL.r });
  sd.ellipsoid({ pos: [0, 0.212, -0.056], r: [0.134, 0.096, 0.096], k: 0.06 });
  sd.ellipsoid({ pos: [0, 0.148, -0.034], r: [0.114, 0.104, 0.122], k: 0.07 });                // slim oval jaw
  sd.ellipsoid({ pos: [0, 0.07, -0.078], r: [0.04, 0.032, 0.04], k: 0.05 });
  sd.mirrorX(() => sd.sphere({ pos: [0.07, 0.146 + smile * 0.012, -0.1 - smile * 0.004], r: 0.047 + smile * 0.004, k: 0.05 }));
  sd.capsule({ a: [0, 0.226, -0.15], b: [0, 0.19, -0.176], r: 0.014, k: 0.02 });
  sd.sphere({ pos: [0, 0.176, -0.184], r: 0.02, k: 0.016 });
  sd.mirrorX(() => sd.sphere({ pos: [0.017, 0.168, -0.172], r: 0.012, k: 0.012 }));
  sd.mirrorX(() => sd.ellipsoid({ pos: [0.148, 0.19, 0.018], r: [0.024, 0.044, 0.032], rot: [0, -0.3, 0.12], k: 0.014 }));
}

// Molded-toy hair lock laid on the CROWN guide (Duke's recipe): path [[az, el, lift]] in degrees, analytic normals.
function onE(E, az, el) {
  const a = az * Math.PI / 180, e = el * Math.PI / 180;
  return [E.c[0] + Math.sin(a) * Math.cos(e) * E.r[0], E.c[1] + Math.sin(e) * E.r[1], E.c[2] - Math.cos(a) * Math.cos(e) * E.r[2]];
}
function hairLock(sd, path, r, o = {}) {
  const E = CROWN, pts = [], ups = [];
  for (const [az, el, lift] of path) {
    const q = onE(E, az, el);
    const n = [(q[0] - E.c[0]) / E.r[0] ** 2, (q[1] - E.c[1]) / E.r[1] ** 2, (q[2] - E.c[2]) / E.r[2] ** 2];
    const l = Math.hypot(...n), u = n.map((v) => v / l);
    pts.push([q[0] + u[0] * lift, q[1] + u[1] * lift, q[2] + u[2] * lift]);
    ups.push(u);
  }
  return sd.worm({ pts, r, flat: o.flat ?? 0.55, up: ups[0], ups, k: o.k, segs: o.segs || 20 });
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

function lipsPaint(sd, ex) {
  const m = MOUTH[ex] || MOUTH.base;
  sd.paint({ color: '#E0707A', soft: 0.003, strength: 0.65, only: ['skin'] }, () => {
    sd.frame({ pos: [0, m.y + (m.R == null ? 0 : 0.002), -0.15], rot: [0, 0, m.roll || 0] }, () => {
      sd.ellipsoid({ pos: [0, 0, 0], r: [m.w + 0.005, Math.min(m.h, 0.02) * 0.85 + 0.007, 0.08] });
    });
  });
}

function browShape(sd, s) {
  sd.bone('head', () => sd.frame({ scale: HS }, () => {
    const H = sd.guide({ k: 0.07 }, () => headBase(sd, null));
    const up = s < 0 ? 0.004 : 0;   // the left brow (-x) a little higher: curious engineer
    const P = [[0.026, 0.304 + up], [0.05, 0.316 + up], [0.076, 0.322 + up], [0.102, 0.312 + up]];
    // lifts = the brow's half thickness + ~1 mm: a brow part that sinks into the skin hands its sideways normals to the
    // skin vertices under it (the baker shades the body with body + parts), which shows as pale wedges on the forehead
    const pts = sd.snapAll(H, P.map(([x, y]) => [x * s, y, -0.2]), [0.0044, 0.0048, 0.0043, 0.003]);
    sd.worm({ mat: 'brow', pts, r: [0.0074, 0.0084, 0.0072, 0.0038], flat: 0.45, up: [0, 0.25, -1], segs: 14 });
  }));
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
// Round chunky glasses: one merged frame mesh (rims, bridge, temples) + one merged lens mesh.
function roundGlasses(b, o) {
  const THREE = b.THREE, E = o.eye;
  const R = o.r, t = o.thick, zf = o.z;
  const frames = [], lenses = [];
  for (const s of [1, -1]) {
    const cx = s * E.x;
    const outer = new THREE.Shape(); outer.absellipse(0, 0, R, R * (o.squash ?? 1), 0, Math.PI * 2);
    const inner = new THREE.Path(); inner.absellipse(0, 0, R - t, (R - t) * (o.squash ?? 1), 0, Math.PI * 2, true);
    outer.holes.push(inner);
    const g = new THREE.ExtrudeGeometry(outer, { depth: o.depth, bevelEnabled: true, bevelThickness: o.depth * 0.35, bevelSize: t * 0.22, bevelSegments: 2, curveSegments: 40 });
    g.translate(0, 0, -o.depth / 2);
    g.rotateY(-s * (o.wrap ?? 0.1));
    g.translate(cx, E.y + (o.dy || 0), zf);
    frames.push(g);
    const lsh = new THREE.Shape(); lsh.absellipse(0, 0, R - t * 0.7, (R - t * 0.7) * (o.squash ?? 1), 0, Math.PI * 2);
    const lg = new THREE.ShapeGeometry(lsh, 24);
    lg.rotateY(-s * (o.wrap ?? 0.1));
    lg.translate(cx, E.y + (o.dy || 0), zf + 0.001);
    lenses.push(lg);
    const ca = Math.cos(o.wrap ?? 0.1), sa = Math.sin(o.wrap ?? 0.1);
    const ax = cx + s * R * ca * 0.98, az = zf + R * sa;
    const tA = new THREE.Vector3(ax, E.y + (o.dy || 0) + R * 0.25, az + 0.004);
    const tB = new THREE.Vector3(s * o.templeX, E.y + (o.dy || 0) + R * 0.3, az + 0.07);
    const tC = new THREE.Vector3(s * (o.templeX + 0.004), E.y + (o.dy || 0) + R * 0.05, o.earZ);
    frames.push(new THREE.TubeGeometry(new THREE.CatmullRomCurve3([tA, tB, tC]), 14, t * 0.34, 6));
  }
  const bl = new THREE.Vector3(-E.x + R * 0.97, E.y + (o.dy || 0) + R * 0.2, zf);
  const br = new THREE.Vector3(E.x - R * 0.97, E.y + (o.dy || 0) + R * 0.2, zf);
  frames.push(new THREE.TubeGeometry(new THREE.CatmullRomCurve3([bl, new THREE.Vector3(0, E.y + (o.dy || 0) + R * 0.36, zf - 0.006), br]), 10, t * 0.4, 6));
  const frameMat = b.mat({ color: o.color || '#1B1520', rough: 0.28, rim: 0.18, envIntensity: 0.9 });
  // lenses barely there (a faint reflection): the big eyes must keep their warm color behind the glass
  const glassMat = b.mat({ color: '#EAF4FF', rough: 0.05, transparent: true, opacity: 0.045, envIntensity: 0.55, rim: 0.08, rimColor: '#FFFFFF' });
  b.mesh(o.parent || 'head', mergeGeos(THREE, frames), frameMat, { name: 'glassesFrame' });
  const lens = b.mesh(o.parent || 'head', mergeGeos(THREE, lenses), glassMat, { name: 'glassesLens', cast: false });
  lens.renderOrder = 3;
}
function lashWings(b, E, color) {
  const THREE = b.THREE;
  const mat = b.mat({ color, rough: 0.5, rim: 0.05 });
  for (const side of ['L', 'R']) {
    const root = b.joint('head').getObjectByName('eye' + side);
    if (!root || root.children.length < 5) continue;
    const upper = root.children[3];
    const sx = side === 'L' ? -1 : 1;
    const lr = E.r * (E.lidScale ?? 1.06), cap = Math.PI * 0.53, y0 = lr * Math.cos(cap);
    const geos = [];
    [[1.05, 0.02, 0.05], [1.35, 0.024, 0.2]].forEach(([th, len, up]) => {
      const p = new THREE.Vector3(sx * lr * Math.sin(th), y0, -lr * Math.cos(th));
      const out = new THREE.Vector3(sx * Math.sin(th), 0, -Math.cos(th)).normalize();
      const pts = [];
      for (let i = 0; i <= 6; i++) { const t = i / 6; pts.push(p.clone().addScaledVector(out, len * t).add(new THREE.Vector3(0, (0.35 + up) * len * t * t + 0.004 * t, 0))); }
      const C = new THREE.CatmullRomCurve3(pts);
      const g = new THREE.TubeGeometry(C, 8, 1, 5);
      const P = g.attributes.position;
      for (let s = 0; s <= 8; s++) {
        const c = C.getPointAt(s / 8), rad = 0.0024 * (1 - s / 8) + 0.0004;
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
  id: 'penny',
  name: 'Penny Watts',
  kind: 'hero',
  // 1.68 m: headScale 1.3 like Duke; long legs in tights, short torso under the turtleneck.
  rig: { height: 1.68, headScale: 1.3, shoulderW: 0.36, hipW: 0.25, legLen: 0.84, torsoLen: 0.44, armLen: 0.55 },
  bake: { voxel: 0.0042, tris: 20200, aoStrength: 0.85, aoReach: 0.1, morphMax: 0.04 },
  armOut: 0.22,
  poseOffset: { hipL: [0, 0, -0.04], hipR: [0, 0, 0.04], footL: [0, 0, 0.04], footR: [0, 0, -0.04] },
  rim: { color: '#FFD9A0', strength: 0.4 },
  materials: {
    skin: { color: SKIN, rough: 0.5, sss: 1, wrap: 0.6, cav: 0.35 },
    hair: { color: HAIR, rough: 0.4, sheen: 1.0, sheenExp: 65, wrap: 0.55, spec: 0.35, cav: 0.5 },
    band: { color: '#F0721E', rough: 0.45, spec: 0.6, cav: 0.4 },
    brow: { color: BROW, rough: 0.45, sheen: 0.5, sheenExp: 50, wrap: 0.55, spec: 0.3, cav: 0.25 },
    knit: { color: '#ffffff', rough: 0.8, fuzz: 0.45, bump: 0.25, cav: 0.5,
      pattern: { type: 'knit', color: '#F0641E', ribs: 14, scale: 0.09 } },
    cord: { color: '#ffffff', rough: 0.8, fuzz: 0.5, lines: true, bump: 0.3, cav: 0.5,
      pattern: { type: 'corduroy', color: '#83492A', ribs: 24, scale: 0.1 } },
    leather: { color: '#62371D', rough: 0.36, spec: 0.6, cav: 0.5 },
    gold: { color: '#EDB64C', metal: 1, rough: 0.2 },
    tights: { color: '#4E2C25', rough: 0.55, sss: 0.2, fuzz: 0.2, spec: 0.5, cav: 0.4 },
    boot: { color: '#E8DAC0', rough: 0.2, spec: 0.95, cav: 0.5 },
    sole: { color: '#6A3D22', rough: 0.45, spec: 0.5, cav: 0.4 },
    mouth: { color: '#5C1C24', rough: 0.55, sss: 0.4, wrap: 0.6, cav: 0.1 },
    teeth: { color: '#FFF9F0', rough: 0.25, spec: 0.7, wrap: 0.6, cav: 0.1 },
    tongue: { color: '#E46F78', rough: 0.4, sss: 0.6, wrap: 0.6, cav: 0.1 },
  },
  anchors: () => ({ EYE }),
  expressions: ['smile', 'frown', 'o_mouth'],

  sculpt(sd, ctx) {
    const J = ctx.J;
    const Y = { hip: J.hips.pos[1], sh: J.shoulderL.pos[1], neck: J.neck.pos[1], head: J.head.pos[1] };
    const H0 = Y.head;   // world y of the head joint (head-local = (world - [0, H0, 0]) / HS)

    // ---------------- neck + sweater body ----------------
    sd.group({ name: 'neck', mat: 'skin', bone: 'torso', k: 0.03 }, () => {
      sd.capsule({ a: [0, Y.sh - 0.04, 0.008], b: [0, Y.head + 0.07, 0.004], r: 0.047 });
    });
    const knitFrame = sd.patternFrame({ pos: [0, Y.sh - 0.1, 0], mode: 'cyl', radius: 0.13 });
    sd.group({ name: 'sweater', mat: 'knit', bone: 'torso', k: 0.06, blend: 0.012, pframe: knitFrame }, () => torsoShapes(sd, Y));
    // turtleneck: a tube up the neck + a thick folded roll
    const neckFrame = sd.patternFrame({ pos: [0, Y.sh + 0.05, 0.006], mode: 'cyl', radius: 0.06 });
    sd.group({ name: 'turtle', mat: 'knit', bone: 'torso', k: 0.02, blend: 0.03, pframe: neckFrame }, () => {
      sd.roundCone({ a: [0, Y.sh - 0.01, 0.01], b: [0, Y.head - 0.005, 0.006], ra: 0.068, rb: 0.058 });
      sd.torus({ pos: [0, Y.sh + 0.035, 0.008], rot: [-0.08, 0, 0], R: 0.058, r: 0.026 });
    });
    // gold medallion on a chain
    const sweaterG = sd.guide({ k: 0.06 }, () => torsoShapes(sd, Y));
    const mp = sd.snap(sweaterG, [0, Y.sh - 0.15, -0.3], 0.004);
    sd.group({ name: 'medallion', mat: 'gold', bone: 'chest', rigid: true, blend: 0.003, k: 0.003 }, () => {
      sd.frame({ pos: mp, rot: [-Math.PI / 2 + 0.25, 0, 0] }, () => {
        sd.cylinder({ r: 0.027, h: 0.004, round: 0.003 });
        sd.torus({ pos: [0, 0.004, 0], R: 0.022, r: 0.0035 });
        sd.sphere({ pos: [0, 0.004, 0], r: 0.009, scale: [1, 0.4, 1] });
      });
      sd.torus({ pos: [mp[0], mp[1] + 0.034, mp[2] + 0.002], rot: [0, 0, Math.PI / 2], R: 0.007, r: 0.0028 });
      // chain: from the bail up the chest to the neck roll on both sides
      sd.mirrorX(() => {
        const pts = sd.snapAll(sweaterG, [[0.004, mp[1] + 0.04, -0.3], [0.03, Y.sh - 0.06, -0.3], [0.052, Y.sh + 0.0, -0.3]], 0.004);
        sd.worm({ pts: [...pts, [0.062, Y.sh + 0.02, -0.04]], r: 0.0042, segs: 16 });
      });
    });

    // ---------------- skirt + belt ----------------
    const WAIST = Y.hip + 0.095;
    const skirtFrame = sd.patternFrame({ pos: [0, Y.hip, 0], mode: 'cyl', radius: 0.16 });
    // A-line: skinned to the hips and both thighs (the front follows each leg a little when walking)
    sd.group({ name: 'skirt', mat: 'cord', bone: ['hips', 'hipL', 'hipR', 'spine'], k: 0.05, blend: 0.01, pframe: skirtFrame }, () => {
      sd.ellipsoid({ pos: [0, Y.hip + 0.06, 0.008], r: [0.156, 0.075, 0.114] });
      sd.cone({ pos: [0, Y.hip - 0.07, 0.01], h: 0.13, r1: 0.21, r2: 0.172, round: 0.014, scale: [1, 1, 0.84] });
    });
    const BELT_Y = WAIST - 0.01;
    sd.group({ name: 'belt', mat: 'leather', bone: 'torso', blend: 0.004 }, () => {
      sd.group({ offset: 0.006, k: 0.05 }, () => {
        sd.ellipsoid({ pos: [0, Y.hip + 0.14, 0.008], r: [0.12, 0.11, 0.092] });
        sd.ellipsoid({ pos: [0, Y.hip + 0.06, 0.008], r: [0.156, 0.075, 0.114] });
      });
      sd.box({ op: 'int', k: 0.004, pos: [0, BELT_Y, 0], size: [0.3, 0.021, 0.3], round: 0.002 });
    });
    const beltG = sd.guide({ offset: 0.006, k: 0.05 }, () => {
      sd.ellipsoid({ pos: [0, Y.hip + 0.14, 0.008], r: [0.12, 0.11, 0.092] });
      sd.ellipsoid({ pos: [0, Y.hip + 0.06, 0.008], r: [0.14, 0.07, 0.108] });
    });
    const bp = sd.snap(beltG, [0, BELT_Y, -0.3], 0.002);
    sd.group({ name: 'buckle', mat: 'gold', bone: 'hips', rigid: true, k: 0.003 }, () => {
      sd.frame({ pos: bp, rot: [-Math.PI / 2, 0, 0] }, () => {
        sd.cylinder({ r: 0.027, h: 0.005, round: 0.004 });
        sd.cylinder({ op: 'sub', k: 0.002, pos: [0, 0.004, 0], r: 0.017, h: 0.004, round: 0.002 });
      });
      sd.box({ mat: 'leather', pos: [bp[0], bp[1], bp[2] - 0.002], size: [0.016, 0.009, 0.004], round: 0.003 });
    });
    // 4 gold buttons down the front of the skirt
    const skirtG = sd.guide({ k: 0.05 }, () => {
      sd.ellipsoid({ pos: [0, Y.hip + 0.06, 0.008], r: [0.156, 0.075, 0.114] });
      sd.cone({ pos: [0, Y.hip - 0.07, 0.01], h: 0.13, r1: 0.21, r2: 0.172, round: 0.014, scale: [1, 1, 0.84] });
    });
    for (let i = 0; i < 4; i++) {
      const by = BELT_Y - 0.05 - i * 0.047;
      sd.sphere({ mat: 'gold', bone: 'hips', rigid: true, pos: sd.snap(skirtG, [0, by, -0.3], 0.001), r: 0.0095, scale: [1, 1, 0.6], k: 0.002 });
    }
    const st = { mats: ['cord'], color: '#E6A15C', width: 0.0013 };
    sd.stitch([[0.022, BELT_Y - 0.03, -0.3], [0.022, Y.hip - 0.19, -0.3]], st);
    sd.stitch([[-0.022, BELT_Y - 0.03, -0.3], [-0.022, Y.hip - 0.19, -0.3]], st);
    const hem = [];
    for (let i = 0; i <= 36; i++) { const a = (i / 36) * Math.PI * 2; hem.push([Math.sin(a) * 0.2, Y.hip - 0.188, 0.01 + Math.cos(a) * 0.168]); }
    sd.stitch(hem, { ...st, smooth: false });
    sd.mirrorX(() => sd.stitch([[0.06, BELT_Y - 0.03, -0.14], [0.1, BELT_Y - 0.07, -0.12], [0.14, BELT_Y - 0.08, -0.07]], st));

    // ---------------- head ----------------
    sd.bone('head', () => sd.frame({ scale: HS }, () => {
      sd.group({ name: 'head', mat: 'skin', k: 0.07, blend: 0.02 }, () => headShapes(sd, sd.expr));
      lipsPaint(sd, sd.expr);
      sd.paint({ color: '#F08A86', soft: 0.035, strength: 0.7, only: ['skin'] }, () => sd.mirrorX(() => sd.sphere({ pos: [0.085, 0.15, -0.13], r: 0.028 })));
      sd.paint({ color: '#F29C8A', soft: 0.02, strength: 0.45, only: ['skin'] }, () => sd.sphere({ pos: [0, 0.176, -0.205], r: 0.016 }));

      // (the orange headband is the rigid part 'hband': its own mesh keeps its edges crisp against hair and skin)

      // ---- hair on the head: crown with a soft side part + one big side-swept fringe lock ----
      sd.group({ name: 'hairTop', mat: 'hair', blend: 0.012, k: 0.03, flow: (x, y, z) => [x * 1.5 - 0.5, -1, 0.5] }, () => {
        sd.group({ k: 0.04 }, () => {
          sd.ellipsoid({ pos: CROWN.c, r: CROWN.r });
          sd.ellipsoid({ op: 'sub', k: 0.03, pos: [0, 0.2, -0.21], r: [0.142, 0.21, 0.19] });                 // face opening
        });
        // fringe: from the part (+x) sweeping down across the forehead to the left temple (-x), laid on the crown
        // flat on the forehead: long axis along the sweep (Rz), thin axis along the forehead normal (Rx), the left
        // end following the head's curve back (Ry)
        sd.group({ k: 0.035 }, () => {
          sd.ellipsoid({ pos: [-0.032, 0.366, -0.122], r: [0.108, 0.04, 0.022], rot: [0.57, 0.3, 0.67] });
          sd.ellipsoid({ pos: [-0.12, 0.3, -0.088], r: [0.05, 0.034, 0.02], rot: [0.3, 0.8, 1.0] });
        });
        // a smaller lock on the part side, tucked behind the headband to the right temple
        hairLock(sd, [[40, 42, 0.0], [58, 30, 0.012], [74, 14, 0.014], [88, 0, 0.01]], [0.028, 0.038, 0.032, 0.012], { flat: 0.45 });
      });
    }));

    // ---------------- long hair: side curtains + back curtain with a wavy scalloped hem (world coords) ----------------
    // Skinned head -> neck -> chest (nearest segment): the lengths below the neck follow the chest. Kept behind the
    // shoulders (z > 0.06) and inside |x| < 0.18 so the arms never plough through it.
    const W = (x, y, z) => [x * HS, H0 + y * HS, z * HS];   // head-local -> world
    sd.group({ name: 'hairLong', mat: 'hair', bone: ['head', 'neck', 'chest'], blend: 0.014, k: 0.045, flow: (x, y, z) => [x * 0.3, -1, 0.1] }, () => {
      // back of the head + nape
      sd.ellipsoid({ pos: W(0, 0.2, 0.07), r: [0.2, 0.21, 0.165] });
      // curtains over the ears (framing the face), falling behind the shoulders
      sd.mirrorX(() => {
        sd.ellipsoid({ pos: W(0.16, 0.19, 0.03), r: [0.054, 0.17, 0.09] });
        sd.ellipsoid({ pos: [0.15, Y.sh + 0.03, 0.09], r: [0.052, 0.11, 0.055] });
        sd.ellipsoid({ pos: [0.16, Y.sh - 0.12, 0.105], r: [0.05, 0.1, 0.05] });
        // S-wave bulges along the outer edge of the curtain
        sd.sphere({ pos: [0.172, Y.sh + 0.1, 0.075], r: 0.045 });
        sd.sphere({ pos: [0.18, Y.sh - 0.08, 0.105], r: 0.048 });
      });
      // back curtain down to the shoulder blades
      sd.ellipsoid({ pos: [0, Y.sh - 0.03, 0.125], r: [0.17, 0.17, 0.052] });
      // scalloped hem: four round wave lobes
      for (const [x, dy] of [[-0.105, 0.0], [0.0, -0.02], [0.105, -0.005]]) sd.sphere({ pos: [x, Y.sh - 0.185 + dy, 0.128], r: 0.064 });
    });
    // flicked tips at the curtain ends (small C-curls turning outward)
    sd.mirrorX(() => sd.arc({ mat: 'hair', bone: 'chest', pos: [0.175, Y.sh - 0.22, 0.1], rot: [0.2, 1.3, 2.0], R: 0.028, r: 0.019, angle: Math.PI * 1.1, k: 0.02 }));

    // ---------------- legs (tights) + go-go boots ----------------
    sd.mirrorX(() => {
      sd.bone('hipL', () => {
        sd.group({ mat: 'tights', k: 0.04, blend: 0.012 }, () => {
          sd.roundCone({ a: [0.018, 0.02, 0.006], b: [0, -0.3, 0.004], ra: 0.07, rb: 0.056 });
          sd.sphere({ pos: [0, -0.31, 0.002], r: 0.058 });
        });
      });
      sd.bone('kneeL', () => {
        sd.roundCone({ mat: 'tights', a: [0, 0.0, 0.002], b: [0, -0.1, 0.004], ra: 0.057, rb: 0.056, k: 0.02 });
        // boot shaft: from just below the knee to the ankle, clean rolled top edge
        sd.group({ mat: 'boot', k: 0.03, blend: 0.004 }, () => {
          sd.roundCone({ a: [0, -0.035, 0.004], b: [0, -0.2, 0.01], ra: 0.068, rb: 0.064 });       // calf
          sd.roundCone({ a: [0, -0.2, 0.01], b: [0, -0.3, 0.004], ra: 0.064, rb: 0.049 });         // ankle
          sd.cylinder({ pos: [0, -0.034, 0.004], r: 0.071, h: 0.009, round: 0.007 });      // flared top rim
        });
      });
      sd.bone('footL', () => sd.frame({ scale: 1.08, pos: [0, 0.004, -0.004] }, () => {
        const upper = () => {
          sd.ellipsoid({ pos: [0, -0.02, -0.105], r: [0.058, 0.045, 0.118] });
          sd.ellipsoid({ pos: [0, -0.014, 0.01], r: [0.05, 0.05, 0.056] });
          sd.ellipsoid({ pos: [0, 0.02, -0.02], r: [0.052, 0.06, 0.06] });
        };
        sd.group({ mat: 'boot', k: 0.035 }, upper);
        sd.group({ mat: 'sole', k: 0.012, blend: 0.004 }, () => {
          sd.group({ offset: 0.004, k: 0.035 }, upper);
          sd.box({ op: 'int', k: 0.003, pos: [0, -0.06, -0.06], size: [0.1, 0.011, 0.25], round: 0.004 });
        });
        sd.box({ mat: 'sole', pos: [0, -0.045, 0.028], size: [0.036, 0.026, 0.03], round: 0.01, k: 0.006 });   // block heel
      }));
    });

    // ---------------- arms (long knit sleeves, ribbed cuffs) ----------------
    sd.mirrorX(() => {
      sd.bone('shoulderL', () => {
        const slv = sd.patternFrame({ pos: [0, -0.1, 0], mode: 'cyl', radius: 0.055 });
        sd.group({ mat: 'knit', k: 0.035, blend: 0.035, pframe: slv }, () => {
          sd.roundCone({ a: [0.01, -0.02, 0], b: [0, -0.22, 0], ra: 0.058, rb: 0.05 });
        });
      });
      sd.bone('elbowL', () => {
        const slv = sd.patternFrame({ pos: [0, -0.1, 0], mode: 'cyl', radius: 0.05 });
        sd.group({ mat: 'knit', k: 0.02, pframe: slv }, () => {
          sd.roundCone({ a: [0, 0.03, 0], b: [0, -0.19, 0], ra: 0.05, rb: 0.044 });
          sd.cylinder({ pos: [0, -0.2, 0], r: 0.05, h: 0.03, round: 0.014, k: 0.012 });      // ribbed cuff
        });
        sd.roundCone({ mat: 'skin', a: [0, -0.2, 0], b: [0, -0.24, 0], ra: 0.032, rb: 0.03, k: 0.006 });
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
        sd.paint({ color: '#F2A987', soft: 0.02, strength: 0.4, only: ['skin'] }, () => sd.sphere({ pos: [0.004, -0.07, 0], r: 0.11 }));
      }));
    });
    void prism;
  },

  parts: {
    hband: { bone: 'head', tris: 700, voxel: 0.0034, sculpt(sd) {
      sd.bone('head', () => sd.frame({ scale: HS }, () => {
        sd.group({ name: 'hband', mat: 'band', k: 0 }, () => {
          sd.ellipsoid({ pos: CROWN.c, r: CROWN.r.map((v) => v + 0.016), shell: 0.0085 });
          sd.plane({ op: 'int', k: 0.004, n: HB.n, d: hbD(HB.half) });
          sd.plane({ op: 'int', k: 0.004, n: HB.n.map((v) => -v), d: -hbD(-HB.half) });
          sd.plane({ op: 'int', k: 0.012, n: [0, -1, 0], d: -0.33 });         // ends tucked under the side curtains
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
    roundGlasses(b, { parent: HG, eye: EYE, r: 0.06, thick: 0.0105, depth: 0.007, z: -0.192, dy: 0.002, wrap: 0.12, templeX: 0.158, earZ: 0.03 });
    const hoops = [];
    for (const s of [1, -1]) {
      const g = new THREE.TorusGeometry(0.03, 0.0055, 10, 32);
      g.rotateY(s * 0.6);
      g.translate(s * 0.146, 0.088, -0.058);   // hanging in front of the side curtains
      hoops.push(g);
    }
    b.mesh(HG, mergeGeos(THREE, hoops), b.mat({ color: '#FFC23A', metal: 1, rough: 0.2, envIntensity: 1.2 }), { name: 'hoops' });
  },
};
