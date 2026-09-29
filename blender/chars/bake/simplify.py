"""Seam-preserving quadric edge-collapse simplification (numpy), replacing the JS meshoptimizer
simplifyWithAttributes() call of tools/bake/bake.mjs.

Same model as meshoptimizer: vertices sharing a position are one welded vertex with several "wedges" (the
material / pattern-frame border duplicates and the cylindrical wrap copies); edges whose two faces disagree on a
wedge are SEAMS, open edges are BORDERS. Vertex kinds: manifold (one wedge, no seam/border edge) collapses onto any
neighbour; seam / border vertices only slide ALONG their seam / border (both wedges move together, so material
borders stay crisp and closed); junctions (3+ seam edges, non-manifold fans) are locked. Error = generalized
(Garland-Heckbert) quadric over position (rescaled to the unit cube) + the weighted attributes (normal, colour: the
JS weights), plus meshopt's edge quadrics along seams/borders; collapses keep the target vertex (no new vertices,
attributes are never averaged, exactly like meshopt). Passes: rank all valid collapses, take an independent set in
error order (a collapse claims its source, target and the source's one-ring: every face moves at most one vertex),
reject flips / link-condition violations, apply, until the triangle target (or the error limit) is reached.
"""
import math
import numpy as np

_TRIU = np.triu_indices(10)
_W = np.where(_TRIU[0] == _TRIU[1], 1.0, 2.0)


_DEBUG = False
_NORMALIZE = True    # meshopt: error = quadric / accumulated weight (mean squared distance, unit cube)
_DBGSTATE = []


def _pack(M):
    """(m,10,10) symmetric -> (m,55) with off-diagonals doubled (so x^T M x = sum(q * x_i * x_j))."""
    return M[:, _TRIU[0], _TRIU[1]] * _W


def _face_quadrics(X, F, area_w):
    """Generalized quadrics of faces F (m,3) over points X (n,9) -> (m,55), weighted by area_w (m,)."""
    m = len(F)
    out = np.zeros((m, 55))
    CH = 40000
    for s in range(0, m, CH):
        f = F[s:s + CH]
        p, q, r = X[f[:, 0]], X[f[:, 1]], X[f[:, 2]]
        e1 = q - p
        l1 = np.linalg.norm(e1, axis=1)
        ok = l1 > 1e-12
        e1 = e1 / np.where(ok, l1, 1)[:, None]
        rp = r - p
        e2 = rp - (rp * e1).sum(1)[:, None] * e1
        l2 = np.linalg.norm(e2, axis=1)
        ok &= l2 > 1e-12
        e2 = e2 / np.where(l2 > 1e-12, l2, 1)[:, None]
        k = len(f)
        M = np.zeros((k, 10, 10))
        A = np.eye(9)[None] - e1[:, :, None] * e1[:, None, :] - e2[:, :, None] * e2[:, None, :]
        pe1 = (p * e1).sum(1)
        pe2 = (p * e2).sum(1)
        b = pe1[:, None] * e1 + pe2[:, None] * e2 - p
        c = (p * p).sum(1) - pe1 ** 2 - pe2 ** 2
        M[:, :9, :9] = A
        M[:, :9, 9] = b
        M[:, 9, :9] = b
        M[:, 9, 9] = c
        w = np.where(ok, area_w[s:s + CH], 0)
        out[s:s + k] = _pack(M) * w[:, None]
    return out


def _plane_quadric(n, d, w):
    """Plane (n·x + d = 0) quadric on the position dims, packed (m,55)."""
    m = len(n)
    M = np.zeros((m, 10, 10))
    M[:, :3, :3] = n[:, :, None] * n[:, None, :]
    M[:, :3, 9] = n * d[:, None]
    M[:, 9, :3] = n * d[:, None]
    M[:, 9, 9] = d * d
    return _pack(M) * w[:, None]


