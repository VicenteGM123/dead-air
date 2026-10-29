"""Tocados que CONTIENEN el pelo (ronda 3): sombreros, cascos, gorros, pañuelos, velos, turbantes y capuchas.

Regla (como Octopath Traveler: el gorro de Castti, el sombrero de Partitio): el tocado se SIENTA en la cabeza.
  - La copa / cúpula es tan ancha como la cabeza con su pelo: no asoma pelo por encima ni al lado de la copa.
  - El ala o el borde queda a la altura de la frente; el pelo solo se ve POR DEBAJO del borde (flequillo, patillas,
    mechones que caen por los lados y la espalda, una trenza).
Cada función de tocado: 1) calcula su línea de borde, 2) borra el pelo que queda por encima (clip_hair), 3) se
dibuja encima. El pelo ya está pintado cuando se llaman (van en la lista 'head' de la ficha).
Reemplaza a los tocados de c64acc (chars64 importa este módulo al final).

Coordenadas de cabeza como hp(): una cabeza de 18 x 20 unidades que se escala a la plantilla real.
"""
import math
import numpy as np
from c64core import *
from c64body import GROUND

HW, HH = 18.0, 20.0


def H(B, x, y):
    """Unidades de cabeza -> píxeles del cuadro."""
    return (B.hx + x * B.head['w'] / HW, B.hy + y * B.head['h'] / HH)


def sx(B):
    return B.head['w'] / HW


def sy(B):
    return B.head['h'] / HH


def skull_cx(B):
    """Centro horizontal del cráneo (la coronilla)."""
    return B.hx + B.head['w'] / 2.0 - 0.5


def hair_vol(sp):
    return sp.get('hair', {}).get('volume', 2.0)


# ------------------------------------------------------------------ recorte del pelo

def _hair_parts(cv, mats=('hair',)):
    m = np.zeros((cv.h, cv.w), bool)
    for p in range(1, len(cv.parts)):
        part = cv.parts[p]
        if part is not None and part.mat in mats:
            m |= cv.pid == p
    return m


def edge_line(cv, pts):
    """Polilínea (px, de izquierda a derecha) -> y del borde por columna (se extiende plana a los lados)."""
    xs = np.array([p[0] for p in pts], np.float32)
    ys = np.array([p[1] for p in pts], np.float32)
    o = np.argsort(xs)
    return np.interp(np.arange(cv.w, dtype=np.float32), xs[o], ys[o])


def clip_hair(cv, B, yline, mats=('hair',), skin=True):
    """Borra el pelo (y, si skin, el cráneo) que queda por encima de la línea de borde: lo tapa el tocado.
    yline: y del borde por columna (edge_line)."""
    above = cv.ys < yline[None, :]
    m = above & _hair_parts(cv, mats)
    if skin and getattr(B, 'head_part', None):
        m |= above & (cv.pid == B.head_part)
    cv.erase(m)
    return m


def under_mask(cv, yline):
    """Píxeles por encima de la línea de borde (la zona que cubre el tocado)."""
    return cv.ys < yline[None, :]


# ------------------------------------------------------------------ sombrero de bruja

def _crown_base(cv, hcx, ybase, cw, ry):
    """Base de la copa vista un poco desde arriba: media elipse de abajo (se apoya sobre el ala)."""
    ys = cv.ys.astype(np.float32)
    return cv.ellipse(hcx, ybase, cw, ry) & (ys >= ybase)


