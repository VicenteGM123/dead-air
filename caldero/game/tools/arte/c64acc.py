"""Sombreros, cascos y objetos (bastones, armas, cestas...) para el generador 64x96."""
import math
import numpy as np
from c64core import *
from c64body import GROUND

HW, HH = 18.0, 20.0   # cabeza de referencia (coordenadas de hp)
from c64parts import hp, ha, hem_trim, folds


# ------------------------------------------------------------------ cabeza

def witch_hat(cv, B, sp, pose, mat='hat', band='band', h=17.0, brim=12.5, bend=-6.0, deco=None, droop=1.5, crown_w=11.5,
              brim_cast=2):
    hw = B.head['w']
    bx = B.hx + hw / 2 + 0.5
    by = B.hy + sp.get('hair', {}).get('hairline', 5.0) - 2.2
    lag = pose.lag
    sway = pose.sway
    tip = (bx + bend + sway * 0.8, by - h + lag * 0.6)
    pts = [(bx - crown_w / 2, by + 0.5), (bx - crown_w * 0.36, by - h * 0.42), (bx - crown_w * 0.15 + bend * 0.35, by - h * 0.78),
           tip, (bx + crown_w * 0.05 + bend * 0.2, by - h * 0.70), (bx + crown_w * 0.28, by - h * 0.40), (bx + crown_w / 2, by + 0.5)]
    crown = cv.put(cv.poly(pts), mat, mode='rim', cast=1, band=0.32)
    # pliegue de la punta
    cv.shade(cv.line([(bx - crown_w * 0.05, by - h * 0.45), (bx + bend * 0.5, by - h * 0.82)]), -1, within=[crown])
    if band:
        bm = cv.poly(pts) & (cv.ys >= int(by - 2.5)) & (cv.ys <= int(by - 0.5))
        cv.put(bm, band, mode='shine')
    b = cv.poly([(bx - brim, by + droop), (bx - brim * 0.6, by - 0.6), (bx, by - 1.4), (bx + brim * 0.65, by - 0.8), (bx + brim + 0.5, by + 0.5),
                 (bx + brim * 0.6, by + 2.0), (bx, by + 2.3), (bx - brim * 0.6, by + droop + 1.6)])
    pb = cv.put(b, mat, mode='top', cast=brim_cast, iline=True, band=0.2)
    if deco:
        deco(cv, bx, by)
    return crown


def leaf_sprig(mat_leaf='leaf', mat_berry=None):
    def f(cv, bx, by):
        for (x, y) in ((bx + 3.5, by - 2.5), (bx + 4.5, by - 3.5), (bx + 5.5, by - 3.0), (bx + 3.0, by - 4.0)):
            cv.put(cv.ellipse(x, y, 1.0, 0.8), mat_leaf, mode='top')
        if mat_berry:
            cv.put(cv.ellipse(bx + 2.5, by - 1.8, 0.8, 0.8), mat_berry, mode='shine')
    return f


def straw_hat(cv, B, sp, pose, mat='straw', band='band', brim=11.5, h=5.5):
    hw = B.head['w']
    bx = B.hx + hw / 2 + 0.8
    by = B.hy + 3.6
    crown = cv.poly([(bx - 5.8, by), (bx - 5.0, by - h + 0.5), (bx - 2.5, by - h), (bx + 3.0, by - h), (bx + 5.2, by - h + 0.8), (bx + 5.8, by)])
    pc = cv.put(crown, mat, mode='rim', cast=1)
    if band:
        cv.put(crown & (cv.ys >= int(by - 2)), band, mode='cyl')
    b = cv.ellipse(bx, by + 0.6, brim, 2.3)
    pb = cv.put(b, mat, mode='top', cast=2, iline=True, band=0.2)
    # trama
    cv.shade(b & ((cv.xs + cv.ys) % 3 == 0) & (cv.ys > by), -1, within=[pb])
    cv.shade(crown & ((cv.xs - cv.ys) % 3 == 0), -1, within=[pc])
    return pc


def kerchief(cv, B, sp, pose, mat='kerchief', dots=None, knot=True):
    hw = B.head['w']
    m = cv.ellipse(B.hx + hw / 2 - 0.8, B.hy + 5.0, hw / 2 + 1.4, 7.0) & (cv.ys <= B.hy + 6.5)
    m |= cv.poly([hp(B, -1.0, 4.0), hp(B, 3.0, 4.0), hp(B, 2.5, 9.5), hp(B, -1.5, 9.0)])
    p = cv.put(m, mat, mode='top', cast=1, iline=True)
    if dots:
        cv.paint(m & (cv.xs % 3 == 0) & (cv.ys % 3 == 1), dots, 3)
    if knot:
        lag = pose.lag
        k = cv.poly([hp(B, -0.5, 7.0), hp(B, -4.5 + pose.sway, 9.0 + lag), hp(B, -3.5 + pose.sway, 12.0 + lag), hp(B, 0.5, 9.5)])
        cv.put(k, mat, mode='cyl', iline=True)
    return p


def veil(cv, B, sp, pose, mat='veil', band=None, length=20):
    """Toca y velo de sacerdotisa."""
    hw = B.head['w']
    lag, sway = pose.lag, pose.sway
    back = cv.poly([hp(B, 2.0, -1.5), hp(B, 9.0, -2.0), hp(B, HW + 0.5, 3.0), hp(B, 5.0, 4.0), hp(B, 3.5, 12.0),
                    hp(B, 1.0 + sway * 0.5, length + lag), hp(B, -4.5 + sway * 1.5, length - 1 + lag), hp(B, -3.0, 6.0)])
    pv = cv.put(back, mat, mode='top', cast=1, iline=True, band=0.25)
    folds(cv, pv, B, B.hy + 8, B.hy + length - 2, [(B.hx - 1, B.hx - 3 + sway), (B.hx + 1.5, B.hx + 0.5 + sway)], lag)
    if band:
        bm = cv.poly([hp(B, 3.5, 2.5), hp(B, HW + 0.8, 1.5), hp(B, HW + 0.8, 3.3), hp(B, 4.0, 4.5)])
        cv.put(bm, band, mode='flat')
    return pv


