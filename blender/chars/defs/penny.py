"""PENNY WATTS v1 — night-shift broadcast engineer (GDD §4, ref docs/ref/hero_glasses.png). (Port of
src/art/chars/penny.js.) Same recipes and finish as the approved Duke: SIMPLIFY + EXAGGERATE.
  - Long wavy brown molded-toy hair: crown + a big side-swept fringe + two face-framing side curtains + a back curtain
    ending in wavy S-locks with flicked tips; orange headband behind the fringe.
  - Big brown eyes with lashes behind round chunky black glasses, rosy cheeks, gentle smile, gold hoops.
  - Orange ribbed turtleneck (knit pattern, folded neck roll, ribbed cuffs), gold medallion on a chain.
  - Brown corduroy A-line mini skirt with 4 gold buttons and stitching, wide brown belt + round gold buckle,
    dark brown tights, cream knee-high go-go boots with brown heels and soles.
Layout: world coords for torso/skirt/back hair (feet y=0, facing -z), bone-local for limbs and head (head scaled by HS).
"""
import math

from ..jsutil import O, nz
from ._face import EYE_DEFAULTS
from ._hands import handParts
from ._sculpt import cartoonMouth, prism
from .roxy import mergeGeos

SKIN = '#F5C3A2'
HAIR = '#6B3A22'
BROW = '#553020'

HS = 1.06
EYE = O(EYE_DEFAULTS, x=0.064, y=0.228, z=-0.128, r=0.045, iris='#9A5626', irisSize=0.66, pupilSize=0.44,
        lid='#F0B08E', lash='#1E120E', lidOpen=1.0, lowerLid=0.62, lidScale=1.04, yaw=0.07, glint=1.15, tilt=0.03)
SKULL = O(c=[0, 0.266, 0.012], r=[0.152, 0.174, 0.162])
MOUTH = O(
    base=O(y=0.1, w=0.039, h=0.013, top=0.097, R=0.07, teeth=0.9, roll=-0.04, clip=True),
    smile=O(y=0.099, w=0.048, h=0.025, top=0.093, R=0.06, teeth=0.75, roll=-0.03, clip=True),
    frown=O(y=0.095, w=0.033, h=0.012, top=0.103, R=-0.09, teeth=0.4, tongue=False, roll=0.0, clip=True),
    o_mouth=O(y=0.093, w=0.025, h=0.026, top=0.12, R=None, teeth=0.35, roll=0.001, clip=True),
)
CROWN = O(c=[0, 0.29, 0.02], r=[0.172, 0.186, 0.186])
# headband plane: over the top of the head from ear to ear, just behind the fringe
HB = O(n=[0, 0.371, 0.928], p=[0, 0.45, -0.1], half=0.019)


# Hand proportions (the old in-body hand; _hands.py builds every shape from them).
HAND = O(s=1.14, pos=[0, 0.006, 0], wrist=[0.03, 0.036], palm=[0.02, 0.047, 0.044], palmRound=0.019, ball=[0.016, 0.028, 0.02], zk=0.029 / 0.03,
         fz=[-0.033, -0.011, 0.011, 0.032], fl=[0.064, 0.072, 0.068, 0.056], fr=[0.0098, 0.0094, 0.0086], y0=-0.088, kr=0.0098,
         thumbR=[0.0142, 0.012, 0.0108], thumbP=[[0.012, -0.028, -0.036], [0.022, -0.053, -0.058], [0.03, -0.075, -0.062]],
         warm='#F2A987', warmK=0.4, nails=None)


def hbD(off):
    return HB.n[1] * HB.p[1] + HB.n[2] * HB.p[2] + off


# ------------------------------------------------------------------------------------------------------------
def torsoShapes(sd, Y):
    sd.ellipsoid(pos=[0, Y.sh - 0.08, 0.004], r=[0.148, 0.11, 0.1])          # rib cage
    sd.mirrorX(lambda: sd.sphere(pos=[0.05, Y.sh - 0.112, -0.05], r=0.054, k=0.05))   # modest bust
    sd.ellipsoid(pos=[0, Y.hip + 0.14, 0.008], r=[0.12, 0.11, 0.092])        # waist
    sd.ellipsoid(pos=[0, Y.sh - 0.012, 0.01], r=[0.165, 0.044, 0.082])       # shoulder yoke


