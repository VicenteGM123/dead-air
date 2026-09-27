// Newsroom "ACTION 13 NEWS" set dressing (GDD §5.7, §3.3, §13 toys; ARCHITECTURE §7/§12). Owner: rooms-news-mc.
// build(game, area, root) runs once from level.build() after the graybox; static meshes are merged per material by
// the level afterwards, animated parts are flagged noMerge. Props come from src/props (placeProp registers their
// colliders, light anchors and screens); a few room-only props are registered here (ids nm_*).
//
// Layout (world metres; walls inner faces x 7.15 / 22.85, z -5.85 / 3.85):
//   anchor riser x 18..22 z -2..2 (0.4 m): curved anchor desk (ee_anchor_desk) facing west, empty anchor chair
//   (ee_anchor_chair), floor globe (toy_globe), two Fresnels on a batten; skyline backdrop + 3 world clocks at 11:59
//   on the east wall; reporter desks 2 x 3 (north row faces the aisle from z -3.55, south row from z 1.05, 0.9 m
//   weave gaps); central aisle z ~-2.3..0 from D1 to the riser; teletype (toy_teletype) in the NW corner with its
//   work lamp (lit before power); weather map (ee_weather_map) on the north wall; coffee cart + water cooler;
//   ss_newsroom monitor bank in the SE corner; feed camera + cart monitor (scr_feed_newsroom); T2 Telly nook (SW,
//   left empty for the Telly agent); moonlight slats under B4/B5 (strong before power).
//
// game.level.objects (created if missing) — ids registered here:
//   ee_anchor_desk  { group, parts:{hairspray}, top:[x,y,z] (puppet seat), drop:[x,y,z] }
//   ee_anchor_chair { group }
//   ee_weather_map  { group, parts:{magnet_sun_a, magnet_sun_b, magnet_cloud, magnet_rain, magnet_bolt, magnet_storm},
//                     anchors (local), towerIcon:Vector3 (world), showMagnet(name, [x,y]|null) (local face coords),
//                     slide(name, [x,y], seconds) (eased slide, world time), flash(on) (map hood light boost) }
//   ss_newsroom     { group, screen (the screen-spawn CRT), screens[] }         mon_newsroom_cart { group, screen }
//   feed_cam_newsroom { group, parts:{head, tilt, tally, lensTip}, setTally(on) }  (head pans ±20° / 8 s here)
//   toy_typewriter / toy_globe / toy_teletype { group, parts, play() }
//   clocks_newsroom { parts:{ny, london, tokyo}, set(h, m, s) }                  skyline_backdrop { group, wash }
// Toys (GDD §13): key-only [E] prompts via game.interact, cues toy_typewriter / toy_globe / toy_teletype.
// Power: lights, washes, lamps and tallies switch as the Sign-On colour wave reaches them (signon.waveReached(pos)
// when available, else distance-from-lever / 15 m/s after power:on) with the level's 3-flash flicker; a machines
// power reset (new game) switches everything back off.
//
// Shared room toolkit (also used by master_control.js): runtime(game, areaId), stdMats(game), atlas(game),
// quad(w, h, cell), ribbon(points, width), obj(game, id, o), place(...), pool(...), yawTo(a, b), setClockHands(...).

import * as THREE from 'three';
import * as K from '../../props/kit.js';
import { registerProp, PAL } from '../../props/kit.js';
import { placeProp } from '../../props/index.js';
import { setLamp } from '../../props/broadcast.js';
import { showMagnet } from '../../props/sets.js';
import { mulberry32 } from '../../core/rng.js';
import { ANCHORS } from '../layout.js';

const TAU = Math.PI * 2;
const HP = Math.PI / 2;
const WAVE_SPEED = 15;
const FLICKER = [[0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]];
const LEVER = new THREE.Vector3(...ANCHORS.sign_on_lever.pos).setY(1);

// ================================================================================================ toolkit
export const yawTo = (from, to) => Math.atan2(-(to[0] - from[0]), -(to[2] - from[2]));
export const tc = (geo, color) => K.tint(geo.clone(), color);
const v3 = (a) => new THREE.Vector3(a[0], a[1], a[2]);

// The furniture kit's shared white-base materials (vertex tints carry the colour): same instances as the
// library's props, so the level merge folds our meshes into the draws it already has.
export function stdMats(game) {
  return {
    plastic: K.mat(game, 'plastic', '#ffffff'),
    lacquer: K.mat(game, 'lacquer', '#ffffff'),
    paint: K.mat(game, 'paint', '#ffffff'),
    metal: K.mat(game, 'metal', '#ffffff'),
    chrome: K.mat(game, 'chrome', '#A8B0BA'),
    brass: K.mat(game, 'brass', '#C8963C'),
    rubber: K.mat(game, 'rubber', '#ffffff'),
    fabric: K.mat(game, 'fabric', '#ffffff'),
    teak: K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood(PAL.teak, { dark: 0.36 }) }),
    walnut: K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.42 }) }),
  };
}

// ------------------------------------------------------------------------------------------------ atlas
// 1024² paper/print atlas (4 x 4 cells of 256 px) shared by both rooms + a 512² alpha atlas (2 x 2) for floor
// decals. cell(c, r) -> [u0, v0, u1, v1] (r counted from the top).
const CELLS = {
  page: [0, 0], news: [1, 0], wire: [2, 0], memo: [3, 0],
  sched: [0, 1], quiet: [1, 1], eng: [2, 1], spines: [3, 1],
  bars: [0, 2], donut: [1, 2], logo13: [2, 2], promo: [3, 2],
  panel: [0, 3], plate: [1, 3], assign: [2, 3], cream: [3, 3],
};
const DECALS = { stain: [0, 0], scuff: [1, 0], tapeX: [0, 1], dust: [1, 1] };

