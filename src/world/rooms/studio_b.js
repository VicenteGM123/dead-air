// Studio B — "HOOTIE'S HULLABALOO" (the kids' show) set dressing (GDD §5.7 "Studio B", lighting §3.3, toys §13,
// EE step 2 theater §13 / §18.13). Owner: rooms-studio-b. Uses the shared studio kit exported by rooms/studio_a.js.
//
// build(game, area, root)  called by level.js after the graybox; the level merges static meshes per material afterwards.
// Everything animated or swapped at runtime lives in noMerge groups (or is a noMerge prop part).
//
// Layout (GDD §5.6/§5.7 + layout ANCHORS): cardboard rocket [22,0,-21] (the loop pillar, porthole facing D7 / the
// shot camera), treehouse facade [25.5,0,-27.6] with Hootie's giant TV = screen spawn ss_studio_b (scr_decor, loops
// 'hullabaloo'), the striped puppet theater (ee_puppet_theater, apron slots on the GDD sill line z -25.5), the blue
// chroma-key cyclorama on the east wall (narrowed to 3.3 m so it clears the treehouse), three 1 m ABC blocks, the
// rainbow arch FRAMING THE D6 ELEPHANT DOOR (GDD spot [24.5,-15.5] puts a cloud foot inside D7's doorway and, moved
// onto D7, the arch fills the cam_studio_b lens), the toy train loop (toy_train, x0.85, centre [18.95,-20.45] in the
// gap between the rainbow, block 1, the rocket and the Wobble-Up sponsor camera, whose footprint covers the GDD toy
// anchor), the xylophone (toy_xylophone), giant crayons, a rainbow story rug + bean bags (kept out of the theater's
// and the xylophone's approaches), the feed camera + stand monitor (scr_feed_studio_b), a painted "Hullabaloo Hills"
// flat, a toy piano, a toy chest, sunflower cut-outs, Hootie's costume rack by D7, the Sockettes' clothesline, balloon
// clusters, star/planet/cloud mobiles, bunting, fairy lights, wall cut-outs, star confetti, kid drawings, signage.
// Left clear for other agents: set_wobble_up (SW 3x3 + its camera), telly_home_studio_b (T4, east), 2 m in front of
// D6, D7, B11, B12 and the TV spawn.
//
// Power (GDD §3.3): before Sign-On the room is lit by the moon night-light in the treehouse window, a glowing paper-moon
// lantern and dim fairy lights (+ a blue moon pool). When the Sign-On colour wave reaches each item: pastel gel
// Fresnels light (pink / lilac / yellow / cyan) with soft beams on the theater and Hootie's TV, pink + lilac fill
// anchors, pastel floor pools, brighter fairy lights, the cyc floods. (The level owns the grid key light #FFF1C9.)
//
// game.level.objects (world space):
//   ee_puppet_theater { group, parts:{ curtain (Group: both halves), curtain_l, curtain_r, slot_owl, slot_sock,
//                       slot_dragon (Object3Ds on the playboard ledge, where a slotted puppet sits), sil_owl, sil_sock,
//                       sil_dragon (golden silhouette overlays on the apron, hidden until filled) },
//                       slots:{ owl|sock|dragon: Vector3 } (ledge seats above each painted silhouette),
//                       stage:{ owl|sock|dragon: Vector3 } (behind the curtain line, for the kazoo song),
//                       puppetOf:{ owl:'ee_puppet_hootie', sock:'ee_puppet_sockrates', dragon:'ee_puppet_dudley' },
//                       keyOf:{ ee_puppet_hootie:'owl', ... }, interact:Vector3 (GDD [17.75,0,-24.9]), interactR:1.5,
//                       filled:{ owl, sock, dragon }, open (0..1), setOpen(k, seconds = 0.8), setSlot(key, on) (gold
//                       silhouette + sparkle burst), reset() }   (the EE agent registers the [E] interaction itself)
//   ss_studio_b       { group, screen }   Hootie's TV (screen registered as scr_decor / ss_studio_b)
//   cardboard_rocket  { group }            treehouse { group, parts }     chroma_cyc { group, mark:Vector3 }
//   rainbow_arch      { group }            alpha_blocks { groups:[g1,g2,g3] }
//   toy_train         { group, parts:{ train }, running, run(laps = 2) }
//   toy_xylophone     { group, parts:{ bars, mallets }, play(barIndices?) -> seconds }
//   feed_cam_studio_b { group, parts:{ head, tilt, tally, lensTip } } (physical camera; screens.js owns the feed camera)
//   mon_studio_b_stand { group, screen }   studio_b { rt, root, dyn }  (debug)
// Toys (key-only [E] prompts, GDD §13): toy_train ('toy_train': toots, circles twice puffing smoke; [E] point = loop centre),
//   toy_xylophone ('toy_xylophone' with 3 random pentatonic bars: the struck bars bounce, the mallets tap).
//   Both emit 'toy:use' {id}.

import * as THREE from 'three';
import * as K from '../../props/kit.js';
import { PAL } from '../../core/config.js';
import { ANCHORS } from '../layout.js';
import { drawTo } from '../../gfx/cards.js';
import {
  runtime, place, studioMats, makeAtlas, quad, tg, unlockParts, harvestLenses, feedCamera, standMonitor,
  txt, rr, FONT, yawTo, starPath,
} from './studio_a.js';

const TAU = Math.PI * 2;
const HP = Math.PI / 2;
const AREA = 'studio_b';
const GRID_Y = 5.0;                       // surfaces.js studio_b gridY (pipes along x at 5.0, along z at 5.09)
const GX = [16.67, 18.8, 20.93, 23.07, 25.2, 27.33];      // z-running pipes (x fixed)
const GZ = [-26.33, -24.2, -22.07, -19.93, -17.8, -15.67]; // x-running pipes (z fixed)
const W = { w: 15.155, e: 28.845, n: -27.845, s: -14.155 }; // inner wall faces
const v3 = (p) => (p.isVector3 ? p.clone() : new THREE.Vector3(p[0], p[1] ?? 0, p[2]));
const PASTEL = ['#FF8FB8', '#FFB347', '#FFE45C', '#8CE07A', '#6FD3F0', '#9E8CFF', '#FF6F91'];

function mulberry(a) {
  return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// ============================================================================================ Studio B atlas
const REG_B = {
  logo: [0, 0, 1024, 300],
  peanut: [640, 300, 384, 96],
  clap: [640, 396, 384, 104],
  drawings: [0, 500, 480, 240],
  sunflower: [480, 500, 176, 280],
  poster: [656, 500, 144, 192],
  cloud: [800, 500, 224, 128],
  star: [800, 628, 72, 72],
  moon: [872, 628, 72, 72],
  note: [944, 628, 80, 72],
  saturn: [656, 692, 160, 96],
  raindrop: [816, 700, 64, 80],
  spike: [880, 700, 72, 72],
  heart: [952, 700, 72, 72],
  launch: [0, 740, 256, 256],
  cue1: [256, 740, 160, 112],
  cue2: [256, 852, 160, 112],
  piano: [416, 780, 240, 56],
  pianoLbl: [416, 836, 240, 40],
  chest: [416, 876, 240, 104],
  signB: [656, 788, 240, 112],
  countdown: [656, 900, 240, 112],
  sock: [896, 780, 128, 128],
  eyes: [896, 908, 128, 104],
  white: [1000, 1014, 24, 10],
};
const WHITE_UV = [(1000 + 12) / 1024, 1 - (1014 + 5) / 1024];
// uv of every vertex -> the white atlas block (vertex-coloured sticks merge with the atlas cut-outs: one draw)
function solidUV(geo) {
  const uv = geo.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, WHITE_UV[0], WHITE_UV[1]);
  uv.needsUpdate = true;
  return geo;
}
// sub-cell of the drawings region (3 x 2 cells of 160 x 120)
const drawingUV = (A, i) => {
  const [x, y] = REG_B.drawings, cx = x + (i % 3) * 160, cy = y + Math.floor(i / 3) * 120, S = 1024;
  return [cx / S, 1 - (cy + 120) / S, (cx + 160) / S, 1 - cy / S];
};

function owlFace(ctx, x, y, s, { body = '#8A5A3A', belly = '#C89A6A' } = {}) {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s);
  ctx.fillStyle = body;
  ctx.beginPath(); ctx.moveTo(-40, -30); ctx.lineTo(-52, -70); ctx.lineTo(-14, -48); ctx.lineTo(14, -48); ctx.lineTo(52, -70); ctx.lineTo(40, -30); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.ellipse(0, 0, 58, 54, 0, 0, TAU); ctx.fill();
  ctx.fillStyle = belly; ctx.beginPath(); ctx.ellipse(0, 22, 30, 26, 0, 0, TAU); ctx.fill();
  for (const sd of [-1, 1]) {
    ctx.fillStyle = '#FFF8E8'; ctx.beginPath(); ctx.arc(sd * 24, -8, 22, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#F4A020'; ctx.lineWidth = 5; ctx.stroke();
    ctx.fillStyle = '#2A1D3A'; ctx.beginPath(); ctx.arc(sd * 21, -6, 11, 0, TAU); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(sd * 17, -11, 4, 0, TAU); ctx.fill();
  }
  ctx.fillStyle = '#F4A020'; ctx.beginPath(); ctx.moveTo(-9, 12); ctx.lineTo(9, 12); ctx.lineTo(0, 27); ctx.closePath(); ctx.fill();
  ctx.restore();
}

