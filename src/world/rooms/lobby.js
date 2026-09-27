// Room dressing: LOBBY & RECEPTION (GDD §5.7 "Lobby", §3.3 lighting, §2 story props, §13 toys + step-1 objects,
// §18.13 ids). Owner: rooms-lobby-green (this file also exports the small room kit green_room.js uses).
//
// build(game, area, root) — called by level.js after the graybox (the level merges static meshes afterwards).
//
// game.level.objects entries registered here (world space, all Object3Ds live under the lobby area root):
//   ee_chime_rack  { group, parts:{ ee_bar_red, ee_bar_yellow, ee_bar_green, ee_bar_blue } (pivot Groups, swing =
//                    rotation.x), bars:{ red|yellow|green|blue: { part, note, hz, len, top():Vector3, bottom():Vector3 } },
//                    swing(color, strength=1, dir?:Vector3), raycast(origin, dir, maxDist, color?) → { color, dist,
//                    point } | null (capsule r 0.055 per bar, first hit), ring(color) (swing + no sound) }
//   ee_trophy_case { group, parts:{ door }, dudley:Vector3 (empty middle-shelf spot), dropPoint:Vector3,
//                    setOpen(open, instant=false) }
//   neon_logo      { group, parts:{ W, Z, T, V, 13 } (tube meshes), state 'dark'|'broken'|'lit', setState(state),
//                    setLetter(key, level 0..1), fix() (stutter Z+T back to full glow, 'ee_neon_stutter') }
//                    Automatic: dark before power, 'broken' (W V 13 lit, Z T dead + buzzing) when the color wave
//                    reaches it, fix() on egg:step >= 1. Idempotent, so the EE may also call it.
//   booth_on_air   { group, set(on) }   (lights permanently on egg:step >= 1)
//   letter_board   { group, parts:{ face }, letters:[Mesh] (fallen SIGN OFF letters), signOff(on) } (on egg:complete)
//   lobby_clock    { group, parts:{ hour, minute, second }, setMidnight(on) }  (11:59, second hand twitching :58↔:59;
//                    egg:complete → ticks to 12:00 and plays the station motif)
//   reception_desk { group, parts:{ bell, magazine } }    exhibit_camera { group, parts, setTally(on) }
//   mon_lobby_exhibit / mon_lobby_booth { group, screen } (screens registered as scr_feed_lobby)
// Toys (GDD §13): toy_desk_bell ('toy_bell', bell squash-hop), toy_exhibit_camera ('toy_camera_zoom', tally toggle +
//   head nod; asks game.screens.zoomFeed?.('lobby', 5) and emits 'toy:exhibit_zoom' {area:'lobby', seconds:5}).
//   All toys use a key-only prompt (prompt() → {}). Every toy emits 'toy:use' {id}.
//
// Room kit (exported for green_room.js): roomKit(game, area, root) → kit with place(id, pos, rotY, opts, o),
//   put(group, pos, rotY, o), anchor({...pre, post}), pool(pos, r, color, pre, post), onPower(pos, apply(on, instant)),
//   glowSwap(mesh, onMat, offMat), toy(id, pos, use, radius), obj(id, fields), sound(id, pos), hook(mesh),
//   mergeInto(meshes, material, name), ticks[] (fn(dt, t, realDt)), resets[] (fn on game:start).
//   Power: every onPower entry switches when the Sign-On color wave (15 m/s from the lever) reaches it, with the
//   level's 3-flash flicker; a new game with the power off switches everything back instantly.
//   Local builders: ATLAS (shared 1024² decal atlas), cellPlane(), decal(), velvetRopes(), wallShelf(), exitSign().

import * as THREE from 'three';
import { buildProp } from '../../props/index.js';
import * as K from '../../props/kit.js';
import { setNeon } from '../../props/sets.js';
import { setLamp } from '../../props/broadcast.js';
import { ANCHORS } from '../layout.js';
import { PAL } from '../../core/config.js';

const PI = Math.PI;
const TAU = PI * 2;
const LEVER = new THREE.Vector3(29, 1, -7.6);
const WAVE = 15;
const FLICKER = [[0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]];
const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _bb = new THREE.Box3();
const _m4 = new THREE.Matrix4();
const v3 = (p) => (p && p.isVector3 ? p.clone() : new THREE.Vector3(p[0], p[1] ?? 0, p[2]));
const hash = (n) => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };

// =========================================================================================================== kit
export function roomKit(game, area, root) {
  const level = game.level;
  if (!level.objects) level.objects = {};
  const aid = area.id;
  const ticks = [];
  const switches = [];
  const resets = [];
  let uid = 0;
  let powerT0 = -1;
  let pending = false;
  let warned = false;
  const now = () => game.time?.realNow ?? performance.now() / 1000;
  const kit = { game, area, root, ticks, switches, resets, powered: false, t: 0 };

  // Positions a built group, registers its colliders / light anchors / screens (placeProp semantics + scale,
  // tilt, anchor power modes, screen ids).
  kit.put = (g, pos, rotY = 0, o = {}) => {
    g.position.set(pos[0], pos[1] ?? 0, pos[2]);
    g.rotation.set(o.tilt?.[0] ?? 0, rotY, o.tilt?.[1] ?? 0);
    if (o.scale) {
      if (typeof o.scale === 'number') g.scale.setScalar(o.scale); else g.scale.set(o.scale[0], o.scale[1], o.scale[2]);
    }
    (o.parent || root).add(g);
    g.updateMatrixWorld(true);
    const u = g.userData;
    if (o.colliders !== false && level.col) {
      for (const c of (o.boxes || u.colliders || [])) {
        _bb.makeEmpty();
        for (let i = 0; i < 8; i++) {
          _v.set(i & 1 ? c.max[0] : c.min[0], i & 2 ? c.max[1] : c.min[1], i & 4 ? c.max[2] : c.min[2]).applyMatrix4(g.matrixWorld);
          _bb.expandByPoint(_v);
        }
        level.col.addBox(_bb.min.toArray(), _bb.max.toArray(), { tag: o.tag || 'prop', ...(c.opts || {}) });
      }
    }
    u.anchorIds = [];
    if (o.lights !== false) {
      for (const a of u.lightAnchors || []) {
        _v.fromArray(a.pos).applyMatrix4(g.matrixWorld);
        u.anchorIds.push(kit.anchor({
          pos: _v.toArray(), color: a.color, intensity: (a.intensity ?? 1.5) * (o.lightMul ?? 1), distance: a.distance,
          flicker: a.flicker, pre: o.pre ?? 1, post: o.post ?? 1,
        }));
      }
    }
    if (o.screens !== false && game.screens?.register) {
      (u.screens || []).forEach((s, i) => {
        const id = o.screenIds?.[i] || s.id;
        game.screens.register(s.mesh, o.screenGroup || s.group || 'scr_decor', id ? { id } : {});
      });
    }
    if (o.noMerge) u.noMerge = true;
    return g;
  };

  kit.place = (id, pos, rotY = 0, opts = {}, o = {}) => {
    let g;
    try {
      g = buildProp(id, game, opts);
    } catch (err) {
      console.warn(`[rooms:${aid}] prop "${id}" failed`, err);
      return null;
    }
    return kit.put(g, pos, rotY, o);
  };

  // Pooled light anchor with power states: intensity × pre before Sign-On, × post after.
  kit.anchor = ({ pos, color = PAL.tungsten, intensity = 1.5, distance = 5, flicker = 0, pre = 1, post = 1, id = null }) => {
    const aidStr = id || `${aid}_dress_${++uid}`;
    const L = game.lights;
    if (!L?.addAnchor) return aidStr;
    const p = Array.isArray(pos) ? pos : pos.toArray();
    L.addAnchor({ id: aidStr, pos: p, color, intensity: intensity * pre, distance, area: aid, flicker: typeof flicker === 'number' ? flicker : flicker ? 0.5 : 0 });
    if (pre !== post) kit.onPower(p, (on) => L.setAnchor(aidStr, { intensity: intensity * (on ? post : pre) }));
    return aidStr;
  };

  // Additive floor light pool (fx.lightPool) with power states.
  kit.pool = (pos, radius, color, pre, post = pre) => {
    const h = game.fx?.lightPool?.(v3(pos), radius, color, pre);
    if (!h) return null;
    if (pre !== post) kit.onPower(pos, (on) => h.set({ intensity: on ? post : pre }));
    return h;
  };

  kit.onPower = (pos, apply) => {
    const p = v3(pos);
    switches.push({ pos: p, delay: LEVER.distanceTo(p) / WAVE, apply, state: false, done: true });
  };

  kit.glowSwap = (mesh, onMat, offMat, pos = null) => {
    if (!mesh) return;
    mesh.updateMatrixWorld(true);
    const p = pos || mesh.getWorldPosition(new THREE.Vector3());
    mesh.material = offMat;
    kit.onPower(p, (on) => { mesh.material = on ? onMat : offMat; });
  };

  kit.toy = (id, pos, use, radius = 1.5) => {
    if (!game.interact?.register) return null;
    return game.interact.register({
      id, pos: v3(pos), radius, prompt: () => ({}),
      use: () => {
        try { use(); } catch (err) { console.warn(`[rooms:${aid}] toy ${id}`, err); }
        game.events?.emit?.('toy:use', { id });
      },
    });
  };

  kit.obj = (id, fields) => (level.objects[id] = { id, area: aid, ...fields });
  kit.sound = (id, pos, o = {}) => game.audio?.play?.(id, { pos: v3(pos), ...o });

  // Merges static meshes (possibly under different props) into one noMerge mesh (one draw call) whose material
  // can be swapped at runtime (bulb rings, globes). Attributes are normalized (position, normal, uv, color).
  kit.mergeInto = (meshes, material, name = 'merged_parts') => {
    root.updateMatrixWorld(true);
    const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
    const geos = [];
    for (const m of meshes) {
      if (!m) continue;
      m.updateMatrixWorld(true);
      let g = m.geometry.index ? m.geometry.toNonIndexed() : m.geometry.clone();
      const n = g.attributes.position.count;
      const out = new THREE.BufferGeometry();
      out.setAttribute('position', g.attributes.position);
      if (!g.attributes.normal) g.computeVertexNormals();
      out.setAttribute('normal', g.attributes.normal);
      out.setAttribute('uv', g.attributes.uv || new THREE.BufferAttribute(new Float32Array(n * 2), 2));
      out.setAttribute('color', g.attributes.color || new THREE.BufferAttribute(new Float32Array(n * 3).fill(1), 3));
      _m4.multiplyMatrices(inv, m.matrixWorld);
      out.applyMatrix4(_m4);
      geos.push(out);
      m.parent?.remove(m);
    }
    if (!geos.length) return null;
    const merged = mergeGeos(geos);
    const mesh = new THREE.Mesh(merged, material);
    mesh.name = name;
    mesh.userData.noMerge = true;
    mesh.castShadow = false;
    mesh.receiveShadow = false;
    root.add(mesh);
    return mesh;
  };

  // Frame hook: the room's per-frame work runs from the onBeforeRender of one always-drawn mesh of the room
  // (rooms have no update() in the level contract), i.e. only while the area is rendered, once per frame.
  kit.hook = (mesh) => {
    if (!mesh) return;
    mesh.frustumCulled = false;
    let last = -1;
    mesh.onBeforeRender = () => {
      const f = game.time?.frame ?? 0;
      if (f === last) return;
      last = f;
      run();
    };
  };

  function setAll(on) {
    for (const s of switches) {
      try { s.apply(on, true); } catch (err) { if (!warned) { warned = true; console.warn(`[rooms:${aid}] power`, err); } }
      s.state = on;
      s.done = true;
    }
    pending = false;
    kit.powered = on;
  }

  function powerStep() {
    const powerOn = !!game.machines?.powerOn;
    if (!powerOn && kit.powered) { setAll(false); return; }
    if (!pending) return;
    const el = now() - powerT0;
    let busy = false;
    for (const s of switches) {
      if (s.done) continue;
      const t = el - s.delay;
      if (t < 0) { busy = true; continue; }
      let on = true;
      if (t < 1.2) for (const [t0, val] of FLICKER) if (t >= t0) on = val;   // overdue: switch without flicker
      if (on !== s.state) {
        try { s.apply(on, false); } catch (err) { if (!warned) { warned = true; console.warn(`[rooms:${aid}] power`, err); } }
        s.state = on;
      }
      if (t >= FLICKER[FLICKER.length - 1][0]) s.done = true; else busy = true;
    }
    pending = busy;
  }

  function run() {
    const dt = Math.min(0.05, game.time?.dt ?? 0);
    const rdt = Math.min(0.05, game.time?.realDt ?? 0);
    kit.t += dt;
    powerStep();
    for (const fn of ticks) {
      try { fn(dt, kit.t, rdt); } catch (err) { if (!warned) { warned = true; console.warn(`[rooms:${aid}] tick`, err); } }
    }
  }

  game.events?.on?.('power:on', () => {
    powerT0 = now();
    pending = true;
    kit.powered = true;
    for (const s of switches) s.done = false;
  });
  game.events?.on?.('game:start', () => {
    if (!game.machines?.powerOn) setAll(false);
    for (const fn of resets) { try { fn(); } catch (err) { console.warn(`[rooms:${aid}] reset`, err); } }
  });
  return kit;
}