def hood(cv, B, sp, pose, mat='hood', part='front'):
    hw, hh = B.head['w'], B.head['h']
    lag, sway = pose.lag, pose.sway
    if part == 'back':
        m = cv.poly([hp(B, -3.5, 4.0), hp(B, 3.0, -2.5), hp(B, 10.0, -3.0), hp(B, HW + 1.5, 2.0), hp(B, HW + 0.5, 12.0),
                     hp(B, HW - 2.0, HH + 1.0), hp(B, -1.0 + sway, HH + 3.0 + lag), hp(B, -4.0 + sway, 10.0)])
        return cv.put(m, mat, mode='top', cast=0)
    # borde de la capucha que enmarca la cara
    m = cv.poly([hp(B, 1.0, 2.0), hp(B, 5.0, -2.0), hp(B, 11.0, -2.3), hp(B, HW + 1.5, 1.5), hp(B, HW + 1.2, 5.5),
                 hp(B, HW - 2.0, 3.5), hp(B, 8.0, 3.0), hp(B, 5.0, 5.0), hp(B, 4.0, 12.0), hp(B, 4.6, HH + 0.5),
                 hp(B, 1.0, HH + 1.0), hp(B, -1.5, 10.0)])
    p = cv.put(m, mat, mode='top', cast=2, iline=True, band=0.25)
    cv.shade(cv.line([hp(B, 3.5, 3.0), hp(B, 2.5, HH - 1.0)]), -1, within=[p])
    return p


def helmet(cv, B, sp, pose, mat='steel', kind='dwarf', plume=None, trim=None):
    hw, hh = B.head['w'], B.head['h']
    if kind == 'dwarf':
        dome = cv.ellipse(B.hx + hw / 2, B.hy + 5.5, hw / 2 + 1.5, 7.0) & (cv.ys <= B.hy + 6.5)
        p = cv.put(dome, mat, mode='shine', cast=2, iline=True)
        rim = cv.rect(B.hx - 1, B.hy + 5, B.hx + hw + 1, B.hy + 6)
        cv.put(rim & cv.ellipse(B.hx + hw / 2, B.hy + 5.5, hw / 2 + 2.0, 8.0), trim or mat, mode='shine', cast=1)
        nose = cv.rect(B.hx + 11, B.hy + 6, B.hx + 11, B.hy + 10)
        cv.put(nose, trim or mat, mode='shine', cast=1)
        # remaches
        for x in (3, 7, 11):
            cv.dot(B.hx + x, B.hy + 5, mat, 4)
        return p
    if kind == 'kettle':
        # casco de guardia: ala ancha de acero
        dome = cv.ellipse(B.hx + hw / 2, B.hy + 4.5, hw / 2 + 0.8, 6.5) & (cv.ys <= B.hy + 5.0)
        p = cv.put(dome, mat, mode='shine', cast=2, iline=True)
        brim = cv.ellipse(B.hx + hw / 2 + 0.5, B.hy + 5.5, hw / 2 + 4.0, 1.8)
        cv.put(brim, mat, mode='shine', cast=2, iline=True)
        ridge = cv.line([hp(B, HW / 2 - 1, -2.0), hp(B, HW / 2 + 1, 4.0)])
        cv.shade(ridge, +1, within=[p])
        return p
    if kind == 'knight':
        # casco abierto con cresta / penacho
        dome = cv.ellipse(B.hx + hw / 2 - 0.5, B.hy + 5.0, hw / 2 + 1.2, 7.0) & (cv.ys <= B.hy + 6.0)
        dome |= cv.poly([hp(B, -1.0, 4.0), hp(B, 4.5, 4.0), hp(B, 4.0, 12.5), hp(B, -0.5, 12.0)])
        p = cv.put(dome, mat, mode='shine', cast=2, iline=True)
        band = cv.poly([hp(B, 3.5, 4.5), hp(B, HW + 0.8, 3.5), hp(B, HW + 0.8, 5.0), hp(B, 3.5, 6.0)])
        cv.put(band & cv.ellipse(B.hx + hw / 2 - 0.5, B.hy + 5.0, hw / 2 + 2.0, 8.0), trim or mat, mode='shine', cast=1)
        if plume:
            lag, sway = pose.lag, pose.sway
            pts = bez3(hp(B, HW / 2 + 1, -1.5), hp(B, HW / 2 - 2, -7.0), hp(B, 0.0 + sway, -7.5 + lag * 0.5), hp(B, -6.0 + sway * 1.5, -1.0 + lag), 10)
            m = cv.stroke(pts, 2.4, 1.4)
            pp = cv.put(m, plume, mode='top', cast=0)
            cv.shade(cv.line(pts[2:-1]), -1, within=[pp])
        return p


def turban(cv, B, sp, pose, mat='turban', gem='gem'):
    hw = B.head['w']
    m = cv.ellipse(B.hx + hw / 2 - 0.5, B.hy + 3.5, hw / 2 + 2.0, 6.2) & (cv.ys <= B.hy + 6.5)
    p = cv.put(m, mat, mode='top', cast=2, iline=True, band=0.3)
    for k in range(3):
        cv.shade(cv.line([hp(B, -1.0 + k * 2, 6.0 - k * 0.5), hp(B, HW + 0.5, -0.5 + k * 2.2)]), -1, within=[p])
    if gem:
        cv.put(cv.ellipse(B.hx + hw - 2.0, B.hy + 2.5, 1.3, 1.6), gem, mode='shine')
    return p


def flower_crown(cv, B, sp, pose, flowers=('flower1', 'flower2', 'flower3'), leaf='leaf'):
    hw = B.head['w']
    pts = [(-0.5, 3.5), (2.0, 1.4), (5.0, 0.0), (8.5, -0.6), (12.0, 0.0), (14.8, 1.6)]
    for i, (x, y) in enumerate(pts):
        cv.put(cv.ellipse(B.hx + x + 0.8, B.hy + y + 0.8, 1.0, 0.8), leaf, mode='top')
    for i, (x, y) in enumerate(pts):
        c = flowers[i % len(flowers)]
        cv.put(cv.ellipse(B.hx + x, B.hy + y, 1.3, 1.2), c, mode='top', cast=1)
        cv.dot(B.hx + x, B.hy + y, 'gold', 3)


