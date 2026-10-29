"""Secondhand Stars · props del taller (interior cálido y abarrotado) y de la calle (puerto del desierto).

Mismo lienzo Cv + render HD-2D del kit de personajes. Cada prop mira a la cámara (3/4 de frente, luz arriba a la
izquierda). props.json: para cada prop, px = tamaño sugerido de un píxel de textura en el mundo (los personajes usan
0.0222) y anchor ('bottom' apoyado en el suelo, 'top' colgado del techo, 'center' en la pared o el cielo); 'frames'
si es una tira animada (cuadros iguales en fila).

Uso: python3 ss_props.py [--out DIR] [nombres...]
"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from c64core import *
from c64core import _norm
from ss_bots import pal_of
from ss_items import concave_n, hcyl_n, crack, soot

MATS = {
    'wood': '#946a44', 'wood2': '#6e4a30', 'wood3': '#b48a5a', 'plank': '#a87e52',
    'steel': ('#a8acb6', 'metal'), 'dkmetal': ('#5a5660', 'metal'), 'iron': ('#3e3a42', 'metal'), 'brass': ('#d4a64a', 'metal'),
    'copper': ('#d27c42', 'metal'), 'teal': '#3e8a86', 'teal2': '#2e6664', 'tealp': '#5e9a92', 'rust': '#a45a36',
    'rust2': '#7a3e26', 'amber': '#e8a038', 'cream': ('#ece2c4', 'white'), 'paper': ('#e8dcc0', 'white'),
    'red': '#b4452e', 'glow': ('#ffe2a0', 'flat'), 'glow2': ('#ffc860', 'flat'), 'lampshade': '#3e8a86',
    'cable_k': ('#2e2a2e', 'leather'), 'cable_r': '#a8402e', 'cable_y': '#d8a040', 'rubber': ('#33302e', 'leather'),
    'glass': ('#8ac8d8', 'gem'), 'sky': ('#f0c890', 'flat'), 'sky2': ('#f6dcaa', 'flat'), 'dune': ('#d8a868', 'flat'),
    'dune2': ('#c08a50', 'flat'), 'far': ('#b8946a', 'flat'), 'hole': ('#1a1618', 'flat'), 'shadow': ('#2a2224', 'flat'),
    'tea': ('#8a4e2a', 'cloth'), 'smoke': ('#f0ece4', 'flat'), 'label': ('#d8cca8', 'white'), 'sand': '#d6aa72',
    'adobe': '#d6b488', 'adobe2': '#b89468', 'scrap': ('#8a9294', 'metal'), 'canvas': '#c8b890', 'stripe': '#b4452e',
    'bulb': ('#fff0b8', 'flat'), 'bulb_off': ('#6a5a4a', 'metal'), 'star': ('#d8a440', 'metal'), 'star_off': ('#8a7a5e', 'metal'),
    'plast': '#d8703a', 'hull': ('#b8b4a8', 'metal'), 'hull2': ('#8a8c88', 'metal'), 'hullr': '#b4452e', 'hullt': '#3e8a86',
    'engine': ('#ffb04a', 'flat'), 'engine2': ('#fff0c0', 'flat'), 'window': ('#7ab8c8', 'gem'),
    'soot': ('#2a2222', 'flat'), 'burnt': ('#5a3424', 'cloth'), 'crackl': ('#f0e6d0', 'flat'),
    'night': ('#1e1a3a', 'flat'), 'night2': ('#3a2e58', 'flat'), 'starw': ('#fff8e4', 'flat'), 'ringn': ('#8a7a9a', 'flat'),
    'nightdome': ('#2a2438', 'flat'), 'nightdune': ('#3a3044', 'flat'),
}


def cv_new(w, h, accents=('teal', 'amber', 'red', 'glow', 'glow2', 'hullr', 'hullt', 'star')):
    pal, kinds = pal_of(MATS, accents=accents)
    return Cv(pal, w=w, h=h, kinds=kinds)


def keep(cv, p):
    cv.parts[p].keep = True
    return p


def box(cv, x0, y0, x1, y1, front, top=None, side=None, depth=(3, -3), iline=True, cast=1):
    """Caja en vista 3/4: frente, tapa (corrida en depth) y costado derecho. Devuelve las partes."""
    dx, dy = depth
    f = cv.rect(x0, y0, x1, y1)
    t = cv.poly([(x0, y0), (x1, y0), (x1 + dx, y0 + dy), (x0 + dx, y0 + dy)]) & ~f
    s_ = cv.poly([(x1, y0), (x1 + dx, y0 + dy), (x1 + dx, y1 + dy), (x1, y1)]) & ~f
    ps = cv.put(s_, side or front, mode='flat', iline=iline)
    cv.parts[ps].bias = -0.9
    pt = cv.put(t, top or front, mode='flat', iline=iline)
    cv.parts[pt].bias = 0.8
    pf = cv.put(f, front, mode='cyl', cast=cast, iline=iline)
    return pf, pt, ps


# ================================================================== taller

def workbench():
    """El banco de reparación: tablero grueso de madera con borde de chapa, patas de hierro, cajonera, morsa, lámpara
    de brazo con luz cálida, tablero de herramientas atrás y un trasto a medio abrir encima."""
    cv = cv_new(88, 64)
    # tablero perforado atrás (pegboard) con herramientas colgadas
    pb = cv.rect(8, 6, 70, 30)
    p = cv.put(pb, 'wood3', mode='flat', iline=True)
    cv.parts[p].bias = -0.4
    for y in range(9, 29, 4):
        for x in range(11, 69, 4):
            cv.dot(x, y, 'wood2', 1)
    for (x, y, L, m) in ((16, 10, 12, 'steel'), (22, 10, 10, 'red'), (28, 11, 9, 'dkmetal'), (36, 10, 13, 'steel')):
        cv.put(cv.rect(x, y, x + 1, y + L), m, mode='shine', iline=True)
    cv.put(cv.ellipse(48, 15, 4.5, 4.5) & ~cv.ellipse(48, 15, 2.5, 2.5), 'cable_y', mode='shine', iline=True)
    cv.put(cv.rect(58, 11, 64, 16), 'amber', mode='cyl', iline=True)
    # patas y travesaño
    for x in (10, 74):
        cv.put(cv.rect(x, 40, x + 3, 62), 'iron', mode='cyl', iline=True)
    cv.put(cv.rect(10, 55, 76, 57), 'iron', mode='cyl', iline=True)
    # cajonera bajo el tablero a la derecha
    pf, pt, ps = box(cv, 50, 40, 72, 60, 'teal', depth=(3, -2))
    for y in (46, 53):
        cv.shade(cv.line([(51, y), (71, y)]), -1, within=[pf])
        cv.put(cv.rect(59, y + 2, 63, y + 2), 'brass', mode='shine')
    cv.put(cv.rect(59, 42, 63, 42), 'brass', mode='shine')
    # tablero (tapa gruesa, borde de chapa)
    pf, pt, ps = box(cv, 4, 32, 80, 39, 'wood', top='plank', side='wood2', depth=(4, -4))
    cv.paint(cv.rect(4, 38, 80, 39), 'dkmetal', 2)
    # morsa a la izquierda
    cv.put(cv.rect(8, 22, 18, 30), 'teal2', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(6, 26, 20, 28), 'dkmetal', mode='shine', iline=True)
    cv.put(cv.line([(13, 31), (13, 35)]), 'steel', mode='flat')
    # trasto a medio arreglar: la radio abierta
    pf, pt, ps = box(cv, 28, 22, 44, 30, 'tealp', depth=(2, -2))
    cv.put(cv.ellipse(32, 26, 2.4, 2.4), 'hole', mode='flat')
    cv.put(cv.rect(37, 24, 42, 27), 'amber', mode='flat')
    # tornillos sueltos y una taza
    for (x, y) in ((50, 30), (53, 31), (55, 29)):
        cv.dot(x, y, 'steel', 3)
    cv.put(cv.rect(64, 26, 68, 31), 'cream', mode='cyl', iline=True)
    cv.put(cv.ellipse(66, 26, 2.2, 0.8), 'tea', mode='flat')
    # lámpara de brazo: base, dos tramos y pantalla con luz
    cv.put(cv.ellipse(78, 30, 3.0, 1.2), 'dkmetal', mode='shine', iline=True)
    cv.put(cv.stroke([(78, 29), (82, 14), (70, 8)], 0.8), 'dkmetal', mode='shine', iline=True)
    sh = cv.poly([(64, 7), (72, 5), (74, 11), (66, 13)])
    cv.put(sh, 'lampshade', mode='top', cast=1, iline=True)
    gl = cv.poly([(66, 13), (74, 11), (72, 14), (67, 15)])
    keep(cv, cv.put(gl, 'glow', mode='flat', outline=False))
    return render(cv)


def junk_shelf():
    """Estantería de chatarra: parantes de metal, cuatro estantes con radios viejas, engranajes, latas, cables,
    una cabeza de robot y frascos de tornillos."""
    cv = cv_new(64, 84)
    for x in (3, 58):
        cv.put(cv.rect(x, 2, x + 2, 83), 'dkmetal', mode='shine', iline=True)
    ys = [20, 40, 60, 80]
    for y in ys:
        box(cv, 3, y, 60, y + 2, 'wood', top='plank', side='wood2', depth=(2, -2))
    # estante 1: radio vieja, latas
    box(cv, 8, 9, 24, 19, 'tealp', depth=(2, -2))
    cv.put(cv.ellipse(12.5, 14, 2.6, 2.6), 'hole', mode='flat')
    cv.put(cv.rect(17, 12, 22, 15), 'amber', mode='flat')
    for (x, m) in ((30, 'red'), (36, 'cream'), (42, 'red')):
        cv.put(cv.rect(x, 12, x + 4, 19), m, mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(52, 14, 4.6, 4.6) & ~cv.ellipse(52, 14, 1.6, 1.6), 'brass', mode='shine', cast=1, iline=True)
    # estante 2: cabeza de robot vieja (redonda con un ojo apagado), engranaje y frascos de tornillos
    hd = cv.ellipse(16, 33, 7.0, 6.4)
    cv.put(hd, 'scrap', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(18, 33, 2.4, 2.4), 'hole', mode='flat')
    cv.dot(17, 32, 'steel', 3)
    gm = cv.ellipse(34, 33, 5.0, 5.0)
    for k in range(8):
        a = k * math.pi / 4
        gm |= cv.ellipse(34 + math.cos(a) * 5.4, 33 + math.sin(a) * 5.4, 1.2, 1.2)
    gm &= ~cv.ellipse(34, 33, 1.6, 1.6)
    cv.put(gm, 'copper', mode='shine', cast=1, iline=True)
    for x in (44, 51):
        cv.put(cv.rect(x, 31, x + 5, 39), 'glass', mode='shine', cast=1, iline=True)
        cv.paint(cv.rect(x + 1, 35, x + 4, 38), 'steel', 2)
        cv.put(cv.rect(x, 30, x + 5, 31), 'red', mode='flat', iline=True)
    # estante 3: rollo de cable, caja de cartón con etiqueta, propulsor viejo
    ring = cv.ellipse(14, 53, 6.6, 5.0) & ~cv.ellipse(14, 53, 3.0, 2.0)
    cv.put(ring, 'cable_r', mode='stroke', nrm=cv.sphere_n(13, 52, 7.5, 6.0), cast=1, iline=True)
    box(cv, 24, 49, 38, 59, 'canvas', depth=(2, -2))
    cv.put(cv.rect(27, 52, 34, 55), 'paper', mode='flat')
    cv.put(cv.rect(42, 50, 56, 58), 'red', mode='stroke', nrm=hcyl_n(cv, 54, 4.5), cast=1, iline=True)
    cv.put(cv.ellipse(56, 54, 1.6, 4.4), 'dkmetal', mode='shine', iline=True)
    # estante 4: cajón de piezas y una pava vieja abollada
    box(cv, 8, 70, 30, 79, 'wood2', depth=(2, -2))
    for x in range(11, 29, 4):
        cv.dot(x, 69, 'steel', 3)
    cv.put(cv.ellipse(44, 74, 7.0, 5.0) & (cv.ys <= 79), 'copper', mode='shine', cast=1, iline=True)
    cv.put(cv.stroke([(50, 74), (54, 70)], 1.2), 'copper', mode='shine', iline=True)
    # cables que cuelgan del estante de arriba
    keep(cv, cv.put(cv.stroke(bez((40, 21), (44, 30), (49, 25), 8), 0.5), 'cable_k', mode='flat'))
    return render(cv)


def parts_cabinet():
    """Mueble de cajoncitos de repuestos (4 x 5) con etiquetas de papel y tiradores de bronce; uno entreabierto."""
    cv = cv_new(46, 60)
    pf, pt, ps = box(cv, 4, 6, 40, 58, 'teal', side='teal2', depth=(4, -4))
    for r in range(5):
        for c in range(4):
            x, y = 6 + c * 8.5, 8 + r * 10
            d = cv.rect(int(x), int(y), int(x + 7), int(y + 8))
            cv.shade(cv.rect(int(x), int(y + 8), int(x + 7), int(y + 8)), -2, within=[pf])
            cv.shade(cv.rect(int(x + 7), int(y), int(x + 7), int(y + 8)), -1, within=[pf])
            cv.paint(cv.rect(int(x + 1), int(y + 1), int(x + 5), int(y + 3)), 'paper', 2)
            cv.dot(x + 3, y + 6, 'brass', 3)
    # un cajón entreabierto con tornillos
    dm = cv.rect(14, 37, 23, 41)
    cv.put(dm, 'teal', mode='top', cast=1, iline=True)
    cv.put(cv.rect(15, 35, 22, 37), 'hole', mode='flat')
    for x in (16, 18, 20):
        cv.dot(x, 36, 'steel', 3)
    return render(cv)


def crate(stack=False):
    """Cajón de carga de madera con flejes de metal y un número estarcido."""
    cv = cv_new(40 if stack else 26, 44 if stack else 22)

    def one(x0, y0):
        pf, pt, ps = box(cv, x0, y0, x0 + 20, y0 + 14, 'wood3', top='plank', side='wood2', depth=(3, -3))
        for x in (x0 + 4, x0 + 16):
            cv.paint(cv.rect(x, y0, x + 1, y0 + 14), 'dkmetal', 2)
        cv.shade(cv.line([(x0, y0 + 7), (x0 + 20, y0 + 7)]), -1, within=[pf])
        cv.paint(cv.rect(x0 + 8, y0 + 3, x0 + 12, y0 + 5), 'red', 2)
    if stack:
        one(3, 26)
        one(14, 26) if False else None
        one(8, 9)
    else:
        one(2, 5)
    return render(cv)


def hanging_lamp():
    """Lámpara colgante industrial: cable, pantalla cónica verde agua y la bombita con un cono de luz cálida."""
    cv = cv_new(24, 44)
    keep(cv, cv.put(cv.rect(11, 0, 11, 24), 'cable_k', mode='flat'))
    sh = cv.poly([(8, 24), (15, 24), (21, 33), (2, 33)])
    cv.put(sh, 'lampshade', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(9, 22, 14, 24), 'brass', mode='shine', iline=True)
    keep(cv, cv.put(cv.ellipse(11.5, 34, 3.0, 2.2), 'bulb', mode='flat', outline=False))
    # cono de luz (dos tonos, sin contorno)
    cone = cv.poly([(4, 35), (19, 35), (23, 43), (0, 43)]) & ~cv.ellipse(11.5, 34, 3.0, 2.2)
    q = cv.put(cone, 'glow2', mode='flat', outline=False)
    keep(cv, q)
    cv.paint(cv.poly([(7, 35), (16, 35), (18, 40), (5, 40)]) & cone, 'glow', 2)
    return render(cv)


def cables():
    """Cables que cuelgan en guirnalda de pared a pared (tira de 128 px: se puede repetir)."""
    cv = cv_new(128, 24)
    for (m, y0, sag, ph) in (('cable_k', 2, 12, 0.0), ('cable_r', 4, 16, 0.3), ('cable_y', 3, 9, 0.6), ('cable_k', 6, 18, 0.1)):
        pts = [(x, y0 + sag * math.sin(math.pi * ((x / 64.0 + ph) % 1.0))) for x in range(-2, 131, 4)]
        keep(cv, cv.put(cv.stroke(pts, 0.7), m, mode='shine', iline=True))
    for x in (0, 64):
        cv.put(cv.rect(x, 0, x + 3, 4), 'dkmetal', mode='shine', iline=True)
    return render(cv)


def ceiling_fan(frame=0):
    """Ventilador de techo: eje, motor y cuatro aspas de madera vistas desde abajo en perspectiva; 4 cuadros."""
    cv = cv_new(64, 22)
    cv.put(cv.rect(31, 0, 32, 6), 'dkmetal', mode='shine', iline=True)
    cv.put(cv.ellipse(31.5, 9, 6.0, 3.6), 'brass', mode='shine', cast=1, iline=True)
    a0 = frame * (math.pi / 2) / 4
    for k in range(4):
        a = a0 + k * math.pi / 2
        ex, ey = 31.5 + math.cos(a) * 29.0, 10.0 + math.sin(a) * 6.5
        mx, my = 31.5 + math.cos(a) * 6.0, 10.0 + math.sin(a) * 1.5
        w = 2.2 + 1.2 * abs(math.sin(a))
        m = cv.stroke([(mx, my), (ex, ey)], 1.2, w)
        p = cv.put(m, 'wood', mode='top', cast=1, iline=True)
        if math.sin(a) > 0.2:
            cv.parts[p].bias = 0.4
        else:
            cv.parts[p].bias = -0.3
    cv.put(cv.ellipse(31.5, 12.0, 2.6, 1.6), 'dkmetal', mode='shine', iline=True)
    return render(cv)


def tea_station():
    """El rincón del té de Kettle: mesita de chapa con un samovar de cobre (canilla, tapa, llama chica abajo), tazas,
    una lata de té y un banquito para que Kettle se suba."""
    cv = cv_new(48, 50)
    # banquito
    box(cv, 2, 40, 12, 44, 'wood3', depth=(2, -2))
    for x in (3, 10):
        cv.put(cv.rect(x, 45, x + 1, 49), 'wood2', mode='cyl', iline=True)
    # mesa
    for x in (16, 42):
        cv.put(cv.rect(x, 34, x + 2, 49), 'dkmetal', mode='shine', iline=True)
    box(cv, 14, 30, 45, 34, 'tealp', side='teal2', depth=(2, -2))
    # samovar: cuerpo de cobre, canilla, tapa con perilla, chimenea
    body = cv.ellipse(25, 20, 7.0, 9.0) & (cv.ys <= 28)
    p = cv.put(body, 'copper', mode='shine', cast=1, iline=True)
    cv.set_nrm(p, cv.sphere_n(23, 17, 8.0, 10.0, k=0.9))
    cv.put(cv.rect(20, 27, 30, 29), 'brass', mode='shine', iline=True)
    cv.put(cv.rect(31, 21, 34, 22), 'brass', mode='shine', iline=True)
    cv.put(cv.rect(33, 22, 34, 24), 'brass', mode='shine', iline=True)
    cv.put(cv.ellipse(25, 11, 4.4, 1.6), 'brass', mode='shine', iline=True)
    cv.put(cv.rect(24, 6, 26, 10), 'dkmetal', mode='shine', iline=True)
    for (x, y, r) in ((26, 3, 1.6), (28, 0.5, 1.2)):
        keep(cv, cv.put(cv.ellipse(x, y, r, r * 0.9), 'smoke', mode='flat', outline=False))
    # tazas y lata de té
    for x in (36, 40):
        cv.put(cv.rect(x, 26, x + 3, 29), 'cream', mode='cyl', iline=True)
        cv.dot(x + 1, 26, 'tea', 2)
    cv.put(cv.rect(15, 23, 19, 29), 'red', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(15, 22, 19, 23), 'brass', mode='shine', iline=True)
    return render(cv)


def shop_door():
    """Puerta del taller: escotilla de chapa verde agua desteñida con ventanita redonda (luz de la calle), marco de
    adobe y un cartel de OPEN/CLOSED colgado (se cambia con el cuadro: 0 cerrado, 1 abierto)."""
    out = []
    for opened in (False, True):
        cv = cv_new(44, 72)
        fr = cv.rect(0, 0, 43, 71) & ~cv.rect(6, 6, 37, 71)
        cv.put(fr, 'adobe', mode='flat', iline=True)
        cv.parts[-1].bias = -0.2
        d = cv.rect(6, 6, 37, 71)
        p = cv.put(d, 'tealp', mode='cyl', cast=1, iline=True)
        for y in (24, 50):
            cv.shade(cv.line([(7, y), (36, y)]), -1, within=[p])
            for x in (9, 34):
                cv.dot(x, y + 2, 'steel', 3)
        cv.put(cv.ellipse(21.5, 17, 6.0, 6.0) & ~cv.ellipse(21.5, 17, 4.4, 4.4), 'brass', mode='shine', iline=True)
        cv.put(cv.ellipse(21.5, 17, 4.4, 4.4), 'sky2', mode='flat')
        cv.dot(20, 15, 'white', 4)
        cv.put(cv.rect(31, 38, 34, 42), 'brass', mode='shine', cast=1, iline=True)
        # cartel colgado
        keep(cv, cv.put(cv.line([(17, 26), (21, 22), (26, 26)]), 'cable_k', mode='flat'))
        sign = cv.rect(14, 27, 29, 33)
        cv.put(sign, 'paper' if opened else 'red', mode='flat', iline=True)
        # rayitas de "letras" (no texto real: el juego dice Open / Closed en la interfaz)
        for x in range(16, 28, 2):
            cv.dot(x, 30, 'teal2' if opened else 'cream', 1 if opened else 3)
        out.append(render(cv))
    return out


def window_view():
    """Ventana del taller al puerto luminoso: marco de chapa remachado, cielo ámbar, dunas, cúpulas de adobe, una
    nave en la plataforma y el anillo de restos en el cielo. Se ve desde adentro (luz de día fuerte)."""
    cv = cv_new(96, 60)
    view = cv.rect(5, 5, 90, 54)
    ys = cv.ys
    cv.put(view & (ys < 22), 'sky', mode='flat', outline=False)
    cv.put(view & (ys >= 22) & (ys < 34), 'sky2', mode='flat', outline=False)
    # anillo de restos: arco fino de puntitos
    for k in range(60):
        t = k / 59.0
        x = 8 + t * 80
        y = 16 - 9 * math.sin(math.pi * t)
        if k % 2 == 0:
            cv.dot(x, y, 'far', 2, p=None)
            cv.put(cv.rect(int(x), int(y), int(x), int(y)), 'far', mode='flat', outline=False)
    # sol grande
    keep(cv, cv.put(cv.ellipse(72, 22, 7.0, 7.0) & view, 'glow', mode='flat', outline=False))
    keep(cv, cv.put((cv.ellipse(72, 22, 9.0, 9.0) & ~cv.ellipse(72, 22, 7.0, 7.0)) & view, 'glow2', mode='flat', outline=False))
    # cúpulas lejanas y dunas
    far = (cv.ellipse(20, 36, 10, 7) | cv.ellipse(36, 37, 7, 5) | cv.rect(10, 36, 46, 44)) & view
    cv.put(far, 'far', mode='flat', outline=False)
    dune = (cv.ellipse(70, 48, 30, 9) | cv.ellipse(20, 52, 26, 8)) & view
    cv.put(dune, 'dune', mode='flat', outline=False)
    cv.put(view & (ys >= 50), 'dune2', mode='flat', outline=False)
    # nave posada (escarabajo) en la plataforma
    hull = cv.ellipse(56, 40, 9, 4.6) & view
    cv.put(hull, 'hull', mode='shine', outline=False)
    cv.put(cv.rect(50, 43, 62, 45) & view, 'dkmetal', mode='flat', outline=False)
    keep(cv, cv.put(cv.rect(53, 38, 56, 39) & view, 'window', mode='flat', outline=False))
    # marco remachado con parteluz
    fr = cv.rect(0, 0, 95, 59) & ~view
    pf = cv.put(fr, 'dkmetal', mode='top', cast=1, iline=True)
    cv.put(cv.rect(46, 5, 48, 54), 'dkmetal', mode='shine', iline=True)
    for (x, y) in ((2, 2), (93, 2), (2, 57), (93, 57), (47, 2), (47, 57)):
        cv.dot(x, y, 'steel', 3)
    return render(cv)


STREET = {}     # se llena más abajo (calle, naves, cielo)

def window_view_night():
    """La misma ventana de noche: cielo violeta profundo con estrellas, el anillo de restos apenas iluminado, la
    lluvia de chatarra cayendo (estelas ámbar en diagonal), cúpulas oscuras con ventanitas encendidas."""
    cv = cv_new(96, 60)
    view = cv.rect(5, 5, 90, 54)
    ys, xs = cv.ys, cv.xs
    cv.put(view & (ys < 20), 'night', mode='flat', outline=False)
    cv.put(view & (ys >= 20) & (ys < 36), 'night2', mode='flat', outline=False)
    rng = np.random.RandomState(4)
    for _ in range(26):
        x, y = rng.randint(6, 90), rng.randint(6, 34)
        if 46 <= x <= 48:
            continue
        keep(cv, cv.put(cv.rect(x, y, x, y), 'starw', mode='flat', outline=False))
    for k in range(60):
        t = k / 59.0
        x = 8 + t * 80
        y = 16 - 9 * math.sin(math.pi * t)
        if k % 2 == 0:
            keep(cv, cv.put(cv.rect(int(x), int(y), int(x), int(y)), 'ringn', mode='flat', outline=False))
    # estelas de la lluvia de chatarra (cabeza clara, cola ámbar)
    for (x0, y0, L) in ((28, 8, 9), (66, 6, 12), (80, 18, 7), (16, 22, 6)):
        for k in range(L):
            m = 'starw' if k < 2 else ('glow2' if k < L * 0.6 else 'amber')
            keep(cv, cv.put(cv.rect(x0 + k, y0 - k // 2, x0 + k, y0 - k // 2) & view, m, mode='flat', outline=False))
    far = (cv.ellipse(20, 36, 10, 7) | cv.ellipse(36, 37, 7, 5) | cv.rect(10, 36, 46, 44)) & view
    cv.put(far, 'nightdome', mode='flat', outline=False)
    for (x, y) in ((16, 39), (24, 40), (36, 39)):
        keep(cv, cv.put(cv.rect(x, y, x + 1, y + 1), 'glow2', mode='flat', outline=False))
    dune = (cv.ellipse(70, 48, 30, 9) | cv.ellipse(20, 52, 26, 8)) & view
    cv.put(dune, 'nightdune', mode='flat', outline=False)
    cv.put(view & (ys >= 50), 'nightdune', mode='flat', outline=False)
    hull = cv.ellipse(56, 40, 9, 4.6) & view
    cv.put(hull, 'nightdome', mode='flat', outline=False)
    keep(cv, cv.put(cv.rect(53, 38, 56, 39) & view, 'glow2', mode='flat', outline=False))
    fr = cv.rect(0, 0, 95, 59) & ~view
    cv.put(fr, 'dkmetal', mode='top', cast=1, iline=True)
    cv.put(cv.rect(46, 5, 48, 54), 'dkmetal', mode='shine', iline=True)
    for (x, y) in ((2, 2), (93, 2), (2, 57), (93, 57), (47, 2), (47, 57)):
        cv.dot(x, y, 'steel', 3)
    return render(cv)


SHOP = {'workbench': (workbench, 0.03, 'bottom'), 'junk_shelf': (junk_shelf, 0.03, 'bottom'),
        'parts_cabinet': (parts_cabinet, 0.03, 'bottom'), 'crate': (lambda: crate(False), 0.03, 'bottom'),
        'crate_stack': (lambda: crate(True), 0.03, 'bottom'), 'lamp_hanging': (hanging_lamp, 0.03, 'top'),
        'cables': (cables, 0.03, 'top'), 'tea_station': (tea_station, 0.03, 'bottom'),
        'window_port': (window_view, 0.03, 'center'), 'window_port_night': (window_view_night, 0.03, 'center')}


# ================================================================== calle: piezas de edificio, puestos, torre, cartel

def dome_cap():
    """Cúpula de adobe para poner sobre un edificio: domo con un parche de chatarra remachado, un aro de chapa en la
    base, un respiradero y una antenita."""
    cv = cv_new(96, 52)
    cv.put(cv.line([(70, 2), (70, 16)]), 'dkmetal', mode='flat')
    cv.put(cv.ellipse(70, 2, 1.6, 1.6), 'red', mode='shine', iline=True)
    dome = cv.ellipse(46, 46, 42, 38) & (cv.ys <= 46)
    p = cv.put(dome, 'adobe', mode='dome', cast=1, iline=True)
    cv.set_nrm(p, cv.sphere_n(38, 32, 46, 42, k=0.9))
    # parche de chatarra (chapa remachada) en el costado
    pt = cv.poly([(56, 18), (74, 22), (72, 36), (54, 32)])
    q = cv.put(pt & dome, 'scrap', mode='flat', iline=True)
    for (x, y) in ((57, 20), (72, 24), (70, 34), (56, 30)):
        cv.dot(x, y, 'steel', 3)
    # grietas del revoque
    for pts in (((24, 26), (27, 30), (26, 34)), ((40, 14), (43, 17))):
        cv.shade(cv.line(list(pts)), -2, within=[p])
    # respiradero (tubo con sombrerito)
    cv.put(cv.rect(28, 6, 33, 16), 'dkmetal', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(26, 4, 35, 6), 'dkmetal', mode='shine', iline=True)
    # aro de chapa en la base
    cv.put(cv.rect(3, 45, 89, 51), 'rust', mode='cyl', cast=1, iline=True)
    for x in range(8, 88, 8):
        cv.dot(x, 48, 'steel', 3)
    return render(cv)


def antenna_mast():
    """Mástil de antenas: caño con travesaños, una parabólica chica y una lucecita roja arriba."""
    cv = cv_new(24, 80)
    cv.put(cv.rect(11, 6, 12, 79), 'dkmetal', mode='shine', iline=True)
    for (y, w) in ((14, 8), (26, 6), (38, 9)):
        cv.put(cv.rect(12 - w, y, 12 + w, y + 1), 'dkmetal', mode='shine', iline=True)
    dm = cv.ellipse(6, 50, 5.0, 6.0) & ~cv.ellipse(8.0, 49, 4.0, 5.0)
    cv.put(dm, 'steel', mode='shine', cast=1, iline=True)
    keep(cv, cv.put(cv.ellipse(11.5, 4, 2.0, 2.0), 'red', mode='flat'))
    cv.dot(11, 3, 'white', 4)
    return render(cv)


def vent_pipe():
    cv = cv_new(20, 30)
    cv.put(cv.stroke([(6, 29), (6, 14), (12, 8)], 2.6), 'rust', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(13, 7, 4.4, 2.2), 'dkmetal', mode='shine', iline=True)
    cv.put(cv.rect(2, 26, 10, 29), 'dkmetal', mode='shine', iline=True)
    return render(cv)


def round_window(lit=True):
    cv = cv_new(22, 22)
    cv.put(cv.ellipse(10.5, 10.5, 10, 10), 'brass', mode='shine', cast=1, iline=True)
    g = cv.ellipse(10.5, 10.5, 7.4, 7.4)
    cv.put(g, 'glow2' if lit else 'window', mode='flat' if lit else 'shine')
    if lit:
        cv.paint(cv.ellipse(10, 11, 4.0, 4.0), 'glow', 2)
    cv.put(cv.rect(10, 3, 11, 18) & g, 'dkmetal', mode='flat')
    for (x, y) in ((10.5, 1.5), (1.5, 10.5), (19.5, 10.5), (10.5, 19.5)):
        cv.dot(x, y, 'steel', 3)
    return render(cv)


def scrap_patch(kind=0):
    w, h = (28, 20) if kind == 0 else (20, 28)
    cv = cv_new(w, h)
    m = cv.poly([(1, 2), (w - 2, 0), (w - 1, h - 3), (2, h - 1)]) if kind == 0 else cv.poly([(2, 0), (w - 1, 2), (w - 3, h - 1), (0, h - 2)])
    p = cv.put(m, 'scrap' if kind == 0 else 'rust', mode='flat', iline=True)
    cv.parts[p].bias = 0.2
    for (x, y) in ((3, 3), (w - 4, 2), (w - 4, h - 4), (3, h - 3)):
        cv.dot(x, y, 'steel', 3)
    cv.shade(cv.line([(4, h // 2), (w - 5, h // 2 + 1)]), -1, within=[p])
    if kind == 1:
        cv.paint(cv.rect(4, 6, w - 6, 9) & m, 'tealp', 2)
    return render(cv)


def arch_door():
    """Portal de adobe con arco y cortina de tela a rayas (otros negocios de la calle)."""
    cv = cv_new(40, 56)
    arch = cv.rect(0, 14, 39, 55) | cv.ellipse(19.5, 16, 19.5, 15)
    p = cv.put(arch, 'adobe', mode='flat', iline=True)
    hole = cv.rect(8, 18, 31, 55) | cv.ellipse(19.5, 19, 11.5, 10)
    cv.put(hole, 'shadow', mode='flat')
    cur = cv.rect(9, 14, 30, 50) & hole
    q = cv.put(cur, 'canvas', mode='cyl', iline=True)
    for x in range(10, 31, 6):
        cv.paint(cv.rect(x, 14, x + 2, 50) & cur, 'stripe', 2)
    for x in range(12, 30, 5):
        cv.shade(cv.line([(x, 20), (x - 1, 50)]), -1, within=[q])
    return render(cv)


def stall_canopy(color='stripe'):
    """Puesto del mercado: toldo a rayas en pendiente con volado festoneado, dos postes y un mostrador de tablas."""
    cv = cv_new(88, 72)
    for x in (6, 79):
        cv.put(cv.rect(x, 14, x + 2, 71), 'wood2', mode='cyl', iline=True)
    # mostrador
    box(cv, 4, 50, 82, 58, 'wood3', top='plank', side='wood2', depth=(3, -3))
    cv.put(cv.rect(6, 59, 80, 70), 'wood', mode='flat', iline=True)
    cv.parts[-1].bias = -0.5
    # toldo
    roof = cv.poly([(0, 18), (86, 18), (80, 4), (6, 4)])
    p = cv.put(roof, 'canvas', mode='top', cast=2, iline=True)
    for k in range(0, 90, 12):
        band = cv.poly([(k, 18), (k + 6, 18), (k + 6 - (k - 43) * 0.07, 4), (k - (k - 43) * 0.07, 4)])
        cv.paint(band & roof, color, 2)
    # volado festoneado
    val = np.zeros_like(roof)
    for k, x in enumerate(range(0, 88, 6)):
        val |= cv.ellipse(x + 3, 21, 3.2, 3.4) & (cv.ys >= 18)
    val |= cv.rect(0, 18, 87, 20)
    q = cv.put(val, 'canvas', mode='cyl', cast=1, iline=True)
    for k, x in enumerate(range(0, 88, 6)):
        if k % 2 == 0:
            cv.paint(cv.rect(x, 18, x + 5, 25) & val, color, 2)
    return render(cv)


def canopy_edge(color='stripe'):
    """Volado festoneado suelto (tira de 64 px que se repite) para toldos hechos con quads 3D."""
    cv = cv_new(64, 12)
    val = cv.rect(0, 0, 63, 3)
    for x in range(0, 64, 8):
        val |= cv.ellipse(x + 4, 4, 4.2, 5.0) & (cv.ys >= 2)
    p = cv.put(val, 'canvas', mode='cyl', iline=True)
    for k, x in enumerate(range(0, 64, 8)):
        if k % 2 == 0:
            cv.paint(cv.rect(x, 0, x + 7, 11) & val, color, 2)
    return render(cv)


def well_tower():
    """Torre del pozo, oxidada: cuatro patas de reticulado, tanque redondo con chorreaduras, escalera, caño que baja a
    una bomba de manivela con canilla y un balde. (Un tanque de agua del pueblo: nada de 'vaporadores'.)"""
    cv = cv_new(56, 120)
    # patas y crucetas
    for (a, b) in (((10, 118), (18, 44)), ((46, 118), (38, 44)), ((20, 118), (22, 44)), ((36, 118), (34, 44))):
        cv.put(cv.stroke([a, b], 1.1), 'rust2', mode='cyl', iline=True)
    for y in range(52, 116, 16):
        t = (y - 44) / 74.0
        xl, xr = 18 - 8 * t, 38 + 8 * t
        cv.put(cv.line([(xl, y), (xr, y + 14)]) | cv.line([(xr, y), (xl, y + 14)]), 'rust2', mode='flat')
        cv.put(cv.rect(int(xl), y, int(xr), y), 'rust', mode='flat')
    # tanque
    tank = cv.rect(8, 14, 48, 44) | cv.ellipse(28, 14, 20, 5)
    p = cv.put(tank, 'rust', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(28, 12, 20, 5) & (cv.ys <= 12) | cv.poly([(10, 12), (46, 12), (28, 2)]), 'rust2', mode='top', cast=1, iline=True)
    for y in (22, 32, 42):
        cv.shade(cv.line([(8, y), (48, y)]), -1, within=[p])
        for x in range(10, 48, 5):
            cv.dot(x, y - 1, 'steel', 2)
    # restos de pintura y chorreaduras
    cv.paint(cv.rect(14, 24, 40, 30) & tank, 'tealp', 2)
    for x in (17, 29, 41):
        cv.paint(cv.rect(x, 30, x, 43) & tank, 'rust2', 2)
    # escalera
    for x in (44, 48):
        cv.put(cv.rect(x, 44, x, 116), 'dkmetal', mode='flat', iline=True)
    for y in range(48, 116, 5):
        cv.put(cv.rect(44, y, 48, y), 'dkmetal', mode='flat')
    # caño, bomba y canilla
    cv.put(cv.rect(26, 44, 29, 104), 'dkmetal', mode='cyl', iline=True)
    box(cv, 20, 100, 34, 118, 'teal', side='teal2', depth=(2, -2))
    cv.put(cv.stroke([(34, 104), (40, 106)], 1.1), 'dkmetal', mode='shine', iline=True)
    cv.put(cv.stroke([(20, 102), (12, 96)], 0.9), 'dkmetal', mode='shine', iline=True)
    cv.put(cv.rect(37, 110, 43, 118), 'steel', mode='cyl', iline=True)
    return render(cv)


STAR_TIPS = None


def star_sign(lit=0):
    """El cartel de la tienda: una estrella de chapa de cinco puntas, remendada y remachada, con un foco en cada
    punta. lit = cuántas puntas están encendidas (0-5; se encienden en orden: arriba y en sentido horario)."""
    cv = cv_new(72, 72)
    cx, cy = 36.0, 38.0
    ro, ri = 33.0, 14.0

    def pts(r_o, r_i):
        out = []
        for k in range(10):
            a = math.radians(-90 + k * 36)
            r = r_o if k % 2 == 0 else r_i
            out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
        return out
    P = pts(ro, ri)
    body = cv.poly(P)
    p = cv.put(body, 'star_off', mode='flat', cast=1, iline=True)
    # cada punta: triángulo entre las dos esquinas internas vecinas
    for k in range(5):
        tip = P[2 * k]
        l, r = P[(2 * k - 1) % 10], P[(2 * k + 1) % 10]
        tri = cv.poly([tip, l, (cx, cy), r]) & body
        on = k < lit
        cv.paint(tri, 'star' if on else 'star_off', 2)
        # foco de la punta
        bx, by = cx + (tip[0] - cx) * 0.80, cy + (tip[1] - cy) * 0.80
        keep(cv, cv.put(cv.ellipse(bx, by, 2.2, 2.2), 'bulb' if on else 'bulb_off', mode='flat' if on else 'shine', iline=True))
        if on:
            cv.dot(bx - 0.6, by - 0.6, 'white', 4)
    # biseles: luz arriba a la izquierda de cada cara (la placa es plana, se marcan las aristas)
    for k in range(10):
        a, b = P[k], P[(k + 1) % 10]
        cv.shade(cv.line([(cx, cy), a]), -1, within=[p])
    # parche soldado en una punta (está remendada) y remaches
    pt = cv.poly([(46, 44), (56, 48), (53, 54), (44, 50)])
    cv.put(pt & body, 'scrap', mode='flat', iline=True)
    for (x, y) in ((47, 46), (54, 49), (52, 53)):
        cv.dot(x, y, 'steel', 3)
    # disco central remachado con un tornillo grande
    cv.put(cv.ellipse(cx, cy, 7.0, 7.0), 'brass', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(cx, cy, 2.0, 2.0), 'dkmetal', mode='shine', iline=True)
    for a in range(0, 360, 72):
        cv.dot(cx + math.cos(math.radians(a - 90)) * 5.0, cy + math.sin(math.radians(a - 90)) * 5.0, 'dkmetal', 1)
    # soporte abajo
    cv.put(cv.rect(34, 66, 38, 71), 'dkmetal', mode='cyl', iline=True)
    return render(cv)


def shop_plate():
    """Placa con el nombre de la tienda: THE SECONDHAND STAR (esténcil crema sobre chapa verde agua remachada).
    El ancho sale del texto (no se corta)."""
    from PIL import ImageDraw, ImageFont
    f = ImageFont.truetype(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts', 'SairaStencilOne-Regular.ttf'), 11)
    txt = 'THE SECONDHAND STAR'
    tw = int(math.ceil(f.getlength(txt)))
    w, h = tw + 16, 18
    cv = cv_new(w, h)
    cv.put(cv.rect(0, 0, w - 1, h - 1), 'teal', mode='top', cast=1, iline=True)
    for (x, y) in ((2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)):
        cv.dot(x, y, 'steel', 3)
    arr = render(cv)
    im = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(im)
    d.fontmode = '1'
    d.text(((w - tw) / 2, 2), txt, font=f, fill=255)
    m = np.array(im) > 127
    sh = np.zeros_like(m)
    sh[1:, 1:] = m[:-1, :-1]
    arr[sh & ~m, :3] = (24, 40, 40)
    arr[m, :3] = (236, 226, 200)
    return arr


# ================================================================== naves (originales), anillo de restos, sol, estrella fugaz

def ship_hammerhead():
    """Carguero 'cabeza de martillo': casco rechoncho y cuadrado, proa ancha y alta como un yunque (con ventanas del
    puente), contenedores apilados de colores, dos motores grandes atrás y patas de aterrizaje. Visto de costado."""
    cv = cv_new(176, 76)
    # patas
    for x in (46, 96, 140):
        cv.put(cv.stroke([(x, 56), (x - 4, 70)], 1.4), 'dkmetal', mode='shine', iline=True)
        cv.put(cv.rect(x - 9, 70, x + 1, 72), 'dkmetal', mode='shine', iline=True)
    # motores atrás
    for (y, r) in ((30, 9), (48, 8)):
        cv.put(cv.rect(4, y - r, 26, y + r), 'hull2', mode='stroke', nrm=hcyl_n(cv, y, r), cast=1, iline=True)
        cv.put(cv.ellipse(4, y, 3, r), 'dkmetal', mode='shine', iline=True)
        cv.put(cv.ellipse(3, y, 1.6, r - 2.5), 'engine', mode='flat')
    # casco
    hull = cv.rect(20, 22, 140, 58)
    p = cv.put(hull, 'hull', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(20, 50, 140, 53), 'hullr', 2)
    for x in range(30, 140, 14):
        cv.shade(cv.line([(x, 23), (x, 57)]), -1, within=[p])
    # contenedores arriba
    for (x0, w, c) in ((30, 26, 'rust'), (58, 22, 'hullt'), (82, 28, 'cream'), (112, 20, 'rust')):
        box(cv, x0, 10, x0 + w, 22, c, depth=(2, -2))
    # proa martillo: bloque alto y ancho con ventanas
    bow = cv.poly([(136, 6), (164, 10), (172, 40), (168, 66), (138, 62)])
    q = cv.put(bow, 'hull', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(150, 16, 170, 21) & bow, 'window', 2)
    for x in range(151, 170, 4):
        cv.dot(x, 18, 'white', 3)
    cv.paint(cv.poly([(140, 56), (168, 58), (168, 62), (139, 61)]) & bow, 'hullr', 2)
    cv.shade(cv.line([(138, 30), (171, 32)]), -1, within=[q])
    # antena y número
    cv.put(cv.line([(152, 6), (156, 0)]), 'dkmetal', mode='flat')
    for (x, y) in ((60, 38), (64, 38), (68, 38)):
        cv.put(cv.rect(x, y, x + 2, y + 5), 'hullt', mode='flat')
    soot(cv, 32, 30, 4, 2)
    return render(cv)


def ship_beetle():
    """Lanzadera 'escarabajo': caparazón redondo partido en dos élitros (rojo óxido) sobre una panza oscura, cabina
    redonda adelante con ventanales, seis patitas de aterrizaje y dos toberas cortas atrás."""
    cv = cv_new(116, 72)
    for x in (30, 56, 82):
        cv.put(cv.stroke([(x, 50), (x - 6, 64), (x - 9, 68)], 1.3), 'dkmetal', mode='shine', iline=True)
        cv.put(cv.rect(x - 13, 68, x - 5, 70), 'dkmetal', mode='shine', iline=True)
    for y in (36, 46):
        cv.put(cv.rect(2, y - 4, 14, y + 4), 'hull2', mode='stroke', nrm=hcyl_n(cv, y, 4), cast=1, iline=True)
        cv.put(cv.ellipse(2, y, 1.6, 3.0), 'engine', mode='flat')
    belly = cv.ellipse(56, 46, 46, 12)
    cv.put(belly, 'dkmetal', mode='cyl', cast=1, iline=True)
    shell = cv.ellipse(52, 38, 44, 26) & (cv.ys <= 46)
    p = cv.put(shell, 'hullr', mode='dome', cast=2, iline=True)
    cv.set_nrm(p, cv.sphere_n(44, 26, 50, 32, k=0.9))
    cv.shade(cv.line([(14, 34), (52, 14), (92, 30)]), -2, within=[p])
    for (x, y) in ((30, 30), (46, 24), (64, 26), (78, 34)):
        cv.paint(cv.ellipse(x, y, 3.0, 2.0) & shell, 'hull', 2)
    head = cv.ellipse(98, 42, 14, 12)
    q = cv.put(head, 'hull', mode='dome', cast=1, iline=True)
    cv.set_nrm(q, cv.sphere_n(94, 38, 15, 13))
    win = cv.ellipse(104, 38, 7, 5) & head
    cv.put(win, 'window', mode='shine', iline=True)
    cv.dot(101, 36, 'white', 4)
    cv.dot(102, 35, 'white', 3)
    return render(cv)


def ship_needle():
    """Correo 'aguja': cuerpo larguísimo y fino que termina en punta, cabina de burbuja atrás, dos aletitas en flecha
    y UN motor (nada de corredores de dos motores)."""
    cv = cv_new(150, 40)
    fin = cv.poly([(18, 18), (36, 18), (22, 4), (14, 4)])
    cv.put(fin, 'hullt', mode='top', cast=1, iline=True)
    body = cv.poly([(8, 16), (60, 15), (148, 22), (60, 29), (8, 28)])
    p = cv.put(body, 'hull', mode='stroke', nrm=hcyl_n(cv, 22.0, 7.0), cast=1, iline=True)
    cv.paint(cv.poly([(10, 22), (146, 22), (60, 25), (10, 25)]) & body, 'amber', 2)
    fin2 = cv.poly([(18, 26), (36, 26), (24, 38), (14, 38)])
    cv.put(fin2, 'hullt', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(0, 18, 9, 26), 'hull2', mode='stroke', nrm=hcyl_n(cv, 22, 4), cast=1, iline=True)
    cv.put(cv.ellipse(0.5, 22, 1.4, 3.0), 'engine', mode='flat')
    bub = cv.ellipse(46, 15, 9, 5) & (cv.ys <= 17)
    cv.put(bub, 'window', mode='shine', cast=1, iline=True)
    cv.dot(42, 12, 'white', 4)
    return render(cv)


def thrust_flame(i=0):
    """Llama de propulsión para el despegue (3 cuadros): núcleo blanco, cuerpo ámbar, puntas naranjas."""
    cv = cv_new(20, 28)
    L = [22, 26, 19][i]
    w = [6.0, 5.4, 6.6][i]
    outer = cv.poly([(10 - w, 0), (10 + w, 0), (10 + 1.5, L), (10 - 1.5, L)])
    keep(cv, cv.put(outer, 'glow2', mode='flat', outline=False))
    inner = cv.poly([(10 - w * 0.6, 0), (10 + w * 0.6, 0), (10.5, L * 0.6), (9.5, L * 0.6)])
    keep(cv, cv.put(inner, 'glow', mode='flat', outline=False))
    core = cv.poly([(10 - w * 0.3, 0), (10 + w * 0.3, 0), (10, L * 0.3)])
    keep(cv, cv.put(core, 'bulb', mode='flat', outline=False))
    return render(cv)


def sky_ring():
    """El anillo misterioso de restos (el viejo astillero) cruzando el cielo: arco fino de pedazos oscuros con el
    borde iluminado por el sol, más tupido en grumos; sin alfa intermedio (solo opaco o transparente)."""
    W_, H_ = 512, 112
    rng = np.random.RandomState(9)
    arr = np.zeros((H_, W_, 4), np.uint8)
    dark = (150, 128, 112, 255)
    mid = (184, 160, 134, 255)
    lite = (236, 208, 164, 255)
    for k in range(1400):
        t = rng.rand()
        # densidad en grumos
        if rng.rand() > 0.55 + 0.45 * math.sin(t * math.pi * 7 + 1.0) ** 2:
            continue
        x = 6 + t * (W_ - 12)
        y = (H_ - 10) - (H_ - 26) * math.sin(math.pi * t) + rng.normal(0, 2.2)
        s = rng.choice([1, 1, 1, 2, 2, 3])
        xi, yi = int(x), int(y)
        if 0 <= yi < H_ - s and 0 <= xi < W_ - s:
            arr[yi:yi + s, xi:xi + s] = dark if s > 1 else mid
            if s > 1:
                arr[yi, xi:xi + s] = lite
    # banda tenue: puntitos sueltos a lo largo del arco (polvo)
    for k in range(900):
        t = rng.rand()
        x = 6 + t * (W_ - 12)
        y = (H_ - 10) - (H_ - 26) * math.sin(math.pi * t) + rng.normal(0, 5.0)
        xi, yi = int(x), int(y)
        if 0 <= yi < H_ and 0 <= xi < W_ and arr[yi, xi, 3] == 0 and (xi + yi) % 2 == 0:
            arr[yi, xi] = (214, 190, 156, 255)
    return arr


def sun_disc():
    """Sol grande ámbar: bandas concéntricas posterizadas (sin degradé), todo opaco."""
    W_ = 160
    arr = np.zeros((W_, W_, 4), np.uint8)
    yy, xx = np.mgrid[0:W_, 0:W_]
    d = np.sqrt((xx - 79.5) ** 2 + (yy - 79.5) ** 2)
    bands = [(79, (232, 140, 60)), (70, (240, 164, 70)), (58, (250, 196, 96)), (46, (255, 222, 140)), (36, (255, 240, 196))]
    for r, c in bands:
        m = d <= r
        arr[m, :3] = c
        arr[m, 3] = 255
    # anillos punteados en la corona exterior
    ring = (d > 70) & (d <= 79) & ((xx + yy) % 3 == 0)
    arr[ring, :3] = (226, 128, 54)
    return arr


def starfall():
    """Estrella fugaz de la lluvia de chatarra (de noche): cabeza blanca, estela que se apaga en diagonal."""
    W_, H_ = 64, 24
    arr = np.zeros((H_, W_, 4), np.uint8)
    cols = [(255, 248, 220), (255, 226, 150), (246, 176, 80), (200, 120, 60)]
    for k in range(60):
        x = 62 - k
        y = 2 + k * 0.33
        c = cols[min(3, k // 12)]
        w = 3 if k < 6 else (2 if k < 24 else 1)
        if k > 40 and k % 2:
            continue
        for j in range(w):
            yi = int(y) + j - w // 2
            if 0 <= yi < H_ and 0 <= x < W_:
                arr[yi, x, :3] = c
                arr[yi, x, 3] = 255
    arr[1:4, 60:63, :3] = (255, 255, 255)
    arr[1:4, 60:63, 3] = 255
    return arr


STREET.update({
    'dome_cap': (dome_cap, 0.045, 'bottom'), 'antenna_mast': (antenna_mast, 0.04, 'bottom'),
    'vent_pipe': (vent_pipe, 0.04, 'bottom'), 'round_window': (lambda: round_window(True), 0.035, 'center'),
    'round_window_dark': (lambda: round_window(False), 0.035, 'center'), 'scrap_patch_a': (lambda: scrap_patch(0), 0.035, 'center'),
    'scrap_patch_b': (lambda: scrap_patch(1), 0.035, 'center'), 'arch_door': (arch_door, 0.045, 'bottom'),
    'stall_canopy_red': (lambda: stall_canopy('stripe'), 0.04, 'bottom'), 'stall_canopy_teal': (lambda: stall_canopy('teal'), 0.04, 'bottom'),
    'canopy_edge_red': (lambda: canopy_edge('stripe'), 0.04, 'top'), 'canopy_edge_teal': (lambda: canopy_edge('teal'), 0.04, 'top'),
    'well_tower': (well_tower, 0.045, 'bottom'), 'shop_plate': (shop_plate, 0.02, 'center'),
    'ship_hammerhead': (ship_hammerhead, 0.06, 'center'), 'ship_beetle': (ship_beetle, 0.06, 'center'),
    'ship_needle': (ship_needle, 0.06, 'center'), 'sky_ring': (sky_ring, 0.1, 'center'), 'sun': (sun_disc, 0.1, 'center'),
    'starfall': (starfall, 0.06, 'center'),
})
for _n in range(6):
    STREET[f'star_sign_{_n}'] = ((lambda n=_n: star_sign(n)), 0.04, 'bottom')

STRIPS = {'ceiling_fan': (lambda: [ceiling_fan(i) for i in range(4)], 0.03, 'top'),
          'door': (shop_door, 0.035, 'bottom'), 'thrust_flame': (lambda: [thrust_flame(i) for i in range(3)], 0.06, 'top')}


def build_props(out, names=None):
    d = os.path.join(out, 'props')
    os.makedirs(d, exist_ok=True)
    spec = {}
    for table in (SHOP, STREET):
        for name, (fn, px, anchor) in table.items():
            if names and name not in names:
                continue
            Image.fromarray(fn(), 'RGBA').save(os.path.join(d, f'{name}.png'))
            spec[name] = dict(px=px, anchor=anchor)
    for name, (fn, px, anchor) in STRIPS.items():
        if names and name not in names:
            continue
        frs = fn()
        Image.fromarray(np.concatenate(frs, axis=1), 'RGBA').save(os.path.join(d, f'{name}.png'))
        spec[name] = dict(px=px, anchor=anchor, frames=len(frs))
    return spec


if __name__ == '__main__':
    args = sys.argv[1:]
    out = './out'
    if '--out' in args:
        k = args.index('--out')
        out = args[k + 1]
        del args[k:k + 2]
    spec = build_props(out, args or None)
    pj = os.path.join(out, 'props', 'props.json')
    old = json.load(open(pj)) if os.path.exists(pj) else {}
    old.update(spec)
    old['tortoise'] = dict(px=0.0222, anchor='bottom', note='same pixel density as the characters (drawn next to them 1:1)')
    json.dump(old, open(pj, 'w'), indent=1, sort_keys=True)
    print('ok props', len(spec))
