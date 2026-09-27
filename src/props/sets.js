// DEAD AIR — props: STUDIO SETS & EASTER-EGG OBJECTS (docs/PROPKIT.md, GDD §5.7 / §13).
// Owner: sets prop artist. Shoot: node tools/propview/shoot.cjs category:sets
//
//   Studio A   marquee_arch · pledge_wheel · baron_throne · contestant_podium · ghost_light · pledge_carousel
//              tote_board_tower · bleacher_block · disco_ball · applause_sign · chroma_cyc
//   Studio B   cardboard_rocket · treehouse_facade · puppet_theater · alphabet_block · rainbow_arch · giant_crayon
//              giant_crayons · toy_train_loop · xylophone
//   EE         chime_rack · trophy_case · neon_logo_partition · letter_board · weather_map · rundown_board
//              kill_switch_cage · perpetua_crate · dressing_room_door
//
// STATUS (keep updated): all 29 ids built and reviewed (3 rounds, budgets met: typical <= 3k, hero <= 12k). Shots: _shots/props/sets/ (cat_sets.png, singles,
// scene_sets_*.png). Isolated shooting pipeline used by the artist lives in the session scratchpad (sets_pv/); the
// kit tool works too: node tools/propview/shoot.cjs category:sets. Scenes: sets_studio_a, sets_studio_b, sets_ee.
//
// Runtime helpers (exported; call them on the placed prop group): marqueeChase, setGhostLight, setToteValue,
// setToteGlow, setPodiumScore, ringPhone, setNeon, setApplause, setRundownCard, showMagnet. Every prop keeps
// its animatable pieces in userData.parts (see each builder's header comment) and extra JSON anchors in
// userData.anchors (local [x,y,z]).

import * as K from './kit.js';
import { registerProp, registerScene, PAL, THREE } from './kit.js';
import { getCard } from '../gfx/cards.js';
import { mulberry32 } from '../core/rng.js';
import * as BGU from 'three/addons/utils/BufferGeometryUtils.js';
import { woodPanel } from '../core/textures.js';

const TAU = Math.PI * 2;
const { lerp, clamp } = THREE.MathUtils;
const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
const UP = V3(0, 1, 0);
const CAT = 'sets';

// --------------------------------------------------------------------------------------------- local helpers
const FONT = {
  sign: '"Bungee", Impact, "Arial Black", sans-serif',
  round: '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif',
  groovy: '"Shrikhand", "Cooper Black", Georgia, serif',
  osd: '"VT323", "Courier New", monospace',
  hand: '"Titan One", "Comic Sans MS", sans-serif',
};

// tinted copy of a (cached) kit geometry: lets one white material carry many colors (fewer draw calls)
function tg(geo, color) { return K.tint(geo.clone(), color); }
// mesh from a tinted geometry
function tm(geo, mat, color, o) { return K.m(color ? tg(geo, color) : geo, mat, o); }

// canvas texture (non repeating, redrawn when fonts load)
function cv(key, w, h, draw, repeat = false) { return K.tex.canvas(`sets.${key}`, w, h, draw, { repeat, fonts: true }); }

function rrect(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
function text(ctx, s, x, y, o = {}) {
  const { font = FONT.sign, size = 40, fill = '#fff', stroke = null, lw = 0, align = 'center', base = 'middle', maxW = 0,
    shadow = null, rot = 0, track = 0 } = o;
  ctx.save();
  ctx.translate(x, y);
  if (rot) ctx.rotate(rot);
  let px = size;
  ctx.font = `${px}px ${font}`;
  if (track) ctx.letterSpacing = `${track}px`;
  if (maxW) while (ctx.measureText(s).width > maxW && px > 6) { px *= 0.94; ctx.font = `${px}px ${font}`; }
  ctx.textAlign = align; ctx.textBaseline = base;
  ctx.lineJoin = 'round';
  if (shadow) { ctx.fillStyle = shadow; ctx.fillText(s, px * 0.05, px * 0.07); if (stroke) { ctx.lineWidth = lw; ctx.strokeStyle = shadow; ctx.strokeText(s, px * 0.05, px * 0.07); } }
  if (stroke) { ctx.lineWidth = lw; ctx.strokeStyle = stroke; ctx.strokeText(s, 0, 0); }
  ctx.fillStyle = fill; ctx.fillText(s, 0, 0);
  ctx.restore();
}
function starPts(cx, cy, ro, ri, n = 5, a0 = -Math.PI / 2) {
  const p = [];
  for (let i = 0; i < n * 2; i++) { const a = a0 + (i / (n * 2)) * TAU, r = i % 2 ? ri : ro; p.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); }
  return p;
}
function poly(ctx, pts) { ctx.beginPath(); pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y))); ctx.closePath(); }
function grad(ctx, x0, y0, x1, y1, stops) {
  const g = ctx.createLinearGradient(x0, y0, x1, y1);
  stops.forEach((c, i) => (Array.isArray(c) ? g.addColorStop(c[0], c[1]) : g.addColorStop(i / Math.max(1, stops.length - 1), c)));
  return g;
}
function speckle(ctx, w, h, rand, n = 400, a = 0.06) {
  for (let i = 0; i < n; i++) {
    ctx.fillStyle = rand() < 0.5 ? `rgba(255,255,255,${a})` : `rgba(40,20,40,${a})`;
    ctx.fillRect(rand() * w, rand() * h, 1 + rand() * 2, 1 + rand() * 2);
  }
}
function shadeHex(hex, amt) {
  const c = new THREE.Color(hex);
  if (amt >= 0) c.lerp(new THREE.Color(1, 1, 1), amt); else c.multiplyScalar(1 + amt);
  return '#' + c.getHexString();
}

// flat decal facing -Z (prop front) or +Z (back=true)
function decalGeo(w, h, uvr = null, back = false) {
  const g = new THREE.PlaneGeometry(w, h);
  if (!back) g.rotateY(Math.PI);
  if (uvr) K.uvRect(g, ...uvr);
  return g;
}

// mesh aligned from a to b; geo built along +Y with base at 0 and unit-less length l (use K.cyl(r, r, l))
function between(geo, mat, a, b) {
  const A = Array.isArray(a) ? V3(...a) : a, B = Array.isArray(b) ? V3(...b) : b;
  const m = K.m(geo, mat);
  m.position.copy(A);
  m.quaternion.setFromUnitVectors(UP, B.clone().sub(A).normalize());
  return m;
}
function rodGeo(r, a, b, seg = 8, bevel = 0.003) {
  const A = Array.isArray(a) ? V3(...a) : a, B = Array.isArray(b) ? V3(...b) : b;
  return K.cyl(r, r, A.distanceTo(B), { seg, bevel: Math.min(bevel, r * 0.5) });
}
function rod(r, mat, a, b, seg = 8) { return between(rodGeo(r, a, b, seg), mat, a, b); }

function ringPts(r, n, y = 0, a0 = 0) {
  const p = [];
  for (let i = 0; i < n; i++) { const a = a0 + (i / n) * TAU; p.push([Math.cos(a) * r, y, Math.sin(a) * r]); }
  return p;
}

// InstancedMesh from transforms [{pos, rot:[x,y,z], scale:number|[x,y,z]}] with optional per-instance colors
function instanced(geo, mat, xf, colors = null, name = '') {
  const im = new THREE.InstancedMesh(geo, mat, xf.length);
  const o = new THREE.Object3D();
  xf.forEach((t, i) => {
    o.position.fromArray(t.pos);
    if (t.quat) o.quaternion.copy(t.quat); else o.rotation.set(...(t.rot || [0, 0, 0]));
    const s = t.scale ?? 1;
    if (typeof s === 'number') o.scale.setScalar(s); else o.scale.set(...s);
    o.updateMatrix();
    im.setMatrixAt(i, o.matrix);
  });
  if (colors) colors.forEach((c, i) => im.setColorAt(i, c.isColor ? c : new THREE.Color(c)));
  im.instanceMatrix.needsUpdate = true;
  if (im.instanceColor) im.instanceColor.needsUpdate = true;
  im.computeBoundingSphere();
  im.userData.noMerge = true;
  im.name = name;
  return im;
}
const hdr = (hex, k) => new THREE.Color(hex).multiplyScalar(k);

// bulb dome facing -Z (marquee chasers)
function bulbGeo(r = 0.06) {
  const g = new THREE.SphereGeometry(r, 8, 4, 0, TAU, 0, Math.PI * 0.62);
  g.rotateX(-Math.PI / 2);
  return g;
}
function socketGeo(r = 0.06) {
  const g = K.lathe([[0, 0], [r * 1.25, 0], [r * 1.3, r * 0.35], [r * 1.05, r * 0.55], [0, r * 0.55]], { seg: 10 }).clone();
  g.rotateX(-Math.PI / 2);
  return g;
}

// sample a polyline by arc length: returns [{p:[x,y], t:[tx,ty]}]
function resample(pts, spacing, { offset = 0.5, closed = false } = {}) {
  const P = closed ? [...pts, pts[0]] : pts;
  const seg = [];
  let L = 0;
  for (let i = 1; i < P.length; i++) { const l = Math.hypot(P[i][0] - P[i - 1][0], P[i][1] - P[i - 1][1]); seg.push(l); L += l; }
  const n = Math.max(1, Math.round(L / spacing));
  const step = L / n;
  const out = [];
  let si = 0, acc = 0;
  for (let k = 0; k < (closed ? n : n + 1); k++) {
    let d = (k + (closed ? offset : 0)) * step;
    if (!closed) d = Math.min(L - 1e-6, k * step);
    while (si < seg.length - 1 && acc + seg[si] < d) { acc += seg[si]; si++; }
    const t = seg[si] > 0 ? (d - acc) / seg[si] : 0;
    const a = P[si], b = P[si + 1];
    const tx = (b[0] - a[0]) / (seg[si] || 1), ty = (b[1] - a[1]) / (seg[si] || 1);
    out.push({ p: [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t], t: [tx, ty] });
  }
  return out;
}
function arcPts(cx, cy, r, a0, a1, n) {
  const p = [];
  for (let i = 0; i <= n; i++) { const a = a0 + (a1 - a0) * (i / n); p.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); }
  return p;
}

// flip-digit strip (n quads facing -Z) from the tote_digits atlas; setStrip() rewrites its UVs
function toteStripGeo(str, tw, th, pitch) {
  const n = str.length;
  const pos = [], uv = [], idx = [];
  for (let i = 0; i < n; i++) {
    const x0 = ((n - 1) / 2 - i) * pitch; // -Z facing: first char at +x (viewer's left)
    const q = [[x0 + tw / 2, -th / 2], [x0 - tw / 2, -th / 2], [x0 - tw / 2, th / 2], [x0 + tw / 2, th / 2]];
    q.forEach(([x, y]) => { pos.push(x, y, 0); uv.push(0, 0); });
    const b = i * 4;
    idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(n * 4).fill(0).flatMap(() => [0, 0, -1]), 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  writeStripUV(g, str);
  return g;
}
function writeStripUV(g, str) {
  const at = getCard('tote_digits').userData.atlas;
  const uv = g.attributes.uv;
  const n = uv.count / 4;
  for (let i = 0; i < n; i++) {
    const ch = str[i] ?? ' ';
    let [u0, v0, u1, v1] = ch === ' ' ? [0.001, 0.001, 0.002, 0.002] : at.uv(ch);
    const e = 0.002; u0 += e; u1 -= e; v0 += e; v1 -= e;
    uv.setXY(i * 4, u0, v0); uv.setXY(i * 4 + 1, u1, v0); uv.setXY(i * 4 + 2, u1, v1); uv.setXY(i * 4 + 3, u0, v1);
  }
  uv.needsUpdate = true;
}
function setStrip(mesh, str) {
  if (!mesh) return;
  if (!mesh.userData.ownGeo) { mesh.geometry = mesh.geometry.clone(); mesh.userData.ownGeo = true; } // clones share geometry
  writeStripUV(mesh.geometry, str);
}

// hanging props: no floor contact shading
const AO_HANG = { floor: false, height: 0 };

// =========================================================================================================
// STUDIO A
// =========================================================================================================

// ---------------------------------------------------------------------------------------- marquee_arch
// Light-bulb marquee arch framing the Studio A stage (inverted-U frame shaped like a CRT screen outline,
// stepped 70s stripes, chrome beads, WZTV 13 pylons, "Spooktacular" crest on a sunburst). opts: { width=14.4, height=4.8 }
// parts.bulbs: InstancedMesh (userData.chase = { count, on, dim }) -> marqueeChase(prop, t, mode).
// Local: arch feet on the stage floor (y=0), opening centered on x, front -Z. Colliders: the two feet only.
registerProp('marquee_arch', (game, opts = {}) => {
  const g = K.prop('marquee_arch');
  const W = opts.width ?? 14.4, H = opts.height ?? 4.8, B = 1.05, R = 1.9, D = 0.62;
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');

  // U-shaped band (outer w x h, band width b, outer top-corner radius r) as a shape with concentric corners
  const uShape = (w, h, b, r) => {
    const s = new THREE.Shape();
    const x0 = -w / 2, x1 = w / 2;
    s.moveTo(x0, 0); s.lineTo(x0, h - r);
    s.absarc(x0 + r, h - r, r, Math.PI, Math.PI / 2, true);
    s.lineTo(x1 - r, h); s.absarc(x1 - r, h - r, r, Math.PI / 2, 0, true);
    s.lineTo(x1, 0); s.lineTo(x1 - b, 0); s.lineTo(x1 - b, h - r);
    s.absarc(x1 - r, h - r, r - b, 0, Math.PI / 2, false);
    s.lineTo(x0 + r, h - b); s.absarc(x0 + r, h - r, r - b, Math.PI / 2, Math.PI, false);
    s.lineTo(x0 + b, 0); s.closePath();
    return s;
  };
  // stripe inset o from the outer edge, width b
  const stripe = (o, b, depth, z, col, bevel = 0.025, bs = 1) => g.add(tm(K.extrude(uShape(W - 2 * o, H - o, b, R - o), depth, { bevel, bevelSeg: bs, curveSeg: 12 }), lac, col, { pos: [0, 0, z] }));
  stripe(0, B, D, 0, PAL.burntOrange, 0.07, 2);
  stripe(0.06, 0.15, 0.06, -D / 2 - 0.02, PAL.channelRed);
  const GB = 0.44, GO = (B - GB) / 2;
  stripe(GO, GB, 0.1, -D / 2 - 0.04, PAL.harvestGold, 0.035, 2);
  stripe(B - 0.2, 0.14, 0.06, -D / 2 - 0.02, PAL.chocolate);
  // chrome beads along the outer and inner front edges
  const edge = (w, h, r, y0) => [[-w / 2, y0], [-w / 2, h - r], ...arcPts(-w / 2 + r, h - r, r, Math.PI, Math.PI / 2, 8).slice(1),
    ...arcPts(w / 2 - r, h - r, r, Math.PI / 2, 0, 8), [w / 2, y0]];
  const bead = (pts, z) => K.tube(pts.map(([x, y]) => [x, y, z]), 0.035, { seg: 60, radial: 6 });
  g.add(K.m(bead(edge(W - 0.03, H - 0.015, R - 0.015, 1.8), -D / 2 + 0.02), chrome));
  g.add(K.m(bead(edge(W - 2 * B + 0.03, H - B + 0.015, R - B + 0.015, 1.8), -D / 2 + 0.02), chrome));
  // back battens (the back side is seen from the stage)
  for (const s of [-1, 1]) g.add(tm(K.box(0.12, H - 0.6, 0.06, 0.012), lac, '#8A5A34', { pos: [s * (W / 2 - B / 2), H / 2, D / 2 + 0.03] }));
  g.add(tm(K.box(W - 2 * R, 0.12, 0.06, 0.012), lac, '#8A5A34', { pos: [0, H - B / 2, D / 2 + 0.03] }));

  // pylons at the feet with a WZTV 13 roundel
  const badge = cv('marquee_badge', 256, 256, (ctx, w, h) => {
    const c = w / 2;
    poly(ctx, starPts(c, c, 126, 104, 16, 0)); ctx.fillStyle = PAL.harvestGold; ctx.fill();
    ctx.fillStyle = PAL.channelRed; ctx.beginPath(); ctx.arc(c, c, 98, 0, TAU); ctx.fill();
    ctx.fillStyle = PAL.wztvBlue; ctx.beginPath(); ctx.arc(c, c, 80, 0, TAU); ctx.fill();
    text(ctx, '13', c, c + 8, { font: FONT.round, size: 104, fill: '#F4F1E8', stroke: '#1B2F7A', lw: 8 });
    text(ctx, 'WZTV', c, c - 58, { font: FONT.sign, size: 22, fill: PAL.harvestGold });
  });
  const badgeMat = K.mat(game, 'lacquer', '#ffffff', { map: badge });
  const PH = 2.3;
  for (const s of [-1, 1]) {
    const x = s * (W / 2 - B / 2);
    g.add(tm(K.box(B + 0.42, PH, D + 0.4, 0.09), lac, PAL.chocolate, { pos: [x, PH / 2, 0] }));
    g.add(tm(K.box(B + 0.54, 0.14, D + 0.52, 0.045), lac, PAL.harvestGold, { pos: [x, PH + 0.02, 0] }));
    g.add(tm(K.box(B + 0.5, 0.1, D + 0.48, 0.014), lac, '#2A1810', { pos: [x, 0.05, 0] }));
    for (let i = 0; i < 3; i++) g.add(tm(K.box(B + 0.44, 0.05, D + 0.42, 0.02), lac, [PAL.burntOrange, PAL.harvestGold, PAL.channelRed][i], { pos: [x, 0.3 + i * 0.075, 0] }));
    const bg = new THREE.CircleGeometry(0.46, 32); bg.rotateY(Math.PI);
    g.add(K.m(bg, badgeMat, { pos: [x, 1.35, -D / 2 - 0.205] }));
  }

  // crest: rounded plaque on a sunburst fan
  const cy = H + 0.25, pw = 4.8, ph = 1.35;
  const rays = 15;
  for (let i = 0; i < rays; i++) {
    const a = Math.PI * (0.08 + 0.84 * (i / (rays - 1)));
    const len = 1.55 + (i % 2) * 0.3;
    const ray = K.extrude([[-0.1, 0], [0.1, 0], [0.24, len], [-0.24, len]], 0.08, { bevel: 0.02, bevelSeg: 1 });
    const m = tm(ray, lac, [PAL.channelRed, PAL.harvestGold, PAL.burntOrange][i % 3], { pos: [0, cy - 0.1, 0.05] });
    m.rotation.z = a - Math.PI / 2;
    g.add(m);
  }
  const plaque = cv('marquee_crest2', 512, 160, (ctx, w, h) => {
    rrect(ctx, 0, 0, w, h, 40); ctx.fillStyle = grad(ctx, 0, 0, 0, h, ['#6B3A6E', '#3E1E48']); ctx.fill();
    ctx.save(); rrect(ctx, 0, 0, w, h, 40); ctx.clip();
    for (let i = 0; i < 3; i++) { ctx.fillStyle = [PAL.burntOrange, PAL.harvestGold, PAL.channelRed][i]; ctx.fillRect(0, h - 40 + i * 9, w, 6); }
    ctx.fillStyle = 'rgba(255,255,255,0.07)'; ctx.fillRect(0, 0, w, h * 0.4);
    ctx.restore();
    text(ctx, 'Spooktacular', w / 2, 60, { font: FONT.groovy, size: 72, fill: grad(ctx, 0, 28, 0, 96, ['#FFF2B0', '#FFC23A', '#FF8A2A']), stroke: '#2A1030', lw: 10, maxW: w * 0.9, shadow: 'rgba(0,0,0,0.35)' });
    text(ctx, '13-HOUR TELETHON  ·  WZTV 13', w / 2, 114, { font: FONT.sign, size: 22, fill: '#F6E7C8', stroke: '#2A1030', lw: 5, maxW: w * 0.8, track: 1 });
  });
  const plaqueMat = K.mat(game, 'lacquer', '#ffffff', { map: plaque });
  g.add(tm(K.extrude(K.roundRect(pw + 0.24, ph + 0.24, 0.45), 0.2, { bevel: 0.06, bevelSeg: 2 }), lac, PAL.harvestGold, { pos: [0, cy, -0.05] }));
  g.add(K.m(decalGeo(pw - 0.02, ph - 0.02), plaqueMat, { pos: [0, cy, -0.157] }));
  const bz = -D / 2 - 0.09 - 0.012;
  const xf = [];
  // bulbs along the gold stripe centerline (pylon tops up; skip the part hidden behind the plaque)
  const c = GO + GB / 2, legY0 = PH + 0.3;
  const pathPts = [[-W / 2 + c, legY0], [-W / 2 + c, H - R], ...arcPts(-W / 2 + R, H - R, R - c, Math.PI, Math.PI / 2, 16).slice(1),
    ...arcPts(W / 2 - R, H - R, R - c, Math.PI / 2, 0, 16), [W / 2 - c, legY0]];
  for (const s of resample(pathPts, 0.3)) {
    if (Math.abs(s.p[0]) < pw / 2 + 0.15 && s.p[1] > H - 0.7) continue;
    xf.push({ pos: [s.p[0], s.p[1], bz] });
  }
  const crestPts = [];
  const rw = pw / 2 - 0.02, rh = ph / 2 - 0.02, rr = 0.36;
  crestPts.push(...arcPts(rw - rr, rh - rr, rr, 0, Math.PI / 2, 5), ...arcPts(-rw + rr, rh - rr, rr, Math.PI / 2, Math.PI, 5),
    ...arcPts(-rw + rr, -rh + rr, rr, Math.PI, Math.PI * 1.5, 5), ...arcPts(rw - rr, -rh + rr, rr, Math.PI * 1.5, TAU, 5));
  for (const s of resample(crestPts, 0.28, { closed: true })) xf.push({ pos: [s.p[0], cy + s.p[1], -0.28], scale: 0.72 });
  const on = PAL.marqueeGold;
  const bulbs = instanced(bulbGeo(0.075), K.glow(game, '#ffffff', 1), xf, xf.map((_, i) => hdr(on, i % 3 === 0 ? 3.2 : 1.5)), 'bulbs');
  const sockets = instanced(socketGeo(0.075), K.mat(game, 'brass', '#C8963C'), xf.map((t) => ({ ...t, pos: [t.pos[0], t.pos[1], t.pos[2] + 0.035] })), null, 'sockets');
  g.add(bulbs, sockets);

  const u = g.userData;
  u.parts = { bulbs };
  u.chase = { count: xf.length, on, dim: '#5A3A22' };
  u.colliders = [-1, 1].map((s) => ({ min: [s * (W / 2 - B / 2) - (B + 0.54) / 2, 0, -D / 2 - 0.26], max: [s * (W / 2 - B / 2) + (B + 0.54) / 2, H, D / 2 + 0.26] }));
  u.lightAnchors = [
    { pos: [-W / 2 + 1.4, H - 0.9, -1.2], color: PAL.marqueeGold, intensity: 2.2, distance: 7 },
    { pos: [W / 2 - 1.4, H - 0.9, -1.2], color: PAL.marqueeGold, intensity: 2.2, distance: 7 },
  ];
  return K.finish(game, g, { ao: { res: 80, dist: 0.5 } });
}, { category: CAT, tags: ['studio_a', 'stage', 'marquee', 'bulbs'], size: [14.9, 6.35, 1.2], desc: 'light-bulb marquee arch framing the telethon stage', hero: true });

// Chase the marquee bulbs. mode: 'chase' (every 3rd bulb runs), 'flash' (all blink), 'on', 'off' (dim), 'sparkle'
export function marqueeChase(prop, t = 0, mode = 'chase', { speed = 9, bright = 3.2 } = {}) {
  const im = prop?.userData?.parts?.bulbs;
  const ch = prop?.userData?.chase;
  if (!im || !ch) return;
  const c = new THREE.Color();
  const step = Math.floor(t * speed);
  const on = new THREE.Color(ch.on), dim = new THREE.Color(ch.dim);
  for (let i = 0; i < ch.count; i++) {
    let k;
    if (mode === 'off') k = 0;
    else if (mode === 'on') k = 1;
    else if (mode === 'flash') k = step % 2;
    else if (mode === 'sparkle') k = ((i * 7919 + step * 104729) % 11) < 4 ? 1 : 0.25;
    else k = ((i + step) % 3 === 0) ? 1 : 0.18;
    if (k <= 0) c.copy(dim).multiplyScalar(0.5); else c.copy(on).multiplyScalar(bright * k);
    im.setColorAt(i, c);
  }
  im.instanceColor.needsUpdate = true;
}

// ---------------------------------------------------------------------------------------- pledge_wheel
// The Wheel of Pledges (ee_prize_wheel / toy_prize_wheel): 4 m vertical prize wheel with 13 painted wedges, brass
// pegs, rim bulbs, a static gold hub with a little perch (Hootie sits there) and a leather flapper.
// parts: wheel (rotate .rotation.z), flapper (pivot at its hinge, rotate .rotation.z), lever (SPIN pull lever).
// anchors.puppet_seat: where the puppet sits (local). Placed as in GDD (pos [4.0,0.6,-29.3], rotY=PI) the SPIN
// lever/interact lands at world [5.8,0.6,-28.8]. userData.wedges: labels clockwise from the top.
const WEDGES = ['$13', '$5', '$25', 'DEAD AIR', '$50', '$10', 'BONUS', '$13', '$100', '$20', '$1', 'DOUBLE', '13!'];
registerProp('pledge_wheel', (game) => {
  const g = K.prop('pledge_wheel');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const brass = K.mat(game, 'brass', '#C8963C');
  const CY = 2.36, RW = 1.98;
  const n = WEDGES.length;
  const cols = [PAL.channelRed, PAL.harvestGold, PAL.teal, PAL.burntOrange, PAL.plum];
  const faceTex = cv('wheel_face', 512, 512, (ctx, w, h) => {
    const cx = w / 2, cy = h / 2, R = w / 2;
    for (let i = 0; i < n; i++) {
      const a0 = -Math.PI / 2 - Math.PI / n + (i / n) * TAU, a1 = a0 + TAU / n;
      let col = cols[i % cols.length];
      if (WEDGES[i] === 'DEAD AIR') col = '#2A1D3A';
      if (WEDGES[i] === 'BONUS' || WEDGES[i] === '13!') col = i % 2 ? '#2F5BD3' : '#8C9A3A';
      const gr = ctx.createRadialGradient(cx, cy, R * 0.15, cx, cy, R);
      gr.addColorStop(0, shadeHex(col, -0.25)); gr.addColorStop(0.55, col); gr.addColorStop(0.92, shadeHex(col, 0.12)); gr.addColorStop(1, shadeHex(col, -0.2));
      ctx.beginPath(); ctx.moveTo(cx, cy); ctx.arc(cx, cy, R, a0, a1); ctx.closePath(); ctx.fillStyle = gr; ctx.fill();
      // glossy streak
      ctx.save(); ctx.clip();
      ctx.fillStyle = 'rgba(255,255,255,0.08)';
      ctx.beginPath(); ctx.moveTo(cx, cy); ctx.arc(cx, cy, R, a0, a0 + (a1 - a0) * 0.35); ctx.closePath(); ctx.fill();
      ctx.restore();
      // label along the radius, reading outward
      const am = (a0 + a1) / 2;
      ctx.save(); ctx.translate(cx + Math.cos(am) * R * 0.6, cy + Math.sin(am) * R * 0.6); ctx.rotate(am + Math.PI);
      const lbl = WEDGES[i];
      const dark = col === '#2A1D3A';
      text(ctx, lbl, 0, 0, { font: lbl.length > 4 ? FONT.sign : FONT.round, size: lbl.length > 4 ? 30 : 46, fill: dark ? '#9CFF57' : '#FFF8E6', stroke: dark ? '#10081A' : shadeHex(col, -0.55), lw: 7, maxW: R * 0.62, shadow: 'rgba(0,0,0,0.25)' });
      if (dark) text(ctx, '☠', -R * 0.26, 0, { font: FONT.round, size: 26, fill: '#9CFF57' });
      ctx.restore();
    }
    // dividers + dotted border + hub ring
    ctx.strokeStyle = '#FFF4DC'; ctx.lineWidth = 5;
    for (let i = 0; i < n; i++) { const a = -Math.PI / 2 - Math.PI / n + (i / n) * TAU; ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * R * 0.2, cy + Math.sin(a) * R * 0.2); ctx.lineTo(cx + Math.cos(a) * R, cy + Math.sin(a) * R); ctx.stroke(); }
    ctx.beginPath(); ctx.arc(cx, cy, R * 0.97, 0, TAU); ctx.lineWidth = 10; ctx.strokeStyle = '#3A1E2E'; ctx.stroke();
    ctx.beginPath(); ctx.arc(cx, cy, R * 0.24, 0, TAU); ctx.fillStyle = '#F6E7C8'; ctx.fill(); ctx.lineWidth = 6; ctx.strokeStyle = '#3A1E2E'; ctx.stroke();
    for (let i = 0; i < 26; i++) { const a = (i / 26) * TAU; ctx.beginPath(); ctx.arc(cx + Math.cos(a) * R * 0.2, cy + Math.sin(a) * R * 0.2, 4, 0, TAU); ctx.fillStyle = i % 2 ? PAL.channelRed : PAL.harvestGold; ctx.fill(); }
  });
  const faceMat = K.mat(game, 'lacquer', '#ffffff', { map: faceTex });

  // ---- spinning wheel (own group, pre-merged so it stays one draw call per material)
  const wheel = new THREE.Group();
  wheel.position.set(0, CY, 0);
  const body = K.cyl(RW, RW, 0.16, { bevel: 0.035, seg: 48 }).clone();
  body.rotateX(-Math.PI / 2); body.translate(0, 0, 0.08);
  wheel.add(tm(body, lac, PAL.harvestGold));
  wheel.add(K.m(decalGeo(RW * 2 - 0.1, RW * 2 - 0.1), faceMat, { pos: [0, 0, -0.084] }));
  // replace the square decal by a round one
  wheel.children[1].geometry = (() => { const c = new THREE.CircleGeometry(RW - 0.05, 72); c.rotateY(Math.PI); return c; })();
  const rim = new THREE.TorusGeometry(RW - 0.02, 0.055, 7, 64);
  wheel.add(tm(rim, lac, '#3A1E2E', { pos: [0, 0, -0.08] }));
  for (let i = 0; i < n; i++) {
    const a = Math.PI / 2 + Math.PI / n - (i / n) * TAU;
    const peg = K.cyl(0.026, 0.03, 0.13, { seg: 7, bevel: 0.006 }).clone();
    peg.rotateX(-Math.PI / 2);
    wheel.add(K.m(peg, chrome, { pos: [Math.cos(a) * (RW - 0.02), Math.sin(a) * (RW - 0.02), -0.1] }));
  }
  const rimBulb = K.glow(game, PAL.marqueeGold, 2.6);
  const bg = bulbGeo(0.038);
  for (let i = 0; i < 26; i++) {
    const a = (i / 26) * TAU + Math.PI / 26;
    wheel.add(K.m(bg, rimBulb, { pos: [Math.cos(a) * (RW - 0.2), Math.sin(a) * (RW - 0.2), -0.09] }));
  }
  const backTex = cv('wheel_back', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#C8A06A'; ctx.beginPath(); ctx.arc(128, 128, 128, 0, TAU); ctx.fill();
    for (let i = 0; i < 40; i++) { ctx.strokeStyle = 'rgba(120,80,40,' + (0.1 + rand() * 0.15) + ')'; ctx.lineWidth = 1 + rand() * 2; const y = rand() * h; ctx.beginPath(); ctx.moveTo(0, y); ctx.bezierCurveTo(80, y + 6, 170, y - 6, w, y + 3); ctx.stroke(); }
    ctx.fillStyle = '#8A5A34'; for (let i = 0; i < 4; i++) { ctx.save(); ctx.translate(128, 128); ctx.rotate(i * Math.PI / 4); ctx.fillRect(-128, -9, 256, 18); ctx.restore(); }
    ctx.globalAlpha = 0.7;
    text(ctx, 'PROPERTY OF WZTV', 128, 190, { font: FONT.sign, size: 18, fill: '#3A2A48' });
    text(ctx, 'STUDIO A - DO NOT SPIN BACKWARDS', 128, 212, { font: FONT.round, size: 10, fill: '#3A2A48' });
    ctx.globalAlpha = 1;
  });
  wheel.add(K.m(new THREE.CircleGeometry(RW - 0.05, 40), K.mat(game, 'paint', '#ffffff', { map: backTex }), { pos: [0, 0, 0.162] }));
  K.merge(wheel);
  wheel.userData.noMerge = true;
  g.add(wheel);

  // ---- stand: base platform, back post, splayed legs, axle bearing
  g.add(tm(K.box(3.0, 0.34, 1.2, 0.08), lac, PAL.chocolate, { pos: [0, 0.17, 0.1] }));
  g.add(tm(K.box(3.08, 0.08, 1.28, 0.035), lac, PAL.harvestGold, { pos: [0, 0.36, 0.1] }));
  g.add(tm(K.box(3.12, 0.05, 1.3, 0.02), lac, '#2A1810', { pos: [0, 0.025, 0.1] }));
  const signTex = cv('wheel_sign', 512, 96, (ctx, w, h) => {
    rrect(ctx, 0, 0, w, h, 20); ctx.fillStyle = '#F6E7C8'; ctx.fill();
    ctx.save(); rrect(ctx, 0, 0, w, h, 20); ctx.clip();
    [PAL.channelRed, PAL.harvestGold, PAL.teal].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(0, h - 20 + i * 7, w, 5); });
    ctx.restore();
    text(ctx, 'WHEEL OF PLEDGES', w / 2, h * 0.42, { font: FONT.sign, size: 44, fill: PAL.channelRed, stroke: '#3A1E2E', lw: 6, maxW: w * 0.9, shadow: 'rgba(0,0,0,0.2)' });
  });
  g.add(K.m(decalGeo(2.2, 0.21), K.mat(game, 'lacquer', '#ffffff', { map: signTex }), { pos: [0, 0.18, -0.505] }));
  // back post (tapered) + head that carries the flapper
  g.add(tm(K.taper(K.box(0.36, CY + 2.35, 0.26, 0.07), { axis: 'y', k: 0.72 }), lac, PAL.teal, { pos: [0, (CY + 2.35) / 2 + 0.3, 0.3] }));
  for (const s of [-1, 1]) {
    const a = V3(s * 1.15, 0.38, 0.35), b = V3(s * 0.12, CY - 0.2, 0.3);
    const leg = K.m(tg(K.taper(K.box(0.2, a.distanceTo(b), 0.16, 0.05), { axis: 'y', k: 0.7 }), PAL.teal), lac);
    leg.position.copy(a).add(b).multiplyScalar(0.5);
    leg.quaternion.setFromUnitVectors(UP, b.clone().sub(a).normalize());
    g.add(leg);
    g.add(tm(K.box(0.3, 0.1, 0.26, 0.04), lac, PAL.harvestGold, { pos: [s * 1.15, 0.42, 0.35] }));
  }
  const bearing = K.cyl(0.2, 0.24, 0.2, { seg: 20, bevel: 0.04 }).clone();
  bearing.rotateX(Math.PI / 2);
  g.add(tm(bearing, lac, PAL.harvestGold, { pos: [0, CY, 0.12] }));
  // static hub (in front of the wheel) + perch shelf
  const hub = K.lathe([[0, 0], [0.4, 0], [0.42, 0.06], [0.36, 0.2], [0.24, 0.26], [0.12, 0.3], [0, 0.31]], { round: 0.03, seg: 24 }).clone();
  hub.rotateX(-Math.PI / 2);
  g.add(tm(hub, lac, PAL.harvestGold, { pos: [0, CY, -0.1] }));
  const hubCap = cv('wheel_hub', 256, 256, (ctx, w, h) => {
    ctx.fillStyle = PAL.channelRed; ctx.beginPath(); ctx.arc(w / 2, h / 2, w / 2, 0, TAU); ctx.fill();
    ctx.fillStyle = PAL.wztvBlue; ctx.beginPath(); ctx.arc(w / 2, h / 2, w * 0.4, 0, TAU); ctx.fill();
    text(ctx, '13', w / 2, h / 2 + 6, { font: FONT.round, size: 120, fill: '#F4F1E8', stroke: '#1B2F7A', lw: 10 });
  });
  const capG = new THREE.CircleGeometry(0.2, 32); capG.rotateY(Math.PI);
  g.add(K.m(capG, K.mat(game, 'lacquer', '#ffffff', { map: hubCap }), { pos: [0, CY, -0.414] }));
  const perch = K.lathe([[0, 0], [0.24, 0], [0.27, 0.04], [0.27, 0.07], [0, 0.07]], { round: 0.02, seg: 24 }).clone();
  perch.scale(1, 1, 0.75);
  g.add(tm(perch, lac, PAL.chocolate, { pos: [0, CY - 0.4, -0.42] }));
  g.add(tm(K.box(0.1, 0.38, 0.1, 0.03), lac, PAL.chocolate, { pos: [0, CY - 0.57, -0.33] }));

  // flapper on the post head
  g.add(tm(K.box(0.3, 0.2, 0.62, 0.06), lac, PAL.harvestGold, { pos: [0, CY + RW + 0.3, -0.02] }));
  const flapper = new THREE.Group();
  flapper.position.set(0, CY + RW + 0.2, -0.2);
  flapper.add(tm(K.extrude([[-0.07, 0], [0.07, 0], [0.03, -0.32], [0, -0.38], [-0.03, -0.32]], 0.04, { bevel: 0.012, round: 0.015 }), lac, PAL.channelRed, { pos: [0, 0, 0] }));
  flapper.add(K.m(K.cyl(0.035, 0.035, 0.14, { seg: 10 }).clone().rotateZ(Math.PI / 2), chrome, { pos: [0.07, 0, 0] }));
  K.merge(flapper);
  flapper.userData.noMerge = true;
  g.add(flapper);

  // SPIN pull-lever pedestal (viewer's right)
  const LX = -1.78;
  g.add(tm(K.taper(K.box(0.42, 0.95, 0.42, 0.06), { axis: 'y', k: 0.8 }), lac, PAL.channelRed, { pos: [LX, 0.475, -0.35] }));
  g.add(tm(K.box(0.5, 0.07, 0.5, 0.03), lac, PAL.harvestGold, { pos: [LX, 0.98, -0.35] }));
  const spinTex = cv('wheel_spin', 256, 128, (ctx, w, h) => {
    rrect(ctx, 0, 0, w, h, 24); ctx.fillStyle = '#F6E7C8'; ctx.fill();
    text(ctx, 'SPIN!', w / 2, h / 2 + 4, { font: FONT.sign, size: 64, fill: PAL.channelRed, stroke: '#3A1E2E', lw: 6 });
  });
  g.add(K.m(decalGeo(0.3, 0.15), K.mat(game, 'lacquer', '#ffffff', { map: spinTex }), { pos: [LX, 0.65, -0.575] }));
  const lever = new THREE.Group();
  lever.position.set(LX, 1.02, -0.35);
  lever.add(K.m(K.cyl(0.02, 0.022, 0.5, { seg: 8 }), chrome, { rot: [0, 0, 0.35] }));
  lever.add(K.m(new THREE.SphereGeometry(0.075, 12, 8), lac, { pos: [-Math.sin(0.35) * 0.52, Math.cos(0.35) * 0.52, 0] }));
  lever.children[1].geometry = tg(lever.children[1].geometry, PAL.channelRed);
  K.merge(lever);
  lever.userData.noMerge = true;
  g.add(lever);

  const u = g.userData;
  u.parts = { wheel, flapper, lever };
  u.wedges = WEDGES;
  u.anchors = { puppet_seat: [0, CY - 0.33, -0.44], hub: [0, CY, -0.42] };
  u.interact = { point: [LX, 1.0, -0.6], radius: 1.4 };
  u.colliders = [{ min: [-1.55, 0, -0.5], max: [1.55, CY + RW + 0.2, 0.75] }, { min: [LX - 0.25, 0, -0.6], max: [LX + 0.25, 1.1, -0.1] }];
  return K.finish(game, g, { ao: { res: 64 } });
}, { category: CAT, tags: ['studio_a', 'stage', 'ee', 'toy', 'wheel'], size: [4.0, 4.7, 1.3], desc: 'Wheel of Pledges: 4 m prize wheel with 13 wedges', hero: true });

