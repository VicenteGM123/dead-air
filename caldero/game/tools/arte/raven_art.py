"""Arte de Krápido (ronda 4, lane RAVEN): el cuervo mensajero Graznido, la ventanilla con su percha, la bola de
cristal (el centro de control de los pedidos) y la interfaz de la bola.

Graznido se dibuja por piezas (cuerpo, pecho, ala, cola, cabeza, pico, gorra de mensajero, cartera con el logo):
cada pieza es una máscara con relieve (la distancia al borde hace de altura), la luz llega de arriba a la izquierda
y por delante, un borde de luz fría por detrás (estilo Octopath) y un contorno oscuro del color de cada pieza.

Uso (desde una carpeta fuera del proyecto: escribe ./salida/... y copia a assets si se le da la carpeta):
    python3 raven_art.py <game>/assets            todo el arte (props, ui) a assets/
    python3 raven_art.py --preview hoja.png        hoja de revisión ampliada (no copia nada)
Necesita pillow, numpy y scipy.
"""
import os, sys, math, json
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from pixlib import hexrgb

OUT = './salida/raven'
SS = 8   # supersampling de las máscaras


# ================================================================== utilidades de dibujo

def rgb(h):
    return np.array(hexrgb(h), np.float32)


def ramp(*hexes):
    return [rgb(h) for h in hexes]


def poly_mask(w, h, pts):
    """Máscara (h, w) de un polígono (coordenadas de píxel, pueden ser decimales; el centro del píxel es +0.5)."""
    im = Image.new('L', (w * SS, h * SS), 0)
    ImageDraw.Draw(im).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    a = np.asarray(im, np.float32).reshape(h, SS, w, SS).mean(axis=(1, 3))
    return a >= 127


def ellipse_pts(cx, cy, rx, ry, ang=0.0, n=48):
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        out.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return out


def ellipse_mask(w, h, cx, cy, rx, ry, ang=0.0):
    return poly_mask(w, h, ellipse_pts(cx, cy, rx, ry, ang))


def rot_pts(pts, cx, cy, ang):
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def move_pts(pts, dx, dy):
    return [(x + dx, y + dy) for x, y in pts]


def pillow_normals(mask, k=2.2):
    """Normales de una forma 'inflada': la distancia al borde hace de altura (más alto en el centro)."""
    d = ndimage.distance_transform_edt(np.pad(mask, 1)).astype(np.float32)[1:-1, 1:-1]
    d = np.sqrt(d)   # bordes redondeados, centro plano
    gy, gx = np.gradient(d)
    n = np.stack([-gx * k, -gy * k, np.ones_like(d)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n


def ellipse_normals(w, h, cx, cy, rx, ry, ang=0.0):
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    dx, dy = xs - cx, ys - cy
    u = (dx * ca + dy * sa) / rx
    v = (-dx * sa + dy * ca) / ry
    r2 = np.clip(u * u + v * v, 0, 0.98)
    nz = np.sqrt(1 - r2)
    nx = u * ca - v * sa
    ny = u * sa + v * ca
    n = np.stack([nx, ny, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n


L_KEY = np.array([-0.5, -0.72, 0.55], np.float32)
L_KEY /= np.linalg.norm(L_KEY)
L_RIM = np.array([0.88, -0.25, -0.35], np.float32)
L_RIM /= np.linalg.norm(L_RIM)


def shade_levels(n, cuts=(0.12, 0.38, 0.62, 0.84)):
    i = np.clip((n * L_KEY).sum(-1), -1, 1)
    lv = np.zeros(i.shape, np.int8)
    for c in cuts:
        lv += (i > c).astype(np.int8)
    return lv


def rim_mask(n, thr=0.5):
    return (n * L_RIM).sum(-1) > thr


def erode(m):
    return ndimage.binary_erosion(m, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]])


def dilate(m):
    return ndimage.binary_dilation(m, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]])


def edge(m):
    return m & ~erode(m)


