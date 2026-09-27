// Station architecture meshes (level.js): floors with edge AO, walls with per-area finishes (wainscot, chair
// rail, baseboard, crown), the brick exterior shell with block plinth and coping, ceilings with their light
// fixtures (troffers, recessed cans, studio pipe grids), door thresholds, MC floor plates, the Studio A stage and
// stair, the newsroom riser, the bleachers and their side rails, the Yard chain-link fence and the roofs.
// Everything static goes through the world-UV Batch; fixtures that change at Sign-On are returned as records.
//
// buildArchitecture(ctx) → { fixtures: [{ area, mesh, pre, post, anchors:[{ id, pre, post }], center, dist }] }
//   ctx = { game, batch, surf, group(name) → Object3D }  batch groups: '<area>', '<area>#ceil', 'shell',
//   'shell#roof'. pre/post = { mat } for the fixture mesh and { color, intensity } for its light anchors;
//   dist = metres from the Sign-On lever to the nearest point of the area (the color wave reaches it at dist/15 s).

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as geo from '../core/geo.js';
import {
  AREAS, WALLS, WALL_T, ROOF_T, FENCE_H, PLATFORMS, BLOCKERS, FLOOR_PATCHES, DOORS, WINDOWS, ANCHORS,
} from './layout.js';
import { segmentBox } from './shell.js';
import { AREA_STYLE, EXTERIOR_STYLE } from './surfaces.js';

const H = WALL_T / 2;
const AREA = Object.fromEntries(AREAS.map((a) => [a.id, a]));
const indoor = (id) => !!id && !AREA[id].sky;
const WALL_AO = 0.42;
const EXT_AO = 0.3;
const FLOOR_BORDER = 0.7;
const FLOOR_AO = 0.36;
const LEVER = new THREE.Vector3(...ANCHORS.sign_on_lever.pos).setY(1);
const WALL_TOP_DROP = 0.004;   // interior wall tops sit this far under the roof that covers them (no z-fight)

// Openings whose frame wraps the wall: every door casing (doors.js) and every boarded-window frame (windows.js).
// The frame's inner faces cover the wall's jamb caps, its head covers the lintel soffit and its sill board covers
// the sill top, in exactly the same planes: drawn together they z-fight (the flickering door frames). Those wall
// faces are therefore not emitted; the frame is the visible surface. cover = height up to which the sill piece,
// the frame and the lintel piece hide a neighbouring wall end (the lintel top).
const FRAMED = [
  ...DOORS.map((d) => ({ id: d.id, line: d.line, span: d.span, lo: 0, hi: d.height })),
  ...WINDOWS.filter((w) => w.type === 'boarded').map((w) => ({ id: w.id, line: w.line, span: w.span, lo: w.sill, hi: w.top })),
];
for (const f of FRAMED) {
  const lintel = WALLS.find((s) => s[7] && s[7].opening === f.id && s[4] > 0);
  f.cover = lintel ? lintel[5] : f.hi;
}
const FRAMED_ID = new Map(FRAMED.map((f) => [f.id, f]));
const near = (a, b) => Math.abs(a - b) < 1e-6;
// The framed opening whose side lies at `end` on the wall line (axis, at), or null.
const framedAt = (axis, at, end) => FRAMED.find((f) => f.line[0] === axis && near(f.line[1], at)
  && (near(f.span[0], end) || near(f.span[1], end))) || null;

export function buildArchitecture(ctx) {
  floors(ctx);
  walls(ctx);
  ceilings(ctx);
  platforms(ctx);
  roofs(ctx);
  return { fixtures: AREAS.filter((a) => indoor(a.id)).map((a) => fixtures(ctx, a)) };
}

// --------------------------------------------------------------------------------------------------- floors
function floors({ batch }) {
  for (const a of AREAS) {
    const [x0, z0, x1, z1] = a.rect;
    const outdoor = !indoor(a.id);
    batch.hface(a.id, AREA_STYLE[a.id].floor, x0, z0, x1, z1, 0, true,
      { border: outdoor ? 0 : FLOOR_BORDER, ao: FLOOR_AO });
  }
  for (const p of FLOOR_PATCHES) {
    const [x0, z0, x1, z1] = p.rect;
    batch.hface('master_control', 'metal_plate', x0, z0, x1, z1, 0.006, true);
  }
  // Door thresholds: a steel strip across each doorway hides the floor-material change on the wall line.
  for (const d of DOORS) {
    const [axis, at] = d.line;
    const [s0, s1] = d.span;
    if (axis === 'x') batch.hface(d.areas[0], 'trim_steel', at - 0.22, s0, at + 0.22, s1, 0.012, true);
    else batch.hface(d.areas[0], 'trim_steel', s0, at - 0.22, s1, at + 0.22, 0.012, true);
  }
}