// ---------------------------------------------------------------------------------------- baron_throne
// Deterministic verlet cloth (build time): grid nx*ny, init(u,v)->[x,y,z], pin(i,j)->[x,y,z]|null, colliders = local
// AABBs [{min,max}], floor y=0. Returns an indexed BufferGeometry (uv 0..1).
function drape({ nx = 14, ny = 18, init, pin, colliders = [], iters = 220, relax = 10, gravity = 9.8, floorY = 0.012, thick = 0.02 }) {
  const N = nx * ny;
  const p = new Float32Array(N * 3), q = new Float32Array(N * 3);
  const pinned = new Array(N).fill(null);
  for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
    const k = j * nx + i, v = init(i / (nx - 1), j / (ny - 1));
    p.set(v, k * 3); q.set(v, k * 3);
    const pp = pin(i, j);
    if (pp) pinned[k] = pp;
  }
  const cons = [];
  const add = (a, b) => cons.push([a, b, Math.hypot(p[a * 3] - p[b * 3], p[a * 3 + 1] - p[b * 3 + 1], p[a * 3 + 2] - p[b * 3 + 2])]);
  for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
    const k = j * nx + i;
    if (i < nx - 1) add(k, k + 1);
    if (j < ny - 1) add(k, k + nx);
    if (i < nx - 1 && j < ny - 1) { add(k, k + nx + 1); add(k + 1, k + nx); }
    if (i < nx - 2) add(k, k + 2);
    if (j < ny - 2) add(k, k + nx * 2);
  }
  const dt2 = (1 / 60) ** 2 * gravity;
  for (let it = 0; it < iters; it++) {
    for (let k = 0; k < N; k++) {
      const o = k * 3;
      for (let a = 0; a < 3; a++) {
        const v = (p[o + a] - q[o + a]) * 0.97;
        q[o + a] = p[o + a];
        p[o + a] += v - (a === 1 ? dt2 : 0);
      }
    }
    for (let r = 0; r < relax; r++) {
      for (const [a, b, L] of cons) {
        const ax = a * 3, bx = b * 3;
        const dx = p[bx] - p[ax], dy = p[bx + 1] - p[ax + 1], dz = p[bx + 2] - p[ax + 2];
        const d = Math.hypot(dx, dy, dz) || 1e-6;
        const f = (d - L) / d;
        const wa = pinned[a] ? 0 : 1, wb = pinned[b] ? 0 : 1;
        const s = wa + wb; if (!s) continue;
        p[ax] += dx * f * wa / s; p[ax + 1] += dy * f * wa / s; p[ax + 2] += dz * f * wa / s;
        p[bx] -= dx * f * wb / s; p[bx + 1] -= dy * f * wb / s; p[bx + 2] -= dz * f * wb / s;
      }
      for (let k = 0; k < N; k++) {
        const o = k * 3;
        if (pinned[k]) { p.set(pinned[k], o); continue; }
        if (p[o + 1] < floorY) { p[o + 1] = floorY; q[o] = lerp(q[o], p[o], 0.6); q[o + 2] = lerp(q[o + 2], p[o + 2], 0.6); }
        for (const c of colliders) {
          const x = p[o], y = p[o + 1], z = p[o + 2];
          const mn = c.min, mx = c.max;
          if (x > mn[0] - thick && x < mx[0] + thick && y > mn[1] - thick && y < mx[1] + thick && z > mn[2] - thick && z < mx[2] + thick) {
            const dd = [x - (mn[0] - thick), mx[0] + thick - x, y - (mn[1] - thick), mx[1] + thick - y, z - (mn[2] - thick), mx[2] + thick - z];
            let bi = 0; for (let t = 1; t < 6; t++) if (dd[t] < dd[bi]) bi = t;
            const ax = bi >> 1, sg = bi & 1 ? 1 : -1;
            p[o + ax] += sg * dd[bi];
          }
        }
      }
    }
  }
  const g = new THREE.BufferGeometry();
  const uv = new Float32Array(N * 2), idx = [];
  for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) { const k = j * nx + i; uv[k * 2] = i / (nx - 1); uv[k * 2 + 1] = 1 - j / (ny - 1); }
  for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) { const a = j * nx + i, b = a + 1, c = a + nx, d = c + 1; idx.push(a, c, b, b, c, d); }
  g.setAttribute('position', new THREE.BufferAttribute(p, 3));
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

// The Baron's empty host throne (plum velvet, gothic arched back with antenna crest) with his cape slumped on the
// seat and snagged on a novelty TRAP DOOR lever. GDD pos [-1.5,0.6,-28.3]. parts: lever. anchors.seat.
registerProp('baron_throne', (game) => {
  const g = K.prop('baron_throne');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const brass = K.mat(game, 'brass', '#C8963C');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const velvet = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#7A2E6E', { pattern: 'plain', scale: 2 }) });
  const WOOD = '#3B2238', GOLD = '#D9A520';
  const SW = 1.04, SD = 0.78, SH = 0.46;
  // seat base with a scalloped apron
  g.add(tm(K.box(SW, SH - 0.08, SD, 0.06), lac, WOOD, { pos: [0, 0.12 + (SH - 0.12) / 2 - 0.02, 0] }));
  g.add(tm(K.box(SW + 0.06, 0.07, SD + 0.06, 0.03), lac, GOLD, { pos: [0, SH - 0.03, 0] }));
  for (let i = 0; i < 5; i++) {
    const x = -0.4 + i * 0.2;
    g.add(tm(new THREE.SphereGeometry(0.05, 10, 8, 0, TAU, 0, Math.PI / 2).rotateX(Math.PI), lac, GOLD, { pos: [x, 0.2, -SD / 2 - 0.005] }));
  }
  // ball feet
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    g.add(K.m(new THREE.SphereGeometry(0.075, 10, 7), brass, { pos: [x * (SW / 2 - 0.08), 0.075, z * (SD / 2 - 0.08)] }));
    g.add(tm(K.cyl(0.06, 0.07, 0.06, { seg: 12 }), lac, WOOD, { pos: [x * (SW / 2 - 0.08), 0.13, z * (SD / 2 - 0.08)] }));
  }
  // seat cushion
  g.add(K.m(K.cushion(SW - 0.14, 0.16, SD - 0.12, { puff: 0.03, uv: 3 }), velvet, { pos: [0, SH + 0.07, -0.03] }));
  // gothic back: extruded pointed arch + tufted velvet inset + buttons
  const backShape = (w, h0, h1) => {
    const s = new THREE.Shape();
    s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.lineTo(w / 2, h0);
    s.quadraticCurveTo(w / 2, h0 + (h1 - h0) * 0.55, 0, h1);
    s.quadraticCurveTo(-w / 2, h0 + (h1 - h0) * 0.55, -w / 2, h0);
    s.closePath();
    return s;
  };
  const BZ = SD / 2 - 0.09;
  g.add(tm(K.extrude(backShape(SW, 1.25, 1.95), 0.18, { bevel: 0.05, bevelSeg: 2, curveSeg: 10 }), lac, WOOD, { pos: [0, SH, BZ] }));
  g.add(tm(K.extrude(backShape(SW + 0.06, 1.27, 2.0), 0.08, { bevel: 0.03, bevelSeg: 2, curveSeg: 10 }), lac, '#2A1828', { pos: [0, SH - 0.01, BZ + 0.08] }));
  const outline = backShape(SW - 0.02, 1.24, 1.93).getPoints(8).map((v) => [v.x, SH + v.y, BZ - 0.09]);
  g.add(tm(K.tube(outline.slice(1), 0.022, { seg: 48, radial: 6 }), lac, GOLD));
  const inset = K.extrude(backShape(SW - 0.24, 1.08, 1.72), 0.12, { bevel: 0.05, bevelSeg: 2, curveSeg: 10 });
  K.uvScale(inset, 3, 3);
  g.add(K.m(inset, velvet, { pos: [0, SH + 0.1, BZ - 0.1] }));
  for (let r = 0; r < 4; r++) for (let c = 0; c < 3 - (r % 2); c++) {
    const x = (c - (2 - (r % 2)) / 2) * 0.24, y = SH + 0.36 + r * 0.3;
    g.add(K.m(new THREE.SphereGeometry(0.022, 6, 4), brass, { pos: [x, y, BZ - 0.165] }));
  }
  // spires at the shoulders + crest: medallion with a static bolt and rabbit-ear antennas
  for (const s of [-1, 1]) {
    g.add(tm(K.lathe([[0, 0], [0.07, 0], [0.08, 0.05], [0.05, 0.1], [0.06, 0.16], [0.03, 0.26], [0, 0.34]], { round: 0.015, seg: 10, steps: 1 }), lac, GOLD, { pos: [s * (SW / 2 - 0.02), SH + 1.25, BZ] }));
  }
  const medal = cv('throne_medal', 256, 256, (ctx, w, h) => {
    ctx.fillStyle = '#2A1030'; ctx.beginPath(); ctx.arc(w / 2, h / 2, w / 2, 0, TAU); ctx.fill();
    ctx.fillStyle = grad(ctx, 0, 0, 0, h, ['#B08ADA', '#6B3A6E']); ctx.beginPath(); ctx.arc(w / 2, h / 2, w * 0.42, 0, TAU); ctx.fill();
    poly(ctx, [[150, 30], [90, 135], [130, 135], [100, 226], [175, 110], [132, 110]]); ctx.fillStyle = '#9CFF57'; ctx.fill(); ctx.lineWidth = 8; ctx.strokeStyle = '#1E1030'; ctx.stroke();
  });
  const mg = new THREE.CircleGeometry(0.15, 28); mg.rotateY(Math.PI);
  g.add(tm(K.cyl(0.18, 0.18, 0.06, { seg: 20, bevel: 0.02 }).clone().rotateX(-Math.PI / 2), lac, GOLD, { pos: [0, SH + 1.72, BZ - 0.1] }));
  g.add(K.m(mg, K.mat(game, 'lacquer', '#ffffff', { map: medal }), { pos: [0, SH + 1.72, BZ - 0.162] }));
  for (const s of [-1, 1]) {
    const a = V3(s * 0.05, SH + 1.93, BZ), b = V3(s * 0.34, SH + 2.42, BZ + 0.04);
    g.add(rod(0.014, chrome, a, b, 8));
    g.add(tm(new THREE.SphereGeometry(0.035, 12, 8), lac, PAL.channelRed, { pos: b.toArray() }));
  }
  g.add(tm(new THREE.SphereGeometry(0.06, 10, 7), lac, GOLD, { pos: [0, SH + 1.95, BZ] }));
  // armrests with scroll ends
  for (const s of [-1, 1]) {
    const x = s * (SW / 2 - 0.03);
    g.add(tm(K.box(0.14, 0.34, 0.14, 0.04), lac, WOOD, { pos: [x, SH + 0.17, -SD / 2 + 0.1] }));
    g.add(tm(K.box(0.16, 0.08, SD - 0.02, 0.035), lac, WOOD, { pos: [x, SH + 0.36, 0.0] }));
    g.add(K.m(K.cushion(0.12, 0.05, SD - 0.18, { puff: 0.012 }), velvet, { pos: [x, SH + 0.42, 0.04] }));
    const scroll = new THREE.TorusGeometry(0.075, 0.035, 6, 12);
    scroll.rotateY(Math.PI / 2);
    g.add(tm(scroll, lac, GOLD, { pos: [x, SH + 0.36, -SD / 2 - 0.02] }));
  }
  // novelty TRAP DOOR lever (viewer's left of the throne, prop +x)
  const LX = 0.98, LZ = -0.28;
  g.add(tm(K.taper(K.box(0.24, 0.56, 0.24, 0.05), { axis: 'y', k: 0.75 }), lac, WOOD, { pos: [LX, 0.28, LZ] }));
  g.add(tm(K.box(0.3, 0.06, 0.3, 0.025), lac, GOLD, { pos: [LX, 0.58, LZ] }));
  g.add(tm(K.box(0.3, 0.06, 0.3, 0.025), lac, GOLD, { pos: [LX, 0.03, LZ] }));
  const trap = cv('throne_trap', 256, 160, (ctx, w, h) => {
    rrect(ctx, 0, 0, w, h, 18); ctx.fillStyle = '#F4E03A'; ctx.fill();
    ctx.save(); rrect(ctx, 0, 0, w, h, 18); ctx.clip();
    for (let i = -4; i < 12; i++) { ctx.fillStyle = '#2A1D3A'; ctx.beginPath(); ctx.moveTo(i * 36, h); ctx.lineTo(i * 36 + 18, h); ctx.lineTo(i * 36 + 48, h - 30); ctx.lineTo(i * 36 + 30, h - 30); ctx.fill(); }
    ctx.restore();
    text(ctx, 'TRAP DOOR', w / 2, 48, { font: FONT.sign, size: 38, fill: '#2A1D3A', maxW: w * 0.86 });
    text(ctx, 'DO NOT PULL!', w / 2, 92, { font: FONT.round, size: 26, fill: PAL.channelRed, maxW: w * 0.8 });
  });
  g.add(K.m(decalGeo(0.19, 0.12), K.mat(game, 'lacquer', '#ffffff', { map: trap }), { pos: [LX, 0.36, LZ - 0.112] }));
  const lever = new THREE.Group();
  lever.position.set(LX, 0.62, LZ);
  const la = 0.5;
  lever.add(K.m(K.cyl(0.018, 0.02, 0.48, { seg: 8 }), chrome, { rot: [-la, 0, 0] }));
  const knobPos = [0, Math.cos(la) * 0.5, -Math.sin(la) * 0.5];
  lever.add(tm(new THREE.SphereGeometry(0.06, 10, 7), lac, PAL.channelRed, { pos: knobPos }));
  lever.add(K.m(K.cyl(0.05, 0.05, 0.05, { seg: 12 }).clone().rotateZ(Math.PI / 2), brass, { pos: [0.025, 0, 0] }));
  K.merge(lever);
  lever.userData.noMerge = true;
  g.add(lever);
  // the cape: slumped on the seat, spilling to the floor, one corner hooked on the lever knob
  const knobW = V3(LX, 0.62 + knobPos[1], LZ + knobPos[2]);
  const nx = 14, ny = 20, CW = 1.45, CL = 2.35;
  const cols = [
    { min: [-SW / 2 + 0.04, 0, -SD / 2 + 0.02], max: [SW / 2 - 0.04, SH + 0.14, SD / 2 - 0.02] },
    { min: [-SW / 2 + 0.05, SH, BZ - 0.16], max: [SW / 2 - 0.05, SH + 1.2, SD / 2] },
    { min: [SW / 2 - 0.12, 0, -SD / 2], max: [SW / 2 + 0.06, SH + 0.44, SD / 2] },
    { min: [-SW / 2 - 0.06, 0, -SD / 2], max: [-SW / 2 + 0.12, SH + 0.44, SD / 2] },
    { min: [LX - 0.13, 0, LZ - 0.13], max: [LX + 0.13, 0.6, LZ + 0.13] },
  ];
  const collarY = SH + 1.02, collarZ = BZ - 0.19;
  const capeGeo = drape({
    nx, ny, colliders: cols,
    init: (u, v) => {
      const x = (u - 0.5) * CW * (0.75 + v * 0.4);
      const s = v * CL;
      const s1 = collarY - (SH + 0.16), s2 = s1 + 0.62;
      if (s < s1) return [x * 0.8, collarY - s, collarZ];
      if (s < s2) return [x, SH + 0.17, collarZ - (s - s1)];
      return [x, Math.max(0.02, SH + 0.17 - (s - s2)), collarZ - (s2 - s1) - 0.05];
    },
    pin: (i, j) => {
      if (j === 0) return [((i / (nx - 1)) - 0.5) * CW * 0.62, collarY + Math.sin((i / (nx - 1)) * Math.PI) * 0.04, collarZ - Math.sin((i / (nx - 1)) * Math.PI) * 0.03];
      if (i === nx - 1 && j === Math.round((ny - 1) * 0.62)) return knobW.toArray();
      return null;
    },
  });
  const capeOut = K.mat(game, 'lacquer', '#2A1A3A', { side: THREE.BackSide, rim: 0.3, rimColor: '#B08ADA' });
  const capeIn = K.mat(game, 'lacquer', '#C8283C', { side: THREE.FrontSide });
  g.add(K.m(capeGeo, capeOut), K.m(capeGeo, capeIn));
  // stand-up collar (half cone behind the collar line)
  const collar = new THREE.CylinderGeometry(0.5, 0.28, 0.42, 12, 1, true, -Math.PI * 0.55, Math.PI * 1.1);
  { const p = collar.attributes.position; for (let i = 0; i < p.count; i++) if (p.getY(i) > 0) { const a = Math.atan2(p.getX(i), p.getZ(i)); p.setY(i, p.getY(i) + Math.abs(Math.sin(a * 3)) * 0.06); } collar.computeVertexNormals(); }
  const cIn = K.m(collar, capeIn, { pos: [0, collarY + 0.2, collarZ + 0.02] }), cOut = K.m(collar, capeOut, { pos: [0, collarY + 0.2, collarZ + 0.02] });
  cIn.rotation.x = cOut.rotation.x = -0.2;
  g.add(cIn, cOut);

  const u = g.userData;
  u.parts = { lever };
  u.anchors = { seat: [0, SH + 0.16, -0.05] };
  u.colliders = [{ min: [-SW / 2 - 0.06, 0, -SD / 2 - 0.08], max: [SW / 2 + 0.06, SH + 2.0, SD / 2 + 0.05] }, { min: [LX - 0.16, 0, LZ - 0.16], max: [LX + 0.16, 0.95, LZ + 0.16] }];
  return K.finish(game, g, { ao: { res: 60 } });
}, { category: CAT, tags: ['studio_a', 'stage', 'baron', 'chair'], size: [1.4, 2.9, 1.1], desc: 'the Baron empty host throne, cape snagged on a TRAP DOOR lever', hero: true });

// ---------------------------------------------------------------------------------------- contestant_podium
// 70s game-show contestant podium: tapered body, chaser-bulb frame, buzzer, flip-digit score (tote atlas).
// opts: { num=1..3, color, score='$130' }. parts: score (strip mesh; setPodiumScore(prop, '$250')), buzzer.
registerProp('contestant_podium', (game, opts = {}) => {
  const num = opts.num ?? 1;
  const g = K.prop('contestant_podium');
  const col = opts.color ?? [PAL.channelRed, PAL.harvestGold, PAL.teal][(num - 1) % 3];
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const Wd = 0.84, Hh = 1.02, Dd = 0.58;
  g.add(tm(K.box(Wd + 0.12, 0.1, Dd + 0.12, 0.014), lac, PAL.chocolate, { pos: [0, 0.05, 0] }));
  g.add(tm(K.taper(K.box(Wd, Hh - 0.12, Dd, 0.07), { axis: 'y', k: 1.14 }), lac, col, { pos: [0, 0.1 + (Hh - 0.12) / 2, 0] }));
  // wrap-around racing stripes
  for (let i = 0; i < 3; i++) g.add(tm(K.box(Wd * (1.02 + i * 0.03), 0.045, Dd * (1.02 + i * 0.03), 0.014), lac, [PAL.cream, PAL.burntOrange, PAL.chocolate][i], { pos: [0, 0.26 + i * 0.07, 0] }));
  // counter top + buzzer
  g.add(tm(K.box(Wd * 1.2, 0.08, Dd * 1.18, 0.035), lac, PAL.harvestGold, { pos: [0, Hh + 0.02, -0.01] }));
  g.add(tm(K.box(Wd * 1.14, 0.03, Dd * 1.1, 0.012), lac, PAL.chocolate, { pos: [0, Hh + 0.07, -0.01] }));
  g.add(K.m(K.cyl(0.1, 0.11, 0.035, { seg: 14, bevel: 0.01 }), chrome, { pos: [0.18, Hh + 0.08, 0.02] }));
  const buzzer = K.m(tg(K.lathe([[0, 0], [0.085, 0], [0.085, 0.02], [0.07, 0.06], [0.03, 0.085], [0, 0.09]], { round: 0.01, seg: 14, steps: 1 }), PAL.channelRed), lac, { pos: [0.18, Hh + 0.11, 0.02] });
  buzzer.userData.noMerge = true;
  g.add(buzzer);
  // front number plate + chaser frame
  const fz = -Dd * 1.07 / 2;
  const plateTex = cv(`podium_plate_${num}`, 256, 192, (ctx, w, h) => {
    rrect(ctx, 0, 0, w, h, 26); ctx.fillStyle = PAL.cream; ctx.fill();
    ctx.save(); rrect(ctx, 0, 0, w, h, 26); ctx.clip();
    [PAL.burntOrange, PAL.harvestGold, PAL.channelRed].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(0, h - 40 + i * 12, w, 9); });
    ctx.restore();
    const st = starPts(w / 2, 78, 64, 28, 5); poly(ctx, st); ctx.fillStyle = grad(ctx, 0, 14, 0, 142, ['#FFF2B0', '#FFC23A', '#E8862A']); ctx.fill(); ctx.lineWidth = 6; ctx.strokeStyle = '#6A3A12'; ctx.stroke();
    text(ctx, String(num), w / 2, 88, { font: FONT.round, size: 64, fill: '#3A1E2E' });
    text(ctx, 'CONTESTANT', w / 2, 158, { font: FONT.sign, size: 20, fill: '#3A1E2E', maxW: w * 0.8 });
  });
  g.add(tm(K.box(0.56, 0.44, 0.04, 0.012), lac, PAL.chocolate, { pos: [0, 0.6, fz - 0.02] }));
  g.add(K.m(decalGeo(0.46, 0.345), K.mat(game, 'lacquer', '#ffffff', { map: plateTex }), { pos: [0, 0.6, fz - 0.043] }));
  const frame = [];
  for (let i = 0; i < 7; i++) frame.push([-0.25 + i * (0.5 / 6), 0.6 + 0.2]);
  for (let i = 1; i < 4; i++) frame.push([-0.25, 0.8 - i * 0.1]);
  for (let i = 6; i >= 0; i--) frame.push([-0.25 + i * (0.5 / 6), 0.6 - 0.2]);
  for (let i = 1; i < 4; i++) frame.push([0.25, 0.4 + i * 0.1]);
  const bulbs = instanced(bulbGeo(0.017), K.glow(game, '#ffffff', 1), frame.map(([x, y]) => ({ pos: [x, y, fz - 0.045] })), frame.map((_, i) => hdr(PAL.marqueeGold, i % 2 ? 2.8 : 1.4)), 'bulbs');
  g.add(bulbs);
  // score window (flip digits)
  const score = opts.score ?? '$130';
  const bez = K.extrude(K.roundRect(0.62, 0.22, 0.05), 0.05, { bevel: 0.015 });
  g.add(tm(bez, lac, '#2A1810', { pos: [0, Hh - 0.14, fz - 0.03] }));
  const strip = K.m(toteStripGeo(score, 0.11, 0.145, 0.125), K.glow(game, '#ffffff', 1.05, { map: getCard('tote_digits') }), { pos: [0, Hh - 0.14, fz - 0.056] });
  strip.userData.noMerge = true;
  g.add(strip);
  const u = g.userData;
  u.parts = { score: strip, buzzer, bulbs };
  u.chase = { count: frame.length, on: PAL.marqueeGold, dim: '#5A3A22' };
  u.score = score;
  u.colliders = [{ min: [-0.52, 0, -0.4], max: [0.52, Hh + 0.1, 0.4] }];
  return K.finish(game, g, { ao: { res: 48 } });
}, { category: CAT, tags: ['studio_a', 'stage', 'podium', 'game_show'], size: [1.0, 1.15, 0.72], desc: 'game-show contestant podium with flip-digit score', cache: false });

export function setPodiumScore(prop, str) {
  const m = prop?.userData?.parts?.score;
  if (!m) return;
  const n = m.geometry.attributes.uv.count / 4;
  setStrip(m, String(str).padStart(n, ' ').slice(-n));
  prop.userData.score = str;
}

