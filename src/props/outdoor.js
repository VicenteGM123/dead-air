// DEAD AIR — props: YARD & EXTERIOR (docs/PROPKIT.md, GDD §5.7 Transmitter Yard). Owner: outdoor prop artist.
// Shoot: node tools/propview/shoot.cjs category:outdoor category:outdoor_city --params "bg=%231B1E4A"   (night bg)
//        scenes: scene:out_yard scene:out_street scene:out_tower_base scene:out_van_rear
//
//   yard      (category 'outdoor')
//             yd_tower (hero) · yd_hut (hero, nests hut_tubes + 2 feed CRTs) · yd_news_van (hero) · yd_sodium_post
//             yd_fence · yd_fence_post · yd_fence_gate · yd_neon_wztv (wall) · yd_oil_drum · yd_drum_group · yd_crate
//             yd_crate_stack · yd_film_cans · yd_stones · yd_puddle · yd_gravel_patch · yd_weeds
//   skyline   (category 'outdoor_city') sky_building · sky_water_tower · sky_billboard · sky_moon · sky_skyline
//             far backdrop: no colliders, low tris, canvas facades + additive lit windows, materials ignore fog
//             (opts.fog = true to let the yard fog eat them)
//   street    (category 'outdoor_city') st_sidewalk · st_street_lamp · st_car_70s · st_hydrant · st_mailbox · st_motel_sign
//   runtime   setTowerBeacons(game, g, on, color) (1 Hz blink / rainbow after EE step 4) · setNeon(game, g, on)
//
// TEXT GOTCHA: seen from the front (-z) the viewer's right is -x. decal() planes already read correctly; anything laid
// out as geometry (neon strokes...) must run from +x to -x (see yd_neon_wztv's X(u) = -u).
// VEHICLES (yd_news_van, st_car_70s): length along x, FRONT (cab) at -x; the van's open rear is at +x (GDD layout).
// PLACEMENT CONVENTIONS (see each prop's meta.desc):
//   floor props : kit default. Floor at y = 0, centered on x/z, FRONT = -z.
//   'wall' tag  : origin = the point ON THE WALL under the prop's bottom edge (back at z = 0, prop extends toward -z).
//                 Place with pos = [x, bottomHeight, zOnWall] and rotY so local -z points away from the wall.
//   'backdrop'  : skyline pieces (sky_*) have no colliders, low tris, rich textures; meant for 30..150 m away.
//   Ground decals (yd_puddle, yd_gravel_patch, yd_stones, yd_weeds) have no colliders.
// Light fixtures expose their glowing meshes as userData.parts.* (noMerge) so the engine can switch/flicker them;
// opts.lit = false builds them dark.

import * as K from './kit.js';
import { registerProp, registerScene, PAL, THREE } from './kit.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';
import { mulberry32 } from '../core/rng.js';
import { getCard, drawTo } from '../gfx/cards.js';

const { lerp, clamp, smoothstep } = THREE.MathUtils;
const TAU = Math.PI * 2;
const UP = new THREE.Vector3(0, 1, 0);
const CAT = 'outdoor';

// =================================================================================================== helpers
const _geo = new Map();
function cg(key, make) {
  let g = _geo.get(key);
  if (!g) { g = make(); _geo.set(key, g); }
  return g;
}
const v3 = (a) => new THREE.Vector3(a[0], a[1], a[2]);
// tinted copy (kit geometries are cached/shared: always clone before tinting)
const tc = (geo, color) => K.tint(geo.clone(), color);
// tinted mesh shortcut
const tm = (geo, mat, color, o) => K.m(color ? tc(geo, color) : geo, mat, o);
const hexMul = (hex, k) => '#' + new THREE.Color(hex).multiplyScalar(k).getHexString();
const hexMix = (a, b, t) => '#' + new THREE.Color(a).lerp(new THREE.Color(b), t).getHexString();

// transformed copy of a geometry: { pos, rot:[x,y,z], quat, scale }
function xf(geo, o = {}) {
  const g = geo.clone();
  const q = o.quat || new THREE.Quaternion().setFromEuler(new THREE.Euler(...(o.rot || [0, 0, 0])));
  const s = o.scale === undefined ? new THREE.Vector3(1, 1, 1) : typeof o.scale === 'number' ? new THREE.Vector3(o.scale, o.scale, o.scale) : v3(o.scale);
  g.applyMatrix4(new THREE.Matrix4().compose(o.pos ? v3(o.pos) : new THREE.Vector3(), q, s));
  return g;
}

// merges geometries with mixed attributes/indexing into one (position, normal, uv, color, index)
function mergeList(geos) {
  const list = geos.filter(Boolean).map((g0) => {
    const g = new THREE.BufferGeometry();
    const n = g0.attributes.position.count;
    if (!g0.attributes.normal) g0.computeVertexNormals();
    g.setAttribute('position', g0.attributes.position);
    g.setAttribute('normal', g0.attributes.normal);
    g.setAttribute('uv', g0.attributes.uv || new THREE.BufferAttribute(new Float32Array(n * 2), 2));
    g.setAttribute('color', g0.attributes.color || new THREE.BufferAttribute(new Float32Array(n * 3).fill(1), 3));
    g.setIndex(g0.index ? g0.index : [...Array(n).keys()]);
    return g;
  });
  return mergeGeometries(list, false);
}

// 44-tri chamfered box (flat bevels read as soft edges at small/medium sizes). UVs 0..1 per face.
function cbox(w, h, d, c = 0.006) {
  return cg(`cbox|${w.toFixed(4)}|${h.toFixed(4)}|${d.toFixed(4)}|${c}`, () => {
    const hx = w / 2, hy = h / 2, hz = d / 2;
    const cc = Math.min(c, hx * 0.45, hy * 0.45, hz * 0.45);
    const pts = [];
    for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) {
      pts.push(new THREE.Vector3(sx * hx, sy * (hy - cc), sz * (hz - cc)), new THREE.Vector3(sx * (hx - cc), sy * hy, sz * (hz - cc)),
        new THREE.Vector3(sx * (hx - cc), sy * (hy - cc), sz * hz));
    }
    const g = new ConvexGeometry(pts);
    const p = g.attributes.position, n = g.attributes.normal;
    const uv = new Float32Array(p.count * 2);
    for (let i = 0; i < p.count; i++) {
      const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i)), az = Math.abs(n.getZ(i));
      const x = p.getX(i) / w + 0.5, y = p.getY(i) / h + 0.5, z = p.getZ(i) / d + 0.5;
      let u, v;
      if (az >= ax && az >= ay) { u = n.getZ(i) < 0 ? 1 - x : x; v = y; }
      else if (ax >= ay) { u = n.getX(i) > 0 ? 1 - z : z; v = y; }
      else { u = x; v = n.getY(i) > 0 ? 1 - z : z; }
      uv[i * 2] = u; uv[i * 2 + 1] = v;
    }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    return g;
  });
}

// basis that maps +y to (b - a) and +z toward `nrm` (projected), origin at a
function basis(a, b, nrm) {
  const A = v3(a), B = v3(b);
  const dir = B.clone().sub(A);
  const len = dir.length();
  dir.normalize();
  let z = nrm ? v3(nrm) : new THREE.Vector3(0, 0, 1);
  z.addScaledVector(dir, -z.dot(dir));
  if (z.lengthSq() < 1e-6) { z = new THREE.Vector3(1, 0, 0.3); z.addScaledVector(dir, -z.dot(dir)); }
  z.normalize();
  const x = new THREE.Vector3().crossVectors(dir, z);
  return { m: new THREE.Matrix4().makeBasis(x, dir, z).setPosition(A), len };
}
// flat bar / beam from a to b (w across, d thick along nrm), baked into a geometry
function beamGeo(w, d, a, b, nrm, c = 0.006) {
  const { m, len } = basis(a, b, nrm);
  const g = cbox(w, len, d, c).clone();
  g.translate(0, len / 2, 0);
  g.applyMatrix4(m);
  return g;
}
// open (or capped) round pipe from a to b, baked
function pipeGeo(r, a, b, radial = 8, caps = false, rb = r) {
  const { m, len } = basis(a, b);
  const g = new THREE.CylinderGeometry(r, rb, len, radial, 1, !caps);
  g.translate(0, len / 2, 0);
  g.applyMatrix4(m);
  return g;
}
// any +y-growing geometry (cyl/lathe, base at 0) placed from a toward b
function alongGeo(geo, a, b, nrm) {
  const { m } = basis(a, b, nrm);
  return geo.clone().applyMatrix4(m);
}
// mesh with its local +y pointing from a to b
function span(geo, mat, a, b) {
  const A = v3(a), B = v3(b);
  const msh = K.m(geo, mat);
  msh.position.copy(A);
  msh.quaternion.setFromUnitVectors(UP, B.sub(A).normalize());
  return msh;
}
function rod(r, a, b, mat, o = {}) {
  const len = v3(a).distanceTo(v3(b));
  const g = K.cyl(r, o.rb ?? r, len, { seg: o.seg ?? 10, bevel: o.bevel ?? Math.min(0.004, r * 0.4) });
  return span(o.color ? tc(g, o.color) : g, mat, a, b);
}

function ring(r, n, y = 0, a0 = 0, a1 = TAU, closed = true) {
  const pts = [];
  const cnt = closed ? n : n + 1;
  for (let i = 0; i < cnt; i++) { const a = a0 + (i / n) * (a1 - a0); pts.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
  return pts;
}
function puck(r, h, round = 0.02, seg = 24) {
  return K.lathe([[0, 0], [r, 0], [r, h], [0, h]], { round: Math.min(round, h / 2 - 1e-3, r / 2), seg, steps: 2 });
}
// lathe with UVs u = angle, v = y / vh (so painted bands/labels line up with the profile heights)
function latheY(profile, seg = 24, vh = null) {
  const g = new THREE.LatheGeometry(profile.map(([x, y]) => new THREE.Vector2(Math.max(0, x), y)), seg);
  const p = g.attributes.position, uv = g.attributes.uv;
  const top = vh ?? Math.max(...profile.map((q) => q[1]));
  for (let i = 0; i < p.count; i++) {
    uv.setY(i, p.getY(i) / top);
  }
  return g;
}

// flat decal facing -z (reads correctly from the front); rect = [u0, v0, u1, v1]
function decal(w, h, rect = null) {
  const g = new THREE.PlaneGeometry(w, h);
  g.rotateY(Math.PI);
  if (rect) K.uvRect(g, ...rect);
  return g;
}
// flat decal facing +y (ground), rect as above; u along +x, v along -z
function groundDecal(w, d, rect = null) {
  const g = new THREE.PlaneGeometry(w, d);
  g.rotateX(-Math.PI / 2);
  if (rect) K.uvRect(g, ...rect);
  return g;
}

// soft blurred glow card texture of polylines (for neon halos): strokes in [-1,1] units of the card
function haloTex(key, strokes, { w = 256, h = 128, blur = 10, width = 14, circles = [] } = {}) {
  return K.tex.canvas(`out_halo|${key}`, w, h, (ctx) => {
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h);
    ctx.filter = `blur(${blur}px)`;
    ctx.strokeStyle = '#fff'; ctx.lineWidth = width; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    for (const st of strokes) {
      ctx.beginPath();
      st.forEach(([x, y], j) => { const px = (x * 0.5 + 0.5) * w, py = (0.5 - y * 0.5) * h; if (j) ctx.lineTo(px, py); else ctx.moveTo(px, py); });
      ctx.stroke();
    }
    for (const [cx, cy, r] of circles) { ctx.beginPath(); ctx.arc((cx * 0.5 + 0.5) * w, (0.5 - cy * 0.5) * h, r * w * 0.5, 0, TAU); ctx.stroke(); }
    ctx.filter = 'none';
  }, { repeat: false });
}

// transparent stencil/decal atlas painter: cells drawn by fn(ctx, x, y, w, h, i)
function atlasTex(key, w, h, draw, fonts = true) {
  return K.tex.canvas(`out_atlas|${key}`, w, h, draw, { repeat: false, fonts });
}
function font(ctx, px, face = 'Bungee') { ctx.font = `${px}px "${face}", "Arial Black", sans-serif`; }
function fitText(ctx, text, maxW, px, face = 'Bungee') {
  font(ctx, px, face);
  while (ctx.measureText(text).width > maxW && px > 6) { px *= 0.94; font(ctx, px, face); }
  return px;
}
// rough spray-paint stencil: text with gaps (stencil bridges) and soft overspray
function stencilText(ctx, text, x, y, px, color, face = 'Bungee', rand = Math.random) {
  ctx.save();
  font(ctx, px, face);
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillStyle = color;
  ctx.globalAlpha = 0.18; ctx.filter = 'blur(2px)'; ctx.fillText(text, x, y);
  ctx.filter = 'none'; ctx.globalAlpha = 0.92; ctx.fillText(text, x, y);
  // stencil bridges + chips
  ctx.globalCompositeOperation = 'destination-out';
  const tw = ctx.measureText(text).width;
  for (let i = 0; i < text.length; i++) {
    const cx = x - tw / 2 + (i + 0.5) * (tw / text.length);
    ctx.fillRect(cx - px * 0.03, y - px * 0.55, px * 0.06, px * 0.22);
  }
  for (let i = 0; i < 40; i++) { ctx.globalAlpha = 0.3 + rand() * 0.6; ctx.beginPath(); ctx.arc(x + (rand() - 0.5) * tw, y + (rand() - 0.5) * px, 0.5 + rand() * 2.2, 0, TAU); ctx.fill(); }
  ctx.restore();
}
function grime(ctx, w, h, rand, n = 40, color = '#2A1E14', alpha = 0.08) {
  ctx.save();
  for (let i = 0; i < n; i++) {
    ctx.globalAlpha = alpha * (0.4 + rand());
    ctx.fillStyle = color;
    ctx.beginPath(); ctx.ellipse(rand() * w, rand() * h, 4 + rand() * 30, 3 + rand() * 18, rand() * 3, 0, TAU); ctx.fill();
  }
  ctx.restore();
}
function rustStreaks(ctx, x0, y0, w, h, rand, n = 10, color = '#8A4A22') {
  ctx.save();
  for (let i = 0; i < n; i++) {
    const x = x0 + rand() * w, len = h * (0.2 + rand() * 0.8), wd = 1 + rand() * 4;
    const gr = ctx.createLinearGradient(0, y0, 0, y0 + len);
    gr.addColorStop(0, color); gr.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.globalAlpha = 0.25 + rand() * 0.35;
    ctx.fillStyle = gr;
    ctx.fillRect(x, y0, wd, len);
  }
  ctx.restore();
}

// planar box-projected wood UVs with a per-plank offset (variation), grain along the plank length
function woodUV(geo, perM, alongX, rand) {
  const g = K.uvBox(geo, perM, { swap: alongX });
  const du = rand ? rand() * 7 : 0, dv = rand ? rand() * 7 : 0;
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) + du, uv.getY(i) + dv);
  return g;
}

// lumpy stone: subdivided icosahedron, noise-displaced, flattened
function stoneGeo(r, seed, flat = 0.55) {
  const rnd = mulberry32(seed * 131 + 7);
  const g = new THREE.IcosahedronGeometry(r, 1);
  const p = g.attributes.position;
  const ph = [rnd() * 6, rnd() * 6, rnd() * 6];
  const vtx = new THREE.Vector3();
  const seen = new Map();
  for (let i = 0; i < p.count; i++) {
    vtx.fromBufferAttribute(p, i);
    const k = `${vtx.x.toFixed(4)},${vtx.y.toFixed(4)},${vtx.z.toFixed(4)}`;
    let s = seen.get(k);
    if (s === undefined) {
      const n = vtx.clone().normalize();
      s = 1 + 0.18 * Math.sin(n.x * 3.1 + ph[0]) * Math.cos(n.z * 2.7 + ph[1]) + 0.1 * Math.sin(n.y * 4.3 + ph[2]) + (rnd() - 0.5) * 0.08;
      seen.set(k, s);
    }
    p.setXYZ(i, vtx.x * s, vtx.y * s * flat, vtx.z * s * (0.8 + 0.2 * Math.cos(ph[0])));
  }
  g.computeVertexNormals();
  K.weldNormals(g);
  return g;
}

// smooth random blob outline (closed), radius ~r, n points
function blob(r, seed, n = 28, wob = 0.22, sx = 1, sz = 1) {
  const rnd = mulberry32(seed * 977 + 3);
  const a1 = rnd() * 6, a2 = rnd() * 6, a3 = rnd() * 6;
  const pts = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * TAU;
    const k = 1 + wob * (0.55 * Math.sin(a * 2 + a1) + 0.3 * Math.sin(a * 3 + a2) + 0.15 * Math.sin(a * 5 + a3));
    pts.push(new THREE.Vector2(Math.cos(a) * r * k * sx, Math.sin(a) * r * k * sz));
  }
  return pts;
}

// shared colors
const C = {
  red: '#D8402F', white: '#F2EEE4', blue: PAL.wztvBlue, cream: PAL.cream, gold: PAL.harvestGold, orange: PAL.burntOrange,
  avocado: PAL.avocado, choc: PAL.chocolate, galv: '#AEB5BE', galvDark: '#7E8792', concrete: '#B9B2A6', concreteDark: '#8E877D',
  rubber: '#2A2430', ink: '#241A2E', pine: '#C99A5E', sodium: PAL.sodium, pink: PAL.neonPink, plum: PAL.plum,
};

// =================================================================================================== OIL DRUMS
const DRUM_STYLES = {
  blue: { c: '#2F5BD3', label: 'wztv', ink: '#F4F1E8' },
  red: { c: '#C8382E', label: 'flammable', ink: '#F4F1E8' },
  yellow: { c: '#E8A92E', label: 'caution', ink: '#2A1D3A' },
  green: { c: '#6E8A3A', label: 'diesel', ink: '#F4F1E8' },
  orange: { c: '#E3662B', label: 'wztv', ink: '#2A1D3A' },
  black: { c: '#3A3444', label: 'oil', ink: '#E8A92E' },
};
const DR = 0.29, DH = 0.88;
function drumTex(style) {
  const st = DRUM_STYLES[style] || DRUM_STYLES.blue;
  return K.tex.canvas(`out_drum|${style}`, 512, 320, (ctx, w, h, rand) => {
    const sideH = h * 0.8; // v 0..0.8 = side (y/H), v 0.8..1 = lid tile (canvas top 64 px)
    // side (canvas y is flipped: v=1 at the top of the canvas)
    const y0 = h - sideH;
    ctx.fillStyle = st.c; ctx.fillRect(0, y0, w, sideH);
    for (let i = 0; i < 26; i++) { ctx.globalAlpha = 0.08 + rand() * 0.08; ctx.fillStyle = rand() < 0.5 ? '#000' : '#fff'; ctx.fillRect(rand() * w, y0, 2 + rand() * 18, sideH); }
    ctx.globalAlpha = 1;
    // label panel on the front (u ~ 0.25 faces -z with the lathe seam at +z... see drumParts: rotated so u=0.5 is front)
    const cx = w * 0.5, cy = y0 + sideH * 0.5;
    ctx.save();
    if (st.label === 'wztv') {
      ctx.fillStyle = st.ink; ctx.globalAlpha = 0.95;
      ctx.beginPath(); ctx.arc(cx, cy - 40, 30, 0, TAU); ctx.fill();
      ctx.fillStyle = st.c; font(ctx, 30); ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('13', cx, cy - 38);
      stencilText(ctx, 'WZTV', cx, cy + 10, 34, st.ink, 'Bungee', rand);
      stencilText(ctx, 'PROPERTY', cx, cy + 42, 18, st.ink, 'Bungee', rand);
    } else if (st.label === 'flammable') {
      ctx.translate(cx, cy - 8); ctx.rotate(Math.PI / 4);
      ctx.fillStyle = '#F4F1E8'; ctx.fillRect(-44, -44, 88, 88);
      ctx.fillStyle = '#C8382E'; ctx.fillRect(-38, -38, 76, 76);
      ctx.rotate(-Math.PI / 4);
      ctx.fillStyle = '#F4F1E8';
      ctx.beginPath(); ctx.moveTo(0, -30); ctx.bezierCurveTo(18, -8, 16, 8, 0, 18); ctx.bezierCurveTo(-16, 8, -14, -6, -4, -14); ctx.bezierCurveTo(-4, -2, 4, -2, 0, -30); ctx.fill();
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      stencilText(ctx, 'FLAMMABLE', cx, cy + 62, 20, st.ink, 'Bungee', rand);
    } else if (st.label === 'caution') {
      for (let i = -6; i < 7; i++) { ctx.fillStyle = '#2A1D3A'; ctx.beginPath(); ctx.moveTo(cx + i * 22, y0 + 18); ctx.lineTo(cx + i * 22 + 11, y0 + 18); ctx.lineTo(cx + i * 22 + 1, y0 + 34); ctx.lineTo(cx + i * 22 - 10, y0 + 34); ctx.fill(); }
      stencilText(ctx, 'CAUTION', cx, cy - 4, 34, st.ink, 'Bungee', rand);
      stencilText(ctx, 'STAGE FOG', cx, cy + 30, 18, st.ink, 'Bungee', rand);
    } else if (st.label === 'diesel') {
      stencilText(ctx, 'DIESEL', cx, cy - 12, 38, st.ink, 'Bungee', rand);
      stencilText(ctx, 'GENERATOR 2', cx, cy + 24, 17, st.ink, 'Bungee', rand);
    } else {
      stencilText(ctx, 'MOTOR OIL', cx, cy - 8, 28, st.ink, 'Bungee', rand);
      stencilText(ctx, 'SAE 30', cx, cy + 24, 18, st.ink, 'Bungee', rand);
    }
    ctx.restore();
    // small back stencil
    stencilText(ctx, '55 GAL', w * 0.02 + 40, cy + 60, 14, st.ink, 'Bungee', rand);
    stencilText(ctx, '55 GAL', w * 0.98 - 40, cy + 60, 14, st.ink, 'Bungee', rand);
    // rust at the chimes/hoops (y/H 0.0, 0.33, 0.67, 1.0)
    const vy = (t) => h - t * sideH;
    rustStreaks(ctx, 0, vy(1) + 2, w, sideH * 0.35, rand, 26, '#7A3A1A');
    rustStreaks(ctx, 0, vy(0.67), w, sideH * 0.2, rand, 12, '#7A3A1A');
    rustStreaks(ctx, 0, vy(0.33), w, sideH * 0.2, rand, 12, '#7A3A1A');
    ctx.save(); ctx.globalAlpha = 0.5; ctx.fillStyle = '#5A3420'; ctx.fillRect(0, vy(0.03), w, sideH * 0.03); ctx.restore();
    grime(ctx, w, sideH, rand, 30, '#20141C', 0.06);
    // lid tile (top 64 px): paint with concentric pressing rings
    ctx.fillStyle = st.c; ctx.fillRect(0, 0, w, h - sideH);
    ctx.globalAlpha = 0.15; ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, 4); ctx.globalAlpha = 1;
    grime(ctx, w, h - sideH, rand, 10, '#20141C', 0.1);
  });
}
// adds one drum's geometry into the geos map under a transform (so groups bake/merge once)
function drumParts(out, style, xform, seed = 1, o = {}) {
  const rnd = mulberry32(seed * 91 + 5);
  const prof = [[0, 0.012], [0.262, 0.006], [0.279, 0.0], [0.291, 0.012], [0.292, 0.028], [0.284, 0.036],
    [0.284, 0.272], [0.294, 0.283], [0.294, 0.301], [0.284, 0.312],
    [0.284, 0.566], [0.294, 0.577], [0.294, 0.595], [0.284, 0.606],
    [0.284, 0.846], [0.291, 0.853], [0.293, 0.868], [0.284, 0.88], [0.272, 0.875], [0.266, 0.862]];
  const side = latheY(prof, 30, DH / 0.8);
  // dents (seeded): push vertices inward near a random point on the side
  const p = side.attributes.position;
  const dents = [];
  for (let i = 0; i < (o.dents ?? 2); i++) dents.push([rnd() * TAU, 0.15 + rnd() * 0.6, 0.02 + rnd() * 0.025]);
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const rr = Math.hypot(x, z);
    if (rr < 0.2) continue;
    const a = Math.atan2(x, z);
    let k = 0;
    for (const [da, dy, dd] of dents) {
      let dA = Math.abs(a - da); dA = Math.min(dA, TAU - dA);
      const d2 = (dA * DR) ** 2 + (y - dy) ** 2;
      k += dd * Math.exp(-d2 / 0.006);
    }
    if (k > 0) { const s = (rr - k) / rr; p.setX(i, x * s); p.setZ(i, z * s); }
  }
  side.computeVertexNormals();
  K.weldNormals(side);
  // lid: flat disc with planar UVs into the lid tile (v 0.8..1)
  const lid = new THREE.CircleGeometry(0.268, 30);
  lid.rotateX(-Math.PI / 2);
  lid.translate(0, 0.862, 0);
  const luv = lid.attributes.uv, lp = lid.attributes.position;
  for (let i = 0; i < luv.count; i++) luv.setXY(i, 0.1 + (lp.getX(i) / 0.6 + 0.5) * 0.3, 0.82 + (lp.getZ(i) / 0.6 + 0.5) * 0.16);
  // rotate so the label (u = 0.5) faces -z: lathe u=0 is at +z (sin/cos), u=0.5 at -z already
  out.body.push(xf(side, xform), xf(lid, xform));
  // bungs (2" and 3/4") + a pressed ring on the lid
  out.metal.push(xf(K.cyl(0.035, 0.038, 0.018, { seg: 12, bevel: 0.005 }).clone().translate(0.16, 0.862, -0.06), xform));
  out.metal.push(xf(K.cyl(0.018, 0.02, 0.014, { seg: 10, bevel: 0.004 }).clone().translate(-0.17, 0.862, 0.08), xform));
  out.body.push(xf(new THREE.TorusGeometry(0.2, 0.006, 4, 30).rotateX(Math.PI / 2).translate(0, 0.863, 0), xform));
}
function drumMats(game, styles) {
  const body = {};
  for (const s of styles) body[s] = K.mat(game, 'lacquer', '#ffffff', { map: drumTex(s), rough: 0.44 });
  return { body, metal: K.mat(game, 'metal', '#9AA0A8') };
}
function drumXform(pos, rotY = 0, tipped = false) {
  if (!tipped) return { pos, rot: [0, rotY, 0] };
  // lying on its side along local x (rolled a bit so the label shows)
  const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, rotY, 0));
  q.multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(0.35, 0, Math.PI / 2)));
  const off = new THREE.Vector3(0, DH / 2, 0).applyQuaternion(q);
  return { pos: [pos[0] - off.x, 0.293, pos[2] - off.z], quat: q };
}
function addDrum(g, M, style, xform, seed, o) {
  const out = { body: [], metal: [] };
  drumParts(out, style, xform, seed, o);
  g.add(K.m(mergeList(out.body), M.body[style]));
  g.add(K.m(mergeList(out.metal), M.metal));
}