function mergeGeos(geos) {
  let total = 0;
  for (const g of geos) total += g.attributes.position.count;
  const out = new THREE.BufferGeometry();
  for (const [name, size] of [['position', 3], ['normal', 3], ['uv', 2], ['color', 3]]) {
    const arr = new Float32Array(total * size);
    let off = 0;
    for (const g of geos) { arr.set(g.attributes[name].array, off); off += g.attributes[name].array.length; }
    out.setAttribute(name, new THREE.BufferAttribute(arr, size));
  }
  out.computeBoundingSphere();
  out.computeBoundingBox();
  return out;
}

// ====================================================================================================== atlas
// One shared 1024² decal atlas (8×8 cells of 128 px) for every small printed thing of the lobby + green room:
// fallen letters, papers, signs, plaques, the doormat, glass lettering (one material → one draw call).
export const CELLS = {
  S: [0, 0], I: [1, 0], G: [2, 0], N: [3, 0], O: [4, 0], F: [5, 0], exit: [6, 0, 2, 1],
  script: [0, 1], pledge: [1, 1], memo: [2, 1], polaroid: [3, 1], paper: [4, 1, 2, 1], ticket: [6, 1], star: [7, 1],
  mat: [0, 2, 4, 2], plaque: [4, 2, 4, 1], glassAnnounce: [4, 3, 4, 1],
  makeup: [0, 4, 4, 1], callboard: [4, 4, 4, 1], quiet: [0, 5, 4, 1], towel: [4, 5, 2, 1], cue: [6, 5, 2, 1],
  script2: [0, 6], cup: [1, 6], boa: [2, 6], cucumber: [3, 6], fan: [4, 6], wig: [5, 6], sheet: [6, 6], sheet2: [7, 6],
};
const FONT_SIGN = '"Bungee", Impact, "Arial Black", sans-serif';
const FONT_ROUND = '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif';
const FONT_TYPE = '"Courier New", Courier, monospace';
const FONT_GROOVY = '"Shrikhand", "Cooper Black", Georgia, serif';