// ---------------------------------------------------------------------------------------- ghost_light
// Theatre ghost light (toy_ghost_light): caged bare bulb on a pipe stand with a weighted caster base, taped cord.
// parts.bulb (setGhostLight(prop, on, game)). lightAnchors[0] = the bulb (warm #FFE0A8).
registerProp('ghost_light', (game) => {
  const g = K.prop('ghost_light');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const brass = K.mat(game, 'brass', '#C8963C');
  const rubber = K.mat(game, 'rubber', '#2A2230');
  const BY = 1.72;
  g.add(tm(K.lathe([[0, 0.06], [0.3, 0.06], [0.32, 0.09], [0.3, 0.13], [0.2, 0.16], [0.07, 0.19], [0.05, 0.25], [0, 0.25]], { round: 0.02, seg: 20, steps: 1 }), lac, '#3A2A48'));
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.5;
    const x = Math.cos(a) * 0.24, z = Math.sin(a) * 0.24;
    g.add(K.m(K.cyl(0.03, 0.03, 0.03, { seg: 8 }), chrome, { pos: [x, 0.045, z] }));
    const wh = K.cyl(0.03, 0.03, 0.022, { seg: 12, bevel: 0.008 }).clone(); wh.rotateZ(Math.PI / 2); wh.rotateY(a);
    g.add(K.m(wh, rubber, { pos: [x, 0.03, z] }));
  }
  g.add(K.m(K.cyl(0.022, 0.022, BY - 0.35, { seg: 12 }), chrome, { pos: [0, 0.22, 0] }));
  g.add(K.m(K.lathe([[0, 0], [0.034, 0], [0.036, 0.02], [0.036, 0.06], [0.03, 0.08], [0, 0.08]], { round: 0.01, seg: 12 }), chrome, { pos: [0, 0.95, 0] }));
  // tape band with label
  const tape = cv('ghost_tape', 256, 64, (ctx, w, h) => {
    ctx.fillStyle = '#E8E0C8'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = 'rgba(0,0,0,0.06)'; for (let i = 0; i < 40; i++) ctx.fillRect(i * 7, 0, 1, h);
    text(ctx, 'GHOST LIGHT · DO NOT UNPLUG', w / 2, h / 2 + 2, { font: FONT.hand, size: 22, fill: '#2A2A8A', maxW: w * 0.95, rot: -0.02 });
  });
  const tapeG = new THREE.CylinderGeometry(0.027, 0.027, 0.09, 16, 1, true);
  g.add(K.m(tapeG, K.mat(game, 'paint', '#ffffff', { map: tape }), { pos: [0, 1.25, 0] }));
  // socket + bulb + cage
  g.add(K.m(K.lathe([[0, 0], [0.03, 0], [0.042, 0.03], [0.045, 0.1], [0.036, 0.12], [0, 0.12]], { round: 0.01, seg: 14 }), brass, { pos: [0, BY - 0.18, 0] }));
  const bulb = K.m(K.lathe([[0, 0], [0.024, 0.005], [0.03, 0.03], [0.07, 0.09], [0.078, 0.13], [0.06, 0.19], [0, 0.205]], { round: 0.02, seg: 18 }), K.glow(game, '#FFE0A8', 4.5), { pos: [0, BY - 0.07, 0], cast: false });
  bulb.userData.noMerge = true;
  bulb.userData.noOcclude = true;
  g.add(bulb);
  const cageR = 0.13, cy0 = BY - 0.09, cy1 = BY + 0.2;
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * TAU;
    const pts = [[Math.cos(a) * 0.05, cy0, Math.sin(a) * 0.05], [Math.cos(a) * cageR, cy0 + 0.07, Math.sin(a) * cageR], [Math.cos(a) * cageR, cy1 - 0.07, Math.sin(a) * cageR], [Math.cos(a) * 0.03, cy1, Math.sin(a) * 0.03]];
    g.add(K.m(K.tube(pts, 0.005, { seg: 12, radial: 4 }), chrome));
  }
  g.add(K.m(K.tube(ringPts(cageR, 18, 0), 0.006, { seg: 24, radial: 4, closed: true }), chrome, { pos: [0, BY + 0.06, 0] }));
  g.add(K.m(K.tube([[-0.06, 0, 0], [-0.06, 0.07, 0], [0.06, 0.07, 0], [0.06, 0, 0]], 0.008, { seg: 14, radial: 5 }), chrome, { pos: [0, cy1, 0] }));
  // cord down the pole, coiled on the floor, plug
  const cord = [[0.03, BY - 0.12, 0], [0.035, 1.3, 0.005], [0.03, 0.6, 0.02], [0.08, 0.26, 0.05], [0.28, 0.02, 0.12]];
  for (let i = 0; i < 10; i++) { const a = i * 0.7; cord.push([0.45 + Math.cos(a) * 0.16, 0.012 + i * 0.001, 0.1 + Math.sin(a) * 0.11]); }
  cord.push([0.7, 0.012, -0.05], [0.85, 0.012, -0.12]);
  g.add(K.m(K.tube(cord, 0.009, { seg: 34, radial: 4 }), rubber));
  g.add(tm(K.box(0.05, 0.03, 0.07, 0.01), lac, '#E8E0C8', { pos: [0.87, 0.016, -0.14] }));
  const u = g.userData;
  u.parts = { bulb };
  u.lightAnchors = [{ pos: [0, BY + 0.03, 0], color: '#FFE0A8', intensity: 3, distance: 8 }];
  u.colliders = [{ min: [-0.2, 0, -0.2], max: [0.2, BY + 0.28, 0.2] }];
  u.interact = { point: [0, 1.0, -0.2], radius: 1.2 };
  return K.finish(game, g, { ao: { res: 48 } });
}, { category: CAT, tags: ['studio_a', 'stage', 'toy', 'light'], size: [0.64, 2.0, 0.64], desc: 'caged bare-bulb ghost light on a caster stand', hero: true });

// on=false swaps the bulb to an unlit frosted-glass material (pass game the first time).
export function setGhostLight(prop, on, game = null) {
  const b = prop?.userData?.parts?.bulb;
  if (!b) return;
  const u = prop.userData;
  if (!u._bulbOn) u._bulbOn = b.material;
  if (!u._bulbOff && game) u._bulbOff = K.mat(game, 'ceramic', '#E8E0D0');
  b.material = on || !u._bulbOff ? u._bulbOn : u._bulbOff;
}

// ---------------------------------------------------------------------------------------- pledge_carousel
// The Carousel: round telethon pledge desk (outer radius 2.0 m, 1.0 m tall, ring open in the middle for the
// tote_board_tower) with 12 rotary phones facing out, pledge slips and a ring lamp per phone.
// parts.handsets: InstancedMesh(12) (base matrices in userData.phones), parts.lamps: InstancedMesh(12).
// ringPhone(prop, i, t) rattles handset i and blinks its lamp (call per frame while ringing; t = seconds).
registerProp('pledge_carousel', (game) => {
  const g = K.prop('pledge_carousel');
  const RO = 2.0, RI = 1.2, H = 1.0;
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const plastic = K.mat(game, 'plastic', '#ffffff');
  const atlas = cv('carousel_atlas', 512, 512, (ctx, w, h) => {
    // [0,0]-[256,256]: rotary dial face
    const cx = 128, cy = 128;
    ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(cx, cy, 124, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#B8B0A0'; ctx.lineWidth = 4; ctx.stroke();
    for (let i = 0; i < 10; i++) {
      const a = -Math.PI * 0.35 - (i / 10) * Math.PI * 1.55;
      const x = cx + Math.cos(a) * 84, y = cy + Math.sin(a) * 84;
      ctx.fillStyle = '#2A2230'; ctx.beginPath(); ctx.arc(x, y, 22, 0, TAU); ctx.fill();
      ctx.fillStyle = '#F6E7C8'; ctx.beginPath(); ctx.arc(x, y, 17, 0, TAU); ctx.fill();
      text(ctx, String((i + 1) % 10), x, y + 1, { font: FONT.round, size: 20, fill: '#2A2230' });
    }
    ctx.fillStyle = PAL.channelRed; ctx.beginPath(); ctx.arc(cx, cy, 34, 0, TAU); ctx.fill();
    text(ctx, '13', cx, cy + 2, { font: FONT.round, size: 30, fill: '#F4F1E8' });
    // [256,0]-[512,256]: pledge slip
    ctx.fillStyle = '#FFFBEF'; ctx.fillRect(256, 0, 256, 256);
    ctx.fillStyle = PAL.channelRed; ctx.fillRect(256, 0, 256, 40);
    text(ctx, 'PLEDGE', 384, 22, { font: FONT.sign, size: 26, fill: '#fff' });
    ctx.fillStyle = 'rgba(60,90,200,0.35)'; for (let y = 70; y < 250; y += 26) ctx.fillRect(270, y, 228, 2);
    text(ctx, '$13', 330, 110, { font: FONT.hand, size: 34, fill: '#2A2A8A', rot: -0.1 });
    // [0,256]-[512,448]: apron band (repeats around)
    const by = 256, bh = 192;
    ctx.fillStyle = PAL.cream; ctx.fillRect(0, by, w, bh);
    [[PAL.chocolate, 0, 10], [PAL.burntOrange, 12, 14], [PAL.harvestGold, 28, 10]].forEach(([c, y, hh]) => { ctx.fillStyle = c; ctx.fillRect(0, by + y, w, hh); ctx.fillRect(0, by + bh - y - hh, w, hh); });
    for (let i = 0; i < 2; i++) {
      const x0 = i * 256 + 128;
      ctx.fillStyle = PAL.wztvBlue; ctx.beginPath(); ctx.arc(x0 - 70, by + bh / 2, 38, 0, TAU); ctx.fill();
      ctx.strokeStyle = PAL.channelRed; ctx.lineWidth = 8; ctx.stroke();
      text(ctx, '13', x0 - 70, by + bh / 2 + 3, { font: FONT.round, size: 40, fill: '#F4F1E8' });
      text(ctx, 'PLEDGE', x0 + 38, by + bh / 2 - 14, { font: FONT.sign, size: 34, fill: PAL.channelRed, maxW: 140 });
      text(ctx, 'NOW!', x0 + 38, by + bh / 2 + 24, { font: FONT.groovy, size: 30, fill: PAL.burntOrange, maxW: 120 });
    }
  });
  atlas.wrapS = THREE.RepeatWrapping;
  const atlasMat = K.mat(game, 'lacquer', '#ffffff', { map: atlas });
  // plinth, apron band, counter top, inner wall
  g.add(tm(K.lathe([[RI + 0.1, 0], [RO - 0.08, 0], [RO - 0.06, 0.1], [RI + 0.1, 0.1]], { seg: 64 }), lac, '#2A1810'));
  const band = new THREE.CylinderGeometry(RO - 0.03, RO - 0.03, 0.76, 72, 1, true);
  K.uvRect(band, 0, 64 / 512, 1, 256 / 512);
  K.uvScale(band, 6, 1);
  g.add(K.m(band, atlasMat, { pos: [0, 0.1 + 0.38, 0] }));
  g.add(tm(K.lathe([[RO - 0.06, 0.08], [RO + 0.02, 0.1], [RO + 0.02, 0.14], [RO - 0.06, 0.15]], { round: 0.02, seg: 64 }), lac, PAL.harvestGold));
  g.add(tm(K.lathe([[RI - 0.04, H - 0.07], [RO + 0.07, H - 0.07], [RO + 0.1, H - 0.05], [RO + 0.1, H - 0.02], [RO + 0.07, H], [RI - 0.02, H], [RI - 0.05, H - 0.02], [RI - 0.05, H - 0.05], [RI - 0.04, H - 0.07]], { seg: 48 }), lac, PAL.burntOrange));
  g.add(K.m(K.tube(ringPts(RO + 0.1, 40), 0.022, { seg: 64, radial: 5, closed: true }), chrome, { pos: [0, H - 0.035, 0] }));
  g.add(tm(K.lathe([[RI, H - 0.07], [RI, 0.02]], { seg: 48 }), lac, PAL.teal));
  g.add(tm(K.lathe([[RO - 0.03, 0.86], [RO + 0.01, 0.88], [RO + 0.01, 0.93], [RO - 0.03, 0.93]], { seg: 64 }), lac, PAL.chocolate));

  // phone parts (built once, cloned per station)
  const bodyG = K.taper(K.box(0.22, 0.1, 0.25, 0.035), { axis: 'y', k: 0.72 });
  bodyG.translate(0, 0.05, 0);
  const humpG = K.box(0.15, 0.05, 0.12, 0.014).clone(); humpG.translate(0, 0.11, 0.035);
  const dialG = new THREE.CircleGeometry(0.056, 20); dialG.rotateY(Math.PI); K.uvRect(dialG, 0, 0.5, 0.5, 1);
  const slipG = K.uvRect(decalGeo(0.1, 0.13), 0.5, 0.5, 1, 1).rotateX(-Math.PI / 2);
  const prongG = K.box(0.026, 0.05, 0.03, 0.006);
  // handset (instanced): grip + ear/mouth cups, lying along x
  const hsParts = [K.tube([[-0.1, 0, 0], [-0.05, 0.025, 0], [0.05, 0.025, 0], [0.1, 0, 0]], 0.019, { seg: 10, radial: 7 }).clone()];
  for (const s of [-1, 1]) {
    const cup = K.lathe([[0, 0], [0.036, 0], [0.038, 0.02], [0.02, 0.045], [0, 0.046]], { round: 0.008, seg: 12 }).clone();
    cup.rotateX(Math.PI); cup.translate(s * 0.1, 0.012, 0);
    hsParts.push(cup);
  }
  const hsGeo = mergeGeos(hsParts);
  const colors = [PAL.cream, PAL.channelRed, PAL.harvestGold, PAL.cream, '#2A2230', PAL.avocado];
  const phones = [], hsXf = [], lampXf = [];
  for (let i = 0; i < 12; i++) {
    const th = (i / 12) * TAU + Math.PI / 12;
    const rot = -th - Math.PI / 2;
    const st = new THREE.Group();
    st.position.set(Math.cos(th) * 1.6, H, Math.sin(th) * 1.6);
    st.rotation.y = rot;
    st.scale.setScalar(1.22);
    const c = colors[i % colors.length];
    st.add(tm(bodyG, plastic, c), tm(humpG, plastic, c));
    const dial = K.m(dialG, atlasMat, { pos: [0, 0.075, -0.098] });
    dial.rotation.x = 0.62;
    st.add(dial);
    const slip = K.m(slipG, atlasMat, { pos: [0.2, 0.004, -0.02] });
    slip.rotation.y = 0.2 * ((i % 3) - 1);
    st.add(slip);
    // coiled cord from the body side to the handset end
    const cord = [];
    const a0 = V3(-0.11, 0.03, 0.0), a1 = V3(-0.2, 0.02, 0.02), a2 = V3(-0.16, 0.1, 0.05), a3 = V3(-0.1, 0.15, 0.035);
    const curve = new THREE.CubicBezierCurve3(a0, a1, a2, a3);
    for (let k = 0; k <= 26; k++) { const t = k / 26, p = curve.getPoint(t), a = t * TAU * 6; cord.push([p.x + Math.cos(a) * 0.009, p.y + Math.sin(a) * 0.009, p.z]); }
    st.add(tm(K.tube(cord, 0.0045, { seg: 18, radial: 3 }), plastic, '#2A2230'));
    st.add(K.m(K.cyl(0.006, 0.008, 0.16, { seg: 6 }), chrome, { pos: [-0.13, 0, -0.08] }));
    g.add(st);
    st.updateMatrix();
    const hp = V3(0, 0.165, 0.035).applyMatrix4(st.matrix);
    const hq = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, rot, 0));
    hsXf.push({ pos: hp.toArray(), quat: hq, scale: 1.22 });
    phones.push({ pos: hp.toArray(), rotY: rot, color: c });
    lampXf.push({ pos: V3(-0.13, 0.17, -0.08).applyMatrix4(st.matrix).toArray(), scale: 1.2 });
  }
  const handsets = instanced(hsGeo, plastic, hsXf, phones.map((p) => p.color), 'handsets');
  const lampGeo = new THREE.SphereGeometry(0.028, 10, 8);
  const lamps = instanced(lampGeo, K.glow(game, '#ffffff', 1), lampXf, lampXf.map((_, i) => hdr(PAL.onAirRed, i % 4 === 1 ? 3 : 0.35)), 'lamps');
  g.add(handsets, lamps);

  const u = g.userData;
  u.parts = { handsets, lamps };
  u.phones = phones;
  const s = 1.42;
  u.colliders = [
    { min: [-RO - 0.1, 0, -0.85], max: [RO + 0.1, H, 0.85] },
    { min: [-0.85, 0, -RO - 0.1], max: [0.85, H, RO + 0.1] },
    { min: [-s, 0, -s], max: [s, H, s] },
  ];
  return K.finish(game, g, { ao: { res: 64, dist: 0.35 } });
}, { category: CAT, tags: ['studio_a', 'telethon', 'desk', 'phones'], size: [4.2, 1.2, 4.2], desc: 'round telethon pledge desk with 12 rotary phones', hero: true });

function mergeGeos(list) {
  const prep = list.map((g0) => {
    const g = g0.index ? g0.toNonIndexed() : g0.clone();
    for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
    if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
    return g;
  });
  const out = BGU.mergeGeometries(prep, false);
  prep.forEach((g) => g.dispose());
  return out;
}

const _m4 = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _s = new THREE.Vector3(1, 1, 1), _p = new THREE.Vector3();
export function ringPhone(prop, i, t = 0, ringing = true) {
  const u = prop?.userData;
  const hs = u?.parts?.handsets, lamps = u?.parts?.lamps, ph = u?.phones?.[i];
  if (!hs || !ph) return;
  const k = ringing ? Math.sin(t * 60) * 0.5 + 0.5 : 0;
  _p.fromArray(ph.pos); _p.y += k * 0.012;
  _e.set(0, ph.rotY + (ringing ? Math.sin(t * 47) * 0.06 : 0), ringing ? Math.sin(t * 53) * 0.08 : 0);
  _q.setFromEuler(_e);
  hs.setMatrixAt(i, _m4.compose(_p, _q, _s.setScalar(1.22)));
  hs.instanceMatrix.needsUpdate = true;
  if (lamps) { lamps.setColorAt(i, hdr(PAL.onAirRed, ringing && Math.floor(t * 6) % 2 === 0 ? 3.2 : 0.35)); lamps.instanceColor.needsUpdate = true; }
}

// ---------------------------------------------------------------------------------------- tote_board_tower
// 4-sided telethon tote board tower (ee_tote_board), 3.2 m: flip-digit totals ($12,987, tote_digits atlas) on every
// face, a $13,000 goal thermometer per face, chaser crown and a spinning "13" topper. Stands in the carousel ring.
// parts: digits_0..3 (strip meshes), thermo_0..3 (fill pivots, scale.y = value/13000), bulbs (InstancedMesh),
// topper (rotate .rotation.y). setToteValue(prop, 12988), setToteGlow(prop, game, level 0..1).
registerProp('tote_board_tower', (game, opts = {}) => {
  const g = K.prop('tote_board_tower');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const glass = game.mats.glass('#DDEFFF', { opacity: 0.14 });
  const W = 1.34;
  const value = opts.value ?? 12987;
  const str = fmtTote(value);
  const panel = cv('tote_panels2', 512, 512, (ctx, w, h) => {
    // A [0,0 200x392] thermometer panel
    rrect(ctx, 4, 4, 192, 384, 22); ctx.fillStyle = PAL.cream; ctx.fill();
    ctx.lineWidth = 5; ctx.strokeStyle = PAL.harvestGold; ctx.stroke();
    rrect(ctx, 12, 12, 176, 58, 14); ctx.fillStyle = PAL.channelRed; ctx.fill();
    text(ctx, 'GOAL', 100, 30, { font: FONT.sign, size: 22, fill: '#FFF4DC' });
    text(ctx, '$13,000', 100, 55, { font: FONT.round, size: 24, fill: '#FFF4DC', maxW: 160 });
    const y0 = 337, y1 = 92;
    for (let i = 0; i <= 13; i++) {
      const y = lerp(y0, y1, i / 13), big = i % 5 === 0 || i === 13;
      ctx.fillStyle = '#5A3A22'; ctx.fillRect(big ? 104 : 110, y - 2, big ? 30 : 16, 4);
      if (i === 0 || i === 5 || i === 10 || i === 13) text(ctx, `$${i}K`, 138, y, { font: FONT.round, size: 17, fill: '#5A3A22', align: 'left' });
    }
    text(ctx, 'HELP US STAY ON!', 36, 215, { font: FONT.sign, size: 15, fill: PAL.wztvBlue, rot: -Math.PI / 2, maxW: 230 });
    // B [200,0 150x228] call card
    rrect(ctx, 204, 4, 142, 220, 16); ctx.fillStyle = PAL.wztvBlue; ctx.fill();
    ctx.lineWidth = 4; ctx.strokeStyle = PAL.harvestGold; ctx.stroke();
    text(ctx, 'CALL', 275, 40, { font: FONT.sign, size: 30, fill: '#F4F1E8' });
    text(ctx, 'NOW!', 275, 76, { font: FONT.groovy, size: 34, fill: PAL.marqueeGold, stroke: '#1B2F7A', lw: 4 });
    rrect(ctx, 226, 104, 98, 60, 12); ctx.fillStyle = '#F4F1E8'; ctx.fill();
    text(ctx, '☎', 275, 136, { font: FONT.round, size: 44, fill: PAL.channelRed });
    text(ctx, '555-1313', 275, 196, { font: FONT.round, size: 24, fill: '#F4F1E8', maxW: 130 });
    // C [200,236 312x58] header
    rrect(ctx, 202, 238, 308, 54, 14); ctx.fillStyle = PAL.harvestGold; ctx.fill();
    text(ctx, 'TOTAL PLEDGED', 356, 266, { font: FONT.sign, size: 28, fill: '#3A1E2E', maxW: 290 });
    // D [0,400 280x112] crown band
    ctx.fillStyle = PAL.wztvBlue; ctx.fillRect(0, 400, 280, 112);
    ctx.fillStyle = PAL.channelRed; ctx.fillRect(0, 400, 280, 10); ctx.fillRect(0, 502, 280, 10);
    text(ctx, 'WZTV 13', 140, 438, { font: FONT.sign, size: 36, fill: '#F4F1E8', stroke: '#1B2F7A', lw: 5, maxW: 250 });
    text(ctx, 'Telethon', 140, 478, { font: FONT.groovy, size: 30, fill: PAL.marqueeGold, stroke: '#1B2F7A', lw: 4, maxW: 250 });
  });
  const px = (x, y, w, h) => [x / 512, 1 - (y + h) / 512, (x + w) / 512, 1 - y / 512];
  const panelMat = K.mat(game, 'lacquer', '#ffffff', { map: panel });
  const digitsMat = K.glow(game, '#ffffff', 1.1, { map: getCard('tote_digits') });
  // hidden plinth inside the desk ring, column, cornice bands
  g.add(tm(K.box(W - 0.1, 0.95, W - 0.1, 0.05), lac, '#2A1810', { pos: [0, 0.475, 0] }));
  g.add(tm(K.box(W, 1.95, W, 0.09), lac, PAL.chocolate, { pos: [0, 0.95 + 0.975, 0] }));
  g.add(tm(K.box(W + 0.08, 0.08, W + 0.08, 0.035), lac, PAL.harvestGold, { pos: [0, 0.98, 0] }));
  g.add(tm(K.box(W + 0.06, 0.06, W + 0.06, 0.028), lac, PAL.harvestGold, { pos: [0, 2.1, 0] }));
  // crown: flared cap with the WZTV band + chasers
  g.add(tm(K.taper(K.box(W + 0.02, 0.5, W + 0.02, 0.07), { axis: 'y', k: 1.12 }), lac, PAL.wztvBlue, { pos: [0, 2.95, 0] }));
  g.add(tm(K.box(W + 0.24, 0.08, W + 0.24, 0.035), lac, PAL.channelRed, { pos: [0, 3.22, 0] }));
  g.add(tm(K.box(W - 0.1, 0.07, W - 0.1, 0.03), lac, PAL.chocolate, { pos: [0, 3.28, 0] }));
  const parts = {};
  const bulbXf = [];
  for (let side = 0; side < 4; side++) {
    const sg = new THREE.Group();
    sg.rotation.y = side * (Math.PI / 2);
    const fz = -W / 2;
    // thermometer panel + tube + fill
    sg.add(K.m(decalGeo(0.46, 0.9, px(0, 0, 200, 392)), panelMat, { pos: [-0.3, 1.55, fz - 0.004] }));
    sg.add(tm(K.box(0.52, 0.96, 0.03, 0.02), lac, PAL.harvestGold, { pos: [-0.3, 1.55, fz + 0.005] }));
    const tx = -0.25;
    const tube = new THREE.CapsuleGeometry(0.04, 0.56, 4, 10);
    sg.add(K.m(tube, glass, { pos: [tx, 1.52, fz - 0.06] }));
    sg.add(K.m(new THREE.SphereGeometry(0.075, 12, 8), glass, { pos: [tx, 1.17, fz - 0.06] }));
    const redM = K.glow(game, '#FF3B30', 1.25);
    sg.add(K.m(new THREE.SphereGeometry(0.06, 10, 7), redM, { pos: [tx, 1.17, fz - 0.06] }));
    const fill = new THREE.Group();
    fill.position.set(tx, 1.2, fz - 0.06);
    const fc = K.cyl(0.026, 0.026, 0.59, { seg: 10, bevel: 0.01 });
    fill.add(K.m(fc, redM));
    fill.scale.y = clamp(value / 13000, 0.02, 1);
    fill.userData.noMerge = true;
    sg.add(fill);
    parts[`thermo_${side}`] = fill;
    for (const y of [1.3, 1.84]) sg.add(K.m(K.box(0.12, 0.03, 0.05, 0.01), chrome, { pos: [tx, y, fz - 0.03] }));
    // pledge-now card beside the thermometer
    sg.add(tm(K.box(0.5, 0.9, 0.035, 0.03), lac, PAL.cream, { pos: [0.3, 1.55, fz - 0.005] }));
    sg.add(K.m(decalGeo(0.44, 0.67, px(200, 0, 150, 228)), panelMat, { pos: [0.3, 1.55, fz - 0.025] }));
    // digit board
    sg.add(tm(K.box(1.24, 0.46, 0.06, 0.04), lac, '#2A1810', { pos: [0, 2.42, fz - 0.01] }));
    sg.add(tm(K.box(1.3, 0.52, 0.03, 0.03), lac, PAL.harvestGold, { pos: [0, 2.42, fz + 0.01] }));
    sg.add(K.m(decalGeo(0.7, 0.13, px(200, 236, 312, 58)), panelMat, { pos: [0, 2.72, fz - 0.03] }));
    sg.add(tm(K.box(0.74, 0.16, 0.03, 0.03), lac, PAL.chocolate, { pos: [0, 2.72, fz - 0.012] }));
    const strip = K.m(toteStripGeo(str, 0.15, 0.2, 0.162), digitsMat, { pos: [0, 2.4, fz - 0.043] });
    strip.userData.noMerge = true;
    sg.add(strip);
    parts[`digits_${side}`] = strip;
    // crown band decal
    sg.add(K.m(decalGeo(0.9, 0.36, px(0, 400, 280, 112)), panelMat, { pos: [0, 2.95, fz - 0.07] }));
    g.add(sg);
    for (let b = 0; b < 9; b++) {
      const x = -0.64 + b * 0.16;
      const p = V3(x, 3.22, fz - 0.14).applyAxisAngle(UP, side * (Math.PI / 2));
      bulbXf.push({ pos: p.toArray(), rot: [0, side * (Math.PI / 2), 0] });
    }
  }
  const bulbs = instanced(bulbGeo(0.035), K.glow(game, '#ffffff', 1), bulbXf, bulbXf.map((_, i) => hdr(PAL.marqueeGold, i % 2 ? 3 : 1.4)), 'bulbs');
  g.add(bulbs);
  // spinning 13 topper
  const top = cv('tote_topper', 256, 256, (ctx, w, h) => {
    ctx.fillStyle = PAL.channelRed; ctx.beginPath(); ctx.arc(128, 128, 126, 0, TAU); ctx.fill();
    ctx.fillStyle = PAL.wztvBlue; ctx.beginPath(); ctx.arc(128, 128, 100, 0, TAU); ctx.fill();
    text(ctx, '13', 128, 136, { font: FONT.round, size: 130, fill: '#F4F1E8', stroke: '#1B2F7A', lw: 8 });
  });
  const topMat = K.mat(game, 'lacquer', '#ffffff', { map: top });
  g.add(K.m(K.cyl(0.03, 0.035, 0.3, { seg: 10 }), chrome, { pos: [0, 3.25, 0] }));
  const topper = new THREE.Group();
  topper.position.set(0, 3.78, 0);
  topper.add(tm(K.cyl(0.32, 0.32, 0.07, { seg: 32, bevel: 0.025 }).clone().rotateX(Math.PI / 2).translate(0, 0, -0.035), lac, PAL.harvestGold));
  const c1 = new THREE.CircleGeometry(0.29, 32); c1.rotateY(Math.PI);
  topper.add(K.m(c1, topMat, { pos: [0, 0, -0.037] }));
  topper.add(K.m(new THREE.CircleGeometry(0.29, 32), topMat, { pos: [0, 0, 0.037] }));
  K.merge(topper);
  topper.userData.noMerge = true;
  g.add(topper);
  parts.bulbs = bulbs; parts.topper = topper;
  const u = g.userData;
  u.parts = parts;
  u.tote = { value, goal: 13000 };
  u.colliders = [{ min: [-W / 2 - 0.05, 0, -W / 2 - 0.05], max: [W / 2 + 0.05, 3.3, W / 2 + 0.05] }];
  u.lightAnchors = [{ pos: [0, 2.4, 0], color: PAL.gelAmber, intensity: 1.6, distance: 5 }];
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['studio_a', 'telethon', 'ee', 'tote'], size: [1.6, 4.1, 1.6], desc: '4-sided telethon tote board tower with flip digits and goal thermometers', hero: true, cache: false });

function fmtTote(v) {
  if (typeof v === 'string') return v;
  const s = Math.round(v).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return ('$' + s).padStart(7, ' ').slice(-7);
}
export function setToteValue(prop, value) {
  const u = prop?.userData;
  if (!u?.parts) return;
  const s = fmtTote(value);
  for (let i = 0; i < 4; i++) setStrip(u.parts[`digits_${i}`], s);
  const k = clamp((typeof value === 'number' ? value : 0) / (u.tote?.goal || 13000), 0.02, 1);
  for (let i = 0; i < 4; i++) if (u.parts[`thermo_${i}`]) u.parts[`thermo_${i}`].scale.y = k;
  if (u.tote) u.tote.value = value;
}
// level 0..1: before power the digits only glow faintly (0.3)
export function setToteGlow(prop, game, level = 1) {
  const u = prop?.userData;
  if (!u?.parts || !game) return;
  const m = K.glow(game, '#ffffff', 0.25 + 0.85 * clamp(level, 0, 1), { map: getCard('tote_digits') });
  for (let i = 0; i < 4; i++) if (u.parts[`digits_${i}`]) u.parts[`digits_${i}`].material = m;
}

