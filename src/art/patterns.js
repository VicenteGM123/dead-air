// Fabric/surface pattern tiles generated in code for the character material (browser only).
//   patternLayers(materials) -> { texture: THREE.DataArrayTexture (RGBA: sRGB albedo + linear height in A),
//                                layerOf: Int array per material index (-1 = none) }
// Material pattern spec: { type, scale (m per tile repeat), ...params } with types:
//   stripes {colors[], widths[], soft}      plaid {base, bands:[[color, width, pos, alpha]], weave}
//   denim {color, twill}                    corduroy {color, ribs}        knit {color, ribs}
//   floral {base, petal, center, density}   sequins {color, color2}      felt {color}
//   check {a, b, line}                      houndstooth {a, b}           argyle {a, b, c, line}
//   leather {color}                         solid {color} (fabric grain only)
// Tiles are 512 px; u runs "around" (x), v "along" (y). All tiles repeat seamlessly.
import * as THREE from 'three';

const SIZE = 512;
const cache = new Map();

function rgb(hex) {
  const c = new THREE.Color(hex);
  return [c.r, c.g, c.b]; // linear
}
const toSRGB = (c) => (c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);
const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const fract = (x) => x - Math.floor(x);
const sstep = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

// Tileable value noise on a periodic lattice.
function hash2(x, y, s = 0) {
  let h = (x * 374761393 + y * 668265263 + s * 982451653) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}
function vnoise(u, v, period, seed = 0) {
  const x = u * period, y = v * period;
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = x - xi, yf = y - yi;
  const P = (a) => ((a % period) + period) % period;
  const a = hash2(P(xi), P(yi), seed), b = hash2(P(xi + 1), P(yi), seed), c = hash2(P(xi), P(yi + 1), seed), d = hash2(P(xi + 1), P(yi + 1), seed);
  const sx = xf * xf * (3 - 2 * xf), sy = yf * yf * (3 - 2 * yf);
  return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
}
function fbm(u, v, base, oct, seed = 0) {
  let s = 0, amp = 0.5, p = base;
  for (let i = 0; i < oct; i++) { s += amp * vnoise(u, v, p, seed + i * 7); p *= 2; amp *= 0.5; }
  return s;
}
// Fine plain-weave grain shared by fabrics (value around 1).
const weave = (u, v, n = 160) => 1 + 0.05 * Math.sin(u * n * Math.PI * 2) * Math.sin(v * n * Math.PI * 2) + 0.04 * (vnoise(u, v, 64, 3) - 0.5);