function atlasTex() {
  return K.tex.canvas('rooms.lg.atlas.v1', 1024, 1024, (ctx, W, H, rand) => {
    ctx.clearRect(0, 0, W, H);
    const C = 128;
    const at = (name) => { const c = CELLS[name]; return [c[0] * C, c[1] * C, (c[2] ?? 1) * C, (c[3] ?? 1) * C]; };
    const rr = (x, y, w, h, r) => { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); };
    const text = (s, x, y, size, font, fill, o = {}) => {
      ctx.save();
      ctx.font = `${size}px ${font}`;
      if (o.max) { let sz = size; while (ctx.measureText(s).width > o.max && sz > 6) { sz *= 0.93; ctx.font = `${sz}px ${font}`; } }
      ctx.textAlign = o.align || 'center'; ctx.textBaseline = 'middle';
      if (o.shadow) { ctx.fillStyle = o.shadow; ctx.fillText(s, x + size * 0.05, y + size * 0.07); }
      if (o.stroke) { ctx.lineWidth = o.lw || size * 0.12; ctx.strokeStyle = o.stroke; ctx.lineJoin = 'round'; ctx.strokeText(s, x, y); }
      ctx.fillStyle = fill; ctx.fillText(s, x, y);
      ctx.restore();
    };
    // fallen changeable letters: white molded plastic with a soft shadow edge
    for (const L of ['S', 'I', 'G', 'N', 'O', 'F']) {
      const [x, y] = at(L);
      text(L, x + 64, y + 68, 110, FONT_SIGN, '#F7F2E6', { stroke: '#8C7F6A', lw: 8, shadow: 'rgba(40,24,40,0.55)' });
    }
    // EXIT face
    { const [x, y, w, h] = at('exit');
      ctx.fillStyle = '#5A0F12'; ctx.fillRect(x, y, w, h);
      rr(x + 8, y + 8, w - 16, h - 16, 14); ctx.fillStyle = '#7A1418'; ctx.fill();
      text('EXIT', x + w / 2, y + h / 2 + 4, 86, FONT_SIGN, '#FFE0D0', { stroke: '#FF4A30', lw: 10 }); }
    // papers
    const paper = (name, bg, lines, header, hc) => {
      const [x, y, w, h] = at(name);
      rr(x + 6, y + 4, w - 12, h - 8, 4); ctx.fillStyle = bg; ctx.fill();
      if (header) text(header, x + w / 2, y + 20, 15, FONT_SIGN, hc || '#5A3A22', { max: w - 24 });
      ctx.fillStyle = 'rgba(60,40,50,0.55)';
      for (let i = 0; i < lines; i++) ctx.fillRect(x + 16, y + 36 + i * 11, (w - 32) * (0.55 + rand() * 0.45), 3);
    };
    paper('script', '#F6F0E0', 8, 'SPOOKTACULAR', '#B5472A');
    paper('script2', '#FFF8E8', 8, 'RUNDOWN', '#2F5BD3');
    paper('sheet', '#F2ECDC', 9, 'CALL SHEET', '#5A3A22');
    paper('sheet2', '#EDF2E0', 9, 'PLEDGES', '#2E8C8C');
    paper('memo', '#FFE680', 5, 'MEMO', '#7A4A2A');
    { const [x, y, w, h] = at('pledge');
      rr(x + 8, y + 18, w - 16, h - 36, 6); ctx.fillStyle = '#FFB6C8'; ctx.fill();
      text('PLEDGE', x + w / 2, y + 40, 22, FONT_SIGN, '#8E2A2E');
      text('$13', x + w / 2, y + 74, 34, FONT_ROUND, '#E23B3B');
      ctx.fillStyle = 'rgba(90,40,60,0.5)'; ctx.fillRect(x + 22, y + 96, w - 44, 3); }
    { const [x, y, w, h] = at('polaroid');
      rr(x + 14, y + 8, w - 28, h - 16, 3); ctx.fillStyle = '#FBF8F1'; ctx.fill();
      const g = ctx.createLinearGradient(0, y + 16, 0, y + 90); g.addColorStop(0, '#6B3A6E'); g.addColorStop(1, '#E3662B');
      ctx.fillStyle = g; ctx.fillRect(x + 22, y + 16, w - 44, 76);
      ctx.fillStyle = '#F6E7C8'; ctx.beginPath(); ctx.arc(x + 64, y + 50, 16, 0, TAU); ctx.fill(); }
    { const [x, y, w, h] = at('paper');
      ctx.fillStyle = '#EDE6D2'; ctx.fillRect(x + 4, y + 6, w - 8, h - 12);
      text('THE TRI-COUNTY TRIBUNE', x + w / 2, y + 22, 16, FONT_GROOVY, '#2A2231', { max: w - 20 });
      ctx.fillStyle = '#2A2231'; ctx.fillRect(x + 10, y + 34, w - 20, 2);
      text('TELETHON $13 SHORT!', x + w / 2, y + 52, 20, FONT_SIGN, '#2A2231', { max: w - 24 });
      ctx.fillStyle = '#9A9284'; ctx.fillRect(x + 12, y + 66, 70, 48);
      ctx.fillStyle = 'rgba(40,30,40,0.45)';
      for (let i = 0; i < 7; i++) ctx.fillRect(x + 92, y + 68 + i * 7, w - 106, 3); }
    { const [x, y, w, h] = at('ticket');
      rr(x + 8, y + 36, w - 16, h - 72, 6); ctx.fillStyle = '#F4E03A'; ctx.fill();
      text('ADMIT ONE', x + w / 2, y + 56, 16, FONT_SIGN, '#8E2A2E');
      text('WZTV 13', x + w / 2, y + 76, 14, FONT_ROUND, '#2F5BD3'); }
    { const [x, y] = at('star');
      ctx.fillStyle = '#FFC23A'; ctx.strokeStyle = '#A8701A'; ctx.lineWidth = 5; ctx.beginPath();
      for (let i = 0; i < 10; i++) { const a = -PI / 2 + i * PI / 5, r = i % 2 ? 22 : 54; ctx.lineTo(x + 64 + Math.cos(a) * r, y + 66 + Math.sin(a) * r); }
      ctx.closePath(); ctx.fill(); ctx.stroke(); }
    // doormat (rubber, WZTV 13 WELCOME)
    { const [x, y, w, h] = at('mat');
      rr(x + 6, y + 6, w - 12, h - 12, 26); ctx.fillStyle = '#3B2A30'; ctx.fill();
      rr(x + 22, y + 22, w - 44, h - 44, 18); ctx.fillStyle = '#4E3840'; ctx.fill();
      ctx.strokeStyle = 'rgba(0,0,0,0.25)'; ctx.lineWidth = 3;
      for (let i = 0; i < 26; i++) { ctx.beginPath(); ctx.moveTo(x + 30 + i * 18, y + 30); ctx.lineTo(x + 30 + i * 18, y + h - 30); ctx.stroke(); }
      ctx.fillStyle = PAL.wztvBlue; ctx.beginPath(); ctx.arc(x + 118, y + 128, 70, 0, TAU); ctx.fill();
      ctx.lineWidth = 12; ctx.strokeStyle = PAL.channelRed; ctx.stroke();
      text('13', x + 118, y + 132, 80, FONT_SIGN, '#F4F1E8');
      text('WZTV', x + 330, y + 104, 74, FONT_SIGN, '#E8A92E', { shadow: 'rgba(0,0,0,0.4)' });
      text('WELCOME', x + 330, y + 170, 38, FONT_ROUND, '#F6E7C8'); }
    // brass plaque for the studio-tour exhibit
    { const [x, y, w, h] = at('plaque');
      const g = ctx.createLinearGradient(0, y, 0, y + h); g.addColorStop(0, '#FFE9A8'); g.addColorStop(0.5, '#E0B04A'); g.addColorStop(1, '#A8761C');
      rr(x + 6, y + 10, w - 12, h - 20, 14); ctx.fillStyle = g; ctx.fill();
      ctx.lineWidth = 4; ctx.strokeStyle = '#7A5210'; ctx.stroke();
      text('STUDIO TOUR', x + w / 2, y + 44, 34, FONT_SIGN, '#4A2E08');
      text('RCA TK-41 · THE FIRST COLOR CAMERA OF WZTV · 1954', x + w / 2, y + 84, 18, FONT_ROUND, '#5A3A0A', { max: w - 40 }); }
    // gold vinyl lettering for the booth glass (transparent bg)
    { const [x, y, w, h] = at('glassAnnounce');
      text('ANNOUNCE', x + w / 2, y + 52, 64, FONT_GROOVY, '#FFD27A', { stroke: '#8A5A20', lw: 6 });
      text('· WZTV 13 ·', x + w / 2, y + 104, 26, FONT_SIGN, '#FFD27A'); }
    // MAKE-UP sign, CALL BOARD header, QUIET PLEASE
    { const [x, y, w, h] = at('makeup');
      rr(x + 4, y + 8, w - 8, h - 16, 40); ctx.fillStyle = '#F6E7C8'; ctx.fill();
      ctx.lineWidth = 8; ctx.strokeStyle = '#E3662B'; ctx.stroke();
      text('Make-Up', x + w / 2, y + h / 2 + 6, 70, FONT_GROOVY, '#B5472A', { shadow: 'rgba(90,40,20,0.3)' }); }
    { const [x, y, w, h] = at('callboard');
      rr(x + 4, y + 16, w - 8, h - 32, 12); ctx.fillStyle = '#2A2231'; ctx.fill();
      text('CALL BOARD', x + w / 2, y + h / 2 + 3, 54, FONT_SIGN, '#FFC23A'); }
    { const [x, y, w, h] = at('quiet');
      rr(x + 4, y + 14, w - 8, h - 28, 16); ctx.fillStyle = '#E23B3B'; ctx.fill();
      text('QUIET PLEASE', x + w / 2, y + h / 2 + 3, 50, FONT_SIGN, '#FBF8F1'); }
    { const [x, y, w, h] = at('towel');
      ctx.fillStyle = '#F4F1E8'; ctx.fillRect(x, y, w, h);
      for (const [c, yy] of [[PAL.burntOrange, 18], [PAL.harvestGold, 34], [PAL.avocado, 50]]) { ctx.fillStyle = c; ctx.fillRect(x, y + yy, w, 10); ctx.fillRect(x, y + h - yy - 10, w, 10); }
      text('WZTV', x + w / 2, y + h / 2, 30, FONT_SIGN, PAL.wztvBlue); }
    { const [x, y, w, h] = at('cue');
      rr(x + 6, y + 10, w - 12, h - 20, 8); ctx.fillStyle = '#FBF8F1'; ctx.fill();
      text('STATION ID', x + w / 2, y + 42, 26, FONT_SIGN, '#E23B3B');
      text('"This is WZTV, Channel 13..."', x + w / 2, y + 80, 15, FONT_TYPE, '#2A2231', { max: w - 24 }); }
    // cup lid, boa fluff, cucumber, fan, wig
    { const [x, y] = at('cup'); ctx.fillStyle = '#F6E7C8'; ctx.beginPath(); ctx.arc(x + 64, y + 64, 50, 0, TAU); ctx.fill();
      ctx.fillStyle = '#5A3A22'; ctx.beginPath(); ctx.arc(x + 64, y + 64, 40, 0, TAU); ctx.fill(); }
    { const [x, y] = at('boa'); for (let i = 0; i < 80; i++) { ctx.fillStyle = rand() < 0.5 ? '#FF5FA2' : '#FF8CC0'; ctx.beginPath(); ctx.ellipse(x + 20 + rand() * 88, y + 20 + rand() * 88, 12, 5, rand() * 3, 0, TAU); ctx.fill(); } }
    { const [x, y] = at('cucumber');
      ctx.fillStyle = '#3F7A2A'; ctx.beginPath(); ctx.arc(x + 64, y + 64, 56, 0, TAU); ctx.fill();
      ctx.fillStyle = '#CFE8A0'; ctx.beginPath(); ctx.arc(x + 64, y + 64, 48, 0, TAU); ctx.fill();
      ctx.fillStyle = '#E8F6C8';
      for (let i = 0; i < 7; i++) { const a = i / 7 * TAU; ctx.beginPath(); ctx.ellipse(x + 64 + Math.cos(a) * 22, y + 64 + Math.sin(a) * 22, 7, 4, a, 0, TAU); ctx.fill(); } }
    { const [x, y] = at('fan');
      ctx.fillStyle = '#6B3A6E'; ctx.beginPath(); ctx.moveTo(x + 64, y + 110); ctx.arc(x + 64, y + 110, 96, -PI * 0.85, -PI * 0.15); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = '#FFC23A'; ctx.lineWidth = 3; for (let i = 0; i < 8; i++) { const a = -PI * 0.85 + i * PI * 0.1; ctx.beginPath(); ctx.moveTo(x + 64, y + 110); ctx.lineTo(x + 64 + Math.cos(a) * 94, y + 110 + Math.sin(a) * 94); ctx.stroke(); } }
    { const [x, y] = at('wig');
      for (let i = 0; i < 60; i++) { ctx.fillStyle = rand() < 0.5 ? '#2A1A12' : '#4A2E1E'; ctx.beginPath(); ctx.arc(x + 20 + rand() * 88, y + 20 + rand() * 88, 10 + rand() * 8, 0, TAU); ctx.fill(); } }
  }, { repeat: false, fonts: true });
}

