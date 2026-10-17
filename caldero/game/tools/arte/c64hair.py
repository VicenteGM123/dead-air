"""Pelo por mechones grandes (pasada 4, estilo Octopath Traveler).

Cada mechón es un trazo afinado que termina en punta, con:
  - un tono base (3 = a la luz, 2 = en sombra, 1 = muy al fondo),
  - UNA banda de brillo (2-4 px de largo, 1-2 px de grueso) en su borde de arriba a la izquierda (hacia la luz),
  - 1 px de separación oscura en su borde de abajo a la derecha.
Una cabeza lleva 4-6 mechones grandes más el flequillo; las puntas dibujan picos y ondas en la silueta. Nada de vetas
finas ni píxeles sueltos: 3-4 tonos más el contorno.

Coordenadas de cabeza (como hp() en c64parts): una cabeza de 18 x 20 unidades que se escala a la plantilla real.
"""
import math
import numpy as np
from scipy import ndimage as ndi
from c64core import *
from c64body import GROUND

# dirección de la luz en el plano de la imagen (arriba a la izquierda)
L2 = np.array([-0.70710678, -0.70710678], np.float32)
HW, HH = 18.0, 20.0


def H(B, x, y):
    """Unidades de cabeza -> píxeles del cuadro."""
    return (B.hx + x * B.head['w'] / HW, B.hy + y * B.head['h'] / HH)


def hs_(B):
    """Escala de unidades de cabeza a píxeles (horizontal)."""
    return B.head['w'] / HW


def lid_y(B):
    """Fila del párpado en unidades de cabeza."""
    return (B.head['a'][1][1] - 1) * HH / B.head['h']