def witch_hat(cv, B, sp, pose, mat='hat', band='band', h=17.0, brim=13.5, bend=-6.0, deco=None, droop=1.5, crown_w=None,
              brim_cast=2, rim=6.6, brim_h=2.8, tilt=0.0, **_):
    """Sombrero de bruja PUESTO: el ala a la altura de la frente (rim = fila de su borde delantero, en unidades de
    cabeza), la copa tan ancha como la cabeza con el pelo; la punta se dobla hacia atrás. Del ala se ve la franja de
    delante de la copa y las puntas a los lados; el pelo asoma por debajo (flequillo, los lados, la espalda)."""
    lag, sway = pose.lag, pose.sway
    hcx = skull_cx(B) + 0.5
    front = H(B, 0, rim)[1]
    rcy = front - brim_h                   # centro del ala
    vol = hair_vol(sp)
    cw = crown_w if crown_w is not None else B.head['w'] / 2.0 + min(vol, 1.4) + 0.4
    yb = rcy - 0.6                         # centro de la base de la copa (algo detrás del centro del ala)
    rb = brim_h * 0.50
    # 1. todo lo que queda por encima de la base de la copa lo cubre el sombrero (o no existe)
    clip_hair(cv, B, np.full(cv.w, yb + rb * 0.6, np.float32))
    # 2. ala
    pb, bm = _brim(cv, hcx, rcy, brim, brim_h, mat, droop_l=droop, droop_r=-0.4, cast=brim_cast)
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    # 3. copa: cono con los lados algo cóncavos y la punta doblada hacia atrás
    tip = (hcx + bend + sway * 0.8, yb - h + lag * 0.6)
    pts = [(hcx - cw, yb + 0.2), (hcx - cw * 0.72, yb - h * 0.30), (hcx - cw * 0.42 + bend * 0.15, yb - h * 0.62),
           (hcx - cw * 0.20 + bend * 0.45, yb - h * 0.86), tip,
           (hcx + cw * 0.05 + bend * 0.30, yb - h * 0.78), (hcx + cw * 0.30 + bend * 0.10, yb - h * 0.52),
           (hcx + cw * 0.70, yb - h * 0.22), (hcx + cw, yb + 0.2)]
    cone = cv.poly(pts)
    crown_m = cone | _crown_base(cv, hcx, yb, cw, rb)
    pc = cv.put(crown_m, mat, mode='rim', cast=1, band=0.32, iline=True)
    cv.shade(cv.line([(hcx - cw * 0.10, yb - h * 0.48), (hcx + bend * 0.45, yb - h * 0.82)]), -1, within=[pc])
    # 4. cinta: dos filas justo encima de la base (sigue la curva de la base)
    if band:
        ybf = yb + rb * np.sqrt(np.clip(1.0 - ((xs - hcx) / cw) ** 2, 0, 1))
        bmask = crown_m & (ys <= ybf - 0.6) & (ys >= ybf - 2.6)
        cv.put(bmask, band, mode='shine', iline=False)
    if deco:
        deco(cv, hcx + 1.5, yb)
    return pc


# ramita sobre la cinta: hojas en abanico y una baya, píxel a píxel (nítida a 1x). Niveles viejos 0..4.
_SPRIG = [
    "..LL.l.",
    ".LLl.ll",
    "..Llll.",
    ".BBl...",
    ".Bb....",
]


def leaf_sprig(mat_leaf='leaf', mat_berry=None):
    """Ramita de hojas con una baya en la cinta (a la derecha, hacia la cara)."""
    def f(cv, bx, by):
        ox, oy = int(round(bx + 2.0)), int(round(by - 4.0))
        codes = {'L': (mat_leaf, 3), 'l': (mat_leaf, 2), 'B': (mat_berry or mat_leaf, 3), 'b': (mat_berry or mat_leaf, 4)}
        pid = cv.put(np.zeros((cv.h, cv.w), bool), mat_leaf, mode='flat')
        for y, row in enumerate(_SPRIG):
            for x, ch in enumerate(row):
                if ch in codes:
                    mat, lv = codes[ch]
                    cv.dot(ox + x, oy + y, mat, lv, p=pid)
    return f


# ------------------------------------------------------------------ sombreros de ala (paja, guardia)

def _brim(cv, hcx, rcy, rx, ry, mat, droop_l=0.6, droop_r=0.6, cast=2, mode='top'):
    """Ala elíptica vista un poco desde arriba; las puntas caen un poco. Devuelve (id, máscara)."""
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    u = (xs - hcx) / rx
    yc = rcy + np.where(u < 0, droop_l, droop_r) * u * u
    m = ((xs - hcx) / rx) ** 2 + ((ys - yc) / ry) ** 2 <= 1.0
    p = cv.put(m, mat, mode=mode, cast=cast, iline=True, band=0.2)
    # canto del ala: la fila de abajo un tono más oscura (grosor)
    lower = m & ~np.roll(m, -1, axis=0) & (ys > rcy)
    cv.shade(lower, -1, within=[p])
    return p, m