function crayonLine(ctx, pts, color, w = 5, rand = Math.random) {
  ctx.strokeStyle = color; ctx.lineWidth = w; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  for (let pass = 0; pass < 2; pass++) {
    ctx.globalAlpha = pass ? 0.55 : 0.9;
    ctx.beginPath();
    pts.forEach(([x, y], i) => { const jx = (rand() - 0.5) * 2.4, jy = (rand() - 0.5) * 2.4; if (i) ctx.lineTo(x + jx, y + jy); else ctx.moveTo(x + jx, y + jy); });
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
}
const circlePts = (cx, cy, r, n = 18, ry = r) => Array.from({ length: n + 1 }, (_, i) => [cx + Math.cos((i / n) * TAU) * r, cy + Math.sin((i / n) * TAU) * ry]);

// Painted "Hullabaloo Hills" flat (own 1024x576 canvas: the 5 m backdrop needs the resolution): sky, smiling sun,
// clouds, rainbow, rolling hills, flowers, the WZTV tower on a far hill. Drawn in a 1024x300 design space, scaled.
function hillsTex() {
  return K.tex.canvas('sb_hills_v1', 1024, 576, (ctx, W0, H0, rand) => {
    const ink = '#3A1E2E';
    const x = 0, y = 0, w = W0, h = 300;
    ctx.save(); ctx.translate(x, y); ctx.scale(1, H0 / 300);
    let g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, '#7CC8FF'); g.addColorStop(0.6, '#BFE6FF'); g.addColorStop(1, '#E6F6FF');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    // brush texture on the sky
    for (let i = 0; i < 80; i++) { ctx.strokeStyle = `rgba(255,255,255,${0.05 + rand() * 0.08})`; ctx.lineWidth = 2 + rand() * 4; const xx = rand() * w, yy = rand() * h * 0.6; ctx.beginPath(); ctx.moveTo(xx, yy); ctx.lineTo(xx + 30 + rand() * 60, yy + (rand() - 0.5) * 6); ctx.stroke(); }
    // rainbow behind the hills
    const rc = ['#FF6F6F', '#FFB347', '#FFE45C', '#8CE07A', '#6FD3F0', '#9E8CFF'];
    rc.forEach((c, i) => { ctx.strokeStyle = c; ctx.lineWidth = 13; ctx.beginPath(); ctx.arc(700, 300, 190 - i * 13, Math.PI, TAU); ctx.stroke(); });
    // smiling sun with rays
    const sx = 150, sy = 92;
    ctx.fillStyle = '#FFB347';
    for (let i = 0; i < 14; i++) { const a = (i / 14) * TAU; ctx.beginPath(); ctx.moveTo(sx + Math.cos(a - 0.12) * 60, sy + Math.sin(a - 0.12) * 60); ctx.lineTo(sx + Math.cos(a) * 92, sy + Math.sin(a) * 92); ctx.lineTo(sx + Math.cos(a + 0.12) * 60, sy + Math.sin(a + 0.12) * 60); ctx.fill(); }
    ctx.fillStyle = '#FFD23A'; ctx.beginPath(); ctx.arc(sx, sy, 62, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#F29A1E'; ctx.lineWidth = 5; ctx.stroke();
    ctx.fillStyle = ink; for (const sd of [-1, 1]) { ctx.beginPath(); ctx.ellipse(sx + sd * 20, sy - 10, 7, 11, 0, 0, TAU); ctx.fill(); }
    ctx.fillStyle = 'rgba(255,110,120,0.5)'; for (const sd of [-1, 1]) { ctx.beginPath(); ctx.arc(sx + sd * 36, sy + 10, 10, 0, TAU); ctx.fill(); }
    ctx.strokeStyle = ink; ctx.lineWidth = 5; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(sx, sy + 6, 24, 0.2, Math.PI - 0.2); ctx.stroke();
    // puffy clouds
    const cloud = (cx, cy, s) => {
      ctx.fillStyle = '#FFFFFF';
      for (const [dx, dy, r] of [[-38, 6, 24], [-12, -10, 32], [20, -4, 28], [44, 8, 20], [0, 12, 26]]) { ctx.beginPath(); ctx.arc(cx + dx * s, cy + dy * s, r * s, 0, TAU); ctx.fill(); }
      ctx.fillStyle = 'rgba(150,190,230,0.35)'; ctx.fillRect(cx - 60 * s, cy + 22 * s, 120 * s, 6 * s);
    };
    cloud(420, 70, 1.1); cloud(880, 58, 0.95); cloud(640, 118, 0.7);
    // hills (back to front) with scalloped tops
    const hill = (y0, amp, col, ph, dark) => {
      ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(0, h);
      for (let xx = 0; xx <= w; xx += 8) ctx.lineTo(xx, y0 - Math.sin(xx * 0.006 + ph) * amp - Math.sin(xx * 0.017 + ph * 2) * amp * 0.25);
      ctx.lineTo(w, h); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = dark; ctx.lineWidth = 4; ctx.beginPath();
      for (let xx = 0; xx <= w; xx += 8) { const yy = y0 - Math.sin(xx * 0.006 + ph) * amp - Math.sin(xx * 0.017 + ph * 2) * amp * 0.25; if (xx) ctx.lineTo(xx, yy); else ctx.moveTo(xx, yy); }
      ctx.stroke();
    };
    hill(205, 34, '#9ED86A', 0.4, '#7DBE52');
    // the WZTV tower on the far hill (station in-joke)
    { const tx = 905, ty = 172; ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(tx - 12, ty); ctx.lineTo(tx, ty - 70); ctx.lineTo(tx + 12, ty); ctx.stroke(); for (let i = 1; i < 5; i++) { ctx.beginPath(); ctx.moveTo(tx - 12 + i * 2.4, ty - i * 14); ctx.lineTo(tx + 12 - i * 2.4, ty - i * 14); ctx.stroke(); } ctx.fillStyle = '#FF3B30'; ctx.beginPath(); ctx.arc(tx, ty - 72, 5, 0, TAU); ctx.fill(); }
    hill(236, 28, '#7FCB55', 2.2, '#63AE43');
    hill(270, 22, '#62B845', 4.1, '#4E9A36');
    // winding path + flowers + a little mushroom house
    ctx.fillStyle = '#F2D9A6'; ctx.beginPath(); ctx.moveTo(460, h); ctx.bezierCurveTo(520, 270, 420, 250, 520, 228); ctx.lineTo(532, 230); ctx.bezierCurveTo(450, 256, 560, 272, 520, h); ctx.fill();
    for (let i = 0; i < 70; i++) {
      const fx = rand() * w, fy = 225 + rand() * 70, c = ['#FF8FB8', '#FFE45C', '#FFFFFF', '#FF6F6F', '#B9A2FF'][i % 5], r = 3 + rand() * 3;
      ctx.fillStyle = c; for (let k = 0; k < 5; k++) { const a = (k / 5) * TAU; ctx.beginPath(); ctx.arc(fx + Math.cos(a) * r, fy + Math.sin(a) * r, r * 0.75, 0, TAU); ctx.fill(); }
      ctx.fillStyle = '#FFB347'; ctx.beginPath(); ctx.arc(fx, fy, r * 0.55, 0, TAU); ctx.fill();
    }
    { const mx = 300, my = 250; ctx.fillStyle = '#FFF4DC'; rr(ctx, mx - 18, my - 10, 36, 34, 8); ctx.fill(); ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.ellipse(mx, my - 12, 40, 26, 0, Math.PI, TAU); ctx.fill(); ctx.fillStyle = '#FFF'; for (const [dx, dy] of [[-18, -22], [8, -28], [22, -16]]) { ctx.beginPath(); ctx.arc(mx + dx, my + dy, 5, 0, TAU); ctx.fill(); } ctx.fillStyle = '#8A5A3A'; rr(ctx, mx - 6, my + 6, 12, 18, 5); ctx.fill(); }
    ctx.restore();
    // painted border
    ctx.lineWidth = 12; ctx.strokeStyle = '#FF8FB8'; rr(ctx, 6, 6, W0 - 12, H0 - 12, 26); ctx.stroke();
  }, { repeat: false, fonts: false });
}

function drawStudioB(ctx, R, rand) {
  const ink = '#3A1E2E';
  // ---- show logo banner
  {
    const [x, y, w0, h0] = R('logo');
    const w = 640, h = 200;
    ctx.save(); ctx.translate(x, y); ctx.scale(w0 / w, h0 / h);
    rr(ctx, 4, 4, w - 8, h - 8, 44); ctx.fillStyle = '#FF8FB8'; ctx.fill();
    ctx.lineWidth = 10; ctx.strokeStyle = '#FFE45C'; rr(ctx, 14, 14, w - 28, h - 28, 36); ctx.stroke();
    for (let i = 0; i < 26; i++) { ctx.fillStyle = `rgba(255,255,255,${0.25 + rand() * 0.3})`; starPath(ctx, 30 + rand() * (w - 60), 26 + rand() * (h - 52), 5 + rand() * 4, 2); ctx.fill(); }
    owlFace(ctx, 110, 108, 1.15);
    txt(ctx, "Hootie's", 380, 62, { font: FONT.groovy, size: 58, fill: '#FFE45C', stroke: '#5A1E3E', lw: 9, shadow: 'rgba(0,0,0,0.25)' });
    const word = 'HULLABALOO!';
    const cols = ['#E23B3B', '#FF8A2A', '#FFD23A', '#52D24A', '#3FD6E0', '#3A58E4', '#B05AD6'];
    ctx.font = `64px ${FONT.round}`;
    const total = ctx.measureText(word).width * 0.92;
    let cx = 380 - total / 2;
    [...word].forEach((ch, i) => {
      const cw = ctx.measureText(ch).width * 0.92;
      txt(ctx, ch, cx + cw / 2, 136 + Math.sin(i * 1.1) * 7, { font: FONT.round, size: 64, fill: cols[i % cols.length], stroke: '#FFFFFF', lw: 9, rot: Math.sin(i * 1.7) * 0.12, shadow: 'rgba(90,30,62,0.45)' });
      cx += cw;
    });
    ctx.restore();
  }
  // ---- PEANUT GALLERY plank
  {
    const [x, y, w, h] = R('peanut');
    ctx.save(); ctx.translate(x, y);
    rr(ctx, 2, 2, w - 4, h - 4, 30); ctx.fillStyle = '#C8904E'; ctx.fill();
    for (let i = 0; i < 16; i++) { ctx.strokeStyle = 'rgba(90,50,20,0.22)'; ctx.lineWidth = 1.5; const yy = 10 + rand() * (h - 20); ctx.beginPath(); ctx.moveTo(10, yy); ctx.bezierCurveTo(w * 0.3, yy + 4, w * 0.6, yy - 4, w - 10, yy + 2); ctx.stroke(); }
    ctx.lineWidth = 6; ctx.strokeStyle = '#7A4A2A'; rr(ctx, 8, 8, w - 16, h - 16, 24); ctx.stroke();
    const peanut = (px, py, r) => { ctx.save(); ctx.translate(px, py); ctx.rotate(r); ctx.fillStyle = '#E8C27A'; ctx.beginPath(); ctx.ellipse(0, -9, 10, 12, 0, 0, TAU); ctx.ellipse(0, 10, 11, 13, 0, 0, TAU); ctx.fill(); ctx.strokeStyle = '#9A6A3A'; ctx.lineWidth = 2; ctx.stroke(); ctx.restore(); };
    peanut(34, h / 2, 0.4); peanut(w - 34, h / 2, -0.4);
    txt(ctx, 'PEANUT GALLERY', w / 2, h / 2 + 2, { font: FONT.round, size: 40, fill: '#FFF6E0', stroke: '#5A3A22', lw: 7, maxW: w - 100 });
    ctx.restore();
  }
  // ---- CLAP ALONG! sign
  {
    const [x, y, w, h] = R('clap');
    ctx.save(); ctx.translate(x, y);
    rr(ctx, 3, 3, w - 6, h - 6, 26); ctx.fillStyle = '#3A58E4'; ctx.fill();
    ctx.lineWidth = 7; ctx.strokeStyle = '#FFE45C'; rr(ctx, 11, 11, w - 22, h - 22, 20); ctx.stroke();
    for (let i = 0; i < 12; i++) { ctx.fillStyle = i % 2 ? '#FFE45C' : '#FF8FB8'; ctx.beginPath(); ctx.arc(24 + i * ((w - 48) / 11), 11, 5, 0, TAU); ctx.fill(); ctx.beginPath(); ctx.arc(24 + i * ((w - 48) / 11), h - 11, 5, 0, TAU); ctx.fill(); }
    txt(ctx, 'CLAP ALONG!', w / 2, h / 2 + 2, { font: FONT.sign, size: 44, fill: '#FFFFFF', stroke: '#1B2F7A', lw: 6, maxW: w - 60 });
    ctx.restore();
  }
  // ---- kid drawings (6 cells)
  {
    const [x0, y0] = R('drawings');
    const papers = ['#FFFBEF', '#FFF0F6', '#EFF8FF', '#FFFBE0', '#F2FFEF', '#FFF4E8'];
    for (let i = 0; i < 6; i++) {
      const x = x0 + (i % 3) * 160, y = y0 + Math.floor(i / 3) * 120;
      ctx.save(); ctx.translate(x, y);
      ctx.fillStyle = papers[i]; ctx.fillRect(0, 0, 160, 120);
      ctx.fillStyle = 'rgba(0,0,0,0.05)'; ctx.fillRect(0, 116, 160, 4);
      if (i === 0) { // Hootie
        crayonLine(ctx, circlePts(80, 64, 34, 16, 30), '#8A5A3A', 7, rand);
        crayonLine(ctx, circlePts(66, 58, 10), '#3A2A2A', 4, rand); crayonLine(ctx, circlePts(94, 58, 10), '#3A2A2A', 4, rand);
        crayonLine(ctx, [[74, 74], [86, 74], [80, 84], [74, 74]], '#F4A020', 5, rand);
        crayonLine(ctx, [[54, 40], [50, 22], [66, 36]], '#8A5A3A', 5, rand); crayonLine(ctx, [[106, 40], [110, 22], [94, 36]], '#8A5A3A', 5, rand);
        txt(ctx, 'HOOTIE', 80, 108, { font: FONT.round, size: 17, fill: '#E23B3B', rot: -0.05 });
      } else if (i === 1) { // house + sun
        crayonLine(ctx, [[40, 100], [40, 60], [80, 34], [120, 60], [120, 100], [40, 100]], '#E23B3B', 5, rand);
        crayonLine(ctx, [[70, 100], [70, 78], [88, 78], [88, 100]], '#3A58E4', 4, rand);
        crayonLine(ctx, circlePts(136, 22, 12), '#FFB020', 5, rand);
        for (let k = 0; k < 8; k++) { const a = (k / 8) * TAU; crayonLine(ctx, [[136 + Math.cos(a) * 16, 22 + Math.sin(a) * 16], [136 + Math.cos(a) * 24, 22 + Math.sin(a) * 24]], '#FFB020', 3, rand); }
        crayonLine(ctx, [[8, 108], [152, 108]], '#52C24A', 6, rand);
      } else if (i === 2) { // Telly the TV with legs (a kid who knows)
        crayonLine(ctx, [[46, 30], [114, 30], [118, 84], [42, 84], [46, 30]], '#8A5A3A', 6, rand);
        crayonLine(ctx, [[56, 40], [104, 40], [104, 74], [56, 74], [56, 40]], '#6FD3F0', 5, rand);
        crayonLine(ctx, [[68, 52], [70, 54]], '#222', 5, rand); crayonLine(ctx, [[92, 52], [94, 54]], '#222', 5, rand);
        crayonLine(ctx, [[68, 64], [80, 70], [92, 64]], '#222', 4, rand);
        crayonLine(ctx, [[60, 84], [56, 110]], '#8A5A3A', 5, rand); crayonLine(ctx, [[100, 84], [104, 110]], '#8A5A3A', 5, rand);
        crayonLine(ctx, [[70, 30], [56, 10]], '#999', 3, rand); crayonLine(ctx, [[90, 30], [104, 10]], '#999', 3, rand);
      } else if (i === 3) { // rocket
        crayonLine(ctx, [[80, 12], [96, 40], [96, 88], [64, 88], [64, 40], [80, 12]], '#E23B3B', 5, rand);
        crayonLine(ctx, circlePts(80, 54, 9), '#3A58E4', 4, rand);
        crayonLine(ctx, [[64, 70], [48, 94], [64, 88]], '#FF8A2A', 4, rand); crayonLine(ctx, [[96, 70], [112, 94], [96, 88]], '#FF8A2A', 4, rand);
        crayonLine(ctx, [[70, 92], [74, 112], [80, 96], [86, 112], [90, 92]], '#FFB020', 5, rand);
        for (let k = 0; k < 5; k++) { ctx.fillStyle = '#FFD23A'; starPath(ctx, 20 + rand() * 30 + (k % 2) * 100, 20 + rand() * 80, 6, 2.5); ctx.fill(); }
      } else if (i === 4) { // tower + lightning
        crayonLine(ctx, [[64, 110], [80, 18], [96, 110]], '#E23B3B', 5, rand);
        for (let k = 1; k < 5; k++) crayonLine(ctx, [[64 + k * 3.5, 110 - k * 20], [96 - k * 3.5, 110 - k * 20]], '#E23B3B', 3, rand);
        crayonLine(ctx, [[120, 16], [108, 44], [124, 44], [110, 76]], '#FFC020', 5, rand);
        crayonLine(ctx, circlePts(80, 16, 5), '#FF3B30', 5, rand);
      } else { // rainbow + I <3 13
        const rc = ['#E23B3B', '#FF8A2A', '#FFD23A', '#52C24A', '#3A58E4'];
        rc.forEach((c, k) => crayonLine(ctx, Array.from({ length: 13 }, (_, j) => [80 + Math.cos(Math.PI + (j / 12) * Math.PI) * (54 - k * 7), 76 + Math.sin(Math.PI + (j / 12) * Math.PI) * (48 - k * 7)]), c, 5, rand));
        txt(ctx, 'I ♥ 13', 80, 100, { font: FONT.round, size: 22, fill: '#B05AD6', rot: 0.04 });
      }
      ctx.restore();
    }
  }
  // ---- sunflower cut-out (smiling)
  {
    const [x, y, w, h] = R('sunflower');
    ctx.save(); ctx.translate(x, y);
    ctx.fillStyle = '#4E9A36'; rr(ctx, w / 2 - 7, 88, 14, h - 90, 7); ctx.fill();
    for (const [ly, sd] of [[170, -1], [215, 1]]) { ctx.save(); ctx.translate(w / 2, ly); ctx.scale(sd, 1); ctx.fillStyle = '#62B845'; ctx.beginPath(); ctx.moveTo(0, 0); ctx.quadraticCurveTo(40, -34, 74, -10); ctx.quadraticCurveTo(40, 12, 0, 0); ctx.fill(); ctx.strokeStyle = '#3E7A2C'; ctx.lineWidth = 3; ctx.stroke(); ctx.restore(); }
    const fx = w / 2, fy = 76;
    for (let i = 0; i < 14; i++) { const a = (i / 14) * TAU; ctx.save(); ctx.translate(fx + Math.cos(a) * 44, fy + Math.sin(a) * 44); ctx.rotate(a); ctx.fillStyle = i % 2 ? '#FFD23A' : '#FFC020'; ctx.beginPath(); ctx.ellipse(0, 0, 26, 12, 0, 0, TAU); ctx.fill(); ctx.strokeStyle = '#E89A10'; ctx.lineWidth = 2.5; ctx.stroke(); ctx.restore(); }
    ctx.fillStyle = '#8A5230'; ctx.beginPath(); ctx.arc(fx, fy, 34, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(0,0,0,0.12)'; for (let i = 0; i < 30; i++) { ctx.beginPath(); ctx.arc(fx + (rand() - 0.5) * 50, fy + (rand() - 0.5) * 50, 2, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#2A1D2A'; for (const sd of [-1, 1]) { ctx.beginPath(); ctx.ellipse(fx + sd * 11, fy - 6, 4.5, 7, 0, 0, TAU); ctx.fill(); }
    ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 4; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(fx, fy + 2, 14, 0.25, Math.PI - 0.25); ctx.stroke();
    ctx.fillStyle = 'rgba(255,120,120,0.55)'; for (const sd of [-1, 1]) { ctx.beginPath(); ctx.arc(fx + sd * 20, fy + 8, 6, 0, TAU); ctx.fill(); }
    ctx.restore();
  }
  // ---- Hootie poster (cards.js art)
  { const [x, y, w, h] = R('poster'); ctx.save(); ctx.translate(x, y); try { drawTo(ctx, 'poster_hootie', w, h); } catch (e) { ctx.fillStyle = '#FF8FB8'; ctx.fillRect(0, 0, w, h); owlFace(ctx, w / 2, h / 2, 0.8); } ctx.restore(); }
  // ---- cloud with a face
  {
    const [x, y, w, h] = R('cloud');
    ctx.save(); ctx.translate(x, y);
    const blobs = [[60, 72, 40], [104, 52, 48], [150, 66, 40], [186, 84, 28], [34, 92, 26], [112, 90, 38]];
    ctx.fillStyle = '#B8D8F8'; for (const [bx, by, r] of blobs) { ctx.beginPath(); ctx.arc(bx, by + 4, r + 5, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#FFFFFF'; for (const [bx, by, r] of blobs) { ctx.beginPath(); ctx.arc(bx, by, r, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#3A2A48'; for (const sd of [-1, 1]) { ctx.beginPath(); ctx.ellipse(110 + sd * 18, 70, 5, 7, 0, 0, TAU); ctx.fill(); }
    ctx.strokeStyle = '#3A2A48'; ctx.lineWidth = 4; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(110, 78, 10, 0.3, Math.PI - 0.3); ctx.stroke();
    ctx.fillStyle = 'rgba(255,140,170,0.6)'; for (const sd of [-1, 1]) { ctx.beginPath(); ctx.arc(110 + sd * 32, 82, 7, 0, TAU); ctx.fill(); }
    ctx.restore();
  }
  // ---- small cut-outs: star, sleepy moon, music note, saturn, raindrop, spike X, heart
  { const [x, y, w, h] = R('star'); ctx.fillStyle = '#FFD23A'; starPath(ctx, x + w / 2, y + h / 2 + 2, 33, 14); ctx.fill(); ctx.lineWidth = 4; ctx.strokeStyle = '#E8901A'; ctx.stroke(); }
  {
    const [x, y, w, h] = R('moon'); const cx = x + w / 2, cy = y + h / 2;
    ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, 32, 0, TAU); ctx.arc(cx + 17, cy - 9, 27, 0, TAU, true); ctx.fillStyle = '#FFF2C4'; ctx.fill('evenodd'); ctx.restore();
    ctx.strokeStyle = '#8A7A5A'; ctx.lineWidth = 3; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(cx - 14, cy + 2, 5, 0.1, Math.PI - 0.1); ctx.stroke();
    ctx.fillStyle = 'rgba(255,140,140,0.6)'; ctx.beginPath(); ctx.arc(cx - 10, cy + 13, 4, 0, TAU); ctx.fill();
  }
  { const [x, y] = R('note'); ctx.fillStyle = '#FF6F91'; ctx.beginPath(); ctx.ellipse(x + 26, y + 56, 14, 10, -0.4, 0, TAU); ctx.fill(); ctx.beginPath(); ctx.ellipse(x + 58, y + 48, 14, 10, -0.4, 0, TAU); ctx.fill(); ctx.fillRect(x + 36, y + 10, 6, 46); ctx.fillRect(x + 68, y + 4, 6, 44); ctx.beginPath(); ctx.moveTo(x + 36, y + 10); ctx.lineTo(x + 74, y + 2); ctx.lineTo(x + 74, y + 14); ctx.lineTo(x + 36, y + 22); ctx.fill(); }
  {
    const [x, y, w, h] = R('saturn'); const cx = x + w / 2, cy = y + h / 2;
    ctx.save(); ctx.translate(cx, cy); ctx.rotate(-0.25);
    ctx.strokeStyle = '#B9A2FF'; ctx.lineWidth = 9; ctx.beginPath(); ctx.ellipse(0, 0, 70, 18, 0, Math.PI, TAU); ctx.stroke();
    ctx.fillStyle = '#FFB347'; ctx.beginPath(); ctx.arc(0, 0, 32, 0, TAU); ctx.fill();
    ctx.save(); ctx.beginPath(); ctx.arc(0, 0, 32, 0, TAU); ctx.clip(); ctx.fillStyle = '#FF8A5A'; ctx.fillRect(-40, -14, 80, 8); ctx.fillRect(-40, 6, 80, 7); ctx.restore();
    ctx.strokeStyle = '#B9A2FF'; ctx.lineWidth = 9; ctx.beginPath(); ctx.ellipse(0, 0, 70, 18, 0, 0, Math.PI); ctx.stroke();
    ctx.restore();
  }
  { const [x, y, w, h] = R('raindrop'); const cx = x + w / 2; ctx.fillStyle = '#6FB8F0'; ctx.beginPath(); ctx.moveTo(cx, y + 6); ctx.bezierCurveTo(cx + 30, y + 44, cx + 26, y + 74, cx, y + 74); ctx.bezierCurveTo(cx - 26, y + 74, cx - 30, y + 44, cx, y + 6); ctx.fill(); ctx.fillStyle = 'rgba(255,255,255,0.6)'; ctx.beginPath(); ctx.ellipse(cx - 9, y + 46, 5, 9, 0.3, 0, TAU); ctx.fill(); }
  {
    const [x, y, w, h] = R('spike');
    ctx.save(); ctx.translate(x + w / 2, y + h / 2);
    for (const a of [0.785, -0.785]) { ctx.save(); ctx.rotate(a); ctx.fillStyle = '#FF5FA2'; ctx.fillRect(-32, -6, 64, 12); ctx.fillStyle = 'rgba(255,255,255,0.2)'; ctx.fillRect(-32, -6, 64, 2); ctx.restore(); }
    ctx.restore();
  }
  { const [x, y, w, h] = R('heart'); const cx = x + w / 2, cy = y + h / 2; ctx.fillStyle = '#FF6F91'; ctx.beginPath(); ctx.moveTo(cx, cy + 26); ctx.bezierCurveTo(cx - 44, cy - 2, cx - 20, cy - 36, cx, cy - 14); ctx.bezierCurveTo(cx + 20, cy - 36, cx + 44, cy - 2, cx, cy + 26); ctx.fill(); ctx.fillStyle = 'rgba(255,255,255,0.45)'; ctx.beginPath(); ctx.ellipse(cx - 13, cy - 8, 5, 8, -0.5, 0, TAU); ctx.fill(); }
  // ---- launch pad ring (painted on the floor around the rocket): red ring, countdown numbers, stars
  {
    const [x, y, w, h] = R('launch'); const cx = x + w / 2, cy = y + h / 2, Ro = w / 2 - 2, Ri = Ro * 0.6;
    ctx.save();
    ctx.beginPath(); ctx.arc(cx, cy, Ro, 0, TAU); ctx.arc(cx, cy, Ri, 0, TAU, true); ctx.fillStyle = '#FFE45C'; ctx.fill('evenodd');
    ctx.beginPath(); ctx.arc(cx, cy, Ro - 8, 0, TAU); ctx.arc(cx, cy, Ri + 8, 0, TAU, true); ctx.fillStyle = '#E23B3B'; ctx.fill('evenodd');
    for (let i = 0; i < 10; i++) {
      const a = -HP + (i / 10) * TAU, r = (Ro + Ri) / 2;
      txt(ctx, String(10 - i), cx + Math.cos(a) * r, cy + Math.sin(a) * r, { font: FONT.round, size: 17, fill: '#FFF6E0', rot: a + HP });
      ctx.fillStyle = '#FFE45C'; starPath(ctx, cx + Math.cos(a + TAU / 20) * r, cy + Math.sin(a + TAU / 20) * r, 7, 3); ctx.fill();
    }
    ctx.restore();
  }
  // ---- cue cards
  for (const [n, s, col, rot] of [['cue1', 'WAVE HI!', '#E23B3B', -0.05], ['cue2', 'SING ALONG!', '#3A58E4', 0.04]]) {
    const [x, y, w, h] = R(n);
    ctx.fillStyle = '#FFFBEF'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = 'rgba(60,90,200,0.25)'; for (let yy = y + 20; yy < y + h - 6; yy += 16) ctx.fillRect(x + 6, yy, w - 12, 2);
    txt(ctx, s, x + w / 2, y + h / 2 - 4, { font: FONT.round, size: 30, fill: col, maxW: w - 14, rot });
    ctx.fillStyle = '#FFD23A'; starPath(ctx, x + w - 18, y + h - 16, 9, 4); ctx.fill();
  }
  // ---- toy piano keys + label
  {
    const [x, y, w, h] = R('piano');
    ctx.fillStyle = '#2A1D2A'; ctx.fillRect(x, y, w, h);
    const n = 15, kw = w / n;
    for (let i = 0; i < n; i++) { rr(ctx, x + i * kw + 1, y + 1, kw - 2, h - 2, 3); ctx.fillStyle = '#FFFBEF'; ctx.fill(); }
    for (let i = 0; i < n - 1; i++) { if ([2, 6, 9, 13].includes(i)) continue; rr(ctx, x + (i + 1) * kw - kw * 0.3, y, kw * 0.6, h * 0.6, 2); ctx.fillStyle = '#2A1D2A'; ctx.fill(); }
  }
  { const [x, y, w, h] = R('pianoLbl'); rr(ctx, x + 2, y + 2, w - 4, h - 4, 10); ctx.fillStyle = '#8A2A4A'; ctx.fill(); txt(ctx, "Hootie's Toy Piano", x + w / 2, y + h / 2 + 1, { font: FONT.groovy, size: 24, fill: '#FFE45C', maxW: w - 20 }); }
  // ---- toy chest front
  {
    const [x, y, w, h] = R('chest');
    ctx.save(); ctx.translate(x, y);
    ctx.fillStyle = '#7FC8F0'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = 'rgba(255,255,255,0.18)'; for (let i = 0; i < 8; i++) ctx.fillRect(i * 34, 0, 14, h);
    ctx.lineWidth = 8; ctx.strokeStyle = '#FFE45C'; rr(ctx, 8, 8, w - 16, h - 16, 16); ctx.stroke();
    const letters = [['T', '#E23B3B'], ['O', '#52C24A'], ['Y', '#FF8A2A'], ['S', '#B05AD6']];
    letters.forEach(([c, col], i) => txt(ctx, c, 62 + i * 40, h / 2 + 4 + (i % 2 ? -5 : 5), { font: FONT.round, size: 50, fill: col, stroke: '#FFFFFF', lw: 7, rot: (i % 2 ? 0.14 : -0.12) }));
    for (const sx of [24, w - 24]) { ctx.fillStyle = '#FFE45C'; starPath(ctx, sx, h / 2, 13, 6); ctx.fill(); }
    ctx.restore();
  }
  // ---- STUDIO B sign (same family as Studio A's)
  {
    const [x, y, w, h] = R('signB');
    ctx.fillStyle = '#E8A92E'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = '#2A1D2A'; for (let i = 0; i < 12; i++) { ctx.beginPath(); ctx.moveTo(x + i * 22, y + h); ctx.lineTo(x + i * 22 + 11, y + h); ctx.lineTo(x + i * 22 + 25, y + h - 14); ctx.lineTo(x + i * 22 + 14, y + h - 14); ctx.fill(); }
    txt(ctx, 'STUDIO B', x + w / 2, y + 48, { font: FONT.sign, size: 50, fill: '#2A1D2A', maxW: w - 20 });
  }
  // ---- countdown sign (kid-lettered cardboard)
  {
    const [x, y, w, h] = R('countdown');
    ctx.fillStyle = '#D8B27A'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = 'rgba(120,80,40,0.25)'; for (let i = 0; i < 20; i++) ctx.fillRect(x, y + 4 + i * 5.5, w, 1.5);
    txt(ctx, '3 · 2 · 1', x + w / 2, y + 34, { font: FONT.round, size: 34, fill: '#E23B3B', stroke: '#FFF6E0', lw: 5, rot: -0.03 });
    txt(ctx, 'BLAST OFF!', x + w / 2, y + 78, { font: FONT.sign, size: 32, fill: '#3A58E4', stroke: '#FFF6E0', lw: 5, rot: 0.03, maxW: w - 20 });
  }
  // ---- Sockette sock (stripes on cream, heel + toe)
  {
    const [x, y, w, h] = R('sock');
    ctx.save(); ctx.translate(x, y);
    ctx.beginPath(); ctx.moveTo(40, 4); ctx.lineTo(84, 4); ctx.lineTo(84, 76); ctx.quadraticCurveTo(84, 122, 36, 122); ctx.quadraticCurveTo(6, 120, 8, 100); ctx.quadraticCurveTo(10, 84, 40, 78); ctx.closePath();
    ctx.save(); ctx.clip();
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 0, w, h);
    const sc = ['#E23B3B', '#F4E03A', '#3A58E4'];
    for (let i = 0; i < 5; i++) { ctx.fillStyle = sc[i % 3]; ctx.fillRect(0, 10 + i * 14, w, 8); }
    ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(22, 106, 18, 0, TAU); ctx.fill();
    ctx.fillStyle = '#F4E03A'; ctx.fillRect(0, 0, w, 7);
    ctx.restore();
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(60,30,50,0.5)'; ctx.stroke();
    ctx.restore();
  }
  // ---- solid white block (uv target for sticks and strings drawn with the cut-out material)
  { const [x, y, w, h] = R('white'); ctx.fillStyle = '#FFFFFF'; ctx.fillRect(x, y, w, h); }
  // ---- googly eyes pair
  { const [x, y] = R('eyes'); for (const [ex, px] of [[36, 42], [88, 82]]) { ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.arc(x + ex, y + 52, 26, 0, TAU); ctx.fill(); ctx.lineWidth = 3; ctx.strokeStyle = '#2A1D2A'; ctx.stroke(); ctx.fillStyle = '#1E1530'; ctx.beginPath(); ctx.arc(x + px, y + 60, 12, 0, TAU); ctx.fill(); } }
}

// Golden puppet silhouettes (same shapes as the puppet theater apron's dashed outlines, sets.js), 3 cells of 170 px.
function silhouetteTex() {
  return K.tex.canvas('sb_silhouettes_v1', 512, 256, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    const cells = [[85, 128], [256, 128], [427, 128]];
    const cy = 0; // silhouettes drawn around (cx, cy) exactly like the apron paths (cy = apron center line)
    const paint = () => { const g = ctx.createLinearGradient(0, -80, 0, 80); g.addColorStop(0, '#FFF2A0'); g.addColorStop(1, '#FFB020'); ctx.fillStyle = g; ctx.fill(); ctx.lineWidth = 7; ctx.strokeStyle = '#FFFFFF'; ctx.stroke(); };
    cells.forEach(([x, y], k) => {
      ctx.save(); ctx.translate(x, y);
      const c = 0;
      ctx.beginPath();
      if (k === 0) { // owl
        ctx.ellipse(c, cy + 10, 50, 62, 0, 0, TAU); ctx.moveTo(c - 40, cy - 34); ctx.lineTo(c - 46, cy - 72); ctx.lineTo(c - 14, cy - 50); ctx.moveTo(c + 40, cy - 34); ctx.lineTo(c + 46, cy - 72); ctx.lineTo(c + 14, cy - 50);
      } else if (k === 1) { // sock
        ctx.moveTo(c - 28, cy - 80); ctx.lineTo(c + 26, cy - 80); ctx.lineTo(c + 26, cy + 20); ctx.quadraticCurveTo(c + 26, cy + 72, c - 30, cy + 70); ctx.quadraticCurveTo(c - 74, cy + 66, c - 60, cy + 38); ctx.lineTo(c - 28, cy + 26); ctx.closePath();
      } else { // dragon
        ctx.moveTo(c - 50, cy + 60); ctx.quadraticCurveTo(c - 60, cy - 10, c - 10, cy - 30); ctx.lineTo(c - 4, cy - 70); ctx.lineTo(c + 10, cy - 40); ctx.lineTo(c + 22, cy - 76); ctx.lineTo(c + 28, cy - 36); ctx.quadraticCurveTo(c + 78, cy - 36, c + 72, cy - 6); ctx.quadraticCurveTo(c + 40, cy + 4, c + 36, cy + 20); ctx.quadraticCurveTo(c + 40, cy + 60, c + 20, cy + 60); ctx.closePath();
      }
      paint();
      ctx.fillStyle = 'rgba(255,255,255,0.8)';
      for (let i = 0; i < 4; i++) { starPath(ctx, -40 + i * 27, -86 + (i % 2) * 10, 6, 2.5); ctx.fill(); }
      ctx.restore();
    });
  }, { repeat: false, fonts: false });
}

// ============================================================================================ local builders
// Painted plywood flat standing on the floor (front faces -z), with two stage jacks + sandbags behind.
function flat(game, tex, w, h) {
  const M = studioMats(game);
  const g = K.prop('sb_flat');
  g.add(K.m(tg(K.box(w + 0.1, h + 0.1, 0.06, 0.02), '#E8D2B0'), M.lac, { pos: [0, h / 2 + 0.05, 0.02] }));
  g.add(K.m(quad(w, h), K.mat(game, 'paint', '#ffffff', { map: tex, rough: 0.7 }), { pos: [0, h / 2 + 0.05, -0.012] }));
  for (const s of [-0.34, 0.34]) {
    const jack = K.extrude([[0, 0], [0.5, 0], [0, h * 0.8]], 0.04, { bevel: 0.008 });
    const m = K.m(tg(jack, '#B89868'), M.lac, { pos: [s * w - 0.02, 0.02, 0.06], rot: [0, -HP, 0] });
    g.add(m);
    g.add(K.m(tg(K.cushion(0.34, 0.13, 0.22, { puff: 0.03 }), '#7A6A48'), M.felt, { pos: [s * w, 0.07, 0.36] }));
  }
  g.userData.colliders = [{ min: [-w / 2 - 0.05, 0, -0.05], max: [w / 2 + 0.05, h + 0.1, 0.55] }];
  return K.finish(game, g, { ao: { res: 40 } });
}

// Framed sign / banner (front faces -z), optionally hanging from strings.
function banner(game, A, region, w, h, { color = '#2A1D2A', hang = 0, glossy = false } = {}) {
  const M = studioMats(game);
  const g = K.prop('sb_banner');
  g.add(K.m(tg(K.box(w + 0.08, h + 0.08, 0.04, 0.02), color), M.lac));
  g.add(K.m(quad(w, h, A.uv(region)), glossy ? A.gloss : A.mat, { pos: [0, 0, -0.022] }));
  if (hang) for (const s of [-1, 1]) g.add(K.m(tg(K.cyl(0.005, 0.005, hang, { seg: 5 }), '#2A2230'), M.lac, { pos: [s * (w / 2 - 0.15), h / 2 + 0.04, 0] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}

// Toy chest with the lid open and toys spilling out (front faces -z).
function toyChest(game, A) {
  const M = studioMats(game);
  const g = K.prop('sb_toy_chest');
  const Wd = 1.0, Hh = 0.5, D = 0.55;
  g.add(K.m(tg(K.box(Wd, Hh, D, 0.04), '#6FB8E8'), M.lac, { pos: [0, Hh / 2 + 0.04, 0] }));
  g.add(K.m(quad(Wd - 0.08, Hh - 0.1, A.uv('chest')), A.mat, { pos: [0, Hh / 2 + 0.04, -D / 2 - 0.004] }));
  g.add(K.m(tg(K.box(Wd + 0.04, 0.05, D + 0.04, 0.02), '#FFE45C'), M.lac, { pos: [0, Hh + 0.05, 0] }));
  for (const [x, z] of [[-0.42, -0.2], [0.42, -0.2], [-0.42, 0.2], [0.42, 0.2]]) g.add(K.m(tg(new THREE.SphereGeometry(0.045, 10, 8), '#FF8FB8'), M.lac, { pos: [x, 0.03, z] }));
  const lid = K.m(tg(K.box(Wd + 0.04, 0.06, D + 0.04, 0.025), '#6FB8E8'), M.lac);
  lid.geometry.translate(0, 0, -(D + 0.04) / 2);
  lid.position.set(0, Hh + 0.08, D / 2 + 0.02);
  lid.rotation.x = -1.95;
  g.add(lid);
  // teddy peeking out
  const bear = '#C8905A';
  g.add(K.m(tg(new THREE.SphereGeometry(0.15, 16, 12), bear), M.felt, { pos: [-0.22, Hh + 0.16, 0.02] }));
  for (const s of [-1, 1]) g.add(K.m(tg(new THREE.SphereGeometry(0.055, 10, 8), bear), M.felt, { pos: [-0.22 + s * 0.11, Hh + 0.29, 0.03] }));
  g.add(K.m(tg(new THREE.SphereGeometry(0.06, 10, 8), '#F0D2A8'), M.felt, { pos: [-0.22, Hh + 0.12, -0.12] }));
  g.add(K.m(tg(new THREE.SphereGeometry(0.022, 8, 6), '#2A1D2A'), M.lac, { pos: [-0.22, Hh + 0.14, -0.175] }));
  for (const s of [-1, 1]) g.add(K.m(tg(new THREE.SphereGeometry(0.018, 8, 6), '#2A1D2A'), M.lac, { pos: [-0.22 + s * 0.055, Hh + 0.2, -0.13] }));
  g.add(K.m(tg(K.box(0.14, 0.05, 0.05, 0.02), '#E23B3B'), M.felt, { pos: [-0.22, Hh + 0.05, -0.13] }));
  // striped ball + jack-in-the-box spring + star wand
  const ball = new THREE.SphereGeometry(0.13, 18, 12);
  K.tint(ball, (x, y) => new THREE.Color(Math.abs(y) < 0.04 ? '#FFFFFF' : y > 0 ? '#E23B3B' : '#3A58E4'));
  g.add(K.m(ball, M.plastic, { pos: [0.18, Hh + 0.13, 0.08] }));
  g.add(K.m(tg(K.box(0.18, 0.18, 0.18, 0.03), '#FFE45C'), M.lac, { pos: [0.36, Hh + 0.05, -0.08], rot: [0, 0.3, 0] }));
  const spring = [];
  for (let i = 0; i <= 40; i++) { const a = (i / 40) * TAU * 5; spring.push([Math.cos(a) * 0.035, i * 0.006, Math.sin(a) * 0.035]); }
  g.add(K.m(tg(K.tube(spring, 0.007, { seg: 80, radial: 4 }), '#C0C6D0'), M.chrome, { pos: [0.36, Hh + 0.14, -0.08] }));
  g.add(K.m(tg(new THREE.SphereGeometry(0.075, 14, 10), '#FFD8B8'), M.lac, { pos: [0.36, Hh + 0.44, -0.08] }));
  g.add(K.m(tg(new THREE.ConeGeometry(0.07, 0.14, 12), '#B05AD6'), M.lac, { pos: [0.36, Hh + 0.55, -0.08], rot: [0.2, 0, 0.3] }));
  g.add(K.m(tg(new THREE.SphereGeometry(0.016, 8, 6), '#2A1D2A'), M.lac, { pos: [0.335, Hh + 0.46, -0.15] }), K.m(tg(new THREE.SphereGeometry(0.016, 8, 6), '#2A1D2A'), M.lac, { pos: [0.385, Hh + 0.46, -0.15] }));
  g.add(K.m(tg(new THREE.SphereGeometry(0.02, 8, 6), '#E23B3B'), M.lac, { pos: [0.36, Hh + 0.43, -0.16] }));
  g.add(K.m(tg(K.cyl(0.01, 0.01, 0.5, { seg: 6 }), '#FF8FB8'), M.lac, { pos: [0.02, Hh, 0.12], rot: [0.35, 0, -0.5] }));
  g.add(K.m(tg(K.extrude(starShape(0.08, 0.035), 0.025, { bevel: 0.006 }), '#FFD23A'), M.lac, { pos: [0.24, Hh + 0.46, 0.27], rot: [0.35, 0, -0.5] }));
  g.userData.colliders = [{ min: [-Wd / 2, 0, -D / 2], max: [Wd / 2, Hh + 0.12, D / 2] }];
  return K.finish(game, g, { ao: { res: 40 } });
}
function starShape(ro, ri, n = 5) {
  const p = [];
  for (let i = 0; i < n * 2; i++) { const a = HP + (i / (n * 2)) * TAU, r = i % 2 ? ri : ro; p.push([Math.cos(a) * r, Math.sin(a) * r]); }
  return p;
}

// Pastel upright toy piano + stool (front = keyboard side, faces -z).
function toyPiano(game, A) {
  const M = studioMats(game);
  const g = K.prop('sb_toy_piano');
  const Wd = 1.2, pink = '#FF9EC4', cream = '#FFF1DC';
  for (const [x, z] of [[-0.52, -0.14], [0.52, -0.14], [-0.52, 0.16], [0.52, 0.16]]) g.add(K.m(tg(K.cyl(0.035, 0.028, 0.34, { seg: 10 }), cream), M.lac, { pos: [x, 0, z] }));
  g.add(K.m(tg(K.box(Wd, 0.5, 0.42, 0.05), pink), M.lac, { pos: [0, 0.6, 0.02] }));
  g.add(K.m(tg(K.box(Wd, 0.46, 0.14, 0.04), pink), M.lac, { pos: [0, 1.08, 0.16] }));
  g.add(K.m(tg(K.box(Wd + 0.06, 0.05, 0.22, 0.02), cream), M.lac, { pos: [0, 1.33, 0.14] }));
  // keyboard shelf + keys (atlas) + key cheeks
  g.add(K.m(tg(K.box(Wd - 0.04, 0.05, 0.24, 0.015), '#2A1D2A'), M.lac, { pos: [0, 0.86, -0.14] }));
  const keys = quad(Wd - 0.18, 0.2, A.uv('piano')).rotateX(-HP);
  g.add(K.m(keys, A.gloss, { pos: [0, 0.887, -0.14] }));
  for (const s of [-1, 1]) g.add(K.m(tg(K.box(0.07, 0.1, 0.26, 0.02), pink), M.lac, { pos: [s * (Wd / 2 - 0.05), 0.9, -0.14] }));
  g.add(K.m(quad(0.72, 0.12, A.uv('pianoLbl')), A.gloss, { pos: [0, 0.6, -0.195] }));
  // music stand with a song sheet + a floating note cut-out
  g.add(K.m(tg(K.box(0.5, 0.3, 0.02, 0.008), '#FFFBEF'), M.lac, { pos: [0, 1.06, 0.07], rot: [-0.25, 0, 0] }));
  for (let i = 0; i < 4; i++) g.add(K.m(tg(K.box(0.42, 0.006, 0.004, 0.001), '#6A6A8A'), M.lac, { pos: [0, 0.97 + i * 0.05, 0.055 - i * 0.012], rot: [-0.25, 0, 0] }));
  const note = K.m(quad(0.2, 0.18, A.uv('note')), A.cut, { pos: [0.34, 1.52, 0.14], rot: [0, 0, 0.2] });
  g.add(note);
  g.add(K.m(tg(K.cyl(0.004, 0.004, 0.18, { seg: 4 }), '#2A2230'), M.lac, { pos: [0.34, 1.34, 0.14] }));
  // stool
  g.add(K.m(tg(K.cyl(0.03, 0.04, 0.42, { seg: 10 }), cream), M.lac, { pos: [0.05, 0, -0.62] }));
  g.add(K.m(tg(K.cyl(0.18, 0.2, 0.03, { seg: 16 }), cream), M.lac, { pos: [0.05, 0, -0.62] }));
  g.add(K.m(tg(K.cushion(0.36, 0.08, 0.36, { puff: 0.03 }), '#B05AD6'), M.felt, { pos: [0.05, 0.46, -0.62] }));
  g.userData.colliders = [{ min: [-Wd / 2, 0, -0.27], max: [Wd / 2, 1.36, 0.25] }, { min: [-0.15, 0, -0.82], max: [0.25, 0.5, -0.42] }];
  return K.finish(game, g, { ao: { res: 44 } });
}

// Rolling wardrobe rack with Hootie's owl costume on a hanger and the big owl head on a hatbox (front faces -z).
function costumeRack(game) {
  const M = studioMats(game);
  const g = K.prop('sb_costume_rack');
  const Wd = 1.2, H = 1.72, chromeC = '#C0C6D0';
  for (const s of [-1, 1]) {
    g.add(K.m(tg(K.cyl(0.02, 0.02, H, { seg: 10 }), chromeC), M.chrome, { pos: [s * Wd / 2, 0.08, 0] }));
    g.add(K.m(tg(K.cyl(0.018, 0.018, 0.5, { seg: 8 }).clone().rotateX(HP).translate(0, 0, -0.25), chromeC), M.chrome, { pos: [s * Wd / 2, 0.1, 0.25] }));
    for (const z of [-0.24, 0.24]) g.add(K.m(tg(new THREE.SphereGeometry(0.04, 10, 8), '#2A2230'), M.lac, { pos: [s * Wd / 2, 0.04, z] }));
  }
  g.add(K.m(tg(K.cyl(0.018, 0.018, Wd, { seg: 10 }).clone().rotateZ(HP).translate(Wd / 2, 0, 0), chromeC), M.chrome, { pos: [-Wd / 2, H + 0.06, 0] }));
  // hangers + owl suit (felt body, cream belly, wings) + a striped sock-puppet costume
  const brown = '#8A5A3A';
  for (const [x, w] of [[-0.18, 1], [0.34, 0.8]]) {
    g.add(K.m(tg(K.tube([[x - 0.18 * w, H - 0.08, 0], [x, H, 0], [x + 0.18 * w, H - 0.08, 0]], 0.008, { seg: 8, radial: 4 }), '#C8A06A'), M.lac));
    g.add(K.m(tg(K.tube([[x, H, 0], [x, H + 0.06, 0]], 0.006, { seg: 2, radial: 4 }), chromeC), M.chrome));
  }
  const suit = new THREE.SphereGeometry(0.3, 18, 14);
  suit.scale(1, 1.55, 0.55);
  g.add(K.m(tg(suit, brown), M.felt, { pos: [-0.18, H - 0.52, 0] }));
  const belly = new THREE.SphereGeometry(0.2, 16, 12);
  belly.scale(1, 1.4, 0.4);
  g.add(K.m(tg(belly, '#E8C89A'), M.felt, { pos: [-0.18, H - 0.6, -0.1] }));
  for (const s of [-1, 1]) {
    const wing = new THREE.SphereGeometry(0.16, 12, 10);
    wing.scale(0.55, 1.5, 0.35);
    g.add(K.m(tg(wing, '#6E4428'), M.felt, { pos: [-0.18 + s * 0.3, H - 0.55, 0.02], rot: [0, 0, s * 0.25] }));
  }
  for (let i = 0; i < 5; i++) g.add(K.m(tg(new THREE.SphereGeometry(0.03, 8, 6), '#FFE45C'), M.plastic, { pos: [-0.18, H - 0.35 - i * 0.1, -0.2] }));
  const sock = new THREE.CylinderGeometry(0.15, 0.13, 0.85, 16, 6);
  K.tint(sock, (x, y) => new THREE.Color(['#E23B3B', '#F4E03A', '#3A58E4', '#F4F1E8'][Math.floor((y + 0.43) / 0.14) % 4]));
  g.add(K.m(sock, M.felt, { pos: [0.34, H - 0.55, 0], rot: [0, 0, 0.04] }));
  // hatbox + the big owl head
  g.add(K.m(tg(K.cyl(0.26, 0.26, 0.34, { seg: 20 }), '#FF8FB8'), M.lac, { pos: [0.95, 0, -0.05] }));
  g.add(K.m(tg(K.cyl(0.275, 0.275, 0.05, { seg: 20 }), '#FFE45C'), M.lac, { pos: [0.95, 0.33, -0.05] }));
  const hx = 0.95, hy = 0.68, hz = -0.05;
  const head = new THREE.SphereGeometry(0.3, 20, 16);
  head.scale(1, 0.92, 0.95);
  g.add(K.m(tg(head, brown), M.felt, { pos: [hx, hy, hz] }));
  const ring = Array.from({ length: 17 }, (_, i) => { const a = (i / 16) * TAU; return [Math.cos(a) * 0.11, Math.sin(a) * 0.11, 0]; });
  for (const s of [-1, 1]) {
    // feathery ear tufts + the heart-shaped cream facial disc that makes it read as an owl
    const tuft = new THREE.ConeGeometry(0.075, 0.24, 10);
    tuft.scale(1, 1, 0.45);
    g.add(K.m(tg(tuft, '#6E4428'), M.felt, { pos: [hx + s * 0.2, hy + 0.3, hz + 0.02], rot: [0, 0, -s * 0.55] }));
    const disc = new THREE.SphereGeometry(0.15, 16, 12);
    disc.scale(1, 1.12, 0.32);
    g.add(K.m(tg(disc, '#F0DDB8'), M.felt, { pos: [hx + s * 0.1, hy + 0.01, hz - 0.2] }));
    g.add(K.m(tg(new THREE.SphereGeometry(0.1, 14, 10), '#FFF8E8'), M.lac, { pos: [hx + s * 0.11, hy + 0.04, hz - 0.22] }));
    g.add(K.m(tg(K.tube(ring, 0.018, { seg: 24, radial: 5, closed: true }), '#F4A020'), M.lac, { pos: [hx + s * 0.11, hy + 0.04, hz - 0.26] }));
    g.add(K.m(tg(new THREE.SphereGeometry(0.045, 10, 8), '#2A1D3A'), M.lac, { pos: [hx + s * 0.1, hy + 0.03, hz - 0.31] }));
  }
  g.add(K.m(tg(new THREE.ConeGeometry(0.05, 0.12, 10).rotateX(-HP * 1.2), '#F4A020'), M.lac, { pos: [hx, hy - 0.07, hz - 0.3] }));
  g.userData.colliders = [{ min: [-Wd / 2 - 0.05, 0, -0.3], max: [Wd / 2 + 0.05, H + 0.1, 0.3] }, { min: [0.66, 0, -0.34], max: [1.24, 1.0, 0.24] }];
  return K.finish(game, g, { ao: { res: 40 } });
}

// Cut-out on a stake (sunflower) — front faces -z.
function cutout(game, A, region, w, h, { stake = 0, stakeColor = '#4E9A36' } = {}) {
  const M = studioMats(game);
  const g = K.prop('sb_cutout');
  g.add(K.m(quad(w, h, A.uv(region)), A.cut, { pos: [0, h / 2 + stake, 0] }));
  if (stake) g.add(K.m(tg(K.box(0.05, stake + h * 0.3, 0.03, 0.01), stakeColor), M.lac, { pos: [0, (stake + h * 0.3) / 2, 0.03] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}

// Balloon cluster: tie point at the origin, balloons floating 0.8..1.5 m above (one mesh, one draw).
function balloonCluster(game, seed, n = 5, rise = 1.0) {
  const M = studioMats(game);
  const rnd = mulberry(seed);
  const g = new THREE.Group();
  g.name = 'sb_balloons';
  const cols = ['#FF5F7F', '#FFD23A', '#6FD3F0', '#8CE07A', '#B9A2FF', '#FF9A3C', '#FF8FB8'];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * TAU + rnd() * 0.6, r = 0.14 + rnd() * 0.16, y = rise + rnd() * 0.5;
    const top = new THREE.Vector3(Math.cos(a) * r, y, Math.sin(a) * r);
    const b = new THREE.SphereGeometry(0.16, 14, 11);
    b.scale(1, 1.18, 1);
    const col = cols[(i + seed) % cols.length];
    g.add(K.m(tg(b, col), M.plastic, { pos: [top.x, top.y + 0.19, top.z] }));
    g.add(K.m(tg(new THREE.ConeGeometry(0.03, 0.05, 8).rotateX(Math.PI), col), M.plastic, { pos: [top.x, top.y - 0.005, top.z] }));
    const mid = top.clone().multiplyScalar(0.5).add(new THREE.Vector3((rnd() - 0.5) * 0.08, 0, (rnd() - 0.5) * 0.08));
    g.add(K.m(tg(K.tube([[0, 0, 0], [mid.x, mid.y, mid.z], [top.x, top.y - 0.03, top.z]], 0.004, { seg: 8, radial: 3 }), '#FFFFFF'), M.plastic));
  }
  K.merge(g);
  g.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = true; } });
  g.userData.noMerge = true;
  return g;
}

// Hanging mobile: string from the grid to a crossbar, cut-outs dangling (rotates as one piece).
function mobile(game, A, items, { drop = 0.9, bar = 1.2, glowMat = null } = {}) {
  const g = new THREE.Group();
  g.name = 'sb_mobile';
  const barY = -drop;
  const stick = (geo, color) => solidUV(tg(geo, color));
  g.add(K.m(stick(K.cyl(0.004, 0.004, drop, { seg: 4 }), '#2A2230'), A.cut, { pos: [0, barY, 0] }));
  g.add(K.m(stick(K.cyl(0.012, 0.012, bar, { seg: 6 }).clone().rotateZ(HP).translate(bar / 2, 0, 0), '#F4F1E8'), A.cut, { pos: [0, barY, 0] }));
  g.add(K.m(stick(K.cyl(0.012, 0.012, bar * 0.7, { seg: 6 }).clone().rotateX(HP).translate(0, 0, -bar * 0.35), '#FF8FB8'), A.cut, { pos: [0, barY, 0] }));
  for (const it of items) {
    const [x, z] = it.at, y = barY - it.hang;
    g.add(K.m(stick(K.cyl(0.003, 0.003, it.hang, { seg: 4 }), '#2A2230'), A.cut, { pos: [x, y, z] }));
    const q = K.m(quad(it.w, it.h, A.uv(it.region)), it.glow && glowMat ? glowMat : A.cut, { pos: [x, y - it.h / 2 + 0.02, z], rot: [0, it.rot ?? 0, 0] });
    g.add(q);
  }
  const grp = new THREE.Group();
  grp.add(g);
  K.merge(g);
  g.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
  grp.userData.noMerge = true;
  grp.userData.spin = g;
  return grp;
}

// Sagging catenary points between a and b
function sagPts(a, b, sag, n = 12) {
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    pts.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t - Math.sin(t * Math.PI) * sag, a[2] + (b[2] - a[2]) * t]);
  }
  return pts;
}
function sampleAlong(pts, step) {
  const out = [];
  let acc = 0;
  for (let i = 1; i < pts.length; i++) {
    const a = v3(pts[i - 1]), b = v3(pts[i]), d = a.distanceTo(b);
    while (acc <= d) { out.push({ p: a.clone().lerp(b, acc / d), dir: b.clone().sub(a).normalize() }); acc += step; }
    acc -= d;
  }
  return out;
}

