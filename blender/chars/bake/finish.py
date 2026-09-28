"""Final per-vertex shading data on the simplified mesh (port of tools/bake/finish.mjs): SDF-gradient normals, baked
ambient occlusion (normal-direction samples + cone-traced hemisphere visibility), cavity/convexity (SDF Laplacian),
triplanar weights, sparse morph targets (projection onto expression variants) and stitch-line projection."""
import math
import numpy as np

from ..jsutil import O
from ..sdf import CellEvaluator
from .attrib import projectToSurface

import sys as _sys
import os as _os
_BL = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..', '..'))
if _BL not in _sys.path:
    _sys.path.insert(0, _BL)
from dalib import three_geo as THREE   # noqa: E402


def makeRegionTrees(tree, cell=0.08, margin=0.22):
    return CellEvaluator(tree, cell, margin)


def gradN(ev, P, bid, e):
    n = len(P)
    off = np.array([[e, 0, 0], [-e, 0, 0], [0, e, 0], [0, -e, 0], [0, 0, e], [0, 0, -e]])
    Q = (P[None, :, :] + off[:, None, :]).reshape(-1, 3)
    f = ev.dist(Q, np.tile(bid, 6)).reshape(6, n)
    g = np.stack([f[0] - f[1], f[2] - f[3], f[4] - f[5]], 1)
    ln = np.sqrt((g * g).sum(1))
    ln[ln == 0] = 1
    return g / ln[:, None]


# Fixed hemisphere directions (cosine-ish distribution) in a local frame (z = normal).
def _hemi():
    dirs = []
    N = 10
    for i in range(N):
        u = (i + 0.5) / N
        phi = i * 2.399963
        r = math.sqrt(u) * 0.92
        dirs.append([math.cos(phi) * r, math.sin(phi) * r, math.sqrt(1 - r * r)])
    return np.array(dirs)


HEMI = _hemi()


def shadeVertices(pos, treeAt, opts=None):
    """normals, AO, cavity at the final vertices. treeAt: CellEvaluator (region trees)."""
    opts = O(opts or {})
    n = len(pos)
    aoScale = opts.aoStrength if opts.aoStrength is not None else 1
    reach = opts.aoReach if opts.aoReach is not None else 0.16
    steps = [0.014, 0.038, 0.08, reach]
    P = np.asarray(pos, float)
    bid = treeAt.bids(P)
    g = gradN(treeAt, P, bid, 0.0012)
    # 1) normal-direction occlusion (IQ style)
    occ = np.zeros(n)
    w = 1.0
    for i in range(1, 6):
        h = 0.008 * i * i * 0.6 + 0.004
        d = treeAt.dist(P + g * h, bid)
        occ += np.maximum(0, h - d) * w
        w *= 0.7
    aoN = np.maximum(0, 1 - occ * 7)
    # 2) hemisphere cone visibility
    t = np.where((np.abs(g[:, 1]) < 0.9)[:, None], np.array([0, 1.0, 0]), np.array([1.0, 0, 0]))
    tv = np.cross(t, g)
    tv /= np.linalg.norm(tv, axis=1)[:, None]
    bv = np.cross(g, tv)
    rot = ((np.arange(n) * 0.618034) % 1) * math.pi * 2
    cr, sr = np.cos(rot), np.sin(rot)
    vis = np.zeros(n)
    wsum = 0.0
    base = P + g * 0.003
    for hx0, hy0, hz in HEMI:
        hx = hx0 * cr - hy0 * sr
        hy = hx0 * sr + hy0 * cr
        D = tv * hx[:, None] + bv * hy[:, None] + g * hz
        Q = np.concatenate([base + D * s for s in steps])
        dd = treeAt.dist(Q, np.tile(bid, len(steps))).reshape(len(steps), n)
        c = np.clip(dd / (np.array(steps)[:, None] * 0.55), 0, 1)
        vmin = np.minimum(1, c.min(0))
        vis += vmin * hz
        wsum += hz
    aoH = vis / wsum
    ao = np.clip(aoN * (0.45 + 0.55 * aoH), 0, 1) ** aoScale
    # 3) cavity (Laplacian at a small scale): <0 concave crease, >0 convex edge
    e = opts.cavScale if opts.cavScale is not None else 0.005
    off = np.array([[0, 0, 0], [e, 0, 0], [-e, 0, 0], [0, e, 0], [0, -e, 0], [0, 0, e], [0, 0, -e]])
    Q = (P[None, :, :] + off[:, None, :]).reshape(-1, 3)
    f = treeAt.dist(Q, np.tile(bid, 7)).reshape(7, n)
    lap = (f[1:].sum(0) - 6 * f[0]) / (e * e)
    cav = np.clip(lap * (opts.cavGain if opts.cavGain is not None else 0.01), -1, 1)
    return O(nrm=g, ao=ao, cav=cav)


