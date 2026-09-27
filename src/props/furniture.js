// DEAD AIR — props: 70s FURNITURE & DECOR (docs/PROPKIT.md). Owner: furniture prop artist.
// Every builder registers with registerProp(id, build, { category: 'furniture', ... }). Shoot with
//   node tools/propview/shoot.cjs category:furniture      (or a single id)
//
// PLACEMENT CONVENTIONS used in this file (see also each prop's meta.desc / tags):
//   floor props   : kit default. Floor at y = 0, centered on x/z, FRONT (the side people use / sit facing) = -z.
//   'wall' tag    : origin = the point ON THE WALL under the prop's BOTTOM edge (back face at z = 0, prop extends
//                   toward -z into the room, centered on x). Place with pos = [x, bottomHeight, z-on-wall] and rotY so
//                   local -z points into the room. meta.desc gives a suggested bottom height. Colliders are [] (the
//                   wall already blocks) unless the prop sticks out > 0.15 m.
//   'ceiling' tag : origin = the attach point on the ceiling, prop hangs toward -y. Place with pos.y = ceiling height.
//                   Colliders are [] (out of reach).
//   'tabletop' tag: small props that sit on furniture (y = 0 is their base; put pos.y = the surface height).
//   Light fixtures carry lightAnchors and expose their glowing mesh as userData.parts.glow (noMerge) so rooms can
//   swap its material when the power is off (opts.lit = false builds it unlit).
// Colors: most parts use a few neutral-textured materials and get their color from vertex tints (tc()), so a
// prop stays at 2-5 materials; the AO bake multiplies on top.
//
// PROPS (46): seating  sofa_cloud* couch_avocado* couch_talkshow* armchair_barrel chair_ball bean_bag chair_office
//             desks    desk_reporter* desk_reception* desk_anchor* typewriter phone_rotary
//             tables   table_coffee table_side_tulip table_side_drum
//             lamps    lamp_arc lamp_tripod lamp_pole lamp_lava lamp_globe_pendant(ceiling) light_fluoro_panel(ceiling)
//                      light_can(ceiling)
//             plants   plant_rubber plant_fern plant_snake macrame_hanger(ceiling)
//             misc     water_cooler filing_cabinet coat_rack trash_can ash_urn vending_soda* vending_cigarette* bookshelf
//             wall     payphone_rotary clock_wall clock_sunburst cork_board frame_picture trophy_shelf macrame_owl
//                      trim_baseboard trim_chair_rail trim_crown
//             floor    rug_shag_round rug_shag_oval                                            (* = hero budget)
// Scenes (propview): furn_lobby, furn_newsroom, furn_green (set-dressing references), furn_ceiling (ceiling fixtures:
// they hang below y = 0 so the category sheet shows them as empty cells; review them in this scene).
// Shared building blocks here: cbox (44-tri chamfer box), channelShell (continuous channel tufting), arcSlab /
// arcColliders (curved desks), potGroup, phoneGroup / typewriterGroup / paperStack / mugGroup (desk dressing),
// deskAtlas() + decorAtlas() (4x4 printed-detail atlases, cell()/dcell() map a 0..1-UV geometry into a cell).

import * as K from './kit.js';
import { registerProp, registerScene, PAL, THREE } from './kit.js';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { mulberry32 } from '../core/rng.js';
import { getCard, cardInfo } from '../gfx/cards.js';

const { lerp, clamp } = THREE.MathUtils;
const UP = new THREE.Vector3(0, 1, 0);
const TAU = Math.PI * 2;
const CAT = 'furniture';

// =================================================================================================== helpers
const _geo = new Map();
function cg(key, make) {
  let g = _geo.get(key);
  if (!g) { g = make(); _geo.set(key, g); }
  return g;
}
// tinted copy (kit geometries are cached/shared: always clone before tinting)
const tc = (geo, color) => K.tint(geo.clone(), color);
const v3 = (a) => new THREE.Vector3(a[0], a[1], a[2]);
const sph = (r, ws = 14, hs = 10) => cg(`sph|${r}|${ws}|${hs}`, () => new THREE.SphereGeometry(r, ws, hs));

// mesh placed at a with its local +y pointing at b (for cyl/lathe geometry that grows along +y from y = 0)
function span(geo, mat, a, b) {
  const A = v3(a), B = v3(b);
  const msh = K.m(geo, mat);
  msh.position.copy(A);
  msh.quaternion.setFromUnitVectors(UP, B.sub(A).normalize());
  return msh;
}
// bevelled rod from a to b (rb = radius at a, r = radius at b)
function rod(r, a, b, mat, o = {}) {
  const len = v3(a).distanceTo(v3(b));
  const g = K.cyl(r, o.rb ?? r, len, { seg: o.seg ?? 10, bevel: o.bevel ?? Math.min(0.004, r * 0.4) });
  return span(o.color ? tc(g, o.color) : g, mat, a, b);
}

// 44-tri chamfered box (books, papers, keys, slats): flat bevels read as soft edges at small sizes. UVs 0..1 per
// face; the -z face reads left->right from the front (spines, labels).
function cbox(w, h, d, c = 0.004) {
  return cg(`cbox|${w}|${h}|${d}|${c}`, () => {
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

// taper + welded normals (K.taper recomputes flat normals on the non-indexed rounded box)
const taperS = (geo, o) => K.weldNormals(K.taper(geo, o));

// wall props: shift children so the bbox bottom sits at y = 0 and the back at z = 0. Returns [dy, dz].
function wallFit(g) {
  g.updateMatrixWorld(true);
  const bb = new THREE.Box3().setFromObject(g);
  const dy = -bb.min.y, dz = -bb.max.z;
  for (const c of g.children) { c.position.y += dy; c.position.z += dz; }
  return [dy, dz];
}

function ring(r, n, y = 0, a0 = 0, a1 = TAU, closed = true) {
  const pts = [];
  const cnt = closed ? n : n + 1;
  for (let i = 0; i < cnt; i++) { const a = a0 + (i / n) * (a1 - a0); pts.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
  return pts;
}

// flat disc/puck with rounded edge (lathe), base at y = 0
function puck(r, h, round = 0.02, seg = 24) {
  return K.lathe([[0, 0], [r, 0], [r, h], [0, h]], { round: Math.min(round, h / 2 - 1e-3, r / 2), seg, steps: 2 });
}

// removes triangles whose centroid satisfies cut(x,y,z) (indexed geometry in, indexed out)
function cutTris(geo, cut) {
  const g = geo.clone();
  const idx = g.index.array, p = g.attributes.position;
  const keep = [];
  for (let t = 0; t < idx.length; t += 3) {
    const a = idx[t], b = idx[t + 1], c = idx[t + 2];
    const x = (p.getX(a) + p.getX(b) + p.getX(c)) / 3, y = (p.getY(a) + p.getY(b) + p.getY(c)) / 3, z = (p.getZ(a) + p.getZ(b) + p.getZ(c)) / 3;
    if (!cut(x, y, z)) keep.push(a, b, c);
  }
  g.setIndex(keep);
  return g;
}
function flipGeo(geo) {
  const g = geo.clone();
  const idx = g.index.array;
  for (let i = 0; i < idx.length; i += 3) { const t = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t; }
  const n = g.attributes.normal;
  for (let i = 0; i < n.count; i++) n.setXYZ(i, -n.getX(i), -n.getY(i), -n.getZ(i));
  return g;
}

// ------------------------------------------------------------------------------------------------ textures
const ctxRR = (ctx, x, y, w, h, r) => { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); };

// 70s fabric patterns atlas (2x2): 0 flower power, 1 concentric circles, 2 racing stripes, 3 avocado ogee.
function patternTex() {
  return K.tex.canvas('furn_patterns', 512, 512, (ctx, W, H, rand) => {
    const S = 256;
    // 0: flower power (top-left)
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, S, S); ctx.clip();
    ctx.fillStyle = '#E8A92E'; ctx.fillRect(0, 0, S, S);
    const flower = (x, y, r, c, cc) => {
      ctx.fillStyle = c;
      for (let i = 0; i < 5; i++) { const a = i / 5 * TAU; ctx.beginPath(); ctx.ellipse(x + Math.cos(a) * r * 0.55, y + Math.sin(a) * r * 0.55, r * 0.5, r * 0.34, a, 0, TAU); ctx.fill(); }
      ctx.fillStyle = cc; ctx.beginPath(); ctx.arc(x, y, r * 0.3, 0, TAU); ctx.fill();
    };
    for (let i = 0; i < 9; i++) flower((i % 3) * 90 + 40 + (Math.floor(i / 3) % 2) * 40, Math.floor(i / 3) * 90 + 40, 30, i % 2 ? '#F6E7C8' : '#E3662B', i % 2 ? '#E3662B' : '#5A3A22');
    ctx.restore();
    // 1: concentric circles (top-right)
    ctx.save(); ctx.translate(S, 0); ctx.beginPath(); ctx.rect(0, 0, S, S); ctx.clip();
    ctx.fillStyle = '#5A3A22'; ctx.fillRect(0, 0, S, S);
    for (const [cx, cy] of [[64, 64], [192, 64], [64, 192], [192, 192]]) {
      ['#E3662B', '#E8A92E', '#F6E7C8', '#B5472A', '#5A3A22'].forEach((c, i) => { ctx.fillStyle = c; ctx.beginPath(); ctx.arc(cx, cy, 58 - i * 11, 0, TAU); ctx.fill(); });
    }
    ctx.restore();
    // 2: racing stripes (bottom-left)
    ctx.save(); ctx.translate(0, S); ctx.beginPath(); ctx.rect(0, 0, S, S); ctx.clip();
    ctx.fillStyle = '#F6E7C8'; ctx.fillRect(0, 0, S, S);
    ['#5A3A22', '#B5472A', '#E3662B', '#E8A92E'].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(0, 70 + i * 30, S, 24); });
    ctx.restore();
    // 3: avocado ogee (bottom-right)
    ctx.save(); ctx.translate(S, S); ctx.beginPath(); ctx.rect(0, 0, S, S); ctx.clip();
    ctx.fillStyle = '#8C9A3A'; ctx.fillRect(0, 0, S, S);
    ctx.strokeStyle = '#F6E7C8'; ctx.lineWidth = 7;
    for (let y = -64; y < S + 64; y += 64) for (let x = 0; x < S + 64; x += 64) {
      ctx.beginPath(); ctx.ellipse(x + ((y / 64) % 2 ? 32 : 0), y, 30, 30, 0, 0, TAU); ctx.stroke();
    }
    ctx.fillStyle = '#5A3A22';
    for (let y = 0; y < S; y += 64) for (let x = 0; x < S; x += 64) { ctx.beginPath(); ctx.arc(x + 32, y + 32, 6, 0, TAU); ctx.fill(); }
    ctx.restore();
    void rand; void W; void H;
  }, { repeat: false });
}
const PAT = { flower: [0, 0.5, 0.5, 1], circles: [0.5, 0.5, 1, 1], stripes: [0, 0, 0.5, 0.5], ogee: [0.5, 0, 1, 0.5] };
const patUV = (geo, key) => { const [u0, v0, u1, v1] = PAT[key]; return K.uvRect(geo.clone(), u0, v0, u1, v1); };

// neutral (light) fabric/vinyl/wood textures: color comes from vertex tints
const NEUTRAL = '#EDE6DA';
function M(game) {
  return {
    plastic: K.mat(game, 'plastic', '#ffffff'),
    lacquer: K.mat(game, 'lacquer', '#ffffff'),
    paint: K.mat(game, 'paint', '#ffffff'),
    metal: K.mat(game, 'metal', '#ffffff'),
    chrome: K.mat(game, 'chrome', '#A8B0BA'),
    brass: K.mat(game, 'brass', '#C8963C'),
    rubber: K.mat(game, 'rubber', '#ffffff'),
    cord: K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave(NEUTRAL, { pattern: 'cord', scale: 3 }), rim: 0.2, rimPower: 3.4, rimColor: '#FFD9B0', wrap: 0.6 }),
    tweed: K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave(NEUTRAL, { pattern: 'tweed', fleck: ['#FFFFFF', '#B8AE9C', '#8A806E'] }), rim: 0.2, rimPower: 3.4, rimColor: '#FFD9B0', wrap: 0.6 }),
    velvet: K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave(NEUTRAL, { pattern: 'plain', scale: 2 }), rim: 0.22, rimPower: 3.4, rimColor: '#FFD9B0', wrap: 0.6, rough: 0.8 }),
    vinyl: K.mat(game, 'vinyl', '#ffffff', { map: K.tex.pebble('#EEE8E0') }),
    teak: K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood(PAL.teak, { dark: 0.36 }) }),
    walnut: K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.42 }) }),
    pattern: K.mat(game, 'fabric', '#ffffff', { map: patternTex(), rim: 0.15, rimPower: 3.4, rimColor: '#FFD9B0', wrap: 0.6 }),
  };
}

// Button tufts: small domed discs on a surface point with normal n (world-aligned in prop space).
function tuft(g, mat, pos, n, color, r = 0.018) {
  const b = K.m(tc(K.lathe([[0, 0], [r, 0], [r * 0.85, r * 0.5], [0, r * 0.62]], { seg: 8 }), color), mat);
  b.position.set(pos[0], pos[1], pos[2]);
  b.quaternion.setFromUnitVectors(UP, v3(n).normalize());
  g.add(b);
}

// ================================================================================================== SEATING
// ------------------------------------------------------------------------------------------- cloud sofa
registerProp('sofa_cloud', (game, opts = {}) => {
  const g = K.prop('sofa_cloud');
  const mt = M(game);
  const col = opts.color ?? '#DE5A22';
  const deep = new THREE.Color(col).multiplyScalar(0.72).getStyle();
  const seatW = 0.66, n = 3, armW = 0.26, D = 0.98;
  const W = seatW * n + armW * 2;
  // recessed walnut plinth
  g.add(K.m(K.box(W - 0.3, 0.1, D - 0.3, 'sm', { uv: 1.5 }), mt.walnut, { pos: [0, 0.05, 0.02] }));
  // deck
  g.add(K.m(tc(K.cushion(seatW * n + 0.04, 0.2, D, { puff: 0.025, r: 0.07, seg: [10, 3, 5], uv: 3 }), deep), mt.cord, { pos: [0, 0.2, 0] }));
  // seat + back cushions
  for (let i = 0; i < n; i++) {
    const x = (i - (n - 1) / 2) * seatW;
    g.add(K.m(tc(K.cushion(seatW - 0.01, 0.22, 0.8, { puff: 0.08, r: 0.1, seg: [8, 4, 8], uv: 3 }), col), mt.cord, { pos: [x, 0.41, -0.08] }));
    g.add(K.m(tc(K.cushion(seatW - 0.02, 0.5, 0.28, { puff: 0.09, r: 0.13, seg: [8, 6, 3], uv: 3 }), col), mt.cord, { pos: [x, 0.63, 0.32], rot: [0.2, 0, 0] }));
  }
  g.add(K.m(tc(K.cushion(seatW * n + 0.04, 0.66, 0.16, { puff: 0.03, r: 0.07, seg: [10, 4, 2], uv: 3 }), deep), mt.cord, { pos: [0, 0.56, D / 2 - 0.09], rot: [0.1, 0, 0] }));
  // cloud arms: tall puffy bolsters
  for (const s of [-1, 1]) {
    g.add(K.m(tc(K.cushion(armW + 0.04, 0.6, D + 0.02, { puff: 0.07, r: 0.15, seg: [4, 6, 8], uv: 3 }), col), mt.cord, { pos: [s * (W / 2 - armW / 2), 0.36, 0] }));
  }
  // throw pillows (flower power + circles)
  g.add(K.m(patUV(K.cushion(0.42, 0.42, 0.13, { puff: 0.06, r: 0.06, seg: [5, 5, 2] }), 'flower'), mt.pattern, { pos: [-0.66, 0.72, 0.12], rot: [0.28, 0.35, 0.12] }));
  g.add(K.m(patUV(K.cushion(0.38, 0.38, 0.12, { puff: 0.055, r: 0.06, seg: [5, 5, 2] }), 'circles'), mt.pattern, { pos: [0.7, 0.7, 0.12], rot: [0.26, -0.4, -0.1] }));
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, 0.55, D / 2] }, { min: [-W / 2, 0, 0.15], max: [W / 2, 0.86, D / 2] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['seat', 'sofa', 'lobby'], size: [2.5, 0.87, 0.98], desc: 'orange corduroy "cloud" sofa, puffy arms, flower-power pillows (opts.color)', hero: true });

// --------------------------------------------------------------------------------------- avocado couch
registerProp('couch_avocado', (game, opts = {}) => {
  const g = K.prop('couch_avocado');
  const mt = M(game);
  const col = opts.color ?? '#8C9A3A';
  const dark = new THREE.Color(col).multiplyScalar(0.6).getStyle();
  const n = 3, sw = 0.62, W = sw * n + 0.2, D = 0.84;
  // teak frame: side slabs with flat arm caps, front/back rails, tapered splayed legs
  for (const s of [-1, 1]) {
    g.add(K.m(K.box(0.07, 0.36, D - 0.06, 'sm', { uv: 1.4, swap: true }), mt.teak, { pos: [s * (W / 2 - 0.05), 0.42, 0] }));
    g.add(K.m(K.box(0.14, 0.045, D + 0.02, 0.018, { uv: 1.4, swap: true }), mt.teak, { pos: [s * (W / 2 - 0.05), 0.62, 0] }));
  }
  g.add(K.m(K.box(W - 0.14, 0.07, 0.05, 'sm', { uv: 1.4 }), mt.teak, { pos: [0, 0.26, -D / 2 + 0.06] }));
  g.add(K.m(K.box(W - 0.14, 0.07, 0.05, 'sm', { uv: 1.4 }), mt.teak, { pos: [0, 0.26, D / 2 - 0.06] }));
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1], [0, -1], [0, 1]]) {
    const bx = x * (W / 2 - 0.09), bz = z * (D / 2 - 0.07);
    g.add(rod(0.026, [bx + x * 0.035, 0.012, bz + z * 0.03], [bx, 0.25, bz], mt.teak, { rb: 0.016, seg: 10 }));
    g.add(K.m(K.cyl(0.017, 0.018, 0.018, { seg: 10, bevel: 0.005 }), mt.brass, { pos: [bx + x * 0.036, 0, bz + z * 0.031] }));
  }
  // upholstered deck + back panel
  g.add(K.m(tc(K.box(W - 0.16, 0.12, D - 0.1, 0.03, { uv: 3 }), dark), mt.tweed, { pos: [0, 0.33, 0] }));
  g.add(K.m(tc(K.cushion(W - 0.16, 0.44, 0.1, { puff: 0.015, r: 0.04, seg: [8, 4, 2], uv: 3 }), dark), mt.tweed, { pos: [0, 0.6, D / 2 - 0.07], rot: [0.14, 0, 0] }));
  for (let i = 0; i < n; i++) {
    const x = (i - (n - 1) / 2) * sw;
    g.add(K.m(tc(K.cushion(sw - 0.012, 0.16, 0.66, { puff: 0.045, r: 0.05, seg: [7, 3, 7], uv: 3 }), col), mt.tweed, { pos: [x, 0.47, -0.06] }));
    // welt piping along the front top edge
    g.add(K.m(tc(K.tube([[x - sw / 2 + 0.06, 0.545, -0.39], [x + sw / 2 - 0.06, 0.545, -0.39]], 0.011, { seg: 2, radial: 6 }), dark), mt.tweed));
    const bz = 0.28, by = 0.74;
    g.add(K.m(tc(K.cushion(sw - 0.02, 0.44, 0.17, { puff: 0.05, r: 0.06, seg: [6, 5, 2], uv: 3 }), col), mt.tweed, { pos: [x, by, bz], rot: [0.2, 0, 0] }));
    for (const bx of [-0.14, 0.14]) tuft(g, mt.tweed, [x + bx, by + 0.04, bz - 0.14], [0, 0.2, -1], dark, 0.02);
  }
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, 0.64, D / 2] }, { min: [-W / 2, 0, 0.1], max: [W / 2, 0.98, D / 2] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['seat', 'sofa', 'green_room', 'telly_home'], size: [2.06, 0.98, 0.86], desc: 'avocado tweed couch on a Danish teak frame, tufted back (opts.color)', hero: true });

// ------------------------------------------------------------------------------------ talk-show couch
registerProp('couch_talkshow', (game, opts = {}) => {
  const g = K.prop('couch_talkshow');
  const mt = M(game);
  const col = opts.color ?? '#E8A92E';
  const pip = opts.piping ?? '#B5472A';
  const Rc = 2.4, span = 0.62; // arc radius, half angle (rad); arc center in front (-z) so it hugs the guests
  const cz = -Rc + 0.55; // arc center z (front)
  const at = (r, a, y = 0) => [Math.sin(a) * r, y, cz + Math.cos(a) * r];
  // plinth: extruded annulus sector (walnut) + chrome kick rail
  const sector = (r0, r1, a0, a1, steps = 20) => {
    const pts = [];
    for (let i = 0; i <= steps; i++) { const a = lerp(a0, a1, i / steps); pts.push([Math.sin(a) * r1, -(cz + Math.cos(a) * r1)]); }
    for (let i = steps; i >= 0; i--) { const a = lerp(a0, a1, i / steps); pts.push([Math.sin(a) * r0, -(cz + Math.cos(a) * r0)]); }
    return pts;
  };
  const plinth = K.extrude(sector(Rc - 0.46, Rc + 0.12, -span, span), 0.14, { bevel: 0.02, round: 0.03, uv: 1.4 });
  plinth.rotateX(-Math.PI / 2);
  g.add(K.m(plinth, mt.walnut, { pos: [0, 0.07 + 0.02, 0] }));
  g.add(K.m(K.tube(ring(Rc - 0.47, 24, 0, -span, span, false).map(([x, y, z]) => [x, 0.035, z + cz]), 0.018, { seg: 36, radial: 6 }), mt.chrome));
  // seat cushions along the arc
  const nSeat = 4, segA = (span * 2) / nSeat;
  for (let i = 0; i < nSeat; i++) {
    const a = -span + segA * (i + 0.5);
    const w = segA * (Rc - 0.2) - 0.02;
    const c = K.m(tc(K.cushion(w, 0.18, 0.62, { puff: 0.05, r: 0.07, seg: [7, 3, 6], uv: 3 }), col), mt.velvet);
    c.position.set(...at(Rc - 0.2, a, 0.28));
    c.rotation.y = a;
    g.add(c);
    // piping on the front-top edge (follows the cushion)
    const pw = w / 2 - 0.05;
    const p0 = new THREE.Vector3(-pw, 0.36, -0.3).applyAxisAngle(UP, a).add(v3(at(Rc - 0.2, a)));
    const p1 = new THREE.Vector3(pw, 0.36, -0.3).applyAxisAngle(UP, a).add(v3(at(Rc - 0.2, a)));
    g.add(K.m(tc(K.tube([p0.toArray(), p1.toArray()], 0.012, { seg: 2, radial: 6 }), pip), mt.velvet));
  }
  // channel-tufted back: vertical rolls around the arc
  const nCh = 14, chA = (span * 2) / nCh;
  for (let i = 0; i < nCh; i++) {
    const a = -span + chA * (i + 0.5);
    const w = chA * (Rc + 0.05);
    const c = K.m(tc(K.cushion(w + 0.012, 0.56, 0.16, { puff: 0.045, r: 0.07, seg: [3, 7, 2], uv: 3 }), col), mt.velvet);
    c.position.set(...at(Rc + 0.04, a, 0.62));
    c.rotation.set(0, a, 0);
    c.rotateX(0.14);
    g.add(c);
  }
  // back cap roll (piping color) along the top
  g.add(K.m(tc(K.tube(ring(Rc + 0.07, 24, 0, -span, span, false).map(([x, , z]) => [x, 0.885, z + cz]), 0.04, { seg: 30, radial: 8 }), pip), mt.velvet));
  // rounded arms
  for (const s of [-1, 1]) {
    const a = s * (span + 0.03);
    const c = K.m(tc(K.cushion(0.2, 0.36, 0.7, { puff: 0.035, r: 0.09, seg: [3, 5, 7], uv: 3 }), col), mt.velvet);
    c.position.set(...at(Rc - 0.14, a, 0.36));
    c.rotation.y = a;
    g.add(c);
    g.add(K.m(tc(K.cushion(0.22, 0.08, 0.72, { puff: 0.02, r: 0.035, seg: [3, 2, 7], uv: 3 }), pip), mt.velvet, { pos: at(Rc - 0.14, a, 0.56), rot: [0, a, 0] }));
  }
  // a guest's forgotten throw pillow
  g.add(K.m(patUV(K.cushion(0.38, 0.38, 0.12, { puff: 0.055, r: 0.06, seg: [5, 5, 2] }), 'stripes'), mt.pattern, { pos: [...at(Rc - 0.02, 0.38, 0.62)], rot: [0.25, 0.38, 0.1] }));
  const cols = [];
  for (let i = 0; i < 5; i++) {
    const a0 = lerp(-span - 0.1, span + 0.1, i / 5), a1 = lerp(-span - 0.1, span + 0.1, (i + 1) / 5);
    const xs = [a0, a1].map((a) => Math.sin(a) * (Rc + 0.12)).concat([a0, a1].map((a) => Math.sin(a) * (Rc - 0.5)));
    const zf = cz + Math.max(Math.cos(a0), Math.cos(a1)) * (Rc - 0.5);
    const zb = cz + Math.max(Math.cos(a0), Math.cos(a1), Math.cos((a0 + a1) / 2)) * (Rc + 0.14);
    cols.push({ min: [+Math.min(...xs).toFixed(3), 0, +zf.toFixed(3)], max: [+Math.max(...xs).toFixed(3), 0.95, +zb.toFixed(3)] });
  }
  g.userData.colliders = cols;
  return K.finish(game, g);
}, { category: CAT, tags: ['seat', 'sofa', 'studio_a', 'telly_home'], size: [2.8, 0.96, 1.15], desc: 'curved harvest-gold velvet talk-show couch, channel-tufted back, walnut plinth', hero: true });