def goggles(cv, B, sp, pose, mat='brass', lens='lens'):
    hw = B.head['w']
    strap = cv.poly([hp(B, -1.0, 3.5), hp(B, HW + 0.5, 2.0), hp(B, HW + 0.5, 3.5), hp(B, -1.0, 5.0)])
    cv.put(strap, 'strap', mode='cyl', cast=1)
    for (x, y) in ((7.5, 2.6), (12.5, 2.2)):
        cv.put(cv.ellipse(B.hx + x, B.hy + y, 2.3, 2.2), mat, mode='shine', cast=1, iline=True)
        cv.put(cv.ellipse(B.hx + x, B.hy + y, 1.3, 1.2), lens, mode='shine')
        cv.dot(B.hx + x - 0.6, B.hy + y - 0.6, 'white', 4)


def glasses(cv, B, sp, pose, mat='frame'):
    a1, a2 = ha(B, 1), ha(B, 2)
    y0 = int(a1[1])
    for (x, w) in ((int(a1[0]) - 1, 5), (int(a2[0]) - 1, 4)):
        ring = cv.rect(x, y0, x + w, y0 + 4) & ~cv.rect(x + 1, y0 + 1, x + w - 1, y0 + 3)
        ring &= ~(cv.rect(x, y0, x, y0) | cv.rect(x + w, y0, x + w, y0) | cv.rect(x, y0 + 4, x, y0 + 4) | cv.rect(x + w, y0 + 4, x + w, y0 + 4))
        cv.paint(ring, mat, 2)
    cv.paint(cv.rect(int(a1[0]) + 4, y0 + 1, int(a2[0]) - 1, y0 + 1), mat, 2)
    cv.dot(int(a1[0]) + 2, y0 + 1, 'white', 4)


def cap_soft(cv, B, sp, pose, mat='cap'):
    hw = B.head['w']
    m = cv.ellipse(B.hx + hw / 2 - 1.0, B.hy + 3.0, hw / 2 + 1.5, 5.0) & (cv.ys <= B.hy + 5.0)
    m |= cv.ellipse(B.hx + 2.0, B.hy + 1.5, 4.0, 3.2)
    p = cv.put(m, mat, mode='top', cast=2, iline=True)
    cv.put(cv.rect(B.hx + 3, B.hy + 4, B.hx + hw + 1, B.hy + 5) & cv.ellipse(B.hx + hw / 2, B.hy + 4.5, hw / 2 + 2.5, 3.0), mat, mode='cyl', cast=1)
    return p


def chef_hat(cv, B, sp, pose, mat='cloth_w'):
    """Gorro de cocinero: banda y copa abombada."""
    band = cv.poly([hp(B, 2.0, 4.0), hp(B, 17.0, 2.8), hp(B, 17.3, 5.4), hp(B, 2.3, 6.8)])
    puff = cv.ellipse(*hp(B, 6.0, 0.2), 3.8, 3.4) | cv.ellipse(*hp(B, 10.5, -1.4), 4.2, 3.8) | cv.ellipse(*hp(B, 14.6, 0.4), 3.4, 3.2)
    puff &= cv.ys <= B.hy + 4.0 * B.head['h'] / 20.0
    p = cv.put(puff, mat, mode='top', cast=1, band=0.25)
    cv.shade(cv.line([hp(B, 8.4, -0.6), hp(B, 8.6, 3.0)]) | cv.line([hp(B, 12.8, -1.0), hp(B, 12.8, 2.6)]), -1, within=[p])
    cv.put(band, mat, mode='cyl', cast=2, iline=True)
    return p


def toque_old(cv, B, sp, pose, mat='cloth_w'):
    """Pañuelo de cocinero atado."""
    hw = B.head['w']
    m = cv.ellipse(B.hx + hw / 2, B.hy + 4.0, hw / 2 + 1.5, 6.0) & (cv.ys <= B.hy + 5.5)
    p = cv.put(m, mat, mode='top', cast=2, iline=True)
    k = cv.poly([hp(B, 0.0, 3.0), hp(B, -4.0 + pose.sway, 1.0 + pose.lag), hp(B, -4.5 + pose.sway, 5.5 + pose.lag), hp(B, 0.5, 5.0)])
    cv.put(k, mat, mode='cyl', iline=True)
    return p


# ------------------------------------------------------------------ objetos en la mano

def staff(cv, B, sp, side, pose, wood='wood', gem='gem', crown='wood', top=None, kind='mage', foot=True):
    g = B.arm[side]['grip']
    x = g[0] + 0.2
    y_top = (B.hy - 6) if top is None else B.hy + top
    y_bot = GROUND - 1 if foot else g[1] + 14
    m = cv.capsule((x + 0.6, y_top + 4), (x - 0.3, y_bot), 0.9, 0.9)
    p = cv.put(m, wood, mode='cyl')
    if kind == 'mage':
        # corona: dos ramas curvas que abrazan la gema (bastón de maga elfa)
        cy = y_top + 1.5
        arc_l = bez((x + 0.5, y_top + 5.5), (x - 4.0, cy + 1.5), (x - 1.5, cy - 3.5), 6)
        arc_r = bez((x + 0.5, y_top + 5.5), (x + 5.0, cy + 1.0), (x + 2.5, cy - 3.5), 6)
        cv.put(cv.stroke(arc_l, 0.9, 0.6) | cv.stroke(arc_r, 0.9, 0.6), crown, mode='shine')
        cv.put(cv.ellipse(x + 0.5, cy, 1.9, 2.3), gem, mode='shine')
        cv.dot(x - 0.3, cy - 1.0, 'white', 4)
    elif kind == 'orb':
        cy = y_top + 1.0
        cv.put(cv.capsule((x - 1.5, y_top + 4), (x + 2.5, y_top + 4), 0.8), crown, mode='shine')
        cv.put(cv.ellipse(x + 0.5, cy, 2.2, 2.4), gem, mode='shine')
        cv.dot(x - 0.3, cy - 1.0, 'white', 4)
    elif kind == 'sun':
        cy = y_top + 1.5
        cv.put(cv.ellipse(x + 0.5, cy, 3.0, 3.0) & ~cv.ellipse(x + 0.5, cy, 1.6, 1.6), crown, mode='shine')
        for a in range(0, 360, 45):
            r = math.radians(a)
            cv.put(cv.capsule((x + 0.5 + math.cos(r) * 3.0, cy + math.sin(r) * 3.0), (x + 0.5 + math.cos(r) * 4.4, cy + math.sin(r) * 4.4), 0.5), crown, mode='flat')
        cv.put(cv.ellipse(x + 0.5, cy, 1.2, 1.2), gem, mode='shine')
    elif kind == 'cane':
        cv.put(cv.stroke(bez((x - 0.3, y_top + 4), (x + 1.0, y_top), (x + 3.5, y_top + 1.5), 6), 1.0, 1.0), wood, mode='cyl')
    return p


