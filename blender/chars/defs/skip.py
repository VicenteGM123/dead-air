"""SKIP KOWALSKI v1 — 17-year-old WZTV 13 floor runner / cable wrangler (GDD §4, ref docs/ref/hero_crewkid.png).
(Port of src/art/chars/skip.js.) Built with the same recipes as the approved Duke: SIMPLIFY + EXAGGERATE.
  - Big round kid head (~31 % of 1.60 m with the cap), huge brown eyes behind big square black glasses, freckles,
    a small crooked smile, friendly brows.
  - Blue/white "13" trucker cap: tall white front panel with the 13 badge (canvas decal), blue crown + button, arched
    blue bill. Curly brown hair bursting out under the cap: clustered round curls + C-hook curls at the edges.
  - Headphones round the neck (cups on the collar, band behind the neck), a coiled cord down to the walkie pouch.
  - Royal-blue open short-sleeve shirt (a real shell layer over the white tee), pointed collar, white buttons,
    white cuff bands, chest pocket with the clip-on "WZTV 13 CREW" badge (canvas card).
  - Brown belt + silver buckle, black walkie pouches, plaid bell-bottoms, blue canvas high-tops with white soles.
Layout: world coords for torso/pants (feet y=0, facing -z), bone-local coords for limbs and head. Heights from ctx.J.
Character right = +x (joints *R), left = -x.
"""
import math

import numpy as np

from ..jsutil import O, nz
from ._face import EYE_DEFAULTS
from ._sculpt import prism, cartoonMouth, onEllipsoid
from .roxy import mergeGeos

SKIN = '#F6C29E'
HAIR = '#7A4424'
BROW = '#63381E'
BLUE = '#2F5BD3'      # WZTV Blue (GDD §3.2)
CAPWHITE = '#F4F1E8'  # Cap White

# Head-local anchors (origin = head joint, y up, -z forward).
EYE = O(EYE_DEFAULTS, x=0.063, y=0.232, z=-0.13, r=0.044, iris='#8A4E24', irisSize=0.64, pupilSize=0.44,
        lid='#F2B792', lidOpen=1.0, lowerLid=0.6, lidScale=1.04, yaw=0.07, glint=1.15)
# The head is sculpted in these units and scaled by HS about the head joint (sculpt, brows and attachments).
HS = 1.1
SKULL = O(c=[0, 0.268, 0.012], r=[0.158, 0.178, 0.166])
# Mouth per expression (cartoonMouth): a small crooked smile, the +x corner higher.
MOUTH = O(
    base=O(y=0.098, w=0.043, h=0.019, top=0.093, R=0.058, teeth=0.55, roll=0.045, clip=True),
    smile=O(y=0.097, w=0.052, h=0.028, top=0.09, R=0.06, teeth=0.68, roll=0.05, clip=True),
    frown=O(y=0.094, w=0.036, h=0.012, top=0.1, R=-0.09, teeth=0.4, tongue=False, roll=0.02, clip=True),
    o_mouth=O(y=0.092, w=0.026, h=0.027, top=0.12, R=None, teeth=0.35, roll=0.001, clip=True),
)
# Cap: brim line y = CAP.y0 - CAP.tilt * z (front higher than the back), badge disc on the front panel.
CAP = O(y0=0.318, tilt=0.15)
BADGE = O(pos=[0, 0.408, -0.19], n=[0, 0.34, -1], r=0.046)


# ------------------------------------------------------------------------------------------------------------
def torsoShapes(sd, Y):
    sd.ellipsoid(pos=[0, Y.sh - 0.075, 0.0], r=[0.168, 0.125, 0.112])       # chest
    sd.ellipsoid(pos=[0, Y.hip + 0.11, 0.004], r=[0.146, 0.112, 0.108])     # belly
    sd.ellipsoid(pos=[0, Y.sh - 0.01, 0.01], r=[0.178, 0.048, 0.09])        # shoulder yoke
    sd.ellipsoid(pos=[0, Y.sh - 0.07, -0.022], r=[0.124, 0.085, 0.085])     # chest front


def headBase(sd, ex):
    smile = 1 if ex == 'smile' else 0
    sd.ellipsoid(pos=SKULL.c, r=SKULL.r)                                                   # cranium
    sd.ellipsoid(pos=[0, 0.214, -0.058], r=[0.138, 0.098, 0.098], k=0.06)                # soft face mask
    sd.ellipsoid(pos=[0, 0.148, -0.034], r=[0.126, 0.106, 0.128], k=0.07)                # round jaw
    sd.ellipsoid(pos=[0, 0.072, -0.082], r=[0.046, 0.034, 0.042], k=0.05)                # small pointed chin
    sd.mirrorX(lambda: sd.sphere(pos=[0.074, 0.142 + smile * 0.012, -0.102 - smile * 0.004], r=0.05 + smile * 0.004, k=0.05))  # cheeks
    # button nose, a touch upturned
    sd.capsule(a=[0, 0.228, -0.152], b=[0, 0.19, -0.18], r=0.015, k=0.02)
    sd.sphere(pos=[0, 0.176, -0.19], r=0.024, k=0.016)
    sd.mirrorX(lambda: sd.sphere(pos=[0.018, 0.168, -0.178], r=0.013, k=0.012))

    # ears (stick out a little between the curls)
    @sd.mirrorX
    def _():
        sd.ellipsoid(pos=[0.154, 0.19, 0.018], r=[0.026, 0.046, 0.034], rot=[0, -0.35, 0.16], k=0.014)
        sd.ellipsoid(op='sub', k=0.008, pos=[0.17, 0.188, 0.014], r=[0.012, 0.027, 0.018], rot=[0, -0.35, 0.16])