def straw_hat(cv, B, sp, pose, mat='straw', band='band', brim=12.5, h=5.0, rim=6.6, brim_h=3.0, crown_w=None, weave=True, **_):
    """Sombrero de paja PUESTO: el ala a la altura de la frente, la copa del ancho de la cabeza con su pelo; del ala
    se ve la franja de delante y las puntas; el pelo asoma por debajo (patillas, nuca). Trama: un anillo de trenzado
    en el ala (sin ruido)."""
    hcx = skull_cx(B) + 0.5
    rcy = H(B, 0, rim)[1] - brim_h
    vol = hair_vol(sp)
    cw = crown_w if crown_w is not None else B.head['w'] / 2.0 + min(vol, 1.2) - 0.4
    yb = rcy - 0.6
    rb = brim_h * 0.45
    clip_hair(cv, B, np.full(cv.w, yb + rb * 0.6, np.float32))
    pb, bm = _brim(cv, hcx, rcy, brim, brim_h, mat, droop_l=0.8, droop_r=0.5)
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    if weave:
        ring = (((xs - hcx) / (brim * 0.78)) ** 2 + ((ys - rcy) / (brim_h * 0.78)) ** 2)
        cv.shade(bm & (np.abs(ring - 1.0) < 0.14) & (ys > rcy + 0.5), -1, within=[pb])
    top = yb - h
    crown = cv.poly([(hcx - cw, yb + 0.2), (hcx - cw + 0.3, top + 1.4), (hcx - cw + 1.6, top), (hcx + cw - 1.6, top),
                     (hcx + cw - 0.3, top + 1.4), (hcx + cw, yb + 0.2)])
    crown |= _crown_base(cv, hcx, yb, cw, rb)
    pc = cv.put(crown, mat, mode='rim', cast=1, iline=True)
    cv.shade(cv.line([(hcx - cw * 0.45, top + 1), (hcx + cw * 0.35, top + 1)]), -1, within=[pc])
    if band:
        ybf = yb + rb * np.sqrt(np.clip(1.0 - ((xs - hcx) / cw) ** 2, 0, 1))
        cv.put(crown & (ys <= ybf - 0.5) & (ys >= ybf - 2.4), band, mode='cyl', iline=False)
    return pc


# ------------------------------------------------------------------ cascos

def helmet(cv, B, sp, pose, mat='steel', kind='dwarf', plume=None, trim=None, **kw):
    if kind == 'kettle':
        return _kettle(cv, B, sp, pose, mat, trim, **kw)
    if kind == 'knight':
        return _knight(cv, B, sp, pose, mat, plume, trim, **kw)
    return _dwarf_helm(cv, B, sp, pose, mat, trim, **kw)


def _kettle(cv, B, sp, pose, mat, trim, rim=7.0, brim=12.0, brim_h=2.6, h=6.5, **_):
    """Casco de guardia (capelina): cúpula de acero que cubre toda la cabeza con el pelo y un ala ancha; debajo del
    ala solo asoman las patillas y la nuca."""
    hcx = skull_cx(B) + 0.5
    rcy = H(B, 0, rim)[1] - brim_h
    cw = B.head['w'] / 2.0 + min(hair_vol(sp), 1.2) + 0.2
    yb = rcy - 0.6
    rb = brim_h * 0.45
    clip_hair(cv, B, np.full(cv.w, yb + rb * 0.6, np.float32))
    pb, bm = _brim(cv, hcx, rcy, brim, brim_h, mat, droop_l=0.9, droop_r=0.9, mode='shine')
    cv.set_nrm(pb, cv.sphere_n(hcx - 2.0, rcy - 3.0, brim + 2.0, brim_h + 5.0, k=0.6))
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    dome = (cv.ellipse(hcx, yb, cw, h) & (ys <= yb)) | _crown_base(cv, hcx, yb, cw, rb)
    pd = cv.put(dome, mat, mode='shine', cast=1, iline=True)
    cv.set_nrm(pd, cv.sphere_n(hcx - 0.5, yb - 1.0, cw + 1.0, h + 1.0, k=0.95))
    cv.shade(cv.line([(hcx + 1.0, yb - h + 1.0), (hcx + 1.5, yb - 0.5)]), +1, within=[pd])
    if trim:
        ybf = yb + rb * np.sqrt(np.clip(1.0 - ((xs - hcx) / cw) ** 2, 0, 1))
        cv.put(dome & (ys >= ybf - 1.2), trim, mode='shine')
    return pd


