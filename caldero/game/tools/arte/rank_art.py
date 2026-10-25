"""--- R4 RANK: el arte del Escalafón del Gremio de Boticarios de Arvendal.

Escudos de las 30 tiendas (rank_crest_<id>.png) y el del Gremio, el caldero de oro (el trofeo del final), la cabecera
de la Gaceta del Gremio, el tablón del Gremio (madera oscura y una tablilla tallada), el papel de periódico, las
flechas de subir y bajar, medallas, el subrayado amarillo de su fila, confeti y el botón del HUD.

Uso (desde una carpeta de trabajo FUERA del proyecto; escribe ./salida/ui/rank_*.png, copiar a assets/ui/):
    python3 /ruta/al/juego/tools/arte/rank_art.py
Necesita pillow y numpy. Pixel art a 1x (Godot lo escala con PaperKit.pic / UIKit.icon), salvo los nine-patch, que
se guardan a x2 como los de papel (rank_newsprint9, rank_board9, rank_mark9; márgenes en scripts/ui/rank_ui.gd).
Paleta de la guía de estilo de la ronda 3: tinta #3A2618, lacre #9E2B25, latón #C9A15A, hierba #4E6B3A, noche #3B2F52.
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from pixlib import hexrgb, shift, preview

OUT = './salida/ui'
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
FONT_SC = os.path.join(HERE, '../../assets/fonts/AlegreyaSC-Bold.ttf')

INK = '#3A2618'
INK_DARK = '#1c1424'
BRASS = ['#4a3418', '#7a5a2a', '#a8823f', '#c9a15a', '#e3c27e', '#f8e6b0']
GOLD = ['#3a2408', '#6e4612', '#a06a1c', '#d09a2e', '#eec456', '#fde79a', '#fffbe6']
WAL = ['#1f120a', '#33200f', '#4a2f1a', '#5a3a22', '#74502f', '#916a40', '#b08552']
MAHOG = ['#1a0d08', '#2e160d', '#432015', '#562a1a', '#6e3a24', '#8a4c30', '#a8623e']
NEWS = ['#FBF8EE', '#F1ECDC', '#E4DCC6', '#D2C7AB', '#BCAF90', '#9E9174', '#7A6E58']   # papel de periódico


def rgb(c):
    return np.array(hexrgb(c) if isinstance(c, str) else c[:3], dtype=np.float64)


def canvas(w, h):
    return np.zeros((h, w, 4), np.uint8)


def put(img, x, y, c, a=255):
    h, w = img.shape[:2]
    if 0 <= x < w and 0 <= y < h:
        img[y, x] = (*[int(v) for v in rgb(c)], a)


def save(img, name, k=1):
    a = np.asarray(img, np.uint8)
    if k > 1:
        a = a.repeat(k, 0).repeat(k, 1)
    Image.fromarray(a, 'RGBA').save(f'{OUT}/{name}')
    return img


def outline(img, c, diag=False):
    a = img[..., 3] > 0
    nb = np.zeros_like(a)
    nb[1:, :] |= a[:-1, :]
    nb[:-1, :] |= a[1:, :]
    nb[:, 1:] |= a[:, :-1]
    nb[:, :-1] |= a[:, 1:]
    if diag:
        nb[1:, 1:] |= a[:-1, :-1]
        nb[1:, :-1] |= a[:-1, 1:]
        nb[:-1, 1:] |= a[1:, :-1]
        nb[:-1, :-1] |= a[1:, 1:]
    m = nb & ~a
    img[m] = (*[int(v) for v in rgb(c)], 255)
    return img


def stamp(img, art, ox, oy, codes):
    rows = [r for r in art.strip('\n').split('\n')]
    for y, r in enumerate(rows):
        for x, ch in enumerate(r.strip() if False else r):
            if ch in codes:
                put(img, ox + x, oy + y, codes[ch])


# ------------------------------------------------------------------ escudos (16 de ancho + contorno)

SHIELD = """
................
................
................
................
................
................
................
................
................
................
.ffffffffffffff.
.ffffffffffffff.
..ffffffffffff..
..ffffffffffff..
...ffffffffff...
....ffffffff....
.....ffffff.....
.......ff.......
"""
SHIELD = SHIELD.replace('.', 'f', 16 * 10) if False else SHIELD


def shield_mask(w=16, h=18):
    m = np.zeros((h, w), bool)
    for y in range(h):
        if y < 10:
            m[y, :] = True
        else:
            k = [1, 1, 2, 2, 3, 4, 5, 7][y - 10]
            m[y, k:w - k] = True
    return m


# Figuras de los escudos (9x9): X color de la figura, h luz, d sombra, a acento.
CHARGES = {
    'alembic': """
...XXX...
....X....
....XXXXX
....X...X
...XXX..X
..XXXXX..
.XXhXXXX.
.XXXXXXX.
..XXXXX..
""",
    'book': """
