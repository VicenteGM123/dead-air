// Room dressing: MASTER CONTROL (GDD §5.7 "Master Control", §3.3 lighting, §10.0/§10.1 screens, §13 step 5 + toys,
// §18.13/§18.14 ids). Owner: rooms-green-mc. build(game, area, root) runs once from level.build() after the
// graybox; static meshes are merged per material by the level afterwards, animated parts are flagged noMerge.
// Uses the room toolkit exported by newsroom.js (runtime: world tickers + power-wave switches; atlas; place...).
//
// Layout (world metres; inner wall faces x 23.15 / 34.85, z -13.85 (north) / -2.15 (south); ceiling 3.6):
//   north wall  the 4 x 3 monitor wall x 28.2..34.6 (middle row scr_mc_feeds at eye level, top + bottom rows
//               scr_mc_canned; bottom corners are the screen spawns ss_mc_w / ss_mc_e), two tall patch-bay racks in the
//               NW corner, D7 kept clear
//   west wall   ee_rundown_board (6 slots) under a brass picture light, three patch bays + a WZTV clock at 11:59,
//               D5 kept clear
//   south wall  three quad VTRs (#1 and #3 spin their reels after power; ee_vtr2 with bare spindles, a blinking
//               amber lamp, the 13-detent ee_tracking_knob and its scr_vtr2 monitor) under a QUAD VTR BAY sign, the
//               quad-tape library shelf (one empty slot labelled SIGN OFF) under the master clock at 11:59 with a tape
//               cart beside it, the oscillating floor fan in the SE corner, B13 kept clear
//   east wall   TRANSMITTER remote meter panel, waveform/vectorscope cart, DANGER sign, fire extinguisher, the opened
//               Perpetua-Tube crate with the "NEVER SIGN OFF AGAIN!" ad taped above it (SE corner), DY kept clear
//   centre      the console island + Sign-On lever belong to signon.js (left clear); flanking the lever sit the
//               Laff-O-Matic cart (toy_laff_o_matic) and the routing switcher cart (toy_switcher); rolling chairs;
//               dark anti-static floor mats (console, VTR aisle, monitor wall); overhead ladder cable trays with looms
//               into the racks, the wall, the console and the VTRs; floor cable runs, tape boxes, spilled coffee
//
// Power (GDD §3.3 / §10.1): before Sign-On the monitor wall glows faint static cyan and VTR #2's amber lamp blinks;
// as the colour wave passes: VTR #1/#3 lamps go green and their reels/VU needles run, the scopes light their green
// traces, the rack LED speckle starts blinking (one live-canvas mesh), the transmitter meters swing up, the fan
// spins, the rundown picture light and the wall's cyan wash come up. A new game with the power off reverts all.
//
// game.level.objects entries (world space):
//   mc_monitor_wall { group, screens:[12 meshes], byId:{ mcwall_r{row}c{col} | ss_mc_w | ss_mc_e -> mesh } }
//   ss_mc_w / ss_mc_e { group, screen }
//   ee_vtr2 { group, parts:{ spindleL, spindleR, lamp, trackingKnob, reelL, reelR, tape, monitor, needleL, needleR },
//             screen (scr_vtr2 CRT), loaded, lamp:'amber'|'green'|..., setLamp(color|'off', blink = color==='amber'),
//             loadTape(seconds = 1.5) (reels pop onto the spindles, tape threads, reels spin), unloadTape(),
//             spin(on), knobPos:Vector3 }
//   ee_tracking_knob { group (the knob part), parts:{ knob }, detents:13, detent, set(k, animate = true), turn(dir = 1)
//             -> detent, pos:Vector3 }
//   vtr_1 / vtr_3 { group, parts, spin(on) }
//   ee_rundown_board { group, parts:{ card_1..card_6 }, slots:[Vector3 x6], cards:[bool x6], setCard(n, on = true,
//             animate = true) }  (also automatic: egg:step {step} pins card <step>, egg:complete pins card 6; a new game
//             clears them)
//   perpetua_crate { group }   mc_clocks { parts:{ west, master } }   laff_o_matic { group, parts, play() }
//   mc_switcher { group, parts, play() }
// Toys (GDD §13, key-only [E]): toy_laff_o_matic ('toy_laff' from its speaker, 10 s cooldown: the big red button
//   squashes, the LAUGH / APPLAUSE lamps flash, the needle dances), toy_switcher ('toy_switcher': after power the
//   whole wall shows one indoor feed tiled 12x for 5 s via screens.override(feed_<area>, ['scr_mc_feeds',
//   'scr_mc_canned'], 5, 7.5); before power the wall blinks). Each emits 'toy:use' {id}.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as K from '../../props/kit.js';
import { PAL } from '../../props/kit.js';
import { setLamp } from '../../props/broadcast.js';
import { setRundownCard } from '../../props/sets.js';
import { runtime, stdMats, atlas, quad, obj, place, pool, toy, tc, setClockHands } from './newsroom.js';
import { ANCHORS } from '../layout.js';

const PI = Math.PI;
const HP = PI / 2;
const TAU = PI * 2;
const WALL = { n: -13.85, s: -2.15, w: 23.15, e: 34.85 };
const DETENT = TAU / 13;
const sph = (r, ws = 14, hs = 10) => new THREE.SphereGeometry(r, ws, hs);
const hash = (n) => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };
const v3 = (a) => new THREE.Vector3(a[0], a[1], a[2]);

// ================================================================================================ mc atlas
// 512² print atlas (4 x 4 cells of 128 px): fire sign, no smoking, the SIGN OFF shelf label, VTR BAY sign, the
// switcher key plate, tape-box labels. cell(name) -> [u0, v0, u1, v1].
const MCELLS = {
  fire: [0, 0], nosmoke: [1, 0], signoff: [2, 0, 2, 1], vtrbay: [0, 1, 2, 1], router: [2, 1, 2, 1],
  tapelbl: [0, 2, 4, 1], library: [0, 3, 4, 1],
};
function mcAtlasTex() {
  return K.tex.canvas('rooms.mc.atlas.v1', 512, 512, (ctx, W, H) => {
    ctx.clearRect(0, 0, W, H);
    const C = 128;
    const at = (n) => { const c = MCELLS[n]; return [c[0] * C, c[1] * C, (c[2] ?? 1) * C, (c[3] ?? 1) * C]; };
    const rr = (x, y, w, h, r) => { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); };
    const text = (s, x, y, size, font, fill, o = {}) => {
      ctx.save(); ctx.translate(x, y); if (o.rot) ctx.rotate(o.rot);
      let sz = size; ctx.font = `${sz}px ${font}`;
      if (o.max) while (ctx.measureText(s).width > o.max && sz > 6) { sz *= 0.93; ctx.font = `${sz}px ${font}`; }
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = fill; ctx.fillText(s, 0, 0); ctx.restore();
    };
    const SIGN = '"Bungee", Impact, "Arial Black", sans-serif';
    const ROUND = '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif';
    const HAND = '"Titan One", "Comic Sans MS", sans-serif';
    { const [x, y, w, h] = at('fire');
      rr(x + 6, y + 6, w - 12, h - 12, 12); ctx.fillStyle = '#E23B3B'; ctx.fill();
      ctx.fillStyle = '#FFE3A3'; ctx.beginPath(); ctx.moveTo(x + 64, y + 22); ctx.bezierCurveTo(x + 96, y + 52, x + 90, y + 88, x + 64, y + 94); ctx.bezierCurveTo(x + 38, y + 88, x + 32, y + 56, x + 52, y + 40); ctx.bezierCurveTo(x + 52, y + 56, x + 60, y + 60, x + 64, y + 22); ctx.fill();
      text('FIRE', x + 64, y + 110, 20, SIGN, '#FBF8F1'); }
    { const [x, y, w, h] = at('nosmoke');
      ctx.fillStyle = '#FBF8F1'; rr(x + 6, y + 6, w - 12, h - 12, 12); ctx.fill();
      ctx.fillStyle = '#5A3A22'; ctx.fillRect(x + 30, y + 58, 60, 12); ctx.fillStyle = '#E3662B'; ctx.fillRect(x + 84, y + 58, 10, 12);
      ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 9; ctx.beginPath(); ctx.arc(x + 64, y + 60, 38, 0, TAU); ctx.moveTo(x + 37, y + 33); ctx.lineTo(x + 91, y + 87); ctx.stroke();
      text('NO SMOKING', x + 64, y + 112, 13, SIGN, '#2A2231'); }
    { const [x, y, w, h] = at('signoff');
      ctx.fillStyle = '#FBF8F1'; rr(x + 8, y + 30, w - 16, h - 60, 6); ctx.fill();
      ctx.strokeStyle = '#2A2A8A'; ctx.lineWidth = 3; ctx.strokeRect(x + 14, y + 36, w - 28, h - 72);
      text('SIGN OFF', x + w / 2, y + 60, 34, HAND, '#E23B3B', { rot: -0.03 });
      text('12:00 AM  · #13', x + w / 2, y + 88, 16, HAND, '#2A2A8A', { rot: -0.02 }); }
    { const [x, y, w, h] = at('vtrbay');
      rr(x + 4, y + 20, w - 8, h - 40, 14); ctx.fillStyle = '#2A2231'; ctx.fill();
      ctx.strokeStyle = '#FFB347'; ctx.lineWidth = 5; ctx.stroke();
      text('QUAD VTR BAY', x + w / 2, y + h / 2 - 4, 34, SIGN, '#FFB347', { max: w - 30 });
      text('2-INCH · 15 IPS', x + w / 2, y + h / 2 + 26, 14, ROUND, '#F6E7C8'); }
    { const [x, y, w, h] = at('router');
      rr(x + 4, y + 30, w - 8, h - 60, 10); ctx.fillStyle = '#F6E7C8'; ctx.fill();
      text('ROUTE-O-MATIC 16', x + w / 2, y + h / 2, 26, SIGN, '#2F5BD3', { max: w - 24 }); }
    { const [x, y, w, h] = at('tapelbl');
      ctx.fillStyle = '#F3EEDF'; ctx.fillRect(x, y, w, h);
      for (let i = 0; i < 8; i++) {
        ctx.fillStyle = ['#E23B3B', '#2F5BD3', '#E8A92E', '#52D24A'][i % 4]; ctx.fillRect(x + i * 64, y, 64, 18);
        ctx.fillStyle = 'rgba(40,30,60,0.7)'; for (let k = 0; k < 4; k++) ctx.fillRect(x + i * 64 + 8, y + 34 + k * 20, 30 + ((i * 7 + k * 3) % 18), 5);
      } }
    { const [x, y, w, h] = at('library');
      rr(x + 4, y + 24, w - 8, h - 48, 12); ctx.fillStyle = '#C8963C'; ctx.fill();
      rr(x + 12, y + 32, w - 24, h - 64, 8); ctx.fillStyle = '#2A2231'; ctx.fill();
      text('WZTV TAPE LIBRARY', x + w / 2, y + h / 2 + 2, 36, SIGN, '#E8B84A', { max: w - 50 }); }
    void W; void H;
  }, { repeat: false, fonts: true });
}
function mcAtlas(game) {
  const map = mcAtlasTex();
  map.anisotropy = 8;
  const cell = (name, sub = [0, 0, 1, 1]) => {
    const c = MCELLS[name], cw = (c[2] ?? 1) / 4, ch = (c[3] ?? 1) / 4, u0 = c[0] / 4, vTop = 1 - c[1] / 4;
    return [u0 + sub[0] * cw, vTop - sub[3] * ch, u0 + sub[2] * cw, vTop - sub[1] * ch];
  };
  return { map, cell, mat: K.mat(game, 'paint', '#ffffff', { map, rim: 0.12 }), dim: K.mat(game, 'paint', '#D8CCB0', { map, rim: 0.05, rough: 0.9 }) };
}
// plane facing -z (prop front) with a rect of UVs
const qf = (w, h, rect) => quad(w, h, rect).rotateY(PI);

