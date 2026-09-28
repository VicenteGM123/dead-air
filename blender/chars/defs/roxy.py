"""ROXY RIVERS v1 — host of "Boogie Down Saturday" (GDD §4, ref docs/ref/hero_disco.png). (Port of
src/art/chars/roxy.js.) Same recipes and finish as the approved Duke: SIMPLIFY + EXAGGERATE.
  - HUGE afro = her silhouette (~0.72 m wide): a clustered mass of round fuzzy puffs (felt-textured, no noise
    displacement) on a big soft volume, pushed back by an orange/yellow floral headband over the forehead.
  - Warm brown skin, big brown eyes with long lashes (lash wings ride the blinking lids), groomed arched brows,
    rosy lips in a confident smile, gold hoops.
  - White floral crop shirt: a real shell layer with a V neckline, flat pointed collar, puff sleeves with cuffs and a
    front knot; bare midriff; brown belt with a gold ring buckle.
  - Red bell-bottoms with the strongest flare of the cast, cream platform shoes with thick brown soles.
Layout: world coords for torso/pants (feet y=0, facing -z), bone-local for limbs and head (head scaled by HS).
"""
import math

from ..jsutil import O, nz
from ._face import EYE_DEFAULTS
from ._sculpt import prism, cartoonMouth

SKIN = '#9C603F'
AFRO = '#3B2419'
BROW = '#24150F'
LIPS = '#C4453F'

HS = 1.06
EYE = O(EYE_DEFAULTS, x=0.064, y=0.228, z=-0.128, r=0.046, iris='#8A4A22', irisSize=0.64, pupilSize=0.44,
        lid='#8E5637', lash='#160D0A', lidOpen=0.98, lowerLid=0.62, lidScale=1.04, yaw=0.07, glint=1.15, tilt=0.05)
SKULL = O(c=[0, 0.266, 0.012], r=[0.152, 0.174, 0.162])
MOUTH = O(
    base=O(y=0.1, w=0.042, h=0.017, top=0.096, R=0.065, teeth=0.85, roll=0.05, clip=True),
    smile=O(y=0.099, w=0.05, h=0.027, top=0.093, R=0.062, teeth=0.72, roll=0.04, clip=True),
    frown=O(y=0.095, w=0.034, h=0.012, top=0.103, R=-0.09, teeth=0.4, tongue=False, roll=0.02, clip=True),
    o_mouth=O(y=0.093, w=0.026, h=0.027, top=0.12, R=None, teeth=0.35, roll=0.001, clip=True),
)
# Headband: the plane through the hairline at the forehead (0, 0.37, -0.13) and just in front of the ears; the afro is
# on its +n side (top / back), the face on its -n side.
BAND = O(n=[0, 0.607, 0.794], p=[0, 0.37, -0.13], half=0.029)


def bandD(off):
    return BAND.n[0] * BAND.p[0] + BAND.n[1] * BAND.p[1] + BAND.n[2] * BAND.p[2] + off


AFRO_E = O(c=[0, 0.395, 0.05], r=[0.33, 0.315, 0.3])


def _jsmod(a, b):
    """JS a % b (sign of the dividend)."""
    return math.fmod(a, b)


# ------------------------------------------------------------------------------------------------------------
def torsoShapes(sd, Y):
    sd.ellipsoid(pos=[0, Y.sh - 0.08, 0.004], r=[0.148, 0.108, 0.098])       # rib cage
    sd.mirrorX(lambda: sd.sphere(pos=[0.052, Y.sh - 0.112, -0.05], r=0.056, k=0.05))   # modest bust
    sd.ellipsoid(pos=[0, Y.sh - 0.012, 0.01], r=[0.165, 0.044, 0.082])       # shoulder yoke


def waistShapes(sd, Y):
    sd.ellipsoid(pos=[0, Y.hip + 0.15, 0.008], r=[0.112, 0.105, 0.088])      # slim waist (midriff)