registerProp('yd_oil_drum', (game, opts = {}) => {
  const g = K.prop('yd_oil_drum');
  const style = DRUM_STYLES[opts.color] ? opts.color : 'blue';
  const M = drumMats(game, [style]);
  const tipped = !!opts.tipped;
  addDrum(g, M, style, drumXform([0, 0, 0], 0, tipped), opts.seed ?? 1, { dents: opts.dents });
  g.userData.colliders = tipped ? [{ min: [-DH / 2, 0, -DR], max: [DH / 2, DR * 2, DR] }] : [{ min: [-DR, 0, -DR], max: [DR, DH, DR] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['yard', 'drum', 'clutter'], size: [0.59, 0.88, 0.59], desc: '55-gal steel drum, painted + stenciled, dents and rust (opts.color blue|red|yellow|green|orange|black, opts.tipped, opts.seed)' });

registerProp('yd_drum_group', (game, opts = {}) => {
  const g = K.prop('yd_drum_group');
  const set = opts.set === 'b' ? ['red', 'yellow', 'black', 'red'] : ['blue', 'green', 'orange', 'blue'];
  const M = drumMats(game, [...new Set(set)]);
  // wooden pallet under the two standing drums
  const wood = K.mat(game, 'teak', '#ffffff', { map: K.tex.wood('#A87A48', { dark: 0.4, wear: 0.4 }) });
  const rnd = mulberry32(51);
  const PW = 1.2, PD = 1.0, px = -0.18, pz = 0.08;
  for (let i = 0; i < 7; i++) g.add(K.m(woodUV(cbox(PW, 0.022, 0.12, 0.004), 1.4, true, rnd), wood, { pos: [px, 0.133, pz - PD / 2 + 0.06 + i * ((PD - 0.12) / 6)] }));
  for (const s of [-1, 0, 1]) g.add(K.m(woodUV(cbox(0.1, 0.1, PD, 0.006), 1.4, false, rnd), wood, { pos: [px + s * (PW / 2 - 0.05), 0.072, pz] }));
  for (let i = 0; i < 3; i++) g.add(K.m(woodUV(cbox(PW, 0.022, 0.1, 0.004), 1.4, true, rnd), wood, { pos: [px, 0.011, pz - PD / 2 + 0.05 + i * ((PD - 0.1) / 2)] }));
  const top = 0.144;
  addDrum(g, M, set[0], { pos: [px - 0.3, top, pz + 0.18], rot: [0, 0.4, 0] }, 3);
  addDrum(g, M, set[1], { pos: [px + 0.3, top, pz + 0.16], rot: [0, -1.1, 0] }, 4);
  addDrum(g, M, set[2], { pos: [px + 0.05, top, pz - 0.28], rot: [0, 2.6, 0] }, 5, { dents: 1 });
  // one tipped over in front, rolled away
  addDrum(g, M, set[3], drumXform([0.55, 0, -0.62], -0.5, true), 6, { dents: 3 });
  g.userData.colliders = [
    { min: [px - PW / 2, 0, pz - PD / 2], max: [px + PW / 2, top + DH, pz + PD / 2] },
    { min: [0.05, 0, -1.05], max: [1.05, DR * 2, -0.2] },
  ];
  return K.finish(game, g);
}, { category: CAT, tags: ['yard', 'drum', 'clutter', 'group'], size: [1.9, 1.03, 1.6], desc: 'three drums on a pallet + one tipped over (opts.set a|b)' });

// =================================================================================================== CRATES
const CRATE_SIZES = { lg: [1.2, 0.9, 0.9], md: [0.9, 0.7, 0.7], sm: [0.6, 0.45, 0.5], long: [1.8, 0.5, 0.6] };
function crateStencils() {
  // 4x2 atlas of transparent stencils (256x128 each)
  return atlasTex('crate_stencils', 1024, 256, (ctx, W, H) => {
    const rand = mulberry32(77);
    const cell = (i, f) => { ctx.save(); ctx.translate((i % 4) * 256, Math.floor(i / 4) * 128); f(); ctx.restore(); };
    const ink = '#2A1D2A', red = '#B8332A', blue = '#2A4AA8';
    cell(0, () => { stencilText(ctx, 'WZTV-13', 128, 52, 46, ink, 'Bungee', rand); stencilText(ctx, 'CHANNEL 13 · TRI-COUNTY', 128, 96, 15, ink, 'Bungee', rand); });
    cell(1, () => { ctx.strokeStyle = red; ctx.lineWidth = 6; ctx.globalAlpha = 0.9; ctx.strokeRect(22, 24, 212, 80); stencilText(ctx, 'FRAGILE', 128, 64, 42, red, 'Bungee', rand); });
    cell(2, () => {
      ctx.fillStyle = ink; ctx.globalAlpha = 0.9;
      for (const x of [88, 168]) { ctx.beginPath(); ctx.moveTo(x, 18); ctx.lineTo(x + 26, 50); ctx.lineTo(x + 10, 50); ctx.lineTo(x + 10, 84); ctx.lineTo(x - 10, 84); ctx.lineTo(x - 10, 50); ctx.lineTo(x - 26, 50); ctx.fill(); }
      stencilText(ctx, 'THIS SIDE UP', 128, 106, 17, ink, 'Bungee', rand);
    });
    cell(3, () => { stencilText(ctx, 'FILM', 128, 44, 44, blue, 'Bungee', rand); stencilText(ctx, 'KEEP DRY · KEEP COOL', 128, 92, 15, blue, 'Bungee', rand); });
    cell(4, () => {
      // wine-glass "fragile" icon
      ctx.strokeStyle = ink; ctx.lineWidth = 7; ctx.globalAlpha = 0.9; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(100, 20); ctx.quadraticCurveTo(100, 64, 128, 66); ctx.quadraticCurveTo(156, 64, 156, 20); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(128, 66); ctx.lineTo(128, 100); ctx.moveTo(108, 104); ctx.lineTo(148, 104); ctx.stroke();
    });
    cell(5, () => { stencilText(ctx, 'NO. 1313', 128, 50, 34, ink, 'Bungee', rand); stencilText(ctx, 'STUDIO B · PROPS', 128, 92, 16, ink, 'Bungee', rand); });
    cell(6, () => { stencilText(ctx, 'HANDLE', 128, 44, 34, red, 'Bungee', rand); stencilText(ctx, 'WITH CARE', 128, 88, 30, red, 'Bungee', rand); });
    cell(7, () => {
      // shipping label (paper)
      ctx.globalAlpha = 1; ctx.fillStyle = '#EFE4C8'; ctx.fillRect(40, 14, 176, 100);
      ctx.fillStyle = '#E3662B'; ctx.fillRect(40, 14, 176, 20);
      ctx.fillStyle = '#F4F1E8'; font(ctx, 13); ctx.textAlign = 'center'; ctx.fillText('RAILWAY EXPRESS', 128, 29);
      ctx.fillStyle = '#3A2A30'; font(ctx, 12, 'Titan One'); ctx.textAlign = 'left';
      ctx.fillText('TO: WZTV CH.13', 50, 54); ctx.fillText('ATTN: B. VON STATIC', 50, 74); ctx.fillText('ETERNA-VISION INC.', 50, 94);
      ctx.globalAlpha = 0.25; ctx.fillStyle = '#6A4A2A'; ctx.fillRect(40, 100, 176, 14);
    });
  });
}
function crateParts(g, M, [W, H, D], xform, seed, stencils = [0, 2, 1, 3]) {
  const rnd = mulberry32(seed * 313 + 11);
  const grp = new THREE.Group();
  if (xform.pos) grp.position.fromArray(xform.pos);
  if (xform.rot) grp.rotation.set(...xform.rot);
  g.add(grp);
  const T = 0.022; // board thickness
  const woodCols = ['#FFFFFF', '#F2E6D6', '#FFF4E4', '#E8D8C4', '#F8EEDC'];
  const wc = () => woodCols[Math.floor(rnd() * woodCols.length)];
  // dark core (reads through the gaps)
  grp.add(tm(cbox(W - 0.03, H - 0.03, D - 0.03, 0.01), M.core, null, { pos: [0, H / 2, 0] }));
  // sheathing planks: horizontal on the 4 sides, along x on the top
  const nP = Math.max(2, Math.round(H / 0.16));
  const gap = 0.012, ph = (H - 0.02 - gap * (nP - 1)) / nP;
  for (let i = 0; i < nP; i++) {
    const y = 0.01 + ph / 2 + i * (ph + gap);
    for (const s of [-1, 1]) {
      grp.add(tm(woodUV(cbox(W - 0.004, ph, T, 0.005), 1.3, true, rnd), M.wood, wc(), { pos: [0, y, s * (D / 2 - T / 2)] }));
      grp.add(tm(woodUV(cbox(T, ph, D - 2 * T - 0.004, 0.005), 1.3, true, rnd), M.wood, wc(), { pos: [s * (W / 2 - T / 2), y, 0] }));
    }
  }
  const nT = Math.max(2, Math.round(D / 0.15));
  const tp = (D - gap * (nT - 1)) / nT;
  for (let i = 0; i < nT; i++) grp.add(tm(woodUV(cbox(W, T, tp - 0.002, 0.005), 1.3, true, rnd), M.wood, wc(), { pos: [0, H - T / 2 + 0.002, -D / 2 + tp / 2 + i * (tp + gap)] }));
  // cleats (frame boards) on front/back and sides, a diagonal brace on the long faces
  const cw = 0.075, ct = 0.02;
  for (const s of [-1, 1]) {
    const z = s * (D / 2 + ct / 2 - 0.002);
    for (const x of [-1, 1]) grp.add(tm(woodUV(cbox(cw, H - 0.004, ct, 0.006), 1.3, false, rnd), M.wood, wc(), { pos: [x * (W / 2 - cw / 2), H / 2, z] }));
    for (const y of [cw / 2 + 0.002, H - cw / 2 - 0.002]) grp.add(tm(woodUV(cbox(W - 2 * cw, cw, ct, 0.006), 1.3, true, rnd), M.wood, wc(), { pos: [0, y, z] }));
    if (W > 0.8) {
      const a = [-W / 2 + cw, cw, z], b = [W / 2 - cw, H - cw, z];
      grp.add(tm(K.uvBox(beamGeo(cw, ct, a, b, [0, 0, s], 0.006), 1.3, { swap: false }), M.wood, wc()));
    }
    const x = s * (W / 2 + ct / 2 - 0.002);
    for (const zz of [-1, 1]) grp.add(tm(woodUV(cbox(ct, H - 0.004, cw, 0.006), 1.3, false, rnd), M.wood, wc(), { pos: [x, H / 2, zz * (D / 2 - cw / 2 + 0.02)] }));
    for (const y of [cw / 2 + 0.002, H - cw / 2 - 0.002]) grp.add(tm(woodUV(cbox(ct, cw, D - 2 * cw + 0.04, 0.006), 1.3, true, rnd), M.wood, wc(), { pos: [x, y, 0] }));
  }
  // steel corner caps on the top corners
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) grp.add(K.m(cbox(0.07, 0.05, 0.07, 0.008), M.metal, { pos: [sx * (W / 2 - 0.02), H - 0.02, sz * (D / 2 - 0.02)] }));
  // stencils: front (-z), right side (+x), back, top
  const cellR = (i) => [(i % 4) / 4, 1 - (Math.floor(i / 4) + 1) / 2, (i % 4 + 1) / 4, 1 - Math.floor(i / 4) / 2];
  const sw = Math.min(W - 0.2, 0.62), sh = sw / 2;
  const f = grp;
  f.add(K.m(decal(sw, sh, cellR(stencils[0])), M.sten, { pos: [rnd() * 0.06 - 0.03, H * 0.52, -D / 2 - ct - 0.004] }));
  const ss = Math.min(D - 0.18, 0.5);
  f.add(K.m(decal(ss, ss / 2, cellR(stencils[1])), M.sten, { pos: [W / 2 + ct + 0.004, H * 0.55, 0], rot: [0, -Math.PI / 2, 0] }));
  f.add(K.m(decal(sw * 0.8, sw * 0.4, cellR(stencils[2])), M.sten, { pos: [0, H * 0.5, D / 2 + ct + 0.004], rot: [0, Math.PI, 0] }));
  const lab = K.m(groundDecal(0.34, 0.17, cellR(stencils[3] ?? 7)), M.sten, { pos: [W * 0.18, H + 0.009, D * 0.1], rot: [0, 0.2, 0] });
  f.add(lab);
}
function crateMats(game) {
  return {
    wood: K.mat(game, 'teak', '#ffffff', { map: K.tex.wood('#C99A5E', { dark: 0.36, wear: 0.35 }) }),
    core: K.mat(game, 'paint', '#3A2A22'),
    metal: K.mat(game, 'metal', '#8A9098'),
    sten: K.mat(game, 'paint', '#ffffff', { map: crateStencils(), transparent: true, depthWrite: false }),
  };
}
registerProp('yd_crate', (game, opts = {}) => {
  const g = K.prop('yd_crate');
  const size = CRATE_SIZES[opts.size] || CRATE_SIZES.md;
  const M = crateMats(game);
  const seed = opts.seed ?? 1;
  const st = opts.film ? [3, 4, 1, 7] : [[0, 2, 1, 3], [5, 6, 0, 7], [0, 1, 2, 3]][seed % 3];
  crateParts(g, M, size, {}, seed, st);
  g.userData.colliders = [{ min: [-size[0] / 2 - 0.03, 0, -size[2] / 2 - 0.03], max: [size[0] / 2 + 0.03, size[1], size[2] / 2 + 0.03] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['yard', 'crate', 'clutter'], size: [0.96, 0.7, 0.76], desc: 'slatted pine shipping crate with cleats, steel corners, spray stencils (opts.size lg|md|sm|long, opts.seed, opts.film)' });

registerProp('yd_crate_stack', (game, opts = {}) => {
  const g = K.prop('yd_crate_stack');
  const M = crateMats(game);
  const [lw, lh, ld] = CRATE_SIZES.lg, [mw, mh, md] = CRATE_SIZES.md, [sw, sh, sd] = CRATE_SIZES.sm;
  crateParts(g, M, CRATE_SIZES.lg, { pos: [-0.25, 0, 0.1], rot: [0, 0.05, 0] }, 2, [0, 2, 1, 7]);
  crateParts(g, M, CRATE_SIZES.md, { pos: [-0.3, lh + 0.003, 0.15], rot: [0, -0.18, 0] }, 3, [5, 6, 0, 3]);
  crateParts(g, M, CRATE_SIZES.md, { pos: [0.72, 0, -0.05], rot: [0, 0.35, 0] }, 4, [3, 4, 1, 7]);
  crateParts(g, M, CRATE_SIZES.sm, { pos: [0.62, mh + 0.003, 0.0], rot: [0, 0.1, 0] }, 5, [1, 0, 2, 3]);
  g.userData.colliders = [
    { min: [-0.25 - lw / 2 - 0.05, 0, 0.1 - ld / 2 - 0.05], max: [-0.25 + lw / 2 + 0.05, lh + mh, 0.1 + ld / 2 + 0.05] },
    { min: [0.72 - 0.55, 0, -0.05 - 0.52], max: [0.72 + 0.55, mh + sh, -0.05 + 0.52] },
  ];
  void mw; void md; void sw; void sd;
  return K.finish(game, g);
}, { category: CAT, tags: ['yard', 'crate', 'clutter', 'group'], size: [2.2, 1.6, 1.3], desc: 'stack of four shipping crates (big + medium on top, medium + small beside)' });

// =================================================================================================== FILM CANS
function filmLabels() {
  return atlasTex('film_labels', 512, 256, (ctx) => {
    const rand = mulberry32(19);
    const labels = [['PRECINCT 13', 'REEL 2 of 3'], ['SPOOKTACULAR', 'ep. 113 · MASTER'], ["HOOTIE'S", 'PUPPET HOUR 41'], ['NEWS FILM', 'JUNE 1977'],
      ['DO NOT AIR!!', 'B.v.S.'], ['BOOGIE DOWN', 'SAT. 9PM'], ['STATION ID', '1971 · COLOR'], ['SIGN-OFF', 'ANTHEM · 16mm']];
    labels.forEach(([a, b], i) => {
      const x = (i % 4) * 128, y = Math.floor(i / 4) * 128;
      ctx.save(); ctx.translate(x + 64, y + 64); ctx.rotate((rand() - 0.5) * 0.08);
      ctx.fillStyle = i === 4 ? '#F6D84A' : '#EFE4C4'; ctx.fillRect(-60, -24, 120, 48);
      ctx.globalAlpha = 0.18; ctx.fillStyle = '#7A5A30'; ctx.fillRect(-60, 16, 120, 8); ctx.fillRect(-60, -24, 4, 48); ctx.globalAlpha = 1;
      ctx.fillStyle = i === 4 ? '#C8201E' : '#2A2A6A'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      fitText(ctx, a, 108, 17, 'Titan One'); ctx.fillText(a, 0, -8);
      fitText(ctx, b, 108, 12, 'Titan One'); ctx.fillStyle = '#5A3A3A'; ctx.fillText(b, 0, 12);
      ctx.restore();
    });
  });
}
function reelTex() {
  return K.tex.canvas('out_film_reel', 256, 256, (ctx, w) => {
    ctx.fillStyle = '#000'; ctx.clearRect(0, 0, w, w);
    const c = w / 2;
    // film pack (brown) + silver 3-spoke reel flange with holes
    ctx.fillStyle = '#5A3424'; ctx.beginPath(); ctx.arc(c, c, c * 0.8, 0, TAU); ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.25)'; ctx.lineWidth = 1;
    for (let r = c * 0.3; r < c * 0.8; r += 3) { ctx.beginPath(); ctx.arc(c, c, r, 0, TAU); ctx.stroke(); }
    ctx.fillStyle = '#C8CDD4'; ctx.beginPath(); ctx.arc(c, c, c * 0.3, 0, TAU); ctx.fill();
    ctx.fillStyle = '#8A9098'; ctx.beginPath(); ctx.arc(c, c, c * 0.08, 0, TAU); ctx.fill();
  }, { repeat: false });
}
registerProp('yd_film_cans', (game, opts = {}) => {
  const g = K.prop('yd_film_cans');
  const rnd = mulberry32((opts.seed ?? 1) * 7 + 2);
  const tin = K.mat(game, 'metal', '#ffffff', { rough: 0.38 });
  const lab = K.mat(game, 'paint', '#ffffff', { map: filmLabels(), rough: 0.8 });
  const film = K.mat(game, 'plastic', '#ffffff', { map: reelTex(), rough: 0.5 });
  const R0 = 0.19, HC = 0.052;
  const prof = [[0, 0], [0.176, 0], [0.188, 0.007], [0.188, 0.036], [0.195, 0.039], [0.195, HC - 0.004], [0.186, HC], [0, HC]];
  const canGeo = cg('film_can', () => K.lathe(prof, { seg: 20 }));
  const canCols = ['#C9CED6', '#B8BEC6', '#D9463A', '#3A6AC8', '#D8A030', '#C9CED6', '#7FA05A', '#B8BEC6'];
  const geos = [], lgeos = [];
  let li = 0;
  const addCan = (x, y, z, rx, ry, rz, col, withLabel = true) => {
    const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz));
    geos.push(K.tint(xf(canGeo, { pos: [x, y, z], quat: q }), col));
    if (withLabel) {
      const i = li++ % 8;
      const d = groundDecal(0.16, 0.064, [(i % 4) / 4, 1 - (Math.floor(i / 4) + 1) / 2, (i % 4 + 1) / 4, 1 - Math.floor(i / 4) / 2]);
      d.rotateY((rnd() - 0.5) * 0.6);
      d.translate(0, HC + 0.0015, 0.04);
      lgeos.push(xf(d, { pos: [x, y, z], quat: q }));
    }
  };
  // three stacks, slightly askew
  const stacks = [[-0.28, 0.12, 6], [0.2, 0.2, 4], [0.05, -0.28, 3]];
  stacks.forEach(([sx, sz, n], si) => {
    for (let i = 0; i < n; i++) {
      const top = i === n - 1;
      addCan(sx + (rnd() - 0.5) * 0.04, i * (HC + 0.001), sz + (rnd() - 0.5) * 0.04, 0, rnd() * TAU, (rnd() - 0.5) * 0.02, canCols[(si * 3 + i) % canCols.length], top || rnd() < 0.3);
    }
  });
  // one leaning against the tall stack, one flat on the floor, open, with its reel
  addCan(-0.28 + 0.26, 0.19, 0.12 - 0.02, 0, 0.3, 1.2, '#D9463A');
  const ox = 0.46, oz = -0.2;
  // open can: bottom tray + lid leaning off to the side
  geos.push(K.tint(xf(K.lathe([[0, 0], [0.176, 0], [0.188, 0.007], [0.188, 0.034], [0.18, 0.036], [0.18, 0.006], [0, 0.006]], { seg: 20 }), { pos: [ox, 0, oz] }), '#B8BEC6'));
  geos.push(K.tint(xf(canGeo, { pos: [ox + 0.28, 0.012, oz + 0.14], rot: [0.25, 0.5, -0.06] }), '#B8BEC6'));
  // reel in the open tray
  const reel = new THREE.CircleGeometry(0.17, 28);
  reel.rotateX(-Math.PI / 2);
  const ruv = reel.attributes.uv;
  void ruv;
  g.add(K.m(reel, film, { pos: [ox, 0.03, oz] }));
  g.add(tm(K.cyl(0.17, 0.17, 0.022, { seg: 24, bevel: 0.004 }), tin, '#4A2A1E', { pos: [ox, 0.007, oz] }));
  // a loop of film spilling out: ribbon along a curve with sprocket texture
  const filmTex = K.tex.canvas('out_film_strip', 64, 256, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = '#3A2418'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#7A4A2A'; for (let y = 8; y < h; y += 42) ctx.fillRect(12, y, w - 24, 32);
    ctx.fillStyle = 'rgba(0,0,0,1)'; ctx.globalCompositeOperation = 'destination-out';
    for (let y = 2; y < h; y += 10) { ctx.fillRect(2, y, 6, 5); ctx.fillRect(w - 8, y, 6, 5); }
  });
  const curve = new THREE.CatmullRomCurve3([[ox - 0.12, 0.028, oz - 0.08], [ox - 0.3, 0.004, oz - 0.2], [ox - 0.12, 0.004, oz - 0.42], [ox + 0.16, 0.05, oz - 0.36], [ox + 0.1, 0.004, oz - 0.2], [ox + 0.36, 0.004, oz - 0.3]].map((p) => v3(p)));
  const N = 40, wF = 0.035;
  const pos = [], uvs = [], idx = [];
  for (let i = 0; i <= N; i++) {
    const t = i / N, pt = curve.getPoint(t), tan = curve.getTangent(t);
    const side = new THREE.Vector3(-tan.z, 0, tan.x).normalize().multiplyScalar(wF / 2);
    const tw = Math.sin(t * 5) * 0.6;
    const lift = new THREE.Vector3(0, Math.abs(Math.sin(tw)) * wF * 0.5, 0);
    pos.push(pt.x + side.x * Math.cos(tw), pt.y + 0.002 + lift.y, pt.z + side.z * Math.cos(tw), pt.x - side.x * Math.cos(tw), pt.y + 0.002 - lift.y + 0.004, pt.z - side.z * Math.cos(tw));
    uvs.push(0, t * 12, 1, t * 12);
    if (i < N) { const a = i * 2; idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3); }
  }
  const rib = new THREE.BufferGeometry();
  rib.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  rib.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  rib.setIndex(idx); rib.computeVertexNormals();
  const ribMesh = K.m(rib, K.mat(game, 'plastic', '#ffffff', { map: filmTex, alphaTest: 0.5, side: THREE.DoubleSide, rough: 0.3 }));
  ribMesh.userData.noOcclude = true;
  g.add(ribMesh);
  g.add(K.m(mergeList(geos), tin));
  g.add(K.m(mergeList(lgeos), lab));
  g.userData.colliders = [{ min: [-0.5, 0, -0.5], max: [0.4, 0.34, 0.42] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['yard', 'film', 'clutter', 'tabletop'], size: [1.2, 0.34, 1.0], desc: 'pile of 35mm film cans: askew stacks, taped labels, an open can with reel and a spilled film loop (opts.seed)' });

// =================================================================================================== GRAVEL DETAILS
const STONE_COLS = ['#9C958C', '#B4ADA2', '#8A8480', '#A89A88', '#C2B8A8', '#8E8A94', '#A8846A'];
registerProp('yd_stones', (game, opts = {}) => {
  const g = K.prop('yd_stones');
  const seed = opts.seed ?? 1;
  const rnd = mulberry32(seed * 37 + 1);
  const mat = K.mat(game, 'paint', '#ffffff', { rough: 0.85 });
  const geos = [];
  const n = opts.count ?? 14;
  const R = opts.radius ?? 0.7;
  for (let i = 0; i < n; i++) {
    const big = i < 3;
    const r = big ? 0.09 + rnd() * 0.08 : 0.025 + rnd() * 0.04;
    const a = rnd() * TAU, d = Math.sqrt(rnd()) * R * (big ? 0.5 : 1);
    const s = stoneGeo(r, seed * 50 + i, big ? 0.6 : 0.5 + rnd() * 0.25);
    const col = STONE_COLS[Math.floor(rnd() * STONE_COLS.length)];
    geos.push(K.tint(xf(s, { pos: [Math.cos(a) * d, r * 0.18, Math.sin(a) * d], rot: [(rnd() - 0.5) * 0.4, rnd() * TAU, (rnd() - 0.5) * 0.4] }), col));
  }
  g.add(K.m(mergeList(geos), mat));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { dist: 0.12 } });
}, { category: CAT, tags: ['yard', 'ground', 'decal'], size: [1.4, 0.12, 1.4], desc: 'cluster of chunky gravel stones and pebbles, no collider (opts.seed, opts.count, opts.radius)' });

registerProp('yd_puddle', (game, opts = {}) => {
  const g = K.prop('yd_puddle');
  const seed = opts.seed ?? 1, r = opts.size ?? 0.8;
  const water = K.mat(game, 'crt', '#262A52', { rough: 0.34, env: 0.12, rim: 0.5, rimColor: '#9FB6FF', rimPower: 3 });   // rough enough that a nearby lamp gives a glint, not a white disc
  const wet = K.mat(game, 'paint', '#ffffff', { map: K.tex.canvas('out_wet_rim', 128, 128, (ctx, w, h) => {
    const gr = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
    gr.addColorStop(0, 'rgba(40,34,52,1)'); gr.addColorStop(0.72, 'rgba(46,40,58,0.9)'); gr.addColorStop(1, 'rgba(46,40,58,0)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h);
  }, { repeat: false }), transparent: true, depthWrite: false, rough: 0.7 });
  const sh = new THREE.Shape(blob(r, seed, 36, 0.25, 1.25, 0.85));
  const wg = new THREE.ShapeGeometry(sh, 2);
  wg.rotateX(-Math.PI / 2);
  // wet dark margin: a soft disc under the water
  const mg = new THREE.PlaneGeometry(r * 3.3, r * 2.4);
  mg.rotateX(-Math.PI / 2);
  const mm = K.m(mg, wet, { pos: [0, 0.004, 0] });
  mm.userData.noAO = true;
  g.add(mm);
  const wm = K.m(wg, water, { pos: [0, 0.008, 0] });
  wm.userData.noAO = true;
  g.add(wm);
  // a few pebbles poking through the water
  const stones = K.mat(game, 'paint', '#ffffff', { rough: 0.5 });
  const rnd = mulberry32(seed * 3 + 1);
  const geos = [];
  for (let i = 0; i < 4; i++) geos.push(K.tint(xf(stoneGeo(0.03 + rnd() * 0.03, seed * 9 + i, 0.5), { pos: [(rnd() - 0.5) * r * 1.8, 0.004, (rnd() - 0.5) * r * 1.1] }), STONE_COLS[i % 5]));
  g.add(K.m(mergeList(geos), stones));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}, { category: CAT, tags: ['yard', 'ground', 'decal'], size: [2.2, 0.02, 1.6], desc: 'rain puddle: glossy dark water with a moonlit rim sheen, wet margin, pebbles; no collider (opts.size, opts.seed)' });

function gravelTex() {
  return K.tex.canvas('out_gravel_patch', 512, 512, (ctx, w, h, rand) => {
    ctx.clearRect(0, 0, w, h);
    const c = w / 2;
    for (let i = 0; i < 5200; i++) {
      const a = rand() * TAU, d = Math.sqrt(rand()) * c * 0.98;
      const x = c + Math.cos(a) * d, y = c + Math.sin(a) * d;
      const edge = 1 - d / c;
      if (rand() > edge * 3.2) continue;
      const r = 2 + rand() * 5;
      const col = STONE_COLS[Math.floor(rand() * STONE_COLS.length)];
      ctx.globalAlpha = 1;
      ctx.fillStyle = hexMul(col, 0.45); ctx.beginPath(); ctx.ellipse(x + 1.2, y + 1.6, r, r * 0.75, rand() * 3, 0, TAU); ctx.fill();
      ctx.fillStyle = col; ctx.beginPath(); ctx.ellipse(x, y, r, r * 0.75, rand() * 3, 0, TAU); ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.25)'; ctx.beginPath(); ctx.ellipse(x - r * 0.25, y - r * 0.3, r * 0.4, r * 0.25, 0, 0, TAU); ctx.fill();
    }
  }, { repeat: false });
}
registerProp('yd_gravel_patch', (game, opts = {}) => {
  const g = K.prop('yd_gravel_patch');
  const s = opts.size ?? 2.2;
  const mat = K.mat(game, 'paint', '#ffffff', { map: gravelTex(), alphaTest: 0.4, rough: 0.9 });
  const m = K.m(groundDecal(s, s), mat, { pos: [0, 0.006, 0], rot: [0, (opts.seed ?? 0) * 1.3, 0] });
  m.userData.noAO = true;
  g.add(m);
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}, { category: CAT, tags: ['yard', 'ground', 'decal'], size: [2.2, 0.01, 2.2], desc: 'loose coarse-gravel ground decal with a ragged edge; no collider (opts.size, opts.seed rotates it)' });

registerProp('yd_weeds', (game, opts = {}) => {
  const g = K.prop('yd_weeds');
  const seed = opts.seed ?? 1;
  const rnd = mulberry32(seed * 17 + 9);
  const leafMat = K.mat(game, 'leaf', '#ffffff');
  const geos = [];
  const tufts = opts.tufts ?? 3;
  const greens = ['#7C9A3A', '#94A83E', '#6A8A34', '#A8A84A'];
  for (let t = 0; t < tufts; t++) {
    const a = rnd() * TAU, d = t ? 0.12 + rnd() * 0.25 : 0;
    const x = Math.cos(a) * d, z = Math.sin(a) * d;
    const cl = K.leafCluster({ count: 9 + Math.floor(rnd() * 5), len: [0.16, 0.34], width: 0.035, a0: [1.2, 1.5], a1: [0.2, 0.9], fold: 0.5, seed: seed * 10 + t, spread: 0.015, vary: 0.3 });
    geos.push(K.tint(xf(cl, { pos: [x, 0, z], scale: 0.7 + rnd() * 0.6 }), greens[t % greens.length]));
  }
  // a dandelion or two (stalk + yellow puff)
  const flowers = [];
  for (let i = 0; i < 2; i++) {
    const x = (rnd() - 0.5) * 0.3, z = (rnd() - 0.5) * 0.3, h = 0.22 + rnd() * 0.12;
    geos.push(K.tint(pipeGeo(0.004, [x, 0, z], [x + 0.02, h, z], 4, false), '#6A8A34'));
    flowers.push(xf(new THREE.IcosahedronGeometry(0.024, 1), { pos: [x + 0.02, h + 0.01, z], scale: [1, 0.6, 1] }));
  }
  g.add(K.m(mergeList(geos), leafMat));
  g.add(K.m(mergeList(flowers), K.mat(game, 'plastic', '#F4D03A', { rough: 0.8 })));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { dist: 0.1, height: 0.1 } });
}, { category: CAT, tags: ['yard', 'ground', 'plant', 'decal'], size: [0.7, 0.35, 0.7], desc: 'tufts of weeds poking through the gravel + dandelions; no collider (opts.seed, opts.tufts)' });

// =================================================================================================== shared (tower, hut, van...)
const lerp3 = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
// canvas pixel rect -> uvRect (v measured from the bottom: CanvasTexture flipY). Mutates g.
function pxUV(g, x0, y0, x1, y1, W, H) { return K.uvRect(g, x0 / W, 1 - y1 / H, x1 / W, 1 - y0 / H); }
// 12-tri box beam from a to b (w across, d along nrm): the cheap LOD member
function boxBeam(w, d, a, b, nrm) {
  const { m, len } = basis(a, b, nrm);
  const g = new THREE.BoxGeometry(w, len, d);
  g.translate(0, len / 2, 0);
  g.applyMatrix4(m);
  return g;
}
// 16-tri chamfered bar (octagonal section, open ends) from a to b: w across, d along nrm, chamfer c
function bar8(w, d, a, b, nrm, c = 0.012) {
  const { m, len } = basis(a, b, nrm);
  const hw = w / 2, hd = d / 2, cc = Math.min(c, hw * 0.45, hd * 0.45);
  const sec = [[hw - cc, hd], [hw, hd - cc], [hw, -hd + cc], [hw - cc, -hd], [-hw + cc, -hd], [-hw, -hd + cc], [-hw, hd - cc], [-hw + cc, hd]];
  const pos = [], uv = [];
  for (let i = 0; i < 8; i++) {
    const [x0, z0] = sec[i], [x1, z1] = sec[(i + 1) % 8];
    const u0 = i / 8, u1 = (i + 1) / 8;
    pos.push(x0, 0, z0, x1, 0, z1, x1, len, z1, x0, 0, z0, x1, len, z1, x0, len, z0);
    uv.push(u0, 0, u1, 0, u1, len, u0, 0, u1, len, u0, len);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.computeVertexNormals();
  g.applyMatrix4(m);
  return g;
}
function concreteTex(base = C.concrete) {
  return K.tex.canvas(`out_concrete|${base}`, 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 1800; i++) {
      ctx.globalAlpha = 0.1 + rand() * 0.22;
      ctx.fillStyle = rand() < 0.55 ? hexMul(base, 0.72) : hexMix(base, '#ffffff', 0.4);
      ctx.beginPath(); ctx.arc(rand() * w, rand() * h, 0.5 + rand() * 1.5, 0, TAU); ctx.fill();
    }
    grime(ctx, w, h, rand, 16, '#3A3040', 0.05);
    ctx.globalAlpha = 1;
  });
}
// glowing bulb/lens material pair for switchable lights: lit glow vs dark glass
function lensMats(game, color, intensity = 2.4) {
  return { on: K.glow(game, color, intensity), off: K.mat(game, 'crt', hexMul(color, 0.35), { rough: 0.15, rim: 0.5 }) };
}
function ensureCol(root) {
  root.traverse((o) => {
    if (o.isMesh && o.material?.vertexColors && !o.geometry.attributes.color) {
      o.geometry = o.geometry.clone();
      o.geometry.setAttribute('color', new THREE.BufferAttribute(new Float32Array(o.geometry.attributes.position.count * 3).fill(1), 3));
    }
  });
  return root;
}
function lightMesh(geo, mat, o = {}) {
  const b = K.m(geo, mat, o);
  b.userData.noMerge = true; b.userData.noAO = true; b.userData.noOcclude = true; b.userData.noShadow = true;
  return b;
}

