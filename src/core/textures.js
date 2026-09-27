// Canvas texture helpers (ARCHITECTURE §6). Every helper returns a cached THREE.CanvasTexture in sRGB,
// keyed by its arguments, so equal requests share one GPU texture. Patterns are deterministic (seeded).
// staticNoise() is the single animated TV-snow texture shared by zombie eyes and snowy screens (GDD §3.5);
// Game calls textures.update() every frame, which re-randomizes it at ~24 Hz.

import * as THREE from 'three';
import { mulberry32 } from './rng.js';
import { PAL } from './config.js';

const cache = new Map();
let anisotropy = 4;

function hashStr(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

function makeCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

function finish(canvas, { repeat = true, srgb = true } = {}) {
  const t = new THREE.CanvasTexture(canvas);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = anisotropy;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.needsUpdate = true;
  return t;
}

// Cache wrapper: builder(ctx, canvas, rand) draws; returns the shared texture for `key`.
function cached(key, w, h, builder, opts) {
  let t = cache.get(key);
  if (t) return t;
  const canvas = makeCanvas(w, h);
  const ctx = canvas.getContext('2d');
  builder(ctx, canvas, mulberry32(hashStr(key)));
  t = finish(canvas, opts);
  t.name = key;
  cache.set(key, t);
  return t;
}

function shade(hex, amt) {
  const c = new THREE.Color(hex);
  if (amt >= 0) c.lerp(new THREE.Color(1, 1, 1), amt);
  else c.multiplyScalar(1 + amt);
  return '#' + c.getHexString();
}

// Tartan: `lines` = [[color, width(0..1 of tile), offset(0..1)], ...] woven both ways over `base`.
export function plaid(base, lines = [], scale = 1) {
  const t = cached(`plaid|${base}|${JSON.stringify(lines)}`, 256, 256, (ctx, c, rand) => {
    ctx.fillStyle = base; ctx.fillRect(0, 0, 256, 256);
    for (const [color, w, o] of lines) {
      ctx.fillStyle = color;
      ctx.globalAlpha = 0.55;
      ctx.fillRect(0, o * 256, 256, w * 256);
      ctx.fillRect(o * 256, 0, w * 256, 256);
    }
    // Twill weave: fine diagonal hatching gives the cloth a woven feel.
    ctx.globalAlpha = 0.07;
    ctx.strokeStyle = '#000';
    for (let i = -256; i < 256; i += 4) {
      ctx.beginPath(); ctx.moveTo(i, 256); ctx.lineTo(i + 256, 0); ctx.stroke();
    }
    ctx.globalAlpha = 0.05;
    for (let i = 0; i < 900; i++) {
      ctx.fillStyle = rand() < 0.5 ? '#fff' : '#000';
      ctx.fillRect(rand() * 256, rand() * 256, 2, 1);
    }
    ctx.globalAlpha = 1;
  });
  return withRepeat(t, scale, scale);
}

// Equal-width color stripes, repeated `count` bands in total.
export function stripes(colors, vertical = true, count = colors.length) {
  return cached(`stripes|${colors.join(',')}|${vertical}|${count}`, 256, 256, (ctx) => {
    const n = Math.max(1, count);
    const step = 256 / n;
    for (let i = 0; i < n; i++) {
      ctx.fillStyle = colors[i % colors.length];
      if (vertical) ctx.fillRect(Math.floor(i * step), 0, Math.ceil(step), 256);
      else ctx.fillRect(0, Math.floor(i * step), 256, Math.ceil(step));
    }
    // A soft fabric sheen between stripes.
    ctx.globalAlpha = 0.08;
    ctx.fillStyle = '#000';
    for (let i = 1; i < n; i++) {
      if (vertical) ctx.fillRect(Math.floor(i * step) - 1, 0, 2, 256);
      else ctx.fillRect(0, Math.floor(i * step) - 1, 256, 2);
    }
    ctx.globalAlpha = 1;
  });
}

// Cartoonized SMPTE color bars (GDD §3.2) with the reverse-blue strip and PLUGE row.
export function colorBars() {
  return cached('colorBars', 256, 192, (ctx) => {
    const bars = PAL.BARS;
    const w = 256 / 7;
    bars.forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(Math.floor(i * w), 0, Math.ceil(w), 128); });
    const rev = [PAL.barBlue, '#141018', PAL.barMagenta, '#141018', PAL.barCyan, '#141018', PAL.barWhite];
    rev.forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(Math.floor(i * w), 128, Math.ceil(w), 16); });
    const pluge = ['#1D2A5C', '#F4F1E8', '#3A1D5C', '#141018', '#0E0B12', '#141018', '#1A1620'];
    const pw = [46, 46, 46, 46, 24, 24, 24];
    let x = 0;
    pluge.forEach((c, i) => { ctx.fillStyle = c; ctx.fillRect(x, 144, pw[i] + 1, 48); x += pw[i]; });
  }, { repeat: false });
}