def headBase(sd, ex):
    smile = 1 if ex == 'smile' else 0
    sd.ellipsoid(pos=SKULL.c, r=SKULL.r)
    sd.ellipsoid(pos=[0, 0.212, -0.056], r=[0.134, 0.096, 0.096], k=0.06)
    sd.ellipsoid(pos=[0, 0.148, -0.034], r=[0.114, 0.104, 0.122], k=0.07)                # slim oval jaw
    sd.ellipsoid(pos=[0, 0.07, -0.078], r=[0.04, 0.032, 0.04], k=0.05)
    sd.mirrorX(lambda: sd.sphere(pos=[0.07, 0.146 + smile * 0.012, -0.1 - smile * 0.004], r=0.047 + smile * 0.004, k=0.05))
    sd.capsule(a=[0, 0.226, -0.15], b=[0, 0.19, -0.176], r=0.014, k=0.02)
    sd.sphere(pos=[0, 0.176, -0.184], r=0.02, k=0.016)
    sd.mirrorX(lambda: sd.sphere(pos=[0.017, 0.168, -0.172], r=0.012, k=0.012))
    sd.mirrorX(lambda: sd.ellipsoid(pos=[0.148, 0.19, 0.018], r=[0.024, 0.044, 0.032], rot=[0, -0.3, 0.12], k=0.014))


def onE(E, az, el):
    """Molded-toy hair lock laid on the CROWN guide (Duke's recipe): path [[az, el, lift]] in degrees."""
    a, e = az * math.pi / 180, el * math.pi / 180
    return [E.c[0] + math.sin(a) * math.cos(e) * E.r[0], E.c[1] + math.sin(e) * E.r[1], E.c[2] - math.cos(a) * math.cos(e) * E.r[2]]


def hairLock(sd, path, r, o=None):
    o = O(o or {})
    E = CROWN
    pts, ups = [], []
    for az, el, lift in path:
        q = onE(E, az, el)
        n = [(q[0] - E.c[0]) / E.r[0] ** 2, (q[1] - E.c[1]) / E.r[1] ** 2, (q[2] - E.c[2]) / E.r[2] ** 2]
        l = math.hypot(*n)
        u = [v / l for v in n]
        pts.append([q[0] + u[0] * lift, q[1] + u[1] * lift, q[2] + u[2] * lift])
        ups.append(u)
    return sd.worm(pts=pts, r=r, flat=nz(o.flat, 0.55), up=ups[0], ups=ups, k=o.k, segs=o.segs or 20)


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


def lipsPaint(sd, ex):
    m = MOUTH[ex] if ex in MOUTH else MOUTH.base
    with sd.paint(color='#E0707A', soft=0.003, strength=0.65, only=['skin']):
        with sd.frame(pos=[0, m.y + (0 if m.R is None else 0.002), -0.15], rot=[0, 0, m.roll or 0]):
            sd.ellipsoid(pos=[0, 0, 0], r=[m.w + 0.005, min(m.h, 0.02) * 0.85 + 0.007, 0.08])


def browShape(sd, s):
    with sd.bone('head'), sd.frame(scale=HS):
        H = sd.guide({'k': 0.07}, lambda: headBase(sd, None))
        up = 0.004 if s < 0 else 0   # the left brow (-x) a little higher: curious engineer
        P = [[0.026, 0.304 + up], [0.05, 0.316 + up], [0.076, 0.322 + up], [0.102, 0.312 + up]]
        pts = sd.snapAll(H, [[x * s, y, -0.2] for x, y in P], [0.0044, 0.0048, 0.0043, 0.003])
        sd.worm(mat='brow', pts=pts, r=[0.0074, 0.0084, 0.0072, 0.0038], flat=0.45, up=[0, 0.25, -1], segs=14)