.........
.XXXXXXX.
.XhhXhhX.
.XhhXhhX.
.XhhXhhX.
.XhhXhhX.
.XXXXXXX.
....X....
.........
""",
    'bell': """
....X....
...XXX...
..XXhXX..
..XhXXX..
..XhXXX..
.XXXXXXX.
XXXXXXXXX
....d....
.........
""",
    'rose': """
...XXX...
..XXhXX..
.XXhXXXX.
.XhXXdXX.
..XXXXX..
...aXa...
....a....
...aa....
....a....
""",
    'flask': """
...XXX...
....X....
....X....
...XXX...
..XXXXX..
.XXhXXXX.
.XhXXXXX.
.XXXXXXX.
..XXXXX..
""",
    'hammer': """
.XXXXXXX.
.XhhhhhX.
.XXXXXXX.
....d....
....d....
....d....
....d....
....d....
...ddd...
""",
    'willow': """
...XXX...
.XXXXXXX.
XXhXXXXXX
XhXXXXXXX
X.XXXXX.X
X.X.d.X.X
..X.d.X..
....d....
...ddd...
""",
    'roundflask': """
....X....
....X....
...XXX...
..XXXXX..
.XXhXXXX.
.XhXXXXX.
.XXXXXXX.
..XXXXX..
...XXX...
""",
    'anchor': """
....X....
...X.X...
....X....
..XXXXX..
....X....
....X....
X...X...X
.X..X..X.
..XXXXX..
""",
    'owl': """
.X.....X.
.XXXXXXX.
XXhXXXhXX
XhdhXhdhX
XXhXXXhXX
.XXXaXXX.
.XXXXXXX.
..XXXXX..
..a...a..
""",
    'mountain': """
.........
....X....
...XhX...
..XhXXX..
..XXXXX..
.XXXXXXX.
.XXXXXXXX
XXXXXXXXX
.........
""",
    'key': """
..XXX....
.X...X...
.X...X...
..XXX....
...X.....
...X.....
...XX....
...X.....
...XX....
""",
    'mandrake': """
..a.a.a..
...aaa...
....a....
..XXXXX..
.XXdXdXX.
.XXXXXXX.
..XXXXX..
.X.X.X.X.
X..X.X..X
""",
    'moon': """
...XXX...
..XX.....
.XX......
.XX......
.XX......
.XX......
..XX...X.
...XXXXX.
.........
""",
    'sun': """
....X....
.X..X..X.
..XXXXX..
..XhXXX..
XXXXXXXXX
..XXXXX..
..XXXXX..
.X..X..X.
....X....
""",
    'drop': """
....X....
....X....
...XXX...
..XXXXX..
..XhXXX..
.XhXXXXX.
.XXXXXXX.
..XXXXX..
...XXX...
""",
    'mushroom': """
...XXX...
.XXhXXXX.
XXXXXhXXX
XhXXXXXXX
XXXXXXXXX
...aaa...
...aaa...
...aaa...
..aaaaa..
""",
    'spark': """
....X....
.X..X..X.
..X.X.X..
...XhX...
XXXhhhXXX
...XhX...
..X.X.X..
.X..X..X.
....X....
""",
    'note': """
.....XX..
.....XXX.
.....X.XX
.....X...
.....X...
..XXXX...
.XXXXX...
.XXXX....
..XX.....
""",
    'retort': """
.........
......XX.
.....X..X
..XXX...X
.XXXXX..X
XXhXXXX..
XXXXXXX..
.XXXXX...
..XXX....
""",
    'leaf': """
.......XX
.....XXXX
....XXhXX
...XXhXX.
..XXhXX..
..XhXX...
..hXX....
.d.......
d........
""",
    'acorn': """
...aaa...
..aaaaa..
.aaaaaaa.
.adadada.
..XXXXX..
..XhXXX..
..XXXXX..
...XXX...
....X....
""",
    'wheat': """
....X....
...X.X...
....X....
...X.X...
....X....
...X.X...
....X....
....d....
....d....
""",
    'crooked': """
.....XX..
....X....
....X....
...XX....
..XXXX...
.XXXXXX..
.XhXXXXX.
..XXXXXX.
...XXXX..
""",
    'moonstar': """
..XX...h.
.XX...hhh
XX.....h.
XX.......
XX.......
XX.......
.XX....X.
..XXXXX..
.........
""",
    'button': """
...XXX...
.XXXXXXX.
.XXXXXXX.
XXXdXdXXX
XXXXXXXXX
XXXdXdXXX
.XXXXXXX.
.XXXXXXX.
...XXX...
""",
    'needle': """
..aaa..XX
.a...aX.X
.a...X.XX
..a.X....
...X.....
..X.a....
.X..a....
X...a....
.........
""",
    'cauldronmoon': """
