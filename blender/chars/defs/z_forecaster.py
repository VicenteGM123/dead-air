"""Z_FORECASTER — THE FORECASTER, a "Stormy Stu" clone (GDD §8.3, STYLE_GUIDE §7). (Port of
src/art/chars/z_forecaster.js.) A 1.8 m zombie weatherman: loud mustard/brown checkered sport coat with HUGE chocolate
lapels, pale-yellow shirt with a spread collar, a wide red kipper tie, brown flares, white loafers, a MASSIVE glossy
pompadour and a GIANT toothy grin (his one exaggerated feature). Static-snow eyes with plum under-eyes.
Parts (rigid, baked): 'cloud' = his tiny grumpy rain cloud floating 0.6 m over his head — the runtime detaches it.
Attachments: the telescoping pointer in his right hand (userData.pointer = 'rod'|'tip'; rod group 'pointerRod'
scales along its length), static eyes, the "13 ADMIT ONE" stub on the lapel.
"""
import math

from ..jsutil import O
from ._sculpt import prism
from .z_crew import ZOMBIE_MATS, ZSHADOW, zEyeSocket, zEyeLid, zEyePaint, zHand, staticEyes, ticketStub

HAIR = '#3A2A22'
# Head-local anchors (origin = head joint; y up, -z forward)
EYES = [
    O(x=0.074, y=0.31, z=-0.152, r=0.052, pitch=0.02, yaw=-0.3, lid=0.32, droop=0.22, depth=0.7),
    O(x=-0.072, y=0.314, z=-0.153, r=0.058, pitch=0.04, yaw=0.3, lid=0.26, droop=0.18, depth=0.7),
]
MOUTH = O(y=0.128, z=-0.176, w=0.118, h=0.056, top=0.148, R=0.24)
CLOUD_Y = 0.6     # cloud centre above the top of the pompadour (world: head joint + ~0.62 + 0.6)


def torsoShapes(sd, Y):
    sd.ellipsoid(pos=[0, Y.sh - 0.1, 0.0], r=[0.205, 0.16, 0.135])          # chest
    sd.ellipsoid(pos=[0, Y.hip + 0.13, -0.012], r=[0.19, 0.14, 0.14])        # belly (a little paunch)
    sd.ellipsoid(pos=[0, Y.sh - 0.01, 0.012], r=[0.235, 0.058, 0.108])       # wide shoulder yoke


def headSkin(sd):
    with sd.group(k=0.07):
        sd.ellipsoid(pos=[0, 0.31, 0.01], r=[0.168, 0.2, 0.172])                # cranium
        sd.ellipsoid(pos=[0, 0.15, -0.03], r=[0.182, 0.125, 0.155])            # wide square jaw (holds the grin)
    sd.ellipsoid(pos=[0, 0.066, -0.075], r=[0.105, 0.05, 0.075], k=0.05)  # chin
    # small upturned nose
    sd.capsule(a=[0, 0.3, -0.172], b=[0, 0.245, -0.2], r=0.018, k=0.02)
    sd.sphere(pos=[0, 0.236, -0.206], r=0.029, k=0.016)

    # ears
    @sd.mirrorX
    def _():
        sd.ellipsoid(pos=[0.172, 0.24, 0.02], rot=[0, -0.3, 0.15], r=[0.024, 0.05, 0.034], k=0.014)
        sd.ellipsoid(op='sub', k=0.008, pos=[0.187, 0.238, 0.016], rot=[0, -0.3, 0.15], r=[0.011, 0.03, 0.019])


def _cloud(sd, ctx):
    hy = ctx.J['head'].pos[1]
    cy = hy + 0.62 + CLOUD_Y
    with sd.group(mat='cloud', k=0.045):
        sd.sphere(pos=[0, cy + 0.03, 0], r=0.12)
        sd.sphere(pos=[-0.12, cy - 0.02, 0.01], r=0.09)
        sd.sphere(pos=[0.125, cy - 0.015, 0.0], r=0.095)
        sd.sphere(pos=[-0.05, cy - 0.055, -0.03], r=0.085)
        sd.sphere(pos=[0.06, cy + 0.07, 0.05], r=0.09)
        sd.ellipsoid(pos=[0, cy - 0.07, 0.0], r=[0.19, 0.045, 0.1])        # flat-ish underside
    # grumpy face: two small slanted eye slits, angry brows, a downturned mouth (carved)
    with sd.group(op='sub', blend=0.004, cutMat='cloudface'):
        sd.mirrorX(lambda: sd.ellipsoid(pos=[0.045, cy + 0.0, -0.118], rot=[0, 0, 0.35], r=[0.02, 0.011, 0.03]))
        sd.arc(pos=[0, cy - 0.075, -0.112], rot=[-math.pi / 2 + 0.25, 0, 0], R=0.032, r=0.006, angle=1.2)
    sd.mirrorX(lambda: sd.capsule(mat='cloudface', a=[0.018, cy + 0.028, -0.124], b=[0.07, cy + 0.045, -0.11], r=0.007, k=0.003))
    # the dangling raindrop: a teardrop hanging on a short droplet neck under the cloud
    with sd.group(mat='drop', k=0.012):
        sd.capsule(a=[0.03, cy - 0.105, -0.02], b=[0.03, cy - 0.15, -0.02], r=0.008)
        sd.sphere(pos=[0.03, cy - 0.19, -0.02], r=0.028)
        sd.roundCone(a=[0.03, cy - 0.19, -0.02], b=[0.03, cy - 0.145, -0.02], ra=0.027, rb=0.006)