def _dwarf_helm(cv, B, sp, pose, mat, trim, edge=None, h=None, nose=True, rivets=True, **_):
    """Casco enano (spangenhelm): cúpula que baja hasta las cejas por delante y tapa las orejas a los lados; banda de
    latón en el borde, nasal y remaches. Debajo solo asoman las patillas, que se juntan con la barba."""
    edge = edge or [(-2.5, 11.8), (1.5, 11.0), (4.5, 9.0), (7.5, 7.6), (12.0, 7.2), (16.5, 7.4), (20.0, 8.6)]
    pts = [H(B, x, y) for x, y in edge]
    yl = edge_line(cv, pts)
    hcx = skull_cx(B) + 0.3
    vol = min(hair_vol(sp), 1.2)
    rx = B.head['w'] / 2.0 + vol + 0.9
    top = B.hy - vol - 1.4
    cyd = B.hy + B.head['h'] * 0.42
    ry = cyd - top
    clip_hair(cv, B, yl + 0.5)
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    dome = (cv.ellipse(hcx, cyd, rx, ry) | ((np.abs(xs - hcx) <= rx - 0.3) & (ys >= cyd))) & (ys <= yl[None, :] + 0.5)
    pd = cv.put(dome, mat, mode='shine', cast=2, iline=True)
    cv.set_nrm(pd, cv.sphere_n(hcx - 0.8, cyd - 1.5, rx + 1.2, ry + 2.0, k=0.95))
    # costillas (las placas del casco): dos líneas de la cima al borde
    for fx in (-0.35, 0.30):
        cv.shade(cv.line([(hcx + fx * 2.0, top + 1.0), (hcx + fx * rx * 1.4, cyd + 1.0)]), -1, within=[pd])
    # banda del borde (2 filas) siguiendo la línea
    band = dome & (ys >= yl[None, :] - 1.6)
    pbd = cv.put(band, trim or mat, mode='shine', cast=1, iline=True)
    if nose:
        nx = ha_px(B, 7)[0] - 0.5
        nm = cv.rect(int(round(nx)), int(yl[int(round(nx))]) - 1, int(round(nx)), int(round(ha_px(B, 7)[1])) - 1)
        cv.put(nm, trim or mat, mode='shine', cast=1, iline=True)
    if rivets:
        for x in (hcx - rx * 0.6, hcx - rx * 0.15, hcx + rx * 0.45):
            xi = int(round(x))
            if 0 <= xi < cv.w:
                cv.dot(xi, int(round(yl[xi] - 0.8)), trim or mat, 4)
    return pd


def _knight(cv, B, sp, pose, mat, plume, trim, **_):
    """Casco de caballero abierto: cúpula, carrilleras a los lados de la cara y cubrenuca; la melena sale por debajo
    del cubrenuca. Banda dorada en la frente y penacho."""
    lag, sway = pose.lag, pose.sway
    hcx = skull_cx(B) + 0.2
    vol = min(hair_vol(sp), 1.2)
    rx = B.head['w'] / 2.0 + vol + 0.8
    top = B.hy - vol - 1.2
    cyd = B.hy + B.head['h'] * 0.40
    ry = cyd - top
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    brow = H(B, 0, 6.8)[1]
    # línea inferior del casco: cubrenuca (atrás), carrillera cercana, abertura de la cara (frente), carrillera lejana
    edge = [(-2.6, 11.6), (2.2, 11.8), (3.0, 15.8), (5.2, 16.0), (5.6, 6.8), (16.6, 6.8), (17.0, 13.0), (20.0, 12.0)]
    pts = [H(B, x, y) for x, y in edge]
    yl = edge_line(cv, pts)
    # la abertura de la cara es un escalón: se rehace columna por columna
    x_face0, x_face1 = H(B, 5.4, 0)[0], H(B, 16.8, 0)[0]
    for x in range(cv.w):
        if x_face0 <= x <= x_face1:
            yl[x] = brow
    clip_hair(cv, B, yl + 0.5)
    helm = (cv.ellipse(hcx, cyd, rx, ry) | ((np.abs(xs - hcx) <= rx - 0.3) & (ys >= cyd))) & (ys <= yl[None, :] + 0.5)
    pd = cv.put(helm, mat, mode='shine', cast=2, iline=True)
    cv.set_nrm(pd, cv.sphere_n(hcx - 0.8, cyd - 1.5, rx + 1.2, ry + 2.0, k=0.95))
    if trim:
        bandm = helm & (ys >= brow - 1.6) & (ys <= brow + 0.5) & (xs >= x_face0 - 1) & (xs <= x_face1 + 1)
        cv.put(bandm, trim, mode='shine', cast=1)
    # cresta
    cv.shade(cv.line([(hcx + 0.5, top + 1.0), (hcx + 1.0, brow - 2.0)]), +1, within=[pd])
    if plume:
        pts_ = bez3((hcx + 0.5, top + 1.0), (hcx - 2.0, top - 5.0), (hcx - 7.0 + sway, top - 5.5 + lag * 0.5),
                    (hcx - 11.0 + sway * 1.5, top + 1.0 + lag), 12)
        radii = [max(0.6, 2.2 * (1.0 - i / 12.0) ** 0.6) for i in range(13)]
        m, nn = cv.stroke_n(pts_, radii)
        pp = cv.put(m, plume, mode='stroke', nrm=nn, cast=0, iline=True)
        cv.shade(cv.line(pts_[3:-2]), -1, within=[pp])
    return pd


