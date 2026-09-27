// DEAD AIR — props: machines (docs/PROPKIT.md, GDD §10). The station's showpieces:
//   telly           Telly, the living walnut console TV (hero): rubber-glass CRT diorama, VHF dial, rabbit ears,
//                   telescoping legs, cord tail and the white four-fingered cartoon glove on a stretchy arm
//   telly_lamp      Telly's home floor lamp (bulb = named part + light anchor; setLampLevel)
//   telly_rug       Telly's home braided oval rug (parts.dust = 'dust_rect' footprint decal, opts.dust)
//   telly_cord      the unplugged extension cord an empty home keeps
//   sign_on_lever   Master Control Sign-On lever: red knife switch under a hinged red cover + ON AIR lamp
//   uplink_dish     THE UPLINK: 5 m white dish on an az-el turntable (hero; tilt/yaw parts, instanced rim chasers)
//   uplink_cradle   feed-horn cradle clamp at chest height with R/G/B lamps
//   uplink_crank    alignment crank wheel with a glowing handle
//   uplink_booth    little uplink control booth with blinking lamps (instanced)
//   skylark_13      the satellite Skylark-13 (small, cute, blinking beacon)
//   hut_tubes       transmitter-hut tube rack: 4 orange tubes + the green Perpetua-Tube
// Scenes (tools/propview): telly_home, telly_home_empty, uplink, sign_on.
// Runtime helpers exported below (the machine code animates the named parts through them).
// Shoot: node tools/propview/shoot.cjs category:machines --out _shots/props/machines

import * as K from './kit.js';
import { registerProp, registerScene, PAL, THREE } from './kit.js';
import { getCard } from '../gfx/cards.js';

const TAU = Math.PI * 2;
const UP = new THREE.Vector3(0, 1, 0);
const V = (x, y, z) => new THREE.Vector3(x, y, z);
const { clamp, lerp, smoothstep } = THREE.MathUtils;

// ============================================================================================ local helpers
// Group that finish() leaves alone (animated part). Its own meshes are merged later by finishRig().
function grp(name, pos = [0, 0, 0]) {
  const g = new THREE.Group();
  g.name = name;
  g.position.set(pos[0], pos[1], pos[2]);
  g.userData.noMerge = true;
  return g;
}
function keep(o) { o.userData.noMerge = true; return o; }
function tinted(geo, c) { return K.tint(geo.clone(), c); }
// Orients an object whose geometry runs along +Y so it goes from a toward b.
function aim(o, a, b) {
  const d = V(b[0] - a[0], b[1] - a[1], b[2] - a[2]).normalize();
  o.position.set(a[0], a[1], a[2]);
  o.quaternion.setFromUnitVectors(UP, d);
  return o;
}
function dist3(a, b) { return Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]); }
// Bevelled rod from a (radius r) to b (radius r2).
function rod(a, b, r, mat, o = {}) {
  const len = dist3(a, b);
  const geo = K.cyl(o.r2 ?? r, r, len, { bevel: o.bevel ?? Math.min(r * 0.45, 0.012), seg: o.seg ?? 10 });
  return aim(K.m(o.tint ? tinted(geo, o.tint) : geo, mat), a, b);
}
function ringXZ(r, n, y = 0) {
  const pts = [];
  for (let i = 0; i < n; i++) { const a = (i / n) * TAU; pts.push([Math.cos(a) * r, y, Math.sin(a) * r]); }
  return pts;
}
function ringXY(r, n, z = 0) {
  const pts = [];
  for (let i = 0; i < n; i++) { const a = (i / n) * TAU; pts.push([Math.cos(a) * r, Math.sin(a) * r, z]); }
  return pts;
}
// Closed rounded-rectangle path in the XY plane (for tubes: lips, piping, pinstripes).
function rrXY(w, h, r, z = 0, steps = 4, cx = 0, cy = 0) {
  const pts = [];
  const hx = w / 2 - r, hy = h / 2 - r;
  for (const [x0, y0, a0] of [[hx, hy, 0], [-hx, hy, Math.PI / 2], [-hx, -hy, Math.PI], [hx, -hy, Math.PI * 1.5]]) {
    for (let s = 0; s <= steps; s++) {
      const a = a0 + (s / steps) * (Math.PI / 2);
      pts.push([cx + x0 + Math.cos(a) * r, cy + y0 + Math.sin(a) * r, z]);
    }
  }
  return pts;
}
// Rounded-rect THREE.Path centered at (cx, cy) (holes for extrude()).
function rrPath(w, h, r, cx = 0, cy = 0, seg = 8) {
  return new THREE.Path(K.roundRect(w, h, r).getPoints(seg).map((p) => new THREE.Vector2(p.x + cx, p.y + cy)));
}
function rrShape(w, h, r, cx = 0, cy = 0) {
  const s = K.roundRect(w, h, r);
  if (cx || cy) return new THREE.Shape(s.getPoints(10).map((p) => new THREE.Vector2(p.x + cx, p.y + cy)));
  return s;
}
// Atlas cell UVs: canvas pixel rect -> uvRect (v from the bottom, CanvasTexture flipY).
function cellUV(g, x0, y0, x1, y1, S = 512, SH = S) { return K.uvRect(g, x0 / S, 1 - y1 / SH, x1 / S, 1 - y0 / SH); }
// Disc facing -z (prop front) showing an atlas cell.
function disc(r, seg, cell, S = 512, SH = S) {
  const g = new THREE.CircleGeometry(r, seg);
  cellUV(g, cell[0], cell[1], cell[2], cell[3], S, SH);
  g.rotateY(Math.PI);
  return g;
}
// Knob: lathe with its base at z=0 facing -z (face at z=-h). flutes: knurled side ribs.
function knobGeo(r, h, { flutes = 0, amp = 0.06, seg = 28, flange = 1.08 } = {}) {
  const prof = flange ? [[0, 0], [r * flange, 0], [r * flange, h * 0.16], [r, h * 0.24], [r * 0.97, h * 0.84], [r * 0.84, h], [0, h]]
    : [[0, 0], [r, 0], [r * 0.96, h * 0.84], [r * 0.82, h], [0, h]];
  const g = K.lathe(prof, { round: Math.min(r * 0.16, h * 0.14), seg, steps: 1 }).clone();
  if (flutes) {
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
      const rr = Math.hypot(x, z);
      if (rr < r * 0.5) continue;
      const band = smoothstep(y, h * 0.22, h * 0.3) * (1 - smoothstep(y, h * 0.8, h * 0.9));
      const k = 1 - amp * band * (0.5 + 0.5 * Math.cos(Math.atan2(z, x) * flutes));
      p.setX(i, x * k); p.setZ(i, z * k);
    }
    g.computeVertexNormals();
    K.weldNormals(g);
  }
  g.rotateX(-Math.PI / 2);
  return g;
}
// Moves `geo` vertices: fn(v:Vector3) mutates in place. Returns geo (own copy expected).
function warp(geo, fn) {
  const p = geo.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) { v.fromBufferAttribute(p, i); fn(v, i); p.setXYZ(i, v.x, v.y, v.z); }
  p.needsUpdate = true;
  geo.computeVertexNormals();
  return geo;
}
// Merges the meshes of every animated sub-group (finish() leaves noMerge groups alone).
function mergeParts(root) {
  const groups = [];
  root.traverse((o) => { if (o !== root && !o.isMesh && o.userData.noMerge) groups.push(o); });
  for (const gr of groups) K.merge(gr);
}
// finish() + detached sub-rigs (baked separately or not at all) + per-part merges + fresh stats.
function finishRig(game, g, { detach = [], finish = {} } = {}) {
  const det = detach.filter(Boolean).map((d) => [d, d.parent]);
  det.forEach(([d, p]) => p.remove(d));
  K.finish(game, g, finish);
  det.forEach(([d, p]) => p.add(d));
  ensureColors(g);
  mergeParts(g);
  g.traverse((o) => {
    if (!o.isMesh) return;
    o.receiveShadow = true;
    if (o.userData.noShadow || o.material.type === 'ShaderMaterial' || o.material.transparent || o.material.type === 'MeshBasicMaterial') o.castShadow = false;
  });
  g.userData.stats = K.stats(g);
  return g;
}
function ensureColors(root) {
  root.traverse((o) => {
    if (o.isMesh && o.material?.vertexColors && !o.geometry.attributes.color) {
      o.geometry = o.geometry.clone();
      o.geometry.setAttribute('color', new THREE.BufferAttribute(new Float32Array(o.geometry.attributes.position.count * 3).fill(1), 3));
    }
  });
  return root;
}
function flagTree(o, flags) { o.traverse((m) => { if (m.isMesh) Object.assign(m.userData, flags); }); }

// ================================================================================================= TELLY
// Body space: parts.body origin = cabinet bottom center (world y 0.35 at rest). Front faces -z; the viewer's
// right is -x, so the control column (dial, UHF, sunburst grille) sits at negative x.
const TL = {
  legH: 0.35, w: 1.3, h: 1.0, d: 0.6,
  sx: 0.12, sy: 0.55, sw: 0.8, sh: 0.6,        // screen window (body space)
  cx: -0.43,                                    // control column x
  fz: -0.32,                                    // faceplate front z
  screenZ: -0.105,                              // CRT canvas (back wall of the diorama)
  legSplay: [0.27, 0.19],
  bulge: 0.034,                                 // pillowy side walls (toy look)
};
TL.legDir = V(Math.sin(TL.legSplay[0]), -1, Math.sin(TL.legSplay[1])).normalize();
TL.legLen = TL.legH / -TL.legDir.y;             // along the splayed axis
TL.extLen = 0.4 / -TL.legDir.y;                 // telescoping travel along the axis (+0.4 m of height)
// VHF detents: 2..13 then the blank notch, clockwise from lower-left, blank at 6 o'clock.
TL.dialOrder = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0];
TL.dialStep = TAU / 13;
TL.dialAngle = (i) => i * TL.dialStep - (12 * TL.dialStep - Math.PI);   // clockwise-from-top angle (= rotation.z)

function tellyAtlas() {
  return K.tex.canvas('telly_atlas_v1', 512, 512, (ctx, W, H, rand) => {
    const choc = '#4A2A1A';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    // --- VHF ring (0,0)-(256,256)
    {
      const c = 128;
      const grd = ctx.createRadialGradient(c, c - 30, 10, c, c, 128);
      grd.addColorStop(0, '#FBF1D8'); grd.addColorStop(1, '#E9D6AE');
      ctx.fillStyle = grd; ctx.beginPath(); ctx.arc(c, c, 128, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#B8893A'; ctx.lineWidth = 7; ctx.beginPath(); ctx.arc(c, c, 124, 0, TAU); ctx.stroke();
      ctx.strokeStyle = 'rgba(90,58,34,0.35)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(c, c, 70, 0, TAU); ctx.stroke();
      TL.dialOrder.forEach((ch, i) => {
        const a = TL.dialAngle(i);
        const x = c + Math.sin(a) * 97, y = c - Math.cos(a) * 97;
        if (ch === 0) { // the blank notch: an empty slot
          ctx.save(); ctx.translate(x, y); ctx.rotate(a);
          ctx.fillStyle = '#5A3A22'; ctx.beginPath(); ctx.roundRect(-10, -14, 20, 28, 8); ctx.fill();
          ctx.fillStyle = '#2A1810'; ctx.beginPath(); ctx.roundRect(-6, -10, 12, 20, 5); ctx.fill();
          ctx.restore();
        } else {
          ctx.font = `${ch >= 10 ? 27 : 31}px "Titan One", "Arial Black", sans-serif`;
          ctx.fillStyle = ch === 13 ? PAL.channelRed : choc;
          ctx.fillText(String(ch), x, y + 1);
        }
        const b = a + TL.dialStep / 2; // tick between detents
        ctx.fillStyle = '#B8893A'; ctx.beginPath(); ctx.arc(c + Math.sin(b) * 112, c - Math.cos(b) * 112, 3.2, 0, TAU); ctx.fill();
      });
    }
    // --- grille cloth (256,0)-(512,256): dark woven cloth with gold threads
    {
      ctx.fillStyle = '#3A2418'; ctx.fillRect(256, 0, 256, 256);
      for (let i = 0; i < 256; i += 4) {
        ctx.fillStyle = i % 8 ? 'rgba(150,110,60,0.25)' : 'rgba(210,160,80,0.35)';
        ctx.fillRect(256 + i, 0, 1.5, 256);
        ctx.fillStyle = i % 8 ? 'rgba(20,10,6,0.35)' : 'rgba(170,120,60,0.22)';
        ctx.fillRect(256, i, 256, 1.5);
      }
    }
    // --- UHF ring (0,256)-(128,384)
    {
      const cx = 64, cy = 320;
      ctx.fillStyle = '#EFE0BC'; ctx.beginPath(); ctx.arc(cx, cy, 64, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#B8893A'; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(cx, cy, 61, 0, TAU); ctx.stroke();
      ctx.strokeStyle = choc; ctx.lineWidth = 2.5;
      for (let i = 0; i <= 20; i++) {
        const a = -Math.PI * 0.8 + (i / 20) * Math.PI * 1.6, l = i % 5 ? 6 : 11;
        ctx.beginPath(); ctx.moveTo(cx + Math.sin(a) * 55, cy - Math.cos(a) * 55); ctx.lineTo(cx + Math.sin(a) * (55 - l), cy - Math.cos(a) * (55 - l)); ctx.stroke();
      }
      ctx.fillStyle = PAL.channelRed; ctx.font = '15px "Bungee", "Arial Black", sans-serif'; ctx.fillText('UHF', cx, cy + 46);
    }
    // --- medallion (128,256)-(256,384): brass "13"
    {
      const cx = 192, cy = 320;
      const grd = ctx.createRadialGradient(cx - 18, cy - 22, 4, cx, cy, 64);
      grd.addColorStop(0, '#FFE7A8'); grd.addColorStop(0.55, '#D9A441'); grd.addColorStop(1, '#8A5E1E');
      ctx.fillStyle = grd; ctx.beginPath(); ctx.arc(cx, cy, 64, 0, TAU); ctx.fill();
      ctx.strokeStyle = PAL.channelRed; ctx.lineWidth = 7; ctx.beginPath(); ctx.arc(cx, cy, 52, 0, TAU); ctx.stroke();
      ctx.fillStyle = PAL.wztvBlue; ctx.beginPath(); ctx.arc(cx, cy, 46, 0, TAU); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; ctx.font = '50px "Titan One", "Arial Black", sans-serif'; ctx.fillText('13', cx, cy + 3);
    }
    // --- nameplate (256,256)-(512,320)
    {
      const grd = ctx.createLinearGradient(0, 256, 0, 320);
      grd.addColorStop(0, '#F3D58A'); grd.addColorStop(0.5, '#C8963C'); grd.addColorStop(1, '#8A6224');
      ctx.fillStyle = grd; ctx.beginPath(); ctx.roundRect(256, 256, 256, 64, 14); ctx.fill();
      ctx.strokeStyle = '#5A3A18'; ctx.lineWidth = 3; ctx.beginPath(); ctx.roundRect(262, 262, 244, 52, 10); ctx.stroke();
      ctx.font = '38px "Shrikhand", "Cooper Black", Georgia, serif';
      ctx.fillStyle = 'rgba(60,30,10,0.45)'; ctx.fillText('Telly-Vision', 385, 292);
      ctx.fillStyle = '#4A2410'; ctx.fillText('Telly-Vision', 384, 290);
    }
    // --- back label (256,320)-(512,384)
    {
      ctx.fillStyle = '#F2E6C6'; ctx.fillRect(256, 320, 256, 64);
      ctx.strokeStyle = '#B5472A'; ctx.lineWidth = 3; ctx.strokeRect(259, 323, 250, 58);
      ctx.fillStyle = '#B5472A'; ctx.beginPath(); ctx.moveTo(282, 334); ctx.lineTo(296, 362); ctx.lineTo(268, 362); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#F2E6C6'; ctx.font = '16px "Titan One", sans-serif'; ctx.fillText('!', 282, 353);
      ctx.fillStyle = '#3A2418'; ctx.font = '13px "Bungee", "Arial Black", sans-serif';
      ctx.fillText('TELLY-VISION  MOD. 13', 400, 338);
      ctx.font = '10px "Titan One", sans-serif';
      ctx.fillText('CAUTION: HIGH VOLTAGE INSIDE', 400, 355);
      ctx.fillText('WZTV CHANNEL 13 · PROPERTY', 400, 370);
    }
    // --- back panel (0,384)-(512,512): hardboard with vent slots
    {
      ctx.fillStyle = '#9C7A52'; ctx.fillRect(0, 384, 512, 128);
      for (let i = 0; i < 900; i++) { ctx.fillStyle = `rgba(${rand() < 0.5 ? '60,40,20' : '200,170,120'},0.12)`; ctx.fillRect(rand() * 512, 384 + rand() * 128, 2, 1); }
      ctx.fillStyle = '#3A2616';
      for (let r = 0; r < 3; r++) for (let i = 0; i < 14; i++) {
        ctx.beginPath(); ctx.roundRect(40 + i * 31, 404 + r * 34, 12, 24, 6); ctx.fill();
      }
    }
  }, { repeat: false, fonts: true });
}

// The white, puffy, four-fingered cartoon glove. Origin = wrist (top of the cuff); fingers along +Y, palm
// toward -Z, stitch lines on the back (+Z). Returns { glove, hold, fingers:{index,middle,pinky,thumb} }.
function buildGlove(white) {
  const glove = grp('glove');
  const W = '#FBF7EE', SEAM = '#D8CCB6';
  // cuff: flared bell with a rolled lip, below the wrist
  const cuff = K.lathe([[0.058, 0.0], [0.064, -0.03], [0.08, -0.07], [0.098, -0.1]], { seg: 16 });
  glove.add(K.m(tinted(cuff, W), white, { pos: [0, 0, 0] }));
  glove.add(K.m(tinted(K.tube(ringXZ(0.097, 14, -0.1), 0.014, { seg: 16, radial: 5, closed: true }), W), white));
  glove.add(K.m(tinted(K.tube(ringXZ(0.059, 12, 0.0), 0.01, { seg: 14, radial: 4, closed: true }), W), white));
  // palm: puffy squashed ball
  const palm = new THREE.SphereGeometry(1, 13, 9);
  palm.scale(0.088, 0.098, 0.056);
  palm.translate(0, 0.088, 0);
  glove.add(K.m(tinted(palm, W), white));
  // three stitch lines on the back of the hand
  for (const x of [-0.034, 0, 0.034]) {
    const pts = [];
    for (let i = 0; i <= 6; i++) {
      const y = 0.035 + i * 0.017;
      const nx = x / 0.088, ny = (y - 0.088) / 0.098;
      pts.push([x, y, 0.056 * Math.sqrt(Math.max(0.02, 1 - nx * nx - ny * ny)) + 0.002]);
    }
    glove.add(K.m(tinted(K.tube(pts, 0.0038, { seg: 5, radial: 3 }), SEAM), white));
  }
  // fingers: fat sausages pivoting at the knuckles (curl = rotation.x negative, toward the palm)
  const fingers = {};
  const fdef = [['index', 0.05, 0.078, -0.16], ['middle', 0.0, 0.088, 0.0], ['pinky', -0.05, 0.07, 0.17]];
  for (const [name, x, len, fan] of fdef) {
    const f = grp(`glove_${name}`, [x, 0.155, 0.0]);
    const cap = new THREE.CapsuleGeometry(0.031, len, 3, 9);
    cap.translate(0, len / 2 + 0.012, 0);
    warp(cap, (v) => { const t = clamp(v.y / (len + 0.04), 0, 1); const k = 1 + 0.1 * Math.sin(t * Math.PI); v.x *= k; v.z *= k; }); // puffy middle
    f.add(K.m(tinted(cap, W), white));
    f.rotation.set(-0.12, 0, fan);
    glove.add(f);
    fingers[name] = f;
  }
  const th = grp('glove_thumb', [0.07, 0.07, -0.018]);
  const tcap = new THREE.CapsuleGeometry(0.033, 0.058, 3, 9);
  tcap.translate(0, 0.045, 0);
  th.add(K.m(tinted(tcap, W), white));
  th.rotation.set(-0.35, 0.2, -0.95);
  glove.add(th);
  fingers.thumb = th;
  // hold point: where the presented item rests (on the palm side)
  const hold = grp('glove_hold', [0, 0.1, -0.1]);
  glove.add(hold);
  return { glove, hold, fingers };
}

// Stretchy ribbed tube arm (dynamic geometry, updated by updateTellyArm).
const ARM = { rings: 32, radial: 9, r: 0.052, ribs: 9, restLen: 0.6 };
function armGeometry() {
  const n = (ARM.rings + 1) * (ARM.radial + 1);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(n * 3), 3));
  g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(n * 3), 3));
  g.setAttribute('color', new THREE.BufferAttribute(new Float32Array(n * 3).fill(1), 3));
  g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(n * 2), 2));
  const idx = [];
  for (let i = 0; i < ARM.rings; i++) for (let j = 0; j < ARM.radial; j++) {
    const a = i * (ARM.radial + 1) + j, b = a + ARM.radial + 1;
    idx.push(a, a + 1, b, a + 1, b + 1, b);
  }
  g.setIndex(idx);
  return g;
}
const _a0 = new THREE.Vector3(), _a1 = new THREE.Vector3(), _a2 = new THREE.Vector3(), _p = new THREE.Vector3();
const _t = new THREE.Vector3(), _n = new THREE.Vector3(), _b = new THREE.Vector3(), _q = new THREE.Vector3();
const ARM_GOLD = new THREE.Color('#F2A51E'), ARM_DARK = new THREE.Color('#9A4E0C');