// Rainbow pennant bunting (string + triangles) added to `into` (merged by the level).
function bunting(game, into, a, b, sag, seed = 0) {
  const M = studioMats(game);
  const pts = sagPts(a, b, sag, 16);
  into.add(K.m(tg(K.tube(pts, 0.006, { seg: 32, radial: 3 }), '#F4F1E8'), M.lac, { cast: false }));
  const tri = new THREE.BufferGeometry();
  tri.setAttribute('position', new THREE.Float32BufferAttribute([-0.11, 0, 0, 0.11, 0, 0, 0, -0.28, 0], 3));
  tri.setAttribute('uv', new THREE.Float32BufferAttribute([0, 1, 1, 1, 0.5, 0], 2));
  tri.computeVertexNormals();
  const flags = sampleAlong(pts, 0.3);
  flags.forEach((f, i) => {
    if (i === 0) return;
    const m = K.m(tg(tri.clone(), PASTEL[(i + seed) % PASTEL.length]), M.felt, { pos: [f.p.x, f.p.y - 0.01, f.p.z], cast: false });
    m.rotation.y = Math.atan2(-f.dir.z, f.dir.x);
    into.add(m);
  });
}
// felt pennants need both faces
const PENNANT = new WeakMap();

// ============================================================================================ build
export function build(game, area, root) {
  const rt = runtime(game, AREA, root);
  const M = studioMats(game);
  const O = rt.objects;
  const A = makeAtlas(game, 'sb_atlas_v1', 1024, REG_B, drawStudioB);
  rt.warmMat(M.glow, M.glowDim);
  const dyn = new THREE.Group();
  dyn.name = 'studio_b:dynamic';
  dyn.userData.noMerge = true;
  root.add(dyn);
  const P = (id, o) => place(game, root, id, { area: AREA, ...o });
  const col = game.level?.col;
  const box = (min, max, tag = 'prop') => col?.addBox(min, max, { tag });
  const sfx = (id, pos, o = {}) => game.audio?.play?.(id, { pos: v3(pos), ...o });
  let pennantMat = PENNANT.get(game);
  if (!pennantMat) { pennantMat = K.mat(game, 'felt', '#ffffff', { side: THREE.DoubleSide }); PENNANT.set(game, pennantMat); }
  const glowCut = new THREE.MeshBasicMaterial({ map: A.tex, alphaTest: 0.5, side: THREE.DoubleSide, color: new THREE.Color(0.95, 1.0, 1.15), fog: true });
  rt.warmMat(glowCut);

  const step = (name, fn) => { try { fn(); } catch (err) { console.error(`[rooms:studio_b] ${name}`, err); } };

  // ------------------------------------------------------------------------------------------- hero props
  step('rocket', () => {
    const a = ANCHORS.prop_rocket;
    const rocket = P('cardboard_rocket', { pos: a.pos, rotY: -3 * Math.PI / 4, colliders: false });
    // after the -135 deg turn the fins point along the world axes: body square + fin cross, axis-aligned
    const [x, , z] = a.pos;
    box([x - 0.86, 0, z - 0.86], [x + 0.86, 5.5, z + 0.86]);
    box([x - 1.34, 0, z - 0.2], [x + 1.34, 1.9, z + 0.2]);
    box([x - 0.2, 0, z - 1.34], [x + 0.2, 1.9, z + 1.34]);
    O.cardboard_rocket = { group: rocket };
    // painted launch-pad ring on the floor + the kid-lettered countdown sign on a stake
    const ring = new THREE.PlaneGeometry(3.9, 3.9).rotateX(-HP);
    K.uvRect(ring, ...A.uv('launch'));
    root.add(K.m(ring, A.cut, { pos: [x, 0.012, z], cast: false }));
    const sign = K.prop('sb_countdown');
    sign.add(K.m(tg(K.box(0.05, 1.2, 0.04, 0.012), '#B89868'), M.lac, { pos: [0, 0.6, 0.03] }));
    sign.add(K.m(tg(K.box(0.84, 0.44, 0.03, 0.012), '#C8A06A'), M.lac, { pos: [0, 1.2, 0.012], rot: [0, 0, 0.04] }));
    sign.add(K.m(quad(0.8, 0.4, A.uv('countdown')), A.mat, { pos: [0, 1.2, -0.006], rot: [0, 0, 0.04] }));
    sign.userData.colliders = [{ min: [-0.06, 0, -0.05], max: [0.06, 1.0, 0.07] }];
    K.finish(game, sign, { ao: { res: 28 } });
    P(null, { group: sign, pos: [23.2, 0, -19.8], rotY: -3 * Math.PI / 4 + 0.1 });
  });

  step('treehouse', () => {
    const a = ANCHORS.prop_treehouse;
    const th = P('treehouse_facade', { pos: [a.pos[0], 0, a.pos[2]], rotY: Math.PI, opts: { card: 'hullabaloo' }, screenGroup: 'scr_decor', screenId: 'ss_studio_b' });
    O.treehouse = { group: th, parts: th.userData.parts };
    O.ss_studio_b = { group: th, screen: th.userData.screens?.[0]?.mesh };
    // cardboard mushrooms + flowers at the trunk's feet (clear of the TV spawn lane x 25..27)
    const deco = K.prop('sb_tree_feet');
    for (const [dx, dz, s, c] of [[-2.05, 0.1, 1, '#E23B3B'], [-1.7, -0.25, 0.7, '#FF8FB8'], [1.9, -0.1, 0.85, '#FFB347']]) {
      deco.add(K.m(tg(K.cyl(0.07 * s, 0.09 * s, 0.26 * s, { seg: 10 }), '#FFF4DC'), M.lac, { pos: [dx, 0, dz] }));
      const cap = new THREE.SphereGeometry(0.2 * s, 16, 8, 0, TAU, 0, HP);
      cap.scale(1, 0.62, 1);
      deco.add(K.m(tg(cap, c), M.lac, { pos: [dx, 0.24 * s, dz] }));
      for (let k = 0; k < 4; k++) { const an = k * 1.7 + dx; deco.add(K.m(tg(new THREE.SphereGeometry(0.03 * s, 8, 6), '#FFFFFF'), M.lac, { pos: [dx + Math.cos(an) * 0.12 * s, 0.24 * s + 0.1 * s, dz + Math.sin(an) * 0.12 * s] })); }
    }
    deco.userData.colliders = [];
    K.finish(game, deco, { ao: { res: 32 } });
    P(null, { group: deco, pos: [a.pos[0], 0, -26.75], rotY: Math.PI });
  });

  const theaterObj = {};
  step('theater', () => buildTheater(game, rt, root, dyn, A, theaterObj));

  step('cyc', () => {
    const cyc = P('chroma_cyc', { pos: [28.35, 0, -25.0], rotY: HP, opts: { width: 3.3, height: 3.4 } });
    // flood lenses stay dark until the Sign-On wave reaches the cyc
    const floods = [];
    cyc.traverse((o) => { if (o.isMesh && o.material?.type === 'MeshBasicMaterial') floods.push([o, o.material]); });
    const off = K.mat(game, 'plastic', '#C8CCD8');
    rt.warmMat(off, ...floods.map((f) => f[1]));
    for (const [o] of floods) { o.userData.noMerge = true; dyn.attach(o); }
    const mark = new THREE.Vector3().fromArray(cyc.userData.anchors?.mark || [0, 0, -1]).applyMatrix4(cyc.matrixWorld);
    O.chroma_cyc = { group: cyc, mark };
    rt.anchor('sb_cyc', { pos: [27.6, 3.0, -25.0], color: '#DDE8FF', intensity: 0, distance: 5 });
    const cycPool = rt.pool([27.35, 0.02, -24.8], 1.5, PAL.gelCyan, 0);
    rt.onPower([28, 3, -25], (on) => {
      for (const [o, m] of floods) o.material = on ? m : off;
      rt.setAnchor('sb_cyc', { intensity: on ? 1.5 : 0 });
      cycPool.set({ intensity: on ? 0.1 : 0 });
    });
  });

  step('blocks', () => {
    const b = [
      P('alphabet_block', { pos: ANCHORS.prop_alpha_block_1.pos, rotY: 0.35, opts: { variant: 0 } }),
      P('alphabet_block', { pos: ANCHORS.prop_alpha_block_2.pos, rotY: -0.2, opts: { variant: 1 } }),
      P('alphabet_block', { pos: ANCHORS.prop_alpha_block_3.pos, rotY: 0.1, opts: { variant: 2 } }),
    ];
    P('alphabet_block', { pos: [25.42, 1.0, -24.02], rotY: 0.62, scale: 0.5, opts: { variant: 2 }, colliders: false });
    O.alpha_blocks = { groups: b };
    // little blocks tumbled around (0.28 m clones: no extra materials)
    for (const [x, z, r, v, s] of [[19.35, -22.0, 0.5, 1, 0.28], [19.55, -21.72, 1.2, 2, 0.26], [17.55, -21.95, 2.0, 0, 0.3],
      [24.9, -23.25, 0.9, 0, 0.28], [27.25, -24.05, 0.3, 1, 0.3], [20.35, -26.75, 1.4, 2, 0.26], [15.65, -26.95, 0.2, 0, 0.3]]) {
      P('alphabet_block', { pos: [x, 0, z], rotY: r, scale: s, opts: { variant: v }, colliders: false });
    }
    P('alphabet_block', { pos: [19.45, 0.28, -21.86], rotY: 0.2, scale: 0.26, opts: { variant: 0 }, colliders: false });
  });

  step('rainbow', () => {
    // Framing the D6 elephant door: walk in from Studio A under the rainbow onto the toy-train loop. (The GDD spot
    // [24.5,-15.5] puts a cloud foot inside D7's doorway and, re-centred on D7, the arch fills the cam_studio_b lens.)
    const g = P('rainbow_arch', { pos: [16.95, 0, -20.1], rotY: HP });
    O.rainbow_arch = { group: g };
  });

  // ------------------------------------------------------------------------------------------- toys
  step('train', () => buildTrain(game, rt, root, O, sfx));
  step('xylophone', () => buildXylophone(game, rt, root, O, sfx));

  // ------------------------------------------------------------------------------------------- feed camera
  step('feed', () => {
    feedCamera(game, rt, root, 'feed_cam_studio_b', { num: 1, side: 0.9 });
    standMonitor(game, rt, root, 'mon_studio_b_stand');
    P('bc_cable_spaghetti', { pos: [21.3, 0, -15.05], rotY: 0.2, opts: { w: 2.4, d: 0.6, count: 3, seed: 4 } });
    // cue-card easel beside the camera
    const easel = K.prop('sb_easel');
    for (const [x, z, rx, rz] of [[-0.2, 0, 0.12, 0.14], [0.2, 0, 0.12, -0.14], [0, 0.28, -0.3, 0]]) easel.add(K.m(tg(K.cyl(0.015, 0.015, 1.25, { seg: 6 }), '#B89868'), M.lac, { pos: [x, 0, z], rot: [rx, 0, rz] }));
    easel.add(K.m(tg(K.box(0.62, 0.04, 0.08, 0.01), '#B89868'), M.lac, { pos: [0, 0.72, -0.1] }));
    easel.add(K.m(tg(K.box(0.62, 0.46, 0.02, 0.006), '#FFFBEF'), M.lac, { pos: [0, 0.98, -0.1], rot: [-0.12, 0, 0] }));
    easel.add(K.m(quad(0.58, 0.42, A.uv('cue1')), A.mat, { pos: [0, 0.98, -0.112], rot: [-0.12, 0, 0] }));
    easel.userData.colliders = [{ min: [-0.26, 0, -0.18], max: [0.26, 1.2, 0.3] }];
    K.finish(game, easel, { ao: { res: 28 } });
    P(null, { group: easel, pos: [20.35, 0, -16.75], rotY: 0.5 });
  });

  // ------------------------------------------------------------------------------------------- west wall corner
  step('west', () => {
    P(null, { group: flat(game, hillsTex(), 5.0, 2.8), pos: [W.w + 0.2, 0, -24.85], rotY: -HP });
    P(null, { group: toyPiano(game, A), pos: [15.62, 0, -23.25], rotY: -HP });
    P('giant_crayons', { pos: [16.0, 0, -25.55], rotY: 0.08 });
    P('giant_crayon', { pos: [17.2, 0, -21.95], rotY: 2.6, opts: { color: 2 }, colliders: false });
    P('giant_crayon', { pos: [27.1, 0, -26.25], rotY: 0.9, opts: { color: 4 }, colliders: false });
    // rainbow story rug + bean bags facing the puppet theater
    P('rug_shag_round', { pos: [18.0, 0.002, -24.05], rotY: 0.3, opts: { r: 1.15, rings: ['#FFE45C', '#FFB347', '#FF8FB8', '#B9A2FF', '#6FD3F0', '#8CE07A'] } });
    P('bean_bag', { pos: [16.62, 0, -24.05], rotY: yawTo([16.62, 0, -24.05], [17.75, 0, -25.9]) + 0.2, opts: { color: '#FF8FB8', seed: 3 } });
    P('bean_bag', { pos: [27.55, 0, -26.3], rotY: yawTo([27.55, 0, -26.3], [25.2, 0, -25.2]), opts: { color: '#6FD3F0', seed: 5 } });
    P('bean_bag', { pos: [28.12, 0, -14.9], rotY: yawTo([28.12, 0, -14.9], [23, 0, -20]), opts: { color: '#FFD23A', seed: 8 } });
  });

  // ------------------------------------------------------------------------------------------- north wall
  step('north', () => {
    P(null, { group: cutout(game, A, 'sunflower', 1.36, 2.16, { stake: 0.2 }), pos: [19.45, 0, -27.66], rotY: Math.PI + 0.06 });
    P(null, { group: cutout(game, A, 'sunflower', 1.2, 1.9, { stake: 0.1 }), pos: [20.72, 0, -27.7], rotY: Math.PI - 0.08 });
    P(null, { group: toyChest(game, A), pos: [20.1, 0, -27.22], rotY: Math.PI - 0.05 });
    P(null, { group: banner(game, A, 'clap', 1.6, 0.43, { color: '#1B2F7A' }), pos: [22.0, 3.95, W.n + 0.03], rotY: Math.PI });
    // backstage behind the theater: puppet crate + stool
    P('bc_flight_case', { pos: [15.75, 0, -27.25], rotY: 0.15, opts: { size: 'md', color: '#B05AD6' } });
  });

  // ------------------------------------------------------------------------------------------- south + east walls
  step('walls', () => {
    P(null, { group: banner(game, A, 'logo', 5.0, 1.47, { color: '#FF8FB8', glossy: true }), pos: [20.4, 3.85, W.s - 0.03], rotY: 0 });
    // kid drawings pinned on a pastel pin board
    const board = K.prop('sb_drawings');
    board.add(K.m(tg(K.box(2.3, 0.95, 0.04, 0.02), '#FFD8E8'), M.lac));
    board.add(K.m(tg(K.box(2.38, 0.05, 0.06, 0.02), '#FFE45C'), M.lac, { pos: [0, 0.5, -0.01] }), K.m(tg(K.box(2.38, 0.05, 0.06, 0.02), '#FFE45C'), M.lac, { pos: [0, -0.5, -0.01] }));
    const rnd = mulberry(31);
    for (let i = 0; i < 6; i++) {
      const x = -0.74 + (i % 3) * 0.74, y = 0.2 - Math.floor(i / 3) * 0.42;
      const q = quad(0.5, 0.375, drawingUV(A, i));
      const m = K.m(q, A.mat, { pos: [x + (rnd() - 0.5) * 0.06, y + (rnd() - 0.5) * 0.04, -0.024 - i * 0.0005], rot: [0, 0, (rnd() - 0.5) * 0.14] });
      board.add(m);
      board.add(K.m(tg(new THREE.SphereGeometry(0.016, 8, 6), PASTEL[i]), M.plastic, { pos: [m.position.x, m.position.y + 0.16, -0.035] }));
    }
    board.userData.colliders = [];
    K.finish(game, board, { ao: false });
    P(null, { group: board, pos: [22.25, 1.55, W.s - 0.03], rotY: 0 });
    P(null, { group: banner(game, A, 'poster', 0.72, 0.96, { color: '#FFE45C' }), pos: [28.15, 1.75, W.s - 0.03], rotY: 0 });
    P(null, { group: banner(game, A, 'peanut', 1.9, 0.48, { color: '#7A4A2A' }), pos: [W.e - 0.03, 2.72, -18.5], rotY: HP });
    P(null, { group: banner(game, A, 'signB', 1.5, 0.7, { color: '#2A1D2A' }), pos: [W.w + 0.03, 3.75, -16.3], rotY: -HP });
    // cut-outs pinned high on the walls (clouds, stars, the sleepy moon, a heart, a note) + star confetti on the floor
    const cuts = [
      ['cloud', 0.9, 0.52, [W.w + 0.02, 4.45, -26.6], -HP], ['cloud', 0.7, 0.4, [W.w + 0.02, 4.05, -23.3], -HP],
      ['star', 0.3, 0.3, [W.w + 0.02, 4.62, -24.9], -HP], ['star', 0.22, 0.22, [W.w + 0.02, 3.9, -22.2], -HP],
      ['cloud', 0.9, 0.52, [W.e - 0.02, 4.4, -26.1], HP], ['moon', 0.5, 0.5, [W.e - 0.02, 4.6, -24.3], HP],
      ['star', 0.28, 0.28, [W.e - 0.02, 4.12, -23.1], HP], ['star', 0.24, 0.24, [20.25, 3.5, W.n + 0.02], Math.PI],
      ['heart', 0.26, 0.26, [21.0, 3.28, W.n + 0.02], Math.PI], ['note', 0.3, 0.27, [19.55, 3.62, W.n + 0.02], Math.PI],
      ['star', 0.26, 0.26, [W.e - 0.02, 3.95, -15.6], HP], ['heart', 0.22, 0.22, [W.e - 0.02, 4.35, -16.4], HP],
    ];
    for (const [reg, w, hh, pos, ry] of cuts) root.add(K.m(quad(w, hh, A.uv(reg)), A.cut, { pos, rot: [0, ry, (pos[0] + pos[2]) % 0.3 - 0.15], cast: false }));
    const rc = mulberry(1977);
    for (let i = 0; i < 34; i++) {
      const x = 15.8 + rc() * 12.4, z = -27.0 + rc() * 12.4;
      if (Math.hypot(x - 22, z + 21) < 2.0 || (z < -26.5 && x > 22.8)) continue;
      const s2 = 0.07 + rc() * 0.06;
      const q = new THREE.PlaneGeometry(s2, s2).rotateX(-HP);
      K.uvRect(q, ...A.uv(i % 3 ? 'star' : 'heart'));
      K.tint(q, PASTEL[i % PASTEL.length]);
      root.add(K.m(q, A.cut, { pos: [x, 0.009, z], rot: [0, rc() * TAU, 0], cast: false }));
    }
    // floor spike marks (tape)
    for (const [x, z, r, s] of [[26.0, -25.75, 0.2, 0.55], [20.55, -23.35, 0.7, 0.45], [24.35, -18.4, 0.1, 0.5], [22.0, -16.9, 0.4, 0.4]]) {
      const q = new THREE.PlaneGeometry(s, s).rotateX(-HP);
      K.uvRect(q, ...A.uv('spike'));
      root.add(K.m(q, A.cut, { pos: [x, 0.011, z], rot: [0, r, 0], cast: false }));
    }
    // leaning cue card against block 1
    const cue = K.prop('sb_cue');
    cue.add(K.m(tg(K.box(0.62, 0.46, 0.02, 0.008), '#FFFBEF'), M.lac));
    cue.add(K.m(quad(0.58, 0.42, A.uv('cue2')), A.mat, { pos: [0, 0, -0.012] }));
    cue.userData.colliders = [];
    K.finish(game, cue, { ao: false });
    const c = P(null, { group: cue, pos: [18.85, 0.22, -21.62], rotY: Math.PI + 0.35, colliders: false });
    c.rotation.x = 0.28;
  });

  step('costume', () => P(null, { group: costumeRack(game), pos: [23.55, 0, -14.72], rotY: 0.04 }));

  // ------------------------------------------------------------------------------------------- sockette clothesline
  step('socks', () => {
    const a = [W.w + 0.02, 3.35, -24.9], b = [16.35, 3.2, W.n + 0.02];
    const pts = sagPts(a, b, 0.28, 14);
    root.add(K.m(tg(K.tube(pts, 0.008, { seg: 28, radial: 4 }), '#F4E6C8'), M.lac, { cast: false }));
    for (const p of [a, b]) root.add(K.m(tg(K.box(0.05, 0.05, 0.05, 0.012), '#C0C6D0'), M.chrome, { pos: p }));
    const at = sampleAlong(pts, 0.42);
    const rnd = mulberry(77);
    at.slice(1, -1).forEach((f, i) => {
      const yaw = Math.atan2(-f.dir.z, f.dir.x);
      const s = 0.85 + rnd() * 0.3;
      const sock = K.m(quad(0.3 * s, 0.3 * s, A.uv('sock')), A.cut, { pos: [f.p.x, f.p.y - 0.15 * s - 0.02, f.p.z], rot: [0, yaw + (i % 2 ? Math.PI : 0), (rnd() - 0.5) * 0.3], cast: false });
      root.add(sock);
      if (i === 1 || i === 4) root.add(K.m(quad(0.12 * s, 0.1 * s, A.uv('eyes')), A.cut, { pos: [f.p.x + Math.sin(yaw) * 0.012, f.p.y - 0.1, f.p.z + Math.cos(yaw) * 0.012], rot: [0, yaw + (i % 2 ? Math.PI : 0), 0], cast: false }));
      root.add(K.m(tg(K.box(0.02, 0.06, 0.02, 0.005), PASTEL[i % PASTEL.length]), M.plastic, { pos: [f.p.x, f.p.y - 0.01, f.p.z], cast: false }));
    });
  });

  // ------------------------------------------------------------------------------------------- overhead
  step('bunting', () => {
    const bg = new THREE.Group();
    bunting(game, bg, [16.0, GRID_Y - 0.05, GZ[0]], [27.9, GRID_Y - 0.05, GZ[0]], 0.55, 0);
    bunting(game, bg, [15.6, GRID_Y - 0.05, GZ[5]], [28.3, GRID_Y - 0.05, GZ[5]], 0.5, 3);
    bunting(game, bg, [GX[5], GRID_Y + 0.04, -22.6], [GX[5], GRID_Y + 0.04, -15.2], 0.45, 5);
    bunting(game, bg, [GX[0], GRID_Y + 0.04, -26.0], [GX[0], GRID_Y + 0.04, -17.6], 0.45, 1);
    bg.traverse((o) => { if (o.isMesh && o.material === M.felt) o.material = pennantMat; });
    root.add(...bg.children.slice());
  });

  step('fairy', () => buildFairyLights(game, rt, dyn));
  step('mobiles', () => buildMobiles(game, rt, dyn, A, glowCut));
  step('balloons', () => {
    const spots = [[19.0, 2.35, -25.72, 11, 5, 1.0, true], [16.95, 1.25, -21.95, 23, 6, 0.9, true], [15.55, 1.36, -23.7, 5, 4, 0.8, false], [23.35, 3.45, -27.1, 17, 4, 0.55, false]];
    const list = [];
    for (const [x, y, z, seed, n, rise, sway] of spots) {
      const g = balloonCluster(game, seed, n, rise);
      g.position.set(x, y, z);
      if (sway) { dyn.add(g); list.push({ g, ph: seed * 0.37 }); } else { g.userData.noMerge = false; root.add(g); }
    }
    rt.onTick((t, dt, vis) => {
      if (!vis) return;
      for (const b of list) { b.g.rotation.z = Math.sin(t * 0.7 + b.ph) * 0.05; b.g.rotation.x = Math.sin(t * 0.53 + b.ph * 2) * 0.04; b.g.rotation.y = Math.sin(t * 0.21 + b.ph) * 0.3; }
    });
  });

  // ------------------------------------------------------------------------------------------- lighting
  step('lights', () => buildLighting(game, rt, root, dyn));

  shadowHygiene(root);
  O.studio_b = { rt, root, dyn, theater: theaterObj };
}