def ha_px(B, k):
    ax, ay = B.head['a'][k]
    return (B.hx + ax, B.hy + ay)


# ------------------------------------------------------------------ gorros blandos

def cap_soft(cv, B, sp, pose, mat='cap', edge=None, flop=2.5, cuff=None, **_):
    """Gorro de lana / fieltro bien calado: cubre la cabeza y el pelo hasta la frente (por delante) y la parte de
    arriba de la oreja (al lado); la copa cae un poco hacia atrás; vuelta (puño) en el borde."""
    edge = edge or [(-2.4, 10.0), (1.5, 9.2), (4.5, 7.6), (8.0, 6.4), (12.0, 6.0), (16.0, 6.2), (20.0, 7.2)]
    pts = [H(B, x, y) for x, y in edge]
    yl = edge_line(cv, pts)
    hcx = skull_cx(B) + 0.2
    vol = min(hair_vol(sp), 1.2)
    rx = B.head['w'] / 2.0 + vol + 0.8
    top = B.hy - vol - 1.6
    cyd = B.hy + B.head['h'] * 0.40
    ry = cyd - top
    clip_hair(cv, B, yl + 0.5)
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    m = (cv.ellipse(hcx, cyd, rx, ry) | ((np.abs(xs - hcx) <= rx - 0.3) & (ys >= cyd))) & (ys <= yl[None, :] + 0.5)
    # la copa cae hacia atrás (a la izquierda): un bulto arriba a la izquierda
    if flop:
        m |= cv.ellipse(hcx - rx * 0.45, top + 3.0, rx * 0.55 + flop * 0.3, 3.2) & (ys <= cyd)
    p = cv.put(m, mat, mode='top', cast=2, iline=True, band=0.25)
    cv.set_nrm(p, cv.sphere_n(hcx - 1.0, cyd - 2.0, rx + 1.5, ry + 2.0, k=0.85))
    # pliegue del bulto
    cv.shade(cv.line([(hcx - rx * 0.1, top + 2.0), (hcx - rx * 0.55, top + 4.5)]), -1, within=[p])
    # vuelta (2 filas) siguiendo el borde
    cuffm = m & (ys >= yl[None, :] - 1.8)
    cv.put(cuffm, cuff or mat, mode='cyl', cast=1, iline=True)
    return p


