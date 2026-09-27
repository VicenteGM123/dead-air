// Face attachments + face controller for baked characters.
//   makeAttachBuilder(ctx) -> builder passed to def.attachments(b, ctx):
//     b.eyes(EYE)                 eyeballs (canvas iris texture, catchlights), upper/lower lids with lash lines
//     b.aviators(o) / b.glasses(o) glasses (frames + lenses)        b.hoops(o) earrings
//     b.mesh(joint, geometry, material, { pos, rot, scale, name })   any rigid mesh on a joint (joint-local coords)
//     b.mat(opts) (attachMaterial)  b.joint(name)  b.THREE
//   FaceController: blink(), setLook(x, y) (-1..1), lookAt(worldPos|null), setExpression(name, weight),
//     update(dt) (auto blink, eye darts, smoothing). Expressions: neutral, smile, frown, o_mouth, wink, angry
//     (+ any morph names baked for the character). Drives lids, brows (rigid parts) and morph targets.
import * as THREE from 'three';
import { attachMaterial } from './charMaterial.js';

const texCache = new Map();

// Equirect eyeball texture: rows = polar angle from the +y pole (the iris sits on the pole).
export function eyeTexture(o = {}) {
  const key = JSON.stringify(o);
  if (texCache.has(key)) return texCache.get(key);
  const W = 512, H = 256;
  const cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const g = cv.getContext('2d');
  const img = g.createImageData(W, H);
  const iris = new THREE.Color(o.iris || '#5A3420');
  const irisLight = iris.clone().lerp(new THREE.Color('#E8C070'), 0.35);
  const irisDark = iris.clone().multiplyScalar(0.35);
  const sclera = new THREE.Color(o.sclera || '#FBF6EE');
  const scleraBack = new THREE.Color('#E8C8C0');
  const pupil = new THREE.Color('#0E0A0C');
  const aI = Math.asin(Math.min(0.95, o.irisSize ?? 0.56));
  const aP = Math.asin(Math.min(0.9, (o.irisSize ?? 0.56) * (o.pupilSize ?? 0.42)));
  const c = new THREE.Color();
  let q = 0;
  for (let y = 0; y < H; y++) {
    const phi = ((y + 0.5) / H) * Math.PI;
    for (let x = 0; x < W; x++) {
      const lam = (x / W) * Math.PI * 2;
      if (phi < aP) {
        c.copy(pupil);
      } else if (phi < aI) {
        const t = (phi - aP) / (aI - aP);
        const stri = 0.5 + 0.5 * Math.sin(lam * 38 + Math.sin(lam * 7) * 2) * Math.sin(lam * 13 + 1.3);
        c.copy(irisLight).lerp(iris, Math.min(1, t * 1.3));
        c.lerp(irisDark, Math.pow(t, 3) * 0.9);
        c.multiplyScalar(0.85 + 0.3 * stri * (1 - t * 0.6));
        if (t < 0.12) c.lerp(pupil, (0.12 - t) / 0.12 * 0.6);
      } else {
        const t = Math.min(1, (phi - aI) / (Math.PI * 0.6));
        c.copy(sclera).lerp(scleraBack, Math.pow(t, 1.5) * 0.6);
        const edge = Math.max(0, 1 - (phi - aI) / 0.08);
        c.lerp(irisDark, edge * 0.35);
      }
      img.data[q++] = Math.round(Math.min(1, c.r) ** (1 / 2.2) * 255);
      img.data[q++] = Math.round(Math.min(1, c.g) ** (1 / 2.2) * 255);
      img.data[q++] = Math.round(Math.min(1, c.b) ** (1 / 2.2) * 255);
      img.data[q++] = 255;
    }
  }
  g.putImageData(img, 0, 0);
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  texCache.set(key, tex);
  return tex;
}