// ---------------------------------------------------------------------------------------------------- walls
const baseKey = (owner) => (owner === 'shell' ? EXTERIOR_STYLE.base : AREA_STYLE[owner].wall.base);

function walls(ctx) {
  const { batch } = ctx;
  for (const seg of WALLS) {
    const [, , , , y0, y1, kind, meta] = seg;
    if (kind === 'fence') { fence(ctx, seg); continue; }
    if (kind === 'glass') { boothGlass(ctx, seg); continue; }
    const alongX = seg[1] === seg[3];
    const axis = alongX ? 'z' : 'x';
    const at = alongX ? seg[1] : seg[0];
    const [mn, mx] = segmentBox(seg, H, H);
    const a0 = alongX ? mn[0] : mn[2], a1 = alongX ? mx[0] : mx[2];
    // The framed opening at each end (a sill/lintel piece is framed at both ends by its own opening).
    const own = meta.opening ? FRAMED_ID.get(meta.opening) || null : null;
    const framed = meta.jambs.map((jamb, i) => (jamb ? own || framedAt(axis, at, i === 0 ? a0 : a1) : null));
    meta.sides.forEach((area, i) => {
      const sign = i === 0 ? -1 : 1;
      const plane = at + sign * H;
      if (indoor(area)) indoorFace(ctx, area, axis, plane, sign, a0, a1, y0, y1, framed, meta.jambs);
      else exteriorFace(ctx, axis, plane, sign, a0, a1, y0, y1);
    });
    const owner = indoor(meta.sides[0]) ? meta.sides[0] : indoor(meta.sides[1]) ? meta.sides[1] : 'shell';
    const exterior = meta.sides.some((s) => !indoor(s));
    const sill = meta.opening && y0 === 0;
    if (sill) {
      if (!own) batch.hface(owner, baseKey(owner), mn[0], mn[2], mx[0], mx[2], y1, true);   // framed: the sill board
    } else if (exterior) {
      batch.box('shell', EXTERIOR_STYLE.cap, [mn[0] - 0.05, y1, mn[2] - 0.05], [mx[0] + 0.05, y1 + 0.1, mx[2] + 0.05],
        { skip: { ny: true } });
    } else {
      // Interior wall top: the taller side's roof (roofs(), extended by H) covers it in the very same plane.
      const roofY = Math.max(...meta.sides.map((s) => AREA[s].ceilY)) + ROOF_T;
      batch.hface('shell', EXTERIOR_STYLE.cap, mn[0], mn[2], mx[0], mx[2], near(y1, roofY) ? y1 - WALL_TOP_DROP : y1, true);
    }
    // Soffit under a lintel (a framed opening's head covers it).
    if (y0 > 0 && !(own && near(y0, own.hi))) batch.hface(owner, baseKey(owner), mn[0], mn[2], mx[0], mx[2], y0, false);
    // Jamb caps: the wall ends facing an opening. Next to a framed opening the sill piece, the frame's inner face
    // and the lintel piece hide the end up to the lintel top; only what rises above it (if anything) is drawn.
    // (A sill/lintel piece's own end caps face into the neighbouring wall piece and are kept as they were.)
    meta.jambs.forEach((jamb, i) => {
      if (!jamb) return;
      const end = i === 0 ? a0 : a1;
      const lo = framed[i] && !own ? Math.max(y0, framed[i].cover) : y0;
      if (y1 - lo < 1e-4) return;
      batch.vface(owner, baseKey(owner), alongX ? 'x' : 'z', end, i === 0 ? -1 : 1, at - H, at + H, lo, y1);
    });
  }
}