// ---------------------------------------------------------------------------------------- bleacher_block
// Studio-audience bleacher block: 3 carpeted tiers (0.45/0.9/1.35 m), molded 70s bucket seats (InstancedMesh,
// alternating colors), stepped end panels with racing stripes, abandoned foam "13" fingers and popcorn tubs.
// opts: { width=8, depth=2.5, seed=1 }. Colliders: the 3 tiers (walkable high ground).
registerProp('bleacher_block', (game, opts = {}) => {
  const g = K.prop('bleacher_block');
  const W = opts.width ?? 8, D = opts.depth ?? 2.5, seed = opts.seed ?? 1;
  const rnd = mulberry32(seed * 131 + 7);
  const HT = [0.45, 0.9, 1.35], td = D / 3;
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const carpet = K.mat(game, 'fabric', '#ffffff', { map: K.tex.shag('#8A3A22', '#D9A520'), rim: 0.12, wrap: 0.5 });
  const vinyl = K.mat(game, 'vinyl', '#ffffff');
  for (let t = 0; t < 3; t++) {
    const z0 = -D / 2 + t * td;
    const depth = D - t * td;
    g.add(K.m(K.box(W - 0.12, HT[t], depth, 0.03, { uv: 2.2 }), carpet, { pos: [0, HT[t] / 2, z0 + depth / 2] }));
    g.add(K.m(K.box(W - 0.1, 0.04, 0.05, 0.015), chrome, { pos: [0, HT[t] - 0.01, z0 + 0.02] }));
  }
  // stepped end panels (70s stripes)
  const stepShape = (inset) => {
    const pts = [[-D / 2 + inset, inset], [D / 2 - inset, inset], [D / 2 - inset, HT[2] + 0.08 - inset]];
    for (let t = 2; t >= 0; t--) { const z = -D / 2 + t * td + inset; pts.push([z, HT[t] + 0.08 - inset]); if (t > 0) pts.push([z, HT[t - 1] + 0.08 - inset]); }
    return pts;
  };
  for (const s of [-1, 1]) {
    const x = s * (W / 2 - 0.03);
    const add = (inset, th, col, dx) => {
      const geo = K.extrude(stepShape(inset), th, { bevel: Math.min(0.02, th * 0.4), round: 0.04 });
      geo.rotateY(-Math.PI / 2);
      g.add(tm(geo, lac, col, { pos: [x + s * dx, 0, 0] }));
    };
    add(0, 0.08, PAL.chocolate, 0);
    add(0.07, 0.03, PAL.burntOrange, 0.05);
    add(0.13, 0.03, PAL.harvestGold, 0.07);
    add(0.19, 0.03, PAL.cream, 0.09);
  }
  // upholstered 70s theater seats (instanced: upholstery tinted per seat + dark frame) on a chrome beam per tier
  const seatGeo = mergeGeos([
    K.box(0.5, 0.11, 0.44, 0.045, { seg: 1 }).clone().translate(0, 0.42, -0.02),
    (() => { const b = K.box(0.5, 0.5, 0.11, 0.045, { seg: 1 }).clone(); b.rotateX(-0.12); b.translate(0, 0.72, 0.21); return b; })(),
  ]);
  const frameGeo = mergeGeos([
    K.box(0.07, 0.3, 0.42, 0.025, { seg: 1 }).clone().translate(0.28, 0.52, 0.02),
    K.box(0.12, 0.36, 0.12, 0.02, { seg: 1 }).clone().translate(0, 0.18, 0.04),
  ]);
  const pitch = 0.56;
  const n = Math.max(1, Math.floor((W - 0.5) / pitch));
  const xf = [], cols = [];
  const palette = [PAL.burntOrange, PAL.harvestGold];
  const seatPos = [];
  for (let t = 0; t < 3; t++) {
    const z = -D / 2 + t * td + td * 0.4;
    for (let i = 0; i < n; i++) {
      const x = (i - (n - 1) / 2) * pitch;
      xf.push({ pos: [x, HT[t], z], rot: [0, (rnd() - 0.5) * 0.04, 0] });
      cols.push(palette[(i + t) % 2]);
      seatPos.push([x, HT[t] + 0.48, z - 0.03]);
    }
    g.add(K.m(K.cyl(0.03, 0.03, n * pitch + 0.1, { seg: 8 }).clone().rotateZ(Math.PI / 2).translate((n * pitch + 0.1) / 2, 0, 0), chrome, { pos: [0, HT[t] + 0.1, z + 0.04] }));
  }
  const seats = instanced(seatGeo, vinyl, xf, cols, 'seats');
  const frames = instanced(frameGeo, K.mat(game, 'plastic', '#3A2A30'), xf, null, 'seat_frames');
  g.add(seats, frames);
  // foam fingers + popcorn tubs on random seats / steps
  const foamTex = cv('foam_13', 128, 128, (ctx, w, h) => {
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w, h);
    text(ctx, '13', w / 2, h / 2 + 4, { font: FONT.round, size: 88, fill: PAL.wztvBlue, stroke: '#fff', lw: 2 });
  });
  const foam = K.mat(game, 'felt', '#ffffff');
  const foamPrint = K.mat(game, 'felt', '#ffffff', { map: foamTex });
  const stripeTex = cv('popcorn_stripes', 128, 64, (ctx, w, h) => {
    for (let i = 0; i < 8; i++) { ctx.fillStyle = i % 2 ? '#F4F1E8' : PAL.channelRed; ctx.fillRect(i * 16, 0, 16, h); }
    ctx.fillStyle = PAL.wztvBlue; ctx.fillRect(0, 22, w, 20);
    text(ctx, 'POPCORN', w / 2, 33, { font: FONT.sign, size: 13, fill: '#fff', maxW: w * 0.9 });
  }, true);
  const tub = K.mat(game, 'paint', '#ffffff', { map: stripeTex });
  const cornMat = K.mat(game, 'plastic', '#ffffff');
  const used = new Set();
  const pick = () => { let k; do { k = Math.floor(rnd() * seatPos.length); } while (used.has(k) && used.size < seatPos.length); used.add(k); return seatPos[k]; };
  const fingerCols = [PAL.channelRed, PAL.harvestGold, PAL.wztvBlue];
  for (let f = 0; f < 3; f++) {
    const [x, y, z] = pick();
    const fg = new THREE.Group();
    const c = fingerCols[f % 3];
    fg.add(tm(K.cushion(0.2, 0.22, 0.08, { puff: 0.015 }), foam, c, { pos: [0, 0.11, 0] }));
    fg.add(tm(new THREE.CapsuleGeometry(0.04, 0.2, 4, 10), foam, c, { pos: [0.05, 0.35, 0] }));
    fg.add(tm(new THREE.CapsuleGeometry(0.035, 0.08, 4, 8), foam, c, { pos: [-0.1, 0.16, -0.01], rot: [0, 0, 0.9] }));
    for (const dx of [-0.02, -0.07]) fg.add(tm(new THREE.SphereGeometry(0.045, 10, 8), foam, c, { pos: [dx, 0.22, -0.01] }));
    fg.add(tm(K.cyl(0.08, 0.075, 0.1, { seg: 14, bevel: 0.02 }), foam, '#F4F1E8', { pos: [0, -0.08, 0], scale: [1.2, 1, 0.6] }));
    fg.add(K.m(decalGeo(0.15, 0.15), foamPrint, { pos: [0, 0.1, -0.046] }));
    if (f === 0) { fg.position.set(x, y + 0.14, z); fg.rotation.set(-0.15, (rnd() - 0.5) * 0.8, 0.1); } else { fg.position.set(x, y + 0.05, z); fg.rotation.set(-Math.PI / 2 + 0.2, rnd() * TAU, 0); }
    g.add(fg);
  }
  for (let p = 0; p < 3; p++) {
    const [x, y, z] = pick();
    const pg = new THREE.Group();
    pg.add(K.m(K.lathe([[0, 0], [0.07, 0], [0.1, 0.2], [0.095, 0.205], [0, 0.205]], { seg: 16 }), tub));
    const pr = mulberry32(seed * 17 + p);
    for (let k = 0; k < 14; k++) {
      const a = pr() * TAU, r = Math.sqrt(pr()) * 0.08;
      const kk = new THREE.IcosahedronGeometry(0.024 + pr() * 0.01, 0);
      pg.add(tm(kk, cornMat, pr() < 0.2 ? '#F4D06A' : '#FFF6DC', { pos: [Math.cos(a) * r, 0.2 + pr() * 0.04 + (0.08 - r) * 0.4, Math.sin(a) * r] }));
    }
    if (p === 2) {
      pg.rotation.z = Math.PI / 2 - 0.1; pg.position.set(x, y + 0.02, z);
      for (let k = 0; k < 10; k++) pg.add(tm(new THREE.IcosahedronGeometry(0.022, 0), cornMat, '#FFF6DC', { pos: [0.05 + pr() * 0.06, 0.22 + pr() * 0.25, (pr() - 0.5) * 0.25] }));
    } else pg.position.set(x + 0.1, y, z - 0.05);
    g.add(pg);
  }
  const u = g.userData;
  u.parts = { seats };
  u.colliders = HT.map((h, t) => ({ min: [-W / 2, 0, -D / 2 + t * td], max: [W / 2, h, D / 2] }));
  return K.finish(game, g, { ao: { res: 72, dist: 0.4 } });
}, { category: CAT, tags: ['studio_a', 'audience', 'bleachers'], size: [8, 2.0, 2.5], desc: '3-tier studio audience bleachers with foam fingers and popcorn', hero: true });

// ---------------------------------------------------------------------------------------- disco_ball
// Mirror ball on a motor, hung from the lighting grid, with two pin-spots aimed at it.
// Local origin = bottom of the mirror ball (ball center y=0.45, grid mount plate y=1.45). parts.ball (rotate .y).
// userData.spots = [{ pos, target }] for SpotLights; discoSpeckTexture() gives a speck cookie for SpotLight.map.
registerProp('disco_ball', (game) => {
  const g = K.prop('disco_ball');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const paint = K.mat(game, 'paint', '#ffffff');
  const tiles = cv('disco_tiles', 512, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#3A3848'; ctx.fillRect(0, 0, w, h);
    const nx = 40, ny = 20, tw = w / nx, th = h / ny;
    for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
      const v = 150 + rand() * 105;
      const tint = rand();
      ctx.fillStyle = tint < 0.08 ? `rgb(${v},${v * 0.8},${v})` : tint < 0.14 ? `rgb(${v * 0.8},${v * 0.9},${v})` : `rgb(${v},${v},${v})`;
      ctx.fillRect(i * tw + 1, j * th + 1, tw - 2, th - 2);
      ctx.fillStyle = 'rgba(255,255,255,0.5)'; ctx.fillRect(i * tw + 1, j * th + 1, tw - 2, 1.5);
    }
  });
  const mirror = K.mat(game, 'chrome', '#ffffff', { map: tiles, flat: true, rough: 0.12 });
  const BY = -1.0, R = 0.45;
  g.add(K.m(K.cyl(0.12, 0.12, 0.03, { seg: 16 }), chrome, { pos: [0, -0.03, 0] }));
  g.add(K.m(K.cyl(0.015, 0.015, 0.3, { seg: 8 }), chrome, { pos: [0, -0.33, 0] }));
  g.add(tm(K.lathe([[0, 0], [0.08, 0], [0.09, 0.04], [0.09, 0.1], [0.06, 0.14], [0, 0.14]], { round: 0.015, seg: 16 }), paint, '#2A2230', { pos: [0, -0.48, 0] }));
  const ball = new THREE.Group();
  ball.position.set(0, BY, 0);
  ball.add(K.m(new THREE.SphereGeometry(R, 28, 18), mirror));
  ball.add(K.m(K.cyl(0.006, 0.006, 0.08, { seg: 6 }), chrome, { pos: [0, R - 0.02, 0] }));
  ball.userData.noMerge = true;
  g.add(ball);
  g.add(K.m(K.cyl(0.004, 0.004, 0.44, { seg: 5 }), chrome, { pos: [0, BY + R + 0.05, 0] }));
  // clamp pipe + pin spots
  g.add(K.m(K.cyl(0.024, 0.024, 2.0, { seg: 10 }).clone().rotateZ(Math.PI / 2).translate(1.0, 0, 0), chrome, { pos: [0, -0.06, 0] }));
  const spots = [];
  for (const s of [-1, 1]) {
    const mount = V3(s * 0.85, -0.06, 0);
    const pos = V3(s * 0.85, -0.3, 0.05);
    const target = V3(0, BY, 0);
    const can = new THREE.Group();
    can.position.copy(pos);
    can.lookAt(target);
    can.add(tm(K.cyl(0.065, 0.075, 0.22, { seg: 14, bevel: 0.015 }).clone().rotateX(Math.PI / 2).translate(0, 0, -0.08), paint, '#2A2230'));
    const lens = new THREE.CircleGeometry(0.052, 16);
    can.add(K.m(lens, K.glow(game, '#FFF2D8', 3), { pos: [0, 0, 0.142] }));
    g.add(can);
    g.add(tm(K.box(0.03, 0.26, 0.03, 0.008), paint, '#2A2230', { pos: [s * 0.85, -0.18, 0.03] }));
    g.add(K.m(K.cyl(0.035, 0.035, 0.05, { seg: 10 }).clone().rotateZ(Math.PI / 2), chrome, { pos: mount.toArray() }));
    spots.push({ pos: pos.toArray(), target: target.toArray() });
  }
  // origin = bottom of the ball (placing it at y = 6.5 puts the mount plate at 7.95, just under an 8 m ceiling)
  const OFF = -BY + R;
  for (const c of g.children) c.position.y += OFF;
  for (const sp of spots) { sp.pos[1] += OFF; sp.target[1] += OFF; }
  const u = g.userData;
  u.parts = { ball };
  u.spots = spots;
  u.anchors = { mount: [0, OFF, 0], ball: [0, R, 0] };
  u.colliders = [];
  return K.finish(game, g, { ao: AO_HANG });
}, { category: CAT, tags: ['studio_a', 'hanging', 'disco'], size: [2.0, 1.5, 0.9], desc: 'mirror ball on a motor with two pin-spots (hangs from the grid)' });

export function discoSpeckTexture() {
  return K.tex.canvas('sets.disco_specks', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 160; i++) {
      const x = rand() * w, y = rand() * h, r = 1.5 + rand() * 3;
      const gr = ctx.createRadialGradient(x, y, 0, x, y, r * 2);
      gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.5, 'rgba(255,255,255,0.6)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = gr; ctx.fillRect(x - r * 2, y - r * 2, r * 4, r * 4);
    }
  }, { repeat: false });
}

// ---------------------------------------------------------------------------------------- applause_sign
// APPLAUSE light box (ee_applause_sign) on two hanger rods. Local origin = bottom of the box (y=0), the rods rise
// opts.drop (0.6) above it to a ceiling plate. parts.face -> setApplause(prop, game, on).
function applauseFace(lit) {
  return cv(`applause_${lit ? 'on' : 'off'}`, 512, 128, (ctx, w, h) => {
    ctx.fillStyle = lit ? '#FF5A3C' : '#8A2A2E'; ctx.fillRect(0, 0, w, h);
    const gr = ctx.createRadialGradient(w / 2, h / 2, 10, w / 2, h / 2, w / 2);
    gr.addColorStop(0, lit ? 'rgba(255,230,180,0.55)' : 'rgba(255,120,100,0.12)'); gr.addColorStop(1, 'rgba(0,0,0,0.25)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h);
    text(ctx, 'APPLAUSE', w / 2, h / 2 + 4, { font: FONT.sign, size: 92, fill: lit ? '#FFF6E0' : '#D8B8A0', stroke: lit ? '#FFD0A0' : '#4A1418', lw: lit ? 3 : 4, maxW: w * 0.92, track: 2 });
  });
}
registerProp('applause_sign', (game, opts = {}) => {
  const g = K.prop('applause_sign');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const Wd = 1.9, Hh = 0.56, Dd = 0.32, drop = opts.drop ?? 0.6;
  g.add(tm(K.box(Wd, Hh, Dd, 0.09), lac, '#2A1D2A', { pos: [0, Hh / 2, 0] }));
  const fr = K.roundRect(Wd - 0.04, Hh - 0.04, 0.07);
  fr.holes.push(new THREE.Path(K.roundRect(Wd - 0.2, Hh - 0.18, 0.04).getPoints(6)));
  g.add(K.m(K.extrude(fr, 0.05, { bevel: 0.018, bevelSeg: 2, curveSeg: 6 }), chrome, { pos: [0, Hh / 2, -Dd / 2 - 0.005] }));
  const face = K.m(decalGeo(Wd - 0.19, Hh - 0.17), K.mat(game, 'lacquer', '#ffffff', { map: applauseFace(false) }), { pos: [0, Hh / 2, -Dd / 2 - 0.012] });
  face.userData.noMerge = true;
  g.add(face);
  for (let i = 0; i < 6; i++) g.add(tm(K.box(0.03, 0.14, 0.02, 0.008), lac, '#15101A', { pos: [-0.3 + i * 0.12, Hh / 2, Dd / 2 + 0.002] }));
  for (const s of [-1, 1]) {
    g.add(K.m(K.cyl(0.016, 0.016, drop, { seg: 8 }), chrome, { pos: [s * (Wd / 2 - 0.25), Hh - 0.02, 0] }));
    g.add(K.m(K.lathe([[0, 0], [0.05, 0], [0.05, 0.02], [0.03, 0.04], [0, 0.04]], { seg: 12 }), chrome, { pos: [s * (Wd / 2 - 0.25), Hh - 0.02, 0] }));
    g.add(K.m(K.cyl(0.07, 0.07, 0.025, { seg: 14 }), chrome, { pos: [s * (Wd / 2 - 0.25), Hh + drop - 0.025, 0] }));
  }
  g.add(K.m(K.tube([[0.3, Hh, 0.05], [0.35, Hh + 0.15, 0.08], [0.2, Hh + 0.35, 0.05], [0.26, Hh + drop, 0.02]], 0.01, { seg: 16, radial: 5 }), K.mat(game, 'rubber', '#2A2230')));
  const u = g.userData;
  u.parts = { face };
  u.colliders = [];
  return K.finish(game, g, { ao: AO_HANG });
}, { category: CAT, tags: ['studio_a', 'ee', 'sign', 'hanging'], size: [1.9, 1.2, 0.36], desc: 'APPLAUSE light box on hanger rods' });

export function setApplause(prop, game, on) {
  const f = prop?.userData?.parts?.face;
  if (!f || !game) return;
  f.material = on ? K.glow(game, '#ffffff', 1.25, { map: applauseFace(true) }) : K.mat(game, 'lacquer', '#ffffff', { map: applauseFace(false) });
}

// ---------------------------------------------------------------------------------------- chroma_cyc
// Chroma-key blue cyclorama (Studio B east wall): curved sweep into the floor on a plywood frame, cyc-light batten,
// taped spike X on the floor. opts: { width=4.0, height=3.6 }. Back of the sweep at local z = +0.35 (wall side).
registerProp('chroma_cyc', (game, opts = {}) => {
  const g = K.prop('chroma_cyc');
  const W = opts.width ?? 4.0, Hh = opts.height ?? 3.6, R = 0.9, ZB = 0.35, front = 0.7;
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const teak = K.mat(game, 'teak', '#ffffff', { map: K.tex.wood('#C8A06A', { dark: 0.25 }) });
  const blueTex = cv('cyc_blue', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = PAL.chromaBlue; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 30; i++) { ctx.fillStyle = `rgba(${rand() < 0.5 ? '255,255,255' : '10,20,80'},0.02)`; ctx.fillRect(rand() * w, 0, 10 + rand() * 30, h); }
    speckle(ctx, w, h, rand, 500, 0.035);
  }, true);
  const blue = K.mat(game, 'paint', '#ffffff', { map: blueTex, rough: 0.85 });
  // profile: floor apron -> quarter circle -> vertical
  const prof = [[ZB - R - front, 0.004], [ZB - R, 0.004]];
  for (let i = 1; i <= 12; i++) { const t = (i / 12) * (Math.PI / 2); prof.push([ZB - R + R * Math.sin(t), R - R * Math.cos(t)]); }
  prof.push([ZB, Hh]);
  const L = [0];
  for (let i = 1; i < prof.length; i++) L.push(L[i - 1] + Math.hypot(prof[i][0] - prof[i - 1][0], prof[i][1] - prof[i - 1][1]));
  const pos = [], uv = [], idx = [];
  const nxs = 4;
  for (let k = 0; k < prof.length; k++) for (let i = 0; i <= nxs; i++) {
    const x = (i / nxs - 0.5) * W;
    pos.push(x, prof[k][1], prof[k][0]);
    uv.push((i / nxs) * W / 1.5, L[k] / 1.5);
  }
  for (let k = 0; k < prof.length - 1; k++) for (let i = 0; i < nxs; i++) {
    const a = k * (nxs + 1) + i, b = a + 1, c = a + nxs + 1, d = c + 1;
    idx.push(a, c, b, b, c, d);
  }
  const sweep = new THREE.BufferGeometry();
  sweep.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  sweep.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  sweep.setIndex(idx);
  sweep.computeVertexNormals();
  g.add(K.m(sweep, blue));
  // side frames (plywood edge showing) + back skin
  const side = [...prof.slice(1).map(([z, y]) => [z, y]), [ZB + 0.12, Hh], [ZB + 0.12, 0]];
  for (const s of [-1, 1]) {
    const geo = K.extrude(side.map(([z, y]) => [z, y]), 0.06, { bevel: 0.012 });
    geo.rotateY(-Math.PI / 2);
    g.add(K.m(K.uvScale(geo, 2, 2), teak, { pos: [s * (W / 2 + 0.03), 0, 0] }));
    // stage brace + sandbag
    g.add(tm(K.cushion(0.36, 0.16, 0.26, { puff: 0.03 }), lac, '#6A5A3A', { pos: [s * (W / 2 + 0.25), 0.08, ZB - 0.2] }));
  }
  g.add(tm(K.box(W + 0.1, Hh, 0.04, 0.012), lac, '#8A7A60', { pos: [0, Hh / 2, ZB + 0.1] }));
  // cyc-light batten with three floods
  g.add(K.m(K.cyl(0.024, 0.024, W + 0.3, { seg: 10 }).clone().rotateZ(Math.PI / 2).translate((W + 0.3) / 2, 0, 0), chrome, { pos: [0, Hh + 0.25, -0.35] }));
  for (let i = 0; i < 3; i++) {
    const x = (i - 1) * (W / 3);
    const fl = new THREE.Group();
    fl.position.set(x, Hh + 0.1, -0.35);
    fl.rotation.x = 0.7;
    fl.add(tm(K.taper(K.box(0.42, 0.26, 0.24, 0.03), { axis: 'z', k: 0.8 }), lac, '#2A2230'));
    fl.add(K.m(decalGeo(0.34, 0.18), K.glow(game, '#E8F0FF', 2.2), { pos: [0, 0, -0.125] }));
    g.add(fl);
    g.add(K.m(K.cyl(0.012, 0.012, 0.15, { seg: 6 }), chrome, { pos: [x, Hh + 0.12, -0.35] }));
  }
  // taped spike X + T marks
  const tape = cv('cyc_tape', 128, 128, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    ctx.lineCap = 'butt';
    for (const [a, c] of [[0.785, '#FF5FA2'], [-0.785, '#FF5FA2']]) {
      ctx.save(); ctx.translate(w / 2, h / 2); ctx.rotate(a);
      ctx.fillStyle = c; ctx.fillRect(-58, -9, 116, 18);
      ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.fillRect(-58, -9, 116, 3);
      ctx.restore();
    }
  });
  const tapeMat = K.mat(game, 'plastic', '#ffffff', { map: tape, alphaTest: 0.5, transparent: false });
  const xg = new THREE.PlaneGeometry(0.7, 0.7); xg.rotateX(-Math.PI / 2);
  g.add(K.m(xg, tapeMat, { pos: [0.2, 0.008, ZB - R - 0.2] }));
  const tg2 = new THREE.PlaneGeometry(0.3, 0.3); tg2.rotateX(-Math.PI / 2);
  g.add(K.m(tg2, tapeMat, { pos: [-1.2, 0.008, ZB - R - 0.45], rot: [0, 0.3, 0] }));
  const u = g.userData;
  u.anchors = { mark: [0.2, 0, ZB - R - 0.2] };
  u.colliders = [{ min: [-W / 2 - 0.1, 0, ZB - 0.3], max: [W / 2 + 0.1, Hh, ZB + 0.15] }];
  u.lightAnchors = [{ pos: [0, Hh - 0.2, -0.6], color: '#DDE8FF', intensity: 1.6, distance: 5 }];
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['studio_b', 'chroma', 'backdrop'], size: [4.6, 3.9, 2.1], desc: 'chroma-key blue cyclorama with a taped X' });

// =========================================================================================================
// STUDIO B — HOOTIE'S HULLABALOO
// =========================================================================================================

// vertex colors by normal: faces whose normal is mostly along `axis` get capColor, the rest sideColor
function tintByNormal(geo, capColor, sideColor, axis = 2, th = 0.7) {
  const g = geo.index ? geo.toNonIndexed() : geo.clone();
  g.computeVertexNormals();
  const n = g.attributes.normal, cA = new THREE.Color(capColor), cB = new THREE.Color(sideColor);
  const col = new Float32Array(n.count * 3);
  for (let i = 0; i < n.count; i++) {
    const v = Math.abs(n.getComponent(i, axis)) > th ? cA : cB;
    col[i * 3] = v.r; col[i * 3 + 1] = v.g; col[i * 3 + 2] = v.b;
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  return g;
}
function flameShape(w, h, lean = 0) {
  return [[-w / 2, 0], [w / 2, 0], [w * 0.42, h * 0.35], [w * 0.18 + lean, h * 0.62], [w * 0.1 + lean * 1.4, h], [-w * 0.05 + lean, h * 0.7], [-w * 0.3, h * 0.45], [-w * 0.42, h * 0.3]];
}

// ---------------------------------------------------------------------------------------- cardboard_rocket
// 5.5 m kids'-show cardboard rocket (the Studio B loop pillar, radius 1.4 with fins): 12 painted cardboard
// panels, masking tape, marker rivets, "HOOTIE-1" hand lettering, porthole with Hootie peeking, cardboard fins
// with corrugated edges, crepe-paper flames. Colliders: a pillar square + fin cross.
registerProp('cardboard_rocket', (game) => {
  const g = K.prop('cardboard_rocket');
  const bodyTex = cv('rocket_body', 512, 512, (ctx, w, h, rand) => {
    ctx.fillStyle = '#E9E4D6'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 260; i++) { ctx.fillStyle = `rgba(${rand() < 0.5 ? '255,255,255' : '150,140,120'},0.08)`; ctx.fillRect(rand() * w, rand() * h, 30 + rand() * 60, 2 + rand() * 3); }
    const pw = w / 12;
    // red bands with stars (v: top of canvas = top of body)
    for (const [y, hh] of [[34, 46], [h - 96, 50]]) {
      ctx.fillStyle = PAL.channelRed; ctx.fillRect(0, y, w, hh);
      ctx.fillStyle = 'rgba(0,0,0,0.12)'; for (let i = 0; i < 30; i++) ctx.fillRect(rand() * w, y, 2, hh);
      for (let i = 0; i < 12; i++) { poly(ctx, starPts(i * pw + pw / 2, y + hh / 2, 13, 5.5)); ctx.fillStyle = '#FFF4DC'; ctx.fill(); }
    }
    // kraft cardboard showing at the panel seams + tape strips across seams
    for (let i = 0; i <= 12; i++) {
      const x = i * pw;
      ctx.fillStyle = '#B98A55'; ctx.fillRect(x - 3, 0, 6, h);
      ctx.fillStyle = 'rgba(80,50,20,0.35)'; ctx.fillRect(x - 1, 0, 2, h);
      for (let k = 0; k < 4; k++) {
        const y = 60 + rand() * (h - 120);
        ctx.save(); ctx.translate(x, y); ctx.rotate((rand() - 0.5) * 0.2);
        ctx.fillStyle = 'rgba(232,214,160,0.92)'; ctx.fillRect(-14, -5, 28, 10);
        ctx.fillStyle = 'rgba(160,130,80,0.25)'; ctx.fillRect(-14, -5, 28, 2);
        ctx.restore();
      }
      if (i % 3 === 0) for (let y = 110; y < h - 110; y += 44) { ctx.fillStyle = '#5A5A6A'; ctx.beginPath(); ctx.arc(x + 9, y, 2.4, 0, TAU); ctx.fill(); }
    }
    // hand-painted vertical HOOTIE-1 (front panels ~ u 0.70..0.80 face -z) and a door outline on the back
    const fx = w * 0.64;
    'HOOTIE-1'.split('').forEach((ch, i) => text(ctx, ch, fx + Math.sin(i * 1.7) * 2, 120 + i * 38, { font: FONT.round, size: 40, fill: PAL.wztvBlue, stroke: '#F4F1E8', lw: 3, rot: (rand() - 0.5) * 0.15 }));
    ctx.strokeStyle = '#3A2A48'; ctx.lineWidth = 4; ctx.setLineDash([10, 6]);
    rrect(ctx, w * 0.2, 250, 70, 150, 30); ctx.stroke(); ctx.setLineDash([]);
    ctx.fillStyle = '#D8A83A'; ctx.beginPath(); ctx.arc(w * 0.2 + 58, 330, 6, 0, TAU); ctx.fill();
    // brush streaks
    for (let i = 0; i < 90; i++) { ctx.strokeStyle = `rgba(255,255,255,${0.05 + rand() * 0.06})`; ctx.lineWidth = 1 + rand() * 2; const x = rand() * w, y = rand() * h; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + 20 + rand() * 40, y + (rand() - 0.5) * 6); ctx.stroke(); }
  }, true);
  const noseTex = cv('rocket_nose', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = PAL.channelRed; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 160; i++) { ctx.strokeStyle = `rgba(${rand() < 0.5 ? '255,200,180' : '90,10,20'},0.12)`; ctx.lineWidth = 1 + rand() * 3; const x = rand() * w, y = rand() * h; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + 10 + rand() * 30, y + 6 + rand() * 10); ctx.stroke(); }
    for (let i = 0; i <= 8; i++) { ctx.fillStyle = '#9A6A3A'; ctx.fillRect(i * (w / 8) - 2, 0, 4, h); }
    for (let i = 0; i < 8; i++) { ctx.fillStyle = 'rgba(232,214,160,0.9)'; ctx.fillRect(i * (w / 8) - 10, 60 + (i % 3) * 50, 20, 9); }
  }, true);
  const paint = K.mat(game, 'paint', '#ffffff', { map: bodyTex, flat: true });
  const nosePaint = K.mat(game, 'paint', '#ffffff', { map: noseTex, flat: true });
  const card = K.mat(game, 'paint', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#C0C6D0');
  const glass = game.mats.glass('#CFE8FF', { opacity: 0.3 });
  // body: 12 flat cardboard panels
  const body = new THREE.LatheGeometry([[0.74, 0], [0.8, 0.5], [0.82, 1.2], [0.8, 2.2], [0.72, 3.2]].map(([r, y]) => new THREE.Vector2(r, y)), 12);
  K.uvScale(body, 1, 1);
  g.add(K.m(body, paint, { pos: [0, 0.55, 0] }));
  g.add(tm(K.lathe([[0.7, 0], [0.8, 0], [0.8, 0.06], [0.7, 0.06]], { seg: 12 }), card, '#B98A55', { pos: [0, 0.5, 0] }));
  // nose cone (12 panels) + foil ball
  const nose = new THREE.LatheGeometry([[0.74, 0], [0.7, 0.35], [0.55, 0.85], [0.3, 1.3], [0.06, 1.62]].map(([r, y]) => new THREE.Vector2(r, y)), 12);
  g.add(K.m(nose, nosePaint, { pos: [0, 3.73, 0] }));
  g.add(K.m(new THREE.IcosahedronGeometry(0.11, 1), K.mat(game, 'chrome', '#D8DCE4', { flat: true }), { pos: [0, 5.38, 0] }));
  g.add(tm(K.lathe([[0.76, 0], [0.78, 0.04], [0.76, 0.1], [0.7, 0.1]], { seg: 12 }), card, '#E9E4D6', { pos: [0, 3.68, 0] }));
  // porthole with Hootie peeking
  const peek = cv('rocket_peek', 256, 256, (ctx, w, h) => {
    ctx.fillStyle = '#1B1E4A'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 30; i++) { ctx.fillStyle = '#FFF4D6'; ctx.fillRect((i * 97) % w, (i * 53) % h, 3, 3); }
    ctx.fillStyle = '#8A5A3A'; ctx.beginPath(); ctx.ellipse(128, 170, 90, 80, 0, 0, TAU); ctx.fill();
    for (const s of [-1, 1]) {
      ctx.fillStyle = '#8A5A3A'; poly(ctx, [[128 + s * 50, 110], [128 + s * 86, 60], [128 + s * 84, 130]]); ctx.fill();
      ctx.fillStyle = '#FFF8E8'; ctx.beginPath(); ctx.arc(128 + s * 36, 150, 30, 0, TAU); ctx.fill();
      ctx.fillStyle = '#2A1D3A'; ctx.beginPath(); ctx.arc(128 + s * 32, 152, 14, 0, TAU); ctx.fill();
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(128 + s * 28, 146, 5, 0, TAU); ctx.fill();
    }
    ctx.fillStyle = '#F4A020'; poly(ctx, [[116, 180], [140, 180], [128, 204]]); ctx.fill();
  });
  const pz = -0.815, py = 2.75;
  const ph = new THREE.CircleGeometry(0.3, 24); ph.rotateY(Math.PI);
  g.add(K.m(ph, K.mat(game, 'paint', '#ffffff', { map: peek }), { pos: [0, py, pz + 0.01] }));
  const ring = new THREE.TorusGeometry(0.33, 0.05, 8, 24);
  g.add(K.m(ring, chrome, { pos: [0, py, pz - 0.01] }));
  for (let i = 0; i < 8; i++) { const a = (i / 8) * TAU; g.add(K.m(new THREE.SphereGeometry(0.018, 6, 4), chrome, { pos: [Math.cos(a) * 0.33, py + Math.sin(a) * 0.33, pz - 0.055] })); }
  const lens = new THREE.CircleGeometry(0.3, 24); lens.rotateY(Math.PI);
  g.add(K.m(lens, glass, { pos: [0, py, pz - 0.02] }));
  // fins (cardboard: painted faces, kraft corrugated edges) with yellow stars
  const finShape = [[0, 0.1], [0.62, -0.05], [0.66, 0.2], [0.34, 1.25], [0, 1.7]];
  const starTex = cv('rocket_star', 128, 128, (ctx, w, h) => { poly(ctx, starPts(64, 66, 58, 24)); ctx.fillStyle = PAL.barYellow; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = '#8A5A12'; ctx.stroke(); });
  const starMat = K.mat(game, 'paint', '#ffffff', { map: starTex, alphaTest: 0.5 });
  for (let i = 0; i < 4; i++) {
    const a = Math.PI / 4 + (i / 4) * TAU;
    const fin = tintByNormal(K.extrude(finShape, 0.07, { bevel: 0.015, round: 0.05 }), PAL.channelRed, '#B98A55');
    const fm = K.m(fin, card);
    fm.position.set(Math.sin(a) * 0.7, 0.35, Math.cos(a) * 0.7);
    fm.rotation.y = a - Math.PI / 2;
    g.add(fm);
    for (const sd of [-1, 1]) {
      const st = K.m(new THREE.PlaneGeometry(0.34, 0.34), starMat);
      st.position.set(0.33, 0.55, sd * 0.037);
      if (sd < 0) st.rotation.y = Math.PI;
      fm.add(st);
    }
  }
  // crepe-paper flames under the body
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * TAU;
    for (const [w, h, col, r] of [[0.42, 0.62, PAL.burntOrange, 0.62], [0.26, 0.42, PAL.barYellow, 0.6]]) {
      const f = K.m(tg(K.extrude(flameShape(w, h, (i % 2 ? 0.04 : -0.04)), 0.03, { bevel: 0.008, round: 0.03 }), col), card);
      f.position.set(Math.sin(a) * r, 0, Math.cos(a) * r);
      f.rotation.y = a;
      g.add(f);
    }
  }
  g.add(tm(K.cyl(0.66, 0.7, 0.5, { seg: 12, bevel: 0.03 }), card, '#3A2A48', { pos: [0, 0.02, 0] }));
  const u = g.userData;
  u.colliders = [{ min: [-0.95, 0, -0.95], max: [0.95, 5.5, 0.95] }, { min: [-1.3, 0, -0.3], max: [1.3, 2.0, 0.3] }, { min: [-0.3, 0, -1.3], max: [0.3, 2.0, 1.3] }];
  return K.finish(game, g, { ao: { res: 60 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'pillar', 'rocket'], size: [2.8, 5.5, 2.8], desc: '5.5 m painted cardboard rocket (HOOTIE-1)', hero: true });

