"""Z_MOM — "Tuned-In" zombie variant: the AUDIENCE MOM (GDD §8.1 archetype table, STYLE_GUIDE §7).
(Port of src/art/chars/z_mom.js.) Pear-shaped studio-audience mom: a towering auburn BEEHIVE (her silhouette: a tall
molded dome with a teal ribbon and bow, one forgotten pink curler), red cat-eye glasses with rhinestones framing the
static eyes, pearl earrings and a pearl necklace over a cream blouse with a Peter Pan collar, a mustard knit cardigan
buttoned one hole off (the right panel hangs lower), a teal pleated A-line skirt, bobby socks and burgundy Mary Janes,
a burgundy handbag hooked on her left forearm. Exaggerated feature: the BEEHIVE (+ puffy lipstick "O" mouth and round
chubby cheeks). "13 ADMIT ONE" ticket stub pinned on the cardigan. Shared zombie helpers live in z_crew.py.
"""
import math

import numpy as np

from ..jsutil import O
from ._sculpt import onEllipsoid, prism
from .z_crew import ZOMBIE_MATS, ZSHADOW, zEyeSocket, zEyeLid, zEyePaint, zMouthLip, zMouthInside, zHand, hairClump, staticEyes, ticketStub

HAIR = '#93391F'
# Head-local anchors (origin = head joint; y up, -z forward).
EYES = [
    O(x=0.074, y=0.276, z=-0.142, r=0.058, pitch=0.06, yaw=-0.3, lid=0.4, droop=0.2, depth=0.7),
    O(x=-0.072, y=0.28, z=-0.142, r=0.061, pitch=0.06, yaw=0.3, lid=0.34, droop=0.16, depth=0.7),
]


def heartLips(rx, ry, n=28):
    """Lip ring with a soft cupid's bow on top (wider than tall): a lipstick pout, not a donut."""
    pts = []
    for i in range(n + 3):
        a = (i / n) * math.pi * 2
        c, sn = math.cos(a), math.sin(a)
        bow = (1 - 0.28 * math.exp(-math.pow(c / 0.28, 2)) + 0.12 * math.exp(-math.pow((abs(c) - 0.45) / 0.25, 2))) if sn > 0 else 1.05
        pts.append([c * rx, sn * ry * bow, 0])
    return pts


# Puffy lipstick "O" (the lip ring is repainted with the lipstick material), 3 teeth.
MOUTH = O(
    pos=[0.002, 0.128, -0.164], pitch=0.36, roll=-0.06, r=0.0115, lipPts=heartLips(0.036, 0.024), open=[0.028, 0.017],
    teeth=[
        O(x=-0.0105, y=0.0105, w=0.0092, h=0.0098, rot=0.06),
        O(x=0.0105, y=0.011, w=0.0092, h=0.01, rot=-0.08),
        O(x=-0.004, y=-0.0125, w=0.0082, h=0.0072, rot=-0.1, z=0.004),
    ],
    tongue=O(pts=[[-0.012, -0.009, 0.018], [0.0, -0.008, 0.012], [0.011, -0.01, 0.018]], r=0.009, flat=0.5),
)
HM = O(c=[0, 0.34, 0.014], r=[0.168, 0.19, 0.176])


def headShapes(sd):
    """ROUND HEAD with chubby cheeks (also the base of the molded hair shell)"""
    with sd.group(k=0.07):
        sd.ellipsoid(pos=[0, 0.3, 0.012], r=[0.16, 0.18, 0.166])     # cranium
        sd.ellipsoid(pos=[0, 0.17, -0.028], r=[0.15, 0.13, 0.14])    # lower face


def cheeks(sd):
    sd.mirrorX(lambda: sd.sphere(pos=[0.086, 0.17, -0.112], r=0.058, k=0.04))


def torsoShapes(sd):
    sd.ellipsoid(pos=[0, 0.8, 0.004], r=[0.168, 0.11, 0.12])    # bust
    sd.ellipsoid(pos=[0, 0.68, -0.012], r=[0.162, 0.11, 0.13])  # round tummy
    sd.ellipsoid(pos=[0, 0.872, 0.014], r=[0.188, 0.048, 0.098])  # shoulder yoke


V_OPEN = O(a=[0, 0.64, -0.14], b=[0, 0.96, -0.13], ra=0.018, rb=0.086)   # cardigan front opening