// ------------------------------------------------------------------------------------ barrel armchair
// Continuous channel-tufted shell around the y axis: inner face puffs toward the sitter in `n` vertical channels,
// outer face smooth, height per angle from hAt(a). Returns { geo, edge } (edge = welt path: front-left bottom ->
// up -> along the top -> down to front-right bottom).
function channelShell({ R, a0, a1, y0, hAt, thick = 0.09, n = 9, puff = 0.035, nv = 5, per = 3 }) {
  const nu = n * per;
  const pos = [], uv = [], idx = [];
  const at = (a, y, r) => [Math.sin(a) * r, y, Math.cos(a) * r];
  const chan = (u) => Math.pow(Math.sin(Math.PI * ((u * n) % 1)), 0.5);
  const inner = (u, t) => { const a = lerp(a0, a1, u); return at(a, y0 + t * hAt(a), R - puff * chan(u) * Math.pow(Math.sin(Math.PI * clamp(t * 1.08, 0, 1)), 0.4)); };
  const outer = (u, t) => { const a = lerp(a0, a1, u); return at(a, y0 + t * hAt(a), R + thick); };
  const grid = (fn, cu, cv, want) => {
    const base = pos.length / 3;
    for (let j = 0; j <= cv; j++) for (let i = 0; i <= cu; i++) {
      const p = fn(i / cu, j / cv);
      pos.push(p[0], p[1], p[2]); uv.push((i / cu) * (a1 - a0) * R * 3, (j / cv) * 1.5);
    }
    // orientation test on the middle cell
    const ci = Math.floor(cu / 2), cj = Math.floor(cv / 2);
    const A = v3(fn(ci / cu, cj / cv)), B = v3(fn((ci + 1) / cu, cj / cv)), C = v3(fn(ci / cu, (cj + 1) / cv));
    const nrm = B.clone().sub(A).cross(C.clone().sub(A));
    const flip = nrm.dot(v3(want(ci / cu, cj / cv))) < 0;
    for (let j = 0; j < cv; j++) for (let i = 0; i < cu; i++) {
      const a = base + j * (cu + 1) + i, b = a + 1, c = a + cu + 1, d = c + 1;
      if (flip) idx.push(a, c, b, b, c, d); else idx.push(a, b, c, b, d, c);
    }
  };
  const radial = (u) => { const a = lerp(a0, a1, u); return [Math.sin(a), 0, Math.cos(a)]; };
  grid(inner, nu, nv, (u) => radial(u).map((v) => -v));
  grid(outer, nu, nv, radial);
  grid((u, s) => { const p = inner(u, 1), q = outer(u, 1); return [lerp(p[0], q[0], s), lerp(p[1], q[1], s), lerp(p[2], q[2], s)]; }, nu, 1, () => [0, 1, 0]);
  for (const e of [0, 1]) {
    grid((t, s) => { const p = inner(e, t), q = outer(e, t); return [lerp(p[0], q[0], s), lerp(p[1], q[1], s), lerp(p[2], q[2], s)]; }, nv, 1, () => {
      const a = e ? a1 : a0, sg = e ? 1 : -1; return [Math.cos(a) * sg, 0, -Math.sin(a) * sg];
    });
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const cols = new Float32Array(pos.length).fill(1);
  for (let j = 0; j <= nv; j++) for (let i = 0; i <= nu; i++) {
    const k = 0.62 + 0.38 * chan(i / nu), o = (j * (nu + 1) + i) * 3;
    cols[o] = k; cols[o + 1] = k; cols[o + 2] = k;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
  const mid = (u, t) => { const p = inner(u, t), q = outer(u, t); return [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2]; };
  const edge = [mid(0, 0), mid(0, 0.5), mid(0, 1)];
  for (let i = 1; i < 20; i++) { const p = mid(i / 20, 1); edge.push([p[0], p[1] + 0.004, p[2]]); }
  edge.push(mid(1, 1), mid(1, 0.5), mid(1, 0));
  return { geo, edge };
}

registerProp('armchair_barrel', (game, opts = {}) => {
  const g = K.prop('armchair_barrel');
  const mt = M(game);
  const col = opts.color ?? '#C4502A';
  const dark = new THREE.Color(col).multiplyScalar(0.62).getStyle();
  const R = 0.36;
  // swivel plinth: walnut drum + brass ring and collar
  g.add(K.m(puck(0.27, 0.1, 0.02, 20), mt.walnut));
  g.add(K.m(K.tube(ring(0.272, 20, 0.1), 0.01, { seg: 20, radial: 4, closed: true }), mt.brass));
  g.add(K.m(K.cyl(0.08, 0.1, 0.07, { seg: 16 }), mt.brass, { pos: [0, 0.1, 0] }));
  // upholstered drum body + round seat cushion with welts
  g.add(K.m(tc(puck(R + 0.05, 0.2, 0.06, 24), col), mt.velvet, { pos: [0, 0.16, 0] }));
  g.add(K.m(tc(K.tube(ring(R + 0.05, 24, 0.185), 0.012, { seg: 24, radial: 4, closed: true }), dark), mt.velvet));
  g.add(K.m(tc(puck(R - 0.035, 0.12, 0.05, 24), col), mt.velvet, { pos: [0, 0.35, -0.03] }));
  g.add(K.m(tc(K.tube(ring(R - 0.04, 24, 0.44), 0.011, { seg: 24, radial: 4, closed: true }), dark), mt.velvet, { pos: [0, 0, -0.03] }));
  // continuous channel-tufted barrel back sweeping down into the arms, welt all around its edge
  const hAt = (a) => 0.22 + 0.3 * Math.pow(Math.max(0, Math.cos((a / 2.2) * Math.PI / 2)), 0.9);
  const { geo, edge } = channelShell({ R: R + 0.0, a0: -2.2, a1: 2.2, y0: 0.34, hAt, thick: 0.08, n: 11, puff: 0.06, nv: 5, per: 3 });
  g.add(K.m(tc(K.uvScale(geo, 1, 1), col), mt.velvet));
  g.add(K.m(tc(K.tube(edge, 0.045, { seg: 36, radial: 6 }), dark), mt.velvet));
  g.userData.colliders = [{ min: [-0.44, 0, -0.44], max: [0.44, 0.9, 0.44] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['seat', 'chair', 'lobby', 'green_room'], size: [0.88, 0.9, 0.88], desc: 'rust velvet channel-tufted barrel swivel chair on a walnut plinth (opts.color)' });

// ------------------------------------------------------------------------------------------ ball chair
registerProp('chair_ball', (game, opts = {}) => {
  const g = K.prop('chair_ball');
  const mt = M(game);
  const shellCol = opts.shell ?? '#F4F1E8';
  const inCol = opts.color ?? '#E3662B';
  const R = 0.55, cy = 0.2 + R, cut = 0.4;
  const th0 = Math.acos(cut);
  // spheres opened around -z (pole rotated from +y to -z so the opening edge is a clean circle)
  const shell = (r, ws, hs) => new THREE.SphereGeometry(r, ws, hs, 0, TAU, th0, Math.PI - th0).rotateX(-Math.PI / 2);
  g.add(K.m(tc(shell(R, 28, 14), shellCol), mt.lacquer, { pos: [0, cy, 0] }));
  const Ri = R - 0.05;
  g.add(K.m(K.uvScale(tc(flipGeo(shell(Ri, 22, 11)), inCol), 8, 3), mt.vinyl, { pos: [0, cy, 0] }));
  // rolled rim joining the two shells
  const rz = -(R + Ri) / 2 * cut, rr = Math.sqrt(1 - cut * cut) * (R + Ri) / 2;
  g.add(K.m(tc(new THREE.TorusGeometry(rr, 0.032, 6, 32), shellCol), mt.lacquer, { pos: [0, cy, rz] }));
  // inside: seat puck + tufted back cushion
  g.add(K.m(K.uvScale(tc(puck(0.35, 0.13, 0.055, 24), inCol), 3, 1), mt.vinyl, { pos: [0, cy - 0.38, -0.02] }));
  g.add(K.m(tc(K.cushion(0.52, 0.44, 0.13, { puff: 0.06, r: 0.06, seg: [5, 5, 2], uv: 3 }), inCol), mt.vinyl, { pos: [0, cy + 0.0, 0.3], rot: [0.28, 0, 0] }));
  for (const [x, y] of [[-0.12, 0.06], [0.12, 0.06], [0, -0.08]]) tuft(g, mt.vinyl, [x, cy + y, 0.3 - 0.075 + y * 0.28], [0, 0.28, -1], new THREE.Color(inCol).multiplyScalar(0.6).getStyle(), 0.02);
  // trumpet pedestal
  g.add(K.m(tc(K.lathe([[0, 0], [0.34, 0], [0.34, 0.025], [0.18, 0.06], [0.08, 0.14], [0.07, 0.24], [0, 0.24]], { round: 0.02, seg: 22, steps: 1 }), shellCol), mt.lacquer));
  g.userData.colliders = [{ min: [-R, 0, -R], max: [R, cy + R, R] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['seat', 'chair', 'lobby', 'green_room'], size: [1.1, 1.3, 1.1], desc: 'space-age ball chair: white lacquer shell, orange vinyl interior, trumpet base (opts.color/shell)' });

// --------------------------------------------------------------------------------------------- bean bag
registerProp('bean_bag', (game, opts = {}) => {
  const g = K.prop('bean_bag');
  const mt = M(game);
  const col = opts.color ?? '#E23B3B';
  const seed = opts.seed ?? 3;
  const rnd = mulberry32(seed * 131 + 7);
  const ph = [rnd() * 6, rnd() * 6, rnd() * 6];
  const H = 0.68, Rb = 0.42;
  // slouchy pear: wide pooled bottom, narrower top leaning back, a sitting dent on the front
  const dent = new THREE.Vector3(0, 0.62, -0.78).normalize();
  const d = new THREE.Vector3();
  const shape = (x, y, z) => {
    d.set(x, y, z).normalize();
    const phi = Math.acos(clamp(d.y, -1, 1)), t = phi / Math.PI, th = Math.atan2(d.z, d.x);
    let r = Rb * Math.pow(Math.sin(phi), 0.6) * (0.5 + 0.5 * Math.pow(t, 0.7)) * (1 + 0.07 * Math.sin(th * 4 + ph[0] + t * 5) * Math.sin(phi));
    let yy = H * Math.pow(Math.cos(phi) * 0.5 + 0.5, 1.25);
    const k = Math.max(0, d.dot(dent) - 0.5) / 0.5;
    yy -= k * k * 0.16; r *= 1 + k * 0.06;
    yy += 0.025 * Math.sin(th * 3 + ph[1]) * (1 - t);
    const lean = 0.09 * Math.pow(yy / H, 2);
    return [Math.cos(th) * r, Math.max(0.004, yy), Math.sin(th) * r + lean];
  };
  const geo = new THREE.SphereGeometry(1, 32, 18);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) { const [x, y, z] = shape(p.getX(i), p.getY(i), p.getZ(i)); p.setXYZ(i, x, y, z); }
  geo.computeVertexNormals();
  K.uvScale(geo, 5, 2.5);
  g.add(K.m(tc(geo, col), mt.vinyl));
  // panel seams (slightly proud) + a carry strap on the crown
  const dark = new THREE.Color(col).multiplyScalar(0.6).getStyle();
  for (let s = 0; s < 6; s++) {
    const th = s * Math.PI / 3 + 0.3;
    const pts = [];
    for (let i = 0; i <= 12; i++) {
      const phi = lerp(0.1, 2.2, i / 12);
      const [x, y, z] = shape(Math.sin(phi) * Math.cos(th), Math.cos(phi), Math.sin(phi) * Math.sin(th));
      pts.push([x * 1.012, y + 0.002, z * 1.012]);
    }
    g.add(K.m(tc(K.tube(pts, 0.006, { seg: 18, radial: 4 }), dark), mt.vinyl));
  }
  const top = shape(0, 1, 0.001);
  g.add(K.m(tc(K.tube([[top[0] - 0.06, top[1] - 0.01, top[2] + 0.02], [top[0], top[1] + 0.045, top[2] + 0.03], [top[0] + 0.06, top[1] - 0.01, top[2] + 0.02]], 0.013, { seg: 10, radial: 5 }), dark), mt.vinyl));
  g.userData.colliders = [{ min: [-0.4, 0, -0.4], max: [0.4, 0.6, 0.45] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['seat', 'studio_b', 'green_room'], size: [0.84, 0.68, 0.9], desc: 'slouchy glossy vinyl bean bag with a sitting dent, panel seams, carry strap (opts.color, opts.seed)' });

// ------------------------------------------------------------------------------------ rolling office chair
registerProp('chair_office', (game, opts = {}) => {
  const g = K.prop('chair_office');
  const mt = M(game);
  const col = opts.color ?? '#D2642E';
  const dark = '#3A2A30', shellC = '#4A3530';
  // 5-star polished base with hooded casters
  const legGeo = cg('office_leg', () => taperS(K.box(0.3, 0.04, 0.056, 0.012), { axis: 'x', k: 0.62 }));
  const wheel = cg('office_wheel', () => new THREE.CylinderGeometry(0.03, 0.03, 0.044, 10, 1).translate(0, 0, 0));
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * TAU + 0.3;
    const leg = K.m(legGeo, mt.chrome);
    leg.position.set(Math.sin(a) * 0.15, 0.085, Math.cos(a) * 0.15);
    leg.rotation.set(0, a - Math.PI / 2, -0.1);
    g.add(leg);
    const cx = Math.sin(a) * 0.285, cz = Math.cos(a) * 0.285;
    g.add(K.m(tc(wheel, dark), mt.rubber, { pos: [cx, 0.03, cz], rot: [0, a, Math.PI / 2] }));
    g.add(K.m(tc(cbox(0.056, 0.03, 0.05, 0.008), dark), mt.plastic, { pos: [cx, 0.058, cz], rot: [0, a, 0] }));
  }
  g.add(K.m(K.cyl(0.05, 0.056, 0.06, { seg: 12 }), mt.chrome, { pos: [0, 0.065, 0] }));
  g.add(K.m(tc(K.lathe([[0, 0], [0.034, 0], [0.038, 0.03], [0.03, 0.05], [0.038, 0.07], [0.03, 0.09], [0.038, 0.11], [0.03, 0.13], [0.036, 0.16], [0, 0.16]], { seg: 10 }), dark), mt.rubber, { pos: [0, 0.12, 0] }));
  g.add(K.m(K.cyl(0.022, 0.022, 0.16, { seg: 10 }), mt.chrome, { pos: [0, 0.26, 0] }));
  g.add(K.m(tc(K.box(0.22, 0.03, 0.22, 0.01), dark), mt.plastic, { pos: [0, 0.42, 0] }));
  // tilt knob
  g.add(K.m(tc(K.lathe([[0, 0], [0.025, 0], [0.028, 0.02], [0.02, 0.03], [0, 0.03]], { seg: 10 }), dark), mt.plastic, { pos: [0.11, 0.41, -0.02], rot: [0, 0, -Math.PI / 2] }));
  // seat: molded shell + biscuit-tufted vinyl cushion
  g.add(K.m(tc(K.box(0.5, 0.05, 0.48, 0.014), shellC), mt.plastic, { pos: [0, 0.455, -0.02] }));
  g.add(K.m(tc(K.cushion(0.5, 0.1, 0.48, { puff: 0.035, r: 0.04, seg: [6, 2, 6], uv: 3 }), col), mt.vinyl, { pos: [0, 0.52, -0.02] }));
  const dk = new THREE.Color(col).multiplyScalar(0.55).getStyle();
  g.add(K.m(tc(K.tube([[-0.2, 0.572, -0.03], [0.2, 0.572, -0.03]], 0.006, { seg: 2, radial: 4 }), dk), mt.vinyl));
  // spine + back cushion with a stitched channel
  g.add(K.m(K.tube([[0, 0.44, 0.1], [0, 0.45, 0.25], [0, 0.52, 0.29], [0, 0.66, 0.29]], 0.018, { seg: 10, radial: 7 }), mt.chrome));
  g.add(K.m(tc(K.box(0.44, 0.34, 0.04, 0.014), shellC), mt.plastic, { pos: [0, 0.83, 0.3], rot: [-0.08, 0, 0] }));
  g.add(K.m(tc(K.cushion(0.44, 0.34, 0.08, { puff: 0.03, r: 0.035, seg: [5, 4, 2], uv: 3 }), col), mt.vinyl, { pos: [0, 0.83, 0.255], rot: [-0.08, 0, 0] }));
  g.add(K.m(tc(K.tube([[-0.18, 0.82, 0.205], [0.18, 0.82, 0.205]], 0.005, { seg: 2, radial: 4 }), dk), mt.vinyl));
  // chrome loop arms with black pads
  for (const s of [-1, 1]) {
    g.add(K.m(K.tube([[s * 0.2, 0.46, 0.12], [s * 0.27, 0.52, 0.12], [s * 0.27, 0.66, 0.05], [s * 0.27, 0.66, -0.12], [s * 0.24, 0.5, -0.16], [s * 0.2, 0.46, -0.14]], 0.012, { seg: 16, radial: 6 }), mt.chrome));
    g.add(K.m(tc(K.box(0.055, 0.035, 0.2, 0.012), dark), mt.plastic, { pos: [s * 0.27, 0.685, -0.03] }));
  }
  g.userData.colliders = [{ min: [-0.3, 0, -0.3], max: [0.3, 1.0, 0.33] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['seat', 'chair', 'newsroom', 'master_control'], size: [0.6, 1.02, 0.62], desc: 'rolling office chair: 5-star chrome base, bellows column, orange vinyl (opts.color)' });

// ------------------------------------------------------------------------------------ desk atlas
// One 1024 atlas (4x4 cells of 256) for every small printed desk thing: cell(geo, cx, cy) maps a 0..1-UV geometry
// into a cell (cx, cy counted from the top-left). Uses the matte 'paint' preset (paper, cards, decals).
function deskAtlas() {
  return K.tex.canvas('furn_desk_atlas', 1024, 1024, (ctx, W, H, rand) => {
    const S = 256;
    const at = (cx, cy, fn) => { ctx.save(); ctx.translate(cx * S, cy * S); ctx.beginPath(); ctx.rect(0, 0, S, S); ctx.clip(); fn(); ctx.restore(); };
    const font = (px, f = 'Titan One') => `${px}px "${f}", "Arial Black", sans-serif`;
    const typed = (lines, x, y, lh, px = 13, col = '#2A2230') => {
      ctx.fillStyle = col; ctx.font = `${px}px "Courier New", monospace`; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
      lines.forEach((l, i) => ctx.fillText(l, x, y + i * lh));
    };
    // (0,0) rotary dial: number ring + finger holes
    at(0, 0, () => {
      ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(128, 128, 128, 0, TAU); ctx.fill();
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      for (let i = 0; i < 10; i++) {
        const a = -Math.PI * 0.62 + i * 0.5, x = 128 + Math.cos(a) * 84, y = 128 + Math.sin(a) * 84;
        ctx.fillStyle = '#1E1530'; ctx.beginPath(); ctx.arc(x, y, 24, 0, TAU); ctx.fill();
        ctx.fillStyle = '#F4F1E8'; ctx.font = font(22); ctx.fillText(String((i + 1) % 10), x, y + 1);
      }
      ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(128, 128, 40, 0, TAU); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; ctx.font = font(18, 'Bungee'); ctx.fillText('WZ-13', 128, 130);
    });
    // (1,0) typed sheet
    at(1, 0, () => {
      ctx.fillStyle = '#FBF6EA'; ctx.fillRect(0, 0, S, S);
      typed(['WZTV ACTION 13 NEWS', '11:59 PM  FRI OCT 31', '', 'REPORTS OF STRANGE', 'VIEWERS "TUNING IN"', 'NEAR THE STATION...', '', 'STAY TUNED. DO NOT', 'ADJUST YOUR SET.', '', '-- 30 --'], 18, 30, 19);
      ctx.fillStyle = '#E23B3B'; ctx.fillRect(18, 36, 150, 2);
    });
    // (2,0) TV WEEKLY magazine cover (cards.js)
    at(2, 0, () => { ctx.fillStyle = '#E23B3B'; ctx.fillRect(0, 0, S, S); drawCard(ctx, 'magazine_tv_weekly', 40, 0, 176, 256); ctx.fillStyle = '#E23B3B'; ctx.fillRect(0, 0, 40, S); ctx.fillRect(216, 0, 40, S); });
    // (3,0) yellow legal pad
    at(3, 0, () => {
      ctx.fillStyle = '#FBE88A'; ctx.fillRect(0, 0, S, S);
      ctx.strokeStyle = '#7FB4E0'; ctx.lineWidth = 2;
      for (let y = 40; y < S; y += 18) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(S, y); ctx.stroke(); }
      ctx.strokeStyle = '#E47A7A'; ctx.beginPath(); ctx.moveTo(40, 0); ctx.lineTo(40, S); ctx.stroke();
      ctx.fillStyle = '#6B3A6E'; ctx.fillRect(0, 0, S, 22);
      ctx.strokeStyle = '#2F5BD3'; ctx.lineWidth = 2.5; ctx.lineCap = 'round';
      for (let i = 0; i < 5; i++) { ctx.beginPath(); let x = 50; ctx.moveTo(x, 54 + i * 18); while (x < 120 + rand() * 110) { x += 6; ctx.lineTo(x, 54 + i * 18 - (rand() * 6)); } ctx.stroke(); }
    });
    // (0,1) switchboard jack field
    at(0, 1, () => {
      ctx.fillStyle = '#3A2E36'; ctx.fillRect(0, 0, S, S);
      for (let r = 0; r < 5; r++) for (let c = 0; c < 8; c++) {
        const x = 18 + c * 30, y = 26 + r * 46;
        ctx.fillStyle = r % 2 ? '#FFB347' : '#FF6B5A'; ctx.beginPath(); ctx.arc(x + 7, y - 12, 5, 0, TAU); ctx.fill();
        ctx.fillStyle = '#C9CED6'; ctx.beginPath(); ctx.arc(x + 7, y + 6, 9, 0, TAU); ctx.fill();
        ctx.fillStyle = '#120C16'; ctx.beginPath(); ctx.arc(x + 7, y + 6, 5, 0, TAU); ctx.fill();
        ctx.fillStyle = '#F4F1E8'; ctx.fillRect(x - 3, y + 18, 20, 6);
      }
    });
    // (1,1) rolodex / index card
    at(1, 1, () => {
      ctx.fillStyle = '#F7F1E1'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#E23B3B'; ctx.fillRect(0, 38, S, 3);
      ctx.strokeStyle = '#9FC0E8'; ctx.lineWidth = 2;
      for (let y = 70; y < S; y += 26) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(S, y); ctx.stroke(); }
      typed(['DALTON, DUKE', 'PRECINCT 13 SET', 'EXT. 1313'], 14, 30, 34, 18);
    });
    // (2,1) engraved brass nameplate
    at(2, 1, () => {
      const g = ctx.createLinearGradient(0, 0, 0, S); g.addColorStop(0, '#F2CF6A'); g.addColorStop(0.5, '#C8963C'); g.addColorStop(1, '#8A6224');
      ctx.fillStyle = g; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#3A2410'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = font(34, 'Bungee'); ctx.fillText('RECEPTION', 128, 118);
      ctx.font = font(18); ctx.fillText('PLEASE RING', 128, 160);
    });
    // (3,1) WZTV 13 badge: blue disc, red ring, white 13
    at(3, 1, () => {
      ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(128, 128, 128, 0, TAU); ctx.fill();
      ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(128, 128, 118, 0, TAU); ctx.fill();
      ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.arc(128, 128, 96, 0, TAU); ctx.fill();
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillStyle = '#1B2F7A'; ctx.font = font(104, 'Bungee'); ctx.fillText('13', 134, 144);
      ctx.fillStyle = '#F4F1E8'; ctx.fillText('13', 128, 138);
      ctx.fillStyle = '#FFD23A'; ctx.font = font(24, 'Bungee'); ctx.fillText('WZTV', 128, 62);
    });
    // (0,2) ACTION 13 NEWS logo panel
    at(0, 2, () => {
      ctx.fillStyle = '#2A1D3A'; ctx.fillRect(0, 0, S, S);
      ['#E3662B', '#E8A92E', '#F6E7C8'].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(0, 150 + i * 16, S, 10); });
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillStyle = '#E8A92E'; ctx.font = font(44, 'Bungee'); ctx.fillText('ACTION', 128, 52);
      ctx.fillStyle = '#F4F1E8'; ctx.font = font(78, 'Bungee'); ctx.fillText('13', 128, 112);
      ctx.fillStyle = '#F6E7C8'; ctx.font = font(34, 'Bungee'); ctx.fillText('NEWS', 128, 222);
    });
    // (1,2) drawer label cards
    at(1, 2, () => {
      ctx.fillStyle = '#C9CED6'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#FBF6EA'; ctx.fillRect(16, 60, S - 32, S - 120);
      typed(['A - F', 'SCRIPTS'], 60, 118, 40, 30);
    });
    // (2,2) typewriter brand plate
    at(2, 2, () => {
      ctx.fillStyle = '#2A2230'; ctx.fillRect(0, 0, S, S);
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#E8B84A';
      ctx.font = font(52, 'Bungee'); ctx.fillText('SELECTRA', 128, 116);
      ctx.fillStyle = '#C9CED6'; ctx.font = font(22); ctx.fillText('ELECTRIC  72', 128, 162);
    });
    // (3,2) news script page
    at(3, 2, () => {
      ctx.fillStyle = '#FDFBF4'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#7FB4E0'; ctx.fillRect(0, 0, S, 26);
      typed(['ANCHOR (ON CAM):', 'GOOD EVENING. OUR', 'TOP STORY TONIGHT', '... THE AUDIENCE', 'WON\'T LEAVE.', '', 'ROLL TAPE 13-B', '(VTR)  :30'], 16, 50, 22, 14);
      ctx.fillStyle = '#E23B3B'; ctx.fillRect(12, 186, 110, 3);
    });
    // (0,3) mug wrap: harvest gold with the 13 bug
    at(0, 3, () => {
      ctx.fillStyle = '#E8A92E'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#F6E7C8'; ctx.fillRect(0, 26, S, 12); ctx.fillRect(0, S - 38, S, 12);
      ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.arc(64, 128, 46, 0, TAU); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.font = font(50, 'Bungee'); ctx.fillText('13', 64, 134);
    });
    // (1,3) hairspray can label
    at(1, 3, () => {
      const g = ctx.createLinearGradient(0, 0, S, 0); g.addColorStop(0, '#FF5FA2'); g.addColorStop(1, '#C2407A');
      ctx.fillStyle = g; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#FFE3A3'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = font(40, 'Shrikhand'); ctx.fillText('Aqua', 128, 96); ctx.fillText('Hold', 128, 144);
      ctx.fillStyle = '#F4F1E8'; ctx.font = font(16); ctx.fillText('SUPER HOLD', 128, 196);
    });
    // (2,3) keycap letters
    at(2, 3, () => {
      ctx.fillStyle = '#3A2E36'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#F4F1E8'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.font = font(40);
      ctx.fillText('13', 128, 128);
    });
    // (3,3) manila folder
    at(3, 3, () => {
      ctx.fillStyle = '#E8C98A'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#D4B070'; ctx.fillRect(0, 0, S, 30);
      typed(['CONFIDENTIAL'], 40, 140, 20, 22, '#B5472A');
      ctx.strokeStyle = '#B5472A'; ctx.lineWidth = 3; ctx.strokeRect(30, 116, 196, 34);
    });
    void W; void H;
  }, { repeat: false, fonts: true });
}
function drawCard(ctx, id, x, y, w, h) {
  try {
    const tex = getCard(id);
    if (tex && tex.image) ctx.drawImage(tex.image, x, y, w, h);
  } catch (e) { /* card missing: leave the base color */ }
}
const cell = (geo, cx, cy) => K.uvRect(geo.clone(), cx / 4, 1 - (cy + 1) / 4, (cx + 1) / 4, 1 - cy / 4);
const atlasMat = (game) => K.mat(game, 'paint', '#ffffff', { map: deskAtlas() });

// ---------------------------------------------------------------------------- desk items (sub-assemblies)
// Each returns a THREE.Group in its own local space (base at y = 0, front = -z) built from shared materials.
function phoneGroup(game, color = '#E23B3B') {
  const mt = M(game), atl = atlasMat(game);
  const g = new THREE.Group();
  const dark = '#2A2230';
  g.add(K.m(tc(K.box(0.19, 0.022, 0.205, 0.01), dark), mt.plastic, { pos: [0, 0.011, 0.004] }));
  const body = taperS(K.box(0.19, 0.11, 0.2, 0.045), { axis: 'y', k: 0.72 });
  g.add(K.m(tc(body, color), mt.plastic, { pos: [0, 0.075, 0.005] }));
  // sloped dial face
  const face = new THREE.Group();
  face.position.set(0, 0.078, -0.075);
  face.rotation.x = -0.62;
  face.add(K.m(tc(puck(0.062, 0.012, 0.005, 16), color), mt.plastic, { rot: [-Math.PI / 2, 0, 0] }));
  face.add(K.m(cell(new THREE.CircleGeometry(0.054, 24), 0, 0), atl, { pos: [0, 0, -0.0125], rot: [0, Math.PI, 0] }));
  face.add(K.m(tc(puck(0.013, 0.008, 0.003, 12), '#F4F1E8'), mt.plastic, { pos: [0, 0, -0.012], rot: [-Math.PI / 2, 0, 0] }));
  face.add(K.m(K.box(0.006, 0.02, 0.006, 0.002), mt.chrome, { pos: [0.043, -0.038, -0.015], rot: [0, 0, 0.6] }));
  g.add(face);
  // cradle horns + handset
  for (const s of [-1, 1]) g.add(K.m(tc(K.box(0.034, 0.036, 0.056, 0.014), color), mt.plastic, { pos: [s * 0.078, 0.132, 0.01] }));
  const hs = new THREE.Group();
  hs.position.set(0, 0.152, 0.01);
  const cup = K.lathe([[0, 0], [0.028, 0], [0.034, 0.018], [0.03, 0.03], [0, 0.03]], { seg: 12, round: 0.006, steps: 1 });
  hs.add(K.m(tc(K.tube([[-0.1, -0.012, 0], [-0.06, 0.012, 0], [0.06, 0.012, 0], [0.1, -0.012, 0]], 0.016, { seg: 10, radial: 7 }), color), mt.plastic));
  for (const s of [-1, 1]) hs.add(K.m(tc(cup, color), mt.plastic, { pos: [s * 0.1, -0.012, 0], rot: [0, 0, Math.PI], scale: [1, 1, 1] }));
  g.add(hs);
  // coiled cord from the handset end down to the body side
  const pts = [];
  for (let i = 0; i <= 60; i++) {
    const t = i / 60, a = t * TAU * 9;
    const base = [lerp(-0.1, -0.12, t), lerp(0.13, 0.03, Math.sin(t * Math.PI * 0.5)), lerp(0.02, -0.06, t) - Math.sin(t * Math.PI) * 0.06];
    pts.push([base[0] + Math.cos(a) * 0.008 - 0.012, base[1] + Math.sin(a) * 0.008, base[2]]);
  }
  g.add(K.m(tc(K.tube(pts, 0.0035, { seg: 48, radial: 3 }), color), mt.plastic));
  return g;
}

function typewriterGroup(game, color = '#E8A92E') {
  const mt = M(game), atl = atlasMat(game);
  const g = new THREE.Group();
  const dark = '#2E2630', deep = new THREE.Color(color).multiplyScalar(0.7).getStyle();
  // chunky body: lower tray + domed hood
  g.add(K.m(tc(K.box(0.46, 0.08, 0.38, 0.035), color), mt.plastic, { pos: [0, 0.05, 0] }));
  g.add(K.m(tc(taperS(K.box(0.44, 0.09, 0.2, 0.04), { axis: 'y', k: 0.82 }), color), mt.plastic, { pos: [0, 0.125, 0.07] }));
  g.add(K.m(tc(K.box(0.44, 0.012, 0.36, 0.005), dark), mt.plastic, { pos: [0, 0.006, 0] }));
  // keyboard well
  g.add(K.m(tc(K.box(0.4, 0.03, 0.15, 0.012), dark), mt.plastic, { pos: [0, 0.085, -0.105], rot: [0.2, 0, 0] }));
  const key = cg('tw_key', () => K.lathe([[0, 0], [0.0128, 0], [0.012, 0.015], [0, 0.017]], { seg: 7 }));
  const rows = [[10, 0], [9, 0.01], [8, 0.02]];
  rows.forEach(([n, off], r) => {
    for (let i = 0; i < n; i++) {
      const x = (i - (n - 1) / 2) * 0.034 + off * 0.2, z = -0.155 + r * 0.035, y = 0.09 + r * 0.008;
      g.add(K.m(tc(key, (i + r) % 7 === 3 ? '#E23B3B' : '#F4F1E8'), mt.plastic, { pos: [x, y, z], rot: [0.2, 0, 0] }));
    }
  });
  g.add(K.m(tc(K.box(0.2, 0.014, 0.024, 0.006), '#F4F1E8'), mt.plastic, { pos: [0, 0.088, -0.19], rot: [0.2, 0, 0] }));
  // platen, knobs, paper, return lever, brand plate
  g.add(K.m(tc(K.cyl(0.028, 0.028, 0.42, { seg: 14 }), dark), mt.plastic, { pos: [-0.21, 0.185, 0.1], rot: [0, 0, -Math.PI / 2] }));
  for (const s of [-1, 1]) g.add(K.m(tc(K.lathe([[0, 0], [0.024, 0], [0.028, 0.012], [0.024, 0.028], [0, 0.03]], { seg: 12, round: 0.004, steps: 1 }), dark), mt.plastic, { pos: [s * 0.21, 0.185, 0.1], rot: [0, 0, -s * Math.PI / 2] }));
  g.add(K.m(K.tint(cell(cbox(0.24, 0.26, 0.003, 0.001), 1, 0), '#D8D0C0'), atl, { pos: [0, 0.3, 0.115], rot: [-0.18, 0, 0.02] }));
  g.add(K.m(K.tube([[-0.23, 0.2, 0.06], [-0.27, 0.23, 0.03], [-0.29, 0.25, -0.02]], 0.006, { seg: 8, radial: 5 }), mt.chrome));
  g.add(K.m(K.cyl(0.012, 0.012, 0.02, { seg: 8 }), mt.chrome, { pos: [-0.29, 0.24, -0.02], rot: [0, 0, 0.4] }));
  g.add(K.m(cell(cbox(0.14, 0.03, 0.004, 0.001), 2, 2), atl, { pos: [0, 0.15, -0.035], rot: [-0.55, 0, 0] }));
  g.add(K.m(tc(K.box(0.44, 0.02, 0.05, 0.009), deep), mt.plastic, { pos: [0, 0.172, -0.02] }));
  return g;
}

function paperStack(game, n = 5, seed = 1, cellXY = [1, 0]) {
  const atl = atlasMat(game);
  const rnd = mulberry32(seed * 977 + 3);
  const g = new THREE.Group();
  for (let i = 0; i < n; i++) {
    const top = i === n - 1;
    const sh = K.m(cell(cbox(0.22, 0.004, 0.28, 0.0012), ...(top ? cellXY : [1, 2])), atl, { pos: [(rnd() - 0.5) * 0.012, 0.002 + i * 0.0045, (rnd() - 0.5) * 0.012], rot: [0, (rnd() - 0.5) * 0.12, 0] });
    if (!top) sh.geometry = K.tint(sh.geometry.clone(), '#F4EEDC');
    g.add(sh);
  }
  return g;
}

function mugGroup(game) {
  const atl = atlasMat(game), mt = M(game);
  const g = new THREE.Group();
  g.add(K.m(cell(K.lathe([[0, 0], [0.036, 0], [0.04, 0.005], [0.04, 0.09], [0.036, 0.092], [0.034, 0.02], [0, 0.02]], { seg: 16 }), 0, 3), atl));
  g.add(K.m(tc(new THREE.TorusGeometry(0.024, 0.007, 6, 12, Math.PI * 1.2), '#E8A92E'), mt.plastic, { pos: [0.04, 0.048, 0], rot: [0, 0, -Math.PI * 0.6] }));
  g.add(K.m(tc(new THREE.CircleGeometry(0.034, 14), '#3A2014'), mt.plastic, { pos: [0, 0.075, 0], rot: [-Math.PI / 2, 0, 0] }));
  return g;
}

function pencilCup(game) {
  const mt = M(game);
  const g = new THREE.Group();
  g.add(K.m(tc(K.lathe([[0, 0], [0.034, 0], [0.036, 0.1], [0.032, 0.1], [0.03, 0.01], [0, 0.01]], { seg: 14 }), '#8C9A3A'), mt.plastic));
  const cols = ['#F4E03A', '#F4E03A', '#E23B3B', '#2F5BD3'];
  cols.forEach((c, i) => {
    const a = i * 1.7;
    const p0 = [Math.cos(a) * 0.012, 0.01, Math.sin(a) * 0.012], p1 = [Math.cos(a) * 0.03, 0.17 + i * 0.01, Math.sin(a) * 0.03];
    g.add(rod(0.004, p0, p1, mt.paint, { color: c, seg: 6, bevel: 0.001 }));
    g.add(K.m(tc(K.cyl(0.0042, 0.0042, 0.01, { seg: 6, bevel: 0.001 }), '#FF8FA8'), mt.paint, { pos: p1 }));
  });
  return g;
}

function deskBell(game) {
  const mt = M(game);
  const g = new THREE.Group();
  g.add(K.m(tc(puck(0.05, 0.016, 0.005, 16), '#2A2230'), mt.plastic));
  g.add(K.m(K.lathe([[0, 0], [0.046, 0], [0.044, 0.012], [0.034, 0.03], [0.018, 0.042], [0, 0.045]], { seg: 18, round: 0.006 }), mt.chrome, { pos: [0, 0.016, 0] }));
  g.add(K.m(K.cyl(0.004, 0.004, 0.012, { seg: 6 }), mt.chrome, { pos: [0, 0.06, 0] }));
  g.add(K.m(K.lathe([[0, 0], [0.008, 0], [0.009, 0.004], [0, 0.007]], { seg: 10 }), mt.chrome, { pos: [0, 0.071, 0] }));
  return g;
}

function magazine(game) {
  const atl = atlasMat(game);
  const g = new THREE.Group();
  g.add(K.m(cell(cbox(0.21, 0.006, 0.28, 0.0015), 2, 0), atl, { pos: [0, 0.003, 0] }));
  return g;
}

function deskMic(game) {
  const mt = M(game);
  const g = new THREE.Group();
  g.add(K.m(tc(puck(0.06, 0.02, 0.008, 16), '#2A2230'), mt.plastic));
  g.add(K.m(K.tube([[0, 0.02, 0], [0, 0.1, 0], [0, 0.18, -0.03], [0, 0.22, -0.09]], 0.006, { seg: 12, radial: 6 }), mt.chrome));
  const cap = new THREE.Group();
  cap.position.set(0, 0.225, -0.1);
  cap.rotation.x = -1.1;
  cap.add(K.m(K.lathe([[0, 0], [0.014, 0], [0.022, 0.03], [0.022, 0.06], [0.016, 0.08], [0, 0.082]], { seg: 12, round: 0.005 }), mt.chrome));
  cap.add(K.m(tc(K.lathe([[0, 0], [0.0225, 0], [0.0225, 0.022], [0, 0.022]], { seg: 12 }), '#2A2230'), mt.plastic, { pos: [0, 0.034, 0] }));
  g.add(cap);
  return g;
}

function hairspray(game) {
  const atl = atlasMat(game), mt = M(game);
  const g = new THREE.Group();
  g.add(K.m(cell(K.lathe([[0, 0], [0.026, 0], [0.028, 0.006], [0.028, 0.15], [0.024, 0.16], [0, 0.162]], { seg: 14 }), 1, 3), atl));
  g.add(K.m(tc(K.lathe([[0, 0], [0.02, 0], [0.022, 0.03], [0.016, 0.042], [0, 0.044]], { seg: 12, round: 0.004 }), '#F4F1E8'), mt.plastic, { pos: [0, 0.16, 0] }));
  return g;
}

function put(g, sub, pos, rotY = 0, rot = null) {
  sub.position.set(pos[0], pos[1], pos[2]);
  if (rot) sub.rotation.set(rot[0], rot[1], rot[2]); else sub.rotation.y = rotY;
  g.add(sub);
  return sub;
}

// ------------------------------------------------------------------------------------------ rotary phone
registerProp('phone_rotary', (game, opts = {}) => {
  const g = K.prop('phone_rotary');
  g.add(phoneGroup(game, opts.color ?? '#E23B3B'));
  g.userData.colliders = [];
  g.userData.interact = { point: [0, 0.12, -0.12], radius: 1 };
  return K.finish(game, g, { ao: { height: 0.02 } });
}, { category: CAT, tags: ['tabletop', 'phone', 'newsroom', 'lobby'], size: [0.24, 0.17, 0.24], desc: 'rotary desk phone with printed dial, handset and coiled cord (opts.color)' });

// --------------------------------------------------------------------------------------------- typewriter
registerProp('typewriter', (game, opts = {}) => {
  const g = K.prop('typewriter');
  g.add(typewriterGroup(game, opts.color ?? '#E8A92E'));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { height: 0.02 } });
}, { category: CAT, tags: ['tabletop', 'newsroom'], size: [0.6, 0.44, 0.4], desc: 'chunky 70s electric typewriter, round keys, typed sheet in the platen (opts.color)' });

// ------------------------------------------------------------------------------------------ reporter desk
registerProp('desk_reporter', (game, opts = {}) => {
  const g = K.prop('desk_reporter');
  const mt = M(game), atl = atlasMat(game);
  const steel = opts.color ?? '#8FA38A';
  const W = 1.5, D = 0.76, H = 0.76;
  const lam = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood('#A8743F', { dark: 0.3 }) });
  // top: wood-grain laminate over a brushed aluminum edge band
  g.add(K.m(K.box(W, 0.034, D, 0.012, { uv: 1.2, swap: true }), lam, { pos: [0, H - 0.017, 0] }));
  g.add(K.m(K.box(W + 0.012, 0.022, D + 0.012, 0.008), mt.chrome, { pos: [0, H - 0.04, 0] }));
  // steel carcass: right pedestal (3 drawers), left end panel, modesty panel, pencil drawer
  const pw = 0.44, px = W / 2 - pw / 2 - 0.01;
  g.add(K.m(tc(K.box(pw, H - 0.1, D - 0.04, 0.02), steel), mt.paint, { pos: [px, (H - 0.1) / 2 + 0.05, 0] }));
  g.add(K.m(tc(K.box(0.05, H - 0.1, D - 0.04, 0.02), steel), mt.paint, { pos: [-W / 2 + 0.035, (H - 0.1) / 2 + 0.05, 0] }));
  g.add(K.m(tc(K.box(W - pw - 0.08, 0.42, 0.025, 0.01), steel), mt.paint, { pos: [-pw / 2 + 0.01, H - 0.3, D / 2 - 0.05] }));
  g.add(K.m(tc(K.box(W - 0.06, 0.012, D - 0.1, 0.004), '#3A2E36'), mt.paint, { pos: [0, H - 0.052, 0] }));
  const dark = new THREE.Color(steel).multiplyScalar(0.55).getStyle();
  // recessed plinths
  g.add(K.m(tc(K.box(pw - 0.04, 0.05, D - 0.1, 0.01), dark), mt.paint, { pos: [px, 0.025, 0] }));
  g.add(K.m(tc(K.box(0.04, 0.05, D - 0.1, 0.01), dark), mt.paint, { pos: [-W / 2 + 0.035, 0.025, 0] }));
  // drawers: raised fronts + chrome pulls + label cards
  const dh = [0.16, 0.16, 0.28];
  let y = H - 0.07;
  dh.forEach((h, i) => {
    y -= h / 2 + 0.006;
    g.add(K.m(tc(K.box(pw - 0.03, h - 0.012, 0.03, 0.012), steel), mt.paint, { pos: [px, y, -D / 2 + 0.01] }));
    g.add(K.m(K.tube([[-0.07, 0, 0], [-0.065, 0, -0.02], [0.065, 0, -0.02], [0.07, 0, 0]], 0.007, { seg: 8, radial: 5 }), mt.chrome, { pos: [px, y + h * 0.18, -D / 2 - 0.004] }));
    g.add(K.m(cell(cbox(0.07, 0.03, 0.004, 0.001), 1, 2), atl, { pos: [px, y - h * 0.12, -D / 2 - 0.007] }));
    y -= h / 2 + 0.006;
  });
  // pencil drawer
  g.add(K.m(tc(K.box(W - pw - 0.14, 0.07, 0.03, 0.012), steel), mt.paint, { pos: [-pw / 2 - 0.02, H - 0.09, -D / 2 + 0.01] }));
  g.add(K.m(K.tube([[-0.06, 0, 0], [-0.055, 0, -0.018], [0.055, 0, -0.018], [0.06, 0, 0]], 0.006, { seg: 8, radial: 5 }), mt.chrome, { pos: [-pw / 2 - 0.02, H - 0.09, -D / 2 - 0.004] }));
  // on top: typewriter, phone, papers, legal pad, mug, pencil cup, manila folder, script spike
  const top = H;
  put(g, typewriterGroup(game, opts.typewriter ?? '#E8A92E'), [-0.2, top, -0.04], 0.08);
  put(g, phoneGroup(game, opts.phone ?? '#F4F1E8'), [0.52, top, -0.12], -0.35);
  put(g, paperStack(game, 6, 2), [0.18, top, 0.14], Math.PI + 0.25);
  put(g, paperStack(game, 3, 5, [3, 3]), [0.5, top, 0.2], Math.PI - 0.1);
  g.add(K.m(cell(cbox(0.2, 0.012, 0.28, 0.002), 3, 0), atl, { pos: [0.2, top + 0.006, -0.2], rot: [0, -0.4, 0] }));
  put(g, mugGroup(game), [-0.6, top, 0.18], 2.2);
  put(g, pencilCup(game), [-0.62, top, -0.02], 0);
  g.add(K.m(K.cyl(0.028, 0.03, 0.008, { seg: 12 }), mt.chrome, { pos: [0.66, top, 0.25] }));
  g.add(K.m(K.cyl(0.0018, 0.0018, 0.13, { seg: 5, bevel: 0.0008 }), mt.chrome, { pos: [0.66, top + 0.008, 0.25] }));
  for (let i = 0; i < 3; i++) g.add(K.m(cell(cbox(0.1, 0.002, 0.12, 0.0008), 1, 1), atl, { pos: [0.66, top + 0.03 + i * 0.02, 0.25], rot: [0, i * 0.5, 0] }));
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, H + 0.05, D / 2] }];
  g.userData.interact = null;
  return K.finish(game, g);
}, { category: CAT, tags: ['desk', 'newsroom'], size: [1.5, 1.1, 0.76], desc: 'sage steel tanker desk, wood-grain top: typewriter, rotary phone, papers, legal pad, mug (opts.color/typewriter/phone)', hero: true });