.....mm..
......mm.
......mm.
.....mm..
X.......X
XXXXXXXXX
XhXXXXXXX
.XXXXXXX.
..X...X..
""",
}

# id de la tienda: (campo, figura, color de la figura, acento, partición)
# partición: '' liso, 'pale' (mitad derecha más oscura), 'chief' (franja arriba), 'bend' (banda), 'bordure' (borde de
# segundo color)
CRESTS = {
    'alambique': ('#C9A15A', 'alembic', '#3A2618', '#7a1d18', 'bordure'),
    'academia': ('#3E5A9A', 'book', '#3A2618', '#F2E6C6', 'chief'),
    'monasterio': ('#E8DDC0', 'bell', '#B0822E', '#5A3A22', ''),
    'rosalba': ('#B8507A', 'rose', '#F4D8DC', '#4E8B4A', 'pale'),
    'milfrascos': ('#2E7A7A', 'flask', '#E3C27E', '#F8E6B0', 'bend'),
    'martillo': ('#5A5A68', 'hammer', '#E3C27E', '#7A5A2A', 'chief'),
    'sauce': ('#3E6B3A', 'willow', '#D8DDE6', '#7A6A5A', ''),
    'redoma': ('#2F4F8A', 'roundflask', '#9FD6F0', '#F2F8FF', 'pale'),
    'puerto': ('#2A3A5A', 'anchor', '#EADBB8', '#C9A15A', 'bordure'),
    'lechuza': ('#4A3424', 'owl', '#E8D8B0', '#C9A15A', ''),
    'piedrahierro': ('#4A4E5A', 'mountain', '#9AA0AE', '#F4F6FA', 'chief'),
    'caminoreal': ('#9E2B25', 'key', '#E3C27E', '#F8E6B0', ''),
    'mandragora': ('#4E8B4A', 'mandrake', '#C9A06B', '#69B84A', 'pale'),
    'paramo': ('#5A4E6E', 'moon', '#E8E0C0', '#E8E0C0', 'bend'),
    'plazamayor': ('#7A2A3A', 'sun', '#E8B848', '#FFF0B0', ''),
    'gruka': ('#5A6A2A', 'drop', '#9EE07A', '#E0FFD0', 'chief'),
    'tiobolo': ('#A8823F', 'mushroom', '#C0392B', '#EADBB8', 'pale'),
    'fizz': ('#C8743A', 'spark', '#FFE27A', '#FFFBE6', 'bend'),
    'raicesrocio': ('#5A6B3A', 'drop', '#8FD0F0', '#E0F6FF', ''),
    'cantor': ('#6A4E9A', 'note', '#E3C27E', '#F8E6B0', 'bordure'),
    'retorta': ('#A0532D', 'retort', '#F2E6C6', '#FFFFFF', ''),
    'vado': ('#4E7A4A', 'leaf', '#C8E6A0', '#5A3A22', 'pale'),
    'encina': ('#6B472A', 'acorn', '#C9A15A', '#4E6B3A', ''),
    'molino': ('#5A8AB8', 'wheat', '#F2D27A', '#A8823F', 'chief'),
    'torcido': ('#4A5A4A', 'crooked', '#D8E8D0', '#FFFFFF', 'bend'),
    'lunaticos': ('#2A2A4A', 'moonstar', '#F2DE9A', '#FFF6C8', ''),
    'ortiz': ('#B87A8A', 'button', '#F4E4D0', '#7A4A5A', 'bordure'),
    'gotadorada': ('#C8943A', 'drop', '#FFE08A', '#FFFBE0', 'pale'),
    'remiendos': ('#5A6A8A', 'needle', '#D8DDE6', '#C0392B', ''),
    'caldero': ('#3B2F52', 'cauldronmoon', '#D8A84A', '#9B74E8', 'bordure'),
}


def crest(field, charge, ccol, acc, part):
    """Un escudo de 16x18 con borde de latón y contorno, en un lienzo de 18x20."""
    W, H = 16, 18
    img = canvas(W + 2, H + 2)
    m = shield_mask(W, H)
    f = rgb(field)
    dark = rgb(shift(hexrgb(field), -0.16, 0.04))
    light = rgb(shift(hexrgb(field), 0.10, -0.06))
    yy, xx = np.mgrid[0:H, 0:W]
    col = np.zeros((H, W, 3))
    col[:] = f
    # luz de arriba a la izquierda (dos tonos, sin degradado)
    col[(xx + yy * 0.8) < 7] = light
    col[(xx + yy * 0.6) > 19] = dark
    sec = rgb(acc)
    if part == 'pale':
        col[xx >= W // 2] = rgb(shift(hexrgb(field), -0.10, 0.02))
    elif part == 'chief':
        col[yy < 4] = rgb(shift(hexrgb(field), -0.18, 0.04))
    elif part == 'bend':
        band = np.abs((xx - yy) - 0) <= 1
        col[band] = rgb(shift(hexrgb(field), 0.14, -0.10))
    inner = m.copy()
    for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        sh = np.zeros_like(m)
        sh[max(0, dy):H + min(0, dy), max(0, dx):W + min(0, dx)] = m[max(0, -dy):H - max(0, dy), max(0, -dx):W - max(0, dx)]
        inner &= sh
    rim = m & ~inner
    if part == 'bordure':
        inner2 = inner.copy()
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.zeros_like(inner)
            sh[max(0, dy):H + min(0, dy), max(0, dx):W + min(0, dx)] = inner[max(0, -dy):H - max(0, dy), max(0, -dx):W - max(0, dx)]
            inner2 &= sh
        col[inner & ~inner2] = sec
    # borde de latón: claro arriba a la izquierda, oscuro abajo a la derecha
    for y in range(H):
        for x in range(W):
            if rim[y, x]:
                c = BRASS[4] if (x < W / 2 and y < 10) or y == 0 else (BRASS[2] if y > 12 or x > W / 2 + 4 else BRASS[3])
                col[y, x] = rgb(c)
    img[1:H + 1, 1:W + 1, :3] = np.where(m[..., None], col, 0).astype(np.uint8)
    img[1:H + 1, 1:W + 1, 3] = np.where(m, 255, 0)
    # la figura, centrada un poco arriba
    hl = rgb(shift(hexrgb(ccol), 0.22, -0.18))
    dk = rgb(shift(hexrgb(ccol), -0.30, 0.06))
    codes = {'X': ccol, 'h': tuple(int(v) for v in hl), 'd': tuple(int(v) for v in dk), 'a': acc, 'm': '#F2DE9A'}
    stamp(img, CHARGES[charge], 1 + 3 + (1 if charge in ('leaf', 'needle') else 0) - (1 if charge == 'leaf' else 0), 1 + 3, codes)
    outline(img, INK_DARK)
    return img


def gremio_crest():
    """El escudo del Gremio de Boticarios de Arvendal: un caldero de oro bajo una corona, en campo verde, con laureles."""
    W, H = 30, 30
    img = canvas(W, H)
    m = shield_mask(16, 18)
    big = np.kron(m, np.ones((1, 1), bool))
    # escudo 20x22 hecho a mano (más grande que los de las tiendas)
    sw, sh = 20, 22
    sm = np.zeros((sh, sw), bool)
    for y in range(sh):
        if y < 12:
            sm[y, :] = True
        else:
            k = [1, 1, 2, 2, 3, 4, 5, 6, 7, 8][y - 12]
            sm[y, k:sw - k] = True
    ox, oy = 5, 4
    field = rgb('#2E4A3A')
    light = rgb('#3E6450')
    for y in range(sh):
        for x in range(sw):
            if sm[y, x]:
                edge = not (0 < x < sw - 1 and 0 < y and sm[min(sh - 1, y + 1), x] and sm[y, x - 1] and sm[y, x + 1] and sm[y - 1, x])
                if edge:
                    c = rgb(BRASS[4] if (x < sw / 2 and y < 12) or y == 0 else BRASS[2])
                elif x + y * 0.8 < 9:
                    c = light
                else:
                    c = field
                img[oy + y, ox + x] = (*c.astype(int), 255)
    # corona
    crown = """
