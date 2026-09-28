"""Z_DISCO — "Tuned-In" zombie variant: the DISCO TEEN (GDD §8.1 archetype table, STYLE_GUIDE §7).
(Port of src/art/chars/z_disco.js.) Skinny teen lost on the dance floor forever: a HUGE clustered afro wig worn a bit
askew with a red afro pick stuck in it, long sideburns, hot-pink sequin shirt with a giant white butterfly collar open
over a gold medallion, flared white satin cuffs, white bell-bottoms with the strongest flare of the Tuned-In, silver
platform shoes. Exaggerated feature: LANTERN CHIN (long jutting chin with a cleft) under the afro. Silhouette gag: his
right arm is stuck in the disco point (poseOffset), index finger up, while the left arm reaches like every zombie.
"13 ADMIT ONE" ticket stub on the shirt. Shared zombie helpers live in z_crew.py.
"""
import math

from ..jsutil import O
from ._sculpt import onEllipsoid, prism
from .z_crew import ZOMBIE_MATS, ZSHADOW, zEyeSocket, zEyeLid, zEyePaint, zMouthLip, zMouthInside, zHand, staticEyes, ticketStub

AFRO = '#5B3A2B'
# Head-local anchors (origin = head joint; y up, -z forward). Droopy, mismatched (right eye bigger).
EYES = [
    O(x=0.071, y=0.282, z=-0.128, r=0.062, pitch=0.06, yaw=-0.3, lid=0.38, droop=0.22, depth=0.7),
    O(x=-0.068, y=0.276, z=-0.13, r=0.054, pitch=0.06, yaw=0.28, lid=0.44, droop=0.16, depth=0.7),
]


def lipLoop(rx, ry, n=22):
    pts = []
    for i in range(n + 3):
        a = (i / n) * math.pi * 2
        pts.append([math.cos(a) * rx, math.sin(a) * ry, 0])
    return pts


# Open "O" mouth, 3 big square teeth (GDD §8.1): two up top with a gap, one below.
MOUTH = O(
    pos=[-0.004, 0.142, -0.158], pitch=0.4, roll=0.08, r=0.015, lipPts=lipLoop(0.044, 0.037), open=[0.037, 0.032],
    teeth=[
        O(x=-0.013, y=0.017, w=0.0105, h=0.0135, rot=0.08),
        O(x=0.012, y=0.0175, w=0.0105, h=0.013, rot=-0.1),
        O(x=0.002, y=-0.021, w=0.0095, h=0.0095, rot=0.06, z=0.004),
    ],
    tongue=O(pts=[[-0.014, -0.014, 0.018], [0.0, -0.012, 0.012], [0.013, -0.015, 0.018]], r=0.012, flat=0.5),
)
# Afro wig: guide ellipsoid (head-local), worn askew (tilted to his left, slid right, a little back).
AF = O(pos=[0.012, 0.43, 0.03], rot=[0.04, 0.04, -0.07], r=[0.236, 0.205, 0.224])


def headShapes(sd):
    """LANTERN CHIN head: small cranium (under the afro), narrow cheeks, big jutting chin."""
    with sd.group(k=0.07):
        sd.ellipsoid(pos=[0, 0.33, 0.012], r=[0.148, 0.165, 0.158])              # cranium
        sd.ellipsoid(pos=[0, 0.222, -0.022], r=[0.146, 0.13, 0.138])             # cheeks
        sd.box(pos=[0, 0.082, -0.098], rot=[-0.38, 0, 0], size=[0.082, 0.052, 0.062], round=0.048)   # wide square lantern chin (juts forward)


def torsoShapes(sd):
    sd.ellipsoid(pos=[0, 0.845, 0.008], r=[0.15, 0.095, 0.1])   # chest
    sd.ellipsoid(pos=[0, 0.735, -0.004], r=[0.128, 0.1, 0.098])  # belly
    sd.ellipsoid(pos=[0, 0.9, 0.014], r=[0.182, 0.046, 0.088])   # shoulder yoke


