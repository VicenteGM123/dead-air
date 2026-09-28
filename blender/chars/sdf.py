"""SDF sculpting DSL ("digital clay") — Python port of src/art/sdf.js (see docs/CHARKIT.md).

Same API and names as the JS, evaluated VECTORISED with numpy (arrays of points):

    sd = createSculptor(joints=..., materials=..., expr=None)   # joints: name -> O(matrix=4x4 bind world, pos=[x,y,z])
    sd.ellipsoid(pos=..., r=[rx, ry, rz], rot=..., mat=..., bone=..., k=..., op=..., color=..., noise=..., pframe=...)
    sd.sphere / box / capsule / roundCone / torus / arc / cylinder / cone / worm / plane / custom
    with sd.group(k=..., op=..., mat=..., bone=..., pframe=..., name=...) as g:  ...children...
    @sd.mirrorX                        run the body twice, the second time mirrored across x=0 with L<->R bones
    def _(m): ...                      (m = False, then True)
    with sd.bone('elbowL'): ...        coordinates relative to that joint's bind-pose frame, default binding = its chain
    with sd.frame(pos=..., rot=..., scale=...): ...
    with sd.paint(mat=..., color=..., soft=..., strength=..., only=[...]): ...shapes...   recolor the surface inside
    sd.stitch(points, width=..., dash=..., color=..., mats=[...])
    sd.patternFrame(pos=..., axis=..., mode='cyl'|'tri', radius=...)

Every JS call form also works: options as a dict (`sd.group({'k': 0.03}, lambda: body())`), bodies as functions.
Ops: op 'add' (smooth union, k = blend radius in m), 'sub' (smooth subtract), 'int' (smooth intersect), 'paint'.
Any node takes offset (inflate, m) and shell (onion thickness, m). Units are meters; feet at y=0, facing -z, BIND pose.

Evaluation: node.fn(x, y, z) (scalars or arrays) -> distance; Evaluator(root, boxes, margin) evaluates a tree on many
points with per-block pruning identical to the JS pruneTree(); makeSampler(materials) -> attribute sampler.
"""
import math
import inspect
import numpy as np

from . import m4
from .jsutil import O, nz, jor, opts as _opts

BIG = 1e3

# ---------------------------------------------------------------------------------------------------------------
# Noise (improved Perlin, deterministic) — identical permutation to the JS (LCG seed 1337).
_p = list(range(256))
_s = 1337
for _i in range(255, 0, -1):
    _s = (_s * 1103515245 + 12345) & 0x7fffffff
    _j = _s % (_i + 1)
    _p[_i], _p[_j] = _p[_j], _p[_i]
PERM = np.array([_p[i & 255] for i in range(512)], dtype=np.int64)


def _fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def _grad(h, x, y, z):
    h = h & 15
    u = np.where(h < 8, x, y)
    v = np.where(h < 4, y, np.where((h == 12) | (h == 14), x, z))
    return np.where((h & 1) == 0, u, -u) + np.where((h & 2) == 0, v, -v)


def noise3(x, y, z):
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    z = np.asarray(z, float)
    X = np.floor(x)
    Y = np.floor(y)
    Z = np.floor(z)
    x = x - X
    y = y - Y
    z = z - Z
    xi = X.astype(np.int64) & 255
    yi = Y.astype(np.int64) & 255
    zi = Z.astype(np.int64) & 255
    u, v, w = _fade(x), _fade(y), _fade(z)
    A = PERM[xi] + yi
    AA = PERM[A] + zi
    AB = PERM[A + 1] + zi
    B = PERM[xi + 1] + yi
    BA = PERM[B] + zi
    BB = PERM[B + 1] + zi

    def l(a, b, t):
        return a + (b - a) * t
    return l(
        l(l(_grad(PERM[AA], x, y, z), _grad(PERM[BA], x - 1, y, z), u), l(_grad(PERM[AB], x, y - 1, z), _grad(PERM[BB], x - 1, y - 1, z), u), v),
        l(l(_grad(PERM[AA + 1], x, y, z - 1), _grad(PERM[BA + 1], x - 1, y, z - 1), u), l(_grad(PERM[AB + 1], x, y - 1, z - 1), _grad(PERM[BB + 1], x - 1, y - 1, z - 1), u), v),
        w)


def fbm3(x, y, z, oct=3):
    a = 0.0
    amp = 0.5
    f = 1.0
    for _ in range(oct):
        a = a + amp * noise3(x * f, y * f, z * f)
        f *= 2.03
        amp *= 0.5
    return a


# ---------------------------------------------------------------------------------------------------------------
# Smooth operators (quadratic polynomial smin; k in meters)
def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def ssub(a, b, k):
    return -smin(-a, b, k)


def sint(a, b, k):
    return -smin(-a, -b, k)


def clamp01(x):
    return np.clip(x, 0.0, 1.0)


def smoothstep(a, b, x):
    t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------------------------------------------
# Primitive distance functions in local space (vectorised).
def sdEllipsoid(x, y, z, rx, ry, rz):
    k0 = np.sqrt((x / rx) ** 2 + (y / ry) ** 2 + (z / rz) ** 2)
    k1 = np.sqrt((x / (rx * rx)) ** 2 + (y / (ry * ry)) ** 2 + (z / (rz * rz)) ** 2)
    with np.errstate(divide='ignore', invalid='ignore'):
        d = (k0 * (k0 - 1)) / k1
    return np.where(k0 < 1e-9, -min(rx, ry, rz), d)


def sdBox(x, y, z, bx, by, bz, r):
    qx = np.abs(x) - bx + r
    qy = np.abs(y) - by + r
    qz = np.abs(z) - bz + r
    ox = np.maximum(qx, 0)
    oy = np.maximum(qy, 0)
    oz = np.maximum(qz, 0)
    return np.sqrt(ox * ox + oy * oy + oz * oz) + np.minimum(np.maximum(np.maximum(qx, qy), qz), 0) - r


def sdCapsule(x, y, z, ax, ay, az, bx, by, bz, r):
    pax, pay, paz = x - ax, y - ay, z - az
    bax, bay, baz = bx - ax, by - ay, bz - az
    den = (bax * bax + bay * bay + baz * baz) or 1e-12
    h = clamp01((pax * bax + pay * bay + paz * baz) / den)
    dx, dy, dz = pax - bax * h, pay - bay * h, paz - baz * h
    return np.sqrt(dx * dx + dy * dy + dz * dz) - r


def _rc_degenerate(ax, ay, az, bx, by, bz, r1, r2):
    bax, bay, baz = bx - ax, by - ay, bz - az
    l2 = bax * bax + bay * bay + baz * baz
    rr = r1 - r2
    return l2 < 1e-12 or rr * rr >= l2


def sdRoundCone(x, y, z, ax, ay, az, bx, by, bz, r1, r2):
    """IQ round cone between arbitrary points (requires |r1-r2| < |b-a|)."""
    bax, bay, baz = bx - ax, by - ay, bz - az
    l2 = bax * bax + bay * bay + baz * baz
    rr = r1 - r2
    if l2 < 1e-12 or rr * rr >= l2:
        d1 = np.sqrt((x - ax) ** 2 + (y - ay) ** 2 + (z - az) ** 2) - r1
        d2 = np.sqrt((x - bx) ** 2 + (y - by) ** 2 + (z - bz) ** 2) - r2
        return np.minimum(d1, d2)
    a2 = l2 - rr * rr
    il2 = 1 / l2
    pax, pay, paz = x - ax, y - ay, z - az
    yy = pax * bax + pay * bay + paz * baz
    zz = yy - l2
    qx, qy, qz = pax * l2 - bax * yy, pay * l2 - bay * yy, paz * l2 - baz * yy
    x2 = qx * qx + qy * qy + qz * qz
    y2 = yy * yy * l2
    z2 = zz * zz * l2
    k = math.copysign(1, rr) * rr * rr * x2 if rr != 0 else 0 * x2
    c1 = np.sign(zz) * a2 * z2 > k
    c2 = np.sign(yy) * a2 * y2 < k
    r_1 = np.sqrt(x2 + z2) * il2 - r2
    r_2 = np.sqrt(x2 + y2) * il2 - r1
    r_3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + yy * rr) * il2 - r1
    return np.where(c1, r_1, np.where(c2, r_2, r_3))


