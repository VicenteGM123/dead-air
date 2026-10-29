"""Núcleo del generador de personajes 64x96, estilo HD-2D (sprites tipo Octopath Traveler).

El lienzo guarda, por píxel, el id de la PARTE que lo pintó (las partes se pintan de atrás hacia adelante: el id
sirve de profundidad) y una NORMAL de superficie, calculada al poner la parte según su forma (cilindro vertical,
domo, esfera o trazo). Render en PLANOS (pasada 4, ver render()):
  1. luz desde arriba a la izquierda -> tono continuo por píxel, suavizado dentro de cada parte y cuantizado en 3
     planos grandes (sombra, medio, luz; brillo solo en metales y gemas); nada de ruido ni tramas (salvo pelaje y punto),
  2. el pelo trae su tono explícito (Part.lock / base7): base, separación oscura de 1 px y UNA banda de brillo por mechón,
  3. sombras proyectadas y líneas interiores del lado de la sombra,
  4. ajustes explícitos (pliegues) y niveles forzados (ojos, boca, brillos),
  5. limpieza: ningún píxel suelto (salvo los forzados y las partes 'keep'),
  6. contorno oscuro de color (marrón / violeta, nunca negro), del color de la parte en los bordes que miran a la luz.
Rampas de 7 tonos por material: sombras hacia violeta / azul, luces cálidas.
"""
import colorsys, math
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

W, H = 64, 96

# luz: desde arriba a la izquierda y un poco de frente (x a la derecha, y hacia abajo, z hacia la cámara)
LIGHT = np.array([-0.62, -0.62, 0.48])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# d = n·L -> nivel continuo (puntos de una curva lineal a tramos): los umbrales de cada tono caen en k + 0.5
_LV_D = np.array([-1.0, -0.45, -0.20, 0.30, 0.70, 0.92, 1.0])
_LV_L = np.array([-1.2, -0.6, 0.5, 1.6, 2.85, 3.8, 4.2])

BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) + 0.5) / 16.0


# ------------------------------------------------------------------ colores

def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _cl(v):
    return max(0.0, min(1.0, v))


