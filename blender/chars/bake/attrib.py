"""Per-vertex attribute sampling + crisp material/pattern-frame borders + pattern coordinates
(port of tools/bake/attrib.mjs).
Mesh representation through the bake ("V"): numpy arrays grown by concatenation:
  V.pos (n,3) V.nrm (n,3) V.col (n,3) V.mat (n) V.frame (n) V.key (n) V.flow (n,3) V.leaf (n, leaf uid or -1)
  V.weld (n) V.pco (n,3) V.pmode (n) V.wormT (n);  I = triangle indices (m,3)
"""
import math
import numpy as np

from ..jsutil import O
from ..sdf import LEAVES, CellEvaluator
from .mesher import projectTet

KEYM = 256


def keyOf(mat, frame):
    return (mat + 1) * KEYM + frame


def gradAt(ev, P, bid, e):
    """Normalised central-difference gradient (6 evals) of the (pruned) tree at P (N,3)."""
    n = len(P)
    off = np.array([[e, 0, 0], [-e, 0, 0], [0, e, 0], [0, -e, 0], [0, 0, e], [0, 0, -e]])
    Q = (P[None, :, :] + off[:, None, :]).reshape(-1, 3)
    bq = None if bid is None else np.tile(bid, 6)
    f = ev.dist(Q, bq).reshape(6, n)
    g = np.stack([f[0] - f[1], f[2] - f[3], f[4] - f[5]], 1)
    ln = np.sqrt((g * g).sum(1))
    ln[ln == 0] = 1
    return g / ln[:, None]


def projectToSurface(ev, P, bid, iters=3, e=0.0008, tol=2e-6):
    """attrib.mjs projectToSurface, vectorised (per-point early exit like the JS)."""
    P = np.array(P, float)
    n = len(P)
    active = np.ones(n, bool)
    off = np.array([[0, 0, 0], [e, 0, 0], [-e, 0, 0], [0, e, 0], [0, -e, 0], [0, 0, e], [0, 0, -e]])
    for _ in range(iters):
        ia = np.nonzero(active)[0]
        if not len(ia):
            break
        Pa = P[ia]
        Q = (Pa[None, :, :] + off[:, None, :]).reshape(-1, 3)
        bq = None if bid is None else np.tile(bid[ia], 7)
        f = ev.dist(Q, bq).reshape(7, len(ia))
        d = f[0]
        small = np.abs(d) < tol
        g = np.stack([(f[1] - f[2]) / (2 * e), (f[3] - f[4]) / (2 * e), (f[5] - f[6]) / (2 * e)], 1)
        g2 = (g * g).sum(1)
        flat = g2 < 1e-10
        mv = ~(small | flat)
        with np.errstate(divide='ignore', invalid='ignore'):
            step = np.where(mv[:, None], g * (d / np.where(g2 > 0, g2, 1))[:, None], 0)
        P[ia] = Pa - step
        active[ia[small | flat]] = False
    return P


def flowOf(leafUids, wormI, P):
    """Hair strand direction per vertex: leaf flowFn, else worm segment tangent, else 0."""
    n = len(leafUids)
    out = np.zeros((n, 3))
    for u in np.unique(leafUids):
        if u < 0:
            continue
        L = LEAVES[int(u)]
        sel = np.nonzero(leafUids == u)[0]
        if L.flowFn is not None:
            p = P[sel]
            d = L.flowFn(p[:, 0], p[:, 1], p[:, 2])
            d = np.stack([np.broadcast_to(np.asarray(c, float), (len(sel),)) for c in d], 1)
            ln = np.sqrt((d * d).sum(1))
            ln[ln == 0] = 1
            out[sel] = d / ln[:, None]
            continue
        if L.type != 'worm' or L.flowTag is False:
            continue
        wi = wormI[sel]
        ok = wi >= 0
        if not ok.any():
            continue
        s = L.seg[wi[ok]]
        dd = s[:, 3:6] - s[:, 0:3]
        ln = np.sqrt((dd * dd).sum(1))
        ln[ln == 0] = 1
        out[sel[ok]] = dd / ln[:, None]
    return out


