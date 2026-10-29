#!/usr/bin/env python3
"""--- SS SEED: el arte de RELLENO de la semilla de Secondhand Stars (todo se reemplaza con el de ART).

Escribe en assets/ (rutas del contrato, así lo de ART las pisa sin tocar código):
  assets/chars/<id>_idle.png (2 cuadros) y <id>_walk.png (4 cuadros), 64x96: los 9 humanoides del elenco con el kit
      (chars64.py + c64cast_ss.py) y Kettle dibujado aquí (el kit solo hace humanoides)
  assets/tex/blob_shadow.png      la sombra de los personajes (actor.gd)
  assets/icons/emote_<n>.png      emociones 16x16 (actor.gd emote()): question, excl, dots, heart, angry, steam, note, star
  assets/ui/cursor.png            la flecha del cursor del mando (pad_cursor.gd)
  icon.png                        el icono del proyecto (una estrella remendada)
Y solo para el cuarto de prueba de la semilla (CORE puede borrarlas): assets/tex/seed_floor.png, seed_wall.png,
seed_metal.png.

    python3 tools/arte/ss_placeholders.py            (python3 con pillow, numpy y scipy)
    python3 tools/arte/ss_placeholders.py --sheet x.png   -> además una hoja de contacto
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
A = os.path.join(GAME, "assets")

from pixlib import Mat, new_grid, stamp, render, to_image  # noqa: E402

# ------------------------------------------------------------------ dibujo en grilla (pixlib la sombrea y contornea)


def fill_ellipse(g, cx, cy, rx, ry, ch):
    for y in range(len(g)):
        for x in range(len(g[0])):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                g[y][x] = ch


def fill_rect(g, x0, y0, x1, y1, ch):
    for y in range(max(0, y0), min(len(g), y1 + 1)):
        for x in range(max(0, x0), min(len(g[0]), x1 + 1)):
            g[y][x] = ch


def line(g, x0, y0, x1, y1, ch, w=1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = round(x0 + (x1 - x0) * i / n)
        y = round(y0 + (y1 - y0) * i / n)
        fill_rect(g, x, y, x + w - 1, y + w - 1, ch)


# ------------------------------------------------------------------ Kettle (relleno)
# Bot del alto de una rodilla con forma de tetera: cuerpo de cobre, pico (nariz), tapa que salta, un ojo-lente grande
# y redondo, dos patitas. Mira a la derecha, pies en la fila 91 (como el kit).
KCODES = {
    'c': (Mat('#c0703c', 'cyl'), None),      # cobre
    'C': (Mat('#c0703c', 'cyl'), 3),         # cobre claro (brillo)
    'l': (Mat('#d08a4a', 'top'), None),      # tapa
    'k': (Mat('#d8b050', 'shine'), None),    # perilla de latón
    'd': (Mat('#4e4a50', 'cyl'), None),      # metal oscuro (asa, aro, patas)
    'e': (Mat('#5ab8c8', 'shine'), None),    # lente
    'r': (Mat('#2e2a30', 'flat'), None),     # aro del ojo
    'w': (Mat('#f4f0e0', 'flat'), 4),        # brillo del ojo
}


def kettle_frame(bob=0, lid=0, step=None):
    g = new_grid(64, 96)
    by = 79 + bob
    # patas (step: None quieto; 0..3 ciclo de caminar)
    legs = [(27, 0), (35, 0)]
    if step is not None:
        off = [(-1, 1), (0, 0), (1, -1), (0, 0)][step]
        lift = [(0, 1), (0, 0), (1, 0), (0, 0)][step]
        legs = [(27 + off[0], lift[0]), (35 + off[1], lift[1])]
    for lx, up in legs:
        fill_rect(g, lx, 86 + bob - up, lx + 2, 90 - up, 'd')
        fill_rect(g, lx, 90 - up, lx + 4, 91 - up, 'd')
    # asa (atrás, a la izquierda)
    line(g, 21, by - 6, 18, by - 2, 'd', 2)
    line(g, 18, by - 2, 20, by + 4, 'd', 2)
    # cuerpo
    fill_ellipse(g, 32, by, 11.5, 8.5, 'c')
    fill_rect(g, 22, by + 5, 42, by + 6, 'd')       # aro de la base
    # pico (la nariz), hacia arriba a la derecha
    line(g, 41, by + 1, 47, by - 5, 'c', 3)
    fill_rect(g, 47, by - 7, 49, by - 5, 'c')
    # tapa y perilla (lid > 0: la tapa salta)
    fill_ellipse(g, 31, by - 9 - lid, 7.5, 3.0, 'l')
    fill_rect(g, 30, by - 13 - lid, 32, by - 12 - lid, 'k')
    # el ojo-lente grande, adelante
    fill_ellipse(g, 37.5, by - 1, 4.6, 4.6, 'r')
    fill_ellipse(g, 37.5, by - 1, 3.4, 3.4, 'e')
    g[by - 3][36] = 'w'
    g[by - 2][36] = 'w'
    # brillo del cobre
    fill_rect(g, 25, by - 4, 26, by - 1, 'C')
    return render(g, KCODES)


def kettle_sheets():
    idle = [kettle_frame(0, 0), kettle_frame(0, 1)]
    walk = [kettle_frame([0, -1, 0, -1][i], 0, i) for i in range(4)]
    return idle, walk


# ------------------------------------------------------------------ iconos chicos (16x16)

ICODES = {
    'o': (Mat('#f4e6c4', 'flat'), None),     # globo claro
    'a': (Mat('#ffb040', 'flat'), None),     # ámbar
    'r': (Mat('#e05048', 'flat'), None),     # rojo
    'k': (Mat('#3a2e2a', 'flat'), None),     # tinta
    's': (Mat('#e8eef0', 'flat'), None),     # vapor
    'y': (Mat('#ffd860', 'flat'), None),     # estrella
}

EMOTES = {
    'question': """
