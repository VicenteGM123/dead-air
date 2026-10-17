"""Miga, la gata de la tienda, a doble resolución (mismo render que los personajes).

Cuadros de 64x96 con las patas en la fila 91 (como todo el elenco: sirve con Actor),
y la hoja de la tienda props/cat.png: 5 cuadros de 48x40 (dormida x2, sentada x2, feliz).
"""
import math
import numpy as np
from c64core import *
from c64body import GROUND

PAL = {
    'fur': ramp5('#8f9bb8'), 'fur2': ramp5('#6c7794'), 'bib': ramp5('#f4f1ea', 'white'), 'inner': ramp5('#f2a2b0'),
    'nose': ramp5('#f08a9c', 'flat'), 'iris': ramp5('#ffd24a'), 'lash': ramp5('#2a2238'), 'white': [(138, 136, 170), (196, 196, 220), (226, 228, 240), (244, 245, 252), (255, 255, 255)],
    'blush': ramp5('#f6a8b4', 'flat'),
}

G = GROUND


def _eye(cv, p, x, y, mode='open', far=False):
    """Ojo de gata: lagrimal oscuro arriba, iris amarillo con pupila rasgada y brillo."""
    x, y = int(x), int(y)
    if mode == 'open':
        w = 2 if far else 3
        for dx in range(w):
            cv.dot(x + dx, y, 'lash', 2, p)
        for dy in (1, 2, 3):
            for dx in range(w):
                cv.dot(x + dx, y + dy, 'iris', 3 if dy == 3 else 2, p)
        cv.dot(x + (1 if not far else 0), y + 1, 'lash', 2, p)
        cv.dot(x + (1 if not far else 0), y + 2, 'lash', 2, p)
        cv.dot(x, y + 1, 'white', 4, p)
    elif mode == 'happy':       # ^ ^
        cv.dot(x, y + 2, 'lash', 2, p)
        cv.dot(x + 1, y + 1, 'lash', 2, p)
        if not far:
            cv.dot(x + 2, y + 2, 'lash', 2, p)
    else:                       # dormida: arco hacia abajo
        cv.dot(x, y + 1, 'lash', 2, p)
        cv.dot(x + 1, y + 2, 'lash', 2, p)
        if not far:
            cv.dot(x + 2, y + 1, 'lash', 2, p)


def _head(cv, cx, cy, eyes='open', s=1.0, tilt=0.0):
    hd = cv.ellipse(cx, cy, 8.6 * s, 7.0 * s) | cv.ellipse(cx + 0.5, cy + 2.2 * s, 9.2 * s, 4.6 * s)
    # orejas
    for (bx, tx, d) in ((-5.2, -6.0, 0), (4.6, 6.6, 1)):
        base_l = (cx + (bx - 3.0) * s, cy - 4.0 * s)
        base_r = (cx + (bx + 3.0) * s, cy - 5.2 * s + d * 1.0)
        tip = (cx + tx * s + tilt, cy - 12.5 * s)
        hd |= cv.poly([base_l, tip, base_r])
    p = cv.put(hd, 'fur', mode='top', cast=1, band=0.22)
    for (bx, tx, d) in ((-5.2, -6.0, 0), (4.6, 6.6, 1)):
        inner = cv.poly([(cx + (bx - 1.4) * s, cy - 5.0 * s), (cx + tx * s * 0.92 + tilt, cy - 10.5 * s), (cx + (bx + 1.6) * s, cy - 5.6 * s)])
        cv.paint(inner & cv.of(p), 'inner', 2 if d == 0 else 1)
    # rayitas en la frente
    for dx in (-1.5, 0.5, 2.5):
        cv.shade(cv.line([(cx + dx * s, cy - 6.0 * s), (cx + dx * s + 0.3, cy - 3.8 * s)]), -1, within=[p])
    # hocico blanco
    mz = cv.ellipse(cx + 2.6 * s, cy + 3.2 * s, 4.2 * s, 2.6 * s)
    cv.paint(mz & cv.of(p), 'bib', 3)
    # ojos, nariz y boca
    _eye(cv, p, cx - 4.0 * s, cy - 1.5 * s, eyes)
    _eye(cv, p, cx + 3.0 * s, cy - 1.5 * s, eyes, far=True)
    nx, ny = int(cx + 2.2 * s), int(cy + 2.0 * s)
    cv.dot(nx, ny, 'nose', 2, p)
    cv.dot(nx - 1, ny + 1, 'lash', 1, p)
    cv.dot(nx + 1, ny + 1, 'lash', 1, p)
    if eyes == 'happy':
        cv.dot(cx - 5.5 * s, cy + 2.0 * s, 'blush', 2, p)
        cv.dot(cx - 4.5 * s, cy + 2.0 * s, 'blush', 2, p)
    return p