def pointHand(sd, s=1.4):
    """Right hand frozen in the disco point: fist with the index finger up (bone handR frame, mirrored from L)."""
    with sd.frame(scale=s, pos=[0, 0.004, 0]):
        with sd.group(mat='skin', k=0.012, blend=0.012):
            sd.roundCone(a=[0, 0.014, 0], b=[0, -0.03, 0.001], ra=0.03, rb=0.036, k=0.015)
            sd.box(pos=[0, -0.056, 0.004], size=[0.045, 0.042, 0.022], round=0.018, k=0.016)
            # curled middle/ring/pinky: a soft rounded bar folded toward the palm (+z)
            sd.capsule(a=[-0.036, -0.088, 0.016], b=[0.004, -0.09, 0.018], r=0.0165, k=0.01)
            # index finger, straight up the arm axis (-y)
            sd.worm(pts=[[0.024, -0.082, 0.002], [0.026, -0.122, 0.0], [0.027, -0.158, -0.002]], r=[0.0112, 0.0104, 0.0096], k=0.004, segs=8)
            # thumb folded over the curled fingers
            sd.worm(pts=[[0.03, -0.034, -0.004], [0.04, -0.066, 0.014], [0.012, -0.082, 0.032]], r=[0.015, 0.0132, 0.0118], k=0.01, segs=8)


def rotToward(d):
    """Euler XYZ that turns local +y toward direction d (for small props sticking out of surfaces)."""
    l = math.hypot(d[0], d[1], d[2])
    return [math.atan2(d[2] / l, d[1] / l), 0, -math.asin(d[0] / l)]