// ============================================================================================ puppet theater (EE)
function buildTheater(game, rt, root, dyn, A, out) {
  const a = ANCHORS.ee_puppet_theater;
  // placed so the playboard ledge (the "sill") sits on the GDD slot line z -25.5
  const pos = [a.pos[0], 0, -26.1];
  const th = place(game, root, 'puppet_theater', { area: AREA, pos, rotY: Math.PI });
  th.userData.noMerge = false;
  th.updateMatrixWorld(true);
  const u = th.userData;
  const W2 = (loc) => new THREE.Vector3().fromArray(loc).applyMatrix4(th.matrixWorld);
  // curtain: both halves under one pivot group (parts stay valid)
  const curtain = new THREE.Group();
  curtain.name = 'curtain';
  curtain.userData.noMerge = true;
  th.add(curtain);
  const cl = u.parts.curtain_l, cr = u.parts.curtain_r;
  for (const c of [cl, cr]) if (c) curtain.attach(c);
  dyn.attach(curtain);
  // slot seats on the ledge above each painted silhouette + golden silhouette overlays on the apron (hidden)
  const AW = 2.1, AH = 1.05, AY = 0.72, D = 0.9;
  const keys = ['owl', 'sock', 'dragon'];
  const silTex = silhouetteTex();
  const silMat = new THREE.MeshBasicMaterial({ map: silTex, alphaTest: 0.4, color: new THREE.Color(1.15, 1.02, 0.78), fog: true });
  rt.warmMat(silMat);
  const parts = { curtain, curtain_l: cl, curtain_r: cr };
  const slots = {}, stage = {}, sils = {};
  keys.forEach((k, i) => {
    const cxPx = [0.18, 0.5, 0.82][i] * 512, cyPx = 0.55 * 256;
    const lx = AW / 2 - (cxPx / 512) * AW, ly = AY + AH / 2 - (cyPx / 256) * AH;
    // overlay: 170 px cell (0.697 m) centred on the silhouette
    const s = 170 / 512 * AW;
    const g = new THREE.PlaneGeometry(s, s);     // faces +z = the theater front (rotY PI)
    const cx0 = [85, 256, 427][i];
    K.uvRect(g, (cx0 - 85) / 512, 1 - (128 + 85) / 256, (cx0 + 85) / 512, 1 - (128 - 85) / 256);
    const sil = new THREE.Mesh(g, silMat);
    sil.name = `sil_${k}`;
    sil.position.copy(W2([lx, ly, -D / 2 - 0.058]));
    sil.rotation.y = 0;
    sil.visible = false;
    dyn.add(sil);
    sils[k] = sil;
    parts[`sil_${k}`] = sil;
    const seat = new THREE.Object3D();
    seat.name = `slot_${k}`;
    seat.position.copy(W2([lx, 1.36, -D / 2 - 0.08]));
    seat.rotation.y = 0;
    dyn.add(seat);
    parts[`slot_${k}`] = seat;
    slots[k] = seat.position.clone();
    stage[k] = u.anchors?.[`stage_${k}`] ? W2(u.anchors[`stage_${k}`]) : seat.position.clone().add(new THREE.Vector3(0, 0, -0.5));
  });
  const state = { open: 0, from: 0, to: 0, t: 0, dur: 0, filled: { owl: false, sock: false, dragon: false } };
  const applyOpen = (k) => {
    state.open = k;
    const sx = 1 - 0.75 * k;
    if (cl) cl.scale.x = sx;
    if (cr) cr.scale.x = sx;
  };
  const obj = {
    group: th, parts, slots, stage,
    puppetOf: { owl: 'ee_puppet_hootie', sock: 'ee_puppet_sockrates', dragon: 'ee_puppet_dudley' },
    keyOf: { ee_puppet_hootie: 'owl', ee_puppet_sockrates: 'sock', ee_puppet_dudley: 'dragon' },
    interact: new THREE.Vector3(...a.interact), interactR: a.interactR ?? 1.5,
    filled: state.filled,
    get open() { return state.open; },
    setOpen(k, seconds = 0.8) {
      k = Math.max(0, Math.min(1, k));
      if (seconds <= 0) { state.dur = 0; applyOpen(k); return; }
      Object.assign(state, { from: state.open, to: k, t: 0, dur: seconds });
    },
    setSlot(key, on = true) {
      if (!(key in state.filled)) return;
      state.filled[key] = !!on;
      sils[key].visible = !!on;
      if (on) {
        game.fx?.burst?.(sils[key].getWorldPosition(new THREE.Vector3()), { count: 18, shape: 'star', colors: ['#FFE45C', '#FFFFFF', '#FF8FB8'], speed: 2.2, size: 0.07, life: 0.8, gravity: 2 });
      }
    },
    reset() { for (const k of keys) obj.setSlot(k, false); obj.setOpen(0, 0); },
  };
  rt.onTick((t, dt) => {
    if (state.dur > 0) {
      state.t += dt;
      const k = Math.min(1, state.t / state.dur);
      const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      applyOpen(state.from + (state.to - state.from) * e);
      if (k >= 1) state.dur = 0;
    }
  });
  rt.onReset(() => obj.reset());
  rt.objects.ee_puppet_theater = obj;
  Object.assign(out, obj);
  // a soft pink pool on the story rug in front of the playhouse (after power) is added by buildLighting
}