// ============================================================================================ local builders
// Rolling equipment cart (walnut shelves, chrome posts, casters). Returns the group; top shelf at y = top.
function cart(g, mt, W = 0.52, D = 0.42, top = 0.74) {
  for (const y of [0.16, top]) {
    g.add(K.m(K.box(W, 0.03, D, 0.01, { uv: 1.5 }), mt.walnut, { pos: [0, y, 0] }));
    g.add(K.m(K.tube(K.roundRectPath(W - 0.01, D - 0.01, 0.025, 0.018, 2), 0.006, { seg: 20, radial: 4, closed: true }), mt.chrome, { pos: [0, y, 0] }));
  }
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    g.add(K.m(K.cyl(0.013, 0.013, top - 0.05, { seg: 8 }), mt.chrome, { pos: [x * (W / 2 - 0.03), 0.06, z * (D / 2 - 0.03)] }));
    g.add(K.m(tc(sph(0.028, 10, 8), '#2A2231'), mt.rubber, { pos: [x * (W / 2 - 0.03), 0.028, z * (D / 2 - 0.03)] }));
  }
}
const lampMatsLaff = (game) => ({ on: K.glow(game, '#FFE14A', 2.0), off: K.mat(game, 'plastic', '#8A7A48', { rim: 0.3 }), onR: K.glow(game, '#FF5A3C', 2.0), offR: K.mat(game, 'plastic', '#7A3A34', { rim: 0.3 }) });

// ---------------------------------------------------------------------------------------------- Laff-O-Matic
// The canned-laughter machine on its cart: cream case, orange face, LAFF-O-MATIC plate, a giant red button (part),
// LAUGH / APPLAUSE lamps (parts, material swap), a VU needle (part), a grinning speaker grille and a tape cart.
// Front -z.
function laffCart(game, NA) {
  const g = K.prop('mc_laff_o_matic');
  const mt = stdMats(game);
  const LM = lampMatsLaff(game);
  cart(g, mt);
  const y0 = 0.755;
  g.add(K.m(tc(K.box(0.46, 0.26, 0.32, 0.05), '#F3E6C8'), mt.lacquer, { pos: [0, y0 + 0.13, 0.01] }));
  g.add(K.m(tc(K.box(0.42, 0.2, 0.02, 0.02), PAL.burntOrange), mt.lacquer, { pos: [0, y0 + 0.13, -0.155] }));
  g.add(K.m(quad(0.2, 0.05, NA.cell('plate', [0, 0.5, 1, 1])).rotateY(PI), NA.mat, { pos: [-0.08, y0 + 0.2, -0.167] }));
  // grinning speaker grille: dark slot + chrome smile
  g.add(K.m(tc(K.box(0.16, 0.05, 0.01, 0.02), '#2A2231'), mt.plastic, { pos: [-0.08, y0 + 0.1, -0.166] }));
  g.add(K.m(new THREE.TorusGeometry(0.08, 0.008, 6, 18, PI), mt.chrome, { pos: [-0.08, y0 + 0.12, -0.168], rot: [0, 0, PI] }));
  // VU meter (needle part)
  g.add(K.m(tc(K.box(0.1, 0.07, 0.01, 0.01), '#FFF1C8'), mt.plastic, { pos: [0.12, y0 + 0.17, -0.166] }));
  const needle = new THREE.Group();
  needle.position.set(0.12, y0 + 0.14, -0.173);
  needle.rotation.z = 0.5;
  needle.userData.noMerge = true;
  needle.add(K.m(tc(K.box(0.004, 0.05, 0.003, 0.001), '#E23B3B'), mt.plastic, { pos: [0, 0.025, 0] }));
  g.add(needle);
  // lamps
  const lampL = K.m(K.lathe([[0, 0], [0.028, 0], [0.028, 0.012], [0.02, 0.028], [0, 0.032]], { seg: 14, round: 0.004 }).clone().rotateX(-HP), LM.off, { pos: [0.08, y0 + 0.075, -0.165], cast: false });
  const lampR = K.m(K.lathe([[0, 0], [0.028, 0], [0.028, 0.012], [0.02, 0.028], [0, 0.032]], { seg: 14, round: 0.004 }).clone().rotateX(-HP), LM.offR, { pos: [0.16, y0 + 0.075, -0.165], cast: false });
  for (const l of [lampL, lampR]) { l.userData.noMerge = true; l.userData.noOcclude = true; g.add(l); }
  // giant red button on top (part), chrome collar
  g.add(K.m(K.cyl(0.075, 0.08, 0.025, { seg: 20, bevel: 0.006 }), mt.chrome, { pos: [0.1, y0 + 0.26, -0.02] }));
  const button = new THREE.Group();
  button.position.set(0.1, y0 + 0.285, -0.02);
  button.userData.noMerge = true;
  button.add(K.m(tc(K.lathe([[0, 0], [0.062, 0], [0.064, 0.02], [0.05, 0.045], [0.025, 0.056], [0, 0.058]], { seg: 20, round: 0.006 }), '#E23B3B'), mt.lacquer));
  g.add(button);
  // tape cart slot + cart sticking out
  g.add(K.m(tc(K.box(0.14, 0.02, 0.1, 0.006), '#2A2231'), mt.plastic, { pos: [-0.1, y0 + 0.262, 0.02] }));
  g.add(K.m(tc(K.box(0.12, 0.05, 0.08, 0.01), '#E8A92E'), mt.plastic, { pos: [-0.1, y0 + 0.29, 0.03], rot: [0.1, 0, 0] }));
  // bottom shelf: tape carts + coiled cord
  for (let i = 0; i < 4; i++) g.add(K.m(tc(K.box(0.12, 0.04, 0.1, 0.008), ['#E23B3B', '#2F5BD3', '#E8A92E', '#52D24A'][i]), mt.plastic, { pos: [-0.14 + (i % 2) * 0.13, 0.195 + Math.floor(i / 2) * 0.042, 0.04], rot: [0, (i - 1.5) * 0.12, 0] }));
  const coil = [];
  for (let i = 0; i <= 40; i++) { const t = i / 40, a = t * TAU * 3; coil.push([0.13 + Math.cos(a) * 0.07, 0.19 + t * 0.03, Math.sin(a) * 0.06]); }
  g.add(K.m(tc(K.tube(coil, 0.008, { seg: 36, radial: 4 }), '#2A2231'), mt.plastic));
  g.userData.parts = { button, needle, lampL, lampR };
  g.userData.lampMats = LM;
  g.userData.colliders = [{ min: [-0.28, 0, -0.22], max: [0.28, 1.1, 0.22] }];
  return K.finish(game, g, { ao: { res: 32 } });
}

// --------------------------------------------------------------------------------------- routing switcher
// "ROUTE-O-MATIC 16": a 4 x 4 grid of lit keys (one mesh whose colours come from a small live canvas, so the key
// chase costs one draw), two knobs, a take bar. Front -z. userData.keyTex = the live CanvasTexture.
function routerCart(game, MA) {
  const g = K.prop('mc_switcher');
  const mt = stdMats(game);
  cart(g, mt);
  const y0 = 0.755;
  g.add(K.m(tc(K.box(0.46, 0.1, 0.34, 0.03), '#3B3645'), mt.plastic, { pos: [0, y0 + 0.05, 0] }));
  g.add(K.m(tc(K.box(0.46, 0.12, 0.08, 0.03), '#3B3645'), mt.plastic, { pos: [0, y0 + 0.11, 0.13] }));
  g.add(K.m(qf(0.4, 0.07, MA.cell('router')), MA.mat, { pos: [0, y0 + 0.13, 0.087], rot: [-0.25, 0, 0] }));
  // keys on a sloped plate: 4 x 4, UV per key into a 4 x 4 canvas
  const canvas = typeof document !== 'undefined' ? document.createElement('canvas') : null;
  let keyTex = null;
  if (canvas) {
    canvas.width = canvas.height = 64;
    keyTex = new THREE.CanvasTexture(canvas);
    keyTex.colorSpace = THREE.SRGBColorSpace;
    keyTex.magFilter = THREE.NearestFilter;
    keyTex.minFilter = THREE.NearestFilter;
    keyTex.generateMipmaps = false;
  }
  const geos = [];
  const kg = K.box(0.05, 0.035, 0.042, 0.01);
  for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) {
    const k = kg.clone();
    const uv = k.attributes.uv;
    const u = (c + 0.5) / 4, v = 1 - (r + 0.5) / 4;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, u, v);
    k.translate(-0.105 + c * 0.07, 0.008, -0.095 + r * 0.062);
    geos.push(k);
  }
  const keysGeo = mergeGeometries(geos, false);
  const keys = K.m(keysGeo, game.mats.glow('#ffffff', 1.4, { map: keyTex }), { pos: [-0.04, y0 + 0.108, -0.04], rot: [0.12, 0, 0], cast: false });
  keys.userData.noMerge = true;
  keys.userData.noOcclude = true;
  g.add(keys);
  for (const x of [0.15, 0.2]) {
    g.add(K.m(tc(K.lathe([[0, 0], [0.018, 0], [0.017, 0.025], [0.012, 0.032], [0, 0.033]], { seg: 12, round: 0.003 }), '#2A2231'), mt.plastic, { pos: [x, y0 + 0.1, -0.1] }));
  }
  g.add(K.m(K.cyl(0.008, 0.008, 0.12, { seg: 8 }), mt.chrome, { pos: [0.175, y0 + 0.1, 0.0], rot: [0.3, 0, 0] }));
  g.add(K.m(tc(sph(0.02, 10, 8), '#E23B3B'), mt.plastic, { pos: [0.175, y0 + 0.215, 0.035] }));
  for (let i = 0; i < 3; i++) g.add(K.m(tc(K.box(0.2, 0.012, 0.2, 0.004), ['#2F5BD3', '#E23B3B', '#F4F1E8'][i]), mt.paint, { pos: [0.02, 0.18 + i * 0.013, 0.02], rot: [0, (i - 1) * 0.15, 0] }));
  g.userData.parts = { keys };
  g.userData.keyCanvas = canvas;
  g.userData.keyTex = keyTex;
  g.userData.colliders = [{ min: [-0.28, 0, -0.22], max: [0.28, 1.0, 0.22] }];
  return K.finish(game, g, { ao: { res: 32 } });
}
// Key colours: idle pattern (one lit per row, like a real router) or the chase (col/row sweep).
function paintKeys(canvas, tex, mode, t = 0, powered = true) {
  if (!canvas || !tex) return;
  const ctx = canvas.getContext('2d');
  const cols = ['#52E04A', '#FFB347', '#FF3B30', '#5FE3FF'];
  for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) {
    let on = false, col = '#4A4450';
    if (mode === 'chase') { const k = Math.floor(t * 10) % 16; on = (r * 4 + c) === k || c === Math.floor(t * 4) % 4; col = on ? cols[(r + Math.floor(t * 3)) % 4] : '#4A4450'; }
    else if (powered) { on = c === [1, 3, 0, 2][r]; col = on ? cols[r] : '#5A5462'; }
    ctx.fillStyle = on ? col : (powered ? '#D8D0BC' : '#8A8478');
    ctx.fillRect(c * 16, r * 16, 16, 16);
  }
  tex.needsUpdate = true;
}

