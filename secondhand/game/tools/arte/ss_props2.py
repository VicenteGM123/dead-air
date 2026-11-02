"""Secondhand Stars · ronda 2 · props de la línea WORLD (SS2_DESIGN §6, §8.15): el taller vivido, las mejoras, las
cosas de las historias, la calle nueva (Shine Again, el patio de Dolly, los tablones, el Slow Orbit, la banda), el
decorado de los seis días especiales y el cielo nuevo (las dos lunas Copper y Tin, el anillo v2 con sus 7 lámparas,
el cometa de bronce, las chispas de la gala).

Mismo lienzo Cv + render HD-2D que ss_props.py (luz arriba a la izquierda, contorno de color, rampas de 7 tonos); el
cielo (lunas, anillo, chispas) se dibuja directo en numpy, posterizado (solo opaco o transparente, como el sol).
Ningún nombre propio en un PNG (SHINE AGAIN, FITTINGS, THE SLOW ORBIT... son Label3D); palabras comunes sí (FIXED HERE,
PAID IN FULL, DO NOT, APPROVED).

Uso: python3 ss_props2.py [--out DIR] [nombres...]     (sin --out escribe en ../../assets/props y actualiza props.json)
"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from c64core import *
from ss_props import MATS as MATS1, box, keep, star_sign, hcyl_n
from ss_bots import pal_of

MATS = dict(MATS1)
MATS.update({
    'hide': '#7a8a9a', 'hide2': '#5e6a7a', 'horn': ('#d8c8a0', 'white'), 'cap': '#6a4e3a', 'drum': '#b4452e',
    'drum2': '#7a3e26', 'quill': '#3e8a86', 'quill2': '#e8dcc0', 'scarf': '#c8743a', 'feather': '#d8703a',
    'slate': ('#5a6470', 'metal'), 'slate2': ('#46505c', 'metal'), 'grille': ('#2e3438', 'metal'), 'saw': ('#c8ccd4', 'metal'),
    'bottle_g': ('#5f9e86', 'gem'), 'bottle_a': ('#e8a838', 'gem'), 'bottle_b': ('#7ab8c8', 'gem'), 'spoon': ('#d0d4dc', 'metal'),
    'enamel': ('#f2eee6', 'white'), 'enamel2': ('#dcd6cc', 'white'), 'pink': '#e87aa8', 'pink2': '#c85a88', 'mint': '#8fc9b0',
    'chrome': ('#c8d0dc', 'metal'), 'chrome2': ('#8a94a4', 'metal'), 'carpet': '#a8302e', 'cork': '#b88a5a', 'cork2': '#9a6e44',
    'mustard': '#c8a03a', 'mustard2': '#9a7a2a', 'navy': '#3a4660', 'leaf': '#6a9a5a', 'pot': ('#c8d0dc', 'metal'),
    'board': ('#2a2826', 'flat'), 'boardc': ('#ece2c4', 'flat'), 'lantern_a': ('#ffc860', 'flat'), 'lantern_t': ('#7ad8c8', 'flat'),
    'lantern_r': ('#ff9ab8', 'flat'), 'wire': ('#2e2a2e', 'leather'), 'sail': '#d8c8a0', 'tarp': '#6a7a5a', 'tarp2': '#4e5a44',
    'flagr': '#c84a3a', 'flagc': '#ece2c4', 'flagt': '#3e8a86', 'gold': ('#f0c050', 'metal'), 'ribbon': '#b5523a',
    'leather': ('#6e4a30', 'leather'), 'jacket': '#7a5a3a', 'chalk': ('#33403a', 'flat'), 'chalkw': ('#e8e6dc', 'flat'),
    'glass2': ('#a8d8e0', 'gem'), 'velvet': '#7a2e3e', 'copperp': ('#d27c42', 'metal'), 'neonp': ('#ff6ab0', 'flat'),
    'neont': ('#5ef0d8', 'flat'), 'tin': ('#c4ccd4', 'metal'), 'oil': '#3a5a6a', 'oil2': '#c84a3a',
})
ACC = ('teal', 'amber', 'red', 'glow', 'glow2', 'hullr', 'hullt', 'star', 'pink', 'mint', 'carpet', 'lantern_a', 'lantern_t',
       'lantern_r', 'neonp', 'neont', 'flagr', 'flagt', 'drum', 'quill', 'scarf', 'bottle_g', 'bottle_a', 'bottle_b', 'gold')


def cv_new(w, h):
    pal, kinds = pal_of(MATS, accents=ACC)
    return Cv(pal, w=w, h=h, kinds=kinds)


def blank(w, h):
    return np.zeros((h, w, 4), np.uint8)


def strip(frames):
    return np.concatenate(frames, axis=1)


def paste(dst, src, ox, oy):
    """Pega src sobre dst (solo los píxeles opacos de src)."""
    h, w = src.shape[:2]
    y0, x0 = max(0, oy), max(0, ox)
    y1, x1 = min(dst.shape[0], oy + h), min(dst.shape[1], ox + w)
    s = src[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    m = s[..., 3] > 0
    d = dst[y0:y1, x0:x1]
    d[m] = s[m]
    return dst


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ================================================================== el cielo nuevo (numpy, posterizado)

def _sphere(n, cx, cy, r, light=(0.55, -0.55, 0.62)):
    """Normal-dot-luz de una esfera de radio r (luz arriba a la derecha: la lejana del sol de la tarde)."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    dx, dy = (xx + 0.5 - cx) / r, (yy + 0.5 - cy) / r
    d2 = dx * dx + dy * dy
    inside = d2 <= 1.0
    dz = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
    L = np.array(light, np.float32)
    L = L / np.linalg.norm(L)
    lit = dx * L[0] + dy * L[1] + dz * L[2]
    return inside, lit, dx, dy, dz