def spear(cv, B, sp, side, pose, wood='wood', tip='steel'):
    g = B.arm[side]['grip']
    x = g[0]
    y_top = B.hy - 10
    m = cv.capsule((x + 0.6, y_top + 5), (x - 0.4, GROUND - 1), 0.85)
    p = cv.put(m, wood, mode='cyl')
    head = cv.poly([(x + 0.6, y_top - 2.5), (x + 2.4, y_top + 2.5), (x + 0.8, y_top + 6.0), (x - 1.0, y_top + 2.5)])
    cv.put(head, tip, mode='shine')
    cv.put(cv.rect(int(x) - 1, int(y_top + 6), int(x) + 2, int(y_top + 6)), tip, mode='shine')
    return p


def sword_hip(cv, B, sp, pose, blade='steel', hilt='gold', sheath='leather', side='f'):
    """Espada envainada a la cadera. side 'f': cadera lejana (la vaina se va atrás, tras las piernas);
    'n': cadera cercana (empuñadura al frente a la izquierda, vaina hacia atrás y abajo junto a la pierna)."""
    if side == 'n':
        x0, y0 = B.cx_hip - B.hw / 2 + 1.0, B.y_w + 2.0
        tip = (x0 - 7.5, y0 + B.d['leg'] * 0.85)
        m = cv.capsule((x0, y0), tip, 1.3, 1.1)
        p = cv.put(m, sheath, mode='cyl', iline=True, cast=1)
        cv.put(cv.capsule((tip[0] + 0.6, tip[1] - 1.5), tip, 1.4, 1.2), hilt, mode='shine', iline=True)
        cv.put(cv.capsule((x0 + 0.6, y0 - 1.2), (x0 + 2.4, y0 - 4.6), 0.9), 'leather', mode='cyl', iline=True)
        cv.put(cv.capsule((x0 - 1.6, y0 - 0.2), (x0 + 2.6, y0 - 1.6), 0.7), hilt, mode='shine', iline=True)
        cv.put(cv.ellipse(x0 + 2.6, y0 - 5.2, 1.1, 1.1), hilt, mode='shine', iline=True)
        B.hilt = (x0 + 2.2, y0 - 4.0)
        return p
    x0, y0 = B.cx_hip + B.ww / 2 - 1.0, B.y_w + 2.5
    ang = math.radians(62)
    L = B.d['leg'] * 0.62
    tip = (x0 - math.cos(ang) * L * 0.25 - 1, y0 + math.sin(ang) * L)
    m = cv.capsule((x0, y0), tip, 1.2, 1.0)
    p = cv.put(m, sheath, mode='cyl', iline=True)
    cv.put(cv.capsule((x0 + 0.5, y0 - 1.0), (x0 + 2.2, y0 - 4.5), 0.8), hilt, mode='shine')
    cv.put(cv.capsule((x0 - 1.4, y0 - 0.6), (x0 + 2.6, y0 - 1.6), 0.6), hilt, mode='shine')
    return p


def dagger_hip(cv, B, sp, pose, mat='steel', hilt='leather'):
    x0, y0 = B.cx + B.ww / 2 - 0.5, B.y_w + 2.5
    cv.put(cv.capsule((x0, y0), (x0 - 1.2, y0 + 5.5), 1.0, 0.7), 'leather', mode='cyl', iline=True)
    cv.put(cv.capsule((x0 + 0.3, y0 - 0.5), (x0 + 1.0, y0 - 2.5), 0.7), mat, mode='shine')


def greatsword_back(cv, B, sp, pose, blade='steel', hilt='leather', guard='gold'):
    sx, sy = B.cx - B.sw / 2 - 4.0, B.y_sh - 7.0
    ex, ey = B.cx + B.sw / 2 + 2.5, B.hip_y + 7.0
    m = cv.capsule((sx + 3.0, sy + 4.0), (ex, ey), 1.6, 1.3)
    p = cv.put(m, blade, mode='shine')
    cv.put(cv.capsule((sx - 1.0, sy - 0.5), (sx + 2.0, sy + 2.5), 1.0), hilt, mode='cyl')
    cv.put(cv.capsule((sx + 0.0, sy + 4.5), (sx + 4.5, sy + 0.8), 0.9), guard, mode='shine')
    return p


def axe_back(cv, B, sp, pose, wood='wood', blade='steel'):
    sx, sy = B.cx - B.sw / 2 - 1.0, B.y_sh - 7.0
    ex, ey = B.cx + B.sw / 2 - 2.0, B.hip_y + 4.0
    cv.put(cv.capsule((sx, sy), (ex, ey), 1.0), wood, mode='cyl')
    bl = cv.poly([(sx - 5.0, sy - 3.5), (sx - 0.5, sy - 1.0), (sx + 1.0, sy + 3.0), (sx - 3.5, sy + 5.5), (sx - 6.0, sy + 2.0)])
    cv.put(bl, blade, mode='shine')


def bow_back(cv, B, sp, pose, wood='wood', string='string'):
    cx = B.cx - B.sw / 2 - 0.5
    pts = bez((cx + 7.0, B.y_sh - 7.0), (cx - 8.0, B.y_w - 2.0), (cx + 3.5, B.hip_y + 7.0), 14)
    cv.put(cv.stroke(pts, 1.0, 1.0), wood, mode='cyl')
    cv.put(cv.line([pts[0], pts[-1]]), string, mode='flat', outline=False)