# ------------------------------------------------------------------------------------------------------------
def roundGlasses(b, o):
    """Round chunky glasses: one merged frame mesh (rims, bridge, temples) + one merged lens mesh."""
    o = O(o)
    T3 = b.THREE
    E = o.eye
    R, t, zf = o.r, o.thick, o.z
    wrap = nz(o.wrap, 0.1)
    frames, lenses = [], []
    for s in (1, -1):
        cx = s * E.x
        outer = T3.Shape()
        outer.absellipse(0, 0, R, R * nz(o.squash, 1), 0, math.pi * 2)
        inner = T3.Path()
        inner.absellipse(0, 0, R - t, (R - t) * nz(o.squash, 1), 0, math.pi * 2, True)
        outer.holes.append(inner)
        g = T3.ExtrudeGeometry(outer, {'depth': o.depth, 'bevelEnabled': True, 'bevelThickness': o.depth * 0.35, 'bevelSize': t * 0.22, 'bevelSegments': 2, 'curveSegments': 40})
        g.translate(0, 0, -o.depth / 2)
        g.rotateY(-s * wrap)
        g.translate(cx, E.y + (o.dy or 0), zf)
        frames.append(g)
        lsh = T3.Shape()
        lsh.absellipse(0, 0, R - t * 0.7, (R - t * 0.7) * nz(o.squash, 1), 0, math.pi * 2)
        lg = T3.ShapeGeometry(lsh, 24)
        lg.rotateY(-s * wrap)
        lg.translate(cx, E.y + (o.dy or 0), zf + 0.001)
        lenses.append(lg)
        ca, sa = math.cos(wrap), math.sin(wrap)
        ax, az = cx + s * R * ca * 0.98, zf + R * sa
        tA = T3.Vector3(ax, E.y + (o.dy or 0) + R * 0.25, az + 0.004)
        tB = T3.Vector3(s * o.templeX, E.y + (o.dy or 0) + R * 0.3, az + 0.07)
        tC = T3.Vector3(s * (o.templeX + 0.004), E.y + (o.dy or 0) + R * 0.05, o.earZ)
        frames.append(T3.TubeGeometry(T3.CatmullRomCurve3([tA, tB, tC]), 14, t * 0.34, 6))
    bl = T3.Vector3(-E.x + R * 0.97, E.y + (o.dy or 0) + R * 0.2, zf)
    br = T3.Vector3(E.x - R * 0.97, E.y + (o.dy or 0) + R * 0.2, zf)
    frames.append(T3.TubeGeometry(T3.CatmullRomCurve3([bl, T3.Vector3(0, E.y + (o.dy or 0) + R * 0.36, zf - 0.006), br]), 10, t * 0.4, 6))
    frameMat = b.mat(color=o.color or '#1B1520', rough=0.28, rim=0.18, envIntensity=0.9)
    # lenses barely there (a faint reflection): the big eyes must keep their warm color behind the glass
    glassMat = b.mat(color='#EAF4FF', rough=0.05, transparent=True, opacity=0.045, envIntensity=0.55, rim=0.08, rimColor='#FFFFFF')
    b.mesh(o.parent or 'head', mergeGeos(T3, frames), frameMat, O(name='glassesFrame'))
    lens = b.mesh(o.parent or 'head', mergeGeos(T3, lenses), glassMat, O(name='glassesLens', cast=False))
    lens.renderOrder = 3