export function makeAttachBuilder(ctx) {
  const { joints, face, globals, envMap, rimColor } = ctx;
  const mat = (o) => attachMaterial({ rimColor, globals, envMap, ...o });
  const b = {
    THREE,
    joint: (n) => joints[n],
    mat,
    mesh(joint, geo, material, o = {}) {
      const m = new THREE.Mesh(geo, material);
      if (o.pos) m.position.set(...o.pos);
      if (o.rot) m.rotation.set(...o.rot);
      if (o.scale) typeof o.scale === 'number' ? m.scale.setScalar(o.scale) : m.scale.set(...o.scale);
      m.name = o.name || 'attach';
      m.castShadow = o.cast ?? true;
      m.receiveShadow = !!ctx.receiveShadow;   // same rule as the body (charRuntime opts.receiveShadow)
      (typeof joint === 'string' ? joints[joint] : joint).add(m);
      return m;
    },
    eyes(E) {
      const tex = eyeTexture(E);
      const eyeMat = mat({ map: tex, rough: 0.12, envIntensity: 0.6, rim: 0.12, wrap: 0.3, physical: true, clearcoat: 1, clearcoatRough: 0.04 });
      // lids are seen at grazing angles: no fresnel rim (it made them glow white), soft skin shading
      const lidMat = mat({ color: E.lid, rough: 0.55, sss: 0.6, wrap: 0.6, rim: 0.02 });
      const lashMat = mat({ color: E.lash || '#2A1A14', rough: 0.6, rim: 0.05 });
      const gl = E.glint ?? 1;   // catchlight size scale (STYLE_GUIDE §4: one large + one small catchlight)
      const glint = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.2, 1.2, 1.16), toneMapped: false, transparent: true, opacity: 0.95, depthWrite: false });
      const r = E.r;
      for (const s of [1, -1]) {
        const side = s > 0 ? 'L' : 'R';
        const root = new THREE.Group();
        root.name = 'eye' + side;
        // head-local: +x is the character's left in our convention? joints mirror: L is -x. EYE.x is |x|.
        root.position.set(-s * E.x, E.y, E.z);
        root.rotation.set(0, -s * (E.yaw ?? 0.08), -s * (E.tilt ?? 0));
        joints.head.add(root);
        const ball = new THREE.Group();
        root.add(ball);
        const sph = new THREE.Mesh(new THREE.SphereGeometry(r, 40, 28), eyeMat);
        sph.rotation.x = -Math.PI / 2; // iris pole -> forward (-z)
        sph.castShadow = false;
        ball.add(sph);
        // catchlights (fixed in head space)
        const g1 = new THREE.Mesh(new THREE.CircleGeometry(r * 0.2 * gl, 18), glint);
        const pos = new THREE.Vector3(0.36, 0.42, -1).normalize().multiplyScalar(r * 1.005);
        g1.position.copy(pos); g1.lookAt(pos.clone().multiplyScalar(3)); g1.renderOrder = 2;
        root.add(g1);
        const g2 = new THREE.Mesh(new THREE.CircleGeometry(r * 0.09 * gl, 12), glint);
        const pos2 = new THREE.Vector3(-0.28, -0.2, -1).normalize().multiplyScalar(r * 1.005);
        g2.position.copy(pos2); g2.lookAt(pos2.clone().multiplyScalar(3)); g2.renderOrder = 2;
        root.add(g2);
        // lids: caps around +y (upper) / -y (lower), rotated about x
        const lr = r * (E.lidScale ?? 1.06);   // lids hug the eyeball (Duke: 1.04 = ~2 mm proud, no hood)
        const cap = Math.PI * 0.53;
        const upper = new THREE.Group();
        const ug = new THREE.Mesh(new THREE.SphereGeometry(lr, 36, 14, 0, Math.PI * 2, 0, cap), lidMat);
        upper.add(ug);
        const lashU = new THREE.Mesh(new THREE.TorusGeometry(lr * Math.sin(cap), r * 0.075, 6, 32, Math.PI * 1.1), lashMat);
        lashU.position.y = lr * Math.cos(cap);
        lashU.rotation.set(Math.PI / 2, 0, Math.PI * 0.95 - Math.PI * 0.5 * 1.1 + Math.PI * 0.5);
        upper.add(lashU);
        root.add(upper);
        const lower = new THREE.Group();
        const lg = new THREE.Mesh(new THREE.SphereGeometry(lr * 0.995, 36, 12, 0, Math.PI * 2, Math.PI - cap, cap), lidMat);
        lower.add(lg);
        root.add(lower);
        for (const m of [ug, lg, lashU]) { m.castShadow = false; }
        face.addEye({ side, root, ball, upper, lower, cap, E });
      }
    },
    // Aviators: teardrop rims (gold tube), gradient-tinted lenses, double bridge, temples to the ears.
    // o = { eye, frame, lens, lensTop, lensOpacity, w, h (lens half size), z, dy, templeX, earZ, rimR,
    //       shape: 'teardrop' (outer-bottom drop, o.drop) | 'round' | default rounded superellipse }
    aviators(o) {
      const E = o.eye;
      const frameMat = mat({ color: o.frame || '#E3B04B', metal: 1, rough: 0.32, envIntensity: 0.6, rim: 0.06 });
      // Low-opacity tinted lenses (STYLE_GUIDE §4: the eyes must stay visible) with a soft reflection, no glow.
      const lensMat = mat({ color: '#ffffff', vertexColors: true, rough: 0.1, transparent: true, opacity: o.lensOpacity ?? 0.32, envIntensity: o.lensEnv ?? 0.45, rim: o.lensRim ?? 0.06, rimColor: '#FFE0B0', side: THREE.DoubleSide });
      const w = o.w ?? 0.05, h = o.h ?? 0.042;
      const zf = o.z ?? (E.z - E.r - 0.018);
      const cy0 = E.y - 0.004 + (o.dy ?? 0);   // dy < 0: aviators sit lower on the nose (brows stay visible)
      const bar = o.barR ?? Math.max(0.0024, (o.rimR ?? 0.0027) * 0.9);
      const cTop = new THREE.Color(o.lensTop || o.lens || '#E4501A'), cBot = new THREE.Color(o.lens || '#FF7A2E').lerp(new THREE.Color('#FFD0A0'), 0.35);
      // Outline for the lens on the +x side (local x: + = toward the temple)
      const outline = [];
      for (let i = 0; i < 48; i++) {
        const t = (i / 48) * Math.PI * 2;
        const c = Math.cos(t), sn = Math.sin(t);
        let x, y;
        if (o.shape === 'round') { x = c * w; y = sn * h; }
        else if (o.shape === 'teardrop') {
          // classic aviator teardrop: straight top bar with rounded corners, deep round bottom whose lowest point
          // sits toward the OUTER side (o.drop, default 0.22): the lens leans out like a drop
          const drop = o.drop ?? 0.22;
          if (sn >= 0) { x = Math.sign(c) * Math.pow(Math.abs(c), 2 / 3.6) * w; y = Math.pow(sn, 2 / 3.6) * h * 0.74; }
          else {
            x = Math.sign(c) * Math.pow(Math.abs(c), 2 / 2.3) * w + drop * 0.35 * w * -sn * (1 - Math.abs(c));
            y = -Math.pow(-sn, 2 / 2.3) * h * (1 + drop * c * 0.9);
          }
        } else {
          // aviator teardrop: squarish flat top (superellipse), round bottom dropping lower toward the nose side
          const top = sn > 0, e = top ? 3.2 : 2.1;
          x = Math.sign(c) * Math.pow(Math.abs(c), 2 / e) * w;
          y = Math.sign(sn) * Math.pow(Math.abs(sn), 2 / e) * h;
          if (top) y *= 0.8 + 0.06 * Math.max(0, -c);
          else y *= 1.08 + 0.12 * Math.max(0, -c) - 0.1 * Math.max(0, c);
        }
        outline.push([x, y]);
      }
      const place = (s, x, y) => {
        // s = +1 lens on +x side. lens center, curved back toward the temples
        const cx = s * (E.x + 0.004), cy = cy0;
        const xo = x; // + toward temple
        const z = zf + 2.6 * Math.max(0, xo) * Math.max(0, xo) + 0.35 * Math.max(0, -xo) * Math.max(0, -xo) + 0.06 * xo;
        return new THREE.Vector3(cx + s * x, cy + y, z);
      };
      for (const s of [1, -1]) {
        const P3 = outline.map(([x, y]) => place(s, x, y));
        b.mesh('head', new THREE.TubeGeometry(new THREE.CatmullRomCurve3(P3, true, 'centripetal'), 96, o.rimR ?? 0.0027, 8, true), frameMat, { name: 'aviatorRim' });
        // lens: fan triangulation of the outline with vertex-color gradient
        const pos = [], col = [], idx = [];
        const c = place(s, 0, 0);
        pos.push(c.x, c.y, c.z + 0.0005);
        const cm = cTop.clone().lerp(cBot, 0.5); col.push(cm.r, cm.g, cm.b);
        for (const [x, y] of outline) {
          const p = place(s, x * 0.99, y * 0.99);
          pos.push(p.x, p.y, p.z + 0.0005);
          const k = Math.min(1, Math.max(0, 0.5 - y / (2.4 * h)));
          const cc = cTop.clone().lerp(cBot, k); col.push(cc.r, cc.g, cc.b);
        }
        for (let i = 0; i < outline.length; i++) idx.push(0, 1 + i, 1 + ((i + 1) % outline.length));
        const lg = new THREE.BufferGeometry();
        lg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        lg.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
        lg.setIndex(idx);
        lg.computeVertexNormals();
        const lens = b.mesh('head', lg, lensMat, { name: 'aviatorLens', cast: false });
        lens.renderOrder = 3;
        // temple arm from the upper outer corner to behind the ear
        const tA = place(s, w * 0.96, h * 0.45);
        const tB = new THREE.Vector3(s * (o.templeX ?? 0.155), cy0 + 0.01 + h * 0.3, zf + 0.05);
        const tC = new THREE.Vector3(s * ((o.templeX ?? 0.155) - 0.004), cy0 + h * 0.2, E.z + (o.earZ ?? 0.1));
        b.mesh('head', new THREE.TubeGeometry(new THREE.CatmullRomCurve3([tA, tB, tC]), 16, bar, 6), frameMat, { name: 'aviatorTemple' });
      }
      // double bridge (brow bar + nose bridge)
      const L = (x, y) => place(-1, x, y), Rr = (x, y) => place(1, x, y);
      const top = new THREE.CatmullRomCurve3([L(-w * 0.62, h * 0.74), new THREE.Vector3(0, cy0 + h * 0.86, zf - 0.004), Rr(-w * 0.62, h * 0.74)]);
      b.mesh('head', new THREE.TubeGeometry(top, 20, bar, 6), frameMat, { name: 'aviatorBridge' });
      const low = new THREE.CatmullRomCurve3([L(-w * 0.98, h * 0.2), new THREE.Vector3(0, cy0 + h * 0.34, zf - 0.007), Rr(-w * 0.98, h * 0.2)]);
      b.mesh('head', new THREE.TubeGeometry(low, 20, bar * 1.08, 6), frameMat, { name: 'aviatorBridge2' });
    },
    // Round/square glasses (Skip, Penny): o = { eye, shape:'round'|'square', color, thick, w, h, z }
    glasses(o) {
      const E = o.eye;
      const frameMat = mat({ color: o.color || '#1E1624', rough: 0.3, rim: 0.2 });
      const glassMat = mat({ color: '#EAF4FF', rough: 0.03, transparent: true, opacity: 0.14, envIntensity: 1.5, rim: 0.6, rimColor: '#FFFFFF', side: THREE.DoubleSide });
      const zf = o.z ?? (E.z - E.r - 0.02);
      const w = o.w ?? 0.05, h = o.h ?? 0.045, t = o.thick ?? 0.006;
      for (const s of [1, -1]) {
        const cx = -s * E.x;
        const shape = new THREE.Shape();
        if (o.shape === 'square') {
          const r = Math.min(w, h) * 0.35;
          shape.moveTo(-w + r, -h); shape.lineTo(w - r, -h); shape.quadraticCurveTo(w, -h, w, -h + r); shape.lineTo(w, h - r);
          shape.quadraticCurveTo(w, h, w - r, h); shape.lineTo(-w + r, h); shape.quadraticCurveTo(-w, h, -w, h - r); shape.lineTo(-w, -h + r);
          shape.quadraticCurveTo(-w, -h, -w + r, -h);
        } else shape.absellipse(0, 0, w, h, 0, Math.PI * 2);
        const hole = new THREE.Path(shape.getPoints(32).map((p) => p.clone().multiplyScalar((Math.min(w, h) - t) / Math.min(w, h))));
        shape.holes.push(hole);
        const g = new THREE.ExtrudeGeometry(shape, { depth: t * 0.9, bevelEnabled: true, bevelThickness: t * 0.3, bevelSize: t * 0.25, bevelSegments: 2, curveSegments: 24 });
        b.mesh('head', g, frameMat, { pos: [cx, E.y, zf - t * 0.45] , name: 'glassesFrame' });
        const lens = b.mesh('head', new THREE.ShapeGeometry(new THREE.Shape(hole.getPoints(32)), 16), glassMat, { pos: [cx, E.y, zf], cast: false, name: 'glassesLens' });
        lens.renderOrder = 3;
        const tA = new THREE.Vector3(cx - s * w, E.y + h * 0.4, zf);
        const tC = new THREE.Vector3(-s * (o.templeX ?? 0.13), E.y, E.z + 0.1);
        b.mesh('head', new THREE.TubeGeometry(new THREE.CatmullRomCurve3([tA, new THREE.Vector3(tC.x, tA.y, zf + 0.05), tC]), 12, t * 0.45, 5), frameMat, { name: 'glassesTemple' });
      }
      const br = new THREE.CatmullRomCurve3([new THREE.Vector3(E.x - w, E.y + h * 0.2, zf), new THREE.Vector3(0, E.y + h * 0.35, zf - 0.004), new THREE.Vector3(-E.x + w, E.y + h * 0.2, zf)]);
      b.mesh('head', new THREE.TubeGeometry(br, 12, t * 0.5, 6), frameMat, { name: 'glassesBridge' });
    },
    hoops(o) {
      const m = mat({ color: o.color || '#FFC23A', metal: 1, rough: 0.2, envIntensity: 1.2 });
      for (const s of [1, -1]) b.mesh('head', new THREE.TorusGeometry(o.r || 0.04, o.t || 0.008, 8, 28), m, { pos: [s * o.x, o.y, o.z || 0], rot: [0, Math.PI / 2, 0], name: 'hoop' });
    },
  };
  return b;
}