def sculpt(sd, ctx):
    J = ctx.J
    Y = O(hip=J['hips'].pos[1], sh=J['shoulderL'].pos[1], neck=J['neck'].pos[1], head=J['head'].pos[1])

    # ---------------- neck + shirt + tie ----------------
    sd.capsule(mat='skin', bone='torso', a=[0, Y.sh - 0.02, 0.01], b=[0, Y.head + 0.06, 0.004], r=0.07, k=0.03)
    shirt = sd.group({'name': 'shirt', 'mat': 'shirt', 'bone': 'torso', 'k': 0.05}, lambda: torsoShapes(sd, Y))
    # big spread shirt collar lying over the lapels
    with sd.group(name='collar', mat='shirt', bone='torso', blend=0.008, k=0.014):
        sd.torus(pos=[0, Y.sh + 0.045, 0.016], rot=[0.12, 0, 0], R=0.078, r=0.02)
        sd.mirrorX(lambda: sd.ellipsoid(pos=[0.07, Y.sh + 0.015, -0.1], rot=[0.55, 0.5, 0.95], r=[0.056, 0.03, 0.011]))
    tieFr = sd.patternFrame(pos=[0, Y.sh - 0.1, -0.15], rot=[0, 0, 0.7], mode='tri')
    with sd.group(name='tie', mat='tie', bone='chest', pframe=tieFr, blend=0.004, k=0.01):
        k0 = sd.snap(shirt, [0, Y.sh + 0.01, -0.2], 0.014)
        sd.box(pos=k0, rot=[0.3, 0, 0], size=[0.026, 0.024, 0.016], round=0.014)
        p1 = sd.snap(shirt, [0, Y.sh - 0.07, -0.2], 0.013)
        p2 = sd.snap(shirt, [0, Y.sh - 0.17, -0.2], 0.015)
        p3 = sd.snap(shirt, [0.004, Y.sh - 0.25, -0.2], 0.017)
        with sd.group(k=0.012):
            sd.worm(pts=[[k0[0], k0[1] - 0.014, k0[2]], p1, p2, p3], r=[0.022, 0.04, 0.06, 0.066], flat=0.22, up=[0, 0.1, -1], segs=16)
            with sd.frame(pos=[p3[0], p3[1] - 0.016, p3[2]]):
                sd.plane(op='int', k=0.006, n=[0.7, -0.72, 0], d=0.03)
                sd.plane(op='int', k=0.006, n=[-0.7, -0.72, 0], d=0.03)

    # ---------------- the loud checkered sport coat ----------------
    coatFr = sd.patternFrame(pos=[0, Y.hip, 0], mode='cyl', radius=0.19)
    VT = O(a=[0, Y.hip + 0.06, -0.14], b=[0, Y.sh + 0.02, -0.13], ra=0.03, rb=0.105)
    with sd.group(name='coat', mat='coat', bone='torso', pframe=coatFr, blend=0.006, k=0.02) as coat:
        with sd.group(offset=0.016, k=0.05):
            torsoShapes(sd, Y)
            sd.ellipsoid(pos=[0, Y.hip + 0.0, 0.0], r=[0.19, 0.13, 0.14])     # skirt over the hips
        sd.roundCone(O(VT, op='sub', k=0.012))
        sd.capsule(op='sub', k=0.02, a=[0, Y.sh + 0.0, 0.03], b=[0, Y.sh + 0.15, 0.03], r=0.085)
        sd.plane(op='int', k=0.008, n=[0, -1, 0], d=-(Y.hip - 0.1))
        sd.sphere(op='sub', k=0.006, pos=[-0.13, Y.hip - 0.1, -0.12], r=0.035)   # clean rounded bite out of the hem
    # HUGE 70s lapels: a raised panel following the coat, cut to a wide peaked footprint along the V
    with sd.group(name='lapels', mat='lapel', bone='torso', blend=0.003):
        with sd.group(offset=0.0195, shell=0.0068, k=0.05):
            torsoShapes(sd, Y)
            sd.ellipsoid(pos=[0, Y.hip + 0.0, 0.0], r=[0.19, 0.13, 0.14])
        with sd.group(op='int', k=0.008):
            sd.mirrorX(lambda: prism(sd, [[0.015, Y.hip + 0.05], [0.16, Y.sh - 0.09], [0.24, Y.sh + 0.03], [0.14, Y.sh + 0.05], [0.09, Y.sh + 0.03]], {'max': 0.03, 'k': 0.016}))
        sd.roundCone(O(VT, op='sub', k=0.004, ra=VT.ra - 0.002, rb=VT.rb - 0.002))
        sd.capsule(op='sub', k=0.01, a=[0, Y.sh + 0.0, 0.03], b=[0, Y.sh + 0.15, 0.03], r=0.087)
    for by in [Y.hip + 0.03, Y.hip - 0.05]:
        bt = sd.snap(coat, [0.05, by, -0.25], 0.002)
        sd.ellipsoid(mat='button', bone='torso', rigid=True, pos=bt, r=[0.013, 0.013, 0.007], k=0.002)
    sd.stitch([[-0.07, Y.sh - 0.08, -0.25], [-0.16, Y.sh - 0.07, -0.25]], mats=['coat'], color='#6B3418', smooth=False)
    sd.mirrorX(lambda: sd.stitch([[0.07, Y.hip - 0.03, -0.25], [0.16, Y.hip - 0.02, -0.25]], mats=['coat'], color='#6B3418', smooth=False))

    # ---------------- head ----------------
    with sd.bone('head'):
        with sd.group(name='head', mat='skin', k=0.02, blend=0.03) as head:
            headSkin(sd)
            for E in EYES:
                zEyeSocket(sd, E)
            # GIANT toothy grin: a wide crescent carved into the jaw (corners curl up)
            with sd.group(name='grin', op='sub', blend=0.006, cutMat='mouth', k=0):
                sd.ellipsoid(pos=[0, MOUTH.y, MOUTH.z], r=[MOUTH.w, MOUTH.h, 0.06])
                sd.sphere(op='sub', k=0.004, pos=[0, MOUTH.top + MOUTH.R, MOUTH.z], r=MOUTH.R)

        # teeth: a row of big square upper teeth hugging the upper lip arc + 4 lower ones
        def arcY(x):
            return MOUTH.top + MOUTH.R - math.sqrt(MOUTH.R * MOUTH.R - x * x)
        for i in range(6):
            x = (i - 2.5) * 0.031
            zz = MOUTH.z + 0.022 + abs(x) * 0.35
            sd.box(mat='teeth', pos=[x, arcY(x) - 0.017, zz], rot=[0.15, -x * 1.6, 0], size=[0.0135, 0.019, 0.01], round=0.008, k=0.003)
        for i in range(4):
            x = (i - 1.5) * 0.03
            zz = MOUTH.z + 0.03 + abs(x) * 0.3
            sd.box(mat='teeth', pos=[x, MOUTH.y - MOUTH.h + 0.02 + abs(x) * 0.12, zz], rot=[-0.15, -x * 1.6, 0], size=[0.012, 0.014, 0.009], round=0.007, k=0.003)
        for E in EYES:
            zEyeLid(sd, E)
        for E in EYES:
            zEyePaint(sd, E)
        sd.paint({'color': ZSHADOW, 'soft': 0.03, 'strength': 0.35, 'only': ['skin']}, lambda: sd.ellipsoid(pos=[0, 0.07, -0.04], r=[0.15, 0.05, 0.16]))
        sd.paint({'color': '#8DB58A', 'soft': 0.02, 'strength': 0.5, 'only': ['skin']}, lambda: sd.sphere(pos=[0, 0.236, -0.22], r=0.03))

        # bold showman brows (raised, a bit uneven)
        @sd.mirrorX
        def _(m):
            up = 0.012 if m else 0
            pts = sd.snapAll(head, [[0.035, 0.392 + up * 0.5, -0.25], [0.085, 0.412 + up, -0.25], [0.135, 0.394 + up * 0.6, -0.2]], [0.008, 0.01, 0.008])
            sd.worm(mat='brow', pts=pts, r=[0.013, 0.02, 0.011], flat=0.5, up=[0, 0.2, -1], segs=12, k=0.004)

        # ---- MASSIVE molded-toy pompadour: a big forward wave, slicked sides, full back ----
        def hflow(x, y, z):
            return [x * 1.4, 0.2, 1]
        with sd.group(name='hair', mat='hair', blend=0.006, k=0.06, flow=hflow):
            sd.ellipsoid(pos=[0, 0.39, 0.03], r=[0.18, 0.15, 0.176])                       # dome over the cranium
            sd.ellipsoid(pos=[0, 0.31, 0.06], r=[0.172, 0.16, 0.13])                       # back, down to the nape
            sd.ellipsoid(pos=[0, 0.5, -0.07], rot=[-0.28, 0, 0], r=[0.158, 0.1, 0.19])    # the pomp mass, rising forward
            sd.capsule(a=[-0.09, 0.535, -0.215], b=[0.09, 0.535, -0.215], r=0.075)         # the big front roll
            sd.mirrorX(lambda: sd.ellipsoid(pos=[0.152, 0.37, 0.03], rot=[0.25, 0.06, 0.06], r=[0.04, 0.1, 0.15]))   # slicked sides
            sd.ellipsoid(op='sub', k=0.03, pos=[0, 0.25, -0.28], r=[0.2, 0.2, 0.16])      # hairline in front of the face
            sd.plane(op='int', k=0.05, n=[0, -0.9, 0.44], d=-0.14)                       # nape
            sd.plane(op='int', k=0.04, n=[0, -0.35, -0.94], d=0.2)                       # keep the back compact
        sd.mirrorX(lambda: sd.worm(mat='hair', pts=sd.snapAll(head, [[0.168, 0.33, -0.02], [0.172, 0.27, -0.03], [0.17, 0.235, -0.034]], [0.003, 0.003, 0.001]), r=[0.02, 0.018, 0.011], flat=0.5, up=[1, 0, 0], k=0.01, segs=10))  # sideburns

    # ---------------- flares + white loafers ----------------
    sd.group({'name': 'pelvis', 'mat': 'pants', 'bone': 'torso', 'k': 0.03}, lambda: sd.ellipsoid(pos=[0, Y.hip - 0.02, 0.004], r=[0.17, 0.1, 0.13]))

    @sd.mirrorX
    def _():
        with sd.bone('hipL'):
            with sd.group(mat='pants', k=0.04, blend=0.03):
                sd.roundCone(a=[0.03, -0.03, 0.004], b=[0, -0.28, 0.004], ra=0.092, rb=0.07)
                sd.cone(pos=[0, -0.43, 0.006], h=0.15, r1=0.12, r2=0.07, round=0.01)
            sd.stitch([[0, 0.02, -0.1], [0, -0.28, -0.08], [0, -0.56, -0.13]], mats=['pants'], color='#8A5A36')
        with sd.bone('footL'):
            def upper():
                sd.ellipsoid(pos=[0, -0.028, -0.085], r=[0.066, 0.046, 0.156])
                sd.sphere(pos=[0, -0.024, -0.172], r=0.06)
                sd.ellipsoid(pos=[0, -0.01, 0.0], r=[0.058, 0.056, 0.066])
            sd.group({'mat': 'shoe', 'k': 0.035}, upper)
            with sd.group(mat='sole', blend=0.0):
                sd.group({'offset': 0.006, 'k': 0.035}, upper)
                sd.box(op='int', k=0.003, pos=[0, -0.064, -0.07], size=[0.13, 0.01, 0.29], round=0.003)
            sd.ellipsoid(mat='gold', rigid=True, pos=[0, 0.012, -0.12], r=[0.03, 0.008, 0.014], k=0.003)   # loafer bit

    # ---------------- arms: checkered sleeves, shirt cuffs, big zombie hands ----------------
    @sd.mirrorX
    def _():
        with sd.bone('shoulderL'):
            fr = sd.patternFrame(pos=[0, -0.1, 0], mode='cyl', radius=0.065)
            with sd.group(mat='coat', k=0.03, pframe=fr):
                sd.ellipsoid(pos=[-0.012, -0.03, 0.004], r=[0.07, 0.07, 0.068])
                sd.roundCone(a=[0, -0.03, 0], b=[0, -0.23, 0], ra=0.066, rb=0.056)
        with sd.bone('elbowL'):
            fr = sd.patternFrame(pos=[0, -0.1, 0], mode='cyl', radius=0.055)
            sd.group({'mat': 'coat', 'k': 0.02, 'pframe': fr}, lambda: sd.roundCone(a=[0, 0.02, 0], b=[0, -0.215, 0.002], ra=0.056, rb=0.052))
            sd.group({'mat': 'shirt', 'blend': 0.004, 'k': 0.008}, lambda: sd.cylinder(pos=[0, -0.224, 0], r=0.05, h=0.014, round=0.008))
            sd.roundCone(mat='skin', a=[0, -0.2, 0], b=[0, -0.262, 0], ra=0.038, rb=0.036, k=0.008)
        sd.bone('handL', lambda: zHand(sd, O(scale=1.4, curl=0.45)))


