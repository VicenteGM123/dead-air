"""Partes del personaje 64x96 (estilo HD-2D): cara mínima, pelo por mechones, ropa en capas, calzado.
Cada función pinta en el lienzo (Cv) usando la geometría del cuerpo (Body) y la pose."""
import math
import numpy as np
from c64core import *
from c64core import _norm, _hash
from c64body import GROUND, CX, HEADS

HW, HH = 18.0, 20.0   # cabeza de referencia (coordenadas de hp)


def hp(B, x, y):
    """Punto relativo a la esquina superior izquierda de la cabeza, en unidades de una cabeza de 18x20
    (se escala a la plantilla real: así el mismo peinado sirve para niños, enanos u orcos)."""
    return (B.hx + x * B.head['w'] / 18.0, B.hy + y * B.head['h'] / 20.0)


def ha(B, k):
    """Ancla k de la plantilla de cabeza, en coordenadas del cuadro."""
    ax, ay = B.head['a'][k]
    return (B.hx + ax, B.hy + ay)


def head_center(B):
    return (B.hx + B.head['w'] / 2.0 - 0.5, B.hy + B.head['h'] * 0.46)


def head_form(cv, B, grow=2.5, k=0.78, dy=-1.0):
    """Normales de la 'bola' de la cabeza con el pelo (forma general sobre la que van los mechones)."""
    cx, cy = head_center(B)
    return cv.sphere_n(cx, cy + dy, B.head['w'] / 2 + grow, B.head['h'] / 2 + grow, k=k)


# ------------------------------------------------------------------ cara (mínima: ojos de 1-2 píxeles)

EYE_CODES = {'L': ('lash', 1), 'K': ('lash', 0), 'w': ('eyew', 2), 'v': ('eyew', 1), 'p': ('iris', 0), 'q': ('iris', 1),
             'r': ('iris', 2), 's': ('skin', 1), 'S': ('skin', 0), 'u': ('skin', 3), 'b': ('brow', 1), 'B': ('brow', 0)}

# (ojo cercano, ojo lejano). Pasada 4: el cercano es un bloque de 2 px de ancho y 4 de alto contando el párpado
# (párpado de 3 px con el rabillo hacia fuera; debajo, la pupila de 3 px y la columna clara de 2 px a su lado);
# el lejano, 2x3 (párpado y dos filas). La pupila mira a la derecha (hacia donde mira el personaje).
EYES = {
    #            cercano (rabillo, claro, pupila)              lejano (claro, pupila, rabillo)
    'std':    (["LLL", "_vp", "_wp", "__p"], ["LLL", "vp_", "wp_"]),
    'cute':   (["LLL", "_vp", "_wp", "__p"], ["LLL", "vp_", "wp_"]),
    'kid':    (["LLL", "_vp", "_wp", "__p"], ["LL_", "vp_", "wp_"]),
    'soft':   (["_LL", "Lvp", "_wp", "__p"], ["LL_", "vpL", "wp_"]),
    # serena, párpado bajo sobre el verde (Lirien): la parte clara solo 1 px
    'calm':   (["_ss", "LLL", "_wp", "__p"], ["ss_", "LLL", "wp_"]),
    'man':    (["KLL", "_vp", "_wp", "__q"], ["LLL", "vp_", "wq_"]),
    # severo / mayor: párpado más pesado, parte clara más corta (ojos entornados)
    'stern':  (["KKL", "_Lp", "_wp", "__q"], ["LKK", "Lp_", "wq_"]),
    'fierce': (["K__", "_KL", "_wp", "__p"], ["_LK", "KLL", "wp_"]),
    'old':    (["_LL", "LLL", "_vp", "___"], ["LL_", "LLL", "vp_"]),
    'cat':    (["LLL", "_wp", "_wp", "__p"], ["LLL", "wp_", "wp_"]),
    # alegre: arco oscuro de 2-3 px
    'smile':  (["___", "_L_", "L_L", "___"], ["___", "_L_", "L_L"]),
    'closed': (["___", "___", "LLL", "___"], ["___", "___", "LL_"]),
    'none':   ([], []),
}

BROWS = {
    'thin': (["bb"], ["b"]),
    'man': (["bbb"], ["bb"]),
    'thick': (["BBb"], ["BB"]),
    'up': (["_b", "b_"], ["b"]),
    'old': (["bbb"], ["bb"]),
}

MOUTHS = {
    'small': ["mm"],
    'tiny': ["m"],
    'smile': ["mm"],
    'grin': ["MmM"],
    'open': ["M"],
    'flat': ["mm"],
    'cat': ["m_m"],
    'pout': ["m"],
}
MOUTH_CODES = {'m': ('mouth', 1), 'M': ('mouth', 0), 'o': ('mouth', 0), 't': ('white', 3)}


def _stamp_rows(cv, rows, ox, oy, codes, part):
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '_' or ch not in codes:
                continue
            mat, lvl = codes[ch]
            cv.dot(ox + x, oy + y, mat, lvl, part)


def draw_head(cv, B, sp):
    hd = B.head
    head = cv.put(None, 'skin', mode='soft')
    B.head_part = head
    rows = hd['art'].split('\n')
    m = np.zeros((cv.h, cv.w), bool)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == 'K':
                gx, gy = B.hx + x, B.hy + y
                if 0 <= gx < cv.w and 0 <= gy < cv.h:
                    m[gy, gx] = True
    cv.grow(head, m)
    cx, cy = head_center(B)
    # la cara mira a la derecha: la luz (arriba a la izquierda) deja la mejilla lejana en sombra
    cv.set_nrm(head, cv.sphere_n(cx + 0.5, cy + 2.5, hd['w'] / 2 + 0.5, hd['h'] / 2 + 1.0, k=0.70))
    face = sp.get('face', {})
    style = face.get('eye', 'std')
    near, far = EYES[style]
    a1, a2 = ha(B, 1), ha(B, 2)
    edx = face.get('eye_dx', 0)
    edy = face.get('eye_dy', 0)
    # fila 0 del mapa = párpado (una fila encima del ancla); columna 0 = una a la izquierda (cercano) / el ancla (lejano)
    _stamp_rows(cv, near, a1[0] - 1 + edx, a1[1] - 1 + edy, EYE_CODES, head)
    _stamp_rows(cv, far, a2[0] + edx + face.get('far_dx', 0), a2[1] - 1 + edy, EYE_CODES, head)
    br = face.get('brow')
    if br:
        bn, bf = BROWS[br]
        by = a1[1] + edy - 3 - (len(bn) - 1) + face.get('brow_dy', 0)
        _stamp_rows(cv, bn, a1[0] + edx - 1, by, EYE_CODES, head)
        _stamp_rows(cv, bf, a2[0] + edx, by, EYE_CODES, head)
    mo = face.get('mouth', 'small')
    a3 = ha(B, 3)
    if mo:
        _stamp_rows(cv, MOUTHS[mo], a3[0] + face.get('mouth_dx', 0), a3[1] + face.get('mouth_dy', 0), MOUTH_CODES, head)
    # nariz: un píxel de sombra
    if 7 in hd['a'] and face.get('nose', True):
        n = ha(B, 7)
        cv.dot(n[0] + face.get('nose_dx', 0), n[1], 'skin', 1)
    if face.get('freckles'):
        for (dx, dy) in ((-4, 1), (-2, 2), (3, 1)):
            cv.dot(a1[0] + 1 + dx + 3, a1[1] + 3 + dy, 'skin', 1)
    # modelado de la cara: la mejilla lejana (a la derecha de la nariz) y la mandíbula en sombra,
    # un toque de luz en la mejilla cercana bajo el ojo
    hm = cv.of(head) & (cv.force < 0)
    nx_ = ha(B, 7)[0] if 7 in hd['a'] else a2[0] - 1
    # la mejilla lejana (de la nariz a la derecha) y la mandíbula en sombra: formas grandes, no motas
    far = hm & (cv.xs >= a2[0] + 2) & (cv.ys >= a1[1] + 1)
    cv.shade7(far, -1)
    jaw = hm & (cv.ys >= B.chin - 1) & (cv.xs >= a1[0] - 2)
    cv.shade7(jaw, -1)
    return head


def draw_neck(cv, B, sp):
    cx = B.cx_sh + 1
    w = B.d.get('neck_w', 2.2)
    m = cv.rect(cx - w, B.chin - 3, cx + w - 1, B.y_sh + 2)
    p = cv.put(m, 'skin', mode='cyl')
    # el cuello siempre en sombra bajo la barbilla
    cv.shade(m & (cv.ys <= B.chin + 2), -1, within=[p])
    return p


# ------------------------------------------------------------------ orejas

def ear_human(cv, B, sp):
    a = ha(B, 6)
    m = cv.ellipse(a[0] + 0.3, a[1] + 1.5, 1.3, 2.2)
    p = cv.put(m, 'skin', mode='soft')
    cv.dot(a[0] + 0.5, a[1] + 1.5, 'skin', 1)
    return p


def ear_elf(cv, B, sp, far=False):
    """Oreja larga y puntiaguda, hacia el lado y un poco arriba (la cercana a la izquierda, la lejana a la derecha)."""
    a = ha(B, 6)
    L = sp.get('ear_len', 8)
    up = sp.get('ear_up', 3)
    if far:
        bx, by = B.hx + B.head['w'] - 2.5, a[1] + 1.0
        pts = [(bx - 1, by - 1.5), (bx + L * 0.35, by - up * 0.45 - 1.2), (bx + L * 0.75, by - up - 1.0), (bx + L * 0.40, by - up * 0.1 + 0.6),
               (bx + 0.5, by + 2.5), (bx - 1.5, by + 2.5)]
        return cv.put(cv.poly(pts), 'skin', mode='cyl', bias=-0.4)
    bx, by = a[0] + 1, a[1] + 1
    pts = [(bx + 1.5, by - 1.5), (bx - L * 0.45, by - up * 0.55 - 1.0), (bx - L, by - up - 1.0), (bx - L * 0.55, by - up * 0.2 + 0.5),
           (bx - 1.5, by + 2.5), (bx + 1.5, by + 3.5)]
    p = cv.put(cv.poly(pts), 'skin', mode='cyl', iline=False)
    # sombra interior de la oreja
    inner = cv.line([(bx - 0.5, by + 1), (bx - L * 0.55, by - up * 0.45)])
    cv.shade(inner, -1, within=[p])
    return p


def ears_animal(cv, B, sp, pose, kind='cat'):
    """Orejas de gato / lobo sobre el pelo."""
    big = 1.3 if kind == 'wolf' else 1.0
    out = []
    for i, (bx, lean) in enumerate(((4.0, -1.4), (12.5, 1.0))):
        base_l = hp(B, bx - 3.2 * big, 2.0)
        base_r = hp(B, bx + 3.2 * big, 1.5)
        tip = hp(B, bx + lean * big - 0.5, -6.5 * big)
        m = cv.poly([base_l, tip, base_r])
        p = cv.put(m, 'hair', mode='cyl', cast=0, bias=-0.5 if i == 1 else 0.0)
        inner = cv.poly([hp(B, bx - 1.3 * big, 1.0), hp(B, bx + lean * big - 0.3, -4.2 * big), hp(B, bx + 1.5 * big, 0.8)])
        cv.paint(inner & cv.of(p), 'inner', 1 if i == 0 else 0)
        out.append(p)
    return out


