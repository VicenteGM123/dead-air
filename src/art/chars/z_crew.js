// Z_CREW — "Tuned-In" zombie variant: the WZTV crew member (GDD §8.1, STYLE_GUIDE §7, ref docs/ref/meshy_refs/zombie_crew_vest.png).
// Stocky little guy: navy WZTV vest over a cream shirt with rolled sleeves, rolled jeans with a plaid knee patch, tan
// work boots, walkie-talkie on the belt, red lanyard with an ID card, "13 ADMIT ONE" ticket stub in the vest pocket.
// Exaggerated feature: PEAR HEAD (tiny cranium on a big jowly jaw) + two big buck teeth in an open "O" mouth.
//
// This file also exports the SHARED ZOMBIE HELPERS used by every z_*.js variant (import { ... } from './z_crew.js'):
//   ZOMBIE_MATS            base materials (skin, lid, mouth, teeth, tongue) — spread into def.materials
//   zEye(sd, E)            socket recess + droopy upper lid + plum under-eye (inside sd.bone('head'))
//   zMouth(sd, M)          open "O" mouth: puffy lip ring, dark cavity, big square teeth, optional tongue
//   zHand(sd, o)           big cartoon zombie hand (1.4x), palm facing back (= palm down when the arms reach forward)
//   staticEyes(b, EYES)    attachments: TV-static eye discs + cyan rims (mesh.userData.staticEye = true)
//   ticketStub(b, o)       attachment: the "13 ADMIT ONE" ticket stub (mesh name 'ticketStub')
//   patchDecal(b, o)       attachment: small printed patch / badge (canvas text)
// NOTE for bakes: tools/bake hashes only <id>.js + _*.js, so after editing these helpers rebake the other variants
// with --force.
import { onEllipsoid } from './_sculpt.js';

export const ZSKIN = '#A9C7A4';
export const ZSHADOW = '#7FA08A';
export const ZPLUM = '#7A5C8E';

export const ZOMBIE_MATS = {
  skin: { color: '#A3C99C', rough: 0.48, sss: 0.25, wrap: 0.5, cav: 0.5, spec: 0.7 },
  lid: { color: '#95BC90', rough: 0.48, sss: 0.2, wrap: 0.5, cav: 0.5, spec: 0.7 },
  mouth: { color: '#3B2340', rough: 0.7, spec: 0.3 },
  teeth: { color: '#F4EDD6', rough: 0.3, spec: 0.8, cav: 0.3 },
  tongue: { color: '#B25A78', rough: 0.35, sss: 0.3, spec: 0.8 },
};

// ---------------------------------------------------------------------------------------------------------------
// Eye: E = { x, y, z (disc center = where the disc meets the skin), r, pitch, yaw, lid (0..1 coverage from the
// top), droop (rad, + = outer corner lower), depth (dome height / r) }. Head-local, call inside sd.bone('head').
// The disc itself is an attachment (staticEyes); the sculpt adds a clean recess, a smooth lid and the plum ring.
function eyeFrame(E) {
  return { pos: [E.x, E.y, E.z], rot: [E.pitch || 0, E.yaw || 0, 0] };
}
export function zEyeSocket(sd, E) {
  // recess the dome sits in (flush, clean edge) — call INSIDE the head group
  sd.frame(eyeFrame(E), () => sd.ellipsoid({ op: 'sub', k: 0.006, pos: [0, 0, 0.004], r: [E.r * 1.02, E.r * 1.02, E.r * 0.5] }));
}
export function zEyeLid(sd, E) {
  // upper lid: a shell over the dome, cut by a (drooping) plane — call OUTSIDE the head group, after it
  const side = E.x >= 0 ? 1 : -1;
  const dep = E.depth ?? 0.55;
  const cover = E.lid ?? 0.35;           // 0 = no lid, 1 = closed
  const h = E.r * (1 - 2 * cover);       // lid edge height in the eye frame
  sd.frame(eyeFrame(E), () => {
    sd.group({ mat: 'lid', blend: 0.01, k: 0.006 }, () => {
      sd.ellipsoid({ pos: [0, 0, 0.002], r: [E.r * 1.1, E.r * 1.1, E.r * dep + 0.011] });
      sd.frame({ rot: [0, 0, -side * (E.droop ?? 0.18)] }, () => sd.plane({ op: 'int', k: 0.006, n: [0, -1, 0], d: -h }));
      sd.plane({ op: 'int', k: 0.004, n: [0, 0, 1], d: 0.012 });     // no lid behind the skin
    });
  });
}
export function zEyePaint(sd, E) {
  // plum ring under the eye (skin only; the disc and the lid cover the rest)
  sd.frame(eyeFrame(E), () => sd.paint({ color: ZPLUM, soft: 0.014, strength: 0.8, only: ['skin'] }, () =>
    sd.ellipsoid({ pos: [0, -E.r * 0.28, 0], r: [E.r * 1.3, E.r * 1.26, E.r * 1.2] })));
}

