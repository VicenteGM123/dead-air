// World surfaces: the station's canvas textures (plaster, quilted padding, planks, painted concrete, diamond
// plate, gravel, acoustic tile, brick, cinder block, grass, asphalt, sidewalk, chain-link, the scenery-flat
// board atlas, lit skyline windows) and the material palette built on game.mats.toon.
//
// createSurfaces(game) → { get(key) → { mat, tile:[u,v] }, plain(key) → Material, tex, AREA_STYLE, EXTERIOR_STYLE }
//   get(): the batch material (vertexColors = fake AO, see batch.js) and tile = metres covered by one texture
//   repeat (batch.js bakes world-space UVs with it). plain(): the same look without vertex colors, for ordinary
//   meshes with their own 0..1 UVs (door leaves, frames, props).
// AREA_STYLE[areaId] = { floor, wall:{ base, wainscot?, wainscotH?, rail?, baseboard, crown? }, ceiling,
//   fixtures:'panels'|'cans'|'grid', lightPre (emergency color or null = dark), lightPost, gridY? }
// All textures are deterministic (seeded) and ≤ 512², cached per createSurfaces call.

import * as THREE from 'three';
import { mulberry32 } from '../core/rng.js';

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

function finish(c, { srgb = true } = {}) {
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 8;
  t.needsUpdate = true;
  return t;
}

const shade = (hex, k) => {
  const c = new THREE.Color(hex);
  if (k >= 0) c.lerp(new THREE.Color(1, 1, 1), k); else c.multiplyScalar(1 + k);
  return `#${c.getHexString()}`;
};

// Speckle helper: n soft dots of random grey value around `base` alpha.
function speckle(ctx, w, h, rand, n, size, alpha, light = '#ffffff', dark = '#000000') {
  for (let i = 0; i < n; i++) {
    ctx.globalAlpha = alpha * (0.3 + rand() * 0.7);
    ctx.fillStyle = rand() < 0.5 ? light : dark;
    const s = size * (0.5 + rand());
    ctx.fillRect(rand() * w, rand() * h, s, s);
  }
  ctx.globalAlpha = 1;
}

