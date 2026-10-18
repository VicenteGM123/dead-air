"""Pixel art de la magia (R3 MAGIC3: el libro de runas).
- Tintas: assets/icons/tinta_*.png (16x16, un tintero con pluma por esencia).
- Runas: assets/icons/rune_<id>.png (24x24): un medallón de latón con la runa trazada en el color de su tinta. La forma
  es la MISMA que el trazo del minijuego (los "points" de Data.RUNES, copiados abajo en RUNES).
- El libro: assets/ui/grimoire_*.png. grimoire_book.png (480x290, el juego lo dibuja a 3x = 1440x870): tapas de cuero
  violeta con esquinas de latón y dos páginas de pergamino; pestañas (marcapáginas), botón de cerrar, la etiqueta de la
  poción, nota clavada, botones de cuero y el medallón vacío de una runa sin aprender. Las piezas de 9 cortes (label,
  note, btn_*) se guardan YA a 3x (margen 3x) para dibujarlas nítidas con StyleBoxTexture.
Uso:  python3 magic_art.py [carpeta_assets]   (con carpeta: copia los PNG a <carpeta>/icons y <carpeta>/ui)
"""
import os, sys, shutil, math, random
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from PIL import Image, ImageDraw
from pixlib import *
from props import art

OUT = './salida'
for d in ('icons', 'ui'):
    os.makedirs(f'{OUT}/{d}', exist_ok=True)

ESS = {'fuego': '#ff7a45', 'escarcha': '#7fd4ff', 'vida': '#7ee08a', 'sombra': '#b48cff', 'luz': '#ffd84d'}
INK_ESS = {'tinta_brasa': 'fuego', 'tinta_escarcha': 'escarcha', 'tinta_savia': 'vida', 'tinta_umbra': 'sombra', 'tinta_alba': 'luz'}

# las runas: puntos del trazo (como Data.RUNES[id]["points"]) y su tinta
RUNES = {
    'prisa': ('tinta_brasa', [(0.62, 0.1), (0.3, 0.5), (0.68, 0.5), (0.38, 0.9)]),
    'dulzor': ('tinta_savia', [(0.34, 0.9), (0.34, 0.1), (0.74, 0.3), (0.34, 0.52)]),
    'calma': ('tinta_umbra', [(0.1, 0.52), (0.3, 0.3), (0.5, 0.5), (0.7, 0.7), (0.9, 0.48)]),
    'duracion': ('tinta_alba', [(0.2, 0.14), (0.2, 0.86), (0.8, 0.14), (0.8, 0.86), (0.2, 0.14)]),
    'frescor': ('tinta_escarcha', [(0.5, 0.1), (0.86, 0.5), (0.5, 0.9), (0.14, 0.5), (0.5, 0.1)]),
    'alas': ('tinta_alba', [(0.12, 0.72), (0.3, 0.22), (0.5, 0.56), (0.7, 0.22), (0.88, 0.72)]),
    'sigilo': ('tinta_umbra', [(0.5, 0.52), (0.66, 0.52), (0.66, 0.3), (0.3, 0.3), (0.3, 0.74), (0.86, 0.74)]),
    'fuerza': ('tinta_savia', [(0.26, 0.9), (0.26, 0.14), (0.74, 0.34), (0.74, 0.9)]),
}

# paleta del estilo (BRIEF3 §3): pergamino, tinta, lacre, latón, verde hierba, violeta noche
PARCH = '#eadbb8'
PARCH_D = '#cdb68a'
BURNT = '#a8865a'
INKC = '#3a2618'
WAX = '#9e2b25'
BRASS = '#c9a15a'
BRASS_L = '#f0d58a'
BRASS_D = '#8a6a2e'
NIGHT = '#3b2f52'


def rgb(h):
    return np.array(hexrgb(h), dtype=np.float64)


def lerp(a, b, t):
    return a + (b - a) * t


def blank(w, h):
    return np.zeros((h, w, 4), dtype=np.uint8)


