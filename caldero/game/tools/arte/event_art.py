"""Arte de los escenarios de los eventos (ronda 4, lane EVENTS-SCENES): la Academia de Magia de Valmora, el Concurso
de Pociones de Robledal (la plaza al atardecer) y la Feria del Torneo de Brisaclara (el campo de justas por la mañana).

Pixel art hecho por código, como world_art.py (PIL sin suavizado + rampas de color de pixlib; contorno "sel-out").
Texturas a 32 px por metro (como el suelo y las paredes de la tienda); sprites para 0.03-0.05 m por píxel.
Sale en ./salida/event y se copia a assets/event. Uso (desde una carpeta FUERA del proyecto de Godot):
    python3 <game>/tools/arte/event_art.py <game>/assets          -> todo
    python3 <game>/tools/arte/event_art.py --sheet hoja.png ...    -> además una hoja de contacto para revisar
"""
import os, sys, math, random, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from pixlib import ramp, hexrgb, shift
import world_art as W          # Cv (lienzo), rp (rampas), estanterías y libros

OUT = './salida/event'
os.makedirs(OUT, exist_ok=True)
Cv = W.Cv
rp = W.rp
MADE = []          # nombres (para la hoja de contacto)


def save(cv_or_img, name):
    im = cv_or_img.im if isinstance(cv_or_img, Cv) else cv_or_img
    if isinstance(im, np.ndarray):
        im = Image.fromarray(im, 'RGBA' if im.shape[2] == 4 else 'RGB')
    path = f'{OUT}/{name}.png'
    im.save(path)
    MADE.append(name)
    return path


def strip(frames):
    """Une cuadros (Cv o Image del mismo alto) en una tira horizontal."""
    ims = [f.im if isinstance(f, Cv) else f for f in frames]
    w = sum(i.width for i in ims)
    h = max(i.height for i in ims)
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    x = 0
    for i in ims:
        out.alpha_composite(i, (x, h - i.height))
        x += i.width
    return out


def normal_from_height(h, strength=2.0):
    """Mapa de normales (RGB) a partir de una altura 0..1 (se repite en los bordes: textura que se repite)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def c3(col):
    return np.array(hexrgb(col) if isinstance(col, str) else col, dtype=np.float32)


def mix(a, b, t):
    a, b = c3(a), c3(b)
    return tuple(int(round(x)) for x in a + (b - a) * t)


# pequeños emblemas (9x9) para estandartes, vidrieras y escudos: '#' = color del emblema, '+' = brillo
EMBLEMS = {
    'star': """
....#....
....#....
...###...
#########
.#######.
..##+##..
..##.##..
.##...##.
.#.....#.""",
    'flame': """
....#....
...##....
...###.#.
..####.#.
.#######.
.###+###.
.##+++##.
..#+++#..
...###...""",
    'leaf': """
....#....
...###...
.#.###.#.
.#######.
..##+##..
.###+###.
..##+##..
....#....
....#....""",
    'moon': """
...####..
..###....
.###.....
.##+.....
.##+.....
.###.....
..###....
...####..
.........""",
    'book': """
.........
.##...##.
#++#.#++#
#+++#+++#
#+++#+++#
#+++#+++#
##++#++##
..##.##..
.........""",
    'cauldron': """
..+...+..
...+.+...
.#######.
#########
#########
#########
.#######.
..##.##..
.........""",
    'oak': """
...###...
..#####..
.#######.
#########
.#######.
...+#+...
....#....
...###...
.........""",
    'lion': """
.##......
####.....
.####..#.
..#######
..######.
..##..##.
..#....#.
.##...##.
.........""",
    'tower': """
#.#.#.#..
#######..
.#####...
.##+##...
.##+##...
.#####...
.#####...
#######..
.........""",
}


def stamp_emblem(cv, key, x, y, col, hi=None, scale=1):
    rows = [r for r in EMBLEMS[key].strip('\n').split('\n')]
    for j, r in enumerate(rows):
        for i, ch in enumerate(r):
            if ch == '#' or (ch == '+' and hi is None):
                cv.rect(x + i * scale, y + j * scale, scale, scale, col)
            elif ch == '+':
                cv.rect(x + i * scale, y + j * scale, scale, scale, hi)


# ================================================================== ACADEMIA DE MAGIA DE ARVENDAL

def aca_floor():
    """Suelo de mármol: losas octogonales color crema con rombos de mármol verde oscuro entre ellas (2x2 m)."""
    S = 64
    rnd = random.Random(41)
    cream = rp('#d9c9a8')
    dark = rp('#3f5a56')
    a = np.zeros((S, S, 3), np.uint8)
    hgt = np.zeros((S, S), np.float32)
    for y in range(S):
        for x in range(S):
            cx, cy = x % 32, y % 32
            # distancia "diamante" a la esquina más cercana de la celda
            dxc = min(cx, 31 - cx)
            dyc = min(cy, 31 - cy)
            corner = dxc + dyc
            if corner < 8:
                # rombo oscuro (lo forman las 4 esquinas cortadas de las losas vecinas)
                lv = 2
                if corner == 7:
                    lv = 1
                elif (cx + cy) % 9 == 0:
                    lv = 3
                a[y, x] = dark[lv]
                hgt[y, x] = 0.55
            else:
                lv = 2
                # borde de la losa: biselado (arriba-izquierda claro, abajo-derecha oscuro)
                if cx == 0 or cy == 0 or corner == 8:
                    lv = 1
                elif cx == 1 or cy == 1:
                    lv = 3
                elif cx == 31 or cy == 31:
                    lv = 1
                a[y, x] = cream[lv]
                hgt[y, x] = 0.6 if lv != 1 else 0.35
    # vetas del mármol: líneas finas diagonales que serpentean
    for _ in range(9):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        ang = rnd.uniform(0.3, 1.2)
        for k in range(rnd.randint(10, 26)):
            ix, iy = int(x) % S, int(y) % S
            if hgt[iy, ix] >= 0.6:
                a[iy, ix] = cream[1] if rnd.random() < 0.6 else mix(cream[2], '#b8a888', 0.5)
            x += math.cos(ang) + rnd.uniform(-0.4, 0.4)
            y += math.sin(ang) + rnd.uniform(-0.4, 0.4)
            ang += rnd.uniform(-0.35, 0.35)
    # brillos sueltos
    for _ in range(24):
        x, y = rnd.randrange(S), rnd.randrange(S)
        if hgt[y, x] >= 0.6:
            a[y, x] = cream[4]
    save(Image.fromarray(a, 'RGB'), 'aca_floor')
    save(Image.fromarray(normal_from_height(hgt, 1.6), 'RGB'), 'aca_floor_n')


def aca_wall():
    """Sillares de piedra arenisca cálida (2x2 m): hileras de 0.25 m, bloques de 0.5-0.75 m, juntas finas."""
    S = 64
    rnd = random.Random(12)
    sand = rp('#c7b08e')
    sand2 = rp('#bca684')
    sand3 = rp('#cdb898')
    grout = hexrgb('#7d6a58')
    a = np.zeros((S, S, 3), np.uint8)
    hgt = np.zeros((S, S), np.float32)
    a[:, :] = grout
    y = 0
    row = 0
    while y < S:
        rh = 8
        x = -(rnd.choice([4, 8, 12]) if row % 2 else 0)
        while x < S:
            bw = rnd.choice([16, 16, 20, 24])
            pal = rnd.choice([sand, sand, sand2, sand3])
            for yy in range(0, rh - 1):
                for xx in range(0, bw - 1):
                    X, Y = (x + xx) % S, (y + yy) % S
                    lv = 2
                    if yy == 0 or xx == 0:
                        lv = 3
                    elif yy == rh - 2 or xx == bw - 2:
                        lv = 1
                    elif rnd.random() < 0.08:
                        lv = rnd.choice([1, 3])
                    a[Y, X] = pal[lv]
                    hgt[Y, X] = 0.7 if lv != 1 else 0.5
            # una muesca o grieta de vez en cuando
            if rnd.random() < 0.3:
                cx, cy = (x + rnd.randint(2, bw - 4)) % S, (y + rnd.randint(1, rh - 3)) % S
                a[cy, cx] = pal[0]
                hgt[cy, cx] = 0.3
            x += bw
        y += rh
        row += 1
    save(Image.fromarray(a, 'RGB'), 'aca_wall')
    save(Image.fromarray(normal_from_height(hgt, 2.2), 'RGB'), 'aca_wall_n')


