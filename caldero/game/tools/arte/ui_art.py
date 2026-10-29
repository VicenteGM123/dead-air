import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from pixlib import *
from props import art, pad_to
from PIL import Image
OUT='./salida/ui'
os.makedirs(OUT, exist_ok=True)
# --- R3 BENCH: el banco del caldero (scripts/ui/brew_ui.gd), el ticket del pedido y el HUD (game_ui.gd) -----------
# Pixel art a 1x (el juego lo escala: el banco a 4x, el ticket y el HUD a 3x). Todo lleva prefijo bench_ / B_ para
# no pisar los nombres de pixlib ni de otros bloques. Solo esto: python3 ui_art.py --bench (sin --bench, al final).
import math, textwrap
# ------------------------------------------------------------------ paleta (guía de estilo de la ronda 3)
B_WAL = ['#1f120a', '#33200f', '#4a2f1a', '#5a3a22', '#74502f', '#916a40', '#b08552']   # nogal: 0 contorno .. 6 brillo
B_BRASS = ['#4a3418', '#7a5a2a', '#a8823f', '#c9a15a', '#e3c27e', '#f8e6b0']
B_PAPER = ['#6e4e2e', '#9c7a4e', '#cdb68a', '#dccba2', '#eadbb8', '#f5ecd6']
B_WAX = ['#4a100d', '#7a1d18', '#9e2b25', '#c0463a', '#de7660']
B_IRON = ['#121117', '#1f1e27', '#2c2c37', '#3d3e4c', '#555869', '#787c93', '#a9aec4']
B_COPPER = ['#2a1209', '#4f2512', '#7a3c1f', '#a0532d', '#c46e3f', '#e0925c', '#f6c08e']
B_BRICK = ['#2a1410', '#4a2219', '#6e3324', '#8c4530', '#a85a3c', '#c97a52']
B_INK = '#3a2618'
B_HERB = ['#2c3d22', '#3e5530', '#4e6b3a', '#6c8c4a', '#93b062']
B_FIRE = ['#7a1c0c', '#c23a16', '#ee6a22', '#ffa236', '#ffd451', '#fff4c0']
B_ESS = {'fuego': '#ff7a45', 'escarcha': '#7fd4ff', 'vida': '#7ee08a', 'sombra': '#b48cff', 'luz': '#ffd84d'}


def bench_rgb(c):
    if isinstance(c, str):
        c = c.lstrip('#')
        return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))
    return tuple(int(v) for v in c[:3])


def bench_mix(a, b, t):
    a, b = bench_rgb(a), bench_rgb(b)
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def bench_canvas(w, h):
    return np.zeros((h, w, 4), np.uint8)


def bench_put(img, x, y, c, a=255):
    h, w = img.shape[:2]
    x, y = int(x), int(y)
    if 0 <= x < w and 0 <= y < h:
        img[y, x] = (*bench_rgb(c), a)


def bench_fill(img, x0, y0, x1, y1, c, a=255):
    h, w = img.shape[:2]
    x0, y0, x1, y1 = max(0, int(x0)), max(0, int(y0)), min(w, int(x1)), min(h, int(y1))
    if x1 > x0 and y1 > y0:
        img[y0:y1, x0:x1] = (*bench_rgb(c), a)


def bench_shade(img, x0, y0, x1, y1, k):
    """Oscurece (k > 0) o aclara (k < 0) los píxeles opacos de un rectángulo."""
    h, w = img.shape[:2]
    x0, y0, x1, y1 = max(0, int(x0)), max(0, int(y0)), min(w, int(x1)), min(h, int(y1))
    if x1 <= x0 or y1 <= y0:
        return
    reg = img[y0:y1, x0:x1].astype(float)
    m = reg[..., 3] > 0
    if k >= 0:
        reg[..., :3][m] *= (1.0 - k)
    else:
        reg[..., :3][m] += (255 - reg[..., :3][m]) * (-k)
    img[y0:y1, x0:x1] = np.clip(reg, 0, 255).astype(np.uint8)


def bench_outline(img, c, keep=None, diag=False):
    """Contorno de 1 px por fuera de lo opaco. keep: máscara donde NO se dibuja (p. ej. el hueco del líquido)."""
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
    if keep is not None:
        m &= ~keep
    img[m] = (*bench_rgb(c), 255)


def bench_inner_outline(img, c):
    """Oscurece el borde de lo opaco (para dibujos que llenan el lienzo)."""
    a = img[..., 3] > 0
    h, w = a.shape
    pad = np.zeros((h + 2, w + 2), bool)
    pad[1:-1, 1:-1] = a
    edge = a & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    img[edge] = (*bench_rgb(c), 255)


def bench_up(img, k):
    return np.repeat(np.repeat(img, k, axis=0), k, axis=1)


def bench_save(img, name):
    Image.fromarray(img, 'RGBA').save(f'{OUT}/{name}')
    return img


def bench_ascii_art(art, codes):
    rows = textwrap.dedent(art).strip('\n').split('\n')
    h = len(rows)
    w = max(len(r) for r in rows)
    img = bench_canvas(w, h)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in codes:
                c = codes[ch]
                if isinstance(c, tuple) and len(c) == 2:
                    bench_put(img, x, y, c[0], c[1])
                else:
                    bench_put(img, x, y, c)
    return img


def bench_grain(img, x0, y0, x1, y1, cols, density, rng, horiz=True, lmin=3, lmax=10):
    area = max(1, (x1 - x0) * (y1 - y0))
    n = int(area * density / ((lmin + lmax) / 2.0))
    for _ in range(n):
        c = cols[int(rng.integers(len(cols)))]
        L = int(rng.integers(lmin, lmax + 1))
        if horiz:
            y = int(rng.integers(y0, y1))
            x = int(rng.integers(x0, x1))
            for xx in range(x, min(x + L, x1)):
                bench_put(img, xx, y, c)
        else:
            x = int(rng.integers(x0, x1))
            y = int(rng.integers(y0, y1))
            for yy in range(y, min(y + L, y1)):
                bench_put(img, x, yy, c)


