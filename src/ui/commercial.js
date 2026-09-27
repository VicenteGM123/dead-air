// DEAD AIR — commercial overlay (GDD §10.3, §11 INSTANT REPLAY, §14 "Commercial bezel" / "Replay bug").
// Owned by the sponsors agent. One full-screen 2D canvas (z-index 15: over the HUD, under the menus), drawn only
// while something shows; the 3D picture shows through its transparent parts.
//
//   COMMERCIAL  the wood-grain 1977 console-TV bezel framing the centered 4:3 picture that render.setCameraOverride
//               draws (same maths: viewport()), chrome screen trim with rounded CRT corners, glass glare, a speaker
//               grille on the left panel and two knobs on the right one (the channel knob clicks on the cut), the
//               one-frame white flash of the hard cut, a VCR OSD ("II" pause / "◀◀" rewind pictograms), VHS
//               tracking lines, the Jump Cut tape splice (white frame + a diagonal splice line), the logo card
//               sliding in on its starburst (cards.js sponsor_logo_<perkId>) behind CRT scanlines, and the 5-point
//               STAR WIPE: a star hole growing out of the product reveals the gameplay camera, bezel and all.
//   REPLAY      the sports-replay wipe (a spinning WZTV "13" roundel sweeping over diagonal team-colour bars) and the
//               rewind's VHS tracking band + streaks over the whole screen. The "◀◀" bug itself is the HUD's.
//
// API
//   getOverlay() -> CommercialOverlay (singleton; the DOM is created on first use)
//   overlay.viewport(aspect = 4/3) -> { x, y, w, h } CSS px of the picture rectangle
//   overlay.draw(state)   call every frame while active     overlay.clear()   hide (drops the canvas content)
//   state = {
//     mode: 'commercial' | 'replay',  t (s, real),  perkId,
//     flash 0..1 (white over everything),  cut 0..1 (the channel knob's click),
//     osd: null | 'pause' | 'rew' | 'play',  tracking 0..1 (VHS tracking noise),  splice 0..1 (jump-cut splice),
//     card: -1 | 0..1 (logo card slide-in progress; 1 = settled),
//     cardHold: 0..1 (progress through the held card after it settled: slow push-in + one sheen sweep),
//     star: null | { x, y, r, rot }  (CSS px; the hole reveals the game; r = outer radius),
//     wipe: -1 | 0..1 (replay roundel wipe progress),  bezel: 0..1 (commercial frame opacity, default 1),
//   }
// Nothing here touches the game state; sponsors.js / perks.js drive it.

import { FONTS } from './fonts.js';
import { cards } from '../gfx/cards.js';

const TAU = Math.PI * 2;
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const easeOutBack = (x, k = 1.9) => 1 + (k + 1) * (x - 1) ** 3 + k * (x - 1) ** 2;
const smooth = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };

// Seeded random for the procedural textures (deterministic look).
function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s |= 0; s = (s + 0x6D2B79F5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.round(w));
  c.height = Math.max(1, Math.round(h));
  return c;
}