def kerchief(cv, B, sp, pose, mat='kerchief', dots=None, knot=True, front=5.4, **_):
    """Pañuelo de cabeza atado en la nuca: cubre la coronilla y la parte de atrás del pelo; el borde de delante cruza
    la frente en la línea del pelo (debajo asoma el flequillo) y baja por detrás de la oreja hasta la nuca, donde va
    el nudo con dos puntas que cuelgan."""
    lag, sway = pose.lag, pose.sway
    edge = [(-2.6, 12.8), (0.5, 12.2), (2.8, 9.6), (4.6, 6.8), (7.0, front + 0.2), (12.0, front - 0.2),
            (16.5, front), (20.0, front + 1.0)]
    pts = [H(B, x, y) for x, y in edge]
    yl = edge_line(cv, pts)
    hcx = skull_cx(B)
    vol = min(hair_vol(sp), 1.2)
    rx = B.head['w'] / 2.0 + vol + 0.7
    top = B.hy - vol - 1.0
    cyd = B.hy + B.head['h'] * 0.42
    ry = cyd - top
    clip_hair(cv, B, yl + 0.5)
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    m = (cv.ellipse(hcx, cyd, rx, ry) | ((xs <= hcx + rx - 0.3) & (xs >= hcx - rx + 0.3) & (ys >= cyd))) & (ys <= yl[None, :] + 0.5)
    # la tela se abomba atrás, sobre el moño / la nuca
    m |= cv.ellipse(*H(B, 0.8, 8.0), 3.6, 4.6) & (ys <= yl[None, :] + 0.5)
    p = cv.put(m, mat, mode='top', cast=2, iline=True, band=0.25)
    cv.set_nrm(p, cv.sphere_n(hcx - 1.0, cyd - 1.5, rx + 1.5, ry + 2.5, k=0.85))
    # pliegues que van al nudo
    for (x0, y0) in ((6.0, 1.0), (9.0, 3.5)):
        a = H(B, x0, y0)
        b = H(B, 0.8, 11.0)
        cv.shade(cv.line(bez(a, ((a[0] + b[0]) / 2, a[1] + 1.0), b, 6)), -1, within=[p])
    # dobladillo del borde delantero (la tela doblada): una fila más clara
    hem = m & (ys >= yl[None, :] - 0.6) & (xs >= H(B, 5.0, 0)[0])
    cv.shade(hem, +1, within=[p])
    if dots:
        # lunares sueltos en una grilla rala (nivel fijo: la limpieza no los borra)
        for y in range(int(top) + 1, int(np.max(yl)) + 1):
            for x in range(int(hcx - rx) - 2, int(hcx + rx) + 2):
                if 0 <= x < cv.w and 0 <= y < cv.h and m[y, x] and cv.pid[y, x] == p:
                    if (x * 2 + y * 3) % 7 == 0 and y < yl[x] - 1.0:
                        cv.dot(x, y, dots, 3)
    if knot:
        k = H(B, -0.4, 11.8)
        km = cv.ellipse(k[0], k[1], 1.8, 1.6)
        t1 = cv.poly([(k[0] - 0.5, k[1]), (k[0] - 4.2 + sway, k[1] + 3.6 + lag), (k[0] - 3.4 + sway, k[1] + 5.4 + lag),
                      (k[0] + 0.6, k[1] + 1.2)])
        t2 = cv.poly([(k[0], k[1] + 0.5), (k[0] - 1.6 + sway * 0.6, k[1] + 5.4 + lag), (k[0] + 0.2 + sway * 0.6, k[1] + 6.2 + lag),
                      (k[0] + 1.2, k[1] + 1.0)])
        cv.put(t1 | t2, mat, mode='cyl', cast=0, iline=True, bias=-0.3)
        cv.put(km, mat, mode='top', cast=1, iline=True)
    return p


# ------------------------------------------------------------------ velo de sacerdotisa

def veil_back(cv, B, sp, pose, mat='veil', length=26, **_):
    """La caída del velo por detrás de la cabeza y la espalda (va en la lista 'back')."""
    lag, sway = pose.lag, pose.sway
    m = cv.poly([H(B, 1.0, 2.0), H(B, 17.5, 3.0), H(B, 20.0, 9.0), H(B, 19.5, length * 0.75 + lag * 0.5),
                 H(B, 12.0 + sway, length + lag), H(B, 2.0 + sway * 1.5, length + 1.0 + lag), H(B, -4.2 + sway * 1.5, length - 1.0 + lag),
                 H(B, -3.4, 10.0)])
    p = cv.put(m, mat, mode='cyl', cast=0, band=0.25, bias=-0.35)
    for x0, x1 in ((-0.5, -2.5), (3.5, 2.5), (8.5, 8.0)):
        cv.shade(cv.line([H(B, x0, 12.0), H(B, x1 + sway, length - 0.5 + lag)]), -1, within=[p])
    return p


