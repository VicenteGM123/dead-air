// Studio A — "13-HOUR SPOOKTACULAR TELETHON" set dressing (GDD §5.7, lighting §3.3, toys §13) + the small shared
// studio kit that rooms/studio_b.js imports (place/placeFit/runtime/atlas/baking helpers).
//
// build(game, area, root)  called by level.js after the graybox; the level merges static meshes per material afterwards.
// Everything animated or swapped at runtime lives in noMerge groups (or is a noMerge prop part).
//
// Power: rooms follow game.level.powered; each item switches when the Sign-On color wave reaches it (distance to the
// lever / 15 m/s, like level.js fixtures). Before power: the ghost light + a faint tote board + candle pumpkins.
// After power: gel spots sweeping the stage (additive beams + moving light pools), marquee chase, disco ball + specks,
// ringing pledge phones, lit Fresnels, feed-camera tally.
//
// game.level.objects (other systems read these; all positions are world space):
//   ee_prize_wheel    { group, parts:{ wheel (rot.z), flapper, lever, hub }, hub:Vector3, puppetSeat:Vector3,
//                       spinning, spin({ turns, duration }) -> seconds }        (toy_prize_wheel uses spin())
//   ee_tote_board     { group, parts:{ digits_0..3, thermo_0..3, bulbs, topper }, value, goal:13000,
//                       setValue(v) (flip digits + thermometers), setGlow(0..1) }   (sets.js setToteValue works too)
//   ee_applause_sign  { group, parts:{ lamp, bulbs }, lit, setLit(on) }   (also drives the red light anchor 'sa_applause')
//   marquee_arch      { group, parts:{ bulbs }, mode, setMode('chase'|'flash'|'on'|'off'|'sparkle'|null=auto) }
//   pledge_carousel   { group, parts:{ handsets, lamps } }      baron_throne { group, parts:{ lever }, seat:Vector3 }
//   ghost_light       { group, parts:{ bulb }, on, set(on) }    disco_ball { group, parts:{ ball } }
//   feed_cam_studio_a { group, parts:{ head, tilt, tally, lensTip } }  (physical camera; screens.js owns the feed camera)
//   mon_studio_a_stand / ss_studio_a_w / ss_studio_a_e { group, screen }   (screens registered with those ids)
// Toys (key-only [E] prompts): toy_ghost_light (on/off, 'toy_ghost_light'), toy_prize_wheel (spin, 'toy_wheel').
//
// Shared kit exports (used by studio_b.js): runtime(game, areaId, root), place(), placeFit(), studioMats(game),
// makeAtlas(), quad(), tg(), bakeInstanced(), unlockParts(), harvestLenses(), feedCamera(), standMonitor(),
// txt(), rr(), FONT, yawTo().

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { buildProp, cloneProp } from '../../props/index.js';
import * as K from '../../props/kit.js';
import { PAL } from '../../core/config.js';
import { ANCHORS, SCREEN_SPAWNS, DOORS } from '../layout.js';
import { drawTo } from '../../gfx/cards.js';
import { marqueeChase, setGhostLight, setToteValue, setToteGlow, ringPhone, discoSpeckTexture } from '../../props/sets.js';
import { setLamp } from '../../props/broadcast.js';

const TAU = Math.PI * 2;
const HP = Math.PI / 2;
const WAVE = 15;
const LEVER = new THREE.Vector3(...ANCHORS.sign_on_lever.pos).setY(1);
const AREA = 'studio_a';
const GRID_Y = 6.5;

export const yawTo = (a, b) => Math.atan2(-(b[0] - a[0]), -(b[2] - a[2]));
const v3 = (p) => (p.isVector3 ? p.clone() : new THREE.Vector3(p[0], p[1] ?? 0, p[2]));
const ss = (id) => SCREEN_SPAWNS.find((s) => s.id === id);

// =============================================================================================== shared kit
// Runtime: a per-room frame hook (render pre-pass, CPU only) with power switching, tickers and resets.
export function runtime(game, areaId, root) {
  const rt = {
    game, areaId, root, tickers: [], power: [], resets: [], powered: null, waveT: 1e9, t: 0,
    warm: new THREE.Group(),
    objects: (game.level.objects ??= {}),
  };
  rt.warm.name = `${areaId}:warm`;
  rt.warm.visible = false;
  rt.warm.userData.noMerge = true;
  root.add(rt.warm);
  // fn(on, instant) runs when the color wave reaches pos (instantly when powering off / at boot)
  rt.onPower = (pos, fn) => { rt.power.push({ d: LEVER.distanceTo(v3(pos)) / WAVE, fn, on: null }); };
  rt.onTick = (fn) => { rt.tickers.push(fn); };      // fn(worldTime, worldDt, areaVisible)
  rt.onReset = (fn) => { rt.resets.push(fn); };
  // materials used later at runtime must exist in the scene when game.precompile() runs (no first-use stall)
  const warmGeo = new THREE.PlaneGeometry(0.01, 0.01);
  warmGeo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(warmGeo.attributes.position.count * 3).fill(1), 3));
  rt.warmMat = (...mats) => {
    for (const m of mats) {
      if (!m) continue;
      const w = new THREE.Mesh(warmGeo, m);
      w.receiveShadow = true;
      rt.warm.add(w);
    }
  };
  rt.anchor = (id, o) => game.lights?.addAnchor?.({ id, area: areaId, ...o });
  rt.setAnchor = (id, o) => game.lights?.setAnchor?.(id, o);
  rt.pool = (pos, r, color, i) => game.fx?.lightPool?.(pos, r, color, i) ?? { set() {}, remove() {} };
  const update = () => {
    const tm = game.time;
    if (!tm) return;
    const want = !!game.level?.powered;
    if (rt.powered === null || (!want && rt.powered)) {
      for (const p of rt.power) if (p.on !== want) { p.on = want; p.fn(want, true); }
      rt.powered = want;
      rt.waveT = 1e9;
    } else if (want && !rt.powered) {
      rt.powered = true;
      rt.waveT = 0;
    }
    if (rt.waveT < 1e8) {
      rt.waveT += Math.min(0.1, tm.realDt || 0);
      let pending = false;
      for (const p of rt.power) {
        if (p.on) continue;
        if (rt.waveT >= p.d) { p.on = true; p.fn(true, false); } else pending = true;
      }
      if (!pending) rt.waveT = 1e9;
    }
    const now = tm.now || 0;
    const dt = Math.max(0, Math.min(0.1, now - rt.t));
    rt.t = now;
    const vis = !!game.level?.areaRoots?.[areaId]?.visible;
    for (const f of rt.tickers) f(now, dt, vis);
  };
  game.render?.addPrePass?.(update);
  game.events?.on?.('game:start', () => { for (const f of rt.resets) f(); });
  return rt;
}

// Cached kit materials (white + vertex colors: tinted geometry of every studio prop merges into few draws).
const MATS = new WeakMap();
export function studioMats(game) {
  let m = MATS.get(game);
  if (m) return m;
  const basicV = (k, o = {}) => new THREE.MeshBasicMaterial({ color: new THREE.Color(k, k, k), vertexColors: true, ...o });
  m = {
    lac: K.mat(game, 'lacquer', '#ffffff'),
    paint: K.mat(game, 'paint', '#ffffff'),
    plastic: K.mat(game, 'plastic', '#ffffff'),
    felt: K.mat(game, 'felt', '#ffffff'),
    chrome: K.mat(game, 'chrome', '#A8B0BA'),
    velvet: K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#B81E3A', { pattern: 'cord', scale: 3 }) }),
    glow: basicV(1),          // vertex-colored HDR glow (candles, baked bulbs, fairy lights)
    glowDim: basicV(0.3),
    beam: beamMaterial(),
  };
  MATS.set(game, m);
  return m;
}

// Soft additive light-cone material (fresnel edge fade, fades along the cone). Per-beam color via uniforms clone.
function beamMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: { uColor: { value: new THREE.Color(1, 1, 1) }, uI: { value: 0.3 } },
    vertexShader: `varying vec3 vN; varying vec3 vV; varying float vT;
      void main(){ vN = normalize(normalMatrix * normal); vec4 mv = modelViewMatrix * vec4(position, 1.0);
        vV = normalize(-mv.xyz); vT = uv.y; gl_Position = projectionMatrix * mv; }`,
    // pow() bases are clamped: with 4x MSAA an edge pixel's varyings are extrapolated outside the triangle
    // (vT > 1 at the wide end), and pow(negative) = NaN, which the bloom mip chain spread over the whole frame.
    fragmentShader: `uniform vec3 uColor; uniform float uI; varying vec3 vN; varying vec3 vV; varying float vT;
      void main(){ float e = pow(clamp(abs(dot(normalize(vN), normalize(vV))), 0.0, 1.0), 1.8);
        float f = pow(clamp(1.0 - vT, 0.0, 1.0), 1.3) * 0.85 + 0.15; gl_FragColor = vec4(uColor * uI * e * f, 1.0); }`,
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, fog: false,
  });
}

// tinted copy of a (possibly cached) geometry
export const tg = (geo, color) => K.tint(geo.clone(), color);
// flat quad facing -z showing an atlas rect [u0,v0,u1,v1]
export function quad(w, h, uvr = null, color = '#ffffff') {
  const g = new THREE.PlaneGeometry(w, h);
  g.rotateY(Math.PI);
  if (uvr) K.uvRect(g, ...uvr);
  return K.tint(g, color);
}

// Places a registered prop (like props/index.js placeProp) with scale, collider override, optional light anchors,
// screen group/id override. o.group = a prebuilt prop group. Returns the group.
const _v = new THREE.Vector3();
export function place(game, parent, id, o = {}) {
  const { pos = [0, 0, 0], rotY = 0, scale = 1, opts = {}, area = null, colliders = true, lights = false, screens = true,
    tag = 'prop', screenGroup = null, screenId = null } = o;
  const g = o.group || buildProp(id, game, opts);
  g.position.set(pos[0], pos[1] ?? 0, pos[2]);
  g.rotation.y = rotY;
  if (scale !== 1) g.scale.setScalar(scale);
  parent.add(g);
  g.updateMatrixWorld(true);
  const u = g.userData;
  const boxes = Array.isArray(colliders) ? colliders : colliders ? (u.colliders || []) : [];
  if (boxes.length && game.level?.col) {
    const bb = new THREE.Box3();
    for (const c of boxes) {
      bb.makeEmpty();
      for (let i = 0; i < 8; i++) {
        _v.set(i & 1 ? c.max[0] : c.min[0], i & 2 ? c.max[1] : c.min[1], i & 4 ? c.max[2] : c.min[2]).applyMatrix4(g.matrixWorld);
        bb.expandByPoint(_v);
      }
      game.level.col.addBox(bb.min.toArray(), bb.max.toArray(), { tag, ...(c.opts || {}) });
    }
  }
  if (lights && game.lights?.addAnchor) {
    for (const a of u.lightAnchors || []) {
      _v.fromArray(a.pos).applyMatrix4(g.matrixWorld);
      game.lights.addAnchor({ ...a, pos: _v.toArray(), area: a.area ?? area });
    }
  }
  if (screens && game.screens?.register) {
    (u.screens || []).forEach((s, i) => {
      const sid = screenId ? (i ? `${screenId}_${i}` : screenId) : s.id;
      game.screens.register(s.mesh, screenGroup || s.group || 'scr_decor', sid ? { id: sid } : {});
    });
  }
  return g;
}