// ============================================================================================ toys
function buildTrain(game, rt, root, O, sfx) {
  const a = ANCHORS.toy_train;
  // Loop (x0.85) in the gap between the D6 rainbow, block 1, the rocket and the Wobble-Up sponsor camera (whose
  // footprint covers the GDD toy anchor): centre [18.95,-20.45], tunnel on the east side. The [E] point is the centre.
  const C = [18.95, 0, -20.45];
  const g = place(game, root, 'toy_train_loop', { area: AREA, pos: C, rotY: Math.PI, scale: 0.85 });
  const train = g.userData.parts.train;
  const st = { running: false, t: 0, dur: 0, from: 0, to: 0, puff: 0 };
  const chimney = new THREE.Vector3();
  const obj = {
    group: g, parts: { train },
    get running() { return st.running; },
    run(laps = 2) {
      if (st.running) return 0;
      Object.assign(st, { running: true, t: 0, dur: 1.6 * laps, from: train.rotation.y, to: train.rotation.y + laps * TAU, puff: 0 });
      return st.dur;
    },
  };
  O.toy_train = obj;
  rt.onTick((t, dt) => {
    if (!st.running) return;
    st.t += dt;
    const k = Math.min(1, st.t / st.dur);
    const ease = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;   // pull away, cruise, brake
    train.rotation.y = st.from + (st.to - st.from) * ease;
    st.puff -= dt;
    if (st.puff <= 0 && k < 0.95) {
      st.puff = 0.22;
      train.updateMatrixWorld(true);
      train.localToWorld(chimney.set(1.1, 0.5, -0.14));
      game.fx?.burst?.(chimney, { count: 2, shape: 'puff', colors: ['#FFFFFF', '#EDE6FF'], speed: 0.45, size: 0.1, life: 0.7, gravity: -1.2, drag: 3 });
    }
    if (k >= 1) { st.running = false; train.rotation.y = st.to % TAU; }
  });
  rt.onReset(() => { st.running = false; train.rotation.y = 0; });
  game.interact?.register?.({
    id: 'toy_train', pos: [C[0], a.pos[1], C[2]], radius: 1.6, prompt: () => ({}),
    use: () => { if (obj.run(2)) { sfx('toy_train', [C[0], 0.4, C[2]]); game.events?.emit?.('toy:use', { id: 'toy_train' }); } },
  });
}

