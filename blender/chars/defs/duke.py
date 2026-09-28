"""DUKE DALTON v4 — WZTV's star TV host (GDD §4, ref docs/ref/hero_mustache.png). Default hero.
(Port of src/art/chars/duke.js.)
docs/STYLE_GUIDE.md ("more cartoon, like Plants vs Zombies"): SIMPLIFY + EXAGGERATE. v4 = art-director polish of v3:
  - Face: eyes at ~49 % of the skull height (short jaw, small chin, round cheeks), big eyes set INTO a soft face
    mask (no carved sockets: the lids hug the eyeball), thin friendly brows arching at the outer third, a D-shaped
    grin with one corner higher, a slim mustache whose ends lift with the smile and taper into the cheeks.
  - Molded-toy feathered hair built from SEPARATE overlapping locks: a convex crown, two top swoops meeting at the
    center part, two side wings over the ears; every lock ends in a tapered tip flicked back at the temple / ear,
    and the back ends at ear-lobe height in three flipped tips (the neck shows). Width <= 1.2x the skull.
  - 70s shirt: a real collar stand hugging the neck + two narrow dagger points to mid-chest (no notch), painted V
    neckline with a small 3-lobe chest-hair tuft, bold 5 cm stripes, one smooth shoulder line, clean cuffs.
  - Bell-bottoms: slim hips, straight to the knee, confident cone flare (hem r ~0.15).
Layout: world coords for the torso/pants (feet at y=0, facing -z), bone-local coords for limbs and head.
Heights come from the rig joints (ctx.J), so rig tweaks keep the garments in place.
"""
import math

from ..jsutil import O
from ._face import EYE_DEFAULTS
from ._sculpt import prism, cartoonMouth, onEllipsoid

SKIN = '#F7BE98'
HAIR = '#7B4527'
BROW = '#6B3F24'      # a touch lighter than v3: thin friendly brows, no heavy dark commas
STACHE = '#633821'

# Head-local anchors (origin = head joint, y up, -z forward). Shared by sculpt, parts and attachments.
EYE = O(EYE_DEFAULTS, x=0.066, y=0.25, z=-0.14, r=0.046, iris='#6A3C1C', irisSize=0.6, pupilSize=0.46,
        lid='#F3B590', lidOpen=1.0, lowerLid=0.6, lidScale=1.04, yaw=0.07, glint=1.1)
# Cranium = the guide ellipsoid the hair locks are laid on.
SKULL = O(c=[0, 0.285, 0.016], r=[0.168, 0.19, 0.178])
# Mouth per expression (cartoonMouth in _sculpt). top < y: the upper edge curves UP into the corners (D grin);
# roll lifts the +x corner (confident smirk); clip keeps the teeth/tongue inside the opening.
MOUTH = O(
    base=O(y=0.1, w=0.056, h=0.026, top=0.094, R=0.075, teeth=0.62, roll=0.075, clip=True),
    smile=O(y=0.099, w=0.062, h=0.033, top=0.091, R=0.07, teeth=0.7, roll=0.06, clip=True),
    frown=O(y=0.095, w=0.042, h=0.013, top=0.102, R=-0.1, teeth=0.45, tongue=False, roll=0.02, clip=True),
    o_mouth=O(y=0.093, w=0.03, h=0.03, top=0.123, R=None, teeth=0.4, roll=0.001, clip=True),
)


# ------------------------------------------------------------------------------------------------------------
# Torso volume shared by the shirt and the collar shell (world coords; Y = rig heights).
def torsoShapes(sd, Y):
    sd.ellipsoid(pos=[0, Y.sh - 0.088, 0.0], r=[0.205, 0.152, 0.134])          # chest
    sd.ellipsoid(pos=[0, Y.hip + 0.12, 0.004], r=[0.174, 0.126, 0.128])      # belly
    sd.ellipsoid(pos=[0, Y.sh - 0.01, 0.012], r=[0.212, 0.056, 0.106])       # shoulder yoke
    sd.ellipsoid(pos=[0, Y.sh - 0.085, -0.028], r=[0.15, 0.1, 0.1])          # chest front