// ---------------------------------------------------------------------------------------- treehouse_facade
// Hootie's treehouse facade (Studio B north flat, 5 m wide): cartoon trunk with root flares, pastel plank house,
// scalloped roof, moon night-light window, rope ladder, fairy lights, and Hootie's giant TV in the trunk base
// (screen spawn ss_studio_b: userData.screens[0] {group 'scr_decor', id 'ss_studio_b'}, center local
// [-0.5, 1.0, -0.62] -> world [26.0,1.0,-27.0] when placed at [25.5,0,-27.6] rotY=PI).
registerProp('treehouse_facade', (game, opts = {}) => {
  const g = K.prop('treehouse_facade');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const paint = K.mat(game, 'paint', '#ffffff');
  const barkTex = cv('bark', 256, 512, (ctx, w, h, rand) => {
    ctx.fillStyle = '#7A4A2A'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 26; i++) {
      const x0 = rand() * w;
      ctx.strokeStyle = rand() < 0.5 ? 'rgba(60,30,15,0.55)' : 'rgba(170,110,60,0.35)';
      ctx.lineWidth = 3 + rand() * 7;
      for (const off of [0, -w, w]) { ctx.beginPath(); for (let y = 0; y <= h; y += 16) { const x = x0 + off + Math.sin(y * 0.02 + i) * 8; if (!y) ctx.moveTo(x, y); else ctx.lineTo(x, y); } ctx.stroke(); }
    }
    for (let i = 0; i < 5; i++) { const x = rand() * w, y = rand() * h; ctx.fillStyle = 'rgba(50,25,12,0.5)'; ctx.beginPath(); ctx.ellipse(x, y, 10, 16, 0, 0, TAU); ctx.fill(); ctx.strokeStyle = 'rgba(170,110,60,0.5)'; ctx.lineWidth = 3; ctx.stroke(); }
  }, true);
  const bark = K.mat(game, 'paint', '#ffffff', { map: barkTex });
  const planks = cv('treehouse_planks', 512, 512, (ctx, w, h, rand) => {
    const cols = ['#A8D8B8', '#F6E7C8', '#F2B48A', '#9ED8C8', '#FFE0A8'];
    const bh = 64;
    for (let y = 0, r = 0; y < h; y += bh, r++) {
      let x = -rand() * 120;
      while (x < w) {
        const lw = 200 + rand() * 260, c = cols[(r + Math.floor(rand() * 2)) % cols.length];
        ctx.fillStyle = c; ctx.fillRect(x, y, lw, bh);
        ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.fillRect(x, y + 2, lw, 5);
        ctx.fillStyle = 'rgba(80,40,30,0.35)'; ctx.fillRect(x, y + bh - 4, lw, 4); ctx.fillRect(x + lw - 3, y, 3, bh);
        for (let k = 0; k < 6; k++) { ctx.strokeStyle = 'rgba(90,60,40,0.12)'; ctx.lineWidth = 1; ctx.beginPath(); const yy = y + 8 + rand() * (bh - 14); ctx.moveTo(x, yy); ctx.lineTo(x + lw, yy + (rand() - 0.5) * 4); ctx.stroke(); }
        ctx.fillStyle = '#6A5A5A'; ctx.beginPath(); ctx.arc(x + 8, y + bh / 2, 3, 0, TAU); ctx.fill(); ctx.beginPath(); ctx.arc(x + lw - 10, y + bh / 2, 3, 0, TAU); ctx.fill();
        x += lw;
      }
    }
  }, true);
  const plank = K.mat(game, 'paint', '#ffffff', { map: planks });
  const shingles = cv('treehouse_shingles', 256, 256, (ctx, w, h) => {
    ctx.fillStyle = '#8A3A5A'; ctx.fillRect(0, 0, w, h);
    for (let r = 0; r < 8; r++) for (let i = -1; i < 9; i++) {
      const x = i * 32 + (r % 2) * 16, y = r * 32;
      ctx.fillStyle = r % 2 ? '#C2407A' : '#D8467A';
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + 32, y); ctx.lineTo(x + 32, y + 18); ctx.arc(x + 16, y + 18, 16, 0, Math.PI); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = 'rgba(60,10,30,0.45)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(x + 16, y + 18, 16, 0, Math.PI); ctx.stroke();
    }
  }, true);
  const roofMat = K.mat(game, 'paint', '#ffffff', { map: shingles });
  const PY = 2.85;
  // trunk (flattened lathe, root flares) + branches
  const trunk = K.lathe([[1.25, 0], [1.05, 0.25], [0.86, 0.7], [0.78, 1.4], [0.74, 2.2], [0.8, PY + 0.2], [0.6, PY + 0.25]], { seg: 14 }).clone();
  trunk.scale(1, 1, 0.42);
  K.uvScale(trunk, 3, 2.5);
  g.add(K.m(trunk, bark, { pos: [0.35, 0, 0.12] }));
  for (const [x, z, s, r] of [[-0.8, -0.1, 0.5, 0.4], [1.45, 0.0, 0.45, -0.5], [0.9, -0.25, 0.38, 0.3]]) {
    const root = new THREE.SphereGeometry(s, 10, 6);
    root.scale(1.4, 0.45, 0.8);
    g.add(K.m(K.uvScale(root.clone(), 2, 1), bark, { pos: [x + 0.35, 0.06, z], rot: [0, r, 0] }));
  }
  for (const [pts, r] of [[[[0.9, 2.1, 0], [1.7, 2.45, -0.05], [2.35, 2.7, -0.1]], 0.12], [[[-0.2, 2.2, 0], [-1.0, 2.5, 0], [-1.8, 2.62, -0.05]], 0.11]]) {
    g.add(K.m(K.uvScale(K.tube(pts, r, { seg: 10, radial: 8 }).clone(), 4, 1), bark));
  }
  // platform deck + braces
  g.add(tm(K.box(4.8, 0.14, 0.95, 0.04), lac, '#9A6A3E', { pos: [0, PY, -0.05] }));
  for (let i = 0; i < 12; i++) g.add(tm(K.box(0.36, 0.05, 0.05, 0.008), lac, i % 2 ? '#B08050' : '#8A5A34', { pos: [-2.2 + i * 0.4, PY - 0.01, -0.52] }));
  for (const s of [-1, 1]) {
    const a = V3(s * 0.55, 1.9, -0.1), b = V3(s * 1.8, PY - 0.05, -0.1);
    const br = K.m(tg(K.box(0.1, a.distanceTo(b), 0.1, 0.025), '#8A5A34'), lac);
    br.position.copy(a).add(b).multiplyScalar(0.5); br.quaternion.setFromUnitVectors(UP, b.clone().sub(a).normalize());
    g.add(br);
  }
  // railing
  for (let i = 0; i <= 10; i++) g.add(tm(K.box(0.06, 0.5, 0.06, 0.012), lac, '#F6E7C8', { pos: [-2.3 + i * 0.46, PY + 0.32, -0.46] }));
  g.add(tm(K.box(4.72, 0.07, 0.08, 0.025), lac, PAL.channelRed, { pos: [0, PY + 0.6, -0.46] }));
  // house: plank walls, scalloped roof, round moon window, door
  const HW = 3.2, HH = 1.55, HY = PY + 0.07;
  g.add(K.m(K.box(HW, HH, 0.5, 0.05, { uv: 0.55 }), plank, { pos: [0.1, HY + HH / 2, 0.1] }));
  const roofL = 2.0;
  for (const s of [-1, 1]) {
    const rf = K.m(K.box(roofL, 0.08, 0.8, 0.03, { uv: 1.4 }), roofMat);
    rf.position.set(0.1 + s * 0.85, HY + HH + 0.48, 0.05);
    rf.rotation.z = -s * 0.52;
    g.add(rf);
  }
  g.add(tm(K.box(0.14, 0.14, 0.85, 0.045), lac, PAL.harvestGold, { pos: [0.1, HY + HH + 0.98, 0.05] }));
  const gable = K.extrude([[-HW / 2 + 0.05, 0], [HW / 2 - 0.05, 0], [0, 0.93]], 0.45, { bevel: 0.02 });
  g.add(K.m(K.uvScale(gable, 0.55, 0.55), plank, { pos: [0.1, HY + HH, 0.12] }));
  // round moon window
  const mw = new THREE.CircleGeometry(0.32, 28); mw.rotateY(Math.PI);
  g.add(K.m(mw, K.glow(game, '#9FB6FF', 0.75), { pos: [-0.7, HY + 0.85, -0.16], cast: false }));
  g.add(tm(new THREE.TorusGeometry(0.34, 0.06, 6, 24), lac, PAL.harvestGold, { pos: [-0.7, HY + 0.85, -0.17] }));
  g.add(tm(K.box(0.66, 0.04, 0.04, 0.012), lac, PAL.harvestGold, { pos: [-0.7, HY + 0.85, -0.18] }), tm(K.box(0.04, 0.66, 0.04, 0.012), lac, PAL.harvestGold, { pos: [-0.7, HY + 0.85, -0.18] }));
  const moonTex = cv('treehouse_moon', 128, 128, (ctx, w, h) => { ctx.clearRect(0, 0, w, h); ctx.fillStyle = '#FFF4D6'; ctx.beginPath(); ctx.arc(64, 64, 50, 0, TAU); ctx.fill(); ctx.globalCompositeOperation = 'destination-out'; ctx.beginPath(); ctx.arc(88, 50, 44, 0, TAU); ctx.fill(); });
  g.add(K.m(decalGeo(0.3, 0.3), K.glow(game, '#ffffff', 1.25, { map: moonTex, transparent: true }), { pos: [-0.78, HY + 0.9, -0.2], cast: false }));
  // arched door + HOOTIE sign
  const door = K.extrude([[-0.36, 0], [0.36, 0], [0.36, 0.8], [0, 1.12], [-0.36, 0.8]], 0.06, { bevel: 0.02, round: 0.2 });
  g.add(tm(door, lac, PAL.teal, { pos: [0.85, HY, -0.17] }));
  g.add(tm(new THREE.SphereGeometry(0.04, 10, 8), lac, PAL.harvestGold, { pos: [0.62, HY + 0.5, -0.21] }));
  const signTex = cv('treehouse_sign', 512, 128, (ctx, w, h) => {
    rrect(ctx, 4, 4, w - 8, h - 8, 40); ctx.fillStyle = '#FFF4DC'; ctx.fill(); ctx.lineWidth = 8; ctx.strokeStyle = '#8A5A34'; ctx.stroke();
    const cols = [PAL.channelRed, PAL.burntOrange, PAL.harvestGold, PAL.barGreen, PAL.wztvBlue, PAL.plum];
    const s = "HOOTIE'S HULLABALOO";
    ctx.font = `44px ${FONT.round}`;
    let x = w / 2 - ctx.measureText(s).width / 2;
    [...s].forEach((ch, i) => { const cw = ctx.measureText(ch).width; text(ctx, ch, x + cw / 2, h / 2 + 4 + Math.sin(i * 0.9) * 5, { font: FONT.round, size: 44, fill: cols[i % cols.length], stroke: '#3A1E2E', lw: 5, rot: Math.sin(i * 1.3) * 0.08 }); x += cw; });
  });
  const sign = K.m(decalGeo(2.2, 0.55), K.mat(game, 'paint', '#ffffff', { map: signTex }), { pos: [0.1, PY - 0.45, -0.56] });
  g.add(sign);
  g.add(tm(K.box(2.3, 0.6, 0.05, 0.03), lac, '#8A5A34', { pos: [0.1, PY - 0.45, -0.53] }));
  for (const s of [-1, 1]) g.add(tm(K.tube([[0.1 + s * 1.0, PY - 0.17, -0.55], [0.1 + s * 1.0, PY - 0.07, -0.55]], 0.012, { seg: 2, radial: 4 }), paint, '#D8B878'));
  // canopy: puffy cartoon leaf blobs behind the house
  const leafM = lac;
  const blobs = [[-2.1, 4.5, 0.25, 0.8], [-1.3, 5.0, 0.3, 0.75], [1.6, 5.05, 0.3, 0.8], [2.3, 4.4, 0.25, 0.7], [-2.35, 3.7, 0.25, 0.55], [2.55, 3.55, 0.2, 0.5], [0.4, 5.25, 0.35, 0.6]];
  blobs.forEach(([x, y, z, r], i) => {
    const s = new THREE.SphereGeometry(r, 10, 6); s.scale(1.15, 0.9, 0.55);
    g.add(tm(s, leafM, ['#6FBF4A', '#58A83E', '#8CD05A'][i % 3], { pos: [x, y, z] }));
  });
  // rope ladder
  const LX2 = 1.85;
  for (const s of [-1, 1]) g.add(tm(K.tube([[LX2 + s * 0.22, PY, -0.55], [LX2 + s * 0.23, PY * 0.5, -0.6], [LX2 + s * 0.22, 0.05, -0.62]], 0.018, { seg: 10, radial: 5 }), paint, '#D8B878'));
  for (let i = 1; i < 8; i++) g.add(tm(K.box(0.5, 0.04, 0.09, 0.012), lac, '#B08050', { pos: [LX2, i * (PY / 8), -0.6] }));
  // fairy lights along the railing
  const fl = [];
  for (let i = 0; i < 22; i++) { const t = i / 21; fl.push([-2.3 + t * 4.6, PY + 0.55 - Math.sin(t * Math.PI * 4) ** 2 * 0.12, -0.52]); }
  g.add(tm(K.tube(fl, 0.006, { seg: 40, radial: 3 }), paint, '#2A4A2A'));
  const flCols = [PAL.channelRed, PAL.harvestGold, PAL.barGreen, PAL.wztvBlue, PAL.neonPink];
  const fairy = instanced(new THREE.SphereGeometry(0.032, 6, 5), K.glow(game, '#ffffff', 1), fl.map((p) => ({ pos: [p[0], p[1] - 0.04, p[2]] })), fl.map((_, i) => hdr(flCols[i % 5], 2.2)), 'fairy');
  g.add(fairy);
  // Hootie's giant TV set into the trunk base
  const TX = -0.5, TY = 1.0, TZ = -0.6;
  g.add(tm(K.box(1.5, 1.28, 0.62, 0.12), lac, '#7A4A2A', { pos: [TX, TY - 0.02, TZ + 0.3] }));
  g.add(tm(K.box(1.36, 1.12, 0.1, 0.045), lac, '#F6E7C8', { pos: [TX, TY - 0.02, TZ + 0.02] }));
  const bez = K.roundRect(1.08, 0.84, 0.16); bez.holes.push(new THREE.Path(K.roundRect(0.96, 0.72, 0.12).getPoints(8)));
  g.add(tm(K.extrude(bez, 0.06, { bevel: 0.02, curveSeg: 6 }), lac, '#2A2230', { pos: [TX - 0.08, TY, TZ - 0.02] }));
  const scr = K.screen(game, 0.96, 0.72, { card: opts.card ?? 'hullabaloo', group: 'scr_decor', dome: 0.03 });
  scr.position.set(TX - 0.08, TY, TZ - 0.01);
  g.add(scr);
  for (let i = 0; i < 2; i++) g.add(K.m(K.cyl(0.055, 0.06, 0.05, { seg: 14, bevel: 0.012 }).clone().rotateX(-Math.PI / 2), K.mat(game, 'chrome', '#A8B0BA'), { pos: [TX + 0.56, TY + 0.18 - i * 0.2, TZ - 0.03] }));
  g.add(tm(K.box(0.14, 0.26, 0.02, 0.008), lac, '#3A3040', { pos: [TX + 0.56, TY - 0.32, TZ - 0.03] }));
  for (const s of [-1, 1]) g.add(rod(0.012, K.mat(game, 'chrome', '#A8B0BA'), [TX + s * 0.1, TY + 0.62, TZ + 0.3], [TX + s * 0.45, TY + 1.25, TZ + 0.25]));
  const u = g.userData;
  u.screens = [{ mesh: scr, group: 'scr_decor', id: opts.screenId ?? 'ss_studio_b' }];
  u.anchors = { screen_center: [TX - 0.08, TY, TZ - 0.03] };
  u.colliders = [{ min: [-2.5, 0, -0.62], max: [2.5, 5.4, 0.55] }];
  u.lightAnchors = [{ pos: [-0.7, HY + 0.85, -0.6], color: '#BFD4FF', intensity: 1.5, distance: 5 }];
  return K.finish(game, g, { ao: { res: 72 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'facade', 'screen', 'tv'], size: [5.2, 5.6, 1.2], desc: "Hootie's treehouse facade with the giant TV (screen spawn)", hero: true });

// ---------------------------------------------------------------------------------------- puppet_theater
// Red-and-yellow striped puppet playhouse (ee_puppet_theater): scalloped valance with pompoms, arched crest,
// gold proscenium, red velvet curtain (parts.curtain_l / curtain_r: pivot at the outer top corner, scale.x 1 ->
// 0.25 opens), and the navy apron with three dashed puppet silhouettes (owl, sock, dragon) + brass hooks.
// anchors.slot_owl/sock/dragon (apron hooks), anchors.stage_owl/sock/dragon (behind the curtain line).
// interact = GDD point [17.75,0,-24.9] r 1.5 when the theater is centered 0.75 m behind it.
registerProp('puppet_theater', (game) => {
  const g = K.prop('puppet_theater');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const brass = K.mat(game, 'brass', '#C8963C');
  const stripes = cv('theater_stripes', 256, 256, (ctx, w, h) => {
    for (let i = 0; i < 8; i++) { ctx.fillStyle = i % 2 ? PAL.barYellow : PAL.channelRed; ctx.fillRect(i * 32, 0, 32, h); }
    for (let i = 0; i < 8; i++) { ctx.fillStyle = 'rgba(0,0,0,0.08)'; ctx.fillRect(i * 32 + 28, 0, 4, h); ctx.fillStyle = 'rgba(255,255,255,0.12)'; ctx.fillRect(i * 32 + 2, 0, 3, h); }
  }, true);
  const stripe = K.mat(game, 'fabric', '#ffffff', { map: stripes, rim: 0.3 });
  const velvet = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#B81E3A', { pattern: 'cord', scale: 3 }) });
  const W = 2.4, D = 0.9, OB = 1.3, OT = 2.25;
  // booth: striped fabric-covered sides/top, wooden frame posts
  g.add(K.m(K.box(W, OB, D, 0.04, { uv: 1.6 }), stripe, { pos: [0, OB / 2, 0] }));
  for (const s of [-1, 1]) g.add(K.m(K.box(0.35, OT - OB + 0.02, D, 0.03, { uv: 1.6 }), stripe, { pos: [s * (W / 2 - 0.175), (OB + OT) / 2, 0] }));
  g.add(K.m(K.box(W, 0.45, D, 0.04, { uv: 1.6 }), stripe, { pos: [0, OT + 0.225, 0] }));
  for (const s of [-1, 1]) g.add(tm(K.box(0.1, OT + 0.5, 0.1, 0.03), lac, PAL.harvestGold, { pos: [s * (W / 2 + 0.02), (OT + 0.5) / 2, -D / 2 + 0.02] }));
  // playboard ledge
  g.add(tm(K.box(W + 0.16, 0.08, 0.3, 0.035), lac, '#9A6A3E', { pos: [0, OB + 0.02, -D / 2 - 0.08] }));
  g.add(tm(K.box(W + 0.08, 0.05, 0.04, 0.018), lac, PAL.harvestGold, { pos: [0, OB - 0.03, -D / 2 - 0.22] }));
  // proscenium: gold arched frame
  const pw = W - 0.7;
  const frame = new THREE.Shape();
  frame.moveTo(-pw / 2 - 0.12, OB - 0.12); frame.lineTo(pw / 2 + 0.12, OB - 0.12); frame.lineTo(pw / 2 + 0.12, OT + 0.12);
  frame.quadraticCurveTo(0, OT + 0.32, -pw / 2 - 0.12, OT + 0.12); frame.closePath();
  const hole = new THREE.Path();
  hole.moveTo(-pw / 2, OB); hole.lineTo(pw / 2, OB); hole.lineTo(pw / 2, OT - 0.02); hole.quadraticCurveTo(0, OT + 0.16, -pw / 2, OT - 0.02); hole.closePath();
  frame.holes.push(hole);
  g.add(tm(K.extrude(frame, 0.06, { bevel: 0.014, curveSeg: 12 }), lac, PAL.harvestGold, { pos: [0, 0, -D / 2 - 0.03] }));
  // backdrop (night sky) inside the opening
  const sky = cv('theater_sky', 256, 128, (ctx, w, h, rand) => {
    ctx.fillStyle = grad(ctx, 0, 0, 0, h, ['#1B1E4A', '#3A3A8A']); ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 30; i++) { poly(ctx, starPts(rand() * w, rand() * h * 0.8, 4, 1.6)); ctx.fillStyle = '#FFF4D6'; ctx.fill(); }
    ctx.fillStyle = '#FFF4D6'; ctx.beginPath(); ctx.arc(200, 34, 18, 0, TAU); ctx.fill();
    ctx.fillStyle = '#58A83E'; ctx.beginPath(); ctx.ellipse(60, h + 20, 110, 50, 0, 0, TAU); ctx.fill(); ctx.fillStyle = '#6FBF4A'; ctx.beginPath(); ctx.ellipse(200, h + 26, 110, 50, 0, 0, TAU); ctx.fill();
  });
  g.add(K.m(decalGeo(pw, OT - OB + 0.1), K.mat(game, 'paint', '#ffffff', { map: sky }), { pos: [0, (OB + OT) / 2, D / 2 - 0.1] }));
  g.add(tm(K.box(pw, 0.04, D - 0.1, 0.012), lac, '#5A3A22', { pos: [0, OB + 0.02, 0] }));
  // curtain halves (pleated velvet + gold fringe), pivot at the outer top corners
  const cw = pw / 2 + 0.03, chh = OT - OB + 0.05;
  const pleat = new THREE.PlaneGeometry(cw, chh, 18, 2);
  { const p = pleat.attributes.position; for (let i = 0; i < p.count; i++) p.setZ(i, Math.sin((p.getX(i) / cw) * Math.PI * 7) * 0.025); }
  pleat.rotateY(Math.PI);
  pleat.computeVertexNormals();
  K.uvScale(pleat, 2, 2);
  const parts = {};
  for (const s of [-1, 1]) {
    const cg = new THREE.Group();
    cg.position.set(s * (pw / 2 + 0.02), OT + 0.05, -D / 2 + 0.03);
    const geo = pleat.clone(); geo.translate(-s * cw / 2, -chh / 2, 0);
    cg.add(K.m(geo, velvet));
    cg.add(tm(K.tube([[0, -chh, 0], [-s * cw, -chh, 0]], 0.022, { seg: 2, radial: 6 }), lac, PAL.harvestGold));
    cg.add(tm(K.cyl(0.018, 0.018, 0.1, { seg: 6 }), lac, PAL.harvestGold, { pos: [-s * cw * 0.8, -chh * 0.55, -0.05] }));
    K.merge(cg);
    cg.userData.noMerge = true;
    g.add(cg);
    parts[s < 0 ? 'curtain_r' : 'curtain_l'] = cg; // viewer's left = +x
  }
  // valance: scalloped striped awning + pompoms
  const scW = W + 0.2, nS = 9;
  const sc = [[-scW / 2, 0.3], [scW / 2, 0.3], [scW / 2, 0]];
  for (let i = nS - 1; i >= 0; i--) { const x0 = -scW / 2 + (i + 1) * (scW / nS), x1 = x0 - scW / nS; for (let k = 1; k <= 6; k++) { const t = k / 6; sc.push([lerp(x0, x1, t), -Math.sin(t * Math.PI) * 0.13]); } }
  const val = K.extrude(sc, 0.05, { bevel: 0.015 });
  K.uvScale(val, 1.6, 1.6);
  g.add(K.m(val, stripe, { pos: [0, OT + 0.28, -D / 2 - 0.1], rot: [-0.12, 0, 0] }));
  for (let i = 0; i < nS; i++) g.add(tm(new THREE.SphereGeometry(0.045, 10, 8), lac, PAL.barYellow, { pos: [-scW / 2 + (i + 0.5) * (scW / nS), OT + 0.13, -D / 2 - 0.14] }));
  g.add(tm(K.box(W + 0.24, 0.08, 0.2, 0.03), lac, PAL.harvestGold, { pos: [0, OT + 0.5, -D / 2 - 0.02] }));
  // crest sign
  const crestTex = cv('theater_crest', 512, 192, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    ctx.beginPath(); ctx.moveTo(10, h - 10); ctx.quadraticCurveTo(w / 2, -40, w - 10, h - 10); ctx.closePath(); ctx.fillStyle = PAL.wztvBlue; ctx.fill(); ctx.lineWidth = 10; ctx.strokeStyle = PAL.harvestGold; ctx.stroke();
    text(ctx, "HOOTIE'S", w / 2, 88, { font: FONT.groovy, size: 46, fill: PAL.barYellow, stroke: '#1B2F7A', lw: 6 });
    text(ctx, 'PUPPET PLAYHOUSE', w / 2, 146, { font: FONT.sign, size: 34, fill: '#F4F1E8', stroke: '#1B2F7A', lw: 5, maxW: w * 0.8 });
  });
  const crest = K.extrude([[-1.05, 0], [1.05, 0], [0.9, 0.35], [0, 0.62], [-0.9, 0.35]], 0.06, { bevel: 0.02, round: 0.3 });
  g.add(tm(crest, lac, PAL.harvestGold, { pos: [0, OT + 0.54, -D / 2 + 0.02] }));
  g.add(K.m(decalGeo(2.0, 0.75), K.mat(game, 'paint', '#ffffff', { map: crestTex, alphaTest: 0.5 }), { pos: [0, OT + 0.83, -D / 2 - 0.015] }));
  g.add(tm(K.extrude(starPts(0, 0, 0.2, 0.09), 0.06, { bevel: 0.015 }), lac, PAL.barYellow, { pos: [0, OT + 1.27, -D / 2 + 0.02] }));
  // apron with the three silhouettes
  const apron = cv('theater_apron', 512, 256, (ctx, w, h) => {
    rrect(ctx, 0, 0, w, h, 30); ctx.fillStyle = '#23307A'; ctx.fill();
    ctx.lineWidth = 8; ctx.strokeStyle = PAL.harvestGold; rrect(ctx, 8, 8, w - 16, h - 16, 24); ctx.stroke();
    for (let i = 0; i < 20; i++) { poly(ctx, starPts(20 + (i * 83) % (w - 40), 20 + (i * 47) % (h - 40), 5, 2)); ctx.fillStyle = 'rgba(255,244,214,0.5)'; ctx.fill(); }
    ctx.setLineDash([12, 8]); ctx.lineWidth = 6; ctx.strokeStyle = '#FFF4DC'; ctx.fillStyle = 'rgba(255,244,214,0.12)';
    const cx = [w * 0.18, w * 0.5, w * 0.82], cy = h * 0.55;
    // owl
    ctx.beginPath(); ctx.ellipse(cx[0], cy + 10, 50, 62, 0, 0, TAU); ctx.moveTo(cx[0] - 40, cy - 34); ctx.lineTo(cx[0] - 46, cy - 72); ctx.lineTo(cx[0] - 14, cy - 50); ctx.moveTo(cx[0] + 40, cy - 34); ctx.lineTo(cx[0] + 46, cy - 72); ctx.lineTo(cx[0] + 14, cy - 50); ctx.fill(); ctx.stroke();
    ctx.beginPath(); ctx.arc(cx[0] - 20, cy - 12, 15, 0, TAU); ctx.moveTo(cx[0] + 35, cy - 12); ctx.arc(cx[0] + 20, cy - 12, 15, 0, TAU); ctx.stroke();
    // sock
    ctx.beginPath(); ctx.moveTo(cx[1] - 28, cy - 80); ctx.lineTo(cx[1] + 26, cy - 80); ctx.lineTo(cx[1] + 26, cy + 20); ctx.quadraticCurveTo(cx[1] + 26, cy + 72, cx[1] - 30, cy + 70); ctx.quadraticCurveTo(cx[1] - 74, cy + 66, cx[1] - 60, cy + 38); ctx.lineTo(cx[1] - 28, cy + 26); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(cx[1] - 28, cy - 50); ctx.lineTo(cx[1] + 26, cy - 50); ctx.moveTo(cx[1] - 28, cy - 30); ctx.lineTo(cx[1] + 26, cy - 30); ctx.stroke();
    // dragon
    ctx.beginPath(); ctx.moveTo(cx[2] - 50, cy + 60); ctx.quadraticCurveTo(cx[2] - 60, cy - 10, cx[2] - 10, cy - 30); ctx.lineTo(cx[2] - 4, cy - 70); ctx.lineTo(cx[2] + 10, cy - 40); ctx.lineTo(cx[2] + 22, cy - 76); ctx.lineTo(cx[2] + 28, cy - 36); ctx.quadraticCurveTo(cx[2] + 78, cy - 36, cx[2] + 72, cy - 6); ctx.quadraticCurveTo(cx[2] + 40, cy + 4, cx[2] + 36, cy + 20); ctx.quadraticCurveTo(cx[2] + 40, cy + 60, cx[2] + 20, cy + 60); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.beginPath(); ctx.arc(cx[2] + 36, cy - 20, 7, 0, TAU); ctx.stroke();
    ctx.setLineDash([]);
    ['?', '?', '?'].forEach((q, i) => text(ctx, q, cx[i], h - 26, { font: FONT.round, size: 26, fill: PAL.barYellow }));
  });
  const AY = 0.72, AW = 2.1, AH = 1.05;
  g.add(tm(K.box(AW + 0.08, AH + 0.08, 0.05, 0.04), lac, PAL.harvestGold, { pos: [0, AY, -D / 2 - 0.02] }));
  g.add(K.m(decalGeo(AW, AH), K.mat(game, 'paint', '#ffffff', { map: apron }), { pos: [0, AY, -D / 2 - 0.05] }));
  const slotX = [0.64, 0, -0.64].map((f) => f * AW / 2 / 0.64 * 0.64); // owl (viewer left), sock, dragon
  const anchors = {};
  ['owl', 'sock', 'dragon'].forEach((k, i) => {
    const x = [AW * 0.32, 0, -AW * 0.32][i];
    g.add(K.m(K.tube([[x, AY + 0.42, -D / 2 - 0.05], [x, AY + 0.42, -D / 2 - 0.12], [x, AY + 0.37, -D / 2 - 0.14]], 0.012, { seg: 6, radial: 5 }), brass));
    anchors[`slot_${k}`] = [x, AY + 0.35, -D / 2 - 0.14];
    anchors[`stage_${k}`] = [x * 0.8, OB + 0.1, -D / 2 + 0.15];
  });
  void slotX;
  const u = g.userData;
  u.parts = parts;
  u.anchors = anchors;
  u.interact = { point: [0, 1.0, -0.75], radius: 1.5 };
  u.colliders = [{ min: [-W / 2 - 0.1, 0, -D / 2 - 0.25], max: [W / 2 + 0.1, OT + 1.4, D / 2] }];
  return K.finish(game, g, { ao: { res: 60 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'ee', 'puppets'], size: [2.6, 3.7, 1.2], desc: 'striped puppet playhouse with curtain and three empty puppet silhouettes', hero: true });

