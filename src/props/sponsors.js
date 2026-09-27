// DEAD AIR — props: sponsors, costumes & drops (docs/PROPKIT.md; GDD §10.3, §11, §12, §18.9, §18.11).
// Owner: the sponsors prop artist. Everything is full color (keepColor) except the set structure.
//
// category 'sponsors'
//   product_<perkId>        the 5 GIANT PRODUCTS (1.2-1.5 m, glossy): replay_ade bottle, wobble_up gelatin mold on a
//                           cake stand (parts.jelly wobbles), jump_cut coffee drum + steam bolt, roller_boogie wax tin +
//                           rainbow skate, double_vision striped toothpaste tube (parts.cap spins)
//   sponsor_set_<perkId>    the set prefab, 5 skins: 3x3 m riser (0.2 m), painted 3x2.6 m backdrop flat, neon sign,
//                           rotating pedestal (parts.turntable) with the product, two softboxes, gaffer-tape X, speaker,
//                           pedestal camera with tally (Replay-Ade: ENG camera on a tripod) + per-brand dressing.
//                           opts { lit=true (powered look), camera=true, product=true }
//   sponsor_camera_pedestal · sponsor_camera_eng · sponsor_softbox · sponsor_speaker   (set pieces, placeable alone)
// category 'sponsors_costume'  (hero slot pieces, ARCHITECTURE §12 slots; see COSTUME FIT below)
//   costume_jelly_helmet · costume_oven_mitt · costume_skates · costume_toothbrush · costume_wristbands (+ '_gold')
// category 'sponsors_drop'
//   drop_<type>             the 6 power-ups in a 0.6 m glass "screen bubble" over a glowing gold floor ring
//
// Runtime helpers exported for the game systems (src/game/sponsors.js, powerups.js):
//   setSponsorSetPower(set, on)   swaps sign / tally / softbox materials (dark set before Sign-On)
//   setTally(obj, on)             tally light of a set or a camera prop
//   animateDrop(drop, t)          bob/spin + the model's own loop (stamp, reel, clapper, needle...)
//   animateProduct(prop, t)       product idle (jelly wobble, cap spin) — the set's turntable spins separately
//
// COSTUME FIT: each costume group holds userData.parts.<slot> sub-groups, each built around its slot origin
// (reparent to hero.slots.<slot>, then reset position/rotation to 0). userData.fit documents the reference size.

import * as K from './kit.js';
import { registerProp, registerScene, PAL, THREE } from './kit.js';
import { getCard } from '../gfx/cards.js';

const TAU = Math.PI * 2;
const { clamp, lerp, smoothstep } = THREE.MathUtils;
const UP = new THREE.Vector3(0, 1, 0);
const V3 = (a) => new THREE.Vector3(a[0], a[1], a[2]);

// Sponsor colors (kept identical to gfx/cards.js SPONSORS so the 3D matches the posters and logo cards).
export const SPONSOR_IDS = ['replay_ade', 'wobble_up', 'jump_cut', 'roller_boogie', 'double_vision'];
const SP = {
  replay_ade: { name: 'Replay-Ade', sub: 'SPORTS DRINK', main: '#F4C81E', second: '#2F5BD3', deep: '#1B2F7A', neon: '#FFD23A', neon2: '#3A7BFF' },
  wobble_up: { name: 'Wobble-Up', sub: 'GELATIN', main: '#1FB45A', second: '#E23B3B', deep: '#0E4A26', neon: '#52E04A', neon2: '#FF5FA2' },
  jump_cut: { name: 'Jump Cut', sub: 'COFFEE', main: '#E3662B', second: '#5A3A22', deep: '#4A1E0E', neon: '#FF8A2A', neon2: '#FFD23A' },
  roller_boogie: { name: 'Roller Boogie', sub: 'SKATE WAX', main: '#FF5FA2', second: '#6B3A6E', deep: '#3A1440', neon: '#FF5FA2', neon2: '#5FE3FF' },
  double_vision: { name: 'Double Vision', sub: 'TOOTHPASTE', main: '#3FB8E8', second: '#E23B3B', deep: '#123A7A', neon: '#5FE3FF', neon2: '#FF4FA0' },
};
const BAR = { red: '#E4473A', yellow: '#F4E03A', green: '#52D24A', blue: '#3A58E4', cyan: '#3FD6E0', magenta: '#D64FD6' };
const INK = '#2A1D3A';

// =============================================================================================== helpers
// Full-color material (products, costumes, drops skip the pre-power desaturation).
const pm = (game, preset, color, extra = {}) => {
  const c = new THREE.Color(color);
  const pale = extra.map ? false : c.r * 0.3 + c.g * 0.55 + c.b * 0.15 > 0.72;
  return K.mat(game, preset, color, { keepColor: true, ...(pale && extra.rim === undefined ? { rim: 0.1 } : {}), ...extra });
};

// Fresh (mutable) lathe around Y with V mapped by HEIGHT (so wrap-around labels are not stretched per point).
function lathe2(profile, { seg = 32, round = 0, steps = 2, v = true } = {}) {
  const pts = round ? K.roundProfile(profile, round, steps) : profile;
  const g = new THREE.LatheGeometry(pts.map(([x, y]) => new THREE.Vector2(Math.max(0, x), y)), seg);
  if (v) vByHeight(g);
  return g;
}
function vByHeight(g, y0, y1) {
  g.computeBoundingBox();
  const lo = y0 ?? g.boundingBox.min.y, hi = y1 ?? g.boundingBox.max.y;
  const p = g.attributes.position, uv = g.attributes.uv;
  for (let i = 0; i < p.count; i++) uv.setY(i, (p.getY(i) - lo) / (hi - lo || 1));
  uv.needsUpdate = true;
  return g;
}
// Radial displacement around Y: fn(theta (0 at +z, toward +x), y, r) -> radius multiplier. In place.
function radial(g, fn) {
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const r = Math.hypot(x, z);
    if (r < 1e-6) continue;
    const k = fn(Math.atan2(x, z), y, r);
    p.setX(i, x * k); p.setZ(i, z * k);
  }
  g.computeVertexNormals();
  K.weldNormals(g);
  return g;
}
// Generic vertex deform in place: fn(v:Vector3) mutates v.
function deform(g, fn) {
  const p = g.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) { v.fromBufferAttribute(p, i); fn(v); p.setXYZ(i, v.x, v.y, v.z); }
  g.computeVertexNormals();
  return g;
}
// Planar UV projection: u from axis a over [a0,a1], v from axis b over [b0,b1] (on your own copy).
function uvPlanar(g, a, a0, a1, b, b0, b1) {
  const p = g.attributes.position, uv = g.attributes.uv;
  const ai = 'xyz'.indexOf(a), bi = 'xyz'.indexOf(b);
  const c = [0, 0, 0];
  for (let i = 0; i < p.count; i++) {
    c[0] = p.getX(i); c[1] = p.getY(i); c[2] = p.getZ(i);
    uv.setXY(i, (c[ai] - a0) / (a1 - a0), (c[bi] - b0) / (b1 - b0));
  }
  uv.needsUpdate = true;
  return g;
}
// Painted copy of a (possibly cached) geometry: per-vertex color, lets one white material serve many colors.
const paint = (geo, color) => K.tint(geo.clone(), color);
// Orients a mesh built along +y (base at 0) from a to b.
function span(mesh, a, b) {
  const A = V3(a), B = V3(b);
  mesh.position.copy(A);
  mesh.quaternion.setFromUnitVectors(UP, B.sub(A).normalize());
  return mesh;
}
function rod(r, a, b, mat, seg = 10, bevel) {
  const len = V3(a).distanceTo(V3(b));
  return span(K.m(K.cyl(r, r, len, { bevel: bevel ?? r * 0.45, seg }), mat), a, b);
}
function ring(r, n, y = 0) {
  const pts = [];
  for (let i = 0; i < n; i++) { const a = (i / n) * TAU; pts.push([Math.cos(a) * r, y, Math.sin(a) * r]); }
  return pts;
}
// Torus lying flat (ring around Y) at height y.
const flatTorus = (r, tube, rs = 8, ts = 32) => new THREE.TorusGeometry(r, tube, rs, ts).rotateX(Math.PI / 2);
// Superellipse loft: rings of [ax, az, y, n] -> closed-around surface (u = angle, v = ring index / (count-1)).
function loft(rings, seg = 48) {
  const pos = [], uv = [], idx = [];
  const cols = seg + 1;
  rings.forEach(([ax, az, y, n = 2], i) => {
    for (let j = 0; j <= seg; j++) {
      const th = (j / seg) * TAU, s = Math.sin(th), c = Math.cos(th), e = 2 / n;
      pos.push(ax * Math.sign(s) * Math.abs(s) ** e, y, az * Math.sign(c) * Math.abs(c) ** e);
      uv.push(j / seg, i / (rings.length - 1));
    }
  });
  for (let i = 0; i < rings.length - 1; i++) {
    for (let j = 0; j < seg; j++) {
      const a = i * cols + j, b = a + 1, c = a + cols, d = c + 1;
      idx.push(a, b, c, b, d, c);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  // make sure normals point outward (mid-ring vertex vs its radial direction); flip winding otherwise
  const mid = Math.floor(rings.length / 2) * cols + Math.floor(seg / 4);
  const p = g.attributes.position, nn = g.attributes.normal;
  if (p.getX(mid) * nn.getX(mid) + p.getZ(mid) * nn.getZ(mid) < 0) {
    const ia = g.index.array;
    for (let k = 0; k < ia.length; k += 3) { const t = ia[k + 1]; ia[k + 1] = ia[k + 2]; ia[k + 2] = t; }
    g.computeVertexNormals();
  }
  K.weldNormals(g);
  return g;
}
// Marks every mesh of a nested (already finished) prop so the parent's finish() leaves its bake alone.
function nested(obj) {
  obj.userData.noMerge = true;
  obj.traverse((o) => { if (o.isMesh) o.userData.noAO = true; });
  return obj;
}

// ------------------------------------------------------------------------------------------ 2D drawing
const FONT = { groovy: 'Shrikhand', sign: 'Bungee', round: 'Titan One', mono: 'VT323' };
function font(ctx, px, fam) { ctx.font = `${px}px "${fam}", "Arial Black", sans-serif`; }
function rrp(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
function starP(ctx, cx, cy, ro, ri, n = 5, rot = -Math.PI / 2) {
  ctx.beginPath();
  for (let i = 0; i < n * 2; i++) {
    const a = rot + (i / (n * 2)) * TAU, r = i % 2 ? ri : ro;
    ctx.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
  }
  ctx.closePath();
}
// Lightning bolt (pointing down), centered, s = height.
function boltP(ctx, cx, cy, s) {
  const p = [[0.12, -0.5], [-0.3, 0.06], [-0.04, 0.06], [-0.16, 0.5], [0.3, -0.08], [0.04, -0.08], [0.2, -0.5]];
  ctx.beginPath();
  p.forEach(([x, y], i) => (i ? ctx.lineTo(cx + x * s, cy + y * s) : ctx.moveTo(cx + x * s, cy + y * s)));
  ctx.closePath();
}
const BOLT_PTS = [[0.12, -0.5], [-0.3, 0.06], [-0.04, 0.06], [-0.16, 0.5], [0.3, -0.08], [0.04, -0.08], [0.2, -0.5]];
function rewindP(ctx, cx, cy, s) { // ◀◀ centered, s = height
  ctx.beginPath();
  for (const k of [0, 1]) {
    const ox = cx + s * (0.5 - k * 0.62);
    ctx.moveTo(ox, cy - s * 0.5); ctx.lineTo(ox - s * 0.62, cy); ctx.lineTo(ox, cy + s * 0.5); ctx.closePath();
  }
}
// Text with optional outline, 3D depth and drop shadow. Returns the fitted size.
function text(ctx, str, x, y, o = {}) {
  const { fam = FONT.sign, px = 40, fill = '#fff', stroke = null, lw = 0, maxW = 0, depth = 0, depthFill = INK,
    align = 'center', rot = 0, track = 0, alpha = 1 } = o;
  let size = px;
  font(ctx, size, fam);
  if (track) ctx.letterSpacing = `${track}px`;
  while (maxW && ctx.measureText(str).width > maxW && size > 6) { size *= 0.94; font(ctx, size, fam); }
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.translate(x, y); ctx.rotate(rot);
  ctx.textAlign = align; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
  for (let d = depth; d > 0; d--) {
    if (stroke) { ctx.lineWidth = lw; ctx.strokeStyle = depthFill; ctx.strokeText(str, d * 0.5, d); }
    ctx.fillStyle = depthFill; ctx.fillText(str, d * 0.5, d);
  }
  if (stroke) { ctx.lineWidth = lw; ctx.strokeStyle = stroke; ctx.strokeText(str, 0, 0); }
  ctx.fillStyle = fill; ctx.fillText(str, 0, 0);
  ctx.restore();
  ctx.letterSpacing = '0px';
  return size;
}
function lin(ctx, x0, y0, x1, y1, stops) {
  const g = ctx.createLinearGradient(x0, y0, x1, y1);
  stops.forEach((c, i) => g.addColorStop(i / (stops.length - 1), c));
  return g;
}
function rays(ctx, cx, cy, r, n, col, a0 = 0) {
  ctx.fillStyle = col;
  for (let i = 0; i < n; i++) {
    const a = a0 + (i / n) * TAU, b = a + TAU / n / 2;
    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r); ctx.lineTo(cx + Math.cos(b) * r, cy + Math.sin(b) * r); ctx.closePath(); ctx.fill();
  }
}
function sparkle(ctx, x, y, r, col = '#FFFFFF') {
  ctx.fillStyle = col;
  ctx.beginPath();
  for (let i = 0; i < 8; i++) { const a = (i / 8) * TAU - Math.PI / 2, rr = i % 2 ? r * 0.22 : r; ctx.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr); }
  ctx.closePath(); ctx.fill();
}
const texC = (key, w, h, draw, o = {}) => K.tex.canvas(`sp.${key}`, w, h, draw, { repeat: false, fonts: true, ...o });

// =============================================================================================== PRODUCTS
// All products: floor at y=0, centered, front (logo) toward -z. Glossy full-color toy plastics.

// ------------------------------------------------------------------ Replay-Ade: giant sports-drink bottle
function replayBodyTex() {
  return texC('replay.body', 1024, 512, (ctx, w, h) => {
    ctx.fillStyle = lin(ctx, 0, 0, 0, h, ['#FFE55A', '#FFD52E', '#F4B818']);
    ctx.fillRect(0, 0, w, h);
    const Y = (v) => (1 - v) * h;
    // pinstripe bands framing the waist grip
    for (const v of [0.285, 0.52]) {
      ctx.fillStyle = SP.replay_ade.second; ctx.fillRect(0, Y(v) - 7, w, 14);
      ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, Y(v) - 2, w, 4);
    }
    // bottom stripe + small rewind chevrons around the lower body
    ctx.fillStyle = SP.replay_ade.second; ctx.fillRect(0, Y(0.07), w, 10);
    for (let i = 0; i < 16; i++) { rewindP(ctx, 32 + i * 64, Y(0.17), 22); ctx.fillStyle = 'rgba(27,47,122,0.55)'; ctx.fill(); }
    // the label band
    const y0 = Y(0.845), y1 = Y(0.555);
    ctx.fillStyle = lin(ctx, 0, y0, 0, y1, ['#3F70EA', '#2F5BD3', '#1E3A9A']);
    ctx.fillRect(0, y0, w, y1 - y0);
    ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, y0 + 5, w, 5); ctx.fillRect(0, y1 - 10, w, 5);
    ctx.fillStyle = '#E3662B'; ctx.fillRect(0, y0 + 13, w, 5); ctx.fillRect(0, y1 - 18, w, 5);
    const cy = (y0 + y1) / 2;
    // soft starburst behind the wordmark
    ctx.save(); ctx.beginPath(); ctx.rect(0, y0 + 20, w, y1 - y0 - 40); ctx.clip();
    rays(ctx, 512, cy, 330, 28, 'rgba(255,255,255,0.08)');
    ctx.restore();
    text(ctx, 'Replay-Ade', 512, cy - 12, { fam: FONT.groovy, px: 84, fill: lin(ctx, 0, cy - 50, 0, cy + 30, ['#FFF6B0', '#FFD23A', '#F4B818']), stroke: '#10205A', lw: 12, depth: 6, depthFill: '#10205A', maxW: 330 });
    text(ctx, 'SPORTS DRINK', 512, cy + 42, { fam: FONT.sign, px: 22, fill: '#FFFFFF', stroke: '#10205A', lw: 5, track: 3 });
    for (const s of [-1, 1]) {
      rewindP(ctx, 512 + s * 232, cy + 4, 44);
      ctx.fillStyle = '#FFD23A'; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = '#10205A'; ctx.stroke();
      sparkle(ctx, 512 + s * 196, cy - 44, 11);
    }
    // back of the label
    text(ctx, 'GET BACK IN THE GAME!', 0, cy - 12, { fam: FONT.sign, px: 26, fill: '#FFD23A', stroke: '#10205A', lw: 5 });
    text(ctx, 'GET BACK IN THE GAME!', w, cy - 12, { fam: FONT.sign, px: 26, fill: '#FFD23A', stroke: '#10205A', lw: 5 });
    text(ctx, 'INSTANT REPLAY FORMULA', 0, cy + 24, { fam: FONT.round, px: 18, fill: '#FFFFFF' });
    text(ctx, 'INSTANT REPLAY FORMULA', w, cy + 24, { fam: FONT.round, px: 18, fill: '#FFFFFF' });
  });
}

registerProp('product_replay_ade', (game) => {
  const g = K.prop('product_replay_ade');
  const body = pm(game, 'plastic', '#ffffff', { map: replayBodyTex(), rough: 0.26 });
  const blue = pm(game, 'plastic', '#2F5BD3', { rough: 0.3 });
  const yellow = pm(game, 'plastic', '#FFD23A', { rough: 0.28 });
  const H = 1.2;
  const bg = lathe2([[0, 0], [0.26, 0], [0.305, 0.03], [0.312, 0.09], [0.312, 0.33], [0.29, 0.39], [0.262, 0.47], [0.29, 0.56],
    [0.312, 0.62], [0.312, 1.0], [0.296, 1.06], [0.235, 1.12], [0.15, 1.162], [0.13, 1.18], [0.13, H], [0, H]], { seg: 36, round: 0.03, steps: 1 });
  radial(bg, (th, y) => {
    const w = smoothstep(y, 0.35, 0.41) * (1 - smoothstep(y, 0.53, 0.6));
    return 1 - w * 0.04 * (0.5 + 0.5 * Math.cos(th * 10));
  });
  g.add(K.m(bg, body));
  // neck ring + ribbed cap
  g.add(K.m(flatTorus(0.137, 0.014, 8, 32), blue, { pos: [0, 1.185, 0] }));
  const cap = lathe2([[0, 0], [0.158, 0], [0.166, 0.02], [0.166, 0.11], [0.15, 0.13], [0.1, 0.136], [0, 0.136]], { seg: 40, round: 0.012, steps: 1 });
  radial(cap, (th, y) => 1 + 0.035 * Math.max(0, Math.cos(th * 20)) * smoothstep(y, 0.02, 0.04) * (1 - smoothstep(y, 0.1, 0.12)));
  g.add(K.m(cap, blue, { pos: [0, H - 0.005, 0] }));
  g.add(K.m(flatTorus(0.15, 0.012, 6, 32), yellow, { pos: [0, H + 0.128, 0] }));
  // the rewind-arrow fin on the cap: chunky yellow ◀◀ on a blue plinth (points to the viewer's left = shape +x)
  const tri = (ox) => [[ox, 0.085], [ox + 0.13, 0], [ox, -0.085]];
  for (const ox of [-0.125, 0.0]) g.add(K.m(K.extrude(tri(ox), 0.1, { bevel: 0.028, round: 0.03, curveSeg: 4, bevelSeg: 2 }), yellow, { pos: [0, H + 0.235, 0] }));
  g.add(K.m(K.cyl(0.075, 0.1, 0.07, { bevel: 0.018, seg: 20 }), blue, { pos: [0, H + 0.125, 0] }));
  // cold condensation droplets on the upper body
  const drop = pm(game, 'plastic', '#FFF6C8', { transparent: true, opacity: 0.55, rough: 0.05, env: 0.25, rim: 0.5, rimColor: '#FFFFFF' });
  const drng = [0.31, 0.72, 1.05, 0.18, 0.88, 0.5, 0.64, 0.95, 0.25, 0.77, 0.4, 0.58];
  for (let i = 0; i < 12; i++) {
    const a = Math.PI + (i - 5.5) * 0.23 + drng[i] * 0.1, y = 0.66 + drng[(i + 5) % 12] * 0.34, r = 0.3155;
    const d = K.m(new THREE.SphereGeometry(0.014 + drng[i] * 0.01, 8, 6), drop, { pos: [Math.sin(a) * r, y, Math.cos(a) * r], scale: [1, 1.35, 0.5], rot: [0, a, 0], cast: false });
    d.userData.noAO = true;
    g.add(d);
  }
  g.userData.colliders = [{ min: [-0.32, 0, -0.32], max: [0.32, 1.5, 0.32] }];
  return K.finish(game, g, { ao: { strength: 0.7 } });
}, { category: 'sponsors', tags: ['product', 'replay_ade'], size: [0.63, 1.5, 0.63], desc: 'Replay-Ade giant sports-drink bottle, rewind-arrow cap', hero: true });

// ------------------------------------------------------------------ Wobble-Up: emerald ring mold on a cake stand
function doilyTex() {
  return texC('doily', 512, 512, (ctx, w, h) => {
    const cx = w / 2, cy = h / 2;
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    for (let i = 0; i <= 480; i++) { const a = (i / 480) * TAU, r = 238 + 12 * Math.cos(a * 30); ctx.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r); }
    ctx.fill();
    ctx.globalCompositeOperation = 'destination-out';
    for (let k = 0; k < 4; k++) {
      const rr = 96 + k * 36, n = 14 + k * 6;
      for (let i = 0; i < n; i++) {
        const a = ((i + (k % 2) * 0.5) / n) * TAU;
        ctx.beginPath(); ctx.ellipse(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr, 10 + k * 1.5, 5 + k, a, 0, TAU); ctx.fill();
      }
    }
    for (let i = 0; i < 30; i++) { const a = (i / 30) * TAU; ctx.beginPath(); ctx.arc(cx + Math.cos(a) * 232, cy + Math.sin(a) * 232, 4.5, 0, TAU); ctx.fill(); }
    ctx.globalCompositeOperation = 'source-over';
    ctx.strokeStyle = 'rgba(190,178,160,0.7)'; ctx.lineWidth = 2.5;
    for (const r of [72, 160, 222]) { ctx.beginPath(); ctx.arc(cx, cy, r, 0, TAU); ctx.stroke(); }
  });
}

function flagTex(id, w = 256, h = 128) {
  const S = SP[id];
  return texC(`flag.${id}`, w, h, (ctx) => {
    ctx.fillStyle = S.main; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 8, w, 6); ctx.fillRect(0, h - 14, w, 6);
    text(ctx, S.name, w / 2, h / 2 - 2, { fam: FONT.groovy, px: 52, fill: '#FFFFFF', stroke: S.deep, lw: 8, depth: 3, depthFill: S.deep, maxW: w * 0.86 });
  });
}

registerProp('product_wobble_up', (game) => {
  const g = K.prop('product_wobble_up');
  const glass = pm(game, 'ceramic', '#EAE3D4', { rough: 0.3, rim: 0.12 });       // milk-glass cake stand
  const jellyM = pm(game, 'plastic', '#067A30', { transparent: true, opacity: 0.92, rough: 0.1, env: 0.2,
    emissive: '#046A28', emissiveIntensity: 0.6, rim: 0.3, rimColor: '#6CFFA0', rimPower: 2.6 });
  const fruitM = pm(game, 'lacquer', '#ffffff', { rough: 0.3 });                   // painted per vertex
  const creamM = pm(game, 'ceramic', '#FFF6E6', { rough: 0.55, rim: 0.35 });
  const doily = pm(game, 'paint', '#EDE7DA', { map: doilyTex(), alphaTest: 0.5, side: THREE.DoubleSide, rim: 0.04 });
  const pick = pm(game, 'teak', '#E8C890');
  const flag = pm(game, 'paint', '#ffffff', { map: flagTex('wobble_up') });

  // cake stand: scalloped plate, stem with a knop, domed foot
  const st = lathe2([[0, 0], [0.3, 0], [0.316, 0.02], [0.29, 0.056], [0.13, 0.12], [0.075, 0.2], [0.075, 0.28], [0.11, 0.33],
    [0.55, 0.375], [0.62, 0.395], [0.615, 0.42], [0, 0.42]], { seg: 48, round: 0.02, steps: 1 });
  radial(st, (th, y, r) => 1 + 0.035 * Math.cos(th * 16) * smoothstep(r, 0.5, 0.6));
  g.add(K.m(st, glass));
  g.add(K.m(flatTorus(0.085, 0.024, 8, 24), glass, { pos: [0, 0.235, 0] }));
  const top = 0.42;
  g.add(K.m(new THREE.CircleGeometry(0.585, 48).rotateX(-Math.PI / 2), doily, { pos: [0, top + 0.003, 0] }));

  // the tiered, fluted ring mold (pivot at its base: parts.jelly squashes/shears for the wobble)
  const jelly = new THREE.Group();
  jelly.position.y = top + 0.005;
  jelly.userData.noMerge = true;
  const s = 1.15;
  const jg = lathe2([[0.16, 0], [0.47, 0], [0.485, 0.035], [0.465, 0.2], [0.425, 0.235], [0.402, 0.27], [0.372, 0.42], [0.315, 0.5],
    [0.24, 0.545], [0.19, 0.55], [0.155, 0.525], [0.142, 0.46], [0.15, 0.02], [0.16, 0]].map(([r, y]) => [r * s, y * s]),
  { seg: 60, round: 0.02, steps: 1, v: false });
  radial(jg, (th, y, r) => {
    const t = smoothstep(y, 0.22 * s, 0.28 * s);
    return 1 + 0.05 * (1 - 0.25 * t) * Math.cos(th * 12 + Math.PI * t) * smoothstep(r, 0.22 * s, 0.32 * s);
  });
  jelly.add(K.m(jg, jellyM, { name: 'jelly' }));
  // suspended fruit, close to the surface so it reads through the gelatin
  const sph = (r) => new THREE.SphereGeometry(r, 10, 8);
  const FR = [
    () => paint(sph(0.052), '#D81E3A'),                                   // maraschino cherry
    () => paint(K.box(0.085, 0.06, 0.075, 0.02), '#FFD84A'),              // pineapple chunk
    () => paint(new THREE.TorusGeometry(0.045, 0.026, 6, 10, Math.PI), '#FF9226'), // mandarin segment
    () => paint(sph(0.042), '#8A3C9A'),                                   // grape
  ];
  const put = (n, y, rr, a0) => {
    for (let i = 0; i < n; i++) {
      const a = a0 + (i / n) * TAU;
      const m = K.m(FR[(i + n) % FR.length](), fruitM, { pos: [Math.sin(a) * rr, y, Math.cos(a) * rr], rot: [i * 0.7, a, i * 1.3] });
      jelly.add(m);
    }
  };
  put(8, 0.11 * s, 0.37 * s, 0.2);
  put(6, 0.35 * s, 0.29 * s, 0.6);
  // whipped-cream rosette in the hole + cherry on top + toothpick flag
  const cg = lathe2([[0, 0], [0.215, 0], [0.2, 0.045], [0.15, 0.09], [0.1, 0.13], [0.05, 0.165], [0.012, 0.19], [0, 0.192]], { seg: 48, v: false });
  radial(cg, (th, y) => 1 + 0.13 * Math.cos(th * 8 + y * 26));
  const creamY = 0.55 * s - 0.07;
  jelly.add(K.m(cg, creamM, { pos: [0, creamY, 0] }));
  jelly.add(K.m(paint(new THREE.SphereGeometry(0.065, 16, 12), '#E0183A'), fruitM, { pos: [0.01, creamY + 0.235, 0] }));
  jelly.add(K.m(paint(K.tube([[0.01, creamY + 0.28, 0], [0.03, creamY + 0.34, 0.01], [0.075, creamY + 0.38, 0.02]], 0.007, { seg: 8, radial: 5 }), '#6B8A2A'), fruitM));
  jelly.add(rod(0.006, [-0.06, creamY + 0.08, 0.02], [-0.16, creamY + 0.46, 0.05], pick, 6));
  for (const back of [0, 1]) {
    const fg = new THREE.PlaneGeometry(0.22, 0.11);
    if (!back) fg.rotateY(Math.PI); else fg.translate(0, 0, 0.001);
    const fl = K.m(fg, flag, { pos: [-0.28, creamY + 0.39, 0.05], rot: [0, 0.35, -0.26] });
    fl.userData.noAO = true;
    jelly.add(fl);
  }
  g.add(jelly);
  g.userData.parts = { jelly };
  g.userData.colliders = [{ min: [-0.6, 0, -0.6], max: [0.6, 1.3, 0.6] }];
  return K.finish(game, g, { ao: { strength: 0.7 } });
}, { category: 'sponsors', tags: ['product', 'wobble_up'], size: [1.24, 1.35, 1.24], desc: 'Wobble-Up emerald ring gelatin mold with fruit on a milk-glass cake stand (parts.jelly wobbles)', hero: true });