def sculpt(sd, ctx=None):
    # ---------------- torso: sequin shirt, butterfly collar, medallion ----------------
    torsoFr = sd.patternFrame(pos=[0, 0.8, 0], mode='cyl', radius=0.13)
    with sd.group(name='shirt', mat='shirt', bone='torso', k=0.05, pframe=torsoFr) as shirtNode:
        torsoShapes(sd)
        sd.sphere(op='sub', k=0.006, cutMat='skin', pos=[0.098, 0.7, -0.098], r=0.026)   # clean round tear (belly)
    # open V neckline painted skin (STYLE_GUIDE §5: painted, never carved)
    V = [[0, 0.745], [0.066, 0.93], [-0.066, 0.93]]
    sd.paint({'mat': 'skin', 'only': ['shirt'], 'soft': 0.002}, lambda: prism(sd, V, {'max': -0.02, 'k': 0.012}))
    # neck (skinny, long enough to show under the chin)
    sd.capsule(mat='skin', bone='torso', a=[0, 0.89, 0.014], b=[0, 1.0, 0.008], r=0.056, k=0.024)
    # butterfly collar: a thin flap that follows the shirt (shell of the torso shapes) cut to two huge pointed wings
    with sd.group(name='collar', mat='collar', bone='torso', blend=0.004):
        sd.group({'offset': 0.009, 'shell': 0.0058, 'k': 0.05}, lambda: torsoShapes(sd))
        with sd.group(op='int', k=0.008):
            sd.mirrorX(lambda: prism(sd, [[0.036, 0.935], [0.13, 0.935], [0.158, 0.9], [0.124, 0.78], [0.052, 0.86]], {'max': 0.03, 'k': 0.012}))
    with sd.group(name='collarband', mat='collar', bone='torso', blend=0.008, k=0.02):
        sd.torus(pos=[0, 0.93, 0.016], rot=[0.16, 0, 0], R=0.058, r=0.015)
        sd.plane(op='int', k=0.01, n=[0, 0, -1], d=0.025)     # open at the front
    sd.mirrorX(lambda: sd.stitch([[0.04, 0.93, -0.12], [0.126, 0.93, -0.12], [0.15, 0.9, -0.12], [0.12, 0.79, -0.12], [0.056, 0.862, -0.12]], mats=['collar'], color='#E9A3C8', smooth=False))
    # gold medallion on a thin chain
    med = sd.snap(shirtNode, [0, 0.8, -0.2], 0.004)

    @sd.mirrorX
    def _():
        pts = sd.snapAll(shirtNode, [[0.052, 0.925, -0.06], [0.044, 0.88, -0.1], [0.022, 0.84, -0.12], [0.004, med[1] + 0.024, -0.12]], 0.005)
        sd.worm(mat='gold', bone='torso', pts=pts, r=0.0048, k=0.002, segs=12)
    with sd.group(name='medallion', mat='gold', bone='chest', rigid=True, blend=0.003, k=0.004):
        sd.cylinder(pos=med, rot=[math.pi / 2 + 0.12, 0, 0], r=0.026, h=0.0045, round=0.004)
        sd.sphere(pos=[med[0], med[1], med[2] - 0.003], r=0.011, k=0.006)

    # ---------------- head ----------------
    with sd.bone('head'):
        with sd.group(name='head', mat='skin', k=0.02, blend=0.03) as head:
            headShapes(sd)
            # soft chin dimple
            sd.sphere(op='sub', k=0.016, pos=[0, 0.066, -0.176], r=0.008)
            # small upturned nose
            sd.ellipsoid(pos=[0, 0.222, -0.158], rot=[0.4, 0, 0], r=[0.024, 0.03, 0.028], k=0.02)
            sd.sphere(pos=[0, 0.212, -0.176], r=0.02, k=0.012)
            for E in EYES:
                zEyeSocket(sd, E)
            zMouthLip(sd, MOUTH)
        for E in EYES:
            zEyeLid(sd, E)
        zMouthInside(sd, MOUTH)
        for E in EYES:
            zEyePaint(sd, E)
        sd.paint({'color': '#8DB58A', 'soft': 0.02, 'strength': 0.6, 'only': ['skin']}, lambda: sd.sphere(pos=[0, 0.212, -0.18], r=0.026))
        sd.paint({'color': ZSHADOW, 'soft': 0.03, 'strength': 0.4, 'only': ['skin']}, lambda: sd.ellipsoid(pos=[0, 0.02, -0.06], r=[0.12, 0.05, 0.13]))

        # long 70s sideburns down the cheeks (molded, tapered), roots buried in the afro
        @sd.mirrorX
        def _():
            pts = sd.snapAll(head, [[0.136, 0.33, -0.02], [0.142, 0.27, -0.04], [0.136, 0.215, -0.06], [0.124, 0.18, -0.07]], [-0.006, 0.002, 0.003, 0.002])
            sd.worm(mat='sideburn', pts=pts, r=[0.036, 0.034, 0.028, 0.014], flat=0.55, up=[1, 0, -0.3], k=0.01, segs=14, flow=[0, -1, 0])

        # ---- AFRO WIG: one big clustered mass of round puffs (molded, no noise) worn askew ----
        with sd.frame(pos=AF.pos, rot=AF.rot):
            E = O(c=[0, 0, 0], r=AF.r)
            with sd.group(name='afro', mat='hair', k=0.014, blend=0.012, flow=[0, -1, 0]) as afro:
                sd.ellipsoid(pos=[0, 0, 0], r=[AF.r[0] * 0.8, AF.r[1] * 0.8, AF.r[2] * 0.8])
                N, ga = 44, math.pi * (3 - math.sqrt(5))
                for i in range(N):
                    yy = 1 - (i + 0.5) / N * 1.62                 # top ... down to ~ -0.62 (below: neck / face)
                    rr = math.sqrt(max(0, 1 - yy * yy))
                    th = i * ga
                    x, z = math.cos(th) * rr, math.sin(th) * rr
                    # face window: no puffs in front of the face
                    if z < -0.42 and yy < 0.22 and abs(x) < 0.66:
                        continue
                    s = 0.078 + 0.018 * (0.5 + 0.5 * math.sin(i * 12.9898))
                    sd.sphere(pos=[x * AF.r[0] * 0.9, yy * AF.r[1] * 0.9, z * AF.r[2] * 0.9], r=s)
                # face window + hairline arch, ears/jaw clear, nape
                sd.ellipsoid(op='sub', k=0.03, pos=[-0.01, -0.17, -0.2], rot=[0, 0, 0.07], r=[0.152, 0.22, 0.17])
                sd.plane(op='int', k=0.04, n=[0, -1, 0.35], d=0.36)
            # red afro pick stuck in the top right
            p0 = onEllipsoid(E, 38, 42, 0.02)
            nrm = sd.normalAt(afro, p0)
            d = [nrm[0] * 0.8, nrm[1] * 0.8 + 0.45, nrm[2] * 0.8]
            with sd.frame(pos=sd.snap(afro, p0, -0.02), rot=rotToward(d)):
                with sd.group(name='pick', mat='pick', blend=0.004, k=0.006):
                    sd.box(pos=[0, 0.04, 0], size=[0.017, 0.045, 0.0065], round=0.006)
                    sd.torus(pos=[0, 0.098, 0], rot=[math.pi / 2, 0, 0], R=0.021, r=0.0075, k=0.006)

    # ---------------- belt + bell-bottoms ----------------
    with sd.group(name='pelvis', mat='pants', bone='torso', k=0.03):
        sd.ellipsoid(pos=[0, 0.635, 0.0], r=[0.134, 0.082, 0.104])
    with sd.group(name='belt', mat='belt', bone='torso'):
        sd.ellipsoid(pos=[0, 0.662, -0.002], r=[0.13, 0.09, 0.103], offset=0.007)
        sd.box(op='int', k=0.003, pos=[0, 0.664, 0], size=[0.3, 0.019, 0.3], round=0.002)
    with sd.group(name='buckle', mat='gold', bone='hips', rigid=True, k=0.003):
        sd.ellipsoid(pos=[0, 0.664, -0.112], r=[0.034, 0.026, 0.009])

    @sd.mirrorX
    def _(m):
        with sd.bone('hipL'):
            # straight thigh + confident flare; the flare is tilted out so the two hems stay ~4 cm apart in the bind pose
            # (blend < gap: a wider smooth blend webs the hems together between the feet)
            with sd.group(mat='pants', k=0.04, blend=0.02):
                sd.roundCone(a=[0.03, -0.03, 0.004], b=[0, -0.262, 0.004], ra=0.08, rb=0.058)
                sd.cone(pos=[-0.012, -0.41, 0.008], rot=[0, 0, -0.06], h=0.148, r1=0.12, r2=0.058, round=0.01)
                if not m:
                    sd.sphere(op='sub', k=0.006, cutMat='skin', pos=[0.006, -0.26, -0.062], r=0.024)   # round tear at the left knee
            # front crease + gold hem stitching
            sd.stitch([[0, 0.02, -0.09], [0, -0.26, -0.064], [0, -0.55, -0.13]], mats=['pants'], color='#D8C9A6')
            sd.stitch([[math.sin(a) * 0.15, -0.54, 0.008 + math.cos(a) * 0.15] for a in [(i / 24) * math.pi * 2 for i in range(25)]], mats=['pants'], smooth=False, color='#E8A92E')
        with sd.bone('footL'):
            # silver platform shoe: rounded upper on a thick hot-pink platform + block heel
            def upper():
                sd.ellipsoid(pos=[0, 0.0, -0.06], r=[0.056, 0.042, 0.12])
                sd.ellipsoid(pos=[0, -0.008, -0.13], r=[0.054, 0.036, 0.066])
                sd.ellipsoid(pos=[0, 0.018, 0.006], r=[0.05, 0.048, 0.056])
            sd.group({'mat': 'shoe', 'k': 0.03}, upper)
            with sd.group(mat='sole', blend=0.004, k=0.02):
                sd.box(pos=[0, -0.046, -0.068], size=[0.064, 0.024, 0.118], round=0.02)
                sd.box(pos=[0, -0.042, 0.03], size=[0.052, 0.028, 0.044], round=0.016)

    # ---------------- arms: sequin sleeves, flared white cuffs ----------------
    @sd.mirrorX
    def _(m):
        with sd.bone('shoulderL'):
            fr = sd.patternFrame(pos=[0, -0.1, 0], mode='cyl', radius=0.05)
            with sd.group(mat='shirt', k=0.03, blend=0.02, pframe=fr):
                sd.roundCone(a=[0.016, 0.012, 0], b=[0, -0.212, 0], ra=0.053, rb=0.046)
                if not m:
                    sd.sphere(op='sub', k=0.005, cutMat='skin', pos=[-0.05, -0.11, -0.012], r=0.022)   # round hole in the left sleeve
        with sd.bone('elbowL'):
            fr = sd.patternFrame(pos=[0, -0.1, 0], mode='cyl', radius=0.045)
            with sd.group(mat='shirt', k=0.02, pframe=fr):
                sd.roundCone(a=[0, 0.014, 0], b=[0, -0.16, 0.002], ra=0.046, rb=0.043)
            with sd.group(mat='collar', blend=0.004, k=0.008):
                sd.cone(pos=[0, -0.18, 0.002], h=0.03, r1=0.06, r2=0.045, round=0.008)
            sd.roundCone(mat='skin', a=[0, -0.18, 0], b=[0, -0.228, 0], ra=0.033, rb=0.032, k=0.008)
        sd.bone('handL', lambda: pointHand(sd, 1.4) if m else zHand(sd, O(scale=1.4, curl=0.4)))