const BUMP = new Float32Array(16);
function buildXylophone(game, rt, root, O, sfx) {
  const a = ANCHORS.toy_xylophone;
  const g = place(game, root, 'xylophone', { area: AREA, pos: [a.pos[0], 0, a.pos[2]], rotY: Math.PI });
  const { bars, mallets } = g.userData.parts;
  const xf = g.userData.bars || [];
  const base = [];
  const m4 = new THREE.Matrix4();
  for (let i = 0; i < bars.count; i++) { bars.getMatrixAt(i, m4); base.push(m4.clone()); }
  const MIDI = [72, 74, 76, 77, 79, 81, 83, 84];      // bar 0 = longest (C5) ... bar 7 = shortest (C6)
  const PENTA = [0, 1, 2, 4, 5, 7];                   // C D E G A C (the audio cue's pentatonic pool)
  const hits = [];                                    // { bar, t0 }
  const st = { t: 0, busy: 0, mallet: 0 };
  const off = new THREE.Matrix4();
  const obj = {
    group: g, parts: { bars, mallets },
    play(list = null) {
      if (st.busy > 0) return 0;
      const notes = list || [0, 1, 2].map(() => PENTA[Math.floor(Math.random() * PENTA.length)]);
      notes.forEach((b, k) => hits.push({ bar: b, t0: st.t + k * 0.18 }));
      st.busy = notes.length * 0.18 + 0.35;
      sfx('toy_xylophone', [a.pos[0], 0.7, a.pos[2]], { notes: notes.map((b) => MIDI[b]) });
      return st.busy;
    },
  };
  O.toy_xylophone = obj;
  rt.onTick((t, dt, vis) => {
    st.t += dt;
    if (st.busy > 0) st.busy -= dt;
    if (!hits.length) return;
    const bump = BUMP.fill(0);
    let mal = 0;
    for (let i = hits.length - 1; i >= 0; i--) {
      const h = hits[i], k = st.t - h.t0;
      if (k > -0.12 && k < 0) mal = Math.max(mal, Math.sin(((k + 0.12) / 0.12) * Math.PI));
      if (k < 0) continue;
      if (k > 0.5) { hits.splice(i, 1); continue; }
      bump[h.bar] = Math.max(bump[h.bar], Math.sin(Math.min(1, k / 0.5) * Math.PI) * Math.exp(-k * 5));
    }
    for (let i = 0; i < bars.count; i++) {
      off.makeTranslation(0, -0.02 * bump[i], 0);
      m4.copy(off).multiply(base[i]);
      bars.setMatrixAt(i, m4);
    }
    bars.instanceMatrix.needsUpdate = true;
    if (mallets) mallets.position.y = 0.07 * mal;
    if (!hits.length) { for (let i = 0; i < bars.count; i++) bars.setMatrixAt(i, base[i]); bars.instanceMatrix.needsUpdate = true; if (mallets) mallets.position.y = 0; }
    void xf; void vis;
  });
  game.interact?.register?.({
    id: 'toy_xylophone', pos: [a.pos[0], a.pos[1], a.pos[2]], radius: 1.4, prompt: () => ({}),
    use: () => { if (obj.play()) game.events?.emit?.('toy:use', { id: 'toy_xylophone' }); },
  });
}