function drawText(ctx, s, x, y, { font = 'Bungee', size = 20, fill = '#222', align = 'center', rot = 0, maxW = 0 } = {}) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot);
  let sz = size;
  ctx.font = `${sz}px "${font}", "Arial Black", sans-serif`;
  if (maxW) while (ctx.measureText(s).width > maxW && sz > 6) { sz *= 0.92; ctx.font = `${sz}px "${font}", "Arial Black", sans-serif`; }
  ctx.textAlign = align;
  ctx.textBaseline = 'middle';
  ctx.fillStyle = fill;
  ctx.fillText(s, 0, 0);
  ctx.restore();
}
function rrect(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
function lines(ctx, x, y, w, rows, gap, rand, color = 'rgba(40,40,60,0.55)', thick = 3) {
  ctx.fillStyle = color;
  for (let i = 0; i < rows; i++) {
    const len = w * (0.55 + rand() * 0.45);
    ctx.fillRect(x, y + i * gap, len, thick);
  }
}

function paintAtlas(ctx, W, H, rand) {
  const S = 256;
  const at = (c, r, fn) => { ctx.save(); ctx.translate(c * S, r * S); ctx.beginPath(); ctx.rect(0, 0, S, S); ctx.clip(); fn(); ctx.restore(); };
  // typed page
  at(0, 0, () => {
    ctx.fillStyle = '#F7F2E4'; ctx.fillRect(0, 0, S, S);
    ctx.fillStyle = '#E23B3B'; ctx.fillRect(18, 18, 120, 10);
    drawText(ctx, 'ACTION 13 NEWS', 22, 42, { font: 'Titan One', size: 16, fill: '#2F5BD3', align: 'left' });
    lines(ctx, 22, 66, 210, 11, 16, rand, 'rgba(50,40,60,0.6)', 4);
    ctx.strokeStyle = 'rgba(226,59,59,0.7)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(30, 150); ctx.lineTo(190, 146); ctx.stroke();
  });
  // newspaper
  at(1, 0, () => {
    ctx.fillStyle = '#EDE6D2'; ctx.fillRect(0, 0, S, S);
    drawText(ctx, 'THE DAILY SIGNAL', S / 2, 26, { font: 'Shrikhand', size: 26, fill: '#2A2230', maxW: 230 });
    ctx.fillStyle = '#2A2230'; ctx.fillRect(12, 44, S - 24, 3);
    drawText(ctx, 'TELETHON TONIGHT!', S / 2, 70, { font: 'Bungee', size: 24, fill: '#2A2230', maxW: 230 });
    ctx.fillStyle = '#9A9080'; ctx.fillRect(14, 92, 104, 76);
    ctx.fillStyle = '#6A6258'; ctx.beginPath(); ctx.arc(66, 128, 22, 0, TAU); ctx.fill();
    lines(ctx, 128, 96, 112, 8, 10, rand, 'rgba(40,40,50,0.55)', 3);
    lines(ctx, 14, 182, 228, 6, 11, rand, 'rgba(40,40,50,0.55)', 3);
  });
  // teletype wire copy (continuous feed)
  at(2, 0, () => {
    ctx.fillStyle = '#F4EBC8'; ctx.fillRect(0, 0, S, S);
    for (let i = 0; i < 4; i++) { ctx.fillStyle = 'rgba(160,140,90,0.25)'; ctx.fillRect(0, i * 64 + 30, S, 2); }
    const words = ['ZCZC', 'BULLETIN', 'WZTV', 'WIRE', 'MORE', 'URGENT', 'CITY', 'STORM', 'WATCH', 'NNNN', 'TOWER', '11:59'];
    ctx.font = 'bold 15px "Courier New", monospace'; ctx.fillStyle = '#3A3050'; ctx.textBaseline = 'middle';
    for (let i = 0; i < 14; i++) {
      let s = '';
      for (let k = 0; k < 3 + Math.floor(rand() * 3); k++) s += words[Math.floor(rand() * words.length)] + ' ';
      ctx.fillText(s, 14, 14 + i * 17);
    }
  });
  // yellow memo
  at(3, 0, () => {
    ctx.fillStyle = '#FFF0A0'; ctx.fillRect(0, 0, S, S);
    ctx.fillStyle = 'rgba(0,0,0,0.07)'; ctx.fillRect(0, S - 24, S, 24);
    drawText(ctx, 'CALL BACK', S / 2, 60, { font: 'Titan One', size: 30, fill: '#2A2A8A', rot: -0.05 });
    drawText(ctx, 'STU RE: FORECAST', S / 2, 110, { font: 'Titan One', size: 22, fill: '#2A2A8A', rot: -0.04, maxW: 220 });
    drawText(ctx, 'x 1313', S / 2, 160, { font: 'Titan One', size: 26, fill: '#E23B3B', rot: -0.03 });
  });
  // on-air schedule chart
  at(0, 1, () => {
    ctx.fillStyle = '#F6E7C8'; ctx.fillRect(0, 0, S, S);
    ctx.fillStyle = '#2F5BD3'; ctx.fillRect(0, 0, S, 34);
    drawText(ctx, 'ON-AIR SCHEDULE', S / 2, 18, { font: 'Bungee', size: 18, fill: '#F4F1E8', maxW: 230 });
    const cols = [PAL.harvestGold, PAL.burntOrange, PAL.avocado, PAL.teal, PAL.plum, PAL.channelRed];
    for (let r = 0; r < 7; r++) {
      drawText(ctx, `${(6 + r * 3) % 12 || 12}:00`, 30, 52 + r * 28, { font: 'Titan One', size: 13, fill: '#5A3A22' });
      let x = 58;
      while (x < S - 10) {
        const w = 30 + Math.floor(rand() * 60);
        ctx.fillStyle = cols[Math.floor(rand() * cols.length)];
        rrect(ctx, x, 42 + r * 28, Math.min(w, S - 10 - x), 20, 5); ctx.fill();
        x += w + 4;
      }
    }
  });
  // QUIET sign
  at(1, 1, () => {
    ctx.fillStyle = '#E23B3B'; rrect(ctx, 6, 6, S - 12, S - 12, 24); ctx.fill();
    ctx.strokeStyle = '#F4F1E8'; ctx.lineWidth = 8; rrect(ctx, 18, 18, S - 36, S - 36, 16); ctx.stroke();
    drawText(ctx, 'QUIET!', S / 2, 96, { font: 'Bungee', size: 58, fill: '#F4F1E8' });
    drawText(ctx, "WE'RE ON", S / 2, 158, { font: 'Titan One', size: 32, fill: '#FFE3A3' });
    drawText(ctx, 'THE AIR', S / 2, 196, { font: 'Titan One', size: 32, fill: '#FFE3A3' });
  });
  // ENGINEERING sign
  at(2, 1, () => {
    ctx.fillStyle = '#F4C21E'; rrect(ctx, 6, 6, S - 12, S - 12, 20); ctx.fill();
    ctx.fillStyle = '#1E1530'; ctx.fillRect(6, 80, S - 12, 96);
    ctx.beginPath(); ctx.moveTo(52, 20); ctx.lineTo(28, 66); ctx.lineTo(48, 66); ctx.lineTo(36, 104); ctx.lineTo(74, 50); ctx.lineTo(54, 50); ctx.closePath(); ctx.fill();
    drawText(ctx, 'DANGER', 160, 44, { font: 'Bungee', size: 34, fill: '#1E1530' });
    drawText(ctx, 'ENGINEERING', S / 2, 112, { font: 'Bungee', size: 28, fill: '#F4C21E', maxW: 230 });
    drawText(ctx, 'AUTHORIZED ONLY', S / 2, 150, { font: 'Titan One', size: 20, fill: '#F4F1E8', maxW: 230 });
    drawText(ctx, 'HIGH VOLTAGE', S / 2, 214, { font: 'Bungee', size: 22, fill: '#E23B3B' });
  });
  // tape box spines (8 per cell, vertical strips)
  at(3, 1, () => {
    const cols = ['#2F5BD3', '#E23B3B', '#E8A92E', '#2A2230', '#8C9A3A', '#E3662B', '#6B3A6E', '#2E8C8C'];
    for (let i = 0; i < 8; i++) {
      const x = i * 32;
      ctx.fillStyle = cols[i]; ctx.fillRect(x, 0, 32, S);
      ctx.fillStyle = '#F6EFD8'; ctx.fillRect(x + 5, 40, 22, 130);
      ctx.fillStyle = 'rgba(40,30,60,0.7)';
      for (let k = 0; k < 5; k++) ctx.fillRect(x + 9, 52 + k * 22, 14 * (0.5 + rand() * 0.5), 4);
      ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.fillRect(x, 0, 3, S);
    }
  });
  // SMPTE bars chart poster
  at(0, 2, () => {
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 0, S, S);
    PAL.BARS.forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(14 + i * 32.6, 40, 32.6, 130); });
    ctx.fillStyle = '#1E1530'; ctx.fillRect(14, 170, 228, 30);
    drawText(ctx, 'SMPTE TEST', S / 2, 22, { font: 'Bungee', size: 20, fill: '#1E1530' });
    drawText(ctx, 'ALIGN DAILY  1 kHz  0 dB', S / 2, 226, { font: 'Titan One', size: 14, fill: '#5A3A22', maxW: 230 });
  });
  // donut box lid print
  at(1, 2, () => {
    ctx.fillStyle = '#FFB6C8'; ctx.fillRect(0, 0, S, S);
    for (let i = 0; i < 8; i++) { ctx.fillStyle = i % 2 ? '#F4F1E8' : '#FF8FAE'; ctx.fillRect(i * 32, 0, 16, S); }
    ctx.fillStyle = '#F4F1E8'; rrect(ctx, 30, 70, 196, 116, 20); ctx.fill();
    drawText(ctx, 'DOUGH-NUTS', S / 2, 110, { font: 'Shrikhand', size: 32, fill: '#E23B3B', maxW: 180 });
    drawText(ctx, 'FRESH DAILY', S / 2, 152, { font: 'Titan One', size: 18, fill: '#5A3A22' });
  });
  // round ACTION 13 NEWS logo
  at(2, 2, () => {
    ctx.fillStyle = '#E8A92E'; ctx.beginPath(); ctx.arc(S / 2, S / 2, 124, 0, TAU); ctx.fill();
    ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(S / 2, S / 2, 104, 0, TAU); ctx.fill();
    ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.arc(S / 2, S / 2, 88, 0, TAU); ctx.fill();
    drawText(ctx, '13', S / 2, S / 2 + 6, { font: 'Shrikhand', size: 96, fill: '#F4F1E8' });
    drawText(ctx, 'ACTION', S / 2, 58, { font: 'Bungee', size: 20, fill: '#F4F1E8' });
    drawText(ctx, 'NEWS', S / 2, 206, { font: 'Bungee', size: 22, fill: '#F4F1E8' });
  });
  // promo poster
  at(3, 2, () => {
    const g = ctx.createLinearGradient(0, 0, 0, S);
    g.addColorStop(0, '#2F5BD3'); g.addColorStop(1, '#6B3A6E');
    ctx.fillStyle = g; ctx.fillRect(0, 0, S, S);
    for (let i = 0; i < 5; i++) { ctx.fillStyle = [PAL.harvestGold, PAL.burntOrange, PAL.channelRed, PAL.plum, PAL.teal][i]; ctx.fillRect(0, 150 + i * 12, S, 8); }
    drawText(ctx, "WE'RE ON", S / 2, 50, { font: 'Shrikhand', size: 40, fill: '#F6E7C8' });
    drawText(ctx, 'YOUR SIDE', S / 2, 98, { font: 'Shrikhand', size: 40, fill: '#FFC23A' });
    drawText(ctx, 'ACTION 13 NEWS  6 & 11', S / 2, 230, { font: 'Titan One', size: 17, fill: '#F4F1E8', maxW: 230 });
  });
  // equipment panel with LEDs
  at(0, 3, () => {
    ctx.fillStyle = '#3A3440'; ctx.fillRect(0, 0, S, S);
    for (let r = 0; r < 6; r++) for (let c = 0; c < 8; c++) {
      ctx.fillStyle = ['#52E04A', '#FFB347', '#FF3B30', '#7FE7FF', '#3A3A44'][Math.floor(rand() * 5)];
      ctx.beginPath(); ctx.arc(24 + c * 30, 30 + r * 38, 7, 0, TAU); ctx.fill();
    }
  });
  // nameplates (top: WIRE SERVICE, bottom: LAFF-O-MATIC)
  at(1, 3, () => {
    ctx.fillStyle = '#2A2230'; ctx.fillRect(0, 0, S, S);
    ctx.fillStyle = '#C8963C'; rrect(ctx, 8, 12, S - 16, 104, 14); ctx.fill();
    ctx.fillStyle = '#2A2230'; rrect(ctx, 16, 20, S - 32, 88, 10); ctx.fill();
    drawText(ctx, 'WZTV WIRE', S / 2, 64, { font: 'Bungee', size: 34, fill: '#E8B84A', maxW: 210 });
    ctx.fillStyle = '#F4F1E8'; rrect(ctx, 8, 138, S - 16, 104, 14); ctx.fill();
    ctx.fillStyle = '#E3662B'; rrect(ctx, 16, 146, S - 32, 88, 10); ctx.fill();
    drawText(ctx, 'LAFF-O-MATIC', S / 2, 190, { font: 'Shrikhand', size: 30, fill: '#FFF3B0', maxW: 210 });
  });
  // assignment board (green chalkboard)
  at(2, 3, () => {
    ctx.fillStyle = '#2F4A3A'; ctx.fillRect(0, 0, S, S);
    ctx.strokeStyle = 'rgba(255,255,255,0.08)'; ctx.lineWidth = 16;
    for (let i = 0; i < 6; i++) { ctx.beginPath(); ctx.moveTo(rand() * S, rand() * S); ctx.lineTo(rand() * S, rand() * S); ctx.stroke(); }
    drawText(ctx, 'ASSIGNMENTS', S / 2, 28, { font: 'Titan One', size: 26, fill: '#F4F1E8' });
    const items = ['TELETHON - LIVE', 'CITY HALL - 3PM', 'WEATHER - STU', 'MAYOR PRESSER', 'SPORTS FINAL', 'LATE NIGHT - ??'];
    items.forEach((s, i) => drawText(ctx, s, 18, 70 + i * 30, { font: 'Titan One', size: 17, fill: i === 5 ? '#FFB6C8' : '#E8F0E0', align: 'left', rot: (rand() - 0.5) * 0.04, maxW: 220 }));
  });
  at(3, 3, () => { ctx.fillStyle = '#F6E7C8'; ctx.fillRect(0, 0, S, S); });
}

function paintDecals(ctx, W, H, rand) {
  const S = 256;
  ctx.clearRect(0, 0, W, H);
  // coffee ring + splash
  ctx.save(); ctx.translate(128, 128);
  ctx.fillStyle = 'rgba(92,52,24,0.55)';
  ctx.beginPath(); ctx.ellipse(0, 0, 70, 58, 0.3, 0, TAU); ctx.fill();
  for (let i = 0; i < 9; i++) { const a = rand() * TAU, r = 70 + rand() * 30; ctx.beginPath(); ctx.arc(Math.cos(a) * r, Math.sin(a) * r, 5 + rand() * 9, 0, TAU); ctx.fill(); }
  ctx.strokeStyle = 'rgba(70,36,14,0.7)'; ctx.lineWidth = 6; ctx.beginPath(); ctx.ellipse(-10, 8, 38, 38, 0, 0, TAU); ctx.stroke();
  ctx.restore();
  // scuffs
  ctx.save(); ctx.translate(S, 0);
  ctx.strokeStyle = 'rgba(40,30,40,0.35)'; ctx.lineCap = 'round';
  for (let i = 0; i < 26; i++) { ctx.lineWidth = 2 + rand() * 5; ctx.beginPath(); const x = 30 + rand() * 196, y = 30 + rand() * 196; ctx.moveTo(x, y); ctx.lineTo(x + (rand() - 0.5) * 70, y + (rand() - 0.5) * 20); ctx.stroke(); }
  ctx.restore();
  // gaffer tape X (yellow)
  ctx.save(); ctx.translate(128, S + 128);
  for (const a of [0.78, -0.78]) {
    ctx.save(); ctx.rotate(a);
    ctx.fillStyle = 'rgba(244,210,58,0.95)'; ctx.fillRect(-100, -18, 200, 36);
    ctx.fillStyle = 'rgba(0,0,0,0.12)'; for (let i = -100; i < 100; i += 9) ctx.fillRect(i, -18, 2, 36);
    ctx.restore();
  }
  ctx.restore();
  // dust smudge
  ctx.save(); ctx.translate(S + 128, S + 128);
  const g = ctx.createRadialGradient(0, 0, 10, 0, 0, 120);
  g.addColorStop(0, 'rgba(60,40,50,0.35)'); g.addColorStop(1, 'rgba(60,40,50,0)');
  ctx.fillStyle = g; ctx.fillRect(-128, -128, 256, 256);
  ctx.restore();
}