def headBase(sd, ex):
    smile = 1 if ex == 'smile' else 0
    sd.ellipsoid(pos=SKULL.c, r=SKULL.r)
    sd.ellipsoid(pos=[0, 0.212, -0.056], r=[0.134, 0.096, 0.096], k=0.06)                # soft face mask
    sd.ellipsoid(pos=[0, 0.146, -0.034], r=[0.12, 0.104, 0.124], k=0.07)                 # soft narrow jaw
    sd.ellipsoid(pos=[0, 0.07, -0.08], r=[0.042, 0.032, 0.04], k=0.05)                   # small chin
    sd.mirrorX(lambda: sd.sphere(pos=[0.072, 0.146 + smile * 0.012, -0.1 - smile * 0.004], r=0.048 + smile * 0.004, k=0.05))
    # small cute nose
    sd.capsule(a=[0, 0.226, -0.15], b=[0, 0.188, -0.176], r=0.014, k=0.02)
    sd.sphere(pos=[0, 0.174, -0.184], r=0.021, k=0.016)
    sd.mirrorX(lambda: sd.sphere(pos=[0.018, 0.166, -0.172], r=0.013, k=0.012))
    sd.mirrorX(lambda: sd.ellipsoid(pos=[0.148, 0.19, 0.018], r=[0.024, 0.044, 0.032], rot=[0, -0.3, 0.12], k=0.014))


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
    """Lips: a painted rosy ring around the carved mouth, following the expression (morph colors)."""
    m = MOUTH[ex] if ex in MOUTH else MOUTH.base
    with sd.paint(color=LIPS, soft=0.004, strength=0.95, only=['skin']):
        with sd.frame(pos=[0, m.y + (0 if m.R is None else 0.002), -0.15], rot=[0, 0, m.roll or 0]):
            sd.ellipsoid(pos=[0, 0, 0], r=[m.w + 0.009, (m.h if m.R is None else m.h * 0.9) + 0.011, 0.08])


def browShape(sd, s):
    # groomed dark arch: thick inner end, peak at the outer third, tapered tail
    with sd.bone('head'), sd.frame(scale=HS):
        H = sd.guide({'k': 0.07}, lambda: headBase(sd, None))
        P = [[0.026, 0.298], [0.05, 0.313], [0.078, 0.321], [0.104, 0.308]]
        # lifts = the brow's half thickness + ~1 mm (see skip)
        pts = sd.snapAll(H, [[x * s, y, -0.2] for x, y in P], [0.0048, 0.005, 0.0042, 0.0026])
        sd.worm(mat='brow', pts=pts, r=[0.0082, 0.0086, 0.0068, 0.0032], flat=0.45, up=[0, 0.25, -1], segs=14)


def afroVolume(sd, inset):
    sd.ellipsoid(pos=AFRO_E.c, r=[v - inset for v in AFRO_E.r])
    sd.plane(op='int', k=0.03, n=[-v for v in BAND.n], d=-bandD(0.014))           # behind the band
    sd.ellipsoid(op='sub', k=0.04, pos=[0, 0.19, -0.22], r=[0.15, 0.23, 0.2])       # face tunnel
    sd.plane(op='int', k=0.03, n=[0, -1, 0], d=-0.07)                               # bottom


_puffs = [None]