// ============================================================================================ fairy lights
function buildFairyLights(game, rt, dyn) {
  const M = studioMats(game);
  const runs = [
    [[15.4, 4.25, W.n + 0.05], [22.9, 4.3, W.n + 0.05], 0.4],
    [[W.w + 0.05, 3.4, -27.5], [W.w + 0.05, 3.4, -22.0], 0.32],
    [[W.e - 0.05, 3.5, -20.6], [W.e - 0.05, 3.5, -15.0], 0.3],
    [[15.6, 4.72, W.s - 0.05], [24.5, 4.72, W.s - 0.05], 0.3],
  ];
  const wire = new THREE.Group();
  const bulbs = [[], []];
  const cols = ['#FF5F7F', '#FFD23A', '#6FD3F0', '#8CE07A', '#B9A2FF', '#FF9A3C'];
  let n = 0;
  for (const [a, b, sag] of runs) {
    const pts = [];
    const segs = 4;
    for (let s = 0; s < segs; s++) {
      const A = a.map((v, i) => v + (b[i] - v) * (s / segs)), B = a.map((v, i) => v + (b[i] - v) * ((s + 1) / segs));
      const sp = sagPts(A, B, sag * 0.6, 8);
      pts.push(...(s ? sp.slice(1) : sp));
    }
    wire.add(K.m(tg(K.tube(pts, 0.005, { seg: pts.length * 2, radial: 3 }), '#2A4A2A'), M.lac, { cast: false }));
    for (const f of sampleAlong(pts, 0.26)) {
      const c = new THREE.Color(cols[n % cols.length]).multiplyScalar(2.2);
      const geo = new THREE.IcosahedronGeometry(0.032, 1);
      geo.translate(f.p.x, f.p.y - 0.035, f.p.z);
      K.tint(geo, c);
      bulbs[n % 2].push(geo);
      n++;
    }
  }
  for (const m of wire.children.slice()) dyn.parent.add(m);
  const matA = new THREE.MeshBasicMaterial({ vertexColors: true, color: new THREE.Color(0.55, 0.55, 0.55), fog: true });
  const matB = matA.clone();
  const meshes = bulbs.map((list, i) => {
    const merged = mergeList(list);
    const mesh = new THREE.Mesh(merged, i ? matB : matA);
    mesh.name = `sb_fairy_${i}`;
    mesh.castShadow = false;
    mesh.frustumCulled = true;
    dyn.add(mesh);
    return mesh;
  });
  void meshes;
  let level = 0.55;
  rt.onPower([22, 4, -21], (on) => { level = on ? 0.95 : 0.55; });
  rt.onTick((t, dt, vis) => {
    if (!vis) return;
    const k1 = level * (0.78 + 0.22 * Math.sin(t * 2.3)), k2 = level * (0.78 + 0.22 * Math.sin(t * 2.3 + Math.PI));
    matA.color.setScalar(k1);
    matB.color.setScalar(k2);
  });
}
function mergeList(list) {
  let pos = 0, idx = 0;
  for (const g of list) { pos += g.attributes.position.count; idx += g.index ? g.index.count : g.attributes.position.count; }
  const P = new Float32Array(pos * 3), C = new Float32Array(pos * 3), N = new Float32Array(pos * 3), I = new Uint32Array(idx);
  let po = 0, io = 0;
  for (const g of list) {
    const c = g.attributes.position.count;
    P.set(g.attributes.position.array, po * 3);
    C.set(g.attributes.color.array, po * 3);
    N.set(g.attributes.normal.array, po * 3);
    if (g.index) { for (let i = 0; i < g.index.count; i++) I[io + i] = g.index.array[i] + po; io += g.index.count; } else { for (let i = 0; i < c; i++) I[io + i] = po + i; io += c; }
    po += c;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(P, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(N, 3));
  out.setAttribute('color', new THREE.BufferAttribute(C, 3));
  out.setIndex(new THREE.BufferAttribute(I, 1));
  out.computeBoundingSphere();
  return out;
}

// ============================================================================================ mobiles
function buildMobiles(game, rt, dyn, A, glowCut) {
  const specs = [
    // moon lantern + stars over the story rug (the moon glows: the night-light theme)
    { at: [17.55, GRID_Y, GZ[1]], drop: 0.95, bar: 1.3, items: [
      { region: 'moon', w: 0.62, h: 0.62, at: [0, 0], hang: 0.25, glow: true },
      { region: 'star', w: 0.34, h: 0.34, at: [0.62, 0], hang: 0.45 },
      { region: 'star', w: 0.28, h: 0.28, at: [-0.6, 0], hang: 0.6, rot: 0.8 },
      { region: 'cloud', w: 0.62, h: 0.36, at: [0, -0.4], hang: 0.35, rot: 1.2 },
      { region: 'star', w: 0.22, h: 0.22, at: [0, 0.42], hang: 0.8, rot: 2.1 },
    ] },
    // planets near the rocket nose
    { at: [GX[3], GRID_Y + 0.09, -23.3], drop: 0.85, bar: 1.4, items: [
      { region: 'saturn', w: 0.8, h: 0.48, at: [0.68, 0], hang: 0.3 },
      { region: 'star', w: 0.3, h: 0.3, at: [-0.68, 0], hang: 0.5, rot: 0.5 },
      { region: 'moon', w: 0.36, h: 0.36, at: [0, -0.45], hang: 0.62, rot: 2.4 },
      { region: 'heart', w: 0.26, h: 0.26, at: [0, 0.46], hang: 0.4, rot: 1.0 },
    ] },
    // clouds + raindrops over the rainbow
    { at: [GX[0], GRID_Y + 0.09, -20.1], drop: 0.62, bar: 1.3, items: [
      { region: 'cloud', w: 0.8, h: 0.46, at: [0.6, 0], hang: 0.25 },
      { region: 'raindrop', w: 0.18, h: 0.22, at: [-0.62, 0], hang: 0.55, rot: 0.3 },
      { region: 'raindrop', w: 0.16, h: 0.2, at: [0, -0.44], hang: 0.75, rot: 1.3 },
      { region: 'star', w: 0.26, h: 0.26, at: [0, 0.45], hang: 0.5, rot: 2.2 },
    ] },
  ];
  const list = specs.map((s, i) => {
    const m = mobile(game, A, s.items, { drop: s.drop, bar: s.bar, glowMat: glowCut });
    m.position.set(...s.at);
    dyn.add(m);
    return { m: m.userData.spin, sp: 0.12 + i * 0.05, ph: i * 1.3 };
  });
  rt.onTick((t, dt, vis) => {
    if (!vis) return;
    for (const L of list) { L.m.rotation.y = L.ph + t * L.sp; L.m.rotation.z = Math.sin(t * 0.6 + L.ph) * 0.02; }
  });
}

// ============================================================================================ lighting
function buildLighting(game, rt, root, dyn) {
  const M = studioMats(game);
  // pre-power night-lights (GDD §3.3): the treehouse moon window + the paper-moon lantern, fairy glow
  rt.anchor('sb_moon', { pos: [26.2, 3.6, -26.2], color: '#BFD4FF', intensity: 3.2, distance: 9 });
  rt.anchor('sb_lantern', { pos: [17.55, 3.7, -24.2], color: '#BFD4FF', intensity: 2.0, distance: 7.5 });
  rt.anchor('sb_fairy', { pos: [16.0, 3.3, -25.2], color: '#FFB6C8', intensity: 1.0, distance: 5.5 });
  const moonPool = rt.pool([26.0, 0.02, -25.3], 2.6, '#BFD4FF', 0.17);
  const lanternPool = rt.pool([17.6, 0.03, -24.2], 1.8, '#BFD4FF', 0.1);
  // post-power pastel fills (pink west, lilac east) + pastel pools
  rt.anchor('sb_fill_pink', { pos: [18.4, 3.3, -21.2], color: '#FFB6C8', intensity: 0, distance: 10 });
  rt.anchor('sb_fill_lilac', { pos: [25.8, 3.3, -20.8], color: '#C9A7FF', intensity: 0, distance: 10 });
  const pools = [
    rt.pool([17.75, 0.035, -24.6], 2.2, '#FF8FB8', 0),
    rt.pool([25.9, 0.02, -25.4], 2.3, '#C9A7FF', 0),
    rt.pool([19.3, 0.02, -18.4], 1.9, '#FFE45C', 0),
    rt.pool([26.0, 0.02, -17.6], 2.0, '#FF8FB8', 0),
    rt.pool([22.0, 0.02, -21.0], 2.6, '#FFF1C9', 0),
  ];
  rt.onPower([22, 3, -21], (on) => {
    rt.setAnchor('sb_moon', { intensity: on ? 1.0 : 3.2 });
    rt.setAnchor('sb_lantern', { intensity: on ? 0.7 : 2.0 });
    rt.setAnchor('sb_fairy', { intensity: on ? 0.5 : 1.0 });
    rt.setAnchor('sb_fill_pink', { intensity: on ? 2.4 : 0 });
    rt.setAnchor('sb_fill_lilac', { intensity: on ? 2.4 : 0 });
    moonPool.set({ intensity: on ? 0.05 : 0.17 });
    lanternPool.set({ intensity: on ? 0.03 : 0.1 });
    const I = [0.15, 0.13, 0.12, 0.12, 0.06];
    pools.forEach((p, i) => p.set({ intensity: on ? I[i] : 0 }));
  });

  // pastel gel Fresnels on the grid (lenses swap at power) + soft beams on the theater and Hootie's TV
  const lensGroup = new THREE.Group();
  lensGroup.userData.noMerge = true;
  dyn.add(lensGroup);
  const specs = [
    { pos: [17.9, GZ[1]], rotY: 0, gel: 'magenta', tilt: 1.15, beam: [17.75, 1.5, -25.6], color: '#FF8FB8' },
    { pos: [25.9, GZ[1]], rotY: 0, gel: 'purple', tilt: 0.85, beam: [26.0, 1.1, -26.9], color: '#C9A7FF' },
    { pos: [19.6, GZ[3]], rotY: Math.PI, gel: 'yellow', tilt: 1.0 },
    { pos: [24.6, GZ[3]], rotY: Math.PI, gel: 'magenta', tilt: 0.95 },
    { pos: [GX[5], -25.0], rotY: -HP, gel: 'cyan', tilt: 1.15, zpipe: true },
  ];
  const lights = specs.map((s) => {
    const f = place(game, root, 'bc_light_fresnel', { area: AREA, pos: [s.pos[0], 0, s.pos[1]], rotY: s.rotY, opts: { gel: s.gel, tilt: s.tilt, lit: false }, colliders: false });
    f.position.y = (s.zpipe ? GRID_Y + 0.09 : GRID_Y) - f.userData.hang.pipeY;
    f.updateMatrixWorld(true);
    unlockParts(f, ['head']);
    return f;
  });
  harvestLenses(lights, lensGroup);
  K.merge(lensGroup);
  const lampOn = lights[0].userData.lampMats?.on, lampOff = lights[0].userData.lampMats?.off;
  if (lampOn && lampOff) {
    rt.warmMat(lampOn, lampOff);
    rt.onPower([22, 5, -22], (on) => { lensGroup.traverse((o) => { if (o.isMesh) o.material = on ? lampOn : lampOff; }); });
  }
  const beams = [];
  specs.forEach((s, i) => {
    if (!s.beam) return;
    const f = lights[i];
    const lens = new THREE.Vector3().fromArray(f.userData.aim?.pos || [0, -0.36, -0.2]).applyMatrix4(f.matrixWorld);
    const tgt = new THREE.Vector3(...s.beam);
    const len = lens.distanceTo(tgt);
    const geo = new THREE.CylinderGeometry(0.75, 0.1, 1, 20, 1, true).translate(0, 0.5, 0).rotateX(HP);
    const mat = M.beam.clone();
    mat.uniforms.uColor.value.set(s.color);
    mat.uniforms.uI.value = 0.2;
    const m = new THREE.Mesh(geo, mat);
    m.position.copy(lens);
    m.lookAt(tgt);
    m.scale.set(1, 1, len);
    m.visible = false;
    m.renderOrder = 3;
    m.frustumCulled = false;
    dyn.add(m);
    rt.warmMat(mat);
    beams.push(m);
  });
  rt.onPower([22, 5, -24], (on) => { for (const b of beams) b.visible = on; });
}

// Parts the level will not merge each cost a shadow draw: unlit glow and parts under ~0.3 m never cast.
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
      const small = r < 0.3 && !o.isInstancedMesh;
      if (small || (m && (m.type === 'MeshBasicMaterial' || m.type === 'ShaderMaterial'))) o.castShadow = false;
    }
    for (const c of o.children) walk(c, um);
  };
  walk(root, false);
}