def put(a, x, y, col, alpha=255):
    h, w = a.shape[:2]
    if 0 <= x < w and 0 <= y < h:
        c = col if not isinstance(col, str) else hexrgb(col)
        a[y, x, :3] = [int(max(0, min(255, v))) for v in c]
        a[y, x, 3] = alpha


def over(a, x, y, col, k):
    """Mezcla col sobre el píxel (k = 0..1)."""
    h, w = a.shape[:2]
    if 0 <= x < w and 0 <= y < h and a[y, x, 3] > 0:
        c = rgb(col) if isinstance(col, str) else np.array(col, dtype=np.float64)
        a[y, x, :3] = np.clip(lerp(a[y, x, :3].astype(np.float64), c, k), 0, 255).astype(np.uint8)


def poly_mask(w, h, pts, width, ss=8, close=False):
    """Máscara (h, w) de una línea quebrada con grosor 'width' (en píxeles finales), sobremuestreada."""
    im = Image.new('L', (w * ss, h * ss), 0)
    d = ImageDraw.Draw(im)
    P = [(x * ss, y * ss) for x, y in pts]
    if close:
        P = P + [P[0]]
    d.line(P, fill=255, width=max(1, int(round(width * ss))), joint='curve')
    r = width * ss / 2.0
    for x, y in P:
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    arr = np.asarray(im, dtype=np.float64).reshape(h, ss, w, ss).mean(axis=(1, 3)) / 255.0
    return arr > 0.42


# ------------------------------------------------------------------ tintas: tintero con pluma (como en la ronda 2)
INK = """
.............Qq.
............QQq.
...........QQq..
..........QQq...
.........QQq....
........QQq.....
.......dQd......
......dddd......
.....GGGGGG.....
...GGggggggGG...
..GggggggggggG..
..GLLLLLLLLLLG..
..GLhLLLLLLLLG..
..GLhLLLLLLLLG..
..GLLLLLLLLLLG..
...GGGGGGGGGG...
"""
ICONS = {}
for ink, ess in INK_ESS.items():
    col = ESS[ess]
    ICONS[ink] = art(INK, {'G': ('#2e2a44', None, 'flat'), 'g': ('#5a6a8a', None, 'flat'), 'L': (col, None),
                           'h': ('#ffffff', None, 'flat'), 'd': ('#2a2638', None, 'flat'), 'Q': ('#f4f0ff', None, 'flat'),
                           'q': ('#b9b0d0', None, 'flat')})


# ------------------------------------------------------------------ runas: medallón de latón con la runa (24x24)
def medallion(face_top='#3b2f52', face_bot='#211a30'):
    a = blank(24, 24)
    c = 11.5
    for y in range(24):
        for x in range(24):
            d = math.hypot(x - c, y - c)
            ang = math.atan2(y - c, x - c)          # luz desde arriba a la izquierda
            lit = -math.cos(ang + math.pi * 0.25)   # 1 arriba-izquierda, -1 abajo-derecha
            if d <= 11.75:
                put(a, x, y, '#1a1222')
            if d <= 10.9:
                if lit > 0.45:
                    col = BRASS_L
                elif lit < -0.35:
                    col = BRASS_D
                else:
                    col = BRASS
                put(a, x, y, col)
            if d <= 9.75:
                put(a, x, y, '#2a1f18')   # filo oscuro del bisel
            if d <= 8.95:
                t = (y + x) / 46.0
                put(a, x, y, lerp(rgb(face_top), rgb(face_bot), t))
    # remaches del aro (4 puntitos)
    for (x, y) in ((11, 1), (22, 11), (12, 22), (1, 12)):
        put(a, x, y, '#fff3c4' if x < 12 and y < 12 else BRASS_L)
    return a


