// DEAD AIR — prop kit (docs/PROPKIT.md). Helpers that make procedural props look like premium stylized game art
// with little code, plus the prop/scene registry used by src/props/index.js and tools/propview.
//
//   Registry   registerProp(id, build(game, opts) -> Group, meta) · buildProp(id, game, opts) · listProps(cat?)
//              propMeta(id) · registerScene(name, spec) · getScene(name) · listScenes()
//   Result     prop(id, {...}) -> Group with the PROP RESULT CONVENTION userData (see below) · finish(game, group, o)
//   Materials  mat(game, preset, color, extra) — presets: lacquer walnut teak vinyl chrome brass plastic fabric felt
//              crt rubber paint metal ceramic soil leaf  (always vertexColors so bakeAO shows; keepColor via extra)
//              glow(game, color, intensity) · screen(game, w, h, {card, bulge, group}) -> CRT mesh
//   Geometry   box(w,h,d,r,{uv,swap,seg}) (centered) · cushion(w,h,d,{r,puff,uv}) (centered) · cyl(rt,rb,h,{bevel})
//              (base at y=0) · lathe(profile,{seg,round}) · roundProfile(pts,r) · extrude(shape|pts,depth,{bevel})
//              roundRect(w,h,r) · tube(pts,r,{seg,radial,closed}) · roundRectPath(w,d,r,y) · leaf(len,w,{...})
//              leafCluster({...}) · taper(geo,{axis,k}) · uvBox(geo, perMeter, {swap}) · uvScale(geo, su, sv) · uvRect(geo,u0,v0,u1,v1)
//              weldNormals(geo)
//              tint(geo, color) · m(geo, mat, o) (mesh shortcut)
//   Textures   tex.wood/burl/shag/weave/pebble/brushed/label/canvas (cached, seeded, fonts redrawn when loaded)
//   Baking     bakeAO(group, opts) — vertex-color AO: height-above-floor band + voxel ray occlusion (runs once)
//   Utils      merge(group) · stats(group) -> {tris, meshes, mats} · R (bevel radius presets) · PAL
//
// PROP RESULT CONVENTION — every builder returns a THREE.Group whose userData is:
//   { id, size:[w,h,d], colliders:[{min:[x,y,z], max:[x,y,z]}], screens:[{mesh, group}], lightAnchors:[{pos,
//     color, intensity, distance}], parts:{name: Object3D}, interact:{point:[x,y,z], radius}|null, stats }
//   Local space: floor at y=0, prop centered on x/z, FRONT FACES -Z. Only the ROOT userData may hold Object3D
//   references (clones remap them); children userData must stay JSON-safe (noMerge / noShadow / noAO flags).

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import * as G from '../core/geo.js';
import { mulberry32 } from '../core/rng.js';
import { PAL } from '../core/config.js';
import { getCard } from '../gfx/cards.js';

export { THREE, PAL };
const { clamp, smoothstep, lerp } = THREE.MathUtils;

// Load time: three's parametric geometries clone() as `new this.constructor().copy(this)`, and the no-argument
// constructor first generates a throw-away DEFAULT shape (RoundedBoxGeometry: a 900-vertex box with arc UVs; Tube: a
// 64-segment tube; Sphere: 32x16) that copy() then overwrites. Props and rooms clone thousands of cached geometries
// (bakeAO, uvBox, taper, tints), so clone() builds the instance through the BufferGeometry constructor only: same
// class, type, parameters and data, without the discarded default build (about 2 s of boot on Iris Xe).
function fastGeometryClone() {
  const g = Reflect.construct(THREE.BufferGeometry, [], this.constructor);
  g.type = this.type;
  g.copy(this);
  if (this.tangents !== undefined) { g.tangents = this.tangents; g.normals = this.normals; g.binormals = this.binormals; }
  return g;
}
for (const C of [RoundedBoxGeometry, THREE.BoxGeometry, THREE.CapsuleGeometry, THREE.CircleGeometry, THREE.CylinderGeometry,
  THREE.ConeGeometry, THREE.SphereGeometry, THREE.TorusGeometry, THREE.TorusKnotGeometry, THREE.PlaneGeometry,
  THREE.RingGeometry, THREE.LatheGeometry, THREE.TubeGeometry, THREE.ExtrudeGeometry, THREE.ShapeGeometry,
  THREE.PolyhedronGeometry, THREE.IcosahedronGeometry, THREE.OctahedronGeometry, THREE.DodecahedronGeometry,
  THREE.TetrahedronGeometry]) {
  if (C && !Object.prototype.hasOwnProperty.call(C.prototype, 'clone')) C.prototype.clone = fastGeometryClone;
}

// =============================================================================================== registry
const PROPS = new Map();
const SCENES = new Map();
const PROTOS = new WeakMap(); // game -> Map(key -> prototype group)

// meta: { category, tags:[], size:[w,h,d] (nominal, for layout tools), desc, cache=true, hero=false }
export function registerProp(id, build, meta = {}) {
  if (PROPS.has(id)) console.warn(`[props] "${id}" registered twice; the last one wins`);
  PROPS.set(id, {
    id, build,
    meta: { category: meta.category ?? 'misc', tags: meta.tags ?? [], size: meta.size ?? null, desc: meta.desc ?? '',
      cache: meta.cache ?? true, hero: !!meta.hero },
  });
}

export function propMeta(id) {
  const e = PROPS.get(id);
  return e ? { id, ...e.meta } : null;
}

export function listProps(category = null) {
  const out = [];
  for (const e of PROPS.values()) if (!category || e.meta.category === category) out.push({ id: e.id, ...e.meta });
  return out;
}

// Builds a prop. Props without screens are built once per (game, id, opts) and cloned afterwards (geometry and
// materials shared, userData Object3D refs remapped). opts.unique = true forces a fresh build.
export function buildProp(id, game, opts = {}) {
  const e = PROPS.get(id);
  if (!e) throw new Error(`[props] unknown prop "${id}"`);
  let cache = PROTOS.get(game);
  if (!cache) PROTOS.set(game, (cache = new Map()));
  const key = `${id}|${JSON.stringify(opts)}`;
  const hit = cache.get(key);
  if (hit) return cloneProp(hit);
  const g = e.build(game, opts);
  normalizeUserData(g, id);
  if (e.meta.cache && !opts.unique && !g.userData.screens.length) {
    cache.set(key, g);
    return cloneProp(g);
  }
  return g;
}

function normalizeUserData(g, id) {
  const u = g.userData;
  u.id = u.id || id;
  u.colliders = u.colliders || [];
  u.screens = u.screens || [];
  u.lightAnchors = u.lightAnchors || [];
  u.parts = u.parts || {};
  if (u.interact === undefined) u.interact = null;
  if (!u.size) {
    const bb = new THREE.Box3().setFromObject(g);
    const s = bb.getSize(new THREE.Vector3());
    u.size = [s.x, s.y, s.z].map(r3);
  }
}

export function cloneProp(src) {
  const ud = src.userData;
  src.userData = {};
  const c = src.clone(true);
  src.userData = ud;
  const map = new Map();
  (function walk(a, b) {
    map.set(a, b);
    for (let i = 0; i < a.children.length; i++) walk(a.children[i], b.children[i]);
  })(src, c);
  const remap = (v) => {
    if (v && v.isObject3D) return map.get(v) ?? v;
    if (Array.isArray(v)) return v.map(remap);
    if (v && v.constructor === Object) {
      const o = {};
      for (const k in v) o[k] = remap(v[k]);
      return o;
    }
    return v;
  };
  c.userData = remap(ud);
  return c;
}

// Set-dressing test scenes for tools/propview (artists may register their own from their category modules).
// spec: { floor:'shag'|'tile'|'wood'|hex, floorColor, wall:'panel'|'plain'|hex, room:[w,d] (default [6,5]),
//         items:[{ id, pos:[x,z]|[x,y,z], rotY, opts }], cam:{ pos:[x,y,z], target:[x,y,z], fov } }
export function registerScene(name, spec) { SCENES.set(name, spec); }
export function getScene(name) { return SCENES.get(name) || null; }
export function listScenes() { return [...SCENES.keys()]; }