// =================================================================================================== TOWER
// Red/white lattice transmitter tower (GDD §5.7): base 4 x 4 m (legs at ±1.8 m on concrete piers), lattice to 27 m,
// batwing TV antenna mast + big red beacon on top (~31.6 m). Detailed lower 8 m: bolted leg flanges, chunky X-bracing,
// caged ladder on the -z face, a work platform at 8 m, coax line down the -x/+z leg toward the hut, signs (DANGER on
// the +z face above the kill-switch cage spot, the WZTV 13 shield on -x, ASR plate). Upper part = cheap LOD (12-tri
// members) in parts.upper. parts.beacons = [top, mid x4] glow meshes (noMerge): setTowerBeacons(game, g, on, color).
const TW = { base: 1.8, top: 0.42, latH: 27, bands: 7, low: [0.38, 2, 4, 6, 8], up: [8, 11.2, 14.4, 17.6, 20.8, 24, 27] };
TW.bandH = TW.latH / TW.bands;
const TWR = { red: '#D8402F', white: '#F4EEE2' };
const twHW = (y) => lerp(TW.base, TW.top, clamp(y / TW.latH, 0, 1));
const twCol = (y) => (Math.min(TW.bands - 1, Math.floor(y / TW.bandH)) % 2 === 0 ? TWR.red : TWR.white);
const TW_CORN = [[-1, -1], [1, -1], [1, 1], [-1, 1]];
const twP = (c, y) => [c[0] * twHW(y), y, c[1] * twHW(y)];
// splits a->b at the paint band boundaries: [[a', b', color], ...]
function twBands(a, b) {
  const ts = [0, 1];
  const y0 = a[1], y1 = b[1];
  if (Math.abs(y1 - y0) > 1e-5) {
    const lo = Math.min(y0, y1), hi = Math.max(y0, y1);
    for (let k = Math.ceil(lo / TW.bandH); k * TW.bandH < hi; k++) {
      const y = k * TW.bandH;
      if (y > lo + 1e-4 && y < hi - 1e-4) ts.push((y - y0) / (y1 - y0));
    }
  }
  ts.sort((p, q) => p - q);
  const out = [];
  for (let i = 0; i < ts.length - 1; i++) {
    const pa = lerp3(a, b, ts[i]), pb = lerp3(a, b, ts[i + 1]);
    out.push([pa, pb, twCol((pa[1] + pb[1]) / 2)]);
  }
  return out;
}
function towerSigns() {
  return atlasTex('tower_signs', 1024, 512, (ctx) => {
    const rand = mulberry32(1313);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    // DANGER / HIGH VOLTAGE (0,0)-(512,352)
    ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.roundRect(4, 4, 504, 344, 26); ctx.fill();
    ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 8; ctx.beginPath(); ctx.roundRect(16, 16, 480, 320, 18); ctx.stroke();
    ctx.fillStyle = '#2A1D2A'; ctx.beginPath(); ctx.roundRect(28, 28, 456, 112, 12); ctx.fill();
    ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.ellipse(256, 84, 206, 44, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = '#F4F1E8';
    fitText(ctx, 'DANGER', 360, 70); ctx.fillText('DANGER', 256, 88);
    ctx.fillStyle = '#2A1D2A'; fitText(ctx, 'HIGH VOLTAGE', 440, 54); ctx.fillText('HIGH VOLTAGE', 256, 190);
    fitText(ctx, 'KEEP OFF THE TOWER', 420, 30, 'Titan One'); ctx.fillText('KEEP OFF THE TOWER', 256, 250);
    ctx.fillStyle = '#E8A92E';
    ctx.beginPath(); ctx.moveTo(250, 272); ctx.lineTo(222, 312); ctx.lineTo(248, 310); ctx.lineTo(236, 336); ctx.lineTo(284, 294); ctx.lineTo(258, 296); ctx.lineTo(276, 272); ctx.closePath(); ctx.fill();
    ctx.globalAlpha = 0.16; ctx.fillStyle = '#7A4A2A';
    for (let i = 0; i < 20; i++) { ctx.beginPath(); ctx.arc(rand() * 512, rand() * 352, 3 + rand() * 14, 0, TAU); ctx.fill(); }
    ctx.globalAlpha = 1;
    // WZTV 13 shield (512,0)-(896,384)
    {
      const cx = 704, cy = 192;
      ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(cx, cy, 190, 0, TAU); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(cx, cy, 168, 0, TAU); ctx.fill();
      ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.arc(cx, cy, 150, 0, TAU); ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 6; ctx.beginPath(); ctx.arc(cx, cy, 132, Math.PI * 1.1, Math.PI * 1.6); ctx.stroke();
      ctx.fillStyle = '#F4F1E8'; font(ctx, 150, 'Titan One'); ctx.fillText('13', cx, cy + 22);
      ctx.fillStyle = '#FFD23A'; fitText(ctx, 'WZTV', 170, 44); ctx.fillText('WZTV', cx, cy - 92);
    }
    // ASR plate (0,384)-(384,512)
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 384, 384, 128);
    ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 5; ctx.strokeRect(8, 392, 368, 112);
    ctx.fillStyle = '#2A1D2A'; fitText(ctx, 'ASR 1013777', 330, 44); ctx.fillText('ASR 1013777', 192, 432);
    fitText(ctx, 'FCC ANTENNA STRUCTURE · WZTV-TV', 340, 18, 'Titan One'); ctx.fillText('FCC ANTENNA STRUCTURE · WZTV-TV', 192, 478);
    // deck grating (512,384)-(1024,512): dark slots on galvanized grey
    ctx.fillStyle = '#9CA3AD'; ctx.fillRect(512, 384, 512, 128);
    ctx.fillStyle = '#4A4656';
    for (let y = 392; y < 508; y += 14) for (let x = 520; x < 1016; x += 40) { ctx.beginPath(); ctx.roundRect(x, y, 32, 7, 3); ctx.fill(); }
  });
}

export function setTowerBeacons(game, g, on = true, color = PAL.onAirRed) {
  const P = g.userData.parts;
  if (!P?.beacons) return;
  const M = lensMats(game, color, 2.6);
  for (const b of P.beacons) b.material = on ? M.on : M.off;
}

registerProp('yd_tower', (game, opts = {}) => {
  const g = K.prop('yd_tower');
  const paint = K.mat(game, 'lacquer', '#ffffff', { rough: 0.42 });
  const galv = K.mat(game, 'metal', C.galv, { rough: 0.5 });
  const conc = K.mat(game, 'paint', '#ffffff', { map: concreteTex(), rough: 0.92 });
  const signs = K.mat(game, 'paint', '#ffffff', { map: towerSigns(), rough: 0.55 });
  const rubber = K.mat(game, 'rubber', '#3A3446');
  const lens = lensMats(game, PAL.onAirRed, 2.6);
  const lit = opts.lit !== false;
  const G = { paint: [], galv: [], conc: [], signs: [], rubber: [] };
  const U = { paint: [], galv: [] };           // upper LOD
  const push = (arr, geo, col) => arr.push(col ? K.tint(geo, col) : geo);
  // --- piers, base plates, anchor bolts
  for (const c of TW_CORN) {
    const x = c[0] * TW.base, z = c[1] * TW.base;
    push(G.conc, xf(K.taper(K.box(0.74, 0.44, 0.74, 0.014), { axis: 'y', k: 0.82 }), { pos: [x, 0.2, z] }));
    push(G.galv, xf(cbox(0.42, 0.04, 0.42, 0.008), { pos: [x, 0.42, z] }));
    for (const [bx, bz] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
      push(G.galv, xf(new THREE.CylinderGeometry(0.028, 0.03, 0.05, 6), { pos: [x + bx * 0.15, 0.45, z + bz * 0.15] }));
    }
  }
  // --- legs (tapered pipes split at the paint bands; flanges at the lower joints)
  const legR = (y) => lerp(0.105, 0.06, y / TW.latH);
  for (const c of TW_CORN) {
    const lv = [...TW.low, ...TW.up.slice(1)];
    for (let i = 0; i < lv.length - 1; i++) {
      const upper = lv[i] >= TW.low[TW.low.length - 1];
      for (const [pa, pb, col] of twBands(twP(c, lv[i]), twP(c, lv[i + 1]))) {
        push(upper ? U.paint : G.paint, pipeGeo(legR(pb[1]), pa, pb, upper ? 7 : 12, false, legR(pa[1])), col);
      }
      if (!upper && i > 0) {
        const p = twP(c, lv[i]), q = twP(c, lv[i] + 0.3);
        push(G.paint, alongGeo(new THREE.CylinderGeometry(legR(lv[i]) + 0.045, legR(lv[i]) + 0.045, 0.07, 10), p, q), twCol(lv[i] + 0.01));
      }
    }
    push(U.paint, xf(new THREE.CylinderGeometry(legR(TW.latH) * 0.8, legR(TW.latH), 0.06, 7), { pos: twP(c, TW.latH) }), twCol(TW.latH - 0.1));
  }
  // --- bracing: X per face per section + girt on top of each section
  const faces = TW_CORN.map((c0, i) => {
    const c1 = TW_CORN[(i + 1) % 4];
    return { c0, c1, n: [Math.sign(c0[0] + c1[0]), 0, Math.sign(c0[1] + c1[1])] };
  });
  const brace = (levels, upper) => {
    for (let i = 0; i < levels.length - 1; i++) {
      const ya = levels[i] === TW.low[0] ? 0.55 : levels[i], yb = levels[i + 1];
      for (const f of faces) {
        const members = [[twP(f.c0, ya), twP(f.c1, yb)], [twP(f.c1, ya), twP(f.c0, yb)], [twP(f.c0, yb), twP(f.c1, yb)]];
        for (const [a, b] of members) {
          for (const [pa, pb, col] of twBands(a, b)) {
            if (upper) U.paint.push(K.tint(boxBeam(0.085, 0.045, pa, pb, f.n), col));
            else G.paint.push(K.tint(bar8(0.12, 0.055, pa, pb, f.n, 0.014), col));
          }
        }
      }
    }
  };
  brace(TW.low, false);
  brace(TW.up, true);
  push(U.paint, xf(cbox(1.1, 0.12, 1.1, 0.02), { pos: [0, TW.latH + 0.06, 0] }), TWR.red);
  // --- caged ladder on the -z face (lower detailed, upper cheap)
  const lz = (y, off = 0.3) => -(twHW(y) + off);
  const railL = (y0, y1, x, arr, cheap) => {
    const a = [x, y0, lz(y0)], b = [x, y1, lz(y1)];
    arr.push(cheap ? boxBeam(0.05, 0.03, a, b, [0, 0, -1]) : bar8(0.06, 0.035, a, b, [0, 0, -1], 0.008));
  };
  railL(0.02, 9.1, -0.22, G.galv, false); railL(0.02, 9.1, 0.22, G.galv, false);
  for (let y = 0.3; y < 8.9; y += 0.3) push(G.galv, pipeGeo(0.017, [-0.22, y, lz(y)], [0.22, y, lz(y)], 6, false));
  railL(9.1, TW.latH - 0.6, -0.2, U.galv, true); railL(9.1, TW.latH - 0.6, 0.2, U.galv, true);
  for (let y = 9.5; y < TW.latH - 0.8; y += 0.6) U.galv.push(boxBeam(0.4, 0.03, [0, y - 0.015, lz(y)], [0, y + 0.015, lz(y)], [0, 0, -1]));
  for (const y of [2, 4, 6]) for (const x of [-0.22, 0.22]) push(G.galv, bar8(0.05, 0.03, [x, y, lz(y)], [x * 0.5, y, -twHW(y)], [0, 1, 0], 0.006));
  for (let y = 2.4; y <= 7.4; y += 0.7) {
    const z0 = lz(y);
    const pts = [[-0.3, y, z0 + 0.02]];
    for (let k = 0; k <= 8; k++) { const a = Math.PI * (k / 8); pts.push([-Math.cos(a) * 0.36, y, z0 - 0.32 - Math.sin(a) * 0.36]); }
    pts.push([0.3, y, z0 + 0.02]);
    push(G.galv, K.tube(pts, 0.016, { seg: 8, radial: 4 }));
  }
  for (const a of [0.35, 1.2, 1.95, 2.8]) {
    const x = -Math.cos(a) * 0.36, dz = -0.32 - Math.sin(a) * 0.36;
    push(G.galv, pipeGeo(0.013, [x, 2.4, lz(2.4) + dz], [x, 7.3, lz(7.3) + dz], 5, false));
  }
  // --- work platform at 8 m
  const PY = 8, Pi = twHW(PY) - 0.04, Po = twHW(PY) + 0.78, PW = Po - Pi, PM = (Po + Pi) / 2;
  const grate = (geo) => pxUV(geo, 520, 390, 1016, 506, 1024, 512);
  const halfW = Po - 0.35;
  for (const s of [-1, 1]) G.signs.push(grate(xf(cbox(halfW, 0.06, PW, 0.012).clone(), { pos: [s * (0.35 + halfW / 2), PY, -PM] })));
  G.signs.push(grate(xf(cbox(2 * Po, 0.06, PW, 0.012).clone(), { pos: [0, PY, PM] })));
  for (const s of [-1, 1]) G.signs.push(grate(xf(cbox(2 * Pi, 0.06, PW, 0.012).clone(), { pos: [s * PM, PY, 0], rot: [0, Math.PI / 2, 0] })));
  for (const c of TW_CORN) push(G.galv, bar8(0.07, 0.04, twP(c, PY - 1.1), [c[0] * (Po - 0.1), PY - 0.04, c[1] * (Po - 0.1)], [c[0], 0, -c[1]], 0.006));
  for (const s of [-1, 1]) {
    push(G.paint, xf(cbox(2 * Po, 0.12, 0.03, 0.008), { pos: [0, PY + 0.09, s * (Po - 0.015)] }), '#F2C230');
    push(G.paint, xf(cbox(0.03, 0.12, 2 * Po, 0.008), { pos: [s * (Po - 0.015), PY + 0.09, 0] }), '#F2C230');
  }
  for (const c of TW_CORN) {
    for (const [ux, uz] of [[c[0], c[1]], [0, c[1]], [c[0], 0]]) {
      if (ux === 0 && uz === -1) continue;
      const x = ux * (Po - 0.05), z = uz * (Po - 0.05);
      push(G.galv, pipeGeo(0.024, [x, PY, z], [x, PY + 1.08, z], 7, false));
    }
  }
  for (const y of [PY + 0.55, PY + 1.08]) push(G.galv, K.tube(K.roundRectPath(2 * Po - 0.1, 2 * Po - 0.1, 0.14, y, 2), 0.026, { seg: 24, radial: 5, closed: true }));
  for (const x of [-0.22, 0.22]) push(G.galv, K.tube([[x, 9.0, lz(9.0)], [x, 9.6, lz(9.6)], [x * 1.1, 9.8, lz(9.8) + 0.15], [x * 1.1, 9.4, lz(9.4) + 0.4]], 0.02, { seg: 6, radial: 4 }));
  // --- microwave drum on the -x face (12.6 m) + coax line down the -x/+z leg
  {
    const y = 12.6, x = -twHW(y) - 0.55;
    const drum = K.lathe([[0, -0.2], [0.5, -0.2], [0.53, -0.16], [0.53, 0.16], [0.5, 0.21], [0.36, 0.25], [0, 0.26]], { seg: 16 }).clone();
    drum.rotateZ(Math.PI / 2);
    push(U.galv, xf(drum, { pos: [x, y, 0.3] }), '#EEE8DA');
    push(U.galv, xf(new THREE.CircleGeometry(0.42, 18).rotateY(-Math.PI / 2), { pos: [x - 0.265, y, 0.3] }), '#B8B2C4');
    push(U.galv, pipeGeo(0.05, [x + 0.2, y - 0.5, 0.3], [x + 0.2, y + 0.5, 0.3], 6, true));
    U.galv.push(boxBeam(0.06, 0.06, [x + 0.2, y + 0.4, 0.3], [-twHW(y + 0.4), y + 0.4, twHW(y + 0.4) * 0.2], [0, 1, 0]));
    U.galv.push(boxBeam(0.06, 0.06, [x + 0.2, y - 0.4, 0.3], [-twHW(y - 0.4), y - 0.4, twHW(y - 0.4) * 0.2], [0, 1, 0]));
  }
  const coax = (y) => { const h = twHW(y) + 0.16; return [-h, y, h]; };
  push(G.rubber, pipeGeo(0.05, coax(1.2), coax(8.4), 8, false));
  push(G.rubber, K.tube([coax(1.25), [-TW.base - 0.3, 0.7, TW.base + 0.3], [-TW.base - 0.75, 0.12, TW.base + 0.75], [-TW.base - 0.95, -0.05, TW.base + 0.95]], 0.05, { seg: 10, radial: 8 }));
  U.galv.push(K.tint(pipeGeo(0.045, coax(8.4), coax(TW.latH - 0.3), 5, false), '#3A3446'));
  for (let y = 1.8; y < 8; y += 1.6) push(G.galv, xf(cbox(0.1, 0.07, 0.1, 0.01), { pos: coax(y) }));
  // --- antenna mast: 3 batwing bays + the big beacon
  const MY = TW.latH + 0.12, MT = MY + 4.1;
  push(U.galv, pipeGeo(0.11, [0, MY, 0], [0, MT, 0], 10, false, 0.13));
  const wing = new THREE.Shape([[0.12, -0.4], [0.62, -0.32], [0.62, 0.32], [0.12, 0.4]].map(([x, y]) => new THREE.Vector2(x, y)));
  wing.holes.push(new THREE.Path([[0.22, -0.26], [0.52, -0.21], [0.52, 0.21], [0.22, 0.26]].map(([x, y]) => new THREE.Vector2(x, y))));
  const wingGeo = K.extrude(wing, 0.035, { bevel: 0, curveSeg: 1 });
  for (let b = 0; b < 3; b++) {
    const y = MY + 0.75 + b * 1.15;
    for (let k = 0; k < 4; k++) push(U.galv, xf(wingGeo, { pos: [0, y, 0], rot: [0, k * Math.PI / 2, 0] }));
    push(U.galv, xf(new THREE.CylinderGeometry(0.16, 0.16, 0.08, 10), { pos: [0, y, 0] }), '#C9CED6');
  }
  push(U.paint, xf(K.lathe([[0, 0], [0.26, 0], [0.26, 0.08], [0.2, 0.12], [0, 0.12]], { seg: 14, round: 0.02, steps: 1 }), { pos: [0, MT, 0] }), TWR.red);
  const beacons = [];
  const beaconGeo = (r) => K.lathe([[0, 0], [r, 0], [r * 1.02, r * 0.5], [r * 0.85, r * 1.15], [r * 0.45, r * 1.5], [0, r * 1.58]], { seg: 10, round: r * 0.2, steps: 1 });
  const addBeacon = (pos, r, name) => {
    const b = lightMesh(beaconGeo(r), lit ? lens.on : lens.off, { pos, name });
    g.add(b);
    beacons.push(b);
    for (let k = 0; r > 0.2 && k < 3; k++) {
      const pts = [];
      for (let s = 0; s <= 6; s++) { const a = (s / 6) * Math.PI; pts.push([Math.cos(a) * r * 1.2, Math.sin(a) * r * 1.7, 0]); }
      push(U.galv, xf(K.tube(pts, r * 0.05, { seg: 8, radial: 3 }), { pos, rot: [0, (k * Math.PI) / 3, 0] }));
    }
    push(U.paint, xf(new THREE.CylinderGeometry(r * 1.1, r * 1.15, r * 0.25, 12), { pos: [pos[0], pos[1] - r * 0.125, pos[2]] }), TWR.red);
    return b;
  };
  const top = addBeacon([0, MT + 0.12, 0], 0.24, 'beacon_top');
  for (const [y, cs] of [[9.9, [[-1, -1], [1, 1]]], [18.6, [[1, -1], [-1, 1]]]]) {
    for (const c of cs) {
      const p = twP(c, y), q = [p[0] + c[0] * 0.32, y, p[2] + c[1] * 0.32];
      U.galv.push(boxBeam(0.05, 0.05, p, q, [0, 1, 0]));
      addBeacon([q[0], y + 0.02, q[2]], 0.13, 'beacon_mid');
    }
  }
  // --- signs
  {
    const y = 2.55, z = twHW(y) + 0.045;
    G.signs.push(xf(pxUV(decal(0.78, 0.54), 0, 0, 512, 352, 1024, 512), { pos: [0, y, z + 0.002], rot: [0, Math.PI, 0] }));
    push(G.galv, xf(cbox(0.84, 0.6, 0.03, 0.01), { pos: [0, y, z - 0.018] }));
    const y2 = 5.1, x2 = -twHW(y2) - 0.08;
    const shield = new THREE.CircleGeometry(0.62, 28);
    G.signs.push(xf(pxUV(shield, 512, 0, 896, 384, 1024, 512), { pos: [x2 - 0.032, y2, 0], rot: [0, -Math.PI / 2, 0] }));
    push(G.paint, xf(new THREE.CylinderGeometry(0.66, 0.66, 0.06, 28), { pos: [x2 + 0.03, y2, 0], rot: [0, 0, Math.PI / 2] }), TWR.white);
    for (const dy of [-0.35, 0.35]) push(G.galv, beamGeo(0.06, 0.04, [x2 + 0.03, y2 + dy, 0], [-twHW(y2 + dy), y2 + dy, 0], [0, 1, 0], 0.006));
    const y3 = 1.55, z3 = -twHW(y3) - 0.05;
    G.signs.push(xf(pxUV(decal(0.45, 0.15), 0, 384, 384, 512, 1024, 512), { pos: [0.72, y3, z3 - 0.012] }));
    push(G.galv, xf(cbox(0.48, 0.18, 0.02, 0.006), { pos: [0.72, y3, z3] }));
  }
  // --- assemble: lower merged per material, upper in its own (noMerge) group merged locally
  g.add(K.m(mergeList(G.paint), paint));
  g.add(K.m(mergeList(G.galv), galv));
  g.add(K.m(mergeList(G.conc), conc));
  g.add(K.m(mergeList(G.signs), signs));
  g.add(K.m(mergeList(G.rubber), rubber));
  const upper = new THREE.Group();
  upper.name = 'upper';
  upper.userData.noMerge = true;
  upper.add(K.m(mergeList(U.paint), paint), K.m(mergeList(U.galv), galv));
  g.add(upper);
  g.userData.parts = { upper, beacons, beaconTop: top };
  g.userData.lightAnchors = lit ? [
    { pos: [0, MT + 0.3, 0], color: PAL.onAirRed, intensity: 3, distance: 14, flicker: 0 },
    { pos: [0, 10.2, 0], color: PAL.onAirRed, intensity: 1.4, distance: 6, flicker: 0 },
  ] : [];
  const bb = TW.base + 0.4;
  g.userData.colliders = [{ min: [-bb, 0, -bb], max: [bb, 3, bb] }];
  return K.finish(game, g, { ao: { res: 150, dist: 0.45, rays: 8, height: 0.5, heightStrength: 0.3 } });
}, { category: CAT, tags: ['yard', 'tower', 'landmark'], size: [4.4, 31.7, 4.4], hero: true, desc: 'red/white lattice transmitter tower, 4 m base, batwing mast + beacons; parts.upper (LOD), parts.beacons (setTowerBeacons); +z face kept clear for the kill-switch cage (opts.lit)' });

registerScene('out_tower_base', {
  floor: '#4A4652', wall: '#1E2344', room: [40, 40], wallH: 0.01, hemi: 0.8,
  items: [{ id: 'yd_tower', pos: [0, 4] }],
  cam: { pos: [-5.5, 3.2, -7.5], target: [0, 4.6, 3.2], fov: 60 },
});

