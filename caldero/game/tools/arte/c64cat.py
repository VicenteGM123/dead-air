"""Miga, la gata de la tienda (mismo render que los personajes). --- R3 ART3: proporciones de gata de verdad.

Cabeza redonda con orejas triangulares, hocico chico; sentada: pecho erguido, patas delanteras finas y rectas, anca
redonda atrás y la cola enroscada; caminando: cuerpo largo, patas finas con patitas, cabeza al frente y la cola
arriba; dormida: un pan redondo con la cabeza apoyada y la cola alrededor.
Cuadros de 64x96 con las patas en la fila 91 (como todo el elenco: sirve con Actor) y la hoja de la tienda
props/cat.png: 5 cuadros de 48x40 (dormida x2, sentada x2, feliz) — el mismo formato que usa shop_world.gd.
"""
import math
import numpy as np
from c64core import *
from c64body import GROUND

PAL = {
    'fur': ramp5('#8f9bb8'), 'fur2': ramp5('#7a86a4'), 'bib': ramp5('#f4f1ea', 'white'), 'inner': ramp5('#eaa0ae'),
    'nose': ramp5('#e8889a', 'flat'), 'iris': ramp5('#f2c23e'), 'lash': ramp5('#2a2238'),
    'white': [(138, 136, 170), (196, 196, 220), (226, 228, 240), (244, 245, 252), (255, 255, 255)],
    'blush': ramp5('#f2a2b0', 'flat'),
}

G = GROUND


def _eye(cv, p, x, y, mode='open', far=False):
    """Ojo de gata (2-3 px de ancho, 3 de alto): iris amarillo con la pupila rasgada y un brillo; cerrado: arco."""
    x, y = int(round(x)), int(round(y))
    if mode == 'open':
        w = 2 if far else 3
        for dx in range(w):
            for dy in range(3):
                cv.dot(x + dx, y + dy, 'iris', 3 if dy == 2 else 2, p)
        px_ = x + (1 if not far else 1)
        cv.dot(px_, y, 'lash', 1, p)
        cv.dot(px_, y + 1, 'lash', 1, p)
        cv.dot(px_, y + 2, 'lash', 1, p)
        for dx in range(w):
            cv.dot(x + dx, y - 1, 'lash', 2, p)
        if not far:
            cv.dot(x, y, 'white', 4, p)
    elif mode == 'happy':       # ^ ^
        cv.dot(x, y + 2, 'lash', 1, p)
        cv.dot(x + 1, y + 1, 'lash', 1, p)
        if not far:
            cv.dot(x + 2, y + 2, 'lash', 1, p)
    else:                       # dormida: arco hacia abajo
        cv.dot(x, y + 1, 'lash', 1, p)
        cv.dot(x + 1, y + 2, 'lash', 1, p)
        if not far:
            cv.dot(x + 2, y + 1, 'lash', 1, p)


def _head(cv, cx, cy, eyes='open', s=1.0, tilt=0.0, ear_flick=0.0):
    """Cabeza redonda en 3/4 mirando a la derecha: cráneo, mejillas mullidas, orejas triangulares, hocico chico."""
    hd = cv.ellipse(cx, cy, 6.3 * s, 5.2 * s) | cv.ellipse(cx + 0.4 * s, cy + 1.7 * s, 6.6 * s, 3.5 * s)
    ears = []
    # oreja cercana (izquierda) y lejana (derecha, algo más chica por la perspectiva)
    for (b0, b1, tip, k) in (((-6.0, -1.8), (-1.6, -4.6), (-5.4 + tilt, -10.2 + ear_flick), 1.0),
                             ((1.6, -4.8), (5.8, -2.4), (4.8 + tilt, -9.6), 0.92)):
        e = cv.poly([(cx + b0[0] * s, cy + b0[1] * s), (cx + tip[0] * s, cy + tip[1] * s), (cx + b1[0] * s, cy + b1[1] * s)])
        ears.append((e, b0, b1, tip))
        hd |= e
    p = cv.put(hd, 'fur', mode='top', cast=1, band=0.22)
    cv.set_nrm(p, cv.sphere_n(cx - 0.6 * s, cy - 0.4 * s, 7.2 * s, 6.4 * s, k=0.8))
    for i, (e, b0, b1, tip) in enumerate(ears):
        c0 = ((b0[0] + b1[0]) / 2, (b0[1] + b1[1]) / 2)
        inner = cv.poly([(cx + (b0[0] * 0.65 + c0[0] * 0.35) * s, cy + (b0[1] * 0.65 + c0[1] * 0.35 - 0.6) * s),
                         (cx + (tip[0] * 0.80 + c0[0] * 0.20) * s, cy + (tip[1] * 0.80 + c0[1] * 0.20) * s),
                         (cx + (b1[0] * 0.65 + c0[0] * 0.35) * s, cy + (b1[1] * 0.65 + c0[1] * 0.35 - 0.6) * s)])
        cv.paint(inner & cv.of(p), 'inner', 2 if i == 0 else 1)
    # rayitas de la frente (tres trazos cortos)
    for dx in (-1.2, 0.6, 2.4):
        cv.shade(cv.line([(cx + dx * s, cy - 4.6 * s), (cx + (dx + 0.2) * s, cy - 3.0 * s)]), -1, within=[p])
    # hocico y pechera blanca bajo la nariz
    mz = cv.ellipse(cx + 2.0 * s, cy + 2.4 * s, 3.2 * s, 2.0 * s)
    cv.paint(mz & cv.of(p), 'bib', 3)
    # ojos, nariz y boca
    _eye(cv, p, cx - 3.6 * s, cy - 1.4 * s, eyes)
    _eye(cv, p, cx + 1.6 * s, cy - 1.5 * s, eyes, far=True)
    nx, ny = int(round(cx + 1.6 * s)), int(round(cy + 1.3 * s))
    cv.dot(nx, ny, 'nose', 2, p)
    cv.dot(nx - 1, ny + 1, 'lash', 1, p)
    cv.dot(nx + 1, ny + 1, 'lash', 1, p)
    if eyes == 'happy':
        cv.dot(cx - 4.2 * s, cy + 1.6 * s, 'blush', 2, p)
        cv.dot(cx - 3.2 * s, cy + 1.6 * s, 'blush', 2, p)
    return p