// ============================================================================================= materials
// Roughness/metal/rim presets tuned for the toon shader + ACES grade. env = RoomEnvironment reflection amount:
// keep it low on dielectrics (its HDR light panels bloom on up-facing glossy tops above ~0.15). All force vertexColors (bakeAO writes
// them). Colors: pass a hex; textured presets usually use '#ffffff' and put the color in the canvas texture.
export const MAT = {
  lacquer: { rough: 0.36, rim: 0.22, env: 0.12 },          // glossy lacquered wood / enamel paint
  walnut: { rough: 0.42, rim: 0.2, env: 0.08 },
  teak: { rough: 0.5, rim: 0.2, env: 0.05 },
  vinyl: { rough: 0.36, rim: 0.32, env: 0.1 },            // naugahyde, tolex
  chrome: { rough: 0.2, metal: 1, rim: 0.18, env: 0.55 },   // use mid-grey colors (#A8B0BA): env adds the shine
  brass: { rough: 0.3, metal: 1, rim: 0.2, env: 0.45 },
  plastic: { rough: 0.34, rim: 0.3, env: 0.12 },            // ABS / bakelite
  fabric: { rough: 0.95, rim: 0.5, wrap: 0.7, rimPower: 1.8 }, // velvet-ish sheen on silhouettes
  felt: { rough: 1, rim: 0.55, wrap: 0.75, rimPower: 1.6 },
  crt: { rough: 0.06, rim: 0.55, env: 0.5 },               // dark glass (unpowered tubes, lenses)
  rubber: { rough: 0.85, rim: 0.12 },
  paint: { rough: 0.6, rim: 0.2 },                         // matte painted wood/metal
  metal: { rough: 0.42, metal: 0.7, rim: 0.2, env: 0.35 }, // brushed / painted steel
  ceramic: { rough: 0.22, rim: 0.3, env: 0.15 },
  soil: { rough: 1, rim: 0.05 },
  leaf: { rough: 0.55, rim: 0.4, wrap: 0.8, side: THREE.DoubleSide, rimColor: '#EFFFB0' },
};

export function mat(game, preset = 'plastic', color = '#ffffff', extra = {}) {
  const p = MAT[preset];
  if (!p) console.warn(`[props] unknown material preset "${preset}"`);
  return game.mats.toon(color, { ...(p || {}), vertexColors: true, ...extra });
}

export function glow(game, color = PAL.tungsten, intensity = 2.5, opts = {}) {
  return game.mats.glow(color, intensity, opts);
}

// CRT/monitor face: slightly domed plane with the engine CRT material. Push the result into
// userData.screens as { mesh, group } so rooms can hand it to game.screens.register (placeProp does it).
// opts: { card='station_id' (preview art until ScreenManager takes over), bright=0.85, dome=0.012, bulge, group='scr_decor' }
export function screen(game, w, h, opts = {}) {
  const dome = opts.dome ?? Math.min(w, h) * 0.05;
  const g = new THREE.PlaneGeometry(w, h, 12, 9);
  const pos = g.attributes.position;
  for (let i = 0; i < pos.count; i++) {
    const x = (pos.getX(i) / w) * 2, y = (pos.getY(i) / h) * 2;
    pos.setZ(i, dome * (1 - x * x * 0.5 - y * y * 0.5));
  }
  g.computeVertexNormals();
  g.rotateY(Math.PI); // face -z (prop front)
  const card = opts.card === null ? null : getCard(opts.card ?? 'station_id');
  const mt = game.mats.screen(card, { w, h, bulge: opts.bulge ?? 0, bright: opts.bright ?? 0.85 });
  const mesh = new THREE.Mesh(g, mt);
  mesh.name = 'screen';
  mesh.userData.noMerge = true;
  mesh.userData.screenGroup = opts.group ?? 'scr_decor';
  mesh.castShadow = false;
  return mesh;
}

// ============================================================================================== geometry
// Bevel radius presets (meters). Never ship raw box edges: xs for trims, sm/md for furniture, lg/xl for chunky toys.
export const R = { xs: 0.006, sm: 0.012, md: 0.025, lg: 0.05, xl: 0.09 };
const r3 = (n) => Math.round(n * 1000) / 1000;
const rad = (r) => (typeof r === 'string' ? R[r] ?? R.md : r);

// Rounded box, centered. r: preset name or meters (clamped). seg auto: 1 for tiny radii, 2, 3 for big ones.
// opts.uv = repeats per meter -> box-projected UVs (consistent texel density; returns an own copy).
export function box(w, h, d, r = 'md', opts = {}) {
  let rr = Math.min(rad(r), Math.min(w, h, d) / 2 - 1e-4);
  rr = Math.max(rr, 1e-4);
  const seg = opts.seg ?? (rr < 0.015 ? 1 : rr < 0.05 ? 2 : 3); // 108 / 300 / 588 tris
  const g = G.roundedBox(w, h, d, rr, seg);
  return opts.uv ? uvBox(g, opts.uv, opts) : g;
}

// Box-projected UVs (dominant normal axis), `perMeter` texture repeats per meter. Returns a new geometry.
// swap: rotate the pattern 90deg (e.g. wood grain along x on a table top).
export function uvBox(geo, perMeter = 1, { swap = false } = {}) {
  const g = geo.clone();
  const p = g.attributes.position, n = g.attributes.normal;
  const uv = new Float32Array(p.count * 2);
  for (let i = 0; i < p.count; i++) {
    const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i)), az = Math.abs(n.getZ(i));
    let u, v;
    if (ay >= ax && ay >= az) { u = p.getX(i); v = p.getZ(i); } else if (ax >= az) { u = p.getZ(i); v = p.getY(i); } else { u = p.getX(i); v = p.getY(i); }
    if (swap) { const t = u; u = v; v = t; }
    uv[i * 2] = u * perMeter; uv[i * 2 + 1] = v * perMeter;
  }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  return g;
}

// Tapers a geometry along an axis (returns a copy): cross-section scaled from 1 at the min end to `k` at the max
// end (TV backs, cabinets, lamp bases, speaker boxes). opts: { axis='z', k=0.7, center:[cx,cy] of the cross-section
// (default 0,0), ease=1 (exponent) }. Call before positioning.
export function taper(geo, { axis = 'z', k = 0.7, center = [0, 0], ease = 1 } = {}) {
  const g = geo.clone();
  const p = g.attributes.position;
  g.computeBoundingBox();
  const ai = { x: 0, y: 1, z: 2 }[axis];
  const lo = g.boundingBox.min.getComponent(ai), hi = g.boundingBox.max.getComponent(ai);
  const [u, v] = [0, 1, 2].filter((i) => i !== ai);
  const a = [0, 0, 0];
  for (let i = 0; i < p.count; i++) {
    a[0] = p.getX(i); a[1] = p.getY(i); a[2] = p.getZ(i);
    const t = Math.pow((a[ai] - lo) / Math.max(1e-6, hi - lo), ease);
    const s = 1 + (k - 1) * t;
    a[u] = center[0] + (a[u] - center[0]) * s;
    a[v] = center[1] + (a[v] - center[1]) * s;
    p.setXYZ(i, a[0], a[1], a[2]);
  }
  g.computeVertexNormals();
  return g;
}

// Remaps a geometry's 0..1 UVs into the atlas rect [u0,v0]-[u1,v1] in place (returns it; use on your own copy).
export function uvRect(g, u0, v0, u1, v1) {
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, u0 + uv.getX(i) * (u1 - u0), v0 + uv.getY(i) * (v1 - v0));
  uv.needsUpdate = true;
  return g;
}

// Scales a geometry's UVs in place (returns it). Use on your own copies (not on cached kit/geo results).
export function uvScale(g, su = 1, sv = su) {
  const uv = g.attributes.uv;
  if (!uv) return g;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * su, uv.getY(i) * sv);
  uv.needsUpdate = true;
  return g;
}

// Averages normals of coincident vertices (removes shading seams on welded-looking shapes).
export function weldNormals(g, eps = 1e-4) {
  const p = g.attributes.position, n = g.attributes.normal;
  const acc = new Map();
  const key = (i) => `${Math.round(p.getX(i) / eps)},${Math.round(p.getY(i) / eps)},${Math.round(p.getZ(i) / eps)}`;
  for (let i = 0; i < p.count; i++) {
    const k = key(i);
    const a = acc.get(k) || [0, 0, 0];
    a[0] += n.getX(i); a[1] += n.getY(i); a[2] += n.getZ(i);
    acc.set(k, a);
  }
  const v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    const a = acc.get(key(i));
    v.set(a[0], a[1], a[2]).normalize();
    n.setXYZ(i, v.x, v.y, v.z);
  }
  n.needsUpdate = true;
  return g;
}