export function atlas(game) {
  const map = K.tex.canvas('nm_atlas_v1', 1024, 1024, paintAtlas, { repeat: false, fonts: true });
  const dmap = K.tex.canvas('nm_decals_v1', 512, 512, paintDecals, { repeat: false });
  const mat = K.mat(game, 'paint', '#ffffff', { map, rim: 0.12 });
  const decal = game.mats.toon('#ffffff', { map: dmap, transparent: true, depthWrite: false, rough: 0.8, rim: 0, name: 'nm_decal' });
  decal.polygonOffset = true;
  decal.polygonOffsetFactor = -2;
  decal.polygonOffsetUnits = -2;
  const cell = (name, sub = [0, 0, 1, 1]) => {
    const [c, r] = CELLS[name];
    const u0 = (c + sub[0]) / 4, u1 = (c + sub[2]) / 4;
    const v1 = 1 - (r + sub[1]) / 4, v0 = 1 - (r + sub[3]) / 4;
    return [u0, v0, u1, v1];
  };
  const dcell = (name) => {
    const [c, r] = DECALS[name];
    return [c / 2, 1 - (r + 1) / 2, (c + 1) / 2, 1 - r / 2];
  };
  return { mat, decal, cell, dcell, map };
}

// Plane w x h facing +z with its UVs remapped into rect [u0, v0, u1, v1].
export function quad(w, h, rect = [0, 0, 1, 1], seg = 1) {
  const g = new THREE.PlaneGeometry(w, h, seg, seg);
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, rect[0] + uv.getX(i) * (rect[2] - rect[0]), rect[1] + uv.getY(i) * (rect[3] - rect[1]));
  return g;
}