def attachments(b, ctx=None):
    T3 = b.THREE
    staticEyes(b, EYES)
    ticketStub(b, O(joint='chest', pos=[-0.12, 0.09, -0.125], rot=[0.12, 0.4, -0.5], w=0.085, h=0.047))
    # telescoping pointer: 3 chrome segments + a red tip, gripped in the right fist, extending past the knuckles
    chrome = b.mat(color='#D9DDE3', metal=1, rough=0.18, envIntensity=1.1)
    red = b.mat(color='#E23B2F', rough=0.35)
    grip = T3.Group()
    grip.name = 'pointerGrip'
    grip.position.set(0, -0.09, -0.02)
    grip.rotation.set(-0.35, 0, 0)
    b.joint('handR').add(grip)
    rod = T3.Group()
    rod.name = 'pointerRod'
    rod.userData['pointer'] = 'rod'
    grip.add(rod)
    segs = [[0.0075, 0.2, 0.06], [0.0058, 0.2, 0.24], [0.0042, 0.2, 0.42]]
    for r, ln, y0 in segs:
        m = b.mesh(rod, T3.CylinderGeometry(r, r, ln, 10), chrome, O(pos=[0, -(y0 + ln / 2) + 0.12, 0], name='pointerSeg', cast=False))
        m.userData['pointer'] = 'rod'
    tip = b.mesh(rod, T3.SphereGeometry(0.014, 14, 10), red, O(pos=[0, -0.52, 0], name='pointerTip', cast=False))
    tip.userData['pointer'] = 'tip'


