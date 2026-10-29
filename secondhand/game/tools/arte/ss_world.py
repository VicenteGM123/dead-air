"""Secondhand Stars · mundo: texturas que se repiten (assets/tex) y props del taller y de la calle (assets/props).

Texturas: ruido que se repite (filtro gaussiano con 'wrap') cuantizado a una rampa corta elegida a mano (4-6 tonos,
nada de degradés sucios), con rasgos dibujados que también dan la vuelta (ondas de arena, grietas, remaches...).
Props: el mismo lienzo y render HD-2D que los personajes (luz arriba a la izquierda, contorno selectivo).
props.json da para cada prop el tamaño de píxel sugerido en el mundo (px, unidades por píxel de textura; los
personajes usan 0.0222) y el ancla ('bottom' = se apoya en el suelo, 'top' = cuelga, 'center' = cielo / pared).

Uso: python3 ss_world.py [--out DIR] [tex|props|sky ...]
"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def hexc(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def noise(w, h, sigma, seed):
    rng = np.random.RandomState(seed)
    n = rng.rand(h, w)
    n = ndi.gaussian_filter(n, sigma, mode='wrap')
    n = (n - n.min()) / (n.max() - n.min() + 1e-9)
    return n


def quant(v, ramp, cuts=None):
    """v en 0..1 -> índices de la rampa (cortes parejos o dados)."""
    k = len(ramp)
    if cuts is None:
        cuts = np.linspace(0, 1, k + 1)[1:-1]
    idx = np.digitize(v, cuts)
    return idx


def to_img(idx, ramp, alpha=None):
    pal = np.array([hexc(c) for c in ramp], np.uint8)
    rgb = pal[np.clip(idx, 0, len(ramp) - 1)]
    if alpha is None:
        return Image.fromarray(rgb, 'RGB')
    a = np.where(alpha, 255, 0).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, a]), 'RGBA')


def wline(idx, pts, val, w, h, delta=False):
    """Línea de 1 px que da la vuelta (para texturas que se repiten). delta: suma val al índice en vez de fijarlo."""
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for t in np.linspace(0, 1, n):
            x = int(round(x0 + (x1 - x0) * t)) % w
            y = int(round(y0 + (y1 - y0) * t)) % h
            if delta:
                idx[y, x] = idx[y, x] + val
            else:
                idx[y, x] = val


# ================================================================== texturas

SAND = ['#9a6c44', '#b88a58', '#cfa470', '#dfb984', '#ecce9c', '#f6e2b8']


def tex_sand(w=64, h=64, seed=3):
    n = noise(w, h, 3.0, seed) * 0.65 + noise(w, h, 1.0, seed + 1) * 0.35
    idx = quant(n, SAND[1:5], cuts=[0.30, 0.52, 0.74]) + 1
    # ondas del viento: pares oscuro/claro que cruzan en diagonal suave, dan la vuelta
    ys, xs = np.mgrid[0:h, 0:w]
    for k in range(4):
        y0 = k * h / 4 + 3
        for x in range(w):
            y = y0 + 2.2 * math.sin(2 * math.pi * x / w * 2 + k * 1.3)
            yy = int(round(y)) % h
            if (x + k * 7) % 11 < 8:
                idx[yy, x] = max(1, idx[yy, x] - 1)
                idx[(yy - 1) % h, x] = min(5, idx[(yy - 1) % h, x] + 1)
    # piedritas: 3 px con luz arriba a la izquierda y sombra abajo
    rng = np.random.RandomState(seed + 5)
    for _ in range(7):
        x, y = rng.randint(0, w), rng.randint(0, h)
        idx[y % h, x % w] = 4
        idx[y % h, (x + 1) % w] = 2
        idx[(y + 1) % h, x % w] = 1
        idx[(y + 1) % h, (x + 1) % w] = 0
    return to_img(idx, SAND)


ADOBE = ['#8a6444', '#a8805a', '#c49e74', '#d6b488', '#e4c8a0', '#efdcbc']


def tex_adobe(w=128, h=128, seed=11):
    n = noise(w, h, 6.0, seed) * 0.7 + noise(w, h, 1.2, seed + 2) * 0.3
    idx = quant(n, ADOBE[2:5], cuts=[0.40, 0.66]) + 2
    rng = np.random.RandomState(seed + 3)
    # parches de revoque nuevo (un tono más claro, bordes netos)
    ys, xs = np.mgrid[0:h, 0:w]
    for _ in range(4):
        cx, cy = rng.randint(0, w), rng.randint(0, h)
        rx, ry = rng.randint(8, 18), rng.randint(6, 12)
        dx = ((xs - cx + w / 2) % w) - w / 2
        dy = ((ys - cy + h / 2) % h) - h / 2
        m = (dx / rx) ** 2 + (dy / ry) ** 2 <= 1.0
        idx[m] = np.minimum(5, idx[m] + 1)
        edge = m & ~ndi.binary_erosion(m)
        idx[edge & (dy > 0)] = 2
    # grietas finas: línea oscura con un borde claro arriba (pocas: con muchas se nota la repetición)
    for _ in range(3):
        x, y = rng.randint(0, w), rng.randint(0, h)
        pts = [(x, y)]
        for k in range(rng.randint(2, 4)):
            x += rng.randint(2, 6) * rng.choice([-1, 1])
            y += rng.randint(2, 6)
            pts.append((x, y))
        wline(idx, [(a, b - 1) for a, b in pts], 5, w, h)
        wline(idx, pts, 0, w, h)
    # agujeritos y briznas de paja
    for _ in range(14):
        x, y = rng.randint(0, w), rng.randint(0, h)
        if rng.rand() < 0.5:
            idx[y, x] = 1
            idx[(y + 1) % h, x] = 0
        else:
            idx[y, x] = 5
            idx[y, (x + 1) % w] = 4
    return to_img(idx, ADOBE)


METAL = ['#26302e', '#3e4c4a', '#56686a', '#6e8486', '#8aa0a0', '#a8bcb8', '#9a5434', '#c07a44']


def tex_metal_plate(w=64, h=64, seed=21):
    n = noise(w, h, 4.0, seed)
    idx = quant(n, METAL[2:5], cuts=[0.35, 0.68]) + 2
    # cuatro planchas de 32x32: costura oscura abajo/derecha, filo claro arriba/izquierda
    for k in range(0, w, 32):
        idx[:, k] = 0
        idx[:, (k + 1) % w] = 5
    for k in range(0, h, 32):
        idx[k, :] = 0
        idx[(k + 1) % h, :] = 5
    # remaches cada 8 px a lo largo de las costuras
    for k in range(0, w, 32):
        for y in range(4, h, 8):
            if y % 32 in (0, 1, 31):
                continue
            x = (k + 3) % w
            idx[y, x] = 5
            idx[y, (x + 1) % w] = 3
            idx[(y + 1) % h, x] = 3
            idx[(y + 1) % h, (x + 1) % w] = 1
    for k in range(0, h, 32):
        for x in range(4, w, 8):
            if x % 32 in (0, 1, 31):
                continue
            y = (k + 3) % h
            idx[y, x] = 5
            idx[y, (x + 1) % w] = 3
            idx[(y + 1) % h, x] = 3
            idx[(y + 1) % h, (x + 1) % w] = 1
    # óxido en las costuras (manchas chicas) y rayones claros
    rng = np.random.RandomState(seed + 1)
    for _ in range(6):
        x, y = rng.choice([1, 2, 33, 34]), rng.randint(0, h)
        for k in range(rng.randint(2, 5)):
            idx[(y + k) % h, x % w] = 6 if k % 2 else 7
    for _ in range(5):
        x, y = rng.randint(0, w), rng.randint(0, h)
        L = rng.randint(3, 7)
        wline(idx, [(x, y), (x + L, y + L // 3)], 4, w, h)
    return to_img(idx, METAL)


RUST = ['#3a2218', '#5e3422', '#844a2c', '#a8623a', '#c47c48', '#d89a62', '#4e7a74', '#6e9a92']


def tex_rusted_panel(w=64, h=64, seed=31):
    n = noise(w, h, (5.0, 2.0), seed)
    idx = quant(n, RUST[2:6], cuts=[0.30, 0.55, 0.78]) + 2
    # chapa acanalada vertical: cada 8 px un canal (oscuro / claro)
    for x in range(0, w, 8):
        idx[:, x] = np.maximum(1, idx[:, x] - 2)
        idx[:, (x + 1) % w] = np.maximum(1, idx[:, (x + 1) % w] - 1)
        idx[:, (x + 4) % w] = np.minimum(5, idx[:, (x + 4) % w] + 1)
    # restos de una franja de pintura verde agua vieja, descascarada (borde de arriba y de abajo irregulares)
    rng = np.random.RandomState(seed + 2)
    ys, xs = np.mgrid[0:h, 0:w]
    top = 18 + (noise(w, 1, 2.0, seed + 3)[0] * 8).astype(int)
    bot = 34 + (noise(w, 1, 1.5, seed + 4)[0] * 10).astype(int)
    paint = (ys >= top[None, :]) & (ys <= bot[None, :])
    holes = noise(w, h, 1.6, seed + 5) > 0.72
    paint &= ~holes
    idx[paint] = 7
    idx[paint & ((xs % 8) <= 1)] = 6
    edge = paint & ~ndi.binary_erosion(paint)
    idx[edge] = 6
    # chorreaduras de óxido hacia abajo
    for _ in range(6):
        x, y = rng.randint(0, w), rng.randint(0, h)
        for k in range(rng.randint(5, 14)):
            idx[(y + k) % h, x] = 1 if k % 3 else 2
    return to_img(idx, RUST)


TILE = ['#4e3428', '#6c4634', '#875a40', '#9c6c4c', '#b0805c', '#c49a74', '#cdbd9e', '#a89a80', '#6e8482', '#8aa0a0']


def tex_tile(w=128, h=128, seed=41):
    """Piso del taller: baldosas de barro cocido de 16 px (textura de 128), gastadas, alguna más oscura y alguna rota."""
    n = noise(w, h, 2.5, seed)
    idx = quant(n, TILE[2:6], cuts=[0.33, 0.6, 0.82]) + 2
    rng = np.random.RandomState(seed + 1)
    for ty in range(0, h, 16):
        for tx in range(0, w, 16):
            tone = rng.choice([-1, 0, 0, 1])
            sub = (slice(ty, ty + 16), slice(tx, tx + 16))
            idx[sub] = np.clip(idx[sub] + tone, 2, 5)
            if rng.rand() < 0.08:
                # baldosa más gastada (un tono más oscura): nada de chapas, que repetidas forman una grilla
                idx[sub] = np.clip(idx[sub] - 1, 1, 5)
            # luz en el borde de arriba / izquierda de cada baldosa
            idx[ty + 1, tx + 1:tx + 15] = np.minimum(idx[ty + 1, tx + 1:tx + 15] + 1, 5) * (idx[ty + 1, tx + 1:tx + 15] < 8) + \
                idx[ty + 1, tx + 1:tx + 15] * (idx[ty + 1, tx + 1:tx + 15] >= 8)
    # juntas (lechada) y una grieta
    idx[:, ::16] = 7
    idx[::16, :] = 7
    idx[:, 15::16] = 1
    idx[15::16, :] = 1
    wline(idx, [(37, 20), (40, 24), (39, 27), (43, 30)], 0, w, h)
    wline(idx, [(101, 84), (104, 88), (103, 91)], 0, w, h)
    # despostillado en esquinas
    for (x, y) in ((17, 17), (49, 33), (2, 50), (81, 97), (113, 65)):
        idx[y, x] = 6
        idx[y, x + 1] = 6
    return to_img(idx, TILE)


def tex_canopy(w=64, h=64, seed=51, a='#b4452e', b='#ece0c4'):
    """Lona de los puestos: rayas verticales de 8 px gastadas por el sol, trama fina y pliegues suaves."""
    ra = [a, '#ffffff', '#ffffff']
    base_a, base_b = hexc(a), hexc(b)

    def shades(c):
        r, g, bb = c
        return [tuple(int(v * k) for v in c) for k in (0.74, 0.87, 1.0)] + [tuple(min(255, int(v * 1.0 + 14)) for v in c)]
    sa, sb = shades(base_a), shades(base_b)
    ys, xs = np.mgrid[0:h, 0:w]
    stripe = (xs // 8) % 2 == 0
    n = noise(w, h, (8.0, 2.0), seed)
    lvl = np.digitize(n, [0.28, 0.55, 0.84])            # 0..3
    # pliegues: cada 16 px de alto un poco más oscuro (la lona cuelga entre los listones)
    lvl = np.where(((ys % 32) >= 26), np.maximum(0, lvl - 1), lvl)
    # trama: un píxel más claro en damero suave cada 2
    weave = ((xs % 4 == 0) & (ys % 4 == 0)) | ((xs % 4 == 2) & (ys % 4 == 2))
    lvl = np.where(weave & (lvl < 2), lvl + 1, lvl)
    rgb = np.zeros((h, w, 3), np.uint8)
    for k in range(4):
        rgb[stripe & (lvl == k)] = sa[k]
        rgb[~stripe & (lvl == k)] = sb[k]
    return Image.fromarray(rgb, 'RGB')


WOOD = ['#3a2418', '#5a3a26', '#7a5234', '#946a44', '#ae8456', '#c8a070']


def tex_wood(w=64, h=64, seed=61):
    """Tablones horizontales gastados (bancos, estantes, cajones)."""
    n = noise(w, h, (0.8, 6.0), seed)
    idx = quant(n, WOOD[2:5], cuts=[0.38, 0.7]) + 2
    for y in range(0, h, 16):
        idx[y, :] = 0
        idx[(y + 1) % h, :] = 4
    rng = np.random.RandomState(seed + 1)
    for y0 in range(0, h, 16):
        for x in rng.choice(w, 2, replace=False):
            idx[y0 + 6:y0 + 9, x] = 1
            idx[y0 + 7, (x + 1) % w] = 1
        xj = rng.randint(0, w)
        idx[y0 + 1:y0 + 16, xj] = 0
    return to_img(idx, WOOD)


TEXTURES = {'sand': tex_sand, 'adobe': tex_adobe, 'metal_plate': tex_metal_plate, 'rusted_panel': tex_rusted_panel,
            'tile': tex_tile, 'canopy_fabric': tex_canopy,
            'canopy_fabric_teal': lambda: tex_canopy(seed=53, a='#3e8a86'), 'wood': tex_wood}


def build_tex(out):
    d = os.path.join(out, 'tex')
    os.makedirs(d, exist_ok=True)
    for name, fn in TEXTURES.items():
        fn().save(os.path.join(d, f'{name}.png'))


if __name__ == '__main__':
    args = sys.argv[1:]
    out = './out'
    if '--out' in args:
        k = args.index('--out')
        out = args[k + 1]
        del args[k:k + 2]
    what = args or ['tex', 'props', 'sky']
    if 'tex' in what:
        build_tex(out)
    if 'props' in what and 'build_props' in globals():
        build_props(out)
    print('ok world', what)
