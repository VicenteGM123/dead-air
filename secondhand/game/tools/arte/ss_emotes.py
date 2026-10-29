"""Secondhand Stars · emociones sobre la cabeza (assets/icons/emote_<nombre>.png) e icono de la app (icon.png).

Lienzo 16x24: el dibujo (16x16) va ARRIBA y abajo quedan 8 filas vacías. actor.gd centra el Sprite3D de la emoción en
top_height() + 0.15 con pixel_size 0.04; con un lienzo de 16x16 la mitad de abajo tapaba la cabeza (los cuernos de
Gorrum, la cúpula de Oona, la pantalla de Clatter). Con 16x24 el borde de abajo del dibujo cae justo en lo alto de la
cabeza (la colita del globo la toca) sin cambiar actor.gd.

actor.gd las pinta como Sprite3D sin sombreado a pixel_size 0.04, encima de la cabeza; tienen que leerse igual sobre el
taller oscuro que sobre la arena clara: todas llevan contorno de tinta (#2a2024) de 1 px. Los globos son los del kit de
UI (crema #f4ecd8, sombra #d8ccb0, misma tinta) y los acentos son los de la paleta (ámbar, teja, verde azulado).
Nombres que usa el juego: question, excl, dots, heart, angry, steam, note, star.

icon.png (64x64): la estrella de chapa remendada del logo con su estela, sobre una placa remachada verde azulado.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from ss_ui import hexc, rrect_mask, shrink, edges, paint, ic_star, ic_rep, plate
from ss_logo import star_pts, dilate

INK = '#2a2024'
CREAM = '#f4ecd8'
CREAM_LO = '#d8ccb0'
N = 16
PAD_BOTTOM = 8   # filas vacías bajo el dibujo (el lienzo queda de 16x24)


def outline4(arr, col=INK):
    """Contorno de 1 px (vecindad 4) alrededor de lo opaco, sin salirse del lienzo."""
    a = arr[..., 3] > 0
    ring = ndi.binary_dilation(a, structure=ndi.generate_binary_structure(2, 1)) & ~a
    arr[ring] = hexc(col)
    return arr


def grid(rows, x0, y0, arr, col):
    for j, row in enumerate(rows):
        for i, c in enumerate(row):
            if c == '#':
                arr[y0 + j, x0 + i] = hexc(col)


def bubble16():
    """Globo crema de pensamiento/diálogo con la colita abajo a la izquierda (cuerpo 14x11)."""
    arr = np.zeros((N, N, 4), np.uint8)
    body = np.zeros((N, N), bool)
    body[0:12, 1:15] = rrect_mask(14, 12, r=4)
    paint(arr, body, hexc(INK))
    inner = shrink(body)
    paint(arr, inner, hexc(CREAM))
    t, l, b, r = edges(inner)
    paint(arr, b | r, hexc(CREAM_LO))
    # colita: dos escalones hacia abajo a la izquierda
    for (x, y, c) in ((4, 11, CREAM), (5, 11, CREAM), (3, 12, INK), (4, 12, CREAM), (5, 12, INK), (3, 13, INK),
                      (4, 13, INK), (2, 13, INK), (6, 11, INK)):
        arr[y, x] = hexc(c)
    arr[11, 4] = hexc(CREAM)
    arr[11, 5] = hexc(CREAM_LO)
    return arr


def e_question():
    a = bubble16()
    grid([".####.",
          "##..##",
          "....##",
          "...##.",
          "..##..",
          "......",
          "..##.."], 5, 2, a, '#2a6662')
    return a


def e_excl():
    a = bubble16()
    grid(["##", "##", "##", "##", "##", "..", "##"], 7, 2, a, '#c8402e')
    return a


def e_dots():
    a = bubble16()
    for x in (3, 7, 11):
        a[5:7, x:x + 2] = hexc(INK)
    return a


def e_heart():
    return ic_rep()


def e_star():
    return ic_star()


def e_angry():
    """Marca de enfado (la "vena en cruz"): cuatro esquinas rojas que apuntan al centro, hueco en cruz."""
    q = [".......",
         "....##.",
         "....##.",
         "...###.",
         ".####..",
         ".###...",
         "......."]
    quad = np.array([[c == '#' for c in row] for row in q])
    m14 = np.zeros((14, 14), bool)
    m14[0:7, 0:7] = quad
    m14[0:7, 7:14] = quad[:, ::-1]
    m14[7:14, 0:7] = quad[::-1, :]
    m14[7:14, 7:14] = quad[::-1, ::-1]
    m = np.zeros((N, N), bool)
    m[1:15, 1:15] = m14
    arr = np.zeros((N, N, 4), np.uint8)
    ys, xs = np.mgrid[0:N, 0:N]
    paint(arr, m, hexc('#d8463e'))
    up_ = m & ~np.pad(m, ((1, 0), (0, 0)))[:-1, :]
    paint(arr, up_, hexc('#f07a6a'))
    dn = m & ~np.pad(m, ((0, 1), (0, 0)))[1:, :]
    paint(arr, dn, hexc('#9a2e26'))
    return outline4(arr)


def e_steam():
    """Vapor (enfado de tetera o pensar mucho): una bocanada grande y otra pequeña que sube; sombra gris abajo."""
    arr = np.zeros((N, N, 4), np.uint8)
    ys, xs = np.mgrid[0:N, 0:N]
    big = np.zeros((N, N), bool)
    for (cx, cy, r) in ((4.6, 11.0, 3.0), (8.6, 10.6, 3.2), (6.6, 8.0, 2.8)):
        big |= (xs - cx) ** 2 + (ys - cy) ** 2 <= r * r
    big[14:, :] = False
    small = np.zeros((N, N), bool)
    for (cx, cy, r) in ((11.6, 4.0, 2.2), (13.0, 3.0, 1.4)):
        small |= (xs - cx) ** 2 + (ys - cy) ** 2 <= r * r
    small[:1, :] = False
    small[:, 15:] = False
    for m, low in ((big, 12), (small, 5)):
        paint(arr, m, hexc('#f6f2ea'))
        paint(arr, m & (ys >= low), hexc('#cfc8bc'))
    paint(arr, big & (ys <= 7) & (xs <= 7), hexc('#ffffff'))
    return outline4(arr, '#3a3034')


def e_note():
    """Nota musical de latón (tararear): cabeza ovalada, plica y banderita; contorno de tinta."""
    arr = np.zeros((N, N, 4), np.uint8)
    ys, xs = np.mgrid[0:N, 0:N]
    head = ((xs - 5.6) / 3.0) ** 2 + ((ys - 11.6) / 2.2) ** 2 <= 1.0
    stem = (xs >= 8) & (xs <= 9) & (ys >= 2) & (ys <= 11)
    flag = np.zeros((N, N), bool)
    for (x, y) in ((10, 2), (10, 3), (11, 3), (11, 4), (12, 4), (12, 5), (12, 6), (11, 7)):
        flag[y, x] = True
    flag[2:4, 10] = True
    m = head | stem | flag
    paint(arr, m, hexc('#e8b448'))
    paint(arr, head & (xs <= 4) & (ys <= 11), hexc('#ffe4a0'))
    paint(arr, stem & (xs == 8), hexc('#ffe4a0'))
    paint(arr, (head & (ys >= 13)) | (flag & (xs >= 12)), hexc('#b07a2a'))
    return outline4(arr)


EMOTES = {'question': e_question, 'excl': e_excl, 'dots': e_dots, 'heart': e_heart, 'angry': e_angry,
          'steam': e_steam, 'note': e_note, 'star': e_star}


def app_icon(px=2, S0=32):
    """32x32 nativo, agrandado x2 = 64x64: placa remachada verde azulado + estrella remendada con estela."""
    can = np.zeros((S0, S0, 4), np.uint8)
    pl = plate(S0, S0, '#2e4a48', '#467270', '#1e3230', '#121c1c', rivet=('#7a9a94', '#b4d0c8', '#16201f'), chamfer=4)
    can[:] = pl
    cx, cy = 14.5, 17.0
    # estela (arriba a la derecha)
    for k, (col, w_) in enumerate((('#ffe4a0', 2), ('#eaa23c', 1), ('#c8702e', 1))):
        for t in range(7 + k * 2):
            x = int(cx + 5 + t + k)
            y = int(cy - 5 - t * 0.7 + k * 1.4)
            if 2 <= y < S0 - 2 and 2 <= x < S0 - 3:
                can[y, x:x + w_] = hexc(col)
    im = Image.new('L', (S0, S0), 0)
    ImageDraw.Draw(im).polygon(star_pts(cx, cy, 11.5, 4.9, rot=-90 + 8), fill=255)
    m = np.array(im) > 127
    outm = dilate(m, 1)
    shm = np.zeros_like(outm)
    shm[2:, 2:] = outm[:-2, :-2]
    can[shm & ~outm] = hexc('#0e1616')
    can[outm & ~m] = hexc('#2a1a16')
    yy, xx = np.mgrid[0:S0, 0:S0]
    lit = (xx - cx) * 0.6 + (yy - cy) * 0.8
    can[m & (lit <= -1.5)] = hexc('#f6d27a')
    can[m & (lit > -1.5) & (lit <= 3.5)] = hexc('#dcae4e')
    can[m & (lit > 3.5)] = hexc('#a8783a')
    # costura de soldadura en un brazo + dos remaches
    for t in range(6):
        x = int(cx + 2 + t)
        y = int(cy - 1 + (t % 2) + t * 0.3)
        if m[y, x]:
            can[y, x] = hexc('#6a4424')
    for (x, y) in star_pts(cx, cy, 3.4, 3.4, rot=-90 + 8 + 36)[::2]:
        x, y = int(round(x)), int(round(y))
        if m[y, x]:
            can[y, x] = hexc('#fff0c0')
    return Image.fromarray(can, 'RGBA').resize((S0 * px, S0 * px), Image.NEAREST)


def build_emotes(out):
    d = os.path.join(out, 'icons')
    os.makedirs(d, exist_ok=True)
    for name, fn in EMOTES.items():
        arr = np.pad(fn(), ((0, PAD_BOTTOM), (0, 0), (0, 0)))   # 16x24: dibujo arriba, aire abajo (ver arriba)
        Image.fromarray(arr, 'RGBA').save(os.path.join(d, f'emote_{name}.png'))
    app_icon().save(os.path.join(out, 'icon.png'))
    return sorted(EMOTES)


if __name__ == '__main__':
    args = sys.argv[1:]
    out = './out'
    if '--out' in args:
        out = args[args.index('--out') + 1]
    print('ok emotes', build_emotes(out))