// ---------------------------------------------------------------------------------------- alphabet_block
// 1 m wooden ABC block (rounded maple cube, six painted faces). opts: { variant=0..2 }.
const ABC_FACES = [
  ['A', PAL.channelRed, PAL.cream], ['B', PAL.wztvBlue, PAL.cream], ['C', PAL.barGreen, PAL.cream],
  ['H', PAL.burntOrange, '#FFF4DC'], ['13', PAL.cream, PAL.wztvBlue], ['star', PAL.barYellow, PAL.plum],
  ['owl', '#8A5A3A', '#9ED8FF'], ['moon', '#FFF4D6', '#23307A'], ['Z', PAL.plum, '#FFE3A3'],
];
function abcAtlas() {
  return cv('abc_atlas', 512, 512, (ctx, w, h) => {
    const cs = w / 3;
    ABC_FACES.forEach(([s, fg, bg], i) => {
      const x = (i % 3) * cs, y = Math.floor(i / 3) * cs, c = cs / 2;
      ctx.fillStyle = shadeHex(bg, -0.25); ctx.fillRect(x, y, cs, cs);
      rrect(ctx, x + 8, y + 8, cs - 16, cs - 16, 18); ctx.fillStyle = fg === PAL.cream ? PAL.channelRed : shadeHex(fg, 0.1); ctx.fill();
      rrect(ctx, x + 18, y + 18, cs - 36, cs - 36, 12); ctx.fillStyle = bg; ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.25)'; rrect(ctx, x + 18, y + 18, cs - 36, 10, 5); ctx.fill();
      if (s === 'star') { poly(ctx, starPts(x + c, y + c + 4, 58, 24)); ctx.fillStyle = fg; ctx.fill(); ctx.lineWidth = 6; ctx.strokeStyle = shadeHex(fg, -0.5); ctx.stroke(); }
      else if (s === 'moon') { ctx.fillStyle = fg; ctx.beginPath(); ctx.arc(x + c, y + c, 50, 0, TAU); ctx.fill(); ctx.fillStyle = bg; ctx.beginPath(); ctx.arc(x + c + 26, y + c - 16, 44, 0, TAU); ctx.fill(); poly(ctx, starPts(x + c + 40, y + c + 36, 12, 5)); ctx.fillStyle = fg; ctx.fill(); }
      else if (s === 'owl') {
        ctx.fillStyle = fg; ctx.beginPath(); ctx.ellipse(x + c, y + c + 12, 50, 56, 0, 0, TAU); ctx.fill();
        for (const sd of [-1, 1]) { poly(ctx, [[x + c + sd * 26, y + c - 30], [x + c + sd * 48, y + c - 64], [x + c + sd * 50, y + c - 20]]); ctx.fill(); ctx.fillStyle = '#FFF8E8'; ctx.beginPath(); ctx.arc(x + c + sd * 22, y + c - 4, 19, 0, TAU); ctx.fill(); ctx.fillStyle = '#2A1D3A'; ctx.beginPath(); ctx.arc(x + c + sd * 20, y + c - 2, 9, 0, TAU); ctx.fill(); ctx.fillStyle = fg; }
        ctx.fillStyle = '#F4A020'; poly(ctx, [[x + c - 9, y + c + 16], [x + c + 9, y + c + 16], [x + c, y + c + 30]]); ctx.fill();
      } else text(ctx, s, x + c, y + c + 6, { font: FONT.round, size: s.length > 1 ? 88 : 116, fill: fg, stroke: shadeHex(fg === PAL.cream ? PAL.wztvBlue : fg, -0.5), lw: 7, shadow: 'rgba(0,0,0,0.25)' });
    });
  });
}
registerProp('alphabet_block', (game, opts = {}) => {
  const v = (opts.variant ?? 0) % 3;
  const g = K.prop('alphabet_block');
  const S = 1.0;
  const maple = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood('#E8C890', { dark: 0.22 }) });
  g.add(K.m(K.box(S, S, S, 0.09, { uv: 1.2 }), maple, { pos: [0, S / 2, 0] }));
  const atlas = K.mat(game, 'lacquer', '#ffffff', { map: abcAtlas() });
  const faces = [[0, 1, 2, 3, 4, 5], [3, 6, 8, 1, 7, 2], [4, 5, 0, 6, 8, 3]][v];
  const cell = (i) => { const c = i % 3, r = Math.floor(i / 3); return [c / 3, 1 - (r + 1) / 3, (c + 1) / 3, 1 - r / 3]; };
  const fs = S - 0.14, o = S / 2 + 0.003;
  const place = [
    [[0, S / 2, -o], [0, 0, 0]], [[-o, S / 2, 0], [0, Math.PI / 2, 0]], [[0, S / 2, o], [0, Math.PI, 0]], [[o, S / 2, 0], [0, -Math.PI / 2, 0]],
    [[0, S + 0.003, 0], [Math.PI / 2, 0, 0]], [[0, -0.002, 0], [-Math.PI / 2, 0, 0]],
  ];
  place.forEach(([p, r], i) => {
    if (i === 5) return; // bottom face hidden
    const m = K.m(decalGeo(fs, fs, cell(faces[i])), atlas, { pos: p });
    m.rotation.set(...r);
    g.add(m);
  });
  const u = g.userData;
  u.colliders = [{ min: [-S / 2, 0, -S / 2], max: [S / 2, S, S / 2] }];
  return K.finish(game, g, { ao: { res: 40 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'block'], size: [1, 1, 1], desc: '1 m wooden alphabet block' });

// ---------------------------------------------------------------------------------------- rainbow_arch
// Walk-through pillowy rainbow arch (6 soft bands) standing on two puffy clouds with gold stars.
// Opening ~2.5 m wide x 2.2 m tall. Colliders: the two cloud feet.
registerProp('rainbow_arch', (game) => {
  const g = K.prop('rainbow_arch');
  const plastic = K.mat(game, 'plastic', '#ffffff', { rough: 0.5 });
  const cols = [PAL.barRed, PAL.burntOrange, PAL.barYellow, PAL.barGreen, PAL.barBlue, PAL.plum];
  const R0 = 1.35, dr = 0.21, cy = 0.95, tr = 0.125;
  cols.forEach((c, i) => {
    const r = R0 + (cols.length - 1 - i) * dr;
    const pts = [];
    for (let k = 0; k <= 20; k++) { const a = (k / 20) * Math.PI; pts.push([Math.cos(a) * r, cy + Math.sin(a) * r, 0]); }
    g.add(tm(K.tube(pts, tr, { seg: 28, radial: 8 }), plastic, c));
  });
  const cloudM = K.mat(game, 'plastic', '#ffffff', { rough: 0.55 });
  for (const s of [-1, 1]) {
    const cx = s * (R0 + 2.5 * dr);
    for (const [dx, dy, dz, r] of [[0, 0.45, 0, 0.55], [0.42, 0.32, 0.08, 0.4], [-0.42, 0.34, -0.05, 0.42], [0.12, 0.85, 0.05, 0.42], [-0.2, 0.25, 0.3, 0.3], [0.25, 0.22, -0.32, 0.3]]) {
      const sp = new THREE.SphereGeometry(r, 12, 9);
      g.add(tm(sp, cloudM, dy > 0.7 ? '#FFFFFF' : '#EFE8FF', { pos: [cx + dx * s, dy, dz] }));
    }
    for (let k = 0; k < 2; k++) {
      const st = K.extrude(starPts(0, 0, 0.13, 0.055), 0.05, { bevel: 0.015 });
      g.add(tm(st, plastic, PAL.marqueeGold, { pos: [cx + s * (0.35 - k * 0.6), 1.05 + k * 0.25, -0.45 + k * 0.1], rot: [0, 0, 0.2 * s] }));
    }
  }
  const u = g.userData;
  const fx = R0 + 2.5 * dr;
  u.colliders = [-1, 1].map((s) => ({ min: [s * fx - 0.75, 0, -0.55], max: [s * fx + 0.75, 1.3, 0.55] }));
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'arch', 'walkthrough'], size: [5.6, 3.6, 1.2], desc: 'walk-through pillowy rainbow arch on clouds', hero: true });

// ---------------------------------------------------------------------------------------- giant crayons
const CRAYONS = [['#E23B3B', 'RED'], ['#3A58E4', 'BLUE'], ['#F4E03A', 'YELLOW'], ['#52D24A', 'GREEN'], ['#B05AD6', 'PURPLE'], ['#FF8A2A', 'ORANGE']];
function crayonGroup(game, color, name, len = 1.7) {
  const r = 0.12;
  const grp = new THREE.Group();
  const wax = K.mat(game, 'plastic', '#ffffff', { rough: 0.55 });
  const wrapTex = cv(`crayon_wrap_${name}`, 256, 128, (ctx, w, h) => {
    ctx.fillStyle = color; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#1E1530';
    for (const y of [10, h - 22]) { ctx.beginPath(); for (let x = 0; x <= w; x += 16) { ctx.lineTo(x, y + (x / 16 % 2 ? 12 : 0)); } ctx.lineTo(w, y + 4); ctx.lineTo(0, y + 4); ctx.fill(); }
    ctx.fillStyle = 'rgba(255,255,255,0.9)'; rrect(ctx, 20, 38, w - 40, 52, 26); ctx.fill();
    text(ctx, 'HOOTIE', w / 2, 56, { font: FONT.round, size: 20, fill: '#1E1530' });
    text(ctx, name, w / 2, 78, { font: FONT.sign, size: 18, fill: shadeHex(color, -0.3), maxW: w * 0.6 });
  }, true);
  const wrap = K.mat(game, 'paint', '#ffffff', { map: wrapTex });
  const bodyL = len * 0.8;
  grp.add(tm(K.cyl(r * 0.97, r * 0.97, bodyL, { seg: 16, bevel: 0.02 }), wax, color));
  const wg = new THREE.CylinderGeometry(r + 0.006, r + 0.006, bodyL * 0.72, 16, 1, true);
  K.uvScale(wg, 2, 1);
  grp.add(K.m(wg, wrap, { pos: [0, bodyL * 0.48, 0] }));
  const tip = K.lathe([[r * 0.97, 0], [r * 0.9, 0.03], [r * 0.3, len * 0.18], [r * 0.18, len * 0.2], [0, len * 0.2]], { seg: 16 }).clone();
  // worn flat facet on the tip
  { const p = tip.attributes.position; for (let i = 0; i < p.count; i++) { const x = p.getX(i), y = p.getY(i); const lim = len * 0.2 - 0.06 + x * 0.5; if (y > lim && x > 0) p.setY(i, lim); } tip.computeVertexNormals(); }
  grp.add(tm(tip, wax, color, { pos: [0, bodyL, 0] }));
  return grp;
}
registerProp('giant_crayon', (game, opts = {}) => {
  const g = K.prop('giant_crayon');
  const [color, name] = CRAYONS[(opts.color ?? 0) % CRAYONS.length];
  const c = crayonGroup(game, color, name, opts.length ?? 1.7);
  if ((opts.pose ?? 'lie') === 'lie') { c.rotation.z = Math.PI / 2; c.position.set(0.85, 0.12, 0); c.rotation.x = 0.2; }
  g.add(c);
  return K.finish(game, g, { ao: { res: 40 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'crayon'], size: [1.7, 0.25, 0.25], desc: 'giant wax crayon (opts.color 0..5, pose lie|stand)' });

// Giant open crayon box (HOOTIE CRAYONS) with four crayons standing in it and two on the floor.
registerProp('giant_crayons', (game) => {
  const g = K.prop('giant_crayons');
  const card = K.mat(game, 'paint', '#ffffff');
  const boxTex = cv('crayon_box', 512, 512, (ctx, w, h) => {
    ctx.fillStyle = PAL.barYellow; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = PAL.barGreen; ctx.beginPath(); ctx.moveTo(0, h * 0.55); ctx.quadraticCurveTo(w / 2, h * 0.35, w, h * 0.55); ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.fill();
    ctx.fillStyle = PAL.channelRed; for (let i = 0; i < 6; i++) { ctx.beginPath(); ctx.arc(40 + i * 86, h * 0.9, 20, 0, TAU); ctx.fill(); }
    text(ctx, 'HOOTIE', w / 2, h * 0.2, { font: FONT.groovy, size: 96, fill: PAL.wztvBlue, stroke: '#fff', lw: 10, maxW: w * 0.9 });
    text(ctx, 'CRAYONS', w / 2, h * 0.38, { font: FONT.sign, size: 70, fill: PAL.channelRed, stroke: '#fff', lw: 8, maxW: w * 0.9 });
    text(ctx, '8 GROOVY COLORS!', w / 2, h * 0.7, { font: FONT.round, size: 40, fill: '#fff', stroke: '#1E4A1E', lw: 6, maxW: w * 0.9 });
  });
  const boxMat = K.mat(game, 'paint', '#ffffff', { map: boxTex });
  const BW = 0.95, BH = 0.8, BD = 0.42, th = 0.03;
  g.add(K.m(K.box(BW, BH, th, 0.012), boxMat, { pos: [0, BH / 2, -BD / 2] }));
  g.add(K.m(K.box(BW, BH, th, 0.012), boxMat, { pos: [0, BH / 2, BD / 2] }));
  for (const s of [-1, 1]) g.add(tm(K.box(th, BH, BD, 0.012), card, PAL.barGreen, { pos: [s * BW / 2, BH / 2, 0] }));
  g.add(tm(K.box(BW, th, BD, 0.012), card, PAL.barGreen, { pos: [0, th / 2, 0] }));
  // open flap
  const flap = K.m(tg(K.box(BW, 0.3, th, 0.012), PAL.barYellow), card);
  flap.position.set(0, BH + 0.13, BD / 2 + 0.06); flap.rotation.x = -0.45;
  g.add(flap);
  const heights = [1.5, 1.72, 1.6, 1.36];
  for (let i = 0; i < 4; i++) {
    const [c, n] = CRAYONS[i];
    const cr = crayonGroup(game, c, n, heights[i]);
    cr.position.set(-0.33 + i * 0.22, 0.03, (i % 2 ? 0.06 : -0.06));
    cr.rotation.z = (i - 1.5) * 0.06;
    g.add(cr);
  }
  for (let i = 0; i < 2; i++) {
    const [c, n] = CRAYONS[4 + i];
    const cr = crayonGroup(game, c, n, 1.55);
    cr.rotation.z = Math.PI / 2; cr.rotation.y = i ? 0.5 : -0.2;
    cr.position.set(i ? 0.9 : 0.6, 0.12, i ? 0.55 : -0.62);
    g.add(cr);
  }
  const u = g.userData;
  u.colliders = [{ min: [-BW / 2, 0, -BD / 2], max: [BW / 2, 1.75, BD / 2] }];
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'crayon'], size: [1.8, 1.8, 1.4], desc: 'giant open crayon box with crayons' });

// ---------------------------------------------------------------------------------------- toy_train_loop
// Wind-up toy train on a round track (toy_train): chunky loco + block wagon + caboose, cardboard tunnel.
// parts.train: rotate .rotation.y around the loop center (track radius 1.1 m).
registerProp('toy_train_loop', (game) => {
  const g = K.prop('toy_train_loop');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const RT = 1.1;
  const ties = cv('train_ties', 512, 64, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    for (let i = 0; i < 16; i++) { rrect(ctx, i * 32 + 6, 4, 20, h - 8, 5); ctx.fillStyle = i % 2 ? '#8A5A34' : '#7A4A2A'; ctx.fill(); ctx.fillStyle = 'rgba(255,255,255,0.12)'; ctx.fillRect(i * 32 + 8, 6, 16, 4); }
  }, true);
  const tieMat = K.mat(game, 'paint', '#ffffff', { map: ties, alphaTest: 0.5 });
  const rg = new THREE.RingGeometry(RT - 0.13, RT + 0.13, 72, 1);
  { const p = rg.attributes.position, uv = rg.attributes.uv; for (let i = 0; i < p.count; i++) { const a = Math.atan2(p.getY(i), p.getX(i)); const r = Math.hypot(p.getX(i), p.getY(i)); uv.setXY(i, (a / TAU) * 12, (r - (RT - 0.13)) / 0.26); } }
  rg.rotateX(-Math.PI / 2);
  g.add(K.m(rg, tieMat, { pos: [0, 0.012, 0] }));
  for (const r of [RT - 0.07, RT + 0.07]) { const t = new THREE.TorusGeometry(r, 0.012, 5, 56); t.rotateX(Math.PI / 2); g.add(K.m(t, chrome, { pos: [0, 0.035, 0] })); }
  // tunnel (painted cardboard mountain)
  const tun = cv('train_tunnel', 256, 128, (ctx, w, h) => {
    ctx.fillStyle = '#6FBF4A'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#58A83E'; for (let i = 0; i < 12; i++) { ctx.beginPath(); ctx.arc((i * 47) % w, 20 + (i * 31) % 80, 14, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#FFF4DC'; for (let i = 0; i < 5; i++) { ctx.beginPath(); ctx.arc(30 + i * 50, 100 - (i % 2) * 20, 4, 0, TAU); ctx.fill(); }
  }, true);
  const tunG = new THREE.CylinderGeometry(0.34, 0.34, 0.8, 16, 1, true, 0, Math.PI);
  tunG.rotateZ(Math.PI / 2); tunG.rotateY(Math.PI / 2);
  const tunnel = K.m(tunG, K.mat(game, 'paint', '#ffffff', { map: tun, side: THREE.DoubleSide }));
  tunnel.position.set(-RT, 0, 0.0);
  g.add(tunnel);
  for (const z of [-0.4, 0.4]) g.add(tm(new THREE.TorusGeometry(0.34, 0.035, 6, 16, Math.PI), lac, PAL.channelRed, { pos: [-RT, 0, z] }));
  // train on the loop
  const train = new THREE.Group();
  const wheelG = K.cyl(0.055, 0.055, 0.03, { seg: 10, bevel: 0.008 }).clone(); wheelG.rotateX(Math.PI / 2);
  const car = (build, ang) => {
    const cg = new THREE.Group();
    cg.position.set(Math.cos(ang) * RT, 0.04, -Math.sin(ang) * RT);
    cg.rotation.y = ang;
    build(cg);
    for (const x of [-0.12, 0.12]) for (const z of [-0.075, 0.075]) cg.add(tm(wheelG, lac, PAL.barYellow, { pos: [x, 0.055, z] }));
    train.add(cg);
  };
  // loco (faces -z in its frame = direction of travel for +rotation.y)
  car((c) => {
    c.add(tm(K.box(0.2, 0.08, 0.36, 0.025), lac, '#2A2230', { pos: [0, 0.1, 0] }));
    const boiler = K.cyl(0.085, 0.085, 0.24, { seg: 16, bevel: 0.02 }).clone(); boiler.rotateX(Math.PI / 2);
    c.add(tm(boiler, lac, PAL.channelRed, { pos: [0, 0.22, -0.04 + 0.12] }).translateZ(-0.24));
    c.add(tm(K.box(0.2, 0.2, 0.14, 0.03), lac, PAL.wztvBlue, { pos: [0, 0.25, 0.12] }));
    c.add(tm(K.box(0.24, 0.035, 0.18, 0.015), lac, PAL.channelRed, { pos: [0, 0.36, 0.12] }));
    c.add(tm(K.lathe([[0, 0], [0.03, 0], [0.032, 0.08], [0.055, 0.13], [0.05, 0.14], [0, 0.14]], { seg: 12 }), lac, '#2A2230', { pos: [0, 0.29, -0.14] }));
    c.add(tm(K.extrude([[-0.1, 0], [0.1, 0], [0, 0.09]], 0.08, { bevel: 0.01 }).rotateX(-Math.PI / 2), lac, PAL.barYellow, { pos: [0, 0.07, -0.2] }));
    c.add(K.m(new THREE.CircleGeometry(0.03, 12).rotateY(Math.PI), K.glow(game, '#FFF2C0', 3), { pos: [0, 0.22, -0.168] }));
    c.add(K.m(new THREE.SphereGeometry(0.05, 10, 8), chrome, { pos: [0, 0.31, -0.02] }));
  }, 0);
  car((c) => {
    c.add(tm(K.box(0.22, 0.12, 0.3, 0.03), lac, PAL.barGreen, { pos: [0, 0.14, 0] }));
    const bc = [PAL.channelRed, PAL.barYellow, PAL.wztvBlue];
    for (let i = 0; i < 3; i++) c.add(tm(K.box(0.08, 0.08, 0.08, 0.015), lac, bc[i], { pos: [(i - 1) * 0.05, 0.24, (i - 1) * 0.08], rot: [0, i * 0.4, 0] }));
  }, -0.42);
  car((c) => {
    c.add(tm(K.box(0.22, 0.2, 0.28, 0.035), lac, PAL.burntOrange, { pos: [0, 0.18, 0] }));
    c.add(tm(K.box(0.26, 0.03, 0.32, 0.012), lac, '#5A3A22', { pos: [0, 0.3, 0] }));
    c.add(tm(K.box(0.14, 0.08, 0.12, 0.02), lac, PAL.burntOrange, { pos: [0, 0.35, 0] }));
    for (const s of [-1, 1]) c.add(K.m(new THREE.CircleGeometry(0.03, 10).rotateY(s * Math.PI / 2), K.glow(game, '#FFE3A3', 1.8), { pos: [s * 0.112, 0.2, 0] }));
  }, -0.8);
  train.userData.noMerge = true;
  K.merge(train);
  g.add(train);
  const u = g.userData;
  u.parts = { train };
  u.interact = { point: [0, 0.5, 0], radius: 1.6 };
  u.colliders = [{ min: [-RT - 0.4, 0, -0.45], max: [-RT + 0.4, 0.4, 0.45] }];
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'toy', 'train'], size: [2.6, 0.45, 2.6], desc: 'toy train on a round track with a cardboard tunnel', hero: true });

// ---------------------------------------------------------------------------------------- xylophone
// Giant pull-toy xylophone (toy_xylophone): 8 rainbow bars (parts.bars InstancedMesh, per-bar bounce), wooden
// frame on red wheels, pull cord, two mallets (parts.mallets). Bars at y ~0.6.
registerProp('xylophone', (game) => {
  const g = K.prop('xylophone');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const maple = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood('#E8C890', { dark: 0.25 }) });
  const L = 1.4, BY = 0.56;
  // trapezoid frame: two converging rails
  const wBig = 0.82, wSmall = 0.48;
  for (const s of [-1, 1]) {
    const a = V3(-L / 2, BY - 0.06, s * wBig / 2 * 0.62), b = V3(L / 2, BY - 0.06, s * wSmall / 2 * 0.62);
    const rail = K.m(K.box(a.distanceTo(b) + 0.14, 0.1, 0.09, 0.03, { uv: 2 }), maple);
    rail.position.copy(a).add(b).multiplyScalar(0.5);
    rail.rotation.y = -Math.atan2(b.z - a.z, b.x - a.x);
    g.add(rail);
  }
  // body skirt + base
  g.add(K.m(K.taper(K.box(L + 0.1, 0.34, 0.66, 0.06, { uv: 1.5 }), { axis: 'x', k: 0.72 }), maple, { pos: [0, 0.3, 0] }));
  g.add(tm(K.taper(K.box(L + 0.14, 0.05, 0.7, 0.02), { axis: 'x', k: 0.72 }), lac, PAL.channelRed, { pos: [0, 0.47, 0] }));
  for (const [x, z] of [[-0.55, -0.36], [-0.55, 0.36], [0.55, -0.28], [0.55, 0.28]]) {
    const wh = K.cyl(0.12, 0.12, 0.07, { seg: 14, bevel: 0.02 }).clone(); wh.rotateX(Math.PI / 2);
    g.add(tm(wh, lac, PAL.channelRed, { pos: [x, 0.12, z] }));
    g.add(K.m(K.cyl(0.035, 0.035, 0.08, { seg: 10 }).clone().rotateX(Math.PI / 2), chrome, { pos: [x, 0.12, z + Math.sign(z) * 0.01] }));
  }
  // bars (instanced) + studs
  const cols = [PAL.barRed, PAL.burntOrange, PAL.barYellow, PAL.barGreen, PAL.barCyan, PAL.barBlue, PAL.plum, PAL.neonPink];
  const barGeo = K.box(0.13, 0.045, 1.0, 0.018);
  const xf = [];
  for (let i = 0; i < 8; i++) {
    const t = i / 7, x = -L / 2 + 0.12 + t * (L - 0.24);
    const len = lerp(0.8, 0.46, t);
    xf.push({ pos: [x, BY + 0.03, 0], scale: [1, 1, len] });
    for (const s of [-1, 1]) g.add(K.m(new THREE.SphereGeometry(0.014, 6, 4), chrome, { pos: [x, BY + 0.06, s * len * 0.38] }));
  }
  const bars = instanced(barGeo, K.mat(game, 'metal', '#ffffff', { rough: 0.35 }), xf, cols, 'bars');
  g.add(bars);
  // mallets
  const mallets = new THREE.Group();
  for (const s of [-1, 1]) {
    const a = V3(-0.1 + s * 0.14, BY + 0.1, -0.1), b = V3(0.35 + s * 0.12, BY + 0.14, -0.62 - s * 0.05);
    mallets.add(rod(0.012, maple, a, b, 6));
    mallets.add(tm(new THREE.SphereGeometry(0.045, 12, 9), lac, s < 0 ? PAL.channelRed : PAL.wztvBlue, { pos: a.toArray() }));
  }
  K.merge(mallets);
  mallets.userData.noMerge = true;
  g.add(mallets);
  // pull cord + bead
  g.add(tm(K.tube([[L / 2 + 0.05, 0.3, 0], [L / 2 + 0.3, 0.15, -0.05], [L / 2 + 0.45, 0.02, 0.1], [L / 2 + 0.6, 0.02, 0.25]], 0.008, { seg: 16, radial: 4 }), lac, '#E8E0C8'));
  g.add(tm(new THREE.SphereGeometry(0.05, 12, 9), lac, PAL.barYellow, { pos: [L / 2 + 0.62, 0.05, 0.27] }));
  const u = g.userData;
  u.parts = { bars, mallets };
  u.bars = xf.map((t) => ({ pos: t.pos, len: t.scale[2] }));
  u.interact = { point: [0, 0.6, -0.4], radius: 1.3 };
  u.colliders = [{ min: [-L / 2 - 0.1, 0, -0.45], max: [L / 2 + 0.1, BY + 0.1, 0.45] }];
  return K.finish(game, g, { ao: { res: 48 } });
}, { category: CAT, tags: ['studio_b', 'kids', 'toy', 'music'], size: [2.2, 0.7, 1.0], desc: 'giant rainbow pull-toy xylophone', hero: true });

// =========================================================================================================
// EASTER-EGG OBJECTS
// =========================================================================================================

// ---------------------------------------------------------------------------------------- chime_rack
// Announce-booth electric chime rack (ee_chime_rack): walnut frame, four anodized tubular bars on eye hooks with
// solenoid strikers, control box. Bars left->right as seen from the front: green, blue, red, yellow (GDD §13).
// parts.bar_red / bar_yellow / bar_green / bar_blue: Groups pivoting at the hook (swing = .rotation.x).
// userData.chimes[color] = { len, note, hz, center:[x,y,z] }. Place at [~-6.5, 0, -4.5] with rotY = -PI/2 to get
// the exact GDD z positions (red -4.7, yellow -5.1, green -3.9, blue -4.3).
const CHIMES = { red: { len: 1.2, note: 'G4', hz: 392.0, col: '#E23B3B', x: -0.2 }, yellow: { len: 1.05, note: 'C5', hz: 523.3, col: '#F4C81E', x: -0.6 },
  green: { len: 0.9, note: 'E5', hz: 659.3, col: '#3FBF4A', x: 0.6 }, blue: { len: 0.75, note: 'G5', hz: 784.0, col: '#3A68E4', x: 0.2 } };
registerProp('chime_rack', (game) => {
  const g = K.prop('chime_rack');
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.35 }) });
  const brass = K.mat(game, 'brass', '#C8963C');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const W = 1.72, TOP = 2.08, HOOK = 1.96;
  g.add(K.m(K.box(W, 0.12, 0.52, 0.035, { uv: 1.5 }), walnut, { pos: [0, 0.1, 0] }));
  g.add(K.m(K.box(W + 0.06, 0.04, 0.58, 0.015, { uv: 1.5 }), walnut, { pos: [0, 0.18, 0] }));
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(K.m(K.cyl(0.035, 0.045, 0.04, { seg: 10 }), brass, { pos: [x * (W / 2 - 0.08), 0, z * 0.2] }));
  for (const s of [-1, 1]) {
    g.add(K.m(K.box(0.1, TOP - 0.1, 0.1, 0.025, { uv: 1.5, swap: true }), walnut, { pos: [s * (W / 2 - 0.08), (TOP - 0.1) / 2 + 0.1, 0] }));
    g.add(K.m(K.lathe([[0, 0], [0.06, 0], [0.065, 0.03], [0.05, 0.06], [0.07, 0.11], [0.04, 0.16], [0, 0.17]], { round: 0.01, seg: 12, steps: 1 }), brass, { pos: [s * (W / 2 - 0.08), TOP + 0.06, 0] }));
    // brace
    const a = V3(s * (W / 2 - 0.08), 0.2, 0.14), b = V3(s * (W / 2 - 0.08), 0.75, 0.04);
    g.add(between(K.box(0.05, a.distanceTo(b), 0.05, 0.012), walnut, a, b).translateY(a.distanceTo(b) / 2));
  }
  g.add(K.m(K.box(W, 0.13, 0.15, 0.035, { uv: 1.5 }), walnut, { pos: [0, TOP, 0] }));
  const plate = K.tex.label('WZTV  ·  STATION CHIMES', { bg: '#E8C878', fg: '#3A2418', accent: '#8A5A20', w: 512, h: 64, border: 0.1, wear: 0.15 });
  g.add(K.m(decalGeo(0.72, 0.09), K.mat(game, 'brass', '#ffffff', { map: plate, rough: 0.35 }), { pos: [0, TOP, -0.078] }));
  // front striker rail with 4 solenoids
  g.add(K.m(K.cyl(0.012, 0.012, W - 0.2, { seg: 8 }).clone().rotateZ(Math.PI / 2).translate((W - 0.2) / 2, 0, 0), chrome, { pos: [0, HOOK - 0.1, -0.12] }));
  const parts = {}, chimes = {};
  for (const [name, c] of Object.entries(CHIMES)) {
    // solenoid + hammer
    g.add(K.m(K.cyl(0.028, 0.028, 0.09, { seg: 12, bevel: 0.008 }), chrome, { pos: [c.x, HOOK - 0.15, -0.12] }));
    g.add(tm(K.cyl(0.03, 0.03, 0.02, { seg: 12, bevel: 0.006 }), lac, c.col, { pos: [c.x, HOOK - 0.06, -0.12] }));
    g.add(K.m(K.tube([[c.x, HOOK - 0.15, -0.12], [c.x, HOOK - 0.19, -0.09], [c.x, HOOK - 0.2, -0.055]], 0.007, { seg: 6, radial: 5 }), brass));
    // eye hook
    g.add(K.m(new THREE.TorusGeometry(0.018, 0.005, 5, 10), brass, { pos: [c.x, HOOK + 0.03, 0], rot: [0, Math.PI / 2, 0] }));
    const bar = new THREE.Group();
    bar.position.set(c.x, HOOK, 0);
    const mat = K.mat(game, 'metal', c.col, { rough: 0.28, env: 0.5, rim: 0.3 });
    bar.add(K.m(K.cyl(0.033, 0.033, c.len - 0.08, { seg: 12, bevel: 0.004 }), mat, { pos: [0, -c.len + 0.04, 0] }));
    bar.add(K.m(K.lathe([[0, 0], [0.036, 0], [0.038, 0.012], [0.036, 0.05], [0.02, 0.06], [0, 0.062]], { seg: 12 }), chrome, { pos: [0, -0.07, 0] }));
    bar.add(K.m(K.lathe([[0, 0], [0.036, 0.004], [0.038, 0.03], [0.036, 0.04], [0, 0.04]], { seg: 12 }), chrome, { pos: [0, -c.len, 0] }));
    bar.add(K.m(new THREE.TorusGeometry(0.014, 0.005, 5, 10), chrome, { pos: [0, 0, 0], rot: [0, 0, 0] }));
    bar.add(K.m(K.cyl(0.036, 0.036, 0.03, { seg: 12, bevel: 0.004 }), chrome, { pos: [0, -0.24, 0] }));
    K.merge(bar);
    bar.userData.noMerge = true;
    g.add(bar);
    parts[`bar_${name}`] = bar;
    chimes[name] = { len: c.len, note: c.note, hz: c.hz, center: [c.x, HOOK - c.len / 2, 0] };
  }
  // control box with four colored buttons
  g.add(tm(K.taper(K.box(0.42, 0.16, 0.26, 0.03), { axis: 'y', k: 0.85 }), lac, '#E8DCC0', { pos: [0.35, 0.28, -0.05] }));
  ['green', 'blue', 'red', 'yellow'].forEach((n, i) => g.add(tm(K.cyl(0.025, 0.028, 0.03, { seg: 10, bevel: 0.008 }), lac, CHIMES[n].col, { pos: [0.5 - i * 0.1, 0.36, -0.07] })));
  g.add(K.m(K.tube([[0.14, 0.26, 0.0], [0.0, 0.2, 0.05], [-0.4, 0.2, 0.06], [-0.78, 0.5, 0.05], [-0.78, 1.8, 0.05]], 0.009, { seg: 20, radial: 4 }), K.mat(game, 'rubber', '#2A2230')));
  const u = g.userData;
  u.parts = parts;
  u.chimes = chimes;
  u.colliders = [{ min: [-W / 2, 0, -0.28], max: [W / 2, TOP + 0.2, 0.28] }];
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['lobby', 'booth', 'ee', 'chimes'], size: [1.8, 2.3, 0.6], desc: 'four-bar electric station chime rack (red/yellow/green/blue)', hero: true });