def afroPuffs():
    """Fibonacci points on the afro ellipsoid, filtered to the visible puff layer (behind the band, clear of the face)."""
    if _puffs[0] is not None:
        return _puffs[0]
    out = []
    _puffs[0] = out
    N = 200
    for i in range(N):
        y = 1 - (i + 0.5) / N * 2
        rr = math.sqrt(1 - y * y)
        th = i * 2.399963
        d = [math.cos(th) * rr, y, math.sin(th) * rr]
        p = [AFRO_E.c[0] + d[0] * AFRO_E.r[0], AFRO_E.c[1] + d[1] * AFRO_E.r[1], AFRO_E.c[2] + d[2] * AFRO_E.r[2]]
        if p[1] < 0.1:
            continue                                                                  # nothing below the jaw
        band = BAND.n[0] * p[0] + BAND.n[1] * p[1] + BAND.n[2] * p[2] - bandD(0)
        if band < 0.012:
            continue                                                                  # stays behind the headband
        fx, fy = p[0] / 0.165, (p[1] - 0.2) / 0.25
        if p[2] < -0.05 and fx * fx + fy * fy < 1:
            continue                                                                  # keep the face clear
        r = 0.052 + 0.014 * ((i * 7919) % 13) / 12
        out.append(O(p=[p[0] - d[0] * 0.028, p[1] - d[1] * 0.028, p[2] - d[2] * 0.028], r=r, ext=False))
    # puffs over the CUT faces of the afro volume (just behind the headband, and the sides of the face tunnel), so
    # no smooth base shows there: candidates on a 1 cm grid where the cut plane / tunnel is the active surface,
    # picked greedily with the same spacing as the Fibonacci layer
    E2 = [v - 0.03 for v in AFRO_E.r]
    T = O(c=[0, 0.19, -0.22], r=[0.15, 0.23, 0.2])

    def ell(q, c, r):
        return (math.hypot((q[0] - c[0]) / r[0], (q[1] - c[1]) / r[1], (q[2] - c[2]) / r[2]) - 1) * min(r)
    cand = []
    x = -0.34
    while x <= 0.34:
        y = 0.12
        while y <= 0.72:
            z = -0.3
            while z <= 0.2:
                q = [x, y, z]
                dE = ell(q, AFRO_E.c, E2)
                dP = bandD(0.014) - (BAND.n[1] * y + BAND.n[2] * z)
                dT = -ell(q, T.c, T.r)
                m = max(dE, dP, dT)
                if not (abs(m) > 0.005 or m == dE) and not (m == dT and y < 0.16):   # leave the jaw / hoops clear
                    if m == dP:
                        n = [0, BAND.n[1], BAND.n[2]]
                    else:                                                             # inward normal (into the volume)
                        g = [(x - T.c[0]) / T.r[0] ** 2, (y - T.c[1]) / T.r[1] ** 2, (z - T.c[2]) / T.r[2] ** 2]
                        l = math.hypot(*g)
                        n = [v / l for v in g]
                    inset = 0.05 if m == dP else 0.024                               # behind the band: the band stays proud
                    iv = int(x * 1000 + y * 377)                                      # (… | 0) truncates toward zero
                    cand.append(O(p=[x + n[0] * inset, y + n[1] * inset, z + n[2] * inset], r=0.05 + 0.012 * _jsmod(iv, 5) / 4, ext=False))
                z += 0.01
            y += 0.01
        x += 0.01
    for c in cand:
        if all(math.hypot(q.p[0] - c.p[0], q.p[1] - c.p[1], q.p[2] - c.p[2]) > 0.072 for q in out):
            out.append(c)
    # outermost puffs (top, left, right, back): flagged ext (baked in the body, skipped by the part)

    def pick(f):
        a = out[0]
        for q in out:
            if f(q) > f(a):
                a = q
        return a
    for f in (lambda q: q.p[1], lambda q: q.p[0], lambda q: -q.p[0], lambda q: q.p[2]):
        pick(f).ext = True
    return out


# ------------------------------------------------------------------------------------------------------------
def mergeGeos(T3, geos):
    parts = [g.toNonIndexed() if g.index is not None else g for g in geos]
    import numpy as np
    pos, nrm, uv = [], [], []
    for g in parts:
        if g.attributes.normal is None:
            g.computeVertexNormals()
        n = g.attributes.position.count
        pos.append(np.asarray(g.attributes.position).reshape(n, 3))
        nrm.append(np.asarray(g.attributes.normal).reshape(n, 3))
        uv.append(np.asarray(g.attributes.uv).reshape(n, 2) if g.attributes.uv is not None else np.zeros((n, 2)))
    out = T3.Geometry()
    out.setAttribute('position', T3.BufferAttribute(np.concatenate(pos), 3))
    out.setAttribute('normal', T3.BufferAttribute(np.concatenate(nrm), 3))
    out.setAttribute('uv', T3.BufferAttribute(np.concatenate(uv), 2))
    return out


