// DEAD AIR — props: broadcast gear (docs/PROPKIT.md). 1977 TV-station hardware for Master Control, the studios,
// the newsroom and the lobby exhibit. One shared 1024² canvas ATLAS ("bc_atlas_2") carries flat palette swatches
// (32 px cells, rows 0-1), lit lamp colors (row 2) and every printed part (dials, VU faces, jacks, nameplates, signs,
// slate, reel faces), so most props render with 3-6 materials: paletted plastic (pl), paletted matte (mt), paletted
// metal (me), chrome (ch), lit atlas (lit / soft / sign glows), dim (unlit lamp), CRT glass + one CRT per screen.
//
// PROPS (category 'broadcast'; shoot: node tools/propview/shoot.cjs category:broadcast --out _shots/props/broadcast)
//   bc_pedestal_camera   hero studio camera: tally dome, zoom lens + matte box, pan bars, headset on hook
//   bc_eng_camera        hero ENG shoulder camera on a wooden tripod, battery belt on the front leg
//   bc_tv_portable       13" red portable, VHF/UHF dials, rabbit ears          bc_tv_19        19" walnut TV on legs
//   bc_rack_monitor      broadcast rack monitor (9"/14")                        bc_monitor_bank hero 5-CRT bank
//   bc_cart_monitor      hero AV cart: 19" monitor + cassette deck              bc_monitor_wall hero MC 4x3 CRT wall
//   bc_console_switcher / _audio / _monitor (hero, preview monitor) / _corner (45 deg) / _end   MC island segments
//   bc_patch_bay         19" rack with patch rows + cords                       bc_vtr_quad     hero quad 2" VTR
//   bc_boom_mic          hero Fisher boom dolly                                 bc_light_fresnel / _scoop (hanging)
//   bc_light_tripod / bc_light_softbox (floor stands)                           bc_grid_clamp / bc_grid_batten
//   bc_cable_spaghetti / bc_cable_coil (walkable)                               bc_flight_case / _stack (hero)
//   bc_on_air (wall) / bc_applause (hero, hanging)                              bc_clapperboard, bc_teleprompter
//   bc_reel_to_reel, bc_headphones_hook (wall)
// Scenes: bc_master_control, bc_studio. Debug (only with ?bcprof=1): bc__atlas, bc__vu + per-prop tri breakdown log.
//
// Conventions (on top of the kit's): wall-mounted props (ON AIR, headphones hook) have their back face at z = +D/2
// (place at wallZ - D/2); hanging props (APPLAUSE, grid lights, batten, clamp) keep y = 0 at their lowest point and
// expose userData.hang.pipeY (pipe center above the origin: place at gridY - pipeY); grid lights expose
// userData.aim {pos, dir} for spot lights. Screens get ids in userData.screens[i].id where useful. Named parts
// (userData.parts) are noMerge so rooms/machines can animate or re-material them; lamps expose
// userData.lampMats = { on, off } and the exported setLamp(prop, 'on'|'off'|color, part='lamp').
// Geometry helpers (local): cbox (44-tri chamfer box), keycap (18 tris), L/bcyl (1-step lathes), frame (bevelled
// ring: keep bevel < 0.35 * border), monitorUnit, tapeReel, spindle, vuMeter, knob, caster, rabbitEars, fresnelHead.

import * as K from './kit.js';
import { registerProp, registerScene, PAL, THREE } from './kit.js';
import { getCard } from '../gfx/cards.js';
import { mulberry32 } from '../core/rng.js';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';

const TAU = Math.PI * 2, HP = Math.PI / 2;
const UP = new THREE.Vector3(0, 1, 0);

// ================================================================================================= ATLAS
const AS = 1024;
// flat swatches: rows 0-1 (32) + row 3 (16). Sampled at the swatch center (palette texturing).
const SW = {
  cream: '#F6E7C8', ivory: '#EFE6D2', capWhite: '#F4F1E8', putty: '#D2C6AE', beige: '#C4B394', sand: '#E3D3B0',
  wztvBlue: '#2F5BD3', navy: '#22367A', sky: '#86B6EA', teal: '#2E8C8C',
  red: '#E23B3B', maroon: '#8E2A2E', orange: '#E3662B', gold: '#E8A92E', mustard: '#D9A520', avocado: '#8C9A3A',
  chocolate: '#5A3A22', walnut: '#7A4A2A', tan: '#B8895A', plum: '#6B3A6E',
  ink: '#2A2231', charcoal: '#3B3645', slate: '#505A6E', gunmetal: '#6B7282', grey: '#8F95A0', silver: '#B8BEC8', light: '#DADDE2',
  rubber: '#2B2530', black: '#1D1822', white: '#FBF8F1', olive: '#6E7A34', rust: '#B5472A',
  // row 3
  lampRed: '#7A2428', lampAmber: '#86602A', lampGreen: '#2F6234', lampBlue: '#2C3F78', lampWhite: '#9A9284',
  tape: '#4A2E1E', tapeGold: '#A8823A', pink: '#E88AAA', lilac: '#A88ACF', mint: '#9ED9C0', brass: '#C8963C',
  copper: '#B8683A', cork: '#B98F5E', denim: '#3A5A8A', paper: '#F3EEDF', steel: '#7C8594',
};
// lit swatches (row 2): used with the lit (glow) atlas material
const LIT = {
  red: '#FF3B30', amber: '#FFB347', green: '#52E04A', blue: '#4A86FF', white: '#FFF1D8', yellow: '#FFE14A',
  cyan: '#5FE3FF', magenta: '#FF4FA0', orange: '#FF8A2A', tungsten: '#FFC98A', purple: '#B070FF', softWhite: '#E8DCC0',
};
// 32 px swatch cells, 32 per row: rows 0-1 flat, row 2 lit. Swatch-mapped meshes have one UV per mesh, so their UV
// derivatives are zero (mip 0 always): no bleeding between neighbours at any distance.
const SWS = 32;
const SWUV = {};
Object.keys(SW).forEach((k, i) => {
  const row = Math.floor(i / 32), col = i % 32;
  SWUV[k] = [(col * SWS + SWS / 2) / AS, 1 - (row * SWS + SWS / 2) / AS, col * SWS, row * SWS];
});
const LITUV = {};
Object.keys(LIT).forEach((k, i) => { LITUV[k] = [(i * SWS + SWS / 2) / AS, 1 - (2 * SWS + SWS / 2) / AS, i * SWS, 2 * SWS]; });

const FONTS = {
  bungee: '"Bungee", "Arial Black", sans-serif', titan: '"Titan One", "Arial Black", sans-serif',
  vt: '"VT323", "Courier New", monospace', shrik: '"Shrikhand", "Cooper Black", Georgia, serif', mono: '"Courier New", Courier, monospace',
};
function txt(ctx, s, x, y, size, font, color, o = {}) {
  const f = FONTS[font] || font;
  let sz = size;
  ctx.font = `${sz}px ${f}`;
  if (o.max) while (ctx.measureText(s).width > o.max && sz > 5) { sz *= 0.92; ctx.font = `${sz}px ${f}`; }
  ctx.textAlign = o.align || 'center';
  ctx.textBaseline = 'middle';
  if (o.stroke) { ctx.lineWidth = o.lw || sz * 0.12; ctx.strokeStyle = o.stroke; ctx.lineJoin = 'round'; ctx.strokeText(s, x, y); }
  if (o.shadow) { ctx.fillStyle = o.shadow; ctx.fillText(s, x + sz * 0.04, y + sz * 0.05); }
  ctx.fillStyle = color;
  ctx.fillText(s, x, y);
}
function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
function lighten(hex, a) { const c = new THREE.Color(hex); if (a >= 0) c.lerp(new THREE.Color(1, 1, 1), a); else c.multiplyScalar(1 + a); return '#' + c.getHexString(); }

// printed plate: rounded plate with border + text
function drawPlate(text, o = {}) {
  const { bg = '#C9CED6', fg = '#2A2231', border = '#8F95A0', stripe = null, font = 'bungee', sub = null } = o;
  return (ctx, w, h) => {
    const g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, lighten(bg, 0.25)); g.addColorStop(0.5, bg); g.addColorStop(1, lighten(bg, -0.18));
    ctx.fillStyle = border; ctx.fillRect(0, 0, w, h);
    rr(ctx, 3, 3, w - 6, h - 6, h * 0.22); ctx.fillStyle = g; ctx.fill();
    if (stripe) { ctx.fillStyle = stripe; ctx.fillRect(6, h * 0.72, w - 12, h * 0.1); }
    txt(ctx, text, w / 2, sub ? h * 0.4 : h * 0.52, h * (sub ? 0.46 : 0.58), font, fg, { max: w * 0.86 });
    if (sub) txt(ctx, sub, w / 2, h * 0.78, h * 0.22, 'titan', fg, { max: w * 0.8 });
  };
}

function drawDial(labels, o = {}) {
  const { bg = '#F4F1E8', fg = '#2A2231', ring = null, title = null, titleColor = '#E23B3B', span = 1.6, font = 'titan' } = o;
  return (ctx, w, h) => {
    const cx = w / 2, cy = h / 2, R = w / 2 - 2;
    ctx.fillStyle = ring || lighten(bg, -0.25); ctx.beginPath(); ctx.arc(cx, cy, R, 0, TAU); ctx.fill();
    ctx.fillStyle = bg; ctx.beginPath(); ctx.arc(cx, cy, R - 4, 0, TAU); ctx.fill();
    const n = labels.length;
    for (let i = 0; i < n; i++) {
      const a = -Math.PI * span / 2 + (n > 1 ? i / (n - 1) : 0) * Math.PI * span;
      const sx = Math.sin(a), sy = -Math.cos(a);
      ctx.strokeStyle = fg; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.moveTo(cx + sx * R * 0.84, cy + sy * R * 0.84); ctx.lineTo(cx + sx * R * 0.95, cy + sy * R * 0.95); ctx.stroke();
      if (labels[i] !== '') txt(ctx, String(labels[i]), cx + sx * R * 0.66, cy + sy * R * 0.66, w * (n > 12 ? 0.1 : 0.12), font, fg);
    }
    if (title) txt(ctx, title, cx, cy + R * 0.62, w * 0.1, 'bungee', titleColor, { max: R * 1.1 });
  };
}

// cells [name, w, h, draw(ctx, w, h, rand)] — shelf-packed from y = 96 (rows 0-2 are swatches)
const SPECS = [];
const cell = (name, w, h, draw) => SPECS.push([name, w, h, draw]);

cell('reel', 256, 256, (ctx, w, h) => { // 2" quad / NAB aluminum reel flange with tape visible through windows
  const cx = w / 2, cy = h / 2, R = w / 2 - 2;
  const g = ctx.createRadialGradient(cx - 30, cy - 40, 10, cx, cy, R);
  g.addColorStop(0, '#EEF1F5'); g.addColorStop(0.6, '#BCC3CC'); g.addColorStop(1, '#8E96A2');
  ctx.fillStyle = '#6E7684'; ctx.beginPath(); ctx.arc(cx, cy, R, 0, TAU); ctx.fill();
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(cx, cy, R - 5, 0, TAU); ctx.fill();
  for (let i = 0; i < 3; i++) { // three windows showing the tape pack
    const a = i / 3 * TAU - HP;
    ctx.beginPath();
    ctx.arc(cx, cy, R * 0.82, a - 0.62, a + 0.62);
    ctx.arc(cx, cy, R * 0.34, a + 0.5, a - 0.5, true);
    ctx.closePath();
    const tg = ctx.createRadialGradient(cx, cy, R * 0.3, cx, cy, R * 0.85);
    tg.addColorStop(0, '#2A1A12'); tg.addColorStop(0.55, '#5A3A22'); tg.addColorStop(1, '#3A2416');
    ctx.fillStyle = tg; ctx.fill();
    ctx.strokeStyle = '#5E6674'; ctx.lineWidth = 4; ctx.stroke();
  }
  for (let r = 0.9; r > 0.3; r -= 0.06) { ctx.strokeStyle = 'rgba(255,255,255,0.08)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(cx, cy, R * r, 0, TAU); ctx.stroke(); }
  ctx.fillStyle = '#9AA2AE'; ctx.beginPath(); ctx.arc(cx, cy, R * 0.26, 0, TAU); ctx.fill();
  ctx.fillStyle = '#4A5260'; ctx.beginPath(); ctx.arc(cx, cy, R * 0.12, 0, TAU); ctx.fill();
  for (let i = 0; i < 6; i++) { const a = i / 6 * TAU; ctx.fillStyle = '#6E7684'; ctx.beginPath(); ctx.arc(cx + Math.cos(a) * R * 0.19, cy + Math.sin(a) * R * 0.19, 3.5, 0, TAU); ctx.fill(); }
});
cell('slate', 256, 192, (ctx, w, h) => { // clapperboard slate face
  ctx.fillStyle = '#26242C'; ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = 'rgba(244,241,232,0.85)'; ctx.lineWidth = 2.5;
  const L = (x0, y0, x1, y1) => { ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke(); };
  L(8, 48, w - 8, 48); L(8, 96, w - 8, 96); L(8, 144, w - 8, 144); L(w / 3, 96, w / 3, 144); L(2 * w / 3, 96, 2 * w / 3, 144);
  txt(ctx, 'WZTV 13', w / 2, 26, 30, 'bungee', '#F4F1E8');
  txt(ctx, 'PROD.', 30, 62, 11, 'titan', '#CFCAC0'); txt(ctx, 'Spooktacular', w / 2 + 14, 74, 26, 'shrik', '#F4F1E8', { max: 190 });
  txt(ctx, 'ROLL', 26, 106, 10, 'titan', '#CFCAC0'); txt(ctx, 'SCENE', w / 3 + 22, 106, 10, 'titan', '#CFCAC0'); txt(ctx, 'TAKE', 2 * w / 3 + 20, 106, 10, 'titan', '#CFCAC0');
  txt(ctx, '13', w / 6, 124, 26, 'shrik', '#F4F1E8'); txt(ctx, '1', w / 2, 124, 26, 'shrik', '#F4F1E8'); txt(ctx, '3', 5 * w / 6, 124, 26, 'shrik', '#FFB0A0');
  txt(ctx, 'DIR. B. VON STATIC', w / 2, 158, 14, 'titan', '#F4F1E8', { max: 230 });
  txt(ctx, '10 · 31 · 77', w / 2, 178, 14, 'titan', '#CFCAC0');
  ctx.fillStyle = 'rgba(255,255,255,0.05)'; for (let i = 0; i < 40; i++) ctx.fillRect((i * 97) % w, (i * 53) % h, 30, 2);
});
cell('script', 256, 192, (ctx, w, h) => { // teleprompter text (lit, on black: additive on the glass)
  ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h);
  const lines = ['GOOD EVENING,', 'AND WELCOME', 'BACK TO THE', '13-HOUR', 'SPOOKTACULAR!', '(SMILE)'];
  lines.forEach((s, i) => txt(ctx, s, w / 2, 20 + i * 30, 27, 'vt', i === 5 ? '#FFD23A' : '#F4F1E8', { max: w - 16 }));
});
cell('onair', 256, 96, (ctx, w, h) => {
  const g = ctx.createRadialGradient(w / 2, h / 2, 10, w / 2, h / 2, w * 0.55);
  g.addColorStop(0, '#FF5A48'); g.addColorStop(0.7, '#D8231E'); g.addColorStop(1, '#8A1010');
  ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  txt(ctx, 'ON AIR', w / 2, h * 0.54, 62, 'bungee', '#FFF1E0', { max: w * 0.88, shadow: 'rgba(90,0,0,0.5)' });
});
cell('applause', 384, 96, (ctx, w, h) => {
  const g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, '#C8283A'); g.addColorStop(1, '#8A1428');
  ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  txt(ctx, 'APPLAUSE', w / 2, h * 0.54, 60, 'bungee', '#FFF4D8', { max: w * 0.84, shadow: 'rgba(60,0,20,0.55)' });
});
cell('vu', 256, 128, (ctx, w, h) => { // backlit VU meter face (needle is 3D)
  const g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, '#FFF6CC'); g.addColorStop(1, '#F0D68A');
  ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  const cx = w / 2, cy = h * 1.02, R = h * 0.8;
  const T = [[-20, 0], [-10, 0.28], [-7, 0.4], [-5, 0.5], [-3, 0.6], [-2, 0.66], [-1, 0.72], [0, 0.78], [1, 0.85], [2, 0.92], [3, 1]];
  const ang = (t) => -HP - 0.8 + t * 1.6;
  ctx.lineWidth = 3; ctx.strokeStyle = '#2A2231'; ctx.beginPath(); ctx.arc(cx, cy, R, ang(0), ang(0.78)); ctx.stroke();
  ctx.lineWidth = 7; ctx.strokeStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(cx, cy, R + 2, ang(0.78), ang(1)); ctx.stroke();
  for (const [db, t] of T) {
    const a = ang(t), c = Math.cos(a), s = Math.sin(a);
    ctx.strokeStyle = t >= 0.78 ? '#C8201E' : '#2A2231'; ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.moveTo(cx + c * R, cy + s * R); ctx.lineTo(cx + c * (R + 12), cy + s * (R + 12)); ctx.stroke();
    if ([-20, -10, -5, -3, 0, 3].includes(db)) txt(ctx, String(Math.abs(db)), cx + c * (R + 24), cy + s * (R + 24), 15, 'titan', t >= 0.78 ? '#C8201E' : '#2A2231');
  }
  txt(ctx, 'VU', cx, h * 0.7, 30, 'bungee', '#2A2231');
  ctx.strokeStyle = '#8A7040'; ctx.lineWidth = 4; ctx.strokeRect(2, 2, w - 4, h - 4);
});
cell('vuBar', 64, 128, (ctx, w, h) => { // LED bar graph (lit)
  ctx.fillStyle = '#140E18'; ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 10; i++) {
    const y = h - 12 - i * 11.5;
    ctx.fillStyle = i >= 8 ? '#FF3B30' : i >= 6 ? '#FFB347' : '#52E04A';
    ctx.globalAlpha = i < 7 ? 1 : 0.35;
    rr(ctx, 14, y - 4, w - 28, 8, 2); ctx.fill();
  }
  ctx.globalAlpha = 1;
});
cell('dial10', 128, 128, drawDial(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10'], { bg: '#2E2836', fg: '#F4F1E8', ring: '#15101A', span: 1.55 }));
cell('dialCh', 128, 128, drawDial(['2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13'], { title: 'VHF' }));
cell('dialUhf', 128, 128, drawDial(['14', '', '30', '', '45', '', '60', '', '83'], { title: 'UHF', titleColor: '#2F5BD3' }));
cell('dialTrk', 128, 128, drawDial(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'], { title: 'TRACK', bg: '#F6E7C8', span: 1.8 }));
cell('logo13', 128, 128, (ctx, w, h) => { // WZTV "13" disc: white 13 in a blue disc with a red ring
  const cx = w / 2, cy = h / 2;
  ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(cx, cy, 63, 0, TAU); ctx.fill();
  ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(cx, cy, 58, 0, TAU); ctx.fill();
  ctx.fillStyle = '#2F5BD3'; ctx.beginPath(); ctx.arc(cx, cy, 47, 0, TAU); ctx.fill();
  txt(ctx, '13', cx + 1, cy + 4, 56, 'bungee', '#F4F1E8', { shadow: 'rgba(20,20,80,0.45)' });
});
cell('grille', 128, 128, (ctx, w, h) => {
  ctx.fillStyle = '#3A3444'; ctx.fillRect(0, 0, w, h);
  for (let y = 0; y < 9; y++) for (let x = 0; x < 9; x++) {
    ctx.fillStyle = '#120C16'; ctx.beginPath(); ctx.arc(10 + x * 13.5, 10 + y * 13.5, 4.2, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.12)'; ctx.beginPath(); ctx.arc(10 + x * 13.5, 11.5 + y * 13.5, 4.2, 0.2, 2.9); ctx.fill();
  }
});
cell('vent', 128, 128, (ctx, w, h) => {
  ctx.fillStyle = '#4A4556'; ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 7; i++) {
    rr(ctx, 10, 9 + i * 16.5, w - 20, 8, 4); ctx.fillStyle = '#120C16'; ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.14)'; ctx.fillRect(14, 18 + i * 16.5, w - 28, 1.5);
  }
});
cell('fabric', 128, 128, (ctx, w, h, rand) => { // TV speaker cloth: brown with gold thread
  ctx.fillStyle = '#5A3A22'; ctx.fillRect(0, 0, w, h);
  for (let y = 0; y < h; y += 4) { ctx.fillStyle = y % 8 ? '#6A4630' : '#4A2E1A'; ctx.fillRect(0, y, w, 2); }
  for (let x = 0; x < w; x += 4) { ctx.fillStyle = 'rgba(232,169,46,0.35)'; ctx.fillRect(x, 0, 1.5, h); }
  for (let i = 0; i < 300; i++) { ctx.fillStyle = rand() < 0.5 ? 'rgba(255,220,150,0.18)' : 'rgba(0,0,0,0.15)'; ctx.fillRect(rand() * w, rand() * h, 2, 1); }
});
cell('reelLabel', 128, 128, (ctx, w, h) => {
  ctx.fillStyle = '#F7F2E4'; ctx.beginPath(); ctx.arc(w / 2, h / 2, 62, 0, TAU); ctx.fill();
  ctx.strokeStyle = '#2F5BD3'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(w / 2, h / 2, 56, 0, TAU); ctx.stroke();
  txt(ctx, '13', w / 2, h / 2 + 2, 52, 'shrik', '#D8231E');
  txt(ctx, 'SIGN-OFF', w / 2, h * 0.82, 13, 'titan', '#2A2231');
  ctx.fillStyle = '#2A2231'; ctx.beginPath(); ctx.arc(w / 2, h / 2, 9, 0, TAU); ctx.fill();
});
cell('caseTag', 128, 128, (ctx, w, h) => { // stuck-on paper tag "FRAGILE" + arrows
  ctx.fillStyle = '#F3EEDF'; rr(ctx, 2, 2, w - 4, h - 4, 10); ctx.fill();
  ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 5; rr(ctx, 8, 8, w - 16, h - 16, 8); ctx.stroke();
  txt(ctx, 'FRAGILE', w / 2, 30, 22, 'bungee', '#E23B3B', { max: w - 24 });
  ctx.fillStyle = '#2A2231';
  for (const x of [w * 0.34, w * 0.66]) { ctx.beginPath(); ctx.moveTo(x, 50); ctx.lineTo(x + 16, 72); ctx.lineTo(x + 6, 72); ctx.lineTo(x + 6, 100); ctx.lineTo(x - 6, 100); ctx.lineTo(x - 6, 72); ctx.lineTo(x - 16, 72); ctx.closePath(); ctx.fill(); }
  txt(ctx, 'THIS SIDE UP', w / 2, 112, 12, 'titan', '#2A2231');
});
cell('digits', 128, 32, (ctx, w, h) => { ctx.fillStyle = '#0C0A10'; ctx.fillRect(0, 0, w, h); txt(ctx, '00:13:07:13', w / 2, h / 2 + 1, 28, 'vt', '#7CFF6A', { max: w - 8 }); });
cell('keys', 256, 32, (ctx, w, h) => {
  ctx.fillStyle = '#2E2836'; ctx.fillRect(0, 0, w, h);
  ['REW', 'PLAY', 'STOP', 'FF', 'REC'].forEach((s, i) => txt(ctx, s, 26 + i * 51, h / 2 + 1, 14, 'titan', i === 4 ? '#FF6A5A' : '#F4F1E8'));
});
cell('bus', 256, 32, (ctx, w, h) => {
  ctx.fillStyle = '#2E2836'; ctx.fillRect(0, 0, w, h);
  ['CAM1', 'CAM2', 'CAM3', 'CAM4', 'VTR1', 'VTR2', 'NET', 'BARS'].forEach((s, i) => txt(ctx, s, 16 + i * 32, h / 2 + 1, 10, 'titan', '#E8E2D4'));
});
cell('hv', 256, 48, (ctx, w, h) => {
  ctx.fillStyle = '#F4C81E'; ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = '#2A2231';
  for (let x = -h; x < w; x += 28) { ctx.beginPath(); ctx.moveTo(x, h); ctx.lineTo(x + 14, h); ctx.lineTo(x + 14 + h * 0.5, 0); ctx.lineTo(x + h * 0.5, 0); ctx.closePath(); ctx.fill(); }
  ctx.fillStyle = '#F4C81E'; rr(ctx, 30, 9, w - 60, h - 18, 6); ctx.fill();
  txt(ctx, 'HIGH VOLTAGE', w / 2, h / 2 + 1, 20, 'bungee', '#2A2231', { max: w - 70 });
});
cell('stripes', 256, 32, (ctx, w, h) => {
  ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = '#26242C';
  for (let x = -h; x < w + h; x += 44) { ctx.beginPath(); ctx.moveTo(x, h); ctx.lineTo(x + 22, h); ctx.lineTo(x + 22 + h, 0); ctx.lineTo(x + h, 0); ctx.closePath(); ctx.fill(); }
});
cell('jacks', 256, 64, (ctx, w, h) => { // patch bay jack row
  ctx.fillStyle = '#35303E'; ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = '#F0EBDD'; ctx.fillRect(4, h / 2 - 6, w - 8, 12);
  for (let i = 0; i < 16; i++) txt(ctx, String(i + 1), 10 + i * 15.6, h / 2, 8, 'titan', '#2A2231');
  for (const yy of [13, h - 13]) for (let i = 0; i < 16; i++) {
    const x = 10 + i * 15.6;
    ctx.fillStyle = '#C8CDD6'; ctx.beginPath(); ctx.arc(x, yy, 6, 0, TAU); ctx.fill();
    ctx.fillStyle = '#0E0A12'; ctx.beginPath(); ctx.arc(x, yy, 3, 0, TAU); ctx.fill();
  }
});
cell('meterRound', 128, 128, (ctx, w, h) => { // round panel meter (black face)
  ctx.fillStyle = '#1A1620'; ctx.beginPath(); ctx.arc(w / 2, h / 2, 62, 0, TAU); ctx.fill();
  ctx.strokeStyle = '#F4F1E8'; ctx.lineWidth = 2;
  for (let i = 0; i <= 10; i++) { const a = -2.3 + i / 10 * 1.6 * 1.3; ctx.beginPath(); ctx.moveTo(64 + Math.cos(a) * 44, 70 + Math.sin(a) * 44); ctx.lineTo(64 + Math.cos(a) * 52, 70 + Math.sin(a) * 52); ctx.stroke(); }
  ctx.strokeStyle = '#52E04A'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(64, 70, 48, -1.3, -0.4); ctx.stroke();
  txt(ctx, 'mA', 64, 92, 16, 'titan', '#F4F1E8');
});
cell('tape', 128, 64, (ctx, w, h) => { // gaffer tape strip
  ctx.fillStyle = '#9EA4AE'; ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 40; i++) { ctx.fillStyle = i % 2 ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)'; ctx.fillRect(0, i * 1.6, w, 0.8); }
  ctx.fillStyle = '#8A909A'; for (let x = 0; x < w; x += 6) ctx.fillRect(x, 0, 3, 3), ctx.fillRect(x + 3, h - 3, 3, 3);
});
// small labels (white on charcoal) and nameplates
const LABELS = ['LOBBY', 'NEWS', 'STUDIO A', 'STUDIO B', 'PGM', 'PVW', 'NET', 'VTR', 'CAM 1', 'CAM 2', 'AUDIO', 'SYNC', 'LINE', 'AIR'];
for (const t of LABELS) cell('lbl_' + t, 128, 32, drawPlate(t, { bg: '#2E2836', fg: '#F4F1E8', border: '#15101A', font: 'titan' }));
cell('pl_QUADRAMAX', 256, 48, drawPlate('QUADRAMAX', { bg: '#C9CED6', fg: '#22367A', stripe: '#E3662B' }));
cell('pl_VIDICAM', 256, 48, drawPlate('VIDICAM', { bg: '#C9CED6', fg: '#2A2231', stripe: '#2F5BD3' }));
cell('pl_KINETRON', 256, 48, drawPlate('KINETRON', { bg: '#2E2836', fg: '#E8E2D4', border: '#15101A' }));
cell('pl_AUDIOLUX', 256, 48, drawPlate('AUDIOLUX', { bg: '#D8C8A0', fg: '#5A3A22', border: '#8A6A40', font: 'titan' }));
cell('pl_ZENOLUX', 256, 48, drawPlate('ZENOLUX', { bg: '#C9CED6', fg: '#8E2A2E', font: 'titan' }));
cell('pl_WZTV', 256, 48, drawPlate('WZTV 13', { bg: '#2F5BD3', fg: '#F4F1E8', border: '#E23B3B' }));
cell('pl_PROPERTY', 256, 48, drawPlate('PROPERTY OF WZTV-13', { bg: '#F4C81E', fg: '#2A2231', border: '#2A2231', font: 'titan' }));
cell('pl_STUDIOA', 256, 48, drawPlate('STUDIO A', { bg: '#F3EEDF', fg: '#2A2231', border: '#E3662B', font: 'bungee' }));
cell('pl_MASTER', 256, 48, drawPlate('MASTER CONTROL', { bg: '#2E2836', fg: '#FFB347', border: '#15101A', font: 'bungee' }));
cell('pl_TELESCRIPT', 256, 48, drawPlate('TELE·Q', { bg: '#C9CED6', fg: '#2A2231', stripe: '#E23B3B' }));
cell('pl_FISHER', 256, 48, drawPlate('BOOMCO', { bg: '#C9CED6', fg: '#2A2231', stripe: '#E8A92E' }));
cell('pl_LUMEX', 256, 48, drawPlate('LUMEX', { bg: '#2E2836', fg: '#FFC98A', border: '#15101A' }));
for (let i = 1; i <= 4; i++) cell('num' + i, 64, 64, (ctx, w, h) => { ctx.fillStyle = '#2A2231'; rr(ctx, 1, 1, w - 2, h - 2, 10); ctx.fill(); txt(ctx, String(i), w / 2, h / 2 + 3, 48, 'bungee', '#F4F1E8'); });
for (let i = 1; i <= 3; i++) cell('vtr' + i, 128, 48, drawPlate('VTR ' + i, { bg: '#2E2836', fg: '#FFE14A', border: '#15101A' }));

const CELLS = {};
(function pack() {
  const order = SPECS.slice().sort((a, b) => b[2] - a[2]);
  let x = 0, y = 3 * SWS, rh = 0;
  for (const [n, w, h] of order) {
    if (x + w > AS) { x = 0; y += rh; rh = 0; }
    CELLS[n] = [x, y, w, h];
    x += w; rh = Math.max(rh, h);
  }
  if (y + rh > AS) console.warn('[props/broadcast] atlas overflow', y + rh);
})();

function atlasTex() {
  return K.tex.canvas('bc_atlas_2', AS, AS, (ctx, W, H, rand) => {
    ctx.fillStyle = '#7A7480'; ctx.fillRect(0, 0, W, H);
    for (const k in SWUV) { const [, , x, y] = SWUV[k]; ctx.fillStyle = SW[k]; ctx.fillRect(x, y, SWS, SWS); }
    for (const k in LITUV) { const [, , x, y] = LITUV[k]; ctx.fillStyle = LIT[k]; ctx.fillRect(x, y, SWS, SWS); }
    for (const [n, , , draw] of SPECS) {
      const [x, y, w, h] = CELLS[n];
      ctx.save(); ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip(); ctx.translate(x, y);
      draw(ctx, w, h, rand);
      ctx.restore();
    }
  }, { repeat: false, fonts: true });
}

// ---- UV helpers (all return new geometry)
function fillUV(geo, u, v) {
  const g = geo.clone();
  const n = g.attributes.position.count;
  const uv = new Float32Array(n * 2);
  for (let i = 0; i < n; i++) { uv[i * 2] = u; uv[i * 2 + 1] = v; }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  return g;
}
function sw(geo, name) { const s = SWUV[name]; if (!s) throw new Error(`[bc] swatch ${name}`); return fillUV(geo, s[0], s[1]); }
function lw(geo, name) { const s = LITUV[name]; if (!s) throw new Error(`[bc] lit ${name}`); return fillUV(geo, s[0], s[1]); }
function cu(geo, name, inset = 1.5) {
  const c = CELLS[name]; if (!c) throw new Error(`[bc] cell ${name}`);
  const [x, y, w, h] = c;
  const g = geo.clone();
  if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
  return K.uvRect(g, (x + inset) / AS, 1 - (y + h - inset) / AS, (x + w - inset) / AS, 1 - (y + inset) / AS);
}
// flat decal facing -z (front), w x h meters, showing an atlas cell
function decal(name, w, h) { return cu(new THREE.PlaneGeometry(w, h).rotateY(Math.PI), name); }
function discDecal(name, r, seg = 24) { return cu(new THREE.CircleGeometry(r, seg).rotateY(Math.PI), name); }

// ---- shared materials (cached by the engine per params)
function mats(game) {
  const at = atlasTex();
  return {
    pl: K.mat(game, 'plastic', '#ffffff', { map: at }),                 // paletted glossy plastic / enamel
    mt: K.mat(game, 'paint', '#ffffff', { map: at }),                   // paletted matte (rubber, crinkle paint)
    me: K.mat(game, 'metal', '#ffffff', { map: at }),                   // paletted painted metal
    lit: K.glow(game, '#ffffff', 1.7, { map: at }),                     // lit lamps / buttons / LEDs / signs
    soft: K.glow(game, '#ffffff', 0.86, { map: at }),                   // backlit meter faces / reflectors (soft bloom)
    sign: K.glow(game, '#ffffff', 1.12, { map: at }),                   // lit sign faces (letters bloom, bg stays readable)
    dim: K.mat(game, 'plastic', '#6A6068', { map: at }),                // unlit lamp (same UVs as lit: darker glossy lens)
    ch: K.mat(game, 'chrome', '#9CA4AE'),
    glass: K.mat(game, 'crt', '#232838'),
  };
}
const woodMat = (game, base = PAL.walnut) => K.mat(game, 'walnut', '#ffffff', { map: K.tex.wood(base, { dark: 0.42 }) });
const brushedMat = (game, base = '#C4CAD2') => K.mat(game, 'metal', '#ffffff', { map: K.tex.brushed(base) });

// ================================================================================================= GEOMETRY
// Chamfered keycap: top at y = h, open bottom, flat faces (18 tris). Buttons, keys, switch caps.
const _kc = new Map();
function keycap(w, d, h, c = 0.004) {
  const key = `${w}|${d}|${h}|${c}`;
  if (_kc.has(key)) return _kc.get(key);
  const hw = w / 2, hd = d / 2, iw = hw - c, id = hd - c, hc = h - c;
  const T = [[-iw, h, -id], [iw, h, -id], [iw, h, id], [-iw, h, id]];
  const S = [[-hw, hc, -hd], [hw, hc, -hd], [hw, hc, hd], [-hw, hc, hd]];
  const B = [[-hw, 0, -hd], [hw, 0, -hd], [hw, 0, hd], [-hw, 0, hd]];
  const tris = [];
  const quad = (a, b, c2, d2) => { tris.push(a, b, c2, a, c2, d2); };
  quad(T[0], T[3], T[2], T[1]); // top (+y)
  for (let i = 0; i < 4; i++) { const j = (i + 1) % 4; quad(T[i], T[j], S[j], S[i]); quad(S[i], S[j], B[j], B[i]); }
  const pos = new Float32Array(tris.length * 3);
  tris.forEach((p, i) => pos.set(p, i * 3));
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(tris.length * 2), 2));
  g.computeVertexNormals();
  _kc.set(key, g);
  return g;
}
// cheap closed cylinder, base at y = 0 (tiny parts: LEDs, screws, pins)
const lowCyl = (r, h, seg = 10, rb = r) => new THREE.CylinderGeometry(r, rb, h, seg, 1).translate(0, h / 2, 0);
const lowSphere = (r, ws = 8, hs = 6) => new THREE.SphereGeometry(r, ws, hs);
// 1-step-rounded lathe (cheaper than the kit default) and bevelled cylinder, base at y = 0
const L = (p, round = 0, seg = 16) => K.lathe(p, { round, seg, steps: 1 });
const bcyl = (rt, rb, h, bevel = 0.005, seg = 14) => L([[0, 0], [rb, 0], [rt, h], [0, h]], bevel, seg);
// Chamfered box (44 tris, flat facets), centered: small and medium hard parts.
const _cb = new Map();
function cbox(w, h, d, c = 0.004) {
  c = Math.max(1e-4, Math.min(c, w / 2 - 1e-4, h / 2 - 1e-4, d / 2 - 1e-4));
  const key = `${w}|${h}|${d}|${c}`;
  let g = _cb.get(key);
  if (!g) {
    const hx = w / 2, hy = h / 2, hz = d / 2, pts = [];
    for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) {
      pts.push(new THREE.Vector3(sx * hx, sy * (hy - c), sz * (hz - c)), new THREE.Vector3(sx * (hx - c), sy * hy, sz * (hz - c)), new THREE.Vector3(sx * (hx - c), sy * (hy - c), sz * hz));
    }
    g = new ConvexGeometry(pts);
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
    _cb.set(key, g);
  }
  return g;
}

