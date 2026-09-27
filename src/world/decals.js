// Canvas decals for the level's set pieces: signs, stencils, the ON AIR / EXIT box faces, hazard stripes, the
// high-voltage pictogram, taped-up newspaper and the storefront neon signs. Cached per argument set; sRGB,
// clamped (not tiled). Text auto-fits its canvas so a label's aspect always matches the plane it is put on.
//
//   labelTex(text, { w=512, h=128, fg, bg, font, stroke, border, pad }) → CanvasTexture
//   stencilTex(text, { w, h, ink })   spray-painted stencil on transparent (crates, the elephant door)
//   hazardTex()  boltSignTex()  newspaperTex()  movingPadTex()

import * as THREE from 'three';

const cache = new Map();
const FALLBACK = '"Arial Black", "Helvetica Neue", sans-serif';

function make(key, w, h, draw) {
  let t = cache.get(key);
  if (t) return t;
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  t.needsUpdate = true;
  cache.set(key, t);
  return t;
}

// Largest font size (≤ h·0.72 per line) whose widest line fits `maxW`.
function fit(ctx, lines, font, maxW, maxH) {
  let size = Math.floor(maxH / lines.length / 1.15);
  for (; size > 6; size -= 2) {
    ctx.font = `${size}px "${font}", ${FALLBACK}`;
    if (Math.max(...lines.map((l) => ctx.measureText(l).width)) <= maxW) break;
  }
  return size;
}

export function labelTex(text, opts = {}) {
  const { w = 512, h = 128, fg = '#F4F1E8', bg = null, font = 'Bungee', stroke = null, border = null, pad = 0.1 } = opts;
  return make(`label|${text}|${JSON.stringify(opts)}`, w, h, (x) => {
    if (bg) { x.fillStyle = bg; x.fillRect(0, 0, w, h); }
    if (border) {
      x.strokeStyle = border; x.lineWidth = h * 0.06;
      x.strokeRect(x.lineWidth, x.lineWidth, w - x.lineWidth * 2, h - x.lineWidth * 2);
    }
    const lines = String(text).split('\n');
    const size = fit(x, lines, font, w * (1 - pad * 2), h * (1 - pad * 2));
    x.textAlign = 'center'; x.textBaseline = 'middle';
    const lh = size * 1.12;
    const y0 = h / 2 - ((lines.length - 1) * lh) / 2;
    lines.forEach((l, i) => {
      if (stroke) { x.strokeStyle = stroke; x.lineWidth = size * 0.14; x.lineJoin = 'round'; x.strokeText(l, w / 2, y0 + i * lh); }
      x.fillStyle = fg;
      x.fillText(l, w / 2, y0 + i * lh);
    });
  });
}

export function stencilTex(text, { w = 512, h = 256, ink = '#2A2230' } = {}) {
  return make(`stencil|${text}|${w}|${h}|${ink}`, w, h, (x) => {
    const lines = String(text).split('\n');
    const size = fit(x, lines, 'Bungee', w * 0.86, h * 0.8);
    x.textAlign = 'center'; x.textBaseline = 'middle';
    x.fillStyle = ink;
    const lh = size * 1.12;
    const y0 = h / 2 - ((lines.length - 1) * lh) / 2;
    lines.forEach((l, i) => x.fillText(l, w / 2, y0 + i * lh));
    // Stencil bridges + overspray: knock thin vertical gaps out of the letters and speckle the edges.
    x.globalCompositeOperation = 'destination-out';
    for (let i = 0; i < w; i += size * 0.62) x.fillRect(i, 0, Math.max(2, size * 0.06), h);
    x.globalCompositeOperation = 'source-over';
    x.globalAlpha = 0.18;
    for (let i = 0; i < 500; i++) x.fillRect((i * 97) % w, (i * 57) % h, 2, 2);
    x.globalAlpha = 1;
  });
}

export function hazardTex() {
  return make('hazard', 256, 64, (x, w, h) => {
    x.fillStyle = '#F4C21E'; x.fillRect(0, 0, w, h);
    x.fillStyle = '#231E24';
    for (let i = -h; i < w + h; i += 48) {
      x.beginPath(); x.moveTo(i, h); x.lineTo(i + 24, h); x.lineTo(i + 24 + h, 0); x.lineTo(i + h, 0); x.closePath(); x.fill();
    }
  });
}

export function boltSignTex() {
  return make('bolt', 256, 256, (x) => {
    x.fillStyle = '#231E24';
    x.beginPath(); x.moveTo(128, 14); x.lineTo(246, 226); x.lineTo(10, 226); x.closePath(); x.fill();
    x.fillStyle = '#F4C21E';
    x.beginPath(); x.moveTo(128, 40); x.lineTo(224, 212); x.lineTo(32, 212); x.closePath(); x.fill();
    x.fillStyle = '#231E24';
    x.beginPath();
    x.moveTo(140, 78); x.lineTo(98, 150); x.lineTo(128, 150); x.lineTo(112, 200); x.lineTo(160, 124); x.lineTo(130, 124);
    x.closePath(); x.fill();
  });
}

export function newspaperTex() {
  return make('newspaper', 256, 320, (x, w, h) => {
    x.fillStyle = '#E9E2CF'; x.fillRect(0, 0, w, h);
    x.fillStyle = '#2A2230';
    x.font = `bold 30px "Times New Roman", serif`;
    x.textAlign = 'center';
    x.fillText('THE DAILY DIAL', w / 2, 36);
    x.fillRect(12, 46, w - 24, 3);
    x.font = `bold 26px ${FALLBACK}`;
    x.fillText('STATION', w / 2, 84);
    x.fillText('GOES DARK', w / 2, 114);
    x.globalAlpha = 0.55;
    for (let c = 0; c < 3; c++) {
      for (let r = 0; r < 18; r++) x.fillRect(14 + c * 80, 132 + r * 10, 68 - ((r * 7 + c * 3) % 4) * 6, 4);
    }
    x.globalAlpha = 0.4;
    x.fillRect(96, 140, 64, 56);
    x.globalAlpha = 1;
  });
}

// Quilted grey-blue moving blanket (hung across the D3 doorway behind the debris).
export function movingPadTex() {
  return make('movingPad', 256, 256, (x, w, h) => {
    x.fillStyle = '#3F5C8A'; x.fillRect(0, 0, w, h);
    x.strokeStyle = 'rgba(20,24,48,0.55)'; x.lineWidth = 3;
    for (let i = -h; i < w; i += 32) {
      x.beginPath(); x.moveTo(i, 0); x.lineTo(i + h, h); x.stroke();
      x.beginPath(); x.moveTo(i + h, 0); x.lineTo(i, h); x.stroke();
    }
    x.fillStyle = '#C9A24A';
    x.fillRect(0, 0, w, 10); x.fillRect(0, h - 10, w, 10);
  });
}