def axisRot(d):
    """Euler XYZ (beta = 0) that turns local +y into the direction d (cylinders / cups facing d)."""
    l = math.hypot(*d)
    x, y, z = d[0] / l, d[1] / l, d[2] / l
    return [math.atan2(z, y), 0, -math.asin(x)]


def surfZ(sd, G, x, y):
    sd.snap(G, [x, y, -0.1])
    a, b = -0.35, 0
    for _ in range(40):
        m = (a + b) / 2
        w = sd.toWorld([x, y, m])
        if G.fn(w[0], w[1], w[2]) > 0:
            a = m
        else:
            b = m
    return (a + b) / 2


def headShapes(sd, ex):
    headBase(sd, ex)
    m = MOUTH[ex] if ex in MOUTH else MOUTH.base
    G = sd.guide({'k': 0.07}, lambda: headBase(sd, ex))
    cartoonMouth(sd, O(m, z=surfZ(sd, G, 0, m.y)))


def browShape(sd, s):
    # above the glasses: soft friendly arch, inner end low, the right brow (+x) a bit higher (curious kid)
    with sd.bone('head'), sd.frame(scale=HS):
        H = sd.guide({'k': 0.07}, lambda: headBase(sd, None))
        up = 0.006 if s > 0 else 0
        P = [[0.024, 0.306 + up], [0.048, 0.318 + up], [0.074, 0.323 + up], [0.1, 0.314 + up]]
        # lifts = the brow's half thickness + ~1 mm: a brow part that sinks into the skin hands its sideways normals to
        # the skin vertices under it (the baker shades the body with body + parts): pale wedges on the forehead
        pts = sd.snapAll(H, [[x * s, y, -0.2] for x, y in P], [0.0046, 0.0054, 0.0053, 0.0036])
        sd.worm(mat='brow', pts=pts, r=[0.0078, 0.0098, 0.0094, 0.0055], flat=0.45, up=[0, 0.25, -1], segs=14)


def capCrown(sd):
    """Cap crown (without the brim cut) — shared by the cap and the hair (the hair is cut by it)."""
    sd.ellipsoid(pos=[0, 0.325, 0.012], r=[0.17, 0.162, 0.182])
    sd.ellipsoid(pos=[0, 0.37, -0.075], r=[0.145, 0.12, 0.12], k=0.05)        # tall trucker front panel


def capPlane(sd, o=None):
    o = O(o or {})
    n = math.hypot(1, CAP.tilt)
    sd.plane(op='int', k=nz(o.k, 0.006), n=[0, -1 / n, -CAP.tilt / n], d=-(CAP.y0 + (o.lower or 0)) / n)


# ------------------------------------------------------------------------------------------------------------
# Attachment helpers (canvas + three geometry through b.THREE).
def roundRectShape(T3, w, h, r):
    s = T3.Shape()
    s.moveTo(-w + r, -h)
    s.lineTo(w - r, -h)
    s.quadraticCurveTo(w, -h, w, -h + r)
    s.lineTo(w, h - r)
    s.quadraticCurveTo(w, h, w - r, h)
    s.lineTo(-w + r, h)
    s.quadraticCurveTo(-w, h, -w, h - r)
    s.lineTo(-w, -h + r)
    s.quadraticCurveTo(-w, -h, -w + r, -h)
    return s


def squareGlasses(b, o):
    """Big square glasses: one merged frame mesh (rims, bridge, temples) + one merged lens mesh (2 draw calls)."""
    o = O(o)
    T3 = b.THREE
    E = o.eye
    w, h, t, r = o.w, o.h, o.thick, o['round']
    zf = o.z
    wrap = nz(o.wrap, 0.1)
    dy = o.dy or 0
    frames, lenses = [], []
    for s in (1, -1):
        cx = s * E.x
        outer = roundRectShape(T3, w, h, r)
        inner = roundRectShape(T3, w - t, h - t, max(0.004, r - t * 0.6))
        outer.holes.append(T3.Path(inner.getPoints(12)))
        g = T3.ExtrudeGeometry(outer, {'depth': o.depth, 'bevelEnabled': True, 'bevelThickness': o.depth * 0.35, 'bevelSize': t * 0.22, 'bevelSegments': 2, 'curveSegments': 10})
        g.translate(0, 0, -o.depth / 2)
        g.rotateY(-s * wrap)
        g.translate(cx, E.y + dy, zf)
        frames.append(g)
        lg = T3.ShapeGeometry(roundRectShape(T3, w - t * 0.7, h - t * 0.7, max(0.004, r - t * 0.5)), 8)
        lg.rotateY(-s * wrap)
        lg.translate(cx, E.y + dy, zf + 0.001)
        lenses.append(lg)
        # temple: from the outer top corner back over the ear
        ca, sa = math.cos(wrap), math.sin(wrap)
        ax, az = cx + s * w * ca, zf + w * sa
        tA = T3.Vector3(ax, E.y + dy + h * 0.55, az + 0.004)
        tB = T3.Vector3(s * o.templeX, E.y + dy + h * 0.5, az + 0.07)
        tC = T3.Vector3(s * (o.templeX + 0.004), E.y + dy + h * 0.2, o.earZ)
        frames.append(T3.TubeGeometry(T3.CatmullRomCurve3([tA, tB, tC]), 14, t * 0.36, 6))
    bl = T3.Vector3(-E.x + w * 0.96, E.y + dy + h * 0.3, zf)
    br = T3.Vector3(E.x - w * 0.96, E.y + dy + h * 0.3, zf)
    frames.append(T3.TubeGeometry(T3.CatmullRomCurve3([bl, T3.Vector3(0, E.y + dy + h * 0.42, zf - 0.006), br]), 10, t * 0.42, 6))
    frameMat = b.mat(color=o.color or '#1B1520', rough=0.28, rim=0.18, envIntensity=0.9)
    # lenses barely there (a faint reflection): the big eyes must keep their warm color behind the glass
    glassMat = b.mat(color='#EAF4FF', rough=0.05, transparent=True, opacity=0.045, envIntensity=0.55, rim=0.08, rimColor='#FFFFFF')
    b.mesh(o.parent or 'head', mergeGeos(T3, frames), frameMat, O(name='glassesFrame'))
    lens = b.mesh(o.parent or 'head', mergeGeos(T3, lenses), glassMat, O(name='glassesLens', cast=False))
    lens.renderOrder = 3


