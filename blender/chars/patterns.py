"""Fabric/surface pattern tiles for the character material — pixel port of src/art/patterns.js (numpy).
  makeTile(spec) -> (512, 512, 4) uint8 RGBA (sRGB albedo + LINEAR height in A)
  patternLayers(materials) -> (specs [json key], layerOf [int per material index, -1 = none])
  write_tiles(materials, out_dir) -> list of file names (layer order)
Material pattern spec: { type, scale (m per tile repeat), ...params } with types:
  stripes {colors[], widths[], soft}      plaid {base, bands:[[color, width, pos, alpha]], weave}
  denim {color, twill}                    corduroy {color, ribs}        knit {color, ribs}
  floral {base, petal, center, density}   sequins {color, color2}      felt {color}
  check {a, b, line}                      houndstooth {a, b}           argyle {a, b, c, line}
  leather {color}                         solid {color} (fabric grain only)
Tiles are 512 px; u runs "around" (x), v "along" (y). All tiles repeat seamlessly.
"""
import hashlib
import json
import math
import os

import numpy as np

SIZE = 512
M32 = 0xFFFFFFFF


def rgb(hexv):
    h = str(hexv).lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    v = int(h[:6], 16)
    c = [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255]
    return np.array([x / 12.92 if x < 0.04045 else ((x * 0.9478672986 + 0.0521327014) ** 2.4) for x in c])  # linear


def toSRGB(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)


def mix(a, b, t):
    t = np.asarray(t, float)
    return a + (b - a) * (t[..., None] if t.ndim else t)


def fract(x):
    return x - np.floor(x)


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def _i32(x):
    """JS ToInt32 of an integer array (int64 in)."""
    x = np.asarray(x, np.int64) & M32
    return np.where(x >= 2 ** 31, x - 2 ** 32, x)


def hash2(x, y, s=0):
    """Tileable value-noise hash (JS: imul / >>> semantics on 32 bits)."""
    x = np.asarray(x, np.int64)
    y = np.asarray(y, np.int64)
    h = (x * 374761393 + y * 668265263 + np.int64(s) * 982451653) & M32      # (… | 0) as uint32 bits
    h = ((h ^ (h >> 13)) * 1274126177) & M32                                   # Math.imul(h ^ (h >>> 13), …)
    return ((h ^ (h >> 16)) & M32).astype(np.float64) / 4294967296


def vnoise(u, v, period, seed=0):
    x, y = u * period, v * period
    xi, yi = np.floor(x), np.floor(y)
    xf, yf = x - xi, y - yi
    xi = xi.astype(np.int64)
    yi = yi.astype(np.int64)

    def P(a):
        return ((a % period) + period) % period
    a = hash2(P(xi), P(yi), seed)
    b = hash2(P(xi + 1), P(yi), seed)
    c = hash2(P(xi), P(yi + 1), seed)
    d = hash2(P(xi + 1), P(yi + 1), seed)
    sx, sy = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy


def fbm(u, v, base, oct, seed=0):
    s, amp, p = 0.0, 0.5, base
    for i in range(oct):
        s = s + amp * vnoise(u, v, p, seed + i * 7)
        p *= 2
        amp *= 0.5
    return s


def weave(u, v, n=160):
    """Fine plain-weave grain shared by fabrics (value around 1)."""
    return 1 + 0.05 * np.sin(u * n * math.pi * 2) * np.sin(v * n * math.pi * 2) + 0.04 * (vnoise(u, v, 64, 3) - 0.5)


def _out(col, h):
    return col, np.broadcast_to(np.asarray(h, float), col.shape[:-1])


def g_solid(p, u, v):
    c = rgb(p.get('color') or '#ffffff')
    return _out(c * weave(u, v)[..., None], 0.5)