def sdRoundConeV(x, y, z, A, Bp, R1, R2):
    """Round cone vectorised over segments: x,y,z (N,1); A,Bp (S,3); R1,R2 (S,) -> (N,S)."""
    ba = Bp - A
    l2 = (ba * ba).sum(1)
    rr = R1 - R2
    deg = (l2 < 1e-12) | (rr * rr >= l2)
    ax, ay, az = A[:, 0], A[:, 1], A[:, 2]
    bax, bay, baz = ba[:, 0], ba[:, 1], ba[:, 2]
    a2 = l2 - rr * rr
    with np.errstate(divide='ignore', invalid='ignore'):
        il2 = np.where(l2 > 0, 1 / np.where(l2 > 0, l2, 1), 0)
    pax, pay, paz = x - ax, y - ay, z - az
    yy = pax * bax + pay * bay + paz * baz
    zz = yy - l2
    qx, qy, qz = pax * l2 - bax * yy, pay * l2 - bay * yy, paz * l2 - baz * yy
    x2 = qx * qx + qy * qy + qz * qz
    y2 = yy * yy * l2
    z2 = zz * zz * l2
    k = np.sign(rr) * rr * rr * x2
    c1 = np.sign(zz) * a2 * z2 > k
    c2 = np.sign(yy) * a2 * y2 < k
    r_1 = np.sqrt(x2 + z2) * il2 - R2
    r_2 = np.sqrt(x2 + y2) * il2 - R1
    r_3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + yy * rr) * il2 - R1
    d = np.where(c1, r_1, np.where(c2, r_2, r_3))
    if deg.any():
        d1 = np.sqrt(pax ** 2 + pay ** 2 + paz ** 2) - R1
        d2 = np.sqrt((x - Bp[:, 0]) ** 2 + (y - Bp[:, 1]) ** 2 + (z - Bp[:, 2]) ** 2) - R2
        d = np.where(deg, np.minimum(d1, d2), d)
    return d


def sdTorus(x, y, z, R, r):
    qx = np.sqrt(x * x + z * z) - R
    return np.sqrt(qx * qx + y * y) - r


def sdArc(x, y, z, sa, ca, R, r):
    """Arc of a torus in the XZ plane, centered on +z, half-angle `ha`."""
    px = np.abs(x)
    k = np.where(ca * px > sa * z, px * sa + z * ca, np.sqrt(px * px + z * z))
    return np.sqrt(np.maximum(px * px + y * y + z * z + R * R - 2 * R * k, 0)) - r


def sdCylinder(x, y, z, r, h, rr):
    dx = np.sqrt(x * x + z * z) - r + rr
    dy = np.abs(y) - h + rr
    ox = np.maximum(dx, 0)
    oy = np.maximum(dy, 0)
    return np.minimum(np.maximum(dx, dy), 0) + np.sqrt(ox * ox + oy * oy) - rr


def sdCappedCone(x, y, z, h, r1, r2):
    qx = np.sqrt(x * x + z * z)
    qy = y
    k1x, k1y, k2x, k2y = r2, h, r2 - r1, 2 * h
    cax = qx - np.minimum(qx, np.where(qy < 0, r1, r2))
    cay = np.abs(qy) - h
    t = clamp01(((k1x - qx) * k2x + (k1y - qy) * k2y) / (k2x * k2x + k2y * k2y))
    cbx = qx - k1x + k2x * t
    cby = qy - k1y + k2y * t
    s = np.where((cbx < 0) & (cay < 0), -1.0, 1.0)
    return s * np.sqrt(np.minimum(cax * cax + cay * cay, cbx * cbx + cby * cby))


# ---------------------------------------------------------------------------------------------------------------
# Catmull-Rom helpers for worms
def catmull(pts, t):
    n = len(pts) - 1
    f = min(n - 1e-9, max(0, t * n))
    i = int(math.floor(f))
    u = f - i
    p0, p1, p2, p3 = pts[max(0, i - 1)], pts[i], pts[i + 1], pts[min(n, i + 2)]
    out = [0.0, 0.0, 0.0]
    for c in range(3):
        a, b = p1[c], p2[c]
        m1 = (p2[c] - p0[c]) * 0.5
        m2 = (p3[c] - p1[c]) * 0.5
        u2 = u * u
        u3 = u2 * u
        out[c] = (2 * u3 - 3 * u2 + 1) * a + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * b + (u3 - u2) * m2
    return out


def interpProfile(r, t):
    if isinstance(r, (int, float)):
        return r
    if callable(r):
        return r(t)
    n = len(r) - 1
    if n <= 0:
        return r[0]
    f = min(n, max(0, t * n))
    i = min(n - 1, int(math.floor(f)))
    u = f - i
    s = u * u * (3 - 2 * u)
    return r[i] + (r[i + 1] - r[i]) * s


# ---------------------------------------------------------------------------------------------------------------
MIRROR = m4.scale_m(-1, 1, 1)


def toMatrix(o=None):
    o = o or {}
    pos = o.get('pos') or [0, 0, 0]
    if o.get('quat'):
        q = tuple(o['quat'])
    elif o.get('rot'):
        r = o['rot']
        q = m4.quat_from_euler(r[0] or 0, r[1] or 0, r[2] or 0, o.get('order') or 'XYZ')
    else:
        q = (0, 0, 0, 1)
    s = o.get('scale') or 1
    sc = (s[0], s[1], s[2]) if isinstance(s, (list, tuple)) else (s, s, s)
    return m4.compose((pos[0], pos[1], pos[2]), q, sc)


def SWAP_LR(name):
    if not isinstance(name, str):
        return name
    s = name
    if s.endswith('L'):
        s = s[:-1] + '\u0001'
    if s.endswith('R'):
        s = s[:-1] + 'L'
    return s.replace('\u0001', 'R', 1)


# Default humanoid chains used for bone binding (see CHARKIT.md "Skinning").
CHAINS = {
    'torso': ['hips', 'spine', 'chest', 'neck'],
    'head': ['head'],
    'armL': ['shoulderL', 'elbowL', 'handL'],
    'armR': ['shoulderR', 'elbowR', 'handR'],
    'legL': ['hipL', 'kneeL', 'footL'],
    'legR': ['hipR', 'kneeR', 'footR'],
}

_uid = [0]
LEAVES = {}   # uid -> leaf (every leaf ever created; samplers report leaves by uid)


def _next_uid():
    u = _uid[0]
    _uid[0] += 1
    return u


def v3(a, d=(0, 0, 0)):
    return [a[0] or 0, a[1] or 0, a[2] or 0] if a else list(d)