// Text label. opts: { font='Bungee', size=64, color='#fff', bg=null, w, h, align='center', pad=0.18, weight='' }
export function text(str, opts = {}) {
  const { font = 'Bungee', size = 64, color = '#ffffff', bg = null, align = 'center', pad = 0.18, weight = '' } = opts;
  const probe = makeCanvas(4, 4).getContext('2d');
  const fontStr = `${weight} ${size}px "${font}", "Arial Black", sans-serif`.trim();
  probe.font = fontStr;
  const lines = String(str).split('\n');
  const tw = Math.max(...lines.map((l) => probe.measureText(l).width));
  const w = opts.w || Math.min(1024, THREE.MathUtils.ceilPowerOfTwo(Math.ceil(tw + size * pad * 2)));
  const h = opts.h || Math.min(1024, THREE.MathUtils.ceilPowerOfTwo(Math.ceil(size * (lines.length * 1.2 + pad * 2))));
  return cached(`text|${str}|${JSON.stringify(opts)}`, w, h, (ctx) => {
    if (bg) { ctx.fillStyle = bg; ctx.fillRect(0, 0, w, h); }
    ctx.font = fontStr;
    ctx.fillStyle = color;
    ctx.textBaseline = 'middle';
    ctx.textAlign = align;
    const x = align === 'left' ? size * pad : align === 'right' ? w - size * pad : w / 2;
    const lh = size * 1.2;
    const y0 = h / 2 - ((lines.length - 1) * lh) / 2;
    lines.forEach((l, i) => ctx.fillText(l, x, y0 + i * lh));
  }, { repeat: false });
}