// =================================================================================================== HUT
// Nests another registered prop inside `g` AFTER K.finish (keeps its own AO/merge): forwards its screens, light
// anchors (transformed into g's space) and parts (prefixed). Returns the child.
function attachProp(game, g, id, opts, pos, rotY = 0, prefix = '') {
  const c = K.buildProp(id, game, opts);
  c.position.set(pos[0], pos[1], pos[2]);
  c.rotation.y = rotY;
  c.userData.noMerge = true;
  g.add(c);
  c.updateMatrix();
  const u = g.userData, cu = c.userData;
  for (const s of cu.screens || []) u.screens.push(s);
  for (const a of cu.lightAnchors || []) u.lightAnchors.push({ ...a, pos: new THREE.Vector3().fromArray(a.pos).applyMatrix4(c.matrix).toArray().map((v) => Math.round(v * 1000) / 1000) });
  for (const [k, v] of Object.entries(cu.parts || {})) u.parts[prefix + k] = v;
  return c;
}
// painted concrete-block wall (running bond, 0.5 x 0.25 m blocks at uv = 1 repeat / m)
function blockTex(base = '#EFE2C4') {
  return K.tex.canvas(`out_block|${base}`, 256, 256, (ctx, w, h, rand) => {
    const mortar = hexMul(base, 0.78);
    ctx.fillStyle = mortar; ctx.fillRect(0, 0, w, h);
    const bw = w / 2, bh = h / 4;
    for (let r = 0; r < 4; r++) for (let c = -1; c < 3; c++) {
      const x = c * bw + (r % 2 ? bw / 2 : 0), y = r * bh;
      ctx.fillStyle = hexMix(base, rand() < 0.5 ? '#ffffff' : '#C8B89A', rand() * 0.18);
      ctx.beginPath(); ctx.roundRect(x + 3, y + 3, bw - 6, bh - 6, 5); ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.fillRect(x + 6, y + 4, bw - 12, 3);
      ctx.fillStyle = 'rgba(60,40,30,0.08)'; ctx.fillRect(x + 4, y + bh - 8, bw - 8, 4);
    }
    for (let i = 0; i < 500; i++) { ctx.globalAlpha = 0.08 + rand() * 0.1; ctx.fillStyle = rand() < 0.5 ? '#8A7A60' : '#fff'; ctx.fillRect(rand() * w, rand() * h, 1.5, 1.5); }
    ctx.globalAlpha = 1;
  });
}
// hut / van / street shared printed bits: transmitter cabinet front, meter face, AC grille, van logo...
function hutAtlas() {
  return atlasTex('hut_atlas', 1024, 512, (ctx) => {
    const rand = mulberry32(37);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    // transmitter cabinet front (0,0)-(256,512): meters, lamps, louvers, label
    {
      ctx.fillStyle = '#6C8474'; ctx.fillRect(0, 0, 256, 512);
      ctx.fillStyle = '#2E2A36'; ctx.beginPath(); ctx.roundRect(20, 24, 216, 96, 10); ctx.fill();
      for (let i = 0; i < 2; i++) {
        const cx = 76 + i * 104, cy = 76;
        ctx.fillStyle = '#F4ECD6'; ctx.beginPath(); ctx.arc(cx, cy, 38, Math.PI, 0); ctx.lineTo(cx + 38, cy + 12); ctx.lineTo(cx - 38, cy + 12); ctx.fill();
        ctx.strokeStyle = '#2E2A36'; ctx.lineWidth = 3;
        for (let k = 0; k <= 8; k++) { const a = Math.PI + (k / 8) * Math.PI; ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * 34, cy + Math.sin(a) * 34); ctx.lineTo(cx + Math.cos(a) * 26, cy + Math.sin(a) * 26); ctx.stroke(); }
        ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(cx, cy + 6); ctx.lineTo(cx + Math.cos(-0.9 - i * 0.7) * 32, cy + 6 + Math.sin(-0.9 - i * 0.7) * 32); ctx.stroke();
      }
      const lamps = ['#FF3B30', '#52E04A', '#FFC23A', '#52E04A', '#7FE7FF'];
      lamps.forEach((c, i) => { ctx.fillStyle = c; ctx.beginPath(); ctx.arc(46 + i * 41, 150, 11, 0, TAU); ctx.fill(); ctx.fillStyle = 'rgba(255,255,255,0.5)'; ctx.beginPath(); ctx.arc(43 + i * 41, 146, 4, 0, TAU); ctx.fill(); });
      ctx.fillStyle = '#F4ECD6'; ctx.fillRect(48, 186, 160, 34); ctx.fillStyle = '#2E2A36'; fitText(ctx, 'WZTV TX-13', 150, 22); ctx.fillText('WZTV TX-13', 128, 204);
      ctx.fillStyle = '#4E6356';
      for (let i = 0; i < 9; i++) { ctx.beginPath(); ctx.roundRect(30, 250 + i * 26, 196, 12, 6); ctx.fill(); }
      ctx.fillStyle = '#3A4A40'; ctx.fillRect(0, 490, 256, 22);
      ctx.strokeStyle = 'rgba(0,0,0,0.25)'; ctx.lineWidth = 3; ctx.strokeRect(8, 8, 240, 496);
    }
    // AC unit side grille (256,0)-(512,256)
    {
      ctx.fillStyle = '#D8D2C2'; ctx.fillRect(256, 0, 256, 256);
      ctx.fillStyle = '#3A3444'; ctx.beginPath(); ctx.arc(384, 128, 104, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#B8B2A4'; ctx.lineWidth = 5;
      for (let r = 20; r < 104; r += 14) { ctx.beginPath(); ctx.arc(384, 128, r, 0, TAU); ctx.stroke(); }
      for (let k = 0; k < 6; k++) { const a = (k / 6) * TAU; ctx.beginPath(); ctx.moveTo(384, 128); ctx.lineTo(384 + Math.cos(a) * 104, 128 + Math.sin(a) * 104); ctx.stroke(); }
      ctx.fillStyle = '#B8B2A4'; ctx.beginPath(); ctx.arc(384, 128, 18, 0, TAU); ctx.fill();
    }
    // electric meter face (512,0)-(640,128)
    {
      ctx.fillStyle = '#F2EEE4'; ctx.beginPath(); ctx.arc(576, 64, 62, 0, TAU); ctx.fill();
      for (let i = 0; i < 4; i++) { ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(540 + i * 24, 48, 9, 0, TAU); ctx.stroke(); ctx.beginPath(); ctx.moveTo(540 + i * 24, 48); ctx.lineTo(540 + i * 24 + 6, 42 + i * 2); ctx.stroke(); }
      ctx.fillStyle = '#2A1D2A'; font(ctx, 12, 'Titan One'); ctx.fillText('KWH', 576, 78);
      ctx.fillStyle = '#C8201E'; ctx.fillRect(546, 90, 60, 6);
    }
    // door face (640,0)-(768,256): teal steel door with a louver + kick plate
    {
      ctx.fillStyle = '#2E8C8C'; ctx.fillRect(640, 0, 128, 256);
      ctx.strokeStyle = 'rgba(0,0,0,0.2)'; ctx.lineWidth = 3; ctx.strokeRect(650, 10, 108, 236);
      ctx.fillStyle = '#1F6464'; for (let i = 0; i < 6; i++) ctx.fillRect(664, 170 + i * 9, 80, 5);
      ctx.fillStyle = '#B8BEC6'; ctx.fillRect(646, 236, 116, 16);
      grime(ctx, 128, 256, rand, 0);
    }
    // cable boot plate (768,0)-(896,128)
    {
      ctx.fillStyle = '#9CA3AD'; ctx.beginPath(); ctx.roundRect(770, 2, 124, 124, 16); ctx.fill();
      for (const [x, y] of [[800, 40], [864, 40], [832, 92]]) { ctx.fillStyle = '#3A3446'; ctx.beginPath(); ctx.arc(x, y, 16, 0, TAU); ctx.fill(); }
      for (const [x, y] of [[782, 14], [882, 14], [782, 114], [882, 114]]) { ctx.fillStyle = '#6A6E78'; ctx.beginPath(); ctx.arc(x, y, 5, 0, TAU); ctx.fill(); }
    }
    // hut sign (256,256)-(768,384): TRANSMITTER · WZTV 13
    {
      const x0 = 256, y0 = 256;
      ctx.fillStyle = '#5A3A22'; ctx.beginPath(); ctx.roundRect(x0, y0, 512, 128, 24); ctx.fill();
      ctx.fillStyle = '#F6E7C8'; ctx.beginPath(); ctx.roundRect(x0 + 8, y0 + 8, 496, 112, 18); ctx.fill();
      ctx.fillStyle = '#E3662B'; ctx.fillRect(x0 + 8, y0 + 86, 496, 10); ctx.fillStyle = '#E8A92E'; ctx.fillRect(x0 + 8, y0 + 98, 496, 8);
      ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.arc(x0 + 62, y0 + 60, 40, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 6; ctx.stroke();
      ctx.fillStyle = '#F4F1E8'; font(ctx, 40, 'Titan One'); ctx.fillText('13', x0 + 62, y0 + 64);
      ctx.fillStyle = '#5A3A22'; fitText(ctx, 'TRANSMITTER', 360, 50); ctx.fillText('TRANSMITTER', x0 + 300, y0 + 46);
      fitText(ctx, 'WZTV CHANNEL 13 · 50,000 WATTS', 360, 18, 'Titan One'); ctx.fillText('WZTV CHANNEL 13 · 50,000 WATTS', x0 + 300, y0 + 76);
    }
    // SKYCAM 13 decal (768,128)-(1024,192)
    {
      ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.roundRect(770, 130, 252, 60, 14); ctx.fill();
      ctx.fillStyle = '#FFD23A'; fitText(ctx, 'SKYCAM 13', 220, 36); ctx.fillText('SKYCAM 13', 896, 162);
    }
    // NO SMOKING / AUTHORIZED (768,192)-(1024,256)
    {
      ctx.fillStyle = '#F4F1E8'; ctx.fillRect(768, 192, 256, 64);
      ctx.fillStyle = '#C8201E'; ctx.fillRect(768, 192, 256, 20);
      ctx.fillStyle = '#F4F1E8'; fitText(ctx, 'AUTHORIZED', 200, 16); ctx.fillText('AUTHORIZED', 896, 203);
      ctx.fillStyle = '#2A1D2A'; fitText(ctx, 'PERSONNEL ONLY', 230, 26); ctx.fillText('PERSONNEL ONLY', 896, 236);
    }
    // interior back wall (0,384)-(256,512): pegboard with a clipboard + calendar
    {
      ctx.fillStyle = '#B89A6A'; ctx.fillRect(768, 256, 256, 128);
      ctx.fillStyle = '#8A6E48'; for (let y = 264; y < 384; y += 12) for (let x = 776; x < 1024; x += 12) { ctx.beginPath(); ctx.arc(x, y, 1.6, 0, TAU); ctx.fill(); }
      ctx.fillStyle = '#F4F1E8'; ctx.fillRect(800, 276, 60, 84); ctx.fillStyle = '#E23B3B'; ctx.fillRect(800, 276, 60, 18);
      ctx.fillStyle = '#2A1D2A'; font(ctx, 12, 'Bungee'); ctx.fillText('OCT 77', 830, 286);
      ctx.fillStyle = '#C89A5A'; ctx.fillRect(890, 280, 50, 70); ctx.fillStyle = '#F4F1E8'; ctx.fillRect(895, 292, 40, 54);
    }
    // van logo "ACTION 13 NEWS" (0,512-...) lives in vanAtlas
    // grating strip (256,384)-(1024,512): roof gravel
    {
      ctx.fillStyle = '#7E7686'; ctx.fillRect(256, 384, 768, 128);
      for (let i = 0; i < 2600; i++) { ctx.fillStyle = STONE_COLS[Math.floor(rand() * STONE_COLS.length)]; ctx.globalAlpha = 0.8; ctx.beginPath(); ctx.arc(256 + rand() * 768, 384 + rand() * 128, 1 + rand() * 2.4, 0, TAU); ctx.fill(); }
      ctx.globalAlpha = 1;
    }
  });
}
const HUT = { W: 3.4, D: 2.6, H: 2.75, T: 0.2, win: [-1.05, 0.95, 0.85, 1.85] };
// small chunky CRT monitor (front -z) used in the hut window and the van
function miniMonitor(game, M, o) {
  const grp = new THREE.Group();
  const { w = 0.46, h = 0.36, d = 0.4, card = 'station_id', group = 'scr_decor', id = null, shell = '#3A3444' } = o;
  grp.add(tm(K.box(w, h, d * 0.62, 0.045), M.plastic, shell, { pos: [0, h / 2, 0.02] }));
  grp.add(tm(K.taper(cbox(w * 0.82, h * 0.8, d * 0.5, 0.03), { axis: 'z', k: 0.62 }), M.plastic, hexMul(shell, 0.85), { pos: [0, h / 2, d * 0.38] }));
  grp.add(tm(K.box(w * 0.94, h * 0.9, 0.03, 0.012), M.plastic, '#CFC6B4', { pos: [0, h / 2 + 0.005, -d * 0.31 + 0.012] }));
  const scr = K.screen(game, w * 0.7, h * 0.66, { card, group, dome: 0.012 });
  scr.position.set(-w * 0.07, h / 2 + 0.01, -d * 0.31 - 0.008);
  if (id) scr.userData.screenId = id;
  grp.add(scr);
  for (let i = 0; i < 2; i++) grp.add(tm(K.cyl(0.018, 0.02, 0.022, { seg: 8, bevel: 0.005 }), M.plastic, '#2A2430', { pos: [w * 0.36, h * 0.62 - i * 0.1, -d * 0.31], rot: [-Math.PI / 2, 0, 0] }));
  grp.add(lightMesh(new THREE.SphereGeometry(0.009, 6, 4), K.glow(game, PAL.onAirRed, 2), { pos: [w * 0.36, h * 0.25, -d * 0.31 - 0.004] }));
  return { grp, scr };
}

registerProp('yd_hut', (game, opts = {}) => {
  const g = K.prop('yd_hut');
  const { W, D, H, T } = HUT;
  const [wx0, wx1, wy0, wy1] = HUT.win;
  const wall = K.mat(game, 'paint', '#ffffff', { map: blockTex(), rough: 0.72 });
  const paint = K.mat(game, 'lacquer', '#ffffff', { rough: 0.45 });
  const galv = K.mat(game, 'metal', C.galv, { rough: 0.45 });
  const atlas = K.mat(game, 'paint', '#ffffff', { map: hutAtlas(), rough: 0.55 });
  const glass = game.mats.glass('#BFD4FF', { opacity: 0.16 });
  const M = { plastic: K.mat(game, 'plastic', '#ffffff', { rough: 0.4 }) };
  const lit = opts.lit !== false;
  const BROWN = '#5A3A22', ORANGE = PAL.burntOrange, GOLD = PAL.harvestGold, CREAM = '#EFE2C4';
  const uvb = (geo) => K.uvBox(geo, 1);
  // --- plinth + walls (front wall is 4 pieces around the window)
  g.add(tm(cbox(W + 0.12, 0.14, D + 0.12, 0.03), paint, '#8E877D', { pos: [0, 0.07, 0] }));
  const wallBox = (w, h, d, pos) => g.add(K.m(uvb(cbox(w, h, d, 0.02)), wall, { pos }));
  wallBox(W - 0.3, H, T, [0, H / 2 + 0.1, D / 2 - T / 2]);
  wallBox(T, H, D - 0.3, [-W / 2 + T / 2, H / 2 + 0.1, 0]);
  wallBox(T, H, D - 0.3, [W / 2 - T / 2, H / 2 + 0.1, 0]);
  const fz = -D / 2 + T / 2;
  wallBox(W - 0.3, wy0 - 0.1, T, [0, (wy0 - 0.1) / 2 + 0.1, fz]);
  wallBox(W - 0.3, H + 0.1 - wy1, T, [0, (H + 0.1 + wy1) / 2, fz]);
  wallBox(wx0 + W / 2 - 0.15, wy1 - wy0, T, [(-W / 2 + 0.15 + wx0) / 2, (wy0 + wy1) / 2, fz]);
  wallBox(W / 2 - 0.15 - wx1, wy1 - wy0, T, [(W / 2 - 0.15 + wx1) / 2, (wy0 + wy1) / 2, fz]);
  // chunky corner pilasters + 70s stripe band
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) g.add(tm(cbox(0.32, H + 0.02, 0.32, 0.045), paint, BROWN, { pos: [sx * (W / 2 - 0.14), H / 2 + 0.11, sz * (D / 2 - 0.14)] }));
  [[ORANGE, 2.34], [GOLD, 2.24], [BROWN, 2.14]].forEach(([col, y]) => {
    for (const s of [-1, 1]) {
      g.add(tm(cbox(W - 0.34, 0.075, 0.02, 0.006), paint, col, { pos: [0, y, s * (D / 2 + 0.006)] }));
      g.add(tm(cbox(0.02, 0.075, D - 0.34, 0.006), paint, col, { pos: [s * (W / 2 + 0.006), y, 0] }));
    }
  });
  // --- roof slab, flashing, gravel top
  const RY = H + 0.1;
  g.add(tm(K.box(W + 0.26, 0.2, D + 0.26, 0.04), paint, '#D9CDB2', { pos: [0, RY + 0.1, 0] }));
  g.add(tm(K.tube(K.roundRectPath(W + 0.2, D + 0.2, 0.08, RY + 0.21, 2), 0.035, { seg: 36, radial: 5, closed: true }), galv, null));
  g.add(K.m(pxUV(groundDecal(W + 0.1, D + 0.1), 256, 384, 1024, 512, 1024, 512), atlas, { pos: [0, RY + 0.202, 0] }));
  // interior: dark floor, back pegboard, cabinets, ceiling fixture
  g.add(tm(cbox(W - 0.4, 0.04, D - 0.4, 0.006), paint, '#4A3E4E', { pos: [0, 0.16, 0] }));
  g.add(K.m(pxUV(decal(0.8, 0.4), 768, 256, 1024, 384, 1024, 512), atlas, { pos: [1.1, 1.6, D / 2 - T - 0.005] }));
  for (let i = 0; i < 3; i++) {
    const x = -1.1 + i * 0.74;
    g.add(tm(cbox(0.7, 2.05, 0.55, 0.02), paint, '#6C8474', { pos: [x, 1.2, D / 2 - T - 0.3] }));
    g.add(K.m(pxUV(decal(0.62, 1.9), 0, 0, 256, 512, 1024, 512), atlas, { pos: [x, 1.2, D / 2 - T - 0.58] }));
  }
  g.add(tm(K.box(1.3, 0.06, 0.16, 0.02), paint, '#D8D2C2', { pos: [-0.1, RY - 0.05, -0.2] }));
  const tubeLight = lightMesh(K.cyl(0.03, 0.03, 1.1, { seg: 8, bevel: 0.01 }).clone().rotateZ(Math.PI / 2).translate(0.55, 0, 0), lit ? K.glow(game, '#E8F5E1', 1.6) : K.mat(game, 'ceramic', '#DDE6DA'), { pos: [-0.1, RY - 0.1, -0.2], name: 'ceilingLight' });
  g.add(tubeLight);
  // --- window: aluminum frame + mullion + sill + glass + sign above
  const ww = wx1 - wx0, wh = wy1 - wy0, wcx = (wx0 + wx1) / 2, wcy = (wy0 + wy1) / 2;
  const frame = K.roundRect(ww + 0.06, wh + 0.06, 0.05);
  frame.holes.push(new THREE.Path(K.roundRect(ww - 0.06, wh - 0.06, 0.03).getPoints(6)));
  g.add(tm(K.extrude(frame, 0.08, { bevel: 0.015, bevelSeg: 1, curveSeg: 4 }), galv, null, { pos: [wcx, wcy, -D / 2 + 0.03] }));
  g.add(tm(cbox(0.05, wh - 0.05, 0.06, 0.01), galv, null, { pos: [wcx + 0.2, wcy, -D / 2 + 0.03] }));
  g.add(tm(K.box(ww + 0.24, 0.08, 0.22, 0.025), paint, '#D9CDB2', { pos: [wcx, wy0 - 0.02, -D / 2 - 0.02] }));
  const gl = K.m(new THREE.PlaneGeometry(ww - 0.04, wh - 0.04).rotateY(Math.PI), glass, { pos: [wcx, wcy, -D / 2 + 0.04], name: 'windowGlass' });
  gl.userData.noOcclude = true; gl.userData.noMerge = true;
  g.add(gl);
  g.add(K.m(pxUV(decal(1.7, 0.425), 256, 256, 768, 384, 1024, 512), atlas, { pos: [wcx, 2.62, -D / 2 - 0.012] }));
  // --- door (+x face), step, caged light, meter, cable port
  const dz = 0.35, dx = W / 2 + 0.005;
  g.add(tm(cbox(0.06, 2.18, 1.1, 0.015), galv, null, { pos: [dx, 1.19, dz] }));
  g.add(K.m(pxUV(decal(0.94, 2.02).rotateY(-Math.PI / 2), 640, 0, 768, 256, 1024, 512), atlas, { pos: [dx + 0.042, 1.16, dz] }));
  g.add(tm(cbox(0.03, 2.04, 0.96, 0.01), paint, '#2E8C8C', { pos: [dx + 0.02, 1.16, dz] }));
  g.add(tm(K.lathe([[0, 0], [0.03, 0], [0.035, 0.03], [0.02, 0.05], [0, 0.055]], { seg: 10, round: 0.01, steps: 1 }).clone().rotateZ(-Math.PI / 2), galv, null, { pos: [dx + 0.035, 1.05, dz - 0.36] }));
  g.add(K.m(pxUV(decal(0.4, 0.1).rotateY(-Math.PI / 2), 768, 192, 1024, 256, 1024, 512), atlas, { pos: [dx + 0.046, 1.7, dz] }));
  g.add(K.m(pxUV(decal(0.38, 0.26).rotateY(-Math.PI / 2), 0, 0, 512, 352, 1024, 512), K.mat(game, 'paint', '#ffffff', { map: towerSigns(), rough: 0.55 }), { pos: [dx + 0.046, 1.45, dz] }));
  g.add(tm(cbox(0.5, 0.16, 1.3, 0.03), paint, '#A8A196', { pos: [W / 2 + 0.25, 0.08, dz] }));
  // caged bulb over the door
  g.add(tm(K.cyl(0.07, 0.08, 0.05, { seg: 10, bevel: 0.01 }).clone().rotateZ(-Math.PI / 2), galv, null, { pos: [dx + 0.02, 2.42, dz] }));
  const bulb = lightMesh(new THREE.SphereGeometry(0.07, 10, 8), lit ? K.glow(game, PAL.tungsten, 2.6) : K.mat(game, 'ceramic', '#F0E6D0'), { pos: [dx + 0.13, 2.42, dz], name: 'doorLight' });
  g.add(bulb);
  for (let k = 0; k < 3; k++) {
    const pts = [];
    for (let s = 0; s <= 6; s++) { const a = (s / 6) * Math.PI; pts.push([Math.sin(a) * 0.16, Math.cos(a) * 0.09, 0]); }
    g.add(tm(K.tube(pts, 0.006, { seg: 8, radial: 3 }), galv, null, { pos: [dx + 0.03, 2.42, dz], rot: [(k - 1) * 0.9, 0, 0] }));
  }
  // meter + conduit
  g.add(tm(K.box(0.05, 0.32, 0.26, 0.015), galv, null, { pos: [dx + 0.02, 1.5, dz + 0.85] }));
  g.add(K.m(pxUV(new THREE.CircleGeometry(0.09, 16).rotateY(Math.PI / 2), 512, 0, 640, 128, 1024, 512), atlas, { pos: [dx + 0.1, 1.52, dz + 0.85] }));
  const dome = K.m(K.lathe([[0.1, 0], [0.1, 0.04], [0.08, 0.08], [0, 0.1]], { seg: 14 }).clone().rotateZ(-Math.PI / 2), glass, { pos: [dx + 0.05, 1.52, dz + 0.85] });
  dome.userData.noOcclude = true; dome.userData.noMerge = true;
  g.add(dome);
  g.add(tm(K.cyl(0.02, 0.02, 1.3, { seg: 8, bevel: 0.004 }), galv, null, { pos: [dx + 0.03, 0.05, dz + 0.85] }));
  // cable entry plate near the -z corner with three coax lines diving into the gravel (toward the tower)
  g.add(K.m(pxUV(decal(0.34, 0.34).rotateY(-Math.PI / 2), 768, 0, 896, 128, 1024, 512), atlas, { pos: [dx + 0.012, 1.25, -0.7] }));
  const rub = K.mat(game, 'rubber', '#3A3446');
  for (const [oy, oz, k] of [[0.08, -0.08, 0], [0.08, 0.08, 1], [-0.1, 0, 2]]) {
    const y0 = 1.25 + oy, z0 = -0.7 + oz;
    g.add(K.m(K.tube([[dx, y0, z0], [dx + 0.18, y0 - 0.05, z0], [dx + 0.32 + k * 0.05, y0 - 0.5, z0 - 0.05 * k], [dx + 0.42 + k * 0.08, 0.1, z0 - 0.1 - 0.08 * k], [dx + 0.7 + k * 0.1, -0.05, z0 - 0.3 - 0.1 * k]], 0.028, { seg: 12, radial: 6 }), rub));
  }
  // downpipe on the back-left corner + gutter box
  g.add(tm(K.box(0.14, 0.12, 0.14, 0.02), galv, null, { pos: [-W / 2 - 0.02, RY + 0.08, D / 2 + 0.06] }));
  g.add(tm(K.cyl(0.04, 0.04, RY - 0.1, { seg: 8, bevel: 0.006 }), galv, null, { pos: [-W / 2 - 0.02, 0.12, D / 2 + 0.06] }));
  // --- roof: AC unit, vent stack, whip antenna, SkyCam 13 (pan/tilt parts)
  const RT = RY + 0.2;
  g.add(tm(K.box(0.9, 0.5, 0.6, 0.045), paint, '#D8D2C2', { pos: [0.9, RT + 0.27, 0.55] }));
  g.add(K.m(pxUV(decal(0.46, 0.46), 256, 0, 512, 256, 1024, 512), atlas, { pos: [0.9, RT + 0.28, 0.55 - 0.305] }));
  g.add(tm(K.box(0.94, 0.05, 0.64, 0.02), paint, '#8E877D', { pos: [0.9, RT + 0.02, 0.55] }));
  g.add(tm(K.cyl(0.06, 0.06, 0.45, { seg: 10, bevel: 0.01 }), galv, null, { pos: [-1.1, RT, 0.7] }));
  g.add(tm(K.lathe([[0, 0], [0.1, 0], [0.1, 0.03], [0.06, 0.08], [0, 0.09]], { seg: 10, round: 0.01, steps: 1 }), galv, null, { pos: [-1.1, RT + 0.45, 0.7] }));
  g.add(tm(K.cyl(0.006, 0.01, 1.4, { seg: 5, bevel: 0.002 }), galv, null, { pos: [-1.4, RT, -0.9] }));
  g.add(tm(new THREE.SphereGeometry(0.03, 8, 6), galv, null, { pos: [-1.4, RT + 1.42, -0.9] }));
  // SkyCam 13 on a short mast at the roof center; looks toward the tower (+x, -z)
  const camX = -0.1, camZ = -0.1;
  g.add(tm(K.cyl(0.13, 0.15, 0.06, { seg: 12, bevel: 0.015 }), galv, null, { pos: [camX, RT, camZ] }));
  g.add(tm(K.cyl(0.045, 0.05, 0.42, { seg: 10, bevel: 0.008 }), galv, null, { pos: [camX, RT + 0.05, camZ] }));
  const pan = new THREE.Group();
  pan.name = 'skycam'; pan.userData.noMerge = true;
  pan.position.set(camX, RT + 0.47, camZ);
  pan.rotation.y = opts.camYaw ?? -Math.PI / 4;
  const tilt = new THREE.Group();
  tilt.name = 'skycamTilt'; tilt.userData.noMerge = true;
  tilt.position.set(0, 0.14, 0);
  tilt.rotation.x = opts.camTilt ?? 0.12;
  pan.add(tm(K.cyl(0.08, 0.09, 0.06, { seg: 12, bevel: 0.012 }), galv, null));
  for (const s of [-1, 1]) pan.add(tm(K.box(0.03, 0.2, 0.08, 0.01), galv, null, { pos: [s * 0.15, 0.1, 0] }));
  tilt.add(tm(K.box(0.24, 0.22, 0.5, 0.045), paint, '#F2EEE4', { pos: [0, 0, 0.02] }));
  tilt.add(tm(K.box(0.3, 0.03, 0.58, 0.012), paint, '#F2EEE4', { pos: [0, 0.13, -0.02] }));
  tilt.add(tm(K.cyl(0.085, 0.09, 0.08, { seg: 14, bevel: 0.015 }).clone().rotateX(-Math.PI / 2), paint, '#3A3444', { pos: [0, -0.005, -0.23] }));
  const lensM = K.mat(game, 'crt', '#1E2A4A', { rim: 0.8, rimColor: '#9FB6FF' });
  tilt.add(K.m(new THREE.CircleGeometry(0.066, 16).rotateY(Math.PI), lensM, { pos: [0, -0.005, -0.312] }));
  tilt.add(K.m(pxUV(decal(0.34, 0.08).rotateY(-Math.PI / 2), 768, 128, 1024, 192, 1024, 512), atlas, { pos: [0.122, 0.01, 0.04] }));
  tilt.add(K.m(pxUV(decal(0.34, 0.08).rotateY(Math.PI / 2), 768, 128, 1024, 192, 1024, 512), atlas, { pos: [-0.122, 0.01, 0.04] }));
  const tally = lightMesh(new THREE.SphereGeometry(0.026, 8, 6), lit ? K.glow(game, PAL.onAirRed, 2.6) : K.mat(game, 'crt', '#5A1A1A'), { pos: [0, 0.16, -0.18], name: 'skycamTally' });
  tilt.add(tally);
  pan.add(tilt);
  g.add(pan);
  // --- window stack: two feed monitors (scr_feed_yard) on a steel shelf right behind the glass
  const shelfX = 0.5, shelfZ = -D / 2 + T + 0.3;
  g.add(tm(K.box(0.6, 0.04, 0.46, 0.012), galv, null, { pos: [shelfX, 0.8, shelfZ] }));
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) g.add(tm(K.cyl(0.015, 0.015, 0.66, { seg: 6, bevel: 0.003 }), galv, null, { pos: [shelfX + sx * 0.27, 0.14, shelfZ + sz * 0.2] }));
  const mons = [];
  [[0.82, 'station_id', '#3A3444'], [1.2, 'color_bars', '#5A4A3A']].forEach(([y, card, shell], i) => {
    const mm = miniMonitor(game, M, { w: 0.5, h: 0.37, d: 0.4, card, group: 'scr_feed_yard', id: `hut_feed_${i + 1}`, shell });
    mm.grp.position.set(shelfX, y, shelfZ);
    mm.grp.rotation.set(0, i ? 0.06 : -0.04, i ? 0.015 : 0);
    g.add(mm.grp);
    mons.push(mm.scr);
  });
  g.userData.parts = { skycam: pan, skycamTilt: tilt, skycamTally: tally, doorLight: bulb, ceilingLight: tubeLight, windowGlass: gl };
  g.userData.screens = mons.map((s, i) => ({ mesh: s, group: 'scr_feed_yard', id: `hut_feed_${i + 1}` }));
  g.userData.lightAnchors = lit ? [
    { pos: [dx + 0.45, 2.3, dz], color: PAL.tungsten, intensity: 1.6, distance: 5, flicker: 0.05 },
  ] : [];
  g.userData.colliders = [{ min: [-W / 2 - 0.08, 0, -D / 2 - 0.1], max: [W / 2 + 0.08, RY + 0.25, D / 2 + 0.1] }, { min: [W / 2, 0, dz - 0.65], max: [W / 2 + 0.5, 0.16, dz + 0.65] }];
  g.userData.feedCam = { pos: [camX, RT + 0.61, camZ], note: 'GDD feed_cam_yard sits here (SkyCam 13)' };
  K.finish(game, g, { ao: { res: 44, rays: 10, strength: 0.8 } });
  // the tube rack lives behind the window (its own bake / glow parts / anchors)
  if (opts.tubes !== false) attachProp(game, g, 'hut_tubes', {}, [-0.5, 0.16, -D / 2 + T + 0.42], 0, 'tubes_');
  g.userData.stats = K.stats(g);
  return g;
}, { category: CAT, tags: ['yard', 'hut', 'building', 'screens'], size: [3.7, 3.7, 2.9], hero: true, cache: false, desc: 'transmitter hut: painted block walls, window with the tube rack + 2 feed monitors (scr_feed_yard), teal door on +x with caged light, SkyCam 13 on the roof (parts.skycam / skycamTilt); front (-z) faces the yard (opts.lit, opts.tubes, opts.camYaw)' });