// ------------------------------------------------------------------------------------------ textures
const TEX = {
  // Light plaster with roller texture: tinted by the material color.
  plaster(rand) {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#eeeeee'; x.fillRect(0, 0, 256, 256);
    speckle(x, 256, 256, rand, 2600, 2.2, 0.08, '#ffffff', '#9a9a9a');
    x.globalAlpha = 0.05;
    for (let i = 0; i < 18; i++) { x.fillStyle = rand() < 0.5 ? '#fff' : '#bbb'; x.fillRect(rand() * 256, 0, 10 + rand() * 30, 256); }
    x.globalAlpha = 1;
    return finish(c);
  },
  // Quilted padding: diamond tufts with buttons (soundstage walls, padded doors). Tinted.
  quilt() {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#d8d8d8'; x.fillRect(0, 0, 256, 256);
    const s = 64;
    for (let j = -1; j <= 4; j++) {
      for (let i = -1; i <= 4; i++) {
        const cx = i * s + (j % 2 ? s / 2 : 0), cy = j * s;
        const g = x.createRadialGradient(cx, cy + s / 2, 4, cx, cy + s / 2, s * 0.62);
        g.addColorStop(0, '#ffffff'); g.addColorStop(0.7, '#d0d0d0'); g.addColorStop(1, '#8a8a8a');
        x.fillStyle = g;
        x.beginPath();
        x.moveTo(cx, cy); x.lineTo(cx + s / 2, cy + s / 2); x.lineTo(cx, cy + s); x.lineTo(cx - s / 2, cy + s / 2);
        x.closePath(); x.fill();
      }
    }
    x.fillStyle = '#6e6e6e';
    for (let j = 0; j <= 4; j++) for (let i = 0; i <= 8; i++) {
      x.beginPath(); x.arc(i * s / 2, j * s + (i % 2 ? s / 2 : 0), 4, 0, Math.PI * 2); x.fill();
    }
    return finish(c);
  },
  // Floor planks with staggered joints and grain (base color baked in).
  planks(rand, base = '#D9B27C', rows = 8) {
    const c = canvas(512, 512), x = c.getContext('2d');
    const h = 512 / rows;
    for (let r = 0; r < rows; r++) {
      let px = -rand() * 256;
      while (px < 512) {
        const len = 160 + rand() * 220;
        x.fillStyle = shade(base, (rand() - 0.5) * 0.18);
        x.fillRect(px, r * h, len, h);
        x.strokeStyle = shade(base, -0.22);
        x.globalAlpha = 0.35;
        for (let g = 0; g < 5; g++) {
          const gy = r * h + 4 + rand() * (h - 8);
          x.beginPath(); x.moveTo(px, gy);
          x.bezierCurveTo(px + len * 0.3, gy + (rand() - 0.5) * 6, px + len * 0.7, gy + (rand() - 0.5) * 6, px + len, gy);
          x.stroke();
        }
        x.globalAlpha = 1;
        x.fillStyle = shade(base, -0.45);
        x.fillRect(px, r * h, 2, h);
        px += len;
      }
      x.fillStyle = shade(base, -0.5);
      x.fillRect(0, r * h, 512, 2);
      x.fillStyle = shade(base, 0.2);
      x.fillRect(0, r * h + 2, 512, 1);
    }
    return finish(c);
  },
  // Painted studio concrete (full color): mottled plum-grey, scuffs and colored spike-tape marks.
  concrete(rand) {
    const c = canvas(512, 512), x = c.getContext('2d');
    x.fillStyle = '#4b4254'; x.fillRect(0, 0, 512, 512);
    for (let i = 0; i < 90; i++) {
      const g = x.createRadialGradient(0, 0, 0, 0, 0, 40 + rand() * 60);
      const v = rand() < 0.5 ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.07)';
      g.addColorStop(0, v); g.addColorStop(1, 'rgba(0,0,0,0)');
      x.save(); x.translate(rand() * 512, rand() * 512); x.fillStyle = g; x.fillRect(-100, -100, 200, 200); x.restore();
    }
    speckle(x, 512, 512, rand, 3000, 1.6, 0.12, '#bdb4c6', '#1c1822');
    const tapes = ['#F4E03A', '#3FD6E0', '#FF5FA2', '#F4F1E8'];
    for (let i = 0; i < 7; i++) {
      x.save();
      x.translate(40 + rand() * 432, 40 + rand() * 432);
      x.rotate((rand() - 0.5) * 0.3);
      x.fillStyle = tapes[i % tapes.length];
      x.globalAlpha = 0.85;
      if (i % 2) { x.fillRect(-14, -3, 28, 6); x.fillRect(-3, -14, 6, 28); } else x.fillRect(-22, -3, 44, 6);
      x.restore();
    }
    x.globalAlpha = 1;
    return finish(c);
  },
  diamondPlate(rand) {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#9aa3ab'; x.fillRect(0, 0, 256, 256);
    speckle(x, 256, 256, rand, 900, 2, 0.1, '#ffffff', '#40464c');
    for (let j = 0; j < 8; j++) for (let i = 0; i < 8; i++) {
      x.save();
      x.translate(i * 32 + (j % 2 ? 16 : 0) + 8, j * 32 + 16);
      x.rotate((i + j) % 2 ? 0.8 : -0.8);
      x.fillStyle = '#6c747c'; x.fillRect(-11, -3, 22, 6);
      x.fillStyle = '#d4dade'; x.fillRect(-11, -3, 22, 2);
      x.restore();
    }
    return finish(c);
  },
  gravel(rand) {
    const c = canvas(512, 512), x = c.getContext('2d');
    x.fillStyle = '#5d5866'; x.fillRect(0, 0, 512, 512);
    const cols = ['#7b7684', '#8c8795', '#4a4652', '#a39eab', '#6a6573', '#77705f'];
    for (let i = 0; i < 5200; i++) {
      const r = 1.5 + rand() * 4;
      const px = rand() * 512, py = rand() * 512;
      x.fillStyle = '#2c2933';
      x.beginPath(); x.ellipse(px + 1, py + 1.5, r, r * 0.8, rand() * 3, 0, Math.PI * 2); x.fill();
      x.fillStyle = cols[(rand() * cols.length) | 0];
      x.beginPath(); x.ellipse(px, py, r, r * 0.8, rand() * 3, 0, Math.PI * 2); x.fill();
    }
    return finish(c);
  },
  // 2×2 acoustic ceiling tiles with pinholes and a T-bar grid (tinted).
  acoustic(rand) {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#efefef'; x.fillRect(0, 0, 256, 256);
    x.fillStyle = '#b5b5b5';
    for (let i = 0; i < 1500; i++) x.fillRect(rand() * 256, rand() * 256, 1.4, 1.4);
    x.fillStyle = '#c9c9c9';
    for (let i = 0; i < 2; i++) { x.fillRect(i * 128, 0, 5, 256); x.fillRect(0, i * 128, 256, 5); }
    x.fillStyle = '#ffffff';
    for (let i = 0; i < 2; i++) { x.fillRect(i * 128 + 5, 0, 1, 256); x.fillRect(0, i * 128 + 5, 256, 1); }
    return finish(c);
  },
  brick(rand) {
    const c = canvas(512, 512), x = c.getContext('2d');
    x.fillStyle = '#6d5a52'; x.fillRect(0, 0, 512, 512);
    const bw = 64, bh = 24;
    for (let r = 0; r < 512 / bh; r++) {
      for (let i = -1; i < 512 / bw + 1; i++) {
        const px = i * bw + (r % 2 ? bw / 2 : 0);
        x.fillStyle = shade('#B98A6A', (rand() - 0.5) * 0.25);
        x.fillRect(px + 2, r * bh + 2, bw - 4, bh - 4);
        x.fillStyle = 'rgba(255,255,255,0.08)';
        x.fillRect(px + 2, r * bh + 2, bw - 4, 3);
      }
    }
    speckle(x, 512, 512, rand, 2500, 1.5, 0.1, '#e8d2bd', '#3a2a24');
    return finish(c);
  },
  block(rand) {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#9c9c9c'; x.fillRect(0, 0, 256, 256);
    const bw = 128, bh = 64;
    for (let r = 0; r < 4; r++) for (let i = -1; i < 3; i++) {
      const px = i * bw + (r % 2 ? bw / 2 : 0);
      x.fillStyle = shade('#e4e4e4', (rand() - 0.5) * 0.06);
      x.fillRect(px + 3, r * bh + 3, bw - 6, bh - 6);
    }
    speckle(x, 256, 256, rand, 1400, 1.6, 0.12, '#ffffff', '#707070');
    return finish(c);
  },
  grass(rand) {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#2f4a3a'; x.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 2600; i++) {
      x.strokeStyle = rand() < 0.5 ? '#3d5e46' : '#24392e';
      x.globalAlpha = 0.6;
      const px = rand() * 256, py = rand() * 256;
      x.beginPath(); x.moveTo(px, py); x.lineTo(px + (rand() - 0.5) * 3, py - 3 - rand() * 4); x.stroke();
    }
    x.globalAlpha = 1;
    return finish(c);
  },
  asphalt(rand) {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#2b2a31'; x.fillRect(0, 0, 256, 256);
    speckle(x, 256, 256, rand, 4000, 1.3, 0.25, '#58566a', '#141318');
    return finish(c);
  },
  sidewalk(rand) {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#8b8792'; x.fillRect(0, 0, 256, 256);
    speckle(x, 256, 256, rand, 2200, 1.5, 0.12, '#c8c4ce', '#4a4750');
    x.fillStyle = '#5d5a63';
    x.fillRect(0, 0, 256, 3); x.fillRect(0, 0, 3, 256);
    return finish(c);
  },
  // RGBA chain-link: galvanized wire diamonds on transparent (alphaTest in the material).
  chainLink() {
    const c = canvas(128, 128), x = c.getContext('2d');
    x.clearRect(0, 0, 128, 128);
    x.lineWidth = 3.2;
    x.lineCap = 'round';
    const draw = (col, off) => {
      x.strokeStyle = col;
      for (let i = -2; i < 4; i++) {
        x.beginPath(); x.moveTo(i * 64 + off, 0); x.lineTo(i * 64 + 128 + off, 128); x.stroke();
        x.beginPath(); x.moveTo(i * 64 + off, 128); x.lineTo(i * 64 + 128 + off, 0); x.stroke();
      }
    };
    draw('#4e565e', 1.2);
    draw('#c9d2da', 0);
    return finish(c);
  },
  // Six scenery-flat slices (sky with clouds, brick, wood fence, stars, sunset stripes, hedge) + plywood band.
  boards(rand) {
    const c = canvas(512, 512), x = c.getContext('2d');
    const band = 512 / 7;
    const B = (i, fn) => { x.save(); x.beginPath(); x.rect(0, i * band, 512, band); x.clip(); x.translate(0, i * band); fn(); x.restore(); };
    B(0, () => {
      x.fillStyle = '#7FC8F0'; x.fillRect(0, 0, 512, band);
      x.fillStyle = '#ffffff';
      for (let i = 0; i < 7; i++) { const cx = rand() * 512; for (let k = 0; k < 4; k++) { x.beginPath(); x.arc(cx + k * 16, band * 0.5 + (k % 2) * 6, 14 + rand() * 6, 0, 7); x.fill(); } }
    });
    B(1, () => {
      x.fillStyle = '#E3E0D8'; x.fillRect(0, 0, 512, band);
      for (let r = 0; r < 4; r++) for (let i = -1; i < 12; i++) {
        x.fillStyle = shade('#C0513A', (rand() - 0.5) * 0.2);
        x.fillRect(i * 48 + (r % 2 ? 24 : 0) + 2, r * (band / 4) + 2, 44, band / 4 - 4);
      }
    });
    B(2, () => {
      for (let i = 0; i < 16; i++) { x.fillStyle = shade('#B07A45', (rand() - 0.5) * 0.25); x.fillRect(i * 32, 0, 30, band); }
      x.fillStyle = 'rgba(60,30,10,0.4)';
      for (let i = 0; i < 16; i++) x.fillRect(i * 32 + 30, 0, 2, band);
    });
    B(3, () => {
      x.fillStyle = '#23285E'; x.fillRect(0, 0, 512, band);
      x.fillStyle = '#FFF4B0';
      for (let i = 0; i < 40; i++) { const s = 1 + rand() * 2.5; x.fillRect(rand() * 512, rand() * band, s, s); }
      x.fillStyle = '#FFF4D6'; x.beginPath(); x.arc(400, band / 2, band * 0.32, 0, 7); x.fill();
    });
    B(4, () => {
      ['#FF7E5F', '#FFB36B', '#FFE3A3', '#FFB36B'].forEach((col, i) => { x.fillStyle = col; x.fillRect(0, i * band / 4, 512, band / 4 + 1); });
      x.fillStyle = '#E3662B'; x.beginPath(); x.arc(140, band, band * 0.6, 0, 7); x.fill();
    });
    B(5, () => {
      x.fillStyle = '#4E8A3E'; x.fillRect(0, 0, 512, band);
      for (let i = 0; i < 70; i++) { x.fillStyle = rand() < 0.5 ? '#63A84E' : '#3C6E30'; x.beginPath(); x.arc(rand() * 512, rand() * band, 8 + rand() * 12, 0, 7); x.fill(); }
    });
    B(6, () => {
      x.fillStyle = '#C9A77A'; x.fillRect(0, 0, 512, band);
      x.strokeStyle = 'rgba(120,80,40,0.35)';
      for (let i = 0; i < 30; i++) { const y = rand() * band; x.beginPath(); x.moveTo(0, y); x.bezierCurveTo(170, y + 8, 340, y - 8, 512, y); x.stroke(); }
    });
    // white painted edges on every slice
    x.fillStyle = 'rgba(255,255,255,0.55)';
    for (let i = 0; i < 6; i++) { x.fillRect(0, i * band, 512, 3); x.fillRect(0, (i + 1) * band - 3, 512, 3); }
    return finish(c);
  },
  // Night facade with lit windows (warm, TV-blue, dark). Used unlit on skyline boxes.
  skyline(rand) {
    const c = canvas(256, 256), x = c.getContext('2d');
    x.fillStyle = '#161a3a'; x.fillRect(0, 0, 256, 256);
    for (let r = 0; r < 16; r++) for (let i = 0; i < 12; i++) {
      const k = rand();
      x.fillStyle = k < 0.7 ? '#1f2448' : k < 0.86 ? '#FFD88A' : k < 0.95 ? '#8FD8FF' : '#FFB36B';
      x.fillRect(i * 21 + 5, r * 16 + 4, 11, 8);
    }
    return finish(c);
  },
};