.X.X.X.
.XXXXX.
.XhXhX.
"""
    stamp(img, crown, ox + 6, oy + 2, {'X': GOLD[4], 'h': '#C0392B'})
    # caldero de oro
    caul = """
X.........X
XXXXXXXXXXX
XhhhhhhhhhX
.XhXXXXXXX.
.XXXXXXXXX.
..XXXXXXX..
..X.....X..
"""
    stamp(img, caul, ox + 4, oy + 7, {'X': GOLD[3], 'h': GOLD[5]})
    # estrellita
    put(img, ox + 10, oy + 16, GOLD[5])
    put(img, ox + 9, oy + 17, GOLD[4])
    put(img, ox + 11, oy + 17, GOLD[4])
    put(img, ox + 10, oy + 18, GOLD[4])
    outline(img, INK_DARK)
    # ramas de laurel doradas: un arco a cada lado, de abajo hacia arriba, con hojas en pares
    stem = GOLD[2]
    for side in (-1, 1):
        last = None
        for i in range(48):
            t = i / 47.0
            ang = math.radians(255 - 120 * t)
            x = 15 - math.cos(ang) * 13.5 if side < 0 else 14 + math.cos(ang) * 13.5
            y = 15.5 - math.sin(ang) * 12.5
            xi, yi = int(round(x)), int(round(y))
            if (xi, yi) == last:
                continue
            last = (xi, yi)
            if img[yi, xi, 3] == 0:
                put(img, xi, yi, stem)
            if i % 7 == 3 and i < 44:
                ox = -1 if side < 0 else 1
                for (dx, dy, c) in ((ox, -1, GOLD[4]), (ox * 2, -2, GOLD[5]), (-ox, -1, GOLD[4]), (-ox * 2, -2, GOLD[3])):
                    if 0 <= yi + dy < H and 0 <= xi + dx < W and img[yi + dy, xi + dx, 3] == 0:
                        put(img, xi + dx, yi + dy, c)
    return img


# ------------------------------------------------------------------ el caldero de oro (trofeo del final)

def trophy():
    W, H = 44, 42
    img = canvas(W, H)
    cx, cy = 22.0, 24.0
    rx, ry = 15.0, 11.5
    L = np.array([-0.55, -0.65, 0.52])
    L /= np.linalg.norm(L)
    for y in range(H):
        for x in range(W):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0 and y >= 15:
                nz = math.sqrt(max(0.0, 1 - dx * dx - dy * dy))
                n = np.array([dx, dy, nz])
                lam = float(np.dot(n, L))
                spec = max(0.0, lam) ** 14
                v = 1.6 + lam * 2.4 + spec * 2.0
                # banda de laurel en relieve (más oscura) a media altura
                if abs(y - 26) <= 0 and abs(dx) < 0.92:
                    v -= 1.1
                idx = int(round(min(6, max(0, v))))
                img[y, x] = (*rgb(GOLD[idx]).astype(int), 255)
    # boca: borde (anillo) y el hueco oscuro
    for y in range(11, 18):
        for x in range(W):
            dx, dy = (x + 0.5 - cx) / (rx + 1.5), (y + 0.5 - 15.0) / 3.2
            d = dx * dx + dy * dy
            if d <= 1.0:
                inner = ((x + 0.5 - cx) / (rx - 1.5)) ** 2 + ((y + 0.5 - 15.2) / 2.0) ** 2 <= 1.0
                if inner:
                    img[y, x] = (*rgb('#3a2408').astype(int), 255)
                    if y <= 14:
                        img[y, x] = (*rgb('#5a3a12').astype(int), 255)
                else:
                    lit = x < cx and y < 15.5
                    img[y, x] = (*rgb(GOLD[5] if lit else (GOLD[4] if y < 16 else GOLD[3])).astype(int), 255)
    # brillo dentro de la boca (destello mágico)
    for (x, y) in ((19, 15), (20, 15), (24, 14), (27, 15)):
        img[y, x] = (*rgb('#fff6c8').astype(int), 255)
    # asas
    for side in (-1, 1):
        hx = int(cx + side * (rx + 1.0))
        for (dx, dy) in ((0, 0), (side, 0), (side * 2, 1), (side * 2, 2), (side * 2, 3), (side, 4), (0, 4)):
            img[18 + dy, hx + dx] = (*rgb(GOLD[4] if dy < 2 else GOLD[3]).astype(int), 255)
    # patas
    for lx in (12, 21, 30):
        for dy in range(3):
            img[34 + dy, lx:lx + 3] = (*rgb(GOLD[2] if dy else GOLD[3]).astype(int), 255)
    # peana de nogal con placa de latón
    for y in range(37, 42):
        for x in range(6, 38):
            c = WAL[4] if y == 37 else (WAL[3] if y < 40 else WAL[2])
            img[y, x] = (*rgb(c).astype(int), 255)
    for x in range(15, 29):
        for y in range(38, 41):
            img[y, x] = (*rgb(BRASS[4] if y == 38 else BRASS[3]).astype(int), 255)
    # el «1» grabado en la placa
    for (x, y) in ((22, 38), (22, 39), (22, 40), (21, 38)):
        img[y, x] = (*rgb(BRASS[1]).astype(int), 255)
    outline(img, INK_DARK)
    # destellos
    for (sx, sy) in ((6, 9), (37, 6), (40, 22)):
        for (dx, dy, c) in ((0, 0, '#ffffff'), (1, 0, '#fff2c0'), (-1, 0, '#fff2c0'), (0, 1, '#fff2c0'), (0, -1, '#fff2c0')):
            put(img, sx + dx, sy + dy, c)
    return img


# ------------------------------------------------------------------ la cabecera de la Gaceta

def masthead():
    """«The Guild Gazette» en versalitas de pixel (Alegreya SC sin suavizado), filetes dobles y dos escuditos.
    --- R5 EN-UI: el título en inglés (antes «La Gaceta del Gremio»)."""
    title = 'The Guild Gazette'
    font = ImageFont.truetype(FONT_SC, 30)
    tmp = Image.new('L', (600, 80), 0)
    d = ImageDraw.Draw(tmp)
    d.fontmode = '1'
    d.text((10, 10), title, font=font, fill=255)
    a = np.array(tmp) > 127
    ys, xs = np.nonzero(a)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    th, tw = a.shape
    W = tw + 2 * 30
    H = th + 18
    img = canvas(W, H)
    ox, oy = 30, 8
    ink = rgb('#2a1d14')
    for y in range(th):
        for x in range(tw):
            if a[y, x]:
                img[oy + y, ox + x] = (*ink.astype(int), 255)
    # filetes: grueso + fino arriba y abajo
    for x in range(2, W - 2):
        img[1, x] = (*ink.astype(int), 255)
        img[2, x] = (*ink.astype(int), 255)
        img[4, x] = (*ink.astype(int), 255)
        img[H - 5, x] = (*ink.astype(int), 255)
        img[H - 3, x] = (*ink.astype(int), 255)
        img[H - 2, x] = (*ink.astype(int), 255)
    # rombos en las puntas de los filetes
    for (x, y) in ((1, 3), (W - 2, 3), (1, H - 4), (W - 2, H - 4)):
        for (dx, dy) in ((0, -1), (-1, 0), (0, 0), (1, 0), (0, 1)):
            put(img, x + dx, y + dy, '#2a1d14')
    # escuditos del Gremio (pequeños, a tinta) a los lados del título
    sm = shield_mask(12, 14) if False else None
    for side in (0, 1):
        sx = 8 if side == 0 else W - 8 - 14
        sy = (H - 16) // 2
        for y in range(15):
            for x in range(14):
                inside = (y < 8) or (abs(x - 6.5) < 7 - (y - 7) * 0.9)
                if inside:
                    edge = y == 0 or x == 0 or x == 13 or not ((y + 1 < 8) or (abs(x - 6.5) < 7 - (y - 6) * 0.9))
                    put(img, sx + x, sy + y, '#2a1d14' if edge else '#e4dcc6')
        # caldero dentro
        stamp(img, """