// Places a prop so that a local point of it (fn(g) -> Object3D | Vector3 in prop space) lands on `target`.
export function placeFit(game, parent, id, o = {}) {
  const g = o.group || buildProp(id, game, o.opts || {});
  g.updateMatrixWorld(true);
  const ref = o.fit(g);
  const lp = ref.isObject3D ? ref.getWorldPosition(new THREE.Vector3()) : ref.clone();
  const s = o.scale ?? 1;
  lp.multiplyScalar(s).applyAxisAngle(new THREE.Vector3(0, 1, 0), o.rotY ?? 0);
  const t = v3(o.target);
  const pos = [t.x - lp.x, o.floorY ?? (t.y - lp.y), t.z - lp.z];
  return place(game, parent, id, { ...o, group: g, pos });
}

// Canvas atlas shared by a room: regions {name: [x, y, w, h]} (px, top-left origin). Returns { tex, mat, glow, cut, uv(name) }.
export function makeAtlas(game, key, size, regions, draw) {
  const tex = K.tex.canvas(key, size, size, (ctx, w, h, rand) => {
    ctx.clearRect(0, 0, w, h);
    draw(ctx, (n) => regions[n], rand);
  }, { repeat: false, fonts: true });
  tex.anisotropy = 8;
  const uv = (n) => {
    const [x, y, w, h] = regions[n];
    return [x / size, 1 - (y + h) / size, (x + w) / size, 1 - y / size];
  };
  return {
    tex, uv,
    mat: K.mat(game, 'paint', '#ffffff', { map: tex, rough: 0.7 }),
    gloss: K.mat(game, 'lacquer', '#ffffff', { map: tex }),
    glow: K.glow(game, '#ffffff', 1.35, { map: tex }),
    cut: K.mat(game, 'paint', '#ffffff', { map: tex, alphaTest: 0.5, side: THREE.DoubleSide }),
  };
}

// Converts an InstancedMesh into one static mesh (instance colors -> vertex colors) so the level can merge it.
export function bakeInstanced(im, mat = null) {
  const src = im.geometry.index ? im.geometry.toNonIndexed() : im.geometry.clone();
  const m4 = new THREE.Matrix4(), c = new THREE.Color(1, 1, 1);
  const geos = [];
  for (let i = 0; i < im.count; i++) {
    im.getMatrixAt(i, m4);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', src.attributes.position.clone());
    if (src.attributes.normal) g.setAttribute('normal', src.attributes.normal.clone());
    g.setAttribute('uv', src.attributes.uv ? src.attributes.uv.clone() : new THREE.BufferAttribute(new Float32Array(src.attributes.position.count * 2), 2));
    g.applyMatrix4(m4);
    if (im.instanceColor) im.getColorAt(i, c); else c.setRGB(1, 1, 1);
    const n = g.attributes.position.count, col = new Float32Array(n * 3);
    const base = src.attributes.color;
    for (let k = 0; k < n; k++) {
      col[k * 3] = c.r * (base ? base.getX(k) : 1);
      col[k * 3 + 1] = c.g * (base ? base.getY(k) : 1);
      col[k * 3 + 2] = c.b * (base ? base.getZ(k) : 1);
    }
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    geos.push(g);
  }
  const merged = mergeGeometries(geos, false);
  const out = new THREE.Mesh(merged, mat || im.material);
  out.name = `baked:${im.name}`;
  out.position.copy(im.position); out.quaternion.copy(im.quaternion); out.scale.copy(im.scale);
  out.castShadow = false; out.receiveShadow = true;
  const p = im.parent;
  p.add(out);
  p.remove(im);
  return out;
}

// Static props: let their noMerge parts merge with the area (they will never animate here).
export function unlockParts(g, names = null) {
  for (const [k, v] of Object.entries(g.userData.parts || {})) {
    if (names && !names.includes(k)) continue;
    if (v?.isObject3D) v.userData.noMerge = false;
  }
}

// Moves lamp lenses of broadcast lights into one noMerge group (one draw for all lenses; material swaps at power).
export function harvestLenses(lights, into, partName = 'lens') {
  for (const g of lights) {
    const lens = g.userData.parts?.[partName];
    if (!lens) continue;
    lens.userData.noMerge = false;
    g.updateMatrixWorld(true);
    into.attach(lens);
  }
}

// Canvas text helpers (Bungee / Titan One / Shrikhand are bundled; fonts reload triggers a redraw)
export const FONT = {
  sign: '"Bungee", Impact, "Arial Black", sans-serif',
  round: '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif',
  groovy: '"Shrikhand", "Cooper Black", Georgia, serif',
};
export function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
export function txt(ctx, s, x, y, o = {}) {
  const { font = FONT.sign, size = 40, fill = '#fff', stroke = null, lw = 0, align = 'center', maxW = 0, shadow = null, rot = 0 } = o;
  ctx.save();
  ctx.translate(x, y);
  if (rot) ctx.rotate(rot);
  let px = size;
  ctx.font = `${px}px ${font}`;
  if (maxW) while (ctx.measureText(s).width > maxW && px > 6) { px *= 0.94; ctx.font = `${px}px ${font}`; }
  ctx.textAlign = align; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
  if (shadow) { ctx.fillStyle = shadow; ctx.fillText(s, px * 0.05, px * 0.08); }
  if (stroke) { ctx.lineWidth = lw; ctx.strokeStyle = stroke; ctx.strokeText(s, 0, 0); }
  ctx.fillStyle = fill; ctx.fillText(s, 0, 0);
  ctx.restore();
}
export function starPath(ctx, cx, cy, ro, ri, n = 5, a0 = -HP) {
  ctx.beginPath();
  for (let i = 0; i < n * 2; i++) {
    const a = a0 + (i / (n * 2)) * TAU, r = i % 2 ? ri : ro;
    if (i) ctx.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r); else ctx.moveTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
  }
  ctx.closePath();
}

// A studio feed camera (bc_pedestal_camera) whose lens sits near the feed anchor; the prop is shifted sideways by
// `side` metres (keeps lanes clear; the virtual feed camera stays at the anchor, the prop never enters its view).
export function feedCamera(game, rt, parent, anchorId, { num = 1, side = 0, colliders = null } = {}) {
  const a = ANCHORS[anchorId];
  const yaw = yawTo(a.pos, a.target);
  const fwd = new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw));
  const right = new THREE.Vector3(Math.cos(yaw), 0, -Math.sin(yaw));
  const org = v3(a.pos).setY(0).addScaledVector(fwd, -0.74).addScaledVector(right, side);
  const g = place(game, parent, 'bc_pedestal_camera', {
    pos: org.toArray(), rotY: yaw, opts: { num, tally: false },
    colliders: colliders || [{ min: [-0.46, 0, -0.46], max: [0.46, 1.9, 0.5] }],
  });
  const { head, tilt, tally, lensTip } = g.userData.parts;
  const lensY = 1.44;
  const d = Math.hypot(a.target[0] - a.pos[0], a.target[2] - a.pos[2]);
  tilt.rotation.x = Math.atan2(a.target[1] - lensY, d);
  const mats = g.userData.lampMats;
  rt.warmMat(mats.on, mats.off);
  rt.onPower(a.pos, (on) => { tally.material = on ? mats.on : mats.off; });
  const phase = hashPhase(anchorId);
  rt.onTick((t, dt, vis) => { if (vis) head.rotation.y = 0.349 * Math.sin((t / 8) * TAU + phase); });
  rt.objects[anchorId] = { group: g, parts: { head, tilt, tally, lensTip } };
  return g;
}
const hashPhase = (s) => { let h = 0; for (const ch of s) h = (h * 31 + ch.charCodeAt(0)) % 997; return (h / 997) * TAU; };

// Feed monitor on a rolling AV stand; screen center lands on the anchor (faces the anchor's rotY).
export function standMonitor(game, rt, parent, anchorId) {
  const a = ANCHORS[anchorId];
  const M = studioMats(game);
  const size = 19.6, s = size / 14;
  const topY = a.pos[1] - (0.37 * s) * 0.57;               // monitor base so the screen center is at a.pos.y
  const stand = K.prop('sa_monitor_stand');
  const ink = '#2A2230', steel = '#8A8F9A';
  for (const r of [0.35, -0.35]) {
    stand.add(K.m(tg(K.box(0.72, 0.06, 0.08, 0.02), ink), M.lac, { pos: [0, 0.1, 0], rot: [0, r + 0.4, 0] }));
  }
  for (let i = 0; i < 4; i++) {
    const ang = 0.4 + (i / 4) * TAU + 0.35 * (i % 2 ? -1 : 1);
    stand.add(K.m(tg(K.cyl(0.035, 0.035, 0.05, { seg: 10 }), '#1E1A22').rotateZ(HP), M.lac, { pos: [Math.cos(ang) * 0.34, 0.035, Math.sin(ang) * 0.34] }));
  }
  stand.add(K.m(tg(K.cyl(0.03, 0.035, topY - 0.14, { seg: 12 }), steel), M.chrome, { pos: [0, 0.13, 0] }));
  stand.add(K.m(tg(K.box(0.62, 0.05, 0.5, 0.02), '#D9A520'), M.lac, { pos: [0, topY - 0.025, 0.02] }));
  stand.add(K.m(tg(K.box(0.14, 0.18, 0.14, 0.03), ink), M.lac, { pos: [0, topY - 0.12, 0] }));
  // cable dropping to the floor
  stand.add(K.m(tg(K.tube([[0.08, topY - 0.05, 0.2], [0.1, topY - 0.4, 0.26], [0.06, 0.5, 0.12], [0.1, 0.05, 0.3], [0.4, 0.012, 0.55]], 0.012, { seg: 16, radial: 4 }), ink), M.lac));
  K.finish(game, stand, { ao: { res: 40 } });
  place(game, parent, null, { group: stand, pos: [a.pos[0], 0, a.pos[2]], rotY: a.rotY, colliders: [{ min: [-0.36, 0, -0.34], max: [0.36, topY + 0.5, 0.34] }] });
  const mon = placeFit(game, parent, 'bc_rack_monitor', {
    opts: { size, card: 'snow', group: a.group, id: anchorId }, rotY: a.rotY, colliders: false,
    fit: (g) => g.userData.screens[0].mesh, target: a.pos, screenGroup: a.group, screenId: anchorId,
  });
  rt.objects[anchorId] = { group: mon, screen: mon.userData.screens[0]?.mesh, stand };
  return mon;
}