// Rebuilds Telly's arm tube from parts.armRig origin (inside the screen) through parts.armCtrl (curve control)
// to the glove's cuff. Call after moving parts.glove / parts.armCtrl. The tube thins as it stretches and its
// accordion ribs spread out (fixed rib count).
export function updateTellyArm(g) {
  const P = g.userData.parts;
  const arm = P.arm, glove = P.glove, ctrl = P.armCtrl;
  if (!arm || !glove) return;
  glove.updateMatrix();
  _a0.set(0, 0, 0);
  _a1.copy(ctrl.position);
  _a2.set(0, -0.085, 0).applyMatrix4(glove.matrix);   // cuff mouth
  // arc length (coarse)
  let L = 0;
  const bez = (t, out) => out.set(0, 0, 0).addScaledVector(_a0, (1 - t) * (1 - t)).addScaledVector(_a1, 2 * (1 - t) * t).addScaledVector(_a2, t * t);
  const prev = new THREE.Vector3().copy(_a0);
  for (let i = 1; i <= 16; i++) { bez(i / 16, _p); L += _p.distanceTo(prev); prev.copy(_p); }
  const thin = Math.sqrt(clamp(ARM.restLen / Math.max(L, 1e-3), 0.45, 1.25));
  const pos = arm.geometry.attributes.position, nor = arm.geometry.attributes.normal, col = arm.geometry.attributes.color, uv = arm.geometry.attributes.uv;
  // parallel-transport frame
  _n.set(1, 0, 0);
  const c = new THREE.Color();
  for (let i = 0; i <= ARM.rings; i++) {
    const t = i / ARM.rings;
    bez(t, _p);
    // tangent
    _t.set(0, 0, 0).addScaledVector(_a0, -2 * (1 - t)).addScaledVector(_a1, 2 - 4 * t).addScaledVector(_a2, 2 * t);
    if (_t.lengthSq() < 1e-10) _t.set(0, 0, -1);
    _t.normalize();
    _n.sub(_q.copy(_t).multiplyScalar(_n.dot(_t)));
    if (_n.lengthSq() < 1e-8) _n.set(0, 1, 0).sub(_q.copy(_t).multiplyScalar(_t.y));
    _n.normalize();
    _b.crossVectors(_t, _n);
    const rib = 0.5 + 0.5 * Math.cos(t * ARM.ribs * TAU);
    const r = ARM.r * thin * (0.84 + 0.26 * rib) * (1.08 - 0.2 * t);
    c.copy(ARM_DARK).lerp(ARM_GOLD, 0.35 + 0.65 * rib);
    for (let j = 0; j <= ARM.radial; j++) {
      const a = (j / ARM.radial) * TAU;
      const ca = Math.cos(a), sa = Math.sin(a);
      const k = i * (ARM.radial + 1) + j;
      const nx = _n.x * ca + _b.x * sa, ny = _n.y * ca + _b.y * sa, nz = _n.z * ca + _b.z * sa;
      pos.setXYZ(k, _p.x + nx * r, _p.y + ny * r, _p.z + nz * r);
      nor.setXYZ(k, nx, ny, nz);
      col.setXYZ(k, c.r, c.g, c.b);
      uv.setXY(k, j / ARM.radial, t);
    }
  }
  pos.needsUpdate = nor.needsUpdate = col.needsUpdate = uv.needsUpdate = true;
  arm.geometry.computeBoundingSphere();
  arm.geometry.computeBoundingBox();
}

// Legs telescope: t = 0 (rest, top at 1.35 m) .. 1 (standing, +0.4 m). Moves parts.body and every leg's
// chrome tube/foot so the feet stay on the floor.
export function setTellyLegs(g, t) {
  const P = g.userData.parts;
  t = clamp(t, 0, 1);
  P.body.position.y = TL.legH + t * 0.4;
  for (const leg of P.legs) {
    const tube = leg.userData.tubeName && leg.getObjectByName(leg.userData.tubeName);
    const foot = leg.getObjectByName(leg.userData.footName);
    if (tube) { tube.scale.y = Math.max(1e-3, t); tube.visible = t > 0.01; }
    if (foot) foot.position.y = -0.14 - t * TL.extLen;
  }
}
// Turns the VHF dial to a channel (2..13, 0 = blank notch); returns the rotation.z used.
export function setTellyDial(g, ch) {
  const i = Math.max(0, TL.dialOrder.indexOf(ch));
  const a = TL.dialAngle(i);
  g.userData.parts.dial.rotation.z = a;
  return a;
}
// Glove poses for previews: 'hidden' | 'present' | 'fingerguns' | 'wag'. The machine animates the same parts.
export function setTellyGlove(g, pose = 'present') {
  const P = g.userData.parts;
  const F = P.gloveFingers;
  const show = pose !== 'hidden';
  P.glove.visible = show; P.arm.visible = show;
  if (P.glass) P.glass.visible = !show;           // the membrane has parted while the glove is out
  if (!show) { P.glove.position.set(0, 0, 0.02); P.glove.quaternion.identity(); P.armCtrl.position.set(0, 0, -0.02); updateTellyArm(g); return; }
  // item 0.8 m in front of the screen at 1.2 m height (legs at rest): palm up, fingers to the viewer's left
  P.glove.position.set(-0.02, 1.12 - (TL.legH + TL.sy), -0.74);
  P.armCtrl.position.set(0.06, -0.26, -0.34);
  const y = V(1, 0.28, -0.3).normalize();
  const z = V(0, -1, 0.1);
  z.sub(y.clone().multiplyScalar(z.dot(y))).normalize();
  const x = new THREE.Vector3().crossVectors(y, z);
  P.glove.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(x, y, z));
  P.gloveHold.quaternion.copy(P.glove.quaternion).invert();   // hold stays aligned with Telly's axes
  const curl = { present: [-0.35, -0.45, -0.55, -0.3], fingerguns: [-0.05, -1.9, -2.0, 0.3], wag: [0.05, -1.9, -2.0, -1.2] }[pose] || [-0.3, -0.3, -0.3, -0.3];
  F.index.rotation.x = curl[0]; F.middle.rotation.x = curl[1]; F.pinky.rotation.x = curl[2];
  F.thumb.rotation.x = curl[3] - 0.35;
  if (pose === 'fingerguns' || pose === 'wag') {
    P.glove.quaternion.setFromEuler(new THREE.Euler(-0.25, 0.25, pose === 'wag' ? 0.2 : -Math.PI / 2 + 0.2));
    P.glove.position.set(0.05, 0.62, -0.62);
  }
  updateTellyArm(g);
}

registerProp('telly', (game, opts = {}) => {
  const g = K.prop('telly');
  const kc = { keepColor: true };
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.42 }), ...kc });
  const plastic = K.mat(game, 'plastic', '#ffffff', { rough: 0.42, ...kc });   // tinted per part (faceplate, knobs, glove, arm)
  const brass = K.mat(game, 'brass', '#C8963C', kc);
  const chrome = K.mat(game, 'chrome', '#A8B0BA', kc);
  const atlas = K.mat(game, 'plastic', '#ffffff', { map: tellyAtlas(), rough: 0.45, ...kc });
  const glass = game.mats.glass('#E8F4FF', { opacity: 0.1 });
  const CREAM = '#F3E3C0', DARK = '#3A2630', LINER = '#2E2238', KNOB = '#4A2C1E';

  const body = grp('body', [0, TL.legH, 0]);
  g.add(body);
  const { w, h, d, sx, sy, sw, sh, cx, fz } = TL;

  // ---- carcass: rounded walnut shell with the diorama opening (one extrude, hole = screen tunnel)
  const shape = rrShape(w, h, 0.21, 0, h / 2);
  shape.holes.push(rrPath(sw + 0.05, sh + 0.05, 0.1, sx, sy, 6));
  const carcass = warp(K.extrude(shape, d, { bevel: 0.05, bevelSeg: 2, curveSeg: 5 }), (v) => {
    // pillowy toy sides: the outer walls bow out a little at mid height (the window/liner area is untouched)
    const yn = (v.y - h / 2) / (h / 2);
    v.x += Math.sign(v.x) * TL.bulge * (1 - yn * yn) * smoothstep(Math.abs(v.x), 0.56, 0.66);
    v.z += Math.sign(v.z) * 0.018 * (1 - yn * yn) * smoothstep(Math.abs(v.z), 0.24, 0.3);
  });
  const carcassUV = K.uvBox(carcass, 1.1);
  body.add(K.m(carcassUV, walnut));
  // lid with overhang
  body.add(K.m(K.box(w + 0.06, 0.09, d + 0.06, 0.045, { uv: 1.1, swap: true }), walnut, { pos: [0, h + 0.036, 0] }));   // puffy toy lid
  // ---- cream faceplate framing screen + control column
  const fpW = 1.16, fpH = 0.76, fpD = 0.036;
  const fp = rrShape(fpW, fpH, 0.17);
  fp.holes.push(rrPath(sw, sh, 0.085, sx, 0, 5));
  body.add(K.m(tinted(K.extrude(fp, fpD, { bevel: 0.012, bevelSeg: 1, curveSeg: 5 }), CREAM), plastic, { pos: [0, sy, fz + fpD / 2] }));
  // diorama liner (tunnel walls) and the brass lip around the window
  const liner = rrShape(sw + 0.052, sh + 0.052, 0.1);
  liner.holes.push(rrPath(sw, sh, 0.085, 0, 0, 5));
  body.add(K.m(tinted(K.extrude(liner, 0.22, { bevel: 0.004, bevelSeg: 1, curveSeg: 5 }), LINER), plastic, { pos: [sx, sy, fz + 0.11] }));
  body.add(K.m(K.tube(rrXY(sw + 0.012, sh + 0.012, 0.09, 0, 4), 0.009, { seg: 36, radial: 4, closed: true }), brass, { pos: [sx, sy, fz - 0.002] }));

  // ---- CRT canvas (rubber glass, scr_telly) at the back of the diorama, weapon slot, front glass
  const scrMat = game.mats.rubberGlass(opts.card === null ? null : getCard(opts.card ?? 'telly_face', { expr: opts.expr ?? 'idle' }), { w: sw + 0.04, h: sh + 0.04, bright: 1.05 });
  const screen = keep(new THREE.Mesh(game.mats.screenGeometry(sw + 0.04, sh + 0.04), scrMat));
  screen.name = 'screen';
  screen.rotation.y = Math.PI;                 // shader bulges along local +z -> world -z (out of the TV)
  screen.position.set(sx, sy, TL.screenZ);
  screen.userData.screenGroup = 'scr_telly';
  screen.castShadow = false;
  body.add(screen);
  const weaponSlot = grp('weaponSlot', [sx, sy, (TL.screenZ + fz) / 2]);
  body.add(weaponSlot);
  const glassGeo = new THREE.PlaneGeometry(sw + 0.02, sh + 0.02, 12, 9);
  warp(glassGeo, (v) => { const x = v.x / (sw / 2), y = v.y / (sh / 2); v.z = 0.018 * Math.max(0, 1 - 0.5 * x * x - 0.5 * y * y); });
  glassGeo.rotateY(Math.PI);
  const glassMesh = keep(K.m(glassGeo, glass, { pos: [sx, sy, fz + 0.006], name: 'glass' }));
  glassMesh.userData.noOcclude = true;
  body.add(glassMesh);

  // ---- control column: VHF dial (fist-sized chicken-head knob over a printed ring), UHF knob, sunburst grille
  const vy = sy + 0.2, uy = sy - 0.005, gy = sy - 0.215;
  body.add(K.m(disc(0.112, 36, [0, 0, 256, 256]), atlas, { pos: [cx, vy, fz - 0.003] }));
  body.add(K.m(K.tube(ringXY(0.113, 20, 0), 0.0065, { seg: 24, radial: 4, closed: true }), brass, { pos: [cx, vy, fz - 0.003] }));
  const dial = grp('dial', [cx, vy, fz - 0.004]);
  dial.add(K.m(tinted(knobGeo(0.058, 0.07, { flutes: 10, amp: 0.07, seg: 30, flange: 1.07 }), KNOB), plastic));
  const ptrShape = [[0, 0.082], [0.018, 0.042], [0.024, -0.022], [0.015, -0.052], [-0.015, -0.052], [-0.024, -0.022], [-0.018, 0.042]];
  dial.add(K.m(tinted(K.extrude(ptrShape, 0.022, { bevel: 0.007, bevelSeg: 2 }), CREAM), plastic, { pos: [0, 0, -0.079] }));
  dial.add(K.m(K.tube([[0, 0.068, -0.0905], [0, 0.0, -0.0905]], 0.004, { seg: 2, radial: 5 }), K.glow(game, PAL.channelRed, 1.2)));
  dial.add(K.m(K.cyl(0.018, 0.02, 0.008, { bevel: 0.003, seg: 10 }), brass, { pos: [0, 0, -0.089], rot: [-Math.PI / 2, 0, 0] }));
  body.add(dial);
  // UHF fine tune
  body.add(K.m(disc(0.045, 28, [0, 256, 128, 384]), atlas, { pos: [cx, uy, fz - 0.003] }));
  const uhf = grp('uhf', [cx, uy, fz - 0.004]);
  uhf.add(K.m(tinted(knobGeo(0.024, 0.034, { seg: 12, flange: 0 }), KNOB), plastic));
  uhf.add(K.m(K.cyl(0.012, 0.013, 0.004, { bevel: 0.0015, seg: 8 }), brass, { pos: [0, 0, -0.034], rot: [-Math.PI / 2, 0, 0] }));
  uhf.add(K.m(tinted(K.box(0.005, 0.02, 0.006, 0.002), CREAM), plastic, { pos: [0, 0.012, -0.036] }));
  uhf.rotation.z = 0.5;
  body.add(uhf);
  // pilot jewel
  const pilot = keep(K.m(new THREE.SphereGeometry(0.011, 8, 6), K.glow(game, PAL.onAirRed, 2.2), { pos: [cx + 0.075, uy + 0.03, fz - 0.004], name: 'pilot' }));
  body.add(pilot);
  body.add(K.m(K.cyl(0.016, 0.017, 0.006, { bevel: 0.002, seg: 10 }), brass, { pos: [cx + 0.075, uy + 0.03, fz], rot: [-Math.PI / 2, 0, 0] }));
  // sunburst speaker grille
  body.add(K.m(disc(0.1, 30, [256, 0, 512, 256]), atlas, { pos: [cx, gy, fz - 0.002] }));
  body.add(K.m(K.tube(ringXY(0.102, 20, 0), 0.008, { seg: 24, radial: 4, closed: true }), brass, { pos: [cx, gy, fz - 0.004] }));
  const rays = 16, star = [];
  for (let i = 0; i < rays * 2; i++) {
    const a = (i / (rays * 2)) * TAU + Math.PI / 2;
    const r = i % 2 ? 0.024 : 0.094;
    star.push([Math.cos(a) * r, Math.sin(a) * r]);
  }
  body.add(K.m(K.extrude(star, 0.01, { bevel: 0 }), brass, { pos: [cx, gy, fz - 0.008] }));
  body.add(K.m(K.lathe([[0, 0], [0.03, 0], [0.028, 0.012], [0.018, 0.02], [0, 0.022]], { seg: 12, round: 0.006, steps: 1 }), brass, { pos: [cx, gy, fz - 0.01], rot: [-Math.PI / 2, 0, 0] }));
  body.add(K.m(disc(0.017, 20, [128, 256, 256, 384]), atlas, { pos: [cx, gy, fz - 0.0325] }));
  // nameplate on the apron
  body.add(K.m(cellUV(K.box(0.34, 0.064, 0.012, 0.004).clone(), 256, 256, 512, 320), atlas, { pos: [0.02, 0.09, -d / 2 - 0.004] }));

  // ---- back: hardboard panel with vents, label, cord grommet
  body.add(K.m(cellUV(new THREE.PlaneGeometry(1.08, 0.72), 0, 384, 512, 512), atlas, { pos: [0.06, sy, d / 2 + 0.003] }));
  body.add(K.m(cellUV(new THREE.PlaneGeometry(0.26, 0.066), 256, 320, 512, 384), atlas, { pos: [0.28, sy + 0.24, d / 2 + 0.005] }));
  body.add(K.m(tinted(K.cyl(0.02, 0.022, 0.012, { bevel: 0.004, seg: 12 }), DARK), plastic, { pos: [-0.36, 0.26, d / 2 + 0.006], rot: [Math.PI / 2, 0, 0] }));

  // ---- cord tail with a plug (named: it can wag)
  const cord = grp('cord', [-0.36, 0.26, d / 2 + 0.01]);
  const fy = -TL.legH - 0.26 + 0.009;             // floor in cord space
  const cpts = [[0, 0, 0], [-0.02, -0.08, 0.07], [-0.06, -0.36, 0.13], [-0.01, fy + 0.01, 0.2], [0.1, fy, 0.25], [0.21, fy, 0.22]];
  cord.add(K.m(tinted(K.tube(cpts, 0.0085, { seg: 22, radial: 5 }), '#5A3A22'), plastic));
  const plug = new THREE.Group();
  plug.position.set(0.235, fy + 0.006, 0.212);
  plug.rotation.set(0, 0.35, 0);
  plug.add(K.m(tinted(K.box(0.05, 0.03, 0.036, 0.011), '#4A3020'), plastic, { pos: [0, 0.008, 0] }));
  for (const s of [-1, 1]) plug.add(K.m(new THREE.BoxGeometry(0.03, 0.012, 0.004), brass, { pos: [0.038, 0.01, s * 0.009] }));
  cord.add(plug);
  body.add(cord);

  // ---- legs: splayed tapered walnut, brass collar, hidden chrome telescoping tube, brass sabot feet
  const legs = [];
  const corners = [[1, -1], [-1, -1], [1, 1], [-1, 1]];
  corners.forEach(([sxx, szz], i) => {
    const leg = grp(`leg${i}`, [sxx * 0.5, 0.004, szz * 0.19]);
    const dir = V(sxx * Math.sin(TL.legSplay[0]), -1, szz * Math.sin(TL.legSplay[1])).normalize();
    leg.quaternion.setFromUnitVectors(V(0, -1, 0), dir);
    leg.add(K.m(K.uvScale(K.cyl(0.058, 0.043, 0.14, { bevel: 0.012, seg: 8 }).clone(), 1, 2), walnut, { pos: [0, -0.14, 0] }));   // chunky toy legs
    leg.add(K.m(K.lathe([[0, 0], [0.048, 0], [0.048, 0.03], [0, 0.03]], { seg: 10, round: 0.009, steps: 1 }), brass, { pos: [0, -0.158, 0] }));
    const tube = grp(`leg${i}_tube`, [0, -0.14, 0]);
    const tm = K.m(K.cyl(0.028, 0.028, TL.extLen, { bevel: 0.004, seg: 8 }), chrome, { pos: [0, -TL.extLen, 0] });
    tm.userData.noAO = true; tm.userData.noOcclude = true;
    tube.add(tm);
    leg.add(tube);
    const foot = grp(`leg${i}_foot`, [0, -0.14, 0]);
    const lowLen = TL.legLen - 0.14 - 0.04;
    foot.add(K.m(K.uvScale(K.cyl(0.042, 0.032, lowLen, { bevel: 0.008, seg: 8 }).clone(), 1, 2), walnut, { pos: [0, -lowLen, 0] }));
    foot.add(K.m(K.lathe([[0, 0], [0.03, 0], [0.044, 0.018], [0.044, 0.034], [0.032, 0.048], [0, 0.052]], { seg: 10, round: 0.008, steps: 1 }), brass, { pos: [0, -lowLen - 0.04, 0] }));   // round brass booties
    leg.add(foot);
    leg.userData.tubeName = tube.name; leg.userData.footName = foot.name;
    body.add(leg);
    legs.push(leg);
  });

  // ---- rabbit ears on a swivel dome (antennas spin about Y like propellers; earL/earR splay/droop)
  const antennas = grp('antennas', [0.0, h + 0.05, 0.12]);
  antennas.add(K.m(tinted(K.lathe([[0, 0], [0.075, 0], [0.078, 0.014], [0.05, 0.05], [0.02, 0.062], [0, 0.064]], { seg: 15, round: 0.012, steps: 1 }), KNOB), plastic));
  antennas.add(K.m(K.tube(ringXZ(0.072, 16, 0.012), 0.005, { seg: 18, radial: 4, closed: true }), brass));
  antennas.add(K.m(new THREE.SphereGeometry(0.026, 10, 6), brass, { pos: [0, 0.066, 0] }));
  const ears = {};
  for (const [name, s] of [['earL', 1], ['earR', -1]]) {
    const ear = grp(name, [s * 0.014, 0.07, 0]);
    let y = 0;
    for (const [r, l] of [[0.0095, 0.27], [0.0075, 0.25], [0.0058, 0.22]]) {
      ear.add(K.m(K.cyl(r, r + 0.0012, l, { bevel: 0.0015, seg: 6 }), chrome, { pos: [0, y, 0] }));
      y += l - 0.01;
    }
    ear.add(K.m(new THREE.SphereGeometry(0.036, 9, 6), chrome, { pos: [0, y + 0.024, 0] }));   // big bobble tips
    ear.rotation.set(s > 0 ? 0.06 : 0.2, 0, -s * (s > 0 ? 0.44 : 0.6));   // a little lopsided = cute
    antennas.add(ear);
    ears[name] = ear;
  }
  body.add(antennas);

  // ---- glove + stretchy arm, living inside the diorama (hidden until the machine calls it out)
  const armRig = grp('armRig', [sx, sy, TL.screenZ - 0.03]);
  const armCtrl = grp('armCtrl', [0, -0.2, -0.3]);
  armRig.add(armCtrl);
  const gl = buildGlove(plastic);
  gl.glove.scale.setScalar(1.35);
  armRig.add(gl.glove);
  const armMesh = keep(new THREE.Mesh(armGeometry(), plastic));
  armMesh.name = 'arm';
  armMesh.userData.noAO = true; armMesh.userData.noOcclude = true;
  armMesh.frustumCulled = false;
  armRig.add(armMesh);
  body.add(armRig);
  // glove gets its own AO bake (puffy crevices between fingers), then is kept out of the main bake
  gl.glove.updateMatrixWorld(true);
  K.bakeAO(gl.glove, { floor: false, height: 0, res: 36, strength: 0.7 });
  flagTree(gl.glove, { noAO: true, noOcclude: true });

  const parts = {
    body, screen, glass: glassMesh, weaponSlot, dial, uhf, pilot, antennas, earL: ears.earL, earR: ears.earR, cord,
    legs, armRig, armCtrl, arm: armMesh, glove: gl.glove, gloveHold: gl.hold, gloveFingers: gl.fingers,
  };
  g.userData.parts = parts;
  g.userData.screens = [{ mesh: screen, group: 'scr_telly', id: 'telly' }];
  g.userData.colliders = [{ min: [-0.72, 0, -0.38], max: [0.72, 1.42, 0.38] }];
  g.userData.interact = { point: [sx, TL.legH + sy, -0.55], radius: 1.6 };
  g.userData.rig = {
    bodyBaseY: TL.legH,
    screen: { w: sw, h: sh, center: [sx, sy, TL.screenZ], bulgeMax: 0.35 },
    dial: { order: TL.dialOrder, step: TL.dialStep, detents: Object.fromEntries(TL.dialOrder.map((ch, i) => [ch, TL.dialAngle(i)])) },
    legs: { travel: 0.4, axisTravel: TL.extLen },
    glove: { presentWorld: [sx, 1.2, -1.1] },
  };

  finishRig(game, g, { detach: [antennas, armRig], finish: { ao: { res: 72, strength: 0.9 } } });
  setTellyLegs(g, opts.legs ?? 0);
  setTellyDial(g, opts.channel ?? 13);
  setTellyGlove(g, opts.pose ?? 'hidden');
  if (opts.demo && opts.pose && opts.pose !== 'hidden') gl.hold.add(ensureColors(demoRayGun(game)));
  return g;
}, { category: 'machines', tags: ['telly', 'machine', 'tv', 'mascot'], size: [1.44, 2.05, 0.76], desc: 'Telly, the living walnut console TV (mystery box)', hero: true, cache: false });