X......X
XXXXXXXX
.XXXXXX.
..XXXX..
..X..X..
""", sx + 3, sy + 4, {'X': '#2a1d14'})
    return img


# ------------------------------------------------------------------ papeles y madera (nine-patch a x2)

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def _wrap_blur(a, r, n=2):
    for _ in range(n):
        a = sum(np.roll(a, d, axis=1) for d in range(-r, r + 1)) / (2 * r + 1)
        a = sum(np.roll(a, d, axis=0) for d in range(-r, r + 1)) / (2 * r + 1)
    return a


def _tile_noise(w, h, r, rng, n=3):
    a = _wrap_blur(rng.random((h, w)), r, n)
    a -= a.min()
    return a / max(1e-6, a.max())


def _noise1(n, r, rng, passes=3):
    a = rng.random(n)
    for _ in range(passes):
        a = sum(np.roll(a, d) for d in range(-r, r + 1)) / (2 * r + 1)
    a -= a.min()
    return a / max(1e-6, a.max())


def _quantize(v, ramp, dither=1.0):
    h, w = v.shape
    b = np.tile(BAYER4, (h // 4 + 2, w // 4 + 2))[:h, :w]
    idx = np.clip(np.floor(v + (b - 0.5) * dither), 0, len(ramp) - 1).astype(int)
    pal = np.array([rgb(c) for c in ramp])
    return pal[idx]


def newsprint9(seed=41, M=12, C=128):
    """Papel de periódico: más gris y liso que el pergamino, con el filo cortado (casi recto) y algo de tinta corrida."""
    rng = np.random.default_rng(seed)
    S = 2 * M + C
    low = _tile_noise(C, C, 10, rng)
    mid = _tile_noise(C, C, 1, rng, 2)
    base = 1.0 + (low - 0.5) * 0.7 + (mid - 0.5) * 0.45
    v = np.roll(np.tile(base, (3, 3))[:S, :S], (M % C, M % C), axis=(0, 1))
    yy, xx = np.mgrid[0:S, 0:S].astype(float)

    def edge():
        seg = _noise1(C, 2, rng) * 1.0
        full = np.zeros(S)
        for x in range(S):
            full[x] = seg[(x - M) % C]
        return full
    dt, db, dl, dr = edge(), edge(), edge(), edge()
    m = 3
    dist = np.minimum.reduce([xx - m - dl[yy.astype(int)], (S - 1 - m) - xx - dr[yy.astype(int)],
                              yy - m - dt[xx.astype(int)], (S - 1 - m) - yy - db[xx.astype(int)]])
    v += np.where(dist < 1.0, 2.2, 0.0) + np.where((dist >= 1) & (dist < 4), (4 - dist) / 3.0 * 0.8, 0.0)
    col = _quantize(v, NEWS, 1.0)
    out = np.dstack([col, np.where(dist >= 0, 255, 0)]).astype(np.uint8)
    # sombra dura debajo
    h, w = out.shape[:2]
    msk = out[..., 3] > 0
    sh = np.zeros((h, w), bool)
    sh[2:, 1:] = msk[:h - 2, :w - 1]
    out[sh & ~msk] = [32, 20, 12, 80]
    return out


def board9(seed=5, M=12, C=40):
    """El tablón del Gremio: caoba oscura con un marco tallado (ranura) y remaches de latón en las esquinas."""
    rng = np.random.default_rng(seed)
    S = 2 * M + C
    yy, xx = np.mgrid[0:S, 0:S]
    v = np.full((S, S), 3.0)
    # vetas verticales (tablas)
    xs = (xx - M) % C
    plank = xs // 10
    inx = xs % 10
    ph = rng.random(8) * 6.28
    for p in range(4):
        sel = plank == p
        ys = (yy - M) % C
        grain = np.sin(ys * 6.28 / C * (1 + p % 2) + ph[p])
        v = np.where(sel & (np.abs(inx - 5 - grain * 2.0) < 0.6), v - 0.8, v)
    v = np.where(inx == 0, 1.2, v)
    n = _tile_noise(C, C, 1, rng, 1)
    v += (np.roll(np.tile(n, (3, 3))[:S, :S], (M % C, M % C), axis=(0, 1)) - 0.5) * 0.8
    d = np.minimum.reduce([xx, yy, S - 1 - xx, S - 1 - yy])
    v = np.where(d == 0, 0.3, v)
    v = np.where((d >= 1) & (d <= 3) & ((xx <= 3) | (yy <= 3)) & (xx < S - 4) & (yy < S - 4), 5.3, v)
    v = np.where((d >= 1) & (d <= 3) & ((xx >= S - 4) | (yy >= S - 4)), 2.0, v)
    v = np.where((d >= 4) & (d <= 5), 3.6, v)
    v = np.where(d == 7, 1.0, v)          # la ranura tallada
    v = np.where(d == 8, 4.6, v)
    col = _quantize(v, MAHOG, 0.7)
    out = np.dstack([col, np.full((S, S), 255)]).astype(np.uint8)
    for (cx, cy) in ((5, 5), (S - 6, 5), (5, S - 6), (S - 6, S - 6)):
        for (dx, dy, c) in ((0, 0, BRASS[3]), (-1, 0, BRASS[2]), (0, -1, BRASS[4]), (1, 0, BRASS[2]), (0, 1, BRASS[1]), (-1, -1, BRASS[5])):
            out[cy + dy, cx + dx] = (*rgb(c).astype(int), 255)
    return out


def mark9():
    """El subrayado amarillo de su fila: un trazo de marcador con los extremos irregulares (se estira a lo ancho)."""
    W, H = 32, 14
    rng = np.random.default_rng(3)
    img = canvas(W, H)
    for x in range(W):
        top = 1 + int(rng.integers(0, 2))
        bot = H - 2 - int(rng.integers(0, 2))
        if x < 3:
            top += 3 - x
            bot -= 3 - x
        if x > W - 4:
            top += x - (W - 4)
            bot -= x - (W - 4)
        for y in range(top, bot + 1):
            a = 150 if 1 < y < H - 2 else 110
            img[y, x] = (255, 226, 110, a)
    return img


def plaque():
    """La tablilla tallada de arriba del tablón (el texto lo escribe Godot encima): caoba, clavos de latón, laureles."""
    W, H = 190, 26
    img = canvas(W, H)
    rng = np.random.default_rng(9)
    for y in range(H):
        for x in range(W):
            # extremos en punta (tipo banderola)
            notch = abs(y - H / 2) < (x * 1.2) and abs(y - H / 2) < ((W - 1 - x) * 1.2)
            if not notch:
                continue
            v = 3.2
            if y <= 2:
                v = 5.2
            elif y >= H - 3:
                v = 1.8
            v += math.sin(x * 0.21 + y * 0.9) * 0.35 + (rng.random() - 0.5) * 0.5
            if (y - 7) % 9 == 0 and 8 < x < W - 8:
                v -= 0.7
            idx = int(round(min(6, max(0, v))))
            img[y, x] = (*rgb(MAHOG[idx]).astype(int), 255)
    # ranura interior
    for x in range(10, W - 10):
        put(img, x, 4, MAHOG[1])
        put(img, x, H - 5, MAHOG[5])
    # clavos
    for nx in (8, W - 9):
        for (dx, dy, c) in ((0, 0, BRASS[3]), (1, 0, BRASS[2]), (0, 1, BRASS[1]), (1, 1, BRASS[2]), (0, -1, BRASS[5])):
            put(img, nx + dx, H // 2 + dy, c)
    # ramitas de laurel doradas junto a los clavos
    for side in (0, 1):
        for i in range(4):
            x = (14 + i * 4) if side == 0 else (W - 15 - i * 4)
            put(img, x, 9 + (i % 2), GOLD[4])
            put(img, x + (1 if side == 0 else -1), 8 + (i % 2), GOLD[5])
            put(img, x, 16 - (i % 2), GOLD[3])
            put(img, x + (1 if side == 0 else -1), 17 - (i % 2), GOLD[4])
        for i in range(15):
            x = (13 + i) if side == 0 else (W - 14 - i)
            put(img, x, 13, GOLD[2])
    outline(img, INK_DARK)
    return img


# ------------------------------------------------------------------ iconos pequeños

def arrows():
    up = """