// Lacquered walnut paneling: vertical planks, grooves and flowing grain.
export function woodPanel(base = PAL.walnut) {
  return cached(`wood|${base}`, 256, 256, (ctx, c, rand) => {
    ctx.fillStyle = base; ctx.fillRect(0, 0, 256, 256);
    const planks = 4;
    const pw = 256 / planks;
    for (let p = 0; p < planks; p++) {
      const x0 = p * pw;
      ctx.fillStyle = shade(base, (rand() - 0.5) * 0.16);
      ctx.fillRect(x0, 0, pw, 256);
      ctx.lineWidth = 1.2;
      for (let g = 0; g < 9; g++) {
        const gx = x0 + rand() * pw;
        const amp = 2 + rand() * 5;
        const freq = 0.01 + rand() * 0.02;
        ctx.strokeStyle = shade(base, -0.25 - rand() * 0.15);
        ctx.globalAlpha = 0.35 + rand() * 0.3;
        ctx.beginPath();
        for (let y = 0; y <= 256; y += 8) {
          const x = gx + Math.sin(y * freq + g) * amp;
          if (y === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
      ctx.fillStyle = shade(base, -0.55);
      ctx.fillRect(x0, 0, 2, 256);
      ctx.fillStyle = shade(base, 0.18);
      ctx.fillRect(x0 + 2, 0, 1, 256);
    }
  });
}

// Shag carpet: dense colored flecks over a base.
export function carpet(base = PAL.shagOrange, fleck = PAL.harvestGold) {
  return cached(`carpet|${base}|${fleck}`, 256, 256, (ctx, c, rand) => {
    ctx.fillStyle = base; ctx.fillRect(0, 0, 256, 256);
    const dark = shade(base, -0.3);
    const light = shade(base, 0.15);
    for (let i = 0; i < 5200; i++) {
      const r = rand();
      ctx.fillStyle = r < 0.45 ? dark : r < 0.85 ? light : fleck;
      ctx.globalAlpha = 0.35 + rand() * 0.5;
      const x = rand() * 256, y = rand() * 256;
      ctx.beginPath();
      ctx.ellipse(x, y, 1 + rand() * 1.6, 1 + rand() * 1.6, 0, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  });
}

// Checker tiles (n x n per texture) with soft grout and a faint gloss.
export function tiles(a = '#E8E1D0', b = '#B5472A', n = 4) {
  return cached(`tiles|${a}|${b}|${n}`, 256, 256, (ctx, c, rand) => {
    const s = 256 / n;
    for (let y = 0; y < n; y++) {
      for (let x = 0; x < n; x++) {
        ctx.fillStyle = shade((x + y) % 2 ? b : a, (rand() - 0.5) * 0.06);
        ctx.fillRect(x * s, y * s, s, s);
      }
    }
    ctx.strokeStyle = 'rgba(40,24,30,0.35)';
    ctx.lineWidth = 2;
    for (let i = 0; i <= n; i++) {
      ctx.beginPath(); ctx.moveTo(i * s, 0); ctx.lineTo(i * s, 256); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(0, i * s); ctx.lineTo(256, i * s); ctx.stroke();
    }
  });
}

// Grey value noise around mid-grey (+-amount), handy as a subtle overlay/roughness map.
export function noise(w = 128, h = 128, amount = 0.2) {
  return cached(`noise|${w}|${h}|${amount}`, w, h, (ctx, c, rand) => {
    const img = ctx.createImageData(w, h);
    for (let i = 0; i < w * h; i++) {
      const v = Math.round(255 * THREE.MathUtils.clamp(0.5 + (rand() * 2 - 1) * amount, 0, 1));
      img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = v;
      img.data[i * 4 + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
  });
}

// Linear gradient. stops: ['#a', '#b', ...] (evenly spaced) or [[0,'#a'], [1,'#b']].
export function gradient(stops, vertical = true) {
  return cached(`grad|${JSON.stringify(stops)}|${vertical}`, vertical ? 4 : 256, vertical ? 256 : 4, (ctx, c) => {
    const g = vertical ? ctx.createLinearGradient(0, 0, 0, 256) : ctx.createLinearGradient(0, 0, 256, 0);
    stops.forEach((s, i) => Array.isArray(s) ? g.addColorStop(s[0], s[1]) : g.addColorStop(i / Math.max(1, stops.length - 1), s));
    ctx.fillStyle = g; ctx.fillRect(0, 0, c.width, c.height);
  }, { repeat: false });
}

// Radial gradient (center -> edge). stops as in gradient(); default = soft white falloff to transparent.
export function radial(stops = [[0, 'rgba(255,255,255,1)'], [0.45, 'rgba(255,255,255,0.45)'], [1, 'rgba(255,255,255,0)']]) {
  return cached(`radial|${JSON.stringify(stops)}`, 128, 128, (ctx) => {
    const g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
    stops.forEach((s, i) => Array.isArray(s) ? g.addColorStop(s[0], s[1]) : g.addColorStop(i / Math.max(1, stops.length - 1), s));
    ctx.fillStyle = g; ctx.fillRect(0, 0, 128, 128);
  }, { repeat: false });
}

// Retro show poster: sunburst background, big title, subtitle band.
// opts: { title='WZTV', sub='CHANNEL 13', bg=PAL.harvestGold, fg=PAL.chocolate, accent=PAL.burntOrange, font='Bungee', w=256, h=384 }
export function poster(opts = {}) {
  const { title = 'WZTV', sub = 'CHANNEL 13', bg = PAL.harvestGold, fg = PAL.chocolate, accent = PAL.burntOrange,
    font = 'Bungee', w = 256, h = 384 } = opts;
  return cached(`poster|${JSON.stringify(opts)}`, w, h, (ctx) => {
    ctx.fillStyle = bg; ctx.fillRect(0, 0, w, h);
    const cx = w / 2, cy = h * 0.42, rays = 18;
    ctx.fillStyle = accent;
    ctx.globalAlpha = 0.55;
    for (let i = 0; i < rays; i++) {
      const a0 = (i / rays) * Math.PI * 2, a1 = a0 + Math.PI / rays;
      ctx.beginPath(); ctx.moveTo(cx, cy);
      ctx.lineTo(cx + Math.cos(a0) * h, cy + Math.sin(a0) * h);
      ctx.lineTo(cx + Math.cos(a1) * h, cy + Math.sin(a1) * h);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
    ctx.lineWidth = w * 0.035;
    ctx.strokeStyle = fg;
    ctx.strokeRect(ctx.lineWidth, ctx.lineWidth, w - ctx.lineWidth * 2, h - ctx.lineWidth * 2);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    let size = w * 0.24;
    ctx.font = `${size}px "${font}", "Arial Black", sans-serif`;
    while (ctx.measureText(title).width > w * 0.84 && size > 8) {
      size *= 0.92; ctx.font = `${size}px "${font}", "Arial Black", sans-serif`;
    }
    ctx.fillStyle = shade(fg, -0.3);
    ctx.fillText(title, cx + 3, cy + 3);
    ctx.fillStyle = PAL.capWhite;
    ctx.fillText(title, cx, cy);
    ctx.fillStyle = fg;
    ctx.fillRect(w * 0.08, h * 0.76, w * 0.84, h * 0.13);
    ctx.fillStyle = bg;
    ctx.font = `${w * 0.09}px "${font}", "Arial Black", sans-serif`;
    ctx.fillText(sub, cx, h * 0.825);
  }, { repeat: false });
}

// Animated TV snow (singleton, 128^2 DataTexture: a typed-array upload with no mipmaps, far cheaper than
// re-uploading a canvas). tick() re-randomizes it at most ~24 times per second (real time).
let staticTex = null;
export function staticNoise() {
  if (staticTex) return staticTex;
  const size = 128;
  const data = new Uint8Array(size * size * 4);
  const px = new Uint32Array(data.buffer);
  let seed = 0x9E3779B9;
  let frame = 0;
  let last = -1;
  staticTex = new THREE.DataTexture(data, size, size, THREE.RGBAFormat);
  staticTex.colorSpace = THREE.SRGBColorSpace;
  staticTex.wrapS = staticTex.wrapT = THREE.RepeatWrapping;
  staticTex.magFilter = THREE.LinearFilter;
  staticTex.minFilter = THREE.LinearFilter;
  staticTex.generateMipmaps = false;
  staticTex.name = 'staticNoise';
  staticTex.tick = () => {
    const now = performance.now();
    if (last >= 0 && now - last < 41) return;
    last = now;
    frame++;
    for (let i = 0; i < px.length; i++) {
      seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
      const v = (seed >>> 24) & 0xff;
      // Slight blue-ish bias reads as "TV" rather than grey noise (little-endian RGBA: 0xAABBGGRR).
      px[i] = 0xff000000 | (Math.min(255, v + 18) << 16) | (v << 8) | Math.max(0, v - 6);
    }
    // Rolling darker band like a drifting sync bar.
    const band = (frame * 3) % size;
    for (let y = band; y < Math.min(size, band + 7); y++) {
      for (let x = 0; x < size; x++) px[y * size + x] = (px[y * size + x] >>> 1) & 0x7f7f7f7f | 0xff000000;
    }
    staticTex.needsUpdate = true;
  };
  staticTex.tick();
  return staticTex;
}

// Textures are shared: callers wanting their own repeat get a lightweight clone (same image, own transform).
function withRepeat(tex, rx, ry) {
  if (rx === 1 && ry === 1) return tex;
  const key = `${tex.name}|rep${rx}x${ry}`;
  let t = cache.get(key);
  if (!t) {
    t = tex.clone();
    t.repeat.set(rx, ry);
    t.name = key;
    t.needsUpdate = true;
    cache.set(key, t);
  }
  return t;
}

// Shared-texture repeat helper for any cached texture.
export function repeat(tex, rx, ry = rx) {
  return withRepeat(tex, rx, ry);
}

// game.tex: the helpers above plus per-frame update (animated static).
export class Textures {
  constructor(game) {
    this.game = game;
    Object.assign(this, { plaid, stripes, colorBars, text, woodPanel, carpet, tiles, noise, staticNoise, poster, gradient, radial, repeat });
  }

  init() {
    anisotropy = Math.min(8, this.game.renderer.capabilities.getMaxAnisotropy());
  }

  update() {
    if (staticTex) staticTex.tick();
  }
}