// Inside finish of one wall face: wainscot + upper wall, baseboard, chair rail, crown; above this area's ceiling
// the face belongs to the exterior shell (seen from the Yard over lower roofs).
// framed = [opening at a0 | null, opening at a1 | null]: trim ends there lose their end cap (see trim()).
// jambs = [a0 faces an opening, a1 faces an opening]: every other end runs H into a junction (segmentBox), so its
// trim end cap would lie exactly in the far face of the crossing wall (next room / exterior): never drawn.
function indoorFace(ctx, area, axis, plane, sign, a0, a1, y0, y1, framed = [null, null], jambs = [true, true]) {
  const { batch } = ctx;
  const st = AREA_STYLE[area].wall;
  const ceil = AREA[area].ceilY;
  const top = Math.min(y1, ceil);
  if (y1 - ceil > ROOF_T + 0.01) exteriorFace(ctx, axis, plane, sign, a0, a1, Math.max(y0, ceil), y1);
  if (top <= y0) return;
  const wH = st.wainscot ? st.wainscotH : 0;
  const o = { ao: WALL_AO, top: ceil };
  if (wH > y0) batch.vface(area, st.wainscot, axis, plane, sign, a0, a1, y0, Math.min(wH, top), o);
  if (top > Math.max(y0, wH)) batch.vface(area, st.base, axis, plane, sign, a0, a1, Math.max(y0, wH), top, o);
  const trim = (key, ya, yb, depth, onFloor) => {
    const lo = Math.min(plane, plane + sign * depth), hi = Math.max(plane, plane + sign * depth);
    const min = axis === 'z' ? [a0, ya, lo] : [lo, ya, a0];
    const max = axis === 'z' ? [a1, yb, hi] : [hi, yb, a1];
    const back = axis === 'z' ? (sign > 0 ? 'nz' : 'pz') : (sign > 0 ? 'nx' : 'px');
    const skip = { [back]: true, ny: onFloor };
    // At a framed opening the trim runs into the casing/frame (5 cm proud, deeper than any trim: it swallows the
    // end) or into the sill/lintel piece's identical trim; the end cap would only sit in the frame's inner-face
    // plane (z-fight), so it is dropped. A trim straddling the frame's top or bottom keeps it.
    const cap = (i) => (axis === 'z' ? (i ? 'px' : 'nx') : (i ? 'pz' : 'nz'));
    framed.forEach((f, i) => {
      if (!f || (ya < f.lo - 1e-6 && yb > f.lo + 1e-6) || (ya < f.hi - 1e-6 && yb > f.hi + 1e-6)) return;
      skip[cap(i)] = true;
    });
    jambs.forEach((jamb, i) => { if (!jamb) skip[cap(i)] = true; });
    batch.box(area, key, min, max, { skip });
  };
  if (y0 === 0) trim(st.baseboard, 0, 0.16, 0.035, true);
  // Chair rail 3.7 cm deep: wall-mounted lightboxes/posters hang their face 4 cm off the wall and stay in front.
  if (st.rail && wH > y0 && wH < top) trim(st.rail, wH - 0.035, wH + 0.035, 0.037, false);
  if (st.crown && top === ceil) trim(st.crown, ceil - 0.14, ceil, 0.05, false);
}

function exteriorFace({ batch }, axis, plane, sign, a0, a1, y0, y1) {
  const E = EXTERIOR_STYLE;
  if (y0 < E.wainscotH) batch.vface('shell', E.wainscot, axis, plane, sign, a0, a1, y0, Math.min(E.wainscotH, y1), { ao: EXT_AO });
  if (y1 > E.wainscotH) batch.vface('shell', E.base, axis, plane, sign, a0, a1, Math.max(y0, E.wainscotH), y1, { ao: EXT_AO });
}

// Announce-booth glass (§5.7): pane between knee wall and header, chrome mullions.
function boothGlass({ game, surf, group }, seg) {
  const [x0, z, x1, , y0, y1] = seg;
  const a = Math.min(x0, x1) + H, b = Math.max(x0, x1);
  const root = group('lobby');
  const glass = game.mats.toon('#3A4A5C', {
    transparent: true, opacity: 0.28, rough: 0.06, env: 0.6, rim: 0.4, rimColor: '#FFC98A', depthWrite: false, name: 'booth_glass',
  });
  root.add(geo.mesh(geo.plane(b - a, y1 - y0), glass, { pos: [(a + b) / 2, (y0 + y1) / 2, z], cast: false }));
  const chrome = surf.plain('trim_chrome');
  for (const x of [b - 0.03, (a + b) / 2]) {
    root.add(geo.mesh(geo.box(0.06, y1 - y0, 0.08), chrome, { pos: [x, (y0 + y1) / 2, z], cast: false }));
  }
}