// Hanging string from a point up to the grid
function stringTo(M, x, y0, z, y1, color = '#2A2230', r = 0.005) {
  return K.m(tg(K.cyl(r, r, Math.max(0.05, y1 - y0), { seg: 5 }), color), M.lac, { pos: [x, y0, z] });
}

// =============================================================================================== Studio A deco
const CACHE = new WeakMap();
function cached(game, key, make) {
  let c = CACHE.get(game);
  if (!c) CACHE.set(game, (c = new Map()));
  let g = c.get(key);
  if (!g) { g = make(); c.set(key, g); }
  return cloneProp(g);
}

// Cute cardboard bat (hangs on a string): extruded silhouette + big googly eyes. Local: body center at origin.
function bat(game, s = 1) {
  return cached(game, `bat|${s}`, () => {
    const M = studioMats(game);
    const g = K.prop('sa_bat');
    const half = [[0, 0.1], [0.035, 0.15], [0.06, 0.07], [0.17, 0.12], [0.3, 0.21], [0.34, 0.1], [0.28, 0.075], [0.25, 0.0],
      [0.19, 0.045], [0.15, -0.035], [0.09, -0.01], [0.04, -0.08], [0, -0.09]];
    const pts = [...half, ...half.slice(1, -1).reverse().map(([x, y]) => [-x, y])].map(([x, y]) => [x * s, y * s]);
    g.add(K.m(tg(K.extrude(pts, 0.018 * s, { bevel: 0.006 * s, bevelSeg: 1 }), '#3A2440'), M.lac, { pos: [0, 0, -0.009 * s] }));
    for (const x of [-0.028, 0.028]) {
      g.add(K.m(tg(new THREE.SphereGeometry(0.024 * s, 10, 8), '#FFF8E8'), M.lac, { pos: [x * s, 0.035 * s, -0.018 * s] }));
      g.add(K.m(tg(new THREE.SphereGeometry(0.012 * s, 8, 6), '#1E1530'), M.lac, { pos: [(x + 0.004) * s, 0.03 * s, -0.035 * s] }));
    }
    for (const x of [-0.012, 0.012]) g.add(K.m(tg(new THREE.ConeGeometry(0.006 * s, 0.018 * s, 5).rotateX(Math.PI), '#FFFFFF'), M.lac, { pos: [x * s, -0.012 * s, -0.02 * s] }));
    g.userData.colliders = [];
    return K.finish(game, g, { ao: false });
  });
}

// Jack-o'-lantern with a glowing carved face (candle glow, always on).
function pumpkin(game, r = 0.24, seed = 1) {
  return cached(game, `pumpkin|${r}|${seed}`, () => {
    const M = studioMats(game);
    const g = K.prop('sa_pumpkin');
    const body = new THREE.SphereGeometry(r, 24, 14);
    const p = body.attributes.position;
    const col = new Float32Array(p.count * 3);
    const cA = new THREE.Color('#F08A24'), cB = new THREE.Color('#B8501A'), c = new THREE.Color();
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
      const th = Math.atan2(z, x);
      const f = Math.abs(Math.cos(th * 4));
      const k = 0.92 + 0.08 * Math.sqrt(f);
      const flat = y < -r * 0.6 ? 0.9 : 1;
      p.setXYZ(i, x * k, y * 0.78 * flat, z * k);
      c.copy(cB).lerp(cA, Math.pow(f, 0.35));
      col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
    }
    body.setAttribute('color', new THREE.BufferAttribute(col, 3));
    body.computeVertexNormals();
    g.add(K.m(body, M.lac, { pos: [0, r * 0.78, 0] }));
    g.add(K.m(tg(K.cyl(r * 0.1, r * 0.13, r * 0.35, { seg: 7 }), '#5A6A2A'), M.lac, { pos: [0, r * 1.45, 0], rot: [0.2, 0, 0.25 * (seed % 2 ? 1 : -1)] }));
    const face = new THREE.Group();
    const eye = K.extrude([[-0.07, -0.04], [0.07, -0.04], [0, 0.07]], 0.01, { bevel: 0.003 });
    const glowC = '#FFB347';
    for (const s of [-1, 1]) face.add(K.m(tg(eye, glowC), M.glow, { pos: [s * r * 0.36, r * 0.95, -r * 0.93], scale: r / 0.24 }));
    const mouth = [[-0.13, 0.02], [-0.08, -0.02], [-0.05, 0.01], [0, -0.035], [0.05, 0.01], [0.08, -0.02], [0.13, 0.02], [0.06, -0.06], [0, -0.075], [-0.06, -0.06]];
    face.add(K.m(tg(K.extrude(mouth, 0.01, { bevel: 0.003 }), glowC), M.glow, { pos: [0, r * 0.62, -r * 0.9], scale: r / 0.24 }));
    for (const o of face.children) { o.userData.noAO = true; o.material = M.glow; o.geometry = K.tint(o.geometry.clone(), new THREE.Color(1.9, 1.9, 1.9)); }
    g.add(...face.children);
    g.userData.colliders = [];
    return K.finish(game, g, { ao: { res: 32 } });
  });
}

// Cartoon cardboard tombstone with an atlas epitaph + a grass tuft
function tombstone(game, A, region, w = 0.62, h = 0.86) {
  return cached(game, `tomb|${region}|${w}`, () => {
    const M = studioMats(game);
    const g = K.prop('sa_tombstone');
    const s = new THREE.Shape();
    s.moveTo(-w / 2, 0); s.lineTo(w / 2, 0); s.lineTo(w / 2, h - w / 2);
    s.absarc(0, h - w / 2, w / 2, 0, Math.PI, false); s.closePath();
    g.add(K.m(tg(K.extrude(s, 0.12, { bevel: 0.03, bevelSeg: 2, curveSeg: 14 }), '#8C829E'), M.lac, { pos: [0, 0.02, -0.06] }));
    g.add(K.m(quad(w * 0.8, w * 0.8, A.uv(region)), A.mat, { pos: [0, h * 0.52, -0.095] }));
    for (const [x, sc] of [[-0.18, 1], [0.05, 0.8], [0.22, 0.9]]) g.add(K.m(tg(new THREE.SphereGeometry(0.1 * sc, 10, 6, 0, TAU, 0, HP), '#58A83E').scale(1.3, 0.6, 1), M.lac, { pos: [x, 0, -0.12] }));
    g.userData.colliders = [{ min: [-w / 2, 0, -0.14], max: [w / 2, h, 0.08] }];
    return K.finish(game, g, { ao: { res: 36 } });
  });
}

// Pleated velvet curtain leg (w x h, hangs from y = h), gold fringe hem; faces -z.
function curtainLeg(game, w, h, seed = 1) {
  return cached(game, `leg|${w}|${h}|${seed}`, () => {
    const M = studioMats(game);
    const g = K.prop('sa_curtain_leg');
    const pl = new THREE.PlaneGeometry(w, h, 26, 6);
    const p = pl.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i);
      const gather = 1 - 0.1 * ((y + h / 2) / h);
      p.setX(i, x * gather);
      p.setZ(i, Math.sin((x / w) * Math.PI * 9 + seed) * 0.06 + (y < -h / 2 + 0.3 ? 0.03 : 0));
    }
    pl.rotateY(Math.PI);
    pl.computeVertexNormals();
    K.uvScale(pl, w * 0.9, h * 0.9);
    g.add(K.m(K.tint(pl, '#ffffff'), M.velvet, { pos: [0, h / 2, 0] }));
    g.add(K.m(tg(K.tube([[-w * 0.47, 0.06, -0.02], [0, 0.07, -0.05], [w * 0.47, 0.06, -0.02]], 0.03, { seg: 12, radial: 5 }), PAL.harvestGold), M.lac));
    g.add(K.m(tg(K.box(w + 0.1, 0.16, 0.16, 0.03), '#2A1D2A'), M.lac, { pos: [0, h, 0.02] }));
    g.userData.colliders = [];
    return K.finish(game, g, { ao: false });
  });
}

// Scalloped velvet valance with gold fringe (w wide, hangs down from y = 0), faces -z.
function valance(game, w, depthH = 0.8) {
  return cached(game, `val|${w}`, () => {
    const M = studioMats(game);
    const g = K.prop('sa_valance');
    const n = Math.round(w / 1.4);
    const pl = new THREE.PlaneGeometry(w, depthH, n * 6, 3);
    const p = pl.attributes.position;
    const hem = [];
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i);
      const ph = ((x / w + 0.5) * n) % 1;
      const sag = Math.sin(ph * Math.PI) * 0.28;
      const t = (depthH / 2 - y) / depthH;
      p.setY(i, y - sag * t);
      p.setZ(i, -Math.sin(ph * Math.PI) * 0.12 * t + Math.sin((x / w) * Math.PI * n * 4) * 0.02);
      if (y < -depthH / 2 + 1e-4) hem.push([x, y - sag - depthH / 2, p.getZ(i)]);
    }
    pl.rotateY(Math.PI);
    pl.computeVertexNormals();
    K.uvScale(pl, w * 0.9, 1);
    g.add(K.m(K.tint(pl, '#ffffff'), M.velvet, { pos: [0, -depthH / 2, 0] }));
    hem.sort((a, b) => a[0] - b[0]);
    g.add(K.m(tg(K.tube(hem.map(([x, y, z]) => [-x, y + depthH / 2 - depthH / 2, -z - 0.01]), 0.028, { seg: n * 10, radial: 5 }), PAL.harvestGold), M.lac, { pos: [0, 0, 0] }));
    g.add(K.m(tg(K.box(w + 0.1, 0.14, 0.14, 0.03), '#2A1D2A'), M.lac, { pos: [0, 0.02, 0.05] }));
    g.userData.colliders = [];
    return K.finish(game, g, { ao: false });
  });
}

// Hanging or wall banner: board with an atlas face (both sides printed when hanging); strings to `hangTo` height.
function banner(game, A, region, w, h, { hang = 0, color = '#2A1D2A' } = {}) {
  const M = studioMats(game);
  const g = K.prop('sa_banner');
  g.add(K.m(tg(K.box(w + 0.08, h + 0.08, 0.04, 0.02), color), M.lac, { pos: [0, 0, 0] }));
  g.add(K.m(quad(w, h, A.uv(region)), A.mat, { pos: [0, 0, -0.022] }));
  if (hang) {
    const back = quad(w, h, A.uv(region)); back.rotateY(Math.PI);
    g.add(K.m(back, A.mat, { pos: [0, 0, 0.022] }));
    for (const s of [-1, 1]) g.add(stringTo(M, s * (w / 2 - 0.2), h / 2 + 0.04, 0, h / 2 + hang));
  }
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}