# ---------------------------------------------------------------------------------------------------------------
class Node:
    kind = 'node'

    def fn(self, x, y, z):
        """Distance of this node (full tree, no pruning). Scalars in -> float out; arrays in -> array out."""
        scalar = np.isscalar(x)
        X = np.atleast_1d(np.asarray(x, float))
        Y = np.atleast_1d(np.asarray(y, float))
        Z = np.atleast_1d(np.asarray(z, float))
        X, Y, Z = np.broadcast_arrays(X, Y, Z)
        d = eval_dist(self, X.ravel(), Y.ravel(), Z.ravel())
        return float(d[0]) if scalar else d.reshape(X.shape)


class Leaf(Node):
    kind = 'leaf'

    def __init__(self, type_, W, lbox, params):
        self.type = type_
        self.W = W
        self.lbox = lbox
        self.groovePad = 0
        for k, v in params.items():
            setattr(self, k, v)
        self.op = 'add'
        self.k = 0
        self.cutMat = None
        self.paint = None
        self.box = None


class Group(Node):
    kind = 'group'

    def __init__(self, name='group', offset=0, shell=0):
        self.id = _next_uid()
        self.children = []
        self.name = name
        self.offset = offset
        self.shell = shell
        self.op = 'add'
        self.k = 0
        self.gk = 0
        self.cutMat = None
        self.paint = None
        self.box = None
        self._scope = None
        self._sd = None
        self._prev = None

    # context-manager form: `with sd.group(...) as g:` runs the body inside the group's scope
    def __enter__(self):
        self._prev = self._sd._push(self._scope)
        return self

    def __exit__(self, *a):
        self._sd._pop(self._prev)
        return False


class _Ctx:
    """Context manager used by sd.bone / sd.frame (no node)."""

    def __init__(self, sd, patch):
        self.sd = sd
        self.patch = patch
        self.prev = None

    def __enter__(self):
        self.prev = self.sd._push(self.patch)
        return self

    def __exit__(self, *a):
        self.sd._pop(self.prev)
        return False


def _call(fn, *args):
    """Call a body function with as many positional args as it accepts (JS ignores extra args)."""
    try:
        sig = inspect.signature(fn)
        n = sum(1 for p in sig.parameters.values() if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD))
        if any(p.kind == p.VAR_POSITIONAL for p in sig.parameters.values()):
            n = len(args)
    except (TypeError, ValueError):
        n = len(args)
    return fn(*args[:n])