def lashWings(b, E, color):
    T3 = b.THREE
    mat = b.mat(color=color, rough=0.5, rim=0.05)
    for side in ('L', 'R'):
        root = b.joint('head').getObjectByName('eye' + side)
        if not root or len(root.children) < 5:
            continue
        upper = root.children[3]
        sx = -1 if side == 'L' else 1
        lr = E.r * nz(E.lidScale, 1.06)
        cap = math.pi * 0.53
        y0 = lr * math.cos(cap)
        geos = []
        for th, ln, up in [[1.05, 0.02, 0.05], [1.35, 0.024, 0.2]]:
            p = T3.Vector3(sx * lr * math.sin(th), y0, -lr * math.cos(th))
            out = T3.Vector3(sx * math.sin(th), 0, -math.cos(th)).normalize()
            pts = []
            for i in range(7):
                t = i / 6
                pts.append(p.clone().addScaledVector(out, ln * t).add(T3.Vector3(0, (0.35 + up) * ln * t * t + 0.004 * t, 0)))
            C = T3.CatmullRomCurve3(pts)
            g = T3.TubeGeometry(C, 8, 1, 5)
            P = g.attributes.position
            for s in range(9):
                c = C.getPointAt(s / 8)
                rad = 0.0024 * (1 - s / 8) + 0.0004
                for k in range(6):
                    idx = s * 6 + k
                    v = T3.Vector3(P.getX(idx), P.getY(idx), P.getZ(idx)).sub(c).multiplyScalar(rad).add(c)
                    P.setXYZ(idx, v.x, v.y, v.z)
            g.computeVertexNormals()
            geos.append(g)
        m = T3.Mesh(mergeGeos(T3, geos), mat)
        m.name = 'lashWings'
        m.castShadow = False
        upper.add(m)