// =================================================================================================== NEWS VAN
// "Action 13 News" van (GDD §5.7): 70s wood-paneled van, 5.0 x 2.0 m. LOCAL AXES: length along x, FRONT (cab) at -x,
// REAR (open doors) at +x, sliding/passenger side at -z. Placed with rotY = 0 it matches the layout (x 40.5–45.5,
// rear TV facing +x). Rear doors open (parts.doorL / doorR pivots), shag-lined cargo with an equipment rack, the rear
// feed TV (screen 'scr_feed_yard', id 'van_rear_tv'), a portable radio (parts.radio), dome light; telescoping mast
// with a microwave dish on the roof (parts.mast). opts: { lit=true, doors=1.75 (open angle, rad), mast=1 (0..1) }.
function vanAtlas() {
  return atlasTex('van_atlas', 1024, 512, (ctx) => {
    const rand = mulberry32(1977);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    // logo (0,0)-(640,160) on transparent
    {
      ctx.save();
      ctx.translate(0, 0);
      ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.arc(86, 80, 70, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 10; ctx.stroke();
      ctx.strokeStyle = '#F4F1E8'; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(86, 80, 58, 0, TAU); ctx.stroke();
      ctx.fillStyle = '#F4F1E8'; font(ctx, 70, 'Titan One'); ctx.fillText('13', 86, 86);
      // ACTION (groovy, outlined, slanted)
      ctx.save(); ctx.translate(360, 62); ctx.transform(1, 0, -0.18, 1, 0, 0);
      font(ctx, 84, 'Shrikhand');
      ctx.lineJoin = 'round'; ctx.lineWidth = 16; ctx.strokeStyle = '#5A3A22'; ctx.strokeText('Action', 0, 0);
      ctx.lineWidth = 8; ctx.strokeStyle = '#F4F1E8'; ctx.strokeText('Action', 0, 0);
      const gr = ctx.createLinearGradient(0, -40, 0, 40); gr.addColorStop(0, '#FFC23A'); gr.addColorStop(0.55, '#E3662B'); gr.addColorStop(1, '#C8402A');
      ctx.fillStyle = gr; ctx.fillText('Action', 0, 0);
      ctx.restore();
      ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.roundRect(196, 112, 350, 40, 20); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; fitText(ctx, 'NEWS · WZTV CHANNEL 13', 320, 26); ctx.fillText('NEWS · WZTV CHANNEL 13', 371, 133);
      // lightning bolt
      ctx.fillStyle = '#FFD23A'; ctx.strokeStyle = '#5A3A22'; ctx.lineWidth = 4;
      ctx.beginPath(); ctx.moveTo(596, 14); ctx.lineTo(566, 80); ctx.lineTo(590, 78); ctx.lineTo(572, 146); ctx.lineTo(626, 62); ctx.lineTo(600, 64); ctx.lineTo(618, 14); ctx.closePath(); ctx.fill(); ctx.stroke();
      ctx.restore();
    }
    // plates (640,0)-(896,128) front, (640,128)-(896,256) rear
    const plate = (y, t) => {
      ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.roundRect(646, y + 8, 244, 112, 14); ctx.fill();
      ctx.strokeStyle = '#2F5BD3'; ctx.lineWidth = 6; ctx.stroke();
      ctx.fillStyle = '#2F5BD3'; fitText(ctx, 'TRI-COUNTY 1977', 200, 16, 'Titan One'); ctx.fillText('TRI-COUNTY 1977', 768, y + 28);
      ctx.fillStyle = '#C8201E'; fitText(ctx, t, 220, 56); ctx.fillText(t, 768, y + 78);
    };
    plate(0, 'WZTV 13'); plate(128, 'NEWS 13');
    // grille (896,0)-(1024,128): dark slots between chrome bars
    ctx.fillStyle = '#C9CED6'; ctx.fillRect(896, 0, 128, 128);
    ctx.fillStyle = '#2A2430'; for (let i = 0; i < 6; i++) ctx.fillRect(902, 8 + i * 20, 116, 12);
    ctx.fillStyle = 'rgba(255,255,255,0.4)'; for (let i = 0; i < 6; i++) ctx.fillRect(902, 20 + i * 20, 116, 2);
    // tail light (896,128)-(960,256), amber (960,128)-(1024,256)
    for (const [x, c1, c2] of [[896, '#FF4A3A', '#A8201A'], [960, '#FFB347', '#B86A10']]) {
      const gr = ctx.createLinearGradient(x, 0, x + 64, 0); gr.addColorStop(0, c2); gr.addColorStop(0.5, c1); gr.addColorStop(1, c2);
      ctx.fillStyle = gr; ctx.fillRect(x, 128, 64, 128);
      ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 2; for (let i = 0; i < 7; i++) { ctx.beginPath(); ctx.moveTo(x + 4, 136 + i * 18); ctx.lineTo(x + 60, 136 + i * 18); ctx.stroke(); }
    }
    // equipment rack faces (0,256)-(512,512): 4 rows of gear
    {
      const rows = [['#3A3444', 'vu'], ['#C9CED6', 'knobs'], ['#3A3444', 'lamps'], ['#5A4A3A', 'reel']];
      rows.forEach(([bg, kind], r) => {
        const y = 256 + r * 64;
        ctx.fillStyle = bg; ctx.fillRect(0, y, 512, 64);
        ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.fillRect(0, y + 60, 512, 4);
        ctx.fillStyle = '#9CA3AD'; for (const x of [10, 502]) { ctx.beginPath(); ctx.arc(x, y + 32, 5, 0, TAU); ctx.fill(); }
        if (kind === 'vu') for (let i = 0; i < 4; i++) {
          const cx = 80 + i * 118;
          ctx.fillStyle = '#F4E6B8'; ctx.fillRect(cx - 44, y + 10, 88, 44);
          ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(cx, y + 60, 40, Math.PI * 1.2, Math.PI * 1.8); ctx.stroke();
          ctx.strokeStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(cx, y + 60, 40, Math.PI * 1.65, Math.PI * 1.8); ctx.stroke();
          ctx.strokeStyle = '#2A1D2A'; ctx.beginPath(); ctx.moveTo(cx, y + 56); ctx.lineTo(cx + Math.cos(-1.9 + i * 0.3) * 38, y + 56 + Math.sin(-1.9 + i * 0.3) * 38); ctx.stroke();
        }
        if (kind === 'knobs') for (let i = 0; i < 9; i++) { ctx.fillStyle = '#2A2430'; ctx.beginPath(); ctx.arc(40 + i * 54, y + 30, 14, 0, TAU); ctx.fill(); ctx.fillStyle = '#F4F1E8'; ctx.fillRect(38 + i * 54, y + 16, 4, 10); }
        if (kind === 'lamps') for (let i = 0; i < 16; i++) { ctx.fillStyle = ['#FF3B30', '#52E04A', '#FFC23A', '#7FE7FF'][i % 4]; ctx.beginPath(); ctx.arc(32 + i * 30, y + 32, 8, 0, TAU); ctx.fill(); }
        if (kind === 'reel') for (let i = 0; i < 2; i++) {
          const cx = 140 + i * 230;
          ctx.fillStyle = '#9CA3AD'; ctx.beginPath(); ctx.arc(cx, y + 32, 28, 0, TAU); ctx.fill();
          ctx.fillStyle = '#5A3424'; ctx.beginPath(); ctx.arc(cx, y + 32, 20, 0, TAU); ctx.fill();
          ctx.fillStyle = '#C9CED6'; ctx.beginPath(); ctx.arc(cx, y + 32, 6, 0, TAU); ctx.fill();
        }
      });
    }
    // ribbed rubber floor mat (512,256)-(1024,512)
    ctx.fillStyle = '#3A3446'; ctx.fillRect(512, 256, 512, 256);
    for (let x = 520; x < 1024; x += 16) { ctx.fillStyle = '#4E4A5C'; ctx.fillRect(x, 256, 7, 256); }
    grime(ctx, 512, 256, rand, 0);
    // wheel-well shadow disc (640,256)... drawn procedurally in vanWellTex
  });
}
function vanWood() { return K.tex.wood('#8A5634', { planks: 5, dark: 0.4, wear: 0.15 }); }
// Returns the side-panel shape (x along the van, y up) with wheel-arch notches of radius ar around wheel centers.
function vanPanelShape(x0, x1, y0, y1, wheels, ar, wy, r = 0.06) {
  const s = new THREE.Shape();
  s.moveTo(x0 + r, y0);
  for (const xw of wheels) {
    const dx = Math.sqrt(Math.max(0, ar * ar - (y0 - wy) ** 2));
    const a0 = Math.atan2(y0 - wy, -dx), a1 = Math.atan2(y0 - wy, dx);
    s.lineTo(xw - dx, y0);
    s.absarc(xw, wy, ar, a0, a1, true);
  }
  s.lineTo(x1 - r, y0); s.quadraticCurveTo(x1, y0, x1, y0 + r);
  s.lineTo(x1, y1 - r); s.quadraticCurveTo(x1, y1, x1 - r, y1);
  s.lineTo(x0 + r, y1); s.quadraticCurveTo(x0, y1, x0, y1 - r);
  s.lineTo(x0, y0 + r); s.quadraticCurveTo(x0, y0, x0 + r, y0);
  return s;
}
// rounded-rect Shape in the (u, v) plane centered at (cu, cv) with per-corner radii [bl, br, tr, tl]
function rrShape4(w, h, rads, cu = 0, cv = 0) {
  const [bl, br, tr, tl] = rads;
  const x0 = cu - w / 2, x1 = cu + w / 2, y0 = cv - h / 2, y1 = cv + h / 2;
  const s = new THREE.Shape();
  s.moveTo(x0 + bl, y0);
  s.lineTo(x1 - br, y0); s.absarc(x1 - br, y0 + br, br, -Math.PI / 2, 0, false);
  s.lineTo(x1, y1 - tr); s.absarc(x1 - tr, y1 - tr, tr, 0, Math.PI / 2, false);
  s.lineTo(x0 + tl, y1); s.absarc(x0 + tl, y1 - tl, tl, Math.PI / 2, Math.PI, false);
  s.lineTo(x0, y0 + bl); s.absarc(x0 + bl, y0 + bl, bl, Math.PI, Math.PI * 1.5, false);
  return s;
}
const VAN = { L: 5.0, W: 1.96, yb: 0.5, yt: 2.08, xc: -0.72, xr: 2.44, wheels: [-1.62, 1.5], wr: 0.37, wz: 0.87 };

registerProp('yd_news_van', (game, opts = {}) => {
  const g = K.prop('yd_news_van');
  const { W, yb, yt, xc, xr, wr, wz } = VAN;
  const hw = W / 2;
  const kc = {};
  const body = K.mat(game, 'lacquer', '#ffffff', { rough: 0.42, env: 0.05, ...kc });
  const chrome = K.mat(game, 'chrome', '#B4BCC6');
  const wood = K.mat(game, 'lacquer', '#ffffff', { map: vanWood(), rough: 0.4 });
  const atlas = K.mat(game, 'plastic', '#ffffff', { map: vanAtlas(), rough: 0.45 });
  const decalM = K.mat(game, 'plastic', '#ffffff', { map: vanAtlas(), rough: 0.4, transparent: true, depthWrite: false });
  const rubber = K.mat(game, 'rubber', '#ffffff');
  const glassDark = K.mat(game, 'crt', '#27305A', { rough: 0.06, rim: 0.7, rimColor: '#9FB6FF', env: 0.6 });
  const shag = K.mat(game, 'fabric', '#ffffff', { map: K.tex.shag('#B8481E', '#E8A92E', { size: 256 }), rough: 1, rim: 0.3 });
  const lit = opts.lit !== false;
  const CREAM = '#F3E7CC', BROWN = '#5A3A22';
  const M = { plastic: K.mat(game, 'plastic', '#ffffff', { rough: 0.4 }) };
  const addG = (geo, mat, col, o) => g.add(tm(geo, mat, col, o));

  // ---- cargo shell: rounded cross-section tube along x (open at the rear) + shag lining
  const sec = rrShape4(W, yt - yb, [0.12, 0.12, 0.26, 0.26], 0, (yb + yt) / 2);
  const holeW = W - 0.1, holeB = yb + 0.16, holeT = yt - 0.05;
  sec.holes.push(new THREE.Path(rrShape4(holeW, holeT - holeB, [0.05, 0.05, 0.2, 0.2], 0, (holeB + holeT) / 2).getPoints(5)));
  const cargoLen = xr - xc;
  const toX = (geo, x0) => { geo.rotateY(Math.PI / 2); geo.translate(x0, 0, 0); return geo; };
  const shell = K.extrude(sec, cargoLen, { bevel: 0.015, bevelSeg: 2, curveSeg: 6 }).clone();   // bevel < half the wall gap (else the cap loses its hole)
  addG(toX(shell, (xc + xr) / 2), body, CREAM);
  const lin = rrShape4(holeW - 0.008, holeT - holeB - 0.008, [0.05, 0.05, 0.2, 0.2], 0, (holeB + holeT) / 2);
  lin.holes.push(new THREE.Path(rrShape4(holeW - 0.06, holeT - holeB - 0.05, [0.04, 0.04, 0.18, 0.18], 0, (holeB + holeT) / 2 + 0.005).getPoints(5)));
  const lining = K.extrude(lin, cargoLen - 0.08, { bevel: 0, curveSeg: 5 }).clone();
  K.uvScale(lining, 2.2, 2.2);
  g.add(K.m(toX(lining, (xc + xr) / 2 - 0.02), shag));
  // rubber mat floor + wheel-well humps + front bulkhead (behind the seats)
  g.add(K.m(pxUV(xf(cbox(cargoLen - 0.2, 0.03, holeW - 0.1, 0.008), { pos: [(xc + xr) / 2 + 0.05, holeB + 0.035, 0] }), 512, 256, 1024, 512, 1024, 512), atlas));
  for (const s of [-1, 1]) addG(cbox(0.9, 0.3, 0.3, 0.06), shag, null, { pos: [VAN.wheels[1], holeB + 0.14, s * (holeW / 2 - 0.16)] });
  addG(cbox(0.05, holeT - holeB - 0.05, holeW - 0.06, 0.01), body, '#6A4A3A', { pos: [xc + 0.08, (holeB + holeT) / 2, 0] });
  // rear door frame ring (cream trim) + chrome rear bumper + tail lights + plate
  const ring = rrShape4(W + 0.03, yt - yb + 0.03, [0.13, 0.13, 0.27, 0.27], 0, (yb + yt) / 2);
  ring.holes.push(new THREE.Path(rrShape4(holeW - 0.02, holeT - holeB, [0.05, 0.05, 0.2, 0.2], 0, (holeB + holeT) / 2).getPoints(5)));
  addG(toX(K.extrude(ring, 0.05, { bevel: 0.015, bevelSeg: 1, curveSeg: 6 }).clone(), xr - 0.01), body, '#E8DCC0');
  addG(K.box(0.2, 0.14, W + 0.06, 0.045), chrome, null, { pos: [xr + 0.06, yb + 0.02, 0] });
  addG(cbox(0.24, 0.05, 0.7, 0.02), rubber, '#2A2430', { pos: [xr + 0.06, yb + 0.1, 0] });
  for (const s of [-1, 1]) {
    g.add(K.m(pxUV(xf(cbox(0.05, 0.36, 0.13, 0.015), { pos: [xr + 0.02, yb + 0.5, s * (hw - 0.02)] }), 896, 128, 960, 256, 1024, 512), atlas));
  }
  g.add(K.m(pxUV(decal(0.4, 0.2).rotateY(-Math.PI / 2), 640, 128, 896, 256, 1024, 512), atlas, { pos: [xr + 0.165, yb + 0.02, 0] }));

  // ---- cab: side profile extruded across the width (pillowy bevel), joint band at xc
  const cabPts = [[xc + 0.03, yb], [-2.28, yb], [-2.47, yb + 0.12], [-2.5, 0.98], [-2.42, 1.14], [-1.98, 1.22], [-1.5, yt - 0.02], [xc + 0.03, yt]];
  const cab = K.extrude(cabPts, W, { bevel: 0.16, bevelSeg: 2, round: 0.1, curveSeg: 4 }).clone();
  addG(cab, body, CREAM);
  const band = rrShape4(W + 0.04, yt - yb + 0.04, [0.14, 0.14, 0.28, 0.28], 0, (yb + yt) / 2);
  addG(toX(K.extrude(band, 0.12, { bevel: 0.03, bevelSeg: 1, curveSeg: 6 }).clone(), xc + 0.02), body, PAL.burntOrange);
  // windshield + side windows + porthole windows
  const wsA = [-1.98, 1.22], wsB = [-1.5, yt - 0.02];
  const wsLen = Math.hypot(wsB[0] - wsA[0], wsB[1] - wsA[1]) - 0.14;
  const ws = K.extrude(K.roundRect(1.5, wsLen, 0.12), 0.03, { bevel: 0.01, bevelSeg: 1, curveSeg: 4 }).clone();
  ws.rotateY(Math.PI / 2);                              // shape plane -> YZ, thickness along x
  const ang = Math.atan2(wsB[1] - wsA[1], wsB[0] - wsA[0]);
  ws.rotateZ(ang - Math.PI / 2);
  addG(ws, glassDark, null, { pos: [(wsA[0] + wsB[0]) / 2 - Math.sin(ang) * 0.016, (wsA[1] + wsB[1]) / 2 + Math.cos(ang) * 0.016, 0] });
  const sideWin = [[-1.62, 1.4], [-1.02, 1.4], [-1.02, 1.84], [-1.4, 1.84], [-1.66, 1.54]];
  for (const s of [-1, 1]) {
    addG(K.extrude(sideWin, 0.02, { bevel: 0.006, bevelSeg: 1, round: 0.06 }), glassDark, null, { pos: [0, 0, s * (hw + 0.002)] });
    addG(K.tube(ring2(0.2, 16).map(([a, b]) => [1.85 + a, 1.58 + b, 0]), 0.025, { seg: 16, radial: 4, closed: true }), chrome, null, { pos: [0, 0, s * (hw + 0.012)] });
    addG(new THREE.CircleGeometry(0.2, 18).rotateY(s < 0 ? Math.PI : 0), glassDark, null, { pos: [1.85, 1.58, s * (hw + 0.006)] });
  }
  // ---- wheel wells (dark decals), wood panels with arch notches + trim, 70s tri-stripe, logo
  const wellM = K.mat(game, 'paint', '#2A2232', { rough: 0.9 });
  for (const s of [-1, 1]) for (const xw of VAN.wheels) {
    const R = wr + 0.12, yl = yb - wr + 0.01, dx = Math.sqrt(R * R - yl * yl), a0 = Math.atan2(yl, dx);
    const arch = new THREE.Shape(); arch.moveTo(dx, yl); arch.absarc(0, 0, R, a0, Math.PI - a0, false); arch.lineTo(dx, yl);
    const ag = new THREE.ShapeGeometry(arch, 12);
    if (s < 0) ag.rotateY(Math.PI);
    addG(ag, wellM, null, { pos: [xw, wr, s * (hw + 0.004)] });
  }
  const panelShape = vanPanelShape(-2.3, xr - 0.06, 0.58, 1.18, VAN.wheels, wr + 0.14, wr);
  const panel = K.extrude(panelShape, 0.022, { bevel: 0.008, bevelSeg: 1, curveSeg: 6 }).clone();
  { const uv = panel.attributes.uv; for (let i = 0; i < uv.count; i++) { const u = uv.getX(i), v = uv.getY(i); uv.setXY(i, v * 1.2, u * 0.6); } }
  for (const s of [-1, 1]) g.add(K.m(panel, wood, { pos: [0, 0, s * (hw + 0.012)] }));
  const trimPts = panelShape.getPoints(6).map((p) => [p.x, p.y, 0]);
  for (const s of [-1, 1]) addG(K.tube(trimPts, 0.016, { seg: 36, radial: 3, closed: true }), body, null, { pos: [0, 0, s * (hw + 0.024)] });
  [[PAL.burntOrange, 1.23], [PAL.harvestGold, 1.29], [BROWN, 1.35]].forEach(([col, y]) => {
    for (const s of [-1, 1]) addG(cbox(xr + 2.28 - 0.1, 0.048, 0.012, 0.004), body, col, { pos: [(xr - 2.28) / 2 - 0.02, y, s * (hw + 0.007)] });
  });
  for (const s of [-1, 1]) {
    const lg = pxUV(decal(1.6, 0.4), 0, 0, 640, 160, 1024, 512);
    if (s > 0) lg.rotateY(Math.PI);
    const lm = K.m(lg, decalM, { pos: [0.4, 1.6, s * (hw + 0.009)] });
    lm.userData.noAO = true;
    g.add(lm);
  }
  // ---- front: grille, headlights, turn signals, bumper, plate, badge
  g.add(K.m(pxUV(xf(cbox(0.05, 0.3, 0.9, 0.015), { pos: [-2.49, 0.86, 0] }), 896, 0, 1024, 128, 1024, 512), atlas));
  addG(K.tube(rrXYloop(0.3, 0.92, 0.06).map(([z, y]) => [0, y, z]), 0.02, { seg: 30, radial: 4, closed: true }), chrome, null, { pos: [-2.515, 0.86, 0] });
  const lens = lensMats(game, '#FFF2C8', 1.6);
  const headlights = [];
  for (const s of [-1, 1]) {
    addG(new THREE.LatheGeometry([[0, 0.05], [0.1, 0.05], [0.125, 0.035], [0.13, 0.0]].map(([r, y]) => new THREE.Vector2(r, y)), 16).rotateZ(Math.PI / 2), chrome, null, { pos: [-2.49, 0.9, s * 0.66] });
    const hl = lightMesh(new THREE.SphereGeometry(0.1, 12, 5, 0, TAU, 0, Math.PI / 2).rotateZ(Math.PI / 2), opts.headlights ? lens.on : K.mat(game, 'ceramic', '#CFCBBE', { rough: 0.35, rim: 0.35, env: 0.08 }), { pos: [-2.535, 0.9, s * 0.66], name: 'headlight' });
    hl.scale.set(0.35, 1, 1);
    g.add(hl); headlights.push(hl);
    g.add(K.m(pxUV(xf(cbox(0.04, 0.1, 0.16, 0.012), { pos: [-2.47, 0.66, s * 0.72] }), 960, 128, 1024, 256, 1024, 512), atlas));
  }
  addG(K.box(0.22, 0.15, W + 0.08, 0.045), chrome, null, { pos: [-2.5, 0.56, 0] });
  g.add(K.m(pxUV(decal(0.4, 0.2).rotateY(Math.PI / 2), 640, 0, 896, 128, 1024, 512), atlas, { pos: [-2.615, 0.56, 0] }));
  addG(new THREE.CylinderGeometry(0.07, 0.075, 0.025, 16).rotateZ(Math.PI / 2), body, '#2F5BD3', { pos: [-2.5, 1.06, 0] });
  // mirrors (west-coast), door handles, fuel door, side markers
  for (const s of [-1, 1]) {
    addG(K.tube([[-1.9, 1.42, s * hw], [-1.98, 1.44, s * (hw + 0.14)], [-1.98, 1.62, s * (hw + 0.18)]], 0.012, { seg: 8, radial: 4 }), chrome, null);
    addG(cbox(0.05, 0.3, 0.16, 0.02), chrome, null, { pos: [-1.99, 1.62, s * (hw + 0.2)] });
    addG(new THREE.PlaneGeometry(0.13, 0.26).rotateY(-Math.PI / 2), glassDark, null, { pos: [-1.962, 1.62, s * (hw + 0.2)] });
    addG(cbox(0.14, 0.03, 0.03, 0.01), chrome, null, { pos: [-1.2, 1.3, s * (hw + 0.02)] });
    addG(cbox(0.14, 0.03, 0.03, 0.01), chrome, null, { pos: [0.1, 1.3, s * (hw + 0.02)] });
    addG(cbox(0.05, 0.03, 0.02, 0.006), K.glow(game, '#FFB347', 1.4), null, { pos: [-2.2, 1.0, s * (hw + 0.008)] });
  }
  addG(new THREE.CylinderGeometry(0.07, 0.07, 0.02, 12).rotateX(Math.PI / 2), chrome, null, { pos: [-0.3, 1.1, hw + 0.01] });
  // running-board side step under the sliding door (-z)
  addG(cbox(1.1, 0.05, 0.16, 0.012), rubber, '#3A3446', { pos: [-0.1, 0.46, -hw - 0.04] });
  // chassis skirt + exhaust
  addG(cbox(4.6, 0.22, W - 0.62, 0.02), rubber, '#2A2430', { pos: [-0.05, 0.42, 0] });
  addG(K.cyl(0.035, 0.035, 0.3, { seg: 8, bevel: 0.005 }).clone().rotateZ(Math.PI / 2), chrome, null, { pos: [xr - 0.1, 0.3, 0.55] });

  // ---- wheels: fat whitewall tires + chrome dog-dish caps
  const tireProf = [[0.2, -0.125], [0.238, -0.132], [0.242, -0.133], [0.3, -0.135], [0.304, -0.134], [wr - 0.025, -0.12], [wr, -0.06], [wr, 0.06], [wr - 0.025, 0.12], [0.304, 0.134], [0.3, 0.135], [0.242, 0.133], [0.238, 0.132], [0.2, 0.125]];
  const tire = new THREE.LatheGeometry(tireProf.map(([r, y]) => new THREE.Vector2(r, y)), 14);
  K.tint(tire, (x, y, z) => { const r = Math.hypot(x, z); return Math.abs(y) > 0.1 && r > 0.24 && r < 0.302 ? new THREE.Color('#F2EEE4') : new THREE.Color('#2E2836'); });
  tire.rotateX(Math.PI / 2);
  const cap = new THREE.LatheGeometry([[0, 0.02], [0.2, 0.02], [0.215, 0.0], [0.2, -0.02], [0.15, -0.04], [0.06, -0.055], [0, -0.058]].reverse().map(([r, y]) => new THREE.Vector2(r, y)), 12);
  cap.rotateX(Math.PI / 2);
  for (const xw of VAN.wheels) for (const s of [-1, 1]) {
    const q = s < 0 ? 0 : Math.PI;
    g.add(K.m(tire, rubber, { pos: [xw, wr, s * wz], rot: [0, q, 0] }));
    g.add(K.m(cap, chrome, { pos: [xw, wr, s * (wz + 0.11)], rot: [0, q, 0] }));
  }

  // ---- roof: rack rails, mast housing + telescoping mast + dish (parts.mast)
  for (const s of [-1, 1]) {
    addG(K.tube([[-1.2, yt + 0.02, s * 0.78], [-1.15, yt + 0.12, s * 0.78], [1.9, yt + 0.12, s * 0.78], [1.95, yt + 0.02, s * 0.78]], 0.022, { seg: 16, radial: 5 }), chrome, null);
  }
  for (let i = 0; i < 4; i++) addG(new THREE.CylinderGeometry(0.018, 0.018, 1.56, 6).rotateX(Math.PI / 2), chrome, null, { pos: [-0.8 + i * 0.8, yt + 0.12, 0] });
  addG(new THREE.CylinderGeometry(0.16, 0.18, 0.2, 14).translate(0, 0.1, 0), body, '#E8DCC0', { pos: [1.2, yt - 0.02, 0.2] });
  const mast = new THREE.Group();
  mast.name = 'mast'; mast.userData.noMerge = true;
  mast.position.set(1.2, yt + 0.16, 0.2);
  const mt = clamp(opts.mast ?? 1, 0, 1);
  const segs = [[0.075, 1.3], [0.06, 1.2], [0.047, 1.1]];
  let my = 0;
  segs.forEach(([r, l], i) => {
    const ext = i === 0 ? l : l * mt;
    mast.add(tm(new THREE.CylinderGeometry(r, r, l, 10).translate(0, l / 2, 0), chrome, null, { pos: [0, my + (i ? ext - l : 0), 0] }));
    mast.add(tm(new THREE.CylinderGeometry(r + 0.015, r + 0.015, 0.05, 10).translate(0, 0.025, 0), body, '#2A2430', { pos: [0, my + (i ? ext - l : 0) + l - 0.05, 0] }));
    my += ext - 0.05;
  });
  const head = new THREE.Group();
  head.name = 'mastHead'; head.userData.noMerge = true;
  head.position.set(0, my, 0);
  head.rotation.y = -0.6;
  head.add(tm(cbox(0.2, 0.14, 0.2, 0.025), body, '#E8DCC0', { pos: [0, 0.07, 0] }));
  const dish = K.lathe([[0, 0.0], [0.12, 0.012], [0.24, 0.05], [0.33, 0.1], [0.34, 0.12], [0.3, 0.115], [0.2, 0.07], [0, 0.04]], { seg: 16 }).clone();
  dish.rotateX(-Math.PI / 2);
  head.add(tm(dish, body, '#F2EEE4', { pos: [0, 0.3, -0.08], rot: [0.25, 0, 0] }));
  head.add(tm(K.cyl(0.015, 0.015, 0.3, { seg: 6, bevel: 0.004 }).clone().rotateX(-Math.PI / 2), chrome, null, { pos: [0, 0.3, -0.1], rot: [0.25, 0, 0] }));
  head.add(tm(K.cyl(0.035, 0.03, 0.06, { seg: 8, bevel: 0.008 }).clone().rotateX(-Math.PI / 2), body, '#E23B3B', { pos: [0, 0.37, -0.38], rot: [0.25, 0, 0] }));
  head.add(tm(K.box(0.05, 0.3, 0.05, 0.015), chrome, null, { pos: [0, 0.2, 0] }));
  mast.add(head);
  g.add(mast);
  // coiled cable hanging off the mast base
  addG(K.tube(ring2(0.12, 14).map(([a, b], i) => [1.32 + a * 0.3, yt + 0.3 + b, 0.45 + i * 0.004]), 0.012, { seg: 28, radial: 4, closed: false }), rubber, '#2A2430');

  // ---- rear doors (open), pivot at the rear corners
  const doorAng = opts.doors ?? 1.75;
  const doors = {};
  for (const s of [-1, 1]) {
    const piv = new THREE.Group();
    piv.name = s < 0 ? 'doorL' : 'doorR';
    piv.userData.noMerge = true;
    piv.position.set(xr + 0.02, 0, s * (hw - 0.02));
    piv.rotation.y = s < 0 ? doorAng : -doorAng;
    const dw = hw - 0.04, dh = holeT - holeB + 0.02;
    const dshape = rrShape4(dw, dh, s < 0 ? [0.04, 0.1, 0.2, 0.04] : [0.1, 0.04, 0.04, 0.2], 0, 0);
    const dgeo = K.extrude(dshape, 0.06, { bevel: 0.02, bevelSeg: 1, curveSeg: 5 }).clone();
    dgeo.rotateY(Math.PI / 2);                     // plane -> YZ (width along z)
    const zc = -s * (dw / 2 + 0.01);
    piv.add(tm(dgeo, body, CREAM, { pos: [0.03, (holeB + holeT) / 2, zc] }));
    // window, wood lower panel + trim, handle, tail-side reflector
    const dwin = K.extrude(K.roundRect(0.34, 0.44, 0.06), 0.09, { bevel: 0.005, bevelSeg: 1, curveSeg: 4 }).clone().rotateY(Math.PI / 2);
    piv.add(tm(dwin, glassDark, null, { pos: [0.03, 1.66, zc] }));
    const dp = K.extrude(K.roundRect(dw - 0.12, 0.5, 0.05), 0.02, { bevel: 0.006, bevelSeg: 1, curveSeg: 4 }).clone();
    { const uv = dp.attributes.uv; for (let i = 0; i < uv.count; i++) { const u = uv.getX(i), v = uv.getY(i); uv.setXY(i, v * 1.2, u * 0.6); } }
    dp.rotateY(Math.PI / 2);
    piv.add(K.m(dp, wood, { pos: [0.068, 0.9, zc] }));
    piv.add(tm(cbox(0.03, 0.03, 0.14, 0.008), chrome, null, { pos: [0.08, 1.28, zc - s * 0.28] }));
    // inside face: shag-carpet card
    piv.add(tm(cbox(0.02, dh - 0.16, dw - 0.14, 0.006), shag, null, { pos: [-0.012, (holeB + holeT) / 2, zc] }));
    for (const y of [0.9, 1.9]) piv.add(tm(new THREE.CylinderGeometry(0.02, 0.02, 0.12, 8), chrome, null, { pos: [0.0, y, 0] }));
    g.add(piv);
    doors[piv.name] = piv;
  }

  // ---- cargo interior: equipment rack (+z wall), monitor facing the rear, stool, flight case, radio, dome light
  const rx0 = -0.5, rack = [[0, 0.3], [1, 0.3], [2, 0.3], [3, 0.3]];
  addG(cbox(1.5, 1.28, 0.5, 0.02), body, '#3A3444', { pos: [rx0 + 0.7, holeB + 0.05 + 0.64, hw - 0.36] });
  rack.forEach(([r]) => {
    const y = holeB + 0.24 + r * 0.3;
    g.add(K.m(pxUV(decal(1.4, 0.26), 0, 256 + r * 64, 512, 320 + r * 64, 1024, 512), atlas, { pos: [rx0 + 0.7, y, hw - 0.618] }));
  });
  // counter + monitor at the rear center (faces +x)
  addG(cbox(0.5, 0.05, 0.9, 0.012), body, '#B07A45', { pos: [xr - 0.55, holeB + 0.52, 0] });
  for (const s of [-1, 1]) addG(K.cyl(0.02, 0.02, 0.5, { seg: 6, bevel: 0.004 }), chrome, null, { pos: [xr - 0.55, holeB + 0.02, s * 0.35] });
  const mon = miniMonitor(game, M, { w: 0.5, h: 0.38, d: 0.42, card: 'station_id', group: 'scr_feed_yard', id: 'van_rear_tv', shell: '#E3662B' });
  mon.grp.position.set(xr - 0.6, holeB + 0.545, 0.05);
  mon.grp.rotation.y = -Math.PI / 2 + 0.05;
  g.add(mon.grp);
  // stool, flight case, cable reel
  addG(new THREE.CylinderGeometry(0.17, 0.17, 0.06, 14), shag, null, { pos: [0.9, holeB + 0.48, -0.3] });
  addG(K.cyl(0.03, 0.03, 0.43, { seg: 8, bevel: 0.006 }), chrome, null, { pos: [0.9, holeB + 0.03, -0.3] });
  addG(cbox(0.6, 0.4, 0.4, 0.03), body, '#3A3444', { pos: [0.1, holeB + 0.25, -0.55] });
  addG(cbox(0.62, 0.05, 0.42, 0.015), chrome, null, { pos: [0.1, holeB + 0.25, -0.55] });
  addG(new THREE.CylinderGeometry(0.2, 0.2, 0.18, 16).rotateX(Math.PI / 2), body, '#E23B3B', { pos: [1.45, holeB + 0.5, -0.72] });
  // portable radio (EE toy spot): chunky 70s transistor radio on the counter
  const radio = new THREE.Group();
  radio.name = 'radio'; radio.userData.noMerge = true;
  radio.position.set(xr - 0.5, holeB + 0.545, -0.36);
  radio.rotation.y = -Math.PI / 2 - 0.3;
  radio.add(tm(cbox(0.3, 0.18, 0.1, 0.025), M.plastic, '#8C9A3A', { pos: [0, 0.09, 0] }));
  radio.add(tm(new THREE.CircleGeometry(0.055, 14).rotateY(Math.PI), M.plastic, '#3A3444', { pos: [-0.07, 0.09, -0.052] }));
  radio.add(tm(K.box(0.1, 0.05, 0.01, 0.004), M.plastic, '#F4E6B8', { pos: [0.07, 0.12, -0.052] }));
  radio.add(tm(K.tube([[-0.1, 0.18, 0], [-0.08, 0.24, 0], [0.08, 0.24, 0], [0.1, 0.18, 0]], 0.01, { seg: 10, radial: 4 }), chrome, null));
  radio.add(tm(K.cyl(0.004, 0.006, 0.4, { seg: 4, bevel: 0.001 }), chrome, null, { pos: [0.11, 0.17, 0.02], rot: [0, 0, -0.4] }));
  g.add(radio);
  const domeL = lightMesh(new THREE.SphereGeometry(0.1, 12, 6, 0, TAU, 0, Math.PI / 2).rotateX(Math.PI), lit ? K.glow(game, PAL.tungsten, 1.8) : K.mat(game, 'ceramic', '#F0E6D0'), { pos: [1.2, holeT - 0.035, 0], name: 'domeLight' });
  domeL.scale.set(1.4, 0.5, 1);
  g.add(domeL);

  g.userData.parts = { doorL: doors.doorL, doorR: doors.doorR, mast, mastHead: head, radio, domeLight: domeL, headlights };
  g.userData.screens = [{ mesh: mon.scr, group: 'scr_feed_yard', id: 'van_rear_tv' }];
  g.userData.lightAnchors = lit ? [{ pos: [xr - 0.9, 1.75, 0], color: PAL.tungsten, intensity: 0.9, distance: 3.2, flicker: 0 }] : [];
  g.userData.colliders = [{ min: [-2.62, 0, -hw - 0.05], max: [xr + 0.18, yt + 0.2, hw + 0.05] }, { min: [xr, 0, -hw - 0.22], max: [xr + 0.95, 2.05, -hw + 0.02] }, { min: [xr, 0, hw - 0.02], max: [xr + 0.95, 2.05, hw + 0.22] }];
  g.userData.interact = null;
  g.remove(mast);
  K.finish(game, g, { ao: { res: 40, rays: 10, strength: 0.85 } });
  g.add(mast);
  K.merge(head);
  K.merge(mast);
  ensureCol(mast);
  g.userData.stats = K.stats(g);
  return g;
}, { category: CAT, tags: ['yard', 'van', 'vehicle', 'screens'], size: [5.3, 5.3, 2.4], hero: true, cache: false, desc: '"Action 13 News" wood-paneled 70s van: FRONT at -x, open rear doors at +x (parts.doorL/R), shag cargo with rack + rear feed TV (scr_feed_yard), radio (parts.radio), telescoping mast + dish (parts.mast); opts {lit, doors, mast, headlights}' });
// closed loop of a rounded rectangle in the (u, v) plane
function rrXYloop(h, w, r, steps = 3) {
  const pts = [];
  const hx = w / 2 - r, hy = h / 2 - r;
  for (const [cx, cy, a0] of [[hx, hy, 0], [-hx, hy, Math.PI / 2], [-hx, -hy, Math.PI], [hx, -hy, Math.PI * 1.5]]) {
    for (let s = 0; s <= steps; s++) { const a = a0 + (s / steps) * (Math.PI / 2); pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); }
  }
  return pts;
}
function ring2(r, n) {
  const pts = [];
  for (let i = 0; i < n; i++) { const a = (i / n) * TAU; pts.push([Math.cos(a) * r, Math.sin(a) * r]); }
  return pts;
}