// Flat ribbon (paper tape, cables laid flat) along a Catmull-Rom curve through `points`; normal ~ up.
export function ribbon(points, width, { seg = 32, up = [0, 1, 0], rect = [0, 0, 1, 1] } = {}) {
  const curve = new THREE.CatmullRomCurve3(points.map(v3));
  const pos = [], uv = [], idx = [];
  const U = v3(up);
  const t = new THREE.Vector3(), s = new THREE.Vector3(), p = new THREE.Vector3();
  for (let i = 0; i <= seg; i++) {
    const k = i / seg;
    curve.getPointAt(k, p);
    curve.getTangentAt(k, t);
    s.crossVectors(t, U).normalize().multiplyScalar(width / 2);
    pos.push(p.x - s.x, p.y - s.y, p.z - s.z, p.x + s.x, p.y + s.y, p.z + s.z);
    const v = rect[1] + k * (rect[3] - rect[1]);
    uv.push(rect[0], v, rect[2], v);
    if (i < seg) { const a = i * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

// Registers a named object for other systems (GDD §18.13 ids).
export function obj(game, id, o) {
  const lv = game.level;
  if (!lv) return o;
  if (!lv.objects) lv.objects = {};
  lv.objects[id] = { id, parts: {}, ...o };
  return lv.objects[id];
}

// placeProp wrapper: area tag, optional post-rotation (tilt) and a guard so a broken prop never kills the room.
export function place(game, root, id, pos, rotY = 0, opts = {}, extra = {}) {
  try {
    return placeProp(game, root, id, { pos, rotY, opts, area: extra.area ?? null, ...extra });
  } catch (err) {
    console.warn(`[rooms] prop ${id} failed`, err);
    return null;
  }
}

// Additive floor glow (fx light pool) with a safe fallback.
export function pool(game, pos, radius, color, intensity) {
  const h = game.fx?.lightPool?.(pos, radius, color, intensity);
  return h || { set() {}, remove() {} };
}

// Clock hands to a time (the furniture clocks use rotation.z = fraction of a turn).
export function setClockHands(parts, h, m, s = 0) {
  if (!parts) return;
  if (parts.hour) parts.hour.rotation.z = (((h % 12) + m / 60) / 12) * TAU;
  if (parts.minute) parts.minute.rotation.z = ((m + s / 60) / 60) * TAU;
  if (parts.second) parts.second.rotation.z = (s / 60) * TAU;
}

// Room runtime: per-frame tickers (world dt, via render.addPrePass since rooms have no update hook) and power
// switches that fire as the Sign-On colour wave reaches their position.
export function runtime(game, areaId) {
  const rt = { area: areaId, tickers: [], switches: [], powered: false, powerT: -1, t: 0, _warned: false };
  rt.tick = (fn) => { rt.tickers.push(fn); return fn; };
  // fn(on) is called with the 3-flash flicker (flicker:false → one switch) when the wave reaches pos.
  rt.power = (pos, fn, { flicker = true, sound = null } = {}) => {
    const p = pos.isVector3 ? pos.clone() : v3(pos);
    const s = { pos: p, fn, flicker, sound, delay: LEVER.distanceTo(p) / WAVE_SPEED, state: false, done: true, t0: -1 };
    try { fn(false); } catch (err) { console.warn('[rooms] power switch', err); }
    rt.switches.push(s);
    return s;
  };
  const setAll = (on) => {
    for (const s of rt.switches) {
      if (s.state !== on) { try { s.fn(on); } catch (err) { /* keep going */ } }
      s.state = on; s.done = true; s.t0 = -1;
    }
  };
  const start = () => {
    rt.powered = true;
    rt.powerT = 0;
    for (const s of rt.switches) { s.done = false; s.t0 = -1; }
  };
  game.events?.on?.('power:on', start);
  let noEvent = 0;
  const frame = () => {
    const tm = game.time || {};
    const dt = tm.dt || 0, real = tm.realDt || 0;
    const on = !!game.machines?.powerOn;
    if (rt.powered && !on && game.machines) { rt.powered = false; rt.powerT = -1; setAll(false); noEvent = 0; }
    if (!rt.powered && on) { noEvent += real; if (noEvent > 4) start(); } else noEvent = 0;
    if (rt.powered && rt.powerT >= 0) {
      rt.powerT += real;
      let pending = false;
      const wr = game.signon && typeof game.signon.waveReached === 'function' ? game.signon : null;
      for (const s of rt.switches) {
        if (s.done) continue;
        if (s.t0 < 0) {
          let reached = rt.powerT >= s.delay;
          if (wr) { try { reached = !!wr.waveReached(s.pos) || rt.powerT >= s.delay + 3; } catch (err) { /* fallback */ } }
          if (!reached) { pending = true; continue; }
          s.t0 = rt.powerT;
          if (s.sound) game.audio?.play?.(s.sound, { pos: s.pos });
        }
        const k = rt.powerT - s.t0;
        let want = true;
        if (s.flicker) for (const [t0, v] of FLICKER) if (k >= t0) want = v;
        if (want !== s.state) { try { s.fn(want); } catch (err) { /* ignore */ } s.state = want; }
        if (!s.flicker || k >= FLICKER[FLICKER.length - 1][0]) s.done = true; else pending = true;
      }
      if (!pending) rt.powerT = -1;
    }
    rt.t += dt;
    for (const f of rt.tickers) {
      try { f(dt, rt.t, real); } catch (err) {
        if (!rt._warned) { rt._warned = true; console.warn(`[rooms:${areaId}] ticker`, err); }
      }
    }
  };
  if (game.render?.addPrePass) game.render.addPrePass(frame);
  return rt;
}

// Key-only toy prompt ([E]) with a cooldown; use() gets called on E.
export function toy(game, id, pos, use, { radius = 1.5, cooldown = 0.4 } = {}) {
  let last = -1e9;
  return game.interact?.register?.({
    id, pos: pos.isVector3 ? pos.clone() : v3(pos), radius,
    prompt: () => ({}),
    use: () => {
      const now = game.time?.realNow ?? performance.now() / 1000;
      if (now - last < cooldown) return;
      last = now;
      use();
    },
  });
}

// Materials we mutate at runtime (never the shared caches): a lamp glow that can dim.
export function dimmableGlow(color, intensity = 2.2) {
  const m = new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(intensity), toneMapped: true });
  m.userData.base = new THREE.Color(color);
  m.userData.level = intensity;
  m.setLevel = (lv) => { m.userData.level = lv; m.color.copy(m.userData.base).multiplyScalar(lv); };
  return m;
}

// Replaces every use of material `from` inside a placed prop by `to` (call before the level merge).
export function swapMat(group, from, to) {
  group.traverse((o) => { if (o.isMesh && o.material === from) o.material = to; });
}

// Additive plane material (washes, slats), level-controlled.
export function additive(map, color, level = 1) {
  const m = new THREE.MeshBasicMaterial({ map, color: new THREE.Color(color).multiplyScalar(level), transparent: true, depthWrite: false,
    blending: THREE.AdditiveBlending, fog: false, toneMapped: true, side: THREE.DoubleSide });
  m.userData.base = new THREE.Color(color);
  m.setLevel = (lv) => m.color.copy(m.userData.base).multiplyScalar(lv);
  m.polygonOffset = true; m.polygonOffsetFactor = -3; m.polygonOffsetUnits = -3;
  return m;
}

// Slat stripes (moonlight through boards / blinds) and soft vertical wash gradients.
export function slatTex(n = 6) {
  return K.tex.canvas(`nm_slats_${n}`, 64, 256, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    for (let i = 0; i < n; i++) {
      const y0 = (i + 0.18) * (h / n), hh = (h / n) * 0.55;
      const g = ctx.createLinearGradient(0, y0, 0, y0 + hh);
      g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.25, 'rgba(255,255,255,1)');
      g.addColorStop(0.75, 'rgba(255,255,255,1)'); g.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = g; ctx.fillRect(0, y0, w, hh);
    }
    // soft side falloff
    const s = ctx.createLinearGradient(0, 0, w, 0);
    s.addColorStop(0, 'rgba(0,0,0,1)'); s.addColorStop(0.2, 'rgba(0,0,0,0)'); s.addColorStop(0.8, 'rgba(0,0,0,0)'); s.addColorStop(1, 'rgba(0,0,0,1)');
    ctx.globalCompositeOperation = 'destination-out'; ctx.fillStyle = s; ctx.fillRect(0, 0, w, h);
    const e = ctx.createLinearGradient(0, 0, 0, h);
    e.addColorStop(0, 'rgba(0,0,0,0)'); e.addColorStop(0.7, 'rgba(0,0,0,0.2)'); e.addColorStop(1, 'rgba(0,0,0,1)');
    ctx.fillStyle = e; ctx.fillRect(0, 0, w, h);
    ctx.globalCompositeOperation = 'source-over';
  }, { repeat: false });
}
export function washTex() {
  return K.tex.canvas('nm_wash', 128, 128, (ctx, w, h) => {
    const g = ctx.createRadialGradient(w / 2, h * 0.75, 4, w / 2, h * 0.6, w * 0.6);
    g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.5, 'rgba(255,255,255,0.45)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  }, { repeat: false });
}

// ================================================================================== room-only props (nm_*)
const CAT = 'rooms_nm';
const sph = (r, ws = 14, hs = 10) => new THREE.SphereGeometry(r, ws, hs);
const keyGeo = () => K.lathe([[0, 0], [0.0128, 0], [0.012, 0.015], [0, 0.017]], { seg: 7 });

// ------------------------------------------------------------------------------------------------ teletype
// Wire-service teletype on its pedestal (toy_teletype). Front (keyboard) -z. parts: head (print head, slides x),
// paper (printout, grows scale.y from the slot), tape (punched tape ribbon), bulb (work-lamp glow mesh),
// keys (a few keys that bob). anchors.lamp = bulb position (local).
registerProp('nm_teletype', (game) => {
  const g = K.prop('nm_teletype');
  const mt = stdMats(game), A = atlas(game);
  const cream = '#E9DFC4', putty = '#CFC3A2', dark = '#3A3440';
  // pedestal + kick
  g.add(K.m(tc(K.box(0.6, 0.5, 0.48, 'md'), putty), mt.paint, { pos: [0, 0.33, 0.02] }));
  g.add(K.m(tc(K.box(0.54, 0.08, 0.42, 'sm'), '#5A4A46'), mt.paint, { pos: [0, 0.04, 0.02] }));
  g.add(K.m(tc(K.box(0.44, 0.22, 0.02, 'sm'), '#8A7E66'), mt.paint, { pos: [0, 0.34, -0.225] }));
  // paper feed box in the pedestal opening (fan-fold stack)
  for (let i = 0; i < 6; i++) g.add(K.m(tc(K.box(0.36, 0.02, 0.3, 'xs'), i % 2 ? '#F4EBC8' : '#E9DFB8'), mt.paint, { pos: [0, 0.25 + i * 0.021, -0.07], rot: [0, (i % 3 - 1) * 0.02, 0] }));
  // chassis + stripe
  g.add(K.m(tc(K.box(0.68, 0.16, 0.56, 'lg'), cream), mt.plastic, { pos: [0, 0.66, 0] }));
  g.add(K.m(tc(K.box(0.685, 0.03, 0.565, 'sm'), PAL.burntOrange), mt.plastic, { pos: [0, 0.6, 0] }));
  // sloped keyboard deck with keys
  const deck = new THREE.Group();
  deck.position.set(0, 0.75, -0.19);
  deck.rotation.x = 0.22;
  g.add(deck);
  deck.add(K.m(tc(K.box(0.56, 0.04, 0.2, 'sm'), dark), mt.plastic));
  const kg = keyGeo();
  const bobKeys = new THREE.Group();
  bobKeys.userData.noMerge = true;
  for (let r = 0; r < 3; r++) {
    for (let i = 0; i < 9 - r; i++) {
      const x = (i - (8 - r) / 2) * 0.05, z = -0.06 + r * 0.05;
      const col = (i + r) % 6 === 2 ? PAL.channelRed : '#F4F1E8';
      const key = K.m(tc(kg, col), mt.plastic, { pos: [x, 0.02, z] });
      if (r === 1 && (i === 2 || i === 5)) bobKeys.add(key); else deck.add(key);
    }
  }
  deck.add(bobKeys);
  deck.add(K.m(tc(K.box(0.26, 0.02, 0.035, 'xs'), '#F4F1E8'), mt.plastic, { pos: [0, 0.025, -0.085] }));
  // hood with a smoked window over the platen
  g.add(K.m(tc(K.box(0.62, 0.2, 0.3, 0.08), cream), mt.plastic, { pos: [0, 0.83, 0.1] }));
  g.add(K.m(K.box(0.5, 0.13, 0.012, 'xs'), game.mats.glass('#5A4A3A', { opacity: 0.35 }), { pos: [0, 0.87, -0.052], rot: [-0.25, 0, 0] }));
  g.add(K.m(tc(K.cyl(0.035, 0.035, 0.52, { seg: 14 }), '#2A2230'), mt.rubber, { pos: [-0.26, 0.855, 0.02], rot: [0, 0, -HP] }));
  for (const s of [-1, 1]) g.add(K.m(K.cyl(0.03, 0.034, 0.03, { seg: 12 }), mt.chrome, { pos: [s * 0.33, 0.855, 0.02], rot: [0, 0, -s * HP] }));
  // print head (part)
  const head = new THREE.Group();
  head.position.set(0, 0.86, -0.02);
  head.userData.noMerge = true;
  head.add(K.m(K.box(0.07, 0.05, 0.05, 'sm'), mt.chrome));
  head.add(K.m(tc(K.box(0.03, 0.02, 0.03, 'xs'), PAL.channelRed), mt.plastic, { pos: [0, 0.035, 0] }));
  g.add(head);
  // paper roll behind the hood
  g.add(K.m(tc(K.cyl(0.07, 0.07, 0.5, { seg: 16 }), '#F4EEDC'), mt.paint, { pos: [-0.25, 0.9, 0.2], rot: [0, 0, -HP] }));
  // printout coming out of the slot and curling back (part 'paper', pivot at the slot)
  const paper = new THREE.Group();
  paper.position.set(0, 0.935, 0.06);
  paper.userData.noMerge = true;
  const pg = quad(0.46, 0.46, A.cell('wire'), 8);
  const pp = pg.attributes.position;
  for (let i = 0; i < pp.count; i++) {
    const y = pp.getY(i) + 0.23;              // 0..0.46 up the sheet
    const k = y / 0.46;
    pp.setXYZ(i, -pp.getX(i), Math.sin(k * 1.9) * 0.3, 0.02 + (1 - Math.cos(k * 1.9)) * 0.2); // mirrored: text faces -z
  }
  pg.computeVertexNormals();
  paper.add(K.m(pg, K.mat(game, 'paint', '#ffffff', { map: A.map, side: THREE.DoubleSide, rim: 0.1 }), { cast: false }));
  g.add(paper);
  // punched paper tape (part) spilling from the side punch to the floor
  const tape = new THREE.Group();
  tape.position.set(-0.36, 0.7, -0.08);
  tape.userData.noMerge = true;
  const tpts = [[0, 0, 0], [-0.08, -0.05, -0.04], [-0.12, -0.25, -0.1], [-0.05, -0.45, -0.18], [-0.15, -0.66, -0.24], [-0.3, -0.695, -0.2], [-0.32, -0.695, -0.05]];
  tape.add(K.m(ribbon(tpts, 0.028, { seg: 28, up: [1, 0, 0] }), K.mat(game, 'paint', '#F4D23A', { side: THREE.DoubleSide }), { cast: false }));
  g.add(tape);
  g.add(K.m(tc(K.box(0.08, 0.12, 0.14, 'sm'), '#8A7E66'), mt.plastic, { pos: [-0.36, 0.68, -0.06] }));
  // nameplate on the chassis front
  g.add(K.m(quad(0.2, 0.07, A.cell('plate', [0, 0, 1, 0.5])), A.mat, { pos: [0.18, 0.66, -0.282], rot: [0, Math.PI, 0] }));
  // gooseneck work lamp clamped on the back right
  g.add(K.m(tc(K.cyl(0.05, 0.055, 0.03, { seg: 14 }), '#2A2230'), mt.plastic, { pos: [0.26, 0.74, 0.2] }));
  const neck = [[0.26, 0.76, 0.2], [0.27, 0.95, 0.2], [0.24, 1.14, 0.12], [0.16, 1.22, 0.0], [0.1, 1.2, -0.08]];
  g.add(K.m(K.tube(neck, 0.012, { seg: 20, radial: 6 }), mt.chrome));
  const shade = new THREE.Group();
  shade.position.set(0.09, 1.19, -0.1);
  shade.rotation.x = 0.9;
  shade.add(K.m(tc(K.lathe([[0.03, 0.06], [0.05, 0.04], [0.085, -0.02], [0.09, -0.05], [0.08, -0.05], [0.07, -0.02]], { seg: 16, round: 0.004 }), PAL.burntOrange), mt.lacquer));
  const bulb = K.m(sph(0.035, 12, 8), dimmableGlow('#FFD9A0', 2.4), { pos: [0, -0.02, 0], cast: false });
  bulb.userData.noMerge = true;
  bulb.userData.noOcclude = true;
  shade.add(bulb);
  g.add(shade);
  const u = g.userData;
  u.parts = { head, paper, tape, bulb, keys: bobKeys };
  u.anchors = { lamp: [0.09, 1.13, -0.16] };
  u.colliders = [{ min: [-0.36, 0, -0.32], max: [0.36, 0.96, 0.3] }];
  u.interact = { point: [0, 0.9, -0.5], radius: 1.4 };
  return K.finish(game, g, { ao: { res: 40 } });
}, { category: CAT, tags: ['newsroom', 'toy'], size: [0.72, 1.25, 0.6], desc: 'wire-service teletype on a pedestal with printout, punched tape and a gooseneck work lamp' });

// ------------------------------------------------------------------------------------- toy typewriter
// parts: carriage (slides along x, returns with a ding), keys (bobbing group), sheet (paper in the platen).
registerProp('nm_typewriter', (game, opts = {}) => {
  const g = K.prop('nm_typewriter');
  const mt = stdMats(game), A = atlas(game);
  const color = opts.color ?? PAL.harvestGold;
  const dark = '#2E2630';
  g.add(K.m(tc(K.box(0.46, 0.08, 0.38, 0.035), color), mt.plastic, { pos: [0, 0.05, 0] }));
  g.add(K.m(K.weldNormals(K.taper(tc(K.box(0.44, 0.09, 0.2, 0.04), color), { axis: 'y', k: 0.82 })), mt.plastic, { pos: [0, 0.125, 0.07] }));
  g.add(K.m(tc(K.box(0.44, 0.012, 0.36, 0.005), dark), mt.plastic, { pos: [0, 0.006, 0] }));
  g.add(K.m(tc(K.box(0.4, 0.03, 0.15, 0.012), dark), mt.plastic, { pos: [0, 0.085, -0.105], rot: [0.2, 0, 0] }));
  const kg = keyGeo();
  const bob = new THREE.Group();
  bob.userData.noMerge = true;
  [[10, 0], [9, 0.01], [8, 0.02]].forEach(([n, off], r) => {
    for (let i = 0; i < n; i++) {
      const x = (i - (n - 1) / 2) * 0.034 + off * 0.2, z = -0.155 + r * 0.035, y = 0.09 + r * 0.008;
      const k = K.m(tc(kg, (i + r) % 7 === 3 ? PAL.channelRed : '#F4F1E8'), mt.plastic, { pos: [x, y, z], rot: [0.2, 0, 0] });
      if (r === 1 && i % 3 === 1) bob.add(k); else g.add(k);
    }
  });
  g.add(bob);
  g.add(K.m(tc(K.box(0.2, 0.014, 0.024, 0.006), '#F4F1E8'), mt.plastic, { pos: [0, 0.088, -0.19], rot: [0.2, 0, 0] }));
  // carriage (part): platen, knobs, sheet, return lever, bell
  const car = new THREE.Group();
  car.position.set(0, 0.185, 0.1);
  car.userData.noMerge = true;
  car.add(K.m(tc(K.cyl(0.028, 0.028, 0.42, { seg: 14 }), dark), mt.plastic, { pos: [-0.21, 0, 0], rot: [0, 0, -HP] }));
  for (const s of [-1, 1]) car.add(K.m(tc(K.lathe([[0, 0], [0.024, 0], [0.028, 0.012], [0.024, 0.028], [0, 0.03]], { seg: 12, round: 0.004, steps: 1 }), dark), mt.plastic, { pos: [s * 0.21, 0, 0], rot: [0, 0, -s * HP] }));
  const sheet = K.m(quad(0.24, 0.27, A.cell('page')), K.mat(game, 'paint', '#ffffff', { map: A.map, side: THREE.DoubleSide, rim: 0.1 }), { pos: [0, 0.13, 0.015], rot: [-0.18, 0, 0.02], cast: false });
  car.add(sheet);
  car.add(K.m(K.tube([[-0.23, 0.015, -0.04], [-0.27, 0.045, -0.07], [-0.29, 0.065, -0.12]], 0.006, { seg: 8, radial: 5 }), mt.chrome));
  car.add(K.m(tc(K.box(0.44, 0.02, 0.05, 0.009), new THREE.Color(color).multiplyScalar(0.7).getStyle()), mt.plastic, { pos: [0, -0.013, -0.12] }));
  g.add(car);
  g.add(K.m(K.lathe([[0, 0], [0.02, 0], [0.018, 0.012], [0.01, 0.02], [0, 0.021]], { seg: 12, round: 0.004 }), mt.chrome, { pos: [0.19, 0.1, 0.16] }));
  g.add(K.m(quad(0.12, 0.028, A.cell('plate', [0, 0, 1, 0.5])), A.mat, { pos: [0, 0.15, -0.034], rot: [0.55, Math.PI, 0] }));
  const u = g.userData;
  u.parts = { carriage: car, keys: bob, sheet };
  u.colliders = [];
  return K.finish(game, g, { ao: { height: 0.02 } });
}, { category: CAT, tags: ['tabletop', 'newsroom', 'toy'], size: [0.6, 0.44, 0.4], desc: 'toy typewriter with a sliding carriage (parts.carriage)' });

// ---------------------------------------------------------------------------------- bare reporter desk
// Same sage tanker desk as the library's desk_reporter (same materials/tints), minus the top dressing, so the
// toy typewriter can sit on it. Front (drawers, knee hole) -z.
registerProp('nm_desk_bare', (game, opts = {}) => {
  const g = K.prop('nm_desk_bare');
  const mt = stdMats(game);
  const steel = opts.color ?? '#8FA38A';
  const W = 1.5, D = 0.76, H = 0.76;
  const lam = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood('#A8743F', { dark: 0.3 }) });
  g.add(K.m(K.box(W, 0.034, D, 0.012, { uv: 1.2, swap: true }), lam, { pos: [0, H - 0.017, 0] }));
  g.add(K.m(K.box(W + 0.012, 0.022, D + 0.012, 0.008), mt.chrome, { pos: [0, H - 0.04, 0] }));
  const pw = 0.44, px = W / 2 - pw / 2 - 0.01;
  g.add(K.m(tc(K.box(pw, H - 0.1, D - 0.04, 0.02), steel), mt.paint, { pos: [px, (H - 0.1) / 2 + 0.05, 0] }));
  g.add(K.m(tc(K.box(0.05, H - 0.1, D - 0.04, 0.02), steel), mt.paint, { pos: [-W / 2 + 0.035, (H - 0.1) / 2 + 0.05, 0] }));
  g.add(K.m(tc(K.box(W - pw - 0.08, 0.42, 0.025, 0.01), steel), mt.paint, { pos: [-pw / 2 + 0.01, H - 0.3, D / 2 - 0.05] }));
  const dark = new THREE.Color(steel).multiplyScalar(0.55).getStyle();
  g.add(K.m(tc(K.box(pw - 0.04, 0.05, D - 0.1, 0.01), dark), mt.paint, { pos: [px, 0.025, 0] }));
  g.add(K.m(tc(K.box(0.04, 0.05, D - 0.1, 0.01), dark), mt.paint, { pos: [-W / 2 + 0.035, 0.025, 0] }));
  let y = H - 0.07;
  for (const h of [0.16, 0.16, 0.28]) {
    y -= h / 2 + 0.006;
    g.add(K.m(tc(K.box(pw - 0.03, h - 0.012, 0.03, 0.012), steel), mt.paint, { pos: [px, y, -D / 2 + 0.01] }));
    g.add(K.m(K.tube([[-0.07, 0, 0], [-0.065, 0, -0.02], [0.065, 0, -0.02], [0.07, 0, 0]], 0.007, { seg: 8, radial: 5 }), mt.chrome, { pos: [px, y + h * 0.18, -D / 2 - 0.004] }));
    y -= h / 2 + 0.006;
  }
  g.add(K.m(tc(K.box(W - pw - 0.14, 0.07, 0.03, 0.012), steel), mt.paint, { pos: [-pw / 2 - 0.02, H - 0.09, -D / 2 + 0.01] }));
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, H + 0.05, D / 2] }];
  return K.finish(game, g);
}, { category: CAT, tags: ['desk', 'newsroom'], size: [1.5, 0.78, 0.76], desc: 'bare sage tanker desk (desk_reporter without dressing)' });