// Placeholder item for previews only (the real weapon models come from the weapons module).
function demoRayGun(game) {
  const d = new THREE.Group();
  const teal = K.mat(game, 'plastic', PAL.teal, { keepColor: true });
  const chrome = K.mat(game, 'chrome', '#A8B0BA', { keepColor: true });
  const glowM = K.glow(game, PAL.greenScreen, 2.5);
  d.add(K.m(K.box(0.22, 0.07, 0.07, 0.03), teal, { pos: [0, 0.02, 0] }));
  d.add(K.m(K.lathe([[0.03, 0], [0.045, 0.04], [0.03, 0.09], [0.05, 0.12], [0.05, 0.13], [0, 0.13]], { seg: 16, round: 0.008 }), chrome, { pos: [-0.11, 0.02, 0], rot: [0, 0, Math.PI / 2] }));
  d.add(K.m(K.box(0.05, 0.1, 0.05, 0.02), teal, { pos: [0.06, -0.05, 0], rot: [0, 0, -0.3] }));
  d.add(K.m(new THREE.SphereGeometry(0.02, 10, 8), glowM, { pos: [-0.245, 0.02, 0] }));
  for (let i = 0; i < 3; i++) d.add(K.m(K.cyl(0.04, 0.04, 0.01, { bevel: 0.003, seg: 14 }), chrome, { pos: [-0.02 - i * 0.03, 0.02, 0], rot: [0, 0, Math.PI / 2] }));
  d.rotation.set(0, Math.PI, 0);
  d.position.set(0.02, 0.05, 0);
  d.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return d;
}

// ======================================================================================== TELLY'S HOME SET
// Each of the four homes (GDD §10.2): couch facing a rug, a floor lamp, and (when empty) the dust footprint on the
// rug and an unplugged extension cord. "The lamp is on only where Telly lives."

// Lamp levels: 0 = off, ~0.35 = dim amber (before power), 1 = full. Swaps the bulb / lining / shade materials on
// this instance (materials themselves stay shared). The pooled light is the room code's job:
// game.lights.setAnchor(anchorId, { intensity: 1.6 * level }) (see userData.lightAnchors[0].id / opts.anchorId).
export function setLampLevel(game, g, level = 1) {
  const P = g.userData.parts;
  const q = Math.round(clamp(level, 0, 1) * 20) / 20;
  if (P.bulb) P.bulb.material = q > 0 ? K.glow(game, q < 0.6 ? PAL.gelAmber : PAL.tungsten, 0.6 + 3.4 * q) : K.mat(game, 'ceramic', '#E8DCC0');
  if (P.lining) P.lining.material = q > 0 ? K.glow(game, '#FFD9A0', 0.25 + 0.9 * q) : K.mat(game, 'fabric', '#8A6A3A');
  if (P.shade) P.shade.material = lampShadeMat(game, q);
  g.userData.lampLevel = q;
}
function lampShadeMat(game, q) {
  return K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#E9B64A', { pattern: 'plain', scale: 3 }), side: THREE.DoubleSide, emissive: '#FF9A40', emissiveIntensity: 0.34 * q });
}

registerProp('telly_lamp', (game, opts = {}) => {
  const g = K.prop('telly_lamp');
  const walnut = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.4 }) });
  const brass = K.mat(game, 'brass', '#C8963C');
  const trim = K.mat(game, 'fabric', '#B5472A', { side: THREE.DoubleSide });
  // weighted round base: brass skirt + domed walnut puck
  g.add(K.m(K.lathe([[0, 0], [0.21, 0], [0.215, 0.02], [0.2, 0.034], [0, 0.034]], { seg: 18, round: 0.008, steps: 1 }), brass));
  g.add(K.m(K.uvScale(K.lathe([[0, 0.03], [0.195, 0.03], [0.18, 0.07], [0.09, 0.09], [0, 0.092]], { seg: 18, round: 0.02, steps: 1 }).clone(), 3, 1), walnut));
  // chunky turned walnut spindle up to the tray
  const spindle = [[0, 0.085], [0.055, 0.085], [0.064, 0.13], [0.044, 0.18], [0.034, 0.3], [0.04, 0.37], [0.058, 0.43], [0.038, 0.51], [0.046, 0.58], [0, 0.58]];
  g.add(K.m(K.uvScale(K.lathe(spindle, { seg: 11, round: 0.014, steps: 1 }).clone(), 2, 2), walnut));
  // tray table with a brass gallery rail
  const trayY = 0.6;
  g.add(K.m(K.lathe([[0, 0], [0.235, 0], [0.25, 0.016], [0.24, 0.036], [0, 0.036]], { seg: 20, round: 0.01, steps: 1 }), walnut, { pos: [0, trayY - 0.02, 0] }));
  g.add(K.m(K.tube(ringXZ(0.236, 16, 0), 0.0075, { seg: 20, radial: 3, closed: true }), brass, { pos: [0, trayY + 0.05, 0] }));
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * TAU + 0.3;
    g.add(K.m(new THREE.CylinderGeometry(0.005, 0.005, 0.05, 5, 1, true), brass, { pos: [Math.cos(a) * 0.236, trayY + 0.028, Math.sin(a) * 0.236] }));
  }
  // upper stem + coupling + brass rod
  g.add(K.m(K.uvScale(K.cyl(0.024, 0.03, 0.4, { bevel: 0.008, seg: 10 }).clone(), 1, 3), walnut, { pos: [0, trayY + 0.016, 0] }));
  g.add(K.m(K.lathe([[0, 0], [0.034, 0], [0.034, 0.05], [0, 0.05]], { seg: 10, round: 0.01, steps: 1 }), brass, { pos: [0, trayY + 0.4, 0] }));
  g.add(K.m(K.cyl(0.013, 0.013, 0.34, { bevel: 0.004, seg: 8 }), brass, { pos: [0, trayY + 0.44, 0] }));
  // socket + bulb (named part)
  const bulbY = 1.5;
  g.add(K.m(K.lathe([[0, 0], [0.028, 0], [0.028, 0.06], [0.018, 0.074], [0, 0.074]], { seg: 9, round: 0.006, steps: 1 }), brass, { pos: [0, bulbY - 0.13, 0] }));
  const bulb = keep(K.m(K.lathe([[0, 0], [0.018, 0.004], [0.04, 0.045], [0.046, 0.076], [0.031, 0.112], [0, 0.122]], { seg: 9, round: 0.012, steps: 1 }), K.glow(game, PAL.tungsten, 4), { pos: [0, bulbY - 0.06, 0], name: 'bulb', cast: false }));
  bulb.userData.noOcclude = true;
  g.add(bulb);
  // pleated bell shade (named part), glowing lining, piping and a scalloped fringe band
  const y0 = 1.34, y1 = 1.72, rb = 0.34, rt = 0.17;
  const bell = [];
  for (let i = 0; i <= 5; i++) { const t = i / 5; bell.push(new THREE.Vector2(lerp(rb, rt, t) + Math.sin(t * Math.PI) * 0.03 - t * t * 0.02, t * (y1 - y0))); }
  const shadeGeo = warp(new THREE.LatheGeometry(bell, 48), (v) => { const k = 1 + 0.035 * Math.abs(Math.cos(Math.atan2(v.z, v.x) * 16)); v.x *= k; v.z *= k; });
  K.uvScale(shadeGeo, 12, 1.2);
  const shade = keep(K.m(shadeGeo, lampShadeMat(game, 1), { pos: [0, y0, 0], name: 'shade' }));
  g.add(shade);
  const lining = keep(K.m(new THREE.LatheGeometry(bell.map((p) => new THREE.Vector2(p.x - 0.008, p.y)).reverse(), 18), K.glow(game, '#FFD9A0', 1.15), { pos: [0, y0, 0], name: 'lining', cast: false }));
  lining.userData.noOcclude = true;
  g.add(lining);
  g.add(K.m(K.tube(ringXZ(rb * 1.05, 24, 0), 0.015, { seg: 30, radial: 4, closed: true }), trim, { pos: [0, y0, 0] }));
  g.add(K.m(K.tube(ringXZ(rt * 1.04, 14, 0), 0.011, { seg: 18, radial: 3, closed: true }), trim, { pos: [0, y1, 0] }));
  const band = warp(new THREE.LatheGeometry([new THREE.Vector2(rb * 1.06, -0.05), new THREE.Vector2(rb * 1.05, 0)], 60), (v) => {
    if (v.y < -0.01) v.y = -0.052 + 0.024 * (1 - Math.abs(Math.cos(Math.atan2(v.z, v.x) * 15))); // round scallops
  });
  g.add(K.m(band, trim, { pos: [0, y0, 0] }));
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.5;
    g.add(K.m(K.tube([[0, bulbY + 0.12, 0], [Math.sin(a) * rt * 0.6, y1 - 0.01, Math.cos(a) * rt * 0.6], [Math.sin(a) * rt, y1, Math.cos(a) * rt]], 0.005, { seg: 5, radial: 3 }), brass));
  }
  g.add(K.m(K.lathe([[0, 0], [0.014, 0], [0.022, 0.02], [0.016, 0.038], [0, 0.046]], { seg: 7, round: 0.006, steps: 1 }), brass, { pos: [0, y1 + 0.005, 0] }));
  g.add(K.m(K.tube([[0.03, bulbY - 0.09, 0], [0.036, bulbY - 0.24, -0.01]], 0.002, { seg: 3, radial: 3 }), brass));
  g.add(K.m(new THREE.SphereGeometry(0.009, 6, 5), brass, { pos: [0.036, bulbY - 0.25, -0.01] }));

  g.userData.parts = { bulb, lining, shade };
  const anchor = { pos: [0, 1.62, 0], color: PAL.tungsten, intensity: 1.6, distance: 4.5 };
  if (opts.anchorId) anchor.id = opts.anchorId;
  g.userData.lightAnchors = [anchor];
  g.userData.colliders = [{ min: [-0.22, 0, -0.22], max: [0.22, 1.74, 0.22] }];
  finishRig(game, g);
  setLampLevel(game, g, opts.level ?? 1);
  if ((opts.level ?? 1) <= 0) anchor.intensity = 0;
  return g;
}, { category: 'machines', tags: ['telly_home', 'lamp', 'light', 'living'], size: [0.74, 1.77, 0.74], desc: 'Telly home floor lamp (tray table, bell shade; bulb part + light anchor)' });