// --------------------------------------------------------------------------------------- waveform/vector cart
// Two scope CRTs on a cart: the waveform monitor (green line traces) and the vectorscope (green star); faces are one
// mesh with lit/unlit materials (parts.faces, lampMats {on, off}). Front -z.
function scopeTex() {
  return K.tex.canvas('rooms.mc.scopes.v1', 512, 256, (ctx, w, h) => {
    const S = 256;
    for (let i = 0; i < 2; i++) {
      const x0 = i * S;
      const g = ctx.createRadialGradient(x0 + S / 2, h / 2, 10, x0 + S / 2, h / 2, S * 0.7);
      g.addColorStop(0, '#0E3A26'); g.addColorStop(1, '#04140C');
      ctx.fillStyle = g; ctx.fillRect(x0, 0, S, h);
      ctx.strokeStyle = 'rgba(120,255,160,0.25)'; ctx.lineWidth = 2;
      for (let k = 1; k < 8; k++) { ctx.beginPath(); ctx.moveTo(x0 + k * 32, 16); ctx.lineTo(x0 + k * 32, h - 16); ctx.stroke(); ctx.beginPath(); ctx.moveTo(x0 + 16, k * 32); ctx.lineTo(x0 + S - 16, k * 32); ctx.stroke(); }
    }
    ctx.shadowColor = '#7CFF9A'; ctx.shadowBlur = 8;
    ctx.strokeStyle = '#9CFFB0'; ctx.lineWidth = 3;
    // waveform: colour-bar staircase + sync
    ctx.beginPath();
    const lv = [0.78, 0.7, 0.58, 0.52, 0.44, 0.36, 0.26];
    ctx.moveTo(20, 200);
    lv.forEach((l, k) => { const x = 30 + k * 30; ctx.lineTo(x, 230 - l * 200); ctx.lineTo(x + 28, 230 - l * 200); });
    ctx.lineTo(240, 200); ctx.stroke();
    ctx.beginPath(); for (let x = 20; x < 240; x += 4) ctx.lineTo(x, 214 + Math.sin(x * 0.4) * 3); ctx.stroke();
    // vectorscope: graticule circle + colour-bar star
    const cx = S + S / 2, cy = h / 2;
    ctx.strokeStyle = 'rgba(156,255,176,0.6)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(cx, cy, 100, 0, TAU); ctx.stroke();
    ctx.strokeStyle = '#9CFFB0'; ctx.lineWidth = 3; ctx.beginPath();
    const pts = [[0.2, 1.3], [0.8, 2.4], [0.7, 3.4], [0.75, 4.4], [0.8, 5.5], [0.7, 0.3]];
    ctx.moveTo(cx, cy);
    for (const [r, a] of pts) { ctx.lineTo(cx + Math.cos(a) * r * 90, cy + Math.sin(a) * r * 90); ctx.lineTo(cx, cy); }
    ctx.stroke();
    ctx.shadowBlur = 0;
  }, { repeat: false });
}
function scopeCart(game) {
  const g = K.prop('mc_scope_cart');
  const mt = stdMats(game);
  cart(g, mt, 0.6, 0.46, 0.7);
  const map = scopeTex();
  const on = game.mats.glow('#ffffff', 1.15, { map });
  const off = K.mat(game, 'crt', '#1A2A22', { map });
  const geos = [];
  [[-0.14, 0.95, 0], [0.14, 0.95, 1]].forEach(([x, y, i]) => {
    g.add(K.m(tc(K.box(0.27, 0.24, 0.36, 0.03), '#6B7282'), mt.metal, { pos: [x, y, 0.02] }));
    g.add(K.m(tc(K.box(0.25, 0.22, 0.02, 0.02), '#2A2231'), mt.plastic, { pos: [x, y, -0.16] }));
    const f = quad(0.19, 0.15, [i * 0.5, 0, i * 0.5 + 0.5, 1]).rotateY(PI).translate(x, y + 0.01, -0.172);
    geos.push(f);
    for (let k = 0; k < 3; k++) g.add(K.m(tc(K.cyl(0.012, 0.012, 0.012, { seg: 8 }), '#C9CED6'), mt.plastic, { pos: [x - 0.07 + k * 0.07, y - 0.09, -0.172], rot: [HP, 0, 0] }));
  });
  const faces = K.m(mergeGeometries(geos, false), off, { cast: false });
  faces.userData.noMerge = true;
  faces.userData.noOcclude = true;
  g.add(faces);
  // label + probe cable
  g.add(K.m(K.tube([[0.25, 0.9, 0.2], [0.33, 0.6, 0.25], [0.3, 0.2, 0.3], [0.45, 0.02, 0.5]], 0.01, { seg: 16, radial: 5 }), K.mat(game, 'rubber', '#2A2230')));
  g.userData.parts = { faces };
  g.userData.lampMats = { on, off };
  g.userData.colliders = [{ min: [-0.32, 0, -0.26], max: [0.32, 1.12, 0.26] }];
  return K.finish(game, g, { ao: { res: 32 } });
}

// ------------------------------------------------------------------------------------------- tape library
// Steel shelving of 2" quad tape boxes (spines from the newsroom atlas), a row of round tape cans on top, a WZTV
// TAPE LIBRARY header, shelf-edge labels and ONE EMPTY SLOT with a hand-written SIGN OFF label (the missing reel of
// EE step 5). Front -z, back at local z = +D/2.
function tapeShelf(game, NA, MA) {
  const g = K.prop('mc_tape_shelf');
  const mt = stdMats(game);
  const W = 1.9, H = 2.0, D = 0.42;
  const steel = '#7C8594';
  for (const s of [-1, 1]) g.add(K.m(tc(K.box(0.04, H, D, 0.01), steel), mt.metal, { pos: [s * (W / 2 - 0.02), H / 2, 0] }));
  g.add(K.m(tc(K.box(W, H - 0.02, 0.02, 0.006), '#5A6070'), mt.metal, { pos: [0, H / 2, D / 2 - 0.01] }));
  const shelfY = [0.08, 0.5, 0.92, 1.34, 1.76];
  for (const y of shelfY) {
    g.add(K.m(tc(K.box(W - 0.06, 0.03, D - 0.02, 0.008), steel), mt.metal, { pos: [0, y, 0] }));
    g.add(K.m(tc(K.box(W - 0.06, 0.04, 0.012, 0.004), '#9EA4AE'), mt.metal, { pos: [0, y + 0.005, -D / 2 + 0.01] }));
  }
  // tape boxes: 4 shelves, box width varies; spines = 1/8 of the 'spines' cell each
  const boxGeo = K.box(1, 1, 1, 0.004);
  const spineMat = NA.mat;
  for (let si = 0; si < 4; si++) {
    const y = shelfY[si] + 0.015;
    let x = -W / 2 + 0.07;
    let k = si * 5;
    while (x < W / 2 - 0.1) {
      const bw = 0.055 + hash(k * 1.7) * 0.02;
      const bh = 0.34 + hash(k * 2.3) * 0.02;
      const empty = si === 1 && Math.abs(x - 0.15) < 0.05;
      if (empty) { x += 0.1; k++; continue; }            // the missing Sign-Off reel
      const lean = x > W / 2 - 0.2 && si === 3 ? -0.18 : 0;
      const b = boxGeo.clone().scale(bw, bh, 0.34);
      g.add(K.m(tc(b, '#E8E0CC'), mt.paint, { pos: [x + bw / 2, y + bh / 2, 0.01], rot: [0, 0, lean] }));
      const s = k % 8;
      g.add(K.m(qf(bw - 0.006, bh - 0.02, NA.cell('spines', [s / 8, 0.05, (s + 1) / 8, 0.95])), spineMat, { pos: [x + bw / 2, y + bh / 2, -0.161], rot: [0, 0, lean] }));
      x += bw + 0.004;
      k++;
    }
  }
  // shelf 2 empty-slot label (hand-written SIGN OFF card) + shelf label strips
  g.add(K.m(qf(0.13, 0.065, MA.cell('signoff')), MA.dim, { pos: [0.2, shelfY[1] - 0.03, -D / 2 - 0.002], rot: [0, 0, 0.04] }));
  for (let si = 0; si < 4; si++) g.add(K.m(qf(0.3, 0.035, MA.cell('tapelbl', [si * 0.25, 0, si * 0.25 + 0.25, 1])), MA.mat, { pos: [-0.55 + (si % 2) * 1.1, shelfY[si] - 0.03, -D / 2 - 0.003] }));
  // top: round tape cans + a reel in the open
  for (let i = 0; i < 6; i++) {
    const cx = -0.72 + i * 0.26;
    g.add(K.m(tc(K.cyl(0.13, 0.13, 0.05, { seg: 20, bevel: 0.006 }), ['#B8BEC8', '#E23B3B', '#B8BEC8', '#2F5BD3', '#B8BEC8', '#E8A92E'][i]), mt.metal, { pos: [cx, shelfY[4] + 0.015 + (i % 2) * 0.05, 0.0] }));
  }
  g.add(K.m(qf(1.1, 0.14, MA.cell('library')), MA.mat, { pos: [0, H + 0.12, -D / 2 + 0.02] }));
  g.add(K.m(tc(K.box(1.16, 0.18, 0.03, 0.01), '#2A2231'), mt.plastic, { pos: [0, H + 0.12, -D / 2 + 0.04] }));
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, H + 0.2, D / 2] }];
  return K.finish(game, g, { ao: { res: 48 } });
}