function roundRect(ctx, x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// CRT tube opening: a rounded rectangle whose sides bulge a little (a 1970s picture tube, not a flat box).
function tubePath(ctx, x, y, w, h, r, bulge) {
  const bx = w * bulge, by = h * bulge;
  ctx.moveTo(x + r, y);
  ctx.quadraticCurveTo(x + w / 2, y - by, x + w - r, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + r);
  ctx.quadraticCurveTo(x + w + bx, y + h / 2, x + w, y + h - r);
  ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  ctx.quadraticCurveTo(x + w / 2, y + h + by, x + r, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - r);
  ctx.quadraticCurveTo(x - bx, y + h / 2, x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}

function starPath(ctx, cx, cy, r, rot, inner = 0.42) {
  for (let i = 0; i < 10; i++) {
    const a = rot - Math.PI / 2 + (i * Math.PI) / 5;
    const rr = i % 2 ? r * inner : r;
    const x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr;
    if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y);
  }
  ctx.closePath();
}

// ------------------------------------------------------------------------------------------ procedural textures
// Walnut veneer tile: warm base, long flowing grain lines, darker figure bands and pores (repeats on both axes).
let _woodTile = null;
function woodTile() {
  if (_woodTile) return _woodTile;
  const W = 512, H = 512, c = canvas(W, H), ctx = c.getContext('2d'), r = rng(1977);
  const g = ctx.createLinearGradient(0, 0, W, 0);
  g.addColorStop(0, '#6A3A1C'); g.addColorStop(0.35, '#7E4722'); g.addColorStop(0.62, '#6E3D1E'); g.addColorStop(1, '#6A3A1C');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  // figure bands (wide soft darker/lighter stripes along the grain, which runs horizontally)
  for (let i = 0; i < 14; i++) {
    const y0 = r() * H, th = 10 + r() * 40, a = 0.05 + r() * 0.1;
    ctx.fillStyle = r() < 0.5 ? `rgba(40,16,4,${a})` : `rgba(190,110,50,${a * 0.8})`;
    for (const oy of [-H, 0, H]) {
      ctx.beginPath();
      for (let x = 0; x <= W; x += 16) {
        const y = y0 + oy + Math.sin((x / W) * TAU * 2 + i) * 6 + Math.sin((x / W) * TAU * 5 + i * 3) * 2;
        if (x) ctx.lineTo(x, y); else ctx.moveTo(x, y);
      }
      for (let x = W; x >= 0; x -= 16) {
        const y = y0 + oy + th + Math.sin((x / W) * TAU * 2 + i + 0.7) * 6;
        ctx.lineTo(x, y);
      }
      ctx.closePath(); ctx.fill();
    }
  }
  // fine grain lines (periodic in x so the tile repeats)
  for (let i = 0; i < 150; i++) {
    const y0 = r() * H, amp = 2 + r() * 7, f = 1 + Math.floor(r() * 3), ph = r() * TAU;
    ctx.strokeStyle = r() < 0.7 ? `rgba(35,14,4,${0.12 + r() * 0.22})` : `rgba(210,140,80,${0.06 + r() * 0.1})`;
    ctx.lineWidth = 0.6 + r() * 1.3;
    for (const oy of [-H, 0, H]) {
      ctx.beginPath();
      for (let x = 0; x <= W; x += 8) {
        const y = y0 + oy + Math.sin((x / W) * TAU * f + ph) * amp + Math.sin((x / W) * TAU * (f + 3) + ph * 2) * amp * 0.25;
        if (x) ctx.lineTo(x, y); else ctx.moveTo(x, y);
      }
      ctx.stroke();
    }
  }
  // pores
  for (let i = 0; i < 2200; i++) {
    ctx.fillStyle = `rgba(30,10,2,${0.15 + r() * 0.25})`;
    ctx.fillRect(r() * W, r() * H, 1 + r() * 3, 0.8 + r() * 0.8);
  }
  _woodTile = c;
  return c;
}

// Speaker cloth: dark brown woven fabric with gold threads.
let _clothTile = null;
function clothTile() {
  if (_clothTile) return _clothTile;
  const W = 64, H = 64, c = canvas(W, H), ctx = c.getContext('2d'), r = rng(413);
  ctx.fillStyle = '#3A2414'; ctx.fillRect(0, 0, W, H);
  for (let y = 0; y < H; y += 4) { ctx.fillStyle = y % 8 ? 'rgba(120,80,40,0.35)' : 'rgba(200,150,70,0.28)'; ctx.fillRect(0, y, W, 2); }
  for (let x = 0; x < W; x += 4) { ctx.fillStyle = 'rgba(20,10,4,0.35)'; ctx.fillRect(x, 0, 1.5, H); }
  for (let i = 0; i < 90; i++) { ctx.fillStyle = `rgba(230,180,90,${r() * 0.18})`; ctx.fillRect(r() * W, r() * H, 1, 1); }
  _clothTile = c;
  return c;
}

// VHS noise strip (white speckle + streaks), stretched over the tracking band.
let _noise = null;
function noiseStrip() {
  if (_noise) return _noise;
  const W = 256, H = 48, c = canvas(W, H), ctx = c.getContext('2d'), r = rng(88);
  const img = ctx.createImageData(W, H);
  for (let y = 0; y < H; y++) {
    const row = 0.4 + 0.6 * Math.sin((y / H) * Math.PI);
    for (let x = 0; x < W; x++) {
      const v = r() < 0.5 * row ? 150 + r() * 105 : r() * 40;
      const i = (y * W + x) * 4;
      img.data[i] = v; img.data[i + 1] = v; img.data[i + 2] = v + 10; img.data[i + 3] = r() < 0.75 * row ? 220 : 40;
    }
  }
  ctx.putImageData(img, 0, 0);
  _noise = c;
  return c;
}

// ------------------------------------------------------------------------------------------ the overlay
class CommercialOverlay {
  constructor() {
    this.el = null;
    this.ctx = null;
    this.visible = false;
    this._w = 0; this._h = 0; this._dpr = 1;
    this._bezel = null;          // cached bezel canvas for the current size
    this._layout = null;
    this._card = null;           // cached logo card canvas { id, w, h, c }
    this._rand = rng(7);
  }

  _ensure() {
    if (this.el) return;
    const c = document.createElement('canvas');
    c.id = 'deadair-commercial';
    c.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:15;display:none';
    document.body.appendChild(c);
    this.el = c;
    this.ctx = c.getContext('2d');
  }

  // Picture rectangle of a centered `aspect` viewport (render.setCameraOverride uses the same rule).
  viewport(aspect = 4 / 3) {
    const W = Math.max(1, innerWidth), H = Math.max(1, innerHeight), screen = W / H;
    if (aspect < screen) { const w = H * aspect; return { x: (W - w) / 2, y: 0, w, h: H }; }
    const h = W / aspect;
    return { x: 0, y: (H - h) / 2, w: W, h };
  }

  _resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    const W = Math.max(1, innerWidth), H = Math.max(1, innerHeight);
    if (W === this._w && H === this._h && dpr === this._dpr && this._bezel) return;
    this._w = W; this._h = H; this._dpr = dpr;
    this.el.width = Math.round(W * dpr);
    this.el.height = Math.round(H * dpr);
    this._layout = this._makeLayout(W, H);
    this._bezel = this._buildBezel(W, H, dpr, this._layout);
    this._card = null;
  }

  // Screen opening (a little inside the 4:3 picture so the frame overlaps its edges), side panels, knobs.
  _makeLayout(W, H) {
    const v = this.viewport(4 / 3);
    const u = Math.min(v.h, v.w * 0.75) / 1080;              // reference unit: 1080 p picture height
    const mY = 26 * u, mX = 30 * u;
    const open = { x: v.x + mX, y: v.y + mY, w: v.w - 2 * mX, h: v.h - 2 * mY, r: 96 * u };
    const trim = 16 * u;
    const side = v.x;                                          // free width on each side of the picture
    const lay = { v, u, open, trim, side, knobs: [], grille: null, plate: null };
    const kr = Math.min(side * 0.36, 78 * u * 1.25);
    if (side > 70 * u) {
      const cx = W - side / 2;
      lay.knobs.push({ x: cx, y: H * 0.34, r: kr, kind: 'channel' });
      lay.knobs.push({ x: cx, y: H * 0.34 + kr * 2.7, r: kr * 0.72, kind: 'volume' });
      lay.panel = { x: W - side + side * 0.12, y: H * 0.1, w: side * 0.76, h: H * 0.8 };
      lay.grille = { x: side * 0.12, y: H * 0.1, w: side * 0.76, h: H * 0.8 };
    } else {
      // narrow screens: small knobs sit on the bottom-right of the frame
      const r0 = Math.max(18, 34 * u);
      lay.knobs.push({ x: v.x + v.w - r0 * 3.6, y: v.y + v.h - r0 * 1.1, r: r0, kind: 'channel' });
      lay.knobs.push({ x: v.x + v.w - r0 * 1.4, y: v.y + v.h - r0 * 1.1, r: r0 * 0.75, kind: 'volume' });
    }
    lay.plate = { x: v.x + v.w / 2, y: open.y + open.h + (v.y + v.h - (open.y + open.h)) * 0.5, s: Math.max(9, 15 * u) };
    return lay;
  }

  _buildBezel(W, H, dpr, L) {
    const c = canvas(W * dpr, H * dpr), ctx = c.getContext('2d');
    ctx.scale(dpr, dpr);
    const { open, trim, u } = L;
    // walnut cabinet everywhere
    const pat = ctx.createPattern(woodTile(), 'repeat');
    const k = Math.max(0.6, H / 900);
    pat.setTransform?.(new DOMMatrix().scale(k, k));
    ctx.fillStyle = pat;
    ctx.fillRect(0, 0, W, H);
    // cabinet shading: darker toward the outer edges, warm sheen band across the top
    let g = ctx.createRadialGradient(W / 2, H * 0.45, Math.min(W, H) * 0.3, W / 2, H / 2, Math.max(W, H) * 0.75);
    g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(20,6,0,0.55)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, 'rgba(255,210,150,0.10)'); g.addColorStop(0.12, 'rgba(255,210,150,0)');
    g.addColorStop(0.88, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.25)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    // side panels: speaker grille (left) and the control panel (right), both inset with a bevel
    if (L.grille) {
      const q = L.grille;
      this._inset(ctx, q.x, q.y, q.w, q.h, 14 * u);
      ctx.save();
      ctx.beginPath(); roundRect(ctx, q.x + 6 * u, q.y + 6 * u, q.w - 12 * u, q.h - 12 * u, 10 * u); ctx.clip();
      ctx.fillStyle = ctx.createPattern(clothTile(), 'repeat');
      ctx.fillRect(q.x, q.y, q.w, q.h);
      // vertical wooden slats over the cloth
      const n = 5, sw = (q.w - 12 * u) / (n * 2 - 1);
      for (let i = 0; i < n; i++) {
        const x = q.x + 6 * u + i * sw * 2;
        if (i === 0) continue;
        ctx.fillStyle = pat; ctx.fillRect(x - sw, q.y, sw, q.h);
        const sg = ctx.createLinearGradient(x - sw, 0, x, 0);
        sg.addColorStop(0, 'rgba(255,200,140,0.18)'); sg.addColorStop(0.5, 'rgba(0,0,0,0)'); sg.addColorStop(1, 'rgba(0,0,0,0.35)');
        ctx.fillStyle = sg; ctx.fillRect(x - sw, q.y, sw, q.h);
      }
      const vg = ctx.createLinearGradient(0, q.y, 0, q.y + q.h);
      vg.addColorStop(0, 'rgba(0,0,0,0.35)'); vg.addColorStop(0.2, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,0.3)');
      ctx.fillStyle = vg; ctx.fillRect(q.x, q.y, q.w, q.h);
      ctx.restore();
    }
    if (L.panel) {
      const q = L.panel;
      this._inset(ctx, q.x, q.y, q.w, q.h, 14 * u);
      ctx.save();
      ctx.beginPath(); roundRect(ctx, q.x + 6 * u, q.y + 6 * u, q.w - 12 * u, q.h - 12 * u, 10 * u); ctx.clip();
      const pg = ctx.createLinearGradient(q.x, 0, q.x + q.w, 0);
      pg.addColorStop(0, '#2A1D18'); pg.addColorStop(0.5, '#3A2A22'); pg.addColorStop(1, '#241814');
      ctx.fillStyle = pg; ctx.fillRect(q.x, q.y, q.w, q.h);
      // brushed-aluminium strip with the channel numbers around the tuner knob
      ctx.restore();
      const kn = L.knobs[0];
      ctx.save();
      ctx.fillStyle = '#E8DCC0';
      ctx.font = `${Math.round(kn.r * 0.24)}px ${FONTS.sign}`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      const chans = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
      chans.forEach((ch, i) => {
        const a = -Math.PI * 0.8 + (i / (chans.length - 1)) * Math.PI * 1.6 - Math.PI / 2;
        const rr = kn.r * 1.28;
        ctx.fillStyle = ch === 13 ? '#FF6A4A' : '#E8DCC0';
        ctx.fillText(String(ch), kn.x + Math.cos(a) * rr, kn.y + Math.sin(a) * rr);
      });
      ctx.font = `${Math.round(kn.r * 0.2)}px ${FONTS.sign}`;
      ctx.fillStyle = 'rgba(232,220,192,0.8)';
      ctx.fillText('VHF', kn.x, kn.y + kn.r * 1.62);
      const k2 = L.knobs[1];
      ctx.fillText('VOLUME', k2.x, k2.y + k2.r * 1.55);
      // tiny red power lamp
      ctx.beginPath(); ctx.arc(k2.x, k2.y + k2.r * 2.3, Math.max(3, 6 * u), 0, TAU);
      ctx.fillStyle = '#FF3B30'; ctx.shadowColor = '#FF3B30'; ctx.shadowBlur = 12 * u; ctx.fill();
      ctx.restore();
    }
    // chrome trim ring around the tube
    ctx.save();
    ctx.beginPath();
    tubePath(ctx, open.x - trim, open.y - trim, open.w + trim * 2, open.h + trim * 2, open.r + trim, 0.012);
    const tg = ctx.createLinearGradient(0, open.y - trim, 0, open.y + open.h + trim);
    tg.addColorStop(0, '#F4F0E6'); tg.addColorStop(0.18, '#9A9A98'); tg.addColorStop(0.5, '#D8D6D0');
    tg.addColorStop(0.82, '#7A7874'); tg.addColorStop(1, '#E8E4DA');
    ctx.fillStyle = tg;
    ctx.shadowColor = 'rgba(0,0,0,0.6)'; ctx.shadowBlur = 18 * u; ctx.shadowOffsetY = 4 * u;
    ctx.fill();
    ctx.restore();
    // black rubber gasket between trim and glass
    ctx.beginPath();
    tubePath(ctx, open.x - trim * 0.35, open.y - trim * 0.35, open.w + trim * 0.7, open.h + trim * 0.7, open.r + trim * 0.35, 0.012);
    ctx.fillStyle = '#141014'; ctx.fill();
    // cut the picture opening
    ctx.save();
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath(); tubePath(ctx, open.x, open.y, open.w, open.h, open.r, 0.012);
    ctx.fill();
    ctx.restore();
    // inner glass edge shadow + glare (inside the opening, low alpha so the picture reads)
    ctx.save();
    ctx.beginPath(); tubePath(ctx, open.x, open.y, open.w, open.h, open.r, 0.012); ctx.clip();
    ctx.lineWidth = 40 * u;
    ctx.strokeStyle = 'rgba(0,0,0,0.45)';
    ctx.filter = `blur(${Math.round(14 * u)}px)`;
    ctx.beginPath(); tubePath(ctx, open.x, open.y, open.w, open.h, open.r, 0.012); ctx.stroke();
    ctx.filter = 'none';
    const gl = ctx.createLinearGradient(open.x, open.y, open.x + open.w * 0.55, open.y + open.h * 0.7);
    gl.addColorStop(0, 'rgba(255,255,255,0.16)'); gl.addColorStop(0.35, 'rgba(255,255,255,0.05)'); gl.addColorStop(0.36, 'rgba(255,255,255,0)');
    ctx.fillStyle = gl; ctx.fillRect(open.x, open.y, open.w, open.h);
    ctx.restore();
    // brand plate under the tube
    const P = L.plate;
    ctx.save();
    ctx.font = `${Math.round(P.s)}px ${FONTS.sign}`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const label = 'SOLID STATE  ✦  COLOR';
    const tw = ctx.measureText(label).width;
    ctx.beginPath(); roundRect(ctx, P.x - tw / 2 - P.s, P.y - P.s * 0.8, tw + P.s * 2, P.s * 1.6, P.s * 0.4);
    const bg = ctx.createLinearGradient(0, P.y - P.s, 0, P.y + P.s);
    bg.addColorStop(0, '#E8D9A8'); bg.addColorStop(0.5, '#B8914A'); bg.addColorStop(1, '#E0C888');
    ctx.fillStyle = bg; ctx.fill();
    ctx.fillStyle = '#3A2410'; ctx.fillText(label, P.x, P.y + P.s * 0.05);
    ctx.restore();
    return c;
  }

  // Recessed panel: dark inner shadow + light lower-right lip.
  _inset(ctx, x, y, w, h, r) {
    ctx.save();
    ctx.beginPath(); roundRect(ctx, x, y, w, h, r);
    ctx.fillStyle = 'rgba(20,8,2,0.55)'; ctx.fill();
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(255,200,140,0.22)'; ctx.stroke();
    ctx.restore();
  }

  _knob(ctx, k, angle) {
    const { x, y, r } = k;
    ctx.save();
    // drop shadow + skirt
    ctx.beginPath(); ctx.arc(x, y + r * 0.08, r * 1.04, 0, TAU);
    ctx.fillStyle = 'rgba(0,0,0,0.45)'; ctx.fill();
    let g = ctx.createRadialGradient(x - r * 0.3, y - r * 0.35, r * 0.1, x, y, r);
    g.addColorStop(0, '#6A4A34'); g.addColorStop(0.7, '#3A2418'); g.addColorStop(1, '#1E120C');
    ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fillStyle = g; ctx.fill();
    // knurled ridges
    ctx.translate(x, y); ctx.rotate(angle);
    ctx.strokeStyle = 'rgba(0,0,0,0.5)'; ctx.lineWidth = Math.max(1, r * 0.035);
    for (let i = 0; i < 28; i++) {
      const a = (i / 28) * TAU;
      ctx.beginPath(); ctx.moveTo(Math.cos(a) * r * 0.82, Math.sin(a) * r * 0.82); ctx.lineTo(Math.cos(a) * r * 0.99, Math.sin(a) * r * 0.99); ctx.stroke();
    }
    // chrome cap
    g = ctx.createLinearGradient(-r * 0.6, -r * 0.6, r * 0.6, r * 0.6);
    g.addColorStop(0, '#FFFFFF'); g.addColorStop(0.4, '#B8B8B4'); g.addColorStop(0.6, '#8A8A86'); g.addColorStop(1, '#E8E8E0');
    ctx.beginPath(); ctx.arc(0, 0, r * 0.62, 0, TAU); ctx.fillStyle = g; ctx.fill();
    // pointer
    ctx.fillStyle = '#FF5A3C';
    ctx.beginPath(); roundRect(ctx, -r * 0.07, -r * 0.95, r * 0.14, r * 0.5, r * 0.07); ctx.fill();
    ctx.restore();
  }

  _cardCanvas(perkId, w, h) {
    const id = `sponsor_logo_${perkId}`;
    if (this._card && this._card.id === id && this._card.w === Math.round(w) && this._card.h === Math.round(h)) return this._card.c;
    const c = canvas(w, h), ctx = c.getContext('2d');
    try { cards.drawTo(ctx, id, c.width, c.height, 0); } catch (err) { ctx.fillStyle = '#E3662B'; ctx.fillRect(0, 0, c.width, c.height); }
    // CRT scanlines + vignette baked on the card
    ctx.fillStyle = 'rgba(0,0,0,0.13)';
    for (let y = 0; y < c.height; y += 3) ctx.fillRect(0, y, c.width, 1);
    const vg = ctx.createRadialGradient(c.width / 2, c.height / 2, c.height * 0.35, c.width / 2, c.height / 2, c.height * 0.85);
    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,0.4)');
    ctx.fillStyle = vg; ctx.fillRect(0, 0, c.width, c.height);
    this._card = { id, w: c.width, h: c.height, c };
    return c;
  }

  clear() {
    if (!this.el || !this.visible) return;
    this.visible = false;
    this.el.style.display = 'none';
    this.ctx.setTransform(1, 0, 0, 1, 0, 0);
    this.ctx.clearRect(0, 0, this.el.width, this.el.height);
  }

  draw(s) {
    this._ensure();
    this._resize();
    if (!this.visible) { this.visible = true; this.el.style.display = 'block'; }
    const ctx = this.ctx, W = this._w, H = this._h, dpr = this._dpr;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.el.width, this.el.height);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (s.mode === 'commercial') this._drawCommercial(ctx, W, H, s);
    else if (s.mode === 'replay') this._drawReplay(ctx, W, H, s);
    if (s.flash > 0) {
      ctx.save();
      ctx.globalCompositeOperation = 'source-over';
      ctx.fillStyle = `rgba(255,255,250,${clamp01(s.flash)})`;
      ctx.fillRect(0, 0, W, H);
      ctx.restore();
    }
  }

  _drawCommercial(ctx, W, H, s) {
    const L = this._layout, o = L.open, u = L.u, t = s.t || 0;
    const bez = s.bezel ?? 1;
    // picture-level FX first (they sit on the 3D picture, under the glass/bezel)
    ctx.save();
    ctx.beginPath(); tubePath(ctx, o.x, o.y, o.w, o.h, o.r, 0.012); ctx.clip();
    if (s.tracking > 0) this._tracking(ctx, o.x, o.y, o.w, o.h, s.tracking, t);
    if (s.splice > 0) {
      const a = clamp01(s.splice);
      ctx.fillStyle = `rgba(255,255,255,${a * 0.85})`;
      ctx.fillRect(o.x, o.y, o.w, o.h);
      // the diagonal splice line + tape edge
      ctx.strokeStyle = `rgba(30,20,10,${a})`; ctx.lineWidth = 6 * u;
      const sx = o.x + o.w * 0.2, ex = o.x + o.w * 0.8;
      ctx.beginPath(); ctx.moveTo(sx, o.y); ctx.lineTo(ex, o.y + o.h); ctx.stroke();
      ctx.strokeStyle = `rgba(255,210,120,${a})`; ctx.lineWidth = 2 * u;
      ctx.beginPath(); ctx.moveTo(sx + 10 * u, o.y); ctx.lineTo(ex + 10 * u, o.y + o.h); ctx.stroke();
    }
    if (s.card >= 0) {
      const p = clamp01(s.card);
      const e = easeOutBack(p, 1.6);
      const cw = o.w * 1.02, ch = o.h * 1.02;
      const x = o.x - o.w * 0.01 + (1 - e) * o.w * 1.1, y = o.y - o.h * 0.01;
      const c = this._cardCanvas(s.perkId, Math.min(1024, cw), Math.min(768, ch));
      // while it holds (the product name is being read) the card keeps moving: a slow 3.5 % push-in
      const hold = clamp01(s.cardHold || 0);
      ctx.save();
      ctx.translate(x + cw / 2, y + ch / 2);
      ctx.rotate((1 - e) * 0.18);
      const sc = (0.92 + 0.08 * e + Math.sin(p * Math.PI) * 0.02) * (1 + 0.035 * smooth(0, 1, hold));
      ctx.scale(sc, sc);
      ctx.drawImage(c, -cw / 2, -ch / 2, cw, ch);
      // ...and one soft diagonal sheen sweeps across it, like light over a glossy title card
      const sw = smooth(0.3, 0.75, hold);
      if (sw > 0 && sw < 1) {
        const bx = -cw * 0.75 + sw * cw * 1.5, band = cw * 0.16;
        const g = ctx.createLinearGradient(bx - band, -ch * 0.2, bx + band, ch * 0.2);
        g.addColorStop(0, 'rgba(255,248,230,0)');
        g.addColorStop(0.5, `rgba(255,248,230,${(0.2 * Math.sin(sw * Math.PI)).toFixed(3)})`);
        g.addColorStop(1, 'rgba(255,248,230,0)');
        ctx.globalCompositeOperation = 'lighter';
        ctx.fillStyle = g;
        ctx.fillRect(-cw / 2, -ch / 2, cw, ch);
        ctx.globalCompositeOperation = 'source-over';
      }
      ctx.restore();
    }
    if (s.osd) {
      const f = Math.round(58 * u);
      ctx.font = `${f}px ${FONTS.tape}`;
      ctx.textBaseline = 'top';
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      const txt = s.osd === 'pause' ? 'II' : s.osd === 'rew' ? '◀◀' : '▶';
      const blink = s.osd === 'pause' || Math.floor(t * 6) % 2 === 0;
      if (blink) {
        ctx.fillText(txt, o.x + 92 * u + 3 * u, o.y + 60 * u + 3 * u);
        ctx.fillStyle = '#7CFF8A';
        ctx.shadowColor = '#3AFF5A'; ctx.shadowBlur = 10 * u;
        ctx.fillText(txt, o.x + 92 * u, o.y + 60 * u);
        ctx.shadowBlur = 0;
      }
    }
    ctx.restore();
    // the cabinet
    if (bez > 0) {
      ctx.globalAlpha = bez;
      ctx.drawImage(this._bezel, 0, 0, W, H);
      const click = s.cut || 0;
      L.knobs.forEach((k, i) => this._knob(ctx, k, i === 0 ? 0.35 + 0.35 * Math.sin(click * Math.PI) * (1 - click) + (click > 0.5 ? 0.52 : 0) : -0.8));
      ctx.globalAlpha = 1;
    }
    // star wipe: a hole revealing the gameplay camera, rimmed in gold
    if (s.star && s.star.r > 0) {
      const st = s.star;
      ctx.save();
      ctx.globalCompositeOperation = 'destination-out';
      ctx.fillStyle = '#000';
      ctx.globalAlpha = 1;
      ctx.beginPath(); starPath(ctx, st.x, st.y, st.r, st.rot || 0); ctx.fill();
      ctx.restore();
      ctx.save();
      ctx.beginPath(); starPath(ctx, st.x, st.y, st.r, st.rot || 0);
      ctx.lineJoin = 'round';
      ctx.lineWidth = Math.max(4, st.r * 0.035);
      ctx.strokeStyle = '#FFD84A';
      ctx.shadowColor = '#FFB020'; ctx.shadowBlur = 24 * u;
      ctx.stroke();
      ctx.lineWidth = Math.max(1.5, st.r * 0.012);
      ctx.strokeStyle = '#FFFFFF'; ctx.shadowBlur = 0;
      ctx.stroke();
      ctx.restore();
    }
  }

  // VHS tracking: a rolling noise band, thin white streaks and a colour smear.
  _tracking(ctx, x, y, w, h, amt, t) {
    const n = noiseStrip(), r = this._rand;
    const bandH = h * (0.07 + 0.05 * amt);
    const by = y + ((t * 0.9) % 1) * (h + bandH) - bandH;
    ctx.save();
    ctx.globalAlpha = 0.55 * amt;
    ctx.drawImage(n, 0, 0, n.width, n.height, x - r() * 30, by, w + 60, bandH);
    ctx.globalAlpha = 0.35 * amt;
    ctx.drawImage(n, 0, 0, n.width, n.height, x, y + h - bandH * 0.6, w, bandH * 0.6);
    ctx.globalAlpha = 1;
    for (let i = 0; i < 10 * amt; i++) {
      const ly = y + r() * h, lw = w * (0.1 + r() * 0.5), lx = x + r() * (w - lw);
      ctx.fillStyle = `rgba(255,255,255,${0.25 + r() * 0.4})`;
      ctx.fillRect(lx, ly, lw, 1 + r() * 2);
    }
    ctx.globalCompositeOperation = 'screen';
    ctx.fillStyle = `rgba(80,0,120,${0.12 * amt})`;
    ctx.fillRect(x, y, w, h);
    ctx.restore();
  }

  _drawReplay(ctx, W, H, s) {
    const t = s.t || 0;
    if (s.tracking > 0) this._tracking(ctx, 0, 0, W, H, s.tracking, t);
    if (s.wipe >= 0 && s.wipe <= 1) {
      const p = s.wipe;
      const D = Math.hypot(W, H);
      // diagonal team-colour bars racing across
      ctx.save();
      ctx.translate(W / 2, H / 2);
      ctx.rotate(-0.5);
      const cols = ['#F4C81E', '#2F5BD3', '#F4F1E8', '#E23B3B', '#2F5BD3'];
      const bw = D * 0.16;
      cols.forEach((c, i) => {
        const k = smooth(0.0 + i * 0.05, 0.45 + i * 0.05, p) - smooth(0.55 + i * 0.04, 1.0, p);
        if (k <= 0) return;
        const off = (i - 2) * bw * 0.9;
        ctx.fillStyle = c;
        ctx.fillRect(-D / 2 - D * (1 - k) * (i % 2 ? -1 : 1), off - bw / 2, D, bw);
      });
      ctx.restore();
      // the spinning 13 roundel
      const grow = smooth(0, 0.45, p), shrink = smooth(0.55, 1, p);
      const R = D * 0.36 * grow * (1 - shrink) + 1;
      if (R > 2) {
        ctx.save();
        ctx.translate(W / 2, H / 2);
        ctx.rotate(p * TAU * 1.5);
        ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = R * 0.1;
        ctx.beginPath(); ctx.arc(0, 0, R, 0, TAU); ctx.fillStyle = '#E23B3B'; ctx.fill();
        ctx.shadowBlur = 0;
        ctx.beginPath(); ctx.arc(0, 0, R * 0.8, 0, TAU); ctx.fillStyle = '#2F5BD3'; ctx.fill();
        ctx.beginPath(); ctx.arc(0, 0, R * 0.8, 0, TAU); ctx.lineWidth = R * 0.05; ctx.strokeStyle = '#F4F1E8'; ctx.stroke();
        ctx.font = `${Math.round(R * 0.95)}px ${FONTS.logo}`;
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillStyle = '#B5472A'; ctx.fillText('13', R * 0.03, R * 0.1);
        ctx.fillStyle = '#FFE14D'; ctx.fillText('13', 0, R * 0.06);
        ctx.restore();
      }
    }
  }
}

let _overlay = null;
export function getOverlay() {
  if (!_overlay) _overlay = new CommercialOverlay();
  return _overlay;
}
export { CommercialOverlay };
