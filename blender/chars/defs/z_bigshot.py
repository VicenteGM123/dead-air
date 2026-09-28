"""Z_BIGSHOT — BIG SHOT, the camera operator fused with his studio pedestal (GDD §8.4, STYLE_GUIDE §7). 2.2 m:
(Port of src/art/chars/z_bigshot.js.) a rounded-triangle dolly base with cable guards and three casters, a telescoping
pedestal column with the chrome steering ring, a chubby zombie torso in a 70s ringer tee sitting on the pan-head
collar, chubby arms gripping the pan handles, and a BIG boxy studio camera for a head: steel-blue housing with a cream
band, a huge lens snout, two static-snow eyes on the front face, a red tally light on top like a hat, a headset
strapped over it (orange foam cups, mic boom) and a viewfinder hood at the back. The trailing cable + glowing plug
(his weak point) are built at runtime (they drag on the floor).

Custom skeleton: base (root) -> column -> torso -> head, torso -> shoulderL/R -> elbowL/R -> handL/R.
Attachment tags: userData.wheel (caster wheels, spin about local x), userData.caster (swivel forks),
userData.tally (the red tally lamp mesh), userData.staticEye (eyes), 'lensFront' (Object3D at the lens glass
centre, -z out of the lens) for the runtime iris / flash. The JS createAnimator (preview idle) is runtime code.
"""
import math

from ..jsutil import O
from ._sculpt import prism
from .z_crew import ZOMBIE_MATS, zEyeSocket, zEyeLid, staticEyes

HEAD_Y = 1.5
# Head-local static eyes on the camera's front face (the housing front is at z = -0.27)
EYES = [
    O(x=0.098, y=0.405, z=-0.268, r=0.056, pitch=0.0, yaw=-0.12, lid=0.34, droop=0.22, depth=0.6),
    O(x=-0.1, y=0.4, z=-0.268, r=0.062, pitch=0.0, yaw=0.12, lid=0.28, droop=0.2, depth=0.6),
]
LENS = O(y=1.705, r=0.112, z0=-0.26, z1=-0.54)
CASTERS = [[math.sin(math.pi + (i * math.pi * 2) / 3) * 0.4, math.cos(math.pi + (i * math.pi * 2) / 3) * 0.4] for i in range(3)]


