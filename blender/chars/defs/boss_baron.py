"""BOSS_BARON — BARON VON STATIC's body (GDD §13 step 6 "Boss model", STYLE_GUIDE: SIMPLIFY + EXAGGERATE).
(Port of src/art/chars/boss_baron.js.) Sculpted here in model units (the boss runtime scales the character x2.5):
  - a chunky inverted-trapezoid TUX jacket in #1A1A2E with big rounded shoulder pads,
  - wide PLUM satin peaked lapels (flat shells of the jacket) over a painted white shirt V, two satin buttons,
    a red carnation on the lapel,
  - a white frilly JABOT cascading from a white wing-collar band, and a big gold "13" MEDALLION on a gold chain,
  - the tall stiff Dracula CAPE COLLAR rising behind the head (black outside, magenta-plum lining, two pointed tips),
  - LONG arms in tux sleeves with white shirt cuffs and gold cufflinks,
  - HUGE white four-finger cartoon GLOVES (three sausage fingers + thumb, flared gauntlet cuff, three stitch lines).
Built at runtime by the boss (they animate every frame): the console-TV head, the flowing cape, the static tornado.
Custom skeleton: base (waist, root) -> chest -> head (the neck); chest -> shoulderL/R -> elbowL/R -> handL/R.
The JS createAnimator (charview preview idle) is runtime code.
"""
import math

import numpy as np

from ..jsutil import O
from ._sculpt import prism

# Bind joint positions (absolute, model units).
JP = O(
    base=[0, 0, 0],
    chest=[0, 0.3, 0],
    neck=[0, 0.64, 0.01],
    shoulder=[-0.31, 0.575, 0.01],
    elbow=[-0.46, 0.28, -0.02],
    hand=[-0.55, 0.0, -0.07],
)