def sit(swish=0, eyes='open', breath=0):
    cv = Cv(PAL)
    cx = 30
    # cola rodeando por la izquierda
    tail = bez3((cx - 7, G - 4), (cx - 16, G - 3), (cx - 18 + swish, G - 16), (cx - 13 + swish * 1.5, G - 24), 14)
    pt = cv.put(cv.stroke(tail, 2.3, 1.9), 'fur2', mode='top', band=0.3)
    cv.paint(cv.stroke(tail[-3:], 2.3, 2.0) & cv.of(pt), 'fur2', 1)
    # cuerpo (pera) y anca
    body = cv.ellipse(cx, G - 10.5 + breath * 0.3, 10.0, 12.5 + breath * 0.3) & (cv.ys <= G)
    pb = cv.put(body, 'fur', mode='top', band=0.24)
    haunch = cv.ellipse(cx - 4.5, G - 5.5, 7.0, 5.8) & (cv.ys <= G)
    cv.put(haunch, 'fur', mode='cyl', iline=True, band=0.3)
    bib = cv.ellipse(cx + 5.5, G - 15.0, 3.8, 5.5) & cv.of(pb)
    cv.paint(bib, 'bib', 3)
    # patas delanteras: grises con calcetines blancos
    for (px, w) in ((cx + 3.5, 2.3), (cx + 7.5, 2.3)):
        leg = cv.capsule((px, G - 9), (px + 0.3, G - 1.2), w * 0.9, w)
        pl = cv.put(leg, 'fur', mode='cyl', iline=True)
        cv.paint(cv.of(pl) & (cv.ys >= G - 3), 'bib', 3)
    _head(cv, cx + 4.0, G - 27 + breath, eyes=eyes)
    return render(cv)


def sleep(breath=0):
    cv = Cv(PAL)
    cx = 30
    body = cv.ellipse(cx - 1.0, G - 6.0 - breath * 0.5, 15.0, 7.0 + breath * 0.5) & (cv.ys <= G)
    pb = cv.put(body, 'fur', mode='top', band=0.22)
    # rayas del lomo
    for dx in (-8, -3, 2):
        cv.shade(cv.line([(cx + dx, G - 12.5 - breath * 0.5), (cx + dx + 1, G - 9.5)]), -1, within=[pb])
    # cabeza apoyada a la derecha
    _head(cv, cx + 11.0, G - 8.5, eyes='sleep', s=0.82, tilt=1.0)
    # cola enroscada por delante
    tail = bez3((cx - 14, G - 4), (cx - 12, G + 0.5), (cx + 4, G + 0.5), (cx + 9, G - 1.5), 12)
    cv.put(cv.stroke(tail, 2.0, 1.7), 'fur2', mode='top', iline=True)
    return render(cv)


def walk(i):
    cv = Cv(PAL)
    cx = 29
    bob = [0, -1, 0, -1][i]
    sw = [1, 0, -1, 0][i]
    # patas lejanas (detrás, más oscuras)
    legs = {
        'fr_far': (cx + 7.0, [-2.0, 0.0, 2.0, 0.0][i]),
        'bk_far': (cx - 7.5, [2.0, 0.0, -2.0, 0.0][i]),
        'fr_near': (cx + 9.0, [2.0, 0.5, -2.0, -0.5][i]),
        'bk_near': (cx - 5.5, [-2.0, -0.5, 2.0, 0.5][i]),
    }
    lift = {'fr_far': [0, 0, 0, 2][i], 'bk_far': [0, 2, 0, 0][i], 'fr_near': [0, 2, 0, 0][i], 'bk_near': [0, 0, 0, 2][i]}
    tail = bez3((cx - 10, G - 12 + bob), (cx - 16, G - 15 + bob), (cx - 17 + sw, G - 24 + bob), (cx - 12 + sw * 2, G - 29 + bob), 14)
    cv.put(cv.stroke(tail, 2.2, 1.8), 'fur2', mode='top')
    for k in ('fr_far', 'bk_far'):
        x, dx = legs[k]
        p = cv.put(cv.capsule((x, G - 10 + bob), (x + dx, G - 1.2 - lift[k]), 2.2, 2.0), 'fur', mode='cyl')
        cv.shade(cv.of(p), -1)
    body = cv.ellipse(cx, G - 11.5 + bob, 12.0, 6.5)
    pb = cv.put(body, 'fur', mode='top', band=0.22)
    cv.paint(cv.ellipse(cx + 5.0, G - 8.0 + bob, 6.0, 3.0) & cv.of(pb), 'bib', 3)
    for dx in (-7, -2, 3):
        cv.shade(cv.line([(cx + dx, G - 17.5 + bob), (cx + dx + 1, G - 14.5 + bob)]), -1, within=[pb])
    for k in ('fr_near', 'bk_near'):
        x, dx = legs[k]
        mat = 'bib' if k == 'fr_near' else 'fur'
        cv.put(cv.capsule((x, G - 10 + bob), (x + dx, G - 1.2 - lift[k]), 2.3, 2.1), mat, mode='cyl', iline=True)
    _head(cv, cx + 13.0, G - 21.5 + bob, s=0.9)
    return render(cv)


def frames():
    idle = [sit(0), sit(2, breath=1)]
    wk = [walk(i) for i in range(4)]
    return idle, wk


def shop_sheet():
    """props/cat.png de la tienda: [dormida, dormida, sentada, sentada, feliz], cuadros de 48x40."""
    fr = [sleep(0), sleep(1), sit(0), sit(2), sit(1, eyes='happy')]
    out = []
    for f in fr:
        out.append(f[G - 39:G + 1, 8:56])
    return np.concatenate(out, axis=1)