// ---------------------------------------------------------------------------------------------------------------
// Mouth: M = { pos (surface center), pitch (rad, face normal tilt: + = facing down), R, r (lip tube), open [rx, ry],
// teeth: [{ x, y, w, h, lower }], tongue: { len, droop, w } }. Head-local. Lip ring goes INSIDE the head group
// (zMouthLip), cavity + teeth + tongue after the group (zMouthInside).
function mouthFrame(M) { return { pos: M.pos, rot: [-(M.pitch || 0), M.yaw || 0, M.roll || 0] }; }
export function zMouthLip(sd, M) {
  sd.frame(mouthFrame(M), () => {
    if (M.lipPts) sd.worm({ pts: M.lipPts, r: M.r, k: 0.012, segs: 40 });
    else sd.torus({ rot: [Math.PI / 2, 0, 0], R: M.R, r: M.r, k: 0.012 });
    sd.ellipsoid({ op: 'sub', k: 0.004, cutMat: 'mouth', pos: [0, 0, 0.012], r: [M.open[0], M.open[1], 0.04] });
  });
}
export function zMouthInside(sd, M) {
  sd.frame(mouthFrame(M), () => {
    for (const t of M.teeth || []) {
      sd.box({ mat: 'teeth', pos: [t.x, t.y, t.z ?? 0.006], rot: [0, 0, t.rot || 0], size: [t.w, t.h, 0.009], round: Math.min(t.w, t.h) * 0.55, k: 0.004 });
    }
    if (M.tongue) {
      const T = M.tongue;
      sd.worm({ mat: 'tongue', pts: T.pts, r: T.r, flat: T.flat ?? 0.55, up: [0, 1, -0.3], k: 0.006, segs: 18 });
    }
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Big zombie hand, in sd.bone('handL') (mirrored for R): palm faces +z (back) so it faces DOWN when the arm reaches
// forward; thumb on the medial (+x) side. o = { scale, curl }.
export function zHand(sd, o = {}) {
  const s = o.scale ?? 1.4, curl = o.curl ?? 0.35;
  sd.frame({ scale: s, pos: [0, 0.004, 0] }, () => {
    sd.group({ mat: 'skin', k: 0.012, blend: 0.012 }, () => {
      sd.roundCone({ a: [0, 0.014, 0], b: [0, -0.03, 0.001], ra: 0.03, rb: 0.036, k: 0.015 });
      sd.box({ pos: [0, -0.056, 0.002], size: [0.046, 0.046, 0.02], round: 0.018, k: 0.016 });
      const fx = [-0.0366, -0.0122, 0.0122, 0.0366], fl = [0.054, 0.064, 0.062, 0.052];
      for (let i = 0; i < 4; i++) {
        const x = fx[i], l = fl[i], sp = (i - 1.5) * 0.0025;
        sd.worm({ pts: [[x, -0.088, 0.002], [x + sp, -0.088 - l * 0.55, 0.002 + l * 0.12 * curl], [x + sp * 1.6, -0.088 - l, l * 0.42 * curl]], r: [0.0102, 0.0098, 0.0092], k: 0.003, segs: 8 });
      }
      sd.worm({ pts: [[0.03, -0.034, -0.006], [0.052, -0.058, -0.016], [0.058, -0.082, -0.02]], r: [0.015, 0.0132, 0.0118], k: 0.012, segs: 8 });
    });
  });
}

// Molded-toy hair clump: path [[az, el, lift], ...] on the guide ellipsoid E, each point snapped onto the OUTERMOST of
// `nodes` (e.g. [headSkin, hairMass]) so clumps can run from the hair mass onto the forehead. lift: <0 buried.
export function hairClump(sd, nodes, E, path, o = {}) {
  const pts = [], ups = [];
  for (const e of path) {
    const lift = o.xyz ? e[3] : e[2];
    const g = o.xyz ? [e[0], e[1], e[2]] : onEllipsoid(E, e[0], e[1], 0.1);
    // snap onto every node; keep the candidate that lies on the OUTER surface of the union (not buried in another node)
    let best = null, bn = null, bd = Infinity;
    const cand = nodes.map((n) => sd.snap(n, g, lift ?? 0));
    for (const [i, n] of nodes.entries()) {
      const q = cand[i];
      const w = sd.toWorld(q);
      let buried = false;
      for (const m of nodes) if (m !== n && m.fn(w[0], w[1], w[2]) < (lift ?? 0) - 0.002) buried = true;
      const d = Math.hypot(q[0] - g[0], q[1] - g[1], q[2] - g[2]) + (buried ? 1 : 0);
      if (d < bd) { bd = d; best = q; bn = n; }
    }
    pts.push(best);
    ups.push(sd.normalAt(bn, best));
  }
  return sd.worm({ pts, r: o.r, flat: o.flat ?? 0.62, up: ups[0], ups, k: o.k ?? 0.012, segs: o.segs || 16, color2: o.tip, flow: o.flow });
}

// ---------------------------------------------------------------------------------------------------------------
// Attachments (browser only).
// Static grain: about 1/12 of the eye diameter (not per-texel glitter). The dome UVs span STATIC_CELLS texels of the
// game's 128² staticNoise() across the disc (zombieTypes.js swaps the dome material for it); our own preview texture
// (STATIC_N² soft cells, linear filtered, low contrast, horizontal streaks) is repeated to the same grain.
const STATIC_CELLS = 12, STATIC_N = 32, UV_SPAN = STATIC_CELLS / 128;
let _staticTex = null, _veilTex = null;
function staticTexture(THREE) {
  if (_staticTex) return _staticTex;
  const N = STATIC_N;
  const data = new Uint8Array(N * N * 4);
  let s = 0x2545F491;
  for (let i = 0; i < N * N; i++) {
    s ^= s << 13; s ^= s >>> 17; s ^= s << 5;
    const v = 150 + (((s >>> 24) & 0xff) * 100) / 255;       // soft contrast: 150..250
    // TV snow: horizontal streaks (a texel often copies its left neighbour) with a cool bias
    const w = (i % N !== 0 && ((s >>> 8) & 3) < 2) ? data[(i - 1) * 4 + 1] : v;
    data[i * 4] = Math.max(0, w - 14); data[i * 4 + 1] = w; data[i * 4 + 2] = Math.min(255, w + 10); data[i * 4 + 3] = 255;
  }
  const t = new THREE.DataTexture(data, N, N, THREE.RGBAFormat);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearFilter; t.generateMipmaps = false;
  t.repeat.set(STATIC_CELLS / (N * UV_SPAN), STATIC_CELLS / (N * UV_SPAN));
  t.colorSpace = THREE.SRGBColorSpace;
  t.needsUpdate = true;
  t.name = 'zombieStaticEye';
  t.userData.frame = -1;
  _staticTex = t;
  return t;
}
// Veil over the static (NOT tagged staticEye, so it survives the game's material swap): a soft dark centre a bit
// below the middle (the droopy gaze still reads) + an inner cyan glow vignette toward the rim.
function veilTexture(THREE) {
  if (_veilTex) return _veilTex;
  const N = 128, data = new Uint8Array(N * N * 4);
  const ss = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
  const dark = [10, 20, 40], glow = [150, 246, 255];
  for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
    const u = (i + 0.5) / N * 2 - 1, v = (j + 0.5) / N * 2 - 1;
    const dc = Math.hypot(u * 1.05, v + 0.16);               // pupil-ish centre, slightly low (droopy gaze)
    const dr = Math.hypot(u, v);
    const ad = 0.34 + 0.56 * (1 - ss(0.14, 0.52, dc));       // overall dim (soft contrast) + dark centre
    const ag = 0.9 * ss(0.56, 1.0, dr);                       // inner glow vignette toward the rim
    const a = ag + ad * (1 - ag);
    const o = (j * N + i) * 4;
    for (let c = 0; c < 3; c++) data[o + c] = Math.round((glow[c] * ag + dark[c] * ad * (1 - ag)) / Math.max(1e-6, a));
    data[o + 3] = Math.round(Math.min(1, a) * 255);
  }
  const t = new THREE.DataTexture(data, N, N, THREE.RGBAFormat);
  t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearFilter; t.generateMipmaps = false;
  t.colorSpace = THREE.SRGBColorSpace;
  t.needsUpdate = true;
  t.name = 'zombieEyeVeil';
  _veilTex = t;
  return t;
}
function domeGeo(THREE, r, span, du) {
  const g = new THREE.SphereGeometry(r, 32, 12, 0, Math.PI * 2, 0, Math.PI / 2);
  // planar UVs across the disc (no pole pinch)
  const p = g.attributes.position, uv = g.attributes.uv;
  for (let i = 0; i < p.count; i++) uv.setXY(i, 0.5 + p.getX(i) / (2 * r) * span + du, 0.5 + p.getZ(i) / (2 * r) * span);
  return g;
}

// Eye discs filled with animated TV static + dark centre / glow veil + thin cyan rim. The shared texture jumps every
// other frame (offset jitter); the game swaps the dome material for core/textures.js staticNoise() (domes are
// tagged userData.staticEye; the veil and rim keep their materials). Geometries, textures and materials are cached
// at module level: a crowd of zombies shares them. Keep E inside the head silhouette (small yaw, rim inside).
const _cache = new Map();
const cached = (key, make) => { let v = _cache.get(key); if (!v) { v = make(); _cache.set(key, v); } return v; };
export function staticEyes(b, EYES) {
  const THREE = b.THREE;
  const tex = staticTexture(THREE);
  const eyeMat = cached('eyeMat', () => { const m = new THREE.MeshBasicMaterial({ map: tex, color: '#DDF3F8' }); m.name = 'zombieStaticEye'; return m; });
  const veilMat = cached('veilMat', () => { const m = new THREE.MeshBasicMaterial({ map: veilTexture(THREE), transparent: true, depthWrite: false }); m.name = 'zombieEyeVeil'; return m; });
  const rimMat = cached('rimMat', () => { const m = new THREE.MeshBasicMaterial({ color: '#7FE6F2' }); m.name = 'zombieEyeRim'; return m; });
  const head = b.joint('head');
  for (const E of EYES) {
    const g = new THREE.Group();
    g.name = 'staticEyeRoot';
    g.position.set(E.x, E.y, E.z);
    g.rotation.set(E.pitch || 0, E.yaw || 0, 0);
    head.add(g);
    const dome = new THREE.Mesh(cached(`dome${E.r}|${E.x}`, () => domeGeo(THREE, E.r, UV_SPAN, E.x * 7)), eyeMat);
    dome.rotation.x = -Math.PI / 2;             // pole (+y) -> forward (-z)
    dome.scale.set(1, E.depth ?? 0.55, 1);
    dome.name = 'staticEye';
    dome.userData.staticEye = true;
    dome.castShadow = false;
    dome.onBeforeRender = (renderer) => {
      const f = renderer.info.render.frame;
      if (f === tex.userData.frame) return;
      tex.userData.frame = f;
      if ((f & 3) === 0) tex.offset.set(Math.random(), Math.random());
    };
    g.add(dome);
    const veil = new THREE.Mesh(cached(`veil${E.r}`, () => domeGeo(THREE, E.r * 1.012, 1, 0)), veilMat);
    veil.rotation.x = -Math.PI / 2;
    veil.scale.set(1, (E.depth ?? 0.55) * 1.01, 1);
    veil.name = 'staticEyeVeil';
    veil.renderOrder = 2;
    veil.castShadow = false;
    g.add(veil);
    const rim = new THREE.Mesh(cached(`rim${E.r}|${E.rim}`, () => new THREE.TorusGeometry(E.r * 1.0, E.r * (E.rim ?? 0.06), 6, 40)), rimMat);
    rim.name = 'staticEyeRim';
    rim.userData.staticEyeRim = true;
    rim.castShadow = false;
    g.add(rim);
  }
}

function roundRectPath(g, x, y, w, h, r) {
  g.beginPath();
  g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();
}

// Flat printed card with a canvas face (ticket, patch, badge). shape: 'ticket' (notched ends) | 'round' (rounded rect).
function card(b, o, paint, shape, name) {
  const THREE = b.THREE;
  const key = `card|${name}|${o.w}|${o.h}|${o.text || ''}|${o.bg || ''}|${o.band || ''}|${o.edge || ''}`;
  const C = cached(key, () => makeCard(THREE, b, o, paint, shape));
  const m = b.mesh(o.joint || 'chest', C.geo, C.mats, { pos: o.pos, rot: o.rot, name });
  m.rotation.order = 'XYZ';
  return m;
}
function makeCard(THREE, b, o, paint, shape) {
  const W = 512, H = Math.round(512 * o.h / o.w);
  const cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const g = cv.getContext('2d');
  paint(g, W, H);
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  const w = o.w / 2, h = o.h / 2, r = Math.min(w, h) * 0.18;
  const sh = new THREE.Shape();
  if (shape === 'ticket') {
    const n = h * 0.28;
    sh.moveTo(-w + r, -h); sh.lineTo(w - r, -h); sh.quadraticCurveTo(w, -h, w, -h + r);
    sh.lineTo(w, -n); sh.absarc(w, 0, n, -Math.PI / 2, Math.PI / 2, true); sh.lineTo(w, h - r);
    sh.quadraticCurveTo(w, h, w - r, h); sh.lineTo(-w + r, h); sh.quadraticCurveTo(-w, h, -w, h - r);
    sh.lineTo(-w, n); sh.absarc(-w, 0, n, Math.PI / 2, -Math.PI / 2, true); sh.lineTo(-w, -h + r);
    sh.quadraticCurveTo(-w, -h, -w + r, -h);
  } else {
    sh.moveTo(-w + r, -h); sh.lineTo(w - r, -h); sh.quadraticCurveTo(w, -h, w, -h + r); sh.lineTo(w, h - r);
    sh.quadraticCurveTo(w, h, w - r, h); sh.lineTo(-w + r, h); sh.quadraticCurveTo(-w, h, -w, h - r); sh.lineTo(-w, -h + r);
    sh.quadraticCurveTo(-w, -h, -w + r, -h);
  }
  const geo = new THREE.ExtrudeGeometry(sh, { depth: o.t ?? 0.0025, bevelEnabled: false, curveSegments: 10 });
  const p = geo.attributes.position, uv = geo.attributes.uv;
  // u flipped: the printed face is the cap that faces -z (outward from the chest)
  for (let i = 0; i < p.count; i++) uv.setXY(i, (w - p.getX(i)) / (2 * w), (p.getY(i) + h) / (2 * h));
  geo.translate(0, 0, -(o.t ?? 0.0025));
  const face = b.mat({ map: tex, rough: 0.75, rim: 0.15, rimColor: '#8FF3FF', wrap: 0.5 });
  const edge = b.mat({ color: o.edge || '#E9D9B4', rough: 0.8, rim: 0.1 });
  return { geo, mats: [face, edge] };
}

export function ticketStub(b, o) {
  return card(b, { w: 0.084, h: 0.046, ...o }, (g, W, H) => {
    g.fillStyle = '#F6E7C8'; g.fillRect(0, 0, W, H);
    g.strokeStyle = '#E23B3B'; g.lineWidth = W * 0.022;
    roundRectPath(g, W * 0.085, H * 0.12, W * 0.83, H * 0.76, H * 0.1); g.stroke();
    // perforation line
    g.fillStyle = '#C9B48E';
    for (let y = H * 0.18; y < H * 0.84; y += H * 0.1) { g.beginPath(); g.arc(W * 0.34, y, W * 0.009, 0, Math.PI * 2); g.fill(); }
    g.fillStyle = '#E23B3B';
    g.font = `900 ${Math.round(H * 0.52)}px "Arial Black", Impact, sans-serif`;
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText('13', W * 0.215, H * 0.53);
    g.fillStyle = '#2B2238';
    g.font = `900 ${Math.round(H * 0.25)}px "Arial Black", Impact, sans-serif`;
    g.fillText('ADMIT', W * 0.63, H * 0.37);
    g.fillText('ONE', W * 0.63, H * 0.67);
  }, 'ticket', 'ticketStub');
}

export function patchDecal(b, o) {
  return card(b, { w: 0.07, h: 0.034, edge: o.edgeColor || '#F4F1E8', ...o }, (g, W, H) => {
    g.fillStyle = o.bg || '#F4F1E8'; g.fillRect(0, 0, W, H);
    g.fillStyle = o.band || '#2F5BD3';
    roundRectPath(g, W * 0.05, H * 0.1, W * 0.9, H * 0.8, H * 0.18); g.fill();
    g.fillStyle = '#F4F1E8';
    g.font = `900 ${Math.round(H * 0.5)}px "Arial Black", Impact, sans-serif`;
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(o.text || 'WZTV', W * 0.5, H * 0.47);
    g.fillStyle = '#E23B3B'; g.fillRect(W * 0.16, H * 0.74, W * 0.68, H * 0.07);
  }, 'round', o.name || 'patch');
}

// ===============================================================================================================
// Z_CREW definition
const HAIR = '#4A3428';
// Head-local anchors (origin = head joint = top of the neck; y up, -z forward). Eyes kept inside the head silhouette
// (moderate yaw) with a droopy upper lid covering >= 1/3 of each disc.
const EYES = [
  { x: 0.088, y: 0.3, z: -0.151, r: 0.066, pitch: 0.12, yaw: -0.3, lid: 0.36, droop: 0.2, depth: 0.7 },
  { x: -0.082, y: 0.296, z: -0.153, r: 0.054, pitch: 0.1, yaw: 0.28, lid: 0.42, droop: 0.14, depth: 0.7 },
];
const MOUTH = {
  pos: [0, 0.094, -0.174], pitch: 0.48, R: 0.05, r: 0.0155, open: [0.037, 0.036],
  teeth: [
    { x: -0.0158, y: 0.02, w: 0.0138, h: 0.0175, rot: 0.06 },
    { x: 0.0152, y: 0.02, w: 0.0138, h: 0.0175, rot: -0.05 },
    { x: 0.021, y: -0.026, w: 0.01, h: 0.011, rot: 0.12 },
  ],
  tongue: { pts: [[-0.016, -0.024, 0.016], [0.0, -0.021, 0.008], [0.014, -0.025, 0.014]], r: 0.014, flat: 0.5 },
};

const HM = { c: [0, 0.345, 0.014], r: [0.174, 0.207, 0.184] }; // hair guide ellipsoid (just above the cranium)
// PEAR HEAD: tiny cranium on a big jowly jaw (also the base of the molded hair shell)
function headShapes(sd) {
  sd.group({ k: 0.09 }, () => {
    sd.ellipsoid({ pos: [0, 0.175, -0.006], r: [0.22, 0.18, 0.19] });   // big jowly jaw
    sd.ellipsoid({ pos: [0, 0.345, 0.014], r: [0.162, 0.195, 0.172] }); // small cranium
  });
}

function crewTorso(sd) {
  sd.ellipsoid({ pos: [0, 0.79, 0.005], r: [0.196, 0.13, 0.136] });
  sd.ellipsoid({ pos: [0, 0.662, -0.014], r: [0.186, 0.13, 0.142] });
  sd.ellipsoid({ pos: [0, 0.866, 0.012], r: [0.204, 0.062, 0.116] });
}

export default {
  id: 'z_crew',
  name: 'Tuned-In: WZTV Crew',
  kind: 'zombie',
  rig: { height: 1.56, headScale: 1.34, shoulderW: 0.44, hipW: 0.28, legLen: 0.7, torsoLen: 0.5 },
  bake: { voxel: 0.0046, tris: 9400, aoStrength: 0.9, aoReach: 0.1 },
  armOut: 0.1,
  // hunch: spine + chest + neck ~18 deg forward on top of the zombie lean, head pushed forward (chin up to keep the
  // face readable), arms at different heights (left reaching higher, right drooping).
  poseOffset: {
    spine: [-0.16, 0, 0.02], chest: [-0.14, 0.05, 0], neck: [-0.14, 0, 0], head: [0.36, 0.06, 0.09],
    shoulderL: [0.2, 0, 0.02], shoulderR: [-0.2, 0, -0.04], elbowL: [0.12, 0, 0], elbowR: [0.1, 0, 0],
    handL: [-0.45, 0, 0], handR: [-0.3, 0, 0.12],
  },
  rim: { color: '#8FF3FF', strength: 0.3 },
  materials: {
    ...ZOMBIE_MATS,
    hair: { color: HAIR, rough: 0.4, sheen: 1, sheenExp: 70, spec: 0.35, wrap: 0.5, cav: 0.5 },
    shirt: { color: '#E8D3AA', rough: 0.75, fuzz: 0.3, wrap: 0.55, lines: true },
    vest: { color: '#2A3D7C', rough: 0.72, fuzz: 0.35, wrap: 0.5, lines: true },
    denim: { color: '#ffffff', rough: 0.85, fuzz: 0.4, lines: true, bump: 0.2, pattern: { type: 'denim', color: '#3E5DA6', scale: 0.05 } },
    cuff: { color: '#ffffff', rough: 0.85, fuzz: 0.4, lines: true, pattern: { type: 'denim', color: '#6A88C8', scale: 0.05 } },
    patch: { color: '#ffffff', rough: 0.8, fuzz: 0.4, lines: true,
      pattern: { type: 'plaid', base: '#D9432E', bands: [['#F6E7C8', 0.12, 0.25, 0.9], ['#7A2418', 0.18, 0.7, 0.8]], scale: 0.05 } },
    leather: { color: '#5A3A26', rough: 0.45, spec: 0.5 },
    buckle: { color: '#D9CFB8', metal: 1, rough: 0.28 },
    boot: { color: '#B9793C', rough: 0.45, spec: 0.55, lines: true },
    sole: { color: '#3B2A20', rough: 0.65 },
    walkie: { color: '#2C2C35', rough: 0.35, spec: 0.8 },
    lanyard: { color: '#E23B3B', rough: 0.6, fuzz: 0.2 },
    badge: { color: '#F4F1E8', rough: 0.4, spec: 0.6 },
  },
  anchors: () => ({ EYES, MOUTH }),

  sculpt(sd) {
    // ---------------- torso: shirt, vest, collar ----------------
    const shirtNode = sd.group({ name: 'shirt', mat: 'shirt', bone: 'torso', k: 0.05 }, () => crewTorso(sd));
    // neck (short, mostly hidden by the big head)
    sd.capsule({ mat: 'skin', bone: 'torso', a: [0, 0.87, 0.012], b: [0, 1.0, 0.0], r: 0.066, k: 0.02 });
    // collar: soft roll band
    sd.group({ name: 'collar', mat: 'shirt', bone: 'torso', blend: 0.012, k: 0.02 }, () => {
      sd.torus({ pos: [0, 0.918, 0.014], rot: [0.1, 0, 0], R: 0.074, r: 0.02 });
    });
    const vest = sd.group({ name: 'vest', mat: 'vest', bone: 'torso', blend: 0.006, k: 0.02 }, () => {
      sd.group({ offset: 0.013, k: 0.05 }, () => crewTorso(sd));
      // open front (narrow at the belly, wide at the chest)
      sd.roundCone({ op: 'sub', k: 0.012, a: [0, 0.6, -0.166], b: [0, 0.95, -0.15], ra: 0.03, rb: 0.095 });
      // armholes (small: the vest covers the top of the shoulder, no sleeve "ball" pokes out), neck, hem
      sd.mirrorX(() => sd.ellipsoid({ op: 'sub', k: 0.015, pos: [0.232, 0.83, 0.012], r: [0.062, 0.078, 0.082] }));
      sd.capsule({ op: 'sub', k: 0.02, a: [0, 0.9, 0.02], b: [0, 1.1, 0.02], r: 0.098 });
      sd.plane({ op: 'int', k: 0.008, n: [0, -1, 0], d: -0.606 });
      // scalloped hem: clean rounded bites torn out of the front panels and the back
      for (const [x, y, z, r] of [[-0.145, 0.6, -0.11, 0.04], [-0.07, 0.598, -0.152, 0.03], [0.118, 0.6, -0.132, 0.036],
        [0.06, 0.6, 0.15, 0.04], [-0.1, 0.6, 0.13, 0.03]]) sd.sphere({ op: 'sub', k: 0.006, pos: [x, y, z], r });
      // round hole in the back panel (shirt shows through)
      sd.sphere({ op: 'sub', k: 0.005, pos: [0.075, 0.76, 0.165], r: 0.032 });
    });
    // vest pockets (stitched outlines) + edge piping stitches
    sd.mirrorX(() => {
      sd.stitch([[0.07, 0.8, -0.2], [0.07, 0.74, -0.2], [0.142, 0.74, -0.2], [0.142, 0.8, -0.2]], { mats: ['vest'], color: '#9DB0E8', smooth: false });
      sd.stitch([[0.068, 0.802, -0.2], [0.144, 0.802, -0.2]], { mats: ['vest'], color: '#9DB0E8', smooth: false });
    });
    // lanyard (red cord from behind the collar to an ID card on the belly)
    sd.mirrorX(() => {
      const pts = sd.snapAll(shirtNode, [[0.062, 0.915, -0.04], [0.058, 0.87, -0.13], [0.036, 0.8, -0.16], [0.012, 0.745, -0.16]], 0.009);
      sd.worm({ mat: 'lanyard', bone: 'torso', pts, r: 0.0072, flat: 0.75, up: [0, 0, -1], k: 0.006, segs: 12 });
    });
    const cardC = sd.snap(shirtNode, [0, 0.71, -0.2], 0.012);
    sd.group({ name: 'idcard', mat: 'badge', bone: 'chest', rigid: true, blend: 0.004 }, () => {
      sd.box({ pos: cardC, rot: [0.28, 0, 0.06], size: [0.03, 0.038, 0.0055], round: 0.005 });
      sd.box({ pos: [cardC[0], cardC[1] + 0.03, cardC[2] - 0.004], rot: [0.28, 0, 0.06], size: [0.008, 0.012, 0.006], round: 0.004, mat: 'buckle', k: 0.003 });
    });
    sd.paint({ color: '#2F5BD3', soft: 0.002, only: ['badge'] }, () => sd.box({ pos: [cardC[0], cardC[1] + 0.017, cardC[2]], rot: [0.28, 0, 0.06], size: [0.034, 0.011, 0.03], round: 0.002 }));
    sd.paint({ color: '#E23B3B', soft: 0.002, only: ['badge'] }, () => sd.box({ pos: [cardC[0], cardC[1] - 0.02, cardC[2]], rot: [0.28, 0, 0.06], size: [0.034, 0.004, 0.03], round: 0.001 }));

    // ---------------- head ----------------
    sd.bone('head', () => {
      const head = sd.group({ name: 'head', mat: 'skin', k: 0.02, blend: 0.03 }, () => {
        headShapes(sd);
        // bulbous nose
        sd.sphere({ pos: [0, 0.218, -0.2], r: 0.047, k: 0.022 });
        // ears (one a bit floppier)
        sd.mirrorX((m) => {
          sd.ellipsoid({ pos: [0.214, 0.235, 0.03], rot: [0, -0.35, m ? -0.28 : 0.12], r: [0.026, 0.052, 0.036], k: 0.014 });
          sd.ellipsoid({ op: 'sub', k: 0.008, pos: [0.233, 0.235, 0.024], rot: [0, -0.35, m ? -0.28 : 0.12], r: [0.012, 0.032, 0.02] });
        });
        for (const E of EYES) zEyeSocket(sd, E);
        zMouthLip(sd, MOUTH);
      });
      for (const E of EYES) zEyeLid(sd, E);
      zMouthInside(sd, MOUTH);
      for (const E of EYES) zEyePaint(sd, E);
      sd.paint({ color: '#8DB58A', soft: 0.02, strength: 0.6, only: ['skin'] }, () => sd.sphere({ pos: [0, 0.218, -0.21], r: 0.04 }));
      sd.paint({ color: ZSHADOW, soft: 0.03, strength: 0.35, only: ['skin'] }, () => sd.ellipsoid({ pos: [0, 0.03, -0.03], r: [0.2, 0.06, 0.2] }));

      // ---- hair: a SOLID molded-toy piece that follows the pear (the head shapes inflated): from the back it is one
      //      clean pear of hair down to a low nape edge (no cap sitting on a bulb = no acorn, no crown curl); rounded
      //      hairline, ears clear, a soft side part and a fringe of 4 WIDE, SHORT rounded tufts overlapping each other,
      //      all swept to his right (tips down-right). Flow = constant sideways sweep: its singular points fall on the
      //      jaw sides (skin) -> no whorl highlight in the hair.
      sd.group({ name: 'hair', mat: 'hair', flow: [1, 0, 0.25] }, () => {
        sd.group({ name: 'hairmass', k: 0.05 }, () => {
          sd.group({ offset: 0.022, k: 0.09 }, () => headShapes(sd));
          sd.ellipsoid({ pos: [0, 0.3, 0.16], r: [0.07, 0.12, 0.06], k: 0.04 });                              // nape taper
          sd.ellipsoid({ op: 'sub', k: 0.02, pos: [0, 0.19, -0.23], r: [0.26, 0.2, 0.2] });                   // face opening
          // swept fringe: narrow notches cut up-left into the hairline -> wide, short rounded tufts pointing down-right
          for (const [x, y, l] of [[-0.052, 0.4, 0.03], [0.018, 0.4, 0.034], [0.086, 0.388, 0.032]]) {
            sd.ellipsoid({ op: 'sub', k: 0.012, pos: [x, y, -0.2], rot: [0, 0, 0.72], r: [0.0125, l, 0.12] });
          }
          sd.mirrorX(() => sd.ellipsoid({ op: 'sub', k: 0.03, pos: [0.245, 0.215, 0.01], r: [0.08, 0.1, 0.12] })); // ears clear
          sd.plane({ op: 'int', k: 0.03, n: [0, -0.707, -0.707], d: -0.198 });                                 // nape (low at the back)
          sd.capsule({ op: 'sub', k: 0.022, a: [-0.07, 0.6, -0.16], b: [-0.075, 0.6, 0.06], r: 0.005 });       // soft side part
        });
      });
    });

    // ---------------- belt + pants ----------------
    sd.group({ name: 'pelvis', mat: 'denim', bone: 'torso', k: 0.03 }, () => {
      sd.ellipsoid({ pos: [0, 0.55, 0.0], r: [0.176, 0.104, 0.132] });
    });
    sd.group({ name: 'belt', mat: 'leather', bone: 'torso' }, () => {
      sd.ellipsoid({ pos: [0, 0.572, -0.003], r: [0.17, 0.112, 0.133], offset: 0.007 });
      sd.box({ op: 'int', k: 0.003, pos: [0, 0.572, 0], size: [0.3, 0.02, 0.3], round: 0.002 });
    });
    sd.group({ name: 'buckle', mat: 'buckle', bone: 'hips', rigid: true, k: 0.003 }, () => {
      sd.box({ pos: [0, 0.572, -0.142], size: [0.03, 0.024, 0.008], round: 0.007 });
      sd.box({ op: 'sub', k: 0.002, pos: [0, 0.572, -0.151], size: [0.019, 0.013, 0.006], round: 0.004 });
    });
    // walkie-talkie on the left hip
    sd.group({ name: 'walkie', mat: 'walkie', bone: 'hips', rigid: true, blend: 0.004, k: 0.006 }, () => {
      sd.frame({ pos: [-0.2, 0.53, -0.02], rot: [0.04, -1.37, 0.05] }, () => {
        sd.box({ pos: [0, 0, 0], size: [0.036, 0.064, 0.024], round: 0.014 });
        sd.capsule({ a: [0.016, 0.055, 0.004], b: [0.018, 0.14, 0.004], r: 0.009, k: 0.004 });
        sd.sphere({ pos: [0.018, 0.143, 0.004], r: 0.013, k: 0.003, mat: 'lanyard' });
        sd.box({ pos: [-0.013, 0.068, 0.002], size: [0.008, 0.01, 0.008], round: 0.005, mat: 'buckle' });
      });
    });
    sd.paint({ color: '#F2C63A', soft: 0.002, only: ['walkie'] }, () => sd.frame({ pos: [-0.2, 0.53, -0.02], rot: [0.04, -1.37, 0.05] }, () =>
      sd.box({ pos: [0, 0.026, -0.024], size: [0.024, 0.01, 0.02], round: 0.004 })));
    sd.mirrorX((m) => {
      sd.bone('hipL', () => {
        const fr = sd.patternFrame({ pos: [0, -0.2, 0], mode: 'cyl', radius: 0.085 });
        sd.group({ mat: 'denim', k: 0.035, blend: 0.035, pframe: fr }, () => {
          sd.roundCone({ a: [0.035, -0.03, 0.004], b: [0, -0.235, 0], ra: 0.098, rb: 0.088 });
          sd.roundCone({ a: [0, -0.235, 0], b: [0, -0.385, 0.008], ra: 0.088, rb: 0.08 });
          if (!m) sd.ellipsoid({ op: 'sub', k: 0.006, cutMat: 'skin', pos: [0.012, -0.12, -0.112], rot: [0, 0, 0.3], r: [0.046, 0.036, 0.04] });   // big rounded tear (left thigh)
        });
        // rolled cuff
        sd.group({ mat: 'cuff', blend: 0.004, k: 0.01, pframe: fr }, () => {
          sd.torus({ pos: [0, -0.405, 0.008], R: 0.078, r: 0.023 });
          sd.cylinder({ pos: [0, -0.405, 0.008], r: 0.087, h: 0.019, round: 0.012 });
        });
        sd.stitch(Array.from({ length: 25 }, (_, i) => { const a = (i / 24) * Math.PI * 2; return [Math.sin(a) * 0.11, -0.386, 0.008 + Math.cos(a) * 0.11]; }), { mats: ['cuff'], smooth: false });
        sd.stitch([[-0.11, 0.03, 0], [-0.096, -0.2, 0], [-0.084, -0.38, 0.008]], { mats: ['denim'] });
        if (m) {
          // plaid knee patch with stitched border (right knee)
          const kf = sd.patternFrame({ pos: [0, -0.23, -0.08], mode: 'tri' });
          sd.paint({ mat: 'patch', soft: 0.001, only: ['denim'], pframe: kf }, () =>
            sd.box({ pos: [0.006, -0.235, -0.08], rot: [0, 0, 0.18], size: [0.05, 0.05, 0.04], round: 0.018 }));
          const sq = [];
          for (let i = 0; i <= 32; i++) {
            const a = (i / 32) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
            const e = 0.041 / Math.pow(Math.pow(Math.abs(c), 4) + Math.pow(Math.abs(s), 4), 0.25);
            const x = c * e, y = s * e, rr = 0.18;
            sq.push([0.006 + x * Math.cos(rr) - y * Math.sin(rr), -0.235 + x * Math.sin(rr) + y * Math.cos(rr), -0.12]);
          }
          sd.stitch(sq, { mats: ['patch', 'denim'], color: '#F6E7C8', smooth: false });
        }
      });
      sd.bone('footL', () => {
        const upper = () => {
          sd.cylinder({ pos: [0, 0.02, 0.008], r: 0.07, h: 0.07, round: 0.03 });
          sd.ellipsoid({ pos: [0, -0.026, -0.07], r: [0.07, 0.048, 0.13] });
          sd.sphere({ pos: [0, -0.024, -0.15], r: 0.058 });
        };
        sd.group({ mat: 'boot', k: 0.035 }, upper);
        sd.group({ mat: 'sole', blend: 0.0 }, () => {
          sd.group({ offset: 0.008, k: 0.035 }, upper);
          sd.box({ op: 'int', k: 0.003, pos: [0, -0.061, -0.06], size: [0.12, 0.011, 0.26], round: 0.003 });
        });
        // boot laces / tongue seam
        sd.stitch([[0, 0.06, -0.075], [0, 0.02, -0.09], [0, -0.005, -0.13]], { mats: ['boot'], color: '#F2E3C4', width: 0.004, dash: 0.012, duty: 0.55 });
        sd.stitch([[-0.07, -0.045, -0.2], [-0.07, -0.045, 0.06]], { mats: ['boot'], color: '#7A4A22' });
      });
    });

    // jeans back pockets + yoke seam
    sd.mirrorX(() => sd.stitch([[0.04, 0.53, 0.2], [0.04, 0.47, 0.2], [0.075, 0.45, 0.2], [0.11, 0.47, 0.2], [0.11, 0.53, 0.2]], { mats: ['denim'], smooth: false }));
    sd.stitch([[-0.16, 0.545, 0.2], [0, 0.525, 0.2], [0.16, 0.545, 0.2]], { mats: ['denim'] });

    // ---------------- arms ----------------
    // Sleeves are straight tapered tubes that grow out of the torso (blend, no shoulder ball). Left: neat flat roll at
    // mid-upper-arm. Right: torn short sleeve with a scalloped hem and a round hole.
    sd.mirrorX((m) => {
      sd.bone('shoulderL', () => {
        sd.group({ mat: 'shirt', k: 0.03, blend: 0.02 }, () => {
          sd.roundCone({ a: [0.02, 0.012, 0], b: [0, -0.125, 0], ra: 0.058, rb: 0.058 });
          sd.plane({ op: 'int', k: 0.006, n: [0, -1, 0], d: 0.14 });   // sleeve hem
          if (m) {
            for (const [x, z, r] of [[-0.05, -0.03, 0.024], [-0.02, 0.05, 0.022]]) sd.sphere({ op: 'sub', k: 0.005, pos: [x, -0.142, z], r });
            sd.sphere({ op: 'sub', k: 0.005, cutMat: 'skin', pos: [-0.052, -0.07, -0.03], r: 0.026 });
          }
        });
        if (!m) {
          sd.group({ mat: 'shirt', blend: 0.004, k: 0.008 }, () => {
            sd.cylinder({ pos: [0, -0.118, 0], r: 0.064, h: 0.014, round: 0.009 });
          });
        }
        sd.roundCone({ mat: 'skin', a: [0, -0.1, 0], b: [0, -0.225, 0], ra: 0.05, rb: 0.048, k: 0.01 });
      });
      sd.bone('elbowL', () => {
        sd.roundCone({ mat: 'skin', a: [0, 0.01, 0], b: [0, -0.215, 0], ra: 0.049, rb: 0.043, k: 0.02 });
      });
      sd.bone('handL', () => zHand(sd, { scale: 1.42, curl: 0.4 }));
    });
  },

  attachments(b) {
    staticEyes(b, EYES);
    // chest joint is at y 0.746 (bind pose = rest for the torso, so chest-local = world - [0, 0.746, 0])
    ticketStub(b, { joint: 'chest', pos: [0.097, 0.056, -0.147], rot: [0.05, -0.3, 0.22], w: 0.1, h: 0.055 });
    patchDecal(b, { joint: 'chest', pos: [-0.108, 0.07, -0.143], rot: [0.04, 0.36, -0.03], text: 'WZTV', w: 0.08, h: 0.038 });
  },
};