class VMesh:
    FIELDS3 = ('pos', 'nrm', 'col', 'flow', 'pco')
    FIELDS1 = ('mat', 'frame', 'key', 'leaf', 'weld', 'pmode', 'wormT')

    def __init__(self):
        self.pos = np.zeros((0, 3))
        self.nrm = np.zeros((0, 3))
        self.col = np.zeros((0, 3))
        self.flow = np.zeros((0, 3))
        self.pco = np.zeros((0, 3))
        self.mat = np.zeros(0, np.int64)
        self.frame = np.zeros(0, np.int64)
        self.key = np.zeros(0, np.int64)
        self.leaf = np.zeros(0, np.int64)
        self.weld = np.zeros(0, np.int64)
        self.pmode = np.zeros(0, np.int64)
        self.wormT = np.zeros(0)

    @property
    def n(self):
        return len(self.mat)

    def append(self, **f):
        m = len(f['mat'])
        for k in self.FIELDS3:
            v = f.get(k)
            if v is None:
                v = np.zeros((m, 3))
            setattr(self, k, np.concatenate([getattr(self, k), np.asarray(v, float).reshape(m, 3)]))
        for k in self.FIELDS1:
            v = f.get(k)
            if v is None:
                v = np.zeros(m)
            dt = float if k == 'wormT' else np.int64
            setattr(self, k, np.concatenate([getattr(self, k), np.asarray(v).astype(dt).reshape(m)]))

    def copy_rows(self, src, **over):
        """Copies of vertices src (same position/weld) with optional overrides; returns new indices."""
        n0 = self.n
        f = {k: getattr(self, k)[src].copy() for k in self.FIELDS3 + self.FIELDS1}
        for k, v in over.items():
            f[k] = v
        f['key'] = keyOf(f['mat'], f['frame'])
        self.append(**f)
        return np.arange(n0, n0 + len(src))


def sampleAt(S, P, bid=None):
    """Sampler + gradient at points (the treeAt / local tree used by sampleBatch / pushSample)."""
    ev = S.treeAt
    if bid is None:
        bid = ev.bids(P)
    o = ev.sample(S.sampler, P, bid)
    g = gradAt(ev, P, bid, S.voxel * 0.35)
    return o, g


def sampleMesh(mesh, S):
    """Samples every surface-net vertex (JS sampleBatch: local trees cell 0.06 m, margin voxel*3)."""
    V = VMesh()
    P = mesh.positions
    local = CellEvaluator(S.tree, 0.06, S.voxel * 3)
    n = len(P)
    CH = 60000
    for s in range(0, n, CH):
        p = P[s:s + CH]
        bid = local.bids(p)
        o = local.sample(S.sampler, p, bid)
        g = gradAt(local, p, bid, S.voxel * 0.35)
        mat = o['mat']
        fr = o['pframe']
        V.append(pos=p, nrm=g, col=np.stack([o['r'], o['g'], o['b']], 1), mat=mat, frame=fr, key=keyOf(mat, fr),
                 leaf=o['leaf'], wormT=o['wormT'], flow=flowOf(o['leaf'], o['wormI'], p),
                 weld=np.arange(s, s + len(p)), pco=None, pmode=None)
    return V, mesh.indices.copy()