def quiver(cv, B, sp, pose, mat='leather', fletch='fletch'):
    x0, y0 = B.cx - B.sw / 2 - 1.5, B.y_sh - 1.5
    m = cv.capsule((x0, y0 + 1.0), (x0 + 5.0, B.hip_y - 3.0), 1.8, 1.6)
    p = cv.put(m, mat, mode='cyl')
    cv.put(cv.capsule((x0 - 0.3, y0 + 0.5), (x0 + 0.6, y0 + 2.0), 2.1, 2.1) & m, 'strap', mode='cyl')
    for k in range(3):
        fx = x0 - 1.6 + k * 1.3
        cv.put(cv.poly([(fx, y0 - 3.0 - (k % 2)), (fx + 1.2, y0 - 3.4 - (k % 2)), (fx + 1.6, y0 + 0.5), (fx + 0.4, y0 + 0.5)]), fletch, mode='top')


def shield_back(cv, B, sp, pose, mat='shield', rim='steel', emblem=None):
    cx, cy = B.cx - B.sw / 2 - 1.0, B.y_sh + 8.0
    pts = [(cx - 6.5, cy - 6.0), (cx + 4.0, cy - 6.0), (cx + 4.0, cy + 2.0), (cx - 1.0, cy + 8.5), (cx - 6.5, cy + 2.0)]
    m = cv.poly(pts)
    p = cv.put(m, rim, mode='shine')
    inner = cv.poly([(cx - 5.5, cy - 5.0), (cx + 3.0, cy - 5.0), (cx + 3.0, cy + 1.5), (cx - 1.0, cy + 7.0), (cx - 5.5, cy + 1.5)])
    cv.paint(inner, mat, 2)
    if emblem:
        cv.paint(cv.line([(cx - 1.2, cy - 4.0), (cx - 1.2, cy + 5.0)]) | cv.line([(cx - 4.5, cy - 1.0), (cx + 2.0, cy - 1.0)]), emblem, 3)


def book(cv, B, sp, side, pose, cover='book', page='page', clasp='gold'):
    """Libro sujeto por un canto: la mano tapa el borde izquierdo y se ve la tapa con su broche y el canto de
    las páginas a la derecha."""
    g = B.arm[side]['grip']
    x, y = g[0] + 0.5, g[1] - 1.0
    m = cv.rect(int(x - 2), int(y - 4), int(x + 3), int(y + 1))
    p = cv.put(m, cover, mode='cyl', iline=True)
    cv.paint(cv.rect(int(x + 3), int(y - 3), int(x + 3), int(y)), page, 3)
    cv.paint(cv.rect(int(x - 2), int(y - 4), int(x + 2), int(y - 4)), cover, 3)
    cv.dot(x + 1, y - 2, clasp, 4)
    cv.dot(x + 1, y - 1, clasp, 2)
    return p


def basket(cv, B, sp, side, pose, mat='wicker', goods=('veg1', 'veg2', 'leaf')):
    g = B.arm[side]['grip']
    x, y = g[0] + 0.5, g[1] + 3.5
    body = cv.poly([(x - 5.5, y - 1.5), (x + 5.5, y - 1.5), (x + 4.5, y + 4.5), (x - 4.5, y + 4.5)])
    # contenido
    for i, (dx, dy, r) in enumerate(((-3.0, -2.5, 2.0), (0.0, -3.2, 2.2), (3.0, -2.4, 1.9))):
        cv.put(cv.ellipse(x + dx, y + dy, r, r * 0.9), goods[i % len(goods)], mode='top')
    p = cv.put(body, mat, mode='cyl', iline=True)
    cv.shade(body & ((cv.xs + cv.ys) % 2 == 0), -1, within=[p])
    handle = cv.line(bez((x - 4.5, y - 1.5), (x, y - 9.0), (x + 4.5, y - 1.5), 8))
    cv.put(handle & (cv.pid == 0) | handle, mat, mode='flat')
    return p


def parasol(cv, B, sp, side, pose, mat='lace', trim='lace2', pole='wood'):
    """Vara de la sombrilla (en la mano); la tela la pinta parasol_top por delante."""
    g = B.arm[side]['grip']
    x, y = g[0], g[1]
    top = (B.hx + 6.0, B.hy - 9.0)
    cv.put(cv.capsule((x + 0.8, y + 2.5), top, 0.7), pole, mode='cyl')
    B.parasol_top = top


def parasol_top(cv, B, sp, pose, mat='lace', trim='lace2', pole='wood'):
    tx, ty = B.parasol_top
    cx, cy = tx - 1.0, ty + 1.0
    sway = pose.lag * 0.5
    can = cv.poly([(cx - 14.0, cy + 6.0 + sway), (cx - 10.0, cy - 0.5), (cx - 3.0, cy - 4.5), (cx + 3.5, cy - 4.5), (cx + 10.0, cy - 1.0),
                   (cx + 14.0, cy + 5.0 + sway), (cx + 10.0, cy + 3.8), (cx + 5.5, cy + 5.2), (cx + 0.5, cy + 4.0), (cx - 4.5, cy + 5.4),
                   (cx - 9.5, cy + 4.2)])
    p = cv.put(can, mat, mode='top', cast=1, band=0.25)
    for k in (-9.0, -3.5, 2.5, 8.5):
        cv.shade(cv.line([(cx + k * 0.25, cy - 4.0), (cx + k, cy + 4.2)]), -1, within=[p])
    hem_trim(cv, p, trim, cy)
    cv.put(cv.ellipse(cx, cy - 5.2, 0.9, 1.1), pole, mode='shine')
    return p


def backpack(cv, B, sp, pose, mat='pack', strap='leather', rolled='rug', pot='pot'):
    """Mochila enorme de mercader viajero."""
    x0 = B.cx - B.sw / 2 - 7.5
    y0 = B.y_sh - 10.0 + pose.bob * 0
    m = cv.poly([(x0, y0 + 3), (x0 + 3, y0), (x0 + 12, y0), (x0 + 13.5, y0 + 3), (x0 + 13.5, B.hip_y + 4), (x0 + 1.0, B.hip_y + 5), (x0, B.hip_y + 2)])
    p = cv.put(m, mat, mode='cyl', band=0.3)
    # alfombra enrollada arriba
    cv.put(cv.capsule((x0 - 1.5, y0 - 2.0), (x0 + 14.5, y0 - 2.5), 2.4), rolled, mode='top')
    cv.shade(cv.line([(x0 + 2, y0 - 4.0), (x0 + 2, y0 - 0.5)]) | cv.line([(x0 + 10, y0 - 4.5), (x0 + 10, y0 - 1.0)]), -1)
    # olla colgando y bolsillos
    cv.put(cv.ellipse(x0 + 0.5, B.y_w + 2.0, 3.0, 2.6), pot, mode='shine')
    cv.put(cv.rect(int(x0 + 4), int(B.y_w - 3), int(x0 + 10), int(B.y_w + 3)), strap, mode='cyl')
    cv.dot(x0 + 7, B.y_w - 1, 'gold', 3)
    cv.shade(cv.line([(x0 + 2, y0 + 8), (x0 + 12, y0 + 8)]), -1, within=[p])
    return p