def tone(rgb, hue_to, hue_amt, vmul=1.0, vadd=0.0, sadd=0.0):
    r, g, b = [c / 255 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    hd = h * 360
    if s < 0.07:
        # casi gris: el matiz no existe, se elige el destino con poca saturación
        hd = hue_to
        s = s + max(0.0, sadd) * 0.6
    else:
        diff = ((hue_to - hd + 540) % 360) - 180
        step = max(-hue_amt, min(hue_amt, diff))
        hd = (hd + step) % 360
        s = _cl(s + sadd)
    v = _cl(v * vmul + vadd)
    r, g, b = colorsys.hsv_to_rgb(hd / 360, s, v)
    return (round(r * 255), round(g * 255), round(b * 255))


def mute(base, smul=0.78, vmul=0.95):
    """Apaga un color (menos saturación, un poco más oscuro): la base terrosa del estilo."""
    b = hexrgb(base) if isinstance(base, str) else tuple(base)
    r, g, bb = [c / 255 for c in b]
    h, s, v = colorsys.rgb_to_hsv(r, g, bb)
    r, g, bb = colorsys.hsv_to_rgb(h, _cl(s * smul), _cl(v * vmul))
    return (round(r * 255), round(g * 255), round(bb * 255))


def ramp5(base, kind='cloth'):
    """Rampa corta de 5 tonos (compatibilidad: el render la expande a 7)."""
    r = ramp7(base, kind)
    return [r[0], r[2], r[3], r[5], r[6]]


def _lum(c):
    return 0.30 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def _mix(a, b, t):
    return tuple(max(0, min(255, round(x + (y - x) * t))) for x, y in zip(a, b))


def _shadow_tint(b):
    """Tinte de las sombras según el matiz: azul / violeta en general; en amarillos y naranjas, violeta pardo
    (un amarillo con sombra azul se vuelve verde oliva, y eso no es lo que hace la referencia)."""
    r, g, bb = [x / 255 for x in b]
    h, s, v = colorsys.rgb_to_hsv(r, g, bb)
    hd = h * 360
    if s > 0.12 and 25 <= hd <= 80:
        return (1.06, 0.84, 0.92)
    return (0.90, 0.90, 1.12)


def dark(b, vmul, cool=0.35, tint=None, sadd=0.0):
    """Tono de sombra: más oscuro y mezclado hacia un gris frío (azul / violeta) de la misma luminancia."""
    if tint is None:
        tint = _shadow_tint(b)
    c = tuple(x * vmul for x in b)
    L = _lum(c)
    g = tuple(L * t for t in tint)
    c = _mix(c, g, cool)
    if sadd:
        r, gg, bb = [x / 255 for x in c]
        h, s, v = colorsys.rgb_to_hsv(r, gg, bb)
        r, gg, bb = colorsys.hsv_to_rgb(h, _cl(s + sadd), v)
        c = (round(r * 255), round(gg * 255), round(bb * 255))
    return c


def light(b, vadd, warm=0.25, tint=(1.08, 1.0, 0.82), sdesat=0.0):
    """Tono de luz: más claro y un poco hacia un tono cálido (amarillo / crema)."""
    r, g, bb = [x / 255 for x in b]
    h, s, v = colorsys.rgb_to_hsv(r, g, bb)
    r, g, bb = colorsys.hsv_to_rgb(h, _cl(s - sdesat), _cl(v + vadd))
    c = (r * 255, g * 255, bb * 255)
    L = _lum(c)
    w = tuple(min(255.0, L * t) for t in tint)
    return _mix(c, w, warm)


def ramp7(base, kind='cloth'):
    """7 tonos: 0 casi contorno, 1 sombra profunda, 2 sombra, 3 base, 4 luz, 5 brillo, 6 brillo alto.
    Sombras hacia gris frío (violeta / azul), luces cálidas; la piel con sombras rojizas."""
    b = hexrgb(base) if isinstance(base, str) else tuple(base)
    if kind == 'flat':
        return [b] * 7
    if kind == 'skin':
        warm = (1.20, 0.86, 0.74)
        return [dark(b, 0.46, 0.30, warm, +0.16), dark(b, 0.64, 0.26, warm, +0.12), dark(b, 0.82, 0.18, warm, +0.07), b,
                light(b, 0.05, 0.10), light(b, 0.09, 0.18, sdesat=0.04), light(b, 0.13, 0.26, sdesat=0.08)]
    if kind == 'metal':
        return [dark(b, 0.34, 0.45), dark(b, 0.54, 0.40), dark(b, 0.76, 0.30), b,
                light(b, 0.12, 0.20), light(b, 0.24, 0.35, sdesat=0.10), light(b, 0.40, 0.55, sdesat=0.30)]
    if kind == 'hair':
        return [dark(b, 0.26, 0.40), dark(b, 0.42, 0.34), dark(b, 0.64, 0.22), b,
                light(b, 0.09, 0.15), light(b, 0.18, 0.28, sdesat=0.06), light(b, 0.28, 0.38, sdesat=0.12)]
    if kind == 'silver':
        # pelo plateado: blanco grisáceo con sombras lavanda / gris azulado
        lav = (0.94, 0.92, 1.14)
        return [dark(b, 0.40, 0.70, lav), dark(b, 0.54, 0.70, lav), dark(b, 0.72, 0.60, lav), dark(b, 0.86, 0.30, lav),
                b, light(b, 0.05, 0.20), light(b, 0.09, 0.35)]
    if kind == 'white':
        # tela blanca / crema: sombras gris azuladas frías, luces crema cálidas (nunca blanco puro)
        cool = (0.86, 0.92, 1.12)
        return [dark(b, 0.42, 0.75, cool), dark(b, 0.56, 0.72, cool), dark(b, 0.74, 0.60, cool), b,
                light(b, 0.05, 0.30), light(b, 0.09, 0.40), light(b, 0.13, 0.50)]
    if kind == 'gem':
        return [dark(b, 0.36, 0.20), dark(b, 0.52, 0.16), dark(b, 0.74, 0.10), b,
                light(b, 0.14, 0.15), light(b, 0.26, 0.30, sdesat=0.15), light(b, 0.40, 0.60, sdesat=0.40)]
    if kind == 'leather':
        wl = (1.02, 0.88, 1.0)
        return [dark(b, 0.30, 0.30, wl), dark(b, 0.46, 0.26, wl), dark(b, 0.68, 0.18), b,
                light(b, 0.09, 0.15), light(b, 0.17, 0.25, sdesat=0.06), light(b, 0.25, 0.35, sdesat=0.10)]
    # tela
    return [dark(b, 0.30, 0.38), dark(b, 0.46, 0.32), dark(b, 0.67, 0.22), b,
            light(b, 0.08, 0.14), light(b, 0.15, 0.24, sdesat=0.05), light(b, 0.23, 0.32, sdesat=0.10)]


def expand7(r):
    """Rampa de 5 tonos -> 7 (intercala los intermedios); una de 7 queda igual."""
    r = [tuple(c) for c in r]
    if len(r) >= 7:
        return r[:7]
    mid = lambda a, b: tuple(round((x + y) / 2) for x, y in zip(a, b))
    return [r[0], mid(r[0], r[1]), r[1], r[2], mid(r[2], r[3]), r[3], r[4]]


NT = 7
# niveles 'viejos' (0..4, los que usan ojos, puntos y detalles) -> tono de 7
F_MAP = np.array([0, 2, 3, 5, 6], np.int16)

# textura por tipo de material (en tonos de 7): ruido en grumos, motas sueltas, bordes gastados
#             amp. grumos, motas oscuras, motas claras, borde gastado
KIND_GRIT = {'cloth': (0.95, 0.07, 0.035, 0.30), 'wool': (1.20, 0.10, 0.05, 0.35), 'leather': (1.10, 0.09, 0.05, 0.45),
             'white': (0.45, 0.03, 0.015, 0.25), 'hair': (0.12, 0.01, 0.01, 0.0), 'silver': (0.10, 0.0, 0.0, 0.0),
             'metal': (0.50, 0.03, 0.04, 0.0), 'skin': (0.0, 0.0, 0.0, 0.0), 'gem': (0.0, 0.0, 0.0, 0.0),
             'flat': (0.0, 0.0, 0.0, 0.0)}
# forma de los grumos: (sigma y, sigma x); telas: trazos cortos verticales; pelo: vetas largas
KIND_NOISE_SIGMA = {'cloth': (1.0, 0.55), 'wool': (0.8, 0.8), 'leather': (0.7, 0.7), 'white': (1.1, 0.5),
                    'hair': (2.4, 0.8), 'silver': (2.4, 0.8), 'metal': (0.6, 1.2)}
# tramado ordenado (Bayer, suave) en las transiciones de tono
KIND_DITHER = {'cloth': 0.25, 'leather': 0.20, 'white': 0.30, 'wool': 0.35, 'skin': 0.0, 'hair': 0.0, 'silver': 0.0,
               'metal': 0.0, 'gem': 0.0, 'flat': 0.0}
# desplazamiento de nivel por tipo, en niveles viejos (los blancos y la piel se leen claros; el pelo, medio)
KIND_BIAS = {'skin': 0.65, 'hair': 0.10, 'silver': 0.45, 'white': 0.40, 'metal': 0.40}
KIND_TEX = {'cloth': None, 'leather': 'leather', 'wool': 'noise', 'white': None}

OUTLINE_DARK = (34, 22, 34)
# corrimiento global hacia lo oscuro (en tonos de 7): valores medios más bajos, como la referencia
GLOBAL_SHIFT = -0.35


def outline_of(r, lit=False):
    """Contorno: en el lado de la sombra (abajo / derecha) casi negro con color (violeta / marrón);
    en el lado de la luz (arriba / izquierda) un oscuro del propio material: la luz 'rompe' el contorno."""
    r = expand7(r)
    if lit:
        return r[1]
    c = tone(r[0], 300, 40, 0.42, 0, +0.12)
    rr, g, b = [x / 255 for x in c]
    h2, s2, v2 = colorsys.rgb_to_hsv(rr, g, b)
    v2 = min(v2, 0.22)
    rr, g, b = colorsys.hsv_to_rgb(h2, min(s2, 0.55), v2)
    return (max(round(rr * 255), 20), max(round(g * 255), 13), max(round(b * 255), 20))


SELECTIVE_OUTLINE = True


# ------------------------------------------------------------------ normales

def _norm(nx, ny, zmin=0.10):
    m = np.sqrt(nx * nx + ny * ny)
    k = np.where(m > 0.98, 0.98 / np.maximum(m, 1e-6), 1.0)
    nx, ny = nx * k, ny * k
    nz = np.sqrt(np.maximum(zmin * zmin, 1.0 - nx * nx - ny * ny))
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l, ny / l, nz / l], axis=-1).astype(np.float32)