def sculpt(sd, ctx):
    J = ctx.J
    Y = O(hip=J['hips'].pos[1], sh=J['shoulderL'].pos[1], neck=J['neck'].pos[1], head=J['head'].pos[1])
    H0 = Y.head   # world y of the head joint (head-local = (world - [0, H0, 0]) / HS)

    # ---------------- neck + sweater body ----------------
    with sd.group(name='neck', mat='skin', bone='torso', k=0.03):
        sd.capsule(a=[0, Y.sh - 0.04, 0.008], b=[0, Y.head + 0.07, 0.004], r=0.047)
    knitFrame = sd.patternFrame(pos=[0, Y.sh - 0.1, 0], mode='cyl', radius=0.13)
    sd.group({'name': 'sweater', 'mat': 'knit', 'bone': 'torso', 'k': 0.06, 'blend': 0.012, 'pframe': knitFrame}, lambda: torsoShapes(sd, Y))
    # turtleneck: a tube up the neck + a thick folded roll
    neckFrame = sd.patternFrame(pos=[0, Y.sh + 0.05, 0.006], mode='cyl', radius=0.06)
    with sd.group(name='turtle', mat='knit', bone='torso', k=0.02, blend=0.03, pframe=neckFrame):
        sd.roundCone(a=[0, Y.sh - 0.01, 0.01], b=[0, Y.head - 0.005, 0.006], ra=0.068, rb=0.058)
        sd.torus(pos=[0, Y.sh + 0.035, 0.008], rot=[-0.08, 0, 0], R=0.058, r=0.026)
    # gold medallion on a chain
    sweaterG = sd.guide({'k': 0.06}, lambda: torsoShapes(sd, Y))
    mp = sd.snap(sweaterG, [0, Y.sh - 0.15, -0.3], 0.004)
    with sd.group(name='medallion', mat='gold', bone='chest', rigid=True, blend=0.003, k=0.003):
        with sd.frame(pos=mp, rot=[-math.pi / 2 + 0.25, 0, 0]):
            sd.cylinder(r=0.027, h=0.004, round=0.003)
            sd.torus(pos=[0, 0.004, 0], R=0.022, r=0.0035)
            sd.sphere(pos=[0, 0.004, 0], r=0.009, scale=[1, 0.4, 1])
        sd.torus(pos=[mp[0], mp[1] + 0.034, mp[2] + 0.002], rot=[0, 0, math.pi / 2], R=0.007, r=0.0028)

        # chain: from the bail up the chest to the neck roll on both sides
        @sd.mirrorX
        def _():
            pts = sd.snapAll(sweaterG, [[0.004, mp[1] + 0.04, -0.3], [0.03, Y.sh - 0.06, -0.3], [0.052, Y.sh + 0.0, -0.3]], 0.004)
            sd.worm(pts=[*pts, [0.062, Y.sh + 0.02, -0.04]], r=0.0042, segs=16)

    # ---------------- skirt + belt ----------------
    WAIST = Y.hip + 0.095
    skirtFrame = sd.patternFrame(pos=[0, Y.hip, 0], mode='cyl', radius=0.16)
    # A-line: skinned to the hips and both thighs (the front follows each leg a little when walking)
    with sd.group(name='skirt', mat='cord', bone=['hips', 'hipL', 'hipR', 'spine'], k=0.05, blend=0.01, pframe=skirtFrame):
        sd.ellipsoid(pos=[0, Y.hip + 0.06, 0.008], r=[0.156, 0.075, 0.114])
        sd.cone(pos=[0, Y.hip - 0.07, 0.01], h=0.13, r1=0.21, r2=0.172, round=0.014, scale=[1, 1, 0.84])
    BELT_Y = WAIST - 0.01
    with sd.group(name='belt', mat='leather', bone='torso', blend=0.004):
        with sd.group(offset=0.006, k=0.05):
            sd.ellipsoid(pos=[0, Y.hip + 0.14, 0.008], r=[0.12, 0.11, 0.092])
            sd.ellipsoid(pos=[0, Y.hip + 0.06, 0.008], r=[0.156, 0.075, 0.114])
        sd.box(op='int', k=0.004, pos=[0, BELT_Y, 0], size=[0.3, 0.021, 0.3], round=0.002)

    def _bg():
        sd.ellipsoid(pos=[0, Y.hip + 0.14, 0.008], r=[0.12, 0.11, 0.092])
        sd.ellipsoid(pos=[0, Y.hip + 0.06, 0.008], r=[0.14, 0.07, 0.108])
    beltG = sd.guide({'offset': 0.006, 'k': 0.05}, _bg)
    bp = sd.snap(beltG, [0, BELT_Y, -0.3], 0.002)
    with sd.group(name='buckle', mat='gold', bone='hips', rigid=True, k=0.003):
        with sd.frame(pos=bp, rot=[-math.pi / 2, 0, 0]):
            sd.cylinder(r=0.027, h=0.005, round=0.004)
            sd.cylinder(op='sub', k=0.002, pos=[0, 0.004, 0], r=0.017, h=0.004, round=0.002)
        sd.box(mat='leather', pos=[bp[0], bp[1], bp[2] - 0.002], size=[0.016, 0.009, 0.004], round=0.003)

    # 4 gold buttons down the front of the skirt
    def _sg():
        sd.ellipsoid(pos=[0, Y.hip + 0.06, 0.008], r=[0.156, 0.075, 0.114])
        sd.cone(pos=[0, Y.hip - 0.07, 0.01], h=0.13, r1=0.21, r2=0.172, round=0.014, scale=[1, 1, 0.84])
    skirtG = sd.guide({'k': 0.05}, _sg)
    for i in range(4):
        by = BELT_Y - 0.05 - i * 0.047
        sd.sphere(mat='gold', bone='hips', rigid=True, pos=sd.snap(skirtG, [0, by, -0.3], 0.001), r=0.0095, scale=[1, 1, 0.6], k=0.002)
    st = O(mats=['cord'], color='#E6A15C', width=0.0013)
    sd.stitch([[0.022, BELT_Y - 0.03, -0.3], [0.022, Y.hip - 0.19, -0.3]], st)
    sd.stitch([[-0.022, BELT_Y - 0.03, -0.3], [-0.022, Y.hip - 0.19, -0.3]], st)
    hem = []
    for i in range(37):
        a = (i / 36) * math.pi * 2
        hem.append([math.sin(a) * 0.2, Y.hip - 0.188, 0.01 + math.cos(a) * 0.168])
    sd.stitch(hem, O(st, smooth=False))
    sd.mirrorX(lambda: sd.stitch([[0.06, BELT_Y - 0.03, -0.14], [0.1, BELT_Y - 0.07, -0.12], [0.14, BELT_Y - 0.08, -0.07]], st))

    # ---------------- head ----------------
    with sd.bone('head'), sd.frame(scale=HS):
        sd.group({'name': 'head', 'mat': 'skin', 'k': 0.07, 'blend': 0.02}, lambda: headShapes(sd, sd.expr))
        lipsPaint(sd, sd.expr)
        sd.paint({'color': '#F08A86', 'soft': 0.035, 'strength': 0.7, 'only': ['skin']}, lambda: sd.mirrorX(lambda: sd.sphere(pos=[0.085, 0.15, -0.13], r=0.028)))
        sd.paint({'color': '#F29C8A', 'soft': 0.02, 'strength': 0.45, 'only': ['skin']}, lambda: sd.sphere(pos=[0, 0.176, -0.205], r=0.016))

        # (the orange headband is the rigid part 'hband': its own mesh keeps its edges crisp against hair and skin)

        # ---- hair on the head: crown with a soft side part + one big side-swept fringe lock ----
        def hflow(x, y, z):
            return [x * 1.5 - 0.5, -1, 0.5]
        with sd.group(name='hairTop', mat='hair', blend=0.012, k=0.03, flow=hflow):
            with sd.group(k=0.04):
                sd.ellipsoid(pos=CROWN.c, r=CROWN.r)
                sd.ellipsoid(op='sub', k=0.03, pos=[0, 0.2, -0.21], r=[0.142, 0.21, 0.19])                 # face opening
            # fringe: from the part (+x) sweeping down across the forehead to the left temple (-x), laid on the crown
            with sd.group(k=0.035):
                sd.ellipsoid(pos=[-0.032, 0.366, -0.122], r=[0.108, 0.04, 0.022], rot=[0.57, 0.3, 0.67])
                sd.ellipsoid(pos=[-0.12, 0.3, -0.088], r=[0.05, 0.034, 0.02], rot=[0.3, 0.8, 1.0])
            # a smaller lock on the part side, tucked behind the headband to the right temple
            hairLock(sd, [[40, 42, 0.0], [58, 30, 0.012], [74, 14, 0.014], [88, 0, 0.01]], [0.028, 0.038, 0.032, 0.012], O(flat=0.45))

    # ---------------- long hair: side curtains + back curtain with a wavy scalloped hem (world coords) ----------------
    # Skinned head -> neck -> chest (nearest segment): the lengths below the neck follow the chest. Kept behind the
    # shoulders (z > 0.06) and inside |x| < 0.18 so the arms never plough through it.
    def W(x, y, z):
        return [x * HS, H0 + y * HS, z * HS]   # head-local -> world

    def lflow(x, y, z):
        return [x * 0.3, -1, 0.1]
    with sd.group(name='hairLong', mat='hair', bone=['head', 'neck', 'chest'], blend=0.014, k=0.045, flow=lflow):
        # back of the head + nape
        sd.ellipsoid(pos=W(0, 0.2, 0.07), r=[0.2, 0.21, 0.165])

        # curtains over the ears (framing the face), falling behind the shoulders
        @sd.mirrorX
        def _():
            sd.ellipsoid(pos=W(0.16, 0.19, 0.03), r=[0.054, 0.17, 0.09])
            sd.ellipsoid(pos=[0.15, Y.sh + 0.03, 0.09], r=[0.052, 0.11, 0.055])
            sd.ellipsoid(pos=[0.16, Y.sh - 0.12, 0.105], r=[0.05, 0.1, 0.05])
            # S-wave bulges along the outer edge of the curtain
            sd.sphere(pos=[0.172, Y.sh + 0.1, 0.075], r=0.045)
            sd.sphere(pos=[0.18, Y.sh - 0.08, 0.105], r=0.048)
        # back curtain down to the shoulder blades
        sd.ellipsoid(pos=[0, Y.sh - 0.03, 0.125], r=[0.17, 0.17, 0.052])
        # scalloped hem: four round wave lobes
        for x, dy in [[-0.105, 0.0], [0.0, -0.02], [0.105, -0.005]]:
            sd.sphere(pos=[x, Y.sh - 0.185 + dy, 0.128], r=0.064)
    # flicked tips at the curtain ends (small C-curls turning outward)
    sd.mirrorX(lambda: sd.arc(mat='hair', bone='chest', pos=[0.175, Y.sh - 0.22, 0.1], rot=[0.2, 1.3, 2.0], R=0.028, r=0.019, angle=math.pi * 1.1, k=0.02))

    # ---------------- legs (tights) + go-go boots ----------------
    @sd.mirrorX
    def _():
        with sd.bone('hipL'):
            with sd.group(mat='tights', k=0.04, blend=0.012):
                sd.roundCone(a=[0.018, 0.02, 0.006], b=[0, -0.3, 0.004], ra=0.07, rb=0.056)
                sd.sphere(pos=[0, -0.31, 0.002], r=0.058)
        with sd.bone('kneeL'):
            sd.roundCone(mat='tights', a=[0, 0.0, 0.002], b=[0, -0.1, 0.004], ra=0.057, rb=0.056, k=0.02)
            # boot shaft: from just below the knee to the ankle, clean rolled top edge
            with sd.group(mat='boot', k=0.03, blend=0.004):
                sd.roundCone(a=[0, -0.035, 0.004], b=[0, -0.2, 0.01], ra=0.068, rb=0.064)       # calf
                sd.roundCone(a=[0, -0.2, 0.01], b=[0, -0.3, 0.004], ra=0.064, rb=0.049)         # ankle
                sd.cylinder(pos=[0, -0.034, 0.004], r=0.071, h=0.009, round=0.007)             # flared top rim
        with sd.bone('footL'), sd.frame(scale=1.08, pos=[0, 0.004, -0.004]):
            def upper():
                sd.ellipsoid(pos=[0, -0.02, -0.105], r=[0.058, 0.045, 0.118])
                sd.ellipsoid(pos=[0, -0.014, 0.01], r=[0.05, 0.05, 0.056])
                sd.ellipsoid(pos=[0, 0.02, -0.02], r=[0.052, 0.06, 0.06])
            sd.group({'mat': 'boot', 'k': 0.035}, upper)
            with sd.group(mat='sole', k=0.012, blend=0.004):
                sd.group({'offset': 0.004, 'k': 0.035}, upper)
                sd.box(op='int', k=0.003, pos=[0, -0.06, -0.06], size=[0.1, 0.011, 0.25], round=0.004)
            sd.box(mat='sole', pos=[0, -0.045, 0.028], size=[0.036, 0.026, 0.03], round=0.01, k=0.006)   # block heel

    # ---------------- arms (long knit sleeves, ribbed cuffs) ----------------
    @sd.mirrorX
    def _():
        with sd.bone('shoulderL'):
            slv = sd.patternFrame(pos=[0, -0.1, 0], mode='cyl', radius=0.055)
            with sd.group(mat='knit', k=0.035, blend=0.035, pframe=slv):
                sd.roundCone(a=[0.01, -0.02, 0], b=[0, -0.22, 0], ra=0.058, rb=0.05)
        with sd.bone('elbowL'):
            slv = sd.patternFrame(pos=[0, -0.1, 0], mode='cyl', radius=0.05)
            with sd.group(mat='knit', k=0.02, pframe=slv):
                sd.roundCone(a=[0, 0.03, 0], b=[0, -0.19, 0], ra=0.05, rb=0.044)
                sd.cylinder(pos=[0, -0.2, 0], r=0.05, h=0.03, round=0.014, k=0.012)      # ribbed cuff
            sd.roundCone(mat='skin', a=[0, -0.2, 0], b=[0, -0.24, 0], ra=0.032, rb=0.03, k=0.006)
        # hands: rigid parts, one per shape (_hands.py, HAND at the top)