def satchel(cv, B, sp, pose, mat='leather', strap='leather'):
    cv.put(cv.line([(B.cx + 3, B.y_sh), (B.cx - 4, B.y_w + 2)]), strap, mode='flat', outline=False)
    x, y = B.cx - B.hw / 2 - 1.5, B.hip_y - 1.5
    p = cv.put(cv.rect(int(x - 2), int(y - 2), int(x + 3), int(y + 3)), mat, mode='cyl', iline=True)
    cv.put(cv.rect(int(x - 2), int(y - 2), int(x + 3), int(y - 1)), strap, mode='top')
    return p


def fishing_rod(cv, B, sp, side, pose, wood='wood', line='string', fish='fish'):
    g = B.arm[side]['grip']
    x, y = g[0], g[1]
    tip = (x - 14.0, y - 34.0)
    cv.put(cv.capsule((x + 2.0, y + 3.0), tip, 0.8, 0.5), wood, mode='cyl')
    end = (tip[0] - 1.5, tip[1] + 11.0 + pose.lag)
    cv.put(cv.line([tip, end]), line, mode='flat', outline=False)
    fm = cv.poly([(end[0] - 1.6, end[1] + 1.0), (end[0] + 1.6, end[1] + 1.0), (end[0] + 1.2, end[1] + 5.5), (end[0], end[1] + 6.5), (end[0] - 1.2, end[1] + 5.5)])
    fm |= cv.poly([(end[0] - 1.8, end[1] + 6.5), (end[0] + 1.8, end[1] + 6.5), (end[0], end[1] + 5.0)])
    cv.put(fm, fish, mode='shine')


def ladle(cv, B, sp, side, pose, mat='steel'):
    g = B.arm[side]['grip']
    x, y = g[0], g[1]
    cv.put(cv.capsule((x, y + 1.0), (x + 1.5, y - 11.0), 0.7), 'wood', mode='cyl')
    cv.put(cv.ellipse(x + 2.0, y - 12.5, 2.4, 1.8), mat, mode='shine')


def lantern(cv, B, sp, side, pose, mat='steel', glow='glow'):
    g = B.arm[side]['grip']
    x, y = g[0] + 0.5, g[1] + 2.5
    cv.put(cv.line([(x, y - 2), (x, y)]), mat, mode='flat')
    body = cv.rect(int(x - 2), int(y + 1), int(x + 2), int(y + 6))
    p = cv.put(body, mat, mode='shine')
    cv.paint(cv.rect(int(x - 1), int(y + 2), int(x + 1), int(y + 5)), glow, 3)
    cv.dot(x - 1, y + 2, glow, 4)
    cv.put(cv.rect(int(x - 2), int(y), int(x + 2), int(y)), mat, mode='shine')


def flask(cv, B, sp, side, pose, glass='glass', liquid='potion', up=None):
    """Matraz de fondo redondo: bulbo con líquido, cuello de vidrio y corcho. Con el brazo en alto (up) el frasco
    asoma por encima de la mano (la mano lo sujeta por la base) y se ve entero."""
    A = B.arm[side]
    g = A['grip']
    if up is None:
        up = A['hand'][1] < A['el'][1] - 2.0
    if up:
        x, y = g[0] + 0.5, g[1] - 6.0
    else:
        x, y = g[0] + 0.3, g[1] - 3.2
    bulb = cv.ellipse(x, y + 1.0, 3.0 if up else 2.7, 2.8 if up else 2.5)
    pb = cv.put(bulb, liquid, mode='stroke', nrm=cv.sphere_n(x - 0.8, y, 3.2, 3.0), iline=True, bias=0.9)
    cv.paint(bulb & (cv.ys < y + 0.2), 'glass', 3)
    cv.put(cv.rect(int(x - 0.5), int(y - 3.5), int(x + 0.5), int(y - 1.5)), 'glass', mode='cyl', iline=True)
    cv.put(cv.rect(int(x - 0.5), int(y - 4.5), int(x + 0.5), int(y - 4.5)), 'cork', mode='flat')
    cv.dot(x - 1.2, y + 0.2, 'white', 4)
    if up:
        A['no_regrip'] = True


def gem_hold(cv, B, sp, side, pose, gem='gem'):
    g = B.arm[side]['grip']
    x, y = g[0] + 0.5, g[1] - 2.5
    cv.put(cv.poly([(x - 1.8, y), (x, y - 2.2), (x + 1.8, y), (x, y + 2.2)]), gem, mode='shine')
    cv.dot(x - 0.5, y - 0.6, 'white', 4)


def bread(cv, B, sp, side, pose, mat='bread'):
    g = B.arm[side]['grip']
    x, y = g[0], g[1]
    a, b = (x - 3.0, y + 3.0), (x + 6.0, y - 7.0)
    m = cv.capsule(a, b, 2.2, 1.9)
    p = cv.put(m, mat, mode='top', iline=True, band=0.35)
    for k in range(4):
        t = 0.2 + k * 0.2
        px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        cv.paint(cv.line([(px - 0.8, py - 0.4), (px + 0.6, py + 0.8)]) & cv.of(p), mat, 4)
    return p


def wooden_sword(cv, B, sp, side, pose, mat='wood'):
    g = B.arm[side]['grip']
    x, y = g[0], g[1]
    cv.put(cv.capsule((x + 0.5, y - 1.0), (x + 6.0, y - 11.0), 1.0, 0.8), mat, mode='cyl')
    cv.put(cv.capsule((x - 1.0, y - 0.5), (x + 2.5, y - 2.5), 0.6), 'wood2', mode='cyl')


def earrings(cv, B, sp, pose, mat='gem', dx=0.0, dy=0.0):
    a = ha(B, 6)
    x, y = int(a[0] + 1 + dx), int(a[1] + 3 + dy)
    cv.put(cv.rect(x, y, x, y), 'gold', mode='flat', outline=False)
    cv.put(cv.rect(x, y + 1, x, y + 2), mat, mode='flat')
    cv.dot(x, y + 1, mat, 4)
    cv.dot(x, y + 2, mat, 1)