def pleatedSkirt(sd, o):
    """Knife-pleated A-line skirt: cone with a sawtooth radial profile (soft pleats), capped. Local frame: y up, origin
    at the waist; hem at y = -H. (custom leaf: vectorised distance)"""
    o = O(o)
    H, r0, r1, n, amp = o.H, o.r0, o.r1, o.n, o.amp

    def fn(x, y, z):
        t = np.minimum(1, np.maximum(0, -y / H))
        a = np.arctan2(x, -z)                                   # 0 at the front
        f = (a / (math.pi * 2)) * n + 0.5
        saw = f - np.floor(f)                                   # 0..1 per pleat
        pl = amp * (0.35 + 0.65 * t) * (1 - np.power(np.abs(saw * 2 - 1), 1.6))   # soft pleat crest
        R = r0 + (r1 - r0) * np.power(t, 0.85) + pl
        dr = (np.hypot(x, z) - R) * 0.86
        dy = np.maximum(y, -H - y)                              # top / hem caps
        return np.maximum(dr, dy)
    sd.custom(box=[-r1 - amp - 0.01, -H - 0.01, -r1 - amp - 0.01, r1 + amp + 0.01, 0.01, r1 + amp + 0.01], fn=fn)


def catEyePts(E, side, n=28):
    """Cat-eye frame outline around one eye disc (eye frame coords: x out to the character's side when side = +1)."""
    rx, ry = E.r * 1.34, E.r * 1.06
    pts = []
    for i in range(n + 3):
        a = (i / n) * math.pi * 2
        x, y = math.cos(a) * rx, math.sin(a) * ry
        if y < 0:
            y *= 0.86                                            # flatter bottom
        outer, up = max(0, math.cos(a) * side), max(0, math.sin(a) + 0.35)
        wing = math.pow(outer, 3) * up                           # swept-up outer top corner
        x += side * wing * E.r * 0.6
        y += wing * E.r * 0.72
        pts.append([x, y, 0])
    return pts