// --------------------------------------------------------------------------------------- reception desk
// arcs convex toward -z: P(a, r) = [sin a * r, cz - cos a * r]; sector slab extruded vertically
function arcSector(r0, r1, a0, a1, cz, steps = 28) {
  const pts = [];
  for (let i = 0; i <= steps; i++) { const a = lerp(a0, a1, i / steps); pts.push([Math.sin(a) * r1, -(cz - Math.cos(a) * r1)]); }
  for (let i = steps; i >= 0; i--) { const a = lerp(a0, a1, i / steps); pts.push([Math.sin(a) * r0, -(cz - Math.cos(a) * r0)]); }
  return pts;
}
function arcSlab(r0, r1, a0, a1, cz, y0, h, o = {}) {
  const geo = K.extrude(arcSector(r0, r1, a0, a1, cz, o.steps ?? 24), h, { bevel: o.bevel ?? 0.01, round: 0, uv: o.uv ?? 1.2, curveSeg: 4, bevelSeg: o.bevelSeg ?? 2 });
  geo.rotateX(-Math.PI / 2);
  geo.translate(0, y0 + h / 2, 0);
  return geo;
}
const arcP = (a, r, cz, y = 0) => [Math.sin(a) * r, y, cz - Math.cos(a) * r];
// colliders for a convex-front arc desk: n boxes across x, each from the arc front at its inner edge to zBack
function arcColliders(Ro, cz, xMax, zBack, h, n = 5) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const x0 = lerp(-xMax, xMax, i / n), x1 = lerp(-xMax, xMax, (i + 1) / n);
    const xi = Math.min(Math.abs(x0), Math.abs(x1)) * (x0 * x1 < 0 ? 0 : 1);
    const zf = cz - Math.sqrt(Math.max(0, Ro * Ro - xi * xi));
    out.push({ min: [+x0.toFixed(3), 0, +zf.toFixed(3)], max: [+x1.toFixed(3), h, +zBack.toFixed(3)] });
  }
  return out;
}

registerProp('desk_reception', (game, opts = {}) => {
  const g = K.prop('desk_reception');
  const mt = M(game), atl = atlasMat(game);
  const orange = opts.top ?? '#E3662B';
  const Ro = 4.0, cz = 3.43, am = Math.asin(1.8 / Ro);
  // recessed dark plinth + brass kick rail
  g.add(K.m(tc(arcSlab(Ro - 0.7, Ro - 0.08, -am, am, cz, 0, 0.08, { bevelSeg: 1, steps: 16 }), '#3A2418'), mt.lacquer));
  g.add(K.m(K.tube(Array.from({ length: 25 }, (_, i) => arcP(lerp(-am, am, i / 24), Ro - 0.07, cz, 0.05)), 0.012, { seg: 36, radial: 5 }), mt.brass));
  // walnut front skin
  g.add(K.m(arcSlab(Ro - 0.07, Ro - 0.01, -am, am, cz, 0.08, 0.9, { bevel: 0.008, uv: 0.8, bevelSeg: 1, steps: 16 }), mt.walnut));
  // vertical walnut ribs (fluted front)
  const nR = 26;
  for (let i = 0; i < nR; i++) {
    const a = lerp(-am + 0.02, am - 0.02, (i + 0.5) / nR);
    if (Math.abs(a) < 0.07) continue; // badge
    const rib = K.m(K.uvScale(cbox(0.07, 0.8, 0.035, 0.012).clone(), 0.1, 1.2), mt.walnut);
    rib.position.set(...arcP(a, Ro + 0.005, cz, 0.12 + 0.4));
    rib.rotation.y = -a;
    g.add(rib);
  }
  // orange accent band + bullnose laminate counter
  g.add(K.m(tc(arcSlab(Ro - 0.02, Ro + 0.035, -am, am, cz, 0.93, 0.07, { bevel: 0.012 }), '#B5472A'), mt.lacquer));
  g.add(K.m(tc(arcSlab(Ro - 0.36, Ro + 0.06, -am - 0.004, am + 0.004, cz, 1.0, 0.055, { bevel: 0.02, bevelSeg: 2 }), orange), mt.lacquer));
  // step riser + lower work surface behind (receptionist side)
  g.add(K.m(arcSlab(Ro - 0.37, Ro - 0.31, -am, am, cz, 0.72, 0.28, { bevel: 0.006, uv: 0.8, bevelSeg: 1, steps: 16 }), mt.walnut));
  g.add(K.m(tc(arcSlab(Ro - 0.86, Ro - 0.06, -am, am, cz, 0.7, 0.04, { bevel: 0.012 }), '#F0A060'), mt.lacquer));
  // drawer pedestals under the work surface
  for (const s of [-1, 1]) {
    const a = s * (am - 0.12);
    const ped = K.m(K.box(0.42, 0.62, 0.5, 0.014, { uv: 1.2, swap: true }), mt.walnut);
    ped.position.set(...arcP(a, Ro - 0.5, cz, 0.39));
    ped.rotation.y = -a;
    g.add(ped);
    for (let k = 0; k < 3; k++) {
      const pull = K.m(K.box(0.12, 0.018, 0.02, 0.008), mt.brass);
      pull.position.set(...arcP(a, Ro - 0.5 + 0.26, cz, 0.62 - k * 0.19));
      pull.rotation.y = -a;
      g.add(pull);
    }
  }
  // rounded end drums: walnut with orange caps
  for (const s of [-1, 1]) {
    const p = arcP(s * am, Ro - 0.2, cz);
    g.add(K.m(K.uvScale(K.cyl(0.21, 0.19, 1.0, { seg: 20, bevel: 0.02 }).clone(), 2, 1), mt.walnut, { pos: [p[0], 0, p[2]] }));
    g.add(K.m(tc(puck(0.235, 0.055, 0.02, 20), orange), mt.lacquer, { pos: [p[0], 1.0, p[2]] }));
  }
  // WZTV 13 badge on the front
  const bp = arcP(0, Ro + 0.03, cz, 0.56);
  g.add(K.m(tc(puck(0.25, 0.04, 0.015, 24), '#F4F1E8'), mt.lacquer, { pos: bp, rot: [Math.PI / 2, 0, 0] }));
  g.add(K.m(cell(new THREE.CircleGeometry(0.235, 32), 3, 1), atl, { pos: [bp[0], bp[1], bp[2] - 0.041], rot: [0, Math.PI, 0] }));
  // counter items: bell (toy), TV WEEKLY (Baron), nameplate, pen on a chain, sign-in pad
  const cy = 1.055;
  const bell = put(g, deskBell(game), arcP(0.12, Ro - 0.15, cz, cy), 0);
  bell.userData.noMerge = true;
  const mag = put(g, magazine(game), arcP(-0.2, Ro - 0.17, cz, cy), 0.35);
  mag.userData.noMerge = true;
  const np = K.m(cell(taperS(K.box(0.3, 0.07, 0.05, 0.008), { axis: 'y', k: 0.5 }), 2, 1), atl);
  np.position.set(...arcP(-0.02, Ro - 0.1, cz, cy + 0.035));
  np.rotation.set(0, 0, 0);
  g.add(np);
  g.add(K.m(cell(cbox(0.24, 0.01, 0.18, 0.002), 1, 1), atl, { pos: arcP(0.26, Ro - 0.16, cz, cy + 0.005), rot: [0, 0.2, 0] }));
  g.add(K.m(K.tube([arcP(0.3, Ro - 0.2, cz, cy + 0.01), arcP(0.31, Ro - 0.1, cz, cy + 0.02), arcP(0.33, Ro - 0.15, cz, cy + 0.012)], 0.003, { seg: 8, radial: 4 }), mt.chrome));
  // work surface: switchboard, phone, rolodex, mug
  const wy = 0.74;
  const sb = new THREE.Group();
  sb.add(K.m(tc(K.box(0.62, 0.1, 0.36, 0.02), '#6B5A4A'), mt.plastic, { pos: [0, 0.05, 0] }));
  const panel = new THREE.Group(); panel.position.set(0, 0.2, 0.12); panel.rotation.x = 0.5;
  panel.add(K.m(tc(K.box(0.62, 0.26, 0.08, 0.02), '#6B5A4A'), mt.plastic));
  panel.add(K.m(cell(cbox(0.56, 0.22, 0.004, 0.001), 0, 1), atl, { pos: [0, 0, -0.042], rot: [0, 0, 0] }));
  sb.add(panel);
  sb.add(K.m(tc(K.box(0.56, 0.02, 0.18, 0.008), '#2A2230'), mt.plastic, { pos: [0, 0.11, -0.07] }));
  const cords = [['#E23B3B', -0.2], ['#F4E03A', -0.08], ['#2F5BD3', 0.05], ['#52D24A', 0.18]];
  for (const [c, x] of cords) {
    sb.add(K.m(tc(K.tube([[x, 0.13, -0.1], [x + 0.02, 0.2, -0.16], [x * 0.6, 0.26, -0.02], [x * 0.5, 0.25, 0.08]], 0.005, { seg: 10, radial: 4 }), c), mt.plastic));
    sb.add(K.m(tc(K.cyl(0.009, 0.009, 0.03, { seg: 8 }), c), mt.plastic, { pos: [x, 0.12, -0.1] }));
  }
  put(g, sb, arcP(-0.24, Ro - 0.6, cz, wy), 0.24 + Math.PI);
  const phone = put(g, phoneGroup(game, '#F6E7C8'), arcP(0.05, Ro - 0.62, cz, wy), Math.PI - 0.1);
  void phone;
  const rolo = new THREE.Group();
  rolo.add(K.m(tc(K.box(0.16, 0.03, 0.12, 0.01), '#2A2230'), mt.plastic, { pos: [0, 0.015, 0] }));
  for (let i = 0; i < 9; i++) rolo.add(K.m(cell(cbox(0.12, 0.08, 0.002, 0.0008), 1, 1), atl, { pos: [0, 0.075, -0.04 + i * 0.01], rot: [-0.5 + i * 0.12, 0, 0] }));
  rolo.add(K.m(K.tube([[-0.07, 0.03, 0], [-0.07, 0.09, 0], [0.07, 0.09, 0], [0.07, 0.03, 0]], 0.004, { seg: 10, radial: 4 }), mt.chrome));
  put(g, rolo, arcP(0.24, Ro - 0.6, cz, wy), Math.PI - 0.24);
  put(g, mugGroup(game), arcP(0.36, Ro - 0.72, cz, wy), 1.2);
  g.userData.parts = { bell, magazine: mag };
  const zf = cz - Ro - 0.06, zb = cz - Math.cos(am) * (Ro - 0.86);
  void zf;
  g.userData.colliders = arcColliders(Ro + 0.06, cz, 2.0, zb, 1.1, 5);
  g.userData.interact = { point: arcP(0.12, Ro - 0.15, cz, 1.1), radius: 1.2 };
  return K.finish(game, g);
}, { category: CAT, tags: ['desk', 'lobby', 'reception'], size: [4.0, 1.1, 1.15], desc: 'curved walnut reception desk: fluted front, orange laminate counter, WZTV 13 badge, switchboard, bell (parts.bell), TV WEEKLY (parts.magazine)', hero: true });