def tail(cv, B, sp, pose, kind='cat', mat='hair', tip=None):
    lag, sway = pose.lag, pose.sway
    base = (B.cx - B.hw / 2 + 1.0, B.hip_y - 1.0)
    swing = [0, 1, 0, -1][pose.i] if pose.kind == 'walk' else [0, 1][pose.i]
    if kind == 'cat':
        pts = bez3(base, (base[0] - 7.0, base[1] + 3.0), (base[0] - 12.0 + swing, base[1] - 8.0), (base[0] - 9.0 + swing * 1.5, base[1] - 17.0 + lag), 14)
        m = cv.stroke(pts, 1.8, 1.5)
    elif kind == 'wolf':
        pts = bez3(base, (base[0] - 6.0, base[1] + 2.0), (base[0] - 11.0 + swing, base[1] + 4.0), (base[0] - 13.5 + swing * 1.5, base[1] + 10.0 + lag), 14)
        m = np.zeros((cv.h, cv.w), bool)
        for i, (x, y) in enumerate(pts):
            t = i / (len(pts) - 1)
            r = 1.8 + 2.4 * math.sin(math.pi * min(1.0, t * 1.15))
            m |= cv.ellipse(x, y, r, r)
    else:  # demonio: cola fina con punta de corazón
        pts = bez3(base, (base[0] - 6.0, base[1] + 6.0), (base[0] - 13.0 + swing, base[1] + 2.0), (base[0] - 12.0 + swing * 1.5, base[1] - 7.0 + lag), 14)
        m = cv.stroke(pts, 1.1, 0.8)
    p = cv.put(m, mat, mode='top', band=0.35)
    if kind == 'wolf':
        cv.shade(cv.line(pts[3:-2]), -1, within=[p])
    if tip:
        e = pts[-1]
        if kind == 'demon':
            tm = cv.poly([(e[0] - 2.2, e[1] + 0.5), (e[0], e[1] - 2.8), (e[0] + 2.2, e[1] + 0.5), (e[0], e[1] + 1.5)])
            cv.put(tm, tip, mode='shine')
        else:
            tm = cv.ellipse(e[0], e[1], 1.9, 1.9) | cv.stroke(pts[-3:], 1.9, 1.9)
            cv.put(tm & cv.of(p) | tm, tip, mode='top')
    return p


def tusks(cv, B, sp, pose, mat='tusk'):
    a3 = ha(B, 3)
    for dx in (-2.0, 2.0):
        cv.put(cv.poly([(a3[0] + dx - 0.6, a3[1] + 0.5), (a3[0] + dx + 0.8, a3[1] + 0.5), (a3[0] + dx + 0.3, a3[1] - 2.0)]), mat, mode='top', outline=False)


def big_nose(cv, B, sp, pose, mat='skin'):
    n = ha(B, 7)
    m = cv.ellipse(n[0] + 1.2, n[1] + 0.4, 2.8, 2.3)
    p = cv.put(m, 'nose', mode='soft', iline=False)
    cv.dot(n[0] + 0.2, n[1] - 0.8, 'white', 3)
    return p


def loupe(cv, B, sp, pose, mat='gold', lens='lens'):
    """Lupa de joyero sobre el ojo lejano."""
    a2 = ha(B, 2)
    x, y = a2[0] + 1.5, a2[1] + 2.0
    ring = cv.ellipse(x, y, 2.6, 2.6) & ~cv.ellipse(x, y, 1.4, 1.4)
    cv.put(ring, mat, mode='shine', iline=True)
    cv.dot(x - 0.5, y - 0.6, 'white', 4)


def stripes(cv, B, sp, pose, mat='stripe', step=3):
    """Rayas horizontales sobre la ropa del torso (camisa marinera)."""
    m = (cv.ys % step == 0) & (cv.ys > B.y_sh + 1) & (cv.ys < B.hip_y + 2)
    tops = [i for i, p in enumerate(cv.parts) if p is not None and p.mat == sp.get('top', {}).get('mat')]
    if tops:
        cv.paint(m & cv.of(*tops), mat, 2)


def chainmail(cv, B, sp, pose, mat='mail'):
    """Textura de cota de malla: puntitos claros y oscuros alternados."""
    ids = [i for i, p in enumerate(cv.parts) if p is not None and p.mat == mat]
    if not ids:
        return
    m = cv.of(*ids)
    cv.shade(m & ((cv.xs + cv.ys * 2) % 4 == 0), +1)
    cv.shade(m & ((cv.xs + cv.ys * 2) % 4 == 2), -1)


def belt_vial(cv, B, sp, pose, glass='glass', liquid='potion2'):
    """Frasquito colgando del cinturón (lado cercano)."""
    x, y = B.cx - B.ww / 2 + 1.0, B.y_w + 4.0
    cv.put(cv.line([(x + 0.5, y - 2.0), (x, y)]), 'strap', mode='flat', outline=False)
    cv.put(cv.ellipse(x, y + 2.2, 1.7, 2.0), liquid, mode='shine', iline=True)
    cv.put(cv.rect(int(x), int(y), int(x), int(y)), 'cork', mode='flat')
    cv.dot(x - 0.6, y + 1.6, 'white', 4)


def quill(cv, B, sp, pose, mat='feather'):
    """Pluma de escribir detrás de la oreja: barbas claras y cañón oscuro."""
    a = ha(B, 6)
    base = (a[0] + 1.5, a[1] + 1.5)
    tip = (a[0] - 2.5, a[1] - 7.5)
    vane = cv.poly([(base[0] - 0.5, base[1] - 2.5), (tip[0] + 2.2, tip[1] + 2.0), tip, (tip[0] - 1.2, tip[1] + 3.0), (base[0] - 1.5, base[1] - 1.0)])
    p = cv.put(vane, mat, mode='top', cast=1)
    cv.paint(cv.line([base, tip]) & cv.of(p), 'frame', 2)
    cv.put(cv.line([base, (base[0] + 1.0, base[1] + 1.5)]), 'frame', mode='flat', outline=False)