def canvasTex(key, W, H, paint):
    from ..face import CharTexture
    from dalib.canvas2d import Canvas
    cv = Canvas(W, H)
    paint(cv.getContext('2d'), W, H)
    tex = CharTexture(cv, key, repeat=False, ns='ch')
    tex.anisotropy = 4
    return tex


FONT = '"Arial Black", Impact, sans-serif'


def sculpt(sd, ctx):
    J = ctx.J
    Y = O(hip=J['hips'].pos[1], sh=J['shoulderL'].pos[1], neck=J['neck'].pos[1], head=J['head'].pos[1])

    # ---------------- neck ----------------
    with sd.group(name='neck', mat='skin', bone='torso', k=0.03):
        sd.capsule(a=[0, Y.sh - 0.04, 0.008], b=[0, Y.head + 0.07, 0.004], r=0.054)

    # ---------------- tee (the torso) + open shirt (a shell layer over it, open down the front) ----------------
    teeFrame = sd.patternFrame(pos=[0, 0.85, 0], mode='cyl', radius=0.14)
    sd.group({'name': 'tee', 'mat': 'tee', 'bone': 'torso', 'k': 0.06, 'pframe': teeFrame, 'blend': 0.012}, lambda: torsoShapes(sd, Y))
    # crew neckline of the tee: a painted skin crescent at the base of the neck
    sd.paint({'mat': 'skin', 'soft': 0.0015, 'only': ['tee']}, lambda: sd.ellipsoid(pos=[0, Y.sh + 0.045, -0.06], r=[0.05, 0.03, 0.08]))

    # shirt panels: shell of the torso minus the open front (tee strip widening toward the collar) and minus the hem
    def OPEN(x0, x1):
        return [[-x0, Y.hip - 0.2], [x0, Y.hip - 0.2], [x1, Y.sh + 0.2], [-x1, Y.sh + 0.2]]
    with sd.group(name='shirt', mat='shirt', bone='torso', blend=0.004, k=0):
        sd.group({'offset': 0.004, 'shell': 0.0062, 'k': 0.06, 'pframe': teeFrame}, lambda: torsoShapes(sd, Y))
        prism(sd, OPEN(0.05, 0.062), {'op': 'sub', 'max': -0.02, 'k': 0.006, 'blend': 0.004})
        sd.box(op='sub', k=0.006, pos=[0, Y.hip - 0.2, 0], size=[0.4, 0.2 + 0.01, 0.4])   # hem at hip + 1 cm
    # buttons down the right panel (+x), button holes implied on the left panel
    shirtG = sd.guide({'k': 0.06, 'offset': 0.0102}, lambda: torsoShapes(sd, Y))
    for i in range(4):
        by = Y.sh - 0.075 - i * 0.068
        t = (by - (Y.hip - 0.2)) / (Y.sh + 0.2 - (Y.hip - 0.2))
        bx = 0.05 + (0.062 - 0.05) * t + 0.016
        sd.ellipsoid(mat='button', bone='torso', rigid=True, pos=sd.snap(shirtG, [bx, by, -0.2], 0.0006), r=[0.0105, 0.0105, 0.0055], k=0.002)
    # chest pocket (character's left, -x): a flat patch with a flap, stitched
    PK = O(x=-0.086, y=Y.sh - 0.07)
    with sd.group(name='pocket', mat='shirt', bone='torso', blend=0.003, k=0):
        sd.group({'offset': 0.0102, 'shell': 0.0032, 'k': 0.06}, lambda: torsoShapes(sd, Y))
        prism(sd, [[PK.x - 0.036, PK.y - 0.05], [PK.x + 0.036, PK.y - 0.05], [PK.x + 0.036, PK.y + 0.03], [PK.x - 0.036, PK.y + 0.03]], {'op': 'int', 'max': -0.02, 'k': 0.008})
    pz = -0.3
    sd.stitch([[PK.x - 0.03, PK.y + 0.02, pz], [PK.x - 0.03, PK.y - 0.044, pz], [PK.x + 0.03, PK.y - 0.044, pz], [PK.x + 0.03, PK.y + 0.02, pz]], mats=['shirt'], color='#1E3E9E', width=0.0011, smooth=False)
    sd.stitch([[PK.x - 0.033, PK.y + 0.012, pz], [PK.x + 0.033, PK.y + 0.012, pz]], mats=['shirt'], color='#1E3E9E', width=0.0011, smooth=False)
    # placket stitch lines along both open edges
    sd.mirrorX(lambda: sd.stitch([[0.058, Y.hip + 0.01, -0.3], [0.062, Y.sh - 0.02, -0.3], [0.066, Y.sh + 0.03, -0.3]], mats=['shirt'], color='#1E3E9E', width=0.0011))

    # ---------------- collar: flat pointed flaps lying open on the shoulders ----------------
    FLAP = [[0.05, Y.sh + 0.05], [0.1, Y.sh + 0.05], [0.13, Y.sh - 0.01], [0.085, Y.sh - 0.085], [0.052, Y.sh - 0.012]]
    with sd.group(name='collar', mat='shirt', bone='torso', blend=0.004, k=0.01):
        with sd.group(k=0.004):
            with sd.frame(pos=[0, Y.sh + 0.052, 0.012], rot=[-0.3, 0, 0]):
                sd.cylinder(r=0.075, h=0.012, round=0.0055)
                sd.cylinder(op='sub', k=0.004, r=0.063, h=0.04)
            prism(sd, [[0, Y.sh - 0.06], [0.07, Y.sh + 0.2], [-0.07, Y.sh + 0.2]], {'op': 'sub', 'blend': 0.006, 'max': -0.01, 'k': 0.006})
        with sd.group(k=0, blend=0.01):
            sd.group({'offset': 0.0112, 'shell': 0.0052, 'k': 0.06}, lambda: torsoShapes(sd, Y))
            sd.group({'op': 'int', 'blend': 0.004, 'k': 0}, lambda: sd.mirrorX(lambda: prism(sd, FLAP, {'max': -0.01, 'k': 0.012})))

    @sd.mirrorX
    def _():
        e = FLAP

        def lerp(a, b, t):
            return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
        sd.stitch([[x + 0.006, y + 0.004, -0.25] for x, y in [lerp(e[4], e[3], 0.12), lerp(e[4], e[3], 0.88)]], mats=['shirt'], color='#1E3E9E', width=0.0011)
        sd.stitch([[x - 0.006, y + 0.002, -0.25] for x, y in [lerp(e[3], e[2], 0.12), lerp(e[3], e[2], 0.88)]], mats=['shirt'], color='#1E3E9E', width=0.0011)

    # ---------------- headphones round the neck (cups on the collar, band behind the neck) ----------------
    with sd.group(name='phones', mat='phones', bone='chest', rigid=True, blend=0.004, k=0.008):
        @sd.mirrorX
        def _():
            # cups resting on the collar bones, outer faces turned out / forward / up, cushions against the shirt
            with sd.frame(pos=[0.094, Y.sh + 0.038, -0.05], rot=axisRot([0.55, 0.45, -0.7])):
                sd.cylinder(r=0.047, h=0.019, round=0.01)                                    # cup shell
                sd.cylinder(mat='cushion', pos=[0, -0.022, 0], r=0.042, h=0.01, round=0.009, k=0.003)  # cushion
                sd.cylinder(pos=[0, 0.02, 0], r=0.028, h=0.007, round=0.006, k=0.004)      # cap
            # yoke: short stem from the band into the cup
            sd.capsule(a=[0.078, Y.sh + 0.07, -0.015], b=[0.092, Y.sh + 0.05, -0.045], r=0.0085, k=0.006)
        # band: an arc behind the neck (centered on local +z = back), back end higher
        with sd.frame(pos=[0, Y.sh + 0.062, 0.004], rot=[-0.35, 0, 0]):
            sd.arc(R=0.08, r=0.0098, angle=math.pi * 1.22)
    # coiled cord: from the right cup down the front to the walkie pouch on the right hip (a chunky toy spring)
    A, Bp = [0.118, Y.sh + 0.005, -0.085], [0.132, Y.hip + 0.03, -0.12]
    turns, R, n = 11, 0.0105, 11 * 8
    axis = [Bp[0] - A[0], Bp[1] - A[1], Bp[2] - A[2]]
    pts = []
    for i in range(n + 1):
        t = i / n
        a = t * turns * math.pi * 2
        sag = math.sin(t * math.pi) * 0.035   # hangs away from the belly
        pts.append([A[0] + axis[0] * t + math.cos(a) * R + sag * 0.3, A[1] + axis[1] * t, A[2] + axis[2] * t + math.sin(a) * R - sag])
    with sd.group(name='cord', mat='phones', bone='torso', blend=0.004, k=0):
        for s in range(0, n, 16):
            sd.worm(pts=pts[s:min(n, s + 17) + 1], r=0.0048, segs=24)

    # ---------------- head ----------------
    with sd.bone('head'), sd.frame(scale=HS):
        head = sd.group({'name': 'head', 'mat': 'skin', 'k': 0.07, 'blend': 0.02}, lambda: headShapes(sd, sd.expr))
        sd.paint({'color': '#F29C82', 'soft': 0.02, 'strength': 0.45, 'only': ['skin']}, lambda: sd.sphere(pos=[0, 0.178, -0.212], r=0.018))
        sd.paint({'color': '#F4A08A', 'soft': 0.035, 'strength': 0.55, 'only': ['skin']}, lambda: sd.mirrorX(lambda: sd.sphere(pos=[0.084, 0.148, -0.13], r=0.024)))
        sd.paint({'color': '#F0A088', 'soft': 0.015, 'strength': 0.4, 'only': ['skin']}, lambda: sd.mirrorX(lambda: sd.ellipsoid(pos=[0.17, 0.19, 0.016], r=[0.02, 0.048, 0.034])))
        # freckles: soft dots across the cheeks and the nose bridge
        with sd.paint(color='#C77A55', soft=0.0022, strength=0.75, only=['skin']):
            F = [[0.052, 0.176], [0.068, 0.168], [0.084, 0.178], [0.06, 0.155], [0.077, 0.152], [0.094, 0.162], [0.018, 0.196]]

            @sd.mirrorX
            def _():
                for x, y in F:
                    sd.ellipsoid(pos=[x, y, -0.15], r=[0.0046, 0.0046, 0.07])

        # ---- cap: blue crown + tall white front panel, top button, arched blue bill, raised 13 badge disc ----
        with sd.group(name='cap', mat='cap', blend=0.004, k=0):
            with sd.group(k=0.03):
                capCrown(sd)
                capPlane(sd)
            sd.sphere(pos=[0, 0.488, -0.006], r=0.015, k=0.006)                        # top button
            # arched bill: a thick cap of a big sphere centered below/behind it (slopes down to the tip and the sides)
            with sd.group(name='bill', mat='bill', k=0, blend=0.01):
                sd.sphere(pos=[0, 0.352 - 0.36, -0.1], r=0.36, shell=0.0078)
                with sd.group(op='int', k=0):
                    prism(sd, [[-0.152, -0.08], [-0.147, -0.2], [-0.107, -0.285], [0, -0.325], [0.107, -0.285], [0.147, -0.2], [0.152, -0.08]], {'axis': 'y', 'k': 0.022})
                sd.plane(op='int', k=0.004, n=[0, -1, 0], d=-0.26)
            sd.frame({'pos': BADGE.pos, 'rot': [math.atan2(BADGE.n[1], -BADGE.n[2]) - math.pi / 2, 0, 0]}, lambda:
                     sd.cylinder(mat='capWhite', r=BADGE.r + 0.004, h=0.006, round=0.004, k=0.004))
        # white front panel: the wedge between the two front seams (top button -> brim at ~60 deg azimuth)
        with sd.paint(mat='capWhite', soft=0.001, only=['cap']):
            with sd.group(k=0.004):
                sd.plane(n=[0.513, 0.0765, 0.855], d=0.0332)
                sd.plane(op='int', k=0.004, n=[-0.513, 0.0765, 0.855], d=0.0332)

        # seams on the crown (front-panel edges + back + sides)
        def cs(az):
            return [onEllipsoid(O(c=[0, 0.325, 0.012], r=[0.178, 0.168, 0.19]), az, el) for el in range(4, 85, 10)]
        for az in [118, 242, 180]:
            sd.stitch(cs(az), mats=['cap'], color='#1E3E9E', width=0.0012)

        # ---- curly hair bursting out under the cap: a soft mass + a few big round curls + C-hook curls ----
        def hflow(x, y, z):
            return [x * 1.2, -1, np.where(np.asarray(z) > 0, 0.5, -0.2)]
        with sd.group(name='hair', mat='hair', flow=hflow, blend=0.006):
            with sd.group(k=0.045):
                with sd.group(k=0.04):
                    sd.ellipsoid(pos=[0, 0.255, 0.022], r=[0.178, 0.155, 0.176])
                    sd.ellipsoid(op='sub', k=0.035, pos=[0, 0.19, -0.2], r=[0.138, 0.2, 0.17])   # face opening
                    sd.plane(op='int', k=0.03, n=[0, -0.8, -0.6], d=-0.1)                         # nape / jaw line
                # big round curls (head-local centers): three big puffs per side + three at the back: a scalloped
                # molded-toy silhouette, not a bunch of grapes
                C = [
                    [0.152, 0.292, -0.07, 0.046], [0.176, 0.225, 0.035, 0.07], [0.15, 0.14, 0.1, 0.062], [0.1, 0.2, 0.158, 0.07],
                ]

                @sd.mirrorX
                def _():
                    for x, y, z, r in C:
                        sd.sphere(pos=[x, y, z], r=r)
                sd.sphere(pos=[0, 0.165, 0.168], r=0.07)

            # C-hook curls flicking out of the silhouette (lower sides, back, one on each side of the forehead)
            def hook(pos, rot, R, r):
                return sd.arc(pos=pos, rot=rot, R=R, r=r, angle=math.pi * 1.25, k=0.012)

            @sd.mirrorX
            def _():
                hook([0.2, 0.13, 0.04], [0.2, 1.3, 2.1], 0.028, 0.02)          # flick at the jaw line
                sd.sphere(pos=[0.12, 0.095, 0.13], r=0.042, k=0.02)             # soft round curl at the nape
                hook([0.122, 0.33, -0.148], [1.3, 0.3, -0.5], 0.02, 0.014)      # curl peeking under the bill over the forehead

    # ---------------- belt + pants ----------------
    pantFrame = sd.patternFrame(pos=[0, Y.hip, 0], mode='cyl', radius=0.14)
    with sd.group(name='pelvis', mat='plaid', bone='torso', k=0.03, pframe=pantFrame):
        sd.ellipsoid(pos=[0, Y.hip + 0.02, 0.006], r=[0.143, 0.102, 0.112])
    BELT_Y = Y.hip + 0.07
    with sd.group(name='belt', mat='leather', bone='torso'):
        sd.ellipsoid(pos=[0, BELT_Y, 0.004], r=[0.149, 0.112, 0.114], offset=0.0045)
        sd.box(op='int', k=0.004, pos=[0, BELT_Y, 0], size=[0.3, 0.018, 0.3], round=0.002)
    # silver frame buckle (rectangle with a hole + prong bar)
    with sd.group(name='buckle', mat='silver', bone='hips', rigid=True, k=0.003):
        sd.box(pos=[0, BELT_Y, -0.117], size=[0.03, 0.023, 0.006], round=0.004)
        sd.box(op='sub', k=0.002, pos=[0, BELT_Y, -0.125], size=[0.019, 0.013, 0.01], round=0.003)
        sd.box(mat='leather', pos=[0, BELT_Y, -0.117], size=[0.02, 0.014, 0.004], round=0.002)
    # walkie pouches: two on the right hip (+x, red + yellow walkie tops), one on the left
    with sd.group(name='pouches', mat='pouch', bone='hips', rigid=True, blend=0.004, k=0.004):
        def pouch(x, z, ry, h, top):
            with sd.frame(pos=[x, BELT_Y - 0.035, z], rot=[0, ry, 0]):
                sd.box(size=[0.034, h, 0.022], round=0.012)
                sd.box(pos=[0, h - 0.012, -0.004], size=[0.036, 0.016, 0.022], round=0.01, k=0.004)   # flap
                sd.sphere(mat='silver', pos=[0, h - 0.018, -0.026], r=0.0055, k=0.002)               # snap
                if top:
                    sd.box(mat='plastic', color=top, pos=[0.004, h + 0.022, 0.004], size=[0.022, 0.018, 0.014], round=0.008, k=0.003)
        pouch(0.135, -0.075, -0.75, 0.05, '#E23B3B')
        pouch(0.155, -0.01, -1.2, 0.05, '#F4C22E')
        pouch(-0.148, -0.045, 1.0, 0.055, '#F4C22E')

    @sd.mirrorX
    def _():
        with sd.bone('hipL'):
            fr = sd.patternFrame(pos=[0, -0.3, 0], mode='cyl', radius=0.085)
            with sd.group(mat='plaid', k=0.05, pframe=fr, blend=0.01):
                sd.roundCone(a=[0.01, 0.04, 0.004], b=[0, -0.28, 0.004], ra=0.088, rb=0.068)
                sd.sphere(pos=[0, -0.295, 0.002], r=0.068)
                # flare from the knee to a hem at ankle height (the high-tops show below it)
                sd.cone(pos=[-0.018, -0.425, 0.0], h=0.132, r1=0.136, r2=0.068, round=0.011, scale=[0.84, 1, 1])
            out = [[-0.094, 0.05, 0], [-0.088, -0.13, 0], [-0.072, -0.29, 0], [-0.088, -0.4, 0], [-0.112, -0.5, 0], [-0.13, -0.548, 0]]
            sd.stitch(out, mats=['plaid'], color='#7A3E1C', width=0.0012)
            hem = []
            for i in range(29):
                a = (i / 28) * math.pi * 2
                hem.append([-0.014 + math.sin(a) * 0.118, -0.545, math.cos(a) * 0.13])
            sd.stitch(hem, mats=['plaid'], color='#7A3E1C', width=0.0012, smooth=False)
        with sd.bone('footL'), sd.frame(scale=1.14, pos=[0, 0.01, -0.012]):
            # blue canvas high-top: upper, white rubber sole band + toe cap, laces, ankle collar
            def upper():
                sd.ellipsoid(pos=[0, -0.026, -0.108], r=[0.064, 0.046, 0.13])
                sd.ellipsoid(pos=[0, -0.02, 0.016], r=[0.052, 0.048, 0.056])
                sd.ellipsoid(pos=[0, 0.012, -0.02], r=[0.05, 0.06, 0.062])          # high-top ankle
            sd.group({'mat': 'canvas', 'k': 0.035}, upper)
            with sd.group(mat='rubber', k=0.0):
                sd.group({'offset': 0.005, 'k': 0.035}, upper)
                sd.box(op='int', k=0.003, pos=[0, -0.06, -0.045], size=[0.1, 0.011, 0.26], round=0.004)
            # toe cap
            with sd.group(mat='rubber', k=0.0, blend=0.002):
                sd.group({'offset': 0.003, 'k': 0.035}, upper)
                sd.ellipsoid(op='int', k=0.006, pos=[0, -0.04, -0.235], r=[0.075, 0.042, 0.06])
            # laces: three soft white bars across the tongue
            for i in range(3):
                z, y = -0.085 + i * 0.03, 0.008 + i * 0.012
                sd.capsule(mat='rubber', a=[-0.024, y, z], b=[0.024, y, z], r=0.0058, k=0.004)
    # fly + pocket stitches
    sd.stitch([[0, Y.hip + 0.045, -0.118], [0.0, Y.hip - 0.035, -0.114], [-0.028, Y.hip - 0.065, -0.104]], mats=['plaid'], color='#7A3E1C', width=0.0012)
    sd.mirrorX(lambda: sd.stitch([[0.06, Y.hip + 0.05, -0.118], [0.088, Y.hip + 0.01, -0.104], [0.128, Y.hip - 0.01, -0.07]], mats=['plaid'], color='#7A3E1C', width=0.0012))

    # ---------------- arms ----------------
    @sd.mirrorX
    def _():
        with sd.bone('shoulderL'):
            with sd.group(mat='shirt', k=0.035, blend=0.035):
                sd.roundCone(a=[0.012, -0.025, 0], b=[0, -0.12, 0], ra=0.064, rb=0.066)
            # white cuff band at the sleeve end
            with sd.group(mat='tee', k=0.006, blend=0.004):
                sd.cylinder(pos=[0, -0.13, 0], r=0.069, h=0.013, round=0.008)
            sd.roundCone(mat='skin', a=[0, -0.1, 0], b=[0, -0.21, 0], ra=0.046, rb=0.043, k=0.01)
        with sd.bone('elbowL'):
            sd.roundCone(mat='skin', a=[0, 0.03, 0], b=[0, -0.215, 0], ra=0.044, rb=0.038, k=0.01)
        with sd.bone('handL'), sd.frame(scale=1.2, pos=[0, 0.006, 0]):
            with sd.group(mat='skin', k=0.01, blend=0.012):
                sd.roundCone(a=[0, 0.012, 0], b=[0.002, -0.03, 0], ra=0.032, rb=0.038, k=0.015)
                sd.box(pos=[0.002, -0.055, 0], size=[0.021, 0.048, 0.046], round=0.02, k=0.015)
                sd.ellipsoid(pos=[0.012, -0.045, -0.03], r=[0.017, 0.029, 0.021], k=0.012)
                fz, fl = [-0.034, -0.011, 0.012, 0.034], [0.062, 0.07, 0.066, 0.055]
                for i in range(4):
                    z, l, sp = fz[i], fl[i], (i - 1.5) * 0.003
                    sd.worm(pts=[[0.002, -0.09, z], [0.008, -0.09 - l * 0.55, z + sp], [0.018, -0.09 - l, z + sp * 1.5]], r=[0.0104, 0.01, 0.0094], k=0.004, segs=8)
                    sd.sphere(pos=[-0.008, -0.09, z], r=0.0105, k=0.008)
                sd.worm(pts=[[0.012, -0.028, -0.038], [0.022, -0.054, -0.06], [0.03, -0.077, -0.064]], r=[0.015, 0.0125, 0.0114], k=0.01, segs=8)
            sd.paint({'color': '#F2A987', 'soft': 0.02, 'strength': 0.42, 'only': ['skin']}, lambda: sd.sphere(pos=[0.004, -0.07, 0], r=0.11))