def simplify(indices, positions, attrs, weights, target_index_count, target_error=0.05, log=None):
    """indices (m,3) int, positions (n,3), attrs (n,k), weights (k,) -> (new indices (m',3) into the ORIGINAL vertex
    array, error). Vertices with identical positions are welded wedges (seams)."""
    I = np.asarray(indices, np.int64).reshape(-1, 3)
    P = np.asarray(positions, float)
    n = len(P)
    target_tris = max(0, target_index_count // 3)
    if len(I) <= target_tris:
        return I.copy(), 0.0
    # --- welding by exact position
    _, W2P = np.unique(P.astype(np.float32).view([('', np.float32)] * 3).reshape(-1), return_inverse=True)
    W2P = W2P.reshape(-1).astype(np.int64)
    nwv = W2P.max() + 1
    Pw = np.zeros((nwv, 3))
    Pw[W2P] = P
    # rescale to the unit cube (meshopt rescalePositions)
    mn = Pw.min(0)
    ext = float((Pw.max(0) - mn).max()) or 1.0
    Ps = (Pw - mn) / ext
    X = np.concatenate([Ps[W2P], np.asarray(attrs, float) * np.asarray(weights, float)[None, :]], 1)   # per wedge
    # --- initial quadrics per wedge (face quadrics)
    FW = W2P[I]
    cr = np.cross(Ps[FW[:, 1]] - Ps[FW[:, 0]], Ps[FW[:, 2]] - Ps[FW[:, 0]])
    area = np.linalg.norm(cr, axis=1) * 0.5
    Qf = _face_quadrics(X, I, area)
    Q = np.zeros((n, 55))
    for c in range(3):
        for j in range(55):
            Q[:, j] += np.bincount(I[:, c], weights=Qf[:, j], minlength=n)
    # quadric weights (meshopt normalizes the quadric error by the accumulated weight: errors are mean squared
    # distances in the unit cube, independent of the local triangle size)
    Wq = np.zeros(n)
    for c in range(3):
        Wq += np.bincount(I[:, c], weights=area, minlength=n)
    F = I.copy()                   # faces as wedge ids
    alive = np.ones(n, bool)
    result_error = 0.0
    error_limit = target_error * target_error
    edges_added = False
    passes = 0
    while len(F) > target_tris:
        passes += 1
        FW = W2P[F]
        m = len(F)
        # ---------------- topology: half-edges (a -> b) with wedge pairs
        ha = FW.reshape(-1)
        hb = FW[:, [1, 2, 0]].reshape(-1)
        wa = F.reshape(-1)
        wb = F[:, [1, 2, 0]].reshape(-1)
        hf = np.repeat(np.arange(m), 3)
        key = ha * nwv + hb
        rkey = hb * nwv + ha
        order = np.argsort(key, kind='stable')
        sk = key[order]
        # multiplicity of each directed edge
        uk, first, cnt = np.unique(sk, return_index=True, return_counts=True)
        dup_dir = np.zeros(len(key), bool)
        dup_dir[order] = np.repeat(cnt > 1, cnt)
        # opposite half-edge lookup
        pos_r = np.searchsorted(sk, rkey)
        pos_r = np.minimum(pos_r, len(sk) - 1)
        has_opp = sk[pos_r] == rkey
        opp = np.where(has_opp, order[pos_r], -1)
        # seam: opposite exists but wedges differ at either endpoint
        oppw_a = np.where(has_opp, wb[np.maximum(opp, 0)], -1)    # opposite half-edge (b -> a): its wb is at a
        oppw_b = np.where(has_opp, wa[np.maximum(opp, 0)], -1)
        border = ~has_opp
        seam = has_opp & ((oppw_a != wa) | (oppw_b != wb))
        # vertex kinds (0 manifold, 1 border, 2 seam, 3 locked)
        nb_border = np.bincount(ha[border], minlength=nwv) + np.bincount(hb[border], minlength=nwv)
        nb_seam_dir = np.bincount(ha[seam], minlength=nwv)          # each seam edge appears as 2 half-edges
        bad = np.zeros(nwv, bool)
        bad[ha[dup_dir]] = True
        bad[hb[dup_dir]] = True
        kind = np.zeros(nwv, np.int8)
        kind[nb_border > 0] = 1
        kind[nb_seam_dir > 0] = 2
        kind[(nb_border > 0) & (nb_seam_dir > 0)] = 3
        kind[(kind == 1) & (nb_border != 2)] = 3
        kind[(kind == 2) & (nb_seam_dir != 2)] = 3
        # manifold fan check: number of distinct wedges at the vertex must be 1 (manifold/border) or 2 (seam)
        vw = np.unique(ha * np.int64(n) + wa)
        nwedge = np.bincount(vw // n, minlength=nwv)
        kind[(kind == 0) & (nwedge != 1)] = 3
        kind[(kind == 1) & (nwedge != 1)] = 3
        kind[(kind == 2) & (nwedge != 2)] = 3
        kind[bad] = 3
        if not edges_added:
            # meshopt fillEdgeQuadrics: planes perpendicular to the face through seam / border edges
            sel = np.nonzero(seam | border)[0]
            if len(sel):
                f = hf[sel]
                pa, pb = Ps[ha[sel]], Ps[hb[sel]]
                fn = np.cross(Ps[FW[f, 1]] - Ps[FW[f, 0]], Ps[FW[f, 2]] - Ps[FW[f, 0]])
                e = pb - pa
                ln = np.linalg.norm(e, axis=1)
                perp = np.cross(e, fn)
                pl = np.linalg.norm(perp, axis=1)
                ok = (pl > 1e-18) & (ln > 0)
                perp = perp / np.where(ok, pl, 1)[:, None]
                d = -(perp * pa).sum(1)
                wgt = np.where(border[sel], 10.0, 0.5) * ln * np.where(ok, 1, 0)
                Qe = _plane_quadric(perp, d, wgt)
                for arr in (wa[sel], wb[sel]):
                    for j in range(55):
                        Q[:, j] += np.bincount(arr, weights=Qe[:, j], minlength=n)
                    Wq += np.bincount(arr, weights=wgt, minlength=n)
            edges_added = True
        # ---------------- candidates: every half-edge a -> b gives the collapse a -> b
        ka, kb = kind[ha], kind[hb]
        valid = np.zeros(len(ha), bool)
        valid |= ka == 0
        valid |= (ka == 1) & border & ((kb == 1) | (kb == 3))
        valid |= (ka == 2) & seam & ((kb == 2) | (kb == 3))
        # border vertices also collapse along the incoming border half-edge (b -> a direction): use the reverse
        # half-edge candidate a -> b from the face that holds b -> a
        rev_valid = (kind[hb] == 1) & border & ((kind[ha] == 1) | (kind[ha] == 3))
        cu = np.concatenate([ha[valid], hb[rev_valid]])
        cv = np.concatenate([hb[valid], ha[rev_valid]])
        ch = np.concatenate(np.nonzero(valid) + np.nonzero(rev_valid))
        crev = np.concatenate([np.zeros(valid.sum(), bool), np.ones(rev_valid.sum(), bool)])
        if not len(cu):
            break
        # wedge mapping per candidate from its face(s): source wedge at u -> target wedge at v
        su1 = np.where(crev, wb[ch], wa[ch])
        tv1 = np.where(crev, wa[ch], wb[ch])
        o = opp[ch]
        hasO = o >= 0
        su2 = np.where(hasO, np.where(crev, wa[np.maximum(o, 0)], wb[np.maximum(o, 0)]), -1)
        tv2 = np.where(hasO, np.where(crev, wb[np.maximum(o, 0)], wa[np.maximum(o, 0)]), -1)
        # opposite half-edge is (b -> a): its wb is at a(=u when not rev) and wa is at b(=v)
        su2 = np.where(hasO & ~crev, wb[np.maximum(o, 0)], su2)
        tv2 = np.where(hasO & ~crev, wa[np.maximum(o, 0)], tv2)
        # error: sum over distinct source wedges of Q_w evaluated at (pos(v), attr(target wedge))
        pv = Ps[cv]

        def qerr(src, tgt, pvv):
            out = np.empty(len(src))
            CH = 100000
            for s0 in range(0, len(src), CH):
                s1 = min(len(src), s0 + CH)
                x = np.concatenate([pvv[s0:s1], X[tgt[s0:s1], 3:], np.ones((s1 - s0, 1))], 1)
                out[s0:s1] = np.einsum('ij,ij->i', Q[src[s0:s1]], x[:, _TRIU[0]] * x[:, _TRIU[1]])
            return out
        err = qerr(su1, tv1, pv)
        wsum = Wq[su1].copy()
        two = hasO & (su2 != su1)
        if two.any():
            err[two] += qerr(su2[two], tv2[two], pv[two])
            wsum[two] += Wq[su2[two]]
        err = np.maximum(err, 0)
        if _NORMALIZE:
            err = err / np.maximum(wsum, 1e-30)
        # ---------------- validity on the pre-pass mesh: error limit, link condition, flips. The claims below keep
        # every accepted collapse's one-ring untouched by the others of the pass, so these tests stay exact; testing
        # them up front (instead of after the greedy selection) lets the selection skip invalid collapses without
        # blocking their neighbours, like meshopt's sequential loop, and the other direction of an edge gets its
        # chance when the cheaper one flips.
        uk2 = np.unique(np.concatenate([ha * nwv + hb, hb * nwv + ha]))
        und = np.stack([uk2 // nwv, uk2 % nwv], 1)
        nstart = np.searchsorted(und[:, 0], np.arange(nwv + 1))
        fv = FW.reshape(-1)
        forder = np.argsort(fv, kind='stable')
        fstart = np.searchsorted(fv[forder], np.arange(nwv + 1))
        idx = np.nonzero(err <= error_limit)[0]
        n_lim = len(idx)
        deg = nstart[cu[idx] + 1] - nstart[cu[idx]]
        rep = np.repeat(np.arange(len(idx)), deg)
        off = np.arange(len(rep)) - np.repeat(np.cumsum(deg) - deg, deg)
        nbr = und[np.repeat(nstart[cu[idx]], deg) + off, 1]
        vk = np.repeat(cv[idx], deg) * nwv + nbr
        pk = np.minimum(np.searchsorted(uk2, vk), len(uk2) - 1)
        common = np.bincount(rep[uk2[pk] == vk], minlength=len(idx))
        idx = idx[common == np.where(kind[cu[idx]] == 1, 1, 2)]
        n_link = len(idx)
        fl = np.ones(len(idx), bool)
        CHF = 200000
        for s0 in range(0, len(idx), CHF):
            ii = idx[s0:s0 + CHF]
            fl[s0:s0 + CHF] = _no_flip(cu[ii], cv[ii], FW, Ps, forder, fstart)
        if _DEBUG:
            _DBGSTATE.append(dict(cu=cu.copy(), cv=cv.copy(), err=err.copy(), n_lim=n_lim, link_idx=idx.copy(), fl=fl.copy(), kind=kind.copy(), Ps=Ps, Q=Q, X=X))
        idx = idx[fl]
        if not len(idx):
            break
        cu, cv, err, su1, tv1, su2, tv2, two = cu[idx], cv[idx], err[idx], su1[idx], tv1[idx], su2[idx], tv2[idx], two[idx]
        # keep the cheapest valid direction per undirected edge
        ek = np.minimum(cu, cv) * nwv + np.maximum(cu, cv)
        o2 = np.lexsort((err, ek))
        ek_s = ek[o2]
        firsts = np.ones(len(o2), bool)
        firsts[1:] = ek_s[1:] != ek_s[:-1]
        sel = o2[firsts]
        cu, cv, err, su1, tv1, su2, tv2, two = cu[sel], cv[sel], err[sel], su1[sel], tv1[sel], su2[sel], tv2[sel], two[sel]
        # rank by error; ties (flat regions all collapse at ~0 error) broken by a hash instead of the vertex order,
        # so tied candidates are not chained one behind the other in the parallel greedy selection below
        hk = ((np.minimum(cu, cv) * np.int64(2654435761) + np.maximum(cu, cv) * np.int64(40503)) & 0xFFFFFFF)
        rank = np.lexsort((hk, err))
        cu, cv, err, su1, tv1, su2, tv2, two = cu[rank], cv[rank], err[rank], su1[rank], tv1[rank], su2[rank], tv2[rank], two[rank]
        tri_goal = len(F) - target_tris
        # error goal per pass (meshopt: 1.5x the error at the expected collapse count)
        eg = tri_goal // 2
        err_goal = 1.5 * err[eg] if eg < len(err) else math.inf
        nc = len(cu)
        cidx = np.arange(nc)
        # claims: u, v EXCLUSIVE (moved / receiving); N(u) SHARED (read by the flip + link tests). Two collapses
        # conflict when one's exclusive vertex is claimed (either way) by the other: then no face moves two vertices
        # and the neighbourhoods the link / flip tests read are untouched by the other collapses of the pass.
        deg = nstart[cu + 1] - nstart[cu]
        rep = np.repeat(cidx, deg)
        off = np.arange(len(rep)) - np.repeat(np.cumsum(deg) - deg, deg)
        nbr = und[np.repeat(nstart[cu], deg) + off, 1]
        claim_c = np.concatenate([cidx, cidx, rep])
        claim_v = np.concatenate([cu, cv, nbr])
        claim_x = np.concatenate([np.ones(2 * nc, bool), np.zeros(len(rep), bool)])
        status = np.zeros(nc, np.int8)          # 0 pending, 1 accepted, -1 rejected
        so_c = np.lexsort((claim_c, claim_v))
        so_v, so_cc, so_x = claim_v[so_c], claim_c[so_c], claim_x[so_c]
        accepted_tris = 0
        _dbg = [n_lim, n_link, nc, 0, 0, 0]
        for rnd in range(12):
            pend = status == 0
            if not pend.any():
                break
            # parallel greedy: accepted when no pending candidate of lower rank conflicts with it
            live = pend[claim_c]
            lv, lc, lx = claim_v[live], claim_c[live], claim_x[live]
            BIGI = np.iinfo(np.int64).max
            exB = np.full(nwv, BIGI)
            allB = np.full(nwv, BIGI)
            # per-vertex minimum rank (claims pre-sorted by (vertex, rank): first live entry of each vertex group)
            lo = live[so_c]
            sv, sc, sx = so_v[lo], so_cc[lo], so_x[lo]
            if len(sv):
                f = np.ones(len(sv), bool)
                f[1:] = sv[1:] != sv[:-1]
                allB[sv[f]] = sc[f]
                ev_, ec_ = sv[sx], sc[sx]
                if len(ev_):
                    f = np.ones(len(ev_), bool)
                    f[1:] = ev_[1:] != ev_[:-1]
                    exB[ev_[f]] = ec_[f]
            bad = np.where(lx, allB[lv] < lc, exB[lv] < lc)
            fails = np.bincount(lc, weights=bad.astype(float), minlength=nc)
            won = pend & (fails == 0)
            wi = np.nonzero(won)[0]
            if not len(wi):
                break
            # budget / error goal in rank order
            wtri = np.where(kind[cu[cidx[wi]]] == 1, 1, 2)
            cum = accepted_tris + np.cumsum(wtri)
            e_ok = ~((err[cidx[wi]] > err_goal) & (err[cidx[wi]] > result_error) & (cum > tri_goal / 6))
            within = (cum - wtri < tri_goal) & e_ok
            stop = not within.all()
            _dbg[3] += len(wi); _dbg[4] += int(within.sum())
            wi = wi[within]
            status[wi] = 1
            _dbg[5] += len(wi)
            accepted_tris += int(np.where(kind[cu[cidx[wi]]] == 1, 1, 2).sum())
            # candidates conflicting with an accepted one are out for this pass
            acc = status == 1
            ac = acc[claim_c]
            tEx = np.zeros(nwv, bool)
            tAll = np.zeros(nwv, bool)
            tEx[claim_v[ac & claim_x]] = True
            tAll[claim_v[ac]] = True
            hit = np.where(claim_x, tAll[claim_v], tEx[claim_v])
            conflict = np.bincount(claim_c, weights=hit.astype(float), minlength=nc) > 0
            status[(status == 0) & conflict] = -1
            if stop:
                break
        acc = np.nonzero(status == 1)[0]
        if not len(acc):
            break
        ai = cidx[acc]
        result_error = max(result_error, float(err[ai].max()))
        # ---------------- apply: welded u -> v, wedges mapped per side, quadrics accumulated
        wmap = np.arange(n)
        wmap[su1[ai]] = tv1[ai]
        t2 = ai[two[ai]]
        wmap[su2[t2]] = tv2[t2]
        srcs = np.concatenate([su1[ai], su2[t2]])
        tgts = np.concatenate([tv1[ai], tv2[t2]])
        Wq[tgts] += Wq[srcs]
        Q[tgts] += Q[srcs]      # targets are unique within a pass (every target vertex is claimed once)
        F = wmap[F]
        FW = W2P[F]
        keep = (FW[:, 0] != FW[:, 1]) & (FW[:, 1] != FW[:, 2]) & (FW[:, 0] != FW[:, 2])
        F = F[keep]
        if log:
            log('    simplify pass %d: %d collapses -> %d tris (err %.5f)' % (passes, len(ai), len(F), result_error)
                + ((' dbg lim %d link %d valid %d won %d within %d acc %d' % tuple(_dbg)) if _DEBUG else ''))
    return F, math.sqrt(result_error)


def _no_flip(u, v, FW, Ps, forder, fstart):
    """For collapses u -> v: True where no face around u (not containing v) flips or degenerates."""
    k = len(u)
    if not k:
        return np.zeros(0, bool)
    cnt = fstart[u + 1] - fstart[u]
    rep = np.repeat(np.arange(k), cnt)
    off = np.arange(len(rep)) - np.repeat(np.cumsum(cnt) - cnt, cnt)
    fi = forder[np.repeat(fstart[u], cnt) + off] // 3
    f = FW[fi]
    uu = u[rep]
    vv = v[rep]
    hasv = (f == vv[:, None]).any(1)
    p = Ps[f]
    n0 = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    q = p.copy()
    m = f == uu[:, None]
    q[m] = Ps[np.repeat(vv, 3).reshape(-1, 3)[m]]
    n1 = np.cross(q[:, 1] - q[:, 0], q[:, 2] - q[:, 0])
    dot = (n0 * n1).sum(1)
    l0 = np.linalg.norm(n0, axis=1)
    l1 = np.linalg.norm(n1, axis=1)
    flip = ~hasv & ((dot <= 0.05 * l0 * l1) | (l1 < 1e-14))
    bad = np.bincount(rep, weights=flip.astype(float), minlength=k) > 0
    return ~bad