class Sculptor:
    def __init__(self, opts=None, **kw):
        o = _opts(opts, kw)
        self.joints = o.joints or {}
        mats = o.materials
        self.materials = list(mats.keys()) if mats else []
        self.expr = o.expr
        self._chainOf = o.chainOf
        self.root = Group('root')
        self.root.op = 'add'
        self.stitches = []
        self.frames = [O(id=0, mode='tri', matrix=np.eye(4), inv=np.eye(4), radius=0.15, mirrored=False)]
        self.scope = O(matrix=np.eye(4), mirrored=False, bone='auto', mat=None, pframe=0, group=self.root, k=0,
                       color=None, rigid=None, flow=None)
        self.leaves = []

    # ---- scope stack
    def _push(self, patch):
        prev = self.scope
        s = O(prev)
        s.update(patch)
        self.scope = s
        return prev

    def _pop(self, prev):
        self.scope = prev

    def _run(self, patch, fn, *args):
        prev = self._push(patch)
        try:
            _call(fn, *args)
        finally:
            self._pop(prev)

    def matIndex(self, name):
        if name is None:
            return -1
        if isinstance(name, (int, np.integer)) and not isinstance(name, bool):
            return int(name)
        if name not in self.materials:
            raise ValueError("sdf: unknown material '%s'" % name)
        return self.materials.index(name)

    def chainOf(self, joint):
        if self._chainOf:
            return self._chainOf(joint)
        for c, lst in CHAINS.items():
            if joint in lst:
                return c
        return joint

    def place(self, o):
        return self.scope.matrix @ toMatrix(o)

    def resolveBone(self, b):
        if b is None:
            return self.scope.bone
        if isinstance(b, (list, tuple)):
            return [SWAP_LR(x) if self.scope.mirrored else x for x in b]
        return SWAP_LR(b) if self.scope.mirrored else b

    def _finalizeLeaf(self, leaf, o):
        sc = self.scope
        leaf.id = _next_uid()
        leaf.uid = leaf.id
        LEAVES[leaf.uid] = leaf
        leaf.kind = 'leaf'
        leaf.name = jor(o.get('name'), leaf.type)
        leaf.mat = self.matIndex(nz(o.get('mat'), sc.mat))
        leaf.bone = self.resolveBone(o.get('bone'))
        leaf.color = nz(nz(o.get('color'), sc.color), None)
        leaf.color2 = nz(o.get('color2'), None)
        leaf.pframe = nz(o.get('pframe'), sc.pframe)
        leaf.rigid = bool(nz(o.get('rigid'), sc.rigid))
        leaf.offset = jor(o.get('offset'), 0)
        leaf.shell = jor(o.get('shell'), 0)
        leaf.noise = jor(o.get('noise'), None)
        leaf.flowTag = o.get('flow') is not False
        fl = nz(o.get('flow'), sc.flow)
        if callable(fl):
            leaf.flowFn = fl
        elif isinstance(fl, (list, tuple)):
            d = list(fl)
            leaf.flowFn = lambda x, y, z, d=d: d
        else:
            leaf.flowFn = None
        W = leaf.W
        det = float(np.linalg.det(W))
        leaf.s = (abs(det) ** (1.0 / 3.0)) or 1.0
        inv = np.linalg.inv(W)
        leaf.m = inv[:3, :].copy()          # row-major 3x4 world->local
        leaf.Wm = W[:3, :].copy()
        lb = leaf.lbox
        pad = ((abs(leaf.noise.get('amp') or 0) * 1.5) if leaf.noise else 0) + max(leaf.offset, 0) + leaf.shell + (leaf.groovePad or 0)
        corners = np.array([[lb[3] if i & 1 else lb[0], lb[4] if i & 2 else lb[1], lb[5] if i & 4 else lb[2]] for i in range(8)], float)
        wc = m4.apply_pts(W, corners)
        mn = wc.min(0)
        mx = wc.max(0)
        leaf.box = [mn[0] - pad, mn[1] - pad, mn[2] - pad, mx[0] + pad, mx[1] + pad, mx[2] + pad]
        _prepare_leaf(leaf)
        self.leaves.append(leaf)
        return leaf

    def _addNode(self, node, o):
        node.op = jor(o.get('op'), 'add')
        node.k = nz(o.get('k'), self.scope.k)
        if node.op == 'paint':
            only = o.get('only')
            node.paint = O(
                mat=self.matIndex(o['paintMat']) if o.get('paintMat') is not None else -1,
                color=jor(o.get('paintColor'), None),
                soft=nz(o.get('soft'), 0.004),
                strength=nz(o.get('strength'), 1),
                pframe=nz(o.get('paintFrame'), None),
                only=[self.matIndex(x) for x in only] if only else None,
            )
        if o.get('cutMat') is not None:
            node.cutMat = self.matIndex(o['cutMat'])
        self.scope.group.children.append(node)
        return node

    def _leaf(self, type_, o, lbox, params):
        W = self.place(o)
        lf = Leaf(type_, W, lbox, params)
        self._finalizeLeaf(lf, o)
        return self._addNode(lf, o)

    # ---------------------------------------------------------------------------------------------------- shapes
    def sphere(self, o=None, **kw):
        o = _opts(o, kw)
        r = o.r
        return self._leaf('sphere', o, [-r, -r, -r, r, r, r], {'r': r})

    def ellipsoid(self, o=None, **kw):
        o = _opts(o, kw)
        rx, ry, rz = o.r
        return self._leaf('ellipsoid', o, [-rx, -ry, -rz, rx, ry, rz], {'rx': rx, 'ry': ry, 'rz': rz})

    def box(self, o=None, **kw):
        o = _opts(o, kw)
        bx, by, bz = o.size
        return self._leaf('box', o, [-bx, -by, -bz, bx, by, bz], {'bx': bx, 'by': by, 'bz': bz, 'rr': min(nz(o.get('round'), 0.01), bx, by, bz)})

    def capsule(self, o=None, **kw):
        o = _opts(o, kw)
        a, b, r = v3(o.a), v3(o.b), o.r
        return self._leaf('capsule', o, [min(a[0], b[0]) - r, min(a[1], b[1]) - r, min(a[2], b[2]) - r,
                                         max(a[0], b[0]) + r, max(a[1], b[1]) + r, max(a[2], b[2]) + r], {'a': a, 'b': b, 'r': r})

    def roundCone(self, o=None, **kw):
        o = _opts(o, kw)
        a, b = v3(o.a), v3(o.b)
        ra = nz(o.ra, o.r)
        rb = nz(o.rb, o.r)
        r = max(ra, rb)
        return self._leaf('roundCone', o, [min(a[0], b[0]) - r, min(a[1], b[1]) - r, min(a[2], b[2]) - r,
                                           max(a[0], b[0]) + r, max(a[1], b[1]) + r, max(a[2], b[2]) + r], {'a': a, 'b': b, 'ra': ra, 'rb': rb})

    def torus(self, o=None, **kw):
        o = _opts(o, kw)
        R, r = o.R, o.r
        return self._leaf('torus', o, [-R - r, -r, -R - r, R + r, r, R + r], {'R': R, 'rt': r})

    def arc(self, o=None, **kw):
        """Partial torus: arc centered on local +z, `angle` = total arc angle (radians)."""
        o = _opts(o, kw)
        R, r = o.R, o.r
        ha = nz(o.angle, math.pi) / 2
        return self._leaf('arc', o, [-R - r, -r, -R - r, R + r, r, R + r], {'R': R, 'rt': r, 'sa': math.sin(ha), 'ca': math.cos(ha)})

    def cylinder(self, o=None, **kw):
        o = _opts(o, kw)
        r, h = o.r, o.h
        return self._leaf('cylinder', o, [-r, -h, -r, r, h, r], {'r': r, 'h': h, 'rr': min(nz(o.get('round'), 0.005), r, h)})

    def cone(self, o=None, **kw):
        o = _opts(o, kw)
        h, r1, r2 = o.h, o.r1, o.r2
        rr = nz(o.get('round'), 0.005)
        r = max(r1, r2)
        return self._leaf('cone', o, [-r, -h, -r, r, h, r], {'h': h - rr, 'r1': max(r1 - rr, 1e-4), 'r2': max(r2 - rr, 1e-4), 'rr': rr})

    def plane(self, o=None, **kw):
        o = _opts(o, kw)
        n = np.array(v3(o.n, [0, 1, 0]), float)
        n = n / (np.linalg.norm(n) or 1)
        B = 50
        return self._leaf('plane', o, [-B, -B, -B, B, B, B], {'nx': float(n[0]), 'ny': float(n[1]), 'nz': float(n[2]), 'd': o.d or 0})

    def worm(self, o=None, **kw):
        """Tube along a Catmull-Rom curve through `pts`, radius profile `r` (number | list per t | fn(t)).
        flat: cross-section squash (0..1) along the `up` hint; grooves: {n, depth} strand ridges; twist (rad)."""
        o = _opts(o, kw)
        pts = [v3(p) for p in o.pts]
        segs = o.segs or max(6, (len(pts) - 1) * 5)
        P, R, T = [], [], []
        for i in range(segs + 1):
            t = i / segs
            P.append(catmull(pts, t))
            R.append(max(1e-4, interpProfile(o.r, t)))
            T.append(t)
        # Parallel-transport frames.
        up = np.array(v3(o.up, [0, 0, -1]), float)
        up = up / (np.linalg.norm(up) or 1)
        tan, nor, bin_ = [], [], []
        for i in range(segs):
            t = np.array([P[i + 1][0] - P[i][0], P[i + 1][1] - P[i][1], P[i + 1][2] - P[i][2]], float)
            ln = np.linalg.norm(t)
            tan.append(t / ln if ln > 0 else t)
        n0 = up - tan[0] * float(up @ tan[0])
        if float(n0 @ n0) < 1e-8:
            n0 = np.cross(np.array([1.0, 0, 0]), tan[0])
        n0 = n0 / (np.linalg.norm(n0) or 1)
        ups = o.ups
        for i in range(segs):
            if i > 0:
                q = m4.quat_from_unit_vectors(tan[i - 1], tan[i])
                n0 = np.array(m4.quat_rotate(q, n0))
                n0 = n0 - tan[i] * float(n0 @ tan[i])
                n0 = n0 / (np.linalg.norm(n0) or 1)
            if ups:
                # explicit per-control-point face normals (e.g. surface normals from sd.normalAt), interpolated along t
                tt = (i + 0.5) / segs * (len(ups) - 1)
                i0 = min(len(ups) - 2, int(math.floor(tt)))
                u = tt - i0
                A, Bv = ups[i0], ups[i0 + 1]
                uv = np.array([A[0] + (Bv[0] - A[0]) * u, A[1] + (Bv[1] - A[1]) * u, A[2] + (Bv[2] - A[2]) * u], float)
                uv = uv - tan[i] * float(uv @ tan[i])
                if float(uv @ uv) > 1e-8:
                    n0 = uv / np.linalg.norm(uv)
            if o.twist:
                q = m4.quat_from_axis_angle(tan[i], o.twist / segs)
                n0 = np.array(m4.quat_rotate(q, n0))
            nor.append(n0.copy())
            bb = np.cross(tan[i], n0)
            bin_.append(bb / (np.linalg.norm(bb) or 1))
        Pa = np.array(P, float)
        Ra = np.array(R, float)
        mn = (Pa - Ra[:, None]).min(0)
        mx = (Pa + Ra[:, None]).max(0)
        seg = np.zeros((segs, 14))
        for i in range(segs):
            seg[i] = [*P[i], *P[i + 1], R[i], R[i + 1], *nor[i], *bin_[i]]
        grooves = o.grooves or None
        oo = O(o)
        oo['_gp'] = 0
        lf = self._leaf('worm', oo, [mn[0], mn[1], mn[2], mx[0], mx[1], mx[2]], {
            'seg': seg, 'segs': segs, 'flat': nz(o.flat, 1), 'grooves': grooves, 'tvals': T,
            'groovePad': abs(grooves.get('depth') or 0) if grooves else 0, 'tips': nz(o.tips, 1),
        })
        return lf

    def custom(self, o=None, **kw):
        o = _opts(o, kw)
        return self._leaf('custom', o, o.box or [-1, -1, -1, 1, 1, 1], {'cfn': o.fn})

    # ---------------------------------------------------------------------------------------------------- structure
    def group(self, o=None, fn=None, **kw):
        """k = smooth blend between the group's own children; blend = how the whole group joins its previous siblings.
        Returns the group node; with fn it runs fn inside, without fn use it as a context manager."""
        if callable(o) and fn is None:
            fn, o = o, None
        o = _opts(o, kw)
        g = Group(jor(o.get('name'), 'group'), jor(o.get('offset'), 0), jor(o.get('shell'), 0))
        ao = O(o)
        ao['k'] = nz(o.get('blend'), 0)
        self._addNode(g, ao)
        g.gk = nz(o.get('k'), 0)
        sc = self.scope
        g._scope = dict(group=g, k=g.gk, mat=o['mat'] if 'mat' in o else sc.mat,
                        bone=self.resolveBone(o['bone']) if 'bone' in o else sc.bone,
                        pframe=nz(o.get('pframe'), sc.pframe), color=o['color'] if 'color' in o else sc.color,
                        rigid=nz(o.get('rigid'), sc.rigid), flow=nz(o.get('flow'), sc.flow))
        g._sd = self
        if fn is not None:
            self._run(g._scope, fn)
        return g

    def guide(self, o=None, fn=None, **kw):
        """Guide: a DETACHED group (not part of the baked tree) used only as a snap / normalAt target."""
        if callable(o) and fn is None:
            fn, o = o, None
        o = _opts(o, kw)
        g = Group(jor(o.get('name'), 'guide'), jor(o.get('offset'), 0), jor(o.get('shell'), 0))
        g.op = 'add'
        g.k = 0
        g.gk = nz(o.get('k'), 0)
        sc = self.scope
        g._scope = dict(group=g, k=g.gk, mat=o['mat'] if 'mat' in o else sc.mat, bone=sc.bone, pframe=sc.pframe,
                        color=sc.color, rigid=sc.rigid, flow=sc.flow)
        g._sd = self
        if fn is not None:
            self._run(g._scope, fn)
        return g

    def paint(self, o=None, fn=None, **kw):
        """Paint: shapes created inside recolor the surface where they overlap (they add no volume)."""
        if callable(o):
            o, fn = fn, o
        o = _opts(o, kw)
        g = Group(jor(o.get('name'), 'paint'), 0, 0)
        self._addNode(g, O(op='paint', paintMat=o.get('mat'), paintColor=o.get('color'), soft=o.get('soft'),
                           strength=o.get('strength'), paintFrame=o.get('pframe'), only=o.get('only'), k=0))
        g.gk = nz(o.get('k'), 0)
        g._scope = dict(group=g, k=nz(o.get('k'), 0))
        g._sd = self
        if fn is not None:
            self._run(g._scope, fn)
        return g

    def mirrorX(self, fn=None, o=None, **kw):
        """Run fn(False), then fn(True) mirrored across x=0 (L<->R bones). Usable as a decorator."""
        oo = _opts(o, kw)
        if fn is None:
            return lambda f: self.mirrorX(f, oo)
        if not oo.get('only'):
            _call(fn, False)
        self._run(dict(matrix=MIRROR @ self.scope.matrix, mirrored=not self.scope.mirrored), fn, True)
        return fn

    def bone(self, name, fn=None, o=None, **kw):
        o = _opts(o, kw)
        real = SWAP_LR(name) if self.scope.mirrored else name
        j = self.joints.get(name)
        if not j:
            raise ValueError("sdf: unknown joint '%s'" % name)
        base = MIRROR @ j['matrix'] if self.scope.mirrored else j['matrix'].copy()
        patch = dict(matrix=base, bone=self.resolveBone(o['bone']) if 'bone' in o else self.chainOf(real))
        if fn is not None:
            self._run(patch, fn)
            return None
        return _Ctx(self, patch)

    def frame(self, o=None, fn=None, **kw):
        if callable(o) and fn is None:
            fn, o = o, None
        o = _opts(o, kw)
        patch = dict(matrix=self.scope.matrix @ toMatrix(o))
        if fn is not None:
            self._run(patch, fn)
            return None
        return _Ctx(self, patch)

    def patternFrame(self, o=None, **kw):
        """'tri' = triplanar in the frame's axes; 'cyl' = cylindrical around its local y (u around, v along), seam at
        the back (+z). radius = nominal radius used to snap stripe counts."""
        o = _opts(o, kw)
        W = self.place(o)
        if o.axis:
            ax = np.array(o.axis, float)
            ax = ax / np.linalg.norm(ax)
            q = m4.quat_from_unit_vectors([0, 1, 0], ax)
            W = W @ m4.compose((0, 0, 0), q, (1, 1, 1))
        f = O(id=len(self.frames), mode=jor(o.mode, 'cyl'), matrix=W, inv=np.linalg.inv(W), radius=jor(o.radius, 0.15),
              mirrored=self.scope.mirrored)
        self.frames.append(f)
        return f.id

    def stitch(self, points, o=None, **kw):
        """Stitch / seam line in rest space (projected onto the surface by the baker). points in scope frame."""
        o = _opts(o, kw)
        pts = [m4.apply(self.scope.matrix, v3(p)) for p in points]
        self.stitches.append(O(pts=pts, width=nz(o.width, 0.0014), dash=nz(o.dash, 0.009), duty=nz(o.duty, 0.6),
                               color=jor(o.color, '#F08A2E'), mats=[self.matIndex(m) for m in (o.mats or [])],
                               smooth=nz(o.smooth, True), segLen=nz(o.segLen, 0.012)))

    def toWorld(self, p):
        """World position of a point given in the current scope frame."""
        return m4.apply(self.scope.matrix, v3(p))

    def snap(self, node, p, lift=0):
        """Project a point (scope coords) onto the surface of an already-built node, lifted `lift` m along the
        outward normal; returns scope coords."""
        return self.snapAll(node, [p], [lift])[0]

    def normalAt(self, node, p):
        """Outward surface normal of a built node at a point (scope coords in and out)."""
        e = 0.001
        w = np.array(m4.apply(self.scope.matrix, v3(p)))
        off = np.array([[e, 0, 0], [-e, 0, 0], [0, e, 0], [0, -e, 0], [0, 0, e], [0, 0, -e]])
        Q = w + off
        d = eval_dist(node, Q[:, 0], Q[:, 1], Q[:, 2])
        g = [d[0] - d[1], d[2] - d[3], d[4] - d[5]]
        mi = np.linalg.inv(self.scope.matrix)
        v = m4.apply3(mi, g)
        ln = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) or 1
        return [v[0] / ln, v[1] / ln, v[2] / ln]

    def snapAll(self, node, pts, lift=0):
        n = len(pts)
        if n == 0:
            return []
        lifts = np.array(lift if isinstance(lift, (list, tuple, np.ndarray)) else [lift] * n, float)
        W = m4.apply_pts(self.scope.matrix, np.array([v3(p) for p in pts], float))
        x, y, z = W[:, 0].copy(), W[:, 1].copy(), W[:, 2].copy()
        e = 0.0008
        active = np.ones(n, bool)
        for _ in range(8):
            ia = np.nonzero(active)[0]
            if not len(ia):
                break
            xa, ya, za = x[ia], y[ia], z[ia]
            m = len(ia)
            X = np.concatenate([xa, xa + e, xa - e, xa, xa, xa, xa])
            Y = np.concatenate([ya, ya, ya, ya + e, ya - e, ya, ya])
            Z = np.concatenate([za, za, za, za, za, za + e, za - e])
            f = eval_dist(node, X, Y, Z).reshape(7, m)
            d = f[0] - lifts[ia]
            gx = (f[1] - f[2]) / (2 * e)
            gy = (f[3] - f[4]) / (2 * e)
            gz = (f[5] - f[6]) / (2 * e)
            g2 = gx * gx + gy * gy + gz * gz
            ok = g2 >= 1e-10
            with np.errstate(divide='ignore', invalid='ignore'):
                sx = np.where(ok, d * gx / g2, 0)
                sy = np.where(ok, d * gy / g2, 0)
                sz = np.where(ok, d * gz / g2, 0)
            x[ia] -= sx
            y[ia] -= sy
            z[ia] -= sz
            done = (~ok) | (np.abs(d) < 1e-5)
            active[ia[done]] = False
        mi = np.linalg.inv(self.scope.matrix)
        L = m4.apply_pts(mi, np.stack([x, y, z], 1))
        return [list(map(float, r)) for r in L]