function ring(r, n, y = 0) {
  const pts = [];
  for (let i = 0; i < n; i++) { const a = (i / n) * TAU; pts.push([Math.cos(a) * r, y, Math.sin(a) * r]); }
  return pts;
}
// rounded-rect loop in the XY plane (for trims around faces)
function rectLoopXY(w, h, r, steps = 3) { return K.roundRectPath(w, h, r, 0, steps).map(([x, , z]) => [x, z, 0]); }
// bevelled frame (ring) in the XY plane, depth along z: outer w x h, border b
function frame(w, h, b, depth, r = 0.03, ri = null, o = {}) {
  const s = K.roundRect(w, h, r);
  s.holes.push(new THREE.Path(K.roundRect(w - 2 * b, h - 2 * b, ri ?? Math.max(0.004, r - b * 0.6)).getPoints(o.holeSeg ?? (o.lite ? 2 : 4))));
  // bevel must stay well under half the border or the caps self-intersect and fill the opening
  return K.extrude(s, depth, { bevel: Math.min(o.bevel ?? 0.008, depth * 0.4, b * 0.35), bevelSeg: 1, curveSeg: o.curveSeg ?? (o.lite ? 2 : 4) });
}
// mesh oriented from a to b (for cylinders built along +y from y = 0)
function along(geo, mat, a, b) {
  const va = new THREE.Vector3(...a), vb = new THREE.Vector3(...b);
  const len = va.distanceTo(vb);
  const m = K.m(geo(len), mat);
  m.position.copy(va);
  m.quaternion.setFromUnitVectors(UP, vb.clone().sub(va).normalize());
  return m;
}
// knob: lathe body with a pointer, facing -z; returns meshes array positioned at p (face plane z)
function knob(M, r, p, o = {}) {
  const { color = 'ink', cap = null, depth = r * 0.9, skirt = true, rot = 0.6, mat = 'pl', seg = skirt ? 12 : 10, pointer = true } = o;
  const prof = skirt
    ? [[0, 0], [r * 1.2, 0], [r * 1.2, depth * 0.22], [r * 0.95, depth * 0.34], [r * 0.9, depth * 0.88], [r * 0.72, depth], [0, depth]]
    : [[0, 0], [r, 0], [r * 0.96, depth * 0.84], [r * 0.74, depth], [0, depth]];
  const out = [];
  out.push(K.m(sw(L(prof, 0, seg), color), M[mat], { pos: p, rot: [-HP, 0, 0] }));
  if (cap) out.push(K.m(sw(lowCyl(r * 0.7, 0.003, seg), cap), M.me, { pos: [p[0], p[1], p[2] - depth - 0.001], rot: [-HP, 0, 0] }));
  if (!pointer) return out;
  const ptr = K.m(sw(cbox(r * 0.22, r * 0.75, 0.004, 0.0012), 'white'), M.pl, {});
  ptr.position.set(p[0] + Math.sin(rot) * r * 0.45, p[1] + Math.cos(rot) * r * 0.45, p[2] - depth - 0.0015);
  ptr.rotation.z = -rot;
  out.push(ptr);
  return out;
}
// caster wheel assembly (swivel fork + rubber wheel), contact at y = 0; returns Group
function caster(M, r = 0.04, color = 'charcoal') {
  const c = new THREE.Group();
  c.add(K.m(sw(L([[0, -r * 0.45], [r * 0.75, -r * 0.45], [r, -r * 0.15], [r, r * 0.15], [r * 0.75, r * 0.45], [0, r * 0.45]], 0, 12), 'rubber'), M.mt, { pos: [0, r, 0], rot: [0, 0, HP] }));
  c.add(K.m(sw(cbox(r * 1.35, r * 0.28, r * 1.05, r * 0.1), color), M.pl, { pos: [0, r * 1.95, -r * 0.12] }));
  for (const s of [-1, 1]) c.add(K.m(sw(cbox(r * 0.2, r * 1.25, r * 0.85, r * 0.07), color), M.pl, { pos: [s * r * 0.6, r * 1.35, -r * 0.15] }));
  c.add(K.m(sw(lowCyl(r * 0.3, r * 0.6, 8), 'silver'), M.pl, { pos: [0, r * 2, 0] }));
  return c;
}
// telescoping rabbit ears (V antenna) on a swivel ball; returns Group (noMerge part)
function rabbitEars(M, len = 0.5, spread = 0.55, lean = 0.2) {
  const ant = new THREE.Group();
  ant.userData.noMerge = true;
  ant.add(K.m(sw(L([[0, 0], [0.045, 0], [0.046, 0.012], [0.03, 0.03], [0.012, 0.04], [0, 0.042]], 0, 12), 'ink'), M.pl));
  for (const s of [-1, 1]) {
    const dir = new THREE.Vector3(s * spread, 1, lean).normalize();
    const segs = [[0.0055, len * 0.38], [0.0042, len * 0.34], [0.003, len * 0.32]];
    let d = 0.03;
    for (const [r, l] of segs) {
      const rod = K.m(lowCyl(r, l, 6), M.ch);
      rod.position.copy(dir).multiplyScalar(d).add(new THREE.Vector3(0, 0.02, 0));
      rod.quaternion.setFromUnitVectors(UP, dir);
      ant.add(rod);
      d += l - 0.008;
    }
    ant.add(K.m(lowSphere(0.009, 6, 4), M.ch, { pos: dir.clone().multiplyScalar(d + 0.004).add(new THREE.Vector3(0, 0.02, 0)).toArray() }));
  }
  return ant;
}

// CRT screen (engine CRT material, preview card; ScreenManager owns it in game). Faces -z, domed.
// Cheaper than K.screen (8x6 grid by default). o: { card, group, id, dome, bright, seg:[x,y] }
function scr(game, w, h, o = {}) {
  const [sx, sy] = o.seg ?? [8, 6];
  const dome = o.dome ?? Math.min(w, h) * 0.05;
  const g = new THREE.PlaneGeometry(w, h, sx, sy);
  const pos = g.attributes.position;
  for (let i = 0; i < pos.count; i++) {
    const x = (pos.getX(i) / w) * 2, y = (pos.getY(i) / h) * 2;
    pos.setZ(i, dome * (1 - x * x * 0.5 - y * y * 0.5));
  }
  g.computeVertexNormals();
  g.rotateY(Math.PI);
  const card = o.card === null ? null : getCard(o.card ?? 'station_id');
  const mt = game.mats.screen(card, { w, h, bulge: 0, bright: o.bright ?? 0.85 });
  const mesh = new THREE.Mesh(g, mt);
  mesh.name = 'screen';
  mesh.userData.noMerge = true;
  mesh.userData.screenGroup = o.group ?? 'scr_decor';
  if (o.id) mesh.userData.screenId = o.id;
  mesh.castShadow = false;
  return mesh;
}
// finish + per-group merges for animated parts + screen ids + stats
const PROFILE = typeof location !== 'undefined' && /bcprof=1/.test(location.search);
function done(game, g, o = {}) {
  if (PROFILE) {
    const rows = [];
    g.updateMatrixWorld(true);
    g.traverse((m) => {
      if (!m.isMesh) return;
      const gg = m.geometry, t = (gg.index ? gg.index.count : gg.attributes.position.count) / 3;
      const p = new THREE.Vector3().setFromMatrixPosition(m.matrixWorld);
      rows.push([t, gg.type, p.toArray().map((v) => v.toFixed(2)).join(',')]);
    });
    rows.sort((a, b) => b[0] - a[0]);
    const tot = rows.reduce((a, r) => a + r[0], 0);
    console.log(`[bcprof] ${g.userData.id} total ${tot} in ${rows.length} meshes :: ` + rows.slice(0, 30).map((r) => `${r[0]} ${r[1]} @${r[2]}`).join(' | '));
  }
  K.finish(game, g, o.finish || {});
  for (const p of o.mergeParts || []) if (p) K.merge(p);
  for (const s of g.userData.screens) if (s.mesh.userData.screenId) s.id = s.mesh.userData.screenId;
  // every mesh keeps a color attribute so lamps can swap lit <-> dim (vertexColors) materials at runtime
  g.traverse((o) => {
    if (o.isMesh && !o.geometry.attributes.color && o.material.type !== 'ShaderMaterial') {
      o.geometry = o.geometry.clone();
      o.geometry.setAttribute('color', new THREE.BufferAttribute(new Float32Array(o.geometry.attributes.position.count * 3).fill(1), 3));
    }
  });
  g.userData.stats = K.stats(g);
  return g;
}

// A standalone CRT monitor unit (metal case, face plate, bevelled bezel, screen, control strip). Group, base at
// y = 0, centered, front -z. Returns { group, screen, h, d }.
// o: { w, h, d, case, face, bezel, screen:[sw,sh], sy (screen center offset y), card, group, id, knobs=4, ears,
//      handles, plate, tally, tilt }
function monitorUnit(game, M, o = {}) {
  const w = o.w ?? 0.48, h = o.h ?? 0.38, d = o.d ?? 0.42;
  const caseC = o.case ?? 'charcoal', faceC = o.face ?? 'putty', bezC = o.bezel ?? 'ink';
  const grp = new THREE.Group();
  const fz = -d / 2;
  grp.add(K.m(sw(K.box(w, h, d * 0.62, Math.min(0.035, h * 0.12)), caseC), M.pl, { pos: [0, h / 2, fz + d * 0.31] }));
  grp.add(K.m(sw(K.taper(K.box(w * 0.86, h * 0.84, d * 0.42, 0.035), { axis: 'z', k: 0.62 }), caseC), M.pl, { pos: [0, h / 2 + 0.005, fz + d * 0.62 + d * 0.19 - 0.01] }));
  // face plate
  grp.add(K.m(sw(K.box(w - 0.014, h - 0.014, 0.024, Math.min(0.028, h * 0.1)), faceC), M.pl, { pos: [0, h / 2, fz - 0.004] }));
  const [sW, sH] = o.screen ?? [w * 0.7, h * 0.64];
  const sy = h / 2 + (o.sy ?? h * 0.07);
  const b = Math.min(0.03, sW * 0.08);
  grp.add(K.m(sw(frame(sW + b * 2, sH + b * 2, b, 0.026, Math.min(sW, sH) * 0.14), bezC), M.pl, { pos: [0, sy, fz - 0.018] }));
  const screen = scr(game, sW, sH, { card: o.card, group: o.group, id: o.id, dome: Math.min(sW, sH) * 0.05 });
  screen.position.set(0, sy, fz - 0.012);
  grp.add(screen);
  // control strip
  const stripY = (sy - sH / 2 - b) / 2 + 0.004;
  const nk = o.knobs ?? 4;
  const kr = Math.min(0.014, (sy - sH / 2 - b) * 0.32);
  for (let i = 0; i < nk; i++) {
    const kx = w * 0.12 + i * kr * 3.2;
    for (const mm of knob(M, kr, [kx, stripY, fz - 0.016], { color: 'ink', depth: kr * 0.9, skirt: false, rot: 0.4 + i, seg: 8, pointer: kr > 0.013 })) grp.add(mm);
  }
  if (o.plate !== false) grp.add(K.m(decal(o.plate ?? 'pl_KINETRON', Math.min(w * 0.3, 0.16), Math.min(w * 0.3, 0.16) * 0.19), M.pl, { pos: [-w * 0.24, stripY, fz - 0.0175] }));
  if (o.tally !== false) grp.add(K.m(lw(lowCyl(0.006, 0.006, 8), o.tallyColor ?? 'red'), M.lit, { pos: [-w / 2 + 0.035, stripY, fz - 0.016], rot: [-HP, 0, 0] }));
  if (o.ears) {
    for (const s of [-1, 1]) {
      grp.add(K.m(sw(cbox(0.03, h, 0.006, 0.002), faceC), M.pl, { pos: [s * (w / 2 + 0.012), h / 2, fz - 0.002] }));
      for (const yy of [0.2, 0.8]) grp.add(K.m(sw(new THREE.PlaneGeometry(0.012, 0.006).rotateY(Math.PI), 'ink'), M.pl, { pos: [s * (w / 2 + 0.014), h * yy, fz - 0.0055] }));
    }
  }
  if (o.handles) {
    for (const s of [-1, 1]) {
      const x = s * (w / 2 - 0.02);
      grp.add(K.m(K.tube([[x, h * 0.18, fz - 0.01], [x, h * 0.18, fz - 0.045], [x, h * 0.82, fz - 0.045], [x, h * 0.82, fz - 0.01]], 0.0065, { seg: 10, radial: 5 }), M.ch));
    }
  }
  // top vents
  grp.add(K.m(cu(new THREE.PlaneGeometry(w * 0.5, d * 0.3).rotateX(-HP), 'vent'), M.pl, { pos: [0, h + 0.001, fz + d * 0.3] }));
  return { group: grp, screen, h, d };
}