// Upholstery cushion: rounded box with extra face subdivisions and a soft "puff" (faces bulge, edges stay put).
// opts: { r (edge radius, default 30% of the thinnest side), puff (m, default 0.18*h), seg:[nx,ny,nz], uv, swap }
export function cushion(w, h, d, opts = {}) {
  const key = `cush|${r3(w)}|${r3(h)}|${r3(d)}|${JSON.stringify(opts)}`;
  return cachedGeo(key, () => {
    const hx = w / 2, hy = h / 2, hz = d / 2;
    const r = Math.min(opts.r ?? Math.min(w, h, d) * 0.3, hx - 1e-3, hy - 1e-3, hz - 1e-3);
    const puff = opts.puff ?? h * 0.18;
    const n = (s) => clamp(Math.round(s / 0.07) + 2, 4, 12);
    const [nx, ny, nz] = opts.seg ?? [n(w), n(h), n(d)];
    const g = new THREE.BoxGeometry(2, 2, 2, nx, ny, nz);
    const pos = g.attributes.position;
    const f = (t) => Math.sign(t) * (0.45 * Math.abs(t) + 0.55 * (1 - (1 - Math.abs(t)) ** 2)); // denser near edges
    const faceMin = [Math.min(h, d), Math.min(w, d), Math.min(w, h)];
    const fm = Math.max(...faceMin);
    const c = new THREE.Vector3(), o = new THREE.Vector3();
    const inner = [hx - r, hy - r, hz - r];
    for (let i = 0; i < pos.count; i++) {
      const p = [f(pos.getX(i)) * hx, f(pos.getY(i)) * hy, f(pos.getZ(i)) * hz];
      c.set(clamp(p[0], -inner[0], inner[0]), clamp(p[1], -inner[1], inner[1]), clamp(p[2], -inner[2], inner[2]));
      o.set(p[0] - c.x, p[1] - c.y, p[2] - c.z).normalize();
      // puff along the dominant axis, fading to 0 at the edges
      const a = [Math.abs(o.x), Math.abs(o.y), Math.abs(o.z)];
      const dom = a[0] >= a[1] && a[0] >= a[2] ? 0 : a[1] >= a[2] ? 1 : 2;
      const t1 = (dom === 0 ? c.y / (inner[1] || 1) : c.x / (inner[0] || 1));
      const t2 = (dom === 2 ? c.y / (inner[1] || 1) : c.z / (inner[2] || 1));
      const wgt = (1 - t1 * t1) * (1 - t2 * t2) * a[dom] ** 2 * (faceMin[dom] / fm);
      const k = r + puff * Math.max(0, wgt);
      pos.setXYZ(i, c.x + o.x * k, c.y + o.y * k, c.z + o.z * k);
    }
    g.computeVertexNormals();
    weldNormals(g);
    return opts.uv ? uvBox(g, opts.uv, opts) : g;
  });
}

// Rounds the interior corners of a 2D polyline ([[x,y],...]) with quadratic arcs of radius r.
export function roundProfile(pts, r = 0.01, steps = 3) {
  const out = [pts[0]];
  for (let i = 1; i < pts.length - 1; i++) {
    const [px, py] = pts[i - 1], [x, y] = pts[i], [nx, ny] = pts[i + 1];
    const l0 = Math.hypot(px - x, py - y), l1 = Math.hypot(nx - x, ny - y);
    const rr = Array.isArray(r) ? r[i] ?? 0 : r;
    const d = Math.min(rr, l0 / 2, l1 / 2);
    if (d <= 1e-5) { out.push(pts[i]); continue; }
    const a = [x + ((px - x) / l0) * d, y + ((py - y) / l0) * d];
    const b = [x + ((nx - x) / l1) * d, y + ((ny - y) / l1) * d];
    for (let s = 0; s <= steps; s++) {
      const t = s / steps, u = 1 - t;
      out.push([u * u * a[0] + 2 * u * t * x + t * t * b[0], u * u * a[1] + 2 * u * t * y + t * t * b[1]]);
    }
  }
  out.push(pts[pts.length - 1]);
  return out;
}

// Lathe around Y from a [[radius, y], ...] profile (bottom to top). opts: { seg=20, round (corner radius), steps=2 }
export function lathe(profile, opts = {}) {
  const pts = opts.round ? roundProfile(profile, opts.round, opts.steps ?? 2) : profile;
  return G.lathe(pts.map(([x, y]) => [Math.max(0, x), y]), opts.seg ?? 20);
}

// Bevelled solid cylinder / cone, BASE AT y=0 (closed caps, soft rims). opts: { bevel=0.008, seg=20 }
export function cyl(rt, rb, h, opts = {}) {
  const b = Math.min(opts.bevel ?? 0.008, rt * 0.5 || rb * 0.5, h / 2);
  return lathe([[0, 0], [rb, 0], [rt, h], [0, h]], { round: b, seg: opts.seg ?? 20, steps: 2 });
}

export function roundRect(w, h, r = 0.02) {
  const s = new THREE.Shape();
  const x = -w / 2, y = -h / 2;
  r = Math.min(r, w / 2 - 1e-4, h / 2 - 1e-4);
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y); s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + h - r); s.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  s.lineTo(x + r, y + h); s.quadraticCurveTo(x, y + h, x, y + h - r);
  s.lineTo(x, y + r); s.quadraticCurveTo(x, y, x + r, y);
  return s;
}

// Extruded bevelled slab along z (centered). shape: THREE.Shape or [[x,y],...] (corners rounded by opts.round).
// Outer size equals the shape (bevel is inset), total thickness equals depth. UVs: shape meters * opts.uv.
export function extrude(shape, depth, opts = {}) {
  const bevel = Math.min(opts.bevel ?? 0.008, depth / 2 - 1e-4);
  let s = shape;
  if (Array.isArray(shape)) {
    const pts = opts.round ? roundProfile([...shape, shape[0]], opts.round).slice(0, -1) : shape;
    s = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, y)));
  }
  const g = new THREE.ExtrudeGeometry(s, {
    depth: Math.max(1e-4, depth - bevel * 2), bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel,
    bevelOffset: -bevel, bevelSegments: opts.bevelSeg ?? 2, curveSegments: opts.curveSeg ?? 12,
  });
  g.translate(0, 0, -(depth - bevel * 2) / 2);
  if (opts.uv && opts.uv !== 1) {
    const uv = g.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * opts.uv, uv.getY(i) * opts.uv);
  }
  g.computeVertexNormals();
  return g;
}

// Tube along a Catmull-Rom curve through [[x,y,z],...]. opts: { seg=24, radial=8, closed=false }
export function tube(points, r, opts = {}) {
  return G.tube(points, r, opts.seg ?? 24, opts.radial ?? 8, opts.closed ?? false);
}

// Closed rounded-rectangle path at height y (for piping/welt cords around cushions, rims, table edges).
export function roundRectPath(w, d, r, y = 0, steps = 4) {
  const pts = [];
  const hx = w / 2 - r, hz = d / 2 - r;
  const corners = [[hx, hz, 0], [-hx, hz, Math.PI / 2], [-hx, -hz, Math.PI], [hx, -hz, Math.PI * 1.5]];
  for (const [cx, cz, a0] of corners) {
    for (let s = 0; s <= steps; s++) {
      const a = a0 + (s / steps) * (Math.PI / 2);
      pts.push([cx + Math.cos(a) * r, y, cz + Math.sin(a) * r]);
    }
  }
  return pts;
}