def createSculptor(opts=None, **kw):
    return Sculptor(opts, **kw)


# ---------------------------------------------------------------------------------------------------------------
# Leaf evaluation (vectorised): leaf_dist(L, x, y, z) world coords -> distance (world units)
def _prepare_leaf(L):
    L._local = _make_local(L)


def _make_local(L):
    t = L.type
    if t == 'sphere':
        r = L.r
        return lambda x, y, z: np.sqrt(x * x + y * y + z * z) - r
    if t == 'ellipsoid':
        return lambda x, y, z: sdEllipsoid(x, y, z, L.rx, L.ry, L.rz)
    if t == 'box':
        return lambda x, y, z: sdBox(x, y, z, L.bx, L.by, L.bz, L.rr)
    if t == 'capsule':
        (ax, ay, az), (bx, by, bz), r = L.a, L.b, L.r
        return lambda x, y, z: sdCapsule(x, y, z, ax, ay, az, bx, by, bz, r)
    if t == 'roundCone':
        (ax, ay, az), (bx, by, bz) = L.a, L.b
        return lambda x, y, z: sdRoundCone(x, y, z, ax, ay, az, bx, by, bz, L.ra, L.rb)
    if t == 'torus':
        return lambda x, y, z: sdTorus(x, y, z, L.R, L.rt)
    if t == 'arc':
        return lambda x, y, z: sdArc(x, y, z, L.sa, L.ca, L.R, L.rt)
    if t == 'cylinder':
        return lambda x, y, z: sdCylinder(x, y, z, L.r, L.h, L.rr)
    if t == 'cone':
        return lambda x, y, z: sdCappedCone(x, y, z, L.h, L.r1, L.r2) - L.rr
    if t == 'plane':
        return lambda x, y, z: x * L.nx + y * L.ny + z * L.nz - L.d
    if t == 'worm':
        _prepare_worm(L)
        return None
    if t == 'custom':
        f = L.cfn
        return lambda x, y, z: np.asarray(f(x, y, z), float) + 0 * x
    raise ValueError('sdf: bad leaf ' + t)