// Yard chain-link: a double-sided alpha-tested plane (world UVs), galvanized posts every ≤ 2.5 m, top and
// bottom rails.
function fence({ batch, surf, group }, seg) {
  const [x0, z0, x1, z1] = seg;
  const alongX = z0 === z1;
  const a = alongX ? Math.min(x0, x1) : Math.min(z0, z1);
  const b = alongX ? Math.max(x0, x1) : Math.max(z0, z1);
  const at = alongX ? z0 : x0;
  batch.vface('yard', 'chainlink', alongX ? 'z' : 'x', at, 1, a, b, 0.05, FENCE_H - 0.05);
  const root = group('yard');
  const steel = surf.plain('galvanized');
  const n = Math.max(1, Math.ceil((b - a) / 2.5));
  for (let i = 0; i <= n; i++) {
    const s = a + ((b - a) * i) / n;
    const p = alongX ? [s, (FENCE_H + 0.1) / 2, at] : [at, (FENCE_H + 0.1) / 2, s];
    root.add(geo.mesh(geo.cylinder(0.05, 0.05, FENCE_H + 0.1, 10), steel, { pos: p }));
  }
  for (const y of [FENCE_H - 0.04, 0.12]) {
    const p = alongX ? [(a + b) / 2, y, at] : [at, y, (a + b) / 2];
    const rot = alongX ? [0, 0, Math.PI / 2] : [Math.PI / 2, 0, 0];
    root.add(geo.mesh(geo.cylinder(0.035, 0.035, b - a, 8), steel, { pos: p, rot, cast: false }));
  }
}

// ------------------------------------------------------------------------------------------------- ceilings
function ceilings({ batch }) {
  for (const a of AREAS) {
    if (!indoor(a.id)) continue;
    const [x0, z0, x1, z1] = a.rect;
    batch.hface(`${a.id}#ceil`, AREA_STYLE[a.id].ceiling, x0, z0, x1, z1, a.ceilY, false, { border: 0.5, ao: 0.28 });
  }
}

function roofs({ batch }) {
  for (const a of AREAS) {
    if (!indoor(a.id)) continue;
    const [x0, z0, x1, z1] = a.rect;
    batch.hface('shell#roof', 'roof_gravel', x0 - H, z0 - H, x1 + H, z1 + H, a.ceilY + ROOF_T, true);
  }
}

// Evenly spread centres: n items across [a, b].
const spread = (a, b, n) => Array.from({ length: n }, (_, i) => a + ((b - a) * (i + 0.5)) / n);
const clampN = (v, lo, hi) => Math.max(lo, Math.min(hi, Math.round(v)));