// ================================================================================================= PROPS
// ---------------------------------------------------------------------------------- pedestal studio camera
registerProp('bc_pedestal_camera', (game, opts = {}) => {
  const g = K.prop('bc_pedestal_camera');
  const M = mats(game);
  const bodyC = opts.color ?? 'cream', accC = opts.accent ?? 'wztvBlue', pedC = opts.pedestal ?? 'slate';
  const tallyOn = opts.tally !== false;
  // --- dolly base: rounded triangle, central skirt, domed caster pods with rubber bumpers
  const tri = [];
  for (let i = 0; i < 3; i++) { const a = (i / 3) * TAU - HP; tri.push([Math.cos(a) * 0.52, Math.sin(a) * 0.52]); }
  g.add(K.m(sw(K.extrude(tri, 0.08, { bevel: 0.026, round: 0.22, curveSeg: 4, bevelSeg: 1 }).rotateX(-HP), pedC), M.pl, { pos: [0, 0.14, 0] }));
  g.add(K.m(sw(L([[0, 0], [0.3, 0], [0.28, 0.04], [0.19, 0.08], [0.15, 0.1], [0, 0.1]], 0.02, 18), pedC), M.pl, { pos: [0, 0.17, 0] }));
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU - HP;
    const x = Math.cos(a) * 0.4, z = -Math.sin(a) * 0.4;
    g.add(K.m(sw(L([[0, 0], [0.095, 0], [0.1, 0.03], [0.08, 0.075], [0, 0.085]], 0.015, 12), pedC), M.pl, { pos: [x, 0.09, z] }));
    g.add(K.m(sw(L([[0.088, 0], [0.104, 0], [0.104, 0.03], [0.088, 0.03]], 0, 12), 'rubber'), M.mt, { pos: [x, 0.065, z] }));
    const c = caster(M, 0.036);
    c.position.set(x, 0, z); c.rotation.y = a;
    g.add(c);
  }
  // --- column: flared lower column, rubber bellows, chrome upper column, steering ring
  g.add(K.m(sw(L([[0, 0], [0.15, 0], [0.15, 0.03], [0.12, 0.07], [0.11, 0.12], [0.108, 0.48], [0.125, 0.5], [0.125, 0.54], [0, 0.54]], 0.012, 18), pedC), M.pl, { pos: [0, 0.22, 0] }));
  const bel = [[0, 0]];
  for (let i = 0; i < 4; i++) bel.push([0.098, i * 0.022 + 0.002], [0.112, i * 0.022 + 0.011]);
  bel.push([0.098, 0.09], [0, 0.09]);
  g.add(K.m(sw(L(bel, 0, 16), 'rubber'), M.mt, { pos: [0, 0.76, 0] }));
  g.add(K.m(bcyl(0.075, 0.075, 0.2, 0.006, 16), M.ch, { pos: [0, 0.84, 0] }));
  g.add(K.m(sw(L([[0, 0], [0.1, 0], [0.105, 0.02], [0.1, 0.05], [0, 0.05]], 0.01, 16), pedC), M.pl, { pos: [0, 0.875, 0] }));
  g.add(K.m(sw(K.tube(ring(0.34, 24, 0), 0.026, { seg: 30, radial: 7, closed: true }), 'rubber'), M.mt, { pos: [0, 0.905, 0] }));
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.5;
    g.add(K.m(K.tube([[Math.cos(a) * 0.09, 0.9, Math.sin(a) * 0.09], [Math.cos(a) * 0.22, 0.905, Math.sin(a) * 0.22], [Math.cos(a) * 0.33, 0.905, Math.sin(a) * 0.33]], 0.013, { seg: 5, radial: 6 }), M.ch));
  }
  // --- headset hook + hanging headset (coiled cord) on the column's right side
  const hx = 0.23, hy = 0.66;
  g.add(K.m(K.tube([[0.1, hy - 0.02, 0], [0.19, hy - 0.02, 0], [hx, hy, 0], [hx + 0.005, hy + 0.05, 0]], 0.008, { seg: 8, radial: 5 }), M.ch));
  g.add(K.m(sw(K.tube([[hx, hy - 0.15, -0.105], [hx, hy - 0.05, -0.095], [hx, hy + 0.012, -0.04], [hx, hy + 0.02, 0], [hx, hy + 0.012, 0.04], [hx, hy - 0.05, 0.095], [hx, hy - 0.15, 0.105]], 0.011, { seg: 16, radial: 6 }), 'ink'), M.pl));
  for (const s of [-1, 1]) {
    g.add(K.m(sw(L([[0, 0], [0.052, 0], [0.056, 0.014], [0.048, 0.04], [0, 0.042]], 0.008, 12), 'ink'), M.pl, { pos: [hx, hy - 0.18, s * 0.085], rot: [s * HP, 0, 0] }));
    g.add(K.m(sw(L([[0, 0], [0.046, 0], [0.05, 0.01], [0.036, 0.022], [0, 0.022]], 0.006, 12), 'orange'), M.mt, { pos: [hx, hy - 0.18, s * 0.085], rot: [-s * HP, 0, 0] }));
  }
  g.add(K.m(sw(K.tube([[hx + 0.01, hy - 0.2, -0.12], [hx + 0.05, hy - 0.25, -0.18], [hx + 0.04, hy - 0.3, -0.24]], 0.006, { seg: 8, radial: 5 }), 'ink'), M.pl));
  g.add(K.m(sw(lowSphere(0.02, 10, 7), 'rubber'), M.mt, { pos: [hx + 0.04, hy - 0.305, -0.245] }));
  const coil = [];
  for (let i = 0; i <= 36; i++) { const t = i / 36, a = t * TAU * 5; coil.push([hx + Math.cos(a) * 0.014, hy - 0.23 - t * 0.2, 0.12 + Math.sin(a) * 0.014]); }
  coil.push([0.16, 0.34, 0.1], [0.12, 0.3, 0.06]);
  g.add(K.m(sw(K.tube(coil, 0.004, { seg: 40, radial: 4 }), 'ink'), M.pl));

  // --- pan head (part 'head') + tilt cradle (part 'tilt') carrying the camera
  const head = new THREE.Group();
  head.position.set(0, 1.04, 0);
  head.userData.noMerge = true;
  g.add(head);
  head.add(K.m(sw(L([[0, 0], [0.13, 0], [0.14, 0.025], [0.115, 0.065], [0, 0.065]], 0.012, 16), 'charcoal'), M.pl));
  for (const s of [-1, 1]) head.add(K.m(sw(cbox(0.055, 0.14, 0.24, 0.016), 'charcoal'), M.pl, { pos: [s * 0.13, 0.11, 0] }));
  head.add(K.m(sw(cbox(0.22, 0.05, 0.18, 0.014), 'charcoal'), M.pl, { pos: [0, 0.08, 0] }));
  for (const s of [-1, 1]) head.add(K.m(bcyl(0.034, 0.034, 0.02, 0.006, 12), M.ch, { pos: [s * 0.158, 0.15, 0], rot: [0, 0, -s * HP] }));
  const tilt = new THREE.Group();
  tilt.position.set(0, 0.15, 0);
  tilt.userData.noMerge = true;
  head.add(tilt);
  const bw = 0.42, bh = 0.4, bd = 0.7;
  const by = 0.035 + bh / 2 + 0.01, bz = 0.03; // body center (tilt space)
  tilt.add(K.m(sw(cbox(0.3, 0.04, 0.56, 0.012), 'charcoal'), M.pl, { pos: [0, 0.035, 0.02] }));
  tilt.add(K.m(sw(K.box(bw, bh, bd, 0.085), bodyC), M.pl, { pos: [0, by, bz] }));
  // accent side panels with the 13 disc + nameplate + vent grilles
  for (const s of [-1, 1]) {
    const pan = K.m(sw(K.extrude(K.roundRect(0.54, 0.25, 0.075), 0.026, { bevel: 0.009, curveSeg: 4, bevelSeg: 1 }), accC), M.pl);
    pan.position.set(s * (bw / 2 + 0.002), by - 0.02, bz + 0.03); pan.rotation.y = s * HP;
    tilt.add(pan);
    const logo = K.m(discDecal('logo13', 0.085, 28), M.pl);
    logo.position.set(s * (bw / 2 + 0.0155), by - 0.01, bz - 0.12); logo.rotation.y = -s * HP;
    tilt.add(logo);
    const plate = K.m(decal('pl_VIDICAM', 0.22, 0.041), M.pl);
    plate.position.set(s * (bw / 2 + 0.0155), by - 0.095, bz + 0.1); plate.rotation.y = -s * HP;
    tilt.add(plate);
    const vent = K.m(decal('vent', 0.12, 0.12), M.pl);
    vent.position.set(s * (bw / 2 + 0.0155), by + 0.01, bz + 0.19); vent.rotation.y = -s * HP;
    tilt.add(vent);
  }
  // lens turret + big zoom lens (axis -z) + flared matte-box sunshade
  const fz = bz - bd / 2;
  tilt.add(K.m(sw(K.box(0.34, 0.33, 0.07, 0.045), 'charcoal'), M.pl, { pos: [0, by - 0.005, fz - 0.015] }));
  const lz = fz - 0.05;
  tilt.add(K.m(sw(L([[0, 0], [0.105, 0], [0.105, 0.03], [0.092, 0.036], [0.092, 0.24], [0, 0.24]], 0.008, 18), 'ink'), M.pl, { pos: [0, by, lz], rot: [-HP, 0, 0] }));
  const knurl = (r0, len, n = 6) => { const p = [[0, 0]]; for (let i = 0; i <= n; i++) p.push([r0 + (i % 2 ? 0.009 : 0.002), (i / n) * len]); p.push([0, len]); return p; };
  tilt.add(K.m(sw(L(knurl(0.093, 0.065), 0, 16), 'rubber'), M.mt, { pos: [0, by, lz - 0.05], rot: [-HP, 0, 0] }));
  tilt.add(K.m(sw(L(knurl(0.093, 0.05, 4), 0, 16), 'rubber'), M.mt, { pos: [0, by, lz - 0.15], rot: [-HP, 0, 0] }));
  tilt.add(K.m(L([[0.094, 0], [0.101, 0], [0.101, 0.014], [0.094, 0.014]], 0, 18), M.ch, { pos: [0, by, lz - 0.032], rot: [-HP, 0, 0] }));
  tilt.add(K.m(L([[0.094, 0], [0.101, 0], [0.101, 0.012], [0.094, 0.012]], 0, 18), M.ch, { pos: [0, by, lz - 0.215], rot: [-HP, 0, 0] }));
  tilt.add(K.m(new THREE.CircleGeometry(0.094, 20).rotateY(Math.PI), M.glass, { pos: [0, by, lz - 0.236] }));
  const shade = K.taper(frame(0.25, 0.21, 0.02, 0.13, 0.05, 0.035, { bevel: 0.008 }), { axis: 'z', k: 0.72 });
  tilt.add(K.m(sw(shade, 'rubber'), M.mt, { pos: [0, by, lz - 0.3] }));
  tilt.add(K.m(sw(cbox(0.06, 0.09, 0.17, 0.016), 'charcoal'), M.pl, { pos: [0.12, by - 0.02, lz - 0.1] }));
  tilt.add(K.m(sw(cbox(0.034, 0.034, 0.034, 0.008), 'red'), M.pl, { pos: [0.155, by + 0.01, lz - 0.12] }));
  // viewfinder (flush on the body) with rubber hood + camera number, tally dome up front
  const vh = 0.21, vy = by + bh / 2 + vh / 2 - 0.02, vz = bz + 0.08;
  tilt.add(K.m(sw(K.box(0.36, vh, 0.4, 0.06), bodyC), M.pl, { pos: [0, vy, vz] }));
  tilt.add(K.m(sw(K.box(0.366, 0.055, 0.36, 0.022, { seg: 1 }), accC), M.pl, { pos: [0, vy - 0.05, vz + 0.01] }));
  tilt.add(K.m(sw(K.taper(frame(0.3, 0.2, 0.032, 0.16, 0.055, 0.03, { bevel: 0.01 }), { axis: 'z', k: 1.12 }), 'rubber'), M.mt, { pos: [0, vy + 0.005, vz + 0.26] }));
  tilt.add(K.m(sw(new THREE.PlaneGeometry(0.24, 0.14), 'black'), M.mt, { pos: [0, vy + 0.005, vz + 0.2] }));
  tilt.add(K.m(decal('num' + (opts.num ?? 1), 0.1, 0.1), M.pl, { pos: [0.1, vy + 0.012, vz - 0.2015] }));
  tilt.add(K.m(decal('vent', 0.1, 0.07), M.pl, { pos: [-0.1, vy + 0.012, vz - 0.2015] }));
  tilt.add(K.m(L([[0, 0], [0.06, 0], [0.063, 0.014], [0.056, 0.024], [0, 0.024]], 0.005, 16), M.ch, { pos: [0, vy + vh / 2 - 0.004, vz - 0.12] }));
  const onMat = M.lit, offMat = M.dim;
  const tallyGeo = lw(L([[0, 0], [0.052, 0], [0.052, 0.014], [0.045, 0.042], [0.026, 0.064], [0, 0.069]], 0.012, 16), 'red');
  const tally = K.m(tallyGeo, tallyOn ? onMat : offMat, { pos: [0, vy + vh / 2 + 0.018, vz - 0.12], name: 'tally' });
  tally.userData.noMerge = true;
  tilt.add(tally);
  // carry handle along the viewfinder top
  tilt.add(K.m(K.tube([[0, vy + vh / 2 - 0.01, vz + 0.02], [0, vy + vh / 2 + 0.05, vz + 0.05], [0, vy + vh / 2 + 0.05, vz + 0.14], [0, vy + vh / 2 - 0.01, vz + 0.17]], 0.012, { seg: 12, radial: 6 }), M.ch));
  // pan bars with rubber grips, zoom rocker (right) and focus crank (left)
  for (const s of [-1, 1]) {
    const pts = [[s * 0.11, 0.05, 0.25], [s * 0.18, 0.02, 0.44], [s * 0.25, -0.04, 0.62], [s * 0.29, -0.08, 0.76]];
    tilt.add(K.m(K.tube(pts, 0.016, { seg: 12, radial: 7 }), M.ch));
    tilt.add(K.m(sw(K.tube([[s * 0.245, -0.035, 0.6], [s * 0.27, -0.06, 0.69], [s * 0.293, -0.085, 0.78]], 0.027, { seg: 6, radial: 9 }), 'rubber'), M.mt));
    tilt.add(K.m(sw(lowSphere(0.029, 10, 7), 'rubber'), M.mt, { pos: [s * 0.296, -0.088, 0.79] }));
  }
  tilt.add(K.m(sw(cbox(0.055, 0.04, 0.08, 0.012), 'charcoal'), M.pl, { pos: [0.205, 0.0, 0.5] }));
  tilt.add(K.m(sw(cbox(0.024, 0.02, 0.045, 0.006), 'red'), M.pl, { pos: [0.205, 0.027, 0.5] }));
  tilt.add(K.m(sw(bcyl(0.045, 0.045, 0.02, 0.005, 14), 'charcoal'), M.pl, { pos: [-0.215, 0.0, 0.5], rot: [0, 0, HP] }));
  tilt.add(K.m(sw(lowCyl(0.009, 0.055, 8), 'rubber'), M.mt, { pos: [-0.235, 0.03, 0.5], rot: [0, 0, HP] }));
  // camera cable: back connector, down behind the pedestal, trailing on the floor
  tilt.add(K.m(bcyl(0.032, 0.032, 0.05, 0.006, 12), M.ch, { pos: [0.09, by - 0.07, bz + bd / 2 - 0.005], rot: [HP, 0, 0] }));
  g.add(K.m(sw(K.tube([[0.09, 1.28, 0.44], [0.11, 1.18, 0.54], [0.18, 0.8, 0.56], [0.22, 0.3, 0.56], [0.25, 0.04, 0.62], [0.34, 0.02, 0.76], [0.52, 0.02, 0.82]], 0.019, { seg: 26, radial: 6 }), 'ink'), M.pl));
  const lensTip = new THREE.Object3D();
  lensTip.name = 'lensTip';
  lensTip.position.set(0, by, lz - 0.37);
  tilt.add(lensTip);

  g.userData.parts = { head, tilt, tally, lensTip };
  g.userData.lampMats = { on: onMat, off: offMat };
  g.userData.colliders = [{ min: [-0.46, 0, -0.44], max: [0.46, 1.0, 0.5] }, { min: [-0.26, 1.0, -0.78], max: [0.26, 1.86, 0.85] }];
  return done(game, g, { mergeParts: [head, tilt] });
}, { category: 'broadcast', tags: ['camera', 'studio', 'feed_cam', 'hero'], size: [1.05, 1.86, 1.6], hero: true,
  desc: 'boxy 70s pedestal studio camera: tally dome, zoom lens + matte box, pan bars, headset on hook. parts head/tilt/tally/lensTip (lampMats on/off); opts {num 1-4, tally, color, accent, pedestal}' });

// ---------------------------------------------------------------------------------- 13" portable TV
registerProp('bc_tv_portable', (game, opts = {}) => {
  const g = K.prop('bc_tv_portable');
  const M = mats(game);
  const shellC = opts.color ?? 'red';
  const W = 0.44, H = 0.35, D = 0.25, foot = 0.03;
  const cy = foot + H / 2, fz = -D / 2 - 0.02;
  g.add(K.m(sw(K.box(W, H, D, 0.075, { seg: 2 }), shellC), M.pl, { pos: [0, cy, -0.02] }));
  g.add(K.m(sw(K.taper(K.box(W * 0.8, H * 0.78, 0.2, 0.045), { axis: 'z', k: 0.58, ease: 0.8 }), shellC), M.pl, { pos: [0, cy + 0.01, D / 2 + 0.06] }));
  for (let i = 0; i < 5; i++) g.add(K.m(sw(cbox(0.012, 0.08, 0.01, 0.004), 'ink'), M.pl, { pos: [-0.05 + i * 0.025, cy + 0.02, D / 2 + 0.16] }));
  // visor brow + cream face + chrome trim loop
  g.add(K.m(sw(K.box(W + 0.012, 0.04, 0.07, 0.02, { seg: 1 }), shellC), M.pl, { pos: [0, foot + H - 0.012, fz + 0.01] }));
  g.add(K.m(sw(K.box(W - 0.03, H - 0.05, 0.02, 0.045), 'capWhite'), M.pl, { pos: [0, cy - 0.01, fz + 0.006] }));
  g.add(K.m(K.tube(rectLoopXY(W - 0.022, H - 0.042, 0.05, 2), 0.005, { seg: 28, radial: 4, closed: true }), M.ch, { pos: [0, cy - 0.01, fz - 0.003] }));
  const sx = -0.06, sW = 0.27, sH = 0.21, sy = cy - 0.01;
  g.add(K.m(sw(frame(sW + 0.05, sH + 0.05, 0.028, 0.03, 0.06, 0.045, { curveSeg: 3, holeSeg: 3 }), 'ink'), M.pl, { pos: [sx, sy, fz - 0.008] }));
  const screen = scr(game, sW, sH, { card: opts.card ?? 'show_7', group: opts.group, dome: 0.014 });
  screen.position.set(sx, sy, fz - 0.002);
  g.add(screen);
  // control column: VHF + UHF dials, grille, power knob, nameplate
  const cx = 0.155;
  g.add(K.m(discDecal('dialCh', 0.047), M.pl, { pos: [cx, cy + 0.07, fz - 0.0045] }));
  for (const mm of knob(M, 0.026, [cx, cy + 0.07, fz - 0.005], { color: 'ink', rot: 0.9 })) g.add(mm);
  g.add(K.m(discDecal('dialUhf', 0.036), M.pl, { pos: [cx, cy - 0.025, fz - 0.0045] }));
  for (const mm of knob(M, 0.02, [cx, cy - 0.025, fz - 0.005], { color: 'silver', mat: 'me', rot: -0.7 })) g.add(mm);
  g.add(K.m(cu(cbox(0.075, 0.06, 0.008, 0.003), 'grille'), M.pl, { pos: [cx, cy - 0.105, fz - 0.002] }));
  g.add(K.m(decal('pl_ZENOLUX', 0.12, 0.0225), M.pl, { pos: [sx, cy - 0.145, fz - 0.0045] }));
  // top: fold-down chrome handle, rabbit ears (part 'antenna')
  const top = foot + H;
  for (const s of [-1, 1]) g.add(K.m(sw(bcyl(0.02, 0.022, 0.016, 0.005, 10), 'ink'), M.pl, { pos: [s * (W / 2 - 0.004), top - 0.055, 0.0], rot: [0, 0, -s * HP] }));
  const hx = W / 2 + 0.012;
  g.add(K.m(K.tube([[-hx, top - 0.055, 0], [-hx, top - 0.01, -0.03], [-W / 2 + 0.03, top + 0.012, -0.07], [-0.12, top + 0.016, -0.08], [0.12, top + 0.016, -0.08], [W / 2 - 0.03, top + 0.012, -0.07], [hx, top - 0.01, -0.03], [hx, top - 0.055, 0]], 0.008, { seg: 18, radial: 5 }), M.ch));
  const ant = rabbitEars(M, 0.46, 0.6, 0.25);
  ant.position.set(0.03, top - 0.005, 0.06);
  g.add(ant);
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(K.m(sw(bcyl(0.02, 0.024, foot, 0.006, 8), 'rubber'), M.mt, { pos: [x * (W / 2 - 0.06), 0, z * (D / 2 - 0.04)] }));
  g.userData.parts = { antenna: ant };
  g.userData.colliders = [{ min: [-W / 2, 0, fz], max: [W / 2, top + 0.03, D / 2 + 0.17] }];
  g.userData.interact = { point: [0, cy, fz - 0.05], radius: 1.2 };
  return done(game, g);
}, { category: 'broadcast', tags: ['tv', 'crt', 'screen', 'portable'], size: [0.47, 0.8, 0.45], desc: '13" portable TV, red shell, visor brow, VHF/UHF dials, rabbit ears. opts {color, card, group}' });

// ---------------------------------------------------------------------------------- 19" walnut TV set
registerProp('bc_tv_19', (game, opts = {}) => {
  const g = K.prop('bc_tv_19');
  const M = mats(game);
  const wood = woodMat(game);
  const legs = opts.legs ?? 'splay';
  const legH = legs === 'none' ? 0 : 0.3;
  const W = 0.7, H = 0.52, D = 0.44;
  const y0 = legH, cy = y0 + H / 2, fz = -D / 2;
  g.add(K.m(K.box(W, H, D, 0.04, { uv: 1.4 }), wood, { pos: [0, cy, 0] }));
  g.add(K.m(sw(K.taper(K.box(W * 0.74, H * 0.74, 0.18, 0.05), { axis: 'z', k: 0.6 }), 'chocolate'), M.pl, { pos: [0, cy + 0.01, D / 2 + 0.08] }));
  // recessed silver face panel with chrome trim
  g.add(K.m(sw(K.box(W - 0.07, H - 0.07, 0.03, 0.025), 'silver'), M.me, { pos: [0, cy, fz - 0.002] }));
  g.add(K.m(K.tube(rectLoopXY(W - 0.058, H - 0.058, 0.03, 2), 0.006, { seg: 28, radial: 4, closed: true }), M.ch, { pos: [0, cy, fz - 0.012] }));
  const sx = -0.075, sW = 0.44, sH = 0.34;
  g.add(K.m(sw(frame(sW + 0.05, sH + 0.05, 0.028, 0.03, 0.07, 0.05, { curveSeg: 3, holeSeg: 3 }), 'ink'), M.pl, { pos: [sx, cy, fz - 0.02] }));
  const screen = scr(game, sW, sH, { card: opts.card ?? 'show_4', group: opts.group, dome: 0.02 });
  screen.position.set(sx, cy, fz - 0.014);
  g.add(screen);
  const cx = 0.235;
  g.add(K.m(discDecal('dialCh', 0.05), M.pl, { pos: [cx, cy + 0.14, fz - 0.018] }));
  for (const mm of knob(M, 0.03, [cx, cy + 0.14, fz - 0.018], { color: 'walnut', cap: 'silver', rot: 1.3 })) g.add(mm);
  g.add(K.m(discDecal('dialUhf', 0.04), M.pl, { pos: [cx, cy + 0.035, fz - 0.018] }));
  for (const mm of knob(M, 0.022, [cx, cy + 0.035, fz - 0.018], { color: 'walnut', cap: 'silver', rot: -0.5 })) g.add(mm);
  for (let i = 0; i < 3; i++) g.add(K.m(sw(keycap(0.034, 0.02, 0.012, 0.003), i === 0 ? 'gold' : 'ivory'), M.pl, { pos: [cx - 0.04 + i * 0.04, cy - 0.04, fz - 0.017], rot: [-HP, 0, 0] }));
  g.add(K.m(cu(K.box(0.13, 0.12, 0.01, 0.006), 'fabric'), M.mt, { pos: [cx, cy - 0.14, fz - 0.017] }));
  g.add(K.m(decal('pl_ZENOLUX', 0.12, 0.0225), M.pl, { pos: [sx, cy - 0.215, fz - 0.018] }));
  if (legs === 'splay') {
    for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
      const top = [x * (W / 2 - 0.08), y0 + 0.01, z * (D / 2 - 0.07)];
      const foot = [x * (W / 2 - 0.02), 0.03, z * (D / 2 - 0.01)];
      g.add(along((l) => K.uvScale(bcyl(0.022, 0.014, l, 0.006, 8).clone(), 1, 2), wood, foot, top));
      g.add(K.m(sw(bcyl(0.015, 0.017, 0.035, 0.004, 8), 'brass'), M.me, { pos: [foot[0], 0, foot[2]] }));
    }
    g.add(K.m(K.box(W - 0.1, 0.035, D - 0.1, 0.012, { uv: 1.4 }), wood, { pos: [0, y0 - 0.005, 0] }));
  } else if (legs === 'swivel') {
    g.add(K.m(sw(K.lathe([[0, 0], [0.24, 0], [0.25, 0.02], [0.2, 0.04], [0.06, 0.06], [0.045, 0.1], [0.045, legH - 0.04], [0.14, legH - 0.02], [0.14, legH], [0, legH]], { round: 0.01, seg: 24 }), 'silver'), M.ch));
  }
  if (opts.ears) { const ant = rabbitEars(M, 0.5, 0.55, 0.2); ant.position.set(0.1, y0 + H - 0.005, 0.05); g.add(ant); g.userData.parts = { antenna: ant }; }
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2 - 0.03], max: [W / 2, y0 + H, D / 2 + 0.17] }];
  g.userData.interact = { point: [0, cy, fz - 0.05], radius: 1.3 };
  return done(game, g);
}, { category: 'broadcast', tags: ['tv', 'crt', 'screen', 'walnut'], size: [0.72, 0.82, 0.64], desc: '19" walnut TV on splayed legs, silver face, dials, speaker cloth. opts {legs:splay|swivel|none, ears, card, group}' });