def _blobs(n, seed, count, rmin, rmax, cx, cy, r):
    rng = np.random.RandomState(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    m = np.zeros((n, n), bool)
    for _ in range(count):
        a = rng.rand() * math.tau
        d = math.sqrt(rng.rand()) * r * 0.78
        bx, by = cx + math.cos(a) * d, cy + math.sin(a) * d
        rx, ry = rng.uniform(rmin, rmax), rng.uniform(rmin, rmax) * rng.uniform(0.55, 1.0)
        m |= ((xx - bx) / rx) ** 2 + ((yy - by) / ry) ** 2 <= 1.0
    return m


def moon(n, r, ramp, sea_ramp, seed, phase, crater_n, sea_n, night=(34, 30, 66)):
    """Una luna posterizada (5 tonos), con mares y cráteres. phase: 0 llena, 1 gibosa, 2 media (sombra a la
    izquierda, el lado sin luz es azul noche opaco: tapa las estrellas del cielo)."""
    arr = blank(n, n)
    c = n / 2.0
    inside, lit, dx, dy, dz = _sphere(n, c, c, r)
    seas = _blobs(n, seed, sea_n, r * 0.18, r * 0.42, c, c, r) & inside
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    rng = np.random.RandomState(seed + 7)
    rim = np.zeros((n, n), bool)
    pit = np.zeros((n, n), bool)
    for _ in range(crater_n):
        a = rng.rand() * math.tau
        d = math.sqrt(rng.rand()) * r * 0.8
        bx, by = c + math.cos(a) * d, c + math.sin(a) * d
        cr = rng.uniform(1.2, max(1.6, r * 0.13))
        dd = np.sqrt((xx + 0.5 - bx) ** 2 + (yy + 0.5 - by) ** 2)
        pit |= dd <= cr * 0.7
        rim |= (dd > cr * 0.7) & (dd <= cr * 1.05)
    lv = np.clip((lit * 0.5 + 0.55), 0, 1)
    lv = np.floor(lv * 4.999).astype(int)            # 0..4
    lv = np.where(pit & inside, np.maximum(lv - 1, 0), lv)
    lv = np.where(rim & inside & (dx < 0.2), np.minimum(lv + 1, 4), lv)
    for k in range(5):
        m = inside & (lv == k)
        arr[m & ~seas, :3] = ramp[k]
        arr[m & seas, :3] = sea_ramp[k]
    arr[inside, 3] = 255
    # la fase: un elipse de sombra desde la izquierda (terminador)
    if phase:
        t = {1: 0.45, 2: 0.0}[phase]
        term = dx < (-1.0 + 2.0 * t) * np.sqrt(np.clip(1.0 - dy * dy, 0, 1)) if phase == 1 else dx < 0.0
        if phase == 1:
            term = dx < -0.45 * np.sqrt(np.clip(1.0 - dy * dy, 0, 1)) - 0.12
        sh = inside & term
        arr[sh, :3] = night
        # luz cenicienta: un borde apenas más claro
        edge = sh & ~np.roll(sh, 1, axis=1)
        arr[edge, :3] = tuple(min(255, v + 18) for v in night)
    # borde exterior oscuro de 1 px en el lado de la sombra (lee como disco y no como mancha)
    ring = inside & ~np.roll(inside, -1, axis=1)
    arr[ring & (dx < 0), :3] = tuple(max(0, v - 12) for v in night)
    return arr


def moon_copper():
    """Copper: la luna grande, cobre rosado con mares de verdín. 3 cuadros de 96: llena, gibosa, media."""
    ramp = [rgb('#7a4a48'), rgb('#a8645a'), rgb('#c8826a'), rgb('#e0a688'), rgb('#f4c8a8')]
    sea = [rgb('#2e5a52'), rgb('#3e7266'), rgb('#5f9e86'), rgb('#7cb89c'), rgb('#9ccab0')]
    return strip([moon(96, 44.0, ramp, sea, 21, ph, 22, 7) for ph in (0, 1, 2)])


def moon_tin():
    """Tin: la chiquita, plata azulada con cráteres. 3 cuadros de 40."""
    ramp = [rgb('#4a5670'), rgb('#76849c'), rgb('#a4b2c4'), rgb('#c8d4e0'), rgb('#eef2f6')]
    sea = [rgb('#3e4860'), rgb('#5c6880'), rgb('#7e8aa2'), rgb('#9aa6ba'), rgb('#b8c2d2')]
    return strip([moon(40, 18.0, ramp, sea, 33, ph, 9, 3) for ph in (0, 1, 2)])


def moon_halo():
    """El halo de bronce de Bronzemoon: anillos punteados alrededor de una luna llena (solo opaco o transparente)."""
    n = 160
    arr = blank(n, n)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt((xx + 0.5 - 80) ** 2 + (yy + 0.5 - 80) ** 2)
    cols = [(232, 168, 88), (214, 140, 70), (190, 118, 60)]
    for k, (r0, r1, step) in enumerate([(50, 54, 2), (60, 63, 3), (70, 72, 4)]):
        m = (d >= r0) & (d < r1) & (((xx.astype(int) + yy.astype(int)) % step) == 0)
        arr[m, :3] = cols[k]
        arr[m, 3] = 255
    return arr


RING_W, RING_H = 512, 150


def _ring_curve(t):
    """El anillo v2: una banda fina, rota y pálida que cruza el cielo inclinada (~13°: sube de izquierda a derecha,
    apenas curvada hacia arriba). Devuelve (x, y) del centro de la banda en píxeles de la textura."""
    x = 12 + t * (RING_W - 24)
    y = (RING_H - 22) - t * 104 - 12 * math.sin(math.pi * t)
    return x, y


RING_LAMPS_T = [0.07, 0.2, 0.33, 0.47, 0.6, 0.76, 0.9]   # dónde van las 7 lámparas (t de la curva)
RING_GAPS = [(0.255, 0.285), (0.405, 0.425), (0.53, 0.565), (0.68, 0.7), (0.835, 0.86)]


def sky_ring():
    """El anillo de restos v2 (el viejo astillero, the High Yards): banda fina y pálida de pedazos con huecos (está
    roto), 5 siluetas de vigas reticuladas y grúas, sin aro sólido ni nada que suba recto del horizonte. Las 7 lámparas
    son sprites aparte (ring_lamp.png); props.json guarda dónde van ("lamps": [[u, v], ...])."""
    arr = blank(RING_W, RING_H)
    rng = np.random.RandomState(11)
    pale = (222, 212, 196, 255)
    mid = (188, 178, 166, 255)
    dark = (150, 142, 136, 255)
    lite = (244, 236, 218, 255)

    def put(x, y, c, s=1):
        xi, yi = int(round(x)), int(round(y))
        if 0 <= xi < RING_W - s + 1 and 0 <= yi < RING_H - s + 1:
            arr[yi:yi + s, xi:xi + s] = c

    def in_gap(t):
        return any(a <= t <= b for a, b in RING_GAPS)
    # la banda: pedazos de 1-3 px a lo largo de la curva, más tupidos en el centro de la banda
    for k in range(5200):
        t = rng.rand()
        if in_gap(t):
            continue
        x, y = _ring_curve(t)
        off = rng.normal(0, 1.5)
        s = rng.choice([1, 1, 1, 2, 2, 3])
        c = pale if abs(off) < 1.0 else (mid if abs(off) < 2.2 else dark)
        put(x, y + off, c, s)
        if s > 1:
            put(x, y + off - 1, lite, 1)
    # polvo suelto alrededor (un tramado, sin alfa intermedio)
    for k in range(1400):
        t = rng.rand()
        x, y = _ring_curve(t)
        off = rng.normal(0, 4.5)
        xi, yi = int(x), int(y + off)
        if 0 <= yi < RING_H and 0 <= xi < RING_W and arr[yi, xi, 3] == 0 and (xi + yi) % 2 == 0:
            arr[yi, xi] = (206, 196, 184, 255)
    # siluetas: vigas reticuladas (trusses) y grúas, de pie o colgando de la banda
    def truss(t, h, up=True, w=7):
        x, y = _ring_curve(t)
        x0 = int(x) - w // 2
        sgn = -1 if up else 1
        for j in range(h):
            yy = int(y) + sgn * j
            put(x0, yy, mid)
            put(x0 + w - 1, yy, mid)
            if j % 4 == 0:
                for i in range(w):
                    put(x0 + i, yy, mid)
            # diagonales
            put(x0 + (j % 4) * (w - 1) / 3.0, yy, dark)
    def crane(t, h, arm, up=True):
        x, y = _ring_curve(t)
        sgn = -1 if up else 1
        for j in range(h):
            put(x, y + sgn * j, mid, 2)
        top = y + sgn * (h - 1)
        for i in range(-arm // 3, arm):
            put(x + i, top, pale if i % 3 else dark, 1)
            put(x + i, top + 1, mid, 1)
        for j in range(int(h * 0.55)):
            put(x + arm - 1, top - sgn * (-j), dark, 1)
        put(x + arm - 2, top - sgn * (-int(h * 0.55)), lite, 3)
    truss(0.13, 16, True)
    crane(0.39, 18, 20, True)
    truss(0.5, 12, False, 6)
    crane(0.72, 14, -16, True)
    truss(0.94, 20, True, 8)
    # los bordes de cada hueco: puntas rotas (más claras)
    for a, b in RING_GAPS:
        for t in (a, b):
            x, y = _ring_curve(t)
            put(x, y - 2, lite, 2)
            put(x + 1, y + 1, dark, 2)
    return arr


def ring_lamps_uv():
    return [[round(_ring_curve(t)[0], 1), round(_ring_curve(t)[1] - 1.5, 1)] for t in RING_LAMPS_T]


def ring_lamp():
    """Una lámpara guía del anillo (8x8, 2 cuadros: encendida / apagada): ámbar, cálida, como un faro lejano."""
    on = blank(8, 8)
    off = blank(8, 8)
    for (x, y, c) in [(3, 1, (255, 200, 110)), (4, 1, (255, 200, 110)), (1, 3, (255, 200, 110)), (6, 3, (255, 200, 110)),
                      (1, 4, (255, 200, 110)), (6, 4, (255, 200, 110)), (3, 6, (255, 200, 110)), (4, 6, (255, 200, 110))]:
        on[y, x] = c + (255,)
    on[2:6, 2:6] = (255, 226, 150, 255)
    on[3:5, 3:5] = (255, 252, 230, 255)
    off[3:5, 3:5] = (150, 104, 70, 255)
    return strip([on, off])


def spark():
    """Una chispa de la gala (8x8): estrella de 4 puntas dorada con el centro blanco."""
    a = blank(8, 8)
    for i in range(8):
        a[3:5, i] = (255, 206, 96, 255)
        a[i, 3:5] = (255, 206, 96, 255)
    a[2:6, 2:6] = (255, 232, 150, 255)
    a[3:5, 3:5] = (255, 255, 236, 255)
    for (x, y) in ((0, 3), (0, 4), (7, 3), (7, 4), (3, 0), (4, 0), (3, 7), (4, 7)):
        a[y, x] = (240, 160, 70, 255)
    return a


def star_sign_comet():
    """El cartel con el Brass Comet atornillado: la estrella remendada con sus 5 puntas encendidas y una cola de bronce
    hacia abajo a la izquierda (tubos y chapas con focos): la estrella remendada se volvió estrella fugaz.
    128x72: la estrella ocupa los últimos 72 px (su centro en x = 92), así no se mueve al cambiar de cartel."""
    W_, H_ = 128, 72
    cv = cv_new(W_, H_)
    # tres tubos de bronce que se afinan (la cola)
    tails = [([(94, 40), (60, 50), (30, 57), (4, 62)], 8.5, 1.6, 'brass'),
             ([(90, 30), (62, 37), (36, 42), (14, 44)], 5.0, 1.2, 'copper'),
             ([(92, 50), (66, 60), (42, 66), (22, 69)], 4.0, 1.0, 'copper')]
    for pts, r0, r1, m in tails:
        cv.put(cv.stroke(bez3(*pts, n=14), r0, r1), m, mode='shine', cast=1, iline=True)
    # bandas remachadas en el tubo grande y focos encendidos a lo largo
    for t in (0.25, 0.45, 0.65):
        pts = bez3(*tails[0][0], n=21)
        x, y = pts[int(t * 20)]
        cv.put(cv.ellipse(x, y, 1.6, 4.0 - t * 3), 'dkmetal', mode='shine', iline=True)
    for t in (0.15, 0.35, 0.55, 0.75):
        pts = bez3(*tails[0][0], n=21)
        x, y = pts[int(t * 20)]
        keep(cv, cv.put(cv.ellipse(x - 1, y - 2, 1.5, 1.5), 'bulb', mode='flat'))
    tail = render(cv)
    st = star_sign(5)
    out = tail.copy()
    paste(out, st, W_ - 72, 0)
    return out


# ================================================================== la gala y Bronzemoon: banda y faroles

def band_trio(frame=0):
    """The Low Moons, la banda del Slow Orbit (128x80, 2 cuadros): Mo (un Hornback con gorra plana y un bajo hecho con
    un tambor de combustible), Zee (un Quill de cuatro brazos en verde azulado y crema, con bufanda, dos estantes de
    botellas que golpea con cucharas) y Bow (un bot delgado gris pizarra, cabeza redonda de rejilla de parlante, dedos
    largos, un serrucho que canta). Tres especies distintas; sin vientos ni bronces."""
    cv = cv_new(128, 80)
    f = frame
    # ---- Mo (izquierda): el bajo de tambor (un bidón rojo con un palo y una cuerda)
    cv.put(cv.rect(4, 52, 22, 77), 'drum', mode='cyl', cast=1, iline=True)
    for y in (57, 66, 74):
        cv.paint(cv.rect(4, y, 22, y), 'drum2', 1)
    cv.put(cv.ellipse(13, 52, 9, 2.4), 'drum2', mode='flat', iline=True)
    cv.put(cv.stroke([(14, 52), (19 + f, 18)], 0.9), 'wood2', mode='shine', iline=True)
    keep(cv, cv.put(cv.line([(14, 51), (19 + f, 20)]), 'steel', mode='flat', outline=False))
    # cuerpo grande, piel gris azulada, chaleco
    cv.put(cv.ellipse(34, 60, 10, 15) & (cv.ys <= 74), 'hide', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(26, 50, 42, 68), 'leather', mode='cyl', iline=True)
    for x in (28, 37):
        cv.put(cv.rect(x, 72, x + 5, 77), 'hide2', mode='cyl', iline=True)
    # cabeza con hocico, cuernos de carnero y la gorra plana
    cv.put(cv.ellipse(33, 41, 8, 8), 'hide', mode='dome', cast=1, iline=True)
    cv.put(cv.ellipse(28, 45, 4, 3), 'hide2', mode='dome', iline=True)
    cv.dot(31, 40, 'hole', 5)
    cv.dot(35, 40, 'hole', 5)
    for sx in (-1, 1):
        cv.put(cv.stroke([(33 + sx * 6, 38), (33 + sx * 11, 34), (33 + sx * 11, 42)], 1.6, 1.0), 'horn', mode='shine', iline=True)
    cv.put(cv.ellipse(33, 34, 8.5, 2.8) & (cv.ys <= 35), 'cap', mode='top', iline=True)
    cv.put(cv.rect(24, 34, 37, 35), 'cap', mode='flat', iline=True)
    # brazo que pulsa la cuerda
    cv.put(cv.stroke([(28, 54), (22, 46 - f * 2), (19 + f, 40 - f * 2)], 2.0, 1.6), 'hide', mode='cyl', iline=True)
    # ---- Zee (centro): cuatro brazos, dos estantes de botellas, cucharas
    for bx in (46, 74):
        cv.put(cv.rect(bx, 52, bx + 10, 54), 'wood', mode='flat', iline=True)
        cv.put(cv.rect(bx + 1, 54, bx + 2, 77), 'dkmetal', mode='flat', iline=True)
        cv.put(cv.rect(bx + 8, 54, bx + 9, 77), 'dkmetal', mode='flat', iline=True)
        for i, m in enumerate(('bottle_g', 'bottle_a', 'bottle_b')):
            h = 8 - i * 2
            cv.put(cv.rect(bx + 1 + i * 3, 52 - h, bx + 3 + i * 3, 52), m, mode='shine', iline=True)
    # piernas largas, abrigo verde azulado, bufanda naranja, cresta de pluma, gafas
    for x in (60, 65):
        cv.put(cv.rect(x, 62, x + 2, 77), 'quill2', mode='cyl', iline=True)
    cv.put(cv.poly([(57, 40), (70, 40), (72, 64), (55, 64)]), 'quill', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(57, 38, 70, 42), 'scarf', mode='cyl', iline=True)
    cv.put(cv.stroke([(68, 42), (72, 50)], 1.4), 'scarf', mode='cyl', iline=True)
    cv.put(cv.ellipse(63, 31, 6, 7), 'quill2', mode='dome', cast=1, iline=True)
    cv.put(cv.rect(58, 29, 68, 31), 'dkmetal', mode='shine', iline=True)
    for x in (60, 65):
        cv.dot(x, 30, 'glass', 5)
    for k, (dx, dy) in enumerate(((-3, -8), (0, -11), (3, -9))):
        cv.put(cv.stroke([(63, 25), (63 + dx, 25 + dy)], 1.2, 0.6), 'feather', mode='shine', iline=True)
    # cuatro brazos con cucharas: dos a cada estante (arriba / abajo alternan con el cuadro)
    for side, bx in ((-1, 51), (1, 79)):
        for k, yy in enumerate((44, 52)):
            up = (k + f) % 2
            hx, hy = bx, 47 - up * 4 + k * 2
            cv.put(cv.stroke([(63 + side * 5, yy), (hx, hy)], 1.3), 'quill', mode='cyl', iline=True)
            keep(cv, cv.put(cv.stroke([(hx, hy), (hx + side * -1, hy + 4 - up * 2)], 0.6), 'spoon', mode='shine'))
    # ---- Bow (derecha): bot delgado, cabeza redonda de rejilla, el serrucho entre las rodillas y el arco
    for x in (101, 108):
        cv.put(cv.rect(x, 58, x + 2, 77), 'slate2', mode='cyl', iline=True)
    cv.put(cv.rect(99, 76, 104, 77), 'slate2', mode='flat', iline=True)
    cv.put(cv.rect(106, 76, 111, 77), 'slate2', mode='flat', iline=True)
    cv.put(cv.rect(100, 36, 110, 58), 'slate', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(102, 40, 108, 44), 'mint', 2)
    cv.put(cv.rect(104, 31, 106, 36), 'slate2', mode='cyl', iline=True)
    hd = cv.ellipse(105, 24, 8, 8)
    cv.put(hd, 'slate', mode='dome', cast=1, iline=True)
    cv.put(cv.ellipse(105, 24, 5.5, 5.5), 'grille', mode='flat', iline=True)
    for y in range(20, 29, 2):
        cv.paint(cv.rect(101, y, 109, y) & cv.ellipse(105, 24, 5.0, 5.0), 'steel', 2)
    # el serrucho (curvado) entre las rodillas, y el arco
    saw = cv.stroke(bez((104, 58), (96 - f, 52), (93 - f, 40), 10), 1.6, 0.8)
    keep(cv, cv.put(saw, 'saw', mode='shine', iline=True))
    cv.put(cv.stroke([(108, 46), (100 - f * 2, 49 + f)], 1.1), 'slate', mode='cyl', iline=True)
    cv.put(cv.stroke([(100, 40), (95 - f, 42)], 1.0), 'slate', mode='cyl', iline=True)
    keep(cv, cv.put(cv.line([(100 - f * 2, 49 + f), (90 - f * 2, 44 + f)]), 'wood3', mode='flat', outline=False))
    # notas de música: dos negras flotando (cambian de lugar con el cuadro)
    for (x, y) in ((46 + f * 3, 14), (88 - f * 2, 10 + f * 2)):
        cv.put(cv.ellipse(x, y + 4, 1.8, 1.4), 'amber', mode='flat')
        cv.put(cv.rect(int(x + 1), y - 2, int(x + 1), y + 4), 'amber', mode='flat')
    return render(cv)


def band_trio_window(frame=0):
    """La banda chiquita, vista por la ventana de la tienda (la misma, a mitad de tamaño)."""
    big = Image.fromarray(band_trio(frame), 'RGBA')
    return np.array(big.resize((64, 40), Image.NEAREST))


def lantern_string():
    """Una guirnalda de faroles de papel (192x28): un cable combado y siete faroles ámbar, verde agua y rosa, con su
    tapita oscura. Se dibuja sin sombra (sprite sin luz: brilla de noche)."""
    W_, H_ = 192, 28
    cv = cv_new(W_, H_)
    pts = [(x, 3 + 9 * math.sin(math.pi * x / (W_ - 1))) for x in range(0, W_, 4)]
    keep(cv, cv.put(cv.stroke(pts, 0.6), 'wire', mode='flat'))
    cols = ['lantern_a', 'lantern_t', 'lantern_r']
    for k in range(7):
        x = 14 + k * 27
        y = 3 + 9 * math.sin(math.pi * x / (W_ - 1))
        keep(cv, cv.put(cv.line([(x, y), (x, y + 3)]), 'wire', mode='flat'))
        body = cv.ellipse(x, y + 9, 4.6, 5.6)
        keep(cv, cv.put(body, cols[k % 3], mode='flat', iline=True))
        cv.paint(cv.ellipse(x - 1, y + 8, 1.6, 2.4) & body, 'bulb', 2)
        for yy in (y + 6, y + 12):
            cv.paint(cv.rect(int(x - 4), int(yy), int(x + 4), int(yy)) & body, 'wire', 1)
        cv.put(cv.rect(int(x - 2), int(y + 3), int(x + 2), int(y + 4)), 'dkmetal', mode='flat')
        cv.put(cv.rect(int(x - 1), int(y + 15), int(x + 1), int(y + 15)), 'dkmetal', mode='flat')
    return render(cv)


# ================================================================== la calle: la vecina, el patio, los tablones

def rrect(cv, x0, y0, x1, y1, r):
    """Rectángulo de esquinas redondeadas (máscara)."""
    m = cv.rect(x0 + r, y0, x1 - r, y1) | cv.rect(x0, y0 + r, x1, y1 - r)
    for cx, cy in ((x0 + r, y0 + r), (x1 - r, y0 + r), (x0 + r, y1 - r), (x1 - r, y1 - r)):
        m |= cv.ellipse(cx, cy, r + 0.4, r + 0.4)
    return m


def sparkle_pts(cx, cy, rl, rs, rin):
    """Destello: 4 puntas largas (arriba, abajo, izquierda, derecha) y 4 cortas en diagonal; sólido (nunca 8 rayos
    iguales y afilados)."""
    pts = []
    for k in range(16):
        a = math.radians(-90 + k * 22.5)
        if k % 4 == 0:
            r = rl
        elif k % 4 == 2:
            r = rs
        else:
            r = rin
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def shine_facade():
    """El frente de Shine Again (la casa de la izquierda desde el día 3): paneles de esmalte blanco de esquinas
    redondeadas, una vidriera curva con cosas relucientes, una puerta blanca con ojo de buey cromado, filetes rosa y
    una franja verde agua abajo. Sin letras (SHINE AGAIN es un Label3D de neón)."""
    W_, H_ = 180, 86
    cv = cv_new(W_, H_)
    base = cv.rect(0, 6, W_ - 1, H_ - 1)
    p = cv.put(base, 'enamel', mode='flat', iline=True)
    # paneles redondeados (juntas)
    for x0 in range(2, W_ - 20, 30):
        cv.shade(rrect(cv, x0, 8, x0 + 27, 60, 4) & ~rrect(cv, x0 + 1, 9, x0 + 26, 59, 3), -1, within=[p])
    cv.paint(cv.rect(0, 6, W_ - 1, 8), 'pink', 2)
    cv.paint(cv.rect(0, 74, W_ - 1, H_ - 1), 'quill', 2)
    cv.paint(cv.rect(0, 72, W_ - 1, 73), 'pink', 2)
    # la vidriera curva (izquierda-centro): marco cromado, vidrio y cosas que brillan
    win = rrect(cv, 70, 22, 128, 64, 9)
    cv.put(win, 'chrome', mode='shine', cast=1, iline=True)
    gl = rrect(cv, 73, 25, 125, 61, 7)
    q = cv.put(gl, 'glass2', mode='flat', iline=True)
    cv.put(cv.rect(74, 52, 124, 54), 'chrome2', mode='flat', iline=True)
    # en la vidriera: una pava cromada, una radio rosa, un robotito brillante
    cv.put(cv.ellipse(84, 47, 6, 5), 'chrome', mode='dome', cast=1, iline=True)
    cv.put(cv.stroke([(89, 45), (93, 41)], 1.2), 'chrome', mode='shine', iline=True)
    box(cv, 98, 40, 110, 51, 'pink', depth=(2, -2))
    cv.put(cv.ellipse(102, 46, 2.2, 2.2), 'chrome2', mode='flat')
    cv.put(cv.rect(114, 40, 121, 51), 'chrome', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(117.5, 37, 3.6, 3.2), 'chrome', mode='dome', iline=True)
    cv.dot(116, 37, 'neont', 4)
    for (x, y) in ((80, 30), (95, 33), (108, 29), (121, 33), (88, 36)):
        keep(cv, cv.put(cv.rect(x, y, x, y), 'white', mode='flat', outline=False))
        cv.dot(x - 1, y, 'white', 3)
        cv.dot(x + 1, y, 'white', 3)
    cv.shade(cv.line([(76, 58), (96, 27)]), 2, within=[q])
    cv.shade(cv.line([(80, 59), (100, 28)]), 1, within=[q])
    # la puerta (derecha): blanca, ojo de buey cromado, tirador
    door = rrect(cv, 140, 24, 162, 76, 5)
    d = cv.put(door, 'enamel2', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(151, 37, 5.5, 5.5), 'chrome', mode='shine', iline=True)
    cv.put(cv.ellipse(151, 37, 3.8, 3.8), 'glass2', mode='flat')
    cv.dot(150, 36, 'white', 4)
    cv.put(cv.rect(157, 50, 159, 56), 'chrome', mode='shine', iline=True)
    cv.paint(cv.rect(140, 64, 162, 65) & door, 'pink', 2)
    # una ventana chica a la izquierda con persiana rosa
    cv.put(rrect(cv, 18, 26, 44, 50, 5), 'chrome', mode='shine', cast=1, iline=True)
    cv.put(rrect(cv, 20, 28, 42, 48, 4), 'pink', mode='flat', iline=True)
    for y in range(30, 48, 3):
        cv.paint(cv.rect(21, y, 41, y), 'pink2', 2)
    return render(cv)


def shine_star():
    """El destello espejado de Shine Again (sobre la puerta): 4 puntas largas y 4 cortas, gordas y sólidas (nunca 8
    rayos iguales y afilados), cromo con reflejos rosa y verde agua."""
    cv = cv_new(48, 48)
    st = cv.poly(sparkle_pts(24, 24, 22, 12, 8.0))
    p = cv.put(st, 'chrome', mode='dome', cast=1, iline=True)
    cv.set_nrm(p, cv.sphere_n(21, 21, 17, 17, k=0.8))
    cv.paint(cv.poly([(24, 2), (30, 18), (24, 24), (18, 18)]) & st, 'pink', 3)
    cv.paint(cv.poly([(46, 24), (30, 30), (24, 24), (30, 18)]) & st, 'neont', 2)
    cv.paint(cv.poly([(24, 46), (18, 30), (24, 24), (30, 30)]) & st, 'pink', 2)
    cv.dot(20, 19, 'white', 4)
    cv.dot(21, 18, 'white', 4)
    cv.dot(22, 19, 'white', 4)
    return render(cv)


def shine_carpet():
    """La alfombra roja de Shine Again, vista desde arriba (va acostada en el suelo): roja con bordes dorados."""
    cv = cv_new(28, 72)
    c = cv.rect(2, 0, 25, 71)
    cv.put(c, 'carpet', mode='flat', iline=True)
    for x in (3, 24):
        cv.paint(cv.rect(x, 0, x, 71), 'gold', 2)
    for y in range(6, 70, 10):
        cv.paint(cv.rect(4, y, 23, y), 'carpet', 1)
    return render(cv)


def chrome_plant():
    """Una planta de cromo en maceta de cromo (Shine Again): hojas en punta plateadas y verde agua."""
    cv = cv_new(22, 36)
    for k, (dx, h) in enumerate(((-6, 12), (-3, 18), (0, 22), (3, 17), (6, 13))):
        leaf = cv.poly([(11 + dx * 0.4 - 1.5, 22), (11 + dx * 0.4 + 1.5, 22), (11 + dx, 22 - h)])
        cv.put(leaf, 'chrome' if k % 2 else 'mint', mode='shine', cast=1, iline=True)
    pot = cv.poly([(4, 21), (18, 21), (16, 35), (6, 35)])
    cv.put(pot, 'chrome', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(3, 20, 19, 22), 'chrome2', mode='shine', iline=True)
    return render(cv)


def boarded_poster():
    """La casa de al lado tapiada (días 1-2): tablas clavadas en cruz sobre la puerta en arco y un afiche rosa con un
    destello y una radio reluciente (sin letras: COMING SOON es un Label3D)."""
    cv = cv_new(56, 60)
    for (a, b) in (((4, 14), (52, 50)), ((4, 48), (52, 18)), ((2, 30), (54, 32))):
        cv.put(cv.stroke([a, b], 2.4), 'wood3', mode='cyl', cast=1, iline=True)
    for (x, y) in ((6, 15), (50, 49), (6, 47), (50, 19), (4, 31), (52, 31)):
        cv.dot(x, y, 'dkmetal', 3)
    ps = cv.rect(16, 2, 40, 30)
    p = cv.put(ps, 'pink', mode='flat', cast=1, iline=True)
    cv.paint(cv.rect(16, 2, 40, 4), 'enamel', 2)
    st = cv.poly(sparkle_pts(23, 13, 7, 3.5, 1.6))
    cv.put(st, 'enamel', mode='flat', iline=True)
    box(cv, 27, 15, 37, 24, 'chrome', depth=(1, -1))
    cv.put(cv.ellipse(30, 20, 1.8, 1.8), 'chrome2', mode='flat')
    cv.put(cv.poly([(36, 30), (40, 26), (40, 30)]), 'paper', mode='flat')
    return render(cv)


def vendor_crates():
    """El patio de Dolly: una pila de cajones con mejoras encima (una urna de cobre, una lámpara de lupa, un asiento
    crema) y una eslinga de carga."""
    cv = cv_new(72, 56)
    box(cv, 4, 34, 30, 54, 'wood3', top='plank', side='wood2', depth=(3, -3))
    box(cv, 32, 38, 66, 54, 'teal', top='tealp', side='teal2', depth=(3, -3))
    box(cv, 10, 18, 28, 33, 'wood3', top='plank', side='wood2', depth=(2, -2))
    for (x0, y0, x1, y1) in ((4, 34, 30, 54), (10, 18, 28, 33)):
        for x in (x0 + 4, x1 - 4):
            cv.paint(cv.rect(x, y0, x + 1, y1), 'dkmetal', 2)
    # la urna de cobre sobre la caja alta
    cv.put(cv.ellipse(19, 10, 5, 7) & (cv.ys <= 16), 'copper', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(16, 2, 22, 4), 'copper', mode='shine', iline=True)
    cv.put(cv.stroke([(24, 12), (27, 14)], 0.8), 'brass', mode='shine', iline=True)
    # el asiento crema sobre la caja verde
    cv.put(rrect(cv, 36, 22, 52, 36, 3), 'cream', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(36, 32, 60, 37), 'cream', mode='top', iline=True)
    cv.put(cv.rect(54, 26, 57, 33), 'chrome', mode='shine', iline=True)
    # la lámpara de lupa (verde agua) apoyada
    cv.put(cv.stroke([(60, 37), (64, 24), (58, 18)], 0.9), 'tealp', mode='shine', iline=True)
    cv.put(cv.ellipse(57, 17, 3.6, 3.6), 'brass', mode='shine', iline=True)
    cv.put(cv.ellipse(57, 17, 2.4, 2.4), 'glass', mode='flat')
    # la eslinga
    keep(cv, cv.put(cv.stroke(bez((30, 35), (34, 28), (38, 22), 6), 0.5), 'cable_y', mode='flat'))
    return render(cv)


def notice_board():
    """El tablón de anuncios en la fachada de Nell: corcho en un tablón con marco, un calendario de papel con los diez
    días marcados con rayitas, un recibo y una tarjeta; deja lugar a la derecha para el afiche del próximo evento."""
    cv = cv_new(48, 36)
    fr = cv.rect(0, 0, 47, 35)
    cv.put(fr, 'wood2', mode='flat', cast=1, iline=True)
    ck = cv.rect(3, 3, 44, 32)
    p = cv.put(ck, 'cork', mode='flat', iline=True)
    for (x, y) in ((8, 8), (14, 22), (30, 6), (38, 28), (24, 15)):
        cv.dot(x, y, 'cork2', 2)
    # calendario: 2 filas de 5 casilleros
    cal = cv.rect(5, 5, 23, 22)
    cv.put(cal, 'paper', mode='flat', cast=1, iline=True)
    cv.paint(cv.rect(5, 5, 23, 7), 'red', 2)
    for r in range(2):
        for c in range(5):
            x, y = 6 + c * 3.6, 10 + r * 6
            cv.paint(cv.rect(int(x), int(y), int(x) + 2, int(y) + 4), 'paper', 1)
    cv.dot(9, 11, 'red', 2)
    cv.dot(13, 11, 'red', 2)
    # una tarjeta y un recibo
    cv.put(cv.rect(7, 25, 19, 30), 'boardc', mode='flat', iline=True)
    cv.put(cv.rect(9, 27, 16, 27), 'wire', mode='flat')
    for (x, y) in ((14, 5), (13, 25)):
        cv.dot(x, y, 'red', 3)
    return render(cv)


def poster_frame():
    """Un afiche de papel en blanco con una esquina rota (para el pictograma del evento, R: event_<id>.png)."""
    cv = cv_new(32, 40)
    pp = cv.poly([(1, 1), (30, 1), (30, 32), (25, 38), (1, 38)])
    cv.put(pp, 'paper', mode='flat', cast=1, iline=True)
    cv.put(cv.poly([(30, 32), (25, 38), (25, 32)]), 'cream', mode='flat', iline=True)
    cv.dot(15, 2, 'red', 3)
    return render(cv)


def departure_board():
    """El tablero de salidas (negro y crema, como los de las estaciones): marco remachado, 5 renglones vacíos (las
    filas son Label3D en la fuente mono) y una tejadita de chapa."""
    cv = cv_new(80, 44)
    cv.put(cv.poly([(0, 6), (79, 6), (74, 0), (5, 0)]), 'rust', mode='top', cast=1, iline=True)
    fr = cv.rect(1, 6, 78, 43)
    cv.put(fr, 'dkmetal', mode='flat', cast=1, iline=True)
    bd = cv.rect(4, 9, 75, 40)
    cv.put(bd, 'board', mode='flat', iline=True)
    for r in range(5):
        y = 11 + r * 6
        cv.paint(cv.rect(5, y + 5, 74, y + 5), 'iron', 2)
    for (x, y) in ((2, 8), (77, 8), (2, 41), (77, 41)):
        cv.dot(x, y, 'steel', 3)
    return render(cv)


def lounge_sign():
    """El letrero del Slow Orbit: un planeta de neón con su anillo (rosa y verde agua) sobre una chapa oscura."""
    cv = cv_new(44, 30)
    cv.put(rrect(cv, 1, 1, 42, 28, 4), 'iron', mode='flat', iline=True)
    pl = cv.ellipse(22, 15, 8, 8)
    keep(cv, cv.put(pl & ~cv.ellipse(22, 15, 6.6, 6.6), 'neonp', mode='flat', outline=False))
    ring = cv.ellipse(22, 16, 17, 4.2) & ~cv.ellipse(22, 16, 15.4, 3.0)
    keep(cv, cv.put(ring & ~(cv.ellipse(22, 15, 8.2, 8.2) & (cv.ys < 16)), 'neont', mode='flat', outline=False))
    for (x, y) in ((8, 6), (36, 24), (34, 6)):
        keep(cv, cv.put(cv.rect(x, y, x, y), 'lantern_a', mode='flat', outline=False))
    return render(cv, outline=False)


def glint_balloon(frame=0):
    """El globo de cromo de Glint (día 8: inflado con su cuerda; día 9: desinflado y colgando sobre el techo)."""
    cv = cv_new(56, 72)
    if frame == 0:
        b = cv.ellipse(28, 24, 18, 21)
        p = cv.put(b, 'chrome', mode='dome', cast=1, iline=True)
        cv.set_nrm(p, cv.sphere_n(24, 18, 20, 23, k=0.9))
        cv.paint(cv.ellipse(20, 14, 4, 6) & b, 'white', 3)
        cv.paint(cv.poly(sparkle_pts(32, 26, 8, 4, 1.8)), 'pink', 2)
        cv.put(cv.poly([(25, 44), (31, 44), (28, 48)]), 'chrome2', mode='flat', iline=True)
        keep(cv, cv.put(cv.stroke(bez((28, 48), (24, 58), (30, 71), 8), 0.5), 'wire', mode='flat'))
    else:
        skin = cv.poly([(2, 58), (12, 50), (24, 54), (34, 48), (46, 54), (54, 60), (50, 66), (36, 62), (22, 66), (8, 64)])
        cv.put(skin, 'chrome', mode='cyl', cast=1, iline=True)
        for x in (12, 24, 36, 46):
            cv.shade(cv.line([(x, 54), (x - 2, 64)]), -2)
        cv.paint(cv.poly(sparkle_pts(30, 58, 5, 2.5, 1.2)), 'pink', 2)
        keep(cv, cv.put(cv.stroke(bez((50, 64), (53, 68), (55, 71), 5), 0.5), 'wire', mode='flat'))
    return render(cv)


def tally_banner():
    """El estandarte de la Tally Office (el día de la inspección): tela mostaza con el emblema de la marca de
    conteo (cuatro palotes cruzados por un quinto; nunca un engranaje) y flecos; cuelga de un travesaño."""
    cv = cv_new(30, 56)
    cv.put(cv.rect(0, 0, 29, 2), 'dkmetal', mode='shine', iline=True)
    bn = cv.poly([(3, 3), (26, 3), (26, 46), (14.5, 53), (3, 46)])
    p = cv.put(bn, 'mustard', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(3, 3, 26, 5), 'navy', 2)
    cv.put(cv.rect(5, 15, 24, 33), 'cream', mode='flat', iline=True)
    for k in range(4):
        x = 8.5 + k * 3.4
        cv.put(cv.rect(int(x), 18, int(x) + 1, 30), 'navy', mode='flat')
    cv.put(cv.stroke([(6, 27), (23, 21)], 0.8), 'navy', mode='flat')
    for x in range(5, 25, 3):
        cv.paint(cv.rect(x, 40, x, 44) & bn, 'mustard2', 2)
    return render(cv)


def smoke_column(frame=0):
    """La columna de humo de Bigfall en el horizonte (4 cuadros que ondulan): bocanadas que suben, se abren y se
    inclinan con el viento; luz arriba a la izquierda, brasas en la base."""
    W_, H_ = 64, 140
    arr = blank(W_, H_)
    rng = np.random.RandomState(5)
    yy, xx = np.mgrid[0:H_, 0:W_].astype(np.float32)
    ramp = [(62, 52, 52), (88, 74, 70), (116, 98, 90), (146, 126, 112), (176, 156, 138)]
    puffs = []
    for k in range(34):
        t = k / 33.0
        y = H_ - 8 - t * (H_ - 22)
        sway = math.sin(t * 5.0 + frame * math.pi / 2) * (2 + t * 5) + t * t * 14
        x = W_ / 2 - 6 + sway + rng.uniform(-2, 2) * (1 + t * 2)
        r = 3.5 + t * 9 + rng.uniform(0, 2.5)
        puffs.append((x, y, r, t))
    lvl = np.full((H_, W_), -1, np.int32)
    for x, y, r, t in puffs:
        d = np.sqrt((xx - x) ** 2 + (yy - y) ** 2)
        m = d <= r
        # luz arriba a la izquierda dentro de cada bocanada
        lit = ((x - xx) * 0.6 + (y - yy) * 0.8) / max(r, 1.0)
        base = min(4, int(t * 3.2) + 1)
        v = np.clip(base + np.round(lit * 1.2), 0, 4).astype(np.int32)
        lvl = np.where(m, v, lvl)
    for k in range(5):
        arr[lvl == k] = ramp[k] + (255,)
    for (x, y) in ((28, 132), (32, 130), (25, 128), (33, 134), (29, 127)):
        arr[y:y + 2, x:x + 2] = (255, 150, 60, 255)
    return arr


def wreck_glow():
    """El resplandor del naufragio de Bigfall de noche: vigas y aros caídos recortados contra un brillo naranja."""
    cv = cv_new(96, 36)
    gl = cv.ellipse(48, 34, 46, 14)
    keep(cv, cv.put(gl, 'glow2', mode='flat', outline=False))
    keep(cv, cv.put(cv.ellipse(48, 35, 30, 8), 'glow', mode='flat', outline=False))
    for (x0, y0, x1, y1) in ((20, 34, 34, 16), (34, 16, 40, 34), (56, 34, 70, 20), (70, 20, 76, 34)):
        cv.put(cv.stroke([(x0, y0), (x1, y1)], 1.0), 'iron', mode='flat')
    ring = cv.ellipse(52, 26, 9, 9) & ~cv.ellipse(52, 26, 7, 7) & (cv.ys < 34)
    cv.put(ring, 'iron', mode='flat')
    return render(cv, outline=False)


def pennants(kind='bunting'):
    """Una guirnalda de banderines en V (bunting: crema, rosa, verde agua, ámbar; race: a cuadros y rojo)."""
    W_, H_ = 192, 26
    cv = cv_new(W_, H_)
    pts = [(x, 2 + 7 * math.sin(math.pi * x / (W_ - 1))) for x in range(0, W_, 4)]
    keep(cv, cv.put(cv.stroke(pts, 0.5), 'wire', mode='flat'))
    cols = ['flagc', 'pink', 'flagt', 'amber'] if kind == 'bunting' else ['flagc', 'flagr', 'board', 'flagr']
    for k in range(11):
        x = 6 + k * 17.5
        y = 2 + 7 * math.sin(math.pi * x / (W_ - 1))
        tri = cv.poly([(x - 6, y), (x + 6, y), (x, y + 13)])
        cv.put(tri, cols[k % 4], mode='flat', iline=True)
        if kind == 'race' and k % 4 == 2:
            for j in range(0, 12, 3):
                cv.paint(cv.rect(int(x - 6 + j), int(y), int(x - 5 + j), int(y + 2)) & tri, 'boardc', 2)
                cv.paint(cv.rect(int(x - 4 + j), int(y + 3), int(x - 3 + j), int(y + 5)) & tri, 'boardc', 2)
    return render(cv)


def moon_banner():
    """El estandarte de Bronzemoon: tela azul noche con las dos lunas llenas (una grande cobre, una chica plata) y un
    halo de bronce; flecos dorados."""
    cv = cv_new(24, 52)
    cv.put(cv.rect(0, 0, 23, 2), 'brass', mode='shine', iline=True)
    bn = cv.poly([(2, 3), (21, 3), (21, 44), (11.5, 50), (2, 44)])
    cv.put(bn, 'navy', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(11, 18, 6.4, 6.4) & ~cv.ellipse(11, 18, 5.4, 5.4), 'amber', mode='flat')
    cv.put(cv.ellipse(11, 18, 4.6, 4.6), 'copperp', mode='dome', iline=True)
    cv.put(cv.ellipse(15, 31, 2.6, 2.6), 'tin', mode='dome', iline=True)
    for x in range(4, 20, 3):
        cv.paint(cv.rect(x, 41, x, 44) & bn, 'gold', 2)
    return render(cv)


def race_gate():
    """La puerta de largada del Glasspan Derby (lejos, más allá de las plataformas): un arco de vigas con banderines a
    cuadros y tres luces de largada."""
    cv = cv_new(96, 60)
    for x in (6, 86):
        cv.put(cv.rect(x, 10, x + 4, 59), 'rust', mode='cyl', cast=1, iline=True)
    beam = cv.rect(4, 8, 92, 16)
    p = cv.put(beam, 'flagc', mode='cyl', cast=1, iline=True)
    for x in range(4, 92, 6):
        cv.paint(cv.rect(x, 8, x + 2, 11), 'board', 2)
        cv.paint(cv.rect(x + 3, 12, x + 5, 15), 'board', 2)
    for k, m in enumerate(('flagr', 'amber', 'mint')):
        keep(cv, cv.put(cv.ellipse(38 + k * 10, 22, 3.2, 3.2), m, mode='flat', iline=True))
    cv.put(cv.rect(34, 17, 62, 18), 'dkmetal', mode='flat', iline=True)
    return render(cv)


def cloth_flap(frame=0):
    """Un trapo que flamea al viento del Scour (2 cuadros)."""
    cv = cv_new(28, 18)
    if frame == 0:
        pts = [(1, 2), (14, 1), (27, 4), (25, 9), (14, 7), (2, 9)]
    else:
        pts = [(1, 2), (12, 4), (27, 2), (26, 8), (12, 10), (2, 9)]
    cv.put(cv.poly(pts), 'canvas', mode='cyl', cast=1, iline=True)
    cv.paint(cv.poly(pts) & cv.rect(0, 4, 27, 5), 'stripe', 2)
    cv.put(cv.rect(0, 0, 1, 12), 'wood2', mode='flat', iline=True)
    return render(cv)


def stall_tarp():
    """La lona que tapa el mostrador de Raker el día del Scour (cerrado): lona verde oliva atada con sogas."""
    cv = cv_new(88, 40)
    t = cv.poly([(2, 10), (84, 8), (86, 36), (4, 38)])
    p = cv.put(t, 'tarp', mode='cyl', cast=1, iline=True)
    for x in (16, 44, 70):
        cv.shade(cv.line([(x, 9), (x - 3, 37)]), -2, within=[p])
        keep(cv, cv.put(cv.line([(x + 4, 6), (x + 4, 39)]), 'cable_y', mode='flat'))
    cv.paint(cv.rect(4, 30, 84, 33) & t, 'tarp2', 2)
    for (x, y) in ((6, 12), (82, 10), (8, 36), (82, 34)):
        cv.dot(x, y, 'brass', 3)
    return render(cv)


def facade_awning():
    """El toldo a rayas sobre la puerta de Nell (Cool Coil: la tienda fresca): rayas crema y verde agua, volado."""
    cv = cv_new(64, 22)
    roof = cv.poly([(0, 14), (63, 14), (58, 2), (5, 2)])
    p = cv.put(roof, 'canvas', mode='top', cast=2, iline=True)
    for x in range(0, 64, 10):
        cv.paint(cv.poly([(x, 14), (x + 5, 14), (x + 5 - 3, 2), (x - 3, 2)]) & roof, 'tealp', 2)
    for k in range(0, 64, 8):
        sc = cv.ellipse(k + 4, 14, 4.2, 4.0) & (cv.ys >= 14)
        cv.put(sc, 'canvas' if (k // 8) % 2 else 'tealp', mode='flat', iline=True)
    return render(cv)


def neon_street(frame=0):
    """La estrella de neón en la ventana redonda de la fachada (Neon Star): rosa y verde agua (2 cuadros: parpadea)."""
    cv = cv_new(24, 24)
    st = []
    for k in range(10):
        a = math.radians(-90 + k * 36)
        r = 10 if k % 2 == 0 else 4.4
        st.append((12 + math.cos(a) * r, 12.5 + math.sin(a) * r))
    outer = cv.poly(st)
    inner = cv.poly([(12 + (x - 12) * 0.62, 12.5 + (y - 12.5) * 0.62) for x, y in st])
    keep(cv, cv.put(outer & ~inner, 'neonp' if frame == 0 else 'pink2', mode='flat', outline=False))
    keep(cv, cv.put(cv.ellipse(12, 12.5, 1.6, 1.6), 'neont', mode='flat', outline=False))
    return render(cv, outline=False)


# ================================================================== el taller: letras chiquitas (palabras comunes)

FONT3 = {
    'A': ['.#.', '#.#', '###', '#.#', '#.#'], 'D': ['##.', '#.#', '#.#', '#.#', '##.'], 'E': ['###', '#..', '##.', '#..', '###'],
    'F': ['###', '#..', '##.', '#..', '#..'], 'H': ['#.#', '#.#', '###', '#.#', '#.#'], 'I': ['###', '.#.', '.#.', '.#.', '###'],
    'L': ['#..', '#..', '#..', '#..', '###'], 'N': ['#..#', '##.#', '#.##', '#..#', '#..#'], 'O': ['###', '#.#', '#.#', '#.#', '###'],
    'P': ['##.', '#.#', '##.', '#..', '#..'], 'R': ['##.', '#.#', '##.', '#.#', '#.#'], 'T': ['###', '.#.', '.#.', '.#.', '.#.'],
    'U': ['#.#', '#.#', '#.#', '#.#', '###'], 'V': ['#.#', '#.#', '#.#', '#.#', '.#.'], 'X': ['#.#', '#.#', '.#.', '#.#', '#.#'],
    ' ': ['..', '..', '..', '..', '..'],
}


def text_mask(cv, text, x, y, scale=1):
    """Máscara de un texto en la letra de 3x5 (solo palabras comunes en inglés: nunca nombres propios)."""
    m = np.zeros((cv.h, cv.w), bool)
    cx = x
    for ch in text:
        g = FONT3[ch]
        for r, row in enumerate(g):
            for c, v in enumerate(row):
                if v == '#':
                    y0, x0 = y + r * scale, cx + c * scale
                    m[max(0, y0):y0 + scale, max(0, x0):x0 + scale] = True
        cx += (len(g[0]) + 1) * scale
    return m


def text_w(text, scale=1):
    return sum((len(FONT3[c][0]) + 1) * scale for c in text) - scale


# ================================================================== el taller vivido (§6.1)

def fg_bike_frame():
    """Primer plano (borroso): el cuadro de una hoverbike de un asiento colgado de dos cadenas: propulsor trasero
    gordo, nariz corta (nada de paletas largas adelante)."""
    cv = cv_new(96, 80)
    for x in (24, 70):
        keep(cv, cv.put(cv.rect(x, 0, x + 1, 34), 'iron', mode='flat'))
        for y in range(2, 34, 4):
            cv.dot(x, y, 'steel', 3)
    body = cv.poly([(14, 46), (60, 40), (80, 44), (84, 52), (60, 58), (18, 58)])
    cv.put(body, 'rust', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(18, 52, 12, 9), 'dkmetal', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(10, 52, 4, 7), 'iron', mode='flat', iline=True)
    cv.put(cv.poly([(38, 40), (56, 38), (58, 42), (40, 44)]), 'leather', mode='top', iline=True)
    cv.put(cv.stroke([(70, 44), (74, 32), (80, 30)], 1.2), 'steel', mode='shine', iline=True)
    cv.put(cv.rect(30, 58, 70, 60), 'iron', mode='flat', iline=True)
    for x in (24, 70):
        cv.put(cv.rect(x - 1, 34, x + 2, 38), 'iron', mode='flat', iline=True)
    return render(cv)


def fg_cable_coil():
    """Primer plano: un rollo de cable gordo con la punta suelta."""
    cv = cv_new(48, 32)
    for k, (r0, m) in enumerate(((18, 'cable_k'), (13, 'cable_r'), (8, 'cable_k'))):
        ring = cv.ellipse(24, 20, r0, r0 * 0.55) & ~cv.ellipse(24, 20, r0 - 4, (r0 - 4) * 0.55)
        cv.put(ring, m, mode='stroke', nrm=cv.sphere_n(23, 19, r0 + 2, r0 * 0.6), cast=1, iline=True)
    cv.put(cv.stroke([(40, 22), (46, 28)], 1.6), 'cable_k', mode='cyl', iline=True)
    return render(cv)


def fg_pod_shells():
    """Primer plano: cáscaras de cápsulas de chatarra abiertas, apiladas."""
    cv = cv_new(64, 40)
    for (cx, cy, rx, ry, m) in ((18, 28, 15, 10, 'hull2'), (44, 30, 16, 9, 'scrap'), (30, 18, 13, 9, 'hull')):
        sh = cv.ellipse(cx, cy, rx, ry) & (cv.ys >= cy - ry * 0.2)
        p = cv.put(sh, m, mode='dome', cast=1, iline=True)
        cv.put(cv.ellipse(cx, cy - ry * 0.2, rx * 0.8, ry * 0.3) & sh, 'hole', mode='flat')
        cv.paint(cv.rect(int(cx - rx), int(cy + ry * 0.4), int(cx + rx), int(cy + ry * 0.5)) & sh, 'amber', 2)
    return render(cv)


def fg_oil_drum():
    """Primer plano: un bidón de aceite azul petróleo con una franja roja y abolladuras."""
    cv = cv_new(32, 48)
    cv.put(cv.rect(4, 6, 27, 46), 'oil', mode='cyl', cast=1, iline=True)
    for y in (14, 30):
        cv.paint(cv.rect(4, y, 27, y + 1), 'dkmetal', 2)
    cv.paint(cv.rect(4, 20, 27, 24), 'oil2', 2)
    cv.put(cv.ellipse(15.5, 6, 11.5, 3), 'dkmetal', mode='flat', iline=True)
    cv.dot(20, 5, 'steel', 3)
    return render(cv)


def fg_engine_block():
    """Primer plano: un bloque de motor viejo (caja de chapa con aletas y dos caños), sin cúpulas ni paneles famosos."""
    cv = cv_new(64, 48)
    pf, pt, ps = box(cv, 6, 18, 50, 46, 'dkmetal', top='steel', side='iron', depth=(5, -5))
    for x in range(10, 48, 5):
        cv.paint(cv.rect(x, 22, x + 1, 42), 'iron', 2)
    cv.put(cv.stroke([(48, 26), (58, 20), (60, 10)], 2.2), 'copper', mode='shine', cast=1, iline=True)
    cv.put(cv.stroke([(14, 18), (12, 8), (20, 4)], 1.8), 'steel', mode='shine', cast=1, iline=True)
    cv.put(cv.rect(22, 30, 34, 36), 'amber', mode='flat', iline=True)
    return render(cv)


def shadow_board():
    """El tablero de sombras sobre el banco: herramientas colgadas sobre su silueta pintada; dos siluetas vacías
    (faltan una llave y un destornillador)."""
    cv = cv_new(64, 40)
    bd = cv.rect(1, 1, 62, 38)
    cv.put(bd, 'tealp', mode='flat', cast=1, iline=True)
    cv.put(cv.rect(1, 1, 62, 2), 'wood2', mode='flat', iline=True)
    tools = [((8, 8), (8, 30), 'steel', 1.2), ((16, 8), (16, 26), 'red', 1.4), ((30, 10), (30, 32), 'steel', 1.0),
             ((40, 8), (40, 28), 'wood3', 1.6), ((54, 8), (54, 30), 'steel', 1.3)]
    for k, (a, b, m, r) in enumerate(tools):
        sil = cv.stroke([a, b], r + 1.0)
        cv.paint(sil & bd, 'teal2', 1)
        if k in (1, 3):
            continue    # las que faltan: solo la silueta pintada
        cv.put(cv.stroke([a, b], r), m, mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(23, 14, 4, 4) & ~cv.ellipse(23, 14, 2, 2), 'brass', mode='shine', iline=True)
    cv.put(cv.ellipse(47, 30, 4, 3), 'cable_y', mode='shine', iline=True)
    return render(cv)


def wall_niche():
    """Un nicho de adobe en la pared (hasta que llega el Parts Wall): una radio vieja, una cabeza de robot cuadrada con
    dos ojos redondos y frascos de tornillos."""
    cv = cv_new(46, 40)
    n = cv.poly([(2, 39), (2, 12), (8, 4), (38, 4), (44, 12), (44, 39)])
    cv.put(n, 'adobe2', mode='flat', iline=True)
    inner = cv.poly([(6, 36), (6, 13), (10, 8), (36, 8), (40, 13), (40, 36)])
    cv.put(inner, 'shadow', mode='flat', iline=True)
    cv.put(cv.rect(4, 36, 42, 39), 'adobe', mode='top', iline=True)
    box(cv, 8, 24, 20, 35, 'tealp', depth=(2, -2))
    cv.put(cv.ellipse(12, 30, 2.2, 2.2), 'hole', mode='flat')
    box(cv, 23, 20, 35, 35, 'scrap', depth=(2, -2))
    for x in (26, 32):
        cv.put(cv.ellipse(x, 26, 2.2, 2.2), 'glass', mode='shine', iline=True)
    cv.put(cv.rect(27, 30, 31, 31), 'iron', mode='flat')
    for x in (10, 15):
        cv.put(cv.rect(x, 15, x + 3, 22), 'glass', mode='shine', cast=1, iline=True)
        cv.paint(cv.rect(x + 1, 18, x + 2, 21), 'steel', 2)
    return render(cv)


def pipe_run():
    """Un tramo de caño por la pared (se repite): caño de cobre con abrazaderas, un manómetro y una llave de paso."""
    cv = cv_new(128, 18)
    cv.put(cv.rect(0, 6, 127, 11), 'copper', mode='cyl', cast=1, iline=True)
    for x in (10, 52, 96):
        cv.put(cv.rect(x, 4, x + 3, 13), 'dkmetal', mode='shine', iline=True)
    cv.put(cv.ellipse(34, 8, 6, 6), 'brass', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(34, 8, 4.2, 4.2), 'paper', mode='flat')
    keep(cv, cv.put(cv.line([(34, 8), (36, 5)]), 'red', mode='flat', outline=False))
    wheel = cv.ellipse(76, 6, 5, 5) & ~cv.ellipse(76, 6, 3.4, 3.4)
    cv.put(wheel, 'red', mode='shine', cast=1, iline=True)
    cv.put(cv.rect(75, 2, 76, 10) | cv.rect(72, 5, 80, 6), 'red', mode='flat')
    return render(cv)


def chalkboard(n=0):
    """La pizarra "hoy" (4 cuadros: 0, 1-2, 3-5, 6+ rayitas de reparaciones del día), marco de madera, una tiza."""
    cv = cv_new(34, 26)
    cv.put(cv.rect(0, 0, 33, 25), 'wood2', mode='flat', cast=1, iline=True)
    b = cv.rect(2, 2, 31, 21)
    cv.put(b, 'chalk', mode='flat', iline=True)
    cv.put(cv.rect(8, 22, 14, 23), 'chalkw', mode='flat')
    # una estrellita arriba (sin letras) y las rayitas en grupos de cinco
    keep(cv, cv.put(cv.poly(sparkle_pts(6, 6, 3, 2, 1.2)), 'chalkw', mode='flat', outline=False))
    count = [0, 2, 5, 8][n]
    for k in range(count):
        g, i = divmod(k, 5)
        x = 11 + g * 9 + i * 2
        if i < 4:
            keep(cv, cv.put(cv.rect(x, 9 + g % 1, x, 16), 'chalkw', mode='flat', outline=False))
        else:
            keep(cv, cv.put(cv.line([(x - 9, 15), (x - 1, 9)]), 'chalkw', mode='flat', outline=False))
    return render(cv)


def radio_wall():
    """La radio de la tienda en un estante de pared (ahí sale el Drift Signal): radio de baquelita crema con dial
    ámbar, antena de alambre, un frasco y un trapo."""
    cv = cv_new(40, 30)
    box(cv, 0, 24, 37, 27, 'wood', top='plank', side='wood2', depth=(2, -2))
    for x in (4, 32):
        cv.put(cv.poly([(x, 27), (x + 2, 27), (x + 2, 29), (x, 29)]), 'iron', mode='flat', iline=True)
    pf, pt, ps = box(cv, 6, 8, 28, 23, 'cream', depth=(3, -3))
    cv.put(cv.ellipse(12, 16, 4, 4), 'wood2', mode='flat', iline=True)
    for y in (14, 16, 18):
        cv.paint(cv.rect(9, y, 15, y), 'wood3', 2)
    keep(cv, cv.put(cv.rect(18, 12, 26, 15), 'amber', mode='flat', iline=True))
    cv.dot(22, 13, 'red', 3)
    for x in (19, 24):
        cv.put(cv.ellipse(x, 19, 1.6, 1.6), 'dkmetal', mode='shine', iline=True)
    keep(cv, cv.put(cv.line([(24, 8), (34, 1)]), 'steel', mode='flat'))
    cv.put(cv.rect(31, 17, 35, 23), 'glass', mode='shine', iline=True)
    return render(cv)


def coat_rack():
    """Un perchero de caño con una chaqueta de vuelo y una gorra."""
    cv = cv_new(28, 64)
    cv.put(cv.rect(13, 6, 15, 60), 'dkmetal', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(14, 61, 9, 2.6), 'iron', mode='flat', iline=True)
    for (a, b) in (((14, 9), (6, 6)), ((14, 9), (22, 6))):
        cv.put(cv.stroke([a, b], 0.9), 'dkmetal', mode='shine', iline=True)
    jk = cv.poly([(4, 10), (14, 9), (16, 12), (17, 40), (3, 40)])
    cv.put(jk, 'jacket', mode='cyl', cast=1, iline=True)
    cv.put(cv.poly([(5, 10), (10, 10), (8, 18)]), 'cream', mode='flat', iline=True)
    cv.paint(cv.rect(3, 24, 17, 25) & jk, 'leather', 2)
    cv.put(cv.ellipse(21, 8, 5, 3), 'tealp', mode='dome', cast=1, iline=True)
    cv.put(cv.rect(16, 9, 26, 10), 'teal2', mode='flat', iline=True)
    return render(cv)


def bot_torso():
    """El torso de un bot de servicio viejo y cuadrado, medio abierto (sin cúpula, sin paneles famosos): caja de chapa
    gris con una tapa caída y cables."""
    cv = cv_new(34, 44)
    pf, pt, ps = box(cv, 4, 12, 26, 42, 'scrap', top='steel', side='hull2', depth=(4, -4))
    cv.put(cv.rect(8, 18, 22, 34), 'hole', mode='flat', iline=True)
    keep(cv, cv.put(cv.stroke(bez((10, 20), (14, 30), (18, 24), 6), 0.6), 'cable_r', mode='flat'))
    keep(cv, cv.put(cv.stroke(bez((12, 32), (18, 26), (20, 32), 6), 0.6), 'cable_y', mode='flat'))
    cv.put(cv.poly([(26, 18), (32, 22), (32, 40), (26, 36)]), 'scrap', mode='flat', cast=1, iline=True)
    box(cv, 9, 2, 21, 11, 'hull2', depth=(2, -2))
    for x in (12, 18):
        cv.put(cv.ellipse(x, 6, 1.8, 1.8), 'bulb_off', mode='shine', iline=True)
    return render(cv)


def trophy_shelf():
    """El estante de los trofeos (sobre la puerta): una tabla con dos ménsulas de hierro."""
    cv = cv_new(56, 14)
    box(cv, 1, 2, 53, 6, 'wood', top='plank', side='wood2', depth=(2, -2))
    for x in (6, 46):
        cv.put(cv.poly([(x, 6), (x + 4, 6), (x + 4, 13), (x, 8)]), 'iron', mode='flat', iline=True)
    return render(cv)


def beam(cool=False, frame=0):
    """El rayo de sol (o de luna) que entra por la ventana: degradé suave baked + motas de polvo (2 cuadros que se
    alternan). Alfa suave: se dibuja como la lluvia de chatarra (sin luz, con alfa)."""
    W_, H_ = 96, 160
    a = np.zeros((H_, W_, 4), np.uint8)
    yy, xx = np.mgrid[0:H_, 0:W_].astype(np.float32)
    t = yy / (H_ - 1)
    edge = np.minimum(xx, W_ - 1 - xx) / (W_ * 0.5)
    alpha = np.clip(edge * 1.5, 0, 1) ** 1.1 * np.clip(0.8 - 0.75 * t, 0, 1)
    col = (180, 196, 255) if cool else (255, 230, 170)
    a[..., 0], a[..., 1], a[..., 2] = col
    a[..., 3] = np.clip(alpha * 255 * (0.75 if cool else 0.9), 0, 255).astype(np.uint8)
    rng = np.random.RandomState(7 + frame)
    for k in range(70):
        x, y = rng.randint(8, W_ - 8), rng.randint(4, H_ - 10)
        a[y, x] = (255, 250, 230, 200) if not cool else (230, 236, 255, 170)
    return a


# ================================================================== las mejoras (§4.1)

def up_samovar():
    """Kettle's Samovar: una urna alta de cobre con canilla, asas y una chimenea, sobre una bandeja."""
    cv = cv_new(30, 48)
    cv.put(cv.rect(4, 44, 26, 46), 'brass', mode='shine', iline=True)
    cv.put(cv.poly([(9, 44), (21, 44), (19, 40), (11, 40)]), 'copper', mode='cyl', iline=True)
    body = cv.ellipse(15, 26, 10, 14) & (cv.ys <= 40) & (cv.ys >= 14)
    cv.put(body, 'copper', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(9, 10, 21, 14), 'brass', mode='shine', iline=True)
    cv.put(cv.rect(13, 3, 17, 10), 'copper', mode='cyl', iline=True)
    cv.put(cv.ellipse(15, 3, 4, 1.5), 'brass', mode='shine', iline=True)
    for sx in (-1, 1):
        cv.put(cv.stroke([(15 + sx * 9, 20), (15 + sx * 13, 22), (15 + sx * 10, 28)], 0.9), 'brass', mode='shine', iline=True)
    cv.put(cv.stroke([(19, 34), (25, 35)], 1.1), 'brass', mode='shine', iline=True)
    cv.put(cv.rect(24, 35, 25, 37), 'brass', mode='flat')
    cv.paint(cv.rect(6, 24, 24, 25) & body, 'brass', 2)
    return render(cv)


def up_seats():
    """Liner Seats: dos asientos de pasajero atornillados, cuero crema, apoyabrazos de cromo, uno roto."""
    cv = cv_new(62, 42)
    cv.put(cv.rect(4, 32, 58, 34), 'chrome2', mode='shine', iline=True)
    for x in (8, 54):
        cv.put(cv.rect(x, 34, x + 2, 41), 'dkmetal', mode='cyl', iline=True)
    for k, x0 in enumerate((4, 32)):
        back = rrect(cv, x0 + 2, 2, x0 + 24, 26, 4)
        p = cv.put(back, 'cream', mode='cyl', cast=1, iline=True)
        for y in (9, 16):
            cv.shade(cv.line([(x0 + 4, y), (x0 + 22, y)]), -1, within=[p])
        seat = rrect(cv, x0, 24, x0 + 26, 32, 3)
        cv.put(seat, 'cream', mode='top', cast=1, iline=True)
        cv.put(cv.rect(x0, 20, x0 + 1, 30), 'chrome', mode='shine', iline=True)
        if k == 1:
            cv.put(cv.poly([(x0 + 14, 6), (x0 + 20, 10), (x0 + 15, 14)]), 'wood2', mode='flat')
            keep(cv, cv.put(cv.line([(x0 + 15, 7), (x0 + 18, 12)]), 'canvas', mode='flat'))
    cv.put(cv.rect(58, 20, 59, 30), 'chrome', mode='shine', iline=True)
    return render(cv)


def up_podlamp():
    """Pod Lamp: una lámpara de escáner con lente de vidrio verde colgada de un gancho."""
    cv = cv_new(22, 42)
    cv.put(cv.stroke([(11, 0), (11, 6), (8, 9), (11, 12)], 0.7), 'iron', mode='shine', iline=True)
    keep(cv, cv.put(cv.rect(11, 12, 11, 18), 'cable_k', mode='flat'))
    body = cv.poly([(5, 18), (17, 18), (19, 30), (3, 30)])
    cv.put(body, 'dkmetal', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(6, 22, 16, 23), 'amber', mode='flat')
    lens = cv.ellipse(11, 32, 8, 5)
    keep(cv, cv.put(lens, 'bottle_g', mode='shine', iline=True))
    cv.dot(8, 31, 'white', 4)
    return render(cv)


def up_coolring():
    """Cool Coil: un anillo de enfriamiento de cobre colgado bajo el ventilador, con gotitas (cuelga del techo)."""
    cv = cv_new(52, 22)
    for x in (14, 38):
        cv.put(cv.rect(x, 0, x + 1, 8), 'iron', mode='flat', iline=True)
    ring = cv.ellipse(26, 11, 22, 5) & ~cv.ellipse(26, 11, 17, 3)
    cv.put(ring, 'copper', mode='stroke', nrm=cv.sphere_n(26, 10, 23, 6), cast=1, iline=True)
    for x in range(8, 46, 6):
        cv.paint(cv.rect(x, 10, x + 1, 13) & ring, 'brass', 2)
    for (x, y) in ((10, 17), (24, 19), (36, 18), (44, 15)):
        keep(cv, cv.put(cv.rect(x, y, x, y + 1), 'glass', mode='flat', outline=False))
    return render(cv)


def up_display():
    """Display Case: una vitrina de vidrio con marco de bronce sobre patas, iluminada desde arriba (el ítem va adentro,
    otro sprite)."""
    cv = cv_new(44, 46)
    for x in (4, 38):
        cv.put(cv.rect(x, 30, x + 2, 45), 'brass', mode='cyl', cast=1, iline=True)
    base = cv.rect(2, 26, 41, 31)
    cv.put(base, 'velvet', mode='top', cast=1, iline=True)
    fr = cv.rect(2, 4, 41, 27)
    cv.put(fr & ~cv.rect(4, 6, 39, 25), 'brass', mode='shine', cast=1, iline=True)
    g = cv.rect(4, 6, 39, 25)
    q = cv.put(g, 'glass2', mode='flat', iline=False)
    cv.shade(cv.line([(8, 24), (20, 7)]), 2, within=[q])
    cv.shade(cv.line([(11, 24), (23, 7)]), 1, within=[q])
    cv.put(cv.rect(1, 2, 42, 4), 'brass', mode='shine', iline=True)
    keep(cv, cv.put(cv.rect(18, 5, 25, 5), 'bulb', mode='flat', outline=False))
    return render(cv)


def up_partswall(fill=0):
    """Parts Wall: una pared de latitas con etiquetas escritas a mano (3 cuadros: más llenas cuantas más piezas)."""
    cv = cv_new(50, 38)
    cv.put(cv.rect(0, 0, 49, 37), 'wood2', mode='flat', cast=1, iline=True)
    rng = np.random.RandomState(4)
    for r in range(4):
        for c in range(6):
            x, y = 2 + c * 8, 2 + r * 9
            cv.put(cv.rect(x, y, x + 6, y + 7), 'tin', mode='cyl', iline=True)
            cv.paint(cv.rect(x + 1, y + 1, x + 5, y + 2), 'paper', 2)
            full = rng.rand() < [0.3, 0.6, 0.95][fill]
            if full:
                m = ['copper', 'steel', 'amber', 'teal', 'red', 'brass'][rng.randint(6)]
                cv.paint(cv.rect(x + 1, y + 4, x + 5, y + 6), m, 2)
            else:
                cv.paint(cv.rect(x + 1, y + 4, x + 5, y + 6), 'hole', 2)
    return render(cv)


def up_loupe():
    """Loupe Lamp: una lámpara articulada verde agua con una lupa grande en un brazo de resorte, prensada al banco."""
    cv = cv_new(32, 40)
    cv.put(cv.rect(2, 34, 10, 39), 'dkmetal', mode='shine', cast=1, iline=True)
    cv.put(cv.stroke([(6, 34), (10, 18), (22, 10)], 1.1), 'tealp', mode='shine', cast=1, iline=True)
    for (x, y) in ((10, 18),):
        cv.put(cv.ellipse(x, y, 1.8, 1.8), 'brass', mode='shine', iline=True)
    keep(cv, cv.put(cv.stroke(bez((8, 26), (12, 22), (9, 20), 6), 0.4), 'steel', mode='flat'))
    rim = cv.ellipse(23, 12, 8, 8) & ~cv.ellipse(23, 12, 6.2, 6.2)
    cv.put(rim, 'tealp', mode='shine', cast=1, iline=True)
    lens = cv.ellipse(23, 12, 6.2, 6.2)
    q = cv.put(lens, 'glass2', mode='flat')
    cv.shade(cv.line([(19, 14), (25, 8)]), 2, within=[q])
    return render(cv)


def up_neon(frame=0):
    """Neon Star: el cartel de tubos de neón en la ventana, "FIXED HERE" y una estrella, rosa y verde agua (2
    cuadros: parpadea). Las letras son palabras comunes (no un nombre propio)."""
    W_, H_ = 100, 30
    cv = cv_new(W_, H_)
    cv.put(rrect(cv, 0, 0, W_ - 1, H_ - 1, 4), 'iron', mode='flat', iline=True)
    a = text_mask(cv, 'FIXED', 6, 4, 2)
    b = text_mask(cv, 'HERE', 6, 17, 2)
    on = frame == 0
    keep(cv, cv.put(a, 'neonp', mode='flat', outline=False))
    keep(cv, cv.put(b, 'neont' if on else 'tealp', mode='flat', outline=False))
    st = []
    for k in range(10):
        ang = math.radians(-90 + k * 36)
        r = 10 if k % 2 == 0 else 4.4
        st.append((78 + math.cos(ang) * r, 15.5 + math.sin(ang) * r))
    outer = cv.poly(st)
    inner = cv.poly([(78 + (x - 78) * 0.6, 15.5 + (y - 15.5) * 0.6) for x, y in st])
    keep(cv, cv.put(outer & ~inner, 'neonp' if on else 'pink2', mode='flat', outline=False))
    return render(cv, outline=False)


# ================================================================== las cosas de las historias (§6.3)

def crate_sealed():
    """El cajón de Rook: sellado, con flejes y "DO NOT" estarcido (palabras comunes), y un sello de lacre."""
    cv = cv_new(36, 30)
    pf, pt, ps = box(cv, 2, 8, 30, 28, 'tarp', top='tarp2', side='tarp2', depth=(4, -4))
    for x in (6, 26):
        cv.paint(cv.rect(x, 8, x + 1, 28), 'dkmetal', 2)
    m = text_mask(cv, 'DO NOT', 8, 15, 1)
    cv.paint(m, 'cream', 2)
    cv.put(cv.ellipse(16, 24, 2.4, 2.0), 'red', mode='dome', iline=True)
    return render(cv)


def frame_certificate():
    """El certificado de la Tally Office en un marco (aprobado: un sello rojo con APPROVED y la marca de conteo)."""
    cv = cv_new(42, 36)
    cv.put(cv.rect(0, 0, 41, 35), 'wood', mode='flat', cast=1, iline=True)
    cv.put(cv.rect(3, 3, 38, 32), 'paper', mode='flat', iline=True)
    for y in (7, 10, 13):
        cv.paint(cv.rect(7, y, 34, y), 'wire', 1)
    for k in range(4):
        cv.paint(cv.rect(8 + k * 2, 16, 8 + k * 2, 21), 'navy', 2)
    cv.paint(cv.line([(7, 20), (16, 17)]), 'navy', 2)
    st = cv.rect(4, 23, 37, 30)
    cv.paint(st & ~cv.rect(5, 24, 36, 29), 'red', 2)
    cv.paint(text_mask(cv, 'APPROVED', 6, 24, 1), 'red', 2)
    return render(cv)


def trophy_cup():
    """La copa del Glasspan Derby (chiquita, dorada, con dos asas)."""
    cv = cv_new(16, 20)
    cup = cv.poly([(3, 2), (13, 2), (11, 10), (5, 10)])
    cv.put(cup, 'gold', mode='cyl', cast=1, iline=True)
    for sx in (-1, 1):
        cv.put(cv.ellipse(8 + sx * 6, 5, 2.2, 2.6) & ~cv.ellipse(8 + sx * 6, 5, 1.0, 1.4), 'gold', mode='shine', iline=True)
    cv.put(cv.rect(7, 10, 9, 14), 'gold', mode='cyl', iline=True)
    cv.put(cv.rect(4, 14, 12, 18), 'wood2', mode='top', iline=True)
    return render(cv)


def lucky_key():
    """La llave de la suerte de Rook: una llave de arranque de bronce con una borla roja (nunca dados)."""
    cv = cv_new(14, 22)
    cv.put(cv.ellipse(7, 5, 4, 4) & ~cv.ellipse(7, 5, 1.6, 1.6), 'brass', mode='shine', cast=1, iline=True)
    cv.put(cv.rect(6, 9, 8, 17), 'brass', mode='cyl', iline=True)
    cv.put(cv.rect(8, 13, 10, 14) | cv.rect(8, 16, 9, 17), 'brass', mode='flat')
    cv.put(cv.stroke([(4, 3), (2, 10), (3, 18)], 1.2, 0.8), 'red', mode='cyl', iline=True)
    cv.put(cv.ellipse(3, 19, 1.8, 2.2), 'red', mode='dome', iline=True)
    return render(cv)


def ribbon_bronze():
    """La escarapela de bronce de "local favourite" (la banda en la puerta): roseta bronce con dos cintas."""
    cv = cv_new(14, 22)
    for (a, b) in (((6, 10), (3, 20)), ((8, 10), (11, 20))):
        cv.put(cv.stroke([a, b], 1.6), 'ribbon', mode='cyl', iline=True)
    cv.put(cv.ellipse(7, 7, 6, 6), 'copperp', mode='dome', cast=1, iline=True)
    cv.put(cv.ellipse(7, 7, 3, 3), 'amber', mode='flat', iline=True)
    return render(cv)


def plaque_paid():
    """La placa de bronce "PAID IN FULL" junto a la puerta (las tres cuotas a tiempo)."""
    tw = text_w('PAID IN FULL')
    W_ = tw + 10
    cv = cv_new(W_, 16)
    cv.put(rrect(cv, 0, 0, W_ - 1, 15, 2), 'brass', mode='shine', cast=1, iline=True)
    cv.put(rrect(cv, 2, 2, W_ - 3, 13, 1), 'copper', mode='flat', iline=True)
    cv.paint(text_mask(cv, 'PAID IN FULL', 5, 5, 1), 'gold', 3)
    for (x, y) in ((2, 2), (W_ - 3, 2), (2, 13), (W_ - 3, 13)):
        cv.dot(x, y, 'steel', 3)
    return render(cv)


def lamp_core_prop(n=0):
    """Los núcleos de lámpara de Old Seven en el alféizar (4 cuadros: 0, 1, 2 o 3 bombitas que brillan)."""
    cv = cv_new(46, 18)
    cv.put(cv.rect(0, 14, 45, 17), 'adobe', mode='top', iline=True)
    for k in range(n):
        x = 9 + k * 14
        b = cv.ellipse(x, 8, 4.5, 5.5)
        keep(cv, cv.put(b, 'glass2', mode='shine', iline=True))
        keep(cv, cv.put(cv.stroke(bez((x - 2, 10), (x, 4), (x + 2, 10), 5), 0.5), 'glow', mode='flat', outline=False))
        cv.put(cv.rect(x - 2, 13, x + 2, 14), 'brass', mode='shine', iline=True)
    return render(cv)


def window_haze():
    """La bruma ocre del Scour sobre la ventana (tramado: solo opaco o transparente)."""
    W_, H_ = 96, 60
    a = np.zeros((H_, W_, 4), np.uint8)
    yy, xx = np.mgrid[0:H_, 0:W_]
    rng = np.random.RandomState(9)
    dens = 0.3 + 0.14 * np.sin(xx * 0.18 + yy * 0.05)
    m = rng.rand(H_, W_) < dens
    m &= ((xx + yy * 2) % 3 != 0)
    a[m] = (214, 160, 92, 255)
    m2 = m & (rng.rand(H_, W_) < 0.3)
    a[m2] = (236, 190, 120, 255)
    return a


def flyer_bike(tint='flagr'):
    """(P1) Una hoverbike del Glasspan Derby cruzando el cielo: un asiento, propulsor trasero gordo, nariz corta, el
    piloto agachado (nada de paletas largas adelante ni dos motores)."""
    cv = cv_new(56, 26)
    body = cv.poly([(10, 12), (40, 10), (52, 14), (40, 19), (10, 19)])
    cv.put(body, tint, mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(10, 15, 7, 6), 'dkmetal', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(4, 15, 2.4, 4), 'engine', mode='flat')
    cv.put(cv.rect(20, 19, 36, 20), 'iron', mode='flat', iline=True)
    cv.put(cv.ellipse(28, 8, 6, 4), 'leather', mode='dome', iline=True)
    cv.put(cv.ellipse(33, 4, 3.4, 3.2), 'cream', mode='dome', iline=True)
    cv.put(cv.rect(34, 3, 37, 4), 'glass', mode='flat')
    return render(cv)


# ================================================================== texturas (assets/tex)

def tex_enamel():
    """Paneles de esmalte blanco (Shine Again), 64x64 que se repite: blanco cálido, juntas grises de esquinas
    redondeadas, un brillo suave arriba a la izquierda de cada panel."""
    n = 64
    a = np.zeros((n, n, 4), np.uint8)
    a[...] = (240, 236, 228, 255)
    yy, xx = np.mgrid[0:n, 0:n]
    for (x0, y0) in ((0, 0), (32, 0), (0, 32), (32, 32)):
        lx, ly = xx - x0, yy - y0
        inside = (lx >= 0) & (lx < 32) & (ly >= 0) & (ly < 32)
        edge = inside & ((lx == 0) | (ly == 0) | (lx == 31) | (ly == 31))
        a[edge] = (196, 192, 188, 255)
        hi = inside & (lx >= 2) & (lx <= 6) & (ly >= 2) & (ly <= 3)
        a[hi] = (252, 250, 246, 255)
        sh = inside & ((lx == 30) | (ly == 30)) & ~edge
        a[sh] = (222, 218, 212, 255)
    return a


def tex_sand_blow():
    """La arena del Scour (256x256 que se repite, para la capa 2D): rayas de arena en diagonal, granos sueltos;
    transparente entre medio (el alfa lo pone la capa)."""
    n = 256
    a = np.zeros((n, n, 4), np.uint8)
    rng = np.random.RandomState(3)
    cols = [(232, 196, 140), (214, 172, 112), (246, 220, 170)]
    for k in range(90):
        x0, y0 = rng.randint(0, n), rng.randint(0, n)
        L = rng.randint(24, 90)
        c = cols[k % 3]
        th = rng.choice([1, 1, 2])
        for i in range(L):
            x = (x0 + i) % n
            y = (y0 + int(i * 0.18)) % n
            if rng.rand() < 0.82:
                a[y:y + th, x] = c + (255,)
    for k in range(900):
        x, y = rng.randint(0, n), rng.randint(0, n)
        a[y, x] = cols[k % 3] + (255,)
    return a


def sand_drift(frame=0):
    """Un montoncito de arena visto desde arriba (va acostado en el piso: la puerta de la tienda, la calle en el Scour);
    2 cuadros: chico, grande."""
    W_, H_ = 64, 40
    cv = cv_new(W_, H_)
    if frame == 0:
        m = cv.ellipse(30, 22, 22, 9) | cv.ellipse(44, 26, 12, 6)
    else:
        m = cv.ellipse(32, 20, 30, 15) | cv.ellipse(48, 26, 14, 9) | cv.ellipse(16, 26, 12, 8)
    p = cv.put(m, 'sand', mode='dome', iline=False)
    for k in range(5):
        y = 12 + k * 4
        cv.shade(cv.line([(8 + k * 2, y), (54 - k * 3, y + 2)]), -1, within=[p])
    return render(cv)


TEX = {'enamel': tex_enamel, 'sand_blow': tex_sand_blow}


# ================================================================== registro

# nombre -> (función que devuelve un array o una lista de cuadros, px, ancla, extra para props.json)
SPRITES = {
    'flyer_bike': (lambda: strip([flyer_bike('flagr'), flyer_bike('flagt')]), 0.05, 'center', {'frames': 2}),
    'fg_bike_frame': (fg_bike_frame, 0.03, 'top', {}),
    'fg_cable_coil': (fg_cable_coil, 0.03, 'bottom', {}),
    'fg_pod_shells': (fg_pod_shells, 0.03, 'bottom', {}),
    'fg_oil_drum': (fg_oil_drum, 0.03, 'bottom', {}),
    'fg_engine_block': (fg_engine_block, 0.03, 'bottom', {}),
    'shadow_board': (shadow_board, 0.03, 'center', {}),
    'wall_niche': (wall_niche, 0.03, 'center', {}),
    'pipe_run': (pipe_run, 0.03, 'center', {}),
    'chalkboard': (lambda: strip([chalkboard(i) for i in range(4)]), 0.03, 'center', {'frames': 4}),
    'radio_wall': (radio_wall, 0.026, 'center', {}),
    'coat_rack': (coat_rack, 0.03, 'bottom', {}),
    'bot_torso': (bot_torso, 0.03, 'bottom', {}),
    'trophy_shelf': (trophy_shelf, 0.03, 'center', {}),
    'sunbeam': (lambda: strip([beam(False, 0), beam(False, 1)]), 0.03, 'center', {'frames': 2}),
    'moonbeam': (lambda: beam(True, 0), 0.03, 'center', {}),
    'up_samovar': (up_samovar, 0.028, 'bottom', {}),
    'up_seats': (up_seats, 0.03, 'bottom', {}),
    'up_podlamp': (up_podlamp, 0.03, 'top', {}),
    'up_coolring': (up_coolring, 0.03, 'top', {}),
    'up_display': (up_display, 0.03, 'bottom', {}),
    'up_partswall': (lambda: strip([up_partswall(i) for i in range(3)]), 0.03, 'center', {'frames': 3}),
    'up_loupe': (up_loupe, 0.026, 'bottom', {}),
    'up_neon': (lambda: strip([up_neon(0), up_neon(1)]), 0.022, 'center', {'frames': 2}),
    'crate_sealed': (crate_sealed, 0.03, 'bottom', {}),
    'frame_certificate': (frame_certificate, 0.026, 'center', {}),
    'trophy_cup': (trophy_cup, 0.022, 'bottom', {}),
    'lucky_key': (lucky_key, 0.022, 'bottom', {}),
    'ribbon_bronze': (ribbon_bronze, 0.022, 'bottom', {}),
    'plaque_paid': (plaque_paid, 0.022, 'center', {}),
    'lamp_core_prop': (lambda: strip([lamp_core_prop(i) for i in range(4)]), 0.024, 'bottom', {'frames': 4}),
    'window_haze': (window_haze, 0.028, 'center', {}),
    'sand_drift': (lambda: strip([sand_drift(0), sand_drift(1)]), 0.03, 'center', {'frames': 2}),
    'shine_facade': (shine_facade, 0.035, 'bottom', {}),
    'shine_star': (shine_star, 0.035, 'center', {}),
    'shine_carpet': (shine_carpet, 0.035, 'center', {}),
    'chrome_plant': (chrome_plant, 0.03, 'bottom', {}),
    'boarded_poster': (boarded_poster, 0.035, 'bottom', {}),
    'vendor_crates': (vendor_crates, 0.03, 'bottom', {}),
    'notice_board': (notice_board, 0.03, 'center', {}),
    'poster_frame': (poster_frame, 0.022, 'center', {}),
    'departure_board': (departure_board, 0.03, 'bottom', {}),
    'lounge_sign': (lounge_sign, 0.045, 'center', {}),
    'glint_balloon': (lambda: strip([glint_balloon(0), glint_balloon(1)]), 0.045, 'bottom', {'frames': 2}),
    'tally_banner': (tally_banner, 0.035, 'top', {}),
    'smoke_column': (lambda: strip([smoke_column(i) for i in range(4)]), 0.09, 'bottom', {'frames': 4}),
    'wreck_glow': (wreck_glow, 0.1, 'bottom', {}),
    'bunting': (lambda: pennants('bunting'), 0.03, 'top', {}),
    'flag_race': (lambda: pennants('race'), 0.03, 'top', {}),
    'moon_banner': (moon_banner, 0.035, 'top', {}),
    'race_gate': (race_gate, 0.06, 'bottom', {}),
    'cloth_flap': (lambda: strip([cloth_flap(0), cloth_flap(1)]), 0.03, 'top', {'frames': 2}),
    'stall_tarp': (stall_tarp, 0.045, 'bottom', {}),
    'facade_awning': (facade_awning, 0.035, 'top', {}),
    'neon_street': (lambda: strip([neon_street(0), neon_street(1)]), 0.035, 'center', {'frames': 2}),
    'moon_copper': (moon_copper, 0.05, 'center', {'frames': 3}),
    'moon_tin': (moon_tin, 0.05, 'center', {'frames': 3}),
    'moon_halo': (moon_halo, 0.05, 'center', {}),
    'sky_ring': (sky_ring, 0.06, 'center', {}),
    'ring_lamp': (ring_lamp, 0.06, 'center', {'frames': 2}),
    'spark': (spark, 0.04, 'center', {}),
    'star_sign_comet': (star_sign_comet, 0.031, 'bottom', {'star_cx': 92}),
    'band_trio': (lambda: strip([band_trio(0), band_trio(1)]), 0.0222, 'bottom', {'frames': 2}),
    'band_trio_window': (lambda: strip([band_trio_window(0), band_trio_window(1)]), 0.02, 'bottom', {'frames': 2}),
    'lantern_string': (lantern_string, 0.03, 'top', {}),
}


def extra_info(name):
    if name == 'sky_ring':
        return {'lamps': ring_lamps_uv(), 'size': [RING_W, RING_H]}
    return {}


def build_tex(tex_dir, names=None):
    os.makedirs(tex_dir, exist_ok=True)
    n = 0
    for name, fn in TEX.items():
        if names and name not in names:
            continue
        Image.fromarray(fn(), 'RGBA').save(os.path.join(tex_dir, f'{name}.png'))
        n += 1
    return n


def build(out_dir, names=None):
    os.makedirs(out_dir, exist_ok=True)
    spec = {}
    for name, (fn, px, anchor, extra) in SPRITES.items():
        if names and name not in names:
            continue
        arr = fn()
        Image.fromarray(arr, 'RGBA').save(os.path.join(out_dir, f'{name}.png'))
        d = dict(px=px, anchor=anchor)
        d.update(extra)
        d.update(extra_info(name))
        spec[name] = d
    return spec


if __name__ == '__main__':
    args = sys.argv[1:]
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.normpath(os.path.join(here, '..', '..', 'assets', 'props'))
    if '--out' in args:
        k = args.index('--out')
        out = args[k + 1]
        del args[k:k + 2]
    spec = build(out, args or None)
    nt = build_tex(os.path.join(os.path.dirname(out), 'tex') if '--out' not in sys.argv else os.path.join(out, 'tex'), args or None)
    pj = os.path.join(out, 'props.json')
    old = json.load(open(pj)) if os.path.exists(pj) else {}
    old.update(spec)
    json.dump(old, open(pj, 'w'), indent=1, sort_keys=True)
    print('ok props2', len(spec), 'tex', nt, '->', out)