// Ceiling fixtures of one area → record whose diffuser mesh + light anchors switch at Sign-On.
function fixtures({ game, surf, group }, area) {
  const st = AREA_STYLE[area.id];
  const [x0, z0, x1, z1] = area.rect;
  const ceil = area.ceilY;
  const root = group(area.id);
  const lens = [];
  if (st.fixtures === 'panels') {
    // Troffer: a 6 cm cream frame ring around a lens recessed 2 cm into it (a lens lying 2 mm under a solid
    // frame plate z-fought with it across the room).
    const frame = surf.plain('trim_cream');
    for (const x of spread(x0, x1, clampN((x1 - x0) / 3.4, 1, 8))) {
      for (const z of spread(z0, z1, clampN((z1 - z0) / 3.2, 1, 6))) {
        for (const s of [-1, 1]) {
          root.add(geo.mesh(geo.box(0.06, 0.05, 1.32), frame, { pos: [x + s * 0.33, ceil - 0.025, z], cast: false }));
          root.add(geo.mesh(geo.box(0.6, 0.05, 0.06), frame, { pos: [x, ceil - 0.025, z + s * 0.63], cast: false }));
        }
        lens.push(new THREE.PlaneGeometry(0.6, 1.2).rotateX(Math.PI / 2).translate(x, ceil - 0.03, z));
      }
    }
  } else if (st.fixtures === 'cans') {
    const ring = surf.plain('trim_chrome');
    for (const x of spread(x0, x1, 3)) {
      for (const z of spread(z0, z1, 2)) {
        root.add(geo.mesh(geo.cylinder(0.2, 0.2, 0.05, 20), ring, { pos: [x, ceil - 0.025, z], cast: false }));
        lens.push(new THREE.CircleGeometry(0.15, 20).rotateX(Math.PI / 2).translate(x, ceil - 0.058, z));   // 8 mm proud
      }
    }
  } else if (st.fixtures === 'grid') {
    // Pipe grid + drop rods, and a row of scoop lights hanging from it (post-power work lights).
    const pipe = surf.plain('trim_black');
    const y = st.gridY;
    const gx = spread(x0 + 0.6, x1 - 0.6, clampN((x1 - x0) / 2.5, 2, 12));
    const gz = spread(z0 + 0.6, z1 - 0.6, clampN((z1 - z0) / 2.5, 2, 12));
    for (const z of gz) root.add(geo.mesh(geo.cylinder(0.045, 0.045, x1 - x0 - 1, 8), pipe, { pos: [(x0 + x1) / 2, y, z], rot: [0, 0, Math.PI / 2], cast: false }));
    for (const x of gx) root.add(geo.mesh(geo.cylinder(0.045, 0.045, z1 - z0 - 1, 8), pipe, { pos: [x, y + 0.09, (z0 + z1) / 2], rot: [Math.PI / 2, 0, 0], cast: false }));
    for (let i = 0; i < gx.length; i += 3) {
      for (let k = 0; k < gz.length; k += 3) {
        root.add(geo.mesh(geo.cylinder(0.025, 0.025, ceil - y, 6), pipe, { pos: [gx[i], (ceil + y) / 2, gz[k]], cast: false }));
      }
    }
    const housing = surf.plain('trim_black');
    for (const x of spread(x0 + 2, x1 - 2, clampN((x1 - x0) / 4, 2, 6))) {
      for (const z of [gz[1], gz[gz.length - 2]]) {
        root.add(geo.mesh(geo.cylinder(0.26, 0.2, 0.34, 16), housing, { pos: [x, y - 0.3, z], cast: false }));
        lens.push(new THREE.CircleGeometry(0.2, 16).rotateX(Math.PI / 2).translate(x, y - 0.475, z));
      }
    }
  }
  const mesh = new THREE.Mesh(mergeGeometries(lens), game.mats.glow('#ffffff', 1));
  mesh.name = `fixtures:${area.id}`;
  mesh.userData.noMerge = true;
  root.add(mesh);

  const pre = st.lightPre;
  const post = st.lightPost;
  const preMat = pre ? game.mats.glow(pre, 1.1) : game.mats.toon('#D8D2C4', { rough: 0.3, rim: 0 });
  const postMat = game.mats.glow(post, 1.9);
  mesh.material = preMat;
  const low = area.id === 'master_control' ? 3 : 5;
  const ly = st.fixtures === 'grid' ? st.gridY - 0.6 : ceil - 0.5;
  const anchors = [];
  for (const x of spread(x0, x1, clampN((x1 - x0) / 8, 1, 3))) {
    for (const z of spread(z0, z1, clampN((z1 - z0) / 8, 1, 3))) {
      const id = `lvl_${area.id}_${anchors.length}`;
      const a = {
        id,
        pre: { color: pre || post, intensity: pre ? 3.2 : 0 },
        post: { color: post, intensity: low },
      };
      game.lights.addAnchor({ id, pos: [x, ly, z], color: a.pre.color, intensity: a.pre.intensity, distance: Math.max(9, ceil * 1.8), area: area.id });
      anchors.push(a);
    }
  }
  const cx = THREE.MathUtils.clamp(LEVER.x, x0, x1), cz = THREE.MathUtils.clamp(LEVER.z, z0, z1);
  return {
    area: area.id, mesh, pre: { mat: preMat }, post: { mat: postMat }, anchors,
    center: new THREE.Vector3((x0 + x1) / 2, ceil - 0.5, (z0 + z1) / 2),
    dist: LEVER.distanceTo(new THREE.Vector3(cx, 1, cz)),
  };
}