def stroke_uv(cv, pts, radii):
    """Trazo por una polilínea con radio variable. Devuelve (máscara, t a lo largo 0..1, rel = distancia al eje /
    radio, nx, ny = dirección unitaria del eje al píxel, largo en px)."""
    pts = [(float(x), float(y)) for x, y in pts]
    if not isinstance(radii, (list, tuple, np.ndarray)):
        radii = [radii] * len(pts)
    n = len(pts)
    seg = [math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(n - 1)]
    total = max(1e-6, sum(seg))
    acc = np.cumsum([0.0] + seg)
    best = np.full((cv.h, cv.w), 1e9, np.float32)
    T = np.zeros((cv.h, cv.w), np.float32)
    NX = np.zeros((cv.h, cv.w), np.float32)
    NY = np.zeros((cv.h, cv.w), np.float32)
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    for i in range(n - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        dx, dy = bx - ax, by - ay
        L2_ = dx * dx + dy * dy
        if L2_ < 1e-9:
            tt = np.zeros_like(xs)
        else:
            tt = np.clip(((xs - ax) * dx + (ys - ay) * dy) / L2_, 0, 1)
        px, py = ax + tt * dx, ay + tt * dy
        vx, vy = xs - px, ys - py
        d = np.sqrt(vx * vx + vy * vy)
        r = radii[i] + (radii[i + 1] - radii[i]) * tt
        rel = d / np.maximum(r, 0.35)
        upd = (rel <= 1.0) & (rel < best)
        if upd.any():
            best[upd] = rel[upd]
            T[upd] = (acc[i] + tt[upd] * seg[i]) / total
            dd = np.maximum(d, 1e-6)
            # en el eje la dirección no existe: se usa la perpendicular del trazo hacia la luz
            perp = np.array([-dy, dx], np.float32) / max(1e-6, math.sqrt(L2_))
            if perp @ L2 < 0:
                perp = -perp
            nxv = np.where(d > 0.25, vx / dd, perp[0] * 0.0)
            nyv = np.where(d > 0.25, vy / dd, perp[1] * 0.0)
            NX[upd] = nxv[upd]
            NY[upd] = nyv[upd]
    m = best <= 1.0
    return m, T, np.where(m, best, 0.0), NX, NY, total


def taper(n, w0, kind='root', w1=0.35, belly=0.35):
    """Radios a lo largo de un mechón. 'root': ancho en la raíz y punta afilada; 'leaf': fino en la raíz, panza
    en el primer tercio y punta; 'even': parejo hasta la punta."""
    out = []
    for i in range(n):
        t = i / max(1, n - 1)
        if kind == 'leaf':
            r = w0 * (0.55 + 0.45 * math.sin(math.pi * min(1.0, t / (2 * belly)) * 0.5 + 0.0)) * (1.0 - t) ** 0.6 + w1 * t
            if t < belly:
                r = w0 * (0.55 + 0.45 * t / belly)
            else:
                r = w0 * ((1.0 - t) / (1.0 - belly)) ** 0.75 + w1 * t * 0.5
        elif kind == 'even':
            r = w0 if t < 0.7 else w0 * (1.0 - (t - 0.7) / 0.3) ** 0.8 + w1 * 0.5
        else:
            r = w0 * (1.0 - t) ** 0.7 + w1 * t
        out.append(max(0.45, r))
    return out


def hlock(cv, pts, radii, mat='hair', base=3, shine=True, shine_at=0.25, shine_len=3.0, sep=True, cast=1, iline=False,
          outline=True, lit_thr=0.15, bright=2, fade=(), sep_d=2, ring=False, **_):
    """Pone un mechón. Su tono lo decide el render según lo que quede visible (ver c64core._shade_locks): base, una
    banda de brillo del lado de la luz (en el tramo visible, a shine_at de su largo visible, shine_len px) y 1 px
    oscuro en su borde de abajo / a la derecha donde toca otro pelo. Devuelve el id de la parte."""
    m, T, REL, NX, NY, L = stroke_uv(cv, pts, radii)
    if not m.any():
        return None
    nn = np.zeros(m.shape + (3,), np.float32)
    nn[..., 2] = 1.0
    p = cv.put(m, mat, mode='stroke', cast=cast, iline=iline, nrm=nn, outline=outline)
    lit = NX * L2[0] + NY * L2[1]
    r_mean = float(np.mean(radii)) if isinstance(radii, (list, tuple, np.ndarray)) else float(radii)
    part = cv.parts[p]
    part.hairy = True
    part.lock = dict(t=T, rel=REL, lit=lit, base=base, shine=shine, shine_at=shine_at, shine_len=shine_len, sep=sep,
                     r=r_mean, len=L, lit_thr=lit_thr, bright=bright, fade=tuple(fade), sep_d=sep_d, ring=ring)
    return p


def hmass(cv, mask, tone=2, mat='hair', cast=0, sep=True, iline=False):
    """Masa de pelo de un solo tono (lo que asoma entre los mechones: casquete, base del pelo de atrás)."""
    p = cv.put(mask, mat, mode='stroke', cast=cast, sep=sep, iline=iline)
    cv.parts[p].hairy = True
    off = 1 if cv.kinds.get(mat) in ('silver', 'white') else 0
    cv.base7[mask & (cv.pid == p)] = min(6, tone + off)
    return p


def lock_pts(B, a, b, c, d=None, n=10):
    """Curva en unidades de cabeza -> puntos en px (Bézier cuadrática o cúbica)."""
    if d is None:
        return bez(H(B, *a), H(B, *b), H(B, *c), n)
    return bez3(H(B, *a), H(B, *b), H(B, *c), H(B, *d), n)


# ------------------------------------------------------------------ casquete (cabeza)

def cap_geometry(B, hs):
    """Centro y radios de la masa de pelo sobre el cráneo (px)."""
    w, h = B.head['w'], B.head['h']
    vol = hs.get('volume', 2.0)
    cx = B.hx + w / 2.0 - 0.5
    cy = B.hy + h * 0.42
    return cx, cy, w / 2.0 + vol, h * 0.42 + vol + 0.4


# mechones del casquete por estilo: (raíz, control1, control2, punta, ancho, tono base) en unidades de cabeza.
# 'n' = lado cercano (nuca / detrás de la oreja, a la izquierda), 'top' = coronilla hacia la frente, 'f' = lado lejano
CAP_LOCKS = {
    'long': [((6.0, -2.4), (0.5, -1.5), (-2.6, 7.0), (-1.6, 16.5), 4.0, 3),
             ((8.5, -2.6), (4.5, 1.0), (2.0, 9.0), (2.6, 18.5), 3.4, 3),
             ((7.0, -2.8), (13.0, -3.6), (19.8, 0.5), (20.0, 9.5), 3.8, 3)],
    'short': [((6.0, -2.4), (0.5, -1.5), (-2.4, 5.5), (-0.6, 12.5), 3.8, 3),
              ((8.5, -2.6), (4.5, 0.5), (2.6, 6.5), (3.0, 12.0), 3.0, 3),
              ((7.0, -2.8), (13.0, -3.6), (19.6, 0.5), (19.6, 8.5), 3.6, 3)],
}

# flequillo por estilo: lista de (x de la raíz, x de la punta, desplazamiento de la punta respecto del párpado,
# ancho, tono base) en unidades de cabeza; de atrás (derecha) hacia delante (izquierda)
BANGS = {
    # 3-4 mechones de ancho y largo distinto (nada de peine): los de la izquierda, a la luz, más claros
    'parted':   [(16.6, 17.6, -0.4, 2.4, 2), (13.2, 14.4, 0.6, 3.0, 2), (9.6, 10.4, -1.4, 2.6, 3), (6.4, 6.0, 0.8, 3.2, 3)],
    'straight': [(16.4, 17.2, 0.0, 2.4, 2), (13.0, 13.8, 0.6, 3.0, 2), (9.8, 10.2, -0.2, 2.8, 3), (6.6, 6.4, 0.8, 3.2, 3)],
    'frieren':  [(16.8, 17.6, 0.0, 2.4, 2), (13.6, 14.2, -0.8, 2.8, 2), (10.6, 10.8, 0.8, 2.6, 3), (7.0, 6.8, -0.4, 3.2, 3)],
    'swept':    [(16.8, 18.4, -1.2, 2.6, 2), (12.6, 15.4, -0.2, 3.2, 2), (8.6, 11.4, -0.8, 3.2, 3), (5.8, 7.4, 0.4, 2.8, 3)],
    'spiky':    [(16.5, 18.6, -1.8, 2.6, 2), (12.8, 14.8, -0.6, 3.0, 2), (9.2, 10.8, -1.8, 2.8, 3), (6.2, 7.0, -0.2, 3.0, 3)],
    'short':    [(16.2, 17.4, -2.2, 3.0, 2), (12.6, 14.0, -1.6, 3.6, 2), (9.0, 10.2, -2.2, 3.6, 3), (6.0, 6.6, -1.2, 3.4, 3)],
    'curly':    [(16.0, 17.0, -1.2, 2.6, 2), (12.6, 13.2, -0.4, 3.0, 2), (9.2, 9.6, -1.4, 2.8, 3), (6.4, 6.2, -0.2, 3.0, 3)],
    'heavy':    [(16.5, 17.4, 0.6, 2.8, 2), (12.8, 13.6, 0.8, 3.2, 2), (9.2, 9.4, 0.6, 3.0, 3), (6.2, 6.0, 1.0, 3.2, 3)],
    'none': [],
}


def face_window(cv, B, hs):
    """Ventana de la cara (lo que el pelo no tapa): de la línea del pelo hacia abajo, entre los mechones laterales."""
    side = hs.get('side', 4.8)
    fr = hs.get('face_r', 17.0)
    hl = hs.get('hairline', 4.0)
    return cv.poly([H(B, side, hl), H(B, fr, hl - 0.5), H(B, fr + 0.4, HH + 3), H(B, side + 0.4, HH + 3)])


def _flow(mask, crown, ang, start=2.5, grav=0.05, step=0.5, maxlen=60):
    """Línea de flujo desde la coronilla con ángulo ang (grados; 0 derecha, 90 abajo), curvada por la gravedad;
    devuelve los puntos dentro de la máscara (sin los primeros 'start' px)."""
    h, w = mask.shape
    x, y = crown
    dx, dy = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    pts, d, seen = [], 0.0, False
    while d < maxlen:
        ix, iy = int(round(x)), int(round(y))
        ok = 0 <= ix < w and 0 <= iy < h and mask[iy, ix]
        if ok:
            seen = True
            if d >= start:
                pts.append((x, y))
        elif seen and d > start:
            break
        vx, vy = dx, dy + grav * d
        l = math.hypot(vx, vy)
        x, y, d = x + vx / l * step, y + vy / l * step, d + step
    return pts


# sectores del casquete (ángulos desde la coronilla: -90 arriba, 0 derecha / frente, 90 abajo, 180 atrás)
CAP_BINS = {'default': [-80, -25, 25, 80, 140, 200, 260]}


def hair_cap(cv, B, sp):
    """Casquete (pasada 4): una masa con 4-6 mechones en abanico desde la coronilla. Cada mechón: tono base, una
    línea oscura de 1 px que lo separa del siguiente y su tramo del 'anillo' de brillo que cruza la cabeza arriba a
    la izquierda (así cada mechón tiene UNA banda de brillo de 2-4 px). Silueta con bultos por mechón."""
    hs = sp.get('hair', {})
    kind = hs.get('kind', 'short')
    long_ = kind in LONG_KINDS
    cx, cy, rx, ry = cap_geometry(B, hs)
    crown = H(B, hs.get('crown_x', 6.0), hs.get('crown_y', -1.0))
    bins = hs.get('cap_bins', CAP_BINS['default'])
    xs, ys = cv.xs.astype(np.float32), cv.ys.astype(np.float32)
    th = np.degrees(np.arctan2(ys - crown[1], xs - crown[0]))
    th = np.where(th < -90, th + 360, th)
    # silueta con un bulto por mechón
    bump = np.zeros(xs.shape, np.float32)
    for a0, a1 in zip(bins[:-1], bins[1:]):
        sel = (th >= a0) & (th < a1)
        c, hw_ = (a0 + a1) / 2.0, max(0.5, (a1 - a0) / 2.0)
        uu = (th[sel] - c) / hw_
        bump[sel] = 0.07 * (1 - uu * uu) - 0.03
    rr = np.sqrt(((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2)
    cap = rr <= 1.0 + bump * hs.get('bumpy', 1.0)
    sl = hs.get('side_len', 18.0 if long_ else 12.5)
    y_sl = H(B, 0, sl)[1]
    win = face_window(cv, B, hs)
    skull = cv.of(B.head_part) & (cv.ys < y_sl)
    # pelo largo: los lados bajan hasta la mandíbula (por fuera de la cara)
    side = np.zeros_like(cap)
    if long_:
        side = cv.poly([H(B, -2.2, 6.0), H(B, 5.0, 6.0), H(B, 5.0, sl), H(B, 1.0, sl + 1.0), H(B, -2.4, sl - 0.5)])
    cap = ((cap & (cv.ys < y_sl + (0 if not long_ else 2))) | skull | side) & ~win
    p = hmass(cv, cap, 3, cast=1, sep=False)
    vis = cap & (cv.pid == p)
    tone = np.full(cap.shape, 3, np.int16)
    # luz de la masa: la mitad de abajo / a la derecha en sombra; más abajo de la oreja, más oscuro
    hcx, hcy = cx, cy - ry * 0.15
    side_d = (xs - hcx) * 0.62 + (ys - hcy) * 0.78
    tone[side_d > rx * 0.42] = 2
    lid_px = B.hy + B.head['a'][1][1]
    tone[(ys > lid_px + 2) & (xs < B.hx + B.head['w'] * 0.4)] = 2
    tone[ys > B.chin - 1] = 2
    # anillo de brillo: banda a ~0.6-0.8 del radio, arriba a la izquierda (de la izquierda a arriba-derecha)
    ang_c = np.degrees(np.arctan2(ys - cy, xs - cx))
    ang_c = np.where(ang_c < 0, ang_c + 360, ang_c)
    r_in, r_out = hs.get('ring', (0.52, 0.80))
    cv.hair_ring = (cx, cy, rx, ry, r_in, r_out)
    ring = (rr >= r_in) & (rr <= r_out) & (ang_c >= 165) & (ang_c <= 320)
    core = (rr >= r_in + 0.06) & (rr <= r_out - 0.06) & (ang_c >= 190) & (ang_c <= 290)
    # líneas de separación entre mechones (de la coronilla hacia fuera) y su margen
    seps = np.zeros(cap.shape, bool)
    for a in bins[1:-1]:
        pts = _flow(cap, crown, a, start=hs.get('sep_start', 2.5))
        if len(pts) >= 2:
            seps |= cv.line(pts)
    near_sep = ndi.binary_dilation(seps, iterations=1)
    tone[ring & ~near_sep] = np.maximum(tone[ring & ~near_sep], 4)
    tone[core & ~near_sep] = 5
    tone[seps] = np.maximum(1, tone[seps] - 2)
    if cv.kinds.get('hair') in ('silver', 'white'):
        tone = np.minimum(6, tone + 1)
    cv.base7[vis] = tone[vis].astype(np.int8)
    return p


def hair_bangs(cv, B, sp):
    """Flequillo: 3-5 mechones que caen de la línea del pelo hasta el párpado, con punta; los de la izquierda (a la
    luz) más claros; proyectan sombra sobre la frente."""
    hs = sp.get('hair', {})
    style = hs.get('bangs', 'parted')
    tips = BANGS.get(style, [])
    if not tips:
        return None
    lid = lid_y(B) + hs.get('bangs_dy', 0)
    s = hs_(B)
    top = hs.get('bangs_top', 0.5)
    first = None
    for (xr, xt, dy, wd, tb) in tips:
        root = (xr - 0.8, top)
        mid = (xr * 0.4 + xt * 0.6 - 0.4, (top + lid + dy) * 0.5)
        tip = (xt, lid + dy)
        pts = lock_pts(B, root, mid, tip, n=10)
        q = hlock(cv, pts, taper(len(pts), wd * s, 'root'), base=tb, shine=False, ring=True, cast=2, sep_d=2,
                  fade=(B.hy + (B.head['a'][1][1] - 3),))
        first = first or q
    return first


def side_lock(cv, B, sp, side='n', length=None, width=2.2, curl=0.0, pose=None):
    """Mechón que enmarca la cara: el cercano cae por delante de la oreja (fuera del ojo cercano), el lejano junto
    a la mejilla lejana (en sombra). Curvo, con panza arriba y punta abajo; más oscuro bajo la mandíbula."""
    hs = sp.get('hair', {})
    L = length if length is not None else hs.get('lock', 18.0)
    lag = pose.lag if pose else 0
    sway = pose.sway if pose else 0
    s = hs_(B)
    w = hs.get('lock_w', width)
    lid_px = B.hy + B.head['a'][1][1]
    if side == 'n':
        x0 = hs.get('side', 4.8) - 0.6
        pts = lock_pts(B, (x0 + 0.8, 4.0), (x0 - 1.0, L * 0.40), (x0 - 0.6 + curl, L * 0.78), (x0 + 0.4 + curl + sway * 0.5, L + lag * 0.6), 14)
        return hlock(cv, pts, taper(len(pts), w * s, 'leaf', belly=0.32), base=3, shine_at=0.10, shine_len=3.0, cast=1,
                     fade=(lid_px + 3, B.chin + 2))
    x0 = hs.get('face_r', 17.0) + 0.8
    pts = lock_pts(B, (x0 - 0.8, 3.0), (x0 + 0.8, L * 0.42), (x0 + 0.9 + curl, L * 0.80), (x0 + 0.2 + curl + sway * 0.5, L * 0.95 + lag * 0.6), 14)
    return hlock(cv, pts, taper(len(pts), w * 0.9 * s, 'leaf', belly=0.32), base=2, shine=False, cast=1, fade=(B.chin + 1,))


LONG_KINDS = ('long', 'wavy', 'twintails', 'braid_back', 'braid_front', 'ponytail', 'bob', 'shaggy')


# ------------------------------------------------------------------ pelo de atrás

def hair_long_back(cv, B, sp, pose):
    """Pelo largo detrás del cuerpo: 4-5 mechones grandes con puntas a distinto largo (picos en la silueta)."""
    hs = sp.get('hair', {})
    L = hs.get('length', 30)
    wid = hs.get('width', 0)
    lag, sway = pose.lag, pose.sway
    cx, cy, rx, ry = cap_geometry(B, hs)
    base = cv.ellipse(cx, cy + 1.0, rx + 0.3, ry + 0.6)
    pb = hmass(cv, base, 1)
    n = hs.get('tips', 5)
    x_l = B.hx - 2.0 - wid
    x_r = B.hx + B.head['w'] + 1.0 + wid * 0.5
    y_end = B.hy + L * B.head['h'] / HH
    out = pb
    order = list(range(n))
    for i in order:
        t = i / (n - 1)
        x0 = x_l + 2.0 + (x_r - x_l - 4.0) * t
        ex = x_l + (x_r - x_l) * t + (t - 0.5) * 2.0 + sway * (1.5 - t)
        ey = y_end + lag * (0.5 + t * 0.5) + (2.0 if i % 2 == 0 else -1.5) - abs(t - 0.5) * 3.0
        pts = bez3((x0, cy - 2.0), (x0 + (t - 0.5) * 5.0, cy + 5.0), (ex - (t - 0.5) * 1.0, (cy + ey) * 0.55 + 3), (ex, ey), 12)
        tb = 3 if t < 0.3 else 2
        hlock(cv, pts, taper(len(pts), 3.0 if 0 < i < n - 1 else 2.5, 'root'), base=tb, shine=(t < 0.4), shine_at=0.10,
              shine_len=3.0, bright=1, cast=0, fade=(B.y_sh + 3,))
    return out


def twin_tail(cv, B, sp, side, pose):
    """Coleta baja (maga elfa): nace detrás de la oreja a la altura de la mandíbula con un lazo, fina en el lazo, se
    llena y cae por fuera del hombro; punta afilada. Un mechón grande: brillo arriba, separación al lado oscuro."""
    hs = sp.get('hair', {})
    L = hs.get('tail_len', 30)
    lag, sway = pose.lag, pose.sway
    tw = hs.get('tail_w', 2.0) * hs_(B)
    out = hs.get('tail_out', 3.0)
    ry = hs.get('tail_root', 15.0)
    if side == 'n':
        root = H(B, 1.0, ry)
        ctrl = [root, H(B, -out * 0.9, ry + 3.5), H(B, -out - 0.8 + sway * 0.5, ry + 6.0 + L * 0.45),
                H(B, -out + 0.4 + sway * 1.5, ry + L + lag)]
    else:
        root = H(B, 17.0, ry)
        ctrl = [root, H(B, HW + out * 0.9, ry + 3.5), H(B, HW + out + 0.6 + sway * 0.5, ry + 6.0 + L * 0.45),
                H(B, HW + out - 0.6 + sway * 1.5, ry + L * 0.94 + lag)]
    main = bez3(*ctrl, 22)
    n = len(main)
    radii = []
    for i in range(n):
        t = i / (n - 1)
        if t < 0.08:
            r = tw * 0.45
        elif t < 0.30:
            r = tw * (0.45 + 0.55 * (t - 0.08) / 0.22)
        elif t < 0.75:
            r = tw * (1.0 - 0.15 * (t - 0.30) / 0.45)
        else:
            r = tw * 0.85 * (1.0 - t) / 0.25
        radii.append(max(0.45, r))
    near = side == 'n'
    p = hlock(cv, main, radii, base=3 if near else 2, shine=near, shine_at=0.10, shine_len=4.0, cast=0 if near else 1,
              bright=2, fade=(B.y_w + 2,))
    # una segunda separación a lo largo (la coleta se ve hecha de dos mechones)
    if near:
        ln = cv.line([(x + 0.4, y) for (x, y) in main[8:-6]])
        cv.parts[p].lock['dark'] = ln
    tie = hs.get('tie')
    if tie:
        tp = main[2]
        cv.put(cv.ellipse(tp[0], tp[1], 1.4, 1.1), tie, mode='shine', iline=True)
    return p


def ponytail(cv, B, sp, pose):
    hs = sp.get('hair', {})
    L = hs.get('tail_len', 22)
    lag, sway = pose.lag, pose.sway
    root = H(B, 2.0, 3.5)
    pts = bez3(root, H(B, -3.0, 3.5), H(B, -4.2 + sway, 9.0 + L * 0.4), H(B, -2.4 + sway * 1.5, 4.0 + L + lag), 14)
    radii = taper(len(pts), hs.get('tail_w', 2.6) * hs_(B), 'leaf', belly=0.3)
    p = hlock(cv, pts, radii, base=3, shine_at=0.12, shine_len=3.5, cast=0, fade=(B.y_sh + 2,))
    tie = hs.get('tie')
    if tie:
        cv.put(cv.ellipse(root[0] - 0.8, root[1] + 0.5, 1.3, 1.5), tie, mode='shine')
    return p


def braid(cv, B, sp, pose, front=False, root=None, length=None):
    """Trenza: cuentas alternadas (cada una un mechoncito con brillo arriba a la izquierda y sombra abajo)."""
    hs = sp.get('hair', {})
    L = length or hs.get('braid_len', 24)
    lag, sway = pose.lag, pose.sway
    if front:
        r = root or H(B, 2.8, 17.0)
        pts = bez3(r, (r[0] - 0.5, r[1] + 4), (r[0] + 0.5 + sway * 0.3, r[1] + L * 0.6), (r[0] + 1.2 + sway * 0.5, r[1] + L + lag), 16)
    else:
        r = root or H(B, 0.5, 9.0)
        pts = bez3(r, (r[0] - 3.5, r[1] + 3), (r[0] - 4.0 + sway, r[1] + L * 0.6), (r[0] - 2.5 + sway * 1.5, r[1] + L + lag), 16)
    seg = max(2, int(L / 2.6))
    first = None
    for i in range(seg):
        t = i / seg
        idx = int(t * (len(pts) - 1))
        x, y = pts[idx]
        w = 2.0 - 0.7 * t
        cxx = x + (0.4 if i % 2 else -0.4)
        a = (cxx - (0.6 if i % 2 else -0.6), y - 0.6)
        b = (cxx + (0.6 if i % 2 else -0.6), y + 2.2)
        q = hlock(cv, [a, b], [w, w * 0.7], base=3 if not front or i < seg - 1 else 2, shine_at=0.0, shine_len=2.0,
                  cast=0, iline=False, bright=1)
        first = first or q
    end = pts[-1]
    tip = cv.poly([(end[0] - 1.3, end[1] - 1), (end[0] + 1.3, end[1] - 1), (end[0] + 0.5, end[1] + 3.0), (end[0] - 0.8, end[1] + 2.5)])
    pt = hmass(cv, tip, 2)
    tie = hs.get('tie')
    if tie:
        cv.put(cv.ellipse(end[0], end[1] - 1.2, 1.6, 1.0), tie, mode='shine', iline=True)
    return first or pt


def bun(cv, B, sp):
    hs = sp.get('hair', {})
    c = H(B, hs.get('bun_x', 1.0), hs.get('bun_y', 3.0))
    r = hs.get('bun_r', 3.2) * hs_(B)
    m = cv.ellipse(c[0], c[1], r, r * 0.9)
    p = hmass(cv, m, 2, cast=1, iline=True)
    # dos mechones enrollados: brillo arriba a la izquierda
    hlock(cv, bez((c[0] - r + 0.8, c[1] + 0.6), (c[0] - 0.4, c[1] - r * 0.9), (c[0] + r - 0.6, c[1] - 0.2), 6),
          [r * 0.45] * 7, base=3, shine_at=0.0, shine_len=2.5, cast=0)
    return p


def curls_back(cv, B, sp, pose):
    """Pelo rizado y abultado (niños, medianos): bolas grandes, cada una con su brillo."""
    out = []
    s = hs_(B)
    for (x, y, r) in ((0.5, 5.0, 3.4), (0.0, 9.5, 3.2), (1.0, 13.0, 2.8), (4.0, 1.0, 3.4), (8.5, -0.5, 3.4), (13.0, 0.5, 3.2),
                      (16.2, 4.0, 2.6)):
        c = H(B, x, y)
        rr = r * s
        m = cv.ellipse(c[0], c[1], rr, rr)
        q = hmass(cv, m, 2 if x > 12 else 3, cast=1)
        lit = (cv.xs - c[0]) * L2[0] + (cv.ys - c[1]) * L2[1]
        cv.base7[m & (lit > rr * 0.45)] = 4
        cv.base7[m & (lit < -rr * 0.5)] = 1
        out.append(q)
    return out[0]


def hair_bob(cv, B, sp, pose):
    """Melena corta hasta la mandíbula: 4 mechones grandes detrás de la cabeza."""
    hs = sp.get('hair', {})
    L = hs.get('bob_len', 19.0)
    lag = pose.lag
    cx, cy, rx, ry = cap_geometry(B, hs)
    base = cv.ellipse(cx, cy + 0.5, rx + 0.2, ry)
    pb = hmass(cv, base, 1)
    s = hs_(B)
    for (x0, x1, l, tb) in ((-1.0, -2.2, L, 2), (2.0, 0.6, L + 1.0, 3), (14.5, 18.6, L - 1.0, 2), (17.0, 19.6, L - 2.0, 1)):
        pts = lock_pts(B, (x0 + 2.0, 3.0), (x0 - 0.5, l * 0.5), (x1, l + lag * 0.5), n=10)
        hlock(cv, pts, taper(len(pts), 3.0 * s, 'root'), base=tb, shine=tb >= 3, shine_at=0.3, cast=0)
    return pb


def hair_wavy_back(cv, B, sp, pose):
    """Pelo largo ondulado detrás del cuerpo: 5 mechones en S con punta."""
    hs = sp.get('hair', {})
    L = hs.get('length', 34)
    lag, sway = pose.lag, pose.sway
    cx, cy, rx, ry = cap_geometry(B, hs)
    base = cv.ellipse(cx, cy + 1.0, rx + 0.3, ry + 0.6)
    pb = hmass(cv, base, 1)
    n = 5
    for i in range(n):
        t = i / (n - 1)
        x0 = H(B, -1.0 + 19.0 * t, 6.0)[0]
        pts = []
        for k in range(13):
            ss = k / 12
            y = cy + (L - 6) * ss * B.head['h'] / HH
            wob = math.sin(ss * math.pi * 2.5 + i) * 1.2
            spread = (t - 0.5) * (6.0 + 5.0 * ss)
            pts.append((x0 + spread * 0.5 + wob + sway * ss * 2, y + lag * ss))
        hlock(cv, pts, taper(len(pts), 2.9, 'root'), base=2 if t < 0.7 else 1, shine=t < 0.5, shine_at=0.25,
              shine_len=3.0, bright=1, cast=0)
    return pb


def ringlets(cv, B, sp, pose):
    """Tirabuzones a los lados de la cara (dama noble)."""
    lag = pose.lag
    for (x, L, tb) in ((2.0, 22.0, 3), (17.0, 20.0, 2)):
        for k in range(4):
            y = 12.0 + k * (L - 12.0) / 3.0
            c = H(B, x + (0.7 if k % 2 else -0.7), y + lag * (k / 3.0))
            hlock(cv, [(c[0] - 0.6, c[1] - 1.2), (c[0] + 0.6, c[1] + 1.4)], [1.7, 1.3], base=tb, shine_at=0.0,
                  shine_len=2.0, cast=1, bright=1)


def hair_ring(cv, B, sp):
    """Calvo: media luna de pelo pegada a la nuca y sobre la oreja (y un poco del lado lejano)."""
    m = cv.poly([H(B, 0.6, 6.0), H(B, 2.6, 4.6), H(B, 4.4, 6.4), H(B, 4.6, 12.6), H(B, 3.2, 14.6), H(B, 0.8, 14.2),
                 H(B, -0.6, 10.5)])
    m &= ~cv.of(B.head_part) | (cv.xs < B.hx + B.head['w'] * 0.32)
    p = hmass(cv, m, 3, cast=1, iline=True)
    lit = (cv.xs - H(B, 2.0, 8.0)[0]) * L2[0] + (cv.ys - H(B, 2.0, 8.0)[1]) * L2[1]
    cv.base7[m & (cv.pid == p) & (lit > 1.0)] = cv.base7[m & (cv.pid == p) & (lit > 1.0)] + 1
    cv.base7[m & (cv.pid == p) & (cv.ys > H(B, 0, 12.0)[1])] -= 1
    far = cv.poly([H(B, 16.6, 7.0), H(B, 18.6, 7.6), H(B, 18.6, 10.6), H(B, 17.2, 10.2)])
    hmass(cv, far, 2, cast=1)
    return p


def hair_spikes(cv, B, sp, pose, n=5, big=1.0):
    """Puntas sobre la coronilla y la nuca (pelo de punta / desgreñado): cada una un mechón con brillo."""
    pts_ = [(-1.0, 7.0, -3.5, 5.5), (0.5, 2.5, -3.0, -1.0), (4.0, -0.5, 1.5, -4.0), (8.5, -1.2, 7.5, -4.8), (13.0, -0.5, 14.5, -3.8),
            (16.5, 2.0, 19.5, -0.5)]
    s = hs_(B)
    for (x, y, tx, ty) in pts_[:n + 1]:
        a = H(B, x, y + 2.5)
        b_ = H(B, x + (tx - x) * big, y + (ty - y) * big)
        pts = bez(a, ((a[0] + b_[0]) / 2 - 0.5, (a[1] + b_[1]) / 2), b_, 6)
        hlock(cv, pts, taper(len(pts), 2.3 * s, 'root'), base=3 if x < 10 else 2, shine_at=0.1, shine_len=2.0, cast=0)


def hair_shaggy_back(cv, B, sp, pose):
    """Melena desordenada hasta la nuca con puntas (lobo, guerreros)."""
    hs = sp.get('hair', {})
    L = hs.get('length', 20)
    lag = pose.lag
    cx, cy, rx, ry = cap_geometry(B, hs)
    base = cv.ellipse(cx, cy + 0.5, rx + 0.4, ry + 0.4)
    pb = hmass(cv, base, 1)
    s = hs_(B)
    for (x0, x1, l, tb) in ((-0.5, -3.5, L + 0.5, 3), (2.5, 0.5, L + 2.0, 2), (5.5, 4.5, L - 1.0, 2), (14.0, 18.0, L - 4.0, 2),
                            (17.0, 20.5, L - 6.0, 1)):
        pts = lock_pts(B, (x0 + 1.5, 4.0), (x0, l * 0.55), (x1, l + lag), n=10)
        hlock(cv, pts, taper(len(pts), 2.8 * s, 'root'), base=tb, shine=tb >= 3, shine_at=0.3, cast=0)
    return pb


# ------------------------------------------------------------------ barbas (mechones grandes, como el pelo)

def _mustache(cv, B, mat, base=3):
    """Bigote: dos mechones cortos que salen de bajo la nariz y caen a los lados de la boca."""
    a3 = (B.head['a'][3][0] * HW / B.head['w'], B.head['a'][3][1] * HH / B.head['h'])
    mx, my = a3
    s = hs_(B)
    hlock(cv, lock_pts(B, (mx + 0.6, my - 1.6), (mx - 1.6, my - 1.4), (mx - 3.2, my + 0.6), n=8), taper(9, 1.3 * s, 'root'),
          mat=mat, base=base, shine_at=0.0, shine_len=2.0, cast=0, sep=False)
    hlock(cv, lock_pts(B, (mx + 0.4, my - 1.6), (mx + 2.6, my - 1.5), (mx + 4.0, my + 0.4), n=8), taper(9, 1.2 * s, 'root'),
          mat=mat, base=base - 1, shine=False, cast=0, sep=False)


def beard(cv, B, sp, pose, kind='full', len=10, mat='beard'):
    """Barbas por mechones: dejan ver ojos, nariz y mejillas (empiezan bajo los pómulos). Cada mechón con su brillo
    arriba y más oscuro hacia la punta; las puntas dibujan picos abajo."""
    L = len
    lag = pose.lag
    s = hs_(B)
    chin = HH
    top_y = B.chin - 1
    if kind in ('full', 'long'):
        if kind == 'full':
            locks = [((3.6, 11.5), (2.4, 15.5), (3.0, chin + L * 0.75), 3.0, 3),
                     ((7.5, 15.5), (6.8, chin + L * 0.4), (7.2, chin + L + lag), 3.0, 3),
                     ((12.0, 16.0), (12.4, chin + L * 0.4), (12.6, chin + L * 0.92 + lag), 3.0, 3),
                     ((17.6, 12.5), (18.6, chin + L * 0.2), (18.2, chin + L * 0.62 + lag), 2.6, 2)]
            mass = cv.poly([H(B, 3.0, 11.0), H(B, 6.0, 15.4), H(B, 12.0, 15.8), H(B, 18.6, 12.0), H(B, 19.4, 15.0),
                            H(B, 18.0, chin + L * 0.55), H(B, 12.5, chin + L * 0.85), H(B, 7.0, chin + L * 0.9),
                            H(B, 2.6, chin + L * 0.6), H(B, 2.0, 14.0)])
        else:
            locks = [((5.2, 14.0), (4.4, chin + L * 0.3), (5.0, chin + L * 0.8 + lag), 2.6, 3),
                     ((10.4, 16.4), (10.0, chin + L * 0.5), (10.2, chin + L + lag), 2.8, 3),
                     ((15.6, 15.0), (16.4, chin + L * 0.4), (15.8, chin + L * 0.85 + lag), 2.4, 2)]
            mass = cv.poly([H(B, 4.5, 13.0), H(B, 9.0, 16.0), H(B, 14.0, 16.0), H(B, 17.4, 13.5), H(B, 17.0, chin + L * 0.5),
                            H(B, 13.0, chin + L * 0.8), H(B, 8.0, chin + L * 0.8), H(B, 4.4, chin + L * 0.5)])
        p0 = hmass(cv, mass, 2, mat=mat, cast=1)
        fade = (B.chin + 2, B.chin + 2 + L * 0.5)
        for (r0, c, tip, w, tb) in locks:
            pts = lock_pts(B, r0, c, tip, n=10)
            hlock(cv, pts, taper(11, w * s, 'root'), mat=mat, base=tb,
                  shine=tb >= 3, shine_at=0.05, shine_len=2.5, cast=1, fade=fade)
        _mustache(cv, B, mat)
        return p0
    if kind == 'short':
        mass = cv.poly([H(B, 3.4, 11.0), H(B, 5.2, 14.6), H(B, 8.5, 17.4), H(B, 13.0, 17.6), H(B, 17.2, 15.6), H(B, 18.6, 12.0),
                        H(B, 19.0, 15.5), H(B, 16.8, chin + 0.6 + lag * 0.5), H(B, 12.0, chin + 2.0), H(B, 7.0, chin + 1.2),
                        H(B, 4.0, chin - 2.5)])
        p0 = hmass(cv, mass, 2, mat=mat, cast=1)
        for (r0, c, tip, w, tb) in (((6.0, 15.0), (6.6, chin), (7.6, chin + 1.6), 1.6, 3),
                                    ((11.0, 17.0), (11.2, chin + 0.8), (11.6, chin + 2.6), 1.6, 3)):
            hlock(cv, lock_pts(B, r0, c, tip, n=6), taper(7, w * s, 'root'), mat=mat, base=tb, shine_at=0.0, shine_len=2.0,
                  cast=0, sep=False)
        _mustache(cv, B, mat)
        return p0
    if kind == 'mustache':
        _mustache(cv, B, mat)
        return None
    if kind == 'stubble':
        # sombra de barba: un plano más oscuro en la mandíbula (sin tramas)
        m = cv.poly([H(B, 6.0, 16.0), H(B, 17.5, 15.4), H(B, 17.0, HH - 0.2), H(B, 9.0, HH + 0.2), H(B, 6.0, HH - 2.0)])
        cv.shade7(m & cv.of(B.head_part) & (cv.force < 0), -1)
        return None