// Braided oval rag rug (origin = where Telly stands; the rug runs toward the couch, -z). parts.dust = the
// 'dust_rect' footprint decal aligned with Telly's feet (visible when opts.dust or when the machine shows it).
registerProp('telly_rug', (game, opts = {}) => {
  const g = K.prop('telly_rug');
  const RW = 2.5, RD = 2.1, cz = -0.4, rings = 11, seg = 48;
  const braid = K.tex.canvas('telly_rug_braid', 512, 512, (ctx, W, H, rand) => {
    const cols = ['#5A3A22', '#E3662B', '#E8A92E', '#8C9A3A', '#B5472A', '#F2DDB0', '#D9602B', '#6B3A6E', '#E8A92E', '#5A3A22', '#B07A45'];
    const band = H / rings;
    for (let r = 0; r < rings; r++) {
      ctx.fillStyle = cols[r % cols.length]; ctx.fillRect(0, r * band, W, band);
      for (let x = -band; x < W + band; x += band * 0.55) {   // chevron braid strands
        for (const [dy, s] of [[0, 1], [band / 2, -1]]) {
          ctx.fillStyle = `rgba(${s > 0 ? '255,255,255' : '0,0,0'},${0.1 + rand() * 0.06})`;
          ctx.beginPath();
          ctx.moveTo(x, r * band + dy);
          ctx.lineTo(x + band * 0.3, r * band + dy + band * 0.25);
          ctx.lineTo(x + band * 0.55, r * band + dy);
          ctx.lineTo(x + band * 0.3, r * band + dy + band * 0.5 - 2);
          ctx.closePath(); ctx.fill();
        }
      }
      const gr = ctx.createLinearGradient(0, r * band, 0, (r + 1) * band);
      gr.addColorStop(0, 'rgba(40,20,10,0.35)'); gr.addColorStop(0.18, 'rgba(0,0,0,0)'); gr.addColorStop(0.82, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(40,20,10,0.35)');
      ctx.fillStyle = gr; ctx.fillRect(0, r * band, W, band);
    }
    for (let i = 0; i < 3000; i++) { ctx.fillStyle = rand() < 0.5 ? 'rgba(255,240,210,0.12)' : 'rgba(30,15,5,0.12)'; ctx.fillRect(rand() * W, rand() * H, 1.5, 1.5); }
  });
  const rugMat = K.mat(game, 'fabric', '#ffffff', { map: braid, rim: 0.14, wrap: 0.55 });
  // concentric braided rings: radial grid (v = ring), each ring a soft bump, rolled-down edge
  const pos = [], uv = [], idx = [];
  const steps = rings * 2;
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const ringPhase = (t * rings) % 1;
    const hgt = 0.012 + 0.0035 * Math.sin(ringPhase * Math.PI) - (t > 0.97 ? ((t - 0.97) / 0.03) * 0.01 : 0);
    for (let j = 0; j <= seg; j++) {
      const a = (j / seg) * TAU;
      pos.push(Math.cos(a) * t * RW / 2, hgt, cz + Math.sin(a) * t * RD / 2);
      uv.push((j / seg) * 8, 1 - t);
    }
  }
  for (let i = 0; i < steps; i++) for (let j = 0; j < seg; j++) {
    const a = i * (seg + 1) + j, b = a + seg + 1;
    idx.push(a, a + 1, b, a + 1, b + 1, b);
  }
  const rg = new THREE.BufferGeometry();
  rg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  rg.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  rg.setIndex(idx);
  rg.computeVertexNormals();
  g.add(K.m(rg, rugMat, { cast: false }));
  const edge = [];
  for (let j = 0; j < 48; j++) { const a = (j / 48) * TAU; edge.push([Math.cos(a) * RW / 2, 0.008, cz + Math.sin(a) * RD / 2]); }
  g.add(K.m(tinted(K.tube(edge, 0.015, { seg: 48, radial: 5, closed: true }), '#5A3A22'), K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#ffffff', { pattern: 'tweed', scale: 3 }), rim: 0.14, wrap: 0.55 })));
  // dust footprint decal: the card's leg dots (22%/78% x 20%/80%) sit under Telly's feet (x +-0.593, z +-0.256)
  const fx = 0.593, fz = 0.256;
  const dw = ((2 * fx) / 0.56) * 1.15, dd = ((2 * fz) / 0.6) * 1.8;   // card drawn at 1/1.15 x 1/1.8 of the canvas
  const dustTex = K.tex.canvas('telly_dust_v4', 512, 512, (ctx, W, H, rand) => {
    // own take on the 'dust_rect' card: a soft oval of grey dust with the crisp clean TV footprint + four leg dots
    const cw = 512 / 1.15, ch = 512 / 1.8, ox = (512 - cw) / 2, oy = (512 - ch) / 2;
    const img = ctx.createImageData(512, 512), d = img.data;
    for (let i = 0; i < d.length; i += 4) {
      const v = rand();
      d[i] = 158 + v * 40; d[i + 1] = 150 + v * 36; d[i + 2] = 140 + v * 32;
      d[i + 3] = (0.64 + rand() * rand() * 0.34) * 255;
    }
    ctx.putImageData(img, 0, 0);
    for (let i = 0; i < 260; i++) { // lint and fuzz flecks
      ctx.fillStyle = rand() < 0.5 ? 'rgba(235,228,214,0.55)' : 'rgba(150,140,128,0.4)';
      ctx.beginPath(); ctx.ellipse(rand() * 512, rand() * 512, 1 + rand() * 3, 0.6 + rand() * 1.5, rand() * 3, 0, TAU); ctx.fill();
    }
    ctx.save();                         // dust piles up along the TV's edge
    ctx.filter = 'blur(3px)';
    ctx.strokeStyle = 'rgba(96,86,76,0.75)'; ctx.lineWidth = 9;
    ctx.beginPath(); ctx.roundRect(ox + cw * 0.25, oy + ch * 0.27, cw * 0.5, ch * 0.46, 14); ctx.stroke();
    ctx.restore();
    ctx.save();
    ctx.globalCompositeOperation = 'destination-out';
    ctx.filter = 'blur(2px)';
    ctx.beginPath(); ctx.roundRect(ox + cw * 0.25 + 3, oy + ch * 0.27 + 3, cw * 0.5 - 6, ch * 0.46 - 6, 12); ctx.fill();
    ctx.filter = 'blur(1.5px)';
    for (const [x, y] of [[0.22, 0.2], [0.78, 0.2], [0.22, 0.8], [0.78, 0.8]]) { ctx.beginPath(); ctx.arc(ox + cw * x, oy + ch * y, 8, 0, TAU); ctx.fill(); }
    ctx.restore();
    ctx.save();
    ctx.globalCompositeOperation = 'destination-in';
    ctx.translate(256, 256); ctx.scale(1, 0.66);
    const gr = ctx.createRadialGradient(0, 0, 170, 0, 0, 250);
    gr.addColorStop(0, 'rgba(0,0,0,1)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = gr; ctx.fillRect(-256, -400, 512, 800);
    ctx.restore();
  }, { repeat: false });
  const dustMat = game.mats.toon('#F4EEE4', { map: dustTex, transparent: true, depthWrite: false, rough: 1, rim: 0 });
  const dust = keep(K.m(new THREE.PlaneGeometry(dw, dd).rotateX(-Math.PI / 2), dustMat, { pos: [0, 0.0175, 0], name: 'dust', cast: false }));
  dust.userData.noAO = true; dust.userData.noOcclude = true;
  dust.renderOrder = 1;
  g.add(dust);
  g.userData.parts = { dust };
  g.userData.colliders = [];
  finishRig(game, g, { finish: { ao: { strength: 0.4, height: 0.02, heightStrength: 0.2 } } });
  dust.visible = !!opts.dust;
  return g;
}, { category: 'machines', tags: ['telly_home', 'rug', 'living'], size: [2.53, 0.03, 1.93], desc: 'Telly home braided oval rug (dust footprint decal part)' });

// Unplugged extension cord: wall outlet plate (back at z = 0, place against a wall), the pulled plug on the
// floor, the brown cord snaking toward -z and a cube tap where Telly's own cord would go.
registerProp('telly_cord', (game) => {
  const g = K.prop('telly_cord');
  const plastic = K.mat(game, 'plastic', '#ffffff');
  const brass = K.mat(game, 'brass', '#C8963C');
  const IVORY = '#EFE3C6', BROWN = '#5A3A22';
  // outlet plate with a surprised little face (two sockets + ground hole)
  g.add(K.m(tinted(K.box(0.08, 0.125, 0.012, 0.005), IVORY), plastic, { pos: [0, 0.3, -0.006] }));
  for (const y of [0.33, 0.27]) {
    g.add(K.m(tinted(K.box(0.05, 0.036, 0.006, 0.012), '#E6D8B8'), plastic, { pos: [0, y, -0.013] }));
    for (const x of [-0.011, 0.011]) g.add(K.m(tinted(new THREE.BoxGeometry(0.004, 0.012, 0.004), '#2A1C14'), plastic, { pos: [x, y + 0.003, -0.0165] }));
    g.add(K.m(tinted(new THREE.CylinderGeometry(0.004, 0.004, 0.004, 8).rotateX(Math.PI / 2), '#2A1C14'), plastic, { pos: [0, y - 0.01, -0.0165] }));
  }
  g.add(K.m(K.cyl(0.004, 0.004, 0.003, { bevel: 0.001, seg: 8 }), brass, { pos: [0, 0.3, -0.013], rot: [-Math.PI / 2, 0, 0] }));
  // cord: from the plug lying near the wall, snaking out to the cube tap
  const fy = 0.009;
  const pts = [[0.22, fy, -0.14], [0.34, fy, -0.3], [0.2, fy, -0.52], [-0.06, fy, -0.62], [-0.22, fy, -0.82], [-0.08, fy, -1.05], [0.18, fy, -1.14], [0.3, fy, -1.26]];
  g.add(K.m(tinted(K.tube(pts, 0.0085, { seg: 60, radial: 6 }), BROWN), plastic));
  const plug = new THREE.Group();
  plug.position.set(0.19, 0.012, -0.1);
  plug.rotation.set(0, 0.95, 0.18);
  plug.add(K.m(tinted(K.box(0.055, 0.03, 0.038, 0.012), '#4A3020'), plastic, { pos: [0, 0.012, 0] }));
  for (const s of [-1, 1]) plug.add(K.m(new THREE.BoxGeometry(0.032, 0.013, 0.004), brass, { pos: [0.042, 0.014, s * 0.01] }));
  g.add(plug);
  const tap = new THREE.Group();
  tap.position.set(0.33, 0.028, -1.3);
  tap.rotation.y = 0.5;
  tap.add(K.m(tinted(K.box(0.056, 0.056, 0.056, 0.012), BROWN), plastic));
  for (const [x, y, z, ry] of [[0, 0, -0.029, 0], [0.029, 0, 0, Math.PI / 2], [0, 0.029, 0, 0]]) {
    const face = new THREE.Group();
    face.position.set(x, y, z); face.rotation.y = ry;
    if (y) face.rotation.x = -Math.PI / 2;
    for (const sx of [-0.009, 0.009]) face.add(K.m(tinted(new THREE.BoxGeometry(0.004, 0.012, 0.004), '#1A100A'), plastic, { pos: [sx, 0, 0] }));
    tap.add(face);
  }
  g.add(tap);
  g.userData.colliders = [];
  return finishRig(game, g, { finish: { ao: { strength: 0.6 } } });
}, { category: 'machines', tags: ['telly_home', 'cord', 'clutter'], size: [0.6, 0.37, 1.35], desc: 'unplugged extension cord + wall outlet (empty Telly home)' });

registerScene('telly_home', {
  floor: 'shag', wall: 'panel', room: [5.2, 3.8],
  items: [
    { id: 'telly_rug', pos: [0.1, 0.45], rotY: 0 },
    { id: 'telly', pos: [0.1, 0.45], rotY: 0 },
    { id: 'telly_lamp', pos: [-1.35, 1.0], rotY: 0.4 },
    { id: 'telly_cord', pos: [1.25, 1.9], rotY: 0 },
  ],
  cam: { pos: [0.9, 1.6, -2.9], target: [0, 0.75, 0.5], fov: 50 },
});
registerScene('telly_home_empty', {
  floor: 'shag', wall: 'panel', room: [5.2, 3.8],
  items: [
    { id: 'telly_rug', pos: [0.1, 0.45], rotY: 0, opts: { dust: true } },
    { id: 'telly_lamp', pos: [-1.35, 1.0], rotY: 0.4, opts: { level: 0 } },
    { id: 'telly_cord', pos: [0.75, 1.9], rotY: 0 },
  ],
  cam: { pos: [0.6, 1.9, -2.4], target: [0, 0.2, 0.6], fov: 50 },
});

// ========================================================================================= SIGN-ON LEVER
// Master Control power switch (GDD §10.1): waist-high red knife switch under a hinged red safety hood, with a big
// ON AIR lamp on a mast. Floor-standing (anchor sign_on_lever, operator on the -z side).
//   parts.cover  hood, hinge at its back edge: rotation.x 0 = closed .. rig.coverOpen (flipped back)
//   parts.lever  knife-switch blades + red handle, hinge axis: rotation.x rig.leverOff (raised) .. 0 (ON, slammed)
//   parts.lamp   ON AIR face (setOnAirLamp swaps its glow level; pulse it every 2 s before power)
//   parts.jewels indicator lamps (setOnAirLamp lights them with the lamp)
const SO = { slope: 0.3, deckY: 0.93, w: 0.64, d: 0.5, h: 0.86 };

export function setOnAirLamp(game, g, level = 1) {
  const P = g.userData.parts;
  const q = Math.round(clamp(level, 0, 1) * 10) / 10;
  if (P.lamp) P.lamp.material = q > 0 ? K.glow(game, '#ffffff', 0.35 + 1.5 * q, { map: getCard('on_air', { lit: true }) }) : K.mat(game, 'plastic', '#ffffff', { map: getCard('on_air', { lit: false }) });
  if (P.jewels) P.jewels.material = q > 0 ? K.glow(game, '#FFB347', 0.5 + 2 * q) : K.mat(game, 'plastic', '#7A4A2A');
  g.userData.lampLevel = q;
}

function signOnAtlas() {
  return K.tex.canvas('signon_atlas_v1', 512, 256, (ctx, W, H, rand) => {
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    // two gauges (0,0)-(128,128) KILOVOLTS, (128,0)-(256,128) PLATE mA
    [['KILOVOLTS', 0], ['PLATE mA', 128]].forEach(([label, ox]) => {
      const cx = ox + 64, cy = 64;
      ctx.fillStyle = '#F4ECD6'; ctx.beginPath(); ctx.arc(cx, cy, 64, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#2A2230'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(cx, cy + 14, 44, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke();
      ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 6;
      ctx.beginPath(); ctx.arc(cx, cy + 14, 44, Math.PI * 1.7, Math.PI * 1.85); ctx.stroke();
      ctx.strokeStyle = '#2A2230'; ctx.lineWidth = 2;
      for (let i = 0; i <= 10; i++) {
        const a = Math.PI * 1.15 + (i / 10) * Math.PI * 0.7, l = i % 5 ? 6 : 11;
        ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * 44, cy + 14 + Math.sin(a) * 44); ctx.lineTo(cx + Math.cos(a) * (44 - l), cy + 14 + Math.sin(a) * (44 - l)); ctx.stroke();
      }
      ctx.fillStyle = '#2A2230'; ctx.font = '11px "Bungee", "Arial Black", sans-serif'; ctx.fillText(label, cx, cy + 34);
    });
    // plate (256,0)-(512,64): SIGN-ON / MAIN POWER
    ctx.fillStyle = '#2A2230'; ctx.beginPath(); ctx.roundRect(256, 0, 256, 64, 10); ctx.fill();
    ctx.strokeStyle = '#C8C8C8'; ctx.lineWidth = 3; ctx.beginPath(); ctx.roundRect(261, 5, 246, 54, 8); ctx.stroke();
    ctx.fillStyle = '#F4F1E8'; ctx.font = '26px "Bungee", "Arial Black", sans-serif'; ctx.fillText('SIGN-ON', 384, 26);
    ctx.fillStyle = '#FFB347'; ctx.font = '11px "Titan One", sans-serif'; ctx.fillText('MAIN TRANSMITTER POWER', 384, 48);
    // hazard stripes (256,64)-(512,128)
    ctx.save(); ctx.beginPath(); ctx.rect(256, 64, 256, 64); ctx.clip();
    ctx.fillStyle = '#F4C81E'; ctx.fillRect(256, 64, 256, 64);
    ctx.fillStyle = '#231A22';
    for (let x = 200; x < 560; x += 40) { ctx.beginPath(); ctx.moveTo(x, 128); ctx.lineTo(x + 20, 128); ctx.lineTo(x + 84, 64); ctx.lineTo(x + 64, 64); ctx.closePath(); ctx.fill(); }
    ctx.restore();
    // warning label (0,128)-(256,192)
    ctx.fillStyle = '#F4C81E'; ctx.beginPath(); ctx.roundRect(0, 128, 256, 64, 8); ctx.fill();
    ctx.fillStyle = '#231A22'; ctx.beginPath(); ctx.moveTo(34, 138); ctx.lineTo(56, 182); ctx.lineTo(12, 182); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#F4C81E'; ctx.font = '22px "Titan One", sans-serif'; ctx.fillText('!', 34, 170);
    ctx.fillStyle = '#231A22'; ctx.font = '17px "Bungee", "Arial Black", sans-serif'; ctx.fillText('DANGER', 150, 148);
    ctx.font = '12px "Titan One", sans-serif'; ctx.fillText('10,000 VOLTS  ·  KEEP COVER SHUT', 150, 172);
    // lever tag (256,128)-(512,192): ON / OFF arrow
    ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.roundRect(256, 128, 256, 64, 8); ctx.fill();
    ctx.fillStyle = '#E23B3B'; ctx.font = '22px "Bungee", "Arial Black", sans-serif'; ctx.fillText('ON', 300, 162);
    ctx.fillStyle = '#2A2230'; ctx.fillText('OFF', 468, 162);
    ctx.beginPath(); ctx.moveTo(340, 160); ctx.lineTo(420, 160); ctx.lineWidth = 5; ctx.strokeStyle = '#2A2230'; ctx.stroke();
    ctx.beginPath(); ctx.moveTo(334, 160); ctx.lineTo(350, 150); ctx.lineTo(350, 170); ctx.closePath(); ctx.fill();
    // brushed panel (0,192)-(512,256)
    ctx.fillStyle = '#B9BEC6'; ctx.fillRect(0, 192, 512, 64);
    for (let i = 0; i < 500; i++) { ctx.fillStyle = rand() < 0.5 ? 'rgba(255,255,255,0.25)' : 'rgba(40,40,50,0.18)'; ctx.fillRect(rand() * 512, 192 + rand() * 64, 20 + rand() * 80, 1); }
  }, { repeat: false, fonts: true });
}

registerProp('sign_on_lever', (game, opts = {}) => {
  const g = K.prop('sign_on_lever');
  const paint = K.mat(game, 'lacquer', '#ffffff');        // tinted: slate enamel, red handle, porcelain, cable
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const copper = K.mat(game, 'brass', '#C8784A');
  const atlas = K.mat(game, 'plastic', '#ffffff', { map: signOnAtlas() });
  const hood = game.mats.glass('#FF3A2E', { opacity: 0.38 });
  const SLATE = '#5479A8', SLATE_D = '#34496A', RED = '#E23B3B', PORC = '#F2EEE4', BLACK = '#262028';
  const { w, d, h, slope } = SO;
  // pedestal: rounded enamel cabinet on a darker kick base, chrome corner trims
  g.add(K.m(tinted(K.box(w + 0.04, 0.09, d + 0.04, 0.03), SLATE_D), paint, { pos: [0, 0.045, 0] }));
  g.add(K.m(cellUV(K.box(w + 0.045, 0.05, 0.006, 0.003).clone(), 256, 64, 512, 128, 512, 256), atlas, { pos: [0, 0.05, -(d + 0.04) / 2 - 0.002] }));
  const cab = K.box(w, h - 0.09, d, 0.06);
  g.add(K.m(tinted(cab, SLATE), paint, { pos: [0, 0.09 + (h - 0.09) / 2, 0] }));
  for (const sx of [-1, 1]) g.add(K.m(K.box(0.02, h - 0.14, 0.02, 0.008), chrome, { pos: [sx * (w / 2 - 0.004), 0.09 + (h - 0.09) / 2, -d / 2 + 0.004] }));
  // sloped deck (rises toward the back): a cap wedge + inset brushed panel
  const deck = new THREE.Group();
  deck.position.set(0, SO.deckY, 0);
  deck.rotation.x = -(Math.PI / 2 + slope);               // local +y = toward the operator (down-slope), +z = deck normal
  g.add(deck);
  // sloped cap: a wedge from the cabinet top up to the deck plane (profile in -z/y, extruded along x)
  const ft = SO.deckY - (d / 2) * Math.sin(slope), bt = SO.deckY + (d / 2) * Math.sin(slope);
  const wedge = K.extrude([[d / 2 + 0.01, h - 0.04], [-d / 2 - 0.01, h - 0.04], [-d / 2 - 0.01, bt], [d / 2 + 0.01, ft]], w + 0.02, { bevel: 0.02, round: 0.02, bevelSeg: 2 });
  wedge.rotateY(Math.PI / 2);
  g.add(K.m(tinted(wedge, SLATE), paint));
  // front: gauges, jewel lamps, nameplate, warning label
  const fz = -d / 2 - 0.002;
  for (const [x, cell] of [[-0.14, [0, 0, 128, 128]], [0.14, [128, 0, 256, 128]]]) {
    g.add(K.m(K.tube(ringXY(0.072, 20, 0), 0.01, { seg: 24, radial: 5, closed: true }), chrome, { pos: [x, 0.68, fz - 0.004] }));
    g.add(K.m(disc(0.07, 24, cell, 512, 256), atlas, { pos: [x, 0.68, fz - 0.003] }));
    const needle = K.m(tinted(new THREE.BoxGeometry(0.003, 0.05, 0.003), '#E23B3B'), paint, { pos: [x - 0.012, 0.685, fz - 0.008], rot: [0, 0, 0.5 - (x > 0 ? 0.4 : 0)] });
    g.add(needle);
    g.add(K.m(new THREE.CircleGeometry(0.07, 20).rotateY(Math.PI), game.mats.glass('#DDEEFF', { opacity: 0.12 }), { pos: [x, 0.68, fz - 0.012] }));
  }
  g.add(K.m(cellUV(K.box(0.4, 0.1, 0.012, 0.005).clone(), 256, 0, 512, 64, 512, 256), atlas, { pos: [0, 0.5, fz - 0.004] }));
  g.add(K.m(cellUV(new THREE.PlaneGeometry(0.3, 0.075).rotateY(Math.PI), 0, 128, 256, 192, 512, 256), atlas, { pos: [0, 0.33, fz - 0.001] }));
  const jewelGeo = [];
  for (let i = 0; i < 4; i++) {
    const x = -0.15 + i * 0.1;
    g.add(K.m(K.cyl(0.022, 0.024, 0.012, { bevel: 0.004, seg: 12 }), chrome, { pos: [x, 0.58, fz], rot: [-Math.PI / 2, 0, 0] }));
    const j = new THREE.SphereGeometry(0.016, 10, 6, 0, TAU, 0, Math.PI / 2).rotateX(-Math.PI / 2);
    j.translate(x, 0.58, fz - 0.012);
    jewelGeo.push(j);
  }
  const jewels = keep(new THREE.Mesh(K.tint(mergeGeos(jewelGeo), '#ffffff'), K.glow(game, '#FFB347', 2)));
  jewels.name = 'jewels';
  jewels.userData.noOcclude = true;
  g.add(jewels);
  // side vents
  for (const sx of [-1, 1]) for (let i = 0; i < 4; i++) g.add(K.m(tinted(K.box(0.008, 0.02, 0.16, 0.006), SLATE_D), paint, { pos: [sx * (w / 2 + 0.001), 0.36 + i * 0.05, 0.05] }));

  // ---- knife switch on the deck (deck-local: +y toward the operator, +z up from the deck)
  deck.add(K.m(tinted(K.box(0.4, 0.34, 0.03, 0.01), PORC), paint, { pos: [0, 0, 0.018] }));
  deck.add(K.m(cellUV(new THREE.PlaneGeometry(0.2, 0.05), 256, 128, 512, 192, 512, 256), atlas, { pos: [0, 0.145, 0.0335] }));
  const hingeY = -0.1, jawY = 0.12, bladeX = 0.075, bladeLen = 0.26;
  for (const sx of [-1, 1]) {
    // hinge posts + jaw clips (copper on porcelain insulators)
    deck.add(K.m(K.box(0.03, 0.03, 0.05, 0.006), copper, { pos: [sx * bladeX, hingeY, 0.058] }));
    deck.add(K.m(K.box(0.012, 0.03, 0.06, 0.004), copper, { pos: [sx * bladeX - 0.014, jawY, 0.062] }));
    deck.add(K.m(K.box(0.012, 0.03, 0.06, 0.004), copper, { pos: [sx * bladeX + 0.014, jawY, 0.062] }));
    deck.add(K.m(tinted(K.cyl(0.02, 0.024, 0.02, { bevel: 0.005, seg: 12 }), PORC), paint, { pos: [sx * bladeX, jawY, 0.03], rot: [Math.PI / 2, 0, 0] }));
    deck.add(K.m(tinted(K.cyl(0.02, 0.024, 0.02, { bevel: 0.005, seg: 12 }), PORC), paint, { pos: [sx * bladeX, hingeY, 0.03], rot: [Math.PI / 2, 0, 0] }));
  }
  deck.add(K.m(K.cyl(0.008, 0.008, 2 * bladeX + 0.05, { bevel: 0.003, seg: 8 }), chrome, { pos: [-(bladeX + 0.025), hingeY, 0.07], rot: [0, 0, -Math.PI / 2] }));
  const lever = grp('lever', [0, hingeY, 0.07]);
  for (const sx of [-1, 1]) lever.add(K.m(K.box(0.018, bladeLen, 0.034, 0.006), copper, { pos: [sx * bladeX, bladeLen / 2, 0] }));
  lever.add(K.m(tinted(K.box(2 * bladeX + 0.05, 0.03, 0.03, 0.012), BLACK), paint, { pos: [0, bladeLen - 0.02, 0.008] }));
  lever.add(K.m(tinted(K.cyl(0.018, 0.02, 0.07, { bevel: 0.008, seg: 12 }), RED), paint, { pos: [0, bladeLen - 0.02, 0.02], rot: [Math.PI / 2, 0, 0] }));
  lever.add(K.m(tinted(new THREE.SphereGeometry(0.034, 14, 10), RED), paint, { pos: [0, bladeLen - 0.02, 0.1] }));
  lever.rotation.x = 1.2;
  deck.add(lever);
  // hinged red safety hood (hinge at its back edge)
  const cover = grp('cover', [0, -0.19, 0.035]);
  const hw = 0.44, hl = 0.4, hh = 0.42;
  const hoodGeo = warp(K.box(hw, hl, hh, 0.045).clone(), (v) => { if (v.z < -hh / 2 + 0.001) v.z = -hh / 2; });
  hoodGeo.translate(0, hl / 2, hh / 2);
  const hoodMesh = K.m(hoodGeo, hood, { cast: false });
  hoodMesh.userData.noOcclude = true;
  cover.add(hoodMesh);
  cover.add(K.m(tinted(K.tube(rrXY(hw + 0.01, hl + 0.01, 0.05, 0, 3), 0.009, { seg: 32, radial: 5, closed: true }), RED), paint, { pos: [0, hl / 2, 0.006] }));
  cover.add(K.m(tinted(K.box(0.1, 0.02, 0.03, 0.01), RED), paint, { pos: [0, hl + 0.01, hh * 0.35] }));
  cover.add(K.m(K.cyl(0.008, 0.008, hw - 0.04, { bevel: 0.003, seg: 8 }), chrome, { pos: [-(hw - 0.04) / 2, 0, 0], rot: [0, 0, -Math.PI / 2] }));
  deck.add(cover);

  // ---- ON AIR lamp on a chrome mast at the back
  // chrome goalpost frame at the back corners (the hood flips back between the posts)
  const mastTop = 1.8, mz = d / 2 - 0.03;
  for (const sx of [-1, 1]) {
    g.add(K.m(K.cyl(0.019, 0.022, mastTop - 0.8, { bevel: 0.006, seg: 10 }), chrome, { pos: [sx * (w / 2 - 0.02), 0.8, mz] }));
    g.add(K.m(K.cyl(0.036, 0.04, 0.03, { bevel: 0.008, seg: 12 }), chrome, { pos: [sx * (w / 2 - 0.02), bt - 0.02, mz] }));
  }
  g.add(K.m(K.cyl(0.016, 0.016, w - 0.04, { bevel: 0.005, seg: 10 }), chrome, { pos: [-(w / 2 - 0.02), mastTop - 0.02, mz], rot: [0, 0, -Math.PI / 2] }));
  const box = new THREE.Group();
  box.position.set(0, mastTop + 0.1, mz);
  box.rotation.x = 0.12;
  box.add(K.m(tinted(K.box(0.56, 0.24, 0.13, 0.05), '#2A2230'), paint));
  box.add(K.m(tinted(K.tube(rrXY(0.54, 0.22, 0.05, 0, 3), 0.01, { seg: 32, radial: 5, closed: true }), RED), paint, { pos: [0, 0, -0.066] }));
  for (const sx of [-1, 1]) box.add(K.m(K.cyl(0.018, 0.018, 0.06, { bevel: 0.006, seg: 8 }), chrome, { pos: [sx * 0.18, -0.15, 0] }));
  const lamp = keep(K.m(new THREE.PlaneGeometry(0.48, 0.18).rotateY(Math.PI), K.glow(game, '#ffffff', 1.6, { map: getCard('on_air', { lit: true }) }), { pos: [0, 0, -0.067], name: 'lamp', cast: false }));
  lamp.userData.noOcclude = true;
  box.add(lamp);
  g.add(box);
  // cable into the floor
  g.add(K.m(tinted(K.tube([[0.2, 0.25, d / 2 - 0.02], [0.24, 0.12, d / 2 + 0.08], [0.26, 0.012, d / 2 + 0.26], [0.2, 0.012, d / 2 + 0.5]], 0.018, { seg: 16, radial: 6 }), BLACK), paint));

  g.userData.parts = { lever, cover, lamp, jewels, deck };
  g.userData.rig = { leverOff: 1.2, leverOn: 0, coverClosed: 0, coverOpen: 1.95, axis: 'x' };
  const lampWorld = box.position.clone();
  const anchor = { pos: [lampWorld.x, lampWorld.y, lampWorld.z - 0.2], color: PAL.onAirRed, intensity: 2.2, distance: 5 };
  if (opts.anchorId) anchor.id = opts.anchorId;
  g.userData.lightAnchors = [anchor];
  g.userData.colliders = [{ min: [-w / 2 - 0.03, 0, -d / 2 - 0.03], max: [w / 2 + 0.03, 1.25, d / 2 + 0.03] }];
  g.userData.interact = { point: [0, 1.0, -d / 2 - 0.25], radius: 1.4 };
  finishRig(game, g);
  if (opts.on) { lever.rotation.x = 0; cover.rotation.x = 1.95; }
  if (opts.cover === 'open') cover.rotation.x = 1.95;
  setOnAirLamp(game, g, opts.lamp ?? 1);
  return g;
}, { category: 'machines', tags: ['sign_on', 'machine', 'master_control', 'lever'], size: [0.7, 1.95, 0.8], desc: 'Sign-On knife-switch lever with red hood and ON AIR lamp', hero: true });

function mergeGeos(list) {
  const out = [];
  for (const gg of list) { const c = gg.index ? gg.toNonIndexed() : gg; out.push(c); }
  const total = out.reduce((n, gg) => n + gg.attributes.position.count, 0);
  const pos = new Float32Array(total * 3), nor = new Float32Array(total * 3), uv = new Float32Array(total * 2);
  let o = 0;
  for (const gg of out) {
    pos.set(gg.attributes.position.array, o * 3);
    nor.set(gg.attributes.normal.array, o * 3);
    if (gg.attributes.uv) uv.set(gg.attributes.uv.array, o * 2);
    o += gg.attributes.position.count;
  }
  const r = new THREE.BufferGeometry();
  r.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  r.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  r.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  return r;
}

registerScene('sign_on', {
  floor: 'tile', wall: 'plain', room: [4.4, 3.4], tileA: '#3A4658', tileB: '#2A3242',
  items: [
    { id: 'sign_on_lever', pos: [0.4, 0.3], rotY: 0.35 },
    { id: 'sign_on_lever', pos: [-1.1, 0.8], rotY: -0.3, opts: { on: true, lamp: 1 } },
  ],
  cam: { pos: [0.2, 1.7, -2.4], target: [-0.2, 0.9, 0.5], fov: 50 },
});

// ============================================================================================ THE UPLINK
// Transmitter Yard (GDD §10.4). Anchors: uplink_dish (the dish), uplink_cradle (feed-horn clamp, y 1.3),
// uplink_crank (crank wheel, hub y 1.0); the booth and the satellite are extra props. All face -z locally.
const UP_DISH = { R: 2.5, depth: 0.85, pivotY: 3.3, hub: 0.75, bulbs: 40, droop: -0.33, aligned: 0.95 };
UP_DISH.f = (UP_DISH.R * UP_DISH.R) / (4 * UP_DISH.depth);

// Rim chaser helper: t = seconds, on = bool, speed = bulbs per second (chase), lit fraction every 4th bulb.
const _cc = new THREE.Color();
export function setUplinkChase(g, t = 0, { on = true, speed = 12, color = PAL.marqueeGold } = {}) {
  const inst = g.userData.parts.rimBulbs;
  if (!inst) return;
  const n = inst.count, head = Math.floor(t * speed);
  for (let i = 0; i < n; i++) {
    const k = ((i - head) % 4 + 4) % 4;
    const v = on ? (k === 0 ? 1 : k === 1 ? 0.35 : 0.12) : 0.1;
    _cc.set(color).multiplyScalar(v);
    inst.setColorAt(i, _cc);
  }
  inst.instanceColor.needsUpdate = true;
}
// Pose: tilt = elevation in radians (rig.droop .. rig.aligned), yaw = turntable angle.
export function setUplinkPose(g, { tilt, yaw } = {}) {
  const P = g.userData.parts;
  if (tilt !== undefined) P.tilt.rotation.x = tilt;
  if (yaw !== undefined) P.yaw.rotation.y = yaw;
}

function dishTextures() {
  const face = K.tex.canvas('uplink_dish_face_v1', 512, 512, (ctx, W, H, rand) => {
    // u = around (12 petals), v = center (bottom row) -> rim (top row)
    const g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#F2F0EA'); g.addColorStop(1, '#E4E1D8');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    for (let i = 0; i < 12; i++) { // petal tint variation
      ctx.fillStyle = `rgba(${rand() < 0.5 ? '255,255,250' : '200,196,186'},${0.12 + rand() * 0.1})`;
      ctx.fillRect((i / 12) * W, 0, W / 12, H);
    }
    // painted station stripes near the rim (top): blue + red racing bands
    ctx.fillStyle = PAL.wztvBlue; ctx.fillRect(0, H * 0.075, W, H * 0.05);
    ctx.fillStyle = PAL.channelRed; ctx.fillRect(0, H * 0.14, W, H * 0.03);
    // seams + painted rivet heads
    ctx.strokeStyle = 'rgba(90,86,96,0.55)'; ctx.lineWidth = 2;
    for (let i = 0; i < 12; i++) { const x = (i / 12) * W + 0.5; ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke(); }
    for (const v of [0.34, 0.62]) { ctx.beginPath(); ctx.moveTo(0, H * v); ctx.lineTo(W, H * v); ctx.stroke(); }
    for (let i = 0; i < 12; i++) for (let j = 0; j < 16; j++) {
      const x = (i / 12) * W + 4, y = (j / 16) * H + 8;
      ctx.fillStyle = 'rgba(120,116,126,0.7)'; ctx.beginPath(); ctx.arc(x, y, 2.2, 0, TAU); ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.7)'; ctx.beginPath(); ctx.arc(x - 0.6, y - 0.6, 1, 0, TAU); ctx.fill();
    }
    for (const v of [0.34, 0.62]) for (let i = 0; i < 48; i++) {
      const x = (i / 48) * W + 5, y = H * v + 4;
      ctx.fillStyle = 'rgba(120,116,126,0.7)'; ctx.beginPath(); ctx.arc(x, y, 2.2, 0, TAU); ctx.fill();
    }
    // weathering: a few drips and scuffs (soft), scratches around the dent (u ~ 0.11)
    for (let i = 0; i < 40; i++) {
      ctx.fillStyle = `rgba(110,100,90,${0.04 + rand() * 0.05})`;
      const x = rand() * W, y = rand() * H;
      ctx.fillRect(x, y, 1.5, 6 + rand() * 30);
    }
    ctx.strokeStyle = 'rgba(80,70,64,0.35)'; ctx.lineWidth = 1.2;
    for (let i = 0; i < 9; i++) { const x = W * 0.11 + (rand() - 0.5) * 40, y = H * 0.32 + (rand() - 0.5) * 50; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + (rand() - 0.5) * 30, y + (rand() - 0.5) * 20); ctx.stroke(); }
  });
  const atlas = K.tex.canvas('uplink_atlas_v1', 512, 512, (ctx, W, H, rand) => {
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    // (0,0)-(256,256): station "13" badge for the dish center
    ctx.fillStyle = '#F2F0EA'; ctx.fillRect(0, 0, 256, 256);
    ctx.fillStyle = PAL.channelRed; ctx.beginPath(); ctx.arc(128, 128, 118, 0, TAU); ctx.fill();
    ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(128, 128, 104, 0, TAU); ctx.fill();
    ctx.fillStyle = PAL.wztvBlue; ctx.beginPath(); ctx.arc(128, 128, 96, 0, TAU); ctx.fill();
    ctx.fillStyle = '#F4F1E8'; ctx.font = '118px "Titan One", "Arial Black", sans-serif'; ctx.fillText('13', 128, 136);
    ctx.fillStyle = PAL.harvestGold; ctx.font = '22px "Bungee", "Arial Black", sans-serif'; ctx.fillText('WZTV', 128, 56);
    // (256,0)-(512,128): concrete with hazard band (plinth side)
    ctx.fillStyle = '#9A958E'; ctx.fillRect(256, 0, 256, 128);
    for (let i = 0; i < 1500; i++) { ctx.fillStyle = rand() < 0.5 ? 'rgba(60,56,52,0.25)' : 'rgba(220,214,204,0.25)'; ctx.fillRect(256 + rand() * 256, rand() * 128, 1.5, 1.5); }
    ctx.save(); ctx.beginPath(); ctx.rect(256, 40, 256, 48); ctx.clip();
    ctx.fillStyle = '#F4C81E'; ctx.fillRect(256, 40, 256, 48);
    ctx.fillStyle = '#231A22';
    for (let x = 220; x < 540; x += 36) { ctx.beginPath(); ctx.moveTo(x, 88); ctx.lineTo(x + 18, 88); ctx.lineTo(x + 66, 40); ctx.lineTo(x + 48, 40); ctx.closePath(); ctx.fill(); }
    ctx.restore();
    // (256,128)-(512,192): motor box label
    ctx.fillStyle = '#23324A'; ctx.beginPath(); ctx.roundRect(256, 128, 256, 64, 8); ctx.fill();
    ctx.fillStyle = '#F4F1E8'; ctx.font = '24px "Bungee", "Arial Black", sans-serif'; ctx.fillText('UPLINK 13', 384, 152);
    ctx.fillStyle = '#FFB347'; ctx.font = '11px "Titan One", sans-serif'; ctx.fillText('AZ-EL DRIVE · DO NOT CLIMB', 384, 177);
    // (256,192)-(512,256): pedestal door (danger)
    ctx.fillStyle = '#F4C81E'; ctx.beginPath(); ctx.roundRect(256, 192, 256, 64, 8); ctx.fill();
    ctx.fillStyle = '#231A22'; ctx.font = '20px "Bungee", "Arial Black", sans-serif'; ctx.fillText('DANGER', 384, 214);
    ctx.font = '11px "Titan One", sans-serif'; ctx.fillText('HIGH-POWER MICROWAVE · STAND CLEAR', 384, 238);
  }, { repeat: false, fonts: true });
  return { face, atlas };
}