// ------------------------------------------------------------------------------------------ floor globe
// Teak tripod floor globe (toy_globe). parts: globe (spins about its local y), tilt (23.5° axis group).
function globeTex() {
  return K.tex.canvas('nm_globe_map', 512, 256, (ctx, w, h, rand) => {
    ctx.fillStyle = '#3F9AB8'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 40; i++) { ctx.fillStyle = `rgba(255,255,255,${0.04 + rand() * 0.05})`; ctx.fillRect(0, rand() * h, w, 2); }
    const blob = (cx, cy, rx, ry, col, n = 9) => {
      ctx.fillStyle = col;
      for (let i = 0; i < n; i++) {
        ctx.beginPath();
        ctx.ellipse(cx + (rand() - 0.5) * rx, cy + (rand() - 0.5) * ry, rx * (0.3 + rand() * 0.4), ry * (0.3 + rand() * 0.4), rand() * 3, 0, TAU);
        ctx.fill();
      }
    };
    const land = [[110, 80, 90, 60], [150, 170, 50, 70], [260, 80, 60, 50], [280, 150, 50, 70], [380, 90, 110, 60], [420, 190, 50, 30], [70, 30, 60, 20]];
    for (const [x, y, rx, ry] of land) blob(x, y, rx, ry, '#E8D9A0');
    for (const [x, y, rx, ry] of land) blob(x, y, rx * 0.7, ry * 0.6, '#9CC46A', 5);
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 0, w, 12); ctx.fillRect(0, h - 12, w, 12);
    ctx.strokeStyle = 'rgba(30,40,70,0.25)'; ctx.lineWidth = 1.5;
    for (let i = 1; i < 6; i++) { ctx.beginPath(); ctx.moveTo(0, (i * h) / 6); ctx.lineTo(w, (i * h) / 6); ctx.stroke(); }
    for (let i = 0; i < 12; i++) { ctx.beginPath(); ctx.moveTo((i * w) / 12, 0); ctx.lineTo((i * w) / 12, h); ctx.stroke(); }
    ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(130, 92, 7, 0, TAU); ctx.fill();
  });
}
registerProp('nm_globe', (game) => {
  const g = K.prop('nm_globe');
  const mt = stdMats(game);
  const hubY = 0.42, R = 0.22, cy = 0.74;
  // tripod legs
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.3;
    const top = new THREE.Vector3(Math.cos(a) * 0.05, hubY, Math.sin(a) * 0.05);
    const foot = new THREE.Vector3(Math.cos(a) * 0.27, 0.0, Math.sin(a) * 0.27);
    const len = top.distanceTo(foot);
    const leg = K.m(K.uvScale(K.cyl(0.02, 0.014, len, { seg: 10 }).clone(), 1, 2), mt.teak);
    leg.position.copy(foot);
    leg.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), top.clone().sub(foot).normalize());
    g.add(leg);
    g.add(K.m(K.cyl(0.018, 0.02, 0.025, { seg: 10 }), mt.brass, { pos: [foot.x, 0, foot.z] }));
  }
  g.add(K.m(K.tube(Array.from({ length: 13 }, (_, i) => { const a = (i / 12) * TAU; return [Math.cos(a) * 0.16, 0.16, Math.sin(a) * 0.16]; }), 0.008, { seg: 24, radial: 5, closed: true }), mt.brass));
  g.add(K.m(K.lathe([[0, 0], [0.06, 0], [0.065, 0.03], [0.03, 0.06], [0.025, 0.2], [0.04, 0.22], [0, 0.23]], { seg: 14, round: 0.006 }), mt.teak, { pos: [0, hubY - 0.05, 0] }));
  // meridian + globe (parts)
  const tilt = new THREE.Group();
  tilt.position.set(0, cy, 0);
  tilt.rotation.z = 0.41;
  tilt.userData.noMerge = true;
  tilt.add(K.m(new THREE.TorusGeometry(R + 0.03, 0.012, 6, 40, Math.PI * 1.3), mt.brass, { rot: [0, 0, -Math.PI * 0.65 + HP] }));
  const globe = K.m(new THREE.SphereGeometry(R, 32, 20), K.mat(game, 'lacquer', '#ffffff', { map: globeTex() }), { name: 'globe' });
  globe.userData.noMerge = true;
  tilt.add(globe);
  for (const s of [-1, 1]) tilt.add(K.m(K.cyl(0.012, 0.012, 0.04, { seg: 8 }), mt.brass, { pos: [0, s * (R + 0.02) - (s < 0 ? 0.04 : 0), 0] }));
  g.add(tilt);
  // stem from the hub to the meridian
  g.add(K.m(K.cyl(0.012, 0.012, cy - R - hubY + 0.1, { seg: 8 }), mt.brass, { pos: [0, hubY + 0.15, 0] }));
  const u = g.userData;
  u.parts = { globe, tilt };
  u.colliders = [{ min: [-0.28, 0, -0.28], max: [0.28, 1.0, 0.28] }];
  return K.finish(game, g, { ao: { res: 36 } });
}, { category: CAT, tags: ['newsroom', 'toy'], size: [0.56, 1.0, 0.56], desc: 'teak tripod floor globe (parts.globe spins)' });

// ------------------------------------------------------------------------------------------- coffee cart
registerProp('nm_coffee_cart', (game) => {
  const g = K.prop('nm_coffee_cart');
  const mt = stdMats(game), A = atlas(game);
  const W = 0.82, D = 0.46;
  for (const [y, c] of [[0.22, PAL.avocado], [0.78, PAL.mustard]]) {
    g.add(K.m(tc(K.box(W, 0.035, D, 0.014), c), mt.lacquer, { pos: [0, y, 0] }));
    g.add(K.m(K.tube(K.roundRectPath(W - 0.01, D - 0.01, 0.03, 0.025, 2), 0.008, { seg: 20, radial: 4, closed: true }), mt.chrome, { pos: [0, y, 0] }));
  }
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    g.add(K.m(K.cyl(0.013, 0.013, 0.78, { seg: 8 }), mt.chrome, { pos: [x * (W / 2 - 0.03), 0.07, z * (D / 2 - 0.03)] }));
    g.add(K.m(tc(sph(0.035, 10, 8), '#2A2230'), mt.rubber, { pos: [x * (W / 2 - 0.03), 0.035, z * (D / 2 - 0.03)] }));
  }
  g.add(K.m(K.tube([[W / 2 - 0.03, 0.8, -D / 2 + 0.05], [W / 2 + 0.06, 0.86, -D / 2 + 0.05], [W / 2 + 0.06, 0.86, D / 2 - 0.05], [W / 2 - 0.03, 0.8, D / 2 - 0.05]], 0.012, { seg: 12, radial: 6 }), mt.chrome));
  // percolator
  const top = 0.8;
  g.add(K.m(K.lathe([[0, 0], [0.09, 0], [0.1, 0.02], [0.085, 0.05], [0.075, 0.26], [0.08, 0.28], [0.05, 0.3], [0.03, 0.34], [0, 0.35]], { seg: 20, round: 0.008 }), mt.chrome, { pos: [-0.24, top, -0.02] }));
  g.add(K.m(K.lathe([[0, 0], [0.022, 0], [0.018, 0.03], [0, 0.04]], { seg: 10 }), game.mats.glass('#8A5A30', { opacity: 0.5 }), { pos: [-0.24, top + 0.34, -0.02] }));
  g.add(K.m(tc(K.tube([[-0.16, top + 0.24, -0.02], [-0.12, top + 0.22, -0.02], [-0.12, top + 0.08, -0.02], [-0.16, top + 0.06, -0.02]], 0.014, { seg: 10, radial: 6 }), '#2A2230'), mt.plastic));
  g.add(K.m(K.tube([[-0.33, top + 0.2, -0.02], [-0.37, top + 0.25, -0.02]], 0.01, { seg: 3, radial: 6 }), mt.chrome));
  // cup stack + mugs
  for (let i = 0; i < 6; i++) g.add(K.m(tc(K.lathe([[0, 0], [0.028, 0], [0.036, 0.06], [0.034, 0.06], [0.026, 0.004], [0, 0.004]], { seg: 12 }), '#F4F1E8'), mt.plastic, { pos: [0.02, top + i * 0.018, -0.08] }));
  for (const [x, z, c] of [[0.1, 0.1, PAL.channelRed], [0.02, 0.12, PAL.wztvBlue]]) {
    g.add(K.m(tc(K.lathe([[0, 0], [0.034, 0], [0.036, 0.085], [0.032, 0.085], [0.03, 0.01], [0, 0.01]], { seg: 14 }), c), mt.ceramic ?? mt.plastic, { pos: [x, top, z] }));
    g.add(K.m(tc(new THREE.TorusGeometry(0.022, 0.006, 6, 12, Math.PI * 1.2), c), mt.plastic, { pos: [x + 0.036, top + 0.045, z], rot: [0, 0, -Math.PI * 0.6] }));
  }
  // open donut box with donuts
  const bx = 0.2, bz = -0.04;
  g.add(K.m(tc(K.box(0.3, 0.05, 0.26, 'xs'), '#F4F1E8'), mt.paint, { pos: [bx, top + 0.025, bz] }));
  const lid = K.m(quad(0.3, 0.26, A.cell('donut')), A.mat, { pos: [bx, top + 0.16, bz + 0.2], rot: [-0.35, Math.PI, 0] });
  g.add(lid);
  const glaze = [PAL.neonPink, '#6B3A22', '#F6E7C8', PAL.neonPink];
  [[-0.07, -0.05], [0.07, -0.05], [-0.07, 0.07], [0.06, 0.06]].forEach(([x, z], i) => {
    g.add(K.m(tc(new THREE.TorusGeometry(0.042, 0.022, 8, 16), '#D9A060'), mt.plastic, { pos: [bx + x, top + 0.07, bz + z], rot: [HP, 0, 0] }));
    g.add(K.m(tc(new THREE.TorusGeometry(0.042, 0.02, 6, 16, TAU), glaze[i]), mt.plastic, { pos: [bx + x, top + 0.077, bz + z], rot: [HP, 0, 0], scale: [1.02, 1.02, 0.6] }));
  });
  // bottom shelf: coffee cans + sugar
  for (const [x, z] of [[-0.22, 0], [-0.08, 0.04]]) {
    g.add(K.m(tc(K.cyl(0.07, 0.07, 0.16, { seg: 14 }), PAL.channelRed), mt.lacquer, { pos: [x, 0.24, z] }));
    g.add(K.m(tc(K.cyl(0.072, 0.072, 0.02, { seg: 14 }), '#C8963C'), mt.metal, { pos: [x, 0.39, z] }));
  }
  g.add(K.m(K.lathe([[0, 0], [0.05, 0], [0.05, 0.12], [0.02, 0.15], [0, 0.16]], { seg: 12 }), game.mats.glass('#F4F1E8', { opacity: 0.5 }), { pos: [0.2, 0.24, 0.02] }));
  g.userData.colliders = [{ min: [-W / 2 - 0.02, 0, -D / 2 - 0.02], max: [W / 2 + 0.08, 1.15, D / 2 + 0.02] }];
  return K.finish(game, g, { ao: { res: 40 } });
}, { category: CAT, tags: ['newsroom', 'cart'], size: [0.9, 1.15, 0.5], desc: 'rolling coffee cart: chrome percolator, cups, an open box of donuts, coffee cans' });