// Fog machine (FOG-O-MATIC) with a hose and a cable
function fogMachine(game, A) {
  const M = studioMats(game);
  const g = K.prop('sa_fog');
  g.add(K.m(tg(K.box(0.56, 0.26, 0.32, 0.04), '#3A3348'), M.lac, { pos: [0, 0.16, 0] }));
  g.add(K.m(tg(K.box(0.6, 0.04, 0.36, 0.015), '#2A2230'), M.lac, { pos: [0, 0.02, 0] }));
  g.add(K.m(quad(0.34, 0.085, A.uv('fog')), A.mat, { pos: [0, 0.18, -0.162] }));
  g.add(K.m(tg(K.cyl(0.05, 0.06, 0.14, { seg: 12 }).rotateX(-HP), '#A8B0BA'), M.chrome, { pos: [0.16, 0.2, -0.16] }));
  g.add(K.m(tg(K.box(0.2, 0.06, 0.12, 0.02), PAL.channelRed), M.lac, { pos: [-0.12, 0.31, 0.04] }));
  g.add(K.m(tg(K.tube([[0.28, 0.1, 0.12], [0.5, 0.02, 0.3], [0.9, 0.012, 0.35], [1.3, 0.012, 0.6]], 0.012, { seg: 16, radial: 4 }), '#2A2230'), M.lac));
  g.userData.colliders = [{ min: [-0.3, 0, -0.2], max: [0.3, 0.36, 0.2] }];
  return K.finish(game, g, { ao: { res: 32 } });
}