def rune_icon(points, ink_hex):
    a = medallion()
    lo, hi = 5.2, 18.8
    pts = [(lo + px_ * (hi - lo), lo + py * (hi - lo)) for px_, py in points]
    m = poly_mask(24, 24, [(x + 0.5, y + 0.5) for x, y in pts], 2.15)
    glow = poly_mask(24, 24, [(x + 0.5, y + 0.5) for x, y in pts], 4.2)
    inkc = rgb(ink_hex)
    light = np.clip(inkc * 0.55 + 255 * 0.45, 0, 255)
    dark = inkc * 0.62
    for y in range(24):
        for x in range(24):
            d = math.hypot(x - 11.5, y - 11.5)
            if d > 8.95:
                continue
            if glow[y, x] and not m[y, x]:
                over(a, x, y, inkc, 0.33)
            if m[y, x]:
                up = y > 0 and m[y - 1, x]
                down = y < 23 and m[y + 1, x]
                col = inkc
                if not up:
                    col = light
                elif not down:
                    col = dark
                put(a, x, y, col)
    return a


def rune_locked():
    """Una runa que todavía no se sabe: solo un contorno punteado (página en blanco)."""
    a = blank(24, 24)
    for k in range(48):
        ang = k / 48.0 * math.tau
        if (k // 3) % 2 == 1:
            continue
        x = int(round(11.5 + math.cos(ang) * 10.4))
        y = int(round(11.5 + math.sin(ang) * 10.4))
        put(a, x, y, '#8a6e4a', 200)
    return a


for rid, (ink, pts) in RUNES.items():
    ICONS['rune_' + rid] = rune_icon(pts, ESS[INK_ESS[ink]])

UI = {}
UI['grimoire_rune_locked'] = rune_locked()


# ------------------------------------------------------------------ el libro abierto (480x290)
def leather_noise(w, h, seed):
    rnd = np.random.default_rng(seed)
    base = rnd.normal(0, 1, (h // 6 + 2, w // 6 + 2))
    big = np.kron(base, np.ones((6, 6)))[:h, :w]
    # suavizado barato
    big = (big + np.roll(big, 3, 0) + np.roll(big, 3, 1) + np.roll(big, -3, 0) + np.roll(big, -3, 1)) / 5.0
    fine = rnd.normal(0, 1, (h, w))
    return big * 0.035 + fine * 0.018


def rounded_inside(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.5


def book():
    W, H = 480, 290
    a = blank(W, H)
    x0, y0, x1, y1, R = 1, 2, 478, 283, 8
    noise = leather_noise(W, H, 7)
    lb = rgb(NIGHT)
    # tapas: cuero violeta con bisel (luz arriba a la izquierda) y un leve veteado diagonal
    for y in range(H):
        for x in range(W):
            if not rounded_inside(x, y, x0, y0, x1, y1, R):
                continue
            edge = not (rounded_inside(x - 1, y, x0, y0, x1, y1, R) and rounded_inside(x + 1, y, x0, y0, x1, y1, R)
                        and rounded_inside(x, y - 1, x0, y0, x1, y1, R) and rounded_inside(x, y + 1, x0, y0, x1, y1, R))
            vein = 0.03 * math.sin((x * 0.7 + y * 1.3) * 0.21) * math.sin(y * 0.05 + x * 0.013)
            col = lb * (1.0 + noise[y, x] * 1.4 + vein)
            if edge:
                col = rgb('#120c1c')
            elif x <= x0 + 2 or y <= y0 + 2:
                col = col * 1.32
            elif x >= x1 - 2 or y >= y1 - 2:
                col = col * 0.6
            put(a, x, y, col)

    def tool(inset, colr, k, r_add=3):
        for y in range(H):
            for x in range(W):
                on = rounded_inside(x, y, x0 + inset, y0 + inset, x1 - inset, y1 - inset, max(2, R - inset + r_add))
                inn = rounded_inside(x, y, x0 + inset + 1, y0 + inset + 1, x1 - inset - 1, y1 - inset - 1, max(2, R - inset + r_add - 1))
                if on and not inn:
                    over(a, x, y, colr, k)
    # doble filete dorado gofrado en el margen de las tapas
    tool(5, '#c9a15a', 0.9)
    tool(6, '#120c1c', 0.4)
    tool(9, '#b8924a', 0.55)
    # rombos dorados en el margen, a media altura y a medio ancho
    for (cx, cy) in ((8, 143), (471, 143)):
        for dy in range(-4, 5):
            for dx in range(-2, 3):
                if abs(dx) * 2 + abs(dy) <= 4:
                    put(a, cx + dx, cy + dy, BRASS_L if dy < 0 else BRASS)
    # esquineras de latón (triángulo con remache)
    def corner(cx, cy, sx, sy):
        S = 23
        for i in range(S):
            for j in range(S - i):
                x = cx + sx * i
                y = cy + sy * j
                if not rounded_inside(x, y, x0, y0, x1, y1, R):
                    continue
                d = i + j
                col = BRASS
                if d >= S - 2:
                    col = BRASS_D
                elif d == S - 3:
                    col = '#a8843e'
                elif (sy > 0 and j <= 1) or (sx > 0 and i <= 1):
                    col = BRASS_L
                elif (sy < 0 and j <= 1) or (sx < 0 and i <= 1):
                    col = '#d8b46a'
                put(a, x, y, col)
        rx, ry = cx + sx * 6, cy + sy * 6
        for dx, dy, c in ((0, 0, '#fff3c4'), (sx, 0, '#e8c87a'), (0, sy, '#e8c87a'), (sx, sy, '#6b5022')):
            put(a, rx + dx, ry + dy, c)
    corner(x0, y0, 1, 1)
    corner(x1, y0, -1, 1)
    corner(x0, y1, 1, -1)
    corner(x1, y1, -1, -1)
    # el bloque de páginas
    LX0, LX1, RX0, RX1, PT, PB = 17, 237, 242, 462, 14, 263
    GUT = (LX1 + RX0) / 2.0

    def page_top(x):
        g = abs(x - GUT)
        dip = int(round(4.0 * (1 - g / 30.0) ** 2)) if g < 30 else 0
        o = min(x - LX0, RX1 - x)
        curl = -1 if o < 10 else 0
        return PT + dip + curl

    def page_bot(x):
        g = abs(x - GUT)
        return PB - (int(round(2.5 * (1 - g / 30.0) ** 2)) if g < 30 else 0)

    # cantos de las hojas (el grosor del libro): debajo y a los lados, siguiendo la curva
    for k, colh in ((5, '#9c8358'), (4, '#cdb68a'), (3, '#e8d8b0'), (2, '#c4ab7c'), (1, '#e3d2ab')):
        for x in range(LX0 - k, RX1 + k + 1):
            g = abs(x - GUT)
            if g < 3:
                continue
            xb = min(max(x, LX0), RX1)
            yb = page_bot(xb) + k - (1 if g < 14 else 0)
            put(a, x, yb, colh)
        for y in range(PT + 3, PB + 1 + k):
            put(a, LX0 - k, y, colh)
            put(a, RX1 + k, y, colh)
    for x in range(LX0 - 5, RX1 + 6):
        if abs(x - GUT) >= 3:
            put(a, x, page_bot(min(max(x, LX0), RX1)) + 6, '#4a3622')
    # las dos hojas de pergamino
    rnd = random.Random(3)
    pn = np.random.default_rng(11).normal(0, 1, (H, W))
    blot = leather_noise(W, H, 21)
    pc, pd, pb = rgb(PARCH), rgb(PARCH_D), rgb(BURNT)
    for x in list(range(LX0, LX1 + 1)) + list(range(RX0, RX1 + 1)):
        left = x <= LX1
        outer = (x - LX0) if left else (RX1 - x)          # distancia al canto exterior
        gut = (LX1 - x) if left else (x - RX0)            # distancia al lomo
        t0, t1 = page_top(x), page_bot(x)
        for y in range(t0, t1 + 1):
            # manchas de pergamino viejo: las oscuras tiran a marrón cálido, las claras a crema
            b = blot[y, x] * 14.0
            col = lerp(pc, rgb('#d2b07a'), min(1.0, -b) * 0.55) if b < 0 else lerp(pc, rgb('#f3e6c6'), min(1.0, b) * 0.5)
            # la hoja se curva hacia el lomo: sombra que se hace fuerte en los últimos píxeles
            if gut < 34:
                col = lerp(col, pd, (1 - gut / 34.0) ** 1.4 * 0.9)
            if gut < 9:
                col = lerp(col, pb, (1 - gut / 9.0) ** 1.2 * 0.85)
            if outer < 12:
                col = lerp(col, pd, (1 - outer / 12.0) ** 1.5 * 0.6)
            vy = min(y - t0, t1 - y)
            if vy < 8:
                col = lerp(col, pd, (1 - vy / 8.0) ** 1.5 * 0.5)
            col = col * (1.0 + pn[y, x] * 0.024)
            # canto quemado
            if outer == 0 or y == t0 or y == t1:
                col = lerp(col, pb, 0.8)
                if rnd.random() < 0.22:
                    col = rgb('#8a6a44')
            put(a, x, y, col)
    # fibras y motas
    for _ in range(240):
        x = rnd.randint(LX0 + 3, RX1 - 3)
        if abs(x - GUT) < 10:
            continue
        y = rnd.randint(PT + 5, PB - 5)
        L = rnd.randint(2, 8)
        colf = '#d4c094' if rnd.random() < 0.6 else '#f6ebd0'
        for i in range(L):
            if abs(x + i - GUT) > 8:
                over(a, x + i, y, colf, 0.6)
    for _ in range(420):
        x = rnd.randint(LX0 + 2, RX1 - 2)
        y = rnd.randint(PT + 3, PB - 3)
        if abs(x - GUT) > 8:
            over(a, x, y, '#b0946a' if rnd.random() < 0.7 else '#fff6e0', 0.4)
    # marco doble impreso en cada página, con florituras de tinta en las esquinas
    FLOUR = ["..xx...",
             ".x..x..",
             "x..x.x.",
             "x.x..x.",
             ".x...xx",
             "..xxx..",
             "......."]
    for (fx0, fx1) in ((LX0 + 11, LX1 - 15), (RX0 + 15, RX1 - 11)):
        fy0, fy1 = PT + 12, PB - 12
        for inset, colr, k in ((0, '#9c7f52', 0.6), (2, '#b89c6c', 0.45)):
            for x in range(fx0 + inset, fx1 - inset + 1):
                over(a, x, fy0 + inset, colr, k)
                over(a, x, fy1 - inset, colr, k)
            for y in range(fy0 + inset, fy1 - inset + 1):
                over(a, fx0 + inset, y, colr, k)
                over(a, fx1 - inset, y, colr, k)
        for (cx, cy, sx, sy) in ((fx0 + 4, fy0 + 4, 1, 1), (fx1 - 4, fy0 + 4, -1, 1), (fx0 + 4, fy1 - 4, 1, -1), (fx1 - 4, fy1 - 4, -1, -1)):
            for j, row in enumerate(FLOUR):
                for i, ch in enumerate(row):
                    if ch == 'x':
                        over(a, cx + sx * i, cy + sy * j, '#7a5e3e', 0.7)
        # un pequeño adorno a media altura del marco
        mx = (fx0 + fx1) // 2
        for dx in range(-6, 7):
            if abs(dx) != 1:
                over(a, mx + dx, fy0 + 2, '#9c7f52', 0.5)
                over(a, mx + dx, fy1 - 2, '#9c7f52', 0.5)
        for (yy) in (fy0 + 2, fy1 - 2):
            over(a, mx, yy - 1, '#7a5e3e', 0.7)
            over(a, mx, yy + 1, '#7a5e3e', 0.7)
    # el lomo: pliegue oscuro
    for y in range(PT + 3, PB + 1):
        put(a, LX1 + 1, y, '#5e4630')
        put(a, LX1 + 2, y, '#7a5e3e')
        put(a, RX0 - 1, y, '#6b5236')
    # cinta marcapáginas roja: sale de entre las hojas por abajo y cuelga
    for y in range(PB - 1, H):
        for x in range(232, 238):
            col = rgb(WAX)
            if x == 232:
                col = col * 1.3
            if x == 237:
                col = col * 0.68
            tip = y - (H - 6)
            if tip >= 0 and abs(x - 234.5) < tip * 0.9:
                continue   # corte en V
            put(a, x, y, col)
    return a


UI['grimoire_book'] = book()


# ------------------------------------------------------------------ pestañas (marcapáginas de tela) 52x24
def tab(base, light, dark):
    a = blank(52, 24)
    for y in range(24):
        for x in range(52):
            if not rounded_inside(x, y, 0, 0, 51, 30, 6):
                continue
            edge = not (rounded_inside(x - 1, y, 0, 0, 51, 30, 6) and rounded_inside(x + 1, y, 0, 0, 51, 30, 6)
                        and rounded_inside(x, y - 1, 0, 0, 51, 30, 6))
            col = rgb(base)
            if edge:
                col = rgb('#140c18')
            elif y <= 2 or x <= 2:
                col = rgb(light)
            elif x >= 49:
                col = rgb(dark)
            put(a, x, y, col)
    # pespunte
    for x in range(5, 47, 2):
        over(a, x, 4, '#f4e9cf', 0.45)
    return a


UI['grimoire_tab_on'] = tab(WAX, '#c4463c', '#6e1c18')
UI['grimoire_tab_off'] = tab('#4f4068', '#66558a', '#2f2542')
UI['grimoire_tab_hover'] = tab('#6a4a78', '#8a6a9a', '#3f2a52')


# ------------------------------------------------------------------ botón de cerrar (16x16): aro de latón con una X
def close_btn(hover=False):
    a = blank(16, 16)
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d <= 7.7:
                put(a, x, y, '#140c18')
            if d <= 6.8:
                put(a, x, y, BRASS_L if (x + y < 13) else BRASS)
            if d <= 5.4:
                put(a, x, y, '#5a2420' if hover else NIGHT)
    for i in range(4, 12):
        put(a, i, i, '#f4e9cf')
        put(a, 15 - i, i, '#f4e9cf')
    return a


UI['grimoire_close'] = close_btn()
UI['grimoire_close_hover'] = close_btn(True)


# ------------------------------------------------------------------ la etiqueta de la poción (una etiqueta colgante) 64x40
def tag():
    a = blank(64, 40)
    # forma: rectángulo con la punta izquierda cortada en chaflán
    for y in range(2, 38):
        for x in range(2, 62):
            cut = max(0, 9 - min(y - 2, 37 - y))
            if x - 2 < cut:
                continue
            put(a, x, y, PARCH)
    m = a[:, :, 3] > 0
    out = a.copy()
    for y in range(40):
        for x in range(64):
            if m[y, x]:
                edge = not (0 < x < 63 and 0 < y < 39 and m[y, x - 1] and m[y, x + 1] and m[y - 1, x] and m[y + 1, x])
                if edge:
                    out[y, x, :3] = hexrgb('#5a4228')
                else:
                    near = not (m[y, max(0, x - 2)] and m[y, min(63, x + 2)] and m[max(0, y - 2), x] and m[min(39, y + 2), x])
                    if near:
                        out[y, x, :3] = hexrgb(PARCH_D)
    a = out
    # marco impreso
    for x in range(14, 58):
        over(a, x, 6, '#8a6e4a', 0.55)
        over(a, x, 33, '#8a6e4a', 0.55)
    for y in range(6, 34):
        over(a, 57, y, '#8a6e4a', 0.55)
        over(a, 14, y, '#8a6e4a', 0.55)
    # ojal de latón
    for y in range(40):
        for x in range(64):
            d = math.hypot(x - 8.5, y - 19.5)
            if d <= 3.2:
                put(a, x, y, BRASS if d > 1.6 else '#3a2618')
                if 1.6 < d <= 3.2 and x + y < 28:
                    put(a, x, y, BRASS_L)
    return a


UI['grimoire_tag'] = tag()


# ------------------------------------------------------------------ piezas de 9 cortes (se guardan ya a 3x)
def up3(a):
    return np.kron(a, np.ones((3, 3, 1), dtype=np.uint8))


def label9():
    """La etiqueta grande donde se traza la runa: pergamino con esquinas cortadas y doble filete de tinta."""
    n = 30
    a = blank(n, n)
    rnd = np.random.default_rng(5).normal(0, 1, (n, n))
    for y in range(n):
        for x in range(n):
            c = min(x, y, n - 1 - x, n - 1 - y)
            corner = min(x, n - 1 - x) + min(y, n - 1 - y)
            if corner < 3:
                continue
            col = rgb(PARCH) * (1 + rnd[y, x] * 0.02)
            if c == 0 or corner == 3:
                col = rgb('#5a4228')
            elif c == 1:
                col = rgb(BURNT)
            elif c == 2:
                col = rgb(PARCH_D)
            elif c in (4, 6):
                col = lerp(col, rgb('#8a6e4a'), 0.6)
            put(a, x, y, col)
    return up3(a)


def note9():
    """Nota clavada (el pedido, la nota de la maestra): papel claro con el borde algo irregular."""
    n = 24
    a = blank(n, n)
    rnd = random.Random(9)
    for y in range(n):
        for x in range(n):
            c = min(x, y, n - 1 - x, n - 1 - y)
            if c == 0 and ((x + y) % 5 == 0):
                continue
            col = rgb('#f3e7c8')
            if c == 0:
                col = rgb('#b89c6c')
            elif c == 1:
                col = rgb('#e2d1aa')
            if rnd.random() < 0.05 and c > 1:
                col = col * 0.97
            put(a, x, y, col)
    return up3(a)


def btn9(face, rim, light, shadow):
    n = 16
    a = blank(n, n)
    for y in range(n):
        for x in range(n):
            c = min(x, y, n - 1 - x, n - 1 - y)
            corner = min(x, n - 1 - x) + min(y, n - 1 - y)
            if corner < 2:
                continue
            col = rgb(face)
            if c == 0 or corner == 2:
                col = rgb('#140c18')
            elif c == 1:
                col = rgb(rim)
            elif y == 2:
                col = rgb(light)
            elif y == n - 3:
                col = rgb(shadow)
            put(a, x, y, col)
    return up3(a)


UI['grimoire_label'] = label9()
UI['grimoire_note'] = note9()
UI['grimoire_btn'] = btn9('#4a3b63', BRASS, '#66558a', '#2a2140')
UI['grimoire_btn_hover'] = btn9('#5c4a7a', BRASS_L, '#7d6aa2', '#33284d')
UI['grimoire_btn_pressed'] = btn9('#2f2542', BRASS_D, '#3b2f52', '#1d1629')
UI['grimoire_btn_off'] = btn9('#4a4452', '#7a7064', '#5a5464', '#38333f')
UI['grimoire_btn_gold'] = btn9(WAX, BRASS_L, '#c4463c', '#6e1c18')


# ------------------------------------------------------------------ alfiler (para la nota clavada) 8x8
def pin():
    a = blank(8, 10)
    for y in range(10):
        for x in range(8):
            d = math.hypot(x - 3.5, y - 3.0)
            if d <= 3.1:
                put(a, x, y, '#140c18')
            if d <= 2.3:
                put(a, x, y, '#d0453a' if x + y < 6 else WAX)
    put(a, 2, 2, '#ff9a8a')
    for y in range(6, 10):
        put(a, 4, y, '#9a9aa8')
    return a


UI['grimoire_pin'] = pin()

if __name__ == '__main__':
    for k, v in ICONS.items():
        save(v, f'{OUT}/icons/{k}.png')
    for k, v in UI.items():
        save(v, f'{OUT}/ui/{k}.png')
    preview([ICONS[k] for k in ICONS], scale=8, cols=8, path='./prev_magic_icons.png')
    big = Image.fromarray(UI['grimoire_book'], 'RGBA').resize((480 * 2, 290 * 2), Image.NEAREST)
    big.save('./prev_magic_book.png')
    preview([UI[k] for k in UI if k != 'grimoire_book'], scale=4, cols=6, path='./prev_magic_ui.png')
    print('magic art ok:', len(ICONS), 'icons,', len(UI), 'ui')
    if len(sys.argv) > 1:
        dst = sys.argv[1]
        for k in ICONS:
            shutil.copy(f'{OUT}/icons/{k}.png', f'{dst}/icons/{k}.png')
        for k in UI:
            shutil.copy(f'{OUT}/ui/{k}.png', f'{dst}/ui/{k}.png')
        print('copiado a', dst)