def horns(cv, B, sp, pose):
    out = []
    for (bx, by, dd) in ((4.5, 3.0, -1), (12.5, 2.0, 1)):
        pts = bez(hp(B, bx, by), hp(B, bx + dd * 0.5, by - 4), hp(B, bx + dd * 3.0, by - 5.5), 6)
        m, n = cv.stroke_n(pts, list(np.linspace(1.5, 0.5, len(pts))))
        out.append(cv.put(m, 'horn', mode='stroke', nrm=n, bias=-0.4 if dd > 0 else 0.0))
    return out


# ------------------------------------------------------------------ pelo (mechones)

def _hair_part(cv, m, cast=0, mode='top', mat='hair', band=0.28, sep=True, nrm=None, iline=False, bias=0.0):
    return cv.put(m, mat, mode=mode if nrm is None else 'stroke', cast=cast, band=band, sep=sep, nrm=nrm, iline=iline, bias=bias)


def lock(cv, B, pts, w0, w1=0.5, mat='hair', form=None, mix=0.5, cast=0, iline=True, taper='leaf', bias=0.0, sep=True):
    """Mechón: trazo afinado que sigue pts. Normales de tubo mezcladas con la forma general (form)."""
    n = len(pts)
    radii = []
    for i in range(n):
        t = i / max(1, n - 1)
        if taper == 'leaf':
            r = w0 * (0.70 + 0.45 * math.sin(math.pi * min(1.0, t * 1.4))) * (1.0 - t) ** 0.55 + w1 * t
        elif taper == 'root':
            r = w0 * (1.0 - t) ** 0.8 + w1 * t
        else:
            r = w0 + (w1 - w0) * t
        radii.append(max(0.45, r))
    m, nl = cv.stroke_n(pts, radii)
    nn = nl if form is None else mix_n(form, nl, mix)
    return cv.put(m, mat, mode='stroke', cast=cast, iline=iline, nrm=nn, bias=bias, sep=sep)


def _cap_geometry(B, hs):
    cx = B.hx + B.head['w'] / 2.0 - 0.5
    cy = B.hy + B.head['h'] * 0.42
    vol = hs.get('volume', 3.0)
    rx = B.head['w'] / 2.0 + vol
    ry = B.head['h'] * 0.42 + vol + 0.6
    return cx, cy, rx, ry


def _fan_normals(cv, B, mask, crown, bins, form, mix=0.48, seps=True, sep_from=0.35, rr=None, sep_within=None):
    """Mechones en abanico desde la coronilla: normales de tubo por sector angular + líneas oscuras entre sectores."""
    xs, ys = cv.xs, cv.ys
    th = np.degrees(np.arctan2(ys - crown[1], xs - crown[0]))
    th = np.where(th < -90, th + 360, th)            # -90..270: arriba = -90, derecha = 0, abajo = 90, izquierda = 180
    u = np.zeros(mask.shape, np.float32)
    edge = np.zeros(mask.shape, bool)
    for a0, a1 in zip(bins[:-1], bins[1:]):
        sel = (th >= a0) & (th < a1)
        c, hw_ = (a0 + a1) / 2.0, max(0.5, (a1 - a0) / 2.0)
        u[sel] = (th[sel] - c) / hw_
    thr = np.radians(th)
    px, py = -np.sin(thr), np.cos(thr)     # perpendicular al flujo, hacia el lado de u > 0
    s = np.clip(u, -1, 1) * 0.85
    nl = _norm(px * s, py * s)
    nn = mix_n(form, nl, mix)
    # bordes entre sectores (líneas finas): donde u salta
    du = np.abs(np.diff(u, axis=1, prepend=u[:, :1])) > 1.0
    dv = np.abs(np.diff(u, axis=0, prepend=u[:1, :])) > 1.0
    dist = np.sqrt((xs - crown[0]) ** 2 + (ys - crown[1]) ** 2)
    edge = (du | dv) & mask & (dist > sep_from * 10)
    return nn, edge, u