def bench_ellipse_mask(w, h, cx, cy, rx, ry):
    yy, xx = np.mgrid[0:h, 0:w]
    return ((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1.0


def bench_brass_dot(img, x, y):
    bench_put(img, x, y, B_BRASS[4])
    bench_put(img, x + 1, y, B_BRASS[3])
    bench_put(img, x, y + 1, B_BRASS[2])
    bench_put(img, x + 1, y + 1, B_BRASS[1])


# ------------------------------------------------------------------ el mueble de los frascos
B_JAR_X = [31, 77, 123, 169]     # centro de cada frasco (px del arte)
B_BOARD_Y = [52, 104]            # y de la repisa: el frasco apoya aquí (abajo del frasco)


def bench_label_plate(img, x, y, w, h):
    bench_fill(img, x, y, x + w, y + h, B_PAPER[2])
    bench_fill(img, x + 1, y + 1, x + w - 1, y + h - 1, B_PAPER[4])
    bench_fill(img, x + 1, y + 1, x + w - 1, y + 2, B_PAPER[5])
    bench_fill(img, x + 1, y + h - 2, x + w - 1, y + h - 1, B_PAPER[3])
    for (px, py) in [(x, y), (x + w - 1, y), (x, y + h - 1), (x + w - 1, y + h - 1)]:
        bench_put(img, px, py, B_PAPER[1])


def bench_herb_bundle(img, x, y, rng, cols=None):
    cols = cols or B_HERB
    # cordel
    for yy in range(y, y + 3):
        bench_put(img, x, yy, B_PAPER[1])
    bench_put(img, x - 1, y + 3, B_WAL[4])
    bench_put(img, x, y + 3, B_WAL[5])
    bench_put(img, x + 1, y + 3, B_WAL[4])
    # tallos y hojas colgando
    for i, dx in enumerate([-4, -3, -2, -1, 0, 1, 2, 3, 4]):
        length = 13 + int(rng.integers(0, 6)) - abs(dx)
        for k in range(length):
            xx = x + dx + (1 if (k > 5 and dx > 0) else (-1 if (k > 5 and dx < 0) else 0))
            c = cols[1 + int(rng.integers(0, 3))] if k > 1 else B_WAL[4]
            if k % 3 == 2 and dx != 0:
                bench_put(img, xx + (1 if dx > 0 else -1), y + 4 + k, cols[3])
            bench_put(img, xx, y + 4 + k, c)


def bench_shelf():
    W, H = 200, 150
    img = bench_canvas(W, H)
    rng = np.random.default_rng(11)
    # fondo: tablas verticales
    x = 7
    i = 0
    while x < 193:
        x1 = min(x + 13, 193)
        base = B_WAL[1] if i % 2 == 0 else bench_mix(B_WAL[1], B_WAL[2], 0.35)
        bench_fill(img, x, 11, x1, 136, base)
        bench_grain(img, x + 1, 11, x1, 136, [bench_mix(base, B_WAL[2], 0.6), bench_mix(base, B_WAL[0], 0.45)], 0.16, rng, horiz=False, lmin=4, lmax=14)
        bench_fill(img, x, 11, x + 1, 136, B_WAL[0])
        x = x1
        i += 1
    # sombra bajo la cornisa
    for k, a in enumerate([0.55, 0.35, 0.18]):
        bench_shade(img, 7, 11 + k, 193, 12 + k, a)
    # cajones
    for (x0, x1) in [(9, 99), (101, 191)]:
        bench_fill(img, x0, 119, x1, 134, B_WAL[3])
        bench_grain(img, x0 + 1, 120, x1 - 1, 133, [B_WAL[4], B_WAL[2]], 0.22, rng)
        bench_fill(img, x0, 119, x1, 120, B_WAL[5])
        bench_fill(img, x0, 119, x0 + 1, 134, B_WAL[4])
        bench_fill(img, x0, 133, x1, 134, B_WAL[1])
        bench_fill(img, x1 - 1, 119, x1, 134, B_WAL[2])
        # tirador de latón
        kx = (x0 + x1) // 2
        bench_fill(img, kx - 4, 124, kx + 4, 129, B_BRASS[1])
        bench_fill(img, kx - 3, 125, kx + 3, 128, B_BRASS[3])
        bench_fill(img, kx - 3, 125, kx + 3, 126, B_BRASS[4])
        bench_put(img, kx - 3, 127, B_BRASS[2])
        bench_put(img, kx + 2, 127, B_BRASS[2])
        # sombra bajo el tirador
        bench_fill(img, kx - 3, 129, kx + 4, 130, B_WAL[2])
    # repisas
    for top in B_BOARD_Y:
        for k, a in enumerate([0.55, 0.35, 0.18]):
            bench_shade(img, 7, top + 10 + k, 193, top + 11 + k, a)
        bench_fill(img, 5, top, 195, top + 1, B_WAL[6])
        bench_fill(img, 5, top + 1, 195, top + 2, B_WAL[5])
        bench_fill(img, 5, top + 2, 195, top + 10, B_WAL[3])
        bench_grain(img, 5, top + 3, 195, top + 9, [B_WAL[4], B_WAL[2]], 0.25, rng)
        bench_fill(img, 5, top + 2, 195, top + 3, B_WAL[4])
        bench_fill(img, 5, top + 9, 195, top + 10, B_WAL[2])
        for cx in B_JAR_X:
            bench_label_plate(img, cx - 9, top + 3, 18, 6)
            bench_brass_dot(img, cx - 11, top + 5)
            bench_brass_dot(img, cx + 9, top + 5)
    # postes laterales
    for (x0, x1) in [(0, 7), (193, 200)]:
        bench_fill(img, x0, 9, x1, 142, B_WAL[3])
        bench_grain(img, x0 + 1, 9, x1 - 1, 142, [B_WAL[4], B_WAL[2]], 0.3, rng, horiz=False, lmin=4, lmax=12)
    bench_fill(img, 1, 9, 2, 142, B_WAL[5])
    bench_fill(img, 6, 9, 7, 142, B_WAL[2])
    bench_fill(img, 193, 9, 194, 142, B_WAL[4])
    bench_fill(img, 198, 9, 199, 142, B_WAL[2])
    # cornisa
    bench_fill(img, 0, 0, 200, 3, B_WAL[4])
    bench_fill(img, 0, 0, 200, 1, B_WAL[6])
    bench_fill(img, 0, 2, 200, 3, B_WAL[3])
    bench_fill(img, 2, 3, 198, 9, B_WAL[3])
    bench_grain(img, 2, 3, 198, 9, [B_WAL[4]], 0.15, rng)
    for xx in range(5, 195, 6):
        bench_fill(img, xx, 6, xx + 3, 9, B_WAL[2])
        bench_put(img, xx, 6, B_WAL[4])
    bench_fill(img, 2, 3, 198, 4, B_WAL[2])
    bench_fill(img, 0, 9, 200, 10, B_WAL[5])
    bench_fill(img, 0, 10, 200, 11, B_WAL[2])
    # placa de latón con un matraz grabado
    px0, px1 = 84, 116
    bench_fill(img, px0, 1, px1, 10, B_BRASS[1])
    bench_fill(img, px0 + 1, 2, px1 - 1, 9, B_BRASS[3])
    bench_fill(img, px0 + 1, 2, px1 - 1, 3, B_BRASS[4])
    bench_fill(img, px0 + 1, 8, px1 - 1, 9, B_BRASS[2])
    flask = bench_ascii_art("""
        ..EE..
        ..EE..
        .E..E.
        E....E
        EEEEEE
        """, {'E': B_BRASS[1]})
    fh, fw = flask.shape[:2]
    m = flask[..., 3] > 0
    img[3:3 + fh, 97:97 + fw][m] = flask[m]
    for xx in [px0 + 3, px1 - 5]:
        bench_put(img, xx, 5, B_BRASS[5])
        bench_put(img, xx + 1, 5, B_BRASS[2])
    # zócalo
    bench_fill(img, 0, 136, 200, 142, B_WAL[3])
    bench_fill(img, 0, 136, 200, 137, B_WAL[6])
    bench_fill(img, 0, 137, 200, 138, B_WAL[4])
    bench_grain(img, 0, 138, 200, 141, [B_WAL[4], B_WAL[2]], 0.2, rng)
    bench_fill(img, 0, 141, 200, 142, B_WAL[2])
    bench_fill(img, 3, 142, 197, 146, B_WAL[2])
    bench_fill(img, 3, 142, 197, 143, B_WAL[1])
    for (fx0, fx1) in [(1, 15), (185, 199)]:
        bench_fill(img, fx0, 142, fx1, 150, B_WAL[3])
        bench_fill(img, fx0, 142, fx1, 143, B_WAL[4])
        bench_fill(img, fx0, 149, fx1, 150, B_WAL[1])
        bench_fill(img, fx0 + 2, 146, fx1 - 2, 147, B_WAL[4])
    # remates de latón en las esquinas
    for (cx, cy, sx, sy) in [(0, 0, 1, 1), (199, 0, -1, 1), (0, 141, 1, -1), (199, 141, -1, -1)]:
        for k in range(5):
            bench_put(img, cx + sx * k, cy, B_BRASS[4] if k < 3 else B_BRASS[3])
            bench_put(img, cx, cy + sy * k, B_BRASS[3] if k < 3 else B_BRASS[2])
        bench_put(img, cx + sx, cy + sy, B_BRASS[2])
    # hierbas secas colgando de la cornisa
    bench_herb_bundle(img, 13, 11, rng)
    bench_herb_bundle(img, 187, 11, rng, [B_HERB[0], B_WAL[2], B_WAL[3], B_WAL[4], B_WAL[5]])
    bench_inner_outline(img, B_WAL[0])
    return bench_save(img, 'bench_shelf.png')


def bench_lock():
    img = bench_ascii_art("""
        ..ooo..
        .o...o.
        .o...o.
        ooooooo
        oHHHHHo
        oHH.HHo
        oHH.HHo
        oMMMMMo
        ooooooo
        """, {'o': B_BRASS[1], 'H': B_BRASS[3], 'M': B_BRASS[2], '.': (B_WAL[0], 0)})
    img[5:7, 3] = 0
    bench_put(img, 3, 5, B_WAL[0])
    bench_put(img, 3, 6, B_WAL[0])
    return bench_save(img, 'bench_lock.png')


def bench_tag():
    W, H = 196, 22
    img = bench_canvas(W, H)
    rng = np.random.default_rng(5)
    bench_fill(img, 3, 2, W - 3, H - 2, B_PAPER[4])
    # fibras
    bench_grain(img, 4, 3, W - 4, H - 3, [B_PAPER[3], B_PAPER[5]], 0.12, rng, lmin=2, lmax=6)
    # bordes deshilachados (arriba/abajo) y extremos rasgados
    for x in range(3, W - 3):
        if rng.random() < 0.25:
            bench_put(img, x, 2, B_PAPER[3])
        if rng.random() < 0.18:
            img[2, x] = 0
        if rng.random() < 0.25:
            bench_put(img, x, H - 3, B_PAPER[3])
        if rng.random() < 0.18:
            img[H - 3, x] = 0
    for y in range(2, H - 2):
        for side in (0, 1):
            d = int(rng.integers(0, 3))
            if side == 0:
                img[y, 3:3 + d] = 0
                bench_put(img, 3 + d, y, B_PAPER[2])
            else:
                img[y, W - 3 - d:W - 3] = 0
                bench_put(img, W - 4 - d, y, B_PAPER[2])
    # borde quemado
    a = img[..., 3] > 0
    pad = np.zeros((H + 2, W + 2), bool)
    pad[1:-1, 1:-1] = a
    edge = a & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    img[edge] = (*bench_rgb(B_PAPER[1]), 255)
    # chinchetas de latón
    for x in (9, W - 11):
        bench_fill(img, x, 9, x + 3, 12, B_BRASS[2])
        bench_put(img, x, 9, B_BRASS[5])
        bench_put(img, x + 1, 9, B_BRASS[4])
        bench_put(img, x + 2, 11, B_BRASS[1])
    # sombra suave abajo
    for x in range(5, W - 5):
        if img[H - 2, x, 3] == 0:
            img[H - 2, x] = (0, 0, 0, 70)
    return bench_save(img, 'bench_tag.png')


# ------------------------------------------------------------------ el caldero grande
B_CX = 52.0
B_RIM_C = (B_CX, 12.0)
B_RIM_OUT = (42.0, 12.5)
B_RIM_IN = (35.0, 9.0)
B_LIQ_C = (B_CX, 14.2)
B_LIQ_R = (33.5, 8.2)
B_PROFILE = [(13, 37.0), (17, 40.5), (22, 44.5), (28, 47.0), (35, 48.0), (42, 47.5), (49, 45.5), (55, 42.0),
           (60, 37.0), (64, 30.5), (67, 23.0), (69, 14.0), (70, 6.0)]
CW, CH = 104, 80


def bench_half_w(y):
    if y < B_PROFILE[0][0] or y > B_PROFILE[-1][0]:
        return 0.0
    for i in range(1, len(B_PROFILE)):
        y0, w0 = B_PROFILE[i - 1]
        y1, w1 = B_PROFILE[i]
        if y <= y1:
            t = (y - y0) / (y1 - y0)
            t = t * t * (3 - 2 * t)
            return w0 + (w1 - w0) * t
    return 0.0


def bench_hole_mask():
    inner = bench_ellipse_mask(CW, CH, B_RIM_C[0], B_RIM_C[1], B_RIM_IN[0], B_RIM_IN[1])
    liq = bench_ellipse_mask(CW, CH, B_LIQ_C[0], B_LIQ_C[1], B_LIQ_R[0], B_LIQ_R[1])
    return inner & liq


def bench_cauldron(ramp, name):
    img = bench_canvas(CW, CH)
    lvl = np.full((CH, CW), -1, int)
    L = np.array([-0.55, -0.5, 0.67])
    L = L / np.linalg.norm(L)
    # cuerpo: un elipsoide de revolución cortado arriba (la boca) y un poco aplastado abajo
    BA, BB, BC = 48.0, 35.8, 35.9      # semiejes (ancho, alto) y centro y
    for y in range(13, 71):
        Y = y + 0.5 - BC
        if abs(Y) >= BB:
            continue
        w = BA * math.sqrt(1 - (Y / BB) ** 2)
        for x in range(CW):
            X = x + 0.5 - B_CX
            if abs(X) > w:
                continue
            Z = math.sqrt(max(0.0, BA * BA * (1 - (Y / BB) ** 2) - X * X))
            n = np.array([X / (BA * BA), Y / (BB * BB), Z / (BA * BA)])
            n = n / np.linalg.norm(n)
            d = float(n @ L)
            if d < -0.2:
                lv = 1
            elif d < 0.12:
                lv = 2
            elif d < 0.42:
                lv = 3
            elif d < 0.7:
                lv = 4
            else:
                lv = 5
            if d > 0.94:
                lv = 6
            lvl[y, x] = lv
    # cinturón con remaches
    for y in (29, 30):
        for x in range(CW):
            if lvl[y, x] >= 0:
                lvl[y, x] = max(1, lvl[y, x] - (2 if y == 29 else 0))
    for x in range(CW):
        if lvl[31, x] >= 0:
            lvl[31, x] = min(6, lvl[31, x] + 1)
    w30 = 48.0 * math.sqrt(1 - ((30.5 - 35.9) / 35.8) ** 2)
    for k in range(-5, 6):
        x = int(round(B_CX + k * w30 / 5.6))
        if 0 <= x < CW and lvl[30, x] >= 0:
            lvl[30, x] = min(6, lvl[30, x] + 2)
    # asas (anillas) a los lados
    for side in (-1, 1):
        hx = B_CX + side * 49.0
        ring = bench_ellipse_mask(CW, CH, hx, 30.0, 4.6, 5.6) & ~bench_ellipse_mask(CW, CH, hx, 30.0, 2.2, 3.2)
        lug = bench_ellipse_mask(CW, CH, B_CX + side * 46.5, 27.5, 2.6, 2.4)
        ys, xs = np.nonzero(ring | lug)
        for y, x in zip(ys, xs):
            lit = (x - hx) * (-1) + (30 - y) * 0.6
            lvl[y, x] = 4 if lit > 1 else (3 if lit > -1.5 else 2)
    legs = np.zeros((CH, CW), bool)
    # patas
    for (lx, ly0, ly1, wd) in [(B_CX - 27, 63, 77, 7), (B_CX + 27, 63, 77, 7), (B_CX, 66, 79, 8)]:
        for y in range(ly0, ly1):
            t = (y - ly0) / max(1, ly1 - ly0 - 1)
            hw = wd / 2.0 * (1.0 - 0.25 * math.sin(t * math.pi)) + (1.0 if y >= ly1 - 2 else 0.0)
            for x in range(int(lx - hw), int(math.ceil(lx + hw))):
                if 0 <= x < CW:
                    rel = (x + 0.5 - (lx - hw)) / (2 * hw)
                    lvl[y, x] = 4 if rel < 0.3 else (3 if rel < 0.65 else 2)
                    legs[y, x] = True
            if y == ly1 - 1:
                for x in range(int(lx - hw), int(math.ceil(lx + hw))):
                    if 0 <= x < CW:
                        lvl[y, x] = 1
    # boca: borde de arriba, banda del frente, pared interior del fondo
    out0 = bench_ellipse_mask(CW, CH, B_RIM_C[0], B_RIM_C[1], B_RIM_OUT[0], B_RIM_OUT[1])
    band = np.zeros_like(out0)
    for k in range(1, 4):
        band |= bench_ellipse_mask(CW, CH, B_RIM_C[0], B_RIM_C[1] + k, B_RIM_OUT[0], B_RIM_OUT[1])
    band &= ~out0
    inner = bench_ellipse_mask(CW, CH, B_RIM_C[0], B_RIM_C[1], B_RIM_IN[0], B_RIM_IN[1])
    hole = bench_hole_mask()
    ys, xs = np.nonzero(band)
    for y, x in zip(ys, xs):
        rel = (x + 0.5 - (B_CX - B_RIM_OUT[0])) / (2 * B_RIM_OUT[0])
        lvl[y, x] = 4 if rel < 0.35 else (3 if rel < 0.7 else 2)
    ys, xs = np.nonzero(out0 & ~inner)
    for y, x in zip(ys, xs):
        u = (x + 0.5 - B_RIM_C[0]) / B_RIM_OUT[0]
        v = (y + 0.5 - B_RIM_C[1]) / B_RIM_OUT[1]
        ang = math.atan2(v, u)
        b = math.cos(ang - math.radians(150))   # la luz viene de la izquierda y de delante
        lvl[y, x] = 6 if b > 0.75 else (5 if b > 0.25 else (4 if b > -0.4 else 3))
        # el canto exterior delantero un poco más oscuro (redondea el labio)
        if v > 0.55 and not out0[min(CH - 1, y + 1), x]:
            lvl[y, x] = max(2, lvl[y, x] - 1)
    ys, xs = np.nonzero(inner & ~hole)
    for y, x in zip(ys, xs):
        v = (y + 0.5 - B_RIM_C[1]) / B_RIM_IN[1]
        lvl[y, x] = 0 if v < -0.75 else 1
    # colorear
    for y in range(CH):
        for x in range(CW):
            lv = lvl[y, x]
            if lv < 0 or hole[y, x]:
                continue
            c = bench_rgb(ramp[lv])
            # reflejo del fuego en la panza de abajo
            if y > 50 and lv > 0 and not legs[y, x]:
                g = min(1.0, (y - 50) / 20.0) * 0.5
                c = bench_mix(c, B_FIRE[2] if lv >= 3 else B_FIRE[1], g * (0.5 + 0.5 * (1 - abs(x - B_CX) / 48.0)))
            img[y, x] = (*c, 255)
    bench_outline(img, ramp[0], keep=hole)
    img[hole] = 0
    return bench_save(img, name)


def bench_liquid():
    img = bench_canvas(CW, CH)
    hole = bench_hole_mask()
    ys, xs = np.nonzero(hole)
    for y, x in zip(ys, xs):
        u = (x + 0.5 - B_LIQ_C[0]) / B_LIQ_R[0]
        v = (y + 0.5 - B_LIQ_C[1]) / B_LIQ_R[1]
        d = math.sqrt(u * u + v * v)
        val = 196
        if v > 0.35:
            val = 168
        if v > 0.7:
            val = 148
        if v < -0.45 and d > 0.7:
            val = 226
        if abs(d - 0.62) < 0.07 and u < 0.1 and v < 0.4:
            val = 214
        img[y, x] = (val, val, val, 255)
    # destellos
    for (x, y) in [(36, 11), (37, 11), (38, 11), (40, 12), (33, 12), (64, 17), (65, 17)]:
        if hole[y, x]:
            img[y, x] = (250, 250, 250, 255)
    return bench_save(img, 'bench_liquid.png')


def bench_bubbles():
    f0 = bench_ascii_art("""
        .......
        .......
        ...a...
        ..aWa..
        ...a...
        .......
        .......
        """, {'a': ((200, 200, 200), 255), 'W': ((255, 255, 255), 255)})
    f1 = bench_ascii_art("""
        .......
        ..aaa..
        .aW.ba.
        .a...a.
        .ab..a.
        ..aaa..
        .......
        """, {'a': ((225, 225, 225), 255), 'W': ((255, 255, 255), 255), 'b': ((210, 210, 210), 140)})
    f1[2:5, 2:5][f1[2:5, 2:5, 3] == 0] = (200, 200, 200, 70)
    f2 = bench_ascii_art("""
        .a...a.
        .......
        a.....a
        .......
        .......
        .a...a.
        .......
        """, {'a': ((235, 235, 235), 255)})
    return bench_save(np.concatenate([f0, f1, f2], axis=1), 'bench_bubble.png')


def bench_flame_layer(w, h, tongues, scale, base_y):
    m = np.zeros((h, w), bool)
    for (tx, bw, th, sway) in tongues:
        bw2 = bw * scale
        th2 = th * scale
        for yy in range(h):
            t = (base_y - yy) / max(0.001, th2)
            if t < 0 or t > 1:
                continue
            hw = bw2 / 2.0 * (1 - t) ** 0.75 * (1.0 + 0.25 * math.sin(t * math.pi))
            cxx = tx + sway * t * t
            x0 = int(round(cxx - hw))
            x1 = int(round(cxx + hw))
            m[yy, max(0, x0):min(w, x1 + 1)] = True
    return m


def bench_fire():
    W, H = 64, 30
    frames = []
    rng = np.random.default_rng(3)
    base = [(10, 12, 10, 0), (20, 13, 14, 0), (32, 16, 18, 0), (44, 13, 13, 0), (54, 12, 9, 0)]
    for f in range(4):
        img = bench_canvas(W, H)
        tongues = []
        for i, (tx, bw, th, _) in enumerate(base):
            ph = f * 1.7 + i * 2.1
            tongues.append((tx + math.sin(ph) * 0.8, bw, th * (0.86 + 0.18 * math.sin(ph * 1.3 + 0.5)), 2.6 * math.sin(ph + 1.0)))
        by = 25
        layers = [(1.0, B_FIRE[1]), (0.78, B_FIRE[2]), (0.56, B_FIRE[3]), (0.36, B_FIRE[4]), (0.18, B_FIRE[5])]
        for sc, col in layers:
            m = bench_flame_layer(W, H, tongues, sc, by)
            img[m] = (*bench_rgb(col), 255)
        bench_outline(img, B_FIRE[0])
        # brasas que saltan
        for k in range(3):
            ex = int(rng.integers(8, W - 8))
            ey = int(rng.integers(1, 9))
            bench_put(img, ex, ey, B_FIRE[4])
        # troncos
        for (x0, x1, y0, col) in [(9, 55, 24, B_WAL[3]), (4, 60, 26, B_WAL[4])]:
            bench_fill(img, x0, y0, x1, y0 + 4, col)
            bench_fill(img, x0, y0, x1, y0 + 1, bench_mix(col, B_FIRE[3], 0.35))
            bench_fill(img, x0, y0 + 3, x1, y0 + 4, B_WAL[1])
            for xx in range(x0 + 3, x1 - 3, 7):
                bench_put(img, xx + (f % 2), y0 + 2, B_FIRE[3])
                bench_put(img, xx + 1 + (f % 2), y0 + 2, B_FIRE[2])
            for ex in (x0, x1 - 2):
                bench_fill(img, ex, y0, ex + 2, y0 + 4, B_PAPER[2])
                bench_put(img, ex + (1 if ex == x0 else 0), y0 + 1, B_PAPER[1])
        bench_outline(img, B_WAL[0])
        frames.append(img)
    return bench_save(np.concatenate(frames, axis=1), 'bench_fire.png')


def bench_hearth():
    W, H = 120, 18
    img = bench_canvas(W, H)
    rng = np.random.default_rng(9)
    # losa de arriba (piedra) y frente de ladrillos
    bench_fill(img, 0, 0, W, 4, '#6b6560')
    bench_fill(img, 0, 0, W, 1, '#9a928a')
    bench_fill(img, 0, 3, W, 4, '#4a4440')
    bench_grain(img, 1, 1, W - 1, 3, ['#7d766f', '#5d5752'], 0.3, rng, lmin=2, lmax=6)
    for row in range(3):
        y0 = 4 + row * 4 + (1 if row else 0)
        off = 0 if row % 2 == 0 else 6
        for x0 in range(-off, W, 12):
            c = B_BRICK[2 + int(rng.integers(0, 3))]
            bench_fill(img, x0 + 1, y0 + 1, x0 + 12, y0 + 4, c)
            bench_fill(img, x0 + 1, y0 + 1, x0 + 12, y0 + 2, bench_mix(c, B_BRICK[5], 0.4))
        bench_fill(img, 0, y0, W, y0 + 1, B_BRICK[0])
    # el fuego ilumina el centro de la losa
    for x in range(W):
        g = max(0.0, 1.0 - abs(x - W / 2) / 34.0)
        for y in range(0, 4):
            if img[y, x, 3]:
                img[y, x, :3] = bench_mix(img[y, x, :3], B_FIRE[3], 0.45 * g * (1.0 - y / 5.0))
    bench_inner_outline(img, B_BRICK[0])
    return bench_save(img, 'bench_hearth.png')


def bench_ladle():
    rows = [".kKk.", "kHHMk", "kHMDk", ".kMk."] + [".HMD."] * 18 + [".HMD.", ".MDD."] * 2
    img = bench_ascii_art("\n".join(rows), {'k': B_WAL[2], 'K': B_WAL[1], 'H': B_WAL[6], 'M': B_WAL[5], 'D': B_WAL[4]})
    pad = bench_canvas(img.shape[1] + 2, img.shape[0] + 2)
    pad[1:-1, 1:-1] = img
    bench_outline(pad, B_WAL[0])
    return bench_save(pad, 'bench_ladle.png')


def bench_slot(empty):
    W = 21
    img = bench_canvas(W, W)
    outer = bench_ellipse_mask(W, W, 10.5, 10.5, 10.0, 10.0)
    inner = bench_ellipse_mask(W, W, 10.5, 10.5, 7.8, 7.8)
    ring = outer & ~inner
    ys, xs = np.nonzero(ring)
    for y, x in zip(ys, xs):
        ang = math.atan2(y + 0.5 - 10.5, x + 0.5 - 10.5)
        b = math.cos(ang - math.radians(225))
        c = B_BRASS[4] if b > 0.5 else (B_BRASS[3] if b > -0.3 else B_BRASS[2])
        if empty:
            c = bench_mix(c, '#3b2f52', 0.55)
            if (int(math.degrees(ang) + 360) // 20) % 2 == 0 and False:
                continue
        img[y, x] = (*bench_rgb(c), 255)
    ys, xs = np.nonzero(inner)
    for y, x in zip(ys, xs):
        img[y, x] = (*bench_rgb(bench_mix('#1a1426', '#3b2f52', 0.3 if empty else 0.15)), 200 if empty else 235)
    bench_outline(img, B_WAL[0])
    return bench_save(img, 'bench_slot_empty.png' if empty else 'bench_slot.png')


# ------------------------------------------------------------------ tubos de ensayo (las esencias)
B_TUBE_X = [13, 31, 49, 67, 85]
B_TUBE_TOP = 12      # interior visible desde aquí (debajo del travesaño)
B_TUBE_BOT = 43      # fondo del interior


def bench_rack():
    W, H = 98, 60
    img = bench_canvas(W, H)
    rng = np.random.default_rng(4)
    glass_l = ((223, 243, 247), 230)
    glass_r = ((150, 180, 192), 220)
    for cx in B_TUBE_X:
        # paredes
        for y in range(3, B_TUBE_BOT - 1):
            bench_put(img, cx - 4, y, *glass_l)
            bench_put(img, cx + 4, y, *glass_r)
        # fondo redondeado
        bench_put(img, cx - 4, B_TUBE_BOT - 1, *glass_l)
        bench_put(img, cx - 3, B_TUBE_BOT, *glass_l)
        bench_put(img, cx - 2, B_TUBE_BOT + 1, *glass_l)
        for x in range(cx - 1, cx + 2):
            bench_put(img, x, B_TUBE_BOT + 1, *glass_r)
        bench_put(img, cx + 2, B_TUBE_BOT + 1, *glass_r)
        bench_put(img, cx + 3, B_TUBE_BOT, *glass_r)
        bench_put(img, cx + 4, B_TUBE_BOT - 1, *glass_r)
        # boca
        for x in range(cx - 5, cx + 6):
            bench_put(img, x, 2, (240, 250, 252), 240)
        bench_put(img, cx - 5, 3, *glass_l)
        bench_put(img, cx + 5, 3, *glass_r)
        # interior: un velo y un brillo vertical
        for y in range(3, B_TUBE_BOT + 1):
            for x in range(cx - 3, cx + 4):
                if img[y, x, 3] == 0 and not (y == B_TUBE_BOT and abs(x - cx) > 2):
                    img[y, x] = (255, 255, 255, 26)
            if 14 <= y <= B_TUBE_BOT - 6:
                bench_put(img, cx - 2, y, (255, 255, 255), 95)
    # travesaño (sujeta los tubos)
    bench_fill(img, 1, 6, W - 1, 11, B_WAL[3])
    bench_fill(img, 1, 6, W - 1, 7, B_WAL[5])
    bench_fill(img, 1, 10, W - 1, 11, B_WAL[2])
    bench_grain(img, 2, 7, W - 2, 10, [B_WAL[4], B_WAL[2]], 0.25, rng)
    for cx in B_TUBE_X:
        bench_fill(img, cx - 5, 7, cx + 6, 10, B_WAL[1])
        bench_fill(img, cx - 4, 8, cx + 5, 10, (60, 70, 80))
        for x in range(cx - 4, cx + 5):
            bench_put(img, x, 8, (205, 225, 232), 230)
    # postes y base
    for x0 in (0, W - 4):
        bench_fill(img, x0, 6, x0 + 4, 46, B_WAL[3])
        bench_fill(img, x0, 6, x0 + 1, 46, B_WAL[5])
        bench_fill(img, x0 + 3, 6, x0 + 4, 46, B_WAL[2])
    bench_fill(img, 0, 44, W, 47, B_WAL[5])
    bench_fill(img, 0, 44, W, 45, B_WAL[6])
    bench_fill(img, 0, 47, W, 60, B_WAL[3])
    bench_grain(img, 0, 48, W, 59, [B_WAL[4], B_WAL[2]], 0.2, rng)
    bench_fill(img, 0, 59, W, 60, B_WAL[1])
    # medallones para los iconos de esencia
    for cx in B_TUBE_X:
        m = bench_ellipse_mask(W, H, cx + 0.5, 53.5, 6.6, 6.0)
        ys, xs = np.nonzero(m)
        for y, x in zip(ys, xs):
            img[y, x] = (*bench_rgb(B_WAL[1]), 255)
        ys, xs = np.nonzero(m & ~bench_ellipse_mask(W, H, cx + 0.5, 53.5, 5.6, 5.0))
        for y, x in zip(ys, xs):
            img[y, x] = (*bench_rgb(B_BRASS[2] if y < 53 else B_BRASS[1]), 255)
    bench_inner_outline(img, B_WAL[0])
    return bench_save(img, 'bench_rack.png')


# ------------------------------------------------------------------ iconos de esencia (11x11)
def bench_ess_icons():
    icons = {}
    icons['fuego'] = bench_ascii_art("""
        .....O.....
        ....ORO....
        ....ORRO...
        ...ORoRO.O.
        ..ORooRO.RO
        ..ORoYoRRO.
        .ORoYYYoRO.
        .ORoYWYoRO.
        .ORooYooRO.
        ..ORRooRO..
        ...OOOOO...
        """, {'O': '#5a1808', 'R': '#d8481e', 'o': '#f58a2a', 'Y': '#ffd24a', 'W': '#fff2b0'})
    icons['escarcha'] = bench_ascii_art("""
        .....O.....
        ..O.OWO.O..
        .OWOOWOOWO.
        ..OWOWOWO..
        .OOOWBWOOO.
        OWWWBBBWWWO
        .OOOWBWOOO.
        ..OWOWOWO..
        .OWOOWOOWO.
        ..O.OWO.O..
        .....O.....
        """, {'O': '#1d4560', 'W': '#e8f8ff', 'B': '#7fd4ff'})
    icons['vida'] = bench_ascii_art("""
        ......OOOO.
        ....OOLLGO.
        ...OLLGGGO.
        ..OLLGLGGO.
        ..OLGLGGgO.
        .OLGLGGgO..
        .OGLGGgO...
        .OGGggO....
        .OOgOO.....
        .OO........
        O..........
        """, {'O': '#1f3d1c', 'L': '#bff0a0', 'G': '#7ee08a', 'g': '#3f9a4e'})
    icons['sombra'] = bench_ascii_art("""
        ...OOOO....
        ..OLVVO....
        .OLVVO...O.
        OLVVO...OSO
        OLVO.....O.
        OLVO.......
        OLVVO......
        OLVVVO..O..
        .OLVVVOOVO.
        ..OOVVVVO..
        ....OOOO...
        """, {'O': '#2a1650', 'L': '#e2d0ff', 'V': '#b48cff', 'S': '#fff2c0'})
    icons['luz'] = bench_ascii_art("""
        .....O.....
        .O..OYO..O.
        OYO..O..OYO
        .O.OOOOO.O.
        ...OWWYYO..
        OO.OWYYYO.OO
        ...OYYYdO..
        .O.OOOOO.O.
        OYO..O..OYO
        .O..OYO..O.
        .....O.....
        """, {'O': '#6a4808', 'Y': '#ffd84d', 'W': '#fff6c8', 'd': '#e0a82a'})
    # el sol tiene una fila de 12: recortar
    icons['luz'] = icons['luz'][:, :11]
    for k, im in icons.items():
        bench_save(im, f'ess_{k}.png')
    return icons


# ------------------------------------------------------------------ botones de madera (9 cortes, ya a 3x)
def bench_wood_button(kind):
    """Botón del banco a tamaño final (30x26 px de arte = 120x104 a 4x): tabla de nogal, remaches arriba."""
    W, H = 30, 26
    img = bench_canvas(W, H)
    rng = np.random.default_rng(21)
    base, top, bot, border = B_WAL[3], B_WAL[5], B_WAL[2], B_WAL[0]
    if kind == 'hover':
        base, top, bot = B_WAL[4], B_WAL[6], B_WAL[3]
    elif kind == 'pressed':
        base, top, bot = B_WAL[2], B_WAL[1], B_WAL[4]
    elif kind == 'disabled':
        base, top, bot = '#4a4340', '#5f5752', '#3a3431'
    bench_fill(img, 1, 1, W - 1, H - 1, base)
    bench_grain(img, 2, 3, W - 2, H - 3, [bench_mix(base, top, 0.5), bench_mix(base, bot, 0.5)], 0.3, rng, lmin=3, lmax=9)
    bench_fill(img, 1, 1, W - 1, 2, top)
    bench_fill(img, 1, 2, W - 1, 3, bench_mix(base, top, 0.5))
    bench_fill(img, 1, H - 2, W - 1, H - 1, bot)
    bench_fill(img, 1, H - 3, W - 1, H - 2, bench_mix(base, bot, 0.5))
    # marco oscuro con esquinas redondeadas
    bench_fill(img, 1, 0, W - 1, 1, border)
    bench_fill(img, 1, H - 1, W - 1, H, border)
    bench_fill(img, 0, 1, 1, H - 1, border)
    bench_fill(img, W - 1, 1, W, H - 1, border)
    if kind == 'hover':
        bench_fill(img, 1, 1, W - 1, 2, B_BRASS[4])
    if kind != 'disabled':
        for (x, y) in [(3, 3), (W - 5, 3)]:
            bench_brass_dot(img, x, y)
    if kind == 'primary':
        for (x0, y0, x1, y1) in [(1, 1, W - 1, 2), (1, H - 2, W - 1, H - 1), (1, 1, 2, H - 1), (W - 2, 1, W - 1, H - 1)]:
            bench_fill(img, x0, y0, x1, y1, B_BRASS[4])
        for (x, y) in [(1, 1), (W - 2, 1), (1, H - 2), (W - 2, H - 2)]:
            bench_put(img, x, y, B_BRASS[5])
    return bench_save(img, f'bench_btn_{kind}.png')


def bench_action_icons():
    codes = {'O': B_WAL[0], 'H': B_WAL[6], 'M': B_WAL[5], 'D': B_WAL[4], 'S': B_WAL[3],
             'g': '#c7e8ef', 'G': '#8fb7c2', 'k': B_BRASS[3], 'K': B_BRASS[1],
             'P': '#9a6ae8', 'p': '#c6a6ff', 'w': '#ffffff', 'i': '#2a2140', 'I': '#4a3a78',
             'q': B_PAPER[5], 'Q': B_PAPER[2], 'L': '#7fd4ff', 'l': '#cfefff', 'c': '#3d3e4c', 'C': '#626578', 'x': '#24232d'}
    icons = {
        'stir': """
            ..........OO....
            .........OHMO...
            ........OHMO....
            .......OHMO.....
            ......OHMO......
            .....OHMO.......
            ....OHMO........
            ...OHMO.........
            ..OMMSO.........
            .OMMSSO.........
            OMHMMSO..pp.....
            OMMMSO..p..p....
            .OSSO..p....p...
            ..OO...p.pp.p...
            ........p..p....
            .........pp.....
            """,
        'bottle': """
            ......OOOO......
            ......OkkO......
            ......OKKO......
            ......OggO......
            ......OggO......
            .....OggGGO.....
            ....OgPPPPGO....
            ...OgPpwpPPGO...
            ..OgPpwPPPPPGO..
            ..OgPpPPPPPPGO..
            ..OgPPPPPPPPGO..
            ..OgPPPPPPPPGO..
            ...OGPPPPPPGO...
            ....OGGGGGGO....
            .....OOOOOO.....
            ................
            """,
        'empty': """
            ................
            .OOOOOOOOO......
            OcCCCCCCCCO.....
            OxccccccccCO....
            .OxcccccccCO....
            .OxcccccccCO....
            ..OxccccccCOOO..
            ..OxcccccCCOLLO.
            ...OxccccCOLlLO.
            ....OxxxxOLLLO..
            .....OOOOOLLO...
            ..........OLO...
            ..........OLLO..
            .........OLlLO..
            ..........OLO...
            ...........O....
            """,
        'ink': """
            ............OO..
            ...........OqqO.
            ..........OqQqO.
            .........OqQqO..
            ........OqQqO...
            .......OqQqO....
            ......OqQqO.....
            .....OQQqO......
            ..OOOOQOOOOO....
            .OiIIOQOIIIiO...
            OiIIIIOIIIIIiO..
            OiIwIIIIIIIIiO..
            OiIIIIIIIIIIiO..
            OiiIIIIIIIIiiO..
            .OiiiiiiiiiiO...
            ..OOOOOOOOOO....
            """,
        'close': """
            ..........
            .OO....OO.
            OwwO..OwwO
            OwwwOOwwwO
            .OwwwwwwO.
            ..OwwwwO..
            .OwwwwwwO.
            OwwwOOwwwO
            OwwO..OwwO
            .OO....OO.
            """,
    }
    out = {}
    for k, art in icons.items():
        im = bench_ascii_art(art, codes)
        out[k] = bench_save(im, f'act_{k}.png')
    return out


def bench_close_seal(hover):
    W = 18
    img = bench_canvas(W, W)
    m = bench_ellipse_mask(W, W, 9, 9, 8.6, 8.6)
    rng = np.random.default_rng(2)
    ys, xs = np.nonzero(m)
    for y, x in zip(ys, xs):
        ang = math.atan2(y + 0.5 - 9, x + 0.5 - 9)
        b = math.cos(ang - math.radians(225))
        c = B_WAX[3] if b > 0.4 else (B_WAX[2] if b > -0.4 else B_WAX[1])
        if hover:
            c = bench_mix(c, B_WAX[4], 0.35)
        img[y, x] = (*bench_rgb(c), 255)
    # borde irregular de cera
    for k in range(10):
        ang = rng.random() * math.tau
        x = int(9 + math.cos(ang) * 9.2)
        y = int(9 + math.sin(ang) * 9.2)
        bench_put(img, x, y, B_WAX[2])
    ring = bench_ellipse_mask(W, W, 9, 9, 6.0, 6.0) & ~bench_ellipse_mask(W, W, 9, 9, 5.0, 5.0)
    ys, xs = np.nonzero(ring)
    for y, x in zip(ys, xs):
        img[y, x] = (*bench_rgb(B_WAX[1]), 255)
    cross = [(6, 6), (7, 7), (8, 8), (9, 9), (10, 10), (11, 11), (11, 6), (10, 7), (9, 8), (8, 9), (7, 10), (6, 11)]
    for (x, y) in cross:
        bench_put(img, x, y, B_PAPER[5])
        bench_put(img, x + 1, y, B_PAPER[3])
    bench_outline(img, B_WAX[0])
    return bench_save(img, 'bench_close_hover.png' if hover else 'bench_close.png')



# ------------------------------------------------------------------ el ticket del pedido (papel clavado arriba)
def bench_ticket_paper():
    """Papel para 9 cortes (márgenes de 7 px de arte), ya a 3x. Bordes deshilachados y un poco quemados."""
    W, H = 36, 32
    img = bench_canvas(W, H)
    rng = np.random.default_rng(13)
    bench_fill(img, 1, 1, W - 1, H - 2, B_PAPER[4])
    bench_grain(img, 2, 2, W - 2, H - 3, [B_PAPER[3], B_PAPER[5]], 0.14, rng, lmin=2, lmax=5)
    # borde quemado y deshilachado
    for x in range(1, W - 1):
        for (y, inner) in ((1, 2), (H - 3, H - 4)):
            bench_put(img, x, y, B_PAPER[2] if rng.random() < 0.7 else B_PAPER[1])
            if rng.random() < 0.3:
                bench_put(img, x, inner, B_PAPER[3])
            if rng.random() < 0.22:
                img[y, x] = 0
    for y in range(1, H - 2):
        for (x, inner) in ((1, 2), (W - 2, W - 3)):
            bench_put(img, x, y, B_PAPER[2] if rng.random() < 0.7 else B_PAPER[1])
            if rng.random() < 0.3:
                bench_put(img, inner, y, B_PAPER[3])
            if rng.random() < 0.22:
                img[y, x] = 0
    # sombrita abajo
    for x in range(3, W - 1):
        if img[H - 2, x, 3] == 0:
            img[H - 2, x] = (20, 12, 6, 90)
        img[H - 1, x] = (20, 12, 6, 40)
    return bench_save(bench_up(img, 3), 'ticket_paper.png')


def bench_ticket_pin():
    img = bench_ascii_art("""
        ..OOO..
        .OwrrRO
        OwwrrRO
        OrrrrRO
        ORrrRRO
        .ORRRO.
        ..OOO..
        """, {'O': B_WAX[0], 'w': B_WAX[4], 'r': B_WAX[3], 'R': B_WAX[2]})
    out = bench_canvas(9, 9)
    out[0:7, 0:7] = img
    for (x, y) in [(7, 3), (7, 4), (6, 6), (5, 7), (4, 7), (7, 5), (6, 7)]:
        if out[y, x, 3] == 0:
            out[y, x] = (20, 12, 6, 80)
    return bench_save(out, 'ticket_pin.png')


def bench_ticket_frame():
    W = 44
    img = bench_canvas(W, W)
    bench_fill(img, 0, 0, W, W, B_BRASS[1])
    bench_fill(img, 1, 1, W - 1, W - 1, B_BRASS[3])
    bench_fill(img, 1, 1, W - 1, 2, B_BRASS[5])
    bench_fill(img, 1, 1, 2, W - 1, B_BRASS[4])
    bench_fill(img, 1, W - 2, W - 1, W - 1, B_BRASS[2])
    bench_fill(img, W - 2, 1, W - 1, W - 1, B_BRASS[2])
    bench_fill(img, 3, 3, W - 3, W - 3, B_BRASS[0])
    bench_fill(img, 4, 4, W - 4, W - 4, B_PAPER[2])
    bench_fill(img, 4, 4, W - 4, 12, bench_mix(B_PAPER[2], B_PAPER[3], 0.5))
    for (x, y) in [(0, 0), (W - 1, 0), (0, W - 1), (W - 1, W - 1)]:
        img[y, x] = 0
    return bench_save(img, 'ticket_frame.png')


# ------------------------------------------------------------------ iconos del HUD (16x16) y horas del día (11x11)
def bench_hud_icons():
    codes = {'O': '#1c1424', 'R': B_WAX[2], 'r': B_WAX[3], 'w': B_WAX[4], 'q': B_PAPER[5], 'Q': B_PAPER[3],
             'k': B_BRASS[4], 'K': B_BRASS[2], 'B': B_WAL[3], 'b': B_WAL[5], 'd': B_WAL[2], 'G': B_HERB[3], 'g': B_HERB[1],
             'a': '#e0503a', 'A': '#a8321e', 'y': '#ffd84d', 'f': '#f5ecd6', 'F': '#9fb8c2'}
    arts = {
        'book': """
            ................
            ..OOOOOOOOOOO...
            .ORrrrrrrrrrRO..
            .ORrrrrkkrrrRqO.
            .ORrrrkKKkrrRqO.
            .ORrrrrkkrrrRqO.
            .ORrrrkqqkrrRqO.
            .ORrrkqQQqkrRqO.
            .ORrrkqQQqkrRqO.
            .ORrrrkkkkrrRqO.
            .ORrrrrrrrrrRqO.
            .ORRRRRRRRRRRqO.
            .ORkkkkkkkkkRqO.
            .OOOOOOOOOOOOQO.
            ..OqqqqqqqqqqqO.
            ...OOOOOOOOOOO..
            """,
        'journal': """
            ..........OO....
            .........OfFO...
            ..OOOOOOOfFO....
            .ObbbbbbOfFOO...
            .ObBBBBBOFOqO...
            .ObBBBBOFOBqO...
            .ObBBBBOOBBqO...
            .ObBkkkkkkBqO...
            .ObBkKKKKkBqO...
            .ObBkkkkkkBqO...
            .ObBBBBBBBBqO...
            .ObBBBBBBRBqO...
            .ObBBBBBBRBqO...
            .OddddddRrRqO...
            ..OOOOOOOROOO...
            ........O.......
            """,
        'market': """
            ................
            .....OOOOOO.....
            ....OK....KO....
            ...OK......KO...
            ...OK..OO..KO...
            ..OOGgOaaOyyOO..
            .OGGgOaawAOyyKO.
            .OkkkkkkkkkkkkO.
            .OKbKbKbKbKbKKO.
            ..ObKbKbKbKbKO..
            ..OKbKbKbKbKKO..
            ..ObKbKbKbKbKO..
            ...OKbKbKbKbO...
            ...OOOOOOOOOO...
            ................
            ................
            """,
        'settings': """
            ......OOOO......
            ......OkkO......
            ..OO..OkkO..OO..
            .OkkOOkkkkOOkkO.
            .OkkkkkKKkkkkkO.
            ..OkkKKOOKKkkO..
            OOOkKO....OKkOOO
            OkkkKO....OKkkkO
            OkkkKO....OKkkkO
            OOOkKO....OKkOOO
            ..OkkKKOOKKkkO..
            .OkkkkkKKkkkkkO.
            .OkkOOkkkkOOkkO.
            ..OO..OkkO..OO..
            ......OkkO......
            ......OOOO......
            """,
    }
    for k, art in arts.items():
        bench_save(bench_ascii_art(art, codes), f'hud_{k}.png')
    tcodes = {'O': '#2a1a10', 'Y': '#ffd84d', 'W': '#fff6c8', 'o': '#ff9a3a', 'r': '#e0503a', 'h': '#7a5a8a',
              'c': '#f5ecd6', 'C': '#a99fbf', 'V': '#b48cff', 'L': '#e2d0ff', 'S': '#fff2c0', 'N': '#2a1650'}
    tods = {
        'manana': """
            .....Y.....
            ..Y.....Y..
            ....OOO....
            ...OWYYO...
            .Y.OYYYO.Y.
            ..OYYYYYO..
            hhhhhhhhhhh
            ...........
            ..hh...hh..
            ...........
            ...........
            """,
        'mediodia': """
            .....Y.....
            .Y...Y...Y.
            ...OOOOO...
            ..OWWYYYO..
            ..OWYYYYO..
            YYOYYYYYOYY
            ..OYYYYoO..
            ..OYYYooO..
            ...OOOOO...
            .Y...Y...Y.
            .....Y.....
            """,
        'tarde': """
            ...Y.......
            .Y.OOO.Y...
            ..OWYYO....
            YOYYYYYO...
            ..OYYOOOOO.
            .Y.OOcccccO
            ...OccccccO
            ..OcccccccO
            ..OCCCCCCO.
            ...OOOOOO..
            ...........
            """,
        'atardecer': """
            ...........
            ...........
            ..o..o..o..
            ....OOO....
            ..OoooooO..
            .OooooooooO
            Orrrrrrrrrr
            hhhhhhhhhhh
            ..hh...hh..
            ...........
            ...........
            """,
        'noche': """
            ...NNNN....
            ..NLVVN..S.
            .NLVVN..SSS
            NLVVN....S.
            NLVN.......
            NLVN.......
            NLVVN......
            NLVVVN..N..
            .NLVVVNNVN.
            ..NNVVVVN..
            ....NNNN...
            """,
    }
    for k, art in tods.items():
        bench_save(bench_ascii_art(art, tcodes), f'tod_{k}.png')


# ------------------------------------------------------------------ el estante de pociones del HUD (6 o 12)
B_SHELF_SLOT_X = [15, 35, 55, 75, 95, 115]


def bench_hud_shelf(rows):
    W = 130
    H = 7 + rows * 31 + 3
    img = bench_canvas(W, H)
    rng = np.random.default_rng(31 + rows)
    # fondo de tablas
    x = 5
    i = 0
    while x < W - 5:
        x1 = min(x + 11, W - 5)
        base = B_WAL[1] if i % 2 == 0 else bench_mix(B_WAL[1], B_WAL[2], 0.3)
        bench_fill(img, x, 6, x1, H - 3, base)
        bench_grain(img, x + 1, 6, x1, H - 3, [bench_mix(base, B_WAL[2], 0.6), bench_mix(base, B_WAL[0], 0.4)], 0.14, rng, horiz=False, lmin=3, lmax=10)
        bench_fill(img, x, 6, x + 1, H - 3, B_WAL[0])
        x = x1
        i += 1
    for k, a in enumerate([0.5, 0.3, 0.15]):
        bench_shade(img, 5, 7 + k, W - 5, 8 + k, a)
    for r in range(rows):
        top = 7 + r * 31 + 22
        # fantasma de botella en cada hueco (se ve cuando está vacío)
        for cx in B_SHELF_SLOT_X:
            ghost = [(cx - 1, top - 14), (cx, top - 14), (cx - 1, top - 13), (cx, top - 13),
                     (cx - 3, top - 10), (cx + 2, top - 10), (cx - 4, top - 7), (cx + 3, top - 7),
                     (cx - 4, top - 4), (cx + 3, top - 4), (cx - 3, top - 2), (cx + 2, top - 2),
                     (cx - 1, top - 1), (cx, top - 1)]
            for (gx, gy) in ghost:
                bench_put(img, gx, gy, bench_mix(B_WAL[1], '#8a7aa8', 0.35))
        for k, a in enumerate([0.5, 0.3]):
            bench_shade(img, 5, top + 9 + k, W - 5, top + 10 + k, a)
        bench_fill(img, 3, top, W - 3, top + 1, B_WAL[6])
        bench_fill(img, 3, top + 1, W - 3, top + 2, B_WAL[5])
        bench_fill(img, 3, top + 2, W - 3, top + 9, B_WAL[3])
        bench_grain(img, 3, top + 3, W - 3, top + 8, [B_WAL[4], B_WAL[2]], 0.2, rng)
        bench_fill(img, 3, top + 2, W - 3, top + 3, B_WAL[4])
        bench_fill(img, 3, top + 8, W - 3, top + 9, B_WAL[2])
    # postes
    for (x0, x1) in [(0, 5), (W - 5, W)]:
        bench_fill(img, x0, 4, x1, H - 2, B_WAL[3])
        bench_grain(img, x0 + 1, 4, x1 - 1, H - 2, [B_WAL[4], B_WAL[2]], 0.3, rng, horiz=False, lmin=3, lmax=8)
    bench_fill(img, 1, 4, 2, H - 2, B_WAL[5])
    bench_fill(img, 4, 4, 5, H - 2, B_WAL[2])
    bench_fill(img, W - 5, 4, W - 4, H - 2, B_WAL[4])
    bench_fill(img, W - 2, 4, W - 1, H - 2, B_WAL[2])
    # cornisa con la plaquita de latón (el número va encima, en el juego)
    bench_fill(img, 0, 0, W, 6, B_WAL[3])
    bench_fill(img, 0, 0, W, 1, B_WAL[6])
    bench_fill(img, 0, 1, W, 2, B_WAL[4])
    bench_fill(img, 0, 5, W, 6, B_WAL[2])
    for xx in range(3, W - 3, 5):
        bench_put(img, xx, 3, B_WAL[2])
        bench_put(img, xx + 1, 3, B_WAL[2])
    px0, px1 = W // 2 - 13, W // 2 + 13
    bench_fill(img, px0, 0, px1, 7, B_BRASS[1])
    bench_fill(img, px0 + 1, 1, px1 - 1, 6, B_BRASS[3])
    bench_fill(img, px0 + 1, 1, px1 - 1, 2, B_BRASS[4])
    bench_fill(img, px0 + 1, 5, px1 - 1, 6, B_BRASS[2])
    # zócalo
    bench_fill(img, 0, H - 3, W, H, B_WAL[3])
    bench_fill(img, 0, H - 3, W, H - 2, B_WAL[5])
    for (cx, cy, sx, sy) in [(0, 0, 1, 1), (W - 1, 0, -1, 1), (0, H - 1, 1, -1), (W - 1, H - 1, -1, -1)]:
        for k in range(4):
            bench_put(img, cx + sx * k, cy, B_BRASS[4] if k < 2 else B_BRASS[3])
            bench_put(img, cx, cy + sy * k, B_BRASS[3] if k < 2 else B_BRASS[2])
    bench_inner_outline(img, B_WAL[0])
    return bench_save(img, f'hud_shelf{rows * 6}.png')


def bench_shelf_stars():
    st = """
        ..Y..
        .YYY.
        YYYYY
        .YYY.
        .Y.Y.
        """
    bench_save(bench_ascii_art(st, {'Y': '#ffd451'}), 'shelf_star.png')
    bench_save(bench_ascii_art(st, {'Y': '#2a1a10'}), 'shelf_star_empty.png')


def bench_preview_all(path):
    files = sorted(os.listdir(OUT))
    ims = [Image.open(f'{OUT}/{f}').convert('RGBA') for f in files if f.endswith('.png')]
    S = 4
    cells = []
    for im in ims:
        k = S if max(im.size) < 120 else 2
        cells.append(im.resize((im.width * k, im.height * k), Image.NEAREST))
    W = 1800
    x = y = 8
    rowh = 0
    pos = []
    for c in cells:
        if x + c.width + 8 > W:
            x = 8
            y += rowh + 12
            rowh = 0
        pos.append((x, y))
        x += c.width + 12
        rowh = max(rowh, c.height)
    sheet = Image.new('RGBA', (W, y + rowh + 8), (58, 48, 78, 255))
    for c, p in zip(cells, pos):
        sheet.alpha_composite(c, p)
    sheet.save(path)

def bench_all():
    """R3 BENCH: todo el arte del banco del caldero, del ticket y del HUD -> ./salida/ui (copiar a assets/ui)."""
    os.makedirs(OUT, exist_ok=True)
    bench_shelf()
    bench_lock()
    bench_tag()
    bench_cauldron(B_IRON, 'bench_cauldron_iron.png')
    bench_cauldron(B_COPPER, 'bench_cauldron_copper.png')
    bench_liquid()
    bench_bubbles()
    bench_fire()
    bench_hearth()
    bench_ladle()
    bench_slot(False)
    bench_slot(True)
    bench_rack()
    bench_ess_icons()
    for k in ['normal', 'hover', 'pressed', 'disabled', 'primary']:
        bench_wood_button(k)
    bench_action_icons()
    bench_close_seal(False)
    bench_close_seal(True)
    bench_ticket_paper()
    bench_ticket_pin()
    bench_ticket_frame()
    bench_hud_icons()
    bench_hud_shelf(1)
    bench_hud_shelf(2)
    bench_shelf_stars()
    bench_preview_all('./prev_bench.png')


if '--bench' in sys.argv:
    bench_all()
    print('ok bench')
    sys.exit(0)
# --- end R3 BENCH
# --- R6 UI: los botones del HUD (arriba al centro y arriba a la derecha), la placa de los avisos de acción («E Hablar»)
# y los glifos de las teclas, del mando y del ratón. Pixel art a 1x guardado ya a 3x (r6_save): Godot lo dibuja 1:1 en
# el lienzo de 1920x1080 (a 1280x720 cada píxel de arte son 2 px de pantalla). Familias:
#   - botones de acción: cara de pergamino (tinta encima) sobre una tabla de nogal, aro de latón el principal;
#   - placas (los avisos sobre la gente y las estaciones): oscuras, con un hilo de latón y una colita que señala;
#   - teclas: tecla de pergamino con borde de tinta (la letra la escribe Godot); mando: botones redondos de colores
#     (A verde, B rojo, X azul, Y ámbar), gatillos, cruceta, Vista y Menú; ratón: el botón que se pulsa en dorado.
# Solo esto: python3 ui_art.py --r6 (sale en ./salida/ui; copiar los r6_*.png a assets/ui).
R6_K = 3
R6_OUT = B_WAL[0]             # contorno (nogal casi negro)
R6_INK = B_INK
R6_PAPER_HI = '#fbf3df'


def r6_save(img, name, k=R6_K):
    Image.fromarray(bench_up(img, k) if k > 1 else img, 'RGBA').save(f'{OUT}/{name}')
    return img


def r6_round(img, r=2):
    """Esquinas redondeadas (radio 1 o 2 px de arte): borra los píxeles de las esquinas."""
    h, w = img.shape[:2]
    cut = [(0, 0)] if r == 1 else [(0, 0), (1, 0), (0, 1)]
    for (x, y) in cut:
        for (cx, cy) in [(x, y), (w - 1 - x, y), (x, h - 1 - y), (w - 1 - x, h - 1 - y)]:
            img[cy, cx] = (0, 0, 0, 0)
    return img


def r6_frame(img, x0, y0, x1, y1, out, top, left, right, bottom):
    """Contorno de 1 px y aro de 1 px por dentro (arriba / izquierda / derecha / abajo) en el rectángulo [x0, x1) x [y0, y1)."""
    bench_fill(img, x0 + 1, y0, x1 - 1, y0 + 1, out)
    bench_fill(img, x0 + 1, y1 - 1, x1 - 1, y1, out)
    bench_fill(img, x0, y0 + 1, x0 + 1, y1 - 1, out)
    bench_fill(img, x1 - 1, y0 + 1, x1, y1 - 1, out)
    bench_fill(img, x0 + 1, y0 + 1, x1 - 1, y0 + 2, top)
    bench_fill(img, x0 + 1, y0 + 2, x0 + 2, y1 - 2, left)
    bench_fill(img, x1 - 2, y0 + 2, x1 - 1, y1 - 2, right)
    bench_fill(img, x0 + 1, y1 - 2, x1 - 1, y1 - 1, bottom)


def r6_paper_face(img, x0, y0, x1, y1, ramp, rng, fibres=True, cx0=None, cx1=None):
    """Cara de pergamino: de claro (arriba) a sombra (abajo), con alguna fibra. Las fibras van solo en [cx0, cx1) y se
    repiten con ese periodo (el centro de un nine-patch se repite sin costuras); sin cx0/cx1, en toda la cara."""
    hi, base, lo, lo2 = ramp
    h = y1 - y0
    for y in range(y0, y1):
        t = (y - y0) / max(1, h - 1)
        c = hi if t < 0.18 else (base if t < 0.72 else (lo if t < 0.9 else lo2))
        bench_fill(img, x0, y, x1, y + 1, c)
    if fibres and h > 4:
        a = x0 if cx0 is None else cx0
        b = x1 if cx1 is None else cx1
        w = b - a
        n = int(w * h * 0.05)
        for _ in range(n):
            x = int(rng.integers(0, w))
            y = int(rng.integers(y0 + 2, y1 - 1))
            L = int(rng.integers(2, 5))
            c = bench_mix(base, lo, 0.55) if rng.random() < 0.6 else bench_mix(base, hi, 0.7)
            if t_row(y, y0, h) > 0.72:
                continue
            for k in range(L):
                bench_put(img, a + (x + k) % w, y, c)


def t_row(y, y0, h):
    return (y - y0) / max(1, h - 1)


def r6_round_rect(img, x0, y0, x1, y1):
    """Esquinas redondeadas (radio 2) de un rectángulo dentro de la imagen."""
    for (x, y) in [(0, 0), (1, 0), (0, 1)]:
        for (cx, cy) in [(x0 + x, y0 + y), (x1 - 1 - x, y0 + y), (x0 + x, y1 - 1 - y), (x1 - 1 - x, y1 - 1 - y)]:
            if 0 <= cy < img.shape[0] and 0 <= cx < img.shape[1]:
                img[cy, cx] = (0, 0, 0, 0)


def r6_button(kind, state, W=64, H=18, edge=6):
    """Botón de acción (nine-patch de márgenes edge px de arte = 3*edge px): la cara de pergamino sobre una tabla de
    nogal que asoma 2 px por debajo (el canto). kind: 'primary' (aro de latón y tachuelas) o 'secondary' (aro de nogal).
    state: normal, hover, pressed (la cara baja 1 px: Godot baja el texto 3 px), disabled."""
    img = bench_canvas(W, H)
    rng = np.random.default_rng(61 if kind == 'primary' else 67)
    down = 1 if state == 'pressed' else 0
    fy0, fy1 = down, H - 3 + down          # la cara con su contorno: filas [fy0, fy1)
    if kind == 'primary':
        # (resume 2) la cara de miel: el principal se distingue de un vistazo del secundario (crema)
        rim = [B_BRASS[5], B_BRASS[4], B_BRASS[2], B_BRASS[1]]   # arriba, izquierda, derecha, abajo
        face = ['#ffeab0', '#f7d68a', '#ebc06c', '#d9a854']
    else:
        rim = [B_WAL[6], B_WAL[5], B_WAL[4], B_WAL[3]]
        face = ['#f4ead4', '#e9dec4', '#dccfb2', '#cdbf9f']
    wood = [B_WAL[1], B_WAL[2]]
    if state == 'hover':
        if kind == 'primary':
            face = ['#fff6d0', '#fde4a4', '#f3cd80', '#e3b666']
            rim = ['#fff6d2', B_BRASS[5], B_BRASS[3], B_BRASS[2]]
        else:
            face = ['#fdf7e8', '#f5eddb', '#eadfc6', '#ddd0b2']
            rim = [B_BRASS[4], B_BRASS[3], B_BRASS[2], B_BRASS[1]]
    elif state == 'pressed':
        face = ['#d2a85a', '#ddb76c', '#e6c47c', '#e6c47c'] if kind == 'primary' else ['#cfc2a4', '#d9ccb0', '#e0d5bc', '#e0d5bc']
        rim = [bench_mix(c, B_WAL[0], 0.35) for c in rim]
    elif state == 'disabled':
        face = ['#d2cabb', '#c8bfae', '#bdb3a1', '#b1a794']
        rim = ['#8f877c', '#7f776d', '#6a635a', '#5a544c']
        wood = ['#2e2a28', '#3a3431']
    # el canto de nogal (lo que asoma debajo de la cara) y su contorno
    if not down:
        bench_fill(img, 1, fy1, W - 1, H - 1, wood[1])
        bench_fill(img, 1, H - 2, W - 1, H - 1, wood[0])
        bench_fill(img, 0, fy1, 1, H - 1, R6_OUT)
        bench_fill(img, W - 1, fy1, W, H - 1, R6_OUT)
        bench_fill(img, 1, H - 1, W - 1, H, R6_OUT)
    else:
        bench_fill(img, 1, fy1, W - 1, H - 1, wood[0])
        bench_fill(img, 0, fy1, 1, H - 1, R6_OUT)
        bench_fill(img, W - 1, fy1, W, H - 1, R6_OUT)
        bench_fill(img, 1, H - 1, W - 1, H, R6_OUT)
    # la cara
    r6_paper_face(img, 2, fy0 + 2, W - 2, fy1 - 2, face, rng, fibres=state != 'disabled', cx0=edge, cx1=W - edge)
    r6_frame(img, 0, fy0, W, fy1, R6_OUT, rim[0], rim[1], rim[2], rim[3])
    r6_round_rect(img, 0, fy0, W, H)
    # tachuelas de latón en los extremos (el principal) o clavitos de nogal (el secundario)
    cy = (fy0 + fy1) // 2 - 1
    if state != 'disabled' and edge >= 5:
        for x in (3, W - 5):
            if kind == 'primary':
                bench_brass_dot(img, x, cy)
            else:
                bench_put(img, x, cy, B_WAL[4])
                bench_put(img, x + 1, cy, B_WAL[3])
                bench_put(img, x, cy + 1, B_WAL[3])
                bench_put(img, x + 1, cy + 1, B_WAL[2])
    return img


def r6_icon_button(state, S=22):
    """Botón cuadrado de icono (barra de arriba a la derecha): cara de pergamino en un marco de nogal; al pasar el ratón,
    el aro se vuelve de latón; pulsado, la cara baja 1 px."""
    img = r6_button('secondary', state, W=S, H=S, edge=0)
    return img


def r6_focus_ring(S=16):
    """Aro del foco del mando (nine-patch, márgenes 5): dos píxeles dorados por fuera del botón, esquinas redondas."""
    img = bench_canvas(S, S)
    gold, glow = '#ffe9a8', B_BRASS[3]
    bench_fill(img, 2, 0, S - 2, 1, glow, 160)
    bench_fill(img, 2, S - 1, S - 2, S, glow, 160)
    bench_fill(img, 0, 2, 1, S - 2, glow, 160)
    bench_fill(img, S - 1, 2, S, S - 2, glow, 160)
    bench_fill(img, 2, 1, S - 2, 2, gold)
    bench_fill(img, 2, S - 2, S - 2, S - 1, gold)
    bench_fill(img, 1, 2, 2, S - 2, gold)
    bench_fill(img, S - 2, 2, S - 1, S - 2, gold)
    for (x, y) in [(1, 1), (S - 2, 1), (1, S - 2), (S - 2, S - 2)]:
        bench_put(img, x, y, glow, 200)
    return img


def r6_plate(S=16, alpha=236):
    """Placa oscura (los avisos de acción, nine-patch de márgenes 5): contorno, hilo de latón y un fondo violeta noche
    casi opaco, esquinas redondas."""
    img = bench_canvas(S, S)
    fill = '#1a1426'
    bench_fill(img, 1, 1, S - 1, S - 1, fill, alpha)
    bench_fill(img, 2, 2, S - 2, 3, '#251d36', alpha)     # una luz arriba
    r6_frame(img, 0, 0, S, S, '#0b0812', B_BRASS[3], B_BRASS[2], B_BRASS[1], B_BRASS[1])
    return r6_round(img, 2)


def r6_tail():
    """La colita de la placa (señala a quién o a qué): 7x4, el borde de latón y el fondo de la placa."""
    art = """
        OkkkkkO
        .OfffO.
        ..OfO..
        ...O...
        """
    return bench_ascii_art(art, {'O': '#0b0812', 'k': B_BRASS[1], 'f': ('#1a1426', 236)})


def r6_key(state='normal', W=11, H=12):
    """Tecla (nine-patch: márgenes 3 a los lados y arriba, 4 abajo): pergamino claro con el canto de abajo más oscuro y
    borde de tinta. Godot escribe encima la tecla (E, Esc, Space...). 'down': pulsada (sin canto). W, H = 7, 8: la tecla
    chica (dentro de los botones y en las esquinas), también a 3x para que a 1280x720 quede nítida (2 px por píxel)."""
    img = bench_canvas(W, H)
    top = ['#fbf3df', '#f2e6c8', '#eadbb8']
    side = ['#cdb68a', '#a88a5c']
    if state == 'down':
        top = ['#e6d6b2', '#e0cda3', '#dccba2']
    body_y1 = H - 1 if state == 'down' else H - 3
    bench_fill(img, 1, 1, W - 1, H - 1, side[0])
    bench_fill(img, 1, H - 2, W - 1, H - 1, side[1])
    bench_fill(img, 1, 1, W - 1, body_y1, top[1])
    bench_fill(img, 1, 1, W - 1, 2, top[0])
    bench_fill(img, 1, body_y1 - 1, W - 1, body_y1, top[2])
    # contorno de tinta
    bench_fill(img, 1, 0, W - 1, 1, R6_INK)
    bench_fill(img, 1, H - 1, W - 1, H, R6_INK)
    bench_fill(img, 0, 1, 1, H - 1, R6_INK)
    bench_fill(img, W - 1, 1, W, H - 1, R6_INK)
    if state != 'down':
        bench_fill(img, 1, body_y1, W - 1, body_y1 + 1, bench_mix(side[0], R6_INK, 0.35))   # la arista entre cara y canto
    return img


# letras de 5x5 para los botones del mando (y 3x5 para LB / RB / LT / RT)
R6_GLYPH5 = {
    'A': [".###.", "#...#", "#####", "#...#", "#...#"],
    'B': ["####.", "#...#", "####.", "#...#", "####."],
    'X': ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    'Y': ["#...#", ".#.#.", "..#..", "..#..", "..#.."],
}
R6_GLYPH3 = {
    'L': ["#..", "#..", "#..", "#..", "###"], 'R': ["##.", "#.#", "##.", "#.#", "#.#"],
    'B': ["##.", "#.#", "##.", "#.#", "##."], 'T': ["###", ".#.", ".#.", ".#.", ".#."],
}
R6_PAD = {   # base, luz, sombra, letra
    'a': ('#3f9c4b', '#7fd28a', '#24662f', '#f4fbef'),
    'b': ('#c43f30', '#ee7f6c', '#7b2319', '#fff1ec'),
    'x': ('#3a6dc8', '#7ea8ee', '#203f7c', '#eef4ff'),
    'y': ('#d39f1f', '#f5d76a', '#86630f', '#fffbe8'),
}


def r6_pad_button(k):
    """Botón redondo del mando (11x11): disco con luz arriba a la izquierda, contorno oscuro y la letra en claro."""
    S = 11
    base, hi, lo, let = R6_PAD[k]
    img = bench_canvas(S, S)
    m = bench_ellipse_mask(S, S, 5.5, 5.5, 5.0, 5.0)
    ys, xs = np.nonzero(m)
    for y, x in zip(ys, xs):
        d = (x - 3.6) * 0.7 + (y - 3.6)
        c = hi if d < -1.2 else (base if d < 4.5 else lo)
        img[y, x] = (*bench_rgb(c), 255)
    g = R6_GLYPH5[k.upper()]
    for yy, row in enumerate(g):
        for xx, ch in enumerate(row):
            if ch == '#':
                bench_put(img, 3 + xx, 3 + yy, let)
                if 3 + yy + 1 < S and (yy + 1 >= 5 or g[yy + 1][xx] != '#'):
                    bench_put(img, 3 + xx, 4 + yy, lo)
    bench_outline(img, '#120e16')
    return img   # 13x13 con el contorno


def r6_bumper(text, trigger=False):
    """LB / RB (gatillos LT / RT con trigger): pastilla gris oscura con las letras."""
    W, H = 15, 9
    img = bench_canvas(W, H)
    body, hi, lo, let = '#4a4b5a', '#6d6f82', '#2c2c37', '#e8e6f0'
    if trigger:
        bench_fill(img, 1, 1, W - 1, H - 1, body)
        bench_fill(img, 2, 1, W - 2, 2, hi)
        bench_fill(img, 1, H - 2, W - 1, H - 1, lo)
    else:
        bench_fill(img, 1, 2, W - 1, H - 1, body)
        bench_fill(img, 3, 1, W - 3, 2, hi)
        bench_fill(img, 1, H - 2, W - 1, H - 1, lo)
    x = (W - 7) // 2
    for ch in text:
        for yy, row in enumerate(R6_GLYPH3[ch]):
            for xx, c in enumerate(row):
                if c == '#':
                    bench_put(img, x + xx, 2 + yy, let)
        x += 4
    bench_outline(img, '#120e16')
    return r6_round(img, 1)


def r6_small_round(kind):
    """Vista (dos ventanitas) y Menú (tres rayas): botones redondos chicos del mando."""
    S = 9
    img = bench_canvas(S, S)
    m = bench_ellipse_mask(S, S, 4.5, 4.5, 4.2, 4.2)
    ys, xs = np.nonzero(m)
    for y, x in zip(ys, xs):
        img[y, x] = (*bench_rgb('#3d3e4c' if (x + y) > 6 else '#55576a'), 255)
    w = '#e8e6f0'
    if kind == 'menu':
        for y in (2, 4, 6):
            bench_fill(img, 2, y, 7, y + 1, w)
    else:
        bench_fill(img, 2, 2, 5, 5, '#8a8ca0')
        bench_fill(img, 4, 4, 7, 7, w)
    bench_outline(img, '#120e16')
    return img


def r6_dpad(hl=''):
    """La cruceta (11x11); hl: 'lr' (izquierda / derecha encendidas), 'ud' o ''."""
    S = 11
    img = bench_canvas(S, S)
    arm, hi, lit = '#4a4b5a', '#6d6f82', '#f0e6c8'
    bench_fill(img, 4, 0, 7, S, arm)
    bench_fill(img, 0, 4, S, 7, arm)
    bench_fill(img, 4, 0, 7, 1, hi)
    bench_fill(img, 0, 4, 1, 7, hi)
    if hl == 'lr':
        bench_fill(img, 0, 4, 3, 7, lit)
        bench_fill(img, 8, 4, S, 7, lit)
    elif hl == 'ud':
        bench_fill(img, 4, 0, 7, 3, lit)
        bench_fill(img, 4, 8, 7, S, lit)
    bench_put(img, 5, 5, '#2c2c37')
    bench_outline(img, '#120e16')
    return img


def r6_stick(letter):
    """Un stick (L / R): disco gris con su letra."""
    S = 11
    img = bench_canvas(S, S)
    m = bench_ellipse_mask(S, S, 5.5, 5.5, 5.0, 5.0)
    ys, xs = np.nonzero(m)
    for y, x in zip(ys, xs):
        r = math.hypot(x + 0.5 - 5.5, y + 0.5 - 5.5)
        img[y, x] = (*bench_rgb('#2c2c37' if r > 3.6 else ('#55576a' if (x + y) < 10 else '#4a4b5a')), 255)
    for yy, row in enumerate(R6_GLYPH3[letter]):
        for xx, c in enumerate(row):
            if c == '#':
                bench_put(img, 4 + xx, 3 + yy, '#e8e6f0')
    bench_outline(img, '#120e16')
    return img


def r6_mouse(button):
    """El ratón (11x14): cuerpo de pergamino, contorno de tinta; button: 'left' / 'right' (en dorado) o '' (ninguno)."""
    art = """
        ...OOOOO...
        ..OLLLORRO.
        .OLLLLORRRO
        .OLLLLORRRO
        .OLLLLORRRO
        .OOOOOOOOOO
        .OwwwwwwwwO
        .OwwwwwwwwO
        .OwwwwwwwwO
        .OwwwwwwwsO
        .OswwwwwwsO
        ..OsssssO..
        ...OOOOO...
        """
    gold, cream, shade = '#e8a93a', '#f2e6c8', '#cdb68a'
    codes = {'O': R6_INK, 'w': cream, 's': shade,
             'L': gold if button == 'left' else cream, 'R': gold if button == 'right' else cream}
    img = bench_ascii_art(art, codes)
    return img


def r6_icons():
    """Iconos de 16x16 de los botones nuevos: la campanilla (abrir la tienda), la casita (volver a la tienda), la luna
    (dormir), el caldero (el banco del evento) y la flecha de salida. Mismo estilo que los del HUD (bench_hud_icons)."""
    codes = {'O': '#1c1424', 'k': B_BRASS[4], 'K': B_BRASS[2], 'h': B_BRASS[5], 'd': B_BRASS[1],
             'R': B_WAX[2], 'r': B_WAX[3], 'W': B_WAL[3], 'w': B_WAL[5], 'q': B_PAPER[5], 'Q': B_PAPER[3],
             'y': '#ffd84d', 'Y': '#f0a030', 'm': '#e9e2ff', 'M': '#b9aee6', 'I': B_IRON[3], 'i': B_IRON[5],
             'g': '#7fd28a', 'G': '#3f9c4b', 'f': B_FIRE[2], 'F': B_FIRE[4]}
    arts = {
        'bell': """
            ................
            .......OO.......
            ......OkKO......
            .......OO.......
            .....OOOOOO.....
            ....OhkkkkKO....
            ...OhkkkkkkKO...
            ...OhkkkkkkKO...
            ...OhkkkkkkKO...
            ...OhkkkkkkKO...
            ..OhkkkkkkkkKO..
            .OhkkkkkkkkkkKO.
            .OKKKKKKKKKKKKO.
            ..OOOOOOOOOOOO..
            ......OdddO.....
            .......OOO......
            """,
        'home': """
            ................
            .......OO.......
            ......ORRO..OO..
            .....ORrrRO.OWO.
            ....ORrrrrROOWO.
            ...ORrrrrrrRRWO.
            ..ORRRRRRRRRRRO.
            ...OqqqqqqqqqO..
            ...OqOOOqqOOqO..
            ...OqOyyOqOWOO..
            ...OqOyYOqOWWO..
            ...OqOOOOqOWWO..
            ...OqqqqqqOWWO..
            ...OQQQQQQOWkO..
            ...OOOOOOOOOOO..
            ................
            """,
        'moon': """
            ................
            .....OOOO.......
            ...OOmmmO.......
            ..OmmmMO........
            ..OmmMO.....O...
            .OmmmMO....OyO..
            .OmmmO......O...
            .OmmmO..........
            .OmmmMO.........
            .OmmmmMO.....O..
            ..OmmmmMOOOOOmO.
            ..OMmmmmmmmmMO..
            ...OMMmmmmMMO...
            ....OOMMMMOO....
            ......OOOO......
            ................
            """,
        'cauldron': """
            ................
            .....g..g.......
            ....gG.gG..g....
            ......G...gG....
            ..OOOOOOOOOOOO..
            .OiiiiiiiiiiiiO.
            ..OgggggggggGO..
            .OIiIIIIIIIIIIO.
            .OIIIIIIIIIIIIO.
            .OIIIIIIIIIIIIO.
            ..OIIIIIIIIIIO..
            ...OIIIIIIIIO...
            ..OfOOOOOOOOfO..
            ..OFfFfFfFfFfO..
            ...OOOOOOOOOO...
            ................
            """,
    }
    out = {}
    for k, a in arts.items():
        out[k] = bench_ascii_art(a, codes)
    return out


def r6_all():
    """R6 UI: todo el arte nuevo de esta ronda -> ./salida/ui/r6_*.png (copiar a assets/ui) y la hoja ./prev_r6.png."""
    os.makedirs(OUT, exist_ok=True)
    made = []

    def keep(img, name):
        r6_save(img, name)
        made.append((name, img))

    for kind in ('primary', 'secondary'):
        for st in ('normal', 'hover', 'pressed', 'disabled'):
            keep(r6_button(kind, st), f'r6_btn_{kind}_{st}.png')
            # (resume 2) la alta (22 px de arte = 66 px): los botones de arriba al centro, a la altura de la barra de la
            # derecha y de la placa del HUD
            keep(r6_button(kind, st, H=22), f'r6_btn_{kind}_{st}_t.png')
    for st in ('normal', 'hover', 'pressed', 'disabled'):
        keep(r6_icon_button(st), f'r6_ibtn_{st}.png')
    keep(r6_focus_ring(), 'r6_focus9.png')
    keep(r6_plate(), 'r6_plate9.png')
    keep(r6_tail(), 'r6_plate_tail.png')
    keep(r6_key('normal'), 'r6_key9.png')
    keep(r6_key('down'), 'r6_key9_down.png')
    keep(r6_key('normal', 7, 8), 'r6_key9_mini.png')   # la tecla chica nítida (3x; márgenes 6 / 6 / 6 / 9)
    for k in R6_PAD:
        keep(r6_pad_button(k), f'r6_pad_{k}.png')
        r6_save(r6_pad_button(k), f'r6_pad_{k}_2x.png', 2)
    keep(r6_bumper('LB'), 'r6_pad_lb.png')
    keep(r6_bumper('RB'), 'r6_pad_rb.png')
    keep(r6_bumper('LT', True), 'r6_pad_lt.png')
    keep(r6_bumper('RT', True), 'r6_pad_rt.png')
    keep(r6_small_round('view'), 'r6_pad_view.png')
    keep(r6_small_round('menu'), 'r6_pad_menu.png')
    keep(r6_dpad(''), 'r6_pad_dpad.png')
    keep(r6_dpad('lr'), 'r6_pad_dpad_lr.png')
    keep(r6_dpad('ud'), 'r6_pad_dpad_ud.png')
    keep(r6_stick('L'), 'r6_pad_ls.png')
    keep(r6_stick('R'), 'r6_pad_rs.png')
    keep(r6_mouse('left'), 'r6_mouse_left.png')
    keep(r6_mouse('right'), 'r6_mouse_right.png')
    keep(r6_mouse(''), 'r6_mouse.png')
    for k in ('left', 'right'):
        r6_save(r6_mouse(k), f'r6_mouse_{k}_2x.png', 2)
    for nm, im in (('view', r6_small_round('view')), ('menu', r6_small_round('menu')), ('dpad_lr', r6_dpad('lr')),
                   ('lb', r6_bumper('LB')), ('rb', r6_bumper('RB'))):
        r6_save(im, f'r6_pad_{nm}_2x.png', 2)
    for k, im in r6_icons().items():
        r6_save(im, f'r6_ico_{k}.png', 1)
        made.append((f'r6_ico_{k}.png', im))
    # la hoja de muestras
    cells = [bench_up(im, 4) for _, im in made]
    W = 1600
    x = y = 8
    rowh = 0
    pos = []
    for c in cells:
        if x + c.shape[1] + 8 > W:
            x = 8
            y += rowh + 12
            rowh = 0
        pos.append((x, y))
        x += c.shape[1] + 12
        rowh = max(rowh, c.shape[0])
    sheet = Image.new('RGBA', (W, y + rowh + 8), (58, 48, 78, 255))
    for c, p in zip(cells, pos):
        sheet.alpha_composite(Image.fromarray(c, 'RGBA'), p)
    sheet.save('./prev_r6.png')
    print('r6:', len(made), 'imágenes')


if '--r6' in sys.argv:
    r6_all()
    sys.exit(0)
# --- end R6 UI
CORNER = """
YYYYYYYYYY..
Y...........
Y.YYYYYY....
Y.Y.........
Y.Y..YY.....
Y.Y..Y......
Y.Y.........
Y...........
Y...........
Y...........
.............
.............
"""
c = art(CORNER, {'Y': ('#e2c27a', None, 'flat')}, outline=False)
save(c, f'{OUT}/corner.png')
DIV = """
...............Y................
.YYYYYYYYYYYY.YYY.YYYYYYYYYYYYY.
...............Y................
"""
save(art(DIV, {'Y': ('#e2c27a', None, 'flat')}, outline=False), f'{OUT}/divider.png')
# cursor del mando: flecha dorada con borde oscuro (la punta es el píxel 1,1)
CURSOR = """
............
.G..........
.GG.........
.GHG........
.GHGG.......
.GHGGG......
.GHGGGG.....
.GHGGGGG....
.GHGGGGGG...
.GHGGGGGGG..
.GHGGGGG....
.GHG.GGG....
.GG..GGGG...
.G....GGG...
.......GG...
............
"""
save(art(CURSOR, {'G': ('#e2c27a', None, 'cyl'), 'H': ('#e2c27a', 4, 'flat')}), f'{OUT}/cursor.png')
# game icon: cauldron with teal liquid on night background
ic = Image.new('RGBA', (64, 64), (24, 20, 44, 255))
cal = Image.open('./salida/props/cauldron_copper.png')
liq = Image.open('./salida/props/cauldron_liquid.png').convert('RGBA')
import numpy as np
l = np.array(liq).astype(float); l[..., 0] *= 95/255; l[..., 1] *= 224/255; l[..., 2] *= 192/255
liq = Image.fromarray(l.astype('uint8'), 'RGBA')
base = Image.new('RGBA', (40, 28), (0, 0, 0, 0)); base.alpha_composite(liq); base.alpha_composite(cal)
# stars
px = ic.load()
for (x, y) in [(8, 8), (50, 12), (30, 5), (12, 30), (56, 34), (40, 20)]:
    px[x, y] = (255, 240, 200, 255)
ic.alpha_composite(base, (12, 26))
# sparkle above
for (x, y) in [(30, 18), (34, 14), (27, 12)]:
    px[x, y] = (180, 255, 230, 255)
ic = ic.resize((128, 128), Image.NEAREST)
ic.save(f'{OUT}/icon.png')
preview([c, art(DIV, {'Y': ('#e2c27a', None, 'flat')}, outline=False), np.array(ic.resize((64,64), Image.NEAREST))], scale=4, cols=3, path='./prev_ui.png')
print('ok')

# --- R3 PAPER: papel de verdad para el recetario, el diario, el correo, el mercado y los paneles ------------------
# Sale en ./salida/ui/paper_*.png (copiar a assets/ui/). Pixel art a 1x guardado ya ampliado con vecino más cercano:
# las hojas y los nine-patch ("*9.png") a x2, los adornos sueltos a 1x (Godot los escala con UIKit.icon / PaperKit).
# Los márgenes de cada nine-patch (en píxeles de la imagen guardada) están en scripts/ui/paper_kit.gd (NINE).
# Paleta de la guía de estilo: crema #EADBB8 -> sombra #CDB68A -> bordes quemados; tinta #3A2618, lacre #9E2B25,
# latón #C9A15A, verde hierba #4E6B3A, violeta noche #3B2F52, nogal #5A3A22.
import glob as _glob

PARCH = ['#F7EED7', '#EADBB8', '#E0CDA3', '#CDB68A', '#B99B6B', '#A07D50', '#765536']   # claro -> quemado
INK_C = '#3A2618'
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
_PRNG = np.random.default_rng(1307)

def _hx(h):
    h = h.lstrip('#').replace(' ', '')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)

def _up(arr, k):
    return np.asarray(arr).repeat(k, 0).repeat(k, 1)

def _save(arr, name, k=1):
    a = np.clip(np.asarray(arr), 0, 255).astype(np.uint8)
    Image.fromarray(_up(a, k) if k > 1 else a, 'RGBA').save(f'{OUT}/{name}')
    return a

def _wrap_blur(a, r, n=2):
    """Desenfoque de caja con vuelta (la textura sigue siendo repetible)."""
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

def _fibres(w, h, rng, density=40):
    f = np.zeros((h, w))
    for _ in range(w * h // density):
        x, y = int(rng.integers(0, w)), int(rng.integers(0, h))
        L = int(rng.integers(2, 6))
        s = float(rng.choice([-0.6, -0.4, 0.45, 0.65]))
        slope = int(rng.choice([0, 0, 0, 1, -1]))
        for i in range(L):
            f[(y + (i * slope) // 3) % h, (x + i) % w] += s
    return f

def _paper_field(w, h, rng, grain=1.0):
    """Valor del papel (1 = crema): manchas grandes, moteado y fibras. Repetible con periodo (w, h)."""
    low = _tile_noise(w, h, max(2, min(w, h) // 9), rng)
    mid = _tile_noise(w, h, 1, rng, 2)
    return 1.0 + (low - 0.5) * 1.0 + (mid - 0.5) * 0.55 * grain + _fibres(w, h, rng) * grain

def _quantize(v, ramp, dither=1.0, ox=0, oy=0):
    h, w = v.shape
    b = np.tile(BAYER4, (h // 4 + 2, w // 4 + 2))[oy % 4:oy % 4 + h, ox % 4:ox % 4 + w]
    idx = np.clip(np.floor(v + (b - 0.5) * dither), 0, len(ramp) - 1).astype(int)
    pal = np.array([_hx(c) for c in ramp])
    return pal[idx]

def _age(dist):
    """Envejecido según la distancia al borde (en píxeles): quemado en el filo, tostado cerca."""
    a = np.zeros_like(dist)
    a += np.where(dist < 1.0, 3.6, 0.0)
    a += np.where((dist >= 1.0) & (dist < 3.0), 2.1 - (dist - 1.0) * 0.55, 0.0)
    a += np.where((dist >= 3.0) & (dist < 9.0), (9.0 - dist) / 6.0 * 0.95, 0.0)
    return a

def _shadow_under(rgba, dx=2, dy=3, alpha=95):
    """Sombra dura de pixel art debajo de la hoja (fuera de la hoja, desplazada)."""
    h, w = rgba.shape[:2]
    m = rgba[..., 3] > 0
    sh = np.zeros((h, w), bool)
    sh[dy:, dx:] = m[:h - dy, :w - dx]
    out = rgba.copy()
    put = sh & ~m
    out[put] = [32, 20, 12, alpha]
    return out

def _deckle(n, amp, rng, r=2, bites=0, periodic=True):
    d = _noise1(n, r, rng) * amp
    d += (rng.random(n) < 0.12) * 0.8          # fibras sueltas en el filo
    for _ in range(bites):                       # mordiscos de papel rasgado
        c, wdt = int(rng.integers(0, n)), int(rng.integers(3, 8))
        for i in range(-wdt, wdt + 1):
            d[(c + i) % n] += (1.0 - abs(i) / (wdt + 1)) * amp * 1.4
    return d

def parchment_sheet(w, h, seed, amp=2.2, bites=(1, 1, 0, 1), stains=(), shadow=True):
    """Una hoja suelta de pergamino de w x h (1x) con bordes deshilachados, filo quemado y manchas."""
    rng = np.random.default_rng(seed)
    v = _paper_field(w, h, rng)
    dt = _deckle(w, amp, rng, bites=bites[0])
    db = _deckle(w, amp, rng, bites=bites[2])
    dl = _deckle(h, amp, rng, bites=bites[3])
    dr = _deckle(h, amp, rng, bites=bites[1])
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    m = 4  # margen para la sombra y el filo
    dist = np.minimum.reduce([xx - m - dl[yy.astype(int)], (w - 1 - m) - xx - dr[yy.astype(int)],
                              yy - m - dt[xx.astype(int)], (h - 1 - m) - yy - db[xx.astype(int)]])
    # esquinas redondeadas un poco
    cr = 5.0
    for cx, cy in ((m + cr, m + cr), (w - 1 - m - cr, m + cr), (m + cr, h - 1 - m - cr), (w - 1 - m - cr, h - 1 - m - cr)):
        box = (np.abs(xx - cx) <= cr + 0.01) & (np.abs(yy - cy) <= cr + 0.01) & ((xx - cx) * (cx - w / 2) > 0) & ((yy - cy) * (cy - h / 2) > 0)
        dc = cr - np.hypot(xx - cx, yy - cy)
        dist = np.where(box, np.minimum(dist, dc), dist)
    dist += (rng.random((h, w)) - 0.5) * 0.7
    v = v + _age(dist)
    # manchas: anillos de té, gotas
    for st in stains:
        kind, sx, sy, R = st[0], st[1], st[2], st[3]
        rr = np.hypot(xx - sx, (yy - sy) * 1.08)
        jit = _noise1(64, 3, rng)[(np.degrees(np.arctan2(yy - sy, xx - sx)) % 360 / 360 * 63).astype(int)] * 1.6
        if kind == 'ring':
            ring = np.exp(-((rr - R - jit) ** 2) / 1.4)
            v += ring * 1.25 + np.where(rr < R + jit, 0.28, 0.0)
        elif kind == 'blot':
            v += np.where(rr < R + jit * 0.6, 0.9, 0.0)
    col = _quantize(v, PARCH, 1.0)
    alpha = np.where(dist >= 0, 255, 0)
    out = np.dstack([col, alpha]).astype(np.float64)
    out = out.astype(np.uint8)
    return _shadow_under(out) if shadow else out

def parchment9(seed, M=12, C=128, amp=1.8, tint=None, ramp=None, blotch=0.7):
    """Nine-patch de pergamino: centro y bordes repetibles (periodo C), filo deshilachado y quemado."""
    rng = np.random.default_rng(seed)
    S = 2 * M + C
    base = _paper_field(C, C, rng)
    base = 1.0 + (base - 1.0) * blotch
    v = np.roll(np.tile(base, (3, 3))[:S, :S], (M % C, M % C), axis=(0, 1))
    def edge():
        seg = _deckle(C, amp, rng, r=2)
        full = np.zeros(S)
        for x in range(S):
            full[x] = seg[(x - M) % C]
        return full
    dt, db, dl, dr = edge(), edge(), edge(), edge()
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    m = 3
    dist = np.minimum.reduce([xx - m - dl[yy.astype(int)], (S - 1 - m) - xx - dr[yy.astype(int)],
                              yy - m - dt[xx.astype(int)], (S - 1 - m) - yy - db[xx.astype(int)]])
    cr = 3.0
    for cx, cy in ((m + cr, m + cr), (S - 1 - m - cr, m + cr), (m + cr, S - 1 - m - cr), (S - 1 - m - cr, S - 1 - m - cr)):
        box = (np.abs(xx - cx) <= cr) & (np.abs(yy - cy) <= cr) & ((xx - cx) * (cx - S / 2) > 0) & ((yy - cy) * (cy - S / 2) > 0)
        dist = np.where(box, np.minimum(dist, cr - np.hypot(xx - cx, yy - cy)), dist)
    v = v + _age(dist * 1.25)
    col = _quantize(v, ramp or PARCH, 1.0)
    if tint is not None:
        col = col * 0.72 + _hx(tint) * 0.28
    out = np.dstack([col, np.where(dist >= 0, 255, 0)]).astype(np.uint8)
    return _shadow_under(out, 1, 2, 80)

WOOD = ['#2A170C', '#3A2414', '#4A2E1A', '#5A3A22', '#6B472A', '#7D5634', '#916640']

def wood9(seed, M=10, C=40, plank=10):
    """Nine-patch de nogal: tablones con veta, marco biselado y esquineras de latón con remache."""
    rng = np.random.default_rng(seed)
    S = 2 * M + C
    yy, xx = np.mgrid[0:S, 0:S]
    v = np.full((S, S), 3.0)
    # tablones horizontales (periodo C en x e y)
    py = (yy - M) % C
    row = py // plank
    inrow = py % plank
    ph = rng.random(8) * 6.28
    for r in range(C // plank):
        sel = row == r
        xs = (xx - M) % C
        grain = np.sin(xs * 6.28 / C * (1 + r % 2) + ph[r] + np.sin(xs * 6.28 / C * 2 + ph[r + 1]) * 1.2)
        v = np.where(sel & (np.abs(inrow - plank / 2 - grain * 2.2) < 0.7), v - 0.8, v)
        v = np.where(sel & (np.abs(inrow - plank / 2 + 2 - grain * 1.6) < 0.5), v + 0.6, v)
    v = np.where(inrow == 0, 1.0, v)            # junta entre tablones
    v = np.where(inrow == 1, v + 0.7, v)        # canto iluminado
    n = _tile_noise(C, C, 1, rng, 1)
    v += (np.roll(np.tile(n, (3, 3))[:S, :S], (M % C, M % C), axis=(0, 1)) - 0.5) * 0.9
    # marco: bisel claro arriba/izquierda, oscuro abajo/derecha
    d = np.minimum.reduce([xx, yy, S - 1 - xx, S - 1 - yy])
    v = np.where(d == 0, 0.2, v)
    v = np.where((d >= 1) & (d <= 3) & ((xx <= 3) | (yy <= 3)) & (xx < S - 4) & (yy < S - 4), 5.2, v)
    v = np.where((d >= 1) & (d <= 3) & ((xx >= S - 4) | (yy >= S - 4)), 2.0, v)
    v = np.where(d == 4, 1.2, v)
    col = _quantize(v, WOOD, 0.8)
    out = np.dstack([col, np.full((S, S), 255)]).astype(np.uint8)
    # esquineras de latón
    cap = art("""
BBBBBBBB.
BhhhhhhB.
BhBBBBBB.
BhB......
BhB.r....
BhB......
BhB......
BBB......
""", {'B': ('#C9A15A', None, 'flat'), 'h': ('#E8C77A', None, 'flat'), 'r': ('#7A5A2A', None, 'flat')}, outline=True)
    ch, cw = cap.shape[:2]
    for fx, fy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        c = cap[:, ::-1] if fx else cap
        c = c[::-1] if fy else c
        x0 = 0 if not fx else S - cw
        y0 = 0 if not fy else S - ch
        mm = c[..., 3] > 0
        out[y0:y0 + ch, x0:x0 + cw][mm] = c[mm]
    return out

CORK = ['#6E4A26', '#8A5F34', '#A6763F', '#B98A55', '#C99B63', '#D8AE78']

def cork9(seed, M=10, C=40):
    """Nine-patch de corcho con marco de roble claro (el tablón del diario)."""
    rng = np.random.default_rng(seed)
    S = 2 * M + C
    yy, xx = np.mgrid[0:S, 0:S]
    n = _tile_noise(C, C, 1, rng, 1)
    v = 3.0 + (np.roll(np.tile(n, (3, 3))[:S, :S], (M % C, M % C), axis=(0, 1)) - 0.5) * 1.6
    sp = rng.random((C, C))
    spk = np.roll(np.tile(sp, (3, 3))[:S, :S], (M % C, M % C), axis=(0, 1))
    v = np.where(spk < 0.07, 1.0, v)
    v = np.where(spk > 0.95, 5.0, v)
    col = _quantize(v, CORK, 0.7)
    d = np.minimum.reduce([xx, yy, S - 1 - xx, S - 1 - yy])
    frame = _quantize(np.full((S, S), 4.0) + (_tile_noise(S, S, 2, rng) - 0.5), WOOD, 0.6)
    col = np.where((d <= 6)[..., None], frame, col)
    col = np.where(((d >= 1) & (d <= 2) & ((xx <= 2) | (yy <= 2)))[..., None], _hx(WOOD[6]), col)
    col = np.where(((d >= 1) & (d <= 2) & ((xx >= S - 3) | (yy >= S - 3)))[..., None], _hx(WOOD[2]), col)
    col = np.where((d == 0)[..., None], _hx(WOOD[0]), col)
    col = np.where((d == 6)[..., None], _hx(CORK[0]), col)
    return np.dstack([col, np.full((S, S), 255)]).astype(np.uint8)

def cloth9(color, seed, M=8, C=32, check=8):
    """Nine-patch de mantel de cuadros (el color del toldo del puesto) con dobladillo cosido."""
    rng = np.random.default_rng(seed)
    S = 2 * M + C
    yy, xx = np.mgrid[0:S, 0:S]
    base = _hx('#EFE4CC')
    tint = _hx(color)
    cx = ((xx - M) % C) // check % 2
    cy = ((yy - M) % C) // check % 2
    k = (cx + cy) * 0.5          # 0, 0.5, 1: cuadro claro, banda, cruce
    col = base * (1 - k[..., None] * 0.62) + tint * (k[..., None] * 0.62)
    weave = ((xx + yy) % 2 == 0)
    col = col * np.where(weave, 1.0, 0.94)[..., None]
    d = np.minimum.reduce([xx, yy, S - 1 - xx, S - 1 - yy])
    col = np.where((d <= 2)[..., None], tint * 0.78, col)
    col = np.where(((d == 4) & (((xx + yy) // 2) % 2 == 0))[..., None], tint * 0.55, col)   # puntadas
    col = np.where((d == 0)[..., None], tint * 0.45, col)
    out = np.dstack([col, np.full((S, S), 255)]).astype(np.uint8)
    return _shadow_under(out, 0, 2, 70)

def sign9(seed, M=10, C=24, H=22):
    """Letrero de madera del puesto (3 partes: extremos con clavo y cuerda, tablón repetible)."""
    rng = np.random.default_rng(seed)
    S = 2 * M + C
    yy, xx = np.mgrid[0:H, 0:S]
    v = np.full((H, S), 4.0)
    ph = rng.random(3) * 6.28
    xs = (xx - M) % C
    v -= (np.abs(np.sin(xs / C * 6.28 + ph[0]) * 3 + 8 - yy) < 0.6) * 0.9
    v -= (np.abs(np.sin(xs / C * 6.28 * 2 + ph[1]) * 2 + 14 - yy) < 0.5) * 0.7
    v = np.where(yy <= 3, 5.4, v)
    v = np.where(yy >= H - 3, 2.2, v)
    v = np.where((yy == 0) | (yy == H - 1), 0.4, v)
    col = _quantize(v, WOOD, 0.6)
    a = np.full((H, S), 255)
    # extremos redondeados
    for x in range(3):
        for y in range(H):
            if (y < 2 - x) or (y > H - 3 + x):
                a[y, x] = 0
                a[y, S - 1 - x] = 0
    out = np.dstack([col, a]).astype(np.uint8)
    for nx in (4, S - 5):        # clavos de latón
        out[H // 2 - 1:H // 2 + 1, nx - 1:nx + 1] = [201, 161, 90, 255]
        out[H // 2 - 1, nx - 1] = [240, 210, 140, 255]
    return out

def tab9(seed, M=6, C=20, H=18):
    """Pestaña de índice de papel (se pega encima de la hoja; sin borde abajo)."""
    rng = np.random.default_rng(seed)
    S = 2 * M + C
    v = 1.0 + (_tile_noise(S, H, 2, rng) - 0.5) * 0.8
    yy, xx = np.mgrid[0:H, 0:S].astype(float)
    dist = np.minimum.reduce([xx - 0.5, S - 1.5 - xx, yy - 0.5])
    for cx, cy in ((3.5, 3.5), (S - 4.5, 3.5)):
        box = (np.abs(xx - cx) <= 3.5) & (yy <= 3.5) & ((xx - cx) * (cx - S / 2) > 0)
        dist = np.where(box, np.minimum(dist, 3.2 - np.hypot(xx - cx, yy - cy)), dist)
    v += np.where(dist < 1, 2.6, 0) + np.where((dist >= 1) & (dist < 3), 0.8, 0)
    v += np.where(yy > H - 3, 0.6, 0)
    col = _quantize(v, PARCH, 0.8)
    return np.dstack([col, np.where(dist >= 0, 255, 0)]).astype(np.uint8)

def tag9(seed):
    """Etiqueta de precio con agujero (9-patch horizontal: la punta y el agujero a la izquierda)."""
    return art("""
............................
.....PPPPPPPPPPPPPPPPPPPPPP.
....PPPPPPPPPPPPPPPPPPPPPPP.
...PPPPPPPPPPPPPPPPPPPPPPPP.
..PPOOPPPPPPPPPPPPPPPPPPPPP.
..PPOOPPPPPPPPPPPPPPPPPPPPP.
...PPPPPPPPPPPPPPPPPPPPPPPP.
....PPPPPPPPPPPPPPPPPPPPPPP.
.....PPPPPPPPPPPPPPPPPPPPPP.
............................
""", {'P': ('#F2E6C6', None, 'flat'), 'O': ('#5A3A22', 1, 'flat')}, outline=True)

def pin(color):
    a = art("""
..HHH..
.HhHHH.
HhhHHHH
HHHHHHH
HHHHHHH
.HHHHH.
..HHH..
...N...
...N...
""", {'H': (color, None, 'cyl'), 'h': (color, 4, 'flat'), 'N': ('#8A8A90', 2, 'flat')}, outline=True)
    return _shadow_under(a, 1, 1, 70)

def tape(seed):
    rng = np.random.default_rng(seed)
    w, h = 24, 8
    a = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        for x in range(w):
            jag_l = 1 + int(rng.integers(0, 2)) if y % 2 else int(rng.integers(0, 2))
            jag_r = w - 2 - int(rng.integers(0, 2)) if y % 2 else w - 1 - int(rng.integers(0, 2))
            if jag_l <= x <= jag_r:
                c = _hx('#E7D9AE') * (0.94 if (x + y * 3) % 7 == 0 else 1.0)
                a[y, x] = [*c.astype(int), 190]
    a[0, :, 3] = np.where(a[0, :, 3] > 0, 150, 0)
    return a

def stain_ring(seed, R=12):
    rng = np.random.default_rng(seed)
    S = 2 * R + 6
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    c = S / 2
    rr = np.hypot(xx - c, yy - c)
    ang = (np.degrees(np.arctan2(yy - c, xx - c)) % 360 / 360 * 63).astype(int)
    jit = _noise1(64, 3, rng)[ang] * 1.5
    ring = np.exp(-((rr - R - jit) ** 2) / 1.0)
    a = np.zeros((S, S, 4), np.uint8)
    alpha = np.clip(ring * 120 + np.where(rr < R + jit, 26, 0), 0, 255)
    alpha = np.where((alpha > 20) & (rng.random((S, S)) > 0.12), alpha, 0)
    a[..., :3] = _hx('#8A5E32').astype(int)
    a[..., 3] = (np.round(alpha / 40) * 40).astype(np.uint8)
    return a

def stain_blot(seed, col='#2A1A10'):
    rng = np.random.default_rng(seed)
    S = 20
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    m = np.hypot(xx - 9, (yy - 10) * 1.2) < 4.5 + _noise1(64, 2, rng)[(np.degrees(np.arctan2(yy - 10, xx - 9)) % 360 / 360 * 63).astype(int)] * 2.5
    for _ in range(6):
        ang, r = rng.random() * 6.28, 7 + rng.random() * 3
        px, py = 9 + np.cos(ang) * r, 10 + np.sin(ang) * r
        m |= np.hypot(xx - px, yy - py) < 0.9 + rng.random()
    a = np.zeros((S, S, 4), np.uint8)
    a[m] = [*_hx(col).astype(int), 225]
    return a

def wax_seal(base, seed, S=24):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    c = (S - 1) / 2
    ang = (np.degrees(np.arctan2(yy - c, xx - c)) % 360 / 360 * 63).astype(int)
    R = 9.6 + _noise1(64, 2, rng)[ang] * 1.8
    rr = np.hypot(xx - c, yy - c)
    blob = rr < R
    r0 = np.array(shift(hexrgb(base), -0.30, 0.04), float)
    r1 = np.array(shift(hexrgb(base), -0.14, 0.02), float)
    r2 = _hx(base)
    r3 = np.array(shift(hexrgb(base), 0.14, -0.06), float)
    r4 = np.array(shift(hexrgb(base), 0.30, -0.16), float)
    col = np.zeros((S, S, 3))
    # luz desde arriba a la izquierda
    lit = ((xx - c) * -0.6 + (yy - c) * -0.8) / 10.0
    v = 2 + lit
    ring = np.abs(rr - 6.2) < 0.75
    v = np.where(ring, v - 1.1, v)
    v = np.where(np.abs(rr - 5.2) < 0.6, v + 0.9, v)
    v = np.where(rr > R - 1.2, v - 0.8, v)
    idx = np.clip(np.round(v), 0, 4).astype(int)
    pal = np.array([r0, r1, r2, r3, r4])
    col = pal[idx]
    a = np.dstack([col, np.where(blob, 255, 0)]).astype(np.uint8)
    hl = (np.hypot(xx - (c - 4), yy - (c - 5)) < 1.3) & blob
    a[hl] = [*np.clip(r4 + 30, 0, 255).astype(int), 255]
    return _shadow_under(a, 1, 1, 90)

def fold(direction, hover=False):
    """Esquina de la hoja levantada para pasar la página (abajo a la derecha = siguiente, a la izquierda = anterior)."""
    S = 18
    a = np.zeros((S, S, 4), np.uint8)
    back = _hx('#D2BB8C' if not hover else '#F2DEB0')
    for y in range(S):
        for x in range(S):
            k = x + y - (S - 1)
            if k >= 1:
                a[y, x] = [*(back * (0.84 + 0.16 * k / S)).astype(int), 255]
                if x == S - 1 or y == S - 1:
                    a[y, x] = [*(back * 0.7).astype(int), 255]
            elif k == 0:
                a[y, x] = [*_hx('#8A6A42').astype(int), 255]
            elif k >= -2:
                a[y, x] = [40, 26, 14, 80 if k == -1 else 40]
    for j, row in enumerate(["X..", ".X.", "..X", ".X.", "X.."]):
        for i, ch in enumerate(row):
            if ch == 'X':
                a[S - 8 + j, S - 7 + i] = [*_hx(INK_C).astype(int), 255]
    return a[:, ::-1] if direction == 'prev' else a

def stamp_x2(rot=-9):
    """Sello de tinta roja «x2» (el encargo de día cuesta el doble)."""
    W, H = 30, 20
    a = np.zeros((H, W, 4), np.uint8)
    red = [*_hx('#B3261E').astype(int), 235]
    rng = np.random.default_rng(22)
    for x in range(1, W - 1):
        for y in (1, 2, H - 3, H - 2):
            a[y, x] = red
    for y in range(1, H - 1):
        for x in (1, 2, W - 3, W - 2):
            a[y, x] = red
    for (x, y) in ((1, 1), (W - 2, 1), (1, H - 2), (W - 2, H - 2)):
        a[y, x] = 0
    GL = {
        'x': ["X.....X", "XX...XX", ".XX.XX.", "..XXX..", ".XX.XX.", "XX...XX", "X.....X"],
        '2': [".XXXXX.", "XX...XX", ".....XX", "...XXX.", ".XXX...", "XX.....", "XXXXXXX"],
    }
    def put(g, ox, oy, sx=1, sy=1):
        for j, row in enumerate(GL[g]):
            for i, ch in enumerate(row):
                if ch == 'X':
                    for dy in range(sy):
                        for dx in range(sx):
                            a[oy + j * sy + dy, ox + i * sx + dx] = red
    put('x', 5, 8)
    put('2', 15, 3, 1, 2)
    # grano del sello (tinta que no llegó)
    holes = (rng.random((H, W)) < 0.13) & (a[..., 3] > 0)
    a[holes, 3] = 120
    im = Image.fromarray(a, 'RGBA').rotate(rot, resample=Image.NEAREST, expand=True)
    b = np.array(im)
    ys, xs = np.nonzero(b[..., 3])
    return b[ys.min():ys.max() + 1, xs.min():xs.max() + 1]

def small_x2():
    red = [*_hx('#B3261E').astype(int), 255]
    rows = ["X...X.XXX.", ".X.X.X...X", "..X.....X.", ".X.X..X...", "X...X.XXXX"]
    a = np.zeros((len(rows) + 2, len(rows[0]) + 2, 4), np.uint8)
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch == 'X':
                a[j + 1, i + 1] = red
    return a

ESS_ART = {
    'fuego': ("""
.......
...F...
..FF...
..FFF.F
.FFYFFF
.FYYYF.
.FYYYF.
..FYF..
.......
""", {'F': ('#E8603A', None, 'cyl'), 'Y': ('#FFC85A', None, 'flat')}),
    'escarcha': ("""
.........
....I....
..I.I.I..
...III...
.IIIIIII.
...III...
..I.I.I..
....I....
.........
""", {'I': ('#6CC4F0', None, 'flat')}),
    'vida': ("""
.........
......LL.
....LLLL.
...LLlLL.
..LLlLL..
..LlLL...
.LlLL....
.l.......
.........
""", {'L': ('#5DBA62', None, 'cyl'), 'l': ('#2F6B35', None, 'flat')}),
    'sombra': ("""
.........
...SSS...
..SS.....
.SS......
.SS......
.SS......
..SS...S.
...SSSS..
.........
""", {'S': ('#9B74E8', None, 'cyl')}),
    'luz': ("""
.........
....Y....
.Y.....Y.
...YYY...
..YYYYY.Y
Y.YYYYY..
..YYYYY..
.Y.YYY.Y.
....Y....
""", {'Y': ('#F2C230', None, 'cyl')}),
}

def ess_icon(e):
    spec, mats = ESS_ART[e]
    return art(spec, mats, outline=True)

def ink_sketch(icon, seed=0):
    """Boceto a tinta y acuarela de un icono de 16x16: línea fina de tinta, aguada desplazada y sombreado a rayas."""
    rng = np.random.default_rng(seed)
    a = _up(np.asarray(icon), 2).astype(np.float64)       # 32x32
    S = a.shape[0] + 2
    big = np.zeros((S, S, 4))
    big[1:-1, 1:-1] = a
    m = big[..., 3] > 0
    lum = big[..., 0] * 0.3 + big[..., 1] * 0.59 + big[..., 2] * 0.11
    paper = _hx(PARCH[1])
    out = np.zeros((S, S, 4))
    # aguada: color algo desaturado hacia el papel, con grano, desplazada (+1, +1)
    g = lum[..., None]
    wash = big[..., :3] * 0.82 + g * 0.18
    wash = wash * 0.78 + paper * 0.22
    wa = np.where(m, 0.82 + (rng.random((S, S)) - 0.5) * 0.22, 0.0)
    wa = np.where(lum > 200, wa * 0.45, wa)
    wsh = np.roll(np.roll(wash, 1, 0), 1, 1)
    wash_a = np.roll(np.roll(wa, 1, 0), 1, 1)
    out[..., :3] = wsh
    out[..., 3] = wash_a
    # rayado en las zonas oscuras del objeto
    inside = m.copy()
    med = np.median(lum[m]) if m.any() else 128
    yy, xx = np.mgrid[0:S, 0:S]
    hatch = inside & (lum < med * 0.8) & ((xx + yy) % 3 == 0)
    ink = _hx(INK_C)
    def over(mask, color, alpha):
        al = out[..., 3]
        na = alpha + al * (1 - alpha)
        safe = np.where(na > 0, na, 1)
        out[..., :3] = np.where(mask[..., None], (color * alpha + out[..., :3] * al[..., None] * (1 - alpha)) / safe[..., None], out[..., :3])
        out[..., 3] = np.where(mask, na, al)
    over(hatch, ink, 0.42)
    # contorno de tinta: borde de la silueta (1 px)
    pad = np.pad(m, 1)
    edge = m & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    # líneas internas: saltos fuertes de luminancia
    dl = np.zeros_like(m)
    dl[:, :-1] |= (np.abs(lum[:, :-1] - lum[:, 1:]) > 70) & m[:, :-1] & m[:, 1:] & ((xx[:, :-1] % 2) == 1)
    dl[:-1, :] |= (np.abs(lum[:-1, :] - lum[1:, :]) > 70) & m[:-1, :] & m[1:, :] & ((yy[:-1, :] % 2) == 1)
    lines = edge | (dl & (lum < med))
    jitter = rng.random((S, S))
    over(lines & (jitter > 0.06), ink, 0.93)
    over(lines & (jitter <= 0.06), ink, 0.5)
    o = out.copy()
    o[..., 3] *= 255
    return np.clip(o, 0, 255).astype(np.uint8)

def _icon_src(name):
    for d in ('./salida/icons', os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../assets/icons')):
        p = os.path.join(d, name)
        if os.path.exists(p):
            return np.array(Image.open(p).convert('RGBA'))
    return None

UP_ART = {
    'cojin': ("""
................
................
................
..T..........T..
...CCCCCCCCCC...
..CCCCCCCCCCCC..
.CCCcCCCCCCcCCC.
.CCCCCCCCCCCCCC.
.CCCCCCdCCCCCCC.
.CCCCCCCCCCCCCC.
..CCCCCCCCCCCC..
...CCCCCCCCCC...
..T..........T..
................
................
................
""", {'C': ('#A0466E', None, 'cyl'), 'c': ('#D77AA0', None, 'flat'), 'd': ('#6E2A4A', None, 'flat'), 'T': ('#E8C04A', None, 'flat')}),
    'alfombra': ("""
................
................
................
..RRRRRRRRRRRo..
.RRRRRRRRRRRRoo.
.RYRYRYRYRYRRoOo
.RRRRRRRRRRRRoOo
.RBBBBBBBBBBRoOo
.RRRRRRRRRRRRoOo
.RYRYRYRYRYRRoOo
.RRRRRRRRRRRRoo.
..RRRRRRRRRRRo..
..F.F.F.F.F.F...
................
................
................
""", {'R': ('#B8402E', None, 'flat'), 'Y': ('#E9B44C', None, 'flat'), 'B': ('#3B5C8C', None, 'flat'), 'o': ('#8A2E22', None, 'flat'), 'O': ('#D8664A', None, 'flat'), 'F': ('#E9D9B0', None, 'flat')}),
    'caldero_ancho': ("""
................
................
................
................
.KKKKKKKKKKKKKK.
KKkkkkkkkkkkkkKK
KGGGGGGGGGGGGGGK
.KKKKKKKKKKKKKK.
.KKKKKKKKKKKKKK.
.KKKKKKKKKKKKKK.
..KKKKKKKKKKKK..
...KKKKKKKKKK...
...K........K...
..KK........KK..
................
................
""", {'K': ('#3E3A48', None, 'cyl'), 'k': ('#6A6478', None, 'flat'), 'G': ('#6CD6A8', None, 'flat')}),
    'huerto': ("""
................
....G.....G.....
...GGG...GGG.G..
..G.G.G.G.G.GGG.
....G.....G..G..
....G..G..G..G..
....G.GGG.G..G..
.PPPPPPPPPPPPPP.
.PdPPdPPPdPPdPP.
.PPPPPPPPPPPPPP.
.PPPPPPPPPPPPPP.
..PPPPPPPPPPPP..
................
................
................
................
""", {'G': ('#5DBA52', None, 'flat'), 'P': ('#B86A3E', None, 'cyl'), 'd': ('#7A3E20', None, 'flat')}),
    'estante': ("""
................
................
...A.....B......
..AAA...BBB..C..
..AAA...BBB.CCC.
..AAA..BBBBBCCC.
.WWWWWWWWWWWWWWW
.WWWWWWWWWWWWWWW
..ww.........ww.
..w...........w.
................
................
................
................
................
................
""", {'A': ('#7A5AE8', None, 'cyl'), 'B': ('#4ED0B0', None, 'cyl'), 'C': ('#E8784A', None, 'cyl'), 'W': ('#8A5A34', None, 'top'), 'w': ('#5A3A22', None, 'flat')}),
    'campanilla': ("""
................
.......SS.......
......S..S......
.......RR.......
......RRRR......
......BBBB......
.....BBBBBB.....
.....BBBBBB.....
....BBBBBBBB....
....BBBBBBBB....
...BBBBBBBBBB...
...BBBBBBBBBB...
..BBBBBBBBBBBB..
.......bb.......
................
................
""", {'S': ('#7A6A5A', None, 'flat'), 'R': ('#C0392B', None, 'flat'), 'B': ('#E8B848', None, 'shine'), 'b': ('#8A6A2A', None, 'flat')}),
    'farolillos': ("""
................
SSSSSSSSSSSSSSSS
...S.......S....
..MMM.....MMM...
.LLLLL...LLLLL..
.LYYYL...LYYYL..
.LYOYL...LYOYL..
.LYYYL...LYYYL..
.LLLLL...LLLLL..
..MMM.....MMM...
...T.......T....
................
................
................
................
................
""", {'S': ('#6A5A4A', None, 'flat'), 'M': ('#5A5668', None, 'flat'), 'L': ('#E8A84A', None, 'flat'), 'Y': ('#FFD88A', None, 'flat'), 'O': ('#FFF8E0', None, 'flat'), 'T': ('#C0392B', None, 'flat')}),
    'caldero_cobre': ("""
................
................
................
....KKKKKKKK....
...KkkkkkkkkK...
..KGGGGGGGGGGK..
..KKKKKKKKKKKK..
.KKKKKKKKKKKKKK.
.KKKKKKKKKKKKKK.
.KKKKKKKKKKKKKK.
..KKKKKKKKKKKK..
...KKKKKKKKKK...
....K......K....
...KK......KK...
................
................
""", {'K': ('#C8743A', None, 'shine'), 'k': ('#F0A060', None, 'flat'), 'G': ('#B48CFF', None, 'flat')}),
}

SMALL_ART = {
    'envelope': ("""
..............
.EEEEEEEEEEEE.
.EeEEEEEEEEeE.
.EEeEEEEEEeEE.
.EEEeEEEEeEEE.
.EEEEeRReEEEE.
.EEEEEeReEEEE.
.EEEEEEEEEEEE.
.EEEEEEEEEEEE.
..............
""", {'E': ('#EADBB8', None, 'flat'), 'e': ('#A27F52', None, 'flat'), 'R': ('#9E2B25', None, 'flat')}),
    'hourglass': ("""
.........
.WWWWWWW.
..GGGGG..
..GSSSG..
...GSG...
....G....
...GSG...
..GSSSG..
..GSSSG..
.WWWWWWW.
.........
""", {'W': ('#8A5A34', None, 'flat'), 'G': ('#BFE0E8', None, 'flat'), 'S': ('#E8C77A', None, 'flat')}),
    'bag': ("""
...........
....TTT....
...T...T...
....SSS....
..SSSSSSS..
.SSSSSSSSS.
.SSSSSSSSS.
.SSSSSSSSS.
..SSSSSSS..
...........
""", {'T': ('#5A3A22', None, 'flat'), 'S': ('#B08850', None, 'cyl')}),
    'lock': ("""
.........
...LLL...
..L...L..
..L...L..
.BBBBBBB.
.BBBkBBB.
.BBBkBBB.
.BBBBBBB.
.........
""", {'L': ('#8A8A96', None, 'flat'), 'B': ('#C9A15A', None, 'cyl'), 'k': ('#3A2618', None, 'flat')}),
    'person': ("""
.........
...HHH...
...HHH...
....H....
..BBBBB..
.BBBBBBB.
.BBBBBBB.
..BBBBB..
.........
""", {'H': ('#E8B890', None, 'flat'), 'B': ('#4E6B3A', None, 'cyl')}),
    'moon': ("""
..........
...MMMM...
..MMM.....
.MMM......
.MMM......
.MMM......
..MMM...M.
...MMMMM..
..........
""", {'M': ('#F2DE9A', None, 'cyl')}),
    'bottle': ("""
.........
...CCC...
...ggg...
...GGG...
..GGGGG..
.GGLGGGG.
.GGLGGGG.
.GGGGGGG.
..GGGGG..
.........
""", {'C': ('#8A5A34', None, 'flat'), 'g': ('#BFE0E8', None, 'flat'), 'G': ('#9B74E8', None, 'cyl'), 'L': ('#E8DCFF', None, 'flat')}),
    'page': ("""
..........
.PPPPPP...
.PPPPPPP..
.PlllPPPP.
.PPPPPPPP.
.PllllllP.
.PPPPPPPP.
.PllllPPP.
.PPPPPPPP.
..........
""", {'P': ('#F2E6C8', None, 'flat'), 'l': ('#8A6A4A', None, 'flat')}),
    'note': ("""
.........
....NN...
....N.N..
....N..N.
....N....
..NNN....
.NNNN....
..NN.....
.........
""", {'N': ('#3A2618', None, 'flat')}),
    'speaker': ("""
..........
....S.....
...SS..s..
.SSSS...s.
.SSSS.s.s.
.SSSS...s.
...SS..s..
....S.....
..........
""", {'S': ('#3A2618', None, 'flat'), 's': ('#6B4A2C', None, 'flat')}),
    'screen': ("""
...........
.FFFFFFFFF.
.F.......F.
.F.......F.
.F.......F.
.FFFFFFFFF.
.....F.....
...FFFFF...
...........
""", {'F': ('#3A2618', None, 'flat')}),
    'door': ("""
.........
..DDDDD..
.DDDDDDD.
.DDdDdDD.
.DDdDdDD.
.DDDDDYD.
.DDdDdDD.
.DDDDDDD.
.........
""", {'D': ('#8A5A34', None, 'cyl'), 'd': ('#5A3A22', None, 'flat'), 'Y': ('#E8C04A', None, 'flat')}),
    'star_ink': ("""
.........
....S....
....S....
.SSSSSSS.
..SSSSS..
...SSS...
..SS.SS..
.S.....S.
.........
""", {'S': ('#B3261E', None, 'flat')}),
}

EMBLEM = """
..........................
.........RRRRRRRR.........
.......RRbbbbbbbbRR.......
.....RRbbbbbbbbbbbbRR.....
....RbbbbbbbbbbbbbmbbR....
...RbbbbbbbbbbbbbmmmbbR...
...RbbbbbbbbbbbbbbmbbbR...
..RbbbbbbsbbbbbbbbbbbbbR..
..RbbbbbbbbbbbbbbbbbbbbR..
.RbbbbbbbbbbbbbbbbbbbbbbR.
.RbbbbbbKKKKKKKKKKbbbbbbR.
.RbbbbbKkkkkkkkkkkKbbbbbR.
.RbbbbbKGGGGGGGGGGKbbbbbR.
.RbbbbKKKKKKKKKKKKKKbbbbR.
.RbbbbKKKKKKKKKKKKKKbbbbR.
.RbbbbKKKKKKKKKKKKKKbbbbR.
..RbbbbKKKKKKKKKKKKbbbbR..
..RbbbbbKKKKKKKKKKbbbbbR..
...RbbbbbKbbbbbbKbbbbbR...
...RbbbFFFFFFFFFFFFbbbR...
....RbbbFFFFFFFFFFbbbR....
.....RRbbbbbbbbbbbbRR.....
.......RRbbbbbbbbRR.......
.........RRRRRRRR.........
..........................
"""

def emblem():
    return art(EMBLEM, {'R': ('#C9A15A', None, 'shine'), 'b': ('#2A2140', None, 'flat'), 'm': ('#F2DE9A', None, 'flat'),
                        's': ('#F2DE9A', 3, 'flat'), 'K': ('#C8743A', None, 'shine'), 'k': ('#F0A060', None, 'flat'),
                        'G': ('#6CD6A8', None, 'flat'), 'F': ('#E8783A', None, 'flat')}, outline=True)

def bubble9(seed):
    """Bocadillo de papel para el saludo del vendedor (9-patch, sin pico: el pico va aparte)."""
    return parchment9(seed, M=10, C=96, amp=1.0, ramp=['#FFFBEE', '#F6EEDA', '#EADBB8', '#CDB68A', '#B99B6B', '#A07D50', '#765536'])

def paper_all():
    made = []
    def keep(arr, name, k=1):
        _save(arr, name, k)
        made.append((name, np.asarray(arr)))
    # hojas sueltas del recetario y del diario (tamaño fijo: 290x380 a 1x, se ven a x2: 580x760)
    keep(parchment_sheet(290, 380, 11, stains=[("ring", 226, 300, 15)], bites=(1, 0, 0, 1)), 'paper_sheet_a.png', 2)
    keep(parchment_sheet(290, 380, 23, stains=[('ring', 62, 66, 11)], bites=(0, 1, 1, 0)), 'paper_sheet_b.png', 2)
    keep(parchment_sheet(290, 380, 37, stains=[], bites=(1, 1, 0, 0)), 'paper_sheet_c.png', 2)
    # nine-patch
    keep(parchment9(5), 'paper_sheet9.png', 2)
    keep(parchment9(9, amp=1.2, ramp=['#FFF9E6', '#F4EAD0', '#E8D9B4', '#D2BC90', '#BBA073', '#A38458', '#7A5A3A']), 'paper_card9.png', 2)
    keep(parchment9(14, amp=1.4, ramp=['#FFF6C8', '#F8EAA6', '#EED98E', '#D6BE74', '#BDA05C', '#A08448', '#7A6232']), 'paper_note9.png', 2)
    keep(wood9(3), 'paper_wood9.png', 2)
    keep(cork9(4), 'paper_cork9.png', 2)
    for c, hexc in (('verde', '#4E8B4A'), ('morado', '#7A4E9A'), ('rojo', '#A8443A'), ('naranja', '#C8743A'), ('azul', '#3E6A9A')):
        keep(cloth9(hexc, 6), 'paper_cloth_%s9.png' % c, 2)
    keep(sign9(8), 'paper_sign9.png', 2)
    keep(tab9(12), 'paper_tab9.png', 2)
    keep(tag9(3), 'paper_tag9.png', 2)
    keep(bubble9(15), 'paper_bubble9.png', 2)
    # adornos sueltos (1x; Godot los escala x3)
    keep(pin('#C8443C'), 'paper_pin_red.png')
    keep(pin('#C9A15A'), 'paper_pin_brass.png')
    keep(pin('#4E8B5A'), 'paper_pin_green.png')
    keep(pin('#5A6EC8'), 'paper_pin_blue.png')
    keep(tape(3), 'paper_tape.png')
    keep(stain_ring(4), 'paper_stain_ring.png')
    keep(stain_blot(5), 'paper_stain_blot.png')
    keep(wax_seal('#9E2B25', 6), 'paper_seal.png')
    keep(wax_seal('#5E5670', 7), 'paper_seal_grey.png')
    keep(wax_seal('#C9A15A', 8), 'paper_seal_gold.png')
    keep(fold('next'), 'paper_fold_next.png')
    keep(fold('next', True), 'paper_fold_next_hover.png')
    keep(fold('prev'), 'paper_fold_prev.png')
    keep(fold('prev', True), 'paper_fold_prev_hover.png')
    keep(stamp_x2(), 'paper_x2.png')
    keep(small_x2(), 'paper_x2_small.png')
    keep(emblem(), 'paper_emblem.png')
    for e in ESS_ART:
        keep(ess_icon(e), 'paper_ess_%s.png' % e)
    for k, (spec, mats) in UP_ART.items():
        keep(art(spec, mats, outline=True), 'paper_up_%s.png' % k)
    for k, (spec, mats) in SMALL_ART.items():
        keep(art(spec, mats, outline=k not in ('note', 'speaker', 'screen', 'star_ink')), 'paper_i_%s.png' % k)
    # bocetos a tinta de las pociones y los ingredientes
    n = 0
    for p in sorted(set(os.path.basename(f) for f in _glob.glob('./salida/icons/pot_*.png') + _glob.glob('./salida/icons/ing_*.png'))):
        src = _icon_src(p)
        if src is not None:
            keep(ink_sketch(src, n), 'paper_sk_' + p[:-4] + '.png')
            n += 1
    preview([m for _, m in made if m.shape[0] <= 200 and m.shape[1] <= 200], scale=3, cols=10, path='./prev_paper.png')
    print('paper:', len(made), 'imágenes')

paper_all()
# --- end R3 PAPER

# --- R3 BENCH: también en la ejecución normal
bench_all()
# --- end R3 BENCH
