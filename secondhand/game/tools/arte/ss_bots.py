"""Secondhand Stars · robots y bestia de carga dibujados a mano sobre el lienzo del kit (mismo render HD-2D:
planos de luz, contorno selectivo, sin píxeles sueltos).

  kettle   el ayudante de Nell: una pava de cobre a la altura de la rodilla (pico = nariz, tapa que salta, un ojo
           de lente grande y redondo, dos patitas)
  clatter  robot de servicio viejo, alto y flaco, cabeza de pantalla de lámpara (la cara es la bombita), rodilla que
           rechina (vendada con cinta) y una aceitera en la mano
  tortoise la tortuga de las dunas que carga la chatarra de los Rakers (props/tortoise.png, 128x96)

Se registran en REG (kettle, clatter) y PROPS (tortoise); ss_chars.py los usa.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import math
import numpy as np
from c64core import *
from c64body import GROUND
import chars64
from chars64 import WHITE

REG = {}      # id -> función que devuelve (idle[2], walk[4]); ss_chars.py los agrega a su BOTS
PROPS = {}    # nombre -> función que devuelve un arreglo RGBA


def pal_of(mats, ms=0.74, mv=0.92, accents=()):
    """Rampas de 7 tonos por material, apagadas como las del elenco (ver chars64.make_pal)."""
    pal, kinds = {}, {}
    for k, v in mats.items():
        base, kind = v if isinstance(v, tuple) else (v, 'cloth')
        b = hexrgb(base) if isinstance(base, str) else tuple(base)
        if kind == 'white':
            b = chars64._cream(b)
        sm, vm = chars64.MUTE.get(kind, (1.0, 1.0))
        if kind in ('cloth', 'wool'):
            sm, vm = ms, mv
        if k in accents:
            sm, vm = min(1.0, sm + 0.30), min(1.0, vm + 0.08)
        b = mute(b, sm, vm)
        pal[k] = ramp7(b, 'cloth' if kind == 'wool' else kind)
        kinds[k] = kind
    pal['white'] = WHITE
    kinds['white'] = 'flat'
    return pal, kinds


def keep(cv, p):
    cv.parts[p].keep = True
    return p


# ================================================================== Kettle

KETTLE_MATS = {
    'copper': ('#d87c40', 'metal'), 'copper2': ('#a65430', 'metal'), 'patina': ('#5aa898', 'cloth'),
    'bake': ('#3a2e2c', 'leather'), 'brass': ('#d4a64a', 'metal'), 'lens': ('#24323c', 'gem'), 'iris': ('#78dcd8', 'gem'),
    'iron': ('#5c5660', 'metal'), 'rubber': ('#33302e', 'leather'), 'hole': ('#1e1a1c', 'flat'),
    'steam': ('#f8f4ec', 'flat'), 'puffgrey': ('#a8a4a0', 'flat'),
}


def draw_kettle(kind='idle', i=0, react=None):
    """Kettle mirando a la derecha. Cuerpo ~20 px de ancho, total ~25 px de alto (pies en la fila 91).
    react: None, 'whistle' (la tapa salta y sale un chorro de vapor blanco del pico: diagnóstico correcto) o 'hmm'
    (bocanada gris chiquita sobre la tapa y el ojo entornado: diagnóstico equivocado); i = 0 / 1 (dos cuadros)."""
    pal, kinds = pal_of(KETTLE_MATS, accents=('iris', 'copper'))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    # pose: rebote del cuerpo, pasos y la tapa
    if kind == 'idle':
        bob = [0, 1][i]
        lid = [0, -1][i]          # al bajar el cuerpo la tapa queda un poquito levantada (respira vapor)
        legs = ((0, 0), (0, 0))
        tilt = 0.0
    else:
        bob = [0, -1, 0, -1][i]
        lid = [0, 1, 0, 1][i]
        # (dx, lift) de la pata cercana y la lejana
        legs = [((2, 0), (-2, 1)), ((0, 0), (0, 2)), ((-2, 1), (2, 0)), ((0, 2), (0, 0))][i]
        tilt = [0.5, 0.0, -0.5, 0.0][i]
    if react == 'whistle':
        bob, lid, tilt = [0, -1][i], [-3, -5][i], 0.0
    elif react == 'hmm':
        bob, lid, tilt = [0, 0][i], 0, -0.5
    cx = 31.0 + tilt
    yb = G - 5 + bob                 # fila de abajo del cuerpo
    # patas (la lejana detrás y más oscura)
    for side, (dx, lift), x0, bias in (('f', legs[1], cx + 3.5, -0.6), ('n', legs[0], cx - 3.0, 0.0)):
        fx = x0 + dx
        top = yb - 1
        foot_y = G - 1 - lift - (0 if side == 'n' else 1)
        m, n = cv.capsule_n((fx, top), (fx, foot_y - 1.0), 1.5, 1.4)
        cv.put(m, 'iron', mode='stroke', nrm=n, iline=side == 'n', bias=bias)
        fm = cv.ellipse(fx + 0.8, foot_y, 2.9, 1.3)
        cv.put(fm, 'rubber', mode='cyl', iline=side == 'n', bias=bias)
    # asa de atrás (C de baquelita)
    hp_ = bez3((cx - 7.5, yb - 12.0), (cx - 13.5, yb - 13.0), (cx - 14.0, yb - 6.5), (cx - 9.5, yb - 5.0), 14)
    m, n = cv.stroke_n(hp_, 1.7)
    cv.put(m, 'bake', mode='stroke', nrm=n, iline=True, cast=1)
    # pico (nariz): sale de abajo a la derecha y sube
    sp_ = bez((cx + 7.5, yb - 4.5), (cx + 13.0, yb - 6.0), (cx + 15.5, yb - 12.5), 12)
    m, n = cv.stroke_n(sp_, list(np.linspace(2.6, 1.3, len(sp_))))
    cv.put(m, 'copper', mode='stroke', nrm=n, iline=True, cast=1)
    tip = sp_[-1]
    cv.put(cv.ellipse(tip[0] + 0.2, tip[1] - 0.2, 1.5, 1.0), 'copper2', mode='shine', iline=True)
    cv.dot(tip[0] + 0.4, tip[1] - 0.6, 'hole', 0)
    # cuerpo: pava panzona (más ancha abajo), base con un aro más oscuro
    body = cv.ellipse(cx, yb - 6.5, 10.6, 7.2) | cv.ellipse(cx - 0.3, yb - 11.5, 8.0, 4.0)
    body &= cv.ys <= yb
    p = cv.put(body, 'copper', mode='shine', cast=1, iline=True)
    cv.set_nrm(p, cv.sphere_n(cx - 1.5, yb - 8.5, 11.5, 9.0, k=0.92))
    base = body & (cv.ys >= yb - 1)
    cv.paint(base, 'copper2', 2)
    # costura y remaches a media altura
    for x in range(int(cx - 9), int(cx + 10), 3):
        cv.dot(x, yb - 3, 'copper2', 1)
    # pátina verdiazul (manchas grandes, no motas)
    for (x, y, rx, ry) in ((cx - 7.0, yb - 3.0, 1.8, 1.1),):
        cv.paint(cv.ellipse(x, y, rx, ry) & body, 'patina', 2)
    # tapa: domito con aro, y el botón negro
    ly = yb - 15.0 + lid
    rim = cv.ellipse(cx - 0.6, ly + 2.0, 7.4, 1.6)
    cv.put(rim, 'brass', mode='shine', iline=True, cast=1)
    lm = cv.ellipse(cx - 0.6, ly + 1.4, 6.0, 3.0) & (cv.ys <= ly + 1.4)
    q = cv.put(lm, 'copper', mode='shine', cast=2, iline=True)
    cv.set_nrm(q, cv.sphere_n(cx - 1.6, ly + 0.5, 6.5, 3.5))
    cv.put(cv.rect(int(cx - 1.4), int(ly - 2.6), int(cx + 0.4), int(ly - 1.6)), 'bake', mode='cyl', iline=True)
    km = cv.ellipse(cx - 0.5, ly - 3.2, 2.2, 1.6)
    cv.put(km, 'bake', mode='shine', iline=True, cast=1)
    # el ojo: lente grande y redonda (aro de bronce, vidrio oscuro, iris verdiazul que brilla, reflejo)
    ex, ey = cx + 3.4, yb - 8.0
    cv.put(cv.ellipse(ex, ey, 4.4, 4.3), 'brass', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(ex + 0.2, ey + 0.1, 3.2, 3.1), 'lens', mode='shine')
    ir = cv.ellipse(ex + 0.7, ey + 0.3, 1.7, 1.7)
    cv.put(ir, 'iris', mode='shine')
    cv.dot(ex - 1.2, ey - 1.3, 'white', 4)
    cv.dot(ex - 0.2, ey - 1.6, 'white', 3)
    cv.dot(ex + 1.6, ey + 1.6, 'iris', 4)
    if react == 'hmm':
        # ojo entornado: el párpado de bronce baja sobre la mitad de arriba de la lente
        cv.put(cv.ellipse(ex + 0.2, ey - 1.0, 3.6, 2.2) & cv.ellipse(ex, ey, 4.4, 4.3) & (cv.ys <= ey - 0.5), 'brass', mode='shine')
        for (x, y, r) in (((cx - 1.0, yb - 21.0, 1.8), (cx + 1.5, yb - 23.5 - i, 2.2)) if True else ()):
            q = cv.put(cv.ellipse(x, y, r, r * 0.9), 'puffgrey', mode='flat', outline=False)
            cv.parts[q].keep = True
    if react == 'whistle':
        # chorro de vapor blanco desde el pico, hacia arriba a la derecha; notita de silbido
        tip = sp_[-1]
        puffs = [(tip[0] + 2.0, tip[1] - 3.0, 1.6), (tip[0] + 4.0, tip[1] - 6.5, 2.2), (tip[0] + 6.5, tip[1] - 10.5 - i, 2.8)]
        if i == 1:
            puffs.append((tip[0] + 9.5, tip[1] - 15.5, 3.2))
        for (x, y, r) in puffs:
            q = cv.put(cv.ellipse(x, y, r, r * 0.9), 'steam', mode='flat', outline=False)
            cv.parts[q].keep = True
    return render(cv)


def kettle_frames():
    return [draw_kettle('idle', i) for i in range(2)], [draw_kettle('walk', i) for i in range(4)]


REG['kettle'] = kettle_frames
# reacciones de Kettle para el banco (tira de 4 cuadros de 64x96: silbido x2, "hmm" x2) -> chars/kettle_react.png
PROPS_CHARS = {'kettle_react': lambda: np.concatenate([draw_kettle('idle', 0, 'whistle'), draw_kettle('idle', 1, 'whistle'),
                                                        draw_kettle('idle', 0, 'hmm'), draw_kettle('idle', 1, 'hmm')], axis=1)}


# ================================================================== Clatter

CLATTER_MATS = {
    'shade': ('#e4d8ac', 'white'), 'glowring': ('#f4b84a', 'flat'), 'filament': ('#e07a2a', 'flat'), 'shade2': ('#b8a878', 'cloth'), 'fringe': ('#d08a38', 'cloth'), 'under': ('#5a4636', 'cloth'),
    'brass': ('#d4a64a', 'metal'), 'bulb': ('#fff0b8', 'flat'), 'eyed': ('#3a2a2a', 'flat'),
    'enamel': ('#8fb6a4', 'metal'), 'enamel2': ('#6e9484', 'metal'), 'rust': ('#a45a36', 'cloth'),
    'iron': ('#77717a', 'metal'), 'joint': ('#45404a', 'metal'), 'tape': ('#ece0c4', 'white'),
    'dial': ('#efe6cc', 'white'), 'needle': ('#c0402e', 'flat'), 'can': ('#c84a36', 'metal'), 'oil': ('#3a3230', 'flat'),
}


def _limb(cv, a, b, r0, r1, mat, near, bias=0.0):
    m, n = cv.capsule_n(a, b, r0, r1)
    return cv.put(m, mat, mode='stroke', nrm=n, iline=near, cast=1 if near else 0, bias=bias)


def _ball(cv, c, r, mat='joint', near=True, bias=0.0):
    m = cv.ellipse(c[0], c[1], r, r)
    p = cv.put(m, mat, mode='shine', iline=near, cast=1 if near else 0, bias=bias)
    cv.set_nrm(p, cv.sphere_n(c[0] - 0.4, c[1] - 0.4, r + 0.8, r + 0.8))
    return p


def _knee_pt(hip, ank, l1, l2, fwd=1.0):
    dx, dy = ank[0] - hip[0], ank[1] - hip[1]
    d = math.hypot(dx, dy)
    mx, my = (hip[0] + ank[0]) / 2, (hip[1] + ank[1]) / 2
    if d >= l1 + l2 - 0.05:
        return (mx, my)
    h = math.sqrt(max(0.0, l1 * l1 - (d / 2) ** 2))
    nx, ny = -dy / d, dx / d
    if nx * fwd < 0:
        nx, ny = -nx, -ny
    return (mx + nx * h, my + ny * h)


def draw_clatter(kind='idle', i=0):
    """Clatter mirando a la derecha: viejo, alto y flaco, un poco encorvado hacia delante."""
    pal, kinds = pal_of(CLATTER_MATS, accents=('fringe', 'can'))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    if kind == 'idle':
        bob = [0, 1][i]
        lag = [0, 1][i]
        # pies: (x del tobillo, levantado) cercano y lejano
        feet = ((-2.5, 0), (3.0, 0))
        swing = 0.0
    else:
        bob = [0, -1, 0, -1][i]
        lag = [0, 1, 0, 1][i]
        # la rodilla cercana chirría: paso más corto con esa pierna
        feet = [((3.0, 0), (-4.5, 2)), ((-0.5, 0), (1.5, 3)), ((-3.5, 2), (4.5, 0)), ((1.0, 2), (-0.5, 0))][i]
        swing = [-1.0, 0.0, 1.0, 0.0][i]
    cx = 31.0
    hip_y = 64.0 + bob
    # --- piernas (la lejana primero, más oscura)
    for side, (ax, lift), hx, bias in (('f', feet[1], cx + 2.0, -0.6), ('n', feet[0], cx - 2.0, 0.0)):
        near = side == 'n'
        hip = (hx, hip_y + 1.0)
        ank = (cx + ax, G - 3.0 - lift - (0 if near else 1))
        knee = _knee_pt(hip, ank, 11.9, 11.7, fwd=1.0)
        _limb(cv, hip, knee, 1.5, 1.3, 'iron', near, bias)
        _limb(cv, knee, ank, 1.7, 1.5, 'enamel', near, bias)
        _ball(cv, knee, 2.0, 'joint', near, bias)
        if near:
            # la rodilla que rechina: cinta alrededor y una mancha de óxido
            tp = cv.rect(int(knee[0] - 2), int(knee[1] + 1), int(knee[0] + 2), int(knee[1] + 2))
            cv.put(tp, 'tape', mode='cyl', iline=True)
            cv.dot(knee[0] + 1, knee[1] - 1, 'rust', 2)
        foot = cv.ellipse(ank[0] + 0.8, ank[1] + 2.0, 3.8, 1.4)
        cv.put(foot, 'joint', mode='cyl', iline=near, bias=bias)
    # --- brazo lejano (detrás del cuerpo), cuelga y se balancea
    sh_f = (cx + 5.0, 44.5 + bob)
    el_f = (sh_f[0] + 1.5 - swing * 1.5, sh_f[1] + 9.0)
    hd_f = (el_f[0] + 1.0 - swing * 2.0, el_f[1] + 8.5)
    _limb(cv, sh_f, el_f, 1.2, 1.1, 'iron', False, -0.6)
    _limb(cv, el_f, hd_f, 1.1, 1.0, 'iron', False, -0.6)
    _ball(cv, el_f, 1.5, 'joint', False, -0.6)
    cv.put(cv.ellipse(hd_f[0], hd_f[1] + 1.0, 1.6, 1.8), 'joint', mode='cyl', bias=-0.6)
    # --- pelvis y torso (lata alta de esmalte verde agua desteñido), encorvado: el pecho adelantado
    pel = cv.ellipse(cx, hip_y, 5.2, 2.8)
    cv.put(pel, 'enamel2', mode='cyl', iline=True, cast=1)
    tor = cv.poly([(cx - 5.0, hip_y - 3.0), (cx + 4.5, hip_y - 3.0), (cx + 6.6, 47.0 + bob), (cx + 6.0, 42.0 + bob),
                   (cx + 4.0, 40.5 + bob), (cx - 3.5, 40.5 + bob), (cx - 5.5, 42.5 + bob), (cx - 6.0, 47.0 + bob)])
    p = cv.put(tor, 'enamel', mode='cyl', iline=True, cast=1)
    # aros de la lata
    for y in (hip_y - 4.0, 46.0 + bob):
        cv.shade(cv.line([(cx - 7, y), (cx + 8, y)]), -1, within=[p])
        cv.shade(cv.line([(cx - 7, y + 1), (cx + 8, y + 1)]), +1, within=[p])
    # óxido en los bordes de abajo y una placa con un dial
    cv.paint(cv.ellipse(cx - 5.0, hip_y - 6.0, 1.8, 2.6) & cv.of(p), 'rust', 2)
    cv.paint(cv.ellipse(cx + 5.5, hip_y - 4.0, 1.4, 1.2) & cv.of(p), 'rust', 2)
    dc = (cx + 2.5, 51.5 + bob)
    cv.put(cv.ellipse(dc[0], dc[1], 3.0, 2.9), 'brass', mode='shine', iline=True, cast=1)
    cv.put(cv.ellipse(dc[0] + 0.1, dc[1] + 0.1, 2.0, 1.9), 'dial', mode='flat')
    cv.dot(dc[0] + 1, dc[1] - 1, 'needle', 4)
    cv.dot(dc[0], dc[1], 'needle', 4)
    # remaches
    for y in (49.0, 55.0):
        cv.dot(cx - 3.5, y + bob, 'enamel2', 1)
    # hombros (bolas)
    _ball(cv, sh_f, 1.9, 'joint', False, -0.4)
    # --- cuello (caño fino con un aro) y la cabeza: bombita (la cara) bajo una pantalla de lámpara
    hx = cx + 3.0                    # la cabeza adelantada (encorvado)
    neck = cv.capsule((cx + 1.0, 41.0 + bob), (hx - 0.5, 36.0 + bob), 0.9)
    cv.put(neck, 'iron', mode='cyl', iline=True)
    cv.put(cv.ellipse(cx + 1.0, 40.6 + bob, 2.4, 1.0), 'brass', mode='shine', iline=True)
    by = 33.0 + bob
    # bombita de vidrio que cuelga bajo la pantalla: redonda abajo, cuello angosto hacia el casquillo; sin contorno
    # oscuro: un halo ámbar alrededor (se lee como luz)
    bulb = cv.ellipse(hx, by + 1.0, 3.7, 3.6) | cv.poly([(hx - 1.4, by - 4.4), (hx + 1.4, by - 4.4), (hx + 2.8, by - 1.2), (hx - 2.8, by - 1.2)])
    halo = (cv.ellipse(hx, by + 1.0, 4.8, 4.7) | cv.poly([(hx - 2.3, by - 4.4), (hx + 2.3, by - 4.4), (hx + 3.8, by - 1.2), (hx - 3.8, by - 1.2)])) & ~bulb
    h_ = cv.put(halo, 'glowring', mode='flat', outline=False)
    cv.parts[h_].keep = True
    q = cv.put(bulb, 'bulb', mode='flat', outline=False)
    cv.parts[q].keep = True
    # núcleo blanco y reflejo del vidrio
    for (x, y) in ((hx - 1, by + 2), (hx, by + 2), (hx - 1, by + 3), (hx, by + 3)):
        cv.dot(x, y, 'white', 4)
    cv.dot(hx - 2.4, by + 0.2, 'white', 4)
    # la cara: dos ojitos oscuros mirando a la derecha (nada de boca: es una bombita)
    for (ex, ey) in ((hx + 0.2, by + 0.0), (hx + 2.2, by - 0.1)):
        cv.dot(ex, ey, 'eyed', 0)
        cv.dot(ex, ey + 1, 'eyed', 0)
    # casquillo de bronce entre la bombita y la pantalla
    cv.put(cv.rect(int(hx - 2.0), int(by - 6.5), int(hx + 2.0), int(by - 4.6)), 'brass', mode='shine', iline=True)
    # pantalla: cono truncado (angosto arriba), plisada, con el borde de abajo y flecos que se mecen
    top_y, bot_y = 17.5 + bob, 28.8 + bob
    tw, bw = 5.0, 10.8
    sx = hx - 0.5
    sh = cv.poly([(sx - tw, top_y), (sx + tw, top_y), (sx + bw, bot_y), (sx - bw, bot_y)])
    s = cv.put(sh, 'shade', mode='cyl', cast=2, iline=True)
    for k in range(-4, 5):
        t0 = (sx + k * tw / 4.5, top_y + 1)
        t1 = (sx + k * bw / 4.5, bot_y - 1)
        cv.shade(cv.line([t0, t1]), -1 if k % 2 else +1, within=[s])
    # ribete arriba y abajo
    cv.paint(sh & (cv.ys <= top_y + 0.5), 'shade2', 2)
    cv.paint(sh & (cv.ys >= bot_y - 1.0), 'fringe', 2)
    # flecos (borlitas) colgando del borde, se mecen con el paso
    fr = np.zeros_like(sh)
    for k, x in enumerate(range(int(sx - bw) + 1, int(sx + bw), 2)):
        fr |= cv.rect(x + (lag if k % 2 else 0) * 0, int(bot_y + 1), x, int(bot_y + 2 + (k % 2)))
    f = cv.put(fr & ~sh, 'fringe', mode='flat', iline=False)
    cv.parts[f].keep = True
    # remate de bronce arriba
    cv.put(cv.ellipse(sx, top_y - 1.4, 1.6, 1.4), 'brass', mode='shine', iline=True, cast=1)
    # --- brazo cercano con la aceitera (para su rodilla): cuelga adelante
    sh_n = (cx - 5.5, 44.0 + bob)
    el_n = (sh_n[0] - 0.5 + swing * 1.5, sh_n[1] + 9.0)
    hd_n = (el_n[0] + 2.5 + swing * 2.0, el_n[1] + 8.0)
    _limb(cv, sh_n, el_n, 1.3, 1.2, 'iron', True)
    _limb(cv, el_n, hd_n, 1.2, 1.1, 'iron', True)
    _ball(cv, sh_n, 2.1, 'joint', True)
    _ball(cv, el_n, 1.6, 'joint', True)
    # aceitera: lata cónica roja con pico largo
    cx_, cy_ = hd_n[0] + 0.5, hd_n[1] + 3.5
    can = cv.poly([(cx_ - 2.8, cy_ + 2.5), (cx_ + 2.8, cy_ + 2.5), (cx_ + 1.4, cy_ - 1.5), (cx_ - 1.4, cy_ - 1.5)])
    cv.put(can, 'can', mode='shine', iline=True, cast=1)
    cv.put(cv.line([(cx_ + 0.5, cy_ - 1.5), (cx_ + 4.5, cy_ - 6.0)]), 'brass', mode='flat')
    # pinza (mano) sobre el asa de la aceitera
    cv.put(cv.ellipse(hd_n[0], hd_n[1] + 0.5, 1.7, 1.9), 'joint', mode='cyl', iline=True)
    return render(cv)


def clatter_frames():
    return [draw_clatter('idle', i) for i in range(2)], [draw_clatter('walk', i) for i in range(4)]


REG['clatter'] = clatter_frames


# ================================================================== la tortuga de las dunas (props/tortoise.png)

TORT_MATS = {
    'shell': ('#c89c5c', 'cloth'), 'shell2': ('#8a6438', 'cloth'), 'shellhi': ('#e2c48a', 'cloth'), 'rim': ('#a07a46', 'cloth'),
    'tskin': ('#9c9474', 'skin'), 'tskin2': ('#7a7458', 'skin'), 'nail': ('#e6dcc0', 'white'), 'eyed': ('#2a2224', 'flat'),
    'blanket': '#b04a34', 'blanket2': ('#e8dcc0', 'white'), 'blanket3': '#3e8a86', 'fringe': '#d8a040',
    'rope': ('#d2b884', 'cloth'), 'crate': '#b08048', 'tarp': '#c8b890', 'tarp2': '#3e8a86', 'pipe': ('#a86a44', 'metal'),
    'gear': ('#c07a3a', 'metal'), 'hose': '#2e4a4a', 'lamp': ('#8a8a90', 'metal'), 'glow': ('#ffd36a', 'flat'),
    'can': ('#c84a36', 'metal'), 'iron': ('#6a646c', 'metal'),
}


def draw_tortoise(blink=False):
    """Tortuga de carga mirando a la derecha: caparazón alto (placas hexagonales, borde festoneado), manta a rayas,
    carga atada (cajón, lona, manguera, caños, engranaje, farol), cabeza con párpado pesado y patas cortas y anchas."""
    pal, kinds = pal_of(TORT_MATS, accents=('blanket', 'blanket3'))
    W_, H_ = 128, 96
    cv = Cv(pal, w=W_, h=H_, kinds=kinds)
    G = 92
    oy = 9.0                       # todo el cuerpo baja: patas cortas, el caparazón cerca del suelo

    def Y(y):
        return y + oy
    # cola y patas lejanas (detrás, más oscuras)
    cv.put(cv.poly([(22, Y(64)), (14, Y(69)), (16, Y(71)), (25, Y(67))]), 'tskin2', mode='cyl', iline=False, bias=-0.4)
    for (x, top) in ((32.0, Y(64.0)), (80.0, Y(64.0))):
        m, n = cv.capsule_n((x, top), (x - 1.0, G - 3.5), 5.6, 6.0)
        cv.put(m, 'tskin2', mode='stroke', nrm=n, bias=-0.7)
        cv.put(cv.ellipse(x - 0.5, G - 2.0, 7.0, 2.6), 'tskin2', mode='cyl', bias=-0.7)
    # cuello y cabeza (a la derecha, sale de debajo del caparazón)
    neck, nn = cv.capsule_n((86.0, Y(64.0)), (104.0, Y(58.0)), 6.6, 5.4)
    pn = cv.put(neck, 'tskin', mode='stroke', nrm=nn, iline=True, cast=1)
    for k in range(3):
        x = 92 + k * 4
        cv.shade(cv.line([(x, Y(55 + k * 0.3)), (x - 1, Y(68 - k))]), -1, within=[pn])
    hm = cv.ellipse(110.0, Y(55.0), 10.0, 7.4) | cv.ellipse(117.0, Y(57.0), 5.0, 4.8)
    ph = cv.put(hm, 'tskin', mode='soft', iline=True, cast=1)
    cv.set_nrm(ph, cv.sphere_n(108.0, Y(53.0), 12.0, 9.0, k=0.85))
    cv.paint(cv.line([(105.0, Y(60.5)), (112.0, Y(61.6)), (118.0, Y(60.4)), (121.5, Y(58.0))]), 'eyed', 1)
    cv.dot(120.0, Y(54.5), 'eyed', 0)
    ex, ey = 111.0, Y(52.0)
    if blink:
        cv.paint(cv.line([(ex - 2, ey + 1), (ex + 2, ey + 1)]), 'eyed', 0)
    else:
        for (x, y, l) in ((ex - 1, ey + 1, 0), (ex, ey + 1, 0), (ex + 1, ey + 1, 0), (ex, ey + 2, 0), (ex - 1, ey + 2, 0)):
            cv.dot(x, y, 'eyed', l)
        cv.dot(ex - 1, ey + 1, 'white', 4)
        cv.paint(cv.line([(ex - 2.5, ey), (ex + 2.5, ey - 0.5)]), 'tskin2', 1)
    # caparazón
    sx, sy = 58.0, Y(52.0)
    dome = cv.ellipse(sx, sy, 39.0, 29.0) & (cv.ys <= sy + 8)
    ps = cv.put(dome, 'shell', mode='dome', cast=2, iline=True)
    cv.set_nrm(ps, cv.sphere_n(sx - 6, sy - 10, 44.0, 34.0, k=0.9))
    rim = np.zeros_like(dome)
    for k, x in enumerate(range(21, 97, 6)):
        rim |= cv.ellipse(x + 3.0, sy + 8.5 + (1.0 if k % 2 else 0.0), 3.6, 2.6)
    rim |= cv.rect(20, int(sy + 5), 96, int(sy + 8))
    rim &= cv.ellipse(sx, sy + 2, 40.5, 34.0)
    pr = cv.put(rim, 'rim', mode='cyl', iline=True, cast=1)
    for x in range(24, 97, 6):
        cv.shade(cv.line([(x, sy + 5), (x, sy + 11)]), -1, within=[pr])
    plates = [((44, 34), 8.5, 6.0), ((60, 29), 9.0, 6.4), ((76, 34), 8.0, 6.0), ((34, 46), 7.0, 5.6), ((52, 44), 8.0, 5.8),
              ((70, 44), 8.0, 5.8), ((86, 46), 6.4, 5.4)]
    for (c, rx, ry) in plates:
        c = (c[0], Y(c[1]))
        pts = [(c[0] + rx * math.cos(a), c[1] + ry * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 7)]
        cv.shade(cv.line(pts), -2, within=[ps])
        cv.paint(cv.ellipse(c[0] - 1.5, c[1] - 1.2, rx * 0.45, ry * 0.40) & dome, 'shellhi', 2)
    # manta de montura
    bl = cv.poly([(42, Y(20)), (66, Y(18)), (72, Y(38)), (75, Y(60)), (39, Y(61)), (40, Y(38))]) & (dome | rim)
    pb = cv.put(bl, 'blanket', mode='cyl', cast=1, iline=True)
    for (y0, mat) in ((28, 'blanket2'), (31, 'blanket3'), (46, 'blanket2'), (49, 'blanket3')):
        cv.paint(cv.rect(30, int(Y(y0)), 90, int(Y(y0)) + 1) & cv.of(pb), mat, 2)
    fr = np.zeros_like(bl)
    for x in range(40, 76, 2):
        fr |= cv.rect(x, int(Y(61)), x, int(Y(63)) + (x // 2) % 2)
    q = cv.put(fr & ~bl, 'fringe', mode='flat')
    cv.parts[q].keep = True
    # carga atada encima
    cr = cv.rect(46, int(Y(8)), 64, int(Y(20)))
    pc = cv.put(cr, 'crate', mode='cyl', iline=True, cast=2)
    for y in (11, 14, 17):
        cv.shade(cv.line([(46, Y(y)), (64, Y(y))]), -1, within=[pc])
    cv.shade(cv.line([(47, Y(9)), (63, Y(19))]), +1, within=[pc])
    tm = cv.capsule((32.0, Y(20.0)), (48.0, Y(17.0)), 4.2)
    pt = cv.put(tm, 'tarp', mode='top', iline=True, cast=1)
    for x in range(30, 50, 4):
        cv.paint(cv.rect(x, int(Y(12)), x + 1, int(Y(25))) & cv.of(pt), 'tarp2', 2)
    ring = cv.ellipse(73.0, Y(19.0), 7.5, 4.0) & ~cv.ellipse(73.5, Y(19.0), 3.6, 1.6)
    cv.put(ring, 'hose', mode='stroke', nrm=cv.sphere_n(72.0, Y(18.0), 8.5, 5.0), iline=True, cast=1)
    cv.put(cv.capsule((40.0, Y(16.0)), (26.0, Y(4.0)), 1.6), 'pipe', mode='shine', iline=True, cast=1)
    cv.put(cv.capsule((60.0, Y(8.0)), (66.0, Y(-0.5)), 1.2), 'pipe', mode='shine', iline=True, cast=1)
    gc = (82.0, Y(24.0))
    gm = cv.ellipse(gc[0], gc[1], 5.0, 5.0)
    for k in range(10):
        a = k * math.pi / 5
        gm |= cv.ellipse(gc[0] + math.cos(a) * 5.4, gc[1] + math.sin(a) * 5.4, 1.2, 1.2)
    gm &= ~cv.ellipse(gc[0], gc[1], 1.8, 1.8)
    cv.put(gm, 'gear', mode='shine', iline=True, cast=1)
    for (a, b) in (((47, 20), (41, 56)), ((63, 20), (70, 56)), ((34, 23), (30, 50))):
        cv.put(cv.line([(a[0], Y(a[1])), (b[0], Y(b[1]))]), 'rope', mode='flat')
    cv.put(cv.line([(94.0, Y(38.0)), (95.0, Y(42.0))]), 'iron', mode='flat')
    lm = cv.rect(92, int(Y(42)), 97, int(Y(48)))
    cv.put(lm, 'lamp', mode='shine', iline=True, cast=1)
    cv.paint(cv.rect(93, int(Y(43)), 96, int(Y(47))), 'glow', 3)
    cv.put(cv.rect(25, int(Y(38)), 30, int(Y(45))), 'can', mode='shine', iline=True, cast=1)
    # patas cercanas: cortas, anchas, un poco abiertas, con uñas
    for (x, top) in ((38.0, Y(62.0)), (84.0, Y(62.0))):
        m, n = cv.capsule_n((x, top), (x + 1.0, G - 3.0), 6.2, 6.6)
        pl = cv.put(m, 'tskin', mode='stroke', nrm=n, iline=True, cast=1)
        cv.shade(cv.line([(x - 4, top + 6), (x + 4, top + 7)]), -1, within=[pl])
        foot = cv.ellipse(x + 1.2, G - 2.0, 7.6, 2.8)
        cv.put(foot, 'tskin', mode='cyl', iline=True)
        for k in (-3.5, 0.0, 3.5):
            cv.dot(x + 2.5 + k, G - 1.0, 'nail', 3)
    return render(cv)


PROPS['tortoise'] = lambda: draw_tortoise(False)