def hair_cap(cv, B, sp):
    """Casquete de pelo: masa grande que cubre todo el cráneo hasta el párpado y los lados de la cara hasta la
    mandíbula (la cara visible queda pequeña, ~11 px de ancho). Mechones grandes desde la coronilla: líneas de
    separación continuas, brillos en grupos del lado de la luz, contorno abultado."""
    hs = sp.get('hair', {})
    cx, cy, rx, ry = _cap_geometry(B, hs)
    hl = hs.get('hairline', 4.5)
    side = hs.get('side', 4.6)
    fr = hs.get('face_r', 14.6)
    lid = lid_hu(B)
    crown = (cx + hs.get('crown_dx', -1.0), cy - ry * 0.80)
    bins = hs.get('cap_bins', [-70, -20, 8, 34, 58, 80, 100, 122, 146, 170, 196, 225, 270])
    xs, ys = cv.xs, cv.ys
    th = np.degrees(np.arctan2(ys - crown[1], xs - crown[0]))
    th = np.where(th < -90, th + 360, th)
    bump = np.zeros(xs.shape, np.float32)
    for a0, a1 in zip(bins[:-1], bins[1:]):
        sel = (th >= a0) & (th < a1)
        c, hw_ = (a0 + a1) / 2.0, max(0.5, (a1 - a0) / 2.0)
        uu = (th[sel] - c) / hw_
        bump[sel] = 0.10 * (1 - uu * uu) - 0.045
    rr = np.sqrt(((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2)
    cap = rr <= 1.0 + bump * hs.get('bumpy', 1.0)
    win = cv.poly([hp(B, side, hl), hp(B, fr, hl), hp(B, fr, lid + 2.0), hp(B, fr - 0.6, HH + 4), hp(B, side + 0.6, HH + 4),
                   hp(B, side, lid + 2.0)])
    cap &= ~win
    long_ = hs.get('kind') in LONG_KINDS
    sl = hs.get('side_len', 21.0 if long_ else 18.6)
    slf = hs.get('side_len_f', min(sl, 19.0 if long_ else 17.6))
    sw_ = hs.get('side_w', 0.0)
    sidem = cv.poly([hp(B, -2.4 - sw_, 5), hp(B, side + 0.4, 5), hp(B, side + 0.4, lid + 1.0), hp(B, side - 0.2, sl - 1.0),
                     hp(B, side - 1.4, sl), hp(B, 0.2 - sw_, sl - 0.6), hp(B, -2.4 - sw_, 12)])
    sidef = cv.poly([hp(B, fr - 0.2, 5), hp(B, HW + 2.6 + sw_, 5), hp(B, HW + 2.4 + sw_, slf - 1.5), hp(B, HW + 0.6, slf),
                     hp(B, fr + 0.6, slf - 0.6), hp(B, fr - 0.2, lid + 1.0)])
    if hs.get('jag', True):
        sidem = jag_bottom(sidem, period=4, phase=1)
        sidef = jag_bottom(sidef, period=4, phase=3)
    skull = cv.of(B.head_part) & ~win & (cv.ys < B.hy + sl * B.head['h'] / 20.0)
    mask = cap | sidem | sidef | skull
    form = head_form(cv, B, grow=hs.get('volume', 2.4) + 0.5)
    nn, edge, u = _fan_normals(cv, B, mask, crown, bins, form, mix=hs.get('lock_mix', 0.40))
    p = _hair_part(cv, mask, cast=1, sep=False, nrm=nn)
    hair_clumps(cv, p, mask, crown, bins, start=hs.get('clump_start', 2.5))
    if hs.get('strays', 3):
        stray_strands(cv, B, mask, crown, n=hs.get('strays', 3), seed=len(sp.get('name', '')))
    # puntas: el borde exterior de abajo un tono más oscuro (los mechones se separan)
    cv.shade(edge & (rr > 0.85) & (cv.ys > crown[1] + 6), -1, within=[p])
    return p


BANGS = {
    # (x de la punta, desplazamiento de la punta respecto del párpado, ancho de la base), en unidades de cabeza
    'parted':   [(4.6, 0.6, 2.5), (7.0, -0.4, 2.3), (9.4, -2.2, 1.9), (11.6, -0.3, 2.3), (14.0, 0.5, 2.1)],
    'straight': [(4.8, 0.5, 2.3), (7.0, 0.1, 2.1), (9.2, 0.0, 2.0), (11.4, 0.1, 2.0), (13.6, 0.3, 2.0), (15.4, 0.6, 1.7)],
    'frieren':  [(4.6, 0.9, 2.3), (6.8, 0.0, 2.0), (8.8, -1.0, 1.7), (10.4, 0.6, 1.5), (12.4, -0.4, 1.9), (14.4, 0.8, 1.8)],
    'swept':    [(5.0, 0.2, 2.5), (7.8, -0.4, 2.6), (10.8, -0.9, 2.6), (13.8, -0.2, 2.4)],
    'spiky':    [(5.0, 0.0, 2.4), (7.8, -0.8, 2.4), (10.6, -1.2, 2.4), (13.6, -0.6, 2.0)],
    'short':    [(5.2, -1.2, 2.5), (8.0, -1.8, 2.5), (10.8, -2.2, 2.5), (13.6, -1.6, 2.2)],
    'curly':    [(5.0, -0.4, 2.1), (7.4, -1.0, 2.1), (9.8, -1.4, 2.1), (12.2, -1.0, 2.1), (14.4, -0.6, 1.8)],
    'heavy':    [(4.6, 1.0, 2.6), (7.0, 0.6, 2.5), (9.4, 0.2, 2.4), (11.8, 0.6, 2.4), (14.2, 1.0, 2.2)],
    'none': [],
}


def _lock_radii(n, w0, w1=0.45, taper='root'):
    radii = []
    for i in range(n):
        t = i / max(1, n - 1)
        if taper == 'leaf':
            r = w0 * (0.70 + 0.45 * math.sin(math.pi * min(1.0, t * 1.4))) * (1.0 - t) ** 0.55 + w1 * t
        else:
            r = w0 * (1.0 - t) ** 0.8 + w1 * t
        radii.append(max(0.45, r))
    return radii


def locks_union(cv, strokes):
    """Une varios mechones en una sola máscara; en los cruces manda el último (el de delante).
    strokes: lista de (pts, radii). Devuelve (máscara, normales, máscaras por mechón)."""
    m_all = np.zeros((cv.h, cv.w), bool)
    n_all = np.zeros((cv.h, cv.w, 3), np.float32)
    n_all[..., 2] = 1
    each = []
    for pts, radii in strokes:
        m, n = cv.stroke_n(pts, radii)
        n_all[m] = n[m]
        m_all |= m
        each.append(m)
    return m_all, n_all, each


def jag_bottom(m, period=4, phase=0, pattern=None):
    """Borde de abajo en puntas (mechones que terminan en pico): alarga cada columna según un patrón."""
    pattern = pattern or ([0, 1, 2, 1] if period == 4 else [0, 1, 2])
    out = m.copy()
    h = m.shape[0]
    cols = np.flatnonzero(m.any(axis=0))
    for x in cols:
        yb = np.flatnonzero(m[:, x]).max()
        ext = pattern[(x + phase) % len(pattern)]
        if ext:
            out[yb + 1:min(h, yb + 1 + ext), x] = True
    return out


def hair_bangs(cv, B, sp):
    """Flequillo: mechones que caen sobre la frente hasta el párpado (los ojos quedan justo debajo, en la sombra
    del flequillo), con un par de separaciones y sombra proyectada sobre la frente."""
    hs = sp.get('hair', {})
    style = hs.get('bangs', 'parted')
    tips = BANGS[style]
    if not tips:
        return None
    hl = hs.get('hairline', 4.5)
    lid = lid_hu(B) + hs.get('bangs_dy', 0)
    form = head_form(cv, B, grow=hs.get('volume', 2.4) + 0.8)
    cx, cy, rx, ry = _cap_geometry(B, hs)
    base = cv.poly([hp(B, 3.4, hl - 3.0), hp(B, HW + 0.6, hl - 4.0), hp(B, HW + 0.6, hl + 1.0), hp(B, 3.4, hl + 1.6)])
    base &= cv.ellipse(cx, cy, rx + 0.3, ry + 0.3)
    strokes = []
    order = sorted(range(len(tips)), key=lambda i: -tips[i][0])   # de derecha a izquierda: el de la izquierda queda delante
    sweep = hs.get('sweep', 0.0)
    for i in order:
        x, dy, w = tips[i]
        lean = (-0.8 if x < HW * 0.5 else 0.5) + sweep
        root = hp(B, x - lean * 1.2, hl - 3.0)
        mid = hp(B, x - lean * 0.3, (hl - 3.0 + lid + dy) * 0.5)
        tip = hp(B, x + lean * 0.6, lid + dy)
        pts = bez(root, mid, tip, 8)
        strokes.append((pts, _lock_radii(len(pts), w * 0.98)))
    m, nl, each = locks_union(cv, strokes)
    nb = cv.sphere_n(cx, cy, rx, ry)
    nl[base & ~m] = nb[base & ~m]
    mask = m | base
    p = cv.put(mask, 'hair', mode='stroke', cast=2, nrm=mix_n(form, nl, 0.55), sep=False)
    for k, (pts, radii) in enumerate(strokes):
        hl_pts = [(x - radii[i] * 0.45, y) for i, (x, y) in enumerate(pts[1:4], 1)]
        cv.shade(cv.line(hl_pts), +1, within=[p])
    # separaciones finas entre algunos mechones (no todas)
    for k, i in enumerate(order[:-1]):
        if k % 2 == 1:
            continue
        a = each[k] & ~each[k + 1]
        b_ = each[k + 1]
        edge = a & (np.roll(b_, 1, axis=1) | np.roll(b_, -1, axis=1))
        cv.shade(edge & (cv.ys > B.hy + (hl - 1.0) * B.head['h'] / 20.0), -1, within=[p])
    return p


def side_lock(cv, B, sp, side='n', length=None, width=2.4, curl=0.0, pose=None):
    """Mechón que enmarca la cara (n: delante de la oreja, sobre la mejilla cercana; f: junto a la mejilla lejana).
    No tapa los ojos: el cercano cae por fuera del ojo cercano."""
    hs = sp.get('hair', {})
    L = length if length is not None else hs.get('lock', 19)
    lag = pose.lag if pose else 0
    sway = pose.sway if pose else 0
    form = head_form(cv, B, grow=2.5)
    lid = lid_hu(B)
    if side == 'n':
        x0 = hs.get('side', 4.6) - 1.5
        pts = bez3(hp(B, x0 + 0.8, 5.0), hp(B, x0 + 0.3, lid), hp(B, x0 - 0.3 + curl, L * 0.80), hp(B, x0 - 0.1 + curl + sway * 0.6, L + lag * 0.6), 10)
        return lock(cv, B, pts, width * 0.85, 0.5, form=form, mix=0.6, cast=0, iline=True, taper='root')
    x0 = hs.get('face_r', 14.6) + 0.6
    pts = bez3(hp(B, x0 - 0.6, 4.0), hp(B, x0 + 0.4, lid), hp(B, x0 + 0.4 + curl, L * 0.80), hp(B, x0 + curl + sway * 0.6, L + lag * 0.6), 10)
    return lock(cv, B, pts, width * 0.9, 0.5, form=form, mix=0.6, cast=0, iline=True, taper='root', bias=-0.3)


def _mass_form(cv, mask):
    """Forma de una masa de pelo grande (cilindro vertical)."""
    return n_cyl(mask, curv=0.85, vround=3.0)


def _locks_mass(cv, B, roots_tips, widths, mask_extra=None, cast=0, bias=0.0, mix=0.55, sep_lines=True):
    """Masa de pelo hecha de varios mechones (cada uno: lista de puntos). Devuelve los ids."""
    allm = np.zeros((cv.h, cv.w), bool)
    strokes = []
    for pts, w in zip(roots_tips, widths):
        n = len(pts)
        radii = [max(0.5, w * (0.85 + 0.3 * math.sin(math.pi * min(1.0, (i / (n - 1)) * 1.6))) * (1 - (i / (n - 1))) ** 0.45 + 0.4 * (i / (n - 1)))
                 for i in range(n)]
        m, nl = cv.stroke_n(pts, radii)
        strokes.append((m, nl))
        allm |= m
    if mask_extra is not None:
        allm |= mask_extra
    form = _mass_form(cv, allm)
    ids = []
    for (m, nl) in strokes:
        ids.append(cv.put(m, 'hair', mode='stroke', cast=cast, iline=sep_lines, nrm=mix_n(form, nl, mix), bias=bias))
    return ids


def hair_long_back(cv, B, sp, pose):
    """Pelo largo detrás del cuerpo: varios mechones gruesos con puntas a distinto largo."""
    hs = sp.get('hair', {})
    L = hs.get('length', 30)
    wid = hs.get('width', 0)
    lag, sway = pose.lag, pose.sway
    y_end = B.hy + L
    x_l = B.hx - 2.5 - wid
    x_r = B.hx + B.head['w'] + 1.5 + wid * 0.5
    # base (detrás de la cabeza)
    cx, cy, rx, ry = _cap_geometry(B, hs)
    base = cv.ellipse(cx, cy + 1.5, rx + 0.5, ry + 1.0)
    pb = _hair_part(cv, base, cast=0, nrm=head_form(cv, B, grow=3.0), bias=-0.3)
    locks = []
    widths = []
    n = hs.get('tips', 5)
    for i in range(n):
        t = i / (n - 1)
        x0 = x_l + 2.5 + (x_r - x_l - 5.0) * t
        ex = x_l + (x_r - x_l) * t + (t - 0.5) * 2.0 + sway * (1.5 - t)
        ey = y_end + lag * (0.5 + t * 0.5) + (2.5 if i % 2 == 0 else -1.0) - abs(t - 0.5) * 3.0
        pts = bez3((x0, cy - 2.0), (x0 + (t - 0.5) * 6.0, cy + 6.0), (ex - (t - 0.5) * 1.0, (cy + ey) * 0.55 + 4), (ex, ey), 12)
        locks.append(pts)
        widths.append(3.4 if 0 < i < n - 1 else 2.8)
    ids = _locks_mass(cv, B, locks, widths, cast=0, bias=-0.2)
    return ids[0]


def twin_tail(cv, B, sp, side, pose):
    """Coleta baja (estilo maga elfa): nace detrás de la oreja a la altura de la mandíbula con un lazo / adorno,
    fina en el lazo, se llena y cae por fuera del hombro con una separación del cuerpo; punta afilada.
    side n: detrás del hombro cercano (a la izquierda); f: detrás del hombro lejano (a la derecha)."""
    hs = sp.get('hair', {})
    L = hs.get('tail_len', 30)
    lag = pose.lag
    sway = pose.sway
    tw = hs.get('tail_w', 2.6)
    out = hs.get('tail_out', 3.0)
    ry = hs.get('tail_root', 15.0)
    if side == 'n':
        root = hp(B, 1.2, ry)
        ctrl = [root, hp(B, -out * 0.9, ry + 3.5), hp(B, -out - 0.8 + sway * 0.5, ry + 6.0 + L * 0.45),
                hp(B, -out + 0.4 + sway * 1.5, ry + L + lag)]
    else:
        root = hp(B, 16.8, ry)
        ctrl = [root, hp(B, HW + out * 0.9, ry + 3.5), hp(B, HW + out + 0.6 + sway * 0.5, ry + 6.0 + L * 0.45),
                hp(B, HW + out - 0.6 + sway * 1.5, ry + L * 0.94 + lag)]
    main = bez3(*ctrl, 22)
    radii = []
    n = len(main)
    for i in range(n):
        t = i / (n - 1)
        if t < 0.08:
            r = tw * 0.42
        elif t < 0.30:
            r = tw * (0.42 + 0.58 * (t - 0.08) / 0.22)
        elif t < 0.78:
            r = tw * (1.0 - 0.18 * (t - 0.30) / 0.48)
        else:
            r = tw * 0.82 * (1.0 - t) / 0.22
        radii.append(max(0.5, r))
    m_all, n_all = cv.stroke_n(main, radii)
    form = _mass_form(cv, m_all)
    bias = -0.35 if side == 'f' else 0.0
    p = cv.put(m_all, 'hair', mode='stroke', cast=0 if side == 'n' else 1, nrm=mix_n(form, n_all, 0.45), bias=bias)
    # mechones de la coleta: una separación oscura y vetas claras del lado de la luz
    cv.shade(cv.line([(x + 0.7, y) for (x, y) in main[5:-4]]), -1, within=[p])
    cv.shade7(cv.line([(x - 0.9, y) for (x, y) in main[6:-7]]), +2, within=[p])
    cv.shade7(cv.line([(x - 0.2, y) for (x, y) in main[9:-9]]), +1, within=[p])
    tie = hs.get('tie')
    if tie:
        tp = main[2]
        tm = cv.ellipse(tp[0], tp[1], 1.6, 1.2)
        cv.put(tm, tie, mode='shine', iline=True)
    return p


def ponytail(cv, B, sp, pose):
    hs = sp.get('hair', {})
    L = hs.get('tail_len', 22)
    lag, sway = pose.lag, pose.sway
    root = hp(B, 1.5, 4.0)
    pts = bez3(root, hp(B, -4.5, 4.5), hp(B, -5.8 + sway, 10.0 + L * 0.4), hp(B, -3.5 + sway * 1.5, 4.0 + L + lag), 14)
    n = len(pts)
    radii = [max(0.6, hs.get('tail_w', 3.4) * (0.7 + 0.5 * math.sin(math.pi * min(1.0, i / (n - 1) * 1.3))) * (1 - i / (n - 1)) ** 0.5) for i in range(n)]
    m, nl = cv.stroke_n(pts, radii)
    p = cv.put(m, 'hair', mode='stroke', nrm=mix_n(_mass_form(cv, m), nl, 0.5), iline=True)
    cv.shade(cv.line([(x + 0.8, y) for (x, y) in pts[2:-2]]), -1, within=[p])
    tie = hs.get('tie')
    if tie:
        cv.put(cv.ellipse(root[0] - 1.0, root[1] + 0.5, 1.5, 1.8), tie, mode='shine')
    return p


def braid(cv, B, sp, pose, front=False, root=None, length=None):
    """Trenza: cuentas alternadas con sombra entre ellas. front=True cae por delante del hombro cercano."""
    hs = sp.get('hair', {})
    L = length or hs.get('braid_len', 26)
    lag, sway = pose.lag, pose.sway
    if front:
        # nace detrás de la mejilla cercana (bajo el pelo del lado, no sobre la cara) y cae por delante del hombro
        r = root or hp(B, 2.6, 17.5)
        pts = bez3(r, (r[0] - 0.5, r[1] + 5), (r[0] + 0.5 + sway * 0.3, r[1] + L * 0.6), (r[0] + 1.5 + sway * 0.5, r[1] + L + lag), 16)
    else:
        r = root or hp(B, 0.5, 9.0)
        pts = bez3(r, (r[0] - 4.0, r[1] + 3), (r[0] - 4.5 + sway, r[1] + L * 0.6), (r[0] - 3.0 + sway * 1.5, r[1] + L + lag), 16)
    seg = max(2, int(L / 3.0))
    ids = []
    for i in range(seg):
        t = i / seg
        idx = int(t * (len(pts) - 1))
        x, y = pts[idx]
        w = 2.5 - 0.9 * t
        cxx = x + (0.5 if i % 2 else -0.5)
        m = cv.ellipse(cxx, y + 0.8, w, 2.0)
        nrm = cv.sphere_n(cxx - 0.3, y + 0.5, w + 0.6, 2.4, k=0.9)
        ids.append(cv.put(m, 'hair', mode='stroke', nrm=nrm, iline=True, cast=0))
    end = pts[-1]
    tip = cv.poly([(end[0] - 1.6, end[1] - 1), (end[0] + 1.6, end[1] - 1), (end[0] + 0.6, end[1] + 3.5), (end[0] - 1.0, end[1] + 3.0)])
    pt = cv.put(tip, 'hair', mode='cyl', iline=True)
    tie = hs.get('tie')
    if tie:
        cv.put(cv.ellipse(end[0], end[1] - 1.2, 1.8, 1.1), tie, mode='shine', iline=True)
    return ids[0] if ids else pt


def bun(cv, B, sp):
    hs = sp.get('hair', {})
    c = hp(B, hs.get('bun_x', 1.0), hs.get('bun_y', 3.0))
    r = hs.get('bun_r', 3.6)
    m = cv.ellipse(c[0], c[1], r, r * 0.9)
    p = cv.put(m, 'hair', mode='stroke', nrm=cv.sphere_n(c[0], c[1], r + 0.8, r * 0.9 + 0.8), iline=True)
    cv.shade(cv.line(bez((c[0] - r + 1, c[1] + 0.5), (c[0] - 0.5, c[1] - r * 0.6), (c[0] + r - 1.0, c[1] - 0.5), 5)), -1, within=[p])
    return p


def curls_back(cv, B, sp, pose):
    """Pelo rizado y abultado (niños, medianos)."""
    out = []
    for (x, y, r) in ((1.0, 5.0, 3.6), (0.0, 9.0, 3.4), (1.0, 12.5, 3.0), (4.0, 1.5, 3.6), (8.0, 0.0, 3.6), (12.0, 1.0, 3.4),
                      (14.8, 4.0, 2.8), (15.6, 7.5, 2.2)):
        cx, cy = B.hx + x, B.hy + y
        out.append(cv.put(cv.ellipse(cx, cy, r, r), 'hair', mode='stroke', nrm=cv.sphere_n(cx - 0.5, cy - 0.5, r + 1, r + 1), iline=True))
    return out[0]


def beard(cv, B, sp, pose, kind='full', len=10, mat='beard'):
    """Barbas: dejan ver ojos, nariz y mejillas (empiezan bajo la nariz). Mechones con textura."""
    L = len
    lag = pose.lag
    form = head_form(cv, B, grow=2.0, dy=4.0)
    if kind in ('full', 'long'):
        top = 15.6 if kind == 'full' else 16.2
        side = 3.0 if kind == 'full' else 4.0
        pts = [hp(B, side, 10.5), hp(B, 5.5, 13.5), hp(B, 8.0, top), hp(B, 12.0, top - 0.3), hp(B, 18.4, top - 1.0), hp(B, 19.2, top + 1.2),
               hp(B, 18.2, HH + L * 0.45), hp(B, 15.0, HH + L + lag), hp(B, 11.5, HH + L * 0.85 + lag), hp(B, 8.0, HH + L + 1.0 + lag),
               hp(B, 4.5, HH + L * 0.7 + lag), hp(B, 2.0, HH + 1.5), hp(B, side - 1.0, 12.0)]
        m = cv.poly(pts)
        nn = mix_n(form, n_cyl(m), 0.5)
        p_ = cv.put(m, mat, mode='stroke', cast=1, nrm=nn)
        for x in (5.5, 8.5, 11.5, 14.5):
            cv.shade(cv.line(bez(hp(B, x, HH - 1.5), hp(B, x - 0.8, HH + L * 0.4), hp(B, x - 0.2, HH + L * 0.8 + lag), 5)), -1, within=[p_])
        for x in (7.0, 10.0):
            cv.shade(cv.line([hp(B, x, HH), hp(B, x - 0.5, HH + L * 0.5)]), +1, within=[p_])
        # bigote bajo la nariz, cayendo a los lados de la boca
        mus = cv.poly([hp(B, 8.5, top + 0.3), hp(B, 12.0, top - 0.6), hp(B, 16.0, top - 0.4), hp(B, 18.0, top + 1.4), hp(B, 16.5, top + 2.2),
                       hp(B, 12.5, top + 1.2), hp(B, 9.5, top + 2.4), hp(B, 8.0, top + 1.6)])
        cv.put(mus, mat, mode='cyl', cast=1, iline=True)
        return p_
    if kind == 'short':
        pts = [hp(B, 4.0, 12.0), hp(B, 5.6, 15.0), hp(B, 8.5, 18.2), hp(B, 13.5, 18.4), hp(B, 17.6, 16.4), hp(B, 18.6, 16.8),
               hp(B, 17.0, HH + 0.8 + lag * 0.5), hp(B, 12.0, HH + 2.2), hp(B, 7.0, HH + 1.2), hp(B, 4.6, HH - 2.5)]
        m = cv.poly(pts)
        p_ = cv.put(m, mat, mode='stroke', cast=1, nrm=mix_n(form, n_cyl(m), 0.4))
        cv.shade(m & ((cv.xs + cv.ys * 3) % 5 == 0), -1, within=[p_])
        mus = cv.poly([hp(B, 9.8, 16.6), hp(B, 12.5, 15.9), hp(B, 16.5, 16.0), hp(B, 16.8, 17.0), hp(B, 12.5, 16.9), hp(B, 10.0, 17.4)])
        cv.put(mus, mat, mode='cyl', cast=0, iline=True)
        return p_
    if kind == 'mustache':
        a3 = ha(B, 3)
        mus = cv.poly([(a3[0] - 2.5, a3[1] - 0.2), (a3[0] - 0.5, a3[1] - 1.6), (a3[0] + 2.5, a3[1] - 1.4), (a3[0] + 3.0, a3[1] + 0.6),
                       (a3[0] + 1.0, a3[1] - 0.4), (a3[0] - 1.5, a3[1] + 0.8)])
        return cv.put(mus, mat, mode='cyl', cast=0, iline=True)
    if kind == 'stubble':
        m = cv.poly([hp(B, 6.0, 16.5), hp(B, 17.5, 15.8), hp(B, 16.5, HH - 0.5), hp(B, 9.0, HH), hp(B, 6.0, HH - 2.0)])
        cv.shade7(m & cv.of(B.head_part) & (cv.force < 0) & ((cv.xs + cv.ys) % 2 == 0), -1)
        return None


# ------------------------------------------------------------------ cuerpo y ropa

def torso_mask(cv, B, y_bot=None, pad=0.0, chest=True):
    """Torso en 3/4: los hombros siguen la línea inclinada (lean) y la cadera la del peso (sway)."""
    cs, ch_ = B.cx_sh, B.cx_hip
    ysh = B.y_sh
    yb = B.hip_y if y_bot is None else y_bot
    chv = B.d['chest'] if chest else 0

    def cxa(y):
        t = min(1.0, max(0.0, (y - ysh) / max(1.0, B.hip_y - ysh)))
        return cs + (ch_ - cs) * t

    tn = getattr(B, 'turn', 0.0)
    l = cs - B.sw / 2 - pad
    r = cs + B.sw / 2 + pad - 1.4 * tn          # el lado lejano se esconde con el giro
    yw = B.y_w
    pts = [(l + 2.0, ysh - 0.5), (r - 2.0, ysh - 0.5 + 0.4 * tn), (r, ysh + 1.5 + 0.4 * tn), (r + chv * 0.7, ysh + 4),
           (cxa(yw) + B.ww / 2 + pad - 0.8 * tn, yw), (cxa(yb) + B.hw / 2 + pad - 0.8 * tn, yb), (cxa(yb) - B.hw / 2 - pad, yb),
           (cxa(yw) - B.ww / 2 - pad, yw), (l, ysh + 2.5)]
    return cv.poly(pts)


def skirt_mask(cv, B, pose, y_top, y_hem, flare=0.6, widen=0.0, front=1.0):
    """Falda / bajo de túnica: trapecio con vuelo; al caminar se abre y se mece hacia atrás."""
    cx = B.cx_hip
    top_w = B.hw if y_top >= B.hip_y - 1 else B.ww + (B.hw - B.ww) * max(0.0, (y_top - B.y_w) / max(1.0, B.hip_y - B.y_w))
    L = y_hem - y_top
    hem_w = B.hw + L * flare + widen
    st = pose.step
    spread = 1.5 if st in (0, 2) else 0.0
    sway = -1.0 if pose.kind == 'walk' else 0.0
    lag = pose.lag
    l_top, r_top = cx - top_w / 2 - 0.3, cx + top_w / 2 + 0.3
    l_hem = cx - hem_w / 2 - spread + sway * 1.5
    r_hem = cx + hem_w / 2 + spread * front + sway * 0.5
    pts = [(l_top, y_top), (r_top, y_top), (r_top + (r_hem - r_top) * 0.4, y_top + L * 0.5), (r_hem, y_hem + lag * 0.5),
           ((l_hem + r_hem) / 2, y_hem + 1 + lag * 0.5), (l_hem, y_hem - 0.5 + lag), (l_top - (l_top - l_hem) * 0.4, y_top + L * 0.5)]
    return cv.poly(pts), (l_hem, r_hem, y_hem)


def folds(cv, p, B, y0, y1, xs, lag=0, d=-1, light=True):
    """Pliegues: línea oscura con una línea de luz a su izquierda."""
    for (xa, xb) in xs:
        cv.shade(cv.line([(xa, y0), (xb, y1 + lag)]), d, within=[p])
        if light:
            cv.shade(cv.line([(xa - 1, y0 + 1), (xb - 1, y1 + lag - 1)]), +1, within=[p])


def hem_trim(cv, p, mat, y_from, rows=1, lvl=2):
    """Ribete: las últimas filas de la parte p (por columna)."""
    m = cv.of(p)
    if not m.any():
        return None
    out = np.zeros_like(m)
    for x in range(cv.w):
        col = np.where(m[:, x])[0]
        if len(col) == 0:
            continue
        yb = col.max()
        for k in range(rows):
            if yb - k >= y_from and m[yb - k, x]:
                out[yb - k, x] = True
    cv.paint(out, mat, lvl)
    return out


def _limb_n(cv, a, b, ra, rb):
    m, n = cv.capsule_n(a, b, ra, rb)
    return m, n


def leg(cv, B, sp, side, pose):
    """Pierna firme: muslo y canilla como dos cápsulas (rodilla marcada), la lejana más oscura; bota grande."""
    L = B.leg[side]
    lg = sp.get('legs', {})
    kind = lg.get('kind', 'pants')
    mat = lg.get('mat', 'pants') if kind != 'bare' else 'skin'
    tr, sr = B.d['tr'], B.d['sr']
    if kind in ('tights', 'bare'):
        tr, sr = tr * 0.90, sr * 0.92
    if kind == 'baggy':
        tr, sr = tr * 1.15, sr * 1.20
    hip, knee, ank = L['hip'], L['knee'], L['ank']
    kr = (tr + sr) / 2
    m1, n1 = cv.capsule_n(hip, knee, tr, kr)
    m2, n2 = cv.capsule_n(knee, ank, kr, sr * 0.92)
    m = m1 | m2
    nn = np.where(m2[..., None] & ~m1[..., None], n2, n1)
    yh = hem_y(B, sp)
    if yh > B.hip_y + 4:
        m &= cv.ys >= int(yh) - 1
    far = side == 'f'
    p = cv.put(m, mat, mode='stroke', nrm=nn, iline=(side == 'n'), bias=-0.7 if far else 0.0)
    if kind == 'shorts':
        km = m2 & ~cv.capsule(hip, (hip[0] * 0.35 + knee[0] * 0.65, hip[1] * 0.35 + knee[1] * 0.65), tr + 0.6)
        cv.put(km, 'skin', mode='stroke', nrm=n2, iline=(side == 'n'), bias=-0.7 if far else 0.0)
    elif kind not in ('bare',) and m.any():
        # rodilla: un pliegue de sombra corto en la tela
        if L['knee'][1] < cv.h:
            kx, ky = knee
            cv.shade(cv.line([(kx - 0.5, ky), (kx + 1.0, ky + 0.5)]) & cv.of(p), -1)
    feet(cv, B, sp, side, pose)
    return p


def _rot(pts, a, piv):
    ca, sa = math.cos(a), math.sin(a)
    return [(piv[0] + (x - piv[0]) * ca - (y - piv[1]) * sa, piv[1] + (x - piv[0]) * sa + (y - piv[1]) * ca) for x, y in pts]


def foot_shape(B, side, fl, kind='boots'):
    """--- R3 ART3: pie / bota en 3/4 (estilo Octopath): suela plana, talón y punta hacia donde apunta el pie.
    Coordenadas locales: tobillo en (0, 0), x hacia la punta, y hacia abajo, suela en y = 2.5.
    toe (continuo, -1..1): +1 punta a la derecha, -1 a la izquierda, 0 hacia la cámara (escorzo: el pie se ve corto
    y redondo). heel: 0 apoyado, 1 despegue (gira sobre la punta: talón arriba), 2 en el aire (cuelga hacia abajo);
    strike: apoyo de talón (la punta un poco arriba).
    Devuelve (polígono en px, función px -> local, datos) para pintar suela, talón y puntera."""
    L = B.leg[side]
    ax, ay = L['ank']
    toe = float(L['toe'])
    heel = L['heel']
    s = 1.0 if toe >= 0 else -1.0
    at = min(1.0, abs(toe))
    fwd = 0.40 + 0.60 * at                    # escorzo de lo largo del pie
    reach = max(2.2, (fl - 1.2) * fwd)        # del tobillo a la punta
    back = 1.7 * (0.55 + 0.45 * at)           # el talón detrás del tobillo
    wid = 1.0 + (1.0 - at) * 0.9              # con el pie de frente se ve su ancho
    pts = [(-back + 0.2, -1.7), (1.0, -1.7), (reach - 2.0, -0.3), (reach - 0.7, 0.5), (reach + 0.1, 1.5),
           (reach - 0.3, 2.5), (-back - wid * 0.25 + 0.4, 2.5), (-back - wid * 0.25, 1.3)]
    lift = L.get('lift', 0)
    a = 0.0
    if heel == 1:
        piv = (reach - 0.3, 2.5)
        d = math.hypot(piv[0], piv[1])
        a = math.asin(max(-0.9, min(0.9, max(1.0, lift) / max(1.0, d)))) * 1.1
        pts = _rot(pts, a, piv)
        dx_, dy_ = _rot([(0.0, 0.0)], a, piv)[0]
        pts = [(x - dx_, y - dy_) for x, y in pts]
    elif heel == 2:
        a = math.radians(18)
        pts = _rot(pts, a, (0.0, 0.0))
    elif L.get('strike'):
        piv = (-back + 0.3, 2.5)
        a = math.radians(-14)
        pts = _rot(pts, a, piv)
        dx_, dy_ = _rot([(0.0, 0.0)], a, piv)[0]
        pts = [(x - dx_, y - dy_) for x, y in pts]
    world = [(ax + s * x, ay + y) for x, y in pts]
    ca, sa = math.cos(-a), math.sin(-a)

    def to_local(X, Y):
        lx, ly = (X - ax) * s, Y - ay
        return lx * ca - ly * sa, lx * sa + ly * ca
    info = dict(reach=reach, back=back, s=s, a=a, flat=(heel == 0 and not L.get('strike')), at=at)
    return world, to_local, info


def foot_poly(B, side, fl, extra=0.0):
    """Compatibilidad: el polígono del pie (ver foot_shape)."""
    return foot_shape(B, side, fl)[0]


def _foot_details(cv, p, to_local, info, B, side, sole=True, heel_gap=False, cap=True):
    """Suela (fila de abajo más oscura), talón y puntera con luz; en botas con tacón, un hueco de 1 px bajo el arco."""
    m = cv.of(p)
    if not m.any():
        return
    ys_, xs_ = np.nonzero(m)
    lx, ly = to_local(xs_.astype(np.float32), ys_.astype(np.float32))
    reach, back = info['reach'], info['back']
    if sole:
        so = ly >= 1.6
        sm = np.zeros_like(m)
        sm[ys_[so], xs_[so]] = True
        cv.shade(sm, -1, within=[p])
    if cap:
        cp = (lx >= reach - 2.2) & (ly >= -0.6) & (ly <= 0.9)
        cm = np.zeros_like(m)
        cm[ys_[cp], xs_[cp]] = True
        cv.shade7(cm, +1, within=[p])
    if heel_gap and info['flat'] and info['at'] >= 0.55 and reach >= 4.0:
        g = (ly >= 1.6) & (lx >= -0.2) & (lx <= reach * 0.42)
        gm = np.zeros_like(m)
        gm[ys_[g], xs_[g]] = True
        cv.erase(gm & (cv.pid == p))


def feet(cv, B, sp, side, pose):
    """--- R3 ART3: calzado legible: caña (botas), pie con suela, talón y puntera; los pies quietos siempre apoyados."""
    ft = sp.get('feet', {})
    kind = ft.get('kind', 'boots')
    L = B.leg[side]
    knee, ank = L['knee'], L['ank']
    near = side == 'n'
    fl = B.d['foot'] + ft.get('long', 0) + (0.5 if near else 0)
    sr = B.d['sr']
    bias = -0.7 if not near else 0.0
    if kind == 'bare':
        poly, to_local, info = foot_shape(B, side, fl - 1)
        p = cv.put(cv.poly(poly), 'skin', mode='cyl', iline=near, bias=bias)
        _foot_details(cv, p, to_local, info, B, side, sole=False, cap=False)
        return p
    if kind == 'sandals':
        poly, to_local, info = foot_shape(B, side, fl - 0.5)
        m = cv.poly(poly)
        p = cv.put(m, 'skin', mode='cyl', iline=near, bias=bias)
        mat = ft.get('mat', 'leather')
        # suela de cuero bajo el pie y dos tiras (empeine y tobillo)
        ys_, xs_ = np.nonzero(cv.of(p))
        lx, ly = to_local(xs_.astype(np.float32), ys_.astype(np.float32))
        sel = (ly >= 1.7) | ((np.abs(lx - info['reach'] * 0.45) <= 0.6) & (ly >= -0.6)) | ((np.abs(ly + 1.0) <= 0.5) & (lx <= 1.2))
        sm = np.zeros_like(m)
        sm[ys_[sel], xs_[sel]] = True
        cv.paint(sm, mat, 1)
        return p
    mat = ft.get('mat', 'boots')
    h = ft.get('h', 0.5)          # alto de la caña (fracción de la canilla)
    top = (ank[0] + (knee[0] - ank[0]) * h, ank[1] + (knee[1] - ank[1]) * h)
    poly, to_local, info = foot_shape(B, side, fl, kind)
    m = cv.poly(poly)
    if kind == 'shoes':
        top = (ank[0] + (knee[0] - ank[0]) * 0.12, ank[1] + (knee[1] - ank[1]) * 0.12)
        m |= cv.capsule(top, ank, sr + 0.35, sr + 0.4)
    if kind in ('boots', 'greaves', 'sabaton'):
        m |= cv.capsule(top, ank, sr + 0.75, sr + 0.65)
    mode = 'shine' if kind in ('greaves', 'sabaton') else 'cyl'
    p = cv.put(m, mat, mode=mode, iline=near, bias=bias)
    if kind == 'boots':
        # vuelta de la caña
        cuff = cv.capsule((top[0], top[1] - 0.3), (top[0], top[1] + 0.9), sr + 1.1, sr + 1.0)
        cv.put(cuff, ft.get('cuff', mat), mode='cyl', iline=True, bias=bias)
    _foot_details(cv, p, to_local, info, B, side, heel_gap=kind in ('boots', 'greaves'))
    return p


def arm(cv, B, sp, side, pose, layer='sleeve'):
    A = B.arm[side]
    sl = sp.get('sleeves', {})
    kind = sl.get('kind', 'long')
    mat = sl.get('mat', 'top')
    ar = B.d['ar']
    sh, el, hand = A['sh'], A['el'], A['hand']
    near = side == 'n'
    bias = 0.0 if near else -0.55
    mu, nu = cv.capsule_n(sh, el, ar + 0.45, ar)
    mf, nf = cv.capsule_n(el, hand, ar, ar * 0.85)
    sm = mu | mf
    nn = np.where(mf[..., None] & ~mu[..., None], nf, nu)
    if kind in ('long', 'armor', 'wide', 'puff_long'):
        p = cv.put(sm, mat, mode='stroke', nrm=nn, iline=near, cast=1 if near else 0, bias=bias)
        if kind == 'armor':
            cv.parts[p].mode = 'shine'
        if kind == 'wide':
            # manga acampanada que cuelga
            bell = cv.poly([el, (hand[0] - 3.0, hand[1] + 1.8), (hand[0] + 2.6, hand[1] + 1.2), (el[0] + 2.2, el[1])])
            pb = cv.put(bell, mat, mode='cyl', iline=near, cast=1 if near else 0, bias=bias)
            folds(cv, pb, B, el[1] + 1, hand[1], [(el[0] + 0.5, hand[0] - 0.5)], 0)
        if kind == 'puff_long':
            pm = cv.ellipse(sh[0] + 0.3, sh[1] + 1.4, ar + 1.0, ar + 1.5)
            cv.put(pm, mat, mode='stroke', nrm=cv.sphere_n(sh[0], sh[1] + 1, ar + 2.2, ar + 2.6), iline=near, cast=1, bias=bias)
        if sl.get('cuff'):
            cm, cn = cv.capsule_n((el[0] * 0.25 + hand[0] * 0.75, el[1] * 0.25 + hand[1] * 0.75), hand, ar + 0.5, ar * 0.9 + 0.45)
            cv.put(cm, sl['cuff'], mode='stroke', nrm=cn, iline=near, bias=bias)
        if kind == 'armor':
            pad = cv.ellipse(sh[0] + (0.0 if near else 0.5), sh[1] + 0.5, ar + 1.5, ar + 1.1)
            cv.put(pad, sl.get('pad', mat), mode='shine', iline=near, cast=1, bias=bias)
            cv.parts[-1].mode = 'shine'
            cv.set_nrm(len(cv.parts) - 1, cv.sphere_n(sh[0] - 0.5, sh[1], ar + 2.0, ar + 1.6))
    elif kind in ('short', 'puff', 'none', 'rolled'):
        cv.put(sm, 'skin', mode='stroke', nrm=nn, iline=near, cast=1 if near else 0, bias=bias)
        if kind == 'short':
            m2, n2 = cv.capsule_n(sh, (sh[0] * 0.45 + el[0] * 0.55, sh[1] * 0.45 + el[1] * 0.55), ar + 0.45, ar + 0.35)
            cv.put(m2, mat, mode='stroke', nrm=n2, iline=near, cast=1, bias=bias)
        elif kind == 'rolled':
            m2, n2 = cv.capsule_n(sh, (sh[0] * 0.25 + el[0] * 0.75, sh[1] * 0.25 + el[1] * 0.75), ar + 0.35, ar + 0.3)
            cv.put(m2, mat, mode='stroke', nrm=n2, iline=near, cast=1, bias=bias)
            rp = (sh[0] * 0.1 + el[0] * 0.9, sh[1] * 0.1 + el[1] * 0.9)
            roll, rn = cv.capsule_n((rp[0] - 0.01, rp[1] - 0.5), (rp[0] + 0.01, rp[1] + 0.5), ar + 0.55)
            cv.put(roll, mat, mode='stroke', nrm=rn, iline=True, bias=bias)
        elif kind == 'puff':
            pm = cv.ellipse(sh[0] + 0.3, sh[1] + 1.4, ar + 0.6, ar + 1.0)
            cv.put(pm, mat, mode='stroke', nrm=cv.sphere_n(sh[0] - 0.3, sh[1] + 1.0, ar + 1.6, ar + 2.0), iline=near, cast=1, bias=bias)
    return None


def hand(cv, B, sp, side, pose):
    A = B.arm[side]
    el, hd = A['el'], A['hand']
    dx, dy = hd[0] - el[0], hd[1] - el[1]
    d = math.hypot(dx, dy) or 1.0
    c = (hd[0] + dx / d * 1.3, hd[1] + dy / d * 1.3)
    gl = sp.get('gloves')
    mat = gl if gl else 'skin'
    r = B.d['ar'] * 1.0
    m = cv.ellipse(c[0], c[1], r + 0.3, r + 0.6)
    p = cv.put(m, mat, mode='stroke', nrm=cv.sphere_n(c[0] - 0.4, c[1] - 0.4, r + 1.0, r + 1.2), iline=(side == 'n'),
               bias=0.0 if side == 'n' else -0.5)
    if gl and cv.kinds.get(gl) == 'metal':
        cv.parts[p].mode = 'shine'
    A['grip'] = c
    return p


def neckline(cv, B, sp, p_top, kind='round', mat=None):
    cx = B.cx + 1
    y = B.y_sh
    if kind == 'round':
        m = cv.ellipse(cx - 0.5, y - 0.5, 2.8, 1.8)
        cv.erase(m & cv.of(p_top))
        cv.put(m & (cv.ys >= y - 1), 'skin', mode='cyl', bias=-0.6)
    elif kind == 'v':
        m = cv.poly([(cx - 3, y - 1), (cx + 2.5, y - 1), (cx, y + 3.5)])
        cv.erase(m & cv.of(p_top))
        cv.put(m & (cv.ys >= y - 1), 'skin', mode='cyl', bias=-0.5)
    elif kind == 'collar':
        m = cv.poly([(cx - 4.5, y - 1.5), (cx + 4.0, y - 1.5), (cx + 3.5, y + 1.2), (cx - 0.3, y + 2.8), (cx - 4.0, y + 1.2)])
        cv.put(m, mat or 'top', mode='cyl', cast=1, iline=True)
    elif kind == 'high':
        m = cv.rect(cx - 3, y - 2.5, cx + 2.0, y + 0.5)
        cv.put(m, mat or 'top', mode='cyl', cast=1, iline=True)


def belt(cv, B, sp, pose, y=None, mat='belt', buckle='gold', h=2):
    yy = B.y_w + 1.5 if y is None else y
    m = torso_mask(cv, B, y_bot=B.hip_y + 6, pad=0.5) & (cv.ys >= int(yy)) & (cv.ys < int(yy) + h)
    p = cv.put(m, mat, mode='cyl', iline=True, cast=1)
    if buckle:
        bx = B.cx + B.ww * 0.18
        cv.put(cv.rect(int(bx), int(yy), int(bx) + 1, int(yy) + h - 1), buckle, mode='shine', iline=True)
    return p


def pouch(cv, B, sp, pose, mat='leather', x=None, flap=None):
    """Bolsita colgando del cinturón."""
    bx = B.cx - B.ww * 0.35 if x is None else B.cx + x
    by = B.y_w + 3.0
    m = cv.rect(int(bx - 1), int(by), int(bx + 2), int(by + 3))
    p = cv.put(m, mat, mode='cyl', iline=True, cast=1)
    cv.put(cv.rect(int(bx - 1), int(by), int(bx + 2), int(by)), flap or mat, mode='cyl', iline=True)
    return p


def sash(cv, B, sp, pose, mat='sash', tail=True):
    """Fajín ancho en la cintura con un cabo que cuelga."""
    yy = B.y_w + 0.5
    m = torso_mask(cv, B, y_bot=B.hip_y + 6, pad=0.7) & (cv.ys >= int(yy)) & (cv.ys < int(yy) + 3)
    p = cv.put(m, mat, mode='cyl', iline=True, cast=1)
    cv.shade(cv.line([(B.cx - B.ww / 2, yy + 1), (B.cx + B.ww / 2, yy + 1.5)]), -1, within=[p])
    if tail:
        x = B.cx + B.ww * 0.3
        t = cv.poly([(x - 1.0, yy + 1), (x + 1.5, yy + 1), (x + 2.0 + pose.sway, yy + 9 + pose.lag), (x - 0.5 + pose.sway, yy + 9.5 + pose.lag)])
        cv.put(t, mat, mode='cyl', iline=True)
    return p


def apron(cv, B, sp, pose, mat='apron', y_top=None, y_hem=None, bib=True, width=0.8, trim=None, pockets=False):
    cx = B.cx + B.ww * 0.18
    yt = B.y_w if y_top is None else y_top
    if y_hem == 'hip':
        y_hem = B.hip_y + 3
    yh = hem_y(B, sp) - 1 if y_hem is None else y_hem
    w = B.hw * width
    lag = pose.lag
    pts = [(cx - w * 0.45, yt), (cx + w * 0.5, yt), (cx + w * 0.62 + 0.5, yh + lag * 0.5), (cx - w * 0.55 - (1 if pose.kind == 'walk' else 0), yh + lag)]
    m = cv.poly(pts)
    if bib:
        m |= cv.poly([(cx - w * 0.32, B.y_sh + 3), (cx + w * 0.38, B.y_sh + 3), (cx + w * 0.42, yt + 1), (cx - w * 0.38, yt + 1)])
    p = cv.put(m, mat, mode='cyl', iline=True, band=0.25, cast=1)
    folds(cv, p, B, yt + 3, yh - 1, [(cx - 0.5, cx - 1.5), (cx + w * 0.25, cx + w * 0.35)], lag)
    if trim:
        hem_trim(cv, p, trim, yt + 4)
    if pockets:
        for (px0, pw) in ((cx - w * 0.38, 3), (cx + w * 0.12, 3)):
            pm = cv.rect(int(px0), int(yt + 4), int(px0) + pw, int(yt + 7))
            pk = cv.put(pm & cv.of(p), mat, mode='cyl', iline=True)
            cv.shade(cv.rect(int(px0), int(yt + 4), int(px0) + pw, int(yt + 4)) & cv.of(pk), -1)
    # tira del cuello
    if bib:
        cv.put(cv.line([(cx - w * 0.3, B.y_sh + 3), (B.cx - 1, B.y_sh)]), mat, mode='flat')
    return p


# ------------------------------------------------------------------ prendas superiores

def hem_y(B, sp):
    """Fila del bajo de la prenda principal."""
    tp = sp.get('top', {})
    leg = B.d['leg']
    length = tp.get('length', 'hip')
    if not isinstance(length, str):
        return B.hip_y + length
    return {'waist': B.hip_y - 1, 'hip': B.hip_y + 2, 'thigh': B.hip_y + leg * 0.32, 'knee': B.hip_y + leg * 0.55,
            'calf': B.hip_y + leg * 0.75, 'ankle': GROUND - 3, 'floor': GROUND - 1.5}[length]


def top_garment(cv, B, sp, pose):
    """Prenda principal: torso + falda/bajo según el largo."""
    tp = sp.get('top', {})
    mat = tp.get('mat', 'top')
    leg = B.d['leg']
    y_hem = hem_y(B, sp)
    tor = torso_mask(cv, B, y_bot=B.hip_y + 1, pad=tp.get('pad', 0.3))
    p = cv.put(tor, mat, mode='cyl', band=0.26)
    skirt_mat = tp.get('skirt', mat)
    y_top = tp.get('skirt_top', 'waist')
    yt = B.y_w if y_top == 'waist' else B.hip_y - 2
    sk = None
    if y_hem > B.hip_y:
        sm, hem = skirt_mask(cv, B, pose, yt, y_hem, flare=tp.get('flare', 0.45), widen=tp.get('widen', 0.0))
        if tp.get('wavy', True) and y_hem - yt > 8:
            # bajo ondulado: cada pliegue baja un píxel
            nf = max(2, tp.get('folds', 3) + 1)
            l_hem, r_hem, _ = hem
            for x in range(int(l_hem) - 1, int(r_hem) + 2):
                t = (x - l_hem) / max(1.0, r_hem - l_hem)
                if math.sin(t * math.pi * nf * 2.0) > 0.35:
                    col = sm[:, x] if 0 <= x < cv.w else None
                    if col is not None and col.any():
                        yb = np.flatnonzero(col).max()
                        if yb + 1 < cv.h and yb > y_hem - 3:
                            sm[yb + 1, x] = True
        if skirt_mat == mat:
            cv.grow(p, sm)
            sk = p
        else:
            sk = cv.put(sm, skirt_mat, mode='cyl', band=0.26, iline=True)
        # pliegues (oscuro + luz al lado)
        l_hem, r_hem, yh = hem
        n = tp.get('folds', 3)
        for k in range(n):
            t = (k + 1) / (n + 1)
            xa = B.cx - B.ww / 2 + B.ww * t
            xb = l_hem + (r_hem - l_hem) * t + (0.8 if k % 2 else -0.6)
            ya = yt + (y_hem - yt) * 0.30
            cv.shade(cv.line([(xa, ya), (xb, y_hem + pose.lag + 1)]), -1, within=[sk])
            cv.shade(cv.line([(xa + 0.6, ya + (y_hem - ya) * 0.45), (xb + 1, y_hem + pose.lag + 1)]), -1, within=[sk])
            cv.shade(cv.line([(xa - 1, ya + 2), (xb - 1.2, y_hem + pose.lag)]), +1, within=[sk])
        if tp.get('trim'):
            hem_trim(cv, sk, tp['trim'], yt + 2, rows=tp.get('trim_rows', 1))
    if tp.get('front'):
        # línea central (abotonado / abertura de túnica)
        fx = B.cx + B.ww * 0.22
        ln = cv.line([(fx + 0.5, B.y_sh + 1), (fx, B.y_w), (fx - 0.5, y_hem)])
        cv.paint(ln & (cv.of(p) | (cv.of(sk) if sk else False)), tp['front'], 2)
    return p, sk


def coat(cv, B, sp, pose, mat='coat', inner=None, length='knee', lapel=None, trim=None, flare=0.35, folds_n=2):
    """Abrigo largo abierto por delante (deja ver la prenda de dentro en una franja central)."""
    leg = B.d['leg']
    y_hem = {'thigh': B.hip_y + leg * 0.32, 'knee': B.hip_y + leg * 0.55, 'calf': B.hip_y + leg * 0.75, 'ankle': GROUND - 3}.get(length, length)
    tor = torso_mask(cv, B, y_bot=B.hip_y + 1, pad=0.9)
    sm, hem = skirt_mask(cv, B, pose, B.y_w, y_hem, flare=flare)
    m = tor | sm
    fx = B.cx + B.ww * 0.22
    gap = cv.poly([(fx - 0.5, B.y_sh + 2.0), (fx + 1.5, B.y_sh + 2.0), (fx + 2.6, y_hem + 2), (fx - 2.4, y_hem + 2)])
    m &= ~gap
    p = cv.put(m, mat, mode='cyl', iline=True, cast=1)
    l_hem, r_hem, yh = hem
    for k in range(folds_n):
        t = (k + 1) / (folds_n + 1)
        xa = B.cx - B.ww / 2 + B.ww * t * 0.6
        xb = l_hem + (r_hem - l_hem) * t * 0.6
        cv.shade(cv.line([(xa, B.hip_y), (xb, y_hem + pose.lag)]), -1, within=[p])
        cv.shade(cv.line([(xa - 1, B.hip_y + 2), (xb - 1, y_hem + pose.lag - 1)]), +1, within=[p])
    if lapel:
        lm = cv.poly([(fx - 4.0, B.y_sh - 0.5), (fx - 0.2, B.y_sh + 1.5), (fx - 0.6, B.y_w - 2), (fx - 2.5, B.y_sh + 5)])
        lm |= cv.poly([(fx + 1.2, B.y_sh + 1.5), (fx + 4.5, B.y_sh - 0.5), (fx + 3.2, B.y_sh + 5), (fx + 1.6, B.y_w - 2)])
        cv.put(lm & m | lm, lapel, mode='cyl', iline=True, cast=1)
    if trim:
        edge = m & ~np.roll(m, 1, axis=1) | m & ~np.roll(m, -1, axis=1)
        edge &= (cv.xs > fx - 4) & (cv.xs < fx + 4) & (cv.ys > B.y_sh + 2)
        cv.paint(edge, trim, 2)
        hem_trim(cv, p, trim, B.hip_y)
    return p


def capelet(cv, B, sp, pose, mat='cape', trim=None, length=7.0, clasp=None):
    """Capita corta sobre los hombros."""
    cx = B.cx
    y = B.y_sh - 1.0
    lag = pose.lag
    sw = B.sw
    pts = [(cx - 2.0, y - 1.0), (cx + 3.5, y - 1.2), (cx + sw / 2 + 1.6, y + 2.0), (cx + sw / 2 + 2.6, y + length - 0.5 + lag * 0.3),
           (cx + 1.5, y + length + 1.0 + lag * 0.4), (cx - sw / 2 - 1.5, y + length + 0.5 + lag * 0.5), (cx - sw / 2 - 2.6, y + length - 1.0 + lag),
           (cx - sw / 2 - 1.0, y + 1.5)]
    m = cv.poly(pts)
    nn = mix_n(cv.sphere_n(cx, y + length * 0.2, sw / 2 + 4, length + 2), n_cyl(m), 0.4)
    p = cv.put(m, mat, mode='stroke', nrm=nn, cast=1, iline=True)
    if trim:
        hem_trim(cv, p, trim, y + 2)
    for xa, xb in ((cx - 3.5, cx - 4.5), (cx + 2.0, cx + 2.5)):
        cv.shade(cv.line([(xa, y + 2.5), (xb, y + length - 0.5 + lag * 0.4)]), -1, within=[p])
    if clasp:
        cv.put(cv.ellipse(cx + 1.6, y + 1.6, 1.3, 1.3), clasp, mode='shine', iline=True)
    return p


def cape_back(cv, B, sp, pose, mat='cape', length=None, width=3.0, trim=None):
    """Capa larga por detrás (sale por la izquierda y por debajo)."""
    cx = B.cx
    y = B.y_sh
    L = length or (B.hip_y - y + B.d['leg'] * 0.7)
    sway = pose.sway
    lag = pose.lag
    yb = y + L
    pts = [(cx - B.sw / 2 + 1, y - 0.5), (cx + B.sw / 2 - 1, y - 0.5), (cx + B.sw / 2 + 0.5, yb - 4 + lag * 0.3),
           (cx + 1.5 + sway, yb + lag * 0.5), (cx - B.sw / 2 - width + sway * 2, yb - 1.0 + lag),
           (cx - B.sw / 2 - width * 0.6 + sway, y + L * 0.5), (cx - B.sw / 2, y + 2.5)]
    p = cv.put(cv.poly(pts), mat, mode='cyl', cast=0, band=0.3, bias=-0.3)
    for k in range(3):
        xa = cx - B.sw / 2 + 2 + k * 3
        cv.shade(cv.line([(xa, y + L * 0.35), (xa - 1.5 + sway, yb - 1 + lag)]), -1, within=[p])
    if trim:
        hem_trim(cv, p, trim, y + 4)
    return p


def tabard(cv, B, sp, pose, mat='tabard', trim=None, emblem=None, length=None):
    cx = B.cx + B.ww * 0.15
    w = B.ww * 0.66
    y0 = B.y_sh + 1.5
    yb = B.hip_y + (length if length is not None else B.d['leg'] * 0.42)
    lag = pose.lag
    pts = [(cx - w * 0.5, y0), (cx + w * 0.55, y0), (cx + w * 0.62, yb + lag * 0.4), (cx - w * 0.6 - (0.8 if pose.kind == 'walk' else 0), yb + lag)]
    p = cv.put(cv.poly(pts), mat, mode='cyl', iline=True, band=0.25, cast=1)
    if trim:
        hem_trim(cv, p, trim, y0 + 3)
        side = cv.of(p) & ((cv.xs == int(cx - w * 0.5 + 0.5)) | (cv.xs == int(cx + w * 0.55)))
        cv.paint(side & (cv.ys > y0 + 1), trim, 2)
    if emblem:
        ey = B.y_sh + (B.y_w - B.y_sh) * 0.55
        em = cv.poly([(cx - 1.8, ey - 2.0), (cx + 2.2, ey - 2.0), (cx + 2.0, ey + 0.5), (cx + 0.2, ey + 2.6), (cx - 1.6, ey + 0.5)])
        cv.paint(em & cv.of(p), emblem, 2)
        cv.paint(cv.line([(cx + 0.2, ey - 1.5), (cx + 0.2, ey + 1.6)]) & cv.of(p), emblem, 3)
    return p


def scarf(cv, B, sp, pose, mat='scarf', stripe=None, tail=True):
    cx = B.cx + 1
    y = B.y_sh
    m = cv.ellipse(cx - 0.5, y - 0.2, B.sw / 2 - 0.5, 2.8)
    p = cv.put(m, mat, mode='stroke', nrm=cv.sphere_n(cx - 1, y - 1, B.sw / 2 + 1, 4.0), cast=1, iline=True)
    cv.shade(cv.line([(cx - B.sw / 2 + 2, y + 0.5), (cx + B.sw / 2 - 2, y - 0.5)]), -1, within=[p])
    if tail:
        lag = pose.lag
        t = cv.poly([(cx - 3.5, y + 1), (cx - 1.0, y + 1), (cx - 1.5 + pose.sway, y + 10 + lag), (cx - 4.5 + pose.sway * 1.5, y + 9.5 + lag)])
        p2 = cv.put(t, mat, mode='cyl', cast=0, iline=True)
        if stripe:
            cv.paint(cv.of(p2) & ((cv.ys - y).astype(int) % 3 == 0), stripe, 2)
    if stripe:
        cv.paint(cv.of(p) & ((cv.xs + cv.ys) % 4 == 0), stripe, 2)
    return p


def fur_collar(cv, B, sp, pose, mat='fur'):
    """Cuello de piel sobre los hombros: borde abultado con mechones."""
    cx = B.cx + 0.5
    y = B.y_sh
    m = cv.ellipse(cx, y + 0.5, B.sw / 2 + 1.5, 3.4)
    for k in range(-3, 4):
        m |= cv.ellipse(cx + k * B.sw / 7.0, y + 3.2 + (k % 2) * 0.6, 1.6, 1.4)
    p = cv.put(m, mat, mode='stroke', nrm=cv.sphere_n(cx - 1, y - 0.5, B.sw / 2 + 3, 5.0), cast=1, iline=True)
    cv.shade(m & ((cv.xs * 3 + cv.ys * 2) % 5 == 0), -1, within=[p])
    return p


# ------------------------------------------------------------------ más peinados

def hair_bob(cv, B, sp, pose):
    """Melena corta hasta la mandíbula (detrás de la cabeza), por mechones."""
    hs = sp.get('hair', {})
    L = hs.get('bob_len', 19.0)
    lag = pose.lag
    locks = []
    for (x0, x1, l) in ((-1.0, -2.4, L), (2.0, 0.8, L + 1.0), (14.5, 18.8, L - 1.0), (17.0, 19.8, L - 2.0)):
        locks.append(bez(hp(B, x0 + 2.0, 3.0), hp(B, x0 - 0.5, l * 0.5), hp(B, x1, l + lag * 0.5), 8))
    ids = _locks_mass(cv, B, locks, [3.2, 3.0, 3.0, 2.6], mask_extra=cv.ellipse(*hp(B, 9.0, 8.0), B.head['w'] / 2 + 2.0, B.head['h'] * 0.42 + 1.5))
    return ids[0]


def hair_wavy_back(cv, B, sp, pose):
    """Pelo largo ondulado (hasta la cintura), detrás del cuerpo: mechones en S."""
    hs = sp.get('hair', {})
    L = hs.get('length', 34)
    lag, sway = pose.lag, pose.sway
    cx, cy, rx, ry = _cap_geometry(B, hs)
    base = cv.ellipse(cx, cy + 1.5, rx + 0.5, ry + 1.0)
    _hair_part(cv, base, cast=0, nrm=head_form(cv, B, grow=3.0), bias=-0.3)
    locks = []
    n = 5
    for i in range(n):
        t = i / (n - 1)
        x0 = hp(B, -1.0 + 19.0 * t, 6.0)[0]
        pts = []
        for k in range(13):
            s = k / 12
            y = cy + (L - 6) * s * B.head['h'] / 20.0
            wob = math.sin(s * math.pi * 3.0 + i) * 1.3
            spread = (t - 0.5) * (6.0 + 6.0 * s)
            pts.append((x0 + spread * 0.5 + wob + sway * s * 2, y + lag * s))
        locks.append(pts)
    ids = _locks_mass(cv, B, locks, [3.2] * n, cast=0, bias=-0.2)
    return ids[0]


def ringlets(cv, B, sp, pose):
    """Tirabuzones a los lados de la cara (dama noble)."""
    lag = pose.lag
    for (x, L) in ((2.0, 22.0), (16.5, 20.0)):
        for k in range(5):
            y = 12.0 + k * (L - 12.0) / 4.0
            c = hp(B, x + (0.8 if k % 2 else -0.8), y + lag * (k / 4.0))
            cv.put(cv.ellipse(c[0], c[1], 2.1, 1.8), 'hair', mode='stroke', nrm=cv.sphere_n(c[0] - 0.5, c[1] - 0.6, 2.8, 2.5), iline=True, cast=1)


def hair_ring(cv, B, sp):
    """Calvo: corona de pelo alrededor de la nuca y sobre las orejas."""
    m = cv.poly([hp(B, -1.0, 6.5), hp(B, 2.0, 4.5), hp(B, 4.5, 6.0), hp(B, 5.0, 12.5), hp(B, 3.0, 15.0), hp(B, 0.0, 14.5), hp(B, -1.5, 11.0)])
    p = _hair_part(cv, m, cast=1, nrm=mix_n(head_form(cv, B), n_cyl(m), 0.5), iline=True)
    cv.shade(cv.line([hp(B, 1.0, 7.0), hp(B, 1.5, 13.5)]), -1, within=[p])
    far = cv.poly([hp(B, 16.0, 6.5), hp(B, 18.8, 7.5), hp(B, 18.8, 11.0), hp(B, 17.0, 10.5)])
    _hair_part(cv, far, cast=1, nrm=head_form(cv, B), bias=-0.4)
    return p


def hair_spikes(cv, B, sp, pose, n=5, big=1.0):
    """Puntas sobre la coronilla y la nuca (pelo de punta / desgreñado), cada una un mechón."""
    pts = [(-1.0, 7.0, -3.5, 5.5), (0.5, 2.5, -3.0, -1.0), (4.0, -0.5, 1.5, -4.0), (8.5, -1.2, 7.5, -4.8), (13.0, -0.5, 14.5, -3.8), (16.5, 2.0, 19.5, -0.5)]
    form = head_form(cv, B, grow=3.5)
    for (x, y, tx, ty) in pts[:n + 1]:
        a = hp(B, x, y + 2.5)
        b_ = hp(B, x + (tx - x) * big, y + (ty - y) * big)
        lock(cv, B, bez(a, ((a[0] + b_[0]) / 2 - 0.5, (a[1] + b_[1]) / 2), b_, 5), 2.4, 0.4, form=form, mix=0.5, cast=0, iline=True, taper='root')


def hair_shaggy_back(cv, B, sp, pose):
    """Melena desordenada hasta la nuca con puntas (lobo, guerreros)."""
    hs = sp.get('hair', {})
    L = hs.get('length', 20)
    lag = pose.lag
    locks = []
    for (x0, x1, l) in ((-0.5, -3.5, L + 0.5), (2.5, 0.5, L + 2.0), (5.5, 4.5, L - 1.0), (14.0, 18.0, L - 4.0), (17.0, 20.5, L - 6.0)):
        locks.append(bez(hp(B, x0 + 1.5, 4.0), hp(B, x0, l * 0.55), hp(B, x1, l + lag), 8))
    ids = _locks_mass(cv, B, locks, [3.0, 3.2, 2.8, 2.6, 2.4],
                      mask_extra=cv.ellipse(*hp(B, 9.0, 7.0), B.head['w'] / 2 + 2.2, B.head['h'] * 0.42 + 1.5))
    return ids[0]



def hu_y(B, k):
    """Fila del ancla k en unidades de cabeza (0..20), para colocar flequillos a la altura de los ojos."""
    return B.head['a'][k][1] * 20.0 / B.head['h']



def lid_hu(B):
    """Fila del párpado (una encima del ojo) en unidades de cabeza: hasta aquí bajan las puntas del flequillo."""
    return (B.head['a'][1][1] - 1) * 20.0 / B.head['h']

LONG_KINDS = ('long', 'wavy', 'twintails', 'braid_back', 'braid_front', 'ponytail', 'bob', 'shaggy')



def _flow_line(mask, crown, ang, start=3.0, stop=1.0, grav=0.055, step=0.5, maxlen=60):
    """Línea de flujo del pelo: sale de la coronilla con ángulo ang (grados; 0 derecha, 90 abajo) y se curva
    hacia abajo con la distancia. Devuelve los puntos dentro de la máscara (sin los primeros 'start' px)."""
    h, w = mask.shape
    x, y = crown
    dx, dy = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    pts = []
    d = 0.0
    inside_seen = False
    while d < maxlen:
        ix, iy = int(round(x)), int(round(y))
        ok = 0 <= ix < w and 0 <= iy < h and mask[iy, ix]
        if ok:
            inside_seen = True
            if d >= start:
                pts.append((x, y))
        elif inside_seen and d > start:
            break
        vx, vy = dx, dy + grav * d
        l = math.hypot(vx, vy)
        x += vx / l * step
        y += vy / l * step
        d += step
    # recorta 'stop' px del final (la punta queda limpia)
    k = int(stop / step)
    return pts[:-k] if k and len(pts) > k + 1 else pts

def hair_clumps(cv, p, mask, crown, bins, lit=(115, 250), start=3.0, grav=0.055, hl=True, deep=1):
    """Mechones grandes: líneas oscuras continuas entre mechones (curvadas por la gravedad), grumos oscuros
    cortos dentro de los mechones, y muchas vetas claras finas del lado de la luz (en grupos, no parejas)."""
    for a in bins[1:-1]:
        pts = _flow_line(mask, crown, a, start=start, stop=0.5, grav=grav)
        if len(pts) >= 2:
            ln = cv.line(pts)
            cv.shade(ln & mask, -deep, within=[p])
    # grumos oscuros: trazos cortos a mitad de algunos mechones (abajo, donde el pelo se separa)
    for i, (a0, a1) in enumerate(zip(bins[:-1], bins[1:])):
        for k, t in enumerate((0.5,) if i % 2 else ()):
            a = a0 + (a1 - a0) * t
            pts = _flow_line(mask, crown, a, start=start + 2.0, stop=0.5, grav=grav)
            n = len(pts)
            if n < 6:
                continue
            h0 = _hash(i, k, 3)
            s0 = int(n * (0.45 + 0.25 * h0))
            seg = pts[s0:s0 + max(3, int(n * 0.30))]
            if len(seg) >= 2:
                cv.shade7(cv.line(seg) & mask, -2, within=[p])
    if not hl:
        return
    for i, (a0, a1) in enumerate(zip(bins[:-1], bins[1:])):
        mid = (a0 + a1) / 2.0
        if not (lit[0] <= mid <= lit[1]):
            continue
        # vetas: 1-2 trazos finos del lado iluminado del mechón, de largo distinto
        for k, t in enumerate((0.72, 0.45) if i % 2 == 0 else (0.72,)):
            side = a0 + (a1 - a0) * t
            pts = _flow_line(mask, crown, side, start=start + 1.0 + k, stop=0.5, grav=grav)
            n = len(pts)
            if n < 4:
                continue
            h0 = _hash(i, k, 9)
            a_ = int(n * (0.10 + 0.15 * h0))
            b_ = max(a_ + 2, int(n * (0.40 + 0.25 * _hash(i, k, 13))))
            seg = pts[a_:b_]
            if len(seg) >= 2:
                cv.shade7(cv.line(seg) & mask, +2 if k == 0 else +1, within=[p])
                if k == 0 and mid > lit[0] + 15:
                    core = seg[len(seg) // 4: len(seg) // 4 + max(2, len(seg) // 3)]
                    if len(core) >= 2:
                        cv.shade7(cv.line(core) & mask, +1, within=[p])


def stray_strands(cv, B, mask, crown, n=4, seed=0, mat='hair', grav=0.06, length=4.0):
    """Unos pocos pelos sueltos que rompen la silueta: líneas de 1 px, oscuras, que salen del borde de la masa
    siguiendo el flujo (desde la coronilla hacia fuera y abajo)."""
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    # puntos del borde exterior
    edge = mask & ~(np.roll(mask, 1, 0) & np.roll(mask, -1, 0) & np.roll(mask, 1, 1) & np.roll(mask, -1, 1))
    ey, ex = np.nonzero(edge)
    ang = np.degrees(np.arctan2(ey - crown[1], ex - crown[0]))
    out = np.zeros((h, w), bool)
    picks = []
    targets = [-150, -25, 200, -5, 170, 15][:n]
    for i, ta in enumerate(targets):
        diff = np.abs(((ang - ta + 540) % 360) - 180)
        j = int(np.argmin(diff + _hash(i, seed, 21) * 6))
        picks.append((ex[j], ey[j], ta))
    for i, (x, y, ta) in enumerate(picks):
        a = math.radians(ta)
        dx, dy = math.cos(a), math.sin(a)
        L = length * (0.7 + 0.6 * _hash(i, seed, 23))
        pts = []
        px, py = float(x), float(y)
        for s in range(int(L * 2) + 1):
            pts.append((px, py))
            vx, vy = dx, dy + grav * s * 2
            l = math.hypot(vx, vy)
            px += vx / l * 0.5
            py += vy / l * 0.5
        ln = cv.line(pts) & ~mask
        out |= ln
    if not out.any():
        return None
    p = cv.put(out, mat, mode='flat', outline=False)
    cv.force[out] = 0
    return p
