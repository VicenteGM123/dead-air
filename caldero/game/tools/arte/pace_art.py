"""R4 PACE: el reloj y la fila de la tienda.
Iconos (estilo de los emotes de props.py, 16x16 con contorno):
  icons/emote_hourglass_0..4.png  el reloj de arena sobre la cabeza de quien espera (4 = arriba lleno, 0 = vacío)
  icons/emote_sigh.png            el suspiro (bocanada de aire) de quien ve la fila llena o se va a casa al cerrar
  icons/emote_angry.png           la venita de enfado de quien se cansó de esperar
  ui/hud_clock.png                la esfera del reloj de la placa del HUD (las agujas las dibuja game_ui.gd)
  ui/hud_queue.png                la personita del contador de la fila (HUD)
Uso (desde una carpeta fuera del proyecto):  python3 <game>/tools/arte/pace_art.py [<game>/assets]
Sin argumento escribe en ./salida/{icons,ui}; con la carpeta assets, escribe ahí directamente.
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from pixlib import Mat, new_grid, stamp, render, save, preview

OUT = sys.argv[1] if len(sys.argv) > 1 else './salida'
for d in ('icons', 'ui'):
    os.makedirs(f'{OUT}/{d}', exist_ok=True)


def art(spec, mats, outline=True, light='left'):
    rows = spec.strip('\n').split('\n')
    W = max(len(r) for r in rows)
    H = len(rows)
    g = new_grid(W, H)
    stamp(g, '\n'.join(r.ljust(W, '.') for r in rows))
    cache, codes = {}, {}
    for ch, v in mats.items():
        base, lvl = v[0], v[1]
        mode = v[2] if len(v) > 2 else 'cyl'
        key = (base, mode)
        if key not in cache:
            cache[key] = Mat(base, mode)
        codes[ch] = (cache[key], lvl)
    return render(g, codes, outline=outline, light_from=light)


def pad_to(arr, w, h, anchor='center'):
    out = np.zeros((h, w, 4), dtype=np.uint8)
    ah, aw = arr.shape[:2]
    x = (w - aw) // 2
    y = {'bottom': h - ah, 'top': 1}.get(anchor, (h - ah) // 2)
    out[y:y + ah, x:x + aw] = arr
    return out


# ------------------------------------------------------------------ el reloj de arena (5 niveles de arena)
# Columnas interiores de cada fila del vidrio (12 de ancho): la ampolla de arriba (filas 1-5), el cuello (6) y la de
# abajo (7-11). Las tapas de madera son las filas 0 y 12.
TOP = {1: (2, 9), 2: (2, 9), 3: (3, 8), 4: (4, 7), 5: (5, 6)}
NECK = {6: (5, 6)}
BOT = {7: (5, 6), 8: (4, 7), 9: (3, 8), 10: (2, 9), 11: (2, 9)}
# arena arriba según el nivel (filas llenas, de abajo hacia arriba) y abajo (filas llenas desde el fondo)
TOP_FILL = {4: [2, 3, 4, 5], 3: [3, 4, 5], 2: [4, 5], 1: [5], 0: []}
BOT_FILL = {4: [11], 3: [10, 11], 2: [9, 10, 11], 1: [8, 9, 10, 11], 0: [7, 8, 9, 10, 11]}


def hourglass(level):
    W, H = 12, 13
    g = [['.'] * W for _ in range(H)]
    for x in range(W):
        g[0][x] = 'W'
        g[12][x] = 'W'
    g[0][0] = g[0][11] = g[12][0] = g[12][11] = '.'   # esquinas redondeadas
    for rows in (TOP, NECK, BOT):
        for y, (a, b) in rows.items():
            for x in range(a, b + 1):
                g[y][x] = 'G'
            # el borde del vidrio (un píxel claro a cada lado)
            g[y][a - 1] = 'E'
            g[y][b + 1] = 'E'
    for y in TOP_FILL[level]:
        a, b = TOP[y]
        for x in range(a, b + 1):
            g[y][x] = 'S'
    for y in BOT_FILL[level]:
        a, b = BOT[y]
        for x in range(a, b + 1):
            g[y][x] = 'S'
    if level > 0:   # el hilito de arena que cae por el cuello
        g[6][5] = 's'
        g[7][5] = 's'
    # un brillo en el vidrio de arriba
    if g[1][3] == 'G':
        g[1][3] = 'w'
    if g[2][3] == 'G':
        g[2][3] = 'w'
    spec = '\n'.join(''.join(r) for r in g)
    arr = art(spec, {
        'W': ('#9a6234', None, 'top'),          # madera de las tapas
        'G': ('#cfe8f6', 3, 'flat'),            # vidrio vacío (claro)
        'E': ('#8fb7d0', 2, 'flat'),            # canto del vidrio
        'S': ('#f2c14e', None, 'cyl'),          # arena dorada
        's': ('#f7d77e', 3, 'flat'),            # el hilito
        'w': ('#ffffff', 4, 'flat'),
    })
    return pad_to(arr, 16, 16)


# ------------------------------------------------------------------ suspiro y enfado
SIGH = art("""
..........CCCC..
........CCCCCCC.
...cc..CCCCCCCCC
..cccc.CCCCCCCCC
..cccc..CCCCCCC.
...cc.....CCCC..
""", {'C': ('#e3e9f5', None, 'top'), 'c': ('#cbd4e6', None, 'top')})

# el enfado: una nubecita de tormenta con un rayo (se lee mejor que la venita a este tamaño). Va arriba del cuadro
# (actor.gd centra el emote justo sobre la cabeza: así flota encima y no parece un gorro)
ANGRY = art("""
.....LLLL.....
...LLLLLLLL...
.LLLLLLLLLLLL.
LLLLLLLLLLLLLL
.DDDDDDDDDDDD.
....RRR.......
...RRRRR......
.....RR.......
....RR........
""", {'L': ('#d9d3e6', None, 'top'), 'D': ('#9a91b2', None, 'top'), 'R': ('#ffb02e', 3, 'flat')})


# ------------------------------------------------------------------ HUD: la esfera del reloj y la personita de la fila
CLOCK = art("""
....BBBBB....
..BBFFFFFBB..
.BFFFFMFFFFB.
.BFFFFFFFFFB.
BFFFFFFFFFFFB
BFFFFFFFFFFFB
BFMFFFFFFFMFB
BFFFFFFFFFFFB
BFFFFFFFFFFFB
.BFFFFFFFFFB.
.BFFFFMFFFFB.
..BBFFFFFBB..
....BBBBB....
""", {'B': ('#c9a15a', None, 'cyl'), 'F': ('#f4e4bd', 3, 'flat'), 'M': ('#5a3a24', 1, 'flat')})

PERSON = art("""
..HHH..
.HHHHH.
.HHHHH.
..HHH..
.BBBBB.
BBBBBBB
BBBBBBB
BBBBBBB
BBBBBBB
""", {'H': ('#f1dcb4', None, 'top'), 'B': ('#e7c98f', None, 'cyl')})


if __name__ == '__main__':
    frames = [hourglass(k) for k in range(5)]
    for k, f in enumerate(frames):
        save(f, f'{OUT}/icons/emote_hourglass_{k}.png')
    save(pad_to(SIGH, 16, 16), f'{OUT}/icons/emote_sigh.png')
    save(pad_to(ANGRY, 16, 16, 'top'), f'{OUT}/icons/emote_angry.png')
    save(CLOCK, f'{OUT}/ui/hud_clock.png')
    save(PERSON, f'{OUT}/ui/hud_queue.png')
    preview(frames + [pad_to(SIGH, 16, 16), pad_to(ANGRY, 16, 16, 'top'), pad_to(CLOCK, 16, 16), pad_to(PERSON, 16, 16)],
            scale=8, cols=9, path='./prev_pace.png')
    print('ok')