// ------------------------------------------------------------------ Jump Cut: drum-sized coffee can + steam bolt
function filmStrip(ctx, y, w, hh, col, hole) {
  ctx.fillStyle = col; ctx.fillRect(0, y, w, hh);
  ctx.fillStyle = hole;
  const n = 32, step = w / n;
  for (let i = 0; i < n; i++) { rrp(ctx, i * step + step * 0.22, y + hh * 0.25, step * 0.56, hh * 0.5, 4); ctx.fill(); }
}
function jumpBodyTex() {
  const S = SP.jump_cut;
  return texC('jump.body', 1024, 416, (ctx, w, h) => {
    ctx.fillStyle = lin(ctx, 0, 0, 0, h, ['#F27A36', '#E3662B', '#C9531F']);
    ctx.fillRect(0, 0, w, h);
    ctx.save(); ctx.beginPath(); ctx.rect(0, 60, w, h - 120); ctx.clip();
    rays(ctx, 512, 150, 700, 36, 'rgba(255,214,120,0.16)');
    ctx.restore();
    filmStrip(ctx, 16, w, 40, S.second, '#F6E7C8');
    filmStrip(ctx, h - 56, w, 40, S.second, '#F6E7C8');
    ctx.fillStyle = '#F6E7C8'; ctx.fillRect(0, 60, w, 4); ctx.fillRect(0, h - 64, w, 4);
    // emblem: cream roundel with the bolt
    ctx.beginPath(); ctx.arc(512, 142, 58, 0, TAU); ctx.fillStyle = '#F6E7C8'; ctx.fill();
    ctx.lineWidth = 8; ctx.strokeStyle = S.second; ctx.stroke();
    boltP(ctx, 512, 142, 88); ctx.fillStyle = '#FFD23A'; ctx.fill(); ctx.lineWidth = 6; ctx.strokeStyle = S.deep; ctx.lineJoin = 'round'; ctx.stroke();
    text(ctx, 'Jump Cut', 512, 240, { fam: FONT.groovy, px: 92, fill: lin(ctx, 0, 200, 0, 280, ['#FFFFFF', '#FFF0D0', '#F6D9A8']), stroke: S.deep, lw: 12, depth: 6, depthFill: S.deep, maxW: 310 });
    // "COFFEE" ribbon
    rrp(ctx, 400, 288, 224, 44, 8); ctx.fillStyle = S.second; ctx.fill();
    text(ctx, 'COFFEE', 512, 311, { fam: FONT.sign, px: 32, fill: '#FFD23A', track: 6 });
    // side panels: little steaming cup + copy
    for (const x of [230, 794]) {
      ctx.save(); ctx.translate(x, 190);
      rrp(ctx, -34, -10, 68, 58, 12); ctx.fillStyle = '#F6E7C8'; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = S.deep; ctx.stroke();
      ctx.beginPath(); ctx.arc(38, 16, 14, -1.3, 1.3); ctx.lineWidth = 7; ctx.stroke();
      ctx.fillStyle = S.second; ctx.fillRect(-28, -4, 56, 10);
      ctx.strokeStyle = 'rgba(255,255,255,0.8)'; ctx.lineWidth = 5; ctx.lineCap = 'round';
      for (const k of [-14, 0, 14]) { ctx.beginPath(); ctx.moveTo(k, -18); ctx.bezierCurveTo(k - 8, -30, k + 8, -40, k, -56); ctx.stroke(); }
      ctx.restore();
      text(ctx, x < 512 ? 'VACUUM PACKED' : 'FRESH-CUT ROAST', x, 272, { fam: FONT.sign, px: 22, fill: '#F6E7C8', stroke: S.deep, lw: 4 });
      text(ctx, x < 512 ? 'REGULAR GRIND' : 'NET WT. 200 LBS', x, 302, { fam: FONT.round, px: 18, fill: S.deep });
    }
    text(ctx, 'SKIP THE WAITING!', 0, 200, { fam: FONT.sign, px: 26, fill: '#FFD23A', stroke: S.deep, lw: 5 });
    text(ctx, 'SKIP THE WAITING!', w, 200, { fam: FONT.sign, px: 26, fill: '#FFD23A', stroke: S.deep, lw: 5 });
    // splice marks (the brand's jump-cut gag)
    ctx.strokeStyle = 'rgba(255,255,255,0.55)'; ctx.lineWidth = 3; ctx.setLineDash([10, 8]);
    for (const x of [360, 664]) { ctx.beginPath(); ctx.moveTo(x, 70); ctx.lineTo(x - 18, h - 70); ctx.stroke(); }
    ctx.setLineDash([]);
  });
}
function groundsTex() {
  return K.tex.canvas('sp.grounds', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#3A2014'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 2600; i++) { ctx.fillStyle = rand() < 0.5 ? '#24120A' : '#5A3420'; ctx.globalAlpha = 0.6; ctx.fillRect(rand() * w, rand() * h, 2, 2); }
    ctx.globalAlpha = 1;
  });
}

registerProp('product_jump_cut', (game) => {
  const g = K.prop('product_jump_cut');
  const body = pm(game, 'lacquer', '#ffffff', { map: jumpBodyTex(), rough: 0.3 });
  const tin = pm(game, 'metal', '#C9CED6', { rough: 0.3 });
  const lidM = pm(game, 'plastic', '#8A5230', { rough: 0.38, env: 0.03 });
  const grounds = pm(game, 'soil', '#ffffff', { map: groundsTex() });
  const steam = pm(game, 'fabric', '#E6DCCD', { emissive: '#FFD9A0', emissiveIntensity: 0.05, rim: 0.35, rimColor: '#FFF4E0' });
  const R = 0.42, H = 1.04;
  const bead = (y) => [[R, y - 0.015], [R - 0.013, y], [R, y + 0.015]];
  const can = lathe2([[R, 0.03], ...bead(0.085), ...bead(0.14), [R, 0.2], [R, H - 0.2], ...bead(H - 0.14), ...bead(H - 0.085), [R, H - 0.03]], { seg: 48 });
  g.add(K.m(can, body));
  const inner = lathe2([[R - 0.01, H - 0.02], [R - 0.01, H - 0.12]], { seg: 48, v: false });
  g.add(K.m(inner, tin));
  g.add(K.m(new THREE.CircleGeometry(R - 0.008, 40).rotateX(-Math.PI / 2), grounds, { pos: [0, H - 0.1, 0] }));
  g.add(K.m(new THREE.CircleGeometry(R, 40).rotateX(Math.PI / 2), tin, { pos: [0, 0.03, 0] }));
  g.add(K.m(flatTorus(R, 0.024, 8, 48), tin, { pos: [0, 0.03, 0] }));
  g.add(K.m(flatTorus(R, 0.022, 8, 48), tin, { pos: [0, H - 0.02, 0] }));
  // snap-on lid popped open at the front (hinged on its back edge)
  const lid = lathe2([[0, 0], [0.4, 0], [0.43, -0.02], [0.448, -0.012], [0.452, 0.06], [0.436, 0.082], [0.37, 0.09], [0, 0.094]], { seg: 48, round: 0.01, steps: 1, v: false });
  const hinge = new THREE.Group();
  hinge.position.set(0, H + 0.004, R);
  hinge.rotation.x = 0.26;
  hinge.add(K.m(lid, lidM, { pos: [0, 0, -R] }));
  hinge.add(K.m(flatTorus(0.34, 0.012, 6, 40), lidM, { pos: [0, 0.09, -R] }));
  g.add(hinge);
  // steam puffs escaping the gap + the steam lightning bolt
  const puff = (x, y, z, r, sx = 1, sy = 0.8) => g.add(K.m(new THREE.SphereGeometry(r, 14, 10), steam, { pos: [x, y, z], scale: [sx, sy, sx] }));
  puff(-0.02, H + 0.08, -0.3, 0.11, 1.2, 0.75);
  puff(0.13, H + 0.07, -0.26, 0.085);
  puff(-0.15, H + 0.06, -0.24, 0.08);
  puff(0.05, H + 0.16, -0.3, 0.075);
  const boltShape = BOLT_PTS.map(([x, y]) => [x * 0.66, -y * 0.62]);
  g.add(K.m(K.extrude(boltShape, 0.17, { bevel: 0.055, round: 0.04, curveSeg: 6, bevelSeg: 3 }), steam, { pos: [0.02, H + 0.43, -0.3], rot: [0.12, 0, -0.12] }));
  // a wind-key soldered on the side (opens the old vacuum strip)
  g.add(K.m(new THREE.TorusGeometry(0.045, 0.011, 6, 16), tin, { pos: [R + 0.075, H - 0.24, 0.1], rot: [0, Math.PI / 2, 0] }));
  g.add(rod(0.009, [R + 0.005, H - 0.24, 0.1], [R + 0.03, H - 0.24, 0.1], tin, 8));
  g.add(K.m(new THREE.CylinderGeometry(0.01, 0.01, 0.32, 8).rotateX(Math.PI / 2), tin, { pos: [R + 0.012, H - 0.24, -0.06] }));
  g.userData.colliders = [{ min: [-0.45, 0, -0.45], max: [0.45, 1.5, 0.45] }];
  return K.finish(game, g, { ao: { strength: 0.7 } });
}, { category: 'sponsors', tags: ['product', 'jump_cut'], size: [0.9, 1.55, 0.9], desc: 'Jump Cut Coffee drum-sized orange can, lid popped, steam lightning bolt', hero: true });

// ------------------------------------------------------------------ Roller Boogie: wax tin + rainbow roller skate
function tinSideTex() {
  const S = SP.roller_boogie;
  return texC('roller.side', 1024, 128, (ctx, w, h) => {
    ctx.fillStyle = S.second; ctx.fillRect(0, 0, w, h);
    const cols = [BAR.red, '#FF9A2A', BAR.yellow, BAR.green, BAR.blue];
    cols.forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(0, 22 + i * 9, w, 9); });
    for (let i = 0; i < 4; i++) {
      text(ctx, 'ROLLER BOOGIE', 128 + i * 256, 96, { fam: FONT.sign, px: 24, fill: '#FFFFFF', stroke: S.deep, lw: 4 });
      sparkle(ctx, 256 + i * 256, 96, 10, '#5FE3FF');
    }
  });
}
function tinLidTex() {
  const S = SP.roller_boogie;
  return texC('roller.lid', 512, 512, (ctx, w, h) => {
    const cx = w / 2, cy = h / 2;
    ctx.fillStyle = S.main; ctx.fillRect(0, 0, w, h);
    ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, 250, 0, TAU); ctx.clip();
    rays(ctx, cx, cy, 300, 24, 'rgba(255,255,255,0.14)');
    ctx.restore();
    const cols = [BAR.blue, BAR.green, BAR.yellow, '#FF9A2A', BAR.red];
    cols.forEach((c, i) => { ctx.beginPath(); ctx.arc(cx, cy, 250 - i * 9, 0, TAU); ctx.lineWidth = 9; ctx.strokeStyle = c; ctx.stroke(); });
    ctx.beginPath(); ctx.arc(cx, cy, 204, 0, TAU); ctx.fillStyle = S.second; ctx.fill();
    // arched lettering around the rim
    const arc = (str, r, a0, px, col, flip) => {
      font(ctx, px, FONT.sign);
      ctx.fillStyle = col; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      const chars = [...str], sp = (chars.length * px * 0.62) / r;
      chars.forEach((ch, i) => {
        const a = flip ? a0 + sp / 2 - (i + 0.5) * (sp / chars.length) : a0 - sp / 2 + (i + 0.5) * (sp / chars.length);
        ctx.save(); ctx.translate(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
        ctx.rotate(flip ? a - Math.PI / 2 : a + Math.PI / 2);
        ctx.lineWidth = 6; ctx.strokeStyle = S.deep; ctx.strokeText(ch, 0, 0); ctx.fillText(ch, 0, 0);
        ctx.restore();
      });
    };
    arc('ROLLER BOOGIE', 172, -Math.PI / 2, 40, '#FFFFFF', false);
    arc("NEVER STOP ROLLIN'", 176, Math.PI / 2, 26, '#5FE3FF', true);
    text(ctx, 'SKATE WAX', cx, cy, { fam: FONT.groovy, px: 58, fill: '#FFD23A', stroke: S.deep, lw: 9, depth: 4, depthFill: S.deep, maxW: 300 });
    for (const [x, y, r] of [[150, 200, 14], [360, 190, 11], [170, 330, 10], [350, 320, 14]]) sparkle(ctx, x, y, r, '#FFFFFF');
  });
}
function bootTex() {
  return texC('roller.boot', 512, 512, (ctx, w, h) => {
    ctx.fillStyle = '#EFE7D8'; ctx.fillRect(0, 0, w, h);
    const cols = [BAR.red, '#FF9A2A', BAR.yellow, BAR.green, BAR.blue, '#8A4ADC'];
    // rainbow swoosh sweeping from the toe (u low, bottom) up to the heel collar (u high, top)
    ctx.lineCap = 'butt';
    cols.forEach((c, i) => {
      const o = i * 15;
      ctx.beginPath(); ctx.moveTo(20, 450 - o); ctx.bezierCurveTo(250, 450 - o, 360 - o * 0.6, 420 - o, 400 - o * 0.9, 60);
      ctx.lineWidth = 16; ctx.strokeStyle = c; ctx.stroke();
    });
    ctx.strokeStyle = 'rgba(90,60,40,0.45)'; ctx.lineWidth = 2; ctx.setLineDash([6, 5]);
    ctx.beginPath(); ctx.moveTo(20, 470); ctx.bezierCurveTo(250, 470, 372, 440, 412, 60); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(20, 364); ctx.bezierCurveTo(250, 364, 300, 330, 316, 60); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(0, 470); ctx.lineTo(w, 470); ctx.stroke();
    ctx.setLineDash([]);
  });
}

function rollerSkate(game, mats, o = {}) {
  // local: wheels touch y=0, toe toward -z. mats: { boot, plastic (vertex painted), chrome }
  const g = new THREE.Group();
  const { boot, plastic, chrome } = mats;
  const wheelCols = o.wheelCols || [BAR.red, BAR.yellow, BAR.green, BAR.blue];
  const WR = 0.08;
  const wheel = K.lathe([[0.028, -0.036], [0.066, -0.036], [0.08, -0.022], [0.08, 0.022], [0.066, 0.036], [0.028, 0.036]], { seg: 16, round: 0.01, steps: 1 });
  let wi = 0;
  for (const z of [-0.22, 0.22]) {
    for (const x of [-0.125, 0.125]) {
      g.add(K.m(paint(wheel, wheelCols[wi++ % 4]), plastic, { pos: [x, WR, z], rot: [0, 0, Math.PI / 2] }));
      g.add(K.m(new THREE.CylinderGeometry(0.03, 0.03, 0.078, 10).rotateZ(Math.PI / 2), chrome, { pos: [x, WR, z] }));
    }
    g.add(K.m(new THREE.CylinderGeometry(0.011, 0.011, 0.34, 8).rotateZ(Math.PI / 2), chrome, { pos: [0, WR, z] }));
    g.add(K.m(K.box(0.1, 0.06, 0.07, 0.012), chrome, { pos: [0, WR + 0.035, z] }));
    g.add(K.m(paint(new THREE.CylinderGeometry(0.03, 0.03, 0.03, 10), '#F4E03A'), plastic, { pos: [0, WR + 0.07, z + (z < 0 ? 0.035 : -0.035)] }));
  }
  g.add(K.m(K.box(0.17, 0.024, 0.66, 0.01), chrome, { pos: [0, 0.143, 0] }));
  // sole + heel block (brown), boot on top
  g.add(K.m(paint(K.box(0.3, 0.05, 0.74, 0.02), '#7A4A2A'), plastic, { pos: [0, 0.18, -0.01] }));
  g.add(K.m(paint(K.box(0.27, 0.07, 0.22, 0.02), '#6B3E22'), plastic, { pos: [0, 0.235, 0.24] }));
  // the boot: ONE sculpted shell (a subdivided cushion re-mapped to an L profile: low toe box, instep ramp, tall
  // shaft leaning back), so it reads as a single stitched leather boot
  const SOLE = 0.205;
  const topH = (z) => 0.13 + 0.07 * smoothstep(z, -0.37, -0.27) + 0.06 * smoothstep(z, -0.28, -0.12) + 0.37 * smoothstep(z, -0.16, 0.1);
  const bootG = K.cushion(0.29, 1, 0.74, { puff: 0.025, r: 0.1, seg: [6, 12, 13] }).clone();
  deform(bootG, (v) => {
    const h = topH(v.z);
    v.y = SOLE + (v.y + 0.5) * h;
    const toe = smoothstep(-v.z, 0.1, 0.37);
    v.x *= (1 - 0.18 * toe) * (1 - 0.1 * smoothstep(v.y, 0.5, 0.85));
    if (v.z < -0.26) v.z = -0.26 - (-0.26 - v.z) * Math.sqrt(Math.max(0, 1 - (v.x / 0.13) ** 2));
    v.z += Math.max(0, v.y - 0.45) * 0.14;
  });
  K.weldNormals(bootG);
  g.add(K.m(uvPlanar(bootG, 'z', -0.42, 0.42, 'y', 0.15, 0.95), boot));
  const ramp = (z, lift = 0) => [SOLE + topH(z) + lift, z + Math.max(0, SOLE + topH(z) - 0.45) * 0.14];
  // padded collar
  const collar = new THREE.TorusGeometry(0.15, 0.04, 8, 24).rotateX(Math.PI / 2);
  collar.scale(0.98, 1, 0.95);
  g.add(K.m(paint(collar, '#FF5FA2'), plastic, { pos: [0, SOLE + 0.63, 0.27], rot: [0.14, 0, 0] }));
  // tongue lying on the instep ramp, poking out above the collar
  const tongue = K.cushion(0.15, 0.3, 0.04, { puff: 0.012 }).clone();
  deform(tongue, (v) => { v.z += 0.35 * (v.y + 0.15) ** 2; });
  g.add(K.m(paint(tongue, '#FF8CBE'), plastic, { pos: [0, 0.7, -0.005], rot: [0.5, 0, 0] }));
  // criss-cross laces over the tongue + a bow at the top
  const zs = [-0.15, -0.1, -0.05, 0.0, 0.045];
  for (let i = 0; i < zs.length - 1; i++) {
    const [y0, z0] = ramp(zs[i], 0.035), [y1, z1] = ramp(zs[i + 1], 0.035), [ym, zm] = ramp((zs[i] + zs[i + 1]) / 2, 0.06);
    for (const sx of [-1, 1]) g.add(K.m(paint(K.tube([[sx * 0.1, y0, z0], [0, ym, zm - 0.012], [-sx * 0.1, y1, z1]], 0.0095, { seg: 8, radial: 4 }), '#FF5FA2'), plastic));
  }
  const [by, bz] = ramp(0.06, 0.07);
  for (const sx of [-1, 1]) g.add(K.m(paint(new THREE.TorusGeometry(0.036, 0.012, 6, 14), '#FF5FA2'), plastic, { pos: [sx * 0.035, by + 0.01, bz - 0.03], rot: [-0.9, sx * 0.5, sx * 0.4], scale: [1.25, 0.8, 1] }));
  g.add(K.m(paint(new THREE.SphereGeometry(0.018, 8, 6), '#FF5FA2'), plastic, { pos: [0, by, bz - 0.035] }));
  // pink toe stop on a chrome stem
  g.add(rod(0.014, [0, 0.14, -0.3], [0, 0.1, -0.37], chrome, 8));
  const stop = K.lathe([[0, 0], [0.05, 0], [0.056, 0.012], [0.056, 0.06], [0.046, 0.072], [0, 0.072]], { seg: 16, round: 0.01 });
  g.add(span(K.m(paint(stop, '#FF4F9A'), plastic), [0, 0.115, -0.35], [0, 0.03, -0.43]));
  return g;
}

registerProp('product_roller_boogie', (game) => {
  const g = K.prop('product_roller_boogie');
  const plastic = pm(game, 'lacquer', '#ffffff', { rough: 0.3 });
  const chrome = pm(game, 'chrome', '#98A0AC');
  const side = pm(game, 'lacquer', '#ffffff', { map: tinSideTex(), rough: 0.3 });
  const lidTop = pm(game, 'lacquer', '#ffffff', { map: tinLidTex(), rough: 0.45, rim: 0.05, env: 0.02 });
  const boot = pm(game, 'vinyl', '#ffffff', { map: bootTex(), rough: 0.32 });
  const R = 0.5;
  g.add(K.m(lathe2([[0, 0], [R - 0.012, 0], [R, 0.014], [R, 0.25], [R - 0.01, 0.258], [0, 0.258]], { seg: 40, round: 0.006, steps: 1 }), side));
  g.add(K.m(paint(flatTorus(R - 0.004, 0.012, 5, 40), SP.roller_boogie.main), plastic, { pos: [0, 0.012, 0] }));
  const lid = lathe2([[R - 0.004, 0.232], [R + 0.013, 0.24], [R + 0.016, 0.25], [R + 0.016, 0.33], [R + 0.008, 0.346], [R - 0.012, 0.352], [0, 0.353]], { seg: 40, round: 0.006, steps: 1, v: false });
  g.add(K.m(paint(lid, SP.roller_boogie.main), plastic));
  g.add(K.m(new THREE.CircleGeometry(R - 0.03, 48).rotateX(-Math.PI / 2).rotateY(Math.PI), lidTop, { pos: [0, 0.354, 0] }));
  // the butterfly twist-opener on the side of the tin
  const op = new THREE.Group();
  op.position.set(R + 0.02, 0.2, -0.02);
  op.add(K.m(K.cyl(0.028, 0.028, 0.03, { bevel: 0.008, seg: 12 }), chrome, { rot: [0, 0, -Math.PI / 2] }));
  op.add(K.m(K.extrude([[-0.075, 0.02], [0.075, 0.02], [0.075, -0.02], [-0.075, -0.02]], 0.014, { bevel: 0.005, round: 0.018 }), chrome, { pos: [0.035, 0, 0], rot: [0, Math.PI / 2, 0.5] }));
  g.add(op);
  const sk = rollerSkate(game, { boot, plastic, chrome });
  sk.scale.setScalar(1.12);
  sk.position.set(0, 0.354, 0.02);
  sk.rotation.y = -0.45;
  g.add(sk);
  g.userData.colliders = [{ min: [-0.52, 0, -0.52], max: [0.52, 1.3, 0.52] }];
  return K.finish(game, g, { ao: { strength: 0.7 } });
}, { category: 'sponsors', tags: ['product', 'roller_boogie'], size: [1.04, 1.3, 1.04], desc: 'Roller Boogie Wax tin with a rainbow roller skate on the lid', hero: true });