registerProp('uplink_dish', (game, opts = {}) => {
  const g = K.prop('uplink_dish');
  const { face, atlas } = dishTextures();
  const paint = K.mat(game, 'paint', '#ffffff', { rough: 0.5 });                 // tinted: white, WZTV blue, steel
  const dishMat = K.mat(game, 'paint', '#ffffff', { map: face, rough: 0.45 });
  const atl = K.mat(game, 'paint', '#ffffff', { map: atlas, rough: 0.55 });
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const WHITE = '#F1EFE9', BLUE = '#3E67C8', STEEL = '#5A5E6E', DARK = '#3A3A48';
  const { R, depth, pivotY, hub, f } = UP_DISH;
  const zOf = (r) => -(hub + (r * r) / (4 * f));                              // dish front surface (tilt space)
  const SEG = 48;

  // ---- plinth (concrete + hazard band), bolted steel collar, blue pedestal column
  const plinth = K.lathe([[0, 0], [1.3, 0], [1.3, 0.25], [0, 0.25]], { seg: 28, round: 0.05, steps: 2 }).clone();
  cellUV(plinth, 256, 0, 512, 128);
  g.add(K.m(plinth, atl));
  g.add(K.m(tinted(K.lathe([[0, 0.24], [0.72, 0.24], [0.74, 0.3], [0.6, 0.34], [0, 0.34]], { seg: 20, round: 0.02, steps: 1 }), STEEL), paint));
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * TAU;
    g.add(K.m(tinted(new THREE.CylinderGeometry(0.034, 0.04, 0.05, 6), DARK), paint, { pos: [Math.cos(a) * 0.66, 0.32, Math.sin(a) * 0.66] }));
  }
  g.add(K.m(tinted(K.lathe([[0, 0.3], [0.55, 0.3], [0.5, 0.6], [0.42, 1.9], [0.5, 1.98], [0, 1.98]], { seg: 18, round: 0.04, steps: 1 }), BLUE), paint));
  // access door + danger plate on the front
  g.add(K.m(tinted(K.box(0.4, 0.8, 0.04, 0.03), '#3558A8'), paint, { pos: [0, 0.95, -0.49], rot: [0.06, 0, 0] }));
  g.add(K.m(cellUV(new THREE.PlaneGeometry(0.34, 0.085).rotateY(Math.PI), 256, 192, 512, 256), atl, { pos: [0, 1.2, -0.515], rot: [0.06, 0, 0] }));
  g.add(K.m(chromeHandle(), chrome, { pos: [0.14, 0.9, -0.52], rot: [0.06, 0, 0] }));
  // ladder on the +x side
  for (const s of [-1, 1]) g.add(K.m(new THREE.CylinderGeometry(0.018, 0.018, 1.75, 6).translate(0, 0.875, 0), chrome, { pos: [0.56, 0.3, s * 0.17] }));
  for (let i = 0; i < 7; i++) g.add(K.m(new THREE.CylinderGeometry(0.013, 0.013, 0.34, 6), chrome, { pos: [0.56, 0.5 + i * 0.24, 0], rot: [Math.PI / 2, 0, 0] }));
  // bull gear ring on top of the pedestal
  const teeth = [];
  const nT = 28, rG = 0.72;
  for (let i = 0; i < nT * 2; i++) { const a = (i / (nT * 2)) * TAU, r = i % 2 ? rG : rG + 0.05; teeth.push([Math.cos(a) * r, Math.sin(a) * r]); }
  const gearShape = new THREE.Shape(teeth.map(([x, y]) => new THREE.Vector2(x, y)));
  gearShape.holes.push(new THREE.Path(ringXY(0.4, 20).map(([x, y]) => new THREE.Vector2(x, y))));
  const gear = K.extrude(gearShape, 0.1, { bevel: 0.012, bevelSeg: 1, curveSeg: 4 });
  gear.rotateX(-Math.PI / 2);
  g.add(K.m(tinted(gear, STEEL), paint, { pos: [0, 2.03, 0] }));

  // ---- yaw head: platform, yoke arms, bearings, motor box, elevation pinion
  const yaw = grp('yaw', [0, 2.08, 0]);
  yaw.add(K.m(tinted(K.lathe([[0, 0], [0.8, 0], [0.82, 0.06], [0.76, 0.14], [0, 0.14]], { seg: 24, round: 0.03, steps: 1 }), BLUE), paint));
  const armH = pivotY - 2.08 - 0.12;
  for (const s of [-1, 1]) {
    const arm = K.extrude([[-0.3, 0], [0.3, 0], [0.2, armH], [-0.2, armH]], 0.13, { bevel: 0.03, round: 0.05, bevelSeg: 2 });
    arm.rotateY(Math.PI / 2);
    yaw.add(K.m(tinted(arm, BLUE), paint, { pos: [s * 0.66, 0.12, 0] }));
    yaw.add(K.m(tinted(K.cyl(0.19, 0.19, 0.16, { bevel: 0.03, seg: 14 }), STEEL), paint, { pos: [s * 0.74 - 0.08, pivotY - 2.08, 0], rot: [0, 0, -Math.PI / 2] }));
    yaw.add(K.m(tinted(K.cyl(0.1, 0.1, 0.05, { bevel: 0.015, seg: 10 }), WHITE), paint, { pos: [s * 0.82 + (s > 0 ? 0 : -0.05), pivotY - 2.08, 0], rot: [0, 0, -Math.PI / 2] }));
  }
  yaw.add(K.m(tinted(K.box(0.5, 0.36, 0.42, 0.06), '#2F4F9E'), paint, { pos: [0, 0.32, 0.46] }));
  yaw.add(K.m(cellUV(new THREE.PlaneGeometry(0.4, 0.1), 256, 128, 512, 192), atl, { pos: [0, 0.34, 0.672] }));
  for (let i = 0; i < 4; i++) yaw.add(K.m(tinted(K.box(0.42, 0.018, 0.02, 0.008), '#243E80'), paint, { pos: [0, 0.2 + i * 0.05, 0.265] }));
  yaw.add(K.m(tinted(K.tube([[0.2, 0.3, 0.68], [0.3, 0.12, 0.72], [0.44, -0.3, 0.58], [0.48, -0.6, 0.5]], 0.028, { seg: 10, radial: 5 }), DARK), paint));
  yaw.add(K.m(tinted(K.cyl(0.13, 0.13, 0.08, { bevel: 0.02, seg: 12 }), STEEL), paint, { pos: [0.3, pivotY - 2.08 - 0.95, 0.12], rot: [0, 0, -Math.PI / 2] }));
  g.add(yaw);

  // ---- tilt: the dish (tilt space: pivot at origin, dish axis toward -z)
  const tilt = grp('tilt', [0, pivotY - 2.08, 0]);
  yaw.add(tilt);
  const dent = { a: 0.72, r: 1.6, rad: 0.45, amt: 0.16 };
  const dentK = (x, y) => {            // x, y in the dish plane (tilt space, before any axial offset)
    const ang = Math.atan2(y, x), rr = Math.hypot(x, y);
    const da = Math.atan2(Math.sin(ang - dent.a), Math.cos(ang - dent.a)) * rr;
    const d2 = da * da + (rr - dent.r) * (rr - dent.r);
    return { k: Math.exp(-d2 / (dent.rad * dent.rad * 0.5)), da, dr: rr - dent.r };
  };
  // profiles in lathe space [r, h] (h = height toward the dish opening); front = concave skin (normals up),
  // back = convex skin 0.08 behind (normals down), lip = rolled rim joining them
  const N = 12, rs = [];
  for (let i = 0; i <= N; i++) rs.push((i / N) ** 0.8 * (R - 0.03));
  const front = rs.map((r) => [r, (r * r) / (4 * f)]).reverse();              // rim -> center: normals face the opening
  const backP = rs.map((r) => [r, (r * r) / (4 * f) - 0.08]);                // center -> rim: normals face the back
  const lip = [[R - 0.03, depth - 0.08 + 0.001], [R + 0.03, depth - 0.07], [R + 0.05, depth - 0.02], [R + 0.02, depth + 0.012], [R - 0.03, depth - 0.001]];
  const toGeo = (pts, dentIt) => {
    const gg = new THREE.LatheGeometry(pts.map(([x, y]) => new THREE.Vector2(x, y)), SEG);
    gg.rotateX(-Math.PI / 2);                                                  // lathe +y -> tilt -z
    if (dentIt) warp(gg, (v) => { const { k, da, dr } = dentK(v.x, v.y); v.z += dent.amt * k * (1 + 0.3 * Math.sin(da * 28) * Math.sin(dr * 22)); });
    gg.translate(0, 0, -hub);
    return gg;
  };
  const frontGeo = toGeo(front, true);
  {
    const uv = frontGeo.attributes.uv;           // v = 0 at the center .. 1 at the rim
    for (let i = 0; i < uv.count; i++) uv.setY(i, 1 - uv.getY(i));
  }
  K.tint(frontGeo, (x, y) => { const { k, da, dr } = dentK(x, y); const c = 1 - 0.3 * k - 0.12 * k * Math.sin(da * 28) * Math.sin(dr * 22); return new THREE.Color(c, c, c * 1.04); });
  tilt.add(K.m(frontGeo, dishMat));
  tilt.add(K.m(tinted(toGeo(backP, true), WHITE), paint));
  tilt.add(K.m(tinted(toGeo(lip, false), WHITE), paint));
  // center badge conformed to the paraboloid, 6 mm in front of the surface
  const badge = new THREE.CircleGeometry(0.8, 28);
  cellUV(badge, 0, 0, 256, 256);
  warp(badge, (v) => { v.z = (v.x * v.x + v.y * v.y) / (4 * f) + 0.012; });
  badge.rotateY(Math.PI);
  badge.translate(0, 0, -hub);
  tilt.add(K.m(badge, atl));
  // rivet ring on the rim band
  const rivet = new THREE.SphereGeometry(0.026, 5, 2, 0, TAU, 0, Math.PI / 2);
  const rivets = [];
  for (let i = 0; i < 40; i++) {
    const a = (i / 40) * TAU, r = R - 0.12;
    const rg2 = rivet.clone();
    rg2.rotateX(-Math.PI / 2 + 0.55);
    rg2.rotateZ(a - Math.PI / 2);
    rg2.translate(Math.cos(a) * r, Math.sin(a) * r, zOf(r) - 0.004);
    rivets.push(rg2);
  }
  tilt.add(K.m(tinted(mergeGeos(rivets), '#D4D0C6'), paint));
  // chrome bulb rail + instanced chaser bulbs (setUplinkChase)
  const rail = [];
  for (let i = 0; i < 48; i++) { const a = (i / 48) * TAU; rail.push([Math.cos(a) * (R + 0.035), Math.sin(a) * (R + 0.035), -(hub + depth) - 0.02]); }
  tilt.add(K.m(K.tube(rail, 0.022, { seg: 64, radial: 4, closed: true }), chrome));
  const bulbs = new THREE.InstancedMesh(new THREE.SphereGeometry(0.055, 6, 4), K.glow(game, '#ffffff', 2.4), UP_DISH.bulbs);
  const m4 = new THREE.Matrix4();
  for (let i = 0; i < UP_DISH.bulbs; i++) {
    const a = (i / UP_DISH.bulbs) * TAU;
    m4.makeTranslation(Math.cos(a) * (R + 0.035), Math.sin(a) * (R + 0.035), -(hub + depth) - 0.07);
    bulbs.setMatrixAt(i, m4);
    bulbs.setColorAt(i, _cc.set(PAL.marqueeGold).multiplyScalar(0.1));
  }
  bulbs.name = 'rimBulbs';
  bulbs.userData.noMerge = true;
  bulbs.castShadow = false;
  tilt.add(bulbs);
  // back ribs (radial trusses), hub drum, pivot shaft, counterweight
  for (let k = 0; k < 6; k++) {
    const pts = [];
    for (let i = 0; i <= 7; i++) { const r = 0.3 + (i / 7) * 1.95; pts.push([r, zOf(r) + 0.08]); }
    for (let i = 7; i >= 0; i--) { const r = 0.3 + (i / 7) * 1.95; pts.push([r, zOf(r) + 0.08 + lerp(0.36, 0.05, i / 7)]); }
    const rib = K.extrude(pts, 0.05, { bevel: 0.012, bevelSeg: 1 });
    rib.rotateX(Math.PI / 2);                                                 // shape y -> tilt z, thickness -> tangential
    rib.rotateZ((k / 6) * TAU + TAU / 12);
    tilt.add(K.m(tinted(rib, WHITE), paint));
  }
  tilt.add(K.m(tinted(K.cyl(0.34, 0.34, hub + 0.2, { bevel: 0.05, seg: 16 }), WHITE), paint, { pos: [0, 0, 0.2], rot: [-Math.PI / 2, 0, 0] }));
  tilt.add(K.m(tinted(K.cyl(0.13, 0.13, 1.3, { bevel: 0.02, seg: 10 }), STEEL), paint, { pos: [-0.65, 0, 0], rot: [0, 0, -Math.PI / 2] }));
  tilt.add(K.m(tinted(K.box(0.42, 0.34, 0.3, 0.06), STEEL), paint, { pos: [0, 0.05, 0.4] }));
  // elevation sector gear (rides with the dish)
  const sec = [];
  const a0 = -Math.PI / 2 - 0.6, a1 = -Math.PI / 2 + 1.25, nt = 22;
  for (let i = 0; i <= nt * 2; i++) { const a = lerp(a0, a1, i / (nt * 2)), r = i % 2 ? 0.95 : 1.0; sec.push([Math.cos(a) * r, Math.sin(a) * r]); }
  for (let i = 6; i >= 0; i--) { const a = lerp(a0, a1, i / 6); sec.push([Math.cos(a) * 0.62, Math.sin(a) * 0.62]); }
  const secGeo = K.extrude(sec.map(([zz, y]) => [-zz, y]), 0.06, { bevel: 0.01, bevelSeg: 1 });
  secGeo.rotateY(Math.PI / 2);
  tilt.add(K.m(tinted(secGeo, STEEL), paint, { pos: [0.3, 0, 0] }));
  // feed struts to the focal feed (white body, red horn facing the dish)
  const fz = -(hub + f);
  for (let k = 0; k < 4; k++) {
    const a = (k / 4) * TAU + Math.PI / 4;
    tilt.add(rod([Math.cos(a) * (R - 0.15), Math.sin(a) * (R - 0.15), zOf(R - 0.15) - 0.02], [Math.cos(a) * 0.12, Math.sin(a) * 0.12, fz - 0.05], 0.035, paint, { tint: WHITE, seg: 7, r2: 0.028 }));
  }
  const feed = grp('feed', [0, 0, fz]);
  feed.add(K.m(tinted(K.cyl(0.14, 0.16, 0.34, { bevel: 0.04, seg: 12 }), WHITE), paint, { pos: [0, 0, -0.34], rot: [Math.PI / 2, 0, 0] }));
  feed.add(K.m(tinted(K.lathe([[0.06, 0], [0.14, 0.02], [0.24, 0.24], [0.22, 0.26], [0.1, 0.06], [0, 0.06]], { seg: 14, round: 0.02, steps: 1 }), PAL.channelRed), paint, { pos: [0, 0, 0.0], rot: [Math.PI / 2, 0, 0] }));
  tilt.add(feed);

  g.userData.parts = { yaw, tilt, rimBulbs: bulbs, feed };
  g.userData.rig = { droop: UP_DISH.droop, aligned: UP_DISH.aligned, pivotY, radius: R, bulbs: UP_DISH.bulbs };
  g.userData.colliders = [
    { min: [-1.3, 0, -1.3], max: [1.3, 0.34, 1.3] },
    { min: [-0.62, 0, -0.62], max: [0.62, 2.2, 0.62] },
    { min: [-1.9, 0, -2.3], max: [1.9, 1.5, -1.0], opts: { tag: 'uplink_droop' } },   // under the drooped rim; drop after alignment
  ];
  g.userData.interact = null;
  tilt.rotation.x = 0.45;                              // bake pose (dish up: no floor darkening on the rim)
  finishRig(game, g, { finish: { ao: { res: 64, strength: 0.7, dist: 0.5 } } });
  setUplinkPose(g, { tilt: opts.tilt ?? (opts.aligned ? UP_DISH.aligned : UP_DISH.droop), yaw: opts.yaw ?? 0 });
  setUplinkChase(g, 0, { on: !!opts.lit });
  return g;
}, { category: 'machines', tags: ['uplink', 'machine', 'yard', 'dish'], size: [5.3, 5.8, 5.2], desc: 'THE UPLINK: 5 m white satellite dish on an az-el turntable', hero: true });