// ---------------------------------------------------------------------------------------------------------------
const EXPR = {
  neutral: {},
  // smiles reach the eyes: the cheeks push the lower lids up (~15-20 % of the eye opening)
  smile: { lid: -0.04, lower: 0.36, brow: [0.004, 0.0], morph: { smile: 1 } },
  frown: { lid: -0.06, brow: [-0.004, -0.14], morph: { frown: 1 } },
  o_mouth: { lid: 0.1, lower: -0.05, brow: [0.01, 0.1], morph: { o_mouth: 1 } },
  wink: { lidL: -1, lower: 0.32, brow: [0.003, 0], morph: { smile: 0.8 } },
  angry: { lid: -0.18, brow: [-0.006, -0.32], morph: { frown: 0.8 } },
  // STYLE_GUIDE §4 presets (heroes: the sculpted base face is the warm soft smile = 'neutral')
  determined: { lid: -0.1, brow: [-0.003, -0.12], morph: { frown: 0.35 } },
  hurt: { lid: -0.25, lower: 0.1, brow: [0.004, 0.22], morph: { o_mouth: 0.6, frown: 0.3 } },
  grin: { lid: -0.04, lower: 0.36, brow: [0.004, 0.0], morph: { smile: 1 } },
  surprised: { lid: 0.12, lower: -0.06, brow: [0.012, 0.1], morph: { o_mouth: 1 } },
};
export const EXPRESSIONS = Object.keys(EXPR);
const ZERO2 = [0, 0];
const NO_MORPH = {};