export function atlasMats(game) {
  const map = atlasTex();
  map.anisotropy = 8;
  return {
    decal: K.mat(game, 'plastic', '#ffffff', { map, alphaTest: 0.5, side: THREE.DoubleSide }),
    paper: K.mat(game, 'paint', '#ffffff', { map, alphaTest: 0.5, side: THREE.DoubleSide }),
    glow: K.glow(game, '#ffffff', 1.5, { map }),
  };
}

// PlaneGeometry (w × h, facing +z) textured with an atlas cell. flat = lying on the floor (facing +y, text top → -z).
export function cellPlane(name, w, h, { flat = false, face = '+z' } = {}) {
  const c = CELLS[name];
  const g = new THREE.PlaneGeometry(w, h);
  K.uvRect(g, c[0] / 8, 1 - (c[1] + (c[3] ?? 1)) / 8, (c[0] + (c[2] ?? 1)) / 8, 1 - c[1] / 8);
  if (flat) g.rotateX(-PI / 2);
  else if (face === '-z') g.rotateY(PI);
  return g;
}

// Small flat paper / letter on the floor or a tabletop (y = surface height).
export function decal(mat, name, w, h, pos, rotY = 0) {
  const m = new THREE.Mesh(cellPlane(name, w, h, { flat: true }), mat);
  m.position.set(pos[0], pos[1] + 0.004, pos[2]);
  m.rotation.y = rotY;
  m.castShadow = false;
  m.receiveShadow = true;
  return m;
}

// ================================================================================================ local props
// Brass stanchions + red velvet ropes through [[x,z],...] (local), axis-aligned segments get thin colliders.
export function velvetRopes(game, posts) {
  const g = K.prop('lg_velvet_ropes');
  const brass = K.mat(game, 'brass', '#C8963C');
  const velvet = K.mat(game, 'felt', '#B0203A');
  const H = 0.92;
  for (const [x, z] of posts) {
    g.add(K.m(K.lathe([[0, 0], [0.16, 0], [0.165, 0.02], [0.12, 0.045], [0.04, 0.065], [0, 0.066]], { seg: 22, round: 0.008 }), brass, { pos: [x, 0, z] }));
    g.add(K.m(K.cyl(0.026, 0.03, H - 0.06, { seg: 14 }), brass, { pos: [x, 0.05, z] }));
    g.add(K.m(K.lathe([[0, 0], [0.042, 0], [0.05, 0.03], [0.044, 0.06], [0.024, 0.08], [0.032, 0.1], [0.02, 0.125], [0, 0.13]], { seg: 16, round: 0.006 }), brass, { pos: [x, H - 0.03, z] }));
  }
  const colliders = [];
  for (let i = 0; i < posts.length - 1; i++) {
    const [ax, az] = posts[i], [bx, bz] = posts[i + 1];
    const pts = [];
    for (let k = 0; k <= 10; k++) {
      const t = k / 10;
      pts.push([ax + (bx - ax) * t, H - 0.07 - Math.sin(PI * t) * 0.17, az + (bz - az) * t]);
    }
    g.add(K.m(K.tube(pts, 0.024, { seg: 22, radial: 8 }), velvet));
    for (const [x, z, s] of [[ax, az, 1], [bx, bz, -1]]) {
      const d = Math.hypot(bx - ax, bz - az) || 1;
      g.add(K.m(K.cyl(0.03, 0.03, 0.05, { seg: 10 }).clone().rotateZ(PI / 2).rotateY(-Math.atan2(bz - az, bx - ax)), brass,
        { pos: [x + ((bx - ax) / d) * 0.05 * s, H - 0.075, z + ((bz - az) / d) * 0.05 * s] }));
    }
    colliders.push({ min: [Math.min(ax, bx) - 0.07, 0, Math.min(az, bz) - 0.07], max: [Math.max(ax, bx) + 0.07, H, Math.max(az, bz) + 0.07] });
  }
  g.userData.colliders = colliders;
  return K.finish(game, g, { ao: { res: 40, height: 0.08 } });
}

// Walnut wall shelf on two brass brackets; back at local z = 0 (wall plane), top at y = 0.
export function wallShelf(game, w = 0.62, d = 0.46) {
  const g = K.prop('lg_wall_shelf');
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.35 }) });
  const brass = K.mat(game, 'brass', '#C8963C');
  g.add(K.m(K.box(w, 0.04, d, 0.012, { uv: 1.5 }), walnut, { pos: [0, -0.02, -d / 2] }));
  for (const s of [-1, 1]) {
    g.add(K.m(K.box(0.03, 0.22, 0.02, 0.006), brass, { pos: [s * (w / 2 - 0.08), -0.15, -0.012] }));
    g.add(K.m(K.tube([[0, -0.25, -0.02], [0, -0.12, -d * 0.45], [0, -0.04, -d * 0.7]], 0.012, { seg: 10, radial: 5 }), brass, { pos: [s * (w / 2 - 0.08), 0, 0] }));
  }
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}

// Lit EXIT box (emergency circuit: always on). Back at local z = 0, faces -z, bottom at y = 0.
export function exitSign(game, am) {
  const g = K.prop('lg_exit');
  const shell = K.mat(game, 'plastic', '#E8E0CC');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  g.add(K.m(K.box(0.56, 0.24, 0.1, 0.03), shell, { pos: [0, 0.12, -0.05] }));
  const face = K.m(cellPlane('exit', 0.5, 0.19, { face: '-z' }), am.glow, { pos: [0, 0.12, -0.102] });
  face.userData.noOcclude = true;
  g.add(face);
  for (const s of [-1, 1]) g.add(K.m(K.cyl(0.012, 0.012, 0.12, { seg: 8 }), chrome, { pos: [s * 0.2, 0.24, -0.05] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0 } });
}

// ============================================================================================ lobby builders
function plinth(game, am, h = 1.22) {
  const g = K.prop('lg_plinth');
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.35 }) });
  const lac = K.mat(game, 'lacquer', '#2A1D2A');
  g.add(K.m(K.box(0.62, 0.1, 0.56, 0.03, { uv: 1.5 }), lac, { pos: [0, 0.05, 0] }));
  g.add(K.m(K.box(0.5, h - 0.2, 0.44, 0.04, { uv: 1.5, swap: true }), walnut, { pos: [0, 0.1 + (h - 0.2) / 2, 0] }));
  g.add(K.m(K.box(0.64, 0.1, 0.58, 0.03, { uv: 1.5 }), lac, { pos: [0, h - 0.05, 0] }));
  for (const y of [0.34, h - 0.24]) g.add(K.m(K.box(0.52, 0.035, 0.46, 0.012), K.mat(game, 'brass', '#C8963C'), { pos: [0, y, 0] }));
  g.add(K.m(cellPlane('plaque', 0.44, 0.11, { face: '-z' }), am.decal, { pos: [0, h - 0.42, -0.226] }));
  g.userData.colliders = [{ min: [-0.32, 0, -0.3], max: [0.32, h, 0.3] }];
  return K.finish(game, g, { ao: { res: 32 } });
}