// ---------------------------------------------------------------------------------- rack monitor
registerProp('bc_rack_monitor', (game, opts = {}) => {
  const g = K.prop('bc_rack_monitor');
  const M = mats(game);
  const s = (opts.size ?? 14) / 14;
  const u = monitorUnit(game, M, { w: 0.48 * s, h: 0.37 * s, d: 0.44 * s, card: opts.card ?? 'color_bars', group: opts.group, id: opts.id,
    ears: true, handles: true, case: opts.case ?? 'charcoal', face: opts.face ?? 'putty', knobs: 4 });
  g.add(u.group);
  g.userData.colliders = [{ min: [-0.26 * s, 0, -0.27 * s], max: [0.26 * s, 0.37 * s, 0.24 * s] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['monitor', 'crt', 'screen', 'master_control'], size: [0.53, 0.37, 0.48], desc: 'broadcast rack monitor: rack ears, chrome handles, knob strip, tally LED. opts {size:9|14, card, group, id, case, face}' });

// ---------------------------------------------------------------------------------- stacked monitor bank
registerProp('bc_monitor_bank', (game, opts = {}) => {
  const g = K.prop('bc_monitor_bank');
  const M = mats(game);
  const wood = woodMat(game);
  const W = 1.5, CH = 0.66, D = 0.56;
  // base cabinet: walnut cheeks, charcoal front with vent + plate, kick recess
  for (const sx of [-1, 1]) g.add(K.m(K.box(0.05, CH, D, 0.018, { uv: 1.5, swap: true }), wood, { pos: [sx * (W / 2 - 0.025), CH / 2, 0] }));
  g.add(K.m(sw(K.box(W - 0.1, CH - 0.08, D - 0.03, 0.02), 'charcoal'), M.pl, { pos: [0, CH / 2 + 0.04, 0.01] }));
  g.add(K.m(sw(cbox(W - 0.14, 0.07, D - 0.1, 0.008), 'black'), M.pl, { pos: [0, 0.035, 0.03] }));
  g.add(K.m(K.box(W + 0.02, 0.035, D + 0.02, 0.014, { uv: 1.4 }), wood, { pos: [0, CH + 0.0175, 0] }));
  for (const sx of [-0.4, 0.4]) g.add(K.m(decal('vent', 0.3, 0.26), M.pl, { pos: [sx, CH / 2 + 0.03, -D / 2 + 0.004] }));
  g.add(K.m(decal('pl_MASTER', 0.3, 0.056), M.pl, { pos: [0, CH / 2 + 0.1, -D / 2 + 0.004] }));
  for (let i = 0; i < 4; i++) g.add(K.m(lw(keycap(0.04, 0.03, 0.014, 0.004), ['green', 'amber', 'red', 'white'][i]), M.lit, { pos: [-0.075 + i * 0.05, CH / 2 - 0.02, -D / 2 + 0.005], rot: [-HP, 0, 0] }));
  const cards = opts.cards ?? ['color_bars', 'show_2', 'station_id', 'show_9', 'show_12'];
  const groups = opts.groups ?? [];
  const units = [];
  // lower row: 3 x 14" rack monitors, slight lean; upper row: 2 x 19" monitors
  const lower = [-0.49, 0, 0.49];
  lower.forEach((x, i) => {
    const u = monitorUnit(game, M, { w: 0.47, h: 0.37, d: 0.44, card: cards[i], group: groups[i], id: opts.ids?.[i], face: i === 1 ? 'light' : 'putty', knobs: 3 });
    u.group.position.set(x, CH + 0.035, -0.02);
    u.group.rotation.z = [0.012, -0.006, -0.015][i];
    g.add(u.group); units.push(u);
  });
  [-0.33, 0.35].forEach((x, i) => {
    const u = monitorUnit(game, M, { w: 0.62, h: 0.46, d: 0.46, card: cards[3 + i], group: groups[3 + i], id: opts.ids?.[3 + i], case: i ? 'slate' : 'charcoal', face: 'putty', knobs: 4 });
    u.group.position.set(x, CH + 0.035 + 0.375, 0.0);
    u.group.rotation.set(-0.06, [0.035, -0.028][i], [-0.02, 0.025][i]);
    g.add(u.group); units.push(u);
  });
  // cables drooping behind
  g.add(K.m(sw(K.tube([[-0.5, 1.0, 0.25], [-0.45, 0.8, 0.34], [-0.2, 0.7, 0.32], [0.3, 0.72, 0.33], [0.55, 0.95, 0.27]], 0.014, { seg: 24, radial: 6 }), 'ink'), M.pl));
  g.userData.colliders = [{ min: [-W / 2 - 0.01, 0, -D / 2 - 0.02], max: [W / 2 + 0.01, 1.55, D / 2 + 0.02] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['monitor', 'crt', 'screen', 'master_control', 'newsroom'], size: [1.52, 1.56, 0.58], hero: true,
  desc: 'monitor bank: walnut base cabinet + 3 rack monitors + 2 x 19" on top, leaning. 5 screens. opts {cards[5], groups[5], ids[5]}' });

// ---------------------------------------------------------------------------------- cart monitor (AV cart)
registerProp('bc_cart_monitor', (game, opts = {}) => {
  const g = K.prop('bc_cart_monitor');
  const M = mats(game);
  const cartC = opts.cart ?? 'mustard';
  const W = 0.72, D = 0.52;
  const shelves = [0.2, 0.56, 0.94];
  for (const y of shelves) {
    g.add(K.m(sw(K.box(W, 0.03, D, 0.012), cartC), M.pl, { pos: [0, y, 0] }));
    g.add(K.m(sw(K.tube(K.roundRectPath(W - 0.012, D - 0.012, 0.03, 0.022, 2), 0.008, { seg: 20, radial: 4, closed: true }), cartC), M.pl, { pos: [0, y, 0] }));
  }
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    g.add(K.m(bcyl(0.015, 0.015, 0.88, 0.004, 8), M.ch, { pos: [x * (W / 2 - 0.03), 0.09, z * (D / 2 - 0.03)] }));
    const c = caster(M, 0.035);
    c.position.set(x * (W / 2 - 0.03), 0, z * (D / 2 - 0.03)); c.rotation.y = x * z * 0.6;
    g.add(c);
  }
  const mon = monitorUnit(game, M, { w: 0.58, h: 0.46, d: 0.46, card: opts.card ?? 'show_5', group: opts.group, id: opts.id, case: 'slate', face: 'light', handles: true, knobs: 4 });
  mon.group.position.set(0, 0.955, -0.01);
  mon.group.rotation.y = 0.04;
  g.add(mon.group);
  // strap over the monitor
  g.add(K.m(sw(cbox(0.05, 0.006, 0.47, 0.002), 'ink'), M.mt, { pos: [0.18, 0.955 + 0.465, 0.0], rot: [0, 0.04, 0] }));
  // cassette deck on the middle shelf
  const dy = 0.575;
  g.add(K.m(sw(K.box(0.54, 0.14, 0.38, 0.025), 'silver'), M.me, { pos: [0, dy + 0.07, 0.0] }));
  g.add(K.m(sw(cbox(0.52, 0.02, 0.36, 0.008), 'charcoal'), M.pl, { pos: [0, dy + 0.145, 0.0] }));
  g.add(K.m(sw(cbox(0.3, 0.012, 0.2, 0.004), 'ink'), M.pl, { pos: [-0.08, dy + 0.155, 0.02] }));
  for (let i = 0; i < 6; i++) g.add(K.m(sw(keycap(0.04, 0.05, 0.016, 0.004), i === 4 ? 'red' : 'ivory'), M.pl, { pos: [-0.2 + i * 0.045, dy + 0.12, -0.19], rot: [-0.6, 0, 0] }));
  g.add(K.m(decal('digits', 0.12, 0.03), M.lit, { pos: [0.17, dy + 0.08, -0.1905] }));
  g.add(K.m(decal('lbl_VTR', 0.1, 0.025), M.pl, { pos: [0.17, dy + 0.035, -0.1905] }));
  // bottom shelf: cable coil + tape boxes
  const coil = [];
  for (let i = 0; i <= 60; i++) { const t = i / 60, a = t * TAU * 3.2; const r = 0.1 + Math.sin(a * 0.5) * 0.008; coil.push([-0.15 + Math.cos(a) * r, 0.24 + t * 0.05, 0.02 + Math.sin(a) * r * 0.9]); }
  g.add(K.m(sw(K.tube(coil, 0.012, { seg: 50, radial: 4 }), 'orange'), M.pl));
  [[0.13, 0.215, 'wztvBlue', 0.1], [0.16, 0.255, 'charcoal', -0.12], [0.14, 0.295, 'red', 0.05]].forEach(([x, y, c, r]) => {
    g.add(K.m(sw(cbox(0.24, 0.04, 0.16, 0.007), c), M.pl, { pos: [x, y, 0.0], rot: [0, r, 0] }));
    const lab = K.m(sw(cbox(0.1, 0.002, 0.07, 0.0008), 'paper'), M.pl, { pos: [x, y + 0.021, 0.0], rot: [0, r, 0] });
    g.add(lab);
  });
  // power cable down the back leg
  g.add(K.m(sw(K.tube([[0.1, 1.1, 0.24], [0.2, 1.0, 0.3], [0.33, 0.8, 0.27], [0.33, 0.3, 0.27], [0.36, 0.02, 0.4], [0.5, 0.012, 0.6]], 0.01, { seg: 22, radial: 5 }), 'ink'), M.pl));
  g.userData.colliders = [{ min: [-W / 2 - 0.02, 0, -D / 2 - 0.05], max: [W / 2 + 0.02, 1.42, D / 2 + 0.02] }];
  g.userData.interact = null;
  return done(game, g);
}, { category: 'broadcast', tags: ['monitor', 'crt', 'screen', 'cart', 'feed_monitor', 'newsroom'], size: [0.76, 1.42, 0.6], hero: true,
  desc: 'rolling AV cart: 19" monitor (strap), cassette deck, cable coil, tape boxes. opts {card, group (e.g. scr_feed_newsroom), id, cart}' });

// ---------------------------------------------------------------------------------- MC monitor wall (4x3)
// Three rows of big CRTs fill MC's CRT band (0.56-3.28 m under the 3.6 m ceiling). The MIDDLE row, at eye level, is
// scr_mc_feeds (the four live feeds); the top and bottom rows are scr_mc_canned. The bottom-row corner CRTs carry the
// screen-spawn ids ss_mc_w (column 0 = the viewer's left) / ss_mc_e (last column); every other screen is
// mcwall_r{row}c{col}. The furniture (lamp keys, LED bars, knobs, bezels) scales with the row height.
registerProp('bc_monitor_wall', (game, opts = {}) => {
  const g = K.prop('bc_monitor_wall');
  const M = mats(game);
  const brushed = brushedMat(game);
  const cols = opts.cols ?? 4, rows = opts.rows ?? 3;
  // defaults fit MC's 3.6 m ceiling: CRT band 0.56-3.28 m, header to 3.48, cap to 3.55
  const base = opts.base ?? 0.56, band = opts.band ?? 2.72, headH = opts.headH ?? 0.2;
  const cw = opts.cellW ?? 1.6, rh = opts.cellH ?? band / rows;
  const k = rh / 0.68, kw = Math.min(k, 1.2);   // furniture scale vs the classic 0.68 m row
  const W = cols * cw, D = 0.5, topY = base + rows * rh;
  const H = topY + headH;
  const post = 0.07;
  const sW = opts.screenW ?? Math.min(0.8 * k, cw - 2 * post - 0.36), sH = opts.screenH ?? sW * (0.58 / 0.8);
  const fz = -D / 2;
  const colLabels = opts.labels ?? ['LOBBY', 'NEWS', 'STUDIO A', 'STUDIO B'];
  const feedRow = opts.feedRow ?? (rows >= 3 ? Math.floor((rows - 1) / 2) : 0);
  const spawnIds = opts.spawnIds === false ? null : { [`${rows - 1}_0`]: 'ss_mc_w', [`${rows - 1}_${cols - 1}`]: 'ss_mc_e' };
  const rnd = mulberry32(1313);
  const canned = ['color_bars', 'station_id', 'snow', 'color_bars', 'station_id', 'snow', 'station_id', 'color_bars', 'snow', 'station_id', 'color_bars', 'snow'];
  const feeds = ['show_4', 'show_7', 'show_2', 'show_9'];
  let cannedN = 0;
  // back shell (one box) + top cap + plinth
  g.add(K.m(sw(K.box(W - 0.02, H - 0.04, D - 0.1, 0.01), 'charcoal'), M.pl, { pos: [0, H / 2, 0.05] }));
  g.add(K.m(sw(K.box(W + 0.04, 0.07, D + 0.04, 0.025, { seg: 1 }), 'wztvBlue'), M.pl, { pos: [0, H + 0.025, 0] }));
  g.add(K.m(sw(cbox(W, 0.018, 0.01, 0.003), 'orange'), M.pl, { pos: [0, H - 0.03, -D / 2 - 0.003] }));
  for (let c = 0; c <= cols; c++) g.add(K.m(discDecal('logo13', 0.05, 16), M.pl, { pos: [-W / 2 + c * cw, H + 0.025, -D / 2 - 0.021] }));
  g.add(K.m(sw(K.box(W, 0.08, D - 0.06, 0.012), 'black'), M.mt, { pos: [0, 0.04, 0.02] }));
  for (let c = 0; c < cols; c++) {
    const x0 = W / 2 - (c + 0.5) * cw; // c = 0 is the leftmost column seen from the front
    const pw = cw - 2 * post - 0.006;
    // posts
    for (const s of [-1, 1]) g.add(K.m(K.box(post, H, D, 0.012, { uv: 2.2, swap: true }), brushed, { pos: [x0 + s * (cw / 2 - post / 2), H / 2, 0] }));
    // front panel with rounded CRT openings
    const shape = K.roundRect(pw, rows * rh - 0.01, 0.015);
    for (let r = 0; r < rows; r++) {
      const cy = (rows - 1 - r + 0.5) * rh - (rows * rh) / 2;
      shape.holes.push(new THREE.Path(K.roundRect(sW + 0.06, sH + 0.06, 0.1 * kw).getPoints(4).map((p) => p.add(new THREE.Vector2(0, cy)))));
    }
    const panel = K.extrude(shape, 0.03, { bevel: 0.008, bevelSeg: 1, curveSeg: 3, uv: 2 });
    g.add(K.m(panel, brushed, { pos: [x0, base + (rows * rh) / 2, fz + 0.015] }));
    // header + kick cabinet
    g.add(K.m(K.box(pw, headH - 0.02, 0.05, 0.015, { uv: 2, seg: 1 }), brushed, { pos: [x0, topY + headH / 2, fz + 0.03] }));
    g.add(K.m(decal('lbl_' + (colLabels[c] ?? 'LINE'), 0.36, 0.09), M.pl, { pos: [x0 + 0.2, topY + headH / 2, fz + 0.0035] }));
    for (let i = 0; i < 3; i++) g.add(K.m(lw(keycap(0.04, 0.03, 0.012, 0.004), i === 0 ? (c === 0 ? 'red' : 'green') : 'amber'), i === 2 ? M.dim : M.lit, { pos: [x0 - 0.2 - i * 0.07, topY + headH / 2, fz + 0.004], rot: [-HP, 0, 0] }));
    g.add(K.m(K.box(pw, base - 0.1, 0.04, 0.015, { uv: 2, seg: 1 }), brushed, { pos: [x0, 0.08 + (base - 0.1) / 2, fz + 0.03] }));
    g.add(K.m(decal('vent', 0.5, 0.26), M.pl, { pos: [x0 + 0.3, 0.08 + (base - 0.1) / 2, fz + 0.0085] }));
    g.add(K.m(decal(c === 1 ? 'pl_MASTER' : 'pl_KINETRON', 0.34, 0.064), M.pl, { pos: [x0 - 0.3, 0.08 + (base - 0.1) / 2 + 0.06, fz + 0.0085] }));
    g.add(K.m(decal('hv', 0.2, 0.0375), M.pl, { pos: [x0 - 0.3, 0.08 + (base - 0.1) / 2 - 0.07, fz + 0.0085] }));
    for (let r = 0; r < rows; r++) {
      const cy = base + (rows - 1 - r + 0.5) * rh;
      // tube bezel (dark rounded face behind the opening) + screen
      g.add(K.m(sw(new THREE.ShapeGeometry(K.roundRect(sW + 0.06, sH + 0.06, 0.1 * kw), 4).rotateY(Math.PI), 'ink'), M.pl, { pos: [x0, cy, fz + 0.034] }));
      const idx = r * cols + c;
      const isFeed = r === feedRow;
      const ssId = spawnIds && spawnIds[`${r}_${c}`];
      const screen = scr(game, sW, sH, {
        card: opts.cards?.[idx] ?? (isFeed ? feeds[c % 4] : ssId ? 'snow' : canned[cannedN++ % canned.length]),
        group: opts.groups?.[idx] ?? (isFeed ? 'scr_mc_feeds' : 'scr_mc_canned'), id: ssId || `mcwall_r${r}c${c}`, dome: 0.03 * k,
        seg: k > 1.1 ? [10, 8] : undefined,
      });
      screen.position.set(x0, cy, fz + 0.03);
      g.add(screen);
      // side furniture: two lamp keys left, LED bar + knob right, centred in the strip between the opening and the post
      const side = (sW / 2 + 0.03 + cw / 2 - post) / 2;
      const lx = x0 + side, rx = x0 - side; // lamp keys on the viewer's left, meter on the right
      for (let i = 0; i < 2; i++) {
        const on = rnd() < 0.6;
        const colr = ['green', 'amber', 'red', 'white'][Math.floor(rnd() * 4)];
        g.add(K.m(on ? lw(keycap(0.06, 0.045, 0.014, 0.005), colr) : sw(keycap(0.06, 0.045, 0.014, 0.005), 'lampWhite'), on ? M.lit : M.pl, { pos: [lx, cy + 0.08 * k - i * 0.15 * k, fz], rot: [-HP, 0, 0] }));
      }
      g.add(K.m(decal('vuBar', 0.045 * kw, 0.2 * k), M.lit, { pos: [rx, cy + 0.06 * k, fz - 0.001] }));
      for (const mm of knob(M, 0.018 * kw, [rx, cy - 0.15 * k, fz], { color: 'ink', skirt: false, rot: rnd() * 3, seg: 8 })) g.add(mm);
    }
  }
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2, H + 0.05, D / 2] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['monitor', 'crt', 'screen', 'master_control', 'wall', 'hero'], size: [6.5, 3.55, 0.54], hero: true,
  desc: 'MC monitor wall: 4x3 big CRTs flush in brushed racks, lamp keys, LED meters, column labels. 12 screens: middle row scr_mc_feeds, top + bottom rows scr_mc_canned; ids mcwall_r{row}c{col}, bottom corners ss_mc_w / ss_mc_e. opts {cols, rows, band, cellW, cellH, base, screenW, screenH, feedRow, spawnIds:false, labels[], cards[], groups[]}' });

// ---------------------------------------------------------------------------------- ON AIR light box
function signBox(game, g, M, o) {
  const { W, H, D, cellName, lit, frameC = 'ink', bezel = true } = o;
  g.add(K.m(sw(K.box(W, H, D, Math.min(0.05, H * 0.22)), frameC), M.pl, { pos: [0, H / 2, 0] }));
  if (bezel) g.add(K.m(frame(W - 0.02, H - 0.02, 0.032, 0.022, Math.min(0.045, H * 0.2), 0.02), M.ch, { pos: [0, H / 2, -D / 2 - 0.004] }));
  const faceGeo = cu(K.box(W - 0.075, H - 0.075, 0.016, 0.008), cellName);
  const lamp = K.m(faceGeo, lit ? M.sign : M.dim, { pos: [0, H / 2, -D / 2 - 0.0], name: 'lamp' });
  lamp.userData.noMerge = true;
  lamp.userData.noOcclude = true;
  g.add(lamp);
  g.userData.parts = { ...(g.userData.parts || {}), lamp };
  g.userData.lampMats = { on: M.sign, off: M.dim };
  return lamp;
}
registerProp('bc_on_air', (game, opts = {}) => {
  const g = K.prop('bc_on_air');
  const M = mats(game);
  const W = 0.64, H = 0.24, D = 0.13;
  const lit = !!opts.lit;
  signBox(game, g, M, { W, H, D, cellName: 'onair', lit });
  // wall brackets + conduit up the wall
  for (const s of [-1, 1]) g.add(K.m(sw(K.box(0.04, 0.12, 0.04, 0.012), 'charcoal'), M.pl, { pos: [s * (W / 2 - 0.08), H / 2, D / 2 + 0.005] }));
  g.add(K.m(K.cyl(0.013, 0.013, 0.34, { bevel: 0.003, seg: 8 }), M.ch, { pos: [W / 2 - 0.1, H - 0.02, D / 2 - 0.02] }));
  g.add(K.m(sw(K.box(0.05, 0.05, 0.04, 0.012), 'charcoal'), M.pl, { pos: [W / 2 - 0.1, H + 0.005, D / 2 - 0.02] }));
  // little visor above the face
  g.add(K.m(sw(K.box(W - 0.02, 0.018, 0.07, 0.008), 'ink'), M.pl, { pos: [0, H - 0.01, -D / 2 - 0.03], rot: [0.18, 0, 0] }));
  if (lit && opts.anchor) g.userData.lightAnchors = [{ pos: [0, H / 2, -0.4], color: PAL.onAirRed, intensity: 0.8, distance: 2.5 }];
  g.userData.colliders = [];
  return done(game, g);
}, { category: 'broadcast', tags: ['sign', 'on_air', 'wall', 'lamp'], size: [0.64, 0.58, 0.2],
  desc: 'wall ON AIR light box (back at z=+0.065): chrome bezel, red face = parts.lamp; lampMats {on, off}. opts {lit=false, anchor}' });

// ---------------------------------------------------------------------------------- APPLAUSE light box
registerProp('bc_applause', (game, opts = {}) => {
  const g = K.prop('bc_applause');
  const M = mats(game);
  const W = 1.5, H = 0.42, D = 0.2;
  const lit = opts.lit !== false;
  const lamp = signBox(game, g, M, { W, H, D, cellName: 'applause', lit, frameC: 'charcoal' });
  lamp.scale.set(1, 0.86, 1);
  // marquee bulbs around the face (part 'bulbs')
  const bulbs = new THREE.Group();
  bulbs.userData.noMerge = true;
  const bgeo = lw(lowSphere(0.02, 6, 4), 'tungsten');
  const n = 14;
  for (let i = 0; i < n; i++) {
    const x = -W / 2 + 0.08 + (i / (n - 1)) * (W - 0.16);
    for (const y of [H - 0.028, 0.028]) bulbs.add(K.m(bgeo, lit ? M.lit : M.dim, { pos: [x, y, -D / 2 - 0.018] }));
  }
  for (const s of [-1, 1]) for (const y of [0.14, 0.28]) bulbs.add(K.m(bgeo, lit ? M.lit : M.dim, { pos: [s * (W / 2 - 0.03), y, -D / 2 - 0.018] }));
  g.add(bulbs);
  // hanging chains to the grid
  const chain = opts.chain ?? 0.7;
  for (const s of [-1, 1]) {
    g.add(K.m(sw(bcyl(0.022, 0.022, 0.03, 0.006, 10), 'ink'), M.pl, { pos: [s * (W / 2 - 0.15), H, 0] }));
    const links = Math.round(chain / 0.06);
    for (let i = 0; i < links; i++) {
      const l = K.m(K.tube(ring(0.018, 6), 0.0045, { seg: 6, radial: 3, closed: true }), M.ch, { pos: [s * (W / 2 - 0.15), H + 0.045 + i * 0.06, 0] });
      l.rotation.set(HP, i % 2 ? HP : 0, 0);
      l.scale.set(1, 1.7, 1);
      g.add(l);
    }
  }
  g.userData.parts = { lamp, bulbs };
  if (lit && opts.anchor) g.userData.lightAnchors = [{ pos: [0, H / 2, -0.6], color: '#FF6A50', intensity: 1.2, distance: 4 }];
  g.userData.colliders = [];
  return done(game, g, { mergeParts: [bulbs] });
}, { category: 'broadcast', tags: ['sign', 'applause', 'studio_a', 'lamp', 'hanging', 'ee'], size: [1.5, 1.15, 0.24], hero: true,
  desc: 'hanging APPLAUSE box: marquee bulbs (parts.bulbs), face = parts.lamp; y=0 is the box bottom, chains rise opts.chain (0.7 m). opts {lit=true, chain, anchor}' });

// ---------------------------------------------------------------------------------- lamp helper (engine API)
// setLamp(prop, state, partName = 'lamp'): state 'on' | 'off' | a LIT color name (red amber green blue white
// yellow cyan magenta orange tungsten purple). Color changes rewrite the lamp's UVs on its own geometry copy.
export const LAMP_COLORS = Object.keys(LIT);
export function setLamp(prop, state, partName = 'lamp') {
  const u = prop.userData, mesh = u.parts?.[partName];
  if (!mesh || !u.lampMats) return false;
  if (state === 'off') { mesh.material = u.lampMats.off; return true; }
  if (state !== 'on') {
    const c = LITUV[state];
    if (!c) return false;
    if (!mesh.userData.ownGeo) { mesh.geometry = mesh.geometry.clone(); mesh.userData.ownGeo = true; }
    const uv = mesh.geometry.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, c[0], c[1]);
    uv.needsUpdate = true;
  }
  mesh.material = u.lampMats.on;
  return true;
}

// ---------------------------------------------------------------------------------- quad 2-inch VTR
// A reel group (flanges with the printed aluminum face, tape pack, hub), axis along z, front face at z = 0.
function tapeReel(M, r = 0.18, o = {}) {
  const grp = new THREE.Group();
  grp.userData.noMerge = true;
  const depth = o.depth ?? 0.055, pack = o.pack ?? 0.72;
  const rs = r < 0.12 ? 22 : 32;
  grp.add(K.m(discDecal('reel', r, rs), M.me, { pos: [0, 0, -0.001] }));
  grp.add(K.m(cu(new THREE.CircleGeometry(r, rs), 'reel'), M.me, { pos: [0, 0, depth] }));
  for (const z of r < 0.12 ? [-0.002] : [-0.002, depth + 0.001]) grp.add(K.m(sw(K.tube(ring(r, 20), 0.0045, { seg: 22, radial: 3, closed: true }), 'steel'), M.me, { pos: [0, 0, z], rot: [HP, 0, 0] }));
  grp.add(K.m(sw(lowCyl(r * pack, depth - 0.006, 20), 'tape'), M.pl, { pos: [0, 0, 0.003], rot: [HP, 0, 0] }));
  grp.add(K.m(sw(L([[0, 0], [r * 0.24, 0], [r * 0.24, 0.012], [r * 0.18, 0.02], [0, 0.02]], 0, 12), 'silver'), M.me, { pos: [0, 0, -0.001], rot: [-HP, 0, 0] }));
  if (o.label) grp.add(K.m(discDecal('reelLabel', r * 0.17, 20), M.pl, { pos: [0, 0, -0.023] }));
  return grp;
}
// spindle with three lock tabs (bare = conspicuous), axis along -z from the deck plate
function spindle(M) {
  const grp = new THREE.Group();
  grp.userData.noMerge = true;
  grp.add(K.m(sw(L([[0, 0], [0.05, 0], [0.05, 0.012], [0.026, 0.02], [0.024, 0.075], [0.03, 0.08], [0.02, 0.095], [0, 0.097]], 0.004, 16), 'silver'), M.me, { rot: [-HP, 0, 0] }));
  for (let i = 0; i < 3; i++) {
    const t = K.m(sw(cbox(0.016, 0.034, 0.016, 0.004), 'silver'), M.me, {});
    const a = (i / 3) * TAU;
    t.position.set(Math.cos(a) * 0.03, Math.sin(a) * 0.03, -0.075);
    t.rotation.z = a - HP;
    grp.add(t);
  }
  return grp;
}
// VU meter: soft-lit face in a bezel + needle (part), facing -z; returns { meshes, needle }
function vuMeter(M, w, p, o = {}) {
  const h = w * 0.5;
  const out = [];
  out.push(K.m(sw(frame(w + 0.024, h + 0.024, 0.014, 0.02, 0.012, 0.005, { lite: true }), o.bezel ?? 'ink'), M.pl, { pos: [p[0], p[1], p[2] - 0.008] }));
  out.push(K.m(decal('vu', w, h), M.soft, { pos: [p[0], p[1], p[2] - 0.004] }));
  const needle = K.m(sw(cbox(0.003, h * 0.78, 0.002, 0.0008), 'black'), M.pl, {});
  const pivot = new THREE.Group();
  pivot.position.set(p[0], p[1] - h * 0.5, p[2] - 0.007);
  needle.position.set(0, h * 0.39, 0);
  pivot.rotation.z = o.angle ?? 0.25;
  pivot.add(needle);
  if (o.part) pivot.userData.noMerge = true;
  out.push(pivot);
  return { meshes: out, needle: pivot };
}

registerProp('bc_vtr_quad', (game, opts = {}) => {
  const g = K.prop('bc_vtr_quad');
  const M = mats(game);
  const bodyC = opts.color ?? 'ivory', accC = opts.accent ?? 'teal', deckC = 'gunmetal';
  const reels = opts.reels !== false;
  const W = 1.16, H = 1.92, D = 0.8, fz = -D / 2;
  // cabinet: plinth, main body, accent cheeks, overhanging top cap
  g.add(K.m(sw(cbox(W - 0.08, 0.08, D - 0.08, 0.01), 'black'), M.pl, { pos: [0, 0.04, 0.02] }));
  g.add(K.m(sw(K.box(W - 0.1, H - 0.1, D, 0.05), bodyC), M.pl, { pos: [0, 0.07 + (H - 0.1) / 2, 0] }));
  for (const s of [-1, 1]) g.add(K.m(sw(K.box(0.07, H - 0.07, D + 0.02, 0.03), accC), M.pl, { pos: [s * (W / 2 - 0.035), 0.07 + (H - 0.07) / 2, 0] }));
  g.add(K.m(sw(K.box(W + 0.02, 0.05, D + 0.05, 0.022, { seg: 1 }), 'charcoal'), M.pl, { pos: [0, H + 0.02, 0] }));
  // lower doors with vents, chrome pulls, nameplate + number
  for (const s of [-1, 1]) {
    g.add(K.m(sw(K.extrude(K.roundRect(0.47, 0.64, 0.035), 0.022, { bevel: 0.008, curveSeg: 3, bevelSeg: 1 }), bodyC), M.pl, { pos: [s * 0.25, 0.46, fz - 0.009] }));
    g.add(K.m(decal('vent', 0.3, 0.2), M.pl, { pos: [s * 0.25, 0.3, fz - 0.0205] }));
    g.add(K.m(K.tube([[s * 0.04, 0.58, fz - 0.02], [s * 0.04, 0.58, fz - 0.05], [s * 0.04, 0.68, fz - 0.05], [s * 0.04, 0.68, fz - 0.02]], 0.008, { seg: 8, radial: 5 }), M.ch));
  }
  g.add(K.m(decal('pl_QUADRAMAX', 0.3, 0.056), M.pl, { pos: [-0.25, 0.66, fz - 0.0205] }));
  g.add(K.m(decal('vtr' + (opts.num ?? 1), 0.16, 0.06), M.pl, { pos: [0.25, 0.66, fz - 0.0205] }));
  // control ledge: sloped strip with transport keys, timecode, TRACKING knob (part)
  const ly = 0.86;
  g.add(K.m(sw(K.box(W - 0.14, 0.09, 0.2, 0.03), 'charcoal'), M.pl, { pos: [0, ly, fz - 0.06], rot: [-0.35, 0, 0] }));
  const ledge = new THREE.Group();
  ledge.position.set(0, ly + 0.045 * Math.cos(0.35), fz - 0.06 - 0.045 * Math.sin(0.35));
  ledge.rotation.x = -0.35;
  g.add(ledge);
  const keyC = [['lampWhite', 0], ['green', 1], ['lampRed', 0], ['lampWhite', 0], ['red', opts.rec ? 1 : 0]];
  keyC.forEach(([c, on], i) => ledge.add(K.m(on ? lw(keycap(0.065, 0.06, 0.02, 0.006), c) : sw(keycap(0.065, 0.06, 0.02, 0.006), c), on ? M.lit : M.pl, { pos: [-0.42 + i * 0.078, 0.0, 0.02] })));
  ledge.add(K.m(cu(new THREE.PlaneGeometry(0.38, 0.036).rotateX(-HP), 'keys'), M.pl, { pos: [-0.265, 0.002, -0.058] }));
  ledge.add(K.m(cu(new THREE.PlaneGeometry(0.16, 0.04).rotateX(-HP), 'digits'), M.lit, { pos: [0.03, 0.002, 0.0] }));
  ledge.add(K.m(cu(new THREE.CircleGeometry(0.078, 28).rotateX(-HP), 'dialTrk'), M.pl, { pos: [0.33, 0.002, 0] }));
  const knobG = new THREE.Group();
  knobG.position.set(0.33, 0.002, 0);
  knobG.rotation.y = (opts.track ?? 3) * -0.48; // 13 detents
  knobG.userData.noMerge = true;
  knobG.add(K.m(sw(L([[0, 0], [0.05, 0], [0.05, 0.012], [0.042, 0.02], [0.04, 0.05], [0.032, 0.058], [0, 0.058]], 0, 16), 'ink'), M.pl));
  knobG.add(K.m(sw(cbox(0.012, 0.012, 0.05, 0.003), 'red'), M.pl, { pos: [0, 0.058, -0.022] }));
  knobG.add(K.m(sw(lowCyl(0.03, 0.004, 14), 'silver'), M.me, { pos: [0, 0.058, 0] }));
  ledge.add(knobG);
  // tape deck: inset gunmetal panel, reels or bare spindles, head block, tape path
  const dy = 1.26, rx = 0.3, rr0 = 0.18;
  g.add(K.m(sw(K.box(W - 0.2, 0.62, 0.03, 0.03), deckC), M.pl, { pos: [0, dy, fz - 0.006] }));
  g.add(K.m(K.tube(rectLoopXY(W - 0.19, 0.61, 0.03), 0.006, { seg: 32, radial: 4, closed: true }), M.ch, { pos: [0, dy, fz - 0.02] }));
  const spL = spindle(M), spR = spindle(M);
  spL.position.set(-rx, dy + 0.04, fz - 0.021); spR.position.set(rx, dy + 0.04, fz - 0.021);
  if (!reels) { spL.scale.setScalar(1.5); spR.scale.setScalar(1.5); } // bare spindles must read from across MC (EE step 5)
  g.add(spL, spR);
  let reelL = null, reelR = null;
  if (reels) {
    reelL = tapeReel(M, rr0, { pack: 0.8 }); reelR = tapeReel(M, rr0, { pack: 0.5 });
    reelL.position.set(-rx, dy + 0.04, fz - 0.1); reelR.position.set(rx, dy + 0.04, fz - 0.1);
    reelL.rotation.z = 0.4; reelR.rotation.z = 1.3;
    g.add(reelL, reelR);
  }
  // head assembly: chrome block with the rotary head drum + guide rollers
  g.add(K.m(sw(K.box(0.24, 0.13, 0.08, 0.02), 'silver'), M.me, { pos: [0, dy - 0.2, fz - 0.05] }));
  g.add(K.m(bcyl(0.045, 0.045, 0.05, 0.006, 16), M.ch, { pos: [0, dy - 0.2, fz - 0.09], rot: [-HP, 0, 0] }));
  g.add(K.m(sw(cbox(0.06, 0.03, 0.02, 0.006), 'red'), M.pl, { pos: [0, dy - 0.13, fz - 0.09] }));
  for (const s of [-1, 1]) g.add(K.m(bcyl(0.018, 0.018, 0.07, 0.004, 10), M.ch, { pos: [s * 0.17, dy - 0.2, fz - 0.02], rot: [-HP, 0, 0] }));
  if (reels) {
    const tz = fz - 0.13, tc = 'tapeGold';
    const band = (a, b) => { const va = new THREE.Vector3(...a), vb = new THREE.Vector3(...b); const len = va.distanceTo(vb); const m = K.m(sw(cbox(0.004, len, 0.05, 0.001), tc), M.pl); m.position.copy(va).lerp(vb, 0.5); m.rotation.z = Math.atan2(vb.y - va.y, vb.x - va.x) - HP; return m; };
    g.add(band([-rx - 0.02, dy + 0.04 - rr0 * 0.8, tz], [-0.18, dy - 0.2, tz]));
    g.add(band([-0.18, dy - 0.215, tz], [0.18, dy - 0.215, tz]));
    g.add(band([0.18, dy - 0.2, tz], [rx + 0.02, dy + 0.04 - rr0 * 0.5, tz]));
  }
  // meter bridge: slanted panel, 2 VU meters (needle parts), monitor, status lamp (part)
  const my = 1.72;
  g.add(K.m(sw(K.box(W - 0.14, 0.34, 0.1, 0.03), 'charcoal'), M.pl, { pos: [0, my, fz + 0.03], rot: [0.12, 0, 0] }));
  const bridge = new THREE.Group();
  bridge.position.set(0, my, fz - 0.02);
  bridge.rotation.x = 0.12;
  g.add(bridge);
  const vuL = vuMeter(M, 0.16, [-0.38, 0.02, 0], { angle: 0.35, part: true }), vuR = vuMeter(M, 0.16, [-0.17, 0.02, 0], { angle: -0.1, part: true });
  for (const m of [...vuL.meshes, ...vuR.meshes]) bridge.add(m);
  const mon = monitorUnit(game, M, { w: 0.34, h: 0.27, d: 0.24, case: 'ink', face: 'charcoal', card: opts.card ?? (opts.group === 'scr_vtr2' ? 'snow' : 'station_id'), group: opts.group, id: opts.id, knobs: 2, plate: false, tally: false });
  mon.group.position.set(0.3, -0.145, 0.02);
  bridge.add(mon.group);
  for (let i = 0; i < 4; i++) bridge.add(K.m((i === 3 ? sw : lw)(cbox(0.03, 0.02, 0.012, 0.004), ['green', 'amber', 'green', 'lampRed'][i]), i === 3 ? M.pl : M.lit, { pos: [-0.44 + i * 0.05, -0.11, -0.012] }));
  bridge.add(K.m(decal('lbl_AUDIO', 0.16, 0.04), M.pl, { pos: [-0.275, 0.13, -0.004] }));
  // status beacon on the top cap
  g.add(K.m(sw(L([[0, 0], [0.06, 0], [0.062, 0.02], [0.05, 0.03], [0, 0.03]], 0.005, 14), 'charcoal'), M.pl, { pos: [0.42, H + 0.045, -0.2] }));
  const lampColor = opts.lamp ?? 'green';
  const lamp = K.m(lw(L([[0, 0], [0.045, 0], [0.045, 0.02], [0.04, 0.06], [0.024, 0.085], [0, 0.09]], 0.012, 14), lampColor === 'off' ? 'amber' : lampColor), lampColor === 'off' ? M.dim : M.lit, { pos: [0.42, H + 0.072, -0.2], name: 'lamp' });
  lamp.userData.noMerge = true;
  g.add(lamp);
  // cable bundle out the back
  g.add(K.m(sw(K.tube([[-0.3, 0.5, D / 2 - 0.02], [-0.3, 0.2, D / 2 + 0.08], [-0.25, 0.03, D / 2 + 0.2], [-0.1, 0.025, D / 2 + 0.45]], 0.025, { seg: 14, radial: 6 }), 'ink'), M.pl));
  g.userData.parts = { lamp, reelL, reelR, spindleL: spL, spindleR: spR, needleL: vuL.needle, needleR: vuR.needle, trackingKnob: knobG };
  g.userData.lampMats = { on: M.lit, off: M.dim };
  g.userData.colliders = [{ min: [-W / 2 - 0.01, 0, fz - 0.14], max: [W / 2 + 0.01, H + 0.1, D / 2 + 0.03] }];
  g.userData.interact = { point: [0, 1.1, fz - 0.45], radius: 1.5 };
  return done(game, g, { mergeParts: [reelL, reelR, spL, spR, knobG] });
}, { category: 'broadcast', tags: ['vtr', 'tape', 'master_control', 'ee', 'hero', 'screen'], size: [1.18, 2.03, 0.95], hero: true,
  desc: 'fridge-sized quad 2" VTR: reels (parts reelL/R, spin about z), spindles, VU needles, TRACKING knob, status lamp (setLamp), monitor. opts {reels=true, lamp:green|amber|purple|red|off, num 1-3, group (scr_vtr2 for #2), card, id, rec}' });

// ---------------------------------------------------------------------------------- MC console segments
// Shared side profile (z, y): recessed kick, front, armrest lip, sloped work panel, turret. Width along x.
const CON = { D: 0.96, slope: [[-0.38, 0.78], [0.08, 0.93]], turret: [[0.12, 0.95], [0.16, 1.2]], topY: 1.22 };
const CON_PROFILE = [[-0.4, 0], [0.47, 0], [0.47, 1.2], [0.44, 1.23], [0.16, 1.22], [0.1, 0.95], [0.08, 0.93], [-0.38, 0.78], [-0.44, 0.76], [-0.47, 0.72], [-0.47, 0.12], [-0.4, 0.1]];
const SLOPE_A = Math.atan2(0.93 - 0.78, 0.08 + 0.38); // ~18 deg
function consoleBody(game, g, M, W, o = {}) {
  const bodyC = o.color ?? 'putty';
  const geo = K.extrude(CON_PROFILE, W, { bevel: 0.018, round: 0.025, curveSeg: 2, bevelSeg: 1 }).rotateY(-HP);
  if (o.taper) { // corner wedge: scale x by depth
    const p = geo.attributes.position;
    for (let i = 0; i < p.count; i++) { const t = (p.getZ(i) + 0.47) / 0.94; p.setX(i, p.getX(i) * (o.taper[0] + (o.taper[1] - o.taper[0]) * t)); }
    geo.computeVertexNormals();
  }
  g.add(K.m(sw(geo, bodyC), M.pl));
  const wood = woodMat(game);
  const wf = (z) => (o.taper ? o.taper[0] + (o.taper[1] - o.taper[0]) * ((z + 0.47) / 0.94) : 1);
  // vinyl armrest + walnut kick trim + walnut turret top
  const vinyl = K.mat(game, 'vinyl', '#ffffff', { map: K.tex.pebble(o.vinyl ?? '#8A3A22') });
  g.add(K.m(K.cushion(W * wf(-0.43) - 0.01, 0.075, 0.13, { puff: 0.012, seg: [6, 2, 3] }), vinyl, { pos: [0, 0.785, -0.42] }));
  g.add(K.m(K.box(W * wf(-0.47) - 0.01, 0.06, 0.03, 0.01, { uv: 1.5, swap: true }), wood, { pos: [0, 0.69, -0.475] }));
  g.add(K.m(K.box(W * wf(0.3) - 0.01, 0.03, 0.34, 0.01, { uv: 1.5, swap: true }), wood, { pos: [0, 1.235, 0.3] }));
  // panel plates (charcoal) on the slope and turret
  const slope = new THREE.Group();
  slope.position.set(0, 0.855 + 0.008, -0.15);
  slope.rotation.x = -SLOPE_A;
  g.add(slope);
  slope.add(K.m(sw(cbox(W * wf(-0.15) - 0.1, 0.012, 0.44, 0.005), 'charcoal'), M.pl));
  const turret = new THREE.Group();
  const ta = Math.atan2(0.06, 0.27);
  turret.position.set(0, 1.085, 0.13);
  turret.rotation.x = ta;
  g.add(turret);
  turret.add(K.m(sw(cbox(W * wf(0.13) - 0.1, 0.22, 0.012, 0.005), 'charcoal'), M.pl, { pos: [0, 0, -0.004] }));
  return { slope, turret, wood };
}
// face-up items on the slope group: y up = panel normal, -z = toward the operator
function consoleCommon(g) {
  g.userData.colliders = [{ min: [-g.userData.__w / 2, 0, -0.5], max: [g.userData.__w / 2, 1.25, 0.48] }];
  delete g.userData.__w;
}

registerProp('bc_console_switcher', (game, opts = {}) => {
  const g = K.prop('bc_console_switcher');
  const M = mats(game);
  const W = opts.width ?? 1.2;
  const { slope, turret } = consoleBody(game, g, M, W, opts);
  const rnd = mulberry32(77);
  // three buses x 10 chunky keys; one lit per bus (PGM red, PST green, EFX amber)
  const bus = [['red', 'lampWhite', -0.13], ['green', 'lampWhite', -0.03], ['amber', 'beige', 0.07]];
  bus.forEach(([litC, offC, z], bi) => {
    const litIdx = [2, 5, 7][bi];
    for (let i = 0; i < 10; i++) {
      const x = -0.43 + i * 0.068;
      const on = i === litIdx;
      slope.add(K.m(on ? lw(keycap(0.052, 0.052, 0.022, 0.007), litC) : sw(keycap(0.052, 0.052, 0.022, 0.007), rnd() < 0.15 ? 'sky' : offC), on ? M.lit : M.pl, { pos: [x, 0.006, z] }));
    }
    slope.add(K.m(cu(new THREE.PlaneGeometry(0.66, 0.024).rotateX(-HP), 'bus'), M.pl, { pos: [-0.12, 0.0075, z - 0.042] }));
  });
  // T-bar fader (part 'tbar' pivots about x) in a slotted plate
  slope.add(K.m(sw(cbox(0.13, 0.014, 0.3, 0.006), 'ink'), M.pl, { pos: [0.44, 0.008, -0.02] }));
  slope.add(K.m(sw(new THREE.PlaneGeometry(0.03, 0.24).rotateX(-HP), 'black'), M.pl, { pos: [0.44, 0.0155, -0.02] }));
  const tbar = new THREE.Group();
  tbar.position.set(0.44, 0.01, -0.02);
  tbar.rotation.x = opts.tbar ?? 0.35;
  tbar.userData.noMerge = true;
  tbar.add(K.m(bcyl(0.011, 0.011, 0.2, 0.003, 8), M.ch));
  tbar.add(K.m(K.tube([[-0.09, 0.2, 0], [0.09, 0.2, 0]], 0.02, { seg: 2, radial: 10 }), M.ch));
  for (const s of [-1, 1]) tbar.add(K.m(sw(K.tube([[s * 0.03, 0.2, 0], [s * 0.1, 0.2, 0]], 0.026, { seg: 2, radial: 10 }), 'black'), M.pl));
  for (const s of [-1, 1]) tbar.add(K.m(sw(lowSphere(0.026, 10, 6), 'black'), M.pl, { pos: [s * 0.1, 0.2, 0] }));
  slope.add(tbar);
  // joystick positioner + wipe pattern keys
  slope.add(K.m(sw(L([[0, 0], [0.04, 0], [0.042, 0.01], [0.02, 0.022], [0, 0.024]], 0.004, 12), 'ink'), M.pl, { pos: [-0.42, 0.006, 0.16] }));
  slope.add(K.m(K.cyl(0.006, 0.006, 0.07, { bevel: 0.002, seg: 6 }), M.ch, { pos: [-0.42, 0.02, 0.16], rot: [0.2, 0, 0.15] }));
  slope.add(K.m(sw(lowSphere(0.017, 10, 6), 'red'), M.pl, { pos: [-0.411, 0.088, 0.174] }));
  for (let i = 0; i < 6; i++) slope.add(K.m((i === 2 ? lw : sw)(keycap(0.04, 0.04, 0.016, 0.005), i === 2 ? 'cyan' : 'light'), i === 2 ? M.lit : M.pl, { pos: [-0.3 + i * 0.05, 0.006, 0.16] }));
  // turret: 2 round meters, lit status keys, labels
  for (const [x, c] of [[-0.4, 'meterRound'], [-0.26, 'meterRound']]) {
    turret.add(K.m(sw(L([[0.05, 0], [0.058, 0], [0.058, 0.012], [0.05, 0.012]], 0, 16), 'silver'), M.pl, { pos: [x, 0.02, -0.01], rot: [-HP, 0, 0] }));
    turret.add(K.m(discDecal(c, 0.05, 20), M.soft, { pos: [x, 0.02, -0.012] }));
  }
  ['AIR', 'LINE', 'SYNC'].forEach((t, i) => {
    const airOff = i === 0 && !opts.onAir;
    turret.add(K.m((airOff ? sw : lw)(keycap(0.07, 0.05, 0.014, 0.005), airOff ? 'lampRed' : ['red', 'green', 'amber'][i]).clone().rotateX(-HP), airOff ? M.pl : M.lit, { pos: [-0.05 + i * 0.12, 0.04, -0.01] }));
    turret.add(K.m(decal('lbl_' + t, 0.09, 0.0225), M.pl, { pos: [-0.05 + i * 0.12, -0.03, -0.0112] }));
  });
  turret.add(K.m(decal('pl_MASTER', 0.2, 0.0375), M.pl, { pos: [0.4, 0.06, -0.0112] }));
  turret.add(K.m(decal('digits', 0.16, 0.04), M.lit, { pos: [0.4, -0.02, -0.0112] }));
  g.userData.parts = { tbar };
  g.userData.__w = W;
  consoleCommon(g);
  return done(game, g, { mergeParts: [tbar] });
}, { category: 'broadcast', tags: ['console', 'switcher', 'master_control', 'island'], size: [1.2, 1.25, 0.96],
  desc: 'MC island segment: vision switcher, 3 buses of chunky lit keys, chrome T-bar (parts.tbar, rot.x), joystick, turret meters. Segments butt together along x (width 1.2). opts {width, color, vinyl, tbar, onAir}' });

registerProp('bc_console_audio', (game, opts = {}) => {
  const g = K.prop('bc_console_audio');
  const M = mats(game);
  const W = opts.width ?? 1.2;
  const { slope, turret } = consoleBody(game, g, M, W, opts);
  const rnd = mulberry32(31);
  const n = 8, sp = (W - 0.24) / n;
  const capC = ['red', 'ivory', 'ivory', 'sky', 'sky', 'ivory', 'gold', 'black'];
  for (let i = 0; i < n; i++) {
    const x = -W / 2 + 0.16 + i * sp;
    for (const [z, c] of [[-0.17, 'orange'], [-0.1, 'sky']]) {
      slope.add(K.m(sw(L([[0, 0], [0.016, 0], [0.015, 0.018], [0.011, 0.024], [0, 0.024]], 0, 7), 'ink'), M.pl, { pos: [x, 0.006, z] }));
      slope.add(K.m(sw(lowCyl(0.009, 0.003, 7), c), M.pl, { pos: [x, 0.03, z] }));
    }
    slope.add(K.m(sw(new THREE.PlaneGeometry(0.014, 0.22).rotateX(-HP), 'black'), M.mt, { pos: [x, 0.0065, 0.07] }));
    slope.add(K.m(sw(keycap(0.04, 0.032, 0.028, 0.007), capC[i]), M.pl, { pos: [x, 0.006, 0.12 - rnd() * 0.15] }));
    const on = rnd() < 0.5;
    slope.add(K.m(on ? lw(keycap(0.034, 0.026, 0.012, 0.004), 'amber') : sw(keycap(0.034, 0.026, 0.012, 0.004), 'lampAmber'), on ? M.lit : M.pl, { pos: [x, 0.006, -0.04] }));
  }
  // turret: two big VU meters with needles (parts), master knobs
  const vA = vuMeter(M, 0.26, [-0.26, 0.0, -0.012], { angle: 0.3, part: true }), vB = vuMeter(M, 0.26, [0.08, 0.0, -0.012], { angle: -0.15, part: true });
  for (const m of [...vA.meshes, ...vB.meshes]) turret.add(m);
  for (const mm of knob(M, 0.03, [0.36, 0.02, -0.012], { color: 'ink', rot: 0.4 })) turret.add(mm);
  turret.add(K.m(decal('pl_AUDIOLUX', 0.16, 0.03), M.pl, { pos: [0.36, -0.07, -0.0112] }));
  g.userData.parts = { needleL: vA.needle, needleR: vB.needle };
  g.userData.__w = W;
  consoleCommon(g);
  return done(game, g, { mergeParts: [] });
}, { category: 'broadcast', tags: ['console', 'audio', 'master_control', 'island'], size: [1.2, 1.25, 0.96],
  desc: 'MC island segment: audio board, 8 fader strips + knobs, 2 big VU meters (parts needleL/needleR, rot.z). opts {width, color, vinyl}' });

registerProp('bc_console_monitor', (game, opts = {}) => {
  const g = K.prop('bc_console_monitor');
  const M = mats(game);
  const W = opts.width ?? 1.2;
  const { slope } = consoleBody(game, g, M, W, opts);
  // two monitors on the turret: preview (color bars, never overridden) + program
  const pv = monitorUnit(game, M, { w: 0.42, h: 0.33, d: 0.32, case: 'charcoal', face: 'light', card: 'color_bars', group: opts.previewGroup ?? 'scr_preview', id: 'mc_preview', knobs: 3, plate: 'lbl_PVW' });
  pv.group.position.set(-0.24, 1.25, 0.28); pv.group.rotation.set(-0.08, 0.1, 0);
  const pg = monitorUnit(game, M, { w: 0.42, h: 0.33, d: 0.32, case: 'charcoal', face: 'light', card: opts.card ?? 'station_id', group: opts.group, id: opts.id ?? 'mc_program', knobs: 3, plate: 'lbl_PGM' });
  pg.group.position.set(0.24, 1.25, 0.28); pg.group.rotation.set(-0.08, -0.1, 0);
  g.add(pv.group, pg.group);
  // slope: intercom panel, clock, a few keys, script clipboard
  const rnd = mulberry32(5);
  for (let r = 0; r < 2; r++) for (let i = 0; i < 6; i++) {
    const on = rnd() < 0.3;
    slope.add(K.m(on ? lw(keycap(0.045, 0.04, 0.016, 0.005), 'green') : sw(keycap(0.045, 0.04, 0.016, 0.005), 'light'), on ? M.lit : M.pl, { pos: [-0.44 + i * 0.058, 0.006, -0.12 + r * 0.06] }));
  }
  slope.add(K.m(sw(K.box(0.24, 0.012, 0.3, 0.006), 'cork'), M.mt, { pos: [0.3, 0.012, -0.02], rot: [0, 0.15, 0] }));
  slope.add(K.m(cu(new THREE.PlaneGeometry(0.2, 0.26).rotateX(-HP), 'script'), M.pl, { pos: [0.3, 0.0195, -0.01], rot: [0, 0.15, 0] }));
  slope.add(K.m(K.tube([[0.25, 0.02, -0.15], [0.35, 0.02, -0.165]], 0.006, { seg: 2, radial: 6 }), M.ch, { rot: [0, 0.15, 0] }));
  slope.add(K.m(sw(L([[0, 0], [0.05, 0], [0.05, 0.018], [0.045, 0.024], [0, 0.024]], 0.003, 14), 'ink'), M.pl, { pos: [-0.02, 0.006, 0.12] }));
  slope.add(K.m(sw(lowCyl(0.018, 0.006, 8), 'red'), M.pl, { pos: [-0.02, 0.03, 0.12] }));
  g.userData.__w = W;
  consoleCommon(g);
  return done(game, g);
}, { category: 'broadcast', tags: ['console', 'monitor', 'master_control', 'island', 'screen'], size: [1.2, 1.6, 0.96], hero: true,
  desc: 'MC island segment with preview (color bars, scr_preview, id mc_preview) + program monitors on the turret, intercom keys, rundown clipboard. opts {width, group, card, id, previewGroup}' });

registerProp('bc_console_corner', (game, opts = {}) => {
  const g = K.prop('bc_console_corner');
  const M = mats(game);
  const t = Math.tan(Math.PI / 8) * 0.94; // 45-degree wedge: front narrower than back
  const w0 = opts.front ?? 0.36, w1 = w0 + 2 * t;
  const W = 1;
  const { slope, turret } = consoleBody(game, g, M, W, { ...opts, taper: [w0, w1] });
  const rnd = mulberry32(9);
  for (let r = 0; r < 3; r++) for (let i = 0; i < 4; i++) {
    const on = rnd() < 0.35;
    slope.add(K.m(on ? lw(keycap(0.045, 0.045, 0.018, 0.005), ['amber', 'green', 'cyan'][r]) : sw(keycap(0.045, 0.045, 0.018, 0.005), 'light'), on ? M.lit : M.pl, { pos: [-0.12 + i * 0.08, 0.006, -0.12 + r * 0.08] }));
  }
  turret.add(K.m(decal('lbl_NET', 0.12, 0.03), M.pl, { pos: [0, 0.06, -0.0112] }));
  turret.add(K.m(decal('vuBar', 0.04, 0.08), M.lit, { pos: [-0.08, -0.03, -0.0112] }));
  turret.add(K.m(decal('vuBar', 0.04, 0.08), M.lit, { pos: [0.08, -0.03, -0.0112] }));
  g.userData.colliders = [{ min: [-w1 / 2, 0, -0.5], max: [w1 / 2, 1.25, 0.48] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['console', 'master_control', 'island', 'corner'], size: [1.14, 1.25, 0.96],
  desc: '45-degree console corner wedge (front width 0.36, back ~1.14): side faces at +-22.5 deg, joins two segments turned 45 deg apart. opts {front, color, vinyl}' });

registerProp('bc_console_end', (game, opts = {}) => {
  const g = K.prop('bc_console_end');
  const wood = woodMat(game);
  const M = mats(game);
  const T = 0.05;
  const geo = K.extrude(CON_PROFILE.map(([z, y]) => [z * 1.02, y + (y > 0.5 ? 0.012 : 0)]), T, { bevel: 0.014, round: 0.03, curveSeg: 2, bevelSeg: 1, uv: 1.4 }).rotateY(-HP);
  g.add(K.m(geo, wood));
  g.add(K.m(sw(cbox(T + 0.006, 0.07, 0.9, 0.01), 'black'), M.mt, { pos: [0, 0.035, 0.02] }));
  g.userData.colliders = [{ min: [-T / 2, 0, -0.5], max: [T / 2, 1.26, 0.49] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['console', 'master_control', 'island'], size: [0.05, 1.26, 0.98],
  desc: 'walnut end cheek for the console island (same profile, 5 cm thick); place at a run end, x = +-(segment edge + 0.025)' });

// ---------------------------------------------------------------------------------- patch bay rack
registerProp('bc_patch_bay', (game, opts = {}) => {
  const g = K.prop('bc_patch_bay');
  const M = mats(game);
  const W = 0.62, H = 1.96, D = 0.66, fz = -D / 2;
  const rackC = opts.color ?? 'charcoal';
  g.add(K.m(sw(K.box(W, H - 0.06, D, 0.035), rackC), M.pl, { pos: [0, 0.06 + (H - 0.06) / 2, 0] }));
  g.add(K.m(sw(cbox(W - 0.06, 0.06, D - 0.06, 0.01), 'black'), M.mt, { pos: [0, 0.03, 0.01] }));
  g.add(K.m(sw(K.box(W + 0.02, 0.05, D + 0.02, 0.02, { seg: 1 }), 'ink'), M.pl, { pos: [0, H, 0] }));
  for (const s of [-1, 1]) g.add(K.m(sw(cbox(0.04, H - 0.14, 0.02, 0.006), 'silver'), M.me, { pos: [s * (W / 2 - 0.05), 0.07 + (H - 0.14) / 2 + 0.02, fz - 0.005] }));
  // stack of 1U/2U panels from the top
  let y = H - 0.08;
  const panel = (h, fn) => {
    const cy = y - h / 2;
    g.add(K.m(sw(cbox(W - 0.08, h - 0.008, 0.012, 0.004), 'slate'), M.pl, { pos: [0, cy, fz - 0.012] }));
    for (const s of [-1, 1]) g.add(K.m(sw(lowCyl(0.006, 0.004, 6), 'silver'), M.pl, { pos: [s * (W / 2 - 0.05), cy + s * h * 0.25, fz - 0.018], rot: [-HP, 0, 0] }));
    fn && fn(cy, h);
    y -= h;
  };
  panel(0.1, (cy) => g.add(K.m(decal('vent', 0.4, 0.07), M.pl, { pos: [0, cy, fz - 0.0185] })));
  panel(0.06, (cy) => { g.add(K.m(decal('lbl_SYNC', 0.14, 0.035), M.pl, { pos: [-0.14, cy, fz - 0.0185] })); for (let i = 0; i < 4; i++) g.add(K.m(lw(cbox(0.02, 0.014, 0.01, 0.003), ['green', 'green', 'amber', 'red'][i]), i === 3 ? M.dim : M.lit, { pos: [0.06 + i * 0.045, cy, fz - 0.02] })); });
  const jackRows = [];
  for (let i = 0; i < 6; i++) panel(0.09, (cy) => { g.add(K.m(decal('jacks', 0.48, 0.084), M.pl, { pos: [0, cy, fz - 0.0185] })); jackRows.push(cy); });
  panel(0.16, (cy) => { for (let i = 0; i < 4; i++) g.add(K.m(decal('vuBar', 0.05, 0.12), M.lit, { pos: [-0.15 + i * 0.1, cy, fz - 0.0185] })); });
  panel(0.12, (cy) => { g.add(K.m(sw(cbox(W - 0.1, 0.1, 0.03, 0.008), 'gunmetal'), M.pl, { pos: [0, cy, fz - 0.025] })); g.add(K.m(K.tube([[-0.08, cy, fz - 0.04], [-0.08, cy, fz - 0.07], [0.08, cy, fz - 0.07], [0.08, cy, fz - 0.04]], 0.007, { seg: 8, radial: 5 }), M.ch)); });
  panel(0.2, (cy) => { g.add(K.m(decal('pl_KINETRON', 0.22, 0.041), M.pl, { pos: [0, cy + 0.04, fz - 0.0185] })); g.add(K.m(decal('hv', 0.2, 0.0375), M.pl, { pos: [0, cy - 0.04, fz - 0.0185] })); });
  panel(Math.max(0.1, y - 0.1), (cy, h) => g.add(K.m(decal('vent', 0.44, Math.min(0.3, h - 0.04)), M.pl, { pos: [0, cy, fz - 0.0185] })));
  // patch cords: sagging arcs between jacks, colored plugs
  const rnd = mulberry32(opts.seed ?? 4);
  const cols = ['red', 'gold', 'wztvBlue', 'avocado', 'orange', 'black', 'red', 'teal'];
  const n = opts.cords ?? 6;
  for (let i = 0; i < n; i++) {
    const r0 = Math.floor(rnd() * jackRows.length), r1 = Math.min(jackRows.length - 1, r0 + 1 + Math.floor(rnd() * 3));
    const x0 = -0.22 + Math.floor(rnd() * 16) * 0.0293, x1 = -0.22 + Math.floor(rnd() * 16) * 0.0293;
    const y0 = jackRows[r0] + (rnd() < 0.5 ? 0.024 : -0.024), y1 = jackRows[r1] + (rnd() < 0.5 ? 0.024 : -0.024);
    const sag = 0.08 + rnd() * 0.12;
    const c = cols[i % cols.length];
    const a = [x0, y0, fz - 0.05], b = [x1, y1, fz - 0.05];
    g.add(K.m(sw(K.tube([[x0, y0, fz - 0.03], a, [(x0 + x1) / 2 + (rnd() - 0.5) * 0.1, Math.min(y0, y1) - sag, fz - 0.1 - rnd() * 0.05], b, [x1, y1, fz - 0.03]], 0.0055, { seg: 12, radial: 4 }), c), M.pl));
    for (const [px, py] of [[x0, y0], [x1, y1]]) g.add(K.m(sw(lowCyl(0.009, 0.032, 8), c), M.pl, { pos: [px, py, fz - 0.018], rot: [-HP, 0, 0] }));
  }
  g.userData.colliders = [{ min: [-W / 2 - 0.01, 0, fz - 0.12], max: [W / 2 + 0.01, H + 0.03, D / 2 + 0.01] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['rack', 'patch', 'master_control'], size: [0.64, 1.99, 0.8],
  desc: '19" rack: 6 patch-jack rows with sagging colored cords, lamp row, LED meters, drawer, vents. opts {cords=7, seed, color}' });

// ================================================================================================= STUDIO LIGHTS
// Hanging props are built around their pipe/hook at the origin, then lifted so the lowest point sits at y = 0:
// userData.hang = { pipeY } is the pipe center height above the prop origin (place at gridY - pipeY).
function liftToFloor(g) {
  g.updateMatrixWorld(true);
  const bb = new THREE.Box3().setFromObject(g);
  const dy = -bb.min.y;
  for (const c of g.children) c.position.y += dy;
  return dy;
}
const HANG_AO = { ao: { floor: false, height: 0 } };

// Fresnel lamp head, pivot (tilt axis x) at the body center, lens toward -z. Returns { head, lens }.
function fresnelHead(M, o = {}) {
  const r = o.r ?? 0.13, len = o.len ?? 0.3, bodyC = o.color ?? 'charcoal', gel = o.gel ?? 'tungsten', lit = o.lit !== false;
  const head = new THREE.Group();
  const prof = [[0, 0], [r * 0.72, 0], [r * 0.86, 0.016], [r * 0.9, 0.04]];
  for (let i = 0; i < 3; i++) prof.push([r * 1.03, 0.05 + i * 0.03], [r * 0.93, 0.065 + i * 0.03]);
  prof.push([r * 0.97, 0.16], [r * 0.97, len - 0.035], [r * 1.1, len - 0.025], [r * 1.1, len], [r * 0.86, len], [0, len - 0.004]);
  head.add(K.m(sw(L(prof, 0, 16), bodyC), M.pl, { pos: [0, 0, len / 2], rot: [-HP, 0, 0] }));
  // stepped fresnel lens (lit)
  const lp = [[0, 0.018]];
  for (let i = 1; i <= 4; i++) { const rr = r * 0.84 * (i / 4); lp.push([rr, 0.018 - i * 0.002], [rr, 0.004 + (4 - i) * 0.002]); }
  lp.push([r * 0.84, 0]);
  const lens = K.m(lw(L(lp, 0, 18), gel), lit ? M.lit : M.dim, { pos: [0, 0, -len / 2 + 0.006], rot: [-HP, 0, 0], name: 'lens' });
  lens.userData.noMerge = true;
  lens.userData.noOcclude = true;
  head.add(lens);
  // rear vent cap + handle
  head.add(K.m(sw(L([[0, 0], [r * 0.5, 0], [r * 0.52, 0.02], [r * 0.3, 0.035], [0, 0.036]], 0.006, 12), 'ink'), M.pl, { pos: [0, 0, len / 2 - 0.004], rot: [HP, 0, 0] }));
  head.add(K.m(K.tube([[0, r * 0.55, len / 2 - 0.02], [0, r * 0.75, len / 2 + 0.03], [0, r * 0.2, len / 2 + 0.07], [0, -r * 0.3, len / 2 + 0.05]], 0.008, { seg: 10, radial: 5 }), M.ch));
  // barn doors (4 leaves on a ring)
  const bz = -len / 2 - 0.012, open = o.open ?? 0.55;
  head.add(K.m(sw(K.tube(ring(r * 1.1, 16), 0.01, { seg: 18, radial: 4, closed: true }), 'ink'), M.pl, { pos: [0, 0, bz], rot: [HP, 0, 0] }));
  const leaf = (sx, sy, sz, px, py, rx, ry) => {
    const pv = new THREE.Group();
    pv.position.set(px, py, bz);
    pv.rotation.set(rx, ry, 0);
    pv.add(K.m(sw(cbox(sx, sy, sz, 0.002), 'ink'), M.pl, { pos: [0, 0, -sz / 2] }));
    head.add(pv);
  };
  leaf(r * 2.1, 0.006, r * 0.95, 0, r * 1.06, open, 0);
  leaf(r * 2.1, 0.006, r * 0.8, 0, -r * 1.06, -open, 0);
  leaf(0.006, r * 1.8, r * 0.8, -r * 1.06, 0, 0, open);
  leaf(0.006, r * 1.8, r * 0.8, r * 1.06, 0, 0, -open);
  // brand plate on the side
  const pl = K.m(decal('pl_LUMEX', 0.13, 0.026), M.pl, { pos: [r * 0.975 + 0.002, 0, 0.02], rot: [0, -HP, 0] });
  head.add(pl);
  return { head, lens, len, r };
}
// yoke (U strap) around a head of radius r, pivot at y = 0; up=true: strap goes over the top (hanging)
function yoke(M, r, up = true, color = 'charcoal') {
  const grp = new THREE.Group();
  const s = up ? 1 : -1, w = r + 0.035, t = r + 0.1;
  grp.add(K.m(sw(K.tube([[-w, 0, 0], [-w, s * t * 0.7, 0], [-w * 0.6, s * t, 0], [w * 0.6, s * t, 0], [w, s * t * 0.7, 0], [w, 0, 0]], 0.013, { seg: 18, radial: 6 }), color), M.pl));
  for (const x of [-1, 1]) {
    grp.add(K.m(sw(L([[0, 0], [0.032, 0], [0.034, 0.012], [0.024, 0.03], [0, 0.03]], 0.005, 12), 'ink'), M.pl, { pos: [x * (w + 0.008), 0, 0], rot: [0, 0, -x * HP] }));
  }
  return grp;
}
// C-clamp around a grid pipe (pipe center at the origin, pipe along x); optional pipe stub
function cClamp(M, o = {}) {
  const grp = new THREE.Group();
  const pr = 0.024;
  grp.add(K.m(sw(cbox(0.05, 0.02, 0.1, 0.005), 'ink'), M.pl, { pos: [0, pr + 0.012, 0.005] }));
  grp.add(K.m(sw(cbox(0.05, 0.1, 0.02, 0.005), 'ink'), M.pl, { pos: [0, 0, pr + 0.022] }));
  grp.add(K.m(sw(cbox(0.05, 0.02, 0.05, 0.005), 'ink'), M.pl, { pos: [0, -pr - 0.02, pr + 0.005] }));
  grp.add(K.m(lowCyl(0.006, 0.06, 6), M.ch, { pos: [0, -pr - 0.055, -0.005] }));
  grp.add(K.m(K.tube([[-0.03, -pr - 0.06, -0.005], [0.03, -pr - 0.06, -0.005]], 0.005, { seg: 2, radial: 5 }), M.ch));
  grp.add(K.m(sw(bcyl(0.012, 0.012, 0.05, 0.003, 8), 'ink'), M.pl, { pos: [0, -pr - 0.08, 0.005] }));
  if (o.pipe) grp.add(K.m(sw(bcyl(pr, pr, o.pipe, 0.003, 12), 'silver'), M.me, { pos: [-o.pipe / 2, 0, 0], rot: [0, 0, -HP] }));
  return grp;
}

registerProp('bc_light_fresnel', (game, opts = {}) => {
  const g = K.prop('bc_light_fresnel');
  const M = mats(game);
  const { head, len, r } = fresnelHead(M, { gel: opts.gel, lit: opts.lit, color: opts.color });
  const tiltG = new THREE.Group();
  tiltG.rotation.x = -(opts.tilt ?? 0.6);
  tiltG.add(head);
  tiltG.userData.noMerge = true;
  const rig = new THREE.Group();
  rig.position.y = -0.36;
  rig.add(tiltG, yoke(M, r, true));
  g.add(rig);
  const clamp = cClamp(M, { pipe: opts.pipe ?? 0.5 });
  g.add(clamp);
  g.add(K.m(bcyl(0.012, 0.012, 0.13, 0.003, 8), M.ch, { pos: [0, -0.24, 0] }));
  // safety cable loop
  g.add(K.m(K.tube([[0.03, 0, 0.03], [0.07, -0.08, 0.03], [0.1, -0.25, 0.02], [r + 0.05, -0.36, 0]], 0.003, { seg: 12, radial: 3 }), M.ch));
  const dy = liftToFloor(g);
  g.userData.hang = { pipeY: +dy.toFixed(3) };
  const t = opts.tilt ?? 0.6;
  g.userData.aim = { pos: [0, dy - 0.36, 0], dir: [0, -Math.sin(t), -Math.cos(t)] };
  g.userData.parts = { head: tiltG, lens: head.children.find((c) => c.name === 'lens') };
  g.userData.lampMats = { on: M.lit, off: M.dim };
  g.userData.colliders = [];
  if (opts.anchor) g.userData.lightAnchors = [{ pos: [0, dy - 0.6, -0.3], color: LIT[opts.gel ?? 'tungsten'], intensity: 3, distance: 9 }];
  void len;
  return done(game, g, { finish: HANG_AO, mergeParts: [tiltG] });
}, { category: 'broadcast', tags: ['light', 'studio', 'grid', 'hanging'], size: [0.5, 0.7, 0.5],
  desc: 'hanging Fresnel on a yoke + C-clamp (pipe stub along x): barn doors, glowing stepped lens (gel). y=0 lowest point, userData.hang.pipeY, userData.aim {pos, dir}. parts head (rot.x) / lens (setLamp). opts {gel:tungsten|magenta|amber|cyan, tilt, lit, pipe, anchor}' });

registerProp('bc_light_scoop', (game, opts = {}) => {
  const g = K.prop('bc_light_scoop');
  const M = mats(game);
  const R0 = 0.24, dep = 0.24;
  const head = new THREE.Group();
  const shell = [];
  for (let i = 0; i <= 8; i++) { const t = i / 8; shell.push([R0 * Math.sqrt(t) + 0.02, t * dep]); }
  shell[0] = [0, 0];
  const outer = [[0, 0], ...shell.slice(1), [R0 + 0.035, dep + 0.005], [R0 + 0.035, dep + 0.025], [R0 + 0.01, dep + 0.025]];
  head.add(K.m(sw(L(outer, 0.004, 22), opts.color ?? 'gunmetal'), M.pl, { pos: [0, 0, dep / 2], rot: [-HP, 0, 0] }));
  const inner = shell.map(([x, y]) => [Math.max(0, x - 0.012), y + 0.006]);
  const lining = K.m(lw(L(inner, 0, 22), opts.gel ?? 'softWhite'), opts.lit === false ? M.dim : M.soft, { pos: [0, 0, dep / 2 - 0.002], rot: [-HP, 0, 0], name: 'lens' });
  lining.geometry = lining.geometry.clone();
  const idx = lining.geometry.index.array; for (let i = 0; i < idx.length; i += 3) { const t2 = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t2; }
  lining.geometry.computeVertexNormals();
  lining.userData.noMerge = true; lining.userData.noOcclude = true;
  head.add(lining);
  head.add(K.m(lw(lowSphere(0.05, 10, 8), 'tungsten'), opts.lit === false ? M.dim : M.lit, { pos: [0, 0, -dep * 0.35] }));
  head.add(K.m(sw(bcyl(0.04, 0.05, 0.06, 0.008, 12), 'ink'), M.pl, { pos: [0, 0, dep / 2 + 0.05], rot: [-HP, 0, 0] }));
  const tiltG = new THREE.Group();
  tiltG.rotation.x = -(opts.tilt ?? 0.7);
  tiltG.add(head);
  tiltG.userData.noMerge = true;
  const rig = new THREE.Group();
  rig.position.y = -0.42;
  rig.add(tiltG, yoke(M, R0 + 0.02, true));
  g.add(rig);
  g.add(cClamp(M, { pipe: opts.pipe ?? 0.5 }));
  g.add(K.m(bcyl(0.012, 0.012, 0.1, 0.003, 8), M.ch, { pos: [0, -0.2, 0] }));
  const dy = liftToFloor(g);
  g.userData.hang = { pipeY: +dy.toFixed(3) };
  const t = opts.tilt ?? 0.7;
  g.userData.aim = { pos: [0, dy - 0.42, 0], dir: [0, -Math.sin(t), -Math.cos(t)] };
  g.userData.parts = { head: tiltG, lens: lining };
  g.userData.lampMats = { on: M.soft, off: M.dim };
  g.userData.colliders = [];
  return done(game, g, { finish: HANG_AO, mergeParts: [tiltG] });
}, { category: 'broadcast', tags: ['light', 'studio', 'grid', 'hanging'], size: [0.6, 0.8, 0.6],
  desc: 'hanging scoop floodlight: big bowl with a glowing white lining + bulb, yoke, C-clamp. hang.pipeY / aim like the Fresnel. opts {tilt, lit, gel, color, pipe}' });

// tripod light stand (floor), top spigot at height h; returns Group
function tripodStand(M, h, o = {}) {
  const grp = new THREE.Group();
  const cy = o.collar ?? 0.62, fr = o.foot ?? 0.46, legC = o.legColor ?? 'charcoal';
  grp.add(K.m(sw(bcyl(0.03, 0.03, 0.09, 0.006, 12), legC), M.pl, { pos: [0, cy - 0.05, 0] }));
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + (o.rot ?? 0);
    const foot = [Math.cos(a) * fr, 0.025, Math.sin(a) * fr];
    const top = [Math.cos(a) * 0.035, cy, Math.sin(a) * 0.035];
    grp.add(along((l) => sw(bcyl(0.014, 0.014, l, 0.003, 6), legC), M.pl, foot, top));
    const brace0 = [Math.cos(a) * fr * 0.55, cy * 0.45, Math.sin(a) * fr * 0.55];
    grp.add(along((l) => lowCyl(0.007, l, 6), M.ch, brace0, [0, cy * 0.3, 0]));
    grp.add(K.m(sw(L([[0, 0], [0.026, 0], [0.024, 0.02], [0.012, 0.03], [0, 0.03]], 0.004, 10), 'rubber'), M.mt, { pos: [foot[0] * 1.02, 0, foot[2] * 1.02] }));
  }
  grp.add(K.m(sw(bcyl(0.022, 0.022, cy + 0.02, 0.004, 10), legC), M.pl, { pos: [0, cy * 0.3, 0] }));
  grp.add(K.m(bcyl(0.015, 0.015, h - cy, 0.003, 10), M.ch, { pos: [0, cy, 0] }));
  grp.add(K.m(sw(bcyl(0.026, 0.026, 0.05, 0.006, 10), legC), M.pl, { pos: [0, cy + (h - cy) * 0.45, 0] }));
  grp.add(K.m(sw(lowCyl(0.006, 0.05, 6), 'ink'), M.pl, { pos: [0.03, cy + (h - cy) * 0.45 + 0.025, 0], rot: [0, 0, -HP] }));
  return grp;
}

registerProp('bc_light_tripod', (game, opts = {}) => {
  const g = K.prop('bc_light_tripod');
  const M = mats(game);
  const h = opts.height ?? 1.55;
  g.add(tripodStand(M, h, { rot: 0.4 }));
  const { head, r } = fresnelHead(M, { r: 0.14, len: 0.3, gel: opts.gel, lit: opts.lit, color: opts.color ?? 'charcoal' });
  const tiltG = new THREE.Group();
  tiltG.rotation.x = -(opts.tilt ?? 0.18);
  tiltG.add(head);
  tiltG.userData.noMerge = true;
  const rig = new THREE.Group();
  rig.position.y = h + r + 0.1;
  rig.add(tiltG, yoke(M, r, false));
  g.add(rig);
  // power cable down the pole to the floor
  g.add(K.m(sw(K.tube([[0.05, h + r + 0.05, 0.12], [0.06, h - 0.1, 0.06], [0.03, 1.0, 0.03], [0.04, 0.6, 0.05], [0.12, 0.08, 0.2], [0.3, 0.012, 0.45], [0.55, 0.012, 0.5]], 0.009, { seg: 18, radial: 4 }), 'ink'), M.pl));
  g.userData.parts = { head: tiltG, lens: head.children.find((c) => c.name === 'lens') };
  g.userData.lampMats = { on: M.lit, off: M.dim };
  g.userData.aim = { pos: [0, h + r + 0.1, 0], dir: [0, -Math.sin(opts.tilt ?? 0.18), -Math.cos(opts.tilt ?? 0.18)] };
  g.userData.colliders = [{ min: [-0.3, 0, -0.3], max: [0.3, h + 0.35, 0.3] }];
  if (opts.anchor !== false && opts.lit !== false) g.userData.lightAnchors = [{ pos: [0, h + r + 0.05, -0.45], color: LIT[opts.gel ?? 'tungsten'], intensity: 2.2, distance: 6 }];
  return done(game, g, { mergeParts: [tiltG] });
}, { category: 'broadcast', tags: ['light', 'studio', 'stand', 'tripod'], size: [0.95, 1.95, 0.95],
  desc: 'Fresnel on a chrome tripod stand: barn doors, lit lens (gel), cable to the floor, point-light anchor in front. parts head/lens. opts {height, tilt, gel, lit, anchor=true}' });

registerProp('bc_light_softbox', (game, opts = {}) => {
  const g = K.prop('bc_light_softbox');
  const M = mats(game);
  const h = opts.height ?? 1.2;
  // rolling 3-caster stand
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.3;
    g.add(along((l) => sw(cbox(0.035, l, 0.03, 0.008), 'charcoal').translate(0, l / 2, 0), M.pl, [0, 0.1, 0], [Math.cos(a) * 0.42, 0.08, Math.sin(a) * 0.42]));
    const c = caster(M, 0.03);
    c.position.set(Math.cos(a) * 0.42, 0, Math.sin(a) * 0.42);
    g.add(c);
  }
  g.add(K.m(sw(bcyl(0.05, 0.06, 0.08, 0.01, 12), 'charcoal'), M.pl, { pos: [0, 0.06, 0] }));
  g.add(K.m(sw(bcyl(0.024, 0.024, 0.6, 0.004, 10), 'charcoal'), M.pl, { pos: [0, 0.12, 0] }));
  g.add(K.m(bcyl(0.017, 0.017, h - 0.7, 0.003, 10), M.ch, { pos: [0, 0.7, 0] }));
  g.add(K.m(sw(bcyl(0.03, 0.03, 0.05, 0.006, 10), 'charcoal'), M.pl, { pos: [0, 0.68, 0] }));
  // soft light: tapered painted shell, deep front rim, concave glowing reflector, lamp lip with tube lamps
  const W = 0.7, Hh = 0.52, D = 0.34;
  const shellC = opts.color ?? 'sand';
  const lit = opts.lit !== false;
  const head = new THREE.Group();
  head.rotation.x = -(opts.tilt ?? 0.15);
  head.userData.noMerge = true;
  head.add(K.m(sw(K.taper(K.box(W, Hh, D * 0.6, 0.06), { axis: 'z', k: 0.6 }), shellC), M.pl, { pos: [0, 0, 0.04] }));
  head.add(K.m(sw(frame(W + 0.02, Hh + 0.02, 0.04, 0.12, 0.06, 0.03, { bevel: 0.012 }), shellC), M.pl, { pos: [0, 0, -0.102] }));
  const rg = new THREE.PlaneGeometry(W - 0.08, Hh - 0.08, 8, 1);
  const rp = rg.attributes.position;
  for (let i = 0; i < rp.count; i++) { const x = rp.getX(i) / ((W - 0.08) / 2); rp.setZ(i, -0.03 * (1 - x * x)); }
  rg.rotateY(Math.PI);
  const refl = K.m(lw(rg, 'softWhite'), lit ? M.soft : M.dim, { pos: [0, 0, -0.1], name: 'lens' });
  refl.userData.noMerge = true; refl.userData.noOcclude = true;
  head.add(refl);
  head.add(K.m(sw(cbox(W - 0.05, 0.085, 0.06, 0.02), 'ink'), M.pl, { pos: [0, -Hh / 2 + 0.065, -0.135] }));
  head.add(K.m(lw(K.tube([[-W / 2 + 0.09, -Hh / 2 + 0.105, -0.12], [W / 2 - 0.09, -Hh / 2 + 0.105, -0.12]], 0.02, { seg: 2, radial: 8 }), 'tungsten'), lit ? M.lit : M.dim));
  head.add(K.m(K.tube([[-0.1, Hh / 2 + 0.005, 0.0], [-0.08, Hh / 2 + 0.06, 0.0], [0.08, Hh / 2 + 0.06, 0.0], [0.1, Hh / 2 + 0.005, 0.0]], 0.01, { seg: 10, radial: 5 }), M.ch));
  head.add(K.m(decal('pl_LUMEX', 0.14, 0.028), M.pl, { pos: [0.18, Hh / 2 - 0.018, -0.163] }));
  head.add(K.m(decal('vent', 0.2, 0.12), M.pl, { pos: [0, 0.03, 0.172], rot: [0, Math.PI, 0] }));
  const rig = new THREE.Group();
  rig.add(K.m(sw(K.tube([[-W / 2 - 0.035, Hh * 0.05, 0], [-W / 2 - 0.035, -Hh / 2 - 0.05, 0], [0, -Hh / 2 - 0.09, 0], [W / 2 + 0.035, -Hh / 2 - 0.05, 0], [W / 2 + 0.035, Hh * 0.05, 0]], 0.014, { seg: 12, radial: 5 }), 'charcoal'), M.pl));
  for (const x of [-1, 1]) rig.add(K.m(sw(L([[0, 0], [0.036, 0], [0.038, 0.014], [0.026, 0.034], [0, 0.034]], 0.005, 12), 'ink'), M.pl, { pos: [x * (W / 2 + 0.04), 0, 0], rot: [0, 0, -x * HP] }));
  rig.add(head);
  rig.position.y = h + Hh / 2 + 0.07;
  g.add(rig);
  g.userData.parts = { head, lens: refl };
  g.userData.lampMats = { on: M.soft, off: M.dim };
  g.userData.colliders = [{ min: [-0.4, 0, -0.4], max: [0.4, h + Hh + 0.12, 0.4] }];
  if (opts.anchor) g.userData.lightAnchors = [{ pos: [0, h + Hh / 2, -0.6], color: '#FFE6C0', intensity: 2, distance: 5 }];
  return done(game, g, { mergeParts: [head] });
}, { category: 'broadcast', tags: ['light', 'studio', 'stand', 'softlight'], size: [0.86, 1.9, 0.86],
  desc: '70s soft light: sand shell, deep rim, concave glowing reflector (parts.lens), tube lamps behind a lip, on a rolling 3-caster stand. opts {height, tilt, lit, color, anchor}' });

registerProp('bc_grid_clamp', (game, opts = {}) => {
  const g = K.prop('bc_grid_clamp');
  const M = mats(game);
  g.add(cClamp(M, { pipe: opts.pipe ?? 0.4 }));
  g.add(K.m(K.tube([[0.03, 0, 0.03], [0.06, -0.08, 0.04], [0.02, -0.14, 0.03], [-0.02, -0.08, 0.03], [-0.03, 0, 0.03]], 0.003, { seg: 14, radial: 3 }), M.ch));
  const dy = liftToFloor(g);
  g.userData.hang = { pipeY: +dy.toFixed(3) };
  g.userData.colliders = [];
  return done(game, g, { finish: HANG_AO });
}, { category: 'broadcast', tags: ['grid', 'clamp', 'hanging'], size: [0.4, 0.16, 0.1], desc: 'C-clamp + safety loop on a 0.4 m pipe stub (pipe along x). hang.pipeY. opts {pipe}' });

registerProp('bc_grid_batten', (game, opts = {}) => {
  const g = K.prop('bc_grid_batten');
  const M = mats(game);
  const len = opts.len ?? 3;
  g.add(K.m(sw(bcyl(0.024, 0.024, len, 0.004, 12), 'silver'), M.me, { pos: [-len / 2, 0, 0], rot: [0, 0, -HP] }));
  // plugging strip (raceway) with numbered outlets
  g.add(K.m(sw(K.box(len * 0.92, 0.07, 0.06, 0.012, { seg: 1 }), 'charcoal'), M.pl, { pos: [0, -0.07, 0] }));
  const n = Math.max(2, Math.round(len / 0.5));
  for (let i = 0; i < n; i++) {
    const x = -len * 0.42 + (i / (n - 1)) * len * 0.84;
    g.add(K.m(sw(cbox(0.06, 0.04, 0.02, 0.005), 'ink'), M.pl, { pos: [x, -0.07, -0.035] }));
    g.add(K.m(decal('num' + ((i % 4) + 1), 0.026, 0.026), M.pl, { pos: [x + 0.05, -0.07, -0.0305] }));
    // pigtail tails dangling
    if (i % 2 === 0) g.add(K.m(sw(K.tube([[x, -0.1, -0.03], [x + 0.02, -0.25, -0.05], [x + 0.05, -0.35, -0.03]], 0.008, { seg: 8, radial: 4 }), 'ink'), M.pl));
  }
  // cable bundle tied along the pipe with gaffer tape
  g.add(K.m(sw(K.tube([[-len / 2, 0.035, 0.02], [-len / 4, 0.04, 0.025], [0, 0.035, 0.02], [len / 4, 0.042, 0.022], [len / 2, 0.035, 0.02]], 0.014, { seg: 20, radial: 5 }), 'ink'), M.pl));
  for (let i = 0; i < 4; i++) g.add(K.m(cu(bcyl(0.042, 0.042, 0.04, 0.002, 10), 'tape'), M.pl, { pos: [-len * 0.4 + i * len * 0.27, 0.012, 0.01], rot: [0, 0, -HP] }));
  for (const x of [-len * 0.45, len * 0.45]) g.add(cClamp(M, {}).translateX(x));
  const dy = liftToFloor(g);
  g.userData.hang = { pipeY: +dy.toFixed(3) };
  g.userData.colliders = [];
  return done(game, g, { finish: HANG_AO });
}, { category: 'broadcast', tags: ['grid', 'batten', 'hanging', 'studio'], size: [3, 0.5, 0.12],
  desc: 'lighting batten: chrome pipe (along x) with a numbered plugging strip, dangling pigtails, taped cable bundle, clamps. hang.pipeY. opts {len=3}' });

// ================================================================================================= STUDIO FLOOR
registerProp('bc_boom_mic', (game, opts = {}) => {
  const g = K.prop('bc_boom_mic');
  const M = mats(game);
  const chC = opts.color ?? 'gold';
  // tricycle chassis: two rear wheels, one steerable front wheel, platform + seat
  const wheel = (x, z, r) => {
    g.add(K.m(sw(L([[0, -0.03], [r * 0.8, -0.03], [r, -0.01], [r, 0.01], [r * 0.8, 0.03], [0, 0.03]], 0.008, 16), 'rubber'), M.mt, { pos: [x, r, z], rot: [0, 0, HP] }));
    g.add(K.m(sw(bcyl(r * 0.45, r * 0.45, 0.066, 0.006, 12), chC), M.pl, { pos: [x - 0.033, r, z], rot: [0, 0, -HP] }));
  };
  wheel(-0.42, 0.34, 0.11); wheel(0.42, 0.34, 0.11); wheel(0, -0.48, 0.1);
  // chassis plate (world x,z) -> shape (x, -z): rear axle at z = +0.34, nose over the front wheel
  const chassis = [[-0.46, 0.44], [0.46, 0.44], [0.46, 0.2], [0.16, -0.5], [-0.16, -0.5], [-0.46, 0.2]].map(([x, z]) => [x, -z]);
  g.add(K.m(sw(K.extrude(chassis, 0.075, { bevel: 0.024, round: 0.09, curveSeg: 2, bevelSeg: 1 }).rotateX(-HP), chC), M.pl, { pos: [0, 0.2, 0] }));
  g.add(K.m(sw(cbox(0.72, 0.03, 0.26, 0.01), 'slate'), M.mt, { pos: [0, 0.252, 0.28] }));
  for (const x of [-0.42, 0.42]) g.add(K.m(sw(cbox(0.05, 0.11, 0.08, 0.012), chC), M.pl, { pos: [x * 0.92, 0.18, 0.34] }));
  g.add(K.m(sw(bcyl(0.02, 0.02, 0.12, 0.005, 10), 'charcoal'), M.pl, { pos: [0, 0.13, -0.48] }));
  // operator seat on a post
  g.add(K.m(bcyl(0.018, 0.018, 0.34, 0.004, 8), M.ch, { pos: [0.3, 0.26, 0.3] }));
  g.add(K.m(K.cushion(0.3, 0.07, 0.28, { puff: 0.02 }), K.mat(game, 'vinyl', '#ffffff', { map: K.tex.pebble('#5A3A22') }), { pos: [0.3, 0.63, 0.3] }));
  // column: charcoal lower + chrome telescoping upper
  g.add(K.m(sw(L([[0, 0], [0.13, 0], [0.13, 0.03], [0.09, 0.07], [0.08, 0.12], [0.075, 0.9], [0.09, 0.93], [0.09, 0.97], [0, 0.97]], 0.01, 16), 'charcoal'), M.pl, { pos: [0, 0.23, 0] }));
  g.add(K.m(bcyl(0.05, 0.05, 0.42, 0.005, 14), M.ch, { pos: [0, 1.18, 0] }));
  g.add(K.m(decal('pl_FISHER', 0.14, 0.026), M.pl, { pos: [0, 0.7, -0.0775] }));
  // boom (part): pivot cradle, telescoping arm forward, counterweight + crank wheel behind, mic on a yoke
  const boom = new THREE.Group();
  boom.position.set(0, 1.64, 0);
  boom.rotation.set(opts.raise ?? 0.12, opts.swing ?? 0, 0);
  boom.userData.noMerge = true;
  g.add(boom);
  boom.add(K.m(sw(L([[0, 0], [0.09, 0], [0.1, 0.02], [0.08, 0.05], [0, 0.05]], 0.008, 14), 'charcoal'), M.pl, { pos: [0, -0.05, 0] }));
  for (const s of [-1, 1]) boom.add(K.m(sw(cbox(0.03, 0.14, 0.16, 0.01), 'charcoal'), M.pl, { pos: [s * 0.07, 0.04, 0] }));
  const reach = opts.reach ?? 2.2;
  const secs = [[0.056, 0.9, chC], [0.043, 0.9, null], [0.033, reach - 1.4, null]];
  let z = 0.55, tipZ = 0;
  for (const [r, l, c] of secs) {
    boom.add(K.m(sw(bcyl(r, r, l, 0.004, c ? 14 : 12), c ?? 'silver'), c ? M.pl : M.me, { pos: [0, 0.08, z], rot: [-HP, 0, 0] }));
    boom.add(K.m(sw(bcyl(r + 0.008, r + 0.008, 0.03, 0.004, 12), 'ink'), M.pl, { pos: [0, 0.08, z - l + 0.03], rot: [-HP, 0, 0] }));
    tipZ = z - l;
    z -= l - 0.1;
  }
  boom.add(K.m(sw(cbox(0.1, 0.1, 0.16, 0.02), 'charcoal'), M.pl, { pos: [0, 0.08, 0.6] }));
  boom.add(K.m(bcyl(0.012, 0.012, 0.3, 0.003, 8), M.ch, { pos: [0, 0.08, 0.6], rot: [HP, 0, 0] }));
  for (let i = 0; i < 3; i++) boom.add(K.m(sw(bcyl(0.1 - i * 0.012, 0.1 - i * 0.012, 0.045, 0.01, 18), i === 1 ? 'red' : 'charcoal'), M.pl, { pos: [0, 0.08, 0.7 + i * 0.05], rot: [HP, 0, 0] }));
  boom.add(K.m(sw(K.tube(ring(0.13, 16), 0.012, { seg: 20, radial: 5, closed: true }), 'ink'), M.pl, { pos: [0.12, 0.08, 0.48], rot: [0, 0, HP] }));
  boom.add(K.m(K.tube([[0.12, 0.08, 0.48], [0.12, 0.2, 0.48]], 0.008, { seg: 2, radial: 5 }), M.ch));
  boom.add(K.m(sw(lowCyl(0.012, 0.06, 8), 'rubber'), M.mt, { pos: [0.12, 0.2, 0.48], rot: [0, 0, -HP] }));
  // mic cable along the arm
  boom.add(K.m(sw(K.tube([[0, 0.02, 0.6], [0, 0.03, 0.2], [0, 0.04, -0.6], [0, 0.03, tipZ + 0.3], [0, -0.03, tipZ + 0.05]], 0.007, { seg: 20, radial: 4 }), 'ink'), M.pl));
  // big ribbon mic in a yoke at the tip
  const mic = new THREE.Group();
  mic.position.set(0, 0.08, tipZ);
  mic.rotation.x = -(opts.micTilt ?? 0.5);
  mic.scale.setScalar(1.45);
  mic.userData.noMerge = true;
  boom.add(mic);
  mic.add(K.m(K.tube([[-0.07, -0.02, 0], [-0.075, -0.1, 0], [-0.07, -0.18, 0]], 0.007, { seg: 6, radial: 5 }), M.ch));
  mic.add(K.m(K.tube([[0.07, -0.02, 0], [0.075, -0.1, 0], [0.07, -0.18, 0]], 0.007, { seg: 6, radial: 5 }), M.ch));
  mic.add(K.m(K.tube([[-0.07, -0.02, 0], [0, 0.01, 0], [0.07, -0.02, 0]], 0.007, { seg: 6, radial: 5 }), M.ch));
  const capsule = [[0, 0], [0.03, 0.005], [0.05, 0.03], [0.058, 0.07], [0.058, 0.14], [0.05, 0.18], [0.03, 0.205], [0, 0.21]];
  mic.add(K.m(sw(L(capsule, 0.01, 16), 'silver'), M.me, { pos: [0, -0.24, 0] }));
  for (let i = 0; i < 5; i++) mic.add(K.m(sw(K.tube(ring(0.06, 14), 0.003, { seg: 16, radial: 3, closed: true }), 'charcoal'), M.pl, { pos: [0, -0.2 + i * 0.03, 0] }));
  mic.add(K.m(sw(bcyl(0.02, 0.024, 0.05, 0.004, 10), 'ink'), M.pl, { pos: [0, -0.285, 0] }));
  mic.add(K.m(discDecal('logo13', 0.035, 16), M.pl, { pos: [0, -0.17, -0.06] }));
  g.userData.parts = { boom, mic };
  g.userData.colliders = [{ min: [-0.55, 0, -0.6], max: [0.55, 1.75, 0.5] }];
  return done(game, g, { mergeParts: [boom, mic] });
}, { category: 'broadcast', tags: ['boom', 'mic', 'studio_a', 'hero'], size: [1.1, 1.9, 3.0], hero: true,
  desc: 'Fisher-style boom mic dolly: gold tricycle chassis, seat, telescoping arm reaching -z, counterweight + crank, ribbon mic in a yoke. parts boom (rot.y swing, rot.x raise) / mic. opts {reach, raise, swing, micTilt, color}' });

// cable spaghetti: several floor cables snaking inside w x d, connectors at the ends, gaffer tape crossings
function floorCable(rnd, x0, z0, x1, z1, r, bends = 5) {
  const pts = [];
  for (let i = 0; i <= bends; i++) {
    const t = i / bends;
    const wob = i === 0 || i === bends ? 0 : 1;
    pts.push([x0 + (x1 - x0) * t + (rnd() - 0.5) * 0.5 * wob, r + (wob ? rnd() * 0.012 : 0), z0 + (z1 - z0) * t + (rnd() - 0.5) * 0.45 * wob]);
  }
  return pts;
}
registerProp('bc_cable_spaghetti', (game, opts = {}) => {
  const g = K.prop('bc_cable_spaghetti');
  const M = mats(game);
  const w = opts.w ?? 2.4, d = opts.d ?? 1.2;
  const rnd = mulberry32(opts.seed ?? 7);
  const cols = ['ink', 'orange', 'wztvBlue', 'mustard', 'ink', 'red'];
  const n = opts.count ?? 5;
  for (let i = 0; i < n; i++) {
    const r = 0.019 + rnd() * 0.01;
    const pts = floorCable(rnd, -w / 2, (rnd() - 0.5) * d, w / 2, (rnd() - 0.5) * d, r, 6);
    if (rnd() < 0.4) { const k = 2 + Math.floor(rnd() * 3); const [px, , pz] = pts[k]; pts.splice(k + 1, 0, [px + 0.18, r + 0.01, pz + 0.12], [px + 0.02, r + 0.02, pz + 0.24], [px - 0.12, r + 0.01, pz + 0.08]); }
    const c = cols[i % cols.length];
    g.add(K.m(sw(K.tube(pts, r, { seg: 28, radial: 6 }), c), M.mt));
    for (const [px, , pz] of [pts[0], pts[pts.length - 1]]) g.add(K.m(sw(bcyl(r * 1.6, r * 1.6, 0.08, 0.005, 10), i % 2 ? 'charcoal' : 'silver'), M.pl, { pos: [px, r * 1.6, pz], rot: [0, 0, px < 0 ? HP : -HP] }));
  }
  for (let i = 0; i < 3; i++) {
    const x = -w * 0.3 + i * w * 0.3;
    g.add(K.m(cu(cbox(0.1, 0.005, d * 0.7, 0.001), 'tape'), M.mt, { pos: [x, 0.052, 0], rot: [0, (rnd() - 0.5) * 0.3, 0] }));
  }
  g.userData.colliders = [];
  return done(game, g, { finish: { ao: { strength: 0.55, height: 0.02, heightStrength: 0.2 } } });
}, { category: 'broadcast', tags: ['cable', 'floor', 'studio'], size: [2.6, 0.05, 1.4], desc: 'walkable floor cable spaghetti (no collider): 5 cables, connectors, gaffer-tape strips. opts {w, d, count, seed}' });

registerProp('bc_cable_coil', (game, opts = {}) => {
  const g = K.prop('bc_cable_coil');
  const M = mats(game);
  const r = 0.016, c = opts.color ?? 'orange';
  const pts = [];
  for (let i = 0; i <= 80; i++) { const t = i / 80, a = t * TAU * 5; const rr = 0.24 + Math.sin(a * 0.7) * 0.02; pts.push([Math.cos(a) * rr, r + t * r * 7 + Math.sin(a * 3) * 0.004, Math.sin(a) * rr * 0.92]); }
  pts.push([0.3, r * 3, 0.1], [0.45, r, 0.3], [0.7, r, 0.35]);
  g.add(K.m(sw(K.tube(pts, r * 1.3, { seg: 100, radial: 5 }), c), M.mt));
  g.add(K.m(sw(bcyl(r * 1.8, r * 1.8, 0.08, 0.004, 10), 'charcoal'), M.pl, { pos: [0.78, r * 1.8, 0.35], rot: [0, 0, -HP] }));
  g.add(K.m(cu(cbox(0.06, 0.006, 0.12, 0.002), 'tape'), M.mt, { pos: [0.22, r * 10, 0.0], rot: [0, 0.3, 0.12] }));
  g.userData.colliders = [];
  return done(game, g, { finish: { ao: { strength: 0.6, height: 0.03, heightStrength: 0.2 } } });
}, { category: 'broadcast', tags: ['cable', 'floor'], size: [1.1, 0.16, 0.6], desc: 'coiled orange cable on the floor with a trailing end + connector, taped (no collider). opts {color}' });

// ================================================================================================= CASES
function flightCase(game, M, parent, o = {}) {
  const S = { sm: [0.5, 0.34, 0.36], md: [0.8, 0.5, 0.5], lg: [1.1, 0.68, 0.62], tall: [0.62, 1.1, 0.56] }[o.size ?? 'md'];
  const [w, h, d] = S;
  const grp = new THREE.Group();
  const tolex = K.mat(game, 'paint', '#ffffff', { map: K.tex.pebble(o.color ?? '#2E2934'), rim: 0.07, rimPower: 3.5, rough: 0.7 });
  const y0 = o.size === 'tall' ? 0.09 : 0.012;
  grp.add(K.m(K.box(w - 0.02, h - 0.02, d - 0.02, 0.012, { uv: 2 }), tolex, { pos: [0, y0 + h / 2, 0] }));
  // aluminum edge extrusions + ball corners
  const e = 0.024;
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) {
    grp.add(K.m(sw(cbox(w - 0.04, e, e, 0.005), 'silver'), M.me, { pos: [0, y0 + h / 2 + sy * (h / 2 - e / 2), sx * (d / 2 - e / 2)] }));
    grp.add(K.m(sw(cbox(e, h - 0.04, e, 0.005), 'silver'), M.me, { pos: [sx * (w / 2 - e / 2), y0 + h / 2, sy * (d / 2 - e / 2)] }));
    grp.add(K.m(sw(cbox(e, e, d - 0.04, 0.005), 'silver'), M.me, { pos: [sx * (w / 2 - e / 2), y0 + h / 2 + sy * (h / 2 - e / 2), 0] }));
  }
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) grp.add(K.m(lowSphere(0.024, 8, 6), M.ch, { pos: [sx * (w / 2 - 0.012), y0 + h / 2 + sy * (h / 2 - 0.012), sz * (d / 2 - 0.012)] }));
  // lid seam valance + latches + side dish handles
  const sy = y0 + h * 0.7;
  grp.add(K.m(sw(cbox(w - 0.03, 0.018, 0.006, 0.002), 'silver'), M.me, { pos: [0, sy, -d / 2 - 0.001] }));
  grp.add(K.m(sw(cbox(w - 0.03, 0.018, 0.006, 0.002), 'silver'), M.me, { pos: [0, sy, d / 2 + 0.001] }));
  const nl = w > 0.7 ? 3 : 2;
  for (let i = 0; i < nl; i++) {
    const x = (i - (nl - 1) / 2) * (w * 0.6 / (nl - 1 || 1));
    grp.add(K.m(sw(cbox(0.07, 0.07, 0.014, 0.006), 'silver'), M.me, { pos: [x, sy, -d / 2 - 0.006] }));
    grp.add(K.m(sw(lowCyl(0.02, 0.008, 10), 'steel'), M.me, { pos: [x, sy, -d / 2 - 0.013], rot: [-HP, 0, 0] }));
  }
  for (const s of [-1, 1]) {
    grp.add(K.m(sw(cbox(0.012, 0.09, 0.16, 0.004), 'ink'), M.pl, { pos: [s * (w / 2 + 0.001), sy - h * 0.25, 0] }));
    grp.add(K.m(K.tube([[s * (w / 2 + 0.004), sy - h * 0.25, -0.06], [s * (w / 2 + 0.018), sy - h * 0.25, -0.05], [s * (w / 2 + 0.018), sy - h * 0.25, 0.05], [s * (w / 2 + 0.004), sy - h * 0.25, 0.06]], 0.007, { seg: 8, radial: 5 }), M.ch));
  }
  // stenciled tags
  grp.add(K.m(decal(o.tag ?? 'pl_STUDIOA', Math.min(0.32, w * 0.45), Math.min(0.32, w * 0.45) * 0.1875), M.pl, { pos: [-w * 0.18, y0 + h * 0.36, -d / 2 + 0.009] }));
  grp.add(K.m(decal('caseTag', Math.min(0.14, h * 0.4), Math.min(0.14, h * 0.4)), M.pl, { pos: [w * 0.26, y0 + h * 0.36, -d / 2 + 0.009] }));
  if (o.size !== 'sm') grp.add(K.m(cu(new THREE.PlaneGeometry(0.3, 0.056).rotateX(-HP), 'pl_PROPERTY'), M.pl, { pos: [0.05, y0 + h - 0.009, 0.02], rot: [0, 0.1, 0] }));
  if (o.size === 'tall') for (const sx of [-1, 1]) for (const sz of [-1, 1]) { const c = caster(M, 0.035); c.position.set(sx * (w / 2 - 0.07), 0, sz * (d / 2 - 0.07)); grp.add(c); }
  parent.add(grp);
  return { grp, w, h: h + y0, d };
}
registerProp('bc_flight_case', (game, opts = {}) => {
  const g = K.prop('bc_flight_case');
  const M = mats(game);
  const c = flightCase(game, M, g, opts);
  g.userData.colliders = [{ min: [-c.w / 2 - 0.02, 0, -c.d / 2 - 0.02], max: [c.w / 2 + 0.02, c.h, c.d / 2 + 0.02] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['case', 'road_case', 'studio', 'crate'], size: [0.84, 0.51, 0.54],
  desc: 'road/flight case: pebbled tolex, aluminum edges, ball corners, butterfly latches, dish handles, stencil tags. opts {size:sm|md|lg|tall, color (hex tolex), tag}' });

registerProp('bc_flight_case_stack', (game, opts = {}) => {
  const g = K.prop('bc_flight_case_stack');
  const M = mats(game);
  const a = flightCase(game, M, g, { size: 'lg', color: opts.colors?.[0] ?? '#2E2934' });
  const b = flightCase(game, M, g, { size: 'md', color: opts.colors?.[1] ?? '#2F4A7A', tag: 'pl_WZTV' });
  b.grp.position.set(-0.08, a.h, 0.02); b.grp.rotation.y = 0.12;
  const c = flightCase(game, M, g, { size: 'sm', color: opts.colors?.[2] ?? '#7A2A26' });
  c.grp.position.set(0.12, a.h + b.h, -0.02); c.grp.rotation.y = -0.2;
  g.userData.colliders = [{ min: [-0.58, 0, -0.34], max: [0.58, a.h + b.h + c.h, 0.34] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['case', 'road_case', 'stack', 'studio'], size: [1.16, 1.55, 0.68], hero: true, desc: 'stack of 3 flight cases (lg black, md blue, sm red), slightly twisted. opts {colors[3]}' });

// ================================================================================================= SMALL PROPS
registerProp('bc_clapperboard', (game, opts = {}) => {
  const g = K.prop('bc_clapperboard');
  const M = mats(game);
  const W = 0.3, H = 0.24, T = 0.014;
  const root = new THREE.Group();
  g.add(root);
  root.add(K.m(sw(K.box(W, H, T, 0.006, { seg: 1 }), 'black'), M.pl, { pos: [0, H / 2, 0] }));
  root.add(K.m(decal('slate', W - 0.02, H - 0.02), M.pl, { pos: [0, H / 2, -T / 2 - 0.0008] }));
  root.add(K.m(cu(cbox(W, 0.04, T, 0.004), 'stripes'), M.pl, { pos: [0, H + 0.02, 0] }));
  const clap = new THREE.Group();
  clap.position.set(-W / 2 + 0.005, H + 0.04, 0);
  clap.rotation.z = opts.open ?? 0.4;
  clap.userData.noMerge = true;
  clap.add(K.m(cu(cbox(W, 0.04, T, 0.004), 'stripes'), M.pl, { pos: [W / 2 - 0.005, 0.02, 0] }));
  root.add(clap);
  root.add(K.m(bcyl(0.01, 0.01, T + 0.01, 0.002, 10), M.ch, { pos: [-W / 2 + 0.005, H + 0.04, -T / 2 - 0.005], rot: [HP, 0, 0] }));
  if (opts.flat) { root.rotation.x = HP; root.position.set(0, T / 2, -H / 2 - 0.02); }
  else root.rotation.x = -0.12;
  g.userData.parts = { clapper: clap };
  g.userData.colliders = [];
  return done(game, g, { mergeParts: [clap] });
}, { category: 'broadcast', tags: ['clapper', 'slate', 'small', 'desk'], size: [0.3, 0.3, 0.05], desc: 'clapperboard: chalk slate "SPOOKTACULAR", striped clapper (parts.clapper rot.z). opts {open, flat}' });

registerProp('bc_teleprompter', (game, opts = {}) => {
  const g = K.prop('bc_teleprompter');
  const M = mats(game);
  // small rolling base + chrome column
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + HP;
    g.add(along((l) => sw(cbox(0.04, l, 0.035, 0.008), 'slate').translate(0, l / 2, 0), M.pl, [0, 0.1, 0], [Math.cos(a) * 0.36, 0.1, Math.sin(a) * 0.36]));
    const c = caster(M, 0.03); c.position.set(Math.cos(a) * 0.36, 0, Math.sin(a) * 0.36); g.add(c);
  }
  g.add(K.m(sw(L([[0, 0], [0.09, 0], [0.09, 0.03], [0.05, 0.08], [0, 0.08]], 0.01, 14), 'slate'), M.pl, { pos: [0, 0.06, 0] }));
  g.add(K.m(bcyl(0.028, 0.028, 0.95, 0.004, 12), M.ch, { pos: [0, 0.12, 0] }));
  g.add(K.m(sw(bcyl(0.04, 0.04, 0.05, 0.006, 12), 'slate'), M.pl, { pos: [0, 0.6, 0] }));
  // hooded prompter head: monitor box facing up, 45deg beam-splitter glass, cloth hood, glowing script
  const y0 = 1.07, W = 0.5, D = 0.46;
  g.add(K.m(sw(K.box(W, 0.18, D, 0.04), 'charcoal'), M.pl, { pos: [0, y0 + 0.09, 0] }));
  g.add(K.m(sw(frame(W - 0.03, D - 0.03, 0.03, 0.02, 0.03, 0.01).rotateX(-HP), 'ink'), M.pl, { pos: [0, y0 + 0.185, 0] }));
  g.add(K.m(cu(new THREE.PlaneGeometry(W - 0.09, D - 0.09).rotateX(-HP).rotateY(Math.PI), 'script'), M.pl, { pos: [0, y0 + 0.187, 0] }));
  for (const s of [-1, 1]) g.add(K.m(sw(K.extrude([[-D / 2, 0], [D / 2, 0], [D / 2, D - 0.04], [D / 2 - 0.04, D]], 0.02, { bevel: 0.006, round: 0.02 }).rotateY(-HP), 'ink'), M.mt, { pos: [s * (W / 2 - 0.01), y0 + 0.18, 0] }));
  g.add(K.m(sw(cbox(W, 0.02, 0.08, 0.006), 'ink'), M.mt, { pos: [0, y0 + 0.18 + D - 0.02, D / 2 - 0.04] }));
  g.add(K.m(sw(cbox(W, D - 0.02, 0.02, 0.006), 'ink'), M.mt, { pos: [0, y0 + 0.18 + D / 2 - 0.01, D / 2 - 0.01] }));
  const L45 = Math.hypot(D, D) - 0.05;
  const glassMat = game.mats.toon('#2A3446', { rough: 0.12, env: 0.25, rim: 0.35, rimColor: '#BFE8FF', transparent: true, opacity: 0.55, depthWrite: false, side: THREE.DoubleSide });
  const gl = K.m(new THREE.PlaneGeometry(W - 0.05, L45), glassMat, { pos: [0, y0 + 0.18 + D / 2, 0], rot: [Math.PI / 4, 0, 0] });
  gl.userData.noAO = true;
  g.add(gl);
  g.add(K.m(cu(new THREE.PlaneGeometry(W - 0.12, L45 * 0.7), 'script'), K.glow(game, '#ffffff', 0.95, { map: atlasTex(), additive: true }), { pos: [0, y0 + 0.18 + D / 2 + 0.003, -0.003], rot: [Math.PI / 4, Math.PI, 0] }));
  g.children[g.children.length - 1].userData.noOcclude = true;
  g.add(K.m(decal('pl_TELESCRIPT', 0.16, 0.03), M.pl, { pos: [0, y0 + 0.1, -D / 2 - 0.003] }));
  g.add(K.m(lw(lowCyl(0.008, 0.006, 8), 'green'), M.lit, { pos: [0.18, y0 + 0.1, -D / 2 - 0.001], rot: [-HP, 0, 0] }));
  g.userData.colliders = [{ min: [-0.38, 0, -0.38], max: [0.38, y0 + 0.2 + D, 0.38] }];
  return done(game, g);
}, { category: 'broadcast', tags: ['teleprompter', 'studio', 'newsroom'], size: [0.76, 1.72, 0.76], desc: 'rolling teleprompter: up-facing script monitor, 45-degree beam-splitter glass with glowing script, cloth hood' });

registerProp('bc_reel_to_reel', (game, opts = {}) => {
  const g = K.prop('bc_reel_to_reel');
  const M = mats(game);
  const wood = woodMat(game);
  const brushed = brushedMat(game);
  const W = 0.46, H = 0.52, D = 0.2, fz = -D / 2;
  g.add(K.m(sw(K.box(W - 0.06, H, D - 0.01, 0.02), 'charcoal'), M.pl, { pos: [0, H / 2, 0.005] }));
  for (const s of [-1, 1]) g.add(K.m(K.box(0.035, H + 0.01, D + 0.01, 0.012, { uv: 2, swap: true }), wood, { pos: [s * (W / 2 - 0.0175), H / 2 + 0.005, 0] }));
  g.add(K.m(K.box(W - 0.07, H - 0.02, 0.012, 0.006, { uv: 2.5, seg: 1 }), brushed, { pos: [0, H / 2, fz + 0.002] }));
  const reels = opts.reels !== false;
  const ry = H * 0.7, rx = 0.1, rr0 = 0.09;
  const parts = {};
  for (const [s, k, pack] of [[-1, 'reelL', 0.85], [1, 'reelR', 0.45]]) {
    const sp = K.m(sw(lowCyl(0.012, 0.03, 8), 'silver'), M.me, { pos: [s * rx, ry, fz - 0.004], rot: [-HP, 0, 0] });
    g.add(sp);
    if (reels) { const rl = tapeReel(M, rr0, { depth: 0.03, pack }); rl.position.set(s * rx, ry, fz - 0.03); rl.rotation.z = s; g.add(rl); parts[k] = rl; }
  }
  // head cover + tape path + capstan
  g.add(K.m(sw(K.box(0.12, 0.06, 0.04, 0.012), 'ink'), M.pl, { pos: [0, ry - 0.11, fz - 0.018] }));
  g.add(K.m(bcyl(0.008, 0.008, 0.04, 0.002, 8), M.ch, { pos: [0.075, ry - 0.11, fz - 0.004], rot: [-HP, 0, 0] }));
  g.add(K.m(sw(bcyl(0.016, 0.016, 0.03, 0.004, 10), 'rubber'), M.mt, { pos: [0.1, ry - 0.1, fz - 0.004], rot: [-HP, 0, 0] }));
  if (reels) for (const [a, b] of [[[-rx - rr0 * 0.6, ry - 0.05], [-0.06, ry - 0.14]], [[-0.06, ry - 0.145], [0.075, ry - 0.145]], [[0.075, ry - 0.14], [rx + rr0 * 0.35, ry - 0.03]]]) {
    const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
    const m = K.m(sw(cbox(0.003, len, 0.018, 0.001), 'tapeGold'), M.pl, { pos: [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, fz - 0.045] });
    m.rotation.z = Math.atan2(b[1] - a[1], b[0] - a[0]) - HP;
    g.add(m);
  }
  // meters, knobs, piano keys, badge
  const vA = vuMeter(M, 0.1, [-0.085, H * 0.28, fz - 0.004], { angle: 0.3 }), vB = vuMeter(M, 0.1, [0.085, H * 0.28, fz - 0.004], { angle: 0.05 });
  for (const m of [...vA.meshes, ...vB.meshes]) g.add(m);
  for (let i = 0; i < 4; i++) for (const mm of knob(M, 0.014, [-0.12 + i * 0.08, H * 0.16, fz - 0.004], { color: 'ink', cap: 'silver', rot: i * 0.7, seg: 10 })) g.add(mm);
  for (let i = 0; i < 5; i++) g.add(K.m(sw(keycap(0.05, 0.035, 0.03, 0.006), i === 4 ? 'red' : 'ivory'), M.pl, { pos: [-0.12 + i * 0.06, H * 0.06, fz - 0.004], rot: [-HP + 0.3, 0, 0] }));
  g.add(K.m(decal('pl_AUDIOLUX', 0.13, 0.025), M.pl, { pos: [0, H * 0.4, fz - 0.0045] }));
  g.userData.parts = parts;
  g.userData.colliders = [{ min: [-W / 2, 0, fz - 0.06], max: [W / 2, H + 0.01, D / 2] }];
  return done(game, g, { mergeParts: Object.values(parts) });
}, { category: 'broadcast', tags: ['audio', 'tape', 'desk', 'master_control'], size: [0.46, 0.53, 0.26], desc: 'upright reel-to-reel deck: brushed face, walnut cheeks, reels (parts reelL/R spin about z), VU meters, piano keys. opts {reels}' });

function headphones(M, g, o = {}) {
  const grp = new THREE.Group();
  const cupC = o.cup ?? 'silver', padC = o.pad ?? 'orange';
  grp.add(K.m(sw(K.tube([[-0.09, -0.04, 0], [-0.085, 0.05, 0], [-0.05, 0.1, 0], [0, 0.115, 0], [0.05, 0.1, 0], [0.085, 0.05, 0], [0.09, -0.04, 0]], 0.009, { seg: 18, radial: 6 }), 'ink'), M.pl));
  grp.add(K.m(sw(K.tube([[-0.055, 0.092, 0], [-0.03, 0.108, 0], [0, 0.113, 0], [0.03, 0.108, 0], [0.055, 0.092, 0]], 0.017, { seg: 10, radial: 7 }), 'chocolate'), M.mt));
  for (const s of [-1, 1]) {
    grp.add(K.m(sw(L([[0, 0], [0.055, 0], [0.06, 0.012], [0.052, 0.04], [0.03, 0.05], [0, 0.052]], 0.008, 14), cupC), M.me, { pos: [s * 0.1, -0.06, 0], rot: [0, 0, s * HP] }));
    grp.add(K.m(sw(L([[0, 0], [0.056, 0], [0.058, 0.012], [0.045, 0.026], [0, 0.026]], 0.008, 14), padC), M.mt, { pos: [s * 0.1, -0.06, 0], rot: [0, 0, -s * HP] }));
    grp.add(K.m(sw(cbox(0.012, 0.05, 0.02, 0.004), 'ink'), M.pl, { pos: [s * 0.095, -0.02, 0] }));
  }
  const coil = [];
  for (let i = 0; i <= 40; i++) { const t = i / 40, a = t * TAU * 8; coil.push([0.13 + Math.cos(a) * 0.012, -0.09 - t * 0.28, Math.sin(a) * 0.012]); }
  coil.push([0.12, -0.42, 0.0], [0.11, -0.48, -0.01]);
  grp.add(K.m(sw(K.tube(coil, 0.0035, { seg: 60, radial: 4 }), 'ink'), M.pl));
  grp.add(K.m(bcyl(0.006, 0.006, 0.05, 0.002, 8), M.ch, { pos: [0.11, -0.53, -0.01] }));
  grp.add(K.m(sw(bcyl(0.01, 0.01, 0.05, 0.003, 8), 'ink'), M.pl, { pos: [0.11, -0.49, -0.01] }));
  g.add(grp);
  return grp;
}
registerProp('bc_headphones_hook', (game, opts = {}) => {
  const g = K.prop('bc_headphones_hook');
  const M = mats(game);
  const wood = woodMat(game);
  const Dd = 0.1;
  g.add(K.m(K.box(0.1, 0.14, 0.02, 0.008, { uv: 3 }), wood, { pos: [0, 0.62, Dd / 2 - 0.01] }));
  g.add(K.m(K.tube([[0, 0.6, Dd / 2 - 0.02], [0, 0.6, -0.02], [0, 0.62, -0.05], [0, 0.66, -0.05]], 0.008, { seg: 10, radial: 6 }), M.ch));
  const hp = headphones(M, g, opts);
  hp.position.set(0, 0.5, -0.03);
  hp.rotation.y = 0.12;
  g.userData.colliders = [];
  return done(game, g, { finish: { ao: { floor: false, height: 0 } } });
}, { category: 'broadcast', tags: ['headphones', 'wall', 'small'], size: [0.26, 0.7, 0.13], desc: 'wall hook (back at z=+0.05) with 70s headphones: padded band, silver cups, orange pads, coiled cord + plug. y=0 = plug tip (hook at 0.6 m)' });

// ================================================================================================= ENG CAMERA
registerProp('bc_eng_camera', (game, opts = {}) => {
  const g = K.prop('bc_eng_camera');
  const M = mats(game);
  // wooden tripod legs with spreader
  const wood = woodMat(game, '#9A6A3E');
  const hy = 1.18;
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.5;
    const foot = [Math.cos(a) * 0.48, 0.02, Math.sin(a) * 0.48], top = [Math.cos(a) * 0.07, hy - 0.04, Math.sin(a) * 0.07];
    for (const o2 of [-0.018, 0.018]) {
      const ofs = [Math.cos(a + HP) * o2, 0, Math.sin(a + HP) * o2];
      g.add(along((l) => K.uvScale(bcyl(0.013, 0.011, l, 0.003, 8).clone(), 1, 3), wood, [foot[0] + ofs[0], foot[1], foot[2] + ofs[2]], [top[0] + ofs[0], top[1], top[2] + ofs[2]]));
    }
    const mid = [foot[0] * 0.55 + top[0] * 0.45, 0.55, foot[2] * 0.55 + top[2] * 0.45];
    g.add(K.m(sw(cbox(0.06, 0.05, 0.03, 0.008), 'ink'), M.pl, { pos: mid, rot: [0, -a, 0] }));
    g.add(K.m(sw(L([[0, 0], [0.024, 0], [0.02, 0.03], [0, 0.034]], 0.004, 8), 'silver'), M.pl, { pos: [foot[0], 0, foot[2]] }));
    g.add(along((l) => sw(cbox(0.02, l, 0.012, 0.004), 'charcoal').translate(0, l / 2, 0), M.pl, [foot[0] * 0.7, 0.08, foot[2] * 0.7], [0, 0.08, 0]));
  }
  g.add(K.m(sw(L([[0, 0], [0.11, 0], [0.11, 0.04], [0.08, 0.06], [0, 0.06]], 0.01, 14), 'charcoal'), M.pl, { pos: [0, hy - 0.06, 0] }));
  // fluid head + pan handle
  const head = new THREE.Group();
  head.position.set(0, hy, 0);
  head.rotation.y = opts.pan ?? -0.3;
  head.userData.noMerge = true;
  g.add(head);
  head.add(K.m(sw(bcyl(0.06, 0.07, 0.08, 0.01, 14), 'ink'), M.pl));
  head.add(K.m(sw(cbox(0.12, 0.03, 0.2, 0.008), 'charcoal'), M.pl, { pos: [0, 0.095, 0] }));
  head.add(K.m(K.tube([[0.04, 0.06, 0.08], [0.1, 0.02, 0.3], [0.14, -0.04, 0.5]], 0.012, { seg: 10, radial: 6 }), M.ch));
  head.add(K.m(sw(K.tube([[0.12, -0.01, 0.42], [0.14, -0.04, 0.5]], 0.02, { seg: 3, radial: 8 }), 'rubber'), M.mt));
  // shoulder ENG camera: body, lens, side viewfinder tube, top handle, tally, shoulder pad
  const cam = new THREE.Group();
  cam.position.set(0, 0.11, 0.02);
  cam.scale.setScalar(opts.camScale ?? 1.25);
  head.add(cam);
  const bodyC = opts.color ?? 'putty';
  cam.add(K.m(sw(K.box(0.18, 0.22, 0.4, 0.04), bodyC), M.pl, { pos: [0, 0.12, 0.02] }));
  cam.add(K.m(sw(K.box(0.186, 0.06, 0.3, 0.02, { seg: 1 }), 'orange'), M.pl, { pos: [0, 0.06, 0.04] }));
  cam.add(K.m(sw(K.box(0.16, 0.05, 0.22, 0.02), 'rubber'), M.mt, { pos: [0, -0.005, 0.1] }));
  cam.add(K.m(sw(L([[0, 0], [0.06, 0], [0.06, 0.02], [0.054, 0.025], [0.054, 0.18], [0.07, 0.24], [0.066, 0.25], [0, 0.25]], 0.006, 16), 'ink'), M.pl, { pos: [0, 0.12, -0.18], rot: [-HP, 0, 0] }));
  cam.add(K.m(sw(L([[0.055, 0], [0.061, 0], [0.061, 0.05], [0.055, 0.05]], 0, 16), 'rubber'), M.mt, { pos: [0, 0.12, -0.23], rot: [-HP, 0, 0] }));
  cam.add(K.m(new THREE.CircleGeometry(0.058, 16).rotateY(Math.PI), M.glass, { pos: [0, 0.12, -0.425] }));
  cam.add(K.m(sw(cbox(0.03, 0.05, 0.12, 0.008), 'charcoal'), M.pl, { pos: [0.075, 0.1, -0.28] }));
  cam.add(K.m(sw(bcyl(0.028, 0.028, 0.22, 0.005, 12), 'ink'), M.pl, { pos: [-0.13, 0.2, -0.1], rot: [HP, 0, 0] }));
  cam.add(K.m(sw(L([[0, 0], [0.03, 0], [0.042, 0.04], [0.036, 0.05], [0, 0.05]], 0.005, 12), 'rubber'), M.mt, { pos: [-0.13, 0.2, 0.12], rot: [HP, 0, 0] }));
  cam.add(K.m(sw(cbox(0.06, 0.03, 0.03, 0.008), 'ink'), M.pl, { pos: [-0.1, 0.2, -0.06] }));
  cam.add(K.m(K.tube([[0, 0.23, -0.12], [0, 0.3, -0.09], [0, 0.3, 0.1], [0, 0.23, 0.14]], 0.012, { seg: 12, radial: 6 }), M.ch));
  cam.add(K.m(opts.tally ? lw(L([[0, 0], [0.016, 0], [0.016, 0.008], [0.01, 0.018], [0, 0.02]], 0.004, 10), 'red') : sw(L([[0, 0], [0.016, 0], [0.016, 0.008], [0.01, 0.018], [0, 0.02]], 0.004, 10), 'lampRed'), opts.tally ? M.lit : M.pl, { pos: [0.05, 0.23, -0.15] }));
  cam.add(K.m(decal('pl_VIDICAM', 0.12, 0.0225), M.pl, { pos: [0.0935, 0.14, 0.05], rot: [0, -HP, 0] }));
  cam.add(K.m(discDecal('logo13', 0.035, 16), M.pl, { pos: [0.0935, 0.17, -0.07], rot: [0, -HP, 0] }));
  // battery belt draped over the front leg: leather strap, chunky cells, chrome buckle, cable up to the camera
  const af = 0.5 + (2 / 3) * TAU; // front leg angle
  const dir = [Math.cos(af), 0, Math.sin(af)], tan = [-Math.sin(af), 0, Math.cos(af)];
  const P = (s2, drop, out = 0) => [dir[0] * (0.215 + out) + tan[0] * s2, 0.76 - drop, dir[2] * (0.215 + out) + tan[2] * s2];
  const beltPts = [];
  for (let i = 0; i <= 14; i++) { const t = i / 14 * 2 - 1; beltPts.push(P(t * 0.15, 0.3 * Math.pow(Math.abs(t), 1.6) - 0.028, 0.045 * (1 - Math.abs(t)))); }
  g.add(K.m(sw(K.tube(beltPts, 0.026, { seg: 24, radial: 6 }), 'chocolate'), M.pl));
  for (const i of [2, 4, 10, 12]) {
    const p0 = beltPts[i - 1], p1 = beltPts[i + 1];
    g.add(along((l) => sw(bcyl(0.034, 0.034, l, 0.008, 10), i % 4 ? 'ink' : 'charcoal'), M.pl, [p0[0] + dir[0] * 0.02, p0[1], p0[2] + dir[2] * 0.02], [p1[0] + dir[0] * 0.02, p1[1], p1[2] + dir[2] * 0.02]));
  }
  g.add(K.m(sw(cbox(0.05, 0.04, 0.02, 0.006), 'silver'), M.pl, { pos: beltPts[14], rot: [0, -af, 0] }));
  g.add(K.m(sw(K.tube([beltPts[13], [beltPts[13][0], 0.5, beltPts[13][2] - 0.08], [0.1, 0.3, -0.25], [0.2, 0.9, -0.05], [0.06, 1.2, 0.05], [0.02, 1.33, 0.2]], 0.007, { seg: 22, radial: 4 }), 'ink'), M.pl));
  g.userData.parts = { head };
  g.userData.colliders = [{ min: [-0.45, 0, -0.45], max: [0.45, 1.55, 0.45] }];
  return done(game, g, { mergeParts: [head] });
}, { category: 'broadcast', tags: ['camera', 'eng', 'news', 'lobby', 'tripod'], size: [1.0, 1.7, 1.05], hero: true,
  desc: 'portable ENG shoulder camera on a wooden tripod: fluid head + pan bar (parts.head rot.y), side viewfinder, battery belt draped over a leg. opts {pan, tally, color}' });

// ================================================================================================= SCENES
// propview set-dressing checks (camera looks toward +z; back wall at +z, side wall at -x)
const HPI = Math.PI / 2;
registerScene('bc_master_control', {
  floor: '#3C4252', wall: '#2C3646', room: [9, 7], wallH: 3.9,
  items: [
    { id: 'bc_monitor_wall', pos: [0, 3.22] },
    { id: 'bc_console_end', pos: [-1.825, 0.5] },
    { id: 'bc_console_switcher', pos: [-1.2, 0.5] },
    { id: 'bc_console_monitor', pos: [0, 0.5] },
    { id: 'bc_console_audio', pos: [1.2, 0.5] },
    { id: 'bc_console_end', pos: [1.825, 0.5] },
    { id: 'bc_vtr_quad', pos: [-4.02, -0.9], rotY: -HPI, opts: { num: 1 } },
    { id: 'bc_vtr_quad', pos: [-4.02, 0.45], rotY: -HPI, opts: { num: 2, reels: false, lamp: 'amber', group: 'scr_vtr2' } },
    { id: 'bc_vtr_quad', pos: [-4.02, 1.8], rotY: -HPI, opts: { num: 3 } },
    { id: 'bc_patch_bay', pos: [3.95, 3.05] },
    { id: 'bc_patch_bay', pos: [3.95, 2.3], rotY: -0.08, opts: { seed: 9, cords: 5 } },
    { id: 'bc_on_air', pos: [-4.43, 2.75, 2.75], rotY: -HPI, opts: { lit: true } },
    { id: 'bc_headphones_hook', pos: [-4.45, 0.75, 2.65], rotY: -HPI },
    { id: 'bc_cart_monitor', pos: [3.2, -1.4], rotY: -0.7, opts: { card: 'show_9' } },
    { id: 'bc_flight_case_stack', pos: [-2.6, -2.6], rotY: 0.3 },
    { id: 'bc_cable_spaghetti', pos: [-2.4, -0.7], rotY: 0.4 },
    { id: 'bc_cable_coil', pos: [2.2, -2.3], rotY: 2.1 },
    { id: 'bc_reel_to_reel', pos: [2.9, 0.84, 1.6], rotY: -0.5 },
    { id: 'bc_flight_case', pos: [2.9, 1.6], rotY: -0.3, opts: { size: 'lg', color: '#2F4A7A' } },
  ],
  cam: { pos: [0.6, 2.3, -4.6], target: [-0.3, 1.35, 1.6], fov: 58 }, hemi: 0.75, key: 1.1,
});
registerScene('bc_studio', {
  floor: 'wood', floorColor: '#6A4A36', wall: '#3A2A4A', room: [10, 7], wallH: 3.8,
  items: [
    { id: 'bc_pedestal_camera', pos: [-1.6, -0.6], rotY: 0.35, opts: { num: 1 } },
    { id: 'bc_pedestal_camera', pos: [1.5, -0.3], rotY: -0.4, opts: { num: 2, tally: false, accent: 'orange' } },
    { id: 'bc_boom_mic', pos: [3.3, 1.2], rotY: -2.4, opts: { swing: 0.2 } },
    { id: 'bc_light_tripod', pos: [-3.6, 1.8], rotY: 0.9, opts: { gel: 'amber' } },
    { id: 'bc_light_softbox', pos: [3.6, 2.6], rotY: -0.6 },
    { id: 'bc_teleprompter', pos: [0.1, 2.2], rotY: Math.PI },
    { id: 'bc_grid_batten', pos: [0, 3.18, 1.8], opts: { len: 5 } },
    { id: 'bc_light_fresnel', pos: [-1.6, 2.52, 1.8], opts: { gel: 'magenta' } },
    { id: 'bc_light_scoop', pos: [0.2, 2.46, 1.8] },
    { id: 'bc_light_fresnel', pos: [1.8, 2.52, 1.8], opts: { gel: 'cyan' } },
    { id: 'bc_applause', pos: [0, 2.3, 3.2] },
    { id: 'bc_cable_spaghetti', pos: [-0.4, 0.6], rotY: 0.1, opts: { seed: 3 } },
    { id: 'bc_flight_case_stack', pos: [-4.1, -0.9], rotY: 0.6 },
    { id: 'bc_flight_case', pos: [-2.9, -2.3], rotY: -0.2, opts: { size: 'md' } },
    { id: 'bc_clapperboard', pos: [-2.9, 0.51, -2.3], rotY: 0.3, opts: { flat: true } },
    { id: 'bc_cart_monitor', pos: [4.1, -1.5], rotY: -0.9, opts: { card: 'show_12' } },
    { id: 'bc_cable_coil', pos: [1.6, -2.3], rotY: 0.8 },
  ],
  cam: { pos: [0.2, 2.1, -5.2], target: [0, 1.2, 1.2], fov: 58 }, hemi: 0.8, key: 1.1,
});

// debug: ?bcprof=1 registers a plane showing the whole atlas (not part of the library)
if (PROFILE) {
  registerProp('bc__atlas', (game) => {
    const g = K.prop('bc__atlas');
    const M = mats(game);
    g.add(K.m(new THREE.PlaneGeometry(2, 2), M.pl, { pos: [0, 1, 0], rot: [0, Math.PI, 0] }));
    g.add(K.m(new THREE.PlaneGeometry(2, 2), M.soft, { pos: [2.1, 1, 0], rot: [0, Math.PI, 0] }));
    return done(game, g, { finish: { ao: false } });
  }, { category: 'debug' });
  registerProp('bc__vu', (game) => {
    const g = K.prop('bc__vu');
    const M = mats(game);
    g.add(K.m(sw(cbox(0.6, 0.4, 0.05, 0.01), 'charcoal'), M.pl, { pos: [0, 0.3, 0.03] }));
    const v = vuMeter(M, 0.26, [-0.14, 0.3, 0], {});
    for (const m of v.meshes) g.add(m);
    g.add(K.m(decal('vu', 0.2, 0.1), M.soft, { pos: [0.16, 0.3, -0.01] }));
    return done(game, g);
  }, { category: 'debug' });
}