def triWeights(nrm, frameIds, frames):
    """Triplanar weights in each vertex's pattern frame (tri mode); packed 0..255 (u8, 4 per vertex, w = 0)."""
    n = len(nrm)
    out = np.zeros((n, 4), np.uint8)
    mats = [f.inv[:3, :3] for f in frames]
    for fid in np.unique(frameIds):
        sel = np.nonzero(frameIds == fid)[0]
        M = mats[int(fid)] if 0 <= fid < len(mats) else mats[0]
        v = nrm[sel] @ M.T
        ln = np.linalg.norm(v, axis=1)
        ln[ln == 0] = 1
        v = v / ln[:, None]
        wv = np.abs(v) ** 4
        s = wv.sum(1)
        s[s == 0] = 1
        out[sel, :3] = np.floor(wv / s[:, None] * 255 + 0.5).astype(np.uint8)
    return out


def morphTarget(pos, nrm, variantTreeAt, mask, maxMove=0.03, baseTreeAt=None, col=None, sampler=None):
    """Sparse morph target: base vertices (mask) projected onto the variant surface; with col (linear base colours)
    + sampler, the variant's colour at the moved position gives colour deltas dc."""
    idx = np.nonzero(mask)[0]
    P = pos[idx]
    bid = variantTreeAt.bids(P)
    d = variantTreeAt.dist(P, bid)
    same = np.abs(d) < 1e-4
    if baseTreeAt is not None:
        db = baseTreeAt.dist(P)
        same |= np.abs(d - db) < 1e-4
    mv = np.zeros_like(P)
    todo = np.nonzero(~same)[0]
    if len(todo):
        pp = projectToSurface(variantTreeAt, P[todo], bid[todo], 5, 0.001)
        m = pp - P[todo]
        ml = np.sqrt((m * m).sum(1))
        m[ml < 1e-4] = 0
        big = ml > maxMove
        m[big] *= (maxMove / ml[big])[:, None]
        mv[todo] = m
    moved = (mv != 0).any(1)
    dc = np.zeros_like(P)
    if col is not None and sampler is not None and moved.any():
        j = np.nonzero(moved)[0]
        Q = P[j] + mv[j]
        o = variantTreeAt.sample(sampler, Q)
        c = np.stack([o['r'], o['g'], o['b']], 1) - col[idx[j]]
        small = np.abs(c).sum(1) < 0.012
        c[small] = 0
        dc[j] = c
    keep = moved | (dc != 0).any(1)
    k = np.nonzero(keep)[0]
    g = nrm[idx[k]].copy()
    mk = moved[k]
    if mk.any():
        Q = P[k[mk]] + mv[k[mk]]
        g[mk] = gradN(variantTreeAt, Q, variantTreeAt.bids(Q), 0.0012)
    return O(ids=idx[k], dp=mv[k], dn=g - nrm[idx[k]], dc=dc[k])


def projectStitches(stitches, tree_ev):
    """Stitch polylines: resample, project onto the surface, emit segments. tree_ev: evaluator of the full tree."""
    segs = []
    stroke = 0
    for s in stitches:
        stroke += 1
        pts = [THREE.Vector3(*p) for p in s.pts]
        if len(pts) > 2 and s.smooth:
            curve = THREE.CatmullRomCurve3(pts, False, 'centripetal')
        else:
            curve = THREE.CurvePath()
            for i in range(len(pts) - 1):
                curve.add(THREE.LineCurve3(pts[i], pts[i + 1]))
        ln = curve.getLength()
        N = max(2, math.ceil(ln / s.segLen))
        raw = []
        for i in range(N + 1):
            p = curve.getPointAt(i / N)
            raw.append([p.x, p.y, p.z])
        P = projectToSurface(tree_ev, np.array(raw), None, 6, 0.001)
        acc = 0.0
        for i in range(N):
            a, b = P[i], P[i + 1]
            l = float(np.linalg.norm(b - a))
            segs.append(O(a=[float(v) for v in a], b=[float(v) for v in b], t0=acc, width=s.width, dash=s.dash, duty=s.duty,
                          color=s.color, mats=s.mats, stroke=stroke))
            acc += l
    return segs


def stitchChunks(segs, mx=16):
    """Group consecutive segments of a stroke into chunks (<= 16) with bounding spheres for the shader."""
    out = []
    i = 0
    while i < len(segs):
        first = i
        st = segs[i].stroke
        while i < len(segs) and segs[i].stroke == st and i - first < mx:
            i += 1
        pts = []
        for k in range(first, i):
            pts.append(segs[k].a)
            pts.append(segs[k].b)
        c = [sum(p[q] for p in pts) / len(pts) for q in range(3)]
        r = 0
        for p in pts:
            r = max(r, math.hypot(p[0] - c[0], p[1] - c[1], p[2] - c[2]))
        out.append([*c, r + segs[first].width * 3 + 0.002, first, i - first])
    return out