function signPost(game, card) {
  const g = K.prop('lg_sign_post');
  const brass = K.mat(game, 'brass', '#C8963C');
  const face = K.mat(game, 'lacquer', '#ffffff', { map: card });
  g.add(K.m(K.lathe([[0, 0], [0.15, 0], [0.155, 0.02], [0.1, 0.04], [0.03, 0.06], [0, 0.06]], { seg: 20, round: 0.008 }), brass));
  g.add(K.m(K.cyl(0.022, 0.024, 0.9, { seg: 12 }), brass, { pos: [0, 0.04, 0] }));
  const panel = new THREE.Group();
  panel.position.set(0, 1.02, 0);
  panel.rotation.x = 0.3;
  panel.add(K.m(K.box(0.66, 0.36, 0.035, 0.012), brass, { pos: [0, 0, 0.02] }));
  panel.add(K.m(new THREE.PlaneGeometry(0.62, 0.31).rotateY(PI), face, { pos: [0, 0, 0.0] }));
  g.add(panel);
  g.userData.colliders = [{ min: [-0.16, 0, -0.16], max: [0.16, 1.2, 0.16] }];
  return K.finish(game, g, { ao: { res: 32 } });
}

// Announcer desk with a chunky ribbon microphone, script, cue card and coffee mug. Front (announcer side) = -z.
function announcerDesk(game, am) {
  const g = K.prop('lg_announcer_desk');
  const walnut = K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.35 }) });
  const felt = K.mat(game, 'felt', '#3E6B3A');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const lac = K.mat(game, 'lacquer', '#ffffff');
  const W = 1.2, D = 0.58, H = 0.76;
  g.add(K.m(K.box(W, 0.05, D, 0.02, { uv: 1.5 }), walnut, { pos: [0, H - 0.025, 0] }));
  g.add(K.m(K.box(W - 0.1, 0.012, D - 0.14, 0.004), felt, { pos: [0, H + 0.006, -0.02] }));
  for (const s of [-1, 1]) g.add(K.m(K.box(0.05, H - 0.05, D - 0.06, 0.015, { uv: 1.5, swap: true }), walnut, { pos: [s * (W / 2 - 0.04), (H - 0.05) / 2, 0] }));
  g.add(K.m(K.box(W - 0.1, 0.42, 0.03, 0.012, { uv: 1.5 }), walnut, { pos: [0, H - 0.3, D / 2 - 0.06] }));
  g.add(K.m(K.tint(K.box(W - 0.14, 0.05, 0.03, 0.012).clone(), PAL.burntOrange), lac, { pos: [0, H - 0.1, D / 2 - 0.08] }));
  // ribbon mic (RCA 44 style, chunky): pill body with a dark grille band, chrome caps, yoke, weighted base
  const mic = new THREE.Group();
  mic.position.set(0.05, H, 0.02);
  mic.add(K.m(K.lathe([[0, 0], [0.11, 0], [0.115, 0.02], [0.07, 0.045], [0, 0.05]], { seg: 22, round: 0.01 }), chrome));
  mic.add(K.m(K.cyl(0.016, 0.016, 0.22, { seg: 10 }), chrome, { pos: [0, 0.04, 0] }));
  const head = new THREE.Group();
  head.position.set(0, 0.36, 0);
  head.rotation.x = 0.12;
  head.add(K.m(K.lathe([[0, -0.13], [0.05, -0.12], [0.075, -0.07], [0.08, 0], [0.075, 0.07], [0.05, 0.12], [0, 0.13]], { seg: 22, round: 0.01 }), K.mat(game, 'metal', '#3A3440', { rough: 0.5 })));
  for (const y of [-0.085, 0.085]) head.add(K.m(K.cyl(0.078, 0.078, 0.03, { seg: 22, bevel: 0.008 }), chrome, { pos: [0, y - 0.015, 0] }));
  head.add(K.m(K.cyl(0.083, 0.083, 0.02, { seg: 22, bevel: 0.006 }), K.mat(game, 'lacquer', PAL.channelRed), { pos: [0, -0.01, 0] }));
  for (const s of [-1, 1]) head.add(K.m(K.box(0.012, 0.16, 0.03, 0.005), chrome, { pos: [s * 0.095, -0.03, 0] }));
  mic.add(head);
  g.add(mic);
  // script, cue card, mug
  g.add(K.m(cellPlane('script', 0.21, 0.28, { flat: true }), am.paper, { pos: [-0.33, H + 0.016, -0.05], rot: [0, 0.18, 0] }));
  g.add(K.m(cellPlane('script2', 0.21, 0.28, { flat: true }), am.paper, { pos: [-0.36, H + 0.02, -0.02], rot: [0, -0.1, 0] }));
  const cue = K.m(cellPlane('cue', 0.3, 0.15, { face: '-z' }), am.decal, { pos: [0.4, H + 0.09, -0.02], rot: [-0.3, -0.2, 0] });
  g.add(cue);
  g.add(K.m(K.tint(K.cyl(0.042, 0.038, 0.1, { seg: 16 }).clone(), PAL.harvestGold), lac, { pos: [-0.12, H + 0.012, -0.14] }));
  g.add(K.m(K.tube([[-0.08, H + 0.09, -0.14], [-0.055, H + 0.07, -0.14], [-0.055, H + 0.04, -0.14], [-0.08, H + 0.03, -0.14]], 0.008, { seg: 10, radial: 5 }), lac));
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, H + 0.05, D / 2] }];
  return K.finish(game, g, { ao: { res: 40 } });
}

