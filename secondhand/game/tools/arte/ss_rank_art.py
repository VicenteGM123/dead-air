"""Secondhand Stars · ronda 2 · el arte de la interfaz del Lantern Board (línea R, SS2_DESIGN §8.15).

Todo original, sin ninguna letra ni nombre propio en los PNG (los nombres son texto del juego): solo las palabras
sueltas LATE, PAID y GRADED de los sellos de goma (inglés llano, permitido en §8.15).
  board9.png        72x72   9 cortes: marco de latón remachado con el fondo oscuro del tablero (márgenes 18 px)
  flap_cell.png     96x32   2 cuadros de 48x32: la celda de un cartel de persianas (quieta / a medio girar)
  lanterns.png      112x24  7 farolitos de 16x24: brillo 0..3 y latón dorado, plateado, cobrizo (puestos 1-3)
  crests.png        720x24  30 escudos de 24x24 en el orden de Ranking.SHOPS (+ crests.json)
  chart.png         320x180 la carta del Amber Drift dibujada a tinta (sin letras)
  tape9.png         64x64   9 cortes: la cinta de papel (perforaciones a los lados, borde rasgado abajo)
  tape_header.png   480x48  la cabecera de la cinta (banda de tinta, el marquito del retrato, ondas de radio)
  rosa.png          32x32   Rosa Reverb (pelo rizado negro, auriculares grandes, sonrisa, micrófono antiguo)
  stamp_late.png / stamp_paid.png / stamp_graded.png   96x48  sellos de goma
  comet_card.png    256x128 la tarjeta del premio (el cometa de latón)
  award_ribbon.png  96x96   la escarapela de los premios que no son el #1
  icon_{rank,fittings,event,dues,calendar,core,radio}.png        16x16 (como los iconos del kit: se muestran x2)
  event_{sandstorm,inspection,bigfall,festival,race,finale}.png  32x32 pictogramas de los días especiales
Reglas de §10 (lo que NO puede parecer): el emblema de la Tally Office es una marca de conteo (cuatro palos y un
quinto cruzado), nunca un engranaje; el escudo de Shine Again es un destello de 4 puntas largas y 4 cortas, nunca 8
rayos iguales; nada de alfabetos inventados, ni engranaje-sol, ni pájaro redondo, ni media luna con estrella; la moto
del Derby es de un asiento, propulsor gordo atrás y nariz corta (sin aletas largas delante); el núcleo de lámpara es
una bombilla con filamento (no un cristal). The Gilded Gear lleva un reloj dorado (no un engranaje): «Keeps the
Fixers' Guild's clocks» y así el escudo no es un engranaje.
Uso: python3 ss_rank_art.py [--out DIR] [--sheet hoja.png]   (sin --out: escribe en ../../assets/ui)
"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from c64core import Cv, render, bez
from ss_bots import pal_of
from ss_ui import star_poly, rrect_mask, edges, shrink, hexc

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_STENCIL = os.path.join(HERE, 'fonts', 'SairaStencilOne-Regular.ttf')

# el orden de Ranking.SHOPS (crests.png) y el color de su mundo (Ranking.WORLDS)
SHOPS = [('gildedgear', 'hitchpost'), ('deepsalvage', 'shoals'), ('patienthand', 'hollowmere'),
         ('longcounter', 'hitchpost'), ('kilnworks', 'ochre'), ('hornpost', 'brindle'), ('brineswap', 'brineflat'),
         ('fogbellows', 'patina'), ('glassblown', 'saffra'), ('thimble', 'thimble'), ('clockpantry', 'thimble'),
         ('pipeworks', 'patina'), ('rollingbazaar', 'moving'), ('couriercorner', 'hitchpost'), ('orchard', 'teasel'),
         ('unittwelve', 'hitchpost'), ('bikebolt', 'brindle'), ('drybell', 'saffra'), ('moonmoth', 'hollowmere'),
         ('tinpot', 'ochre'), ('pricklyparts', 'saffra'), ('shineagain', 'pink'), ('gutter', 'shoals'),
         ('halfhalf', 'teasel'), ('honestholt', 'brindle'), ('lastbolt', 'brineflat'), ('oddsendings', 'patina'),
         ('fennel', 'teasel'), ('dunepocket', 'saffra'), ('secondhandstar', 'saffra')]
WORLD_COL = {'saffra': '#e8a83a', 'brindle': '#b5523a', 'ochre': '#c8743a', 'patina': '#5f9e86', 'thimble': '#c99d48',
             'hollowmere': '#a98bc4', 'teasel': '#7da26a', 'brineflat': '#7f8f99', 'hitchpost': '#f0c050',
             'shoals': '#4a6a8a', 'moving': '#b08a5a', 'pink': '#e8d8e0'}


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mixc(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade_c(c, k):
    """k > 0 aclara hacia un blanco cálido, k < 0 oscurece hacia un pardo frío."""
    if k >= 0:
        return mixc(c, (255, 246, 222), k)
    return mixc(c, (34, 24, 30), -k)


def up(arr, s):
    im = Image.fromarray(arr, 'RGBA')
    return im.resize((im.width * s, im.height * s), Image.NEAREST)


def blank(w, h):
    return np.zeros((h, w, 4), np.uint8)


def put(arr, mask, c, a=255):
    arr[mask] = (c[0], c[1], c[2], a)


def mask_from(w, h, fn):
    im = Image.new('L', (w, h), 0)
    fn(ImageDraw.Draw(im))
    return np.array(im) > 0


# ================================================================== 9 cortes: el marco de latón del tablero
def board9():
    n = 24
    a = blank(n, n)
    m = rrect_mask(n, n, chamfer=2)
    put(a, m, rgb('#24180f'))
    brass = shrink(m, 1)
    put(a, brass, rgb('#c99a48'))
    t, l, b, r = edges(brass)
    put(a, t | l, rgb('#f2d27e'))
    put(a, b | r, rgb('#7a5420'))
    inner_line = shrink(brass, 3)
    put(a, inner_line, rgb('#2a1d14'))
    inner = shrink(inner_line, 1)
    put(a, inner, rgb('#1d1915'))
    t2, l2, _, _ = edges(inner)
    put(a, t2 | l2, rgb('#2c2620'))
    # brillo del latón: una línea más clara dentro del marco arriba, más oscura abajo
    for x in range(3, n - 3):
        a[2, x] = (*rgb('#e0b860'), 255)
        a[n - 3, x] = (*rgb('#9c6e2c'), 255)
    for (x, y) in ((2, 2), (n - 3, 2), (2, n - 3), (n - 3, n - 3)):
        a[y, x] = (*rgb('#fff0c0'), 255)
        a[y + 1, x] = (*rgb('#6a4818'), 255)
    return up(a, 3)


# ================================================================== la celda del cartel de persianas
def flap_cell():
    w, h = 24, 16
    frames = []
    for fr in (0, 1):
        a = blank(w, h)
        m = rrect_mask(w, h, chamfer=1)
        put(a, m, rgb('#0e0c0b'))
        body = shrink(m, 1)
        top = body & (np.mgrid[0:h, 0:w][0] < 8)
        bot = body & ~top
        put(a, top, rgb('#2b2622') if fr == 0 else rgb('#16130f'))
        put(a, bot, rgb('#221e1b'))
        # bisel: arriba más claro
        for x in range(2, w - 2):
            a[1, x] = (*rgb('#3c3530' if fr == 0 else '#1f1b17'), 255)
        # la raya del medio (las dos persianas) y su brillo
        for x in range(1, w - 1):
            a[7, x] = (*rgb('#0a0807'), 255)
            a[8, x] = (*rgb('#353029'), 255)
        # los pernos de las bisagras
        for x in (0, w - 1):
            a[7, x] = (*rgb('#7a6e62'), 255)
            a[8, x] = (*rgb('#4a423a'), 255)
        if fr == 1:
            # la persiana de arriba cayendo: un canto claro a media altura
            for x in range(2, w - 2):
                a[4, x] = (*rgb('#4a4239'), 255)
                a[5, x] = (*rgb('#0c0a09'), 255)
        frames.append(a)
    strip = np.concatenate(frames, axis=1)
    return up(strip, 2)


# ================================================================== los farolitos (brillo por franja; oro/plata/cobre)
def lanterns():
    w, h = 8, 12
    glass = ['#3a3028', '#8a5226', '#e0962e', '#ffd36a']
    frames = []
    looks = [(i, '#4a4038', '#2a221c') for i in range(4)] + [(3, '#f0c050', '#8a6020'), (3, '#d6dae2', '#6a6e78'),
                                                              (3, '#d08a50', '#7a4420')]
    for (g, metal, metal_dk) in looks:
        a = blank(w, h)
        mc, md = rgb(metal), rgb(metal_dk)
        # asa y gancho
        a[0, 3:5] = (*md, 255)
        a[1, 2] = (*md, 255)
        a[1, 5] = (*md, 255)
        # sombrero
        a[2, 2:6] = (*mc, 255)
        a[3, 1:7] = (*mc, 255)
        a[3, 6] = (*md, 255)
        # vidrio
        gc = rgb(glass[g])
        for y in range(4, 10):
            a[y, 1] = (*md, 255)
            a[y, 6] = (*md, 255)
            a[y, 2:6] = (*gc, 255)
        if g >= 2:
            hot = rgb('#fff4c8') if g == 3 else rgb('#ffcc66')
            a[6:8, 3:5] = (*hot, 255)
        if g == 0:
            a[8, 3] = (*rgb('#6a3a20'), 255)     # una brasa apagada
        else:
            a[5, 2] = (*shade_c(gc, 0.45), 255)  # reflejo
        # base
        a[10, 1:7] = (*mc, 255)
        a[11, 2:6] = (*md, 255)
        frames.append(a)
    return up(np.concatenate(frames, axis=1), 2)


# ================================================================== los escudos (24x24)
def crest_plate(col):
    n = 24
    a = blank(n, n)
    base = rgb(col)
    m = rrect_mask(n - 2, n - 2, chamfer=3)
    mm = np.zeros((n, n), bool)
    mm[1:n - 1, 1:n - 1] = m
    put(a, mm, shade_c(base, -0.72))
    body = shrink(mm, 1)
    put(a, body, base)
    t, l, b, r = edges(body)
    put(a, t | l, shade_c(base, 0.45))
    put(a, b | r, shade_c(base, -0.35))
    # vetas suaves de chapa
    for y in range(4, n - 4, 4):
        row = body.copy()
        row[:y] = False
        row[y + 1:] = False
        put(a, row & ~(t | l | b | r), shade_c(base, 0.08))
    for (x, y) in ((4, 4), (n - 5, 4)):
        a[y, x] = (*shade_c(base, 0.7), 255)
        a[y + 1, x] = (*shade_c(base, -0.5), 255)
    return a, base


def glyph_on(a, base, mask, ink=None, dark=None):
    """El pictograma en crema con una sombra de 1 px (abajo a la derecha) del color oscuro del escudo."""
    ink = ink or rgb('#f6eedb')
    dark = dark or shade_c(base, -0.62)
    sh = np.zeros_like(mask)
    sh[1:, 1:] = mask[:-1, :-1]
    put(a, sh & ~mask, dark)
    put(a, mask, ink)


def poly_mask(pts, n=24):
    return mask_from(n, n, lambda d: d.polygon(pts, fill=1))


def ell(cx, cy, rx, ry, n=24):
    ys, xs = np.mgrid[0:n, 0:n]
    return ((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2 <= 1.0


def lines_mask(segs, width=1, n=24):
    return mask_from(n, n, lambda d: [d.line(s, fill=1, width=width) for s in segs])


def star_mask(cx, cy, ro, ri, n=24, rot=-90):
    return poly_mask(star_poly(cx, cy, ro, ri, rot), n)


def crest_glyph(cid):
    """La máscara del pictograma de cada tienda (zona útil ~5..18)."""
    n = 24
    ys, xs = np.mgrid[0:n, 0:n]
    if cid == 'gildedgear':      # un reloj dorado (no un engranaje): esfera, dos agujas, campanita
        m = ell(11.5, 12.5, 6.2, 6.2) & ~ell(11.5, 12.5, 4.6, 4.6)
        m |= lines_mask([[(11.5, 12.5), (11.5, 9)], [(11.5, 12.5), (14, 13.5)]])
        m |= ell(11.5, 4.6, 1.6, 1.3)
        for k in range(4):
            ang = k * math.pi / 2
            m[int(round(12.5 + 5.4 * math.sin(ang))), int(round(11.5 + 5.4 * math.cos(ang)))] = True
        return m
    if cid == 'deepsalvage':     # gancho de remolque con un eslabón
        m = ell(11.5, 13.5, 5.0, 5.0) & ~ell(11.5, 13.5, 3.2, 3.2) & ~((xs > 11) & (ys < 13))
        m |= lines_mask([[(16, 13), (16, 7)]], 2) | (ell(16, 5.5, 2.0, 2.0) & ~ell(16, 5.5, 0.9, 0.9))
        m |= poly_mask([(6, 13), (8.5, 10.5), (9, 14)])
        return m
    if cid == 'patienthand':     # la palma abierta
        m = ell(11.5, 15, 4.5, 4.2)
        for i, (x, top) in enumerate(((8, 8), (10.3, 6.5), (12.7, 6.5), (15, 8))):
            m |= lines_mask([[(x, top), (x, 13)]], 2)
        m |= lines_mask([[(7, 16), (5, 12.5)]], 2)
        return m
    if cid == 'longcounter':     # el mostrador largo y su timbre
        m = (xs >= 4) & (xs <= 19) & (ys >= 13) & (ys <= 15)
        m |= ((xs == 5) | (xs == 18)) & (ys >= 15) & (ys <= 18)
        m |= ell(11.5, 11, 2.6, 2.0) & (ys <= 11)
        m |= (xs == 11) & (ys == 8) | (xs == 12) & (ys == 8)
        return m
    if cid == 'kilnworks':       # vasija y llama
        m = ell(11.5, 14.5, 5.0, 4.6) | ((xs >= 9) & (xs <= 14) & (ys >= 9) & (ys <= 11))
        m |= (xs >= 8) & (xs <= 15) & (ys == 9)
        m &= ~(ell(11.5, 14.5, 2.0, 1.6))
        m |= poly_mask([(10, 7), (11.5, 3), (13, 7)])
        return m
    if cid == 'hornpost':        # un cuerno
        pts = [(5, 17), (8, 16), (12, 13), (15, 9), (17, 5)]
        m = np.zeros((n, n), bool)
        for i in range(len(pts) - 1):
            m |= lines_mask([[pts[i], pts[i + 1]]], 4 - i // 2 if i < 2 else 2)
        m |= ell(5, 17, 2.4, 2.4)
        return m
    if cid == 'brineswap':       # concha de vieira
        m = poly_mask([(11.5, 17), (4.5, 9), (6.5, 6), (11.5, 4.5), (16.5, 6), (18.5, 9)])
        m &= ~lines_mask([[(11.5, 16), (8, 6)], [(11.5, 16), (11.5, 5)], [(11.5, 16), (15, 6)]])
        m |= (xs >= 10) & (xs <= 13) & (ys >= 17) & (ys <= 18)
        return m
    if cid == 'fogbellows':      # casco de buzo con mirilla
        m = ell(11.5, 11.5, 6.5, 6.5) & ~ell(11.5, 11.5, 3.0, 3.0)
        m |= (xs >= 6) & (xs <= 17) & (ys >= 17) & (ys <= 18)
        for (x, y) in ((11.5, 7.2), (7.2, 11.5), (15.8, 11.5), (11.5, 15.8)):
            m[int(y), int(x)] = False
        return m
    if cid == 'glassblown':      # reloj de arena
        m = poly_mask([(7, 5), (16, 5), (12.5, 11.5), (10.5, 11.5)]) | poly_mask([(10.5, 12.5), (12.5, 12.5), (16, 18), (7, 18)])
        m |= (xs >= 5) & (xs <= 18) & ((ys == 4) | (ys == 19))
        m &= ~(poly_mask([(9, 6), (14, 6), (12, 9), (11, 9)]))
        return m
    if cid == 'thimble':         # dedal con puntitos
        m = poly_mask([(7.5, 18), (8, 9), (10, 6), (13, 6), (15, 9), (15.5, 18)])
        for (x, y) in ((10, 9), (13, 9), (11.5, 11), (9.5, 13), (13.5, 13), (11.5, 15)):
            m[y, int(x)] = False
        m |= (xs >= 6) & (xs <= 17) & (ys >= 17) & (ys <= 18)
        return m
    if cid == 'clockpantry':     # taza con ojitos y antena (un bot de té)
        m = poly_mask([(6, 9), (16, 9), (15, 16), (7, 16)])
        m |= ell(17.5, 12, 2.4, 2.4) & ~ell(17.5, 12, 1.0, 1.0)
        m |= (xs >= 5) & (xs <= 17) & (ys == 17)
        m &= ~(((xs == 9) | (xs == 13)) & (ys == 12))
        m |= lines_mask([[(11, 9), (11, 5)]]) | ell(11, 4.5, 1.2, 1.2)
        return m
    if cid == 'pipeworks':       # codo de tubería con bridas
        m = ((xs >= 6) & (xs <= 10) & (ys >= 5) & (ys <= 16)) | ((xs >= 6) & (xs <= 18) & (ys >= 12) & (ys <= 16))
        m |= (xs >= 5) & (xs <= 11) & (ys >= 4) & (ys <= 5)
        m |= (xs >= 17) & (xs <= 18) & (ys >= 11) & (ys <= 17)
        m &= ~(((xs >= 7) & (xs <= 9) & (ys >= 6) & (ys <= 13)) | ((xs >= 10) & (xs <= 16) & (ys >= 13) & (ys <= 15)))
        return m
    if cid == 'rollingbazaar':   # tortuga de perfil: caparazón en cúpula, cabeza, cuatro patas cortas (nunca un tanque)
        m = ell(10.5, 13.5, 6.6, 6.0) & (ys <= 13)
        m |= ell(18.4, 13.2, 2.5, 2.1)
        m[12, 19] = False
        for x in (6, 9, 12, 15):
            m |= (xs >= x) & (xs <= x + 1) & (ys >= 15) & (ys <= 17)
        m |= lines_mask([[(4, 13), (2, 14)]])
        m &= ~((ys == 11) & (xs >= 6) & (xs <= 15) & (xs % 3 == 0))   # tres placas del caparazón
        return m
    if cid == 'couriercorner':   # pluma
        m = poly_mask([(17, 4), (19, 6), (10, 16), (7, 17), (8, 14)])
        m &= ~lines_mask([[(17.5, 5.5), (8.5, 15.5)]])
        m |= lines_mask([[(8, 15), (5, 19)]])
        return m
    if cid == 'orchard':         # manzana y llave
        m = ell(10, 13, 4.6, 4.6) | ell(13, 13, 4.0, 4.4)
        m &= ~ell(11.5, 8.6, 1.4, 1.0)
        m |= lines_mask([[(11.5, 9), (12.5, 5)]]) | poly_mask([(13, 6), (17, 4), (15, 7)])
        m &= ~lines_mask([[(8, 17), (15, 10)]])
        return m
    if cid == 'unittwelve':      # tornillo
        m = (xs >= 7) & (xs <= 16) & (ys >= 4) & (ys <= 7)
        m &= ~((xs == 11) | (xs == 12)) | (ys > 5)
        m |= (xs >= 10) & (xs <= 13) & (ys >= 8) & (ys <= 17)
        for y in range(9, 17, 2):
            m[y, 9] = True
            m[y + 1, 14] = True
        m |= (xs >= 11) & (xs <= 12) & (ys == 18)
        return m
    if cid == 'bikebolt':        # moto de un asiento: propulsor gordo atrás, nariz corta, flota
        m = ell(7.5, 11.5, 3.8, 3.6)                     # el propulsor
        m &= ~ell(5.6, 11.5, 1.6, 1.8)                   # la tobera
        m |= poly_mask([(8, 9), (15, 10), (19, 12.5), (15, 14), (8, 14)])
        m |= (xs >= 10) & (xs <= 14) & (ys >= 7) & (ys <= 8)   # el asiento
        m |= (xs == 15) & (ys >= 7) & (ys <= 9)          # el manillar
        m |= lines_mask([[(7, 17), (17, 17)]])           # la sombra (flota)
        return m
    if cid == 'drybell':         # broca en espiral
        m = poly_mask([(9, 4), (14, 4), (14, 14), (11.5, 19), (9, 14)])
        m &= ~lines_mask([[(9, 7), (14, 9)], [(9, 10), (14, 12)], [(9, 13), (13, 15)]])
        return m
    if cid == 'moonmoth':        # polilla de frente: alas grandes abiertas en V, cuerpo fino, antenas
        m = poly_mask([(11, 8), (3, 4), (2, 9), (5, 13), (11, 12)]) | poly_mask([(12, 8), (20, 4), (21, 9), (18, 13), (12, 12)])
        m |= poly_mask([(11, 12), (6, 14), (7, 18), (11, 15)]) | poly_mask([(12, 12), (17, 14), (16, 18), (12, 15)])
        m &= ~(ell(6.5, 8.5, 1.3, 1.3) | ell(16.5, 8.5, 1.3, 1.3))
        m |= (xs >= 11) & (xs <= 12) & (ys >= 7) & (ys <= 17)
        m |= lines_mask([[(11, 7), (9, 3)], [(12, 7), (14, 3)]])
        return m
    if cid == 'tinpot':          # olla con mango
        m = (xs >= 6) & (xs <= 15) & (ys >= 9) & (ys <= 17)
        m |= (xs >= 5) & (xs <= 16) & (ys == 8)
        m |= lines_mask([[(16, 10), (20, 9)]], 2)
        m |= (xs >= 9) & (xs <= 12) & (ys == 6) | (xs >= 10) & (xs <= 11) & (ys == 5)
        m &= ~((xs >= 7) & (xs <= 14) & (ys == 12))
        return m
    if cid == 'pricklyparts':    # cactus con flor
        m = (xs >= 10) & (xs <= 13) & (ys >= 6) & (ys <= 18)
        m |= (xs >= 6) & (xs <= 7) & (ys >= 9) & (ys <= 13) | (xs >= 6) & (xs <= 10) & (ys >= 13) & (ys <= 14)
        m |= (xs >= 16) & (xs <= 17) & (ys >= 8) & (ys <= 12) | (xs >= 13) & (xs <= 17) & (ys >= 12) & (ys <= 13)
        m |= (xs >= 7) & (xs <= 16) & (ys >= 18) & (ys <= 19)
        return m
    if cid == 'shineagain':      # el destello: 4 puntas largas y 4 cortas, macizo
        pts = []
        for k in range(16):
            ang = math.radians(-90 + k * 22.5)
            r = (7.6 if k % 4 == 0 else (4.2 if k % 4 == 2 else 2.2))
            pts.append((11.5 + math.cos(ang) * r, 12 + math.sin(ang) * r))
        return poly_mask(pts)
    if cid == 'gutter':          # perno partido
        m = poly_mask([(6, 6), (11, 6), (10, 10), (6, 10)]) | poly_mask([(8, 10), (10, 10), (9.5, 12), (8, 12)])
        m |= poly_mask([(13, 13), (15, 13), (15, 18), (13, 18)]) | poly_mask([(12, 11), (16, 11), (15.5, 13), (12, 13)])
        m |= lines_mask([[(15, 5), (17, 3)], [(17, 7), (19, 7)]])
        return m
    if cid == 'halfhalf':        # moneda mitad y mitad (sin media luna con estrella)
        m = ell(11.5, 11.5, 6.4, 6.4) & ~ell(11.5, 11.5, 5.0, 5.0)
        m |= ell(11.5, 11.5, 5.0, 5.0) & (xs <= 11)
        m |= (xs == 11) & (ys >= 5) & (ys <= 18)
        return m
    if cid == 'honestholt':      # una aureola tachada (el chiste de Honest Holt's)
        m = ell(11.5, 11.5, 7.0, 3.4) & ~ell(11.5, 11.5, 5.2, 2.0)
        m |= lines_mask([[(5, 18), (18, 5)]], 2)
        return m
    if cid == 'lastbolt':        # el último perno, de pie
        m = (xs >= 7) & (xs <= 16) & (ys >= 4) & (ys <= 8)
        m &= ~(((xs == 7) | (xs == 16)) & ((ys == 4) | (ys == 8)))
        m |= (xs >= 10) & (xs <= 13) & (ys >= 9) & (ys <= 18)
        for y in range(10, 18, 2):
            m[y, 10:14] = False
            m[y, 10] = True
        return m
    if cid == 'oddsendings':     # media tetera: la mitad de la izquierda maciza, la otra mitad solo punteada
        m = ell(12, 13.5, 6.4, 4.8) & (xs <= 12)
        m |= poly_mask([(7, 12), (2.5, 8.5), (2, 10), (6.5, 15)])
        m |= (xs >= 9) & (xs <= 12) & (ys == 8) | (xs >= 10) & (xs <= 12) & (ys == 7)
        m |= (xs >= 7) & (xs <= 12) & (ys == 18)
        half = ell(12, 13.5, 6.4, 4.8) & ~ell(12, 13.5, 5.4, 3.8) & (xs > 13)
        m |= half & ((xs + ys) % 2 == 0)
        m |= ((xs == 20) | (xs == 19)) & (ys >= 11) & (ys <= 15) & (ys % 2 == 1)
        return m
    if cid == 'fennel':          # cerca: dos postes y dos travesaños
        m = ((xs >= 6) & (xs <= 8) | (xs >= 15) & (xs <= 17)) & (ys >= 6) & (ys <= 18)
        m |= poly_mask([(6, 6), (7, 4), (8, 6)]) | poly_mask([(15, 6), (16, 4), (17, 6)])
        m |= (xs >= 4) & (xs <= 19) & ((ys == 9) | (ys == 10) | (ys == 14) | (ys == 15))
        return m
    if cid == 'dunepocket':      # una manta doblada y una estrellita
        m = poly_mask([(4, 14), (19, 13), (19, 18), (4, 19)])
        m &= ~lines_mask([[(4, 16), (19, 15)]])
        m |= star_mask(11.5, 7.5, 4.4, 1.9)
        return m
    if cid == 'secondhandstar':  # la estrella remendada de Nell
        m = star_mask(11.5, 12.2, 8.2, 3.4)
        return m
    return ell(11.5, 11.5, 5, 5)


def crests():
    cells = []
    for cid, world in SHOPS:
        a, base = crest_plate(WORLD_COL[world])
        g = crest_glyph(cid)
        if cid == 'shineagain':
            glyph_on(a, base, g, ink=rgb('#e85a9a'), dark=rgb('#8a2a5a'))
        elif cid == 'secondhandstar':
            glyph_on(a, base, g, ink=rgb('#ffe08a'), dark=rgb('#7a4a18'))
            # el parche: un cuadrado más oscuro con dos puntadas
            patch = np.zeros((24, 24), bool)
            patch[12:16, 12:16] = True
            patch &= g
            put(a, patch, rgb('#c0782a'))
            for (x, y) in ((12, 11), (16, 13), (14, 16), (11, 15)):
                if 0 <= y < 24:
                    a[y, x] = (*rgb('#5a3014'), 255)
        elif cid == 'gildedgear':
            glyph_on(a, base, g, ink=rgb('#fff2c4'), dark=rgb('#6a4a10'))
        else:
            glyph_on(a, base, g)
        cells.append(a)
    return Image.fromarray(np.concatenate(cells, axis=1), 'RGBA')


# ================================================================== la carta del Amber Drift (tinta sobre pergamino)
CHART_WORLDS = [  # (id, x, y) en 160x90
    ('saffra', 34, 60), ('brindle', 18, 34), ('ochre', 56, 30), ('patina', 82, 52), ('thimble', 98, 22),
    ('hollowmere', 118, 44), ('teasel', 136, 66), ('brineflat', 106, 74), ('hitchpost', 66, 70), ('shoals', 146, 24)]


def chart():
    w, h = 160, 90
    rng = np.random.default_rng(42)
    ys, xs = np.mgrid[0:h, 0:w]
    # pergamino: borde más tostado, manchitas
    edge = np.minimum(np.minimum(xs, w - 1 - xs), np.minimum(ys, h - 1 - ys)).astype(float)
    t = np.clip(edge / 10.0, 0, 1)
    base = np.array(rgb('#e8d9b0'), float)
    dark = np.array(rgb('#c9b07a'), float)
    img = dark[None, None, :] * (1 - t[..., None]) + base[None, None, :] * t[..., None]
    noise = rng.random((h, w))
    img[noise > 0.985] = np.array(rgb('#d6c38e'))
    for (cx, cy, r) in ((128, 16, 7), (22, 76, 5)):
        st = ((xs - cx) ** 2 + (ys - cy) ** 2) < r * r
        img[st] = img[st] * 0.94
    a = np.zeros((h, w, 4), np.uint8)
    a[..., :3] = np.clip(img, 0, 255).astype(np.uint8)
    a[..., 3] = 255
    # bordes rotos (unos píxeles transparentes en las esquinas)
    for (x, y) in ((0, 0), (1, 0), (0, 1), (w - 1, 0), (w - 2, 0), (w - 1, h - 1), (0, h - 1), (0, h - 2)):
        a[y, x, 3] = 0
    ink = rgb('#3a2a1e')
    pim = Image.fromarray(a, 'RGBA')
    d = ImageDraw.Draw(pim)
    # la ruta de chatarra (punteada) que une los mundos en orden de viaje
    route = ['brindle', 'saffra', 'hitchpost', 'patina', 'ochre', 'thimble', 'hollowmere', 'brineflat', 'teasel']
    pos = {k: (x, y) for k, x, y in CHART_WORLDS}
    pts = []
    for i in range(len(route) - 1):
        p0, p1 = pos[route[i]], pos[route[i + 1]]
        mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 - 6
        for k in range(14):
            u = k / 14
            pts.append(((1 - u) ** 2 * p0[0] + 2 * (1 - u) * u * mx + u * u * p1[0],
                        (1 - u) ** 2 * p0[1] + 2 * (1 - u) * u * my + u * u * p1[1]))
    pts.append(pos[route[-1]])
    for i, p in enumerate(pts):
        if i % 2 == 0:
            d.point((round(p[0]), round(p[1])), fill=ink + (255,))
    # la ruta hacia los Bajíos (más tenue, rayitas)
    for k in range(0, 18, 3):
        u = k / 18
        x = pos['thimble'][0] + (pos['shoals'][0] - pos['thimble'][0]) * u
        y = pos['thimble'][1] + (pos['shoals'][1] - pos['thimble'][1]) * u
        d.line([(round(x), round(y)), (round(x) + 1, round(y))], fill=rgb('#6a5440') + (255,))
    # los Bajíos: un arrecife de puntitos alrededor de una estrella muerta
    sx, sy = pos['shoals']
    for k in range(10):
        ang = k * 2 * math.pi / 10
        d.point((round(sx + 6 * math.cos(ang)), round(sy + 4 * math.sin(ang))), fill=ink + (255,))
    # los mundos: círculos con su color y contorno de tinta
    for k, x, y in CHART_WORLDS:
        col = rgb(WORLD_COL[k])
        r = 3 if k not in ('hitchpost', 'saffra') else 4
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (255,), outline=ink + (255,))
        d.point((x - 1, y - 1), fill=shade_c(col, 0.5) + (255,))
        if k == 'hitchpost':      # la estación: anillo doble
            d.ellipse([x - 6, y - 6, x + 6, y + 6], outline=ink + (255,))
        if k == 'saffra':         # el anillo de chatarra en el cielo: un arco roto y tenue
            for kk in range(0, 22):
                if kk % 4 == 3:
                    continue
                ang = math.radians(200 + kk * 6)
                d.point((round(x + 8 * math.cos(ang)), round(y + 3 * math.sin(ang) - 1)), fill=rgb('#7a6450') + (255,))
    # Nell: una estrellita al lado de Saffra
    nx, ny = pos['saffra']
    st = star_poly(nx + 9, ny + 7, 3.4, 1.4)
    d.polygon(st, fill=rgb('#f0b440') + (255,), outline=ink + (255,))
    # Ledger, fuera del mapa: un cuadradito mostaza más allá de una línea de rayas
    for y in range(4, 30, 3):
        d.point((150, y), fill=rgb('#7a6450') + (255,))
    d.rectangle([152, 8, 155, 11], fill=rgb('#c8a030') + (255,), outline=ink + (255,))
    # rosa de los vientos: estrella de 4 puntas sin letras
    cx, cy = 14, 12
    rose = []
    for k in range(8):
        ang = math.radians(-90 + k * 45)
        r = 7 if k % 2 == 0 else 2.2
        rose.append((cx + math.cos(ang) * r, cy + math.sin(ang) * r))
    d.polygon(rose, fill=rgb('#d8c08a') + (255,), outline=ink + (255,))
    d.line([(cx, cy - 7), (cx, cy - 2)], fill=ink + (255,))
    # un marco a tinta, a mano
    d.rectangle([3, 3, w - 4, h - 4], outline=rgb('#8a7050') + (255,))
    return pim.resize((w * 2, h * 2), Image.NEAREST)


# ================================================================== la cinta de papel (9 cortes) y su cabecera
PAPER = rgb('#efe6cf')
PAPER_DK = rgb('#e2d6b8')
PERF = rgb('#a8987a')


def _paper(w, h, seed=3):
    rng = np.random.default_rng(seed)
    a = blank(w, h)
    put(a, np.ones((h, w), bool), PAPER)
    fib = rng.random((h, w)) > 0.93
    put(a, fib, PAPER_DK)
    return a


def _perf_margin(a, x0, period=10, y0=2, h=None):
    h = a.shape[0] if h is None else h
    for y in range(y0, h, period):
        if y + 2 < a.shape[0]:
            a[y:y + 3, x0:x0 + 3] = (*PERF, 255)
            a[y + 1, x0 + 1] = (0, 0, 0, 0)
    for y in range(0, a.shape[0], 2):   # la línea de corte punteada
        a[y, x0 + 5 if x0 < a.shape[1] // 2 else x0 - 3] = (*rgb('#d4c6a4'), 255)


def tape9():
    w = h = 32
    a = _paper(w, h)
    # márgenes perforados: izquierda x 2..4, derecha x 27..29; período 10 (el centro del 9 cortes mide 20)
    for x0 in (2, 27):
        for y in (4 + 5, 4 + 15):
            a[y - 1:y + 2, x0:x0 + 3] = (*PERF, 255)
            a[y, x0 + 1] = (0, 0, 0, 0)
    for y in range(0, h, 2):
        a[y, 7] = (*rgb('#d6c8a6'), 255)
        a[y, 24] = (*rgb('#d6c8a6'), 255)
    # borde rasgado abajo (las últimas 8 filas = el margen de abajo del 9 cortes)
    rng = np.random.default_rng(9)
    prof = [26 + int(v) for v in rng.integers(0, 5, size=w)]
    for x in range(w):
        a[prof[x]:, x] = 0
        if prof[x] - 1 >= 0:
            a[prof[x] - 1, x] = (*rgb('#d8caa8'), 255)
    return up(a, 2)


def tape_header():
    w, h = 240, 24
    a = _paper(w, h, seed=5)
    for x0 in (2, 235):
        for y in (4, 14):
            a[y - 1:y + 2, x0:x0 + 3] = (*PERF, 255)
            a[y, x0 + 1] = (0, 0, 0, 0)
    for y in range(0, h, 2):
        a[y, 7] = (*rgb('#d6c8a6'), 255)
        a[y, 232] = (*rgb('#d6c8a6'), 255)
    # la banda de tinta (impresa: una trama de puntos un poco más clara)
    band = np.zeros((h, w), bool)
    band[3:19, 10:230] = True
    put(a, band, rgb('#2b211b'))
    ys, xs = np.mgrid[0:h, 0:w]
    dots = band & ((xs + ys) % 4 == 0)
    put(a, dots, rgb('#3a2e26'))
    # el marquito del retrato (Rosa se pone encima: 32x32 en pantalla = 16 nativos)
    fr = np.zeros((h, w), bool)
    fr[2:20, 12:30] = True
    put(a, fr, rgb('#c99a48'))
    inn = np.zeros((h, w), bool)
    inn[3:19, 13:29] = True
    put(a, inn, rgb('#1a1410'))
    # ondas de radio (arcos crema) a la derecha
    pim = Image.fromarray(a, 'RGBA')
    d = ImageDraw.Draw(pim)
    cx, cy = 222, 11
    for r in (3, 6, 9):
        d.arc([cx - r, cy - r, cx + r, cy + r], 120, 240, fill=rgb('#e8d8b0') + (255,))
    d.ellipse([cx - 1, cy - 1, cx + 1, cy + 1], fill=rgb('#f0c050') + (255,))
    # línea de impresión punteada bajo la banda
    for x in range(10, 230, 3):
        d.point((x, 21), fill=rgb('#8a7a60') + (255,))
    return pim.resize((w * 2, h * 2), Image.NEAREST)


# ================================================================== los sellos de goma
def stamp(word, ink_hex, seed, wide=96, tall=48, size=27):
    ink = rgb(ink_hex)
    big = Image.new('L', (wide * 2, tall * 2), 0)
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([4, 4, wide * 2 - 5, tall * 2 - 5], radius=10, outline=255, width=5)
    d.rounded_rectangle([12, 12, wide * 2 - 13, tall * 2 - 13], radius=6, outline=255, width=2)
    f = ImageFont.truetype(FONT_STENCIL, size * 2)
    bb = d.textbbox((0, 0), word, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text(((wide * 2 - tw) / 2 - bb[0], (tall * 2 - th) / 2 - bb[1]), word, fill=255, font=f)
    big = big.rotate(-4, resample=Image.BICUBIC, expand=False)
    small = big.resize((wide, tall), Image.BOX)
    m = np.array(small) > 110
    rng = np.random.default_rng(seed)
    m &= rng.random(m.shape) > 0.10            # la tinta que no agarró
    a = blank(wide, tall)
    put(a, m, ink, 235)
    edge = m & (rng.random(m.shape) > 0.7)
    put(a, edge, shade_c(ink, -0.2), 245)
    return Image.fromarray(a, 'RGBA')


# ================================================================== Cv: los dibujos sombreados (iconos, pictogramas...)
MATS = {
    'brass': ('#e8b448', 'metal'), 'brass2': ('#b07a2a', 'metal'), 'copper': ('#c87a48', 'metal'),
    'steel': ('#b4b8c2', 'metal'), 'dkmetal': ('#5a5660', 'metal'), 'chrome': ('#d0d4dc', 'metal'),
    'wood': ('#a06a3e', 'leather'), 'paper': ('#ece2c8', 'white'), 'cream': ('#ece2c8', 'white'),
    'glass': ('#c4dce4', 'white'), 'glow': ('#ffd36a', 'flat'), 'glow2': ('#ffb040', 'flat'), 'ember': ('#e8642e', 'gem'),
    'teal': '#3e9a92', 'teal2': '#2a6662', 'red': ('#c8463a', 'cloth'), 'sand': ('#e8a838', 'cloth'),
    'dune': ('#c8843a', 'cloth'), 'smoke': ('#d8d0c4', 'flat'), 'dark': ('#2a2226', 'flat'), 'ink': ('#2a2024', 'flat'),
    'mustard': ('#d8a830', 'cloth'), 'moon_cu': ('#e0957a', 'skin'), 'moon_tin': ('#b8c8dc', 'cloth'),
    'night': ('#2a3050', 'flat'), 'star': ('#f0b440', 'metal'), 'pink': ('#e85a9a', 'cloth'),
    'skin': ('#9a6444', 'skin'), 'hair': ('#221a1c', 'flat'), 'lip': ('#b04a3a', 'cloth'), 'white': ('#f4f0e8', 'flat'),
    'card': ('#d89a3a', 'cloth'), 'bronze': ('#b8783a', 'metal'), 'green': ('#4a9a5a', 'cloth'),
    'parch': ('#f0dcae', 'cloth'),
}


def cv(w, h):
    pal, kinds = pal_of(MATS, accents=('teal', 'ember', 'red', 'sand', 'star', 'brass', 'pink', 'glow', 'mustard'))
    return Cv(pal, w=w, h=h, kinds=kinds)


def keep(c, p):
    c.parts[p].keep = True
    return p


# --- iconos 16x16
def ic_rank():
    """Un farolito con una estrella (el Lantern Board)."""
    c = cv(16, 16)
    c.put(c.rect(6, 0, 9, 1), 'dkmetal', mode='flat', iline=True)
    c.put(c.poly([(3.5, 4), (12.5, 4), (11, 2), (5, 2)]), 'brass', mode='top', cast=1, iline=True)
    g = c.put(c.rect(4, 5, 11, 12), 'glow', mode='flat')
    c.paint(c.poly(star_poly(7.5, 8.6, 3.0, 1.3)), 'white', 3)
    for x in (4, 11):
        c.put(c.rect(x, 5, x, 12), 'brass2', mode='flat', iline=True)
    c.put(c.rect(3, 13, 12, 14), 'brass', mode='top', cast=1, iline=True)
    return render(c)


def ic_fittings():
    """Una caja con correa y un perno (las mejoras de Dolly)."""
    c = cv(16, 16)
    p = c.put(c.rect(2, 5, 13, 14), 'wood', mode='top', cast=1, iline=True)
    c.paint(c.rect(2, 9, 13, 10), 'teal', 2, within=[p])
    c.paint(c.rect(7, 5, 8, 14), 'teal', 2, within=[p])
    c.put(c.ellipse(7.5, 3.0, 2.6, 2.0), 'steel', mode='shine', cast=1, iline=True)
    c.dot(7, 2, 'white', 4)
    return render(c)


def ic_event():
    """Un banderín con una estrella (el día especial)."""
    c = cv(16, 16)
    c.put(c.rect(3, 1, 3, 15), 'wood', mode='flat', iline=True)
    p = c.put(c.poly([(4, 2), (14, 5), (4, 9)]), 'red', mode='cyl', cast=1, iline=True)
    c.paint(c.poly(star_poly(7.4, 5.4, 2.4, 1.0)), 'glow', 3, within=[p])
    return render(c)


def ic_dues():
    """Dos monedas apiladas y la marca de la oficina (la cuota del muelle)."""
    c = cv(16, 16)
    for (cy, n) in ((12.0, 0), (9.5, 1)):
        c.put(c.ellipse(7.0, cy, 5.6, 2.4), 'brass', mode='top', cast=1, iline=True)
        c.put(c.rect(1.4, cy, 12.6, cy + 1.6) & ~c.ellipse(7.0, cy + 2.6, 5.6, 2.4) | c.ellipse(7.0, cy + 1.6, 5.6, 2.4),
              'brass2', mode='cyl', cast=1, iline=True)
    c.put(c.ellipse(7.0, 9.5, 5.6, 2.4), 'brass', mode='top', iline=True)
    # el sello: cuatro palitos cruzados por un quinto
    q = c.put(c.line([(10, 1), (10, 5)]) | c.line([(12, 1), (12, 5)]) | c.line([(14, 1), (14, 5)]) | c.line([(9, 4), (15, 2)]),
              'red', mode='flat', outline=False)
    keep(c, q)
    return render(c)


def ic_calendar():
    """Una hoja de calendario con argollas y un día marcado."""
    c = cv(16, 16)
    p = c.put(c.rect(2, 3, 13, 14), 'paper', mode='flat', cast=1, iline=True)
    c.paint(c.rect(2, 3, 13, 5), 'red', 2, within=[p])
    for x in (5, 10):
        c.put(c.rect(x, 1, x, 4), 'dkmetal', mode='flat', iline=True)
    for (x, y) in ((4, 8), (7, 8), (10, 8), (4, 11), (7, 11)):
        c.dot(x, y, 'ink', 1)
    q = c.put(c.ellipse(10.5, 11.0, 2.0, 1.7) & ~c.ellipse(10.5, 11.0, 1.0, 0.8), 'red', mode='flat', outline=False)
    keep(c, q)
    return render(c)


def ic_core():
    """El núcleo de lámpara: bombilla de vidrio con filamento enroscado (no un cristal)."""
    c = cv(16, 16)
    g = c.put(c.ellipse(7.5, 6.5, 5.0, 5.4), 'glass', mode='shine', cast=1)
    c.set_nrm(g, c.sphere_n(6.0, 5.0, 6.0, 6.0, k=0.7))
    q = c.put(c.line([(5.5, 9), (5.5, 6), (6.5, 5), (7.5, 6), (8.5, 5), (9.5, 6), (9.5, 9)]), 'glow2', mode='flat', outline=False)
    keep(c, q)
    c.put(c.rect(5, 11, 10, 14), 'brass', mode='cyl', cast=1, iline=True)
    c.paint(c.rect(5, 12, 10, 12), 'brass2', 1)
    c.dot(5.0, 4.0, 'white', 4)
    return render(c)


def ic_radio():
    """La radio de la tienda (el Drift Signal)."""
    c = cv(16, 16)
    c.put(c.line([(9, 5), (13, 0)]), 'steel', mode='flat', iline=False)
    p = c.put(c.rect(1, 5, 14, 14), 'teal', mode='top', cast=1, iline=True)
    c.paint(c.rect(2, 7, 7, 12), 'cream', 2, within=[p])
    for y in (8, 10):
        c.paint(c.rect(3, y, 6, y), 'teal2', 1, within=[p])
    c.put(c.ellipse(10.5, 9.5, 2.2, 2.2), 'brass', mode='shine', iline=True)
    c.dot(10, 9, 'white', 4)
    return render(c)


ICONS2 = {'rank': ic_rank, 'fittings': ic_fittings, 'event': ic_event, 'dues': ic_dues, 'calendar': ic_calendar,
          'core': ic_core, 'radio': ic_radio}


# --- pictogramas de los días especiales (32x32)
def ev_sandstorm():
    c = cv(32, 32)
    c.put(c.ellipse(16, 30, 18, 7) & c.rect(0, 23, 31, 31), 'dune', mode='top', cast=1, iline=True)
    for (pts, mat) in (([(3, 8), (12, 6), (20, 9), (24, 7), (27, 4)], 'sand'), ([(2, 14), (10, 12), (18, 15), (26, 12), (30, 14)], 'sand'),
                       ([(5, 19), (14, 18), (21, 20), (28, 19)], 'dune')):
        q = c.put(c.stroke([(x, y) for x, y in pts], 0.7), mat, mode='flat', outline=False)
        keep(c, q)
    for (x, y) in ((8, 3), (22, 17), (13, 22), (27, 9), (4, 21)):
        c.dot(x, y, 'sand', 3, p=1)
    return render(c)


def ev_inspection():
    """La marca de conteo de la Tally Office en un sello redondo (nunca un engranaje)."""
    c = cv(32, 32)
    c.put(c.ellipse(16, 16, 13.5, 13.5), 'mustard', mode='soft', cast=1, iline=True)
    c.put(c.ellipse(16, 16, 10.5, 10.5), 'cream', mode='flat')
    q = c.put(c.stroke([(10, 10), (10, 22)], 0.9) | c.stroke([(14, 10), (14, 22)], 0.9) | c.stroke([(18, 10), (18, 22)], 0.9)
              | c.stroke([(22, 10), (22, 22)], 0.9) | c.stroke([(7, 21), (25, 11)], 0.9), 'ink', mode='flat', outline=False)
    keep(c, q)
    return render(c)


def ev_bigfall():
    c = cv(32, 32)
    trail = c.stroke([(3, 3), (10, 9), (16, 15)], 1.0, 3.2)
    c.put(trail, 'glow2', mode='flat')
    c.paint(c.stroke([(5, 5), (12, 11)], 0.6, 1.4), 'glow', 3)
    # el pedazo de anillo (una celosía, nunca un casco en cuña)
    ring = c.ellipse(21, 21, 8, 8) & ~c.ellipse(21, 21, 5.5, 5.5) & (c.ys > 14) & (c.xs > 13)
    p = c.put(ring, 'dkmetal', mode='cyl', cast=1, iline=True)
    for k in range(4):
        ang = math.radians(180 + k * 25)
    c.paint(c.line([(14, 21), (20, 27)]) | c.line([(16, 16), (23, 28)]) | c.line([(20, 15), (27, 26)]), 'steel', 3, within=[p])
    for (x, y, r) in ((26, 9, 3), (29, 13, 2)):
        c.put(c.ellipse(x, y, r, r), 'smoke', mode='soft')
    return render(c)


def ev_festival():
    """Las dos lunas llenas (Copper grande, Tin chica) con el halo de bronce y una guirnalda de faroles."""
    c = cv(32, 32)
    c.put(c.ellipse(16, 12, 15, 10) & ~c.ellipse(16, 12, 13.2, 8.4), 'bronze', mode='flat')
    m1 = c.put(c.ellipse(11, 11, 6.5, 6.5), 'moon_cu', mode='shine', cast=1)
    c.set_nrm(m1, c.sphere_n(9.5, 9.5, 7, 7, k=0.8))
    c.paint(c.ellipse(8.5, 13, 1.6, 1.0) | c.ellipse(13.5, 9, 1.0, 0.8), 'teal', 2, within=[m1])
    m2 = c.put(c.ellipse(23.5, 9, 3.4, 3.4), 'moon_tin', mode='shine', cast=1)
    c.set_nrm(m2, c.sphere_n(22.5, 8, 3.6, 3.6, k=0.8))
    q = c.put(c.line([(1, 21), (8, 25), (16, 26), (24, 25), (31, 21)]), 'dkmetal', mode='flat', outline=False)
    keep(c, q)
    for x, y in ((6, 24), (12, 26), (19, 26), (26, 24)):
        c.put(c.rect(x - 1, y + 1, x + 1, y + 4), 'glow', mode='flat', iline=True)
    return render(c)


def ev_race():
    """Una moto flotante de un asiento: propulsor gordo atrás, nariz corta, rayas de velocidad y un banderín."""
    c = cv(32, 32)
    for y in (12, 17, 22):
        q = c.put(c.line([(0, y), (6, y)]), 'sand', mode='flat', outline=False)
        keep(c, q)
    c.put(c.ellipse(11, 17, 5.0, 4.4), 'dkmetal', mode='cyl', cast=1, iline=True)          # propulsor
    c.put(c.ellipse(9.5, 17, 2.2, 2.0), 'glow2', mode='flat')                               # tobera
    body = c.poly([(11, 13), (24, 14.5), (28, 17), (24, 19.5), (11, 21)])
    p = c.put(body, 'red', mode='cyl', cast=1, iline=True)
    c.paint(c.poly([(18, 15), (24, 15.5), (26, 17), (18, 17)]), 'cream', 3, within=[p])
    c.put(c.rect(14, 11, 19, 13), 'wood', mode='top', cast=1, iline=True)                  # asiento
    q = c.put(c.line([(13, 25), (27, 25)]), 'dune', mode='flat', outline=False)            # sombra (flota)
    keep(c, q)
    c.put(c.rect(26, 2, 26, 11), 'steel', mode='flat', iline=True)
    flag = c.rect(27, 2, 31, 7)
    c.put(flag, 'white', mode='flat', iline=True)
    c.paint(flag & (((c.xs + c.ys) % 2) == 0), 'ink', 1)
    return render(c)


def ev_finale():
    """La Great Starfall: estrellas fugaces sobre la estrellita remendada."""
    c = cv(32, 32)
    for (a, b) in (((2, 2), (11, 9)), ((14, 1), (21, 6)), ((22, 10), (30, 15))):
        tr = c.stroke([a, b], 0.4, 1.4)
        c.put(tr, 'glow', mode='flat')
        c.dot(b[0], b[1], 'white', 4)
    s = c.put(c.poly(star_poly(13, 21, 9.5, 4.0)), 'star', mode='shine', cast=1)
    c.set_nrm(s, c.sphere_n(11, 19, 9, 9, k=0.7))
    c.paint(c.rect(13, 21, 16, 24), 'copper', 2, within=[s])
    return render(c)


EVENTS2 = {'sandstorm': ev_sandstorm, 'inspection': ev_inspection, 'bigfall': ev_bigfall, 'festival': ev_festival,
           'race': ev_race, 'finale': ev_finale}


# --- Rosa Reverb (32x32): pelo rizado negro, auriculares grandes, sonrisa, micrófono antiguo; sin mono de trabajo
def rosa():
    c = cv(32, 32)
    # hombros: chaqueta de punto mostaza con cuello crema
    sh = c.put(c.ellipse(15, 33, 13, 8), 'mustard', mode='soft', cast=1, iline=True)
    c.paint(c.poly([(11, 26), (15, 31), (19, 26)]), 'cream', 2, within=[sh])
    c.put(c.rect(13, 22, 17, 27), 'skin', mode='cyl', cast=1)
    # pelo: una masa rizada grande detrás de la cabeza
    hair = c.ellipse(15, 12, 11, 10.5)
    for (x, y, r) in ((5, 8, 3.2), (8, 3.5, 3.2), (14, 1.5, 3.4), (20, 2.5, 3.2), (25, 7, 3.2), (27, 13, 3.0),
                      (4, 14, 3.0), (5, 19, 2.8), (26, 19, 2.6)):
        hair |= c.ellipse(x, y, r, r)
    hp = c.put(hair, 'hair', mode='soft', iline=True)
    for (x, y) in ((7, 6), (11, 3), (17, 2), (22, 5), (25, 11), (6, 12), (24, 16), (6, 17)):
        c.dot(x, y, 'dkmetal', 2)
    # cara
    f = c.put(c.ellipse(15.5, 15, 6.5, 7.4), 'skin', mode='soft', cast=1)
    c.set_nrm(f, c.sphere_n(14, 13, 7, 8, k=0.75))
    c.put(c.ellipse(15.5, 7.6, 6.0, 2.2) & c.rect(9, 6, 22, 9), 'hair', mode='soft')   # flequillo rizado
    # ojos (alegres, entrecerrados) y cejas
    for x in (12.5, 18.5):
        c.dot(x - 0.5, 14, 'ink', 1)
        c.dot(x + 0.5, 14, 'ink', 1)
        c.dot(x, 13, 'ink', 1)
    for x in (12, 19):
        c.dot(x, 11, 'hair', 1)
        c.dot(x + 1, 11, 'hair', 1)
    # la sonrisa grande
    grin = c.ellipse(15.5, 18.6, 3.6, 2.2) & (c.ys >= 18)
    c.paint(grin, 'white', 3, within=[f])
    c.paint(c.rect(12, 18, 19, 18) & grin, 'lip', 1, within=[f])
    c.dot(15.5, 21, 'lip', 2)
    c.dot(11, 17, 'red', 3)
    c.dot(20, 17, 'red', 3)
    # auriculares: diadema teal sobre el pelo y dos copas crema con borde de cobre
    band = c.stroke(bez((6, 13), (15, -4), (25, 13), 12), 0.9)
    c.put(band & ~c.ellipse(15.5, 15, 6.5, 7.4), 'teal', mode='cyl', iline=True)
    for x in (7.0, 24.0):
        c.put(c.ellipse(x, 15, 3.0, 4.0), 'copper', mode='shine', cast=1, iline=True)
        c.put(c.ellipse(x, 15, 1.8, 2.8), 'cream', mode='soft')
    # micrófono antiguo (cabeza ovalada de rejilla y un pie) abajo a la derecha
    mic = c.put(c.ellipse(26.5, 25.5, 3.6, 4.6), 'chrome', mode='shine', cast=1, iline=True)
    for y in (23, 25, 27):
        c.paint(c.rect(24, y, 29, y) & c.ellipse(26.5, 25.5, 3.6, 4.6), 'dkmetal', 1, within=[mic])
    c.put(c.rect(25, 30, 28, 31), 'dkmetal', mode='flat', iline=True)
    c.dot(25, 23, 'white', 4)
    return render(c)


# --- la escarapela (48x48 -> 96x96)
def award_ribbon():
    c = cv(48, 48)
    for (a, b, mat) in (((18, 30), (13, 46), 'teal'), ((30, 30), (35, 46), 'teal')):
        tail = c.capsule(a, b, 4.2)
        p = c.put(tail, mat, mode='cyl', cast=1, iline=True)
    c.erase(c.poly([(10, 47), (13, 42), (16, 47)]) | c.poly([(32, 47), (35, 42), (38, 47)]))
    rim = c.ellipse(24, 20, 18, 18)
    pts = []
    for k in range(36):
        ang = math.radians(k * 10)
        r = 18 if k % 2 == 0 else 15.5
        pts.append((24 + math.cos(ang) * r, 20 + math.sin(ang) * r))
    p = c.put(c.poly(pts), 'parch', mode='soft', cast=1, iline=True)
    for k in range(18):
        ang = math.radians(k * 20 + 5)
        c.paint(c.line([(24 + math.cos(ang) * 11, 20 + math.sin(ang) * 11), (24 + math.cos(ang) * 17, 20 + math.sin(ang) * 17)]),
                'teal', 2, within=[p])
    m = c.put(c.ellipse(24, 20, 10.5, 10.5), 'bronze', mode='shine', cast=1, iline=True)
    c.set_nrm(m, c.sphere_n(21, 17, 11, 11, k=0.8))
    s = c.put(c.poly(star_poly(24, 20.5, 7.5, 3.1)), 'star', mode='shine', cast=1, iline=True)
    c.dot(20, 15, 'white', 4)
    return Image.fromarray(render(c), 'RGBA').resize((96, 96), Image.NEAREST)


# --- la tarjeta del cometa (128x64 -> 256x128)
def comet_card():
    w, h = 128, 64
    c = cv(w, h)
    card = c.put(c.rect(1, 1, w - 2, h - 2), 'parch', mode='flat', iline=True)
    c.paint(c.rect(1, 1, w - 2, 3) | c.rect(1, h - 4, w - 2, h - 2) | c.rect(1, 1, 3, h - 2) | c.rect(w - 4, 1, w - 2, h - 2),
            'brass', 2, within=[card])
    for (x, y) in ((6, 6), (w - 7, 6), (6, h - 7), (w - 7, h - 7)):
        c.dot(x, y, 'brass2', 1)
    # la cola de latón: tres trazos que se afinan hacia la izquierda
    for (y0, y1, r0, r1, mat) in ((40, 30, 0.6, 4.6, 'brass'), (46, 33, 0.5, 3.4, 'brass2'), (33, 27, 0.4, 2.6, 'brass')):
        tail = c.stroke([(14, y0), (40, (y0 + y1) / 2 + 2), (70, y1 + 2), (88, y1)], r0, r1)
        c.put(tail, mat, mode='cyl', cast=1, iline=True)
    s = c.put(c.poly(star_poly(98, 30, 17, 7)), 'star', mode='shine', cast=1, iline=True)
    c.set_nrm(s, c.sphere_n(94, 26, 16, 16, k=0.7))
    c.paint(c.rect(98, 30, 104, 36), 'copper', 2, within=[s])
    for (x, y) in ((99, 29), (105, 32), (101, 37), (97, 34)):
        c.dot(x, y, 'brass2', 1)
    for (x, y) in ((24, 18), (52, 14), (70, 50), (114, 12), (40, 52)):
        c.dot(x, y, 'glow', 4, p=card)
        c.dot(x + 1, y, 'glow', 3, p=card)
        c.dot(x - 1, y, 'glow', 3, p=card)
        c.dot(x, y + 1, 'glow', 3, p=card)
        c.dot(x, y - 1, 'glow', 3, p=card)
    return Image.fromarray(render(c), 'RGBA').resize((w * 2, h * 2), Image.NEAREST)


# ================================================================== todo
def build(out):
    os.makedirs(out, exist_ok=True)
    files = {}
    def save(name, im):
        if isinstance(im, np.ndarray):
            im = Image.fromarray(im, 'RGBA')
        im.save(os.path.join(out, name))
        files[name] = im
    save('board9.png', board9())
    save('flap_cell.png', flap_cell())
    save('lanterns.png', lanterns())
    save('crests.png', crests())
    with open(os.path.join(out, 'crests.json'), 'w') as f:
        json.dump({'cell': [24, 24], 'order': [s for s, _ in SHOPS],
                   'note': 'crests.png: 30 escudos de 24x24 en el orden de Ranking.SHOPS (Ranking.crest_index)'}, f, indent=1)
    save('chart.png', chart())
    save('tape9.png', tape9())
    save('tape_header.png', tape_header())
    save('rosa.png', rosa())
    save('stamp_late.png', stamp('LATE', '#c23a2e', 1))
    save('stamp_paid.png', stamp('PAID', '#3f8a4a', 2))
    save('stamp_graded.png', stamp('GRADED', '#b07a22', 3, size=22))
    save('comet_card.png', comet_card())
    save('award_ribbon.png', award_ribbon())
    for k, fn in ICONS2.items():
        save('icon_%s.png' % k, fn())
    for k, fn in EVENTS2.items():
        save('event_%s.png' % k, fn())
    return files


def sheet(files, path):
    order = list(files.keys())
    rows = []
    for name in order:
        im = files[name]
        s = 4 if im.width <= 32 else (2 if im.width <= 128 else 1)
        rows.append((name, im.resize((im.width * s, im.height * s), Image.NEAREST)))
    W = 1500
    x = y = 10
    line_h = 0
    pos = []
    for name, im in rows:
        if x + im.width > W - 10:
            x = 10
            y += line_h + 24
            line_h = 0
        pos.append((name, im, x, y))
        x += im.width + 18
        line_h = max(line_h, im.height)
    H = y + line_h + 30
    out = Image.new('RGBA', (W, H), (52, 44, 60, 255))
    d = ImageDraw.Draw(out)
    for name, im, x, y in pos:
        out.alpha_composite(im, (x, y + 16))
        d.text((x, y), name, fill=(240, 230, 210, 255))
    out.save(path)


if __name__ == '__main__':
    args = sys.argv[1:]
    out = os.path.join(HERE, '..', '..', 'assets', 'ui')
    if '--out' in args:
        out = args[args.index('--out') + 1]
    files = build(out)
    if '--sheet' in args:
        sheet(files, args[args.index('--sheet') + 1])
    print('ok rank art ->', os.path.abspath(out), len(files), 'files')