def veil(cv, B, sp, pose, mat='veil', band=None, length=26, front=5.6, **_):
    """Toca y velo puestos: el velo cubre toda la cabeza y el pelo; la toca (banda) cruza la frente y debajo solo
    asoma el flequillo; a los lados de la cara el velo cae hasta los hombros (el cercano tapa la oreja)."""
    lag, sway = pose.lag, pose.sway
    # borde: banda en la frente, y a los lados el velo baja enmarcando la cara
    edge = [(-3.0, 20.0), (3.6, 20.0), (4.2, 8.0), (5.2, front), (16.8, front), (17.6, 8.0), (18.4, 18.0), (21.0, 18.0)]
    pts = [H(B, x, y) for x, y in edge]
    yl = edge_line(cv, pts)
    x_f0, x_f1 = H(B, 5.0, 0)[0], H(B, 17.0, 0)[0]
    brow = H(B, 0, front)[1]
    for x in range(cv.w):
        if x_f0 <= x <= x_f1:
            yl[x] = brow
    clip_hair(cv, B, yl + 0.5)
    hcx = skull_cx(B)
    vol = 1.0
    rx = B.head['w'] / 2.0 + vol + 1.0
    top = B.hy - vol - 1.2
    cyd = B.hy + B.head['h'] * 0.42
    ry = cyd - top
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    hood = cv.ellipse(hcx, cyd, rx, ry) | ((np.abs(xs - hcx) <= rx) & (ys >= cyd))
    hood &= ys <= yl[None, :] + 0.5
    # los lados caen por fuera de la cara y se abren un poco hacia los hombros
    side_n = cv.poly([H(B, -2.6, 8.0), H(B, 4.4, 8.0), H(B, 4.0, 20.5 + lag * 0.4), H(B, -3.4 + sway * 0.5, 21.5 + lag)])
    side_f = cv.poly([H(B, 17.0, 8.0), H(B, 20.4, 8.0), H(B, 21.0 + sway * 0.3, 19.0 + lag), H(B, 17.4, 18.5 + lag * 0.4)])
    pv = cv.put(hood | side_n, mat, mode='top', cast=2, iline=True, band=0.25)
    cv.set_nrm(pv, cv.sphere_n(hcx - 1.0, cyd - 1.0, rx + 2.0, ry + 4.0, k=0.85))
    pf = cv.put(side_f & ~cv.of(pv), mat, mode='cyl', cast=1, iline=True, bias=-0.4)
    # pliegues del velo a los lados
    cv.shade(cv.line([H(B, 1.0, 9.0), H(B, 0.2 + sway * 0.5, 20.0 + lag)]), -1, within=[pv])
    cv.shade(cv.line([H(B, 3.6, 9.0), H(B, 3.4, 19.0 + lag * 0.4)]), -1, within=[pv])
    if band:
        # toca: banda en la frente (y su borde a los lados de la cara)
        bm = (ys >= brow - 1.8) & (ys <= brow + 0.5) & (xs >= x_f0 - 1.0) & (xs <= x_f1 + 1.0)
        bm |= cv.poly([H(B, 3.4, front - 1.0), H(B, 5.2, front - 1.0), H(B, 5.0, 17.0), H(B, 3.8, 17.0)])
        cv.put(bm & (cv.of(pv) | cv.of(pf)), band, mode='cyl', cast=1, iline=True)
    return pv


# ------------------------------------------------------------------ turbante y capucha

def turban(cv, B, sp, pose, mat='turban', gem='gem', **_):
    """Turbante enrollado: cubre la cabeza y el pelo hasta la frente y las orejas; vueltas en diagonal; joya delante."""
    edge = [(-2.6, 10.6), (1.5, 10.2), (4.5, 8.4), (8.0, 6.6), (12.0, 6.2), (16.0, 6.4), (20.2, 7.6)]
    pts = [H(B, x, y) for x, y in edge]
    yl = edge_line(cv, pts)
    hcx = skull_cx(B)
    rx = B.head['w'] / 2.0 + 2.4
    top = B.hy - 3.6
    cyd = B.hy + B.head['h'] * 0.36
    ry = cyd - top
    clip_hair(cv, B, yl + 0.5)
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    m = (cv.ellipse(hcx, cyd, rx, ry) | ((np.abs(xs - hcx) <= rx - 0.5) & (ys >= cyd))) & (ys <= yl[None, :] + 0.5)
    p = cv.put(m, mat, mode='top', cast=2, iline=True, band=0.3)
    cv.set_nrm(p, cv.sphere_n(hcx - 1.0, cyd - 1.5, rx + 1.5, ry + 2.0, k=0.85))
    # vueltas de la tela: tres arcos en diagonal
    for k in range(3):
        a = (hcx - rx + 1.0, cyd + 2.0 - k * 2.6)
        b = (hcx + rx - 1.0, top + 2.0 + k * 3.0)
        cv.shade(cv.line(bez(a, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - 2.0), b, 8)) & m, -1, within=[p])
    if gem:
        g = (hcx + rx * 0.35, int(np.min(yl[int(hcx):int(hcx + rx)])) - 2.0)
        cv.put(cv.ellipse(g[0], g[1], 1.3, 1.5), gem, mode='shine', iline=True)
        cv.dot(g[0] - 0.4, g[1] - 0.6, 'white', 4)
    return p


