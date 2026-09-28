"""Skin weights (port of tools/bake/skin.mjs): nearest allowed bone segment (from the dominant primitive's binding) +
joint blending (parent at the bone's origin, children near their origins, gated by limb radius) + diffusion smoothing
on the position-welded surface graph. Output: top-4 bones per vertex (u8 weights summing to 255)."""
import numpy as np

from ..jsutil import O
from ..sdf import CHAINS, LEAVES


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def segDist(P, s):
    a = np.array(s.a)
    b = np.array(s.b)
    pa = P - a
    ba = b - a
    den = float(ba @ ba) or 1e-12
    h = np.clip((pa @ ba) / den, 0, 1)
    d = pa - ba * h[:, None]
    return np.sqrt((d * d).sum(1))


def computeSkin(V, I, R, segments, opts=None):
    opts = O(opts or {})
    bones = R.bones
    nb = len(bones)
    bi = {b: i for i, b in enumerate(bones)}
    children = [[] for _ in bones]
    for b in bones:
        if R.parents[b]:
            children[bi[R.parents[b]]].append(bi[b])
    seg = [segments[b] for b in bones]
    axis = []
    for s in seg:
        d = np.array(s.b) - np.array(s.a)
        ln = np.linalg.norm(d) or 1
        axis.append(d / ln)
    skin = [R.skin.get(b) or O(blend=0.05, gate=0.1) for b in bones]
    allowedCache = {}

    def allowed(leaf):
        b = leaf.bone if leaf is not None else 'auto'
        key = ','.join(b) if isinstance(b, (list, tuple)) else str(b)
        a = allowedCache.get(key)
        if a is not None:
            return a
        if b is None or b == 'auto':
            names = bones
        elif isinstance(b, (list, tuple)):
            names = b
        elif R.humanoid and b in CHAINS:
            names = CHAINS[b]
        elif opts.chains and b in opts.chains:
            names = opts.chains[b]
        else:
            names = [b]
        a = [bi[n] for n in names if n in bi]
        if not a:
            a = list(range(nb))
        allowedCache[key] = a
        return a

    # Welded representatives
    n = V.n
    weld = V.weld
    rep = np.full(n, -1, np.int64)
    reps = []
    # first vertex (in index order) of each weld id is the representative
    uw, firstIdx = np.unique(weld, return_index=True)
    order = np.argsort(firstIdx)
    reps = firstIdx[order]
    rep[weld[reps]] = np.arange(len(reps))
    nw = len(reps)
    wid = rep[weld]

    W = np.zeros((nw, nb))
    rigid = np.zeros(nw, bool)
    P = V.pos[reps]
    leafU = V.leaf[reps]
    # group reps by allowed set
    groups = {}
    ul, inv = np.unique(leafU, return_inverse=True)
    for li, u in enumerate(ul):
        L = LEAVES.get(int(u)) if u >= 0 else None
        sel = np.nonzero(inv == li)[0]
        al = tuple(allowed(L))
        g = groups.setdefault(al, [[], []])
        g[0].append(sel)
        g[1].append(np.full(len(sel), bool(L.rigid) if L is not None else False))
    best = np.zeros(nw, np.int64)
    for al, (sels, rg) in groups.items():
        sel = np.concatenate(sels)
        rgd = np.concatenate(rg)
        D = np.stack([segDist(P[sel], seg[j]) for j in al], 1)
        bj = np.argmin(D, axis=1)          # first minimum like the JS strict '<'
        best[sel] = np.array(al)[bj]
        rigid[sel] = rgd
    # rigid primitives: all weight on the nearest bone
    rr = np.nonzero(rigid)[0]
    W[rr, best[rr]] = 1
    for j in range(nb):
        sel = np.nonzero((best == j) & ~rigid)[0]
        if not len(sel):
            continue
        p = P[sel]
        wh = np.ones(len(sel))
        # (1) parent blend at the bone origin
        par = R.parents[bones[j]]
        sk = skin[j]
        if par and sk.blend > 0:
            a = np.array(seg[j].a)
            s = (p - a) @ axis[j]
            t = smoothstep(-sk.blend, sk.blend, s)
            W[sel, bi[par]] += 1 - t
            wh = t
        # (2) children blend near their origins (gated by the limb radius)
        for c in children[j]:
            kc = skin[c]
            if not (kc.blend > 0):
                continue
            a = np.array(seg[c].a)
            ax = axis[c]
            dv = p - a
            s = dv @ ax
            radv = dv - s[:, None] * ax
            rad = np.sqrt((radv * radv).sum(1))
            g = 1 - smoothstep(kc.gate * 0.75, kc.gate * 1.35, rad)
            tc = smoothstep(-kc.blend, kc.blend, s) * g
            ok = (s >= -kc.blend) & (tc > 0)
            tc = np.where(ok, tc, 0)
            W[sel, c] += wh * tc
            wh = wh * (1 - tc)
        W[sel, j] += wh

    # Welded adjacency (directed edge list incl. duplicates, like the JS CSR)
    a = wid[I]
    src = np.concatenate([a[:, 0], a[:, 1], a[:, 2], a[:, 1], a[:, 2], a[:, 0]])
    dst = np.concatenate([a[:, 1], a[:, 2], a[:, 0], a[:, 0], a[:, 1], a[:, 2]])
    keep = src != dst
    src, dst = src[keep], dst[keep]
    o = np.argsort(src, kind='stable')
    src, dst = src[o], dst[o]
    deg = np.bincount(src, minlength=nw)
    start = np.concatenate([[0], np.cumsum(deg)])
    has = deg > 0
    fixed = rigid | ~has
    iters = opts.smooth if opts.smooth is not None else 8
    lam = 0.5
    A = W
    starts = start[:-1][has]
    for _ in range(int(iters)):
        S = np.zeros_like(A)
        S[has] = np.add.reduceat(A[dst], starts, axis=0)
        mean = S / np.maximum(deg, 1)[:, None]
        Bf = A * (1 - lam) + mean * lam
        Bf[fixed] = A[fixed]
        A = Bf

    # Top-4 per welded vertex, then expand to all vertices
    if nb < 4:
        A = np.concatenate([A, np.full((nw, 4 - nb), -1.0)], 1)
    order = np.argsort(-A, axis=1, kind='stable')[:, :4]
    tw = np.take_along_axis(A, order, 1)
    order = np.where(order >= nb, 0, order)
    tw = np.where(tw < 0.004, 0, tw)
    s = tw.sum(1, keepdims=True)
    s[s == 0] = 1
    q = np.floor(tw / s * 255 + 0.5)
    q[:, 0] += 255 - q.sum(1)     # rounding remainder on the dominant bone
    repI = order.astype(np.uint8)
    repW = q.astype(np.int64)
    return O(skinIndex=repI[wid], skinWeight=np.clip(repW[wid], 0, 255).astype(np.uint8), welded=nw)