// ---------------------------------------------------------------------------------------- trophy_case
// Lobby trophy case (ee_trophy_case): walnut cabinet, plum velvet back, lit crown, glass shelves, golden winged-TV
// "Telly Award" statuettes and plaques; the glass front door is parts.door (pivot on the viewer's left edge,
// open = rotation.y ~ -1.9). anchors.dudley = the empty middle-shelf spot (GDD [-6.75,1.3,-2.0] against the
// west wall: back at local +z).
function tellyAward(gold, base, s = 1) {
  const g = new THREE.Group();
  g.add(K.m(K.box(0.16 * s, 0.05 * s, 0.12 * s, 0.01, { seg: 1 }), base, { pos: [0, 0.025 * s, 0] }));
  g.add(K.m(K.box(0.12 * s, 0.04 * s, 0.09 * s, 0.008, { seg: 1 }), base, { pos: [0, 0.07 * s, 0] }));
  g.add(K.m(K.lathe([[0, 0], [0.03, 0], [0.018, 0.03], [0.014, 0.08], [0.03, 0.1], [0, 0.1]], { seg: 8 }), gold, { pos: [0, 0.09 * s, 0], scale: s }));
  g.add(K.m(K.box(0.14 * s, 0.11 * s, 0.09 * s, 0.028 * s, { seg: 2 }), gold, { pos: [0, 0.245 * s, 0] }));
  g.add(K.m(K.box(0.1 * s, 0.075 * s, 0.02 * s, 0.012, { seg: 1 }), base, { pos: [-0.008 * s, 0.245 * s, -0.04 * s] }));
  for (const sd of [-1, 1]) {
    const wing = K.extrude([[0, 0], [0.12, 0.05], [0.14, 0.11], [0.1, 0.09], [0.11, 0.14], [0.06, 0.1], [0.05, 0.13], [0.0, 0.07]], 0.016, { bevel: 0.004, bevelSeg: 1 });
    const wm = K.m(wing, gold, { pos: [sd * 0.065 * s, 0.22 * s, 0.01 * s], scale: [sd * s, s, s] });
    g.add(wm);
  }
  for (const sd of [-1, 1]) g.add(K.m(K.cyl(0.004 * s, 0.004 * s, 0.09 * s, { seg: 5 }), gold, { pos: [sd * 0.02 * s, 0.295 * s, 0], rot: [0, 0, -sd * 0.5] }));
  return g;
}
registerProp('trophy_case', (game) => {
  const g = K.prop('trophy_case');
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.35 }) });
  const velvet = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#5A2A5E', { pattern: 'plain', scale: 2 }) });
  const gold = K.mat(game, 'brass', '#E0B04A', { rough: 0.22 });
  const blackLac = K.mat(game, 'lacquer', '#2A1D2A');
  const glass = game.mats.glass('#DDEFFF', { opacity: 0.09 });
  const W = 1.6, H = 2.1, D = 0.55, t = 0.06;
  // carcass
  g.add(K.m(K.box(W + 0.08, 0.2, D + 0.05, 0.03, { uv: 1.5 }), walnut, { pos: [0, 0.1, 0] }));
  g.add(K.m(K.box(W + 0.14, 0.14, D + 0.1, 0.04, { uv: 1.5 }), walnut, { pos: [0, H - 0.07, 0] }));
  g.add(K.m(K.box(W + 0.2, 0.05, D + 0.14, 0.02, { uv: 1.5 }), walnut, { pos: [0, H + 0.02, 0] }));
  for (const s of [-1, 1]) g.add(K.m(K.box(t, H - 0.2, D, 0.02, { uv: 1.5, swap: true }), walnut, { pos: [s * (W / 2 - t / 2), H / 2, 0] }));
  g.add(K.m(K.box(W - 0.1, H - 0.3, 0.03, 0.01, { uv: 2.5 }), velvet, { pos: [0, H / 2, D / 2 - 0.03] }));
  g.add(K.m(K.box(W - 0.1, 0.03, D - 0.05, 0.01, { uv: 2.5 }), velvet, { pos: [0, 0.215, 0] }));
  // lit crown strip
  g.add(K.m(K.box(W - 0.2, 0.025, 0.04, 0.01), K.glow(game, '#FFE6B8', 2.2), { pos: [0, H - 0.16, -D / 2 + 0.1], cast: false }));
  // glass shelves with brass clips
  for (const y of [0.6, 1.02, 1.47]) {
    g.add(K.m(K.box(W - 0.14, 0.018, D - 0.12, 0.006), glass, { pos: [0, y, 0.02] }));
    for (const s of [-1, 1]) g.add(K.m(K.box(0.03, 0.02, 0.03, 0.006), gold, { pos: [s * (W / 2 - 0.08), y - 0.015, 0.02] }));
  }
  // awards
  const addAward = (x, y, s, rot = 0) => { const a = tellyAward(gold, blackLac, s); a.position.set(x, y, 0.04); a.rotation.y = rot; g.add(a); };
  addAward(0, 1.48, 1.32); addAward(0.5, 1.48, 1.12, -0.25); addAward(-0.5, 1.48, 1.12, 0.25);
  addAward(0.52, 1.03, 1.18, -0.2); addAward(-0.52, 1.03, 1.18, 0.2);
  // plaques + pennant on the bottom shelf
  const plq = cv('trophy_plaques', 256, 128, (ctx, w, h) => {
    for (let i = 0; i < 2; i++) {
      const x = i * 128;
      rrect(ctx, x + 4, 4, 120, 120, 12); ctx.fillStyle = '#6A3A22'; ctx.fill();
      rrect(ctx, x + 18, 22, 92, 70, 6); ctx.fillStyle = grad(ctx, 0, 22, 0, 92, ['#FFF2B0', '#E8B84A', '#B07A16']); ctx.fill();
      text(ctx, i ? 'BEST' : 'TELLY', x + 64, 44, { font: FONT.sign, size: 16, fill: '#5A3A08' });
      text(ctx, i ? 'HOST' : '1976', x + 64, 70, { font: FONT.sign, size: 18, fill: '#5A3A08' });
    }
  });
  const plqMat = K.mat(game, 'lacquer', '#ffffff', { map: plq });
  for (let i = 0; i < 2; i++) {
    const p = K.m(K.uvRect(K.box(0.26, 0.26, 0.03, 0.01).clone(), i / 2, 0, (i + 1) / 2, 1), plqMat, { pos: [-0.35 + i * 0.7, 0.74, D / 2 - 0.12], rot: [-0.18, i ? -0.15 : 0.15, 0] });
    g.add(p);
  }
  const pennant = cv('trophy_pennant', 256, 96, (ctx, w, h) => {
    ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(w, h / 2); ctx.lineTo(0, h); ctx.closePath(); ctx.fillStyle = PAL.channelRed; ctx.fill();
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 0, 22, h);
    text(ctx, 'WZTV 13', 100, h / 2 + 2, { font: FONT.sign, size: 26, fill: '#F4F1E8', maxW: 150 });
  });
  g.add(K.m(decalGeo(0.7, 0.26), K.mat(game, 'fabric', '#ffffff', { map: pennant, alphaTest: 0.5, side: THREE.DoubleSide }), { pos: [0, 0.4, D / 2 - 0.05], rot: [0, 0, -0.08] }));
  // name plate
  const namePlate = K.tex.label('TELLY AWARDS', { sub: 'WZTV CHANNEL 13 · EXCELLENCE IN BROADCASTING', bg: '#E8C878', fg: '#3A2418', accent: '#8A5A20', w: 512, h: 128, wear: 0.1 });
  g.add(K.m(decalGeo(0.56, 0.14), K.mat(game, 'brass', '#ffffff', { map: namePlate, rough: 0.35 }), { pos: [0, 0.1, -D / 2 - 0.028] }));
  // glass door (pivot on the viewer's left = +x edge)
  const door = new THREE.Group();
  door.position.set(W / 2 - 0.03, 0, -D / 2);
  const df = K.roundRect(W - 0.06, H - 0.36, 0.03);
  df.holes.push(new THREE.Path(K.roundRect(W - 0.2, H - 0.5, 0.02).getPoints(4)));
  door.add(K.m(K.uvScale(K.extrude(df, 0.035, { bevel: 0.01, curveSeg: 4 }), 1.5, 1.5), walnut, { pos: [-(W - 0.06) / 2, H / 2 + 0.02, -0.02] }));
  door.add(K.m(new THREE.PlaneGeometry(W - 0.18, H - 0.48), glass, { pos: [-(W - 0.06) / 2, H / 2 + 0.02, -0.02] }));
  door.add(K.m(K.cyl(0.012, 0.012, 0.14, { seg: 8 }), gold, { pos: [-(W - 0.06) + 0.05, H / 2 - 0.05, -0.055] }));
  door.userData.noMerge = true;
  g.add(door);
  for (const y of [0.4, H - 0.4]) g.add(K.m(K.cyl(0.012, 0.012, 0.1, { seg: 8 }), gold, { pos: [W / 2 - 0.02, y, -D / 2 - 0.02] }));
  const u = g.userData;
  u.parts = { door };
  u.anchors = { dudley: [0, 1.3, 0.0], door_drop: [0.6, 0, -0.9] };
  u.lightAnchors = [{ pos: [0, H - 0.3, -0.3], color: '#FFE6B8', intensity: 1.2, distance: 3.5 }];
  u.colliders = [{ min: [-W / 2 - 0.1, 0, -D / 2 - 0.05], max: [W / 2 + 0.1, H + 0.05, D / 2 + 0.07] }];
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['lobby', 'ee', 'trophy', 'wall'], size: [1.8, 2.15, 0.7], desc: 'walnut trophy case with golden winged-TV Telly Awards and a glass door', hero: true });

// ---------------------------------------------------------------------------------------- neon_logo_partition
// Lobby partition (4 x 2.4 x 0.3 m, walnut paneling + 70s stripe band) carrying the neon WZTV 13 logo on its
// front: four tube letters W red, Z yellow, T green, V blue + the "13" disc (red neon ring, white 13).
// parts.neon_W/Z/T/V/13 (tube meshes) + halo_W/Z/T/V/13 (additive glow cards). setNeon(prop, game, key, level)
// with level 0..1 (0.2 = dead tube, still visibly colored). opts.state: 'lit' (default) | 'dark' | 'broken'.
const NEON = { W: PAL.neonW, Z: PAL.neonZ, T: PAL.neonT, V: PAL.neonV, 13: '#FFF6E8' };
const NEON_PATHS = {
  W: [[[-0.27, 0.3], [-0.15, -0.3], [0, 0.12], [0.15, -0.3], [0.27, 0.3]]],
  Z: [[[-0.21, 0.3], [0.22, 0.3], [-0.22, -0.3], [0.22, -0.3]]],
  T: [[[-0.24, 0.3], [0.24, 0.3]], [[0, 0.3], [0, -0.3]]],
  V: [[[-0.24, 0.3], [0, -0.3], [0.24, 0.3]]],
  13: [[[-0.2, 0.12], [-0.12, 0.2], [-0.12, -0.2]], [[0.02, 0.14], [0.08, 0.2], [0.17, 0.19], [0.2, 0.1], [0.14, 0.02], [0.08, 0.01], [0.15, -0.01], [0.21, -0.09], [0.18, -0.18], [0.09, -0.21], [0.02, -0.15]]],
};
function neonLevelMat(game, key, level) {
  const q = Math.round(clamp(level, 0, 1) * 20) / 20;
  return K.glow(game, NEON[key], (0.12 + q ** 1.5 * 2.9) * (key === '13' ? 0.62 : 1));
}
function haloMat(game, key, level, map) {
  const q = Math.round(clamp(level, 0, 1) * 20) / 20;
  return K.glow(game, NEON[key], (0.01 + q ** 2 * 0.76) * (key === '13' ? 0.35 : 1), { map, additive: true });
}
registerProp('neon_logo_partition', (game, opts = {}) => {
  const g = K.prop('neon_logo_partition');
  const W = 4.0, H = 2.4, D = 0.3;
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const panel = K.mat(game, 'walnut', '#ffffff', { map: woodPanel(PAL.walnut) });
  g.add(K.m(K.uvScale(K.box(W, H - 0.12, D, 0.13, { uv: 1 }).clone(), 0.85, 0.42), panel, { pos: [0, H / 2 + 0.04, 0] }));
  g.add(tm(K.box(W + 0.04, 0.1, D + 0.04, 0.04), lac, '#2A1810', { pos: [0, 0.05, 0] }));
  g.add(tm(K.box(W + 0.06, 0.07, D + 0.06, 0.03), lac, PAL.harvestGold, { pos: [0, H + 0.0, 0] }));
  [[PAL.burntOrange, 0.98], [PAL.harvestGold, 0.86], [PAL.chocolate, 0.76]].forEach(([c, y]) => g.add(tm(K.box(W + 0.02, 0.09, D + 0.02, 0.04), lac, c, { pos: [0, y, 0] })));
  // backer board for the logo
  const BW = 3.5, BH = 0.98, BY = 1.9, fz = -D / 2;
  g.add(tm(K.extrude(K.roundRect(BW, BH, 0.2), 0.05, { bevel: 0.02 }), lac, '#1E1530', { pos: [0, BY, fz - 0.02] }));
  g.add(K.m(K.tube(roundRectLoop(BW + 0.02, BH + 0.02, 0.21), 0.012, { seg: 80, radial: 5, closed: true }), chrome, { pos: [0, BY, fz - 0.045] }));
  // halo atlas (soft white glows of each glyph)
  const keys = ['W', 'Z', 'T', 'V', '13'];
  const halo = cv('neon_halo', 640, 128, (ctx, w, h) => {
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h);
    keys.forEach((k, i) => {
      ctx.save(); ctx.translate(i * 128 + 64, 64);
      ctx.filter = 'blur(9px)';
      ctx.strokeStyle = '#fff'; ctx.lineWidth = 16; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      for (const st of NEON_PATHS[k]) { ctx.beginPath(); st.forEach(([x, y], j) => (j ? ctx.lineTo(x * 170, -y * 170) : ctx.moveTo(x * 170, -y * 170))); ctx.stroke(); }
      if (k === '13') { ctx.beginPath(); ctx.arc(0, 0, 50, 0, TAU); ctx.stroke(); }
      ctx.restore();
    });
  });
  const state = opts.state ?? 'lit';
  const lvl = (k) => (state === 'dark' ? 0.2 : state === 'broken' && (k === 'Z' || k === 'T') ? 0.2 : 1);
  const xs = { W: 1.28, Z: 0.66, T: 0.07, V: -0.52, 13: -1.24 }; // prop x (viewer's left = +x)
  const parts = {};
  const tubeMat = (k) => neonLevelMat(game, k, lvl(k));
  const cap = K.mat(game, 'plastic', '#2A2230');
  for (const k of keys) {
    const cx = xs[k];
    const tg2 = [];
    const strokes = NEON_PATHS[k];
    for (const st of strokes) {
      const pts = K.roundProfile(st, 0.035, 3).map(([x, y]) => [cx - x * 1.0, BY + y * 1.0, fz - 0.1]);
      tg2.push(K.tube(pts, 0.021, { seg: Math.max(8, pts.length * 3), radial: 7 }).clone());
      for (const e of [st[0], st[st.length - 1]]) g.add(K.m(K.cyl(0.026, 0.026, 0.05, { seg: 8 }).clone().rotateX(Math.PI / 2), cap, { pos: [cx - e[0], BY + e[1], fz - 0.075] }));
      // standoff clips
      const mid = st[Math.floor(st.length / 2)];
      g.add(K.m(K.cyl(0.008, 0.008, 0.07, { seg: 6 }).clone().rotateX(Math.PI / 2), chrome, { pos: [cx - mid[0], BY + mid[1], fz - 0.08] }));
    }
    let tube;
    if (k === '13') {
      // blue disc + red neon ring behind the white 13
      g.add(tm(K.cyl(0.34, 0.34, 0.05, { seg: 32, bevel: 0.015 }).clone().rotateX(-Math.PI / 2), lac, PAL.wztvBlue, { pos: [cx, BY, fz - 0.04] }));
      const ring = K.m(new THREE.TorusGeometry(0.32, 0.022, 8, 40), neonLevelMat(game, 'W', lvl(k)), { pos: [cx, BY, fz - 0.1] });
      ring.userData.noMerge = true; ring.userData.noOcclude = true;
      g.add(ring);
      parts.neon_ring = ring;
      tube = K.m(mergeGeos(tg2), tubeMat(k));
    } else tube = K.m(tg2.length > 1 ? mergeGeos(tg2) : tg2[0], tubeMat(k));
    tube.userData.noMerge = true; tube.userData.noOcclude = true;
    g.add(tube);
    parts[`neon_${k}`] = tube;
    const i = keys.indexOf(k);
    const hl = K.m(decalGeo(0.78, 0.78, [i / 5, 0, (i + 1) / 5, 1]), haloMat(game, k, lvl(k), halo), { pos: [cx, BY, k === '13' ? fz - 0.242 : fz - 0.052], cast: false });
    hl.userData.noMerge = true; hl.userData.noAO = true; hl.userData.noOcclude = true;
    g.add(hl);
    parts[`halo_${k}`] = hl;
  }
  const u = g.userData;
  u.parts = parts;
  u.neon = { keys, state };
  u.colliders = [{ min: [-W / 2 - 0.03, 0, -D / 2 - 0.12], max: [W / 2 + 0.03, H + 0.05, D / 2 + 0.03] }];
  u.lightAnchors = [{ pos: [0, BY, -1.0], color: '#FF9AC8', intensity: 1.5, distance: 5 }];
  return K.finish(game, g, { ao: { res: 64 } });
}, { category: CAT, tags: ['lobby', 'ee', 'neon', 'logo', 'partition'], size: [4.1, 2.45, 0.45], desc: 'walnut lobby partition with the neon WZTV 13 logo (4 separately lit letters)', cache: false, hero: true });

function roundRectLoop(w, h, r, n = 5) {
  const pts = [];
  const cs = [[w / 2 - r, h / 2 - r, 0], [-w / 2 + r, h / 2 - r, Math.PI / 2], [-w / 2 + r, -h / 2 + r, Math.PI], [w / 2 - r, -h / 2 + r, Math.PI * 1.5]];
  for (const [cx, cy, a0] of cs) for (let i = 0; i <= n; i++) { const a = a0 + (i / n) * (Math.PI / 2); pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r, 0]); }
  return pts;
}
// key: 'W' | 'Z' | 'T' | 'V' | '13'; level 0..1 (0.2 = dead but visibly colored; flicker by calling with noise)
export function setNeon(prop, game, key, level = 1) {
  const p = prop?.userData?.parts;
  if (!p || !game) return;
  const tube = p[`neon_${key}`];
  if (tube) tube.material = neonLevelMat(game, key, level);
  if (key === '13' && p.neon_ring) p.neon_ring.material = neonLevelMat(game, 'W', level);
  const hl = p[`halo_${key}`];
  if (hl) hl.material = haloMat(game, key, level, hl.material.map);
}

// ---------------------------------------------------------------------------------------- letter_board
// Lobby changeable-letter board on a walnut easel (cards.js 'letter_board'): parts.face (swap its map to
// getCard('letter_board', { signOff: true }) after the easter egg), two fallen letters on the floor.
registerProp('letter_board', (game, opts = {}) => {
  const g = K.prop('letter_board');
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.35 }) });
  const brass = K.mat(game, 'brass', '#C8963C');
  const FW = 1.6, FH = 1.0, CY = 1.45;
  const face = K.m(decalGeo(FW, FH), K.mat(game, 'felt', '#ffffff', { map: getCard('letter_board', { signOff: !!opts.signOff }), rim: 0.12 }), { pos: [0, CY, -0.02] });
  face.userData.noMerge = true;
  g.add(face);
  const fr = K.roundRect(FW + 0.14, FH + 0.14, 0.06);
  fr.holes.push(new THREE.Path(K.roundRect(FW - 0.1, FH - 0.1, 0.03).getPoints(4)));
  g.add(K.m(K.uvScale(K.extrude(fr, 0.07, { bevel: 0.02, curveSeg: 6 }), 1.5, 1.5), walnut, { pos: [0, CY, -0.01] }));
  g.add(K.m(K.box(FW + 0.1, FH + 0.1, 0.03, 0.01, { uv: 1.5 }), walnut, { pos: [0, CY, 0.02] }));
  // easel: two front legs + back leg, ledge
  for (const s of [-1, 1]) {
    const a = V3(s * 0.62, 0, -0.12), b = V3(s * 0.5, CY + FH / 2 + 0.18, 0.04);
    g.add(between(K.box(0.07, a.distanceTo(b), 0.05, 0.015, { uv: 1.5, swap: true }), walnut, a, b).translateY(a.distanceTo(b) / 2));
    g.add(K.m(K.cyl(0.03, 0.035, 0.03, { seg: 8 }), brass, { pos: [s * 0.62, 0, -0.12] }));
    g.add(K.m(K.lathe([[0, 0], [0.035, 0], [0.04, 0.03], [0, 0.07]], { round: 0.01, seg: 10 }), brass, { pos: [s * 0.5, CY + FH / 2 + 0.2, 0.04] }));
  }
  const bl = [V3(0, 0, 0.7), V3(0, CY + FH / 2 + 0.1, 0.06)];
  g.add(between(K.box(0.06, bl[0].distanceTo(bl[1]), 0.045, 0.015, { uv: 1.5, swap: true }), walnut, bl[0], bl[1]).translateY(bl[0].distanceTo(bl[1]) / 2));
  g.add(K.m(K.box(FW + 0.2, 0.05, 0.14, 0.018, { uv: 1.5 }), walnut, { pos: [0, CY - FH / 2 - 0.09, -0.05] }));
  // fallen letters on the floor
  const lt = cv('fallen_letters', 128, 64, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    text(ctx, 'G', 32, 34, { font: FONT.sign, size: 52, fill: '#F4F1E8' });
    text(ctx, 'F', 96, 34, { font: FONT.sign, size: 52, fill: '#F4F1E8' });
  });
  const ltMat = K.mat(game, 'plastic', '#ffffff', { map: lt, alphaTest: 0.5 });
  [[0, 0.3, -0.45, 0.4], [1, -0.25, -0.62, -0.7]].forEach(([i, x, z, r]) => {
    const gg = new THREE.PlaneGeometry(0.1, 0.1); K.uvRect(gg, i / 2, 0.05, (i + 1) / 2, 0.95); gg.rotateX(-Math.PI / 2);
    g.add(K.m(gg, ltMat, { pos: [x, 0.004, z], rot: [0, r, 0] }));
  });
  const u = g.userData;
  u.parts = { face };
  u.colliders = [{ min: [-0.9, 0, -0.2], max: [0.9, CY + FH / 2 + 0.3, 0.75] }];
  return K.finish(game, g, { ao: { res: 48 } });
}, { category: CAT, tags: ['lobby', 'ee', 'sign'], size: [1.8, 2.2, 0.9], desc: 'changeable-letter lobby board on a walnut easel' });

// ---------------------------------------------------------------------------------------- weather_map
// Newsroom magnetic weather map (ee_weather_map), wall mounted (back at local z ~ +0.05): cards.js weather_map
// face in a chunky teal frame, light hood, tray with a pointer and the spare storm magnet.
// parts.magnet_sun_a/sun_b/cloud/rain/bolt/storm (Meshes: slide by moving .position.x/.y on the face plane).
// anchors.tower_icon (face point of the red tower), anchors.face_z; showMagnet(prop, name, [x,y]|null).
const MAGNETS = [['sun_a', 'sun', 0.25, 0.38], ['sun_b', 'sun', 0.6, 0.3], ['cloud', 'cloud', 0.43, 0.62], ['rain', 'rain', 0.18, 0.72], ['bolt', 'bolt', 0.62, 0.72]];
registerProp('weather_map', (game) => {
  const g = K.prop('weather_map');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const MW = 2.2, MH = 1.65, CY = 1.55, fz = -0.06;
  g.add(K.m(decalGeo(MW, MH), K.mat(game, 'lacquer', '#ffffff', { map: getCard('weather_map') }), { pos: [0, CY, fz] }));
  const fr = K.roundRect(MW + 0.22, MH + 0.22, 0.1);
  fr.holes.push(new THREE.Path(K.roundRect(MW - 0.04, MH - 0.04, 0.05).getPoints(5)));
  g.add(tm(K.extrude(fr, 0.1, { bevel: 0.03, curveSeg: 8 }), lac, PAL.teal, { pos: [0, CY, fz + 0.02] }));
  g.add(tm(K.box(MW + 0.1, MH + 0.1, 0.05, 0.02), lac, '#23307A', { pos: [0, CY, 0.0] }));
  // light hood with glowing underside + plaque
  const hood = new THREE.CylinderGeometry(0.16, 0.16, MW + 0.2, 20, 1, false, Math.PI * 0.5, Math.PI);
  hood.rotateZ(Math.PI / 2);
  g.add(tm(hood, lac, PAL.teal, { pos: [0, CY + MH / 2 + 0.2, fz - 0.12] }));
  g.add(K.m(K.box(MW + 0.1, 0.02, 0.16, 0.008), K.glow(game, '#FFF2D8', 2.0), { pos: [0, CY + MH / 2 + 0.1, fz - 0.12], cast: false }));
  for (const s of [-1, 1]) g.add(K.m(K.tube([[s * (MW / 2 - 0.1), CY + MH / 2 + 0.2, fz - 0.05], [s * (MW / 2 - 0.1), CY + MH / 2 + 0.28, fz + 0.03]], 0.014, { seg: 3, radial: 6 }), chrome));
  const plq = K.tex.label('WEATHER WATCH 13', { bg: PAL.wztvBlue, fg: '#F4F1E8', accent: PAL.harvestGold, w: 512, h: 96, border: 0.12, wear: 0.05 });
  g.add(K.m(decalGeo(0.9, 0.17), K.mat(game, 'lacquer', '#ffffff', { map: plq }), { pos: [0, CY + MH / 2 + 0.2, fz - 0.285] }));
  // tray, pointer, eraser
  g.add(tm(K.box(MW + 0.1, 0.05, 0.16, 0.02), lac, PAL.teal, { pos: [0, CY - MH / 2 - 0.14, fz - 0.07] }));
  g.add(tm(K.box(MW + 0.1, 0.06, 0.02, 0.008), lac, PAL.teal, { pos: [0, CY - MH / 2 - 0.1, fz - 0.15] }));
  g.add(K.m(K.cyl(0.008, 0.012, 0.9, { seg: 8 }).clone().rotateZ(Math.PI / 2).translate(0.45, 0, 0), K.mat(game, 'teak', '#ffffff', { map: K.tex.wood(PAL.teak) }), { pos: [-0.3, CY - MH / 2 - 0.1, fz - 0.07] }));
  g.add(tm(K.box(0.14, 0.05, 0.06, 0.015), lac, PAL.channelRed, { pos: [0.75, CY - MH / 2 - 0.09, fz - 0.07] }));
  // magnets
  const parts = {};
  const place = (u, v) => [(0.5 - u) * MW, CY + (0.5 - v) * MH];
  const addMag = (name, kind, x, y, z) => {
    const m = K.m(decalGeo(0.3, 0.3), K.mat(game, 'plastic', '#ffffff', { map: getCard(`magnet_${kind}`), alphaTest: 0.35 }), { pos: [x, y, z] });
    m.userData.noMerge = true; m.userData.noOcclude = true;
    g.add(m);
    parts[`magnet_${name}`] = m;
  };
  for (const [name, kind, u, v] of MAGNETS) { const [x, y] = place(u, v); addMag(name, kind, x, y, fz - 0.012); }
  addMag('storm', 'storm', -0.65, CY - MH / 2 - 0.02, fz - 0.1);
  parts.magnet_storm.rotation.x = -0.25;
  const [tx, ty] = place(400 / 512, (238 - 16) / 384);
  const u = g.userData;
  u.parts = parts;
  u.anchors = { tower_icon: [tx, ty, fz - 0.012], face_z: fz - 0.012, face: { w: MW, h: MH, cy: CY } };
  u.colliders = [{ min: [-MW / 2 - 0.15, CY - MH / 2 - 0.2, -0.3], max: [MW / 2 + 0.15, CY + MH / 2 + 0.4, 0.05] }];
  u.lightAnchors = [{ pos: [0, CY + 0.3, -0.7], color: '#FFF2D8', intensity: 1.3, distance: 4 }];
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['newsroom', 'ee', 'weather', 'wall'], size: [2.45, 2.6, 0.4], desc: 'magnetic Tri-County weather map with sliding magnets' });

// name: sun_a | sun_b | cloud | rain | bolt | storm ; pos [x,y] on the face (local) or null to hide
export function showMagnet(prop, name, pos) {
  const m = prop?.userData?.parts?.[`magnet_${name}`];
  if (!m) return;
  if (!pos) { m.visible = false; return; }
  m.visible = true;
  m.position.x = pos[0]; m.position.y = pos[1]; m.position.z = prop.userData.anchors.face_z - 0.004; m.rotation.x = 0;
}