def cutBorders(V, I, S):
    """Split triangles along material/pattern-frame borders found by bisection -> crisp, smooth borders."""
    ev = S.treeAt
    K = V.key
    ka, kb, kc = K[I[:, 0]], K[I[:, 1]], K[I[:, 2]]
    same = (ka == kb) & (kb == kc)
    three = (ka != kb) & (kb != kc) & (ka != kc)
    two = ~same & ~three
    out = [I[same]]
    # --- three different keys: flat triangle of the first vertex's key (copies of b, c)
    T3 = I[three]
    if len(T3):
        copies = {}
        rows = []
        for a, b, c in T3:
            r = [a]
            for v in (b, c):
                if K[v] == K[a]:
                    r.append(v)
                    continue
                ck = (int(v), int(K[a]) % 4096)
                if ck not in copies:
                    copies[ck] = None
                r.append(ck)
            rows.append(r)
        keys = [ck for ck in copies]
        if keys:
            src = np.array([k[0] for k in keys])
            # override mat/frame/leaf/col from the lone key's vertex a: find a representative a per key
            rep = {}
            for (a, b, c), r in zip(T3, rows):
                for x in r[1:]:
                    if isinstance(x, tuple) and x not in rep:
                        rep[x] = a
            ra = np.array([rep[k] for k in keys])
            new = V.copy_rows(src, mat=V.mat[ra], frame=V.frame[ra], leaf=V.leaf[ra], col=V.col[ra])
            for k, ni in zip(keys, new):
                copies[k] = int(ni)
        out.append(np.array([[x if not isinstance(x, tuple) else copies[x] for x in r] for r in rows], np.int64))
    # --- two keys: rotate so that the lone vertex X is first
    T2 = I[two]
    cut = 0
    if len(T2):
        a, b, c = T2[:, 0], T2[:, 1], T2[:, 2]
        Ka, Kb, Kc = K[a], K[b], K[c]
        r1 = Kb == Kc
        r2 = ~r1 & (Ka == Kc)
        X = np.where(r1, a, np.where(r2, b, c))
        Y = np.where(r1, b, np.where(r2, c, a))
        Z = np.where(r1, c, np.where(r2, a, b))
        # unique undirected edges X-Y and X-Z (direction: first occurrence decides, like the JS edge cache)
        E = np.concatenate([np.stack([X, Y], 1), np.stack([X, Z], 1)])
        lo = np.minimum(E[:, 0], E[:, 1])
        hi = np.maximum(E[:, 0], E[:, 1])
        ek = lo * (V.n + 1) + hi
        uk, first, inv = np.unique(ek, return_index=True, return_inverse=True)
        Ed = E[first]                                    # directed as first encountered (a = lone vertex)
        cr = _crossings(V, S, Ed)                          # (ne, 2): index for key of Ed[:,0], key of Ed[:,1]
        # map: for triangle edge (X, other) find crossing copies for keys kx, ky
        eXY = inv[:len(X)]
        eXZ = inv[len(X):]

        def side(eidx, v):
            # crossing copy with the key of vertex v
            src0 = Ed[eidx, 0]
            return np.where(K[src0] == K[v], cr[eidx, 0], cr[eidx, 1])
        mxyX, mxyY = side(eXY, X), side(eXY, Y)
        mxzX, mxzY = side(eXZ, X), side(eXZ, Y)
        out.append(np.stack([X, mxyX, mxzX], 1))
        out.append(np.stack([mxyY, Y, Z], 1))
        out.append(np.stack([mxyY, Z, mxzY], 1))
        cut = len(T2)
    return np.concatenate(out).astype(np.int64), cut


def _crossings(V, S, Ed):
    """For directed edges (a, b) with different keys: bisection (7 steps) on the key, projection, two samples at the
    same position forced to the two sides. Returns (ne, 2) new vertex indices [side a, side b]."""
    ev = S.treeAt
    ne = len(Ed)
    a, b = Ed[:, 0], Ed[:, 1]
    pa, pb = V.pos[a], V.pos[b]
    ka = V.key[a]
    lo = np.zeros(ne)
    hi = np.ones(ne)
    for _ in range(7):
        m = (lo + hi) * 0.5
        pm = pa + (pb - pa) * m[:, None]
        o = ev.sample(S.sampler, pm)
        k = keyOf(o['mat'], o['pframe'])
        eq = k == ka
        lo = np.where(eq, m, lo)
        hi = np.where(eq, hi, m)
    mid = pa + (pb - pa) * 0.5
    bid = ev.bids(mid)
    e, mm = S.voxel * 0.3, S.voxel * 0.5
    pm = projectTet(ev, pa + (pb - pa) * ((lo + hi) * 0.5)[:, None], bid, e, 2, mm)
    plo = projectTet(ev, pa + (pb - pa) * lo[:, None], bid, e, 2, mm)
    phi = projectTet(ev, pa + (pb - pa) * hi[:, None], bid, e, 2, mm)
    base = V.n
    weld = base + np.arange(ne) * 2                     # weld = index of the first pushed sample (V.mat.length)
    res = np.zeros((ne, 2), np.int64)
    for j, (pp, src) in enumerate(((plo, a), (phi, b))):
        o, _g = sampleAt(S, pp)
        mat, fr = o['mat'], o['pframe']
        col = np.stack([o['r'], o['g'], o['b']], 1)
        leaf = o['leaf']
        key = keyOf(mat, fr)
        flow = flowOf(leaf, o['wormI'], pp)
        # Same position for both copies, keys forced to the two sides.
        diff = key != V.key[src]
        mat = np.where(diff, V.mat[src], mat)
        fr = np.where(diff, V.frame[src], fr)
        leaf = np.where(diff, V.leaf[src], leaf)
        col = np.where(diff[:, None], V.col[src], col)
        if j == 0:
            A = dict(mat=mat, frame=fr, leaf=leaf, col=col, flow=flow, wormT=o['wormT'])
        else:
            Bd = dict(mat=mat, frame=fr, leaf=leaf, col=col, flow=flow, wormT=o['wormT'])
    # normals: identical (gradient at pm)
    nn = gradAt(ev, pm, bid, S.voxel * 0.35)
    # interleave A/B like the JS push order (iA, iB per crossing)
    def inter(x, y):
        z = np.empty((2 * ne,) + x.shape[1:], x.dtype)
        z[0::2] = x
        z[1::2] = y
        return z
    V.append(pos=inter(pm, pm), nrm=inter(nn, nn), col=inter(A['col'], Bd['col']), mat=inter(A['mat'], Bd['mat']),
             frame=inter(A['frame'], Bd['frame']), key=keyOf(inter(A['mat'], Bd['mat']), inter(A['frame'], Bd['frame'])),
             leaf=inter(A['leaf'], Bd['leaf']), wormT=inter(A['wormT'], Bd['wormT']), flow=inter(A['flow'], Bd['flow']),
             weld=np.repeat(weld, 2), pco=None, pmode=None)
    res[:, 0] = base + np.arange(ne) * 2
    res[:, 1] = base + np.arange(ne) * 2 + 1
    return res