// ------------------------------------------------------------------ Double Vision: striped toothpaste tube
function tubeTex() {
  const S = SP.double_vision;
  return texC('dv.tube', 1024, 512, (ctx, w, h) => {
    const cols = ['#E23B3B', '#F7F3EA', '#2F5BD3'];
    const P = 128, bw = P / 3, sk = 0.62 * h;
    for (let k = -8; k < 14; k++) cols.forEach((c, b) => {
      const x = k * P + b * bw;
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x + bw + 0.8, 0); ctx.lineTo(x + bw + 0.8 - sk, h); ctx.lineTo(x - sk, h); ctx.closePath();
      ctx.fillStyle = c; ctx.fill();
    });
    // white shoulder band and crimp band with ridges + printer registration squares
    ctx.fillStyle = '#F7F3EA'; ctx.fillRect(0, 0, w, 22);
    ctx.fillStyle = S.deep; ctx.fillRect(0, 20, w, 6);
    const cy0 = h * 0.86;
    ctx.fillStyle = '#F7F3EA'; ctx.fillRect(0, cy0, w, h - cy0);
    ctx.fillStyle = S.deep; ctx.fillRect(0, cy0 - 6, w, 6);
    ctx.strokeStyle = 'rgba(40,40,60,0.28)'; ctx.lineWidth = 2;
    for (let x = 0; x < w; x += 7) { ctx.beginPath(); ctx.moveTo(x, cy0 + 22); ctx.lineTo(x, h); ctx.stroke(); }
    [BAR.cyan, BAR.magenta, BAR.yellow, INK].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(452 + i * 30, cy0 + 8, 20, 12); });
    // front label panel (u = 0.5 faces -z)
    const px = 512, py0 = 60, py1 = 380;
    rrp(ctx, px - 138, py0, 276, py1 - py0, 26); ctx.fillStyle = S.deep; ctx.fill();
    rrp(ctx, px - 130, py0 + 8, 260, py1 - py0 - 16, 20); ctx.fillStyle = '#FFFDF6'; ctx.fill();
    ctx.save(); ctx.clip();
    rays(ctx, px, 170, 260, 20, 'rgba(63,184,232,0.14)');
    ctx.restore();
    // smiling tooth mascot with a star glint
    ctx.save(); ctx.translate(px, 128);
    ctx.beginPath();
    ctx.moveTo(-34, -30); ctx.bezierCurveTo(-50, -48, -12, -54, 0, -40); ctx.bezierCurveTo(12, -54, 50, -48, 34, -30);
    ctx.bezierCurveTo(44, 0, 30, 20, 22, 44); ctx.bezierCurveTo(16, 56, 8, 40, 0, 26); ctx.bezierCurveTo(-8, 40, -16, 56, -22, 44);
    ctx.bezierCurveTo(-30, 20, -44, 0, -34, -30); ctx.closePath();
    ctx.fillStyle = '#FFFFFF'; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = S.deep; ctx.stroke();
    ctx.fillStyle = S.deep;
    for (const s of [-1, 1]) { ctx.beginPath(); ctx.ellipse(s * 12, -14, 4.5, 7, 0, 0, TAU); ctx.fill(); }
    ctx.beginPath(); ctx.arc(0, 0, 14, 0.2, Math.PI - 0.2); ctx.lineWidth = 4; ctx.stroke();
    ctx.restore();
    sparkle(ctx, px + 44, 96, 16, '#FFD23A');
    // the ghosted wordmark: cyan + magenta copies drifting apart behind the main one
    for (const [dx, col] of [[-6, 'rgba(63,214,224,0.85)'], [6, 'rgba(255,79,160,0.85)'], [0, S.deep]]) {
      text(ctx, 'Double', px + dx, 212, { fam: FONT.groovy, px: 62, fill: col, maxW: 236 });
      text(ctx, 'Vision', px + dx, 268, { fam: FONT.groovy, px: 62, fill: col, maxW: 236 });
    }
    rrp(ctx, px - 110, 306, 220, 34, 8); ctx.fillStyle = '#E23B3B'; ctx.fill();
    text(ctx, 'TOOTHPASTE', px, 324, { fam: FONT.sign, px: 24, fill: '#FFFFFF', track: 2, maxW: 200 });
    text(ctx, 'TWICE THE SMILE!', px, 356, { fam: FONT.round, px: 17, fill: S.deep });
    // back panel
    for (const ox of [0, w]) {
      rrp(ctx, ox - 80, 146, 160, 128, 16); ctx.fillStyle = S.deep; ctx.fill();
      rrp(ctx, ox - 74, 152, 148, 116, 12); ctx.fillStyle = '#FFFDF6'; ctx.fill();
    }
    for (const x of [0, w]) {
      text(ctx, 'WITH', x, 180, { fam: FONT.round, px: 18, fill: S.deep });
      text(ctx, 'SPARKLE', x, 208, { fam: FONT.sign, px: 22, fill: '#E23B3B' });
      text(ctx, 'CRYSTALS', x, 236, { fam: FONT.sign, px: 22, fill: '#2F5BD3' });
    }
  });
}

registerProp('product_double_vision', (game) => {
  const g = K.prop('product_double_vision');
  const tubeM = pm(game, 'plastic', '#ffffff', { map: tubeTex(), rough: 0.26 });
  const plastic = pm(game, 'plastic', '#ffffff', { rough: 0.28 });
  const chrome = pm(game, 'chrome', '#98A0AC');
  const rings = [[0.36, 0.0, 0.07, 5]];
  const N = 30;
  for (let i = 0; i <= N; i++) {
    const t = i / N, flat = 1 - smoothstep(t, 0.05, 0.5);
    const bulge = 0.012 * Math.sin(Math.PI * clamp((t - 0.45) / 0.55, 0, 1));
    rings.push([lerp(0.27, 0.365, flat) + bulge, lerp(0.27, 0.022, flat ** 1.5) + bulge, 0.07 + t * 1.0, lerp(2, 5, flat ** 1.5)]);
  }
  g.add(K.m(loft(rings, 48), tubeM));
  // shoulder + threaded neck
  const T = 1.07;
  g.add(K.m(paint(lathe2([[0.268, 0], [0.266, 0.02], [0.225, 0.065], [0.14, 0.094], [0.1, 0.1], [0.1, 0.13], [0, 0.13]], { seg: 40, round: 0.012, steps: 1, v: false }), '#F7F3EA'), plastic, { pos: [0, T, 0] }));
  for (const y of [0.107, 0.122]) g.add(K.m(paint(flatTorus(0.1, 0.006, 5, 24), '#F7F3EA'), plastic, { pos: [0, T + y, 0] }));
  // spinning fluted cap (parts.cap)
  const cap = new THREE.Group();
  cap.position.y = T + 0.098;
  cap.userData.noMerge = true;
  const cg = lathe2([[0, 0], [0.13, 0], [0.142, 0.012], [0.142, 0.15], [0.13, 0.168], [0.06, 0.176], [0, 0.176]], { seg: 48, round: 0.01, steps: 1, v: false });
  radial(cg, (th, y) => 1 + 0.045 * Math.max(0, Math.cos(th * 24)) * smoothstep(y, 0.015, 0.03) * (1 - smoothstep(y, 0.14, 0.155)));
  cap.add(K.m(paint(cg, '#2F5BD3'), plastic));
  cap.add(K.m(paint(flatTorus(0.1, 0.012, 6, 32), '#F7F3EA'), plastic, { pos: [0, 0.172, 0] }));
  cap.add(K.m(paint(K.cyl(0.075, 0.08, 0.02, { bevel: 0.008, seg: 24 }), '#E23B3B'), plastic, { pos: [0, 0.168, 0] }));
  g.add(cap);
  // chrome display clamp holding the crimp
  const steel = pm(game, 'metal', '#7A828E', { rough: 0.42, env: 0.12 });
  const base = lathe2([[0, 0], [0.34, 0], [0.352, 0.018], [0.32, 0.05], [0, 0.056]], { seg: 40, round: 0.01, steps: 1, v: false });
  base.scale(1.25, 1, 0.62);
  g.add(K.m(base, steel));
  g.add(K.m(K.box(0.84, 0.07, 0.09, 0.025), steel, { pos: [0, 0.09, 0] }));
  for (const sx of [-1, 1]) g.add(K.m(K.cyl(0.02, 0.02, 0.012, { bevel: 0.005, seg: 12 }), chrome, { pos: [sx * 0.3, 0.09, -0.046], rot: [Math.PI / 2, 0, 0] }));
  g.userData.parts = { cap };
  g.userData.colliders = [{ min: [-0.43, 0, -0.3], max: [0.43, 1.35, 0.3] }];
  return K.finish(game, g, { ao: { strength: 0.7 } });
}, { category: 'sponsors', tags: ['product', 'double_vision'], size: [0.86, 1.35, 0.44], desc: 'Double Vision striped toothpaste tube in a chrome clamp (parts.cap spins)', hero: true });

// =============================================================================================== DROPS
// drop_<type>: the item floats inside a 0.6 m glass "screen bubble" (glossy glass + additive fresnel shell with
// rolling scanlines in the drop's glow color, GDD §12) over a glowing gold floor ring. Local: floor at y=0; the
// bubble center sits at y=1.0 (parts.float). parts.model = the item; animated sub-parts listed per type.
// animateDrop(drop, t) runs the bob (0.1 m @ 1 Hz), the 90°/s spin and the item's own loop.
export const DROP_TYPES = ['cancelled', 'full_reel', 'one_take', 'sweeps_week', 'gaffer_tape', 'please_stand_by'];
const DROP_GLOW = { cancelled: '#E3662B', full_reel: '#FFC23A', one_take: '#FF3B30', sweeps_week: '#FF4FA0', gaffer_tape: '#DDE3EA', please_stand_by: '#EDEDED' };

const BUBBLE_VERT = /* glsl */`
varying vec3 vN; varying vec3 vV; varying vec3 vP;
void main() {
  vP = position;
  vN = normalize(normalMatrix * normal);
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  vV = normalize(-mv.xyz);
  gl_Position = projectionMatrix * mv;
}`;
const BUBBLE_FRAG = /* glsl */`
uniform vec3 uColor; uniform float uTime; uniform float uIntensity;
varying vec3 vN; varying vec3 vV; varying vec3 vP;
void main() {
  float f = 1.0 - abs(dot(normalize(vN), normalize(vV)));
  float edge = pow(f, 3.2);
  float scan = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(vP.y * 160.0 - uTime * 5.0));
  float roll = fract(vP.y * 1.3 - uTime * 0.45);
  float band = smoothstep(0.0, 0.05, roll) * (1.0 - smoothstep(0.05, 0.18, roll));
  float a = edge * 1.1 + scan * (0.018 + 0.25 * edge) + band * (0.035 + 0.3 * edge);
  gl_FragColor = vec4(uColor * a * uIntensity, 1.0);
}`;
const _bubbleMats = new WeakMap();
function bubbleMat(game, color, intensity = 1.1) {
  let m = _bubbleMats.get(game);
  if (!m) _bubbleMats.set(game, (m = new Map()));
  const key = `${color}|${intensity}`;
  if (!m.has(key)) {
    const mat = new THREE.ShaderMaterial({
      uniforms: { uColor: { value: new THREE.Color(color) }, uTime: game.mats.uniforms?.uTime ?? { value: 0 }, uIntensity: { value: intensity } },
      vertexShader: BUBBLE_VERT, fragmentShader: BUBBLE_FRAG,
      transparent: true, blending: THREE.AdditiveBlending, depthWrite: false,
    });
    mat.name = `bubble:${color}`;
    m.set(key, mat);
  }
  return m.get(key);
}
function radialTex() {
  return K.tex.canvas('sp.radial', 256, 256, (ctx, w, h) => {
    const g = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
    g.addColorStop(0, 'rgba(255,255,255,0.9)'); g.addColorStop(0.35, 'rgba(255,255,255,0.35)');
    g.addColorStop(0.72, 'rgba(255,255,255,0.12)'); g.addColorStop(0.86, 'rgba(255,255,255,0.5)'); g.addColorStop(0.93, 'rgba(255,255,255,0.08)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  }, { repeat: false });
}

// Shared shell: gold floor ring + bubble. Returns { g, float, model }.
function dropShell(game, type) {
  const g = K.prop(`drop_${type}`);
  const glowCol = DROP_GLOW[type];
  // glowing gold floor ring (flat glow ring + soft pool + a glossy gold torus)
  const ringG = new THREE.Group();
  ringG.add(K.m(new THREE.RingGeometry(0.32, 0.375, 40).rotateX(-Math.PI / 2), K.glow(game, PAL.marqueeGold, 1.5), { pos: [0, 0.012, 0], cast: false }));
  const pool = K.m(new THREE.CircleGeometry(0.58, 32).rotateX(-Math.PI / 2), K.glow(game, PAL.marqueeGold, 0.7, { map: radialTex(), additive: true }), { pos: [0, 0.008, 0], cast: false });
  ringG.add(pool);
  ringG.add(K.m(flatTorus(0.385, 0.016, 5, 40), pm(game, 'brass', '#D6A13C'), { pos: [0, 0.018, 0] }));
  ringG.traverse((o) => { if (o.isMesh) { o.userData.noAO = true; o.userData.noOcclude = true; o.userData.noShadow = true; } });
  g.add(ringG);
  // the floating screen bubble
  const float = new THREE.Group();
  float.position.y = 1.0;
  float.userData.noMerge = true;
  const shellG = K.cushion(0.6, 0.6, 0.6, { r: 0.16, puff: 0.04, seg: [6, 6, 6] });
  const glassM = game.mats.toon('#ffffff', { transparent: true, opacity: 0.07, rough: 0.06, env: 0.35, rim: 0.12, rimColor: '#ffffff',
    depthWrite: false, keepColor: true, name: 'bubble_glass' });
  const glass = K.m(shellG, glassM, { name: 'bubble_glass', cast: false });
  const rim = K.m(shellG, bubbleMat(game, glowCol), { name: 'bubble_rim', cast: false, scale: 1.004 });
  for (const o of [glass, rim]) { o.userData.noAO = true; o.userData.noShadow = true; o.renderOrder = 2; }
  const model = new THREE.Group();
  model.name = 'model';
  model.scale.setScalar(1.22);
  float.add(model, glass, rim);
  g.add(float);
  g.userData.colliders = [];
  g.userData.dropType = type;
  g.userData.glow = glowCol;
  g.userData.lightAnchors = [{ pos: [0, 0.15, 0], color: glowCol, intensity: 0.8, distance: 2.2 }]; // floor glow, below the item
  g.userData.parts = { float, model, bubble: glass, rim, ring: ringG };
  return { g, float, model };
}
// AO once, merge the static item meshes, then finish without re-baking.
function finishDrop(game, g, model) {
  K.bakeAO(g, { strength: 0.75, height: 0 });
  K.merge(model);
  return K.finish(game, g, { ao: false, merge: false, cast: 0.1 });
}

// ------------------------------------------------------------------ CANCELLED: rubber stamp over a stamped ticket
function stampTicketTex() {
  return texC('drop.ticket', 256, 160, (ctx, w, h, rand) => {
    ctx.fillStyle = '#FBF3DE'; ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = 'rgba(47,91,211,0.25)'; ctx.lineWidth = 2;
    for (let y = 26; y < h; y += 18) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke(); }
    ctx.save(); ctx.translate(w / 2, h / 2); ctx.rotate(-0.12);
    ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 7; rrp(ctx, -108, -38, 216, 76, 10); ctx.stroke();
    text(ctx, 'CANCELLED', 0, 2, { fam: FONT.sign, px: 34, fill: '#E23B3B', maxW: 196 });
    ctx.restore();
    ctx.globalCompositeOperation = 'destination-out';
    for (let i = 0; i < 90; i++) { ctx.globalAlpha = 0.25 + rand() * 0.4; ctx.beginPath(); ctx.arc(40 + rand() * 180, 40 + rand() * 80, 1 + rand() * 2.5, 0, TAU); ctx.fill(); }
    ctx.globalCompositeOperation = 'source-over'; ctx.globalAlpha = 1;
  });
}
function stampFaceTex() { // the rubber die: raised mirrored letters (seen from below)
  return texC('drop.stampface', 256, 128, (ctx, w, h) => {
    ctx.fillStyle = '#9E1E24'; ctx.fillRect(0, 0, w, h);
    ctx.save(); ctx.translate(w / 2, h / 2); ctx.scale(-1, 1);
    ctx.strokeStyle = '#E8454A'; ctx.lineWidth = 8; rrp(ctx, -112, -46, 224, 92, 10); ctx.stroke();
    text(ctx, 'CANCELLED', 0, 3, { fam: FONT.sign, px: 36, fill: '#E8454A', maxW: 200 });
    ctx.restore();
  });
}
registerProp('drop_cancelled', (game) => {
  const { g, float, model } = dropShell(game, 'cancelled');
  const red = pm(game, 'lacquer', '#E23B3B', { rough: 0.24 });
  const wood = pm(game, 'lacquer', '#ffffff', { map: K.tex.wood('#8A5A34', { dark: 0.35 }) });
  const label = pm(game, 'plastic', '#ffffff', { map: K.tex.label('CANCELLED', { bg: '#F6E7C8', fg: '#E23B3B', accent: '#5A3A22', w: 512, h: 128, border: 0.08, wear: 0.15 }) });
  const face = pm(game, 'rubber', '#ffffff', { map: stampFaceTex() });
  const paper = pm(game, 'paint', '#ffffff', { map: stampTicketTex(), side: THREE.DoubleSide, rim: 0.05 });
  const brass = pm(game, 'brass', '#C8963C');
  // stamped ticket at the bubble floor
  const tk = K.m(new THREE.PlaneGeometry(0.3, 0.19, 4, 1).rotateX(-Math.PI / 2).rotateY(Math.PI), paper, { pos: [0, -0.2, 0], rot: [0, 0.18, 0] });
  deform(tk.geometry, (v) => { v.y += 0.012 * Math.cos((v.x / 0.15) * 1.6); });
  model.add(tk);
  // the stamp (parts.stamp moves down to the ticket)
  const stamp = new THREE.Group();
  stamp.userData.noMerge = true;
  stamp.position.y = -0.1;
  stamp.add(K.m(K.box(0.27, 0.022, 0.13, 0.008), face, { pos: [0, 0.011, 0] }));
  stamp.add(K.m(new THREE.PlaneGeometry(0.25, 0.115).rotateX(Math.PI / 2), face, { pos: [0, -0.0005, 0] }));
  stamp.add(K.m(K.box(0.29, 0.07, 0.15, 0.018, { uv: 3 }), wood, { pos: [0, 0.057, 0] }));
  stamp.add(K.m(K.box(0.24, 0.042, 0.004, 0.002), label, { pos: [0, 0.057, -0.076] }));
  stamp.add(K.m(K.box(0.24, 0.042, 0.004, 0.002), label, { pos: [0, 0.057, 0.076], rot: [0, Math.PI, 0] }));
  stamp.add(K.m(K.lathe([[0, 0], [0.045, 0], [0.032, 0.03], [0.03, 0.06], [0.04, 0.075], [0.028, 0.095], [0, 0.095]], { seg: 16, round: 0.008, steps: 1 }), wood, { pos: [0, 0.09, 0] }));
  stamp.add(K.m(flatTorus(0.036, 0.008, 5, 16), brass, { pos: [0, 0.16, 0] }));
  stamp.add(K.m(K.lathe([[0, 0], [0.04, 0], [0.075, 0.025], [0.085, 0.06], [0.07, 0.095], [0.035, 0.112], [0, 0.114]], { seg: 20, round: 0.012, steps: 1 }), red, { pos: [0, 0.18, 0] }));
  model.add(stamp);
  model.rotation.set(0.12, -0.3, 0.05);
  g.userData.parts.stamp = stamp;
  return finishDrop(game, g, model);
}, { category: 'sponsors_drop', tags: ['drop', 'cancelled'], size: [0.84, 1.3, 0.84], desc: 'CANCELLED drop: red-knob rubber stamp over a stamped ticket (parts.stamp)' });

// ------------------------------------------------------------------ FULL REEL: 2-inch aluminium quad tape reel
function packTex() {
  return K.tex.canvas('sp.tapepack', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#6B4630'; ctx.fillRect(0, 0, w, h);
    for (let r = 20; r < 128; r += 1.6) {
      ctx.strokeStyle = rand() < 0.5 ? 'rgba(40,22,12,0.5)' : 'rgba(190,140,100,0.4)';
      ctx.lineWidth = 0.8 + rand(); ctx.beginPath(); ctx.arc(w / 2, h / 2, r, 0, TAU); ctx.stroke();
    }
  }, { repeat: false });
}
function hubTex() {
  return texC('drop.hub', 256, 256, (ctx, w, h) => {
    const cx = w / 2, cy = h / 2;
    ctx.fillStyle = '#FFC23A'; ctx.beginPath(); ctx.arc(cx, cy, 126, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#8A5A10'; ctx.lineWidth = 8; ctx.stroke();
    ctx.fillStyle = '#FFF4D0'; ctx.beginPath(); ctx.arc(cx, cy, 40, 0, TAU); ctx.fill();
    text(ctx, 'FULL', cx, cy - 72, { fam: FONT.sign, px: 34, fill: '#5A3A10' });
    text(ctx, 'REEL', cx, cy + 74, { fam: FONT.sign, px: 34, fill: '#5A3A10' });
    text(ctx, '2" QUAD', cx, cy, { fam: FONT.round, px: 18, fill: '#8A5A10' });
  });
}
function reelFlangeShape(R) {
  const s = new THREE.Shape();
  s.absarc(0, 0, R, 0, TAU, false);
  for (let i = 0; i < 3; i++) {
    const a0 = (i / 3) * TAU + 0.28, a1 = a0 + TAU / 3 - 0.56, r0 = R * 0.36, r1 = R * 0.86;
    const p = new THREE.Path();
    p.absarc(0, 0, r1, a0, a1, false);
    p.absarc(0, 0, r0, a1, a0, true);
    p.closePath();
    s.holes.push(p);
  }
  return s;
}
registerProp('drop_full_reel', (game) => {
  const { g, model } = dropShell(game, 'full_reel');
  const alu = pm(game, 'metal', '#C9CFD8', { rough: 0.3, map: K.tex.brushed('#D8DDE4'), side: THREE.DoubleSide });
  const pack = pm(game, 'lacquer', '#ffffff', { map: packTex(), rough: 0.25 });
  const hubM = pm(game, 'plastic', '#ffffff', { map: hubTex() });
  const R = 0.2, W = 0.09;
  const reel = new THREE.Group();
  reel.userData.noMerge = true;
  const fl = new THREE.ShapeGeometry(reelFlangeShape(R), 10);
  K.uvScale(fl, 3, 3);
  reel.add(K.m(fl, alu, { pos: [0, 0, -W / 2] }), K.m(fl, alu, { pos: [0, 0, W / 2] }));
  for (const z of [-W / 2, W / 2]) reel.add(K.m(new THREE.TorusGeometry(R, 0.007, 5, 40), alu, { pos: [0, 0, z] }));
  // wound tape pack (concentric-ring caps show through the windows) + hub
  const pk = new THREE.CylinderGeometry(R * 0.8, R * 0.8, W - 0.012, 40, 1).rotateX(Math.PI / 2);
  reel.add(K.m(pk, pack));
  reel.add(K.m(new THREE.CylinderGeometry(0.065, 0.065, W + 0.03, 24).rotateX(Math.PI / 2), alu));
  for (const s of [-1, 1]) {
    const lab = new THREE.CircleGeometry(0.062, 24);
    if (s > 0) lab.rotateY(Math.PI);
    reel.add(K.m(lab, hubM, { pos: [0, 0, s * -(W / 2 + 0.0155)] }));
  }
  // loose tape tail with a white leader
  reel.add(K.m(paint(K.tube([[R * 0.8, 0, 0], [R * 0.95, -0.08, 0], [R * 0.9, -0.17, 0.01]], 0.01, { seg: 10, radial: 4 }), '#3B2A22'), pm(game, 'plastic', '#ffffff')));
  model.add(reel);
  model.rotation.set(0.15, -0.35, 0);
  g.userData.parts.reel = reel;
  return finishDrop(game, g, model);
}, { category: 'sponsors_drop', tags: ['drop', 'full_reel'], size: [0.84, 1.3, 0.84], desc: 'FULL REEL drop: spinning 2-inch aluminium quad tape reel (parts.reel spins on z)' });

// ------------------------------------------------------------------ ONE TAKE: clapperboard that keeps clapping
function slateTex() {
  return texC('drop.slate', 512, 512, (ctx, w, h) => {
    // slate face (top 384 px)
    ctx.fillStyle = '#26222E'; ctx.fillRect(0, 0, w, 384);
    ctx.strokeStyle = '#F4F1E8'; ctx.lineWidth = 5;
    rrp(ctx, 14, 14, w - 28, 356, 16); ctx.stroke();
    ctx.lineWidth = 4;
    for (const y of [96, 196, 290]) { ctx.beginPath(); ctx.moveTo(14, y); ctx.lineTo(w - 14, y); ctx.stroke(); }
    for (const x of [180, 346]) { ctx.beginPath(); ctx.moveTo(x, 196); ctx.lineTo(x, 290); ctx.stroke(); }
    text(ctx, 'ONE TAKE', w / 2, 56, { fam: FONT.groovy, px: 60, fill: '#FFD23A', stroke: '#E23B3B', lw: 8 });
    text(ctx, 'PROD.', 60, 124, { fam: FONT.round, px: 20, fill: '#CFC8D8' });
    text(ctx, 'DEAD AIR', w / 2 + 30, 150, { fam: FONT.sign, px: 44, fill: '#F4F1E8' });
    [['ROLL', '13', 97], ['SCENE', '1', 263], ['TAKE', '1', 428]].forEach(([a, b, x]) => {
      text(ctx, a, x, 214, { fam: FONT.round, px: 18, fill: '#CFC8D8' });
      text(ctx, b, x, 256, { fam: FONT.sign, px: 44, fill: b === '1' && a === 'TAKE' ? '#FFD23A' : '#F4F1E8' });
    });
    text(ctx, 'WZTV 13 · 1977', w / 2, 330, { fam: FONT.round, px: 24, fill: '#F4F1E8' });
    // clapper stripes (bottom 128 px)
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 384, w, 128);
    ctx.fillStyle = '#26222E';
    for (let i = -2; i < 10; i++) { ctx.beginPath(); ctx.moveTo(i * 64, 384); ctx.lineTo(i * 64 + 32, 384); ctx.lineTo(i * 64 + 72, 512); ctx.lineTo(i * 64 + 40, 512); ctx.closePath(); ctx.fill(); }
  });
}
registerProp('drop_one_take', (game) => {
  const { g, model } = dropShell(game, 'one_take');
  const tx = slateTex();
  const slateM = pm(game, 'plastic', '#ffffff', { map: tx, rough: 0.5 });
  const body = pm(game, 'plastic', '#2A2632', { rough: 0.45 });
  const chrome = pm(game, 'chrome', '#98A0AC');
  const W = 0.4, H = 0.29;
  model.add(K.m(K.box(W, H, 0.03, 0.012), body, { pos: [0, -0.04, 0] }));
  const face = K.uvRect(new THREE.PlaneGeometry(W - 0.02, H - 0.02), 0, 0.25, 1, 1).rotateY(Math.PI);
  model.add(K.m(face, slateM, { pos: [0, -0.04, -0.0155] }));
  const stick = (y) => {
    const s = uvPlanar(K.box(W + 0.01, 0.055, 0.032, 0.01).clone(), 'x', W / 2 + 0.01, -W / 2 - 0.01, 'y', -0.2, 0.2);
    const uv = s.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setY(i, 0.0 + clamp(uv.getY(i), 0, 1) * 0.25 * (0.99));
    return K.m(s, slateM, { pos: [0, y, 0] });
  };
  model.add(stick(H / 2 - 0.04 + 0.03));
  // hinged top clapper (parts.clapper: rotate z to open, pivot at the left hinge = +x seen from the front)
  const clap = new THREE.Group();
  clap.userData.noMerge = true;
  clap.position.set(W / 2, H / 2 - 0.04 + 0.09, 0);
  const top = stick(0); top.position.set(-W / 2, 0, 0);
  clap.add(top);
  clap.rotation.z = -0.3;
  model.add(clap);
  model.scale.setScalar(1.02);
  model.position.y = -0.035;
  model.add(K.m(K.cyl(0.018, 0.018, 0.05, { bevel: 0.006, seg: 12 }), chrome, { pos: [W / 2, H / 2 - 0.04 + 0.06, -0.025], rot: [Math.PI / 2, 0, 0] }));
  model.rotation.set(0.1, 0.35, 0.06);
  g.userData.parts.clapper = clap;
  return finishDrop(game, g, model);
}, { category: 'sponsors_drop', tags: ['drop', 'one_take'], size: [0.84, 1.3, 0.84], desc: 'ONE TAKE drop: clapperboard, hinged clapper (parts.clapper rotates on z)' });

// ------------------------------------------------------------------ SWEEPS WEEK: little TV with ×2 + ratings meter
function x2Tex() {
  return texC('drop.x2', 256, 192, (ctx, w, h) => {
    ctx.fillStyle = lin(ctx, 0, 0, 0, h, ['#FF6FB8', '#D8307E']); ctx.fillRect(0, 0, w, h);
    rays(ctx, w / 2, h / 2, 220, 16, 'rgba(255,230,150,0.2)');
    text(ctx, '×2', w / 2, h / 2 - 8, { fam: FONT.groovy, px: 118, fill: lin(ctx, 0, 40, 0, 140, ['#FFF6B0', '#FFC23A', '#E89A1A']), stroke: '#5A1440', lw: 10, depth: 5, depthFill: '#5A1440' });
    text(ctx, 'SWEEPS WEEK', w / 2, h - 22, { fam: FONT.sign, px: 22, fill: '#FFFFFF', stroke: '#5A1440', lw: 4 });
  });
}
function meterTex() {
  return texC('drop.meter', 256, 144, (ctx, w, h) => {
    ctx.fillStyle = '#FFF4D8'; ctx.fillRect(0, 0, w, h);
    const cx = w / 2, cy = h - 18;
    for (let i = 0; i <= 20; i++) {
      const a = Math.PI + (i / 20) * Math.PI, r0 = i % 5 ? 96 : 86;
      ctx.strokeStyle = i > 14 ? '#E23B3B' : i > 9 ? '#E8A92E' : '#3FA34A'; ctx.lineWidth = i % 5 ? 3 : 5;
      ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0); ctx.lineTo(cx + Math.cos(a) * 108, cy + Math.sin(a) * 108); ctx.stroke();
    }
    ctx.lineWidth = 12; ctx.strokeStyle = 'rgba(226,59,59,0.85)'; ctx.beginPath(); ctx.arc(cx, cy, 116, Math.PI * 1.72, Math.PI * 2); ctx.stroke();
    text(ctx, 'RATINGS', cx, cy - 40, { fam: FONT.sign, px: 22, fill: '#2A1D3A' });
    text(ctx, '+', 34, 40, { fam: FONT.sign, px: 26, fill: '#E23B3B' });
  });
}
registerProp('drop_sweeps_week', (game) => {
  const { g, model } = dropShell(game, 'sweeps_week');
  const shell = pm(game, 'plastic', '#F6E7C8', { rough: 0.3 });
  const trim = pm(game, 'plastic', '#FF4FA0', { rough: 0.3 });
  const dark = pm(game, 'plastic', '#2A2230', { rough: 0.35 });
  const scr = K.glow(game, '#ffffff', 1.0, { map: x2Tex() });
  const meter = pm(game, 'plastic', '#ffffff', { map: meterTex(), rough: 0.4 });
  const W = 0.34, H = 0.25, D = 0.22;
  model.add(K.m(K.box(W, H, D, 0.048), shell, { pos: [0, -0.07, 0] }));
  model.add(K.m(K.taper(K.box(W * 0.8, H * 0.78, 0.1, 0.04), { axis: 'z', k: 0.6 }), trim, { pos: [0, -0.07, D / 2 + 0.03] }));
  const bez = K.roundRect(0.25, 0.19, 0.045);
  bez.holes.push(new THREE.Path(K.roundRect(0.21, 0.155, 0.035).getPoints(8)));
  model.add(K.m(K.extrude(bez, 0.02, { bevel: 0.006, bevelSeg: 1, curveSeg: 6 }), trim, { pos: [-0.03, -0.07, -D / 2 - 0.004] }));
  const sg = new THREE.PlaneGeometry(0.212, 0.157, 6, 5);
  deform(sg, (v) => { v.z = 0.008 * (1 - (v.x / 0.106) ** 2 * 0.5 - (v.y / 0.078) ** 2 * 0.5); });
  sg.rotateY(Math.PI);
  const screen = K.m(sg, scr, { pos: [-0.03, -0.07, -D / 2 - 0.002], cast: false });
  screen.userData.noAO = true;
  model.add(screen);
  for (const [dy, m] of [[0.04, dark], [-0.03, trim]]) model.add(K.m(K.cyl(0.022, 0.024, 0.02, { bevel: 0.006, seg: 14 }), m, { pos: [0.132, -0.07 + dy, -D / 2 - 0.004], rot: [-Math.PI / 2, 0, 0] }));
  model.add(K.m(K.box(0.05, 0.03, 0.006, 0.003), dark, { pos: [0.132, -0.17, -D / 2 - 0.002] }));
  for (const sx of [-1, 1]) model.add(K.m(K.cyl(0.018, 0.022, 0.03, { bevel: 0.006, seg: 10 }), dark, { pos: [sx * 0.11, -0.225, 0] }));
  // the ratings meter perched on top (half-dome housing, printed face, red needle = parts.needle)
  const hous = new THREE.Group();
  hous.position.set(0, -0.07 + H / 2, 0);
  hous.add(K.m(K.extrude(K.roundRect(0.2, 0.12, 0.05), 0.08, { bevel: 0.012, curveSeg: 8 }), trim, { pos: [0, 0.07, 0] }));
  const face = new THREE.PlaneGeometry(0.17, 0.095).rotateY(Math.PI);
  hous.add(K.m(face, meter, { pos: [0, 0.07, -0.041] }));
  const needle = new THREE.Group();
  needle.userData.noMerge = true;
  needle.position.set(0, 0.03, -0.047);
  needle.add(K.m(paint(K.box(0.006, 0.085, 0.004, 0.002), '#E23B3B'), pm(game, 'plastic', '#ffffff'), { pos: [0, 0.042, 0] }));
  needle.add(K.m(new THREE.CylinderGeometry(0.009, 0.009, 0.008, 10).rotateX(Math.PI / 2), dark));
  needle.rotation.z = -0.95;
  hous.add(needle);
  model.add(hous);
  model.rotation.set(0.1, -0.35, 0);
  g.userData.parts.needle = needle;
  return finishDrop(game, g, model);
}, { category: 'sponsors_drop', tags: ['drop', 'sweeps_week'], size: [0.84, 1.3, 0.84], desc: 'SWEEPS WEEK drop: little TV showing ×2 with a ratings meter on top (parts.needle)' });