registerScene('out_van_rear', {
  floor: '#4A4652', wall: '#1E2344', room: [30, 30], wallH: 0.01, hemi: 0.75,
  items: [{ id: 'yd_news_van', pos: [0, 2], rotY: 0 }],
  cam: { pos: [6.2, 2.1, -1.2], target: [1.4, 1.1, 2.1], fov: 50 },
});

// =================================================================================================== SODIUM LAMP POST
// 6.6 m galvanized pole on a concrete pier, curved davit arm reaching toward -z, 70s cobra-head luminaire with a glowing
// sodium refractor (parts.lamp, noMerge) + photocell, a soft additive light cone (parts.beam, opts.beam=false to skip).
// Light anchor at the lens (sodium #FFB347). opts.lit=false builds it dark.
function beamTex() {
  return K.tex.canvas('out_beam', 64, 256, (ctx, w, h) => {
    const gr = ctx.createLinearGradient(0, 0, 0, h);
    gr.addColorStop(0, 'rgba(255,255,255,0.9)'); gr.addColorStop(0.35, 'rgba(255,255,255,0.35)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h);
    const gx = ctx.createLinearGradient(0, 0, w, 0);
    gx.addColorStop(0, 'rgba(0,0,0,1)'); gx.addColorStop(0.25, 'rgba(0,0,0,0)'); gx.addColorStop(0.75, 'rgba(0,0,0,0)'); gx.addColorStop(1, 'rgba(0,0,0,1)');
    ctx.globalCompositeOperation = 'destination-out'; ctx.fillStyle = gx; ctx.fillRect(0, 0, w, h);
  }, { repeat: false });
}
function beamCone(game, color, topR, botR, h, intensity = 0.5) {
  const geo = new THREE.CylinderGeometry(topR, botR, h, 20, 1, true);
  geo.translate(0, -h / 2, 0);
  const mat = K.glow(game, color, intensity, { map: beamTex(), additive: true, side: THREE.DoubleSide, fog: true });
  const m = K.m(geo, mat, { name: 'beam' });
  m.userData.noMerge = true; m.userData.noAO = true; m.userData.noOcclude = true; m.userData.noShadow = true;
  m.renderOrder = 5;
  return m;
}
function cobraHead(game, M, lit, color = PAL.sodium) {
  const grp = new THREE.Group();
  // housing: long rounded teardrop (lathe along x), flattened
  const prof = [[0, -0.34], [0.07, -0.33], [0.13, -0.26], [0.16, -0.1], [0.16, 0.12], [0.13, 0.26], [0.08, 0.34], [0, 0.36]];
  const hous = K.lathe(prof, { seg: 16, round: 0.03, steps: 1 }).clone();
  hous.rotateZ(-Math.PI / 2);
  hous.scale(1, 0.62, 1);
  grp.add(tm(hous, M.body, '#C9CED6', { pos: [0, 0, 0] }));
  // refractor bowl underneath
  const bowl = new THREE.SphereGeometry(1, 16, 8, 0, TAU, Math.PI / 2, Math.PI / 2);
  bowl.scale(0.26, 0.09, 0.14);
  const lamp = lightMesh(bowl, lit ? K.glow(game, color, 2.8) : K.mat(game, 'crt', '#8A6A4A', { rough: 0.2 }), { pos: [0.04, -0.07, 0], name: 'lamp' });
  grp.add(lamp);
  grp.add(tm(K.tube(ring2(1, 20).map(([a, b]) => [0.04 + a * 0.265, -0.068, b * 0.145]), 0.012, { seg: 20, radial: 4, closed: true }), M.body, '#8E959E'));
  // photocell + seam ridge
  grp.add(tm(K.cyl(0.035, 0.04, 0.05, { seg: 10, bevel: 0.01 }), M.body, '#3A3444', { pos: [-0.08, 0.09, 0] }));
  grp.add(tm(K.cyl(0.03, 0.03, 0.02, { seg: 10, bevel: 0.006 }), M.body, '#F2C230', { pos: [-0.08, 0.135, 0] }));
  grp.add(tm(K.tube([[-0.32, 0.04, 0], [0, 0.1, 0], [0.3, 0.05, 0]], 0.012, { seg: 10, radial: 4 }), M.body, '#B4BCC6'));
  return { grp, lamp };
}
registerProp('yd_sodium_post', (game, opts = {}) => {
  const g = K.prop('yd_sodium_post');
  const lit = opts.lit !== false;
  const M = { body: K.mat(game, 'metal', '#ffffff', { rough: 0.42 }) };
  const conc = K.mat(game, 'paint', '#ffffff', { map: concreteTex(), rough: 0.92 });
  const H = opts.height ?? 6.6, reach = 1.7;
  // pier + base plate + bolts + skirt cover
  g.add(K.m(K.taper(K.cyl(0.3, 0.3, 0.42, { seg: 16, bevel: 0.05 }), { axis: 'y', k: 0.86 }), conc));
  g.add(tm(K.cyl(0.2, 0.2, 0.03, { seg: 12, bevel: 0.008 }), M.body, '#9CA3AD', { pos: [0, 0.42, 0] }));
  for (let i = 0; i < 4; i++) { const a = i * Math.PI / 2 + Math.PI / 4; g.add(tm(new THREE.CylinderGeometry(0.022, 0.024, 0.06, 6), M.body, '#7E8792', { pos: [Math.cos(a) * 0.15, 0.47, Math.sin(a) * 0.15] })); }
  g.add(tm(K.lathe([[0.14, 0], [0.12, 0.16], [0.085, 0.22]], { seg: 14 }), M.body, '#B8BEC6', { pos: [0, 0.44, 0] }));
  // tapered pole with a hand-hole plate + number tag
  g.add(tm(K.cyl(0.055, 0.09, H - 0.5, { seg: 14, bevel: 0.01 }), M.body, '#B8BEC6', { pos: [0, 0.44, 0] }));
  g.add(tm(cbox(0.09, 0.16, 0.04, 0.012), M.body, '#9CA3AD', { pos: [0, 1.0, -0.085] }));
  g.add(K.m(pxUV(decal(0.1, 0.14), 0, 384, 384, 512, 1024, 512), K.mat(game, 'paint', '#ffffff', { map: towerSigns(), rough: 0.6 }), { pos: [0, 2.2, -0.083] }));
  // davit arm: a quarter bend toward -z, then level out
  const top = H - 0.06;
  const arm = [[0, top - 0.6, 0], [0, top - 0.1, -0.02], [0, top + 0.12, -0.3], [0, top + 0.18, -0.8], [0, top + 0.12, -reach + 0.2], [0, top + 0.06, -reach]];
  g.add(tm(K.tube(arm, 0.045, { seg: 24, radial: 8 }), M.body, '#B8BEC6'));
  g.add(tm(K.lathe([[0, 0], [0.07, 0], [0.07, 0.03], [0.04, 0.08], [0, 0.09]], { seg: 12, round: 0.02, steps: 1 }), M.body, '#9CA3AD', { pos: [0, top - 0.62, 0] }));
  const ch = cobraHead(game, M, lit);
  ch.grp.position.set(0, top + 0.02, -reach - 0.2);
  ch.grp.rotation.set(0, Math.PI / 2, 0.06);
  g.add(ch.grp);
  const lensPos = [0, top - 0.06, -reach - 0.24];
  let beam = null;
  if (lit && opts.beam !== false) { beam = beamCone(game, PAL.sodium, 0.18, 2.3, top - 0.1, 0.32); beam.position.set(lensPos[0], lensPos[1], lensPos[2]); g.add(beam); }
  g.userData.parts = { lamp: ch.lamp, beam };
  g.userData.lightAnchors = lit ? [{ pos: [lensPos[0], lensPos[1] - 0.15, lensPos[2]], color: PAL.sodium, intensity: 3.2, distance: 13, flicker: 0.02 }] : [];
  g.userData.colliders = [{ min: [-0.3, 0, -0.3], max: [0.3, 2.6, 0.3] }];
  if (beam) g.remove(beam);
  K.finish(game, g, { ao: { res: 60, dist: 0.3 } });
  if (beam) g.add(beam);
  return g;
}, { category: CAT, tags: ['yard', 'light', 'lamp', 'street'], size: [0.6, 6.8, 2.3], desc: '6.6 m sodium lamp post: concrete pier, davit arm toward -z, cobra head with glowing refractor (parts.lamp), soft light cone (parts.beam); anchor sodium 3.2/13 m (opts.lit, opts.beam, opts.height)' });

// =================================================================================================== CHAIN-LINK FENCE
// 3 m chain-link (GDD §5.7). yd_fence: one section along x (opts.len, default 3 m), posts at both ends (opts.posts
// 'both'|'left'|'none'), top rail, bottom wire, alpha-tested diamond mesh, 3-strand barbed wire on arms leaning to
// -z (the OUTSIDE by default; opts.flip leans them to +z), optional sign (opts.sign 'danger'|'private'|'wztv').
// yd_fence_post: terminal/corner post with a diagonal brace. yd_fence_gate: ajar double vehicle gate.
function chainTex() {
  return K.tex.canvas('out_chainlink', 256, 256, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    const n = 4, s = w / n;
    const draw = (col, lw, off) => {
      ctx.strokeStyle = col; ctx.lineWidth = lw; ctx.lineCap = 'round';
      for (let i = -n; i <= n * 2; i++) {
        ctx.beginPath(); ctx.moveTo(i * s + off, 0 + off); ctx.lineTo(i * s + h + off, h + off); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(i * s + off, h + off); ctx.lineTo(i * s + h + off, 0 + off); ctx.stroke();
      }
    };
    draw('rgba(40,36,56,0.55)', 9, 2);
    draw('#B9C0CA', 7, 0);
    draw('rgba(255,255,255,0.55)', 2, -1.5);
  }, { repeat: true });
}
function fenceSignTex() {
  return atlasTex('fence_signs', 512, 256, (ctx) => {
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    // private property (0,0)-(256,128)
    ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.roundRect(2, 2, 252, 124, 12); ctx.fill();
    ctx.fillStyle = '#C8201E'; ctx.beginPath(); ctx.roundRect(8, 8, 240, 44, 8); ctx.fill();
    ctx.fillStyle = '#F4F1E8'; fitText(ctx, 'NO TRESPASSING', 220, 28); ctx.fillText('NO TRESPASSING', 128, 31);
    ctx.fillStyle = '#2A1D2A'; fitText(ctx, 'WZTV PROPERTY', 220, 26, 'Titan One'); ctx.fillText('WZTV PROPERTY', 128, 78);
    fitText(ctx, 'VIOLATORS WILL BE PROSECUTED', 220, 12, 'Titan One'); ctx.fillText('VIOLATORS WILL BE PROSECUTED', 128, 106);
    // wztv (256,0)-(512,128)
    ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.roundRect(258, 2, 252, 124, 12); ctx.fill();
    ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(318, 64, 44, 0, TAU); ctx.fill();
    ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(318, 64, 38, 0, TAU); ctx.fill();
    ctx.fillStyle = '#F4F1E8'; font(ctx, 44, 'Titan One'); ctx.fillText('13', 318, 68);
    ctx.fillStyle = '#FFD23A'; fitText(ctx, 'WZTV', 140, 40); ctx.fillText('WZTV', 434, 50);
    ctx.fillStyle = '#F4F1E8'; fitText(ctx, 'TRANSMITTER SITE', 140, 16, 'Titan One'); ctx.fillText('TRANSMITTER SITE', 434, 88);
    // keep gate closed (0,128)-(256,256)
    ctx.fillStyle = '#F2C230'; ctx.beginPath(); ctx.roundRect(2, 130, 252, 124, 12); ctx.fill();
    ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 6; ctx.beginPath(); ctx.roundRect(10, 138, 236, 108, 8); ctx.stroke();
    ctx.fillStyle = '#2A1D2A'; fitText(ctx, 'KEEP GATE', 200, 34); ctx.fillText('KEEP GATE', 128, 172);
    fitText(ctx, 'CLOSED', 200, 40); ctx.fillText('CLOSED', 128, 214);
  });
}
function fenceMats(game) {
  const mesh = K.mat(game, 'metal', '#ffffff', { map: chainTex(), alphaTest: 0.45, side: THREE.DoubleSide, rough: 0.45, rim: 0.3 });
  mesh.alphaToCoverage = true;
  return {
    galv: K.mat(game, 'metal', C.galv, { rough: 0.42 }),
    mesh,
    sign: K.mat(game, 'paint', '#ffffff', { map: fenceSignTex(), rough: 0.5 }),
    tower: null,
  };
}
const FH = 3.0;
function fencePost(G, x, z, r, h, cap = true) {
  G.galv.push(pipeGeo(r, [x, 0, z], [x, h, z], 10, false));
  if (cap) G.galv.push(xf(K.lathe([[0, 0], [r + 0.012, 0], [r + 0.012, 0.03], [r * 0.7, 0.07], [0, 0.08]], { seg: 10 }), { pos: [x, h, z] }));
  G.galv.push(xf(new THREE.CylinderGeometry(r + 0.03, r + 0.05, 0.08, 10), { pos: [x, 0.04, z] }));
}
// barbed wire: arm leaning to side sz (-1/+1) at post x + 3 strands with tetra barbs between x0..x1
function barbArm(G, x, sz, h) {
  const a = [x, h - 0.05, 0], b = [x, h + 0.36, sz * 0.36];
  G.galv.push(bar8(0.05, 0.03, a, b, [1, 0, 0], 0.008));
}
function barbWire(G, x0, x1, sz, h, rnd) {
  for (let k = 0; k < 3; k++) {
    const t = (k + 1) / 3, y = h - 0.05 + 0.41 * t, z = sz * 0.36 * t;
    G.galv.push(pipeGeo(0.006, [x0, y, z], [x1, y, z], 4, false));
    for (let x = x0 + 0.12; x < x1 - 0.05; x += 0.22) {
      const tet = new THREE.TetrahedronGeometry(0.03);
      tet.scale(1, 0.5, 0.5);
      G.galv.push(xf(tet, { pos: [x + (rnd() - 0.5) * 0.04, y, z], rot: [rnd() * 3, rnd() * 3, rnd() * 3] }));
    }
  }
}
function meshPanel(w, h, x0 = 0, y0 = 0) {
  const pg = new THREE.PlaneGeometry(w, h);
  const uv = pg.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, (uv.getX(i) * w + x0) * 2.2, (uv.getY(i) * h + y0) * 2.2);
  return pg;
}
registerProp('yd_fence', (game, opts = {}) => {
  const g = K.prop('yd_fence');
  const L = opts.len ?? 3, hl = L / 2;
  const M = fenceMats(game);
  const G = { galv: [], sign: [] };
  const rnd = mulberry32((opts.seed ?? 1) * 17 + 3);
  const posts = opts.posts ?? 'both';
  const sz = opts.flip ? 1 : -1;
  if (posts !== 'none') { fencePost(G, -hl, 0, 0.045, FH); barbArm(G, -hl, sz, FH); }
  if (posts === 'both') { fencePost(G, hl, 0, 0.045, FH); barbArm(G, hl, sz, FH); }
  G.galv.push(pipeGeo(0.03, [-hl, FH - 0.08, 0.05], [hl, FH - 0.08, 0.05], 8, false));
  G.galv.push(pipeGeo(0.008, [-hl, 0.06, 0.05], [hl, 0.06, 0.05], 4, false));
  // wire ties
  for (let y = 0.4; y < FH - 0.2; y += 0.6) for (const x of [-hl, hl]) if (posts === 'both' || x < 0) G.galv.push(xf(new THREE.TorusGeometry(0.052, 0.006, 3, 8), { pos: [x, y, 0], rot: [Math.PI / 2, 0, 0] }));
  barbWire(G, -hl, hl, sz, FH, rnd);
  const mesh = K.m(meshPanel(L, FH - 0.12, (opts.seed ?? 0) * 0.37, 0), M.mesh, { pos: [0, (FH - 0.12) / 2 + 0.04, 0.05] });
  mesh.userData.noOcclude = true; mesh.userData.noAO = true;
  g.add(mesh);
  if (opts.sign) {
    const cell = { private: [0, 0, 256, 128], wztv: [256, 0, 512, 128], closed: [0, 128, 256, 256] }[opts.sign] || [0, 0, 256, 128];
    const sx = (rnd() - 0.5) * 0.6;
    G.sign.push(xf(pxUV(decal(0.62, 0.31), ...cell, 512, 256), { pos: [sx, 1.55, 0.02], rot: [0, 0, (rnd() - 0.5) * 0.06] }));
    G.sign.push(xf(pxUV(decal(0.62, 0.31).rotateY(Math.PI), ...cell, 512, 256), { pos: [sx, 1.55, 0.03], rot: [0, 0, (rnd() - 0.5) * 0.06] }));
  }
  g.add(K.m(mergeList(G.galv), M.galv));
  if (G.sign.length) g.add(K.m(mergeList(G.sign), M.sign));
  g.userData.colliders = [{ min: [-hl, 0, -0.08], max: [hl, FH, 0.12] }];
  return K.finish(game, g, { ao: { res: 48, dist: 0.2, height: 0.3 } });
}, { category: CAT, tags: ['yard', 'fence', 'wall'], size: [3.0, 3.45, 0.5], desc: '3 m chain-link section along x: posts, top rail, diamond mesh (alpha), barbed wire leaning to -z (opts.len, posts both|left|none, flip, sign private|wztv|closed, seed)' });

registerProp('yd_fence_post', (game, opts = {}) => {
  const g = K.prop('yd_fence_post');
  const M = fenceMats(game);
  const G = { galv: [] };
  fencePost(G, 0, 0, 0.065, FH + 0.05);
  G.galv.push(xf(new THREE.CylinderGeometry(0.085, 0.085, 0.05, 12), { pos: [0, FH - 0.1, 0] }));
  G.galv.push(xf(new THREE.CylinderGeometry(0.085, 0.085, 0.05, 12), { pos: [0, 0.6, 0] }));
  // diagonal brace + tension rod toward +x (the run it terminates)
  G.galv.push(pipeGeo(0.03, [0, 1.5, 0], [1.6, 1.5, 0], 8, false));
  G.galv.push(pipeGeo(0.009, [1.6, 1.5, 0], [0, 0.15, 0], 4, false));
  G.galv.push(pipeGeo(0.009, [0, 1.5, 0], [1.6, 0.15, 0], 4, false));
  G.galv.push(bar8(0.06, 0.035, [0, FH - 0.05, 0], [0, FH + 0.36, opts.flip ? 0.36 : -0.36], [1, 0, 0], 0.008));
  g.add(K.m(mergeList(G.galv), M.galv));
  g.userData.colliders = [{ min: [-0.1, 0, -0.1], max: [0.1, FH, 0.1] }];
  return K.finish(game, g, { ao: { res: 40, dist: 0.2 } });
}, { category: CAT, tags: ['yard', 'fence'], size: [1.7, 3.5, 0.5], desc: 'chain-link terminal/corner post with brace + tension rods toward +x, barb arm (opts.flip)' });

registerProp('yd_fence_gate', (game, opts = {}) => {
  const g = K.prop('yd_fence_gate');
  const M = fenceMats(game);
  const G = { galv: [], sign: [] };
  const rnd = mulberry32(99);
  const span = 4.6, hs = span / 2, LW = hs - 0.12, LH = 2.7;
  for (const s of [-1, 1]) {
    fencePost(G, s * hs, 0, 0.075, FH + 0.1);
    G.galv.push(bar8(0.06, 0.035, [s * hs, FH, 0], [s * hs, FH + 0.4, opts.flip ? 0.38 : -0.38], [1, 0, 0], 0.008));
  }
  const leaves = {};
  const ajar = opts.ajar ?? 0.5;
  for (const s of [-1, 1]) {
    const piv = new THREE.Group();
    piv.name = s < 0 ? 'leafL' : 'leafR';
    piv.userData.noMerge = true;
    piv.position.set(s * (hs - 0.1), 0, 0);
    piv.rotation.y = s < 0 ? 0 : -ajar;
    const L = { galv: [] };
    const x0 = 0, x1 = -s * LW, y0 = 0.14, y1 = LH;
    const frame = [[x0, y0, 0], [x1, y0, 0], [x1, y1, 0], [x0, y1, 0]];
    for (let i = 0; i < 4; i++) L.galv.push(pipeGeo(0.035, frame[i], frame[(i + 1) % 4], 8, false));
    for (const p of frame) L.galv.push(xf(new THREE.SphereGeometry(0.036, 8, 6), { pos: p }));
    L.galv.push(pipeGeo(0.025, [x0, (y0 + y1) / 2, 0], [x1, (y0 + y1) / 2, 0], 8, false));
    L.galv.push(pipeGeo(0.02, [x0, y0, 0], [x1, y1, 0], 6, false));
    for (const y of [0.5, 2.3]) L.galv.push(xf(new THREE.CylinderGeometry(0.05, 0.05, 0.12, 10), { pos: [0.02 * s, y, 0] }));
    // latch on the free end
    L.galv.push(xf(cbox(0.08, 0.14, 0.06, 0.012), { pos: [x1 + s * 0.04, 1.3, 0] }));
    piv.add(K.m(mergeList(L.galv), M.galv));
    const mesh = K.m(meshPanel(LW - 0.04, LH - 0.2, s * 0.3, 0), M.mesh, { pos: [x1 / 2, (y0 + y1) / 2, 0] });
    mesh.userData.noOcclude = true; mesh.userData.noAO = true;
    piv.add(mesh);
    g.add(piv);
    leaves[piv.name] = piv;
  }
  // loose chain + padlock hanging off the closed leaf's latch
  const chain = [];
  const cx = -hs + 0.1 + LW + 0.06;
  for (let i = 0; i < 9; i++) {
    const t = i / 8, x = cx + 0.02 + Math.sin(t * Math.PI) * 0.05, y = 1.28 - t * 0.5;
    chain.push(xf(new THREE.TorusGeometry(0.022, 0.006, 4, 8), { pos: [x, y, -0.05], rot: [0, i % 2 ? Math.PI / 2 : 0, 0] }));
  }
  chain.push(xf(cbox(0.07, 0.08, 0.035, 0.012), { pos: [cx + 0.03, 0.73, -0.05] }));
  chain.push(xf(new THREE.TorusGeometry(0.026, 0.008, 4, 10, Math.PI), { pos: [cx + 0.03, 0.77, -0.05] }));
  g.add(K.m(mergeList(chain), K.mat(game, 'brass', '#C8963C')));
  G.sign.push(xf(pxUV(decal(0.6, 0.3), 0, 128, 256, 256, 512, 256), { pos: [-1.2, 1.6, -0.02] }));
  G.sign.push(xf(pxUV(decal(0.6, 0.3).rotateY(Math.PI), 0, 128, 256, 256, 512, 256), { pos: [-1.2, 1.6, 0.02] }));
  barbWire(G, -hs, hs, opts.flip ? 1 : -1, FH + 0.05, rnd);
  g.add(K.m(mergeList(G.galv), M.galv));
  g.add(K.m(mergeList(G.sign), M.sign));
  g.userData.parts = leaves;
  g.userData.colliders = [
    { min: [-hs - 0.1, 0, -0.1], max: [-hs + 0.1, FH, 0.1] }, { min: [hs - 0.1, 0, -0.1], max: [hs + 0.1, FH, 0.1] },
    { min: [-hs, 0, -0.08], max: [-hs + LW, LH, 0.08] },
  ];
  K.finish(game, g, { ao: { res: 56, dist: 0.2, height: 0.3 } });
  return g;
}, { category: CAT, tags: ['yard', 'fence', 'gate'], size: [4.8, 3.5, 0.9], desc: 'chain-link double vehicle gate (4.6 m): left leaf closed with chain + padlock, right leaf ajar (parts.leafL/R, opts.ajar rad, opts.flip); colliders: posts + closed leaf only (the squeeze gap stays open)' });

