/**
 * DEAD AIR — gfx/cards.js
 * Every piece of 2D broadcast artwork the station shows: TV sources (bars, test card, station ID, bumpers,
 * Hootie, the Baron, the sign-off film), Telly's dot-matrix face and its nine channel cards, wall-buy and
 * sponsor posters, logo cards, neon signs, props with printed graphics (weather map, rundown cards, tote
 * digits, badges, tickets...), the title logo and the Chroma-Key stock-footage worlds.
 * Pure Canvas 2D, no image files; THREE is only used to wrap canvases as CanvasTextures.
 *
 * API
 *   getCard(id, opts?)      -> THREE.CanvasTexture. Static card, drawn lazily, cached per id + opts, sRGB,
 *                              mipmapped. Animated ids render one frame here (opts.time, seconds, default 0).
 *   getAnimated(id, opts?)  -> { texture, canvas, opts, tick(time), set(patch) }. Cached per id + opts, so every
 *                              screen showing a source shares one texture. tick(time) (seconds) redraws only when
 *                              the card's own frame index changes (its fps) or after set(); returns true if it
 *                              redrew. set(patch) merges into this handle's opts (Telly's expression / gaze...).
 *                              Handles are shared: add any extra key (e.g. { owner:'telly' }) for a private one.
 *                              Timeline cards (signoff_film) expect time since the source started (loops at 20 s).
 *   drawTo(ctx, id, w, h, time = 0, opts?)  draws the card into any 2D context at 0,0 scaled to w x h (HUD, menus).
 *   cardIds()               -> every registered id.
 *   cardInfo(id)            -> { w, h, fps, alpha, opts } native size, frame rate (0 = static), transparency and a
 *                              short description of the options the id understands.
 *   invalidateAll()         -> redraws every cached canvas; runs by itself when webfonts finish loading.
 *   cards                   -> the same API as one namespace ({ get, animated, drawTo, ids, info, invalidateAll })
 *                              for engine code that holds a single provider (game.cards is this object).
 *
 * Atlases: getCard('tote_digits').userData.atlas = { chars, cols, rows, cellW, cellH, uv(ch) -> [u0,v0,u1,v1] }
 *          (v measured from the bottom, as THREE UVs with flipY).
 * Fonts:   Shrikhand, Titan One, VT323 and Bungee (registered by ui/fonts.js through FontFace), with fallbacks.
 * Sizes:   TV sources are 4:3 (512x384); posters 384x512; everything is <= 512 px per side.
 *
 * Catalogue (cardIds() is authoritative; cardInfo(id).opts documents each id's options)
 *   TV sources   color_bars test_card stand_by station_id* right_back* hullabaloo* baron* signoff_film* snow*
 *                satellite_super telly_face* show_<2|4|5|7|8|9|11|12|13> promo_<heroId>      (* = animated)
 *   Posters      poster_<pump_37|mp7|m16a1> {winked} poster_<spooktacular|hootie|precinct13|boogie_down>
 *                sponsor_poster_<perkId> sponsor_logo_<perkId> sponsor_sign_<perkId> {lit}
 *   Newsroom/MC  weather_map magnet_<sun|cloud|rain|bolt|storm> rundown_header rundown_card_<1..6> {star}
 *   Lobby/props  letter_board {signOff} tote_digits dust_rect scenery_board_<1..6> chyron {text, sub}
 *                hero_portrait_<heroId> portrait_baron portrait_stormy_stu magazine_tv_weekly perpetua_ad
 *                ticket_stub badge_crew cap_13 dressing_room_doors {who} baron_dressing_room
 *                sign_see_yourself applause_sign {lit} on_air {lit} clock_face {hands, time} reel_label
 *   Overlays     flinch crack_overlay logo_dead_air world_<space|beach|volcano|underwater|desert|moon>
 */
import * as THREE from 'three';

// ---------------------------------------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------------------------------------

const TAU = Math.PI * 2;
const DEG = Math.PI / 180;

/** GDD §3.2 palette (subset used by the 2D art). */
const C = {
  blue: '#2F5BD3', red: '#E23B3B', white: '#F4F1E8', cream: '#F6E7C8',
  gold: '#E8A92E', orange: '#E3662B', avocado: '#8C9A3A', mustard: '#D9A520', choc: '#5A3A22',
  walnut: '#7A4A2A', teak: '#B07A45', rust: '#B5472A', teal: '#2E8C8C', plum: '#6B3A6E', shag: '#D9602B',
  onAir: '#FF3B30', crt: '#7FE7FF', tungsten: '#FFC98A', pink: '#FF5FA2', marquee: '#FFC23A',
  magenta: '#FF4FA0', amber: '#FFB347', cyan: '#5FE3FF',
  shadow: '#3A2A5A', ink: '#2A1D3A', deep: '#1E1530',
  nightTop: '#1B1E4A', nightHz: '#2A2F6B', moon: '#FFF4D6', moonlight: '#9FB6FF',
  dawn: ['#FF7E5F', '#FFB36B', '#FFE3A3'],
  chroma: '#1E5BFF', lime: '#39E75F', perpetua: '#9CFF57',
  osd: '#5CFF6E', brass: '#E8B84A',
};
/** Cartoonized SMPTE bars, left to right (GDD §3.2). */
const BARS = ['#EDEDED', '#F4E03A', '#3FD6E0', '#52D24A', '#D64FD6', '#E4473A', '#3A58E4'];
/** Neon logo letters (GDD §3.2). */
const NEON = { W: '#FF3B30', Z: '#FFD23A', T: '#52E04A', V: '#3A7BFF' };

const FONT = {
  groovy: 'Shrikhand, "Cooper Black", "Bookman Old Style", Georgia, serif',
  round: '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif',
  osd: 'VT323, "Lucida Console", "Courier New", monospace',
  sign: 'Bungee, Impact, "Arial Black", sans-serif',
  type: '"Courier New", Courier, monospace',
};

const HERO_IDS = ['skip', 'roxy', 'penny', 'duke'];
const PERK_IDS = ['replay_ade', 'wobble_up', 'jump_cut', 'roller_boogie', 'double_vision'];

// ---------------------------------------------------------------------------------------------------------
// Math, random, colour
// ---------------------------------------------------------------------------------------------------------

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;
const fract = (x) => x - Math.floor(x);

/** mulberry32: deterministic art randomness (cards must look identical on every redraw). */
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

function rgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
function mix(a, b, t) {
  const x = rgb(a), y = rgb(b);
  return '#' + x.map((v, i) => Math.round(lerp(v, y[i], t)).toString(16).padStart(2, '0')).join('');
}
const lighten = (c, t) => mix(c, '#ffffff', t);
/** Darkens toward the tinted purple shadow: never pure black (GDD §3.2). */
const darken = (c, t) => mix(c, '#1c1228', t);
function alpha(c, a) {
  const [r, g, b] = rgb(c);
  return `rgba(${r},${g},${b},${a})`;
}

// ---------------------------------------------------------------------------------------------------------
// Canvas primitives
// ---------------------------------------------------------------------------------------------------------

function makeCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
}

function linear(ctx, x0, y0, x1, y1, stops) {
  const g = ctx.createLinearGradient(x0, y0, x1, y1);
  stops.forEach((s, i) => (Array.isArray(s) ? g.addColorStop(s[0], s[1]) : g.addColorStop(i / (stops.length - 1), s)));
  return g;
}
function radial(ctx, x, y, r0, r1, stops, fx = x, fy = y) {
  const g = ctx.createRadialGradient(fx, fy, r0, x, y, r1);
  stops.forEach((s, i) => (Array.isArray(s) ? g.addColorStop(s[0], s[1]) : g.addColorStop(i / (stops.length - 1), s)));
  return g;
}

function rr(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}
function circle(ctx, x, y, r) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
}
function ellipse(ctx, x, y, rx, ry, rot = 0) {
  ctx.beginPath();
  ctx.ellipse(x, y, Math.max(rx, 0.01), Math.max(ry, 0.01), rot, 0, TAU);
}
function poly(ctx, pts, close = true) {
  ctx.beginPath();
  ctx.moveTo(pts[0], pts[1]);
  for (let i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i], pts[i + 1]);
  if (close) ctx.closePath();
}
function fill(ctx, style) {
  ctx.fillStyle = style;
  ctx.fill();
}
function stroke(ctx, style, lw) {
  ctx.strokeStyle = style;
  ctx.lineWidth = lw;
  ctx.stroke();
}
/** Fills the current path, then outlines it (cartoon ink line). */
function inked(ctx, style, lw, ink = C.ink) {
  ctx.fillStyle = style;
  ctx.fill();
  if (lw > 0) { ctx.strokeStyle = ink; ctx.lineWidth = lw; ctx.stroke(); }
}
function starPath(ctx, x, y, ro, ri, n = 5, rot = -Math.PI / 2) {
  ctx.beginPath();
  for (let i = 0; i < n * 2; i++) {
    const r = i & 1 ? ri : ro, a = rot + (i * Math.PI) / n;
    ctx.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r);
  }
  ctx.closePath();
}
/** Alternating sunburst wedges over the whole canvas. */
function rays(ctx, cx, cy, R, n, color, rot = 0, duty = 0.5) {
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const a0 = rot + (i * TAU) / n, a1 = a0 + (TAU / n) * duty;
    ctx.moveTo(cx, cy);
    ctx.arc(cx, cy, R, a0, a1);
    ctx.closePath();
  }
  ctx.fillStyle = color;
  ctx.fill();
}
/** Puffy cartoon cloud made of circles; returns nothing, fills with `style`, optional ink. */
function cloudPath(ctx, x, y, w, h) {
  const bumps = [[-0.36, 0.12, 0.3], [-0.12, -0.12, 0.38], [0.18, -0.2, 0.34], [0.38, 0.06, 0.28], [0, 0.16, 0.34]];
  ctx.beginPath();
  for (const [bx, by, br] of bumps) {
    const r = br * w * 0.62;
    ctx.moveTo(x + bx * w + r, y + by * h);
    ctx.arc(x + bx * w, y + by * h, r, 0, TAU);
  }
  ctx.roundRect(x - w * 0.46, y - h * 0.02, w * 0.92, h * 0.42, h * 0.2);
}
function cloud(ctx, x, y, w, h, style, ink = null, lw = 0) {
  if (ink) {
    ctx.save();
    cloudPath(ctx, x, y, w, h);
    ctx.strokeStyle = ink;
    ctx.lineWidth = lw * 2;
    ctx.lineJoin = 'round';
    ctx.stroke();
    ctx.restore();
  }
  cloudPath(ctx, x, y, w, h);
  ctx.fillStyle = style;
  ctx.fill();
}
/** Thick round-capped segment: outline pass then fill pass gives one inked silhouette. */
function capsule(ctx, x0, y0, x1, y1, w, style, ink = null, lw = 0) {
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(x0, y0);
  ctx.lineTo(x1, y1);
  if (ink) { ctx.strokeStyle = ink; ctx.lineWidth = w + lw * 2; ctx.stroke(); }
  ctx.strokeStyle = style;
  ctx.lineWidth = w;
  ctx.stroke();
}

// ---------------------------------------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------------------------------------

function setFont(ctx, px, fam) {
  ctx.font = `${Math.max(1, Math.round(px))}px ${fam}`;
}
/** Picks the largest size <= px so `str` fits in maxW. */
function fitFont(ctx, str, fam, px, maxW) {
  setFont(ctx, px, fam);
  const m = ctx.measureText(str).width;
  if (m > maxW) { px = Math.max(6, Math.floor((px * maxW) / m)); setFont(ctx, px, fam); }
  return px;
}
/**
 * Poster lettering. o: { fam, px, maxW, fill (style or fn(ctx, px)), stroke, lw, depth, depthFill, dx, dy,
 * align, base, rot, skew, track, shadow, shadowBlur, glow }
 * depth draws a stacked 70s extrusion toward (dx, dy); stroke/lw outline every layer.
 */
function label(ctx, str, x, y, o = {}) {
  const fam = o.fam || FONT.sign;
  ctx.save();
  if (o.track) ctx.letterSpacing = `${o.track}px`;
  const px = o.maxW ? fitFont(ctx, str, fam, o.px || 32, o.maxW) : (setFont(ctx, o.px || 32, fam), o.px || 32);
  ctx.textAlign = o.align || 'center';
  ctx.textBaseline = o.base || 'middle';
  ctx.lineJoin = 'round';
  ctx.miterLimit = 2;
  ctx.translate(x, y);
  if (o.rot) ctx.rotate(o.rot);
  if (o.skew) ctx.transform(1, 0, o.skew, 1, 0, 0);
  const lw = o.lw ?? px * 0.1;
  const depth = o.depth || 0, dx = o.dx ?? 0.7, dy = o.dy ?? 1;
  if (o.shadow) {
    ctx.save();
    ctx.shadowColor = o.shadow;
    ctx.shadowBlur = o.shadowBlur ?? px * 0.25;
    ctx.shadowOffsetY = o.shadowY ?? px * 0.06;
    ctx.fillStyle = o.shadow;
    ctx.fillText(str, (depth + 1) * dx, (depth + 1) * dy);
    ctx.restore();
  }
  for (let i = depth; i > 0; i--) {
    ctx.fillStyle = o.depthFill || C.ink;
    if (o.stroke) { ctx.strokeStyle = o.depthStroke || o.stroke; ctx.lineWidth = lw; ctx.strokeText(str, i * dx, i * dy); }
    ctx.fillText(str, i * dx, i * dy);
  }
  if (o.stroke) { ctx.strokeStyle = o.stroke; ctx.lineWidth = lw; ctx.strokeText(str, 0, 0); }
  if (o.glow) { ctx.shadowColor = o.glow; ctx.shadowBlur = o.glowBlur ?? px * 0.4; }
  ctx.fillStyle = typeof o.fill === 'function' ? o.fill(ctx, px) : o.fill || '#fff';
  ctx.fillText(str, 0, 0);
  ctx.restore();
  return px;
}
/** Vertical gradient generator for label fills (spans the glyph box of a centred label). */
const vgrad = (stops) => (ctx, px) => linear(ctx, 0, -px * 0.5, 0, px * 0.45, stops);
const CHROME = ['#FFFFFF', '#DDE6F4', '#9AA8C8', '#4E5C82', [0.52, '#F4F7FF'], '#B6C2DC', '#FFFFFF'];
const GOLDEN = ['#FFF6C8', '#FFD45A', '#E8A92E', [0.55, '#FFE38A'], '#C97E1E'];

// ---------------------------------------------------------------------------------------------------------
// Surface effects (cached tiles; cheap enough for animated cards)
// ---------------------------------------------------------------------------------------------------------

let noiseTile = null;
function getNoiseTile() {
  if (!noiseTile) {
    noiseTile = makeCanvas(256, 256);
    const g = noiseTile.getContext('2d');
    const img = g.createImageData(256, 256), d = img.data, r = rng(1977);
    for (let i = 0; i < d.length; i += 4) {
      const v = (r() * 0.6 + r() * 0.4) * 255;
      d[i] = d[i + 1] = d[i + 2] = v;
      d[i + 3] = 255;
    }
    g.putImageData(img, 0, 0);
  }
  return noiseTile;
}
/** Film/paper grain (overlay blend). Only for opaque cards. */
function grain(ctx, w, h, amt = 0.08, seed = 0) {
  ctx.save();
  ctx.globalAlpha = amt;
  ctx.globalCompositeOperation = 'overlay';
  const ox = (seed * 97) % 256, oy = (seed * 61) % 256;
  ctx.translate(-ox, -oy);
  ctx.fillStyle = ctx.createPattern(getNoiseTile(), 'repeat');
  ctx.fillRect(ox, oy, w, h);
  ctx.restore();
}
function vignette(ctx, w, h, a = 0.45, col = '28,16,46', inner = 0.45) {
  ctx.fillStyle = radial(ctx, w / 2, h / 2, Math.min(w, h) * inner, Math.hypot(w, h) * 0.55,
    [`rgba(${col},0)`, `rgba(${col},${a})`]);
  ctx.fillRect(0, 0, w, h);
}
/** Halftone dot field; fn(u, v) -> 0..1 dot size over the rect. */
function halftone(ctx, x, y, w, h, color, cell, fn) {
  ctx.fillStyle = color;
  ctx.beginPath();
  for (let j = 0; j <= h / cell + 1; j++) {
    for (let i = 0; i <= w / cell + 1; i++) {
      const px = x + i * cell + (j & 1 ? cell / 2 : 0), py = y + j * cell;
      const r = fn((px - x) / w, (py - y) / h) * cell * 0.62;
      if (r > 0.35) { ctx.moveTo(px + r, py); ctx.arc(px, py, r, 0, TAU); }
    }
  }
  ctx.fill();
}
/** Printed-paper finish for posters: warm grain, faint edge wear and a vignette. */
function paper(ctx, w, h, seed = 0, amt = 0.1) {
  grain(ctx, w, h, amt, seed);
  vignette(ctx, w, h, 0.28, '60,30,20', 0.5);
}
/** Glossy highlight streak across the top of a rounded rect. */
function gloss(ctx, x, y, w, h, r, a = 0.35) {
  ctx.save();
  rr(ctx, x, y, w, h, r);
  ctx.clip();
  ctx.fillStyle = linear(ctx, 0, y, 0, y + h * 0.5, [`rgba(255,255,255,${a})`, 'rgba(255,255,255,0)']);
  ctx.fillRect(x, y, w, h * 0.5);
  ctx.restore();
}

// ---------------------------------------------------------------------------------------------------------
// Registry & public API
// ---------------------------------------------------------------------------------------------------------

const REG = new Map();
const staticCache = new Map(); // key -> { def, canvas, texture, opts }
const animCache = new Map(); // key -> handle
const layerCache = new Map(); // key -> canvas (static sub-layers of animated cards)
const warned = new Set();

/** Registers a card. spec: { w, h, fps?, alpha?, opts? (doc string), atlas? }. draw(ctx, w, h, t, o). */
function card(id, spec, draw) {
  REG.set(id, { id, w: spec.w, h: spec.h, fps: spec.fps || 0, alpha: !!spec.alpha, opts: spec.opts || '', atlas: spec.atlas, draw });
}

/** Cached sub-layer (drawn once per key; cleared by invalidateAll). */
function layer(key, w, h, paint) {
  let c = layerCache.get(key);
  if (!c) {
    c = makeCanvas(w, h);
    paint(c.getContext('2d'), w, h);
    layerCache.set(key, c);
  }
  return c;
}

function optKey(o) {
  return Object.keys(o).sort().map((k) => `${k}=${JSON.stringify(o[k])}`).join('&');
}

function need(id) {
  const def = REG.get(id);
  if (def) return def;
  if (!warned.has(id)) { warned.add(id); console.warn(`[cards] unknown card id "${id}", showing snow`); }
  return REG.get('snow');
}

function resetState(ctx) {
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = 'source-over';
  ctx.shadowBlur = 0;
  ctx.shadowColor = 'rgba(0,0,0,0)';
  ctx.shadowOffsetX = ctx.shadowOffsetY = 0;
  ctx.filter = 'none';
  ctx.lineCap = 'butt';
  ctx.lineJoin = 'miter';
  ctx.setLineDash([]);
}

function render(def, ctx, t, o) {
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  resetState(ctx);
  ctx.clearRect(0, 0, def.w, def.h);
  def.draw(ctx, def.w, def.h, t, o);
  ctx.restore();
}

const quantize = (def, time) => (def.fps ? Math.floor(time * def.fps + 1e-6) / def.fps : time);

function wrap(canvas, id, animated) {
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  tex.name = `card:${id}`;
  if (animated) { tex.generateMipmaps = false; tex.minFilter = THREE.LinearFilter; }
  return tex;
}

/** Static card texture (see header). */
export function getCard(id, opts = {}) {
  const key = `${id}|${optKey(opts)}`;
  const hit = staticCache.get(key);
  if (hit) return hit.texture;
  const def = need(id);
  const canvas = makeCanvas(def.w, def.h);
  render(def, canvas.getContext('2d'), quantize(def, opts.time || 0), opts);
  const texture = wrap(canvas, id, false);
  if (def.atlas) texture.userData.atlas = def.atlas;
  staticCache.set(key, { def, canvas, texture, opts });
  return texture;
}

/** Animated card handle (see header). */
export function getAnimated(id, opts = {}) {
  const key = `${id}|${optKey(opts)}`;
  const hit = animCache.get(key);
  if (hit) return hit;
  const def = need(id);
  const canvas = makeCanvas(def.w, def.h);
  const ctx = canvas.getContext('2d');
  const texture = wrap(canvas, id, true);
  const o = { ...opts };
  let frame = -1, dirty = true, last = 0;
  const handle = {
    texture, canvas, opts: o,
    tick(time) {
      last = time;
      const f = def.fps ? Math.floor(time * def.fps + 1e-6) : 0;
      if (f === frame && !dirty) return false;
      frame = f;
      dirty = false;
      render(def, ctx, def.fps ? f / def.fps : time, o);
      texture.needsUpdate = true;
      return true;
    },
    set(patch) {
      Object.assign(o, patch);
      dirty = true;
    },
    redraw() {
      dirty = true;
      handle.tick(last);
    },
  };
  handle.tick(0);
  animCache.set(key, handle);
  return handle;
}

/** Draws a card into any 2D context at (0,0) scaled to w x h. */
export function drawTo(ctx, id, w, h, time = 0, opts = {}) {
  const def = need(id);
  ctx.save();
  resetState(ctx);
  ctx.scale(w / def.w, h / def.h);
  ctx.beginPath();
  ctx.rect(0, 0, def.w, def.h);
  ctx.clip();
  def.draw(ctx, def.w, def.h, quantize(def, time), opts);
  ctx.restore();
}

export function cardIds() {
  return [...REG.keys()];
}

export function cardInfo(id) {
  const d = REG.get(id);
  return d ? { w: d.w, h: d.h, fps: d.fps, alpha: d.alpha, opts: d.opts } : null;
}

/** Redraws every cached canvas (fonts arrived, palette tweak...). */
export function invalidateAll() {
  layerCache.clear();
  for (const e of staticCache.values()) {
    render(e.def, e.canvas.getContext('2d'), quantize(e.def, e.opts.time || 0), e.opts);
    e.texture.needsUpdate = true;
  }
  for (const h of animCache.values()) h.redraw();
}

/** Namespace form of the API (see header). */
export const cards = { get: getCard, animated: getAnimated, drawTo, ids: cardIds, info: cardInfo, invalidateAll };

if (typeof document !== 'undefined' && document.fonts) {
  document.fonts.addEventListener?.('loadingdone', () => invalidateAll());
  document.fonts.ready.then(() => invalidateAll());
}

// ---------------------------------------------------------------------------------------------------------
// Telly's face: vector shapes in a 64x48 box, rendered as glowing scanline dots
// ---------------------------------------------------------------------------------------------------------

const TELLY_EXPRS = ['idle', 'sleepy', 'happy', 'o_mouth', 'wink', 'pout', 'glare', 'shiver', 'zzz', 'baron_glitch'];

/** Draws expression `expr` in a 64x48 box. ink = lit, hole = unlit (pupils, lids). look = gaze [-1..1, -1..1]. */
function tellyFaceShapes(ctx, expr, t, look, ink, hole) {
  const lx = clamp(look[0], -1, 1), ly = clamp(look[1], -1, 1);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const L = 21, R = 43, EY = 19;
  const openEye = (x, y, rx = 7.5, ry = 9.5, pr = 3.8, gx = lx, gy = ly) => {
    ellipse(ctx, x, y, rx, ry);
    fill(ctx, ink);
    const px = x + gx * (rx - pr - 1.2), py = y + 1.2 + gy * (ry - pr - 2);
    circle(ctx, px, py, pr);
    fill(ctx, hole);
    circle(ctx, px - pr * 0.35, py - pr * 0.4, pr * 0.32);
    fill(ctx, ink);
  };
  const shutEye = (x, y, up, w = 7) => {
    ctx.beginPath();
    if (up) ctx.arc(x, y + 4.5, w, Math.PI * 1.15, Math.PI * 1.85);
    else ctx.arc(x, y - 3.5, w, Math.PI * 0.15, Math.PI * 0.85);
    stroke(ctx, ink, 3.4);
  };
  const flatEye = (x, y) => {
    ctx.beginPath();
    ctx.moveTo(x - 6.5, y + 1);
    ctx.quadraticCurveTo(x, y + 3, x + 6.5, y + 1);
    stroke(ctx, ink, 3.4);
  };
  const smile = (w = 10, d = 4.5, y = 33) => {
    ctx.beginPath();
    ctx.moveTo(32 - w, y);
    ctx.quadraticCurveTo(32, y + d * 2, 32 + w, y);
    stroke(ctx, ink, 3.4);
  };
  const Z = (x, y, s) => {
    poly(ctx, [x - s, y - s, x + s, y - s, x - s, y + s, x + s, y + s], false);
    stroke(ctx, ink, Math.max(1.6, s * 0.5));
  };
  const blink = fract(t / 3.7 + 0.13) > 0.955;

  switch (expr) {
    case 'sleepy':
      shutEye(L, EY + 2, false);
      shutEye(R, EY + 2, false);
      smile(5, 2, 35);
      break;
    case 'happy': {
      shutEye(L, EY, true);
      shutEye(R, EY, true);
      ctx.beginPath();
      ctx.moveTo(20, 30);
      ctx.lineTo(44, 30);
      ctx.quadraticCurveTo(44, 44, 32, 44);
      ctx.quadraticCurveTo(20, 44, 20, 30);
      fill(ctx, ink);
      ctx.beginPath();
      ctx.moveTo(23, 32.5);
      ctx.lineTo(41, 32.5);
      ctx.quadraticCurveTo(41, 41.5, 32, 41.5);
      ctx.quadraticCurveTo(23, 41.5, 23, 32.5);
      fill(ctx, hole);
      ellipse(ctx, 32, 40, 6, 3.2);
      fill(ctx, ink);
      break;
    }
    case 'o_mouth':
      openEye(L, EY, 8.5, 10.5, 3.2);
      openEye(R, EY, 8.5, 10.5, 3.2);
      ellipse(ctx, 32, 37, 4.5, 5.5);
      stroke(ctx, ink, 3.2);
      break;
    case 'wink':
      openEye(L, EY);
      shutEye(R, EY, true);
      ctx.beginPath();
      ctx.moveTo(R + 6, EY - 1);
      ctx.lineTo(R + 10, EY - 4);
      stroke(ctx, ink, 2.4);
      smile(11, 5, 32);
      ctx.beginPath();
      ctx.moveTo(34, 38.5);
      ctx.quadraticCurveTo(37, 45, 40, 37.5);
      fill(ctx, ink);
      break;
    case 'pout':
      for (const x of [L, R]) {
        openEye(x, EY + 1, 7.5, 9, 3.6, lx * 0.5, 0.8);
        ctx.fillStyle = hole;
        ctx.fillRect(x - 9, EY - 12, 18, 10.5);
        ctx.beginPath();
        ctx.moveTo(x - 7.5, EY - 1.5 + (x === L ? 1.5 : -0.5));
        ctx.lineTo(x + 7.5, EY - 1.5 + (x === L ? -0.5 : 1.5));
        stroke(ctx, ink, 2.6);
      }
      ctx.beginPath();
      ctx.moveTo(25, 39);
      ctx.quadraticCurveTo(32, 32, 39, 39);
      stroke(ctx, ink, 3.4);
      ctx.beginPath();
      ctx.moveTo(L - 3, EY + 11);
      ctx.quadraticCurveTo(L - 5.5, EY + 15, L - 3, EY + 16.5);
      ctx.quadraticCurveTo(L - 0.5, EY + 15, L - 3, EY + 11);
      fill(ctx, ink);
      break;
    case 'glare':
      openEye(L, EY + 1, 7.5, 9, 3.4, 0, 0.2);
      openEye(R, EY + 1, 7.5, 9, 3.4, 0, 0.2);
      poly(ctx, [10, 2, 31, 2, 31, 16, 10, 8]);
      fill(ctx, hole);
      poly(ctx, [54, 2, 33, 2, 33, 16, 54, 8]);
      fill(ctx, hole);
      ctx.beginPath();
      ctx.moveTo(12, 8);
      ctx.lineTo(29, 14.5);
      ctx.moveTo(52, 8);
      ctx.lineTo(35, 14.5);
      stroke(ctx, ink, 3.6);
      ctx.beginPath();
      ctx.moveTo(24, 37);
      ctx.lineTo(40, 35.5);
      stroke(ctx, ink, 3.4);
      break;
    case 'shiver': {
      const j = (Math.floor(t * 24) & 1 ? 1 : -1) * 0.9;
      ctx.save();
      ctx.translate(j, 0);
      openEye(L, EY, 8.5, 10.5, 2.3, 0, 0);
      openEye(R, EY, 8.5, 10.5, 2.3, 0, 0);
      const zz = [];
      for (let i = 0; i <= 8; i++) zz.push(21 + i * 2.75, i & 1 ? 32.5 : 37);
      poly(ctx, zz, false);
      stroke(ctx, ink, 2.6);
      ctx.beginPath();
      ctx.moveTo(55, 6);
      ctx.quadraticCurveTo(51, 12, 55, 14);
      ctx.quadraticCurveTo(59, 12, 55, 6);
      fill(ctx, ink);
      ctx.restore();
      break;
    }
    case 'zzz':
      shutEye(L, EY + 2, false);
      shutEye(R, EY + 2, false);
      ellipse(ctx, 32, 36, 2.8, 2.4);
      stroke(ctx, ink, 2.4);
      for (let k = 0; k < 3; k++) {
        const p = fract(t * 0.45 + k / 3);
        if (p > 0.92) continue;
        Z(49 + p * 9, 16 - p * 15, 2 + p * 3.2);
      }
      break;
    case 'baron_glitch':
      baronDots(ctx, t, ink, hole);
      break;
    default:
      if (blink) { flatEye(L, EY); flatEye(R, EY); } else { openEye(L, EY); openEye(R, EY); }
      smile(10, 4.5, 33);
  }
}

/** The Baron as dot-matrix line art (Telly glitch, EE step 4). */
function baronDots(ctx, t, ink, hole) {
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  poly(ctx, [6, 12, 20, 3, 32, 13, 44, 3, 58, 12], false);
  stroke(ctx, ink, 3);
  ctx.beginPath();
  ctx.moveTo(11, 13);
  ctx.lineTo(27, 18);
  ctx.moveTo(53, 13);
  ctx.lineTo(37, 18);
  stroke(ctx, ink, 3.6);
  ellipse(ctx, 21, 22, 6, 3.6, 0.2);
  fill(ctx, ink);
  ellipse(ctx, 43, 22, 6, 3.6, -0.2);
  fill(ctx, ink);
  circle(ctx, 21, 22.4, 2);
  fill(ctx, hole);
  circle(ctx, 43, 22.4, 2);
  fill(ctx, hole);
  circle(ctx, 43, 22, 9);
  stroke(ctx, ink, 1.8);
  ctx.beginPath();
  ctx.moveTo(51, 26);
  ctx.quadraticCurveTo(55, 36, 50, 46);
  stroke(ctx, ink, 1.2);
  const open = 2 + Math.abs(Math.sin(t * 9)) * 3;
  ctx.beginPath();
  ctx.moveTo(16, 32);
  ctx.quadraticCurveTo(32, 36, 48, 32);
  ctx.quadraticCurveTo(32, 40 + open, 16, 32);
  fill(ctx, ink);
  poly(ctx, [24, 33.4, 27.5, 33.8, 25.6, 38.5]);
  fill(ctx, hole);
  poly(ctx, [36.5, 33.8, 40, 33.4, 38.4, 38.5]);
  fill(ctx, hole);
}

let dotMask = null;
let dotGlow = null;
/**
 * Renders drawShapes (64x48 space, white on black) as a dot-matrix into (x, y, w, h).
 * o: { cols, rows, core, glow, dim, split, seed }
 */
function dotMatrix(ctx, x, y, w, h, drawShapes, o = {}) {
  const cols = o.cols || 64, rows = o.rows || 48;
  if (!dotMask) {
    dotMask = makeCanvas(64, 48);
    dotMask.ctx = dotMask.getContext('2d', { willReadFrequently: true });
  }
  if (dotMask.width !== cols || dotMask.height !== rows) {
    dotMask.width = cols;
    dotMask.height = rows;
  }
  const m = dotMask.ctx;
  m.setTransform(1, 0, 0, 1, 0, 0);
  m.fillStyle = '#000';
  m.fillRect(0, 0, cols, rows);
  m.scale(cols / 64, rows / 48);
  drawShapes(m);
  const data = m.getImageData(0, 0, cols, rows).data;
  const sx = w / cols, sy = h / rows, maxR = Math.min(sx, sy) * 0.46;
  const r = rng(o.seed || 1);
  const shift = new Float32Array(rows);
  if (o.split) for (let j = 0; j < rows; j++) shift[j] = r() < 0.12 ? (r() - 0.5) * sx * 6 : 0;
  const dots = new Path2D();
  const halo = new Path2D();
  for (let j = 0; j < rows; j++) {
    for (let i = 0; i < cols; i++) {
      const v = data[(j * cols + i) * 4] / 255;
      if (v < 0.14) continue;
      const cx = x + (i + 0.5) * sx + shift[j], cy = y + (j + 0.5) * sy, rad = maxR * (0.5 + 0.5 * v);
      dots.moveTo(cx + rad, cy);
      dots.arc(cx, cy, rad, 0, TAU);
      halo.moveTo(cx + rad * 2.2, cy);
      halo.arc(cx, cy, rad * 2.2, 0, TAU);
    }
  }
  if (o.dim !== false) {
    ctx.fillStyle = layerPattern(ctx, sx, sy, maxR * 0.42, o.dim || 'rgba(127,231,255,0.08)');
    ctx.save();
    ctx.translate(x, y);
    ctx.fillRect(0, 0, w, h);
    ctx.restore();
  }
  // Soft glow: halo dots drawn at quarter scale and upsampled (cheap blur).
  const gw = Math.max(8, Math.ceil(w / 4)), gh = Math.max(8, Math.ceil(h / 4));
  if (!dotGlow) dotGlow = makeCanvas(gw, gh);
  if (dotGlow.width < gw || dotGlow.height < gh) { dotGlow.width = gw; dotGlow.height = gh; }
  const g = dotGlow.getContext('2d');
  g.setTransform(1, 0, 0, 1, 0, 0);
  g.clearRect(0, 0, dotGlow.width, dotGlow.height);
  g.scale(0.25, 0.25);
  g.translate(-x, -y);
  g.fillStyle = o.glow || C.crt;
  g.fill(halo);
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  ctx.globalAlpha = 0.55;
  ctx.imageSmoothingEnabled = true;
  ctx.drawImage(dotGlow, 0, 0, gw, gh, x, y, gw * 4, gh * 4);
  ctx.restore();
  if (o.split) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.translate(-sx * 0.6, 0);
    ctx.fillStyle = 'rgba(255,60,200,0.75)';
    ctx.fill(dots);
    ctx.translate(sx * 1.2, 0);
    ctx.fillStyle = 'rgba(80,255,140,0.75)';
    ctx.fill(dots);
    ctx.restore();
  }
  ctx.fillStyle = o.core || '#E6FDFF';
  ctx.fill(dots);
}

const dimPatterns = new Map();
/** Pattern of unlit dots (the LED panel look), cached per spacing. */
function layerPattern(ctx, sx, sy, r, color) {
  const key = `${sx.toFixed(2)}|${sy.toFixed(2)}|${r.toFixed(2)}|${color}`;
  let tile = dimPatterns.get(key);
  if (!tile) {
    const tw = Math.max(1, Math.round(sx * 8)), th = Math.max(1, Math.round(sy * 8));
    tile = makeCanvas(tw, th);
    const g = tile.getContext('2d');
    g.fillStyle = color;
    g.beginPath();
    for (let j = 0; j < 8; j++) for (let i = 0; i < 8; i++) {
      const cx = ((i + 0.5) * tw) / 8, cy = ((j + 0.5) * th) / 8;
      g.moveTo(cx + r, cy);
      g.arc(cx, cy, r, 0, TAU);
    }
    g.fill();
    dimPatterns.set(key, tile);
  }
  return ctx.createPattern(tile, 'repeat');
}

/** Telly's face on a CRT rectangle (background + dots). */
function tellyScreen(ctx, x, y, w, h, expr, t, look = [0, 0], cols = 64) {
  const rows = Math.round(cols * 0.75);
  const glitch = expr === 'baron_glitch';
  ctx.fillStyle = radial(ctx, x + w / 2, y + h * 0.45, 0, Math.max(w, h) * 0.7,
    glitch ? ['#2A1840', '#150C22'] : ['#1D4656', '#10283A', '#0B1A28']);
  ctx.fillRect(x, y, w, h);
  dotMatrix(ctx, x + w * 0.04, y + h * 0.04, w * 0.92, h * 0.92,
    (m) => tellyFaceShapes(m, expr, t, look, '#fff', '#000'),
    { cols, rows, split: glitch, seed: Math.floor(t * 12) + 3, core: glitch ? '#F4E8FF' : '#E6FDFF', glow: glitch ? '#C77DFF' : C.crt });
}

// ---------------------------------------------------------------------------------------------------------
// Telly the console TV, the white glove, station logo, "13" badge
// ---------------------------------------------------------------------------------------------------------

/** White four-finger cartoon glove, wrist at (x, y), fingers pointing along -y rotated by rot. */
function drawGlove(ctx, x, y, s, rot = 0, pose = 'open') {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot);
  ctx.scale(s, s);
  const ol = 0.07;
  const fingers = pose === 'point'
    ? [[0.02, -0.52, 0.06, -1.22]]
    : [[-0.24, -0.55, -0.4, -1.08], [0, -0.6, 0.02, -1.2], [0.24, -0.55, 0.42, -1.06]];
  const curled = pose === 'point' ? [[-0.2, -0.5, -0.22, -0.72], [0.22, -0.5, 0.25, -0.7]] : [];
  const shapes = (extra, style) => {
    ctx.fillStyle = style;
    ctx.strokeStyle = style;
    ctx.lineCap = 'round';
    for (const [a, b, c2, d] of [...fingers, ...curled]) {
      ctx.beginPath(); ctx.moveTo(a, b); ctx.lineTo(c2, d);
      ctx.lineWidth = 0.27 + extra; ctx.stroke();
    }
    ctx.beginPath(); ctx.moveTo(-0.28, -0.35); ctx.lineTo(-0.68, -0.62);
    ctx.lineWidth = 0.25 + extra; ctx.stroke();
    ellipse(ctx, 0, -0.42, 0.42 + extra / 2, 0.36 + extra / 2);
    ctx.fill();
    ctx.beginPath();
    ctx.roundRect(-0.34 - extra / 2, -0.16 - extra / 2, 0.68 + extra, 0.34 + extra, 0.12);
    ctx.fill();
  };
  shapes(ol * 2, C.ink);
  shapes(0, '#FFFFFF');
  ctx.fillStyle = '#E4E0F2';
  ellipse(ctx, 0.08, -0.3, 0.3, 0.14);
  ctx.fill();
  ctx.beginPath();
  ctx.roundRect(-0.34, 0.06, 0.68, 0.12, 0.06);
  ctx.fill();
  ctx.strokeStyle = C.ink;
  ctx.lineWidth = 0.045;
  ctx.beginPath();
  for (const sx of [-0.14, 0, 0.14]) { ctx.moveTo(sx, -0.62); ctx.lineTo(sx * 1.2, -0.4); }
  ctx.moveTo(-0.34, 0.0);
  ctx.lineTo(0.34, 0.0);
  ctx.stroke();
  ctx.restore();
}

/**
 * Telly, the walnut console TV mascot. (cx, cy) = cabinet centre, s = cabinet width.
 * o: { expr, t, look, wave (glove angle, radians) , hop, cols }
 */
function drawTelly(ctx, cx, cy, s, o = {}) {
  const t = o.t || 0;
  const w = s, h = s * 0.74, x = cx - w / 2, y = cy - h / 2, ol = Math.max(1.5, s * 0.016);
  ctx.save();
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  // rabbit ears
  const ax = x + w * 0.42, ay = y + s * 0.01;
  for (const side of [-1, 1]) {
    const a = side * (26 + (o.earTwitch || 0) * side) * DEG, len = s * 0.52;
    const ex = ax + Math.sin(a) * len, ey = ay - Math.cos(a) * len;
    capsule(ctx, ax, ay, ex, ey, s * 0.02, '#D5DAE8', C.ink, ol * 0.7);
    circle(ctx, ex, ey, s * 0.032);
    inked(ctx, radial(ctx, ex - s * 0.01, ey - s * 0.01, 0, s * 0.04, ['#FFFFFF', '#BFC6DA']), ol * 0.7);
  }
  ellipse(ctx, ax, ay + s * 0.012, s * 0.08, s * 0.05);
  inked(ctx, linear(ctx, 0, ay - s * 0.04, 0, ay + s * 0.05, ['#6A4A3A', '#3A2630']), ol);
  // legs
  for (const [lx, dir] of [[0.17, -1], [0.83, 1]]) {
    const bx = x + w * lx, by = y + h - ol;
    poly(ctx, [bx - s * 0.035, by, bx + s * 0.035, by, bx + dir * s * 0.075 + s * 0.013, by + s * 0.25, bx + dir * s * 0.075 - s * 0.013, by + s * 0.25]);
    inked(ctx, linear(ctx, bx - s * 0.04, 0, bx + s * 0.04, 0, ['#6A3E22', '#4A2A18']), ol);
    rr(ctx, bx + dir * s * 0.075 - s * 0.018, by + s * 0.22, s * 0.036, s * 0.04, s * 0.01);
    inked(ctx, C.brass, ol * 0.7);
  }
  // cabinet
  rr(ctx, x, y, w, h, s * 0.09);
  inked(ctx, linear(ctx, 0, y, 0, y + h, ['#B27A45', '#8C5630', '#6A3C20']), ol * 1.3);
  ctx.save();
  rr(ctx, x, y, w, h, s * 0.09);
  ctx.clip();
  const g = rng(42);
  ctx.strokeStyle = 'rgba(70,36,18,0.28)';
  ctx.lineWidth = Math.max(1, s * 0.006);
  for (let i = 0; i < 16; i++) {
    const yy = y + h * (i + 0.5) / 16 + g() * 3;
    ctx.beginPath();
    ctx.moveTo(x, yy);
    ctx.bezierCurveTo(x + w * 0.3, yy + (g() - 0.5) * s * 0.05, x + w * 0.6, yy + (g() - 0.5) * s * 0.05, x + w, yy + (g() - 0.5) * 4);
    ctx.stroke();
  }
  ctx.fillStyle = 'rgba(255,220,170,0.28)';
  ctx.fillRect(x, y + s * 0.008, w, s * 0.03);
  ctx.restore();
  // screen
  const bx = x + w * 0.055, by = y + h * 0.1, bw = w * 0.62, bh = h * 0.8;
  rr(ctx, bx, by, bw, bh, bh * 0.26);
  inked(ctx, linear(ctx, 0, by, 0, by + bh, ['#FBF1D8', '#E3D2AA', '#BCA57A']), ol);
  const ins = s * 0.028, sx = bx + ins, sy = by + ins, sw = bw - ins * 2, sh = bh - ins * 2;
  ctx.save();
  rr(ctx, sx, sy, sw, sh, sh * 0.24);
  ctx.clip();
  tellyScreen(ctx, sx, sy, sw, sh, o.expr || 'idle', t, o.look || [0, 0], o.cols || clamp(Math.round(sw / 4.2), 20, 64));
  ctx.fillStyle = linear(ctx, sx, sy, sx + sw * 0.6, sy + sh * 0.6, ['rgba(255,255,255,0.22)', 'rgba(255,255,255,0.04)', 'rgba(255,255,255,0)']);
  ctx.beginPath();
  ctx.ellipse(sx + sw * 0.28, sy + sh * 0.18, sw * 0.34, sh * 0.16, -0.2, 0, TAU);
  ctx.fill();
  ctx.restore();
  rr(ctx, sx, sy, sw, sh, sh * 0.24);
  stroke(ctx, C.ink, ol);
  // controls
  const kx = x + w * 0.835;
  const dr = s * 0.078, dy0 = y + h * 0.27;
  circle(ctx, kx, dy0, dr * 1.25);
  inked(ctx, '#5A341C', ol * 0.8);
  ctx.strokeStyle = '#F6E7C8';
  ctx.lineWidth = Math.max(1, s * 0.006);
  ctx.beginPath();
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * TAU;
    ctx.moveTo(kx + Math.cos(a) * dr * 1.02, dy0 + Math.sin(a) * dr * 1.02);
    ctx.lineTo(kx + Math.cos(a) * dr * 1.16, dy0 + Math.sin(a) * dr * 1.16);
  }
  ctx.stroke();
  circle(ctx, kx, dy0, dr * 0.9);
  inked(ctx, radial(ctx, kx - dr * 0.3, dy0 - dr * 0.3, 0, dr, ['#FFF8E6', '#E8D6B0', '#B89D70']), ol * 0.8);
  const da = (o.dial ?? 0.6) * TAU;
  capsule(ctx, kx, dy0, kx + Math.sin(da) * dr * 0.7, dy0 - Math.cos(da) * dr * 0.7, dr * 0.22, C.red);
  circle(ctx, kx, y + h * 0.49, s * 0.034);
  inked(ctx, radial(ctx, kx, y + h * 0.48, 0, s * 0.04, ['#FFF8E6', '#B89D70']), ol * 0.8);
  const gy = y + h * 0.74, gr = s * 0.095;
  ctx.save();
  circle(ctx, kx, gy, gr);
  ctx.clip();
  ctx.fillStyle = '#4A2A18';
  ctx.fillRect(kx - gr, gy - gr, gr * 2, gr * 2);
  rays(ctx, kx, gy, gr, 14, '#C8905A', 0.1, 0.45);
  ctx.restore();
  circle(ctx, kx, gy, gr);
  stroke(ctx, C.ink, ol * 0.8);
  circle(ctx, kx, gy, gr * 0.22);
  inked(ctx, C.brass, ol * 0.6);
  // glove waving out of the screen edge
  if (o.wave !== undefined) {
    const sx0 = bx + bw - ins * 0.5, sy0 = by + bh * 0.45;
    const gx = x + w * 1.02 + Math.sin(o.wave) * s * 0.06, gyy = y - s * 0.12;
    ctx.beginPath();
    ctx.moveTo(sx0, sy0);
    ctx.bezierCurveTo(sx0 + s * 0.22, sy0, gx - s * 0.05, gyy + s * 0.35, gx, gyy + s * 0.04);
    ctx.strokeStyle = C.ink;
    ctx.lineWidth = s * 0.075 + ol * 2;
    ctx.stroke();
    ctx.strokeStyle = '#F4F2FA';
    ctx.lineWidth = s * 0.075;
    ctx.stroke();
    drawGlove(ctx, gx, gyy + s * 0.04, s * 0.26, o.wave, 'open');
  }
  ctx.restore();
}

/** Blue disc, red ring, white "13" (colours overridable: the cap badge is white/red/blue). */
function badge13(ctx, x, y, r, o = {}) {
  circle(ctx, x, y, r);
  inked(ctx, o.ring || C.red, o.ol ?? r * 0.06);
  circle(ctx, x, y, r * 0.8);
  fill(ctx, o.disc || C.blue);
  if (o.inner) { circle(ctx, x, y, r * 0.8); stroke(ctx, o.inner, r * 0.05); }
  // Letter in device pixels, so the badge also works inside unit-space drawings (busts).
  const m = ctx.getTransform(), k = Math.hypot(m.a, m.b) || 1;
  ctx.save();
  ctx.translate(x, y + r * 0.06);
  ctx.scale(1 / k, 1 / k);
  label(ctx, '13', 0, 0, { fam: FONT.round, px: r * 0.92 * k, maxW: r * 1.25 * k, fill: o.num || '#FFFFFF' });
  ctx.restore();
  ctx.save();
  circle(ctx, x, y, r);
  ctx.clip();
  ctx.fillStyle = linear(ctx, 0, y - r, 0, y, ['rgba(255,255,255,0.35)', 'rgba(255,255,255,0)']);
  ctx.fillRect(x - r, y - r, r * 2, r);
  ctx.restore();
}

/**
 * WZTV + 13 station logo centred at (cx, cy), cap height h.
 * o: { style: 'neon' | 'flat', dead: ['Z','T'], lit: true }
 */
function drawLogo(ctx, cx, cy, h, o = {}) {
  const letters = ['W', 'Z', 'T', 'V'];
  ctx.save();
  setFont(ctx, h * 1.25, FONT.sign);
  const ws = letters.map((l) => ctx.measureText(l).width);
  const gap = h * 0.06, disc = h * 1.2;
  const total = ws.reduce((a, b) => a + b, 0) + gap * 4 + disc;
  let x = cx - total / 2;
  ctx.textBaseline = 'middle';
  ctx.textAlign = 'left';
  ctx.lineJoin = 'round';
  letters.forEach((l, i) => {
    const col = NEON[l], dead = o.dead?.includes(l) || o.lit === false;
    if (o.style === 'neon') {
      ctx.save();
      ctx.lineWidth = h * 0.1;
      ctx.strokeStyle = dead ? darken(col, 0.45) : col;
      if (!dead) { ctx.shadowColor = col; ctx.shadowBlur = h * 0.5; }
      ctx.strokeText(l, x, cy);
      ctx.strokeText(l, x, cy);
      ctx.shadowBlur = 0;
      ctx.lineWidth = h * 0.035;
      ctx.strokeStyle = dead ? darken(col, 0.25) : lighten(col, 0.75);
      ctx.strokeText(l, x, cy);
      ctx.restore();
    } else {
      for (let k = Math.round(h * 0.12); k > 0; k--) {
        ctx.fillStyle = darken(col, 0.5);
        ctx.fillText(l, x + k * 0.6, cy + k);
      }
      ctx.lineWidth = h * 0.09;
      ctx.strokeStyle = C.ink;
      ctx.strokeText(l, x, cy);
      ctx.fillStyle = linear(ctx, 0, cy - h * 0.6, 0, cy + h * 0.6, [lighten(col, 0.35), col, darken(col, 0.15)]);
      ctx.fillText(l, x, cy);
    }
    x += ws[i] + gap;
  });
  const dr = disc / 2;
  if (o.style === 'neon' && o.lit !== false) {
    ctx.save();
    ctx.shadowColor = '#7FB0FF';
    ctx.shadowBlur = h * 0.5;
    circle(ctx, x + dr, cy, dr);
    fill(ctx, C.red);
    ctx.restore();
  }
  badge13(ctx, x + dr, cy, dr, { ol: h * 0.05 });
  ctx.restore();
}

// ---------------------------------------------------------------------------------------------------------
// Cartoon busts (portraits, posters, magazine). Unit space: face centre (0,0), head radius 1.
// ---------------------------------------------------------------------------------------------------------

const LW = 0.055;
const SKIN = { skip: '#F2C29B', roxy: '#8A5A3C', penny: '#F4C7A6', duke: '#E6B089', baron: '#CBC2DD', stu: '#F0BE96' };

/** Text inside a scaled unit-space transform (fonts are specified in device pixels). */
function uText(ctx, str, x, y, px, fam, style, o = {}) {
  const m = ctx.getTransform(), s = Math.hypot(m.a, m.b);
  ctx.save();
  ctx.translate(x, y);
  if (o.rot) ctx.rotate(o.rot);
  ctx.scale(1 / s, 1 / s);
  label(ctx, str, 0, 0, { fam, px: px * s, fill: style, stroke: o.stroke, lw: o.lw ? o.lw * s : undefined, maxW: o.maxW ? o.maxW * s : undefined });
  ctx.restore();
}

function headPath(ctx, jaw = 1, long = 1) {
  const cw = 0.6 * jaw + 0.1, by = 0.98 * long;
  ctx.beginPath();
  ctx.moveTo(0, -1);
  ctx.bezierCurveTo(0.62, -1, 0.9, -0.62, 0.9, -0.1);
  ctx.bezierCurveTo(0.9, 0.45 * long, cw, by * 0.96, 0, by);
  ctx.bezierCurveTo(-cw, by * 0.96, -0.9, 0.45 * long, -0.9, -0.1);
  ctx.bezierCurveTo(-0.9, -0.62, -0.62, -1, 0, -1);
  ctx.closePath();
}
function faceBase(ctx, skin, jaw = 1, long = 1, blush = 0.26) {
  headPath(ctx, jaw, long);
  inked(ctx, radial(ctx, -0.2, -0.25, 0.05, 1.25, [lighten(skin, 0.16), skin, darken(skin, 0.14)]), LW);
  if (blush) {
    for (const s of [-1, 1]) { ellipse(ctx, s * 0.52, 0.36, 0.19, 0.11); fill(ctx, alpha('#FF6B6B', blush)); }
  }
}
function ears(ctx, skin, y = 0.08, pointed = false) {
  for (const s of [-1, 1]) {
    ctx.beginPath();
    if (pointed) {
      ctx.moveTo(s * 0.84, -0.12);
      ctx.quadraticCurveTo(s * 1.3, -0.45, s * 1.12, 0.05);
      ctx.quadraticCurveTo(s * 1.05, 0.34, s * 0.84, 0.3);
    } else {
      ctx.ellipse(s * 0.9, y, 0.15, 0.21, 0, 0, TAU);
    }
    inked(ctx, skin, LW);
    ctx.beginPath();
    ctx.arc(s * 0.92, y, 0.08, s > 0 ? -1.2 : 1.9, s > 0 ? 1.2 : 4.3);
    stroke(ctx, darken(skin, 0.25), 0.035);
  }
}
function neck(ctx, skin, w = 0.3) {
  rr(ctx, -w, 0.55, w * 2, 0.75, 0.1);
  inked(ctx, darken(skin, 0.1), LW);
  ellipse(ctx, 0, 0.82, w * 0.9, 0.12);
  fill(ctx, alpha(darken(skin, 0.4), 0.35));
}
/** Pair of big cartoon eyes. o: { y, x, rx, ry, iris, lash, wink, look, lid, squint, tiny } */
function eyes(ctx, skin, o = {}) {
  const y = o.y ?? 0.06, ex0 = o.x ?? 0.34, rx = o.rx ?? 0.19, ry = o.ry ?? 0.23;
  const look = o.look || [0.04, 0];
  for (const s of [-1, 1]) {
    const ex = s * ex0;
    if (o.wink && s === 1) {
      ctx.beginPath();
      ctx.arc(ex, y + ry * 0.55, rx * 1.05, Math.PI * 1.15, Math.PI * 1.85);
      stroke(ctx, C.ink, 0.07);
      if (o.lash) { capsule(ctx, ex + rx * 0.9, y - ry * 0.05, ex + rx * 1.3, y - ry * 0.3, 0.035, C.ink); }
      continue;
    }
    ellipse(ctx, ex, y, rx, ry);
    inked(ctx, '#FFFDF6', 0.04);
    ctx.save();
    ellipse(ctx, ex, y, rx, ry);
    ctx.clip();
    const ix = ex + look[0] * rx * 0.4, iy = y + ry * 0.12 + look[1] * ry * 0.3, ir = rx * (o.tiny ? 0.45 : 0.78);
    circle(ctx, ix, iy, ir);
    fill(ctx, radial(ctx, ix, iy - ir * 0.3, ir * 0.1, ir, [lighten(o.iris || '#6B3A1E', 0.35), o.iris || '#6B3A1E', darken(o.iris || '#6B3A1E', 0.35)]));
    circle(ctx, ix, iy, ir * 0.5);
    fill(ctx, '#1E1428');
    circle(ctx, ix + ir * 0.35, iy - ir * 0.4, ir * 0.3);
    fill(ctx, '#FFFFFF');
    circle(ctx, ix - ir * 0.35, iy + ir * 0.35, ir * 0.13);
    fill(ctx, '#FFFFFF');
    if (o.lid) { ctx.fillStyle = skin; ctx.fillRect(ex - rx, y - ry, rx * 2, ry * 2 * o.lid); }
    if (o.squint) { ctx.fillStyle = skin; ctx.beginPath(); ctx.ellipse(ex, y + ry * 1.25, rx * 1.3, ry * 0.7, 0, 0, TAU); ctx.fill(); }
    ctx.restore();
    ctx.beginPath();
    ctx.ellipse(ex, y, rx, ry, 0, Math.PI * 1.02, Math.PI * 1.98);
    stroke(ctx, C.ink, 0.075);
    if (o.lid) {
      ctx.beginPath();
      ctx.moveTo(ex - rx, y - ry + ry * 2 * o.lid);
      ctx.lineTo(ex + rx, y - ry + ry * 2 * o.lid);
      stroke(ctx, C.ink, 0.06);
    }
    if (o.lash) {
      capsule(ctx, ex + s * rx * 0.85, y - ry * 0.55, ex + s * rx * 1.28, y - ry * 0.85, 0.035, C.ink);
      capsule(ctx, ex + s * rx * 0.98, y - ry * 0.2, ex + s * rx * 1.38, y - ry * 0.35, 0.035, C.ink);
    }
  }
}
function brows(ctx, color, y = -0.26, tilt = 0, thick = 0.075, x = 0.34, len = 0.2, arch = 0.04) {
  for (const s of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(s * (x - len), y + tilt);
    ctx.quadraticCurveTo(s * x, y - arch - 0.02, s * (x + len), y - tilt * 0.4);
    ctx.lineCap = 'round';
    stroke(ctx, color, thick);
  }
}
function nose(ctx, skin, y = 0.3, w = 0.1) {
  ellipse(ctx, 0, y, w, w * 0.78);
  fill(ctx, darken(skin, 0.1));
  ellipse(ctx, -w * 0.25, y - w * 0.25, w * 0.35, w * 0.25);
  fill(ctx, alpha('#FFFFFF', 0.35));
}
/** Mouth. kind: smile | grin (open with teeth) | smirk | line | o */
function mouth(ctx, kind = 'smile', y = 0.58, w = 0.24, lip = null) {
  ctx.lineCap = 'round';
  if (kind === 'grin') {
    ctx.beginPath();
    ctx.moveTo(-w, y - 0.04);
    ctx.quadraticCurveTo(0, y + 0.04, w, y - 0.04);
    ctx.quadraticCurveTo(w * 0.8, y + 0.26, 0, y + 0.26);
    ctx.quadraticCurveTo(-w * 0.8, y + 0.26, -w, y - 0.04);
    inked(ctx, '#7A2A3A', 0.045);
    ctx.save();
    ctx.clip();
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(-w, y - 0.08, w * 2, 0.1);
    ellipse(ctx, 0, y + 0.26, w * 0.55, 0.1);
    fill(ctx, '#E86A7A');
    ctx.restore();
  } else if (kind === 'o') {
    ellipse(ctx, 0, y + 0.04, w * 0.35, w * 0.45);
    inked(ctx, '#7A2A3A', 0.045);
  } else {
    ctx.beginPath();
    const cur = kind === 'line' ? 0.01 : kind === 'smirk' ? 0.06 : 0.14;
    ctx.moveTo(-w, y - (kind === 'smirk' ? -0.02 : 0));
    ctx.quadraticCurveTo(0, y + cur, w, y - (kind === 'smirk' ? 0.07 : 0));
    stroke(ctx, lip || C.ink, lip ? 0.1 : 0.055);
  }
}
/** Shoulders/torso silhouette path from the neck down past the frame. */
function torsoPath(ctx, wide = 1) {
  ctx.beginPath();
  ctx.moveTo(-0.36, 0.95);
  ctx.bezierCurveTo(-0.9 * wide, 1.02, -1.5 * wide, 1.22, -1.6 * wide, 1.95);
  ctx.lineTo(-1.7 * wide, 2.9);
  ctx.lineTo(1.7 * wide, 2.9);
  ctx.lineTo(1.6 * wide, 1.95);
  ctx.bezierCurveTo(1.5 * wide, 1.22, 0.9 * wide, 1.02, 0.36, 0.95);
  ctx.closePath();
}
function curl(ctx, x, y, r, col) {
  circle(ctx, x, y, r);
  inked(ctx, col, LW * 0.9);
  ctx.beginPath();
  ctx.arc(x + r * 0.1, y + r * 0.05, r * 0.55, 0.3, 4.2);
  stroke(ctx, darken(col, 0.35), 0.035);
}

// Skip Kowalski: crew cap, curls, square glasses, blue shirt, headphones.
function bustSkip(ctx, o) {
  const skin = SKIN.skip, hair = '#6B3A1E';
  for (const s of [-1, 1]) {
    for (const [x, y, r] of [[0.66, -0.5, 0.24], [0.86, -0.2, 0.26], [0.95, 0.12, 0.25], [0.86, 0.42, 0.22], [0.66, 0.58, 0.18]]) curl(ctx, s * x, y, r, hair);
  }
  torsoPath(ctx, 0.95);
  inked(ctx, linear(ctx, 0, 1, 0, 2.6, [lighten(C.blue, 0.12), C.blue, darken(C.blue, 0.2)]), LW);
  poly(ctx, [-0.42, 0.98, 0.42, 0.98, 0.3, 2.9, -0.3, 2.9]);
  inked(ctx, '#F7F4EC', LW);
  for (const s of [-1, 1]) {
    poly(ctx, [s * 0.34, 0.95, s * 0.78, 1.08, s * 0.52, 1.62]);
    inked(ctx, lighten(C.blue, 0.08), LW);
    circle(ctx, s * 0.36, 1.95 + (s > 0 ? 0 : 0.35), 0.05);
    inked(ctx, '#FFFFFF', 0.03);
  }
  rr(ctx, 0.62, 1.62, 0.36, 0.5, 0.05);
  inked(ctx, '#FFFFFF', 0.035);
  ctx.fillStyle = C.blue; ctx.fillRect(0.66, 1.68, 0.28, 0.08);
  ctx.fillStyle = C.red; ctx.fillRect(0.66, 1.78, 0.28, 0.025);
  badge13(ctx, 0.8, 1.93, 0.09, { ol: 0.015 });
  neck(ctx, skin);
  // headphones round the neck
  ctx.beginPath();
  ctx.ellipse(0, 1.0, 0.62, 0.2, 0, 0.1, Math.PI - 0.1);
  stroke(ctx, '#2C2632', 0.09);
  for (const s of [-1, 1]) {
    ellipse(ctx, s * 0.6, 1.06, 0.17, 0.22, s * 0.3);
    inked(ctx, linear(ctx, 0, 0.85, 0, 1.3, ['#4A4452', '#221E2A']), LW);
    ellipse(ctx, s * 0.6, 1.06, 0.09, 0.12, s * 0.3);
    fill(ctx, '#5E5868');
  }
  ears(ctx, skin);
  faceBase(ctx, skin, 0.95);
  for (const [x, y, r] of [[-0.42, -0.62, 0.16], [-0.12, -0.7, 0.15], [0.2, -0.68, 0.15], [0.48, -0.6, 0.14]]) curl(ctx, x, y, r, hair);
  eyes(ctx, skin, { iris: '#7A4520', wink: o.wink, y: 0.08 });
  brows(ctx, hair, -0.3, 0, 0.07);
  nose(ctx, skin, 0.33);
  mouth(ctx, o.mouth || 'smile', 0.6, 0.22);
  // square glasses
  for (const s of [-1, 1]) { rr(ctx, s * 0.34 - 0.27, -0.16, 0.54, 0.46, 0.1); stroke(ctx, '#1E1824', 0.085); }
  capsule(ctx, -0.08, -0.02, 0.08, -0.02, 0.06, '#1E1824');
  for (const s of [-1, 1]) capsule(ctx, s * 0.61, -0.06, s * 0.86, -0.1, 0.06, '#1E1824');
  // cap
  ctx.beginPath();
  ctx.moveTo(-0.98, -0.5);
  ctx.bezierCurveTo(-1.02, -1.7, 1.02, -1.7, 0.98, -0.5);
  ctx.closePath();
  inked(ctx, linear(ctx, 0, -1.45, 0, -0.5, [lighten(C.blue, 0.15), C.blue]), LW);
  ctx.beginPath();
  ctx.moveTo(-0.6, -0.52);
  ctx.bezierCurveTo(-0.62, -1.58, 0.62, -1.58, 0.6, -0.52);
  ctx.closePath();
  inked(ctx, linear(ctx, 0, -1.45, 0, -0.5, ['#FFFFFF', '#E8E2D4']), LW * 0.8);
  circle(ctx, 0, -1.4, 0.08);
  inked(ctx, C.blue, 0.035);
  badge13(ctx, 0, -0.95, 0.3, { disc: '#FFFFFF', ring: C.red, num: C.blue, ol: 0.03 });
  ctx.beginPath();
  ctx.ellipse(0, -0.5, 1.02, 0.2, 0, 0, TAU);
  inked(ctx, linear(ctx, 0, -0.7, 0, -0.3, [lighten(C.blue, 0.1), darken(C.blue, 0.25)]), LW);
}

// Roxy Rivers: huge afro, floral headband, gold hoops, flower-print crop shirt.
function bustRoxy(ctx, o) {
  const skin = SKIN.roxy, fro = '#3A2418';
  const r = rng(11);
  ellipse(ctx, 0, -0.42, 1.62, 1.5);
  inked(ctx, fro, LW);
  const bumps = [];
  for (let i = 0; i < 26; i++) {
    const a = (i / 26) * TAU + r() * 0.1;
    bumps.push([Math.cos(a) * 1.5, -0.42 + Math.sin(a) * 1.38, 0.34 + r() * 0.1]);
  }
  for (let i = 0; i < 16; i++) bumps.push([(r() - 0.5) * 2.2, -0.42 + (r() - 0.5) * 2.0, 0.3 + r() * 0.08]);
  for (const [x, y, br] of bumps) {
    circle(ctx, x, y, br);
    inked(ctx, radial(ctx, x - br * 0.35, y - br * 0.4, br * 0.1, br * 1.1, ['#6A4632', '#4A2F20', '#2E1A10']), 0.03, '#24140C');
  }
  torsoPath(ctx, 0.9);
  inked(ctx, linear(ctx, 0, 1, 0, 2.6, ['#FFFDF6', '#EDE4D0']), LW);
  for (const [x, y] of [[-1.05, 1.6], [0.9, 1.45], [-0.6, 2.2], [1.25, 2.3], [0.5, 2.5]]) flower(ctx, x, y, 0.2, '#F08A1E', '#FFD23A');
  poly(ctx, [-0.34, 0.96, 0.34, 0.96, 0, 1.75]);
  inked(ctx, darken(skin, 0.05), LW);
  for (const s of [-1, 1]) {
    poly(ctx, [s * 0.3, 0.92, s * 0.95, 1.18, s * 0.46, 1.5, s * 0.12, 1.55]);
    inked(ctx, '#FFFFFF', LW);
  }
  neck(ctx, skin, 0.28);
  ears(ctx, skin);
  for (const s of [-1, 1]) {
    circle(ctx, s * 0.92, 0.5, 0.2);
    stroke(ctx, C.ink, 0.1);
    circle(ctx, s * 0.92, 0.5, 0.2);
    stroke(ctx, '#F2C14E', 0.065);
  }
  faceBase(ctx, skin, 0.9, 1, 0.18);
  eyes(ctx, skin, { iris: '#5A3218', lash: true, wink: o.wink, rx: 0.2, ry: 0.24 });
  brows(ctx, '#24140C', -0.27, -0.02, 0.06, 0.34, 0.2, 0.08);
  nose(ctx, skin, 0.32, 0.11);
  ctx.beginPath();
  ctx.moveTo(-0.22, 0.56);
  ctx.quadraticCurveTo(0, 0.74, 0.22, 0.56);
  ctx.quadraticCurveTo(0, 0.62, -0.22, 0.56);
  inked(ctx, '#D9543A', 0.035);
  // floral headband
  ctx.beginPath();
  ctx.moveTo(-0.95, -0.42);
  ctx.bezierCurveTo(-0.7, -1.02, 0.7, -1.02, 0.95, -0.42);
  ctx.lineCap = 'round';
  stroke(ctx, C.ink, 0.3);
  stroke(ctx, '#F0801E', 0.22);
  for (const [x, y] of [[-0.62, -0.72], [-0.2, -0.86], [0.24, -0.86], [0.64, -0.7]]) flower(ctx, x, y, 0.1, '#FFD23A', '#E3462B');
}

function flower(ctx, x, y, r, petal, center) {
  ctx.beginPath();
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * TAU;
    ctx.moveTo(x + Math.cos(a) * r * 0.55 + r * 0.45, y + Math.sin(a) * r * 0.55);
    ctx.arc(x + Math.cos(a) * r * 0.55, y + Math.sin(a) * r * 0.55, r * 0.45, 0, TAU);
  }
  inked(ctx, petal, r * 0.12);
  circle(ctx, x, y, r * 0.3);
  fill(ctx, center);
}

// Penny Watts: long wavy hair, orange headband, round glasses, ribbed turtleneck, medallion.
function bustPenny(ctx, o) {
  const skin = SKIN.penny, hair = '#5A3320';
  ctx.beginPath();
  ctx.moveTo(0, -1.2);
  ctx.bezierCurveTo(1.2, -1.2, 1.25, 0, 1.2, 0.8);
  ctx.bezierCurveTo(1.35, 1.3, 1.1, 1.8, 1.25, 2.3);
  ctx.lineTo(-1.25, 2.3);
  ctx.bezierCurveTo(-1.1, 1.8, -1.35, 1.3, -1.2, 0.8);
  ctx.bezierCurveTo(-1.25, 0, -1.2, -1.2, 0, -1.2);
  inked(ctx, linear(ctx, 0, -1.2, 0, 2.3, [lighten(hair, 0.12), hair, darken(hair, 0.2)]), LW);
  torsoPath(ctx, 0.9);
  inked(ctx, linear(ctx, 0, 1, 0, 2.6, ['#FF7A32', '#F0641E', '#C84E14']), LW);
  ctx.strokeStyle = alpha('#9A3A0E', 0.35);
  ctx.lineWidth = 0.025;
  ctx.beginPath();
  for (let x = -1.5; x <= 1.5; x += 0.1) { ctx.moveTo(x, 1.35); ctx.lineTo(x * 1.05, 2.9); }
  ctx.stroke();
  // front locks over the shoulders
  for (const s of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(s * 0.7, 0.2);
    ctx.bezierCurveTo(s * 1.25, 0.9, s * 0.85, 1.4, s * 1.18, 2.1);
    ctx.bezierCurveTo(s * 0.95, 1.9, s * 1.0, 1.7, s * 0.9, 1.5);
    ctx.bezierCurveTo(s * 0.6, 1.1, s * 0.75, 0.7, s * 0.6, 0.35);
    inked(ctx, hair, LW);
  }
  neck(ctx, skin, 0.27);
  rr(ctx, -0.42, 0.9, 0.84, 0.36, 0.16);
  inked(ctx, linear(ctx, 0, 0.9, 0, 1.26, ['#FF8A42', '#E0561A']), LW);
  ctx.beginPath();
  ctx.moveTo(-0.3, 1.2);
  ctx.quadraticCurveTo(0, 1.9, 0.3, 1.2);
  stroke(ctx, '#C9961E', 0.03);
  circle(ctx, 0, 1.88, 0.14);
  inked(ctx, radial(ctx, -0.04, 1.84, 0.01, 0.16, ['#FFE9A0', '#E8B030', '#B07A16']), 0.03);
  ears(ctx, skin);
  for (const s of [-1, 1]) {
    circle(ctx, s * 0.9, 0.46, 0.16);
    stroke(ctx, C.ink, 0.09);
    circle(ctx, s * 0.9, 0.46, 0.16);
    stroke(ctx, '#F2C14E', 0.055);
  }
  faceBase(ctx, skin, 0.88);
  eyes(ctx, skin, { iris: '#6A3A1C', lash: true, wink: o.wink });
  brows(ctx, hair, -0.3, 0, 0.06, 0.34, 0.18, 0.05);
  nose(ctx, skin, 0.33, 0.09);
  mouth(ctx, 'smile', 0.6, 0.18, '#D9605A');
  for (const s of [-1, 1]) { circle(ctx, s * 0.34, 0.06, 0.28); stroke(ctx, '#1E1824', 0.075); }
  capsule(ctx, -0.07, 0.02, 0.07, 0.02, 0.05, '#1E1824');
  // side-swept fringe + headband
  ctx.beginPath();
  ctx.moveTo(-0.92, -0.2);
  ctx.bezierCurveTo(-1.0, -1.1, 0.4, -1.3, 0.92, -0.5);
  ctx.bezierCurveTo(0.5, -0.72, 0.0, -0.66, -0.35, -0.42);
  ctx.bezierCurveTo(-0.6, -0.3, -0.75, -0.2, -0.92, -0.2);
  inked(ctx, linear(ctx, -0.9, -1.1, 0.8, -0.3, [lighten(hair, 0.18), hair]), LW);
  ctx.beginPath();
  ctx.moveTo(-0.88, -0.62);
  ctx.bezierCurveTo(-0.6, -1.18, 0.6, -1.18, 0.88, -0.62);
  ctx.lineCap = 'round';
  stroke(ctx, C.ink, 0.22);
  stroke(ctx, '#F57A1E', 0.15);
}

/**
 * Duke Dalton: feathered hair, chevron mustache, orange aviators, big collar.
 * o: { wink, hat: 'cowboy'|'beret'|'headband'|null, outfit: 'disco'|'western'|'tux'|'camo'|'leather' }
 */
function bustDuke(ctx, o) {
  const skin = SKIN.duke, hair = '#6B3A1E', outfit = o.outfit || 'disco';
  // hair mass behind head
  ctx.beginPath();
  ctx.moveTo(-0.95, 0.35);
  ctx.bezierCurveTo(-1.35, 0.1, -1.3, -0.5, -1.05, -0.85);
  ctx.bezierCurveTo(-0.8, -1.45, 0.8, -1.45, 1.05, -0.85);
  ctx.bezierCurveTo(1.3, -0.5, 1.35, 0.1, 0.95, 0.35);
  ctx.closePath();
  inked(ctx, linear(ctx, 0, -1.4, 0, 0.4, [lighten(hair, 0.2), hair, darken(hair, 0.15)]), LW);
  for (const s of [-1, 1]) {
    for (const [y, len] of [[-0.3, 0.42], [0.0, 0.46], [0.25, 0.38]]) {
      ctx.beginPath();
      ctx.moveTo(s * 0.9, y - 0.1);
      ctx.quadraticCurveTo(s * (1.1 + len * 0.3), y - 0.05, s * (0.95 + len * 0.55), y + 0.18);
      ctx.quadraticCurveTo(s * 1.05, y + 0.08, s * 0.9, y + 0.12);
      inked(ctx, lighten(hair, 0.08), LW * 0.8);
    }
  }
  torsoPath(ctx, 1.05);
  if (outfit === 'tux') {
    inked(ctx, linear(ctx, 0, 1, 0, 2.6, ['#2E3150', '#1A1A2E']), LW);
    poly(ctx, [-0.36, 0.96, 0.36, 0.96, 0.1, 2.9, -0.1, 2.9]);
    inked(ctx, '#FFFFFF', LW);
    for (const s of [-1, 1]) { poly(ctx, [s * 0.36, 0.96, s * 0.95, 1.2, s * 0.2, 2.2]); inked(ctx, '#3A3E62', LW); }
    poly(ctx, [0, 1.12, -0.3, 0.98, -0.3, 1.28]);
    inked(ctx, '#1A1A2E', 0.03);
    poly(ctx, [0, 1.12, 0.3, 0.98, 0.3, 1.28]);
    inked(ctx, '#1A1A2E', 0.03);
  } else if (outfit === 'camo') {
    inked(ctx, '#6E7A3A', LW);
    ctx.save();
    torsoPath(ctx, 1.05);
    ctx.clip();
    const r = rng(5);
    for (let i = 0; i < 40; i++) {
      ellipse(ctx, (r() - 0.5) * 3.4, 0.9 + r() * 2, 0.2 + r() * 0.2, 0.1 + r() * 0.12, r() * 3);
      fill(ctx, ['#4A5A2A', '#8C8A4A', '#3A3020'][i % 3]);
    }
    ctx.restore();
    ctx.beginPath();
    ctx.moveTo(-0.3, 1.0);
    ctx.quadraticCurveTo(0, 1.8, 0.3, 1.0);
    stroke(ctx, '#C9CED8', 0.03);
    rr(ctx, -0.1, 1.72, 0.2, 0.28, 0.05);
    inked(ctx, '#D8DCE6', 0.03);
  } else if (outfit === 'leather') {
    inked(ctx, linear(ctx, 0, 1, 0, 2.6, ['#9A5A30', '#6A3A1C']), LW);
    poly(ctx, [-0.36, 0.96, 0.36, 0.96, 0.22, 2.9, -0.22, 2.9]);
    inked(ctx, '#F7C531', LW);
    for (const s of [-1, 1]) { poly(ctx, [s * 0.34, 0.96, s * 1.0, 1.15, s * 0.45, 2.1]); inked(ctx, '#8A4E28', LW); }
  } else {
    inked(ctx, '#F7C531', LW);
    ctx.save();
    torsoPath(ctx, 1.05);
    ctx.clip();
    const cols = ['#F07A1E', '#F7C531', '#F6E7C8', '#F7C531'];
    for (let i = -10; i < 10; i++) { ctx.fillStyle = cols[(i + 20) % 4]; ctx.fillRect(i * 0.18, 0.9, 0.18, 2.2); }
    ctx.restore();
    torsoPath(ctx, 1.05);
    stroke(ctx, C.ink, LW);
    poly(ctx, [-0.3, 0.96, 0.3, 0.96, 0, 1.55]);
    inked(ctx, darken(skin, 0.06), LW);
    ctx.fillStyle = '#4A2A18';
    for (let i = 0; i < 7; i++) { circle(ctx, (i % 3 - 1) * 0.06, 1.18 + i * 0.04, 0.035); ctx.fill(); }
    for (const s of [-1, 1]) {
      poly(ctx, [s * 0.28, 0.92, s * 1.15, 1.3, s * 0.62, 1.52, s * 0.12, 1.45]);
      inked(ctx, '#FFD23A', LW);
    }
  }
  if (outfit === 'western') {
    inked(ctx, '#C0763A', LW);
    ctx.beginPath();
    ctx.moveTo(-0.5, 0.98);
    ctx.quadraticCurveTo(0, 1.25, 0.5, 0.98);
    ctx.lineTo(0.12, 1.55);
    ctx.lineTo(0, 1.35);
    ctx.lineTo(-0.12, 1.55);
    ctx.closePath();
    inked(ctx, '#D8322B', LW);
    halftoneDots(ctx, -0.4, 1.0, 0.8, 0.4, '#FFFFFF');
  }
  neck(ctx, skin, 0.3);
  ears(ctx, skin);
  faceBase(ctx, skin, 1.0, 1.04, 0.14);
  for (const s of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(s * 0.9, -0.4);
    ctx.lineTo(s * 0.9, 0.42);
    ctx.quadraticCurveTo(s * 0.8, 0.46, s * 0.74, 0.36);
    ctx.lineTo(s * 0.74, -0.4);
    inked(ctx, darken(hair, 0.1), LW * 0.8);
  }
  eyes(ctx, skin, { iris: '#5A3218', wink: o.wink, y: 0.08, rx: 0.17, ry: 0.2 });
  brows(ctx, darken(hair, 0.2), -0.24, 0.07, 0.1, 0.34, 0.2, -0.02);
  nose(ctx, skin, 0.32, 0.11);
  mouth(ctx, 'smirk', 0.74, 0.16);
  // chevron mustache
  ctx.beginPath();
  ctx.moveTo(0, 0.42);
  ctx.bezierCurveTo(0.22, 0.38, 0.42, 0.46, 0.46, 0.68);
  ctx.bezierCurveTo(0.3, 0.6, 0.16, 0.6, 0, 0.62);
  ctx.bezierCurveTo(-0.16, 0.6, -0.3, 0.6, -0.46, 0.68);
  ctx.bezierCurveTo(-0.42, 0.46, -0.22, 0.38, 0, 0.42);
  inked(ctx, linear(ctx, 0, 0.4, 0, 0.7, ['#5A3220', '#3A2014']), LW * 0.8);
  // aviators
  for (const s of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(s * 0.08, -0.08);
    ctx.lineTo(s * 0.62, -0.1);
    ctx.bezierCurveTo(s * 0.66, 0.12, s * 0.58, 0.34, s * 0.38, 0.34);
    ctx.bezierCurveTo(s * 0.14, 0.34, s * 0.06, 0.12, s * 0.08, -0.08);
    ctx.fillStyle = linear(ctx, 0, -0.1, 0, 0.34, ['rgba(255,110,40,0.72)', 'rgba(255,150,60,0.55)']);
    ctx.fill();
    stroke(ctx, '#C99A2E', 0.04);
    ctx.beginPath();
    ctx.moveTo(s * 0.2, -0.02);
    ctx.lineTo(s * 0.34, 0.12);
    stroke(ctx, 'rgba(255,255,255,0.55)', 0.035);
  }
  capsule(ctx, -0.09, -0.06, 0.09, -0.06, 0.035, '#C99A2E');
  for (const s of [-1, 1]) capsule(ctx, s * 0.62, -0.08, s * 0.88, -0.1, 0.035, '#C99A2E');
  // front hair: feathered crown (or the costume hat)
  if (o.hat === 'cowboy') {
    ellipse(ctx, 0, -0.62, 1.55, 0.26, 0);
    inked(ctx, linear(ctx, 0, -0.85, 0, -0.4, ['#C58A4E', '#8A5528']), LW);
    ctx.beginPath();
    ctx.moveTo(-0.7, -0.66);
    ctx.bezierCurveTo(-0.8, -1.5, -0.3, -1.62, 0, -1.4);
    ctx.bezierCurveTo(0.3, -1.62, 0.8, -1.5, 0.7, -0.66);
    ctx.closePath();
    inked(ctx, linear(ctx, 0, -1.6, 0, -0.66, ['#D69A5C', '#A8693A']), LW);
    ctx.fillStyle = '#5A3220';
    ctx.fillRect(-0.71, -0.86, 1.42, 0.14);
    ctx.beginPath();
    ctx.moveTo(-0.3, -1.52);
    ctx.quadraticCurveTo(0, -1.25, 0.3, -1.52);
    stroke(ctx, darken('#A8693A', 0.2), 0.04);
  } else {
    ctx.beginPath();
    ctx.moveTo(-0.92, -0.3);
    ctx.bezierCurveTo(-1.0, -1.2, -0.3, -1.45, 0.1, -1.3);
    ctx.bezierCurveTo(0.7, -1.35, 1.05, -0.95, 0.92, -0.3);
    ctx.bezierCurveTo(0.7, -0.65, 0.3, -0.72, 0.05, -0.62);
    ctx.bezierCurveTo(-0.35, -0.72, -0.72, -0.62, -0.92, -0.3);
    inked(ctx, linear(ctx, 0, -1.4, 0, -0.4, [lighten(hair, 0.25), hair]), LW);
    ctx.strokeStyle = lighten(hair, 0.35);
    ctx.lineWidth = 0.035;
    ctx.beginPath();
    for (const s of [-1, 1]) for (let k = 0; k < 3; k++) {
      ctx.moveTo(s * 0.1, -1.18 + k * 0.1);
      ctx.quadraticCurveTo(s * 0.55, -1.2 + k * 0.12, s * 0.82, -0.62 + k * 0.08);
    }
    ctx.stroke();
    if (o.hat === 'headband') {
      ctx.beginPath();
      ctx.moveTo(-0.95, -0.42);
      ctx.bezierCurveTo(-0.6, -0.72, 0.6, -0.72, 0.95, -0.42);
      ctx.lineCap = 'round';
      stroke(ctx, C.ink, 0.24);
      stroke(ctx, '#D8322B', 0.17);
      capsule(ctx, 0.95, -0.42, 1.35, -0.1, 0.1, '#D8322B', C.ink, 0.03);
      capsule(ctx, 0.95, -0.42, 1.3, -0.5, 0.1, '#D8322B', C.ink, 0.03);
    } else if (o.hat === 'beret') {
      ellipse(ctx, 0.2, -1.08, 1.0, 0.38, -0.15);
      inked(ctx, '#2F5A3A', LW);
      circle(ctx, -0.35, -1.0, 0.13);
      inked(ctx, C.gold, 0.03);
    }
  }
}
function halftoneDots(ctx, x, y, w, h, col) {
  ctx.fillStyle = col;
  ctx.beginPath();
  for (let j = 0; j < 4; j++) for (let i = 0; i < 8; i++) {
    const px = x + (i + (j & 1) * 0.5) * (w / 8), py = y + j * (h / 4);
    ctx.moveTo(px + 0.03, py);
    ctx.arc(px, py, 0.03, 0, TAU);
  }
  ctx.fill();
}

/** Baron Von Static's face (unit space). mood: grin | laugh | angry | frantic | goodnight. m = mouth open 0..1. */
function baronFace(ctx, mood = 'grin', t = 0, m = 0.4) {
  const skin = SKIN.baron;
  const frantic = mood === 'frantic', angry = mood === 'angry', night = mood === 'goodnight';
  ears(ctx, skin, 0.05, true);
  faceBase(ctx, skin, 0.62, 1.12, angry ? 0.3 : 0.18);
  // under-eye plum shadows
  for (const s of [-1, 1]) { ellipse(ctx, s * 0.33, 0.28, 0.2, 0.08); fill(ctx, alpha('#7A5C8E', 0.45)); }
  // slick hair with widow's peak and a silver streak
  ctx.beginPath();
  ctx.moveTo(-0.9, -0.05);
  ctx.bezierCurveTo(-1.0, -0.9, -0.55, -1.18, 0, -1.16);
  ctx.bezierCurveTo(0.55, -1.18, 1.0, -0.9, 0.9, -0.05);
  ctx.bezierCurveTo(0.82, -0.42, 0.6, -0.58, 0.32, -0.62);
  ctx.lineTo(0, -0.34);
  ctx.lineTo(-0.32, -0.62);
  ctx.bezierCurveTo(-0.6, -0.58, -0.82, -0.42, -0.9, -0.05);
  inked(ctx, linear(ctx, 0, -1.2, 0, -0.3, ['#3E3458', '#1E1830']), LW);
  ctx.beginPath();
  ctx.moveTo(0.22, -1.12);
  ctx.bezierCurveTo(0.5, -1.0, 0.62, -0.8, 0.6, -0.58);
  ctx.lineTo(0.46, -0.6);
  ctx.bezierCurveTo(0.45, -0.8, 0.35, -0.98, 0.12, -1.1);
  fill(ctx, '#D8D4E8');
  if (frantic) {
    for (const [x, y, a] of [[-0.5, -1.1, -0.6], [0.1, -1.2, 0.2], [0.6, -1.05, 0.7]]) {
      capsule(ctx, x, y, x + Math.sin(a) * 0.3, y - Math.cos(a) * 0.3, 0.08, '#2A2240', C.ink, 0.02);
    }
  }
  // brows
  const bt = angry ? 0.16 : night ? -0.12 : frantic ? -0.1 : 0.08;
  for (const s of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(s * 0.12, -0.22 + bt);
    ctx.quadraticCurveTo(s * 0.35, -0.38 - (night ? -0.06 : 0.08), s * 0.62, -0.34 - bt * 0.6);
    ctx.lineCap = 'round';
    stroke(ctx, '#1E1830', 0.13);
  }
  // eyes
  const shake = frantic ? Math.sin(t * 60) * 0.02 : 0;
  if (night) {
    for (const s of [-1, 1]) {
      ellipse(ctx, s * 0.33, 0.06, 0.2, 0.22);
      inked(ctx, '#FFFDF6', 0.04);
      circle(ctx, s * 0.33, 0.1, 0.16);
      fill(ctx, '#3A2A5A');
      circle(ctx, s * 0.33 + 0.06, 0.03, 0.06);
      fill(ctx, '#FFFFFF');
      circle(ctx, s * 0.33 - 0.06, 0.15, 0.03);
      fill(ctx, '#FFFFFF');
      ctx.beginPath();
      ctx.moveTo(s * 0.4, 0.26);
      ctx.quadraticCurveTo(s * 0.48, 0.5, s * 0.38, 0.6);
      ctx.quadraticCurveTo(s * 0.3, 0.5, s * 0.4, 0.26);
      fill(ctx, alpha('#8FE3FF', 0.9));
    }
  } else {
    const laughSquint = mood === 'laugh' ? 0.35 + m * 0.3 : 0;
    for (const s of [-1, 1]) {
      const big = frantic ? (s < 0 ? 1.25 : 0.95) : 1;
      const ex = s * 0.33 + shake, ey = 0.07;
      ellipse(ctx, ex, ey, 0.17 * big, (angry ? 0.13 : 0.19) * big);
      inked(ctx, angry ? '#FFF1D0' : '#FFFDF6', 0.04);
      circle(ctx, ex + 0.02, ey + 0.02, (frantic ? 0.04 : 0.09) * big);
      fill(ctx, angry ? '#E0203A' : '#C0284A');
      circle(ctx, ex + 0.02, ey + 0.02, (frantic ? 0.02 : 0.045) * big);
      fill(ctx, '#1E1428');
      if (laughSquint) {
        ctx.save();
        ellipse(ctx, ex, ey, 0.18, 0.2);
        ctx.clip();
        ellipse(ctx, ex, ey + 0.3, 0.3, laughSquint);
        fill(ctx, skin);
        ctx.restore();
      }
      if (angry) {
        ctx.save();
        ellipse(ctx, ex, ey, 0.18, 0.14);
        ctx.clip();
        poly(ctx, [ex - s * 0.2, ey - 0.2, ex + s * 0.2, ey - 0.2, ex + s * 0.2, ey + 0.03]);
        fill(ctx, skin);
        ctx.restore();
      }
    }
  }
  // monocle on his left eye (viewer right)
  const mx = 0.33 + shake, my = 0.07;
  if (frantic) {
    const sw = Math.sin(t * 7) * 0.4;
    ctx.beginPath();
    ctx.moveTo(0.6, 0.2);
    ctx.quadraticCurveTo(0.7, 0.7, 0.55 + sw * 0.3, 1.0);
    stroke(ctx, C.brass, 0.025);
    circle(ctx, 0.55 + sw * 0.3, 1.1, 0.14);
    stroke(ctx, C.ink, 0.07);
    stroke(ctx, C.brass, 0.04);
  } else {
    circle(ctx, mx, my, 0.26);
    ctx.fillStyle = 'rgba(200,240,255,0.18)';
    ctx.fill();
    stroke(ctx, C.ink, 0.085);
    stroke(ctx, C.brass, 0.05);
    ctx.beginPath();
    ctx.arc(mx, my, 0.18, -2.4, -1.6);
    stroke(ctx, 'rgba(255,255,255,0.7)', 0.03);
    ctx.beginPath();
    ctx.moveTo(mx + 0.2, my + 0.18);
    ctx.quadraticCurveTo(0.75, 0.8, 0.55, 1.25);
    stroke(ctx, C.brass, 0.022);
  }
  // long nose
  ctx.beginPath();
  ctx.moveTo(-0.05, 0.02);
  ctx.quadraticCurveTo(0.02, 0.3, 0.12, 0.42);
  ctx.quadraticCurveTo(0.02, 0.48, -0.08, 0.42);
  inked(ctx, darken(skin, 0.1), 0.04);
  // mouth
  const my0 = 0.62;
  if (night) {
    ctx.beginPath();
    ctx.moveTo(-0.2, my0);
    ctx.bezierCurveTo(-0.1, my0 + 0.06, 0.1, my0 + 0.06, 0.2, my0);
    stroke(ctx, C.ink, 0.05);
    poly(ctx, [-0.12, my0 + 0.03, -0.06, my0 + 0.035, -0.09, my0 + 0.12]);
    inked(ctx, '#FFFFFF', 0.02);
    poly(ctx, [0.12, my0 + 0.03, 0.06, my0 + 0.035, 0.09, my0 + 0.12]);
    inked(ctx, '#FFFFFF', 0.02);
  } else if (frantic) {
    ctx.beginPath();
    ctx.moveTo(-0.32, my0);
    for (let i = 1; i <= 8; i++) ctx.lineTo(-0.32 + i * 0.08, my0 + (i & 1 ? 0.08 : -0.02) + Math.sin(t * 30 + i) * 0.02);
    ctx.lineTo(0.3, my0 + 0.3);
    ctx.lineTo(-0.3, my0 + 0.3);
    ctx.closePath();
    inked(ctx, '#3B2340', 0.045);
    for (const s of [-1, 1]) { poly(ctx, [s * 0.2, my0 + 0.02, s * 0.12, my0 + 0.02, s * 0.16, my0 + 0.16]); inked(ctx, '#FFFFFF', 0.02); }
  } else {
    const open = angry ? 0.12 : 0.06 + m * 0.34, w = angry ? 0.36 : 0.42;
    ctx.beginPath();
    ctx.moveTo(-w, my0 - 0.06);
    ctx.quadraticCurveTo(0, my0 + 0.08, w, my0 - 0.06);
    ctx.quadraticCurveTo(w * 0.7, my0 + open + 0.08, 0, my0 + open + 0.1);
    ctx.quadraticCurveTo(-w * 0.7, my0 + open + 0.08, -w, my0 - 0.06);
    inked(ctx, '#3B2340', 0.05);
    ctx.save();
    ctx.clip();
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    ctx.moveTo(-w, my0 - 0.1);
    ctx.quadraticCurveTo(0, my0 + 0.12, w, my0 - 0.1);
    ctx.lineTo(w, my0 - 0.2);
    ctx.lineTo(-w, my0 - 0.2);
    ctx.fill();
    if (open > 0.15) { ellipse(ctx, 0, my0 + open + 0.08, w * 0.5, 0.1); fill(ctx, '#E0507A'); }
    if (angry) { ctx.fillStyle = '#FFFFFF'; ctx.fillRect(-w, my0 + 0.08, w * 2, 0.1); }
    ctx.restore();
    for (const s of [-1, 1]) {
      poly(ctx, [s * 0.24, my0 - 0.01, s * 0.12, my0 + 0.02, s * 0.19, my0 + 0.2]);
      inked(ctx, '#FFFFFF', 0.025);
    }
  }
  if (angry) {
    for (const s of [-1, 1]) {
      ctx.beginPath();
      ctx.moveTo(s * 0.66, -0.7);
      ctx.lineTo(s * 0.74, -0.62);
      ctx.moveTo(s * 0.8, -0.72);
      ctx.lineTo(s * 0.72, -0.64);
      stroke(ctx, C.red, 0.05);
    }
  }
  if (frantic) {
    for (const [x, y] of [[-0.95, -0.3], [0.98, -0.1], [-0.9, 0.4]]) {
      ctx.beginPath();
      const yy = y + fract(t * 2 + x) * 0.2;
      ctx.moveTo(x, yy - 0.12);
      ctx.quadraticCurveTo(x - 0.08, yy + 0.02, x, yy + 0.06);
      ctx.quadraticCurveTo(x + 0.08, yy + 0.02, x, yy - 0.12);
      inked(ctx, '#9FE6FF', 0.02);
    }
  }
}

/** Baron bust with cape collar, tux, jabot and medallion. */
function bustBaron(ctx, o) {
  for (const s of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(s * 0.35, 0.95);
    ctx.lineTo(s * 1.55, -1.25);
    ctx.quadraticCurveTo(s * 1.6, 0.2, s * 1.7, 1.2);
    ctx.closePath();
    inked(ctx, linear(ctx, 0, -1.2, 0, 1.2, ['#C0283E', '#7A1428']), LW);
    ctx.beginPath();
    ctx.moveTo(s * 1.55, -1.25);
    ctx.quadraticCurveTo(s * 1.9, 0.2, s * 1.85, 1.3);
    ctx.lineTo(s * 1.7, 1.2);
    ctx.quadraticCurveTo(s * 1.6, 0.2, s * 1.55, -1.25);
    inked(ctx, '#1E1830', LW);
  }
  torsoPath(ctx, 1.05);
  inked(ctx, linear(ctx, 0, 1, 0, 2.6, ['#2E2E4E', '#1A1A2E']), LW);
  for (const s of [-1, 1]) { poly(ctx, [s * 0.3, 0.98, s * 1.0, 1.25, s * 0.28, 2.3]); inked(ctx, C.plum, LW); }
  poly(ctx, [-0.3, 0.98, 0.3, 0.98, 0.16, 2.3, -0.16, 2.3]);
  inked(ctx, '#FFFFFF', LW);
  for (let i = 0; i < 4; i++) {
    const y = 1.12 + i * 0.2;
    ctx.beginPath();
    ctx.ellipse(0, y, 0.3 - i * 0.03, 0.1, 0, 0, Math.PI);
    inked(ctx, '#FFFFFF', 0.03);
  }
  ctx.beginPath();
  ctx.moveTo(-0.45, 1.05);
  ctx.quadraticCurveTo(0, 1.8, 0.45, 1.05);
  stroke(ctx, C.brass, 0.035);
  circle(ctx, 0, 1.9, 0.22);
  inked(ctx, radial(ctx, -0.06, 1.84, 0.02, 0.24, ['#FFF0A8', '#E8B030', '#A87010']), 0.03);
  uText(ctx, '13', 0, 1.91, 0.2, FONT.round, '#7A4A10');
  neck(ctx, SKIN.baron, 0.24);
  baronFace(ctx, o.mood || 'grin', o.t || 0, o.m ?? 0.35);
}

/** "Stormy Stu" the weatherman: pompadour, giant grin, loud checked sport coat. */
function bustStu(ctx) {
  const skin = SKIN.stu, hair = '#4A2A1A';
  torsoPath(ctx, 1.05);
  inked(ctx, '#D9602B', LW);
  ctx.save();
  torsoPath(ctx, 1.05);
  ctx.clip();
  for (let j = 0; j < 12; j++) for (let i = -10; i < 10; i++) {
    if ((i + j) & 1) continue;
    ctx.fillStyle = 'rgba(90,40,20,0.55)';
    ctx.fillRect(i * 0.22, 0.9 + j * 0.22, 0.22, 0.22);
  }
  ctx.strokeStyle = 'rgba(246,231,200,0.7)';
  ctx.lineWidth = 0.025;
  ctx.beginPath();
  for (let i = -10; i < 10; i++) { ctx.moveTo(i * 0.44 + 0.11, 0.9); ctx.lineTo(i * 0.44 + 0.11, 3); }
  for (let j = 0; j < 6; j++) { ctx.moveTo(-2, 1.01 + j * 0.44); ctx.lineTo(2, 1.01 + j * 0.44); }
  ctx.stroke();
  ctx.restore();
  poly(ctx, [-0.34, 0.97, 0.34, 0.97, 0.16, 2.9, -0.16, 2.9]);
  inked(ctx, C.cream, LW);
  poly(ctx, [-0.1, 1.05, 0.1, 1.05, 0.2, 2.2, 0, 2.4, -0.2, 2.2]);
  inked(ctx, C.mustard, LW);
  for (const s of [-1, 1]) { poly(ctx, [s * 0.34, 0.97, s * 1.25, 1.3, s * 0.8, 1.6, s * 0.2, 2.4]); inked(ctx, '#C0501E', LW); }
  circle(ctx, 0.9, 1.75, 0.14);
  inked(ctx, '#FFD23A', 0.03);
  neck(ctx, skin, 0.3);
  ears(ctx, skin);
  faceBase(ctx, skin, 1.0, 1.02, 0.3);
  eyes(ctx, skin, { iris: '#3A6AA8', y: 0.02, rx: 0.17, ry: 0.21 });
  brows(ctx, hair, -0.33, -0.04, 0.09, 0.34, 0.2, 0.08);
  nose(ctx, skin, 0.3, 0.12);
  ctx.beginPath();
  ctx.moveTo(-0.5, 0.42);
  ctx.quadraticCurveTo(0, 0.56, 0.5, 0.42);
  ctx.quadraticCurveTo(0.42, 0.9, 0, 0.9);
  ctx.quadraticCurveTo(-0.42, 0.9, -0.5, 0.42);
  inked(ctx, '#7A2A3A', 0.05);
  ctx.save();
  ctx.clip();
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(-0.6, 0.38, 1.2, 0.2);
  ctx.fillRect(-0.6, 0.74, 1.2, 0.2);
  ctx.strokeStyle = '#D8D0E0';
  ctx.lineWidth = 0.02;
  ctx.beginPath();
  for (let x = -0.4; x <= 0.4; x += 0.1) { ctx.moveTo(x, 0.4); ctx.lineTo(x, 0.58); ctx.moveTo(x + 0.05, 0.74); ctx.lineTo(x + 0.05, 0.92); }
  ctx.stroke();
  ctx.restore();
  // pompadour
  ctx.beginPath();
  ctx.moveTo(-0.92, -0.2);
  ctx.bezierCurveTo(-1.05, -1.1, -0.5, -1.5, 0.1, -1.55);
  ctx.bezierCurveTo(0.9, -1.75, 1.35, -1.2, 0.95, -0.9);
  ctx.bezierCurveTo(1.05, -0.6, 0.95, -0.4, 0.92, -0.2);
  ctx.bezierCurveTo(0.7, -0.7, 0.2, -0.75, -0.1, -0.7);
  ctx.bezierCurveTo(-0.5, -0.66, -0.8, -0.5, -0.92, -0.2);
  inked(ctx, linear(ctx, 0, -1.7, 0, -0.3, [lighten(hair, 0.35), hair]), LW);
  ctx.beginPath();
  ctx.moveTo(-0.5, -1.2);
  ctx.bezierCurveTo(0, -1.5, 0.7, -1.55, 1.05, -1.12);
  stroke(ctx, 'rgba(255,255,255,0.45)', 0.05);
}

/** Draws a bust at (cx, cy) (face centre) with head radius s. who: hero id | 'baron' | 'stu'. */
function drawBust(ctx, who, cx, cy, s, o = {}) {
  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(s, s);
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  ({ skip: bustSkip, roxy: bustRoxy, penny: bustPenny, duke: bustDuke, baron: bustBaron, stu: bustStu })[who](ctx, o);
  ctx.restore();
}

// ---------------------------------------------------------------------------------------------------------
// Hootie the owl (kids' show host)
// ---------------------------------------------------------------------------------------------------------

/** Hootie at (cx, cy) = body centre, s = body half-height. o: { t, wave, blink } */
function drawHootie(ctx, cx, cy, s, o = {}) {
  const t = o.t || 0;
  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(s, s);
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  const brown = '#8A5A3C', dark = '#5E3A24', belly = '#E9CFA0';
  for (const sx of [-1, 1]) {
    ellipse(ctx, sx * 0.3, 1.02, 0.2, 0.09);
    inked(ctx, '#F0A032', LW);
  }
  // wings (right one may wave)
  const wave = o.wave ?? 0;
  for (const sx of [-1, 1]) {
    ctx.save();
    ctx.translate(sx * 0.72, 0.05);
    ctx.rotate(sx * (0.25 + (sx > 0 ? wave : 0)));
    ellipse(ctx, sx * 0.12, 0.3, 0.26, 0.55);
    inked(ctx, linear(ctx, 0, -0.2, 0, 0.9, [brown, dark]), LW);
    ctx.strokeStyle = alpha(darken(dark, 0.3), 0.6);
    ctx.lineWidth = 0.035;
    for (let k = 0; k < 3; k++) { ctx.beginPath(); ctx.arc(sx * 0.12, 0.45 + k * 0.16, 0.18, 0.4, 2.7); ctx.stroke(); }
    ctx.restore();
  }
  // ear tufts + body
  for (const sx of [-1, 1]) {
    poly(ctx, [sx * 0.34, -0.72, sx * 0.72, -1.22, sx * 0.72, -0.55]);
    inked(ctx, dark, LW);
  }
  ctx.beginPath();
  ctx.ellipse(0, 0.05, 0.8, 0.98, 0, 0, TAU);
  inked(ctx, radial(ctx, -0.2, -0.3, 0.1, 1.1, [lighten(brown, 0.15), brown, dark]), LW);
  ctx.save();
  ellipse(ctx, 0, 0.42, 0.52, 0.55);
  inked(ctx, belly, LW * 0.8);
  ctx.clip();
  ctx.strokeStyle = alpha('#B88A58', 0.8);
  ctx.lineWidth = 0.03;
  for (let j = 0; j < 5; j++) for (let i = -3; i <= 3; i++) {
    ctx.beginPath();
    ctx.arc(i * 0.16 + (j & 1) * 0.08, 0.05 + j * 0.16, 0.08, 0.2, Math.PI - 0.2);
    ctx.stroke();
  }
  ctx.restore();
  // facial disc + eyes
  ctx.beginPath();
  ctx.moveTo(0, -0.35);
  ctx.bezierCurveTo(-0.3, -0.75, -0.9, -0.6, -0.72, -0.18);
  ctx.bezierCurveTo(-0.6, 0.18, -0.2, 0.2, 0, 0.12);
  ctx.bezierCurveTo(0.2, 0.2, 0.6, 0.18, 0.72, -0.18);
  ctx.bezierCurveTo(0.9, -0.6, 0.3, -0.75, 0, -0.35);
  inked(ctx, '#D8B484', LW * 0.8);
  const blink = o.blink ?? fract(t / 3.1) > 0.94;
  for (const sx of [-1, 1]) {
    const ex = sx * 0.33, ey = -0.26;
    circle(ctx, ex, ey, 0.3);
    inked(ctx, '#F4B63A', LW);
    circle(ctx, ex, ey, 0.24);
    fill(ctx, '#FFFDF6');
    if (blink) {
      ctx.beginPath();
      ctx.arc(ex, ey - 0.05, 0.2, 0.3, Math.PI - 0.3);
      stroke(ctx, C.ink, 0.06);
    } else {
      const px = ex + Math.sin(t * 1.3) * 0.03;
      circle(ctx, px, ey + 0.02, 0.15);
      fill(ctx, '#1E1428');
      circle(ctx, px + 0.06, ey - 0.05, 0.05);
      fill(ctx, '#FFFFFF');
    }
  }
  poly(ctx, [-0.09, -0.06, 0.09, -0.06, 0, 0.14]);
  inked(ctx, '#F0901E', LW * 0.8);
  // red bow tie
  poly(ctx, [0, 0.3, -0.26, 0.18, -0.26, 0.44]);
  inked(ctx, C.red, LW * 0.8);
  poly(ctx, [0, 0.3, 0.26, 0.18, 0.26, 0.44]);
  inked(ctx, C.red, LW * 0.8);
  circle(ctx, 0, 0.31, 0.07);
  inked(ctx, darken(C.red, 0.2), LW * 0.6);
  for (const [x, y] of [[-0.18, 0.26], [0.18, 0.36], [-0.2, 0.38], [0.16, 0.24]]) { circle(ctx, x, y, 0.025); fill(ctx, '#FFFFFF'); }
  ctx.restore();
}

// ---------------------------------------------------------------------------------------------------------
// Pictograms (70s Olympic-sign style figures) and marker doodles
// ---------------------------------------------------------------------------------------------------------

/**
 * Stick-figure pictogram. (x, y) = hip, s = figure height. Angles in degrees from straight down
 * (+ = toward +x). p: { lean, head:[dx,dy], la:[upper, lower], ra, ll, rl }. Returns joint positions.
 */
function picto(ctx, x, y, s, p, col) {
  const u = s / 10, lw = u * 1.25;
  const lean = (p.lean || 0) * DEG;
  const nx = x + Math.sin(lean) * 3.3 * u, ny = y - Math.cos(lean) * 3.3 * u;
  const seg = (ax, ay, a, len) => [ax + Math.sin(a * DEG) * len * u, ay + Math.cos(a * DEG) * len * u];
  const limb = (ax, ay, a1, a2, l1, l2) => { const m = seg(ax, ay, a1, l1); return [m, seg(m[0], m[1], a2, l2)]; };
  const la = limb(nx, ny, ...(p.la || [-15, -10]), 1.9, 1.8), ra = limb(nx, ny, ...(p.ra || [15, 10]), 1.9, 1.8);
  const ll = limb(x, y, ...(p.ll || [-8, -4]), 2.3, 2.3), rl = limb(x, y, ...(p.rl || [8, 4]), 2.3, 2.3);
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.strokeStyle = col;
  ctx.lineWidth = lw;
  ctx.beginPath();
  ctx.moveTo(x, y); ctx.lineTo(nx, ny);
  for (const [a, b] of [la, ra]) { ctx.moveTo(nx, ny); ctx.lineTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
  for (const [a, b] of [ll, rl]) { ctx.moveTo(x, y); ctx.lineTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
  ctx.stroke();
  ctx.lineWidth = lw * 1.5;
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.lineTo(lerp(x, nx, 0.8), lerp(y, ny, 0.8));
  ctx.stroke();
  const hd = p.head || [0, 0];
  const hx = nx + Math.sin(lean) * 1.45 * u + hd[0] * u, hy = ny - Math.cos(lean) * 1.45 * u + hd[1] * u;
  circle(ctx, hx, hy, u * 1.05);
  fill(ctx, col);
  ctx.restore();
  return { head: [hx, hy], neck: [nx, ny], handL: la[1], handR: ra[1], elbowL: la[0], elbowR: ra[0], footL: ll[1], footR: rl[1], hip: [x, y], u };
}

/** Hand-drawn marker helpers: every stroke gets a deterministic wobble and a streaky second pass. */
function marker(ctx, r, col, lw) {
  const jit = lw * 0.35;
  const path = (pts, close) => {
    ctx.beginPath();
    for (let i = 0; i < pts.length; i += 2) {
      const x = pts[i] + (r() - 0.5) * jit, y = pts[i + 1] + (r() - 0.5) * jit;
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    if (close) ctx.closePath();
  };
  const ink = (pts, close = false) => {
    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = col;
    ctx.lineWidth = lw;
    ctx.globalAlpha = 0.92;
    path(pts, close);
    ctx.stroke();
    ctx.globalAlpha = 0.35;
    ctx.lineWidth = lw * 0.55;
    path(pts, close);
    ctx.stroke();
    ctx.restore();
  };
  const ring = (cx, cy, rx, ry = rx, n = 26) => {
    const pts = [];
    const a0 = r() * TAU;
    for (let i = 0; i <= n + 2; i++) { const a = a0 + (i / n) * TAU; pts.push(cx + Math.cos(a) * rx * (1 + (r() - 0.5) * 0.06), cy + Math.sin(a) * ry * (1 + (r() - 0.5) * 0.06)); }
    return pts;
  };
  const fillIn = (pts, style) => {
    ctx.save();
    ctx.globalAlpha = 0.55;
    ctx.fillStyle = style;
    path(pts, true);
    ctx.fill();
    ctx.restore();
  };
  return { ink, ring, fillIn };
}

// ---------------------------------------------------------------------------------------------------------
// Products and icons
// ---------------------------------------------------------------------------------------------------------

/** Sponsor product illustrations centred at (x, y), height s. */
const PRODUCTS = {
  replay_ade(ctx, x, y, s) {
    const w = s * 0.42, ol = s * 0.02;
    rr(ctx, x - w * 0.24, y - s * 0.5, w * 0.48, s * 0.12, s * 0.02);
    inked(ctx, C.blue, ol);
    ctx.beginPath();
    ctx.moveTo(x - w * 0.2, y - s * 0.38);
    ctx.lineTo(x + w * 0.2, y - s * 0.38);
    ctx.quadraticCurveTo(x + w * 0.5, y - s * 0.3, x + w * 0.5, y - s * 0.12);
    ctx.lineTo(x + w * 0.5, y + s * 0.42);
    ctx.quadraticCurveTo(x + w * 0.5, y + s * 0.5, x + w * 0.4, y + s * 0.5);
    ctx.lineTo(x - w * 0.4, y + s * 0.5);
    ctx.quadraticCurveTo(x - w * 0.5, y + s * 0.5, x - w * 0.5, y + s * 0.42);
    ctx.lineTo(x - w * 0.5, y - s * 0.12);
    ctx.quadraticCurveTo(x - w * 0.5, y - s * 0.3, x - w * 0.2, y - s * 0.38);
    inked(ctx, linear(ctx, x - w / 2, 0, x + w / 2, 0, ['#FFE45A', '#F4C81E', '#E0A816']), ol);
    rr(ctx, x - w * 0.5, y - s * 0.02, w, s * 0.3, 0);
    inked(ctx, C.blue, ol);
    ctx.fillStyle = '#FFE45A';
    for (const k of [-1, 0.15]) poly(ctx, [x + k * w * 0.3, y + s * 0.13, x + (k + 0.45) * w * 0.3, y + s * 0.04, x + (k + 0.45) * w * 0.3, y + s * 0.22]), ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.45)';
    rr(ctx, x - w * 0.36, y - s * 0.28, w * 0.1, s * 0.62, w * 0.05);
    ctx.fill();
  },
  wobble_up(ctx, x, y, s, t = 0) {
    const w = s * 0.9, ol = s * 0.02, wob = Math.sin(t * 9) * 0.04;
    ellipse(ctx, x, y + s * 0.38, w * 0.62, s * 0.1);
    inked(ctx, '#F4F1E8', ol);
    ctx.save();
    ctx.translate(x, y + s * 0.35);
    ctx.transform(1, 0, wob, 1, 0, 0);
    ctx.scale(1 + wob, 1 - wob);
    ctx.beginPath();
    ctx.moveTo(-w * 0.5, 0);
    ctx.bezierCurveTo(-w * 0.52, -s * 0.5, -w * 0.3, -s * 0.72, 0, -s * 0.72);
    ctx.bezierCurveTo(w * 0.3, -s * 0.72, w * 0.52, -s * 0.5, w * 0.5, 0);
    ctx.closePath();
    inked(ctx, linear(ctx, 0, -s * 0.72, 0, 0, ['#7CF29A', '#1FB45A', '#0E7A3A']), ol);
    ctx.strokeStyle = 'rgba(10,80,40,0.45)';
    ctx.lineWidth = s * 0.015;
    for (const k of [-0.32, -0.12, 0.12, 0.32]) { ctx.beginPath(); ctx.moveTo(k * w, -s * 0.02); ctx.quadraticCurveTo(k * w * 0.95, -s * 0.4, k * w * 0.5, -s * 0.66); ctx.stroke(); }
    ellipse(ctx, 0, -s * 0.66, w * 0.14, s * 0.05);
    inked(ctx, '#0E7A3A', ol * 0.8);
    ctx.fillStyle = 'rgba(255,255,255,0.55)';
    ellipse(ctx, -w * 0.25, -s * 0.45, w * 0.06, s * 0.14, 0.3);
    ctx.fill();
    ctx.restore();
  },
  jump_cut(ctx, x, y, s) {
    const w = s * 0.62, ol = s * 0.02;
    ctx.beginPath();
    ctx.arc(x + w * 0.45, y + s * 0.05, s * 0.2, -1.2, 1.2);
    stroke(ctx, C.ink, s * 0.09);
    stroke(ctx, C.orange, s * 0.06);
    ctx.beginPath();
    ctx.moveTo(x - w * 0.3, y - s * 0.22);
    ctx.lineTo(x + w * 0.3, y - s * 0.22);
    ctx.bezierCurveTo(x + w * 0.62, y + s * 0.05, x + w * 0.55, y + s * 0.46, x + w * 0.36, y + s * 0.46);
    ctx.lineTo(x - w * 0.36, y + s * 0.46);
    ctx.bezierCurveTo(x - w * 0.55, y + s * 0.46, x - w * 0.62, y + s * 0.05, x - w * 0.3, y - s * 0.22);
    inked(ctx, 'rgba(210,235,255,0.55)', ol);
    ctx.save();
    ctx.clip();
    ctx.fillStyle = linear(ctx, 0, y, 0, y + s * 0.46, ['#8A4A22', '#5A2A12']);
    ctx.fillRect(x - w, y + s * 0.02, w * 2, s * 0.5);
    ctx.restore();
    rr(ctx, x - w * 0.36, y - s * 0.36, w * 0.72, s * 0.16, s * 0.05);
    inked(ctx, C.orange, ol);
    circle(ctx, x, y - s * 0.4, s * 0.05);
    inked(ctx, C.ink, ol * 0.6);
    poly(ctx, [x + s * 0.02, y + s * 0.08, x - s * 0.1, y + s * 0.26, x - s * 0.01, y + s * 0.26, x - s * 0.05, y + s * 0.42, x + s * 0.1, y + s * 0.2, x + s * 0.01, y + s * 0.2]);
    inked(ctx, '#FFD23A', ol * 0.6);
    ctx.strokeStyle = 'rgba(255,255,255,0.75)';
    ctx.lineWidth = s * 0.03;
    for (const k of [-0.12, 0.02, 0.16]) {
      ctx.beginPath();
      ctx.moveTo(x + k * s, y - s * 0.48);
      ctx.bezierCurveTo(x + (k - 0.06) * s, y - s * 0.56, x + (k + 0.06) * s, y - s * 0.62, x + k * s, y - s * 0.7);
      ctx.stroke();
    }
  },
  roller_boogie(ctx, x, y, s) {
    const ol = s * 0.02;
    ctx.beginPath();
    ctx.moveTo(x - s * 0.18, y - s * 0.46);
    ctx.lineTo(x + s * 0.12, y - s * 0.46);
    ctx.lineTo(x + s * 0.14, y - s * 0.05);
    ctx.quadraticCurveTo(x + s * 0.42, y - s * 0.02, x + s * 0.44, y + s * 0.14);
    ctx.lineTo(x + s * 0.44, y + s * 0.2);
    ctx.lineTo(x - s * 0.3, y + s * 0.2);
    ctx.lineTo(x - s * 0.3, y - s * 0.02);
    ctx.quadraticCurveTo(x - s * 0.22, y - s * 0.2, x - s * 0.18, y - s * 0.46);
    inked(ctx, linear(ctx, 0, y - s * 0.46, 0, y + s * 0.2, ['#FFFFFF', '#EDE4D0']), ol);
    ctx.fillStyle = C.red;
    ctx.fillRect(x - s * 0.2, y - s * 0.3, s * 0.34, s * 0.05);
    ctx.fillRect(x - s * 0.23, y - s * 0.2, s * 0.37, s * 0.05);
    rr(ctx, x - s * 0.34, y + s * 0.18, s * 0.82, s * 0.07, s * 0.03);
    inked(ctx, '#D8DCE6', ol);
    ellipse(ctx, x + s * 0.5, y + s * 0.2, s * 0.06, s * 0.05);
    inked(ctx, C.pink, ol);
    ['#E23B3B', '#F4E03A', '#52D24A', '#3A58E4'].forEach((c, i) => {
      circle(ctx, x - s * 0.24 + i * s * 0.22 - (i > 1 ? 0 : 0), y + s * 0.33, s * 0.09);
      inked(ctx, c, ol);
      circle(ctx, x - s * 0.24 + i * s * 0.22, y + s * 0.33, s * 0.03);
      fill(ctx, '#F4F1E8');
    });
  },
  double_vision(ctx, x, y, s) {
    const ol = s * 0.02;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(-0.35);
    ctx.beginPath();
    ctx.moveTo(-s * 0.16, -s * 0.46);
    ctx.lineTo(s * 0.16, -s * 0.46);
    ctx.lineTo(s * 0.12, s * 0.3);
    ctx.lineTo(-s * 0.12, s * 0.3);
    ctx.closePath();
    inked(ctx, '#F4F1E8', ol);
    ctx.save();
    ctx.clip();
    [C.red, '#F4F1E8', C.blue].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(-s * 0.2, -s * 0.34 + i * s * 0.18, s * 0.4, s * 0.1); });
    ctx.restore();
    ctx.beginPath();
    ctx.moveTo(-s * 0.16, -s * 0.46);
    ctx.lineTo(s * 0.16, -s * 0.46);
    stroke(ctx, C.ink, ol);
    rr(ctx, -s * 0.07, s * 0.3, s * 0.14, s * 0.1, s * 0.02);
    inked(ctx, C.red, ol);
    ctx.restore();
    ctx.save();
    ctx.translate(x + s * 0.2, y + s * 0.05);
    ctx.rotate(0.5);
    rr(ctx, -s * 0.035, -s * 0.46, s * 0.07, s * 0.62, s * 0.03);
    inked(ctx, C.cyan, ol);
    rr(ctx, -s * 0.05, -s * 0.52, s * 0.1, s * 0.16, s * 0.02);
    inked(ctx, '#FFFFFF', ol * 0.8);
    ctx.fillStyle = C.magenta;
    for (let i = 0; i < 4; i++) ctx.fillRect(-s * 0.04 + i * s * 0.02, -s * 0.52, s * 0.012, s * 0.14);
    ctx.restore();
  },
};

function sunIcon(ctx, x, y, r, face = true, rot = 0) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot);
  starPath(ctx, 0, 0, r, r * 0.72, 12, 0);
  inked(ctx, '#FFB020', r * 0.08);
  circle(ctx, 0, 0, r * 0.62);
  inked(ctx, radial(ctx, -r * 0.2, -r * 0.2, 0, r * 0.7, ['#FFF3A0', '#FFD23A', '#F4B020']), r * 0.07);
  ctx.restore();
  if (face) {
    for (const s of [-1, 1]) { circle(ctx, x + s * r * 0.2, y - r * 0.08, r * 0.07); fill(ctx, C.ink); }
    ctx.beginPath();
    ctx.arc(x, y + r * 0.02, r * 0.26, 0.4, Math.PI - 0.4);
    stroke(ctx, C.ink, r * 0.07);
  }
}
function boltPath(ctx, x, y, s) {
  poly(ctx, [x + s * 0.1, y - s * 0.5, x - s * 0.3, y + s * 0.06, x - s * 0.02, y + s * 0.06, x - s * 0.14, y + s * 0.5, x + s * 0.3, y - s * 0.1, x + s * 0.02, y - s * 0.1, x + s * 0.16, y - s * 0.5]);
}
function towerIcon(ctx, x, y, h, col = C.red) {
  const w = h * 0.36;
  ctx.save();
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  ctx.strokeStyle = col;
  ctx.lineWidth = Math.max(1.5, h * 0.06);
  ctx.beginPath();
  ctx.moveTo(x - w / 2, y);
  ctx.lineTo(x, y - h);
  ctx.lineTo(x + w / 2, y);
  for (let k = 1; k < 5; k++) {
    const yy = y - (h * k) / 5, hw = (w / 2) * (1 - k / 5);
    ctx.moveTo(x - hw, yy);
    ctx.lineTo(x + hw, yy);
    if (k < 4) { ctx.lineTo(x - (w / 2) * (1 - (k + 1) / 5), y - (h * (k + 1)) / 5); }
  }
  ctx.stroke();
  for (const rr0 of [0.18, 0.3]) {
    ctx.beginPath();
    ctx.arc(x, y - h, h * rr0, -2.4, -0.74);
    ctx.stroke();
  }
  circle(ctx, x, y - h, h * 0.06);
  fill(ctx, col);
  ctx.restore();
}

// ---------------------------------------------------------------------------------------------------------
// Broadcast sources (4:3 TV cards)
// ---------------------------------------------------------------------------------------------------------

/** Green on-screen channel number, top-right. */
function osd(ctx, w, h, txt, px = h * 0.17) {
  ctx.save();
  setFont(ctx, px, FONT.osd);
  ctx.textAlign = 'right';
  ctx.textBaseline = 'top';
  const x = w * 0.955, y = h * 0.035;
  ctx.fillStyle = 'rgba(8,24,12,0.7)';
  ctx.fillText(txt, x + px * 0.06, y + px * 0.06);
  ctx.shadowColor = 'rgba(92,255,110,0.85)';
  ctx.shadowBlur = px * 0.25;
  ctx.fillStyle = C.osd;
  ctx.fillText(txt, x, y);
  ctx.shadowBlur = 0;
  ctx.fillStyle = 'rgba(220,255,225,0.55)';
  ctx.fillText(txt, x, y - px * 0.02);
  ctx.restore();
}

/** Streaky TV snow frame k (256x192, generated with ImageData, cached). */
function snowFrame(k) {
  return layer(`snow:${k}`, 256, 192, (g, w, h) => {
    const img = g.createImageData(w, h), d = img.data, r = rng(k * 7919 + 3);
    for (let y = 0; y < h; y++) {
      const gain = 0.7 + r() * 0.5 + (r() < 0.03 ? 0.6 : 0);
      for (let x = 0; x < w; x++) {
        const v = Math.min(255, (r() * r() * 1.3 + r() * 0.45) * 255 * gain);
        const i = (y * w + x) * 4;
        d[i] = v * 0.94 + 10; d[i + 1] = v * 0.96 + 8; d[i + 2] = Math.min(255, v + 22); d[i + 3] = 255;
      }
    }
    g.putImageData(img, 0, 0);
  });
}
function drawSnow(ctx, w, h, k) {
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(snowFrame(k % 6), 0, 0, w, h);
  ctx.restore();
  vignette(ctx, w, h, 0.35, '20,14,36', 0.5);
}

function drawBars(ctx, w, h, o = {}) {
  const top = Math.round(h * 0.66), mid = Math.round(h * 0.08), bw = w / 7;
  BARS.forEach((c, i) => {
    ctx.fillStyle = linear(ctx, 0, 0, 0, top, [lighten(c, 0.12), c, c, darken(c, 0.08)]);
    ctx.fillRect(Math.floor(i * bw), 0, Math.ceil(bw) + 1, top);
  });
  const dark = '#241C38';
  [BARS[6], dark, BARS[4], dark, BARS[2], dark, BARS[0]].forEach((c, i) => {
    ctx.fillStyle = c;
    ctx.fillRect(Math.floor(i * bw), top, Math.ceil(bw) + 1, mid);
  });
  const y2 = top + mid, segs = [['#1F3F7A', 1.25], ['#F4F1E8', 1.25], ['#4E2C80', 1.25], [dark, 1.25], ['#1A1428', 1 / 3], [dark, 1 / 3], ['#3A3252', 1 / 3], [dark, 1]];
  let x = 0;
  for (const [c, u] of segs) { ctx.fillStyle = c; ctx.fillRect(Math.floor(x), y2, Math.ceil(u * bw) + 1, h - y2); x += u * bw; }
  // painted-card touches: soft seams, gloss, pillow vignette
  ctx.fillStyle = 'rgba(30,20,50,0.12)';
  for (let i = 1; i < 7; i++) ctx.fillRect(Math.round(i * bw) - 1, 0, 2, top);
  ctx.fillStyle = linear(ctx, 0, 0, 0, top * 0.35, ['rgba(255,255,255,0.22)', 'rgba(255,255,255,0)']);
  ctx.fillRect(0, 0, w, top * 0.35);
  ctx.fillStyle = linear(ctx, 0, top - h * 0.05, 0, top, ['rgba(30,20,50,0)', 'rgba(30,20,50,0.18)']);
  ctx.fillRect(0, top - h * 0.05, w, h * 0.05);
  if (!o.plain) badge13(ctx, w - bw * 0.62, y2 + (h - y2) / 2, (h - y2) * 0.3, { ol: 1.5 });
  vignette(ctx, w, h, 0.28, '28,16,46', 0.55);
}

card('color_bars', { w: 512, h: 384, opts: 'plain: no station badge' }, (ctx, w, h, t, o) => drawBars(ctx, w, h, o));

/** The WZTV test card with Telly in the centre circle. */
function drawTestCard(ctx, w, h, o = {}) {
  const cx = w / 2, cy = h / 2, R = h * 0.445;
  ctx.fillStyle = '#8C8898';
  ctx.fillRect(0, 0, w, h);
  const cell = h / 12;
  ctx.fillStyle = '#6E6A7C';
  for (let j = 0; j < 12; j++) for (let i = 0; i < Math.ceil(w / cell); i++) if ((i + j) % 2 === 0) ctx.fillRect(i * cell + (w % cell) / 2, j * cell, cell, cell);
  ctx.strokeStyle = 'rgba(246,242,232,0.9)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  for (let x = (w % cell) / 2; x <= w; x += cell) { ctx.moveTo(Math.round(x) + 0.5, 0); ctx.lineTo(Math.round(x) + 0.5, h); }
  for (let y = 0; y <= h; y += cell) { ctx.moveTo(0, Math.round(y) + 0.5); ctx.lineTo(w, Math.round(y) + 0.5); }
  ctx.stroke();
  // castellated border
  const ch = h * 0.035;
  for (let i = 0; i < Math.ceil(w / cell); i++) {
    ctx.fillStyle = i & 1 ? '#F4F1E8' : '#2A2140';
    ctx.fillRect(i * cell + (w % cell) / 2, 0, cell, ch);
    ctx.fillStyle = i & 1 ? '#2A2140' : '#F4F1E8';
    ctx.fillRect(i * cell + (w % cell) / 2, h - ch, cell, ch);
  }
  for (let j = 0; j < 12; j++) {
    ctx.fillStyle = j & 1 ? '#F4F1E8' : '#2A2140';
    ctx.fillRect(0, j * cell, ch, cell);
    ctx.fillStyle = j & 1 ? '#2A2140' : '#F4F1E8';
    ctx.fillRect(w - ch, j * cell, ch, cell);
  }
  // resolution wedges left and right of the circle
  for (const s of [-1, 1]) {
    const wx = cx + s * (R + (w / 2 - R) * 0.48), wy = cy;
    ctx.strokeStyle = '#1E1830';
    ctx.lineWidth = 1.4;
    ctx.beginPath();
    for (let k = -5; k <= 5; k++) { ctx.moveTo(wx - s * cell * 1.1, wy + k * cell * 0.26); ctx.lineTo(wx + s * cell * 0.9, wy + k * cell * 0.04); }
    ctx.stroke();
    for (const k of [-1, 1]) { circle(ctx, wx, wy + k * cell * 3.4, cell * 0.72); inked(ctx, '#F4F1E8', 2, '#1E1830'); circle(ctx, wx, wy + k * cell * 3.4, cell * 0.3); fill(ctx, '#1E1830'); }
  }
  // centre circle
  ctx.save();
  circle(ctx, cx, cy, R);
  ctx.clip();
  ctx.fillStyle = linear(ctx, 0, cy - R, 0, cy + R, ['#9ED8FF', '#CDEBFF', '#FFE9C2']);
  ctx.fillRect(cx - R, cy - R, R * 2, R * 2);
  const barH = R * 0.36;
  BARS.forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(cx - R + (i * 2 * R) / 7, cy - R, (2 * R) / 7 + 1, barH); });
  ctx.fillStyle = 'rgba(30,20,50,0.2)';
  ctx.fillRect(cx - R, cy - R + barH - 3, R * 2, 3);
  const steps = 6, gy = cy + R * 0.62;
  for (let i = 0; i < steps; i++) { const v = Math.round(40 + (i * 200) / (steps - 1)); ctx.fillStyle = `rgb(${v},${v - 4},${v + 10})`; ctx.fillRect(cx - R + (i * 2 * R) / steps, gy, (2 * R) / steps + 1, R); }
  ctx.strokeStyle = 'rgba(40,30,70,0.25)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(cx - R, cy + R * 0.18); ctx.lineTo(cx + R, cy + R * 0.18);
  ctx.moveTo(cx, cy - R + barH); ctx.lineTo(cx, gy);
  ctx.stroke();
  ellipse(ctx, cx, cy + R * 0.56, R * 0.55, R * 0.08);
  fill(ctx, 'rgba(58,42,90,0.25)');
  const s = R * 0.78;
  drawTelly(ctx, cx, cy + R * 0.14, s, { expr: o.expr || 'idle', t: o.t || 0, look: [0, 0.1], cols: 26, dial: 0.1 });
  ctx.restore();
  circle(ctx, cx, cy, R);
  stroke(ctx, '#F4F1E8', 5);
  circle(ctx, cx, cy, R + 3);
  stroke(ctx, '#2A2140', 2);
  // station box
  const bw = R * 0.9, bh = R * 0.2, by = cy + R * 0.66;
  rr(ctx, cx - bw / 2, by, bw, bh, bh * 0.25);
  inked(ctx, '#1E1830', 2, '#F4F1E8');
  drawLogo(ctx, cx, by + bh / 2 + 1, bh * 0.52, { style: 'flat' });
}

card('test_card', { w: 512, h: 384, opts: 'variant: sleepy' }, (ctx, w, h, t, o) =>
  drawTestCard(ctx, w, h, { expr: o.variant === 'sleepy' ? 'sleepy' : 'idle', t }));

card('stand_by', { w: 512, h: 384, opts: 'variant: awake (default sleepy Telly)' }, (ctx, w, h, t, o) => {
  drawTestCard(ctx, w, h, { expr: o.variant === 'awake' ? 'idle' : 'sleepy', t });
  const bw = w * 0.84, bh = h * 0.2, bx = (w - bw) / 2, by = h * 0.7;
  ctx.save();
  ctx.shadowColor = 'rgba(20,10,40,0.6)';
  ctx.shadowBlur = 16;
  ctx.shadowOffsetY = 5;
  rr(ctx, bx, by, bw, bh, bh * 0.28);
  fill(ctx, linear(ctx, 0, by, 0, by + bh, ['#3A58E4', '#2F3FA8']));
  ctx.restore();
  rr(ctx, bx, by, bw, bh, bh * 0.28);
  stroke(ctx, '#F4F1E8', 4);
  rr(ctx, bx + 7, by + 7, bw - 14, bh - 14, bh * 0.2);
  stroke(ctx, alpha('#F4E03A', 0.9), 2);
  label(ctx, 'PLEASE STAND BY', w / 2, by + bh * 0.47, {
    fam: FONT.groovy, px: bh * 0.62, maxW: bw * 0.88, fill: vgrad(['#FFFBEA', '#FFE28A']),
    stroke: C.ink, lw: bh * 0.07, depth: 4, depthFill: '#1E2A6E', dx: 0.6, dy: 1,
  });
});

// Station ID: chrome "13" spinning over colour bars, WZTV logo plate.
function chromeGlyph(dark) {
  return layer(`chrome13:${dark ? 'side' : 'face'}`, 360, 260, (g, w, h) => {
    label(g, '13', w / 2, h / 2 + 8, {
      fam: FONT.round, px: 230, maxW: w * 0.92,
      fill: dark ? vgrad(['#8A96B4', '#3E4868', '#2A3050']) : vgrad(CHROME),
      stroke: dark ? '#1E2240' : '#1E2A5A', lw: 14,
    });
    if (!dark) {
      g.globalCompositeOperation = 'source-atop';
      g.fillStyle = linear(g, 0, 0, w, h, ['rgba(255,255,255,0)', 'rgba(255,255,255,0)', [0.46, 'rgba(255,255,255,0.55)'], [0.52, 'rgba(255,255,255,0)'], 'rgba(255,255,255,0)']);
      g.fillRect(0, 0, w, h);
    }
  });
}
function sparkle(ctx, x, y, r, a = 1) {
  ctx.save();
  ctx.globalAlpha = a;
  ctx.fillStyle = '#FFFFFF';
  ctx.shadowColor = '#BFE8FF';
  ctx.shadowBlur = r;
  starPath(ctx, x, y, r, r * 0.16, 4, 0);
  ctx.fill();
  ctx.restore();
}
card('station_id', { w: 512, h: 384, fps: 12 }, (ctx, w, h, t) => {
  ctx.drawImage(layer('station_id:bg', w, h, (g) => {
    drawBars(g, w, h, { plain: true });
    g.fillStyle = radial(g, w / 2, h * 0.42, 0, h * 0.55, ['rgba(22,18,52,0.9)', 'rgba(22,18,52,0.72)', 'rgba(22,18,52,0)']);
    g.fillRect(0, 0, w, h);
    const pw = w * 0.74, ph = h * 0.19, px = (w - pw) / 2, py = h * 0.77;
    g.save();
    g.shadowColor = 'rgba(10,6,24,0.7)';
    g.shadowBlur = 14;
    rr(g, px, py, pw, ph, ph / 2);
    fill(g, linear(g, 0, py, 0, py + ph, ['#2A2466', '#161236']));
    g.restore();
    rr(g, px, py, pw, ph, ph / 2);
    stroke(g, '#C9D3EA', 3);
    drawLogo(g, w / 2, py + ph / 2 + 1, ph * 0.56, { style: 'neon' });
  }), 0, 0);
  const th = (t * TAU) / 6.5, cs = Math.cos(th), sn = Math.sin(th);
  const face = chromeGlyph(false), side = chromeGlyph(true);
  const gw = face.width * 0.92, gh = face.height * 0.92, cx = w / 2, cy = h * 0.4 + Math.sin(t * 1.3) * 3;
  const depth = 26, steps = 12;
  ctx.save();
  ctx.translate(cx, cy);
  for (let k = steps; k >= 1; k--) {
    ctx.save();
    ctx.translate(sn * depth * (k / steps), 0);
    ctx.scale(Math.max(Math.abs(cs), 0.02) * Math.sign(cs || 1), 1);
    ctx.drawImage(side, -gw / 2, -gh / 2, gw, gh);
    ctx.restore();
  }
  ctx.scale(Math.max(Math.abs(cs), 0.02) * Math.sign(cs || 1), 1);
  if (cs < 0) ctx.filter = 'brightness(0.8)';
  ctx.drawImage(face, -gw / 2, -gh / 2, gw, gh);
  ctx.restore();
  const front = Math.max(0, cs);
  sparkle(ctx, cx - gw * 0.28 * cs, cy - gh * 0.3, 16 + 10 * Math.sin(t * 7), front);
  sparkle(ctx, cx + gw * 0.3 * cs, cy + gh * 0.18, 10 + 6 * Math.sin(t * 5 + 1), front * 0.8);
});

card('right_back', { w: 512, h: 384, fps: 12 }, (ctx, w, h, t) => {
  const ox = w * 0.3, oy = h * 0.62;
  ctx.fillStyle = radial(ctx, ox, oy, 0, w * 0.9, ['#FFB347', '#E3662B', '#B5472A']);
  ctx.fillRect(0, 0, w, h);
  rays(ctx, ox, oy, w * 1.2, 18, 'rgba(255,214,120,0.35)', t * 0.25);
  ctx.fillStyle = radial(ctx, ox, oy, w * 0.1, w * 0.8, ['rgba(255,240,200,0.35)', 'rgba(255,240,200,0)']);
  ctx.fillRect(0, 0, w, h);
  ellipse(ctx, ox, oy + w * 0.23, w * 0.2, w * 0.03);
  fill(ctx, 'rgba(90,30,20,0.35)');
  const bob = Math.abs(Math.sin(t * TAU * 1.1)) * -6;
  drawTelly(ctx, ox, oy + bob, w * 0.3, { expr: 'happy', t, wave: Math.sin(t * TAU * 1.4) * 0.55, earTwitch: Math.sin(t * 9) * 4, cols: 30 });
  const lines = ["WE'LL BE", 'RIGHT', 'BACK'];
  const sizes = [h * 0.12, h * 0.19, h * 0.21];
  let y = h * 0.2;
  lines.forEach((s, i) => {
    const b = Math.sin(t * TAU * 1.1 - i * 0.7) * 3;
    label(ctx, s, w * 0.71, y + b, {
      fam: FONT.groovy, px: sizes[i], maxW: w * 0.5, fill: vgrad(['#FFFDF0', '#FFE7A8']),
      stroke: C.ink, lw: sizes[i] * 0.1, depth: Math.round(sizes[i] * 0.09), depthFill: '#7A2A1A', dx: 0.5, dy: 1, rot: -0.05,
    });
    y += sizes[i] * 0.5 + (sizes[i + 1] || 0) * 0.62;
  });
  badge13(ctx, w * 0.9, h * 0.88, h * 0.06, { ol: 2 });
  vignette(ctx, w, h, 0.3, '70,20,20', 0.5);
});

// Hootie's Hullabaloo intro: owl host, rainbow and bouncing balloon letters.
function balloonText(ctx, str, cx, y, px, t, phase, maxW) {
  const cols = ['#FF4F5E', '#FFC23A', '#3FA9F5', '#52D24A', '#FF7AC8', '#FF8A2A', '#9B6BFF'];
  ctx.save();
  setFont(ctx, px, FONT.round);
  const chars = [...str], ws = chars.map((c) => ctx.measureText(c).width * 1.1);
  let total = ws.reduce((a, b) => a + b, 0);
  const sc = maxW && total > maxW ? maxW / total : 1;
  total *= sc;
  let x = cx - total / 2;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  ctx.lineJoin = 'round';
  chars.forEach((ch, i) => {
    const cw = ws[i] * sc, lx = x + cw / 2;
    x += cw;
    if (ch === ' ') return;
    const ph = t * 1.7 + phase + i * 0.42, hop = Math.abs(Math.sin(ph * Math.PI));
    const squash = hop < 0.18 ? 1 - (0.18 - hop) * 0.9 : 1;
    const col = cols[(i + Math.round(phase * 3)) % cols.length];
    ctx.save();
    ctx.translate(lx, y - hop * px * 0.22);
    ctx.scale(sc * (2 - squash), sc * squash);
    ctx.rotate(Math.sin(ph * 2) * 0.06);
    ctx.beginPath();
    ctx.moveTo(0, px * 0.05);
    ctx.bezierCurveTo(px * 0.08, px * 0.25, -px * 0.08, px * 0.35, px * 0.02, px * 0.5);
    stroke(ctx, 'rgba(60,40,80,0.6)', 1.5);
    ctx.strokeStyle = C.ink;
    ctx.lineWidth = px * 0.3;
    ctx.strokeText(ch, 0, 0);
    ctx.strokeStyle = col;
    ctx.lineWidth = px * 0.16;
    ctx.strokeText(ch, 0, 0);
    ctx.fillStyle = col;
    ctx.fillText(ch, 0, 0);
    ctx.fillStyle = linear(ctx, 0, -px * 0.8, 0, -px * 0.1, ['rgba(255,255,255,0.75)', 'rgba(255,255,255,0)']);
    ctx.fillText(ch, -px * 0.03, -px * 0.03);
    ellipse(ctx, -px * 0.12, -px * 0.55, px * 0.06, px * 0.1, 0.5);
    fill(ctx, 'rgba(255,255,255,0.85)');
    ctx.restore();
  });
  ctx.restore();
}
card('hullabaloo', { w: 512, h: 384, fps: 12 }, (ctx, w, h, t) => {
  ctx.drawImage(layer('hullabaloo:bg', w, h, (g) => {
    g.fillStyle = linear(g, 0, 0, 0, h, ['#6EC8FF', '#BDEBFF', '#E8FAFF']);
    g.fillRect(0, 0, w, h);
    const bands = ['#FF6B6B', '#FFA94D', '#FFE066', '#69DB7C', '#4DABF7', '#9775FA'];
    bands.forEach((c, i) => { g.beginPath(); g.arc(w / 2, h * 0.95, w * 0.58 - i * w * 0.04, Math.PI, 0); stroke(g, c, w * 0.04 + 1); });
    g.fillStyle = '#8FD06A';
    g.beginPath();
    g.moveTo(0, h * 0.8);
    g.bezierCurveTo(w * 0.25, h * 0.7, w * 0.4, h * 0.78, w * 0.55, h * 0.82);
    g.bezierCurveTo(w * 0.75, h * 0.72, w * 0.9, h * 0.74, w, h * 0.78);
    g.lineTo(w, h); g.lineTo(0, h);
    g.fill();
    g.fillStyle = '#5DB84E';
    g.beginPath();
    g.moveTo(0, h * 0.9);
    g.bezierCurveTo(w * 0.3, h * 0.82, w * 0.7, h * 0.95, w, h * 0.86);
    g.lineTo(w, h); g.lineTo(0, h);
    g.fill();
    const r = rng(9);
    for (let i = 0; i < 16; i++) flower(g, r() * w, h * (0.84 + r() * 0.14), 6 + r() * 3, ['#FFFFFF', '#FFD23A', '#FF8AC8'][i % 3], '#FF8A2A');
  }), 0, 0);
  for (let i = 0; i < 3; i++) {
    const x = fract(t * 0.03 + i * 0.37) * (w + 160) - 80;
    cloud(ctx, x, h * (0.12 + i * 0.1), 90 + i * 16, 50 + i * 8, '#FFFFFF', 'rgba(90,140,200,0.45)', 2);
  }
  const bob = Math.abs(Math.sin(t * TAU * 0.9)) * -8;
  ellipse(ctx, w / 2, h * 0.93, 64, 10);
  fill(ctx, 'rgba(40,90,40,0.3)');
  drawHootie(ctx, w / 2, h * 0.72 + bob, h * 0.19, { t, wave: Math.sin(t * TAU * 1.2) * 0.6 - 0.5 });
  balloonText(ctx, "HOOTIE'S", w / 2, h * 0.2, h * 0.13, t, 0, w * 0.6);
  balloonText(ctx, 'HULLABALOO', w / 2, h * 0.41, h * 0.17, t, 2.3, w * 0.94);
});

// The Baron on Channel 0.
function purpleStatic(ctx, w, h, k, a) {
  ctx.save();
  ctx.globalAlpha = a;
  ctx.globalCompositeOperation = 'screen';
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(snowFrame(k % 6), 0, 0, w, h);
  ctx.restore();
}
const BARON_BG = {
  laugh: ['#5A2A8A', '#2A1448', '#140A26'],
  angry: ['#A8203A', '#5A0E2A', '#240818'],
  frantic: ['#6A2A9A', '#2A0E48', '#10061E'],
  goodnight: ['#2A3A8A', '#18204E', '#0C1030'],
};
card('baron', { w: 512, h: 384, fps: 20, opts: 'variant: angry | frantic | goodnight (default laughing)' }, (ctx, w, h, t, o) => {
  const mood = ['angry', 'frantic', 'goodnight'].includes(o.variant) ? o.variant : 'laugh';
  const f = Math.round(t * 20);
  ctx.fillStyle = radial(ctx, w / 2, h * 0.45, 0, w * 0.75, BARON_BG[mood]);
  ctx.fillRect(0, 0, w, h);
  if (mood === 'goodnight') {
    const r = rng(4);
    for (let i = 0; i < 40; i++) {
      const tw = 0.5 + 0.5 * Math.sin(t * 3 + i);
      circle(ctx, r() * w, r() * h * 0.7, 0.8 + r() * 1.6);
      fill(ctx, `rgba(255,244,214,${0.3 + tw * 0.6})`);
    }
    circle(ctx, w * 0.84, h * 0.2, 30);
    fill(ctx, C.moon);
    circle(ctx, w * 0.87, h * 0.18, 26);
    fill(ctx, BARON_BG.goodnight[1]);
  } else {
    ctx.save();
    ctx.translate(w / 2, h / 2);
    ctx.rotate(t * (mood === 'frantic' ? 1.2 : 0.35));
    rays(ctx, 0, 0, w, 16, mood === 'angry' ? 'rgba(255,90,60,0.12)' : 'rgba(156,255,87,0.08)', 0);
    ctx.restore();
    purpleStatic(ctx, w, h, f, mood === 'frantic' ? 0.28 : 0.16);
  }
  let m = 0.35, tilt = 0, bob = 0, shake = 0;
  if (mood === 'laugh') {
    m = 0.45 + 0.55 * Math.abs(Math.sin(t * TAU * 1.7));
    tilt = Math.sin(t * TAU * 0.85) * 0.07;
    bob = -Math.abs(Math.sin(t * TAU * 1.7)) * 8;
  } else if (mood === 'angry') {
    shake = Math.sin(t * 70) * 2;
    m = 0.2;
  } else if (mood === 'frantic') {
    shake = Math.sin(t * 90) * 5;
    tilt = Math.sin(t * 13) * 0.1;
  } else {
    tilt = Math.sin(t * 1.5) * 0.05;
    bob = Math.sin(t * 2) * 3;
  }
  ctx.save();
  ctx.translate(w / 2 + shake, h * 0.54 + bob);
  ctx.rotate(tilt);
  ctx.scale(h * 0.34, h * 0.34);
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  baronFace(ctx, mood, t, m);
  ctx.restore();
  if (mood === 'frantic') {
    ctx.strokeStyle = 'rgba(240,250,255,0.85)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(w * 0.62, 0); ctx.lineTo(w * 0.58, h * 0.18); ctx.lineTo(w * 0.66, h * 0.3); ctx.lineTo(w * 0.61, h * 0.45);
    ctx.moveTo(w * 0.58, h * 0.18); ctx.lineTo(w * 0.48, h * 0.24);
    ctx.stroke();
  }
  const band = fract(t * 0.35) * (h + 80) - 40;
  ctx.fillStyle = linear(ctx, 0, band - 30, 0, band + 30, ['rgba(255,255,255,0)', 'rgba(255,255,255,0.07)', 'rgba(255,255,255,0)']);
  ctx.fillRect(0, band - 30, w, 60);
  osd(ctx, w, h, '0');
  vignette(ctx, w, h, 0.55, '12,6,24', 0.45);
});

// Sign-off film: WZTV logo over a waving "13" flag, then the test card (20 s loop, 15 fps).
function flagImage() {
  return layer('flag13', 300, 190, (g, w, h) => {
    g.fillStyle = linear(g, 0, 0, 0, h, ['#3A6AE8', C.blue, '#2448B0']);
    g.fillRect(0, 0, w, h);
    g.fillStyle = C.red;
    g.fillRect(0, 0, w, h * 0.1);
    g.fillRect(0, h * 0.9, w, h * 0.1);
    g.fillStyle = C.white;
    g.fillRect(0, h * 0.1, w, h * 0.035);
    g.fillRect(0, h * 0.865, w, h * 0.035);
    badge13(g, w * 0.55, h / 2, h * 0.3, { disc: C.white, ring: C.red, num: C.blue, ol: 3 });
  });
}
card('signoff_film', { w: 512, h: 384, fps: 15, opts: 'time = seconds since the film started (loops at 20 s)' }, (ctx, w, h, t) => {
  const lt = t % 20, f = Math.round(t * 15);
  const r = rng(f + 11);
  const weaveX = (r() - 0.5) * 2, weaveY = (r() - 0.5) * 2;
  ctx.fillStyle = '#1A1024';
  ctx.fillRect(0, 0, w, h);
  ctx.save();
  ctx.translate(weaveX, weaveY);
  if (lt < 16) {
    ctx.drawImage(layer('signoff:sky', w, h, (g) => {
      g.fillStyle = linear(g, 0, 0, 0, h, ['#1B1E4A', '#3A3F8A', '#8A7AB8', '#FFB36B']);
      g.fillRect(0, 0, w, h);
      const sr = rng(77);
      for (let i = 0; i < 60; i++) { circle(g, sr() * w, sr() * h * 0.5, 0.6 + sr() * 1.2); fill(g, `rgba(255,244,214,${0.4 + sr() * 0.5})`); }
      g.fillStyle = 'rgba(255,200,170,0.25)';
      for (let i = 0; i < 4; i++) { ellipse(g, sr() * w, h * (0.55 + sr() * 0.2), 80 + sr() * 60, 10 + sr() * 6); g.fill(); }
      g.fillStyle = '#2A1E40';
      g.beginPath();
      g.moveTo(0, h);
      for (let x = 0; x <= w; x += 16) g.lineTo(x, h * 0.9 - (Math.sin(x * 0.03) * 8 + (sr() * 14 | 0)));
      g.lineTo(w, h);
      g.fill();
    }), 0, 0);
    // pole
    const px = w * 0.2;
    rr(ctx, px - 5, h * 0.12, 10, h * 0.9, 5);
    fill(ctx, linear(ctx, px - 5, 0, px + 5, 0, ['#8A8EA0', '#F4F6FF', '#8A8EA0']));
    circle(ctx, px, h * 0.11, 11);
    fill(ctx, radial(ctx, px - 3, h * 0.1 - 3, 0, 12, ['#FFF6C8', C.gold, '#A87010']));
    // waving flag, sliced into strips
    const img = flagImage(), fw = w * 0.56, fh = fw * (img.height / img.width), fx = px + 4, fy = h * 0.16;
    const strips = 56, sw = fw / strips;
    for (let i = 0; i < strips; i++) {
      const u = i / strips, amp = 4 + u * 20;
      const ph = u * 7 - t * 4.2;
      const dy = Math.sin(ph) * amp, slope = Math.cos(ph);
      const sq = 1 - u * 0.06;
      ctx.drawImage(img, u * img.width, 0, img.width / strips + 1, img.height, fx + i * sw, fy + dy + (fh * (1 - sq)) / 2, sw + 1, fh * sq);
      ctx.fillStyle = slope > 0 ? `rgba(255,255,255,${slope * 0.16})` : `rgba(20,10,40,${-slope * 0.3})`;
      ctx.fillRect(fx + i * sw, fy + dy + (fh * (1 - sq)) / 2, sw + 1, fh * sq);
    }
    const la = clamp((lt - 1.2) / 1.5, 0, 1);
    if (la > 0) {
      ctx.save();
      ctx.globalAlpha = la;
      const ph = h * 0.15;
      rr(ctx, w * 0.5 - w * 0.33, h * 0.75, w * 0.66, ph, ph / 2);
      fill(ctx, 'rgba(20,14,48,0.8)');
      drawLogo(ctx, w / 2, h * 0.75 + ph / 2 + 1, ph * 0.55, { style: 'neon' });
      ctx.restore();
    }
  }
  if (lt > 15.2) {
    ctx.globalAlpha = clamp((lt - 15.2) / 0.8, 0, 1);
    ctx.drawImage(layer('signoff:test', w, h, (g) => drawTestCard(g, w, h, { expr: 'sleepy' })), 0, 0);
    ctx.globalAlpha = 1;
  }
  ctx.restore();
  // film artefacts
  grain(ctx, w, h, 0.22, f);
  ctx.fillStyle = `rgba(255,220,170,${0.05 + r() * 0.05})`;
  ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = 'rgba(30,20,20,0.7)';
  for (let i = 0; i < 5; i++) { circle(ctx, r() * w, r() * h, 0.6 + r() * 1.8); ctx.fill(); }
  if (r() < 0.35) { ctx.fillStyle = 'rgba(255,250,235,0.35)'; ctx.fillRect(r() * w, 0, 1.2, h); }
  vignette(ctx, w, h, 0.65, '20,10,10', 0.4);
  const fade = clamp(lt / 0.8, 0, 1);
  if (fade < 1) { ctx.fillStyle = `rgba(16,10,20,${1 - fade})`; ctx.fillRect(0, 0, w, h); }
});

// LIVE VIA SATELLITE super (transparent, full 4:3 frame so it overlays 1:1).
card('satellite_super', { w: 512, h: 384, alpha: true }, (ctx, w, h) => {
  const y = h * 0.74, bh = h * 0.14;
  ctx.save();
  ctx.shadowColor = 'rgba(10,8,30,0.55)';
  ctx.shadowBlur = 10;
  ctx.shadowOffsetY = 3;
  rr(ctx, w * 0.06, y, w * 0.2, bh, [bh * 0.3, 0, 0, bh * 0.3]);
  fill(ctx, linear(ctx, 0, y, 0, y + bh, ['#FF5A4A', '#D8242A']));
  rr(ctx, w * 0.26, y, w * 0.68, bh, [0, bh * 0.3, bh * 0.3, 0]);
  fill(ctx, linear(ctx, 0, y, 0, y + bh, ['rgba(40,70,190,0.92)', 'rgba(22,34,110,0.92)']));
  ctx.restore();
  ctx.fillStyle = 'rgba(255,255,255,0.18)';
  ctx.fillRect(w * 0.06, y + 3, w * 0.88, bh * 0.3);
  ctx.fillStyle = '#F4E03A';
  ctx.fillRect(w * 0.26, y + bh - 4, w * 0.68, 4);
  circle(ctx, w * 0.085, y + bh / 2, bh * 0.1);
  fill(ctx, '#FFFFFF');
  label(ctx, 'LIVE', w * 0.172, y + bh * 0.53, { fam: FONT.sign, px: bh * 0.55, maxW: w * 0.12, fill: '#FFFFFF', stroke: '#7A0E14', lw: 3 });
  const sx = w * 0.33, sy = y + bh / 2;
  ctx.save();
  ctx.translate(sx, sy);
  ctx.rotate(-0.5);
  rr(ctx, -bh * 0.1, -bh * 0.12, bh * 0.2, bh * 0.24, 2);
  inked(ctx, '#D8DCE6', 1.5);
  for (const s of [-1, 1]) { rr(ctx, s > 0 ? bh * 0.12 : -bh * 0.4, -bh * 0.07, bh * 0.28, bh * 0.14, 1); inked(ctx, '#5FA8FF', 1.5); }
  ctx.restore();
  ctx.strokeStyle = '#FFFFFF';
  ctx.lineWidth = 2;
  for (const k of [1, 2]) { ctx.beginPath(); ctx.arc(sx - bh * 0.18, sy + bh * 0.18, bh * 0.14 * k + 4, Math.PI * 0.55, Math.PI * 1.0); ctx.stroke(); }
  label(ctx, 'VIA SATELLITE', w * 0.63, y + bh * 0.53, { fam: FONT.sign, px: bh * 0.52, maxW: w * 0.52, fill: '#FFFFFF', stroke: '#141040', lw: 4, track: 1 });
  ctx.globalAlpha = 0.85;
  badge13(ctx, w * 0.9, h * 0.1, h * 0.055, { ol: 2 });
});

card('telly_face', { w: 384, h: 288, fps: 12, opts: `expr: ${TELLY_EXPRS.join(' | ')}; look: [x, y] gaze -1..1` }, (ctx, w, h, t, o) =>
  tellyScreen(ctx, 0, 0, w, h, TELLY_EXPRS.includes(o.expr) ? o.expr : 'idle', t, o.look || [0, 0], 64));

card('snow', { w: 512, h: 384, fps: 20, opts: 'channel: OSD number for snow channels (3, 6, 10)' }, (ctx, w, h, t, o) => {
  drawSnow(ctx, w, h, Math.round(t * 20));
  if (o.channel !== undefined) osd(ctx, w, h, String(o.channel));
});

// ---------------------------------------------------------------------------------------------------------
// Scenery kit (skylines, deserts, space, disco...) shared by show cards, promos, posters and worlds
// ---------------------------------------------------------------------------------------------------------

function starField(ctx, w, h, n, seed, maxY = 1, col = '255,244,214') {
  const r = rng(seed);
  for (let i = 0; i < n; i++) {
    const x = r() * w, y = r() * h * maxY, s = r();
    if (s > 0.94) sparkle(ctx, x, y, 3 + r() * 4, 0.9);
    else { circle(ctx, x, y, 0.5 + s * 1.3); fill(ctx, `rgba(${col},${0.35 + r() * 0.6})`); }
  }
}
/** City skyline silhouette band with lit windows. */
function skyline(ctx, w, base, hMin, hMax, col, seed, lit = 0.35, winCol = '#FFD27A') {
  const r = rng(seed);
  let x = -10;
  while (x < w + 10) {
    const bw = 22 + r() * 46, bh = hMin + r() * (hMax - hMin);
    ctx.fillStyle = col;
    ctx.fillRect(x, base - bh, bw, bh + 2);
    if (r() < 0.3) ctx.fillRect(x + bw * 0.4, base - bh - 12 - r() * 16, 3, 30);
    if (r() < 0.25) { ctx.beginPath(); ctx.moveTo(x, base - bh); ctx.lineTo(x + bw / 2, base - bh - bw * 0.35); ctx.lineTo(x + bw, base - bh); ctx.fill(); }
    ctx.fillStyle = winCol;
    for (let yy = base - bh + 6; yy < base - 6; yy += 9) for (let xx = x + 4; xx < x + bw - 5; xx += 8) if (r() < lit) ctx.fillRect(xx, yy, 4, 5);
    x += bw + r() * 4;
  }
}
function glowBlob(ctx, x, y, r, col, a = 0.8) {
  ctx.fillStyle = radial(ctx, x, y, 0, r, [alpha(col, a), alpha(col, a * 0.35), alpha(col, 0)]);
  ctx.fillRect(x - r, y - r, r * 2, r * 2);
}
/** 70s sunset sun with horizontal slices cut out of its lower half. */
function slicedSun(ctx, x, y, r, top, bottom, gapCol) {
  circle(ctx, x, y, r);
  fill(ctx, linear(ctx, 0, y - r, 0, y + r, [top, bottom]));
  ctx.fillStyle = gapCol;
  for (let i = 0; i < 5; i++) {
    const gy = y + r * (0.1 + i * 0.2), gh = 2 + i * 1.6;
    ctx.fillRect(x - r - 2, gy, r * 2 + 4, gh);
  }
}
function mesas(ctx, w, base, col, seed) {
  const r = rng(seed);
  ctx.fillStyle = col;
  ctx.beginPath();
  ctx.moveTo(0, base);
  let x = 0;
  while (x < w) {
    const mw = 50 + r() * 90, mh = 20 + r() * 50;
    if (r() < 0.55) {
      ctx.lineTo(x + mw * 0.15, base - mh);
      ctx.lineTo(x + mw * 0.85, base - mh);
      ctx.lineTo(x + mw, base);
    } else ctx.lineTo(x + mw, base - r() * 8);
    x += mw;
  }
  ctx.lineTo(w, base);
  ctx.lineTo(w, base + 400);
  ctx.lineTo(0, base + 400);
  ctx.fill();
}
function cactus(ctx, x, y, h, col, ink = null) {
  const w = h * 0.2;
  const parts = [[x, y, x, y - h, w], [x, y - h * 0.45, x - h * 0.28, y - h * 0.45, w * 0.8], [x - h * 0.28, y - h * 0.44, x - h * 0.28, y - h * 0.78, w * 0.8],
    [x, y - h * 0.6, x + h * 0.26, y - h * 0.6, w * 0.8], [x + h * 0.26, y - h * 0.59, x + h * 0.26, y - h * 0.88, w * 0.8]];
  if (ink) for (const p of parts) capsule(ctx, p[0], p[1], p[2], p[3], p[4] + 4, ink);
  for (const p of parts) capsule(ctx, p[0], p[1], p[2], p[3], p[4], col);
  if (ink) {
    ctx.strokeStyle = alpha('#0E3A1E', 0.4);
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.moveTo(x, y - 2);
    ctx.lineTo(x, y - h + w * 0.4);
    ctx.stroke();
  }
}
function palm(ctx, x, y, h, trunk, leaf) {
  ctx.beginPath();
  ctx.moveTo(x - h * 0.04, y);
  ctx.quadraticCurveTo(x + h * 0.1, y - h * 0.5, x + h * 0.22, y - h);
  ctx.lineTo(x + h * 0.27, y - h);
  ctx.quadraticCurveTo(x + h * 0.16, y - h * 0.5, x + h * 0.05, y);
  fill(ctx, trunk);
  const tx = x + h * 0.245, ty = y - h;
  for (let i = 0; i < 7; i++) {
    const a = -Math.PI + (i / 6) * Math.PI + (i > 3 ? 0.2 : -0.2), len = h * (0.45 + (i % 2) * 0.1);
    const ex = tx + Math.cos(a) * len, ey = ty + Math.sin(a) * len * 0.5 + len * 0.3;
    ctx.beginPath();
    ctx.moveTo(tx, ty);
    ctx.quadraticCurveTo((tx + ex) / 2 + Math.sin(a) * 10, ty - len * 0.3, ex, ey);
    ctx.quadraticCurveTo((tx + ex) / 2, ty - len * 0.05, tx, ty);
    fill(ctx, leaf);
  }
  for (const [dx, dy] of [[-4, 4], [4, 5], [0, 8]]) { circle(ctx, tx + dx, ty + dy, h * 0.035); fill(ctx, '#6A3E22'); }
}
function ringedPlanet(ctx, x, y, r, c1, c2, ring, tilt = -0.35) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(tilt);
  ctx.beginPath();
  ctx.ellipse(0, 0, r * 2, r * 0.5, 0, Math.PI, TAU);
  stroke(ctx, ring, r * 0.18);
  ctx.restore();
  circle(ctx, x, y, r);
  fill(ctx, linear(ctx, x - r, y - r, x + r, y + r, [lighten(c1, 0.25), c1, c2]));
  ctx.save();
  circle(ctx, x, y, r);
  ctx.clip();
  ctx.translate(x, y);
  ctx.rotate(tilt);
  for (let i = -3; i <= 3; i++) { ctx.fillStyle = alpha(i & 1 ? c2 : lighten(c1, 0.3), 0.35); ctx.fillRect(-r, i * r * 0.28 - r * 0.07, r * 2, r * 0.14); }
  ctx.rotate(-tilt);
  ctx.fillStyle = radial(ctx, r * 0.4, r * 0.4, r * 0.2, r * 1.3, ['rgba(20,10,40,0)', 'rgba(20,10,40,0.55)']);
  ctx.fillRect(-r, -r, r * 2, r * 2);
  ctx.restore();
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(tilt);
  ctx.beginPath();
  ctx.ellipse(0, 0, r * 2, r * 0.5, 0, 0, Math.PI);
  stroke(ctx, ring, r * 0.18);
  ctx.beginPath();
  ctx.ellipse(0, 0, r * 1.75, r * 0.42, 0, 0, Math.PI);
  stroke(ctx, alpha('#FFFFFF', 0.4), r * 0.04);
  ctx.restore();
}
function rocket(ctx, x, y, s, rot, t = 0) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot);
  const fl = 0.8 + Math.sin(t * 30) * 0.15;
  ctx.beginPath();
  ctx.moveTo(-s * 0.12, s * 0.45);
  ctx.quadraticCurveTo(0, s * (0.45 + 0.6 * fl), s * 0.12, s * 0.45);
  fill(ctx, linear(ctx, 0, s * 0.45, 0, s * 1.1, ['#FFF3A0', '#FF8A2A', 'rgba(255,60,40,0)']));
  for (const sd of [-1, 1]) { poly(ctx, [sd * s * 0.14, s * 0.1, sd * s * 0.34, s * 0.5, sd * s * 0.12, s * 0.42]); inked(ctx, C.red, s * 0.03); }
  ctx.beginPath();
  ctx.moveTo(0, -s * 0.6);
  ctx.bezierCurveTo(s * 0.22, -s * 0.35, s * 0.2, s * 0.2, s * 0.14, s * 0.46);
  ctx.lineTo(-s * 0.14, s * 0.46);
  ctx.bezierCurveTo(-s * 0.2, s * 0.2, -s * 0.22, -s * 0.35, 0, -s * 0.6);
  inked(ctx, linear(ctx, -s * 0.2, 0, s * 0.2, 0, ['#FFFFFF', '#E8E4F0', '#B8B0CC']), s * 0.03);
  ctx.save();
  ctx.clip();
  ctx.fillStyle = C.red;
  ctx.fillRect(-s, -s * 0.62, s * 2, s * 0.22);
  ctx.restore();
  circle(ctx, 0, -s * 0.08, s * 0.09);
  inked(ctx, radial(ctx, -s * 0.03, -s * 0.11, 0, s * 0.1, ['#DFF8FF', '#3FA9F5']), s * 0.03);
  ctx.restore();
}
function mirrorBall(ctx, x, y, r) {
  ctx.beginPath();
  ctx.moveTo(x, 0);
  ctx.lineTo(x, y - r);
  stroke(ctx, '#8A8EA0', 2);
  circle(ctx, x, y, r);
  fill(ctx, radial(ctx, x - r * 0.3, y - r * 0.3, 0, r * 1.1, ['#FFFFFF', '#B8C4DC', '#4A5070']));
  ctx.save();
  circle(ctx, x, y, r);
  ctx.clip();
  const n = 9;
  for (let j = 0; j < n; j++) {
    const lat = -Math.PI / 2 + ((j + 0.5) / n) * Math.PI, yy = y + Math.sin(lat) * r, rr0 = Math.cos(lat) * r;
    const cells = Math.max(3, Math.round(rr0 / 5));
    for (let i = 0; i < cells; i++) {
      const u = (i + (j & 1) * 0.5) / cells, xx = x - rr0 + u * rr0 * 2;
      const b = 0.5 + 0.5 * Math.sin(i * 1.7 + j * 2.3);
      ctx.fillStyle = `rgba(${200 + b * 55},${210 + b * 45},255,${0.5 + b * 0.5})`;
      ctx.fillRect(xx, yy - r / n / 2, (rr0 * 2) / cells - 1.2, r / n * 0.9);
    }
  }
  ctx.restore();
  circle(ctx, x, y, r);
  stroke(ctx, alpha(C.ink, 0.6), 1.5);
  sparkle(ctx, x - r * 0.35, y - r * 0.4, r * 0.35);
}
/** Lit disco floor in perspective, from y0 to the bottom. */
function danceFloor(ctx, w, h, y0, cols, t = 0) {
  const rows = 5, n = 8;
  for (let j = 0; j < rows; j++) {
    const v0 = j / rows, v1 = (j + 1) / rows;
    const ya = y0 + (h - y0) * v0 * v0, yb = y0 + (h - y0) * v1 * v1;
    const spreadA = 0.6 + v0 * 0.9, spreadB = 0.6 + v1 * 0.9;
    for (let i = 0; i < n; i++) {
      const ua = (i / n - 0.5) * spreadA, ub = ((i + 1) / n - 0.5) * spreadA, uc = ((i + 1) / n - 0.5) * spreadB, ud = (i / n - 0.5) * spreadB;
      const on = (i + j + Math.floor(t * 2)) % 3 !== 0;
      poly(ctx, [w / 2 + ua * w, ya, w / 2 + ub * w, ya, w / 2 + uc * w, yb, w / 2 + ud * w, yb]);
      inked(ctx, on ? cols[(i * 3 + j * 2) % cols.length] : '#3A2050', 1.5, '#1A0E2A');
    }
  }
}
/** Organic camouflage blobs. */
function camo(ctx, w, h, seed, cols) {
  const r = rng(seed);
  ctx.fillStyle = cols[0];
  ctx.fillRect(0, 0, w, h);
  for (let k = 1; k < cols.length; k++) {
    for (let i = 0; i < 18; i++) {
      const cx = r() * w, cy = r() * h, rad = 20 + r() * 44, pts = 9;
      ctx.beginPath();
      for (let p = 0; p <= pts + 1; p++) {
        const a = (p / pts) * TAU, rr0 = rad * (0.6 + r() * 0.6);
        const px = cx + Math.cos(a) * rr0 * 1.4, py = cy + Math.sin(a) * rr0 * 0.8;
        if (p === 0) ctx.moveTo(px, py); else ctx.quadraticCurveTo(cx + Math.cos(a - 0.35) * rr0 * 1.6, cy + Math.sin(a - 0.35) * rr0, px, py);
      }
      fill(ctx, cols[k]);
    }
  }
}
function bigRig(ctx, x, y, s) {
  const ol = s * 0.02;
  rr(ctx, x - s * 0.5, y - s * 0.95, s, s * 0.95, s * 0.08);
  inked(ctx, linear(ctx, 0, y - s, 0, y, ['#FF5A4A', '#D8242A', '#9A1A20']), ol);
  rr(ctx, x - s * 0.42, y - s * 0.88, s * 0.84, s * 0.34, s * 0.05);
  inked(ctx, linear(ctx, 0, y - s * 0.88, 0, y - s * 0.54, ['#BFE8FF', '#5FA8D8']), ol);
  ctx.fillStyle = 'rgba(255,255,255,0.5)';
  poly(ctx, [x - s * 0.36, y - s * 0.86, x - s * 0.2, y - s * 0.86, x - s * 0.34, y - s * 0.56, x - s * 0.42, y - s * 0.56]);
  ctx.fill();
  ctx.fillRect(x - s * 0.42, y - s * 0.9, s * 0.84, s * 0.05);
  rr(ctx, x - s * 0.3, y - s * 0.48, s * 0.6, s * 0.36, s * 0.04);
  inked(ctx, linear(ctx, 0, y - s * 0.48, 0, y - s * 0.12, ['#FFFFFF', '#9AA4BC', '#E8ECF6', '#7A8098']), ol);
  ctx.strokeStyle = '#5A6078';
  ctx.lineWidth = s * 0.012;
  ctx.beginPath();
  for (let i = 1; i < 10; i++) { ctx.moveTo(x - s * 0.3 + i * s * 0.06, y - s * 0.46); ctx.lineTo(x - s * 0.3 + i * s * 0.06, y - s * 0.14); }
  ctx.stroke();
  for (const sd of [-1, 1]) {
    circle(ctx, x + sd * s * 0.4, y - s * 0.3, s * 0.07);
    inked(ctx, radial(ctx, x + sd * s * 0.4, y - s * 0.32, 0, s * 0.08, ['#FFFFFF', '#FFF0A0', '#E8B830']), ol);
    rr(ctx, x + sd * s * 0.62 - s * 0.05, y - s * 1.35, s * 0.1, s * 1.2, s * 0.05);
    inked(ctx, linear(ctx, x + sd * s * 0.62 - s * 0.05, 0, x + sd * s * 0.62 + s * 0.05, 0, ['#8A8EA0', '#FFFFFF', '#8A8EA0']), ol);
    rr(ctx, x + sd * s * 0.42 - s * 0.1, y - s * 0.02, s * 0.2, s * 0.22, s * 0.06);
    inked(ctx, '#2A2230', ol);
  }
  rr(ctx, x - s * 0.55, y - s * 0.1, s * 1.1, s * 0.12, s * 0.04);
  inked(ctx, linear(ctx, 0, y - s * 0.1, 0, y + s * 0.02, ['#FFFFFF', '#9AA4BC']), ol);
  label(ctx, '13', x, y - s * 0.035, { fam: FONT.sign, px: s * 0.1, fill: C.red });
}
function perspectiveRoad(ctx, w, h, hy, asphalt = '#4A4458') {
  const vx = w / 2;
  poly(ctx, [vx - 6, hy, vx + 6, hy, w * 0.95, h, w * 0.05, h]);
  fill(ctx, linear(ctx, 0, hy, 0, h, [lighten(asphalt, 0.2), asphalt]));
  ctx.fillStyle = '#F4F1E8';
  poly(ctx, [vx - 6, hy, vx - 4, hy, w * 0.09, h, w * 0.05, h]);
  ctx.fill();
  poly(ctx, [vx + 4, hy, vx + 6, hy, w * 0.95, h, w * 0.91, h]);
  ctx.fill();
  ctx.fillStyle = '#FFD23A';
  for (let i = 0; i < 7; i++) {
    const a = Math.pow(i / 7, 2), b = Math.pow((i + 0.5) / 7, 2);
    const ya = hy + (h - hy) * a, yb = hy + (h - hy) * b, wa = 1 + a * 10, wb = 1 + b * 10;
    poly(ctx, [vx - wa / 2, ya, vx + wa / 2, ya, vx + wb / 2, yb, vx - wb / 2, yb]);
    ctx.fill();
  }
}
/** Sunset desert: banded sky, sliced sun, mesas and a striped sand floor from the horizon `hz` down. */
function desertScene(ctx, w, h, hz, sunR) {
  ctx.fillStyle = linear(ctx, 0, 0, 0, hz, ['#5A2A6E', '#C2407A', '#FF7E5F', '#FFB36B', '#FFE3A3']);
  ctx.fillRect(0, 0, w, h);
  slicedSun(ctx, w * 0.5, hz - sunR * 0.3, sunR, '#FFF1A0', '#FF8A3A', '#FFB36B');
  mesas(ctx, w, hz, '#8A3A5A', 12);
  ctx.fillStyle = linear(ctx, 0, hz + h * 0.02, 0, h, ['#E08A4A', '#C0602E']);
  ctx.fillRect(0, hz + h * 0.04, w, h);
  ctx.fillStyle = 'rgba(120,50,30,0.35)';
  for (let y = hz + h * 0.08; y < h; y += h * 0.04) ctx.fillRect(0, y, w, 1.5);
}
/** Op-art hypno spiral (Agent Thirteen) centred at (cx, cy). */
function opSpiral(ctx, w, h, cx, cy) {
  ctx.fillStyle = '#F6E7C8';
  ctx.fillRect(0, 0, w, h);
  const arms = 14, R = Math.hypot(w, h);
  ctx.fillStyle = '#2A1D3A';
  for (let i = 0; i < arms; i += 2) {
    ctx.beginPath();
    for (let k = 0; k <= 40; k++) { const rr0 = (k / 40) * R, a = (i / arms) * TAU + rr0 * 0.012; ctx.lineTo(cx + Math.cos(a) * rr0, cy + Math.sin(a) * rr0); }
    for (let k = 40; k >= 0; k--) { const rr0 = (k / 40) * R, a = ((i + 1) / arms) * TAU + rr0 * 0.012; ctx.lineTo(cx + Math.cos(a) * rr0, cy + Math.sin(a) * rr0); }
    ctx.fill();
  }
  for (let k = 0; k < 4; k++) { circle(ctx, cx, cy, 40 + k * 46); stroke(ctx, alpha(C.orange, 0.85), 5); }
  ctx.fillStyle = radial(ctx, cx, cy, 20, Math.max(w, h) * 0.7, ['rgba(246,231,200,0)', 'rgba(42,29,58,0.55)']);
  ctx.fillRect(0, 0, w, h);
}
/** Jungle camouflage with corner fronds (Commando Club). */
function jungle(ctx, w, h) {
  camo(ctx, w, h, 71, ['#6E7A3A', '#4A5A2A', '#A89A5A', '#3A3020']);
  ctx.fillStyle = radial(ctx, w / 2, h / 2, w * 0.2, Math.max(w, h) * 0.8, ['rgba(20,24,10,0)', 'rgba(20,24,10,0.55)']);
  ctx.fillRect(0, 0, w, h);
  for (const [x, y, a] of [[0, 0, 0.6], [w, 0, 2.5], [0, h, -0.6], [w, h, -2.5]]) frond(ctx, x, y, 120, a);
}
function weatherMapArt(ctx, x, y, w, h, o = {}) {
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(w / 512, h / 341);
  ctx.fillStyle = linear(ctx, 0, 0, 0, 341, ['#3E86D8', '#2F6FC0']);
  ctx.fillRect(0, 0, 512, 341);
  ctx.strokeStyle = 'rgba(255,255,255,0.12)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let i = 1; i < 12; i++) { ctx.moveTo(i * 44, 0); ctx.lineTo(i * 44, 341); }
  for (let j = 1; j < 8; j++) { ctx.moveTo(0, j * 44); ctx.lineTo(512, j * 44); }
  ctx.stroke();
  const land = new Path2D('M40 60 C120 30 200 50 260 40 C330 30 420 45 470 70 C495 110 480 160 488 210 C495 260 470 300 420 310 C340 322 260 300 190 312 C120 322 60 300 45 250 C30 200 50 160 36 120 C30 95 32 75 40 60 Z');
  ctx.save();
  ctx.translate(4, 6);
  ctx.fillStyle = 'rgba(20,20,60,0.35)';
  ctx.fill(land);
  ctx.restore();
  ctx.fillStyle = '#8CCB6A';
  ctx.fill(land);
  ctx.save();
  ctx.clip(land);
  const counties = [['#A6D873', 'M0 0 L200 0 L185 150 L210 341 L0 341 Z'], ['#E9D98A', 'M200 0 L350 0 L330 160 L360 341 L210 341 L185 150 Z'], ['#F2B48A', 'M350 0 L512 0 L512 341 L360 341 L330 160 Z']];
  for (const [col, d] of counties) { ctx.fillStyle = col; ctx.fill(new Path2D(d)); }
  ctx.fillStyle = '#5FB0F0';
  ctx.fill(new Path2D('M95 200 C120 180 160 190 165 215 C170 240 130 255 105 245 C85 238 80 215 95 200 Z'));
  ctx.strokeStyle = '#5FB0F0';
  ctx.lineWidth = 6;
  ctx.lineCap = 'round';
  ctx.stroke(new Path2D('M160 210 C220 230 250 170 300 190 C350 210 380 260 440 250 C470 245 490 260 512 250'));
  ctx.setLineDash([7, 6]);
  ctx.strokeStyle = 'rgba(60,40,80,0.6)';
  ctx.lineWidth = 3;
  ctx.stroke(new Path2D('M200 0 L185 150 L210 341 M350 0 L330 160 L360 341'));
  ctx.setLineDash([]);
  const r = rng(3);
  for (let i = 0; i < 26; i++) { const px = 60 + r() * 400, py = 70 + r() * 220; poly(ctx, [px - 6, py, px, py - 9, px + 6, py]); fill(ctx, 'rgba(60,110,50,0.35)'); }
  ctx.restore();
  ctx.lineJoin = 'round';
  ctx.strokeStyle = C.ink;
  ctx.lineWidth = 4;
  ctx.stroke(land);
  if (o.names !== false) {
    const names = [['WEBB', 100, 110], ['ORVILLE', 268, 100], ['CASS', 420, 120]];
    for (const [n, nx, ny] of names) label(ctx, n, nx, ny, { fam: FONT.sign, px: 17, fill: '#FFFDF2', stroke: '#3A2A5A', lw: 4 });
  }
  const tx = 400, ty = 238;
  circle(ctx, tx, ty - 16, 26);
  fill(ctx, 'rgba(255,255,255,0.75)');
  towerIcon(ctx, tx, ty, 40, C.red);
  circle(ctx, 250, 225, 7);
  inked(ctx, C.white, 3);
  if (o.temps) {
    for (const [tt, tx0, ty0] of [['58', 110, 170], ['61', 270, 150], ['55', 440, 190]]) label(ctx, tt + '°', tx0, ty0, { fam: FONT.round, px: 26, fill: '#FFFFFF', stroke: '#2A3A8A', lw: 5 });
  }
  ctx.restore();
}

// ---------------------------------------------------------------------------------------------------------
// Telly's nine channel cards (show_<n>): each a 70s title card with the green OSD number
// ---------------------------------------------------------------------------------------------------------

const SHOWS = {
  2: ['Precinct 13', (ctx, w, h) => {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#141638', '#2A2F6B', '#6B3A6E']);
    ctx.fillRect(0, 0, w, h);
    starField(ctx, w, h, 50, 21, 0.55);
    circle(ctx, w * 0.91, h * 0.37, 24);
    fill(ctx, C.moon);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    for (const [x, a] of [[0.25, -0.35], [0.7, 0.3]]) {
      ctx.save();
      ctx.translate(w * x, h);
      ctx.rotate(a);
      poly(ctx, [-10, 0, 10, 0, 70, -h * 1.2, -70, -h * 1.2]);
      fill(ctx, linear(ctx, 0, 0, 0, -h, ['rgba(255,240,200,0.35)', 'rgba(255,240,200,0)']));
      ctx.restore();
    }
    glowBlob(ctx, 0, h * 0.8, w * 0.45, '#FF3B30', 0.55);
    glowBlob(ctx, w, h * 0.8, w * 0.45, '#3A7BFF', 0.6);
    ctx.restore();
    skyline(ctx, w, h * 0.9, 60, 150, '#2A2358', 5, 0.15, '#8A7AD8');
    skyline(ctx, w, h, 50, 120, '#141030', 8, 0.35);
    // title: chrome word + police shield
    label(ctx, 'PRECINCT', w * 0.37, h * 0.19, { fam: FONT.sign, px: 58, maxW: w * 0.6, fill: vgrad(CHROME), stroke: '#141040', lw: 7, depth: 5, depthFill: '#5A2A8A', skew: -0.18 });
    shield(ctx, w * 0.775, h * 0.215, 40);
  }],
  4: ['Dusty Trails', (ctx, w, h) => {
    desertScene(ctx, w, h, h * 0.7, 92);
    cactus(ctx, w * 0.1, h, h * 0.55, '#2F6A3A', '#12301C');
    cactus(ctx, w * 0.9, h * 1.02, h * 0.45, '#2F6A3A', '#12301C');
    cactus(ctx, w * 0.72, h * 0.8, h * 0.14, '#6A3A4A');
    label(ctx, 'Dusty Trails', w * 0.45, h * 0.2, { fam: FONT.groovy, px: 72, maxW: w * 0.74, fill: vgrad(['#FFF3D0', '#F2C27A', '#D08A3A']), stroke: '#4A1E14', lw: 8, depth: 6, depthFill: '#7A2E1E', rot: -0.04 });
    ctx.beginPath();
    ctx.moveTo(w * 0.18, h * 0.33);
    ctx.bezierCurveTo(w * 0.4, h * 0.4, w * 0.6, h * 0.28, w * 0.82, h * 0.34);
    stroke(ctx, '#4A1E14', 5);
    stroke(ctx, '#E8B070', 2.5);
  }],
  5: ['Agent Thirteen', (ctx, w, h) => {
    opSpiral(ctx, w, h, w / 2, h * 0.55);
    rr(ctx, 0, 0, w, h * 0.3, 0);
    fill(ctx, 'rgba(26,18,40,0.82)');
    label(ctx, 'AGENT', w * 0.45, h * 0.09, { fam: FONT.sign, px: 26, fill: C.orange, track: 12 });
    label(ctx, 'THIRTEEN', w * 0.45, h * 0.2, { fam: FONT.sign, px: 58, maxW: w * 0.72, fill: vgrad(['#FFFFFF', '#F6E7C8']), stroke: C.red, lw: 5, track: 3 });
  }],
  7: ['Commando Club', (ctx, w, h) => {
    jungle(ctx, w, h);
    const py = h * 0.12, ph = h * 0.22;
    rr(ctx, w * 0.06, py, w * 0.78, ph, 8);
    inked(ctx, linear(ctx, 0, py, 0, py + ph, ['#5A6A2E', '#3E4A1E']), 4, '#1E2410');
    for (const sx of [0.09, 0.81]) { circle(ctx, w * sx, py + ph / 2, 5); inked(ctx, '#C9CED8', 2, '#1E2410'); }
    stencil(ctx, 'COMMANDO CLUB', w * 0.45, py + ph * 0.54, 44, w * 0.64, '#F4E03A');
    starBadge(ctx, w * 0.5, h * 0.86, 30);
  }],
  8: ['Truckers!', (ctx, w, h) => {
    const hy = h * 0.52;
    ctx.fillStyle = linear(ctx, 0, 0, 0, hy, ['#4AA8F0', '#9ED8FF', '#FFE3A3']);
    ctx.fillRect(0, 0, w, hy);
    sunIcon(ctx, w * 0.16, h * 0.34, 34, false);
    cloud(ctx, w * 0.62, h * 0.36, 110, 40, '#FFFFFF');
    mesas(ctx, w, hy, '#B87A9A', 30);
    ctx.fillStyle = linear(ctx, 0, hy, 0, h, ['#D8B070', '#A8783A']);
    ctx.fillRect(0, hy, w, h - hy);
    perspectiveRoad(ctx, w, h, hy);
    for (let i = 0; i < 5; i++) {
      const u = Math.pow(i / 5, 2), px = w / 2 - 20 - u * w * 0.55, py = hy + (h - hy) * u, ph = 8 + u * 120;
      capsule(ctx, px, py, px, py - ph, 1 + u * 5, '#5A3A2A');
      capsule(ctx, px - ph * 0.15, py - ph * 0.85, px + ph * 0.15, py - ph * 0.85, 1 + u * 3, '#5A3A2A');
    }
    bigRig(ctx, w * 0.74, h * 0.98, 150);
    label(ctx, 'TRUCKERS!', w * 0.4, h * 0.17, { fam: FONT.sign, px: 64, maxW: w * 0.72, fill: vgrad(CHROME), stroke: '#8A1414', lw: 8, depth: 6, depthFill: '#4A0E14', skew: -0.22 });
  }],
  9: ['Saturday Morning Cartoons', (ctx, w, h) => {
    ctx.fillStyle = '#FFD23A';
    ctx.fillRect(0, 0, w, h);
    rays(ctx, w / 2, h * 0.62, w, 20, '#FFB020', 0.1);
    halftone(ctx, 0, 0, w, h, 'rgba(255,120,60,0.35)', 14, (u, v) => 0.25 + 0.35 * v);
    cloud(ctx, w * 0.2, h * 0.84, 170, 70, '#FFFFFF', C.ink, 3);
    cloud(ctx, w * 0.82, h * 0.88, 190, 76, '#FFFFFF', C.ink, 3);
    sunIcon(ctx, w * 0.86, h * 0.48, 38, true, 0.2);
    rocket(ctx, w * 0.13, h * 0.5, 64, 0.5);
    for (const [x, y, c] of [[0.3, 0.62, '#FF4F5E'], [0.66, 0.66, '#3FA9F5'], [0.5, 0.9, '#52D24A']]) { starPath(ctx, w * x, h * y, 16, 7, 5); inked(ctx, c, 3); }
    balloonText(ctx, 'SATURDAY MORNING', w * 0.45, h * 0.19, 40, 0.3, 0.8, w * 0.76);
    balloonText(ctx, 'CARTOONS', w * 0.47, h * 0.39, 58, 0.1, 2.2, w * 0.7);
  }],
  11: ['Space Patrol 3000', (ctx, w, h) => {
    ctx.fillStyle = linear(ctx, 0, 0, w, h, ['#0E0A2A', '#1E1450', '#3A1A5A']);
    ctx.fillRect(0, 0, w, h);
    glowBlob(ctx, w * 0.3, h * 0.6, 180, '#FF4FA0', 0.35);
    glowBlob(ctx, w * 0.75, h * 0.4, 160, '#5FE3FF', 0.3);
    starField(ctx, w, h, 110, 111);
    ringedPlanet(ctx, w * 0.8, h * 0.78, 62, '#FFB36B', '#C2407A', '#FFE3A3');
    circle(ctx, w * 0.12, h * 0.8, 20);
    fill(ctx, linear(ctx, 0, h * 0.75, 0, h * 0.85, ['#E8E4F0', '#8A7AB8']));
    ctx.strokeStyle = 'rgba(255,255,255,0.5)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let i = 0; i < 5; i++) { ctx.moveTo(w * 0.12 - i * 14, h * 0.62 + i * 12); ctx.lineTo(w * 0.28 - i * 14, h * 0.52 + i * 12); }
    ctx.stroke();
    rocket(ctx, w * 0.36, h * 0.52, 80, 1.0);
    label(ctx, 'SPACE PATROL', w * 0.44, h * 0.14, { fam: FONT.sign, px: 50, maxW: w * 0.74, fill: vgrad(CHROME), stroke: '#141040', lw: 6, depth: 5, depthFill: '#3A1A6A' });
    label(ctx, '3000', w * 0.44, h * 0.3, { fam: FONT.sign, px: 52, fill: vgrad(['#FFFFFF', '#FF9AD0', '#FF4FA0']), stroke: '#2A0E3A', lw: 6, glow: '#FF4FA0', track: 8 });
  }],
  12: ['The Groove Hour', (ctx, w, h) => {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#1A0E2E', '#3A1450', '#5A1A5A']);
    ctx.fillRect(0, 0, w, h);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    for (const [x, a, c] of [[0.15, 0.5, '#FF4FA0'], [0.5, 0, '#5FE3FF'], [0.85, -0.5, '#FFC23A'], [0.35, 0.25, '#52E04A'], [0.65, -0.25, '#9B6BFF']]) {
      ctx.save();
      ctx.translate(w * x, -10);
      ctx.rotate(a);
      poly(ctx, [-6, 0, 6, 0, 60, h * 1.1, -60, h * 1.1]);
      fill(ctx, linear(ctx, 0, 0, 0, h, [alpha(c, 0.55), alpha(c, 0.05)]));
      ctx.restore();
    }
    ctx.restore();
    danceFloor(ctx, w, h, h * 0.72, ['#FF4FA0', '#FFC23A', '#5FE3FF', '#52E04A', '#9B6BFF']);
    mirrorBall(ctx, w / 2, h * 0.42, 34);
    const r = rng(12);
    for (let i = 0; i < 14; i++) sparkle(ctx, r() * w, r() * h * 0.7, 3 + r() * 5, 0.8);
    label(ctx, 'The Groove Hour', w * 0.45, h * 0.17, { fam: FONT.groovy, px: 62, maxW: w * 0.78, fill: vgrad(['#FFFFFF', '#FFE58A', '#FFB020']), stroke: '#2A0A3A', lw: 7, depth: 6, depthFill: '#FF4FA0', depthStroke: '#2A0A3A', shadow: 'rgba(255,79,160,0.8)', shadowBlur: 18 });
  }],
  13: ['Weather Watch 13', (ctx, w, h) => {
    weatherMapArt(ctx, 0, h * 0.18, w, h * 0.82, { temps: true, names: false });
    sunIcon(ctx, w * 0.2, h * 0.5, 30, true);
    cloud(ctx, w * 0.58, h * 0.47, 90, 42, '#FFFFFF', C.ink, 2.5);
    cloud(ctx, w * 0.8, h * 0.72, 80, 38, '#DDE3F0', C.ink, 2.5);
    ctx.strokeStyle = '#5FA8FF';
    ctx.lineWidth = 3;
    ctx.beginPath();
    for (let i = 0; i < 4; i++) { ctx.moveTo(w * 0.76 + i * 10, h * 0.8); ctx.lineTo(w * 0.74 + i * 10, h * 0.87); }
    ctx.stroke();
    rr(ctx, 0, 0, w, h * 0.2, 0);
    fill(ctx, linear(ctx, 0, 0, 0, h * 0.2, ['#2A4FB8', '#1B327E']));
    ctx.fillStyle = C.red;
    ctx.fillRect(0, h * 0.2 - 6, w, 6);
    ctx.fillStyle = C.white;
    ctx.fillRect(0, h * 0.2 - 9, w, 3);
    badge13(ctx, w * 0.09, h * 0.095, h * 0.068, { ol: 2 });
    label(ctx, 'WEATHER WATCH', w * 0.46, h * 0.1, { fam: FONT.sign, px: 40, maxW: w * 0.6, fill: vgrad(['#FFFFFF', '#DDE6F4']), stroke: '#0E1A4A', lw: 5, depth: 3, depthFill: '#0E1A4A', track: 1 });
  }],
};

function shield(ctx, x, y, s) {
  starPath(ctx, x, y, s, s * 0.62, 7, -Math.PI / 2);
  inked(ctx, linear(ctx, 0, y - s, 0, y + s, GOLDEN), s * 0.08);
  circle(ctx, x, y, s * 0.5);
  inked(ctx, C.blue, s * 0.05);
  label(ctx, '13', x, y + s * 0.04, { fam: FONT.round, px: s * 0.55, fill: '#FFFFFF' });
}
function starBadge(ctx, x, y, r) {
  circle(ctx, x, y, r);
  inked(ctx, '#F4F1E8', r * 0.1, '#1E2410');
  starPath(ctx, x, y, r * 0.78, r * 0.32, 5);
  fill(ctx, '#3E4A1E');
}
function frond(ctx, x, y, len, a) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(a);
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.quadraticCurveTo(len * 0.5, -len * 0.1, len, len * 0.1);
  stroke(ctx, '#2A4A1E', 4);
  for (let i = 1; i < 9; i++) {
    const u = i / 9, px = len * u, py = -len * 0.1 * Math.sin(u * Math.PI) + len * 0.1 * u * u;
    for (const s of [-1, 1]) {
      ctx.beginPath();
      ctx.moveTo(px, py);
      ctx.quadraticCurveTo(px + 8, py + s * 18, px + 18, py + s * 30 * (1 - u * 0.5));
      stroke(ctx, i & 1 ? '#3E6A2A' : '#2F5A22', 7 - u * 3);
    }
  }
  ctx.restore();
}
/** Army-stencil lettering: text with bridges cut through each glyph. */
function stencil(ctx, str, x, y, px, maxW, col) {
  const c = layer(`stencil:${str}:${px}:${col}`, Math.ceil(maxW) + 20, Math.ceil(px * 1.6), (g, lw, lh) => {
    label(g, str, lw / 2, lh / 2, { fam: FONT.sign, px, maxW, fill: col });
    g.globalCompositeOperation = 'destination-out';
    setFont(g, px, FONT.sign);
    g.fillStyle = '#000';
    const tw = Math.min(maxW, g.measureText(str).width), n = str.length;
    for (let i = 0; i < n; i++) if (str[i] !== ' ') g.fillRect(lw / 2 - tw / 2 + (tw * (i + 0.5)) / n - 1.5, 0, 3, lh);
  });
  ctx.drawImage(c, x - c.width / 2, y - c.height / 2);
}

for (const n of [2, 4, 5, 7, 8, 9, 11, 12, 13]) {
  card(`show_${n}`, { w: 512, h: 384, opts: 'osd: false hides the channel number' }, (ctx, w, h, t, o) => {
    SHOWS[n][1](ctx, w, h);
    vignette(ctx, w, h, 0.3, '20,12,36', 0.5);
    if (o.osd !== false) osd(ctx, w, h, String(n));
  });
}

// ---------------------------------------------------------------------------------------------------------
// Character-select promo backdrops (channels 2, 4, 5, 7). The 3D hero stands in the middle.
// ---------------------------------------------------------------------------------------------------------

const PROMOS = {
  skip: [2, (ctx, w, h) => {
    ctx.fillStyle = '#5A2A22';
    ctx.fillRect(0, 0, w, h);
    for (let j = 0; j < 24; j++) for (let i = -1; i < 14; i++) {
      const bx = i * 40 + (j & 1) * 20, by = j * 18;
      rr(ctx, bx + 1.5, by + 1.5, 37, 15, 3);
      fill(ctx, mix('#8A3A2A', '#A8503A', ((i * 7 + j * 3) % 5) / 5));
    }
    ctx.fillStyle = radial(ctx, w * 0.5, h * 0.35, 30, w * 0.7, ['rgba(255,210,140,0.45)', 'rgba(40,16,20,0.75)']);
    ctx.fillRect(0, 0, w, h);
    for (const x of [0.08, 0.92]) {
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      poly(ctx, [w * x - 12, h * 0.08, w * x + 12, h * 0.08, w * x + (x < 0.5 ? 160 : -60), h, w * x - (x < 0.5 ? 60 : 160), h]);
      fill(ctx, linear(ctx, 0, h * 0.08, 0, h, ['rgba(255,220,150,0.5)', 'rgba(255,220,150,0)']));
      ctx.restore();
      rr(ctx, w * x - 16, h * 0.04, 32, 24, 6);
      inked(ctx, '#2A2230', 2);
      circle(ctx, w * x, h * 0.1, 8);
      fill(ctx, '#FFF4C8');
    }
    ctx.strokeStyle = '#1E1824';
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.2);
    ctx.bezierCurveTo(w * 0.3, h * 0.34, w * 0.6, h * 0.1, w, h * 0.26);
    ctx.moveTo(0, h * 0.28);
    ctx.bezierCurveTo(w * 0.4, h * 0.4, w * 0.7, h * 0.22, w, h * 0.34);
    ctx.stroke();
    for (const [x, y, cw, ch] of [[0.02, 0.66, 0.22, 0.34], [0.2, 0.78, 0.16, 0.22], [0.76, 0.62, 0.24, 0.38]]) {
      rr(ctx, w * x, h * y, w * cw, h * ch, 6);
      inked(ctx, linear(ctx, 0, h * y, 0, h, ['#4A4A5A', '#2A2A38']), 3, '#141018');
      ctx.fillStyle = '#C9CED8';
      for (const k of [0.1, 0.9]) ctx.fillRect(w * (x + cw * k) - 4, h * y, 8, h * ch);
      label(ctx, 'WZTV 13', w * (x + cw / 2), h * (y + 0.1), { fam: FONT.sign, px: 14, maxW: w * cw * 0.7, fill: '#F4F1E8' });
    }
    const sy = h * 0.06, sh = h * 0.16;
    rr(ctx, w * 0.2, sy, w * 0.6, sh, 6);
    fill(ctx, '#1E1824');
    ctx.save();
    rr(ctx, w * 0.2, sy, w * 0.6, sh, 6);
    ctx.clip();
    for (let i = -4; i < 30; i++) { poly(ctx, [w * 0.2 + i * 18, sy, w * 0.2 + i * 18 + 9, sy, w * 0.2 + i * 18 - 6, sy + sh, w * 0.2 + i * 18 - 15, sy + sh]); fill(ctx, '#F4C81E'); }
    rr(ctx, w * 0.22, sy + 6, w * 0.56, sh - 12, 4);
    fill(ctx, '#1E1824');
    ctx.restore();
    label(ctx, 'BEHIND THE SCENES', w / 2, sy + sh / 2 + 1, { fam: FONT.sign, px: 30, maxW: w * 0.52, fill: '#F4C81E' });
  }],
  roxy: [4, (ctx, w, h) => {
    ctx.fillStyle = radial(ctx, w / 2, h * 0.55, 10, w * 0.8, ['#FFB36B', '#E3462B', '#6B1A4A']);
    ctx.fillRect(0, 0, w, h);
    rays(ctx, w / 2, h * 0.55, w, 24, 'rgba(255,79,160,0.45)', 0.05);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    glowBlob(ctx, w / 2, h * 0.5, 180, '#FFE3A3', 0.35);
    ctx.restore();
    danceFloor(ctx, w, h, h * 0.7, ['#FF4FA0', '#FFC23A', '#5FE3FF', '#52E04A', '#FF8A2A']);
    mirrorBall(ctx, w * 0.84, h * 0.2, 30);
    const r = rng(44);
    for (let i = 0; i < 16; i++) sparkle(ctx, r() * w, r() * h * 0.65, 3 + r() * 6, 0.9);
    label(ctx, 'Boogie Down', w * 0.42, h * 0.13, { fam: FONT.groovy, px: 56, maxW: w * 0.7, fill: vgrad(['#FFFFFF', '#FFE0F0', '#FF9AD0']), stroke: '#6A1A4A', lw: 7, depth: 5, depthFill: '#3A0E2A', rot: -0.05 });
    label(ctx, 'SATURDAY', w * 0.45, h * 0.27, { fam: FONT.sign, px: 26, fill: '#FFE14A', stroke: '#6A1A4A', lw: 5, track: 8, rot: -0.05 });
  }],
  penny: [5, (ctx, w, h) => {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#2E62B8', '#234C94']);
    ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = 'rgba(200,230,255,0.22)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = 0; x < w; x += 16) { ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, h); }
    for (let y = 0; y < h; y += 16) { ctx.moveTo(0, y + 0.5); ctx.lineTo(w, y + 0.5); }
    ctx.stroke();
    ctx.strokeStyle = 'rgba(220,240,255,0.75)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(20, h * 0.5);
    for (let i = 0; i < 6; i++) { ctx.lineTo(30 + i * 8, h * 0.5 + (i & 1 ? -8 : 8)); }
    ctx.lineTo(90, h * 0.5);
    ctx.lineTo(120, h * 0.5);
    ctx.moveTo(w - 130, h * 0.62);
    ctx.lineTo(w - 20, h * 0.62);
    ctx.stroke();
    for (const [x, y] of [[0.12, 0.72], [0.88, 0.38]]) {
      circle(ctx, w * x, h * y, 26);
      stroke(ctx, 'rgba(220,240,255,0.75)', 2);
      ctx.beginPath();
      ctx.moveTo(w * x - 10, h * y + 16); ctx.lineTo(w * x - 10, h * y - 4); ctx.lineTo(w * x + 10, h * y - 4); ctx.lineTo(w * x + 10, h * y + 16);
      ctx.moveTo(w * x - 14, h * y - 12); ctx.lineTo(w * x + 14, h * y - 12);
      ctx.stroke();
    }
    const ox = w * 0.83, oy = h * 0.78, orr = 44;
    rr(ctx, ox - orr - 12, oy - orr - 12, orr * 2 + 24, orr * 2 + 24, 10);
    inked(ctx, '#5A5A6A', 3, '#1E1830');
    circle(ctx, ox, oy, orr);
    fill(ctx, '#0E2A1E');
    ctx.strokeStyle = 'rgba(92,255,110,0.3)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let k = -2; k <= 2; k++) { ctx.moveTo(ox - orr, oy + k * 16); ctx.lineTo(ox + orr, oy + k * 16); ctx.moveTo(ox + k * 16, oy - orr); ctx.lineTo(ox + k * 16, oy + orr); }
    ctx.stroke();
    ctx.beginPath();
    for (let i = 0; i <= 40; i++) { const u = i / 40; ctx.lineTo(ox - orr + u * orr * 2, oy + Math.sin(u * TAU * 2) * 20); }
    ctx.save();
    ctx.shadowColor = C.osd;
    ctx.shadowBlur = 8;
    stroke(ctx, C.osd, 2.5);
    ctx.restore();
    for (const x of [0.03, 0.97]) {
      const rx = x < 0.5 ? 0 : w - 40;
      rr(ctx, rx, h * 0.12, 40, h * 0.5, 4);
      inked(ctx, '#3A3A4A', 2, '#141018');
      for (let j = 0; j < 12; j++) for (let i = 0; i < 2; i++) {
        circle(ctx, rx + 12 + i * 16, h * 0.15 + j * 15, 3.5);
        fill(ctx, (i + j) % 4 === 0 ? '#FF5A3C' : (i + j) % 3 === 0 ? C.osd : '#1E1824');
      }
    }
    rr(ctx, w * 0.2, h * 0.06, w * 0.6, h * 0.17, 4);
    inked(ctx, C.white, 3, '#141018');
    ctx.fillStyle = C.orange;
    ctx.fillRect(w * 0.2, h * 0.06, w * 0.04, h * 0.17);
    label(ctx, 'ENGINEERING', w * 0.52, h * 0.115, { fam: FONT.sign, px: 26, maxW: w * 0.5, fill: '#1E3A7A' });
    label(ctx, 'REPORT', w * 0.52, h * 0.185, { fam: FONT.osd, px: 30, fill: C.orange, track: 10 });
  }],
  duke: [7, (ctx, w, h) => {
    SHOWS[2][1](ctx, w, h);
    ctx.fillStyle = 'rgba(20,16,50,0.25)';
    ctx.fillRect(0, h * 0.3, w, h * 0.7);
  }],
};
for (const hero of HERO_IDS) {
  card(`promo_${hero}`, { w: 512, h: 384, opts: 'osd: false hides the channel number' }, (ctx, w, h, t, o) => {
    PROMOS[hero][1](ctx, w, h);
    vignette(ctx, w, h, 0.4, '20,12,36', 0.45);
    if (o.osd !== false) osd(ctx, w, h, String(PROMOS[hero][0]));
  });
}

// ---------------------------------------------------------------------------------------------------------
// Chroma-Key stock-footage worlds (16:9, sampled in screen space by the keyed shader)
// ---------------------------------------------------------------------------------------------------------

const WORLDS = {
  space(ctx, w, h) {
    ctx.fillStyle = linear(ctx, 0, 0, w, h, ['#0A0826', '#1A1048', '#2A0E3E']);
    ctx.fillRect(0, 0, w, h);
    glowBlob(ctx, w * 0.25, h * 0.4, 170, '#FF4FA0', 0.3);
    glowBlob(ctx, w * 0.6, h * 0.7, 150, '#5FE3FF', 0.25);
    starField(ctx, w, h, 160, 5);
    ringedPlanet(ctx, w * 0.68, h * 0.46, 64, '#FFB36B', '#B5472A', '#FFE3A3');
    circle(ctx, w * 0.18, h * 0.24, 16);
    fill(ctx, linear(ctx, 0, h * 0.2, 0, h * 0.28, ['#E8E4F0', '#7A6AA8']));
  },
  beach(ctx, w, h) {
    const hy = h * 0.52;
    ctx.fillStyle = linear(ctx, 0, 0, 0, hy, ['#3FB6F5', '#9EE0FF', '#FFE9C2']);
    ctx.fillRect(0, 0, w, hy);
    sunIcon(ctx, w * 0.78, h * 0.2, 30, false);
    cloud(ctx, w * 0.3, h * 0.2, 110, 36, '#FFFFFF');
    ctx.fillStyle = linear(ctx, 0, hy, 0, h * 0.78, ['#1E8CD8', '#2EC4D8', '#6EE6D8']);
    ctx.fillRect(0, hy, w, h * 0.3);
    ctx.strokeStyle = 'rgba(255,255,255,0.8)';
    ctx.lineWidth = 3;
    for (let j = 0; j < 4; j++) {
      ctx.beginPath();
      for (let x = 0; x <= w; x += 8) ctx.lineTo(x, hy + 14 + j * 16 + Math.sin(x * 0.05 + j) * 3);
      ctx.stroke();
    }
    ctx.fillStyle = linear(ctx, 0, h * 0.74, 0, h, ['#FFE3A3', '#F2C27A']);
    ctx.beginPath();
    ctx.moveTo(0, h * 0.8);
    for (let x = 0; x <= w; x += 16) ctx.lineTo(x, h * 0.78 + Math.sin(x * 0.03) * 5);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.fill();
    palm(ctx, w * 0.1, h, h * 0.8, '#8A5A3C', '#2E9A4A');
    ctx.save();
    ctx.translate(w * 0.72, h * 0.86);
    ctx.beginPath();
    ctx.moveTo(-60, 0);
    ctx.quadraticCurveTo(0, -50, 60, 0);
    ctx.closePath();
    fill(ctx, C.red);
    ctx.save();
    ctx.clip();
    for (let i = -3; i < 3; i++) { poly(ctx, [0, -50, i * 20 + 10, 0, i * 20 + 20, 0]); fill(ctx, '#F4F1E8'); }
    ctx.restore();
    capsule(ctx, 0, -40, 4, 40, 4, '#E8E4F0');
    ctx.restore();
  },
  volcano(ctx, w, h) {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#2A0E2A', '#7A1A2A', '#E3662B']);
    ctx.fillRect(0, 0, w, h);
    const r = rng(8);
    for (let i = 0; i < 9; i++) { circle(ctx, w * 0.5 + (r() - 0.5) * 160, h * 0.2 - r() * 40, 30 + r() * 30); fill(ctx, `rgba(60,30,50,${0.5 + r() * 0.3})`); }
    glowBlob(ctx, w * 0.5, h * 0.4, 200, '#FFB347', 0.55);
    poly(ctx, [w * 0.12, h, w * 0.43, h * 0.38, w * 0.57, h * 0.38, w * 0.9, h]);
    fill(ctx, linear(ctx, 0, h * 0.38, 0, h, ['#5A2A3A', '#2A1424']));
    ctx.fillStyle = '#FF8A2A';
    ctx.beginPath();
    ctx.moveTo(w * 0.47, h * 0.4);
    ctx.bezierCurveTo(w * 0.45, h * 0.6, w * 0.38, h * 0.7, w * 0.33, h);
    ctx.lineTo(w * 0.38, h);
    ctx.bezierCurveTo(w * 0.43, h * 0.72, w * 0.5, h * 0.6, w * 0.52, h * 0.4);
    ctx.fill();
    for (let i = 0; i < 14; i++) {
      const a = -Math.PI / 2 + (r() - 0.5) * 1.4, d = 30 + r() * 90;
      circle(ctx, w * 0.5 + Math.cos(a) * d, h * 0.36 + Math.sin(a) * d, 5 + r() * 9);
      fill(ctx, i & 1 ? '#FFD23A' : '#FF5A2A');
    }
    ellipse(ctx, w * 0.5, h * 0.38, w * 0.07, h * 0.03);
    fill(ctx, '#FFF1A0');
  },
  underwater(ctx, w, h) {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#5FD8F0', '#1E8CC8', '#0E3A7A']);
    ctx.fillRect(0, 0, w, h);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    for (let i = 0; i < 6; i++) { poly(ctx, [w * (0.1 + i * 0.16), 0, w * (0.16 + i * 0.16), 0, w * (0.26 + i * 0.14), h, w * (0.14 + i * 0.14), h]); fill(ctx, 'rgba(200,250,255,0.07)'); }
    ctx.restore();
    ctx.fillStyle = '#E8C98A';
    ctx.beginPath();
    ctx.moveTo(0, h * 0.86);
    ctx.quadraticCurveTo(w * 0.5, h * 0.78, w, h * 0.88);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.fill();
    const r = rng(15);
    for (let i = 0; i < 7; i++) {
      const x = r() * w;
      ctx.beginPath();
      ctx.moveTo(x, h);
      ctx.bezierCurveTo(x - 20, h * 0.8, x + 20, h * 0.7, x, h * (0.5 + r() * 0.2));
      stroke(ctx, i & 1 ? '#2E9A4A' : '#52D24A', 6);
    }
    for (const [x, y, s, c] of [[0.3, 0.4, 26, '#FF8A2A'], [0.62, 0.3, 20, '#FFD23A'], [0.75, 0.6, 30, '#FF4FA0'], [0.45, 0.62, 16, '#FF8A2A']]) fish(ctx, w * x, h * y, s, c);
    for (let i = 0; i < 18; i++) { circle(ctx, r() * w, r() * h, 2 + r() * 5); stroke(ctx, 'rgba(255,255,255,0.7)', 1.5); }
  },
  desert(ctx, w, h) {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h * 0.7, ['#6B3A6E', '#E3662B', '#FFB36B', '#FFE3A3']);
    ctx.fillRect(0, 0, w, h);
    slicedSun(ctx, w * 0.3, h * 0.6, 60, '#FFF1A0', '#FF8A3A', '#FFB36B');
    mesas(ctx, w, h * 0.68, '#8A3A5A', 44);
    ctx.fillStyle = linear(ctx, 0, h * 0.7, 0, h, ['#E08A4A', '#B8582A']);
    ctx.fillRect(0, h * 0.72, w, h);
    cactus(ctx, w * 0.82, h, h * 0.6, '#2F6A3A', '#12301C');
    circle(ctx, w * 0.55, h * 0.88, 16);
    stroke(ctx, '#8A5A2A', 2);
    circle(ctx, w * 0.55, h * 0.88, 10);
    stroke(ctx, '#A8703A', 2);
  },
  moon(ctx, w, h) {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#05061A', '#141838']);
    ctx.fillRect(0, 0, w, h);
    starField(ctx, w, h, 140, 99, 0.7);
    circle(ctx, w * 0.75, h * 0.28, 34);
    fill(ctx, linear(ctx, 0, h * 0.2, 0, h * 0.4, ['#5FB0F0', '#2A6AC0']));
    ctx.save();
    circle(ctx, w * 0.75, h * 0.28, 34);
    ctx.clip();
    ctx.fillStyle = '#52D24A';
    ellipse(ctx, w * 0.73, h * 0.24, 14, 9, 0.4); ctx.fill();
    ellipse(ctx, w * 0.8, h * 0.34, 9, 7, 0); ctx.fill();
    ctx.restore();
    ctx.fillStyle = linear(ctx, 0, h * 0.62, 0, h, ['#D8D4E8', '#8A86A0']);
    ctx.beginPath();
    ctx.moveTo(0, h * 0.7);
    ctx.bezierCurveTo(w * 0.3, h * 0.6, w * 0.6, h * 0.72, w, h * 0.64);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.fill();
    const r = rng(23);
    for (let i = 0; i < 9; i++) { const x = r() * w, y = h * (0.75 + r() * 0.2), rx = 10 + r() * 24; ellipse(ctx, x, y, rx, rx * 0.3); fill(ctx, '#9A96B0'); ellipse(ctx, x + 2, y + 1, rx * 0.8, rx * 0.22); fill(ctx, '#B8B4CC'); }
    capsule(ctx, w * 0.28, h * 0.76, w * 0.28, h * 0.48, 3, '#E8E4F0');
    poly(ctx, [w * 0.28, h * 0.48, w * 0.28 + 44, h * 0.5, w * 0.28 + 40, h * 0.56, w * 0.28, h * 0.58]);
    fill(ctx, C.blue);
    badge13(ctx, w * 0.28 + 21, h * 0.53, 8, { ol: 1 });
  },
};
function fish(ctx, x, y, s, col) {
  poly(ctx, [x - s * 0.8, y, x - s * 1.3, y - s * 0.45, x - s * 1.3, y + s * 0.45]);
  inked(ctx, darken(col, 0.1), 2);
  ellipse(ctx, x, y, s, s * 0.6);
  inked(ctx, linear(ctx, 0, y - s * 0.6, 0, y + s * 0.6, [lighten(col, 0.3), col]), 2);
  circle(ctx, x + s * 0.45, y - s * 0.12, s * 0.16);
  fill(ctx, '#FFFFFF');
  circle(ctx, x + s * 0.5, y - s * 0.12, s * 0.08);
  fill(ctx, C.ink);
}
for (const [name, paint] of Object.entries(WORLDS)) {
  card(`world_${name}`, { w: 512, h: 288 }, (ctx, w, h) => {
    paint(ctx, w, h);
    vignette(ctx, w, h, 0.25, '20,12,36', 0.55);
  });
}

// ---------------------------------------------------------------------------------------------------------
// Posters (portrait 384x512): Duke Dalton wall-buy show posters and decor posters
// ---------------------------------------------------------------------------------------------------------

/** Printed-poster finish: paper grain, two faint fold creases and a white printed margin. */
function posterFinish(ctx, w, h, seed) {
  paper(ctx, w, h, seed, 0.12);
  ctx.fillStyle = 'rgba(255,255,255,0.08)';
  ctx.fillRect(w / 2 - 1.5, 0, 1.5, h);
  ctx.fillRect(0, h / 2 - 1.5, w, 1.5);
  ctx.fillStyle = 'rgba(60,30,40,0.08)';
  ctx.fillRect(w / 2, 0, 1.5, h);
  ctx.fillRect(0, h / 2, w, 1.5);
  const m = 9;
  ctx.strokeStyle = '#F6EEDC';
  ctx.lineWidth = m * 2;
  ctx.strokeRect(0, 0, w, h);
  ctx.strokeStyle = 'rgba(60,40,30,0.3)';
  ctx.lineWidth = 1;
  ctx.strokeRect(m + 0.5, m + 0.5, w - 2 * m - 1, h - 2 * m - 1);
}

/** Tune-in band at the foot of a show poster: station badge, air time and a small tag line. */
function tuneIn(ctx, w, h, when, band, ink, sub = 'ONLY ON WZTV CHANNEL 13') {
  const y = h - 86, bh = 68;
  ctx.fillStyle = linear(ctx, 0, y, 0, y + bh, [lighten(band, 0.1), band]);
  ctx.fillRect(0, y, w, h - y);
  ctx.fillStyle = 'rgba(255,255,255,0.22)';
  ctx.fillRect(0, y, w, 3);
  ctx.fillStyle = alpha(ink, 0.5);
  ctx.fillRect(0, y + 3, w, 2);
  badge13(ctx, 50, y + bh / 2, 24, { ol: 2 });
  label(ctx, when, w * 0.58, y + bh * 0.4, { fam: FONT.sign, px: 27, maxW: w * 0.64, fill: '#FFFFFF', stroke: ink, lw: 4 });
  label(ctx, sub, w * 0.58, y + bh * 0.78, { fam: FONT.round, px: 12.5, maxW: w * 0.64, fill: '#FFE9B0', track: 1 });
}

/** "starring DUKE DALTON" credit line. */
function starring(ctx, x, y, name, col, ink) {
  label(ctx, 'starring', x, y - 12, { fam: FONT.groovy, px: 15, fill: col, stroke: ink, lw: 3.5 });
  label(ctx, name, x, y + 7, { fam: FONT.sign, px: 19, fill: '#FFFFFF', stroke: ink, lw: 4.5, track: 2 });
}

/** Wall-buy mount: a jagged burst plate with two chrome clips, where the real prop gun hangs. */
function gunMount(ctx, cx, cy, rx, ry, col) {
  ctx.beginPath();
  for (let i = 0; i < 44; i++) {
    const a = (i / 44) * TAU, k = i & 1 ? 0.84 : 1;
    ctx.lineTo(cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k);
  }
  ctx.closePath();
  ctx.save();
  ctx.shadowColor = 'rgba(20,10,30,0.45)';
  ctx.shadowBlur = 10;
  ctx.shadowOffsetY = 4;
  fill(ctx, radial(ctx, cx, cy - ry * 0.3, ry * 0.2, rx, [lighten(col, 0.55), col, darken(col, 0.2)]));
  ctx.restore();
  stroke(ctx, C.ink, 3);
  for (const s of [-1, 1]) {
    const x = cx + s * rx * 0.42, y = cy - ry * 0.18;
    rr(ctx, x - 9, y - 16, 18, 32, 6);
    inked(ctx, linear(ctx, x - 9, 0, x + 9, 0, ['#8A90A8', '#FFFFFF', '#9AA2BC']), 2);
    circle(ctx, x, y - 8, 3);
    inked(ctx, '#C9CED8', 1.2);
  }
}

const WALL_POSTERS = {
  pump_37: {
    when: 'SUNDAYS 7PM', band: '#8A3A1E', ink: '#3A120A', burst: '#FFD23A', seed: 37, duke: { outfit: 'western', hat: 'cowboy' },
    bg(ctx, w, h) {
      desertScene(ctx, w, h, h * 0.62, 118);
      cactus(ctx, w * 0.08, h * 0.92, h * 0.34, '#2F6A3A', '#12301C');
      cactus(ctx, w * 0.94, h * 0.86, h * 0.25, '#2F6A3A', '#12301C');
    },
    title(ctx, w, h) {
      label(ctx, 'Dusty Trails', w / 2, h * 0.1, { fam: FONT.groovy, px: 62, maxW: w * 0.86, fill: vgrad(['#FFF3D0', '#F2C27A', '#D08A3A']), stroke: '#4A1E14', lw: 7, depth: 6, depthFill: '#7A2E1E', rot: -0.04 });
    },
  },
  mp7: {
    when: 'FRIDAYS 9PM', band: '#3A2A52', ink: '#0E0818', burst: '#FF7A4A', seed: 7, duke: { outfit: 'tux' },
    bg(ctx, w, h) { opSpiral(ctx, w, h, w / 2, h * 0.45); },
    title(ctx, w, h) {
      ctx.fillStyle = 'rgba(26,18,40,0.86)';
      ctx.fillRect(0, 0, w, h * 0.19);
      label(ctx, 'AGENT', w / 2, h * 0.06, { fam: FONT.sign, px: 22, fill: C.orange, track: 12 });
      label(ctx, 'THIRTEEN', w / 2, h * 0.135, { fam: FONT.sign, px: 50, maxW: w * 0.84, fill: vgrad(['#FFFFFF', '#F6E7C8']), stroke: C.red, lw: 5, track: 3 });
    },
  },
  m16a1: {
    when: 'TUESDAYS 8PM', band: '#4A5A22', ink: '#141A08', burst: '#F4E03A', seed: 16, duke: { outfit: 'camo', hat: 'headband' },
    bg(ctx, w, h) { jungle(ctx, w, h); },
    title(ctx, w, h) {
      const py = h * 0.04, ph = h * 0.12;
      rr(ctx, w * 0.07, py, w * 0.86, ph, 8);
      inked(ctx, linear(ctx, 0, py, 0, py + ph, ['#5A6A2E', '#3E4A1E']), 4, '#1E2410');
      for (const sx of [0.11, 0.89]) { circle(ctx, w * sx, py + ph / 2, 4); inked(ctx, '#C9CED8', 2, '#1E2410'); }
      stencil(ctx, 'COMMANDO CLUB', w / 2, py + ph * 0.54, 38, w * 0.7, '#F4E03A');
    },
  },
};
for (const [gun, P] of Object.entries(WALL_POSTERS)) {
  card(`poster_${gun}`, { w: 384, h: 512, opts: 'winked: true = Duke winks (after the gun is bought)' }, (ctx, w, h, t, o) => {
    const hx = w / 2, hy = h * 0.45, s = 56;
    P.bg(ctx, w, h);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    glowBlob(ctx, hx, hy, w * 0.5, '#FFE9C0', 0.3);
    ctx.restore();
    drawBust(ctx, 'duke', hx, hy, s, { ...P.duke, wink: !!o.winked });
    if (o.winked) { sparkle(ctx, hx + s * 0.62, hy - s * 0.18, 17); sparkle(ctx, hx + s * 0.95, hy - s * 0.5, 8, 0.8); }
    gunMount(ctx, w / 2, h * 0.73, w * 0.42, 46, P.burst);
    tuneIn(ctx, w, h, P.when, P.band, P.ink);
    P.title(ctx, w, h);
    starring(ctx, w / 2, h * 0.225, 'DUKE DALTON', '#FFE9B0', P.ink);
    posterFinish(ctx, w, h, P.seed);
  });
}

/** Cute cartoon bat. */
function bat(ctx, x, y, s, col) {
  ctx.fillStyle = col;
  for (const sx of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(x, y - s * 0.1);
    ctx.quadraticCurveTo(x + sx * s * 0.5, y - s * 0.44, x + sx * s, y - s * 0.22);
    ctx.quadraticCurveTo(x + sx * s * 0.86, y + s * 0.02, x + sx * s * 0.7, y + s * 0.07);
    ctx.quadraticCurveTo(x + sx * s * 0.58, y - s * 0.05, x + sx * s * 0.42, y + s * 0.09);
    ctx.quadraticCurveTo(x + sx * s * 0.3, y - s * 0.01, x, y + s * 0.2);
    ctx.fill();
    poly(ctx, [x + sx * s * 0.03, y - s * 0.12, x + sx * s * 0.13, y - s * 0.32, x + sx * s * 0.16, y - s * 0.08]);
    ctx.fill();
  }
  ellipse(ctx, x, y, s * 0.17, s * 0.21);
  ctx.fill();
  for (const sx of [-1, 1]) { circle(ctx, x + sx * s * 0.06, y - s * 0.04, s * 0.035); fill(ctx, '#FFE14A'); }
}

/** Telethon goal thermometer, filled to `frac`. */
function goalThermo(ctx, x, top, bottom, frac, wd) {
  rr(ctx, x - wd / 2, top, wd, bottom - top, wd / 2);
  inked(ctx, '#F4F1E8', 3);
  const fy = lerp(bottom, top + wd * 0.3, frac);
  rr(ctx, x - wd * 0.28, fy, wd * 0.56, bottom - fy, wd * 0.28);
  fill(ctx, linear(ctx, x - wd * 0.3, 0, x + wd * 0.3, 0, ['#FF6A5A', C.red, '#B01E28']));
  circle(ctx, x, bottom, wd * 0.9);
  inked(ctx, radial(ctx, x - wd * 0.3, bottom - wd * 0.3, 0, wd, ['#FF8A7A', C.red, '#A01A24']), 3);
  ctx.strokeStyle = C.ink;
  ctx.lineWidth = 2;
  ctx.beginPath();
  for (let i = 0; i <= 8; i++) {
    const yy = lerp(bottom - wd, top + wd * 0.5, i / 8);
    ctx.moveTo(x - wd / 2 - (i & 1 ? 5 : 9), yy);
    ctx.lineTo(x - wd / 2, yy);
  }
  ctx.stroke();
}

card('poster_spooktacular', { w: 384, h: 512 }, (ctx, w, h) => {
  ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#1B1E4A', '#3A1A5A', '#6B3A6E', '#C2407A', '#E3662B']);
  ctx.fillRect(0, 0, w, h);
  starField(ctx, w, h, 60, 13, 0.55);
  circle(ctx, w * 0.5, h * 0.5, 128);
  fill(ctx, radial(ctx, w * 0.45, h * 0.46, 10, 130, ['#FFFBEA', C.moon, '#F2D9A8']));
  for (const [x, y, r] of [[0.36, 0.42, 16], [0.62, 0.38, 10], [0.66, 0.56, 20], [0.4, 0.6, 9]]) { circle(ctx, w * x, h * y, r); fill(ctx, 'rgba(210,180,140,0.35)'); }
  for (const [x, y, s] of [[0.14, 0.34, 26], [0.86, 0.3, 30], [0.2, 0.62, 18], [0.8, 0.66, 22], [0.5, 0.29, 14]]) bat(ctx, w * x, h * y, s, '#2A1640');
  drawBust(ctx, 'baron', w / 2, h * 0.52, 52, { mood: 'grin', m: 0.55 });
  goalThermo(ctx, w * 0.88, h * 0.33, h * 0.72, 0.97, 18);
  label(ctx, '$13,000', w * 0.88, h * 0.3, { fam: FONT.sign, px: 15, fill: '#FFE14A', stroke: C.ink, lw: 3.5 });
  tuneIn(ctx, w, h, 'SAT 11AM – MIDNIGHT', '#5A1E5A', '#1E0A28', 'HOSTED BY BARON VON STATIC');
  label(ctx, '13-HOUR', w / 2, h * 0.066, { fam: FONT.sign, px: 24, fill: '#FFE14A', stroke: '#1E0A28', lw: 5, track: 6 });
  label(ctx, 'Spooktacular', w / 2, h * 0.145, { fam: FONT.groovy, px: 58, maxW: w * 0.9, fill: vgrad(['#FFE9A0', '#FFB347', '#E3662B']), stroke: '#1E0A28', lw: 7, depth: 6, depthFill: '#6B1A6E', rot: -0.04 });
  label(ctx, 'TELETHON', w / 2, h * 0.235, { fam: FONT.sign, px: 22, fill: '#FFFFFF', stroke: '#1E0A28', lw: 5, track: 9 });
  posterFinish(ctx, w, h, 29);
});

card('poster_hootie', { w: 384, h: 512 }, (ctx, w, h) => {
  ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#6EC8FF', '#BDEBFF', '#E8FAFF']);
  ctx.fillRect(0, 0, w, h);
  rays(ctx, w / 2, h * 0.62, h, 22, 'rgba(255,255,255,0.28)', 0.05);
  ['#FF6B6B', '#FFA94D', '#FFE066', '#69DB7C', '#4DABF7', '#9775FA'].forEach((c, i) => { ctx.beginPath(); ctx.arc(w / 2, h * 0.78, w * 0.62 - i * 18, Math.PI, 0); stroke(ctx, c, 19); });
  cloud(ctx, w * 0.16, h * 0.4, 110, 52, '#FFFFFF', 'rgba(90,140,200,0.5)', 2);
  cloud(ctx, w * 0.86, h * 0.47, 120, 56, '#FFFFFF', 'rgba(90,140,200,0.5)', 2);
  ctx.fillStyle = '#8FD06A';
  ctx.beginPath();
  ctx.moveTo(0, h * 0.74);
  ctx.bezierCurveTo(w * 0.3, h * 0.68, w * 0.6, h * 0.76, w, h * 0.7);
  ctx.lineTo(w, h);
  ctx.lineTo(0, h);
  ctx.fill();
  const r = rng(31);
  for (let i = 0; i < 12; i++) flower(ctx, r() * w, h * (0.75 + r() * 0.08), 6 + r() * 3, ['#FFFFFF', '#FFD23A', '#FF8AC8'][i % 3], '#FF8A2A');
  ellipse(ctx, w / 2, h * 0.79, 70, 11);
  fill(ctx, 'rgba(40,90,40,0.3)');
  drawHootie(ctx, w / 2, h * 0.6, 92, { wave: -0.9, blink: false });
  for (const [x, c, a] of [[0.08, '#FF4F5E', 0.3], [0.9, '#3FA9F5', -0.35]]) {
    ctx.save();
    ctx.translate(w * x, h * 0.74);
    ctx.rotate(a);
    rr(ctx, -9, -70, 18, 78, 3);
    inked(ctx, c, 2.5);
    poly(ctx, [-9, -70, 9, -70, 0, -92]);
    inked(ctx, '#F6E7C8', 2.5);
    poly(ctx, [-3, -85, 3, -85, 0, -92]);
    fill(ctx, c);
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.fillRect(-6, -64, 4, 66);
    ctx.restore();
  }
  tuneIn(ctx, w, h, 'WEEKDAYS 4PM', '#E0507A', '#5A1030', 'FUN FOR THE WHOLE FAMILY!');
  balloonText(ctx, "HOOTIE'S", w / 2, h * 0.12, 44, 0, 0, w * 0.62);
  balloonText(ctx, 'HULLABALOO', w / 2, h * 0.245, 52, 0, 2.3, w * 0.9);
  posterFinish(ctx, w, h, 41);
});

card('poster_precinct13', { w: 384, h: 512 }, (ctx, w, h) => {
  ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#141638', '#2A2F6B', '#6B3A6E']);
  ctx.fillRect(0, 0, w, h);
  starField(ctx, w, h, 40, 22, 0.4);
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  for (const [x, a] of [[0.2, -0.3], [0.8, 0.28]]) {
    ctx.save();
    ctx.translate(w * x, h * 0.85);
    ctx.rotate(a);
    poly(ctx, [-8, 0, 8, 0, 60, -h, -60, -h]);
    fill(ctx, linear(ctx, 0, 0, 0, -h, ['rgba(255,240,200,0.32)', 'rgba(255,240,200,0)']));
    ctx.restore();
  }
  glowBlob(ctx, 0, h * 0.62, w * 0.6, '#FF3B30', 0.55);
  glowBlob(ctx, w, h * 0.62, w * 0.6, '#3A7BFF', 0.6);
  ctx.restore();
  skyline(ctx, w, h * 0.8, 70, 170, '#2A2358', 15, 0.15, '#8A7AD8');
  skyline(ctx, w, h * 0.9, 50, 130, '#141030', 18, 0.35);
  drawBust(ctx, 'duke', w / 2, h * 0.47, 56, { outfit: 'leather' });
  tuneIn(ctx, w, h, 'THURSDAYS 9PM', '#23307A', '#0A0E30', 'THE TOUGHEST BEAT IN THE TRI-COUNTY');
  label(ctx, 'PRECINCT', w * 0.4, h * 0.1, { fam: FONT.sign, px: 52, maxW: w * 0.68, fill: vgrad(CHROME), stroke: '#141040', lw: 7, depth: 5, depthFill: '#5A2A8A', skew: -0.18 });
  shield(ctx, w * 0.85, h * 0.1, 34);
  starring(ctx, w / 2, h * 0.215, 'DUKE DALTON', '#FFB0A8', '#141040');
  posterFinish(ctx, w, h, 13);
});

card('poster_boogie_down', { w: 384, h: 512 }, (ctx, w, h) => {
  ctx.fillStyle = radial(ctx, w / 2, h * 0.45, 10, h * 0.7, ['#FFE3A3', '#FFB36B', '#E3462B', '#6B1A4A']);
  ctx.fillRect(0, 0, w, h);
  rays(ctx, w / 2, h * 0.45, h, 26, 'rgba(255,79,160,0.4)', 0.04);
  danceFloor(ctx, w, h, h * 0.7, ['#FF4FA0', '#FFC23A', '#5FE3FF', '#52E04A', '#FF8A2A'], 1);
  mirrorBall(ctx, w * 0.84, h * 0.3, 24);
  const r = rng(45);
  for (let i = 0; i < 14; i++) sparkle(ctx, r() * w, h * (0.25 + r() * 0.45), 3 + r() * 6, 0.9);
  drawBust(ctx, 'roxy', w / 2, h * 0.5, 46, {});
  tuneIn(ctx, w, h, 'SATURDAYS 7PM', '#6B1A4A', '#2A0A1E', 'GET DOWN WITH ROXY RIVERS!');
  label(ctx, 'Boogie Down', w / 2, h * 0.1, { fam: FONT.groovy, px: 56, maxW: w * 0.86, fill: vgrad(['#FFFFFF', '#FFE0F0', '#FF9AD0']), stroke: '#6A1A4A', lw: 7, depth: 5, depthFill: '#3A0E2A', rot: -0.05 });
  label(ctx, 'SATURDAY', w / 2, h * 0.2, { fam: FONT.sign, px: 26, fill: '#FFE14A', stroke: '#6A1A4A', lw: 5, track: 8, rot: -0.05 });
  posterFinish(ctx, w, h, 77);
});

// ---------------------------------------------------------------------------------------------------------
// Sponsors: wordless pictogram gag posters, starburst logo cards and neon signs (GDD §10.3, §11)
// ---------------------------------------------------------------------------------------------------------

const SPONSORS = {
  replay_ade: { name: 'Replay-Ade', sub: 'SPORTS DRINK', tag: 'GET BACK IN THE GAME!', main: '#F4C81E', second: '#2F5BD3', deep: '#1B2F7A', neon: '#FFD23A', neon2: '#3A7BFF' },
  wobble_up: { name: 'Wobble-Up', sub: 'GELATIN', tag: 'IT BOUNCES RIGHT BACK!', main: '#1FB45A', second: '#E23B3B', deep: '#0E4A26', neon: '#52E04A', neon2: '#FF5FA2' },
  jump_cut: { name: 'Jump Cut', sub: 'COFFEE', tag: 'SKIP THE WAITING!', main: '#E3662B', second: '#5A3A22', deep: '#4A1E0E', neon: '#FF8A2A', neon2: '#FFD23A' },
  roller_boogie: { name: 'Roller Boogie', sub: 'SKATE WAX', tag: "NEVER STOP ROLLIN'!", main: '#FF5FA2', second: '#6B3A6E', deep: '#3A1440', neon: '#FF5FA2', neon2: '#5FE3FF' },
  double_vision: { name: 'Double Vision', sub: 'TOOTHPASTE', tag: 'TWICE THE SMILE!', main: '#3FB8E8', second: '#E23B3B', deep: '#123A7A', neon: '#5FE3FF', neon2: '#FF4FA0' },
};

/** 70s starburst: alternating rays around (cx, cy) with a warm centre glow. */
function starburst(ctx, w, h, cx, cy, c1, c2, n = 22) {
  ctx.fillStyle = c1;
  ctx.fillRect(0, 0, w, h);
  rays(ctx, cx, cy, Math.hypot(w, h), n, c2, 0.08);
  ctx.fillStyle = radial(ctx, cx, cy, 0, Math.max(w, h) * 0.6, ['rgba(255,250,230,0.75)', 'rgba(255,250,230,0.15)', 'rgba(255,250,230,0)']);
  ctx.fillRect(0, 0, w, h);
}

/** Banner ribbon with folded tails. */
function ribbon(ctx, cx, cy, w, h, col) {
  for (const s of [-1, 1]) {
    const x0 = cx + s * (w / 2 - h * 0.3), x1 = cx + s * (w / 2 + h * 0.85);
    poly(ctx, [x0, cy - h * 0.25, x1, cy - h * 0.25, x1 - s * h * 0.35, cy + h * 0.28, x1, cy + h * 0.8, x0, cy + h * 0.8]);
    inked(ctx, darken(col, 0.3), 3);
  }
  rr(ctx, cx - w / 2, cy - h / 2, w, h, 4);
  inked(ctx, linear(ctx, 0, cy - h / 2, 0, cy + h / 2, [lighten(col, 0.15), col]), 3);
  ctx.fillStyle = 'rgba(255,255,255,0.18)';
  ctx.fillRect(cx - w / 2 + 4, cy - h / 2 + 3, w - 8, h * 0.25);
}

function fist(ctx, x, y, u, thumb = false) {
  if (thumb) capsule(ctx, x, y, x + u * 0.1, y - u * 1.15, u * 0.55, C.ink);
  circle(ctx, x, y, u * 0.62);
  fill(ctx, C.ink);
}
function heart(ctx, x, y, s, col, lw) {
  ctx.beginPath();
  ctx.moveTo(x, y + s * 0.38);
  ctx.bezierCurveTo(x - s * 0.95, y - s * 0.22, x - s * 0.38, y - s * 0.88, x, y - s * 0.36);
  ctx.bezierCurveTo(x + s * 0.38, y - s * 0.88, x + s * 0.95, y - s * 0.22, x, y + s * 0.38);
  inked(ctx, col, lw);
}
function bananaPeel(ctx, x, y, s) {
  for (const a of [-2.5, -0.65, -1.55]) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(a + Math.PI / 2);
    ellipse(ctx, 0, -s * 0.45, s * 0.2, s * 0.5);
    inked(ctx, '#FFE14A', s * 0.08);
    ctx.restore();
  }
  ellipse(ctx, x, y, s * 0.32, s * 0.2);
  inked(ctx, '#F4C81E', s * 0.08);
  capsule(ctx, x, y - s * 0.1, x + s * 0.1, y - s * 0.5, s * 0.1, '#8A6A2A');
}
/** Quick speed/motion strokes. */
function motionLines(ctx, x, y, len, n, gap, col, lw) {
  ctx.save();
  ctx.lineCap = 'round';
  ctx.strokeStyle = col;
  ctx.lineWidth = lw;
  ctx.beginPath();
  for (let i = 0; i < n; i++) { const yy = y + (i - (n - 1) / 2) * gap, l = len * (i % 2 ? 0.7 : 1); ctx.moveTo(x, yy); ctx.lineTo(x + l, yy); }
  ctx.stroke();
  ctx.restore();
}
function impactStar(ctx, x, y, r, col) {
  starPath(ctx, x, y, r, r * 0.5, 8, 0.2);
  inked(ctx, col, r * 0.1);
}
function rewindIcon(ctx, x, y, s, col) {
  for (const k of [0, 1]) {
    poly(ctx, [x + s * (0.1 - k * 0.55), y - s * 0.32, x + s * (0.1 - k * 0.55), y + s * 0.32, x - s * (0.38 + k * 0.55), y]);
    inked(ctx, col, s * 0.07);
  }
}
/** Roller wheels under a pictogram foot. */
function skateFoot(ctx, x, y, u) {
  rr(ctx, x - u * 0.9, y - u * 0.3, u * 1.8, u * 0.55, u * 0.2);
  fill(ctx, C.ink);
  for (const k of [-0.5, 0.5]) { circle(ctx, x + k * u, y + u * 0.45, u * 0.38); inked(ctx, '#FF5FA2', u * 0.15); }
}
function toothbrush(ctx, x, y, len, rot) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot);
  rr(ctx, -len * 0.06, -len * 0.5, len * 0.12, len, len * 0.06);
  inked(ctx, '#F4F1E8', len * 0.03);
  ctx.save();
  ctx.clip();
  [C.red, C.blue, C.red].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(-len, -len * 0.2 + i * len * 0.22, len * 2, len * 0.1); });
  ctx.restore();
  rr(ctx, -len * 0.08, -len * 0.62, len * 0.2, len * 0.16, len * 0.03);
  inked(ctx, '#FFFFFF', len * 0.025);
  ctx.restore();
}
function stopwatch(ctx, x, y, r, frac, col) {
  rr(ctx, x - r * 0.18, y - r * 1.35, r * 0.36, r * 0.3, r * 0.06);
  inked(ctx, '#C9CED8', r * 0.08);
  circle(ctx, x, y, r);
  inked(ctx, '#C9CED8', r * 0.1);
  circle(ctx, x, y, r * 0.8);
  fill(ctx, '#FFFDF2');
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.arc(x, y, r * 0.8, -Math.PI / 2, -Math.PI / 2 + frac * TAU);
  ctx.closePath();
  fill(ctx, col);
  ctx.strokeStyle = C.ink;
  ctx.lineWidth = r * 0.06;
  ctx.beginPath();
  for (let i = 0; i < 12; i++) { const a = (i / 12) * TAU; ctx.moveTo(x + Math.cos(a) * r * 0.66, y + Math.sin(a) * r * 0.66); ctx.lineTo(x + Math.cos(a) * r * 0.78, y + Math.sin(a) * r * 0.78); }
  ctx.stroke();
  capsule(ctx, x, y, x, y - r * 0.62, r * 0.1, C.ink);
  circle(ctx, x, y, r * 0.1);
  fill(ctx, C.ink);
}
/** Film-strip sprocket edges for the jump-cut panels. */
function sprockets(ctx, x, y, w, h) {
  ctx.fillStyle = '#2A1D3A';
  ctx.fillRect(x, y, 14, h);
  ctx.fillRect(x + w - 14, y, 14, h);
  ctx.fillStyle = '#FFF8E8';
  for (let yy = y + 6; yy < y + h - 8; yy += 18) { rr(ctx, x + 3, yy, 8, 10, 2); ctx.fill(); rr(ctx, x + w - 11, yy, 8, 10, 2); ctx.fill(); }
}

/** The four wordless gag panels per sponsor: fn(ctx, cx, cy, pw, ph, S). */
const GAGS = {
  replay_ade: [
    (ctx, cx, cy, pw, ph) => {
      const s = ph * 0.64, j = picto(ctx, cx - pw * 0.06, cy + ph * 0.08, s, { head: [-0.3, 0.1], la: [-18, -8], ra: [58, -150] }, C.ink);
      ctx.save();
      ctx.translate(j.handR[0] + j.u * 0.9, j.handR[1] - j.u * 0.6);
      ctx.rotate(-1.95);
      PRODUCTS.replay_ade(ctx, 0, 0, s * 0.36);
      ctx.restore();
      for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(j.head[0] - j.u * 2.2, j.head[1] - j.u * 0.4, j.u * (0.8 + i * 0.7), 2.4, 3.9); stroke(ctx, C.ink, 2); }
    },
    (ctx, cx, cy, pw, ph) => {
      const s = ph * 0.58;
      ctx.save();
      ctx.translate(cx - pw * 0.06, cy - ph * 0.02);
      ctx.rotate(-1.15);
      picto(ctx, 0, 0, s, { la: [-150, -178], ra: [150, 176], ll: [42, 70], rl: [-12, 14] }, C.ink);
      ctx.restore();
      bananaPeel(ctx, cx + pw * 0.2, cy + ph * 0.36, ph * 0.13);
      ctx.beginPath();
      ctx.arc(cx, cy + ph * 0.1, ph * 0.3, -2.9, -1.4);
      stroke(ctx, alpha(C.ink, 0.5), 2.5);
      for (const [x, y, r] of [[0.28, -0.3, 9], [0.36, -0.14, 6], [-0.3, -0.34, 7]]) { starPath(ctx, cx + pw * x, cy + ph * y, r, r * 0.45, 5); inked(ctx, '#FFE14A', 1.5); }
      ctx.fillStyle = alpha(C.ink, 0.25);
      ctx.fillRect(cx - pw * 0.45, cy + ph * 0.42, pw * 0.9, 3);
    },
    (ctx, cx, cy, pw, ph) => {
      ctx.fillStyle = linear(ctx, 0, cy - ph / 2, 0, cy + ph / 2, ['#2A3A9A', '#1B2766']);
      ctx.fillRect(cx - pw / 2, cy - ph / 2, pw, ph);
      const r = rng(5);
      for (let i = 0; i < 7; i++) { ctx.fillStyle = `rgba(255,255,255,${0.12 + r() * 0.25})`; ctx.fillRect(cx - pw / 2, cy - ph / 2 + r() * ph, pw, 2 + r() * 4); }
      const s = ph * 0.52;
      [[0.24, -1.2, 0.25], [0.04, -0.6, 0.45], [-0.18, 0, 1]].forEach(([dx, rot, a]) => {
        ctx.save();
        ctx.globalAlpha = a;
        ctx.translate(cx + pw * dx, cy + ph * (0.12 - Math.abs(rot) * 0.1));
        ctx.rotate(rot);
        picto(ctx, 0, 0, s, { la: [-120, -150], ra: [120, 150] }, '#DFF4FF');
        ctx.restore();
      });
      rewindIcon(ctx, cx + pw * 0.2, cy - ph * 0.26, ph * 0.24, '#FFE14A');
    },
    (ctx, cx, cy, pw, ph, S) => {
      ctx.save();
      rays(ctx, cx, cy - ph * 0.05, pw, 16, alpha(S.main, 0.35), 0.1);
      ctx.restore();
      const j = picto(ctx, cx, cy + ph * 0.08, ph * 0.64, { la: [-28, -18], ra: [48, 172] }, C.ink);
      fist(ctx, j.handR[0], j.handR[1], j.u, true);
      for (const [e, hnd] of [[j.elbowR, j.handR], [j.elbowL, j.handL]]) {
        const mx = lerp(e[0], hnd[0], 0.7), my = lerp(e[1], hnd[1], 0.7);
        circle(ctx, mx, my, j.u * 0.55);
        inked(ctx, S.main, 2, S.second);
      }
      sparkle(ctx, cx + pw * 0.3, cy - ph * 0.3, 11);
      sparkle(ctx, cx - pw * 0.28, cy - ph * 0.12, 7);
      ctx.fillStyle = alpha(C.ink, 0.25);
      ctx.fillRect(cx - pw * 0.42, cy + ph * 0.45, pw * 0.84, 3);
    },
  ],
  wobble_up: [
    (ctx, cx, cy, pw, ph) => {
      const s = ph * 0.64, j = picto(ctx, cx + pw * 0.04, cy + ph * 0.08, s, { head: [0.1, 0], la: [-55, 45], ra: [58, -152] }, C.ink);
      PRODUCTS.wobble_up(ctx, j.handL[0] - j.u * 0.4, j.handL[1] - s * 0.12, s * 0.3);
      capsule(ctx, j.handR[0], j.handR[1], j.head[0] + j.u * 0.9, j.head[1] + j.u * 0.8, j.u * 0.35, '#C9CED8', C.ink, 1.5);
      circle(ctx, j.head[0] + j.u * 1.0, j.head[1] + j.u * 0.8, j.u * 0.45);
      inked(ctx, '#3FD27A', 1.5);
    },
    (ctx, cx, cy, pw, ph) => {
      const hipX = cx + pw * 0.16, s = ph * 0.62;
      const j = picto(ctx, hipX, cy + ph * 0.08, s, { lean: 18, la: [-130, -160], ra: [150, 170], head: [0.4, 0] }, C.ink);
      const gx = j.neck[0] - j.u * 1.2, gy = j.neck[1] + j.u * 0.8, x0 = cx - pw / 2;
      ctx.beginPath();
      ctx.moveTo(x0, gy);
      for (let i = 1; i < 9; i++) ctx.lineTo(lerp(x0, gx - j.u * 1.6, i / 9), gy + (i & 1 ? -j.u : j.u));
      ctx.lineTo(gx - j.u * 1.6, gy);
      stroke(ctx, '#8A90A8', 3);
      ellipse(ctx, gx - j.u * 0.6, gy, j.u * 1.3, j.u * 1.1);
      inked(ctx, C.red, 2.5);
      ellipse(ctx, gx - j.u * 0.4, gy - j.u * 0.9, j.u * 0.5, j.u * 0.35, 0.4);
      inked(ctx, C.red, 2);
      rr(ctx, gx - j.u * 2.1, gy - j.u * 0.8, j.u * 0.6, j.u * 1.6, j.u * 0.2);
      inked(ctx, '#F4F1E8', 2);
      impactStar(ctx, gx + j.u * 0.8, gy - j.u * 0.4, j.u * 1.6, '#FFE14A');
    },
    (ctx, cx, cy, pw, ph, S) => {
      const s = ph * 0.64, hy = cy + ph * 0.08;
      for (const [dx, a] of [[-5, 0.35], [5, 0.35]]) { ctx.save(); ctx.globalAlpha = a; picto(ctx, cx + dx, hy, s, { la: [-40, -10], ra: [40, 10], lean: dx * 0.8 }, '#3FD27A'); ctx.restore(); }
      const j = picto(ctx, cx, hy, s, { la: [-40, -10], ra: [40, 10] }, '#0E7A3A');
      ctx.save();
      ctx.translate(j.head[0], j.head[1] - j.u * 0.4);
      ctx.scale(1.1, 1);
      PRODUCTS.wobble_up(ctx, 0, 0, j.u * 3.2, 0.12);
      ctx.restore();
      ctx.lineCap = 'round';
      for (const sd of [-1, 1]) for (let k = 0; k < 3; k++) {
        ctx.beginPath();
        ctx.arc(cx, hy - j.u * 2, j.u * (3.5 + k * 1.2), sd > 0 ? -0.5 : Math.PI - 0.5, sd > 0 ? 0.5 : Math.PI + 0.5);
        stroke(ctx, alpha(S.main, 0.8 - k * 0.2), 2.5);
      }
    },
    (ctx, cx, cy, pw, ph, S) => {
      const j = picto(ctx, cx - pw * 0.12, cy + ph * 0.1, ph * 0.6, { la: [-28, -18], ra: [48, 172] }, C.ink);
      fist(ctx, j.handR[0], j.handR[1], j.u, true);
      PRODUCTS.wobble_up(ctx, j.head[0], j.head[1] - j.u * 0.6, j.u * 3.0, 0);
      heart(ctx, cx + pw * 0.22, cy - ph * 0.28, ph * 0.12, S.second, 2.5);
      ctx.beginPath();
      ctx.moveTo(cx + pw * 0.22, cy - ph * 0.16);
      ctx.lineTo(cx + pw * 0.22, cy - ph * 0.05);
      stroke(ctx, C.ink, 3);
      poly(ctx, [cx + pw * 0.22 - 6, cy - ph * 0.07, cx + pw * 0.22 + 6, cy - ph * 0.07, cx + pw * 0.22, cy]);
      fill(ctx, C.ink);
      heart(ctx, cx + pw * 0.15, cy + ph * 0.12, ph * 0.13, S.second, 2.5);
      heart(ctx, cx + pw * 0.3, cy + ph * 0.12, ph * 0.13, S.second, 2.5);
    },
  ],
  jump_cut: [
    (ctx, cx, cy, pw, ph) => {
      const s = ph * 0.64, j = picto(ctx, cx - pw * 0.08, cy + ph * 0.08, s, { head: [-0.2, 0], la: [-18, -8], ra: [58, -150] }, C.ink);
      PRODUCTS.jump_cut(ctx, j.handR[0] + j.u * 1.2, j.handR[1] + j.u * 0.2, s * 0.34);
    },
    (ctx, cx, cy, pw, ph) => {
      sprockets(ctx, cx - pw / 2, cy - ph / 2, pw, ph);
      picto(ctx, cx, cy + ph * 0.08, ph * 0.62, { la: [-28, 100], ra: [28, -100] }, C.ink);
      ctx.save();
      ctx.setLineDash([6, 5]);
      ctx.beginPath();
      ctx.moveTo(cx - pw * 0.4, cy + ph * 0.32);
      ctx.lineTo(cx + pw * 0.4, cy - ph * 0.3);
      stroke(ctx, '#FF3B30', 3);
      ctx.restore();
      ctx.save();
      ctx.translate(cx + pw * 0.3, cy - ph * 0.32);
      ctx.rotate(-0.6);
      for (const s of [-1, 1]) {
        capsule(ctx, 0, 0, s * 10, -18, 4, '#C9CED8', C.ink, 1.5);
        circle(ctx, s * 6, 8, 6);
        stroke(ctx, C.ink, 3);
      }
      ctx.restore();
    },
    (ctx, cx, cy, pw, ph) => {
      sprockets(ctx, cx - pw / 2, cy - ph / 2, pw, ph);
      const j = picto(ctx, cx - pw * 0.1, cy + ph * 0.08, ph * 0.62, { la: [55, 88], ra: [70, 92] }, C.ink);
      for (const hnd of [j.handL, j.handR]) capsule(ctx, hnd[0], hnd[1], hnd[0] + j.u * 1.2, hnd[1], j.u * 0.4, C.ink);
      boltPath(ctx, cx + pw * 0.28, cy - ph * 0.22, ph * 0.26);
      inked(ctx, '#FFD23A', 2.5);
      motionLines(ctx, cx + pw * 0.18, cy - ph * 0.02, pw * 0.2, 3, 7, alpha(C.ink, 0.6), 2);
    },
    (ctx, cx, cy, pw, ph, S) => {
      stopwatch(ctx, cx - pw * 0.08, cy + ph * 0.06, ph * 0.28, 0.5, S.main);
      boltPath(ctx, cx + pw * 0.28, cy - ph * 0.12, ph * 0.32);
      inked(ctx, '#FFD23A', 2.5);
      for (const k of [-1, 1]) motionLines(ctx, cx - pw * 0.44, cy + k * ph * 0.1, pw * 0.08, 2, 6, alpha(C.ink, 0.5), 2);
    },
  ],
  roller_boogie: [
    (ctx, cx, cy, pw, ph, S) => {
      const s = ph * 0.64, j = picto(ctx, cx, cy + ph * 0.08, s, { la: [-60, 40], ra: [60, -40] }, C.ink);
      PRODUCTS.roller_boogie(ctx, j.handL[0] - j.u * 0.2, j.handL[1] - j.u * 0.6, s * 0.36);
      rr(ctx, j.handR[0] - j.u * 0.8, j.handR[1] - j.u * 1.4, j.u * 1.6, j.u * 1.2, j.u * 0.3);
      inked(ctx, S.main, 2);
      sparkle(ctx, j.handL[0] - j.u * 1.8, j.handL[1] - j.u * 2.2, 9);
      sparkle(ctx, j.handL[0] + j.u * 1.4, j.handL[1] - j.u * 2.6, 6);
    },
    (ctx, cx, cy, pw, ph) => {
      const j = picto(ctx, cx - pw * 0.36, cy + ph * 0.08, ph * 0.62, { lean: -28, la: [40, -30], ra: [-70, -40], ll: [-60, -10], rl: [40, 90] }, C.ink);
      skateFoot(ctx, j.footL[0], j.footL[1], j.u);
      skateFoot(ctx, j.footR[0], j.footR[1], j.u);
      motionLines(ctx, cx - pw * 0.12, cy - ph * 0.05, pw * 0.5, 5, 12, alpha(C.ink, 0.7), 3);
      for (const [x, y, r] of [[0.26, 0.38, 12], [0.38, 0.34, 8], [0.16, 0.42, 7]]) { cloud(ctx, cx + pw * x, cy + ph * y, r * 2.4, r * 1.4, '#EDE4D0', alpha(C.ink, 0.5), 1); }
    },
    (ctx, cx, cy, pw, ph, S) => {
      ctx.beginPath();
      for (let i = 0; i <= 60; i++) { const a = i * 0.2, rr0 = ph * 0.05 + i * ph * 0.006; ctx.lineTo(cx + Math.cos(a) * rr0 * 1.3, cy + Math.sin(a) * rr0 * 0.5 + ph * 0.3); }
      stroke(ctx, alpha(S.neon2, 0.8), 3);
      const r = rng(8);
      for (let i = 0; i < 7; i++) sparkle(ctx, cx + (r() - 0.5) * pw * 0.8, cy + ph * (0.1 + r() * 0.3), 4 + r() * 5);
      const j = picto(ctx, cx, cy + ph * 0.02, ph * 0.6, { la: [-100, -95], ra: [100, 95], ll: [-4, 0], rl: [70, 110] }, C.ink);
      skateFoot(ctx, j.footL[0], j.footL[1], j.u);
      skateFoot(ctx, j.footR[0], j.footR[1], j.u);
    },
    (ctx, cx, cy, pw, ph, S) => {
      mirrorBall(ctx, cx + pw * 0.3, cy - ph * 0.3, ph * 0.1);
      ctx.save();
      ctx.globalCompositeOperation = 'multiply';
      rays(ctx, cx + pw * 0.3, cy - ph * 0.3, pw, 12, alpha(S.main, 0.25), 0.3);
      ctx.restore();
      const j = picto(ctx, cx - pw * 0.08, cy + ph * 0.06, ph * 0.6, { la: [-30, 50], ra: [158, 172], ll: [-14, -6], rl: [14, 6] }, C.ink);
      capsule(ctx, j.handR[0], j.handR[1], j.handR[0] + j.u * 0.3, j.handR[1] - j.u * 1.1, j.u * 0.4, C.ink);
      skateFoot(ctx, j.footL[0], j.footL[1], j.u);
      skateFoot(ctx, j.footR[0], j.footR[1], j.u);
      ctx.save();
      ctx.translate(cx - pw * 0.33, cy - ph * 0.04);
      ctx.beginPath();
      for (let i = 0; i <= 40; i++) { const a = (i / 40) * TAU; ctx.lineTo(Math.sin(a) * 18, Math.sin(a * 2) * 8); }
      stroke(ctx, C.ink, 7);
      stroke(ctx, S.main, 3.5);
      ctx.restore();
    },
  ],
  double_vision: [
    (ctx, cx, cy, pw, ph) => {
      const s = ph * 0.64, j = picto(ctx, cx - pw * 0.04, cy + ph * 0.08, s, { la: [-18, -8], ra: [60, -130] }, C.ink);
      toothbrush(ctx, j.handR[0] - j.u * 0.4, j.handR[1] - j.u * 0.3, s * 0.3, -1.1);
      for (const [x, y, r] of [[-1.6, -0.2, 0.5], [-1.9, 0.6, 0.35], [-1.2, 0.9, 0.3]]) { circle(ctx, j.head[0] + x * j.u, j.head[1] + y * j.u, r * j.u); inked(ctx, '#FFFFFF', 1.5); }
    },
    (ctx, cx, cy, pw, ph) => {
      const r = ph * 0.3, hx = cx - pw * 0.04, hy = cy + ph * 0.02;
      circle(ctx, hx, hy, r);
      fill(ctx, C.ink);
      ctx.beginPath();
      ctx.moveTo(hx - r * 0.62, hy + r * 0.08);
      ctx.quadraticCurveTo(hx, hy + r * 0.3, hx + r * 0.62, hy + r * 0.08);
      ctx.quadraticCurveTo(hx + r * 0.5, hy + r * 0.7, hx, hy + r * 0.72);
      ctx.quadraticCurveTo(hx - r * 0.5, hy + r * 0.7, hx - r * 0.62, hy + r * 0.08);
      fill(ctx, '#FFFFFF');
      ctx.strokeStyle = C.ink;
      ctx.lineWidth = 2;
      ctx.beginPath();
      for (const k of [-0.3, 0, 0.3]) { ctx.moveTo(hx + k * r, hy + r * 0.2); ctx.lineTo(hx + k * r, hy + r * 0.66); }
      ctx.stroke();
      for (const s of [-1, 1]) { ctx.beginPath(); ctx.arc(hx + s * r * 0.36, hy - r * 0.2, r * 0.16, Math.PI * 1.1, Math.PI * 1.9); stroke(ctx, '#FFFFFF', 4); }
      sparkle(ctx, hx + r * 0.35, hy + r * 0.35, r * 0.5);
      ctx.lineCap = 'round';
      for (const a of [-0.9, -0.4, 0.1]) { ctx.beginPath(); ctx.moveTo(hx + r * 0.9 + Math.cos(a) * r * 0.2, hy + r * 0.3 + Math.sin(a) * r * 0.2); ctx.lineTo(hx + r * 0.9 + Math.cos(a) * r * 0.55, hy + r * 0.3 + Math.sin(a) * r * 0.55); stroke(ctx, C.ink, 3); }
    },
    (ctx, cx, cy, pw, ph) => {
      ctx.save();
      ctx.globalCompositeOperation = 'multiply';
      picto(ctx, cx - pw * 0.13, cy + ph * 0.08, ph * 0.62, { la: [-150, -170], ra: [40, 20] }, '#3FD6E0');
      picto(ctx, cx + pw * 0.13, cy + ph * 0.08, ph * 0.62, { la: [-40, -20], ra: [150, 170] }, '#D64FD6');
      ctx.restore();
      for (const s of [-1, 1]) {
        ctx.beginPath();
        ctx.moveTo(cx + s * pw * 0.06, cy - ph * 0.4);
        ctx.lineTo(cx + s * pw * 0.2, cy - ph * 0.4);
        stroke(ctx, C.ink, 2.5);
        poly(ctx, [cx + s * pw * 0.24, cy - ph * 0.4, cx + s * pw * 0.19, cy - ph * 0.44, cx + s * pw * 0.19, cy - ph * 0.36]);
        fill(ctx, C.ink);
      }
    },
    (ctx, cx, cy, pw, ph) => {
      const j = picto(ctx, cx - pw * 0.28, cy + ph * 0.08, ph * 0.6, { la: [62, 86], ra: [78, 90] }, C.ink);
      rr(ctx, j.handR[0] - 2, j.handR[1] - 7, j.u * 2.2, j.u * 1.0, 3);
      fill(ctx, '#3A4A6B');
      const gx = j.handR[0] + j.u * 2.2, gy = j.handR[1] - 3, tx = cx + pw * 0.34;
      capsule(ctx, gx, gy, tx - 14, gy, 3.5, '#FFD23A');
      ctx.save();
      ctx.globalCompositeOperation = 'multiply';
      capsule(ctx, gx, gy + 9, tx - 14, gy + 9, 3.5, alpha('#3FD6E0', 0.9));
      capsule(ctx, gx, gy + 12, tx - 14, gy + 12, 3.5, alpha('#D64FD6', 0.7));
      ctx.restore();
      circle(ctx, tx, gy, ph * 0.12);
      inked(ctx, '#A9C7A4', 2.5);
      for (const s of [-1, 1]) {
        ctx.beginPath();
        ctx.moveTo(tx + s * 8 - 4, gy - 8); ctx.lineTo(tx + s * 8 + 4, gy - 2);
        ctx.moveTo(tx + s * 8 + 4, gy - 8); ctx.lineTo(tx + s * 8 - 4, gy - 2);
        stroke(ctx, C.ink, 2);
      }
      impactStar(ctx, tx - ph * 0.12, gy + 6, 10, '#FFE14A');
    },
  ],
};

/** Comic panel frame for the gag posters. */
function gagPanel(ctx, x, y, w, h, n, S, draw) {
  ctx.save();
  rr(ctx, x, y, w, h, 10);
  fill(ctx, '#FFF8E8');
  ctx.clip();
  halftone(ctx, x, y, w, h, alpha(S.main, 0.2), 10, (u, v) => 0.15 + 0.45 * v);
  ctx.lineJoin = 'round';
  draw(ctx, x + w / 2, y + h / 2, w, h, S);
  ctx.restore();
  rr(ctx, x, y, w, h, 10);
  stroke(ctx, C.ink, 4);
  circle(ctx, x + 17, y + 17, 12);
  inked(ctx, S.main, 2.5);
  label(ctx, String(n), x + 17, y + 18, { fam: FONT.round, px: 15, fill: '#FFFFFF', stroke: C.ink, lw: 3 });
}

for (const id of PERK_IDS) {
  const S = SPONSORS[id];
  card(`sponsor_poster_${id}`, { w: 384, h: 512 }, (ctx, w, h) => {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, [lighten(S.main, 0.25), S.main]);
    ctx.fillRect(0, 0, w, h);
    const hh = 118;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, w, hh);
    ctx.clip();
    starburst(ctx, w, hh, w / 2, hh * 0.6, lighten(S.main, 0.2), lighten(S.main, 0.45), 18);
    ctx.restore();
    PRODUCTS[id](ctx, w / 2, hh * 0.56, hh * 0.78);
    sparkle(ctx, w * 0.3, hh * 0.3, 12);
    sparkle(ctx, w * 0.72, hh * 0.62, 9);
    ctx.fillStyle = S.deep;
    ctx.fillRect(0, hh - 4, w, 6);
    const m = 20, gap = 12, pw = (w - m * 2 - gap) / 2, ph = (h - hh - m - gap - 10) / 2;
    GAGS[id].forEach((fn, i) => gagPanel(ctx, m + (i % 2) * (pw + gap), hh + 10 + Math.floor(i / 2) * (ph + gap), pw, ph, i + 1, S, fn));
    posterFinish(ctx, w, h, hash(id) & 255);
  });
}

function wordmark(ctx, S, x, y, px, maxW, rot = -0.06) {
  const words = S.name.split(' ');
  const lpx = words.length > 1 ? px * 0.82 : px;
  words.forEach((word, i) => {
    label(ctx, word, x, y + (i - (words.length - 1) / 2) * lpx * 0.92, {
      fam: FONT.groovy, px: lpx, maxW, fill: vgrad(['#FFFFFF', lighten(S.main, 0.7), lighten(S.main, 0.45)]),
      stroke: S.deep, lw: lpx * 0.11, depth: Math.round(lpx * 0.1), depthFill: S.deep, rot,
    });
  });
}

for (const id of PERK_IDS) {
  const S = SPONSORS[id];
  card(`sponsor_logo_${id}`, { w: 512, h: 384 }, (ctx, w, h) => {
    starburst(ctx, w, h, w * 0.28, h * 0.5, S.main, lighten(S.main, 0.3), 24);
    circle(ctx, w * 0.27, h * 0.48, h * 0.33);
    fill(ctx, radial(ctx, w * 0.27, h * 0.48, 0, h * 0.33, ['rgba(255,255,255,0.9)', 'rgba(255,255,255,0.5)', 'rgba(255,255,255,0)']));
    PRODUCTS[id](ctx, w * 0.27, h * 0.48, h * 0.56, 0.1);
    wordmark(ctx, S, w * 0.66, h * 0.36, 74, w * 0.56);
    label(ctx, S.sub, w * 0.7, h * 0.63, { fam: FONT.sign, px: 26, maxW: w * 0.5, fill: S.deep, stroke: '#FFFFFF', lw: 6, track: 4, rot: -0.06 });
    ribbon(ctx, w / 2, h * 0.86, w * 0.7, h * 0.12, S.second === '#5A3A22' ? S.deep : S.second);
    label(ctx, S.tag, w / 2, h * 0.865, { fam: FONT.sign, px: 22, maxW: w * 0.64, fill: '#FFFFFF', stroke: darken(S.second, 0.4), lw: 3, track: 1 });
    for (const [x, y, r] of [[0.08, 0.12, 12], [0.92, 0.14, 16], [0.5, 0.08, 8], [0.95, 0.6, 9]]) sparkle(ctx, w * x, h * y, r);
    vignette(ctx, w, h, 0.25, '40,20,40', 0.55);
  });
}

/** Neon-tube lettering: coloured glass tube with a hot white core; dim when unlit. */
function neonText(ctx, str, x, y, px, fam, col, lit, maxW) {
  ctx.save();
  const size = maxW ? fitFont(ctx, str, fam, px, maxW) : (setFont(ctx, px, fam), px);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineJoin = 'round';
  ctx.lineWidth = size * 0.11;
  ctx.strokeStyle = lit ? col : darken(col, 0.55);
  if (lit) { ctx.shadowColor = col; ctx.shadowBlur = size * 0.5; ctx.strokeText(str, x, y); }
  ctx.strokeText(str, x, y);
  ctx.shadowBlur = 0;
  ctx.lineWidth = size * 0.04;
  ctx.strokeStyle = lit ? lighten(col, 0.8) : darken(col, 0.35);
  ctx.strokeText(str, x, y);
  ctx.restore();
}
/** Neon tube along an arbitrary path built by `build()`. */
function neonPath(ctx, build, col, lw, lit) {
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.lineWidth = lw;
  ctx.strokeStyle = lit ? col : darken(col, 0.55);
  if (lit) { ctx.shadowColor = col; ctx.shadowBlur = lw * 4; build(); ctx.stroke(); }
  build();
  ctx.stroke();
  ctx.shadowBlur = 0;
  ctx.lineWidth = lw * 0.36;
  ctx.strokeStyle = lit ? lighten(col, 0.8) : darken(col, 0.35);
  build();
  ctx.stroke();
  ctx.restore();
}
const NEON_ICONS = {
  replay_ade: (ctx, x, y, s) => {
    ctx.beginPath();
    for (const k of [0, 1]) { const ox = x + s * (0.42 - k * 0.5); ctx.moveTo(ox, y - s * 0.3); ctx.lineTo(ox - s * 0.42, y); ctx.lineTo(ox, y + s * 0.3); ctx.closePath(); }
  },
  wobble_up: (ctx, x, y, s) => {
    ctx.beginPath();
    ctx.moveTo(x - s * 0.45, y + s * 0.3);
    ctx.bezierCurveTo(x - s * 0.48, y - s * 0.3, x - s * 0.25, y - s * 0.45, x, y - s * 0.45);
    ctx.bezierCurveTo(x + s * 0.25, y - s * 0.45, x + s * 0.48, y - s * 0.3, x + s * 0.45, y + s * 0.3);
    ctx.closePath();
    for (const k of [-0.2, 0.2]) { ctx.moveTo(x + k * s, y + s * 0.25); ctx.quadraticCurveTo(x + k * s * 0.8, y - s * 0.1, x + k * s * 0.4, y - s * 0.38); }
  },
  jump_cut: (ctx, x, y, s) => boltPath(ctx, x, y, s * 0.95),
  roller_boogie: (ctx, x, y, s) => {
    ctx.beginPath();
    ctx.moveTo(x - s * 0.3, y - s * 0.42);
    ctx.lineTo(x - s * 0.02, y - s * 0.42);
    ctx.lineTo(x, y - s * 0.02);
    ctx.quadraticCurveTo(x + s * 0.42, y, x + s * 0.42, y + s * 0.16);
    ctx.lineTo(x - s * 0.38, y + s * 0.16);
    ctx.closePath();
    for (const k of [-0.22, 0.24]) { ctx.moveTo(x + k * s + s * 0.1, y + s * 0.34); ctx.arc(x + k * s, y + s * 0.34, s * 0.1, 0, TAU); }
  },
  double_vision: (ctx, x, y, s) => starPath(ctx, x, y, s * 0.46, s * 0.1, 4, 0),
};

for (const id of PERK_IDS) {
  const S = SPONSORS[id];
  card(`sponsor_sign_${id}`, { w: 512, h: 192, alpha: true, opts: 'lit: false = unpowered (dark tubes)' }, (ctx, w, h, t, o) => {
    const lit = o.lit !== false;
    ctx.save();
    ctx.shadowColor = 'rgba(10,6,20,0.5)';
    ctx.shadowBlur = 8;
    ctx.shadowOffsetY = 3;
    rr(ctx, 10, 14, w - 20, h - 28, 30);
    fill(ctx, linear(ctx, 0, 14, 0, h - 14, ['#2E2240', '#1A1228']));
    ctx.restore();
    rr(ctx, 10, 14, w - 20, h - 28, 30);
    stroke(ctx, '#120C1C', 4);
    rr(ctx, 20, 24, w - 40, h - 48, 22);
    stroke(ctx, alpha(S.main, lit ? 0.55 : 0.25), 3);
    for (const [x, y] of [[30, 34], [w - 30, 34], [30, h - 34], [w - 30, h - 34]]) { circle(ctx, x, y, 4); inked(ctx, '#8A90A8', 1.5, '#120C1C'); }
    if (lit) {
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      glowBlob(ctx, w * 0.58, h * 0.45, w * 0.4, S.neon, 0.22);
      glowBlob(ctx, w * 0.15, h * 0.5, h * 0.5, S.neon2, 0.25);
      ctx.restore();
    }
    const icon = NEON_ICONS[id];
    if (id === 'double_vision') {
      neonPath(ctx, () => icon(ctx, w * 0.13, h * 0.47, h * 0.56), S.neon, 6, lit);
      neonPath(ctx, () => icon(ctx, w * 0.17, h * 0.53, h * 0.56), S.neon2, 6, lit);
    } else neonPath(ctx, () => icon(ctx, w * 0.15, h * 0.5, h * 0.56), S.neon2, 7, lit);
    neonText(ctx, S.name, w * 0.6, h * 0.42, 62, FONT.groovy, S.neon, lit, w * 0.66);
    neonText(ctx, S.sub, w * 0.6, h * 0.74, 22, FONT.sign, S.neon2, lit, w * 0.5);
  });
}

// ---------------------------------------------------------------------------------------------------------
// Newsroom weather map + magnets, Master Control rundown board (GDD §5.7, §13)
// ---------------------------------------------------------------------------------------------------------

card('weather_map', { w: 512, h: 384, opts: 'bare map: the magnets are separate cards (magnet_*)' }, (ctx, w, h) => {
  rr(ctx, 0, 0, w, h, 14);
  fill(ctx, linear(ctx, 0, 0, 0, h, ['#E8ECF6', '#9AA4BC', '#C9CED8', '#7A8098']));
  rr(ctx, 12, 12, w - 24, h - 24, 6);
  fill(ctx, '#23307A');
  const hh = 50;
  ctx.fillStyle = linear(ctx, 0, 12, 0, 12 + hh, ['#2F5BD3', '#1E3A9A']);
  ctx.fillRect(12, 12, w - 24, hh);
  ctx.fillStyle = C.red;
  ctx.fillRect(12, 12 + hh - 5, w - 24, 5);
  badge13(ctx, 44, 12 + hh / 2 - 2, 17, { ol: 2 });
  label(ctx, 'TRI-COUNTY WEATHER', w / 2 + 16, 12 + hh / 2 - 1, { fam: FONT.sign, px: 26, maxW: w * 0.76, fill: '#FFFFFF', stroke: '#0E1A4A', lw: 4, track: 2 });
  weatherMapArt(ctx, 12, 12 + hh, w - 24, h - 24 - hh, { names: true });
  // compass rose
  const cx = 52, cy = h - 56;
  circle(ctx, cx, cy, 20);
  inked(ctx, 'rgba(255,255,255,0.85)', 2);
  poly(ctx, [cx, cy - 17, cx + 6, cy, cx, cy + 17, cx - 6, cy]);
  inked(ctx, C.red, 1.5);
  label(ctx, 'N', cx, cy - 28, { fam: FONT.sign, px: 12, fill: '#FFFFFF', stroke: C.ink, lw: 3 });
  gloss(ctx, 12, 12, w - 24, h - 24, 6, 0.12);
});

/** Die-cut vinyl magnet: the painted icon gets a thick white border, a gloss and a soft drop shadow. */
function dieCut(ctx, w, h, paint, border = 7) {
  const icon = makeCanvas(w, h);
  const ig = icon.getContext('2d');
  ig.lineJoin = 'round';
  ig.lineCap = 'round';
  paint(ig, w, h);
  const sil = makeCanvas(w, h), g = sil.getContext('2d');
  for (let i = 0; i < 20; i++) { const a = (i / 20) * TAU; g.drawImage(icon, Math.cos(a) * border, Math.sin(a) * border); }
  g.globalCompositeOperation = 'source-in';
  g.fillStyle = '#FFFFFF';
  g.fillRect(0, 0, w, h);
  ctx.save();
  ctx.shadowColor = 'rgba(20,10,40,0.5)';
  ctx.shadowBlur = 6;
  ctx.shadowOffsetY = 3;
  ctx.drawImage(sil, 0, 0);
  ctx.restore();
  ctx.drawImage(icon, 0, 0);
  ctx.save();
  ctx.globalCompositeOperation = 'source-atop';
  ctx.fillStyle = linear(ctx, 0, 0, w * 0.6, h * 0.6, ['rgba(255,255,255,0.35)', 'rgba(255,255,255,0)']);
  ctx.fillRect(0, 0, w, h);
  ctx.restore();
}
function cloudFace(ctx, x, y, s, mood = 'happy') {
  for (const k of [-1, 1]) {
    circle(ctx, x + k * s * 0.2, y, s * 0.07);
    fill(ctx, C.ink);
    if (mood === 'grumpy') { capsule(ctx, x + k * s * 0.3, y - s * 0.16, x + k * s * 0.1, y - s * 0.1, s * 0.05, C.ink); }
  }
  ctx.beginPath();
  if (mood === 'grumpy') ctx.arc(x, y + s * 0.2, s * 0.14, Math.PI + 0.5, TAU - 0.5);
  else ctx.arc(x, y + s * 0.04, s * 0.14, 0.4, Math.PI - 0.4);
  stroke(ctx, C.ink, s * 0.05);
  if (mood === 'happy') for (const k of [-1, 1]) { ellipse(ctx, x + k * s * 0.34, y + s * 0.1, s * 0.08, s * 0.05); fill(ctx, 'rgba(255,110,120,0.5)'); }
}
function raindrop(ctx, x, y, s, col) {
  ctx.beginPath();
  ctx.moveTo(x, y - s);
  ctx.bezierCurveTo(x + s * 0.7, y - s * 0.1, x + s * 0.6, y + s * 0.6, x, y + s * 0.6);
  ctx.bezierCurveTo(x - s * 0.6, y + s * 0.6, x - s * 0.7, y - s * 0.1, x, y - s);
  inked(ctx, col, s * 0.18);
}
const MAGNETS = {
  sun: (g, w, h) => sunIcon(g, w / 2, h / 2, w * 0.36, true),
  cloud: (g, w, h) => {
    cloud(g, w / 2, h * 0.5, w * 0.78, h * 0.46, linear(g, 0, h * 0.25, 0, h * 0.75, ['#FFFFFF', '#D8E6F8']), C.ink, 3);
    cloudFace(g, w / 2, h * 0.55, w * 0.5);
  },
  rain: (g, w, h) => {
    for (const [x, y] of [[0.3, 0.74], [0.52, 0.8], [0.72, 0.72]]) raindrop(g, w * x, h * y, w * 0.08, '#3FA9F5');
    cloud(g, w / 2, h * 0.38, w * 0.74, h * 0.42, linear(g, 0, h * 0.15, 0, h * 0.6, ['#E8EEF8', '#9AAAC8']), C.ink, 3);
    cloudFace(g, w / 2, h * 0.43, w * 0.46, 'sad');
  },
  bolt: (g, w, h) => {
    boltPath(g, w / 2, h / 2, h * 0.78);
    inked(g, linear(g, 0, h * 0.1, 0, h * 0.9, ['#FFF3A0', '#FFD23A', '#F4A020']), 4);
  },
  storm: (g, w, h) => {
    boltPath(g, w * 0.56, h * 0.72, h * 0.42);
    inked(g, '#FFD23A', 3);
    cloud(g, w / 2, h * 0.36, w * 0.8, h * 0.44, linear(g, 0, h * 0.12, 0, h * 0.6, ['#7A6A9A', '#5B4A7A', '#3E3058']), C.ink, 3);
    cloudFace(g, w / 2, h * 0.41, w * 0.5, 'grumpy');
  },
};
for (const [k, paint] of Object.entries(MAGNETS)) {
  card(`magnet_${k}`, { w: 128, h: 128, alpha: true }, (ctx, w, h) => dieCut(ctx, w, h, (g, iw, ih) => {
    g.translate(iw * 0.1, ih * 0.1);
    paint(g, iw * 0.8, ih * 0.8);
  }, 6));
}

/** Lined index card with a red pushpin. */
function indexCard(ctx, w, h, seed) {
  const r = rng(seed);
  ctx.save();
  ctx.translate(w / 2, h / 2);
  ctx.rotate((r() - 0.5) * 0.03);
  ctx.translate(-w / 2, -h / 2);
  ctx.save();
  ctx.shadowColor = 'rgba(40,24,20,0.35)';
  ctx.shadowBlur = 6;
  ctx.shadowOffsetY = 3;
  rr(ctx, 6, 6, w - 12, h - 12, 4);
  fill(ctx, '#FFFBEF');
  ctx.restore();
  ctx.save();
  rr(ctx, 6, 6, w - 12, h - 12, 4);
  ctx.clip();
  ctx.fillStyle = 'rgba(90,150,220,0.35)';
  for (let y = 44; y < h - 8; y += 20) ctx.fillRect(6, y, w - 12, 1.2);
  ctx.fillStyle = 'rgba(226,59,59,0.55)';
  ctx.fillRect(6, 34, w - 12, 1.6);
  ctx.fillStyle = linear(ctx, w - 50, h - 50, w, h, ['rgba(120,90,60,0)', 'rgba(120,90,60,0.18)']);
  ctx.fillRect(0, 0, w, h);
  grain(ctx, w, h, 0.08, seed);
  ctx.restore();
  ctx.restore();
  circle(ctx, w / 2, 16, 7);
  inked(ctx, radial(ctx, w / 2 - 2, 14, 0, 8, ['#FF8A7A', C.red, '#9A1A20']), 1.5);
}
/** Gold-foil star sticker (the rundown board's trophy mark). */
function goldStar(ctx, sx, sy) {
  ctx.save();
  ctx.shadowColor = 'rgba(80,40,0,0.4)';
  ctx.shadowBlur = 4;
  ctx.shadowOffsetY = 2;
  starPath(ctx, sx, sy, 26, 12, 5, -Math.PI / 2 + 0.2);
  fill(ctx, linear(ctx, sx - 26, sy - 26, sx + 26, sy + 26, GOLDEN));
  ctx.restore();
  starPath(ctx, sx, sy, 26, 12, 5, -Math.PI / 2 + 0.2);
  stroke(ctx, '#B07A16', 1.5);
  sparkle(ctx, sx - 8, sy - 8, 7);
}
const MARK = { ink: '#2A2438', red: '#D8322B', blue: '#2F5BD3', green: '#2E9A4A', yellow: '#E8B82E', purple: '#7A3A9A', brown: '#8A5A3C' };
/** Marker pictograms for rundown cards 1-6, drawn in a 320x200 card around (cx, cy). */
const RUNDOWN = [
  (ctx, m, cx, cy) => {
    m.ink([cx - 90, cy - 44, cx + 90, cy - 44]);
    [[MARK.red, 86], [MARK.yellow, 72], [MARK.green, 58], [MARK.blue, 44]].forEach(([c, len], i) => {
      const x = cx - 60 + i * 40;
      m.ink([x, cy - 44, x, cy - 36]);
      const bar = [x - 9, cy - 36, x + 9, cy - 36, x + 9, cy - 36 + len, x - 9, cy - 36 + len];
      m.fillIn(bar, c);
      m.ink(bar, true);
    });
    m.ink([cx + 96, cy + 20, cx + 96, cy - 16, cx + 112, cy - 22, cx + 112, cy + 12]);
    m.ink(m.ring(cx + 91, cy + 21, 6, 5));
    m.ink(m.ring(cx + 107, cy + 14, 6, 5));
  },
  (ctx, m, cx, cy) => {
    const ox = cx - 80;
    m.fillIn(m.ring(ox, cy + 6, 30, 36), MARK.brown);
    m.ink(m.ring(ox, cy + 6, 30, 36));
    m.ink([ox - 24, cy - 22, ox - 26, cy - 44, ox - 10, cy - 30]);
    m.ink([ox + 24, cy - 22, ox + 26, cy - 44, ox + 10, cy - 30]);
    for (const s of [-1, 1]) { m.ink(m.ring(ox + s * 12, cy - 4, 10)); m.ink(m.ring(ox + s * 12, cy - 3, 3)); }
    m.ink([ox - 4, cy + 10, ox, cy + 16, ox + 4, cy + 10]);
    const sx = cx;
    const sock = [sx - 18, cy - 40, sx + 18, cy - 40, sx + 18, cy + 18, sx + 30, cy + 30, sx + 18, cy + 44, sx - 18, cy + 40];
    m.fillIn(sock, MARK.red);
    m.ink(sock, true);
    for (const y of [-26, -12]) m.ink([sx - 18, cy + y, sx + 18, cy + y]);
    m.ink(m.ring(sx - 7, cy + 2, 6));
    m.ink(m.ring(sx + 9, cy + 2, 6));
    m.ink([sx - 1, cy + 2, sx + 3, cy + 2]);
    const dx = cx + 82;
    const head = [dx - 26, cy + 36, dx - 30, cy - 10, dx - 10, cy - 34, dx + 18, cy - 30, dx + 34, cy - 6, dx + 30, cy + 36];
    m.fillIn(head, MARK.purple);
    m.ink(head, true);
    m.ink([dx - 10, cy - 34, dx - 4, cy - 48, dx + 4, cy - 34, dx + 12, cy - 46, dx + 18, cy - 30]);
    for (const s of [-1, 1]) { m.ink(m.ring(dx + s * 11, cy - 10, 9)); m.ink(m.ring(dx + s * 11 + 3, cy - 8, 3)); }
    m.ink([dx - 14, cy + 16, dx + 18, cy + 16]);
  },
  (ctx, m, cx, cy) => {
    for (const s of [-1, 1]) {
      const bx = cx + s * 30;
      const palm = [bx - s * 4, cy + 44, bx - s * 26, cy + 6, bx - s * 22, cy - 34, bx - s * 8, cy - 40, bx + s * 8, cy - 20, bx + s * 10, cy + 40];
      m.fillIn(palm, '#F2C29B');
      m.ink(palm, true);
      m.ink([bx - s * 12, cy - 30, bx - s * 4, cy - 2]);
    }
    for (const s of [-1, 1]) for (let k = 0; k < 3; k++) {
      const a = -Math.PI / 2 + s * (0.45 + k * 0.4);
      m.ink([cx + Math.cos(a) * 52, cy - 8 + Math.sin(a) * 52, cx + Math.cos(a) * 68, cy - 8 + Math.sin(a) * 68]);
    }
    label(ctx, '$', cx + 100, cy + 4, { fam: FONT.round, px: 58, fill: MARK.green, rot: 0.12 });
    label(ctx, '$', cx - 100, cy + 10, { fam: FONT.round, px: 34, fill: MARK.green, rot: -0.2 });
  },
  (ctx, m, cx, cy) => {
    const tx = cx + 10, base = cy + 50;
    m.ink([tx - 26, base, tx, base - 70, tx + 26, base]);
    m.ink([tx - 18, base - 20, tx + 18, base - 20, tx - 10, base - 44, tx + 10, base - 44]);
    m.ink([tx - 18, base - 20, tx + 10, base - 44]);
    const cl = [];
    for (let i = 0; i <= 44; i++) {
      const a = (i / 44) * TAU, bump = Math.sin(a) < 0 ? 1 + 0.22 * Math.abs(Math.sin(a * 3.5)) : 1;
      cl.push(tx - 18 + Math.cos(a) * 58 * bump, cy - 46 + Math.sin(a) * 22 * bump * (Math.sin(a) < 0 ? 1.5 : 1));
    }
    m.fillIn(cl, '#6A5A8A');
    m.ink(cl, true);
    const bolt = [tx + 4, cy - 30, tx - 8, cy - 8, tx + 4, cy - 8, tx - 2, cy + 12, tx + 16, cy - 14, tx + 4, cy - 14, tx + 12, cy - 30];
    m.fillIn(bolt, MARK.yellow);
    m.ink(bolt, true);
    for (const s of [-1, 1]) m.ink([tx + s * 38, base - 66, tx + s * 50, base - 74]);
  },
  (ctx, m, cx, cy) => {
    const rx = cx - 6;
    m.fillIn(m.ring(rx, cy, 54), '#C9962E');
    m.ink(m.ring(rx, cy, 60));
    m.ink(m.ring(rx, cy, 54));
    for (let i = 0; i < 3; i++) { const a = (i / 3) * TAU - Math.PI / 2; m.fillIn(m.ring(rx + Math.cos(a) * 30, cy + Math.sin(a) * 30, 12), '#FFFFFF'); m.ink(m.ring(rx + Math.cos(a) * 30, cy + Math.sin(a) * 30, 12)); }
    m.ink(m.ring(rx, cy, 9));
    m.ink([rx + 56, cy + 20, rx + 110, cy + 44]);
    label(ctx, '13', rx + 104, cy - 20, { fam: FONT.round, px: 30, fill: MARK.red, rot: 0.1 });
  },
  (ctx, m, cx, cy) => {
    const box = [cx - 66, cy - 30, cx + 66, cy - 30, cx + 66, cy + 50, cx - 66, cy + 50];
    m.fillIn(box, MARK.brown);
    m.ink(box, true);
    m.fillIn(m.ring(cx - 12, cy + 10, 42, 30), '#FFFFFF');
    m.ink(m.ring(cx - 12, cy + 10, 42, 30));
    m.ink([cx - 10, cy - 30, cx - 36, cy - 64]);
    m.ink([cx - 10, cy - 30, cx + 18, cy - 62]);
    m.ink([cx - 14, cy + 22, cx - 6, cy + 30, cx + 4, cy + 22]);
    m.ink([cx - 30, cy + 2, cx - 20, cy + 6]);
    m.ink([cx - 4, cy + 6, cx + 6, cy + 2]);
    m.ink(m.ring(cx + 50, cy + 2, 6));
    m.ink(m.ring(cx + 50, cy + 24, 6));
    label(ctx, 'z', cx + 90, cy - 36, { fam: FONT.round, px: 22, fill: MARK.blue, rot: 0.2 });
    label(ctx, 'Z', cx + 108, cy - 58, { fam: FONT.round, px: 32, fill: MARK.blue, rot: 0.2 });
  },
];
RUNDOWN.forEach((draw, i) => {
  card(`rundown_card_${i + 1}`, { w: 320, h: 200, opts: 'star: true adds the gold-star sticker (the step is done)' }, (ctx, w, h, t, o) => {
    indexCard(ctx, w, h, 60 + i);
    const m = marker(ctx, rng(300 + i), MARK.ink, 4.5);
    draw(ctx, m, w / 2, h / 2 + 14);
    if (o.star) goldStar(ctx, w - 38, 38);
  });
});

card('rundown_header', { w: 512, h: 128 }, (ctx, w, h) => {
  rr(ctx, 0, 0, w, h, 10);
  fill(ctx, '#FFF4DC');
  ctx.save();
  rr(ctx, 0, 0, w, h, 10);
  ctx.clip();
  ctx.fillStyle = linear(ctx, 0, 0, w, 0, [C.orange, C.gold, C.orange]);
  ctx.fillRect(0, 0, w, 14);
  ctx.fillStyle = C.plum;
  ctx.fillRect(0, h - 12, w, 12);
  ctx.fillStyle = C.gold;
  ctx.fillRect(0, h - 16, w, 4);
  grain(ctx, w, h, 0.1, 5);
  ctx.restore();
  rr(ctx, 0, 0, w, h, 10);
  stroke(ctx, C.choc, 3);
  bat(ctx, 44, 60, 30, C.plum);
  bat(ctx, w - 44, 56, 26, C.plum);
  label(ctx, 'Spooktacular', w / 2, h * 0.43, { fam: FONT.groovy, px: 52, maxW: w * 0.7, fill: vgrad(['#FFD27A', C.orange, '#C04A1E']), stroke: '#3A1440', lw: 6, depth: 4, depthFill: '#3A1440', rot: -0.03 });
  label(ctx, 'RUNDOWN', w / 2, h * 0.76, { fam: FONT.sign, px: 22, fill: C.plum, track: 12 });
});

// ---------------------------------------------------------------------------------------------------------
// Lobby & studio props: letter board, tote flip digits, dust mark, scenery-flat boards, chyron
// ---------------------------------------------------------------------------------------------------------

/** Walnut picture/board frame of thickness `t` around the whole canvas. */
function woodFrame(ctx, w, h, t, r = 10) {
  rr(ctx, 0, 0, w, h, r);
  fill(ctx, linear(ctx, 0, 0, 0, h, ['#9A6038', C.walnut, '#5A3420']));
  ctx.save();
  rr(ctx, 0, 0, w, h, r);
  ctx.clip();
  const g = rng(w * 7 + h);
  ctx.strokeStyle = 'rgba(50,24,12,0.3)';
  ctx.lineWidth = 1.2;
  for (let i = 0; i < 30; i++) {
    const y = g() * h;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.bezierCurveTo(w * 0.3, y + (g() - 0.5) * 10, w * 0.6, y + (g() - 0.5) * 10, w, y + (g() - 0.5) * 6);
    ctx.stroke();
  }
  ctx.restore();
  rr(ctx, t, t, w - t * 2, h - t * 2, r * 0.4);
  stroke(ctx, 'rgba(30,14,8,0.6)', 3);
  rr(ctx, 1.5, 1.5, w - 3, h - 3, r);
  stroke(ctx, 'rgba(255,220,170,0.35)', 2);
}

/** One white plastic changeable letter, slightly skewed on its groove. */
function boardLetter(ctx, ch, x, y, px, rot = 0) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot);
  setFont(ctx, px, FONT.sign);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = 'rgba(0,0,0,0.45)';
  ctx.fillText(ch, 1.5, 2);
  ctx.fillStyle = '#F4F1E8';
  ctx.fillText(ch, 0, 0);
  ctx.restore();
}
/** Lays a line of letters from x0 with fixed pitch; `keep(i)` false leaves a letter's groove empty. */
function boardLine(ctx, str, x0, y, px, pitch, seed, keep = () => true) {
  const r = rng(seed);
  [...str].forEach((ch, i) => {
    const jit = (r() - 0.5) * 0.08;
    if (ch !== ' ' && keep(i)) boardLetter(ctx, ch, x0 + i * pitch, y + (r() - 0.5) * 1.5, px, jit);
  });
}

card('letter_board', { w: 512, h: 320, opts: 'signOff: true = the fallen SIGN OFF letters are back (after the easter egg)' }, (ctx, w, h, t, o) => {
  const f = 18;
  woodFrame(ctx, w, h, f, 12);
  ctx.fillStyle = '#211A26';
  ctx.fillRect(f, f, w - f * 2, h - f * 2);
  ctx.fillStyle = 'rgba(255,255,255,0.05)';
  for (let y = f + 3; y < h - f; y += 7) ctx.fillRect(f, y, w - f * 2, 2);
  ctx.fillStyle = radial(ctx, w * 0.35, h * 0.25, 10, w * 0.8, ['rgba(255,230,190,0.08)', 'rgba(0,0,0,0.25)']);
  ctx.fillRect(f, f, w - f * 2, h - f * 2);
  const px = 30, pitch = 23, x0 = 50;
  boardLine(ctx, 'TONIGHT ON WZTV 13', x0 + pitch * 0.5, 60, px * 0.9, pitch * 0.95, 3);
  boardLine(ctx, '10:00 PRECINCT 13', x0, 116, px, pitch, 5);
  boardLine(ctx, '11:00 SPOOKTACULAR', x0, 168, px, pitch, 7);
  const line = '12:00 SIGN OFF';
  if (o.signOff) boardLine(ctx, line, x0, 220, px, pitch, 9);
  else {
    boardLine(ctx, line, x0, 220, px, pitch, 9, (i) => i < 6);
    boardLetter(ctx, 'G', x0 + 8 * pitch + 4, 226, px, 0.5);
    boardLetter(ctx, 'F', x0 + 12 * pitch + 2, 232, px, -0.9);
  }
  ctx.fillStyle = C.gold;
  ctx.fillRect(f, h - f - 26, w - f * 2, 3);
  label(ctx, 'THE TRI-COUNTY\'S HAPPY CHANNEL', w / 2, h - f - 12, { fam: FONT.round, px: 12, fill: '#E8D8B8', track: 2 });
});

const TOTE_CHARS = '0123456789$,';
const TOTE_ATLAS = {
  chars: TOTE_CHARS, cols: 4, rows: 3, cellW: 128, cellH: 168,
  uv(ch) {
    const i = Math.max(0, TOTE_CHARS.indexOf(ch)), c = i % 4, r = Math.floor(i / 4);
    return [(c * 128) / 512, 1 - ((r + 1) * 168) / 504, ((c + 1) * 128) / 512, 1 - (r * 168) / 504];
  },
};
card('tote_digits', { w: 512, h: 504, atlas: TOTE_ATLAS, opts: 'atlas: texture.userData.atlas.uv(ch) -> [u0, v0, u1, v1]' }, (ctx, w, h) => {
  ctx.fillStyle = '#2A1810';
  ctx.fillRect(0, 0, w, h);
  [...TOTE_CHARS].forEach((ch, i) => {
    const x = (i % 4) * 128, y = Math.floor(i / 4) * 168, pad = 7, cw = 128 - pad * 2, chh = 168 - pad * 2, mid = y + 84;
    rr(ctx, x + pad, y + pad, cw, chh, 14);
    fill(ctx, linear(ctx, 0, y + pad, 0, y + 168 - pad, ['#5A3424', '#3E2218', [0.5, '#34190F'], [0.5, '#2A140C'], '#3A2016']));
    ctx.save();
    rr(ctx, x + pad, y + pad, cw, chh, 14);
    ctx.clip();
    label(ctx, ch, x + 64, y + 90, { fam: FONT.round, px: 128, maxW: cw * 0.86, fill: vgrad(['#FFE6A0', '#FFB347', '#E8862A']), glow: 'rgba(255,170,60,0.55)', glowBlur: 12 });
    ctx.fillStyle = 'rgba(255,255,255,0.08)';
    ctx.fillRect(x, y + pad, 128, 84 - pad);
    ctx.restore();
    ctx.fillStyle = '#140A06';
    ctx.fillRect(x + pad, mid - 2, cw, 4);
    for (const s of [-1, 1]) { rr(ctx, x + 64 + s * (cw / 2 - 2) - 4, mid - 7, 8, 14, 3); fill(ctx, '#8A90A8'); }
    rr(ctx, x + pad, y + pad, cw, chh, 14);
    stroke(ctx, '#140A06', 3);
  });
});

card('dust_rect', { w: 512, h: 256, alpha: true, opts: 'rug decal: grey dust with the clean footprint where Telly stood' }, (ctx, w, h) => {
  const dust = layer('dust:speckle', w, h, (g) => {
    const img = g.createImageData(w, h), d = img.data, r = rng(606);
    for (let i = 0; i < d.length; i += 4) {
      const v = r();
      d[i] = 205 + v * 30; d[i + 1] = 198 + v * 28; d[i + 2] = 186 + v * 26;
      d[i + 3] = (0.22 + r() * r() * 0.55) * 255;
    }
    g.putImageData(img, 0, 0);
  });
  ctx.drawImage(dust, 0, 0);
  ctx.save();
  ctx.globalCompositeOperation = 'destination-in';
  ctx.fillStyle = radial(ctx, w / 2, h / 2, h * 0.3, w * 0.52, ['rgba(0,0,0,1)', 'rgba(0,0,0,0.85)', 'rgba(0,0,0,0)']);
  ctx.fillRect(0, 0, w, h);
  ctx.restore();
  ctx.save();
  ctx.globalCompositeOperation = 'destination-out';
  ctx.filter = 'blur(5px)';
  rr(ctx, w * 0.25, h * 0.27, w * 0.5, h * 0.46, 18);
  fill(ctx, '#000');
  ctx.filter = 'blur(2px)';
  for (const [x, y] of [[0.22, 0.2], [0.78, 0.2], [0.22, 0.8], [0.78, 0.8]]) { circle(ctx, w * x, h * y, 9); fill(ctx, '#000'); }
  ctx.restore();
  ctx.save();
  ctx.globalCompositeOperation = 'source-over';
  for (const [x, y] of [[0.22, 0.2], [0.78, 0.2], [0.22, 0.8], [0.78, 0.8]]) { circle(ctx, w * x, h * y, 7); fill(ctx, 'rgba(70,40,30,0.3)'); }
  ctx.restore();
});

/** Painted scenery-flat slices used as window boards: fn(ctx, w, h) paints the face. */
const BOARDS = [
  (ctx, w, h) => {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#4AA8F0', '#9ED8FF']);
    ctx.fillRect(0, 0, w, h);
    cloud(ctx, w * 0.22, h * 0.55, 120, 50, '#FFFFFF');
    cloud(ctx, w * 0.7, h * 0.4, 150, 58, '#FFFFFF');
  },
  (ctx, w, h) => {
    ctx.fillStyle = '#E8D8C0';
    ctx.fillRect(0, 0, w, h);
    const bh = h / 4;
    for (let j = 0; j < 4; j++) for (let i = -1; i < 12; i++) {
      rr(ctx, i * 52 + (j & 1) * 26 + 2, j * bh + 2, 48, bh - 4, 3);
      fill(ctx, mix('#B5472A', '#D2643A', ((i * 5 + j * 3) % 7) / 7));
    }
  },
  (ctx, w, h) => {
    for (let i = 0; i < 10; i++) {
      ctx.fillStyle = mix('#C8905A', '#E0AC70', (i * 3 % 5) / 5);
      ctx.fillRect(i * (w / 10), 0, w / 10, h);
      ctx.fillStyle = 'rgba(90,50,20,0.5)';
      ctx.fillRect(i * (w / 10), 0, 2, h);
    }
    const r = rng(12);
    for (let i = 0; i < 6; i++) { ellipse(ctx, r() * w, r() * h, 6, 3.5); stroke(ctx, 'rgba(110,60,25,0.6)', 1.5); }
  },
  (ctx, w, h) => {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, [C.nightTop, C.nightHz]);
    ctx.fillRect(0, 0, w, h);
    starField(ctx, w, h, 40, 44);
    circle(ctx, w * 0.8, h * 0.45, 26);
    fill(ctx, C.moon);
    circle(ctx, w * 0.8 + 10, h * 0.4, 22);
    fill(ctx, C.nightTop);
  },
  (ctx, w, h) => {
    [C.shag, C.gold, C.orange, C.rust, C.choc].forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(0, (i * h) / 5, w, h / 5 + 1); });
    slicedSun(ctx, w * 0.3, h * 1.05, 60, '#FFF1A0', '#FF8A3A', C.orange);
  },
  (ctx, w, h) => {
    ctx.fillStyle = '#E3A04A';
    ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 7; i++) {
      const cx = i * 80 + 20, cy = h / 2;
      for (let k = 4; k > 0; k--) { circle(ctx, cx, cy, k * 11); fill(ctx, k & 1 ? '#7A4A2A' : '#F0C070'); }
    }
  },
];
BOARDS.forEach((paint, i) => {
  card(`scenery_board_${i + 1}`, { w: 512, h: 112 }, (ctx, w, h) => {
    ctx.fillStyle = linear(ctx, 0, 0, 0, h, ['#C8905A', '#A8703A']);
    ctx.fillRect(0, 0, w, h);
    const r = rng(20 + i);
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(10, 6);
    for (let x = 10; x <= w - 10; x += 16) ctx.lineTo(x, 5 + r() * 4);
    for (let x = w - 10; x >= 10; x -= 16) ctx.lineTo(x, h - 5 - r() * 4);
    ctx.closePath();
    ctx.clip();
    paint(ctx, w, h);
    for (let k = 0; k < 7; k++) { ellipse(ctx, r() * w, r() < 0.5 ? r() * 12 : h - r() * 12, 8 + r() * 14, 3 + r() * 4, r()); fill(ctx, '#B88048'); }
    ctx.restore();
    ctx.fillStyle = 'rgba(255,230,190,0.25)';
    ctx.fillRect(0, 0, w, 3);
    ctx.fillStyle = 'rgba(40,20,10,0.35)';
    ctx.fillRect(0, h - 4, w, 4);
    for (const x of [18, w - 18]) for (const y of [h * 0.3, h * 0.7]) { circle(ctx, x, y, 4.5); inked(ctx, radial(ctx, x - 1, y - 1, 0, 5, ['#E8ECF6', '#6A7088']), 1.2, '#2A2230'); }
    grain(ctx, w, h, 0.12, i);
  });
});

card('chyron', { w: 512, h: 128, alpha: true, opts: 'text / sub: optional lines (the HUD may overlay its own DOM text instead)' }, (ctx, w, h, t, o) => {
  const y = 22, bh = 62, x0 = 70;
  ctx.save();
  ctx.shadowColor = 'rgba(30,12,10,0.5)';
  ctx.shadowBlur = 10;
  ctx.shadowOffsetY = 4;
  rr(ctx, x0 - 10, y, w - x0 - 4, bh, [0, bh / 2, bh / 2, 0]);
  fill(ctx, linear(ctx, 0, y, 0, y + bh, ['#F08A3A', '#D9602B', '#A8401E']));
  rr(ctx, x0 + 20, y + bh - 2, w * 0.62, 30, [0, 0, 15, 15]);
  fill(ctx, linear(ctx, 0, y + bh, 0, y + bh + 30, ['#6A3A22', '#4A2616']));
  ctx.restore();
  ctx.fillStyle = C.gold;
  ctx.fillRect(x0, y + bh - 8, w - x0 - 40, 3);
  ctx.fillStyle = C.mustard;
  ctx.fillRect(x0, y + bh - 4, w - x0 - 60, 2);
  ctx.fillStyle = 'rgba(255,255,255,0.22)';
  ctx.fillRect(x0 - 10, y + 4, w - x0 - 36, 10);
  circle(ctx, x0 - 8, y + bh / 2 + 6, 46);
  fill(ctx, linear(ctx, 0, y - 20, 0, y + bh + 30, ['#7A4A2A', C.choc]));
  circle(ctx, x0 - 8, y + bh / 2 + 6, 46);
  stroke(ctx, C.gold, 4);
  badge13(ctx, x0 - 8, y + bh / 2 + 6, 34, { ol: 2 });
  if (o.text) label(ctx, o.text, x0 + 40, y + bh * 0.46, { fam: FONT.groovy, px: 40, maxW: w - x0 - 90, align: 'left', fill: vgrad(['#FFFDF0', '#FFE7A8']), stroke: '#5A2210', lw: 5, depth: 3, depthFill: '#5A2210' });
  if (o.sub) label(ctx, o.sub, x0 + 44, y + bh + 13, { fam: FONT.sign, px: 15, maxW: w * 0.58, align: 'left', fill: '#FFD27A', track: 1 });
});

// ---------------------------------------------------------------------------------------------------------
// Lobby portrait wall, TV WEEKLY, Perpetua-Tube ad, ticket stub, crew badge, cap badge, dressing rooms
// ---------------------------------------------------------------------------------------------------------

const PORTRAITS = {
  skip: { name: 'SKIP KOWALSKI', job: 'FLOOR CREW', bg: ['#6FA0F0', '#2F5BD3', '#1B2F7A'] },
  roxy: { name: 'ROXY RIVERS', job: 'BOOGIE DOWN SATURDAY', bg: ['#FFB0C8', '#C2407A', '#5A1A4A'] },
  penny: { name: 'PENNY WATTS', job: 'CHIEF ENGINEER', bg: ['#8ADADA', '#2E8C8C', '#14464A'] },
  duke: { name: 'DUKE DALTON', job: 'PRECINCT 13', bg: ['#FFC08A', '#B5472A', '#4A1A12'] },
  baron: { name: 'BARON VON STATIC', job: 'HORROR HOST', bg: ['#B08ADA', '#6B3A6E', '#24102E'] },
  stormy_stu: { name: 'STORMY STU', job: 'WEATHER WATCH 13', bg: ['#BFE8FF', '#4AA8F0', '#1E4A8A'] },
};
/** Framed 70s studio portrait: mottled backdrop, bust, brass name plate. */
function portrait(ctx, w, h, who, P, o = {}) {
  woodFrame(ctx, w, h, 16, 8);
  const ix = 16, iy = 16, iw = w - 32, ih = h - 32;
  ctx.save();
  rr(ctx, ix, iy, iw, ih, 4);
  ctx.clip();
  ctx.fillStyle = radial(ctx, w * 0.45, h * 0.36, 10, h * 0.7, P.bg);
  ctx.fillRect(ix, iy, iw, ih);
  const r = rng(hash(who));
  for (let i = 0; i < 14; i++) { ellipse(ctx, ix + r() * iw, iy + r() * ih, 20 + r() * 40, 14 + r() * 26, r() * 3); fill(ctx, alpha(r() < 0.5 ? '#FFFFFF' : '#1E1030', 0.07)); }
  ctx.fillStyle = radial(ctx, w * 0.5, h * 0.38, 10, w * 0.5, ['rgba(255,245,220,0.35)', 'rgba(255,245,220,0)']);
  ctx.fillRect(ix, iy, iw, ih);
  drawBust(ctx, who === 'stormy_stu' ? 'stu' : who, w / 2, h * 0.43, w * 0.19, o);
  vignette(ctx, w, h, 0.4, '30,16,30', 0.35);
  ctx.fillStyle = linear(ctx, ix, iy, ix + iw, iy + ih, ['rgba(255,255,255,0.16)', 'rgba(255,255,255,0)', [0.55, 'rgba(255,255,255,0)'], [0.6, 'rgba(255,255,255,0.1)'], 'rgba(255,255,255,0)']);
  ctx.fillRect(ix, iy, iw, ih);
  ctx.restore();
  const pw = w * 0.74, ph = 36, px = (w - pw) / 2, py = h - 16 - ph - 8;
  ctx.save();
  ctx.shadowColor = 'rgba(20,10,10,0.5)';
  ctx.shadowBlur = 4;
  ctx.shadowOffsetY = 2;
  rr(ctx, px, py, pw, ph, 5);
  fill(ctx, linear(ctx, 0, py, 0, py + ph, GOLDEN));
  ctx.restore();
  rr(ctx, px, py, pw, ph, 5);
  stroke(ctx, '#8A5A12', 1.5);
  for (const sx of [px + 7, px + pw - 7]) { circle(ctx, sx, py + ph / 2, 2.5); fill(ctx, '#8A5A12'); }
  label(ctx, P.name, w / 2, py + 13, { fam: FONT.sign, px: 14, maxW: pw - 26, fill: '#3A2208' });
  label(ctx, P.job, w / 2, py + 27, { fam: FONT.round, px: 9, maxW: pw - 26, fill: '#6A4210', track: 1 });
}
for (const hero of HERO_IDS) card(`hero_portrait_${hero}`, { w: 256, h: 320 }, (ctx, w, h) => portrait(ctx, w, h, hero, PORTRAITS[hero]));
card('portrait_baron', { w: 256, h: 320 }, (ctx, w, h) => portrait(ctx, w, h, 'baron', PORTRAITS.baron, { mood: 'grin', m: 0.3 }));
card('portrait_stormy_stu', { w: 256, h: 320 }, (ctx, w, h) => portrait(ctx, w, h, 'stormy_stu', PORTRAITS.stormy_stu));

card('magazine_tv_weekly', { w: 384, h: 512 }, (ctx, w, h) => {
  ctx.fillStyle = radial(ctx, w * 0.5, h * 0.5, 20, h * 0.7, ['#9A5ACA', '#5A2A8A', '#1E0E36']);
  ctx.fillRect(0, 0, w, h);
  ctx.save();
  ctx.translate(w / 2, h * 0.5);
  rays(ctx, 0, 0, h, 18, 'rgba(156,255,87,0.1)', 0.1);
  ctx.restore();
  for (const [x, y, s] of [[0.14, 0.3, 22], [0.86, 0.36, 26], [0.84, 0.62, 16]]) bat(ctx, w * x, h * y, s, '#140A22');
  drawBust(ctx, 'baron', w / 2, h * 0.5, 64, { mood: 'laugh', m: 0.7 });
  ctx.fillStyle = C.red;
  ctx.fillRect(0, 0, w, 86);
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 86, w, 5);
  label(ctx, 'TV', 64, 45, { fam: FONT.sign, px: 60, fill: '#FFFFFF', stroke: '#7A0E14', lw: 5 });
  label(ctx, 'WEEKLY', 238, 36, { fam: FONT.sign, px: 40, maxW: 210, fill: '#FFFFFF', stroke: '#7A0E14', lw: 5, track: 2 });
  label(ctx, 'OCT 29 – NOV 4, 1977', 238, 70, { fam: FONT.round, px: 13, fill: '#FFE9B0', track: 1 });
  label(ctx, '35¢', w - 30, 70, { fam: FONT.round, px: 14, fill: '#FFFFFF' });
  starPath(ctx, w * 0.8, h * 0.28, 50, 36, 16, 0);
  inked(ctx, linear(ctx, 0, h * 0.2, 0, h * 0.36, ['#FFF08A', '#FFD23A']), 3);
  label(ctx, 'HORROR', w * 0.8, h * 0.26, { fam: FONT.sign, px: 15, fill: C.red });
  label(ctx, 'HOST OF', w * 0.8, h * 0.285, { fam: FONT.sign, px: 11, fill: C.ink });
  label(ctx, 'THE YEAR!', w * 0.8, h * 0.31, { fam: FONT.sign, px: 13, fill: C.red });
  ctx.fillStyle = 'rgba(20,8,30,0.72)';
  ctx.fillRect(0, h * 0.8, w, h * 0.2);
  label(ctx, 'THE BARON:', w / 2, h * 0.845, { fam: FONT.sign, px: 24, fill: '#FFE14A', stroke: '#140A22', lw: 4 });
  label(ctx, '"I\'LL NEVER SIGN OFF!"', w / 2, h * 0.9, { fam: FONT.groovy, px: 30, maxW: w * 0.9, fill: '#FFFFFF', stroke: '#140A22', lw: 5 });
  label(ctx, 'TRI-COUNTY LISTINGS INSIDE', w / 2, h * 0.955, { fam: FONT.round, px: 12, fill: C.perpetua, track: 2 });
  paper(ctx, w, h, 9, 0.1);
});

card('perpetua_ad', { w: 384, h: 512 }, (ctx, w, h) => {
  ctx.fillStyle = '#F4E9D0';
  ctx.fillRect(0, 0, w, h);
  halftone(ctx, 0, 0, w, h * 0.7, 'rgba(156,255,87,0.35)', 12, (u, v) => clamp(0.9 - Math.hypot(u - 0.5, (v - 0.55) * 1.3) * 1.6, 0, 1));
  label(ctx, 'ETERNA-VISION PRESENTS', w / 2, 34, { fam: FONT.sign, px: 17, fill: C.red, track: 2 });
  const tx = w / 2, ty = h * 0.44;
  ctx.save();
  ctx.shadowColor = C.perpetua;
  ctx.shadowBlur = 30;
  ctx.beginPath();
  ctx.moveTo(tx - 58, ty + 70);
  ctx.bezierCurveTo(tx - 66, ty - 40, tx - 50, ty - 110, tx, ty - 118);
  ctx.bezierCurveTo(tx + 50, ty - 110, tx + 66, ty - 40, tx + 58, ty + 70);
  ctx.closePath();
  fill(ctx, radial(ctx, tx - 15, ty - 40, 10, 120, ['rgba(230,255,210,0.95)', 'rgba(156,255,87,0.75)', 'rgba(60,160,60,0.8)']));
  ctx.restore();
  ctx.beginPath();
  ctx.moveTo(tx - 58, ty + 70);
  ctx.bezierCurveTo(tx - 66, ty - 40, tx - 50, ty - 110, tx, ty - 118);
  ctx.bezierCurveTo(tx + 50, ty - 110, tx + 66, ty - 40, tx + 58, ty + 70);
  stroke(ctx, C.ink, 4);
  poly(ctx, [tx - 4, ty - 118, tx + 4, ty - 118, tx, ty - 132]);
  inked(ctx, '#DFF8FF', 2);
  ctx.strokeStyle = 'rgba(40,90,40,0.7)';
  ctx.lineWidth = 3;
  ctx.beginPath();
  for (const k of [-18, 18]) { ctx.moveTo(tx + k, ty + 66); ctx.lineTo(tx + k, ty + 20); }
  ctx.stroke();
  rr(ctx, tx - 66, ty + 64, 132, 44, 10);
  inked(ctx, linear(ctx, 0, ty + 64, 0, ty + 108, ['#5A5A6A', '#2A2A38']), 3);
  for (let i = 0; i < 5; i++) { rr(ctx, tx - 44 + i * 20, ty + 108, 6, 16, 2); inked(ctx, '#C9CED8', 1.5); }
  for (const s of [-1, 1]) { ellipse(ctx, tx + s * 22, ty - 46, 11, 15); inked(ctx, '#FFFFFF', 3); circle(ctx, tx + s * 22 + 3, ty - 43, 6); fill(ctx, C.ink); }
  ctx.beginPath();
  ctx.moveTo(tx - 34, ty - 12);
  ctx.quadraticCurveTo(tx, ty + 6, tx + 34, ty - 12);
  ctx.quadraticCurveTo(tx + 26, ty + 26, tx, ty + 26);
  ctx.quadraticCurveTo(tx - 26, ty + 26, tx - 34, ty - 12);
  inked(ctx, '#FFFFFF', 3);
  ctx.strokeStyle = C.ink;
  ctx.lineWidth = 2;
  ctx.beginPath();
  for (const k of [-18, -6, 6, 18]) { ctx.moveTo(tx + k, ty - 6); ctx.lineTo(tx + k, ty + 22); }
  ctx.stroke();
  const bx = w * 0.08, by = h * 0.1, bw = w * 0.5, bh = 70;
  rr(ctx, bx, by, bw, bh, 30);
  inked(ctx, '#FFFFFF', 3);
  poly(ctx, [bx + bw * 0.62, by + bh - 2, bx + bw * 0.86, by + bh + 34, bx + bw * 0.84, by + bh - 2]);
  inked(ctx, '#FFFFFF', 3);
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(bx + bw * 0.6, by + bh - 5, bw * 0.26, 6);
  label(ctx, 'NEVER', bx + bw / 2, by + 22, { fam: FONT.groovy, px: 24, fill: C.red });
  label(ctx, 'SIGN OFF AGAIN!', bx + bw / 2, by + 48, { fam: FONT.groovy, px: 22, maxW: bw * 0.88, fill: C.red });
  label(ctx, 'THE PERPETUA-TUBE', w / 2, h * 0.73, { fam: FONT.sign, px: 26, maxW: w * 0.9, fill: '#2E7A2E', stroke: '#FFFFFF', lw: 4 });
  label(ctx, 'BROADCAST FOREVER! ONLY $13.13', w / 2, h * 0.775, { fam: FONT.round, px: 15, maxW: w * 0.9, fill: C.ink });
  ctx.save();
  ctx.setLineDash([7, 5]);
  rr(ctx, 22, h * 0.81, w - 44, h * 0.16, 4);
  stroke(ctx, C.ink, 2);
  ctx.restore();
  label(ctx, 'MAIL TODAY!', w / 2, h * 0.84, { fam: FONT.sign, px: 15, fill: C.red, track: 3 });
  ctx.fillStyle = 'rgba(42,29,58,0.55)';
  for (let i = 0; i < 3; i++) ctx.fillRect(40, h * 0.87 + i * 14, w - 80, 1.5);
  paper(ctx, w, h, 13, 0.14);
});

card('ticket_stub', { w: 256, h: 128, alpha: true }, (ctx, w, h) => {
  ctx.beginPath();
  const n = 9, R = h / (n * 2);
  ctx.moveTo(10, 8);
  ctx.lineTo(w - 10, 8);
  for (let i = 0; i < n; i++) ctx.arc(w - 10, 8 + R + i * 2 * R * ((h - 16) / h), R * 0.7, -Math.PI / 2, Math.PI / 2, true);
  ctx.lineTo(10, h - 8);
  for (let i = n - 1; i >= 0; i--) ctx.arc(10, 8 + R + i * 2 * R * ((h - 16) / h), R * 0.7, Math.PI / 2, -Math.PI / 2, true);
  ctx.closePath();
  inked(ctx, linear(ctx, 0, 0, 0, h, ['#FF9A4A', C.orange, '#C84E1A']), 2.5, '#7A2A0E');
  ctx.save();
  ctx.clip();
  grain(ctx, w, h, 0.12, 3);
  ctx.restore();
  ctx.save();
  ctx.setLineDash([4, 4]);
  ctx.beginPath();
  ctx.moveTo(w * 0.7, 12);
  ctx.lineTo(w * 0.7, h - 12);
  stroke(ctx, '#7A2A0E', 2);
  ctx.restore();
  rr(ctx, 22, 18, w * 0.7 - 34, h - 36, 6);
  stroke(ctx, alpha('#FFF1D0', 0.85), 2);
  label(ctx, 'ADMIT ONE', (w * 0.7) / 2 + 6, 38, { fam: FONT.sign, px: 20, maxW: w * 0.55, fill: '#FFF8E8', stroke: '#7A2A0E', lw: 3.5 });
  label(ctx, 'WZTV STUDIO AUDIENCE', (w * 0.7) / 2 + 6, h - 32, { fam: FONT.round, px: 10, maxW: w * 0.56, fill: '#FFF1D0', track: 1 });
  label(ctx, 'No. 001313', (w * 0.7) / 2 + 6, h - 50, { fam: FONT.type, px: 11, fill: '#5A1A08' });
  label(ctx, '13', w * 0.85, h * 0.52, { fam: FONT.round, px: 50, fill: '#FFF8E8', stroke: '#7A2A0E', lw: 5, depth: 3, depthFill: '#7A2A0E' });
});

card('badge_crew', { w: 256, h: 160 }, (ctx, w, h) => {
  ctx.fillStyle = '#5A6078';
  ctx.fillRect(0, 0, w, h);
  rr(ctx, 4, 4, w - 8, h - 8, 14);
  fill(ctx, '#FFFDF6');
  ctx.save();
  rr(ctx, 4, 4, w - 8, h - 8, 14);
  ctx.clip();
  ctx.fillStyle = linear(ctx, 0, 0, 0, 52, [lighten(C.blue, 0.1), C.blue]);
  ctx.fillRect(0, 0, w, 52);
  ctx.fillStyle = C.red;
  ctx.fillRect(0, 52, w, 5);
  ctx.fillStyle = C.gold;
  ctx.fillRect(0, h - 22, w, 18);
  ctx.restore();
  rr(ctx, w / 2 - 22, 12, 44, 10, 5);
  fill(ctx, '#1E3A8A');
  drawLogo(ctx, w * 0.5, 36, 17, { style: 'flat' });
  label(ctx, 'CREW', w * 0.5, 94, { fam: FONT.sign, px: 46, fill: C.red, stroke: '#7A0E14', lw: 2, track: 4 });
  label(ctx, 'ALL AREAS', w * 0.5, h - 13, { fam: FONT.round, px: 11, fill: '#5A3A08', track: 3 });
  rr(ctx, 4, 4, w - 8, h - 8, 14);
  stroke(ctx, '#2A2438', 3);
  gloss(ctx, 4, 4, w - 8, h - 8, 14, 0.3);
});

card('cap_13', { w: 128, h: 128, alpha: true }, (ctx, w, h) => {
  const r = w * 0.46;
  badge13(ctx, w / 2, h / 2, r, { disc: '#FFFFFF', ring: C.red, num: C.blue, ol: 3 });
  ctx.save();
  ctx.setLineDash([3, 3]);
  circle(ctx, w / 2, h / 2, r * 0.9);
  stroke(ctx, 'rgba(255,255,255,0.75)', 1.2);
  ctx.restore();
});

/** The Baron's dressing room as painted for the porthole: bulb mirror with a lipstick "13", fan mail, plaque, wig stand. */
function baronRoom(ctx, w, h) {
  ctx.fillStyle = '#4A2450';
  ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = 'rgba(255,79,160,0.12)';
  for (let x = 0; x < w; x += 22) ctx.fillRect(x, 0, 10, h * 0.66);
  ctx.fillStyle = linear(ctx, 0, h * 0.66, 0, h, ['#6A3A22', '#3E2014']);
  ctx.fillRect(0, h * 0.66, w, h * 0.34);
  const mx = w * 0.42, my = h * 0.36, mw = 118, mh = 96;
  rr(ctx, mx - mw / 2 - 12, my - mh / 2 - 12, mw + 24, mh + 24, 14);
  inked(ctx, '#E8D8C0', 2);
  rr(ctx, mx - mw / 2, my - mh / 2, mw, mh, 8);
  fill(ctx, linear(ctx, mx - mw / 2, my - mh / 2, mx + mw / 2, my + mh / 2, ['#DDEBF4', '#9AB4C8', '#C8DCE8']));
  ctx.fillStyle = 'rgba(255,255,255,0.4)';
  poly(ctx, [mx - 40, my - mh / 2, mx - 20, my - mh / 2, mx - 56, my + mh / 2, mx - 59, my + mh / 2, mx - 59, my + 10]);
  ctx.fill();
  label(ctx, '13', mx + 6, my + 4, { fam: FONT.groovy, px: 56, fill: 'rgba(210,30,60,0.85)', rot: -0.12 });
  for (let i = 0; i < 14; i++) {
    const u = i / 13, per = 2 * (mw + mh + 24 * 2), d = u * per;
    let bx, by;
    const W = mw + 24, H = mh + 24;
    if (d < W) { bx = mx - W / 2 + d; by = my - H / 2; } else if (d < W + H) { bx = mx + W / 2; by = my - H / 2 + d - W; } else if (d < 2 * W + H) { bx = mx + W / 2 - (d - W - H); by = my + H / 2; } else { bx = mx - W / 2; by = my + H / 2 - (d - 2 * W - H); }
    circle(ctx, bx, by, 5);
    ctx.save();
    ctx.shadowColor = '#FFD08A';
    ctx.shadowBlur = 8;
    fill(ctx, '#FFF4C8');
    ctx.restore();
  }
  ctx.fillStyle = linear(ctx, 0, h * 0.64, 0, h * 0.72, ['#8A5A3A', '#5A3420']);
  ctx.fillRect(0, h * 0.64, w, h * 0.08);
  const r = rng(76);
  for (let i = 0; i < 7; i++) {
    const ex = 20 + i * 14 + r() * 6, ey = h * 0.6 - (i % 3) * 4;
    ctx.save();
    ctx.translate(ex, ey);
    ctx.rotate((r() - 0.5) * 0.6);
    rr(ctx, -14, -9, 28, 18, 2);
    inked(ctx, i % 2 ? '#FFF4DC' : '#FFDDE8', 1.2);
    poly(ctx, [-14, -9, 0, 1, 14, -9], false);
    stroke(ctx, '#B8A080', 1);
    heart(ctx, 7, 3, 5, C.red, 0);
    ctx.restore();
  }
  const px = w * 0.86, py = h * 0.32;
  rr(ctx, px - 24, py - 32, 48, 64, 5);
  inked(ctx, linear(ctx, 0, py - 32, 0, py + 32, ['#6A3A22', '#3E2014']), 2);
  rr(ctx, px - 18, py - 26, 36, 52, 3);
  fill(ctx, linear(ctx, 0, py - 26, 0, py + 26, GOLDEN));
  rr(ctx, px - 8, py - 16, 16, 12, 3);
  inked(ctx, '#B07A16', 1);
  label(ctx, 'HOST', px, py + 6, { fam: FONT.sign, px: 7, fill: '#5A3A08' });
  label(ctx, '1976', px, py + 16, { fam: FONT.sign, px: 8, fill: '#5A3A08' });
  const wx = w * 0.84, wy = h * 0.58;
  capsule(ctx, wx, wy + 8, wx, wy + 40, 5, '#C9CED8', C.ink, 1.2);
  ellipse(ctx, wx, wy + 42, 16, 5);
  inked(ctx, '#8A90A8', 1.2);
  ellipse(ctx, wx, wy - 8, 15, 19);
  inked(ctx, '#F4F1E8', 1.5);
  vignette(ctx, w, h, 0.5, '20,8,24', 0.4);
}
card('baron_dressing_room', { w: 256, h: 256 }, (ctx, w, h) => baronRoom(ctx, w, h));

const DOORS = {
  skip: { name: 'SKIP', col: '#3A6AC8' },
  roxy: { name: 'ROXY', col: '#D8467A' },
  penny: { name: 'PENNY', col: '#E3662B' },
  duke: { name: 'DUKE', col: '#8A5A2A' },
  baron: { name: 'THE BARON', col: '#4A2A5A' },
};
card('dressing_room_doors', { w: 256, h: 512, opts: 'who: skip | roxy | penny | duke | baron (porthole with the painted interior)' }, (ctx, w, h, t, o) => {
  const who = DOORS[o.who] ? o.who : 'skip', D = DOORS[who];
  ctx.fillStyle = linear(ctx, 0, 0, w, 0, [darken(D.col, 0.1), lighten(D.col, 0.08), darken(D.col, 0.15)]);
  ctx.fillRect(0, 0, w, h);
  for (const [y, ph] of [[who === 'baron' ? 250 : 200, 110], [380, 100]]) {
    rr(ctx, 30, y, w - 60, ph, 8);
    fill(ctx, darken(D.col, 0.08));
    rr(ctx, 30, y, w - 60, ph, 8);
    stroke(ctx, alpha('#FFFFFF', 0.25), 3);
    rr(ctx, 33, y + 3, w - 66, ph - 6, 6);
    stroke(ctx, alpha('#1E1030', 0.35), 2);
  }
  if (who === 'baron') {
    const cx = w / 2, cy = 110, R = 62;
    ctx.save();
    circle(ctx, cx, cy, R);
    ctx.clip();
    ctx.drawImage(layer('baron_room', 256, 256, baronRoom), cx - R * 1.25, cy - R * 1.25, R * 2.5, R * 2.5);
    ctx.fillStyle = linear(ctx, cx - R, cy - R, cx + R, cy + R, ['rgba(255,255,255,0.3)', 'rgba(255,255,255,0)', [0.6, 'rgba(255,255,255,0)'], 'rgba(255,255,255,0.12)']);
    ctx.fillRect(cx - R, cy - R, R * 2, R * 2);
    ctx.restore();
    circle(ctx, cx, cy, R + 7);
    stroke(ctx, C.brass, 12);
    circle(ctx, cx, cy, R + 7);
    stroke(ctx, '#8A5A12', 1.5);
    for (let i = 0; i < 8; i++) { const a = (i / 8) * TAU; circle(ctx, cx + Math.cos(a) * (R + 7), cy + Math.sin(a) * (R + 7), 2.5); fill(ctx, '#8A5A12'); }
  }
  const sy = who === 'baron' ? 206 : 110;
  starPath(ctx, w / 2, sy, who === 'baron' ? 36 : 62, who === 'baron' ? 16 : 28, 5);
  ctx.save();
  ctx.shadowColor = 'rgba(20,10,20,0.4)';
  ctx.shadowBlur = 6;
  ctx.shadowOffsetY = 3;
  fill(ctx, linear(ctx, 0, sy - 62, 0, sy + 50, GOLDEN));
  ctx.restore();
  starPath(ctx, w / 2, sy, who === 'baron' ? 36 : 62, who === 'baron' ? 16 : 28, 5);
  stroke(ctx, '#8A5A12', 2);
  sparkle(ctx, w / 2 - 20, sy - 22, 8);
  const ny = who === 'baron' ? 236 : 170;
  rr(ctx, 44, ny - 1, w - 88, 26, 5);
  inked(ctx, '#FFFDF2', 2, '#5A3A08');
  label(ctx, D.name, w / 2, ny + 12, { fam: FONT.sign, px: 17, maxW: w - 104, fill: '#2A1D3A' });
  const kx = w - 34, ky = 330;
  rr(ctx, kx - 9, ky - 26, 18, 52, 6);
  inked(ctx, linear(ctx, 0, ky - 26, 0, ky + 26, GOLDEN), 1.5, '#8A5A12');
  circle(ctx, kx, ky, 11);
  inked(ctx, radial(ctx, kx - 3, ky - 3, 0, 12, ['#FFF6C8', C.gold, '#9A6A10']), 1.5, '#8A5A12');
  ctx.fillStyle = linear(ctx, 0, h - 40, 0, h, ['#E8ECF6', '#8A90A8']);
  ctx.fillRect(0, h - 36, w, 36);
  ctx.fillStyle = 'rgba(30,16,30,0.25)';
  ctx.fillRect(0, 0, 6, h);
  ctx.fillRect(w - 6, 0, 6, h);
  grain(ctx, w, h, 0.08, hash(who) & 255);
});

// ---------------------------------------------------------------------------------------------------------
// Title logo and station extras: flinch fallback, exhibit sign, light boxes, clock, reel label, crack
// ---------------------------------------------------------------------------------------------------------

card('logo_dead_air', { w: 512, h: 256, alpha: true }, (ctx, w, h) => {
  const str = 'Dead Air', cx = w / 2, cy = h * 0.44;
  ctx.save();
  const px = fitFont(ctx, str, FONT.groovy, 124, w * 0.9);
  const tw = ctx.measureText(str).width, iX = cx - tw / 2 + ctx.measureText('Dead A').width + ctx.measureText('i').width / 2;
  ctx.restore();
  // rabbit-ear antennas on the "i"
  const ay = cy - px * 0.52;
  for (const s of [-1, 1]) {
    capsule(ctx, iX, ay, iX + s * px * 0.32, ay - px * 0.46, px * 0.045, '#D5DAE8', C.ink, 3);
    circle(ctx, iX + s * px * 0.32, ay - px * 0.46, px * 0.06);
    inked(ctx, s < 0 ? NEON.W : NEON.V, 3);
  }
  const stripes = [[C.plum, 13], [C.red, 9], [C.orange, 5]];
  for (const [col, d] of stripes) label(ctx, str, cx + d * 0.7, cy + d, { fam: FONT.groovy, px, fill: col, stroke: C.ink, lw: px * 0.07 });
  label(ctx, str, cx, cy, { fam: FONT.groovy, px, fill: vgrad(['#FFFBEA', '#FFE28A', '#FFB347', '#E3662B']), stroke: C.ink, lw: px * 0.08 });
  const tex = makeCanvas(w, h), g = tex.getContext('2d');
  label(g, str, cx, cy, { fam: FONT.groovy, px, fill: '#FFFFFF' });
  g.globalCompositeOperation = 'source-in';
  g.fillStyle = linear(g, 0, cy - px * 0.5, 0, cy - px * 0.1, ['rgba(255,255,255,0.75)', 'rgba(255,255,255,0)']);
  g.fillRect(0, 0, w, h);
  ctx.drawImage(tex, -px * 0.02, -px * 0.03);
  sparkle(ctx, cx - tw * 0.36, cy - px * 0.28, 14);
  sparkle(ctx, cx + tw * 0.42, cy + px * 0.12, 10);
  ribbon(ctx, cx, h * 0.83, w * 0.62, 34, C.blue);
  label(ctx, 'LIVE FROM WZTV CHANNEL 13', cx, h * 0.835, { fam: FONT.sign, px: 17, maxW: w * 0.58, fill: '#FFFFFF', stroke: '#141040', lw: 3, track: 1 });
});

card('flinch', { w: 512, h: 384, opts: 'fallback freeze-frame when no feed frame exists' }, (ctx, w, h) => {
  ctx.fillStyle = radial(ctx, w * 0.5, h * 0.45, 10, w * 0.7, ['#FFFFFF', '#FFF1C8', '#F2C27A', '#B07A45']);
  ctx.fillRect(0, 0, w, h);
  rays(ctx, w * 0.5, h * 0.4, w, 20, 'rgba(255,255,255,0.55)', 0.1);
  const j = picto(ctx, w * 0.5, h * 0.62, h * 0.52, { lean: -10, head: [-0.6, 0.4], la: [-150, 150], ra: [140, -160], ll: [-14, -4], rl: [18, 30] }, '#3A2A4A');
  for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(j.head[0], j.head[1], j.u * (2.2 + i * 0.9), -2.6, -0.6); stroke(ctx, alpha('#3A2A4A', 0.55 - i * 0.12), 3); }
  for (const [x, y, r] of [[0.3, 0.2, 10], [0.72, 0.26, 8]]) { starPath(ctx, w * x, h * y, r, r * 0.45, 5); inked(ctx, '#FFE14A', 2); }
  ctx.fillStyle = 'rgba(160,110,60,0.2)';
  ctx.fillRect(0, 0, w, h);
  grain(ctx, w, h, 0.25, 4);
  const fb = 30;
  ctx.fillStyle = '#1E1624';
  ctx.fillRect(0, 0, w, fb);
  ctx.fillRect(0, h - fb, w, fb);
  ctx.fillStyle = '#FFF4DC';
  for (let x = 10; x < w; x += 34) { rr(ctx, x, 9, 18, 12, 3); ctx.fill(); rr(ctx, x, h - 21, 18, 12, 3); ctx.fill(); }
  ctx.strokeStyle = 'rgba(30,22,36,0.8)';
  ctx.lineWidth = 6;
  ctx.strokeRect(3, fb, w - 6, h - fb * 2);
  vignette(ctx, w, h, 0.45, '40,24,20', 0.4);
});

card('sign_see_yourself', { w: 512, h: 256 }, (ctx, w, h) => {
  rr(ctx, 0, 0, w, h, 16);
  fill(ctx, linear(ctx, 0, 0, 0, h, ['#FFF4DC', '#F2DDB0']));
  ctx.save();
  rr(ctx, 0, 0, w, h, 16);
  ctx.clip();
  rays(ctx, w * 0.2, h * 0.55, w, 18, 'rgba(232,169,46,0.22)', 0.1);
  ctx.fillStyle = C.red;
  ctx.fillRect(0, h - 26, w, 26);
  grain(ctx, w, h, 0.1, 8);
  ctx.restore();
  rr(ctx, 5, 5, w - 10, h - 10, 12);
  stroke(ctx, C.walnut, 6);
  const tx = w * 0.19, ty = h * 0.46, tw = 124, th = 100;
  rr(ctx, tx - tw / 2, ty - th / 2, tw, th, 16);
  inked(ctx, linear(ctx, 0, ty - th / 2, 0, ty + th / 2, ['#B27A45', '#6A3C20']), 3);
  rr(ctx, tx - tw / 2 + 10, ty - th / 2 + 10, tw * 0.66, th - 20, 12);
  inked(ctx, linear(ctx, 0, ty - th / 2, 0, ty + th / 2, ['#7FE7FF', '#2E8CB8']), 2.5);
  const j = picto(ctx, tx - tw * 0.1, ty + 10, 58, { la: [-150, -170], ra: [150, 170] }, C.ink);
  circle(ctx, j.head[0] - 3, j.head[1], 1.6);
  fill(ctx, '#FFFFFF');
  circle(ctx, j.head[0] + 3, j.head[1], 1.6);
  fill(ctx, '#FFFFFF');
  circle(ctx, tx + tw * 0.34, ty - 18, 9);
  inked(ctx, '#F6E7C8', 2);
  circle(ctx, tx + tw * 0.34, ty + 12, 7);
  inked(ctx, '#F6E7C8', 2);
  for (const s of [-1, 1]) capsule(ctx, tx - 6, ty - th / 2, tx - 6 + s * 30, ty - th / 2 - 36, 3, '#C9CED8', C.ink, 1.5);
  label(ctx, 'SEE YOURSELF', w * 0.64, h * 0.3, { fam: FONT.sign, px: 38, maxW: w * 0.58, fill: C.blue, stroke: '#FFFFFF', lw: 5 });
  label(ctx, 'ON CHANNEL', w * 0.6, h * 0.53, { fam: FONT.sign, px: 30, maxW: w * 0.5, fill: C.red, stroke: '#FFFFFF', lw: 5 });
  badge13(ctx, w * 0.88, h * 0.53, 28, { ol: 2.5 });
  label(ctx, 'STEP RIGHT UP! YOU\'RE ON TV!', w * 0.6, h * 0.74, { fam: FONT.round, px: 16, maxW: w * 0.6, fill: C.choc, track: 1 });
  poly(ctx, [w * 0.93, h * 0.84, w * 0.85, h * 0.78, w * 0.85, h * 0.81, w * 0.74, h * 0.81, w * 0.74, h * 0.87, w * 0.85, h * 0.87, w * 0.85, h * 0.9]);
  inked(ctx, C.gold, 2);
  label(ctx, 'WZTV 13 STUDIO TOUR', w / 2, h - 13, { fam: FONT.round, px: 13, fill: '#FFFFFF', track: 3 });
});

/** Studio light box (APPLAUSE / ON AIR): glass panel in a black housing; lit glows. */
function lightBox(ctx, w, h, str, lit, glass, bulbs) {
  rr(ctx, 2, 2, w - 4, h - 4, h * 0.2);
  fill(ctx, linear(ctx, 0, 0, 0, h, ['#3A3448', '#1A1624']));
  rr(ctx, 2, 2, w - 4, h - 4, h * 0.2);
  stroke(ctx, '#0E0A14', 3);
  const m = h * 0.16, gx = m, gy = m, gw = w - m * 2, gh = h - m * 2;
  rr(ctx, gx, gy, gw, gh, h * 0.1);
  fill(ctx, lit ? radial(ctx, w / 2, h / 2, 0, w * 0.6, [lighten(glass, 0.35), glass, darken(glass, 0.25)]) : linear(ctx, 0, gy, 0, gy + gh, [darken(glass, 0.45), darken(glass, 0.62)]));
  if (bulbs) {
    const n = Math.floor(gw / 26);
    for (let i = 0; i < n; i++) for (const yy of [gy + 9, gy + gh - 9]) {
      const bx = gx + 13 + i * ((gw - 26) / (n - 1));
      circle(ctx, bx, yy, 5);
      if (lit) { ctx.save(); ctx.shadowColor = '#FFE0A0'; ctx.shadowBlur = 8; fill(ctx, '#FFF4D0'); ctx.restore(); } else fill(ctx, '#6A5A50');
    }
  }
  const px = gh * (bulbs ? 0.46 : 0.62);
  if (lit) label(ctx, str, w / 2, h / 2 + 2, { fam: FONT.sign, px, maxW: gw * 0.86, fill: '#FFFFFF', glow: lighten(glass, 0.4), glowBlur: px * 0.5, track: 3 });
  else label(ctx, str, w / 2, h / 2 + 2, { fam: FONT.sign, px, maxW: gw * 0.86, fill: alpha(lighten(glass, 0.2), 0.45), track: 3 });
  gloss(ctx, gx, gy, gw, gh, h * 0.1, lit ? 0.25 : 0.12);
}
card('applause_sign', { w: 512, h: 160, opts: 'lit: false = dark box' }, (ctx, w, h, t, o) => lightBox(ctx, w, h, 'APPLAUSE', o.lit !== false, '#E4302A', true));
card('on_air', { w: 256, h: 96, opts: 'lit: false = dark box' }, (ctx, w, h, t, o) => lightBox(ctx, w, h, 'ON AIR', o.lit !== false, C.onAir, false));

card('clock_face', { w: 256, h: 256, alpha: true, opts: 'hands: false = dial only; time: [h, m, s] (default 11:59:58)' }, (ctx, w, h, t, o) => {
  const cx = w / 2, cy = h / 2, R = w * 0.47;
  circle(ctx, cx, cy, R);
  fill(ctx, linear(ctx, 0, cy - R, 0, cy + R, ['#FFB347', C.orange, C.rust]));
  circle(ctx, cx, cy, R);
  stroke(ctx, C.ink, 3);
  circle(ctx, cx, cy, R * 0.86);
  fill(ctx, radial(ctx, cx - R * 0.2, cy - R * 0.25, 0, R, ['#FFFDF4', '#F6E7C8', '#E8D2A8']));
  circle(ctx, cx, cy, R * 0.86);
  stroke(ctx, C.choc, 2.5);
  ctx.strokeStyle = C.ink;
  for (let i = 0; i < 60; i++) {
    const a = (i / 60) * TAU, big = i % 5 === 0;
    ctx.lineWidth = big ? 4 : 1.5;
    ctx.beginPath();
    ctx.moveTo(cx + Math.sin(a) * R * (big ? 0.7 : 0.76), cy - Math.cos(a) * R * (big ? 0.7 : 0.76));
    ctx.lineTo(cx + Math.sin(a) * R * 0.82, cy - Math.cos(a) * R * 0.82);
    ctx.stroke();
  }
  for (const [n, a] of [['12', 0], ['3', 0.25], ['6', 0.5], ['9', 0.75]]) label(ctx, n, cx + Math.sin(a * TAU) * R * 0.55, cy - Math.cos(a * TAU) * R * 0.55 + 2, { fam: FONT.round, px: 26, fill: C.choc });
  badge13(ctx, cx, cy + R * 0.3, R * 0.14, { ol: 1.5 });
  if (o.hands !== false) {
    const [hh, mm, ss] = o.time || [11, 59, 58];
    const hand = (a, len, wd, col) => capsule(ctx, cx - Math.sin(a) * len * 0.15, cy + Math.cos(a) * len * 0.15, cx + Math.sin(a) * len, cy - Math.cos(a) * len, wd, col, C.ink, 1.5);
    hand(((hh % 12) + mm / 60) / 12 * TAU, R * 0.42, 9, C.choc);
    hand((mm + ss / 60) / 60 * TAU, R * 0.66, 6, C.choc);
    hand((ss / 60) * TAU, R * 0.72, 2.5, C.red);
    circle(ctx, cx, cy, 6);
    inked(ctx, C.gold, 1.5);
  }
  ctx.save();
  circle(ctx, cx, cy, R * 0.86);
  ctx.clip();
  ctx.fillStyle = linear(ctx, cx - R, cy - R, cx, cy, ['rgba(255,255,255,0.45)', 'rgba(255,255,255,0)']);
  ctx.beginPath();
  ctx.ellipse(cx - R * 0.25, cy - R * 0.35, R * 0.6, R * 0.3, -0.5, 0, TAU);
  ctx.fill();
  ctx.restore();
});

card('reel_label', { w: 128, h: 128, alpha: true, opts: 'hub label for the quad tape reel' }, (ctx, w, h) => {
  circle(ctx, w / 2, h / 2, w * 0.46);
  inked(ctx, '#FFFDF4', 2.5, '#B8A890');
  circle(ctx, w / 2, h / 2, w * 0.14);
  inked(ctx, '#8A90A8', 2, '#4A4E60');
  label(ctx, '13', w * 0.5, h * 0.23, { fam: FONT.round, px: 24, fill: '#D8322B', rot: -0.1 });
  label(ctx, 'SIGN-OFF', w * 0.5, h * 0.77, { fam: FONT.round, px: 13, fill: '#2A2438', rot: 0.05 });
});

card('crack_overlay', { w: 512, h: 384, alpha: true, opts: 'transparent cracked-glass overlay (boss screen at 66%)' }, (ctx, w, h) => {
  const r = rng(66), ox = w * 0.68, oy = h * 0.32;
  const lines = [];
  for (let i = 0; i < 11; i++) {
    const a = (i / 11) * TAU + r() * 0.4;
    let x = ox, y = oy;
    const pts = [x, y];
    const len = 60 + r() * 260, steps = 6;
    for (let k = 1; k <= steps; k++) { const aa = a + (r() - 0.5) * 0.5, d = (len / steps) * (0.6 + r() * 0.8); x += Math.cos(aa) * d; y += Math.sin(aa) * d; pts.push(x, y); }
    lines.push(pts);
  }
  for (let k = 1; k <= 3; k++) {
    const ring = [];
    for (let i = 0; i <= 11; i++) { const a = (i / 11) * TAU, rr0 = k * 34 * (0.8 + r() * 0.4); ring.push(ox + Math.cos(a) * rr0, oy + Math.sin(a) * rr0); }
    lines.push(ring);
  }
  const draw = (col, lw) => {
    ctx.strokeStyle = col;
    ctx.lineWidth = lw;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    for (const pts of lines) { poly(ctx, pts, false); ctx.stroke(); }
  };
  draw('rgba(20,16,40,0.6)', 5.5);
  draw('rgba(240,250,255,0.95)', 2.2);
  circle(ctx, ox, oy, 12);
  fill(ctx, radial(ctx, ox, oy, 0, 14, ['rgba(255,255,255,0.9)', 'rgba(255,255,255,0.2)']));
});