// ------------------------------------------------------------------ GAFFER TAPE: roll of silver gaffer tape
function woundTex() {
  return K.tex.canvas('sp.wound', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#A9B0BA'; ctx.fillRect(0, 0, w, h);
    for (let r = 60; r < 128; r += 1.4) {
      ctx.strokeStyle = rand() < 0.5 ? 'rgba(70,76,88,0.35)' : 'rgba(235,240,246,0.4)';
      ctx.lineWidth = 0.7 + rand(); ctx.beginPath(); ctx.arc(w / 2, h / 2, r, 0, TAU); ctx.stroke();
    }
  }, { repeat: false });
}
registerProp('drop_gaffer_tape', (game) => {
  const { g, model } = dropShell(game, 'gaffer_tape');
  const cloth = pm(game, 'metal', '#ffffff', { map: K.tex.weave('#B7BEC8', { pattern: 'plain', scale: 3 }), rough: 0.5, env: 0.25 });
  const side = pm(game, 'metal', '#ffffff', { map: woundTex(), rough: 0.45, env: 0.25 });
  const core = pm(game, 'paint', '#B8915F', { rim: 0.08 });
  const R0 = 0.085, R1 = 0.17, W = 0.11;
  const roll = new THREE.Group();
  roll.userData.noMerge = true;
  const tread = new THREE.CylinderGeometry(R1, R1, W, 44, 1, true);
  K.uvScale(tread, 5, 1);
  roll.add(K.m(tread, cloth));
  for (const s of [-1, 1]) {
    const face = new THREE.RingGeometry(R0 + 0.005, R1, 44, 1).rotateX(s * -Math.PI / 2);
    roll.add(K.m(face, side, { pos: [0, (s * W) / 2, 0] }));
    roll.add(K.m(flatTorus(R1 - 0.004, 0.006, 5, 44), cloth, { pos: [0, (s * (W - 0.008)) / 2, 0] }));
  }
  const coreG = lathe2([[R0 + 0.008, W / 2 + 0.006], [R0, W / 2 + 0.006], [R0, -W / 2 - 0.006], [R0 + 0.008, -W / 2 - 0.006], [R0 + 0.008, W / 2 + 0.006]], { seg: 32, v: false });
  roll.add(K.m(coreG, core));
  // the torn tail curling off the roll
  // local axis = y (the roll is turned so y faces the viewer); world "down" is local +z
  const tail = new THREE.PlaneGeometry(W - 0.006, 0.2, 6, 10);
  {
    const p = tail.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const col = i % 7, row = Math.floor(i / 7), s = (row / 10) * 0.2, s1 = 0.07, y = p.getX(i);
      let x, z;
      if (s < s1) { const a = Math.PI / 2 + (s1 - s) / R1; x = Math.sin(a) * (R1 + 0.002); z = Math.cos(a) * (R1 + 0.002); }
      else { const d = s - s1; x = R1 + 0.002 + d * 0.2 + d * d * 1.2; z = d; }
      if (row === 10) z += col % 2 ? 0.014 : -0.004;
      p.setXYZ(i, x, y, z);
    }
    tail.computeVertexNormals();
  }
  const tailM = pm(game, 'metal', '#ffffff', { map: K.tex.weave('#B7BEC8', { pattern: 'plain', scale: 3 }), rough: 0.5, env: 0.25, side: THREE.DoubleSide });
  roll.add(K.m(tail, tailM));
  roll.rotation.x = Math.PI / 2;
  model.add(roll);
  model.rotation.set(0.25, -0.5, 0.15);
  g.userData.parts.roll = roll;
  return finishDrop(game, g, model);
}, { category: 'sponsors_drop', tags: ['drop', 'gaffer_tape'], size: [0.84, 1.3, 0.84], desc: 'GAFFER TAPE drop: roll of silver cloth tape with a torn tail (parts.roll)' });

// ------------------------------------------------------------------ PLEASE STAND BY: tiny space-age TV with the test card
registerProp('drop_please_stand_by', (game) => {
  const { g, model } = dropShell(game, 'please_stand_by');
  const shell = pm(game, 'plastic', '#E23B3B', { rough: 0.24 });
  const cream = pm(game, 'plastic', '#F6E7C8', { rough: 0.3 });
  const dark = pm(game, 'plastic', '#2A2230', { rough: 0.35 });
  const chrome = pm(game, 'chrome', '#98A0AC');
  const scr = K.glow(game, '#ffffff', 0.78, { map: getCard('test_card') });
  // Videosphere-style helmet TV: ball body, cream face ring, chain loop on top, pedestal
  const R = 0.16;
  const ball = new THREE.SphereGeometry(R, 22, 15);
  model.add(K.m(ball, shell, { pos: [0, 0, 0] }));
  const ringG = K.extrude(K.roundRect(0.23, 0.19, 0.07), 0.05, { bevel: 0.014, curveSeg: 8 });
  model.add(K.m(ringG, cream, { pos: [0, 0, -R + 0.022] }));
  const sg = new THREE.PlaneGeometry(0.19, 0.143, 8, 6);
  deform(sg, (v) => { v.z = 0.012 * (1 - (v.x / 0.095) ** 2 * 0.5 - (v.y / 0.072) ** 2 * 0.5); });
  sg.rotateY(Math.PI);
  const screen = K.m(sg, scr, { pos: [0, 0, -R - 0.006], cast: false });
  screen.userData.noAO = true;
  model.add(screen);
  model.add(K.m(K.box(0.2, 0.012, 0.006, 0.003), dark, { pos: [0, -0.086, -R + 0.003] }));
  model.add(K.m(new THREE.TorusGeometry(0.05, 0.009, 6, 20), chrome, { pos: [0, R + 0.04, 0] }));
  model.add(K.m(K.cyl(0.03, 0.035, 0.03, { bevel: 0.008, seg: 14 }), chrome, { pos: [0, R - 0.02, 0] }));
  model.add(K.m(K.lathe([[0, 0], [0.11, 0], [0.115, 0.012], [0.08, 0.03], [0.045, 0.05], [0.04, 0.07], [0, 0.07]], { seg: 24, round: 0.008, steps: 1 }), cream, { pos: [0, -R - 0.06, 0] }));
  for (const sx of [-1, 1]) model.add(K.m(K.cyl(0.018, 0.02, 0.018, { bevel: 0.005, seg: 12 }), dark, { pos: [sx * R * 0.72, -0.02, R * 0.62], rot: [0, 0, sx * Math.PI / 2] }));
  model.rotation.set(0.12, -0.3, 0);
  model.position.y = 0.03;
  return finishDrop(game, g, model);
}, { category: 'sponsors_drop', tags: ['drop', 'please_stand_by'], size: [0.84, 1.3, 0.84], desc: 'PLEASE STAND BY drop: tiny red space-age TV showing the test card' });

// Bob + spin + each item's own loop. t = seconds (use the drop's age).
export function animateDrop(drop, t) {
  const p = drop.userData.parts;
  if (!p || !p.float) return;
  p.float.position.y = 1.0 + Math.sin(t * TAU) * 0.05;
  p.float.rotation.y = t * (Math.PI / 2);
  const type = drop.userData.dropType;
  if (type === 'cancelled' && p.stamp) {
    const c = (t * 1.4) % 1; // lift, slam, hold
    p.stamp.position.y = -0.1 + (c < 0.55 ? smoothstep(c, 0, 0.5) * 0.09 : c < 0.62 ? 0.09 * (1 - (c - 0.55) / 0.07) : 0) - (c >= 0.62 && c < 0.7 ? 0.004 : 0);
  } else if (type === 'full_reel' && p.reel) p.reel.rotation.z = -t * 5;
  else if (type === 'one_take' && p.clapper) {
    const c = (t * 1.2) % 1;
    p.clapper.rotation.z = c < 0.7 ? -0.34 * smoothstep(c, 0, 0.6) : -0.34 * (1 - (c - 0.7) / 0.06) * (c < 0.76 ? 1 : 0);
  } else if (type === 'sweeps_week' && p.needle) p.needle.rotation.z = -0.9 + Math.sin(t * 9) * 0.08 + Math.sin(t * 2.3) * 0.12;
  else if (type === 'gaffer_tape' && p.roll) p.roll.rotation.y = t * 2;
}

// =============================================================================================== COSTUMES
// costume_<name> and costume_<name>_gold (Sign-Off reward: gold leaf). Each root holds userData.parts.<slot>
// (head | handL | footL/footR | back | wristL/wristR/neck), every part built around its SLOT ORIGIN with the
// hero convention (+y up, face toward -z, hero's left = -x). The root lays the parts out for the gallery only:
// reparent a part to hero.slots.<slot> and reset its position/rotation (scale by userData.fit when needed).
// userData.fit = { slot:{...} reference sizes }, userData.perk = perkId. No colliders.
const GOLD = { light: '#F4D885', mid: '#E2B04A', deep: '#B98232', rose: '#EBAE72' };
function goldLeafTex() {
  return K.tex.canvas('sp.goldleaf', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#F6EEDC'; ctx.fillRect(0, 0, w, h);
    const n = 4, s = w / n;
    for (let y = 0; y < n; y++) for (let x = -1; x < n; x++) {
      const ox = (y % 2) * s * 0.5;
      ctx.fillStyle = `hsl(${38 + rand() * 8}, ${40 + rand() * 20}%, ${84 + rand() * 12}%)`;
      ctx.fillRect(x * s + ox, y * s, s, s);
    }
    ctx.strokeStyle = 'rgba(120,80,20,0.35)'; ctx.lineWidth = 1.4;
    for (let y = 0; y <= n; y++) { ctx.beginPath(); ctx.moveTo(0, y * s + rand() * 2); ctx.lineTo(w, y * s + rand() * 2); ctx.stroke(); }
    for (let i = 0; i < 260; i++) {
      ctx.strokeStyle = rand() < 0.5 ? 'rgba(255,255,255,0.55)' : 'rgba(140,96,30,0.35)';
      ctx.lineWidth = 0.6 + rand();
      const x = rand() * w, y = rand() * h, a = rand() * TAU, l = 2 + rand() * 9;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); ctx.stroke();
    }
  });
}
// Material provider: normal preset/color, or gold leaf in a tone that keeps the pattern readable.
function cmat(game, gold) {
  return (preset, color, tone = 'mid', extra = {}) => (gold
    ? K.mat(game, 'brass', GOLD[tone] || tone, { map: extra.goldMap ?? goldLeafTex(), keepColor: true, rough: 0.28, ...(extra.goldExtra || {}) })
    : pm(game, preset, color, extra.normal || {}));
}
function finishCostume(game, g, parts) {
  for (const p of Object.values(parts)) { p.userData.noMerge = true; if (!p.parent) g.add(p); }
  K.bakeAO(g, { floor: false, height: 0, strength: 0.7, dist: 0.12 });
  for (const p of Object.values(parts)) K.merge(p);
  g.userData.parts = parts;
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false, merge: false, cast: 0.08 });
}
const costumeMeta = (perk, slot, gold, desc) => ({ category: 'sponsors_costume', tags: ['costume', perk, slot, ...(gold ? ['gold'] : [])], desc: (gold ? 'GOLD LEAF · ' : '') + desc });

// ------------------------------------------------------------------ Wobble-Up: gelatin ring-mold helmet (head)
function buildJellyHelmet(game, gold) {
  const id = `costume_jelly_helmet${gold ? '_gold' : ''}`;
  const g = K.prop(id);
  const jellyM = gold
    ? pm(game, 'plastic', '#E6A21C', { transparent: true, opacity: 0.86, rough: 0.08, env: 0.3, emissive: '#9A5A08', emissiveIntensity: 0.5, rim: 0.4, rimColor: '#FFE7A0', rimPower: 2.4 })
    : pm(game, 'plastic', '#067A30', { transparent: true, opacity: 0.88, rough: 0.1, env: 0.2, emissive: '#046A28', emissiveIntensity: 0.6, rim: 0.3, rimColor: '#6CFFA0', rimPower: 2.6 });
  const M = cmat(game, gold);
  const fruitM = gold ? M('', '', 'mid') : pm(game, 'lacquer', '#ffffff', { rough: 0.3 });
  const creamM = M('ceramic', '#FFF6E6', 'light', { normal: { rough: 0.55 } });
  const head = new THREE.Group();
  const cav = (y) => Math.sqrt(Math.max(0, 0.285 ** 2 - (y + 0.2) ** 2));
  const prof = [[0, 0.085], [cav(0.05), 0.05], [cav(0.0), 0.0], [cav(-0.05), -0.05], [cav(-0.1), -0.1], [0.285, -0.128], [0.3, -0.13], [0.312, -0.115],
    [0.318, -0.03], [0.285, -0.004], [0.268, 0.012], [0.248, 0.1], [0.205, 0.145], [0.14, 0.168], [0.1, 0.163], [0.084, 0.13], [0, 0.125]];
  const hg = lathe2(prof, { seg: 40, round: 0.012, steps: 1, v: false });
  radial(hg, (th, y, r) => {
    if (r < cav(y) + 0.02 || y < -0.128) return 1;
    const t = smoothstep(y, -0.02, 0.02), w = smoothstep(r - cav(y), 0.02, 0.04) * (1 - smoothstep(y, 0.13, 0.16));
    return 1 + 0.055 * w * Math.cos(th * 10 + Math.PI * t);
  });
  head.add(K.m(hg, jellyM, { name: 'jelly' }));
  // suspended fruit (gold: gold-leaf flakes) in the thick upper tier
  for (let i = 0; i < 7; i++) {
    const a = (i / 7) * TAU + 0.3, rr = 0.2, y = 0.05 + (i % 2) * 0.03;
    const geo = gold ? new THREE.OctahedronGeometry(0.022, 0) : [() => paint(new THREE.SphereGeometry(0.024, 8, 6), '#D81E3A'), () => paint(K.box(0.04, 0.03, 0.035, 0.01), '#FFD84A'), () => paint(new THREE.SphereGeometry(0.02, 8, 6), '#8A3C9A')][i % 3]();
    head.add(K.m(geo, fruitM, { pos: [Math.sin(a) * rr, y, Math.cos(a) * rr], rot: [i, a, i * 0.5] }));
  }
  const cg = lathe2([[0, 0], [0.105, 0], [0.098, 0.025], [0.07, 0.05], [0.04, 0.072], [0.01, 0.088], [0, 0.09]], { seg: 32, v: false });
  radial(cg, (th, y) => 1 + 0.13 * Math.cos(th * 8 + y * 50));
  head.add(K.m(cg, creamM, { pos: [0, 0.125, 0] }));
  head.add(K.m(gold ? new THREE.SphereGeometry(0.035, 14, 10) : paint(new THREE.SphereGeometry(0.035, 14, 10), '#E0183A'), gold ? M('', '', 'rose') : fruitM, { pos: [0.005, 0.24, 0] }));
  head.add(K.m(gold ? K.tube([[0.005, 0.27, 0], [0.02, 0.31, 0.005], [0.045, 0.33, 0.01]], 0.004, { seg: 6, radial: 4 }) : paint(K.tube([[0.005, 0.27, 0], [0.02, 0.31, 0.005], [0.045, 0.33, 0.01]], 0.004, { seg: 6, radial: 4 }), '#6B8A2A'), gold ? M('', '', 'deep') : fruitM));
  head.position.y = 0.14;
  g.userData.fit = { head: { anchor: 'crown', headRadius: 0.25, note: 'scale = hairBounds*1.05/0.25; cavity fits a 0.285 m sphere centered 0.2 m below the crown' } };
  g.userData.perk = 'wobble_up';
  g.userData.wobble = 'parts.head: squash y / stretch xz on hits (damped spring)';
  return finishCostume(game, g, { head });
}
registerProp('costume_jelly_helmet', (game) => buildJellyHelmet(game, false), costumeMeta('wobble_up', 'head', false, 'translucent emerald gelatin ring-mold helmet with fruit, cream and a cherry'));
registerProp('costume_jelly_helmet_gold', (game) => buildJellyHelmet(game, true), costumeMeta('wobble_up', 'head', true, 'honey-gold gelatin helmet with gold-leaf flakes'));

// ------------------------------------------------------------------ Jump Cut: oversized oven mitt (handL)
function quiltTex(gold) {
  return texC(`quilt.${gold ? 'g' : 'n'}`, 256, 384, (ctx, w, h) => {
    const base = gold ? '#F2E2BC' : '#F07A28', line = gold ? 'rgba(130,86,20,0.55)' : 'rgba(150,50,10,0.55)', hi = gold ? 'rgba(255,255,255,0.5)' : 'rgba(255,200,150,0.45)';
    ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
    ctx.lineWidth = 3;
    for (let k = -12; k < 20; k++) for (const dir of [1, -1]) {
      ctx.strokeStyle = line; ctx.setLineDash([7, 4]);
      ctx.beginPath(); ctx.moveTo(k * 36, 0); ctx.lineTo(k * 36 + dir * h, h); ctx.stroke();
      ctx.strokeStyle = hi; ctx.setLineDash([]); ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(k * 36 + 4, 0); ctx.lineTo(k * 36 + 4 + dir * h, h); ctx.stroke(); ctx.lineWidth = 3;
    }
    ctx.setLineDash([]);
    // logo roundel with the lightning bolt
    const cx = w * 0.5, cy = h * 0.52;
    ctx.beginPath(); ctx.arc(cx, cy, 62, 0, TAU); ctx.fillStyle = gold ? '#FFF6DA' : '#F6E7C8'; ctx.fill();
    ctx.lineWidth = 9; ctx.strokeStyle = gold ? '#A87428' : '#5A3A22'; ctx.stroke();
    boltP(ctx, cx, cy, 96); ctx.fillStyle = gold ? '#C8902E' : '#FFD23A'; ctx.fill();
    ctx.lineWidth = 6; ctx.lineJoin = 'round'; ctx.strokeStyle = gold ? '#7A5210' : '#4A1E0E'; ctx.stroke();
  });
}
function tickingTex(gold) {
  return texC(`ticking.${gold ? 'g' : 'n'}`, 128, 64, (ctx, w, h) => {
    ctx.fillStyle = gold ? '#F6ECD2' : '#F6E7C8'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = gold ? '#B98232' : '#C0392B';
    for (let x = 0; x < w; x += 16) { ctx.fillRect(x, 0, 5, h); ctx.fillRect(x + 8, 0, 2, h); }
  }, { repeat: true });
}
function buildOvenMitt(game, gold) {
  const id = `costume_oven_mitt${gold ? '_gold' : ''}`;
  const g = K.prop(id);
  const M = cmat(game, gold);
  const mitt = M('fabric', '#ffffff', 'mid', { goldMap: quiltTex(true), normal: { map: quiltTex(false), rim: 0.3 } });
  const cuff = M('fabric', '#ffffff', 'light', { goldMap: tickingTex(true), normal: { map: tickingTex(false), rim: 0.3 } });
  const loopM = M('fabric', '#5A3A22', 'deep');
  const hand = new THREE.Group();
  // mitten outline in (u = forward, v = up); fingertips down; thumb forward
  const pts = [[-0.075, 0.07], [-0.08, -0.12], [-0.07, -0.2], [-0.035, -0.235], [0.02, -0.235], [0.055, -0.205], [0.07, -0.15],
    [0.07, -0.12], [0.1, -0.135], [0.13, -0.11], [0.132, -0.075], [0.105, -0.035], [0.075, -0.005], [0.07, 0.07]];
  const sh = K.extrude(pts, 0.12, { bevel: 0.045, round: 0.03, curveSeg: 6, bevelSeg: 3 });
  uvPlanar(sh, 'x', -0.09, 0.14, 'y', -0.25, 0.08);
  sh.rotateY(Math.PI / 2); // shape u -> -z (forward), thickness along x
  hand.add(K.m(sh, mitt));
  // padded ticking-stripe cuff + hanging loop
  const cuffG = new THREE.CylinderGeometry(1, 1.06, 0.07, 24, 1, true);
  cuffG.scale(0.074, 1, 0.09);
  K.uvScale(cuffG, 4, 1);
  hand.add(K.m(cuffG, cuff, { pos: [0, 0.085, 0.005] }));
  const roll = new THREE.TorusGeometry(1, 0.26, 8, 24).rotateX(Math.PI / 2);
  roll.scale(0.08, 0.1, 0.097);
  hand.add(K.m(roll, cuff, { pos: [0, 0.12, 0.005] }));
  hand.add(K.m(new THREE.TorusGeometry(0.022, 0.006, 5, 12), loopM, { pos: [0, 0.155, 0.09], rot: [0, Math.PI / 2, 0] }));
  hand.position.set(0, 0.3, 0);
  hand.rotation.y = -0.5;
  g.userData.fit = { handL: { anchor: 'palm center (hand slot)', note: 'fingertips toward -y, thumb toward -z; about 2.3x a 0.14 m hand' } };
  g.userData.perk = 'jump_cut';
  return finishCostume(game, g, { handL: hand });
}
registerProp('costume_oven_mitt', (game) => buildOvenMitt(game, false), costumeMeta('jump_cut', 'handL', false, 'oversized quilted orange oven mitt with the Jump Cut lightning-bolt logo'));
registerProp('costume_oven_mitt_gold', (game) => buildOvenMitt(game, true), costumeMeta('jump_cut', 'handL', true, 'gold-leaf oven mitt'));