// =================================================================================================== NEON "WZTV 13"
// Pink "WZTV" + blue "13" in a blue ring, glass neon tubes on standoffs over a navy backboard with a cream trim, halo
// cards, transformer can. WALL PROP: origin on the wall at the sign's bottom center, back at z = 0, faces -z.
// parts.neonPink / neonBlue (+ haloPink / haloBlue); setNeon(game, g, on) swaps lit/unlit. opts.lit.
const NEON_GLYPH = {
  W: [[[0, 1], [0.22, 0], [0.5, 0.64], [0.78, 0], [1, 1]]],
  Z: [[[0.02, 1], [0.98, 1], [0.02, 0], [0.98, 0]]],
  T: [[[0, 1], [1, 1]], [[0.5, 1], [0.5, 0]]],
  V: [[[0, 1], [0.5, 0], [1, 1]]],
  1: [[[0.12, 0.78], [0.5, 1], [0.5, 0]], [[0.12, 0], [0.88, 0]]],
  3: [[[0.05, 0.82], [0.25, 1], [0.72, 1], [0.92, 0.8], [0.8, 0.58], [0.45, 0.52], [0.82, 0.44], [0.95, 0.22], [0.72, 0], [0.25, 0], [0.05, 0.16]]],
};
function neonStroke(pts, ox, oy, sw, sh, round = 0.35) {
  const p2 = pts.map(([x, y]) => [ox + x * sw, oy + y * sh]);
  const r = K.roundProfile(p2, Math.min(sw, sh) * 0.14 * round * 3, 3);
  return r;
}
export function setNeon(game, g, on = true) {
  const P = g.userData.parts;
  if (!P?.neonPink) return;
  P.neonPink.material = on ? K.glow(game, PAL.neonPink, 2.6) : K.mat(game, 'plastic', '#E8B8C8', { transparent: true, opacity: 0.7 });
  P.neonBlue.material = on ? K.glow(game, '#3F76FF', 2.6) : K.mat(game, 'plastic', '#B8C8E8', { transparent: true, opacity: 0.7 });
  if (P.haloPink) P.haloPink.visible = on;
  if (P.haloBlue) P.haloBlue.visible = on;
}
registerProp('yd_neon_wztv', (game, opts = {}) => {
  const g = K.prop('yd_neon_wztv');
  const lit = opts.lit !== false;
  const paint = K.mat(game, 'lacquer', '#ffffff', { rough: 0.45 });
  const galv = K.mat(game, 'metal', C.galv, { rough: 0.45 });
  // layout in "reading" coordinates u (left -> right as seen from the front); world x = -u (the viewer's right is -x)
  const X = (u) => -u;
  const H = 1.1, D = 0.1, bz = -0.12;
  const board = K.extrude(K.roundRect(2.5, 0.9, 0.3), D, { bevel: 0.025, bevelSeg: 2, curveSeg: 5 });
  g.add(tm(board, paint, '#1E2344', { pos: [X(-0.35), H / 2, bz + D / 2] }));
  g.add(tm(new THREE.CylinderGeometry(0.58, 0.58, D + 0.06, 28).rotateX(Math.PI / 2), paint, '#1E2344', { pos: [X(1.02), H / 2 + 0.02, bz + D / 2 - 0.02] }));
  g.add(tm(K.tube(K.roundRectPath(2.46, 0.86, 0.28, 0, 3).map(([x, , z]) => [x, z, 0]), 0.018, { seg: 48, radial: 4, closed: true }), paint, '#F6E7C8', { pos: [X(-0.35), H / 2, bz - 0.005] }));
  g.add(tm(K.tube(ring2(0.56, 24).map(([a, b]) => [a, b, 0]), 0.02, { seg: 24, radial: 4, closed: true }), paint, '#F6E7C8', { pos: [X(1.02), H / 2 + 0.02, bz - 0.055] }));
  for (const u of [-1.3, -0.1, 1.02]) g.add(tm(cbox(0.06, 0.5, 0.04, 0.01), galv, null, { pos: [X(u), H / 2, -0.02] }));
  g.add(tm(cbox(0.3, 0.22, 0.14, 0.03), paint, '#8E959E', { pos: [X(-1.2), -0.1, -0.08] }));
  g.add(tm(K.tube([[X(-1.2), 0.0, -0.08], [X(-1.2), 0.15, -0.1], [X(-1.1), 0.24, -0.12]], 0.015, { seg: 8, radial: 4 }), paint, '#3A3444'));
  const pink = [], blue = [], studs = [];
  const tz = bz - 0.07;
  const tubeOf = (pts, r) => K.tube(pts.map(([u, v]) => [X(u), v, tz]), r, { seg: Math.max(10, Math.round(pts.length * 1.6)), radial: 5 });
  const letters = ['W', 'Z', 'T', 'V'];
  const lw = [0.5, 0.4, 0.42, 0.44], gap = 0.08;
  let u = -1.53;
  const haloP = [], haloB = [];
  letters.forEach((ch, i) => {
    for (const st of NEON_GLYPH[ch]) {
      const pts = neonStroke(st, u, 0.28, lw[i], 0.56);
      pink.push(tubeOf(pts, 0.024));
      haloP.push(pts);
      studs.push(pts[0], pts[pts.length - 1]);
    }
    u += lw[i] + gap;
  });
  [['1', 0.34], ['3', 0.4]].forEach(([ch, w], i) => {
    for (const st of NEON_GLYPH[ch]) {
      const pts = neonStroke(st, i ? 0.98 : 0.74, 0.33, i ? 0.25 : 0.19, 0.42, ch === '3' ? 0.25 : 0.35);
      blue.push(tubeOf(pts, 0.022));
      haloB.push(pts);
      studs.push(pts[0]);
    }
  });
  blue.push(K.tube(ring2(0.47, 26).map(([a, b]) => [X(1.02) + a, H / 2 + 0.02 + b, tz]), 0.022, { seg: 30, radial: 5, closed: true }));
  const glowP = lit ? K.glow(game, PAL.neonPink, 2.6) : K.mat(game, 'plastic', '#E8B8C8', { transparent: true, opacity: 0.7 });
  const glowB = lit ? K.glow(game, '#3F76FF', 2.6) : K.mat(game, 'plastic', '#B8C8E8', { transparent: true, opacity: 0.7 });
  const neonPink = lightMesh(mergeList(pink), glowP, { name: 'neonPink' });
  const neonBlue = lightMesh(mergeList(blue), glowB, { name: 'neonBlue' });
  g.add(neonPink, neonBlue);
  const st = [];
  for (const [su, sv] of studs) st.push(xf(new THREE.CylinderGeometry(0.018, 0.022, 0.07, 6).rotateX(Math.PI / 2), { pos: [X(su), sv, bz - 0.035] }));
  g.add(K.m(mergeList(st), K.mat(game, 'ceramic', '#E8E2D4')));
  // halo cards: card x runs with u (a plane facing -z maps texture u = 0 to world +x, the viewer's left)
  const toCard = (pts, cu, cv, hw, hh) => pts.map(([pu, pv]) => [(pu - cu) / hw, (pv - cv) / hh]);
  const hp = haloTex('wztv_pink3', haloP.map((p) => toCard(p, -0.55, 0.56, 1.3, 0.55)), { w: 512, h: 256, blur: 14, width: 26 });
  const hb = haloTex('wztv_blue3', haloB.map((p) => toCard(p, 1.02, 0.57, 0.62, 0.62)), { w: 256, h: 256, blur: 12, width: 22, circles: [[0, 0, 0.76]] });
  const haloPink = lightMesh(new THREE.PlaneGeometry(2.6, 1.1).rotateY(Math.PI), K.glow(game, PAL.neonPink, 0.9, { map: hp, additive: true }), { pos: [X(-0.55), 0.56, bz - 0.01], name: 'haloPink' });
  const haloBlue = lightMesh(new THREE.PlaneGeometry(1.24, 1.24).rotateY(Math.PI), K.glow(game, '#3F76FF', 0.9, { map: hb, additive: true }), { pos: [X(1.02), 0.57, bz - 0.062], name: 'haloBlue' });
  haloPink.visible = haloBlue.visible = lit;
  g.add(haloPink, haloBlue);
  g.userData.parts = { neonPink, neonBlue, haloPink, haloBlue };
  g.userData.lightAnchors = lit ? [
    { pos: [X(-0.55), 0.5, -0.9], color: PAL.neonPink, intensity: 1.6, distance: 5, flicker: 0.08 },
    { pos: [X(1.0), 0.5, -0.9], color: '#3F76FF', intensity: 1.2, distance: 4, flicker: 0.05 },
  ] : [];
  g.userData.colliders = [];
  K.finish(game, g, { ao: { res: 48, dist: 0.15, height: 0 } });
  return g;
}, { category: CAT, tags: ['yard', 'neon', 'sign', 'wall'], size: [3.3, 1.2, 0.25], desc: 'WALL: pink "WZTV" + blue "13" neon on a navy backboard (origin on the wall at bottom center, faces -z); parts.neonPink/neonBlue/haloPink/haloBlue, setNeon(); opts.lit' });

// =================================================================================================== CITY BACKDROP (sky_*)
// Night skyline kit for the views beyond the fence / out of windows (30..150 m away): no colliders, low tris, rich
// canvas facades (4 styles) + an additive lit-window overlay, rooftop water tanks, blinking red aircraft lights
// (parts.redLights), billboards with sponsor art, a big cartoon moon. Materials ignore fog by default (opts.fog = true
// to let the yard fog eat them). All face -z (toward the station). Category 'outdoor_city'.
const CITY = 'outdoor_city';
// style: wall color, window color, tile = cols x rows windows over (cols*bay) x (rows*floor) meters
const FACADE = {
  brick: { wall: '#6E4448', band: '#8A5A54', glass: '#1E1E36', frame: '#C8B49C', bay: 2.6, floor: 3.2, cols: 4, rows: 4, lit: 0.38, kind: 'punch' },
  office: { wall: '#5E6482', band: '#7A809C', glass: '#1A2240', frame: '#A8B0C4', bay: 3.0, floor: 3.6, cols: 4, rows: 4, lit: 0.3, kind: 'ribbon' },
  deco: { wall: '#8A7462', band: '#A89078', glass: '#221E34', frame: '#E0CCA8', bay: 2.4, floor: 3.4, cols: 4, rows: 4, lit: 0.34, kind: 'pier' },
  glass: { wall: '#2C3A5E', band: '#44557E', glass: '#16203E', frame: '#6A7CA8', bay: 1.6, floor: 3.6, cols: 6, rows: 4, lit: 0.24, kind: 'curtain' },
};
function facadeTex(style, glow) {
  const F = FACADE[style];
  return K.tex.canvas(`out_facade|${style}|${glow ? 1 : 0}`, 512, 512, (ctx, w, h) => {
    const rand = mulberry32(style.length * 977 + 13);   // same layout for base + glow
    const cw = w / F.cols, ch = h / F.rows;
    if (glow) { ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h); } else {
      ctx.fillStyle = F.wall; ctx.fillRect(0, 0, w, h);
      for (let i = 0; i < 900; i++) { ctx.globalAlpha = 0.06 + rand() * 0.06; ctx.fillStyle = rand() < 0.5 ? '#000' : '#fff'; ctx.fillRect(rand() * w, rand() * h, 2, 2); }
      ctx.globalAlpha = 1;
      if (style === 'brick') { ctx.strokeStyle = 'rgba(0,0,0,0.12)'; ctx.lineWidth = 1; for (let y = 0; y < h; y += 8) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke(); } }
    }
    for (let r = 0; r < F.rows; r++) {
      // floor band
      if (!glow && F.kind !== 'curtain') { ctx.fillStyle = F.band; ctx.fillRect(0, r * ch + ch - 10, w, 10); }
      for (let c = 0; c < F.cols; c++) {
        const lit = rand() < F.lit, tv = rand() < 0.22, half = rand() < 0.3;
        let x, y, ww, hh;
        if (F.kind === 'ribbon') { x = c * cw + 2; ww = cw - 4; y = r * ch + ch * 0.28; hh = ch * 0.5; }
        else if (F.kind === 'curtain') { x = c * cw + 3; ww = cw - 6; y = r * ch + 4; hh = ch - 8; }
        else if (F.kind === 'pier') { x = c * cw + cw * 0.22; ww = cw * 0.56; y = r * ch + ch * 0.18; hh = ch * 0.62; }
        else { x = c * cw + cw * 0.18; ww = cw * 0.64; y = r * ch + ch * 0.2; hh = ch * 0.56; }
        const warm = tv ? '#8FD8FF' : ['#FFD58A', '#FFC870', '#FFE3A8'][Math.floor(rand() * 3)];
        if (glow) {
          if (!lit) continue;
          ctx.fillStyle = warm; ctx.fillRect(x, y, ww, hh);
          if (half) { ctx.fillStyle = '#000'; ctx.fillRect(x, y, ww, hh * 0.45); }
          ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.fillRect(x + ww * 0.48, y, ww * 0.04, hh);
        } else {
          ctx.fillStyle = F.frame; ctx.fillRect(x - 3, y - 3, ww + 6, hh + 6);
          const gr = ctx.createLinearGradient(x, y, x + ww, y + hh);
          gr.addColorStop(0, hexMix(F.glass, '#6A78B8', 0.35)); gr.addColorStop(1, F.glass);
          ctx.fillStyle = lit ? hexMix(warm, F.glass, 0.35) : gr; ctx.fillRect(x, y, ww, hh);
          if (lit && half) { ctx.fillStyle = hexMix('#C87A5A', F.glass, 0.3); ctx.fillRect(x, y, ww, hh * 0.45); }
          ctx.fillStyle = F.frame; ctx.fillRect(x + ww * 0.48, y, ww * 0.04, hh);
          if (F.kind === 'pier') { ctx.fillStyle = hexMix(F.wall, '#000', 0.15); ctx.fillRect(c * cw, r * ch, cw * 0.1, ch); }
        }
      }
    }
  });
}
// UV'd box for a facade: u along the face in meters / tile width, v = y / tile height; top/bottom faces tiny
function facadeBox(w, h, d, style, du = 0, dv = 0) {
  const F = FACADE[style];
  const tw = F.bay * F.cols, th = F.floor * F.rows;
  const g = new THREE.BoxGeometry(w, h, d);
  g.translate(0, h / 2, 0);
  const p = g.attributes.position, n = g.attributes.normal, uv = g.attributes.uv;
  for (let i = 0; i < p.count; i++) {
    const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i));
    let u, v;
    if (ay > 0.5) { u = 0.02; v = 0.02; }
    else if (ax > 0.5) { u = -p.getZ(i) * Math.sign(n.getX(i)); v = p.getY(i); }
    else { u = p.getX(i) * -Math.sign(n.getZ(i)); v = p.getY(i); }
    uv.setXY(i, (u + du) / tw, (v + dv) / th);
  }
  return g;
}
function cityMats(game, opts = {}) {
  const fog = !!opts.fog;
  const M = { fog, facade: {}, glow: {} };
  for (const s of Object.keys(FACADE)) {
    M.facade[s] = K.mat(game, 'paint', '#ffffff', { map: facadeTex(s, false), rough: 0.8, rim: 0.15, rimColor: '#9FB6FF', fog });
    M.glow[s] = K.glow(game, '#ffffff', 1.35, { map: facadeTex(s, true), additive: true, fog });
  }
  M.roof = K.mat(game, 'paint', '#ffffff', { rough: 0.8, rim: 0.2, rimColor: '#9FB6FF', fog });
  M.red = K.glow(game, PAL.onAirRed, 2.4, { fog });
  M.wood = K.mat(game, 'teak', '#ffffff', { map: K.tex.wood('#8A6040', { planks: 8, dark: 0.35 }), fog, rim: 0.2, rimColor: '#9FB6FF' });
  return M;
}
// adds one building (geometry lists by style) at x, z with its roof details; returns its height
function addBuilding(L, spec, rnd) {
  const { x = 0, z = 0, w, h, d, style } = spec;
  const F = FACADE[style];
  const du = Math.floor(rnd() * F.cols) * F.bay, dv = -F.floor * 0.15;
  const tiers = style === 'deco' ? [[1, 1], [0.72, 0.18], [0.46, 0.1]] : [[1, 1]];
  let y = 0, top = 0;
  tiers.forEach(([s, hf], i) => {
    const tw = w * s, td = d * s, th = i === 0 && tiers.length > 1 ? h * 0.72 : h * hf;
    L.face[style].push(xf(facadeBox(tw, th, td, style, du, dv - y), { pos: [x, y, z] }));
    L.glow[style].push(xf(facadeBox(tw + 0.04, th, td + 0.04, style, du, dv - y), { pos: [x, y, z] }));
    // parapet cap
    L.roof.push(K.tint(xf(new THREE.BoxGeometry(tw + 0.3, 0.45, td + 0.3), { pos: [x, y + th + 0.2, z] }), F.band));
    y += th; top = y;
  });
  // ground-floor storefront band (dark, with a lit shop window)
  L.roof.push(K.tint(xf(new THREE.BoxGeometry(w + 0.1, 0.6, d + 0.1), { pos: [x, 3.6, z] }), hexMix(F.band, '#1B1E4A', 0.3)));
  // roof clutter
  if (style === 'deco') {
    L.roof.push(K.tint(xf(new THREE.ConeGeometry(w * 0.14, h * 0.18, 8), { pos: [x, top + h * 0.09, z] }), '#C8B08A'));
    L.red.push(xf(new THREE.SphereGeometry(0.45, 8, 6), { pos: [x, top + h * 0.18 + 0.3, z] }));
  } else {
    const n = 1 + Math.floor(rnd() * 3);
    for (let i = 0; i < n; i++) L.roof.push(K.tint(xf(new THREE.BoxGeometry(1.6 + rnd() * 2, 1 + rnd() * 1.2, 1.4 + rnd() * 1.5), { pos: [x + (rnd() - 0.5) * w * 0.6, top + 0.9, z + (rnd() - 0.5) * d * 0.5] }), '#7A7890'));
    if (rnd() < 0.55) {
      const ax = x + (rnd() - 0.5) * w * 0.5, az = z + (rnd() - 0.2) * d * 0.4, ah = 4 + rnd() * 6;
      L.roof.push(K.tint(pipeGeo(0.12, [ax, top, az], [ax, top + ah, az], 5, true), '#9CA3AD'));
      L.red.push(xf(new THREE.SphereGeometry(0.35, 8, 6), { pos: [ax, top + ah + 0.2, az] }));
    }
  }
  return top;
}
function waterTankGeo(L, x, y, z, s = 1) {
  // wooden tank on steel legs + conical roof
  const R = 2.2 * s, TH = 3.4 * s, LH = 3.2 * s;
  const tank = latheY([[0, 0], [R, 0], [R, TH], [0, TH]], 16, TH);
  L.wood.push(xf(tank, { pos: [x, y + LH, z] }));
  for (const t of [0.2, 0.5, 0.8]) L.roof.push(K.tint(xf(new THREE.TorusGeometry(R + 0.04 * s, 0.06 * s, 4, 16).rotateX(Math.PI / 2), { pos: [x, y + LH + TH * t, z] }), '#4A4A5A'));
  L.roof.push(K.tint(xf(new THREE.ConeGeometry(R * 1.12, 1.6 * s, 16, 1), { pos: [x, y + LH + TH + 0.8 * s, z] }), '#5A4A56'));
  L.roof.push(K.tint(xf(new THREE.SphereGeometry(0.2 * s, 6, 4), { pos: [x, y + LH + TH + 1.65 * s, z] }), '#C8963C'));
  for (let i = 0; i < 4; i++) {
    const a = i * Math.PI / 2 + Math.PI / 4;
    const lx = x + Math.cos(a) * R * 0.75, lz = z + Math.sin(a) * R * 0.75;
    L.roof.push(K.tint(pipeGeo(0.12 * s, [lx, y, lz], [lx, y + LH, lz], 5, false), '#3A3A4A'));
  }
  L.roof.push(K.tint(xf(new THREE.BoxGeometry(R * 1.8, 0.2 * s, R * 1.8), { pos: [x, y + LH, z] }), '#3A3A4A'));
}
function buildingLists() {
  const L = { face: {}, glow: {}, roof: [], red: [], wood: [] };
  for (const s of Object.keys(FACADE)) { L.face[s] = []; L.glow[s] = []; }
  return L;
}
function addLists(g, L, M) {
  for (const s of Object.keys(FACADE)) {
    if (L.face[s].length) { const m = K.m(mergeList(L.face[s]), M.facade[s]); m.userData.noAO = true; g.add(m); }
    if (L.glow[s].length) { const m = K.m(mergeList(L.glow[s]), M.glow[s]); m.userData.noAO = true; m.userData.noOcclude = true; m.name = 'windows'; g.add(m); }
  }
  if (L.roof.length) { const m = K.m(mergeList(L.roof), M.roof); m.userData.noAO = true; g.add(m); }
  if (L.wood.length) { const m = K.m(mergeList(L.wood), M.wood); m.userData.noAO = true; g.add(m); }
  let red = null;
  if (L.red.length) { red = lightMesh(mergeList(L.red), M.red, { name: 'redLights' }); g.add(red); }
  return red;
}
registerProp('sky_building', (game, opts = {}) => {
  const g = K.prop('sky_building');
  const M = cityMats(game, opts);
  const style = FACADE[opts.style] ? opts.style : 'brick';
  const rnd = mulberry32((opts.seed ?? 1) * 131 + 7);
  const L = buildingLists();
  const w = opts.w ?? 14, h = opts.h ?? 32, d = opts.d ?? 12;
  const top = addBuilding(L, { w, h, d, style }, rnd);
  if (opts.tank) waterTankGeo(L, w * 0.2, top, d * 0.1, 0.8);
  const red = addLists(g, L, M);
  g.userData.parts = { redLights: red };
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}, { category: CITY, tags: ['backdrop', 'skyline', 'building'], size: [14, 36, 12], desc: 'backdrop building with a canvas facade + additive lit windows; opts {style brick|office|deco|glass, w, h, d, seed, tank, fog}' });

registerProp('sky_water_tower', (game, opts = {}) => {
  const g = K.prop('sky_water_tower');
  const M = cityMats(game, opts);
  const L = buildingLists();
  waterTankGeo(L, 0, 0, 0, opts.scale ?? 1);
  // ladder up one leg
  const s = opts.scale ?? 1;
  L.roof.push(K.tint(pipeGeo(0.05 * s, [0.3 * s, 0, -1.9 * s], [0.3 * s, 6.6 * s, -2.3 * s], 4, false), '#3A3A4A'));
  L.roof.push(K.tint(pipeGeo(0.05 * s, [-0.3 * s, 0, -1.9 * s], [-0.3 * s, 6.6 * s, -2.3 * s], 4, false), '#3A3A4A'));
  addLists(g, L, M);
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}, { category: CITY, tags: ['backdrop', 'skyline', 'rooftop'], size: [5, 8.5, 5], desc: 'rooftop wooden water tank on steel legs with a cone roof (opts.scale, opts.fog)' });

function billboardTex(ad) {
  return K.tex.canvas(`out_billboard|${ad}`, 1024, 448, (ctx, w, h) => {
    const ADS = {
      wztv: { bg: '#2F5BD3', fg: '#FFD23A', line1: 'ACTION 13 NEWS', line2: 'TONIGHT AT 11', card: null },
      replay_ade: { bg: '#F4C430', fg: '#2F5BD3', line1: 'THIRSTY? REWIND!', line2: 'REPLAY-ADE', card: 'sponsor_logo_replay_ade' },
      jump_cut: { bg: '#E3662B', fg: '#F6E7C8', line1: 'WAKE UP FASTER', line2: 'JUMP CUT COFFEE', card: 'sponsor_logo_jump_cut' },
      roller_boogie: { bg: '#FF5FA2', fg: '#F4F1E8', line1: 'SHINE ON, SKATER', line2: 'ROLLER BOOGIE WAX', card: 'sponsor_logo_roller_boogie' },
      double_vision: { bg: '#F4F1E8', fg: '#E23B3B', line1: 'SMILE TWICE AS BRIGHT', line2: 'DOUBLE VISION', card: 'sponsor_logo_double_vision' },
      wobble_up: { bg: '#39A85F', fg: '#F6E7C8', line1: 'THE DESSERT THAT DANCES', line2: 'WOBBLE-UP', card: 'sponsor_logo_wobble_up' },
    };
    const A = ADS[ad] || ADS.wztv;
    ctx.fillStyle = A.bg; ctx.fillRect(0, 0, w, h);
    // 70s sunburst rays
    ctx.save(); ctx.translate(220, h / 2); ctx.globalAlpha = 0.14; ctx.fillStyle = '#fff';
    for (let i = 0; i < 16; i++) { ctx.rotate(TAU / 16); ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(900, -70); ctx.lineTo(900, 70); ctx.fill(); }
    ctx.restore();
    if (A.card) {
      ctx.save(); ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.fillRect(34, 50, 380, 285 + 20); ctx.restore();
      ctx.save(); ctx.translate(24, 40); drawTo(ctx, A.card, 380, 285); ctx.restore();
    } else {
      ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(220, h / 2, 150, 0, TAU); ctx.fill();
      ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(220, h / 2, 132, 0, TAU); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; font(ctx, 170, 'Titan One'); ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('13', 220, h / 2 + 14);
    }
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.lineJoin = 'round'; ctx.strokeStyle = 'rgba(40,20,40,0.55)';
    fitText(ctx, A.line1, 520, 58, 'Titan One'); ctx.lineWidth = 10; ctx.strokeText(A.line1, 700, 150); ctx.fillStyle = A.fg; ctx.fillText(A.line1, 700, 150);
    fitText(ctx, A.line2, 540, 96, 'Shrikhand'); ctx.lineWidth = 12; ctx.strokeText(A.line2, 700, 290); ctx.fillStyle = '#F4F1E8'; ctx.fillText(A.line2, 700, 290);
    ctx.strokeStyle = 'rgba(0,0,0,0.2)'; ctx.lineWidth = 2;
    for (let x = 128; x < w; x += 128) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke(); }
  }, { repeat: false, fonts: true });
}
registerProp('sky_billboard', (game, opts = {}) => {
  const g = K.prop('sky_billboard');
  const fog = !!opts.fog;
  const ad = opts.ad ?? 'wztv';
  const face = K.mat(game, 'paint', '#ffffff', { map: billboardTex(ad), rough: 0.7, fog, emissive: '#ffffff', emissiveIntensity: 0.12 });
  face.emissiveMap = face.map;
  const steel = K.mat(game, 'metal', '#8A8FA0', { rough: 0.5, fog });
  const lit = opts.lit !== false;
  const W = 9, H = 3.9, Y = 6;
  const S = [];
  // face panel + frame, catwalk, legs + bracing, 3 gooseneck lamps
  g.add(K.m(pxUV(decal(W, H), 0, 0, 1024, 448, 1024, 448), face, { pos: [0, Y + H / 2, -0.06] }));
  S.push(xf(cbox(W + 0.3, H + 0.3, 0.1, 0.03), { pos: [0, Y + H / 2, 0] }));
  S.push(xf(cbox(W + 0.4, 0.08, 0.9, 0.02), { pos: [0, Y - 0.15, -0.45] }));
  S.push(pipeGeo(0.025, [-W / 2 - 0.2, Y + 0.75, -0.88], [W / 2 + 0.2, Y + 0.75, -0.88], 5, false));
  for (let x = -W / 2 - 0.2; x <= W / 2 + 0.25; x += (W + 0.4) / 6) S.push(pipeGeo(0.02, [x, Y - 0.1, -0.88], [x, Y + 0.75, -0.88], 4, false));
  for (const x of [-W * 0.3, W * 0.3]) {
    S.push(pipeGeo(0.22, [x, 0, 0.3], [x, Y + 0.2, 0.3], 8, false));
    S.push(bar8(0.12, 0.08, [x, Y - 1.8, 0.3], [x, Y - 0.2, -0.4], [1, 0, 0], 0.015));
  }
  S.push(bar8(0.1, 0.08, [-W * 0.3, 1.5, 0.3], [W * 0.3, Y - 0.6, 0.3], [0, 0, 1], 0.015));
  S.push(bar8(0.1, 0.08, [W * 0.3, 1.5, 0.3], [-W * 0.3, Y - 0.6, 0.3], [0, 0, 1], 0.015));
  const lamps = [];
  for (const x of [-W * 0.33, 0, W * 0.33]) {
    S.push(K.tube([[x, Y - 0.1, -0.2], [x, Y - 0.2, -0.9], [x, Y - 0.05, -1.35]], 0.03, { seg: 8, radial: 4 }));
    S.push(xf(K.lathe([[0, 0], [0.22, 0.02], [0.3, 0.14], [0.05, 0.2], [0, 0.2]], { seg: 10 }).clone().rotateX(Math.PI * 0.8), { pos: [x, Y + 0.02, -1.38] }));
    lamps.push(xf(new THREE.CircleGeometry(0.2, 10).rotateX(Math.PI * 0.3), { pos: [x, Y + 0.06, -1.3] }));
  }
  g.add(K.m(mergeList(S), steel));
  const lampM = lightMesh(mergeList(lamps), lit ? K.glow(game, '#FFF0C8', 2.2, { fog }) : K.mat(game, 'ceramic', '#E8E0C8', { fog }), { name: 'lamps' });
  g.add(lampM);
  g.userData.parts = { lamps: lampM };
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { res: 40, dist: 0.3, height: 0 } });
}, { category: CITY, tags: ['backdrop', 'billboard'], size: [9.4, 10, 1.8], desc: '9 m roadside billboard on a steel frame with catwalk + 3 gooseneck lamps; opts.ad wztv|replay_ade|jump_cut|roller_boogie|double_vision|wobble_up (sponsor_logo art), opts.lit, opts.fog' });

function moonTex() {
  return K.tex.canvas('out_moon', 512, 256, (ctx, w, h) => {
    const rand = mulberry32(4242);
    ctx.fillStyle = '#FFF4D6'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 70; i++) {
      const x = rand() * w, y = h * 0.15 + rand() * h * 0.7, r = 4 + rand() * rand() * 38;
      ctx.fillStyle = `rgba(200,180,150,${0.25 + rand() * 0.3})`; ctx.beginPath(); ctx.ellipse(x, y, r, r * 0.8, 0, 0, TAU); ctx.fill();
      ctx.fillStyle = 'rgba(255,255,240,0.5)'; ctx.beginPath(); ctx.ellipse(x - r * 0.15, y - r * 0.2, r * 0.7, r * 0.5, 0, 0, TAU); ctx.fill();
    }
    for (let i = 0; i < 6; i++) { ctx.fillStyle = 'rgba(190,170,150,0.25)'; ctx.beginPath(); ctx.ellipse(rand() * w, h * 0.3 + rand() * h * 0.4, 30 + rand() * 60, 20 + rand() * 30, rand(), 0, TAU); ctx.fill(); }
  }, { repeat: true });
}
function haloDiscTex() {
  return K.tex.canvas('out_moon_halo', 256, 256, (ctx, w, h) => {
    const gr = ctx.createRadialGradient(w / 2, h / 2, w * 0.18, w / 2, h / 2, w / 2);
    gr.addColorStop(0, 'rgba(255,255,255,0.9)'); gr.addColorStop(0.3, 'rgba(255,255,255,0.35)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h);
  }, { repeat: false });
}
registerProp('sky_moon', (game, opts = {}) => {
  const g = K.prop('sky_moon');
  const r = opts.r ?? 8;
  const moon = K.m(new THREE.SphereGeometry(r, 28, 18), K.glow(game, '#FFF4D6', 1.05, { map: moonTex(), fog: false }), { name: 'moon', pos: [0, r, 0] });
  moon.rotation.set(0.3, 2.2, 0.1);
  moon.userData.noAO = true; moon.userData.noShadow = true;
  g.add(moon);
  const halo = lightMesh(new THREE.PlaneGeometry(r * 4.2, r * 4.2).rotateY(Math.PI), K.glow(game, PAL.moonlight, 0.55, { map: haloDiscTex(), additive: true, fog: false }), { pos: [0, r, r * 0.6], name: 'halo' });
  g.add(halo);
  g.userData.parts = { moon, halo };
  g.userData.colliders = [];
  g.userData.size = [r * 2, r * 2, r * 2];
  return K.finish(game, g, { ao: false, merge: false });
}, { category: CITY, tags: ['backdrop', 'sky'], size: [16, 16, 16], desc: 'big cartoon moon: cratered glow sphere + soft blue halo card behind it; origin = bottom of the sphere (center at y = r; opts.r, default 8 m; place ~120 m away, high)' });

registerProp('sky_skyline', (game, opts = {}) => {
  const g = K.prop('sky_skyline');
  const M = cityMats(game, opts);
  const rnd = mulberry32((opts.seed ?? 1) * 7717 + 3);
  const L = buildingLists();
  const span = opts.w ?? 90;
  const styles = ['brick', 'office', 'deco', 'glass', 'brick', 'office'];
  let x = -span / 2;
  const tops = [];
  while (x < span / 2) {
    const w = 8 + rnd() * 9, d = 8 + rnd() * 7, style = styles[Math.floor(rnd() * styles.length)];
    const tall = rnd() < 0.25;
    const h = tall ? 40 + rnd() * 26 : 14 + rnd() * 20;
    const z = (rnd() - 0.5) * 10 + (tall ? 8 : 0);
    const top = addBuilding(L, { x: x + w / 2, z, w, h, d, style }, rnd);
    tops.push([x + w / 2, top, z, w, style]);
    x += w + 0.5 + rnd() * 3;
  }
  // two water tanks on low roofs, one radio mast
  const low = tops.filter((t) => t[1] < 30 && t[4] !== 'deco').slice(0, 2);
  for (const t of low) waterTankGeo(L, t[0] + t[3] * 0.15, t[1], t[2], 0.9);
  const mastAt = tops[Math.floor(tops.length * 0.7)];
  if (mastAt) {
    const [mx, my, mz] = mastAt;
    for (let k = 0; k < 3; k++) L.roof.push(K.tint(pipeGeo(0.35 - k * 0.1, [mx, my + k * 6, mz], [mx, my + (k + 1) * 6, mz], 6, false), k % 2 ? '#F2EEE4' : '#D8402F'));
    for (let k = 1; k <= 3; k++) L.red.push(xf(new THREE.SphereGeometry(0.5, 8, 6), { pos: [mx, my + k * 6 + 0.2, mz] }));
  }
  const red = addLists(g, L, M);
  // a billboard on the first low roof
  if (opts.billboard !== false && low[0]) {
    const bb = K.buildProp('sky_billboard', game, { ad: opts.ad ?? 'jump_cut', fog: !!opts.fog });
    bb.position.set(low[0][0] - low[0][3] * 0.2, low[0][1], low[0][2] - 3);
    bb.scale.setScalar(0.9);
    g.add(bb);
  }
  g.userData.parts = { redLights: red };
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false, merge: false });
}, { category: CITY, tags: ['backdrop', 'skyline'], hero: true, size: [90, 70, 20], desc: 'composed night skyline strip (opts.w m wide, seed): mixed facades with lit windows, setback deco tower, water tanks, red-light mast (parts.redLights), a sponsor billboard (opts.ad, billboard:false); place 60..140 m out, facing the station' });