def g_stripes(p, u, v):
    cols = np.array([rgb(c) for c in p['colors']])
    n = len(cols)
    w = p.get('widths') or [1] * n
    tot = sum(w)
    edges = []
    acc = 0
    for x in w:
        edges.append(acc / tot)
        acc += x
    edges = np.array(edges)
    soft = (p['soft'] if p.get('soft') is not None else 0.03) / n
    vertical = p.get('vertical') is not False
    t = u if vertical else v
    i = np.full(t.shape, n - 1)
    for k in range(len(edges)):
        i = np.where(t >= edges[k], k, i)
    nxt = (i + 1) % n
    end = np.where(i + 1 < len(edges), edges[np.minimum(i + 1, len(edges) - 1)], 1.0)
    prevEnd = edges[i]
    c = cols[i]
    dEnd = end - t
    dStart = t - prevEnd
    c = np.where((dEnd < soft)[..., None], mix(c, cols[nxt], 0.5 * (1 - dEnd / soft)), c)
    c = np.where((dStart < soft)[..., None], mix(c, cols[(i - 1 + n) % n], 0.5 * (1 - dStart / soft)), c)
    g = weave(u, v, 180) * (1 + 0.035 * (vnoise(u * 4, v, 6, 11) - 0.5))
    seam = np.where(np.minimum(dEnd, dStart) < 0.004, 0.45, 0.5)
    return c * g[..., None], seam


def g_plaid(p, u, v):
    base = rgb(p.get('base') or '#B5703A')
    bands = [dict(c=rgb(b[0]), w=b[1], p=b[2], a=b[3] if len(b) > 3 and b[3] is not None else 0.85) for b in (p.get('bands') or [])]

    def bandAt(t):
        c = np.broadcast_to(base, t.shape + (3,)).copy()
        for b in bands:
            d = np.abs(fract(t - b['p'] + 0.5) - 0.5)
            k = 1 - sstep(b['w'] * 0.5 - 0.004, b['w'] * 0.5 + 0.004, d)
            c = np.where((k > 0)[..., None], mix(c, b['c'], k * b['a']), c)
        return c
    n = p.get('weave') or 220
    warp, weft = bandAt(u), bandAt(v)
    tw = np.where(fract((u + v) * n * 0.5) < 0.5, 0.62, 0.38)
    c = mix(warp, weft, tw)
    g = 1 + 0.06 * (vnoise(u, v, 128, 5) - 0.5) + 0.04 * np.sin((u + v) * n * math.pi)
    return c * g[..., None], 0.5 + 0.1 * np.sin((u + v) * n * math.pi)


def g_denim(p, u, v):
    c = rgb(p.get('color') or '#3A4FA0')
    light = mix(c, np.array([0.85, 0.87, 0.95]), 0.45)
    dark = c * 0.7
    n = p.get('twill') or 150
    tw = 0.5 + 0.5 * np.sin((u * 1.0 + v * 0.55) * n * math.pi * 2)
    slub = vnoise(u * 0.5, v * 6, 8, 21) - 0.5   # vertical slub streaks
    heat = fbm(u, v, 16, 3, 9) - 0.5
    col = mix(dark, c, 0.55 + 0.45 * tw)
    hh = hash2(np.floor(u * SIZE).astype(np.int64), np.floor(v * SIZE).astype(np.int64), 4)
    col = mix(col, light, np.maximum(0, slub * 0.12 + heat * 0.12 + (hh - 0.5) * 0.14))
    return col, 0.35 + 0.3 * tw


def g_corduroy(p, u, v):
    c = rgb(p.get('color') or '#6B4226')
    ribs = p.get('ribs') or 22
    r = np.power(np.abs(np.sin(u * ribs * math.pi)), 0.6)
    g = 0.72 + 0.34 * r + 0.05 * (vnoise(u, v * 8, 32, 2) - 0.5)
    return c * g[..., None], r


def g_knit(p, u, v):
    c = rgb(p.get('color') or '#F0641E')
    ribs = p.get('ribs') or 18
    x, y = fract(u * ribs), fract(v * ribs * 1.6)
    vv = np.abs(x - 0.5) * 2
    stitch = 1 - np.abs(fract(y + vv * 0.5) - 0.5) * 2
    rib = np.power(np.sin(x * math.pi), 0.5)
    g = 0.7 + 0.22 * rib + 0.12 * stitch
    return c * g[..., None], 0.3 + 0.5 * rib * (0.6 + 0.4 * stitch)