// ------------------------------------------------------------------ Roller Boogie: roller-skate wheel sets (feet)
function buildSkates(game, gold) {
  const id = `costume_skates${gold ? '_gold' : ''}`;
  const g = K.prop(id);
  const M = cmat(game, gold);
  const chrome = gold ? M('', '', 'light') : pm(game, 'chrome', '#98A0AC');
  const plastic = gold ? null : pm(game, 'lacquer', '#ffffff', { rough: 0.3 });
  const wheelTone = ['rose', 'light', 'mid', 'deep'];
  const cols = [BAR.red, BAR.yellow, BAR.green, BAR.blue];
  const WR = 0.05, WY = -0.068;
  const wheel = K.lathe([[0.02, -0.026], [0.042, -0.026], [0.05, -0.016], [0.05, 0.016], [0.042, 0.026], [0.02, 0.026]], { seg: 12, round: 0.007, steps: 1 });
  const hub = new THREE.CylinderGeometry(0.02, 0.02, 0.056, 8).rotateZ(Math.PI / 2);
  const parts = {};
  for (const side of ['L', 'R']) {
    const f = new THREE.Group();
    let wi = 0;
    for (const z of [-0.088, 0.088]) {
      for (const x of [-0.066, 0.066]) {
        f.add(K.m(gold ? wheel : paint(wheel, cols[wi]), gold ? M('', '', wheelTone[wi]) : plastic, { pos: [x, WY, z], rot: [0, 0, Math.PI / 2] }));
        f.add(K.m(gold ? hub : paint(hub, '#F4F1E8'), gold ? M('', '', 'light') : plastic, { pos: [x, WY, z] }));
        wi++;
      }
      f.add(K.m(new THREE.CylinderGeometry(0.006, 0.006, 0.17, 6).rotateZ(Math.PI / 2), chrome, { pos: [0, WY, z] }));
      f.add(K.m(K.box(0.05, 0.04, 0.036, 0.01), chrome, { pos: [0, -0.036, z] }));
    }
    // pink enamel plate (the "grown" chassis), purple heel strap, big pink toe stop
    f.add(K.m(gold ? K.box(0.105, 0.02, 0.28, 0.008) : paint(K.box(0.105, 0.02, 0.28, 0.008), '#FF5FA2'), gold ? M('', '', 'mid') : plastic, { pos: [0, -0.01, 0] }));
    const cup = new THREE.TorusGeometry(0.066, 0.013, 5, 14, Math.PI).rotateX(Math.PI / 2);
    cup.scale(1.05, 1, 0.8);
    f.add(K.m(gold ? cup : paint(cup, '#8A4ADC'), gold ? M('', '', 'deep') : plastic, { pos: [0, 0.014, 0.075] }));
    const stop = K.lathe([[0, 0], [0.032, 0], [0.037, 0.009], [0.037, 0.045], [0.029, 0.054], [0, 0.054]], { seg: 12, round: 0.006, steps: 1 });
    f.add(span(K.m(gold ? stop : paint(stop, '#FF4F9A'), gold ? M('', '', 'rose') : plastic), [0, -0.02, -0.13], [0, -0.08, -0.168]));
    f.position.set(side === 'L' ? -0.13 : 0.13, 0.12, 0);
    parts['foot' + side] = f;
    g.add(f);
  }
  g.userData.fit = { footL: { anchor: 'shoe sole center, plate top at y=0', lift: 0.118, note: 'wheels hang 0.118 m below the sole: raise the hero by lift while worn (or accept a little clipping)' } };
  g.userData.perk = 'roller_boogie';
  return finishCostume(game, g, parts);
}
registerProp('costume_skates', (game) => buildSkates(game, false), costumeMeta('roller_boogie', 'feet', false, 'retro roller-skate wheel sets per foot: 4 colored wheels + pink toe stop'));
registerProp('costume_skates_gold', (game) => buildSkates(game, true), costumeMeta('roller_boogie', 'feet', true, 'gold-leaf roller-skate wheel sets'));

// ------------------------------------------------------------------ Double Vision: giant striped toothbrush (back)
function brushTex(gold) {
  return texC(`brush.${gold ? 'g' : 'n'}`, 256, 512, (ctx, w, h) => {
    const cols = gold ? ['#E8C06A', '#FFF4D6', '#B98232'] : ['#E23B3B', '#F7F3EA', '#2F5BD3'];
    const P = 256 / 2, bw = P / 3;
    for (let k = -6; k < 12; k++) cols.forEach((c, b) => {
      const y = k * P + b * bw;
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y + w * 0.9); ctx.lineTo(w, y + w * 0.9 + bw + 0.8); ctx.lineTo(0, y + bw + 0.8); ctx.closePath();
      ctx.fillStyle = c; ctx.fill();
    });
  }, { repeat: true });
}
function buildToothbrush(game, gold) {
  const id = `costume_toothbrush${gold ? '_gold' : ''}`;
  const g = K.prop(id);
  const M = cmat(game, gold);
  const handleM = M('plastic', '#ffffff', 'mid', { goldMap: brushTex(true), normal: { map: brushTex(false), rough: 0.25 } });
  const headM = M('plastic', '#F7F3EA', 'light', { normal: { rough: 0.25 } });
  const bristleM = gold ? M('', '', 'light') : pm(game, 'plastic', '#ffffff', { rough: 0.45 });
  const leather = M('vinyl', '#7A4A2A', 'deep', { normal: { map: K.tex.pebble('#7A4A2A') } });
  const brass = gold ? M('', '', 'light') : pm(game, 'brass', '#C8963C');
  const back = new THREE.Group();
  // handle along +y (grip bulge, thinner neck), bristle head at the top
  const rings = [];
  const L = 0.66;
  for (let i = 0; i <= 16; i++) {
    const t = i / 16, grip = 1 + 0.28 * Math.sin(Math.PI * clamp(t / 0.7, 0, 1)) - 0.25 * smoothstep(t, 0.7, 0.95);
    rings.push([0.038 * grip, 0.021 * grip, -L / 2 + t * L, 3]);
  }
  const hg = loft(rings, 20);
  K.uvScale(hg, 1, 2.2);
  back.add(K.m(hg, handleM));
  back.add(K.m(new THREE.SphereGeometry(1, 16, 10).scale(0.038, 0.03, 0.021), handleM, { pos: [0, -L / 2, 0] }));
  // head: rounded paddle + bristle tufts facing outward (+z, away from the hero's back)
  const headY = L / 2 + 0.09;
  back.add(K.m(K.box(0.075, 0.2, 0.035, 0.016), headM, { pos: [0, headY, 0] }));
  const tuft = new THREE.CylinderGeometry(0.009, 0.0095, 0.07, 6).rotateX(Math.PI / 2);
  for (let r = 0; r < 7; r++) for (let c = 0; c < 3; c++) {
    const geo = gold ? tuft : paint(tuft, r % 3 === 1 ? '#5FE3FF' : '#FFFFFF');
    back.add(K.m(geo, bristleM, { pos: [(c - 1) * 0.022, headY - 0.078 + r * 0.026, 0.05 + (r % 2) * 0.004] }));
  }
  // leather holster: back plate + two strap loops around the handle, brass rivets
  const patch = K.extrude(K.roundRect(0.13, 0.36, 0.06), 0.02, { bevel: 0.007, curveSeg: 6 });
  back.add(K.m(patch, leather, { pos: [0, -0.02, -0.036] }));
  for (const y of [-0.15, 0.11]) {
    const band = new THREE.TorusGeometry(1, 0.34, 5, 18).rotateX(Math.PI / 2);
    band.scale(0.047, 0.045, 0.03);
    back.add(K.m(band, leather, { pos: [0, y, -0.006] }));
    for (const sx of [-1, 1]) back.add(K.m(new THREE.SphereGeometry(0.008, 8, 6), brass, { pos: [sx * 0.05, y, -0.028] }));
  }
  // the slot-space pose lives on an inner group (bristles over the hero's LEFT shoulder = -x, 0.05 m behind the slot);
  // the part itself only carries the gallery transform (turned to show its outside), which the game resets
  const brush = new THREE.Group();
  brush.add(...back.children);
  brush.rotation.z = 0.62;
  brush.position.z = 0.05;
  back.add(brush);
  back.position.set(0, 0.55, 0);
  back.rotation.y = Math.PI;
  g.userData.fit = { back: { anchor: 'back slot (chest back surface)', note: 'diagonal, bristles over the left shoulder, handle toward the right hip, sits 0.05 m behind the slot' } };
  g.userData.perk = 'double_vision';
  return finishCostume(game, g, { back });
}
registerProp('costume_toothbrush', (game) => buildToothbrush(game, false), costumeMeta('double_vision', 'back', false, 'giant red-white-blue striped toothbrush holstered diagonally on the back'));
registerProp('costume_toothbrush_gold', (game) => buildToothbrush(game, true), costumeMeta('double_vision', 'back', true, 'gold-leaf toothbrush'));

// ------------------------------------------------------------------ Replay-Ade: terry wristbands + whistle lanyard
function terryTex(gold) {
  return K.tex.canvas(`sp.terry.${gold ? 'g' : 'n'}`, 256, 128, (ctx, w, h, rand) => {
    const base = gold ? '#F4E2B0' : '#F4C81E', stripe = gold ? '#B98232' : '#2F5BD3';
    ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = stripe; ctx.fillRect(0, h * 0.28, w, h * 0.12); ctx.fillRect(0, h * 0.6, w, h * 0.12);
    for (let i = 0; i < 3200; i++) {
      ctx.fillStyle = rand() < 0.5 ? 'rgba(255,255,255,0.25)' : 'rgba(80,50,0,0.18)';
      ctx.beginPath(); ctx.arc(rand() * w, rand() * h, 0.8 + rand() * 1.3, 0, TAU); ctx.fill();
    }
  });
}
function buildWristbands(game, gold) {
  const id = `costume_wristbands${gold ? '_gold' : ''}`;
  const g = K.prop(id);
  const M = cmat(game, gold);
  const terry = M('fabric', '#ffffff', 'mid', { goldMap: terryTex(true), normal: { map: terryTex(false), rim: 0.4 } });
  const cord = M('fabric', '#F4C81E', 'light', { normal: { rim: 0.3 } });
  const chrome = gold ? M('', '', 'light') : pm(game, 'chrome', '#A8B0BA');
  const parts = {};
  const band = lathe2([[0.058, -0.04], [0.07, -0.042], [0.077, -0.032], [0.079, 0], [0.077, 0.032], [0.07, 0.042], [0.058, 0.04], [0.056, 0], [0.058, -0.04]], { seg: 24, round: 0.008, steps: 1 });
  K.uvScale(band, 3, 1);
  for (const side of ['L', 'R']) {
    const w = new THREE.Group();
    w.add(K.m(band, terry));
    w.position.set(side === 'L' ? -0.2 : 0.2, 0.06, 0.1);
    parts['wrist' + side] = w;
    g.add(w);
  }
  // lanyard: loop around the neck, V down to the whistle on the chest
  const neck = new THREE.Group();
  const pts = [[0, -0.155, -0.13], [-0.05, -0.08, -0.12], [-0.085, 0.0, -0.06], [-0.085, 0.02, 0.02], [-0.04, 0.025, 0.075], [0.04, 0.025, 0.075], [0.085, 0.02, 0.02], [0.085, 0.0, -0.06], [0.05, -0.08, -0.12]];
  neck.add(K.m(K.tube(pts, 0.007, { seg: 40, radial: 5, closed: true }), cord));
  const wh = new THREE.Group();
  wh.position.set(0, -0.19, -0.14);
  wh.add(K.m(new THREE.TorusGeometry(0.012, 0.0035, 5, 12), chrome, { pos: [0, 0.03, 0] }));
  wh.add(K.m(new THREE.CylinderGeometry(0.024, 0.024, 0.042, 16).rotateZ(Math.PI / 2), chrome, { pos: [0, 0, 0] }));
  wh.add(K.m(K.box(0.042, 0.014, 0.04, 0.005), chrome, { pos: [0, 0.018, -0.02] }));
  wh.add(K.m(K.box(0.036, 0.012, 0.035, 0.005), chrome, { pos: [0, 0.02, -0.055] }));
  wh.add(K.m(K.box(0.014, 0.012, 0.004, 0.002), pm(game, 'plastic', '#2A2230'), { pos: [0, 0.02, -0.0735] }));
  wh.rotation.set(-0.3, 0.3, 0);
  neck.add(wh);
  neck.position.set(0, 0.34, 0);
  parts.neck = neck;
  g.add(neck);
  g.userData.fit = { wristL: { anchor: 'wrist slot', innerRadius: 0.056 }, neck: { anchor: 'neck slot', loopRadius: 0.085, note: 'whistle hangs on the chest ~0.19 m below, 0.14 m forward' } };
  g.userData.perk = 'replay_ade';
  return finishCostume(game, g, parts);
}
registerProp('costume_wristbands', (game) => buildWristbands(game, false), costumeMeta('replay_ade', 'wrists+neck', false, 'yellow/blue terry wristbands (L+R) + chrome referee whistle on a yellow lanyard'));
registerProp('costume_wristbands_gold', (game) => buildWristbands(game, true), costumeMeta('replay_ade', 'wrists+neck', true, 'gold-leaf wristbands + whistle'));

// =============================================================================================== SET PIECES
// Placeable alone (room dressers) and used by the sponsor set prefab. Environment materials (they desaturate
// before Sign-On like the rest of the station). Each registers the materials the game swaps for power:
// userData.power = { on:{...}, off:{...} } + the meshes in userData.parts (see setTally / setSponsorSetPower).
function tallyMats(game) {
  return { on: K.glow(game, '#FF2A20', 1.9), off: K.mat(game, 'lacquer', '#5A1A1E') };
}
function badgeTex() {
  return texC('badge13', 128, 128, (ctx, w, h) => {
    ctx.beginPath(); ctx.arc(64, 64, 60, 0, TAU); ctx.fillStyle = '#E23B3B'; ctx.fill();
    ctx.beginPath(); ctx.arc(64, 64, 48, 0, TAU); ctx.fillStyle = '#2F5BD3'; ctx.fill();
    text(ctx, '13', 64, 68, { fam: FONT.sign, px: 52, fill: '#F4F1E8' });
  });
}
function camDecalTex() {
  return texC('camdecal', 256, 64, (ctx, w, h) => {
    ctx.fillStyle = '#2F5BD3'; rrp(ctx, 0, 0, w, h, 14); ctx.fill();
    ctx.fillStyle = '#E23B3B'; ctx.fillRect(0, h - 12, w, 6);
    text(ctx, 'WZTV', 80, 30, { fam: FONT.sign, px: 34, fill: '#F4F1E8' });
    text(ctx, 'CAMERA 3', 188, 30, { fam: FONT.round, px: 22, fill: '#FFD23A' });
  });
}

// ------------------------------------------------------------------ shared set-piece materials (one instance each)
function setMats(game) {
  return {
    dark: K.mat(game, 'plastic', '#2E2A34', { rough: 0.45 }),
    metal: K.mat(game, 'metal', '#8A919C', { rough: 0.4 }),
    chrome: K.mat(game, 'metal', '#A8B0BA', { rough: 0.3 }),
    cream: K.mat(game, 'plastic', '#D9D2C2', { rough: 0.4 }),
    blue: K.mat(game, 'plastic', '#2F5BD3', { rough: 0.4 }),
    glass: K.mat(game, 'crt', '#1A2A3A'),
  };
}
// plain (unbevelled, cheap) cylinder with its base at y=0, for thin rods/legs where a bevel is invisible
const pcyl = (rt, rb, h, seg = 8) => new THREE.CylinderGeometry(rt, rb, h, seg).translate(0, h / 2, 0);
function prod(r, a, b, mat, seg = 6) { return span(K.m(pcyl(r, r, V3(a).distanceTo(V3(b)), seg), mat), a, b); }

// ------------------------------------------------------------------ 1970s studio pedestal camera (lens toward -z)
function buildPedestalCamera(game) {
  const g = new THREE.Group();
  const T = tallyMats(game);
  const M = setMats(game);
  const decal = K.mat(game, 'plastic', '#ffffff', { map: camDecalTex() });
  const badge = K.mat(game, 'plastic', '#ffffff', { map: badgeTex() });
  // skirted pedestal base on three casters
  g.add(K.m(K.lathe([[0, 0], [0.4, 0], [0.42, 0.03], [0.4, 0.15], [0.33, 0.19], [0.12, 0.22], [0, 0.22]], { seg: 20, round: 0.02, steps: 1 }), M.dark, { pos: [0, 0.05, 0] }));
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + Math.PI / 6, cx = Math.sin(a) * 0.3, cz = Math.cos(a) * 0.3;
    g.add(K.m(new THREE.CylinderGeometry(0.045, 0.045, 0.035, 10).rotateZ(Math.PI / 2), M.dark, { pos: [cx, 0.045, cz], rot: [0, a, 0] }));
    g.add(K.m(K.box(0.06, 0.05, 0.05, 0.012), M.metal, { pos: [cx, 0.07, cz], rot: [0, a, 0] }));
  }
  g.add(K.m(flatTorus(0.405, 0.02, 5, 28), M.metal, { pos: [0, 0.2, 0] }));
  // telescoping column + steering ring
  g.add(K.m(pcyl(0.09, 0.1, 0.46, 16), M.blue, { pos: [0, 0.26, 0] }));
  g.add(K.m(flatTorus(0.092, 0.014, 5, 16), M.metal, { pos: [0, 0.72, 0] }));
  g.add(K.m(pcyl(0.068, 0.068, 0.42, 14), M.metal, { pos: [0, 0.72, 0] }));
  g.add(K.m(flatTorus(0.28, 0.024, 6, 28), M.metal, { pos: [0, 0.8, 0] }));
  for (let i = 0; i < 3; i++) { const a = (i / 3) * TAU; g.add(prod(0.012, [0, 0.8, 0], [Math.sin(a) * 0.27, 0.8, Math.cos(a) * 0.27], M.metal)); }
  // pan head: parts.head pans (the "shakes its head" gag), pivot on the column axis
  const head = new THREE.Group();
  head.position.y = 1.14;
  head.userData.noMerge = true;
  head.add(K.m(pcyl(0.11, 0.12, 0.09, 16), M.dark, { pos: [0, -0.02, 0] }));
  head.add(K.m(K.box(0.34, 0.04, 0.44, 0.012), M.metal, { pos: [0, 0.09, 0] }));
  const by = 0.32;
  head.add(K.m(K.box(0.42, 0.4, 0.64, 0.07), M.cream, { pos: [0, by, 0.02] }));
  for (const s of [-1, 1]) {
    head.add(K.m(K.box(0.02, 0.29, 0.5, 0.008), M.blue, { pos: [s * 0.212, by - 0.01, 0.04] }));
    const d = new THREE.PlaneGeometry(0.4, 0.1).rotateY(s < 0 ? -Math.PI / 2 : Math.PI / 2);
    head.add(K.m(d, decal, { pos: [s * 0.224, by + 0.05, 0.04] }));
    const b = new THREE.CircleGeometry(0.055, 20).rotateY(s < 0 ? -Math.PI / 2 : Math.PI / 2);
    head.add(K.m(b, badge, { pos: [s * 0.224, by - 0.08, s < 0 ? -0.12 : 0.2] }));
  }
  head.add(K.m(K.box(0.24, 0.012, 0.16, 0.005), M.dark, { pos: [0, by + 0.203, 0.14] }));
  // big zoom lens: barrel, zoom + focus rings, flared hood, dark glass
  const lz = -0.3, ly = by - 0.02;
  head.add(K.m(new THREE.CylinderGeometry(0.125, 0.125, 0.14, 20).rotateX(Math.PI / 2), M.dark, { pos: [0, ly, lz] }));
  head.add(K.m(new THREE.CylinderGeometry(0.105, 0.112, 0.26, 20).rotateX(Math.PI / 2), M.dark, { pos: [0, ly, lz - 0.18] }));
  for (const z of [-0.1, -0.22]) head.add(K.m(new THREE.TorusGeometry(0.114, 0.014, 5, 20), M.metal, { pos: [0, ly, lz + z] }));
  head.add(K.m(K.taper(K.box(0.3, 0.25, 0.14, 0.035), { axis: 'z', k: 0.64 }), M.dark, { pos: [0, ly, lz - 0.37] }));
  head.add(K.m(new THREE.CircleGeometry(0.09, 20).rotateY(Math.PI), M.glass, { pos: [0, ly, lz - 0.312] }));
  // viewfinder on the rear top, rubber hood toward the operator (+z)
  head.add(K.m(K.box(0.3, 0.22, 0.3, 0.045), M.cream, { pos: [0, by + 0.3, 0.1] }));
  head.add(K.m(K.taper(K.box(0.26, 0.19, 0.16, 0.035), { axis: 'z', k: 1.25 }), M.dark, { pos: [0, by + 0.3, 0.32] }));
  // tally lights (parts.tally): big dome on the front top + a lamp on the viewfinder
  head.add(K.m(pcyl(0.05, 0.055, 0.025, 14), M.dark, { pos: [0, by + 0.2, -0.2] }));
  const tallyA = K.m(new THREE.SphereGeometry(0.046, 14, 8, 0, TAU, 0, Math.PI / 2), T.on, { pos: [0, by + 0.224, -0.2], name: 'tally', cast: false });
  const tallyB = K.m(new THREE.SphereGeometry(0.026, 10, 8), T.on, { pos: [0.12, by + 0.42, 0.18], name: 'tally', cast: false });
  for (const t of [tallyA, tallyB]) { t.userData.noMerge = true; t.userData.noAO = true; head.add(t); }
  // pan bars back to the operator
  for (const s of [-1, 1]) {
    head.add(K.m(K.tube([[s * 0.13, 0.09, 0.16], [s * 0.21, 0.04, 0.46], [s * 0.27, -0.06, 0.7]], 0.015, { seg: 8, radial: 5 }), M.metal));
    head.add(span(K.m(pcyl(0.026, 0.026, 0.15, 10), M.dark), [s * 0.25, -0.04, 0.64], [s * 0.28, -0.08, 0.78]));
  }
  g.add(head);
  g.add(K.m(K.tube([[0, 1.36, 0.34], [0.06, 1.1, 0.42], [0.14, 0.6, 0.38], [0.3, 0.1, 0.36], [0.55, 0.025, 0.55], [0.95, 0.02, 0.95]], 0.019, { seg: 14, radial: 5 }), M.dark));
  return { g, head, tallies: [tallyA, tallyB], T };
}
registerProp('sponsor_camera_pedestal', (game, opts = {}) => {
  const g = K.prop('sponsor_camera_pedestal');
  const { g: cam, head, tallies, T } = buildPedestalCamera(game);
  g.add(cam);
  if (opts.lit === false) tallies.forEach((t) => { t.material = T.off; });
  K.bakeAO(g, {});
  K.merge(head);
  g.userData.parts = { head, tally: tallies };
  g.userData.power = { on: { tally: T.on }, off: { tally: T.off } };
  g.userData.colliders = [{ min: [-0.44, 0, -0.44], max: [0.44, 1.85, 0.8] }];
  g.userData.anchors = { lens: [0, 1.44, -0.7] };
  return K.finish(game, g, { ao: false });
}, { category: 'sponsors', tags: ['camera', 'set_piece', 'tally'], size: [0.9, 1.85, 1.5], hero: true, desc: '70s studio pedestal camera: skirted base, cream/WZTV-blue body, big zoom lens, tally lights (parts.head pans, parts.tally)' });