// ------------------------------------------------------------------------------------------- anchor desk
registerProp('desk_anchor', (game, opts = {}) => {
  const g = K.prop('desk_anchor');
  const mt = M(game), atl = atlasMat(game);
  const Ro = 3.6, cz = Ro - 0.42, am = Math.asin(1.3 / Ro);
  const brown = '#5A3A22';
  // recessed kick + chocolate front + racing stripes
  g.add(K.m(tc(arcSlab(Ro - 0.62, Ro - 0.1, -am, am, cz, 0, 0.07), '#2A1C14'), mt.lacquer));
  g.add(K.m(tc(arcSlab(Ro - 0.08, Ro, -am, am, cz, 0.07, 0.68, { bevel: 0.012 }), brown), mt.lacquer));
  ['#E3662B', '#E8A92E', '#B5472A'].forEach((c, i) => g.add(K.m(tc(arcSlab(Ro - 0.01, Ro + 0.016, -am, am, cz, 0.44 + i * 0.075, 0.05, { bevel: 0.01 }), c), mt.lacquer)));
  // back modesty panel (anchors' knees side stays open) + walnut bullnose top with a cream inset
  g.add(K.m(arcSlab(Ro - 0.7, Ro + 0.05, -am - 0.006, am + 0.006, cz, 0.75, 0.06, { bevel: 0.024, bevelSeg: 3, uv: 1.1 }), mt.walnut));
  g.add(K.m(tc(arcSlab(Ro - 0.55, Ro - 0.12, -am + 0.05, am - 0.05, cz, 0.806, 0.006, { bevel: 0.002 }), '#F6E7C8'), mt.paint));
  // rounded orange end drums
  for (const s of [-1, 1]) {
    const p = arcP(s * am, Ro - 0.33, cz);
    g.add(K.m(tc(K.cyl(0.3, 0.3, 0.75, { seg: 28, bevel: 0.02 }), '#E3662B'), mt.lacquer, { pos: [p[0], 0.0, p[2]] }));
    g.add(K.m(tc(K.cyl(0.27, 0.27, 0.07, { seg: 28 }), '#2A1C14'), mt.lacquer, { pos: [p[0], 0, p[2]] }));
    g.add(K.m(puck(0.33, 0.06, 0.024, 28), mt.walnut, { pos: [p[0], 0.75, p[2]] }));
  }
  // ACTION 13 NEWS logo panel (proud, rounded)
  const lp = arcP(0, Ro + 0.035, cz, 0.43);
  g.add(K.m(tc(K.box(0.66, 0.52, 0.05, 0.05), '#E8A92E'), mt.lacquer, { pos: lp }));
  g.add(K.m(cell(cbox(0.58, 0.44, 0.01, 0.003), 0, 2), atl, { pos: [lp[0], lp[1], lp[2] - 0.026] }));
  // desk dressing: scripts, mic, mug, pencil, toppled hairspray (parts.hairspray)
  const ty = 0.812;
  put(g, paperStack(game, 5, 7, [3, 2]), arcP(-0.12, Ro - 0.35, cz, ty), 0.1);
  put(g, paperStack(game, 3, 9, [3, 2]), arcP(0.16, Ro - 0.38, cz, ty), -0.2);
  put(g, deskMic(game), arcP(-0.02, Ro - 0.3, cz, ty), Math.PI);
  put(g, mugGroup(game), arcP(0.3, Ro - 0.5, cz, ty), 2.4);
  g.add(rod(0.0035, arcP(0.02, Ro - 0.44, cz, ty + 0.004), arcP(0.07, Ro - 0.42, cz, ty + 0.004), mt.paint, { color: '#F4E03A', seg: 6, bevel: 0.001 }));
  const hs = put(g, hairspray(game), arcP(-0.3, Ro - 0.42, cz, ty + 0.028), 0, [0, 0.7, Math.PI / 2]);
  hs.userData.noMerge = true;
  g.userData.parts = { hairspray: hs };
  const zf = cz - Ro - 0.06, zb = cz - Math.cos(am) * (Ro - 0.7) + 0.02;
  void zf;
  g.userData.colliders = arcColliders(Ro + 0.05, cz, 1.55, zb, 0.9, 5);
  return K.finish(game, g);
}, { category: CAT, tags: ['desk', 'newsroom', 'anchor'], size: [3.2, 0.9, 1.1], desc: 'curved chocolate anchor desk, orange/gold racing stripes, ACTION 13 NEWS panel, mic, scripts, toppled hairspray (parts.hairspray)', hero: true });

// ------------------------------------------------------------------------------------ surfboard coffee table
function surfShape(w, d, n = 28) {
  const pts = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * TAU;
    const c = Math.cos(a), s = Math.sin(a);
    const x = Math.sign(c) * Math.pow(Math.abs(c), 0.7) * w / 2, y = Math.sign(s) * Math.pow(Math.abs(s), 0.85) * d / 2;
    pts.push([x, y]);
  }
  return pts;
}
registerProp('table_coffee', (game) => {
  const g = K.prop('table_coffee');
  const mt = M(game);
  const W = 1.3, D = 0.6, H = 0.4;
  // surfboard top: teak lacquer slab over a darker walnut lip
  const top = K.extrude(surfShape(W, D), 0.04, { bevel: 0.014, uv: 1.4, bevelSeg: 2 });
  top.rotateX(-Math.PI / 2);
  g.add(K.m(top, mt.teak, { pos: [0, H - 0.02, 0] }));
  const lip = K.extrude(surfShape(W - 0.06, D - 0.06, 24), 0.03, { bevel: 0.008, uv: 1.4, bevelSeg: 1 });
  lip.rotateX(-Math.PI / 2);
  g.add(K.m(tc(lip, '#6A4428'), mt.teak, { pos: [0, H - 0.05, 0] }));
  // splayed tapered legs with brass ferrules
  for (const [sx, sz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    const tx = sx * 0.4, tz = sz * 0.16, fx = sx * 0.47, fz = sz * 0.22;
    g.add(rod(0.024, [fx, 0.02, fz], [tx, H - 0.05, tz], mt.teak, { rb: 0.014, seg: 10 }));
    g.add(K.m(new THREE.CylinderGeometry(0.015, 0.016, 0.03, 8, 1).translate(0, 0.015, 0), mt.brass, { pos: [fx, 0, fz] }));
  }
  // slatted magazine shelf
  for (let i = 0; i < 5; i++) g.add(K.m(K.uvScale(cbox(0.84, 0.018, 0.06, 0.005).clone(), 1, 0.2), mt.teak, { pos: [0, 0.16, -0.14 + i * 0.07] }));
  for (const s of [-1, 1]) g.add(K.m(K.box(0.04, 0.03, 0.4, 0.01, { uv: 1.4, swap: true }), mt.teak, { pos: [s * 0.4, 0.14, 0] }));
  // dressing: magazines on the shelf, orange glass ashtray, gold bowl of wax fruit
  put(g, magazine(game), [-0.18, 0.169, 0.02], 0.3);
  put(g, magazine(game), [-0.14, 0.175, 0.0], -0.2);
  g.add(K.m(tc(K.lathe([[0, 0], [0.07, 0], [0.085, 0.03], [0.07, 0.032], [0.05, 0.012], [0, 0.012]], { seg: 14, round: 0.006, steps: 1 }), '#E3662B'), mt.lacquer, { pos: [0.38, H, 0.08] }));
  g.add(K.m(tc(K.lathe([[0, 0], [0.05, 0], [0.13, 0.06], [0.14, 0.075], [0.125, 0.07], [0.04, 0.012], [0, 0.012]], { seg: 16, round: 0.006, steps: 1 }), '#E8A92E'), mt.lacquer, { pos: [-0.2, H, -0.02] }));
  for (const [x, z, r, c] of [[-0.23, -0.03, 0.045, '#E23B3B'], [-0.16, 0.0, 0.042, '#FF8A2A'], [-0.2, 0.04, 0.04, '#F4E03A']]) {
    g.add(K.m(tc(sph(r, 10, 7), c), mt.lacquer, { pos: [x, H + 0.05, z] }));
  }
  const grapes = [[-0.14, -0.05], [-0.12, -0.03], [-0.15, -0.02], [-0.13, -0.065]];
  grapes.forEach(([x, z], i) => g.add(K.m(tc(sph(0.016, 6, 4), '#6B3A6E'), mt.lacquer, { pos: [x, H + 0.075 + (i % 2) * 0.01, z] })));
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, H + 0.05, D / 2] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['table', 'lobby', 'green_room', 'telly_home'], size: [1.3, 0.48, 0.6], desc: 'teak surfboard coffee table, splayed legs, slatted magazine shelf, ashtray + wax-fruit bowl' });