def sculpt(sd, ctx=None):
    # ---------------- torso: blouse, pearls, cardigan ----------------
    blouseNode = sd.group({'name': 'blouse', 'mat': 'blouse', 'bone': 'torso', 'k': 0.05}, lambda: torsoShapes(sd))
    sd.capsule(mat='skin', bone='torso', a=[0, 0.87, 0.014], b=[0, 1.0, 0.004], r=0.058, k=0.024)
    # Peter Pan collar: two round flat flaps on the blouse
    with sd.group(name='ppcollar', mat='blouse', bone='torso', blend=0.004):
        sd.group({'offset': 0.008, 'shell': 0.0056, 'k': 0.05}, lambda: torsoShapes(sd))
        with sd.group(op='int', k=0.006):
            sd.mirrorX(lambda: sd.cylinder(pos=[0.046, 0.9, -0.06], rot=[math.pi / 2 - 0.35, 0, 0], r=0.05, h=0.1, round=0.01))
        sd.capsule(op='sub', k=0.008, a=[0, 0.88, 0.02], b=[0, 1.1, 0.02], r=0.064)
    sd.mirrorX(lambda: sd.stitch([[0.046 + math.cos(a) * 0.043, 0.9 - math.sin(a) * 0.043, -0.2] for a in [math.pi * (0.1 + 1.25 * i / 16) for i in range(17)]], mats=['blouse'], color='#D9A520', smooth=True))
    # pearl necklace: big cartoon pearls laid on the blouse
    n = 13
    pts = []
    for i in range(n):
        a = -1.15 + (2.3 * i) / (n - 1)
        pts.append([math.sin(a) * 0.085, 0.905 - math.cos(a) * 0.075 + 0.048, -0.2])
    snapped = sd.snapAll(blouseNode, pts, 0.008)
    with sd.group(name='pearls', mat='pearl', bone='chest', blend=0.003, k=0.003):
        for p in snapped:
            sd.sphere(pos=p, r=0.0112)
    with sd.group(name='cardigan', mat='cardigan', bone='torso', blend=0.006, k=0.02) as cardigan:
        with sd.group(offset=0.014, k=0.05):
            torsoShapes(sd)
            sd.ellipsoid(pos=[0, 0.6, 0.0], r=[0.182, 0.08, 0.142])   # hem over the skirt waist
        sd.roundCone(O(V_OPEN, op='sub', k=0.012))
        sd.capsule(op='sub', k=0.02, a=[0, 0.9, 0.024], b=[0, 1.1, 0.024], r=0.084)
        # hem: buttoned one hole off -> her right panel hangs ~3 cm lower than the left
        sd.frame({'pos': [0, 0.57, 0], 'rot': [0, 0, -0.09]}, lambda: sd.plane(op='int', k=0.01, n=[0, -1, 0], d=0))
        sd.sphere(op='sub', k=0.006, pos=[-0.11, 0.62, 0.14], r=0.03)   # clean round hole (back)

    # ribbed band along the opening + hem stitches, patch pockets with a tissue poking out of one
    @sd.mirrorX
    def _():
        sd.stitch([[0.03, 0.62, -0.2], [0.05, 0.8, -0.2], [0.074, 0.95, -0.14]], mats=['cardigan'], color='#B7870F')
        sd.stitch([[0.07, 0.66, -0.2], [0.07, 0.6, -0.2], [0.14, 0.6, -0.2], [0.14, 0.66, -0.2]], mats=['cardigan'], color='#B7870F', smooth=False)
        sd.stitch([[0.068, 0.662, -0.2], [0.142, 0.662, -0.2]], mats=['cardigan'], color='#8A6408', smooth=False)
    sd.stitch([[-0.19, 0.608, -0.05], [0, 0.598, -0.16], [0.19, 0.575, -0.05]], mats=['cardigan'], color='#B7870F')
    tis = sd.snap(cardigan, [-0.105, 0.668, -0.2], -0.004)
    with sd.group(name='tissue', mat='sock', bone='hips', rigid=True, blend=0.004, k=0.012):
        sd.ellipsoid(pos=[tis[0], tis[1] + 0.012, tis[2] - 0.004], rot=[0.2, 0, 0.3], r=[0.022, 0.018, 0.012])
        sd.ellipsoid(pos=[tis[0] + 0.012, tis[1] + 0.02, tis[2] - 0.002], rot=[0.3, 0, -0.4], r=[0.014, 0.016, 0.01])
    # 3 big buttons on her left panel edge (the hole side is empty)
    for y in [0.86, 0.77, 0.68]:
        bp = sd.snap(cardigan, [-0.07 + (0.86 - y) * 0.18, y, -0.2], 0.001)
        with sd.group(name='button', mat='button', bone='torso', rigid=True, blend=0.002, k=0.002):
            sd.ellipsoid(pos=bp, r=[0.014, 0.014, 0.006])

    # ---------------- head ----------------
    with sd.bone('head'):
        with sd.group(name='head', mat='skin', k=0.02, blend=0.03) as head:
            headShapes(sd)
            cheeks(sd)
            # little button nose (upturned)
            sd.ellipsoid(pos=[0, 0.212, -0.17], rot=[0.5, 0, 0], r=[0.024, 0.026, 0.026], k=0.018)
            sd.sphere(pos=[0, 0.203, -0.186], r=0.019, k=0.012)

            # ears
            @sd.mirrorX
            def _():
                sd.ellipsoid(pos=[0.158, 0.225, 0.02], rot=[0, -0.35, 0.1], r=[0.022, 0.042, 0.03], k=0.012)
                sd.ellipsoid(op='sub', k=0.007, pos=[0.172, 0.228, 0.016], rot=[0, -0.35, 0.1], r=[0.01, 0.026, 0.017])
            for E in EYES:
                zEyeSocket(sd, E)
            zMouthLip(sd, MOUTH)
        for E in EYES:
            zEyeLid(sd, E)
        zMouthInside(sd, MOUTH)
        for E in EYES:
            zEyePaint(sd, E)
        # lipstick on the lip ring, rosy cheeks, beauty mark
        sd.paint({'mat': 'lipstick', 'soft': 0.003, 'only': ['skin']}, lambda:
                 sd.frame({'pos': MOUTH.pos, 'rot': [-MOUTH.pitch, 0, MOUTH.roll]}, lambda: sd.worm(pts=MOUTH.lipPts, r=0.017, flat=0.2, up=[0, 0, -1], segs=40)))
        sd.mirrorX(lambda: sd.paint({'color': '#C98FA0', 'soft': 0.03, 'strength': 0.55, 'only': ['skin']}, lambda: sd.sphere(pos=[0.094, 0.17, -0.16], r=0.034)))
        sd.paint({'color': '#4A3040', 'soft': 0.002, 'only': ['skin']}, lambda: sd.sphere(pos=[-0.062, 0.16, -0.17], r=0.0075))
        sd.paint({'color': ZSHADOW, 'soft': 0.03, 'strength': 0.35, 'only': ['skin']}, lambda: sd.ellipsoid(pos=[0, 0.03, -0.04], r=[0.15, 0.05, 0.16]))

        # ---- BEEHIVE + FLIP: a molded-toy hairdo. The hive (a big smooth mound that leans back, fullest at the crown)
        #      grows out of a side-swept front swoop; the sides come down over the ears and end in a 60s flip curling out
        #      at the jaw (hair framing the face = reads as hair, not a hat). French-twist roll up the back, teal bow,
        #      a forgotten pink curler.
        def hiveShapes():
            sd.group({'offset': 0.02, 'k': 0.07}, lambda: headShapes(sd))
            sd.ellipsoid(pos=[0, 0.52, 0.06], rot=[-0.18, 0, 0.04], r=[0.18, 0.225, 0.175])    # the hive, leaning back a little...
            sd.sphere(pos=[0.006, 0.62, 0.09], r=0.158)                                        # ...fullest at the crown
            sd.mirrorX(lambda: sd.ellipsoid(pos=[0.15, 0.245, 0.035], rot=[0, 0, 0.06], r=[0.06, 0.135, 0.12]))   # sides over the ears

        def hflow(x, y, z):
            return [x * 0.4, 1, z * 0.4]
        with sd.group(name='hair', mat='hair', flow=hflow) as hairNode:
            with sd.group(name='hive', k=0.09):
                hiveShapes()
                sd.ellipsoid(op='sub', k=0.025, pos=[0.01, 0.16, -0.235], rot=[0, 0, -0.08], r=[0.19, 0.215, 0.2])  # face opening
                sd.plane(op='int', k=0.03, n=[0, -0.6, 0.8], d=0.05)                               # nape (back only)
                sd.plane(op='int', k=0.03, n=[0, -1, 0], d=-0.11)                                  # flip line
            # 60s flips: rounded rolls curling OUT at the bottom of the sides
            sd.mirrorX(lambda: sd.worm(pts=[[0.15, 0.15, 0.1], [0.172, 0.122, 0.06], [0.2, 0.116, 0.005], [0.222, 0.136, -0.035]], r=[0.03, 0.033, 0.029, 0.016], k=0.03, segs=14))
        # one big molded swoosh wrapping the front of the hive (from her left temple up and over to the crown): the
        # line that makes the tower read as wrapped, teased hair (clean tapered tip, lifted edge, no grooves)
        sd.group({'name': 'swoosh', 'mat': 'hair', 'bone': 'head', 'flow': hflow}, lambda: hairClump(sd, [hairNode], HM, [
            [-0.15, 0.36, -0.07, -0.012], [-0.1, 0.45, -0.14, 0.004], [-0.01, 0.54, -0.16, 0.009], [0.07, 0.63, -0.12, 0.01],
            [0.07, 0.71, -0.04, 0.007], [0.01, 0.76, 0.04, 0.0]], O(xyz=True, r=[0.02, 0.046, 0.052, 0.046, 0.03, 0.01], flat=0.52, k=0.022, segs=28)))
        # French-twist roll up the back of the hive (one smooth raised clump, not a groove)
        twist = sd.snapAll(hairNode, [[0.02, 0.26, 0.2], [0.03, 0.4, 0.24], [0.02, 0.54, 0.26], [-0.005, 0.68, 0.22], [-0.03, 0.75, 0.14]], [-0.006, 0.002, 0.004, 0.004, -0.002])
        sd.worm(mat='hair', bone='head', pts=twist, r=[0.018, 0.026, 0.028, 0.022, 0.01], flat=0.5, up=[0, 0, 1], k=0.02, segs=18)
        # teal bow on her left (a ribbon tied at the base of the hive)
        bowC = sd.snap(hairNode, [-0.17, 0.4, -0.02], 0.008)
        with sd.group(name='bow', mat='ribbon', blend=0.004, k=0.01):
            with sd.frame(pos=bowC, rot=[0, -1.25, 0.2]):
                sd.sphere(r=0.018)
                sd.mirrorX(lambda: sd.ellipsoid(pos=[0.04, 0.006, 0.004], rot=[0, 0, 0.3], r=[0.036, 0.025, 0.012], k=0.008))
                sd.mirrorX(lambda: sd.ellipsoid(pos=[0.02, -0.034, 0.004], rot=[0, 0, 0.5], r=[0.01, 0.028, 0.0065], k=0.006))
        # forgotten pink curler on her right, low at the back of the hive
        cu = sd.snap(hairNode, [0.15, 0.46, 0.14], -0.012)
        with sd.group(name='curler', mat='curler', blend=0.004, k=0.004):
            with sd.frame(pos=cu, rot=[0.3, 0, 0.35]):
                sd.cylinder(r=0.026, h=0.04, round=0.008)
                sd.cylinder(op='sub', k=0.003, r=0.013, h=0.06, round=0.002)

    # ---------------- skirt + legs ----------------
    with sd.group(name='hipsBody', mat='skirt', bone='torso', k=0.03):
        sd.ellipsoid(pos=[0, 0.6, 0.0], r=[0.17, 0.08, 0.135])
    with sd.group(name='skirt', mat='skirt', bone='hips', blend=0.012):
        sd.frame({'pos': [0, 0.625, 0.004]}, lambda: pleatedSkirt(sd, O(H=0.33, r0=0.168, r1=0.25, n=18, amp=0.012)))
    sd.stitch([[math.sin(a) * 0.3, 0.305, math.cos(a) * 0.3] for a in [(i / 40) * math.pi * 2 for i in range(41)]], mats=['skirt'], color='#1D5F5F', smooth=False)

    @sd.mirrorX
    def _():
        with sd.bone('hipL'):
            with sd.group(mat='skin', k=0.03, blend=0.0):
                sd.roundCone(a=[0.02, -0.06, 0.0], b=[0, -0.22, 0.004], ra=0.068, rb=0.056)
                sd.roundCone(a=[0, -0.22, 0.004], b=[0, -0.42, 0.006], ra=0.056, rb=0.044)
            # folded bobby sock
            with sd.group(mat='sock', blend=0.004, k=0.01):
                sd.torus(pos=[0, -0.4, 0.006], R=0.044, r=0.014)
                sd.cylinder(pos=[0, -0.42, 0.006], r=0.05, h=0.02, round=0.01)
        with sd.bone('footL'):
            # Mary Jane: rounded pump with a strap and a little button
            with sd.group(mat='shoe', k=0.03):
                sd.ellipsoid(pos=[0, -0.03, -0.06], r=[0.052, 0.036, 0.11])
                sd.ellipsoid(pos=[0, -0.034, -0.12], r=[0.05, 0.03, 0.06])
                sd.ellipsoid(pos=[0, -0.024, 0.012], r=[0.046, 0.04, 0.05])
                sd.box(pos=[0, -0.052, 0.03], size=[0.03, 0.02, 0.022], round=0.01)   # low heel
                sd.plane(op='int', k=0.004, n=[0, -1, 0], d=0.07)
            with sd.group(mat='shoe', blend=0.004, k=0.004):
                sd.torus(pos=[0, -0.0, -0.04], rot=[0, 0, math.pi / 2], R=0.048, r=0.0065)
                sd.plane(op='int', k=0.004, n=[0, -1, 0], d=0.02)
            sd.sphere(mat='gold', pos=[-0.047, -0.012, -0.04], r=0.007, k=0.002)

    # ---------------- arms: cardigan sleeves, ribbed cuffs, handbag on the left forearm ----------------
    @sd.mirrorX
    def _(m):
        with sd.bone('shoulderL'):
            with sd.group(mat='cardigan', k=0.03, blend=0.02):
                sd.roundCone(a=[0.02, 0.012, 0], b=[0, -0.229, 0], ra=0.06, rb=0.052)
                if m:
                    sd.sphere(op='sub', k=0.005, cutMat='skin', pos=[-0.056, -0.13, -0.01], r=0.022)   # round hole (right sleeve)
        with sd.bone('elbowL'):
            with sd.group(mat='cardigan', k=0.02):
                sd.roundCone(a=[0, 0.014, 0], b=[0, -0.2, 0.002], ra=0.052, rb=0.046)
            with sd.group(mat='cuff', blend=0.004, k=0.008):
                sd.cylinder(pos=[0, -0.205, 0.002], r=0.05, h=0.022, round=0.01)
            sd.roundCone(mat='skin', a=[0, -0.2, 0], b=[0, -0.248, 0], ra=0.035, rb=0.034, k=0.008)
            if not m:
                # handbag hooked over the forearm: hangs along local (0, -0.21, 0.98) = world down in the reaching pose
                with sd.frame(pos=[0, -0.12, 0], rot=[-1.36, 0, 0]):
                    with sd.group(name='bagHandle', mat='bag', bone='elbowL', rigid=True, blend=0.003, k=0.004):
                        sd.torus(pos=[0, -0.004, 0], rot=[math.pi / 2, 0, 0], R=0.058, r=0.0075)
                    with sd.group(name='bag', mat='bag', bone='elbowL', rigid=True, blend=0.004, k=0.02):
                        sd.box(pos=[0, -0.118, 0], size=[0.074, 0.05, 0.03], round=0.024)
                        sd.box(pos=[0, -0.078, 0], size=[0.062, 0.012, 0.026], round=0.012)
                    with sd.group(name='clasp', mat='gold', bone='elbowL', rigid=True, blend=0.002, k=0.003):
                        sd.sphere(pos=[-0.009, -0.068, 0.0], r=0.008)
                        sd.sphere(pos=[0.009, -0.068, 0.0], r=0.008)
                        sd.box(pos=[0, -0.071, 0], size=[0.064, 0.0045, 0.028], round=0.003)
        sd.bone('handL', lambda: zHand(sd, O(scale=1.36, curl=0.35 if m else 0.5)))