// Cue card (hand-lettered) lying on the floor / leaning
function cueCard(game, A, region) {
  const M = studioMats(game);
  const g = K.prop('sa_cue');
  g.add(K.m(tg(K.box(0.62, 0.46, 0.02, 0.008), '#F4F1E8'), M.lac, { pos: [0, 0, 0] }));
  g.add(K.m(quad(0.58, 0.42, A.uv(region)), A.mat, { pos: [0, 0, -0.012] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}

// Floor litter: pledge slips (atlas), paper cups, popcorn — tinted geometry, all merged into ~3 draws.
function litter(game, A, spots, seed = 1) {
  const M = studioMats(game);
  const rnd = mulberry(seed);
  const g = K.prop('sa_litter');
  const slip = quad(0.14, 0.18, A.uv('slip')).rotateX(-HP);
  const cup = K.lathe([[0, 0], [0.032, 0], [0.042, 0.1], [0.044, 0.105], [0, 0.105]], { seg: 12 });
  const corn = new THREE.IcosahedronGeometry(0.022, 0);
  for (const s of spots) {
    const [cx, cy, cz] = s.at;
    for (let i = 0; i < (s.slips || 0); i++) {
      const a = rnd() * TAU, r = (s.r0 ?? 0) + rnd() * (s.r ?? 1);
      g.add(K.m(slip, A.mat, { pos: [cx + Math.cos(a) * r, cy + 0.006 + i * 0.0004, cz + Math.sin(a) * r], rot: [0, rnd() * TAU, 0] }));
    }
    for (let i = 0; i < (s.cups || 0); i++) {
      const a = rnd() * TAU, r = (s.r0 ?? 0) + rnd() * (s.r ?? 1);
      const tip = rnd() < 0.5;
      const m = K.m(tg(cup, i % 2 ? '#F4F1E8' : '#FFE9C8'), M.plastic, { pos: [cx + Math.cos(a) * r, cy + (tip ? 0.044 : 0), cz + Math.sin(a) * r] });
      if (tip) m.rotation.set(HP, rnd() * TAU, 0, 'YXZ');
      g.add(m);
      g.add(K.m(tg(K.cyl(0.045, 0.045, 0.012, { seg: 12 }), PAL.channelRed), M.plastic, { pos: m.position.toArray(), rot: [m.rotation.x, m.rotation.y, 0], scale: tip ? 0.001 : 1 }));
    }
    for (let i = 0; i < (s.corn || 0); i++) {
      const a = rnd() * TAU, r = (s.r0 ?? 0) + Math.sqrt(rnd()) * (s.r ?? 1);
      g.add(K.m(tg(corn, rnd() < 0.25 ? '#F4D06A' : '#FFF6DC'), M.plastic, { pos: [cx + Math.cos(a) * r, cy + 0.015, cz + Math.sin(a) * r], rot: [rnd() * 3, rnd() * 3, 0], scale: 0.8 + rnd() * 0.6 }));
    }
  }
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}
function mulberry(a) {
  return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// Sandbag (stand weights)
function sandbag(game) {
  return cached(game, 'sandbag', () => {
    const M = studioMats(game);
    const g = K.prop('sa_sandbag');
    g.add(K.m(tg(K.cushion(0.36, 0.14, 0.24, { puff: 0.035 }), '#7A6A48'), M.felt, { pos: [0, 0.07, 0] }));
    g.add(K.m(tg(K.tube([[-0.12, 0.13, 0], [0, 0.2, 0], [0.12, 0.13, 0]], 0.012, { seg: 8, radial: 4 }), '#5A4A30'), M.felt));
    g.userData.colliders = [];
    return K.finish(game, g, { ao: { res: 24 } });
  });
}

// ------------------------------------------------------------------------------------------ Studio A atlas
const REG_A = {
  backdrop: [0, 0, 1024, 300],
  pledge: [0, 300, 1024, 120],
  thanks: [0, 420, 1024, 120],
  operators: [0, 540, 1024, 120],
  poster1: [0, 660, 180, 240], poster2: [180, 660, 180, 240], poster3: [360, 660, 180, 240],
  tomb1: [540, 660, 128, 128], tomb2: [668, 660, 128, 128],
  studio: [796, 660, 228, 110], quiet: [796, 770, 228, 70],
  cue1: [540, 788, 128, 96], cue2: [668, 788, 128, 96],
  slip: [796, 840, 56, 72], fog: [852, 840, 172, 44], web: [852, 884, 120, 120],
  goal: [0, 900, 540, 124],
};

function drawStudioA(ctx, R, rand) {
  const C = { plum: '#6B3A6E', deep: '#2A1740', gold: '#FFC23A', orange: '#E3662B', cream: '#F6E7C8', red: '#E23B3B', blue: '#2F5BD3' };
  // ---- backdrop: spooky-cute night over the WZTV tower, giant SPOOKTACULAR title, the Baron's portrait
  {
    const [x, y, w, h] = R('backdrop');
    ctx.save(); ctx.translate(x, y);
    let g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, '#1B1238'); g.addColorStop(0.55, '#4A2466'); g.addColorStop(1, '#A8406A');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 70; i++) { ctx.fillStyle = `rgba(255,244,214,${0.4 + rand() * 0.6})`; starPath(ctx, rand() * w, rand() * h * 0.55, 2 + rand() * 3, 1, 4); ctx.fill(); }
    // moon with a 13
    ctx.fillStyle = '#FFF4D6'; ctx.beginPath(); ctx.arc(120, 92, 62, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(200,180,140,0.35)'; for (const [cx, cy, r] of [[98, 70, 12], [140, 118, 9], [150, 76, 6]]) { ctx.beginPath(); ctx.arc(cx, cy, r, 0, TAU); ctx.fill(); }
    txt(ctx, '13', 120, 96, { font: FONT.round, size: 54, fill: '#E3662B', stroke: '#6B3A6E', lw: 5 });
    // hills + the tower
    ctx.fillStyle = '#2A1740';
    ctx.beginPath(); ctx.moveTo(0, h); ctx.lineTo(0, 230); ctx.quadraticCurveTo(160, 190, 330, 236); ctx.quadraticCurveTo(520, 270, 700, 226); ctx.quadraticCurveTo(880, 196, w, 240); ctx.lineTo(w, h); ctx.fill();
    ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 3;
    const tx = 860, ty = 215;
    ctx.beginPath(); ctx.moveTo(tx - 26, ty); ctx.lineTo(tx, ty - 150); ctx.lineTo(tx + 26, ty); ctx.stroke();
    for (let i = 0; i < 7; i++) { const yy = ty - i * 21; const hw = 26 * (1 - i / 7.2); ctx.beginPath(); ctx.moveTo(tx - hw, yy); ctx.lineTo(tx + hw * 0.8, yy - 21); ctx.stroke(); }
    ctx.fillStyle = '#FF3B30'; ctx.beginPath(); ctx.arc(tx, ty - 152, 7, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(255,59,48,0.25)'; ctx.beginPath(); ctx.arc(tx, ty - 152, 18, 0, TAU); ctx.fill();
    // bats
    ctx.fillStyle = '#1B1238';
    for (const [bx, by, bs] of [[260, 60, 1], [320, 40, 0.7], [700, 50, 0.9], [760, 90, 0.6], [560, 30, 0.6]]) {
      ctx.beginPath(); ctx.moveTo(bx, by);
      ctx.quadraticCurveTo(bx - 18 * bs, by - 16 * bs, bx - 34 * bs, by - 4 * bs); ctx.quadraticCurveTo(bx - 22 * bs, by, bx - 18 * bs, by + 6 * bs);
      ctx.quadraticCurveTo(bx - 8 * bs, by + 2 * bs, bx, by + 8 * bs);
      ctx.quadraticCurveTo(bx + 8 * bs, by + 2 * bs, bx + 18 * bs, by + 6 * bs); ctx.quadraticCurveTo(bx + 22 * bs, by, bx + 34 * bs, by - 4 * bs);
      ctx.quadraticCurveTo(bx + 18 * bs, by - 16 * bs, bx, by); ctx.fill();
    }
    // title
    txt(ctx, '13-HOUR', 512, 50, { font: FONT.sign, size: 40, fill: C.cream, stroke: C.deep, lw: 8, track: 2 });
    g = ctx.createLinearGradient(0, 80, 0, 190); g.addColorStop(0, '#FFF2B0'); g.addColorStop(0.5, '#FFC23A'); g.addColorStop(1, '#FF7A2A');
    txt(ctx, 'Spooktacular', 512, 132, { font: FONT.groovy, size: 118, fill: g, stroke: '#2A1030', lw: 16, maxW: 700, shadow: 'rgba(0,0,0,0.45)' });
    txt(ctx, 'TELETHON', 512, 212, { font: FONT.sign, size: 50, fill: '#F4F1E8', stroke: '#2A1030', lw: 9 });
    txt(ctx, 'STAY UP WITH THE BARON • CALL 555-1313', 512, 268, { font: FONT.round, size: 24, fill: C.gold, stroke: C.deep, lw: 5, maxW: 640 });
    // host portrait
    ctx.save(); ctx.translate(900, 40);
    rr(ctx, -8, -8, 116, 150, 14); ctx.fillStyle = C.gold; ctx.fill();
    try { drawTo(ctx, 'portrait_baron', 100, 134); } catch (e) { /* card missing: keep the frame */ }
    ctx.restore();
    txt(ctx, 'YOUR HOST', 950, 196, { font: FONT.sign, size: 18, fill: C.cream, stroke: C.deep, lw: 4 });
    ctx.restore();
  }
  // ---- long banners
  const band = (name, bg, fg, stroke, main, sub, deco) => {
    const [x, y, w, h] = R(name);
    ctx.save(); ctx.translate(x, y);
    rr(ctx, 2, 2, w - 4, h - 4, 18); ctx.fillStyle = bg; ctx.fill();
    ctx.lineWidth = 8; ctx.strokeStyle = stroke; rr(ctx, 10, 10, w - 20, h - 20, 12); ctx.stroke();
    for (let i = 0; i < 2; i++) { ctx.fillStyle = deco; starPath(ctx, i ? w - 58 : 58, h / 2, 30, 13); ctx.fill(); }
    txt(ctx, main, w / 2, h / 2 - (sub ? 12 : 0), { font: FONT.sign, size: 58, fill: fg, stroke, lw: 8, maxW: w - 180 });
    if (sub) txt(ctx, sub, w / 2, h / 2 + 36, { font: FONT.round, size: 22, fill: fg, maxW: w - 200 });
    ctx.restore();
  };
  band('pledge', C.cream, C.red, C.blue, 'PLEDGE NOW!  ☎ 555-1313', 'KEEP CHANNEL 13 ON THE AIR ALL NIGHT', C.gold);
  band('thanks', C.orange, C.cream, '#5A2A22', 'THANK YOU FOR PLEDGING!', null, C.gold);
  band('operators', C.blue, '#FFF4DC', '#1B2F7A', 'OPERATORS ARE STANDING BY', 'CALL NOW • 555-1313', C.red);
  // ---- posters (cards.js art)
  for (const [n, id] of [['poster1', 'poster_spooktacular'], ['poster2', 'sponsor_poster_double_vision'], ['poster3', 'poster_boogie_down']]) {
    const [x, y, w, h] = R(n);
    ctx.save(); ctx.translate(x, y);
    try { drawTo(ctx, id, w, h); } catch (e) { ctx.fillStyle = C.plum; ctx.fillRect(0, 0, w, h); }
    ctx.restore();
  }
  // ---- tomb epitaphs
  for (const [n, a, b] of [['tomb1', 'R.I.P.', 'DEAD AIR'], ['tomb2', 'R.I.P.', 'RERUNS']]) {
    const [x, y, w, h] = R(n);
    ctx.fillStyle = '#9A90AC'; ctx.fillRect(x, y, w, h);
    for (let i = 0; i < 40; i++) { ctx.fillStyle = `rgba(${rand() < 0.5 ? '255,255,255' : '40,30,60'},0.08)`; ctx.fillRect(x + rand() * w, y + rand() * h, 3 + rand() * 6, 2); }
    txt(ctx, a, x + w / 2, y + 40, { font: FONT.sign, size: 30, fill: '#4A3A5E' });
    txt(ctx, b, x + w / 2, y + 80, { font: FONT.round, size: 18, fill: '#4A3A5E', maxW: w - 16 });
    txt(ctx, '1977', x + w / 2, y + 106, { font: FONT.round, size: 14, fill: '#5A4A6E' });
  }
  // ---- signs
  {
    const [x, y, w, h] = R('studio');
    ctx.fillStyle = '#E8A92E'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = '#2A1D2A'; for (let i = 0; i < 12; i++) { ctx.beginPath(); ctx.moveTo(x + i * 22, y + h); ctx.lineTo(x + i * 22 + 11, y + h); ctx.lineTo(x + i * 22 + 25, y + h - 14); ctx.lineTo(x + i * 22 + 14, y + h - 14); ctx.fill(); }
    txt(ctx, 'STUDIO A', x + w / 2, y + 46, { font: FONT.sign, size: 52, fill: '#2A1D2A', maxW: w - 20 });
  }
  {
    const [x, y, w, h] = R('quiet');
    rr(ctx, x + 2, y + 2, w - 4, h - 4, 12); ctx.fillStyle = '#E23B3B'; ctx.fill();
    txt(ctx, 'QUIET ON THE SET', x + w / 2, y + h / 2, { font: FONT.sign, size: 26, fill: '#FFF4DC', maxW: w - 20 });
  }
  for (const [n, s, col] of [['cue1', 'APPLAUSE!', '#E23B3B'], ['cue2', 'SCREAM!', '#6B3A6E']]) {
    const [x, y, w, h] = R(n);
    ctx.fillStyle = '#FFFBEF'; ctx.fillRect(x, y, w, h);
    txt(ctx, s, x + w / 2, y + h / 2, { font: FONT.round, size: 30, fill: col, maxW: w - 12, rot: -0.06 });
  }
  {
    const [x, y, w, h] = R('slip');
    ctx.fillStyle = '#FFFBEF'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = '#E23B3B'; ctx.fillRect(x, y, w, 14);
    ctx.fillStyle = 'rgba(60,90,200,0.4)'; for (let yy = y + 26; yy < y + h - 4; yy += 10) ctx.fillRect(x + 6, yy, w - 12, 2);
    txt(ctx, '$13', x + 22, y + 40, { font: FONT.round, size: 16, fill: '#2A2A8A', rot: -0.2 });
  }
  {
    const [x, y, w, h] = R('fog');
    ctx.fillStyle = '#2A2230'; ctx.fillRect(x, y, w, h);
    txt(ctx, 'FOG-O-MATIC', x + w / 2, y + h / 2, { font: FONT.sign, size: 22, fill: '#9FE8FF', maxW: w - 10 });
  }
  {
    const [x, y, w, h] = R('web');
    ctx.save(); ctx.translate(x, y);
    ctx.strokeStyle = 'rgba(240,236,255,0.95)'; ctx.lineWidth = 2.2;
    for (let i = 0; i <= 6; i++) { const a = (i / 6) * HP; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.cos(a) * w, Math.sin(a) * h); ctx.stroke(); }
    for (let k = 1; k <= 5; k++) {
      const r = k * (w / 5.4);
      ctx.beginPath();
      for (let i = 0; i <= 6; i++) { const a = (i / 6) * HP; const px = Math.cos(a) * r, py = Math.sin(a) * r; if (i) ctx.quadraticCurveTo(Math.cos(a - HP / 12) * r * 0.86, Math.sin(a - HP / 12) * r * 0.86, px, py); else ctx.moveTo(px, py); }
      ctx.stroke();
    }
    ctx.restore();
  }
  {
    const [x, y, w, h] = R('goal');
    rr(ctx, x + 2, y + 2, w - 4, h - 4, 20); ctx.fillStyle = '#1B2F7A'; ctx.fill();
    ctx.lineWidth = 6; ctx.strokeStyle = C.gold; rr(ctx, x + 10, y + 10, w - 20, h - 20, 14); ctx.stroke();
    txt(ctx, 'TONIGHT\'S GOAL  $13,000', x + w / 2, y + 46, { font: FONT.sign, size: 38, fill: C.gold, maxW: w - 40 });
    txt(ctx, 'HELP KEEP WZTV 13 ON THE AIR!', x + w / 2, y + 90, { font: FONT.round, size: 22, fill: C.cream, maxW: w - 40 });
  }
}

// =============================================================================================== build
export function build(game, area, root) {
  const rt = runtime(game, AREA, root);
  const M = studioMats(game);
  const O = rt.objects;
  const A = makeAtlas(game, 'sa_atlas_v1', 1024, REG_A, drawStudioA);
  rt.warmMat(M.glow, M.glowDim);

  const dyn = new THREE.Group();              // animated / swapped at runtime: never merged by the level
  dyn.name = 'studio_a:dynamic';
  dyn.userData.noMerge = true;
  root.add(dyn);
  const P = (id, o) => place(game, root, id, { area: AREA, ...o });

  // ---------------------------------------------------------------------------------------------- the stage
  const wheelA = ANCHORS.ee_prize_wheel;
  const wheel = P('pledge_wheel', { pos: wheelA.pos, rotY: wheelA.rotY });
  wheel.userData.noMerge = true;
  dyn.attach(wheel);
  const hubObj = new THREE.Object3D();
  hubObj.position.fromArray(wheel.userData.anchors.hub);
  wheel.add(hubObj);
  wheel.updateMatrixWorld(true);
  const seat = new THREE.Vector3().fromArray(wheel.userData.anchors.puppet_seat).applyMatrix4(wheel.matrixWorld);
  const wheelState = { spinning: false, t: 0, dur: 0, from: 0, to: 0, lastPeg: 0, flap: 0 };
  const wp = wheel.userData.parts;
  O.ee_prize_wheel = {
    group: wheel, parts: { wheel: wp.wheel, flapper: wp.flapper, lever: wp.lever, hub: hubObj },
    hub: hubObj.getWorldPosition(new THREE.Vector3()), puppetSeat: seat,
    get spinning() { return wheelState.spinning; },
    spin({ turns = 2.2 + Math.random() * 2.4, duration = 4.1 } = {}) {
      if (wheelState.spinning) return 0;
      Object.assign(wheelState, { spinning: true, t: 0, dur: duration, from: wp.wheel.rotation.z, to: wp.wheel.rotation.z - turns * TAU });
      return duration;
    },
  };
  rt.onTick((t, dt) => {
    const s = wheelState;
    if (s.spinning) {
      s.t += dt;
      const k = Math.min(1, s.t / s.dur);
      const e = 1 - Math.pow(1 - k, 2.6);
      wp.wheel.rotation.z = s.from + (s.to - s.from) * e;
      const pull = Math.min(1, s.t / 0.15) * (1 - Math.min(1, Math.max(0, s.t - 0.35) / 0.4));
      wp.lever.rotation.z = -0.9 * pull;
      const peg = Math.floor(-wp.wheel.rotation.z / (TAU / 13));
      if (peg !== s.lastPeg) { s.lastPeg = peg; s.flap = 1; }
      if (k >= 1) s.spinning = false;
    }
    if (s.flap > 0) { s.flap = Math.max(0, s.flap - dt * 9); wp.flapper.rotation.z = 0.45 * s.flap * (Math.sin(t * 60) * 0.3 + 0.7); }
  });
  rt.onReset(() => { wheelState.spinning = false; wp.lever.rotation.z = 0; });

  const throne = P('baron_throne', { pos: ANCHORS.prop_throne.pos, rotY: ANCHORS.prop_throne.rotY });
  throne.updateMatrixWorld(true);
  O.baron_throne = { group: throne, parts: throne.userData.parts, seat: new THREE.Vector3().fromArray(throne.userData.anchors.seat).applyMatrix4(throne.matrixWorld) };

  // contestant podiums (front-east of the stage, facing the audience)
  const podiums = [[8.33, -26.62, Math.PI + 0.1, '$130'], [9.4, -26.56, Math.PI, '$250'], [10.45, -26.62, Math.PI - 0.12, '$13']];
  const podiumGroups = podiums.map(([x, z, r, score], i) => {
    const g = P('contestant_podium', { pos: [x, 0.6, z], rotY: r, opts: { num: i + 1, score } });
    unlockParts(g, ['buzzer', 'score']);
    bakeInstanced(g.userData.parts.bulbs, M.glow);
    return g;
  });
  O.contestant_podiums = podiumGroups.map((g) => ({ group: g }));

  // ghost light (toy) — the only light before Sign-On
  const gl = ANCHORS.toy_ghost_light;
  const ghost = P('ghost_light', { pos: gl.pos, rotY: 0.4 });
  const bulb = ghost.userData.parts.bulb;
  setGhostLight(ghost, false, game);
  setGhostLight(ghost, true);
  rt.warmMat(ghost.userData._bulbOn, ghost.userData._bulbOff);
  const ghostPos = [gl.pos[0], gl.pos[1] + 1.75, gl.pos[2]];
  rt.anchor('sa_ghost', { pos: ghostPos, color: '#FFE0A8', intensity: 5.5, distance: 11 });
  const ghostPool = rt.pool([gl.pos[0], 0.62, gl.pos[2]], 2.6, '#FFD9A0', 0.22);
  const ghostState = { on: true, powered: false };
  const applyGhost = () => {
    setGhostLight(ghost, ghostState.on);
    rt.setAnchor('sa_ghost', { intensity: ghostState.on ? (ghostState.powered ? 2.6 : 5.5) : 0, distance: ghostState.powered ? 8 : 11 });
    ghostPool.set({ intensity: ghostState.on ? (ghostState.powered ? 0.12 : 0.22) : 0 });
  };
  O.ghost_light = { group: ghost, parts: { bulb }, get on() { return ghostState.on; }, set(on) { ghostState.on = !!on; applyGhost(); } };
  rt.onPower(gl.pos, (on) => { ghostState.powered = on; applyGhost(); });
  rt.onReset(() => { ghostState.on = true; applyGhost(); });
  game.interact?.register?.({
    id: 'toy_ghost_light', pos: [gl.pos[0], gl.pos[1] + 0.4, gl.pos[2]], radius: 1.4, prompt: () => ({}),
    use: () => { O.ghost_light.set(!ghostState.on); game.audio?.play?.('toy_ghost_light', { pos: v3(ghostPos) }); },
  });
  const tw = ANCHORS.toy_prize_wheel;
  game.interact?.register?.({
    id: 'toy_prize_wheel', pos: [tw.pos[0], tw.pos[1] + 0.4, tw.pos[2]], radius: 1.3, prompt: () => ({}),
    use: () => { if (O.ee_prize_wheel.spin()) game.audio?.play?.('toy_wheel', { pos: O.ee_prize_wheel.hub }); },
  });

  // stage monitors (screen spawns): big walnut CRTs, screen centers exactly on ss_studio_a_w / ss_studio_a_e
  for (const [id, legs] of [['ss_studio_a_w', 'splay'], ['ss_studio_a_e', 'swivel']]) {
    const s = ss(id);
    const g = placeFit(game, root, 'bc_tv_19', {
      opts: { legs, card: 'station_id', group: 'scr_decor', unique: id }, scale: 1.8, rotY: s.rotY, area: AREA,
      fit: (gg) => gg.userData.screens[0].mesh, target: s.pos, floorY: id === 'ss_studio_a_e' ? 0.6 : 0,
      screenGroup: 'scr_decor', screenId: id,
    });
    O[id] = { group: g, screen: g.userData.screens[0]?.mesh };
  }

  // spooky telethon stage dressing: tombstones, jack-o'-lanterns, fog machine, cue cards, curtains, backdrop
  P(null, { group: tombstone(game, A, 'tomb1'), pos: [-2.35, 0.6, -29.45], rotY: Math.PI - 0.15 });
  P(null, { group: tombstone(game, A, 'tomb2', 0.52, 0.74), pos: [6.85, 0.6, -29.55], rotY: Math.PI + 0.2 });
  for (const [x, y, z, r, s] of [[-2.55, 0.6, -26.45, 0.26, 1], [-1.95, 0.6, -26.3, 0.18, 2], [7.35, 0.6, -29.2, 0.2, 3],
    [-6.2, 0, -25.6, 0.22, 4], [-5.7, 0, -25.4, 0.16, 5], [11.6, 0, -24.9, 0.2, 6]]) {
    P(null, { group: pumpkin(game, r, s), pos: [x, y, z], rotY: Math.PI + (s % 3 - 1) * 0.35, colliders: [{ min: [-r, 0, -r], max: [r, r * 1.6, r] }] });
  }
  P(null, { group: fogMachine(game, A), pos: [1.05, 0.6, -26.45], rotY: Math.PI - 0.3 });
  P(null, { group: cueCard(game, A, 'cue1'), pos: [2.2, 0.62, -26.35], rotY: Math.PI + 0.1, colliders: false }).rotation.x = -HP + 0.02;
  { const c = P(null, { group: cueCard(game, A, 'cue2'), pos: [-4.1, 0.25, -27.4], rotY: -0.6, colliders: false }); c.rotation.set(-0.28, -0.6, 0.05, 'YXZ'); }
  // curtain legs + valance frame the stage; painted backdrop on the back wall above it
  P(null, { group: curtainLeg(game, 1.5, 5.9, 1), pos: [-2.25, 0.6, -29.62], colliders: false });
  P(null, { group: curtainLeg(game, 1.5, 5.9, 2), pos: [10.25, 0.6, -29.62], colliders: false });
  P(null, { group: valance(game, 14.2), pos: [4, 6.45, -29.55], colliders: false });
  {
    const bd = banner(game, A, 'backdrop', 11.2, 3.28, { color: '#1B1238' });
    P(null, { group: bd, pos: [4, 4.55, -29.8], colliders: false });
  }
  // cobwebs in the stage back corners (alpha cut-out)
  for (const [x, s] of [[-2.9, 1], [10.9, -1]]) {
    const w = K.m(quad(1.1, 1.1, A.uv('web')), A.cut, { pos: [x + s * 0.02, 1.25, -29.83] });
    w.scale.x = s;
    w.rotation.z = s > 0 ? 0 : 0;
    root.add(w);
  }

  // ---------------------------------------------------------------------------------------------- marquee arch
  const mq = P('pledge_carousel' && 'marquee_arch', { pos: [4, 0, -24.95], rotY: 0, opts: { width: 14.4 } });
  mq.userData.noMerge = true;
  dyn.attach(mq);
  marqueeChase(mq, 0, 'off');
  const mqState = { mode: null, powered: false, step: -1 };
  O.marquee_arch = {
    group: mq, parts: mq.userData.parts, get mode() { return mqState.mode ?? (mqState.powered ? 'chase' : 'off'); },
    setMode(m) { mqState.mode = m; mqState.step = -1; },
  };
  rt.anchor('sa_marquee_w', { pos: [-1.8, 3.9, -24.2], color: PAL.marqueeGold, intensity: 0, distance: 8 });
  rt.anchor('sa_marquee_e', { pos: [9.8, 3.9, -24.2], color: PAL.marqueeGold, intensity: 0, distance: 8 });
  const mqPools = [rt.pool([-1.2, 0.02, -24.2], 2.4, PAL.marqueeGold, 0), rt.pool([9.2, 0.02, -24.2], 2.4, PAL.marqueeGold, 0)];
  rt.onPower([4, 1, -24.95], (on) => {
    mqState.powered = on; mqState.step = -1;
    rt.setAnchor('sa_marquee_w', { intensity: on ? 2.4 : 0 });
    rt.setAnchor('sa_marquee_e', { intensity: on ? 2.4 : 0 });
    for (const p of mqPools) p.set({ intensity: on ? 0.16 : 0 });
  });
  rt.onTick((t, dt, vis) => {
    if (!vis) return;
    const mode = O.marquee_arch.mode;
    const step = mode === 'off' || mode === 'on' ? 0 : Math.floor(t * 9);
    if (step === mqState.step && mqState.last === mode) return;
    mqState.step = step; mqState.last = mode;
    marqueeChase(mq, t, mode);
  });

  // ---------------------------------------------------------------------------------------------- carousel + tote
  const toteA = ANCHORS.ee_tote_board;
  const car = P('pledge_carousel', { pos: toteA.pos, rotY: 0.26 });
  car.userData.noMerge = false;
  const carParts = car.userData.parts;
  for (const k of ['handsets', 'lamps']) dyn.attach(carParts[k]);
  O.pledge_carousel = { group: car, parts: carParts };
  const tote = P('tote_board_tower', { pos: toteA.pos, rotY: 0.26, opts: { value: 12987 } });
  tote.userData.noMerge = true;
  dyn.attach(tote);
  bakeInstanced(tote.userData.parts.bulbs, M.glow);
  setToteGlow(tote, game, 1);
  const glowHi = tote.userData.parts.digits_0.material;
  setToteGlow(tote, game, 0.3);
  rt.warmMat(glowHi, tote.userData.parts.digits_0.material);
  const toteState = { value: 12987, glow: 0.3 };
  O.ee_tote_board = {
    group: tote, parts: tote.userData.parts, goal: 13000,
    get value() { return toteState.value; },
    setValue(v) { toteState.value = v; setToteValue(tote, v); },
    setGlow(k) { toteState.glow = k; setToteGlow(tote, game, k); },
  };
  rt.anchor('sa_tote', { pos: [toteA.pos[0], 2.6, toteA.pos[2]], color: PAL.gelAmber, intensity: 1.4, distance: 6 });
  const totePool = rt.pool([toteA.pos[0], 0.02, toteA.pos[2]], 3.4, PAL.gelAmber, 0.07);
  rt.onPower(toteA.pos, (on) => {
    O.ee_tote_board.setGlow(on ? 1 : 0.3);
    rt.setAnchor('sa_tote', { intensity: on ? 2.4 : 1.4 });
    totePool.set({ intensity: on ? 0.13 : 0.07 });
  });
  rt.onReset(() => O.ee_tote_board.setValue(12987));
  // ringing pledge phones (after power): one phone rings for ~1.6 s every ~2.6 s
  const ringer = { i: -1, t0: 0, next: 1.5 };
  rt.onTick((t, dt, vis) => {
    if (!rt.powered || !vis) { if (ringer.i >= 0) { ringPhone(car, ringer.i, 0, false); ringer.i = -1; } return; }
    if (ringer.i < 0 && t > ringer.next) { ringer.i = Math.floor(Math.random() * 12); ringer.t0 = t; }
    if (ringer.i >= 0) {
      const k = t - ringer.t0;
      const on = k < 1.6 && (k % 0.8) < 0.5;
      ringPhone(car, ringer.i, t, on);
      if (k > 1.6) { ringPhone(car, ringer.i, t, false); ringer.i = -1; ringer.next = t + 1 + Math.random() * 2.2; }
    }
  });
  // telethon goal sign on the carousel's east side? (kept clear: the ring). Pledge litter around the desk.
  root.add(litter(game, A, [
    { at: [toteA.pos[0], 0, toteA.pos[2]], slips: 16, r0: 2.2, r: 1.6, cups: 3 },
    { at: [-2.5, 0, -15.1], corn: 60, r: 1.4, cups: 2, slips: 3 },
    { at: [10.5, 0, -15.0], corn: 45, r: 1.2, cups: 2, slips: 2 },
    { at: [4, 0, -25.2], slips: 4, r: 3 },
  ], 13));

  // ---------------------------------------------------------------------------------------------- bleachers
  for (const [x, seed] of [[-2.5, 1], [10.5, 2]]) {
    const b = P('bleacher_block', { pos: [x, 0.012, -13.262], opts: { width: 8, depth: 2.5, seed }, colliders: false });
    const bp = b.children.filter((c) => c.isInstancedMesh);
    for (const im of bp) bakeInstanced(im);
  }

  // ---------------------------------------------------------------------------------------------- applause sign
  const ap = ANCHORS.ee_applause_sign;
  const applause = P('bc_applause', { pos: [ap.pos[0], ap.pos[1] - 0.21, ap.pos[2] - 0.16], rotY: 0, opts: { lit: false, chain: 2.7 }, colliders: false });
  applause.userData.noMerge = true;
  dyn.attach(applause);
  const apm = applause.userData.lampMats;
  rt.warmMat(apm.on, apm.off);
  const bulbsOn = K.glow(game, '#FFC98A', 2.2);
  rt.warmMat(bulbsOn);
  const apBulbs = applause.userData.parts.bulbs;
  const apBulbOff = [];
  apBulbs.traverse((o) => { if (o.isMesh) apBulbOff.push([o, o.material]); });
  rt.anchor('sa_applause', { pos: [ap.pos[0], ap.pos[1], ap.pos[2] - 1.2], color: '#FF5A3C', intensity: 0, distance: 7 });
  const apState = { lit: false };
  O.ee_applause_sign = {
    group: applause, parts: applause.userData.parts, get lit() { return apState.lit; },
    setLit(on) {
      apState.lit = !!on;
      setLamp(applause, on ? 'on' : 'off');
      for (const [o, m] of apBulbOff) o.material = on ? bulbsOn : m;
      rt.setAnchor('sa_applause', { intensity: on ? 2.2 : 0 });
    },
  };
  rt.onReset(() => O.ee_applause_sign.setLit(false));

  // ---------------------------------------------------------------------------------------------- disco ball
  const disco = P('disco_ball', { pos: [4, GRID_Y - 1.39, -21], colliders: false });
  disco.userData.noMerge = false;
  const ball = disco.userData.parts.ball;
  dyn.attach(ball);
  O.disco_ball = { group: disco, parts: { ball } };
  // specks: a rotating floor disc + a sliding band on the walls (additive), after power
  const speckTex = discoSpeckTexture();
  const floorTex = speckTex.clone(); floorTex.needsUpdate = true;
  floorTex.wrapS = floorTex.wrapT = THREE.RepeatWrapping; floorTex.repeat.set(3, 3);
  const wallTex = speckTex.clone(); wallTex.needsUpdate = true;
  wallTex.wrapS = wallTex.wrapT = THREE.RepeatWrapping; wallTex.repeat.set(10, 1.4);
  const speckMat = (tex, k) => new THREE.MeshBasicMaterial({ map: tex, color: new THREE.Color(k, k * 0.92, k * 1.05), blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, fog: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
  const specksFloor = new THREE.Mesh(new THREE.CircleGeometry(8.5, 48).rotateX(-HP), speckMat(floorTex, 0.55));
  specksFloor.position.set(4, 0.025, -21);
  const wallGeo = [];
  const [x0, z0, x1, z1] = area.rect;
  // The band skips door openings (D4, D6): across an opening it sat right in front of a camera standing in the
  // doorway and showed as big soft white blobs over the whole view. Above the door head it continues.
  const BAND_Y0 = 1.3, BAND_Y1 = 5.5;
  const doorsHere = DOORS.filter((d) => d.areas.includes(area.id || 'studio_a'));
  const piece = (ax, az, bx, bz, len, s0, s1, y0, y1) => {
    const w = s1 - s0, hgt = y1 - y0;
    if (w < 0.05 || hgt < 0.05) return;
    const q = new THREE.PlaneGeometry(w, hgt);
    q.rotateY(Math.atan2(-(bz - az), bx - ax));
    const t = (s0 + s1) / 2 / len;
    q.translate(ax + (bx - ax) * t, (y0 + y1) / 2, az + (bz - az) * t);
    const uv = q.attributes.uv;
    for (let i = 0; i < uv.count; i++) {
      uv.setX(i, (s0 + uv.getX(i) * w) / 22);
      uv.setY(i, (y0 - BAND_Y0 + uv.getY(i) * hgt) / (BAND_Y1 - BAND_Y0));
    }
    wallGeo.push(q);
  };
  for (const [ax, az, bx, bz] of [[x0 + 0.16, z1 - 0.16, x0 + 0.16, z0 + 0.16], [x0 + 0.16, z0 + 0.16, x1 - 0.16, z0 + 0.16], [x1 - 0.16, z0 + 0.16, x1 - 0.16, z1 - 0.16], [x1 - 0.16, z1 - 0.16, x0 + 0.16, z1 - 0.16]]) {
    const len = Math.hypot(bx - ax, bz - az);
    const alongX = Math.abs(bx - ax) > Math.abs(bz - az);
    const wallAt = alongX ? az : ax;
    // door spans on this wall, as distances s from (ax, az)
    const cuts = [];
    for (const d of doorsHere) {
      const [axis, at] = d.line;
      if ((axis === 'z') !== alongX || Math.abs(at - wallAt) > 0.6) continue;
      const a = alongX ? (d.span[0] - ax) / (bx - ax) * len : (d.span[0] - az) / (bz - az) * len;
      const b = alongX ? (d.span[1] - ax) / (bx - ax) * len : (d.span[1] - az) / (bz - az) * len;
      cuts.push([Math.max(0, Math.min(a, b) - 0.15), Math.min(len, Math.max(a, b) + 0.15), d.height + 0.15]);
    }
    cuts.sort((m, n) => m[0] - n[0]);
    let sPos = 0;
    for (const [c0, c1, top] of cuts) {
      piece(ax, az, bx, bz, len, sPos, c0, BAND_Y0, BAND_Y1);
      piece(ax, az, bx, bz, len, c0, c1, Math.max(BAND_Y0, top), BAND_Y1);
      sPos = c1;
    }
    piece(ax, az, bx, bz, len, sPos, len, BAND_Y0, BAND_Y1);
  }
  const specksWall = new THREE.Mesh(mergeGeometries(wallGeo), speckMat(wallTex, 0.4));
  specksWall.material.side = THREE.DoubleSide;
  for (const s of [specksFloor, specksWall]) { s.visible = false; s.renderOrder = 2; dyn.add(s); }
  rt.onPower([4, 3, -21], (on) => { specksFloor.visible = specksWall.visible = on; });
  rt.onTick((t, dt, vis) => {
    if (!rt.powered || !vis) return;
    ball.rotation.y += dt * 0.7;
    specksFloor.rotation.y -= dt * 0.12;
    wallTex.offset.x = (wallTex.offset.x + dt * 0.012) % 1;
  });

  // ---------------------------------------------------------------------------------------------- lighting grid
  const lensGroup = new THREE.Group();
  lensGroup.userData.noMerge = true;
  dyn.add(lensGroup);
  const lights = [];
  // warm Fresnels over the stage front (pipe z -25.8), gel spots on the pipe z -23.4
  for (const x of [-2.0, 1.0, 7.0, 10.0]) {
    const f = P('bc_light_fresnel', { pos: [x, 0, -25.8], opts: { gel: 'tungsten', tilt: 1.05, lit: false }, colliders: false });
    f.position.y = GRID_Y - f.userData.hang.pipeY;
    lights.push(f);
  }
  const gels = [['magenta', PAL.gelMagenta, -0.6], ['amber', PAL.gelAmber, 4.0], ['cyan', PAL.gelCyan, 8.6]];
  const gelProps = gels.map(([gel, , x]) => {
    const f = P('bc_light_fresnel', { pos: [x, 0, -23.4], opts: { gel, tilt: 0.9, lit: false }, colliders: false });
    f.position.y = GRID_Y - f.userData.hang.pipeY;
    lights.push(f);
    return f;
  });
  // extra hardware: battens, clamps with dangling safety loops
  for (const [x, z, len] of [[4, -28.2, 6], [-2.5, -16.2, 4], [10.5, -16.2, 4]]) {
    const b = P('bc_grid_batten', { pos: [x, 0, z], opts: { len }, colliders: false });
    b.position.y = GRID_Y - b.userData.hang.pipeY;
  }
  for (const [x, z] of [[-5.2, -18.6], [1.7, -13.8], [13.2, -21], [-0.6, -28.2]]) {
    const c = P('bc_grid_clamp', { pos: [x, 0, z], colliders: false });
    c.position.y = GRID_Y - c.userData.hang.pipeY;
  }
  for (const f of lights) { f.updateMatrixWorld(true); unlockParts(f, ['head']); }
  harvestLenses(lights, lensGroup);
  const lampOn = lights[0].userData.lampMats.on, lampOff = lights[0].userData.lampMats.off;
  rt.warmMat(lampOn, lampOff);
  rt.onPower([4, 6, -24], (on) => { lensGroup.traverse((o) => { if (o.isMesh) o.material = on ? lampOn : lampOff; }); });

  // gel beams (after power): additive cones from the gel Fresnels sweeping across the stage, with moving light pools
  const beams = gels.map(([, color, x], i) => {
    const f = gelProps[i];
    f.updateMatrixWorld(true);
    const lens = new THREE.Vector3().fromArray(f.userData.aim.pos).applyMatrix4(f.matrixWorld);
    const geo = new THREE.CylinderGeometry(0.9, 0.12, 1, 20, 1, true).translate(0, 0.5, 0).rotateX(HP);
    const mat = M.beam.clone();
    mat.uniforms.uColor.value.set(color);
    mat.uniforms.uI.value = 0.22;
    const m = new THREE.Mesh(geo, mat);
    m.position.copy(lens);
    m.visible = false;
    m.renderOrder = 3;
    m.frustumCulled = false;
    dyn.add(m);
    const pool = rt.pool([x, 0.62, -27.5], 1.5, color, 0);
    return { m, pool, lens, color, ph: i * 2.1, x };
  });
  const tgt = new THREE.Vector3();
  const aimBeam = (b, t) => {
    const cx = 4 + 5.4 * Math.sin(t * 0.33 + b.ph) + (b.x - 4) * 0.25;
    const cz = -27.7 + 1.2 * Math.sin(t * 0.21 + b.ph * 1.7);
    tgt.set(cx, 0.6, cz);
    const len = b.lens.distanceTo(tgt);
    b.m.lookAt(tgt);
    b.m.scale.set(1, 1, len);
    b.pool.set({ pos: tgt.setY(0.62) });
  };
  rt.onPower([4, 6, -23.4], (on) => { for (const b of beams) { b.m.visible = on; b.pool.set({ intensity: on ? 0.28 : 0 }); } });
  rt.onTick((t, dt, vis) => { if (rt.powered && vis) for (const b of beams) aimBeam(b, t); });
  for (const b of beams) aimBeam(b, 0);
  // gel wash anchors (after power)
  rt.anchor('sa_gel_w', { pos: [0.5, 3.2, -27.2], color: PAL.gelMagenta, intensity: 0, distance: 9 });
  rt.anchor('sa_gel_e', { pos: [8.5, 3.2, -27.2], color: PAL.gelCyan, intensity: 0, distance: 9 });
  rt.onPower([4, 3, -27], (on) => {
    rt.setAnchor('sa_gel_w', { intensity: on ? 2.6 : 0 });
    rt.setAnchor('sa_gel_e', { intensity: on ? 2.6 : 0 });
  });

  // hanging bats over the audience + the carousel
  const rb = mulberry(77);
  for (let i = 0; i < 14; i++) {
    const x = -5 + rb() * 18, z = -27 + rb() * 12, y = 4.6 + rb() * 1.2;
    if (Math.hypot(x - 4, z + 21) < 1.2) continue;
    const s = 1.4 + rb() * 1.2;
    const b = bat(game, s);
    b.add(stringTo(studioMats(game), 0, 0.02 * s, 0, GRID_Y - y));
    P(null, { group: b, pos: [x, y, z], rotY: rb() * TAU, colliders: false }).rotation.z = (rb() - 0.5) * 0.4;
  }
  // hanging telethon banner ("operators are standing by") over the east aisle
  P(null, { group: banner(game, A, 'operators', 6.4, 0.75, { hang: GRID_Y - 4.9 - 0.375, color: '#1B2F7A' }), pos: [9.9, 4.9, -18.6], rotY: Math.PI, colliders: false });

  // ---------------------------------------------------------------------------------------------- walls
  const W = { w: x0 + 0.155, e: x1 - 0.155, n: z0 + 0.155, s: z1 - 0.155 };
  P(null, { group: banner(game, A, 'pledge', 9.2, 1.08, { color: '#E23B3B' }), pos: [W.w + 0.03, 4.6, -21], rotY: -HP, colliders: false });
  P(null, { group: banner(game, A, 'thanks', 7.2, 0.84, { color: '#5A2A22' }), pos: [-2.5, 4.35, W.s - 0.03], rotY: Math.PI, colliders: false });
  P(null, { group: banner(game, A, 'goal', 5.4, 1.24, { color: '#1B2F7A' }), pos: [10.5, 4.45, W.s - 0.03], rotY: Math.PI, colliders: false });
  P(null, { group: banner(game, A, 'studio', 2.6, 1.26, { color: '#2A1D2A' }), pos: [W.e - 0.03, 4.6, -25.2], rotY: HP, colliders: false });
  P(null, { group: banner(game, A, 'quiet', 1.5, 0.46, { color: '#2A1D2A' }), pos: [W.e - 0.03, 3.7, -23.1], rotY: HP, colliders: false });
  // posters at eye level (framed, lacquer frames)
  for (const [reg, pos, rot] of [['poster1', [W.w + 0.03, 1.55, -27.6], -HP], ['poster2', [W.e - 0.03, 1.6, -24.2], HP], ['poster3', [W.w + 0.03, 1.55, -15.2], -HP]]) {
    P(null, { group: banner(game, A, reg, 0.78, 1.04, { color: PAL.harvestGold }), pos, rotY: rot, colliders: false });
  }

  // ---------------------------------------------------------------------------------------------- floor gear
  // feed camera (camera 1) + its stand monitor; a parked camera 2 aimed at the stage; boom mic; lights; cases
  feedCamera(game, rt, root, 'feed_cam_studio_a', { num: 1, side: 1.1 });
  standMonitor(game, rt, root, 'mon_studio_a_stand');
  const cam2 = P('bc_pedestal_camera', { pos: [11.2, 0, -23.2], rotY: yawTo([11.2, 0, -23.2], [4, 0, -28.2]), opts: { num: 2, tally: false } });
  unlockParts(cam2);
  const boom = P('bc_boom_mic', { pos: [-4.45, 0, -25.95], rotY: yawTo([-4.45, 0, -25.95], [-1.2, 0, -28.6]), opts: { reach: 2.6, raise: 0.1, micTilt: 0.35 } });
  unlockParts(boom);
  const tri = P('bc_light_tripod', { pos: [-3.85, 0, -29.3], rotY: yawTo([-3.85, 0, -29.3], [1.5, 0, -27.8]), opts: { gel: 'amber', height: 1.7, tilt: 0.12, lit: false, anchor: false } });
  const soft = P('bc_light_softbox', { pos: [13.9, 0, -24.6], rotY: yawTo([13.9, 0, -24.6], [8, 0, -27.5]), opts: { lit: false, height: 1.25 } });
  for (const g of [tri, soft]) unlockParts(g, ['head']);
  harvestLenses([tri, soft], lensGroup);
  const softOn = soft.userData.lampMats.on;
  rt.warmMat(softOn);
  rt.onPower([13.9, 1, -24.6], (on) => { lensGroup.traverse((o) => { if (o.isMesh && o.userData._soft) o.material = on ? softOn : lampOff; }); });
  lensGroup.children.at(-1).userData._soft = true;
  for (const g of [tri, soft]) for (const [dx, dz] of [[0.3, 0.2], [-0.25, -0.28]]) P(null, { group: sandbag(game), pos: [g.position.x + dx, 0, g.position.z + dz], rotY: dx * 5, colliders: false });
  P('bc_flight_case_stack', { pos: [-6.35, 0, -26.9], rotY: HP + 0.08 });
  P('bc_flight_case', { pos: [-6.3, 0, -29.35], rotY: HP - 0.2, opts: { size: 'tall', color: '#2E2934' } });
  P('bc_flight_case', { pos: [-5.35, 0, -29.55], rotY: 0.1, opts: { size: 'md', color: '#7A2A26' } });
  P('bc_clapperboard', { pos: [-6.4, 1.56, -26.75], rotY: -1.1, colliders: false });
  P('yd_film_cans', { pos: [-4.55, 0, -29.55], rotY: 0.5, opts: { seed: 3 } });
  P('bc_cable_coil', { pos: [-4.4, 0, -28.1], rotY: 2.1 });
  P('bc_cable_coil', { pos: [13.8, 0, -22.4], rotY: -0.8, opts: { color: 'wztvBlue' } });
  P('bc_cable_spaghetti', { pos: [-3.9, 0, -16.6], rotY: 0.35, opts: { w: 3.6, d: 0.9, count: 4, seed: 3 } });
  P('bc_cable_spaghetti', { pos: [2.0, 0, -25.05], rotY: 0.02, opts: { w: 6.2, d: 0.55, count: 5, seed: 8 } });
  P('bc_cable_spaghetti', { pos: [12.0, 0, -21.9], rotY: 1.2, opts: { w: 2.6, d: 0.8, count: 3, seed: 5 } });
  P('bc_headphones_hook', { pos: [W.e, 1.2, -25.9], rotY: HP, colliders: false });

  // ---------------------------------------------------------------------------------------------- light pools
  rt.pool([4, 0.62, -28.0], 4.2, '#FF6FB0', 0);
  const stagePools = [rt.pool([1.5, 0.62, -27.8], 3.2, '#FF5FA2', 0), rt.pool([7.8, 0.62, -27.8], 3.0, '#5FE3FF', 0)];
  const monPools = [rt.pool([-5.3, 0.02, -28.3], 1.3, PAL.crtCyan, 0.08), rt.pool([1.2, 0.02, -16.4], 1.1, PAL.crtCyan, 0.06)];
  const pumpkinPools = [rt.pool([-2.3, 0.62, -26.2], 0.9, '#FFB347', 0.12), rt.pool([-6.0, 0.02, -25.4], 0.9, '#FFB347', 0.1)];
  void monPools; void pumpkinPools;
  rt.onPower([4, 1, -27], (on) => { stagePools.forEach((p) => p.set({ intensity: on ? 0.13 : 0 })); });

  shadowHygiene(root);

  // expose a tiny debug helper for the harness
  O.studio_a = { rt, root, dyn };
}

// Parts the level will not merge (under a noMerge / dynamic node) each cost a shadow draw: unlit glow (bulbs,
// candle faces) and parts under ~0.3 m never cast (ARCHITECTURE §5). Mergeable meshes are left alone (their
// castShadow is part of the merge key). ~20 fewer shadow draws in the studio.
function shadowHygiene(root) {
  root.updateMatrixWorld(true);
  const s = new THREE.Vector3();
  const walk = (o, unmerged) => {
    const um = unmerged || !!(o.userData.noMerge || o.userData.dynamic);
    if (um && o.isMesh && o.castShadow && o.geometry) {
      const g = o.geometry;
      if (!g.boundingSphere) g.computeBoundingSphere();
      o.getWorldScale(s);
      const r = g.boundingSphere.radius * Math.max(s.x, s.y, s.z);
      const m = Array.isArray(o.material) ? o.material[0] : o.material;
      const small = r < 0.3 && !o.isInstancedMesh; // an instanced base geometry says nothing about the spread
      if (small || (m && (m.type === 'MeshBasicMaterial' || m.type === 'ShaderMaterial'))) o.castShadow = false;
    }
    for (const c of o.children) walk(c, um);
  };
  walk(root, false);
}