// ------------------------------------------------------------------------------------------ ladder cable tray
// Hanging ladder tray along local x (length L), rails + rungs + a colourful cable bundle lying in it, drop rods to
// the ceiling (rod = ceiling height above the tray bottom). y = 0 is the tray bottom.
function cableTray(game, L, rod = 0.32) {
  const g = K.prop('mc_cable_tray');
  const mt = stdMats(game);
  const Wd = 0.34;
  for (const s of [-1, 1]) g.add(K.m(tc(K.box(L, 0.08, 0.025, 0.006), '#5C6474'), mt.paint, { pos: [0, 0.04, s * Wd / 2] }));
  const rungs = Math.floor(L / 0.3);
  for (let i = 0; i <= rungs; i++) g.add(K.m(tc(K.box(0.03, 0.02, Wd, 0.004), '#5C6474'), mt.paint, { pos: [-L / 2 + (i / rungs) * L, 0.01, 0] }));
  for (let x = -L / 2 + 0.3; x < L / 2; x += 1.6) for (const s of [-1, 1]) g.add(K.m(K.cyl(0.008, 0.008, rod, { seg: 6 }), mt.chrome, { pos: [x, 0.04, s * (Wd / 2 + 0.01)] }));
  const cols = ['#2A2231', '#E3662B', '#2F5BD3', '#E8A92E', '#2A2231', '#E23B3B', '#52D24A'];
  cols.forEach((c, i) => {
    const z = -Wd / 2 + 0.04 + (i % 4) * 0.08, y = 0.035 + Math.floor(i / 4) * 0.035;
    const pts = [];
    for (let k = 0; k <= 8; k++) pts.push([-L / 2 + (k / 8) * L, y + Math.sin(k * 1.3 + i) * 0.006, z + Math.sin(k * 0.9 + i * 2) * 0.012]);
    g.add(K.m(tc(K.tube(pts, 0.016, { seg: Math.max(8, Math.round(L * 3)), radial: 5 }), c), mt.rubber));
  });
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}
// A drooping cable loom from (a) down to (b) (world coords, added under root): 4 coloured strands + tie wraps.
function loom(root, mt, a, b, sag = 0.25, seed = 1) {
  const cols = ['#2A2231', '#E3662B', '#2F5BD3', '#E8A92E'];
  cols.forEach((c, i) => {
    const o = (i - 1.5) * 0.028;
    const mid = [(a[0] + b[0]) / 2 + o, Math.max(a[1], b[1]) - (Math.abs(a[1] - b[1]) * 0.45) - sag * (1 + hash(seed + i) * 0.3), (a[2] + b[2]) / 2 + o];
    root.add(K.m(tc(K.tube([[a[0] + o, a[1], a[2] + o], mid, [b[0] + o, b[1], b[2] + o]], 0.013, { seg: 14, radial: 5 }), c), mt.rubber, { cast: false }));
  });
}

// -------------------------------------------------------------------------------------------- picture light
// Brass picture light over the rundown board: wall plate, swan arm, hood with a glowing slot (parts.glow).
function pictureLight(game) {
  const g = K.prop('mc_picture_light');
  const mt = stdMats(game);
  g.add(K.m(K.box(0.12, 0.08, 0.02, 0.008), mt.brass, { pos: [0, 0, -0.01] }));
  g.add(K.m(K.tube([[0, 0, -0.02], [0, 0.06, -0.12], [0, 0.04, -0.22]], 0.012, { seg: 10, radial: 6 }), mt.brass));
  g.add(K.m(K.cyl(0.05, 0.05, 0.6, { seg: 16 }).clone().rotateZ(HP), mt.brass, { pos: [0.3, 0.02, -0.24] }));
  const glow = K.m(K.box(0.56, 0.012, 0.04, 0.004), K.mat(game, 'plastic', '#C8B890'), { pos: [0, -0.03, -0.24], cast: false });
  glow.userData.noMerge = true;
  glow.userData.noOcclude = true;
  g.add(glow);
  g.userData.parts = { glow };
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}

// ------------------------------------------------------------------------------------------ fire extinguisher
function extinguisher(game, MA) {
  const g = K.prop('mc_extinguisher');
  const mt = stdMats(game);
  g.add(K.m(tc(K.box(0.14, 0.2, 0.02, 0.006), '#3B3645'), mt.metal, { pos: [0, 0.5, -0.01] }));
  g.add(K.m(tc(K.lathe([[0, 0], [0.085, 0], [0.09, 0.03], [0.09, 0.5], [0.07, 0.56], [0.03, 0.58], [0, 0.585]], { seg: 20, round: 0.01 }), '#D8342C'), mt.lacquer, { pos: [0, 0.12, -0.11] }));
  g.add(K.m(K.cyl(0.02, 0.024, 0.06, { seg: 10 }), mt.chrome, { pos: [0, 0.7, -0.11] }));
  g.add(K.m(K.box(0.14, 0.02, 0.03, 0.006), mt.chrome, { pos: [0.04, 0.77, -0.11], rot: [0, 0, -0.2] }));
  g.add(K.m(tc(K.tube([[0.03, 0.74, -0.11], [0.12, 0.7, -0.14], [0.12, 0.35, -0.17], [0.07, 0.25, -0.18]], 0.012, { seg: 14, radial: 5 }), '#2A2231'), mt.rubber));
  g.add(K.m(qf(0.24, 0.24, MA.cell('fire')), MA.mat, { pos: [0, 1.0, -0.004] }));
  g.userData.colliders = [{ min: [-0.12, 0, -0.22], max: [0.14, 0.75, 0] }];
  return K.finish(game, g, { ao: { res: 28, floor: false } });
}

// ------------------------------------------------------------------------------------- oscillating floor fan
// Chrome 70s floor fan (all that tube gear runs hot): weighted base, pole, motor, wire cage, 4 blades (part 'blades',
// spins about local z) on an oscillating head (part 'head', swings about y). Front -z.
function floorFan(game) {
  const g = K.prop('mc_floor_fan');
  const mt = stdMats(game);
  g.add(K.m(K.lathe([[0, 0], [0.2, 0], [0.205, 0.02], [0.15, 0.05], [0.04, 0.07], [0, 0.07]], { seg: 24, round: 0.008 }), mt.chrome));
  g.add(K.m(K.cyl(0.018, 0.018, 1.0, { seg: 10 }), mt.chrome, { pos: [0, 0.06, 0] }));
  const head = new THREE.Group();
  head.position.set(0, 1.12, 0);
  head.userData.noMerge = true;
  head.add(K.m(tc(K.cyl(0.07, 0.08, 0.16, { seg: 16, bevel: 0.02 }).clone().rotateX(HP), '#8C9A3A'), mt.lacquer, { pos: [0, 0, 0.1] }));
  head.add(K.m(tc(K.box(0.05, 0.08, 0.05, 0.015), '#8C9A3A'), mt.lacquer, { pos: [0, -0.06, 0.1] }));
  const ring = (r) => K.tube(Array.from({ length: 29 }, (_, i) => { const a = (i / 28) * TAU; return [Math.cos(a) * r, Math.sin(a) * r, 0]; }), 0.005, { seg: 36, radial: 4, closed: true });
  for (const [r, z] of [[0.26, -0.04], [0.18, -0.07], [0.09, -0.085]]) head.add(K.m(ring(r), mt.chrome, { pos: [0, 0, z] }));
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * TAU;
    head.add(K.m(K.tube([[0, 0, -0.09], [Math.cos(a) * 0.18, Math.sin(a) * 0.18, -0.07], [Math.cos(a) * 0.26, Math.sin(a) * 0.26, -0.04], [Math.cos(a) * 0.26, Math.sin(a) * 0.26, 0.04]], 0.004, { seg: 6, radial: 3 }), mt.chrome));
  }
  head.add(K.m(tc(K.cyl(0.03, 0.03, 0.012, { seg: 12 }), '#E23B3B'), mt.lacquer, { pos: [0, 0, -0.095], rot: [HP, 0, 0] }));
  const blades = new THREE.Group();
  blades.position.set(0, 0, 0.0);
  blades.userData.noMerge = true;
  for (let i = 0; i < 4; i++) {
    const b = K.m(tc(K.box(0.07, 0.2, 0.012, 0.03), '#E8E0CC'), mt.plastic, { pos: [0, 0.12, 0], rot: [0.25, 0, 0] });
    const piv = new THREE.Group();
    piv.rotation.z = (i / 4) * TAU;
    piv.add(b);
    blades.add(piv);
  }
  blades.add(K.m(tc(K.cyl(0.035, 0.035, 0.04, { seg: 12 }).clone().rotateX(HP), '#8C9A3A'), mt.lacquer, { pos: [0, 0, 0.02] }));
  head.add(blades);
  g.add(head);
  g.userData.parts = { head, blades };
  g.userData.colliders = [{ min: [-0.21, 0, -0.21], max: [0.21, 1.1, 0.21] }];
  return K.finish(game, g, { ao: { res: 28 } });
}

