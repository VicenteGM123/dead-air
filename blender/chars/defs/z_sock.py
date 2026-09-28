"""Z_SOCK — the SOCK HOPPER, one of Hootie's "Sockettes" (GDD §8.2, STYLE_GUIDE §7). (Port of src/art/chars/z_sock.js.)
A chunky 0.72 m striped tube sock standing on its ribbed cuff, the foot bent forward into a puppet head: heel knob at
the back, a split toe = the mouth (lower jaw on its own joint for the leap-bite), a felt tongue lolling out, a yarn
tuft, and two BIG googly eyes on top whose pupils are separate meshes (userData.googlyPupil) the runtime jiggles on
springs. 70s bands (red / yellow / blue on cream), red heel + toe, a darned felt patch. Cute and goofy, never gross.

Custom skeleton (custom:true): root -> s1 -> s2 -> s3 -> head (+ jaw, child of head). The type module drives every
joint itself; the JS createAnimator (a preview idle/hop loop) is runtime code (Godot scripts/art/chars/z_sock.gd).
Attachment tags the runtime looks for: userData.googlyEye ('L'|'R', the white), userData.googlyPupil ('L'|'R').
"""
import math

from ..jsutil import O

CREAM = '#EDE0C4'
RED = '#E0392F'
YELLOW = '#F7C630'
BLUE = '#2F63D8'

# Head-local eye anchors (head joint at y = 0.53, z = 0). The eyes sit on top of the head looking forward.
EYES = O(x=0.064, y=0.158, z=-0.118, r=0.06, pitch=0.42)


def sculpt(sd, ctx=None):
    # ---------------- leg: the striped tube, bending forward into the foot ----------------
    legFr = sd.patternFrame(pos=[0, 0.1, 0], mode='cyl', radius=0.1)
    with sd.group(name='leg', mat='leg', pframe=legFr, bone=['root', 's1', 's2', 's3'], k=0.04):
        sd.worm(pts=[[0, 0.08, 0.004], [0, 0.22, 0.006], [0, 0.36, 0.004], [0, 0.46, -0.004], [0, 0.52, -0.03]], r=[0.108, 0.103, 0.096, 0.094, 0.1], segs=24)
    # ribbed cuff it stands on (slight flare, clean rolled rim)
    cuffFr = sd.patternFrame(pos=[0, 0.0, 0], mode='cyl', radius=0.112)
    with sd.group(name='cuff', mat='cuff', pframe=cuffFr, bone=['root'], blend=0.02, k=0.02):
        sd.cone(pos=[0, 0.055, 0.004], h=0.055, r1=0.118, r2=0.104, round=0.012)
        sd.torus(pos=[0, 0.012, 0.004], R=0.108, r=0.013)

    # ---------------- head: heel knob + upper head + lower jaw (the split toe is the mouth) ----------------
    with sd.group(name='head', mat='sock', blend=0.05, k=0.045):
        sd.ellipsoid(bone=['s3', 'head'], pos=[0, 0.55, 0.05], r=[0.112, 0.1, 0.09])            # heel knob
        sd.ellipsoid(bone=['head'], pos=[0, 0.598, -0.108], r=[0.146, 0.1, 0.162])              # upper head
        sd.ellipsoid(bone=['jaw'], pos=[0, 0.512, -0.118], r=[0.13, 0.056, 0.145], k=0.03)      # lower jaw
    # the mouth: a clean horizontal split across the toe, dark felt inside
    with sd.group(name='mouthCut', op='sub', blend=0.008, cutMat='mouth'):
        sd.ellipsoid(pos=[0, 0.546, -0.225], rot=[0.08, 0, 0], r=[0.122, 0.02, 0.18])
    # red toe cap + red heel (painted, soft edge)
    with sd.paint(color=RED, soft=0.004, strength=1, only=['sock']):
        sd.ellipsoid(pos=[0, 0.55, -0.272], r=[0.17, 0.15, 0.075])
        sd.ellipsoid(pos=[0, 0.55, 0.13], r=[0.11, 0.1, 0.06])
    # felt tongue lolling out over the lower lip (moves with the jaw)
    sd.worm(mat='tongue', bone=['jaw'], pts=[[0.004, 0.532, -0.16], [0.008, 0.53, -0.245], [0.014, 0.508, -0.275], [0.018, 0.472, -0.272]], r=[0.03, 0.036, 0.035, 0.028], flat=0.72, up=[0, 1, -0.2], k=0.006, segs=16)
    sd.capsule(op='sub', k=0.004, cutMat='tongue', a=[0.015, 0.52, -0.282], b=[0.018, 0.48, -0.288], r=0.004)   # centre crease

    # ---------------- yarn tuft (3 soft curls on top, a hint of twist) ----------------
    with sd.group(name='tuft', mat='yarn', bone=['head'], blend=0.014, k=0.012):
        C = [[0, 0.02, 0.0, 0.2], [0.028, 0.012, 0.5, -0.1], [-0.028, 0.012, -0.5, -0.1], [0.012, -0.018, 0.25, 0.5], [-0.014, -0.016, -0.3, 0.45], [0.0, 0.04, 0.0, -0.6]]
        for x, z, sx, sz in C:
            b0 = [x, 0.675, -0.05 + z]
            sd.worm(pts=[b0, [x + sx * 0.02, 0.72, b0[2] + sz * 0.02], [x + sx * 0.045, 0.745, b0[2] + sz * 0.045 - 0.012], [x + sx * 0.06, 0.735, b0[2] + sz * 0.06 - 0.03]],
                    r=[0.02, 0.019, 0.016, 0.011], grooves=O(n=3, depth=0.0025), segs=14)

    # ---------------- darned felt patch on the leg (sewn on, never ragged) ----------------
    sd.paint({'mat': 'patch', 'soft': 0.001, 'only': ['leg']}, lambda: sd.ellipsoid(pos=[-0.092, 0.25, -0.03], rot=[0, 0, 0.3], r=[0.06, 0.042, 0.05]))
    ring = [[-0.12, 0.25 + math.sin(a) * 0.034, -0.03 + math.cos(a) * 0.044] for a in [(i / 20) * math.pi * 2 for i in range(21)]]
    sd.stitch(ring, mats=['patch'], color='#2E6B3A', smooth=False, width=0.0022)


