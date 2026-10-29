"""Secondhand Stars · piezas nuevas para el kit de personajes del Caldero (herramientas, ropa de taller y rasgos
alienígenas). Cada función tiene la firma de las piezas del kit: fn(cv, B, sp, pose, **kw) o, si va en una mano,
fn(cv, B, sp, side, pose, **kw). Se usan en las fichas de ss_chars.py ('over', 'head', 'back', 'front', 'near'...)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import math
import numpy as np
from c64core import *
from c64core import _norm
from c64body import *
from c64parts import *
from c64hair import *
from c64acc import *
from c64hat import *


# ================================================================== piezas nuevas (herramientas y ropa de taller)


def wrench(cv, B, sp, side, pose, mat='steel'):
    """Llave inglesa colgando de la mano: mango hacia abajo y la boca abierta abajo."""
    g = B.arm[side]['grip']
    x, y = g[0] + 0.3, g[1]
    sh = cv.capsule((x, y - 1.5), (x - 0.8, y + 9.0), 0.85)
    p = cv.put(sh, mat, mode='shine', iline=True)
    jx, jy = x - 1.0, y + 10.6
    jaw = cv.ellipse(jx, jy, 2.6, 2.1) & ~cv.ellipse(jx + 0.5, jy + 1.8, 1.0, 1.4)
    cv.put(jaw, mat, mode='shine', iline=True)
    return p


def tool_belt(cv, B, sp, pose, mat='belt', pouch_mat='pouch', buckle='brass'):
    """Cinturón de herramientas: cinto, dos bolsillos y un destornillador asomando."""
    p = belt(cv, B, sp, pose, mat=mat, buckle=buckle, h=2)
    y = B.y_w + 3.0
    for (dx, w) in ((-B.ww * 0.42, 3.4), (B.ww * 0.30, 2.6)):
        bx = B.cx + dx
        m = cv.rect(int(bx - 1), int(y), int(bx - 1 + w), int(y + 3))
        cv.put(m, pouch_mat, mode='cyl', iline=True, cast=1)
        cv.put(cv.rect(int(bx - 1), int(y), int(bx - 1 + w), int(y)), pouch_mat, mode='top', iline=True)
    # mango de destornillador en el bolsillo cercano
    bx = B.cx - B.ww * 0.42
    cv.put(cv.rect(int(bx), int(y - 2), int(bx + 1), int(y - 1)), 'handle', mode='shine', iline=True)
    return p


def goggles_up(cv, B, sp, pose, mat='brass', lens='lens', strap='strap'):
    """Antiparras subidas sobre el pelo (arriba de la frente), con su correa alrededor de la cabeza."""
    st = cv.poly([hp(B, -1.2, 2.2), hp(B, HW + 0.6, 0.6), hp(B, HW + 0.6, 2.1), hp(B, -1.2, 3.7)])
    cv.put(st, strap, mode='cyl', cast=1)
    for (x, y, r) in ((8.2, 1.6, 2.5), (13.6, 1.0, 2.2)):
        c = hp(B, x, y)
        cv.put(cv.ellipse(c[0], c[1], r, r * 0.9), mat, mode='shine', cast=1, iline=True)
        cv.put(cv.ellipse(c[0], c[1], r - 1.0, r * 0.9 - 1.0), lens, mode='shine')
        cv.dot(c[0] - 0.6, c[1] - 0.6, 'white', 4)


def visor_up(cv, B, sp, pose, mat='visor', glass='vglass', pivot='steel', band='strap'):
    """Visor de soldar levantado: escudo grande y anguloso echado hacia atrás sobre la coronilla (la cara del visor
    mira arriba), con la ventanilla oscura bien visible, la cinta en la frente y el pivote en la sien."""
    # cinta de la cabeza (por encima de la frente)
    cv.put(cv.poly([hp(B, -0.8, 3.2), hp(B, HW + 0.4, 1.6), hp(B, HW + 0.4, 3.0), hp(B, -0.8, 4.6)]), band, mode='cyl', cast=1)
    poly = [hp(B, -2.6, 2.6), hp(B, -1.0, -3.6), hp(B, 5.0, -7.4), hp(B, 15.0, -7.6), hp(B, 20.6, -4.0), hp(B, 21.0, 0.4),
            hp(B, 17.0, 0.0), hp(B, 9.0, -0.4), hp(B, 2.0, 1.8), hp(B, -0.6, 4.0)]
    m = cv.poly(poly)
    p = cv.put(m, mat, mode='top', cast=2, iline=True)
    c = hp(B, 9.0, -3.0)
    cv.set_nrm(p, cv.sphere_n(c[0], c[1], 14.0, 8.0, k=0.8))
    # borde de abajo (el canto del escudo) más oscuro
    edge = m & ~np.roll(m, -1, axis=0)
    cv.shade(edge, -1, within=[p])
    # ventanilla oscura con marco
    w = cv.poly([hp(B, 5.0, -5.6), hp(B, 14.6, -5.6), hp(B, 15.2, -2.6), hp(B, 5.4, -2.4)])
    cv.put(cv.poly([hp(B, 4.0, -6.4), hp(B, 15.6, -6.4), hp(B, 16.2, -1.8), hp(B, 4.4, -1.6)]) & m, 'vframe', mode='shine', iline=True)
    cv.put(w & m, glass, mode='shine', iline=True)
    g = hp(B, 6.4, -4.8)
    cv.dot(g[0], g[1], 'white', 4)
    cv.dot(g[0] + 1, g[1], 'white', 3)
    # pivote en la sien
    c = hp(B, -0.2, 4.4)
    cv.put(cv.ellipse(c[0], c[1], 1.7, 1.7), pivot, mode='shine', iline=True)
    return p


def keyring(cv, B, sp, side, pose, mat='brass', tag='keytag'):
    """Llavero de la nave colgando de la mano: aro, dos llaves y una placa de color."""
    g = B.arm[side]['grip']
    x, y = g[0] + 0.5, g[1] + 1.5
    ring = cv.ellipse(x, y + 1.5, 1.6, 1.6) & ~cv.ellipse(x, y + 1.5, 0.6, 0.6)
    cv.put(ring, mat, mode='shine', iline=True)
    cv.put(cv.capsule((x - 0.8, y + 3.0), (x - 1.6, y + 6.5), 0.6), 'steel', mode='shine', iline=True)
    cv.put(cv.rect(int(x + 0.5), int(y + 3), int(x + 2.5), int(y + 6)), tag, mode='cyl', iline=True)
    cv.dot(x + 1.5, y + 4, 'white', 3)


def flight_collar(cv, B, sp, pose, mat='shearling'):
    """Cuello de borrego de la chaqueta de vuelo: grueso, por encima de los hombros, abierto en V delante."""
    cx = B.cx + 0.5
    y = B.y_sh
    m = cv.ellipse(cx, y + 0.5, B.sw / 2 + 1.0, 3.0)
    m &= ~cv.poly([(cx - 0.5, y - 1.0), (cx + 3.5, y - 1.0), (cx + 1.6, y + 4.5)])
    p = cv.put(m, mat, mode='stroke', nrm=cv.sphere_n(cx - 1, y - 0.5, B.sw / 2 + 2.5, 4.5), cast=1, iline=True)
    return p


def patch(cv, B, sp, pose, mat='patch', x=-3.6, y=4.5):
    """Parche redondo en el pecho (insignia de taller / de piloto)."""
    c = (B.cx_sh + x, B.y_sh + y)
    cv.put(cv.ellipse(c[0], c[1], 1.6, 1.5), mat, mode='flat', iline=True)



def apron2(cv, B, sp, pose, y_hem=None, **kw):
    """El delantal del kit con el bajo en palabras ('thigh' = medio muslo)."""
    if y_hem == 'thigh':
        y_hem = B.hip_y + B.d['leg'] * 0.30
    return apron(cv, B, sp, pose, y_hem=y_hem, **kw)


def high_ponytail(cv, B, sp, pose, tie='tie', length=15.0, width=2.6):
    """Coleta alta que sale de la nuca hacia atrás (a la izquierda) y cae: se ve en 3/4 (la del kit queda tapada)."""
    lag, sway = pose.lag, pose.sway
    s = hs_(B)
    root = H(B, 2.6, 2.4)
    pts = bez3(root, H(B, -3.5, 1.0), H(B, -6.2 + sway, 6.0 + length * 0.3), H(B, -4.6 + sway * 1.6, 6.0 + length + lag), 14)
    radii = taper(len(pts), width * s, 'leaf', belly=0.32)
    p = hlock(cv, pts, radii, base=3, shine_at=0.10, shine_len=3.5, cast=0, fade=(B.y_sh + 2,))
    c = H(B, 0.6, 2.2)
    cv.put(cv.ellipse(c[0], c[1], 1.5, 1.8), tie, mode='shine', iline=True)
    return p


def bomber(cv, B, sp, pose, mat='jacket', rib='jacket2', inner='shirt', zip_='steel'):
    """Chaqueta de vuelo corta (hasta la cadera), abierta en una franja delante, con pretina de punto abajo."""
    tor = torso_mask(cv, B, y_bot=B.hip_y + 1, pad=0.9)
    # bajo un poco abolsado
    tor |= cv.poly([(B.cx - B.hw / 2 - 1.2, B.hip_y - 2), (B.cx + B.hw / 2 + 0.6, B.hip_y - 2), (B.cx + B.hw / 2 + 0.2, B.hip_y + 1.5),
                    (B.cx - B.hw / 2 - 1.0, B.hip_y + 1.5)])
    fx = B.cx_sh + B.ww * 0.22
    gap = cv.poly([(fx - 0.6, B.y_sh + 1.0), (fx + 1.6, B.y_sh + 1.0), (fx + 1.4, B.hip_y + 3), (fx - 0.4, B.hip_y + 3)])
    p = cv.put(tor & ~gap, mat, mode='cyl', iline=True, cast=1)
    yb = B.hip_y
    band = (tor & ~gap) & (cv.ys >= int(yb)) & (cv.ys <= int(yb) + 1)
    cv.put(band, rib, mode='cyl', iline=True)
    # costuras: un pliegue en el costado cercano y bolsillo
    cv.shade(cv.line([(B.cx - B.ww * 0.30, B.y_w - 3), (B.cx - B.ww * 0.34, B.hip_y - 1)]), -1, within=[p])
    cv.put(cv.rect(int(B.cx - B.ww * 0.30), int(B.y_w - 1), int(B.cx - B.ww * 0.30) + 2, int(B.y_w - 1)), rib, mode='flat')
    return p




# ================================================================== cabezas y especies alienígenas

def reg_head(name, w, h, inside, anchors):
    """Registra una plantilla de cabeza en el kit (HEADS) a partir de una función inside(x, y) -> bool.
    anchors: {1: ojo cercano, 2: ojo lejano, 3: boca, 6: oreja, 7: nariz} en coordenadas de la plantilla."""
    rows = [''.join('K' if inside(x + 0.5, y + 0.5) else '.' for x in range(w)) for y in range(h)]
    for k, (ax, ay) in anchors.items():
        r = list(rows[ay])
        r[ax] = 'K'
        rows[ay] = ''.join(r)
    HEADS[name] = dict(art='\n'.join(rows), w=w, h=h, a=dict(anchors))


def _sup(x, y, cx, cy, rx, ry, e=2.0):
    return abs((x - cx) / rx) ** e + abs((y - cy) / ry) ** e <= 1.0


# Hornback (Gorrum): cráneo ancho de tope plano, quijada ancha (el hocico va aparte)
reg_head('hornback', 22, 17, lambda x, y: _sup(x, y, 10.8, 8.6, 11.0, 8.6, 2.7),
         {1: (9, 8), 2: (15, 8), 3: (15, 13), 6: (2, 8), 7: (18, 11)})
# Quill (Zib): cabeza alargada, mentón angosto hacia la derecha
reg_head('quill', 15, 18, lambda x, y: _sup(x, y, 7.4 + max(0, y - 10) * 0.18, 9.0, 7.3 - max(0, y - 9) * 0.32, 9.0, 2.2),
         {1: (7, 9), 2: (11, 9), 3: (10, 14), 6: (2, 9), 7: (12, 11)})
# Glimmerfolk (Oona): domo de medusa, borde de abajo un poco abierto
reg_head('dome', 20, 19, lambda x, y: (_sup(x, y, 10.0, 10.0, 9.9, 10.0, 2.1) and y < 17.2) or (y >= 15 and y < 18 and 1.2 < x < 18.8),
         {1: (8, 13), 2: (13, 13), 3: (12, 16), 6: (2, 12), 7: (14, 14)})
# Burrower (Pipip): cabeza redonda (el hocico va aparte)
reg_head('mole', 16, 15, lambda x, y: _sup(x, y, 8.0, 7.6, 8.0, 7.5, 2.0),
         {1: (8, 8), 2: (12, 8), 3: (12, 12), 6: (2, 8), 7: (14, 10)})
# Dune Raker (Raker): cabeza ancha y chata de salamandra
reg_head('axolotl', 22, 14, lambda x, y: _sup(x, y, 10.8, 7.4, 10.9, 7.0, 2.4),
         {1: (8, 6), 2: (17, 6), 3: (15, 10), 6: (3, 7), 7: (20, 8)})

SPECIES['hornback'] = dict(h=72, head='hornback', neck=0, sw=22, ww=20, hw=19, leg=19, waist=0.64, ua=8.5, fa=8.0, ar=2.9,
                           tr=3.1, sr=2.7, foot=9, hipx=3.8, chest=2)
SPECIES['quill'] = dict(h=66, head='quill', neck=2, sw=12, ww=8.5, hw=10, leg=25, waist=0.70, ua=8.0, fa=7.5, ar=1.45,
                        tr=1.7, sr=1.4, foot=7, hipx=2.2, chest=0)
SPECIES['glimmer'] = dict(h=63, head='dome', neck=2, sw=12, ww=10, hw=12, leg=19, waist=0.66, ua=7.0, fa=6.5, ar=1.6,
                          tr=1.8, sr=1.6, foot=6, hipx=2.4, chest=0)
SPECIES['burrower'] = dict(h=40, head='mole', neck=0, sw=13, ww=13, hw=13, leg=9, waist=0.62, ua=5.0, fa=4.6, ar=1.8,
                           tr=2.0, sr=1.8, foot=5, hipx=2.2, chest=1)
SPECIES['raker'] = dict(h=55, head='axolotl', neck=0, sw=13, ww=11, hw=12, leg=16, waist=0.68, ua=6.5, fa=6.0, ar=1.7,
                        tr=2.0, sr=1.8, foot=7, hipx=2.4, chest=0)

# ojos de cuenta (salamandra): 2x2 oscuro con un píxel claro
EYES['bead'] = (["___", "_wp", "_pp", "___"], ["___", "wp_", "pp_"])
# ojos chicos y hundidos (bajo una ceja pesada)
EYES['deep'] = (["KKK", "_wp", "_pp", "___"], ["KKK", "wp_", "pq_"])


def P(B, x, y):
    """Punto en píxeles relativo a la esquina de la cabeza (para cabezas propias, sin escalar)."""
    return (B.hx + x, B.hy + y)


def _horn(cv, root, c1, c2, tip, r0, r1, mat='horn', bias=0.0, rings=True):
    pts = bez3(root, c1, c2, tip, 16)
    m, n = cv.stroke_n(pts, list(np.linspace(r0, r1, len(pts))))
    p = cv.put(m, mat, mode='stroke', nrm=n, cast=1, iline=True, bias=bias)
    if rings:
        for t in (3, 6, 9):
            a, b = pts[t], pts[t + 1]
            dx, dy = b[0] - a[0], b[1] - a[1]
            l = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / l, dx / l
            r = r0 + (r1 - r0) * t / 16.0 + 0.6
            cv.shade(cv.line([(a[0] - nx * r, a[1] - ny * r), (a[0] + nx * r, a[1] + ny * r)]), -1, within=[p])
    return p


# ---------------- Gorrum (Hornback)

def _curl(cv, pts_list, r0, r1, mat, bias=0.0, ring_at=None, ring_mat='gold'):
    """Cuerno en espiral: varios tramos de Bézier encadenados; anillo de oro cerca de la punta."""
    pts = []
    for seg in pts_list:
        q = bez3(*seg, 12)
        pts += q if not pts else q[1:]
    m, n = cv.stroke_n(pts, list(np.linspace(r0, r1, len(pts))))
    p = cv.put(m, mat, mode='stroke', nrm=n, cast=1, iline=True, bias=bias)
    # estrías del cuerno
    for t in range(3, len(pts) - 3, 3):
        a, b = pts[t], pts[t + 1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        l = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / l, dx / l
        r = r0 + (r1 - r0) * t / len(pts) + 0.8
        cv.shade(cv.line([(a[0] - nx * r, a[1] - ny * r), (a[0] + nx * r, a[1] + ny * r)]), -1, within=[p])
    if ring_at is not None:
        t = int(len(pts) * ring_at)
        a, b = pts[t], pts[t + 1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        l = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / l, dx / l
        r = r0 + (r1 - r0) * t / len(pts) + 0.9
        for k in (0.0, 0.7):
            cv.paint(cv.line([(a[0] + dx / l * k - nx * r, a[1] + dy / l * k - ny * r),
                              (a[0] + dx / l * k + nx * r, a[1] + dy / l * k + ny * r)]) & cv.of(p), ring_mat, 3)
    return p


def hornback_face(cv, B, sp, pose, horn='horn', muzzle='muzzle'):
    """Cara de Hornback: cuernos de carnero que se enroscan hacia atrás y abajo junto a la cabeza (con anillos de
    oro de comerciante), ceja ósea pesada, nariz ancha y chata, boca larga y seria (terco)."""
    # cuerno lejano (a la derecha, detrás de la mejilla) y cuerno cercano (a la izquierda, delante)
    _curl(cv, [(P(B, 15.0, 2.6), P(B, 19.0, -2.6), P(B, 25.0, -1.0), P(B, 25.0, 4.0)),
               (P(B, 25.0, 4.0), P(B, 25.0, 8.0), P(B, 21.5, 9.6), P(B, 20.6, 7.0))], 2.6, 0.9, horn, bias=-0.45, ring_at=0.62)
    _curl(cv, [(P(B, 6.5, 2.4), P(B, 2.0, -3.4), P(B, -5.0, -2.0), P(B, -5.4, 3.6)),
               (P(B, -5.4, 3.6), P(B, -5.6, 8.6), P(B, -1.0, 10.6), P(B, 0.6, 7.6))], 3.0, 1.0, horn, ring_at=0.62)
    # ceja: banda ancha que sobresale a la derecha (sombra sobre los ojos)
    brow = cv.stroke([P(B, 5.0, 6.0), P(B, 11.0, 5.2), P(B, 19.5, 5.4), P(B, 22.4, 6.4)], 1.4, 1.2)
    cv.put(brow, 'skin', mode='top', cast=2, iline=True)
    # nariz ancha y chata
    c = P(B, 18.6, 10.4)
    cv.put(cv.ellipse(c[0], c[1], 3.4, 2.2), 'skin', mode='soft', cast=1, iline=True)
    for (x, y) in ((20.4, 11.0), (17.6, 11.4)):
        cv.dot(B.hx + x, B.hy + y, 'skin', 0)
    # mandíbula más clara y boca larga con la comisura hacia abajo
    hm = cv.of(B.head_part)
    cv.paint(cv.ellipse(B.hx + 14.5, B.hy + 15.0, 7.0, 2.2) & hm, muzzle, 2)
    ml = cv.line([P(B, 10.6, 14.6), P(B, 12.0, 13.8), P(B, 17.0, 13.6), P(B, 20.6, 13.6)])
    cv.paint(ml, 'mouth', 0)


def back_horns(cv, B, sp, pose, mat='horn'):
    """Fila de cuernos romos a lo largo de la espalda: asoman por encima del hombro, del lado de atrás."""
    for k in range(3):
        bx = B.cx_sh - B.sw * 0.42 - k * 2.2
        by = B.y_sh - 0.5 + k * 3.6
        tip = (bx - 4.0 - k * 0.4, by - 4.8 + k * 0.6)
        m = cv.poly([(bx - 1.6, by + 2.2), (bx + 2.4, by - 0.4), tip])
        cv.put(m, mat, mode='top', cast=1, iline=True, bias=-0.25 * k)


def poncho(cv, B, sp, pose, mat='poncho', stripe='stripe', stripe2='stripe2', fringe='fringe'):
    """Poncho grueso del desierto sobre los hombros hasta la cintura, punta al frente, dos franjas y flecos."""
    cs, ysh = B.cx_sh, B.y_sh
    yh = B.y_w + 2.5
    tn = B.turn
    lag = pose.lag
    pts = [(cs - 3.2, ysh - 1.2), (cs + 3.0, ysh - 1.6), (cs + B.sw / 2 + 2.0 - tn, ysh + 2.6), (cs + B.sw / 2 + 2.8 - tn, yh - 0.5 + lag * 0.4),
           (cs + 1.0, yh + 3.2 + lag * 0.5), (cs - B.sw / 2 - 3.2, yh + 0.5 + lag), (cs - B.sw / 2 - 2.6, ysh + 2.6)]
    m = cv.poly(pts)
    p = cv.put(m, mat, mode='cyl', cast=1, iline=True)
    # franjas que siguen el bajo en punta
    for (off, h, s) in ((5.0, 1.6, stripe), (2.0, 0.8, stripe2)):
        band = cv.poly([(cs - B.sw / 2 - 4, yh - off + 0.5), (cs + 1.0, yh - off + 3.2), (cs + B.sw / 2 + 4, yh - off),
                        (cs + B.sw / 2 + 4, yh - off + h), (cs + 1.0, yh - off + 3.2 + h), (cs - B.sw / 2 - 4, yh - off + 0.5 + h)])
        cv.paint(band & cv.of(p), s, 2)
    # pliegues del hombro hacia abajo
    for xo in (-B.sw * 0.30, B.sw * 0.22):
        cv.shade(cv.line([(cs + xo, ysh + 3), (cs + xo - 0.5, yh)]), -1, within=[p])
    # abertura del cuello
    cv.put(cv.poly([(cs - 2.2, ysh - 1.2), (cs + 2.6, ysh - 1.4), (cs + 0.6, ysh + 1.6)]), 'shirt', mode='cyl', iline=True)
    # flecos: un píxel sí y uno no bajo el borde
    edge = m & ~np.roll(m, -1, axis=0)
    ys_, xs_ = np.nonzero(edge)
    fm = np.zeros_like(m)
    for y, x in zip(ys_, xs_):
        if x % 2 == 0 and y + 2 < cv.h:
            fm[y + 1:y + 3, x] = True
    q = cv.put(fm & ~m, fringe, mode='flat', outline=False)
    cv.parts[q].keep = True
    return p


# ---------------- Zib (Quill)

def quill_crest(cv, B, sp, pose, mats=('quill1', 'quill2'), tip='quill2'):
    """Cresta de púas echada hacia atrás (como la de una cacatúa): nacen en la frente y la coronilla, se curvan
    hacia atrás y arriba; coral en la raíz y ámbar en la punta. Se agitan un poco al caminar."""
    sway = pose.sway
    lag = pose.lag
    # (raíz x, y en la cabeza; dirección (dx, dy) del tramo; curva hacia arriba; largo; grosor)
    qs = [(11.0, 1.4, (-0.55, -1.0), 0.45, 11.0, 1.7), (8.6, 0.8, (-0.85, -0.75), 0.40, 13.5, 1.8),
          (6.0, 1.4, (-1.0, -0.35), 0.40, 13.0, 1.7), (3.8, 3.2, (-1.0, -0.05), 0.35, 10.5, 1.5)]
    for i, (x, y, (dx, dy), up, L, w) in enumerate(qs):
        l = math.hypot(dx, dy)
        dx, dy = dx / l, dy / l
        wob = (lag * 0.8 if i % 2 else -lag * 0.5) + sway * 0.6
        root = P(B, x, y)
        mid = (root[0] + dx * L * 0.55, root[1] + dy * L * 0.55)
        end = (root[0] + dx * L + wob * 0.5, root[1] + dy * L - up * L * 0.55 + wob * 0.3)
        pts = bez(root, mid, end, 12)
        m, n = cv.stroke_n(pts, list(np.linspace(w, 0.55, len(pts))))
        p = cv.put(m, mats[0], mode='stroke', nrm=n, cast=1, iline=True)
        tm = cv.stroke(pts[6:], 1.6, 1.0) & m
        cv.paint(tm, tip, 2)


def goggles_eyes(cv, B, sp, pose, mat='brass', lens='glens', strap='strap'):
    """Antiparras grandes sobre los ojos (lentes ámbar), correa alrededor de la cabeza."""
    a1, a2 = ha(B, 1), ha(B, 2)
    y = a1[1] + 1.0
    st = cv.poly([(B.hx - 0.6, y - 1.6), (B.hx + B.head['w'] + 0.2, y - 2.0), (B.hx + B.head['w'] + 0.2, y + 0.2), (B.hx - 0.6, y + 0.8)])
    cv.put(st & ~cv.of(0), strap, mode='cyl', cast=1)
    for (c, r) in (((a1[0] + 0.2, y), 2.8), ((a2[0] + 1.2, y - 0.3), 2.3)):
        cv.put(cv.ellipse(c[0], c[1], r, r * 0.95), mat, mode='shine', cast=1, iline=True)
        cv.put(cv.ellipse(c[0], c[1], r - 1.0, r * 0.95 - 1.0), lens, mode='shine')
        cv.dot(c[0] - 0.8, c[1] - 0.8, 'white', 4)


def _lower_arm(cv, B, sp, pose, side, mat='skin'):
    """Segundo par de brazos (Quill): nacen bajo las costillas, manos en la cintura y codos bien afuera (jarras):
    con los brazos de arriba cruzados, la silueta muestra cuatro codos (apurado, impaciente)."""
    near = side == 'n'
    ar = B.d['ar'] + 0.25
    if near:
        sh = (B.cx_sh - B.sw / 2 + 2.6, B.y_sh + 8.5)
        el = (sh[0] - 5.6, sh[1] + 3.0)
        hand = (B.cx_hip - B.hw / 2 + 0.4, B.hip_y - 1.6)
    else:
        sh = (B.cx_sh + B.sw / 2 - 2.6 - 2.0 * B.turn, B.y_sh + 9.0)
        el = (sh[0] + 5.4, sh[1] + 3.0)
        hand = (B.cx_hip + B.hw / 2 - 1.0, B.hip_y - 2.0)
    bias = 0.0 if near else -0.6
    mu, nu = cv.capsule_n(sh, el, ar + 0.2, ar)
    mf, nf = cv.capsule_n(el, hand, ar, ar * 0.9)
    nn = np.where(mf[..., None] & ~mu[..., None], nf, nu)
    cv.put(mu | mf, mat, mode='stroke', nrm=nn, iline=near, cast=1 if near else 0, bias=bias)
    c = (hand[0] + (0.5 if near else -0.3), hand[1] + 0.3)
    cv.put(cv.ellipse(c[0], c[1], ar + 0.3, ar + 0.5), 'skin', mode='stroke',
           nrm=cv.sphere_n(c[0] - 0.4, c[1] - 0.4, ar + 1.0, ar + 1.2), iline=near, bias=bias)


def lower_arm_far(cv, B, sp, pose, mat='skin'):
    _lower_arm(cv, B, sp, pose, 'f', mat)


def lower_arm_near(cv, B, sp, pose, mat='skin'):
    _lower_arm(cv, B, sp, pose, 'n', mat)


def strap_bag(cv, B, sp, pose, mat='bag', strap='strap2', flap='bag2'):
    """Bandolera de mensajero: correa cruzada al pecho y la bolsa grande en la cadera de atrás."""
    cv.put(cv.stroke([(B.cx_sh + B.sw / 2 - 2.5, B.y_sh), (B.cx_sh - 1, B.y_w - 2), (B.cx_hip - B.hw / 2 - 1, B.hip_y - 2)], 0.9),
           strap, mode='cyl', iline=True)
    x, y = B.cx_hip - B.hw / 2 - 3.5, B.hip_y - 3.0
    m = cv.rect(int(x - 3), int(y), int(x + 3), int(y + 6))
    p = cv.put(m, mat, mode='cyl', iline=True, cast=1)
    cv.put(cv.rect(int(x - 3), int(y), int(x + 3), int(y + 2)), flap, mode='top', iline=True)
    cv.dot(x, y + 2, 'brass', 3)
    return p


# ---------------- Mother Oona (Glimmerfolk)

def jelly_dome(cv, B, sp, pose, mat='jelly', core='jcore', glow=('glow', 'glow2'), rim='jrim'):
    """Cabeza de medusa translúcida: domo brillante (no se puede usar alfa: la translucidez se pinta), un núcleo más
    oscuro adentro con 'pensamientos' que brillan, borde de abajo ondulado, y una cara amable vista a través."""
    hm = cv.of(B.head_part)
    cx, cy = B.hx + B.head['w'] / 2.0 - 0.3, B.hy + B.head['h'] * 0.48
    p = cv.put(hm, mat, mode='shine', cast=1)
    cv.set_nrm(p, cv.sphere_n(cx - 0.5, cy + 1.0, B.head['w'] / 2 + 1.5, B.head['h'] / 2 + 1.5, k=0.85))
    # volados bajo el domo (el borde de la campana, corto: nada de colgajos largos)
    bot = B.hy + B.head['h'] - 1
    fr = np.zeros_like(hm)
    for k, x in enumerate(range(int(B.hx) + 2, int(B.hx + B.head['w']) - 2, 2)):
        fr |= cv.ellipse(x + 0.5, bot + 1.2 + (k % 2) * 0.6, 1.3, 1.6)
    q0 = cv.put(fr & ~hm, rim, mode='soft', cast=0, iline=True)
    for x in range(int(B.hx) + 1, int(B.hx + B.head['w']) - 1):
        if (x % 3) != 0:
            cv.paint(cv.rect(x, bot - 1, x, bot), rim, 2)
    # núcleo: una masa blanda arriba al centro, sin contorno
    q = cv.put(cv.ellipse(cx + 0.8, B.hy + 6.8, 5.6, 4.2) & hm, core, mode='soft', outline=False)
    cv.parts[q].sep = False
    # pensamientos (puntos de luz que no se limpian)
    for (x, y, g, big) in ((cx - 1.8, B.hy + 5.6, glow[0], True), (cx + 3.2, B.hy + 7.6, glow[1], False),
                           (cx + 1.0, B.hy + 4.2, glow[1], False), (cx - 3.6, B.hy + 9.0, glow[0], False)):
        cv.dot(x, y, g, 4)
        if big:
            for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                cv.dot(x + dx, y + dy, g, 2)
    # brillo del vidrio: arco arriba a la izquierda
    for (x, y, l) in ((B.hx + 4, B.hy + 4, 4), (B.hx + 5, B.hy + 3, 4), (B.hx + 7, B.hy + 2, 3), (B.hx + 3, B.hy + 6, 3)):
        cv.dot(x, y, 'white', l)
    # cara (vista a través): ojos ovalados oscuros con brillo, sonrisa pequeña
    a1, a2 = ha(B, 1), ha(B, 2)
    for (ax, ay, w) in ((a1[0], a1[1], 2), (a2[0], a2[1], 2)):
        for dy in range(3):
            for dx in range(w):
                cv.dot(ax + dx, ay + dy, 'eyed', 0 if dy else 1)
        cv.dot(ax, ay, 'white', 4)
    m3 = ha(B, 3)
    for (dx, dy) in ((0, 0), (1, 0), (-1, -1)):
        cv.dot(m3[0] + dx, m3[1] + dy, 'eyed', 1)
    return p


def stole(cv, B, sp, pose, mat='stole', trim='trim'):
    """Estola larga que cuelga delante de los hombros hasta las rodillas, con borde bordado."""
    lag = pose.lag
    for (x0, ln, w) in ((B.cx_sh - 2.6, 26.0, 2.4), (B.cx_sh + 3.2, 24.0, 2.2)):
        pts = [(x0, B.y_sh - 0.5), (x0 - 0.3, B.y_sh + ln * 0.5), (x0 - 0.6 + pose.sway * 0.5, B.y_sh + ln + lag)]
        m = cv.stroke(pts, w, w)
        p = cv.put(m, mat, mode='cyl', cast=1, iline=True)
        tip = cv.rect(int(x0 - w - 1), int(B.y_sh + ln + lag - 2), int(x0 + w + 1), int(B.y_sh + ln + lag + 3)) & m
        cv.paint(tip, trim, 2)


# ---------------- Pipip (Burrower)

def mole_snout(cv, B, sp, pose, nose='nose', whisk='whisker'):
    """Hocico largo y puntiagudo de topo con la punta rosada y bigotes."""
    a = P(B, 11.5, 9.0)
    b = P(B, 19.5, 10.4)
    m, n = cv.capsule_n(a, b, 3.0, 1.4)
    p = cv.put(m, 'skin', mode='stroke', nrm=n, cast=1, iline=True)
    cv.put(cv.ellipse(b[0] + 0.4, b[1] - 0.2, 1.9, 1.7), nose, mode='shine', iline=True)
    w = cv.line([P(B, 15.5, 11.6), P(B, 19.0, 13.4)]) | cv.line([P(B, 16.0, 9.0), P(B, 20.5, 7.6)])
    q = cv.put(w & (cv.pid == 0), whisk, mode='flat', outline=False)
    cv.parts[q].keep = True
    # boca chiquita bajo el hocico
    cv.dot(B.hx + 13, B.hy + 12, 'mouth', 0)
    return p


def big_goggles(cv, B, sp, pose, mat='brass', lens='glens', strap='strap'):
    """Antiparras enormes de minero (vidrio oscuro con reflejo) sobre los ojos chiquitos."""
    a1, a2 = ha(B, 1), ha(B, 2)
    y = a1[1] + 0.5
    st = cv.poly([(B.hx - 0.8, y - 1.2), (B.hx + 6, y - 1.4), (B.hx + 6, y + 0.6), (B.hx - 0.8, y + 0.8)])
    cv.put(st, strap, mode='cyl', cast=1)
    for (c, r) in (((a1[0] - 0.4, y), 3.3), ((a2[0] + 1.6, y - 0.4), 2.6)):
        cv.put(cv.ellipse(c[0], c[1], r, r), mat, mode='shine', cast=1, iline=True)
        cv.put(cv.ellipse(c[0], c[1], r - 1.1, r - 1.1), lens, mode='shine')
        cv.dot(c[0] - 1.0, c[1] - 1.0, 'white', 4)
        cv.dot(c[0] - 0.0, c[1] - 1.2, 'white', 3)


def hard_hat(cv, B, sp, pose, mat='hat', lamp='lamp', glow='glow'):
    """Casco de minero: domo bajo con visera corta y una lámpara redonda al frente."""
    w = B.head['w']
    cx, top = B.hx + w / 2.0 + 0.3, B.hy - 3.0
    dome = cv.ellipse(cx, top + 6.0, w / 2 + 1.4, 6.2) & (cv.ys <= top + 5.6)
    p = cv.put(dome, mat, mode='top', cast=2, iline=True)
    cv.set_nrm(p, cv.sphere_n(cx - 1, top + 5, w / 2 + 2, 6.5))
    brim = cv.poly([(cx - w / 2 - 2.0, top + 5.0), (cx + w / 2 + 3.4, top + 4.4), (cx + w / 2 + 3.4, top + 6.0), (cx - w / 2 - 1.6, top + 6.4)])
    cv.put(brim, mat, mode='top', cast=2, iline=True)
    # cresta del casco
    cv.shade(cv.line([(cx - 2.0, top + 0.2), (cx + 3.5, top + 0.5)]), +1, within=[p])
    # lámpara
    lc = (cx + w / 2 - 1.2, top + 2.6)
    cv.put(cv.ellipse(lc[0], lc[1], 2.4, 2.3), lamp, mode='shine', iline=True, cast=1)
    cv.put(cv.ellipse(lc[0] + 0.5, lc[1], 1.4, 1.4), glow, mode='flat')
    cv.dot(lc[0] + 0.3, lc[1] - 0.4, 'white', 4)
    return p


def claws(cv, B, sp, side, pose, mat='claw'):
    """Garras de cavar (tres uñas claras) en la mano."""
    g = B.arm[side]['grip']
    for k in range(3):
        x = g[0] - 1.0 + k * 1.2
        cv.put(cv.line([(x, g[1] + 1.0), (x + 0.3, g[1] + 2.4)]), mat, mode='flat', iline=True)


def coin_pouch(cv, B, sp, side, pose, mat='pouch2', tie='string'):
    g = B.arm[side]['grip']
    x, y = g[0] + 0.5, g[1] + 2.5
    cv.put(cv.ellipse(x, y + 1.2, 2.4, 2.2), mat, mode='soft', iline=True, cast=1)
    cv.put(cv.rect(int(x - 1), int(y - 1), int(x + 1), int(y - 1)), tie, mode='flat')


# ---------------- Raker (Dune Raker)

def axolotl_face(cv, B, sp, pose, gill='gill', spot='spot', belly='belly'):
    """Cara de salamandra: ojos de cuenta bien separados, boca ancha sonriente de lado a lado, garganta clara,
    manchas, y branquias plumosas grandes a los costados (tres de cada lado, las lejanas en sombra)."""
    lag = pose.lag
    hm = cv.of(B.head_part)
    th = cv.ellipse(B.hx + 13.0, B.hy + 12.8, 8.0, 2.6) & hm
    cv.paint(th, belly, 2)
    sm = cv.line([P(B, 6.6, 8.2), P(B, 8.2, 9.8), P(B, 13.0, 10.6), P(B, 18.0, 10.2), P(B, 20.4, 8.6)])
    cv.paint(sm & hm, 'mouth', 0)
    for (x, y) in ((3.0, 4.0), (5.5, 2.5), (2.4, 8.6), (12.0, 2.6), (16.0, 3.2)):
        cv.paint(cv.rect(int(B.hx + x), int(B.hy + y), int(B.hx + x) + 1, int(B.hy + y)) & hm, spot, 2)
    # branquias cercanas (izquierda): frondas gruesas con filamentos, se mecen al caminar
    fronds = [((2.0, 5.0), (-3.6, 2.4), (-7.0, 0.6)), ((1.2, 7.6), (-5.0, 7.4), (-8.8, 7.0)), ((1.8, 10.0), (-3.8, 12.0), (-7.0, 13.8))]
    for i, (r, c, t) in enumerate(fronds):
        tt = (t[0] + (lag * 0.6 if i == 1 else 0), t[1] + lag * 0.5)
        pts = bez(P(B, *r), P(B, *c), P(B, *tt), 8)
        m, n = cv.stroke_n(pts, list(np.linspace(1.7, 1.0, len(pts))))
        cv.put(m, gill, mode='stroke', nrm=n, cast=1, iline=True)
        for k in (2, 4, 6):
            x, y = pts[k]
            cv.put(cv.rect(int(x), int(y) - 2, int(x), int(y) - 1) | cv.rect(int(x) - 1, int(y) + 2, int(x) - 1, int(y) + 2),
                   gill, mode='flat', iline=True)
    # lejanas (derecha): asoman detrás de la mejilla, más oscuras
    for (r, t) in (((19.6, 3.0), (24.4, -1.0)), ((20.6, 5.6), (25.6, 4.0))):
        pts = bez(P(B, *r), P(B, (r[0] + t[0]) / 2, r[1] - 1.5), P(B, *t), 6)
        m, n = cv.stroke_n(pts, list(np.linspace(1.3, 0.8, len(pts))))
        cv.put(m, gill, mode='stroke', nrm=n, cast=1, iline=True, bias=-0.6)


def lizard_tail(cv, B, sp, pose, mat='skin', spot='spot'):
    """Cola gruesa de salamandra que baja de la espalda y descansa en el suelo, hacia atrás."""
    swing = [0, 1, 0, -1][pose.i] if pose.kind == 'walk' else [0, 1][pose.i]
    base = (B.cx_hip - B.hw / 2 + 1.5, B.hip_y - 2.0)
    pts = bez3(base, (base[0] - 5.0, base[1] + 4.0), (base[0] - 9.0 + swing, GROUND - 4.0), (base[0] - 15.0 + swing * 1.5, GROUND - 1.5), 16)
    m, n = cv.stroke_n(pts, list(np.linspace(2.8, 0.7, len(pts))))
    p = cv.put(m, mat, mode='stroke', nrm=n, cast=0)
    for t in (4, 8, 12):
        x, y = pts[t]
        cv.paint(cv.rect(int(x), int(y) - 1, int(x) + 1, int(y) - 1) & cv.of(p), spot, 2)
    return p


def junk_pack(cv, B, sp, pose, wood='packwood', crate='crate', hose='hose', dish='dish', pipe='pipe', gear='gear',
              tarp='tarp', tarp2='tarp2'):
    """Mochila enorme de chatarra en un bastidor de palos: cajón, manguera enrollada, antena parabólica, caños,
    un engranaje y una lona enrollada arriba. Va detrás del cuerpo y sube muy por encima de la cabeza."""
    bob = pose.bob
    x0 = B.cx_sh - B.sw / 2 - 10.5
    x1 = B.cx_sh + 1.5
    yb = B.hip_y + 2.0
    yt = B.hy - 15.0 + bob
    # bastidor: dos parantes y travesaños
    for x in (x0 + 1.0, x1 - 1.5):
        cv.put(cv.capsule((x, yb), (x - 0.5, yt + 4), 0.8), wood, mode='cyl', iline=True)
    # cajón abajo
    cy0 = B.y_w - 7.0
    cr = cv.rect(int(x0), int(cy0), int(x1), int(yb))
    p = cv.put(cr, crate, mode='cyl', iline=True, cast=1)
    for y in (cy0 + 3, cy0 + 6, cy0 + 9):
        cv.shade(cv.line([(x0, y), (x1, y)]), -1, within=[p])
    cv.shade(cv.line([(x0 + 1, cy0 + 1), (x1 - 1, yb - 1)]), +1, within=[p])
    # manguera enrollada encima del cajón
    hc = ((x0 + x1) / 2 - 1.0, cy0 - 2.6)
    ring = cv.ellipse(hc[0], hc[1], 6.2, 3.2) & ~cv.ellipse(hc[0] + 0.4, hc[1] + 0.2, 3.0, 1.2)
    cv.put(ring, hose, mode='stroke', nrm=cv.sphere_n(hc[0] - 1, hc[1] - 1, 7, 4), iline=True, cast=1)
    # caños que asoman
    cv.put(cv.capsule((x0 + 3.0, cy0 - 3.0), (x0 - 1.5, yt + 7.0), 1.3), pipe, mode='shine', iline=True, cast=1)
    cv.put(cv.capsule((x1 - 4.0, cy0 - 4.0), (x1 - 2.0, yt + 3.0), 1.0), pipe, mode='shine', iline=True, cast=1)
    # lona enrollada arriba (a rayas)
    tm = cv.capsule((x0 - 0.5, yt + 6.0), (x1 + 0.5, yt + 5.0), 2.6)
    q = cv.put(tm, tarp, mode='top', iline=True, cast=1)
    for x in range(int(x0), int(x1) + 1, 3):
        cv.paint(cv.rect(x, int(yt + 2), x, int(yt + 9)) & cv.of(q), tarp2, 2)
    # antena parabólica arriba a la izquierda
    dc = (x0 + 3.5, yt + 1.0)
    dm = cv.ellipse(dc[0], dc[1], 5.0, 3.2) & ~cv.ellipse(dc[0] + 1.6, dc[1] - 1.4, 4.4, 2.6)
    cv.put(dm, dish, mode='shine', iline=True, cast=1)
    cv.put(cv.line([(dc[0] + 0.5, dc[1] - 0.5), (dc[0] + 3.0, dc[1] - 3.5)]), pipe, mode='flat')
    # engranaje en el costado
    gc = (x0 + 0.5, B.y_w - 9.5)
    gm = cv.ellipse(gc[0], gc[1], 3.4, 3.4)
    for k in range(8):
        a = k * math.pi / 4
        gm |= cv.ellipse(gc[0] + math.cos(a) * 3.6, gc[1] + math.sin(a) * 3.6, 0.9, 0.9)
    gm &= ~cv.ellipse(gc[0], gc[1], 1.1, 1.1)
    cv.put(gm, gear, mode='shine', iline=True, cast=1)
    return p


def tool_apron(cv, B, sp, pose, mat='apron', tool='steel', handle='handle'):
    """Delantal de herramientas corto con mangos asomando de los bolsillos."""
    p = apron(cv, B, sp, pose, mat=mat, y_top=B.y_w - 1, y_hem=B.hip_y + 5, bib=False, width=1.05, pockets=True)
    for (dx, mat2, h) in ((-2.6, tool, 3), (1.4, handle, 2)):
        x = B.cx + dx
        cv.put(cv.rect(int(x), int(B.y_w + 1), int(x), int(B.y_w + 1) + h), mat2, mode='shine', iline=True)
    return p


def pod_hand(cv, B, sp, side, pose, shell='podshell', band='podband', light='podlight'):
    """Cápsula de chatarra sellada (las que venden los Rakers) sostenida en alto en la mano: casco de metal con una
    faja y una lucecita."""
    g = B.arm[side]['grip']
    x, y = g[0] + 0.6, g[1] - 4.2
    m = cv.ellipse(x, y, 3.6, 4.4)
    p = cv.put(m, shell, mode='shine', iline=True, cast=1)
    cv.set_nrm(p, cv.sphere_n(x - 0.6, y - 0.8, 4.2, 5.0))
    cv.paint(cv.rect(int(x - 4), int(y), int(x + 4), int(y + 1)) & m, band, 2)
    cv.dot(x + 1.4, y + 0.5, light, 4)
    B.arm[side]['no_regrip'] = False