def _paw(cv, x, y, mat='bib', r=1.6):
    return cv.put(cv.ellipse(x, y, r, r * 0.75), mat, mode='top', iline=True)


def sit(swish=0, eyes='open', breath=0):
    """Sentada de 3/4 mirando a la derecha: pecho erguido, patas delanteras rectas, anca redonda, cola enroscada."""
    cv = Cv(PAL)
    cx = 30
    by = G
    # cola: sale del anca, se curva detrás y sube; la punta se mece
    tail = bez3((cx - 7.5, by - 3.0), (cx - 14.0, by - 3.5), (cx - 15.5 + swish * 0.5, by - 13.0), (cx - 12.0 + swish, by - 19.0), 16)
    radii = [max(0.9, 1.7 - 0.6 * i / 16) for i in range(17)]
    m, n = cv.stroke_n(tail, radii)
    pt = cv.put(m, 'fur2', mode='stroke', nrm=n, iline=True)
    cv.paint(cv.stroke(tail[-3:], 1.6, 1.2) & cv.of(pt), 'fur2', 1)
    # anca (la pata de atrás doblada) y lomo
    haunch = cv.ellipse(cx - 3.2, by - 6.4, 7.0, 6.4) & (cv.ys <= by)
    back = cv.poly([(cx - 8.0, by - 7.0), (cx - 3.0, by - 15.5 - breath * 0.3), (cx + 2.0, by - 21.0 - breath * 0.3),
                    (cx + 6.5, by - 19.0), (cx + 7.0, by - 8.0), (cx + 2.0, by - 2.0), (cx - 6.0, by - 1.0)])
    pb = cv.put(back | haunch, 'fur', mode='top', band=0.24)
    cv.set_nrm(pb, cv.sphere_n(cx - 1.5, by - 10.0, 10.0, 12.0, k=0.85))
    # pliegue del anca (la pata trasera)
    cv.shade(cv.line(bez((cx - 9.0, by - 4.0), (cx - 6.0, by - 11.5), (cx + 0.5, by - 8.0), 8)) & cv.of(pb), -1, within=[pb])
    # pecho y pechera blanca
    chest = cv.ellipse(cx + 3.8, by - 13.0 - breath * 0.3, 4.6, 7.5)
    pc = cv.put(chest, 'fur', mode='top', band=0.24, iline=True)
    cv.paint(cv.ellipse(cx + 5.0, by - 13.0 - breath * 0.3, 2.8, 5.2) & cv.of(pc), 'bib', 3)
    # pata trasera (la patita asoma delante del anca)
    _paw(cv, cx - 1.5, by - 1.0, 'bib', 2.0)
    # patas delanteras: la lejana más oscura, la cercana delante
    for (px_, far) in ((cx + 6.2, True), (cx + 3.2, False)):
        leg, ln = cv.capsule_n((px_, by - 9.0), (px_ + 0.2, by - 2.0), 1.35, 1.25)
        pl = cv.put(leg, 'fur', mode='stroke', nrm=ln, iline=True, bias=-0.5 if far else 0.0)
        cv.paint(cv.of(pl) & (cv.ys >= by - 4), 'bib', 3)
        _paw(cv, px_ + 0.6, by - 1.0, 'bib', 1.7)
    _head(cv, cx + 4.6, by - 25.0 + breath, eyes=eyes, ear_flick=(0.6 if swish > 1 else 0.0))
    return render(cv)