DEF = O(
    id='z_forecaster',
    name='The Forecaster',
    kind='zombie',
    rig=O(height=1.74, headScale=1.45, shoulderW=0.47, hipW=0.28, legLen=0.8, torsoLen=0.5, armLen=0.64),
    bake=O(voxel=0.0046, tris=9400, aoStrength=0.9, aoReach=0.1),
    armOut=0.16,
    poseOffset=O(spine=[-0.04, 0, 0], head=[0.06, 0, 0], hipL=[0, 0, -0.03], hipR=[0, 0, 0.03]),
    rim=O(color='#8FF3FF', strength=0.3),
    materials=O(
        ZOMBIE_MATS,
        hair=O(color=HAIR, rough=0.34, sheen=1.0, sheenExp=70, wrap=0.5, spec=0.45, cav=0.5),
        brow=O(color='#2E211B', rough=0.45, sheen=0.5, sheenExp=50, wrap=0.5, cav=0.4),
        coat=O(color='#ffffff', rough=0.72, fuzz=0.35, wrap=0.5, lines=True, cav=0.5,
               pattern=O(type='check', a='#C9862B', b='#EFC75A', line='#6B3418', count=4, scale=0.6)),
        lapel=O(color='#5B321C', rough=0.62, fuzz=0.3, wrap=0.5, lines=True),
        shirt=O(color='#F4E6A6', rough=0.7, fuzz=0.25, wrap=0.55),
        tie=O(color='#ffffff', rough=0.5, spec=0.7, wrap=0.5,
              pattern=O(type='stripes', colors=['#D63A2C', '#F6E7C8', '#D63A2C', '#2F5FBF'], widths=[4, 0.8, 4, 0.8], scale=0.1, soft=0.03)),
        pants=O(color='#6B4226', rough=0.78, fuzz=0.3, wrap=0.5, lines=True),
        shoe=O(color='#F4F0E6', rough=0.2, spec=0.9, cav=0.4),
        sole=O(color='#3A2418', rough=0.6),
        gold=O(color='#E9B24A', metal=1, rough=0.25),
        button=O(color='#E9D6B0', rough=0.3, spec=0.7),
        cloud=O(color='#9AA3B2', rough=0.85, fuzz=0.4, wrap=0.75, cav=0.25, sss=0.2),
        cloudface=O(color='#2A2330', rough=0.6),
        drop=O(color='#5FB4FF', rough=0.08, spec=1.0, wrap=0.6),
    ),
    anchors=lambda ctx=None: O(EYES=EYES),
    parts=O(cloud=O(bone='head', tris=1500, sculpt=_cloud)),
    sculpt=sculpt,
    attachments=attachments,
)