// ------------------------------------------------------------------------------------------------ platforms
function platforms(ctx) {
  const { batch } = ctx;
  for (const p of PLATFORMS) {
    if (p.kind === 'riser') { riser(ctx, p); continue; }
    const [x0, z0, x1, z1] = p.rect;
    const bleacher = p.kind === 'bleacher';
    const top = bleacher ? 'bleacher_wood' : 'stage_wood';
    const side = bleacher ? 'bleacher_riser' : 'trim_black';
    const r = AREA[p.area].rect;
    const g = p.area;
    batch.hface(g, top, x0, z0, x1, z1, p.top, true);
    const o = { ao: 0.3 };
    if (z0 > r[1] + 1e-3) batch.vface(g, side, 'z', z0, -1, x0, x1, 0, p.top, o);
    if (z1 < r[3] - 1e-3) batch.vface(g, side, 'z', z1, 1, x0, x1, 0, p.top, o);
    if (x0 > r[0] + 1e-3) batch.vface(g, side, 'x', x0, -1, z0, z1, 0, p.top, o);
    if (x1 < r[2] - 1e-3) batch.vface(g, side, 'x', x1, 1, z0, z1, 0, p.top, o);
    // Nosing: gold on the stage and its step (front edge = +z), mustard on the bleacher tiers (front = −z).
    // The nosing wraps 6 mm past an exposed side (its end cap used to lie in the side face's plane: z-fight;
    // 1 cm would land in the bleacher_block end panels' plane).
    const n0 = x0 > r[0] + 1e-3 ? x0 - 0.006 : x0, n1 = x1 < r[2] - 1e-3 ? x1 + 0.006 : x1;
    if (bleacher) batch.box(g, 'trim_mustard', [n0, p.top - 0.05, z0 - 0.02], [n1, p.top + 0.01, z0 + 0.06], { skip: { ny: true } });
    else batch.box(g, 'trim_gold', [n0, p.top - 0.05, z1 - 0.06], [n1, p.top + 0.01, z1 + 0.02], { skip: { ny: true } });
  }
  // Bleacher side rails: stepped blue end panels with a mustard cap rail.
  // The panels stand 3 mm proud all round: their outer and front faces used to share the tiers' side and riser
  // planes (different AO, so they fought).
  const e = 0.003;
  for (const b of BLOCKERS) {
    const [x0, z0, x1, z1] = b.rect;
    batch.box(b.area, 'bleacher_riser', [x0 - e, b.y0, z0 - e], [x1 + e, b.y1 - 0.06, z1 + e], { skip: { ny: true, py: true } });
    batch.box(b.area, 'trim_mustard', [x0 - 0.02, b.y1 - 0.06, z0 - e], [x1 + 0.02, b.y1, z1 + e], { skip: { ny: true } });
  }
}

// Anchor riser: carpeted top inset by the ramp width, four sloped carpet faces.
function riser({ batch }, p) {
  const [x0, z0, x1, z1] = p.rect;
  const r = p.ramp, y = p.top, g = p.area, key = 'riser_carpet';
  const X0 = x0 + r, X1 = x1 - r, Z0 = z0 + r, Z1 = z1 - r;
  batch.hface(g, key, X0, Z0, X1, Z1, y, true);
  const ny = r / Math.hypot(r, y), nh = y / Math.hypot(r, y);
  batch.poly(g, key, [[x0, 0, z0], [x1, 0, z0], [X1, y, Z0], [X0, y, Z0]], [0, ny, -nh], [0.3, 0.3, 0, 0]);
  batch.poly(g, key, [[x0, 0, z1], [X0, y, Z1], [X1, y, Z1], [x1, 0, z1]], [0, ny, nh], [0.3, 0, 0, 0.3]);
  batch.poly(g, key, [[x0, 0, z0], [X0, y, Z0], [X0, y, Z1], [x0, 0, z1]], [-nh, ny, 0], [0.3, 0, 0, 0.3]);
  batch.poly(g, key, [[x1, 0, z0], [x1, 0, z1], [X1, y, Z1], [X1, y, Z0]], [nh, ny, 0], [0.3, 0.3, 0, 0]);
}