function chromeHandle() {
  return K.tube([[0, 0.06, 0], [0, 0.07, -0.03], [0, -0.07, -0.03], [0, -0.06, 0]], 0.009, { seg: 10, radial: 5 });
}

registerScene('uplink', {
  floor: '#4A4652', wall: '#1E2344', room: [14, 12], wallH: 7, hemi: 0.75,
  items: [
    { id: 'uplink_dish', pos: [0, 2.2], rotY: 0, opts: { aligned: true, lit: true } },
  ],
  cam: { pos: [5.5, 3.4, -6.5], target: [0, 2.6, 1.5], fov: 50 },
});

// ---------------------------------------------------------------------------------------------- cradle
// Feed-horn cradle (anchor uplink_cradle: the gun sits at y 1.3). The horn hangs above-behind the clamp and aims
// its R/G/B lamps down at the weapon. parts.jawF/jawB rotate about x (rig.jawOpen .. 0 closed); parts.gunSlot.
export function setCradleLamps(game, g, level = 1) {
  const P = g.userData.parts;
  const q = Math.round(clamp(level, 0, 1) * 10) / 10;
  [['lampR', PAL.hotMic], ['lampG', PAL.laughTrack], ['lampB', PAL.coldOpen]].forEach(([k, c]) => {
    if (P[k]) P[k].material = q > 0 ? K.glow(game, c, 0.6 + 2.6 * q) : K.mat(game, 'plastic', '#3A3440');
  });
}
function yardAtlas() {
  return K.tex.canvas('yard_atlas_v1', 512, 512, (ctx, W, H, rand) => {
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const plate = (x, y, w, h, bg, fg, t1, t2, acc) => {
      ctx.fillStyle = bg; ctx.beginPath(); ctx.roundRect(x, y, w, h, 8); ctx.fill();
      ctx.strokeStyle = acc || 'rgba(255,255,255,0.5)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.roundRect(x + 4, y + 4, w - 8, h - 8, 6); ctx.stroke();
      ctx.fillStyle = fg; ctx.font = `${Math.round(h * 0.42)}px "Bungee", "Arial Black", sans-serif`; ctx.fillText(t1, x + w / 2, y + h * (t2 ? 0.4 : 0.52));
      if (t2) { ctx.fillStyle = acc || fg; ctx.font = `${Math.round(h * 0.18)}px "Titan One", sans-serif`; ctx.fillText(t2, x + w / 2, y + h * 0.76); }
    };
    plate(0, 0, 256, 64, '#23324A', '#F4F1E8', 'FEED HORN', 'UPLINK 13 · KU BAND', '#FFB347');
    plate(256, 0, 256, 64, '#F4F1E8', '#23324A', 'ALIGN DISH', 'CRANK CLOCKWISE  >>>', '#E23B3B');
    plate(0, 64, 512, 64, '#E23B3B', '#F4F1E8', 'UPLINK CONTROL', 'WZTV CHANNEL 13 · AUTHORIZED CREW ONLY', '#FFD23A');
    plate(0, 128, 256, 64, '#3A4A3E', '#F4F1E8', 'WZTV 50 kW', 'TRANSMITTER · FINAL AMP', '#9CFF57');
    // gauge faces (0,192)-(128,320) elevation, (128,192)-(256,320) plate volts, (256,192)-(384,320) spare
    [['ELEVATION', 0, true], ['PLATE KV', 128, false], ['SIGNAL', 256, false]].forEach(([label, ox, lock]) => {
      const cx = ox + 64, cy = 256;
      ctx.fillStyle = '#F4ECD6'; ctx.beginPath(); ctx.arc(cx, cy, 63, 0, TAU); ctx.fill();
      ctx.lineWidth = 7;
      ctx.strokeStyle = lock ? '#52D24A' : '#E23B3B';
      ctx.beginPath(); ctx.arc(cx, cy + 10, 44, lock ? Math.PI * 1.7 : Math.PI * 1.72, Math.PI * 1.86); ctx.stroke();
      ctx.strokeStyle = '#2A2230'; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.arc(cx, cy + 10, 44, Math.PI * 1.14, Math.PI * 1.86); ctx.stroke();
      for (let i = 0; i <= 10; i++) {
        const a = Math.PI * 1.14 + (i / 10) * Math.PI * 0.72, l = i % 5 ? 6 : 11;
        ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * 44, cy + 10 + Math.sin(a) * 44); ctx.lineTo(cx + Math.cos(a) * (44 - l), cy + 10 + Math.sin(a) * (44 - l)); ctx.stroke();
      }
      ctx.fillStyle = '#2A2230'; ctx.font = '11px "Bungee", "Arial Black", sans-serif'; ctx.fillText(label, cx, cy + 32);
      if (lock) { ctx.fillStyle = '#2E9A3A'; ctx.font = '10px "Titan One", sans-serif'; ctx.fillText('LOCK', cx + 30, cy - 36); }
    });
    // corrugated wall (384,192)-(512,320) (repeat-free strip): cream with vertical ribs
    for (let x = 384; x < 512; x += 16) {
      const gr = ctx.createLinearGradient(x, 0, x + 16, 0);
      gr.addColorStop(0, '#CFC6B0'); gr.addColorStop(0.5, '#F2EAD6'); gr.addColorStop(1, '#CFC6B0');
      ctx.fillStyle = gr; ctx.fillRect(x, 192, 16, 128);
    }
    // interior console glow (0,320)-(256,448): dark panel with lit buttons and a tiny scope
    ctx.fillStyle = '#1A2230'; ctx.fillRect(0, 320, 256, 128);
    const cols = ['#FF3B30', '#FFD23A', '#52E04A', '#7FE7FF', '#FF8A2A'];
    for (let j = 0; j < 3; j++) for (let i = 0; i < 9; i++) {
      ctx.fillStyle = cols[(i * 3 + j * 7) % 5]; ctx.globalAlpha = 0.5 + rand() * 0.5;
      ctx.beginPath(); ctx.roundRect(16 + i * 18, 340 + j * 18, 11, 9, 3); ctx.fill();
    }
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#0E2A1A'; ctx.beginPath(); ctx.roundRect(186, 334, 56, 44, 6); ctx.fill();
    ctx.strokeStyle = '#52E04A'; ctx.lineWidth = 2; ctx.beginPath();
    for (let x = 0; x <= 48; x++) { const y = 356 + Math.sin(x * 0.5) * 10 * Math.exp(-x / 40); if (x) ctx.lineTo(190 + x, y); else ctx.moveTo(190, y); }
    ctx.stroke();
    ctx.fillStyle = '#7FE7FF'; ctx.globalAlpha = 0.7; ctx.fillRect(16, 404, 224, 6); ctx.globalAlpha = 1;
    // solar cells (256,320)-(512,448): blue grid with silver bus lines
    ctx.fillStyle = '#1E3A8A'; ctx.fillRect(256, 320, 256, 128);
    for (let j = 0; j < 4; j++) for (let i = 0; i < 8; i++) {
      const gx = 260 + i * 31.5, gy = 324 + j * 31;
      const gr = ctx.createLinearGradient(gx, gy, gx + 28, gy + 28);
      gr.addColorStop(0, '#3E6BD6'); gr.addColorStop(1, '#1B3478');
      ctx.fillStyle = gr; ctx.fillRect(gx, gy, 28, 27);
      ctx.fillStyle = 'rgba(200,210,230,0.5)'; ctx.fillRect(gx, gy + 13, 28, 1.5);
    }
    // gold foil (0,448)-(256,512)
    ctx.fillStyle = '#D9A63A'; ctx.fillRect(0, 448, 256, 64);
    for (let i = 0; i < 90; i++) {
      ctx.fillStyle = rand() < 0.5 ? 'rgba(255,236,160,0.45)' : 'rgba(120,80,20,0.35)';
      ctx.beginPath(); const x = rand() * 256, y = 448 + rand() * 64;
      ctx.moveTo(x, y); ctx.lineTo(x + 6 + rand() * 18, y + (rand() - 0.5) * 10); ctx.lineTo(x + rand() * 10, y + 6 + rand() * 10); ctx.closePath(); ctx.fill();
    }
    // satellite band (256,448)-(512,512): white with SKYLARK-13
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(256, 448, 256, 64);
    ctx.fillStyle = PAL.wztvBlue; ctx.font = '26px "Bungee", "Arial Black", sans-serif'; ctx.fillText('SKYLARK-13', 384, 482);
    ctx.fillStyle = PAL.channelRed; ctx.fillRect(256, 450, 256, 5); ctx.fillRect(256, 505, 256, 5);
  }, { repeat: false, fonts: true });
}

