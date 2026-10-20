"""Pixel art de los eventos (R4 EVENTS): medallas, trofeos del estante, sellos de lacre de quien invita y el mapa de
Arvendal (el viaje al evento).
- assets/ui/evui_medal_{gold,silver,bronze,none}.png (26x34): la medalla de la tarjeta de resultados.
- assets/ui/evui_tick_{gold,silver,bronze}.png (9x11): las marcas de la barra de puntos del HUD.
- assets/ui/evui_seal_{academia,concurso,torneo}.png (24x24): el sello de lacre de la invitación (azul con un libro,
  verde con una hoja de roble, rojo con el sol de la Orden del Alba).
- assets/ui/evui_map.png (320x180): el mapa de Arvendal en pergamino (Godot dibuja encima el camino y el carro, y
  escribe los nombres). Las coordenadas de los lugares están en MAP_PLACES (las mismas en scripts/ui/event_ui.gd).
- assets/ui/evui_calendar.png (11x11), evui_trophy.png (11x13): iconos para la invitación y los premios.
- assets/props/evui_trophy_{academia,concurso,torneo}_{gold,silver,bronze}.png (16x22): trofeos del estante de la tienda.
Uso:  python3 events_ui_art.py [carpeta_assets]   (sin carpeta escribe en ./salida/ui y ./salida/props)
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from PIL import Image
from pixlib import hexrgb, ramp

ROOT = sys.argv[1] if len(sys.argv) > 1 else './salida'
UI = os.path.join(ROOT, 'ui')
PROPS = os.path.join(ROOT, 'props')
os.makedirs(UI, exist_ok=True)
os.makedirs(PROPS, exist_ok=True)

OUTLINE = (42, 26, 20)
PARCH = '#eadbb8'
INK = (58, 38, 24)

METAL = {
    'gold': ['#5c3a12', '#a8721e', '#e8b74a', '#f6dc86', '#fff6cf'],
    'silver': ['#3c4252', '#7a8496', '#bcc6d4', '#e2e8f0', '#ffffff'],
    'bronze': ['#3e2414', '#7c4a26', '#c98a52', '#e6b081', '#f7dcc0'],
    'none': ['#2e2a34', '#4f4858', '#77707f', '#99929f', '#b8b2bd'],
}
RIBBON = {'gold': ('#b8322a', '#f0c45a'), 'silver': ('#2f5a9e', '#dfe7f2'), 'bronze': ('#3f7a46', '#e9c58f'),
          'none': ('#6a6270', '#8f8698')}


def C(h):
    return tuple(hexrgb(h)) if isinstance(h, str) else tuple(h)


def blank(w, h):
    return np.zeros((h, w, 4), dtype=np.uint8)


def put(a, x, y, col, alpha=255):
    h, w = a.shape[:2]
    if 0 <= x < w and 0 <= y < h:
        a[y, x, :3] = C(col)
        a[y, x, 3] = alpha


def rect(a, x0, y0, x1, y1, col):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(a, x, y, col)


def disc(a, cx, cy, r, col, ry=None):
    ry = r if ry is None else ry
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if ((x + 0.5 - cx) / r) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                put(a, x, y, col)


def outline(a, col=OUTLINE):
    """Contorno oscuro de 1 px alrededor de lo opaco."""
    h, w = a.shape[:2]
    m = a[:, :, 3] > 0
    out = a.copy()
    for y in range(h):
        for x in range(w):
            if m[y, x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h and m[yy, xx]:
                    out[y, x, :3] = C(col)
                    out[y, x, 3] = 255
                    break
    return out


def save(a, path):
    Image.fromarray(a, 'RGBA').save(path)
    print('  ', path)

# ------------------------------------------------------------------ medallas


def medal(kind):
    w, h = 26, 34
    a = blank(w, h)
    m = METAL[kind]
    r1, r2 = RIBBON[kind]
    # la cinta en V (dos tiras con una raya clara)
    if kind != 'none':   # sin medalla: ni cinta ni anilla, solo el disco gris y agrietado
        for i in range(14):
            for k in range(5):
                xl = 5 + k + i // 3
                xr = 20 - k - i // 3
                col = r2 if k == 2 else r1
                put(a, xl, i, col)
                put(a, xr, i, col)
        rect(a, 9, 12, 16, 14, C(r1))
        rect(a, 11, 12, 14, 13, C(m[2]))
    # el disco con su canto
    cx, cy, r = 13.0, 23.0, 9.6
    disc(a, cx, cy, r, m[1])
    disc(a, cx - 0.4, cy - 0.4, r - 1.2, m[2])
    disc(a, cx - 1.2, cy - 1.4, r - 3.4, m[3])
    disc(a, cx - 0.2, cy - 0.2, r - 3.6, m[2])
    if kind != 'none':
        # una estrella en relieve (patrón fijo de 7x7, clara con el canto oscuro)
        star = ["...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", ".#...#."]
        sx, sy = int(cx) - 3, int(cy) - 3
        for yy, row in enumerate(star):
            for xx, ch in enumerate(row):
                if ch == '#':
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = xx + dx, yy + dy
                        if not (0 <= nx < 7 and 0 <= ny < 7 and star[ny][nx] == '#'):
                            put(a, sx + nx, sy + ny, m[1])
        for yy, row in enumerate(star):
            for xx, ch in enumerate(row):
                if ch == '#':
                    put(a, sx + xx, sy + yy, m[4] if yy < 3 else m[3])
        # brillo
        put(a, 7, 18, m[4])
        put(a, 8, 17, m[4])
        put(a, 7, 19, m[3])
    else:
        # sin medalla: una raya y una grieta
        rect(a, 10, 23, 16, 23, C(m[0]))
        for i, (x, y) in enumerate([(17, 16), (16, 17), (16, 18), (15, 19), (15, 20)]):
            put(a, x, y, m[0])
    return outline(a)


def _in_poly(x, y, pts):
    ins = False
    n = len(pts)
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi):
            ins = not ins
        j = i
    return ins


def tick(kind):
    a = blank(9, 11)
    m = METAL[kind]
    r1, r2 = RIBBON[kind]
    rect(a, 2, 0, 3, 3, C(r1))
    rect(a, 5, 0, 6, 3, C(r1))
    disc(a, 4.5, 6.5, 3.6, m[1])
    disc(a, 4.2, 6.2, 2.6, m[2])
    put(a, 3, 5, m[4])
    put(a, 4, 6, m[3])
    return outline(a)

# ------------------------------------------------------------------ sellos de lacre (quien invita)


def seal(base, crest):
    a = blank(24, 24)
    rng = random.Random(7)
    rmp = ramp(base)
    cx, cy = 11.5, 11.5
    # gota de lacre irregular
    for y in range(24):
        for x in range(24):
            ang = math.atan2(y - cy, x - cx)
            rr = 10.2 + 0.9 * math.sin(ang * 5 + 1.3) + 0.5 * math.sin(ang * 9)
            if math.hypot(x + 0.5 - cx - 0.5, y + 0.5 - cy - 0.5) <= rr:
                put(a, x, y, rmp[2])
    # sombra abajo a la derecha y luz arriba a la izquierda
    for y in range(24):
        for x in range(24):
            if a[y, x, 3] and (x + y) > 30 and a[min(23, y + 1), min(23, x + 1), 3] == 0:
                put(a, x, y, rmp[1])
            if a[y, x, 3] and (x + y) < 13:
                put(a, x, y, rmp[3])
    # el anillo hundido del sello
    for y in range(24):
        for x in range(24):
            d = math.hypot(x + 0.5 - 12, y + 0.5 - 12)
            if 6.6 <= d <= 7.6:
                put(a, x, y, rmp[1])
            elif 5.6 <= d < 6.6 and (x + y) < 24:
                put(a, x, y, rmp[3])
    light = rmp[4]
    dark = rmp[0]
    if crest == 'book':
        # un libro abierto: dos páginas que se curvan hacia el lomo
        for x in range(6, 18):
            dip = 1 if x in (11, 12) else 0
            top = 9 + dip + (1 if x in (6, 17) else 0)
            for y in range(top, 15 + dip):
                put(a, x, y, light)
            put(a, x, 15 + dip, dark)
        for y in range(10, 16):
            put(a, 11, y, dark)
        for x in (7, 8, 9, 14, 15, 16):
            put(a, x, 11, rmp[2])
            put(a, x, 13, rmp[2])
    elif crest == 'leaf':
        # una bellota (Robledal = robledal): sombrerito oscuro y fruto claro
        disc(a, 12, 13.8, 3.1, light, 3.4)
        for y in range(8, 12):
            half = 4.2 - (11 - y) * 0.6
            for x in range(int(12 - half), int(12 + half) + 1):
                put(a, x, y, dark if (x + y) % 2 else rmp[1])
        put(a, 12, 7, dark)
        put(a, 13, 6, dark)
        put(a, 11, 13, rmp[3])
        put(a, 11, 14, rmp[3])
    elif crest == 'sun':
        disc(a, 12, 12, 2.6, light)
        for i in range(8):
            ang = i * math.pi / 4
            for rr in (4.2, 5.1):
                put(a, int(round(12 + math.cos(ang) * rr - 0.5)), int(round(12 + math.sin(ang) * rr - 0.5)), light)
    return outline(a, (40, 18, 14))

# ------------------------------------------------------------------ trofeos del estante


def trophy(kind, medal_kind):
    w, h = 16, 22
    a = blank(w, h)
    m = METAL[medal_kind]
    wood = ['#2e1a10', '#4f2e1a', '#6e4428', '#8c5c38', '#a87850']
    # la peana de madera
    rect(a, 3, 18, 12, 21, C(wood[2]))
    rect(a, 3, 18, 12, 18, C(wood[3]))
    rect(a, 4, 20, 11, 20, C(wood[1]))
    if kind == 'concurso':
        # copa con dos asas
        rect(a, 6, 15, 9, 17, C(m[1]))
        rect(a, 7, 12, 8, 15, C(m[2]))
        for y in range(3, 12):
            half = 5 - max(0, (y - 7)) * 0.8
            for x in range(int(7.5 - half), int(8.5 + half)):
                put(a, x, y, m[2])
            put(a, int(7.5 - half), y, m[1])
        for y in range(4, 9):
            put(a, 1, y, m[2])
            put(a, 14, y, m[2])
        put(a, 2, 4, m[2]); put(a, 2, 8, m[2]); put(a, 13, 4, m[2]); put(a, 13, 8, m[2])
        rect(a, 4, 3, 11, 3, C(m[3]))
        for y in range(4, 9):
            put(a, 5, y, m[4] if y < 7 else m[3])
    elif kind == 'academia':
        # sombrero de mago con una estrella
        rect(a, 2, 15, 13, 17, C(m[1]))
        rect(a, 3, 15, 12, 15, C(m[3]))
        for y in range(2, 15):
            half = (y - 1) * 0.42
            for x in range(int(8 - half), int(8 + half) + 1):
                put(a, x, y, m[2])
            put(a, int(8 - half), y, m[3])
        put(a, 9, 1, m[2])
        put(a, 10, 1, m[2])
        put(a, 8, 9, m[4]); put(a, 7, 10, m[4]); put(a, 9, 10, m[4]); put(a, 8, 11, m[4]); put(a, 8, 10, m[4])
    else:
        # escudo con una espada detrás
        for y in range(1, 17):
            put(a, 8, y, m[3] if y > 2 else m[4])
        rect(a, 5, 3, 11, 3, C(m[1]))
        pts = [(3, 5), (13, 5), (13, 10), (8, 16), (3, 10)]
        for y in range(h):
            for x in range(w):
                if _in_poly(x + 0.5, y + 0.5, pts):
                    put(a, x, y, m[2])
        for y in range(6, 13):
            put(a, 8, y, m[1])
        for x in range(5, 12):
            put(a, x, 9, m[1])
        put(a, 5, 6, m[4]); put(a, 4, 7, m[3]); put(a, 4, 6, m[4])
    return outline(a)

# ------------------------------------------------------------------ iconos sueltos


def calendar():
    a = blank(11, 11)
    rect(a, 1, 2, 9, 9, C('#f2e6c8'))
    rect(a, 1, 2, 9, 3, C('#a3261f'))
    put(a, 3, 1, '#5e4632'); put(a, 7, 1, '#5e4632')
    for (x, y) in [(3, 5), (5, 5), (7, 5), (3, 7), (5, 7)]:
        put(a, x, y, '#5e4632')
    put(a, 7, 7, '#a3261f')
    return outline(a)


def trophy_icon():
    a = blank(11, 13)
    m = METAL['gold']
    rect(a, 3, 10, 7, 12, C('#6e4428'))
    rect(a, 4, 8, 6, 9, C(m[1]))
    for y in range(1, 8):
        half = 3.4 - max(0, y - 4) * 0.7
        for x in range(int(5 - half), int(5 + half) + 1):
            put(a, x, y, m[2])
    put(a, 3, 2, m[4]); put(a, 3, 3, m[3])
    put(a, 0, 2, m[2]); put(a, 0, 3, m[2]); put(a, 10, 2, m[2]); put(a, 10, 3, m[2])
    return outline(a)

# ------------------------------------------------------------------ el mapa de Arvendal

# lugares (en px del mapa; event_ui.gd usa los mismos): casa = su tienda al pie de la Montaña Gris
MAP_PLACES = {'casa': (70, 104), 'academia': (252, 50), 'concurso': (168, 132), 'torneo': (270, 140)}


def map_art():
    w, h = 320, 180
    rng = random.Random(11)
    p = np.array(C(PARCH), dtype=np.float64)
    a = blank(w, h)
    # pergamino con manchas y bordes quemados
    for y in range(h):
        for x in range(w):
            n = rng.random() * 10 - 5 + 6 * math.sin(x * 0.05 + y * 0.03) + 4 * math.sin(x * 0.013 - y * 0.07)
            edge = min(x, y, w - 1 - x, h - 1 - y)
            burn = max(0.0, 1.0 - edge / 9.0)
            col = p + n - burn * np.array([70, 80, 90])
            a[y, x, :3] = np.clip(col, 0, 255)
            a[y, x, 3] = 255 if edge > 0 or rng.random() < 0.5 else 0
    def ink(x, y, col=INK, alpha=255):
        if 0 <= x < w and 0 <= y < h:
            base = a[y, x, :3].astype(np.float64)
            a[y, x, :3] = np.clip(base * (1 - alpha / 255.0) + np.array(col) * (alpha / 255.0), 0, 255)
    # mar al este y el río
    for y in range(h):
        for x in range(w):
            shore = 300 + 8 * math.sin(y * 0.09) + 5 * math.sin(y * 0.23)
            if x > shore:
                ink(x, y, (120, 160, 180), 150 if (x + y) % 6 else 190)
    pts = [(150, 0), (148, 20), (140, 40), (146, 62), (160, 80), (156, 100), (140, 118), (130, 140), (118, 180)]
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2)
        for s in range(steps + 1):
            t = s / max(1, steps)
            xx = x0 + (x1 - x0) * t
            yy = y0 + (y1 - y0) * t
            for k in range(-1, 2):
                ink(int(xx) + k, int(yy), (96, 140, 168), 200 if k == 0 else 120)
    # la Montaña Gris (arriba a la izquierda)
    for (mx, my, mh) in [(40, 66, 44), (72, 70, 52), (104, 64, 38), (22, 74, 30), (58, 78, 30), (90, 80, 26)]:
        for y in range(my - mh, my + 1):
            half = (y - (my - mh)) * 0.82
            for x in range(int(mx - half), int(mx + half) + 1):
                shade = 0.82 if x < mx else 1.0
                col = np.array([128, 124, 130]) * shade
                if y < my - mh + mh * 0.3:
                    col = np.array([236, 236, 240]) * shade
                ink(x, y, tuple(col.astype(int)), 255)
            ink(int(mx - half) - 1, y, INK, 200)
            ink(int(mx + half) + 1, y, INK, 200)
    # bosques (Hojaplata abajo a la izquierda, robles alrededor de Robledal)
    def tree(x, y, col=(70, 110, 58)):
        for dy in range(-3, 1):
            for dx in range(-2, 3):
                if dx * dx + (dy + 1.5) ** 2 <= 5:
                    ink(x + dx, y + dy, col)
        ink(x, y + 1, (90, 60, 36))
        ink(x - 2, y - 2, INK, 140)
    for i in range(70):
        tree(rng.randint(14, 120), rng.randint(124, 170), (64, 104, 56))
    for i in range(26):
        tree(rng.randint(150, 205), rng.randint(110, 165), (86, 120, 54))
    for i in range(14):
        tree(rng.randint(200, 240), rng.randint(20, 60), (70, 100, 70))
    # su pueblo: una casita con humo y el caldero en el letrero
    def house(x, y, roof=(150, 70, 52)):
        for yy in range(y - 4, y + 1):
            for xx in range(x - 3, x + 4):
                ink(xx, yy, (236, 222, 196))
        for k in range(5):
            for xx in range(x - 4 + k, x + 5 - k):
                ink(xx, y - 5 - k, roof)
        ink(x, y - 1, INK)
        ink(x, y, INK)
    house(70, 104)
    house(78, 106, (100, 90, 140))
    house(62, 107, (150, 110, 60))
    for i in range(4):
        ink(73 + i // 2, 94 - i, (150, 150, 160), 160)
    # Robledal: casitas entre robles
    for (x, y) in [(162, 132), (170, 130), (176, 135), (166, 137)]:
        house(x, y, (160, 76, 56))
    # Valmora: las torres de la Academia (y unas ruinas viejas)
    for (x, top) in [(246, 34), (254, 28), (262, 36)]:
        for yy in range(top, 54):
            for xx in range(x - 2, x + 3):
                ink(xx, yy, (210, 204, 220))
            ink(x - 3, yy, INK, 200)
            ink(x + 3, yy, INK, 200)
        for k in range(4):
            for xx in range(x - 3 + k, x + 4 - k):
                ink(xx, top - 1 - k, (70, 80, 150))
        ink(x, top + 6, (240, 220, 120))
    for xx in range(236, 272):
        ink(xx, 54, INK, 220)
    for (x, y) in [(232, 58), (276, 57)]:
        for yy in range(y - 4, y + 1):
            ink(x, yy, (150, 146, 156))
    # Brisaclara: las tiendas del torneo con banderines
    for (x, col) in [(262, (180, 60, 50)), (272, (60, 90, 160)), (282, (200, 160, 60))]:
        for k in range(6):
            for xx in range(x - k, x + k + 1):
                ink(xx, 138 + k, col)
        ink(x, 137, INK)
        ink(x, 136, INK)
        ink(x + 1, 135, (220, 60, 50))
        ink(x + 2, 135, (220, 60, 50))
    for xx in range(256, 290):
        ink(xx, 146, (110, 80, 50), 200)
    # caminos (punteados tenues) desde su casa
    roads = [[(70, 104), (100, 98), (128, 86), (152, 74), (190, 66), (222, 58), (252, 50)],
             [(70, 104), (96, 114), (122, 122), (146, 128), (168, 132)],
             [(70, 104), (96, 114), (122, 122), (146, 128), (176, 140), (210, 146), (240, 146), (270, 140)]]
    for road in roads:
        for i in range(len(road) - 1):
            (x0, y0), (x1, y1) = road[i], road[i + 1]
            steps = int(max(abs(x1 - x0), abs(y1 - y0)))
            for s in range(0, steps, 3):
                t = s / max(1, steps)
                ink(int(x0 + (x1 - x0) * t), int(y0 + (y1 - y0) * t), (150, 120, 84), 170)
    # rosa de los vientos (abajo a la derecha, en el mar no: sobre tierra)
    cx, cy = 222, 104
    for i in range(-7, 8):
        ink(cx + i, cy, INK, 150)
        ink(cx, cy + i, INK, 150)
    for k in range(1, 5):
        ink(cx + k, cy - k, INK, 90); ink(cx - k, cy + k, INK, 90); ink(cx + k, cy + k, INK, 90); ink(cx - k, cy - k, INK, 90)
    for (dx, dy) in [(0, -8), (0, -9)]:
        ink(cx + dx, cy + dy, (163, 38, 31))
    # marco a tinta
    for x in range(4, w - 4):
        ink(x, 4, INK, 120)
        ink(x, h - 5, INK, 120)
    for y in range(4, h - 4):
        ink(4, y, INK, 120)
        ink(w - 5, y, INK, 120)
    return a


def main():
    print('events_ui_art ->', ROOT)
    for k in ('gold', 'silver', 'bronze', 'none'):
        save(medal(k), f'{UI}/evui_medal_{k}.png')
    for k in ('gold', 'silver', 'bronze'):
        save(tick(k), f'{UI}/evui_tick_{k}.png')
    save(seal('#3d5aa8', 'book'), f'{UI}/evui_seal_academia.png')
    save(seal('#4e7a3a', 'leaf'), f'{UI}/evui_seal_concurso.png')
    save(seal('#9e2b25', 'sun'), f'{UI}/evui_seal_torneo.png')
    save(calendar(), f'{UI}/evui_calendar.png')
    save(trophy_icon(), f'{UI}/evui_trophy.png')
    save(map_art(), f'{UI}/evui_map.png')
    for kind in ('academia', 'concurso', 'torneo'):
        for m in ('gold', 'silver', 'bronze'):
            save(trophy(kind, m), f'{PROPS}/evui_trophy_{kind}_{m}.png')


if __name__ == '__main__':
    main()