def sculpt(sd, ctx=None):
    # ---------------- dolly base: rounded triangle, hub, cable guards ----------------
    with sd.group(name='base', mat='metal', bone=['base'], k=0.03):
        tri = [[math.sin(math.pi + (i * math.pi * 2) / 3) * 0.52, math.cos(math.pi + (i * math.pi * 2) / 3) * 0.52] for i in range(3)]
        with sd.group(k=0):
            sd.box(pos=[0, 0.12, 0], size=[0.6, 0.035, 0.6], round=0.02)
            prism(sd, tri, {'axis': 'y', 'op': 'int', 'k': 0.09})
        sd.cylinder(pos=[0, 0.18, 0], r=0.15, h=0.045, round=0.02)
    for x, z in CASTERS:
        a = math.atan2(x, z)
        with sd.group(mat='cream', bone=['base'], blend=0.006, k=0.01):
            # cable guard: a curved skirt in front of each caster, down to 2 cm over the floor
            sd.frame({'pos': [x * 1.12, 0.07, z * 1.12], 'rot': [0, a, 0]}, lambda: sd.box(size=[0.085, 0.05, 0.014], round=0.012))
    # ---------------- telescoping pedestal column + chrome steering ring ----------------
    with sd.group(name='column', mat='metal', bone=['column'], blend=0.01, k=0.012):
        sd.cylinder(pos=[0, 0.42, 0], r=0.1, h=0.22, round=0.015)
        sd.cylinder(pos=[0, 0.8, 0], r=0.076, h=0.17, round=0.012)
    with sd.group(name='ring', mat='chrome', bone=['column'], blend=0.006, k=0.01):
        sd.torus(pos=[0, 0.645, 0], R=0.1, r=0.016)
        sd.torus(pos=[0, 0.76, 0], R=0.3, r=0.022)
        for i in range(3):
            a = (i * math.pi * 2) / 3 + 0.5
            sd.capsule(a=[math.sin(a) * 0.075, 0.76, math.cos(a) * 0.075], b=[math.sin(a) * 0.29, 0.76, math.cos(a) * 0.29], r=0.013)
    # pan-head collar the torso is fused onto
    sd.torus(mat='chrome', bone=['column', 'torso'], pos=[0, 0.955, 0], R=0.12, r=0.03, k=0.01)

    # ---------------- chubby torso in a 70s ringer tee ----------------
    with sd.group(name='tee', mat='shirt', bone=['torso'], blend=0.03, k=0.07):
        sd.ellipsoid(pos=[0, 1.1, -0.01], r=[0.29, 0.22, 0.26])       # belly
        sd.ellipsoid(pos=[0, 1.3, 0.02], r=[0.3, 0.15, 0.21])         # chest
        sd.ellipsoid(pos=[0, 1.37, 0.03], r=[0.33, 0.07, 0.16])       # shoulder yoke
        sd.ellipsoid(pos=[0, 0.97, 0.0], r=[0.16, 0.06, 0.15])        # taper into the collar
    # ringer collar band + a clean round tear showing the belly
    sd.torus(mat='ringer', bone=['torso'], pos=[0, 1.44, 0.03], rot=[0.12, 0, 0], R=0.105, r=0.022, k=0.012)
    sd.capsule(mat='skin', bone=['torso', 'head'], a=[0, 1.42, 0.03], b=[0, 1.5, 0.02], r=0.085, k=0.02)
    sd.paint({'mat': 'skin', 'soft': 0.002, 'only': ['shirt']}, lambda: sd.ellipsoid(pos=[0.12, 1.02, -0.26], r=[0.07, 0.055, 0.08]))
    sd.stitch([[0.12 + math.sin(a) * 0.075, 1.02 + math.cos(a) * 0.06, -0.3] for a in [(i / 22) * math.pi * 2 for i in range(23)]], mats=['shirt'], color='#8E2A18', smooth=False)

    # ---------------- chubby arms gripping the pan handles ----------------
    @sd.mirrorX
    def _():
        S, E, H = [-0.3, 1.36, 0.02], [-0.38, 1.14, -0.08], [-0.32, 1.1, -0.3]
        with sd.group(mat='shirt', bone=['shoulderL'], blend=0.03, k=0.04):
            sd.ellipsoid(pos=[S[0] - 0.01, S[1] - 0.02, S[2]], r=[0.1, 0.1, 0.1])
            sd.roundCone(a=S, b=[S[0] * 0.5 + E[0] * 0.5, S[1] * 0.5 + E[1] * 0.5, S[2] * 0.5 + E[2] * 0.5], ra=0.098, rb=0.092)
        sd.torus(mat='ringer', bone=['shoulderL'], pos=[S[0] * 0.5 + E[0] * 0.5 - 0.004, S[1] * 0.5 + E[1] * 0.5, S[2] * 0.5 + E[2] * 0.5 - 0.005], rot=[-0.4, 0, -0.35], R=0.09, r=0.016, k=0.01)
        with sd.group(mat='skin', blend=0.02, k=0.04):
            sd.roundCone(bone=['shoulderL', 'elbowL'], a=[S[0] * 0.45 + E[0] * 0.55, S[1] * 0.45 + E[1] * 0.55, S[2] * 0.45 + E[2] * 0.55], b=E, ra=0.085, rb=0.084)
            sd.roundCone(bone=['elbowL'], a=E, b=H, ra=0.084, rb=0.07)
            # big fist wrapped around the handle (+ thumb over the top)
            sd.ellipsoid(bone=['handL'], pos=[H[0], H[1] + 0.005, H[2] - 0.035], r=[0.078, 0.07, 0.085])
            sd.ellipsoid(bone=['handL'], pos=[H[0] + 0.045, H[1] + 0.045, H[2] - 0.045], rot=[0.3, 0, 0.5], r=[0.03, 0.022, 0.045])
            for i in range(4):
                sd.sphere(bone=['handL'], pos=[H[0] - 0.052, H[1] + 0.03 - i * 0.03, H[2] - 0.085], r=0.024, k=0.012)
        # pan handle: rubber grip through the fist, chrome bar up to the camera's pan head
        with sd.group(bone=['handL'], blend=0.004, k=0.01):
            sd.capsule(mat='rubber', a=[H[0], H[1] - 0.09, H[2] - 0.02], b=[H[0], H[1] + 0.08, H[2] - 0.05], r=0.026)
            sd.capsule(mat='chrome', a=[H[0], H[1] + 0.08, H[2] - 0.05], b=[-0.17, 1.55, -0.14], r=0.017)

    # ---------------- THE HEAD: a big boxy studio camera ----------------
    with sd.group(name='camera', bone=['head'], blend=0.01):
        with sd.group(name='housing', mat='camera', k=0.02):
            sd.box(pos=[0, 1.79, 0.03], size=[0.22, 0.225, 0.3], round=0.06)
            for E in EYES:
                sd.frame({'pos': [0, HEAD_Y, 0]}, lambda E=E: zEyeSocket(sd, E))
        # cream band around the middle + a red accent stripe (painted)
        sd.paint({'mat': 'cream', 'soft': 0.0015, 'only': ['camera']}, lambda: sd.box(pos=[0, 1.66, 0.03], size=[0.3, 0.04, 0.4]))
        sd.paint({'mat': 'stripe', 'soft': 0.0015, 'only': ['camera']}, lambda: sd.box(pos=[0, 1.61, 0.03], size=[0.3, 0.012, 0.4]))
        # pan head under the housing
        sd.cylinder(mat='metal', pos=[0, 1.555, 0.03], r=0.13, h=0.03, round=0.012, k=0.008)
        # lens snout: barrel, chrome rings, flared hood, dark glass inside
        with sd.group(name='lens', k=0.006, blend=0.012):
            sd.cylinder(mat='rubber', pos=[0, LENS.y, (LENS.z0 + LENS.z1) / 2], rot=[math.pi / 2, 0, 0], r=LENS.r, h=(LENS.z0 - LENS.z1) / 2, round=0.012)
            sd.cone(mat='rubber', pos=[0, LENS.y, LENS.z1 - 0.035], rot=[math.pi / 2, 0, 0], h=0.045, r1=0.145, r2=LENS.r + 0.004, round=0.008)
            sd.cylinder(op='sub', k=0.004, cutMat='rubber', pos=[0, LENS.y, LENS.z1 - 0.06], rot=[math.pi / 2, 0, 0], r=0.12, h=0.06)
        for z in [-0.33, -0.43]:
            sd.torus(mat='chrome', pos=[0, LENS.y, z], rot=[math.pi / 2, 0, 0], R=LENS.r + 0.004, r=0.011, k=0.004)
        sd.ellipsoid(mat='glass', pos=[0, LENS.y, LENS.z1 - 0.004], r=[0.1, 0.1, 0.022])
        # tally lamp housing on top (the lamp itself is an attachment), viewfinder hood at the back
        sd.cylinder(mat='metal', pos=[0, 2.02, -0.02], r=0.062, h=0.022, round=0.01, k=0.01)
        with sd.group(mat='metal', k=0.012, blend=0.008):
            sd.box(pos=[0, 1.92, 0.37], size=[0.12, 0.085, 0.07], round=0.03)
            sd.box(op='sub', k=0.006, pos=[0, 1.92, 0.43], size=[0.095, 0.06, 0.04], round=0.02)
        sd.ellipsoid(mat='glass', pos=[0, 1.92, 0.405], r=[0.085, 0.052, 0.012])
        # side knobs (zoom / focus)
        sd.mirrorX(lambda: sd.cylinder(mat='chrome', pos=[-0.238, 1.72, 0.24], rot=[0, 0, math.pi / 2], r=0.032, h=0.02, round=0.008, k=0.005))
        # headset strapped over the housing: band, orange foam cups, mic boom
        with sd.group(mat='headset', k=0.012, blend=0.006):
            sd.worm(pts=[[-0.242, 1.8, 0.12], [-0.225, 1.98, 0.12], [-0.12, 2.028, 0.12], [0.12, 2.028, 0.12], [0.225, 1.98, 0.12], [0.242, 1.8, 0.12]], r=0.017, flat=0.5, up=[0, 0, 1], segs=28)
            sd.mirrorX(lambda: sd.cylinder(pos=[-0.242, 1.79, 0.12], rot=[0, 0, math.pi / 2], r=0.06, h=0.018, round=0.01))
            sd.worm(pts=[[-0.26, 1.76, 0.09], [-0.27, 1.66, -0.08], [-0.22, 1.6, -0.24], [-0.15, 1.59, -0.3]], r=0.009, segs=16)
            sd.sphere(pos=[-0.14, 1.59, -0.31], r=0.022)
        sd.mirrorX(lambda: sd.cylinder(mat='foam', pos=[-0.266, 1.79, 0.12], rot=[0, 0, math.pi / 2], r=0.056, h=0.014, round=0.012, k=0.006))
    for E in EYES:
        sd.frame({'pos': [0, HEAD_Y, 0]}, lambda E=E: sd.group({'bone': ['head']}, lambda: zEyeLid(sd, E)))