// ------------------------------------------------------------------ portable ENG camera on a wooden tripod + battery belt
function buildEngCamera(game) {
  const g = new THREE.Group();
  const T = tallyMats(game);
  const M = setMats(game);
  const wood = K.mat(game, 'teak', '#ffffff', { map: K.tex.wood(PAL.teak, { dark: 0.35 }) });
  const grey = K.mat(game, 'plastic', '#A7ADB6', { rough: 0.4 });
  const leather = K.mat(game, 'vinyl', '#ffffff', { map: K.tex.pebble('#5A3A22') });
  const decal = K.mat(game, 'plastic', '#ffffff', { map: K.tex.label('EYEWITNESS 13', { bg: '#F4F1E8', fg: '#E23B3B', accent: '#2F5BD3', w: 512, h: 96, border: 0.1, wear: 0.15 }) });
  const topY = 1.16, legAt = (a, y) => { const t = (y - 0.02) / (topY - 0.06); const r = lerp(0.5, 0.06, t); return [Math.sin(a) * r, y, Math.cos(a) * r]; };
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + Math.PI / 3;
    g.add(prod(0.024, legAt(a, 0.02), legAt(a, topY - 0.04), wood, 8));
    g.add(K.m(K.box(0.055, 0.05, 0.055, 0.012), M.metal, { pos: legAt(a, 0.62) }));
    g.add(K.m(pcyl(0.022, 0.028, 0.04, 8), M.dark, { pos: legAt(a, 0.0) }));
    g.add(prod(0.008, legAt(a, 0.3), [0, 0.34, 0], M.metal));
  }
  g.add(K.m(pcyl(0.03, 0.03, 0.03, 10), M.metal, { pos: [0, 0.33, 0] }));
  g.add(K.m(pcyl(0.075, 0.085, 0.06, 16), M.metal, { pos: [0, topY - 0.06, 0] }));
  const head = new THREE.Group();
  head.position.y = topY;
  head.userData.noMerge = true;
  head.add(K.m(pcyl(0.065, 0.075, 0.08, 14), M.dark));
  head.add(K.m(K.tube([[0.05, 0.05, 0.08], [0.1, 0.02, 0.3], [0.13, -0.06, 0.5]], 0.013, { seg: 8, radial: 5 }), M.metal));
  const by = 0.22;
  head.add(K.m(K.box(0.19, 0.26, 0.44, 0.04), grey, { pos: [0, by, 0.02] }));
  head.add(K.m(K.cushion(0.13, 0.05, 0.24, { puff: 0.01 }), M.dark, { pos: [0, by - 0.15, 0.08] }));
  head.add(K.m(K.box(0.004, 0.06, 0.3, 0.002), decal, { pos: [0.097, by + 0.03, 0.02] }));
  head.add(K.m(new THREE.CylinderGeometry(0.07, 0.072, 0.3, 18).rotateX(Math.PI / 2), M.dark, { pos: [0, by - 0.02, -0.33] }));
  head.add(K.m(new THREE.TorusGeometry(0.074, 0.011, 5, 18), M.metal, { pos: [0, by - 0.02, -0.38] }));
  head.add(K.m(K.taper(K.box(0.18, 0.16, 0.09, 0.025), { axis: 'z', k: 0.7 }), M.dark, { pos: [0, by - 0.02, -0.51] }));
  head.add(K.m(new THREE.CircleGeometry(0.06, 18).rotateY(Math.PI), M.glass, { pos: [0, by - 0.02, -0.49] }));
  head.add(K.m(K.box(0.055, 0.11, 0.13, 0.015), M.dark, { pos: [0.095, by - 0.06, -0.28] }));
  head.add(K.m(K.tube([[0, by + 0.13, 0.18], [0, by + 0.21, 0.1], [0, by + 0.21, -0.1], [0, by + 0.14, -0.16]], 0.017, { seg: 10, radial: 5 }), M.dark));
  head.add(K.m(new THREE.CylinderGeometry(0.038, 0.044, 0.22, 14).rotateX(Math.PI / 2), M.dark, { pos: [-0.135, by + 0.08, -0.02] }));
  head.add(K.m(pcyl(0.046, 0.04, 0.04, 12).rotateX(Math.PI / 2), M.dark, { pos: [-0.135, by + 0.08, 0.09] }));
  head.add(K.m(pcyl(0.03, 0.034, 0.02, 12), M.dark, { pos: [0, by + 0.13, -0.13] }));
  const tally = K.m(new THREE.SphereGeometry(0.028, 12, 8, 0, TAU, 0, Math.PI / 2), T.on, { pos: [0, by + 0.148, -0.13], name: 'tally', cast: false });
  tally.userData.noMerge = true; tally.userData.noAO = true;
  head.add(tally);
  g.add(head);
  // battery belt slung over the front-right leg (U shape hanging both sides), coiled cable to the camera
  const a0 = Math.PI / 3, hang = legAt(a0, 0.8);
  const belt = new THREE.Group();
  belt.position.set(hang[0], hang[1], hang[2]);
  belt.rotation.y = a0 + Math.PI / 2;
  belt.add(K.m(K.tube([[-0.16, -0.36, 0.0], [-0.1, -0.08, 0.0], [0, 0.03, 0.0], [0.1, -0.08, 0.0], [0.16, -0.36, 0.0]], 0.022, { seg: 16, radial: 5 }), leather));
  for (let i = 0; i < 4; i++) {
    const s = i < 2 ? -1 : 1, k = i % 2;
    belt.add(K.m(K.box(0.08, 0.1, 0.055, 0.012), leather, { pos: [s * (0.115 + k * 0.035), -0.14 - k * 0.14, 0.035], rot: [0, 0, s * (0.35 - k * 0.15)] }));
  }
  g.add(belt);
  g.add(K.m(K.tube([[hang[0] + 0.05, 0.46, hang[2]], [0.16, 0.8, 0.22], [0.04, 1.2, 0.24], [0.0, 1.36, 0.22]], 0.011, { seg: 14, radial: 5 }), M.dark));
  return { g, head, tallies: [tally], T };
}
registerProp('sponsor_camera_eng', (game, opts = {}) => {
  const g = K.prop('sponsor_camera_eng');
  const { g: cam, head, tallies, T } = buildEngCamera(game);
  g.add(cam);
  if (opts.lit === false) tallies.forEach((t) => { t.material = T.off; });
  K.bakeAO(g, {});
  K.merge(head);
  g.userData.parts = { head, tally: tallies };
  g.userData.power = { on: { tally: T.on }, off: { tally: T.off } };
  g.userData.colliders = [{ min: [-0.45, 0, -0.45], max: [0.45, 1.6, 0.45] }];
  g.userData.anchors = { lens: [0, 1.36, -0.56] };
  return K.finish(game, g, { ao: false });
}, { category: 'sponsors', tags: ['camera', 'set_piece', 'tally', 'eng'], size: [1, 1.6, 1.1], desc: 'portable ENG news camera on a wooden tripod with a battery belt (Replay-Ade set, parts.head, parts.tally)' , hero: true });

// ------------------------------------------------------------------ softbox light on a stand (diffuser faces -z)
function softTex() {
  return K.tex.canvas('sp.softbox', 128, 128, (ctx, w, h) => {
    const gr = ctx.createRadialGradient(w / 2, h / 2, 4, w / 2, h / 2, w * 0.72);
    gr.addColorStop(0, '#FFFFFF'); gr.addColorStop(0.55, '#F2E8D8'); gr.addColorStop(1, '#A89C8C');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h);
  }, { repeat: false });
}
function softboxMats(game) { return { on: K.glow(game, '#FFF1D8', 0.95, { map: softTex() }), off: K.mat(game, 'fabric', '#D8D2C8', { rim: 0.1 }) }; }
function buildSoftbox(game, o = {}) {
  const g = new THREE.Group();
  const M = setMats(game);
  const cloth = K.mat(game, 'fabric', '#1E1A24', { rim: 0.3 });
  const mats = softboxMats(game);
  const h = o.height ?? 1.75;
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.4;
    g.add(prod(0.012, [Math.sin(a) * 0.36, 0.01, Math.cos(a) * 0.36], [Math.sin(a) * 0.03, 0.62, Math.cos(a) * 0.03], M.metal));
    g.add(K.m(pcyl(0.018, 0.022, 0.025, 8), M.dark, { pos: [Math.sin(a) * 0.36, 0, Math.cos(a) * 0.36] }));
  }
  g.add(K.m(pcyl(0.035, 0.04, 0.08, 12), M.dark, { pos: [0, 0.58, 0] }));
  g.add(K.m(pcyl(0.018, 0.018, h - 0.6, 10), M.metal, { pos: [0, 0.6, 0] }));
  g.add(K.m(pcyl(0.026, 0.026, 0.05, 10), M.dark, { pos: [0, 1.05, 0] }));
  const box = new THREE.Group();
  box.position.y = h;
  box.rotation.x = o.tilt ?? 0.3;
  for (const s of [-1, 1]) g.add(K.m(K.box(0.03, 0.26, 0.03, 0.01), M.dark, { pos: [s * 0.35, h - 0.1, 0] }));
  g.add(K.m(K.box(0.73, 0.03, 0.03, 0.01), M.dark, { pos: [0, h - 0.22, 0] }));
  box.add(K.m(K.taper(K.box(0.66, 0.5, 0.36, 0.04), { axis: 'z', k: 0.38 }), cloth, { pos: [0, 0, 0.12] }));
  const diff = K.m(new THREE.PlaneGeometry(0.58, 0.42).rotateY(Math.PI), o.lit === false ? mats.off : mats.on, { pos: [0, 0, -0.066], name: 'diffuser', cast: false });
  diff.userData.noMerge = true; diff.userData.noAO = true; diff.userData.noOcclude = true;
  box.add(diff);
  g.add(box);
  return { g, box, diff, mats };
}
registerProp('sponsor_softbox', (game, opts = {}) => {
  const g = K.prop('sponsor_softbox');
  const { g: sb, box, diff, mats } = buildSoftbox(game, opts);
  g.add(sb);
  g.userData.parts = { head: box, diffuser: [diff] };
  g.userData.power = { on: { soft: mats.on }, off: { soft: mats.off } };
  g.userData.lightAnchors = opts.lit === false ? [] : [{ pos: [0, 1.6, -0.5], color: '#FFE8C8', intensity: 2.4, distance: 5.5 }];
  g.userData.colliders = [{ min: [-0.3, 0, -0.3], max: [0.3, 2.1, 0.3] }];
  return K.finish(game, g);
}, { category: 'sponsors', tags: ['light', 'set_piece', 'softbox'], size: [0.75, 2.1, 0.75], desc: 'studio softbox on a tripod stand, glowing diffuser (power swap via userData.power)' });

// ------------------------------------------------------------------ small walnut studio speaker (grille faces -z)
function grilleTex() {
  return K.tex.canvas('sp.grille', 256, 256, (ctx, w, h) => {
    ctx.fillStyle = '#C86A2E'; ctx.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 3) { ctx.fillStyle = y % 6 ? 'rgba(90,40,10,0.28)' : 'rgba(255,200,150,0.18)'; ctx.fillRect(0, y, w, 1.5); }
    for (let x = 0; x < w; x += 3) { ctx.fillStyle = 'rgba(90,40,10,0.18)'; ctx.fillRect(x, 0, 1, h); }
    ctx.fillStyle = '#C8963C'; rrp(ctx, w / 2 - 36, h - 38, 72, 18, 4); ctx.fill();
    text(ctx, 'WZTV', w / 2, h - 29, { fam: FONT.sign, px: 13, fill: '#4A2A10' });
  });
}
function buildSpeaker(game) {
  const g = new THREE.Group();
  const M = setMats(game);
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.4 }) });
  const grille = K.mat(game, 'fabric', '#ffffff', { map: grilleTex(), rim: 0.12 });
  g.add(K.m(K.box(0.4, 0.56, 0.3, 0.035, { uv: 2.5 }), walnut, { pos: [0, 0.34, 0] }));
  g.add(K.m(K.cushion(0.33, 0.47, 0.03, { puff: 0.006, seg: [4, 5, 1] }), grille, { pos: [0, 0.34, -0.15] }));
  for (const x of [-0.14, 0.14]) for (const z of [-0.1, 0.1]) g.add(K.m(pcyl(0.02, 0.026, 0.06, 8), M.dark, { pos: [x, 0, z] }));
  g.add(K.m(K.tube([[0, 0.3, 0.15], [0.05, 0.1, 0.25], [0.3, 0.02, 0.4]], 0.008, { seg: 8, radial: 4 }), M.dark));
  return g;
}
registerProp('sponsor_speaker', (game) => {
  const g = K.prop('sponsor_speaker');
  g.add(buildSpeaker(game));
  g.userData.anchors = { sound: [0, 0.34, -0.2] };
  return K.finish(game, g);
}, { category: 'sponsors', tags: ['speaker', 'set_piece', 'audio'], size: [0.4, 0.62, 0.3], desc: 'small walnut studio speaker with orange grille cloth (sound anchor)' });

// =============================================================================================== SET ART
// Painted backdrop flats (the product's world), riser floor tops and wing flats, one canvas each per brand.
function cloud(ctx, x, y, s, col = '#FFFFFF') {
  ctx.fillStyle = col;
  for (const [dx, dy, r] of [[-38, 6, 22], [-14, -8, 28], [14, -12, 30], [40, 2, 22], [0, 10, 26]]) { ctx.beginPath(); ctx.arc(x + dx * s, y + dy * s, r * s, 0, TAU); ctx.fill(); }
}
function halftone(ctx, x0, y0, w, h, col, step, fn) {
  ctx.fillStyle = col;
  for (let y = y0; y < y0 + h; y += step) for (let x = x0; x < x0 + w; x += step) {
    const r = fn((x - x0) / w, (y - y0) / h) * step * 0.5;
    if (r > 0.3) { ctx.beginPath(); ctx.arc(x + step / 2, y + step / 2, r, 0, TAU); ctx.fill(); }
  }
}
function frameBorder(ctx, w, h, col, lw = 10) { ctx.strokeStyle = col; ctx.lineWidth = lw; ctx.strokeRect(lw / 2, lw / 2, w - lw, h - lw); }