def rel(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def neg(p):
    return [-p[0], p[1], p[2]]


# Glove frame: local -y runs along the forearm (elbow -> hand), local +x is medial (toward the body), -z is front.
GLOVE_ROT = [0.179, 0, -0.31]

TUX = '#1A1A2E'

# Cape collar profile: (radius, height) points of a gently bell-flared surface of revolution around an axis behind
# the neck. collarShell() is its EXACT distance field (2D distance to the profile polyline) minus a half thickness.
COLLAR = O(axisZ=0.14, t=0.0105, prof=[])
for _i in range(9):
    _u = _i / 8
    COLLAR.prof.append([0.15 + 0.46 * math.pow(_u, 1.35), 0.46 + 0.62 * _u])


def collarDist(x, y, z):
    rho = np.hypot(x, z)
    P = COLLAR.prof
    best = np.full(np.shape(rho), np.inf)
    for i in range(len(P) - 1):
        ax, ay, bx, by = P[i][0], P[i][1], P[i + 1][0] - P[i][0], P[i + 1][1] - P[i][1]
        px, py = rho - ax, y - ay
        h = np.clip((px * bx + py * by) / (bx * bx + by * by), 0, 1)
        dx, dy = px - bx * h, py - by * h
        best = np.minimum(best, dx * dx + dy * dy)
    return np.sqrt(best) - COLLAR.t


def collarShell(sd, o=None):
    return sd.custom(O(pos=[0, 0, COLLAR.axisZ], box=[-0.64, 0.42, -0.64, 0.64, 1.12, 0.64], fn=collarDist), **(o or {}))


def jacketShapes(sd):
    """Jacket volume shared by the jacket and the lapel shells."""
    sd.ellipsoid(pos=[0, 0.43, 0.0], r=[0.25, 0.19, 0.155])            # chest
    sd.ellipsoid(pos=[0, 0.18, 0.005], r=[0.172, 0.2, 0.13])           # waist (V taper)
    sd.ellipsoid(pos=[0, 0.548, 0.012], r=[0.3, 0.078, 0.142])         # shoulder yoke
    sd.ellipsoid(pos=[0, 0.42, -0.035], r=[0.2, 0.15, 0.12])           # chest front (fills the lapel area)
    sd.ellipsoid(pos=[0, 0.02, 0.01], r=[0.185, 0.07, 0.135])          # hem, rounds off into the tornado


def _lining(x, y, z):
    P = COLLAR.prof
    u = np.clip((y - P[0][1]) / (P[8][1] - P[0][1]), 0, 1)
    return np.hypot(x, z) - (0.15 + 0.46 * np.power(u, 1.35))


def sculpt(sd, ctx=None):
    # ---------------- tux jacket ----------------
    with sd.group(name='jacket', mat='tux', bone=['base', 'chest'], k=0.07) as jacket:
        jacketShapes(sd)
        sd.mirrorX(lambda: sd.sphere(pos=[-0.285, 0.548, 0.012], r=0.088, k=0.05))    # shoulder pads
    # painted white shirt V (never carved)
    V = [[0, 0.235], [0.088, 0.63], [-0.088, 0.63]]
    sd.paint({'mat': 'shirt', 'soft': 0.0015, 'only': ['tux']}, lambda: prism(sd, V, {'max': -0.03, 'k': 0.004}))
    # wide peaked plum lapels: flat shells of the jacket ∩ the lapel footprint (front only)
    LAPEL = [[0.086, 0.632], [0.212, 0.598], [0.238, 0.51], [0.034, 0.222], [0.012, 0.242]]
    with sd.group(name='lapels', mat='lapel', bone=['chest'], k=0, blend=0.008):
        sd.group({'offset': 0.009, 'shell': 0.0095, 'k': 0.07}, lambda: jacketShapes(sd))
        sd.group({'op': 'int', 'blend': 0.006, 'k': 0}, lambda: sd.mirrorX(lambda: prism(sd, LAPEL, {'max': -0.03, 'k': 0.014})))

    @sd.mirrorX
    def _():
        L = LAPEL

        def lerp(a, b, t):
            return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
        sd.stitch([[x - 0.008, y, -0.3] for x, y in [lerp(L[1], L[2], 0.15), lerp(L[2], L[3], 0.1), lerp(L[2], L[3], 0.5), lerp(L[2], L[3], 0.92)]],
                  mats=['lapel'], color='#B77ABD', width=0.0016, dash=0.011)
    # two satin buttons where the lapels meet
    for by in [0.21, 0.15]:
        p = sd.snap(jacket, [0, by, -0.2], 0.002)
        sd.ellipsoid(mat='button', bone=['base'], pos=p, r=[0.016, 0.016, 0.008], k=0.003)
    # red carnation on the (character's) left lapel
    with sd.group(name='carnation', mat='flower', bone=['chest'], blend=0.004, k=0.01):
        c = [-0.155, 0.505, -0.172]
        sd.sphere(pos=c, r=0.027)
        for i in range(6):
            a = (i / 6) * math.pi * 2
            sd.sphere(pos=[c[0] + math.cos(a) * 0.021, c[1] + math.sin(a) * 0.021, c[2] + 0.004], r=0.016, k=0.008)
    sd.ellipsoid(mat='leaf', bone=['chest'], pos=[-0.18, 0.478, -0.165], rot=[0, 0, -0.7], r=[0.018, 0.008, 0.006], k=0.004)

    # ---------------- wing collar band + frilly jabot + gold "13" medallion ----------------
    with sd.group(name='collarBand', mat='shirt', bone=['chest', 'head'], blend=0.012, k=0.02):
        sd.capsule(a=[0, 0.57, 0.01], b=[0, 0.665, 0.012], r=0.072)
        sd.mirrorX(lambda: sd.ellipsoid(pos=[0.046, 0.655, -0.07], rot=[0.3, 0, -0.5], r=[0.034, 0.02, 0.012]))   # wing tips
    with sd.group(name='jabot', mat='jabot', bone=['chest'], blend=0.01, k=0.018):
        tiers = [[0.612, 0.058, 0.026, -0.104], [0.56, 0.074, 0.032, -0.13], [0.5, 0.084, 0.034, -0.143]]
        for y, w, h, z in tiers:
            sd.ellipsoid(pos=[0, y, z], r=[w, h, 0.026])
            # scalloped bottom edge: a row of soft beads
            n = 5
            for i in range(n):
                u = (i / (n - 1)) * 2 - 1
                sd.sphere(pos=[u * w * 0.82, y - h * 0.72, z - 0.004 - (1 - u * u) * 0.006], r=h * 0.5, k=0.01)
    # chain: two gold cords from the collar band down to the medallion
    sd.mirrorX(lambda: sd.worm(mat='gold', bone=['chest'], pts=[[0.07, 0.6, -0.06], [0.1, 0.5, -0.13], [0.07, 0.43, -0.165], [0.018, 0.418, -0.18]], r=0.0065, segs=14, k=0.003))
    MED = [0, 0.36, -0.184]
    with sd.group(name='medallion', mat='gold', bone=['chest'], rigid=True, blend=0.006, k=0.004):
        sd.cylinder(pos=MED, rot=[math.pi / 2, 0, 0], r=0.058, h=0.009, round=0.006)
        sd.torus(pos=[MED[0], MED[1], MED[2] - 0.009], rot=[math.pi / 2, 0, 0], R=0.05, r=0.0055)
        sd.sphere(pos=[0, 0.422, -0.182], r=0.011)                             # bail
    # the "13": plum digits painted on the face of the medallion
    with sd.paint(color='#4A1D5C', soft=0.001, strength=1, only=['gold']):
        # seen from the front, screen-right is -x: the '1' sits at +x and the '3' bulges toward -x
        z, y0 = MED[2] - 0.0095, MED[1]
        sd.capsule(a=[0.021, y0 - 0.026, z], b=[0.021, y0 + 0.026, z], r=0.0062)
        sd.capsule(a=[0.021, y0 + 0.026, z], b=[0.031, y0 + 0.015, z], r=0.0055)
        sd.worm(pts=[[-0.004, y0 + 0.02, z], [-0.016, y0 + 0.028, z], [-0.028, y0 + 0.018, z], [-0.018, y0 + 0.002, z]], r=0.0058, segs=10)
        sd.worm(pts=[[-0.018, y0 + 0.002, z], [-0.03, y0 - 0.012, z], [-0.018, y0 - 0.028, z], [-0.004, y0 - 0.02, z]], r=0.0058, segs=10)

    # ---------------- the tall stiff Dracula cape collar ----------------
    with sd.group(name='capeCollar', mat='cape', bone=['chest'], blend=0.01, k=0):
        collarShell(sd)
        with sd.group(op='int', k=0.014):
            prism(sd, [[-0.24, 0.5], [0.24, 0.5], [0.52, 1.0], [-0.52, 1.0]], {'k': 0.03})
            sd.plane(n=[0, 0, -1], d=0.03, op='int', k=0.02)                  # keep only the back (z > -0.03)
        sd.ellipsoid(op='sub', k=0.03, pos=[0, 1.25, 0.3], r=[0.3, 0.42, 0.8])  # dip at the back: two tips
    # magenta-plum lining on the inner face: paint where the point is on the axis side of the mid-surface
    sd.paint({'mat': 'lining', 'soft': 0.002, 'only': ['cape']}, lambda: sd.custom(pos=[0, 0, COLLAR.axisZ], box=[-0.64, 0.42, -0.64, 0.64, 1.12, 0.64], fn=_lining))

    # ---------------- long arms: tux sleeves, white cuffs, gold cufflinks ----------------
    @sd.mirrorX
    def _():
        S, E, H = JP.shoulder, JP.elbow, JP.hand

        def mid(a, b, t):
            return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
        with sd.group(mat='tux', blend=0.035, k=0.03):
            sd.roundCone(bone=['shoulderL'], a=mid(S, E, 0.05), b=mid(S, E, 0.6), ra=0.078, rb=0.07)
            sd.roundCone(bone=['shoulderL', 'elbowL'], a=mid(S, E, 0.55), b=E, ra=0.071, rb=0.066)
            sd.roundCone(bone=['elbowL'], a=E, b=mid(E, H, 0.86), ra=0.066, rb=0.058)
        # shirt cuff (clean roll) + cufflink
        C = mid(E, H, 0.9)
        with sd.group(mat='shirt', bone=['elbowL', 'handL'], blend=0.006, k=0.012):
            with sd.frame(pos=C, rot=GLOVE_ROT):
                sd.cylinder(r=0.06, h=0.022, round=0.012)
                sd.torus(pos=[0, -0.02, 0], R=0.052, r=0.014)
        sd.frame({'pos': C, 'rot': GLOVE_ROT}, lambda: sd.sphere(mat='gold', bone=['elbowL'], pos=[0.0, 0.0, -0.062], r=0.011, k=0.003))

        # ---- the huge white cartoon glove ----
        with sd.frame(pos=H, rot=GLOVE_ROT, scale=1.28):
            with sd.group(name='glove', mat='glove', bone=['handL'], blend=0.008, k=0.022):
                # flared gauntlet cuff (opens toward the elbow) + rolled rim
                sd.cone(pos=[0, 0.035, 0], h=0.05, r1=0.054, r2=0.078, round=0.01)
                sd.cone(op='sub', k=0.008, pos=[0, 0.07, 0], h=0.03, r1=0.05, r2=0.068)
                sd.torus(pos=[0, 0.084, 0], R=0.07, r=0.012, k=0.01)
                # puffy mitten palm
                sd.ellipsoid(pos=[0, -0.07, 0], r=[0.052, 0.086, 0.082], k=0.03)
                # three fat sausage fingers, a little spread and curled toward the palm
                fz, fl = [-0.05, 0.0, 0.05], [0.12, 0.13, 0.115]
                for i in range(3):
                    z, l, sp = fz[i], fl[i], (i - 1) * 0.012
                    sd.worm(pts=[[0.004, -0.13, z], [0.012, -0.13 - l * 0.55, z + sp], [0.03, -0.13 - l, z + sp * 1.6]], r=[0.03, 0.029, 0.027], segs=10, k=0.012)
                    sd.sphere(pos=[0.03, -0.13 - l, z + sp * 1.6], r=0.028, k=0.01)
                # thumb (front, pointing forward-down)
                sd.worm(pts=[[0.012, -0.05, -0.06], [0.02, -0.085, -0.105], [0.034, -0.12, -0.12]], r=[0.03, 0.027, 0.025], segs=10, k=0.016)
            # three stitch lines on the back of the hand (lateral face)
            for z in [-0.032, 0, 0.032]:
                sd.stitch([[-0.06, -0.025, z], [-0.064, -0.07, z * 1.08], [-0.058, -0.112, z * 1.15]], mats=['glove'], color='#B9B2C2', width=0.0028, dash=0.012)


DEF = O(
    id='boss_baron',
    name='Baron Von Static',
    kind='creature',
    rig=O(
        custom=True,
        joints=[
            O(name='base', parent=None, pos=JP.base, tail=[0, 0.3, 0], blend=0.05, gate=0.3),
            O(name='chest', parent='base', pos=rel(JP.chest, JP.base), tail=[0, 0.34, 0], blend=0.08, gate=0.3),
            O(name='head', parent='chest', pos=rel(JP.neck, JP.chest), tail=[0, 0.08, 0], blend=0.03, gate=0.1),
            O(name='shoulderL', parent='chest', pos=rel(JP.shoulder, JP.chest), tail=rel(JP.elbow, JP.shoulder), blend=0.07, gate=0.11),
            O(name='elbowL', parent='shoulderL', pos=rel(JP.elbow, JP.shoulder), tail=rel(JP.hand, JP.elbow), blend=0.06, gate=0.09),
            O(name='handL', parent='elbowL', pos=rel(JP.hand, JP.elbow), tail=[-0.05, -0.2, -0.03], blend=0.04, gate=0.08),
            O(name='shoulderR', parent='chest', pos=rel(neg(JP.shoulder), JP.chest), tail=rel(neg(JP.elbow), neg(JP.shoulder)), blend=0.07, gate=0.11),
            O(name='elbowR', parent='shoulderR', pos=rel(neg(JP.elbow), neg(JP.shoulder)), tail=rel(neg(JP.hand), neg(JP.elbow)), blend=0.06, gate=0.09),
            O(name='handR', parent='elbowR', pos=rel(neg(JP.hand), neg(JP.elbow)), tail=[0.05, -0.2, -0.03], blend=0.04, gate=0.08),
        ],
        bindPose=O(),
        dims=O(height=1.2, headH=0.52),
    ),
    bake=O(voxel=0.0046, tris=23000, aoStrength=0.85, aoReach=0.1),
    rim=O(color='#C9A0FF', strength=0.45),
    materials=O(
        tux=O(color=TUX, rough=0.42, spec=0.55, fuzz=0.25, wrap=0.55, cav=0.5),
        lapel=O(color='#7A3F80', rough=0.26, spec=0.95, wrap=0.55, cav=0.4),
        shirt=O(color='#F4F1E8', rough=0.6, fuzz=0.3, wrap=0.6, cav=0.45),
        jabot=O(color='#FFFDF6', rough=0.52, fuzz=0.45, wrap=0.65, cav=0.55),
        gold=O(color='#E8B84A', metal=1, rough=0.2),
        cape=O(color='#1A1522', rough=0.45, spec=0.5, fuzz=0.3, wrap=0.5, cav=0.45),
        lining=O(color='#7E2250', rough=0.28, spec=0.9, wrap=0.6, cav=0.35),
        glove=O(color='#FBF8F0', rough=0.5, fuzz=0.12, wrap=0.62, spec=0.45, cav=0.65),
        button=O(color='#2C2440', rough=0.2, spec=0.9, cav=0.3),
        flower=O(color='#E83A4A', rough=0.5, fuzz=0.4, wrap=0.6, cav=0.6),
        leaf=O(color='#3E8A3A', rough=0.5, wrap=0.6, cav=0.5),
    ),
    sculpt=sculpt,
)