// ---------------------------------------------------------------------------------------------- styles
export const AREA_STYLE = {
  lobby: {
    floor: 'shag_orange',
    wall: { base: 'wood_walnut', baseboard: 'trim_chocolate', crown: 'trim_teak' },
    ceiling: 'ceiling_tile', fixtures: 'cans', lightPre: '#FFB45A', lightPost: '#FFC98A',
  },
  newsroom: {
    floor: 'vinyl_news',
    wall: { base: 'paint_news', wainscot: 'wood_teak', wainscotH: 1.1, rail: 'trim_chocolate', baseboard: 'trim_chocolate', crown: 'trim_cream' },
    ceiling: 'ceiling_tile', fixtures: 'panels', lightPre: null, lightPost: '#E8F5E1',
  },
  green_room: {
    floor: 'shag_avocado',
    wall: { base: 'paint_avocado', wainscot: 'wood_olive', wainscotH: 1.0, rail: 'trim_mustard', baseboard: 'trim_chocolate', crown: 'trim_cream' },
    ceiling: 'ceiling_tile', fixtures: 'panels', lightPre: null, lightPost: '#FFE6C0',
  },
  studio_a: {
    floor: 'concrete_studio',
    wall: { base: 'paint_studio', wainscot: 'quilt_plum', wainscotH: 3.0, rail: 'trim_black', baseboard: 'trim_black' },
    ceiling: 'ceiling_studio', fixtures: 'grid', gridY: 6.5, lightPre: null, lightPost: '#FFC4E4',
  },
  studio_b: {
    floor: 'wood_maple',
    wall: { base: 'paint_lilac', wainscot: 'quilt_pink', wainscotH: 2.2, rail: 'trim_cream', baseboard: 'trim_cream' },
    ceiling: 'ceiling_studio_b', fixtures: 'grid', gridY: 5.0, lightPre: null, lightPost: '#FFF1C9',
  },
  master_control: {
    floor: 'vinyl_mc',
    wall: { base: 'block_mc', baseboard: 'trim_black', crown: 'trim_steel' },
    ceiling: 'ceiling_tile_mc', fixtures: 'panels', lightPre: null, lightPost: '#DDF3FF',
  },
  yard: { floor: 'gravel' },
};