def attachments(b, ctx=None):
    from ..face import basicMaterial
    T3 = b.THREE
    staticEyes(b, EYES)
    head = b.joint('head')
    # red tally lamp (glows; the runtime blinks it)
    tallyMat = basicMaterial({'color': T3.Color('#FF2A1E').multiplyScalar(1.6), 'name': 'bigShotTally'})
    tallyMat.name = 'bigShotTally'
    tally = b.mesh(head, T3.SphereGeometry(0.058, 18, 10, 0, math.pi * 2, 0, math.pi / 2), tallyMat, O(pos=[0, 0.535, -0.02], scale=[1, 0.95, 1], name='tally', cast=False))
    tally.userData['tally'] = True
    # lens front anchor (runtime iris / flash)
    lf = T3.Object3D()
    lf.name = 'lensFront'
    lf.position.set(0, LENS.y - HEAD_Y, LENS.z1 - 0.03)
    head.add(lf)
    # casters: swivel fork + rubber wheel with a chrome hub
    base = b.joint('base')
    fork = b.mat(color='#C9CED4', metal=1, rough=0.2)
    tire = b.mat(color='#1E1C20', rough=0.7)
    hub = b.mat(color='#D3D8DE', metal=1, rough=0.18)
    forkGeo = T3.BoxGeometry(0.075, 0.07, 0.03)
    tireGeo = T3.CylinderGeometry(0.062, 0.062, 0.042, 20).rotateZ(math.pi / 2)
    hubGeo = T3.CylinderGeometry(0.03, 0.03, 0.046, 12).rotateZ(math.pi / 2)
    for i, (x, z) in enumerate(CASTERS):
        sw = T3.Group()
        sw.name = 'caster%d' % i
        sw.userData['caster'] = True
        sw.position.set(x, 0.062, z)
        sw.rotation.y = math.atan2(x, z)
        base.add(sw)
        b.mesh(sw, forkGeo, fork, O(pos=[0, 0.045, 0.02], name='casterFork', cast=False))
        w = T3.Group()
        w.name = 'wheel%d' % i
        w.userData['wheel'] = True
        sw.add(w)
        b.mesh(w, tireGeo, tire, O(name='casterTire', cast=False))
        b.mesh(w, hubGeo, hub, O(name='casterHub', cast=False))