def g_floral(p, u, v):
    base, petal, center = rgb(p.get('base') or '#F7F0E4'), rgb(p.get('petal') or '#F08A1E'), rgb(p.get('center') or '#F7C531')
    N = p.get('density') or 5
    col = base * weave(u, v)[..., None]
    h = np.full(u.shape, 0.5)
    gx, gy = np.floor(u * N).astype(np.int64), np.floor(v * N).astype(np.int64)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = gx + dx, gy + dy
            wx, wy = ((cx % N) + N) % N, ((cy % N) + N) % N
            px = (cx + 0.2 + 0.6 * hash2(wx, wy, 1)) / N
            py = (cy + 0.2 + 0.6 * hash2(wx, wy, 2)) / N
            ddx, ddy = u - px, v - py
            r = np.hypot(ddx, ddy) * N
            a = np.arctan2(ddy, ddx) + hash2(cx, cy, 3) * 6.28
            pr = 0.3 + 0.1 * np.cos(a * 5)
            inr = r <= 0.45
            m1 = inr & (r < 0.08)
            m2 = inr & ~m1 & (r < pr)
            col = np.where(m1[..., None], center, col)
            h = np.where(m1, 0.7, h)
            col = np.where(m2[..., None], mix(petal, petal * 1.15, r / pr), col)
            h = np.where(m2, 0.6, h)
    return col, h


def g_sequins(p, u, v):
    c = rgb(p.get('color') or '#E8B64A')
    c2 = rgb(p.get('color2') or p.get('color') or '#FFE6A0')
    N = p.get('count') or 24
    y = v * N * 1.15
    row = np.floor(y).astype(np.int64)
    x = u * N + (row % 2) * 0.5
    col = np.floor(x).astype(np.int64)
    fx, fy = x - col - 0.5, y - row - 0.5
    r = np.hypot(fx, fy)
    RN = int(math.floor(N * 1.15 + 0.5))
    k = hash2(((col % N) + N) % N, ((row % RN) + 100) % 1000, 7)
    disc = 1 - sstep(0.4, 0.46, r)
    shade = mix(c, c2, k)
    g = np.where(disc != 0, (0.75 + 0.5 * k) * (1 - 0.35 * r), 0.35)
    return shade * g[..., None], 0.3 + 0.6 * disc * (1 - r)


def g_felt(p, u, v):
    c = rgb(p.get('color') or '#8C9A3A')
    n = fbm(u, v, 32, 4, 13)
    return c * (0.86 + 0.28 * n)[..., None], 0.4 + 0.3 * n


def g_check(p, u, v):
    a, b, line = rgb(p.get('a') or '#7A4A2A'), rgb(p.get('b') or '#B07A45'), rgb(p.get('line') or '#E8A92E')
    N = p.get('count') or 4
    cx, cy = np.floor(u * N * 2).astype(np.int64), np.floor(v * N * 2).astype(np.int64)
    c = np.where((((cx + cy) % 2) != 0)[..., None], a, mix(a, b, 0.5))
    c = np.where(((cx % 2 != 0) & (cy % 2 != 0))[..., None], b, c)
    lu, lv = np.abs(fract(u * N) - 0.5), np.abs(fract(v * N) - 0.5)
    c = np.where(((lu < 0.02) | (lv < 0.02))[..., None], mix(c, line, 0.8), c)
    return c * weave(u, v, 200)[..., None], 0.5


def g_houndstooth(p, u, v):
    a, b = rgb(p.get('a') or '#2A2230'), rgb(p.get('b') or '#F4F1E8')
    N = p.get('count') or 8
    x, y = u * N * 4, v * N * 4
    i, j = np.floor(x).astype(np.int64) % 4, np.floor(y).astype(np.int64) % 4
    fx, fy = fract(x), fract(y)
    dark = np.where((i < 2) == (j < 2), i < 2, False)
    dark = np.where(((i == 2) & (j == 1)) | ((i == 1) & (j == 2)), fx + fy > 1, dark)
    dark = np.where(((i == 3) & (j == 0)) | ((i == 0) & (j == 3)), fx + fy < 1, dark)
    return np.where(dark[..., None], a, b) * weave(u, v, 200)[..., None], np.where(dark, 0.45, 0.55)