def _runs_u(mask):
    """Posición en -1..1 a lo largo de cada tramo horizontal de la máscara."""
    h, w = mask.shape
    u = np.zeros((h, w), np.float32)
    for y in range(h):
        row = mask[y]
        if not row.any():
            continue
        xs = np.flatnonzero(row)
        br = np.flatnonzero(np.diff(xs) > 1)
        starts = np.r_[xs[0], xs[br + 1]]
        ends = np.r_[xs[br], xs[-1]]
        for a, b in zip(starts, ends):
            n = b - a + 1
            c = a + (n - 1) / 2.0
            half = max(n / 2.0, 0.75)
            u[y, a:b + 1] = (np.arange(a, b + 1) - c) / half
    return u


def _vdist(mask):
    """Distancia (en píxeles de la máscara) al borde de arriba y al de abajo, por columna."""
    h, w = mask.shape
    up = np.zeros((h, w), np.float32)
    dn = np.zeros((h, w), np.float32)
    run = np.zeros(w, np.float32)
    for y in range(h):
        run = np.where(mask[y], run + 1, 0)
        up[y] = run - 1
    run = np.zeros(w, np.float32)
    for y in range(h - 1, -1, -1):
        run = np.where(mask[y], run + 1, 0)
        dn[y] = run - 1
    return up, dn


def n_cyl(mask, curv=0.92, vround=2.2, vamt=0.65):
    """Cilindro de eje vertical (torsos, faldas, mangas): luz a la izquierda, sombra a la derecha,
    borde de arriba más claro y de abajo más oscuro."""
    u = _runs_u(mask) * curv
    up, dn = _vdist(mask)
    ny = -np.clip(1.0 - up / vround, 0, 1) * vamt + np.clip(1.0 - dn / vround, 0, 1) * vamt * 0.85
    return _norm(u, ny)


def n_dome(mask, R=3.0, k=1.0):
    """Domo: la normal se inclina hacia fuera cerca del borde (radio R); el interior mira a la cámara."""
    if not mask.any():
        return np.zeros(mask.shape + (3,), np.float32)
    pad = np.pad(mask, 2)
    d = ndi.distance_transform_edt(pad)[2:-2, 2:-2]
    ds = ndi.gaussian_filter(d, 0.8)
    gy, gx = np.gradient(ds)
    g = np.sqrt(gx * gx + gy * gy) + 1e-6
    s = np.clip(1.0 - (d - 0.5) / R, 0.0, 1.0) * k
    return _norm(-gx / g * s, -gy / g * s)


def mix_n(a, b, t):
    v = a * (1 - t) + b * t
    l = np.linalg.norm(v, axis=-1, keepdims=True) + 1e-6
    return (v / l).astype(np.float32)


# ------------------------------------------------------------------ lienzo

class Part:
    __slots__ = ('mat', 'mode', 'cast', 'iline', 'outline', 'band', 'sep', 'mask', 'bias', 'dither', 'tex', 'contrast', 'keep',
                 'lock', 'hairy')

    def __init__(self, mat, mode='cyl', cast=0, iline=False, outline=True, band=0.30, sep=True):
        self.mat, self.mode, self.cast, self.iline, self.outline, self.band = mat, mode, cast, iline, outline, band
        self.sep = sep      # False: sobre una parte del mismo material se ve continua (sin sombra de borde)
        self.mask = None
        self.bias = 0.0     # desplazamiento de nivel (p. ej. miembros lejanos más oscuros)
        self.dither = None  # None = el del material
        self.tex = None
        self.contrast = 1.0
        self.keep = False   # True: sus píxeles sueltos son a propósito (la limpieza no los toca)
        self.lock = None    # datos de mechón (pelo): el tono se decide en el render según lo que quede visible
        self.hairy = False  # parte de pelo (mechón o masa): las separaciones entre mechones solo miran a estas