DEF = O(
    id='z_bigshot',
    name='Big Shot',
    kind='zombie',
    rig=O(
        custom=True,
        joints=[
            O(name='base', parent=None, pos=[0, 0, 0], tail=[0, 0.2, 0], blend=0.03, gate=0.5),
            O(name='column', parent='base', pos=[0, 0.2, 0], tail=[0, 0.72, 0], blend=0.03, gate=0.2),
            O(name='torso', parent='column', pos=[0, 0.74, 0], tail=[0, 0.5, 0], blend=0.06, gate=0.35),
            O(name='head', parent='torso', pos=[0, 0.56, 0], tail=[0, 0.28, -0.3], blend=0.03, gate=0.3),
            O(name='shoulderL', parent='torso', pos=[-0.3, 0.42, 0.02], blend=0.07, gate=0.13),
            O(name='elbowL', parent='shoulderL', pos=[-0.08, -0.22, -0.1], blend=0.06, gate=0.11),
            O(name='handL', parent='elbowL', pos=[0.06, -0.04, -0.22], tail=[0, 0, -0.08], blend=0.04, gate=0.1),
            O(name='shoulderR', parent='torso', pos=[0.3, 0.42, 0.02], blend=0.07, gate=0.13),
            O(name='elbowR', parent='shoulderR', pos=[0.08, -0.22, -0.1], blend=0.06, gate=0.11),
            O(name='handR', parent='elbowR', pos=[-0.06, -0.04, -0.22], tail=[0, 0, -0.08], blend=0.04, gate=0.1),
        ],
        bindPose=O(),
        dims=O(height=2.2, headH=0.5),
    ),
    bake=O(voxel=0.0052, tris=9800, aoStrength=0.9, aoReach=0.12),
    rim=O(color='#8FF3FF', strength=0.3),
    materials=O(
        ZOMBIE_MATS,
        camera=O(color='#5C7E97', rough=0.34, spec=0.7, wrap=0.45, cav=0.6),
        lid=O(color='#557590', rough=0.36, spec=0.6, wrap=0.45, cav=0.5),
        cream=O(color='#EADFC4', rough=0.4, spec=0.6, wrap=0.5, cav=0.5),
        stripe=O(color='#E2452F', rough=0.4, spec=0.6, wrap=0.5),
        metal=O(color='#40464F', rough=0.5, metal=0.0, spec=0.6, cav=0.6),
        chrome=O(color='#D3D8DE', metal=1, rough=0.16),
        rubber=O(color='#232126', rough=0.72, spec=0.3, cav=0.5),
        glass=O(color='#0E1626', rough=0.04, spec=1.2, wrap=0.3),
        headset=O(color='#2A2A31', rough=0.45, spec=0.5),
        foam=O(color='#F07A2A', rough=0.95, fuzz=0.8, wrap=0.6),
        shirt=O(color='#E0532C', rough=0.75, fuzz=0.3, wrap=0.55, lines=True),
        ringer=O(color='#F4ECD8', rough=0.75, fuzz=0.3, wrap=0.55),
    ),
    anchors=lambda ctx=None: O(EYES=EYES),
    slots=O(head=O(joint='head', pos=[0, 0.58, -0.12]), handL=O(joint='handL', pos=[0, 0, 0]), handR=O(joint='handR', pos=[0, 0, 0])),
    sculpt=sculpt,
    attachments=attachments,
)