export const EXTERIOR_STYLE = { base: 'brick', wainscot: 'block_ext', wainscotH: 0.6, cap: 'trim_coping' };

// ------------------------------------------------------------------------------------------- factory
export function createSurfaces(game) {
  const rand = mulberry32(0x13131313);
  const tex = {};
  const T = (name, ...args) => (tex[name] ||= TEX[name](rand, ...args));
  const mats = game.mats;
  const toon = (color, o = {}) => mats.toon(color, { rim: 0.12, vertexColors: true, ...o });
  const woodPanel = (base) => game.tex.woodPanel(base);

  const defs = {
    // floors (rim off: floors should not glow at grazing angles)
    shag_orange: () => [toon('#ffffff', { map: game.tex.carpet('#D9602B', '#E8A92E'), rough: 0.95, rim: 0 }), [1.0, 1.0]],
    shag_avocado: () => [toon('#ffffff', { map: game.tex.carpet('#7E8C33', '#C9B458'), rough: 0.95, rim: 0 }), [1.0, 1.0]],
    vinyl_news: () => [toon('#ffffff', { map: game.tex.tiles('#EFE3C4', '#C98F3A', 4), rough: 0.42, rim: 0 }), [1.2, 1.2]],
    vinyl_mc: () => [toon('#ffffff', { map: game.tex.tiles('#C7CEC6', '#7F8F8C', 4), rough: 0.45, rim: 0 }), [1.2, 1.2]],
    metal_plate: () => [toon('#ffffff', { map: T('diamondPlate'), rough: 0.5, metal: 0.35, env: 0.3, rim: 0 }), [0.8, 0.8]],
    concrete_studio: () => [toon('#ffffff', { map: T('concrete'), rough: 0.7, rim: 0 }), [6, 6]],
    wood_maple: () => [toon('#ffffff', { map: T('planks'), rough: 0.5, rim: 0 }), [3, 3]],
    stage_wood: () => [toon('#C98E56', { map: T('planks'), rough: 0.4, rim: 0 }), [3, 3]],
    bleacher_wood: () => [toon('#D6A46C', { map: T('planks'), rough: 0.55, rim: 0.08 }), [3, 3]],
    riser_carpet: () => [toon('#ffffff', { map: game.tex.carpet('#8A3B2A', '#E3662B'), rough: 0.95, rim: 0 }), [1, 1]],
    gravel: () => [toon('#ffffff', { map: T('gravel'), rough: 0.95, rim: 0 }), [3, 3]],
    // walls
    wood_walnut: () => [toon('#ffffff', { map: woodPanel('#8A5530'), rough: 0.35, rimColor: '#FFC98A' }), [1.6, 2.4]],
    wood_teak: () => [toon('#ffffff', { map: woodPanel('#B07A45'), rough: 0.35, rimColor: '#9FC8FF' }), [1.6, 2.4]],
    wood_olive: () => [toon('#ffffff', { map: woodPanel('#6E6A2E'), rough: 0.4, rimColor: '#FFD08A' }), [1.6, 2.4]],
    paint_news: () => [toon('#E6D8B8', { map: T('plaster'), rough: 0.85, rimColor: '#9FC8FF' }), [2, 2]],
    paint_avocado: () => [toon('#9AA844', { map: T('plaster'), rough: 0.85, rimColor: '#FFD08A' }), [2, 2]],
    paint_studio: () => [toon('#4A3A58', { map: T('plaster'), rough: 0.9, rimColor: '#FF4FA0' }), [2, 2]],
    paint_lilac: () => [toon('#C8B4EA', { map: T('plaster'), rough: 0.85, rimColor: '#FFB6C8' }), [2, 2]],
    quilt_plum: () => [toon('#6B4A78', { map: T('quilt'), rough: 0.9, rimColor: '#FF4FA0' }), [1.2, 1.2]],
    quilt_pink: () => [toon('#F2B6C8', { map: T('quilt'), rough: 0.9, rimColor: '#FFB6C8' }), [1.2, 1.2]],
    quilt_red: () => [toon('#B5472A', { map: T('quilt'), rough: 0.7, rimColor: '#FFC98A' }), [0.9, 0.9]],
    block_mc: () => [toon('#8FA6B4', { map: T('block'), rough: 0.8, rimColor: '#7FE7FF' }), [1.6, 1.6]],
    brick: () => [toon('#ffffff', { map: T('brick'), rough: 0.9, rimColor: '#9FB6FF', rim: 0.18 }), [2.4, 2.4]],
    block_ext: () => [toon('#6F6A78', { map: T('block'), rough: 0.9, rimColor: '#9FB6FF' }), [1.6, 1.6]],
    // trims
    trim_chocolate: () => [toon('#5A3A22', { rough: 0.4 }), [1, 1]],
    trim_teak: () => [toon('#B07A45', { rough: 0.35 }), [1, 1]],
    trim_cream: () => [toon('#F6E7C8', { rough: 0.5 }), [1, 1]],
    trim_mustard: () => [toon('#D9A520', { rough: 0.45 }), [1, 1]],
    trim_black: () => [toon('#2A2230', { rough: 0.6 }), [1, 1]],
    trim_steel: () => [toon('#7C8A99', { rough: 0.45, metal: 0.45, env: 0.35 }), [1, 1]],
    trim_chrome: () => [toon('#DDE3EA', { rough: 0.25, metal: 1, env: 0.55 }), [1, 1]],
    trim_coping: () => [toon('#CFC6B8', { rough: 0.8, rim: 0.2, rimColor: '#9FB6FF' }), [1, 1]],
    trim_gold: () => [toon('#E8A92E', { rough: 0.3, metal: 0.8, env: 0.5 }), [1, 1]],
    // ceilings
    ceiling_tile: () => [toon('#F6EEDC', { map: T('acoustic'), rough: 0.95, rim: 0, emissive: '#8A7458', emissiveIntensity: 0.3 }), [1.2, 1.2]],
    ceiling_tile_mc: () => [toon('#DDE4E6', { map: T('acoustic'), rough: 0.95, rim: 0, emissive: '#4A6072', emissiveIntensity: 0.28 }), [1.2, 1.2]],
    ceiling_studio: () => [toon('#1D1724', { rough: 1, rim: 0 }), [1, 1]],
    ceiling_studio_b: () => [toon('#3A3150', { rough: 1, rim: 0 }), [1, 1]],
    // exterior
    grass: () => [toon('#ffffff', { map: T('grass'), rough: 1, rim: 0 }), [3, 3]],
    asphalt: () => [toon('#ffffff', { map: T('asphalt'), rough: 0.9, rim: 0 }), [4, 4]],
    sidewalk: () => [toon('#ffffff', { map: T('sidewalk'), rough: 0.9, rim: 0 }), [2, 2]],
    paint_line: () => [toon('#F2E6C0', { rough: 0.8, rim: 0 }), [1, 1]],
    paint_yellow: () => [toon('#E8C33A', { rough: 0.8, rim: 0 }), [1, 1]],
    chainlink: () => [toon('#C8CED6', { map: T('chainLink'), rough: 0.65, metal: 0.25, env: 0.2, alphaTest: 0.5, side: THREE.DoubleSide, rim: 0.15, rimColor: '#9FB6FF' }), [0.5, 0.5]],
    galvanized: () => [toon('#A7B0B9', { rough: 0.4, metal: 0.6, env: 0.4, rimColor: '#9FB6FF' }), [1, 1]],
    boards: () => [toon('#ffffff', { map: T('boards'), rough: 0.7, rim: 0.15 }), [1, 1]],
    // level extras: stage skirt, bleacher risers, roofs, storefronts, the unlit skyline facades
    bleacher_riser: () => [toon('#2F5BD3', { map: T('plaster'), rough: 0.6, rimColor: '#FF4FA0' }), [2, 2]],
    roof_gravel: () => [toon('#8A8494', { map: T('gravel'), rough: 1, rim: 0 }), [3, 3]],
    stucco_cream: () => [toon('#D9C7A0', { map: T('plaster'), rough: 0.9, rimColor: '#9FB6FF', rim: 0.18 }), [2, 2]],
    stucco_teal: () => [toon('#5E8C8C', { map: T('plaster'), rough: 0.9, rimColor: '#9FB6FF', rim: 0.18 }), [2, 2]],
    stucco_rust: () => [toon('#A0543A', { map: T('plaster'), rough: 0.9, rimColor: '#9FB6FF', rim: 0.18 }), [2, 2]],
    skyline: () => [mats.basic('#8C90B8', { map: T('skyline'), fog: false, vertexColors: true }), [16, 48]],
    storefront: () => [mats.basic('#ffffff', { map: T('skyline'), vertexColors: true }), [3, 3]],
  };

  const cache = new Map();
  const get = (key) => {
    let s = cache.get(key);
    if (!s) {
      const def = defs[key];
      if (!def) throw new Error(`[surfaces] unknown surface ${key}`);
      const [mat, tile] = def();
      s = { mat, tile, key };
      cache.set(key, s);
    }
    return s;
  };

  const plainCache = new Map();
  const plain = (key) => {
    let m = plainCache.get(key);
    if (!m) {
      const src = get(key).mat;
      m = mats.variant(src, { vertexColors: false });
      if (m === src) m = mats.basic(`#${src.color.getHexString()}`, { map: src.map, fog: src.fog });
      plainCache.set(key, m);
    }
    return m;
  };

  return { get, plain, tex: T, AREA_STYLE, EXTERIOR_STYLE };
}