def hood(cv, B, sp, pose, mat='hood', part='front', **_):
    """Capucha puesta. part 'back': la tela de atrás (lista 'back'); 'front': el borde que enmarca la cara y cubre la
    cabeza y el pelo (debajo solo asoma el flequillo)."""
    lag, sway = pose.lag, pose.sway
    if part == 'back':
        m = cv.poly([H(B, -3.8, 4.0), H(B, 3.0, -3.0), H(B, 10.0, -3.6), H(B, 19.8, 2.0), H(B, 20.2, 12.0),
                     H(B, 17.0, 21.0), H(B, -1.0 + sway, 22.0 + lag), H(B, -4.4 + sway, 11.0)])
        return cv.put(m, mat, mode='top', cast=0, bias=-0.3)
    front = 4.6
    edge = [(-3.0, 21.0), (3.4, 21.0), (4.0, 9.0), (5.0, front + 0.6), (9.0, front - 0.2), (16.4, front + 0.4),
            (17.6, 9.0), (18.6, 18.0), (21.0, 18.0)]
    pts = [H(B, x, y) for x, y in edge]
    yl = edge_line(cv, pts)
    x_f0, x_f1 = H(B, 4.8, 0)[0], H(B, 17.0, 0)[0]
    clip_hair(cv, B, yl + 0.5)
    hcx = skull_cx(B)
    rx = B.head['w'] / 2.0 + 2.6
    top = B.hy - 3.2
    cyd = B.hy + B.head['h'] * 0.42
    ry = cyd - top
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    m = (cv.ellipse(hcx, cyd, rx, ry) | ((np.abs(xs - hcx) <= rx) & (ys >= cyd))) & (ys <= yl[None, :] + 0.5)
    # punta de la capucha que cae atrás
    m |= cv.poly([H(B, 2.0, -2.5), H(B, -4.4 + sway, 2.0 + lag * 0.5), H(B, -1.0, 4.0)])
    p = cv.put(m, mat, mode='top', cast=2, iline=True, band=0.25)
    cv.set_nrm(p, cv.sphere_n(hcx - 1.0, cyd - 1.0, rx + 2.0, ry + 3.0, k=0.85))
    # borde de la abertura (la tela doblada) un tono más oscuro por dentro
    inner = m & ~np.roll(m, 1, axis=1) | m & ~np.roll(m, -1, axis=1) | m & ~np.roll(m, -1, axis=0)
    cv.shade(inner & (xs >= x_f0 - 1) & (xs <= x_f1 + 1) & (ys >= H(B, 0, front - 1.0)[1]), -1, within=[p])
    cv.shade(cv.line([H(B, 2.0, 6.0), H(B, 1.5, 19.0)]), -1, within=[p])
    return p


# ------------------------------------------------------------------ gorro de cocinero

def chef_hat(cv, B, sp, pose, mat='cloth_w', front=4.8, **_):
    """Gorro de cocinero calado: banda ancha sobre la frente que contiene el pelo y la copa abombada encima."""
    edge = [(-2.6, 8.6), (2.0, 8.2), (5.0, front + 1.2), (9.0, front + 0.2), (16.0, front), (20.0, front + 0.6)]
    pts = [H(B, x, y) for x, y in edge]
    yl = edge_line(cv, pts)
    clip_hair(cv, B, yl + 0.5)
    hcx = skull_cx(B) + 0.3
    rx = B.head['w'] / 2.0 + 1.3
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    band_top = yl - 3.4
    band = (np.abs(xs - hcx) <= rx) & (ys <= yl[None, :] + 0.5) & (ys >= band_top[None, :])
    puff = cv.ellipse(hcx - 3.6, B.hy - 2.0, 4.6, 4.2) | cv.ellipse(hcx + 0.6, B.hy - 3.6, 5.0, 4.6) | \
        cv.ellipse(hcx + 4.6, B.hy - 1.6, 4.2, 4.0)
    puff &= ys <= band_top[None, :] + 1.0
    p = cv.put(puff, mat, mode='top', cast=1, band=0.25)
    cv.shade(cv.line([(hcx - 1.2, B.hy - 5.0), (hcx - 1.6, B.hy - 0.5)]) | cv.line([(hcx + 3.0, B.hy - 5.4), (hcx + 3.2, B.hy - 0.8)]),
             -1, within=[p])
    pb = cv.put(band, mat, mode='cyl', cast=2, iline=True)
    return p
