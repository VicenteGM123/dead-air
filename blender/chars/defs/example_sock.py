"""EXAMPLE (kit test, not final art): a sock puppet on a custom 5-joint chain, showing the non-humanoid path —
custom rig, zombie kind (cyan rim, ZOMBIES layer), cylindrical stripe pattern, eyes, custom animator.
(Port of src/art/chars/example_sock.js; the JS createAnimator is runtime code.)
"""
from ..jsutil import O
from ._face import EYE_DEFAULTS

SEG = 0.13
EYE = O(EYE_DEFAULTS, x=0.045, y=0.07, z=-0.08, r=0.034, iris='#1E1622', irisSize=0.5, pupilSize=0.7, lid='#F4F1E8', lidOpen=0.8, lowerLid=0.1)


def sculpt(sd, ctx=None):
    fr = sd.patternFrame(pos=[0, 0.3, 0], mode='cyl', radius=0.1)
    with sd.group(mat='sock', k=0.03, pframe=fr, bone='auto'):
        sd.worm(pts=[[0, 0.03, 0.02], [0, 0.2, 0.0], [0, 0.4, 0.0], [0, 0.58, -0.04], [0, 0.66, -0.12]], r=[0.11, 0.1, 0.095, 0.09, 0.07], segs=20)
        sd.plane(op='int', k=0.01, n=[0, -1, 0], d=-0.02)
    sd.ellipsoid(op='sub', k=0.01, cutMat='mouth', pos=[0, 0.6, -0.14], r=[0.07, 0.02, 0.06], rot=[0.5, 0, 0])


def attachments(b, ctx=None):
    b.eyes(EYE)


DEF = O(
    id='example_sock',
    name='Sock (kit example)',
    kind='zombie',
    rig=O(
        custom=True,
        joints=[
            O(name='root', parent=None, pos=[0, 0.02, 0], tail=[0, SEG, 0], blend=0.05, gate=0.2),
            O(name='s1', parent='root', pos=[0, SEG, 0], blend=0.05, gate=0.2),
            O(name='s2', parent='s1', pos=[0, SEG, 0], blend=0.05, gate=0.2),
            O(name='s3', parent='s2', pos=[0, SEG, 0], blend=0.05, gate=0.2),
            O(name='head', parent='s3', pos=[0, SEG, 0], tail=[0, 0.12, -0.05], blend=0.05, gate=0.2),
        ],
        bindPose=O(),
    ),
    bake=O(voxel=0.005, tris=3500),
    materials=O(
        sock=O(color='#ffffff', rough=0.8, fuzz=0.5, pattern=O(type='stripes', colors=['#E23B3B', '#F4F1E8', '#F4E03A', '#F4F1E8', '#3A58E4', '#F4F1E8'], widths=[1, 1, 1, 1, 1, 1], vertical=False, scale=0.18)),
        mouth=O(color='#3B2340', rough=0.6),
    ),
    slots=O(head=O(joint='head', pos=[0, 0.14, 0])),
    sculpt=sculpt,
    attachments=attachments,
)