# Head skin volume without the mouth (head-local). ex = expression name or None.
def headBase(sd, ex):
    smile = 1 if ex == 'smile' else 0
    sd.ellipsoid(pos=SKULL.c, r=SKULL.r)                                                # cranium
    sd.ellipsoid(pos=[0, 0.226, -0.062], r=[0.146, 0.1, 0.1], k=0.06)                   # soft face mask (eyes sit in it)
    sd.ellipsoid(pos=[0, 0.15, -0.034], r=[0.136, 0.114, 0.14], k=0.07)                 # short round jaw
    sd.ellipsoid(pos=[0, 0.07, -0.088], r=[0.056, 0.036, 0.048], k=0.05)                # small chin
    sd.mirrorX(lambda: sd.sphere(pos=[0.078, 0.148 + smile * 0.013, -0.11 - smile * 0.005], r=0.054 + smile * 0.004, k=0.05))  # round cheeks
    # nose: one big friendly bulb on a soft bridge
    sd.capsule(a=[0, 0.238, -0.158], b=[0, 0.195, -0.19], r=0.018, k=0.02)
    sd.sphere(pos=[0, 0.178, -0.204], r=0.031, k=0.018)
    sd.mirrorX(lambda: sd.sphere(pos=[0.025, 0.166, -0.186], r=0.017, k=0.014))

    # ears (tops tucked under the hair wings)
    @sd.mirrorX
    def _():
        sd.ellipsoid(pos=[0.163, 0.198, 0.022], r=[0.026, 0.048, 0.035], rot=[0, -0.3, 0.12], k=0.014)
        sd.ellipsoid(op='sub', k=0.008, pos=[0.179, 0.195, 0.018], r=[0.012, 0.028, 0.019], rot=[0, -0.3, 0.12])


def surfZ(sd, G, x, y):
    """z of the head surface at (x, y) (head-local), by bisection along -z on a guide (never baked)."""
    sd.snap(G, [x, y, -0.1])   # compiles the guide
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
    # s = +1 / -1. Thin, flat, friendly: inner end LOW, arch peaking at the outer third, tail never below the inner end.
    with sd.bone('head'):
        H = sd.guide({'k': 0.07}, lambda: headBase(sd, None))
        P = [[0.028, 0.313], [0.052, 0.323], [0.079, 0.3275], [0.107, 0.3205]]
        pts = sd.snapAll(H, [[x * s, y, -0.2] for x, y in P], [0.0022, 0.0028, 0.0028, 0.002])
        sd.worm(mat='brow', pts=pts, r=[0.0068, 0.0086, 0.0084, 0.0048], flat=0.42, up=[0, 0.25, -1], segs=14)


def hairLock(sd, path, r, o=None):
    """A molded-toy hair lock laid on the SKULL guide: path = [[az, el, lift], ...] (deg, deg, m above the skull),
    radius profile r, flat = thickness / width along the skull normal. Analytic normals (no snapping): smooth ups."""
    o = O(o or {})
    pts, ups = [], []
    for az, el, lift in path:
        p = onEllipsoid(SKULL, az, el)
        n = [(p[0] - SKULL.c[0]) / SKULL.r[0] ** 2, (p[1] - SKULL.c[1]) / SKULL.r[1] ** 2, (p[2] - SKULL.c[2]) / SKULL.r[2] ** 2]
        ln = math.hypot(*n)
        u = [v / ln for v in n]
        pts.append([p[0] + u[0] * lift, p[1] + u[1] * lift, p[2] + u[2] * lift])
        ups.append(u)
    return sd.worm(pts=pts, r=r, flat=o.flat if o.flat is not None else 0.55, up=ups[0], ups=ups, k=o.k, segs=o.segs or 18)