def aca_carpet():
    """Alfombra del pasillo: carmesí con orla dorada y rombos (48x64 px = 1.5 x 2 m, se repite a lo largo)."""
    w, h = 48, 64
    cv = Cv(w, h)
    red = rp('#8e2433')
    gold = rp('#d9a948')
    blue = rp('#2f4a8a')
    cv.rect(0, 0, w, h, red[2])
    # trama: líneas finas cada 2 px más oscuras (lana)
    for y in range(0, h, 2):
        cv.rect(5, y, w - 10, 1, red[1] if (y // 2) % 3 == 0 else red[2])
    # orla
    for x0 in (0, w - 5):
        cv.rect(x0, 0, 5, h, blue[1])
        cv.rect(x0 + 1, 0, 3, h, gold[2])
        cv.rect(x0 + 2, 0, 1, h, gold[3])
        for y in range(0, h, 4):
            cv.px(x0 + 2, y, red[2])
    cv.rect(6, 0, 1, h, gold[1])
    cv.rect(w - 7, 0, 1, h, gold[1])
    # rombo central con estrella
    cx, cy = w // 2, h // 2
    for r in range(13, -1, -1):
        col = gold[2] if r > 11 else (blue[2] if r > 5 else gold[3])
        for dy in range(-r, r + 1):
            dx = r - abs(dy)
            cv.px(cx - dx, cy + dy, col)
            cv.px(cx + dx - 1, cy + dy, col)
    cv.px(cx - 1, cy - 1, '#fff4d0'); cv.px(cx, cy - 1, '#fff4d0')
    # medios rombos arriba y abajo (casan al repetirse)
    for yy, sgn in ((0, 1), (h - 1, -1)):
        for r in range(6):
            cv.rect(cx - (6 - r), yy + sgn * r, 2 * (6 - r), 1, gold[2] if r < 2 else blue[2])
    save(cv, 'aca_carpet')


GLASS = {
    # vidrieras: orla, joyas de la orla, cuarterones claros, fondo del medallón, emblema
    'a': dict(border='#2c4a9e', jewel='#f0c040', panes=['#c8dcf0', '#dce8f4', '#b4cce8', '#e8eef4'], med='#b03048',
              emb='star', embc='#ffd860', top='#e8b040'),
    'b': dict(border='#9a2638', jewel='#4a8ae0', panes=['#f4e2b8', '#f0d8a4', '#f8ecd0', '#e8cc98'], med='#2a4a9a',
              emb='moon', embc='#f0f0ff', top='#4ab070'),
    'c': dict(border='#2a7a52', jewel='#e05050', panes=['#d8ecd8', '#c8e4cc', '#e8f2e0', '#bcdcc4'], med='#6a3a9a',
              emb='cauldron', embc='#ffd060', top='#b04060'),
}
WIN_W, WIN_H, WIN_R = 40, 104, 30      # vidriera: ancho, alto y radio del arco apuntado (px)


def lancet_mask(w, h, r):
    """Máscara de una ventana con arco apuntado: (alto x ancho) bool; arco de radio r con centros en la línea de
    arranque. Devuelve la máscara y la altura del arranque."""
    rise = math.sqrt(r * r - (r - w / 2.0) ** 2)
    spring = int(math.ceil(rise))
    m = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            px, py = x + 0.5, y + 0.5
            if py >= spring:
                m[y, x] = True
            else:
                d1 = math.hypot(px - (w - r), py - spring)
                d2 = math.hypot(px - r, py - spring)
                m[y, x] = d1 <= r and d2 <= r
    return m, spring


def aca_glass(key):
    g = GLASS[key]
    rnd = random.Random(ord(key) * 7)
    m, spring = lancet_mask(WIN_W, WIN_H, WIN_R)
    cv = Cv(WIN_W, WIN_H)
    lead = '#2a2430'
    # cuarterones en rombo (plomo a 45º cada 8 px)
    for y in range(WIN_H):
        for x in range(WIN_W):
            if not m[y, x]:
                continue
            u, v = (x + y) // 7, (x - y + 200) // 7
            if (x + y) % 7 == 0 or (x - y + 200) % 7 == 0:
                cv.px(x, y, lead)
            else:
                rr = random.Random(u * 131 + v * 17 + ord(key))
                cv.px(x, y, rr.choice(g['panes']))
    # orla de color con joyas (dentro del borde)
    inner = m.copy()
    for _ in range(4):
        e = inner.copy()
        e[1:, :] &= inner[:-1, :]
        e[:-1, :] &= inner[1:, :]
        e[:, 1:] &= inner[:, :-1]
        e[:, :-1] &= inner[:, 1:]
        inner = e
    edge1 = m & ~inner
    br = rp(g['border'])
    k = 0
    for y in range(WIN_H):
        for x in range(WIN_W):
            if edge1[y, x]:
                ring_in = not (m[max(0, y - 1), x] and m[min(WIN_H - 1, y + 1), x] and m[y, max(0, x - 1)] and m[y, min(WIN_W - 1, x + 1)])
                if ring_in:
                    cv.px(x, y, lead)
                else:
                    cv.px(x, y, br[2] if (x + y) % 2 else br[3])
    # joyas en la orla, cada 9 px
    for y in range(4, WIN_H - 3, 9):
        for x in (2, WIN_W - 3):
            if m[y, x]:
                cv.rect(x - 1, y - 1, 2, 2, g['jewel'])
                cv.px(x - 1, y - 1, '#fff6d8')
    # línea de plomo entre la orla y el campo
    for y in range(WIN_H):
        for x in range(WIN_W):
            if inner[y, x] and not (inner[max(0, y - 1), x] and inner[min(WIN_H - 1, y + 1), x] and inner[y, max(0, x - 1)] and inner[y, min(WIN_W - 1, x + 1)]):
                cv.px(x, y, lead)
    # barras de hierro horizontales (sostienen el vidrio)
    for by in range(spring + 20, WIN_H - 6, 22):
        for x in range(WIN_W):
            if m[by, x]:
                cv.px(x, by, lead)
    # medallón principal con el emblema
    mx, my, mr = WIN_W // 2, spring + 16, 11
    med = rp(g['med'])
    for y in range(my - mr - 1, my + mr + 2):
        for x in range(mx - mr - 1, mx + mr + 2):
            d = math.hypot(x + 0.5 - mx, y + 0.5 - my)
            if d <= mr + 1.2:
                if d > mr:
                    cv.px(x, y, lead)
                elif d > mr - 2:
                    cv.px(x, y, g['jewel'] if (x * 3 + y) % 5 == 0 else br[2])
                else:
                    cv.px(x, y, med[2] if (x + y) % 3 else med[3])
    stamp_emblem(cv, g['emb'], mx - 9, my - 9, g['embc'], hi='#fffbe8', scale=2)
    # medallón pequeño abajo (una rosa de cuatro pétalos)
    sx, sy = WIN_W // 2, WIN_H - 22
    for y in range(sy - 6, sy + 7):
        for x in range(sx - 6, sx + 7):
            d = math.hypot(x + 0.5 - sx, y + 0.5 - sy)
            if d <= 6.2:
                cv.px(x, y, lead if d > 5.2 else med[3])
    for (dx, dy) in ((0, -3), (0, 3), (-3, 0), (3, 0)):
        cv.rect(sx + dx - 1, sy + dy - 1, 2, 2, g['top'])
    cv.rect(sx - 1, sy - 1, 2, 2, g['embc'])
    # rosetón en la punta del arco
    tx, ty = WIN_W // 2, spring // 2 + 3
    for y in range(ty - 5, ty + 6):
        for x in range(tx - 5, tx + 6):
            d = math.hypot(x + 0.5 - tx, y + 0.5 - ty)
            if d <= 5.2 and m[y, x]:
                cv.px(x, y, lead if d > 4.3 else g['top'])
    cv.rect(tx - 1, ty - 1, 2, 2, '#fff2c8')
    # brillos: unos cuarterones casi blancos (el sol los atraviesa)
    for _ in range(26):
        x, y = rnd.randrange(WIN_W), rnd.randrange(spring, WIN_H)
        if m[y, x] and cv.get(x, y)[:3] != hexrgb(lead):
            cv.px(x, y, '#fbfaf2')
    save(cv, f'aca_glass_{key}')
    return m


def aca_pool(key):
    """La luz de colores de una vidriera en el suelo (en Godot se SUMA sobre el suelo): los cuarterones del color de su
    vidrio, saturados; el plomo y lo de fuera del arco en negro (no suman nada: la sombra del plomo)."""
    g = GLASS[key]
    src = np.array(Image.open(f'{OUT}/aca_glass_{key}.png').convert('RGBA')).astype(np.float32)
    tint = np.array(hexrgb(g['border']), np.float32)
    tint = tint / max(1.0, tint.max())
    h, w = src.shape[:2]
    out = np.zeros((h, w, 4), np.float32)
    out[:, :, 3] = 255
    for y in range(h):
        for x in range(w):
            if src[y, x, 3] < 128:
                continue
            c = src[y, x, :3]
            if c.mean() < 70:
                continue                                          # plomo: no suma
            sat = c.max() - c.min()
            if sat < 60:                                          # cuarterón claro: luz del color de la orla
                out[y, x, :3] = 255.0 * (0.25 + 0.75 * tint) * 0.8
            else:                                                 # vidrio de color: su color, saturado
                m = c.mean()
                out[y, x, :3] = np.clip(m + (c - m) * 1.4, 0, 255)
    save(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA'), f'aca_pool_{key}')


def aca_window_frame():
    """Marco de piedra de la vidriera: moldura que sigue el arco, clave, alféizar. Transparente donde va el vidrio."""
    pad = 4
    w, h = WIN_W + 2 * pad, WIN_H + pad + 5
    m, spring = lancet_mask(WIN_W, WIN_H, WIN_R)
    big = np.zeros((h, w), bool)
    big[pad:pad + WIN_H, pad:pad + WIN_W] = m
    dil = big.copy()
    for _ in range(pad):
        d = dil.copy()
        d[1:, :] |= dil[:-1, :]
        d[:-1, :] |= dil[1:, :]
        d[:, 1:] |= dil[:, :-1]
        d[:, :-1] |= dil[:, 1:]
        dil = d
    frame = dil & ~big
    st = rp('#cbb592')
    wl = rp('#c7b08e')
    cv = Cv(w, h)
    # enjutas (las esquinas por encima del arco): sillares como la pared, para que el hueco del muro no se vea
    for y in range(h):
        for x in range(w):
            if not dil[y, x] and not big[y, x]:
                row = y // 5
                joint = (y % 5 == 4) or ((x + (6 if row % 2 else 0)) % 12 == 11)
                cv.px(x, y, wl[1] if joint else (wl[2] if (x * 7 + y * 3) % 13 else wl[3]))
    for y in range(h):
        for x in range(w):
            if frame[y, x]:
                # bisel: dentro (junto al vidrio) oscuro, fuera claro; luz de arriba a la izquierda
                inner = any(big[yy, xx] for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)) if 0 <= yy < h and 0 <= xx < w)
                outer = any(not dil[yy, xx] for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)) if 0 <= yy < h and 0 <= xx < w)
                lv = 2
                if inner:
                    lv = 0 if x > w // 2 else 1
                elif outer:
                    lv = 3 if (x < w // 2 or y < spring) else 1
                elif (x + y) % 11 == 0:
                    lv = 1
                cv.px(x, y, st[lv])
    # clave del arco
    cv.rect(w // 2 - 3, 0, 6, 6, st[2]); cv.rect(w // 2 - 3, 0, 6, 1, st[4]); cv.rect(w // 2 + 2, 0, 1, 6, st[1])
    # alféizar
    sy = pad + WIN_H
    cv.rect(0, sy, w, 5, st[2]); cv.rect(0, sy, w, 1, st[4]); cv.rect(0, sy + 4, w, 1, st[0]); cv.rect(0, sy + 1, w, 1, st[3])
    cv.outline(0.5)
    save(cv, 'aca_window_frame')


HOUSES = {
    'azul': ('#2f56a8', '#dfe6f0', 'star'),       # azul y plata, la estrella
    'rojo': ('#a8303a', '#e8c060', 'flame'),      # carmesí y oro, la llama
    'verde': ('#2f7a4c', '#d8a860', 'leaf'),      # esmeralda y bronce, la hoja de roble
    'violeta': ('#5f3f96', '#d8dcec', 'moon'),    # violeta y plata, la luna
}


def aca_banner(key):
    """Estandarte de una casa de la Academia: varilla de latón, paño con orla, emblema y cola de golondrina."""
    col, trim, emb = HOUSES[key]
    w, h = 20, 72
    cv = Cv(w, h)
    c = rp(col)
    t = rp(trim)
    brass = rp('#c99a48')
    # paño (cola de golondrina abajo)
    body_bot = 60
    cv.rect(2, 3, w - 4, body_bot - 3, c[2])
    cv.poly([(2, body_bot), (w // 2 - 1, body_bot), (2, h - 2)], c[2])
    cv.poly([(w // 2, body_bot), (w - 3, body_bot), (w - 3, h - 2)], c[2])
    # pliegues verticales: columnas más claras / más oscuras
    for x in range(2, w - 2):
        ph = math.sin((x - 2) / (w - 4) * math.pi * 2.2)
        lv = 3 if ph > 0.55 else (1 if ph < -0.55 else 2)
        if lv != 2:
            for y in range(3, h):
                if cv.get(x, y)[3] > 0:
                    cv.px(x, y, c[lv])
    # orla
    for y in range(3, body_bot):
        cv.px(3, y, t[2]); cv.px(w - 4, y, t[1])
    cv.rect(3, 4, w - 6, 1, t[3])
    cv.rect(3, body_bot - 6, w - 6, 1, t[2])
    cv.rect(3, body_bot - 4, w - 6, 1, t[1])
    # emblema
    stamp_emblem(cv, emb, w // 2 - 5, 13, t[3], hi=t[4])
    # franjas bajo el emblema
    cv.rect(4, 28, w - 8, 2, t[2]); cv.rect(4, 28, w - 8, 1, t[3])
    cv.rect(w // 2 - 2, 33, 4, 4, t[2]); cv.px(w // 2 - 1, 34, t[4])
    # flecos dorados en las puntas
    for (x, y) in ((2, h - 2), (3, h - 3), (w - 3, h - 2), (w - 4, h - 3)):
        cv.px(x, y, brass[3])
    cv.px(2, h - 1, brass[2]); cv.px(w - 3, h - 1, brass[2])
    # varilla con remates
    cv.rect(0, 1, w, 2, brass[2]); cv.rect(0, 1, w, 1, brass[4])
    cv.rect(0, 0, 2, 4, brass[1]); cv.rect(w - 2, 0, 2, 4, brass[1])
    cv.px(0, 0, brass[3]); cv.px(w - 2, 0, brass[3])
    cv.outline(0.5)
    save(cv, f'aca_banner_{key}')


def aca_bookcase(seed, name, w=80, h=214, shelves=10):
    """Estantería hasta el techo: costados con pilastras, cornisa tallada y diez baldas llenas de libros."""
    rnd = random.Random(seed)
    cv = Cv(w, h)
    wd = rp('#6a4430')
    # fondo
    cv.rect(4, 10, w - 8, h - 16, '#2c201b')
    for x in range(8, w - 6, 9):
        cv.rect(x, 10, 1, h - 16, '#241a16')
    # pilastras laterales
    for x0 in (0, w - 5):
        cv.rect(x0, 0, 5, h, wd[2]); cv.rect(x0, 0, 1, h, wd[3]); cv.rect(x0 + 4, 0, 1, h, wd[1])
        for y in range(16, h - 10, 24):
            cv.rect(x0 + 1, y, 3, 2, wd[3]); cv.rect(x0 + 1, y + 2, 3, 1, wd[0])
    # cornisa (tres molduras escalonadas) y una crestería
    cv.rect(0, 4, w, 7, wd[2]); cv.rect(0, 4, w, 1, wd[4]); cv.rect(0, 10, w, 1, wd[0])
    cv.rect(2, 2, w - 4, 2, wd[3]); cv.rect(4, 0, w - 8, 2, wd[2])
    for x in range(6, w - 6, 6):
        cv.rect(x, 7, 3, 2, wd[1])
    # zócalo
    cv.rect(0, h - 7, w, 7, wd[1]); cv.rect(0, h - 7, w, 1, wd[3]); cv.rect(4, h - 4, w - 8, 1, wd[0])
    inner_top, inner_bot = 11, h - 7
    step = (inner_bot - inner_top) / shelves
    decos = [W.deco_plant, W.deco_crystal, W.deco_hourglass, None, None, W.deco_crystal, None, W.deco_plant, None, None]
    rnd.shuffle(decos)
    for i in range(shelves):
        ybot = int(inner_top + step * (i + 1))
        ytop = int(inner_top + step * i)
        W.fill_shelf(cv, 5, w - 5, ybot - 2, (ybot - 2) - (ytop + 2), rnd, decos[i % len(decos)])
        cv.rect(5, ybot - 2, w - 10, 3, wd[2])
        cv.rect(5, ybot - 2, w - 10, 1, wd[4])
        cv.rect(5, ybot, w - 10, 1, wd[0])
    cv.outline(0.45)
    save(cv, name)


def aca_ladder():
    w, h = 18, 150
    cv = Cv(w, h)
    wd = rp('#8a5a3a')
    for x0 in (1, w - 4):
        cv.rect(x0, 2, 3, h - 2, wd[2]); cv.rect(x0, 2, 1, h - 2, wd[3]); cv.rect(x0 + 2, 2, 1, h - 2, wd[1])
    for y in range(8, h - 4, 9):
        cv.rect(4, y, w - 8, 2, wd[2]); cv.rect(4, y, w - 8, 1, wd[3])
    # gancho de latón arriba y ruedas abajo
    br = rp('#c99a48')
    cv.rect(2, 0, 2, 3, br[2]); cv.rect(w - 4, 0, 2, 3, br[2])
    cv.ell(0, h - 4, 5, 4, '#3a3036'); cv.ell(w - 5, h - 4, 5, 4, '#3a3036')
    cv.outline(0.45)
    save(cv, 'aca_ladder')


def aca_lectern():
    """Atril del profesor: pie escalonado, columna torneada, tablero inclinado con un libro grande abierto."""
    w, h = 28, 42
    cv = Cv(w, h)
    wd = rp('#6a4028')
    # pie
    cv.rect(5, h - 4, w - 10, 4, wd[2]); cv.rect(5, h - 4, w - 10, 1, wd[3]); cv.rect(5, h - 1, w - 10, 1, wd[0])
    cv.rect(8, h - 7, w - 16, 3, wd[2]); cv.rect(8, h - 7, w - 16, 1, wd[4])
    # columna torneada (bandas alternas)
    for y in range(17, h - 7):
        lv = 3 if (y // 2) % 2 == 0 else 2
        cv.rect(12, y, 4, 1, wd[lv]); cv.px(15, y, wd[1])
    cv.rect(10, 15, 8, 2, wd[2]); cv.rect(10, 15, 8, 1, wd[3])
    # tablero inclinado (más alto atrás)
    cv.poly([(1, 13), (w - 2, 13), (w - 2, 6), (1, 10)], wd[2])
    cv.poly([(1, 13), (w - 2, 13), (w - 2, 15), (1, 15)], wd[1])
    cv.line(1, 10, w - 2, 6, wd[3])
    # libro abierto sobre el tablero
    pg = rp('#efe2c0')
    cv.poly([(3, 10), (13, 8), (13, 11), (3, 12)], pg[3])
    cv.poly([(14, 8), (w - 4, 5), (w - 4, 9), (14, 11)], pg[2])
    cv.line(13, 7, 13, 11, pg[0])
    for i in range(3):
        cv.line(5, 10 - i, 11, 9 - i, '#8a7a68') if i < 2 else None
        cv.line(16, 9 - i, w - 6, 7 - i, '#8a7a68') if i < 2 else None
    cv.rect(3, 12, 10, 1, '#c99a48'); cv.rect(14, 11, w - 18, 1, '#c99a48')
    # cinta roja que cuelga
    cv.rect(12, 12, 1, 7, '#b8343c'); cv.px(12, 19, '#7a1e28'); cv.px(11, 19, '#b8343c')
    cv.outline(0.45)
    save(cv, 'aca_lectern')


def flame_frame(cv, x, y, f):
    """Llamita de vela (5x7) con tres cuadros de parpadeo; (x, y) = esquina de arriba a la izquierda."""
    shapes = [
        ["..o..", ".ooo.", ".oyo.", "oyyyo", "oywyo", ".oyo.", "..w.."],
        ["...o.", "..oo.", ".oyo.", ".oyyo", "oywyo", ".oyo.", "..w.."],
        [".o...", ".oo..", ".oyo.", "oyyo.", "oywyo", ".oyo.", "..w.."],
    ]
    cols = {'o': '#ff8a2a', 'y': '#ffd25a', 'w': '#fff6d8'}
    for j, row in enumerate(shapes[f]):
        for i, ch in enumerate(row):
            if ch in cols:
                cv.px(x + i, y + j, cols[ch])


def aca_float_candle():
    """Vela flotante (3 cuadros de 7x20 px): cera crema con chorreones y la llamita parpadeando."""
    frames = []
    wax = rp('#f0e4c8')
    for f in range(3):
        cv = Cv(7, 20)
        cv.rect(1, 8, 5, 12, wax[2]); cv.rect(1, 8, 1, 12, wax[3]); cv.rect(5, 8, 1, 12, wax[1])
        cv.rect(1, 8, 5, 1, wax[4])
        cv.px(2, 9, wax[4]); cv.rect(4, 9, 1, 3, wax[3])          # chorreones
        cv.rect(1, 19, 5, 1, wax[0])
        cv.px(3, 7, '#3a2a24')                                    # pabilo
        flame_frame(cv, 1, 0, f)
        frames.append(cv)
    save(strip(frames), 'aca_fcandle')


def aca_crest():
    """Escudo de la Academia: cuartelado azul y carmesí, libro abierto y estrella, laureles y cinta."""
    w, h = 40, 46
    cv = Cv(w, h)
    gold = rp('#d9a948')
    az = rp('#2f56a8')
    cr = rp('#a8303a')
    lf = rp('#5a8a44')
    # laureles a los lados
    for side in (-1, 1):
        for i in range(8):
            ang = math.radians(200 + i * 18) if side < 0 else math.radians(-20 - i * 18)
            x = w // 2 + side * 15 + int(math.cos(math.radians(90 + side * (i * 14 - 50))) * 2)
            y = 34 - i * 4
            cv.ell(x - 2 if side < 0 else x, y, 4, 3, lf[2 + (i % 2)])
    # escudo
    sx0, sx1, sy0, sy1 = 9, 31, 6, 36
    for y in range(sy0, sy1):
        t = (y - sy0) / (sy1 - sy0)
        half = (sx1 - sx0) / 2
        if t > 0.55:
            half *= math.sqrt(max(0.0, 1 - ((t - 0.55) / 0.45) ** 2))
        cx = (sx0 + sx1) / 2
        for x in range(int(cx - half), int(math.ceil(cx + half))):
            cv.px(x, y, az[2] if x < cx else cr[2])
    # orla dorada
    a = np.array(cv.im)
    solid = a[:, :, 3] > 0
    for y in range(h):
        for x in range(w):
            if solid[y, x]:
                nb = [(y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)]
                if any(not (0 <= yy < h and 0 <= xx < w and solid[yy, xx]) for yy, xx in nb):
                    if sx0 - 1 <= x <= sx1 and sy0 - 1 <= y <= sy1:
                        cv.px(x, y, gold[3] if y < 20 else gold[2])
    # libro abierto y estrella
    stamp_emblem(cv, 'book', w // 2 - 4, 20, '#4a3a2a', hi='#f4ecd8')
    stamp_emblem(cv, 'star', w // 2 - 4, 9, gold[3], hi=gold[4])
    # cinta
    rib = rp('#efe2c0')
    cv.poly([(4, 37), (w - 5, 37), (w - 3, 43), (w - 7, 41), (6, 41), (2, 43)], rib[2])
    cv.rect(6, 38, w - 12, 1, rib[3])
    for x in range(10, w - 10, 3):
        cv.px(x, 39, '#9a3a3a')
    # remate: estrellita
    cv.rect(w // 2 - 1, 1, 2, 4, gold[3]); cv.rect(w // 2 - 2, 2, 4, 2, gold[3]); cv.px(w // 2 - 1, 2, '#fff8e0')
    cv.outline(0.45)
    save(cv, 'aca_crest')


def aca_hourglass():
    """Reloj de arena de latón (2 cuadros: el hilo de arena cae)."""
    frames = []
    br = rp('#c99a48')
    gl = '#d8eef4'
    sand = rp('#e8c070')
    for f in range(2):
        cv = Cv(14, 22)
        cv.rect(0, 0, 14, 2, br[2]); cv.rect(0, 0, 14, 1, br[4]); cv.rect(0, 20, 14, 2, br[1]); cv.rect(0, 20, 14, 1, br[3])
        cv.rect(1, 2, 1, 18, br[2]); cv.rect(12, 2, 1, 18, br[1])
        # bulbos de vidrio
        for y in range(2, 20):
            t = abs(y - 11) / 9.0
            half = int(1 + 4 * t)
            cv.rect(7 - half, y, half * 2, 1, gl)
        # arena arriba (poca) y abajo (montoncito)
        cv.rect(5, 7, 4, 2, sand[2]); cv.rect(6, 9, 2, 1, sand[2])
        cv.poly([(3, 19), (10, 19), (7, 15)], sand[2]); cv.line(4, 18, 9, 18, sand[1])
        # hilo de arena
        for y in range(10, 16):
            if (y + f) % 2 == 0:
                cv.px(7, y, sand[3])
        cv.px(4, 5, '#ffffff'); cv.px(4, 16, '#ffffff')
        cv.outline(0.45)
        frames.append(cv)
    save(strip(frames), 'aca_hourglass')


def aca_owl():
    """Lechuza en su percha (3 cuadros: ojos abiertos, parpadeo, cabeza girada)."""
    frames = []
    br = rp('#8a6a4a')
    face = rp('#e8d8b8')
    for f in range(3):
        cv = Cv(16, 18)
        # cuerpo
        cv.ell(2, 5, 12, 12, br[2])
        cv.ell(4, 9, 8, 7, face[2])
        for (x, y) in ((5, 11), (8, 12), (6, 14), (9, 10)):
            cv.px(x, y, br[1])                      # motitas del pecho
        cv.rect(2, 8, 2, 7, br[1]); cv.rect(12, 8, 2, 7, br[3])   # alas
        # cabeza
        dx = 1 if f == 2 else 0
        cv.ell(3 + dx, 0, 10, 8, br[2])
        cv.px(3 + dx, 0, br[3]); cv.px(12 + dx, 0, br[1])          # orejitas
        cv.ell(4 + dx, 2, 4, 5, face[3]); cv.ell(8 + dx, 2, 4, 5, face[3])
        if f == 1:
            cv.rect(5 + dx, 4, 2, 1, br[0]); cv.rect(9 + dx, 4, 2, 1, br[0])
        else:
            for ex in (5, 9):
                cv.rect(ex + dx, 3, 2, 2, '#f0a020'); cv.px(ex + dx + (1 if f == 2 else 0), 4, '#1a1418')
        cv.px(7 + dx, 5, '#d08a30'); cv.px(8 + dx, 5, '#d08a30')       # pico
        # patas
        cv.px(6, 16, '#d08a30'); cv.px(9, 16, '#d08a30')
        cv.outline(0.45)
        frames.append(cv)
    save(strip(frames), 'aca_owl')


def aca_perch():
    w, h = 14, 44
    cv = Cv(w, h)
    wd = rp('#6a4428')
    cv.rect(6, 4, 2, h - 6, wd[2]); cv.px(6, 4, wd[3])
    cv.rect(0, 2, w, 2, wd[2]); cv.rect(0, 2, w, 1, wd[3])
    cv.rect(2, h - 3, w - 4, 3, wd[2]); cv.rect(2, h - 3, w - 4, 1, wd[3])
    cv.outline(0.45)
    save(cv, 'aca_perch')


def aca_armillary():
    """Esfera armilar de latón sobre un trípode: los aros giran (4 cuadros) y el sol del centro brilla."""
    frames = []
    br = rp('#c99a48')
    wd = rp('#6a4428')
    for f in range(4):
        cv = Cv(24, 34)
        cx, cy, r = 12, 11, 9
        # meridiano fijo
        for a in range(0, 360, 3):
            x = cx + r * math.cos(math.radians(a))
            y = cy + r * math.sin(math.radians(a))
            cv.px(int(round(x)), int(round(y)), br[2] if a < 180 else br[3])
        # aro que gira (elipse de ancho variable) y el ecuador inclinado
        k = math.cos(f * math.pi / 4)
        for a in range(0, 360, 4):
            x = cx + r * k * math.cos(math.radians(a))
            y = cy + r * math.sin(math.radians(a))
            cv.px(int(round(x)), int(round(y)), br[1] if math.sin(math.radians(a)) > 0 else br[4])
            x2 = cx + r * math.cos(math.radians(a))
            y2 = cy + r * 0.32 * math.sin(math.radians(a)) + (math.cos(math.radians(a)) * 2.2)
            cv.px(int(round(x2)), int(round(y2)), br[2])
        # sol
        cv.rect(cx - 1, cy - 1, 3, 3, '#ffd860'); cv.px(cx, cy, '#fff8e0')
        # eje y trípode
        cv.rect(cx, cy + r + 1, 1, 5, br[1])
        cv.rect(cx - 3, cy + r + 5, 7, 2, wd[2]); cv.rect(cx - 3, cy + r + 5, 7, 1, wd[3])
        cv.line(cx - 1, cy + r + 7, cx - 6, 33, wd[2]); cv.line(cx + 1, cy + r + 7, cx + 6, 33, wd[1]); cv.line(cx, cy + r + 7, cx, 33, wd[2])
        cv.outline(0.45)
        frames.append(cv)
    save(strip(frames), 'aca_armillary')


def aca_vials():
    """Gradilla con siete frascos iguales (las pociones del examen)."""
    w, h = 34, 14
    cv = Cv(w, h)
    wd = rp('#7a4c30')
    liq = rp('#3ab0c0')
    for i in range(7):
        x = 2 + i * 4 + (1 if i > 3 else 0)
        cv.rect(x, 3, 3, 8, '#cfe6ec')
        cv.rect(x, 6, 3, 5, liq[2]); cv.px(x, 6, liq[4]); cv.px(x + 2, 9, liq[1])
        cv.rect(x, 1, 3, 2, '#9a7048'); cv.px(x, 1, '#c09068')
    cv.rect(0, 9, w, 3, wd[2]); cv.rect(0, 9, w, 1, wd[3]); cv.rect(0, 12, w, 2, wd[1])
    cv.rect(1, 12, 2, 2, wd[0]); cv.rect(w - 3, 12, 2, 2, wd[0])
    cv.outline(0.45)
    save(cv, 'aca_vials')


def aca_flybook():
    """Libro que vuela aleteando (2 cuadros): tapas claras (en Godot se tiñe cada libro de un color) y páginas crema."""
    frames = []
    cover = rp('#d8d0c8')
    pg = rp('#f4ead2')
    for f in range(2):
        cv = Cv(16, 12)
        if f == 0:      # tapas arriba (V): se ven las páginas
            cv.poly([(8, 9), (0, 2), (2, 0), (8, 6)], cover[3])
            cv.poly([(8, 9), (15, 2), (13, 0), (8, 6)], cover[2])
            cv.poly([(8, 8), (2, 2), (4, 1), (8, 5)], pg[3]); cv.poly([(8, 8), (13, 2), (11, 1), (8, 5)], pg[2])
            cv.line(8, 5, 8, 9, cover[0])
        else:           # tapas abajo: el lomo arriba
            cv.poly([(8, 3), (0, 9), (2, 11), (8, 6)], cover[2])
            cv.poly([(8, 3), (15, 9), (13, 11), (8, 6)], cover[1])
            cv.poly([(8, 4), (3, 8), (8, 6)], pg[3]); cv.poly([(8, 4), (12, 8), (8, 6)], pg[2])
            cv.line(8, 3, 8, 6, cover[0])
        cv.outline(0.45)
        frames.append(cv)
    save(strip(frames), 'aca_flybook')


def aca_tablecloth():
    """Paño que cuelga por delante de la mesa de trabajo: azul de la Academia con orla dorada y el escudito."""
    w, h = 56, 20
    cv = Cv(w, h)
    c = rp('#2f4f96')
    g = rp('#d9a948')
    cv.rect(0, 0, w, h - 3, c[2])
    for x in range(0, w, 7):              # festón abajo
        cv.ell(x, h - 7, 7, 7, c[2])
    for x in range(0, w):
        ph = math.sin(x / w * math.pi * 5)
        if ph > 0.6:
            for y in range(1, h):
                if cv.get(x, y)[3] > 0:
                    cv.px(x, y, c[3])
        elif ph < -0.6:
            for y in range(1, h):
                if cv.get(x, y)[3] > 0:
                    cv.px(x, y, c[1])
    cv.rect(0, 0, w, 2, g[2]); cv.rect(0, 0, w, 1, g[3])
    for x in range(3, w, 7):
        cv.px(x, h - 2, g[3]); cv.px(x, h - 1, g[2])
    stamp_emblem(cv, 'book', w // 2 - 4, 5, g[2], hi='#f4ecd8')
    cv.outline(0.5)
    save(cv, 'aca_tablecloth')


def aca_cloth_end():
    """El paño en el extremo de su mesa (el que mira a la cámara): azul de la Academia, orla dorada y una estrella."""
    w, h = 22, 20
    cv = Cv(w, h)
    c = rp('#2f4f96')
    g = rp('#d9a948')
    cv.rect(0, 0, w, h - 3, c[2])
    for x in range(0, w, 5):
        cv.ell(x - 1, h - 7, 6, 7, c[2])
    for x in range(0, w, 4):
        for y in range(2, h - 1):
            if cv.get(x, y)[3] > 0:
                cv.px(x, y, c[1])
    cv.rect(0, 0, w, 2, g[2]); cv.rect(0, 0, w, 1, g[3])
    stamp_emblem(cv, 'star', w // 2 - 4, 5, g[3], hi=g[4])
    cv.outline(0.5)
    save(cv, 'aca_cloth_end')


def aca_light_pool():
    """Mancha de luz suave (para el suelo bajo las vidrieras y los rayos): blanco con borde difuso, se tiñe en Godot."""
    w, h = 32, 32
    a = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        for x in range(w):
            u, v = (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1
            d = max(abs(u), abs(v))
            al = max(0.0, min(1.0, (1.0 - d) * 2.2))
            a[y, x] = (255, 255, 255, int(al * 255))
    save(Image.fromarray(a, 'RGBA'), 'soft_rect')


def aca_medallion():
    """Rosa de los vientos de mármol incrustada en el suelo (96x96 px = 4.8 m): anillos verde, crema y latón, una
    estrella de ocho puntas y el libro de la Academia en el centro."""
    S = 96
    cv = Cv(S, S)
    c = S / 2.0
    green = rp('#3f5a56')
    cream = rp('#d9c9a8')
    brass = rp('#c99a48')
    red = rp('#8e2433')
    for y in range(S):
        for x in range(S):
            r = math.hypot(x + 0.5 - c, y + 0.5 - c)
            if r > 47.5:
                continue
            if r > 45.5:
                col = brass[1]
            elif r > 43.5:
                col = green[2] if (int(math.degrees(math.atan2(y - c, x - c)) + 360) // 15) % 2 else green[1]
            elif r > 42.5:
                col = brass[3]
            elif r > 34.5:
                col = cream[2] if (x + y) % 23 else cream[3]
            elif r > 33.5:
                col = brass[2]
            elif r > 30.5:
                col = red[2]
            elif r > 29.5:
                col = brass[3]
            else:
                col = cream[3]
            cv.px(x, y, col)
    # estrella de ocho puntas (cuatro grandes en verde, cuatro chicas en latón)
    for k in range(8):
        ang = k * math.pi / 4
        big = k % 2 == 0
        L = 40 if big else 26
        w = 6 if big else 4
        tip = (c + math.cos(ang) * L, c + math.sin(ang) * L)
        l1 = (c + math.cos(ang + math.pi / 2) * w, c + math.sin(ang + math.pi / 2) * w)
        l2 = (c + math.cos(ang - math.pi / 2) * w, c + math.sin(ang - math.pi / 2) * w)
        cv.poly([tip, l1, (c, c)], (green[2] if big else brass[2]))
        cv.poly([tip, l2, (c, c)], (green[3] if big else brass[3]))
    # centro: el libro abierto en un círculo crema
    for y in range(S):
        for x in range(S):
            r = math.hypot(x + 0.5 - c, y + 0.5 - c)
            if r <= 9.5:
                cv.px(x, y, brass[2] if r > 8.5 else cream[3])
    stamp_emblem(cv, 'book', int(c) - 9, int(c) - 9, '#4a3a2a', hi='#f4ecd8', scale=2)
    save(cv, 'aca_medallion')


def academia():
    aca_floor()
    aca_wall()
    aca_carpet()
    for k in GLASS:
        aca_glass(k)
        aca_pool(k)
    aca_window_frame()
    for k in HOUSES:
        aca_banner(k)
    aca_bookcase(3, 'aca_bookcase_a')
    aca_bookcase(8, 'aca_bookcase_b')
    aca_ladder()
    aca_lectern()
    aca_float_candle()
    aca_crest()
    aca_hourglass()
    aca_owl()
    aca_perch()
    aca_armillary()
    aca_vials()
    aca_flybook()
    aca_tablecloth()
    aca_cloth_end()
    aca_light_pool()
    aca_medallion()
    fx_confetti()


# ================================================================== CONCURSO DE POCIONES DE ROBLEDAL

FONT5 = {   # letras de 5x7 para los carteles pintados
    'F': ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    'I': ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
    'Z': ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    '!': ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
}


def text5(cv, x, y, txt, col, shadow=None, scale=1):
    for ch in txt:
        g = FONT5.get(ch)
        if g:
            for j, row in enumerate(g):
                for i, c in enumerate(row):
                    if c == '#':
                        if shadow:
                            cv.rect(x + i * scale + 1, y + j * scale + 1, scale, scale, shadow)
            for j, row in enumerate(g):
                for i, c in enumerate(row):
                    if c == '#':
                        cv.rect(x + i * scale, y + j * scale, scale, scale, col)
        x += 6 * scale


def con_skirt():
    """Faldón del escenario: tela roja con guirnaldas doradas y borlas (64x20 px = 2 x 0.62 m, se repite a lo ancho)."""
    w, h = 64, 20
    cv = Cv(w, h)
    red = rp('#a8303a')
    gold = rp('#e0b050')
    cv.rect(0, 0, w, h, red[2])
    for x in range(0, w, 4):                 # pliegues verticales
        cv.rect(x, 0, 1, h, red[1])
        cv.rect(x + 2, 0, 1, h, red[3])
    for x0 in range(0, w, 32):               # dos guirnaldas que cuelgan por tramo
        for x in range(32):
            y = int(2 + 6 * math.sin(math.pi * x / 31))
            cv.px(x0 + x, y, gold[3]); cv.px(x0 + x, y + 1, gold[2]); cv.px(x0 + x, y + 2, red[0])
        cv.rect(x0, 0, 2, 9, gold[2]); cv.rect(x0, 9, 2, 3, gold[3]); cv.px(x0, 12, gold[1])     # borla
    cv.rect(0, 0, w, 2, gold[2]); cv.rect(0, 0, w, 1, gold[4])
    cv.rect(0, h - 2, w, 2, red[0])
    save(cv, 'con_skirt')


def con_jury_cloth():
    """Paño de la mesa del jurado: terciopelo azul con flecos de oro y el roble de Robledal."""
    w, h = 96, 26
    cv = Cv(w, h)
    c = rp('#2c3f86')
    g = rp('#e0b050')
    cv.rect(0, 0, w, h - 4, c[2])
    for x in range(0, w, 6):
        cv.rect(x, 2, 2, h - 6, c[3])
        cv.rect(x + 4, 2, 1, h - 6, c[1])
    cv.rect(0, 0, w, 3, g[2]); cv.rect(0, 0, w, 1, g[4]); cv.rect(0, 3, w, 1, c[0])
    for x in range(0, w, 2):                 # flecos
        cv.rect(x, h - 4, 1, 4 - (x // 2) % 2, g[3] if x % 4 else g[2])
    cv.rect(0, h - 5, w, 1, g[1])
    # medallón con el roble
    cx, cy = w // 2, 12
    for y in range(cy - 8, cy + 9):
        for x in range(cx - 8, cx + 9):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if d <= 8.2:
                cv.px(x, y, g[2] if d > 6.8 else c[3])
    stamp_emblem(cv, 'oak', cx - 4, cy - 5, g[3], hi=g[4])
    cv.outline(0.5)
    save(cv, 'con_jury_cloth')


def con_chair():
    """Silla de respaldo alto del jurado: marco de madera tallada, terciopelo rojo y remates dorados."""
    w, h = 18, 40
    cv = Cv(w, h)
    wd = rp('#6a3c26')
    vel = rp('#a02838')
    g = rp('#e0b050')
    cv.rect(1, 2, w - 2, 26, wd[2]); cv.rect(1, 2, 1, 26, wd[3]); cv.rect(w - 2, 2, 1, 26, wd[1])
    cv.rect(3, 5, w - 6, 21, vel[2]); cv.rect(3, 5, w - 6, 1, vel[3])
    for (x, y) in ((5, 9), (9, 9), (12, 9), (7, 14), (11, 14), (5, 19), (9, 19), (12, 19)):
        cv.px(x, y, vel[4])
    cv.poly([(1, 3), (w // 2, -1), (w - 2, 3)], wd[2])
    cv.px(w // 2, 0, g[4]); cv.px(1, 1, g[3]); cv.px(w - 2, 1, g[3])
    cv.rect(0, 28, w, 3, wd[2]); cv.rect(0, 28, w, 1, wd[4])     # asiento
    cv.rect(1, 31, 2, h - 31, wd[1]); cv.rect(w - 3, 31, 2, h - 31, wd[1])
    cv.outline(0.45)
    save(cv, 'con_chair')


def con_title():
    """El gran estandarte sobre el escenario (el texto lo pone Godot con un Label3D): tela crema con orla roja y dorada,
    colas de golondrina."""
    w, h = 190, 26
    cv = Cv(w, h)
    cr = rp('#efe2c4')
    red = rp('#a8303a')
    g = rp('#e0b050')
    cv.rect(10, 2, w - 20, h - 4, cr[2])
    for side in (0, 1):
        x0 = 0 if side == 0 else w - 12
        if side == 0:
            cv.poly([(10, 2), (0, 2), (6, h // 2), (0, h - 3), (10, h - 3)], red[2])
        else:
            cv.poly([(w - 11, 2), (w - 1, 2), (w - 7, h // 2), (w - 1, h - 3), (w - 11, h - 3)], red[2])
    cv.rect(10, 2, w - 20, 2, red[2]); cv.rect(10, h - 5, w - 20, 2, red[2])
    cv.rect(10, 4, w - 20, 1, g[3]); cv.rect(10, h - 6, w - 20, 1, g[2])
    for x in range(12, w - 12, 3):           # costura
        cv.px(x, 6, cr[1]); cv.px(x, h - 8, cr[1])
    for x in range(10, w - 10):              # ondas suaves de la tela
        if math.sin(x / 9.0) > 0.93:
            for y in range(7, h - 8):
                cv.px(x, y, cr[3])
        elif math.sin(x / 9.0) < -0.93:
            for y in range(7, h - 8):
                cv.px(x, y, cr[1])
    cv.outline(0.45)
    save(cv, 'con_title')


def con_garland():
    """Guirnalda de hojas y flores que cuelga en curva (64x16 px)."""
    w, h = 64, 16
    cv = Cv(w, h)
    rnd = random.Random(14)
    lf = rp('#4f8a44')
    for x in range(w):
        y = int(2 + 8 * math.sin(math.pi * x / (w - 1)))
        cv.rect(x, y, 1, 3, lf[rnd.choice([1, 2, 2, 3])])
        if rnd.random() < 0.35:
            cv.px(x, y - 1, lf[3])
        if rnd.random() < 0.22:
            cv.px(x, y + 3, lf[1])
    for i in range(7):
        x = 4 + i * 9 + rnd.randint(-1, 1)
        y = int(2 + 8 * math.sin(math.pi * x / (w - 1)))
        col = rp(rnd.choice(['#f07080', '#ffd860', '#f4f0e8', '#c070e0']))
        cv.rect(x, y, 2, 2, col[2]); cv.px(x, y, col[4])
    cv.outline(0.45)
    save(cv, 'con_garland')


LANTERN_COLS = ['#e84a4a', '#f08a30', '#f6d060', '#e86aa0']


def con_lanterns():
    """Farolillos de papel: 4 colores (filas) x 2 cuadros (la luz de dentro tiembla). 12x15 px cada uno."""
    fw, fh = 12, 15
    sheet = Image.new('RGBA', (fw * 2, fh * len(LANTERN_COLS)), (0, 0, 0, 0))
    for r, col in enumerate(LANTERN_COLS):
        c = rp(col)
        for f in range(2):
            cv = Cv(fw, fh)
            cv.rect(4, 0, 4, 2, '#3a2a24')                         # sombrerete
            cv.ell(0, 2, fw, 11, c[3])
            cv.ell(2, 3, fw - 4, 9, c[4] if f == 0 else c[3])        # brillo de dentro
            cv.ell(4, 5, 4, 5, '#fff2c0' if f == 0 else '#ffe8a8')
            for x in (2, 5, 8):                                     # costillas
                for y in range(3, 12):
                    if cv.get(x, y)[3] > 0:
                        cv.px(x, y, c[2])
            cv.rect(4, 12, 4, 1, '#3a2a24')
            cv.px(6, 13, c[1]); cv.px(6, 14, c[1]); cv.px(5, 14, c[2])  # borla
            sheet.alpha_composite(cv.im, (f * fw, r * fh))
    save(sheet, 'con_lanterns')


def con_window_lit(shutter, name):
    """Ventana de casa al atardecer, con luz cálida dentro (y la silueta de una maceta)."""
    w, h = 26, 30
    cv = Cv(w, h)
    sh = rp(shutter)
    fr = rp('#5a3a2a')
    cv.rect(5, 3, 16, 20, fr[2])
    cv.rect(7, 5, 12, 16, '#ffd27a')
    cv.rect(7, 5, 12, 5, '#ffe6a8')
    cv.rect(12, 5, 2, 16, fr[1]); cv.rect(7, 12, 12, 1, fr[1])
    cv.rect(8, 17, 3, 4, '#7a4a3a'); cv.rect(15, 16, 3, 5, '#5a7a3a')   # siluetas dentro
    for x0 in (0, 21):
        cv.rect(x0, 3, 5, 20, sh[2]); cv.rect(x0, 3, 5, 1, sh[3])
        for y in range(5, 22, 3):
            cv.rect(x0 + 1, y, 3, 1, sh[1])
    cv.rect(3, 23, 20, 3, '#8a5a3a'); cv.rect(3, 23, 20, 1, '#aa7a50')
    cv.rect(5, 0, 16, 3, fr[2])
    cv.outline(0.45)
    save(cv, name)


def crowd_strip(seed, name, w=180, h=36, dusk=True):
    """Una fila de público pintada (2 cuadros: en el segundo algunos levantan los brazos). Cabezas y hombros."""
    rnd = random.Random(seed)
    skins = ['#f0c8a8', '#e0a882', '#c88a62', '#8a5a40', '#f4d8c0', '#b8d090']
    hairs = ['#3a2a24', '#7a4a2a', '#c8a050', '#d8d0c8', '#a03a2a', '#2a2a3a', '#e8c070']
    cloths = ['#7a3a4a', '#3a5a8a', '#5a7a3a', '#8a6a3a', '#6a4a7a', '#a8603a', '#3a6a6a', '#b0a080', '#9a3a3a']
    figs = []
    x = 2
    while x < w - 8:
        fw = rnd.randint(9, 12)
        figs.append(dict(x=x, w=fw, dy=rnd.randint(0, 6), skin=rnd.choice(skins), hair=rnd.choice(hairs),
                         cloth=rnd.choice(cloths), hat=rnd.random() < 0.3, raise_=rnd.random() < 0.4))
        x += fw - rnd.randint(1, 3)
    frames = []
    for f in range(2):
        cv = Cv(w, h)
        for fg in sorted(figs, key=lambda q: -q['dy']):
            bx, by, fw = fg['x'], 10 + fg['dy'], fg['w']
            cl = rp(fg['cloth'])
            sk = rp(fg['skin'])
            hr = rp(fg['hair'])
            cv.rect(bx, by + 8, fw, h - by - 8, cl[2]); cv.rect(bx, by + 8, 1, h - by - 8, cl[3]); cv.rect(bx + fw - 1, by + 8, 1, h - by - 8, cl[1])
            hx = bx + fw // 2 - 3
            cv.ell(hx, by, 7, 8, sk[2]); cv.px(hx + 1, by + 3, sk[3])
            cv.rect(hx, by - 1, 7, 3, hr[2]); cv.px(hx, by + 2, hr[2]); cv.px(hx + 6, by + 2, hr[1])
            if fg['hat']:
                hc = rp(rnd.choice(['#5a3a2a', '#7a5a3a', '#3a3a5a']))
                cv.rect(hx - 1, by - 1, 9, 2, hc[2]); cv.rect(hx + 1, by - 4, 5, 3, hc[2])
            if f == 1 and fg['raise_']:
                side = bx if (bx // 7) % 2 else bx + fw - 2
                cv.rect(side, by - 4, 2, 13, cl[2]); cv.rect(side, by - 6, 2, 2, sk[2])
        a = np.array(cv.im).astype(np.float32)
        if dusk:   # luz del atardecer: un poco más oscuros y violetas, con borde cálido arriba
            a[:, :, :3] = a[:, :, :3] * np.array([0.78, 0.7, 0.86])
        frames.append(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA'))
    cvs = []
    for im in frames:
        c = Cv(w, h)
        c.im = im
        c.d = ImageDraw.Draw(c.im)
        c.outline(0.5)
        cvs.append(c)
    save(strip(cvs), name)


def crowd_back(seed, name, w=200, h=44, dusk=True):
    """Público de espaldas (primer plano): cabezas con el pelo o el sombrero, hombros; en el segundo cuadro algunos
    levantan los brazos y saltan un poco."""
    rnd = random.Random(seed)
    hairs = ['#3a2a24', '#7a4a2a', '#c8a050', '#d8d0c8', '#a03a2a', '#2a2a3a', '#e8c070', '#5a3a2a']
    cloths = ['#7a3a4a', '#3a5a8a', '#5a7a3a', '#8a6a3a', '#6a4a7a', '#a8603a', '#3a6a6a', '#b0a080', '#9a3a3a']
    hats = ['#5a3a2a', '#7a5a3a', '#3a3a5a', '#8a2a2a', '#c8b070']
    figs = []
    x = 0
    while x < w - 6:
        fw = rnd.randint(13, 17)
        figs.append(dict(x=x, w=fw, dy=rnd.randint(0, 8), hair=rnd.choice(hairs), cloth=rnd.choice(cloths),
                         hat=rnd.choice(hats) if rnd.random() < 0.35 else None, raise_=rnd.random() < 0.45,
                         hop=rnd.random() < 0.3))
        x += fw - rnd.randint(2, 4)
    frames = []
    for f in range(2):
        cv = Cv(w, h)
        for fg in sorted(figs, key=lambda q: -q['dy']):
            bx, fw = fg['x'], fg['w']
            by = 10 + fg['dy'] - (2 if (f == 1 and fg['hop']) else 0)
            cl = rp(fg['cloth'])
            hr = rp(fg['hair'])
            cv.rect(bx, by + 9, fw, h - by - 9, cl[2]); cv.rect(bx, by + 9, fw, 1, cl[3])
            cv.rect(bx + fw - 2, by + 10, 2, h - by - 10, cl[1])
            hx = bx + fw // 2 - 4
            cv.ell(hx, by, 9, 10, hr[2]); cv.ell(hx + 1, by + 1, 4, 4, hr[3]); cv.rect(hx + 6, by + 3, 2, 5, hr[1])
            if fg['hat']:
                hc = rp(fg['hat'])
                cv.rect(hx - 2, by + 2, 13, 2, hc[2]); cv.rect(hx, by - 2, 9, 4, hc[2]); cv.rect(hx, by - 2, 9, 1, hc[3])
            if f == 1 and fg['raise_']:
                for side in (bx + 1, bx + fw - 3):
                    cv.rect(side, by - 5, 2, 15, cl[2]); cv.rect(side, by - 7, 2, 2, '#e8b898')
        a = np.array(cv.im).astype(np.float32)
        if dusk:
            a[:, :, :3] = a[:, :, :3] * np.array([0.7, 0.62, 0.8])
        c = Cv(w, h)
        c.im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA')
        c.d = ImageDraw.Draw(c.im)
        c.outline(0.5)
        frames.append(c)
    save(strip(frames), name)


def con_fizz_sign():
    """El letrero de Fizz: una explosión amarilla y naranja con FIZZ! en letras gordas y un frasquito."""
    w, h = 56, 34
    cv = Cv(w, h)
    cx, cy = w // 2, h // 2
    pts = []
    for k in range(24):
        ang = k * math.pi / 12
        r = (27 if k % 2 == 0 else 19) if k % 4 else 29
        pts.append((cx + math.cos(ang) * r, cy + math.sin(ang) * r * 0.58))
    cv.poly(pts, '#f08a30')
    pts2 = [(cx + (p[0] - cx) * 0.8, cy + (p[1] - cy) * 0.8) for p in pts]
    cv.poly(pts2, '#ffd25a')
    text5(cv, cx - 15, cy - 7, 'FIZZ!', '#b8343c', shadow='#6a1e3a', scale=1)
    # frasquito humeante
    cv.rect(cx + 15, cy - 1, 4, 6, '#7ad0a0'); cv.rect(cx + 16, cy - 3, 2, 2, '#cfe6ec'); cv.px(cx + 16, cy - 5, '#e8f8f0')
    cv.outline(0.45)
    save(cv, 'con_fizz_sign')


def con_fizz_still():
    """El alambique de cobre de Fizz (2 cuadros: burbujas): caldera, serpentín y matraces de colores."""
    frames = []
    cu = rp('#c87a48')
    gl = '#cfe6ec'
    for f in range(2):
        cv = Cv(44, 36)
        cv.ell(2, 14, 18, 18, cu[2]); cv.ell(4, 16, 8, 8, cu[3]); cv.px(6, 18, cu[4])           # caldera
        cv.rect(9, 6, 4, 10, cu[2]); cv.rect(9, 6, 1, 10, cu[3])                                 # cuello
        cv.line(12, 6, 26, 10, cu[2]); cv.line(12, 7, 26, 11, cu[1])                              # tubo
        for i in range(4):                                                                       # serpentín
            cv.ell(24, 10 + i * 4, 9, 4, cu[2] if i % 2 else cu[3])
        cv.rect(31, 18, 2, 6, cu[1])
        cv.ell(29, 24, 10, 11, gl); cv.ell(30, 28, 8, 7, '#7ad04a' if f == 0 else '#8ae05a')       # matraz verde
        cv.rect(32, 20, 4, 5, gl)
        cv.ell(16, 26, 8, 9, gl); cv.ell(17, 29, 6, 6, '#e05aa0' if f == 0 else '#f06ab0')        # matraz rosa
        for (bx, by) in ([(33, 27), (31, 30)] if f == 0 else [(34, 25), (32, 29)]):
            cv.px(bx, by, '#e8ffe0')
        cv.rect(0, 33, 44, 3, '#5a3a2a'); cv.rect(0, 33, 44, 1, '#7a5a3a')
        cv.outline(0.45)
        frames.append(cv)
    save(strip(frames), 'con_fizz_still')


def con_cup():
    """La copa del concurso (dorada) para la mesa del jurado."""
    w, h = 14, 18
    cv = Cv(w, h)
    g = rp('#e0b050')
    cv.poly([(1, 1), (12, 1), (10, 8), (3, 8)], g[2])
    cv.rect(2, 1, 2, 6, g[4])
    cv.ell(0, 2, 3, 5, g[1]); cv.ell(11, 2, 3, 5, g[1])
    cv.rect(6, 8, 2, 5, g[2]); cv.rect(3, 13, 8, 2, g[2]); cv.rect(2, 15, 10, 3, g[1]); cv.rect(2, 15, 10, 1, g[3])
    cv.outline(0.45)
    save(cv, 'con_cup')


def con_tray():
    """La bandeja de plata donde se presentan las tres pociones al jurado: tres cojines de terciopelo (vacíos)."""
    w, h = 26, 9
    cv = Cv(w, h)
    sv = rp('#c8ccd8')
    vel = rp('#a02838')
    cv.ell(0, 3, w, 6, sv[2]); cv.ell(1, 3, w - 2, 4, sv[3]); cv.rect(2, 7, w - 4, 1, sv[1])
    for x in (4, 11, 18):
        cv.ell(x, 2, 6, 4, vel[2]); cv.px(x + 2, 2, vel[4]); cv.px(x + 3, 4, vel[1])
    cv.outline(0.45)
    save(cv, 'con_tray')


def concurso():
    con_skirt()
    con_jury_cloth()
    con_chair()
    con_title()
    con_garland()
    con_lanterns()
    con_window_lit('#6a9a5a', 'con_window_a')
    con_window_lit('#4a7ab0', 'con_window_b')
    crowd_strip(3, 'con_crowd_a')
    crowd_strip(9, 'con_crowd_b')
    crowd_back(21, 'con_crowd_back_a')
    crowd_back(34, 'con_crowd_back_b')
    con_fizz_sign()
    con_fizz_still()
    con_cup()
    con_tray()


# ================================================================== FERIA DEL TORNEO

def tor_grass():
    """Hierba de la mañana (64x64 px = 2x2 m): verdes parecidos (sin manchas grandes), briznas, matas y florecitas."""
    S = 64
    rnd = random.Random(52)
    g = rp('#5f9a44')
    a = np.zeros((S, S, 3), np.uint8)
    for y in range(S):
        for x in range(S):
            v = math.sin(x * 0.39 + y * 0.23) + math.sin(x * 0.17 - y * 0.41) * 0.8 + rnd.uniform(-0.6, 0.6)
            a[y, x] = g[2] if v > -0.9 else g[1]
    for _ in range(260):                      # briznas
        x, y = rnd.randrange(S), rnd.randrange(S)
        a[y, x] = g[3]
        a[(y + 1) % S, x] = g[1]
    for _ in range(30):                       # matas
        x, y = rnd.randrange(S), rnd.randrange(S)
        for dx, dy in ((0, 0), (1, -1), (-1, -1), (0, -2)):
            a[(y + dy) % S, (x + dx) % S] = g[4] if dy == -2 else g[3]
    for _ in range(10):                       # florecitas
        x, y = rnd.randrange(S), rnd.randrange(S)
        a[y, x] = hexrgb(rnd.choice(['#f4f0e0', '#ffd860', '#e890b0', '#a8c8f0']))
    save(Image.fromarray(a, 'RGB'), 'tor_grass')


def tor_dirt():
    """Tierra apisonada del campo de justas (64x64 px): arena cálida con manchas suaves, piedritas y herraduras."""
    S = 64
    rnd = random.Random(61)
    d = rp('#b89468')
    a = np.zeros((S, S, 3), np.uint8)
    # ruido suave que se repite (suma de senos con frecuencias enteras) + grano
    for y in range(S):
        for x in range(S):
            u, v = x / S * 2 * math.pi, y / S * 2 * math.pi
            n = math.sin(u * 2 + math.sin(v * 3)) * 0.5 + math.sin(v * 2 + 1.3) * 0.4 + math.sin((u + v) * 3) * 0.3
            n += rnd.uniform(-0.45, 0.45)
            a[y, x] = d[1] if n < -0.55 else (d[3] if n > 0.75 else d[2])
    for _ in range(10):                       # herraduras
        x, y = rnd.randrange(S), rnd.randrange(S)
        for k in range(5):
            ang = math.pi * (0.15 + 0.7 * k / 4)
            a[int(y + 2 * math.sin(ang)) % S, int(x + 2 * math.cos(ang)) % S] = d[0]
    for _ in range(26):                       # piedritas
        x, y = rnd.randrange(S), rnd.randrange(S)
        a[y, x] = d[4]
        a[(y + 1) % S, x] = d[1]
    save(Image.fromarray(a, 'RGB'), 'tor_dirt')


def tor_trodden():
    """La tierra pisada delante del puesto y de la fila: mancha de bordes irregulares con mechones de hierba (para poner
    plana sobre la hierba). 160x64 px = 5 x 2 m."""
    w, h = 160, 64
    rnd = random.Random(8)
    d = rp('#a8865c')
    g = rp('#5f9a44')
    cv = Cv(w, h)
    for y in range(h):
        for x in range(w):
            u, v = (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1
            edge = 1.0 - (abs(u) ** 6 + abs(v) ** 4) ** 0.25
            edge += 0.12 * math.sin(x * 0.31) * math.cos(y * 0.47) + rnd.uniform(-0.07, 0.07)
            if edge > 0.02:
                n = math.sin(x * 0.21 + math.sin(y * 0.3) * 1.5) * 0.5 + rnd.uniform(-0.5, 0.5)
                col = d[1] if n < -0.5 else (d[3] if n > 0.6 else d[2])
                if edge < 0.09 and rnd.random() < 0.5:
                    col = g[2] if rnd.random() < 0.6 else g[1]
                cv.px(x, y, col)
    for _ in range(40):
        x, y = rnd.randrange(w), rnd.randrange(h)
        if cv.get(x, y)[3] > 0:
            cv.px(x, y, d[4])
    save(cv, 'tor_trodden')


STRIPES = {'rojo': ('#b8343c', '#f1e8d0'), 'azul': ('#2f5aa8', '#e8c060'), 'verde': ('#3f7a4c', '#f1e8d0'),
           'violeta': ('#6a4a9a', '#f1e8d0')}


def tor_stripes(key):
    """Lona a rayas para las tiendas (32x32 px; en Godot se envuelve en los conos y cilindros: rayas verticales)."""
    c1, c2 = STRIPES[key]
    r1, r2 = rp(c1), rp(c2)
    a = np.zeros((32, 32, 3), np.uint8)
    for y in range(32):
        for x in range(32):
            r = r1 if (x // 4) % 2 == 0 else r2
            lv = 2
            if x % 4 == 0:
                lv = 3
            elif x % 4 == 3:
                lv = 1
            a[y, x] = r[lv]
    save(Image.fromarray(a, 'RGB'), f'tor_stripes_{key}')


PENNANTS = {'rojo': '#c83a40', 'azul': '#3a6ac0', 'oro': '#e8b840', 'verde': '#3a8a50'}


def tor_pennant(key):
    """Gallardete de dos puntas (28x12 px): se sujeta por la izquierda (el mástil) y ondea."""
    c = rp(PENNANTS[key])
    w, h = 28, 12
    cv = Cv(w, h)
    cv.poly([(0, 0), (w - 1, 2), (w - 9, 6), (w - 1, h - 3), (0, h - 1)], c[2])
    cv.rect(0, 0, 3, h, c[1])
    cv.line(0, 1, w - 2, 2, c[3])
    cv.line(3, 5, 14, 6, c[3] if key != 'oro' else '#fff2c0')
    cv.outline(0.45)
    save(cv, f'tor_pennant_{key}')


def tor_banner(key, col, trim, emb):
    """Estandarte heráldico en un asta (como los de la Academia, con otros emblemas)."""
    w, h = 20, 60
    cv = Cv(w, h)
    c = rp(col)
    t = rp(trim)
    cv.rect(2, 3, w - 4, 44, c[2])
    cv.poly([(2, 47), (w - 3, 47), (w // 2, h - 2)], c[2])
    for x in range(2, w - 2):
        ph = math.sin((x - 2) / (w - 4) * math.pi * 2.2)
        if ph > 0.6 or ph < -0.6:
            for y in range(3, h):
                if cv.get(x, y)[3] > 0:
                    cv.px(x, y, c[3] if ph > 0 else c[1])
    for y in range(3, 47):
        cv.px(3, y, t[2]); cv.px(w - 4, y, t[1])
    cv.rect(3, 4, w - 6, 1, t[3])
    stamp_emblem(cv, emb, w // 2 - 5, 14, t[3], hi=t[4])
    cv.rect(4, 30, w - 8, 2, t[2])
    cv.rect(0, 1, w, 2, '#8a5a3a'); cv.rect(0, 1, w, 1, '#aa7a50')
    cv.outline(0.45)
    save(cv, f'tor_banner_{key}')


def tor_shield(key, c1, c2, emb):
    w, h = 14, 17
    cv = Cv(w, h)
    for y in range(h):
        t = y / h
        half = 7 if t < 0.55 else 7 * math.sqrt(max(0.0, 1 - ((t - 0.55) / 0.45) ** 2))
        for x in range(int(7 - half), int(math.ceil(7 + half))):
            cv.px(x, y, c1 if (x < 7) else c2)
    stamp_emblem(cv, emb, 3, 4, '#f4e8c0' if emb != 'star' else '#ffd860')
    cv.outline(0.45, '#3a2a24')
    save(cv, f'tor_shield_{key}')


def tor_rail():
    """La valla central de las justas (la «tela»): tablas pintadas con rayas diagonales (32x16 px = 1 x 0.5 m)."""
    w, h = 32, 16
    a = np.zeros((h, w, 3), np.uint8)
    r1, r2 = rp('#c83a40'), rp('#f1e8d0')
    for y in range(h):
        for x in range(w):
            r = r1 if ((x + y) // 6) % 2 == 0 else r2
            lv = 3 if y < 2 else (1 if y > h - 3 else 2)
            a[y, x] = r[lv]
    save(Image.fromarray(a, 'RGB'), 'tor_rail')


def tor_drape():
    """Paño que cuelga del frente de la grada: azul con orla dorada y escudos (64x24 px, se repite)."""
    w, h = 64, 24
    cv = Cv(w, h)
    c = rp('#2f4f96')
    g = rp('#e0b050')
    cv.rect(0, 0, w, h, c[2])
    for x in range(0, w, 5):
        cv.rect(x, 3, 1, h - 3, c[1]); cv.rect(x + 2, 3, 1, h - 3, c[3])
    cv.rect(0, 0, w, 3, g[2]); cv.rect(0, 0, w, 1, g[4]); cv.rect(0, h - 2, w, 2, g[2])
    for cx in (16, 48):
        for y in range(6, 19):
            t = (y - 6) / 13
            half = 5 if t < 0.55 else 5 * math.sqrt(max(0.0, 1 - ((t - 0.55) / 0.45) ** 2))
            for x in range(int(cx - half), int(math.ceil(cx + half))):
                cv.px(x, y, '#b8343c' if x < cx else '#f1e8d0')
    stamp_emblem(cv, 'lion', 11, 8, g[3])
    stamp_emblem(cv, 'tower', 44, 8, g[3])
    save(cv, 'tor_drape')


def horse_frame(cv, ox, oy, coat, cloth, f, small=False):
    """Un caballo de perfil mirando a la derecha con su gualdrapa. f: 0 quieto, 1 cola y cabeza arriba, 2 cabeza abajo."""
    co = rp(coat)
    cl = rp(cloth)
    mane = rp('#3a2a24')
    # patas
    for lx, ph in ((8, 0), (13, 1), (27, 0), (32, 1)):
        cv.rect(ox + lx, oy + 26, 3, 14, co[1] if ph else co[2])
        cv.rect(ox + lx, oy + 38, 3, 2, '#2a2024')
    # cuerpo
    cv.ell(ox + 4, oy + 14, 34, 16, co[2])
    cv.ell(ox + 8, oy + 16, 14, 6, co[3])
    # cuello y cabeza
    hy = {0: 0, 1: -2, 2: 6}[f]
    cv.poly([(ox + 30, oy + 18), (ox + 36, oy + 4 + hy), (ox + 42, oy + 6 + hy), (ox + 40, oy + 22)], co[2])
    cv.poly([(ox + 36, oy + 2 + hy), (ox + 48, oy + 8 + hy), (ox + 47, oy + 12 + hy), (ox + 40, oy + 10 + hy)], co[2])
    cv.px(ox + 41, oy + 5 + hy, '#1a1418')                                       # ojo
    cv.rect(ox + 37, oy + 0 + hy, 2, 3, co[1])                                    # oreja
    cv.poly([(ox + 33, oy + 6 + hy), (ox + 37, oy + 1 + hy), (ox + 38, oy + 4 + hy), (ox + 33, oy + 16)], mane[2])
    # cola
    if f == 1:
        cv.poly([(ox + 5, oy + 16), (ox + 0, oy + 18), (ox - 2, oy + 30), (ox + 2, oy + 28), (ox + 6, oy + 20)], mane[2])
    else:
        cv.poly([(ox + 5, oy + 16), (ox + 1, oy + 20), (ox + 1, oy + 33), (ox + 4, oy + 31), (ox + 6, oy + 20)], mane[2])
    # gualdrapa con festón y un escudo
    cv.poly([(ox + 10, oy + 12), (ox + 30, oy + 12), (ox + 31, oy + 27), (ox + 9, oy + 27)], cl[2])
    for x in range(ox + 9, ox + 31, 4):
        cv.ell(x, oy + 25, 4, 4, cl[2])
    cv.rect(ox + 10, oy + 12, 21, 2, cl[3])
    cv.rect(ox + 12, oy + 26, 18, 1, cl[1])
    cv.rect(ox + 17, oy + 15, 6, 7, '#e8c060'); cv.rect(ox + 18, oy + 16, 4, 5, cl[1])
    # silla
    cv.rect(ox + 16, oy + 9, 9, 4, '#6a4028'); cv.rect(ox + 16, oy + 9, 9, 1, '#8a5a38')


def tor_horse(key, coat, cloth):
    frames = []
    for f in (0, 1, 0, 2):
        cv = Cv(52, 42)
        horse_frame(cv, 2, 1, coat, cloth, f)
        cv.outline(0.45)
        frames.append(cv)
    save(strip(frames), f'tor_horse_{key}')


def tor_rider(key, coat, cloth, plume):
    """Caballero a caballo, galopando con la lanza en ristre (2 cuadros; de fondo, pequeño)."""
    frames = []
    co = rp(coat)
    cl = rp(cloth)
    st = rp('#a8b0c0')
    for f in range(2):
        cv = Cv(64, 48)
        ox, oy = 4, 10
        # patas al galope
        legs = [(8, 0.5), (13, -0.4), (27, 0.6), (32, -0.5)] if f == 0 else [(8, -0.4), (13, 0.5), (27, -0.5), (32, 0.6)]
        for lx, sl in legs:
            cv.line(ox + lx, oy + 26, ox + lx + int(sl * 8), oy + 37, co[1])
            cv.line(ox + lx + 1, oy + 26, ox + lx + 1 + int(sl * 8), oy + 37, co[2])
        cv.ell(ox + 4, oy + 14, 34, 15, co[2])
        cv.poly([(ox + 30, oy + 18), (ox + 38, oy + 6), (ox + 44, oy + 8), (ox + 40, oy + 22)], co[2])
        cv.poly([(ox + 38, oy + 4), (ox + 49, oy + 10), (ox + 48, oy + 14), (ox + 41, oy + 12)], co[2])
        cv.poly([(ox + 9, oy + 12), (ox + 31, oy + 12), (ox + 32, oy + 27), (ox + 8, oy + 27)], cl[2])
        cv.rect(ox + 9, oy + 12, 23, 2, cl[3])
        cv.poly([(ox + 4, oy + 16), (ox - 3, oy + 20 + f * 2), (ox + 4, oy + 22)], '#3a2a24')
        # jinete: armadura, escudo, yelmo con penacho
        cv.rect(ox + 17, oy - 2, 7, 13, st[2]); cv.rect(ox + 17, oy - 2, 2, 13, st[3])
        cv.rect(ox + 18, oy - 8, 6, 6, st[2]); cv.rect(ox + 22, oy - 6, 2, 1, '#2a2a34')
        cv.poly([(ox + 18, oy - 8), (ox + 15, oy - 12 - f), (ox + 21, oy - 9)], plume)
        cv.rect(ox + 14, oy + 1, 5, 7, cl[2]); cv.rect(ox + 15, oy + 2, 3, 5, '#e8c060')
        # lanza en ristre con su banderola
        cv.line(ox + 22, oy + 3, ox + 58, oy - 4, '#d8c8a0'); cv.line(ox + 22, oy + 4, ox + 58, oy - 3, '#a89068')
        cv.poly([(ox + 30, oy + 1), (ox + 36, oy + 0), (ox + 33, oy + 5)], cl[3])
        cv.outline(0.45)
        frames.append(cv)
    save(strip(frames), f'tor_rider_{key}')


def tor_rack():
    """Armero con lanzas a rayas y dos escudos."""
    w, h = 44, 40
    cv = Cv(w, h)
    wd = rp('#7a4c30')
    cv.rect(2, 24, w - 4, 3, wd[2]); cv.rect(2, 24, w - 4, 1, wd[3])
    cv.rect(2, 34, w - 4, 3, wd[2])
    cv.rect(3, 10, 3, h - 10, wd[1]); cv.rect(w - 6, 10, 3, h - 10, wd[1])
    for i, x in enumerate(range(9, w - 8, 5)):
        r1, r2 = (('#c83a40', '#f1e8d0') if i % 2 == 0 else ('#3a6ac0', '#f1e8d0'))
        for y in range(1, h - 2):
            cv.px(x, y, r1 if ((y + i * 3) // 4) % 2 == 0 else r2)
            cv.px(x + 1, y, '#a89068')
        cv.poly([(x - 1, 2), (x + 1, -2), (x + 3, 2)], '#c0c8d0')
    for (sx, c1, c2) in ((4, '#b8343c', '#e8c060'), (w - 16, '#2f5aa8', '#f1e8d0')):
        for y in range(18, 31):
            t = (y - 18) / 13
            half = 6 if t < 0.55 else 6 * math.sqrt(max(0.0, 1 - ((t - 0.55) / 0.45) ** 2))
            for x in range(int(sx + 6 - half), int(math.ceil(sx + 6 + half))):
                cv.px(x, y, c1 if x < sx + 6 else c2)
    cv.outline(0.45)
    save(cv, 'tor_rack')


def tor_hay():
    w, h = 24, 15
    cv = Cv(w, h)
    hy = rp('#d8b45a')
    cv.rect(0, 2, w, h - 2, hy[2]); cv.rect(0, 2, w, 2, hy[3])
    rnd = random.Random(4)
    for _ in range(40):
        x, y = rnd.randrange(w), rnd.randrange(3, h)
        cv.px(x, y, hy[rnd.choice([1, 3, 4])])
    for x in (6, 17):
        cv.rect(x, 2, 1, h - 2, '#8a5a3a')
    cv.outline(0.45)
    save(cv, 'tor_hay')


def tor_trough():
    w, h = 32, 13
    cv = Cv(w, h)
    wd = rp('#7a4c30')
    cv.poly([(0, 2), (w - 1, 2), (w - 4, h - 3), (3, h - 3)], wd[2])
    cv.rect(2, 3, w - 4, 2, '#5ab0d8'); cv.rect(4, 3, 6, 1, '#cfeefa')
    cv.rect(0, 2, w, 1, wd[3])
    cv.rect(3, h - 3, 3, 3, wd[1]); cv.rect(w - 6, h - 3, 3, 3, wd[1])
    cv.outline(0.45)
    save(cv, 'tor_trough')


def tor_castle():
    """El castillo a lo lejos, sobre una loma: azulado por la distancia, con banderitas."""
    w, h = 140, 76
    cv = Cv(w, h)
    hill = rp('#7aa0a0')
    st = rp('#9aa8c4')
    cv.ell(-20, 46, w + 40, 70, hill[2])
    cv.ell(10, 50, w - 20, 50, hill[3])
    def tower(x, y, tw, th, roof=True):
        cv.rect(x, y, tw, th, st[2]); cv.rect(x, y, 2, th, st[3]); cv.rect(x + tw - 2, y, 2, th, st[1])
        for k in range(0, tw, 4):
            cv.rect(x + k, y - 3, 2, 3, st[2])
        if roof:
            cv.poly([(x - 2, y), (x + tw + 1, y), (x + tw // 2, y - 14)], '#7a5a9a')
            cv.line(x + tw // 2, y - 14, x + tw // 2, y - 20, '#5a4a5a')
            cv.poly([(x + tw // 2, y - 20), (x + tw // 2 + 6, y - 18), (x + tw // 2, y - 16)], '#d84a4a')
        for wy in range(y + 6, y + th - 6, 9):
            cv.rect(x + tw // 2 - 1, wy, 2, 4, '#4a5a7a')
    cv.rect(30, 34, 80, 22, st[2]); cv.rect(30, 34, 80, 2, st[3])
    for k in range(30, 110, 5):
        cv.rect(k, 31, 3, 3, st[2])
    cv.rect(64, 44, 12, 12, '#4a5a7a'); cv.ell(64, 40, 12, 8, '#4a5a7a')
    tower(22, 26, 14, 30)
    tower(104, 24, 14, 32)
    tower(58, 12, 22, 24)
    a = np.array(cv.im).astype(np.float32)
    a[:, :, :3] = a[:, :, :3] * 0.85 + np.array([150, 170, 200]) * 0.15
    save(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA'), 'tor_castle')


def torneo():
    tor_grass()
    tor_dirt()
    tor_trodden()
    for k in STRIPES:
        tor_stripes(k)
    for k in PENNANTS:
        tor_pennant(k)
    tor_banner('leon', '#b8343c', '#e8c060', 'lion')
    tor_banner('torre', '#2f5aa8', '#dfe6f0', 'tower')
    tor_banner('estrella', '#3f7a4c', '#e8c060', 'star')
    tor_shield('a', '#b8343c', '#e8c060', 'lion')
    tor_shield('b', '#2f5aa8', '#f1e8d0', 'tower')
    tor_shield('c', '#3f7a4c', '#f1e8d0', 'star')
    tor_rail()
    tor_drape()
    tor_horse('gris', '#c8c4c0', '#2f5aa8')
    tor_horse('castano', '#8a5a3a', '#b8343c')
    tor_rider('rojo', '#5a3a2a', '#b8343c', '#f1e8d0')
    tor_rider('azul', '#d8d4d0', '#2f5aa8', '#e8c060')
    tor_rack()
    tor_hay()
    tor_trough()
    tor_castle()
    crowd_strip(5, 'tor_crowd_a', dusk=False)
    crowd_strip(17, 'tor_crowd_b', dusk=False)
    crowd_back(44, 'tor_crowd_back', dusk=False)


def fx_confetti():
    """Un papelito de confeti (blanco: Godot le da un color a cada uno)."""
    cv = Cv(4, 3)
    cv.rect(0, 0, 4, 3, '#ffffff'); cv.rect(0, 2, 4, 1, '#d8d8d8')
    save(cv, 'fx_confetti')


# ================================================================== ALUMNOS DE LA ACADEMIA (figurantes)

OUT_CHARS = './salida/event_chars'

# alumnos genéricos (no son del elenco): la cara y el pelo salen de un personaje base del generador (chars64.py), con
# otro color de pelo, la túnica larga de su casa, bufanda y, a algunos, sombrero de mago. Sentados tras las mesas de la
# Academia solo se les ve de la cintura para arriba.
STUDENTS = {
    'alumna_azul': dict(base='wren', hc='#6a4030', robe='#2f4f96', trim='#d8dce8', scarf='#d8dce8', hat=False),
    'alumno_rojo': dict(base='tobias', hc='#2a2228', robe='#9a2a34', trim='#d8a848', scarf='#d8a848', hat=False),
    'alumna_verde': dict(base='sylwen', hc='#7a4a2a', robe='#2f6a44', trim='#c8904a', scarf='#c8904a', hat=False),
    'alumno_violeta': dict(base='kit', hc='#b8602e', robe='#5a3a8a', trim='#d8dce8', scarf='#d8dce8', hat=True),
    'alumna_roja': dict(base='marta', hc='#2a2a3a', robe='#9a2a34', trim='#d8a848', scarf='#d8a848', hat=False),
    'alumno_azul': dict(base='pip', hc='#d8b060', robe='#2f4f96', trim='#e8c060', scarf='#e8c060', hat=True),
}


def students(names=None):
    import copy
    import chars64 as C
    os.makedirs(OUT_CHARS, exist_ok=True)
    out = []
    for sid, st in STUDENTS.items():
        if names and sid not in names:
            continue
        base = C.CAST[st['base']]
        sp = {}
        for k in ('species', 'skin', 'eyes', 'face', 'hair', 'ears', 'ear_len', 'ear_up', 'lash', 'mouth_col', 'stance',
                  'stance_mod', 'turn', 'hair_kind', 'hair_mute', 'beard_col'):
            if k in base:
                sp[k] = copy.deepcopy(base[k])
        sp['name'] = sid
        sp['hc'] = st['hc']
        sp.pop('hair_kind', None)
        if st['hat']:
            hair = sp['hair']
            hair['volume'] = min(1.4, hair.get('volume', 1.0))
        sp['top'] = dict(kind='dress', mat='robe', length='floor', flare=0.3, folds=3, trim='trim', front='trim',
                         neck='collar', neck_mat='trim')
        sp['sleeves'] = dict(kind='wide', mat='robe', cuff='trim')
        sp['legs'] = dict(kind='pants', mat='pants')
        sp['feet'] = dict(kind='shoes', mat='shoes')
        sp['over'] = [(C.scarf, dict(mat='scarf'))]
        sp['head'] = [(C.witch_hat, dict(mat='hat', band='trim', brim_cast=1, brim_h=3.1))] if st['hat'] else []
        sp['arms'] = {'n': 'chest', 'f': 'book'}
        sp['hold'] = {}
        sp['near'] = []
        sp['far_front'] = True
        sp['far'] = [(C.book, dict(cover='book', page='page', clasp='gold'))]
        mats = copy.deepcopy(base.get('mats', {}))        # los del pelo (cintas, pañuelos...) siguen sirviendo
        mats.update({'robe': st['robe'], 'trim': st['trim'], 'pants': '#3a3040', 'shoes': ('#4a3426', 'leather'),
                     'scarf': st['scarf'], 'hat': st['robe'], 'book': '#7a3a3a', 'page': '#f3ead2'})
        sp['mats'] = mats
        sp['accent'] = ('scarf',)
        idle, walk = C.frames(sp)
        Image.fromarray(np.concatenate(idle, axis=1), 'RGBA').save(f'{OUT_CHARS}/{sid}_idle.png')
        Image.fromarray(np.concatenate(walk, axis=1), 'RGBA').save(f'{OUT_CHARS}/{sid}_walk.png')
        out.append(sid)
    print('alumnos', out)
    return out


# ================================================================== hoja de contacto y salida

def contact_sheet(path, names=None, scale=3, width=1900):
    names = names or MADE
    ims = [(n, Image.open(f'{OUT}/{n}.png').convert('RGBA')) for n in names]
    x = y = rowh = 0
    pos = []
    for n, im in ims:
        w, h = im.width * scale, im.height * scale
        if x + w > width:
            x, y, rowh = 0, y + rowh + 16, 0
        pos.append((n, im, x, y))
        x += w + 10
        rowh = max(rowh, h)
    sheet = Image.new('RGBA', (width, y + rowh + 20), (58, 50, 70, 255))
    d = ImageDraw.Draw(sheet)
    for n, im, x, y in pos:
        sheet.alpha_composite(im.resize((im.width * scale, im.height * scale), Image.NEAREST), (x, y + 12))
        d.text((x, y), n, fill=(255, 236, 190, 255))
    sheet.save(path)
    print('hoja', path)


if __name__ == '__main__':
    args = [a for a in sys.argv[1:]]
    sheet_path = None
    if '--sheet' in args:
        k = args.index('--sheet')
        sheet_path = args[k + 1]
        del args[k:k + 2]
    which = [a for a in args if a in ('academia', 'concurso', 'torneo', 'students')]
    args = [a for a in args if a not in which]
    for part in (which or ['academia', 'concurso', 'torneo', 'students']):
        fn = globals().get(part)
        if fn:
            fn()
    print('ok', len(MADE), 'imágenes')
    if sheet_path:
        contact_sheet(sheet_path)
    dest = args[0] if args else None
    if dest:
        os.makedirs(f'{dest}/event', exist_ok=True)
        for f in os.listdir(OUT):
            if f.endswith('.png'):
                shutil.copy(f'{OUT}/{f}', f'{dest}/event/{f}')
        print('copiado a', f'{dest}/event')
        if os.path.isdir(OUT_CHARS):
            for f in os.listdir(OUT_CHARS):
                if f.endswith('.png'):
                    shutil.copy(f'{OUT_CHARS}/{f}', f'{dest}/chars/{f}')
            print('alumnos copiados a', f'{dest}/chars')