const GEN = {
  solid(p) {
    const c = rgb(p.color || '#ffffff');
    return (u, v) => [...mul(c, weave(u, v)), 0.5];
  },
  stripes(p) {
    const cols = p.colors.map(rgb);
    const w = p.widths || cols.map(() => 1);
    const tot = w.reduce((a, b) => a + b, 0);
    const edges = [];
    let acc = 0;
    for (const x of w) { edges.push(acc / tot); acc += x; }
    const soft = (p.soft ?? 0.03) / cols.length;
    const vertical = p.vertical !== false;
    return (u, v) => {
      const t = vertical ? u : v;
      let i = cols.length - 1;
      for (let k = 0; k < edges.length; k++) if (t >= edges[k]) i = k;
      const next = (i + 1) % cols.length;
      const end = i + 1 < edges.length ? edges[i + 1] : 1;
      const prevEnd = edges[i];
      let c = cols[i];
      const dEnd = end - t, dStart = t - prevEnd;
      if (dEnd < soft) c = mix(c, cols[next], 0.5 * (1 - dEnd / soft));
      if (dStart < soft) c = mix(c, cols[(i - 1 + cols.length) % cols.length], 0.5 * (1 - dStart / soft));
      const g = weave(u, v, 180) * (1 + 0.035 * (vnoise(u * 4, v, 6, 11) - 0.5));
      const seam = Math.min(dEnd, dStart) < 0.004 ? 0.45 : 0.5;
      return [...mul(c, g), seam];
    };
  },
  plaid(p) {
    const base = rgb(p.base || '#B5703A');
    const bands = (p.bands || []).map(([col, width, pos, alpha]) => ({ c: rgb(col), w: width, p: pos, a: alpha ?? 0.85 }));
    const bandAt = (t) => {
      let c = base;
      for (const b of bands) {
        const d = Math.abs(fract(t - b.p + 0.5) - 0.5);
        const k = 1 - sstep(b.w * 0.5 - 0.004, b.w * 0.5 + 0.004, d);
        if (k > 0) c = mix(c, b.c, k * b.a);
      }
      return c;
    };
    const n = p.weave || 220;
    return (u, v) => {
      const warp = bandAt(u), weft = bandAt(v);
      const tw = fract((u + v) * n * 0.5) < 0.5 ? 0.62 : 0.38; // twill interleave
      const c = mix(warp, weft, tw);
      const g = 1 + 0.06 * (vnoise(u, v, 128, 5) - 0.5) + 0.04 * Math.sin((u + v) * n * Math.PI);
      return [...mul(c, g), 0.5 + 0.1 * Math.sin((u + v) * n * Math.PI)];
    };
  },
  denim(p) {
    const c = rgb(p.color || '#3A4FA0');
    const light = mix(c, [0.85, 0.87, 0.95], 0.45);
    const dark = mul(c, 0.7);
    const n = p.twill || 150;
    return (u, v) => {
      const tw = 0.5 + 0.5 * Math.sin((u * 1.0 + v * 0.55) * n * Math.PI * 2);
      const slub = vnoise(u * 0.5, v * 6, 8, 21) - 0.5; // vertical slub streaks
      const heat = fbm(u, v, 16, 3, 9) - 0.5;
      let col = mix(dark, c, 0.55 + 0.45 * tw);
      col = mix(col, light, Math.max(0, slub * 0.12 + heat * 0.12 + (hash2((u * SIZE) | 0, (v * SIZE) | 0, 4) - 0.5) * 0.14));
      return [...col, 0.35 + 0.3 * tw];
    };
  },
  corduroy(p) {
    const c = rgb(p.color || '#6B4226');
    const ribs = p.ribs || 22;
    return (u, v) => {
      const r = Math.pow(Math.abs(Math.sin(u * ribs * Math.PI)), 0.6);
      const g = 0.72 + 0.34 * r + 0.05 * (vnoise(u, v * 8, 32, 2) - 0.5);
      return [...mul(c, g), r];
    };
  },
  knit(p) {
    const c = rgb(p.color || '#F0641E');
    const ribs = p.ribs || 18;
    return (u, v) => {
      const x = fract(u * ribs), y = fract(v * ribs * 1.6);
      const vv = Math.abs(x - 0.5) * 2;
      const stitch = 1 - Math.abs(fract(y + vv * 0.5) - 0.5) * 2;
      const rib = Math.pow(Math.sin(x * Math.PI), 0.5);
      const g = 0.7 + 0.22 * rib + 0.12 * stitch;
      return [...mul(c, g), 0.3 + 0.5 * rib * (0.6 + 0.4 * stitch)];
    };
  },
  floral(p) {
    const base = rgb(p.base || '#F7F0E4'), petal = rgb(p.petal || '#F08A1E'), center = rgb(p.center || '#F7C531');
    const N = p.density || 5;
    return (u, v) => {
      let col = mul(base, weave(u, v));
      let h = 0.5;
      const gx = Math.floor(u * N), gy = Math.floor(v * N);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const cx = gx + dx, cy = gy + dy;
        const px = (cx + 0.2 + 0.6 * hash2(((cx % N) + N) % N, ((cy % N) + N) % N, 1)) / N;
        const py = (cy + 0.2 + 0.6 * hash2(((cx % N) + N) % N, ((cy % N) + N) % N, 2)) / N;
        const ddx = u - px, ddy = v - py;
        const r = Math.hypot(ddx, ddy) * N;
        if (r > 0.45) continue;
        const a = Math.atan2(ddy, ddx) + hash2(cx, cy, 3) * 6.28;
        const pr = 0.3 + 0.1 * Math.cos(a * 5);
        if (r < 0.08) { col = center; h = 0.7; } else if (r < pr) { col = mix(petal, mul(petal, 1.15), r / pr); h = 0.6; }
      }
      return [...col, h];
    };
  },
  sequins(p) {
    const c = rgb(p.color || '#E8B64A'), c2 = rgb(p.color2 || p.color || '#FFE6A0');
    const N = p.count || 24;
    return (u, v) => {
      const y = v * N * 1.15, row = Math.floor(y);
      const x = u * N + (row % 2) * 0.5, col = Math.floor(x);
      const fx = x - col - 0.5, fy = y - row - 0.5;
      const r = Math.hypot(fx, fy);
      const k = hash2(((col % N) + N) % N, ((row % Math.round(N * 1.15)) + 100) % 1000, 7);
      const disc = 1 - sstep(0.4, 0.46, r);
      const shade = mix(c, c2, k) ;
      const g = disc ? (0.75 + 0.5 * k) * (1 - 0.35 * r) : 0.35;
      return [...mul(shade, g), 0.3 + 0.6 * disc * (1 - r)];
    };
  },
  felt(p) {
    const c = rgb(p.color || '#8C9A3A');
    return (u, v) => {
      const n = fbm(u, v, 32, 4, 13);
      return [...mul(c, 0.86 + 0.28 * n), 0.4 + 0.3 * n];
    };
  },
  check(p) {
    const a = rgb(p.a || '#7A4A2A'), b = rgb(p.b || '#B07A45'), line = rgb(p.line || '#E8A92E');
    const N = p.count || 4;
    return (u, v) => {
      const cx = Math.floor(u * N * 2), cy = Math.floor(v * N * 2);
      let c = (cx + cy) % 2 ? a : mix(a, b, 0.5);
      if (cx % 2 && cy % 2) c = b;
      const lu = Math.abs(fract(u * N) - 0.5), lv = Math.abs(fract(v * N) - 0.5);
      if (lu < 0.02 || lv < 0.02) c = mix(c, line, 0.8);
      return [...mul(c, weave(u, v, 200)), 0.5];
    };
  },
  houndstooth(p) {
    const a = rgb(p.a || '#2A2230'), b = rgb(p.b || '#F4F1E8');
    const N = p.count || 8;
    return (u, v) => {
      const x = u * N * 4, y = v * N * 4;
      const i = Math.floor(x) % 4, j = Math.floor(y) % 4;
      const fx = fract(x), fy = fract(y);
      let dark = (i < 2) === (j < 2) ? i < 2 : false;
      if ((i === 2 && j === 1) || (i === 1 && j === 2)) dark = fx + fy > 1;
      if ((i === 3 && j === 0) || (i === 0 && j === 3)) dark = fx + fy < 1;
      return [...mul(dark ? a : b, weave(u, v, 200)), dark ? 0.45 : 0.55];
    };
  },
  argyle(p) {
    const a = rgb(p.a || '#6B3A6E'), b = rgb(p.b || '#E8A92E'), c = rgb(p.c || '#2E8C8C'), line = rgb(p.line || '#F4F1E8');
    return (u, v) => {
      const x = fract(u) * 2 - 1, y = fract(v * 0.7) * 2 - 1;
      const inD = Math.abs(x) + Math.abs(y) < 1;
      let col = inD ? a : ((Math.floor(u * 2 + v * 0.7) % 2) ? b : c);
      const l1 = Math.abs(fract((u + v * 0.7) * 2) - 0.5), l2 = Math.abs(fract((u - v * 0.7) * 2) - 0.5);
      if (l1 < 0.012 || l2 < 0.012) col = line;
      return [...mul(col, weave(u, v, 120)), 0.5];
    };
  },
  leather(p) {
    const c = rgb(p.color || '#6B3A22');
    return (u, v) => {
      const n = fbm(u, v, 24, 3, 17), cell = vnoise(u, v, 90, 23);
      return [...mul(c, 0.9 + 0.15 * n), 0.35 + 0.4 * cell];
    };
  },
};