// WZTV rubber doormat (walkable, no collider).
function doormat(game, am) {
  const g = K.prop('lg_doormat');
  g.add(K.m(K.box(1.3, 0.018, 0.66, 0.008), K.mat(game, 'rubber', '#3B2A30'), { pos: [0, 0.009, 0] }));
  g.add(K.m(cellPlane('mat', 1.24, 0.6, { flat: true }), am.paper, { pos: [0, 0.019, 0] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}

// Moonlight through the boarded front doors: additive floor slats (board gaps), fading into the room.
function moonSlatsTex() {
  return K.tex.canvas('rooms.lg.moonslats', 256, 256, (ctx, w, h) => {
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h);
    const gaps = [0.1, 0.27, 0.46, 0.63, 0.82];
    for (const g of gaps) {
      const y = g * h;
      const grd = ctx.createLinearGradient(0, y - 12, 0, y + 12);
      grd.addColorStop(0, 'rgba(255,255,255,0)'); grd.addColorStop(0.5, 'rgba(255,255,255,1)'); grd.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = grd; ctx.fillRect(10, y - 12, w - 20, 24);
    }
    // fade toward the room (bottom = far from the window) and soft sides
    ctx.globalCompositeOperation = 'destination-in';
    const f = ctx.createLinearGradient(0, 0, 0, h); f.addColorStop(0, 'rgba(0,0,0,0)'); f.addColorStop(1, 'rgba(0,0,0,1)');
    ctx.fillStyle = f; ctx.fillRect(0, 0, w, h);
    const s = ctx.createLinearGradient(0, 0, w, 0);
    s.addColorStop(0, 'rgba(0,0,0,0)'); s.addColorStop(0.18, 'rgba(0,0,0,1)'); s.addColorStop(0.82, 'rgba(0,0,0,1)'); s.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = s; ctx.fillRect(0, 0, w, h);
    ctx.globalCompositeOperation = 'source-over';
  }, { repeat: false });
}

export function moonSlats(game, kit, pos, rotY, { w = 1.9, d = 2.6, shear = 0.35, pre = 0.55, post = 0.3, color = '#9FB6FF' } = {}) {
  const map = moonSlatsTex();
  const geo = new THREE.PlaneGeometry(w, d, 1, 1).rotateX(-PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) p.setX(i, p.getX(i) + (p.getZ(i) + d / 2) * shear);   // lean
  geo.translate(0, 0, -d / 2);        // local z 0 = the wall, the slats reach into -z (the room)
  const onM = game.mats.glow(color, post, { map, additive: true, fog: false });
  const offM = game.mats.glow(color, pre, { map, additive: true, fog: false });
  const m = new THREE.Mesh(geo, offM);
  m.position.set(pos[0], 0.012, pos[2]);
  m.rotation.y = rotY;
  m.renderOrder = 2;
  m.castShadow = false;
  m.receiveShadow = false;
  m.userData.noMerge = true;
  kit.root.add(m);
  kit.onPower(pos, (on) => { m.material = on ? onM : offM; });
  return m;
}

// ================================================================================================== build
export function build(game, area, root) {
  const kit = roomKit(game, area, root);
  const am = atlasMats(game);
  const A = (id) => ANCHORS[id];
  const WALL = { n: -5.85, s: 5.85, w: -6.85, e: 6.85 };
  const lvl = game.level;

  // ------------------------------------------------------------------------------------ island: desk + neon
  const desk = kit.place('desk_reception', [0, 0, -0.42], PI);
  const neon = kit.place('neon_logo_partition', [0, 0, -1.4], PI, { state: 'dark' }, { lights: false });
  kit.obj('reception_desk', { group: desk, parts: desk?.userData.parts || {} });

  // four globe pendants over the desk (off before Sign-On), merged into one switchable draw
  const globeOn = K.mat(game, 'ceramic', '#FFF1D8', { emissive: '#FFD9A0', emissiveIntensity: 0.95, rim: 0.5, rimColor: '#FFFFFF' });
  const globeOff = K.mat(game, 'ceramic', '#E9DCC4', { rim: 0.4 });
  const globes = [];
  [[-1.55, -0.3], [-0.52, -0.46], [0.52, -0.46], [1.55, -0.3]].forEach(([x, z], i) => {
    const p = kit.place('lamp_globe_pendant', [x, 4.0, z], 0, { drop: 0.95 + (i % 2) * 0.12, r: 0.21 }, { lights: false });
    if (p?.userData.parts.glow) globes.push(p.userData.parts.glow);
  });
  const globeMesh = kit.mergeInto(globes, globeOff, 'lobby_globes');
  kit.onPower([0, 2.8, -0.4], (on) => { if (globeMesh) globeMesh.material = on ? globeOn : globeOff; });
  kit.anchor({ pos: [-1.0, 2.5, -0.1], color: PAL.tungsten, intensity: 2.2, distance: 6.5, pre: 0, post: 1 });
  kit.anchor({ pos: [1.0, 2.5, -0.1], color: PAL.tungsten, intensity: 2.2, distance: 6.5, pre: 0, post: 1 });
  kit.pool([0, 0.02, 0.9], 2.9, '#FFC98A', 0, 0.2);

  // neon logo: dark tubes before power, W V 13 lit + Z T dead after Sign-On, all lit after EE step 1
  const neonLight = kit.anchor({ pos: [0, 1.9, -0.25], color: '#FF8AC0', intensity: 1.6, distance: 5.5, pre: 0.1, post: 1 });
  kit.pool([0, 0.02, -0.2], 2.2, '#FF6FB0', 0.03, 0.14);
  const NEON_KEYS = ['W', 'Z', 'T', 'V', '13'];
  const neonObj = kit.obj('neon_logo', {
    group: neon,
    parts: neon ? Object.fromEntries(NEON_KEYS.map((k) => [k, neon.userData.parts[`neon_${k}`]])) : {},
    state: 'dark',
    levels: { W: 0.2, Z: 0.2, T: 0.2, V: 0.2, 13: 0.2 },
    fixT: -1,
    setLetter(key, level) {
      const q = Math.round(THREE.MathUtils.clamp(level, 0, 1) * 20) / 20;
      if (this.levels[key] === q) return;
      this.levels[key] = q;
      if (neon) setNeon(neon, game, key, q);
    },
    setState(state) {
      this.state = state;
      this.fixT = -1;
      for (const k of NEON_KEYS) this.setLetter(k, state === 'dark' ? 0.2 : state === 'broken' && (k === 'Z' || k === 'T') ? 0.2 : 1);
    },
    fix() {
      if (this.state === 'lit' || this.fixT >= 0) return;
      this.fixT = 0;
      kit.sound('ee_neon_stutter', [0, 1.9, -1.2]);
    },
  });
  if (neon) {
    kit.onPower([0, 1.9, -1.3], (on) => neonObj.setState(on ? ((game.egg?.step ?? 0) >= 1 ? 'lit' : 'broken') : 'dark'));
    const STUTTER = [0.2, 1, 0.2, 0.2, 1, 0.35, 1, 0.2, 0.2, 1, 1, 0.3, 1];
    kit.ticks.push((dt, t, rdt) => {
      const o = neonObj;
      if (o.fixT >= 0) {
        o.fixT += rdt;
        const i = Math.floor(o.fixT / 0.11);
        if (i >= STUTTER.length) { o.setState('lit'); return; }
        o.setLetter('Z', STUTTER[i]);
        o.setLetter('T', STUTTER[(i + 3) % STUTTER.length]);
        return;
      }
      if (o.state !== 'broken') return;
      // dead tubes: a low flickering buzz with rare sputters (still clearly colored)
      const f = Math.floor(game.time.realNow * 12);
      for (const [k, s] of [['Z', 3.1], ['T', 7.7]]) {
        const h = hash(f * 0.37 + s);
        o.setLetter(k, h > 0.93 ? 0.45 : h > 0.6 ? 0.25 : 0.15);
      }
    });
    kit.hook(neon.userData.parts.neon_W);
  }
  void neonLight;

  // ------------------------------------------------------------------------------------ announce booth (NW)
  const rack = kit.place('chime_rack', [-6.55, 0, -4.5], -PI / 2);
  if (rack) setupChimes(game, kit, rack);
  kit.put(announcerDesk(game, am), [-5.5, 0, -5.52], PI);
  kit.place('chair_office', [-5.35, 0, -4.78], 0.35);
  kit.put(wallShelf(game, 0.66, 0.5), [-5.6, 1.69, WALL.n], PI, { colliders: false });
  const prog = kit.place('bc_rack_monitor', [-5.6, 1.69, WALL.n + 0.27], PI, { size: 14, card: 'station_id', group: 'scr_feed_lobby' },
    { screenGroup: 'scr_feed_lobby', screenIds: ['mon_lobby_booth'], colliders: false });
  if (prog) kit.obj('mon_lobby_booth', { group: prog, screen: prog.userData.screens[0]?.mesh || null });
  kit.anchor({ pos: [-5.6, 1.9, -5.1], color: '#8FD8FF', intensity: 0.7, distance: 3.2 });
  const onAir = kit.place('bc_on_air', [-5.6, 2.32, WALL.n + 0.065], PI, { lit: false });
  const onAirLight = kit.anchor({ pos: [-5.6, 2.3, -5.3], color: PAL.onAirRed, intensity: 1.0, distance: 3, pre: 0, post: 0 });
  const boothOnAir = kit.obj('booth_on_air', {
    group: onAir, on: false,
    set(on) {
      this.on = !!on;
      if (onAir) setLamp(onAir, on ? 'on' : 'off');
      game.lights?.setAnchor?.(onAirLight, { intensity: on ? 1.0 : 0 });
    },
  });
  if (onAir?.userData.parts.lamp) onAir.userData.parts.lamp.userData.noMerge = true;
  kit.place('bc_headphones_hook', [-4.78, 0.8, WALL.n + 0.05], PI, {}, { colliders: false });
  kit.place('plant_snake', [-4.95, 0, -3.45], 0.4, { seed: 3 });
  // gold lettering on the booth glass (lobby side)
  const glassTxt = new THREE.Mesh(cellPlane('glassAnnounce', 1.5, 0.375), am.decal);
  glassTxt.position.set(-5.8, 2.25, -2.975);
  glassTxt.castShadow = false;
  root.add(glassTxt);

  // ------------------------------------------------------------------------------------ trophy case (west wall)
  const tc = kit.place('trophy_case', [-6.5, 0, -2.0], -PI / 2, {}, { pre: 0.8, post: 1 });
  if (tc) {
    const door = tc.userData.parts.door;
    const dud = new THREE.Vector3(...(tc.userData.anchors?.dudley || [0, 1.3, 0])).applyMatrix4(tc.matrixWorld);
    const drop = new THREE.Vector3(...(tc.userData.anchors?.door_drop || [0.6, 0, -0.9])).applyMatrix4(tc.matrixWorld);
    const trophy = kit.obj('ee_trophy_case', {
      group: tc, parts: { door }, dudley: dud, dropPoint: drop, open: false, _k: 0,
      setOpen(open, instant = false) { this.open = !!open; if (instant) { this._k = open ? 1 : 0; if (door) door.rotation.y = -1.9 * this._k; } },
    });
    kit.ticks.push((dt, t, rdt) => {
      const target = trophy.open ? 1 : 0;
      if (trophy._k === target || !door) return;
      trophy._k = THREE.MathUtils.clamp(trophy._k + Math.sign(target - trophy._k) * rdt / 0.7, 0, 1);
      const k = trophy._k;
      door.rotation.y = -1.9 * (target ? 1 - (1 - k) ** 3 : k * k);
    });
    kit.resets.push(() => trophy.setOpen(false, true));
    kit.pool([-5.7, 0.02, -2.0], 1.5, '#FFE6B8', 0.1, 0.14);
  }

  // ------------------------------------------------------------------------------------ studio-tour exhibit (SE)
  const fc = A('feed_cam_lobby');
  const cam = kit.place('bc_pedestal_camera', [fc.pos[0], 0, fc.pos[2]], fc.rotY, { num: 1, tally: true, color: 'cream', accent: 'wztvBlue' });
  kit.put(velvetRopes(game, [[4.22, 4.72], [4.22, 3.72], [5.5, 3.72], [6.72, 3.72]]), [0, 0, 0], 0);
  kit.put(signPost(game, game.cards?.get?.('sign_see_yourself') ?? null), [5.0, 0, 3.4], 1.5);
  kit.put(plinth(game, am, 1.22), [4.62, 0, 5.3], PI / 4);
  const mon = kit.place('bc_tv_19', [4.62, 1.22, 5.3], PI / 4, { legs: 'none', card: 'station_id', group: 'scr_feed_lobby' },
    { screenGroup: 'scr_feed_lobby', screenIds: ['mon_lobby_exhibit'], colliders: false });
  if (mon) kit.obj('mon_lobby_exhibit', { group: mon, screen: mon.userData.screens[0]?.mesh || null });
  kit.anchor({ pos: [4.1, 1.4, 4.8], color: '#9FE0FF', intensity: 0.8, distance: 3.5 });
  kit.pool([5.55, 0.02, 4.75], 1.6, '#FFD8A0', 0.14, 0.18);
  // camera cable snaking to a wall box
  const cable = K.m(K.tube([[5.9, 0.03, 5.1], [6.2, 0.03, 5.35], [6.5, 0.03, 5.4], [6.78, 0.08, 5.45], [6.8, 0.35, 5.5]], 0.022, { seg: 20, radial: 6 }),
    K.mat(game, 'rubber', '#2A2230'));
  root.add(cable);
  if (cam) {
    const parts = cam.userData.parts;
    for (const p of [parts.head, parts.tilt, parts.tally]) if (p) p.userData.noMerge = true;
    const camObj = kit.obj('exhibit_camera', {
      group: cam, parts, tally: true, nod: -1,
      setTally(on) { this.tally = !!on; setLamp(cam, on ? 'on' : 'off', 'tally'); },
    });
    const tilt0 = parts.tilt ? parts.tilt.rotation.x : 0;
    kit.toy('toy_exhibit_camera', A('toy_exhibit_camera').pos, () => {
      camObj.setTally(!camObj.tally);
      camObj.nod = 0;
      kit.sound('toy_camera_zoom', fc.pos);
      game.screens?.zoomFeed?.('lobby', 5);
      game.events?.emit?.('toy:exhibit_zoom', { area: 'lobby', seconds: 5, tally: camObj.tally });
    }, 2.1);
    kit.ticks.push((dt, t, rdt) => {
      if (camObj.nod < 0 || !parts.tilt) return;
      camObj.nod += rdt;
      const k = camObj.nod;
      parts.tilt.rotation.x = tilt0 + Math.sin(k * 9) * 0.12 * Math.max(0, 1 - k / 0.9);
      if (k > 0.9) { camObj.nod = -1; parts.tilt.rotation.x = tilt0; }
    });
    kit.resets.push(() => camObj.setTally(true));
  }

  // ------------------------------------------------------------------------------------ desk bell toy + clutter
  const bell = desk?.userData.parts.bell;
  if (bell) {
    const bellPos = bell.getWorldPosition(new THREE.Vector3());
    const bellState = { t: -1 };
    kit.toy('toy_desk_bell', A('toy_desk_bell').pos, () => {
      bellState.t = 0;
      kit.sound('toy_bell', bellPos);
    }, 1.6);
    const s0 = bell.scale.clone(), y0 = bell.position.y;
    kit.ticks.push((dt, t, rdt) => {
      if (bellState.t < 0) return;
      bellState.t += rdt;
      const k = bellState.t;
      const sq = k < 0.08 ? 1 - k / 0.08 * 0.3 : 0.7 + 0.3 * (1 - Math.exp(-(k - 0.08) * 9) * Math.cos((k - 0.08) * 30));
      bell.scale.set(s0.x * (2 - sq) ** 0.5, s0.y * sq, s0.z * (2 - sq) ** 0.5);
      bell.position.y = y0 + Math.max(0, Math.sin((k - 0.08) * 12)) * 0.03 * Math.exp(-k * 4);
      if (k > 0.8) { bellState.t = -1; bell.scale.copy(s0); bell.position.y = y0; }
    });
  }
  // papers + pledge cards around the desk and booth
  for (const [name, x, z, r, s] of [
    ['pledge', 1.6, 0.55, 0.4, 0.2], ['script', -1.2, 0.7, -0.5, 0.26], ['pledge', -2.6, -0.2, 1.1, 0.2],
    ['memo', 2.5, -1.25, 0.3, 0.14], ['paper', -4.1, -4.1, 0.25, 0.5], ['ticket', 3.4, 2.4, -0.7, 0.16],
    ['script2', -3.6, -2.4, 0.8, 0.26], ['pledge', 0.8, 1.9, 2.4, 0.18],
  ]) {
    const hgt = name === 'paper' ? 0.25 : s * (name.startsWith('script') ? 1.33 : 1.15);
    root.add(decal(am.paper, name, s, hgt, [x, 0.0, z], r));
  }

  // ------------------------------------------------------------------------------------ conversation corners (E wall)
  kit.place('sofa_cloud', [6.36, 0, -3.72], PI / 2, {});
  kit.place('rug_shag_round', [5.25, 0, -3.72], 0, { r: 1.05 });
  kit.place('table_coffee', [5.02, 0, -3.72], PI / 2);
  kit.place('table_side_tulip', [6.42, 0, -5.42], 0);
  kit.place('lamp_arc', [5.55, 0, -5.52], 2.85, {}, { pre: 0, post: 0.75 });
  kit.pool([5.1, 0.02, -4.3], 1.7, '#FFD49A', 0, 0.2);
  kit.place('sofa_cloud', [6.36, 0, 2.12], PI / 2, {});
  kit.place('lamp_tripod', [6.5, 0, 0.52], 0.3, {}, { pre: 0, post: 0.75 });
  kit.pool([6.1, 0.02, 0.9], 1.4, '#FFD49A', 0, 0.18);
  // portrait wall above the sofas: the Baron, Stormy Stu, the crew
  for (const [card, z, h, style] of [
    ['portrait_stormy_stu', -4.62, 0.56, 'walnut'], ['portrait_baron', -3.72, 0.72, 'gold'], ['hero_portrait_duke', -2.84, 0.56, 'gold'],
    ['hero_portrait_skip', 1.26, 0.56, 'gold'], ['hero_portrait_roxy', 2.12, 0.56, 'gold'], ['hero_portrait_penny', 2.98, 0.56, 'gold'],
  ]) {
    kit.place('frame_picture', [WALL.e, card === 'portrait_baron' ? 1.24 : 1.36, z], PI / 2, { card, style, h }, { colliders: false,
      tilt: [0, (hash(z * 3.1) - 0.5) * 0.05] });
  }

  // ------------------------------------------------------------------------------------ north wall
  const clock = kit.place('clock_sunburst', [0, 2.8, WALL.n], PI, {}, { colliders: false });
  if (clock) setupClock(game, kit, clock, [0, 3.29, WALL.n]);
  kit.place('plant_rubber', [-3.95, 0, -5.38], 0.6, { seed: 2 });
  for (const [card, x] of [['sponsor_poster_wobble_up', -3.05], ['sponsor_poster_jump_cut', 2.35], ['sponsor_poster_roller_boogie', 6.05]]) {
    kit.place('frame_picture', [x, 1.28, WALL.n], PI, { card, style: 'chrome', h: 0.74 }, { colliders: false, tilt: [0, (hash(x) - 0.5) * 0.05] });
  }

  // ------------------------------------------------------------------------------------ south wall / front doors
  // (player_spawn sits left of this board so the shoulder camera, pulled in against the south wall, is not behind it)
  const lb = kit.place('letter_board', [1.2, 0, 5.08], -0.12);
  const letters = [];
  for (const [L, x, z, r] of [['S', 0.55, 4.55, 0.5], ['I', -0.35, 3.25, -0.9], ['G', 1.95, 4.35, 2.2], ['N', 0.1, 4.95, 1.4],
    ['O', -0.95, 4.2, 0.2], ['F', 2.35, 3.7, -0.4], ['F', 1.2, 3.55, 2.9]]) {
    const m = decal(am.decal, L, 0.19, 0.19, [x, 0.0, z], r);
    letters.push(m);
    root.add(m);
  }
  const letterObj = kit.obj('letter_board', {
    group: lb, parts: { face: lb?.userData.parts.face }, letters, signed: false,
    signOff(on) {
      this.signed = !!on;
      const face = this.parts.face;
      if (face) face.material = K.mat(game, 'felt', '#ffffff', { map: game.cards?.get?.('letter_board', { signOff: !!on }), rim: 0.12 });
      for (const m of letters) m.visible = !on;
    },
  });
  if (lb?.userData.parts.face) lb.userData.parts.face.userData.noMerge = true;
  for (const m of letters) m.userData.noMerge = true;
  kit.resets.push(() => { if (letterObj.signed) letterObj.signOff(false); });
  kit.place('plant_rubber', [-1.75, 0, 5.36], 2.2, { seed: 5 });
  kit.place('frame_picture', [-1.3, 1.25, WALL.s], 0, { card: 'sponsor_poster_replay_ade', style: 'chrome', h: 0.74 }, { colliders: false });
  kit.place('frame_picture', [6.2, 1.34, WALL.s], 0, { card: 'sponsor_poster_double_vision', style: 'chrome', h: 0.66 }, { colliders: false });
  for (const x of [-3, 3]) {
    kit.put(exitSign(game, am), [x, 2.62, WALL.s], 0, { colliders: false });
    kit.put(doormat(game, am), [x, 0, 4.95], 0);
    kit.pool([x, 0.02, 5.2], 1.1, '#FF4A3A', 0.12, 0.06);
    moonSlats(game, kit, [x, 0, WALL.s], 0, { w: 1.7, d: 2.7, shear: x < 0 ? 0.28 : -0.28 });
  }
  moonSlats(game, kit, [WALL.w, 0, 0], -PI / 2, { w: 1.7, d: 2.4, shear: 0.22, pre: 0.4, post: 0.22 });
  kit.anchor({ pos: [0, 2.2, 4.6], color: '#9FB6FF', intensity: 1.6, distance: 7, pre: 1, post: 0.45 });
  kit.anchor({ pos: [-5.4, 1.8, 0], color: '#9FB6FF', intensity: 1.0, distance: 5, pre: 1, post: 0.4 });

  // ------------------------------------------------------------------------------------ west wall
  kit.place('plant_fern', [-6.35, 0, 1.45], 0.8, { seed: 4 });
  kit.place('macrame_owl', [WALL.w, 1.2, 2.25], -PI / 2, {}, { colliders: false });

  // ------------------------------------------------------------------------------------ ceiling cans: floor pools
  for (const x of [-14 / 3, 0, 14 / 3]) {
    for (const z of [-3, 3]) kit.pool([x, 0.02, z], 1.9, '#FFB45A', 0.2, 0.12);
  }

  // ------------------------------------------------------------------------------------ EE / story hooks
  const onStep = ({ step } = {}) => {
    if (step >= 1) { neonObj.fix(); boothOnAir.set(true); }
  };
  game.events?.on?.('egg:step', onStep);
  game.events?.on?.('egg:complete', () => {
    letterObj.signOff(true);
    level_clock(lvl)?.setMidnight(true);
  });
  kit.resets.push(() => {
    boothOnAir.set(false);
    if ((game.egg?.step ?? 0) < 1 && neonObj.state === 'lit') neonObj.setState(game.machines?.powerOn ? 'broken' : 'dark');
    level_clock(lvl)?.setMidnight(false);
  });
  boothOnAir.set(false);
  return kit;
}

const level_clock = (lvl) => lvl?.objects?.lobby_clock;

// Chime rack (EE step 1): springy pendulum bars, capsule raycasts, swing API.
function setupChimes(game, kit, rack) {
  const COLORS = ['red', 'yellow', 'green', 'blue'];
  const info = rack.userData.chimes || {};
  const parts = {};
  const bars = {};
  const front = new THREE.Vector3(0, 0, -1).applyQuaternion(rack.quaternion);   // toward the booth opening (east)
  for (const c of COLORS) {
    const part = rack.userData.parts[`bar_${c}`];
    if (!part) continue;
    part.userData.noMerge = true;
    parts[`ee_bar_${c}`] = part;
    const len = info[c]?.len ?? 1;
    bars[c] = {
      part, note: info[c]?.note, hz: info[c]?.hz, len, th: 0, w: 0,
      top: () => part.localToWorld(new THREE.Vector3(0, 0, 0)),
      bottom: () => part.localToWorld(new THREE.Vector3(0, -len, 0)),
    };
  }
  const R = 0.055;
  const seg = new THREE.Vector3(), w0 = new THREE.Vector3();
  const obj = kit.obj('ee_chime_rack', {
    group: rack, parts, bars,
    swing(color, strength = 1, dir = null) {
      const b = bars[color];
      if (!b) return;
      const s = dir ? Math.sign(dir.dot(front)) || -1 : -1;
      b.w += s * 2.6 * strength;
    },
    ring(color) { this.swing(color, 1); },
    // Ray vs. each bar capsule (current swing pose); returns the nearest hit.
    raycast(origin, dir, maxDist = 100, only = null) {
      let best = null;
      for (const c of COLORS) {
        if (only && c !== only) continue;
        const b = bars[c];
        if (!b) continue;
        const a = b.top(), e = b.bottom();
        seg.subVectors(e, a);
        w0.subVectors(origin, a);
        const A = dir.dot(dir), B = dir.dot(seg), C = seg.dot(seg), D = dir.dot(w0), E = seg.dot(w0);
        const den = A * C - B * B;
        let t = den > 1e-8 ? (B * E - C * D) / den : 0;
        let s = den > 1e-8 ? (A * E - B * D) / den : 0;
        s = THREE.MathUtils.clamp(s, 0, 1);
        t = Math.max(0, (B * s - D) / A);
        const pr = _v.copy(origin).addScaledVector(dir, t);
        const ps = _w.copy(a).addScaledVector(seg, s);
        const d = pr.distanceTo(ps);
        if (d > R) continue;
        const hit = t - Math.sqrt(Math.max(0, R * R - d * d));
        if (hit < 0 || hit > maxDist) continue;
        if (!best || hit < best.dist) best = { color: c, id: `ee_bar_${c}`, dist: hit, point: origin.clone().addScaledVector(dir, hit) };
      }
      return best;
    },
  });
  kit.ticks.push((dt) => {
    const h = Math.min(dt, 1 / 30);
    if (h <= 0) return;
    for (const c of COLORS) {
      const b = bars[c];
      if (!b || (Math.abs(b.th) < 1e-4 && Math.abs(b.w) < 1e-4)) continue;
      const k = 9.8 / (0.55 * b.len);
      b.w += (-k * b.th - 1.1 * b.w) * h;
      b.th += b.w * h;
      b.th = THREE.MathUtils.clamp(b.th, -0.5, 0.5);
      b.part.rotation.x = b.th;
    }
  });
  kit.resets.push(() => { for (const c of COLORS) if (bars[c]) { bars[c].th = bars[c].w = 0; bars[c].part.rotation.x = 0; } });
  // listen to the canonical chime event too (so the EE only needs to emit egg:chime)
  game.events?.on?.('egg:chime', ({ bar } = {}) => { const c = String(bar || '').replace('ee_bar_', ''); if (bars[c]) obj.swing(c, 0.8); });
  return obj;
}

// 11:59 sunburst clock: the second hand twitches :58 → :59 → :58; after the easter egg it ticks to 12:00.
function setupClock(game, kit, clock, center) {
  const parts = clock.userData.parts;
  for (const k of ['hour', 'minute', 'second']) if (parts[k]) parts[k].userData.noMerge = true;
  const ang = (h, m, s) => [((h % 12) + m / 60 + s / 3600) / 12 * TAU, (m + s / 60) / 60 * TAU, s / 60 * TAU];
  const obj = kit.obj('lobby_clock', {
    group: clock, parts, midnight: false, mt: -1,
    setMidnight(on) {
      if (on === this.midnight) return;
      this.midnight = !!on;
      this.mt = on ? 0 : -1;
      if (!on) this.pose(11, 59, 58);
      if (on) ['ee_chime_red', 'ee_chime_yellow', 'ee_chime_green', 'ee_chime_blue'].forEach((id, i) => kit.sound(id, center, { delay: 0.6 + i * 0.45 }));
    },
    pose(h, m, s) {
      const [ah, amn, as] = ang(h, m, s);
      if (parts.hour) parts.hour.rotation.z = ah;
      if (parts.minute) parts.minute.rotation.z = amn;
      if (parts.second) parts.second.rotation.z = as;
    },
  });
  kit.ticks.push((dt, t, rdt) => {
    if (obj.midnight) {
      if (obj.mt < 0) return;
      obj.mt += rdt;
      const k = Math.min(1, obj.mt / 0.5);
      const e = 1 + 2.2 * (k - 1) ** 3 + 1.2 * (k - 1) ** 2;      // back-out ease
      obj.pose(11, 59 + e, 58 + 2 * e);
      if (k >= 1) { obj.pose(12, 0, 0); obj.mt = -1; }
      return;
    }
    const now = game.time?.realNow ?? 0;
    const ph = now % 1.6;
    const s = ph < 0.8 ? 58 + Math.min(1, ph / 0.06) : 59 - Math.min(1, (ph - 0.8) / 0.08);
    obj.pose(11, 59, s + (ph < 0.8 && ph > 0.06 ? Math.sin((ph - 0.06) * 40) * 0.08 * Math.exp(-(ph - 0.06) * 10) : 0));
  });
  return obj;
}