registerProp('uplink_cradle', (game, opts = {}) => {
  const g = K.prop('uplink_cradle');
  const paint = K.mat(game, 'paint', '#ffffff', { rough: 0.45 });
  const atl = K.mat(game, 'paint', '#ffffff', { map: yardAtlas(), rough: 0.5 });
  const alu = K.mat(game, 'metal', '#C9CED6', { map: K.tex.brushed('#C9CED6') });
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const BLUE = '#3E67C8', WHITE = '#F1EFE9', RED = '#D93A34', RUBBER = '#2A2430', STEEL = '#5A5E6E';
  const slotY = 1.3;
  // foot + column + band + plate
  g.add(K.m(tinted(K.lathe([[0, 0], [0.34, 0], [0.35, 0.04], [0.27, 0.09], [0.12, 0.12], [0, 0.12]], { seg: 16, round: 0.025, steps: 1 }), BLUE), paint));
  for (let i = 0; i < 6; i++) { const a = (i / 6) * TAU + 0.3; g.add(K.m(tinted(new THREE.CylinderGeometry(0.022, 0.026, 0.03, 6), STEEL), paint, { pos: [Math.cos(a) * 0.27, 0.07, Math.sin(a) * 0.27] })); }
  g.add(K.m(tinted(K.cyl(0.075, 0.095, 0.78, { bevel: 0.02, seg: 12 }), BLUE), paint, { pos: [0, 0.1, 0] }));
  g.add(K.m(tinted(K.cyl(0.083, 0.086, 0.08, { bevel: 0.01, seg: 12 }), WHITE), paint, { pos: [0, 0.6, 0] }));
  g.add(K.m(cellUV(new THREE.PlaneGeometry(0.2, 0.05).rotateY(Math.PI), 0, 0, 256, 64), atl, { pos: [0, 0.42, -0.094] }));
  // the feed horn: a big square aluminium horn opening to the sky, red rim, flange + rivets at the throat
  const horn = new THREE.Group();
  horn.position.set(0, 0.86, 0.02);
  horn.rotation.x = -0.15;                                 // leans toward the player: lamps + gun visible inside
  const hornProf = [[0.1, 0], [0.12, 0.04], [0.16, 0.12], [0.3, 0.38], [0.42, 0.56], [0.43, 0.6], [0.4, 0.6], [0.29, 0.4], [0.14, 0.13], [0.09, 0.06]];
  const HX = 1.2;                                          // wider along x (the gun lies across the mouth)
  const hornGeo = K.lathe(hornProf, { seg: 4, round: 0.025, steps: 1 }).clone();
  hornGeo.rotateY(Math.PI / 4).scale(HX, 1, 1);
  K.uvScale(hornGeo, 2, 1);
  horn.add(K.m(hornGeo, alu));
  const rimGeo = K.lathe([[0.415, 0.575], [0.45, 0.585], [0.45, 0.63], [0.41, 0.63]], { seg: 4, round: 0.012, steps: 1 }).clone();
  rimGeo.rotateY(Math.PI / 4).scale(HX, 1, 1);
  horn.add(K.m(tinted(rimGeo, RED), paint));
  const flange = K.lathe([[0.1, -0.02], [0.17, -0.02], [0.17, 0.05], [0.1, 0.05]], { seg: 4, round: 0.01, steps: 1 }).clone();
  flange.rotateY(Math.PI / 4).scale(HX, 1, 1);
  horn.add(K.m(tinted(flange, STEEL), paint));
  const wallR = (y) => (y < 0.12 ? lerp(0.12, 0.16, y / 0.12) : y < 0.38 ? lerp(0.16, 0.3, (y - 0.12) / 0.26) : lerp(0.3, 0.42, (y - 0.38) / 0.18)) * Math.SQRT1_2;
  for (let k = 0; k < 4; k++) for (let j = 0; j < 3; j++) {  // rivet rows up the face centres
    const y = 0.2 + j * 0.13, a = (k / 4) * TAU, r = wallR(y) + 0.006;
    horn.add(K.m(new THREE.SphereGeometry(0.013, 5, 3), chrome, { pos: [Math.sin(a) * r * HX, y, Math.cos(a) * r] }));
  }
  // R/G/B lamps on the inner walls near the throat, aimed at the gun
  const lamps = {};
  [['lampR', PAL.hotMic, Math.PI / 2], ['lampG', PAL.laughTrack, 0], ['lampB', PAL.coldOpen, -Math.PI / 2]].forEach(([k, c, a]) => {
    const y = 0.26, wr = wallR(y), sx = Math.sin(a), sz = Math.cos(a);
    const rot = sz > 0.5 ? [-Math.PI / 2, 0, 0] : [0, 0, sx > 0 ? Math.PI / 2 : -Math.PI / 2];
    horn.add(K.m(K.cyl(0.036, 0.04, 0.03, { bevel: 0.008, seg: 8 }), chrome, { pos: [sx * wr * HX * 0.93, y, sz * wr * 0.93], rot }));
    const l = keep(K.m(new THREE.SphereGeometry(0.036, 8, 6), K.glow(game, c, 2.4), { pos: [sx * wr * HX * 0.76, y, sz * wr * 0.76], name: k, cast: false }));
    l.userData.noOcclude = true;
    horn.add(l);
    lamps[k] = l;
  });
  g.add(horn);
  // clamp arm rising through the throat to a padded C-clamp holding the gun across the mouth (along x)
  g.add(K.m(tinted(K.cyl(0.035, 0.045, slotY - 0.95, { bevel: 0.01, seg: 10 }), STEEL), paint, { pos: [0, 0.9, 0.0] }));
  g.add(K.m(tinted(K.box(0.3, 0.06, 0.12, 0.014), BLUE), paint, { pos: [0, slotY - 0.08, 0] }));
  for (const sx of [-1, 1]) g.add(K.m(tinted(K.box(0.05, 0.08, 0.11, 0.012), RUBBER), paint, { pos: [sx * 0.12, slotY - 0.03, 0] }));
  // U-bracket yoke with pivot bolts on the horn's sides (reads as an aimed antenna mount)
  g.add(K.m(tinted(K.tube([[-0.25, 1.07, 0], [-0.25, 0.92, 0], [-0.12, 0.85, 0], [0.12, 0.85, 0], [0.25, 0.92, 0], [0.25, 1.07, 0]], 0.028, { seg: 16, radial: 6 }), BLUE), paint));
  for (const sx of [-1, 1]) g.add(K.m(tinted(K.cyl(0.045, 0.045, 0.1, { bevel: 0.012, seg: 10 }), STEEL), paint, { pos: [sx * 0.3, 1.07, 0], rot: [0, 0, sx * Math.PI / 2] }));
  const gunSlot = grp('gunSlot', [0, slotY, 0]);
  g.add(gunSlot);
  const jaws = {};
  for (const [name, s] of [['jawF', -1], ['jawB', 1]]) {
    const jaw = grp(name, [0, slotY - 0.07, s * 0.06]);
    for (const sx of [-1, 1]) jaw.add(K.m(tinted(K.tube([[0, 0, 0], [0, 0.07, s * 0.05], [0, 0.14, s * 0.02], [0, 0.16, -s * 0.03]], 0.018, { seg: 8, radial: 5 }), RED), paint, { pos: [sx * 0.12, 0, 0] }));
    jaw.add(K.m(tinted(K.box(0.3, 0.04, 0.05, 0.012), RUBBER), paint, { pos: [0, 0.16, -s * 0.035] }));
    jaw.rotation.x = s * 0.5;
    g.add(jaw);
    jaws[name] = jaw;
  }
  // cable down the back toward the dish (+z)
  g.add(K.m(tinted(K.tube([[0.1, 0.95, 0.12], [0.12, 0.6, 0.12], [0.13, 0.08, 0.2], [0.12, 0.012, 0.8]], 0.02, { seg: 14, radial: 5 }), RUBBER), paint));

  g.userData.parts = { gunSlot, jawF: jaws.jawF, jawB: jaws.jawB, ...lamps, horn };
  g.userData.rig = { slotY, jawOpenF: -0.5, jawOpenB: 0.5, jawClosed: 0, beamFrom: [0, 1.5, 0.08], beamDir: [0, Math.cos(0.12), Math.sin(0.12)] };
  g.userData.colliders = [{ min: [-0.46, 0, -0.44], max: [0.46, 1.5, 0.5] }];
  g.userData.interact = { point: [0, slotY, -0.55], radius: 1.3 };
  finishRig(game, g);
  if (opts.closed) { jaws.jawF.rotation.x = 0; jaws.jawB.rotation.x = 0; }
  setCradleLamps(game, g, opts.lamps ?? 0);
  return g;
}, { category: 'machines', tags: ['uplink', 'machine', 'yard'], size: [0.92, 1.5, 0.95], desc: 'Uplink feed-horn cradle: sky-facing horn with a gun clamp and R/G/B lamps inside', hero: true });

// ----------------------------------------------------------------------------------------------- crank
// Alignment crank (anchor uplink_crank: wheel hub at y 1.0, wheel facing the operator). parts.wheel spins about z,
// parts.handle = glowing grip (setCrankGlow), parts.needle = elevation gauge (rig.needleMin droop .. needleMax lock).
export function setCrankGlow(game, g, level = 1) {
  const P = g.userData.parts;
  const q = Math.round(clamp(level, 0, 1) * 10) / 10;
  if (P.handle) P.handle.material = q > 0 ? K.glow(game, PAL.marqueeGold, 0.5 + 2.5 * q) : K.mat(game, 'plastic', '#B89A5A');
}
registerProp('uplink_crank', (game, opts = {}) => {
  const g = K.prop('uplink_crank');
  const paint = K.mat(game, 'paint', '#ffffff', { rough: 0.45 });
  const atl = K.mat(game, 'paint', '#ffffff', { map: yardAtlas(), rough: 0.5 });
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const BLUE = '#3E67C8', RED = '#D93A34', STEEL = '#5A5E6E', DARK = '#2E2A36';
  const hubY = 1.0;
  // cast bell base + column + gearbox
  g.add(K.m(tinted(K.lathe([[0, 0], [0.3, 0], [0.31, 0.04], [0.2, 0.12], [0.1, 0.22], [0.08, 0.3], [0, 0.3]], { seg: 14, round: 0.03, steps: 1 }), BLUE), paint));
  g.add(K.m(tinted(K.cyl(0.075, 0.085, 0.55, { bevel: 0.02, seg: 12 }), BLUE), paint, { pos: [0, 0.28, 0.02] }));
  g.add(K.m(tinted(K.box(0.3, 0.3, 0.3, 0.045), BLUE), paint, { pos: [0, hubY, 0.08] }));
  g.add(K.m(tinted(K.cyl(0.13, 0.13, 0.05, { bevel: 0.015, seg: 16 }), STEEL), paint, { pos: [0.151, hubY, 0.08], rot: [0, 0, -Math.PI / 2] }));
  for (let i = 0; i < 3; i++) g.add(K.m(tinted(K.box(0.24, 0.016, 0.02, 0.007), '#2F4F9E'), paint, { pos: [0, hubY - 0.08 + i * 0.05, 0.235] }));
  // elevation gauge on a tilted pod on top
  const pod = new THREE.Group();
  pod.position.set(0, hubY + 0.44, 0.1);
  g.add(K.m(tinted(K.cyl(0.035, 0.045, 0.3, { bevel: 0.01, seg: 10 }), BLUE), paint, { pos: [0, hubY + 0.12, 0.1] }));
  pod.rotation.x = 0.55;
  pod.add(K.m(tinted(K.cyl(0.11, 0.12, 0.07, { bevel: 0.02, seg: 14 }), BLUE), paint, { rot: [-Math.PI / 2, 0, 0] }));
  pod.add(K.m(K.tube(ringXY(0.1, 20, 0), 0.01, { seg: 24, radial: 4, closed: true }), chrome, { pos: [0, 0, -0.072] }));
  pod.add(K.m(disc(0.095, 24, [0, 192, 128, 320]), atl, { pos: [0, 0, -0.071] }));
  const needle = grp('needle', [0, -0.012, -0.075]);
  needle.add(K.m(tinted(new THREE.BoxGeometry(0.006, 0.075, 0.004).translate(0, 0.036, 0), RED), paint));
  needle.add(K.m(K.cyl(0.01, 0.01, 0.006, { bevel: 0.002, seg: 8 }), chrome, { rot: [-Math.PI / 2, 0, 0] }));
  pod.add(needle);
  g.add(pod);
  g.add(K.m(cellUV(new THREE.PlaneGeometry(0.28, 0.07).rotateY(Math.PI), 256, 0, 512, 64), atl, { pos: [0, 0.66, -0.066] }));
  // the handwheel: red rim, 5 swept spokes, chrome hub, glowing grip (spins with the wheel)
  const wheel = grp('wheel', [0, hubY, -0.1]);
  const rw = 0.34;
  wheel.add(K.m(tinted(K.tube(ringXY(rw, 24, 0), 0.03, { seg: 32, radial: 6, closed: true }), RED), paint));
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * TAU;
    const pts = [];
    for (let k = 0; k <= 4; k++) { const t = k / 4, aa = a + t * 0.45, r = lerp(0.06, rw - 0.015, t); pts.push([Math.cos(aa) * r, Math.sin(aa) * r, -0.02 * Math.sin(t * Math.PI)]); }
    wheel.add(K.m(tinted(K.tube(pts, 0.017, { seg: 6, radial: 4 }), RED), paint));
  }
  wheel.add(K.m(K.lathe([[0, 0], [0.08, 0], [0.085, 0.03], [0.06, 0.07], [0.03, 0.09], [0, 0.09]], { seg: 12, round: 0.012, steps: 1 }), chrome, { rot: [-Math.PI / 2, 0, 0], pos: [0, 0, 0.04] }));
  wheel.add(K.m(K.cyl(0.02, 0.02, 0.1, { bevel: 0.006, seg: 8 }), chrome, { pos: [rw, 0, 0], rot: [-Math.PI / 2, 0, 0] }));
  const handle = keep(K.m(K.lathe([[0, 0], [0.034, 0.01], [0.04, 0.05], [0.036, 0.1], [0.03, 0.125], [0, 0.13]], { seg: 10, round: 0.012, steps: 1 }), K.glow(game, PAL.marqueeGold, 2.4), { pos: [rw, 0, -0.06], rot: [-Math.PI / 2, 0, 0], name: 'handle', cast: false }));
  handle.userData.noOcclude = true;
  wheel.add(handle);
  wheel.rotation.z = 0.3;
  g.add(wheel);
  // conduit to the dish
  g.add(K.m(tinted(K.tube([[0, 0.9, 0.22], [0.02, 0.6, 0.3], [0.03, 0.05, 0.34], [0.03, 0.015, 0.8]], 0.03, { seg: 14, radial: 6 }), DARK), paint));

  g.userData.parts = { wheel, handle, needle };
  g.userData.rig = { hubY, needleMin: -1.05, needleMax: 1.05 };
  g.userData.colliders = [{ min: [-0.32, 0, -0.28], max: [0.32, 1.45, 0.32] }];
  g.userData.interact = { point: [0, hubY, -0.55], radius: 1.2 };
  finishRig(game, g);
  needle.rotation.z = opts.aligned ? -1.05 : 1.05;
  setCrankGlow(game, g, opts.glow ?? 1);
  return g;
}, { category: 'machines', tags: ['uplink', 'machine', 'yard'], size: [0.76, 1.6, 0.9], desc: 'Uplink alignment crank wheel with a glowing handle + elevation gauge', hero: true });