def sleep(breath=0):
    """Dormida hecha un pan: lomo redondo, la cabeza apoyada a la derecha sobre las patas, la cola alrededor."""
    cv = Cv(PAL)
    cx = 30
    by = G
    body = cv.ellipse(cx - 2.0, by - 6.0 - breath * 0.5, 13.0, 6.2 + breath * 0.5) & (cv.ys <= by)
    pb = cv.put(body, 'fur', mode='top', band=0.22)
    cv.set_nrm(pb, cv.sphere_n(cx - 4.0, by - 9.0, 14.0, 9.0, k=0.85))
    # rayas del lomo
    for dx in (-9, -4, 1):
        cv.shade(cv.line([(cx + dx, by - 11.5 - breath * 0.5), (cx + dx + 1, by - 8.5)]), -1, within=[pb])
    # patas delanteras recogidas bajo la cabeza
    _paw(cv, cx + 8.5, by - 1.2, 'bib', 2.2)
    # cabeza apoyada
    _head(cv, cx + 9.0, by - 7.0, eyes='sleep', s=0.86, tilt=1.0)
    # cola enroscada por delante
    tail = bez3((cx - 14.0, by - 4.0), (cx - 13.0, by + 0.4), (cx + 2.0, by + 0.4), (cx + 6.5, by - 1.2), 14)
    m, n = cv.stroke_n(tail, [max(0.9, 1.6 - 0.5 * i / 14) for i in range(15)])
    cv.put(m, 'fur2', mode='stroke', nrm=n, iline=True)
    return render(cv)


def walk(i):
    """Caminando de perfil (3/4): cuerpo largo, patas finas con el paso cruzado, cabeza al frente, cola arriba."""
    cv = Cv(PAL)
    cx = 28
    by = G
    bob = [0, -1, 0, -1][i]
    sw = [1, 0, -1, 0][i]
    # patas: x de la cadera / hombro, desplazamiento del pie, alto levantado
    legs = {
        'fr_far': (cx + 7.5, [-2.5, 0.0, 2.5, 0.5][i], [0, 0, 0, 2][i]),
        'bk_far': (cx - 7.0, [2.5, 0.0, -2.5, -0.5][i], [0, 2, 0, 0][i]),
        'fr_near': (cx + 9.0, [2.5, 0.5, -2.5, 0.0][i], [0, 2, 0, 0][i]),
        'bk_near': (cx - 5.5, [-2.5, -0.5, 2.5, 0.0][i], [0, 0, 0, 2][i]),
    }
    tail = bez3((cx - 10.0, by - 14.0 + bob), (cx - 15.0, by - 16.0 + bob), (cx - 17.0 + sw, by - 22.0 + bob),
                (cx - 14.5 + sw * 2, by - 27.0 + bob), 16)
    m, n = cv.stroke_n(tail, [max(0.9, 1.6 - 0.6 * k / 16) for k in range(17)])
    cv.put(m, 'fur2', mode='stroke', nrm=n)

    def leg(k, near):
        x, dx, lift = legs[k]
        top = (x, by - 10.0 + bob)
        foot = (x + dx, by - 1.4 - lift)
        mid = ((top[0] + foot[0]) / 2 + (0.6 if k.startswith('bk') else -0.3), (top[1] + foot[1]) / 2)
        lm, ln = cv.capsule_n(top, mid, 1.6, 1.25)
        lm2, ln2 = cv.capsule_n(mid, foot, 1.25, 1.1)
        nn = np.where(lm2[..., None] & ~lm[..., None], ln2, ln)
        mat = 'bib' if k == 'fr_near' else 'fur'
        p = cv.put(lm | lm2, mat, mode='stroke', nrm=nn, iline=near, bias=0.0 if near else -0.6)
        _paw(cv, foot[0] + 0.5, foot[1] + 0.3, 'bib' if k.startswith('fr') else 'fur', 1.5)
        return p
    leg('fr_far', False)
    leg('bk_far', False)
    # cuerpo: pecho más alto, cintura, cadera
    body = cv.ellipse(cx, by - 12.0 + bob, 11.0, 4.8) | cv.ellipse(cx + 6.5, by - 12.5 + bob, 5.2, 5.4) | \
        cv.ellipse(cx - 6.5, by - 12.8 + bob, 5.0, 5.0)
    pb = cv.put(body, 'fur', mode='top', band=0.22)
    cv.set_nrm(pb, cv.sphere_n(cx - 1.0, by - 15.0 + bob, 13.0, 7.5, k=0.85))
    cv.paint(cv.ellipse(cx + 5.5, by - 9.0 + bob, 5.5, 2.4) & cv.of(pb), 'bib', 3)
    for dx in (-7, -2, 3):
        cv.shade(cv.line([(cx + dx, by - 17.0 + bob), (cx + dx + 1, by - 14.5 + bob)]), -1, within=[pb])
    leg('fr_near', True)
    leg('bk_near', True)
    _head(cv, cx + 13.0, by - 19.5 + bob, s=0.92)
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