// =================================================================================================== STREET (st_*)
// What the lobby / newsroom windows look out on: sidewalk slabs + curb, an ornamental street lamp, a parked 70s
// sedan, fire hydrant, mailbox and a motel neon sign across the street. Category 'outdoor_city'.
function sidewalkTex() {
  return K.tex.canvas('out_sidewalk', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#B4ADA4'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 1500; i++) { ctx.globalAlpha = 0.1 + rand() * 0.15; ctx.fillStyle = rand() < 0.5 ? '#8A847C' : '#D8D2C8'; ctx.fillRect(rand() * w, rand() * h, 1.5, 1.5); }
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#6E6860'; ctx.fillRect(0, 0, w, 4); ctx.fillRect(0, 0, 4, h);
    ctx.fillStyle = 'rgba(255,255,255,0.25)'; ctx.fillRect(0, 4, w, 2); ctx.fillRect(4, 0, 2, h);
    ctx.strokeStyle = 'rgba(60,50,50,0.35)'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(40, 90); ctx.lineTo(70, 120); ctx.lineTo(66, 160); ctx.stroke();
    grime(ctx, w, h, rand, 10, '#4A4050', 0.06);
    ctx.fillStyle = 'rgba(60,40,60,0.5)'; ctx.beginPath(); ctx.ellipse(180, 190, 8, 6, 0, 0, TAU); ctx.fill();
  });
}
registerProp('st_sidewalk', (game, opts = {}) => {
  const g = K.prop('st_sidewalk');
  const L = opts.len ?? 6, Wd = opts.width ?? 2.5;
  const slab = K.mat(game, 'paint', '#ffffff', { map: sidewalkTex(), rough: 0.9 });
  const conc = K.mat(game, 'paint', '#ffffff', { map: concreteTex('#A8A298'), rough: 0.9 });
  // floor (y = 0) = street level: slab top at 0.15, rounded granite-look curb on the -z (street) side, gutter strip
  const sg = new THREE.BoxGeometry(L, 0.15, Wd);
  const uv = sg.attributes.uv, p = sg.attributes.position;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, p.getX(i) / 1.5, p.getZ(i) / 1.5);
  g.add(K.m(sg, slab, { pos: [0, 0.075, 0] }));
  g.add(K.m(K.uvBox(K.box(L, 0.17, 0.24, 0.05), 1.2), conc, { pos: [0, 0.085, -Wd / 2 - 0.12] }));
  g.add(tm(cbox(L, 0.02, 0.45, 0.006), conc, '#8A857C', { pos: [0, 0.01, -Wd / 2 - 0.46] }));
  g.userData.colliders = [{ min: [-L / 2, 0, -Wd / 2 - 0.24], max: [L / 2, 0.16, Wd / 2] }];
  return K.finish(game, g, { ao: { res: 40, height: 0.05 } });
}, { category: CITY, tags: ['street', 'ground'], size: [6, 0.17, 3.2], desc: 'sidewalk slab run (1.5 m scored squares, top at 0.15 m = curb height; floor = street level) with a rounded curb + gutter on the -z (street) side; opts.len, opts.width' });

registerProp('st_street_lamp', (game, opts = {}) => {
  const g = K.prop('st_street_lamp');
  const lit = opts.lit !== false;
  const iron = K.mat(game, 'paint', '#2E4A3E', { rough: 0.45, rim: 0.3 });
  // fluted cast base, slim post, collar rings, acorn globe + finial
  g.add(K.m(K.lathe([[0, 0], [0.26, 0], [0.26, 0.06], [0.2, 0.1], [0.19, 0.5], [0.13, 0.62], [0.1, 0.9], [0, 0.9]], { seg: 16, round: 0.02, steps: 1 }), iron));
  g.add(K.m(K.cyl(0.07, 0.085, 3.2, { seg: 12, bevel: 0.01 }), iron, { pos: [0, 0.88, 0] }));
  for (const y of [1.4, 3.6, 4.05]) g.add(K.m(K.cyl(0.11, 0.11, 0.06, { seg: 12, bevel: 0.02 }), iron, { pos: [0, y, 0] }));
  g.add(K.m(K.lathe([[0.08, 0], [0.2, 0.05], [0.22, 0.12], [0, 0.14]], { seg: 14 }), iron, { pos: [0, 4.08, 0] }));
  const globe = lightMesh(K.lathe([[0, 0], [0.16, 0.02], [0.24, 0.16], [0.25, 0.32], [0.2, 0.5], [0.1, 0.6], [0, 0.62]], { seg: 16, round: 0.03, steps: 1 }), lit ? K.glow(game, '#FFE0A0', 2.2) : K.mat(game, 'ceramic', '#F2EAD8'), { pos: [0, 4.2, 0], name: 'globe' });
  g.add(globe);
  g.add(K.m(K.lathe([[0.12, 0], [0.14, 0.04], [0.06, 0.12], [0.02, 0.3], [0, 0.32]], { seg: 12, round: 0.01, steps: 1 }), iron, { pos: [0, 4.78, 0] }));
  g.userData.parts = { globe };
  g.userData.lightAnchors = lit ? [{ pos: [0, 4.5, 0], color: '#FFD9A0', intensity: 2.2, distance: 9, flicker: 0.02 }] : [];
  g.userData.colliders = [{ min: [-0.26, 0, -0.26], max: [0.26, 2.5, 0.26] }];
  return K.finish(game, g, { ao: { res: 40, dist: 0.2 } });
}, { category: CITY, tags: ['street', 'light', 'lamp'], size: [0.52, 5.1, 0.52], desc: 'ornamental downtown street lamp: green cast-iron post with an acorn glow globe (parts.globe); anchor warm 2.2/9 m (opts.lit)' });

registerProp('st_hydrant', (game, opts = {}) => {
  const g = K.prop('st_hydrant');
  const red = K.mat(game, 'lacquer', opts.color ?? '#D8402F', { rough: 0.38 });
  const yel = K.mat(game, 'lacquer', '#F2C230', { rough: 0.38 });
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  g.add(K.m(K.lathe([[0, 0], [0.19, 0], [0.19, 0.05], [0.15, 0.08], [0.14, 0.12], [0.13, 0.46], [0.16, 0.5], [0.16, 0.55], [0, 0.55]], { seg: 18, round: 0.015, steps: 1 }), red));
  g.add(K.m(K.lathe([[0, 0], [0.17, 0], [0.17, 0.04], [0.15, 0.1], [0.08, 0.2], [0.05, 0.22], [0, 0.23]], { seg: 18, round: 0.02, steps: 1 }), yel, { pos: [0, 0.55, 0] }));
  g.add(K.m(new THREE.CylinderGeometry(0.035, 0.04, 0.05, 5), yel, { pos: [0, 0.8, 0] }));
  // side nozzles (L/R) + front pumper nozzle with caps and chains
  const noz = (len, r) => K.cyl(r, r, len, { seg: 10, bevel: 0.01 }).clone();
  for (const s of [-1, 1]) {
    g.add(K.m(noz(0.1, 0.05).rotateZ(-s * Math.PI / 2), red, { pos: [s * 0.12, 0.34, 0] }));
    g.add(K.m(K.cyl(0.062, 0.062, 0.035, { seg: 6, bevel: 0.006 }).clone().rotateZ(-s * Math.PI / 2), yel, { pos: [s * 0.215, 0.34, 0] }));
    g.add(K.m(K.tube([[s * 0.23, 0.32, 0.03], [s * 0.2, 0.2, 0.08], [s * 0.14, 0.22, 0.12]], 0.006, { seg: 8, radial: 3 }), chrome));
  }
  g.add(K.m(noz(0.1, 0.07).rotateX(-Math.PI / 2), red, { pos: [0, 0.3, -0.12] }));
  g.add(K.m(K.cyl(0.085, 0.085, 0.04, { seg: 6, bevel: 0.008 }).clone().rotateX(-Math.PI / 2), yel, { pos: [0, 0.3, -0.22] }));
  // bolts ring
  const bolts = [];
  for (let i = 0; i < 8; i++) { const a = (i / 8) * TAU; bolts.push(xf(new THREE.CylinderGeometry(0.012, 0.012, 0.02, 6), { pos: [Math.cos(a) * 0.165, 0.06, Math.sin(a) * 0.165] })); }
  g.add(K.m(mergeList(bolts), chrome));
  g.userData.colliders = [{ min: [-0.24, 0, -0.26], max: [0.24, 0.8, 0.2] }];
  return K.finish(game, g, { ao: { res: 40, dist: 0.12 } });
}, { category: CITY, tags: ['street', 'clutter'], size: [0.5, 0.83, 0.46], desc: 'chunky red fire hydrant with a yellow bonnet, side + pumper nozzles, chains (opts.color)' });

function mailTex() {
  return atlasTex('mailbox', 256, 256, (ctx) => {
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillStyle = '#F4F1E8'; font(ctx, 36, 'Bungee'); ctx.fillText('U.S. MAIL', 128, 40);
    ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(128, 132, 56, 0, TAU); ctx.fill();
    ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(128, 132, 46, 0, TAU); ctx.fill();
    ctx.fillStyle = '#2F4A8A';
    ctx.beginPath(); ctx.moveTo(128, 96); ctx.lineTo(160, 120); ctx.lineTo(148, 124); ctx.lineTo(164, 150); ctx.lineTo(128, 136); ctx.lineTo(92, 150); ctx.lineTo(108, 124); ctx.lineTo(96, 120); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#F4F1E8'; font(ctx, 16, 'Titan One'); ctx.fillText('PICKUP 5 PM', 128, 214);
  });
}
registerProp('st_mailbox', (game, opts = {}) => {
  const g = K.prop('st_mailbox');
  const blue = K.mat(game, 'lacquer', '#2F4A8A', { rough: 0.4 });
  const dec = K.mat(game, 'paint', '#ffffff', { map: mailTex(), transparent: true, depthWrite: false, rough: 0.5 });
  const W = 0.5, D = 0.52, H = 0.95;
  // body: box + half-cylinder top, 4 legs, pull-down chute handle
  g.add(K.m(K.box(W, H - 0.25, D, 0.03), blue, { pos: [0, 0.32 + (H - 0.25) / 2, 0] }));
  g.add(K.m(new THREE.CylinderGeometry(W / 2, W / 2, D, 18, 1, false, 0, Math.PI).rotateX(Math.PI / 2).rotateZ(Math.PI / 2), blue, { pos: [0, 0.32 + H - 0.25, 0], rot: [0, 0, 0] }));
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) g.add(K.m(K.box(0.05, 0.34, 0.05, 0.012), blue, { pos: [sx * (W / 2 - 0.04), 0.17, sz * (D / 2 - 0.04)] }));
  g.add(K.m(K.box(W - 0.1, 0.14, 0.04, 0.02), blue, { pos: [0, 0.32 + H - 0.4, -D / 2 - 0.02] }));
  g.add(K.m(K.box(0.18, 0.03, 0.03, 0.01), K.mat(game, 'chrome', '#A8B0BA'), { pos: [0, 0.32 + H - 0.36, -D / 2 - 0.05] }));
  for (const [z, ry] of [[-D / 2 - 0.004, 0], [D / 2 + 0.004, Math.PI]]) {
    const dm = K.m(decal(0.44, 0.44).rotateY(ry), dec, { pos: [0, 0.56, z] });
    dm.userData.noAO = true;
    g.add(dm);
  }
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, 0.32 + H, D / 2] }];
  return K.finish(game, g, { ao: { res: 40, dist: 0.15 } });
}, { category: CITY, tags: ['street', 'clutter'], size: [0.5, 1.27, 0.56], desc: '70s blue curbside mailbox with a rounded top, legs, chute handle and "U.S. MAIL" decals' });

// parked 70s sedan: FRONT at -x, length along x (like the van); opts.color
registerProp('st_car_70s', (game, opts = {}) => {
  const g = K.prop('st_car_70s');
  const col = opts.color ?? '#8C9A3A';
  const paint = K.mat(game, 'lacquer', '#ffffff', { rough: 0.38, env: 0.06 });
  const chrome = K.mat(game, 'chrome', '#8E96A0', { env: 0.4 });
  const glass = K.mat(game, 'crt', '#27305A', { rough: 0.06, rim: 0.7, rimColor: '#9FB6FF', env: 0.5 });
  const rubber = K.mat(game, 'rubber', '#ffffff');
  const W = 1.9, hw = W / 2, wr = 0.34;
  // lower body (long boat), greenhouse (cabin) + vinyl roof
  const low = [[-2.45, 0.28], [2.45, 0.28], [2.5, 0.45], [2.48, 0.78], [2.3, 0.84], [-2.3, 0.86], [-2.48, 0.8], [-2.5, 0.45]];
  addTo(g, K.extrude(low, W, { bevel: 0.12, bevelSeg: 1, round: 0.08 }), paint, col);
  const cab = [[-1.0, 0.8], [1.25, 0.8], [0.95, 1.32], [-0.45, 1.34]];
  addTo(g, K.extrude(cab, W - 0.26, { bevel: 0.1, bevelSeg: 1, round: 0.1 }), paint, hexMix(col, '#F4F1E8', 0.75));
  addTo(g, xf(cbox(1.26, 0.05, W - 0.34, 0.02), { pos: [0.28, 1.34, 0] }), paint, '#3A2A24');
  // windows: side (2 per side), windshield, rear window
  for (const s of [-1, 1]) {
    addTo(g, xf(K.extrude([[-0.84, 0.88], [0.16, 0.88], [0.16, 1.24], [-0.4, 1.26]], 0.02, { bevel: 0.005, bevelSeg: 1, round: 0.05 }), { pos: [0, 0, s * (hw - 0.12)] }), glass, null);
    addTo(g, xf(K.extrude([[0.24, 0.88], [1.08, 0.88], [0.86, 1.24], [0.24, 1.24]], 0.02, { bevel: 0.005, bevelSeg: 1, round: 0.05 }), { pos: [0, 0, s * (hw - 0.12)] }), glass, null);
  }
  const wsh = (a, b, w) => {
    const len = Math.hypot(b[0] - a[0], b[1] - a[1]) - 0.1;
    const ang = Math.atan2(b[1] - a[1], b[0] - a[0]);
    const gg = K.extrude(K.roundRect(w, len, 0.08), 0.03, { bevel: 0.008, bevelSeg: 1 }).clone().rotateY(Math.PI / 2).rotateZ(ang - Math.PI / 2);
    gg.translate((a[0] + b[0]) / 2 - Math.sin(ang) * 0.012, (a[1] + b[1]) / 2 + Math.cos(ang) * 0.012, 0);
    return gg;
  };
  addTo(g, wsh([-1.0, 0.82], [-0.45, 1.32], 1.36), glass, null);
  addTo(g, wsh([0.95, 1.32], [1.25, 0.82], 1.36), glass, null);
  // chrome: bumpers, grille, quad headlights, belt molding, hubcaps; tail lights
  addTo(g, xf(K.box(0.16, 0.14, W + 0.06, 0.03), { pos: [-2.52, 0.4, 0] }), chrome, null);
  addTo(g, xf(K.box(0.16, 0.14, W + 0.06, 0.03), { pos: [2.52, 0.4, 0] }), chrome, null);
  addTo(g, xf(cbox(0.04, 0.22, 1.2, 0.012), { pos: [-2.5, 0.62, 0] }), chrome, null);
  for (let i = 0; i < 5; i++) addTo(g, xf(new THREE.BoxGeometry(0.02, 0.02, 1.1), { pos: [-2.525, 0.54 + i * 0.04, 0] }), paint, '#2A2430');
  const hl = [];
  for (const s of [-1, 1]) for (const k of [0, 1]) {
    const z = s * (0.66 + k * 0.17);
    addTo(g, xf(new THREE.CylinderGeometry(0.075, 0.075, 0.04, 12).rotateZ(Math.PI / 2), { pos: [-2.5, 0.64, z] }), chrome, null);
    hl.push(xf(new THREE.CircleGeometry(0.06, 12).rotateY(-Math.PI / 2), { pos: [-2.523, 0.64, z] }));
  }
  g.add(K.m(mergeList(hl), K.mat(game, 'ceramic', '#E6E2D2', { rough: 0.3, env: 0.08 })));
  for (const s of [-1, 1]) {
    addTo(g, xf(cbox(0.04, 0.12, 0.42, 0.012), { pos: [2.5, 0.64, s * 0.62] }), K.glow(game, '#C8201E', 1.3), null);
    addTo(g, xf(new THREE.BoxGeometry(4.6, 0.025, 0.012), { pos: [0, 0.74, s * (hw + 0.002)] }), chrome, null);
  }
  const tire = new THREE.LatheGeometry([[0.19, -0.11], [0.23, -0.12], [0.235, -0.121], [0.28, -0.122], [0.285, -0.121], [wr - 0.02, -0.11], [wr, -0.05], [wr, 0.05], [wr - 0.02, 0.11], [0.285, 0.121], [0.28, 0.122], [0.235, 0.121], [0.23, 0.12], [0.19, 0.11]].map(([r, y]) => new THREE.Vector2(r, y)), 12);
  K.tint(tire, (x, y, z) => { const r = Math.hypot(x, z); return Math.abs(y) > 0.1 && r > 0.232 && r < 0.283 ? new THREE.Color('#F2EEE4') : new THREE.Color('#2E2836'); });
  tire.rotateX(Math.PI / 2);
  const cap = new THREE.LatheGeometry([[0, 0.02], [0.19, 0.02], [0.2, 0], [0.14, -0.035], [0, -0.05]].reverse().map(([r, y]) => new THREE.Vector2(r, y)), 12).rotateX(Math.PI / 2);
  const T = [], Cp = [];
  for (const x of [-1.55, 1.5]) for (const s of [-1, 1]) {
    const q = s < 0 ? 0 : Math.PI;
    T.push(xf(tire, { pos: [x, wr, s * 0.82], rot: [0, q, 0] }));
    Cp.push(xf(cap, { pos: [x, wr, s * 0.93], rot: [0, q, 0] }));
    // wheel-well shadow
    const R = wr + 0.1, yl = 0.28 - wr + 0.01, dx = Math.sqrt(R * R - yl * yl), a0 = Math.atan2(yl, dx);
    const arch = new THREE.Shape(); arch.moveTo(dx, yl); arch.absarc(0, 0, R, a0, Math.PI - a0, false); arch.lineTo(dx, yl);
    const ag = new THREE.ShapeGeometry(arch, 10);
    if (s < 0) ag.rotateY(Math.PI);
    addTo(g, xf(ag, { pos: [x, wr, s * (hw + 0.003)] }), K.mat(game, 'paint', '#2A2232', { rough: 0.9 }), null);
  }
  g.add(K.m(mergeList(T), rubber));
  g.add(K.m(mergeList(Cp), chrome));
  g.userData.colliders = [{ min: [-2.62, 0, -hw - 0.05], max: [2.62, 1.38, hw + 0.05] }];
  return K.finish(game, g, { ao: { res: 56, strength: 0.85 } });
}, { category: CITY, tags: ['street', 'vehicle'], size: [5.3, 1.4, 2.0], desc: 'parked 70s boat sedan: two-tone body, vinyl roof, quad headlights, whitewalls; FRONT at -x (opts.color: avocado default, try #E8A92E #E3662B #7A4A2A #2E8C8C)' });
function addTo(g, geo, mat, col, o) { g.add(K.m(col ? K.tint(geo.clone ? geo.clone() : geo, col) : geo, mat, o)); }

function motelFaceTex(glow) {
  return K.tex.canvas(`out_motel|${glow ? 1 : 0}`, 512, 1024, (ctx, w, h) => {
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    if (glow) { ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h); } else {
      const gr = ctx.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#2F5BD3'); gr.addColorStop(1, '#1E2A6A');
      ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = 'rgba(255,255,255,0.12)'; for (let i = 0; i < 40; i++) { ctx.beginPath(); ctx.arc((i * 97) % w, (i * 211) % (h * 0.6), 3, 0, TAU); ctx.fill(); }
    }
    const neon = (txt, x, y, px, col, face = 'Shrikhand', rot = 0) => {
      ctx.save(); ctx.translate(x, y); ctx.rotate(rot);
      font(ctx, px, face);
      if (glow) { ctx.shadowColor = col; ctx.shadowBlur = 24; ctx.fillStyle = col; ctx.fillText(txt, 0, 0); ctx.shadowBlur = 0; ctx.fillStyle = '#fff'; ctx.globalAlpha = 0.6; ctx.fillText(txt, 0, 0); }
      else { ctx.lineWidth = 6; ctx.strokeStyle = '#1A1A3A'; ctx.strokeText(txt, 0, 0); ctx.fillStyle = hexMix(col, '#ffffff', 0.4); ctx.fillText(txt, 0, 0); }
      ctx.restore();
    };
    // star on top of the cabinet
    ctx.save(); ctx.translate(w / 2, 130);
    ctx.beginPath(); for (let i = 0; i < 10; i++) { const r = i % 2 ? 44 : 104, a = -Math.PI / 2 + i * Math.PI / 5; ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r); } ctx.closePath();
    if (glow) { ctx.shadowColor = '#FFD23A'; ctx.shadowBlur = 30; ctx.fillStyle = '#FFD23A'; ctx.fill(); } else { ctx.fillStyle = '#E8A92E'; ctx.fill(); ctx.lineWidth = 6; ctx.strokeStyle = '#1A1A3A'; ctx.stroke(); }
    ctx.restore();
    neon('Starlite', w / 2, 330, 118, '#FF5FA2', 'Shrikhand', -0.08);
    neon('MOTEL', w / 2, 500, 110, '#7FE7FF', 'Bungee');
    neon('COLOR TV', w / 2, 660, 62, '#FFD23A', 'Bungee');
    neon('POOL · AIR COND.', w / 2, 750, 34, '#F4F1E8', 'Titan One');
    neon('VACANCY', w / 2, 900, 76, '#FF3B30', 'Bungee');
  }, { repeat: false, fonts: true });
}
registerProp('st_motel_sign', (game, opts = {}) => {
  const g = K.prop('st_motel_sign');
  const lit = opts.lit !== false;
  const paint = K.mat(game, 'lacquer', '#ffffff', { rough: 0.45 });
  const face = K.mat(game, 'paint', '#ffffff', { map: motelFaceTex(false), rough: 0.6 });
  const W = 2.2, H = 4.4, Y = 3.2;
  // twin poles, cabinet with rounded top, face (both sides), glow overlay, arrow with bulbs
  for (const x of [-0.5, 0.5]) g.add(tm(K.cyl(0.1, 0.12, Y + 0.3, { seg: 10, bevel: 0.02 }), paint, '#E3662B', { pos: [x, 0, 0] }));
  g.add(tm(K.box(0.7, 0.3, 0.4, 0.05), paint, '#B8B2A4', { pos: [0, 0.15, 0] }));
  const cabShape = K.roundRect(W, H, 0.5);
  g.add(tm(K.extrude(cabShape, 0.36, { bevel: 0.05, bevelSeg: 2, curveSeg: 6 }), paint, '#F2EEE4', { pos: [0, Y + H / 2, 0] }));
  for (const [z, ry] of [[-0.185, 0], [0.185, Math.PI]]) {
    g.add(K.m(decal(W - 0.16, H - 0.16).rotateY(ry), face, { pos: [0, Y + H / 2, z] }));
  }
  const glowM = K.glow(game, '#ffffff', 1.5, { map: motelFaceTex(true), additive: true });
  const signGlow = lightMesh(new THREE.PlaneGeometry(W - 0.16, H - 0.16).rotateY(Math.PI), glowM, { pos: [0, Y + H / 2, -0.19], name: 'signGlow' });
  signGlow.visible = lit;
  g.add(signGlow);
  // arrow: points down-left toward the motel, bulbs along its rim
  const arrow = [[1.1, 0.25], [-0.6, 0.25], [-0.6, 0.55], [-1.25, 0], [-0.6, -0.55], [-0.6, -0.25], [1.1, -0.25]];
  const ag = K.extrude(arrow, 0.18, { bevel: 0.03, bevelSeg: 1, round: 0.06 });
  g.add(tm(ag, paint, '#E23B3B', { pos: [-1.0, Y + 0.7, -0.05], rot: [0, 0, 0.35] }));
  const bulbs = [];
  const P = [], q = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, 0.35));
  for (let i = 0; i < arrow.length; i++) {
    const a = arrow[i], b = arrow[(i + 1) % arrow.length];
    const n = Math.max(1, Math.round(Math.hypot(b[0] - a[0], b[1] - a[1]) / 0.2));
    for (let k = 0; k < n; k++) { const t = k / n; P.push([lerp(a[0], b[0], t) * 0.86, lerp(a[1], b[1], t) * 0.72]); }
  }
  for (const [px, py] of P) {
    const v = new THREE.Vector3(px, py, 0).applyQuaternion(q);
    bulbs.push(xf(new THREE.SphereGeometry(0.045, 6, 4), { pos: [-1.0 + v.x, Y + 0.7 + v.y, -0.16] }));
  }
  const bulbMesh = lightMesh(mergeList(bulbs), lit ? K.glow(game, PAL.marqueeGold, 2.4) : K.mat(game, 'ceramic', '#F0E6D0'), { name: 'arrowBulbs' });
  g.add(bulbMesh);
  g.userData.parts = { signGlow, arrowBulbs: bulbMesh };
  g.userData.lightAnchors = lit ? [{ pos: [0, Y + 2, -1.2], color: PAL.neonPink, intensity: 2, distance: 8, flicker: 0.06 }] : [];
  g.userData.colliders = [{ min: [-0.7, 0, -0.25], max: [0.7, 2.5, 0.25] }];
  return K.finish(game, g, { ao: { res: 48, dist: 0.2 } });
}, { category: CITY, tags: ['street', 'sign', 'neon'], size: [3.5, 7.7, 0.5], desc: '"Starlite MOTEL · COLOR TV · VACANCY" pole sign: star-topped cabinet (painted face both sides, lit overlay on -z), red arrow with marquee bulbs (parts.signGlow / arrowBulbs), opts.lit' });

// ------------------------------------------------------------------------------------------- scenes (propview)
registerScene('out_yard', {
  floor: '#4A4652', wall: '#1B1E4A', room: [150, 150], wallH: 0.01, hemi: 0.55, key: 0.9,
  items: [
    { id: 'yd_tower', pos: [9, 12] },
    { id: 'yd_hut', pos: [-7.5, 4.5], rotY: 0 },
    { id: 'yd_news_van', pos: [-1.5, 7], rotY: 0 },
    { id: 'yd_sodium_post', pos: [3.5, 1.5], rotY: Math.PI },
    { id: 'yd_sodium_post', pos: [15, 4], rotY: Math.PI / 2 },
    { id: 'yd_fence', pos: [-3, 20], opts: { sign: 'private' } },
    { id: 'yd_fence', pos: [0, 20], opts: { seed: 2 } },
    { id: 'yd_fence_gate', pos: [3.9, 20] },
    { id: 'yd_fence', pos: [8.7, 20], opts: { seed: 3, sign: 'wztv' } },
    { id: 'yd_fence', pos: [11.7, 20], opts: { seed: 4 } },
    { id: 'yd_drum_group', pos: [-10.5, 9], rotY: 0.4 },
    { id: 'yd_crate_stack', pos: [14, 9], rotY: -0.5 },
    { id: 'yd_puddle', pos: [2, 3] },
    { id: 'yd_gravel_patch', pos: [5, 7] },
    { id: 'yd_weeds', pos: [-4, 1.5] },
    { id: 'yd_stones', pos: [7, 4] },
    { id: 'sky_skyline', pos: [0, 88], opts: { seed: 3, ad: 'jump_cut' } },
    { id: 'sky_moon', pos: [-34, 34, 92], opts: { r: 6 } },
  ],
  cam: { pos: [1.5, 2.6, -13], target: [3, 5.5, 12], fov: 62 },
});
registerScene('out_street', {
  floor: '#3A3848', wall: '#1B1E4A', room: [60, 60], wallH: 0.01, hemi: 0.6, key: 0.9,
  items: [
    { id: 'st_sidewalk', pos: [-3, 4], rotY: Math.PI, opts: { len: 6 } },
    { id: 'st_sidewalk', pos: [3, 4], rotY: Math.PI, opts: { len: 6 } },
    { id: 'st_street_lamp', pos: [-1.5, 3.4] },
    { id: 'st_hydrant', pos: [1.6, 3.2], rotY: Math.PI },
    { id: 'st_mailbox', pos: [3.4, 3.8], rotY: Math.PI },
    { id: 'st_car_70s', pos: [-1.2, 1.4], rotY: Math.PI, opts: { color: '#E8A92E' } },
    { id: 'st_motel_sign', pos: [6.5, 6.2], rotY: 0 },
    { id: 'sky_building', pos: [-6, 14], opts: { style: 'brick', w: 10, h: 16, d: 8 } },
    { id: 'sky_building', pos: [5, 16], opts: { style: 'office', w: 12, h: 24, d: 8, seed: 2 } },
    { id: 'sky_billboard', pos: [-14, 12], rotY: 0.3, opts: { ad: 'replay_ade' } },
  ],
  cam: { pos: [0.5, 1.7, -7.5], target: [1, 2.6, 6], fov: 58 },
});
