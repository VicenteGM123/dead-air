"""Hand shapes for the heroes (char-polish): the hands are rigid baked PARTS bound to handL / handR, one per shape,
and the runtime shows one shape per hand (scripts/art/char_runtime.gd setHand, poses in scripts/core/rig.gd
POSE_HANDS). Every shape is sculpted in the hand joint frame with the hero's own proportions (H = the numbers the
open hand always had), so 'open' is exactly the old hand.

Hand frame (left hand, bind pose = arm hanging): fingers along -y, palm toward +x (the body), thumb on the -z side
(forward), knuckles on the back (-x). The right hand is the same sculpt mirrored (sd.mirrorX(only=True)).
Shapes:
  open   relaxed open hand (default; the old hand)
  thumb  fist, thumb up (thumbs-up)
  gun    index pointing, thumb up, the other three curled (finger guns, disco point)
  grip   fingers curled loosely around a handle, thumb wrapped over (props: bottle, spoon, pot, brush ...)
  fist   closed fist, thumb folded over the fingers
"""
import math

from ..jsutil import O

SHAPES = ['open', 'thumb', 'gun', 'grip', 'fist']

# Per-finger bends (rad) at the 3 joints (knuckle, middle, tip), positive = toward the palm (+x).
CURL = O(
    fist=[[1.38, 1.62, 1.0], [1.42, 1.62, 1.0], [1.46, 1.62, 1.0], [1.5, 1.6, 1.0]],
    grip=[[0.95, 1.25, 0.75], [1.0, 1.28, 0.75], [1.05, 1.3, 0.75], [1.1, 1.3, 0.75]],
)
SEG = [0.46, 0.3, 0.24]   # phalanx length fractions


def _finger(sd, H, i, bends, straight=False):
    z0, l = H.fz[i], H.fl[i]
    y0 = H.y0
    if straight or bends is None:
        sp = (i - 1.5) * 0.003
        if straight:
            sp = 0
        pts = [[0.002, y0, z0], [0.006 if straight else 0.008, y0 - l * 0.55, z0 + sp], [0.01 if straight else 0.018, y0 - l, z0 + sp * 1.5]]
        sd.worm(pts=pts, r=H.fr, k=0.004, segs=8)
        return
    # curled: the fingers of a fist are a little shorter visually (pads pressed into the palm)
    p = [0.002, y0, z0]
    pts = [list(p)]
    th = 0.0
    for j in range(3):
        th += bends[j]
        L = l * SEG[j]
        # half-step point keeps the Catmull-Rom curve tight around each joint
        p = [p[0] + math.sin(th) * L, p[1] - math.cos(th) * L, z0]
        pts.append(list(p))
    # fingertip slightly inside the palm surface (no gap)
    sd.worm(pts=pts, r=[H.fr[0] * 1.04, H.fr[0], H.fr[1], H.fr[2]], k=0.006, segs=14)


def _thumbUp(sd, H):
    """Thick cartoon thumb rising from the index side of the fist (local -z), the tip leaning back a touch."""
    t = H.thumbR
    sd.worm(pts=[[0.01, -0.034, -0.034], [0.016, -0.05, -0.05], [0.017, -0.056, -0.07], [0.014, -0.053, -0.088]],
            r=[t[0] * 1.08, t[0] * 1.08, t[0] * 1.02, t[1] * 1.1], k=0.012, segs=12)


def _thumbWrap(sd, H, tight):
    """Thumb folded over the curled index/middle fingers (fist) or wrapped round a handle (grip)."""
    t = H.thumbR
    if tight:
        pts = [[0.012, -0.03, -0.038], [0.024, -0.054, -0.052], [0.038, -0.084, -0.038], [0.044, -0.096, -0.012]]
    else:
        pts = [[0.012, -0.03, -0.038], [0.026, -0.056, -0.056], [0.045, -0.082, -0.052], [0.056, -0.094, -0.034]]
    sd.worm(pts=pts, r=[t[0] * 1.05, t[0], t[1], t[2]], k=0.012, segs=12)


def hand(sd, H, shape):
    """The hand of `shape` in the CURRENT bone frame (caller: `with sd.bone('handL'), sd.frame(scale=H.s, pos=H.pos)`)."""
    with sd.group(mat='skin', k=0.01, blend=0.012):
        sd.roundCone(a=[0, 0.012, 0], b=[0.002, -0.03, 0], ra=H.wrist[0], rb=H.wrist[1], k=0.015)
        sd.box(pos=[0.002, -0.055, 0], size=H.palm, round=H.palmRound, k=0.015)
        sd.ellipsoid(pos=[0.012, -0.045, -0.03 * H.zk], r=H.ball, k=0.012)
        for i in range(4):
            if shape == 'open':
                _finger(sd, H, i, None)
            elif shape == 'gun' and i == 0:
                _finger(sd, H, i, None, straight=True)
            else:
                _finger(sd, H, i, CURL.grip[i] if shape == 'grip' else CURL.fist[i])
            sd.sphere(pos=[-0.008, H.y0, H.fz[i]], r=H.kr * (1.08 if shape != 'open' else 1), k=0.008)
        if shape == 'open':
            sd.worm(pts=H.thumbP, r=H.thumbR, k=0.01, segs=8)
        elif shape in ('thumb', 'gun'):
            _thumbUp(sd, H)
        else:
            _thumbWrap(sd, H, shape == 'fist')
    if H.nails:
        with sd.paint(color=H.nails, soft=0.002, strength=0.9, only=['skin']):
            for i in range(4):
                if shape == 'open' or (shape == 'gun' and i == 0):
                    sp = 0 if shape == 'gun' else (i - 1.5) * 0.0045
                    sd.sphere(pos=[0.024 if shape == 'open' else 0.016, H.y0 - H.fl[i] + 0.004, H.fz[i] + sp], r=0.0085)
    if H.warm:
        sd.paint({'color': H.warm, 'soft': 0.02, 'strength': H.warmK, 'only': ['skin']}, lambda: sd.sphere(pos=[0.004, -0.07, 0], r=0.11))


def handParts(H, bone='hand', tris=1500, voxel=None):
    """Part definitions {hand<L|R>_<shape>: O(bone, tris, sculpt, ao='self')} for every shape."""
    out = O()
    for shape in SHAPES:
        for side in ('L', 'R'):
            def sculpt(sd, ctx=None, shape=shape, side=side):
                def fn(_m=None):
                    with sd.bone('handL'), sd.frame(scale=H.s, pos=H.pos):
                        hand(sd, H, shape)
                if side == 'L':
                    fn()
                else:
                    sd.mirrorX(fn, only=True)
            out['hand%s_%s' % (side, shape)] = O(bone='hand' + side, tris=tris, voxel=voxel, sculpt=sculpt, ao='self', hand=[side, shape])
    return out