def lashWings(b, E, color):
    """Long lashes: 3 curved tapered wings at the outer corner of each upper lid, parented to the lid group (they blink
    with it). Uses the eye rig made by b.eyes (root children: ball, glint, glint, upper, lower)."""
    T3 = b.THREE
    mat = b.mat(color=color, rough=0.5, rim=0.05)
    for side in ('L', 'R'):
        root = b.joint('head').getObjectByName('eye' + side)
        if not root or len(root.children) < 5:
            continue
        upper = root.children[3]
        sx = -1 if side == 'L' else 1                 # outer corner direction (eye L sits at -x)
        lr = E.r * nz(E.lidScale, 1.06)
        cap = math.pi * 0.53
        y0 = lr * math.cos(cap)
        geos = []
        for th, ln, up in [[0.95, 0.024, 0.0], [1.25, 0.03, 0.18], [1.55, 0.026, 0.36]]:
            p = T3.Vector3(sx * lr * math.sin(th), y0, -lr * math.cos(th))
            out = T3.Vector3(sx * math.sin(th), 0, -math.cos(th)).normalize()
            pts = []
            for i in range(7):
                t = i / 6
                pts.append(p.clone().addScaledVector(out, ln * t).add(T3.Vector3(0, (0.35 + up) * ln * t * t + 0.004 * t, 0)))
            g = T3.TubeGeometry(T3.CatmullRomCurve3(pts), 8, 1, 5)
            # taper: scale the ring radius along the tube (0.0026 -> 0.0004)
            P = g.attributes.position
            C = T3.CatmullRomCurve3(pts)
            for s in range(9):
                c = C.getPointAt(s / 8)
                rad = 0.0026 * (1 - s / 8) + 0.0004
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

    # ---------------- neck + torso (skin) ----------------
    with sd.group(name='neck', mat='skin', bone='torso', k=0.03):
        sd.capsule(a=[0, Y.sh - 0.04, 0.008], b=[0, Y.head + 0.07, 0.004], r=0.047)
    with sd.group(name='body', mat='skin', bone='torso', k=0.06, blend=0.012):
        torsoShapes(sd, Y)
        waistShapes(sd, Y)
    # belly button: a soft painted dot
    sd.paint({'color': '#6E3D25', 'soft': 0.004, 'strength': 0.7, 'only': ['skin']}, lambda: sd.ellipsoid(pos=[0, Y.hip + 0.12, -0.08], r=[0.005, 0.008, 0.05]))

    # ---------------- crop shirt: shell over the rib cage, V neckline, hem under the bust ----------------
    CROP = Y.sh - 0.185
    shirtFrame = sd.patternFrame(pos=[0, Y.sh - 0.08, 0], mode='cyl', radius=0.13)
    with sd.group(name='shirt', mat='shirt', bone='torso', blend=0.004, k=0, pframe=shirtFrame):
        with sd.group(offset=0.004, shell=0.0062, k=0.06):
            torsoShapes(sd, Y)
            waistShapes(sd, Y)
        prism(sd, [[0, CROP + 0.035], [0.078, Y.sh + 0.2], [-0.078, Y.sh + 0.2]], {'op': 'sub', 'max': -0.02, 'k': 0.008, 'blend': 0.004})
        sd.box(op='sub', k=0.008, pos=[0, CROP - 0.2, 0], size=[0.4, 0.2, 0.4])
    # front knot: a round knot + two short tails

    def _sg():
        torsoShapes(sd, Y)
        waistShapes(sd, Y)
    shirtG = sd.guide({'k': 0.06, 'offset': 0.01}, _sg)
    kp = sd.snap(shirtG, [0, CROP + 0.012, -0.25], 0.004)
    with sd.group(name='knot', mat='shirt', bone='torso', k=0.012, blend=0.006, pframe=shirtFrame):
        sd.ellipsoid(pos=kp, r=[0.024, 0.02, 0.016])

        @sd.mirrorX
        def _():
            sd.ellipsoid(pos=[kp[0] + 0.03, kp[1] - 0.014, kp[2] + 0.012], r=[0.028, 0.013, 0.01], rot=[0.2, 0.3, -0.5])
            sd.ellipsoid(pos=[kp[0] + 0.018, kp[1] - 0.03, kp[2] + 0.004], r=[0.012, 0.028, 0.009], rot=[0.15, 0, 0.35])
    # collar: flat pointed flaps lying open along the V
    FLAP = [[0.05, Y.sh + 0.045], [0.098, Y.sh + 0.05], [0.13, Y.sh - 0.015], [0.088, Y.sh - 0.1], [0.05, Y.sh - 0.02]]
    with sd.group(name='collar', mat='shirt', bone='torso', blend=0.004, k=0.01, pframe=shirtFrame):
        with sd.group(k=0.004):
            with sd.frame(pos=[0, Y.sh + 0.05, 0.012], rot=[-0.3, 0, 0]):
                sd.cylinder(r=0.07, h=0.011, round=0.005)
                sd.cylinder(op='sub', k=0.004, r=0.058, h=0.04)
            prism(sd, [[0, Y.sh - 0.07], [0.075, Y.sh + 0.2], [-0.075, Y.sh + 0.2]], {'op': 'sub', 'blend': 0.006, 'max': -0.01, 'k': 0.006})
        with sd.group(k=0, blend=0.01):
            sd.group({'offset': 0.0112, 'shell': 0.0052, 'k': 0.06}, lambda: torsoShapes(sd, Y))
            sd.group({'op': 'int', 'blend': 0.004, 'k': 0}, lambda: sd.mirrorX(lambda: prism(sd, FLAP, {'max': -0.01, 'k': 0.012})))

    # ---------------- head ----------------
    with sd.bone('head'), sd.frame(scale=HS):
        sd.group({'name': 'head', 'mat': 'skin', 'k': 0.07, 'blend': 0.02}, lambda: headShapes(sd, sd.expr))
        lipsPaint(sd, sd.expr)
        # warm blush + highlight on the nose tip
        sd.paint({'color': '#B8694A', 'soft': 0.035, 'strength': 0.5, 'only': ['skin']}, lambda: sd.mirrorX(lambda: sd.sphere(pos=[0.084, 0.15, -0.13], r=0.024)))
        sd.paint({'color': '#AE6A48', 'soft': 0.02, 'strength': 0.4, 'only': ['skin']}, lambda: sd.sphere(pos=[0, 0.176, -0.205], r=0.016))
        # eyeshadow: soft golden-brown above the eyes (shows when the lids close / on the brow bone)
        sd.paint({'color': '#7A4630', 'soft': 0.02, 'strength': 0.35, 'only': ['skin']}, lambda: sd.mirrorX(lambda: sd.ellipsoid(pos=[0.066, 0.27, -0.15], r=[0.03, 0.014, 0.05])))

        # (the floral headband is the rigid part 'band': its own mesh keeps its edges crisp against the skin)

        # ---- afro: the puff mass is the rigid part 'afro' (own triangle budget: the face keeps its detail). Only the
        # five outermost puffs live in the body, so the runtime's hair scan gives Roxy afro-sized hair bounds. ----
        with sd.group(name='afroExt', mat='afro', blend=0.004, k=0.008, flow=[0, -1, 0]):
            for q in [q for q in afroPuffs() if q.ext]:
                sd.sphere(pos=q.p, r=q.r)

    # ---------------- belt + pants ----------------
    pantFrame = sd.patternFrame(pos=[0, Y.hip, 0], mode='cyl', radius=0.14)
    with sd.group(name='pelvis', mat='pants', bone='torso', k=0.04, pframe=pantFrame, blend=0.006):
        sd.ellipsoid(pos=[0, Y.hip + 0.025, 0.008], r=[0.152, 0.112, 0.114])
        sd.ellipsoid(pos=[0, Y.hip + 0.075, 0.008], r=[0.128, 0.05, 0.096])
    BELT_Y = Y.hip + 0.07
    with sd.group(name='belt', mat='leather', bone='torso'):
        with sd.group(offset=0.005, k=0.04):
            sd.ellipsoid(pos=[0, Y.hip + 0.025, 0.008], r=[0.152, 0.112, 0.114])
            sd.ellipsoid(pos=[0, Y.hip + 0.075, 0.008], r=[0.128, 0.05, 0.096])
        sd.box(op='int', k=0.004, pos=[0, BELT_Y, 0], size=[0.3, 0.017, 0.3], round=0.002)
    with sd.group(name='buckle', mat='gold', bone='hips', rigid=True, k=0.003):
        sd.torus(pos=[0, BELT_Y, -0.106], rot=[math.pi / 2, 0, 0], R=0.021, r=0.0058)
        sd.box(pos=[0, BELT_Y, -0.105], size=[0.021, 0.0035, 0.004], round=0.0025)
    stitch = O(mats=['pants'], color='#F4A58E', width=0.0012)
    sd.stitch([[0, BELT_Y - 0.02, -0.106], [0.0, Y.hip - 0.04, -0.104], [-0.026, Y.hip - 0.07, -0.096]], stitch)
    sd.mirrorX(lambda: sd.stitch([[0.052, BELT_Y - 0.018, -0.108], [0.086, Y.hip - 0.005, -0.096], [0.132, Y.hip - 0.02, -0.06]], stitch))

    @sd.mirrorX
    def _():
        with sd.bone('hipL'):
            fr = sd.patternFrame(pos=[0, -0.35, 0], mode='cyl', radius=0.08)
            with sd.group(mat='pants', k=0.05, pframe=fr, blend=0.01):
                sd.roundCone(a=[0.012, 0.045, 0.006], b=[0, -0.31, 0.004], ra=0.088, rb=0.062)
                sd.sphere(pos=[0, -0.325, 0.002], r=0.062)
                # the strongest flare in the cast: a wide cone from the knee to the floor, flattened on the inner side and
                # pushed out so the two hems never touch in the bind pose (a merged hem would web between the legs)
                sd.cone(pos=[-0.042, -0.5, 0.0], h=0.17, r1=0.19, r2=0.062, round=0.012, scale=[0.72, 1, 1.04])
            out = [[-0.098, 0.05, 0], [-0.088, -0.15, 0], [-0.066, -0.32, 0], [-0.1, -0.46, 0], [-0.15, -0.6, 0], [-0.176, -0.66, 0]]
            sd.stitch(out, stitch)
            hem = []
            for i in range(33):
                a = (i / 32) * math.pi * 2
                hem.append([-0.042 + math.sin(a) * 0.134, -0.655, math.cos(a) * 0.194])
            sd.stitch(hem, O(stitch, smooth=False))
        with sd.bone('footL'), sd.frame(scale=1.14, pos=[0, 0.008, -0.01]):
            # cream platform shoe: rounded upper on a thick brown platform + chunky heel
            def upper():
                sd.ellipsoid(pos=[0, 0.002, -0.11], r=[0.062, 0.042, 0.125])
                sd.ellipsoid(pos=[0, 0.006, 0.012], r=[0.05, 0.044, 0.056])
                sd.ellipsoid(pos=[0, 0.022, -0.03], r=[0.046, 0.04, 0.07])
            sd.group({'mat': 'shoe', 'k': 0.035}, upper)
            with sd.group(mat='sole', k=0.012, blend=0.004):
                sd.box(pos=[0, -0.046, -0.07], size=[0.064, 0.022, 0.13], round=0.016)     # platform
                sd.box(pos=[0, -0.046, 0.03], size=[0.052, 0.024, 0.042], round=0.014)     # heel block

    # ---------------- arms ----------------
    @sd.mirrorX
    def _():
        with sd.bone('shoulderL'):
            slv = sd.patternFrame(pos=[0, -0.06, 0], mode='cyl', radius=0.07)
            with sd.group(mat='shirt', k=0.035, blend=0.035, pframe=slv):
                sd.ellipsoid(pos=[0.006, -0.055, 0], r=[0.066, 0.075, 0.066])              # puff sleeve
            with sd.group(mat='shirt', k=0.006, blend=0.004, pframe=slv):
                sd.torus(pos=[0, -0.118, 0], R=0.047, r=0.012)                           # rolled cuff
            sd.roundCone(mat='skin', a=[0, -0.08, 0], b=[0, -0.215, 0], ra=0.042, rb=0.038, k=0.01)
        with sd.bone('elbowL'):
            sd.roundCone(mat='skin', a=[0, 0.03, 0], b=[0, -0.235, 0], ra=0.039, rb=0.032, k=0.01)
        with sd.bone('handL'), sd.frame(scale=1.14, pos=[0, 0.006, 0]):
            with sd.group(mat='skin', k=0.01, blend=0.012):
                sd.roundCone(a=[0, 0.012, 0], b=[0.002, -0.03, 0], ra=0.03, rb=0.036, k=0.015)
                sd.box(pos=[0.002, -0.055, 0], size=[0.02, 0.047, 0.044], round=0.019, k=0.015)
                sd.ellipsoid(pos=[0.012, -0.045, -0.029], r=[0.016, 0.028, 0.02], k=0.012)
                fz, fl = [-0.033, -0.011, 0.011, 0.032], [0.064, 0.072, 0.068, 0.056]
                for i in range(4):
                    z, l, sp = fz[i], fl[i], (i - 1.5) * 0.003
                    sd.worm(pts=[[0.002, -0.088, z], [0.008, -0.088 - l * 0.55, z + sp], [0.018, -0.088 - l, z + sp * 1.5]], r=[0.0098, 0.0094, 0.0086], k=0.004, segs=8)
                    sd.sphere(pos=[-0.008, -0.088, z], r=0.0098, k=0.008)
                sd.worm(pts=[[0.012, -0.028, -0.036], [0.022, -0.053, -0.058], [0.03, -0.075, -0.062]], r=[0.0142, 0.012, 0.0108], k=0.01, segs=8)
            # nail polish: red fingertips
            with sd.paint(color='#D8322B', soft=0.002, strength=0.9, only=['skin']):
                fz, fl = [-0.033, -0.011, 0.011, 0.032], [0.064, 0.072, 0.068, 0.056]
                for i in range(4):
                    sd.sphere(pos=[0.024, -0.088 - fl[i] + 0.004, fz[i] + (i - 1.5) * 0.0045], r=0.0085)