def attachments(b, ctx=None):
    T3 = b.THREE
    # head attachments live in a group scaled by HS about the head joint (same units as the sculpt)
    HG = T3.Group()
    HG.name = 'headScaled'
    HG.scale.setScalar(HS)
    b.joint('head').add(HG)
    b.eyes(O(EYE, x=EYE.x * HS, y=EYE.y * HS, z=EYE.z * HS, r=EYE.r * HS))
    squareGlasses(b, O(parent=HG, eye=EYE, w=0.062, h=0.052, thick=0.0115, round=0.02, depth=0.007, z=-0.196, dy=0.002, wrap=0.12, templeX=0.162, earZ=0.03))

    # cap badge: white disc, red ring, blue "13" (on the raised disc of the front panel)
    def capPaint(g, W, H):
        g.fillStyle = '#F4F1E8'
        g.beginPath()
        g.arc(W / 2, W / 2, W / 2, 0, math.pi * 2)
        g.fill()
        g.strokeStyle = '#E23B3B'
        g.lineWidth = W * 0.075
        g.beginPath()
        g.arc(W / 2, W / 2, W * 0.4, 0, math.pi * 2)
        g.stroke()
        g.fillStyle = '#2F5BD3'
        g.font = '900 %dpx %s' % (int(math.floor(W * 0.46 + 0.5)), FONT)
        g.textAlign = 'center'
        g.textBaseline = 'middle'
        g.fillText('13', W / 2, W * 0.53)
    capTex = canvasTex('skip|capBadge', 256, 256, capPaint)
    N = T3.Vector3(*BADGE.n).normalize()
    decal = b.mesh(HG, T3.CircleGeometry(BADGE.r, 40), b.mat(map=capTex, rough=0.6, rim=0.15, wrap=0.5), O(name='capBadge', cast=False))
    decal.position.set(BADGE.pos[0] + N.x * 0.0068, BADGE.pos[1] + N.y * 0.0068, BADGE.pos[2] + N.z * 0.0068)
    decal.rotation.set(math.asin(N.y), math.pi, 0)   # +z face turned to -z (reads correctly), tilted up to the panel

    # clip-on crew badge on the chest pocket (chest joint local)
    def cardPaint(g, W, H):
        g.fillStyle = '#FBF8F0'
        g.fillRect(0, 0, W, H)
        g.fillStyle = '#2F5BD3'
        g.font = '900 %dpx %s' % (int(math.floor(W * 0.27 + 0.5)), FONT)
        g.textAlign = 'center'
        g.textBaseline = 'middle'
        g.fillText('WZTV', W / 2, H * 0.16)
        g.fillStyle = '#E23B3B'
        g.fillRect(W * 0.08, H * 0.27, W * 0.84, H * 0.035)
        g.fillStyle = '#F4F1E8'
        g.strokeStyle = '#E23B3B'
        g.lineWidth = W * 0.05
        g.beginPath()
        g.arc(W / 2, H * 0.52, W * 0.2, 0, math.pi * 2)
        g.fill()
        g.stroke()
        g.fillStyle = '#2F5BD3'
        g.font = '900 %dpx %s' % (int(math.floor(W * 0.22 + 0.5)), FONT)
        g.fillText('13', W / 2, H * 0.535)
        g.fillStyle = '#2F5BD3'
        g.font = '900 %dpx %s' % (int(math.floor(W * 0.19 + 0.5)), FONT)
        g.fillText('CREW', W / 2, H * 0.84)
    card = canvasTex('skip|crewBadge', 256, 384, cardPaint)
    cw, chh = 0.042, 0.06
    cardGeo = T3.ExtrudeGeometry(roundRectShape(T3, cw / 2, chh / 2, 0.005), {'depth': 0.002, 'bevelEnabled': False, 'curveSegments': 6})
    p, uv = cardGeo.attributes.position, cardGeo.attributes.uv
    for i in range(p.count):
        uv.setXY(i, (p.getX(i) + cw / 2) / cw, (p.getY(i) + chh / 2) / chh)
    # ONE material (the engine's hero-fade pass cannot take material arrays): the side walls sample the cream border
    cardMesh = b.mesh('chest', cardGeo, b.mat(map=card, rough=0.5, rim=0.2, wrap=0.5), O(name='crewBadge'))
    # chest-local surface of the pocket at (x -0.086, y 0.06): z -0.1268, normal (-0.35, 0, -0.94)
    cardMesh.position.set(-0.087, 0.058, -0.1305)
    cardMesh.rotation.set(0.06, math.pi + 0.357, 0)
    # metal clip on top of the card
    clip = b.mesh(cardMesh, T3.BoxGeometry(0.012, 0.016, 0.004), b.mat(color='#D8DCE2', metal=1, rough=0.25, envIntensity=1), O(name='badgeClip'))
    clip.position.set(0, chh / 2 + 0.004, 0.002)