// ---------------------------------------------------------------------------------------- rundown_board
// Master Control rundown cork board (ee_rundown_board): "SPOOKTACULAR RUNDOWN" header, six empty marker-outlined
// slots with push pins; parts.card_1..card_6 (hidden; setRundownCard(prop, n, true) pins card n with its star).
// opts.filled = how many cards are shown (default 0).
registerProp('rundown_board', (game, opts = {}) => {
  const g = K.prop('rundown_board');
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.3 }) });
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const BW = 1.8, BH = 1.25, CY = 1.5, fz = -0.03;
  const slots = [];
  for (let r = 0; r < 2; r++) for (let c = 0; c < 3; c++) slots.push([(1 - c) * 0.56, CY + 0.04 - r * 0.42]);
  const cork = cv('rundown_cork', 512, 384, (ctx, w, h, rand) => {
    ctx.fillStyle = '#C8955A'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 5000; i++) { ctx.fillStyle = rand() < 0.5 ? 'rgba(120,70,30,0.35)' : 'rgba(240,200,140,0.3)'; ctx.fillRect(rand() * w, rand() * h, 1 + rand() * 2.5, 1 + rand() * 2); }
    // slot outlines (canvas coords: viewer left = canvas left)
    ctx.setLineDash([10, 7]); ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(60,30,60,0.55)';
    for (let r = 0; r < 2; r++) for (let c = 0; c < 3; c++) {
      const x = w / 2 + (c - 1) * (0.56 / BW) * w, y = h / 2 - (0.04 - r * 0.42) / BH * h;
      const sw = (0.44 / BW) * w, sh = (0.28 / BH) * h;
      rrect(ctx, x - sw / 2, y - sh / 2, sw, sh, 8); ctx.stroke();
      ctx.setLineDash([]); text(ctx, String(r * 3 + c + 1), x, y + 4, { font: FONT.hand, size: 34, fill: 'rgba(60,30,60,0.35)' }); ctx.setLineDash([10, 7]);
    }
    ctx.setLineDash([]);
  });
  g.add(K.m(decalGeo(BW, BH), K.mat(game, 'felt', '#ffffff', { map: cork, rim: 0.12 }), { pos: [0, CY, fz] }));
  const fr = K.roundRect(BW + 0.14, BH + 0.14, 0.05);
  fr.holes.push(new THREE.Path(K.roundRect(BW - 0.02, BH - 0.02, 0.02).getPoints(4)));
  g.add(K.m(K.uvScale(K.extrude(fr, 0.06, { bevel: 0.018, curveSeg: 5 }), 1.5, 1.5), walnut, { pos: [0, CY, fz + 0.01] }));
  g.add(K.m(K.box(BW + 0.08, BH + 0.08, 0.03, 0.01, { uv: 1.5 }), walnut, { pos: [0, CY, 0.01] }));
  // header card
  g.add(K.m(decalGeo(0.96, 0.24), K.mat(game, 'paint', '#ffffff', { map: getCard('rundown_header') }), { pos: [0, CY + BH / 2 - 0.2, fz - 0.006], rot: [0, 0, 0.01] }));
  // push pins
  const pinCols = [PAL.channelRed, PAL.barYellow, PAL.wztvBlue, PAL.barGreen, PAL.channelRed, PAL.plum];
  const pinHead = K.lathe([[0, 0], [0.018, 0], [0.02, 0.012], [0.012, 0.022], [0.016, 0.032], [0, 0.034]], { round: 0.004, seg: 10 }).clone();
  pinHead.rotateX(-Math.PI / 2);
  slots.forEach(([x, y], i) => g.add(tm(pinHead, lac, pinCols[i], { pos: [x, y + 0.11, fz - 0.004] })));
  for (const [x, y] of [[-0.43, CY + BH / 2 - 0.2], [0.43, CY + BH / 2 - 0.2]]) g.add(tm(pinHead, lac, PAL.channelRed, { pos: [x, y, fz - 0.01] }));
  // old memo in the corner
  const memo = cv('rundown_memo', 128, 160, (ctx, w, h) => {
    ctx.fillStyle = '#FFF6A8'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = 'rgba(0,0,0,0.08)'; ctx.fillRect(0, h - 10, w, 10);
    ['SIGN OFF', '12:00 AM', 'DON\'T FORGET', 'THE TAPE!'].forEach((l, i) => text(ctx, l, w / 2, 30 + i * 32, { font: FONT.hand, size: 18, fill: '#2A2A8A', rot: -0.04 }));
  });
  g.add(K.m(decalGeo(0.2, 0.25), K.mat(game, 'paint', '#ffffff', { map: memo }), { pos: [-BW / 2 + 0.17, CY - BH / 2 + 0.2, fz - 0.005], rot: [0, 0, 0.12] }));
  g.add(tm(pinHead, lac, PAL.barGreen, { pos: [-BW / 2 + 0.17, CY - BH / 2 + 0.3, fz - 0.009] }));
  // the six cards (hidden until earned)
  const parts = {};
  const filled = opts.filled ?? 0;
  slots.forEach(([x, y], i) => {
    const c = K.m(decalGeo(0.42, 0.26), K.mat(game, 'paint', '#ffffff', { map: getCard(`rundown_card_${i + 1}`, { star: true }) }), { pos: [x, y, fz - 0.008] });
    c.rotation.z = ((i * 37) % 7 - 3) * 0.012;
    c.visible = i < filled;
    c.userData.noMerge = true;
    g.add(c);
    parts[`card_${i + 1}`] = c;
  });
  const u = g.userData;
  u.parts = parts;
  u.anchors = { slots: slots.map(([x, y]) => [x, y, fz - 0.008]) };
  u.colliders = [{ min: [-BW / 2 - 0.08, CY - BH / 2 - 0.08, -0.1], max: [BW / 2 + 0.08, CY + BH / 2 + 0.08, 0.04] }];
  return K.finish(game, g, { ao: { res: 48, floor: false, height: 0 } });
}, { category: CAT, tags: ['master_control', 'ee', 'board', 'wall'], size: [1.95, 1.4, 0.1], desc: 'Spooktacular rundown cork board with six trophy slots' });

export function setRundownCard(prop, n, on = true) {
  const c = prop?.userData?.parts?.[`card_${n}`];
  if (c) c.visible = !!on;
}

// ---------------------------------------------------------------------------------------- kill_switch_cage
// Transmitter kill-switch cage (ee_kill_switch): red steel frame with expanded-metal mesh, hinged padlocked door
// (parts.door, pivot on the viewer's left edge, open = rotation.y ~ -1.7), and inside a giant knife switch on a
// slate panel (parts.switch: pivot at the hinge clips, closed/up = 0, thrown/down = rotation.x ~ +1.9).
// Back of the cage at local +z (against the tower leg). anchors.handle for the hold prompt.
registerProp('kill_switch_cage', (game) => {
  const g = K.prop('kill_switch_cage');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const paint = K.mat(game, 'paint', '#ffffff');
  const copper = K.mat(game, 'brass', '#D07A4A', { rough: 0.3 });
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const W = 1.3, H = 2.1, D = 0.8, RED = '#C8282E';
  const meshTex = cv('cage_mesh', 128, 128, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 5; ctx.lineJoin = 'round';
    for (let y = -32; y <= h + 32; y += 32) for (let x = -32; x <= w + 32; x += 32) { ctx.beginPath(); ctx.moveTo(x, y + 16); ctx.lineTo(x + 16, y); ctx.lineTo(x + 32, y + 16); ctx.lineTo(x + 16, y + 32); ctx.closePath(); ctx.stroke(); }
  }, true);
  const mesh = K.mat(game, 'metal', RED, { map: meshTex, alphaTest: 0.5, side: THREE.DoubleSide });
  // concrete pad
  const conc = cv('concrete', 256, 256, (ctx, w, h, rand) => { ctx.fillStyle = '#9A9490'; ctx.fillRect(0, 0, w, h); speckle(ctx, w, h, rand, 1800, 0.12); }, true);
  g.add(K.m(K.box(W + 0.4, 0.1, D + 0.4, 0.03, { uv: 1 }), K.mat(game, 'paint', '#ffffff', { map: conc }), { pos: [0, 0.05, 0] }));
  const Y0 = 0.1;
  // frame edges (except the front door opening)
  const post = (x, z) => g.add(tm(K.box(0.06, H, 0.06, 0.012), paint, RED, { pos: [x, Y0 + H / 2, z] }));
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) post(x * (W / 2 - 0.03), z * (D / 2 - 0.03));
  for (const y of [Y0 + 0.03, Y0 + H - 0.03, Y0 + H / 2]) {
    g.add(tm(K.box(W, 0.05, 0.05, 0.012), paint, RED, { pos: [0, y, D / 2 - 0.03] }));
    for (const s of [-1, 1]) g.add(tm(K.box(0.05, 0.05, D, 0.012), paint, RED, { pos: [s * (W / 2 - 0.03), y, 0] }));
  }
  g.add(tm(K.box(W, 0.05, 0.05, 0.012), paint, RED, { pos: [0, Y0 + H - 0.03, -D / 2 + 0.03] }));
  // mesh panels: sides + top
  for (const s of [-1, 1]) { const p = new THREE.PlaneGeometry(D - 0.06, H - 0.06); K.uvScale(p, 5, 13); p.rotateY(Math.PI / 2); g.add(K.m(p, mesh, { pos: [s * (W / 2 - 0.03), Y0 + H / 2, 0] })); }
  { const p = new THREE.PlaneGeometry(W - 0.06, D - 0.06); K.uvScale(p, 8, 5); p.rotateX(-Math.PI / 2); g.add(K.m(p, mesh, { pos: [0, Y0 + H - 0.03, 0] })); }
  // back panel with the knife switch
  g.add(tm(K.box(W - 0.14, H - 0.3, 0.04, 0.012), paint, '#6A7078', { pos: [0, Y0 + H / 2 + 0.05, D / 2 - 0.06] }));
  const PZ = D / 2 - 0.1;
  g.add(tm(K.box(0.56, 0.86, 0.05, 0.02), lac, '#3A3A44', { pos: [0, Y0 + 1.15, PZ] }));
  g.add(tm(K.box(0.5, 0.8, 0.03, 0.02), lac, '#EDE6D6', { pos: [0, Y0 + 1.15, PZ - 0.035] }));
  const JY = Y0 + 1.44, HY = Y0 + 0.86, SZ = PZ - 0.07;
  for (const x of [-0.11, 0.11]) {
    for (const [y, hh] of [[JY, 0.12], [HY, 0.08]]) {
      g.add(K.m(K.box(0.018, hh, 0.07, 0.005), copper, { pos: [x - 0.028, y, SZ + 0.02] }), K.m(K.box(0.018, hh, 0.07, 0.005), copper, { pos: [x + 0.028, y, SZ + 0.02] }));
      g.add(K.m(K.box(0.08, 0.03, 0.03, 0.008), copper, { pos: [x, y - hh / 2, SZ + 0.04] }));
    }
  }
  const sw = new THREE.Group();
  sw.position.set(0, HY, SZ);
  for (const x of [-0.11, 0.11]) sw.add(K.m(K.box(0.03, 0.62, 0.012, 0.005), copper, { pos: [x, 0.31, 0] }));
  sw.add(K.m(K.cyl(0.016, 0.016, 0.3, { seg: 8 }).clone().rotateZ(Math.PI / 2).translate(0.15, 0, 0), chrome, { pos: [0, 0.6, 0] }));
  sw.add(tm(K.box(0.3, 0.06, 0.06, 0.025), lac, PAL.channelRed, { pos: [0, 0.66, -0.02] }));
  sw.add(tm(K.cyl(0.03, 0.035, 0.18, { seg: 10, bevel: 0.012 }).clone().rotateX(-Math.PI / 2), lac, PAL.channelRed, { pos: [0, 0.66, -0.04] }));
  sw.add(tm(new THREE.SphereGeometry(0.05, 12, 9), lac, PAL.channelRed, { pos: [0, 0.66, -0.23] }));
  K.merge(sw);
  sw.userData.noMerge = true;
  g.add(sw);
  // labels
  const signs = cv('killswitch_signs', 256, 256, (ctx, w, h) => {
    rrect(ctx, 4, 4, 248, 120, 14); ctx.fillStyle = '#F4C81E'; ctx.fill(); ctx.lineWidth = 6; ctx.strokeStyle = '#1E1530'; ctx.stroke();
    poly(ctx, [[46, 20], [20, 70], [40, 70], [28, 110], [66, 56], [46, 56]]); ctx.fillStyle = '#1E1530'; ctx.fill();
    text(ctx, 'DANGER', 160, 44, { font: FONT.sign, size: 38, fill: '#1E1530' });
    text(ctx, 'HIGH VOLTAGE', 160, 90, { font: FONT.sign, size: 20, fill: PAL.channelRed, maxW: 170 });
    rrect(ctx, 4, 132, 248, 120, 12); ctx.fillStyle = '#EDE6D6'; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = PAL.channelRed; ctx.stroke();
    text(ctx, 'KILL SWITCH', 128, 172, { font: FONT.sign, size: 30, fill: PAL.channelRed, maxW: 230 });
    text(ctx, 'TRANSMITTER · WZTV 13', 128, 214, { font: FONT.round, size: 17, fill: '#3A3A44', maxW: 230 });
  });
  const signMat = K.mat(game, 'paint', '#ffffff', { map: signs });
  g.add(K.m(decalGeo(0.46, 0.22, [0, 0, 1, 0.5]), signMat, { pos: [0, Y0 + 1.72, PZ - 0.03] }));
  // door (front): frame + mesh + hasp + padlock; pivot at the viewer's left (+x) edge
  const door = new THREE.Group();
  door.position.set(W / 2 - 0.03, 0, -D / 2 + 0.03);
  const dw = W - 0.08;
  door.add(tm(K.box(0.05, H - 0.1, 0.05, 0.012), paint, RED, { pos: [-0.02, Y0 + H / 2, 0] }), tm(K.box(0.05, H - 0.1, 0.05, 0.012), paint, RED, { pos: [-dw + 0.03, Y0 + H / 2, 0] }));
  for (const y of [Y0 + 0.08, Y0 + H - 0.1, Y0 + H / 2]) door.add(tm(K.box(dw, 0.05, 0.05, 0.012), paint, RED, { pos: [-dw / 2, y, 0] }));
  { const p = new THREE.PlaneGeometry(dw - 0.05, H - 0.2); K.uvScale(p, 8, 13); door.add(K.m(p, mesh, { pos: [-dw / 2, Y0 + H / 2, 0] })); }
  door.add(K.m(decalGeo(0.4, 0.2, [0, 0.5, 1, 1]), signMat, { pos: [-dw / 2, Y0 + 1.25, -0.03] }));
  door.add(K.m(K.box(0.1, 0.05, 0.03, 0.008), chrome, { pos: [-dw + 0.02, Y0 + 1.0, -0.03] }));
  door.add(tm(K.box(0.09, 0.1, 0.035, 0.015), lac, '#C8963C', { pos: [-dw + 0.0, Y0 + 0.9, -0.05] }));
  door.add(K.m(new THREE.TorusGeometry(0.03, 0.008, 5, 12, Math.PI), chrome, { pos: [-dw + 0.0, Y0 + 0.95, -0.05] }));
  K.merge(door);
  door.userData.noMerge = true;
  g.add(door);
  for (const y of [Y0 + 0.4, Y0 + H - 0.4]) g.add(K.m(K.cyl(0.018, 0.018, 0.12, { seg: 8 }), chrome, { pos: [W / 2 - 0.02, y - 0.06, -D / 2 + 0.03] }));
  // conduits up the tower
  for (const x of [-0.35, 0.35]) g.add(tm(K.tube([[x, Y0 + 1.6, PZ], [x, Y0 + H - 0.2, PZ], [x * 0.8, Y0 + H + 0.2, D / 2 - 0.05], [x * 0.8, Y0 + H + 1.2, D / 2 - 0.05]], 0.03, { seg: 12, radial: 6 }), paint, '#8A9098'));
  const u = g.userData;
  u.parts = { door, switch: sw };
  u.anchors = { handle: [0, HY + 0.66, SZ - 0.23] };
  u.interact = { point: [0, 1.2, -D / 2 - 0.4], radius: 1.3 };
  u.colliders = [{ min: [-W / 2 - 0.02, 0, -D / 2 - 0.02], max: [W / 2 + 0.02, Y0 + H + 0.05, D / 2 + 0.02] }];
  return K.finish(game, g, { ao: { res: 60 } });
}, { category: CAT, tags: ['yard', 'ee', 'tower', 'switch'], size: [1.7, 3.4, 1.2], desc: 'red mesh kill-switch cage with a giant knife switch', hero: true });

// ---------------------------------------------------------------------------------------- perpetua_crate
// The opened Perpetua-Tube shipping crate (MC floor [33.8,0,-4.0]): plank crate with stencils and a shipping
// label, lid leaning on its side with nails, golden excelsior straw spilling out (empty tube-shaped nest), crowbar.
registerProp('perpetua_crate', (game) => {
  const g = K.prop('perpetua_crate');
  const wood = K.mat(game, 'teak', '#ffffff', { map: K.tex.wood('#C89A62', { dark: 0.28, wear: 0.4 }) });
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const W = 1.0, H = 0.62, D = 0.7;
  const rnd = mulberry32(77);
  // planked walls
  const plankH = H / 3;
  for (let i = 0; i < 3; i++) {
    const y = plankH * (i + 0.5);
    for (const s of [-1, 1]) {
      g.add(K.m(K.box(W, plankH - 0.012, 0.03, 0.008, { uv: 1.3, swap: true }), wood, { pos: [0, y, s * (D / 2 - 0.015)], rot: [0, 0, (rnd() - 0.5) * 0.01] }));
      g.add(K.m(K.box(0.03, plankH - 0.012, D - 0.06, 0.008, { uv: 1.3, swap: true }), wood, { pos: [s * (W / 2 - 0.015), y, 0] }));
    }
  }
  g.add(K.m(K.box(W - 0.06, 0.03, D - 0.06, 0.008, { uv: 1.3 }), wood, { pos: [0, 0.04, 0] }));
  // corner battens (darker)
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(tm(K.box(0.07, H + 0.02, 0.07, 0.012, { uv: 1.3, swap: true }), wood, '#A87A4A', { pos: [x * (W / 2 - 0.02), H / 2, z * (D / 2 - 0.02)] }));
  for (const s of [-1, 1]) g.add(tm(K.box(W + 0.02, 0.07, 0.04, 0.012, { uv: 1.3 }), wood, '#A87A4A', { pos: [0, H - 0.03, s * (D / 2 + 0.005)] }));
  // stencils + shipping label
  const sten = cv('crate_stencils', 512, 256, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    ctx.globalAlpha = 0.85;
    text(ctx, 'PERPETUA-TUBE', w / 2, 44, { font: FONT.sign, size: 50, fill: '#2A5A2A', maxW: w * 0.9, track: 2 });
    text(ctx, 'ETERNAL SIGNAL TUBE CO.', w / 2, 92, { font: FONT.sign, size: 22, fill: '#2A2A2A', maxW: w * 0.8 });
    text(ctx, 'FRAGILE', 140, 160, { font: FONT.sign, size: 42, fill: '#B5282A', rot: -0.06 });
    ctx.strokeStyle = '#2A2A2A'; ctx.lineWidth = 8;
    for (const x of [360, 420]) { ctx.beginPath(); ctx.moveTo(x, 200); ctx.lineTo(x, 130); ctx.moveTo(x - 18, 150); ctx.lineTo(x, 128); ctx.lineTo(x + 18, 150); ctx.stroke(); }
    text(ctx, 'THIS SIDE UP', 390, 224, { font: FONT.sign, size: 18, fill: '#2A2A2A' });
    ctx.globalAlpha = 1;
    // shipping label (bottom-left cell)
    ctx.save(); ctx.translate(20, 190); ctx.rotate(0.03);
    ctx.fillStyle = '#F6EFD8'; ctx.fillRect(0, 0, 150, 58);
    ctx.fillStyle = PAL.channelRed; ctx.fillRect(0, 0, 150, 12);
    text(ctx, 'SHIP TO: WZTV CH.13', 75, 26, { font: FONT.round, size: 11, fill: '#2A2A2A' });
    text(ctx, 'TRANSMITTER DEPT.', 75, 42, { font: FONT.round, size: 11, fill: '#2A2A2A' });
    ctx.restore();
  });
  const stMat = K.mat(game, 'paint', '#ffffff', { map: sten, alphaTest: 0.3 });
  g.add(K.m(decalGeo(0.92, 0.46), stMat, { pos: [0, H / 2, -D / 2 - 0.032] }));
  g.add(K.m(decalGeo(0.66, 0.33, [0, 0.62, 1, 1]), stMat, { pos: [W / 2 + 0.032, H / 2 + 0.05, 0], rot: [0, -Math.PI / 2, 0] }));
  // straw: lumpy golden mound + loose strands spilling over the rim and on the floor
  const strawTex = cv('excelsior', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#A07A30'; ctx.fillRect(0, 0, w, h);
    ctx.lineCap = 'round';
    for (let i = 0; i < 700; i++) {
      ctx.strokeStyle = ['#F2D07A', '#E0B458', '#C8963C', '#FFE6A0'][Math.floor(rand() * 4)];
      ctx.globalAlpha = 0.5 + rand() * 0.4; ctx.lineWidth = 2 + rand() * 2.5;
      const x = rand() * w, y = rand() * h, a = rand() * TAU, l = 10 + rand() * 30;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.quadraticCurveTo(x + Math.cos(a + 1) * l * 0.5, y + Math.sin(a + 1) * l * 0.5, x + Math.cos(a) * l, y + Math.sin(a) * l); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }, true);
  const straw = K.mat(game, 'paint', '#ffffff', { map: strawTex });
  const mound = (x, y, z, rx, ry, rz, ph) => {
    const sg2 = new THREE.SphereGeometry(1, 14, 8);
    const p = sg2.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const X = p.getX(i), Y = p.getY(i), Z = p.getZ(i);
      const k = 1 + 0.16 * Math.sin(X * 7 + Z * 5 + ph) * Math.cos(Y * 6 - X * 4) + 0.12 * Math.sin(X * 23 + Y * 17 + ph) * Math.sin(Z * 29 - Y * 13);
      p.setXYZ(i, X * k * rx, Math.max(Y, -0.2) * k * ry, Z * k * rz);
    }
    sg2.computeVertexNormals();
    g.add(K.m(K.uvScale(sg2, 3, 1.5), straw, { pos: [x, y, z] }));
  };
  mound(0, H - 0.04, 0, 0.5, 0.2, 0.33, 0);
  mound(0.36, H - 0.02, -0.22, 0.2, 0.1, 0.16, 2);
  mound(-0.34, H - 0.03, 0.2, 0.2, 0.1, 0.17, 4);
  mound(0.62, 0.04, -0.46, 0.18, 0.09, 0.15, 5);
  mound(-0.2, 0.03, -0.6, 0.14, 0.06, 0.12, 7);
  // empty nest (dark hollow where the tube lay)
  const nest = new THREE.CircleGeometry(0.2, 18); nest.scale(1.8, 1, 1); nest.rotateX(-Math.PI / 2);
  g.add(K.m(nest, K.mat(game, 'fabric', '#5A3A14'), { pos: [0, H + 0.13, 0.0] }));
  const strawStrand = K.mat(game, 'plastic', '#E8C068', { rough: 0.7 });
  for (let i = 0; i < 22; i++) {
    const onFloor = i > 13;
    const a = rnd() * TAU;
    const x0 = onFloor ? Math.cos(a) * (0.6 + rnd() * 0.3) : (rnd() - 0.5) * W;
    const z0 = onFloor ? Math.sin(a) * (0.5 + rnd() * 0.25) : (rnd() < 0.5 ? -1 : 1) * (D / 2);
    const y0 = onFloor ? 0.01 : H + 0.02;
    const pts = [];
    for (let k = 0; k < 5; k++) pts.push([x0 + Math.cos(a + k) * 0.03 * k, onFloor ? 0.008 + (k % 2) * 0.004 : y0 - k * 0.04 + Math.sin(k) * 0.02, z0 + Math.sin(a + k * 1.3) * 0.03 * k + (onFloor ? 0 : Math.sign(z0) * k * 0.025)]);
    g.add(tm(K.tube(pts, 0.004, { seg: 8, radial: 3 }), strawStrand, ['#F2D07A', '#E0B458', '#FFE6A0'][i % 3]));
  }
  // leaning lid with nails
  const lid = new THREE.Group();
  for (let i = 0; i < 4; i++) lid.add(K.m(K.box(0.24, 0.025, D, 0.008, { uv: 1.3 }), wood, { pos: [-0.36 + i * 0.245, 0, 0] }));
  for (const s of [-1, 1]) lid.add(tm(K.box(W, 0.03, 0.08, 0.01, { uv: 1.3 }), wood, '#A87A4A', { pos: [0, -0.02, s * (D / 2 - 0.08)] }));
  for (let i = 0; i < 6; i++) lid.add(K.m(K.cyl(0.004, 0.004, 0.05, { seg: 4 }), chrome, { pos: [-0.4 + i * 0.16, 0.01, (i % 2 ? 1 : -1) * (D / 2 - 0.08)] }));
  lid.position.set(-0.93, 0.35, 0.05);
  lid.rotation.set(0, 0, 0.64);
  g.add(lid);
  // crowbar
  g.add(tm(K.tube([[0.35, 0.02, -0.62], [0.9, 0.02, -0.5], [0.97, 0.03, -0.46], [0.99, 0.06, -0.42]], 0.014, { seg: 12, radial: 6 }), lac, PAL.channelRed));
  const u = g.userData;
  u.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, H + 0.1, D / 2] }, { min: [-1.35, 0, -D / 2], max: [-W / 2, 0.6, D / 2] }];
  return K.finish(game, g, { ao: { res: 56 } });
}, { category: CAT, tags: ['master_control', 'crate', 'ee'], size: [1.5, 0.75, 1.4], desc: 'opened Perpetua-Tube crate with excelsior straw', hero: true });

// ---------------------------------------------------------------------------------------- dressing_room_door
// Green-room dressing-room door (fake, in the wall): casing trim, painted slab from cards.js
// 'dressing_room_doors' (star decal + name), brass knob, hinges, sconce bulb above. opts.who: skip | roxy | penny
// | duke | baron (porthole with a brass ring). Back of the casing at local z = 0 (wall plane), front -Z.
registerProp('dressing_room_door', (game, opts = {}) => {
  const who = opts.who ?? 'skip';
  const g = K.prop('dressing_room_door');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const brass = K.mat(game, 'brass', '#C8963C');
  const SW = 0.9, SH = 2.02;
  const cas = [[-SW / 2 - 0.12, 0], [-SW / 2, 0], [-SW / 2, SH], [SW / 2, SH], [SW / 2, 0], [SW / 2 + 0.12, 0], [SW / 2 + 0.12, SH + 0.12], [-SW / 2 - 0.12, SH + 0.12]];
  g.add(tm(K.extrude(cas, 0.06, { bevel: 0.018 }), lac, '#F6E7C8', { pos: [0, 0, -0.03] }));
  g.add(tm(K.box(SW + 0.3, 0.06, 0.09, 0.02), lac, '#F6E7C8', { pos: [0, SH + 0.15, -0.035] }));
  const slab = K.m(decalGeo(SW - 0.02, SH - 0.02), K.mat(game, 'lacquer', '#ffffff', { map: getCard('dressing_room_doors', { who }) }), { pos: [0, SH / 2 + 0.01, -0.035] });
  g.add(slab);
  g.add(tm(K.box(SW - 0.01, SH - 0.01, 0.04, 0.012), lac, '#3A2A2A', { pos: [0, SH / 2 + 0.01, -0.012] }));
  // knob + escutcheon (viewer's right = -x), hinges on the left
  g.add(K.m(K.box(0.06, 0.16, 0.012, 0.005), brass, { pos: [-SW / 2 + 0.1, 1.0, -0.042] }));
  const knob = K.lathe([[0, 0], [0.018, 0], [0.018, 0.03], [0.034, 0.05], [0.036, 0.07], [0.02, 0.085], [0, 0.086]], { round: 0.006, seg: 14 }).clone();
  knob.rotateX(-Math.PI / 2);
  g.add(K.m(knob, brass, { pos: [-SW / 2 + 0.1, 1.0, -0.046] }));
  for (const y of [0.3, 1.0, 1.72]) g.add(K.m(K.cyl(0.012, 0.012, 0.12, { seg: 8 }), brass, { pos: [SW / 2 - 0.005, y, -0.045] }));
  if (who === 'baron') {
    const py = SH + 0.01 - (110 / 512) * (SH - 0.02), pr = (62 / 256) * (SW - 0.02);
    g.add(K.m(new THREE.TorusGeometry(pr + 0.02, 0.028, 8, 28), brass, { pos: [0, py, -0.05] }));
    const gl = new THREE.CircleGeometry(pr, 24); gl.rotateY(Math.PI);
    g.add(K.m(gl, game.mats.glass('#CFE0FF', { opacity: 0.25 }), { pos: [0, py, -0.056] }));
  }
  // sconce with a bulb above the door
  g.add(K.m(K.lathe([[0, 0], [0.06, 0], [0.065, 0.02], [0.03, 0.05], [0, 0.05]], { seg: 12 }).clone().rotateX(-Math.PI / 2), brass, { pos: [0, SH + 0.32, -0.04] }));
  const bulb = K.m(new THREE.SphereGeometry(0.055, 12, 9), K.glow(game, '#FFD08A', 2.4), { pos: [0, SH + 0.32, -0.13], cast: false });
  bulb.userData.noOcclude = true;
  g.add(bulb);
  g.add(K.m(K.cyl(0.012, 0.012, 0.06, { seg: 8 }).clone().rotateX(-Math.PI / 2), brass, { pos: [0, SH + 0.32, -0.07] }));
  const u = g.userData;
  u.colliders = [{ min: [-SW / 2 - 0.12, 0, -0.08], max: [SW / 2 + 0.12, SH + 0.4, 0.0] }];
  u.lightAnchors = [{ pos: [0, SH + 0.3, -0.35], color: '#FFD08A', intensity: 1.0, distance: 3 }];
  return K.finish(game, g, { ao: { res: 44 } });
}, { category: CAT, tags: ['green_room', 'door', 'wall', 'fake'], size: [1.14, 2.45, 0.14], desc: 'dressing-room door with star decal (opts.who)' });

// =========================================================================================================
// PROPVIEW SCENES (set-dressing previews; camera looks toward +z, props face -z)
// =========================================================================================================
registerScene('sets_studio_a', {
  floor: 'wood', floorColor: '#6A4A3A', wall: '#2A1C3A', room: [17, 15], wallH: 7,
  items: [
    { id: 'marquee_arch', pos: [0, 5.0] },
    { id: 'pledge_wheel', pos: [3.3, 6.3] },
    { id: 'baron_throne', pos: [-1.2, 6.2], rotY: 0.15 },
    { id: 'contestant_podium', pos: [-4.8, 5.4], rotY: 0.2, opts: { num: 1, score: '$130' } },
    { id: 'contestant_podium', pos: [-3.7, 5.6], rotY: 0.1, opts: { num: 2, score: '$ 75' } },
    { id: 'ghost_light', pos: [5.6, 5.2] },
    { id: 'pledge_carousel', pos: [0, 0.4] },
    { id: 'tote_board_tower', pos: [0, 0.4], rotY: 0.35 },
    { id: 'bleacher_block', pos: [-6.2, -2.8], rotY: Math.PI / 2 },
    { id: 'disco_ball', pos: [2.4, 4.6, 2.0] },
    { id: 'applause_sign', pos: [-7.8, 3.2, -2.8], rotY: Math.PI / 2 },
  ],
  cam: { pos: [4.2, 3.6, -8.6], target: [-0.2, 1.7, 2.2], fov: 56 }, hemi: 0.7, key: 1.1,
});
registerScene('sets_studio_b', {
  floor: '#E8D8B8', wall: '#C9A7FF', room: [14, 12], wallH: 6,
  items: [
    { id: 'treehouse_facade', pos: [1.2, 5.3] },
    { id: 'chroma_cyc', pos: [-4.6, 5.0] },
    { id: 'cardboard_rocket', pos: [4.6, 1.8] },
    { id: 'puppet_theater', pos: [-3.6, 1.6], rotY: 0.35 },
    { id: 'alphabet_block', pos: [-1.2, 3.1], rotY: 0.3 },
    { id: 'alphabet_block', pos: [-0.3, 3.6], rotY: -0.2, opts: { variant: 1 } },
    { id: 'alphabet_block', pos: [-0.75, 1.0, 3.35], rotY: 0.6, opts: { variant: 2 } },
    { id: 'rainbow_arch', pos: [0.8, -1.2] },
    { id: 'giant_crayons', pos: [2.9, 3.6], rotY: -0.3 },
    { id: 'toy_train_loop', pos: [-1.2, -0.6] },
    { id: 'xylophone', pos: [2.6, 0.2], rotY: -0.5 },
    { id: 'giant_crayon', pos: [-5.2, -1.2], rotY: 0.8, opts: { color: 1 } },
  ],
  cam: { pos: [1.0, 3.2, -8.8], target: [0.2, 1.6, 2.2], fov: 56 }, hemi: 0.95, key: 1.2,
});
registerScene('sets_ee', {
  floor: 'shag', floorColor: '#C8562A', wall: 'panel', room: [14, 10], wallH: 3.8,
  items: [
    { id: 'neon_logo_partition', pos: [-0.8, 1.8], opts: { state: 'broken' } },
    { id: 'trophy_case', pos: [-6.62, -0.6], rotY: -Math.PI / 2 },
    { id: 'chime_rack', pos: [-5.6, 2.2], rotY: -Math.PI / 3 },
    { id: 'letter_board', pos: [2.6, 1.2], rotY: -0.3 },
    { id: 'weather_map', pos: [4.2, 4.95] },
    { id: 'rundown_board', pos: [1.4, 4.95], opts: { filled: 2 } },
    { id: 'dressing_room_door', pos: [-3.6, 5.0], opts: { who: 'roxy' } },
    { id: 'dressing_room_door', pos: [-4.9, 5.0], opts: { who: 'baron' } },
    { id: 'perpetua_crate', pos: [5.2, -0.6], rotY: -0.6 },
    { id: 'kill_switch_cage', pos: [5.9, 2.6], rotY: -0.5 },
  ],
  cam: { pos: [0.2, 2.6, -7.6], target: [-0.2, 1.3, 2.4], fov: 60 }, hemi: 0.9, key: 1.1,
});