class Canvas:
    """Lienzo por capas: cada pieza pinta encima de las anteriores y recuerda su color de contorno."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.col = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), bool)
        self.line = np.zeros((h, w, 3), np.float32)   # color del contorno de la pieza de cada píxel

    def paint(self, mask, colors, line):
        """colors: (h, w, 3) o un color; line: color del contorno exterior de esta pieza."""
        if isinstance(colors, np.ndarray) and colors.ndim == 3:
            self.col[mask] = colors[mask]
        else:
            self.col[mask] = colors
        self.a |= mask
        self.line[mask] = line

    def dot(self, x, y, c, line=None):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.col[y, x] = c
            self.a[y, x] = True
            if line is not None:
                self.line[y, x] = line

    def outline(self, extra_dark=0.0):
        """Contorno exterior de 1 px: cada píxel vacío pegado a la figura toma el color de contorno de su vecino."""
        out = np.zeros_like(self.a)
        lc = np.zeros_like(self.col)
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sh_a = np.roll(np.roll(self.a, dy, 0), dx, 1)
            sh_l = np.roll(np.roll(self.line, dy, 0), dx, 1)
            if dy == 1:
                sh_a[0, :] = False
            if dy == -1:
                sh_a[-1, :] = False
            if dx == 1:
                sh_a[:, 0] = False
            if dx == -1:
                sh_a[:, -1] = False
            new = sh_a & ~self.a & ~out
            lc[new] = sh_l[new]
            out |= new
        self.col[out] = lc[out] * (1.0 - extra_dark)
        self.a |= out

    def image(self):
        img = np.zeros((self.h, self.w, 4), np.uint8)
        img[..., :3] = np.clip(self.col, 0, 255).astype(np.uint8)
        img[..., 3] = np.where(self.a, 255, 0)
        return img


def shaded(n, mask, ramp_cols, cuts=(0.12, 0.38, 0.62, 0.84), rim=None, rim_thr=0.5, lift=0):
    lv = np.clip(shade_levels(n, cuts) + lift, 0, len(ramp_cols) - 1)
    cols = np.zeros(mask.shape + (3,), np.float32)
    for i, c in enumerate(ramp_cols):
        cols[lv == i] = c
    if rim is not None:
        rm = rim_mask(n, rim_thr) & mask & (lv <= 2)
        cols[rm] = rim
    return cols, lv


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(img, 'RGBA').save(path)


# ================================================================== paleta

FEATHER = ramp('#0b0a12', '#15131f', '#201e30', '#2e2d47', '#424a72')
SHEEN = rgb('#5f6cab')
RIM_COOL = rgb('#3f4a80')
FEATHER_LINE = rgb('#040307')
BEAK = ramp('#15141a', '#26252d', '#383741', '#51505c', '#73727f')
LEG = ramp('#17161c', '#28262e', '#3b3843', '#4f4c58')
CAP = ramp('#4a0f18', '#781b26', '#a62a33', '#cc4442', '#ec7a62')
CAP_LINE = rgb('#24060b')
LEATHER = ramp('#3a1f12', '#5a321c', '#7b4828', '#9d6237', '#c0834f')
LEATHER_LINE = rgb('#1c0e07')
GOLD = ramp('#7a5216', '#b07c22', '#e0aa38', '#f5d060', '#fff0a8')
GOLD_LINE = rgb('#3a2608')
EYE_W = rgb('#dcdff0')
EYE_P = rgb('#07060f')
WHITE = rgb('#ffffff')


# ================================================================== Graznido

FW, FH = 64, 64   # cuadro del cuervo


def _feather_texture(cols, lv, mask, axis_ang, spacing, phase, ox, oy, strength=1):
    """Hileras de plumas (escamas) dentro de una pieza: líneas un tono más oscuras cada `spacing` píxeles."""
    h, w = mask.shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    ca, sa = math.cos(math.radians(axis_ang)), math.sin(math.radians(axis_ang))
    along = (xs - ox) * ca + (ys - oy) * sa
    across = -(xs - ox) * sa + (ys - oy) * ca
    wave = np.floor((along + phase + 0.9 * np.abs(np.sin(across * 0.9))) / spacing)
    line = (np.mod(along + phase + 0.9 * np.abs(np.sin(across * 0.9)), spacing) < 1.0) & mask & ~edge(mask)
    return line


def draw_raven(p):
    """p: dict de pose. Devuelve (imagen RGBA 64x64, info) con info = puntos útiles (punta del pico, cartera...)."""
    pose = p.get('pose', 'perch')
    cv = Canvas(FW, FH)
    info = {}
    hop = p.get('hop', 0.0)
    crouch = p.get('crouch', 0.0)
    ruffle = p.get('ruffle', 0.0)
    head_rot = p.get('head_rot', 0.0)
    head_dx, head_dy = p.get('head_dx', 0.0), p.get('head_dy', 0.0)
    beak_open = p.get('beak_open', 0.0)
    wing = p.get('wing', 'fold')
    oy = -hop + crouch * 2.0
    rf = 1.0 + 0.09 * ruffle
    if pose == 'perch':
        body_c = (30.0, 43.0 + oy)
        body_r = (9.8 * rf, 13.0 * (1 + 0.05 * ruffle))
        body_ang = -24.0
        chest_c = (36.0, 36.5 + oy)
        chest_r = (7.4 * rf, 8.4 * rf)
        head_c = (41.0 + head_dx, 23.5 + oy + crouch * 1.5 + head_dy)
        neck = (38.0, 31.0 + oy)
        head_r = 9.0 * (1 + 0.05 * ruffle)
    else:   # en vuelo: el cuerpo horizontal
        body_c = (32.0, 33.0 + oy)
        body_r = (13.0, 7.4)
        body_ang = -8.0
        chest_c = (40.0, 32.0 + oy)
        chest_r = (7.0, 6.5)
        head_c = (47.5 + head_dx, 27.0 + oy + head_dy)
        neck = (44.0, 30.0 + oy)
        head_r = 7.8
    hrot = lambda pts: rot_pts(pts, neck[0], neck[1], head_rot)

    # ---- ala del otro lado (solo en vuelo, detrás de todo)
    if pose == 'fly':
        far = _wing_pts(wing, oy, far=True)
        m = poly_mask(FW, FH, far)
        n = pillow_normals(m, 1.6)
        cols, lv = shaded(n, m, [FEATHER[0], FEATHER[0], FEATHER[1], FEATHER[1], FEATHER[2]])
        cv.paint(m, cols, FEATHER_LINE)

    # ---- cola (cuña de plumas largas)
    if pose == 'perch':
        tail = [(22.5, 49.0 + oy), (28.0, 52.5 + oy), (17.5, 63.6), (9.0, 62.6)]
        tail_ang = 125.0
    else:
        spread = {'up': 2.0, 'mid': 1.0, 'down': 0.0, 'glide': 1.5}.get(wing, 1.0)
        tail = [(21.0, 30.0 + oy), (22.0, 36.5 + oy), (7.0, 41.5 + oy + spread), (5.5, 30.0 + oy - spread)]
        tail_ang = 180.0
    tm = poly_mask(FW, FH, tail)
    n = pillow_normals(tm, 1.8)
    cols, lv = shaded(n, tm, FEATHER, rim=RIM_COOL, rim_thr=0.55)
    tl = _feather_texture(cols, lv, tm, tail_ang - 90.0, 3.0, 0.5, tail[0][0], tail[0][1])
    cols[tl] = FEATHER[0]
    cv.paint(tm, cols, FEATHER_LINE)

    # ---- patas (finas, con dedos que agarran la percha)
    if pose == 'perch':
        leg_top = 52.0 + oy
        for lx in (28.6, 33.4):
            m = poly_mask(FW, FH, [(lx - 0.7, leg_top), (lx + 1.1, leg_top), (lx + 1.0, 59.4), (lx - 0.6, 59.4)])
            cv.paint(m, LEG[2], FEATHER_LINE)
            toes = poly_mask(FW, FH, [(lx - 2.0, 59.0), (lx + 3.6, 59.0), (lx + 3.9, 60.5), (lx - 2.2, 60.5)])
            cv.paint(toes, LEG[1], FEATHER_LINE)
            cv.dot(lx + 3.4, 59.3, LEG[3])
            cv.dot(lx, 59.3, LEG[3])
    else:
        for lx in (26.0, 29.0):
            m = poly_mask(FW, FH, [(lx, 38.5 + oy), (lx + 1.4, 38.5 + oy), (lx - 1.6, 42.5 + oy), (lx - 3.0, 42.5 + oy)])
            cv.paint(m, LEG[2], FEATHER_LINE)

    # ---- cuerpo y pecho
    bm = ellipse_mask(FW, FH, body_c[0], body_c[1], body_r[0], body_r[1], body_ang)
    cm = ellipse_mask(FW, FH, chest_c[0], chest_c[1], chest_r[0], chest_r[1], -20.0)
    nb = ellipse_normals(FW, FH, body_c[0], body_c[1], body_r[0] + 1, body_r[1] + 1, body_ang)
    nc = ellipse_normals(FW, FH, chest_c[0], chest_c[1], chest_r[0] + 1, chest_r[1] + 1, -20.0)
    n = np.where(cm[..., None], nc, nb)
    m = bm | cm
    cols, lv = shaded(n, m, FEATHER, rim=RIM_COOL, rim_thr=0.42)
    i = (n * L_KEY).sum(-1)
    cols[(i > 0.92) & m] = SHEEN
    if ruffle > 0:
        rng = np.random.default_rng(int(ruffle * 100) + 7)
        ed = edge(m)
        ys, xs = np.nonzero(ed)
        for k in range(len(xs)):
            if rng.random() < 0.25 * ruffle:
                vx, vy = xs[k] - body_c[0], ys[k] - body_c[1]
                ln = math.hypot(vx, vy) + 1e-6
                cv.dot(xs[k] + round(vx / ln), ys[k] + round(vy / ln), FEATHER[1], FEATHER_LINE)
    cv.paint(m, cols, FEATHER_LINE)
    chest_tex = _feather_texture(cols, lv, cm & ~edge(cm), 70.0, 3.0, 0.0, chest_c[0], chest_c[1])
    cv.col[chest_tex & (lv >= 2)] = FEATHER[1]

    # ---- ala (plegada sobre el costado, medio abierta o en vuelo)
    wp = _wing_pts(wing, oy, far=False, pose=pose)
    wm = poly_mask(FW, FH, wp)
    n = pillow_normals(wm, 2.0)
    cols, lv = shaded(n, wm, FEATHER, rim=RIM_COOL, rim_thr=0.55)
    i = (n * L_KEY).sum(-1)
    cols[(i > 0.93) & wm] = SHEEN
    ax = {'fold': 240.0, 'lift': 200.0, 'up': 245.0, 'mid': 185.0, 'down': 115.0, 'glide': 190.0}.get(wing, 240.0)
    sh = wp[0]
    scal = _feather_texture(cols, lv, wm, ax, 3.0, 0.3, sh[0], sh[1])
    ys, xs = np.mgrid[0:FH, 0:FW].astype(np.float32)
    dist = np.hypot(xs - sh[0], ys - sh[1])
    reach = max(math.hypot(x - sh[0], y - sh[1]) for x, y in wp)
    cov = scal & (dist < reach * 0.42)
    prim = _feather_texture(cols, lv, wm, ax + 90.0, 2.6, 0.2, sh[0], sh[1]) & (dist > reach * 0.5)
    cols[cov] = FEATHER[1]
    cols[prim] = FEATHER[0]
    # el borde de ataque del ala (arriba) con luz: separa el ala del cuerpo
    top_edge = edge(wm) & ~np.roll(wm, -1, 0)
    cols[top_edge & wm] = FEATHER[3]
    cv.paint(wm, cols, FEATHER_LINE)
    we = edge(wm) & dilate(m) & ~edge(m) & ~top_edge
    cv.col[we] = FEATHER[0]

    # ---- cartera de mensajero (al costado, con el logo de Krápido) y su correa cruzada
    if p.get('bag', True):
        if pose == 'perch':
            bx, by = 21.0, 44.5 + oy
            bag = [(bx, by), (bx + 9.0, by - 0.6), (bx + 9.6, by + 6.6), (bx + 8.3, by + 8.0), (bx + 0.8, by + 8.2), (bx - 0.6, by + 6.8)]
            strap_a, strap_b = (bx + 8.6, by - 0.2), (neck[0] + 1.5, neck[1] + 2.0)
        else:
            bx, by = 25.0, 37.0 + oy + p.get('bag_swing', 0.0)
            bag = [(bx, by), (bx + 8.0, by), (bx + 8.5, by + 6.0), (bx + 7.2, by + 7.0), (bx + 0.8, by + 7.0), (bx - 0.4, by + 6.0)]
            strap_a, strap_b = (bx + 7.6, by + 0.4), (neck[0] + 0.5, neck[1] + 2.5)
        for t in np.linspace(0, 1, 30):
            x = strap_a[0] + (strap_b[0] - strap_a[0]) * t
            y = strap_a[1] + (strap_b[1] - strap_a[1]) * t
            cv.dot(x, y, LEATHER[1] if t < 0.85 else LEATHER[0], LEATHER_LINE)
        bgm = poly_mask(FW, FH, bag)
        n = pillow_normals(bgm, 1.5)
        cols, lv = shaded(n, bgm, LEATHER)
        cv.paint(bgm, cols, LEATHER_LINE)
        fy = by + 3.2
        rows = np.mgrid[0:FH, 0:FW][0]
        flap = bgm & (rows < fy)
        cv.col[flap] = LEATHER[3]
        cv.col[flap & (np.mgrid[0:FH, 0:FW][1] > bx + 6.5)] = LEATHER[2]
        fl_line = bgm & (rows >= fy) & (rows < fy + 1)
        cv.col[fl_line] = LEATHER[0]
        lx, ly = bx + 4.0, fy + 1.6
        for dx, dy, c in [(0, 0, GOLD[3]), (1, 0, GOLD[2]), (0, 1, GOLD[2]), (1, 1, GOLD[1]), (-1, 0, GOLD[3]), (-1, 1, GOLD[2]),
                          (0, -1, GOLD[4]), (1, -1, GOLD[3]), (0, 2, GOLD[1]), (-1, -1, GOLD[3]), (2, 0, GOLD[1]), (2, 1, GOLD[0])]:
            cv.dot(lx + dx, ly + dy, c)
        cv.dot(lx + 1, ly, EYE_P)
        cv.dot(lx, ly, rgb('#2a1a10'))
        info['bag'] = (lx, ly)

    # ---- cuello: plumas de la garganta (barba de cuervo)
    if pose == 'perch':
        hack = [(43.5, 28.5), (49.5, 29.0), (48.6, 32.6), (47.0, 31.6), (46.2, 35.4), (44.5, 33.2), (42.6, 36.4), (40.0, 33.0)]
    else:
        hack = [(48.0, 30.0), (53.0, 30.6), (51.5, 33.4), (49.6, 32.6), (48.0, 35.0), (45.0, 33.0)]
    hk = poly_mask(FW, FH, hrot(move_pts(hack, head_dx, oy + head_dy)))
    n = pillow_normals(hk, 1.4)
    cols, lv = shaded(n, hk, FEATHER, rim=RIM_COOL, rim_thr=0.45)
    cv.paint(hk, cols, FEATHER_LINE)

    # ---- cabeza (grande)
    hc = rot_pts([head_c], neck[0], neck[1], head_rot)[0]
    hm = ellipse_mask(FW, FH, hc[0], hc[1], head_r, head_r * 0.93, 0)
    n = ellipse_normals(FW, FH, hc[0], hc[1], head_r + 1, head_r + 0.6, 0)
    cols, lv = shaded(n, hm, FEATHER, rim=RIM_COOL, rim_thr=0.42)
    i = (n * L_KEY).sum(-1)
    cols[(i > 0.9) & hm] = SHEEN
    cv.paint(hm, cols, FEATHER_LINE)

    # ---- pico grande y grueso, con la punta curva
    bx0, by0 = hc[0] + head_r * 0.62, hc[1] - 3.2
    if pose == 'fly':
        by0 = hc[1] - 2.6
    upper = [(bx0 - 1.6, by0 - 0.6), (bx0 + 4.5, by0 - 0.2), (bx0 + 9.5, by0 + 1.6), (bx0 + 12.8, by0 + 4.4),
             (bx0 + 12.4, by0 + 6.4), (bx0 + 10.6, by0 + 5.5), (bx0 + 4.0, by0 + 5.3), (bx0 - 1.6, by0 + 5.0)]
    lower = [(bx0 - 1.6, by0 + 5.2), (bx0 + 4.0, by0 + 5.6), (bx0 + 10.4, by0 + 5.8), (bx0 + 8.0, by0 + 7.6), (bx0 - 1.0, by0 + 8.0)]
    lower = rot_pts(lower, bx0 - 1.6, by0 + 5.2, 26.0 * beak_open)
    upper = rot_pts(upper, bx0 - 1.6, by0 + 2.0, -7.0 * beak_open)
    upper, lower = hrot(upper), hrot(lower)
    if beak_open > 0.05:
        mouth = poly_mask(FW, FH, [upper[0], upper[6], upper[5], lower[2], lower[4]])
        cv.paint(mouth, rgb('#4a1424'), FEATHER_LINE)
        tongue = hrot([(bx0 + 3.0, by0 + 6.4)])[0]
        cv.dot(tongue[0], tongue[1], rgb('#b04a5a'))
    lm = poly_mask(FW, FH, lower)
    n = pillow_normals(lm, 1.0)
    cols, lv = shaded(n, lm, [BEAK[0], BEAK[1], BEAK[1], BEAK[2], BEAK[2]])
    cv.paint(lm, cols, FEATHER_LINE)
    um = poly_mask(FW, FH, upper)
    n = pillow_normals(um, 1.2)
    cols, lv = shaded(n, um, BEAK)
    cv.paint(um, cols, FEATHER_LINE)
    # la comisura (línea entre las dos mitades) y el brillo
    if beak_open <= 0.05:
        for t in np.linspace(0, 1, 12):
            a, b = hrot([(bx0 - 0.5, by0 + 5.1), (bx0 + 10.4, by0 + 5.6)])
            cv.dot(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, BEAK[0])
    for q, c in [((bx0 + 2.4, by0 + 1.0), BEAK[4]), ((bx0 + 3.4, by0 + 1.0), BEAK[4]), ((bx0 + 6.4, by0 + 2.2), BEAK[3])]:
        qq = hrot([q])[0]
        cv.dot(qq[0], qq[1], c)
    info['beak'] = hrot([(bx0 + 10.5, by0 + 6.5)])[0]
    for k in range(3):   # cerdas sobre la base del pico
        q = hrot([(bx0 - 1.0 + k * 1.3, by0 - 0.8 + k * 0.1)])[0]
        cv.dot(q[0], q[1], FEATHER[2])

    # ---- ojo con párpado (mirada chula); cerrado al parpadear; ceja fruncida si se enoja
    ex, ey = hrot([(hc[0] + 3.2, hc[1] - 1.2)])[0]
    ex, ey = int(round(ex)), int(round(ey))
    if p.get('blink', False):
        for dx in (-1, 0, 1, 2):
            cv.dot(ex + dx, ey + 1, FEATHER[0])
        cv.dot(ex - 1, ey, FEATHER[3])
    else:
        for dx, dy in [(-1, 0), (0, 0), (1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (2, 1)]:
            cv.dot(ex + dx, ey + dy, EYE_W)
        for dx, dy in [(1, 0), (2, 0), (1, 1), (2, 1)]:
            cv.dot(ex + dx, ey + dy, EYE_P)
        cv.dot(ex + 1, ey, WHITE)
        for dx in (-1, 0, 1, 2, 3):   # párpado
            cv.dot(ex + dx, ey - 1, FEATHER[0])
        cv.dot(ex - 1, ey, FEATHER[1])
    if p.get('brow', False):
        for dx, dy in [(-2, -3), (-1, -3), (0, -2), (1, -2), (2, -1), (3, -1)]:
            cv.dot(ex + dx, ey + dy, FEATHER[0])
        cv.dot(ex - 2, ey - 4, FEATHER[3])

    # ---- gorra de mensajero (corona roja, banda, visera hacia delante, insignia dorada)
    if p.get('cap', True):
        cx, cy = hc[0] - 1.2, hc[1] - head_r * 0.72
        tilt = -12.0 + head_rot * 0.8
        band_y = cy + 0.8
        crown = rot_pts(ellipse_pts(cx, cy - 0.4, 7.4, 4.6, 0), cx, cy, tilt)
        cut = poly_mask(FW, FH, rot_pts([(cx - 12, cy - 12), (cx + 12, cy - 12), (cx + 12, band_y), (cx - 12, band_y)], cx, cy, tilt))
        crown_m = poly_mask(FW, FH, crown) & cut
        n = pillow_normals(crown_m, 1.7)
        cols, lv = shaded(n, crown_m, CAP)
        cv.paint(crown_m, cols, CAP_LINE)
        # costuras de la corona
        for t in np.linspace(0.1, 0.9, 7):
            q = rot_pts([(cx + 0.6, cy - 4.4 + t * 5.0)], cx, cy, tilt)[0]
            if crown_m[int(q[1]) % FH, int(q[0]) % FW]:
                cv.col[int(q[1]), int(q[0])] = CAP[1]
        band = rot_pts([(cx - 7.4, band_y - 0.2), (cx + 7.0, band_y - 0.2), (cx + 7.0, band_y + 1.8), (cx - 7.4, band_y + 1.8)], cx, cy, tilt)
        cv.paint(poly_mask(FW, FH, band), CAP[1], CAP_LINE)
        visor = rot_pts([(cx + 4.0, band_y + 0.2), (cx + 12.6, band_y + 1.0), (cx + 12.8, band_y + 2.4), (cx + 4.4, band_y + 2.0)], cx, cy, tilt)
        cv.paint(poly_mask(FW, FH, visor), rgb('#3a1016'), CAP_LINE)
        vt = rot_pts([(cx + 5.4, band_y + 0.6), (cx + 12.0, band_y + 1.2)], cx, cy, tilt)
        for t in np.linspace(0, 1, 8):
            cv.dot(vt[0][0] + (vt[1][0] - vt[0][0]) * t, vt[0][1] + (vt[1][1] - vt[0][1]) * t, rgb('#64222b'))
        badge = rot_pts([(cx + 3.0, cy - 1.6)], cx, cy, tilt)[0]
        for dx, dy, c in [(0, 0, GOLD[3]), (1, 0, GOLD[2]), (0, 1, GOLD[1]), (1, 1, GOLD[1]), (0, -1, GOLD[4]), (-1, 0, GOLD[2])]:
            cv.dot(badge[0] + dx, badge[1] + dy, c, GOLD_LINE)
        bt = rot_pts([(cx - 0.4, cy - 5.0)], cx, cy, tilt)[0]
        cv.dot(bt[0], bt[1], CAP[3], CAP_LINE)
        info['cap'] = (cx, cy)

    cv.outline()
    info['head'] = hc
    return cv.image(), info


def _wing_pts(wing, oy, far=False, pose='fly'):
    """Polígono del ala. El primer punto es el hombro."""
    if pose == 'perch' and not far:
        if wing == 'lift':   # medio abierta hacia atrás y arriba (salta o se enoja)
            pts = [(36.0, 31.0), (30.0, 26.0), (21.0, 21.0), (11.0, 20.0), (5.0, 23.0), (9.5, 25.0), (12.5, 28.0), (18.0, 32.5), (25.0, 37.5), (33.0, 38.5)]
        else:
            pts = [(36.0, 31.0), (28.5, 31.5), (22.0, 37.5), (18.5, 46.0), (14.0, 56.5), (11.5, 61.5), (16.0, 61.0), (23.5, 54.5), (31.0, 47.5), (36.5, 39.0)]
        return move_pts(pts, 0, oy)
    if wing == 'up':
        pts = [(40.0, 29.5), (36.0, 21.0), (33.0, 12.5), (29.0, 4.0), (25.0, 1.0), (22.5, 3.0), (19.5, 2.5), (17.5, 5.5),
               (15.0, 6.5), (16.5, 10.5), (20.0, 15.0), (24.5, 21.0), (29.0, 26.5), (33.0, 30.0)]
    elif wing == 'down':
        pts = [(40.0, 32.0), (37.0, 39.5), (34.0, 47.0), (30.5, 55.5), (27.0, 59.5), (24.5, 58.0), (21.5, 59.0), (20.0, 56.0),
               (18.0, 55.0), (20.0, 50.0), (23.5, 43.5), (27.5, 37.5), (32.0, 33.5)]
    elif wing == 'glide':
        pts = [(40.0, 29.5), (31.0, 25.0), (21.0, 22.0), (11.0, 20.5), (5.0, 21.0), (2.5, 23.0), (4.0, 24.5), (2.5, 26.5),
               (6.5, 27.0), (12.0, 28.5), (21.0, 31.0), (31.0, 33.5)]
    else:   # mid
        pts = [(40.0, 30.0), (31.0, 27.0), (21.0, 25.5), (11.0, 25.0), (5.0, 26.0), (2.5, 28.0), (4.5, 29.5), (3.0, 31.5),
               (7.5, 32.0), (13.0, 33.0), (22.0, 34.5), (32.0, 35.0)]
    pts = move_pts(pts, 0, oy)
    if far:
        pts = move_pts(pts, -2.5, -2.0)
    return pts


# Los cuadros de la tira assets/props/raven.png (64x64 cada uno). Ver RAVEN_FRAMES en scripts/world/raven.gd.
RAVEN_POSES = [
    ('perch', {}),                                                      # 0 posado
    ('blink', {'blink': True}),                                         # 1 parpadea
    ('tilt_up', {'head_rot': -10.0, 'head_dy': -0.5}),                  # 2 cabeza alta (chulo)
    ('tilt_down', {'head_rot': 12.0, 'head_dx': 0.5}),                  # 3 ladea la cabeza (mira)
    ('ruffle_a', {'ruffle': 1.0}),                                      # 4 se esponja
    ('ruffle_b', {'ruffle': 0.6, 'head_rot': -4.0, 'hop': 1.0}),        # 5 se sacude
    ('talk', {'beak_open': 1.0, 'head_rot': -6.0}),                     # 6 habla (pico abierto)
    ('crouch', {'crouch': 1.0, 'wing': 'lift', 'head_rot': 6.0}),       # 7 se agacha para agarrar
    ('hop', {'hop': 5.0, 'wing': 'lift', 'head_rot': -8.0}),            # 8 salto (agarra la botella)
    ('land', {'crouch': 0.6, 'head_rot': -4.0}),                        # 9 aterriza, contento
    ('angry_a', {'ruffle': 1.0, 'brow': True, 'beak_open': 1.0, 'wing': 'lift', 'head_rot': -6.0}),   # 10 ¡KRAA!
    ('angry_b', {'ruffle': 0.7, 'brow': True, 'beak_open': 0.3, 'head_rot': 2.0}),                     # 11 enojado
    ('fly_up', {'pose': 'fly', 'wing': 'up', 'bag_swing': 0.5}),        # 12 vuelo: alas arriba
    ('fly_mid', {'pose': 'fly', 'wing': 'mid', 'hop': 1.0}),            # 13
    ('fly_down', {'pose': 'fly', 'wing': 'down', 'hop': 2.0, 'bag_swing': -0.5}),   # 14
    ('fly_glide', {'pose': 'fly', 'wing': 'glide', 'hop': 1.0}),        # 15 planea
]


def raven_strip():
    frames, infos = [], []
    for name, p in RAVEN_POSES:
        img, info = draw_raven(p)
        frames.append(img)
        infos.append({'name': name, **{k: [round(v[0], 1), round(v[1], 1)] for k, v in info.items()}})
    return np.concatenate(frames, axis=1), infos


# ================================================================== la bola de cristal, la ventanilla, el anillo y la interfaz

BRASS = ramp('#3e2610', '#6e4a1c', '#a6762e', '#d6a84a', '#f4d98a')
BRASS_LINE = rgb('#24160a')
ORB = ramp('#120c26', '#21164a', '#36277a', '#5543ad', '#8d7ee6')
MIST_C = rgb('#7fd8ff')
MIST_V = rgb('#d6a8ff')
WOOD_D = ramp('#2a170c', '#432614', '#5e3a20', '#7c5130', '#9a6a42')
WOOD_L = ramp('#4a2c16', '#6e4424', '#93603a', '#b47d4e', '#d39c66')
WOOD_LINE = rgb('#170c05')
CREAM = rgb('#f2e2b8')

# --- R5 WORLD: letras de 5 px de alto para CROW DELIVERY (antes solo las de KRÁPIDO, que siguen aquí)
PIX_FONT = {
    'K': ['X..X', 'X.X.', 'XX..', 'X.X.', 'X..X'],
    'R': ['XXX.', 'X..X', 'XXX.', 'X.X.', 'X..X'],
    'A': ['.XX.', 'X..X', 'XXXX', 'X..X', 'X..X'],
    'P': ['XXX.', 'X..X', 'XXX.', 'X...', 'X...'],
    'I': ['X', 'X', 'X', 'X', 'X'],   # --- R5 WORLD: (era de 3 px, con remates) para que DELIVERY quepa con aire
    'D': ['XXX.', 'X..X', 'X..X', 'X..X', 'XXX.'],
    'O': ['.XX.', 'X..X', 'X..X', 'X..X', '.XX.'],
    'C': ['.XXX', 'X...', 'X...', 'X...', '.XXX'],
    'W': ['X...X', 'X...X', 'X.X.X', 'X.X.X', '.X.X.'],
    'E': ['XXX', 'X..', 'XX.', 'X..', 'XXX'],
    'L': ['X..', 'X..', 'X..', 'X..', 'XXX'],
    'V': ['X...X', 'X...X', '.X.X.', '.X.X.', '..X..'],
    'Y': ['X.X', 'X.X', '.X.', '.X.', '.X.'],
    ' ': ['..', '..', '..', '..', '..'],
}


def pix_text(cv, text, x, y, col, shadow=None):
    """Letras de 5 px de alto (las de KRÁPIDO y CROW DELIVERY). 'Á' = A con tilde."""
    for ch in text:
        accent = ch == 'Á'
        g = PIX_FONT['A' if accent else ch]
        for yy, row in enumerate(g):
            for xx, c in enumerate(row):
                if c == 'X':
                    if shadow is not None:
                        cv.dot(x + xx + 1, y + yy + 1, shadow)
                    cv.dot(x + xx, y + yy, col)
        if accent:
            cv.dot(x + 2, y - 2, col)
            cv.dot(x + 3, y - 3, col)
        x += len(g[0]) + 1
    return x


def text_w(text):
    return sum(len(PIX_FONT['A' if c == 'Á' else c][0]) + 1 for c in text) - 1


def sphere(cv, cx, cy, r, ramp_cols, line, lift=0, cuts=(0.12, 0.38, 0.62, 0.84)):
    w, h = cv.w, cv.h
    m = ellipse_mask(w, h, cx, cy, r, r)
    n = ellipse_normals(w, h, cx, cy, r + 0.6, r + 0.6)
    cols, lv = shaded(n, m, ramp_cols, cuts=cuts, lift=lift)
    cv.paint(m, cols, line)
    return m, n


def orb(cv, cx, cy, r, detail=1.0, seed=3):
    """El orbe de cristal: interior oscuro con niebla que gira (cian y violeta), núcleo de luz, brillos."""
    w, h = cv.w, cv.h
    m = ellipse_mask(w, h, cx, cy, r, r)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    dx, dy = (xs - cx) / r, (ys - cy) / r
    d = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    cols = np.zeros((h, w, 3), np.float32)
    # fondo: más claro arriba-izquierda (luz que entra), más oscuro abajo
    base = 0.55 - 0.45 * dy - 0.25 * d
    lv = np.clip((base * 3.2).astype(int), 0, 3)
    for i in range(4):
        cols[lv == i] = ORB[i]
    # niebla en espiral
    swirl = np.sin(ang * 2.0 + d * 7.5 * detail) * (1 - d)
    cols[(swirl > 0.38) & (d < 0.8)] = ORB[3]
    cols[(swirl > 0.55) & (d < 0.62)] = MIST_V * 0.9
    swirl2 = np.sin(-ang * 3.0 + d * 9.0 * detail + 1.3) * (1 - d)
    cols[(swirl2 > 0.5) & (d < 0.7) & (d > 0.18)] = MIST_C * 0.85
    # núcleo
    cols[d < 0.2] = ORB[4]
    cols[d < 0.1] = rgb('#e8e2ff')
    # estrellitas
    rng = np.random.default_rng(seed)
    for _ in range(int(r * 0.9)):
        a, rr = rng.uniform(0, 2 * math.pi), rng.uniform(0.25, 0.85)
        sx, sy = int(cx + math.cos(a) * rr * r), int(cy + math.sin(a) * rr * r)
        if 0 <= sx < w and 0 <= sy < h and m[sy, sx]:
            cols[sy, sx] = rgb('#f4f0ff') if rng.random() < 0.5 else MIST_C
    # borde: anillo oscuro y luz refractada abajo a la derecha
    rim = (d > 0.86) & m
    cols[rim] = ORB[1]
    refr = (d > 0.72) & (d < 0.9) & (dx > 0.05) & (dy > 0.2) & m
    cols[refr] = ORB[4]
    cv.paint(m, cols, rgb('#0a0716'))
    # brillos: media luna arriba a la izquierda y un punto
    hl = (d > 0.55) & (d < 0.78) & (ang > -2.6) & (ang < -1.6) & m
    cv.col[hl] = np.minimum(cv.col[hl] + 120, 255)
    for (px, py) in [(-0.42, -0.5), (-0.36, -0.58)]:
        cv.dot(cx + px * r, cy + py * r, WHITE)
    return m


def krapido_ball_prop():
    """La bola de Krápido para la tienda: un orbe sobre un pie de latón con tres garras de cuervo (30x56)."""
    w, h = 30, 56
    cv = Canvas(w, h)
    # patas del trípode (garras) y la base
    for pts in ([(14.0, 42.0), (16.0, 42.0), (8.0, 52.5), (3.0, 55.0), (2.0, 53.6), (6.0, 51.0)],
                [(14.0, 42.0), (16.0, 42.0), (24.0, 51.0), (28.0, 53.6), (27.0, 55.0), (22.0, 52.5)],
                [(13.6, 44.0), (16.4, 44.0), (16.6, 55.0), (13.4, 55.0)]):
        mm = poly_mask(w, h, pts)
        n = pillow_normals(mm, 1.2)
        cols, lv = shaded(n, mm, BRASS)
        cv.paint(mm, cols, BRASS_LINE)
    # columna con nudos
    col = poly_mask(w, h, [(13.2, 26.0), (16.8, 26.0), (16.4, 44.5), (13.6, 44.5)])
    n = pillow_normals(col, 1.0)
    cols, lv = shaded(n, col, BRASS)
    cv.paint(col, cols, BRASS_LINE)
    for ky, kr in ((31.0, 3.0), (38.5, 2.6), (43.6, 3.4)):
        sphere(cv, 15.0, ky, kr, BRASS, BRASS_LINE)
    # copa: tres garras que abrazan el orbe
    cup = ellipse_mask(w, h, 15.0, 25.0, 7.8, 3.2)
    n = ellipse_normals(w, h, 15.0, 25.0, 8.6, 4.0)
    cols, lv = shaded(n, cup, BRASS)
    cv.paint(cup, cols, BRASS_LINE)
    orb(cv, 15.0, 13.5, 11.2, 1.0, 5)
    for pts in ([(8.5, 24.5), (10.5, 23.5), (6.6, 17.0), (5.0, 15.5), (5.4, 18.5)],
                [(21.5, 24.5), (19.5, 23.5), (23.4, 17.0), (25.0, 15.5), (24.6, 18.5)],
                [(14.0, 26.0), (16.0, 26.0), (16.2, 23.0), (15.0, 21.6), (13.8, 23.0)]):
        mm = poly_mask(w, h, pts)
        n = pillow_normals(mm, 1.0)
        cols, lv = shaded(n, mm, BRASS, lift=1)
        cv.paint(mm, cols, BRASS_LINE)
    cv.outline()
    return cv.image()


def krapido_ball_glow():
    """El brillo del orbe (se suma encima, sin luz: late cuando llegan pedidos)."""
    w, h = 30, 56
    img = np.zeros((h, w, 4), np.uint8)
    cx, cy, r = 15.0, 13.5, 12.6
    for y in range(h):
        for x in range(w):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) / r
            if d < 1.0:
                a = (1.0 - d) ** 0.7
                a = round(a * 4) / 4   # en escalones (pixel art)
                c = np.array([170, 150, 255]) * (1 - d) + np.array([120, 220, 255]) * d
                img[y, x, :3] = np.clip(c, 0, 255)
                img[y, x, 3] = int(a * 230)
    return img


def krapido_hatch():
    """La tapa de la ventanilla (26x34): tablas, herrajes y el logo de Krápido pintado."""
    w, h = 26, 34
    cv = Canvas(w, h)
    m = np.ones((h, w), bool)
    cols = np.zeros((h, w, 3), np.float32)
    for x in range(w):
        plank = x // 6
        tone = [2, 3, 2, 1, 2][plank % 5]
        for y in range(h):
            t = tone
            if x % 6 == 0:
                t = 0   # junta entre tablas
            elif x % 6 == 1:
                t = min(4, tone + 1)
            if (x * 7 + y * 3 + plank * 11) % 23 == 0:
                t = max(0, t - 1)   # vetas
            cols[y, x] = WOOD_L[t]
    cv.paint(m, cols, WOOD_LINE)
    # travesaños de hierro arriba y abajo
    for yy in (3, 29):
        for x in range(w):
            cv.col[yy, x] = rgb('#2c2a33')
            cv.col[yy + 1, x] = rgb('#45424f')
        for x in (3, 12, 22):
            cv.col[yy, x] = rgb('#6a6676')
    # el logo pintado en el centro (disco dorado con la cabeza del cuervo)
    lc = Canvas(w, h)
    _logo(lc, 13.0, 16.5, 7.5)
    cv.col[lc.a] = lc.col[lc.a]
    # borde
    for x in range(w):
        cv.col[0, x] = WOOD_D[1]
        cv.col[h - 1, x] = WOOD_D[0]
    for y in range(h):
        cv.col[y, 0] = WOOD_D[1]
        cv.col[y, w - 1] = WOOD_D[0]
    return cv.image()


def _logo(cv, cx, cy, r, ring=True):
    """El logo de Krápido: un disco dorado con la cabeza del cuervo (gorra roja, pico) y dos rayas de velocidad."""
    if ring:
        m, n = sphere(cv, cx, cy, r, GOLD, GOLD_LINE, lift=0)
        inner = ellipse_mask(cv.w, cv.h, cx, cy, r - 1.6, r - 1.6)
        cv.col[inner] = rgb('#241a2e')
    s = r / 7.5
    k = rgb('#0e0d16')
    # busto: hombro y cuello
    bust = poly_mask(cv.w, cv.h, [(cx - 4.8 * s, cy + 6.4 * s), (cx - 4.4 * s, cy + 2.0 * s), (cx - 1.0 * s, cy + 1.0 * s),
                                  (cx + 2.6 * s, cy + 3.2 * s), (cx + 2.2 * s, cy + 6.4 * s)])
    cv.col[bust] = k
    cv.a |= bust
    head = ellipse_mask(cv.w, cv.h, cx - 0.8 * s, cy - 0.2 * s, 3.5 * s, 3.3 * s)
    cv.col[head] = k
    cv.a |= head
    beak = poly_mask(cv.w, cv.h, [(cx + 1.6 * s, cy - 1.6 * s), (cx + 4.8 * s, cy - 0.6 * s), (cx + 6.4 * s, cy + 0.6 * s),
                                  (cx + 5.6 * s, cy + 1.2 * s), (cx + 1.8 * s, cy + 1.6 * s)])
    cv.col[beak] = rgb('#5a5866')
    cv.a |= beak
    for xx in np.arange(cx + 2.0 * s, cx + 5.6 * s, 0.8):
        cv.dot(xx, cy + 0.5 * s, rgb('#2a2930'))
    capm = poly_mask(cv.w, cv.h, [(cx - 4.2 * s, cy - 1.8 * s), (cx - 3.0 * s, cy - 4.4 * s), (cx + 0.2 * s, cy - 4.8 * s),
                                  (cx + 2.2 * s, cy - 3.4 * s), (cx + 5.0 * s, cy - 2.6 * s), (cx + 4.8 * s, cy - 1.8 * s),
                                  (cx + 1.0 * s, cy - 1.8 * s)])
    cv.col[capm] = CAP[2]
    cv.a |= capm
    for xx in np.arange(cx + 1.6 * s, cx + 5.0 * s, 0.8):
        cv.dot(xx, cy - 2.0 * s, CAP[0])
    cv.dot(cx - 0.6 * s, cy - 3.6 * s, CAP[4])
    cv.dot(cx + 0.6 * s, cy - 0.8 * s, WHITE)
    cv.dot(cx + 1.0 * s, cy - 0.8 * s, EYE_P)
    for kk in range(2):   # rayas de velocidad
        yy = cy + (kk * 2.4 - 1.2) * s
        for xx in np.arange(cx - 7.4 * s, cx - 4.8 * s, 1.0):
            cv.dot(xx, yy, GOLD[3])


def krapido_logo():
    cv = Canvas(28, 28)
    _logo(cv, 13.5, 13.5, 12.5)
    cv.outline()
    return cv.image()


def krapido_sign():
    """--- R5 WORLD: el letrero sobre la ventanilla (44x21): tabla oscura con borde dorado y CROW DELIVERY en dos
    renglones, con el logo (la cabeza del cuervo en su disco dorado) delante de CROW. Era de 52x17 con KRÁPIDO: ahora
    es más alto y más angosto, para que quepa entre el poste y el estante de la tienda (0,84 m a 0,019 m/px) y se lea."""
    w, h = 44, 21
    cv = Canvas(w, h)
    m = poly_mask(w, h, [(1, 2), (43, 2), (43, 20), (1, 20)])
    n = pillow_normals(m, 0.8)
    cols, lv = shaded(n, m, WOOD_D)
    cv.paint(m, cols, WOOD_LINE)
    for x in range(2, 42):
        cv.dot(x, 3, GOLD[2])
        cv.dot(x, 18, GOLD[1])
    for y in range(3, 19):
        cv.dot(2, y, GOLD[2])
        cv.dot(41, y, GOLD[1])
    # primer renglón: el logo y CROW, centrados juntos
    lw = 9
    tw1 = text_w('CROW')
    x1 = 3 + (38 - (lw + 2 + tw1)) // 2
    lc = Canvas(w, h)
    _logo(lc, x1 + 4.0, 8.0, 3.9)
    cv.col[lc.a] = lc.col[lc.a]
    pix_text(cv, 'CROW', x1 + lw + 2, 6, CREAM, shadow=rgb('#1a0e06'))
    # segundo renglón: DELIVERY
    tw2 = text_w('DELIVERY')
    pix_text(cv, 'DELIVERY', 3 + (38 - tw2) // 2, 12, CREAM, shadow=rgb('#1a0e06'))
    # argollas de las cadenas
    for x in (8, 35):
        cv.dot(x, 1, rgb('#6a6676'), rgb('#1a1920'))
        cv.dot(x, 0, rgb('#45424f'), rgb('#1a1920'))
    cv.outline()
    return cv.image()


def raven_ring(frames=16, size=20):
    """El reloj sobre Graznido: un aro que se vacía (se tiñe en el juego: verde, ámbar, rojo)."""
    out = []
    c = (size - 1) / 2.0
    for f in range(frames):
        frac = 1.0 - f / (frames - 1)
        img = np.zeros((size, size, 4), np.uint8)
        for y in range(size):
            for x in range(size):
                dx, dy = x - c, y - c
                d = math.hypot(dx, dy)
                a = (math.atan2(dx, -dy) / (2 * math.pi)) % 1.0   # 0 arriba, horario
                if d <= 6.2:
                    img[y, x] = (24, 18, 36, 190)   # disco oscuro
                if 6.2 < d <= 9.4:
                    if a <= frac + 1e-6 and frac > 0.0:
                        img[y, x] = (255, 255, 255, 255) if d < 8.6 else (210, 210, 220, 255)
                    else:
                        img[y, x] = (40, 34, 54, 200)
                elif 9.4 < d <= 10.2:
                    img[y, x] = (12, 8, 20, 230)
        # una plumita en el centro
        for (x, y) in [(10, 6), (10, 7), (9, 8), (10, 8), (9, 9), (10, 9), (9, 10), (10, 10), (9, 11), (8, 12), (9, 12), (8, 13)]:
            img[y, x] = (235, 230, 245, 255)
        out.append(img)
    return np.concatenate(out, axis=1)


# ---------------------------------------------------------------- interfaz de la bola (ui/)

def ui_ball(r=78, size=160):
    """El orbe grande de la interfaz en dos capas: el fondo (interior) y el frente (cristal: brillos y borde)."""
    back = Canvas(size, size)
    c = size / 2.0
    w = h = size
    m = ellipse_mask(w, h, c, c, r, r)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    dx, dy = (xs - c) / r, (ys - c) / r
    d = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    cols = np.zeros((h, w, 3), np.float32)
    deep = ramp('#0b0820', '#130e33', '#1d1648', '#2a2062', '#3a2c7e')
    v = np.clip(0.55 - 0.35 * dy - 0.45 * d, 0, 0.999)
    lv = (v * 5).astype(int)
    lv = np.clip(lv + ((xs.astype(int) + ys.astype(int)) % 2 == 0) * (np.mod(v * 5, 1) > 0.7), 0, 4)   # tramado
    for i in range(5):
        cols[lv == i] = deep[i]
    # nebulosa: dos brazos en espiral, violeta y cian, tramados
    dd = np.clip(1 - d, 0, 1)
    for colr, k0 in ((rgb('#2c1d5c'), 0.0), (rgb('#182c58'), 2.1)):
        sw = np.sin(ang * 2.0 + d * 6.0 + k0) * dd ** 1.3
        chk = ((xs.astype(int) + ys.astype(int)) % 2) == 0
        mk = (sw > 0.30) & (d < 0.9) & chk
        cols[mk] = colr
        mk2 = (sw > 0.42) & (d < 0.8)
        cols[mk2] = colr
        mk3 = (sw > 0.55) & (d < 0.7) & chk
        cols[mk3] = colr * 1.3
    rng = np.random.default_rng(17)
    for _ in range(120):
        a, rr = rng.uniform(0, 2 * math.pi), rng.uniform(0.05, 0.93) ** 0.7
        sx, sy = int(c + math.cos(a) * rr * r), int(c + math.sin(a) * rr * r)
        if m[sy, sx]:
            b = rng.random()
            cols[sy, sx] = rgb('#fff8e8') if b < 0.35 else (rgb('#9fe6ff') if b < 0.6 else rgb('#cdb8ff'))
            if b < 0.08:
                for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if m[sy + oy, sx + ox]:
                        cols[sy + oy, sx + ox] = rgb('#8a7ad8')
    back.paint(m, cols, rgb('#05040c'))
    # frente: borde de cristal y brillos (con transparencia)
    front = np.zeros((h, w, 4), np.uint8)
    ring = (d > 0.955) & (d <= 1.0)
    front[ring] = (16, 12, 34, 255)
    ring2 = (d > 0.915) & (d <= 0.955)
    front[ring2] = (60, 52, 110, 200)
    # media luna grande de luz (arriba a la izquierda), en escalones de transparencia
    hl = (d > 0.62) & (d < 0.9) & (ang > -2.75) & (ang < -1.45)
    front[hl] = (230, 225, 255, 70)
    hl2 = (d > 0.7) & (d < 0.84) & (ang > -2.55) & (ang < -1.75)
    front[hl2] = (245, 240, 255, 120)
    # reflejo inferior (luz que atraviesa el cristal)
    lo = (d > 0.78) & (d < 0.9) & (ang > 0.55) & (ang < 2.1)
    front[lo] = (150, 200, 255, 70)
    # destellos
    for (px, py, s) in [(-0.46, -0.52, 3), (-0.3, -0.64, 1), (0.52, 0.5, 1)]:
        x0, y0 = int(c + px * r), int(c + py * r)
        for k in range(-s, s + 1):
            front[y0, x0 + k] = (255, 255, 255, 230 if k == 0 else 150)
            front[y0 + k, x0] = (255, 255, 255, 230 if k == 0 else 150)
    return back.image(), front


def ui_stand(w=184, h=112, ball_r=78.0, ball_bottom=44.0):
    """El pie de latón de la bola grande (184x112): tres garras de cuervo que suben abrazando la bola (su borde de
    abajo queda en y = ball_bottom de este dibujo), el cuello con nudos y la base ancha."""
    cv = Canvas(w, h)
    cx = w / 2.0
    bcy = ball_bottom - ball_r      # centro (virtual) de la bola, por encima del dibujo
    # base ancha y su borde
    base = ellipse_mask(w, h, cx, 100.0, 82.0, 10.0)
    n = ellipse_normals(w, h, cx, 100.0, 84.0, 12.0)
    cols, lv = shaded(n, base, BRASS)
    cv.paint(base, cols, BRASS_LINE)
    lip = ellipse_mask(w, h, cx, 95.0, 70.0, 7.0)
    n = ellipse_normals(w, h, cx, 95.0, 72.0, 9.0)
    cols, lv = shaded(n, lip, BRASS, lift=1)
    cv.paint(lip, cols, BRASS_LINE)
    # cuello
    neck = poly_mask(w, h, [(cx - 15, 46), (cx + 15, 46), (cx + 9, 66), (cx + 17, 90), (cx - 17, 90), (cx - 9, 66)])
    n = pillow_normals(neck, 1.4)
    cols, lv = shaded(n, neck, BRASS)
    cv.paint(neck, cols, BRASS_LINE)
    for ky, kr in ((70.0, 12.0), (52.0, 20.0)):
        k = ellipse_mask(w, h, cx, ky, kr, 4.6)
        n = ellipse_normals(w, h, cx, ky, kr + 1, 5.6)
        cols, lv = shaded(n, k, BRASS)
        cv.paint(k, cols, BRASS_LINE)
    # garras: bandas que siguen el borde de la bola, de abajo hacia los lados, con uña al final
    def claw(t0, t1, r_in, r_out, nail_dir):
        pts = []
        steps = 14
        for i in range(steps + 1):
            t = math.radians(t0 + (t1 - t0) * i / steps)
            rr = r_out + 2.5 * math.sin(math.pi * i / steps)   # nudillos
            pts.append((cx + rr * math.cos(t), bcy + rr * math.sin(t)))
        for i in range(steps, -1, -1):
            t = math.radians(t0 + (t1 - t0) * i / steps)
            rr = r_in - 0.8 * (i / steps)
            pts.append((cx + rr * math.cos(t), bcy + rr * math.sin(t)))
        mm = poly_mask(w, h, pts)
        n = pillow_normals(mm, 1.3)
        cols, lv = shaded(n, mm, BRASS)
        cv.paint(mm, cols, BRASS_LINE)
        # nudillos marcados
        for i in (5, 10):
            t = math.radians(t0 + (t1 - t0) * i / steps)
            for rr in np.arange(r_in + 0.5, r_out + 1.5, 0.7):
                cv.dot(cx + rr * math.cos(t), bcy + rr * math.sin(t), BRASS[1])
        # uña (oscura) en la punta
        t = math.radians(t1)
        tx, ty = cx + (r_in + r_out) / 2 * math.cos(t), bcy + (r_in + r_out) / 2 * math.sin(t)
        d = math.radians(t1 + nail_dir * 18)
        nx, ny = cx + (r_out - 1.0) * math.cos(d), bcy + (r_out - 1.0) * math.sin(d)
        nail = [(tx - 2.6 * math.sin(t), ty + 2.6 * math.cos(t)), (tx + 2.6 * math.sin(t), ty - 2.6 * math.cos(t)), (nx, ny)]
        cv.paint(poly_mask(w, h, nail), rgb('#2c2a33'), BRASS_LINE)
    claw(97.0, 140.0, ball_r - 3.0, ball_r + 6.0, 1)     # izquierda (sube por el lado izquierdo de la bola)
    claw(83.0, 40.0, ball_r - 3.0, ball_r + 6.0, -1)     # derecha
    # garra de delante: corta, la bola apoya en ella
    front = [(cx - 6, 50), (cx + 6, 50), (cx + 5, ball_bottom - 2), (cx + 2, ball_bottom - 9), (cx - 2, ball_bottom - 9), (cx - 5, ball_bottom - 2)]
    mm = poly_mask(w, h, front)
    n = pillow_normals(mm, 1.1)
    cols, lv = shaded(n, mm, BRASS, lift=1)
    cv.paint(mm, cols, BRASS_LINE)
    cv.paint(poly_mask(w, h, [(cx - 2, ball_bottom - 9), (cx + 2, ball_bottom - 9), (cx, ball_bottom - 13)]), rgb('#2c2a33'), BRASS_LINE)
    cv.outline()
    return cv.image()


def pluma(kind='full'):
    """Una pluma de la calificación (14x20): dorada, vacía (gris) o media."""
    w, h = 14, 20
    cv = Canvas(w, h)
    # pluma de ave: punta curva hacia la derecha, más ancha de un lado, con una muesca
    vane = [(9.5, 0.4), (11.6, 2.6), (12.4, 6.0), (12.0, 9.5), (10.4, 12.8), (8.2, 15.6), (6.8, 16.2), (6.4, 13.6),
            (4.6, 13.0), (5.2, 11.6), (3.6, 9.8), (3.4, 6.8), (4.8, 3.6), (7.2, 1.2)]
    m = poly_mask(w, h, vane)
    n = pillow_normals(m, 1.6)
    gold = GOLD
    grey = ramp('#3a3446', '#524a62', '#6c6380', '#8a8198', '#a79fb6')
    cols_g, lv = shaded(n, m, gold)
    cols_e, _ = shaded(n, m, grey)
    if kind == 'full':
        cols = cols_g
    elif kind == 'empty':
        cols = cols_e
    else:
        xs = np.mgrid[0:h, 0:w][1]
        cols = np.where((xs < 7.5)[..., None], cols_g, cols_e)
    # barbas: rayitas diagonales
    ys, xs = np.mgrid[0:h, 0:w]
    barb = ((xs + ys) % 3 == 0) & m & ~edge(m)
    cols[barb] = cols[barb] * 0.82
    cv.paint(m, cols, GOLD_LINE if kind != 'empty' else rgb('#1e1a26'))
    # raquis (el eje) y el cálamo
    for y in range(2, 19):
        x = 9.2 - (y - 2) * 0.2
        cv.dot(x, y, CREAM if kind != 'empty' else rgb('#c8c0d6'))
    cv.dot(5.6, 19, rgb('#8a6a3a'))
    cv.outline()
    return cv.image()


def raven_head_icon():
    cv = Canvas(18, 16)
    _logo(cv, 8.5, 8.5, 7.6, ring=False)
    cv.outline()
    return cv.image()


def krapido_badge():
    """La medalla del HUD: una bola de cristal pequeñita en su pie de latón (26x28)."""
    w, h = 26, 28
    cv = Canvas(w, h)
    base = ellipse_mask(w, h, 13.0, 24.5, 9.5, 2.6)
    n = ellipse_normals(w, h, 13.0, 24.5, 10.5, 3.6)
    cols, lv = shaded(n, base, BRASS)
    cv.paint(base, cols, BRASS_LINE)
    stem = poly_mask(w, h, [(10.5, 18.0), (15.5, 18.0), (17.0, 24.0), (9.0, 24.0)])
    n = pillow_normals(stem, 1.0)
    cols, lv = shaded(n, stem, BRASS)
    cv.paint(stem, cols, BRASS_LINE)
    orb(cv, 13.0, 10.5, 9.4, 1.2, 9)
    cv.outline()
    return cv.image()


def paper_up_krapido():
    """El icono de la mejora en el puesto de Mabel (16x16): la cabeza de Graznido con su gorra y una bolita violeta."""
    cv = Canvas(16, 16)
    _logo(cv, 7.0, 8.0, 6.6, ring=False)
    m, n = sphere(cv, 12.2, 12.4, 2.6, ORB, rgb('#0a0716'), lift=1)
    cv.dot(11.5, 11.4, WHITE)
    cv.outline()
    return cv.image()


ASSETS = {}


def build_all():
    strip, infos = raven_strip()
    ASSETS['props/raven.png'] = strip
    ASSETS['props/raven_ring.png'] = raven_ring()
    ASSETS['props/krapido_ball.png'] = krapido_ball_prop()
    ASSETS['props/krapido_ball_glow.png'] = krapido_ball_glow()
    ASSETS['props/krapido_hatch.png'] = krapido_hatch()
    ASSETS['props/krapido_sign.png'] = krapido_sign()
    b, f = ui_ball()
    ASSETS['ui/ball_back.png'] = b
    ASSETS['ui/ball_front.png'] = f
    ASSETS['ui/ball_stand.png'] = ui_stand()
    for k in ('full', 'half', 'empty'):
        ASSETS['ui/pluma_%s.png' % k] = pluma(k)
    ASSETS['ui/krapido_logo.png'] = krapido_logo()
    ASSETS['ui/raven_head.png'] = raven_head_icon()
    ASSETS['ui/krapido_badge.png'] = krapido_badge()
    ASSETS['ui/paper_up_krapido.png'] = paper_up_krapido()
    return infos


# ================================================================== hoja de revisión

def preview_sheet(path, items, scale=6, bg=(52, 44, 70)):
    ims = [Image.fromarray(i, 'RGBA') if isinstance(i, np.ndarray) else i for i in items]
    W = sum(i.width * scale + 16 for i in ims) + 16
    H = max(i.height * scale for i in ims) + 32
    sheet = Image.new('RGBA', (W, H), bg + (255,))
    x = 16
    for im in ims:
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (x, 16))
        x += big.width + 16
    sheet.save(path)


if __name__ == '__main__':
    import shutil
    infos = build_all()
    for rel, img in ASSETS.items():
        save(img if isinstance(img, np.ndarray) else np.asarray(img), f'{OUT}/{rel}')
    args = sys.argv[1:]
    if args and args[0] == '--preview':
        strip = ASSETS['props/raven.png']
        frames = [strip[:, i * FW:(i + 1) * FW] for i in range(strip.shape[1] // FW)]
        preview_sheet(args[1], frames[:8], 5)
        preview_sheet(args[1].replace('.png', '_b.png'), frames[8:], 5)
        others = [ASSETS[k] for k in ('props/krapido_ball.png', 'props/krapido_ball_glow.png', 'props/krapido_hatch.png',
                                      'props/krapido_sign.png', 'ui/pluma_full.png', 'ui/pluma_half.png', 'ui/pluma_empty.png',
                                      'ui/krapido_logo.png', 'ui/raven_head.png', 'ui/krapido_badge.png', 'ui/paper_up_krapido.png')]
        preview_sheet(args[1].replace('.png', '_props.png'), others, 6)
        ring = ASSETS['props/raven_ring.png']
        preview_sheet(args[1].replace('.png', '_ring.png'), [ring[:, i * 20:(i + 1) * 20] for i in range(0, 16, 3)], 6)
        b = Image.fromarray(ASSETS['ui/ball_back.png'], 'RGBA')
        b.alpha_composite(Image.fromarray(ASSETS['ui/ball_front.png'], 'RGBA'))
        st = Image.fromarray(ASSETS['ui/ball_stand.png'], 'RGBA')
        comp = Image.new('RGBA', (200, 280), (0, 0, 0, 0))
        comp.alpha_composite(b, (20, 4))
        comp.alpha_composite(st, (8, 4 + 158 - 44))
        preview_sheet(args[1].replace('.png', '_ui.png'), [comp], 3)
        print(json.dumps([i for i in infos]))
    elif args:
        dest = args[0]
        for rel in ASSETS:
            os.makedirs(os.path.join(dest, os.path.dirname(rel)), exist_ok=True)
            shutil.copy(f'{OUT}/{rel}', os.path.join(dest, rel))
        print('copiado a', dest, len(ASSETS), 'imágenes')