....oooooooo....
...oooooooooo...
..oookkkkkooo...
..ookkoooookko..
..ooooooookkoo..
..oooooookkooo..
..ooooookkoooo..
..ooooookkoooo..
..oooooooooooo..
..ooooookkoooo..
...oooookkooo...
....oooooooo....
......ooo.......
.....oo.........
""",
    'excl': """
....oooooooo....
...oooooooooo...
..oooookkooooo..
..oooookkooooo..
..oooookkooooo..
..oooookkooooo..
..oooookkooooo..
..oooooooooooo..
..oooookkooooo..
...ooookkoooo...
....oooooooo....
......ooo.......
.....oo.........
""",
    'dots': """
................
....oooooooo....
...oooooooooo...
..oooooooooooo..
..ookkookkookko.
..ookkookkookko.
..oooooooooooo..
...oooooooooo...
....oooooooo....
......ooo.......
.....oo.........
""",
    'heart': """
................
...rrr...rrr....
..rrrrr.rrrrr...
..rrrrrrrrrrr...
..rrrrrrrrrrr...
...rrrrrrrrr....
....rrrrrrr.....
.....rrrrr......
......rrr.......
.......r........
""",
    'angry': """
................
..rr......rr....
..rrr....rrr....
...rrr..rrr.....
................
...rrr..rrr.....
..rrr....rrr....
..rr......rr....
""",
    'steam': """
.......ss.......
.....ssssss.....
....ssssssss....
...sssssssssss..
..sssssssssssss.
..ssssssssssss..
...ssssssssss...
.....ssssss.....
.......ss.......
""",
    'note': """
.......kkkkk....
.......kkkkkk...
.......k....k...
.......k....k...
.......k....k...
....kkkk.kkkk...
...kkkkkkkkkk...
...kkkk.kkkk....
....kk...kk.....
""",
    'star': """