def hoe(cv, B, sp, side, pose, wood='wood', blade='steel'):
    """Azada apoyada en el hombro: el mango sube desde la mano hacia atrás (izquierda), la hoja arriba detrás de la cabeza."""
    g = B.arm[side]['grip']
    lo = (g[0] + 3.5, g[1] + 7.0)
    hi = (g[0] - 13.0, g[1] - 14.0)
    p = cv.put(cv.capsule(lo, hi, 0.9, 0.9), wood, mode='cyl', iline=True)
    # hoja: placa casi vertical que cuelga del extremo de arriba
    bl = cv.poly([(hi[0] - 1.0, hi[1] - 1.0), (hi[0] + 1.5, hi[1] + 0.5), (hi[0] + 0.5, hi[1] + 6.5), (hi[0] - 2.8, hi[1] + 5.5)])
    cv.put(bl, blade, mode='shine', iline=True)
    cv.put(cv.ellipse(hi[0] - 0.2, hi[1] + 0.2, 1.4, 1.2), 'wood2', mode='cyl', iline=True)
    return p



def tool_planted(cv, B, sp, side, pose, kind='hoe', wood='wood', blade='steel'):
    """Herramienta de campo apoyada en el suelo (azada, horca, rastrillo), sujeta con la mano a media altura."""
    g = B.arm[side]['grip']
    x = g[0] + 0.3
    top = B.hy - 3.0
    p = cv.put(cv.capsule((x + 0.4, top), (x - 0.4, GROUND - 1), 0.9, 0.9), wood, mode='cyl', iline=True)
    if kind == 'hoe':
        bl = cv.poly([(x - 0.5, top - 1.0), (x + 5.0, top + 0.5), (x + 5.5, top + 4.5), (x + 3.5, top + 4.5), (x + 3.0, top + 2.0), (x - 0.5, top + 1.0)])
        cv.put(bl, blade, mode='shine', iline=True)
    elif kind == 'fork':
        cv.put(cv.rect(int(x - 2), int(top - 1), int(x + 2), int(top)), blade, mode='shine', iline=True)
        for dx in (-2, 0, 2):
            cv.put(cv.rect(int(x + dx), int(top - 6), int(x + dx), int(top - 1)), blade, mode='shine', iline=True)
    return p


def axe_shoulder(cv, B, sp, side, pose, wood='wood', blade='steel'):
    """Hacha apoyada en el hombro: el mango sube desde la mano por encima del hombro hacia atrás; la hoja queda
    arriba, detrás (a la izquierda) de la cabeza."""
    g = B.arm[side]['grip']
    lo = (g[0] + 2.0, g[1] + 4.5)
    hi = (g[0] - 6.5, g[1] - 13.0)
    p = cv.put(cv.capsule(lo, hi, 1.0, 1.0), wood, mode='cyl', iline=True)
    bl = cv.poly([(hi[0] + 1.2, hi[1] - 1.5), (hi[0] - 3.5, hi[1] - 4.5), (hi[0] - 6.5, hi[1] - 0.5), (hi[0] - 5.5, hi[1] + 4.5),
                  (hi[0] - 1.5, hi[1] + 5.0), (hi[0] + 1.6, hi[1] + 2.5)])
    pb = cv.put(bl, blade, mode='shine', iline=True)
    cv.shade(cv.line([(hi[0] - 5.0, hi[1] - 1.0), (hi[0] - 4.2, hi[1] + 3.5)]), +1, within=[pb])
    return p


def bow_hand(cv, B, sp, side, pose, wood='wood', string='string'):
    """Arco largo sujeto en la mano, vertical junto al cuerpo: el lomo se curva hacia afuera (izquierda)."""
    g = B.arm[side]['grip']
    x, y = g[0], g[1]
    s = -1 if side == 'n' else 1
    top = (x + 1.5 * -s, y - 17.0)
    bot = (x + 1.5 * -s, min(GROUND - 3.0, y + 15.0))
    pts = bez3(top, (x + 4.5 * s, y - 10.0), (x + 4.5 * s, y + 8.0), bot, 16)
    p = cv.put(cv.stroke(pts, 0.8, 0.8), wood, mode='cyl', iline=True)
    cv.put(cv.line([top, bot]) & ~cv.of(p), string, mode='flat', outline=False)
    return p


def dagger_hand(cv, B, sp, side, pose, blade='steel', hilt='leather'):
    """Daga corta en la mano, la hoja siguiendo la dirección del antebrazo."""
    A = B.arm[side]
    g = A['grip']
    dx, dy = A['hand'][0] - A['el'][0], A['hand'][1] - A['el'][1]
    l = math.hypot(dx, dy) or 1.0
    dx, dy = dx / l, dy / l
    a = (g[0] + dx * 1.5, g[1] + dy * 1.5)
    b = (g[0] + dx * 7.0, g[1] + dy * 7.0)
    p = cv.put(cv.capsule(a, b, 0.9, 0.4), blade, mode='shine', iline=True)
    cv.put(cv.capsule((g[0] - dy * 1.6, g[1] + dx * 1.6), (g[0] + dy * 1.6, g[1] - dx * 1.6), 0.5), 'gold', mode='shine', iline=True)
    return p


def coin_hand(cv, B, sp, side, pose, mat='gold'):
    """Moneda (o una piedrita) en la palma tendida."""
    g = B.arm[side]['grip']
    cv.put(cv.ellipse(g[0], g[1] - 2.6, 1.6, 1.3), mat, mode='shine', iline=True, bias=1.0)
    cv.dot(g[0] - 0.5, g[1] - 3.0, 'white', 4)


def sprig_hand(cv, B, sp, side, pose, leaf='leaf', flower='flower1'):
    """Ramito de hierbas / flor en la mano (herbolaria)."""
    g = B.arm[side]['grip']
    x, y = g[0], g[1] - 1.5
    cv.put(cv.line([(x, y + 1), (x + 1.5, y - 5)]), leaf, mode='flat', outline=False)
    for (dx, dy) in ((0.5, -5.5), (2.2, -4.5), (1.0, -3.2)):
        cv.put(cv.ellipse(x + dx, y + dy, 1.2, 1.0), leaf, mode='top', iline=True)
    cv.put(cv.ellipse(x + 1.6, y - 6.5, 1.3, 1.2), flower, mode='top', iline=True)