# ---------------------------------------------------------------------------------------------------------------
# Cat-eye glasses as ONE smooth rigid attachment on the head (vertex-coloured red frame + white rhinestones, one
# material). Chunky round tubes read crisply at every distance.
_gcache = {}


def eyeToHead(E, p):
    a, b = E.pitch or 0, E.yaw or 0
    x1 = p[0] * math.cos(b) + p[2] * math.sin(b)
    z1 = -p[0] * math.sin(b) + p[2] * math.cos(b)
    y2 = p[1] * math.cos(a) - z1 * math.sin(a)
    z2 = p[1] * math.sin(a) + z1 * math.cos(a)
    return [E.x + x1, E.y + y2, E.z + z2]


def catEyeGlasses(b):
    T3 = b.THREE
    G = _gcache.get('glasses')
    if not G:
        def V(p):
            return T3.Vector3(p[0], p[1], p[2])
        RED, GEM = T3.Color('#E23B3B'), T3.Color('#FFFFFF')

        def tint(g, c):
            n = g.attributes.position.count
            col = np.tile(np.array([c.r, c.g, c.b]), n)
            g.setAttribute('color', T3.BufferAttribute(col, 3))
            return g
        parts = []
        for E in EYES:
            side = 1 if E.x >= 0 else -1
            loop = [V(eyeToHead(E, [x, y, -0.018])) for x, y, _z in catEyePts(E, side, 32)[:32]]
            parts.append(tint(T3.TubeGeometry(T3.CatmullRomCurve3(loop, True, 'centripetal'), 48, 0.0082, 6, True), RED))
            # temple: from the swept-up wing back over the ear into the hair
            w = eyeToHead(E, [side * E.r * 1.5, E.r * 0.82, -0.014])
            t = [V(w), V([w[0] + side * 0.014, w[1] - 0.004, w[2] + 0.03]), V([side * 0.168, 0.286, -0.01]), V([side * 0.172, 0.27, 0.05])]
            parts.append(tint(T3.TubeGeometry(T3.CatmullRomCurve3(t), 10, 0.0068, 5, False), RED))
            # rhinestones on the wing
            for u, v, r in [[1.46, 0.9, 0.0074], [1.13, 1.03, 0.006]]:
                g = T3.IcosahedronGeometry(r, 0)
                c = eyeToHead(E, [side * E.r * u, E.r * v, -0.026])
                g.translate(c[0], c[1], c[2])
                parts.append(tint(g, GEM))
        # bridge over the nose
        iL = eyeToHead(EYES[0], [-EYES[0].r * 1.3, EYES[0].r * 0.25, -0.018])
        iR = eyeToHead(EYES[1], [EYES[1].r * 1.3, EYES[1].r * 0.25, -0.018])
        parts.append(tint(T3.TubeGeometry(T3.CatmullRomCurve3([V(iL), V([0, (iL[1] + iR[1]) / 2 + 0.012, min(iL[2], iR[2]) - 0.022]), V(iR)]), 8, 0.0074, 5, False), RED))
        # merge (non-indexed) into one geometry
        flat = [g.toNonIndexed() if g.index is not None else g for g in parts]
        pos = np.concatenate([np.asarray(f.attributes.position).reshape(-1, 3) for f in flat])
        nrm = np.concatenate([np.asarray(f.attributes.normal).reshape(-1, 3) for f in flat])
        col = np.concatenate([np.asarray(f.attributes.color).reshape(-1, 3) for f in flat])
        geo = T3.Geometry()
        geo.setAttribute('position', T3.BufferAttribute(pos, 3))
        geo.setAttribute('normal', T3.BufferAttribute(nrm, 3))
        geo.setAttribute('color', T3.BufferAttribute(col, 3))
        mat = b.mat(color='#ffffff', vertexColors=True, rough=0.22, rim=0.12, wrap=0.5)
        mat.name = 'zMomGlasses'
        G = O(geo=geo, mat=mat)
        _gcache['glasses'] = G
    return b.mesh('head', G.geo, G.mat, O(name='catEyeGlasses', cast=False))