def attachments(b, ctx=None):
    """Googly eyes: white dome + loose black pupil (+ a cyan zombie rim). Eye whites of both sides share a geometry."""
    from ..face import basicMaterial
    T3 = b.THREE
    E = EYES
    white = b.mat(color='#EDEDEA', rough=0.2, rim=0.05, wrap=0.45, envIntensity=0.45, physical=True, clearcoat=1, clearcoatRough=0.08)
    pupil = b.mat(color='#050305', rough=0.3, rim=0.0, envIntensity=0.2)
    rimMat = basicMaterial({'color': T3.Color('#8FF3FF').multiplyScalar(1.2)})
    domeGeo = T3.SphereGeometry(E.r, 28, 12, 0, math.pi * 2, 0, math.pi / 2)
    pupilGeo = T3.SphereGeometry(E.r * 0.56, 20, 8, 0, math.pi * 2, 0, math.pi / 2)
    rimGeo = T3.TorusGeometry(E.r * 1.01, E.r * 0.075, 6, 32)
    for s in (1, -1):
        side = 'L' if s > 0 else 'R'
        root = T3.Group()
        root.name = 'googly' + side
        root.position.set(-s * E.x, E.y, E.z)
        root.rotation.set(E.pitch, -s * 0.16, 0)
        b.joint('head').add(root)
        dome = b.mesh(root, domeGeo, white, O(rot=[-math.pi / 2, 0, 0], scale=[1, 0.62, 1], name='googlyEye', cast=False))
        dome.userData['googlyEye'] = side
        # pupil pivot: the runtime offsets this group in the eye plane (x/y) on springs
        pv = T3.Group()
        pv.name = 'googlyPupilPivot' + side
        pv.position.set(0, -E.r * 0.12, -E.r * 0.5)
        root.add(pv)
        pu = b.mesh(pv, pupilGeo, pupil, O(rot=[-math.pi / 2, 0, 0], scale=[1, 0.35, 1], name='googlyPupil', cast=False))
        pu.userData['googlyPupil'] = side
        pv.userData['googlyPupil'] = side
        rim = b.mesh(root, rimGeo, rimMat, O(name='googlyRim', cast=False))
        rim.userData['googlyRim'] = side


DEF = O(
    id='z_sock',
    name='Sock Hopper',
    kind='zombie',
    rig=O(
        custom=True,
        joints=[
            O(name='root', parent=None, pos=[0, 0, 0], tail=[0, 0.13, 0], blend=0.06, gate=0.22),
            O(name='s1', parent='root', pos=[0, 0.13, 0], blend=0.07, gate=0.22),
            O(name='s2', parent='s1', pos=[0, 0.13, 0], blend=0.07, gate=0.22),
            O(name='s3', parent='s2', pos=[0, 0.13, 0], blend=0.07, gate=0.22),
            O(name='head', parent='s3', pos=[0, 0.14, 0], tail=[0, 0.03, -0.2], blend=0.07, gate=0.22),
            O(name='jaw', parent='head', pos=[0, -0.012, -0.02], tail=[0, -0.02, -0.18], blend=0.035, gate=0.16),
        ],
        bindPose=O(),
        dims=O(height=0.72, headH=0.2),
    ),
    bake=O(voxel=0.0036, tris=5200, aoStrength=0.8, aoReach=0.08),
    rim=O(color='#8FF3FF', strength=0.3),
    materials=O(
        leg=O(color='#ffffff', rough=0.85, fuzz=0.55, wrap=0.6, cav=0.4,
              pattern=O(type='stripes', colors=[CREAM, RED, CREAM, YELLOW, CREAM, BLUE, CREAM], widths=[3, 2, 1, 2, 1, 2, 3], scale=0.44, soft=0.02, vertical=False)),
        sock=O(color=CREAM, rough=0.85, fuzz=0.55, wrap=0.6, cav=0.4),
        cuff=O(color='#ffffff', rough=0.85, fuzz=0.5, wrap=0.6, cav=0.5, bump=0.25,
               pattern=O(type='knit', color=CREAM, ribs=10, scale=0.12)),
        mouth=O(color='#2A1430', rough=0.9, spec=0.1, cav=1),
        tongue=O(color='#E75A74', rough=0.9, fuzz=0.8, sss=0.3, wrap=0.6),
        yarn=O(color='#F08A24', rough=0.9, fuzz=0.9, wrap=0.6, cav=0.6),
        patch=O(color='#5FB36A', rough=0.95, fuzz=0.8, wrap=0.6, lines=True),
    ),
    slots=O(head=O(joint='head', pos=[0, 0.17, -0.06])),
    anchors=lambda ctx=None: O(EYES=EYES),
    sculpt=sculpt,
    attachments=attachments,
)