// ------------------------------------------------------------------------------------------- tape library cart
function tapeCart(game, NA) {
  const g = K.prop('mc_tape_cart');
  const mt = stdMats(game);
  cart(g, mt, 0.8, 0.44, 0.84);
  g.add(K.m(K.tube([[0.4, 0.86, -0.2], [0.5, 0.95, -0.2], [0.5, 0.95, 0.2], [0.4, 0.86, 0.2]], 0.012, { seg: 10, radial: 6 }), mt.chrome));
  for (const [y, n] of [[0.175, 9], [0.855, 7]]) {
    for (let i = 0; i < n; i++) {
      const bw = 0.065, x = -0.34 + i * 0.075;
      const lean = i === n - 1 ? -0.25 : 0;
      g.add(K.m(tc(K.box(bw, 0.34, 0.34, 0.004), '#E8E0CC'), mt.paint, { pos: [x + (lean ? 0.03 : 0), y + 0.17, 0], rot: [0, 0, lean] }));
      const s = (i * 3 + (y > 0.5 ? 1 : 0)) % 8;
      g.add(K.m(qf(bw - 0.006, 0.32, NA.cell('spines', [s / 8, 0.05, (s + 1) / 8, 0.95])), NA.mat, { pos: [x + (lean ? 0.03 : 0), y + 0.17, -0.171], rot: [0, 0, lean] }));
    }
  }
  g.userData.colliders = [{ min: [-0.45, 0, -0.24], max: [0.52, 1.2, 0.24] }];
  return K.finish(game, g, { ao: { res: 32 } });
}

// ------------------------------------------------------------------------------------- tape-box floor stack
function tapeStack(game, NA, n = 4, seed = 1) {
  const g = K.prop('mc_tape_stack');
  const mt = stdMats(game);
  let y = 0;
  for (let i = 0; i < n; i++) {
    const r = (hash(seed * 3.1 + i) - 0.5) * 0.4;
    const s = Math.floor(hash(seed + i * 1.9) * 8);
    g.add(K.m(tc(K.box(0.4, 0.07, 0.4, 0.012), '#E8E0CC'), mt.paint, { pos: [0, y + 0.035, 0], rot: [0, r, 0] }));
    g.add(K.m(quad(0.38, 0.06, NA.cell('spines', [s / 8, 0.3, (s + 1) / 8, 0.7])).rotateY(PI + r), NA.mat, { pos: [Math.sin(r) * -0.201, y + 0.035, -Math.cos(r) * 0.201] }));
    y += 0.07;
  }
  g.userData.colliders = [{ min: [-0.24, 0, -0.24], max: [0.24, y, 0.24] }];
  return K.finish(game, g, { ao: { res: 24 } });
}


// Meshes added straight under the room (not through K.finish) whose material wants vertex colours get a white
// colour attribute (else the toon shader reads black where the level merge leaves a mesh alone).
function ensureColors(root) {
  root.traverse((o) => {
    if (!o.isMesh || !o.material || Array.isArray(o.material) || !o.material.vertexColors) return;
    const g = o.geometry;
    if (!g || g.attributes.color) return;
    const c = g.clone();
    c.setAttribute('color', new THREE.BufferAttribute(new Float32Array(c.attributes.position.count * 3).fill(1), 3));
    o.geometry = c;
  });
}

// Anti-static rubber floor mat: ribbed dark slate with a yellow safety edge (walkable, no collider).
function mcMatTex() {
  return K.tex.canvas('rooms.mc.floormat.v1', 128, 128, (ctx, w, h) => {
    ctx.fillStyle = '#3C4556'; ctx.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 8) { ctx.fillStyle = 'rgba(255,255,255,0.06)'; ctx.fillRect(0, y, w, 3); ctx.fillStyle = 'rgba(0,0,0,0.12)'; ctx.fillRect(0, y + 4, w, 2); }
  }, { repeat: true });
}
function floorMat(game, root, mt, x0, z0, x1, z1) {
  const w = x1 - x0, d = z1 - z0;
  const map = mcMatTex();
  const m = K.mat(game, 'rubber', '#ffffff', { map, rim: 0 });
  const g = new THREE.PlaneGeometry(w, d).rotateX(-HP);
  K.uvScale(g, w * 1.2, d * 1.2);
  root.add(K.m(tc(g, '#ffffff'), m, { pos: [(x0 + x1) / 2, 0.005, (z0 + z1) / 2], cast: false }));
  const e = 0.05;
  for (const [cx, cz, sx, sz] of [[(x0 + x1) / 2, z0 + e / 2, w, e], [(x0 + x1) / 2, z1 - e / 2, w, e], [x0 + e / 2, (z0 + z1) / 2, e, d], [x1 - e / 2, (z0 + z1) / 2, e, d]]) {
    root.add(K.m(tc(new THREE.PlaneGeometry(sx, sz).rotateX(-HP), '#E8B820'), mt.paint, { pos: [cx, 0.007, cz], cast: false }));
  }
}

// ------------------------------------------------------------------------------ transmitter meter panel (wall)
// Wall-mounted "TRANSMITTER REMOTE" panel: three big round meters (needle parts: 0 before power, the output
// swings up after), a row of lamps (lit/unlit swap), a key switch. Back at local z = 0, front -z, y = bottom.
function meterPanel(game, NA) {
  const g = K.prop('mc_meter_panel');
  const mt = stdMats(game);
  const W = 1.3, H = 0.72;
  g.add(K.m(tc(K.box(W, H, 0.08, 0.02), '#3B3645'), mt.plastic, { pos: [0, H / 2, -0.04] }));
  g.add(K.m(tc(K.box(W - 0.06, H - 0.06, 0.02, 0.012), '#D8D2C2'), mt.plastic, { pos: [0, H / 2, -0.085] }));
  const face = K.tex.canvas('rooms.mc.meterface.v1', 128, 128, (ctx, w, h) => {
    ctx.fillStyle = '#FFF4D6'; ctx.beginPath(); ctx.arc(w / 2, h / 2, 62, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = '#2A2231'; ctx.lineWidth = 3;
    for (let i = 0; i <= 10; i++) { const a = Math.PI * (1.15 + i * 0.07); ctx.beginPath(); ctx.moveTo(w / 2 + Math.cos(a) * 44, h / 2 + 12 + Math.sin(a) * 44); ctx.lineTo(w / 2 + Math.cos(a) * (i % 5 ? 50 : 54), h / 2 + 12 + Math.sin(a) * (i % 5 ? 50 : 54)); ctx.stroke(); }
    ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 6; ctx.beginPath(); ctx.arc(w / 2, h / 2 + 12, 50, Math.PI * 1.75, Math.PI * 1.85); ctx.stroke();
    ctx.fillStyle = '#2A2231'; ctx.font = '14px "Bungee", "Arial Black", sans-serif'; ctx.textAlign = 'center'; ctx.fillText('KW', w / 2, h / 2 + 36);
  }, { repeat: false, fonts: true });
  const faceMat = K.mat(game, 'plastic', '#ffffff', { map: face, rim: 0.1 });
  const needles = [];
  [-0.4, 0, 0.4].forEach((x) => {
    g.add(K.m(K.tube(Array.from({ length: 25 }, (_, i) => { const a = (i / 24) * Math.PI * 2; return [x + Math.cos(a) * 0.15, 0.42 + Math.sin(a) * 0.15, -0.1]; }), 0.012, { seg: 32, radial: 5, closed: true }), mt.chrome));
    g.add(K.m(tc(new THREE.CircleGeometry(0.145, 28).rotateY(Math.PI), '#ffffff'), faceMat, { pos: [x, 0.42, -0.097] }));
    const nd = new THREE.Group();
    nd.position.set(x, 0.42 - 0.03, -0.108);
    nd.rotation.z = 1.05;
    nd.userData.noMerge = true;
    nd.add(K.m(tc(K.box(0.008, 0.12, 0.004, 0.002), '#2A2231'), mt.plastic, { pos: [0, 0.06, 0] }));
    g.add(nd);
    needles.push(nd);
  });
  const plate = K.tex.label('TRANSMITTER', { sub: 'REMOTE CONTROL · 50 KW', bg: '#2A2231', fg: '#E8B84A', w: 256, h: 64 });
  g.add(K.m(tc(new THREE.PlaneGeometry(0.5, 0.09).rotateY(Math.PI), '#ffffff'), K.mat(game, 'plastic', '#ffffff', { map: plate, rim: 0.1 }), { pos: [0, 0.64, -0.097] }));
  const lampOn = K.glow(game, '#FF8A2A', 1.8), lampOff = K.mat(game, 'plastic', '#7A5A3A', { rim: 0.3 });
  const lamps = K.m(tc(mergeGeometries([-0.45, -0.3, -0.15, 0.15, 0.3, 0.45].map((x) => K.cyl(0.025, 0.025, 0.02, { seg: 12 }).clone().rotateX(HP).translate(x, 0.13, -0.1)), false), '#ffffff'), lampOff, { cast: false });
  lamps.userData.noMerge = true;
  g.add(lamps);
  g.add(K.m(tc(K.box(0.07, 0.07, 0.03, 0.01), '#C8963C'), mt.brass, { pos: [0, 0.13, -0.1] }));
  g.userData.parts = { needles, lamps };
  g.userData.lampMats = { on: lampOn, off: lampOff };
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0, res: 32 } });
}

// Status LED strips on top of the racks: one merged mesh whose LED colours come from a tiny live canvas (1 px per
// LED), so the whole room's blinking speckle costs one draw call. Returns { mesh, tick(real, powered) }.
function ledSpeckle(game, root, strips) {
  const canvas = typeof document !== 'undefined' ? document.createElement('canvas') : null;
  const N = strips.reduce((n, s) => n + s.n, 0);
  let tex = null;
  if (canvas) {
    canvas.width = Math.max(1, N); canvas.height = 1;
    tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.magFilter = THREE.NearestFilter; tex.minFilter = THREE.NearestFilter; tex.generateMipmaps = false;
  }
  const mt = stdMats(game);
  const geos = [], bars = [];
  const led = new THREE.SphereGeometry(0.011, 6, 4);
  let k = 0;
  const cols = [];
  for (const s of strips) {
    const dir = new THREE.Vector3(Math.cos(s.rot), 0, -Math.sin(s.rot));        // along the strip (local +x rotated)
    const out = new THREE.Vector3(-Math.sin(s.rot), 0, -Math.cos(s.rot));      // strip front (local -z rotated)
    const bar = K.box(s.len, 0.05, 0.05, 0.01).clone().rotateY(s.rot).translate(s.pos[0], s.pos[1], s.pos[2]);
    bars.push(tc(bar, '#2A2231'));
    for (let i = 0; i < s.n; i++) {
      const t = (i + 0.5) / s.n - 0.5;
      const g = led.clone();
      const uv = g.attributes.uv;
      for (let j = 0; j < uv.count; j++) uv.setXY(j, (k + 0.5) / N, 0.5);
      g.translate(s.pos[0] + dir.x * t * (s.len - 0.06) + out.x * 0.026, s.pos[1] + 0.005, s.pos[2] + dir.z * t * (s.len - 0.06) + out.z * 0.026);
      geos.push(g);
      cols.push(['#52E04A', '#FFB347', '#52E04A', '#FF3B30', '#5FE3FF', '#52E04A', '#FFB347'][k % 7]);
      k++;
    }
  }
  root.add(K.m(mergeGeometries(bars, false), mt.plastic, { cast: false }));
  const mesh = K.m(mergeGeometries(geos, false), game.mats.glow('#ffffff', 1.6, { map: tex }), { cast: false });
  mesh.userData.noMerge = true;
  root.add(mesh);
  const state = cols.map((_, i) => ({ on: hash(i) > 0.4, rate: 0.6 + hash(i * 3.7) * 3.5, t: hash(i * 1.3) }));
  let acc = 1, wasOn = null;
  const paint = (powered) => {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    state.forEach((s, i) => { ctx.fillStyle = powered && s.on ? cols[i] : '#3A3440'; ctx.fillRect(i, 0, 1, 1); });
    tex.needsUpdate = true;
  };
  paint(false);
  return {
    mesh,
    tick(real, powered) {
      acc += real;
      if (!powered) { if (wasOn !== false) { wasOn = false; paint(false); } return; }
      if (acc < 0.1 && wasOn) return;
      for (const s of state) { s.t += acc * s.rate; if (s.t >= 1) { s.t -= Math.floor(s.t); s.on = !s.on || hash(s.rate * 10 + s.t) > 0.7; } }
      acc = 0; wasOn = true;
      paint(true);
    },
  };
}