const BACKDROP = {
  // "Sports Final": stadium under a big sky, scoreboard, bunting, striped field
  replay_ade(ctx, w, h, rand) {
    ctx.fillStyle = lin(ctx, 0, 0, 0, h * 0.5, ['#2F5BD3', '#6E9CF0', '#CFE2FF']); ctx.fillRect(0, 0, w, h);
    ctx.save(); ctx.globalAlpha = 0.16; rays(ctx, w / 2, h * 0.34, w, 28, '#FFFFFF'); ctx.restore();
    cloud(ctx, 110, 150, 1.1); cloud(ctx, 660, 120, 1.3); cloud(ctx, 560, 200, 0.7);
    // light towers
    for (const x of [64, w - 64]) {
      ctx.fillStyle = '#5A6A8A'; ctx.fillRect(x - 5, 110, 10, 200);
      rrp(ctx, x - 44, 70, 88, 56, 8); ctx.fillStyle = '#3A4460'; ctx.fill();
      for (let i = 0; i < 4; i++) for (let j = 0; j < 2; j++) { ctx.beginPath(); ctx.arc(x - 30 + i * 20, 86 + j * 22, 8, 0, TAU); ctx.fillStyle = '#FFF4C8'; ctx.fill(); }
    }
    // stands with a crowd of dots
    const sy0 = h * 0.4, sy1 = h * 0.61;
    ctx.fillStyle = '#23306A';
    ctx.beginPath(); ctx.moveTo(0, sy1); ctx.lineTo(0, sy0 + 20); ctx.quadraticCurveTo(w / 2, sy0 - 40, w, sy0 + 20); ctx.lineTo(w, sy1); ctx.closePath(); ctx.fill();
    const crowd = ['#E23B3B', '#FFD23A', '#F4F1E8', '#E3662B', '#52D24A', '#FF5FA2', '#7FE7FF'];
    for (let y = sy0; y < sy1 - 12; y += 11) for (let x = 6; x < w; x += 11) {
      const top = sy0 + 20 - 60 * Math.sin((x / w) * Math.PI) * 0.5;
      if (y < top) continue;
      ctx.fillStyle = crowd[Math.floor(rand() * crowd.length)]; ctx.beginPath(); ctx.arc(x + rand() * 3, y + rand() * 3, 3.6, 0, TAU); ctx.fill();
    }
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, sy1 - 10, w, 8);
    ctx.fillStyle = '#1B2F7A'; ctx.fillRect(0, sy1 - 2, w, 6);
    // scoreboard
    const bx = w / 2 - 150, by = 34;
    rrp(ctx, bx, by, 300, 150, 14); ctx.fillStyle = '#1E1A2E'; ctx.fill(); ctx.lineWidth = 8; ctx.strokeStyle = '#FFD23A'; ctx.stroke();
    for (let i = 0; i < 24; i++) { const x = bx + 14 + i * 11.6; for (const y of [by + 8, by + 142]) { ctx.beginPath(); ctx.arc(x, y, 3, 0, TAU); ctx.fillStyle = i % 2 ? '#FFF4C8' : '#FFB347'; ctx.fill(); } }
    text(ctx, 'REPLAY', w / 2, by + 44, { fam: FONT.sign, px: 44, fill: '#FFD23A' });
    rewindP(ctx, w / 2 - 118, by + 44, 26); ctx.fillStyle = '#FFD23A'; ctx.fill();
    rewindP(ctx, w / 2 + 128, by + 44, 26); ctx.fill();
    text(ctx, 'HOME', w / 2 - 80, by + 88, { fam: FONT.round, px: 18, fill: '#F4F1E8' });
    text(ctx, 'VISITORS', w / 2 + 80, by + 88, { fam: FONT.round, px: 18, fill: '#F4F1E8' });
    text(ctx, '13', w / 2 - 80, by + 118, { fam: FONT.mono, px: 46, fill: '#FF5A3C' });
    text(ctx, '12', w / 2 + 80, by + 118, { fam: FONT.mono, px: 46, fill: '#FF5A3C' });
    // striped field with perspective yard lines
    const fy = sy1 + 4;
    for (let i = 0; i < 9; i++) {
      const y0 = fy + (h - fy) * ((i / 9) ** 1.35), y1 = fy + (h - fy) * (((i + 1) / 9) ** 1.35);
      ctx.fillStyle = i % 2 ? '#3FA34A' : '#52B85A'; ctx.fillRect(0, y0, w, y1 - y0 + 1);
    }
    ctx.strokeStyle = 'rgba(255,255,255,0.85)'; ctx.lineWidth = 4;
    for (let k = -6; k <= 6; k++) { ctx.beginPath(); ctx.moveTo(w / 2 + k * 40, fy); ctx.lineTo(w / 2 + k * 190, h); ctx.stroke(); }
    ctx.lineWidth = 6; ctx.beginPath(); ctx.moveTo(0, fy + 4); ctx.lineTo(w, fy + 4); ctx.stroke();
    // pennant bunting
    for (const [y0, sag] of [[18, 40], [8, 26]]) {
      ctx.strokeStyle = '#F4F1E8'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(0, y0); ctx.quadraticCurveTo(w / 2, y0 + sag * 2, w, y0); ctx.stroke();
      const cols = ['#FFD23A', '#2F5BD3', '#E23B3B', '#F4F1E8'];
      for (let i = 0; i < 16; i++) {
        const t = (i + 0.5) / 16, x = t * w, y = y0 + 4 * sag * t * (1 - t);
        ctx.beginPath(); ctx.moveTo(x - 18, y); ctx.lineTo(x + 18, y); ctx.lineTo(x, y + 36); ctx.closePath(); ctx.fillStyle = cols[i % 4]; ctx.fill();
      }
      if (y0 === 18) break;
    }
    frameBorder(ctx, w, h, '#1B2F7A', 12);
  },

  // avocado kitchen: 70s circle wallpaper, sunburst clock, window with gingham curtains, cabinets, counter
  wobble_up(ctx, w, h, rand) {
    ctx.fillStyle = '#F6E7C8'; ctx.fillRect(0, 0, w, h);
    for (let y = 0; y < h * 0.66; y += 64) for (let x = 0; x < w + 64; x += 64) {
      const ox = (Math.floor(y / 64) % 2) * 32;
      for (const [r, c] of [[28, '#E3662B'], [20, '#F6E7C8'], [13, '#8A5230'], [6, '#E8A92E']]) { ctx.beginPath(); ctx.arc(x + ox, y + 32, r, 0, TAU); ctx.fillStyle = c; ctx.fill(); }
    }
    // window with sky + gingham curtains
    const wx = 250, wy = 70, ww = 268, wh = 230;
    ctx.fillStyle = lin(ctx, 0, wy, 0, wy + wh, ['#7FC0FF', '#CDE8FF']); ctx.fillRect(wx, wy, ww, wh);
    ctx.beginPath(); ctx.arc(wx + 190, wy + 80, 34, 0, TAU); ctx.fillStyle = '#FFE36A'; ctx.fill();
    cloud(ctx, wx + 80, wy + 60, 0.7);
    ctx.fillStyle = '#5E8A3A'; ctx.beginPath(); ctx.ellipse(wx + 60, wy + wh, 90, 50, 0, Math.PI, TAU); ctx.fill(); ctx.beginPath(); ctx.ellipse(wx + 220, wy + wh, 100, 42, 0, Math.PI, TAU); ctx.fill();
    ctx.strokeStyle = '#F4F1E8'; ctx.lineWidth = 14; ctx.strokeRect(wx, wy, ww, wh);
    ctx.lineWidth = 8; ctx.beginPath(); ctx.moveTo(wx + ww / 2, wy); ctx.lineTo(wx + ww / 2, wy + wh); ctx.moveTo(wx, wy + wh / 2); ctx.lineTo(wx + ww, wy + wh / 2); ctx.stroke();
    for (const s of [0, 1]) {
      const cx = s ? wx + ww - 10 : wx + 10;
      ctx.save();
      ctx.beginPath();
      if (!s) { ctx.moveTo(wx - 40, wy - 20); ctx.lineTo(wx + 60, wy - 20); ctx.quadraticCurveTo(wx + 20, wy + 120, wx + 50, wy + 250); ctx.lineTo(wx - 40, wy + 250); }
      else { ctx.moveTo(wx + ww + 40, wy - 20); ctx.lineTo(wx + ww - 60, wy - 20); ctx.quadraticCurveTo(wx + ww - 20, wy + 120, wx + ww - 50, wy + 250); ctx.lineTo(wx + ww + 40, wy + 250); }
      ctx.closePath(); ctx.clip();
      ctx.fillStyle = '#FFFFFF'; ctx.fillRect(cx - 120, wy - 30, 240, 300);
      ctx.fillStyle = 'rgba(226,59,59,0.55)';
      for (let i = 0; i < 30; i++) { ctx.fillRect(cx - 120 + i * 12, wy - 30, 6, 300); ctx.fillRect(cx - 120, wy - 30 + i * 12, 240, 6); }
      ctx.restore();
    }
    ctx.fillStyle = '#E23B3B'; ctx.fillRect(wx - 50, wy - 30, ww + 100, 22);
    // sunburst clock
    const kx = 110, ky = 130;
    for (let i = 0; i < 24; i++) { const a = (i / 24) * TAU; ctx.strokeStyle = i % 2 ? '#C8963C' : '#8A5230'; ctx.lineWidth = 6; ctx.beginPath(); ctx.moveTo(kx + Math.cos(a) * 36, ky + Math.sin(a) * 36); ctx.lineTo(kx + Math.cos(a) * (i % 2 ? 62 : 74), ky + Math.sin(a) * (i % 2 ? 62 : 74)); ctx.stroke(); }
    ctx.beginPath(); ctx.arc(kx, ky, 36, 0, TAU); ctx.fillStyle = '#F4F1E8'; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = '#8A5230'; ctx.stroke();
    ctx.strokeStyle = '#2A1D3A'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(kx, ky); ctx.lineTo(kx, ky - 24); ctx.moveTo(kx, ky); ctx.lineTo(kx + 16, ky + 6); ctx.stroke();
    // recipe card frame
    rrp(ctx, 590, 110, 130, 150, 8); ctx.fillStyle = '#8A5230'; ctx.fill();
    rrp(ctx, 600, 120, 110, 130, 4); ctx.fillStyle = '#FFFDF2'; ctx.fill();
    PRODUCT_ICON.wobble_up(ctx, 655, 175, 70);
    text(ctx, 'Wobble-Up', 655, 232, { fam: FONT.groovy, px: 20, fill: '#1FB45A' });
    // counter + avocado cabinets
    const cy = h * 0.66;
    ctx.fillStyle = '#EFE3C2'; ctx.fillRect(0, cy - 10, w, 30);
    ctx.fillStyle = '#C8B890'; ctx.fillRect(0, cy + 20, w, 6);
    ctx.fillStyle = '#7F8C32'; ctx.fillRect(0, cy + 26, w, h - cy - 26);
    for (let i = 0; i < 6; i++) {
      const x = 14 + i * 124;
      rrp(ctx, x, cy + 44, 112, h - cy - 64, 8); ctx.fillStyle = '#8C9A3A'; ctx.fill(); ctx.lineWidth = 4; ctx.strokeStyle = '#5E6A22'; ctx.stroke();
      rrp(ctx, x + 14, cy + 60, 84, h - cy - 96, 6); ctx.strokeStyle = '#A8B650'; ctx.stroke();
      ctx.beginPath(); ctx.arc(x + (i % 2 ? 18 : 94), cy + 120, 6, 0, TAU); ctx.fillStyle = '#D8DCE6'; ctx.fill();
    }
    // things on the counter: canisters, toaster
    [['#E3662B', 70], ['#E8A92E', 56], ['#8A5230', 44]].forEach(([c, hh], i) => { rrp(ctx, 40 + i * 58, cy - 10 - hh, 48, hh, 8); ctx.fillStyle = c; ctx.fill(); rrp(ctx, 36 + i * 58, cy - 18 - hh, 56, 12, 5); ctx.fillStyle = '#F4F1E8'; ctx.fill(); });
    rrp(ctx, 560, cy - 70, 120, 62, 18); ctx.fillStyle = '#C9CED8'; ctx.fill(); ctx.fillStyle = '#2A1D3A'; ctx.fillRect(588, cy - 72, 26, 6); ctx.fillRect(628, cy - 72, 26, 6);
    frameBorder(ctx, w, h, '#0E4A26', 12);
  },

  // Jump Cut morning: sunrise skyline through a big window, orange tiles, mug shelf, film-strip border
  jump_cut(ctx, w, h, rand) {
    ctx.fillStyle = '#6B3A1E'; ctx.fillRect(0, 0, w, h);
    const wx = 60, wy = 70, ww = w - 120, wh = 300;
    ctx.fillStyle = lin(ctx, 0, wy, 0, wy + wh, ['#FF7E5F', '#FFB36B', '#FFE3A3']); ctx.fillRect(wx, wy, ww, wh);
    ctx.save(); ctx.beginPath(); ctx.rect(wx, wy, ww, wh); ctx.clip();
    rays(ctx, w / 2, wy + wh - 40, 700, 22, 'rgba(255,255,255,0.18)');
    ctx.beginPath(); ctx.arc(w / 2, wy + wh - 30, 90, 0, TAU); ctx.fillStyle = '#FFF1B0'; ctx.fill();
    ctx.fillStyle = '#7A3A2A';
    let x = wx;
    while (x < wx + ww) { const bw = 30 + rand() * 50, bh = 60 + rand() * 150; ctx.fillRect(x, wy + wh - bh, bw - 4, bh); for (let yy = wy + wh - bh + 10; yy < wy + wh - 10; yy += 18) for (let xx = x + 6; xx < x + bw - 12; xx += 12) if (rand() < 0.4) { ctx.fillStyle = '#FFD27A'; ctx.fillRect(xx, yy, 5, 8); ctx.fillStyle = '#7A3A2A'; } x += bw; }
    ctx.restore();
    ctx.strokeStyle = '#F6E7C8'; ctx.lineWidth = 16; ctx.strokeRect(wx, wy, ww, wh);
    ctx.lineWidth = 8; for (const k of [1, 2]) { ctx.beginPath(); ctx.moveTo(wx + (ww * k) / 3, wy); ctx.lineTo(wx + (ww * k) / 3, wy + wh); ctx.stroke(); }
    // script sign over the window
    rrp(ctx, w / 2 - 170, 18, 340, 56, 26); ctx.fillStyle = '#F6E7C8'; ctx.fill(); ctx.lineWidth = 6; ctx.strokeStyle = '#4A1E0E'; ctx.stroke();
    text(ctx, 'Rise & Shine!', w / 2, 47, { fam: FONT.groovy, px: 38, fill: '#E3662B', stroke: '#4A1E0E', lw: 5 });
    // shelf with 70s mugs
    const sy = wy + wh + 60;
    ctx.fillStyle = '#8A5230'; ctx.fillRect(40, sy, w - 80, 14);
    ['#E3662B', '#E8A92E', '#8C9A3A', '#F6E7C8', '#B5472A', '#E3662B', '#2E8C8C', '#E8A92E'].forEach((c, i) => {
      const mx = 80 + i * 82;
      rrp(ctx, mx - 22, sy - 50, 44, 50, 8); ctx.fillStyle = c; ctx.fill();
      ctx.beginPath(); ctx.arc(mx + 26, sy - 26, 12, -1.3, 1.3); ctx.lineWidth = 6; ctx.strokeStyle = c; ctx.stroke();
    });
    // orange tiles below
    const ty = sy + 24;
    for (let yy = ty; yy < h; yy += 40) for (let xx = 0; xx < w; xx += 40) { ctx.fillStyle = ((xx + yy) / 40) % 2 ? '#E3662B' : '#F08A3A'; ctx.fillRect(xx + 2, yy + 2, 36, 36); }
    // film-strip border (the brand motif)
    ctx.fillStyle = '#2A160C'; ctx.fillRect(0, 0, 22, h); ctx.fillRect(w - 22, 0, 22, h);
    ctx.fillStyle = '#F6E7C8';
    for (let yy = 8; yy < h; yy += 30) { rrp(ctx, 5, yy, 12, 16, 3); ctx.fill(); rrp(ctx, w - 17, yy, 12, 16, 3); ctx.fill(); }
  },

  // roller disco: purple night, rainbow banking arcs, mirror ball beams, checker rink, skater silhouettes
  roller_boogie(ctx, w, h, rand) {
    ctx.fillStyle = lin(ctx, 0, 0, 0, h, ['#2A0E3A', '#4A1A5E', '#6B3A6E']); ctx.fillRect(0, 0, w, h);
    ctx.save(); ctx.globalAlpha = 0.18; rays(ctx, w / 2, 70, w * 1.2, 18, '#FF5FA2'); ctx.restore();
    for (let i = 0; i < 90; i++) sparkle(ctx, rand() * w, rand() * h * 0.6, 2 + rand() * 7, rand() < 0.5 ? '#FFFFFF' : '#5FE3FF');
    // mirror ball (painted, top center)
    ctx.beginPath(); ctx.arc(w / 2, 80, 50, 0, TAU); ctx.fillStyle = '#C9CED8'; ctx.fill();
    ctx.save(); ctx.beginPath(); ctx.arc(w / 2, 80, 50, 0, TAU); ctx.clip();
    for (let y = 30; y < 130; y += 12) for (let x = w / 2 - 50; x < w / 2 + 50; x += 12) { ctx.fillStyle = rand() < 0.3 ? '#FFFFFF' : rand() < 0.5 ? '#8A90A8' : '#AEB4C4'; ctx.fillRect(x, y, 10, 10); }
    ctx.restore();
    ctx.fillStyle = '#8A90A8'; ctx.fillRect(w / 2 - 2, 0, 4, 32);
    // rainbow banking arcs
    const cols = [BAR.red, '#FF9A2A', BAR.yellow, BAR.green, BAR.blue, '#8A4ADC'];
    cols.forEach((c, i) => { ctx.beginPath(); ctx.arc(w * 0.5, h * 1.25, w * 0.92 - i * 26, Math.PI * 1.08, Math.PI * 1.92); ctx.lineWidth = 26; ctx.strokeStyle = c; ctx.stroke(); });
    // SKATE sign
    text(ctx, 'SKATE!', w / 2, h * 0.42, { fam: FONT.groovy, px: 96, fill: '#FF5FA2', stroke: '#FFFFFF', lw: 6, depth: 6, depthFill: '#3A1440' });
    // skater silhouettes
    const skater = (x, y, s, c, flip) => {
      ctx.save(); ctx.translate(x, y); ctx.scale(flip ? -s : s, s); ctx.fillStyle = c;
      ctx.beginPath(); ctx.arc(0, -70, 12, 0, TAU); ctx.fill();
      ctx.beginPath(); ctx.moveTo(-10, -58); ctx.lineTo(12, -58); ctx.lineTo(18, -20); ctx.lineTo(34, 8); ctx.lineTo(24, 12); ctx.lineTo(6, -12); ctx.lineTo(-8, 10); ctx.lineTo(-20, 6); ctx.lineTo(-8, -22); ctx.closePath(); ctx.fill();
      ctx.lineWidth = 6; ctx.strokeStyle = c; ctx.beginPath(); ctx.moveTo(-8, -50); ctx.lineTo(-34, -64); ctx.moveTo(12, -50); ctx.lineTo(36, -40); ctx.stroke();
      for (const [wx2, wy2] of [[-22, 14], [-10, 16], [22, 18], [34, 14]]) { ctx.beginPath(); ctx.arc(wx2, wy2, 4, 0, TAU); ctx.fill(); }
      ctx.restore();
    };
    skater(150, h * 0.66, 1.4, '#5FE3FF', false); skater(610, h * 0.64, 1.3, '#FFD23A', true); skater(380, h * 0.7, 1.0, '#FF5FA2', false);
    // checker rink floor in perspective
    const fy = h * 0.74;
    ctx.fillStyle = '#3A1440'; ctx.fillRect(0, fy, w, h - fy);
    for (let r = 0; r < 6; r++) {
      const y0 = fy + (h - fy) * (r / 6) ** 1.3, y1 = fy + (h - fy) * ((r + 1) / 6) ** 1.3;
      for (let c = -8; c < 9; c++) {
        const k0 = 40 + r * 20, k1 = 40 + (r + 1) * 20;
        if ((r + c) % 2) continue;
        ctx.beginPath(); ctx.moveTo(w / 2 + c * k0, y0); ctx.lineTo(w / 2 + (c + 1) * k0, y0); ctx.lineTo(w / 2 + (c + 1) * k1, y1); ctx.lineTo(w / 2 + c * k1, y1); ctx.closePath();
        ctx.fillStyle = '#FF5FA2'; ctx.fill();
      }
    }
    frameBorder(ctx, w, h, '#FF5FA2', 10);
  },

  // bathroom: pale blue tiles, a stripe band, shelf with toothbrush cup, striped towel, bubbles and sparkles
  double_vision(ctx, w, h, rand) {
    ctx.fillStyle = '#EAF6FB'; ctx.fillRect(0, 0, w, h);
    const s = 48;
    for (let y = 0; y < h; y += s) for (let x = 0; x < w; x += s) {
      ctx.fillStyle = (Math.floor(y / s) === 7) ? ((x / s) % 2 ? '#2F5BD3' : '#E23B3B') : ((x + y) / s) % 2 ? '#BFE6F4' : '#A8DCEF';
      rrp(ctx, x + 2, y + 2, s - 4, s - 4, 5); ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.45)'; ctx.fillRect(x + 6, y + 6, s - 22, 5);
    }
    // shelf + toothbrush cup + soap + bottle
    const sy = 250;
    rrp(ctx, 470, sy, 250, 16, 6); ctx.fillStyle = '#F4F1E8'; ctx.fill();
    rrp(ctx, 500, sy - 64, 50, 64, 10); ctx.fillStyle = 'rgba(160,220,240,0.9)'; ctx.fill();
    [['#E23B3B', -12], ['#2F5BD3', 0], ['#FFD23A', 12]].forEach(([c, dx]) => { ctx.save(); ctx.translate(525 + dx, sy - 60); ctx.rotate(dx * 0.02); ctx.fillStyle = c; rrp(ctx, -4, -70, 8, 76, 4); ctx.fill(); ctx.fillStyle = '#FFFFFF'; rrp(ctx, -6, -86, 12, 20, 4); ctx.fill(); ctx.restore(); });
    rrp(ctx, 580, sy - 22, 56, 22, 10); ctx.fillStyle = '#FF9EC4'; ctx.fill();
    rrp(ctx, 660, sy - 70, 36, 70, 10); ctx.fillStyle = '#52D24A'; ctx.fill(); rrp(ctx, 668, sy - 84, 20, 16, 4); ctx.fillStyle = '#F4F1E8'; ctx.fill();
    // towel ring with a striped towel
    ctx.lineWidth = 8; ctx.strokeStyle = '#C9CED8'; ctx.beginPath(); ctx.arc(130, 170, 44, Math.PI, TAU); ctx.stroke();
    rrp(ctx, 88, 170, 84, 150, 12); ctx.fillStyle = '#F7F3EA'; ctx.fill();
    ['#E23B3B', '#2F5BD3', '#E23B3B'].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(88, 250 + i * 20, 84, 10); });
    // SMILE lettering + bubbles + sparkles
    text(ctx, 'SMILE!', 250, 110, { fam: FONT.groovy, px: 78, fill: '#2F5BD3', stroke: '#FFFFFF', lw: 8, depth: 5, depthFill: '#123A7A', rot: -0.08 });
    for (const [dx, col] of [[-5, 'rgba(63,214,224,0.6)'], [5, 'rgba(255,79,160,0.6)']]) text(ctx, 'SMILE!', 250 + dx, 110, { fam: FONT.groovy, px: 78, fill: col, rot: -0.08 });
    text(ctx, 'SMILE!', 250, 110, { fam: FONT.groovy, px: 78, fill: '#2F5BD3', rot: -0.08 });
    for (let i = 0; i < 26; i++) {
      const x = rand() * w, y = 300 + rand() * (h - 320), r = 8 + rand() * 26;
      ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fillStyle = 'rgba(255,255,255,0.35)'; ctx.fill(); ctx.lineWidth = 2.5; ctx.strokeStyle = 'rgba(255,255,255,0.9)'; ctx.stroke();
      ctx.beginPath(); ctx.arc(x - r * 0.35, y - r * 0.35, r * 0.2, 0, TAU); ctx.fillStyle = '#FFFFFF'; ctx.fill();
    }
    for (let i = 0; i < 14; i++) sparkle(ctx, rand() * w, rand() * h, 6 + rand() * 12, '#FFFFFF');
    frameBorder(ctx, w, h, '#123A7A', 12);
  },
};
// tiny product icons for painted details
const PRODUCT_ICON = {
  wobble_up(ctx, x, y, s) {
    ctx.beginPath(); ctx.ellipse(x, y + s * 0.34, s * 0.5, s * 0.1, 0, 0, TAU); ctx.fillStyle = '#F4F1E8'; ctx.fill();
    ctx.beginPath(); ctx.moveTo(x - s * 0.42, y + s * 0.32); ctx.bezierCurveTo(x - s * 0.46, y - s * 0.3, x - s * 0.2, y - s * 0.4, x, y - s * 0.4);
    ctx.bezierCurveTo(x + s * 0.2, y - s * 0.4, x + s * 0.46, y - s * 0.3, x + s * 0.42, y + s * 0.32); ctx.closePath();
    ctx.fillStyle = '#1FB45A'; ctx.fill(); ctx.lineWidth = 3; ctx.strokeStyle = '#0E4A26'; ctx.stroke();
    ctx.beginPath(); ctx.arc(x, y - s * 0.46, s * 0.08, 0, TAU); ctx.fillStyle = '#E23B3B'; ctx.fill();
  },
};
function backdropTex(id) { return texC(`bd.${id}`, 768, 672, (ctx, w, h, rand) => BACKDROP[id](ctx, w, h, rand)); }

// Riser tops (one canvas for the whole 3x3 m top: floor pattern + border band)
const FLOOR = {
  replay_ade(ctx, w, h, rand) {
    ctx.fillStyle = '#3F9A48'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 6; i++) { ctx.fillStyle = i % 2 ? 'rgba(255,255,255,0.06)' : 'rgba(0,40,0,0.08)'; ctx.fillRect(0, (i * h) / 6, w, h / 6); }
    for (let i = 0; i < 9000; i++) { ctx.fillStyle = rand() < 0.5 ? '#2E7A36' : '#6AC06E'; ctx.globalAlpha = 0.5; ctx.fillRect(rand() * w, rand() * h, 1.5, 3); }
    ctx.globalAlpha = 1;
    ctx.strokeStyle = '#F4F1E8'; ctx.lineWidth = 8; ctx.strokeRect(22, 22, w - 44, h - 44);
    ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(22, h * 0.55); ctx.lineTo(w - 22, h * 0.55); ctx.stroke();
    text(ctx, '13', w * 0.18, h * 0.64, { fam: FONT.sign, px: 44, fill: 'rgba(244,241,232,0.9)' });
    text(ctx, '13', w * 0.82, h * 0.64, { fam: FONT.sign, px: 44, fill: 'rgba(244,241,232,0.9)' });
  },
  wobble_up(ctx, w, h, rand) {
    const n = 12, s = w / n;
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) { ctx.fillStyle = (x + y) % 2 ? '#8C9A3A' : '#F2E4C4'; ctx.fillRect(x * s, y * s, s, s); }
    for (let i = 0; i < 3000; i++) { ctx.fillStyle = rand() < 0.5 ? 'rgba(90,60,30,0.15)' : 'rgba(255,255,255,0.18)'; ctx.fillRect(rand() * w, rand() * h, 2, 2); }
    ctx.strokeStyle = '#5A3A22'; ctx.lineWidth = 16; ctx.strokeRect(8, 8, w - 16, h - 16);
  },
  jump_cut(ctx, w, h) {
    const n = 10, s = w / n;
    ctx.fillStyle = '#F6E7C8'; ctx.fillRect(0, 0, w, h);
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      ctx.fillStyle = (x + y) % 2 ? '#E3662B' : '#F6E7C8';
      ctx.beginPath(); ctx.moveTo(x * s + s / 2, y * s); ctx.lineTo(x * s + s, y * s + s / 2); ctx.lineTo(x * s + s / 2, y * s + s); ctx.lineTo(x * s, y * s + s / 2); ctx.closePath(); ctx.fill();
    }
    ctx.strokeStyle = '#5A3A22'; ctx.lineWidth = 18; ctx.strokeRect(9, 9, w - 18, h - 18);
  },
  roller_boogie(ctx, w, h, rand) {
    const n = 9, pw = w / n;
    for (let i = 0; i < n; i++) { ctx.fillStyle = `hsl(${30 + rand() * 6}, ${50 + rand() * 10}%, ${62 + rand() * 8}%)`; ctx.fillRect(i * pw, 0, pw, h); ctx.fillStyle = 'rgba(90,50,20,0.5)'; ctx.fillRect(i * pw, 0, 2, h); }
    for (let i = 0; i < 60; i++) { ctx.strokeStyle = 'rgba(120,70,30,0.2)'; ctx.lineWidth = 1; const x = rand() * w; ctx.beginPath(); ctx.moveTo(x, 0); ctx.bezierCurveTo(x + 4, h / 3, x - 4, (2 * h) / 3, x + 2, h); ctx.stroke(); }
    const cols = [BAR.red, '#FF9A2A', BAR.yellow, BAR.green, BAR.blue, '#8A4ADC'];
    cols.forEach((c, i) => { ctx.strokeStyle = c; ctx.lineWidth = 9; ctx.strokeRect(10 + i * 9, 10 + i * 9, w - 20 - i * 18, h - 20 - i * 18); });
    starP(ctx, w / 2, h * 0.3, 60, 26, 5); ctx.fillStyle = 'rgba(255,95,162,0.8)'; ctx.fill();
  },
  double_vision(ctx, w, h) {
    const r = 14;
    ctx.fillStyle = '#9CCCDD'; ctx.fillRect(0, 0, w, h);
    for (let y = 0, row = 0; y < h + r; y += r * 1.5, row++) for (let x = (row % 2) * r * 0.87; x < w + r; x += r * 1.74) {
      ctx.beginPath(); for (let k = 0; k < 6; k++) { const a = (k / 6) * TAU + Math.PI / 6; ctx.lineTo(x + Math.cos(a) * (r - 1.5), y + Math.sin(a) * (r - 1.5)); } ctx.closePath();
      ctx.fillStyle = ((row * 7 + Math.round(x)) % 11 === 0) ? '#3FB8E8' : ((row + Math.round(x / 24)) % 3 ? '#D6ECF4' : '#C2E2EE'); ctx.fill();
    }
    ctx.strokeStyle = '#2F5BD3'; ctx.lineWidth = 14; ctx.strokeRect(7, 7, w - 14, h - 14);
    ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 6; ctx.strokeRect(22, 22, w - 44, h - 44);
  },
};
function floorTex(id) { return texC(`floor.${id}`, 512, 512, (ctx, w, h, rand) => FLOOR[id](ctx, w, h, rand)); }
function wingTex(id) {
  const S = SP[id];
  return texC(`wing.${id}`, 256, 512, (ctx, w, h, rand) => {
    ctx.fillStyle = lin(ctx, 0, 0, 0, h, [S.main, S.deep]); ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 5; i++) { ctx.fillStyle = i % 2 ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.12)'; ctx.fillRect(0, 60 + i * 34, w, 18); }
    ctx.fillStyle = S.second; ctx.fillRect(0, h - 90, w, 24);
    for (let i = 0; i < 10; i++) sparkle(ctx, 20 + rand() * (w - 40), 240 + rand() * 160, 6 + rand() * 10, '#FFFFFF');
  });
}
function stencilTex() {
  return texC('stencil', 512, 128, (ctx, w, h) => {
    ctx.fillStyle = '#C9A477'; ctx.fillRect(0, 0, w, h);
    text(ctx, 'WZTV PROP SHOP · THIS SIDE UP ▲', w / 2, h / 2, { fam: FONT.sign, px: 30, fill: 'rgba(42,29,58,0.75)', maxW: w - 30 });
  });
}

// =============================================================================================== SPONSOR SETS
// sponsor_set_<perkId>: 3x3 m riser (0.2 m), backdrop flat (3 x 2.6 m) painted with the product's world + two short
// wing flats, neon sponsor sign (cards.js sponsor_sign_<id>, lit/unlit), rotating pedestal (parts.turntable) with
// the giant product, two softboxes aimed at it, gaffer-tape X (the mark), a small speaker, per-brand dressing and
// the sponsor camera (pedestal camera with tally; Replay-Ade: ENG camera on a tripod) standing 2.6 m in front
// of the mark, off the riser, aimed at it.
// LOCAL LAYOUT (front = -z, riser centered): mark X [0,0.2,-0.75] · pedestal [0,0.2,0.45] (1.2 m behind the mark)
// · camera [0.35,0,-3.35] looking at [0,1.2,-0.75] · backdrop face z=1.3. userData.anchors has them all.
// opts { lit=true, camera=true, product=true }. Before Sign-On: opts.lit=false or setSponsorSetPower(set,false).
const SET = { H: 0.2, mark: [0, 0.2, -0.75], pedestal: [0, 0.2, 0.45], camera: [0.35, 0, -3.35] };

function markX(game) {
  const tape = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#F2EEE4', { pattern: 'plain', scale: 2 }), emissive: '#FFF2D0', emissiveIntensity: 0.12, rim: 0.2 });
  const g = new THREE.Group();
  for (const a of [Math.PI / 4, -Math.PI / 4]) {
    const strip = new THREE.BoxGeometry(0.62, 0.004, 0.075, 6, 1, 1);
    deform(strip, (v) => { v.y += 0.0015 * Math.sin(v.x * 40); if (Math.abs(v.x) > 0.3) v.z += (Math.round(v.z * 100) % 2 ? 0.006 : -0.004); });
    g.add(K.m(strip, tape, { rot: [0, a, 0], cast: false }));
  }
  return g;
}