class Cv:
    def __init__(self, pal, w=W, h=H, kinds=None, tex=None):
        self.pal = pal                    # nombre de material -> rampa de 5 colores
        self.kinds = kinds or {}          # nombre de material -> tipo de rampa (tramado / textura)
        self.tex = tex or {}              # nombre de material -> textura forzada
        self.w, self.h = w, h
        self.pid = np.zeros((h, w), np.int32)
        self.mov = np.full((h, w), '', dtype=object)   # material forzado por píxel ('' = el de la parte)
        self.force = np.full((h, w), -1, np.int8)       # nivel forzado (-1 = automático)
        self.adj = np.zeros((h, w), np.int8)            # ajuste de nivel (+ luz / - sombra), pasos viejos (x2 tonos)
        self.adj7 = np.zeros((h, w), np.int8)           # ajuste fino, en tonos de 7
        self.base7 = np.full((h, w), -1, np.int8)        # tono base explícito (pelo por mechones); -1 = por la luz
        self.nrm = np.zeros((h, w, 3), np.float32)
        self.nrm[..., 2] = 1.0
        self.parts = [None]
        self.ys, self.xs = np.mgrid[0:h, 0:w]
        self.vgrad = None                                # (y0, y1, niveles): oscurece hacia los pies

    # -- normales por modo
    def _normals(self, mask, mode, nrm=None):
        if nrm is not None:
            return nrm
        if mode in ('cyl', 'rim', 'shine'):
            return n_cyl(mask)
        if mode == 'soft':
            return n_dome(mask, R=3.5, k=0.85)
        if mode == 'top':
            return mix_n(n_dome(mask, R=3.0), n_cyl(mask), 0.35)
        if mode == 'dome':
            return n_dome(mask, R=4.0)
        out = np.zeros(mask.shape + (3,), np.float32)
        out[..., 2] = 1.0
        return out

    # -- partes
    def put(self, mask, mat, mode='cyl', cast=0, iline=False, outline=True, band=0.30, sep=True, nrm=None, bias=0.0,
            dither=None, contrast=1.0):
        part = Part(mat, mode, cast, iline, outline, band, sep)
        part.bias, part.dither, part.contrast = bias, dither, contrast
        self.parts.append(part)
        p = len(self.parts) - 1
        if mask is None or not mask.any():
            part.mask = np.zeros((self.h, self.w), bool) if mask is None else mask.copy()
            return p
        part.mask = mask.copy()
        n = self._normals(mask, mode, nrm)
        self.pid[mask] = p
        self.mov[mask] = ''
        self.force[mask] = -1
        self.adj[mask] = 0
        self.adj7[mask] = 0
        self.base7[mask] = -1
        self.nrm[mask] = n[mask]
        return p

    def grow(self, p, mask):
        """Agrega píxeles a una parte existente (sin cambiar su profundidad); recalcula sus normales."""
        part = self.parts[p]
        full = (part.mask if part.mask is not None else np.zeros_like(mask)) | mask
        part.mask = full
        n = self._normals(full, part.mode)
        mine = (self.pid == p) | mask
        self.pid[mask] = p
        self.mov[mask] = ''
        self.force[mask] = -1
        self.adj[mask] = 0
        self.adj7[mask] = 0
        self.base7[mask] = -1
        self.nrm[mine] = n[mine]

    def set_nrm(self, p, nrm):
        """Normales explícitas para los píxeles visibles de la parte p."""
        m = self.pid == p
        self.nrm[m] = nrm[m]

    def erase(self, mask):
        self.pid[mask] = 0
        self.mov[mask] = ''
        self.force[mask] = -1
        self.adj[mask] = 0
        self.adj7[mask] = 0
        self.base7[mask] = -1

    def of(self, *pids):
        m = np.zeros((self.h, self.w), bool)
        for p in pids:
            m |= self.pid == p
        return m

    def shade(self, mask, d, within=None):
        """Oscurece (d<0) o aclara (d>0) píxeles ya pintados; within = ids de partes permitidas."""
        m = mask & (self.pid > 0)
        if within is not None:
            m &= self.of(*within)
        self.adj[m] = np.clip(self.adj[m].astype(int) + d, -4, 4)

    def shade7(self, mask, d, within=None):
        """Como shade() pero en tonos de 7 (un paso fino)."""
        m = mask & (self.pid > 0)
        if within is not None:
            m &= self.of(*within)
        self.adj7[m] = np.clip(self.adj7[m].astype(int) + d, -6, 6)

    def paint(self, mask, mat, lvl, within=None):
        """Pinta un detalle con otro material sobre píxeles ya pintados. El nivel es RELATIVO a la luz
        (2 = el tono que le toca por la luz, 3 = uno más claro, 1 = uno más oscuro)."""
        m = mask & (self.pid > 0)
        if within is not None:
            m &= self.of(*within)
        self.mov[m] = mat
        self.force[m] = -1
        self.adj[m] = int(lvl) - 2

    def dot(self, x, y, mat, lvl, p=None):
        """Un píxel de detalle con nivel FIJO; si p se da y el píxel está vacío, lo agrega a la parte p."""
        x, y = int(round(x)), int(round(y))
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        if self.pid[y, x] == 0:
            if p is None:
                return
            self.pid[y, x] = p
        self.mov[y, x] = mat
        self.force[y, x] = lvl

    # -- máscaras
    def ellipse(self, cx, cy, rx, ry):
        return ((self.xs - cx) / max(rx, 0.01)) ** 2 + ((self.ys - cy) / max(ry, 0.01)) ** 2 <= 1.0

    def sphere_n(self, cx, cy, rx, ry, k=1.0, zmin=0.10):
        """Normales de un elipsoide (cabezas, gorros, bultos)."""
        nx = np.clip((self.xs - cx) / max(rx, 0.01), -1.2, 1.2) * k
        ny = np.clip((self.ys - cy) / max(ry, 0.01), -1.2, 1.2) * k
        return _norm(nx, ny, zmin)

    def rect(self, x0, y0, x1, y1):
        return (self.xs >= x0) & (self.xs <= x1) & (self.ys >= y0) & (self.ys <= y1)

    def poly(self, pts):
        im = Image.new('L', (self.w, self.h), 0)
        ImageDraw.Draw(im).polygon([(float(x), float(y)) for x, y in pts], fill=1, outline=1)
        return np.array(im, dtype=bool)

    def _capsule_d(self, a, b, ra, rb=None):
        if rb is None:
            rb = ra
        ax, ay = a
        bx, by = b
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        if L2 < 1e-6:
            t = np.zeros(self.xs.shape)
        else:
            t = np.clip(((self.xs - ax) * dx + (self.ys - ay) * dy) / L2, 0, 1)
        px = ax + t * dx
        py = ay + t * dy
        vx, vy = self.xs - px, self.ys - py
        d = np.sqrt(vx * vx + vy * vy)
        r = ra + (rb - ra) * t
        return d, r, vx, vy

    def capsule(self, a, b, ra, rb=None):
        d, r, _, _ = self._capsule_d(a, b, ra, rb)
        return d <= r

    def capsule_n(self, a, b, ra, rb=None, k=0.95):
        """Cápsula y sus normales de tubo (perpendiculares al eje)."""
        d, r, vx, vy = self._capsule_d(a, b, ra, rb)
        m = d <= r
        s = np.clip(d / np.maximum(r, 0.5), 0, 1) * k
        dd = np.maximum(d, 1e-6)
        return m, _norm(vx / dd * s, vy / dd * s)

    def stroke(self, pts, r0, r1=None):
        """Trazo por una polilínea con radio que va de r0 a r1."""
        if r1 is None:
            r1 = r0
        m = np.zeros((self.h, self.w), bool)
        n = len(pts) - 1
        for i in range(n):
            ra = r0 + (r1 - r0) * i / n
            rb = r0 + (r1 - r0) * (i + 1) / n
            m |= self.capsule(pts[i], pts[i + 1], ra, rb)
        return m

    def stroke_n(self, pts, radii, k=0.95):
        """Trazo con normales de tubo. radii: lista de radios por punto (o un número)."""
        if not isinstance(radii, (list, tuple, np.ndarray)):
            radii = [radii] * len(pts)
        best = np.full((self.h, self.w), 1e9)
        nv = np.zeros((self.h, self.w, 3), np.float32)
        m = np.zeros((self.h, self.w), bool)
        for i in range(len(pts) - 1):
            d, r, vx, vy = self._capsule_d(pts[i], pts[i + 1], radii[i], radii[i + 1])
            rel = d / np.maximum(r, 0.35)
            inside = rel <= 1.0
            upd = inside & (rel < best)
            if upd.any():
                s = np.clip(rel, 0, 1) * k
                dd = np.maximum(d, 1e-6)
                nn = _norm(vx / dd * s, vy / dd * s)
                nv[upd] = nn[upd]
                best[upd] = rel[upd]
            m |= inside
        return m, nv

    def line(self, pts):
        """Línea de 1 píxel por una polilínea (Bresenham)."""
        m = np.zeros((self.h, self.w), bool)
        for i in range(len(pts) - 1):
            x0, y0 = [int(round(v)) for v in pts[i]]
            x1, y1 = [int(round(v)) for v in pts[i + 1]]
            dx, dy = abs(x1 - x0), -abs(y1 - y0)
            sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
            err = dx + dy
            while True:
                if 0 <= x0 < self.w and 0 <= y0 < self.h:
                    m[y0, x0] = True
                if x0 == x1 and y0 == y1:
                    break
                e2 = 2 * err
                if e2 >= dy:
                    err += dy
                    x0 += sx
                if e2 <= dx:
                    err += dx
                    y0 += sy
        return m

    def stamp(self, art, ox, oy, codes, parts):
        """ASCII -> píxeles. codes: char -> (clave de parte, material o None, nivel o None).
        parts: clave -> id de parte. Un material/nivel no None se fuerza en ese píxel."""
        rows = [r for r in art.strip('\n').split('\n')]
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in '. ' or ch not in codes:
                    continue
                gx, gy = ox + x, oy + y
                if not (0 <= gx < self.w and 0 <= gy < self.h):
                    continue
                key, mat, lvl = codes[ch]
                self.pid[gy, gx] = parts[key]
                self.mov[gy, gx] = mat if mat else ''
                self.force[gy, gx] = -1 if lvl is None else lvl
                self.adj[gy, gx] = 0
                self.adj7[gy, gx] = 0
                self.base7[gy, gx] = -1