// ================================================================================================== build
export function build(game, area, root) {
  const aid = area.id;
  const rt = runtime(game, aid);
  const mt = stdMats(game);
  const NA = atlas(game);
  const MA = mcAtlas(game);
  const lvl = game.level;
  const P = (id, pos, rotY = 0, opts = {}, extra = {}) => place(game, root, id, pos, rotY, opts, { area: aid, ...extra });
  const put = (g, pos, rotY = 0, colliders = true) => {
    g.position.set(pos[0], pos[1], pos[2]);
    g.rotation.y = rotY;
    root.add(g);
    g.updateMatrixWorld(true);
    if (colliders && lvl?.col) {
      const bb = new THREE.Box3(), v = new THREE.Vector3();
      for (const c of g.userData.colliders || []) {
        bb.makeEmpty();
        for (let i = 0; i < 8; i++) { v.set(i & 1 ? c.max[0] : c.min[0], i & 2 ? c.max[1] : c.min[1], i & 4 ? c.max[2] : c.min[2]).applyMatrix4(g.matrixWorld); bb.expandByPoint(v); }
        lvl.col.addBox(bb.min.toArray(), bb.max.toArray(), { tag: 'prop' });
      }
    }
    return g;
  };
  const add = (m) => { root.add(m); return m; };
  const anchor = (id, pos, color, intensity, distance) => game.lights?.addAnchor?.({ id, pos, color, intensity, distance, area: aid });
  const setA = (id, intensity) => game.lights?.setAnchor?.(id, { intensity });
  const powered = () => !!game.machines?.powerOn;

  // ------------------------------------------------------------------------------------ the 4 x 3 monitor wall
  const wall = P('bc_monitor_wall', [31.4, 0, WALL.n + 0.26], PI, {}, { screens: false });
  const byId = {};
  if (wall) {
    const bright = K.mat(game, 'metal', '#ffffff', { map: K.tex.brushed('#C4CAD2') });
    const steel = K.mat(game, 'metal', '#ffffff', { map: K.tex.brushed('#707B8E'), env: 0.22, rim: 0.16 });
    wall.traverse((o) => { if (o.isMesh && o.material === bright) o.material = steel; });
    for (const s of wall.userData.screens) {
      const id0 = s.id || s.mesh.userData.screenId || '';
      const id = id0 === 'mcwall_r2c0' ? 'ss_mc_w' : id0 === 'mcwall_r2c3' ? 'ss_mc_e' : id0; // the prop already names them
      byId[id] = s.mesh;
      game.screens?.register?.(s.mesh, s.group || 'scr_mc_canned', id ? { id } : {});
    }
    obj(game, 'mc_monitor_wall', { area: aid, group: wall, screens: wall.userData.screens.map((s) => s.mesh), byId });
    obj(game, 'ss_mc_w', { area: aid, group: wall, screen: byId.ss_mc_w || null });
    obj(game, 'ss_mc_e', { area: aid, group: wall, screen: byId.ss_mc_e || null });
  }
  anchor('mc_wall_glow', [31.4, 1.8, -12.1], '#9FDCFF', 1.5, 6.5);
  const wallPool = pool(game, [31.4, 0.02, -12.3], 3.0, '#9FDCFF', 0.14);
  rt.power([31.4, 1.8, -13.2], (on) => {
    setA('mc_wall_glow', on ? 2.6 : 1.5);
    wallPool.set({ intensity: on ? 0.2 : 0.14 });
  }, { flicker: false });
  // producer's chair parked in front of the wall + the floor cable run to it
  P('chair_office', [32.3, 0, -11.35], 2.75, { color: PAL.burntOrange });
  P('bc_cable_spaghetti', [30.2, 0, -12.35], 0.05, { w: 3.2, d: 0.7, count: 5, seed: 13 });

  // ------------------------------------------------------------------------------------ NW corner racks
  P('bc_patch_bay', [23.64, 0, WALL.n + 0.35], PI, { seed: 21, cords: 7, color: 'slate' });
  P('bc_patch_bay', [24.28, 0, WALL.n + 0.35], PI, { seed: 5, cords: 5 });

  // ------------------------------------------------------------------------------------ west wall: rundown board
  const rb = P('rundown_board', [WALL.w + 0.03, 0.1, -11.0], -HP);
  if (rb) {
    const parts = rb.userData.parts;
    for (const k in parts) parts[k].userData.noMerge = true;
    const slots = (rb.userData.anchors?.slots || []).map((s) => rb.localToWorld(v3(s)));
    const pops = [];
    const board = obj(game, 'ee_rundown_board', {
      area: aid, group: rb, parts: { ...parts }, slots, cards: [false, false, false, false, false, false],
      setCard(n, on = true, animate = true) {
        const i = n - 1;
        if (i < 0 || i > 5 || this.cards[i] === !!on) return;
        this.cards[i] = !!on;
        setRundownCard(rb, n, on);
        const c = parts[`card_${n}`];
        if (!c) return;
        if (on && animate) {
          pops.push({ c, t: 0 });
          c.scale.setScalar(0.01);
          if (slots[i]) game.fx?.burst?.(slots[i], { shape: 'star', count: 8, speed: 1.6, size: 0.06, colors: ['#FFC23A', '#FFE3A3', '#FFFFFF'], life: 0.8 });
        } else c.scale.setScalar(1);
      },
    });
    rt.tick((dt, t, real) => {
      for (let i = pops.length - 1; i >= 0; i--) {
        const p = pops[i];
        p.t += real;
        const k = Math.min(1, p.t / 0.45);
        const e = 1 + 2.4 * (k - 1) ** 3 + 1.4 * (k - 1) ** 2;
        p.c.scale.setScalar(Math.max(0.01, e));
        p.c.rotation.z = Math.sin(p.t * 20) * 0.1 * (1 - k);
        if (k >= 1) { p.c.scale.setScalar(1); pops.splice(i, 1); }
      }
    });
    game.events?.on?.('egg:step', ({ step } = {}) => { for (let n = 1; n <= Math.min(6, step | 0); n++) board.setCard(n, true, n === (step | 0)); });
    game.events?.on?.('egg:complete', () => board.setCard(6, true));
    game.events?.on?.('game:start', () => { for (let n = 1; n <= 6; n++) board.setCard(n, false, false); });
  }
  const pl = put(pictureLight(game), [WALL.w, 2.47, -11.0], -HP, false);
  const plOn = K.glow(game, '#FFE6B0', 2.2), plOff = pl.userData.parts.glow.material;
  anchor('mc_rundown_light', [23.9, 2.2, -11.0], '#FFE0A8', 0, 3.8);
  const rbPool = pool(game, [23.9, 0.02, -11.0], 1.2, '#FFE0A8', 0);
  rt.power([23.4, 2.4, -11.0], (on) => {
    pl.userData.parts.glow.material = on ? plOn : plOff;
    setA('mc_rundown_light', on ? 1.6 : 0);
    rbPool.set({ intensity: on ? 0.14 : 0 });
  });

  // ------------------------------------------------------------------------------------ west wall: patch bays
  [[-9.3, 4, '#3B3645'], [-8.66, 9, 'charcoal'], [-8.02, 17, 'slate']].forEach(([z, seed, color], i) => {
    P('bc_patch_bay', [WALL.w + 0.35, 0, z], -HP, { seed, cords: 6 + i, color: i === 0 ? 'charcoal' : color });
  });
  const wclock = P('clock_wall', [WALL.w, 2.22, -8.66], -HP, { label: 'WZTV', size: 0.4 }, { colliders: false });
  add(K.m(qf(0.24, 0.24, MA.cell('nosmoke')), MA.mat, { pos: [WALL.w + 0.005, 2.5, -9.75], rot: [0, -HP, 0] }));

  // ------------------------------------------------------------------------------------ south wall: quad VTRs
  const vz = WALL.s - 0.43;
  const vtr = {};
  [[25.25, 1], [26.75, 2], [28.25, 3]].forEach(([x, n]) => {
    const ee = n === 2;
    const g = P('bc_vtr_quad', [x, 0, vz], 0, ee
      ? { num: 2, reels: false, lamp: 'amber', group: 'scr_vtr2', id: 'ee_vtr2_monitor', track: 3 }
      : { num: n, lamp: 'off', reels: true, group: 'scr_decor', id: `vtr${n}_monitor`, rec: n === 3 });
    if (g) vtr[n] = g;
  });
  add(K.m(qf(1.2, 0.3, MA.cell('vtrbay')), MA.mat, { pos: [26.75, 2.5, WALL.s - 0.03] }));
  add(K.m(tc(K.box(1.26, 0.34, 0.03, 0.012), '#2A2231'), mt.plastic, { pos: [26.75, 2.5, WALL.s - 0.012] }));
  put(tapeStack(game, NA, 4, 2), [24.1, 0, -2.45], 0.3);
  put(tapeStack(game, NA, 2, 5), [28.95, 0, -3.35], -0.4);
  // VTR #1 / #3: lamps go green, reels spin and VU needles bounce after power
  for (const n of [1, 3]) {
    const g = vtr[n];
    if (!g) continue;
    const p = g.userData.parts;
    for (const k of ['spindleL', 'spindleR', 'trackingKnob']) if (p[k]) p[k].userData.noMerge = false;
    const st = { spin: false, w: 0 };
    const o = obj(game, `vtr_${n}`, { area: aid, group: g, parts: { ...p }, spin(on) { st.spin = !!on; } });
    rt.power([g.position.x, 1.9, g.position.z], (on) => { setLamp(g, on ? 'green' : 'off'); o.spin(on); });
    const nl0 = p.needleL?.rotation.z ?? 0, nr0 = p.needleR?.rotation.z ?? 0;
    rt.tick((dt, t) => {
      st.w += ((st.spin ? 3.2 : 0) - st.w) * Math.min(1, dt * 1.5);
      if (st.w < 1e-3) return;
      if (p.reelL) p.reelL.rotation.z -= st.w * dt * (n === 1 ? 1 : 0.8);
      if (p.reelR) p.reelR.rotation.z -= st.w * dt * (n === 1 ? 1.35 : 1.1);
      const k = st.w / 3.2;
      if (p.needleL) p.needleL.rotation.z = nl0 + (Math.sin(t * 7.1 + n) * 0.25 + Math.sin(t * 17.3) * 0.1) * k;
      if (p.needleR) p.needleR.rotation.z = nr0 + (Math.sin(t * 6.3 + n * 2) * 0.25 + Math.sin(t * 13.7) * 0.12) * k;
    });
  }
  // VTR #2 (EE step 5): bare spindles, blinking amber lamp, TRACKING knob, loadable reels
  const v2 = vtr[2];
  if (v2) {
    const p = v2.userData.parts;
    for (const k of ['spindleL', 'spindleR', 'trackingKnob', 'lamp']) if (p[k]) p[k].userData.noMerge = true;
    for (const k of ['needleL', 'needleR']) if (p[k]) p[k].userData.noMerge = false;
    // reels to mount later: copies of VTR #1's (hidden), plus the threaded tape bands
    const src = vtr[1]?.userData.parts;
    const mk = (r, x, z0) => {
      const c = r ? r.clone(true) : new THREE.Group();
      c.position.set(x, 1.3, -0.5);
      c.rotation.z = z0;
      c.visible = false;
      c.userData.noMerge = true;
      v2.add(c);
      return c;
    };
    const reelL = mk(src?.reelL, -0.3, 0.2), reelR = mk(src?.reelR, 0.3, 1.1);
    const tape = new THREE.Group();
    tape.visible = false;
    tape.userData.noMerge = true;
    const band = (a, b) => {
      const va = v3(a), vb = v3(b), len = va.distanceTo(vb);
      const m = K.m(tc(K.box(0.006, len, 0.05, 0.002), '#A8823A'), mt.plastic, { cast: false });
      m.position.copy(va).lerp(vb, 0.5);
      m.rotation.z = Math.atan2(vb.y - va.y, vb.x - va.x) - HP;
      tape.add(m);
    };
    const tz = -0.53;
    band([-0.32, 1.16, tz], [-0.18, 1.06, tz]);
    band([-0.18, 1.045, tz], [0.18, 1.045, tz]);
    band([0.18, 1.06, tz], [0.32, 1.22, tz]);
    v2.add(tape);
    const knob = p.trackingKnob;
    const kst = { detent: 3, from: 0, to: 0, t: 1 };
    if (knob) { kst.from = kst.to = knob.rotation.y; }
    const knobPos = knob ? knob.getWorldPosition(new THREE.Vector3()) : v3(ANCHORS.ee_tracking_knob.pos);
    const lampSt = { color: 'amber', blink: true, on: true, t: 0 };
    const reelSt = { spin: false, w: 0, load: -1, dur: 1.5 };
    anchor('mc_vtr2_lamp', [26.75 + 0.42, 2.15, vz - 0.35], '#FFB347', 0.9, 3.2);
    const vtrObj = obj(game, 'ee_vtr2', {
      area: aid, group: v2, screen: v2.userData.screens[0]?.mesh || null, loaded: false, knobPos,
      parts: { ...p, reelL, reelR, tape, monitor: v2.userData.screens[0]?.mesh || null },
      lampColor: 'amber',
      setLamp(color, blink = color === 'amber') {
        this.lampColor = color;
        lampSt.color = color; lampSt.blink = !!blink && color !== 'off'; lampSt.t = 0; lampSt.on = color !== 'off';
        setLamp(v2, color === 'off' ? 'off' : color);
        setA('mc_vtr2_lamp', color === 'off' ? 0 : 0.9);
        const c = { amber: '#FFB347', green: '#52E04A', red: '#FF3B30', purple: '#B070FF' }[color];
        if (c) game.lights?.setAnchor?.('mc_vtr2_lamp', { color: c });
      },
      loadTape(seconds = 1.5) {
        if (this.loaded) return;
        this.loaded = true;
        reelSt.load = 0; reelSt.dur = Math.max(0.2, seconds);
        reelL.visible = reelR.visible = true;
        reelL.scale.setScalar(0.01); reelR.scale.setScalar(0.01);
        for (const s of [p.spindleL, p.spindleR]) if (s) s.scale.setScalar(1);
      },
      unloadTape() {
        this.loaded = false; reelSt.load = -1; reelSt.spin = false; reelSt.w = 0;
        reelL.visible = reelR.visible = tape.visible = false;
        for (const s of [p.spindleL, p.spindleR]) if (s) s.scale.setScalar(1.5);
      },
      spin(on) { reelSt.spin = !!on; },
    });
    const knobObj = obj(game, 'ee_tracking_knob', {
      area: aid, group: knob, parts: { knob }, detents: 13, pos: knobPos, detent: 3,
      set(k, animate = true) {
        const n = ((Math.round(k) % 13) + 13) % 13;
        const cur = knob ? knob.rotation.y : 0;
        let target = -n * DETENT;
        while (target - cur > PI) target -= TAU;
        while (cur - target > PI) target += TAU;
        kst.detent = n;
        this.detent = n;
        kst.from = cur; kst.to = target; kst.t = animate ? 0 : 1;
        if (!animate && knob) knob.rotation.y = target;
        return n;
      },
      turn(dir = 1) { return this.set(kst.detent + (dir < 0 ? -1 : 1)); },
    });
    knobObj.set(3, false);
    rt.tick((dt, t, real) => {
      // amber lamp blink (1 Hz, all game) — lamp part + its pooled light
      if (lampSt.blink) {
        lampSt.t += real;
        const on = (lampSt.t % 1) < 0.55;
        if (on !== lampSt.on) { lampSt.on = on; setLamp(v2, on ? lampSt.color : 'off'); setA('mc_vtr2_lamp', on ? 0.9 : 0.05); }
      }
      // knob detent click (overshoot ease)
      if (kst.t < 1 && knob) {
        kst.t = Math.min(1, kst.t + real / 0.16);
        const k = kst.t, e = 1 + 2.6 * (k - 1) ** 3 + 1.6 * (k - 1) ** 2;
        knob.rotation.y = kst.from + (kst.to - kst.from) * e;
      }
      // tape load: reels pop on (bounce), tape threads at 60 %, then they spin
      if (reelSt.load >= 0) {
        reelSt.load += real;
        const k = Math.min(1, reelSt.load / reelSt.dur);
        const a = Math.min(1, k / 0.45), e = 1 + 2.2 * (a - 1) ** 3 + 1.2 * (a - 1) ** 2;
        reelL.scale.setScalar(Math.max(0.01, e));
        reelR.scale.setScalar(Math.max(0.01, Math.min(1.2, (k - 0.15) / 0.45 > 0 ? 1 + 2.2 * (Math.min(1, (k - 0.15) / 0.45) - 1) ** 3 + 1.2 * (Math.min(1, (k - 0.15) / 0.45) - 1) ** 2 : 0.01)));
        if (k > 0.6) tape.visible = true;
        if (k >= 1) { reelSt.load = -1; reelL.scale.setScalar(1); reelR.scale.setScalar(1); reelSt.spin = true; }
      }
      reelSt.w += ((reelSt.spin ? 2.6 : 0) - reelSt.w) * Math.min(1, dt * 2);
      if (reelSt.w > 1e-3) { reelL.rotation.z -= reelSt.w * dt; reelR.rotation.z -= reelSt.w * dt * 1.25; }
    });
    game.events?.on?.('game:start', () => { vtrObj.unloadTape(); vtrObj.setLamp('amber', true); knobObj.set(3, false); });
    vtrObj.setLamp('amber', true);
  }

  // ------------------------------------------------------------------------------------ south wall: tape library
  put(tapeShelf(game, NA, MA), [30.1, 0, WALL.s - 0.22], 0);
  const mclock = P('clock_wall', [30.1, 2.52, WALL.s], 0, { size: 0.5, bezel: '#2A2231' }, { colliders: false });
  const clocks = { west: wclock?.userData.parts, master: mclock?.userData.parts };
  for (const c of [wclock, mclock]) if (c) for (const k of ['hour', 'minute', 'second']) if (c.userData.parts[k]) c.userData.parts[k].userData.noMerge = k === 'second';
  obj(game, 'mc_clocks', { area: aid, parts: clocks, set: (h, m, s) => { for (const k in clocks) setClockHands(clocks[k], h, m, s); } });
  rt.tick(() => {
    const ph = (game.time?.realNow ?? 0) % 1.6;
    const s = ph < 0.8 ? 58 + Math.min(1, ph / 0.06) : 59 - Math.min(1, (ph - 0.8) / 0.08);
    for (const k in clocks) if (clocks[k]?.second) clocks[k].second.rotation.z = (s / 60) * TAU;
  });

  // ------------------------------------------------------------------------------------ east wall: scopes, crate
  const scopes = put(scopeCart(game), [WALL.e - 0.3, 0, -10.55], HP);
  rt.power([34.3, 1.0, -10.55], (on) => { scopes.userData.parts.faces.material = on ? scopes.userData.lampMats.on : scopes.userData.lampMats.off; });
  const scopePool = pool(game, [33.9, 0.02, -10.55], 1.0, '#7CFF9A', 0);
  rt.power([34.3, 1.0, -10.6], (on) => scopePool.set({ intensity: on ? 0.1 : 0 }), { flicker: false });
  add(K.m(quad(0.5, 0.5, NA.cell('eng')).rotateY(-HP), NA.mat, { pos: [WALL.e - 0.005, 2.05, -10.55] }));
  put(extinguisher(game, MA), [WALL.e, 0.0, -5.95], HP);
  const crate = P('perpetua_crate', [33.78, 0, -4.1], -HP);
  obj(game, 'perpetua_crate', { area: aid, group: crate });
  const ad = game.cards?.get?.('perpetua_ad') || null;
  const adMat = K.mat(game, 'paint', '#ffffff', { map: ad, rim: 0.1 });
  add(K.m(new THREE.PlaneGeometry(0.6, 0.8).rotateY(-HP), adMat, { pos: [WALL.e - 0.006, 1.5, -4.1], rot: [0.03, 0, 0] }));
  for (const [dy, dz] of [[0.38, -0.28], [0.38, 0.28], [-0.38, -0.28], [-0.38, 0.28]]) add(K.m(tc(K.box(0.004, 0.05, 0.12, 0.002), '#9A9284'), mt.paint, { pos: [WALL.e - 0.008, 1.5 + dy, -4.1 + dz], rot: [dz * 1.5, 0, 0], cast: false }));
  add(K.m(new THREE.PlaneGeometry(0.34, 0.45).rotateX(-HP), adMat, { pos: [32.7, 0.006, -4.75], rot: [0, 0.5, 0], cast: false }));

  // ------------------------------------------------------------------------------------ centre: toys + chairs
  const laffPos = ANCHORS.toy_laff_o_matic.pos, swPos = ANCHORS.toy_switcher.pos;
  const laff = put(laffCart(game, NA), [laffPos[0] + 0.1, 0, laffPos[2] - 0.02], PI - 0.08);
  const sw = put(routerCart(game, MA), [swPos[0] - 0.05, 0, swPos[2] - 0.02], PI + 0.08);
  P('chair_office', [27.1, 0, -7.35], 0.6, { color: PAL.harvestGold });
  P('chair_office', [31.15, 0, -7.3], -0.45, { color: PAL.burntOrange });
  // spilled coffee by the console + a tipped mug, papers
  add(K.m(quad(0.7, 0.7, NA.dcell('stain')), NA.decal, { pos: [30.8, 0.004, -6.7], rot: [-HP, 0, 0.6], cast: false }));
  add(K.m(tc(K.lathe([[0, 0], [0.036, 0], [0.04, 0.09], [0.036, 0.09], [0.032, 0.008], [0, 0.008]], { seg: 14 }), PAL.wztvBlue), mt.lacquer, { pos: [30.55, 0.04, -6.85], rot: [HP, 0.4, 0] }));
  for (const [cell, x, z, r] of [['page', 27.7, -6.6, 0.4], ['wire', 25.4, -6.0, -0.7], ['sched', 32.3, -8.9, 1.1], ['page', 24.6, -10.4, 2.2]]) {
    add(K.m(quad(0.22, 0.28, NA.cell(cell)), NA.mat, { pos: [x, 0.006, z], rot: [-HP, 0, r], cast: false }));
  }
  add(K.m(quad(1.6, 1.6, NA.dcell('scuff')), NA.decal, { pos: [26.8, 0.004, -5.0], rot: [-HP, 0, 0.2], cast: false }));
  add(K.m(quad(1.2, 1.2, NA.dcell('tapeX')), NA.decal, { pos: [29.0, 0.004, -11.3], rot: [-HP, 0, 0.1], cast: false }));

  // ------------------------------------------------------------------------------------ overhead cable trays
  const ceil = area.ceilY ?? 3.6;
  const trayY = ceil - 0.36;
  put(cableTray(game, 11.2, 0.36), [29.0, trayY, -11.2], 0, false);
  put(cableTray(game, 7.2, 0.36), [23.75, trayY, -9.9], HP, false);
  loom(root, mt, [30.4, trayY, -11.3], [30.4, 3.52, -13.45], 0.12, 1);
  loom(root, mt, [33.6, trayY, -11.3], [33.6, 3.52, -13.45], 0.12, 2);
  loom(root, mt, [29.0, trayY, -11.1], [29.0, 1.22, -9.7], 0.2, 3);
  loom(root, mt, [23.75, trayY, -12.9], [23.95, 1.99, -13.2], 0.1, 4);
  for (const z of [-9.3, -8.66, -8.02]) loom(root, mt, [23.75, trayY, z], [23.5, 1.99, z], 0.08, 5 + z);
  for (const x of [25.25, 26.75, 28.25]) loom(root, mt, [x - 0.3, ceil - 0.02, -2.4], [x - 0.3, 2.02, -2.45], 0.04, 9 + x);

  // ------------------------------------------------------------------------------------------------ toys
  const LM = laff.userData.lampMats, lp = laff.userData.parts;
  const lst = { t: -1, next: 0 };
  const laffPlay = () => {
    const now = game.time?.realNow ?? 0;
    if (now < lst.next) return;
    lst.next = now + 10;
    lst.t = 0;
    game.audio?.play?.('toy_laff', { pos: v3(laffPos), tv: true });
    game.events?.emit?.('toy:use', { id: 'toy_laff_o_matic' });
  };
  toy(game, 'toy_laff_o_matic', laffPos, laffPlay, { radius: 1.4, cooldown: 0.3 });
  obj(game, 'laff_o_matic', { area: aid, group: laff, parts: { ...lp }, play: laffPlay });
  const n0 = lp.needle.rotation.z, b0 = lp.button.position.y;
  rt.tick((dt, t, real) => {
    if (lst.t < 0) return;
    lst.t += real;
    const k = lst.t;
    const press = k < 0.08 ? k / 0.08 : Math.max(0, 1 - (k - 0.08) / 0.12);
    lp.button.position.y = b0 - press * 0.022;
    lp.button.scale.set(1 + press * 0.12, 1 - press * 0.3, 1 + press * 0.12);
    const on = k < 2.6;
    const f = Math.floor(k * 6);
    lp.lampL.material = on && f % 2 === 0 ? LM.on : LM.off;
    lp.lampR.material = on && f % 2 === 1 ? LM.onR : LM.offR;
    lp.needle.rotation.z = on ? n0 - 0.6 - Math.abs(Math.sin(k * 11)) * 0.5 - Math.sin(k * 23) * 0.15 : n0;
    if (!on && k > 2.7) { lst.t = -1; lp.button.position.y = b0; lp.button.scale.set(1, 1, 1); }
  });

  const kc = sw.userData.keyCanvas, kt = sw.userData.keyTex;
  const sst = { t: -1, handle: null };
  paintKeys(kc, kt, 'idle', 0, false);
  rt.power([28.0, 1.0, -8.3], (on) => { if (sst.t < 0) paintKeys(kc, kt, 'idle', 0, on); }, { flicker: false });
  const swPlay = () => {
    sst.t = 0;
    game.audio?.play?.('toy_switcher', { pos: v3(swPos) });
    const S = game.screens;
    if (S && powered()) {
      const feeds = ['lobby', 'newsroom', 'studio_a', 'studio_b'];
      const a = S._aArea;
      const pick = feeds.filter((f) => f !== a);
      const f = pick[Math.floor(Math.random() * pick.length)] || 'lobby';
      try { sst.handle?.cancel?.(); sst.handle = S.override?.(`feed_${f}`, ['scr_mc_feeds', 'scr_mc_canned'], 5, 7.5) || null; } catch (err) { console.warn('[rooms:master_control] switcher', err); }
    } else if (S?.blink) {
      try { S.blink(['scr_mc_feeds', 'scr_mc_canned'], { spread: 0.4, dur: 0.25 }); } catch (err) { /* optional */ }
    }
    game.events?.emit?.('toy:use', { id: 'toy_switcher' });
  };
  toy(game, 'toy_switcher', swPos, swPlay, { radius: 1.4, cooldown: 0.5 });
  obj(game, 'mc_switcher', { area: aid, group: sw, parts: { ...sw.userData.parts }, play: swPlay });
  let keyT = 0;
  rt.tick((dt, t, real) => {
    if (sst.t < 0) return;
    sst.t += real;
    keyT += real;
    if (keyT > 0.08) { keyT = 0; paintKeys(kc, kt, 'chase', sst.t, true); }
    if (sst.t > 5) { sst.t = -1; paintKeys(kc, kt, 'idle', 0, powered()); }
  });
  game.events?.on?.('game:start', () => { sst.handle?.cancel?.(); sst.handle = null; sst.t = -1; lst.next = 0; });

  // ------------------------------------------------------------------------------------ floor mats + meter panel
  floorMat(game, root, mt, 26.3, -11.5, 31.8, -6.7);
  floorMat(game, root, mt, 24.4, -4.7, 29.2, -3.25);
  floorMat(game, root, mt, 28.6, -13.3, 34.3, -11.75);
  const mp = put(meterPanel(game, NA), [WALL.e, 1.55, -12.35], HP, false);
  const mpn = mp.userData.parts.needles;
  const mst = { on: false, k: 0 };
  rt.power([34.8, 1.9, -12.35], (on) => { mst.on = on; mp.userData.parts.lamps.material = on ? mp.userData.lampMats.on : mp.userData.lampMats.off; });
  rt.tick((dt, t) => {
    mst.k += ((mst.on ? 1 : 0) - mst.k) * Math.min(1, dt * 1.2);
    mpn.forEach((n, i) => { n.rotation.z = 1.05 - mst.k * (1.2 + i * 0.25) - (mst.k > 0.5 ? Math.sin(t * (2 + i) + i) * 0.04 : 0); });
  });

  // a tape cart parked by the library shelf + the oscillating floor fan in the SE corner (runs after power)
  put(tapeCart(game, NA), [30.35, 0, -3.5], 0.08);
  const fan = put(floorFan(game), [33.2, 0, -2.58], PI / 4);
  const fp = fan.userData.parts;
  const fst = { on: false, w: 0 };
  rt.power([33.2, 1.1, -2.6], (on) => { fst.on = on; }, { flicker: false });
  rt.tick((dt, t) => {
    fst.w += ((fst.on ? 14 : 0) - fst.w) * Math.min(1, dt * 0.8);
    if (fst.w < 0.01) return;
    fp.blades.rotation.z -= fst.w * dt;
    fp.head.rotation.y = Math.sin(t * 0.35) * 0.6 * Math.min(1, fst.w / 14);
  });

  // status LED speckle on the racks + scope cart (blinks after power)
  const leds = ledSpeckle(game, root, [
    { pos: [23.64, 2.02, WALL.n + 0.6], rot: PI, len: 0.56, n: 8 },
    { pos: [24.28, 2.02, WALL.n + 0.6], rot: PI, len: 0.56, n: 8 },
    ...[-9.3, -8.66, -8.02].map((z) => ({ pos: [WALL.w + 0.6, 2.02, z], rot: -HP, len: 0.56, n: 8 })),
    { pos: [WALL.e - 0.42, 1.1, -10.55], rot: HP, len: 0.5, n: 6 },
  ]);
  rt.tick((dt, t, real) => leds.tick(real, powered()));

  ensureColors(root);
  return rt;
}