def g_argyle(p, u, v):
    a, b, c, line = rgb(p.get('a') or '#6B3A6E'), rgb(p.get('b') or '#E8A92E'), rgb(p.get('c') or '#2E8C8C'), rgb(p.get('line') or '#F4F1E8')
    x, y = fract(u) * 2 - 1, fract(v * 0.7) * 2 - 1
    inD = np.abs(x) + np.abs(y) < 1
    col = np.where(inD[..., None], a, np.where(((np.floor(u * 2 + v * 0.7).astype(np.int64) % 2) != 0)[..., None], b, c))
    l1, l2 = np.abs(fract((u + v * 0.7) * 2) - 0.5), np.abs(fract((u - v * 0.7) * 2) - 0.5)
    col = np.where(((l1 < 0.012) | (l2 < 0.012))[..., None], line, col)
    return col * weave(u, v, 120)[..., None], 0.5


def g_leather(p, u, v):
    c = rgb(p.get('color') or '#6B3A22')
    n, cell = fbm(u, v, 24, 3, 17), vnoise(u, v, 90, 23)
    return c * (0.9 + 0.15 * n)[..., None], 0.35 + 0.4 * cell


GEN = {'solid': g_solid, 'stripes': g_stripes, 'plaid': g_plaid, 'denim': g_denim, 'corduroy': g_corduroy,
       'knit': g_knit, 'floral': g_floral, 'sequins': g_sequins, 'felt': g_felt, 'check': g_check,
       'houndstooth': g_houndstooth, 'argyle': g_argyle, 'leather': g_leather}


def makeTile(spec):
    gen = GEN.get(spec.get('type'), g_solid)
    y = (np.arange(SIZE) + 0.5) / SIZE
    x = (np.arange(SIZE) + 0.5) / SIZE
    v, u = np.meshgrid(y, x, indexing='ij')         # rows = y (v), cols = x (u)
    col, h = gen(spec, u, v)
    col = np.broadcast_to(col, (SIZE, SIZE, 3))
    h = np.broadcast_to(np.asarray(h, float), (SIZE, SIZE))
    out = np.zeros((SIZE, SIZE, 4), np.uint8)
    out[..., :3] = np.floor(np.clip(toSRGB(col), 0, 1) * 255 + 0.5).astype(np.uint8)
    out[..., 3] = np.floor(np.clip(h, 0, 1) * 255 + 0.5).astype(np.uint8)
    return out


def js_json(v):
    """JSON.stringify of plain data (key order kept, JS number formatting)."""
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if v is None:
        return 'null'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e21:
            return str(int(v))
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return '[' + ','.join(js_json(x) for x in v) + ']'
    if isinstance(v, dict):
        return '{' + ','.join(json.dumps(k) + ':' + js_json(x) for k, x in v.items()) + '}'
    raise TypeError(type(v))


def patternLayers(materials):
    lst = list(materials.values()) if isinstance(materials, dict) else list(materials)
    specs = []
    layerOf = []
    for m in lst:
        if not m.get('pattern'):
            layerOf.append(-1)
            continue
        key = js_json(m['pattern'])
        if key not in specs:
            specs.append(key)
        layerOf.append(specs.index(key))
    return specs, layerOf


def tile_file(key):
    spec = json.loads(key)
    h = hashlib.sha1(key.encode('utf-8')).hexdigest()[:8]
    return '%s_%s.png' % (spec.get('type', 'solid'), h)


IMPORT_FILE = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
process/fix_alpha_border=false
mipmaps/generate=false
detect_3d/compress_to=0
"""


def write_tiles(materials, out_dir):
    """Writes the PNG of every pattern layer (once; skipped when present) -> (files, layerOf)."""
    import skia
    specs, layerOf = patternLayers(materials)
    files = []
    os.makedirs(out_dir, exist_ok=True)
    for key in specs:
        fn = tile_file(key)
        path = os.path.join(out_dir, fn)
        if not os.path.exists(path):
            arr = np.ascontiguousarray(makeTile(json.loads(key)))
            img = skia.Image.fromarray(arr, skia.ColorType.kRGBA_8888_ColorType, skia.AlphaType.kUnpremul_AlphaType)
            with open(path + '.tmp', 'wb') as f:
                f.write(bytes(img.encodeToData(skia.EncodedImageFormat.kPNG, 100)))
            os.replace(path + '.tmp', path)
            imp = path + '.import'
            if not os.path.exists(imp):
                with open(imp, 'w') as f:
                    f.write(IMPORT_FILE)
        files.append(fn)
    return files, layerOf