// ------------------------------------------------------------------------------------ gooseneck desk lamp
// parts.bulb (dimmable glow mesh, swap level on power). Front -z.
registerProp('nm_desk_lamp', (game, opts = {}) => {
  const g = K.prop('nm_desk_lamp');
  const mt = stdMats(game);
  const c = opts.color ?? PAL.avocado;
  g.add(K.m(tc(K.lathe([[0, 0], [0.08, 0], [0.085, 0.015], [0.06, 0.03], [0, 0.035]], { seg: 16, round: 0.005 }), c), mt.lacquer));
  g.add(K.m(K.tube([[0, 0.03, 0.02], [0, 0.2, 0.04], [0, 0.34, -0.02], [0, 0.38, -0.12]], 0.01, { seg: 16, radial: 6 }), mt.chrome));
  const shade = new THREE.Group();
  shade.position.set(0, 0.38, -0.15);
  shade.rotation.x = 0.5;
  shade.add(K.m(tc(K.lathe([[0.025, 0.05], [0.045, 0.03], [0.075, -0.02], [0.08, -0.045], [0.07, -0.045], [0.062, -0.02]], { seg: 16, round: 0.004 }), c), mt.lacquer));
  const bulb = K.m(sph(0.028, 10, 8), dimmableGlow('#FFE0A8', 2.2), { pos: [0, -0.02, 0], cast: false });
  bulb.userData.noMerge = true;
  bulb.userData.noOcclude = true;
  shade.add(bulb);
  g.add(shade);
  g.userData.parts = { bulb };
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { height: 0.02 } });
}, { category: CAT, tags: ['tabletop', 'lamp'], size: [0.18, 0.45, 0.25], desc: 'gooseneck desk lamp (parts.bulb dimmable)' });

// ------------------------------------------------------------------------------------- skyline backdrop
function skylineTex() {
  return K.tex.canvas('nm_skyline_v1', 1024, 768, (ctx, w, h, rand) => {
    const sky = ctx.createLinearGradient(0, 0, 0, h);
    sky.addColorStop(0, '#16185A'); sky.addColorStop(0.45, '#3A2E86'); sky.addColorStop(0.72, '#9A4A8C'); sky.addColorStop(0.86, '#E3662B'); sky.addColorStop(1, '#F6A94A');
    ctx.fillStyle = sky; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 160; i++) { ctx.fillStyle = `rgba(255,244,214,${0.3 + rand() * 0.6})`; const s = rand() < 0.1 ? 3 : 1.6; ctx.fillRect(rand() * w, rand() * h * 0.5, s, s); }
    // moon (right, under the logo band)
    ctx.fillStyle = '#FFF4D6'; ctx.beginPath(); ctx.arc(w * 0.9, h * 0.47, 40, 0, TAU); ctx.fill();
    ctx.fillStyle = '#3A2E86'; ctx.globalAlpha = 0.92; ctx.beginPath(); ctx.arc(w * 0.9 + 20, h * 0.47 - 9, 37, 0, TAU); ctx.fill(); ctx.globalAlpha = 1;
    // skyline layers
    const layer = (base, col, win, minH, maxH, bw) => {
      let x = -10;
      while (x < w) {
        const bwid = bw * (0.6 + rand() * 0.9), bh = minH + rand() * (maxH - minH);
        const top = h - base - bh;
        ctx.fillStyle = col;
        ctx.fillRect(x, top, bwid, bh + base);
        if (rand() < 0.3) { ctx.fillRect(x + bwid * 0.35, top - 26, bwid * 0.3, 26); }
        if (rand() < 0.15) { ctx.fillRect(x + bwid * 0.48, top - 60, 3, 60); ctx.fillStyle = '#FF3B30'; ctx.fillRect(x + bwid * 0.48 - 2, top - 64, 7, 7); ctx.fillStyle = col; }
        if (win) {
          for (let yy = top + 10; yy < h - base - 8; yy += 16) for (let xx = x + 6; xx < x + bwid - 8; xx += 12) {
            if (rand() < 0.42) { ctx.fillStyle = rand() < 0.8 ? '#FFD36A' : '#9FE7FF'; ctx.fillRect(xx, yy, 6, 8); }
          }
        }
        x += bwid + 2;
      }
    };
    layer(0, '#2A2F6B', false, 180, 330, 70);
    layer(0, '#1E2150', true, 90, 250, 90);
    layer(0, '#141638', true, 30, 120, 110);
    // logo band across the top (the world clocks hang under it)
    ctx.fillStyle = 'rgba(16,12,44,0.72)'; ctx.fillRect(0, 18, w, 128);
    [PAL.harvestGold, PAL.burntOrange, PAL.channelRed].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(0, 150 + i * 13, w, 9); });
    const cx = w / 2;
    ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.arc(cx, 82, 58, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 12; ctx.stroke();
    drawText(ctx, '13', cx, 88, { font: 'Shrikhand', size: 70, fill: '#F4F1E8' });
    drawText(ctx, 'ACTION', cx - 78, 84, { font: 'Bungee', size: 56, fill: '#F6E7C8', align: 'right' });
    drawText(ctx, 'NEWS', cx + 78, 80, { font: 'Shrikhand', size: 64, fill: '#FFC23A', align: 'left' });
  }, { repeat: false, fonts: true });
}
registerProp('nm_skyline', (game, opts = {}) => {
  const g = K.prop('nm_skyline');
  const mt = stdMats(game);
  const W = opts.w ?? 4.2, H = opts.h ?? 3.2, y0 = 0.35;
  const face = K.m(quad(W, H), K.mat(game, 'paint', '#ffffff', { map: skylineTex(), rim: 0.08, emissive: '#1A1850', emissiveIntensity: 0.25 }), { pos: [0, y0 + H / 2, -0.07], rot: [0, Math.PI, 0], cast: false });
  g.add(face);
  g.add(K.m(tc(K.box(W + 0.1, H + 0.1, 0.1, 'sm'), '#2A2230'), mt.paint, { pos: [0, y0 + H / 2, -0.01] }));
  // chunky frame: teak bottom sill + chrome edges
  g.add(K.m(K.box(W + 0.24, 0.14, 0.2, 'md', { uv: 1.2 }), mt.teak, { pos: [0, y0 - 0.02, -0.08] }));
  g.add(K.m(tc(K.box(W + 0.24, 0.35, 0.12, 'sm'), '#3A2A40'), mt.paint, { pos: [0, 0.175, -0.06] }));
  for (const s of [-1, 1]) g.add(K.m(K.box(0.06, H + 0.1, 0.06, 'sm'), mt.chrome, { pos: [s * (W / 2 + 0.06), y0 + H / 2, -0.09] }));
  g.add(K.m(K.box(W + 0.18, 0.06, 0.06, 'sm'), mt.chrome, { pos: [0, y0 + H + 0.06, -0.09] }));
  const u = g.userData;
  u.parts = { face };
  u.colliders = [{ min: [-W / 2 - 0.12, 0, -0.18], max: [W / 2 + 0.12, y0 + H + 0.1, 0.05] }];
  return K.finish(game, g, { ao: { floor: false, height: 0.1, res: 40 } });
}, { category: CAT, tags: ['newsroom', 'wall', 'backdrop'], size: [4.44, 3.6, 0.2], desc: 'painted night-skyline news backdrop with the ACTION 13 NEWS logo (back at z = 0)' });

// ========================================================================================== room dressing
const DESK_TOP = 0.76;