def _hband(sd, ctx=None):
    with sd.bone('head'), sd.frame(scale=HS):
        with sd.group(name='hband', mat='band', k=0):
            sd.ellipsoid(pos=CROWN.c, r=[v + 0.016 for v in CROWN.r], shell=0.0085)
            sd.plane(op='int', k=0.004, n=HB.n, d=hbD(HB.half))
            sd.plane(op='int', k=0.004, n=[-v for v in HB.n], d=-hbD(-HB.half))
            sd.plane(op='int', k=0.012, n=[0, -1, 0], d=-0.33)         # ends tucked under the side curtains


def attachments(b, ctx=None):
    T3 = b.THREE
    HG = T3.Group()
    HG.name = 'headScaled'
    HG.scale.setScalar(HS)
    b.joint('head').add(HG)
    ES = O(EYE, x=EYE.x * HS, y=EYE.y * HS, z=EYE.z * HS, r=EYE.r * HS)
    b.eyes(ES)
    lashWings(b, ES, EYE.lash)
    roundGlasses(b, O(parent=HG, eye=EYE, r=0.06, thick=0.0105, depth=0.007, z=-0.192, dy=0.002, wrap=0.12, templeX=0.158, earZ=0.03))
    hoops = []
    for s in (1, -1):
        g = T3.TorusGeometry(0.03, 0.0055, 10, 32)
        g.rotateY(s * 0.6)
        g.translate(s * 0.146, 0.088, -0.058)   # hanging in front of the side curtains
        hoops.append(g)
    b.mesh(HG, mergeGeos(T3, hoops), b.mat(color='#FFC23A', metal=1, rough=0.2, envIntensity=1.2), O(name='hoops'))