def attachments(b, ctx=None):
    staticEyes(b, EYES)
    catEyeGlasses(b)
    # chest joint y = 0.739 (torso bind = rest): ticket pinned on her right cardigan panel
    ticketStub(b, O(joint='chest', pos=[0.1, 0.05, -0.128], rot=[0.12, -0.36, 0.2], w=0.08, h=0.044))


DEF = O(
    id='z_mom',
    name='Tuned-In: Audience Mom',
    kind='zombie',
    rig=O(height=1.56, headScale=1.34, shoulderW=0.42, hipW=0.29, legLen=0.66, torsoLen=0.5, armLen=0.62),
    # body 8.4k tris + the glasses attachment ~1.5k = the 10k zombie budget
    bake=O(voxel=0.0046, tris=8400, aoStrength=0.9, aoReach=0.1),
    armOut=0.1,
    # hunched, head tilted (the beehive leans), right arm reaching, left forearm (with the bag) lower
    poseOffset=O(
        spine=[-0.12, 0, 0.03], chest=[-0.08, -0.06, 0], neck=[-0.1, 0, 0], head=[0.3, 0.05, -0.12],
        shoulderL=[-0.1, 0, 0.04], shoulderR=[0.14, 0, -0.03], elbowL=[0.18, 0, 0], elbowR=[0.08, 0, 0],
        handL=[-0.35, 0, 0.1], handR=[-0.45, 0, 0],
    ),
    rim=O(color='#8FF3FF', strength=0.3),
    materials=O(
        ZOMBIE_MATS,
        hair=O(color=HAIR, rough=0.4, sheen=0.8, sheenExp=60, spec=0.3, wrap=0.5, cav=0.5),
        lipstick=O(color='#E0506A', rough=0.3, spec=0.9, sss=0.2),
        pearl=O(color='#F6F0E4', rough=0.2, spec=1.1, wrap=0.5),
        blouse=O(color='#F6E7C8', rough=0.7, fuzz=0.3, wrap=0.55, lines=True),
        cardigan=O(color='#ffffff', rough=0.85, fuzz=0.5, wrap=0.55, bump=0.35, lines=True, pattern=O(type='knit', color='#D9A520', ribs=16, scale=0.1)),
        cuff=O(color='#ffffff', rough=0.85, fuzz=0.5, wrap=0.55, bump=0.4, pattern=O(type='knit', color='#C99218', ribs=26, scale=0.08)),
        button=O(color='#7A4A2A', rough=0.3, spec=0.8),
        skirt=O(color='#2E8C8C', rough=0.72, fuzz=0.35, wrap=0.5, lines=True),
        ribbon=O(color='#3FB2B0', rough=0.35, spec=0.8, wrap=0.5),
        curler=O(color='#FF7FB4', rough=0.4, spec=0.6),
        sock=O(color='#F4F1E8', rough=0.8, fuzz=0.4),
        shoe=O(color='#7A2436', rough=0.2, spec=1),
        bag=O(color='#8A2A3C', rough=0.22, spec=1),
        gold=O(color='#EDB84A', metal=1, rough=0.22),
    ),
    anchors=lambda ctx=None: O(EYES=EYES, MOUTH=MOUTH),
    sculpt=sculpt,
    attachments=attachments,
)