def attachments(b, ctx=None):
    staticEyes(b, EYES)
    # chest joint y = 0.78 (torso bind = rest): ticket stuck on the sequins, left of the medallion
    ticketStub(b, O(joint='chest', pos=[-0.074, -0.03, -0.096], rot=[0.08, 0.34, -0.24], w=0.08, h=0.044))


DEF = O(
    id='z_disco',
    name='Tuned-In: Disco Teen',
    kind='zombie',
    rig=O(height=1.54, headScale=1.3, shoulderW=0.38, hipW=0.25, legLen=0.86, torsoLen=0.44, armLen=0.64),
    bake=O(voxel=0.0046, tris=9500, aoStrength=0.9, aoReach=0.1),
    armOut=0.1,
    # hunch + head pushed forward (chin up: the chin is the gag) + a disco hip pop; right arm locked in the point
    # (added on top of the zombie arms-forward pose), left arm reaching lower.
    poseOffset=O(
        spine=[-0.08, 0, -0.05], chest=[-0.07, 0.1, 0.03], neck=[-0.08, 0, 0], head=[0.26, -0.08, 0.1],
        hips=[0, 0, 0.06],
        shoulderR=[1.5, 0, 0.76], elbowR=[0.2, 0, 0], handR=[0.12, 0, 0],
        shoulderL=[-0.08, 0, 0.02], elbowL=[0.1, 0, 0], handL=[-0.45, 0, 0],
        hipL=[0, 0, -0.07], hipR=[0, 0, 0.06], footL=[0, 0, 0.07], footR=[0, 0, -0.06],
    ),
    rim=O(color='#8FF3FF', strength=0.3),
    materials=O(
        ZOMBIE_MATS,
        hair=O(color='#ffffff', rough=0.72, fuzz=0.55, spec=0.25, wrap=0.55, cav=0.9, bump=0.35, pattern=O(type='felt', color=AFRO, scale=0.09)),
        sideburn=O(color=AFRO, rough=0.5, sheen=0.5, sheenExp=50, spec=0.3, wrap=0.5, cav=0.5),
        shirt=O(color='#ffffff', rough=0.32, metal=0.25, spec=1.1, fuzz=0.15, wrap=0.5, bump=0.45,
                pattern=O(type='sequins', color='#F0439A', color2='#FFA8D6', count=11, scale=0.12)),
        collar=O(color='#F6F1E6', rough=0.3, spec=0.9, fuzz=0.15, wrap=0.55, lines=True),
        pants=O(color='#DCD4C2', rough=0.72, fuzz=0.28, spec=0.28, wrap=0.55, lines=True),
        belt=O(color='#2B2233', rough=0.3, spec=0.8),
        gold=O(color='#EDB84A', metal=1, rough=0.22),
        shoe=O(color='#E8B64A', metal=0.6, rough=0.3, spec=0.9),
        sole=O(color='#F0439A', rough=0.35, spec=0.8),
        pick=O(color='#E23B3B', rough=0.3, spec=0.9),
    ),
    anchors=lambda ctx=None: O(EYES=EYES, MOUTH=MOUTH),
    sculpt=sculpt,
    attachments=attachments,
)