DEF = O(
    id='penny',
    name='Penny Watts',
    kind='hero',
    # 1.68 m: headScale 1.3 like Duke; long legs in tights, short torso under the turtleneck.
    rig=O(height=1.68, headScale=1.3, shoulderW=0.36, hipW=0.25, legLen=0.84, torsoLen=0.44, armLen=0.55),
    bake=O(voxel=0.0042, tris=20200, aoStrength=0.85, aoReach=0.1, morphMax=0.04),
    armOut=0.22,
    poseOffset=O(hipL=[0, 0, -0.04], hipR=[0, 0, 0.04], footL=[0, 0, 0.04], footR=[0, 0, -0.04]),
    rim=O(color='#FFD9A0', strength=0.4),
    materials=O(
        skin=O(color=SKIN, rough=0.5, sss=1, wrap=0.6, cav=0.35),
        hair=O(color=HAIR, rough=0.4, sheen=1.0, sheenExp=65, wrap=0.55, spec=0.35, cav=0.5),
        band=O(color='#F0721E', rough=0.45, spec=0.6, cav=0.4),
        brow=O(color=BROW, rough=0.45, sheen=0.5, sheenExp=50, wrap=0.55, spec=0.3, cav=0.25),
        knit=O(color='#ffffff', rough=0.8, fuzz=0.45, bump=0.25, cav=0.5,
               pattern=O(type='knit', color='#F0641E', ribs=14, scale=0.09)),
        cord=O(color='#ffffff', rough=0.8, fuzz=0.5, lines=True, bump=0.3, cav=0.5,
               pattern=O(type='corduroy', color='#83492A', ribs=24, scale=0.1)),
        leather=O(color='#62371D', rough=0.36, spec=0.6, cav=0.5),
        gold=O(color='#EDB64C', metal=1, rough=0.2),
        tights=O(color='#4E2C25', rough=0.55, sss=0.2, fuzz=0.2, spec=0.5, cav=0.4),
        boot=O(color='#E8DAC0', rough=0.2, spec=0.95, cav=0.5),
        sole=O(color='#6A3D22', rough=0.45, spec=0.5, cav=0.4),
        mouth=O(color='#5C1C24', rough=0.55, sss=0.4, wrap=0.6, cav=0.1),
        teeth=O(color='#FFF9F0', rough=0.25, spec=0.7, wrap=0.6, cav=0.1),
        tongue=O(color='#E46F78', rough=0.4, sss=0.6, wrap=0.6, cav=0.1),
    ),
    anchors=lambda ctx=None: O(EYE=EYE),
    expressions=['smile', 'frown', 'o_mouth'],
    sculpt=sculpt,
    parts=O(
        hband=O(bone='head', tris=700, voxel=0.0034, sculpt=_hband),
        browL=O(bone='head', tris=380, sculpt=lambda sd, ctx=None: browShape(sd, 1)),
        browR=O(bone='head', tris=380, sculpt=lambda sd, ctx=None: browShape(sd, -1)),
        **handParts(HAND),
    ),
    attachments=attachments,
)