function makeTile(spec) {
  const gen = (GEN[spec.type] || GEN.solid)(spec);
  const data = new Uint8Array(SIZE * SIZE * 4);
  let o = 0;
  for (let y = 0; y < SIZE; y++) {
    const v = (y + 0.5) / SIZE;
    for (let x = 0; x < SIZE; x++) {
      const u = (x + 0.5) / SIZE;
      const [r, g, b, h] = gen(u, v);
      data[o++] = Math.round(Math.min(1, Math.max(0, toSRGB(r))) * 255);
      data[o++] = Math.round(Math.min(1, Math.max(0, toSRGB(g))) * 255);
      data[o++] = Math.round(Math.min(1, Math.max(0, toSRGB(b))) * 255);
      data[o++] = Math.round(Math.min(1, Math.max(0, h)) * 255);
    }
  }
  return data;
}

export function patternLayers(materials) {
  const list = Array.isArray(materials) ? materials : Object.values(materials);
  const specs = [];
  const layerOf = list.map((m) => {
    if (!m.pattern) return -1;
    const key = JSON.stringify(m.pattern);
    let i = specs.indexOf(key);
    if (i < 0) { specs.push(key); i = specs.length - 1; }
    return i;
  });
  const key = specs.join('|') || 'none';
  let tex = cache.get(key);
  if (!tex) {
    const n = Math.max(1, specs.length);
    const data = new Uint8Array(SIZE * SIZE * 4 * n);
    specs.forEach((s, i) => {
      let tile = cache.get('tile:' + s);
      if (!tile) { tile = makeTile(JSON.parse(s)); cache.set('tile:' + s, tile); }
      data.set(tile, i * SIZE * SIZE * 4);
    });
    if (!specs.length) data.fill(255);
    tex = new THREE.DataArrayTexture(data, SIZE, SIZE, n);
    tex.format = THREE.RGBAFormat;
    tex.type = THREE.UnsignedByteType;
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.magFilter = THREE.LinearFilter;
    tex.minFilter = THREE.LinearMipmapLinearFilter;
    tex.generateMipmaps = true;
    tex.anisotropy = 8;
    tex.needsUpdate = true;
    cache.set(key, tex);
  }
  return { texture: tex, layerOf };
}