// ------------------------------------------------------------------------------------------ tulip side table
registerProp('table_side_tulip', (game, opts = {}) => {
  const g = K.prop('table_side_tulip');
  const mt = M(game);
  const col = opts.color ?? '#D4521E';
  g.add(K.m(tc(K.lathe([[0, 0], [0.24, 0], [0.245, 0.02], [0.2, 0.05], [0.08, 0.12], [0.045, 0.24], [0.04, 0.4], [0.07, 0.48], [0.1, 0.5], [0, 0.5]], { round: 0.02, seg: 28 }), '#F4F1E8'), mt.lacquer));
  g.add(K.m(tc(puck(0.3, 0.035, 0.012, 32), '#F4F1E8'), mt.lacquer, { pos: [0, 0.5, 0] }));
  g.add(K.m(tc(new THREE.CircleGeometry(0.28, 32), col), mt.paint, { pos: [0, 0.536, 0], rot: [-Math.PI / 2, 0, 0] }));
  g.userData.colliders = [{ min: [-0.3, 0, -0.3], max: [0.3, 0.54, 0.3] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['table', 'lobby', 'green_room'], size: [0.6, 0.54, 0.6], desc: 'space-age white tulip side table with an orange laminate top (opts.color)' });

// ------------------------------------------------------------------------------------------ drum side table
registerProp('table_side_drum', (game) => {
  const g = K.prop('table_side_drum');
  const mt = M(game);
  g.add(K.m(K.uvScale(K.lathe([[0, 0], [0.2, 0], [0.225, 0.08], [0.235, 0.24], [0.225, 0.4], [0.2, 0.48], [0, 0.48]], { round: 0.015, seg: 24 }).clone(), 3, 1.5), mt.walnut));
  for (const y of [0.07, 0.24, 0.41]) g.add(K.m(K.tube(ring(y === 0.24 ? 0.238 : 0.226, 24, y), 0.009, { seg: 24, radial: 5, closed: true }), mt.brass));
  g.add(K.m(tc(puck(0.25, 0.03, 0.012, 24), '#5A3A22'), mt.lacquer, { pos: [0, 0.48, 0] }));
  g.add(K.m(tc(new THREE.CircleGeometry(0.22, 24), '#3A2A30'), mt.lacquer, { pos: [0, 0.5105, 0], rot: [-Math.PI / 2, 0, 0] }));
  // coaster + a paperback
  g.add(K.m(tc(puck(0.045, 0.006, 0.002, 14), '#E8A92E'), mt.paint, { pos: [0.08, 0.511, -0.06] }));
  g.add(K.m(tc(cbox(0.11, 0.022, 0.17, 0.003), '#2E8C8C'), mt.paint, { pos: [-0.06, 0.522, 0.04], rot: [0, 0.5, 0] }));
  g.userData.colliders = [{ min: [-0.24, 0, -0.24], max: [0.24, 0.52, 0.24] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['table', 'lobby', 'green_room', 'telly_home'], size: [0.5, 0.53, 0.5], desc: 'walnut drum side table with brass hoops and a smoked top' });

// ------------------------------------------------------------------------------------------------ lamps
// glowing part helper: lit -> glow material, unlit -> toon material of the same tint (rooms swap on Sign-On)
function glowMat(game, lit, color, intensity, unlit = '#D8CFC0') {
  return lit ? K.glow(game, color, intensity) : K.mat(game, 'plastic', unlit);
}
function marbleTex() {
  return K.tex.canvas('furn_marble', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#F2EEE6'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 40; i++) { ctx.fillStyle = rand() < 0.5 ? '#E6E0D4' : '#FAF8F2'; ctx.globalAlpha = 0.5; ctx.beginPath(); ctx.arc(rand() * w, rand() * h, 6 + rand() * 30, 0, TAU); ctx.fill(); }
    ctx.globalAlpha = 1; ctx.lineCap = 'round';
    for (let i = 0; i < 9; i++) {
      ctx.strokeStyle = i % 3 ? '#B8B0A6' : '#8E857C'; ctx.lineWidth = 0.6 + rand() * 2; ctx.globalAlpha = 0.5 + rand() * 0.4;
      ctx.beginPath(); let x = rand() * w, y = -10; ctx.moveTo(x, y);
      while (y < h + 10) { x += (rand() - 0.5) * 40; y += 10 + rand() * 30; ctx.lineTo(x, y); }
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  });
}

// ----------------------------------------------------------------------------------------------- arc lamp
registerProp('lamp_arc', (game, opts = {}) => {
  const g = K.prop('lamp_arc');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const marble = K.mat(game, 'ceramic', '#ffffff', { map: marbleTex() });
  const bz = 0.62, sz = -0.7, sy = 1.52;
  // marble block base with a chrome collar
  g.add(K.m(K.box(0.34, 0.36, 0.3, 0.035, { uv: 2 }), marble, { pos: [0, 0.18, bz] }));
  g.add(K.m(K.lathe([[0, 0], [0.035, 0], [0.03, 0.06], [0.018, 0.08], [0, 0.08]], { seg: 14, round: 0.008 }), mt.chrome, { pos: [0, 0.34, bz] }));
  // sweeping chrome arc (telescoping: a thicker lower section)
  const arc = [[0, 0.4, bz], [0, 1.0, bz + 0.02], [0, 1.55, bz - 0.08], [0, 1.9, bz - 0.36], [0, 2.04, bz - 0.72], [0, 2.0, bz - 1.02], [0, 1.88, sz + 0.06], [0, 1.74, sz], [0, sy + 0.14, sz]];
  g.add(K.m(K.tube(arc.slice(0, 4), 0.017, { seg: 20, radial: 8 }), mt.chrome));
  g.add(K.m(K.tube(arc.slice(3), 0.012, { seg: 40, radial: 7 }), mt.chrome));
  g.add(span(K.cyl(0.022, 0.022, 0.05, { seg: 10 }), mt.chrome, [0, 1.87, bz - 0.33], [0, 1.93, bz - 0.4]));
  // brushed dome shade with a rolled rim, perforation ring and glowing underside
  const shade = new THREE.Group();
  shade.position.set(0, sy, sz);
  const dome = K.lathe([[0.2, 0], [0.205, 0.012], [0.19, 0.06], [0.15, 0.14], [0.08, 0.2], [0.02, 0.22], [0, 0.22]], { seg: 28 });
  shade.add(K.m(dome, K.mat(game, 'metal', '#ffffff', { map: K.tex.brushed('#D8DDE4'), side: THREE.DoubleSide })));
  shade.add(K.m(K.tube(ring(0.203, 28, 0.004), 0.01, { seg: 28, radial: 5, closed: true }), mt.chrome));
  for (let i = 0; i < 16; i++) { const a = (i / 16) * TAU; shade.add(K.m(tc(sph(0.008, 6, 4), '#2A2230'), mt.plastic, { pos: [Math.sin(a) * 0.123, 0.172, Math.cos(a) * 0.123] })); }
  const bulb = K.m(K.lathe([[0, 0], [0.03, 0.005], [0.05, 0.04], [0.045, 0.07], [0, 0.08]], { seg: 14 }), glowMat(game, lit, PAL.tungsten, 4), { pos: [0, 0.03, 0] });
  bulb.userData.noMerge = true; bulb.userData.noOcclude = true;
  shade.add(bulb);
  const inner = K.m(new THREE.CircleGeometry(0.19, 24), glowMat(game, lit, '#FFE2B0', 1.4, '#E8E0D0'), { pos: [0, 0.14, 0], rot: [Math.PI / 2, 0, 0] });
  inner.userData.noOcclude = true;
  shade.add(inner);
  g.add(shade);
  g.userData.parts = { glow: bulb };
  g.userData.lightAnchors = lit ? [{ pos: [0, sy - 0.1, sz], color: PAL.tungsten, intensity: 1.8, distance: 4.5 }] : [];
  g.userData.colliders = [{ min: [-0.16, 0, bz - 0.14], max: [0.16, 0.45, bz + 0.14] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['lamp', 'light', 'lobby', 'green_room', 'telly_home'], size: [0.42, 2.1, 1.55], desc: 'chrome arc floor lamp on a marble block, brushed dome shade (light anchor; base-only collider; opts.lit)' });

// ------------------------------------------------------------------------------------------ tripod lamp
registerProp('lamp_tripod', (game, opts = {}) => {
  const g = K.prop('lamp_tripod');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const col = opts.color ?? '#E8A92E';
  const shadeMat = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave(NEUTRAL, { pattern: 'plain', scale: 3 }), side: THREE.DoubleSide, emissive: lit ? '#FFB060' : '#000000', emissiveIntensity: lit ? 0.3 : 0, rim: 0.15, rimPower: 3 });
  const hub = 0.95;
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.5;
    const f = [Math.sin(a) * 0.3, 0.02, Math.cos(a) * 0.3], t = [Math.sin(a) * 0.04, hub, Math.cos(a) * 0.04];
    g.add(rod(0.026, f, t, mt.walnut, { rb: 0.017, seg: 10 }));
    g.add(K.m(new THREE.CylinderGeometry(0.018, 0.02, 0.028, 8, 1).translate(0, 0.014, 0), mt.brass, { pos: [f[0], 0, f[2]] }));
  }
  // round walnut tray between the legs
  g.add(K.m(puck(0.2, 0.025, 0.01, 24), mt.walnut, { pos: [0, 0.46, 0] }));
  g.add(K.m(K.tube(ring(0.2, 24, 0.472), 0.007, { seg: 24, radial: 4, closed: true }), mt.brass));
  g.add(K.m(K.lathe([[0, 0], [0.06, 0], [0.066, 0.04], [0.04, 0.09], [0, 0.1]], { round: 0.012, seg: 16 }), mt.brass, { pos: [0, hub - 0.05, 0] }));
  g.add(K.m(K.cyl(0.014, 0.014, 0.44, { seg: 10 }), mt.brass, { pos: [0, hub + 0.04, 0] }));
  const by = 1.46;
  const bulb = K.m(K.lathe([[0, 0], [0.018, 0.005], [0.04, 0.045], [0.045, 0.075], [0.03, 0.11], [0, 0.12]], { seg: 14 }), glowMat(game, lit, PAL.tungsten, 4), { pos: [0, by - 0.06, 0] });
  bulb.userData.noMerge = true; bulb.userData.noOcclude = true;
  g.add(bulb);
  // mustard drum shade with orange bands, glowing lining
  const y0 = 1.34, y1 = 1.72, r0 = 0.3, r1 = 0.27;
  const shell = new THREE.LatheGeometry([new THREE.Vector2(r0, 0), new THREE.Vector2(r1, y1 - y0)], 48);
  K.uvScale(shell, 9, 1.2);
  g.add(K.m(tc(shell, col), shadeMat, { pos: [0, y0, 0] }));
  for (const [y, r, c] of [[0.04, r0 - 0.003, '#E3662B'], [0.075, r0 - 0.005, '#B5472A'], [y1 - y0 - 0.05, r1 + 0.002, '#E3662B']]) {
    const band = new THREE.LatheGeometry([new THREE.Vector2(r + 0.004, 0), new THREE.Vector2(r + 0.004 - 0.002, 0.022)], 48);
    g.add(K.m(tc(band, c), shadeMat, { pos: [0, y0 + y, 0] }));
  }
  const lin = K.m(new THREE.LatheGeometry([new THREE.Vector2(r1 - 0.006, y1 - y0 - 0.004), new THREE.Vector2(r0 - 0.006, 0.004)], 28), glowMat(game, lit, '#FFD9A0', 1.1, '#E8DCC4'), { pos: [0, y0, 0] });
  lin.userData.noOcclude = true;
  g.add(lin);
  g.add(K.m(K.tube(ring(r0 + 0.006, 24, y0), 0.011, { seg: 28, radial: 4, closed: true }), mt.brass));
  g.add(K.m(K.tube(ring(r1 + 0.006, 24, y1), 0.01, { seg: 28, radial: 4, closed: true }), mt.brass));
  for (let i = 0; i < 3; i++) { const a = (i / 3) * TAU; g.add(K.m(K.tube([[0, by + 0.1, 0], [Math.sin(a) * r1 * 0.6, y1 - 0.01, Math.cos(a) * r1 * 0.6], [Math.sin(a) * r1, y1, Math.cos(a) * r1]], 0.005, { seg: 8, radial: 4 }), mt.brass)); }
  g.userData.parts = { glow: bulb };
  g.userData.lightAnchors = lit ? [{ pos: [0, by, 0], color: PAL.tungsten, intensity: 1.8, distance: 4.5 }] : [];
  g.userData.colliders = [{ min: [-0.24, 0, -0.24], max: [0.24, 1.72, 0.24] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['lamp', 'light', 'lobby', 'newsroom', 'telly_home'], size: [0.64, 1.74, 0.64], desc: 'walnut tripod floor lamp with a tray, mustard drum shade with orange bands (light anchor; opts.color, opts.lit)' });

// ------------------------------------------------------------------------------------ tension pole lamp
registerProp('lamp_pole', (game, opts = {}) => {
  const g = K.prop('lamp_pole');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const H = opts.h ?? 2.4;
  g.add(K.m(tc(puck(0.08, 0.03, 0.012, 12), '#2A2230'), mt.rubber));
  g.add(K.m(K.cyl(0.018, 0.018, H - 0.06, { seg: 10 }), mt.chrome, { pos: [0, 0.03, 0] }));
  g.add(K.m(tc(puck(0.07, 0.03, 0.012, 12), '#2A2230'), mt.rubber, { pos: [0, H - 0.03, 0] }));
  g.add(K.m(K.cyl(0.024, 0.024, 0.12, { seg: 10 }), mt.chrome, { pos: [0, H - 0.5, 0] }));
  const inside = K.mat(game, 'paint', '#F6E7C8');
  const cones = [[0.9, '#E3662B', 0.4, -0.5], [1.35, '#E8A92E', 2.5, 0.2], [1.8, '#8C9A3A', 4.4, -0.3]];
  const bulbs = [];
  cones.forEach(([y, c, a, tilt]) => {
    const arm = new THREE.Group();
    arm.position.set(0, y, 0);
    arm.rotation.y = a;
    arm.add(K.m(K.cyl(0.026, 0.026, 0.05, { seg: 10 }), mt.chrome, { pos: [0, -0.025, 0] }));
    arm.add(K.m(K.tube([[0, 0, 0], [0, 0.03, -0.1], [0, 0.02, -0.15]], 0.008, { seg: 8, radial: 5 }), mt.chrome));
    const hd = new THREE.Group();
    hd.position.set(0, 0.02, -0.17);
    hd.rotation.x = Math.PI * 0.5 + tilt;
    const cone = K.lathe([[0.12, 0], [0.118, 0.012], [0.07, 0.14], [0.04, 0.2], [0.038, 0.22], [0, 0.22]], { seg: 18, round: 0.01, steps: 1 });
    hd.add(K.m(tc(cone, c), mt.lacquer, { pos: [0, -0.2, 0] }));
    hd.add(K.m(flipGeo(K.lathe([[0.112, 0.01], [0.066, 0.135], [0.034, 0.195], [0, 0.2]], { seg: 18 })), inside, { pos: [0, -0.2, 0] }));
    const b = K.m(sph(0.034, 10, 8), glowMat(game, lit, PAL.tungsten, 3.5), { pos: [0, -0.16, 0] });
    b.userData.noOcclude = true; b.userData.noMerge = true;
    hd.add(b);
    bulbs.push(b);
    arm.add(hd);
    g.add(arm);
  });
  g.userData.parts = { glow: bulbs[1], glow0: bulbs[0], glow2: bulbs[2] };
  g.userData.lightAnchors = lit ? [{ pos: [0, 1.35, 0], color: PAL.tungsten, intensity: 1.8, distance: 4.5 }] : [];
  g.userData.colliders = [{ min: [-0.1, 0, -0.1], max: [0.1, H, 0.1] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['lamp', 'light', 'green_room', 'lobby'], size: [0.5, 2.4, 0.5], desc: 'floor-to-ceiling tension pole lamp with orange / mustard / avocado enamel cones (opts.h = ceiling height, opts.lit)' });

// ------------------------------------------------------------------------------------------ globe pendant
registerProp('lamp_globe_pendant', (game, opts = {}) => {
  const g = K.prop('lamp_globe_pendant');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const drop = opts.drop ?? 0.9;
  const R = opts.r ?? 0.2;
  g.add(K.m(K.lathe([[0, 0], [0.09, 0], [0.085, -0.02], [0.03, -0.045], [0, -0.05]], { seg: 20, round: 0.008 }), mt.brass));
  // chain: alternating flat links
  const nL = Math.max(3, Math.round((drop - 0.12) / 0.05));
  for (let i = 0; i < nL; i++) {
    const l = K.m(new THREE.TorusGeometry(0.014, 0.004, 4, 10), mt.brass, { pos: [0, -0.06 - i * 0.05 * (drop - 0.12) / (nL * 0.05), 0], rot: [0, (i % 2) * Math.PI / 2, 0] });
    l.scale.set(1, 1.7, 1);
    g.add(l);
  }
  const cy = -drop - R + 0.02;
  g.add(K.m(K.lathe([[0, 0], [0.07, 0], [0.075, 0.02], [0.05, 0.06], [0.02, 0.09], [0, 0.1]], { seg: 18, round: 0.01 }), mt.brass, { pos: [0, cy + R - 0.035, 0] }));
  const globe = K.m(sph(R, 24, 16), K.mat(game, 'ceramic', '#FFF1D8', lit ? { emissive: '#FFD9A0', emissiveIntensity: 0.95, rim: 0.5, rimColor: '#FFFFFF' } : {}), { pos: [0, cy, 0] });
  globe.userData.noMerge = true; globe.userData.noOcclude = true;
  g.add(globe);
  g.add(K.m(K.lathe([[0, 0], [0.028, 0], [0.024, 0.02], [0, 0.026]], { seg: 12 }), mt.brass, { pos: [0, cy - R - 0.012, 0] }));
  g.userData.parts = { glow: globe };
  g.userData.lightAnchors = lit ? [{ pos: [0, cy, 0], color: PAL.tungsten, intensity: 2.2, distance: 6 }] : [];
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['ceiling', 'lamp', 'light', 'lobby'], size: [0.4, 1.3, 0.4], desc: 'opal glass globe pendant on a brass chain (ceiling origin; opts.drop, opts.r, opts.lit)' });

// ------------------------------------------------------------------------------------------------ lava lamp
registerProp('lamp_lava', (game, opts = {}) => {
  const g = K.prop('lamp_lava');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const wax = opts.color ?? '#FF3B6A';
  const starTex = K.tex.canvas('furn_lava_base', 256, 128, (ctx, w, h) => {
    const gr = ctx.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#F2CF6A'); gr.addColorStop(1, '#A87830');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#3A1E2A';
    for (let i = 0; i < 6; i++) {
      const x = 20 + i * 43, y = 64 + (i % 2 ? -14 : 14);
      ctx.beginPath();
      for (let k = 0; k < 10; k++) { const a = (k / 10) * TAU - Math.PI / 2, r = k % 2 ? 6 : 14; ctx.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r); }
      ctx.fill();
    }
  });
  const gold = K.mat(game, 'brass', '#ffffff', { map: starTex });
  g.add(K.m(K.lathe([[0, 0], [0.11, 0], [0.11, 0.012], [0.07, 0.15], [0.058, 0.16], [0, 0.16]], { seg: 24, round: 0.006 }), gold));
  // tapered bottle: liquid (translucent glow) + blobs (parts.blobs, animatable)
  const bottle = [[0.056, 0], [0.075, 0.1], [0.07, 0.18], [0.046, 0.3], [0.034, 0.33], [0, 0.33]];
  const liquid = K.m(K.lathe(bottle, { seg: 24 }), lit ? K.glow(game, '#FF9A3A', 0.62, { transparent: true, opacity: 0.82 }) : K.mat(game, 'plastic', '#C8A070', { transparent: true, opacity: 0.85 }), { pos: [0, 0.16, 0] });
  liquid.userData.noOcclude = true; liquid.userData.noMerge = true;
  g.add(liquid);
  const blobs = new THREE.Group();
  blobs.position.set(0, 0.16, 0);
  blobs.userData.noMerge = true;
  const wm = lit ? K.glow(game, wax, 1.25) : K.mat(game, 'plastic', wax);
  for (const [x, y, z, r, sy] of [[0.0, 0.035, 0, 0.05, 0.55], [0.012, 0.13, 0.01, 0.028, 1.3], [-0.015, 0.21, -0.008, 0.02, 1.0], [0.004, 0.27, 0.004, 0.014, 1.2]]) {
    const b = K.m(sph(r, 12, 8), wm, { pos: [x, y, z], scale: [1, sy, 1] });
    b.userData.noOcclude = true;
    blobs.add(b);
  }
  g.add(blobs);
  g.add(K.m(K.lathe([[0.036, 0], [0.034, 0.03], [0.022, 0.06], [0.01, 0.07], [0, 0.072]], { seg: 20, round: 0.006 }), gold, { pos: [0, 0.48, 0] }));
  g.userData.parts = { glow: liquid, blobs };
  g.userData.lightAnchors = lit ? [{ pos: [0, 0.35, 0], color: wax, intensity: 1.2, distance: 3 }] : [];
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { height: 0.02 } });
}, { category: CAT, tags: ['tabletop', 'lamp', 'light', 'green_room'], size: [0.22, 0.55, 0.22], desc: 'lava lamp: gold star-cut base, glowing amber liquid, pink wax blobs (parts.blobs to animate; opts.color, opts.lit)' });

// ------------------------------------------------------------------------------------ fluorescent panel
registerProp('light_fluoro_panel', (game, opts = {}) => {
  const g = K.prop('light_fluoro_panel');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const W = opts.w ?? 1.22, D = opts.d ?? 0.61;
  const prism = K.tex.canvas('furn_prism', 128, 128, (ctx, w, h) => {
    ctx.fillStyle = '#F4FAF0'; ctx.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 16) for (let x = 0; x < w; x += 16) {
      const gr = ctx.createRadialGradient(x + 8, y + 8, 1, x + 8, y + 8, 10); gr.addColorStop(0, '#FFFFFF'); gr.addColorStop(1, '#C8D8C8');
      ctx.fillStyle = gr; ctx.beginPath(); ctx.moveTo(x + 8, y); ctx.lineTo(x + 16, y + 8); ctx.lineTo(x + 8, y + 16); ctx.lineTo(x, y + 8); ctx.fill();
    }
  });
  g.add(K.m(tc(K.box(W, 0.07, D, 0.012), '#EDEAE2'), mt.paint, { pos: [0, -0.035, 0] }));
  const lens = K.m(K.uvScale(new THREE.PlaneGeometry(W - 0.07, D - 0.07).clone(), W * 6, D * 6), lit ? K.glow(game, '#E8F5E1', 1.25, { map: prism }) : K.mat(game, 'plastic', '#E4EAE0', { map: prism }), { pos: [0, -0.073, 0], rot: [Math.PI / 2, 0, 0] });
  lens.userData.noMerge = true; lens.userData.noOcclude = true;
  g.add(lens);
  // frame lip
  for (const s of [-1, 1]) {
    g.add(K.m(tc(K.box(W, 0.012, 0.04, 0.004), '#DCD8CE'), mt.paint, { pos: [0, -0.074, s * (D / 2 - 0.02)] }));
    g.add(K.m(tc(K.box(0.04, 0.012, D - 0.06, 0.004), '#DCD8CE'), mt.paint, { pos: [s * (W / 2 - 0.02), -0.074, 0] }));
  }
  g.userData.parts = { glow: lens };
  g.userData.lightAnchors = lit ? [{ pos: [0, -0.4, 0], color: '#E8F5E1', intensity: 2.2, distance: 6, flicker: !!opts.flicker }] : [];
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['ceiling', 'light', 'newsroom', 'master_control'], size: [1.22, 0.08, 0.61], desc: '2x4 fluorescent troffer with a prismatic lens (ceiling origin; opts.w/d, opts.lit, opts.flicker)' });

// ------------------------------------------------------------------------------------------------ can light
registerProp('light_can', (game, opts = {}) => {
  const g = K.prop('light_can');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const recessed = opts.style === 'recessed';
  const col = opts.color ?? '#F4F1E8';
  const h = recessed ? 0.02 : 0.2;
  if (!recessed) {
    g.add(K.m(tc(puck(0.07, 0.02, 0.006, 16), col), mt.lacquer, { pos: [0, -0.02, 0] }));
    g.add(K.m(tc(K.lathe([[0.085, 0], [0.09, 0.01], [0.09, h - 0.03], [0.08, h - 0.02], [0.02, h - 0.02], [0, h - 0.02]], { seg: 22, round: 0.006 }), col), mt.lacquer, { pos: [0, -h, 0] }));
  }
  // trim ring + black stepped baffle + bulb face
  g.add(K.m(tc(K.lathe([[0.075, 0], [0.105, 0], [0.108, 0.01], [0.09, 0.016], [0.075, 0.014]], { seg: 22 }), recessed ? col : '#C9CED6'), recessed ? mt.lacquer : mt.chrome, { pos: [0, -h - 0.004, 0] }));
  g.add(K.m(tc(K.lathe([[0.075, 0.014], [0.068, 0.03], [0.07, 0.034], [0.062, 0.05], [0.064, 0.054], [0.056, 0.07]], { seg: 20 }), '#2A2230'), mt.plastic, { pos: [0, -h - 0.004, 0], rot: [0, 0, 0] }));
  const face = K.m(new THREE.CircleGeometry(0.056, 18), glowMat(game, lit, PAL.tungsten, 3.2), { pos: [0, -h + 0.064, 0], rot: [Math.PI / 2, 0, 0] });
  face.userData.noMerge = true; face.userData.noOcclude = true;
  g.add(face);
  g.userData.parts = { glow: face };
  g.userData.lightAnchors = lit ? [{ pos: [0, -h - 0.3, 0], color: PAL.tungsten, intensity: 1.8, distance: 5 }] : [];
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['ceiling', 'light', 'lobby', 'green_room'], size: [0.22, 0.22, 0.22], desc: 'surface-mounted can light with a chrome trim and black baffle (ceiling origin; opts.style=recessed, opts.color, opts.lit)' });

// ============================================================================================ review scenes
registerScene('furn_ceiling', {
  floor: 'tile', wall: '#D8C9A8', room: [5.2, 4.2], wallH: 3.2,
  items: [
    { id: 'lamp_globe_pendant', pos: [-1.6, 2.8, 0.6] },
    { id: 'lamp_globe_pendant', pos: [-0.9, 2.8, 1.2], opts: { drop: 0.5, r: 0.15 } },
    { id: 'light_fluoro_panel', pos: [0.4, 2.8, 0.7] },
    { id: 'light_fluoro_panel', pos: [0.4, 2.8, 1.6], opts: { lit: false } },
    { id: 'light_can', pos: [1.7, 2.8, 0.4] },
    { id: 'light_can', pos: [1.7, 2.8, 1.3], opts: { style: 'recessed' } },
    { id: 'lamp_globe_pendant', pos: [-0.2, 2.8, 1.9], opts: { lit: false } },
  ],
  cam: { pos: [0, 1.1, -1.9], target: [0, 2.35, 1.1], fov: 64 }, hemi: 0.8,
});

// ------------------------------------------------------------------------------------ decor atlas
// Second 1024 atlas (4x4 of 256): labels, notes, photos, plaques, book spines. dcell(geo, cx, cy) like cell().
function decorAtlas() {
  return K.tex.canvas('furn_decor_atlas', 1024, 1024, (ctx, W, H, rand) => {
    const S = 256;
    const at = (cx, cy, fn) => { ctx.save(); ctx.translate(cx * S, cy * S); ctx.beginPath(); ctx.rect(0, 0, S, S); ctx.clip(); fn(); ctx.restore(); };
    const font = (px, f = 'Titan One') => `${px}px "${f}", "Arial Black", sans-serif`;
    const center = () => { ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; };
    const typed = (lines, x, y, lh, px = 14, col = '#2A2230') => {
      ctx.fillStyle = col; ctx.font = `${px}px "Courier New", monospace`; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
      lines.forEach((l, i) => ctx.fillText(l, x, y + i * lh));
    };
    const scribble = (x, y, w, n, col = '#2F5BD3', lh = 20) => {
      ctx.strokeStyle = col; ctx.lineWidth = 2.5; ctx.lineCap = 'round';
      for (let i = 0; i < n; i++) { ctx.beginPath(); let xx = x; ctx.moveTo(xx, y + i * lh); while (xx < x + w * (0.5 + rand() * 0.5)) { xx += 5; ctx.lineTo(xx, y + i * lh - rand() * 5); } ctx.stroke(); }
    };
    // (0,0) AQUA-PURE water label
    at(0, 0, () => {
      ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#2F5BD3'; ctx.fillRect(0, 0, S, 60); ctx.fillRect(0, S - 40, S, 40);
      ctx.fillStyle = '#3FB8E8'; ctx.beginPath(); ctx.moveTo(128, 78); ctx.bezierCurveTo(170, 130, 168, 176, 128, 178); ctx.bezierCurveTo(88, 176, 86, 130, 128, 78); ctx.fill();
      center(); ctx.fillStyle = '#F4F1E8'; ctx.font = font(36, 'Bungee'); ctx.fillText('AQUA-PURE', 128, 32);
      ctx.fillStyle = '#2F5BD3'; ctx.font = font(22); ctx.fillText('SPRING WATER', 128, 200);
      ctx.fillStyle = '#F4F1E8'; ctx.font = font(18); ctx.fillText('ICE COLD', 128, S - 20);
    });
    // (1,0) payphone instruction card
    at(1, 0, () => {
      ctx.fillStyle = '#F6E7C8'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#2F5BD3'; ctx.fillRect(0, 0, S, 44);
      center(); ctx.fillStyle = '#F4F1E8'; ctx.font = font(24, 'Bungee'); ctx.fillText('LOCAL CALLS 10¢', 128, 23);
      typed(['1. LIFT RECEIVER', '2. DEPOSIT COIN', '3. LISTEN FOR TONE', '4. DIAL NUMBER', '', 'EMERGENCY: DIAL 0', 'WZTV  555-1313'], 16, 76, 24, 15);
    });
    // (2,0) TELEPHONE sign (blue + white)
    at(2, 0, () => {
      ctx.fillStyle = '#2F5BD3'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#F4F1E8'; ctx.fillRect(10, 90, S - 20, 76);
      center(); ctx.fillStyle = '#2F5BD3'; ctx.font = font(40, 'Bungee'); ctx.fillText('PHONE', 128, 130);
      ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(128, 48, 28, 0, TAU); ctx.fill();
      ctx.fillStyle = '#2F5BD3'; ctx.font = font(30, 'Bungee'); ctx.fillText('☎', 128, 50);
      ctx.fillStyle = '#F4F1E8'; ctx.font = font(20); ctx.fillText('PUBLIC TELEPHONE', 128, 205);
    });
    // (3,0) clock dial: cream, chunky numerals, minute ticks
    at(3, 0, () => {
      ctx.fillStyle = '#F6EEDB'; ctx.beginPath(); ctx.arc(128, 128, 128, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#2A2230'; ctx.lineCap = 'round';
      for (let i = 0; i < 60; i++) {
        const a = (i / 60) * TAU, big = i % 5 === 0;
        ctx.lineWidth = big ? 6 : 2;
        ctx.beginPath(); ctx.moveTo(128 + Math.sin(a) * (big ? 104 : 112), 128 - Math.cos(a) * (big ? 104 : 112)); ctx.lineTo(128 + Math.sin(a) * 120, 128 - Math.cos(a) * 120); ctx.stroke();
      }
      center(); ctx.fillStyle = '#2A2230'; ctx.font = font(30);
      for (let i = 1; i <= 12; i++) { const a = (i / 12) * TAU; ctx.fillText(String(i), 128 + Math.sin(a) * 82, 131 - Math.cos(a) * 82); }
      ctx.fillStyle = '#E23B3B'; ctx.font = font(15, 'Bungee'); ctx.fillText('WZTV', 128, 170);
    });
    // (0,1) pink WHILE YOU WERE OUT memo
    at(0, 1, () => {
      ctx.fillStyle = '#FFB6C8'; ctx.fillRect(0, 0, S, S);
      center(); ctx.fillStyle = '#B5472A'; ctx.font = font(20, 'Bungee'); ctx.fillText('WHILE YOU', 128, 28); ctx.fillText('WERE OUT', 128, 52);
      ctx.strokeStyle = '#B5472A'; ctx.lineWidth = 2;
      for (let y = 90; y < S; y += 30) { ctx.beginPath(); ctx.moveTo(14, y); ctx.lineTo(S - 14, y); ctx.stroke(); }
      scribble(20, 84, 200, 5, '#2A2230', 30);
    });
    // (1,1) polaroid: sunny WZTV tower snapshot
    at(1, 1, () => {
      ctx.fillStyle = '#FBF8F0'; ctx.fillRect(0, 0, S, S);
      const g = ctx.createLinearGradient(0, 16, 0, 196); g.addColorStop(0, '#FF7E5F'); g.addColorStop(1, '#FFE3A3');
      ctx.fillStyle = g; ctx.fillRect(16, 16, S - 32, 180);
      ctx.fillStyle = '#FFF4D6'; ctx.beginPath(); ctx.arc(170, 80, 26, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#6B3A6E'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(90, 196); ctx.lineTo(110, 50); ctx.lineTo(130, 196); ctx.moveTo(96, 150); ctx.lineTo(124, 150); ctx.moveTo(101, 110); ctx.lineTo(119, 110); ctx.stroke();
      ctx.fillStyle = '#FF3B30'; ctx.beginPath(); ctx.arc(110, 48, 6, 0, TAU); ctx.fill();
      ctx.fillStyle = '#8C9A3A'; ctx.fillRect(16, 176, S - 32, 20);
      ctx.fillStyle = '#2F5BD3'; ctx.font = '22px "Courier New", monospace'; ctx.textAlign = 'center'; ctx.fillText('SUMMER \'76', 128, 232);
    });
    // (2,1) WZTV weekly schedule sheet
    at(2, 1, () => {
      ctx.fillStyle = '#FDFBF4'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#E3662B'; ctx.fillRect(0, 0, S, 36);
      center(); ctx.fillStyle = '#F4F1E8'; ctx.font = font(20, 'Bungee'); ctx.fillText('ON-AIR SCHEDULE', 128, 19);
      const rows = ['6:00 ACTION 13 NEWS', '6:30 DUSTY TRAILS', '7:00 HOOTIE\'S HOUR', '8:00 PRECINCT 13', '9:00 GROOVE HOUR', '11:00 NEWS FINAL', '11:30 BARON\'S CRYPT'];
      rows.forEach((r, i) => { ctx.fillStyle = i % 2 ? '#F4EEDC' : '#FDFBF4'; ctx.fillRect(0, 44 + i * 30, S, 30); });
      typed(rows, 12, 64, 30, 14);
    });
    // (3,1) yellow sticky
    at(3, 1, () => { ctx.fillStyle = '#FFE36A'; ctx.fillRect(0, 0, S, S); ctx.fillStyle = '#F2D24A'; ctx.fillRect(0, 0, S, 30); scribble(20, 70, 210, 5, '#E23B3B', 34); });
    // (0,2) newspaper clipping
    at(0, 2, () => {
      ctx.fillStyle = '#EFE8D4'; ctx.fillRect(0, 0, S, S);
      ctx.fillStyle = '#2A2230'; ctx.font = font(24, 'Bungee'); ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
      ctx.fillText('CHANNEL 13', 12, 36); ctx.fillText('WINS BIG!', 12, 64);
      ctx.fillStyle = '#9A9080'; ctx.fillRect(12, 76, 110, 80);
      ctx.fillStyle = '#6B6258';
      for (let y = 80; y < S - 10; y += 9) { ctx.fillRect(132, y, 110 - rand() * 20, 4); if (y > 164) ctx.fillRect(12, y, 110 - rand() * 20, 4); }
    });
    // (1,2) crew memo / union notice
    at(1, 2, () => {
      ctx.fillStyle = '#E8F0FF'; ctx.fillRect(0, 0, S, S);
      center(); ctx.fillStyle = '#2F5BD3'; ctx.font = font(22, 'Bungee'); ctx.fillText('CREW NOTICE', 128, 26);
      typed(['NO FOOD ON', 'STUDIO FLOOR!', '', 'TELETHON CALL', 'TIME: 5 PM SHARP', '', '- MGMT'], 20, 64, 24, 16);
    });
    // (2,2) brass plaque plate
    at(2, 2, () => {
      const g = ctx.createLinearGradient(0, 0, 0, S); g.addColorStop(0, '#F2CF6A'); g.addColorStop(0.5, '#C8963C'); g.addColorStop(1, '#8A6224');
      ctx.fillStyle = g; ctx.fillRect(0, 0, S, S);
      ctx.strokeStyle = '#6A4A1A'; ctx.lineWidth = 4; ctx.strokeRect(10, 10, S - 20, S - 20);
      center(); ctx.fillStyle = '#3A2410'; ctx.font = font(26, 'Bungee'); ctx.fillText('BEST LOCAL', 128, 96); ctx.fillText('NEWS', 128, 128);
      ctx.font = font(20); ctx.fillText('TRI-COUNTY 1976', 128, 170);
    });
    // (3,2) world-clock city tags
    at(3, 2, () => {
      ['NEW YORK', 'LONDON', 'TOKYO', 'WZTV'].forEach((c, i) => {
        ctx.fillStyle = i === 3 ? '#E23B3B' : '#2A2230'; ctx.fillRect(0, i * 64, S, 64);
        center(); ctx.fillStyle = '#F4F1E8'; ctx.font = font(30, 'Bungee'); ctx.fillText(c, 128, i * 64 + 34);
      });
    });
    // (0..3,3) book spines: 4 cells x 8 spines (each spine = 32 px wide column)
    const spineCols = ['#B5472A', '#2E8C8C', '#E8A92E', '#5A3A22', '#6B3A6E', '#8C9A3A', '#2F5BD3', '#E3662B', '#F6E7C8', '#7A4A2A', '#D9A520', '#3A2A5A'];
    for (let c = 0; c < 4; c++) at(c, 3, () => {
      for (let i = 0; i < 8; i++) {
        const x = i * 32, col = spineCols[(c * 5 + i * 3) % spineCols.length];
        ctx.fillStyle = col; ctx.fillRect(x, 0, 32, S);
        ctx.fillStyle = 'rgba(255,255,255,0.14)'; ctx.fillRect(x + 3, 0, 4, S);
        ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.fillRect(x + 28, 0, 4, S);
        const band = ['#F2CF6A', '#F4F1E8', '#2A2230'][(i + c) % 3];
        ctx.fillStyle = band; ctx.fillRect(x + 4, 22, 24, 6); ctx.fillRect(x + 4, S - 34, 24, 6);
        ctx.fillRect(x + 9, 60 + ((i * 37) % 60), 14, 70 + ((i * 23) % 50));
      }
    });
    void W; void H;
  }, { repeat: false, fonts: true });
}
const dcell = (geo, cx, cy) => K.uvRect(geo.clone(), cx / 4, 1 - (cy + 1) / 4, (cx + 1) / 4, 1 - cy / 4);
const decorMat = (game) => K.mat(game, 'paint', '#ffffff', { map: decorAtlas() });

// ------------------------------------------------------------------------------------------------ plants
function leafTex() {
  return K.tex.canvas('furn_leaf', 128, 256, (ctx, w, h) => {
    ctx.fillStyle = '#FFFFFF'; ctx.fillRect(0, 0, w, h);
    const g = ctx.createLinearGradient(0, 0, w, 0); g.addColorStop(0, '#C8D4B8'); g.addColorStop(0.5, '#FFFFFF'); g.addColorStop(1, '#C8D4B8');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = '#F2FFD8'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(w / 2, 0); ctx.lineTo(w / 2, h); ctx.stroke();
    ctx.strokeStyle = 'rgba(230,255,200,0.55)'; ctx.lineWidth = 2;
    for (let y = 20; y < h; y += 22) for (const s of [-1, 1]) { ctx.beginPath(); ctx.moveTo(w / 2, y); ctx.quadraticCurveTo(w / 2 + s * 30, y + 8, w / 2 + s * 58, y + 26); ctx.stroke(); }
  }, { repeat: false });
}
function frondTex() {
  return K.tex.canvas('furn_frond', 128, 512, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = '#DDEBC0'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(w / 2, 0); ctx.lineTo(w / 2, h); ctx.stroke();
    for (let y = 8; y < h - 6; y += 13) {
      const t = y / h, len = 60 * Math.sin(Math.PI * Math.min(1, t * 1.05 + 0.02)) + 6;
      for (const s of [-1, 1]) {
        ctx.fillStyle = (Math.floor(y / 13) + (s > 0 ? 1 : 0)) % 2 ? '#FFFFFF' : '#E8F2D8';
        ctx.beginPath(); ctx.moveTo(w / 2, y);
        ctx.quadraticCurveTo(w / 2 + s * len * 0.6, y - 9, w / 2 + s * len, y + 8);
        ctx.quadraticCurveTo(w / 2 + s * len * 0.5, y + 10, w / 2, y + 7);
        ctx.fill();
      }
    }
  }, { repeat: false });
}
function snakeTex() {
  return K.tex.canvas('furn_snake', 128, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#2E5A2A'; ctx.fillRect(0, 0, w, h);
    for (let y = 6; y < h; y += 14 + rand() * 10) {
      ctx.strokeStyle = rand() < 0.5 ? '#6E9A52' : '#4F7A3E'; ctx.lineWidth = 3 + rand() * 4; ctx.globalAlpha = 0.8;
      ctx.beginPath(); for (let x = 0; x <= w; x += 8) { const yy = y + Math.sin(x * 0.12 + y) * 5; if (x === 0) ctx.moveTo(x, yy); else ctx.lineTo(x, yy); } ctx.stroke();
    }
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#E8D24A'; ctx.fillRect(0, 0, 11, h); ctx.fillRect(w - 11, 0, 11, h);
    ctx.fillStyle = '#B8B040'; ctx.fillRect(11, 0, 3, h); ctx.fillRect(w - 14, 0, 3, h);
  }, { repeat: false });
}

// glazed pot: style 'drip' (orange with a chocolate drip glaze), 'bands' (cream + brown bands), 'mustard', 'terracotta'
function potGroup(game, style = 'drip', r = 0.2, h = 0.3) {
  const mt = M(game);
  const g = new THREE.Group();
  const cer = K.mat(game, 'ceramic', '#ffffff');
  const prof = style === 'mustard'
    ? [[0, 0], [r * 0.92, 0], [r, h * 0.1], [r, h * 0.92], [r * 1.04, h], [r * 0.9, h], [r * 0.88, h * 0.9], [0, h * 0.9]]
    : [[0, 0], [r * 0.62, 0], [r * 0.72, h * 0.12], [r * 0.95, h * 0.6], [r, h * 0.88], [r * 1.06, h * 0.94], [r * 1.05, h], [r * 0.92, h], [r * 0.9, h * 0.9], [0, h * 0.9]];
  const geo = K.lathe(prof, { seg: 18, round: 0.012, steps: 1 }).clone();
  const base = { drip: '#E3662B', bands: '#F6E7C8', mustard: '#D9A520', terracotta: '#C8643A' }[style];
  const c1 = new THREE.Color(base), c2 = new THREE.Color(style === 'bands' ? '#7A4A2A' : '#5A3A22'), tmp = new THREE.Color();
  K.tint(geo, (x, y, z) => {
    const a = Math.atan2(z, x);
    if (style === 'drip') { const edge = h * (0.72 - 0.12 * Math.abs(Math.sin(a * 5)) - 0.08 * Math.max(0, Math.sin(a * 11))); return y > edge ? c2 : c1; }
    if (style === 'bands') return (y > h * 0.3 && y < h * 0.38) || (y > h * 0.66 && y < h * 0.72) ? c2 : c1;
    if (style === 'mustard') return y > h * 0.78 && y < h * 0.86 ? tmp.copy(c1).multiplyScalar(0.55) : c1;
    return y > h * 0.86 ? tmp.copy(c1).multiplyScalar(0.85) : c1;
  });
  g.add(K.m(geo, cer));
  g.add(K.m(tc(new THREE.CircleGeometry(r * 0.9, 16), '#3A2418'), mt.paint, { pos: [0, h * 0.86, 0], rot: [-Math.PI / 2, 0, 0] }));
  return g;
}
const leafMat = (game, map, extra = {}) => K.mat(game, 'leaf', '#ffffff', { map, ...extra });

// ------------------------------------------------------------------------------------------- rubber plant
registerProp('plant_rubber', (game, opts = {}) => {
  const g = K.prop('plant_rubber');
  const mt = M(game);
  const seed = opts.seed ?? 2;
  const rnd = mulberry32(seed * 313 + 1);
  const lm = leafMat(game, leafTex(), { rough: 0.28, env: 0.12, rim: 0.22, rimColor: '#D8FFB0' });
  g.add(potGroup(game, opts.pot ?? 'drip', 0.2, 0.32));
  const stems = [[0.0, 0.0, 1.45], [0.07, 0.05, 1.12], [-0.08, 0.03, 0.88]];
  const leafG = [];
  stems.forEach(([sx, sz, top], si) => {
    const lean = [(rnd() - 0.5) * 0.16, (rnd() - 0.5) * 0.16];
    const P = (t) => [sx + lean[0] * t * t, 0.26 + (top - 0.26) * t, sz + lean[1] * t * t];
    const pts = [0, 0.33, 0.66, 1].map(P);
    g.add(K.m(tc(K.tube(pts, 0.012 - si * 0.002, { seg: 10, radial: 5 }), '#4A4A2A'), mt.paint));
    const n = Math.round((top - 0.35) / 0.085) + 2;
    for (let i = 0; i < n; i++) {
      const t = 0.22 + (i / (n - 1)) * 0.78;
      const p = P(t);
      const ang = i * 2.4 + si * 1.3 + rnd() * 0.3;
      const young = t > 0.9;
      const big = young ? 0.62 : 1.08 - (t - 0.22) * 0.3;
      const lf = K.leaf(0.34 * big, 0.2 * big, { a0: young ? 1.1 : 0.45 - rnd() * 0.2, a1: young ? 0.3 : -0.55 - rnd() * 0.3, fold: 0.1, tip: 0.85, segL: 6, segW: 2, twist: (rnd() - 0.5) * 0.4 });
      lf.translate(0, 0, 0.025);
      lf.rotateY(ang);
      lf.translate(p[0], p[1], p[2]);
      const k = 0.85 + rnd() * 0.3;
      K.tint(lf, new THREE.Color(young ? '#4E8A30' : '#1E4A20').multiplyScalar(k));
      leafG.push(lf);
    }
    g.add(K.m(tc(K.lathe([[0, 0], [0.014, 0.01], [0.01, 0.07], [0, 0.1]], { seg: 8 }), '#9A2A3A'), mt.plastic, { pos: P(1) }));
  });
  const merged = mergeGeometries(leafG, false);
  g.add(K.m(merged, lm));
  g.userData.colliders = [{ min: [-0.22, 0, -0.22], max: [0.22, 1.5, 0.22] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['plant', 'lobby', 'newsroom'], size: [0.8, 1.55, 0.8], desc: 'rubber plant: glossy dark leaves on three stems, burgundy tips, drip-glaze pot (opts.pot, opts.seed)' });

// ----------------------------------------------------------------------------------------- fern on stand
registerProp('plant_fern', (game, opts = {}) => {
  const g = K.prop('plant_fern');
  const mt = M(game);
  const fm = leafMat(game, frondTex(), { alphaTest: 0.45, rough: 0.6, rim: 0.35 });
  const standH = opts.stand === false ? 0 : 0.5;
  if (standH) {
    for (let i = 0; i < 3; i++) {
      const a = (i / 3) * TAU + 0.3;
      g.add(rod(0.018, [Math.sin(a) * 0.2, 0.01, Math.cos(a) * 0.2], [Math.sin(a) * 0.13, standH, Math.cos(a) * 0.13], mt.teak, { rb: 0.014, seg: 8 }));
    }
    g.add(K.m(K.tube(ring(0.17, 16, 0.2), 0.012, { seg: 18, radial: 5, closed: true }), mt.teak));
    g.add(K.m(puck(0.17, 0.025, 0.008, 20), mt.teak, { pos: [0, standH - 0.025, 0] }));
  }
  put(g, potGroup(game, opts.pot ?? 'bands', 0.15, 0.2), [0, standH, 0]);
  const fronds = K.leafCluster({ count: 20, len: [0.45, 0.62], width: 0.2, a0: [0.7, 1.35], a1: [-1.5, -0.7], fold: 0.08, seed: opts.seed ?? 4, spread: 0.05, vary: 0.25, segL: 7 });
  K.tint(fronds, '#4E8A34');
  g.add(K.m(fronds, fm, { pos: [0, standH + 0.18, 0] }));
  const inner = K.leafCluster({ count: 8, len: [0.3, 0.4], width: 0.16, a0: [1.2, 1.5], a1: [0.2, 0.7], fold: 0.08, seed: (opts.seed ?? 4) + 7, spread: 0.02, vary: 0.2, segL: 6 });
  K.tint(inner, '#6AAA44');
  g.add(K.m(inner, fm, { pos: [0, standH + 0.18, 0] }));
  g.userData.colliders = [{ min: [-0.22, 0, -0.22], max: [0.22, standH + 0.7, 0.22] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['plant', 'lobby', 'green_room', 'newsroom'], size: [1.0, 1.15, 1.0], desc: 'Boston fern with arching fronds in a banded pot on a teak tripod stand (opts.stand=false, opts.pot, opts.seed)' });

// ------------------------------------------------------------------------------------------- snake plant
registerProp('plant_snake', (game, opts = {}) => {
  const g = K.prop('plant_snake');
  const sm = leafMat(game, snakeTex(), { rough: 0.45, rim: 0.3 });
  g.add(potGroup(game, opts.pot ?? 'mustard', 0.14, 0.3));
  const rnd = mulberry32((opts.seed ?? 5) * 71 + 9);
  const leaves = [];
  for (let i = 0; i < 11; i++) {
    const a = i * 2.39996 + rnd() * 0.3, len = 0.45 + rnd() * 0.4;
    const lf = K.leaf(len, 0.075 + rnd() * 0.03, { a0: 1.52, a1: 1.15 + rnd() * 0.3, fold: 0.28, tip: 1.3, segL: 6, segW: 2, twist: (rnd() - 0.5) * 1.2 });
    lf.rotateY(a);
    const d = 0.02 + rnd() * 0.06;
    lf.translate(Math.sin(a) * d, 0.26, Math.cos(a) * d);
    leaves.push(lf);
  }
  g.add(K.m(mergeGeometries(leaves, false), sm));
  g.userData.colliders = [{ min: [-0.16, 0, -0.16], max: [0.16, 1.0, 0.16] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['plant', 'lobby', 'green_room', 'master_control'], size: [0.4, 1.1, 0.4], desc: 'snake plant: banded sword leaves with yellow edges in a mustard cylinder pot (opts.pot, opts.seed)' });

// -------------------------------------------------------------------------------------------- macrame owl
function jute(game) {
  const t = K.tex.canvas('furn_knots', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#B89A6A'; ctx.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 32) for (let x = (y / 32) % 2 ? 16 : 0; x < w + 16; x += 32) {
      const gr = ctx.createRadialGradient(x - 4, y - 4, 2, x, y, 18); gr.addColorStop(0, '#FFF4DA'); gr.addColorStop(0.7, '#E2CCA0'); gr.addColorStop(1, '#9A7E52');
      ctx.fillStyle = gr; ctx.beginPath(); ctx.ellipse(x, y, 15, 13, 0.3, 0, TAU); ctx.fill();
      ctx.strokeStyle = 'rgba(120,90,50,0.5)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(x - 10, y - 6); ctx.quadraticCurveTo(x, y + 4, x + 10, y - 6); ctx.stroke();
    }
    for (let i = 0; i < 300; i++) { ctx.fillStyle = rand() < 0.5 ? 'rgba(255,240,210,0.4)' : 'rgba(90,60,30,0.3)'; ctx.fillRect(rand() * w, rand() * h, 3, 1); }
  });
  return K.mat(game, 'fabric', '#ffffff', { map: t, rim: 0.2, rimPower: 3 });
}
registerProp('macrame_owl', (game) => {
  const g = K.prop('macrame_owl');
  const mt = M(game), jm = jute(game);
  const cream = '#F2E2C0', tan = '#D2B283', brown = '#6A4428';
  // driftwood branch (mount point at y = 0) + hanging V cords
  g.add(K.m(tc(K.tube([[-0.3, 0.005, -0.03], [-0.1, -0.01, -0.035], [0.12, 0.004, -0.03], [0.3, -0.012, -0.03]], 0.018, { seg: 12, radial: 6 }), '#9A8470'), mt.paint));
  g.add(K.m(tc(K.tube([[-0.2, 0, -0.04], [0, 0.14, -0.04], [0.2, 0, -0.04]], 0.005, { seg: 8, radial: 4 }), tan), jm));
  // knotted body + wings
  const body = K.m(tc(K.uvScale(sph(1, 18, 14).clone(), 3, 2), cream), jm, { pos: [0, -0.33, -0.05], scale: [0.2, 0.27, 0.05] });
  g.add(body);
  for (const s of [-1, 1]) g.add(K.m(tc(K.uvScale(sph(1, 12, 10).clone(), 2, 2), tan), jm, { pos: [s * 0.17, -0.37, -0.06], scale: [0.07, 0.18, 0.04], rot: [0, 0, s * 0.25] }));
  // eyes: wooden rings, knotted discs, bead pupils; beak; ear tassels; bead feet
  for (const s of [-1, 1]) {
    g.add(K.m(tc(new THREE.TorusGeometry(0.062, 0.013, 6, 18), brown), mt.lacquer, { pos: [s * 0.075, -0.22, -0.1] }));
    g.add(K.m(tc(K.uvScale(new THREE.CircleGeometry(0.056, 16).clone(), 0.6, 0.6), '#FFF4E0'), jm, { pos: [s * 0.075, -0.22, -0.098], rot: [0, Math.PI, 0] }));
    g.add(K.m(tc(sph(0.022, 10, 8), '#2A1A14'), mt.lacquer, { pos: [s * 0.075, -0.22, -0.108] }));
    g.add(K.m(tc(K.tube([[s * 0.09, -0.1, -0.07], [s * 0.13, -0.03, -0.07], [s * 0.15, 0.0, -0.075]], 0.008, { seg: 6, radial: 4 }), tan), jm));
    g.add(K.m(tc(sph(0.016, 8, 6), brown), mt.lacquer, { pos: [s * 0.05, -0.6, -0.08] }));
  }
  g.add(K.m(tc(K.lathe([[0, 0], [0.02, 0.005], [0, 0.05]], { seg: 8 }), '#C86A2A'), mt.lacquer, { pos: [0, -0.27, -0.11], rot: [Math.PI, 0, 0] }));
  // fringe
  const rnd = mulberry32(77);
  for (let i = 0; i < 14; i++) {
    const x = -0.13 + (i / 13) * 0.26, len = 0.16 + Math.sin((i / 13) * Math.PI) * 0.14 + rnd() * 0.04;
    g.add(K.m(tc(K.tube([[x, -0.56, -0.05], [x + (rnd() - 0.5) * 0.02, -0.56 - len * 0.5, -0.045], [x + (rnd() - 0.5) * 0.03, -0.56 - len, -0.04]], 0.006, { seg: 5, radial: 4 }), i % 3 ? cream : tan), jm));
  }
  wallFit(g);
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['wall', 'decor', 'lobby', 'green_room'], size: [0.6, 1.02, 0.13], desc: 'macramé owl wall hanging on driftwood: wooden-ring eyes, knotted body, fringe (wall prop; bottom at ~1.1 m)' });

// ------------------------------------------------------------------------------------ macrame plant hanger
registerProp('macrame_hanger', (game, opts = {}) => {
  const g = K.prop('macrame_hanger');
  const mt = M(game), jm = jute(game);
  const drop = opts.drop ?? 0.8;
  const tan = '#E2CCA0';
  const lm = leafMat(game, leafTex(), { rough: 0.4, rim: 0.3 });
  g.add(K.m(new THREE.TorusGeometry(0.035, 0.007, 6, 16), mt.brass, { pos: [0, -0.04, 0] }));
  const knotY = -0.12, potY = -drop;
  g.add(K.m(tc(sph(0.03, 10, 8), tan), jm, { pos: [0, knotY, 0], scale: [1, 1.5, 1] }));
  // 4 cord pairs: gather -> spread -> diamond knots -> cradle under the pot -> gather + tassel
  const r0 = 0.2;
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * TAU + Math.PI / 4, a2 = a + Math.PI / 4;
    const pts = [[0, knotY - 0.02, 0], [Math.cos(a) * 0.08, potY + drop * 0.35, Math.sin(a) * 0.08], [Math.cos(a) * r0 * 0.9, potY + 0.2, Math.sin(a) * r0 * 0.9], [Math.cos(a) * r0 * 1.05, potY + 0.02, Math.sin(a) * r0 * 1.05], [Math.cos(a) * r0 * 0.7, potY - 0.16, Math.sin(a) * r0 * 0.7], [0, potY - 0.24, 0]];
    g.add(K.m(tc(K.tube(pts, 0.007, { seg: 20, radial: 4 }), tan), jm));
    g.add(K.m(tc(sph(0.018, 6, 4), '#F2E2C0'), jm, { pos: [Math.cos(a) * 0.12, potY + drop * 0.18, Math.sin(a) * 0.12] }));
    g.add(K.m(tc(sph(0.013, 6, 4), '#8A5A2A'), mt.lacquer, { pos: [Math.cos(a2) * r0 * 0.98, potY + 0.12, Math.sin(a2) * r0 * 0.98] }));
  }
  put(g, potGroup(game, opts.pot ?? 'terracotta', 0.17, 0.2), [0, potY - 0.16, 0]);
  g.add(K.m(tc(sph(0.035, 10, 8), tan), jm, { pos: [0, potY - 0.25, 0], scale: [1, 1.4, 1] }));
  const rnd = mulberry32(19);
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * TAU, len = 0.2 + rnd() * 0.12;
    g.add(K.m(tc(K.tube([[Math.cos(a) * 0.012, potY - 0.28, Math.sin(a) * 0.012], [Math.cos(a) * 0.03, potY - 0.28 - len, Math.sin(a) * 0.03]], 0.005, { seg: 2, radial: 4 }), tan), jm));
  }
  // trailing pothos: vines over the rim with heart leaves
  const leaves = [];
  for (let v = 0; v < 6; v++) {
    const a = v * 1.05 + 0.3, L = 0.25 + rnd() * 0.35;
    const vine = [];
    for (let k = 0; k <= 5; k++) {
      const t = k / 5, rr = 0.15 + t * 0.06;
      vine.push([Math.cos(a + t * 0.4) * rr, potY + 0.04 - t * L + Math.sin(t * 3) * 0.02, Math.sin(a + t * 0.4) * rr]);
    }
    g.add(K.m(tc(K.tube(vine, 0.004, { seg: 10, radial: 3 }), '#4E7A30'), mt.paint));
    for (let k = 1; k <= 5; k++) {
      const p = vine[k];
      const lf = K.leaf(0.07, 0.06, { a0: -0.3, a1: -1.2, fold: 0.2, tip: 0.7, segL: 4, segW: 1 });
      lf.rotateY(a + Math.PI / 2 + (k % 2 ? 0.7 : -0.7));
      lf.translate(p[0], p[1], p[2]);
      K.tint(lf, new THREE.Color(k % 2 ? '#5A9A3A' : '#8AB84A'));
      leaves.push(lf);
    }
  }
  const crown = K.leafCluster({ count: 8, len: [0.1, 0.14], width: 0.09, a0: [0.5, 1.0], a1: [-0.6, 0.0], fold: 0.2, seed: 3, spread: 0.04, segL: 5 });
  crown.translate(0, potY + 0.02, 0);
  K.tint(crown, '#5A9A3A');
  leaves.push(crown);
  g.add(K.m(mergeGeometries(leaves.map((l) => (l.index ? l.toNonIndexed() : l)), false), lm));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['ceiling', 'plant', 'decor', 'green_room', 'lobby'], size: [0.5, 1.4, 0.5], desc: 'macramé plant hanger with a terracotta pot and trailing pothos (ceiling origin; opts.drop, opts.pot)' });

// -------------------------------------------------------------------------------------------- water cooler
registerProp('water_cooler', (game) => {
  const g = K.prop('water_cooler');
  const mt = M(game), dm = decorMat(game);
  const body = '#EDE6D6';
  g.add(K.m(tc(K.box(0.32, 0.9, 0.32, 0.04), body), mt.lacquer, { pos: [0, 0.47, 0] }));
  g.add(K.m(tc(K.box(0.3, 0.03, 0.3, 0.01), '#3A2E36'), mt.plastic, { pos: [0, 0.015, 0] }));
  g.add(K.m(tc(K.box(0.325, 0.03, 0.325, 0.012), '#2F5BD3'), mt.lacquer, { pos: [0, 0.8, 0] }));
  g.add(K.m(dcell(cbox(0.2, 0.2, 0.006, 0.002), 0, 0), dm, { pos: [0, 0.4, -0.162] }));
  // tap well: dark recess, two tap levers (blue / red), drip grate
  g.add(K.m(tc(K.box(0.22, 0.16, 0.05, 0.012), '#3A2E36'), mt.plastic, { pos: [0, 0.66, -0.145] }));
  for (const [x, c] of [[-0.05, '#2F5BD3'], [0.05, '#E23B3B']]) {
    g.add(K.m(K.cyl(0.012, 0.014, 0.03, { seg: 10 }), mt.chrome, { pos: [x, 0.7, -0.17], rot: [Math.PI / 2, 0, 0] }));
    g.add(K.m(tc(K.box(0.03, 0.05, 0.018, 0.008), c), mt.plastic, { pos: [x, 0.735, -0.19] }));
  }
  g.add(K.m(K.box(0.18, 0.012, 0.07, 0.004), mt.chrome, { pos: [0, 0.59, -0.16] }));
  for (let i = 0; i < 5; i++) g.add(K.m(tc(cbox(0.16, 0.004, 0.006, 0.001), '#2A2230'), mt.plastic, { pos: [0, 0.597, -0.185 + i * 0.012] }));
  // inverted 5-gallon jug: blue tinted glass shell + water inside (air bubble at the top)
  const jugP = [[0, 0], [0.04, 0], [0.045, 0.06], [0.12, 0.13], [0.135, 0.18], [0.135, 0.42], [0.12, 0.47], [0, 0.49]];
  const glass = game.mats.glass('#9FD8FF', { opacity: 0.3 });
  const jug = K.m(K.lathe(jugP, { seg: 18, round: 0.02, steps: 1 }), glass, { pos: [0, 0.89, 0] });
  jug.userData.noAO = true; jug.userData.noOcclude = true;
  g.add(jug);
  for (const y of [0.24, 0.33]) g.add(K.m(K.tube(ring(0.137, 18, 0.89 + y), 0.005, { seg: 18, radial: 3, closed: true }), glass));
  const water = K.m(K.lathe([[0, 0.01], [0.034, 0.01], [0.04, 0.06], [0.115, 0.13], [0.128, 0.18], [0.128, 0.36], [0, 0.36]], { seg: 16 }), K.mat(game, 'plastic', '#3FA8E8', { transparent: true, opacity: 0.55, keepColor: true }), { pos: [0, 0.89, 0] });
  water.userData.noOcclude = true;
  g.add(water);
  g.add(K.m(tc(K.lathe([[0, 0], [0.07, 0], [0.075, 0.03], [0.05, 0.05], [0, 0.05]], { seg: 16 }), body), mt.lacquer, { pos: [0, 0.91, 0] }));
  // paper cone cup dispenser on the side
  g.add(K.m(K.cyl(0.035, 0.035, 0.22, { seg: 12 }), mt.chrome, { pos: [0.2, 0.46, 0] }));
  g.add(K.m(tc(K.lathe([[0.004, 0], [0.032, 0.07], [0.03, 0.07], [0, 0.005]], { seg: 10 }), '#FBF6EA'), mt.plastic, { pos: [0.2, 0.39, 0] }));
  g.add(K.m(K.box(0.03, 0.08, 0.02, 0.006), mt.chrome, { pos: [0.17, 0.52, 0] }));
  g.userData.colliders = [{ min: [-0.17, 0, -0.18], max: [0.24, 1.4, 0.17] }];
  g.userData.interact = { point: [0, 0.72, -0.25], radius: 1 };
  return K.finish(game, g);
}, { category: CAT, tags: ['newsroom', 'green_room', 'appliance'], size: [0.45, 1.4, 0.35], desc: 'cream water cooler: inverted blue jug, hot/cold taps, drip grate, AQUA-PURE label, cone cups' });

// ------------------------------------------------------------------------------------------ filing cabinet
registerProp('filing_cabinet', (game, opts = {}) => {
  const g = K.prop('filing_cabinet');
  const mt = M(game), atl = atlasMat(game);
  const col = opts.color ?? '#C9A45A';
  const n = opts.drawers ?? 4;
  const W = 0.46, D = 0.64, dh = 0.3, H = n * (dh + 0.01) + 0.08;
  const dark = new THREE.Color(col).multiplyScalar(0.55).getStyle();
  g.add(K.m(tc(K.box(W, H - 0.05, D, 0.02), col), mt.paint, { pos: [0, (H - 0.05) / 2 + 0.05, 0] }));
  g.add(K.m(tc(K.box(W - 0.04, 0.05, D - 0.06, 0.01), dark), mt.paint, { pos: [0, 0.025, 0] }));
  g.add(K.m(tc(K.box(W + 0.01, 0.018, D + 0.01, 0.008), col), mt.paint, { pos: [0, H, 0] }));
  for (let i = 0; i < n; i++) {
    const y = 0.07 + dh / 2 + i * (dh + 0.01);
    const ajar = i === n - 1 && opts.ajar !== false ? 0.14 : 0;
    const dr = new THREE.Group();
    dr.position.set(0, y, -D / 2 - ajar);
    dr.add(K.m(tc(K.box(W - 0.03, dh - 0.012, 0.03, 0.014), col), mt.paint, { pos: [0, 0, -0.005] }));
    dr.add(K.m(K.tube([[-0.08, 0.03, 0], [-0.075, 0.03, -0.024], [0.075, 0.03, -0.024], [0.08, 0.03, 0]], 0.008, { seg: 8, radial: 5 }), mt.chrome));
    dr.add(K.m(cbox(0.03, 0.02, 0.012, 0.004), mt.chrome, { pos: [0, 0.052, -0.022] }));
    dr.add(K.m(cbox(0.1, 0.05, 0.008, 0.003), mt.chrome, { pos: [0, -0.04, -0.024] }));
    dr.add(K.m(cell(cbox(0.085, 0.036, 0.004, 0.001), 1, 2), atl, { pos: [0, -0.04, -0.029] }));
    if (ajar) {
      dr.add(K.m(tc(K.box(W - 0.06, dh - 0.05, ajar + 0.02, 0.01), dark), mt.paint, { pos: [0, -0.01, ajar / 2 + 0.01] }));
      for (let f = 0; f < 5; f++) dr.add(K.m(cell(cbox(W - 0.1, 0.09 + (f % 2) * 0.02, 0.004, 0.001), 3, 3), atl, { pos: [(f - 2) * 0.004, dh / 2 - 0.02, 0.03 + f * 0.024], rot: [-0.12 + f * 0.05, 0, (f - 2) * 0.03] }));
    }
    g.add(dr);
  }
  put(g, paperStack(game, 4, 11), [0.02, H + 0.009, 0.08], 0.2);
  put(g, mugGroup(game), [-0.13, H + 0.009, -0.16], 1.0);
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2 - 0.05], max: [W / 2, H + 0.1, D / 2] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['cabinet', 'newsroom', 'master_control'], size: [0.47, 1.4, 0.8], desc: 'harvest steel 4-drawer filing cabinet, chrome pulls, label cards, top drawer ajar with folders (opts.color, opts.drawers, opts.ajar=false)' });

// ---------------------------------------------------------------------------------------------- coat rack
registerProp('coat_rack', (game) => {
  const g = K.prop('coat_rack');
  const mt = M(game);
  const H = 1.8;
  // bentwood: four curved feet, turned pole, two rings of hooks with ball ends, finial
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * TAU + Math.PI / 4;
    const c = Math.cos(a), s = Math.sin(a);
    g.add(K.m(K.tube([[c * 0.03, 0.22, s * 0.03], [c * 0.16, 0.1, s * 0.16], [c * 0.27, 0.025, s * 0.27], [c * 0.3, 0.02, s * 0.3]], 0.018, { seg: 8, radial: 6 }), mt.walnut));
    g.add(K.m(new THREE.CylinderGeometry(0.018, 0.02, 0.02, 8, 1).translate(0, 0.01, 0), mt.brass, { pos: [c * 0.3, 0, s * 0.3] }));
  }
  g.add(K.m(K.uvScale(K.lathe([[0, 0], [0.04, 0], [0.045, 0.06], [0.028, 0.16], [0.024, 0.3], [0.024, H - 0.2], [0.03, H - 0.14], [0.03, H - 0.1], [0.022, H - 0.06], [0, H - 0.05]], { seg: 10, round: 0.01, steps: 1 }).clone(), 2, 4), mt.walnut, { pos: [0, 0.18, 0] }));
  g.add(K.m(sph(0.045, 10, 7), mt.walnut, { pos: [0, H + 0.16, 0] }));
  const hooks = [];
  for (const [y, n, off, L] of [[H - 0.02, 6, 0, 0.2], [H - 0.26, 3, Math.PI / 3, 0.14]]) {
    for (let i = 0; i < n; i++) {
      const a = (i / n) * TAU + off;
      const c = Math.cos(a), s = Math.sin(a);
      const tip = [c * L, y + 0.1, s * L];
      g.add(K.m(K.tube([[c * 0.02, y - 0.06, s * 0.02], [c * L * 0.6, y - 0.02, s * L * 0.6], [c * L, y + 0.04, s * L], tip], 0.011, { seg: 7, radial: 4 }), mt.walnut));
      g.add(K.m(sph(0.017, 6, 4), mt.walnut, { pos: tip }));
      hooks.push([c, s, y, L]);
    }
  }
  // fedora on a top hook
  const [hc, hs, hy, hl] = hooks[1];
  const hat = new THREE.Group();
  hat.position.set(hc * hl * 0.95, hy + 0.1, hs * hl * 0.95);
  hat.rotation.set(0.35, -Math.atan2(hs, hc), 0.25);
  hat.add(K.m(tc(K.lathe([[0, 0], [0.17, 0], [0.18, 0.012], [0.11, 0.02], [0.1, 0.1], [0.07, 0.13], [0, 0.12]], { seg: 16, round: 0.012, steps: 1 }), '#5A3A22'), mt.velvet));
  hat.add(K.m(tc(K.lathe([[0.104, 0], [0.101, 0.03], [0, 0.03]], { seg: 20 }).clone(), '#E3662B'), mt.velvet, { pos: [0, 0.018, 0] }));
  g.add(hat);
  // mustard knit scarf draped over a hook
  const [sc, ss, sy, sl] = hooks[3];
  const px = sc * sl * 0.85, pz = ss * sl * 0.85, ya = Math.atan2(sc, ss);
  const knit = tc(K.cushion(0.13, 0.62, 0.024, { puff: 0.008, r: 0.01, seg: [3, 6, 1], uv: 4 }), '#D9A520');
  for (const s2 of [-1, 1]) {
    const pnl = K.m(knit, mt.tweed);
    pnl.position.set(px + sc * s2 * 0.02, sy - 0.24 + (s2 > 0 ? 0.05 : 0), pz + ss * s2 * 0.02);
    pnl.rotation.set(0, ya, 0);
    pnl.rotateX(s2 * 0.08);
    g.add(pnl);
  }
  g.add(K.m(tc(K.tube([[px - sc * 0.03, sy + 0.04, pz - ss * 0.03], [px, sy + 0.075, pz], [px + sc * 0.03, sy + 0.04, pz + ss * 0.03]], 0.02, { seg: 6, radial: 6 }), '#D9A520'), mt.tweed));
  for (let f = 0; f < 4; f++) for (const s2 of [-1, 1]) {
    const fx = px + sc * s2 * 0.02 + Math.cos(ya) * (f - 1.5) * 0.03, fz = pz + ss * s2 * 0.02 - Math.sin(ya) * (f - 1.5) * 0.03;
    const fy = sy - 0.55 + (s2 > 0 ? 0.05 : 0);
    g.add(K.m(tc(K.tube([[fx, fy, fz], [fx, fy - 0.06, fz]], 0.006, { seg: 1, radial: 4 }), '#E8B83A'), mt.tweed));
  }
  // WZTV satin crew jacket hanging by its collar loop
  const [jc, js, jy, jl] = hooks[5];
  const jk = new THREE.Group();
  jk.position.set(jc * jl * 0.95, jy + 0.06, js * jl * 0.95);
  jk.rotation.y = Math.atan2(jc, js);
  jk.scale.setScalar(0.82);
  const blue = '#2F5BD3';
  jk.add(K.m(tc(K.cushion(0.36, 0.56, 0.1, { puff: 0.03, r: 0.04, seg: [5, 6, 2], uv: 3 }), blue), mt.velvet, { pos: [0, -0.34, 0.06] }));
  jk.add(K.m(tc(K.cushion(0.26, 0.08, 0.1, { puff: 0.02, r: 0.03, seg: [4, 2, 2] }), '#E23B3B'), mt.velvet, { pos: [0, -0.08, 0.06] }));
  for (const s2 of [-1, 1]) {
    jk.add(K.m(tc(K.tube([[s2 * 0.16, -0.12, 0.06], [s2 * 0.2, -0.3, 0.07], [s2 * 0.17, -0.55, 0.06]], 0.05, { seg: 8, radial: 7 }), blue), mt.velvet));
    jk.add(K.m(tc(new THREE.CylinderGeometry(0.048, 0.048, 0.05, 8, 1), '#F4F1E8'), mt.velvet, { pos: [s2 * 0.17, -0.6, 0.06] }));
  }
  jk.add(K.m(tc(cbox(0.36, 0.05, 0.105, 0.012), '#F4F1E8'), mt.velvet, { pos: [0, -0.6, 0.06] }));
  jk.add(K.m(cell(new THREE.CircleGeometry(0.075, 20), 3, 1), atlasMat(game), { pos: [0, -0.3, 0.113] }));
  g.add(jk);
  g.userData.colliders = [{ min: [-0.25, 0, -0.25], max: [0.25, H + 0.2, 0.25] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['green_room', 'lobby', 'newsroom'], size: [0.62, 2.0, 0.62], desc: 'bentwood walnut coat tree with a fedora, a mustard scarf and a rust umbrella' });

// ------------------------------------------------------------------------------------------------ trash can
function paperBall(r, seed) {
  const geo = new THREE.IcosahedronGeometry(r, 1);
  const p = geo.attributes.position, rnd = mulberry32(seed);
  const cache = new Map();
  for (let i = 0; i < p.count; i++) {
    const key = `${p.getX(i).toFixed(4)},${p.getY(i).toFixed(4)},${p.getZ(i).toFixed(4)}`;
    let k = cache.get(key);
    if (k === undefined) { k = 0.75 + rnd() * 0.45; cache.set(key, k); }
    p.setXYZ(i, p.getX(i) * k, p.getY(i) * k, p.getZ(i) * k);
  }
  geo.computeVertexNormals();
  return geo;
}
registerProp('trash_can', (game, opts = {}) => {
  const g = K.prop('trash_can');
  const mt = M(game);
  const col = opts.color ?? '#E3662B';
  const R = 0.15, H = 0.36;
  g.add(K.m(tc(K.lathe([[0, 0], [R * 0.8, 0], [R, H - 0.01], [R + 0.012, H], [R - 0.008, H], [R * 0.8 - 0.01, 0.015], [0, 0.015]], { seg: 24, round: 0.008, steps: 1 }), col), mt.plastic));
  g.add(K.m(tc(K.tube(ring(R + 0.004, 24, H), 0.012, { seg: 24, radial: 5, closed: true }), col), mt.plastic));
  const rnd = mulberry32(5);
  const balls = [[0, H - 0.02, 0, 0.07], [0.06, H + 0.02, 0.03, 0.06], [-0.05, H + 0.03, -0.03, 0.055], [0.01, H + 0.07, -0.01, 0.05], [-0.04, H - 0.01, 0.06, 0.05]];
  balls.forEach(([x, y, z, r], i) => g.add(K.m(tc(paperBall(r, 10 + i), i === 3 ? '#FFE36A' : '#FBF6EA'), mt.paint, { pos: [x, y, z], rot: [rnd() * 3, rnd() * 3, 0] })));
  g.add(K.m(tc(paperBall(0.055, 40), '#FBF6EA'), mt.paint, { pos: [0.24, 0.045, -0.08] }));
  g.userData.colliders = [{ min: [-R, 0, -R], max: [R, H, R] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['trash', 'newsroom', 'master_control', 'green_room'], size: [0.36, 0.45, 0.32], desc: 'orange plastic wastebasket overflowing with crumpled scripts, one on the floor (opts.color)' });

// ------------------------------------------------------------------------------------------------ ash urn
registerProp('ash_urn', (game, opts = {}) => {
  const g = K.prop('ash_urn');
  const mt = M(game);
  const col = opts.color ?? '#8C9A3A';
  g.add(K.m(tc(K.lathe([[0, 0], [0.16, 0], [0.165, 0.02], [0.13, 0.08], [0.12, 0.5], [0.15, 0.56], [0, 0.56]], { seg: 24, round: 0.015, steps: 1 }), col), mt.lacquer));
  g.add(K.m(K.lathe([[0, 0], [0.155, 0], [0.175, 0.03], [0.17, 0.05], [0.14, 0.04], [0, 0.04]], { seg: 24, round: 0.008, steps: 1 }), mt.chrome, { pos: [0, 0.56, 0] }));
  g.add(K.m(K.uvScale(tc(new THREE.CircleGeometry(0.14, 20), '#E8D8B0'), 3, 3), K.mat(game, 'soil', '#ffffff', { map: K.tex.pebble('#E0CFA0') }), { pos: [0, 0.6, 0], rot: [-Math.PI / 2, 0, 0] }));
  for (const [x, z, a] of [[0.04, 0.03, 0.4], [-0.05, -0.02, 2.1]]) {
    g.add(K.m(tc(K.cyl(0.005, 0.005, 0.04, { seg: 6, bevel: 0.001 }), '#FBF6EA'), mt.paint, { pos: [x, 0.603, z], rot: [Math.PI / 2 - 0.2, a, 0] }));
  }
  g.userData.colliders = [{ min: [-0.17, 0, -0.17], max: [0.17, 0.62, 0.17] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['lobby', 'green_room', 'trash'], size: [0.35, 0.62, 0.35], desc: 'avocado enamel lobby ash urn with a chrome sand bowl (opts.color)' });

// ------------------------------------------------------------------------------------------ soda machine
function sodaTex() {
  // 512x1024: [0..384] sign art, [384..512] selection-button labels column
  return K.tex.canvas('furn_soda', 512, 1024, (ctx, W, H, rand) => {
    const g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, '#FFF4D6'); g.addColorStop(1, '#FFD9A0');
    ctx.fillStyle = g; ctx.fillRect(0, 0, 384, H);
    // bubbles
    for (let i = 0; i < 70; i++) { ctx.strokeStyle = 'rgba(227,59,59,0.35)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(rand() * 384, rand() * H, 4 + rand() * 16, 0, TAU); ctx.stroke(); }
    // red wave band + script logo
    ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.moveTo(0, 120); ctx.bezierCurveTo(130, 60, 250, 190, 384, 110); ctx.lineTo(384, 330); ctx.bezierCurveTo(250, 400, 130, 270, 0, 340); ctx.fill();
    ctx.save(); ctx.translate(192, 230); ctx.rotate(-0.12);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = '110px "Shrikhand", "Cooper Black", serif'; ctx.fillStyle = '#7A1A1A'; ctx.fillText('Fizz', 6, 8);
    ctx.fillStyle = '#FFF4D6'; ctx.fillText('Fizz', 0, 0);
    ctx.font = '40px "Bungee", "Arial Black", sans-serif'; ctx.fillText('- UP -', 0, 70);
    ctx.restore();
    // giant tilted can
    ctx.save(); ctx.translate(200, 650); ctx.rotate(0.18);
    const cg = ctx.createLinearGradient(-90, 0, 90, 0); cg.addColorStop(0, '#9A1A1A'); cg.addColorStop(0.35, '#FF5A4A'); cg.addColorStop(0.6, '#E23B3B'); cg.addColorStop(1, '#7A1212');
    ctx.fillStyle = cg; ctxRR(ctx, -90, -190, 180, 380, 30); ctx.fill();
    ctx.fillStyle = '#C9CED6'; ctxRR(ctx, -84, -205, 168, 26, 10); ctx.fill(); ctxRR(ctx, -84, 180, 168, 22, 10); ctx.fill();
    ctx.fillStyle = '#FFF4D6'; ctx.font = '64px "Shrikhand", "Cooper Black", serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.save(); ctx.rotate(-Math.PI / 2); ctx.fillText('Fizz-Up', 0, 6); ctx.restore();
    ctx.restore();
    ctx.fillStyle = '#E23B3B'; ctx.font = '46px "Bungee", "Arial Black", sans-serif'; ctx.textAlign = 'center';
    ctx.fillText('ICE COLD', 192, 930); ctx.font = '30px "Titan One", "Arial Black", sans-serif'; ctx.fillStyle = '#5A1A1A'; ctx.fillText('25¢', 192, 980);
    // button labels
    const flav = [['COLA', '#7A2A1A'], ['ORANGE', '#E3662B'], ['GRAPE', '#6B3A6E'], ['LEMON', '#C8B020'], ['ROOT BEER', '#5A3A22'], ['DIET', '#2F5BD3']];
    flav.forEach(([t, c], i) => {
      const y = i * (H / 6);
      ctx.fillStyle = '#FFF8E8'; ctx.fillRect(384, y, 128, H / 6);
      ctx.fillStyle = c; ctx.fillRect(392, y + 20, 112, H / 6 - 40);
      ctx.fillStyle = '#FFF8E8'; ctx.font = `${t.length > 6 ? 17 : 24}px "Bungee", "Arial Black", sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(t, 448, y + H / 12);
    });
    void W;
  }, { repeat: false, fonts: true });
}
registerProp('vending_soda', (game, opts = {}) => {
  const g = K.prop('vending_soda');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const body = opts.color ?? '#D8342C';
  const W = 0.95, H = 1.84, D = 0.78, fz = -D / 2;
  const tex = sodaTex();
  const sign = lit ? K.glow(game, '#ffffff', 0.7, { map: tex }) : K.mat(game, 'plastic', '#C8B8A0', { map: tex });
  g.add(K.m(tc(K.box(W - 0.06, 0.06, D - 0.06, 0.015), '#2A2230'), mt.plastic, { pos: [0, 0.03, 0] }));
  g.add(K.m(tc(K.box(W, H - 0.12, D, 0.06), body), mt.lacquer, { pos: [0, 0.06 + (H - 0.12) / 2, 0] }));
  g.add(K.m(tc(K.cushion(W + 0.03, 0.1, D + 0.03, { puff: 0.02, r: 0.045, seg: [6, 2, 5] }), '#F6E7C8'), mt.lacquer, { pos: [0, H - 0.05, 0] }));
  // cream side stripes
  for (const s of [-1, 1]) g.add(K.m(tc(K.box(0.012, H - 0.3, 0.16, 0.005), '#F6E7C8'), mt.lacquer, { pos: [s * (W / 2 + 0.002), 0.95, -0.12] }));
  // glowing sign panel with chrome frame
  const sw = 0.56, sh = 1.2, sx = -0.14, sy = 1.08;
  const frame = K.roundRect(sw + 0.06, sh + 0.06, 0.05);
  frame.holes.push(new THREE.Path(K.roundRect(sw, sh, 0.035).getPoints(6)));
  g.add(K.m(K.extrude(frame, 0.03, { bevel: 0.01, bevelSeg: 1, curveSeg: 4 }), mt.chrome, { pos: [sx, sy, fz - 0.01] }));
  const panel = K.m(K.uvRect(new THREE.PlaneGeometry(sw, sh), 0, 0, 0.75, 1), sign, { pos: [sx, sy, fz - 0.006], rot: [0, Math.PI, 0] });
  panel.userData.noMerge = true; panel.userData.noOcclude = true;
  g.add(panel);
  // selection buttons column (lit labels + chrome bezels)
  const bx = 0.31;
  const col = K.m(K.uvRect(new THREE.PlaneGeometry(0.16, 0.6), 0.75, 0, 1, 1), sign, { pos: [bx, 1.25, fz - 0.006], rot: [0, Math.PI, 0] });
  col.userData.noMerge = true; col.userData.noOcclude = true;
  g.add(col);
  for (let i = 0; i < 6; i++) g.add(K.m(K.box(0.17, 0.012, 0.02, 0.004), mt.chrome, { pos: [bx, 0.95 + i * 0.1, fz - 0.012] }));
  g.add(K.m(K.box(0.012, 0.6, 0.02, 0.004), mt.chrome, { pos: [bx - 0.085, 1.25, fz - 0.012] }));
  g.add(K.m(K.box(0.012, 0.6, 0.02, 0.004), mt.chrome, { pos: [bx + 0.085, 1.25, fz - 0.012] }));
  // coin plate + coin return
  g.add(K.m(K.box(0.16, 0.22, 0.03, 0.012), mt.chrome, { pos: [bx, 0.74, fz - 0.01] }));
  g.add(K.m(tc(K.box(0.012, 0.05, 0.01, 0.003), '#1E1530'), mt.plastic, { pos: [bx, 0.8, fz - 0.026] }));
  g.add(K.m(tc(K.cyl(0.025, 0.025, 0.02, { seg: 12 }), '#E23B3B'), mt.plastic, { pos: [bx, 0.7, fz - 0.03], rot: [Math.PI / 2, 0, 0] }));
  g.add(K.m(tc(K.box(0.07, 0.04, 0.03, 0.01), '#1E1530'), mt.plastic, { pos: [bx, 0.64, fz - 0.02] }));
  // can delivery door
  g.add(K.m(K.box(0.5, 0.2, 0.03, 0.02), mt.chrome, { pos: [sx, 0.3, fz - 0.01] }));
  g.add(K.m(tc(K.box(0.44, 0.15, 0.03, 0.015), '#1E1530'), mt.plastic, { pos: [sx, 0.3, fz - 0.02], rot: [0.12, 0, 0] }));
  g.add(K.m(tc(K.box(0.3, 0.035, 0.012, 0.006), '#F6E7C8'), mt.lacquer, { pos: [sx, 0.46, fz - 0.006] }));
  g.userData.parts = { glow: panel, glowButtons: col };
  g.userData.lightAnchors = lit ? [{ pos: [sx, 1.1, fz - 0.5], color: '#FFE2C0', intensity: 1.3, distance: 3.5 }] : [];
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2 - 0.04], max: [W / 2, H + 0.02, D / 2] }];
  g.userData.interact = { point: [bx, 1.0, fz - 0.4], radius: 1.2 };
  return K.finish(game, g);
}, { category: CAT, tags: ['machine', 'vending', 'green_room', 'light'], size: [0.98, 1.86, 0.82], desc: 'red Fizz-Up soda machine with a glowing sign, lit flavour buttons, coin plate, can door (parts.glow; opts.color, opts.lit)', hero: true });

// ------------------------------------------------------------------------------------- cigarette machine
function cigTex() {
  return K.tex.canvas('furn_cig', 512, 512, (ctx, W, H) => {
    // top 128: marquee; rest: pack display (3 rows x 6)
    const g = ctx.createLinearGradient(0, 0, 0, 128); g.addColorStop(0, '#FFE3A3'); g.addColorStop(1, '#FFB347');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, 128);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillStyle = '#6B2A1A'; ctx.font = '64px "Shrikhand", "Cooper Black", serif'; ctx.fillText('Cigarettes', W / 2, 60);
    ctx.fillStyle = '#B5472A'; ctx.font = '20px "Bungee", "Arial Black", sans-serif'; ctx.fillText('SERVE YOURSELF  ·  35¢', W / 2, 108);
    ctx.fillStyle = '#FFF4DA'; ctx.fillRect(0, 128, W, H - 128);
    const packs = [['STATIC', '#E23B3B', '#F4F1E8'], ['NIGHT OWL', '#2A3A8A', '#FFD23A'], ['SIGNAL', '#F4F1E8', '#2E8C8C'], ['HI-FI', '#E8A92E', '#5A3A22'], ['PLAZA', '#2E6A3A', '#F4F1E8'], ['KOOLTONE', '#7FD4FF', '#1E4A8A']];
    for (let r = 0; r < 3; r++) for (let c = 0; c < 6; c++) {
      const [name, bg, fg] = packs[(c + r * 2) % 6];
      const x = 8 + c * 84, y = 140 + r * 124;
      ctx.fillStyle = bg; ctxRR(ctx, x, y, 72, 110, 6); ctx.fill();
      ctx.fillStyle = fg; ctx.fillRect(x + 6, y + 36, 60, 30);
      ctx.fillStyle = bg; ctx.font = `${name.length > 6 ? 11 : 14}px "Bungee", "Arial Black", sans-serif`; ctx.fillText(name, x + 36, y + 52);
      ctx.fillStyle = fg; ctx.beginPath(); ctx.arc(x + 36, y + 88, 10, 0, TAU); ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.3)'; ctx.fillRect(x + 4, y + 4, 10, 100);
    }
  }, { repeat: false, fonts: true });
}
registerProp('vending_cigarette', (game, opts = {}) => {
  const g = K.prop('vending_cigarette');
  const mt = M(game);
  const lit = opts.lit ?? true;
  const W = 0.76, H = 1.46, D = 0.46, fz = -D / 2;
  const tex = cigTex();
  const glowM = lit ? K.glow(game, '#ffffff', 0.75, { map: tex }) : K.mat(game, 'plastic', '#C8B8A0', { map: tex });
  g.add(K.m(tc(K.box(W - 0.05, 0.08, D - 0.05, 0.015), '#2A2230'), mt.plastic, { pos: [0, 0.04, 0] }));
  g.add(K.m(K.box(W, H - 0.08, D, 0.045, { uv: 1.5, swap: true }), mt.walnut, { pos: [0, 0.08 + (H - 0.08) / 2, 0] }));
  g.add(K.m(K.box(W + 0.01, 0.03, D + 0.01, 0.012), mt.chrome, { pos: [0, H, 0] }));
  // lit marquee + pack window (one glow material, atlas halves)
  const mq = K.m(K.uvRect(new THREE.PlaneGeometry(0.66, 0.17), 0, 0.75, 1, 1), glowM, { pos: [0, H - 0.13, fz - 0.006], rot: [0, Math.PI, 0] });
  const win = K.m(K.uvRect(new THREE.PlaneGeometry(0.66, 0.5), 0, 0, 1, 0.75), glowM, { pos: [0, 1.0, fz - 0.006], rot: [0, Math.PI, 0] });
  for (const p of [mq, win]) { p.userData.noMerge = true; p.userData.noOcclude = true; g.add(p); }
  for (const [y, h] of [[H - 0.13, 0.17], [1.0, 0.5]]) {
    const fr = K.roundRect(0.7, h + 0.04, 0.025);
    fr.holes.push(new THREE.Path(K.roundRect(0.66, h, 0.015).getPoints(4)));
    g.add(K.m(K.extrude(fr, 0.025, { bevel: 0.008, bevelSeg: 1, curveSeg: 3 }), mt.chrome, { pos: [0, y, fz - 0.008] }));
  }
  // pull knobs: 2 rows x 6, each with a label chip
  const knob = cg('cig_knob', () => K.lathe([[0, 0], [0.012, 0], [0.012, 0.04], [0.024, 0.05], [0.026, 0.07], [0.018, 0.08], [0, 0.08]], { seg: 10, round: 0.004, steps: 1 }));
  const chips = ['#E23B3B', '#2A3A8A', '#F4F1E8', '#E8A92E', '#2E6A3A', '#7FD4FF'];
  for (let r = 0; r < 2; r++) for (let c = 0; c < 6; c++) {
    const x = -0.275 + c * 0.11, y = 0.64 - r * 0.13;
    g.add(K.m(knob, mt.chrome, { pos: [x, y, fz], rot: [-Math.PI / 2, 0, 0] }));
    g.add(K.m(tc(K.box(0.06, 0.025, 0.008, 0.003), chips[(c + r * 2) % 6]), mt.plastic, { pos: [x, y + 0.05, fz - 0.013] }));
  }
  g.add(K.m(K.box(0.7, 0.3, 0.012, 0.006), mt.chrome, { pos: [0, 0.58, fz - 0.003] }));
  // coin head + delivery trough
  g.add(K.m(K.box(0.14, 0.12, 0.04, 0.012), mt.chrome, { pos: [0.26, 0.33, fz - 0.015] }));
  g.add(K.m(tc(K.box(0.01, 0.04, 0.01, 0.003), '#1E1530'), mt.plastic, { pos: [0.26, 0.35, fz - 0.036] }));
  g.add(K.m(K.box(0.44, 0.1, 0.1, 0.02), mt.chrome, { pos: [-0.08, 0.24, fz - 0.04] }));
  g.add(K.m(tc(K.box(0.4, 0.06, 0.08, 0.012), '#1E1530'), mt.plastic, { pos: [-0.08, 0.265, fz - 0.045] }));
  g.userData.parts = { glow: win, glowMarquee: mq };
  g.userData.lightAnchors = lit ? [{ pos: [0, 1.1, fz - 0.45], color: '#FFD9A0', intensity: 1.1, distance: 3 }] : [];
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2 - 0.1], max: [W / 2, H + 0.02, D / 2] }];
  g.userData.interact = { point: [0, 0.6, fz - 0.4], radius: 1.1 };
  return K.finish(game, g);
}, { category: CAT, tags: ['machine', 'vending', 'green_room', 'light'], size: [0.77, 1.48, 0.56], desc: 'walnut & chrome cigarette machine: lit marquee, backlit pack window, 12 chrome pull knobs (parts.glow; opts.lit)', hero: true });

// ------------------------------------------------------------------------------------- rotary payphone
registerProp('payphone_rotary', (game) => {
  const g = K.prop('payphone_rotary');
  const mt = M(game), atl = atlasMat(game), dm = decorMat(game);
  const steel = K.mat(game, 'metal', '#ffffff', { map: K.tex.brushed('#9EA4AE'), env: 0.2 });
  // wall sign above
  g.add(K.m(dcell(cbox(0.26, 0.26, 0.02, 0.006), 2, 0), dm, { pos: [0, 0.84, -0.01] }));
  // backplate + stainless housing
  g.add(K.m(K.box(0.28, 0.66, 0.02, 0.02), steel, { pos: [0, 0.33, -0.01] }));
  g.add(K.m(K.box(0.21, 0.54, 0.13, 0.025), steel, { pos: [0.02, 0.33, -0.085] }));
  g.add(K.m(K.box(0.215, 0.05, 0.14, 0.015), mt.chrome, { pos: [0.02, 0.62, -0.085] }));
  for (let i = 0; i < 3; i++) g.add(K.m(tc(K.box(0.035, 0.006, 0.012, 0.002), '#1E1530'), mt.plastic, { pos: [-0.03 + i * 0.05, 0.646, -0.1] }));
  // instruction card, dial, coin return
  g.add(K.m(dcell(cbox(0.15, 0.13, 0.006, 0.002), 1, 0), dm, { pos: [0.02, 0.52, -0.153] }));
  g.add(K.m(tc(puck(0.06, 0.02, 0.006, 18), '#2A2230'), mt.plastic, { pos: [0.02, 0.36, -0.15], rot: [-Math.PI / 2, 0, 0] }));
  g.add(K.m(cell(new THREE.CircleGeometry(0.052, 22), 0, 0), atl, { pos: [0.02, 0.36, -0.1705], rot: [0, Math.PI, 0] }));
  g.add(K.m(K.box(0.006, 0.02, 0.006, 0.002), mt.chrome, { pos: [0.06, 0.32, -0.174], rot: [0, 0, 0.6] }));
  g.add(K.m(K.box(0.08, 0.05, 0.04, 0.012), mt.chrome, { pos: [0.02, 0.14, -0.15] }));
  g.add(K.m(tc(K.box(0.06, 0.03, 0.02, 0.006), '#1E1530'), mt.plastic, { pos: [0.02, 0.14, -0.168] }));
  // hook + black handset hanging on the left + armored cord
  g.add(K.m(K.box(0.04, 0.03, 0.05, 0.01), mt.chrome, { pos: [-0.1, 0.5, -0.1] }));
  const hs = new THREE.Group();
  hs.position.set(-0.13, 0.36, -0.11);
  hs.add(K.m(tc(K.tube([[0, 0.14, 0], [-0.012, 0.07, 0], [-0.012, -0.07, 0], [0, -0.14, 0]], 0.017, { seg: 10, radial: 7 }), '#2A2230'), mt.plastic));
  const cup = K.lathe([[0, 0], [0.028, 0], [0.034, 0.018], [0.03, 0.03], [0, 0.03]], { seg: 12, round: 0.006, steps: 1 });
  hs.add(K.m(tc(cup, '#2A2230'), mt.plastic, { pos: [0.006, 0.15, 0], rot: [0, 0, -Math.PI / 2] }));
  hs.add(K.m(tc(cup, '#2A2230'), mt.plastic, { pos: [0.006, -0.15, 0], rot: [0, 0, -Math.PI / 2] }));
  g.add(hs);
  g.add(K.m(K.tube([[-0.14, 0.21, -0.11], [-0.15, 0.12, -0.12], [-0.08, 0.08, -0.13], [-0.06, 0.12, -0.14]], 0.009, { seg: 16, radial: 6 }), mt.chrome));
  wallFit(g);
  g.userData.colliders = [];
  g.userData.interact = { point: [0.0, 0.5, -0.35], radius: 1.1 };
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['wall', 'phone', 'green_room', 'lobby'], size: [0.3, 1.15, 0.2], desc: 'stainless rotary payphone with hanging handset, armored cord and a PHONE sign above (wall prop; bottom at ~0.95 m)' });

// ---------------------------------------------------------------------------------------------- wall clock
// hands at 11:59:58, rotation.z clockwise as seen from the front (-z). parts: { hour, minute, second }
function clockHands(game, g, cx, cy, cz, R, color = '#2A2230') {
  const mt = M(game);
  const mk = (len, w, col, ang, zoff, name) => {
    const hand = new THREE.Group();
    hand.name = name;
    hand.position.set(cx, cy, cz - zoff);
    hand.rotation.z = ang;
    hand.userData.noMerge = true;
    hand.add(K.m(tc(K.box(w, len, 0.005, Math.min(w / 2 - 0.0005, 0.004)), col), mt.plastic, { pos: [0, len / 2 - len * 0.15, 0] }));
    g.add(hand);
    return hand;
  };
  const T = (h, m, s) => [((h % 12) + m / 60) / 12 * TAU, (m + s / 60) / 60 * TAU, s / 60 * TAU];
  const [ah, am, as] = T(11, 59, 58);
  const hour = mk(R * 0.55, R * 0.08, color, ah, 0.004, 'hour');
  const minute = mk(R * 0.8, R * 0.055, color, am, 0.01, 'minute');
  const second = mk(R * 0.85, R * 0.02, '#E23B3B', as, 0.016, 'second');
  g.add(K.m(tc(K.cyl(R * 0.05, R * 0.05, 0.02, { seg: 10 }), '#E23B3B'), mt.plastic, { pos: [cx, cy, cz - 0.02], rot: [Math.PI / 2, 0, 0] }));
  return { hour, minute, second };
}
registerProp('clock_wall', (game, opts = {}) => {
  const g = K.prop('clock_wall');
  const mt = M(game), dm = decorMat(game);
  const R = (opts.size ?? 0.36) / 2;
  const cy = R + 0.02;
  g.add(K.m(tc(puck(R, 0.05, 0.02, 32), opts.bezel ?? '#F4F1E8'), mt.lacquer, { pos: [0, cy, -0.005], rot: [-Math.PI / 2, 0, 0] }));
  g.add(K.m(new THREE.TorusGeometry(R - 0.008, 0.016, 8, 36), mt.chrome, { pos: [0, cy, -0.058] }));
  g.add(K.m(dcell(new THREE.CircleGeometry(R - 0.018, 32), 3, 0), dm, { pos: [0, cy, -0.0565], rot: [0, Math.PI, 0] }));
  const parts = clockHands(game, g, 0, cy, -0.058, R - 0.02);
  if (opts.label) {
    const idx = ['NEW YORK', 'LONDON', 'TOKYO', 'WZTV'].indexOf(opts.label);
    const row = Math.max(0, idx);
    g.add(K.m(K.uvRect(cbox(R * 1.5, R * 0.32, 0.012, 0.003).clone(), 3 / 4, 1 - 3 / 4 + (3 - row) / 16, 1, 1 - 3 / 4 + (4 - row) / 16), dm, { pos: [0, cy - R - 0.08, -0.012] }));
  }
  wallFit(g);
  g.userData.parts = parts;
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['wall', 'clock', 'newsroom', 'master_control', 'lobby'], size: [0.38, 0.4, 0.07], desc: 'chrome-ringed office wall clock stopped at 11:59 (parts.hour/minute/second; opts.size, opts.bezel, opts.label=NEW YORK|LONDON|TOKYO|WZTV; wall prop, bottom ~2.2 m)' });

// ------------------------------------------------------------------------------------------ sunburst clock
registerProp('clock_sunburst', (game) => {
  const g = K.prop('clock_sunburst');
  const mt = M(game);
  const R = 0.16, cy = 0.4;
  g.add(K.m(K.uvScale(puck(R, 0.04, 0.015, 28).clone(), 1, 1), mt.teak, { pos: [0, cy, -0.01], rot: [-Math.PI / 2, 0, 0] }));
  g.add(K.m(new THREE.TorusGeometry(R, 0.012, 5, 28), mt.brass, { pos: [0, cy, -0.05] }));
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * TAU;
    g.add(K.m(cbox(0.014, i % 3 ? 0.03 : 0.05, 0.01, 0.003), mt.brass, { pos: [-Math.sin(a) * (R - 0.035), cy + Math.cos(a) * (R - 0.035), -0.052], rot: [0, 0, a] }));
  }
  for (let i = 0; i < 24; i++) {
    const a = (i / 24) * TAU + 0.13, L = i % 2 ? 0.2 : 0.3;
    const p0 = [-Math.sin(a) * (R + 0.01), cy + Math.cos(a) * (R + 0.01), -0.03], p1 = [-Math.sin(a) * (R + L), cy + Math.cos(a) * (R + L), -0.03];
    g.add(span(new THREE.CylinderGeometry(0.0055, 0.009, L - 0.01, 5, 1, true).translate(0, (L - 0.01) / 2, 0), mt.brass, p0, p1));
    g.add(K.m(sph(i % 2 ? 0.014 : 0.02, 6, 4), mt.brass, { pos: p1 }));
  }
  const parts = clockHands(game, g, 0, cy, -0.054, R - 0.02, '#C8963C');
  wallFit(g);
  g.userData.parts = parts;
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['wall', 'clock', 'lobby'], size: [0.98, 0.98, 0.07], desc: 'brass & teak sunburst clock stopped at 11:59 (parts.hour/minute/second; wall prop, bottom ~1.9 m)' });

// ------------------------------------------------------------------------------------------------ cork board
registerProp('cork_board', (game, opts = {}) => {
  const g = K.prop('cork_board');
  const mt = M(game), dm = decorMat(game);
  const W = opts.w ?? 1.2, H = opts.h ?? 0.8;
  const cork = K.mat(game, 'felt', '#ffffff', { map: K.tex.canvas('furn_cork', 256, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#B8834A'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 4000; i++) { ctx.fillStyle = ['#8A5A2A', '#D4A060', '#A06A34', '#E0B070'][Math.floor(rand() * 4)]; ctx.globalAlpha = 0.5 + rand() * 0.5; ctx.fillRect(rand() * w, rand() * h, 1 + rand() * 2.5, 1 + rand() * 2); }
    ctx.globalAlpha = 1;
  }), rim: 0.1 });
  g.add(K.m(K.uvScale(K.box(W - 0.06, H - 0.06, 0.02, 0.004).clone(), 1, 1), cork, { pos: [0, H / 2, -0.012] }));
  for (const [w, h, x, y] of [[W, 0.05, 0, H - 0.025], [W, 0.05, 0, 0.025], [0.05, H - 0.06, -W / 2 + 0.025, H / 2], [0.05, H - 0.06, W / 2 - 0.025, H / 2]]) {
    g.add(K.m(K.box(w, h, 0.04, 0.012, { uv: 1.5, swap: w < h }), mt.walnut, { pos: [x, y, -0.02] }));
  }
  const rnd = mulberry32(opts.seed ?? 8);
  const notes = [[0, 1, 0.2, 0.2], [1, 1, 0.2, 0.24], [2, 1, 0.26, 0.26], [3, 1, 0.14, 0.14], [0, 2, 0.24, 0.24], [1, 2, 0.22, 0.22], [3, 1, 0.12, 0.12], [2, 2, 0.16, 0.16]];
  const slots = [[-0.4, 0.55], [-0.12, 0.52], [0.22, 0.5], [0.44, 0.6], [-0.36, 0.22], [0.04, 0.2], [0.46, 0.28], [0.26, 0.2]];
  const pins = ['#E23B3B', '#F4E03A', '#2F5BD3', '#52D24A', '#F4F1E8'];
  notes.forEach(([cx, cy2, w, h], i) => {
    const [sx, sy] = slots[i];
    const x = sx * W / 1.2, y = sy * H / 0.8;
    const rz = (rnd() - 0.5) * 0.25;
    g.add(K.m(dcell(cbox(w, h, 0.003, 0.001), cx, cy2), dm, { pos: [x, y, -0.024 - i * 0.0006], rot: [0, 0, rz] }));
    const px = x - Math.sin(rz) * h * 0.4, py = y + Math.cos(rz) * h * 0.4;
    g.add(K.m(tc(sph(0.012, 8, 6), pins[i % pins.length]), mt.plastic, { pos: [px, py, -0.036] }));
    g.add(K.m(K.cyl(0.002, 0.002, 0.012, { seg: 4, bevel: 0.0005 }), mt.chrome, { pos: [px, py, -0.036], rot: [-Math.PI / 2, 0, 0] }));
  });
  wallFit(g);
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['wall', 'decor', 'newsroom', 'green_room', 'master_control'], size: [1.2, 0.8, 0.05], desc: 'walnut-framed cork board with memos, a polaroid, the on-air schedule, clippings, push pins (opts.w/h, opts.seed; wall prop, bottom ~1.0 m)' });

// --------------------------------------------------------------------------------------- framed picture
registerProp('frame_picture', (game, opts = {}) => {
  const g = K.prop('frame_picture');
  const mt = M(game);
  const id = opts.card ?? 'hero_portrait_duke';
  const info = cardInfo(id) || { w: 3, h: 4 };
  const style = opts.style ?? 'gold';
  const ph = opts.h ?? 0.6, pw = ph * info.w / info.h;
  const fw = style === 'gold' ? 0.08 : style === 'chrome' ? 0.025 : 0.05;
  const mat = style === 'walnut' ? 0.05 : 0;
  const ow = pw + 2 * (fw + mat), oh = ph + 2 * (fw + mat);
  const fr = K.roundRect(ow, oh, style === 'chrome' ? 0.02 : 0.012);
  fr.holes.push(new THREE.Path(K.roundRect(pw + 2 * mat, ph + 2 * mat, 0.012).getPoints(4)));
  const fmat = style === 'gold' ? mt.brass : style === 'chrome' ? mt.chrome : mt.walnut;
  // (three.js mis-triangulates holes with big negative-offset bevels: keep the slab bevel small, add beads)
  const depth = style === 'gold' ? 0.045 : 0.035;
  g.add(K.m(K.extrude(fr, depth, { bevel: 0.005, bevelSeg: 2, curveSeg: 2, uv: 1.5 }), fmat, { pos: [0, oh / 2, -depth / 2] }));
  const bead = (w, h, r, z) => g.add(K.m(K.tube(K.roundRectPath(w, h, Math.max(0.006, r * 1.2), 0).map(([x, , zz]) => [x, zz, 0]), r, { seg: 44, radial: 6, closed: true }), fmat, { pos: [0, oh / 2, z] }));
  if (style === 'gold') { bead(pw + 0.02, ph + 0.02, 0.012, -depth); bead(ow - 0.03, oh - 0.03, 0.014, -depth - 0.004); bead(pw + fw, ph + fw, 0.008, -depth - 0.008); }
  else if (style === 'walnut') bead(pw + 2 * mat + 0.012, ph + 2 * mat + 0.012, 0.007, -depth);
  if (mat) g.add(K.m(tc(K.box(pw + 2 * mat, ph + 2 * mat, 0.01, 0.002), '#F6E7C8'), mt.paint, { pos: [0, oh / 2, -0.012] }));
  const pic = K.m(new THREE.PlaneGeometry(pw, ph), K.mat(game, 'paint', '#ffffff', { map: getCard(id), rough: 0.5 }), { pos: [0, oh / 2, -0.019], rot: [0, Math.PI, 0] });
  g.add(pic);
  g.add(K.m(tc(K.box(ow - 0.04, oh - 0.04, 0.01, 0.003), '#3A2A20'), mt.paint, { pos: [0, oh / 2, -0.006] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}, { category: CAT, tags: ['wall', 'decor', 'lobby', 'portrait'], size: [0.64, 0.76, 0.05], desc: 'framed picture of any cards.js card (opts.card = hero_portrait_<id> | portrait_baron | portrait_stormy_stu | poster_*; opts.style gold|walnut|chrome; opts.h; wall prop, bottom ~1.3 m)' });

// ------------------------------------------------------------------------------------------ trophy shelf
function cupTrophy(game, h = 0.3) {
  const mt = M(game);
  const g = new THREE.Group();
  g.add(K.m(K.box(0.1, 0.05, 0.1, 0.01, { uv: 2 }), mt.walnut, { pos: [0, 0.025, 0] }));
  g.add(K.m(K.lathe([[0, 0], [0.035, 0], [0.03, 0.012], [0.012, 0.03], [0.01, h * 0.35], [0.02, h * 0.42], [0.06, h * 0.62], [0.066, h * 0.8], [0.062, h * 0.8], [0, h * 0.62]], { seg: 14, round: 0.006, steps: 1 }), mt.brass, { pos: [0, 0.05, 0] }));
  for (const s of [-1, 1]) g.add(K.m(new THREE.TorusGeometry(0.03, 0.006, 5, 12, Math.PI * 1.1), mt.brass, { pos: [s * 0.068, 0.05 + h * 0.62, 0], rot: [0, 0, s > 0 ? -Math.PI * 0.55 : Math.PI * 0.45] }));
  return g;
}
registerProp('trophy_shelf', (game) => {
  const g = K.prop('trophy_shelf');
  const mt = M(game), dm = decorMat(game);
  const L = 1.1;
  g.add(K.m(K.box(L, 0.04, 0.24, 0.012, { uv: 1.5, swap: true }), mt.walnut, { pos: [0, 0.2, -0.12] }));
  for (const s of [-1, 1]) g.add(K.m(K.extrude([[0, 0], [0.16, 0], [0.16, 0.02], [0.02, 0.18], [0, 0.18]], 0.02, { bevel: 0.004, round: 0.02 }), mt.brass, { pos: [s * (L / 2 - 0.12), 0.01, -0.01], rot: [0, Math.PI / 2, 0] }));
  const sy = 0.22;
  put(g, cupTrophy(game, 0.34), [-0.38, sy, -0.12], 0);
  put(g, cupTrophy(game, 0.24), [0.4, sy, -0.12], 0.3);
  // gold microphone trophy
  const mic = new THREE.Group();
  mic.add(K.m(K.box(0.09, 0.06, 0.09, 0.01, { uv: 2 }), mt.walnut, { pos: [0, 0.03, 0] }));
  mic.add(K.m(K.cyl(0.012, 0.016, 0.18, { seg: 10 }), mt.brass, { pos: [0, 0.06, 0] }));
  mic.add(K.m(K.lathe([[0, 0], [0.02, 0], [0.034, 0.03], [0.036, 0.08], [0.02, 0.11], [0, 0.115]], { seg: 14, round: 0.01 }), mt.brass, { pos: [0, 0.23, 0] }));
  put(g, mic, [0.14, sy, -0.1], 0);
  // leaning plaque with an engraved plate
  const pl = new THREE.Group();
  pl.add(K.m(K.box(0.24, 0.3, 0.025, 0.01, { uv: 2 }), mt.walnut));
  pl.add(K.m(dcell(cbox(0.19, 0.19, 0.006, 0.002), 2, 2), dm, { pos: [0, 0.01, -0.015] }));
  put(g, pl, [-0.1, sy + 0.15, -0.16], 0, [-0.16, 0, 0]);
  g.userData.colliders = [];
  wallFit(g);
  return K.finish(game, g, { ao: { floor: false, height: 0.0 } });
}, { category: CAT, tags: ['wall', 'decor', 'lobby', 'newsroom'], size: [1.1, 0.6, 0.25], desc: 'walnut wall shelf on brass brackets with gold cups, a gold-mic award and a BEST LOCAL NEWS plaque (wall prop; bottom ~1.4 m)' });

// ------------------------------------------------------------------------------------------------ bookshelf
registerProp('bookshelf', (game, opts = {}) => {
  const g = K.prop('bookshelf');
  const mt = M(game), dm = decorMat(game);
  const W = 1.0, H = 1.8, D = 0.34, t = 0.03;
  for (const s of [-1, 1]) g.add(K.m(K.box(t, H, D, 0.01, { uv: 1.4, swap: true }), mt.walnut, { pos: [s * (W / 2 - t / 2), H / 2, 0] }));
  g.add(K.m(K.box(W + 0.02, 0.04, D + 0.02, 0.012, { uv: 1.4 }), mt.walnut, { pos: [0, H - 0.02, 0] }));
  g.add(K.m(tc(K.box(W - 0.02, 0.07, D - 0.03, 0.01), '#3A2418'), mt.lacquer, { pos: [0, 0.035, 0.01] }));
  g.add(K.m(tc(K.box(W - 0.04, H - 0.06, 0.012, 0.004), '#6A4428'), mt.walnut, { pos: [0, H / 2, D / 2 - 0.01] }));
  const shelfY = [0.07, 0.48, 0.9, 1.32];
  shelfY.forEach((y) => g.add(K.m(K.box(W - 2 * t, 0.025, D - 0.02, 0.006, { uv: 1.4 }), mt.walnut, { pos: [0, y + 0.0125, 0] })));
  const rnd = mulberry32(opts.seed ?? 12);
  const inner = W - 2 * t - 0.02;
  shelfY.forEach((y, si) => {
    let x = -inner / 2;
    const y0 = y + 0.025;
    while (x < inner / 2 - 0.08) {
      const kind = rnd();
      if (kind < 0.62) { // block of books
        const w = Math.min(0.12 + rnd() * 0.2, inner / 2 - x);
        const h = 0.22 + rnd() * 0.12, d = 0.2 + rnd() * 0.06;
        g.add(K.m(dcell(cbox(w, h, d, 0.004), Math.floor(rnd() * 4), 3), dm, { pos: [x + w / 2, y0 + h / 2, -D / 2 + d / 2 + 0.02] }));
        x += w + 0.004;
      } else if (kind < 0.78) { // horizontal stack
        const n = 2 + Math.floor(rnd() * 3);
        for (let k = 0; k < n; k++) g.add(K.m(tc(cbox(0.2 - k * 0.012, 0.035, 0.16, 0.004), ['#B5472A', '#2E8C8C', '#E8A92E', '#6B3A6E'][k % 4]), mt.paint, { pos: [x + 0.11, y0 + 0.018 + k * 0.036, -0.02], rot: [0, (rnd() - 0.5) * 0.3, 0] }));
        x += 0.23;
      } else if (kind < 0.9 && si > 0) { // knick-knack: ceramic owl or tiny planter
        if (rnd() < 0.5) {
          g.add(K.m(tc(K.lathe([[0, 0], [0.045, 0], [0.05, 0.05], [0.04, 0.09], [0.042, 0.12], [0, 0.13]], { seg: 12, round: 0.01, steps: 1 }), '#E3662B'), mt.lacquer, { pos: [x + 0.06, y0, -0.02] }));
          for (const s of [-1, 1]) g.add(K.m(tc(sph(0.014, 8, 6), '#F6E7C8'), mt.lacquer, { pos: [x + 0.06 + s * 0.018, y0 + 0.1, -0.058] }));
        } else {
          g.add(K.m(tc(K.cyl(0.05, 0.04, 0.08, { seg: 12 }), '#8C9A3A'), mt.lacquer, { pos: [x + 0.06, y0, -0.02] }));
          const sp = K.leafCluster({ count: 7, len: [0.1, 0.14], width: 0.04, a0: [1.1, 1.4], a1: [0.2, 0.8], seed: si + 3 });
          K.tint(sp, '#4E8A34');
          g.add(K.m(sp, leafMat(game, leafTex(), { rough: 0.5 }), { pos: [x + 0.06, y0 + 0.075, -0.02] }));
        }
        x += 0.14;
      } else { // leaning book
        const h = 0.24 + rnd() * 0.06;
        g.add(K.m(tc(cbox(0.035, h, 0.18, 0.004), ['#2F5BD3', '#E23B3B', '#D9A520'][Math.floor(rnd() * 3)]), mt.paint, { pos: [x + 0.06, y0 + h / 2 - 0.01, -0.03], rot: [0, 0, -0.35] }));
        x += 0.12;
      }
    }
  });
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, H, D / 2] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['shelf', 'books', 'lobby', 'newsroom', 'green_room'], size: [1.02, 1.8, 0.36], desc: 'walnut bookcase: rows of colorful books, stacks, a leaning book, ceramic owl and a small planter (opts.seed)' });

// ------------------------------------------------------------------------------------------------ shag rugs
function shagRingTex(key, rings) {
  return K.tex.canvas(`furn_rug_${key}`, 512, 512, (ctx, w, h, rand) => {
    const cx = w / 2, cy = h / 2, R = w / 2;
    ctx.fillStyle = rings[rings.length - 1]; ctx.fillRect(0, 0, w, h);
    ctx.lineCap = 'round';
    for (let i = 0; i < 26000; i++) {
      const a = rand() * TAU, rr = Math.sqrt(rand()) * R;
      const band = Math.min(rings.length - 1, Math.floor((rr / R) * rings.length + Math.sin(a * 7) * 0.08));
      const base = rings[band];
      const x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr, d = rand() * TAU, l = 3 + rand() * 5;
      ctx.strokeStyle = base; ctx.globalAlpha = 0.6 + rand() * 0.4; ctx.lineWidth = 1.5 + rand() * 1.5;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + Math.cos(d) * l, y + Math.sin(d) * l); ctx.stroke();
      if (rand() < 0.25) { ctx.fillStyle = '#ffffff'; ctx.globalAlpha = 0.18; ctx.fillRect(x + Math.cos(d) * l, y + Math.sin(d) * l, 1.5, 1.5); }
      if (rand() < 0.2) { ctx.fillStyle = '#000000'; ctx.globalAlpha = 0.15; ctx.fillRect(x, y, 1.5, 1.5); }
    }
    ctx.globalAlpha = 1;
  }, { repeat: false });
}
function rugGeo(R, h = 0.028) {
  const geo = puck(R, h, 0.014, 56).clone();
  const p = geo.attributes.position, uv = geo.attributes.uv;
  for (let i = 0; i < p.count; i++) uv.setXY(i, p.getX(i) / (2 * R * 1.02) + 0.5, 0.5 - p.getZ(i) / (2 * R * 1.02));
  uv.needsUpdate = true;
  return geo;
}
registerProp('rug_shag_round', (game, opts = {}) => {
  const g = K.prop('rug_shag_round');
  const R = opts.r ?? 1.1;
  const rings = opts.rings ?? ['#E8A92E', '#E3662B', '#B5472A', '#E8A92E', '#5A3A22'];
  const m = K.mat(game, 'fabric', '#ffffff', { map: shagRingTex(rings.join('').replace(/#/g, ''), rings), rim: 0.12, rimPower: 3 });
  g.add(K.m(rugGeo(R), m));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { height: 0.0, strength: 0.4 } });
}, { category: CAT, tags: ['rug', 'floor', 'lobby', 'green_room', 'telly_home'], size: [2.2, 0.03, 2.2], desc: 'round shag rug in concentric harvest/orange/rust rings (opts.r, opts.rings = [inner..outer colors]; walkable, no collider)' });
registerProp('rug_shag_oval', (game, opts = {}) => {
  const g = K.prop('rug_shag_oval');
  const L = opts.len ?? 2.6, Wd = opts.w ?? 1.7;
  const rings = opts.rings ?? ['#8C9A3A', '#D9A520', '#F6E7C8', '#8C9A3A', '#5A3A22'];
  const m = K.mat(game, 'fabric', '#ffffff', { map: shagRingTex(rings.join('').replace(/#/g, ''), rings), rim: 0.12, rimPower: 3 });
  g.add(K.m(rugGeo(Wd / 2), m, { scale: [L / Wd, 1, 1] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { height: 0.0, strength: 0.4 } });
}, { category: CAT, tags: ['rug', 'floor', 'green_room', 'newsroom', 'telly_home'], size: [2.6, 0.03, 1.7], desc: 'oval shag rug in avocado/mustard/cream rings (opts.len, opts.w, opts.rings; walkable, no collider)' });

// ------------------------------------------------------------------------------------------ wall trims
// Moulding profiles [depth, height] (depth into the room), extruded along x (opts.len). Wall props: back at z = 0.
const TRIMS = {
  trim_baseboard: { h: 0.14, prof: [[0, 0], [0.024, 0], [0.024, 0.09], [0.018, 0.1], [0.018, 0.112], [0.012, 0.128], [0.006, 0.136], [0, 0.14]], desc: 'walnut baseboard with an ogee cap (bottom at the floor)' },
  trim_chair_rail: { h: 0.07, prof: [[0, 0], [0.012, 0.004], [0.026, 0.018], [0.03, 0.035], [0.026, 0.052], [0.012, 0.066], [0, 0.07]], desc: 'rounded walnut chair rail (bottom at ~0.9 m)' },
  trim_crown: { h: 0.13, prof: [[0, 0], [0.018, 0], [0.018, 0.016], [0.03, 0.03], [0.06, 0.07], [0.09, 0.1], [0.1, 0.112], [0.1, 0.13], [0, 0.13]], desc: 'walnut cove crown moulding (bottom at ceiling - 0.13 m)' },
};
for (const [id, T] of Object.entries(TRIMS)) {
  registerProp(id, (game, opts = {}) => {
    const g = K.prop(id);
    const mt = M(game);
    const len = opts.len ?? 2.0;
    const geo = K.extrude(T.prof, len, { bevel: 0.002, bevelSeg: 1, uv: 3 });
    geo.rotateY(Math.PI / 2);
    // wood grain along the length
    const p = geo.attributes.position, uv = geo.attributes.uv;
    for (let i = 0; i < p.count; i++) uv.setXY(i, (p.getY(i) - p.getZ(i)) * 2.5, p.getX(i) * 0.9);
    g.add(K.m(tc(geo, opts.color ?? '#F0DCC8'), mt.walnut));
    g.userData.colliders = [];
    return K.finish(game, g, { ao: false });
  }, { category: CAT, tags: ['wall', 'trim'], size: [2.0, T.h, 0.1], desc: `${T.desc}; opts.len (m), opts.color (tint)` });
}

// set-dressing vignettes (propview review; also a placement reference for the room dressers)
// back wall at z = +d/2 (wall props: rotY 0), left wall at x = -w/2 (wall props: rotY = -PI/2)
registerScene('furn_lobby', {
  floor: 'shag', floorColor: '#C8562A', wall: 'panel', room: [7.2, 5.2], wallH: 3.2,
  items: [
    { id: 'rug_shag_round', pos: [-1.3, 0.75] },
    { id: 'sofa_cloud', pos: [-1.3, 2.02] },
    { id: 'table_coffee', pos: [-1.3, 0.85], rotY: 0.04 },
    { id: 'lamp_arc', pos: [-2.55, 1.55], rotY: -Math.PI / 2 },
    { id: 'chair_ball', pos: [0.75, 0.55], rotY: -0.75 },
    { id: 'table_side_tulip', pos: [0.35, 2.15] },
    { id: 'lamp_lava', pos: [0.35, 0.54, 2.15] },
    { id: 'plant_rubber', pos: [2.9, 2.1] },
    { id: 'armchair_barrel', pos: [2.1, 1.05], rotY: -1.0 },
    { id: 'ash_urn', pos: [1.5, 2.25] },
    { id: 'frame_picture', pos: [-1.95, 1.3, 2.6], opts: { card: 'hero_portrait_duke', h: 0.55 } },
    { id: 'frame_picture', pos: [-0.65, 1.3, 2.6], opts: { card: 'portrait_baron', style: 'walnut', h: 0.55 } },
    { id: 'clock_sunburst', pos: [1.6, 1.55, 2.6] },
    { id: 'macrame_owl', pos: [-3.6, 1.15, 0.2], rotY: -Math.PI / 2 },
    { id: 'plant_fern', pos: [-3.1, -0.9] },
    { id: 'trim_chair_rail', pos: [0, 0.95, 2.6], opts: { len: 7.2 } },
  ],
  cam: { pos: [0.4, 1.65, -3.3], target: [-0.5, 0.95, 1.3], fov: 56 }, hemi: 0.9,
});
registerScene('furn_newsroom', {
  floor: 'tile', tileA: '#E8E1D0', tileB: '#8C9A3A', wall: '#C9B48A', room: [8, 6], wallH: 3.4,
  items: [
    { id: 'desk_reporter', pos: [-1.9, -0.6] },
    { id: 'chair_office', pos: [-1.8, -1.35], rotY: Math.PI + 0.3 },
    { id: 'desk_reporter', pos: [0.2, -0.6], opts: { typewriter: '#8C9A3A', phone: '#E23B3B' } },
    { id: 'chair_office', pos: [0.3, -1.3], rotY: Math.PI - 0.2, opts: { color: '#8C9A3A' } },
    { id: 'desk_anchor', pos: [1.2, 1.9] },
    { id: 'filing_cabinet', pos: [-3.7, 2.55] },
    { id: 'filing_cabinet', pos: [-3.2, 2.55], opts: { color: '#8C9A7A', ajar: false } },
    { id: 'water_cooler', pos: [-2.5, 2.7] },
    { id: 'cork_board', pos: [-1.2, 1.0, 3.0] },
    { id: 'clock_wall', pos: [0.4, 2.2, 3.0], opts: { label: 'NEW YORK' } },
    { id: 'clock_wall', pos: [1.2, 2.2, 3.0], opts: { label: 'WZTV' } },
    { id: 'clock_wall', pos: [2.0, 2.2, 3.0], opts: { label: 'TOKYO' } },
    { id: 'bookshelf', pos: [3.3, 2.75] },
    { id: 'trash_can', pos: [-1.0, -1.1] },
    { id: 'coat_rack', pos: [-3.5, 0.2] },
    { id: 'plant_snake', pos: [2.55, 2.75] },
    { id: 'trophy_shelf', pos: [-4.0, 1.5, -1.4], rotY: -Math.PI / 2 },
  ],
  cam: { pos: [0.3, 2.0, -3.6], target: [-0.4, 0.8, 1.2], fov: 60 }, hemi: 0.95,
});
registerScene('furn_green', {
  floor: 'shag', floorColor: '#6E7A2A', fleck: '#D9A520', wall: '#8C9A3A', room: [7, 5], wallH: 3.0,
  items: [
    { id: 'rug_shag_oval', pos: [0.2, 0.9] },
    { id: 'couch_avocado', pos: [0.2, 1.95] },
    { id: 'table_side_drum', pos: [1.6, 2.1] },
    { id: 'lamp_lava', pos: [1.6, 0.52, 2.1] },
    { id: 'lamp_pole', pos: [-1.25, 2.2] },
    { id: 'bean_bag', pos: [-0.6, 0.3], rotY: 0.6 },
    { id: 'bean_bag', pos: [1.0, 0.1], rotY: -0.7, opts: { color: '#E8A92E', seed: 7 } },
    { id: 'vending_soda', pos: [-2.7, 2.05] },
    { id: 'vending_cigarette', pos: [-1.95, 2.25] },
    { id: 'payphone_rotary', pos: [-3.5, 0.95, 0.4], rotY: -Math.PI / 2 },
    { id: 'macrame_hanger', pos: [2.5, 2.9, 1.2], opts: { drop: 0.9 } },
    { id: 'plant_snake', pos: [2.9, 2.2] },
    { id: 'coat_rack', pos: [3.0, 0.2] },
    { id: 'trash_can', pos: [-1.3, 1.1] },
  ],
  cam: { pos: [0.2, 1.6, -3.1], target: [-0.3, 1.0, 1.4], fov: 58 }, hemi: 0.9,
});