def patternCoords(V, I, frames, materials):
    """Pattern coordinates per vertex from its frame; wraps cylindrical seams by duplicating vertices."""
    matList = list(materials.values())
    computePco(V, np.arange(V.n), frames, matList)
    # cyl wrap: triangles crossing the seam get copies with u + C
    wraps = 0
    pm = V.pmode[I[:, 0]] == 1
    us = V.pco[I, 0]
    Cc = V.pco[I[:, 0], 2]
    cross = pm & ((us.max(1) - us.min(1)) > Cc * 0.5)
    tri = np.nonzero(cross)[0]
    if len(tri):
        wrapCopy = {}
        need = []
        for t in tri:
            for k in range(3):
                v = int(I[t, k])
                if V.pco[v, 0] >= 0:
                    continue
                if v not in wrapCopy:
                    wrapCopy[v] = None
                    need.append(v)
        if need:
            src = np.array(need)
            new = V.copy_rows(src)
            V.pco[new, 0] += V.pco[new, 2]
            for v, ni in zip(need, new):
                wrapCopy[v] = int(ni)
        for t in tri:
            for k in range(3):
                v = int(I[t, k])
                if v in wrapCopy and V.pco[v, 0] < 0:
                    I[t, k] = wrapCopy[v]
        wraps = len(tri)
    return O(wraps=wraps)


def computePco(V, idx, frames, matList):
    fr = V.frame[idx]
    for fid in np.unique(fr):
        f = frames[int(fid)] if 0 <= fid < len(frames) else frames[0]
        sel = idx[fr == fid]
        P = V.pos[sel]
        inv = f.inv
        T = P @ inv[:3, :3].T + inv[:3, 3]
        if f.mode == 'cyl':
            mats = V.mat[sel]
            Pscale = np.array([((matList[m].get('pattern') or {}).get('scale') or 0.1) if 0 <= m < len(matList) and matList[m].get('pattern') else 0.1 for m in mats]) if len(sel) else np.zeros(0)
            Nn = np.maximum(1, np.floor((2 * math.pi * f.radius) / Pscale + 0.5))
            Cc = Nn * Pscale
            th = np.arctan2(T[:, 0], -T[:, 2])
            if f.mirrored:
                th = -th
            V.pco[sel, 0] = (th / (2 * math.pi)) * Cc
            V.pco[sel, 1] = T[:, 1]
            V.pco[sel, 2] = Cc
            V.pmode[sel] = 1
        else:
            V.pco[sel] = T
            V.pmode[sel] = 0