...X...
..XXX..
.XXXXX.
XXXXXXX
..XXX..
..XXX..
"""
    down = """
..XXX..
..XXX..
XXXXXXX
.XXXXX.
..XXX..
...X...
"""
    same = """
.......
.......
XXXXXXX
XXXXXXX
.......
.......
"""
    out = {}
    for name, art, c in (('up', up, '#3E7A2E'), ('down', down, '#A3261F'), ('same', same, '#8A7A62')):
        img = canvas(7, 6)
        stamp(img, art, 0, 0, {'X': c})
        out[name] = img
    return out


def medal(c0, c1, c2):
    img = canvas(12, 17)
    ribbon = """
.RR....BB...
.RRR..BBB...
..RRRBBB....
...RRBB.....
....RB......
"""
    stamp(img, ribbon, 0, 0, {'R': '#A3261F', 'B': '#3E5A9A'})
    disc = """
...OOOO...
..OhhccO..
.OhhcccdO.
.OhccccdO.
.OcccccdO.
.OccccddO.
..OcddddO.
...OOOO...
"""
    stamp(img, disc, 1, 6, {'O': c2, 'h': '#ffffff', 'c': c0, 'd': c1})
    outline(img, INK_DARK)
    return img


def hud_icon():
    """El botón del Escalafón en el HUD (16x16, estilo de los iconos de UI-BENCH): una copita de oro con laureles."""
    art = """