def _prepare_worm(L):
    seg = L.seg
    L._A = seg[:, 0:3].copy()
    L._B = seg[:, 3:6].copy()
    L._R1 = seg[:, 6].copy()
    L._R2 = seg[:, 7].copy()
    L._N = seg[:, 8:11].copy()
    L._BN = seg[:, 11:14].copy()
    c = (L._A + L._B) / 2
    hl = np.linalg.norm(L._B - L._A, axis=1) / 2
    L._bs = np.concatenate([c, (hl + np.maximum(L._R1, L._R2))[:, None]], 1)


def _worm_eval(L, x, y, z, want=False):
    """Worm: min over round-cone segments; flattening and grooves use the segment frame.
    Returns d (and t, i when want)."""
    n = L.segs
    flat = L.flat
    gr = L.grooves
    N = len(x)
    out_d = np.empty(N)
    out_t = np.empty(N) if (want or gr) else None
    out_i = np.empty(N, np.int64) if want else None
    CH = max(1, 400000 // max(1, n))
    A, Bp, R1, R2, NN = L._A, L._B, L._R1, L._R2, L._N
    for s in range(0, N, CH):
        e = min(N, s + CH)
        px = x[s:e, None]
        py = y[s:e, None]
        pz = z[s:e, None]
        if flat != 1:
            dx = px - A[:, 0]
            dy = py - A[:, 1]
            dz = pz - A[:, 2]
            kb = (dx * NN[:, 0] + dy * NN[:, 1] + dz * NN[:, 2]) * (1 / flat - 1)
            qx = px + NN[:, 0] * kb
            qy = py + NN[:, 1] * kb
            qz = pz + NN[:, 2] * kb
            d = sdRoundConeV(qx, qy, qz, A, Bp, R1, R2) * flat
        else:
            d = sdRoundConeV(px, py, pz, A, Bp, R1, R2)
        bi = np.argmin(d, axis=1)
        best = d[np.arange(e - s), bi]
        # Param along the curve and the angle around it (for grooves / color gradients).
        a = A[bi]
        tv = Bp[bi] - a
        l2 = (tv * tv).sum(1)
        l2 = np.where(l2 == 0, 1e-12, l2)
        dd = np.stack([x[s:e], y[s:e], z[s:e]], 1) - a
        u = np.clip((dd * tv).sum(1) / l2, 0, 1)
        bt = (bi + u) / n
        if gr:
            gN = gr.get('n') or 6
            gD = gr.get('depth') or 0.002
            gOff = gr.get('phase') or 0
            cu = (dd * NN[bi]).sum(1)
            cv = (dd * L._BN[bi]).sum(1)
            ang = np.arctan2(cv, cu)
            fadeTip = smoothstep(0.0, 0.15, bt) * smoothstep(1.0, 0.8, bt)
            best = best + gD * (0.5 - 0.5 * np.cos(ang * gN + gOff)) * fadeTip
        out_d[s:e] = best
        if out_t is not None:
            out_t[s:e] = bt
        if out_i is not None:
            out_i[s:e] = bi
    if want:
        return out_d, out_t, out_i
    return out_d


def leaf_dist(L, x, y, z, want=False):
    m = L.m
    lx = m[0, 0] * x + m[0, 1] * y + m[0, 2] * z + m[0, 3]
    ly = m[1, 0] * x + m[1, 1] * y + m[1, 2] * z + m[1, 3]
    lz = m[2, 0] * x + m[2, 1] * y + m[2, 2] * z + m[2, 3]
    t = i = None
    if L.type == 'worm':
        if want:
            d, t, i = _worm_eval(L, lx, ly, lz, True)
        else:
            d = _worm_eval(L, lx, ly, lz)
    else:
        d = L._local(lx, ly, lz)
    d = d * L.s
    nzs = L.noise
    if nzs:
        amp = nzs.get('amp') or 0.003
        fr = nzs.get('freq') or 40
        oct_ = nzs.get('oct') or 2
        st = nzs.get('stretch') or [1, 1, 1]
        sd = (nzs.get('seed') or 0) * 17.13
        nn = fbm3(lx * fr * st[0] + sd, ly * fr * st[1] + sd * 0.7, lz * fr * st[2] - sd, oct_)
        if nzs.get('ridge'):
            nn = 0.5 - np.abs(nn) * 2
        d = d + amp * nn
    if L.offset != 0 or L.shell != 0:
        d = d - L.offset
        if L.shell:
            d = np.abs(d) - L.shell
    if want:
        return d, t, i
    return d


# ---------------------------------------------------------------------------------------------------------------
# Tree evaluation. Groups combine children in order.
def combine(op, a, b, k):
    if op == 'add':
        return smin(a, b, k)
    if op == 'sub':
        return ssub(a, b, k)
    if op == 'int':
        return sint(a, b, k)
    return a


def eval_dist(node, x, y, z, ev=None, bid=None):
    """Distance of `node` at points (x, y, z) (1-D arrays). ev/bid: an Evaluator + per-point block ids (pruning)."""
    if node.kind == 'leaf':
        return leaf_dist(node, x, y, z)
    n = len(x)
    d = np.full(n, BIG)
    for c in node.children:
        if c.op == 'paint':
            continue
        k = c.k or 0
        if ev is not None:
            sel = ev.keep[c.id][bid]
            cnt = int(sel.sum())
            if cnt == 0:
                continue
            if cnt < n:
                idx = np.nonzero(sel)[0]
                dc = eval_dist(c, x[idx], y[idx], z[idx], ev, bid[idx])
                d[idx] = combine(c.op, d[idx], dc, k)
                continue
        dc = eval_dist(c, x, y, z, ev, bid)
        d = combine(c.op, d, dc, k)
    off = node.offset or 0
    sh = node.shell or 0
    if off != 0 or sh != 0:
        d = d - off
        if sh:
            d = np.abs(d) - sh
    return d


def compileTree(node):
    """Compute node boxes (call once after sculpting)."""
    if node.kind == 'leaf':
        return node
    for c in node.children:
        compileTree(c)
    box = [math.inf, math.inf, math.inf, -math.inf, -math.inf, -math.inf]
    for c in node.children:
        if c.op != 'add':
            continue
        k = max(c.k or 0, 0)
        for i in range(3):
            box[i] = min(box[i], c.box[i] - k)
            box[i + 3] = max(box[i + 3], c.box[i + 3] + k)
    # Intersections shrink the box.
    for c in node.children:
        if c.op == 'int':
            for i in range(3):
                box[i] = max(box[i], c.box[i] - (c.k or 0))
                box[i + 3] = min(box[i + 3], c.box[i + 3] + (c.k or 0))
    o = max(node.offset or 0, 0) + (node.shell or 0)
    node.box = [box[0] - o, box[1] - o, box[2] - o, box[3] + o, box[4] + o, box[5] + o]
    return node


def boxDistV(b, Q):
    """Distance between box b (6,) and boxes Q (NB,6) (0 if overlapping)."""
    dx = np.maximum(0, np.maximum(b[0] - Q[:, 3], Q[:, 0] - b[3]))
    dy = np.maximum(0, np.maximum(b[1] - Q[:, 4], Q[:, 1] - b[4]))
    dz = np.maximum(0, np.maximum(b[2] - Q[:, 5], Q[:, 2] - b[5]))
    with np.errstate(invalid='ignore'):
        r = np.sqrt(dx * dx + dy * dy + dz * dz)
    return np.nan_to_num(r, nan=np.inf)


class Evaluator:
    """Per-block pruning of a compiled tree for many query boxes at once, identical to the JS pruneTree():
    keep[node.id] = bool (NB,) per query box. Points carry a block id; a child is evaluated only on the points of
    the blocks that keep it (pruned children contribute nothing, exactly like the pruned JS copies)."""

    def __init__(self, root, boxes, margin):
        self.root = root
        self.boxes = np.asarray(boxes, float).reshape(-1, 6)
        self.keep = {}
        self.rootKeep = self._prune(root, margin)

    def _prune(self, node, margin):
        Q = self.boxes
        if node.kind == 'leaf':
            k = boxDistV(node.box, Q) <= margin + (node.k or 0)
            self.keep[node.id] = k
            return k
        nb = len(Q)
        has_add = np.zeros(nb, bool)
        ok = np.ones(nb, bool)
        for c in node.children:
            if c.op == 'paint':
                b = c.box if c.box is not None else [-1e9, -1e9, -1e9, 1e9, 1e9, 1e9]
                self.keep[c.id] = boxDistV(b, Q) <= margin + (c.paint.soft if c.paint else 0)
                self._full(c)
                continue
            kc = self._prune(c, margin + max(c.k or 0, 0))
            if c.op == 'int':
                ok &= kc
            elif c.op == 'add':
                has_add |= kc
        res = ok & has_add
        self.keep[node.id] = res
        return res

    def _full(self, node):
        """Paint groups are kept unpruned inside (JS keeps the paint node itself)."""
        if node.kind == 'group':
            for c in node.children:
                self.keep[c.id] = np.ones(len(self.boxes), bool)
                self._full(c)

    def dist(self, P, bid):
        """P (N,3), bid (N,) block ids -> distances (BIG where the block keeps nothing)."""
        P = np.asarray(P, float)
        n = len(P)
        d = np.full(n, BIG)
        sel = self.rootKeep[bid]
        idx = np.nonzero(sel)[0]
        if len(idx):
            d[idx] = eval_dist(self.root, P[idx, 0], P[idx, 1], P[idx, 2], self, bid[idx])
        return d

    def sample(self, sampler, P, bid):
        P = np.asarray(P, float)
        n = len(P)
        out = _empty_attr(n)
        sel = self.rootKeep[bid]
        idx = np.nonzero(sel)[0]
        if len(idx):
            r = sampler.eval(self.root, P[idx, 0], P[idx, 1], P[idx, 2], self, bid[idx])
            for k in out:
                out[k][idx] = r[k]
        return out


class FullEvaluator:
    """No pruning (the whole tree everywhere)."""

    def __init__(self, root):
        self.root = root

    def dist(self, P, bid=None):
        P = np.asarray(P, float)
        return eval_dist(self.root, P[:, 0], P[:, 1], P[:, 2])

    def sample(self, sampler, P, bid=None):
        P = np.asarray(P, float)
        return sampler.eval(self.root, P[:, 0], P[:, 1], P[:, 2], None, None)


class CellEvaluator:
    """JS makeLocalTrees / makeRegionTrees: points are grouped in a grid of `cell` m cubes, each cube uses the tree
    pruned to it with `margin`."""

    def __init__(self, root, cell, margin):
        self.root = root
        self.cell = cell
        self.margin = margin
        self.cells = {}      # (i,j,k) -> block id
        self.boxes = []
        self.ev = None
        self._dirty = True

    def _bids(self, P, key_points=None):
        K = np.floor((P if key_points is None else key_points) / self.cell).astype(np.int64)
        keys = [tuple(k) for k in K]
        bid = np.empty(len(keys), np.int64)
        c = self.cell
        for i, k in enumerate(keys):
            b = self.cells.get(k)
            if b is None:
                b = len(self.boxes)
                self.cells[k] = b
                self.boxes.append([k[0] * c, k[1] * c, k[2] * c, (k[0] + 1) * c, (k[1] + 1) * c, (k[2] + 1) * c])
                self._dirty = True
            bid[i] = b
        if self._dirty:
            self.ev = Evaluator(self.root, np.array(self.boxes), self.margin)
            # JS: pruneTree(...) || tree  -> a cell where nothing is kept falls back to the whole tree
            for key in list(self.ev.keep.keys()):
                pass
            empty = ~self.ev.rootKeep
            if empty.any():
                self._fallback(empty)
            self._dirty = False
        return bid

    def _fallback(self, empty):
        ev = self.ev
        for key, arr in ev.keep.items():
            arr[empty] = True
        ev.rootKeep = ev.rootKeep | empty

    def bids(self, P):
        return self._bids(np.asarray(P, float))

    def dist(self, P, bid=None):
        P = np.asarray(P, float)
        if bid is None:
            bid = self._bids(P)
        return self.ev.dist(P, bid)

    def sample(self, sampler, P, bid=None):
        P = np.asarray(P, float)
        if bid is None:
            bid = self._bids(P)
        return self.ev.sample(sampler, P, bid)


# ---------------------------------------------------------------------------------------------------------------
# Attribute sampling: distance + dominant leaf + blended color + material (with paint layers).
def hexToRgb(hexv, out=None):
    """sRGB hex -> LINEAR rgb (THREE.Color with color management); arrays pass through."""
    if isinstance(hexv, (list, tuple)):
        return [float(hexv[0]), float(hexv[1]), float(hexv[2])]
    h = str(hexv).strip()
    if h.startswith('#'):
        h = h[1:]
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    v = int(h[:6], 16)
    rgb = [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255]
    return [srgb_to_linear(c) for c in rgb]


def srgb_to_linear(c):
    return c / 12.92 if c < 0.04045 else ((c * 0.9478672986 + 0.0521327014) ** 2.4)


def linear_to_srgb(c):
    return c * 12.92 if c < 0.0031308 else 1.055 * (c ** 0.41666) - 0.055


ATTR_KEYS = ('d', 'leaf', 'mat', 'r', 'g', 'b', 'pframe', 'wormT', 'wormI')


def _empty_attr(n):
    return {'d': np.full(n, BIG), 'leaf': np.full(n, -1, np.int64), 'mat': np.full(n, -1, np.int64),
            'r': np.ones(n), 'g': np.ones(n), 'b': np.ones(n), 'pframe': np.zeros(n, np.int64),
            'wormT': np.zeros(n), 'wormI': np.full(n, -1, np.int64)}


class Sampler:
    def __init__(self, materials):
        matList = list(materials.values())
        self.baseCol = [hexToRgb(m.get('tint') or '#ffffff') if m.get('pattern') else hexToRgb(m.get('color') or '#ffffff') for m in matList]
        self.colCache = {}

    def leafCol(self, leaf):
        c = self.colCache.get(leaf.id)
        if c is None:
            a = hexToRgb(leaf.color) if leaf.color else (self.baseCol[leaf.mat] if leaf.mat >= 0 else [1, 1, 1])
            b = hexToRgb(leaf.color2) if leaf.color2 else None
            c = (a, b)
            self.colCache[leaf.id] = c
        return c

    def eval(self, node, x, y, z, ev=None, bid=None):
        n = len(x)
        if node.kind == 'leaf':
            d, t, i = leaf_dist(node, x, y, z, True)
            o = {'d': d, 'leaf': np.full(n, node.uid, np.int64), 'mat': np.full(n, node.mat, np.int64),
                 'pframe': np.full(n, node.pframe, np.int64)}
            if node.type == 'worm':
                o['wormT'] = t
                o['wormI'] = i
            else:
                o['wormT'] = np.zeros(n)
                o['wormI'] = np.full(n, -1, np.int64)
            ca, cb = self.leafCol(node)
            if cb is None:
                o['r'] = np.full(n, ca[0])
                o['g'] = np.full(n, ca[1])
                o['b'] = np.full(n, ca[2])
            else:
                tt = o['wormT']
                s = tt * tt * (3 - 2 * tt)
                o['r'] = ca[0] + (cb[0] - ca[0]) * s
                o['g'] = ca[1] + (cb[1] - ca[1]) * s
                o['b'] = ca[2] + (cb[2] - ca[2]) * s
            return o
        out = None
        first = True
        for c in node.children:
            if c.op == 'paint':
                continue
            if ev is not None:
                sel = ev.keep[c.id][bid]
                cnt = int(sel.sum())
            else:
                sel = None
                cnt = n
            if first:
                if c.op != 'add':
                    continue
                first = False
                if cnt == n:
                    out = self.eval(c, x, y, z, ev, bid)
                else:
                    out = _empty_attr(n)
                    if cnt:
                        idx = np.nonzero(sel)[0]
                        r = self.eval(c, x[idx], y[idx], z[idx], ev, bid[idx])
                        for kk in out:
                            out[kk][idx] = r[kk]
                continue
            if cnt == 0:
                continue
            if cnt == n:
                idx = None
                tmp = self.eval(c, x, y, z, ev, bid)
            else:
                idx = np.nonzero(sel)[0]
                tmp = self.eval(c, x[idx], y[idx], z[idx], ev, bid[idx])
            self._combine(out, tmp, idx, c)
        if first:
            out = _empty_attr(n)
            out['d'][:] = BIG
            out['leaf'][:] = -1
            out['mat'][:] = -1
            return out
        # Group offset / shell
        if node.offset:
            out['d'] = out['d'] - node.offset
        if node.shell:
            out['d'] = np.abs(out['d']) - node.shell
        # Paint layers (after geometry): blend color, maybe switch material.
        for c in node.children:
            if c.op != 'paint':
                continue
            if ev is not None:
                sel = ev.keep[c.id][bid]
                if not sel.any():
                    continue
            else:
                sel = np.ones(n, bool)
            P = c.paint
            if P.only is not None:
                sel = sel & np.isin(out['mat'], P.only)
            idx = np.nonzero(sel)[0]
            if not len(idx):
                continue
            pd = eval_dist(c, x[idx], y[idx], z[idx])
            w = (1 - smoothstep(-P.soft, P.soft, pd)) * P.strength
            pos = w > 0
            if not pos.any():
                continue
            idx = idx[pos]
            w = w[pos]
            if P.color:
                pc = hexToRgb(P.color)
                for ci, kk in enumerate(('r', 'g', 'b')):
                    out[kk][idx] += (pc[ci] - out[kk][idx]) * w
            if P.mat >= 0:
                sw = w >= 0.5 * P.strength
                j = idx[sw]
                if len(j):
                    out['mat'][j] = P.mat
                    if not P.color:
                        cc = self.baseCol[P.mat]
                        out['r'][j] = cc[0]
                        out['g'][j] = cc[1]
                        out['b'][j] = cc[2]
                    if P.pframe is not None:
                        out['pframe'][j] = P.pframe
        return out

    def _combine(self, out, tmp, idx, c):
        k = c.k or 0
        if idx is None:
            O_ = out
            a = out['d']
        else:
            O_ = {kk: out[kk][idx] for kk in out}
            a = O_['d']
        b = tmp['d']
        if c.op == 'add':
            nd = smin(a, b, k)
            if k > 0:
                tb = clamp01(0.5 + 0.5 * (a - b) / k)
            else:
                tb = np.where(b < a, 1.0, 0.0)
            less = b < a
            same = tmp['mat'] == O_['mat']
            w = np.where(same, tb, 1.0)
            wc = np.where(less, w, np.where(same & (tb > 0), tb, 0.0))
            for kk in ('r', 'g', 'b'):
                O_[kk] = O_[kk] + (tmp[kk] - O_[kk]) * wc
            for kk in ('leaf', 'mat', 'pframe', 'wormT', 'wormI'):
                O_[kk] = np.where(less, tmp[kk], O_[kk])
            O_['d'] = nd
        elif c.op == 'sub':
            nd = ssub(a, b, k)
            if c.cutMat is not None:
                cut = -b > a - k * 0.25
                if cut.any():
                    O_['mat'] = np.where(cut, c.cutMat, O_['mat'])
                    O_['leaf'] = np.where(cut, tmp['leaf'], O_['leaf'])
                    cc = self.baseCol[c.cutMat]
                    O_['r'] = np.where(cut, cc[0], O_['r'])
                    O_['g'] = np.where(cut, cc[1], O_['g'])
                    O_['b'] = np.where(cut, cc[2], O_['b'])
            O_['d'] = nd
        elif c.op == 'int':
            O_['d'] = sint(a, b, k)
        if idx is not None:
            for kk in out:
                out[kk][idx] = O_[kk]


def makeSampler(materials):
    return Sampler(materials)


# Iterate leaves (for stats / bounds).
def forEachLeaf(node, fn):
    if node.kind == 'leaf':
        return fn(node)
    for c in node.children:
        forEachLeaf(c, fn)


def indexLeaves(root):
    """Deterministic leaf numbering (DFS order)."""
    lst = []

    def f(l):
        l.dfs = len(lst)
        lst.append(l)
    forEachLeaf(root, f)
    return lst