def bez(p0, p1, p2, n=8):
    """Curva de Bézier cuadrática como lista de puntos."""
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 2
        b = 2 * (1 - t) * t
        c = t * t
        out.append((a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]))
    return out


def bez3(p0, p1, p2, p3, n=10):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        d = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def _hash(x, y, s=0):
    v = (x * 374761393 + y * 668265263 + s * 2147483647) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return (v ^ (v >> 16)) / 4294967295.0


_HX = None


def _hash_grid(h, w, s=0):
    ys, xs = np.mgrid[0:h, 0:w]
    v = (xs.astype(np.uint64) * 374761393 + ys.astype(np.uint64) * 668265263 + np.uint64(s * 2654435761 & 0xFFFFFFFF)) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFFFFFF).astype(np.float64) / 4294967295.0


# ------------------------------------------------------------------ render

_NOISE = {}


def _noise_tex(seed, sigma):
    """Ruido en grumos (gaussiano suavizado, normalizado a ~[-1, 1]) de 192x192, cacheado.
    sigma puede ser (sy, sx): grumos alargados (telas que cuelgan: trazos verticales; pelo: vetas)."""
    k = (seed, sigma)
    if k not in _NOISE:
        n = _hash_grid(192, 192, seed)
        if (sigma if not isinstance(sigma, tuple) else max(sigma)) > 0:
            n = ndi.gaussian_filter(n, sigma, mode='wrap')
        n = (n - n.mean()) / (n.std() + 1e-6)
        _NOISE[k] = np.clip(n / 1.6, -1.0, 1.0).astype(np.float32)
    return _NOISE[k]