export function build(game, area, root) {
  const aid = area.id;
  const rt = runtime(game, aid);
  const mt = stdMats(game);
  const A = atlas(game);
  const rnd = mulberry32(1313);
  const P = (id, pos, rotY = 0, opts = {}, extra = {}) => place(game, root, id, pos, rotY, opts, { area: aid, ...extra });
  const add = (mesh) => { root.add(mesh); return mesh; };
  const floorDecal = (name, x, z, s, rot = 0) => add(K.m(quad(s, s, A.dcell(name)), A.decal, { pos: [x, 0.004, z], rot: [-HP, 0, rot], cast: false, receive: true }));
  const sheet = (cellName, x, y, z, w, h, rot = 0, tilt = -HP) => add(K.m(quad(w, h, A.cell(cellName)), A.mat, { pos: [x, y, z], rot: [tilt, 0, rot], cast: false }));

  // -------------------------------------------------------------------------------- anchor riser (hero)
  const desk = P('desk_anchor', [20.2, 0.4, 0.0], HP);
  const chair = P('chair_office', [21.05, 0.4, 0.05], HP + 0.18, { color: PAL.burntOrange });
  const globe = P('nm_globe', [19.0, 0.4, 1.2], 0.4);
  obj(game, 'ee_anchor_desk', { group: desk, parts: { ...(desk?.userData.parts || {}) }, top: [20.2, 1.21, 0.0], drop: [19.6, 0.4, 0.0] });
  obj(game, 'ee_anchor_chair', { group: chair, parts: {} });
  // Fresnels on a short batten in front of the desk (lit after power)
  const batY = 3.52;
  const batten = P('bc_grid_batten', [18.1, 0, 0], -HP, { len: 3 });
  if (batten) batten.position.y = batY - batten.userData.hang.pipeY;
  for (const z of [-1.3, 1.3]) add(K.m(K.cyl(0.015, 0.015, 4.0 - batY, { seg: 8 }), mt.chrome, { pos: [18.1, batY, z] }));
  const fresnels = [];
  for (const z of [-0.75, 0.75]) {
    const f = P('bc_light_fresnel', [18.1, 0, z], -HP, { tilt: 0.72, gel: 'tungsten', lit: false });
    if (!f) continue;
    f.position.y = batY - f.userData.hang.pipeY;
    fresnels.push(f);
  }
  const deskPool = pool(game, [20.0, 0.415, 0.0], 2.4, '#FFD9A0', 0);
  game.lights?.addAnchor?.({ id: 'nr_fresnel', pos: [19.2, 2.6, 0], color: '#FFD9A0', intensity: 0, distance: 7, area: aid });
  rt.power([18.1, 3.2, 0], (on) => {
    for (const f of fresnels) setLamp(f, on ? 'on' : 'off', 'lens');
    deskPool.set({ intensity: on ? 0.32 : 0 });
    game.lights?.setAnchor?.('nr_fresnel', { intensity: on ? 4.2 : 0 });
  }, { sound: 'light_thunk' });

  // ------------------------------------------------------------------------ skyline backdrop + world clocks
  const skyZ = 0.5, skyW = 4.2;
  const sky = P('nm_skyline', [22.85, 0, skyZ], HP, { w: skyW, h: 3.2 });
  const washMat = additive(washTex(), '#2E6BD9', 0);
  const wash = add(K.m(quad(skyW, 3.2), washMat, { pos: [22.7, 1.95, skyZ], rot: [0, -HP, 0], cast: false, receive: false }));
  wash.userData.noMerge = true;
  wash.renderOrder = 2;
  game.lights?.addAnchor?.({ id: 'nr_backdrop_wash', pos: [21.9, 2.3, skyZ], color: '#2E6BD9', intensity: 0, distance: 5.5, area: aid });
  rt.power([22.2, 2, skyZ], (on) => {
    washMat.setLevel(on ? 0.55 : 0);
    game.lights?.setAnchor?.('nr_backdrop_wash', { intensity: on ? 3.2 : 0 });
  });
  const clocks = {};
  [['ny', 'NEW YORK', skyZ - 0.9], ['london', 'LONDON', skyZ], ['tokyo', 'TOKYO', skyZ + 0.9]].forEach(([k, label, z]) => {
    const c = P('clock_wall', [22.75, 2.28, z], HP, { label, size: 0.34 });
    if (c) clocks[k] = c.userData.parts;
  });
  obj(game, 'clocks_newsroom', { parts: clocks, set: (h, m, s) => { for (const k in clocks) setClockHands(clocks[k], h, m, s); } });
  obj(game, 'skyline_backdrop', { group: sky, wash });

  // --------------------------------------------------------------------------------------- reporter desks
  const northZ = -3.55, southZ = 1.05;
  const tw = [PAL.harvestGold, PAL.burntOrange, PAL.teal, PAL.avocado, PAL.channelRed];
  // north row faces the aisle (rotY π); the west desk is the toy desk (bare desk + toy typewriter)
  const toyDesk = P('nm_desk_bare', [10.6, 0, northZ], Math.PI + 0.02);
  const typer = P('nm_typewriter', [11.0, DESK_TOP, -3.52], Math.PI - 0.06, { color: PAL.burntOrange });
  P('phone_rotary', [10.1, DESK_TOP, -3.5], Math.PI + 0.4, { color: '#F4F1E8' });
  const stack = (x, z, n, r0) => { for (let i = 0; i < n; i++) add(K.m(quad(0.22, 0.28, A.cell(i === n - 1 ? 'page' : 'cream')), A.mat, { pos: [x, DESK_TOP + 0.003 + i * 0.004, z], rot: [-HP, 0, r0 + (rnd() - 0.5) * 0.15], cast: false })); };
  stack(10.35, -3.85, 5, 0.3);
  P('nm_desk_lamp', [11.15, DESK_TOP, -3.85], Math.PI + 0.5, { color: PAL.burntOrange });
  P('desk_reporter', [13.0, 0, northZ], Math.PI - 0.015, { typewriter: tw[1], phone: '#E23B3B' });
  P('desk_reporter', [15.4, 0, northZ], Math.PI + 0.02, { typewriter: tw[2], phone: '#F4F1E8', color: '#9AA8B4' });
  // south row faces the aisle (rotY 0)
  P('desk_reporter', [11.1, 0, southZ], 0.02, { typewriter: tw[3], phone: '#2F5BD3', color: '#9AA8B4' });
  P('desk_reporter', [13.5, 0, southZ], -0.01, { typewriter: tw[0], phone: '#F4F1E8' });
  P('desk_reporter', [15.9, 0, southZ], 0.015, { typewriter: tw[4], phone: '#E23B3B' });
  // chairs (pushed out, askew) + one toppled
  P('chair_office', [10.9, 0, -2.78], 0.35, { color: PAL.burntOrange });
  P('chair_office', [13.2, 0, -2.72], -0.25, { color: PAL.harvestGold });
  P('chair_office', [11.3, 0, 0.3], Math.PI - 0.4, { color: PAL.harvestGold });
  P('chair_office', [14.65, 0, 0.3], Math.PI + 0.3, { color: PAL.burntOrange });
  const tipped = P('chair_office', [15.6, 0, -2.55], 0, { color: PAL.avocado }, { colliders: false });
  if (tipped) { tipped.rotation.set(0, 1.1, HP * 0.98); tipped.position.y = 0.3; game.level?.col?.addBox([15.0, 0, -3.0], [16.2, 0.62, -2.1], { tag: 'prop' }); }
  // desk lamps on a few desks (post power)
  const deskLamps = [
    P('nm_desk_lamp', [15.72, DESK_TOP, -3.86], Math.PI - 0.5, { color: PAL.teal }),
    P('nm_desk_lamp', [10.75, DESK_TOP, 1.35], 0.4, { color: PAL.mustard }),
    P('nm_desk_lamp', [15.55, DESK_TOP, 1.35], -0.3, { color: PAL.avocado }),
  ].filter(Boolean);
  const lampPools = deskLamps.map((l) => pool(game, [l.position.x + Math.sin(l.rotation.y) * -0.15, DESK_TOP + 0.01, l.position.z - Math.cos(l.rotation.y) * 0.15], 0.55, '#FFD9A0', 0));
  rt.power([13.5, 1, -1], (on) => {
    for (const l of deskLamps) l.userData.parts.bulb.material.setLevel(on ? 2.4 : 0.35);
    for (const p of lampPools) p.set({ intensity: on ? 0.35 : 0 });
  });
  // floor clutter: papers, crumpled balls, trash cans, a spilled folder
  P('trash_can', [12.0, 0, -4.2], 0.3, { color: PAL.burntOrange });
  P('trash_can', [14.55, 0, 1.6], -0.4, { color: PAL.avocado });
  const ball = (x, z) => add(K.m(tc(new THREE.IcosahedronGeometry(0.045, 1), '#F4EEDC'), mt.paint, { pos: [x, 0.04, z], rot: [rnd() * 3, rnd() * 3, 0] }));
  [[12.3, -4.4], [12.05, -4.55], [14.2, -2.2], [9.6, -0.6], [17.2, -1.4], [16.4, 0.2]].forEach(([x, z]) => ball(x, z));
  [[12.6, -2.1, 0.4], [13.4, -1.8, -0.8], [14.8, -0.7, 1.2], [9.9, -1.9, 2.4], [17.0, -2.4, 0.2], [16.6, -0.3, -1.0], [11.4, -0.4, 0.9]].forEach(([x, z, r], i) => {
    add(K.m(quad(0.22, 0.28, A.cell(i % 3 === 0 ? 'news' : 'page')), A.mat, { pos: [x, 0.006 + i * 0.0006, z], rot: [-HP, 0, r], cast: false }));
  });
  floorDecal('scuff', 13.2, -1.2, 2.2, 0.3);
  floorDecal('scuff', 17.2, 0.6, 1.8, 1.6);
  floorDecal('dust', 9.2, -4.9, 1.6, 0);

  // ----------------------------------------------------------------------------- teletype corner (NW)
  const tele = P('nm_teletype', [8.25, 0, -5.5], Math.PI);
  const tpos = tele ? tele.localToWorld(new THREE.Vector3(...tele.userData.anchors.lamp)) : new THREE.Vector3(8.2, 1.1, -5.3);
  game.lights?.addAnchor?.({ id: 'nr_teletype_lamp', pos: [tpos.x, tpos.y, tpos.z], color: '#FFB45A', intensity: 2.4, distance: 4.5, area: aid, flicker: 0.04 });
  pool(game, [8.25, 0.01, -4.95], 1.3, '#FFB45A', 0.3);
  // fan-fold printout pile + newspaper bundles beside it
  for (let i = 0; i < 7; i++) add(K.m(tc(K.box(0.36, 0.022, 0.28, 'xs'), i % 2 ? '#F4EBC8' : '#E9DFB8'), mt.paint, { pos: [7.55, 0.011 + i * 0.022, -5.45], rot: [0, (rnd() - 0.5) * 0.3, 0] }));
  add(K.m(quad(0.36, 0.28, A.cell('wire')), A.mat, { pos: [7.55, 0.17, -5.45], rot: [-HP, 0, 0.1], cast: false }));
  for (let i = 0; i < 3; i++) {
    add(K.m(tc(K.box(0.42, 0.14, 0.3, 'sm'), '#E6DECB'), mt.paint, { pos: [7.62 + (i === 2 ? 0.05 : 0), 0.07 + (i === 2 ? 0.14 : 0), -4.7 + (i === 1 ? 0.33 : 0)], rot: [0, 0.2 * (i - 1), 0] }));
    add(K.m(quad(0.4, 0.28, A.cell('news')), A.mat, { pos: [7.62 + (i === 2 ? 0.05 : 0), 0.142 + (i === 2 ? 0.14 : 0), -4.7 + (i === 1 ? 0.33 : 0)], rot: [-HP, 0, 0.2 * (i - 1)], cast: false }));
    add(K.m(tc(K.box(0.02, 0.145, 0.31, 'xs'), '#B5472A'), mt.paint, { pos: [7.62 + (i === 2 ? 0.05 : 0), 0.072 + (i === 2 ? 0.14 : 0), -4.7 + (i === 1 ? 0.33 : 0)], rot: [0, 0.2 * (i - 1), 0] }));
  }
  game.level?.col?.addBox([7.3, 0, -5.0], [7.9, 0.4, -4.25], { tag: 'prop' });
  // west wall: filing cabinet, cork board, assignment board, coat tree
  P('filing_cabinet', [7.55, 0, -3.75], -HP, { color: '#C9A06A', ajar: true });
  P('cork_board', [7.15, 1.05, -4.62], -HP, { w: 1.2, h: 0.8, seed: 3 });
  add(K.m(tc(K.box(1.16, 0.84, 0.05, 'sm'), '#7A4A2A'), mt.lacquer, { pos: [7.19, 1.92, -3.0], rot: [0, HP, 0] }));
  sheet('assign', 7.225, 1.92, -3.0, 1.04, 0.72, 0, 0).rotation.set(0, HP, 0);
  P('coat_rack', [7.5, 0, 0.65], 0.3);
  P('clock_wall', [7.16, 2.75, 1.1], -HP, { label: 'WZTV', size: 0.42 });

  // ------------------------------------------------------------------------------------- north wall
  P('water_cooler', [9.2, 0, -5.62], Math.PI);
  P('nm_coffee_cart', [10.15, 0, -5.55], Math.PI + 0.06);
  floorDecal('stain', 10.1, -5.0, 0.55, 0.8);
  add(K.m(tc(new THREE.CylinderGeometry(0.028, 0.02, 0.07, 10, 1, true), '#F4F1E8'), mt.plastic, { pos: [9.8, 0.02, -4.95], rot: [HP, 0, 0.6] }));
  P('bookshelf', [14.1, 0, -5.67], Math.PI, { seed: 5 });
  P('cork_board', [15.45, 1.1, -5.85], Math.PI, { w: 0.9, h: 0.7, seed: 8 });
  sheet('sched', 14.1, 2.45, -5.83, 0.75, 0.75, 0, 0).rotation.set(0, 0, 0.02);
  sheet('quiet', 11.95, 3.02, -5.83, 0.55, 0.55, 0, 0);
  // weather map (EE)
  const wmap = P('weather_map', [17.5, 0.45, -5.9], Math.PI, {}, { lights: false });
  const hoodMat = dimmableGlow('#FFF2D8', 2.0);
  if (wmap) swapMat(wmap, K.glow(game, '#FFF2D8', 2.0), hoodMat);
  if (wmap) {
    const u = wmap.userData;
    const tower = wmap.localToWorld(new THREE.Vector3(...u.anchors.tower_icon));
    const slides = [];
    obj(game, 'ee_weather_map', {
      group: wmap, parts: { ...u.parts }, anchors: u.anchors, towerIcon: tower,
      showMagnet: (name, pos) => showMagnet(wmap, name, pos),
      slide: (name, to, seconds = 1.2) => {
        const m = u.parts[`magnet_${name}`];
        if (!m) return;
        m.visible = true;
        slides.push({ m, from: [m.position.x, m.position.y], to, t: 0, d: Math.max(0.05, seconds) });
      },
      flash: (on) => game.lights?.setAnchor?.('nr_weather_hood', { intensity: on ? 3.5 : mapHoodLevel }),
    });
    rt.tick((dt) => {
      for (let i = slides.length - 1; i >= 0; i--) {
        const s = slides[i];
        s.t += dt;
        const k = Math.min(1, s.t / s.d), e = k * k * (3 - 2 * k);
        s.m.position.x = s.from[0] + (s.to[0] - s.from[0]) * e;
        s.m.position.y = s.from[1] + (s.to[1] - s.from[1]) * e;
        s.m.position.z = u.anchors.face_z - 0.004;
        s.m.rotation.x = 0;
        if (k >= 1) slides.splice(i, 1);
      }
    });
  }
  let mapHoodLevel = 0;
  game.lights?.addAnchor?.({ id: 'nr_weather_hood', pos: [17.5, 2.6, -5.0], color: '#FFF2D8', intensity: 0, distance: 4, area: aid });
  rt.power([17.5, 2.5, -5.3], (on) => {
    mapHoodLevel = on ? 1.6 : 0;
    hoodMat.setLevel(on ? 2.0 : 0.2);
    game.lights?.setAnchor?.('nr_weather_hood', { intensity: mapHoodLevel });
  });
  P('plant_snake', [19.55, 0, -5.55], 0.4, { seed: 2 });
  P('plant_rubber', [22.35, 0, -2.35], 1.2, { seed: 4 });

  // ------------------------------------------------------------------------------ south wall + camera
  P('bookshelf', [12.4, 0, 3.67], 0, { seed: 9 });
  P('plant_fern', [15.3, 0, 3.4], 0.6, { seed: 3 });
  P('filing_cabinet', [17.6, 0, 3.45], 0, { color: '#8FA38A' });
  const tv = P('bc_tv_portable', [17.6, 1.4, 3.5], 0.25, { color: 'orange', card: 'snow' });
  void tv;
  P('frame_picture', [12.4, 2.0, 3.85], 0, { card: 'poster_precinct13', style: 'chrome', h: 0.8 });
  sheet('promo', 20.6, 2.35, 3.83, 0.8, 0.8, 0, 0).rotation.set(0, Math.PI, 0);
  P('bc_teleprompter', [20.7, 0, 2.95], Math.PI * 0.85);
  const cam = P('bc_pedestal_camera', [16.8, 0, 2.0], yawTo([16.8, 0, 2.0], [20.2, 0, 0.0]), { num: 2, tally: false });
  const cart = P('bc_cart_monitor', [16.4, 0, 3.35], 0.03, { group: 'scr_feed_newsroom', id: 'mon_newsroom_cart', card: 'snow' });
  add(K.m(ribbon([[16.9, 0.02, 2.5], [16.6, 0.012, 2.9], [16.1, 0.012, 3.1], [15.8, 0.012, 3.7]], 0.04, { seg: 16 }), K.mat(game, 'rubber', '#2A2230'), { cast: false }));
  if (cam) {
    const cp = cam.userData.parts;
    const baseYaw = cp.head.rotation.y;
    obj(game, 'feed_cam_newsroom', { group: cam, parts: { ...cp }, setTally: (on) => setLamp(cam, on ? 'on' : 'off', 'tally') });
    rt.tick(() => { cp.head.rotation.y = baseYaw + 0.349 * Math.sin((game.time.now / 8) * TAU); });
    rt.power(cam.position.clone().setY(1.6), (on) => setLamp(cam, on ? 'on' : 'off', 'tally'), { flicker: false });
  }
  if (cart) obj(game, 'mon_newsroom_cart', { group: cart, screen: cart.userData.screens[0]?.mesh || null });
  pool(game, [16.4, 0.01, 2.75], 0.9, '#7FE7FF', 0.12);
  // ss_newsroom monitor bank in the SE corner (screen spawn = the middle lower CRT)
  const bank = P('bc_monitor_bank', [22.05, 0, 3.08], Math.PI / 4, {
    cards: ['snow', 'snow', 'snow', 'snow', 'snow'], groups: ['scr_decor', 'scr_decor', 'scr_decor', 'scr_decor', 'scr_decor'],
    ids: ['nr_bank_0', 'ss_newsroom', 'nr_bank_2', 'nr_bank_3', 'nr_bank_4'],
  });
  if (bank) {
    const scr = bank.userData.screens;
    obj(game, 'ss_newsroom', { group: bank, screen: scr.find((s) => s.id === 'ss_newsroom')?.mesh || null, screens: scr.map((s) => s.mesh) });
  }
  pool(game, [21.4, 0.01, 2.4], 1.4, '#7FE7FF', 0.16);

  // ------------------------------------------------------------------------------ moonlight slats (B4/B5)
  const slatMat = additive(slatTex(6), '#9FB6FF', 0.5);
  for (const x of [14, 19]) {
    const m = add(K.m(quad(1.7, 2.3), slatMat, { pos: [x + 0.25, 0.012, 2.65], rot: [-HP, 0, 0.12], cast: false, receive: false }));
    m.renderOrder = 1;
  }
  const mapSlats = add(K.m(quad(2.3, 1.7), slatMat, { pos: [17.6, 1.95, -5.8], rot: [0, 0, 0.5], cast: false, receive: false }));
  mapSlats.renderOrder = 3;
  game.lights?.addAnchor?.({ id: 'nr_moon_w', pos: [14, 1.6, 2.6], color: '#9FB6FF', intensity: 1.4, distance: 5, area: aid });
  game.lights?.addAnchor?.({ id: 'nr_moon_e', pos: [19, 1.6, 2.6], color: '#9FB6FF', intensity: 1.4, distance: 5, area: aid });
  rt.power([16.5, 1.5, 3], (on) => {
    slatMat.setLevel(on ? 0.16 : 0.5);
    game.lights?.setAnchor?.('nr_moon_w', { intensity: on ? 0.4 : 1.4 });
    game.lights?.setAnchor?.('nr_moon_e', { intensity: on ? 0.4 : 1.4 });
  }, { flicker: false });

  // ------------------------------------------------------------------------------------------ toys
  if (typer) {
    const p = typer.userData.parts;
    const x0 = p.carriage.position.x;
    let t = -1;
    const play = () => { t = 0; game.audio?.play?.('toy_typewriter', { pos: typer.getWorldPosition(new THREE.Vector3()) }); };
    rt.tick((dt) => {
      if (t < 0) return;
      t += dt;
      // two clacks (0.0, 0.25, 0.5), ding + return at 0.8 → 1.15
      const steps = Math.min(3, Math.floor(t / 0.22) + 1);
      const inStep = (t % 0.22) / 0.22;
      p.keys.position.y = t < 0.7 && inStep < 0.35 ? -0.008 : 0;
      if (t < 0.8) p.carriage.position.x = x0 + steps * 0.03 - (inStep < 0.2 ? 0.01 : 0);
      else p.carriage.position.x = x0 + 0.09 * (1 - Math.min(1, (t - 0.8) / 0.3));
      if (t > 1.2) { t = -1; p.carriage.position.x = x0; p.keys.position.y = 0; }
    });
    toy(game, 'toy_typewriter', ANCHORS.toy_typewriter.pos, play, { cooldown: 1.2 });
    obj(game, 'toy_typewriter', { group: typer, parts: { ...p }, play });
  }
  if (globe) {
    const p = globe.userData.parts;
    let spin = 0;
    const play = () => { spin = 14; game.audio?.play?.('toy_globe', { pos: new THREE.Vector3(...ANCHORS.toy_globe.pos) }); };
    rt.tick((dt) => {
      if (spin <= 0.001) return;
      p.globe.rotation.y += spin * dt;
      spin *= Math.exp(-0.9 * dt);
      if (spin < 0.05) spin = 0;
    });
    toy(game, 'toy_globe', ANCHORS.toy_globe.pos, play, { cooldown: 0.6 });
    obj(game, 'toy_globe', { group: globe, parts: { ...p }, play });
  }
  if (tele) {
    const p = tele.userData.parts;
    const hx = p.head.position.x;
    const paperScale = { v: 1 };
    let t = -1;
    const play = () => { t = 0; game.audio?.play?.('toy_teletype', { pos: new THREE.Vector3(...ANCHORS.toy_teletype.pos) }); };
    rt.tick((dt, time) => {
      if (t < 0) { p.bulb.material.setLevel(2.4 + Math.sin(time * 9.1) * 0.05); return; }
      t += dt;
      const on = t < 3;
      p.head.position.x = on ? hx + Math.sin(t * 38) * 0.18 * Math.min(1, t * 4) : hx;
      p.keys.position.y = on && Math.sin(t * 47) > 0.2 ? -0.008 : 0;
      paperScale.v = on ? 1 + t * 0.12 : Math.max(1, paperScale.v - dt * 0.5);
      p.paper.scale.set(1, paperScale.v, paperScale.v);
      p.tape.scale.setScalar(on ? 1 + 0.04 * Math.sin(t * 30) : 1);
      if (!on && paperScale.v <= 1) t = -1;
    });
    toy(game, 'toy_teletype', ANCHORS.toy_teletype.pos, play, { cooldown: 3.2 });
    obj(game, 'toy_teletype', { group: tele, parts: { ...p }, play });
  }

  // fluorescent flicker: one of the level's newsroom troffer anchors buzzes after power (GDD §3.3)
  rt.power([10, 3.5, -1], (on) => game.lights?.setAnchor?.('lvl_newsroom_0', { flicker: on ? 0.22 : 0 }), { flicker: false });
  return rt;
}