export class FaceController {
  constructor() {
    this.eyes = [];
    this.brows = [];
    this.mesh = null;
    this.look = new THREE.Vector2();
    this.lookTarget = new THREE.Vector2();
    this.lookWorld = null;
    this.blinkT = 2 + Math.random() * 3;
    this.blinkPhase = -1;
    this.expr = 'neutral';
    this.exprW = 1;
    this.cur = { lid: 0, lidL: 0, lidR: 0, lower: 0, brow: [0, 0] };
    this.auto = true;
    this._t = 0;
  }
  addEye(e) {
    this.eyes.push(e);
    this._applyLids(e, 0, 0);
  }
  addBrow(mesh, side) { this.brows.push({ mesh, side, base: mesh.position.clone(), baseRot: mesh.rotation.clone() }); }
  setMesh(m) { this.mesh = m; }
  blink() { this.blinkPhase = 0; }
  setLook(x, y) { this.lookWorld = null; this.lookTarget.set(Math.max(-1, Math.min(1, x)), Math.max(-1, Math.min(1, y))); }
  lookAt(p) { this.lookWorld = p ? p.clone() : null; }
  setExpression(name, w = 1) { this.expr = EXPR[name] || this.mesh?.morphTargetDictionary?.[name] !== undefined ? name : 'neutral'; this.exprW = w; }
  _applyLids(e, closeU, lowerUp) {
    const E = e.E;
    // Upper lid: front edge elevation (rad) from openness; 0 = edge at the eye center.
    const open = E.lidOpen ?? 0.7;
    const elev = THREE.MathUtils.lerp(-0.12, 0.62, open) - closeU * (THREE.MathUtils.lerp(-0.12, 0.62, open) + 0.14);
    e.upper.rotation.x = elev + (e.cap - Math.PI / 2);
    const low = -(E.lowerLid ?? 0.25) * 1.2 + lowerUp;
    e.lower.rotation.x = low - (e.cap - Math.PI / 2);
  }
  update(dt, headObj) {
    this._t += dt;
    // auto blink
    if (this.auto) {
      this.blinkT -= dt;
      if (this.blinkT <= 0) { this.blink(); this.blinkT = 2.2 + Math.random() * 3.5; }
      if (Math.random() < dt * 0.25) this.lookTarget.set((Math.random() - 0.5) * 0.8, (Math.random() - 0.5) * 0.4);
    }
    let blink = 0;
    if (this.blinkPhase >= 0) {
      this.blinkPhase += dt / 0.16;
      blink = this.blinkPhase < 0.5 ? this.blinkPhase * 2 : Math.max(0, 2 - this.blinkPhase * 2);
      if (this.blinkPhase >= 1) this.blinkPhase = -1;
    }
    const X = EXPR[this.expr] || {};
    const w = this.exprW;
    const k = 1 - Math.exp(-dt * 14);
    const c = this.cur;
    c.lid += ((X.lid || 0) * w - c.lid) * k;
    c.lidL += ((X.lidL || 0) * w - c.lidL) * k;
    c.lidR += ((X.lidR || 0) * w - c.lidR) * k;
    c.lower += ((X.lower || 0) * w - c.lower) * k;
    const bw = X.brow || ZERO2;   // per frame: no allocations (hero + every zombie)
    c.brow[0] += (bw[0] * w - c.brow[0]) * k;
    c.brow[1] += (bw[1] * w - c.brow[1]) * k;
    this.look.lerp(this.lookTarget, 1 - Math.exp(-dt * 18));
    for (const e of this.eyes) {
      const extra = e.side === 'L' ? c.lidL : c.lidR;
      const close = Math.min(1, Math.max(0, blink + Math.max(0, -extra) - Math.min(0, c.lid) * 1.5));
      const openMore = Math.max(0, c.lid) * 1.5;
      this._applyLids(e, close - openMore * 0.5, c.lower);
      e.ball.rotation.set(-this.look.y * 0.35, -this.look.x * 0.5, 0);
    }
    for (const b of this.brows) {
      b.mesh.position.y = b.base.y + c.brow[0];
      b.mesh.rotation.z = b.baseRot.z + c.brow[1] * (b.side === 'L' ? -1 : 1);
    }
    if (this.mesh && this.mesh.morphTargetDictionary) {
      const d = this.mesh.morphTargetDictionary, inf = this.mesh.morphTargetInfluences;
      const target = X.morph || NO_MORPH;
      if (this._morphDict !== d) { this._morphDict = d; this._morphList = Object.entries(d); }   // cached: the dictionary only changes with the geometry
      const list = this._morphList;
      for (let j = 0; j < list.length; j++) {
        const name = list[j][0], i = list[j][1];
        const t = (target[name] || (this.expr === name ? 1 : 0)) * w;
        inf[i] += (t - inf[i]) * k;
      }
    }
  }
}