def _band_part(sd, ctx=None):
    with sd.bone('head'), sd.frame(scale=HS):
        with sd.group(name='band', mat='band', k=0):
            sd.ellipsoid(pos=SKULL.c, r=[v + 0.013 for v in SKULL.r], shell=0.0095)
            sd.plane(op='int', k=0.004, n=BAND.n, d=bandD(BAND.half))
            sd.plane(op='int', k=0.004, n=[-v for v in BAND.n], d=-bandD(-BAND.half))
            sd.plane(op='int', k=0.01, n=[0, -1, 0], d=-0.2)


def _afro_part(sd, ctx=None):
    with sd.bone('head'), sd.frame(scale=HS):
        with sd.group(name='puffs', mat='afro', k=0.008, flow=[0, -1, 0]):
            sd.group({'k': 0.04}, lambda: afroVolume(sd, 0.06))          # crevice floor (only exposed between puffs)
            for q in afroPuffs():
                if not q.ext:
                    sd.sphere(pos=q.p, r=q.r)


def attachments(b, ctx=None):
    T3 = b.THREE
    HG = T3.Group()
    HG.name = 'headScaled'
    HG.scale.setScalar(HS)
    b.joint('head').add(HG)
    ES = O(EYE, x=EYE.x * HS, y=EYE.y * HS, z=EYE.z * HS, r=EYE.r * HS)
    b.eyes(ES)
    lashWings(b, ES, EYE.lash)
    # big gold hoops hanging at the jaw line, just outside the afro edge
    hoops = []
    for s in (1, -1):
        g = T3.TorusGeometry(0.036, 0.0058, 10, 36)
        g.rotateY(s * 0.6)
        g.translate(s * 0.158, 0.098, 0.004)
        hoops.append(g)
    b.mesh(HG, mergeGeos(T3, hoops), b.mat(color='#FFC23A', metal=1, rough=0.2, envIntensity=1.2), O(name='hoops'))