def sculpt(sd, ctx):
    J = ctx.J
    Y = O(hip=J['hips'].pos[1], sh=J['shoulderL'].pos[1], neck=J['neck'].pos[1], head=J['head'].pos[1])

    # ---------------- neck ----------------
    with sd.group(name='neck', mat='skin', bone='torso', k=0.03):
        sd.capsule(a=[0, Y.sh - 0.04, 0.008], b=[0, Y.head + 0.08, 0.004], r=0.066)

    # ---------------- shirt (continuous: the V neckline is PAINTED, never carved) ----------------
    shirtFrame = sd.patternFrame(pos=[0, 1.0, 0], mode='cyl', radius=0.15)
    shirt = sd.group({'name': 'shirt', 'mat': 'shirt', 'bone': 'torso', 'k': 0.06, 'pframe': shirtFrame, 'blend': 0.012}, lambda: torsoShapes(sd, Y))
    VBOT, VTOP = Y.sh - 0.075, Y.sh + 0.132
    sd.paint({'mat': 'skin', 'soft': 0.0015, 'only': ['shirt']}, lambda: prism(sd, [[0, VBOT], [0.075, VTOP], [-0.075, VTOP]], {'max': -0.02, 'k': 0.004}))
    # placket (cream band) + buttons below the V
    sd.paint({'color': '#FBEBCB', 'soft': 0.001, 'strength': 1, 'only': ['shirt']}, lambda: sd.box(pos=[0, (VBOT + Y.hip + 0.05) / 2, -0.12], size=[0.011, (VBOT - Y.hip - 0.05) / 2, 0.06], round=0.002))
    for by in [VBOT - 0.05, VBOT - 0.125]:
        sd.ellipsoid(mat='button', bone='torso', pos=sd.snap(shirt, [0, by, -0.2], 0.0015), r=[0.0125, 0.0125, 0.006], k=0.002)
    # small stylized chest-hair tuft: three soft rounded lobes, PAINTED (no lump, no carved hole), light brown
    with sd.paint(color='#A8653E', soft=0.0025, strength=0.6, only=['skin']):
        y0 = VBOT + 0.036
        sd.ellipsoid(pos=[0, y0 + 0.011, -0.14], r=[0.0068, 0.0105, 0.05])
        sd.mirrorX(lambda: sd.ellipsoid(pos=[0.0095, y0 + 0.004, -0.14], r=[0.0058, 0.0078, 0.05], rot=[0, 0, -0.35]))

    # ---------------- collar: stand hugging the neck + two narrow dagger points (one piece, no notch) ----------------
    FLAP = [[0.05, Y.sh + 0.058], [0.112, Y.sh + 0.05], [0.122, Y.sh - 0.03], [0.07, Y.sh - 0.125], [0.036, Y.sh - 0.02]]
    with sd.group(name='collar', mat='collar', bone='torso', blend=0.004, k=0.012):
        # stand: a 2.8 cm band around the neck, back higher than the front
        with sd.group(k=0.004):
            with sd.frame(pos=[0, Y.sh + 0.06, 0.014], rot=[-0.32, 0, 0]):
                sd.cylinder(r=0.087, h=0.014, round=0.0065)
                sd.cylinder(op='sub', k=0.004, r=0.074, h=0.04)
            prism(sd, [[0, VBOT - 0.02], [0.062, VTOP + 0.06], [-0.062, VTOP + 0.06]], {'op': 'sub', 'blend': 0.006, 'max': -0.01, 'k': 0.006})
        # dagger points: flat shell of the torso ∩ narrow pointed footprint (front only)
        with sd.group(k=0, blend=0.01):
            sd.group({'offset': 0.0048, 'shell': 0.0056, 'k': 0.06}, lambda: torsoShapes(sd, Y))
            sd.group({'op': 'int', 'blend': 0.004, 'k': 0}, lambda: sd.mirrorX(lambda: prism(sd, FLAP, {'max': -0.01, 'k': 0.012})))

    @sd.mirrorX
    def _():
        e = FLAP

        def lerp(a, b, t):
            return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
        sd.stitch([[x + 0.006, y + 0.004, -0.25] for x, y in [lerp(e[4], e[3], 0.1), lerp(e[4], e[3], 0.55), lerp(e[4], e[3], 0.9)]], mats=['collar'], color='#E08A22', width=0.0012)
        sd.stitch([[x - 0.007, y + 0.002, -0.25] for x, y in [lerp(e[3], e[2], 0.1), lerp(e[3], e[2], 0.5), lerp(e[3], e[2], 0.9)]], mats=['collar'], color='#E08A22', width=0.0012)

    # ---------------- head ----------------
    with sd.bone('head'):
        head = sd.group({'name': 'head', 'mat': 'skin', 'k': 0.07, 'blend': 0.02}, lambda: headShapes(sd, sd.expr))
        # soft rosy color variation (nose tip, cheeks, ears)
        sd.paint({'color': '#F09A80', 'soft': 0.02, 'strength': 0.5, 'only': ['skin']}, lambda: sd.sphere(pos=[0, 0.18, -0.226], r=0.02))
        sd.paint({'color': '#F4A088', 'soft': 0.035, 'strength': 0.5, 'only': ['skin']}, lambda: sd.mirrorX(lambda: sd.sphere(pos=[0.088, 0.152, -0.14], r=0.024)))
        sd.paint({'color': '#F0A088', 'soft': 0.015, 'strength': 0.4, 'only': ['skin']}, lambda: sd.mirrorX(lambda: sd.ellipsoid(pos=[0.18, 0.195, 0.02], r=[0.02, 0.05, 0.035])))

        # ---- hair: convex crown + separate overlapping locks with flicked tips ----
        with sd.group(name='hair', mat='hair'):
            # crown: ONE convex dome over the skull; the bottom edge runs from the temples (high) to the nape at
            # ear-lobe height (a tilted plane), so the ears and the neck show
            def flow(x, y, z):
                return [x * 1.4, -1, 0.9]
            with sd.group(name='crown', k=0.05, flow=flow):
                sd.ellipsoid(pos=[0, 0.31, 0.025], r=[0.174, 0.215, 0.19])
                sd.ellipsoid(op='sub', k=0.03, pos=[0, 0.2, -0.2], r=[0.142, 0.21, 0.19])                # face opening
                n = math.hypot(1, 0.675)
                sd.plane(op='int', k=0.03, n=[0, -1 / n, -0.675 / n], d=-0.24 / n)                         # temple -> nape
            with sd.group(name='locks', k=0.016, blend=0.03):
                @sd.mirrorX
                def _():
                    # top swoop: from the center part, up and forward over the forehead, back along the side; the tip
                    # flicks out at the temple
                    hairLock(sd, [[2, 54, 0.024], [12, 43, 0.058], [36, 38, 0.058], [64, 28, 0.036], [88, 22, 0.022], [104, 24, 0.042]],
                             [0.03, 0.05, 0.05, 0.042, 0.028, 0.008], {'flat': 0.55})
                    # side wing: from the temple back over the top of the ear; the tip flicks out behind the ear
                    hairLock(sd, [[56, 10, 0.008], [76, 2, 0.017], [96, -4, 0.02], [112, -8, 0.04]],
                             [0.024, 0.036, 0.034, 0.008], {'flat': 0.45})
                    # back locks: down from the crown to ear-lobe height, flipped out at the tip
                    hairLock(sd, [[150, 10, 0.02], [150, -25, 0.025], [148, -45, 0.03], [142, -54, 0.05]],
                             [0.045, 0.05, 0.042, 0.008], {'flat': 0.55})
                hairLock(sd, [[180, 10, 0.02], [180, -25, 0.026], [180, -46, 0.032], [180, -57, 0.052]],
                         [0.05, 0.055, 0.045, 0.008], {'flat': 0.55})

            # sideburns: clean rounded strips on the skin in front of the ears
            @sd.mirrorX
            def _():
                sb = sd.snapAll(head, [[0.156, 0.3, -0.03], [0.156, 0.24, -0.045], [0.152, 0.185, -0.055]], [0.0, 0.002, 0.002])
                sd.worm(pts=sb, r=[0.024, 0.021, 0.018], flat=0.4, up=[1, 0, -0.4], k=0.03, segs=10, flow=[0, -1, 0])

        # ---- mustache: slim, follows the smile: center under the nose, ends lifting and tapering into the cheeks ----
        G = sd.guide({'k': 0.07}, lambda: headBase(sd, sd.expr))
        lift = 0.006 if sd.expr == 'smile' else -0.006 if sd.expr == 'frown' else 0
        with sd.group(name='mustache', mat='stache', k=0.02):
            @sd.mirrorX
            def _():
                P = [[0.0, 0.147, 0.005], [0.02, 0.145, 0.0065], [0.04, 0.139, 0.006], [0.058, 0.136 + lift * 0.5, 0.004], [0.073, 0.141 + lift, 0.0005], [0.084, 0.151 + lift * 1.3, -0.004]]
                pts = sd.snapAll(G, [[p[0], p[1], -0.25] for p in P], [p[2] for p in P])
                ups = [sd.normalAt(G, p) for p in pts]
                sd.worm(pts=pts, r=[0.0125, 0.0165, 0.0158, 0.0118, 0.0072, 0.0034], flat=0.48, up=ups[0], ups=ups, segs=20)

    # ---------------- belt + pants ----------------
    with sd.group(name='pelvis', mat='denim', bone='torso', k=0.03):
        sd.ellipsoid(pos=[0, Y.hip + 0.02, 0.006], r=[0.171, 0.112, 0.128])
    BELT_Y = Y.hip + 0.078
    with sd.group(name='belt', mat='leather', bone='torso'):
        sd.ellipsoid(pos=[0, BELT_Y, 0.004], r=[0.177, 0.12, 0.131], offset=0.0045)
        sd.box(op='int', k=0.004, pos=[0, BELT_Y, 0], size=[0.3, 0.021, 0.3], round=0.002)
    with sd.group(name='buckle', mat='gold', bone='hips', rigid=True, k=0.004):
        sd.ellipsoid(pos=[0, BELT_Y, -0.13], r=[0.043, 0.031, 0.014])

    @sd.mirrorX
    def _():
        with sd.bone('hipL'):
            fr = sd.patternFrame(pos=[0, -0.37, 0], mode='cyl', radius=0.09)
            with sd.group(mat='denim', k=0.05, pframe=fr, blend=0.01):
                sd.roundCone(a=[0.012, 0.045, 0.004], b=[0, -0.33, 0.004], ra=0.099, rb=0.078)
                sd.sphere(pos=[0, -0.345, 0.002], r=0.078)
                # flare: a confident cone from the knee to the hem, leaning outward (x < 0 = lateral) so the hems clear
                sd.cone(pos=[-0.018, -0.537, 0.0], h=0.192, r1=0.155, r2=0.078, round=0.012, scale=[0.9, 1, 1])
            # outseam double stitch + hem stitch + inseam
            out = [[-0.106, 0.06, 0], [-0.1, -0.15, 0], [-0.082, -0.34, 0], [-0.104, -0.5, 0], [-0.136, -0.64, 0], [-0.156, -0.722, 0]]
            for dz in [-0.005, 0.005]:
                sd.stitch([[x, y, z + dz] for x, y, z in out], mats=['denim'])
            hem = []
            for i in range(29):
                a = (i / 28) * math.pi * 2
                hem.append([-0.018 + math.sin(a) * 0.146, -0.708, math.cos(a) * 0.158])
            sd.stitch(hem, mats=['denim'], smooth=False)
        with sd.bone('footL'):
            def upper():
                sd.ellipsoid(pos=[0, -0.029, -0.12], r=[0.071, 0.048, 0.145])
                sd.ellipsoid(pos=[0, -0.024, 0.018], r=[0.056, 0.048, 0.06])
                sd.ellipsoid(pos=[0, -0.004, -0.036], r=[0.05, 0.046, 0.075])
            sd.group({'mat': 'shoe', 'k': 0.035}, upper)
            with sd.group(mat='sole', k=0.0):
                sd.group({'offset': 0.0045, 'k': 0.035}, upper)
                sd.box(op='int', k=0.003, pos=[0, -0.0625, -0.045], size=[0.1, 0.0085, 0.28], round=0.003)
    # fly + front pocket stitches (world)
    sd.stitch([[0, Y.hip + 0.05, -0.135], [0.0, Y.hip - 0.04, -0.13], [-0.032, Y.hip - 0.075, -0.12]], mats=['denim'])
    sd.mirrorX(lambda: sd.stitch([[0.07, Y.hip + 0.055, -0.135], [0.103, Y.hip + 0.01, -0.118], [0.15, Y.hip - 0.01, -0.08]], mats=['denim']))

    # ---------------- arms ----------------
    @sd.mirrorX
    def _():
        with sd.bone('shoulderL'):
            # one smooth shoulder line: the sleeve starts a bit down the arm and melts into the yoke (no puffed head)
            slv = sd.patternFrame(pos=[0, -0.15, 0], mode='cyl', radius=0.067)
            with sd.group(mat='shirt', k=0.04, pframe=slv, blend=0.04):
                sd.roundCone(a=[0.012, -0.03, 0], b=[0, -0.235, 0], ra=0.072, rb=0.066)
        with sd.bone('elbowL'):
            slv = sd.patternFrame(pos=[0, 0, 0], mode='cyl', radius=0.062)
            with sd.group(mat='shirt', k=0.025, pframe=slv):
                sd.roundCone(a=[0, 0.035, 0], b=[0, -0.1, 0], ra=0.066, rb=0.06)
            with sd.group(mat='collar', k=0.012):
                sd.torus(pos=[0, -0.114, 0], R=0.056, r=0.021)
                sd.cylinder(pos=[0, -0.114, 0], r=0.063, h=0.021, round=0.013)
            sd.roundCone(mat='skin', a=[0, -0.1, 0], b=[0, -0.255, 0], ra=0.047, rb=0.041, k=0.008)
        with sd.bone('handL'), sd.frame(scale=1.3, pos=[0, 0.006, 0]):
            with sd.group(mat='skin', k=0.01, blend=0.012):
                sd.roundCone(a=[0, 0.012, 0], b=[0.002, -0.03, 0], ra=0.034, rb=0.04, k=0.015)
                sd.box(pos=[0.002, -0.055, 0], size=[0.022, 0.05, 0.048], round=0.021, k=0.015)
                sd.ellipsoid(pos=[0.012, -0.045, -0.03], r=[0.018, 0.03, 0.022], k=0.012)
                fz, fl = [-0.036, -0.012, 0.012, 0.036], [0.066, 0.074, 0.07, 0.058]
                for i in range(4):
                    z, l, sp = fz[i], fl[i], (i - 1.5) * 0.003
                    sd.worm(pts=[[0.002, -0.094, z], [0.008, -0.094 - l * 0.55, z + sp], [0.018, -0.094 - l, z + sp * 1.5]], r=[0.0108, 0.0104, 0.0098], k=0.004, segs=8)
                    sd.sphere(pos=[-0.008, -0.094, z], r=0.011, k=0.008)
                sd.worm(pts=[[0.012, -0.028, -0.04], [0.022, -0.056, -0.062], [0.03, -0.08, -0.066]], r=[0.0155, 0.013, 0.0118], k=0.01, segs=8)
            # warm the hands to the face's rosy skin (they read paler: no AO pockets, full key light)
            sd.paint({'color': '#F2A987', 'soft': 0.02, 'strength': 0.45, 'only': ['skin']}, lambda: sd.sphere(pos=[0.004, -0.07, 0], r=0.11))