// One leaf: pointed blade with a V fold, arching from angle a0 to a1 (radians above horizontal), growing
// along +z from the origin. opts: { a0=1.1, a1=-0.35, fold=0.35, segL=8, segW=2, tip=0.8, twist=0 }
export function leaf(len = 0.4, width = 0.12, opts = {}) {
  const { a0 = 1.1, a1 = -0.35, fold = 0.35, segL = 8, segW = 2, tip = 0.8, twist = 0 } = opts;
  const cols = segW * 2 + 1;
  const pos = [], uv = [], idx = [];
  let y = 0, z = 0;
  const step = len / segL;
  for (let i = 0; i <= segL; i++) {
    const s = i / segL;
    const a = lerp(a0, a1, s * s * 0.6 + s * 0.4);
    if (i > 0) { y += Math.sin(a) * step; z += Math.cos(a) * step; }
    const half = width * 0.5 * Math.pow(Math.sin(Math.PI * Math.min(1, s * (1 - 0.001)) ** tip), 0.85) * (s < 0.08 ? s / 0.08 * 0.4 + 0.2 : 1);
    const tw = twist * s;
    for (let j = 0; j < cols; j++) {
      const u = (j / (cols - 1)) * 2 - 1;
      const x = u * half;
      const lift = Math.abs(u) * half * fold;
      // perpendicular to the blade direction in the yz plane for the fold
      const ny = Math.cos(a), nz = -Math.sin(a);
      pos.push(x * Math.cos(tw), y + lift * ny + x * Math.sin(tw), z + lift * nz);
      uv.push(j / (cols - 1), s);
    }
  }
  for (let i = 0; i < segL; i++) {
    for (let j = 0; j < cols - 1; j++) {
      const a = i * cols + j, b = a + 1, c = a + cols, d = c + 1;
      idx.push(a, c, b, b, c, d);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

// A crown of leaves around +y (houseplants, ferns, palms). Returns ONE merged geometry with per-leaf vertex
// color variation (multiplied into bakeAO). opts: { count=9, len=[0.35,0.5], width=0.13, a0=[0.9,1.35],
// a1=[-0.5,0.1], fold, seed=1, spread=0.03 (base radius), vary=0.18 (lightness variation), tilt=0 }
export function leafCluster(opts = {}) {
  const { count = 9, len = [0.35, 0.5], width = 0.13, a0 = [0.9, 1.35], a1 = [-0.5, 0.1], fold = 0.35,
    seed = 1, spread = 0.03, vary = 0.18, segL = 8 } = opts;
  const rnd = mulberry32(seed * 7919 + 13);
  const rr = (v) => (Array.isArray(v) ? lerp(v[0], v[1], rnd()) : v);
  const geos = [];
  for (let i = 0; i < count; i++) {
    const ang = i * 2.39996 + rnd() * 0.4;
    const g = leaf(rr(len), rr(width), { a0: rr(a0), a1: rr(a1), fold, segL, twist: (rnd() - 0.5) * 0.6 });
    g.rotateY(ang);
    g.translate(Math.sin(ang) * spread, rnd() * 0.02, Math.cos(ang) * spread);
    const k = 1 - vary / 2 + rnd() * vary;
    tint(g, new THREE.Color(k, k * (0.98 + rnd() * 0.04), k * 0.95));
    geos.push(g);
  }
  const out = mergeGeometries(geos, false);
  geos.forEach((g) => g.dispose());
  return out;
}

// Multiplies a per-vertex color into a geometry (creates the attribute). color: THREE.Color|hex|fn(x,y,z)->Color
export function tint(g, color) {
  const p = g.attributes.position;
  let col = g.attributes.color;
  if (!col) {
    col = new THREE.BufferAttribute(new Float32Array(p.count * 3).fill(1), 3);
    g.setAttribute('color', col);
  }
  const c = new THREE.Color();
  const fixed = typeof color === 'function' ? null : new THREE.Color(color);
  for (let i = 0; i < p.count; i++) {
    if (fixed) c.copy(fixed); else c.copy(color(p.getX(i), p.getY(i), p.getZ(i)));
    col.setXYZ(i, col.getX(i) * c.r, col.getY(i) * c.g, col.getZ(i) * c.b);
  }
  col.needsUpdate = true;
  return g;
}

// Mesh shortcut: m(geo, mat, { pos, rot, scale, name, cast, receive }).
export const m = G.mesh;

const geoCache = new Map();
function cachedGeo(key, make) {
  let g = geoCache.get(key);
  if (!g) { g = make(); g.name = key; geoCache.set(key, g); }
  return g;
}

// ============================================================================================== textures
// All return cached sRGB CanvasTextures (RepeatWrapping unless noted), deterministic per arguments.
const texCache = new Map();
const fontTex = [];
function hashStr(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}
function shade(hex, amt) {
  const c = new THREE.Color(hex);
  if (amt >= 0) c.lerp(new THREE.Color(1, 1, 1), amt); else c.multiplyScalar(1 + amt);
  return '#' + c.getHexString();
}

// Generic cached canvas texture: draw(ctx, w, h, rand). opts: { repeat=true, fonts=false (redraw on font load) }
function canvasTex(key, w, h, draw, opts = {}) {
  let t = texCache.get(key);
  if (t) return t;
  const cv = document.createElement('canvas');
  cv.width = w; cv.height = h;
  const ctx = cv.getContext('2d');
  const paint = () => { ctx.clearRect(0, 0, w, h); draw(ctx, w, h, mulberry32(hashStr(key))); };
  paint();
  t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  if (opts.repeat !== false) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.name = key;
  texCache.set(key, t);
  if (opts.fonts) fontTex.push(() => { paint(); t.needsUpdate = true; });
  return t;
}
if (typeof document !== 'undefined' && document.fonts) {
  document.fonts.addEventListener?.('loadingdone', () => fontTex.forEach((f) => f()));
}

// Scuffs / scratches / edge wear, drawn over a texture's canvas.
function wear(ctx, w, h, rand, amount = 0.5, color = '#000') {
  if (amount <= 0) return;
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineCap = 'round';
  for (let i = 0; i < 60 * amount; i++) {
    ctx.globalAlpha = 0.04 + rand() * 0.1 * amount;
    ctx.lineWidth = 0.5 + rand() * 1.5;
    const x = rand() * w, y = rand() * h, a = rand() * Math.PI, l = 4 + rand() * 30;
    ctx.beginPath(); ctx.moveTo(x, y);
    ctx.quadraticCurveTo(x + Math.cos(a) * l * 0.5 + rand() * 4, y + Math.sin(a) * l * 0.5, x + Math.cos(a) * l, y + Math.sin(a) * l);
    ctx.stroke();
  }
  for (let i = 0; i < 25 * amount; i++) {
    ctx.globalAlpha = 0.03 + rand() * 0.06 * amount;
    ctx.fillStyle = color;
    ctx.beginPath(); ctx.ellipse(rand() * w, rand() * h, 3 + rand() * 14, 2 + rand() * 8, rand() * 3, 0, Math.PI * 2); ctx.fill();
  }
  ctx.restore();
}

export const tex = {
  canvas: canvasTex,

  // Long-grain wood (flat-sawn cathedrals + straight grain + color bands). Grain runs along V (texture y).
  // opts: { planks=0 (vertical seams), dark=0.32 (grain contrast), wear=0, size=512 }
  wood(base = PAL.teak, opts = {}) {
    const { planks = 0, dark = 0.32, wear: wr = 0, size = 512 } = opts;
    return canvasTex(`k.wood|${base}|${planks}|${dark}|${wr}|${size}`, size, size, (ctx, w, h, rand) => {
      ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
      for (let i = 0; i < 14; i++) { // soft color bands
        ctx.globalAlpha = 0.12 + rand() * 0.12;
        ctx.fillStyle = shade(base, (rand() - 0.5) * 0.3);
        ctx.fillRect(rand() * w, 0, 8 + rand() * 40, h);
      }
      ctx.lineCap = 'round';
      for (let i = 0; i < 70; i++) { // straight grain lines (wrap horizontally)
        const x0 = rand() * w, amp = 1 + rand() * 4, fr = 0.004 + rand() * 0.01, ph = rand() * 6;
        ctx.strokeStyle = shade(base, -dark * (0.4 + rand() * 0.8));
        ctx.globalAlpha = 0.25 + rand() * 0.35;
        ctx.lineWidth = 0.6 + rand() * 1.4;
        for (const off of [0, -w, w]) {
          ctx.beginPath();
          for (let y = 0; y <= h; y += 8) {
            const x = x0 + off + Math.sin(y * fr * 6.283 / 6 + ph) * amp + Math.sin(y * 0.05 + i) * 0.6;
            if (y === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
          }
          ctx.stroke();
        }
      }
      for (let k = 0; k < 3; k++) { // cathedral arches
        const cx = rand() * w, cy = rand() * h, spread = 30 + rand() * 50;
        for (let r = 0; r < 7; r++) {
          ctx.strokeStyle = shade(base, -dark * (0.5 + rand() * 0.5));
          ctx.globalAlpha = 0.18 + rand() * 0.2;
          ctx.lineWidth = 1 + rand() * 1.5;
          const s = spread * (0.35 + r * 0.14);
          ctx.beginPath();
          ctx.moveTo(cx - s, cy + h * 0.45);
          ctx.bezierCurveTo(cx - s, cy - s * 0.3, cx + s * 0.9, cy - s * 0.4, cx + s, cy + h * 0.45);
          ctx.stroke();
        }
      }
      ctx.globalAlpha = 1;
      if (planks > 0) {
        const pw = w / planks;
        for (let p = 0; p < planks; p++) {
          ctx.fillStyle = shade(base, -0.6); ctx.fillRect(p * pw, 0, 2, h);
          ctx.fillStyle = shade(base, 0.2); ctx.fillRect(p * pw + 2, 0, 1, h);
          ctx.globalAlpha = 0.1; ctx.fillStyle = rand() < 0.5 ? '#000' : '#fff'; ctx.fillRect(p * pw + 3, 0, pw - 3, h); ctx.globalAlpha = 1;
        }
      }
      wear(ctx, w, h, rand, wr, shade(base, -0.7));
    });
  },

  // Walnut burl veneer (swirls and eyes): dashboards, console trims, radio cabinets.
  burl(base = PAL.walnut, opts = {}) {
    const { size = 512 } = opts;
    return canvasTex(`k.burl|${base}|${size}`, size, size, (ctx, w, h, rand) => {
      ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
      for (let i = 0; i < 260; i++) {
        const x = rand() * w, y = rand() * h, r = 4 + rand() * 26;
        ctx.strokeStyle = shade(base, rand() < 0.6 ? -0.35 - rand() * 0.3 : 0.15 + rand() * 0.15);
        ctx.globalAlpha = 0.15 + rand() * 0.3;
        ctx.lineWidth = 0.8 + rand() * 1.6;
        ctx.beginPath(); ctx.ellipse(x, y, r, r * (0.4 + rand() * 0.6), rand() * 3.14, 0, Math.PI * (1 + rand())); ctx.stroke();
      }
      for (let i = 0; i < 40; i++) {
        ctx.fillStyle = shade(base, -0.6); ctx.globalAlpha = 0.5;
        ctx.beginPath(); ctx.arc(rand() * w, rand() * h, 1 + rand() * 2.5, 0, 7); ctx.fill();
      }
      ctx.globalAlpha = 1;
    });
  },

  // Shag pile: dense short strands with light tips and dark roots. fleck = second yarn color.
  shag(base = PAL.shagOrange, fleck = PAL.harvestGold, opts = {}) {
    const { size = 512, density = 1 } = opts;
    return canvasTex(`k.shag|${base}|${fleck}|${size}|${density}`, size, size, (ctx, w, h, rand) => {
      ctx.fillStyle = shade(base, -0.35); ctx.fillRect(0, 0, w, h);
      ctx.lineCap = 'round';
      const n = Math.round(size * size * 0.09 * density);
      for (let i = 0; i < n; i++) {
        const x = rand() * w, y = rand() * h, a = rand() * 6.283, l = 3 + rand() * 6;
        const r = rand();
        ctx.strokeStyle = r < 0.08 ? fleck : shade(base, -0.3 + rand() * 0.45);
        ctx.globalAlpha = 0.55 + rand() * 0.45;
        ctx.lineWidth = 1.4 + rand() * 1.6;
        ctx.beginPath(); ctx.moveTo(x, y);
        ctx.quadraticCurveTo(x + Math.cos(a + 0.8) * l * 0.6, y + Math.sin(a + 0.8) * l * 0.6, x + Math.cos(a) * l, y + Math.sin(a) * l);
        ctx.stroke();
        if (rand() < 0.3) { // bright tip
          ctx.fillStyle = shade(r < 0.08 ? fleck : base, 0.25); ctx.globalAlpha = 0.6;
          ctx.fillRect(x + Math.cos(a) * l - 0.8, y + Math.sin(a) * l - 0.8, 1.6, 1.6);
        }
      }
      ctx.globalAlpha = 1;
    });
  },

  // Upholstery weave. pattern: 'plain' | 'tweed' (multi-color flecks) | 'cord' (corduroy ribs along V) | 'herring'
  weave(base = PAL.avocado, opts = {}) {
    const { pattern = 'plain', thread = null, fleck = [], size = 256, scale = 4 } = opts;
    return canvasTex(`k.weave|${base}|${pattern}|${thread}|${fleck}|${size}|${scale}`, size, size, (ctx, w, h, rand) => {
      ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
      const s = scale;
      const lite = thread ?? shade(base, 0.14), dark = shade(base, -0.22);
      if (pattern === 'cord') {
        for (let x = 0; x < w; x += s * 2) {
          const g = ctx.createLinearGradient(x, 0, x + s * 2, 0);
          g.addColorStop(0, dark); g.addColorStop(0.5, lite); g.addColorStop(1, dark);
          ctx.fillStyle = g; ctx.fillRect(x, 0, s * 2, h);
        }
      } else if (pattern === 'herring') {
        for (let y = 0; y < h; y += s) for (let x = 0; x < w; x += s) {
          const band = Math.floor(x / (s * 4)) % 2;
          ctx.fillStyle = ((x / s + (band ? y / s : -y / s)) & 3) < 2 ? lite : dark;
          ctx.globalAlpha = 0.5; ctx.fillRect(x, y, s, s);
        }
      } else {
        for (let y = 0; y < h; y += s) for (let x = 0; x < w; x += s) {
          ctx.fillStyle = ((x + y) / s) % 2 ? lite : dark;
          ctx.globalAlpha = 0.35 + rand() * 0.15;
          ctx.fillRect(x, y, s, s * 0.8);
        }
      }
      ctx.globalAlpha = 1;
      const fl = pattern === 'tweed' && !fleck.length ? [shade(base, 0.35), shade(base, -0.45), PAL.cream] : fleck;
      for (let i = 0; i < (fl.length ? size * 6 : size * 2); i++) {
        ctx.fillStyle = fl.length ? fl[Math.floor(rand() * fl.length)] : rand() < 0.5 ? '#fff' : '#000';
        ctx.globalAlpha = fl.length ? 0.5 + rand() * 0.4 : 0.05;
        ctx.fillRect(rand() * w, rand() * h, 1 + rand() * 2.5, 1);
      }
      ctx.globalAlpha = 1;
    });
  },

  // Pebbled leatherette / tolex / vinyl grain.
  pebble(base = PAL.chocolate, opts = {}) {
    const { size = 256 } = opts;
    return canvasTex(`k.pebble|${base}|${size}`, size, size, (ctx, w, h, rand) => {
      ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
      for (let i = 0; i < size * 10; i++) {
        ctx.fillStyle = rand() < 0.5 ? shade(base, -0.18) : shade(base, 0.1);
        ctx.globalAlpha = 0.35;
        ctx.beginPath(); ctx.arc(rand() * w, rand() * h, 0.6 + rand() * 1.6, 0, 7); ctx.fill();
      }
      ctx.globalAlpha = 1;
    });
  },

  // Brushed metal: fine horizontal streaks (along U).
  brushed(base = '#C9CED6', opts = {}) {
    const { size = 256 } = opts;
    return canvasTex(`k.brushed|${base}|${size}`, size, size, (ctx, w, h, rand) => {
      ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
      for (let i = 0; i < size * 3; i++) {
        ctx.fillStyle = rand() < 0.5 ? shade(base, 0.25) : shade(base, -0.2);
        ctx.globalAlpha = 0.15 + rand() * 0.2;
        ctx.fillRect(rand() * w - 20, rand() * h, 20 + rand() * 120, 1);
      }
      ctx.globalAlpha = 1;
    });
  },

  // Printed label / decal / nameplate (not repeating). opts: { sub, bg, fg, accent, font='Bungee', subFont='Titan One',
  // w=512, h=256, radius=0.12 (of h), border=0.05 (of h), stripes:[colors] (70s racing stripes under the text),
  // wear=0.2, transparent=false (bg outside the rounded rect) }
  label(text = 'WZTV', opts = {}) {
    const { sub = '', bg = PAL.cream, fg = PAL.chocolate, accent = PAL.burntOrange, font = 'Bungee', subFont = 'Titan One',
      w = 512, h = 256, radius = 0.12, border = 0.05, stripes = null, wear: wr = 0.2, transparent = false, outline = null } = opts;
    return canvasTex(`k.label|${text}|${JSON.stringify(opts)}`, w, h, (ctx, W, H, rand) => {
      if (!transparent) { ctx.fillStyle = shade(bg, -0.35); ctx.fillRect(0, 0, W, H); }
      const r = H * radius, b = H * border;
      const rr = (x, y, ww, hh, rad) => { ctx.beginPath(); ctx.roundRect(x, y, ww, hh, rad); };
      rr(0, 0, W, H, r); ctx.fillStyle = accent; ctx.fill();
      rr(b, b, W - 2 * b, H - 2 * b, Math.max(1, r - b)); ctx.fillStyle = bg; ctx.fill();
      ctx.save(); ctx.clip();
      if (stripes) {
        const sh = (H - 2 * b) * 0.1;
        stripes.forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(0, H * 0.62 + i * sh * 1.1, W, sh); });
      }
      ctx.restore();
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      let size = H * (sub ? 0.42 : 0.55);
      const fit = (f, s, max) => { ctx.font = `${s}px "${f}", "Arial Black", sans-serif`; while (ctx.measureText(text).width > max && s > 6) { s *= 0.93; ctx.font = `${s}px "${f}", "Arial Black", sans-serif`; } return s; };
      size = fit(font, size, W * 0.84);
      const ty = sub ? H * 0.4 : H * 0.52;
      if (outline) { ctx.lineWidth = size * 0.14; ctx.strokeStyle = outline; ctx.lineJoin = 'round'; ctx.strokeText(text, W / 2, ty); }
      ctx.fillStyle = shade(fg, -0.35); ctx.globalAlpha = 0.35; ctx.fillText(text, W / 2 + size * 0.05, ty + size * 0.06);
      ctx.globalAlpha = 1; ctx.fillStyle = fg; ctx.fillText(text, W / 2, ty);
      if (sub) {
        let ss = H * 0.17;
        ctx.font = `${ss}px "${subFont}", "Arial Black", sans-serif`;
        while (ctx.measureText(sub).width > W * 0.8 && ss > 6) { ss *= 0.93; ctx.font = `${ss}px "${subFont}", "Arial Black", sans-serif`; }
        ctx.fillStyle = accent; ctx.fillText(sub, W / 2, H * 0.74);
      }
      wear(ctx, W, H, rand, wr, shade(bg, -0.6));
    }, { repeat: false, fonts: true });
  },
};

// ================================================================================================ baking
// Vertex-color ambient occlusion, run once at build time on the prop's own geometry:
//   (a) height band: darkens the bottom `height` meters (contact with the floor),
//   (b) occlusion: `rays` cosine-weighted rays per vertex, marched through a voxelization of every opaque mesh
//       in the group (+ the floor plane at floorY), weighted by hit distance — crevices, under-tops, between
//       cushions, inside cabinets go dark. Colors are multiplied into existing vertex colors (tint() etc.).
// Meshes need materials with vertexColors (mat() presets do; finish() converts other toon materials).
// Every processed mesh gets its own geometry copy. opts: { rays=14, dist (m, default 30% of the largest side,
// clamped 0.12..0.6), strength=0.85, height=0.22, heightStrength=0.35, floorY=0, floor=true, res=44,
// tint=PAL.shadow-ish, skip:(mesh)=>bool }
// Load time (the bake was ~40% of boot): the result is bit-identical to the straightforward Vector3 version
// (tools/scenarios/perf_ao_verify.js checks every prop), but vertices are transformed once per mesh into Float64
// scratch, the voxel and ray loops are scalar code in the exact operation order of the Vector3 calls they replace,
// a vertex that repeats an earlier local position + normal (non-indexed rounded boxes repeat each corner ~6x) is
// marched once, and a bake whose inputs hash equal to an earlier one (geometry, transforms, occluder/target roles,
// opts: props rebuilt per placement, e.g. every prop with a screen) reuses the earlier per-vertex shade factors.
// aoStats = { bakes, hits, verts, marched, ms } (cumulative). globalThis.__propkitBakeAO(root, opts) overrides the
// bake (verification tools); globalThis.__propkitNoAO skips it in finish().
export const aoStats = { bakes: 0, hits: 0, verts: 0, marched: 0, ms: 0 };
const aoCache = new Map(); // content hash -> Float64Array[] (shadeK per vertex, one per target mesh)
let _f64 = new Float64Array(0), _u32 = new Uint32Array(0);
let _f64b = new Float64Array(0);
const scratch = (n) => { if (_f64.length < n) { _f64 = new Float64Array(n * 1.5 | 0); _u32 = new Uint32Array(_f64.buffer); } return _f64; };
const scratchB = (n) => { if (_f64b.length < n) _f64b = new Float64Array(n * 1.5 | 0); return _f64b; };

// 2 x 32-bit content hash (FNV-1a and a murmur-style mix) over everything bakeAO reads.
const _hf = new Float64Array(1), _hu = new Uint32Array(_hf.buffer);
class AOHash {
  constructor() { this.a = 0x811c9dc5 | 0; this.b = 0x3c6ef372 | 0; }
  u(x) {
    this.a = Math.imul(this.a ^ x, 0x01000193);
    const b = Math.imul(this.b ^ x, 0x5bd1e995);
    this.b = b ^ (b >>> 13);
  }
  f(x) { _hf[0] = x; this.u(_hu[0]); this.u(_hu[1]); }
  s(str) { for (let i = 0; i < str.length; i++) this.u(str.charCodeAt(i)); this.u(str.length); }
  attr(at) {
    if (!at) { this.u(0x9e3779b9); return; }
    this.u(at.itemSize | 0); this.u(at.normalized ? 1 : 0); this.u(at.count | 0);
    if (at.isInterleavedBufferAttribute || !at.array) {
      for (let i = 0; i < at.count; i++) {
        this.f(at.getX(i));
        if (at.itemSize > 1) this.f(at.getY(i));
        if (at.itemSize > 2) this.f(at.getZ(i));
        if (at.itemSize > 3) this.f(at.getW(i));
      }
      return;
    }
    const ta = at.array;
    this.s(ta.constructor.name);
    if (ta.BYTES_PER_ELEMENT === 4) {
      const v = new Uint32Array(ta.buffer, ta.byteOffset, ta.length);
      for (let i = 0; i < v.length; i++) this.u(v[i]);
    } else if (ta.BYTES_PER_ELEMENT === 8) {
      for (let i = 0; i < ta.length; i++) this.f(ta[i]);
    } else {
      for (let i = 0; i < ta.length; i++) this.u(ta[i] | 0);
    }
  }
  key() { return `${this.a >>> 0}.${this.b >>> 0}`; }
}

// Local position + normal of every vertex, as read by Vector3.fromBufferAttribute (getX..: denormalized).
function readLocal(pos, nor, out) {
  const n = pos.count;
  const plain = (a) => a && !a.isInterleavedBufferAttribute && !a.normalized && a.itemSize === 3;
  if (plain(pos) && plain(nor)) {
    const P = pos.array, N = nor.array;
    for (let i = 0, k = 0, j = 0; i < n; i++, k += 6, j += 3) {
      out[k] = P[j]; out[k + 1] = P[j + 1]; out[k + 2] = P[j + 2];
      out[k + 3] = N[j]; out[k + 4] = N[j + 1]; out[k + 5] = N[j + 2];
    }
  } else {
    for (let i = 0, k = 0; i < n; i++, k += 6) {
      out[k] = pos.getX(i); out[k + 1] = pos.getY(i); out[k + 2] = pos.getZ(i);
      out[k + 3] = nor.getX(i); out[k + 4] = nor.getY(i); out[k + 5] = nor.getZ(i);
    }
  }
}

export function bakeAO(root, opts = {}) {
  if (globalThis.__propkitBakeAO) return globalThis.__propkitBakeAO(root, opts);
  const T0 = performance.now();
  const { rays = 14, strength = 0.85, height = 0.22, heightStrength = 0.35, floorY = 0, floor = true, res = 44,
    tint: tintHex = '#4B3A5E', skip = null } = opts;
  root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const meshes = [];
  root.traverse((o) => { if (o.isMesh && o.visible && !o.isInstancedMesh && !o.isSkinnedMesh) meshes.push(o); });
  const occluders = meshes.filter((o) => !(o.material.transparent || o.material.userData?.noOcclude || o.userData.noOcclude));
  const targets = meshes.filter((o) => o.material.vertexColors && !o.userData.noAO && !(skip && skip(o)));
  if (!targets.length) return root;
  const occSet = new Set(occluders), tgtSet = new Set(targets);
  const tintC = new THREE.Color(tintHex);

  // bounds in root space (+ the content hash of every input)
  const H = new AOHash();
  H.f(rays); H.f(strength); H.f(height); H.f(heightStrength); H.f(floorY); H.u(floor ? 1 : 0); H.f(res);
  H.f(tintC.r); H.f(tintC.g); H.f(tintC.b); H.f(opts.dist ?? NaN);
  const bb = new THREE.Box3();
  const tmp = new THREE.Box3();
  const mtxOf = new Map();
  for (const o of meshes) {
    if (!o.geometry.boundingBox) o.geometry.computeBoundingBox();
    const m4 = new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld);
    mtxOf.set(o, m4);
    bb.union(tmp.copy(o.geometry.boundingBox).applyMatrix4(m4));
    const isT = tgtSet.has(o);
    H.u((occSet.has(o) ? 1 : 0) | (isT ? 2 : 0));
    for (let i = 0; i < 16; i++) H.f(m4.elements[i]);
    const gb = o.geometry.boundingBox;
    H.f(gb.min.x); H.f(gb.min.y); H.f(gb.min.z); H.f(gb.max.x); H.f(gb.max.y); H.f(gb.max.z);
    H.attr(o.geometry.attributes.position);
    H.attr(o.geometry.index);
    if (isT) H.attr(o.geometry.attributes.normal);
  }
  const key = H.key();
  aoStats.bakes++;
  let shades = aoCache.get(key);
  const hit = !!shades;
  if (hit) aoStats.hits++;
  else shades = bakeShades(opts, bb, occluders, targets, mtxOf, { rays, strength, height, heightStrength, floorY, floor, res });

  const tr = tintC.r, tg = tintC.g, tb = tintC.b;
  const out = [];
  for (let ti = 0; ti < targets.length; ti++) {
    const o = targets[ti];
    const g = o.geometry.clone();
    if (!g.attributes.normal) g.computeVertexNormals();
    const pos = g.attributes.position;
    let ca = g.attributes.color;
    if (!ca) { ca = new THREE.BufferAttribute(new Float32Array(pos.count * 3).fill(1), 3); g.setAttribute('color', ca); }
    const S = shades[ti];
    if (!S || S.length !== pos.count) { aoCache.delete(key); throw new Error('[props] bakeAO cache mismatch'); }
    for (let i = 0; i < pos.count; i++) {
      const s = S[i];
      ca.setXYZ(i, ca.getX(i) * (tr + (1 - tr) * s), ca.getY(i) * (tg + (1 - tg) * s), ca.getZ(i) * (tb + (1 - tb) * s));
    }
    ca.needsUpdate = true;
    out.push(g);
    aoStats.verts += pos.count;
  }
  for (let ti = 0; ti < targets.length; ti++) targets[ti].geometry = out[ti];
  if (!hit) aoCache.set(key, shades);
  aoStats.ms += performance.now() - T0;
  return root;
}

// The bake proper: per target mesh, shadeK (0.12..1) per vertex.
function bakeShades(opts, bb, occluders, targets, mtxOf, { rays, strength, height, heightStrength, floorY, floor, res }) {
  const size = bb.getSize(new THREE.Vector3());
  const maxDim = Math.max(size.x, size.y, size.z, 0.05);
  const cell = maxDim / res;
  const dist = opts.dist ?? clamp(maxDim * 0.3, 0.12, 0.6);
  const o0 = bb.min.clone().subScalar(cell * 2);
  const ox = o0.x, oy = o0.y, oz = o0.z;
  const nx = Math.ceil(size.x / cell) + 5, ny = Math.ceil(size.y / cell) + 5, nz = Math.ceil(size.z / cell) + 5;
  const vox = new Uint8Array(nx * ny * nz);

  // voxelize triangle surfaces by dense barycentric sampling
  voxelize(vox, occluders, mtxOf, ox, oy, oz, cell, nx, ny, nz);

  // cosine-weighted hemisphere directions (tangent space, z = normal), max ~72deg off-normal
  const dl = [];
  for (let i = 0; i < rays; i++) {
    const u = (i + 0.5) / rays, phi = i * 2.39996;
    const r = Math.sqrt(u) * 0.95;
    dl.push(Math.cos(phi) * r, Math.sin(phi) * r, Math.sqrt(1 - r * r));
  }
  const dirs = new Float64Array(dl), nd3 = dirs.length;
  const start = cell * 2.1, step = cell * 0.75;
  const fl = !!floor, hasH = height > 0, fy1 = floorY + height;
  const nMat = new THREE.Matrix3();
  const shades = [];

  for (const o of targets) {
    const geo = o.geometry;
    let nor = geo.attributes.normal;
    const pos = geo.attributes.position;
    if (!nor) { // same normals the caller's clone will compute
      const g2 = new THREE.BufferGeometry();
      g2.setAttribute('position', pos);
      if (geo.index) g2.setIndex(geo.index);
      g2.computeVertexNormals();
      nor = g2.attributes.normal;
    }
    const m4 = mtxOf.get(o), e = m4.elements;
    nMat.getNormalMatrix(m4);
    const ne = nMat.elements;
    const count = pos.count;
    const L = scratch(count * 6), LU = _u32;
    readLocal(pos, nor, L);
    const S = new Float64Array(count);
    // open-addressing table over the 6 local doubles (bit patterns): equal inputs -> equal shade
    let cap = 16;
    while (cap < count * 2) cap <<= 1;
    const mask = cap - 1;
    const table = new Int32Array(cap).fill(-1);
    for (let i = 0; i < count; i++) {
      const k = i * 6, w32 = i * 12;
      let h = 0x811c9dc5 | 0;
      for (let q = 0; q < 12; q++) h = Math.imul(h ^ LU[w32 + q], 0x01000193);
      let slot = (h ^ (h >>> 15)) & mask, found = -1;
      for (;;) {
        const j = table[slot];
        if (j < 0) { table[slot] = i; break; }
        const v32 = j * 12;
        let same = true;
        for (let q = 0; q < 12; q++) if (LU[v32 + q] !== LU[w32 + q]) { same = false; break; }
        if (same) { found = j; break; }
        slot = (slot + 1) & mask;
      }
      if (found >= 0) { S[i] = S[found]; continue; }
      aoStats.marched++;
      // p = position.applyMatrix4(mtx)
      const x = L[k], y = L[k + 1], z = L[k + 2];
      const w = 1 / (e[3] * x + e[7] * y + e[11] * z + e[15]);
      const px = (e[0] * x + e[4] * y + e[8] * z + e[12]) * w;
      const py = (e[1] * x + e[5] * y + e[9] * z + e[13]) * w;
      const pz = (e[2] * x + e[6] * y + e[10] * z + e[14]) * w;
      // nrm = normal.applyMatrix3(nMat).normalize()
      const lx = L[k + 3], ly = L[k + 4], lz = L[k + 5];
      let nX = ne[0] * lx + ne[3] * ly + ne[6] * lz;
      let nY = ne[1] * lx + ne[4] * ly + ne[7] * lz;
      let nZ = ne[2] * lx + ne[5] * ly + ne[8] * lz;
      let s = 1 / (Math.sqrt(nX * nX + nY * nY + nZ * nZ) || 1);
      nX *= s; nY *= s; nZ *= s;
      // tangent basis: tA = (|n.y| < 0.9 ? up : +x) x n, normalized; tB = n x tA
      let ux = 0, uy = 1;
      const uz = 0;
      if (!(Math.abs(nY) < 0.9)) { ux = 1; uy = 0; }
      let aX = uy * nZ - uz * nY, aY = uz * nX - ux * nZ, aZ = ux * nY - uy * nX;
      s = 1 / (Math.sqrt(aX * aX + aY * aY + aZ * aZ) || 1);
      aX *= s; aY *= s; aZ *= s;
      const bX = nY * aZ - nZ * aY, bY = nZ * aX - nX * aZ, bZ = nX * aY - nY * aX;
      let occ = 0, wsum = 0;
      for (let r = 0; r < nd3; r += 3) {
        const X = dirs[r], Y = dirs[r + 1], Z = dirs[r + 2];
        const dx = 0 + aX * X + bX * Y + nX * Z, dy = 0 + aY * X + bY * Y + nY * Z, dz = 0 + aZ * X + bZ * Y + nZ * Z;
        wsum += Z; // cosine weight
        for (let t = start; t < dist; t += step) {
          const qy = py + dy * t;
          if (fl && qy < floorY) { occ += Z * (1 - (t / dist) * 0.6); break; }
          const ix = Math.floor((px + dx * t - ox) / cell), iy = Math.floor((qy - oy) / cell), iz = Math.floor((pz + dz * t - oz) / cell);
          if (ix < 0 || iy < 0 || iz < 0 || ix >= nx || iy >= ny || iz >= nz) break;
          if (vox[ix + nx * (iy + ny * iz)]) { occ += Z * (1 - (t / dist) * 0.6); break; }
        }
      }
      occ = wsum > 0 ? occ / wsum : 0;
      const hk = hasH ? 1 - smoothstep(py, floorY, fy1) : 0;
      S[i] = clamp((1 - occ * strength) * (1 - hk * heightStrength), 0.12, 1);
    }
    shades.push(S);
  }
  return shades;
}

// Marks every voxel that holds a sample of an occluder triangle (dense barycentric sampling, <= 60 steps per edge).
function voxelize(vox, occluders, mtxOf, ox, oy, oz, cell, nx, ny, nz) {
  const c06 = cell * 0.6;
  for (const o of occluders) {
    const e = mtxOf.get(o).elements;
    const pos = o.geometry.attributes.position;
    const vc = pos.count;
    const P = scratchB(vc * 3);
    const plain = !pos.isInterleavedBufferAttribute && !pos.normalized && pos.itemSize === 3;
    const A = pos.array;
    for (let i = 0; i < vc; i++) {
      const x = plain ? A[i * 3] : pos.getX(i), y = plain ? A[i * 3 + 1] : pos.getY(i), z = plain ? A[i * 3 + 2] : pos.getZ(i);
      const w = 1 / (e[3] * x + e[7] * y + e[11] * z + e[15]);
      P[i * 3] = (e[0] * x + e[4] * y + e[8] * z + e[12]) * w;
      P[i * 3 + 1] = (e[1] * x + e[5] * y + e[9] * z + e[13]) * w;
      P[i * 3 + 2] = (e[2] * x + e[6] * y + e[10] * z + e[14]) * w;
    }
    const idx = o.geometry.index;
    const ia = idx ? idx.array : null;
    const triCount = idx ? idx.count / 3 : vc / 3;
    for (let t = 0; t < triCount; t++) {
      let i0, i1, i2;
      if (ia) { i0 = ia[t * 3]; i1 = ia[t * 3 + 1]; i2 = ia[t * 3 + 2]; } else { i0 = t * 3; i1 = i0 + 1; i2 = i0 + 2; }
      if (!(i0 < vc && i1 < vc && i2 < vc)) continue; // out of range reads NaN in the Vector3 version: no samples
      const a3 = i0 * 3, b3 = i1 * 3, c3 = i2 * 3;
      const ax = P[a3], ay = P[a3 + 1], az = P[a3 + 2];
      const bx = P[b3], by = P[b3 + 1], bz = P[b3 + 2];
      const cx = P[c3], cy = P[c3 + 1], cz = P[c3 + 2];
      let dx = ax - bx, dy = ay - by, dz = az - bz;
      const dab = Math.sqrt(dx * dx + dy * dy + dz * dz);
      dx = bx - cx; dy = by - cy; dz = bz - cz;
      const dbc = Math.sqrt(dx * dx + dy * dy + dz * dz);
      dx = cx - ax; dy = cy - ay; dz = cz - az;
      const dca = Math.sqrt(dx * dx + dy * dy + dz * dz);
      const n = Math.min(60, Math.ceil(Math.max(dab, dbc, dca) / c06));
      const nd = Math.max(1, n);
      for (let i = 0; i <= n; i++) {
        const u = i / nd;
        for (let j = 0; j <= n - i; j++) {
          const v = j / nd, w0 = 1 - u - v;
          const ix = Math.floor((0 + ax * w0 + bx * u + cx * v - ox) / cell);
          if (ix < 0 || ix >= nx) continue;
          const iy = Math.floor((0 + ay * w0 + by * u + cy * v - oy) / cell);
          if (iy < 0 || iy >= ny) continue;
          const iz = Math.floor((0 + az * w0 + bz * u + cz * v - oz) / cell);
          if (iz < 0 || iz >= nz) continue;
          vox[ix + nx * (iy + ny * iz)] = 1;
        }
      }
    }
  }
}

// ================================================================================================ result
// Creates the prop root with the convention userData. Any field can be filled later (finish() fills gaps).
export function prop(id, fields = {}) {
  const g = new THREE.Group();
  g.name = `prop:${id}`;
  g.userData = { id, size: null, colliders: null, screens: [], lightAnchors: [], parts: {}, interact: null, ...fields };
  return g;
}

// Final pass every builder should call: toon materials -> vertexColors variants, bakeAO, merge static meshes
// per material (parts under userData.noMerge stay separate), shadow flags, size/colliders defaults, screens
// collected from meshes named/flagged as screens, stats. opts: { ao=true | aoOpts, merge=true, cast=0.3 (min
// size in m to cast shadows) }
export function finish(game, group, opts = {}) {
  const { ao = true, merge: doMerge = true, cast = 0.3 } = opts;
  group.traverse((o) => {
    if (o.isMesh && o.material?.userData?.daToon && !o.material.vertexColors) o.material = game.mats.variant(o.material, { vertexColors: true });
  });
  if (ao && !globalThis.__propkitNoAO) bakeAO(group, typeof ao === 'object' ? ao : {});
  // colors must exist wherever vertexColors are on (else the vertex color reads black)
  group.traverse((o) => {
    if (o.isMesh && o.material?.vertexColors && !o.geometry.attributes.color) {
      o.geometry = o.geometry.clone();
      o.geometry.setAttribute('color', new THREE.BufferAttribute(new Float32Array(o.geometry.attributes.position.count * 3).fill(1), 3));
    }
  });
  const u = group.userData;
  u.screens = u.screens || [];
  group.traverse((o) => {
    if (o.isMesh && o.userData.screenGroup && !u.screens.some((s) => s.mesh === o)) u.screens.push({ mesh: o, group: o.userData.screenGroup });
  });
  if (doMerge) G.mergeByMaterial(group);
  const sz = new THREE.Vector3(), bb = new THREE.Box3();
  group.traverse((o) => {
    if (!o.isMesh) return;
    if (!o.geometry.boundingBox) o.geometry.computeBoundingBox();
    o.geometry.boundingBox.getSize(sz);
    o.castShadow = !o.userData.noShadow && o.material.type !== 'ShaderMaterial' && !o.material.transparent && Math.max(sz.x, sz.y, sz.z) >= cast;
    o.receiveShadow = true;
  });
  bb.setFromObject(group);
  // setFromObject is in world space; props are built at the origin, so treat it as local.
  if (!u.size) { bb.getSize(sz); u.size = [r3(sz.x), r3(sz.y), r3(sz.z)]; }
  if (!u.colliders) u.colliders = [{ min: [r3(bb.min.x), 0, r3(bb.min.z)], max: [r3(bb.max.x), r3(bb.max.y), r3(bb.max.z)] }];
  u.lightAnchors = u.lightAnchors || [];
  u.parts = u.parts || {};
  if (u.interact === undefined) u.interact = null;
  u.stats = stats(group);
  return group;
}

export function merge(group) { return G.mergeByMaterial(group); }

// { tris, meshes, mats } for budgets (typical prop <= 3k tris, hero <= 12k, <= 3 materials when possible).
export function stats(group) {
  let tris = 0, meshes = 0;
  const mats = new Set();
  group.traverse((o) => {
    if (!o.isMesh) return;
    meshes++;
    mats.add(o.material.uuid);
    const g = o.geometry;
    tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
  });
  return { tris: Math.round(tris), meshes, mats: mats.size };
}