DEF = O(
    id='roxy',
    name='Roxy Rivers',
    kind='hero',
    # 1.70 m (+ the afro): headScale 1.3 like Duke, long dancer legs, short torso with a bare midriff.
    rig=O(height=1.70, headScale=1.3, shoulderW=0.36, hipW=0.25, legLen=0.84, torsoLen=0.44, armLen=0.55),
    bake=O(voxel=0.0042, tris=15000, aoStrength=0.8, aoReach=0.1, morphMax=0.04),
    armOut=0.2,
    # head costume slot on top of the afro (the puffs are a part, not counted by the runtime's hair scan)
    slots=O(head=[0, 0.745, 0.05]),
    poseOffset=O(hipL=[0, 0, -0.05], hipR=[0, 0, 0.05], footL=[0, 0, 0.05], footR=[0, 0, -0.05]),
    rim=O(color='#FFD9A0', strength=0.45),
    materials=O(
        skin=O(color=SKIN, rough=0.46, sss=0.8, wrap=0.6, cav=0.35, spec=0.8),
        afro=O(color='#ffffff', rough=0.95, fuzz=0.7, wrap=0.6, spec=0.05, cav=0.8, bump=0.6,
               pattern=O(type='felt', color=AFRO, scale=0.045)),
        band=O(color='#ffffff', rough=0.6, fuzz=0.3, cav=0.4,
               pattern=O(type='floral', base='#F6B21E', petal='#E8541E', center='#FFE27A', density=4, scale=0.09)),
        brow=O(color=BROW, rough=0.45, sheen=0.4, sheenExp=50, wrap=0.55, spec=0.3, cav=0.25),
        shirt=O(color='#ffffff', rough=0.66, fuzz=0.3, lines=True, cav=0.45,
                pattern=O(type='floral', base='#FBF3E4', petal='#F28A1E', center='#E8541E', density=3, scale=0.16)),
        pants=O(color='#ffffff', rough=0.72, fuzz=0.3, lines=True, bump=0.08, cav=0.5,
                pattern=O(type='denim', color='#D8322B', twill=150, scale=0.05)),
        leather=O(color='#6A3A1E', rough=0.38, spec=0.6, cav=0.5),
        gold=O(color='#EDB64C', metal=1, rough=0.2),
        shoe=O(color='#DFCDB1', rough=0.38, spec=0.6, cav=0.55),
        sole=O(color='#8A5230', rough=0.45, spec=0.5, cav=0.4),
        mouth=O(color='#5C1C24', rough=0.55, sss=0.4, wrap=0.6, cav=0.1),
        teeth=O(color='#FFF9F0', rough=0.25, spec=0.7, wrap=0.6, cav=0.1),
        tongue=O(color='#E46F78', rough=0.4, sss=0.6, wrap=0.6, cav=0.1),
    ),
    anchors=lambda ctx=None: O(EYE=EYE),
    expressions=['smile', 'frown', 'o_mouth'],
    sculpt=sculpt,
    parts=O(
        band=O(bone='head', tris=900, voxel=0.0034, sculpt=_band_part),
        # the afro's round puffs: rigid on the head, own budget (the body keeps ~15k for the face and costume)
        afro=O(bone='head', tris=5300, voxel=0.0045, sculpt=_afro_part),
        browL=O(bone='head', tris=380, sculpt=lambda sd, ctx=None: browShape(sd, 1)),
        browR=O(bone='head', tris=380, sculpt=lambda sd, ctx=None: browShape(sd, -1)),
    ),
    attachments=attachments,
)