def attachments(b, ctx=None):
    b.eyes(EYE)
    b.aviators(O(eye=EYE, shape='teardrop', drop=0.24, frame='#E6B04A', lens='#FF7A24', lensTop='#F04E1C', lensOpacity=0.36,
                 rimR=0.0048, w=0.059, h=0.052, dy=0.003, templeX=0.172, earZ=0.11))


DEF = O(
    id='duke',
    name='Duke Dalton',
    kind='hero',
    # headScale 1.3 = 3 heads tall (STYLE_GUIDE §1). src/actors/heroes.js + GDD §4 must use the same spec.
    rig=O(height=1.80, headScale=1.3, shoulderW=0.44, hipW=0.27, legLen=0.82, torsoLen=0.46, armLen=0.55),
    bake=O(voxel=0.0042, tris=21000, aoStrength=0.85, aoReach=0.1, morphMax=0.045),
    armOut=0.22,
    poseOffset=O(hipL=[0, 0, -0.045], hipR=[0, 0, 0.045], footL=[0, 0, 0.045], footR=[0, 0, -0.045]),
    rim=O(color='#FFD9A0', strength=0.4),
    materials=O(
        skin=O(color=SKIN, rough=0.5, sss=1, wrap=0.6, cav=0.35),
        hair=O(color=HAIR, rough=0.4, sheen=1.0, sheenExp=70, wrap=0.55, spec=0.35, cav=0.45),
        brow=O(color=BROW, rough=0.45, sheen=0.5, sheenExp=50, wrap=0.55, spec=0.3, cav=0.25),
        stache=O(color=STACHE, rough=0.45, sheen=0.55, sheenExp=50, wrap=0.6, spec=0.3, cav=0.2),
        shirt=O(color='#ffffff', rough=0.7, fuzz=0.25, cav=0.5,
                pattern=O(type='stripes', colors=['#F2701C', '#FBEBCB', '#F9C22C', '#FBEBCB'], widths=[5, 1.6, 5, 1.6], scale=0.132, soft=0.02)),
        collar=O(color='#F9C12B', rough=0.62, fuzz=0.25, cav=0.45),
        denim=O(color='#ffffff', rough=0.82, fuzz=0.35, lines=True, bump=0.12, cav=0.5,
                pattern=O(type='denim', color='#3E54AE', scale=0.05)),
        leather=O(color='#61391F', rough=0.38, spec=0.6, cav=0.5),
        shoe=O(color='#7E4022', rough=0.2, spec=0.9, cav=0.4),
        sole=O(color='#3A2418', rough=0.6, cav=0.4),
        gold=O(color='#EDB64C', metal=1, rough=0.2),
        button=O(color='#FBF1DE', rough=0.3, spec=0.6),
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