.......y........
.......y........
......yyy.......
..yyyyyyyyyyy...
....yyyyyyy.....
.....yyyyy......
....yyy.yyy.....
....yy...yy.....
...y.......y....
""",
}

CURSOR = """
a...........
aa..........
aaa.........
aaaa........
aaaaa.......
aaaaaa......
aaaaaaa.....
aaaaaaaa....
aaaaa.......
aa.aaa......
a..aaa......
....aaa.....
....aaa.....
""".replace('a', 'a')


def icon16(art, w=16, h=16, oy=1, ox=0):
    g = new_grid(w, h)
    stamp(g, art, ox, oy)
    return render(g, ICODES, outline=True, outline_col='#2a2024')


# ------------------------------------------------------------------ texturas del cuarto de prueba y sombra

def _noise(shape, seed, amp):
    rng = np.random.default_rng(seed)
    return rng.normal(0, amp, shape)


def tex_floor():
    im = np.zeros((32, 32, 3), np.float32)
    im[:] = (128, 118, 108)
    im += _noise((32, 32, 1), 1, 5)
    for k in (0, 16):
        im[k, :] = (88, 78, 72)
        im[:, k] = (88, 78, 72)
    im[1, 1:16] += 14
    im[17, 17:32] += 14
    return np.clip(im, 0, 255).astype(np.uint8)


def tex_wall():
    im = np.zeros((32, 32, 3), np.float32)
    im[:] = (214, 180, 136)
    im += _noise((32, 32, 1), 2, 5)
    rng = np.random.default_rng(3)
    for _ in range(14):
        x, y = rng.integers(0, 32, 2)
        im[y, x] += (-22, -20, -16)
    for i in range(7):
        im[20 + i // 2, 6 + i] = (168, 128, 92)
    return np.clip(im, 0, 255).astype(np.uint8)


def tex_metal():
    im = np.zeros((32, 32, 3), np.float32)
    im[:] = (120, 118, 114)
    im += _noise((32, 32, 1), 4, 4)
    im[0, :] = im[:, 0] = (84, 82, 80)
    im[31, :] = im[:, 31] = (150, 146, 140)
    for (x, y) in ((4, 4), (27, 4), (4, 27), (27, 27)):
        im[y, x] = (176, 172, 164)
        im[y + 1, x + 1] = (70, 68, 66)
    im[12:20, 10:22] += (30, 10, -14)   # óxido
    return np.clip(im, 0, 255).astype(np.uint8)


def blob_shadow():
    w, h = 32, 16
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xx + 0.5 - w / 2) / (w / 2)) ** 2 + ((yy + 0.5 - h / 2) / (h / 2)) ** 2)
    a = np.clip(1.0 - d, 0, 1) ** 0.8 * 150
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = (24, 16, 20)
    out[..., 3] = a.astype(np.uint8)
    return out


def project_icon():
    s = 32
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, s - 1, s - 1), 6, fill=(44, 34, 36, 255))
    import math
    pts = []
    for i in range(10):
        r = 13 if i % 2 == 0 else 5.5
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((16 + r * math.cos(a), 17 + r * math.sin(a)))
    d.polygon(pts, fill=(255, 176, 64, 255), outline=(120, 60, 30, 255))
    d.rectangle((17, 15, 22, 20), fill=(126, 160, 172, 255), outline=(60, 50, 50, 255))   # el remiendo
    for x in (18, 20):
        d.point((x, 14), fill=(60, 50, 50, 255))
        d.point((x, 21), fill=(60, 50, 50, 255))
    return im.resize((64, 64), Image.NEAREST)


def save(arr_or_img, rel):
    p = os.path.join(A, rel) if not rel.startswith('/') else rel
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(arr_or_img)
    img.save(p)
    return p


def main():
    written = []
    # personajes del kit
    import chars64
    ids = [i for i in chars64.ORDER if i in chars64.CAST]
    res = chars64.build(ids, os.path.join(A, 'chars'))
    written += ['chars/%s_idle.png, _walk.png' % i for i in ids]
    # Kettle
    idle, walk = kettle_sheets()
    save(np.concatenate(idle, axis=1), 'chars/kettle_idle.png')
    save(np.concatenate(walk, axis=1), 'chars/kettle_walk.png')
    res['kettle'] = (idle, walk)
    written.append('chars/kettle_idle.png, _walk.png')
    # sombra, emociones, cursor, texturas, icono
    save(blob_shadow(), 'tex/blob_shadow.png')
    for name, art in EMOTES.items():
        save(icon16(art), 'icons/emote_%s.png' % name)
    g = new_grid(12, 16)
    stamp(g, CURSOR, 0, 1)
    save(render(g, ICODES, outline=True, outline_col='#2a1a12'), 'ui/cursor.png')
    save(tex_floor(), 'tex/seed_floor.png')
    save(tex_wall(), 'tex/seed_wall.png')
    save(tex_metal(), 'tex/seed_metal.png')
    project_icon().save(os.path.join(GAME, 'icon.png'))
    written += ['tex/blob_shadow.png', 'icons/emote_*.png (%d)' % len(EMOTES), 'ui/cursor.png',
                'tex/seed_floor.png, seed_wall.png, seed_metal.png', '../icon.png']
    if '--sheet' in sys.argv:
        k = sys.argv.index('--sheet')
        order = ['nell', 'kettle'] + [i for i in ids if i != 'nell']
        frames = [res[i][0][0] for i in order] + list(res['kettle'][1])
        sc = 3
        sheet = Image.new('RGBA', (64 * sc * len(frames[:10]), 96 * sc * 2), (52, 46, 60, 255))
        for n, fr in enumerate(frames):
            x, y = (n % 10) * 64 * sc, (n // 10) * 96 * sc
            sheet.alpha_composite(Image.fromarray(fr).resize((64 * sc, 96 * sc), Image.NEAREST), (x, y))
        sheet.save(sys.argv[k + 1])
        written.append(sys.argv[k + 1])
    for w in written:
        print('  ' + w)


if __name__ == '__main__':
    main()
