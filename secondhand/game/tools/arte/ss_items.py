"""Secondhand Stars · objetos del banco: piezas (32x32, buenas y _bad), objetos cerrados (64x64), vista abierta del
banco (360x240, sin carcasa, 4 zócalos con las piezas puestas), cápsulas de chatarra (64x64) y items/manifest.json.

Mismo render HD-2D que los personajes (lienzo Cv + render del kit: planos de luz arriba a la izquierda, contorno
selectivo, sin píxeles sueltos). En la vista abierta las piezas se pegan a x2 EXACTO (64x64) dentro de cada zócalo:
el banco puede dibujar encima otra pieza (o su _bad) en el mismo rectángulo del manifest y calza píxel a píxel.
También sale <item>_open_empty.png (los zócalos vacíos) por si el banco prefiere dibujar todas las piezas él mismo.

Uso: python3 ss_items.py [--out DIR]   -> DIR/parts/*.png, DIR/items/*.png, DIR/items/manifest.json
"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from c64core import *
from c64core import _norm
from ss_bots import pal_of

MATS = {
    'dkmetal': ('#5a5660', 'metal'), 'steel': ('#a8acb6', 'metal'), 'brass': ('#d4a64a', 'metal'), 'gold': ('#e0b04a', 'metal'),
    'copper': ('#d27c42', 'metal'), 'cone': ('#4a464c', 'leather'), 'cap': ('#6a6670', 'metal'),
    'cream': ('#ece2c4', 'white'), 'cream2': ('#c8b890', 'cloth'), 'teal': '#3e8a86', 'teal2': '#2e6664', 'amber': '#e8a038',
    'red': ('#c84a36', 'cloth'), 'black': ('#2e2a2e', 'leather'), 'chip': ('#3a3640', 'leather'), 'label': ('#a8a4a0', 'cloth'),
    'servo': '#3e4a78', 'servo2': '#2c3458', 'glass': ('#5a78c8', 'gem'), 'glass2': ('#8a6ad0', 'gem'),
    'heat1': ('#7a5ab0', 'gem'), 'heat2': ('#d8a440', 'gem'), 'blade': ('#c0c4cc', 'metal'),
    'soot': ('#2a2222', 'flat'), 'burnt': ('#5a3424', 'cloth'), 'goo': ('#b8c040', 'gem'), 'wire_r': ('#c8402e', 'cloth'),
    'wire_k': ('#2e2a2e', 'leather'), 'wire_y': ('#e0b040', 'cloth'), 'crackl': ('#f0e6d0', 'flat'), 'hole': ('#1a1618', 'flat'),
    'pcb': '#2e5a4e', 'pcb2': '#3e7a64', 'trace': ('#c8a050', 'metal'), 'tray': ('#7a7680', 'metal'),
    'shell': '#4e9a92', 'shell2': '#e4d6b0', 'grille': ('#3a363a', 'leather'), 'dial': ('#f0b44a', 'gem'),
    'needle': ('#c8402e', 'flat'), 'paint': '#c4553a', 'paint2': ('#ece2c4', 'white'), 'screen': ('#e8a838', 'gem'),
    'screen2': ('#6a3a1a', 'flat'), 'plast': '#d8703a', 'plast2': '#a84e2a', 'rubber': ('#33302e', 'leather'),
    'pod': ('#9aa8ac', 'metal'), 'pod2': ('#6a7478', 'metal'), 'podband': '#c0603a', 'light': ('#ffd36a', 'flat'),
    'glow': ('#ffe8a0', 'flat'), 'smoke': ('#c8c0b4', 'white'), 'shadow': ('#2a2224', 'flat'), 'socket': ('#26222a', 'leather'),
    'clip': ('#b8bcc4', 'metal'), 'sticker': ('#e8dcc0', 'white'), 'stripe': ('#ece2c4', 'white'),
}


def canvas(w, h):
    pal, kinds = pal_of(MATS, accents=('amber', 'dial', 'screen', 'teal', 'light', 'heat1', 'heat2'))
    return Cv(pal, w=w, h=h, kinds=kinds)


def concave_n(cv, cx, cy, rx, ry, k=0.8):
    """Normales de una superficie cóncava (cono de parlante, interior de una tobera): al revés que una esfera."""
    n = cv.sphere_n(cx, cy, rx, ry, k=k)
    n = n.copy()
    n[..., 0] *= -1
    n[..., 1] *= -1
    return n


def hcyl_n(cv, cy, r):
    """Cilindro de eje horizontal: arriba a la luz, abajo en sombra."""
    ny = np.clip((cv.ys - cy) / max(r, 0.5), -1, 1) * 0.9
    return _norm(np.zeros_like(ny, dtype=np.float32), ny.astype(np.float32))


def crack(cv, pts, within=None):
    """Grieta: línea oscura con un borde claro arriba (se lee como una rajadura)."""
    m = cv.line(pts)
    cv.paint(m & (cv.pid > 0), 'hole', 2)
    hi = cv.line([(x - 0.0, y - 1.0) for x, y in pts]) & ~m
    cv.paint(hi & (cv.pid > 0), 'crackl', 2)
    for y, x in zip(*np.nonzero(m)):
        cv.dot(x, y, 'hole', 0)


def soot(cv, cx, cy, r, halo=1.5):
    """Mancha de quemado: negra en el centro, borde marrón."""
    cv.paint(cv.ellipse(cx, cy, r + halo, r + halo * 0.8) & (cv.pid > 0), 'burnt', 2)
    cv.paint(cv.ellipse(cx, cy, r, r * 0.85) & (cv.pid > 0), 'soot', 2)


def keep_all(cv):
    for p in cv.parts[1:]:
        p.keep = True


# ================================================================== piezas (32x32)

def p_speaker(bad=False):
    cv = canvas(32, 32)
    plate = cv.rect(3, 3, 28, 28) & ~(cv.ellipse(3, 3, 2, 2) | cv.ellipse(28, 3, 2, 2) | cv.ellipse(3, 28, 2, 2) | cv.ellipse(28, 28, 2, 2))
    plate = cv.ellipse(15.5, 15.5, 13.2, 13.2) | (cv.rect(4, 4, 27, 27) & ~cv.ellipse(15.5, 15.5, 17.5, 17.5) & plate)
    pp = cv.put(plate, 'dkmetal', mode='top', cast=1, iline=True)
    for (x, y) in ((6, 6), (25, 6), (6, 25), (25, 25)):
        cv.put(cv.ellipse(x, y, 1.6, 1.6), 'steel', mode='shine', iline=True)
    cv.put(cv.ellipse(15.5, 15.5, 11.6, 11.6), 'brass', mode='shine', cast=1, iline=True)
    cone = cv.ellipse(15.5, 15.5, 9.6, 9.6)
    pc = cv.put(cone, 'cone', mode='stroke', nrm=concave_n(cv, 15.5, 15.5, 10.5, 10.5))
    for r in (7.6, 5.6):
        ring = cv.ellipse(15.5, 15.5, r, r) & ~cv.ellipse(15.5, 15.5, r - 1, r - 1)
        cv.shade(ring, -1, within=[pc])
    capc = (15.5, 15.5) if not bad else (16.5, 16.5)
    pd = cv.put(cv.ellipse(capc[0], capc[1], 3.4, 3.4), 'cap', mode='stroke', nrm=cv.sphere_n(capc[0] - 0.8, capc[1] - 0.8, 4.0, 4.0))
    if bad:
        cv.shade(cv.ellipse(capc[0] + 0.5, capc[1] + 0.5, 2.0, 2.0), -2, within=[pd])
        crack(cv, [(9, 11), (11, 13), (12, 16), (15, 18), (17, 22), (20, 23)])
        # abolladura en el aro de bronce (arriba a la derecha)
        cv.erase(cv.ellipse(25.0, 7.6, 2.4, 2.0) & ~cv.ellipse(15.5, 15.5, 9.6, 9.6))
        cv.put(cv.ellipse(24.0, 8.6, 1.6, 1.4) & ~cv.ellipse(15.5, 15.5, 9.6, 9.6), 'dkmetal', mode='top', iline=True)
    return render(cv)


def p_tuner(bad=False):
    cv = canvas(32, 32)
    top = cv.poly([(5, 16), (25, 16), (27, 13), (7, 13)])
    front = cv.rect(5, 16, 26, 26)
    cv.put(front, 'teal', mode='cyl', cast=1, iline=True)
    cv.put(top, 'teal', mode='top', cast=1, iline=True)
    cv.paint(cv.rect(5, 23, 26, 26) & cv.of(*range(1, len(cv.parts))), 'teal2', 2)
    for x in (8, 23):
        cv.put(cv.ellipse(x, 20.5, 1.4, 1.4), 'brass', mode='shine', iline=True)
    cv.put(cv.rect(15, 9, 17, 14), 'steel', mode='cyl', iline=True)
    kx, ky = (16.0, 8.5) if not bad else (17.0, 9.0)
    side = cv.ellipse(kx, ky + 2.0, 8.0, 4.0)
    ps = cv.put(side, 'cream2', mode='cyl', cast=1, iline=True)
    for x in range(int(kx - 7), int(kx + 8), 2):
        cv.shade(cv.rect(x, int(ky + 2), x, int(ky + 5)), -1, within=[ps])
    tm = cv.ellipse(kx, ky, 8.0, 4.4)
    pt = cv.put(tm, 'cream', mode='top', cast=1, iline=True)
    for a in np.linspace(0, 2 * math.pi, 13)[:-1]:
        cv.dot(kx + math.cos(a) * 6.4, ky + math.sin(a) * 3.4, 'dkmetal', 1)
    if not bad:
        cv.put(cv.line([(kx, ky), (kx + 5.0, ky - 2.4)]), 'needle', mode='flat', outline=False)
        cv.put(cv.ellipse(kx, ky, 1.3, 1.0), 'dkmetal', mode='shine')
    else:
        # perilla partida: falta un trozo a la derecha y la aguja quebrada
        cv.erase(cv.poly([(kx + 2, ky - 5), (kx + 9, ky - 5), (kx + 9, ky + 7), (kx + 4, ky + 1)]))
        crack(cv, [(kx - 5, ky - 2), (kx - 2, ky), (kx + 2, ky - 1), (kx + 3, ky + 2)])
        cv.put(cv.line([(kx - 1, ky + 0.5), (kx + 1.5, ky - 0.5)]), 'needle', mode='flat', outline=False)
    return render(cv)


def p_cell(bad=False):
    cv = canvas(32, 32)
    if not bad:
        body = cv.rect(10, 7, 21, 26)
    else:
        body = cv.rect(10, 7, 21, 26) | cv.ellipse(15.5, 17.0, 7.6, 7.0)
    cv.put(cv.ellipse(15.5, 26.0, 5.6, 2.2), 'steel', mode='shine', iline=True)
    pb = cv.put(body, 'teal', mode='cyl', cast=1, iline=True)
    cv.paint(body & cv.rect(0, 15, 31, 17), 'amber', 2)
    cv.put(cv.ellipse(15.5, 7.0, 5.6, 2.2), 'steel', mode='shine', iline=True)
    cv.put(cv.rect(14, 3, 17, 6), 'steel', mode='shine', iline=True)
    for (x, y) in ((15, 9), (15, 10), (15, 11), (14, 10), (16, 10)):
        cv.dot(x, y, 'cream', 4)
    if bad:
        soot(cv, 15.5, 7.5, 3.4, 1.6)
        goo = cv.stroke([(19.5, 8.0), (21.6, 11.0), (21.4, 15.0), (21.0, 19.0)], 1.1, 0.8)
        g = cv.put(goo, 'goo', mode='shine', iline=True)
        crack(cv, [(12, 19), (14, 21), (13, 23), (15, 25)])
    return render(cv)


def p_chip(bad=False):
    cv = canvas(32, 32)
    pins = np.zeros((32, 32), bool)
    for y in (9, 12, 15, 18, 21):
        pins |= cv.rect(3, y, 5, y + 1) | cv.rect(26, y, 28, y + 1)
    if bad:
        pins &= ~(cv.rect(26, 12, 28, 13) | cv.rect(3, 18, 5, 19))
        pins |= cv.line([(26, 12), (29, 10)]) | cv.line([(5, 18), (2, 21)])
    cv.put(pins, 'gold', mode='shine', iline=True)
    cv.put(cv.rect(6, 23, 25, 25), 'black', mode='cyl', iline=True)
    pt = cv.put(cv.rect(6, 7, 25, 23), 'chip', mode='top', cast=1, iline=True)
    cv.put(cv.ellipse(9.0, 10.0, 1.2, 1.2), 'dkmetal', mode='shine')
    lb = cv.put(cv.rect(11, 13, 21, 18), 'label', mode='flat', iline=False)
    cv.paint(cv.rect(11, 16, 21, 16), 'teal', 2)
    if bad:
        soot(cv, 18.0, 14.0, 4.0, 2.0)
        crack(cv, [(8, 20), (11, 18), (13, 21), (16, 19)])
    return render(cv)


def p_servo(bad=False):
    cv = canvas(32, 32)
    for (x0, x1) in ((2, 6), (25, 29)):
        cv.put(cv.rect(x0, 15, x1, 17), 'servo2', mode='cyl', iline=True)
        cv.dot((x0 + x1) / 2, 16, 'hole', 0)
    cv.put(cv.rect(6, 14, 25, 26), 'servo', mode='cyl', cast=1, iline=True)
    cv.put(cv.poly([(6, 14), (25, 14), (27, 11), (8, 11)]), 'servo', mode='top', cast=1, iline=True)
    for (c, dy) in (('wire_r', 0), ('wire_k', 1.6), ('wire_y', 3.2)):
        cv.put(cv.line([(6, 21 + dy * 0.6), (3, 23 + dy), (1, 25 + dy)]), c, mode='flat')
    cv.put(cv.ellipse(10.0, 19.5, 2.0, 1.4), 'label', mode='flat')
    hx, hy = 19.0, 10.0
    arms = [((hx - 6, hy - 0.5), (hx + 6, hy + 0.5)), ((hx - 0.4, hy - 4.0), (hx + 0.4, hy + 3.0))]
    if bad:
        arms = [((hx - 6, hy - 0.5), (hx, hy)), ((hx - 0.4, hy - 4.0), (hx + 0.4, hy + 3.0))]
    for a, b in arms:
        cv.put(cv.capsule(a, b, 1.2), 'cream', mode='top', cast=1, iline=True)
    cv.put(cv.ellipse(hx, hy, 2.4, 1.8), 'cream', mode='shine', iline=True)
    cv.dot(hx, hy, 'dkmetal', 1)
    if bad:
        cv.put(cv.poly([(hx + 1.0, hy - 1.0), (hx + 3.6, hy + 0.4), (hx + 1.6, hy + 1.6)]), 'cream', mode='top', iline=True)
        soot(cv, 17.0, 19.0, 2.8, 1.6)
        crack(cv, [(11, 14), (12, 17), (11, 20), (13, 24)])
    return render(cv)


def p_lens(bad=False):
    cv = canvas(32, 32)
    cx, cy = 15.5, 16.0
    pr = cv.put(cv.ellipse(cx, cy, 12.4, 11.6), 'dkmetal', mode='shine', cast=1, iline=True)
    for a in np.linspace(0, 2 * math.pi, 17)[:-1]:
        cv.shade(cv.line([(cx + math.cos(a) * 10.6, cy + math.sin(a) * 9.9), (cx + math.cos(a) * 12.0, cy + math.sin(a) * 11.2)]),
                 -1, within=[pr])
    cv.put(cv.ellipse(cx, cy, 9.8, 9.2), 'brass', mode='shine', iline=True)
    pg = cv.put(cv.ellipse(cx, cy, 8.4, 7.9), 'glass', mode='shine')
    cv.set_nrm(pg, cv.sphere_n(cx - 2.0, cy - 2.0, 9.5, 9.0, k=0.9))
    cv.paint(cv.ellipse(cx + 2.6, cy + 2.4, 3.2, 2.6) & cv.of(pg), 'glass2', 2)
    for (x, y, l) in ((cx - 4, cy - 4, 4), (cx - 3, cy - 5, 4), (cx - 5, cy - 3, 3), (cx - 2, cy - 5, 3)):
        cv.dot(x, y, 'white', l)
    cv.dot(cx + 3, cy + 3, 'heat2', 4)
    if bad:
        o = (cx - 1.0, cy + 0.5)
        for a in (0.3, 1.5, 2.6, 3.7, 5.0):
            crack(cv, [o, (o[0] + math.cos(a) * 4.0, o[1] + math.sin(a) * 4.0), (o[0] + math.cos(a + 0.2) * 7.8, o[1] + math.sin(a + 0.2) * 7.4)])
    return render(cv)


def p_coil(bad=False):
    cv = canvas(32, 32)
    cy = 15.5
    for x, c in ((6.0, 'steel'), (25.5, 'steel')):
        pass
    cv.put(cv.ellipse(25.5, cy, 2.6, 7.4), 'steel', mode='shine', cast=1, iline=True)
    wind = cv.rect(7, 9, 25, 22)
    pw = cv.put(wind, 'copper', mode='stroke', nrm=hcyl_n(cv, cy, 7.0), cast=1, iline=True)
    for x in range(7, 26, 2):
        cv.shade(cv.rect(x, 9, x, 22), -1, within=[pw])
    cv.put(cv.ellipse(6.0, cy, 2.6, 7.4), 'steel', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(6.0, cy, 1.0, 2.2), 'dkmetal', mode='shine')
    leads = [[(24.0, 21.0), (26.0, 25.0), (29.0, 27.0)], [(21.0, 22.0), (22.0, 26.0), (24.0, 29.0)]]
    if bad:
        leads[1] = [(21.0, 22.0), (21.6, 24.6)]
    for pts in leads:
        cv.put(cv.stroke(pts, 0.7), 'copper', mode='flat', iline=True)
    if bad:
        cv.paint(cv.rect(12, 9, 19, 22) & cv.of(pw), 'burnt', 2)
        cv.paint(cv.rect(14, 11, 17, 21) & cv.of(pw), 'soot', 2)
        drip = cv.stroke([(15.0, 22.0), (15.4, 25.0)], 1.0, 0.7)
        cv.put(drip, 'soot', mode='flat', iline=True)
        cv.dot(21.6, 25, 'soot', 0)
    return render(cv)


def p_nozzle(bad=False):
    cv = canvas(32, 32)
    bell = cv.poly([(11, 6), (20, 6), (21, 10), (26, 18), (28, 25), (3, 25), (5, 18), (10, 10)])
    if bad:
        bell &= ~cv.ellipse(28.5, 19.0, 3.4, 3.0)
        bell |= cv.poly([(25, 17), (26.5, 20), (26, 25), (23, 22)])
    pb = cv.put(bell, 'steel', mode='cyl', cast=1, iline=True)
    cv.paint(bell & (cv.ys <= 10), 'heat1', 2)
    cv.paint(bell & (cv.ys >= 11) & (cv.ys <= 13), 'heat2', 2)
    ex = cv.ellipse(15.5, 25.0, 12.6, 3.6)
    cv.put(ex, 'steel', mode='shine', iline=True)
    cv.put(cv.ellipse(15.5, 25.0, 10.8, 2.4), 'hole', mode='flat')
    cv.put(cv.ellipse(15.5, 6.0, 5.6, 2.0), 'dkmetal', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(15.5, 5.6, 3.6, 1.2), 'hole', mode='flat')
    if bad:
        cv.shade(cv.ellipse(23.5, 19.5, 2.6, 2.4), -2, within=[pb])
        soot(cv, 9.0, 21.5, 2.6, 1.6)
        crack(cv, [(13, 14), (14, 17), (13, 20)])
    return render(cv)


def p_fan(bad=False):
    cv = canvas(32, 32)
    cx, cy = 15.5, 16.0
    ring = cv.ellipse(cx, cy, 13.2, 12.6) & ~cv.ellipse(cx, cy, 11.0, 10.4)
    if bad:
        ring &= ~cv.ellipse(cx + 9.8, cy - 8.4, 2.2, 2.0)
        ring |= cv.ellipse(cx + 8.4, cy - 7.4, 1.8, 1.6) & ~cv.ellipse(cx, cy, 10.0, 9.4)
    cv.put(ring, 'dkmetal', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(cx, cy, 11.0, 10.4), 'hole', mode='flat')
    n_bl = 7
    for k in range(n_bl):
        a = k * 2 * math.pi / n_bl + 0.3
        if bad and k == 2:
            continue           # pala arrancada
        L = 9.6 if not (bad and k in (4, 5)) else 6.6
        a2 = a + (0.0 if not (bad and k == 5) else 0.5)
        p0 = (cx + math.cos(a) * 2.6, cy + math.sin(a) * 2.5)
        p1 = (cx + math.cos(a2 + 0.25) * L, cy + math.sin(a2 + 0.25) * L * 0.95)
        p2 = (cx + math.cos(a2 + 0.62) * L * 0.9, cy + math.sin(a2 + 0.62) * L * 0.86)
        m = cv.poly([p0, p1, p2])
        pb = cv.put(m, 'blade', mode='shine', iline=True)
        cv.set_nrm(pb, cv.sphere_n(cx - 3, cy - 3, 14, 14, k=0.6))
    if bad:
        a = 2 * 2 * math.pi / n_bl + 0.3
        stub = cv.poly([(cx + math.cos(a) * 2.6, cy + math.sin(a) * 2.5), (cx + math.cos(a + 0.3) * 4.4, cy + math.sin(a + 0.3) * 4.2),
                        (cx + math.cos(a + 0.6) * 3.6, cy + math.sin(a + 0.6) * 3.4)])
        cv.put(stub, 'blade', mode='shine', iline=True)
    cv.put(cv.ellipse(cx, cy, 3.4, 3.2), 'steel', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(cx, cy, 1.2, 1.1), 'dkmetal', mode='shine')
    return render(cv)



# ================================================================== objetos cerrados (64x64)

def box3(cv, x0, y0, x1, y1, dx, dy, front, top, side, r=0):
    """Caja en vista oblicua: cara de frente, tapa arriba (corrida dx, dy) y costado derecho."""
    f = cv.rect(x0, y0, x1, y1)
    if r:
        for (cx, cy) in ((x0 + r, y1 - r), (x1 - r, y1 - r)):
            corner = cv.rect(cx - r if cx < (x0 + x1) / 2 else cx, cy, cx if cx < (x0 + x1) / 2 else cx + r, cy + r)
            f &= ~(corner & ~cv.ellipse(cx, cy, r + 0.3, r + 0.3))
    t = cv.poly([(x0, y0), (x1, y0), (x1 + dx, y0 + dy), (x0 + dx, y0 + dy)])
    s_ = cv.poly([(x1, y0), (x1 + dx, y0 + dy), (x1 + dx, y1 + dy), (x1, y1)])
    ps = cv.put(s_ & ~f, side, mode='flat', cast=0, iline=True)
    cv.parts[ps].bias = -0.9
    pt = cv.put(t & ~f, top, mode='flat', cast=0, iline=True)
    cv.parts[pt].bias = 0.8
    pf = cv.put(f, front, mode='cyl', cast=1, iline=True)
    return pf, pt, ps


def i_radio():
    cv = canvas(64, 64)
    # antena (detrás) y asa
    cv.put(cv.line([(49, 17), (58, 2)]), 'steel', mode='flat')
    cv.put(cv.ellipse(58.4, 2.0, 1.4, 1.4), 'steel', mode='shine', iline=True)
    cv.put(cv.stroke(bez((16, 18), (31, 3), (46, 18), 12), 1.3), 'steel', mode='shine', cast=1, iline=True)
    pf, pt, ps = box3(cv, 7, 21, 49, 52, 5, -5, 'shell', 'shell', 'shell')
    # panel crema del frente
    panel = cv.rect(10, 24, 46, 49)
    pp = cv.put(panel, 'shell2', mode='cyl', iline=True)
    # parlante: rejilla redonda con agujeros
    gc = (20.0, 37.0)
    g = cv.put(cv.ellipse(gc[0], gc[1], 8.6, 8.6), 'grille', mode='stroke', nrm=concave_n(cv, gc[0], gc[1], 9.5, 9.5), iline=True)
    cv.put(cv.ellipse(gc[0], gc[1], 9.6, 9.6) & ~cv.ellipse(gc[0], gc[1], 8.6, 8.6), 'steel', mode='shine', iline=True)
    for yy in range(30, 45, 2):
        for xx in range(13, 28, 2):
            if (xx - gc[0]) ** 2 + (yy - gc[1]) ** 2 < 60:
                cv.dot(xx, yy, 'hole', 0)
    # dial: ventanita ámbar con marcas y aguja roja
    dw = cv.rect(31, 28, 44, 35)
    cv.put(cv.rect(30, 27, 45, 36), 'dkmetal', mode='shine', iline=True)
    cv.put(dw, 'dial', mode='flat')
    for x in range(32, 44, 2):
        cv.dot(x, 29, 'screen2', 0)
        if x % 4 == 0:
            cv.dot(x, 30, 'screen2', 0)
    cv.put(cv.rect(37, 28, 37, 35), 'needle', mode='flat', outline=False)
    # perillas
    for x in (34.0, 41.5):
        cv.put(cv.ellipse(x, 42.0, 2.6, 2.6), 'black', mode='shine', cast=1, iline=True)
        cv.dot(x - 0.8, 41.0, 'white', 3)
    # tornillos y una calcomanía gastada
    for (x, y) in ((9, 23), (47, 23), (9, 50), (47, 50)):
        cv.dot(x, y, 'steel', 3)
    cv.put(cv.rect(29, 45, 35, 48), 'sticker', mode='flat', iline=False)
    cv.paint(cv.rect(29, 46, 35, 46), 'amber', 2)
    crack(cv, [(12, 26), (14, 27), (15, 26)])
    return render(cv)


def i_helperbot():
    cv = canvas(64, 64)
    # patitas
    for x in (25.0, 37.0):
        cv.put(cv.rect(int(x - 1), 50, int(x + 1), 55), 'dkmetal', mode='cyl', iline=True)
        cv.put(cv.ellipse(x + 0.6, 57.0, 4.0, 2.0), 'rubber', mode='cyl', iline=True)
    # bracitos
    cv.put(cv.capsule((17.0, 36.0), (12.0, 45.0), 1.6), 'steel', mode='shine', iline=True)
    cv.put(cv.ellipse(11.6, 46.0, 2.2, 2.2), 'dkmetal', mode='shine', iline=True)
    cv.put(cv.capsule((46.0, 36.0), (51.0, 44.0), 1.6), 'steel', mode='shine', iline=True)
    cv.put(cv.ellipse(51.6, 45.0, 2.2, 2.2), 'dkmetal', mode='shine', iline=True)
    # cuerpo
    body = cv.rect(17, 30, 46, 51) & ~(cv.rect(17, 48, 19, 51) & ~cv.ellipse(20, 48, 3.2, 3.2)) & ~(cv.rect(44, 48, 46, 51) & ~cv.ellipse(43, 48, 3.2, 3.2))
    pb = cv.put(body, 'plast', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(17, 46, 46, 51) & cv.of(pb), 'plast2', 2)
    cv.put(cv.rect(24, 36, 39, 44), 'plast2', mode='cyl', iline=True)
    for (x, c) in ((27, 'light'), (31, 'teal'), (35, 'red')):
        cv.put(cv.ellipse(x, 40.0, 1.3, 1.3), c, mode='shine')
    # cabeza: carcasa crema con pantalla ámbar inclinada (cara)
    hm = cv.rect(14, 8, 49, 31) & ~(cv.rect(14, 8, 16, 10) & ~cv.ellipse(17, 11, 3.2, 3.2)) & ~(cv.rect(47, 8, 49, 10) & ~cv.ellipse(46, 11, 3.2, 3.2))
    ph = cv.put(hm, 'shell2', mode='cyl', cast=1, iline=True)
    scr = cv.rect(18, 12, 45, 27)
    cv.put(cv.rect(17, 11, 46, 28), 'black', mode='shine', iline=True)
    psc = cv.put(scr, 'screen', mode='flat')
    for y in range(12, 28, 2):
        cv.paint(cv.rect(18, y, 45, y) & cv.of(psc), 'dial', 2)
    for (ex, ey) in ((25, 17), (37, 17)):
        cv.put(cv.rect(ex - 1, ey - 1, ex + 1, ey + 2), 'screen2', mode='flat', outline=False)
    cv.put(cv.line([(26, 23), (28, 24), (35, 24), (37, 23)]), 'screen2', mode='flat', outline=False)
    cv.dot(20, 13, 'white', 4)
    # antena con bombita
    cv.put(cv.line([(39, 8), (42, 2)]), 'steel', mode='flat')
    cv.put(cv.ellipse(42.5, 2.0, 1.6, 1.5), 'light', mode='flat')
    crack(cv, [(44, 34), (45, 37)])
    return render(cv)


def i_thruster():
    cv = canvas(64, 64)
    cy = 32.0
    # aleta arriba y soporte abajo
    cv.put(cv.poly([(22, 22), (34, 22), (30, 12), (25, 12)]), 'dkmetal', mode='top', cast=1, iline=True)
    cv.put(cv.poly([(28, 42), (38, 42), (40, 50), (26, 50)]), 'dkmetal', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(22, 50, 44, 52), 'dkmetal', mode='cyl', iline=True)
    # tobera atrás (izquierda)
    bell = cv.poly([(16, 25), (16, 39), (4, 45), (4, 19)])
    pb = cv.put(bell, 'steel', mode='stroke', nrm=hcyl_n(cv, cy, 12.0), cast=1, iline=True)
    cv.paint(bell & (cv.xs >= 13), 'heat1', 2)
    cv.paint(bell & (cv.xs >= 10) & (cv.xs <= 12), 'heat2', 2)
    cv.put(cv.ellipse(4.0, cy, 2.4, 13.0), 'hole', mode='flat')
    # cuerpo: cilindro horizontal pintado con franja
    body = cv.rect(15, 20, 50, 44)
    pc = cv.put(body, 'paint', mode='stroke', nrm=hcyl_n(cv, cy, 12.5), cast=1, iline=True)
    cv.paint(cv.rect(32, 20, 36, 44) & cv.of(pc), 'paint2', 2)
    for x in (19, 28, 41, 47):
        for y in (22, 42):
            cv.dot(x, y, 'dkmetal', 1)
    # toma de aire adelante (derecha): aro oscuro con aspas
    cv.put(cv.ellipse(51.0, cy, 4.6, 13.0), 'dkmetal', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(51.6, cy, 3.0, 10.6), 'hole', mode='flat')
    for k in range(5):
        y = cy - 8 + k * 4
        cv.put(cv.line([(50.5, y), (53.0, y + 2)]), 'blade', mode='flat', outline=False)
    cv.put(cv.ellipse(52.0, cy, 1.3, 2.2), 'steel', mode='shine')
    soot(cv, 18.0, 36.0, 2.2, 1.6)
    return render(cv)


def i_pod(opened=False):
    cv = canvas(64, 64)
    cx, cy = 32.0, 35.0
    if not opened:
        # aletas de apoyo
        for (a, b) in (((18, 46), (12, 58)), ((46, 46), (52, 58))):
            cv.put(cv.stroke([a, b], 1.6, 1.4), 'pod2', mode='shine', cast=1, iline=True)
        body = cv.ellipse(cx, cy, 17.0, 21.0)
        pb = cv.put(body, 'pod', mode='shine', cast=1, iline=True)
        cv.set_nrm(pb, cv.sphere_n(cx - 4, cy - 6, 19.0, 23.0, k=0.9))
        cv.paint(cv.rect(14, 32, 50, 35) & body, 'podband', 2)
        for y in (24, 46):
            cv.shade(cv.line([(cx - 15, y), (cx + 15, y)]) & body, -1, within=[pb])
        cv.shade(cv.line([(cx + 1, 15), (cx + 2, 32)]) & body, -1, within=[pb])
        cv.put(cv.ellipse(42.0, 33.5, 1.8, 1.6), 'light', mode='flat')
        cv.dot(41.6, 33.0, 'white', 4)
        # asa arriba y quemado de la reentrada
        cv.put(cv.stroke(bez((26, 15), (32, 7), (38, 15), 8), 1.1), 'pod2', mode='shine', iline=True)
        soot(cv, 22.0, 46.0, 5.0, 2.4)
        soot(cv, 18.0, 38.0, 2.4, 1.4)
        for (x, y) in ((24, 26), (40, 26), (24, 44), (40, 44)):
            cv.dot(x, y, 'pod2', 1)
        return render(cv)
    # abierta: la tapa de arriba volcada hacia atrás, adentro brilla y asoman piezas
    # tapa abisagrada atrás (a la izquierda), volcada: se ve como una media cúpula parada
    lid = cv.ellipse(18.0, 17.0, 8.0, 15.0) & (cv.xs <= 20)
    pl = cv.put(lid, 'pod', mode='shine', cast=1, iline=True)
    cv.set_nrm(pl, cv.sphere_n(13, 10, 10, 17))
    cv.put(cv.ellipse(20.0, 17.0, 2.6, 14.6), 'pod2', mode='shine', iline=True)
    cv.paint(cv.rect(10, 14, 20, 16) & lid, 'podband', 2)
    cv.put(cv.rect(16, 29, 20, 32), 'dkmetal', mode='shine', iline=True)
    cup = cv.ellipse(cx, cy + 2, 17.0, 19.0) & (cv.ys >= 30)
    pc = cv.put(cup, 'pod', mode='shine', cast=1, iline=True)
    cv.set_nrm(pc, cv.sphere_n(cx - 4, cy, 19.0, 21.0, k=0.9))
    cv.paint(cv.rect(14, 36, 50, 39) & cup, 'podband', 2)
    soot(cv, 22.0, 48.0, 4.6, 2.2)
    rimm = cv.ellipse(cx, 30.5, 16.4, 4.6)
    cv.put(rimm, 'pod2', mode='shine', iline=True)
    inner = cv.ellipse(cx, 30.5, 14.4, 3.4)
    cv.put(inner, 'glow', mode='flat', outline=False)
    # piezas asomando: un engranaje, la punta de un chip y una celda
    gm = cv.ellipse(25.0, 27.0, 4.0, 4.0)
    for k in range(8):
        a = k * math.pi / 4
        gm |= cv.ellipse(25.0 + math.cos(a) * 4.4, 27.0 + math.sin(a) * 4.4, 1.0, 1.0)
    gm &= ~cv.ellipse(25.0, 27.0, 1.4, 1.4)
    cv.put(gm & (cv.ys <= 30), 'brass', mode='shine', iline=True)
    cv.put(cv.rect(33, 23, 38, 30), 'teal', mode='cyl', iline=True)
    cv.paint(cv.rect(33, 26, 38, 27), 'amber', 2)
    cv.put(cv.rect(40, 26, 44, 30), 'chip', mode='top', iline=True)
    for x in (40, 42, 44):
        cv.dot(x, 25, 'gold', 3)
    # bocanada de vapor
    for (x, y, r) in ((40.0, 19.0, 3.0), (44.0, 13.0, 2.4), (42.0, 8.0, 1.8)):
        q = cv.put(cv.ellipse(x, y, r, r * 0.9), 'smoke', mode='soft', iline=False)
    return render(cv)


ITEMS = {'radio': i_radio, 'helperbot': i_helperbot, 'thruster': i_thruster}


# ================================================================== vista abierta del banco (180x120 -> x2 = 360x240)

DIGITS = {'1': ["010", "110", "010", "010", "111"], '2': ["110", "001", "010", "100", "111"],
          '3': ["110", "001", "010", "001", "110"], '4': ["101", "101", "111", "001", "001"]}

# zócalos (en píxeles de 180x120; el manifest los da x2). Orden de piezas = el del brief.
OPEN = {
    'radio': [('s1', 'speaker', (20, 42)), ('s2', 'tuner', (126, 18)), ('s3', 'cell', (126, 72)), ('s4', 'chip', (72, 56))],
    'helperbot': [('s1', 'servo', (74, 86)), ('s2', 'chip', (40, 54)), ('s3', 'lens', (74, 10)), ('s4', 'cell', (108, 54))],
    'thruster': [('s1', 'coil', (74, 14)), ('s2', 'nozzle', (8, 44)), ('s3', 'fan', (140, 44)), ('s4', 'cell', (74, 78))],
}


def digit(cv, ch, x, y, mat='stripe'):
    for j, row in enumerate(DIGITS[ch]):
        for i, c in enumerate(row):
            if c == '1':
                cv.dot(x + i, y + j, mat, 3)


# --- SS MERGE: el banco (BENCH) ya dibuja su propia insignia 1-4 en cada zócalo (con la tecla y el estado), así que
# los números pintados en el arte salían dos veces: ahora van apagados (NUMBERS = True los vuelve a pintar).
NUMBERS = False


def socket(cv, pos, n):
    """Bahía del zócalo: marco de metal, fondo oscuro hundido, cuatro grampas y los contactos; número pintado."""
    x, y = pos
    frame = cv.rect(x - 3, y - 3, x + 34, y + 34)
    cv.put(frame, 'tray', mode='top', cast=1, iline=True)
    cv.put(cv.rect(x - 1, y - 1, x + 32, y + 32), 'socket', mode='flat', iline=False)
    for (cx_, cy_) in ((x - 2, y - 2), (x + 33, y - 2), (x - 2, y + 33), (x + 33, y + 33)):
        cv.put(cv.rect(int(cx_ - 1), int(cy_ - 1), int(cx_ + 1), int(cy_ + 1)), 'clip', mode='shine', iline=True)
    for k in range(4):
        cv.dot(x + 8 + k * 5, y + 30, 'gold', 3)
    if NUMBERS:
        digit(cv, str(n), x - 2, y + 36 if y + 41 < cv.h else y - 9)


def wire(cv, pts, mat, r=0.8):
    cv.put(cv.stroke(bez(*pts, 14) if len(pts) == 3 else pts, r), mat, mode='shine', iline=True, cast=1)


def pcb_detail(cv, area, seed=1):
    """Pistas doradas y componentes chicos sobre la placa (capacitores, resistencias)."""
    x0, y0, x1, y1 = area
    rng = np.random.RandomState(seed)
    for k in range(9):
        ya = rng.randint(y0 + 3, y1 - 3)
        xa = rng.randint(x0 + 3, x1 - 20)
        xb = xa + rng.randint(8, 22)
        yb = ya + rng.choice([-4, 0, 4])
        cv.paint(cv.line([(xa, ya), (xb - 3, ya), (xb, yb)]) & (cv.pid > 0), 'trace', 2)
    for k in range(5):
        cx_, cy_ = rng.randint(x0 + 4, x1 - 4), rng.randint(y0 + 4, y1 - 4)
        if rng.rand() < 0.5:
            cv.put(cv.rect(cx_, cy_, cx_ + 2, cy_ + 3), rng.choice(['teal', 'amber', 'steel']), mode='cyl', iline=True)
        else:
            cv.put(cv.rect(cx_, cy_, cx_ + 4, cy_ + 1), 'label', mode='cyl', iline=True)
            cv.dot(cx_ + 1, cy_, 'red', 2)


def open_radio(cv):
    case = cv.rect(3, 4, 176, 116) & ~(cv.rect(3, 4, 6, 7) & ~cv.ellipse(7, 8, 4, 4)) & ~(cv.rect(173, 4, 176, 7) & ~cv.ellipse(172, 8, 4, 4))
    cv.put(case, 'shell', mode='top', cast=1, iline=True)
    cv.put(cv.rect(9, 10, 170, 110), 'tray', mode='flat', iline=True)
    cv.put(cv.rect(12, 13, 167, 107), 'pcb', mode='flat', iline=True)
    pcb_detail(cv, (12, 13, 167, 107), 3)
    for (x, y) in ((6, 7), (173, 7), (6, 113), (173, 113)):
        cv.put(cv.ellipse(x, y, 1.6, 1.6), 'steel', mode='shine', iline=True)
    # transformador y capacitores grandes
    cv.put(cv.rect(84, 18, 104, 34), 'dkmetal', mode='top', cast=1, iline=True)
    pw = cv.put(cv.rect(87, 20, 101, 32), 'copper', mode='stroke', nrm=hcyl_n(cv, 26.0, 6.0), iline=True)
    for x in range(87, 102, 2):
        cv.shade(cv.rect(x, 20, x, 32), -1, within=[pw])
    for x in (110, 116):
        cv.put(cv.rect(x, 92, x + 4, 102), 'teal2', mode='cyl', cast=1, iline=True)
        cv.put(cv.ellipse(x + 2, 92, 2.2, 1.0), 'steel', mode='shine')
    wire(cv, [(52, 58), (66, 40), (126, 32)], 'wire_r')
    wire(cv, [(52, 66), (90, 86), (126, 88)], 'wire_k')
    wire(cv, [(104, 72), (116, 60), (142, 52)], 'wire_y')
    cv.put(cv.rect(140, 106, 166, 112), 'sticker', mode='flat')
    cv.paint(cv.line([(142, 109), (162, 109)]) & (cv.pid > 0), 'needle', 2)


def open_helperbot(cv):
    # brazos
    for (a, b, c) in (((38, 66), (20, 80), (12, 96)), ((142, 66), (160, 80), (168, 96))):
        cv.put(cv.stroke([a, b], 2.4), 'steel', mode='shine', cast=1, iline=True)
        cv.put(cv.stroke([b, c], 2.2), 'steel', mode='shine', cast=1, iline=True)
        cv.put(cv.ellipse(b[0], b[1], 3.2, 3.2), 'dkmetal', mode='shine', iline=True)
        cv.put(cv.ellipse(c[0], c[1] + 2, 4.0, 3.6), 'dkmetal', mode='shine', iline=True)
    # cabeza (carcasa crema sin la pantalla)
    head = cv.rect(58, 2, 122, 50)
    cv.put(head, 'shell2', mode='top', cast=1, iline=True)
    cv.put(cv.rect(63, 6, 117, 46), 'socket', mode='flat', iline=True)
    cv.put(cv.rect(86, 50, 94, 56), 'dkmetal', mode='cyl', iline=True)
    cv.put(cv.line([(110, 2), (116, -6)]), 'steel', mode='flat')
    # cuerpo (cáscara naranja abierta)
    body = cv.rect(32, 50, 148, 119)
    cv.put(body, 'plast', mode='top', cast=1, iline=True)
    cv.put(cv.rect(37, 55, 143, 119), 'tray', mode='flat', iline=True)
    cv.put(cv.rect(39, 57, 141, 119), 'pcb', mode='flat', iline=True)
    pcb_detail(cv, (39, 57, 141, 117), 5)
    wire(cv, [(72, 70), (90, 60), (108, 70)], 'wire_y')
    wire(cv, [(90, 52), (88, 70), (90, 86)], 'wire_r')
    wire(cv, [(56, 88), (66, 104), (74, 104)], 'wire_k')
    for (x, y) in ((61, 4), (119, 4), (35, 53), (145, 53)):
        cv.put(cv.ellipse(x, y, 1.5, 1.5), 'steel', mode='shine', iline=True)


def open_thruster(cv):
    # cámara de combustión: cilindro horizontal de punta a punta (con tinte de calor del lado de la tobera)
    ch = cv.rect(30, 40, 150, 80)
    pc = cv.put(ch, 'steel', mode='stroke', nrm=hcyl_n(cv, 60.0, 20.0), cast=1, iline=True)
    cv.paint(ch & (cv.xs <= 52), 'heat1', 2)
    cv.paint(ch & (cv.xs >= 53) & (cv.xs <= 60), 'heat2', 2)
    for x in range(64, 150, 12):
        cv.shade(cv.rect(x, 40, x, 80), -1, within=[pc])
        cv.shade(cv.rect(x + 1, 40, x + 1, 80), +1, within=[pc])
    # bastidor: costillas y largueros del motor sin la carcasa
    for y in (34, 86):
        cv.put(cv.rect(40, y, 140, y + 3), 'dkmetal', mode='shine', cast=1, iline=True)
    for x in (44, 70, 110, 136):
        cv.put(cv.rect(x, 30, x + 3, 93), 'tray', mode='shine', cast=1, iline=True)
    # cañerías de combustible y cables
    wire(cv, [(40, 60), (60, 44), (74, 40)], 'copper', 1.3)
    wire(cv, [(106, 40), (124, 46), (140, 60)], 'copper', 1.3)
    wire(cv, [(40, 66), (60, 82), (74, 90)], 'wire_r')
    wire(cv, [(106, 92), (124, 82), (140, 66)], 'wire_k')
    wire(cv, [(90, 46), (92, 62), (90, 78)], 'wire_y')
    # escudo térmico detrás de la tobera y la carcasa sacada (un trozo pintado apoyado abajo)
    cv.put(cv.rect(4, 38, 8, 82), 'heat1', mode='cyl', iline=True)
    shell = cv.poly([(118, 104), (176, 98), (178, 116), (120, 119)])
    cv.put(shell, 'paint', mode='top', cast=1, iline=True)
    cv.paint(cv.poly([(140, 102), (148, 101), (150, 117), (142, 118)]) & (cv.pid > 0), 'paint2', 2)
    for (x, y) in ((124, 108), (170, 103)):
        cv.dot(x, y, 'steel', 3)
    soot(cv, 30.0, 60.0, 3.0, 2.0)


OPEN_DRAW = {'radio': open_radio, 'helperbot': open_helperbot, 'thruster': open_thruster}


def build_open(out, parts):
    """<item>_open.png (360x240, con las piezas puestas), <item>_open_empty.png (zócalos vacíos) y manifest.json."""
    manifest = {}
    for item, slots in OPEN.items():
        cv = canvas(180, 120)
        OPEN_DRAW[item](cv)
        for n, (sid, part, pos) in enumerate(slots, 1):
            socket(cv, pos, n)
        base = render(cv)
        empty = Image.fromarray(base, 'RGBA')
        full = empty.copy()
        for sid, part, pos in slots:
            full.alpha_composite(Image.fromarray(parts[part][0], 'RGBA'), pos)
        for im, suf in ((full, 'open'), (empty, 'open_empty')):
            im.resize((360, 240), Image.NEAREST).save(os.path.join(out, 'items', f'{item}_{suf}.png'))
        manifest[item] = {'open_size': [360, 240], 'part_scale': 2,
                          'slots': [{'slot': sid, 'part': part, 'pos': [pos[0] * 2, pos[1] * 2], 'size': [64, 64]}
                                    for sid, part, pos in slots]}
    with open(os.path.join(out, 'items', 'manifest.json'), 'w') as f:
        json.dump(manifest, f, indent=1)
    return manifest

PARTS = {'speaker': p_speaker, 'tuner': p_tuner, 'cell': p_cell, 'chip': p_chip, 'servo': p_servo, 'lens': p_lens,
         'coil': p_coil, 'nozzle': p_nozzle, 'fan': p_fan}


def build_parts(out):
    os.makedirs(os.path.join(out, 'parts'), exist_ok=True)
    res = {}
    for name, fn in PARTS.items():
        good, bad = fn(False), fn(True)
        Image.fromarray(good, 'RGBA').save(os.path.join(out, 'parts', f'{name}.png'))
        Image.fromarray(bad, 'RGBA').save(os.path.join(out, 'parts', f'{name}_bad.png'))
        res[name] = (good, bad)
    return res


if __name__ == '__main__':
    args = sys.argv[1:]
    out = './out'
    if '--out' in args:
        out = args[args.index('--out') + 1]
    parts = build_parts(out)
    os.makedirs(os.path.join(out, 'items'), exist_ok=True)
    for name, fn in ITEMS.items():
        Image.fromarray(fn(), 'RGBA').save(os.path.join(out, 'items', f'{name}_closed.png'))
    Image.fromarray(i_pod(False), 'RGBA').save(os.path.join(out, 'items', 'pod_closed.png'))
    Image.fromarray(i_pod(True), 'RGBA').save(os.path.join(out, 'items', 'pod_open.png'))
    if 'build_open' in globals():
        build_open(out, parts)
    print('ok parts + items')