def _part_coords(cv, p):
    """Coordenadas de textura de una parte: relativas a su caja (la textura se mueve con la parte) más un
    desplazamiento por material (dos partes iguales no comparten el mismo dibujo)."""
    m = cv.parts[p].mask
    if m is None or not m.any():
        return 0, 0
    ys, xs = np.nonzero(m)
    hsh = sum(ord(c) * (i + 7) for i, c in enumerate(cv.parts[p].mat)) * 31 + p * 17
    return int(ys.min()) - (hsh % 97), int(xs.min()) - ((hsh // 97) % 89)


def _smooth_in(val, m, sigma):
    """Promedio gaussiano de val restringido a la máscara m (convolución normalizada)."""
    w = ndi.gaussian_filter(m.astype(np.float32), sigma, mode='constant')
    v = ndi.gaussian_filter(np.where(m, val, 0.0).astype(np.float32), sigma, mode='constant')
    return np.where(m, v / np.maximum(w, 1e-4), val)


# luz -> tono continuo (escala de 7). Pocos planos grandes: sombra (2), medio (3), luz (4); el brillo (5) solo en
# metales / gemas ('shine') o donde la luz pega casi de lleno. De frente a la cámara = 3.
_PL_D = np.array([-1.0, -0.30, 0.15, 0.48, 0.62, 0.86, 1.0])
_PL_T = np.array([1.3, 1.85, 2.5, 3.1, 3.5, 4.35, 4.6])
# desplazamiento de tono por tipo de material (la piel y los blancos se leen claros)
KIND_TBIAS = {'skin': 0.25, 'white': 0.25, 'silver': 0.2, 'metal': 0.15, 'hair': 0.0, 'gem': 0.2}
PLANE_SHIFT = -0.30
SMOOTH_SIGMA = 0.75
DESPECKLE = True


def _shade_locks(cv):
    """Tono de los mechones de pelo según lo que quedó VISIBLE de cada uno (los de delante tapan a los de atrás):
    tono base; 1 px oscuro en su borde de abajo / a la derecha donde toca otro pelo; UNA banda de brillo (2-4 px de
    largo, 1-2 de grueso) del lado de la luz, en el tramo visible del mechón."""
    pid = cv.pid
    h, w = pid.shape
    hairy = np.array([False] + [bool(p.hairy) for p in cv.parts[1:]], bool)
    hp_ = hairy[pid]

    def nbp(dx, dy):
        out = np.zeros_like(pid)
        ys0, ys1 = max(0, -dy), min(h, h - dy)
        xs0, xs1 = max(0, -dx), min(w, w - dx)
        out[ys0:ys1, xs0:xs1] = pid[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
        return out

    right, down, diag = nbp(1, 0), nbp(0, 1), nbp(1, 1)
    for p in range(1, len(cv.parts)):
        part = cv.parts[p]
        if part.lock is None:
            continue
        L = part.lock
        vis = pid == p
        if not vis.any():
            continue
        # el pelo plateado / blanco se lee claro: todo un tono más arriba
        off = 1 if cv.kinds.get(part.mat) in ('silver', 'white') else 0
        tone = np.full((h, w), L['base'] + off, np.int16)
        # más oscuro hacia abajo: cada fila de 'fade' que se pasa resta un tono (el pelo de los lados y de la espalda)
        for fy in L.get('fade', ()):
            tone[cv.ys > fy] -= 1
        tone = np.maximum(tone, 1)
        if L.get('sep', True) and L['r'] >= 0.9:
            sep = vis & ((((right != p) & hairy[right] & (right > 0))) | ((down != p) & hairy[down] & (down > 0)) |
                         ((diag != p) & hairy[diag] & (diag > 0) & (L['lit'] < -0.2)))
            tone[sep] = np.maximum(1, tone[sep] - L.get('sep_d', 2))
        else:
            sep = np.zeros((h, w), bool)
        if L.get('dark') is not None:
            dk = vis & L['dark']
            tone[dk] = np.maximum(1, tone[dk] - 1)
            sep = sep | dk
        ring = getattr(cv, 'hair_ring', None)
        if L.get('ring') and ring is not None:
            # el anillo de brillo de la cabeza cruza también este mechón (flequillo): su tramo es su brillo
            rcx, rcy, rrx, rry, r_in, r_out = ring
            rr_ = np.sqrt(((cv.xs - rcx) / rrx) ** 2 + ((cv.ys - rcy) / rry) ** 2)
            an = np.degrees(np.arctan2(cv.ys - rcy, cv.xs - rcx))
            an = np.where(an < 0, an + 360, an)
            band = vis & ~sep & (rr_ >= r_in) & (rr_ <= r_out) & (an >= 200) & (an <= 330)
            core = band & (rr_ >= r_in + 0.06) & (rr_ <= r_out - 0.08) & (an >= 215) & (an <= 300)
            # nunca pegado a una separación: el brillo queda dentro del mechón
            sep_n = np.zeros_like(sep)
            for dx, dy in ((1, 0), (-1, 0)):
                sep_n |= np.roll(sep, dx, axis=1)
            band &= ~sep_n
            core &= ~sep_n
            tone[band] = np.maximum(tone[band], L['base'] + off + 1)
            tone[core] = np.minimum(6, L['base'] + off + 2)
        elif L.get('shine', True) and L['r'] >= 0.9:
            tv = L['t'][vis]
            t0, t1 = float(tv.min()), float(tv.max())
            ta = t0 + (t1 - t0) * L.get('shine_at', 0.25)
            tb = ta + L.get('shine_len', 3.0) / max(L['len'], 1.0)
            sm = vis & ~sep & (L['lit'] > L.get('lit_thr', 0.15)) & (L['rel'] >= 0.2) & (L['t'] >= ta) & (L['t'] <= tb)
            # si el tramo quedó vacío (mechón muy tapado), el brillo va en lo visible más cercano a la luz
            if not sm.any():
                cand = vis & ~sep & (L['lit'] > 0.0)
                if cand.sum() >= 2:
                    sm = cand & (L['t'] >= np.quantile(L['t'][cand], 0.2)) & (L['t'] <= np.quantile(L['t'][cand], 0.5))
            tone[sm] = np.minimum(6, tone[sm] + L.get('bright', 2))
        cv.base7[vis] = tone[vis].astype(np.int8)


def render(cv, outline=True):
    """Render en planos (pasada 4): por parte, la luz da un tono continuo que se suaviza dentro de la parte y se
    cuantiza en 3 planos grandes; los pelos y lo que tenga 'base7' traen su tono explícito. Después: sombras
    proyectadas, líneas interiores (del lado de la sombra), ajustes y niveles forzados, limpieza de píxeles sueltos
    (ningún píxel aislado salvo los forzados: ojos, brillos) y el contorno selectivo."""
    h, w = cv.h, cv.w
    pid = cv.pid
    parts = cv.parts
    filled = pid > 0
    n_parts = len(parts)
    cast_tbl = np.array([0] + [p.cast for p in parts[1:]], np.int16)
    iline_tbl = np.array([False] + [p.iline for p in parts[1:]], bool)
    sep_tbl = np.array([True] + [p.sep for p in parts[1:]], bool)
    bias_tbl = np.array([0.0] + [p.bias for p in parts[1:]], np.float32)
    con_tbl = np.array([1.0] + [p.contrast for p in parts[1:]], np.float32)
    flat_tbl = np.array([True] + [p.mode == 'flat' for p in parts[1:]], bool)
    shine_tbl = np.array([False] + [p.mode == 'shine' for p in parts[1:]], bool)
    oline_tbl = np.array([False] + [p.outline for p in parts[1:]], bool)
    keep_tbl = np.array([False] + [getattr(p, 'keep', False) for p in parts[1:]], bool)
    mids = {}
    mat_tbl = np.array([-1] + [mids.setdefault(p.mat, len(mids)) for p in parts[1:]], np.int32)
    pal7 = {k: expand7(v) for k, v in cv.pal.items()}

    matname = np.empty((h, w), dtype=object)
    for p in range(1, n_parts):
        matname[pid == p] = parts[p].mat
    ov = cv.mov != ''
    matname[ov] = cv.mov[ov]
    matname[~filled] = ''
    kindmap = np.empty((h, w), dtype=object)
    kindmap[:] = ''
    for name in set(matname[filled].tolist()):
        kindmap[matname == name] = cv.kinds.get(name, 'cloth')

    _shade_locks(cv)
    # 1. luz -> tono continuo
    d = (cv.nrm * LIGHT).sum(axis=-1)
    t = np.interp(d, _PL_D, _PL_T).astype(np.float32)
    con = con_tbl[pid]
    t = 3.0 + (t - 3.0) * con
    sh = shine_tbl[pid]
    t[sh] = 3.0 + (t[sh] - 3.0) * 1.25 + np.where(d[sh] > 0.80, 0.9, 0.0)
    t += bias_tbl[pid] * 1.5
    if cv.vgrad is not None:
        y0, y1, amt = cv.vgrad
        t -= np.clip((cv.ys - y0) / max(1.0, y1 - y0), 0.0, 1.0).astype(np.float32) * amt * 1.5
    for kind, kb in KIND_TBIAS.items():
        t[(kindmap == kind) & ~flat_tbl[pid]] += kb
    t += PLANE_SHIFT
    # suavizado dentro de cada parte: planos grandes, sin dientes de 1 px
    base = cv.base7 >= 0
    for p in range(1, n_parts):
        if flat_tbl[p] or shine_tbl[p]:
            continue
        m = (pid == p) & ~base
        if m.sum() > 6:
            t = _smooth_in(t, m, SMOOTH_SIGMA)
    flat = flat_tbl[pid]
    lvl = np.floor(t + 0.5).astype(np.int16)
    lvl = np.clip(lvl, 1, 5)
    lvl[flat] = 3
    lvl[base] = cv.base7[base]

    # texturas solo en materiales ásperos (pelaje, punto), en grumos de 2 px
    texm = np.empty((h, w), dtype=object)
    texm[:] = None
    for name in set(matname[filled].tolist()):
        tx = cv.tex.get(name, KIND_TEX.get(cv.kinds.get(name, 'cloth')))
        if tx:
            texm[matname == name] = tx
    for tx in ('fur', 'knit'):
        m = texm == tx
        if not m.any():
            continue
        if tx == 'fur':
            hv = _hash_grid(h, w, 11)
            seed = m & (hv < 0.07) & (lvl >= 2)
            seed2 = np.roll(seed, 1, axis=0) & m
            lvl[seed | seed2] -= 1
        else:
            lvl[m & ((cv.xs + 2 * cv.ys) % 6 == 0) & (lvl >= 2)] -= 1

    def nb(a, dx, dy, fill=0):
        out = np.full_like(a, fill)
        ys0, ys1 = max(0, -dy), min(h, h - dy)
        xs0, xs1 = max(0, -dx), min(w, w - dx)
        out[ys0:ys1, xs0:xs1] = a[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
        return out

    # 2. sombras proyectadas (luz arriba-izquierda): una parte de delante oscurece lo que tiene detrás abajo / a la derecha
    shadow = np.zeros((h, w), bool)
    contact = np.zeros((h, w), bool)
    for dx, dy, need in ((-1, 0, 1), (0, -1, 1), (-1, -1, 1), (0, -2, 2), (-1, -2, 2), (-2, 0, 2), (0, -3, 3), (-1, -3, 3)):
        q = nb(pid, dx, dy)
        hit = filled & (q > pid) & (cast_tbl[q] >= need) & (sep_tbl[q] | (mat_tbl[q] != mat_tbl[pid]))
        shadow |= hit
        if abs(dx) + abs(dy) == 1:
            contact |= hit & (mat_tbl[q] != mat_tbl[pid])
    lvl[shadow] -= 1
    lvl[contact] -= 1

    # 3. líneas interiores: el borde de una parte que está delante de otra. Del lado de la sombra (derecha / abajo)
    #    una línea oscura; del lado de la luz solo si las dos partes son del mismo material (línea suave).
    il_dark = np.zeros((h, w), bool)
    il_soft = np.zeros((h, w), bool)
    for dx, dy, dark_side in ((1, 0, True), (0, 1, True), (-1, 0, False), (0, -1, False)):
        q = nb(pid, dx, dy)
        behind = filled & iline_tbl[pid] & (q > 0) & (q < pid) & (sep_tbl[pid] | (mat_tbl[q] != mat_tbl[pid]))
        if dark_side:
            il_dark |= behind
        else:
            il_soft |= behind & (mat_tbl[q] == mat_tbl[pid])
    lvl[il_soft & ~il_dark] = np.minimum(lvl[il_soft & ~il_dark], 2)
    lvl[il_dark] = np.where(lvl[il_dark] >= 4, 1, 0)

    # 4. ajustes y niveles forzados
    adj = cv.adj.astype(np.int16)
    lvl = lvl + adj
    lvl = lvl + cv.adj7.astype(np.int16)
    f = cv.force >= 0
    lvl[f] = F_MAP[np.clip(cv.force[f], 0, 4)]
    lvl = np.clip(lvl, 0, NT - 1)

    # 5. limpieza: ningún píxel suelto (sin vecino del mismo color en sus 8 vecinos) salvo los forzados y las partes
    #    marcadas 'keep'; toma el tono más común entre sus vecinos del mismo material.
    if DESPECKLE:
        matid = np.full((h, w), -1, np.int32)
        names = sorted(set(matname[filled].tolist()))
        for i, name in enumerate(names):
            matid[matname == name] = i
        for _ in range(2):
            col = np.where(filled, matid * 8 + lvl, -1)
            same = np.zeros((h, w), np.int16)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    same += (nb(col, dx, dy, -1) == col)
            lone = filled & (same == 0) & ~f & ~keep_tbl[pid]
            if not lone.any():
                break
            ys_, xs_ = np.nonzero(lone)
            new = lvl.copy()
            for y, x in zip(ys_, xs_):
                cnt = {}
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        if dx == 0 and dy == 0:
                            continue
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < h and 0 <= xx < w and matid[yy, xx] == matid[y, x]:
                            k = int(lvl[yy, xx])
                            cnt[k] = cnt.get(k, 0) + (2 if dx == 0 or dy == 0 else 1)
                if cnt:
                    new[y, x] = max(cnt.items(), key=lambda kv: (kv[1], -abs(kv[0] - int(lvl[y, x]))))[0]
                elif ov[y, x]:
                    # un píxel suelto de otro material pintado encima (raya, ribete): vuelve al material de su parte
                    base_m = parts[pid[y, x]].mat
                    matname[y, x] = base_m
                    ov[y, x] = False
                    if base_m in names:
                        matid[y, x] = names.index(base_m)
            lvl = new

    img = np.zeros((h, w, 4), np.uint8)
    for name in set(matname[filled].tolist()):
        m = matname == name
        ramp = np.array(pal7[name], np.uint8)
        img[m, :3] = ramp[lvl[m]]
        img[m, 3] = 255

    # 6. contorno exterior selectivo: oscuro casi negro abajo / a la derecha; del lado de la luz, un oscuro del
    #    color de la parte (y donde la parte está muy iluminada, un tono medio: la luz rompe la línea)
    if outline:
        out = img.copy()
        pl = pid
        for y in range(h):
            for x in range(w):
                if pl[y, x] != 0:
                    continue
                best = None
                for dx, dy, lit in ((-1, 0, False), (0, -1, False), (1, 0, True), (0, 1, True)):
                    nx_, ny_ = x + dx, y + dy
                    if 0 <= nx_ < w and 0 <= ny_ < h:
                        q = pl[ny_, nx_]
                        if q != 0 and oline_tbl[q]:
                            best = (nx_, ny_, q, lit)
                            if not lit:
                                break
                if best is None:
                    continue
                nx_, ny_, q, lit = best
                m = matname[ny_, nx_]
                r7 = pal7[m]
                if lit and SELECTIVE_OUTLINE:
                    k = lvl[ny_, nx_]
                    c = r7[0] if k <= 3 else (r7[1] if k <= 4 else r7[2])
                    if _lum(c) > _lum(r7[3]) * 0.82:
                        c = r7[1]
                else:
                    c = outline_of(r7)
                out[y, x, :3] = c
                out[y, x, 3] = 255
        # el contorno también sin píxeles sueltos: un píxel de contorno de un color que no repite ningún vecino
        # toma el color de contorno más común a su alrededor
        if DESPECKLE:
            oc = (pid == 0) & (out[..., 3] > 0)
            col = (out[..., 0].astype(np.int64) << 16) | (out[..., 1].astype(np.int64) << 8) | out[..., 2]
            col = np.where(out[..., 3] > 0, col, -1)
            fix = []
            for y, x in zip(*np.nonzero(oc)):
                cnt = {}
                alone = True
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        if dx == 0 and dy == 0:
                            continue
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < h and 0 <= xx < w:
                            if col[yy, xx] == col[y, x]:
                                alone = False
                            if oc[yy, xx]:
                                cnt[col[yy, xx]] = cnt.get(col[yy, xx], 0) + 1
                if alone and cnt:
                    fix.append((y, x, max(cnt.items(), key=lambda kv: kv[1])[0]))
            for y, x, c in fix:
                out[y, x, 0], out[y, x, 1], out[y, x, 2] = (c >> 16) & 255, (c >> 8) & 255, c & 255
        img = out
    return img


def to_img(arr):
    return Image.fromarray(arr, 'RGBA')


def sheet(frames, scale=4, cols=8, bg=(52, 46, 70), pad=6, labels=None, path=None, label_h=0):
    """Hoja de contacto simple (sin texto). frames: arrays RGBA."""
    ims = [to_img(f) if not isinstance(f, Image.Image) else f for f in frames]
    cw = max(i.width for i in ims) * scale + pad * 2
    ch = max(i.height for i in ims) * scale + pad * 2 + label_h
    rows = math.ceil(len(ims) / cols)
    out = Image.new('RGBA', (cw * min(cols, len(ims)), ch * rows), bg + (255,))
    for n, im in enumerate(ims):
        cx, cy = (n % cols) * cw, (n // cols) * ch
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        out.alpha_composite(big, (cx + pad + (cw - pad * 2 - big.width) // 2, cy + pad))
    if path:
        out.save(path)
    return out
