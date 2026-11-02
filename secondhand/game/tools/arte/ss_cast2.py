"""Secondhand Stars · round 2 · el elenco nuevo (cuadros de 64x96, el mismo estilo HD-2D del elenco de siempre).

--- SS2 BENCH (nuevo). Ids de ROL (los nombres que se ven viven en scripts/cast_data.gd):
  rival       Madame Glint: alta, colmena turquesa con un broche de estrella cromado, abrigo charolado rosa durazno
              con vivos plateados (forro del mismo color), lupa de joyero colgando de una cadena, botas blancas,
              cartera con forma de estrella. Nunca un abrigo blanco con forro de otro color ni un mechón bicolor.
  inspector   Inspector Tolle: abrigo mostaza entallado, faja y guantes crema, botones de bronce, moño castaño bajo un
              sombrerito redondo SIN ala ni visera (pillbox) con el emblema de la Tally Office (una marca de conteo:
              cuatro palotes cruzados por un quinto, nunca un engranaje), anteojos redondos de bronce, sombrilla verde
              azulado de mango liso y un libro de cuentas gordo.
  singer      Lune (Lampwing): polilla alta y suave, gola de pelusa crema, alas rosa viejo y lila plegadas como un chal
              (la cara siempre a la vista), antenas plumosas, ojos grandes y oscuros (que NO brillan), abrigo largo de
              lentejuelas.
  tracker     Warden Brisk (Brushtail): SIN sombrero: las orejas de zorro son la silueta, antiparras subidas entre las
              orejas, bufanda ciruela larga, abrigo a la rodilla, morral de órdenes, placa de bronce, un lazo de cable
              enrollado y una tablilla. Sin casco, armadura, mochila cohete, capa ni armas. Cola tupida.
  timekeeper  Madam Sift (Sandglass): un reloj de arena de vidrio en un marco de bronce (la ampolla de arriba es la
              cabeza y el pecho, la de abajo la falda), gorrito de bronce, bracitos finos, dos ojos como alfileres en la
              arena dorada; la arena cae entre los dos cuadros quietos.
  vendor      Dolly: robot montacargas bajo y ancho sobre 4 ruedas gordas, con un mástil vertical y SU CARA PINTADA EN
              EL TRAVESAÑO del mástil (dos faros redondos y una sonrisa de plantilla), dos brazos fuertes y las uñas
              del montacargas adelante; pintura verde azulado descascarada. Sin cuello, sin cúpula, sin asiento ni
              cabina. Solo rueda: su hoja de caminar son sus 2 cuadros quietos repetidos.
  hermit      Old Seven: un faro que camina (~84 px): torre ahusada de esmalte verde botella con una franja blanca, la
              baranda de la galería como cuello, la jaula de la linterna como cabeza con una bombita ámbar (sin ojos),
              bracitos fuertes, un bastón de cayado con un farol colgando; costra de sal, arena y parches de pintura
              (nada de musgo); un manto de lona beige remendado sobre los hombros, SIN capucha.
Ningún texto ni nombre propio pintado en los PNG (la plantilla de Dolly es una flecha, no letras).

Uso: python3 ss_cast2.py [ids...] [--out DIR] [--sheet hoja.png] [--game DIR_DEL_JUEGO]
  -> DIR/chars/<id>_idle.png (2 cuadros de 64x96) y <id>_walk.png (4 cuadros). --sheet: la hoja del elenco nuevo a x3
  junto al elenco de siempre (lee las hojas viejas de --game/assets/chars).
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from c64core import *
from c64core import _norm
from c64body import *
from c64parts import *
from c64hair import *
from c64acc import *
from c64hat import *
import chars64
from chars64 import frames
from ss_parts import *
from ss_parts import _curl
from ss_bots import pal_of, _limb, _ball, _knee_pt
from c64body import GROUND


# ================================================================== piezas nuevas para el kit (humanoides)

def beehive(cv, B, sp, pose):
    """Colmena alta (Glint): una masa de pelo redondeada que sube por encima de la coronilla, con mechones que
    giran hacia arriba (va en 'back': la cabeza tapa su base)."""
    c = hp(B, 8.4, -4.2)
    m = cv.ellipse(c[0], c[1], 7.4, 8.8) | cv.ellipse(c[0] - 0.6, c[1] + 4.6, 8.2, 5.4)
    p = hmass(cv, m, 2, cast=1, iline=True)
    cv.set_nrm(p, cv.sphere_n(c[0] - 2.5, c[1] - 3.0, 9.0, 10.5, k=0.85))
    for k in range(3):
        y0 = c[1] + 5.0 - k * 4.4
        cv.shade(cv.line([(c[0] - 5.6 + k, y0 + 1.6), (c[0] - 1.0, y0 - 0.6), (c[0] + 4.6 - k, y0 + 0.4)]), -1, within=[p])
    cv.dot(c[0] - 3.2, c[1] - 5.0, 'white', 3)
    return p


def star_clip(cv, B, sp, pose, mat='chrome'):
    """El broche de estrella cromado en la colmena (5 puntas, chiquito)."""
    c = hp(B, 14.2, -2.6)
    pts = []
    for k in range(10):
        r = 3.6 if k % 2 == 0 else 1.5
        a = -math.pi / 2 + k * math.pi / 5
        pts.append((c[0] + math.cos(a) * r, c[1] + math.sin(a) * r))
    cv.put(cv.poly(pts), mat, mode='shine', iline=True)
    cv.dot(c[0] - 0.5, c[1] - 0.6, 'white', 4)


def loupe_chain(cv, B, sp, pose, mat='chrome', lens='lens'):
    """La lupa de joyero colgando de una cadena fina sobre el pecho."""
    cx = B.cx_sh + 2.0
    top = (cx - 2.5, B.y_sh + 0.5)
    lo = (cx + 0.5, B.y_sh + 7.5 + pose.lag * 0.5)
    m = cv.line([top, lo]) | cv.line([(top[0] + 4.0, top[1]), lo])
    cv.put(m, mat, mode='flat', outline=False)
    ring = cv.ellipse(lo[0], lo[1] + 2.0, 2.2, 2.2)
    cv.put(ring, mat, mode='shine', iline=True)
    cv.put(cv.ellipse(lo[0], lo[1] + 2.0, 1.1, 1.1), lens, mode='flat')


def star_bag(cv, B, sp, side, pose, mat='bag', trim='chrome'):
    """La cartera con forma de estrella colgando del antebrazo (rosa con canto plateado)."""
    g = B.arm[side]['grip']
    c = (g[0] + 1.0, g[1] + 6.5 + pose.lag * 0.5)
    cv.paint(cv.line([(g[0] - 1.0, g[1]), (c[0] - 2.0, c[1] - 4.0)]), trim, 3)
    cv.paint(cv.line([(g[0] + 1.0, g[1]), (c[0] + 2.0, c[1] - 4.0)]), trim, 3)
    pts = []
    for k in range(10):
        r = 5.6 if k % 2 == 0 else 2.7
        a = -math.pi / 2 + k * math.pi / 5
        pts.append((c[0] + math.cos(a) * r, c[1] + math.sin(a) * r * 0.95))
    m = cv.poly(pts)
    p = cv.put(m, mat, mode='shine', cast=1, iline=True)
    cv.dot(c[0] - 1.0, c[1] - 1.2, 'white', 4)
    return p


def pillbox(cv, B, sp, pose, mat='hat', band='hat2', mark='ink'):
    """Sombrerito redondo SIN ala ni visera (un tambor bajo, más angosto que la cabeza) sobre la coronilla, algo
    ladeado hacia la derecha, con el emblema de la Tally Office: cuatro palotes y uno que los cruza."""
    c = hp(B, 10.0, 0.8)
    w = 5.2
    pts = [(c[0] - w, c[1] + 0.8), (c[0] + w, c[1] - 0.4), (c[0] + w - 0.2, c[1] - 5.0), (c[0] - w + 0.4, c[1] - 3.8)]
    p = cv.put(cv.poly(pts), mat, mode='cyl', cast=2, iline=True)
    cv.put(cv.ellipse(c[0] + 0.1, c[1] - 4.4, w - 0.2, 1.1), mat, mode='top', iline=True)
    cv.paint(cv.poly([(c[0] - w, c[1] - 0.6), (c[0] + w, c[1] - 1.8), (c[0] + w, c[1] - 0.6), (c[0] - w, c[1] + 0.6)]) & cv.of(p), band, 2)
    # el emblema (marca de conteo) en el frente: cuatro palotes y uno cruzado
    x0, y0 = int(c[0] - 1), int(c[1] - 4)
    for k in range(4):
        cv.dot(x0 + k, y0 + 1, mark, 3)
        cv.dot(x0 + k, y0 + 2, mark, 3)
    cv.dot(x0 - 1, y0 + 2, mark, 3)
    cv.dot(x0 + 4, y0 + 1, mark, 3)
    return p


def furled_parasol(cv, B, sp, side, pose, mat='canopy', band='canopy2', pole='pole'):
    """La sombrilla cerrada, apoyada en el suelo como un bastón: mango recto y liso arriba de la mano, la tela verde
    azulado enrollada (un huso largo) y la punta en el suelo."""
    g = B.arm[side]['grip']
    top = (g[0] - 0.5, g[1] - 4.0)
    foot = (g[0] + 2.5, GROUND - 0.5)
    cv.put(cv.capsule(top, foot, 0.8, 0.7), pole, mode='shine', iline=True)
    a = (g[0] + 0.4, g[1] + 4.0)
    b = (g[0] + 2.0, GROUND - 7.0)
    pts = [a, ((a[0] + b[0]) / 2 + 1.0, (a[1] + b[1]) / 2), b]
    m = cv.stroke(bez(*pts, 8), 1.3, 0.6) | cv.stroke([a, ((a[0] + b[0]) / 2, a[1] + 6.0)], 2.2, 1.6)
    p = cv.put(m, mat, mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(int(a[0] - 2), int(a[1] + 5), int(a[0] + 3), int(a[1] + 5)) & cv.of(p), band, 2)
    return p


def ledger(cv, B, sp, side, pose, cover='ledger', page='page', clasp='brass'):
    """El libro de cuentas gordo apretado contra el pecho: tapa, el canto de muchas páginas y un broche."""
    g = B.arm[side]['grip']
    x, y = g[0] + 0.5, g[1] - 1.0
    m = cv.rect(int(x - 3), int(y - 6), int(x + 3), int(y + 1))
    p = cv.put(m, cover, mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(int(x + 3), int(y - 5), int(x + 5), int(y + 1)), page, mode='cyl', iline=True)
    for yy in range(int(y - 4), int(y + 1), 2):
        cv.dot(x + 4, yy, page, 1)
    cv.dot(x + 1, y - 3, clasp, 4)
    cv.dot(x + 1, y - 2, clasp, 2)
    return p


def moth_wings_back(cv, B, sp, pose, mat='wing2', edge='wing3'):
    """El ala lejana de Lune (lila), plegada detrás del cuerpo: asoma por el costado y hasta las rodillas."""
    sh = (B.cx_sh + 3.0, B.y_sh + 0.5)
    lag = pose.lag
    pts = [sh, (sh[0] + 7.5, sh[1] + 4.0), (sh[0] + 8.5 + pose.sway, sh[1] + 18.0 + lag), (sh[0] + 5.0 + pose.sway, sh[1] + 27.0 + lag),
           (sh[0] - 1.0, sh[1] + 24.0)]
    m = cv.poly(pts)
    p = cv.put(m, mat, mode='cyl', cast=0, iline=True, bias=-0.4)
    cv.paint(cv.poly([(sh[0] + 6.5, sh[1] + 19.0 + lag), (sh[0] + 8.0, sh[1] + 20.0 + lag), (sh[0] + 4.5, sh[1] + 26.0 + lag),
                      (sh[0] + 3.0, sh[1] + 24.0)]) & cv.of(p), edge, 2)
    return p


def moth_wing_shawl(cv, B, sp, pose, mat='wing', band='wing3', dot='wing4'):
    """El ala cercana plegada sobre el hombro y el brazo como un chal (rosa viejo), con una banda clara festoneada
    abajo y dos pintas suaves (no son ojos)."""
    sh = (B.cx_sh - B.sw / 2.0 - 0.5, B.y_sh - 0.5)
    lag = pose.lag
    sw = pose.sway
    top_r = (B.cx_sh + 3.0, B.y_sh - 0.5)
    pts = [(sh[0] + 2.0, sh[1] - 1.0), top_r, (top_r[0] + 1.0, top_r[1] + 6.0), (sh[0] + 6.0, sh[1] + 15.0 + lag),
           (sh[0] - 1.0 + sw, sh[1] + 22.0 + lag), (sh[0] - 3.5 + sw, sh[1] + 16.0), (sh[0] - 2.5, sh[1] + 4.0)]
    m = cv.poly(pts)
    p = cv.put(m, mat, mode='cyl', cast=1, iline=True)
    # festón claro en el borde de abajo
    hem = cv.poly([(sh[0] + 6.0, sh[1] + 13.0 + lag), (sh[0] + 7.0, sh[1] + 15.5 + lag), (sh[0] - 1.0 + sw, sh[1] + 23.0 + lag),
                   (sh[0] - 4.0 + sw, sh[1] + 17.0), (sh[0] - 3.0 + sw, sh[1] + 15.0)])
    cv.paint(hem & cv.of(p), band, 2)
    for (dx, dy) in ((1.0, 7.0), (-1.0, 11.0)):
        cv.paint(cv.ellipse(sh[0] + dx, sh[1] + dy + lag * 0.5, 1.4, 1.2) & cv.of(p), dot, 2)
    return p


def antennae(cv, B, sp, pose, mat='antenna', vane='antenna2'):
    """Antenas plumosas de polilla: un tallo fino que se arquea hacia atrás con barbas cortas a los dos lados (un peine),
    más cortas hacia la punta. Nunca ramificadas (no son cuernos) ni hojas anchas (no son orejas)."""
    lag = pose.lag * 0.5
    for i, (bx, tdx, cdx, bias) in enumerate(((7.0, -6.5, -0.5, 0.0), (12.0, 4.5, 3.0, -0.6))):
        base = hp(B, bx, 1.8)
        tip = (base[0] + tdx, base[1] - 11.0 + lag)
        ctrl = (base[0] + cdx, base[1] - 9.0)
        pts = bez(base, ctrl, tip, 16)
        barbs = np.zeros((cv.h, cv.w), bool)
        for k in range(2, len(pts) - 1):
            x, y = pts[k]
            dx, dy = pts[k + 1][0] - pts[k - 1][0], pts[k + 1][1] - pts[k - 1][1]
            l = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / l, dx / l
            if k % 2:
                continue
            r = 1.8 * math.sin(math.pi * k / (len(pts) - 1)) + 0.3
            barbs |= cv.line([(x - nx * r, y - ny * r), (x + nx * r, y + ny * r)])
        q = cv.put(barbs, vane, mode='flat', outline=False, bias=bias)
        cv.parts[q].keep = True
        q2 = cv.put(cv.line(pts), mat, mode='flat', outline=False, bias=bias)
        cv.parts[q2].keep = True


def moth_fuzz(cv, B, sp, pose, mat='ruff'):
    """Pelusa crema en la coronilla de la Lampwing (entre las antenas) y un sombreado lila en la nuca."""
    c = hp(B, 9.0, 1.0)
    m = cv.ellipse(c[0], c[1], 5.0, 2.4)
    for k in range(-2, 3):
        m |= cv.ellipse(c[0] + k * 2.0, c[1] - 1.6 - (k % 2) * 0.8, 1.2, 1.4)
    cv.put(m, mat, mode='soft', cast=1, iline=True)
    cv.shade(cv.of(B.head_part) & (cv.xs <= B.hx + 3), -1)


def moth_eyes(cv, B, sp, pose, mat='eyedark'):
    """Ojos grandes y oscuros (sin brillo propio): un óvalo por ojo con un puntito crema arriba."""
    a1, a2 = ha(B, 1), ha(B, 2)
    for (x, y, w, h) in ((a1[0] - 0.2, a1[1] + 0.6, 2.2, 2.8), (a2[0] + 1.0, a2[1] + 0.6, 1.6, 2.6)):
        q = cv.put(cv.ellipse(x, y, w, h), mat, mode='flat', outline=False)
        cv.parts[q].keep = True
        cv.dot(x - 0.8, y - 1.2, 'white', 4)
        cv.dot(x + 0.6, y + 1.2, 'eyelit', 3)


def sequins(cv, B, sp, pose, mat='sequin'):
    """Lentejuelas: puntitos claros sueltos sobre el abrigo largo (a partir de la cintura)."""
    for k in range(40):
        x = 14 + (k * 37) % 36
        y = int(B.y_w) + 2 + (k * 23) % 34
        if y >= cv.h - 1:
            continue
        if cv.pid[y, x] > 0 and cv.parts[cv.pid[y, x]].mat == 'coat' and cv.force[y, x] < 0:
            cv.dot(x, y, mat, 4 if k % 3 else 3)


def fox_snout(cv, B, sp, pose, mat='muzzle', nose='nose'):
    """Hocico de zorro hacia la derecha (crema), la nariz negra en la punta y el cachete blanco."""
    a3 = ha(B, 3)
    tip = (a3[0] + 5.5, a3[1] - 1.0)
    m = cv.poly([(a3[0] - 3.0, a3[1] - 3.0), (tip[0], tip[1] - 1.2), (tip[0] + 0.6, tip[1] + 0.8), (a3[0] - 1.0, a3[1] + 1.6),
                 (a3[0] - 4.0, a3[1] + 1.0)])
    cv.put(m, mat, mode='soft', cast=1, iline=True)
    cv.put(cv.ellipse(tip[0], tip[1] - 0.2, 1.3, 1.1), nose, mode='shine')
    cv.paint(cv.line([(a3[0] - 0.5, a3[1] + 0.8), (tip[0] - 1.0, tip[1] + 1.0)]), 'mouth', 0)
    # cachete claro (pelaje blanco) abajo, lejos de los ojos
    cv.paint(cv.ellipse(a3[0] - 4.5, a3[1] + 1.5, 2.6, 1.6) & cv.of(B.head_part), mat, 2)


def fox_ears(cv, B, sp, pose, mat='skin', inner='inner', tip='eartip'):
    """Orejas de zorro altas y puntiagudas (la silueta de Brisk): la lejana detrás, más oscura."""
    out = []
    for i, (bx, lean) in enumerate(((3.6, -1.8), (13.0, 1.4))):
        base_l = hp(B, bx - 3.6, 2.6)
        base_r = hp(B, bx + 3.4, 2.0)
        tp = hp(B, bx + lean, -9.5)
        m = cv.poly([base_l, tp, base_r])
        p = cv.put(m, mat, mode='cyl', cast=0, iline=True, bias=-0.5 if i == 1 else 0.0)
        cv.paint(cv.poly([hp(B, bx - 1.4, 1.6), hp(B, bx + lean * 0.8, -6.4), hp(B, bx + 1.6, 1.2)]) & cv.of(p), inner, 1 if i == 0 else 0)
        cv.paint(cv.poly([hp(B, bx + lean - 1.6, -6.6), tp, hp(B, bx + lean + 1.6, -6.8)]) & cv.of(p), tip, 1)
        out.append(p)
    return out


def badge(cv, B, sp, pose, mat='brass'):
    """La placa de bronce "TALLY WARRANT" (sin letras: un escudito con su marca)."""
    x, y = B.cx_sh - 2.5, B.y_sh + 5.0
    cv.put(cv.poly([(x - 1.5, y - 1.5), (x + 1.5, y - 1.5), (x + 1.5, y + 0.5), (x, y + 2.0), (x - 1.5, y + 0.5)]), mat, mode='shine', iline=True)
    cv.dot(x - 0.4, y - 0.6, 'white', 4)


def cable_coil(cv, B, sp, pose, mat='cable', band='cable2'):
    """El lazo de cable enrollado colgando de la cadera (anillos)."""
    c = (B.cx_hip + B.hw / 2.0 - 0.5, B.y_w + 4.5 + pose.lag * 0.5)
    ring = cv.ellipse(c[0], c[1], 3.4, 3.0) & ~cv.ellipse(c[0], c[1], 1.6, 1.4)
    p = cv.put(ring, mat, mode='shine', cast=1, iline=True)
    cv.shade(cv.ellipse(c[0] + 0.5, c[1] + 0.5, 2.6, 2.2) & ~cv.ellipse(c[0] + 0.5, c[1] + 0.5, 2.0, 1.6), -1, within=[p])
    cv.paint(cv.rect(int(c[0] - 1), int(c[1] - 3), int(c[0] + 1), int(c[1] - 3)), band, 2)


def clipboard(cv, B, sp, side, pose, board='board', paper='page', clip='steel'):
    """La tablilla con un papel y su pinza, sostenida delante del pecho."""
    g = B.arm[side]['grip']
    x, y = g[0] + 1.0, g[1] - 2.0
    cv.put(cv.rect(int(x - 3), int(y - 6), int(x + 3), int(y + 2)), board, mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(int(x - 2), int(y - 4), int(x + 2), int(y + 1)), paper, mode='flat')
    for yy in (int(y - 3), int(y - 1)):
        cv.paint(cv.rect(int(x - 1), yy, int(x + 1), yy), 'ink', 2)
    cv.put(cv.rect(int(x - 1), int(y - 7), int(x + 1), int(y - 5)), clip, mode='shine', iline=True)


# especie nueva del kit: la Lampwing (alta y fina)
SPECIES['lampwing'] = dict(h=64, head='adult_f', neck=2, sw=11.5, ww=8.5, hw=10.0, leg=21, waist=0.70, ua=7.0, fa=6.5, ar=1.5,
                           tr=1.7, sr=1.5, foot=6, hipx=2.2, chest=0)
SPECIES['brushtail'] = dict(h=58, head='adult_f', neck=1, sw=12, ww=9, hw=10.5, leg=19, waist=0.70, ua=6.5, fa=6.0, ar=1.6,
                            tr=1.8, sr=1.5, foot=6, hipx=2.3, chest=0)


# ================================================================== fichas (kit)
SS2 = {}

SS2['rival'] = dict(
    name='Madame Glint', species='human_f', body=dict(h=61), skin='#f2cdb2', hc='#38b2ae', eyes='#3a6a8a',
    stance='easy_f', turn=0.5, stance_mod=dict(lean=0.5),
    face=dict(eye='soft', mouth='small', blush=True, brow='thin'), blush_col='#e8908a', mouth_col='#c05a6a',
    hair=dict(kind='short', bangs='swept', locks=0, volume=1.1),
    back=[(beehive, {})],
    top=dict(kind='dress', mat='coat', length='knee', flare=0.45, folds=2, trim='chrome', front='chrome', neck='collar',
             neck_mat='coat'),
    sleeves=dict(kind='long', mat='coat', cuff='chrome'),
    legs=dict(kind='tights', mat='tights'), feet=dict(kind='boots', mat='wboots', h=0.7),
    over=[(loupe_chain, dict(mat='chrome', lens='lens'))],
    head=[(star_clip, dict(mat='chrome'))],
    arms={'n': 'waist', 'f': 'hip'}, near=[(star_bag, dict(mat='bag', trim='chrome'))], free_walk=('f',),
    accent=('coat', 'bag'),
    mats={'coat': ('#f4927a', 'gem'), 'chrome': ('#dfe3ec', 'metal'), 'tights': '#c8a8b0', 'wboots': ('#f4f0ea', 'white'),
          'bag': ('#e86a8a', 'gem'), 'lens': ('#9ad0e0', 'gem')},
)

SS2['inspector'] = dict(
    name='Inspector Tolle', species='human_f', body=dict(h=58), skin='#ecc2a0', hc='#9a4428', eyes='#5a6a3a',
    stance='prim', turn=0.45,
    face=dict(eye='calm', mouth='small', brow='thin'),
    hair=dict(kind='short', bangs='parted', locks=0, bun=True, bun_x=0.8, bun_y=4.0, bun_r=3.6, volume=1.0),
    top=dict(kind='dress', mat='coat', length='knee', flare=0.30, folds=2, trim='coat2', front='brass', neck='high',
             neck_mat='cream'),
    sleeves=dict(kind='long', mat='coat', cuff='coat2'),
    legs=dict(kind='tights', mat='tights'), feet=dict(kind='shoes', mat='shoes'),
    gloves='glove',
    over=[(sash, dict(mat='sash', tail=False))],
    head=[(glasses, dict(mat='brass')), (pillbox, dict(mat='hat', band='hat2', mark='stamp'))],
    arms={'n': 'staff', 'f': 'book'}, far_front=True,
    near=[(furled_parasol, dict(mat='canopy', band='canopy2', pole='pole'))],
    far=[(ledger, dict(cover='ledger', page='page', clasp='brass'))],
    accent=('coat',),
    mats={'coat': ('#c8982e', 'cloth'), 'coat2': ('#9a7020', 'cloth'), 'cream': ('#efe4c8', 'white'), 'sash': ('#ece0c0', 'white'),
          'glove': ('#efe6cc', 'white'), 'brass': ('#d4a64a', 'metal'), 'tights': '#5a4a40', 'shoes': ('#4a3428', 'leather'),
          'canopy': '#3e8a86', 'canopy2': '#2e6664', 'pole': ('#6a4a36', 'leather'), 'hat': ('#3e8a86', 'cloth'),
          'hat2': ('#c8982e', 'cloth'), 'ink': ('#2a2024', 'flat'), 'stamp': ('#efe4c8', 'flat'), 'ledger': ('#6a3a2a', 'leather'), 'page': ('#efe4c8', 'white'),
          'frame': ('#c99d48', 'metal')},
)

SS2['singer'] = dict(
    name='Lune', species='lampwing', skin='#d8cce0', hc='#3a3640', eyes='#2a2236', tex={'skin': 'fur'},
    stance='prim', turn=0.45,
    face=dict(eye='none', mouth='tiny', nose=False, blush=False), mouth_col='#9a6a8a',
    hair=dict(kind='none', bangs='none', locks=0),
    back=[(moth_wings_back, dict(mat='wing2', edge='wing3'))],
    top=dict(kind='dress', mat='coat', length='floor', flare=0.55, folds=3, trim='coat2', neck='high', neck_mat='coat'),
    sleeves=dict(kind='long', mat='coat', cuff='coat2'),
    legs=dict(kind='pants', mat='coat'), feet=dict(kind='shoes', mat='shoes'),
    over=[(moth_wing_shawl, dict(mat='wing', band='wing3', dot='wing4')), (fur_collar, dict(mat='ruff'))],
    face_acc=[(moth_eyes, dict(mat='eyedark'))],
    head=[(moth_fuzz, dict(mat='ruff')), (antennae, dict(mat='antenna', vane='antenna2'))],
    arms={'n': 'clasp', 'f': 'clasp'}, far_front=True,
    post=[(sequins, dict(mat='sequin'))],
    accent=('wing',),
    mats={'coat': '#4a2e58', 'coat2': '#6a4a7a', 'shoes': ('#3a2a34', 'leather'), 'wing': ('#e09aaa', 'gem'), 'wing2': ('#b4a0dc', 'gem'),
          'wing3': ('#f0dcc8', 'white'), 'wing4': '#9a6a8a', 'ruff': ('#f2e6cc', 'white'), 'antenna': ('#f4ead4', 'flat'),
          'antenna2': ('#a8906a', 'flat'),
          'eyedark': ('#2a1e30', 'flat'), 'eyelit': ('#5a4a6a', 'flat'), 'sequin': ('#f4e0f0', 'flat')},
)

SS2['tracker'] = dict(
    name='Warden Brisk', species='brushtail', skin='#c8743a', hc='#c8743a', eyes='#2e1e16', tex={'skin': 'fur'},
    stance='step', turn=0.5, stance_mod=dict(lean=0.5),
    face=dict(eye='man', mouth=None, nose=False, blush=False),
    hair=dict(kind='none', bangs='none', locks=0),
    back=[(tail, dict(kind='wolf', mat='skin', tip='tailtip'))],
    top=dict(kind='dress', mat='coat', length='knee', flare=0.32, folds=2, trim='coat2', front='coat2', neck='v'),
    sleeves=dict(kind='long', mat='coat', cuff='coat2'),
    legs=dict(kind='pants', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.7),
    over=[(belt, dict(mat='belt', buckle='brass')), (cable_coil, dict(mat='cable', band='cable2')),
          (strap_bag, dict(mat='bag', strap='strap2', flap='bag2')), (scarf, dict(mat='scarf', tail=True)),
          (badge, dict(mat='brass'))],
    head=[(fox_snout, dict(mat='muzzle', nose='nose')), (fox_ears, dict(mat='skin', inner='inner', tip='eartip')),
          (goggles_up, dict(mat='brass', lens='glens'))],
    arms={'n': 'chest', 'f': 'front'}, near=[(clipboard, dict(board='board', paper='page', clip='steel'))],
    accent=('scarf',),
    mats={'coat': '#3e6a72', 'coat2': '#2c4c54', 'pants': '#4a3e36', 'boots': ('#3e2e26', 'leather'), 'belt': ('#5a4030', 'leather'),
          'bag': ('#8a5a3a', 'leather'), 'bag2': ('#6a4430', 'leather'), 'strap2': ('#4a3428', 'leather'),
          'scarf': '#7a3a62', 'muzzle': ('#f0e2c8', 'white'), 'nose': ('#2a2024', 'leather'), 'inner': '#3a2a2a',
          'eartip': ('#3a2a2a', 'leather'), 'tailtip': ('#f0e2c8', 'white'), 'brass': ('#d4a64a', 'metal'),
          'glens': ('#6ab8c0', 'gem'), 'cable': ('#3a3438', 'leather'), 'cable2': '#d8702e', 'board': ('#8a6040', 'leather'),
          'page': ('#efe4c8', 'white'), 'ink': ('#2a2024', 'flat'), 'steel': ('#a4a8b4', 'metal')},
)

for _sp in SS2.values():
    _sp.setdefault('mute_s', 0.74)
    _sp.setdefault('mute_v', 0.92)


# ================================================================== robots y la Sandglass (a mano, sobre el lienzo)

SIFT_MATS = {
    'brass': ('#d4a64a', 'metal'), 'brass2': ('#a87a34', 'metal'), 'glass': ('#c8e2e6', 'gem'), 'sand': ('#e6b85a', 'flat'),
    'sand2': ('#c8923a', 'flat'), 'eyed': ('#2a2024', 'flat'), 'lace': ('#efe4c8', 'white'), 'iron': ('#5c5660', 'metal'),
}


def draw_sift(kind='idle', i=0):
    """Madam Sift mirando a la derecha: reloj de arena de ~62 px con su marco de bronce."""
    pal, kinds = pal_of(SIFT_MATS, accents=('sand',))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    if kind == 'idle':
        bob = [0, 1][i]
        feet = ((0, 0), (0, 0))
        trick = i
    else:
        bob = [0, -1, 0, -1][i]
        feet = [((2, 0), (-2, 1)), ((0, 0), (0, 2)), ((-2, 1), (2, 0)), ((0, 2), (0, 0))][i]
        trick = i % 2
    cx = 32.0
    yb = G - 6 + bob          # fila de abajo del plato de la base
    # patitas de bronce (la lejana detrás)
    for side, (dx, lift), x0, bias in (('f', feet[1], cx + 5.0, -0.6), ('n', feet[0], cx - 5.0, 0.0)):
        fx = x0 + dx
        m, n = cv.capsule_n((fx, yb), (fx, G - 2 - lift), 1.4, 1.3)
        cv.put(m, 'brass2', mode='stroke', nrm=n, iline=side == 'n', bias=bias)
        cv.put(cv.ellipse(fx + 0.8, G - 1 - lift - (0 if side == 'n' else 1), 2.6, 1.2), 'brass2', mode='cyl', iline=side == 'n', bias=bias)
    # poste lejano del marco (detrás de las ampollas)
    top_y = yb - 50
    cv.put(cv.rect(int(cx + 6), int(top_y + 2), int(cx + 7), int(yb - 1)), 'brass2', mode='cyl', bias=-0.7)
    # ampolla de abajo (la falda) con su montoncito de arena
    lo = cv.ellipse(cx, yb - 12.0, 11.0, 12.0) & (cv.ys <= yb - 1)
    pl = cv.put(lo, 'glass', mode='shine', cast=1, iline=True)
    cv.set_nrm(pl, cv.sphere_n(cx - 4.0, yb - 16.0, 12.0, 13.0, k=0.9))
    pile = lo & (cv.ys >= yb - 9 + abs(cv.xs - cx) * 0.45 - trick * 0.4)
    cv.paint(pile, 'sand', 2)
    cv.paint(pile & (cv.ys >= yb - 4), 'sand2', 2)
    # el cuello angosto
    neck_y = yb - 24.0
    cv.put(cv.rect(int(cx - 2), int(neck_y - 1), int(cx + 2), int(neck_y + 1)), 'glass', mode='cyl', iline=True)
    # ampolla de arriba (cabeza y pecho) con la arena y los ojos
    up = cv.ellipse(cx, neck_y - 11.5, 10.6, 11.6) & (cv.ys >= top_y + 4)
    pu = cv.put(up, 'glass', mode='shine', cast=1, iline=True)
    cv.set_nrm(pu, cv.sphere_n(cx - 4.0, neck_y - 16.0, 12.0, 13.0, k=0.9))
    level = neck_y - 15.0 + trick * 0.5
    sand_up = up & (cv.ys >= level + np.abs(cv.xs - cx) * 0.15)
    cv.paint(sand_up, 'sand', 2)
    cv.paint(sand_up & (cv.ys >= neck_y - 5), 'sand2', 2)
    for ex in (cx - 1.5, cx + 3.5):
        cv.dot(ex, level + 3, 'eyed', 0)
        cv.dot(ex, level + 4, 'eyed', 0)
    # el chorrito de arena por el cuello (cambia de cuadro a cuadro)
    for k in range(5):
        y = int(neck_y + 1 + k * 2 + trick)
        if lo[min(y, 95), int(cx)] or abs(y - neck_y) < 2:
            cv.dot(cx, y, 'sand', 3)
    # brillos del vidrio
    for (x, y) in ((cx - 6, neck_y - 17), (cx - 7, neck_y - 15), (cx - 6, yb - 17), (cx - 7, yb - 15)):
        cv.dot(x, y, 'white', 4)
    # platos de bronce (arriba y abajo) y el poste cercano
    cv.put(cv.ellipse(cx, yb, 13.0, 2.4), 'brass', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(cx, top_y + 3, 10.4, 2.0), 'brass', mode='shine', cast=1, iline=True)
    cv.put(cv.rect(int(cx - 11), int(top_y + 3), int(cx - 10), int(yb - 1)), 'brass', mode='cyl', cast=1, iline=True)
    # el gorrito de bronce (un tambor bajo) arriba
    cv.put(cv.rect(int(cx - 4), int(top_y - 4), int(cx + 4), int(top_y + 1)), 'brass', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(cx, top_y - 4, 4.0, 1.0), 'brass', mode='top', iline=True)
    cv.paint(cv.rect(int(cx - 4), int(top_y - 1), int(cx + 4), int(top_y)), 'brass2', 2)
    # el cuellito de encaje (modales) y los bracitos finos de bronce (manos juntas adelante)
    cv.put(cv.ellipse(cx, neck_y + 0.5, 4.6, 1.6), 'lace', mode='cyl', iline=True)
    sw = 0.0 if kind == 'idle' else [-1.0, 0.0, 1.0, 0.0][i]
    for side, shx, bias in (('f', cx + 9.5, -0.6), ('n', cx - 9.5, 0.0)):
        sh = (shx, neck_y - 6.0)
        el = (shx + (2.5 if side == 'f' else -2.0) + sw * (1 if side == 'n' else -1), neck_y + 1.0)
        hd = (cx + (2.5 if side == 'f' else -1.0), neck_y + 5.5)
        _limb(cv, sh, el, 0.8, 0.8, 'brass', side == 'n', bias)
        _limb(cv, el, hd, 0.8, 0.8, 'brass', side == 'n', bias)
        _ball(cv, sh, 1.3, 'brass2', side == 'n', bias)
        _ball(cv, hd, 1.2, 'brass2', side == 'n', bias)
    return render(cv)


DOLLY_MATS = {
    'teal': ('#3a8a84', 'metal'), 'teal2': ('#2a6662', 'metal'), 'primer': ('#b45a36', 'cloth'), 'iron': ('#5c5660', 'metal'),
    'iron2': ('#3e3a42', 'metal'), 'rubber': ('#2e2a2c', 'leather'), 'hub': ('#a8acb6', 'metal'), 'lamp': ('#ffd36a', 'gem'),
    'lamprim': ('#d4a64a', 'metal'), 'stencil': ('#efe4c8', 'white'), 'hazard': ('#e0b040', 'cloth'), 'hazard2': ('#2e2a2c', 'leather'),
    'steel': ('#a8acb6', 'metal'),
}


def draw_dolly(i=0):
    """Dolly mirando a la derecha: cuerpo bajo y ancho sobre 4 ruedas, y adelante el MÁSTIL del montacargas (un marco de
    dos rieles anchos con travesaños, pegado al cuerpo, no un cuello): su cara pintada en el travesaño de arriba (dos
    faros redondos y una sonrisa de plantilla), entre los rieles que siguen un poco más arriba; dos brazos fuertes y
    las uñas abajo. Dos cuadros quietos (la suspensión respira, los faros parpadean)."""
    pal, kinds = pal_of(DOLLY_MATS, accents=('teal', 'lamp', 'hazard'))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    bob = [0, 1][i]
    # ruedas lejanas (detrás, más oscuras)
    for x in (19.0, 37.0):
        cv.put(cv.ellipse(x + 2.0, G - 6.0, 6.0, 6.0), 'rubber', mode='shine', bias=-0.7)
    # el mástil: un marco ancho (dos rieles a 12 px) delante del cuerpo, del suelo hasta poco más arriba que el cuerpo
    x0, x1 = 41.0, 55.0          # bordes de afuera de los rieles
    top = 47.0 + bob             # arriba del marco (apenas 15 px sobre el cuerpo)
    pr_far = cv.put(cv.rect(int(x1 - 3), int(top - 2), int(x1), G - 3), 'iron', mode='cyl', cast=1, iline=True, bias=-0.4)
    # las uñas y el carro (abajo, hacia la derecha)
    cv.put(cv.rect(int(x0 + 1), G - 17, int(x1 + 1), G - 11), 'iron2', mode='cyl', cast=1, iline=True)
    for dy, bias in ((0, -0.5), (2, 0.0)):
        cv.put(cv.rect(int(x1 - 2), G - 6 + dy - 1, 63, G - 5 + dy - 1), 'steel', mode='shine', cast=1, iline=True, bias=bias)
    # el brazo lejano (detrás del cuerpo), agarrado al riel lejano
    sh_f = (37.0, 63.0 + bob)
    el_f = (43.0, 66.0 + bob)
    hd_f = (50.0, 63.0 + bob)
    _limb(cv, sh_f, el_f, 2.2, 2.0, 'teal2', False, -0.6)
    _limb(cv, el_f, hd_f, 2.0, 1.8, 'teal2', False, -0.6)
    _ball(cv, el_f, 2.3, 'iron', False, -0.6)
    # el cuerpo: bajo y ancho, con el contrapeso atrás (rayas de peligro)
    body = cv.rect(11, int(60 + bob), 42, int(82 + bob))
    body &= ~(cv.rect(11, int(60 + bob), 13, int(62 + bob)) & ~cv.ellipse(14, 63 + bob, 3.2, 3.2))
    pb = cv.put(body, 'teal', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(11, int(78 + bob), 42, int(82 + bob)) & cv.of(pb), 'teal2', 2)
    cw = cv.rect(5, int(62 + bob), 12, int(82 + bob))
    pcw = cv.put(cw, 'iron2', mode='cyl', cast=1, iline=True)
    for k in range(-4, 6):
        cv.paint(cv.line([(5 + k * 3, 82 + bob), (5 + k * 3 + 6, 62 + bob)]) & cv.of(pcw), 'hazard', 2)
    # pintura descascarada (imprimación) y remaches
    for (x, y, rx, ry) in ((17, 68, 2.0, 1.4), (33, 64, 1.6, 1.2), (37, 74, 1.8, 1.2), (24, 76, 1.2, 1.0)):
        cv.paint(cv.ellipse(x, y + bob, rx, ry) & cv.of(pb), 'primer', 2)
    for x in (15, 23, 31, 39):
        cv.dot(x, 62 + bob, 'teal2', 1)
    # la plantilla en el costado: una flecha hacia arriba (levantar), sin letras
    ax, ay = 26, 70 + bob
    for (x, y) in ((ax, ay - 3), (ax - 1, ay - 2), (ax + 1, ay - 2), (ax - 2, ay - 1), (ax + 2, ay - 1), (ax, ay - 2), (ax, ay - 1),
                   (ax, ay), (ax, ay + 1), (ax, ay + 2)):
        cv.dot(x, y, 'stencil', 3)
    # un caño de escape chiquito atrás
    cv.put(cv.rect(8, int(54 + bob), 10, int(61 + bob)), 'iron', mode='cyl', iline=True)
    # ruedas cercanas (gordas) con su cubo
    for x in (17.0, 35.0):
        cv.put(cv.ellipse(x, G - 6.0, 6.6, 6.6), 'rubber', mode='shine', cast=1, iline=True)
        cv.put(cv.ellipse(x, G - 6.0, 2.6, 2.6), 'hub', mode='shine', iline=True)
        for a in range(0, 360, 60):
            cv.dot(x + math.cos(math.radians(a)) * 5.0, G - 6.0 + math.sin(math.radians(a)) * 5.0, 'iron2', 1)
    # el riel cercano, el travesaño de abajo y el de arriba (con la cara pintada)
    cv.put(cv.rect(int(x0), int(top - 2), int(x0 + 3), G - 3), 'iron', mode='cyl', cast=1, iline=True)
    cv.put(cv.rect(int(x0 + 3), int(top + 18), int(x1 - 3), int(top + 20)), 'iron2', mode='cyl', iline=True)
    # el pistón del montacargas entre los rieles (de la viga de abajo a la de arriba)
    cv.put(cv.rect(int(x0 + 6), int(top + 9), int(x0 + 8), int(top + 18)), 'steel', mode='shine', iline=True)
    # la viga de arriba: más ancha que el mástil (una viga, no una cabeza), con los pernos de los rieles y la cara
    beam = cv.rect(int(x0 - 2), int(top), int(x1 + 2), int(top + 8))
    pch = cv.put(beam, 'teal', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(int(x0 - 2), int(top + 7), int(x1 + 2), int(top + 8)) & cv.of(pch), 'teal2', 2)
    cv.paint(cv.rect(int(x0 + 6), int(top), int(x0 + 9), int(top + 1)) & cv.of(pch), 'primer', 2)
    for bx in (x0 - 0.5, x1 + 0.5):
        cv.dot(bx, top + 4, 'iron2', 1)
    for lx in (x0 + 3.5, x0 + 10.5):
        cv.put(cv.ellipse(lx, top + 3.5, 2.2, 2.2), 'lamprim', mode='shine', iline=True)
        cv.put(cv.ellipse(lx, top + 3.5, 1.3, 1.3), 'lamp', mode='shine')
        cv.dot(lx - 0.6, top + 2.8, 'white', 4 if i == 0 else 3)
    for (x, y) in ((x0 + 5, top + 6), (x0 + 6, top + 7), (x0 + 7, top + 7), (x0 + 8, top + 7), (x0 + 9, top + 6)):
        cv.dot(x, y, 'stencil', 3)
    # el brazo cercano: fuerte, la pinza agarrada al riel cercano
    sh_n = (20.0, 64.0 + bob)
    el_n = (28.0, 71.0 + bob)
    hd_n = (39.0, 67.0 + bob)
    _limb(cv, sh_n, el_n, 2.4, 2.2, 'teal', True)
    _limb(cv, el_n, hd_n, 2.2, 2.0, 'teal', True)
    _ball(cv, sh_n, 2.8, 'iron', True)
    _ball(cv, el_n, 2.4, 'iron', True)
    cv.put(cv.ellipse(hd_n[0] + 1.0, hd_n[1], 2.6, 2.2), 'iron2', mode='shine', iline=True)
    return render(cv)


SEVEN_MATS = {
    'enamel': ('#2f6a4c', 'metal'), 'enamel2': ('#1f4a36', 'metal'), 'stripe': ('#e8e4d8', 'white'), 'salt': ('#f0ece0', 'flat'),
    'sandy': ('#c8a46a', 'cloth'), 'patch': ('#4a8a68', 'metal'), 'iron': ('#5c5660', 'metal'), 'iron2': ('#3e3a42', 'metal'),
    'brass': ('#d4a64a', 'metal'), 'bulb': ('#ffd36a', 'flat'), 'glowring': ('#f4b84a', 'flat'), 'roof': ('#a8442e', 'metal'),
    'cloth': ('#b89a6a', 'cloth'), 'cloth2': ('#9a7e54', 'cloth'), 'clothp': ('#7a8a6a', 'cloth'), 'stitch': ('#4a3a2a', 'flat'),
    'wood': ('#7a5236', 'leather'), 'glass': ('#c8e2e6', 'gem'), 'rubber': ('#2e2a2c', 'leather'), 'ink': ('#2a2024', 'flat'),
}


def draw_seven(kind='idle', i=0):
    """Old Seven mirando a la derecha: un faro que camina, apoyado en un cayado con un farol colgando."""
    pal, kinds = pal_of(SEVEN_MATS, accents=('bulb', 'roof'))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    if kind == 'idle':
        bob = [0, 1][i]
        feet = ((-1.5, 0), (2.5, 0))
        swing = [0.0, 0.5][i]
    else:
        bob = [0, -1, 0, -1][i]
        feet = [((3.0, 0), (-3.0, 2)), ((0.0, 0), (1.0, 3)), ((-3.0, 2), (3.0, 0)), ((1.0, 3), (0.0, 0))][i]
        swing = [1.0, 0.0, -1.0, 0.0][i]
    cx = 30.0
    base_y = 80.0 + bob
    lean = 1.5            # se inclina un poco hacia el cayado (a la derecha)
    # el cayado (detrás del brazo cercano): del suelo hasta arriba, con el gancho y el farol
    sx = 52.0 + swing * 0.5
    staff = cv.capsule((sx - 1.0, G - 1.0), (sx, 18.0 + bob), 0.9, 0.9)
    hook = bez((sx, 18.0 + bob), (sx + 1.5, 11.0 + bob), (sx + 6.0, 13.5 + bob), 8)
    cv.put(staff | cv.stroke(hook, 0.9, 0.8), 'wood', mode='shine', cast=1, iline=True)
    lx, ly = sx + 6.0 + swing * 0.8, 21.0 + bob
    cv.paint(cv.line([(sx + 6.0, 14.5 + bob), (lx, ly - 3)]), 'iron2', 2)
    cv.put(cv.rect(int(lx - 2), int(ly - 2), int(lx + 2), int(ly + 3)), 'glass', mode='shine', iline=True)
    cv.put(cv.rect(int(lx - 2), int(ly - 3), int(lx + 2), int(ly - 2)), 'iron', mode='cyl', iline=True)
    cv.put(cv.rect(int(lx - 1), int(ly), int(lx + 1), int(ly + 1)), 'bulb', mode='flat')
    # piernas cortas y fuertes con pies anchos (la lejana detrás)
    for side, (dx, lift), x0, bias in (('f', feet[1], cx + 4.0, -0.6), ('n', feet[0], cx - 3.5, 0.0)):
        fx = x0 + dx
        m, n = cv.capsule_n((x0, base_y + 1.0), (fx, G - 3.0 - lift), 2.4, 2.2)
        cv.put(m, 'iron', mode='stroke', nrm=n, iline=side == 'n', bias=bias)
        cv.put(cv.ellipse(fx + 1.0, G - 1.5 - lift - (0 if side == 'n' else 1), 4.0, 1.8), 'rubber', mode='cyl', iline=side == 'n', bias=bias)
    # el brazo lejano (detrás de la torre)
    sh_f = (cx + 6.0 + lean, 40.0 + bob)
    el_f = (cx + 8.0 + lean, 47.0 + bob)
    hd_f = (cx + 7.0 + lean - swing, 53.0 + bob)
    _limb(cv, sh_f, el_f, 1.8, 1.6, 'enamel2', False, -0.6)
    _limb(cv, el_f, hd_f, 1.6, 1.5, 'enamel2', False, -0.6)
    # la base (zócalo ensanchado) y la torre ahusada
    plinth = cv.poly([(cx - 12.0, base_y), (cx + 12.0, base_y), (cx + 10.0, base_y - 4.0), (cx - 10.0, base_y - 4.0)])
    cv.put(plinth, 'enamel2', mode='cyl', cast=1, iline=True)
    top_y = 30.0 + bob
    tower = cv.poly([(cx - 9.5, base_y - 4.0), (cx + 9.5, base_y - 4.0), (cx + 6.5 + lean, top_y), (cx - 6.5 + lean, top_y)])
    pt = cv.put(tower, 'enamel', mode='cyl', cast=1, iline=True)
    # la franja blanca
    band = tower & (cv.ys >= 52 + bob) & (cv.ys <= 58 + bob)
    cv.paint(band, 'stripe', 2)
    # un "7" de plantilla en la franja (un número, no letras)
    sx7, sy7 = int(cx - 1 + lean * 0.5), 53 + bob
    for (x, y) in ((sx7, sy7), (sx7 + 1, sy7), (sx7 + 2, sy7), (sx7 + 2, sy7 + 1), (sx7 + 1, sy7 + 2), (sx7 + 1, sy7 + 3)):
        cv.dot(x, y, 'ink', 1)
    # ojo de buey, parches de pintura, costra de sal y arena abajo
    cv.put(cv.ellipse(cx + 1.0 + lean * 0.6, 66.0 + bob, 2.6, 2.6), 'brass', mode='shine', iline=True)
    cv.put(cv.ellipse(cx + 1.0 + lean * 0.6, 66.0 + bob, 1.4, 1.4), 'iron2', mode='flat')
    for (x, y, rx, ry) in ((cx - 5.0, 62.0, 2.0, 2.6), (cx + 4.0, 44.0, 1.6, 2.0)):
        cv.paint(cv.ellipse(x, y + bob, rx, ry) & cv.of(pt), 'patch', 2)
    for (x, y) in ((cx - 7, 72), (cx - 6, 74), (cx - 3, 73), (cx + 5, 71), (cx + 7, 74), (cx - 8, 70), (cx + 2, 75), (cx - 1, 70)):
        cv.dot(x, y + bob, 'salt', 4)
    cv.paint(tower & (cv.ys >= base_y - 7), 'sandy', 2)
    # el manto de lona remendado sobre los hombros (sin capucha)
    # (una esclavina corta sobre los hombros: corta adelante, larga atrás, a la izquierda; sin capucha)
    mt = cv.poly([(cx - 8.0 + lean, top_y + 1.0), (cx + 8.0 + lean, top_y + 1.0), (cx + 9.5 + lean, top_y + 6.5),
                  (cx + 4.0 + lean, top_y + 8.0), (cx - 4.0 + lean, top_y + 9.0), (cx - 9.5, top_y + 21.0 - swing * 0.5),
                  (cx - 12.5, top_y + 18.0 - swing * 0.5), (cx - 10.5 + lean, top_y + 6.0)])
    pm = cv.put(mt, 'cloth', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(int(cx - 12), int(top_y + 13), int(cx - 9), int(top_y + 16)) & cv.of(pm), 'clothp', 2)
    for (x, y) in ((cx - 12, top_y + 13), (cx - 9, top_y + 13), (cx - 12, top_y + 16), (cx - 9, top_y + 16)):
        cv.dot(x, y, 'stitch', 1)
    for k in range(3):
        cv.shade(cv.line([(cx - 6 + k * 5 + lean, top_y + 2), (cx - 8 + k * 5, top_y + 9 + (2 - k) * 3)]), -1, within=[pm])
    # la galería: plataforma y baranda (el "cuello")
    gy = top_y - 1.0
    cv.put(cv.ellipse(cx + lean, gy, 11.0, 2.0), 'iron', mode='shine', cast=1, iline=True)
    for k in range(-4, 5):
        x = cx + lean + k * 2.4
        cv.put(cv.rect(int(x), int(gy - 5), int(x), int(gy - 1)), 'iron2', mode='flat', iline=False)
    cv.put(cv.ellipse(cx + lean, gy - 5.0, 10.6, 1.2) & ~cv.ellipse(cx + lean, gy - 5.0, 9.4, 0.4), 'iron', mode='shine', iline=True)
    # la linterna (cabeza): jaula de barrotes con la bombita ámbar, sin ojos; techito cónico con su bolita
    hx = cx + lean + 0.5
    cage_top, cage_bot = gy - 18.0, gy - 6.0
    glow = cv.ellipse(hx, (cage_top + cage_bot) / 2, 5.6, 6.0)
    q = cv.put(glow, 'glowring', mode='flat', outline=False)
    cv.parts[q].keep = True
    bulbm = cv.ellipse(hx, (cage_top + cage_bot) / 2 + 0.5, 3.4, 4.0)
    q2 = cv.put(bulbm, 'bulb', mode='flat', outline=False)
    cv.parts[q2].keep = True
    for (x, y) in ((hx - 1, (cage_top + cage_bot) / 2), (hx, (cage_top + cage_bot) / 2 + 1)):
        cv.dot(x, y, 'white', 4)
    for k in (-6, -3, 0, 3, 6):
        cv.put(cv.rect(int(hx + k), int(cage_top), int(hx + k), int(cage_bot)), 'iron2', mode='flat', iline=False)
    cv.put(cv.rect(int(hx - 7), int(cage_bot), int(hx + 7), int(cage_bot + 1)), 'iron', mode='cyl', iline=True)
    cv.put(cv.rect(int(hx - 7), int(cage_top - 1), int(hx + 7), int(cage_top)), 'iron', mode='cyl', iline=True)
    roof = cv.poly([(hx - 8.0, cage_top - 1.0), (hx + 8.0, cage_top - 1.0), (hx + 0.5, cage_top - 8.0)])
    cv.put(roof, 'roof', mode='top', cast=1, iline=True)
    cv.put(cv.ellipse(hx + 0.5, cage_top - 8.5, 1.4, 1.4), 'brass', mode='shine', iline=True)
    # el brazo cercano: agarra el cayado
    sh_n = (cx - 6.0 + lean, 40.0 + bob)
    hd_n = (sx - 0.5, 47.0 + bob)
    el_n = (cx + 1.0 + lean, 50.0 + bob)
    _limb(cv, sh_n, el_n, 2.0, 1.8, 'enamel', True)
    _limb(cv, el_n, hd_n, 1.8, 1.7, 'enamel', True)
    _ball(cv, el_n, 2.0, 'iron', True)
    cv.put(cv.ellipse(hd_n[0], hd_n[1], 2.2, 2.4), 'iron2', mode='shine', iline=True)
    return render(cv)


# ================================================================== P1: Hesk, Buff, Thunk, Barb, Barrow

def hesk_face(cv, B, sp, pose, horn='horn', cap='brass', muzzle='muzzle', reed='reed'):
    """Cara de Hesk (Hornback): UN cuerno enroscado con la punta tapada de bronce (el otro, un muñón), la ceja pesada,
    la nariz chata y un junco en la boca."""
    _curl(cv, [(P(B, 6.5, 2.4), P(B, 2.0, -3.4), P(B, -5.0, -2.0), P(B, -5.4, 3.6)),
               (P(B, -5.4, 3.6), P(B, -5.6, 8.6), P(B, -1.0, 10.6), P(B, 0.6, 7.6))], 3.0, 1.0, horn, ring_at=0.62)
    cv.put(cv.ellipse(B.hx + 1.0, B.hy + 7.4, 2.0, 1.8), cap, mode='shine', iline=True)
    stub = cv.ellipse(B.hx + 16.0, B.hy + 1.6, 2.6, 2.2)
    cv.put(stub, horn, mode='top', cast=1, iline=True, bias=-0.4)
    brow = cv.stroke([P(B, 5.0, 6.0), P(B, 11.0, 5.2), P(B, 19.5, 5.4), P(B, 22.4, 6.4)], 1.4, 1.2)
    cv.put(brow, 'skin', mode='top', cast=2, iline=True)
    c = P(B, 18.6, 10.4)
    cv.put(cv.ellipse(c[0], c[1], 3.2, 2.0), 'skin', mode='soft', cast=1, iline=True)
    hm = cv.of(B.head_part)
    cv.paint(cv.ellipse(B.hx + 14.5, B.hy + 15.0, 7.0, 2.2) & hm, muzzle, 2)
    cv.paint(cv.line([P(B, 11.0, 14.2), P(B, 17.0, 13.8), P(B, 20.0, 14.0)]), 'mouth', 0)
    cv.put(cv.line([P(B, 19.0, 13.8), P(B, 25.0, 11.6)]), reed, mode='flat', iline=False)
    cv.dot(B.hx + 25.0, B.hy + 11.0, reed, 4)


SS2['dockmaster'] = dict(
    name='Dockmaster Hesk', species='hornback', skin='#7a8ca2', hc='#3a3640', eyes='#e8a840', stance='wide', turn=0.4,
    face=dict(eye='deep', mouth=None, blush=False, nose=False),
    hair=dict(kind='none', bangs='none', locks=0),
    top=dict(kind='dress', mat='coat', length='knee', flare=0.30, folds=2, trim='coat2', front='brass', neck='collar',
             neck_mat='coat2'),
    sleeves=dict(kind='long', mat='coat', cuff='brass'),
    legs=dict(kind='baggy', mat='pants'), feet=dict(kind='boots', mat='boots', h=0.45),
    back=[(back_horns, dict(mat='horn'))],
    over=[(belt, dict(mat='belt', buckle='brass', h=2))],
    head=[(hesk_face, dict(horn='horn', cap='brass', muzzle='muzzle', reed='reed'))],
    arms={'n': 'hip', 'f': 'hip'}, near=[(keyring, dict(mat='brass', tag='keytag'))],
    mats={'coat': '#2e3e66', 'coat2': '#202c4a', 'pants': '#4a4650', 'boots': ('#3a2e26', 'leather'), 'belt': ('#4a3428', 'leather'),
          'horn': ('#e2d4b2', 'white'), 'muzzle': ('#a4b0bc', 'skin'), 'brass': ('#d4a64a', 'metal'), 'reed': ('#c8b46a', 'flat'),
          'keytag': ('#c84a36', 'gem'), 'steel': ('#a4a8b4', 'metal')},
    mute_s=0.74, mute_v=0.92,
)

BUFF_MATS = {'chrome': ('#d8dce6', 'metal'), 'chrome2': ('#9aa0ae', 'metal'), 'mitt': ('#e8c87a', 'cloth'),
             'fluff': ('#f4ecd8', 'white'), 'fluff2': ('#d8ccb0', 'cloth'), 'rubber': ('#2e2a2c', 'leather'),
             'pink': ('#ec7ea0', 'cloth'), 'eyed': ('#2a2024', 'flat')}


def draw_buff(i=0):
    """Buff mirando a la derecha: flaco y vertical, una sola pata sobre una ruedita, cuello de cisne que termina en
    una rueda de pulir esponjosa (gira), manoplas de gamuza. Nunca una caja sobre una rueda; no habla."""
    pal, kinds = pal_of(BUFF_MATS, accents=('pink', 'mitt'))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    bob = [0, 1][i]
    cx = 30.0
    # la ruedita (rueda loca) y la horquilla
    cv.put(cv.ellipse(cx + 1.0, G - 3.0, 3.2, 3.2), 'rubber', mode='shine', cast=1, iline=True)
    cv.put(cv.rect(int(cx - 1), G - 9, int(cx + 2), G - 4), 'chrome2', mode='cyl', iline=True)
    # la pata: un caño fino
    cv.put(cv.rect(int(cx), int(58 + bob), int(cx + 1), G - 8), 'chrome', mode='cyl', iline=True)
    # el torso: una cápsula angosta y alta de cromo, con una franja rosa (los colores de Shine Again)
    tor = cv.capsule((cx + 0.5, 44.0 + bob), (cx + 0.5, 60.0 + bob), 4.2, 3.6)
    pt = cv.put(tor, 'chrome', mode='shine', cast=1, iline=True)
    cv.paint(cv.rect(int(cx - 4), int(51 + bob), int(cx + 5), int(52 + bob)) & cv.of(pt), 'pink', 2)
    # el brazo lejano
    _limb(cv, (cx + 3.0, 48.0 + bob), (cx + 6.0, 54.0 + bob), 0.8, 0.8, 'chrome2', False, -0.6)
    cv.put(cv.ellipse(cx + 6.5, 55.5 + bob, 1.8, 1.6), 'mitt', mode='soft', iline=True, bias=-0.4)
    # el cuello de cisne: sube, se curva hacia delante y baja hasta la rueda de pulir
    neck = bez3((cx + 1.0, 42.0 + bob), (cx + 0.0, 30.0 + bob), (cx + 10.0, 24.0 + bob), (cx + 13.0, 34.0 + bob), 14)
    m, n = cv.stroke_n(neck, 1.0)
    cv.put(m, 'chrome', mode='stroke', nrm=n, cast=1, iline=True)
    # dos ojitos en la curva del cuello (de pintura, sin luz)
    cv.dot(cx + 5.5, 26.5 + bob, 'eyed', 0)
    cv.dot(cx + 7.5, 26.5 + bob, 'eyed', 0)
    # la rueda de pulir esponjosa (gira: las rayas cambian de cuadro a cuadro)
    wc = (cx + 13.5, 38.0 + bob)
    wm = cv.ellipse(wc[0], wc[1], 4.4, 4.4)
    pw = cv.put(wm, 'fluff', mode='soft', cast=1, iline=True)
    for k in range(3):
        a = k * 2.1 + i * 0.9
        cv.shade(cv.line([wc, (wc[0] + math.cos(a) * 4.0, wc[1] + math.sin(a) * 4.0)]), -1, within=[pw])
    cv.put(cv.ellipse(wc[0], wc[1], 1.2, 1.2), 'chrome2', mode='shine', iline=True)
    # el brazo cercano con su manopla
    _limb(cv, (cx - 2.5, 48.0 + bob), (cx - 4.0, 55.0 + bob), 0.9, 0.9, 'chrome', True)
    cv.put(cv.ellipse(cx - 4.0, 57.0 + bob, 2.0, 1.8), 'mitt', mode='soft', iline=True)
    return render(cv)


THUNK_MATS = {'wood': ('#8a5a36', 'leather'), 'wood2': ('#6a4028', 'leather'), 'block': ('#c8982e', 'cloth'),
              'block2': ('#9a7020', 'cloth'), 'rubber': ('#b8402e', 'cloth'), 'spring': ('#a8acb6', 'metal'),
              'foot': ('#3e3a42', 'metal'), 'ink': ('#2a2024', 'flat'), 'eyed': ('#2a2024', 'flat')}


def draw_thunk(kind='idle', i=0):
    """Thunk mirando a la derecha: un sello de goma chiquito (mango de madera, bloque mostaza con la marca de conteo,
    goma roja) sobre dos patas de resorte. Salta en vez de caminar. Nunca una cajita negra con ruedas."""
    pal, kinds = pal_of(THUNK_MATS, accents=('rubber', 'block'))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    if kind == 'idle':
        lift = [0, 1][i]
        squash = [0, 1][i]
    else:
        lift = [0, 4, 6, 3][i]
        squash = [2, 0, 0, 0][i]
    cx = 31.0
    base = G - 8 - lift + squash
    # patas de resorte (zigzag) y pies
    for x, bias in ((cx + 3.0, -0.5), (cx - 3.0, 0.0)):
        pts = []
        y = G - 2 - lift
        k = 0
        while y > base + 1:
            pts.append((x + (1.2 if k % 2 else -1.2), y))
            y -= 1.6 - squash * 0.25
            k += 1
        pts.append((x, base + 1))
        cv.put(cv.line(pts), 'spring', mode='flat', iline=False, bias=bias)
        cv.put(cv.ellipse(x + 0.6, G - 1 - lift, 2.2, 1.0), 'foot', mode='cyl', iline=True, bias=bias)
    # la goma roja, el bloque y el mango
    cv.put(cv.rect(int(cx - 6), int(base - 2), int(cx + 6), int(base)), 'rubber', mode='cyl', cast=1, iline=True)
    pb = cv.put(cv.rect(int(cx - 5), int(base - 10), int(cx + 5), int(base - 2)), 'block', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(int(cx - 5), int(base - 4), int(cx + 5), int(base - 2)) & cv.of(pb), 'block2', 2)
    # la marca de conteo pintada (cuatro palotes y uno cruzado) y dos ojitos arriba
    for k in range(4):
        cv.dot(cx - 2 + k, base - 5, 'ink', 1)
        cv.dot(cx - 2 + k, base - 6, 'ink', 1)
    cv.dot(cx - 3, base - 5, 'ink', 1)
    cv.dot(cx + 2, base - 6, 'ink', 1)
    cv.dot(cx + 1, base - 8, 'eyed', 0)
    cv.dot(cx + 3, base - 8, 'eyed', 0)
    cv.put(cv.rect(int(cx - 1), int(base - 14), int(cx + 1), int(base - 10)), 'wood2', mode='cyl', iline=True)
    km = cv.ellipse(cx, base - 16.0, 3.2, 2.8)
    pk = cv.put(km, 'wood', mode='shine', cast=1, iline=True)
    cv.set_nrm(pk, cv.sphere_n(cx - 1.0, base - 17.0, 3.6, 3.2))
    return render(cv)


BARB_MATS = {'cactus': ('#5a8a4a', 'cloth'), 'cactus2': ('#3e6a38', 'cloth'), 'spine': ('#efe4c8', 'flat'),
             'straw': ('#d8b062', 'cloth'), 'band': ('#c84a36', 'cloth'), 'apron': ('#c8b080', 'cloth'),
             'apron2': ('#a08a5a', 'cloth'), 'seed': ('#6a4a30', 'flat'), 'bud': ('#ec7ea0', 'cloth'),
             'eyed': ('#2a2024', 'flat'), 'root': ('#7a5a3a', 'leather'), 'blush': ('#e8908a', 'flat')}


def draw_barb(kind='idle', i=0):
    """Barb (Thornfolk) mirando a la derecha: un cactus de barril bajito con sombrero de paja de ala ancha y delantal
    de semillas; un pimpollo rosa al costado. Sin cabeza alta y puntiaguda ni brazos de flor."""
    pal, kinds = pal_of(BARB_MATS, accents=('bud', 'band'))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    if kind == 'idle':
        bob = [0, 1][i]
        feet = ((0, 0), (0, 0))
    else:
        bob = [0, -1, 0, -1][i]
        feet = [((2, 0), (-2, 1)), ((0, 0), (0, 2)), ((-2, 1), (2, 0)), ((0, 2), (0, 0))][i]
    cx = 31.0
    yb = G - 5 + bob
    # piecitos de raíz
    for side, (dx, lift), x0, bias in (('f', feet[1], cx + 4.0, -0.6), ('n', feet[0], cx - 4.0, 0.0)):
        cv.put(cv.ellipse(x0 + dx, G - 2 - lift, 3.0, 2.0), 'root', mode='cyl', iline=side == 'n', bias=bias)
    # el barril (cuerpo y cabeza a la vez), con costillas
    body = cv.ellipse(cx, yb - 13.0, 11.0, 13.0)
    pb = cv.put(body, 'cactus', mode='shine', cast=1, iline=True)
    cv.set_nrm(pb, cv.sphere_n(cx - 3.0, yb - 17.0, 12.0, 14.0, k=0.85))
    for k in (-6, -2, 2, 6):
        cv.shade(cv.line([(cx + k * 0.9, yb - 25), (cx + k * 1.4, yb - 13), (cx + k * 0.9, yb - 1)]), -1, within=[pb])
    for (x, y) in ((cx - 8, yb - 16), (cx - 3, yb - 22), (cx + 3, yb - 20), (cx + 8, yb - 12), (cx - 9, yb - 8), (cx + 6, yb - 5)):
        cv.dot(x, y, 'spine', 4)
    # la carita (sin boca grande: dos ojos y un rubor)
    cv.dot(cx + 3, yb - 17, 'eyed', 0)
    cv.dot(cx + 3, yb - 16, 'eyed', 0)
    cv.dot(cx + 7, yb - 17, 'eyed', 0)
    cv.dot(cx + 7, yb - 16, 'eyed', 0)
    cv.dot(cx + 9, yb - 14, 'blush', 4)
    cv.dot(cx + 5, yb - 13, 'eyed', 1)
    # el delantal de semillas con bolsillos
    ap = cv.ellipse(cx, yb - 13.0, 11.0, 13.0) & (cv.ys >= yb - 10)
    pa = cv.put(ap, 'apron', mode='cyl', iline=True)
    for (x0, x1) in ((cx - 7, cx - 2), (cx + 1, cx + 6)):
        cv.paint(cv.rect(int(x0), int(yb - 7), int(x1), int(yb - 4)) & cv.of(pa), 'apron2', 2)
    for (x, y) in ((cx - 5, yb - 6), (cx + 3, yb - 6), (cx + 4, yb - 5)):
        cv.dot(x, y, 'seed', 1)
    # bracitos cortos y redondos (no son flores)
    for (x, y, bias) in ((cx - 11.0, yb - 13.0, 0.0), (cx + 11.0, yb - 15.0, -0.5)):
        cv.put(cv.ellipse(x, y, 2.4, 3.0), 'cactus', mode='soft', iline=True, bias=bias)
    # el pimpollo rosa al costado (se abre cuando le gusta un precio: el regateo lo dibuja aparte)
    cv.put(cv.ellipse(cx - 9.0, yb - 21.0, 1.8, 2.2), 'bud', mode='soft', iline=True)
    # el sombrero de paja de ala ancha con su cinta
    hy = yb - 25.0
    cv.put(cv.ellipse(cx, hy, 14.0, 2.6), 'straw', mode='top', cast=2, iline=True)
    crown = cv.ellipse(cx, hy - 2.0, 6.6, 4.0) & (cv.ys <= hy)
    cv.put(crown, 'straw', mode='top', cast=1, iline=True)
    cv.paint(cv.rect(int(cx - 6), int(hy - 1), int(cx + 6), int(hy)), 'band', 2)
    return render(cv)


BARROW_MATS = {'tray': ('#3a8a84', 'metal'), 'tray2': ('#2a6662', 'metal'), 'paint': ('#efe4c8', 'flat'),
               'iron': ('#5c5660', 'metal'), 'rubber': ('#2e2a2c', 'leather'), 'hub': ('#a8acb6', 'metal'),
               'wood': ('#8a5a36', 'leather'), 'flag': ('#d8702e', 'cloth'), 'grip': ('#3e3a42', 'leather'),
               'rust': ('#b45a36', 'cloth')}


def draw_barrow(kind='idle', i=0):
    """Barrow mirando a la derecha: una carretilla de verdad (la rueda adelante, la batea verde azulado, los dos
    mangos atrás que le hacen de patas), una cara pintada con el dedo en la batea y un banderín de repartos. Nunca
    amarillo; sin un ojo de cámara."""
    pal, kinds = pal_of(BARROW_MATS, accents=('tray', 'flag'))
    cv = Cv(pal, kinds=kinds)
    G = GROUND
    if kind == 'idle':
        bob = [0, 1][i]
        legs = ((0, 0), (0, 0))
        spin = i
    else:
        bob = [0, -1, 0, -1][i]
        legs = [((2, 0), (-2, 2)), ((0, 0), (0, 3)), ((-2, 2), (2, 0)), ((0, 3), (0, 0))][i]
        spin = i
    # los mangos-patas (atrás, a la izquierda): el lejano detrás
    for side, (dx, lift), x0, bias in (('f', legs[1], 18.0, -0.6), ('n', legs[0], 14.0, 0.0)):
        top = (x0 + 8.0, 72.0 + bob)
        foot = (x0 + dx, G - 2 - lift)
        cv.put(cv.capsule(top, foot, 1.1, 1.1), 'wood', mode='shine', iline=side == 'n', bias=bias)
        cv.put(cv.ellipse(foot[0], foot[1] + 0.5, 2.2, 1.2), 'grip', mode='cyl', iline=side == 'n', bias=bias)
    # el banderín de repartos (detrás de la batea)
    cv.put(cv.rect(22, int(52 + bob), 22, int(70 + bob)), 'iron', mode='flat', iline=False)
    fl = cv.poly([(23, 52 + bob), (31, 55 + bob + (i % 2)), (23, 58 + bob)])
    cv.put(fl, 'flag', mode='cyl', iline=True)
    # la batea: un trapecio verde azulado, con la boca arriba
    tray = cv.poly([(16, 66 + bob), (48, 64 + bob), (42, 80 + bob), (22, 80 + bob)])
    pt = cv.put(tray, 'tray', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(32.0, 65.0 + bob, 16.0, 2.0), 'tray2', mode='top', iline=True)
    cv.paint(cv.ellipse(27.0, 76.0 + bob, 2.0, 1.4) & cv.of(pt), 'rust', 2)
    # la cara pintada con el dedo: dos puntos y una sonrisa (pintura crema, sin ningún ojo de cámara)
    for (x, y) in ((33, 70), (38, 70), (32, 74), (33, 75), (34, 75), (35, 75), (36, 75), (37, 75), (38, 74)):
        cv.dot(x, y + bob, 'paint', 3)
    # la rueda adelante (a la derecha) con su eje
    cv.put(cv.rect(38, int(78 + bob), 46, int(80 + bob)), 'iron', mode='cyl', iline=True)
    wc = (46.0, G - 6.0)
    cv.put(cv.ellipse(wc[0], wc[1], 6.0, 6.0), 'rubber', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(wc[0], wc[1], 2.2, 2.2), 'hub', mode='shine', iline=True)
    for k in range(3):
        a = k * 2.09 + spin * 0.7
        cv.dot(wc[0] + math.cos(a) * 4.2, wc[1] + math.sin(a) * 4.2, 'iron', 1)
    return render(cv)


BOTS2 = {
    'timekeeper': lambda: ([draw_sift('idle', i) for i in range(2)], [draw_sift('walk', i) for i in range(4)]),
    # Dolly solo rueda: su hoja de caminar son sus dos cuadros quietos repetidos (actor.gd no cambia)
    'vendor': lambda: ([draw_dolly(i) for i in range(2)], [draw_dolly(i % 2) for i in range(4)]),
    'hermit': lambda: ([draw_seven('idle', i) for i in range(2)], [draw_seven('walk', i) for i in range(4)]),
    # P1
    'buffbot': lambda: ([draw_buff(i) for i in range(2)], [draw_buff(i % 2) for i in range(4)]),   # rueda, como Dolly
    'stampbot': lambda: ([draw_thunk('idle', i) for i in range(2)], [draw_thunk('walk', i) for i in range(4)]),
    'farmer': lambda: ([draw_barb('idle', i) for i in range(2)], [draw_barb('walk', i) for i in range(4)]),
    'porter': lambda: ([draw_barrow('idle', i) for i in range(2)], [draw_barrow('walk', i) for i in range(4)]),
}

ORDER2 = ['rival', 'vendor', 'inspector', 'hermit', 'singer', 'timekeeper', 'tracker']
ORDER2_P1 = ['dockmaster', 'buffbot', 'stampbot', 'farmer', 'porter']
TITLES2 = {
    'rival': ('Madame Glint', 'rival · Shine Again'), 'vendor': ('Dolly', 'fittings bot'),
    'inspector': ('Inspector Tolle', 'Tally Office'), 'hermit': ('Old Seven', 'lamp-keeper bot'),
    'singer': ('Lune', 'Lampwing singer'), 'timekeeper': ('Madam Sift', 'Sandglass'), 'tracker': ('Warden Brisk', 'Brushtail tracker'),
    'dockmaster': ('Dockmaster Hesk', 'Hornback'), 'buffbot': ('Buff', "Glint's bot"), 'stampbot': ('Thunk', "Tolle's stamp bot"),
    'farmer': ('Barb', 'Thornfolk farmer'), 'porter': ('Barrow', 'porter bot'),
}


def build_one(cid):
    if cid in BOTS2:
        return BOTS2[cid]()
    return frames(SS2[cid])


def build(ids, out):
    os.makedirs(os.path.join(out, 'chars'), exist_ok=True)
    res = {}
    for cid in ids:
        idle, walk = build_one(cid)
        Image.fromarray(np.concatenate(idle, axis=1), 'RGBA').save(os.path.join(out, 'chars', f'{cid}_idle.png'))
        Image.fromarray(np.concatenate(walk, axis=1), 'RGBA').save(os.path.join(out, 'chars', f'{cid}_walk.png'))
        res[cid] = (idle, walk)
    return res


def _frames_of(path, n):
    im = np.array(Image.open(path).convert('RGBA'))
    return [im[:, k * 64:(k + 1) * 64] for k in range(n)]


OLD = ['nell', 'kettle', 'gorrum', 'zib', 'oona', 'pipip', 'rook', 'clatter', 'raker', 'mags']
OLD_TITLES = {'nell': 'Nell', 'kettle': 'Kettle', 'gorrum': 'Gorrum', 'zib': 'Zib', 'oona': 'Mother Oona', 'pipip': 'Pipip',
              'rook': 'Rook Varga', 'clatter': 'Clatter', 'raker': 'Raker', 'mags': 'Mags'}


def cast_sheet(res, path, game_dir, scale=3):
    """La hoja del elenco: arriba el elenco nuevo (P0; y debajo los P1 si están) a x3 con nombre, la tira de caminar
    y los dos tamaños de juego (sobre arena y sobre madera); abajo el elenco de siempre, también a x3 (la misma escala:
    se ve que es el mismo estilo)."""
    from PIL import ImageDraw, ImageFont
    fdir = '/home/user/dead-air/caldero/game/assets/fonts'
    f_name = ImageFont.truetype(os.path.join(fdir, 'Alegreya-Bold.ttf'), 22)
    f_small = ImageFont.truetype(os.path.join(fdir, 'Alegreya-Medium.ttf'), 16)
    f_title = ImageFont.truetype(os.path.join(fdir, 'AlegreyaSC-Bold.ttf'), 30)
    cw, chh = 64 * scale, 96 * scale
    rows = [[i for i in ORDER2 if i in res], [i for i in ORDER2_P1 if i in res]]
    rows = [r for r in rows if r]
    old_step = 64 * scale - 50
    W = max(14 + 7 * (cw + 10) + 10, 14 + 10 * old_step + 60)
    block = chh + 70 + 80 + 110 + 20
    H = 60 + len(rows) * block + 40 + chh + 40
    im = Image.new('RGBA', (W, H), (46, 38, 34, 255))
    d = ImageDraw.Draw(im)
    d.text((14, 12), 'Secondhand Stars · round 2 · the new cast (x3) beside the old cast (x3)', font=f_title, fill=(240, 206, 140))
    y0 = 60
    for r, ids in enumerate(rows):
        if r == 1:
            d.text((W - 260, y0 - 30), 'P1 (extra sheets)', font=f_name, fill=(200, 180, 150))
        for k, cid in enumerate(ids):
            x = 14 + k * (cw + 10)
            d.rectangle((x, y0, x + cw - 1, y0 + chh - 1), fill=(64, 54, 48, 255))
            d.rectangle((x, y0 + chh - 14, x + cw - 1, y0 + chh - 1), fill=(84, 70, 58, 255))
            idle, walk = res[cid]
            im.alpha_composite(Image.fromarray(idle[0], 'RGBA').resize((cw, chh), Image.NEAREST), (x, y0))
            name, sub = TITLES2.get(cid, (cid, ''))
            d.text((x + 4, y0 + chh + 6), name, font=f_name, fill=(246, 232, 200))
            d.text((x + 4, y0 + chh + 34), sub, font=f_small, fill=(196, 176, 150))
            y1 = y0 + chh + 70
            for j, fr in enumerate(walk):
                sm = Image.fromarray(fr, 'RGBA').resize((48, 72), Image.NEAREST)
                im.alpha_composite(sm, (x + j * 48, y1))
            for j, bgc in enumerate(((214, 176, 120, 255), (70, 52, 40, 255))):
                xx = x + j * 70
                yy = y1 + 80
                d.rectangle((xx, yy, xx + 66, yy + 99), fill=bgc)
                im.alpha_composite(Image.fromarray(idle[0], 'RGBA'), (xx + 1, yy + 2))
        y0 += block
    y2 = y0
    d.text((14, y2 - 4), 'the cast so far (x3)', font=f_name, fill=(240, 206, 140))
    y2 += 28
    for k, cid in enumerate(OLD):
        p = os.path.join(game_dir, 'assets', 'chars', f'{cid}_idle.png')
        if not os.path.exists(p):
            continue
        fr = _frames_of(p, 2)[0]
        x = 14 + k * old_step
        im.alpha_composite(Image.fromarray(fr, 'RGBA').resize((64 * scale, 96 * scale), Image.NEAREST), (x, y2))
        d.text((x + 40, y2 + 96 * scale + 2), OLD_TITLES[cid], font=f_small, fill=(220, 204, 176))
    im = im.crop((0, 0, W, y2 + 96 * scale + 28))
    im.save(path)
    return path


if __name__ == '__main__':
    args = sys.argv[1:]
    out = './out'
    sheet = None
    game = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
    for flag in ('--out', '--sheet', '--game'):
        if flag in args:
            k = args.index(flag)
            val = args[k + 1]
            del args[k:k + 2]
            if flag == '--out':
                out = val
            elif flag == '--sheet':
                sheet = val
            else:
                game = val
    ids = args or (ORDER2 + ORDER2_P1)
    res = build(ids, out)
    if sheet:
        cast_sheet(res, sheet, game)
    print('ok', ids)
