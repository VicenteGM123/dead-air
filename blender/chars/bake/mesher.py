"""Block-sparse naive surface nets over an SDF tree (port of tools/bake/mesher.mjs).
  surfaceNets(tree, voxel, bounds) -> O(positions, indices, treeAt, grid, stats)
Grid + candidate blocks (per-block pruned trees, vectorised over all blocks), per block 9^3 corner values,
sign-change cells, vertex = mean edge crossing + Newton projection (tetrahedral gradient), quads.
"""
import math
import time
import numpy as np

from ..jsutil import O
from ..sdf import Evaluator, FullEvaluator, BIG

B = 8   # cells per block edge
C = B + 1   # corners per block edge

TET = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], float)


def projectTet(ev, P, bid, e, iters=2, maxMove=math.inf):
    """Newton projection onto the surface with tetrahedral gradients (4 evals / iteration). P (N,3) -> (N,3).
    ev.dist(points, bid) evaluates the (pruned) tree."""
    P = np.array(P, float)
    P0 = P.copy()
    n = len(P)
    active = np.ones(n, bool)
    for _ in range(iters):
        ia = np.nonzero(active)[0]
        if not len(ia):
            break
        Pa = P[ia]
        Q = (Pa[None, :, :] + TET[:, None, :] * e).reshape(-1, 3)
        bq = None if bid is None else np.tile(bid[ia], 4)
        v = ev.dist(Q, bq).reshape(4, len(ia))
        g = (TET[:, None, :] * v[:, :, None]).sum(0)
        d = v.sum(0) * 0.25
        g2 = (g * g).sum(1)
        ok = g2 >= 1e-14
        with np.errstate(divide='ignore', invalid='ignore'):
            s = np.where(ok, d / g2 * (4 * e), 0)
        P[ia] = Pa - g * s[:, None]
        done = (~ok) | (np.abs(d) < e * 0.01)
        active[ia[done]] = False
    if maxMove < math.inf:
        mv = P - P0
        ml = np.sqrt((mv * mv).sum(1))
        big = ml > maxMove
        if big.any():
            P[big] = P0[big] + mv[big] * (maxMove / ml[big])[:, None]
    return P


def makeGrid(bounds, h):
    ox, oy, oz = bounds[0] - 3 * h, bounds[1] - 3 * h, bounds[2] - 3 * h
    NX = math.ceil((bounds[3] - bounds[0]) / h) + 7
    NY = math.ceil((bounds[4] - bounds[1]) / h) + 7
    NZ = math.ceil((bounds[5] - bounds[2]) / h) + 7
    return O(ox=ox, oy=oy, oz=oz, h=h, NX=NX, NY=NY, NZ=NZ, NBX=math.ceil(NX / B), NBY=math.ceil(NY / B), NBZ=math.ceil(NZ / B))


def blockBoxes(G, bxyz, n=1):
    h = G.h
    x0 = G.ox + bxyz[:, 0] * B * h
    y0 = G.oy + bxyz[:, 1] * B * h
    z0 = G.oz + bxyz[:, 2] * B * h
    return np.stack([x0 - h, y0 - h, z0 - h, x0 + (B * n + 1) * h, y0 + (B * n + 1) * h, z0 + (B * n + 1) * h], 1)


EDGES = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
CO = np.array([[c & 1, (c >> 1) & 1, (c >> 2) & 1] for c in range(8)], float)


def cellVertices(cv, gxyz, G, ev, bid):
    """cv (M,8) corner values, gxyz (M,3) global cell coords -> projected vertex positions (M,3)."""
    M = len(cv)
    S = np.zeros((M, 3))
    cnt = np.zeros(M)
    neg = cv < 0
    for a, b in EDGES:
        va, vb = cv[:, a], cv[:, b]
        x = neg[:, a] != neg[:, b]
        with np.errstate(divide='ignore', invalid='ignore'):
            t = np.where(x, va / (va - vb), 0)
        pa, pb = CO[a], CO[b]
        S += np.where(x[:, None], pa + (pb - pa) * t[:, None], 0)
        cnt += x
    none = cnt == 0
    S[none] = 0.5
    cnt[none] = 1
    h = G.h
    P = np.stack([G.ox + (gxyz[:, 0] + S[:, 0] / cnt) * h, G.oy + (gxyz[:, 1] + S[:, 1] / cnt) * h,
                  G.oz + (gxyz[:, 2] + S[:, 2] / cnt) * h], 1)
    return projectTet(ev, P, bid, h * 0.3, 2, h * 0.9)


