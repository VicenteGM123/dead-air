"""Arte del lane WORLD de Caldero Nocturno: la biblioteca de la tienda y el mercado del pueblo.

Pixel art hecho por código (PIL sin suavizado + rampas de color de pixlib). Sale en ./salida/world/{props,tex}
y se copia a assets/props y assets/tex. Uso:  python3 world_art.py [carpeta_assets]
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from PIL import Image, ImageDraw
from pixlib import ramp, hexrgb, shift

OUT = './salida/world'
for d in ('props', 'tex'):
    os.makedirs(f'{OUT}/{d}', exist_ok=True)
R = random.Random(7)


# ------------------------------------------------------------------ lienzo

class Cv:
    """Lienzo RGBA sin suavizado. Colores como '#rrggbb' o tuplas."""
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def c(col, a=255):
        if isinstance(col, str):
            col = hexrgb(col)
        return tuple(col[:3]) + (a,)

    def px(self, x, y, col, a=255):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.im.putpixel((int(x), int(y)), self.c(col, a))

    def rect(self, x, y, w, h, col, a=255):
        if w <= 0 or h <= 0:
            return
        self.d.rectangle([x, y, x + w - 1, y + h - 1], fill=self.c(col, a))

    def line(self, x0, y0, x1, y1, col, a=255):
        self.d.line([x0, y0, x1, y1], fill=self.c(col, a))

    def ell(self, x, y, w, h, col, a=255):
        self.d.ellipse([x, y, x + w - 1, y + h - 1], fill=self.c(col, a))

    def poly(self, pts, col, a=255):
        self.d.polygon(pts, fill=self.c(col, a))

    def get(self, x, y):
        return self.im.getpixel((x, y))

    def outline(self, k=0.45, col=None):
        """Contorno 'sel-out': cada píxel vacío junto a uno lleno toma una versión oscura de su vecino."""
        a = np.array(self.im)
        h, w = a.shape[:2]
        out = a.copy()
        solid = a[:, :, 3] > 0
        for y in range(h):
            for x in range(w):
                if solid[y, x]:
                    continue
                for dx, dy in ((0, 1), (-1, 0), (1, 0), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and solid[ny, nx]:
                        if col is not None:
                            out[y, x, :3] = hexrgb(col)
                        else:
                            out[y, x, :3] = (a[ny, nx, :3] * k).astype(np.uint8)
                        out[y, x, 3] = 255
                        break
        self.im = Image.fromarray(out, 'RGBA')
        self.d = ImageDraw.Draw(self.im)
        return self

    def paste(self, other, x, y):
        self.im.alpha_composite(other.im if isinstance(other, Cv) else other, (int(x), int(y)))
        self.d = ImageDraw.Draw(self.im)

    def flip(self):
        self.im = self.im.transpose(Image.FLIP_LEFT_RIGHT)
        self.d = ImageDraw.Draw(self.im)
        return self

    def save(self, name, kind='props'):
        path = f'{OUT}/{kind}/{name}.png'
        self.im.save(path)
        return path


def rp(base):
    """Rampa de 5 tonos (0 = sombra profunda ... 4 = brillo)."""
    return ramp(base)


def dither_noise(cv, x, y, w, h, cols, density=0.12, rnd=R):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if rnd.random() < density and cv.get(xx, yy)[3] > 0:
                cv.px(xx, yy, rnd.choice(cols))


# ------------------------------------------------------------------ biblioteca

BOOK_COLS = ['#a8443c', '#3f6fa8', '#4f8a4a', '#c9a54a', '#7a4a8a', '#3a7a7a', '#d8c8a8', '#7a4f38', '#2f3f6a', '#b8603a',
             '#5a7a3a', '#8a2f4a']
GOLD = '#e8c060'


def book_spine(cv, x, y, w, h, col, rnd):
    r = rp(col)
    cv.rect(x, y, w, h, r[2])
    cv.rect(x, y, 1, h, r[3])
    cv.rect(x + w - 1, y, 1, h, r[1])
    cv.rect(x, y, w, 1, r[3])
    # bandas doradas o de cuero
    for _ in range(rnd.choice([0, 1, 2, 2])):
        by = y + rnd.randint(1, max(1, h - 3))
        cv.rect(x, by, w, 1, rnd.choice([GOLD, r[0], r[4]]))
    if w >= 4 and rnd.random() < 0.45:
        ly = y + h // 3
        cv.rect(x + 1, ly, w - 2, max(2, h // 6), '#efe2c4')


def fill_shelf(cv, x0, x1, ybot, hmax, rnd, deco=None):
    """Llena un hueco de estantería con libros, de izquierda a derecha."""
    x = x0
    while x < x1:
        room = x1 - x
        if room < 3:
            break
        roll = rnd.random()
        if deco and roll < 0.12:
            dw = deco(cv, x, ybot, hmax, rnd)
            x += dw + 1
            deco = None
            continue
        if roll < 0.2 and room > 10:
            # pila de libros tumbados
            n = rnd.randint(2, 4)
            sw = rnd.randint(7, min(11, room))
            yy = ybot
            for i in range(n):
                hh = rnd.randint(2, 3)
                c = rnd.choice(BOOK_COLS)
                r = rp(c)
                ww = sw - rnd.randint(0, 2)
                cv.rect(x, yy - hh, ww, hh, r[2])
                cv.rect(x, yy - hh, ww, 1, r[3])
                cv.rect(x + ww - 1, yy - hh, 1, hh, r[1])
                yy -= hh
            x += sw + 1
            continue
        if roll < 0.27:
            x += rnd.randint(2, 4)   # hueco
            continue
        w = rnd.randint(3, 6)
        w = min(w, room)
        h = int(hmax * rnd.uniform(0.62, 0.96))
        c = rnd.choice(BOOK_COLS)
        if roll > 0.93 and room > 8:
            # libro inclinado
            r = rp(c)
            for i in range(h):
                off = int(i * 0.35)
                cv.rect(x + off, ybot - 1 - i, w, 1, r[2] if i < h - 1 else r[3])
                cv.px(x + off + w - 1, ybot - 1 - i, r[1])
            x += w + int(h * 0.35) + 1
            continue
        book_spine(cv, x, ybot - h, w, h, c, rnd)
        x += w


def deco_plant(cv, x, ybot, hmax, rnd):
    cv.rect(x + 1, ybot - 4, 5, 4, '#b8603a')
    cv.rect(x + 1, ybot - 4, 5, 1, '#d8804a')
    g = rp('#4f9a4a')
    for (dx, dy) in [(0, -7), (2, -9), (4, -8), (6, -6), (1, -5), (5, -5), (3, -6), (3, -10)]:
        cv.rect(x + dx, ybot - 4 + dy + 2, 2, 2, g[rnd.randint(1, 3)])
    return 8


def deco_crystal(cv, x, ybot, hmax, rnd):
    c = rp('#9a7ae8')
    cv.poly([(x + 1, ybot - 1), (x + 3, ybot - 9), (x + 5, ybot - 1)], c[2])
    cv.poly([(x + 4, ybot - 1), (x + 6, ybot - 6), (x + 8, ybot - 1)], c[1])
    cv.line(x + 3, ybot - 8, x + 3, ybot - 3, c[4])
    return 9


def deco_hourglass(cv, x, ybot, hmax, rnd):
    cv.rect(x, ybot - 1, 7, 1, '#7a4f38')
    cv.rect(x, ybot - 10, 7, 1, '#7a4f38')
    cv.poly([(x + 1, ybot - 9), (x + 5, ybot - 9), (x + 3, ybot - 5)], '#cfe8f0')
    cv.poly([(x + 1, ybot - 2), (x + 5, ybot - 2), (x + 3, ybot - 6)], '#cfe8f0')
    cv.poly([(x + 2, ybot - 2), (x + 4, ybot - 2), (x + 3, ybot - 4)], '#e8c060')
    return 8


def bookshelf(w=56, h=120, shelves=5, seed=1, name='bookshelf'):
    rnd = random.Random(seed)
    cv = Cv(w, h)
    wd = rp('#6e4630')
    # fondo
    cv.rect(2, 4, w - 4, h - 6, '#2e211c')
    for x in range(6, w - 4, 8):
        cv.rect(x, 4, 1, h - 6, '#261a16')
    # costados y corona
    cv.rect(0, 0, 4, h, wd[2]); cv.rect(0, 0, 1, h, wd[3]); cv.rect(3, 0, 1, h, wd[1])
    cv.rect(w - 4, 0, 4, h, wd[2]); cv.rect(w - 4, 0, 1, h, wd[3]); cv.rect(w - 1, 0, 1, h, wd[1])
    cv.rect(0, 0, w, 5, wd[2]); cv.rect(0, 0, w, 1, wd[4]); cv.rect(0, 4, w, 1, wd[0])
    cv.rect(-1 + 1, 5, w, 1, wd[1])
    # zócalo
    cv.rect(0, h - 6, w, 6, wd[1]); cv.rect(0, h - 6, w, 1, wd[3])
    # baldas
    inner_top, inner_bot = 6, h - 6
    step = (inner_bot - inner_top) / shelves
    decos = [deco_plant, deco_crystal, deco_hourglass, None, None]
    rnd.shuffle(decos)
    for i in range(shelves):
        ybot = int(inner_top + step * (i + 1))
        ytop = int(inner_top + step * i)
        fill_shelf(cv, 4, w - 4, ybot - 2, (ybot - 2) - (ytop + 2), rnd, decos[i % len(decos)])
        if i < shelves - 1 or True:
            cv.rect(4, ybot - 2, w - 8, 3, wd[2])
            cv.rect(4, ybot - 2, w - 8, 1, wd[4])
            cv.rect(4, ybot, w - 8, 1, wd[0])
    cv.outline(0.45)
    return cv.save(name)


def grimoire():
    """Grimorio abierto sobre un atril de mesa, con runas que brillan."""
    w, h = 46, 30
    cv = Cv(w, h)
    wd = rp('#7a4f38')
    # atril
    cv.poly([(12, h - 1), (34, h - 1), (31, h - 6), (15, h - 6)], wd[2])
    cv.rect(12, h - 1, 23, 1, wd[0])
    cv.rect(15, h - 6, 17, 1, wd[3])
    # tapas (cuero ciruela)
    cv_ = rp('#5a2a4a')
    cv.poly([(1, 7), (22, 3), (24, 3), (24, 24), (22, 24), (2, 25)], cv_[1])
    cv.poly([(45, 7), (24, 3), (22, 3), (22, 24), (24, 24), (44, 25)], cv_[1])
    # cantos de las páginas
    cv.poly([(2, 7), (22, 4), (23, 4), (23, 23), (3, 23)], '#d8c8a0')
    cv.poly([(44, 7), (24, 4), (23, 4), (23, 23), (43, 23)], '#d8c8a0')
    # hojas
    pg = rp('#f1e4c2')
    cv.poly([(3, 6), (22, 3), (23, 3), (23, 21), (4, 21)], pg[2])
    cv.poly([(43, 6), (24, 3), (23, 3), (23, 21), (42, 21)], pg[3])
    # sombra del lomo
    cv.rect(22, 3, 2, 19, pg[1])
    cv.rect(23, 3, 1, 19, pg[0])
    # renglones (izquierda)
    for i, yy in enumerate(range(8, 20, 2)):
        x0 = 6 + (i % 2)
        cv.rect(x0, yy - (1 if i < 2 else 0), 13 - (i % 3) * 2, 1, '#9a8468')
    # círculo de runas (derecha)
    cx, cy = 33, 12
    for a in range(0, 360, 20):
        x = cx + round(6 * math.cos(math.radians(a)))
        y = cy + round(5 * math.sin(math.radians(a)))
        cv.px(x, y, '#b48cff')
    for a in range(0, 360, 60):
        x = cx + round(3 * math.cos(math.radians(a + 30)))
        y = cy + round(2.5 * math.sin(math.radians(a + 30)))
        cv.px(x, y, '#e2d4ff')
    cv.px(cx, cy, '#ffffff'); cv.px(cx - 1, cy, '#d8c4ff'); cv.px(cx + 1, cy, '#d8c4ff'); cv.px(cx, cy - 1, '#d8c4ff')
    cv.line(cx - 4, cy + 2, cx + 4, cy - 2, '#8a6ad8')
    for i, yy in enumerate(range(18, 21, 2)):
        cv.rect(27, yy, 12, 1, '#9a8468')
    # esquinas doradas
    for (x, y) in [(1, 6), (44, 6), (2, 24), (43, 24)]:
        cv.px(x, y, GOLD)
    # cinta marcapáginas
    cv.rect(24, 21, 1, 6, '#c03a3a'); cv.px(24, 27, '#8a2020'); cv.px(25, 26, '#c03a3a')
    cv.outline(0.4)
    return cv.save('grimoire')


def inkwell():
    cv = Cv(13, 20)
    ink = rp('#2f3f8a')
    cv.rect(2, 13, 7, 6, ink[1]); cv.rect(3, 12, 5, 1, ink[2]); cv.rect(3, 14, 1, 4, ink[3])
    cv.rect(4, 10, 3, 2, '#3a3a4a'); cv.rect(2, 18, 7, 1, ink[0])
    # pluma
    fe = rp('#f4efe6')
    pts = [(5, 11), (11, 1), (12, 2), (7, 10)]
    cv.poly(pts, fe[2])
    cv.line(6, 10, 11, 2, fe[1])
    cv.px(12, 1, fe[4]); cv.px(10, 3, fe[3]); cv.px(9, 5, fe[3])
    cv.outline(0.4)
    return cv.save('inkwell')


def candlestick():
    cv = Cv(8, 16)
    br = rp('#c9963a')
    cv.rect(1, 14, 6, 2, br[2]); cv.rect(1, 14, 6, 1, br[4])
    cv.rect(3, 9, 2, 5, br[2]); cv.rect(3, 9, 1, 5, br[3])
    cv.rect(2, 8, 4, 1, br[3])
    wx = rp('#f2e6c8')
    cv.rect(3, 2, 2, 6, wx[3]); cv.px(4, 2, wx[2]); cv.px(3, 7, wx[1]); cv.px(4, 4, wx[2])
    cv.px(4, 1, '#3a2a20')
    cv.outline(0.45)
    return cv.save('candlestick')


def armchair():
    w, h = 38, 40
    cv = Cv(w, h)
    vt = rp('#2f6f73')
    wd = rp('#5a3a28')
    # patas
    for x in (5, 30):
        cv.rect(x, h - 5, 3, 5, wd[2]); cv.px(x, h - 5, wd[3])
    # respaldo de orejas
    cv.ell(5, 0, 28, 14, vt[2])
    cv.rect(5, 6, 28, 22, vt[2])
    cv.rect(7, 3, 24, 1, vt[3])
    # botones capitoné
    for yy in (8, 15):
        for xx in range(10, 30, 6):
            cv.px(xx + (3 if yy == 15 else 0), yy, vt[1])
    # brazos
    for x in (0, 30):
        cv.ell(x, 14, 9, 8, vt[3] if x == 0 else vt[2])
        cv.rect(x + 1, 18, 7, 16, vt[2] if x == 0 else vt[1])
        cv.rect(x + 1, 18, 1, 16, vt[3])
    # asiento con cojín
    cv.rect(7, 24, 24, 6, vt[3]); cv.rect(7, 24, 24, 1, vt[4]); cv.rect(7, 29, 24, 1, vt[1])
    cv.rect(6, 30, 26, 5, vt[1]); cv.rect(6, 34, 26, 1, vt[0])
    # cojín amarillo
    cu = rp('#e0b24a')
    cv.ell(19, 18, 10, 8, cu[2]); cv.px(21, 19, cu[4]); cv.px(22, 20, cu[3])
    cv.outline(0.4)
    return cv.save('armchair')


def globe():
    w, h = 20, 32
    cv = Cv(w, h)
    wd = rp('#6e4630')
    br = rp('#c9963a')
    cv.rect(4, h - 2, 12, 2, wd[2]); cv.rect(4, h - 2, 12, 1, wd[3])
    cv.line(10, 20, 5, h - 2, wd[2]); cv.line(10, 20, 15, h - 2, wd[1]); cv.line(10, 20, 10, h - 2, wd[2])
    cv.rect(9, 18, 3, 3, br[2])
    # esfera
    sea = rp('#3f7fbf')
    cv.ell(3, 2, 15, 15, sea[2])
    cv.ell(4, 3, 9, 9, sea[3])
    land = rp('#6aaa4a')
    for (x, y, ww, hh) in [(5, 5, 4, 3), (7, 8, 3, 4), (11, 6, 4, 2), (12, 10, 3, 3), (9, 13, 3, 2)]:
        cv.ell(x, y, ww, hh, land[2] if x < 10 else land[1])
    cv.px(6, 5, sea[4]); cv.px(7, 4, '#ffffff')
    # meridiano de latón
    for a in range(-90, 200, 8):
        x = 10 + round(9 * math.cos(math.radians(a)))
        y = 9 + round(9 * math.sin(math.radians(a)))
        cv.px(x, y, br[3] if a < 60 else br[1])
    cv.outline(0.4)
    return cv.save('globe')


def star_chart():
    w, h = 32, 26
    cv = Cv(w, h)
    cv.rect(0, 0, w, 2, '#7a4f38'); cv.rect(0, 0, w, 1, '#a8704a')
    cv.rect(2, 2, w - 4, h - 4, '#1f2a4f')
    cv.rect(2, 2, w - 4, 1, '#2a3a66')
    cv.rect(0, h - 2, w, 2, '#7a4f38'); cv.rect(0, h - 1, w, 1, '#5a3a28')
    stars = [(6, 6), (10, 9), (14, 7), (18, 11), (22, 8), (26, 12), (8, 16), (13, 18), (20, 17), (24, 20), (5, 20), (17, 4)]
    for a, b in [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (6, 7), (7, 8), (8, 9)]:
        cv.line(*stars[a], *stars[b], '#4a5a8a')
    for (x, y) in stars:
        cv.px(x, y, '#f4efd8')
    cv.px(17, 4, '#ffd84d')
    # luna
    cv.ell(22, 3, 6, 6, '#f1e4c2'); cv.ell(24, 3, 5, 5, '#1f2a4f')
    # cordel
    cv.line(10, 0, 16, -4, '#5a3a28')
    cv.outline(0.5)
    return cv.save('star_chart')


def portrait():
    """Retrato de la maestra (con su sombrero de bruja) en un marco dorado."""
    w, h = 24, 30
    cv = Cv(w, h)
    fr = rp('#d8a84a')
    cv.rect(0, 0, w, h, fr[2]); cv.rect(0, 0, w, 1, fr[4]); cv.rect(0, 0, 1, h, fr[3])
    cv.rect(w - 1, 0, 1, h, fr[1]); cv.rect(0, h - 1, w, 1, fr[0])
    cv.rect(2, 2, w - 4, h - 4, '#3a2f4a')
    cv.rect(2, 2, w - 4, 8, '#46385a')
    # hombros (capa morada)
    cv.ell(4, 20, 16, 12, '#6a3a8a')
    cv.rect(3, 25, 18, 3, '#6a3a8a')
    # cara
    cv.ell(8, 12, 8, 9, '#f2c9a8')
    cv.rect(7, 13, 2, 7, '#e8e8f0'); cv.rect(15, 13, 2, 7, '#e8e8f0')   # pelo blanco
    cv.px(10, 16, '#3a2a3a'); cv.px(13, 16, '#3a2a3a'); cv.px(11, 18, '#c0706a'); cv.px(12, 18, '#c0706a')
    # sombrero
    cv.rect(5, 11, 14, 2, '#4a2a6a')
    cv.poly([(8, 11), (16, 11), (14, 3), (11, 2)], '#5a3480')
    cv.px(14, 3, '#5a3480'); cv.px(16, 2, '#5a3480')
    cv.rect(8, 9, 8, 1, '#e8c060')
    cv.outline(0.45)
    return cv.save('portrait')


def scroll_basket():
    w, h = 20, 20
    cv = Cv(w, h)
    pa = rp('#efe2c4')
    for i, (x, tilt) in enumerate([(4, -1), (8, 0), (12, 1), (6, 0), (10, -1)]):
        top = 2 + (i % 2) * 2
        cv.line(x, 12, x + tilt * 3, top, pa[2])
        cv.line(x + 1, 12, x + 1 + tilt * 3, top, pa[3])
        cv.px(x + tilt * 3, top, pa[4]); cv.px(x + tilt * 3 + 1, top, pa[3])
        cv.px(x + tilt * 2, top + 3, '#c03a3a')
    bk = rp('#c08a4a')
    cv.poly([(1, 10), (19, 10), (17, 19), (3, 19)], bk[2])
    for yy in range(11, 19, 2):
        cv.line(2, yy, 18, yy, bk[1])
    for xx in range(3, 18, 3):
        cv.line(xx, 11, xx, 18, bk[3])
    cv.rect(1, 10, 19, 1, bk[3])
    cv.outline(0.45)
    return cv.save('scroll_basket')


def ladder():
    w, h = 16, 112
    cv = Cv(w, h)
    wd = rp('#8a5a3a')
    for i in range(h):
        off = int((h - i) * 0.05)
        cv.px(1 + off, i, wd[3]); cv.px(2 + off, i, wd[2])
        cv.px(12 + off, i, wd[2]); cv.px(13 + off, i, wd[1])
    for y in range(6, h - 2, 9):
        off = int((h - y) * 0.05)
        cv.rect(3 + off, y, 9, 2, wd[2]); cv.rect(3 + off, y, 9, 1, wd[3])
    cv.outline(0.45)
    return cv.save('ladder')


def plant_big():
    w, h = 30, 46
    cv = Cv(w, h)
    tc = rp('#c0663a')
    cv.poly([(7, 34), (23, 34), (21, h - 1), (9, h - 1)], tc[2])
    cv.rect(6, 33, 18, 3, tc[3]); cv.rect(6, 33, 18, 1, tc[4])
    cv.line(9, h - 1, 21, h - 1, tc[0])
    lf = rp('#3f8a4a')
    rnd = random.Random(3)
    leaves = [(15, 32, 3, -26), (15, 32, -10, -18), (15, 32, 11, -16), (15, 32, -13, -6), (15, 32, 13, -6),
              (15, 32, -5, -22), (15, 32, 7, -24), (15, 32, 0, -12)]
    for (x0, y0, dx, dy) in leaves:
        x1, y1 = x0 + dx, y0 + dy
        cv.line(x0, y0, x1, y1, lf[1])
        cv.ell(x1 - 4, y1 - 3, 9, 7, lf[2])
        cv.ell(x1 - 3, y1 - 3, 5, 4, lf[3])
        cv.px(x1 - 2, y1 - 2, lf[4])
        cv.line(x1 - 3, y1 + 1, x1 + 3, y1 - 1, lf[1])
    cv.outline(0.4)
    return cv.save('plant_big')


def paper_stack():
    cv = Cv(16, 8)
    pa = rp('#efe2c4')
    for i, y in enumerate([6, 5, 4, 3, 2]):
        cv.rect(1 + (i % 2), y, 13, 1, pa[2 + (i % 2)])
    cv.rect(2, 2, 12, 1, pa[4])
    cv.ell(9, 3, 4, 3, '#b8303a'); cv.px(10, 4, '#e86a6a')
    cv.outline(0.45)
    return cv.save('paper_stack')


def rug_library():
    w, h = 64, 44
    a = np.zeros((h, w, 4), np.uint8)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    base = rp('#2f4a7a')
    gold = rp('#d8a84a')
    cream = rp('#e8dcc0')
    for y in range(h):
        for x in range(w):
            d = ((x - cx) / (w / 2)) ** 2 + ((y - cy) / (h / 2)) ** 2
            if d > 1.0:
                continue
            col = base[2]
            if d > 0.86:
                col = gold[1] if (x + y) % 3 else gold[2]
            elif d > 0.78:
                col = cream[2]
            elif d > 0.7:
                col = base[1]
            elif d < 0.08:
                col = gold[3]
            elif d < 0.16:
                col = base[3]
            elif 0.38 < d < 0.44:
                col = cream[1] if (x // 2 + y // 2) % 2 else gold[2]
            if col == base[2] and (x * 7 + y * 13) % 29 == 0:
                col = base[3]
            a[y, x, :3] = col
            a[y, x, 3] = 255
    Image.fromarray(a, 'RGBA').save(f'{OUT}/tex/rug_library.png')


# ------------------------------------------------------------------ mercado: texturas

def roof_tiles(base, name):
    w, h = 32, 32
    a = np.zeros((h, w, 3), np.uint8)
    r = rp(base)
    rnd = random.Random(hash(name) & 0xffff)
    for row in range(4):
        y0 = row * 8
        off = 4 if row % 2 else 0
        for col in range(5):
            x0 = col * 8 - off
            t = rnd.choice([1, 2, 2, 2, 3])
            for yy in range(8):
                for xx in range(8):
                    X = (x0 + xx) % w
                    Y = y0 + yy
                    c = r[t]
                    if yy == 7:
                        c = r[0]
                    elif yy == 6:
                        c = r[max(0, t - 1)]
                    elif xx == 0:
                        c = r[max(0, t - 1)]
                    elif xx == 1 and yy < 5:
                        c = r[min(4, t + 1)]
                    elif yy == 0:
                        c = r[min(4, t + 1)]
                    a[Y, X] = c
    # musgo
    for _ in range(18):
        x, y = rnd.randrange(w), rnd.randrange(h)
        a[y, x] = shift(r[2], -0.05, 0.0, -60) if rnd.random() < 0.5 else r[3]
    Image.fromarray(a, 'RGB').save(f'{OUT}/tex/{name}.png')


def cobble_street():
    w, h = 64, 64
    rnd = random.Random(21)
    a = np.zeros((h, w, 3), np.uint8)
    grout = hexrgb('#5a5048')
    a[:, :] = grout
    stones = rp('#a89a88')
    stones2 = rp('#9a8c80')
    stones3 = rp('#b0a080')
    # adoquines en hileras irregulares
    y = 0
    row = 0
    while y < h:
        rh = rnd.randint(7, 9)
        x = -rnd.randint(0, 6) if row % 2 else 0
        while x < w:
            sw = rnd.randint(8, 12)
            pal = rnd.choice([stones, stones, stones2, stones3])
            for yy in range(1, rh - 1):
                for xx in range(1, sw - 1):
                    X, Y = (x + xx) % w, (y + yy) % h
                    # esquinas redondeadas
                    if (yy in (1, rh - 2)) and (xx in (1, sw - 2)):
                        continue
                    c = pal[2]
                    if yy == 1 or xx == 1:
                        c = pal[3]
                    if yy == rh - 2 or xx == sw - 2:
                        c = pal[1]
                    if rnd.random() < 0.06:
                        c = pal[rnd.choice([1, 3])]
                    a[Y, X] = c
            x += sw
        y += rh
        row += 1
    Image.fromarray(a, 'RGB').save(f'{OUT}/tex/cobble_street.png')


def flagstone():
    w, h = 32, 32
    rnd = random.Random(5)
    a = np.zeros((h, w, 3), np.uint8)
    a[:, :] = hexrgb('#6a6058')
    pal = rp('#b8ab98')
    for (x0, y0, ww, hh) in [(0, 0, 15, 15), (16, 0, 16, 10), (16, 11, 16, 21), (0, 16, 15, 16)]:
        t = rnd.choice([2, 2, 3])
        for yy in range(y0, y0 + hh - 1):
            for xx in range(x0, x0 + ww - 1):
                c = pal[t]
                if yy == y0 or xx == x0:
                    c = pal[min(4, t + 1)]
                if rnd.random() < 0.05:
                    c = pal[t - 1]
                a[yy % h, xx % w] = c
    Image.fromarray(a, 'RGB').save(f'{OUT}/tex/flagstone.png')


def water_tex():
    w, h = 32, 32
    a = np.zeros((h, w, 4), np.uint8)
    pal = rp('#3a8ab8')
    rnd = random.Random(9)
    for y in range(h):
        for x in range(w):
            v = math.sin((x + y * 0.5) * 0.4) + math.sin((x * 0.3 - y) * 0.5)
            c = pal[2] if v < 0.9 else pal[3]
            if v > 1.6:
                c = pal[4]
            a[y, x, :3] = c
            a[y, x, 3] = 200
    for _ in range(14):
        x, y = rnd.randrange(w), rnd.randrange(h)
        a[y, x, :3] = (240, 250, 255)
        a[y, x, 3] = 255
    Image.fromarray(a, 'RGBA').save(f'{OUT}/tex/water.png')


# ------------------------------------------------------------------ mercado: casas

def window_house(shutter, name, lit=False):
    w, h = 26, 30
    cv = Cv(w, h)
    wd = rp('#e8dcc0')
    sh = rp(shutter)
    # contraventanas abiertas
    for x in (0, w - 6):
        cv.rect(x, 2, 6, 19, sh[2])
        cv.rect(x, 2, 6, 1, sh[3])
        for yy in range(4, 20, 3):
            cv.rect(x + 1, yy, 4, 1, sh[1])
        cv.rect(x if x == 0 else x + 5, 2, 1, 19, sh[3] if x == 0 else sh[1])
    # marco
    cv.rect(6, 1, 14, 21, wd[2])
    cv.rect(6, 1, 14, 1, wd[3])
    # vidrio
    gl = rp('#7ab0d8') if not lit else rp('#f0c060')
    cv.rect(7, 2, 12, 19, gl[2])
    cv.rect(7, 2, 12, 5, gl[3])
    cv.line(8, 10, 12, 3, gl[4])
    cv.line(9, 12, 14, 4, gl[3])
    cv.rect(12, 2, 2, 19, wd[2])
    cv.rect(7, 10, 12, 2, wd[2])
    # jardinera con flores
    bx = rp('#8a5a3a')
    cv.rect(4, 22, 18, 5, bx[2]); cv.rect(4, 22, 18, 1, bx[3]); cv.rect(4, 26, 18, 1, bx[0])
    leaf = rp('#4f9a4a')
    rnd = random.Random(hash(name) & 0xff)
    flower_cols = ['#e8505a', '#f0a0c0', '#ffd84d', '#ffffff', '#c070e0']
    for x in range(4, 22, 2):
        cv.rect(x, 20, 2, 2, leaf[rnd.choice([1, 2, 3])])
        if rnd.random() < 0.7:
            cv.px(x + rnd.randint(0, 1), 19 + rnd.randint(0, 1), rnd.choice(flower_cols))
    for x in (5, 9, 16, 20):
        cv.rect(x, 27, 1, rnd.randint(1, 3), leaf[1])
    cv.outline(0.45)
    return cv.save(name)


def door_house(col, name):
    w, h = 22, 38
    cv = Cv(w, h)
    st = rp('#b8ab98')
    # marco de piedra con arco
    cv.rect(0, 6, w, h - 6, st[2])
    cv.ell(0, 0, w, 14, st[2])
    cv.rect(0, 6, 1, h - 6, st[3])
    d = rp(col)
    cv.rect(3, 8, w - 6, h - 9, d[2])
    cv.ell(3, 3, w - 6, 12, d[2])
    for x in range(5, w - 3, 3):
        cv.rect(x, 6, 1, h - 7, d[1])
    cv.rect(3, 8, 1, h - 9, d[3])
    # herrajes
    for yy in (12, 28):
        cv.rect(3, yy, 9, 1, '#3a3a40')
    cv.ell(14, 20, 3, 3, '#e8c060')
    # ventanuco
    cv.rect(8, 9, 6, 4, '#3a3040'); cv.rect(9, 9, 1, 4, '#5a4a60'); cv.rect(8, 10, 6, 1, '#2a2030')
    # escalón
    cv.rect(0, h - 2, w, 2, st[1]); cv.rect(0, h - 2, w, 1, st[3])
    cv.outline(0.45)
    return cv.save(name)


def hanging_sign(icon, name):
    w, h = 22, 20
    cv = Cv(w, h)
    ir = rp('#3a3a42')
    # brazo de hierro
    cv.rect(0, 0, 20, 2, ir[2]); cv.rect(0, 0, 20, 1, ir[3])
    cv.line(1, 2, 7, 6, ir[2]); cv.px(19, 2, ir[2])
    cv.px(5, 2, ir[2]); cv.px(16, 2, ir[2]); cv.px(5, 3, ir[1]); cv.px(16, 3, ir[1])
    wd = rp('#9a6a42')
    cv.rect(3, 4, 16, 14, wd[2]); cv.rect(3, 4, 16, 1, wd[3]); cv.rect(3, 4, 1, 14, wd[3])
    cv.rect(18, 4, 1, 14, wd[1]); cv.rect(3, 17, 16, 1, wd[0])
    cx, cy = 11, 11
    if icon == 'pan':
        b = rp('#d8964a')
        cv.ell(cx - 6, cy - 3, 12, 7, b[2]); cv.ell(cx - 5, cy - 3, 9, 3, b[3])
        for x in (cx - 3, cx, cx + 3):
            cv.line(x, cy - 2, x + 1, cy + 1, b[1])
    elif icon == 'jarra':
        m = rp('#c9963a')
        cv.rect(cx - 4, cy - 3, 7, 8, m[2]); cv.rect(cx - 4, cy - 3, 1, 8, m[3])
        cv.rect(cx - 4, cy - 5, 7, 2, '#fff4d8')
        cv.rect(cx + 3, cy - 1, 2, 4, m[1]); cv.px(cx + 4, cy - 1, m[1])
    elif icon == 'bota':
        bt = rp('#6a3a2a')
        cv.rect(cx - 3, cy - 5, 5, 8, bt[2]); cv.rect(cx - 3, cy + 2, 9, 3, bt[2])
        cv.rect(cx - 3, cy - 5, 1, 10, bt[3]); cv.rect(cx - 3, cy + 4, 9, 1, bt[0])
    elif icon == 'yunque':
        an = rp('#5a5a66')
        cv.rect(cx - 6, cy - 3, 12, 3, an[2]); cv.rect(cx - 6, cy - 3, 12, 1, an[3])
        cv.rect(cx - 2, cy, 4, 3, an[1]); cv.rect(cx - 4, cy + 3, 8, 2, an[2])
        cv.poly([(cx - 9, cy - 3), (cx - 6, cy - 3), (cx - 6, cy - 1)], an[2])
    elif icon == 'caldero':
        k = rp('#3a3446')
        cv.ell(cx - 5, cy - 3, 11, 9, k[2]); cv.rect(cx - 6, cy - 3, 13, 2, k[3])
        cv.rect(cx - 4, cy - 4, 9, 1, '#7ee08a'); cv.px(cx - 1, cy - 6, '#9fffaa'); cv.px(cx + 2, cy - 7, '#9fffaa')
    cv.outline(0.45)
    return cv.save(name)


def chimney_pot():
    cv = Cv(10, 14)
    b = rp('#a85a3a')
    cv.rect(1, 3, 8, 11, b[2]); cv.rect(0, 1, 10, 3, b[3]); cv.rect(0, 1, 10, 1, b[4])
    for yy in range(5, 14, 3):
        cv.rect(1, yy, 8, 1, b[1])
    cv.outline(0.45)
    return cv.save('chimney')


# ------------------------------------------------------------------ mercado: puestos

AWNINGS = {
    'verde': ('#5d9c59', '#f1e8d0'),
    'morado': ('#7a5aa8', '#f1e8d0'),
    'rojo': ('#b8433c', '#f1e8d0'),
    'naranja': ('#e08a3a', '#fff0c8'),
    'azul': ('#3f7fbf', '#f4f6fa'),
}


def awning(key):
    c1, c2 = AWNINGS[key]
    r1, r2 = rp(c1), rp(c2)
    w, h = 64, 24
    a = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        for x in range(w):
            stripe = (x // 8) % 2
            r = r1 if stripe == 0 else r2
            lv = 3 if y < 3 else (2 if y < h - 4 else 1)
            if x % 8 == 7:
                lv = max(0, lv - 1)
            a[y, x, :3] = r[lv]
            a[y, x, 3] = 255
    Image.fromarray(a, 'RGBA').save(f'{OUT}/tex/awning_{key}.png')
    # faldón festoneado (cuelga del borde delantero)
    w2, h2 = 64, 10
    cv = Cv(w2, h2)
    for x0 in range(0, w2, 8):
        stripe = (x0 // 8) % 2
        r = r1 if stripe == 0 else r2
        cv.rect(x0, 0, 8, 5, r[2])
        cv.ell(x0, 2, 8, 7, r[2])
        cv.rect(x0, 0, 8, 1, r[3])
        cv.px(x0 + 3, 7, r[1]); cv.px(x0 + 4, 7, r[1])
    a2 = np.array(cv.im)
    a2[0, :, :3] = np.array(rp(c1)[0]) * 0.8
    a2[0, :, 3] = 255
    Image.fromarray(a2, 'RGBA').save(f'{OUT}/tex/valance_{key}.png')


def goods_herbs():
    w, h = 52, 20
    cv = Cv(w, h)
    rnd = random.Random(31)
    bk = rp('#c08a4a')
    # cesta de hongos violeta
    cv.poly([(1, 11), (17, 11), (15, 19), (3, 19)], bk[2])
    for yy in range(12, 19, 2):
        cv.line(2, yy, 16, yy, bk[1])
    mu = rp('#9a5ad6')
    for x in (2, 6, 10, 13):
        cv.ell(x, 6 + (x % 3), 6, 5, mu[2]); cv.px(x + 2, 7 + (x % 3), mu[4]); cv.px(x + 1, 8 + (x % 3), '#f1e6ff')
    # raíces de mandrágora atadas
    ro = rp('#c9a06b')
    for i, x in enumerate((20, 25)):
        cv.ell(x, 9, 6, 9, ro[2]); cv.px(x + 2, 12, '#3a2420'); cv.px(x + 4, 12, '#3a2420')
        cv.rect(x + 2, 4, 1, 5, '#69b84a'); cv.rect(x + 3, 3, 1, 5, '#4f9a4a'); cv.rect(x + 1, 5, 1, 3, '#69b84a')
    # manojos de hierbas
    hb = rp('#5a9a4a')
    for x in (33, 38):
        for k in range(5):
            cv.line(x + k, 18, x + 2 + rnd.randint(-2, 2), 6, hb[rnd.randint(1, 3)])
        cv.rect(x, 14, 5, 1, '#c8a060')
    # macetitas con brotes
    for x in (45,):
        cv.rect(x, 13, 6, 6, '#c0663a'); cv.rect(x, 13, 6, 1, '#e08a5a')
        cv.rect(x + 2, 8, 2, 5, '#4f9a4a'); cv.rect(x, 8, 2, 2, '#69b84a'); cv.rect(x + 4, 7, 2, 2, '#69b84a')
    cv.outline(0.42)
    return cv.save('goods_herbs')


def goods_gems():
    w, h = 52, 18
    cv = Cv(w, h)
    tray = rp('#5a2a4a')
    cv.rect(1, 11, 22, 6, tray[2]); cv.rect(1, 11, 22, 1, tray[3])
    gem_cols = ['#e8455a', '#4a8ae8', '#4ad88a', '#c070e8', '#ffd84d', '#7ad8f0']
    for i, x in enumerate(range(3, 21, 4)):
        g = rp(gem_cols[i % len(gem_cols)])
        cv.poly([(x, 10), (x + 1, 8), (x + 2, 8), (x + 3, 10), (x + 1, 12)], g[2])
        cv.px(x + 1, 9, g[4])
    # cúmulo de cristal (escarcha de luna)
    cr = rp('#a8e6ff')
    cv.poly([(26, 17), (29, 3), (32, 17)], cr[2]); cv.line(29, 4, 29, 15, cr[4])
    cv.poly([(31, 17), (34, 7), (37, 17)], cr[1]); cv.poly([(23, 17), (25, 9), (28, 17)], cr[3])
    # polvo de estrella en frasco y ámbar
    am = rp('#f0a632')
    cv.ell(39, 10, 6, 6, am[2]); cv.px(40, 11, am[4])
    cv.rect(46, 8, 5, 9, '#d8e8f0'); cv.rect(46, 11, 5, 6, '#ffd84d'); cv.px(47, 12, '#ffffff'); cv.rect(46, 7, 5, 1, '#8a5a3a')
    # trozo de ceniza
    ce = rp('#5a4048')
    cv.ell(38, 14, 7, 4, ce[2]); cv.px(40, 15, '#ff7a45')
    cv.outline(0.42)
    return cv.save('goods_gems')


def goods_books():
    w, h = 52, 20
    cv = Cv(w, h)
    rnd = random.Random(41)
    # pila de libros
    y = 19
    for i in range(4):
        c = rnd.choice(BOOK_COLS)
        r = rp(c)
        ww = rnd.randint(11, 14)
        cv.rect(1 + i % 2, y - 3, ww, 3, r[2]); cv.rect(1 + i % 2, y - 3, ww, 1, r[3]); cv.rect(ww + i % 2, y - 3, 1, 3, r[1])
        y -= 3
    # rollos de papel
    pa = rp('#efe2c4')
    for i, x in enumerate((17, 21)):
        cv.rect(x, 9, 3, 10, pa[2]); cv.rect(x, 9, 1, 10, pa[3]); cv.px(x + 1, 13, '#c03a3a'); cv.px(x + 1, 14, '#c03a3a')
    # tinteros de colores
    for i, c in enumerate(['#e8553a', '#4a8ae8', '#4ad88a', '#9a6ae8', '#ffd84d']):
        x = 26 + i * 4
        r = rp(c)
        cv.rect(x, 13, 3, 6, r[2]); cv.px(x, 14, r[4]); cv.rect(x + 1, 11, 1, 2, '#3a3a4a')
    # plumas en un vaso
    cv.rect(46, 12, 5, 7, '#7a6a8a'); cv.rect(46, 12, 1, 7, '#9a8aaa')
    for (x1, y1) in [(45, 3), (49, 2), (51, 5)]:
        cv.line(48, 12, x1, y1, '#f4efe6')
    cv.outline(0.42)
    return cv.save('goods_books')


def goods_mabel():
    w, h = 52, 20
    cv = Cv(w, h)
    cols = ['#e8505a', '#4a9ae0', '#ffd84d', '#7ac06a']
    y = 19
    for i, c in enumerate(cols[:3]):
        r = rp(c)
        cv.ell(1 + i % 2, y - 5, 16, 6, r[2]); cv.ell(3 + i % 2, y - 5, 10, 2, r[3])
        cv.px(1 + i % 2, y - 3, r[1]); cv.px(16 + i % 2, y - 3, r[1])
        y -= 4
    # alfombra enrollada
    rg = rp('#a8443c')
    cv.rect(19, 12, 16, 6, rg[2]); cv.rect(19, 12, 16, 1, rg[3]); cv.ell(33, 12, 5, 6, '#e8c060')
    for x in range(21, 33, 3):
        cv.rect(x, 13, 1, 4, '#e8c060')
    # farolillos
    for x in (38, 45):
        cv.rect(x + 2, 4, 1, 2, '#3a3a40')
        cv.rect(x, 6, 5, 7, '#3a3a40'); cv.rect(x + 1, 7, 3, 5, '#ffd27a'); cv.px(x + 2, 9, '#fff4d0')
        cv.rect(x - 1, 13, 7, 1, '#3a3a40')
    cv.outline(0.42)
    return cv.save('goods_mabel')


def goods_fish():
    w, h = 52, 18
    cv = Cv(w, h)
    cr = rp('#9a6a42')
    cv.rect(1, 9, 24, 8, cr[2]); cv.rect(1, 9, 24, 1, cr[3]); cv.rect(1, 13, 24, 1, cr[1])
    ice = rp('#d8f0f8')
    cv.rect(2, 7, 22, 2, ice[3])
    fish = rp('#8ab0c8')
    for x in (3, 10, 16):
        cv.ell(x, 3, 7, 4, fish[2]); cv.px(x + 1, 4, '#1a1a2a'); cv.poly([(x + 6, 4), (x + 8, 2), (x + 8, 6)], fish[1])
        cv.px(x + 2, 3, fish[4])
    # conchas con lágrimas de sirena
    sh = rp('#f0c8b8')
    for x in (29, 37, 45):
        cv.ell(x, 9, 7, 6, sh[2]); cv.line(x + 1, 11, x + 5, 11, sh[1])
        cv.ell(x + 2, 8, 3, 3, '#6fd6d0'); cv.px(x + 2, 8, '#ffffff')
    cv.outline(0.42)
    return cv.save('goods_fish')


# ------------------------------------------------------------------ mercado: decorado

def tree():
    w, h = 68, 88
    cv = Cv(w, h)
    tr = rp('#6a4a32')
    cv.poly([(29, h - 1), (39, h - 1), (37, 46), (31, 46)], tr[2])
    cv.line(31, 46, 31, h - 1, tr[3])
    cv.poly([(24, h - 1), (30, h - 5), (30, h - 1)], tr[2]); cv.poly([(44, h - 1), (38, h - 5), (38, h - 1)], tr[1])
    cv.line(34, 50, 22, 40, tr[2]); cv.line(34, 52, 46, 42, tr[1])
    lf = rp('#4f9a4a')
    rnd = random.Random(12)
    blobs = []
    for _ in range(26):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0, 1) ** 0.6
        x = 34 + math.cos(a) * r * 26
        y = 30 + math.sin(a) * r * 22
        s = rnd.randint(10, 16)
        blobs.append((x, y, s))
    blobs.sort(key=lambda b: b[1])
    for (x, y, s) in blobs:
        cv.ell(x - s / 2, y - s / 2, s, s * 0.85, lf[1])
    for (x, y, s) in blobs:
        cv.ell(x - s / 2 + 1, y - s / 2, s - 3, s * 0.7 - 2, lf[2])
    for (x, y, s) in blobs:
        if x < 40 and y < 34:
            cv.ell(x - s / 2 + 2, y - s / 2 + 1, s / 2, s / 3, lf[3])
            cv.px(x - s / 4, y - s / 3, lf[4])
    # frutos rojos
    for _ in range(9):
        cv.px(rnd.randint(14, 54), rnd.randint(14, 46), '#e8505a')
    cv.outline(0.42)
    return cv.save('tree')


def bush():
    cv = Cv(34, 20)
    lf = rp('#4a8a44')
    for (x, y, s) in [(2, 6, 14), (10, 2, 16), (19, 5, 14), (8, 8, 12), (22, 9, 11)]:
        cv.ell(x, y, s, s * 0.8, lf[1])
        cv.ell(x + 1, y, s - 3, s * 0.6, lf[2])
        cv.ell(x + 2, y + 1, s / 2.5, s / 4, lf[3])
    for (x, y) in [(6, 9), (14, 6), (24, 10), (18, 12)]:
        cv.px(x, y, '#f0a0c0'); cv.px(x + 1, y, '#ffffff')
    cv.outline(0.42)
    return cv.save('bush')


def lamppost():
    w, h = 14, 56
    cv = Cv(w, h)
    ir = rp('#34343e')
    cv.rect(4, h - 3, 6, 3, ir[2]); cv.rect(4, h - 3, 6, 1, ir[3])
    cv.rect(6, 12, 2, h - 14, ir[2]); cv.rect(6, 12, 1, h - 14, ir[3])
    cv.rect(5, 20, 4, 2, ir[2])
    cv.rect(2, 10, 10, 2, ir[2])
    cv.rect(3, 2, 8, 8, ir[1]); cv.rect(4, 3, 6, 6, '#ffe2a0'); cv.rect(5, 4, 2, 2, '#fff8e0')
    cv.poly([(2, 2), (12, 2), (7, -2)], ir[2]); cv.rect(2, 1, 10, 1, ir[2])
    cv.outline(0.5)
    return cv.save('lamppost')


def bunting(seed, name):
    w, h = 128, 22
    cv = Cv(w, h)
    rnd = random.Random(seed)
    cols = ['#e8505a', '#ffd84d', '#4a9ae0', '#7ac06a', '#f4efe6', '#c070e0', '#e08a3a']
    pts = []
    for x in range(w):
        t = x / (w - 1)
        y = 2 + 7 * (1 - (2 * t - 1) ** 2)
        pts.append((x, round(y)))
    for (x, y) in pts:
        cv.px(x, y, '#5a4a3a')
    for i, x in enumerate(range(4, w - 6, 9)):
        y = pts[x][1]
        c = rp(cols[(i + seed) % len(cols)])
        cv.poly([(x, y + 1), (x + 6, y + 1), (x + 3, y + 9)], c[2])
        cv.line(x, y + 1, x + 6, y + 1, c[3])
        cv.px(x + 3, y + 8, c[1])
    return cv.save(name)


def banner(col, name):
    w, h = 14, 42
    cv = Cv(w, h)
    rod = rp('#8a5a3a')
    cv.rect(0, 0, w, 2, rod[2]); cv.rect(0, 0, w, 1, rod[3])
    c = rp(col)
    cv.poly([(1, 2), (13, 2), (13, h - 1), (7, h - 7), (1, h - 1)], c[2])
    cv.rect(1, 2, 2, h - 6, c[3]); cv.rect(11, 2, 2, h - 6, c[1])
    cv.rect(3, 4, 8, 1, '#e8c060'); cv.rect(3, h - 12, 8, 1, '#e8c060')
    # montaña con estrella (escudo del pueblo)
    cv.poly([(3, 24), (7, 13), (11, 24)], '#f4efe6'); cv.poly([(5, 18), (7, 13), (9, 18)], '#ffffff')
    cv.px(7, 9, '#ffd84d'); cv.px(6, 9, '#ffe890'); cv.px(8, 9, '#ffe890'); cv.px(7, 8, '#ffe890'); cv.px(7, 10, '#ffe890')
    cv.outline(0.45)
    return cv.save(name)


def flowers_bed():
    w, h = 44, 14
    cv = Cv(w, h)
    rnd = random.Random(17)
    lf = rp('#4f9a4a')
    cols = ['#e8505a', '#f0a0c0', '#ffd84d', '#ffffff', '#c070e0', '#e08a3a']
    for x in range(0, w, 2):
        hh = rnd.randint(5, 10)
        cv.rect(x, h - hh, 1, hh, lf[rnd.choice([1, 2])])
        cv.rect(x + 1, h - hh + 3, 1, hh - 3, lf[2])
    for x in range(1, w - 1, 3):
        y = rnd.randint(1, 6)
        c = rp(rnd.choice(cols))
        cv.rect(x, y, 2, 2, c[2]); cv.px(x, y, c[4])
    cv.outline(0.42)
    return cv.save('flowers')


def flowerpot_big(col, name):
    cv = Cv(18, 20)
    tc = rp('#c0663a')
    cv.poly([(3, 11), (15, 11), (13, 19), (5, 19)], tc[2]); cv.rect(2, 10, 14, 2, tc[3])
    lf = rp('#4f9a4a')
    c = rp(col)
    for (x, y) in [(3, 6), (7, 3), (11, 5), (5, 8), (10, 8), (13, 7)]:
        cv.ell(x - 1, y, 5, 4, lf[2])
    for (x, y) in [(4, 4), (8, 1), (12, 3), (9, 6), (5, 7), (14, 5)]:
        cv.rect(x, y, 2, 2, c[2]); cv.px(x, y, c[4])
    cv.outline(0.42)
    return cv.save(name)


def cart():
    w, h = 46, 30
    cv = Cv(w, h)
    wd = rp('#9a6a42')
    # mercancía: calabazas, manzanas, coles
    pu = rp('#e88a2a')
    for x in (6, 15):
        cv.ell(x, 4, 10, 8, pu[2]); cv.line(x + 5, 4, x + 5, 11, pu[1]); cv.px(x + 2, 6, pu[4]); cv.rect(x + 4, 2, 2, 2, '#4f7a3a')
    ap = rp('#d8404a')
    for (x, y) in [(25, 8), (29, 7), (33, 8), (27, 5), (31, 4)]:
        cv.ell(x, y, 5, 5, ap[2]); cv.px(x + 1, y + 1, ap[4])
    co = rp('#7ac06a')
    cv.ell(36, 3, 9, 9, co[2]); cv.ell(38, 4, 5, 5, co[3])
    # caja del carro
    cv.rect(2, 12, 42, 9, wd[2]); cv.rect(2, 12, 42, 1, wd[3]); cv.rect(2, 16, 42, 1, wd[1]); cv.rect(2, 20, 42, 1, wd[0])
    for x in (2, 15, 30, 43):
        cv.rect(x, 12, 1, 9, wd[1])
    # varas
    cv.line(43, 18, 45, 24, wd[1])
    # rueda
    wh = rp('#6a4a32')
    cv.ell(10, 16, 14, 14, wh[2]); cv.ell(12, 18, 10, 10, (0, 0, 0)); cv.ell(13, 19, 8, 8, wh[1])
    im = np.array(cv.im)
    im[(im[:, :, 0] == 0) & (im[:, :, 1] == 0) & (im[:, :, 2] == 0) & (im[:, :, 3] == 255)] = 0
    cv.im = Image.fromarray(im, 'RGBA'); cv.d = ImageDraw.Draw(cv.im)
    for a in range(0, 180, 45):
        dx, dy = 6 * math.cos(math.radians(a)), 6 * math.sin(math.radians(a))
        cv.line(17 - dx, 23 - dy, 17 + dx, 23 + dy, wh[2])
    cv.ell(15, 21, 4, 4, wh[3])
    cv.outline(0.42)
    return cv.save('cart')


def crate_apples():
    cv = Cv(22, 18)
    wd = rp('#9a6a42')
    ap = rp('#d8404a')
    for (x, y) in [(2, 3), (6, 2), (10, 3), (14, 2), (17, 4), (4, 5), (12, 5)]:
        cv.ell(x, y, 5, 5, ap[2]); cv.px(x + 1, y + 1, ap[4]); cv.px(x + 2, y, '#4f7a3a')
    cv.rect(1, 8, 20, 9, wd[2]); cv.rect(1, 8, 20, 1, wd[3]); cv.rect(1, 12, 20, 1, wd[1])
    cv.rect(1, 8, 1, 9, wd[3]); cv.rect(20, 8, 1, 9, wd[1])
    cv.outline(0.42)
    return cv.save('crate_apples')


def pigeon():
    """Paloma: 4 cuadros de 12x10 (quieta, picoteando, volando x2)."""
    fw, fh = 12, 10
    sheet = Cv(fw * 4, fh)
    g = rp('#8a8aa0')
    for f in range(4):
        cv = Cv(fw, fh)
        if f < 2:
            cv.ell(2, 4, 8, 5, g[2]); cv.ell(3, 4, 5, 2, g[3])
            hx, hy = (8, 2) if f == 0 else (9, 5)
            cv.ell(hx, hy, 3, 3, g[2]); cv.px(hx + 1, hy + 1, '#1a1a22'); cv.px(hx + 3, hy + 1, '#e8a04a')
            cv.px(hx, hy + 2, '#6ac0a0')
            cv.px(1, 6, g[1]); cv.px(0, 7, g[1])
            cv.px(5, 9, '#e87060'); cv.px(7, 9, '#e87060')
        else:
            cv.ell(3, 4, 7, 4, g[2]); cv.px(9, 4, '#e8a04a'); cv.px(8, 4, '#1a1a22')
            if f == 2:
                cv.poly([(4, 4), (7, 4), (3, 0)], g[3]); cv.poly([(5, 6), (8, 6), (6, 9)], g[1])
            else:
                cv.poly([(4, 5), (8, 5), (2, 8)], g[3]); cv.poly([(5, 4), (8, 4), (7, 1)], g[1])
        cv.outline(0.45)
        sheet.paste(cv, f * fw, 0)
    return sheet.save('pigeon')


def swallow():
    fw, fh = 12, 7
    sheet = Cv(fw * 2, fh)
    for f in range(2):
        cv = Cv(fw, fh)
        c = '#2a2a3a'
        cv.rect(4, 3, 4, 2, c); cv.px(8, 3, c); cv.px(3, 4, c); cv.px(2, 5, c)
        if f == 0:
            cv.line(5, 3, 1, 0, c); cv.line(7, 3, 10, 0, c)
        else:
            cv.line(5, 4, 1, 6, c); cv.line(7, 4, 11, 6, c)
        sheet.paste(cv, f * fw, 0)
    return sheet.save('swallow')


def window_shop():
    """Escaparate de la tienda de pociones (fachada en el mercado)."""
    w, h = 34, 28
    cv = Cv(w, h)
    wd = rp('#5a3a5a')
    cv.rect(0, 0, w, h, wd[2]); cv.rect(0, 0, w, 1, wd[3]); cv.rect(0, h - 1, w, 1, wd[0])
    gl = rp('#3a3a5a')
    cv.rect(2, 2, w - 4, h - 7, gl[2])
    cv.rect(2, 2, w - 4, 3, gl[3])
    # repisa con frascos
    cv.rect(2, h - 9, w - 4, 2, '#8a5a3a')
    cols = ['#9a6ae8', '#5fe0c0', '#ff7d4d', '#ffbf2e', '#4b5bd6', '#9ae04a']
    for i, x in enumerate(range(4, w - 5, 5)):
        c = rp(cols[i % len(cols)])
        hh = 5 + (i % 2) * 2
        cv.rect(x, h - 9 - hh, 3, hh, c[2]); cv.px(x, h - 9 - hh + 1, c[4]); cv.rect(x + 1, h - 11 - hh, 1, 2, '#c8b89a')
    cv.line(4, 10, 9, 3, '#8a8aaa'); cv.line(6, 10, 11, 3, '#6a6a8a')
    cv.rect(16, 2, 1, h - 7, wd[2])
    # jardinera
    cv.rect(0, h - 5, w, 5, '#7a4f38'); cv.rect(0, h - 5, w, 1, '#a8704a')
    for x in range(1, w - 1, 3):
        cv.px(x, h - 6, ['#e8505a', '#ffd84d', '#c070e0'][x % 3]); cv.px(x + 1, h - 6, '#4f9a4a')
    cv.outline(0.45)
    return cv.save('window_shop')


def well_bucket():
    cv = Cv(12, 12)
    wd = rp('#8a5a3a')
    cv.poly([(1, 2), (11, 2), (10, 11), (2, 11)], wd[2])
    cv.rect(1, 4, 10, 1, '#3a3a40'); cv.rect(2, 9, 9, 1, '#3a3a40'); cv.rect(1, 2, 10, 1, wd[3])
    cv.rect(2, 3, 8, 1, '#5aa0d0')
    cv.outline(0.45)
    return cv.save('bucket')


def drop():
    cv = Cv(3, 4)
    cv.px(1, 0, '#d8f4ff'); cv.rect(0, 1, 3, 2, '#9ad8f8'); cv.px(1, 3, '#6ab8e8'); cv.px(0, 1, '#ffffff')
    return cv.save('drop')


# --- R3 WORLD3: el mostrador transversal (su costado, el libro de cuentas, la campanilla) ------------------------

CF_OUT, CF_DARK, CF_MID, CF_LIGHT, CF_HI = '#140607', '#471d17', '#7a4a2e', '#997246', '#b79a66'
BRASS = ['#4b1f11', '#bd7434', '#f0c050', '#ffe669', '#fff583']


def counter_side():
    """Costado del mostrador del lado de ella (64x32 = 2 m x 1 m): una fila de cajones y dos puertas de alacena."""
    rnd = random.Random(31)
    cv = Cv(64, 32)
    cv.rect(0, 0, 64, 32, CF_MID)
    # cajones (8 px de alto): 4 por cada 2 m
    for i in range(4):
        x0 = i * 16
        cv.rect(x0, 0, 16, 9, CF_OUT)
        cv.rect(x0 + 1, 1, 14, 7, CF_MID)
        cv.rect(x0 + 1, 1, 14, 1, CF_LIGHT)
        cv.rect(x0 + 1, 7, 14, 1, CF_DARK)
        cv.rect(x0 + 1, 1, 1, 7, CF_LIGHT)
        cv.rect(x0 + 6, 3, 4, 2, BRASS[1])        # tirador de latón
        cv.rect(x0 + 6, 3, 3, 1, BRASS[2])
        cv.px(x0 + 6, 3, BRASS[4])
        cv.px(x0 + 9, 4, BRASS[0])
    # dos puertas de alacena (cada una 1 m): marco, panel rehundido y argolla
    for i in range(2):
        x0 = i * 32
        cv.rect(x0, 9, 32, 23, CF_OUT)
        cv.rect(x0 + 1, 10, 30, 21, CF_MID)
        cv.rect(x0 + 1, 10, 30, 1, CF_LIGHT)
        cv.rect(x0 + 1, 10, 1, 21, CF_LIGHT)
        cv.rect(x0 + 4, 13, 24, 15, CF_DARK)       # panel rehundido
        cv.rect(x0 + 5, 14, 22, 13, CF_MID)
        cv.rect(x0 + 5, 26, 22, 1, CF_LIGHT)
        cv.rect(x0 + 26, 14, 1, 13, CF_LIGHT)
        cv.rect(x0 + 5, 14, 22, 1, CF_DARK)
        for _ in range(5):                          # veta
            yy = rnd.randint(16, 25)
            xx = x0 + rnd.randint(6, 18)
            cv.rect(xx, yy, rnd.randint(3, 7), 1, CF_DARK)
        rx = x0 + (27 if i == 0 else 3)              # argolla junto al centro
        cv.rect(rx, 18, 2, 4, BRASS[1])
        cv.px(rx, 18, BRASS[3])
        cv.px(rx + 1, 21, BRASS[0])
    cv.rect(0, 31, 64, 1, CF_OUT)
    return cv.save('counter_side', 'tex')


def ledger():
    """El libro de cuentas abierto sobre el mostrador (visto de frente, como open_book.png), con tintero y pluma."""
    cv = Cv(22, 12)
    # hojas abiertas (izquierda más clara, derecha en sombra) con columnas de cifras
    cv.poly([(0, 5), (3, 3), (8, 3), (10, 4), (10, 9), (0, 9)], '#f0e6cc')
    cv.poly([(10, 4), (12, 3), (17, 3), (19, 5), (19, 9), (10, 9)], '#e2d4b4')
    cv.rect(10, 4, 1, 5, '#bda995')
    for y in (5, 7):
        for x in range(2, 9, 2):
            cv.px(x, y, '#8a7a6a')
        for x in range(12, 18, 2):
            cv.px(x, y, '#8a7a6a')
    cv.rect(1, 6, 8, 1, '#c9b48e')                # renglones
    cv.rect(11, 6, 7, 1, '#bfa984')
    cv.px(16, 7, '#9e2b25'); cv.px(14, 7, '#9e2b25')   # cifras en rojo
    cv.rect(0, 9, 20, 1, '#bda995')                # canto de las hojas
    cv.rect(0, 10, 20, 2, '#6a2220')               # tapas de cuero rojo
    cv.rect(1, 11, 18, 1, '#3a1214')
    cv.px(0, 10, '#8a3a2a'); cv.px(19, 10, '#4a1618')
    # tintero y pluma a la derecha
    cv.rect(18, 8, 4, 4, '#1c1857')
    cv.rect(19, 7, 2, 1, '#3a3a4a')
    cv.px(18, 8, '#2f3f8a'); cv.px(21, 11, '#0b0922')
    for i, (x, y) in enumerate([(20, 6), (20, 5), (21, 4), (21, 3), (21, 2), (21, 1), (21, 0)]):
        cv.px(x, y, '#fffced' if i % 2 else '#c1b7aa')
    cv.px(20, 2, '#f4efe6'); cv.px(20, 1, '#fffced')
    cv.outline(0.45)
    return cv.save('ledger')


def counter_bell():
    """La campanilla de mostrador: una cúpula de latón con su botón, sobre una base de madera oscura."""
    cv = Cv(10, 8)
    cv.rect(0, 6, 10, 2, CF_DARK)                  # base
    cv.rect(0, 6, 10, 1, CF_LIGHT)
    cv.rect(1, 5, 8, 1, BRASS[1])                  # cúpula
    cv.rect(2, 4, 6, 1, BRASS[1])
    cv.rect(3, 3, 4, 1, BRASS[2])
    cv.rect(2, 4, 2, 2, BRASS[2])
    cv.px(3, 3, BRASS[4]); cv.px(2, 4, BRASS[3]); cv.px(3, 4, BRASS[4])
    cv.rect(7, 4, 1, 2, BRASS[0]); cv.px(8, 5, BRASS[0])
    cv.rect(4, 2, 2, 1, '#5a5048')                 # vástago y botón
    cv.rect(4, 1, 2, 1, '#9a8a7a')
    cv.px(4, 1, '#c8b8a8')
    cv.outline(0.45)
    return cv.save('counter_bell')


def r3_world3():
    made = [counter_side(), ledger(), counter_bell()]
    print('R3 WORLD3 ok', made)
    return made
# --- end R3 WORLD3


# ------------------------------------------------------------------ todo

def main():
    made = []
    made.append(bookshelf(seed=1, name='bookshelf'))
    made.append(bookshelf(seed=5, name='bookshelf_b'))
    made.append(bookshelf(w=48, h=56, shelves=2, seed=9, name='bookshelf_low'))
    for f in (grimoire, inkwell, candlestick, armchair, globe, star_chart, portrait, scroll_basket, ladder, plant_big,
              paper_stack, goods_herbs, goods_gems, goods_books, goods_mabel, goods_fish, tree, bush, lamppost,
              flowers_bed, cart, crate_apples, pigeon, swallow, window_shop, well_bucket, drop, chimney_pot):
        made.append(f())
    rug_library()
    roof_tiles('#b5523b', 'roof_red')
    roof_tiles('#56688a', 'roof_slate')
    roof_tiles('#7a5a8a', 'roof_plum')
    cobble_street()
    flagstone()
    water_tex()
    for k in AWNINGS:
        awning(k)
    for col, name in [('#6a9a5a', 'window_green'), ('#4a7ab0', 'window_blue'), ('#b8503c', 'window_red')]:
        made.append(window_house(col, name))
    made.append(window_house('#7a5aa8', 'window_plum'))
    made.append(door_house('#7a4a30', 'door_brown'))
    made.append(door_house('#3f6a8a', 'door_blue'))
    made.append(door_house('#5a7a3a', 'door_green'))
    for icon in ('pan', 'jarra', 'bota', 'yunque', 'caldero'):
        made.append(hanging_sign(icon, f'hsign_{icon}'))
    made.append(bunting(0, 'bunting_a'))
    made.append(bunting(3, 'bunting_b'))
    made.append(banner('#3f6fa8', 'banner_blue'))
    made.append(banner('#b8433c', 'banner_red'))
    made.append(flowerpot_big('#e8505a', 'flowerpot_red'))
    made.append(flowerpot_big('#ffd84d', 'flowerpot_yellow'))
    print('ok', len(made), 'sprites')


if __name__ == '__main__':
    # --- R3 WORLD3: "--r3" hace solo el arte de la ronda 3 (mostrador): python3 world_art.py --r3 [carpeta_assets]
    if '--r3' in sys.argv:
        sys.argv.remove('--r3')
        r3_world3()
    else:
        main()
    dest = sys.argv[1] if len(sys.argv) > 1 else None
    if dest:
        import shutil
        for kind in ('props', 'tex'):
            for f in os.listdir(f'{OUT}/{kind}'):
                shutil.copy(f'{OUT}/{kind}/{f}', f'{dest}/{kind}/{f}')
        print('copiado a', dest)