// ------------------------------------------------------------------ brand dressing (static, sits on the riser)
const DRESS = {
  replay_ade(game) { // sideline water cooler on a bench, paper cups, folded towel
    const g = new THREE.Group();
    const cooler = K.mat(game, 'plastic', '#FFD23A', { rough: 0.3 });
    const white = K.mat(game, 'plastic', '#F4F1E8', { rough: 0.35 });
    const blue = K.mat(game, 'plastic', '#2F5BD3', { rough: 0.35 });
    const { metal } = setMats(game);
    const towel = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#F4F1E8', { pattern: 'plain', scale: 2 }) });
    const flag = K.mat(game, 'paint', '#ffffff', { map: flagTex('replay_ade') });
    g.add(K.m(K.box(0.62, 0.05, 0.4, 0.015, { uv: 2 }), K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood(PAL.teak) }), { pos: [0, 0.42, 0] }));
    for (const x of [-0.26, 0.26]) for (const z of [-0.15, 0.15]) g.add(K.m(pcyl(0.016, 0.016, 0.4, 8), metal, { pos: [x, 0, z] }));
    g.add(K.m(K.lathe([[0, 0], [0.19, 0], [0.2, 0.02], [0.2, 0.36], [0.19, 0.38], [0, 0.38]], { seg: 24, round: 0.02, steps: 1 }), cooler, { pos: [0.08, 0.445, 0] }));
    g.add(K.m(K.lathe([[0, 0], [0.205, 0], [0.21, 0.03], [0.17, 0.08], [0, 0.1]], { seg: 24, round: 0.02, steps: 1 }), white, { pos: [0.08, 0.82, 0] }));
    g.add(K.m(flatTorus(0.2, 0.012, 5, 24), blue, { pos: [0.08, 0.56, 0] }));
    g.add(K.m(flatTorus(0.2, 0.012, 5, 24), blue, { pos: [0.08, 0.74, 0] }));
    g.add(K.m(new THREE.PlaneGeometry(0.2, 0.1).rotateY(Math.PI), flag, { pos: [0.08, 0.65, -0.203] }));
    g.add(K.m(K.box(0.05, 0.04, 0.06, 0.012), white, { pos: [0.08, 0.5, -0.215] }));
    g.add(K.m(K.tube([[-0.06, 0.82, 0], [0.08, 0.94, 0], [0.22, 0.82, 0]], 0.012, { seg: 10, radial: 5 }), white));
    // cup stack + towel
    g.add(K.m(K.lathe([[0.025, 0], [0.036, 0.26], [0.03, 0.26], [0.02, 0.0]], { seg: 14 }), white, { pos: [-0.2, 0.445, -0.05] }));
    g.add(K.m(K.cushion(0.2, 0.06, 0.16, { puff: 0.015 }), towel, { pos: [-0.2, 0.475, 0.1], rot: [0, 0.2, 0] }));
    return g;
  },
  wobble_up(game) { // avocado kitchen counter with a mixing bowl + spoon + gelatin box
    const g = new THREE.Group();
    const avo = K.mat(game, 'lacquer', '#8C9A3A', { rough: 0.4 });
    const top = K.mat(game, 'plastic', '#F2E4C4', { rough: 0.4 });
    const { chrome } = setMats(game);
    const bowl = K.mat(game, 'ceramic', '#E3662B');
    const wood = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood('#C89058') });
    const box = K.mat(game, 'paint', '#ffffff', { map: K.tex.label('WOBBLE-UP', { sub: 'LIME · 6 SERVINGS', bg: '#1FB45A', fg: '#FFFFFF', accent: '#E23B3B', w: 256, h: 192 }) });
    g.add(K.m(K.box(0.62, 0.8, 0.5, 0.03), avo, { pos: [0, 0.4, 0] }));
    g.add(K.m(K.box(0.68, 0.045, 0.56, 0.015), top, { pos: [0, 0.82, 0] }));
    for (const x of [-0.152, 0.152]) {
      g.add(K.m(K.box(0.27, 0.64, 0.02, 0.012), avo, { pos: [x, 0.42, -0.255] }));
      g.add(K.m(K.box(0.03, 0.14, 0.03, 0.01), chrome, { pos: [x + (x < 0 ? 0.1 : -0.1), 0.55, -0.275] }));
    }
    g.add(K.m(K.lathe([[0, 0], [0.07, 0], [0.13, 0.05], [0.165, 0.12], [0.16, 0.13], [0, 0.03]], { seg: 24, round: 0.01, steps: 1 }), bowl, { pos: [-0.1, 0.84, 0.02] }));
    g.add(span(K.m(K.cyl(0.012, 0.012, 0.3, { bevel: 0.005, seg: 8 }), wood), [-0.15, 0.9, 0.05], [0.02, 1.1, 0.02]));
    g.add(K.m(K.box(0.14, 0.18, 0.055, 0.01), box, { pos: [0.19, 0.935, 0], rot: [0, -0.3, 0] }));
    return g;
  },
  jump_cut(game) { // craft services: chrome coffee urn, cups, donut box on a little cart
    const g = new THREE.Group();
    const teak = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood(PAL.teak) });
    const { chrome, dark } = setMats(game);
    const cups = K.mat(game, 'plastic', '#F6E7C8', { rough: 0.4 });
    const pink = K.mat(game, 'paint', '#FF9EC4');
    const donut = K.mat(game, 'lacquer', '#ffffff', { rough: 0.5 });
    g.add(K.m(K.box(0.62, 0.05, 0.44, 0.015, { uv: 2 }), teak, { pos: [0, 0.74, 0] }));
    g.add(K.m(K.box(0.56, 0.035, 0.38, 0.012, { uv: 2 }), teak, { pos: [0, 0.2, 0] }));
    for (const x of [-0.27, 0.27]) for (const z of [-0.18, 0.18]) g.add(K.m(pcyl(0.018, 0.018, 0.72, 8), chrome, { pos: [x, 0, z] }));
    g.add(K.m(K.lathe([[0, 0], [0.12, 0], [0.14, 0.03], [0.14, 0.38], [0.12, 0.42], [0.06, 0.44], [0.05, 0.48], [0, 0.48]], { seg: 24, round: 0.015, steps: 1 }), chrome, { pos: [0.12, 0.765, 0.02] }));
    for (const s of [-1, 1]) g.add(K.m(K.box(0.03, 0.12, 0.05, 0.01), dark, { pos: [0.12 + s * 0.155, 1.02, 0.02] }));
    g.add(K.m(K.box(0.05, 0.04, 0.06, 0.01), dark, { pos: [0.12, 0.84, -0.16] }));
    g.add(K.m(K.lathe([[0.03, 0], [0.042, 0.22], [0.036, 0.22], [0.024, 0]], { seg: 12 }), cups, { pos: [-0.15, 0.765, 0.1] }));
    g.add(K.m(K.lathe([[0.03, 0], [0.042, 0.16], [0.036, 0.16], [0.024, 0]], { seg: 12 }), cups, { pos: [-0.24, 0.765, 0.12] }));
    g.add(K.m(K.box(0.3, 0.07, 0.22, 0.01), pink, { pos: [-0.14, 0.8, -0.08] }));
    g.add(K.m(K.box(0.3, 0.012, 0.22, 0.005), pink, { pos: [-0.14, 0.93, 0.05], rot: [-1.1, 0, 0] }));
    [['#C87A3A', '#FF7AB4'], ['#C87A3A', '#5A3A22'], ['#D89A5A', '#F6E7C8']].forEach(([dough, icing], i) => {
      g.add(K.m(paint(new THREE.TorusGeometry(0.035, 0.018, 5, 10).rotateX(Math.PI / 2), dough), donut, { pos: [-0.23 + i * 0.085, 0.845, -0.08] }));
      g.add(K.m(paint(new THREE.TorusGeometry(0.035, 0.012, 4, 10).rotateX(Math.PI / 2), icing), donut, { pos: [-0.23 + i * 0.085, 0.856, -0.08] }));
    });
    return g;
  },
  roller_boogie(game) { // little mirror ball on a pole (parts.mirrorball spins)
    const g = new THREE.Group();
    const { metal, dark } = setMats(game);
    const mirror = K.mat(game, 'chrome', '#ffffff', { map: mirrorTex(), rough: 0.18 });
    g.add(K.m(K.lathe([[0, 0], [0.26, 0], [0.27, 0.02], [0.2, 0.05], [0.04, 0.06], [0, 0.06]], { seg: 20, round: 0.01, steps: 1 }), dark));
    g.add(K.m(K.cyl(0.02, 0.02, 2.1, { bevel: 0.005, seg: 10 }), metal, { pos: [0, 0.05, 0] }));
    g.add(K.m(K.tube([[0, 2.12, 0], [0.12, 2.2, -0.05], [0.35, 2.22, -0.2]], 0.014, { seg: 10, radial: 5 }), metal));
    g.add(K.m(K.cyl(0.03, 0.03, 0.06, { bevel: 0.01, seg: 10 }), dark, { pos: [0.35, 2.17, -0.2] }));
    const ball = new THREE.Group();
    ball.position.set(0.35, 1.93, -0.2);
    ball.userData.noMerge = true;
    ball.add(K.m(new THREE.SphereGeometry(0.19, 18, 12), mirror, { name: 'mirrorball' }));
    ball.add(rod(0.004, [0, 0.19, 0], [0, 0.24, 0], metal, 4));
    g.add(ball);
    g.userData.parts = { mirrorball: ball };
    return g;
  },
  double_vision(game) { // pedestal sink + round vanity mirror ringed with bulbs
    const g = new THREE.Group();
    const porcelain = K.mat(game, 'ceramic', '#F2F0EA', { rim: 0.1 });
    const { chrome } = setMats(game);
    const frame = K.mat(game, 'lacquer', '#2F5BD3', { rough: 0.35 });
    const glassM = K.mat(game, 'crt', '#9FC8D8', { rough: 0.08 });
    const bulbs = new THREE.Group();
    bulbs.userData.noMerge = true;
    g.add(K.m(K.lathe([[0, 0], [0.16, 0], [0.17, 0.02], [0.1, 0.08], [0.08, 0.6], [0.12, 0.66], [0.26, 0.72], [0.27, 0.8], [0.23, 0.82], [0.18, 0.77], [0, 0.76]], { seg: 16, round: 0.02, steps: 1 }), porcelain));
    g.add(K.m(K.cyl(0.018, 0.022, 0.12, { bevel: 0.006, seg: 10 }), chrome, { pos: [0, 0.8, 0.2] }));
    g.add(K.m(K.tube([[0, 0.9, 0.2], [0, 0.94, 0.12], [0, 0.9, 0.06]], 0.013, { seg: 8, radial: 5 }), chrome));
    for (const s of [-1, 1]) g.add(K.m(K.cyl(0.025, 0.025, 0.03, { bevel: 0.008, seg: 10 }), chrome, { pos: [s * 0.1, 0.82, 0.21] }));
    // round mirror on a post behind the sink
    g.add(K.m(K.cyl(0.03, 0.03, 0.5, { bevel: 0.008, seg: 10 }), chrome, { pos: [0, 0.78, 0.32] }));
    const my = 1.55;
    g.add(K.m(new THREE.TorusGeometry(0.3, 0.045, 8, 28), frame, { pos: [0, my, 0.3] }));
    g.add(K.m(new THREE.CircleGeometry(0.3, 32).rotateY(Math.PI), glassM, { pos: [0, my, 0.305] }));
    g.add(K.m(new THREE.CircleGeometry(0.3, 24), frame, { pos: [0, my, 0.33] }));
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * TAU + Math.PI / 2;
      bulbs.add(K.m(new THREE.SphereGeometry(0.03, 7, 5), K.glow(game, '#FFE7B0', 1.6), { pos: [Math.cos(a) * 0.35, my + Math.sin(a) * 0.35, 0.27], cast: false }));
    }
    g.add(bulbs);
    g.userData.parts = { bulbs };
    return g;
  },
};
function mirrorTex() {
  return K.tex.canvas('sp.mirrorball', 256, 128, (ctx, w, h, rand) => {
    ctx.fillStyle = '#8A90A0'; ctx.fillRect(0, 0, w, h);
    const s = 10;
    for (let y = 0; y < h; y += s) for (let x = 0; x < w; x += s) {
      const v = rand();
      ctx.fillStyle = v < 0.12 ? '#FFFFFF' : v < 0.2 ? '#FFD6F0' : v < 0.28 ? '#C8F4FF' : `hsl(230, 8%, ${48 + v * 36}%)`;
      ctx.fillRect(x + 1, y + 1, s - 2, s - 2);
    }
  });
}

// ------------------------------------------------------------------ the prefab
function buildSponsorSet(game, id, opts = {}) {
  const S = SP[id];
  const lit = opts.lit !== false;
  const withCam = opts.camera !== false, withProduct = opts.product !== false;
  const g = K.prop(`sponsor_set_${id}`);
  const H = SET.H;
  const parts = { tally: [], diffuser: [], bulbs: [], sign: null };
  const power = { on: {}, off: {} };
  const colliders = [];
  // ---- riser: themed top, corduroy skirt, accent bumper, chaser bulbs along the front
  const topG = K.box(3, 0.05, 3, 0.02).clone();
  uvPlanar(topG, 'x', 1.5, -1.5, 'z', -1.5, 1.5);
  g.add(K.m(topG, K.mat(game, id === 'double_vision' ? 'ceramic' : id === 'roller_boogie' ? 'lacquer' : 'paint', '#ffffff', { map: floorTex(id), rim: 0.06, rough: id === 'replay_ade' ? 0.95 : 0.55 }), { pos: [0, H - 0.025, 0] }));
  g.add(K.m(K.box(2.96, H - 0.04, 2.96, 0.02, { uv: 2 }), K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#3A2A48', { pattern: 'cord', scale: 3 }) }), { pos: [0, (H - 0.04) / 2, 0] }));
  const accent = K.mat(game, 'lacquer', S.main, { rough: 0.35 });
  g.add(K.m(K.tube(K.roundRectPath(3.02, 3.02, 0.08, H - 0.03), 0.024, { seg: 48, radial: 5, closed: true }), accent));
  const bulbOn = K.glow(game, PAL.marqueeGold, 1.7), bulbOff = K.mat(game, 'plastic', '#E8DCC0', { rim: 0.1 });
  power.on.bulbs = bulbOn; power.off.bulbs = bulbOff;
  const rbulbs = new THREE.Group();
  rbulbs.userData.noMerge = true;
  const SM = setMats(game), chrome = SM.chrome;
  for (let i = 0; i < 11; i++) {
    const x = -1.25 + i * 0.25;
    rbulbs.add(K.m(new THREE.SphereGeometry(0.027, 6, 4), lit ? bulbOn : bulbOff, { pos: [x, 0.085, -1.505], cast: false }));
    g.add(K.m(new THREE.CylinderGeometry(0.032, 0.032, 0.02, 8).rotateX(Math.PI / 2), chrome, { pos: [x, 0.085, -1.485] }));
  }
  g.add(rbulbs);
  colliders.push({ min: [-1.52, 0, -1.52], max: [1.52, H, 1.52] });
  // ---- backdrop flat: painted face in an accent frame, plywood back with battens + stencil
  const FY = H + 1.3, FZ = 1.32;
  g.add(K.m(new THREE.PlaneGeometry(2.9, 2.5).rotateY(Math.PI), K.mat(game, 'paint', '#ffffff', { map: backdropTex(id), rim: 0.04, rough: 0.7 }), { pos: [0, FY, FZ] }));
  g.add(K.m(K.box(3.04, 0.1, 0.1, 0.014), accent, { pos: [0, H + 2.6 - 0.05, FZ + 0.02] }));
  g.add(K.m(K.box(3.04, 0.1, 0.1, 0.014), accent, { pos: [0, H + 0.05, FZ + 0.02] }));
  for (const s of [-1, 1]) g.add(K.m(K.box(0.1, 2.6, 0.1, 0.014), accent, { pos: [s * 1.47, FY, FZ + 0.02] }));
  const ply = K.mat(game, 'teak', '#ffffff', { map: K.tex.wood('#C9A477', { dark: 0.2 }) });
  g.add(K.m(K.box(2.98, 2.58, 0.04, 0.01, { uv: 1.2 }), ply, { pos: [0, FY, FZ + 0.05] }));
  for (const y of [H + 0.3, H + 2.3]) g.add(K.m(K.box(2.9, 0.08, 0.04, 0.01, { uv: 2, swap: true }), ply, { pos: [0, y, FZ + 0.09] }));
  for (const x of [-0.9, 0.9]) g.add(K.m(K.box(0.08, 2.5, 0.04, 0.01, { uv: 2 }), ply, { pos: [x, FY, FZ + 0.09] }));
  g.add(K.m(new THREE.PlaneGeometry(1.0, 0.25), K.mat(game, 'paint', '#ffffff', { map: stencilTex() }), { pos: [0, H + 1.8, FZ + 0.111] }));
  colliders.push({ min: [-1.52, H, FZ - 0.06], max: [1.52, H + 2.6, FZ + 0.12] });
  // ---- wing flats angled forward at both ends
  const wingM = K.mat(game, 'paint', '#ffffff', { map: wingTex(id), rim: 0.06 });
  for (const s of [-1, 1]) {
    const x0 = s * 1.44, z0 = FZ - 0.02, dx = -s * 0.42, dz = -0.906, L = 0.72;
    const cx = x0 + (dx * L) / 2, cz = z0 + (dz * L) / 2;
    const wing = K.m(K.box(L, 2.2, 0.06, 0.012), wingM, { pos: [cx, H + 1.1, cz], rot: [0, Math.atan2(-dz, dx), 0] });
    g.add(wing);
    g.add(K.m(K.box(0.07, 0.07, 0.07, 0.012), accent, { pos: [x0 + dx * L, H + 2.23, z0 + dz * L] }));
    colliders.push({ min: [Math.min(x0, x0 + dx * L) - 0.04, H, z0 + dz * L - 0.04], max: [Math.max(x0, x0 + dx * L) + 0.04, H + 2.2, z0 + 0.04] });
  }
  // ---- neon sponsor sign on the top of the flat
  const signY = H + 2.6, signZ = FZ - 0.14;
  g.add(K.m(K.box(1.98, 0.76, 0.1, 0.04), SM.dark, { pos: [0, signY, signZ + 0.05] }));
  for (const x of [-0.7, 0.7]) g.add(K.m(K.box(0.06, 0.06, 0.2, 0.012), chrome, { pos: [x, signY + 0.2, FZ - 0.02] }));
  const signOn = K.glow(game, '#ffffff', 1.15, { map: getCard(`sponsor_sign_${id}`), transparent: true });
  const signOff = K.mat(game, 'paint', '#ffffff', { map: getCard(`sponsor_sign_${id}`, { lit: false }), transparent: true, alphaTest: 0.05, rim: 0.05 });
  power.on.sign = signOn; power.off.sign = signOff;
  const sign = K.m(new THREE.PlaneGeometry(1.92, 0.72).rotateY(Math.PI), lit ? signOn : signOff, { pos: [0, signY, signZ - 0.003], name: 'sign', cast: false });
  sign.userData.noMerge = true; sign.userData.noAO = true; sign.userData.noOcclude = true;
  g.add(sign);
  parts.sign = sign;
  // ---- pedestal + turntable (+ product)
  const [px, , pz] = SET.pedestal;
  g.add(K.m(K.lathe([[0, 0], [0.5, 0], [0.52, 0.02], [0.5, 0.05], [0.46, 0.08], [0.45, 0.25], [0.5, 0.28], [0.5, 0.3], [0, 0.3]], { seg: 24, round: 0.015, steps: 1 }), accent, { pos: [px, H, pz] }));
  g.add(K.m(flatTorus(0.462, 0.016, 5, 32), chrome, { pos: [px, H + 0.165, pz] }));
  const turntable = new THREE.Group();
  turntable.position.set(px, H + 0.3, pz);
  turntable.userData.noMerge = true;
  const deck = K.mat(game, 'lacquer', S.deep, { rough: 0.45, env: 0.04, rim: 0.12 });
  turntable.add(K.m(K.lathe([[0, 0], [0.47, 0], [0.48, 0.015], [0.47, 0.045], [0, 0.045]], { seg: 32, round: 0.01, steps: 1 }), deck));
  const tbulbs = new THREE.Group();
  tbulbs.userData.noMerge = true;
  for (let i = 0; i < 10; i++) { const a = (i / 10) * TAU; tbulbs.add(K.m(new THREE.SphereGeometry(0.022, 6, 4), lit ? bulbOn : bulbOff, { pos: [Math.sin(a) * 0.44, 0.05, Math.cos(a) * 0.44], cast: false })); }
  turntable.add(tbulbs);
  let product = null;
  if (withProduct) {
    product = nested(K.buildProp(`product_${id}`, game, {}));
    product.position.y = 0.045;
    turntable.add(product);
    parts.product = product;
    parts.productParts = { ...product.userData.parts };
    product.userData = { id: product.userData.id, nested: true, noMerge: true };
  }
  g.add(turntable);
  parts.turntable = turntable;
  const soldOut = new THREE.Group();
  soldOut.position.set(px, H + 0.95, pz - 0.62);
  soldOut.userData.noMerge = true;
  const tapeM = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#AEB5BE', { pattern: 'plain', scale: 2 }), side: THREE.DoubleSide });
  for (const a of [0.72, -0.72]) {
    const st = new THREE.PlaneGeometry(1.5, 0.16, 8, 1);
    deform(st, (v) => { v.z = 0.03 * Math.sin(v.x * 5); if (Math.abs(v.x) > 0.7) v.y *= Math.round(v.x * 40) % 2 ? 1.1 : 0.85; });
    const m = K.m(st, tapeM, { rot: [0, 0, a], cast: false });
    m.userData.noAO = true;
    soldOut.add(m);
  }
  soldOut.visible = false;
  g.add(soldOut);
  parts.soldOut = soldOut;
  colliders.push({ min: [px - 0.53, H, pz - 0.53], max: [px + 0.53, H + 1.95, pz + 0.53] });
  // ---- softboxes aimed at the product
  const { on: softOn, off: softOff } = softboxMats(game);
  power.on.soft = softOn; power.off.soft = softOff;
  for (const s of [-1, 1]) {
    const sp = [s * 1.15, H, -0.5];
    const { g: sb, diff } = buildSoftbox(game, { height: 1.92, tilt: 0.36, lit });
    sb.position.set(sp[0], sp[1], sp[2]);
    sb.rotation.y = Math.atan2(-(px - sp[0]), -(pz - sp[2]));
    sb.userData.noMerge = true;
    g.add(sb);
    parts.diffuser.push(diff);
    parts['soft' + (s < 0 ? 'L' : 'R')] = sb;
    colliders.push({ min: [sp[0] - 0.28, H, sp[2] - 0.28], max: [sp[0] + 0.28, H + 2.25, sp[2] + 0.28] });
  }
  // ---- the mark + speaker
  const mk = markX(game);
  mk.position.set(SET.mark[0], H + 0.003, SET.mark[2]);
  g.add(mk);
  const spk = buildSpeaker(game);
  spk.position.set(-1.2, H, -1.22);
  spk.rotation.y = Math.atan2(-(SET.mark[0] + 1.2), -(SET.mark[2] + 1.22));
  spk.scale.setScalar(0.85);
  g.add(spk);
  colliders.push({ min: [-1.42, H, -1.44], max: [-0.98, H + 0.55, -1.0] });
  // ---- brand dressing
  const dr = DRESS[id](game);
  const side = id === 'replay_ade' || id === 'jump_cut' ? 1 : -1;
  const drPos = [side * 0.92, 0.9];
  dr.position.set(drPos[0], H, drPos[1]);
  dr.rotation.y = side * 0.52;
  g.add(dr);
  if (dr.userData.parts?.mirrorball) parts.mirrorball = dr.userData.parts.mirrorball;
  if (dr.userData.parts?.bulbs) { dr.userData.parts.bulbs.children.forEach((b) => { b.material = lit ? bulbOn : bulbOff; }); parts.vanityBulbs = dr.userData.parts.bulbs; }
  dr.userData = {};
  colliders.push({ min: [drPos[0] - 0.36, H, drPos[1] - 0.36], max: [drPos[0] + 0.36, H + (id === 'roller_boogie' ? 2.3 : id === 'double_vision' ? 2.1 : 1.1), drPos[1] + 0.36] });
  // ---- the sponsor camera, off the riser, aimed at the mark (target y 1.2)
  if (withCam) {
    const cam = nested(K.buildProp(id === 'replay_ade' ? 'sponsor_camera_eng' : 'sponsor_camera_pedestal', game, {}));
    const [cx, , cz] = SET.camera;
    cam.position.set(cx, 0, cz);
    cam.rotation.y = Math.atan2(-(SET.mark[0] - cx), -(SET.mark[2] - cz));
    g.add(cam);
    parts.camera = cam;
    parts.cameraHead = cam.userData.parts.head;
    parts.tally.push(...cam.userData.parts.tally);
    power.on.tally = cam.userData.power.on.tally; power.off.tally = cam.userData.power.off.tally;
    if (!lit) parts.tally.forEach((t) => { t.material = power.off.tally; });
    cam.userData = { id: cam.userData.id, nested: true, noMerge: true };
    colliders.push({ min: [cx - 0.5, 0, cz - 0.6], max: [cx + 0.5, 1.8, cz + 0.6] });
  }
  // ---- bake, merge the part groups, finish
  if (typeof location !== 'undefined' && /spprofile=1/.test(location.search)) {
    const rows = [];
    g.traverse((o) => { if (o.isMesh && !o.userData.noAO) { const gg = o.geometry; const t = (gg.index ? gg.index.count : gg.attributes.position.count) / 3; gg.computeBoundingBox(); const sz = gg.boundingBox.getSize(new THREE.Vector3()); rows.push([t, o.material.name, gg.type, sz.toArray().map((v) => v.toFixed(2)).join('x')]); } });
    rows.sort((x, y) => y[0] - x[0]);
    console.log('SPPROFILE ' + id + ' ' + JSON.stringify(rows.slice(0, 30)));
  }
  K.bakeAO(g, { strength: 0.8, rays: 12, res: 56 });
  for (const grp of [rbulbs, tbulbs, turntable, ...(parts.softL ? [parts.softL, parts.softR] : [])]) K.merge(grp);
  parts.bulbs = [...rbulbs.children, ...tbulbs.children].filter((o) => o.isMesh);
  if (parts.vanityBulbs) { K.merge(parts.vanityBulbs); parts.bulbs.push(...parts.vanityBulbs.children.filter((o) => o.isMesh)); }
  const u = g.userData;
  u.parts = parts;
  u.power = power;
  u.powered = lit;
  u.sponsor = id;
  u.colliders = colliders;
  u.anchors = { mark: SET.mark.slice(), pedestal: SET.pedestal.slice(), camera: SET.camera.slice(), cameraTarget: [SET.mark[0], 1.2, SET.mark[2]],
    lens: [SET.camera[0], 1.38, SET.camera[2]], speaker: [-1.2, H + 0.3, -1.22], sign: [0, signY, signZ] };
  u.interact = { point: SET.mark.slice(), radius: 1.0 };
  u.lightAnchors = [
    { id: `sponsor_${id}_key`, pos: [0, 2.1, -1.0], color: '#FFE8C8', intensity: lit ? 1.5 : 0, distance: 5.5 },
    { id: `sponsor_${id}_neon`, pos: [0, H + 2.4, 0.6], color: S.neon, intensity: lit ? 1.3 : 0, distance: 4 },
  ];
  return K.finish(game, g, { ao: false });
}
for (const id of SPONSOR_IDS) {
  registerProp(`sponsor_set_${id}`, (game, opts = {}) => buildSponsorSet(game, id, opts), {
    category: 'sponsors', tags: ['sponsor_set', id, 'machine'], size: [3.04, 3.2, 4.9], hero: true,
    desc: `${SP[id].name} sponsor set prefab (riser, painted flat, neon sign, turntable + product, softboxes, mark, speaker, camera)`,
  });
}

// ------------------------------------------------------------------ runtime helpers for the game systems
// Dark set before Sign-On (Replay-Ade is lit from the start): swaps sign, tally, softbox, bulb materials.
export function setSponsorSetPower(set, on) {
  const u = set.userData, P = u.power;
  if (!P) return;
  const m = on ? P.on : P.off;
  const swap = (list, mat) => { if (!mat) return; for (const o of [].concat(list || [])) if (o && o.isMesh) o.material = mat; };
  swap(u.parts.sign, m.sign);
  swap(u.parts.tally, m.tally);
  swap(u.parts.diffuser, m.soft);
  swap(u.parts.bulbs, m.bulbs);
  u.powered = on;
}
export function setTally(obj, on) {
  const u = obj.userData;
  if (!u.power || !u.power.on.tally) return;
  for (const t of [].concat(u.parts.tally || [])) t.material = on ? u.power.on.tally : u.power.off.tally;
}
// Replay-Ade sold out (GDD §11 step 6): tape X over the product, camera tipped over, tally off. on=false restores.
export function setSoldOut(set, on) {
  const p = set.userData.parts;
  if (!p) return;
  if (p.soldOut) p.soldOut.visible = on;
  if (p.camera) {
    if (p.camera.userData.base === undefined) p.camera.userData.base = { y: p.camera.position.y, rx: p.camera.rotation.x };
    const b = p.camera.userData.base;
    p.camera.position.y = on ? b.y + 0.42 : b.y;
    p.camera.rotation.x = on ? b.rx - 1.45 : b.rx;
  }
  if (on) setTally(set, false);
}
// Idle life for a product (standalone or inside a set): jelly wobble, cap spin; the set's turntable + mirror ball.
export function animateProduct(obj, t) {
  const p = obj.userData.parts || {};
  const pp = p.productParts || p;
  if (pp.jelly) { const w = Math.sin(t * 7) * 0.025; pp.jelly.scale.set(1 + w * 0.6, 1 - w, 1 + w * 0.6); pp.jelly.rotation.z = Math.sin(t * 5.3) * 0.02; }
  if (pp.cap) pp.cap.rotation.y = t * 1.6;
  if (p.turntable) p.turntable.rotation.y = t * 0.35;
  if (p.mirrorball) p.mirrorball.rotation.y = t * 0.8;
}

registerScene('sponsors_all', {
  floor: 'tile', wall: 'panel', room: [18, 7], wallH: 3.6,
  items: SPONSOR_IDS.map((id, i) => ({ id: `sponsor_set_${id}`, pos: [(i - 2) * 3.5, 0, 1.6], opts: { camera: false } })),
  cam: { pos: [0, 3.2, -8.2], target: [0, 1.2, 1.2], fov: 62 }, hemi: 1.0,
});
// the commercial's point of view: the sponsor camera lens looking at the mark (what the 4:3 shot frames)
for (const id of SPONSOR_IDS) {
  registerScene(`sponsor_pov_${id}`, {
    floor: 'tile', wall: 'panel', room: [9, 11], wallH: 3.8,
    items: [{ id: `sponsor_set_${id}`, pos: [0, 0, 0], opts: { camera: false } }],
    cam: { pos: [SET.camera[0], 1.38, SET.camera[2]], target: [0, 1.25, -0.2], fov: 44 }, hemi: 0.9,
  });
}
registerScene('sponsors', {
  floor: 'tile', wall: 'panel', room: [7, 7.5], wallH: 3.6,
  items: [{ id: 'sponsor_set_jump_cut', pos: [0, 0, 1.6] }],
  cam: { pos: [1.6, 2.0, -3.6], target: [0, 1.3, 1.2], fov: 58 },
});