DEF = O(
    id='skip',
    name='Skip Kowalski',
    kind='hero',
    # 1.60 m kid: headScale 1.3 like Duke (head + cap ~0.56 m = 2.9 heads tall), short chunky torso, long legs.
    rig=O(height=1.60, headScale=1.3, shoulderW=0.36, hipW=0.23, legLen=0.74, torsoLen=0.38, armLen=0.5),
    bake=O(voxel=0.004, tris=21200, aoStrength=0.85, aoReach=0.1, morphMax=0.04),
    armOut=0.2,
    poseOffset=O(hipL=[0, 0, -0.04], hipR=[0, 0, 0.04], footL=[0, 0, 0.04], footR=[0, 0, -0.04]),
    rim=O(color='#FFD9A0', strength=0.4),
    materials=O(
        skin=O(color=SKIN, rough=0.5, sss=1, wrap=0.6, cav=0.35),
        hair=O(color=HAIR, rough=0.4, sheen=1.0, sheenExp=60, wrap=0.55, spec=0.35, cav=0.55),
        brow=O(color=BROW, rough=0.45, sheen=0.5, sheenExp=50, wrap=0.55, spec=0.3, cav=0.25),
        cap=O(color=BLUE, rough=0.62, fuzz=0.3, cav=0.45),
        bill=O(color='#2D57CF', rough=0.5, fuzz=0.2, spec=0.6, cav=0.45),
        capWhite=O(color='#E2DBCB', rough=0.72, fuzz=0.25, spec=0.6, cav=0.5),
        shirt=O(color=BLUE, rough=0.68, fuzz=0.3, lines=True, cav=0.5),
        tee=O(color='#F1ECE1', rough=0.74, fuzz=0.3, cav=0.45),
        button=O(color='#FBF7EE', rough=0.25, spec=0.7),
        plaid=O(color='#ffffff', rough=0.78, fuzz=0.35, lines=True, bump=0.08, cav=0.5,
                pattern=O(type='plaid', base='#D99658', scale=0.16, weave=200,
                          bands=[['#8E4A22', 0.13, 0.25, 0.85], ['#8E4A22', 0.13, 0.75, 0.85], ['#F6E2BE', 0.035, 0.5, 0.9], ['#B8612E', 0.05, 0.0, 0.6]])),
        leather=O(color='#6A3D1E', rough=0.38, spec=0.6, cav=0.5),
        silver=O(color='#D8DCE2', metal=1, rough=0.22),
        pouch=O(color='#2A2528', rough=0.42, spec=0.55, cav=0.5),
        plastic=O(color='#ffffff', rough=0.3, spec=0.7, cav=0.3),
        phones=O(color='#26222A', rough=0.25, spec=0.8, cav=0.35),
        cushion=O(color='#48434C', rough=0.55, fuzz=0.3, cav=0.4),
        canvas=O(color='#2F56CC', rough=0.7, fuzz=0.35, cav=0.45),
        rubber=O(color='#ECE5D5', rough=0.5, spec=0.45, cav=0.45),
        mouth=O(color='#5C1C24', rough=0.55, sss=0.4, wrap=0.6, cav=0.1),
        teeth=O(color='#FFF9F0', rough=0.25, spec=0.7, wrap=0.6, cav=0.1),
        tongue=O(color='#E46F78', rough=0.4, sss=0.6, wrap=0.6, cav=0.1),
    ),
    anchors=lambda ctx=None: O(EYE=EYE),
    expressions=['smile', 'frown', 'o_mouth'],
    sculpt=sculpt,
    parts=O(
        browL=O(bone='head', tris=380, sculpt=lambda sd, ctx=None: browShape(sd, 1)),
        browR=O(bone='head', tris=380, sculpt=lambda sd, ctx=None: browShape(sd, -1)),
    ),
    attachments=attachments,
)