................
..O..........O..
.OGO.OOOOOO.OGO.
.OgOOykkkkyOOgO.
OGgOkyyKKKkKOgGO
OgOOKkKKKKKKOOgO
.OGOOKKKKKKOOGO.
..OgOOKKKKOOgO..
...OOOOKKOOOO...
.......KK.......
......OKKO......
.....OkKKKO.....
....OkkKKKKO....
....OOOOOOOO....
................
................
"""
    img = canvas(16, 16)
    stamp(img, art, 0, 0, {'O': '#1c1424', 'K': GOLD[3], 'k': GOLD[4], 'y': GOLD[5], 'G': '#7AA84A', 'g': '#4E7A2E'})
    return img


def confetti():
    img = canvas(3, 4)
    for y in range(4):
        for x in range(3):
            img[y, x] = (255, 255, 255, 255) if x < 2 else (205, 205, 205, 255)
    return img


def lantern_glow():
    """Un farolillo de papel rojo colgado de su cordel (las guirnaldas de la fiesta del final)."""
    art = """
....S....
....S....
....S....
...OOO...
..OKKKO..
.ORrRrRO.
ORrYYYrRO
ORYyWyYRO
ORYyyyYRO
ORrYYYrRO
.ORrRrRO.
..OKKKO..
...OOO...
....T....
...TTT...
...T.T...
"""
    img = canvas(9, 16)
    stamp(img, art, 0, 0, {'S': '#6A5A4A', 'O': '#4a140f', 'K': '#2a1a10', 'R': '#C8443C', 'r': '#A8322A',
                           'Y': '#F08A4A', 'y': '#FFC27A', 'W': '#FFF2C0', 'T': '#E8C04A'})
    return img


def rank_all():
    made = []

    def keep(arr, name, k=1):
        save(arr, name, k)
        made.append((name, np.asarray(arr)))
    for sid, (field, charge, ccol, acc, part) in CRESTS.items():
        keep(crest(field, charge, ccol, acc, part), 'rank_crest_%s.png' % sid)
    keep(gremio_crest(), 'rank_crest_gremio.png')
    keep(trophy(), 'rank_trophy.png')
    keep(masthead(), 'rank_masthead.png')
    keep(newsprint9(), 'rank_newsprint9.png', 2)
    keep(board9(), 'rank_board9.png', 2)
    keep(mark9(), 'rank_mark9.png', 2)
    keep(plaque(), 'rank_plaque.png')
    for k, v in arrows().items():
        keep(v, 'rank_%s.png' % k)
    keep(medal(GOLD[4], GOLD[3], GOLD[1]), 'rank_medal_oro.png')
    keep(medal('#E8EAF0', '#A8ACB8', '#5A5E6A'), 'rank_medal_plata.png')
    keep(medal('#D89A5A', '#A86A3A', '#5A3418'), 'rank_medal_bronce.png')
    keep(hud_icon(), 'hud_rank.png')
    keep(confetti(), 'rank_confetti.png')
    keep(lantern_glow(), 'rank_lantern.png')
    small = [m for n, m in made if m.shape[0] <= 64 and m.shape[1] <= 64]
    preview(small, scale=5, cols=12, path='./prev_rank.png')
    print('rank:', len(made), 'imágenes ->', OUT)


if __name__ == '__main__':
    rank_all()