// ----------------------------------------------------------------------------------------------- booth
// Small uplink control booth: corrugated kiosk with a lit console behind the window and a blinking lamp panel.
// setBoothLamps(g, t) drives parts.lamps (instanced); parts.beacon = roof beacon mesh.
const BOOTH_COLS = ['#FF3B30', '#FFD23A', '#52E04A', '#7FE7FF', '#FF8A2A'];
export function setBoothLamps(g, t = 0) {
  const inst = g.userData.parts.lamps;
  if (!inst) return;
  for (let i = 0; i < inst.count; i++) {
    const ph = Math.sin(i * 12.9898 + 78.233) * 43758.5453;
    const rate = 0.7 + (ph - Math.floor(ph)) * 2.2;
    const on = Math.sin(t * rate * TAU + i * 1.7) > -0.1;
    _cc.set(BOOTH_COLS[i % 5]).multiplyScalar(on ? 1 : 0.12);
    inst.setColorAt(i, _cc);
  }
  inst.instanceColor.needsUpdate = true;
}
registerProp('uplink_booth', (game, opts = {}) => {
  const g = K.prop('uplink_booth');
  const paint = K.mat(game, 'paint', '#ffffff', { rough: 0.5 });
  const atl = K.mat(game, 'paint', '#ffffff', { map: yardAtlas(), rough: 0.5 });
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const glass = game.mats.glass('#BFE6FF', { opacity: 0.18 });
  const CREAM = '#EFE6D0', BLUE = '#3E67C8', RED = '#D93A34', DARK = '#2E2A36';
  const W = 1.5, H = 2.25, D = 1.25;
  // body: corrugated walls (atlas strip, repeated by UV) with a blue skirt
  const corr = K.tex.canvas('booth_corrugated', 128, 128, (ctx, w, h, rand) => {
    for (let x = 0; x < w; x += 16) {
      const gr = ctx.createLinearGradient(x, 0, x + 16, 0);
      gr.addColorStop(0, '#CBBFA6'); gr.addColorStop(0.5, '#F4ECDA'); gr.addColorStop(1, '#CBBFA6');
      ctx.fillStyle = gr; ctx.fillRect(x, 0, 16, h);
    }
    for (let i = 0; i < 40; i++) { ctx.fillStyle = `rgba(120,96,70,${0.04 + rand() * 0.05})`; ctx.fillRect(rand() * w, rand() * h, 1.5, 4 + rand() * 20); }
  });
  const wallMat = K.mat(game, 'paint', '#ffffff', { map: corr, rough: 0.5 });
  g.add(K.m(K.box(W, H - 0.25, D, 0.045, { uv: 0.62 }), wallMat, { pos: [0, 0.12 + (H - 0.25) / 2, 0] }));
  g.add(K.m(tinted(K.box(W + 0.03, 0.26, D + 0.03, 0.04), BLUE), paint, { pos: [0, 0.13, 0] }));
  // roof: overhanging red slab, beacon, whip antenna
  g.add(K.m(tinted(K.box(W + 0.24, 0.1, D + 0.28, 0.045), RED), paint, { pos: [0, H - 0.08, 0.02], rot: [0.05, 0, 0] }));
  g.add(K.m(tinted(K.cyl(0.08, 0.09, 0.06, { bevel: 0.015, seg: 12 }), DARK), paint, { pos: [0.4, H - 0.03, 0.2] }));
  const beacon = keep(K.m(new THREE.SphereGeometry(0.075, 12, 8, 0, TAU, 0, Math.PI / 2), K.glow(game, PAL.onAirRed, 2.6), { pos: [0.4, H + 0.03, 0.2], name: 'beacon', cast: false }));
  beacon.userData.noOcclude = true;
  g.add(beacon);
  g.add(K.m(new THREE.CylinderGeometry(0.006, 0.01, 0.9, 5).translate(0, 0.45, 0), chrome, { pos: [-0.5, H - 0.03, 0.3] }));
  g.add(K.m(new THREE.SphereGeometry(0.02, 6, 4), chrome, { pos: [-0.5, H + 0.88, 0.3] }));
  // sign band
  g.add(K.m(cellUV(K.box(1.2, 0.15, 0.03, 0.012).clone(), 0, 64, 512, 128), atl, { pos: [0, H - 0.26, -D / 2 - 0.02] }));
  // window: chrome frame, glass, lit console inside
  const winY = 1.45, ww = 0.95, wh = 0.5;
  g.add(K.m(K.tube(rrXY(ww, wh, 0.07, 0, 3), 0.02, { seg: 36, radial: 5, closed: true }), chrome, { pos: [0, winY, -D / 2 - 0.012] }));
  g.add(K.m(tinted(new THREE.PlaneGeometry(ww, wh).rotateY(Math.PI), '#10141E'), paint, { pos: [0, winY, -D / 2 + 0.02] }));
  const con = keep(K.m(cellUV(new THREE.PlaneGeometry(ww * 0.86, wh * 0.5).rotateY(Math.PI), 0, 320, 256, 448), K.glow(game, '#ffffff', 1.1, { map: yardAtlas() }), { pos: [0, winY - 0.1, -D / 2 + 0.012], rot: [-0.5, 0, 0], name: 'console', cast: false }));
  g.add(con);
  g.add(K.m(new THREE.PlaneGeometry(ww, wh).rotateY(Math.PI), glass, { pos: [0, winY, -D / 2 - 0.006], cast: false }));
  // exterior lamp panel below the window: plate + instanced jewel lamps + two meters + toggles
  const panelY = 0.88;
  g.add(K.m(tinted(K.box(1.0, 0.44, 0.05, 0.025), '#3A4A66'), paint, { pos: [0, panelY, -D / 2 - 0.02] }));
  const cols = 6, rows = 3;
  const lamps = new THREE.InstancedMesh(new THREE.SphereGeometry(0.026, 7, 3, 0, TAU, 0, Math.PI / 2).rotateX(-Math.PI / 2), K.glow(game, '#ffffff', 2.2), cols * rows);
  const m4 = new THREE.Matrix4();
  for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
    const k = j * cols + i;
    m4.makeTranslation(-0.43 + i * 0.075, panelY + 0.12 - j * 0.075, -D / 2 - 0.046);
    lamps.setMatrixAt(k, m4);
    lamps.setColorAt(k, _cc.set(BOOTH_COLS[k % 5]));
  }
  lamps.name = 'lamps';
  lamps.userData.noMerge = true;
  lamps.castShadow = false;
  g.add(lamps);
  for (const [x, cell] of [[0.16, [128, 192, 256, 320]], [0.35, [256, 192, 384, 320]]]) {
    g.add(K.m(K.tube(ringXY(0.075, 16, 0), 0.01, { seg: 20, radial: 4, closed: true }), chrome, { pos: [x, panelY + 0.05, -D / 2 - 0.05] }));
    g.add(K.m(disc(0.072, 20, cell), atl, { pos: [x, panelY + 0.05, -D / 2 - 0.047] }));
  }
  for (let i = 0; i < 5; i++) g.add(K.m(K.cyl(0.008, 0.01, 0.05, { bevel: 0.003, seg: 6 }), chrome, { pos: [0.08 + i * 0.07, panelY - 0.15, -D / 2 - 0.045], rot: [-Math.PI / 2 - 0.4, 0, 0] }));
  // side door (+x wall) with porthole + handle
  g.add(K.m(tinted(K.box(0.05, 1.7, 0.72, 0.03), '#E4DAC0'), paint, { pos: [W / 2 + 0.01, 0.97, 0.05] }));
  g.add(K.m(K.tube(ringXZ(0.12, 16, 0).map(([x, y, z]) => [0, x, z]), 0.018, { seg: 20, radial: 4, closed: true }), chrome, { pos: [W / 2 + 0.04, 1.45, 0.05] }));
  g.add(K.m(tinted(new THREE.CircleGeometry(0.12, 16).rotateY(Math.PI / 2), '#141A26'), paint, { pos: [W / 2 + 0.037, 1.45, 0.05] }));
  g.add(K.m(chromeHandle(), chrome, { pos: [W / 2 + 0.04, 1.0, -0.22], rot: [0, -Math.PI / 2, 0] }));
  // step + conduit
  g.add(K.m(tinted(K.box(0.3, 0.12, 0.8, 0.03), '#5A5E6E'), paint, { pos: [W / 2 + 0.18, 0.06, 0.05] }));
  g.add(K.m(tinted(K.tube([[-W / 2 + 0.1, 0.4, D / 2], [-W / 2 + 0.1, 0.1, D / 2 + 0.12], [-W / 2 + 0.1, 0.015, D / 2 + 0.5]], 0.035, { seg: 10, radial: 6 }), DARK), paint));

  g.userData.parts = { lamps, beacon, console: con };
  const anchor = { pos: [0, 1.2, -D / 2 - 0.6], color: '#7FE7FF', intensity: 1.2, distance: 4 };
  g.userData.lightAnchors = opts.light === false ? [] : [anchor];
  g.userData.colliders = [{ min: [-W / 2 - 0.02, 0, -D / 2 - 0.08], max: [W / 2 + 0.12, H, D / 2 + 0.02] }];
  finishRig(game, g);
  setBoothLamps(g, opts.t ?? 0.37);
  return g;
}, { category: 'machines', tags: ['uplink', 'yard', 'booth'], size: [1.9, 2.4, 1.6], desc: 'little uplink control booth with blinking lamps', hero: true });

// --------------------------------------------------------------------------------------------- Skylark
// The satellite Skylark-13 (GDD §10.4): chunky gold-foil drum, blue solar wings, downward dish, beacon on top.
// Local -y faces Earth. setSkylarkBeacon(game, g, 'red'|'green'|'flare'|'off').
export function setSkylarkBeacon(game, g, state = 'red') {
  const P = g.userData.parts;
  const c = state === 'green' ? PAL.laughTrack : state === 'flare' ? '#FFFFFF' : PAL.onAirRed;
  P.beacon.material = state === 'off' ? K.mat(game, 'plastic', '#5A2A2A') : K.glow(game, c, state === 'flare' ? 6 : 3);
}
registerProp('skylark_13', (game, opts = {}) => {
  const g = K.prop('skylark_13');
  const paint = K.mat(game, 'plastic', '#ffffff', { keepColor: true });
  const atl = K.mat(game, 'plastic', '#ffffff', { map: yardAtlas(), keepColor: true });
  const foil = K.mat(game, 'brass', '#ffffff', { map: yardAtlas(), keepColor: true, rough: 0.35 });
  const chrome = K.mat(game, 'chrome', '#A8B0BA', { keepColor: true });
  const WHITE = '#F4F1E8';
  const cy = 0.0;
  // body: octagonal gold-foil drum with a white name band, white caps
  const drum = K.lathe([[0, -0.3], [0.3, -0.3], [0.34, -0.22], [0.34, 0.22], [0.3, 0.3], [0, 0.3]], { seg: 8, round: 0.05, steps: 1 }).clone();
  cellUV(drum, 0, 448, 256, 512);
  g.add(K.m(drum, foil, { pos: [0, cy, 0], rot: [0, Math.PI / 8, 0] }));
  const band = K.lathe([[0.352, -0.075], [0.352, 0.075]], { seg: 8 }).clone();
  cellUV(band, 256, 448, 512, 512);
  g.add(K.m(band, atl, { pos: [0, cy, 0], rot: [0, Math.PI / 8, 0] }));
  g.add(K.m(tinted(K.lathe([[0, 0], [0.26, 0], [0.24, 0.06], [0.12, 0.1], [0, 0.1]], { seg: 16, round: 0.03, steps: 1 }), WHITE), paint, { pos: [0, cy + 0.29, 0] }));
  g.add(K.m(tinted(K.lathe([[0, 0], [0.26, 0], [0.24, -0.06], [0.1, -0.09], [0, -0.09]].map(([r, y]) => [r, -y]), { seg: 16, round: 0.03, steps: 1 }), WHITE), paint, { pos: [0, cy - 0.29, 0], rot: [Math.PI, 0, 0] }));
  // solar wings on chrome booms
  const panels = grp('panels', [0, cy, 0]);
  for (const s of [-1, 1]) {
    panels.add(K.m(K.cyl(0.018, 0.018, 0.3, { bevel: 0.005, seg: 8 }), chrome, { pos: [s * 0.32, 0, 0], rot: [0, 0, -s * Math.PI / 2] }));
    panels.add(K.m(tinted(K.box(0.66, 0.035, 0.34, 0.017), '#C9CED6'), paint, { pos: [s * 0.96, 0, 0] }));
    const cells = cellUV(new THREE.PlaneGeometry(0.6, 0.29).rotateX(-Math.PI / 2), 256, 320, 512, 448);
    panels.add(K.m(cells, atl, { pos: [s * 0.96, 0.019, 0] }));
    const under = cellUV(new THREE.PlaneGeometry(0.6, 0.29).rotateX(Math.PI / 2), 256, 320, 512, 448);
    panels.add(K.m(under, atl, { pos: [s * 0.96, -0.019, 0] }));
  }
  g.add(panels);
  // Earth-facing dish + feed, thrusters
  const dishG = K.lathe([[0, 0], [0.12, 0.012], [0.22, 0.05], [0.235, 0.06], [0.225, 0.07], [0.12, 0.03], [0, 0.02]], { seg: 16, round: 0.01, steps: 1 }).clone();
  dishG.rotateX(Math.PI);
  g.add(K.m(tinted(dishG, WHITE), paint, { pos: [0, cy - 0.46, 0] }));
  g.add(K.m(K.cyl(0.03, 0.035, 0.1, { bevel: 0.01, seg: 8 }), chrome, { pos: [0, cy - 0.46, 0] }));
  for (let k = 0; k < 3; k++) g.add(rod([Math.cos(k * 2.1) * 0.18, cy - 0.52, Math.sin(k * 2.1) * 0.18], [0, cy - 0.66, 0], 0.006, chrome, { seg: 5 }));
  g.add(K.m(tinted(new THREE.SphereGeometry(0.025, 8, 6), PAL.channelRed), paint, { pos: [0, cy - 0.67, 0] }));
  for (const [x, z] of [[0.2, 0.2], [-0.2, 0.2], [0.2, -0.2], [-0.2, -0.2]]) g.add(K.m(K.lathe([[0.02, 0], [0.045, -0.07], [0.05, -0.075], [0.03, -0.01]], { seg: 8 }), chrome, { pos: [x, cy - 0.3, z] }));
  // beacon cage + whip antenna on top
  const beacon = keep(K.m(new THREE.SphereGeometry(0.05, 12, 8), K.glow(game, PAL.onAirRed, 3), { pos: [0, cy + 0.46, 0], name: 'beacon', cast: false }));
  beacon.userData.noOcclude = true;
  g.add(beacon);
  for (let k = 0; k < 4; k++) g.add(rod([Math.cos(k * TAU / 4) * 0.06, cy + 0.39, Math.sin(k * TAU / 4) * 0.06], [0, cy + 0.53, 0], 0.005, chrome, { seg: 5 }));
  g.add(K.m(new THREE.CylinderGeometry(0.004, 0.008, 0.55, 5).translate(0, 0.275, 0), chrome, { pos: [0.15, cy + 0.36, 0.1], rot: [0.2, 0, -0.3] }));
  g.add(K.m(new THREE.SphereGeometry(0.015, 6, 4), chrome, { pos: [0.15 + 0.155, cy + 0.36 + 0.505, 0.1 + 0.1] }));

  g.userData.parts = { beacon, panels };
  g.userData.colliders = [];
  g.userData.lightAnchors = [];
  finishRig(game, g, { finish: { ao: { floor: false, height: 0 } } });
  // the prop's floor is y = 0: lift it so it previews above the ground (the game flies it on its own path)
  g.children.forEach((c) => { c.position.y += 0.7; });
  setSkylarkBeacon(game, g, opts.beacon ?? 'red');
  return g;
}, { category: 'machines', tags: ['uplink', 'sky', 'satellite'], size: [2.6, 1.3, 0.6], desc: 'the satellite Skylark-13 (gold drum, solar wings, blinking beacon)' });

// ------------------------------------------------------------------------------------------- hut tubes
// Transmitter-hut window tubes (GDD §2/§13): four big orange-glowing transmitting tubes and the sickly green
// Perpetua-Tube in the middle, on the final-amp chassis (opts.base = false -> just a steel shelf).
registerProp('hut_tubes', (game, opts = {}) => {
  const g = K.prop('hut_tubes');
  const paint = K.mat(game, 'paint', '#ffffff', { rough: 0.5 });
  const atl = K.mat(game, 'paint', '#ffffff', { map: yardAtlas(), rough: 0.5 });
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const ceramic = K.mat(game, 'ceramic', '#ffffff');
  const clearGlass = (c, o) => game.mats.toon(c, { rough: 0.05, transparent: true, opacity: o, rim: 0.28, rimColor: '#FFF4E0', rimPower: 3, env: 0.5, depthWrite: false, side: THREE.DoubleSide, keepColor: true });
  const glassO = clearGlass('#FFC890', 0.14);
  const glassG = clearGlass('#B8FF8A', 0.18);
  const HAMMER = '#6C8474', DARK = '#2E2A36';
  const base = opts.base !== false;
  const topY = base ? 0.95 : 0.06;
  if (base) {
    g.add(K.m(tinted(K.box(1.34, 0.9, 0.48, 0.04), HAMMER), paint, { pos: [0, 0.47, 0] }));
    g.add(K.m(tinted(K.box(1.38, 0.08, 0.5, 0.03), DARK), paint, { pos: [0, 0.04, 0] }));
    g.add(K.m(cellUV(K.box(0.42, 0.1, 0.012, 0.005).clone(), 0, 128, 256, 192), atl, { pos: [-0.36, 0.78, -0.245] }));
    for (const [x, cell] of [[0.08, [128, 192, 256, 320]], [0.3, [256, 192, 384, 320]], [0.52, [0, 192, 128, 320]]]) {
      g.add(K.m(K.tube(ringXY(0.075, 14, 0), 0.011, { seg: 16, radial: 3, closed: true }), chrome, { pos: [x, 0.72, -0.25] }));
      g.add(K.m(disc(0.072, 20, cell), atl, { pos: [x, 0.72, -0.246] }));
    }
    for (let i = 0; i < 4; i++) g.add(K.m(tinted(knobGeo(0.03, 0.035, { seg: 10, flange: 0 }), DARK), paint, { pos: [-0.5 + i * 0.16, 0.52, -0.24] }));
    for (let i = 0; i < 4; i++) g.add(K.m(tinted(new THREE.BoxGeometry(0.9, 0.018, 0.012), '#4E6356'), paint, { pos: [0.08, 0.2 + i * 0.05, -0.243] }));
    g.add(K.m(tinted(K.box(1.3, 0.04, 0.46, 0.015), '#8A9A8E'), paint, { pos: [0, topY - 0.02, 0] }));
  } else {
    g.add(K.m(tinted(K.box(1.3, 0.05, 0.36, 0.015), '#8A9A8E'), paint, { pos: [0, 0.035, 0] }));
  }
  // five tubes: sockets, glass envelopes, anodes, glow cores, top caps
  const xs = [-0.5, -0.25, 0, 0.25, 0.5];
  const glowO = [], glowG = [];
  xs.forEach((x, i) => {
    const green = i === 2;
    const s = green ? 1.22 : 1;
    g.add(K.m(tinted(K.lathe([[0, 0], [0.085, 0], [0.09, 0.02], [0.075, 0.05], [0, 0.05]].map(([r, y]) => [r * s, y]), { seg: 10 }), '#F2EEE4'), ceramic, { pos: [x, topY, 0] }));
    const env = [[0.055, 0], [0.062, 0.04], [0.095, 0.12], [0.1, 0.24], [0.088, 0.36], [0.05, 0.42], [0.03, 0.44], [0, 0.445]].map(([r, y]) => [r * s, y * s]);
    const glassMesh = K.m(K.lathe(env, { seg: 12 }), green ? glassG : glassO, { pos: [x, topY + 0.045, 0], cast: false });
    glassMesh.userData.noOcclude = true;
    g.add(glassMesh);
    g.add(K.m(tinted(K.cyl(0.052 * s, 0.056 * s, 0.22 * s, { bevel: 0.01, seg: 8 }), '#3C3A44'), paint, { pos: [x, topY + 0.09 * s, 0] }));
    g.add(K.m(tinted(new THREE.CylinderGeometry(0.066 * s, 0.066 * s, 0.012, 10, 1, true), '#6A6872'), paint, { pos: [x, topY + 0.305 * s, 0] }));
    const core = K.lathe([[0, 0], [0.058, 0], [0.058, 0.035], [0, 0.035]].map(([r, y]) => [r * s, y * s]), { seg: 10 }).clone();
    core.translate(x, topY + 0.31 * s, 0);
    (green ? glowG : glowO).push(core);
    g.add(K.m(new THREE.CylinderGeometry(0.026 * s, 0.03 * s, 0.035, 8).translate(0, 0.0175, 0), chrome, { pos: [x, topY + 0.045 + 0.435 * s, 0] }));
    g.add(K.m(new THREE.CylinderGeometry(0.004, 0.004, 0.2, 4).translate(0, 0.1, 0), chrome, { pos: [x, topY + 0.045 + 0.47 * s, 0], rot: [0, 0, green ? 0.9 : 1.2] }));
  });
  const glowOrange = keep(new THREE.Mesh(mergeGeos(glowO), K.glow(game, '#FF7A1A', 2.2)));
  glowOrange.name = 'glowOrange';
  glowOrange.userData.noOcclude = true;
  const glowGreen = keep(new THREE.Mesh(mergeGeos(glowG), K.glow(game, PAL.perpetua, 2.8)));
  glowGreen.name = 'glowGreen';
  glowGreen.userData.noOcclude = true;
  g.add(glowOrange, glowGreen);
  // Perpetua tag on a string from the green tube's cap
  const tag = cellUV(new THREE.PlaneGeometry(0.12, 0.16).rotateY(Math.PI), 0, 0, 1, 1, 1, 1);
  const tagMat = K.mat(game, 'plastic', '#ffffff', { map: getCard('perpetua_ad'), side: THREE.DoubleSide });
  g.add(K.m(tag, tagMat, { pos: [0.1, topY + 0.34, -0.14], rot: [0.1, -0.35, 0.12] }));
  g.add(K.m(K.tube([[0.03, topY + 0.6, -0.02], [0.08, topY + 0.5, -0.1], [0.1, topY + 0.42, -0.14]], 0.0025, { seg: 6, radial: 3 }), chrome));
  g.userData.parts = { glowOrange, glowGreen };
  g.userData.lightAnchors = [
    { pos: [-0.3, topY + 0.55, -0.8], color: '#FF9A40', intensity: 1.2, distance: 4, flicker: 0.15 },
    { pos: [0.1, topY + 0.6, -0.8], color: PAL.perpetua, intensity: 1.0, distance: 3.5, flicker: 0.3 },
  ];
  g.userData.colliders = [{ min: [-0.7, 0, -0.26], max: [0.7, topY + 0.6, 0.26] }];
  finishRig(game, g);
  return g;
}, { category: 'machines', tags: ['yard', 'hut', 'tubes', 'perpetua'], size: [1.4, 1.62, 0.52], desc: 'transmitter-hut tube rack: 4 orange tubes + the green Perpetua-Tube', hero: true });

registerScene('uplink_yard', {
  floor: '#4A4652', wall: '#1E2344', room: [14, 12], wallH: 7, hemi: 0.7,
  items: [
    { id: 'uplink_dish', pos: [0, 2.5], rotY: 0, opts: { tilt: 0.3, lit: true } },
    { id: 'uplink_cradle', pos: [0, -0.4], rotY: 0, opts: { lamps: 1 } },
    { id: 'uplink_crank', pos: [2.1, -1.1], rotY: -0.3 },
    { id: 'uplink_booth', pos: [-3.6, 0.2], rotY: Math.PI / 2 + 0.3 },
    { id: 'hut_tubes', pos: [4.2, 1.8], rotY: -0.4 },
    { id: 'skylark_13', pos: [-3.4, 3.2, 0.8], rotY: 0.6 },
  ],
  cam: { pos: [2.2, 2.6, -7.2], target: [0, 1.8, 1.0], fov: 55 },
});