class BlockTrees:
    """treeAt(x,y,z) of the JS mesher: the tree pruned to the point's block (or the whole tree)."""

    def __init__(self, G, ev):
        self.G = G
        self.ev = ev

    def bids(self, P):
        G = self.G
        s = B * G.h
        bx = np.clip(np.floor((P[:, 0] - G.ox) / s), 0, G.NBX - 1).astype(np.int64)
        by = np.clip(np.floor((P[:, 1] - G.oy) / s), 0, G.NBY - 1).astype(np.int64)
        bz = np.clip(np.floor((P[:, 2] - G.oz) / s), 0, G.NBZ - 1).astype(np.int64)
        return bx + G.NBX * (by + G.NBY * bz)

    def dist(self, P, bid=None):
        P = np.asarray(P, float)
        if bid is None:
            bid = self.bids(P)
        return self.ev.dist(P, bid)

    def sample(self, sampler, P, bid=None):
        P = np.asarray(P, float)
        if bid is None:
            bid = self.bids(P)
        return self.ev.sample(sampler, P, bid)


def surfaceNets(tree, voxel, bounds, margin=1.5, log=None):
    h = voxel
    t0 = time.time()
    G = makeGrid(bounds, h)
    NBX, NBY, NBZ = G.NBX, G.NBY, G.NBZ
    NB = NBX * NBY * NBZ
    bz, by, bx = np.meshgrid(np.arange(NBZ), np.arange(NBY), np.arange(NBX), indexing='ij')
    bxyz = np.stack([bx.ravel(), by.ravel(), bz.ravel()], 1)       # block id = bx + NBX*(by + NBY*bz)
    boxes = blockBoxes(G, bxyz)
    ev = Evaluator(tree, boxes, 2 * h)
    # 1) candidates: block pruned tree exists and the block center is near the surface
    R = math.sqrt(3) * B * h * 0.5
    kept = np.nonzero(ev.rootKeep)[0]
    centers = np.stack([G.ox + (bxyz[kept, 0] + 0.5) * B * h, G.oy + (bxyz[kept, 1] + 0.5) * B * h,
                        G.oz + (bxyz[kept, 2] + 0.5) * B * h], 1)
    dc = ev.dist(centers, kept)
    cand = kept[np.abs(dc) <= R * margin + h]
    tCand = time.time() - t0
    # 2) corners of the candidate blocks, sign-change cells, cell vertices
    ii = np.arange(C)
    kk, jj, iv = np.meshgrid(ii, ii, ii, indexing='ij')
    loc = np.stack([iv.ravel(), jj.ravel(), kk.ravel()], 1).astype(float)     # corner order i + C*(j + C*k)
    CORN = np.empty((len(cand), C, C, C))
    rowOf = np.full(NB, -1, np.int64)
    rowOf[cand] = np.arange(len(cand))
    vpos = []
    vcell = []
    CH = 160
    cidx = np.arange(B)
    ck, cj, ci = np.meshgrid(cidx, cidx, cidx, indexing='ij')
    cellLoc = np.stack([ci.ravel(), cj.ravel(), ck.ravel()], 1)            # cell li = i + B*(j + B*k)
    evals = 0
    for s in range(0, len(cand), CH):
        blk = cand[s:s + CH]
        nb = len(blk)
        org = np.stack([G.ox + bxyz[blk, 0] * B * h, G.oy + bxyz[blk, 1] * B * h, G.oz + bxyz[blk, 2] * B * h], 1)
        P = (org[:, None, :] + loc[None, :, :] * h).reshape(-1, 3)
        bid = np.repeat(blk, C * C * C)
        vals = ev.dist(P, bid).reshape(nb, C, C, C)        # [block, k, j, i]
        evals += len(P)
        CORN[s:s + nb] = vals
        # corner values per cell: (nb, 8, 8, 8 cells [k,j,i], 8 corners)
        cv = np.stack([vals[:, (c >> 2) & 1:(c >> 2) + B, (c >> 1) & 1:((c >> 1) & 1) + B, (c & 1):(c & 1) + B] for c in range(8)], -1)
        neg = (cv < 0).sum(-1)
        m = (neg > 0) & (neg < 8)
        qb, kc, jc, ic = np.nonzero(m)
        if not len(qb):
            continue
        cvs = cv[qb, kc, jc, ic]
        gxyz = np.stack([bxyz[blk[qb], 0] * B + ic, bxyz[blk[qb], 1] * B + jc, bxyz[blk[qb], 2] * B + kc], 1)
        V = cellVertices(cvs, gxyz, G, ev, blk[qb])
        evals += len(V) * 8
        vpos.append(V)
        vcell.append(gxyz)
    tBlocks = time.time() - t0 - tCand
    pos = np.concatenate(vpos) if vpos else np.zeros((0, 3))
    cells = np.concatenate(vcell) if vcell else np.zeros((0, 3), np.int64)
    NX, NY = G.NX, G.NY

    def lin(g):
        return g[:, 0] + (NX + 8) * (g[:, 1] + (NY + 8) * g[:, 2])
    keys = lin(cells)
    order = np.argsort(keys, kind='stable')
    skeys = keys[order]

    def lookup(g):
        k = lin(g)
        p = np.searchsorted(skeys, k)
        p = np.minimum(p, len(skeys) - 1)
        found = skeys[p] == k if len(skeys) else np.zeros(len(k), bool)
        return np.where(found, order[p], -1)

    # quads
    nC = len(cells)
    blockOf = (cells[:, 0] // B) + NBX * ((cells[:, 1] // B) + NBY * (cells[:, 2] // B))
    li, lj, lk = cells[:, 0] % B, cells[:, 1] % B, cells[:, 2] % B
    quads = []
    for a in range(3):
        u, w = (a + 1) % 3, (a + 2) % 3
        du = np.zeros(3, np.int64)
        du[u] = 1
        dw = np.zeros(3, np.int64)
        dw[w] = 1
        # corner values from the owning block's corner array
        row = rowOf[blockOf]
        v0 = CORN[row, lk, lj, li]
        v1 = CORN[row, lk + (a == 2), lj + (a == 1), li + (a == 0)]
        x = (v0 < 0) != (v1 < 0)
        ok = x & ((cells - du - dw) >= 0).all(1)
        idx = np.nonzero(ok)[0]
        quads.append((idx, cells[idx], cells[idx] - du, cells[idx] - du - dw, cells[idx] - dw, v0[idx] < 0))
    # vertex lookup incl. lazy cells
    need = np.concatenate([np.concatenate([q[2], q[3], q[4]]) for q in quads]) if quads else np.zeros((0, 3), np.int64)
    miss = lookup(need) < 0 if len(need) else np.zeros(0, bool)
    lazy = 0
    if miss.any():
        mc = np.unique(need[miss], axis=0)
        lazy = len(mc)
        mb = (mc[:, 0] // B) + NBX * ((mc[:, 1] // B) + NBY * (mc[:, 2] // B))
        # JS: pruneTree(tree, blockBox) || tree
        noTree = ~ev.rootKeep[mb]
        cv = np.zeros((len(mc), 8))
        Pc = np.stack([G.ox + (mc[:, None, 0] + CO[None, :, 0]) * h, G.oy + (mc[:, None, 1] + CO[None, :, 1]) * h,
                       G.oz + (mc[:, None, 2] + CO[None, :, 2]) * h], -1)
        LV = np.zeros((len(mc), 3))
        full = FullEvaluator(tree)
        for grp, E_ in ((np.nonzero(~noTree)[0], ev), (np.nonzero(noTree)[0], full)):
            if not len(grp):
                continue
            bb = np.repeat(mb[grp], 8)
            cv[grp] = E_.dist(Pc[grp].reshape(-1, 3), bb).reshape(-1, 8)
            LV[grp] = cellVertices(cv[grp], mc[grp], G, E_, mb[grp])
        pos = np.concatenate([pos, LV])
        cells = np.concatenate([cells, mc])
        keys = lin(cells)
        order = np.argsort(keys, kind='stable')
        skeys = keys[order]
    tris = []
    for idx, g0, g1, g2, g3, negv in quads:
        c0, c1, c2, c3 = lookup(g0), lookup(g1), lookup(g2), lookup(g3)
        q = np.where(negv[:, None], np.stack([c0, c1, c2, c3], 1), np.stack([c0, c3, c2, c1], 1))
        p = pos[q]
        d02 = ((p[:, 0] - p[:, 2]) ** 2).sum(1)
        d13 = ((p[:, 1] - p[:, 3]) ** 2).sum(1)
        s = d02 < d13
        tA = np.where(s[:, None], q[:, [0, 1, 2]], q[:, [0, 1, 3]])
        tB = np.where(s[:, None], q[:, [0, 2, 3]], q[:, [1, 2, 3]])
        tris.append(np.stack([tA, tB], 1).reshape(-1, 3))
    I = np.concatenate(tris) if tris else np.zeros((0, 3), np.int64)
    good = (I[:, 0] != I[:, 1]) & (I[:, 1] != I[:, 2]) & (I[:, 0] != I[:, 2])
    I = I[good]
    # JS: pruneTree(...) || tree for treeAt: blocks without a pruned tree use the whole tree
    empty = ~ev.rootKeep
    if empty.any():
        for key in ev.keep:
            ev.keep[key][empty] = True
        ev.rootKeep = ev.rootKeep | empty
    stats = O(ms=int((time.time() - t0) * 1000), candMs=int(tCand * 1000), blockMs=int(tBlocks * 1000), evals=evals,
              cand=len(cand), lazy=lazy, verts=len(pos), tris=len(I))
    return O(positions=pos, indices=I.astype(np.int64), treeAt=BlockTrees(G, ev), grid=G, stats=stats)
