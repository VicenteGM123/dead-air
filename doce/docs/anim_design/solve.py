"""Damped least squares for the sword arm: joint angles (az, e, r, el, uln, ext, tw in degrees) that put the grip and the
blade tip at world targets (rig frame) given the body pose at that time. numpy only."""
import numpy as np
from smodel import *

CLEAR_ON = True
CLEAR_MARGIN = 0.008
LIM = {"az": (-170, 170), "e": (0, 175), "r": (-70, 100), "el": (14, 140), "uln": (28, 62), "ext": (-35, 42), "tw": (-120, 120)}
NAMES = ["az", "e", "r", "el", "uln", "ext", "tw"]


# the torso as the clip checker sees it, in chest space (origin P_CHEST): (a, b, r)
TORSO_CAPS = []
for _sx in (-1.0, 1.0):
    TORSO_CAPS.append((np.array([0.085 * _sx, -0.10, 0.0]), np.array([0.10 * _sx, 0.13, 0.0]), 0.135))
    TORSO_CAPS.append((np.array([0.06 * _sx, -0.27, 0.0]), np.array([0.07 * _sx, -0.13, 0.0]), 0.12))
TORSO_CAPS.append((np.array([0.0, -0.10, -0.01]), np.array([0.0, 0.12, -0.01]), 0.155))
TORSO_CAPS.append((np.array([-0.07, -0.40, 0.0]), np.array([0.07, -0.40, 0.0]), 0.17))


def _seg_dist(p, a, b):
    ab = b - a
    t = min(max(np.dot(p - a, ab) / np.dot(ab, ab), 0.0), 1.0)
    return float(np.linalg.norm(p - (a + ab * t)))


def torso_clear(p):
    """distance from a point (chest space) to the nearest torso surface (negative inside)"""
    return min(_seg_dist(p, a, b) - r for (a, b, r) in TORSO_CAPS)


def arm_state(x, body):
    """grip, tip, flat normal, elbow, wrist in rig space for joint vector x (deg) and body (pb, tb, po, co)"""
    az, e, r, el, uln, ext, tw = [v * D for v in x]
    W, pole, f, E, xl = arm_q(1.0, az, e, r, el)
    hrb, hrk = sword_hand2(f, xl, uln, ext, tw)
    hb = hand_basis(hrb, hrk, 1.0)
    grip_cs = W + hb @ GRIP
    tb, co = body["tb"], body["co"]
    return {"grip": co + tb @ grip_cs, "tip": co + tb @ (grip_cs + 0.64 * hrb), "flat": tb @ hb[:, 0], "elbow": co + tb @ E,
            "wrist": co + tb @ W, "f": tb @ f, "blade": tb @ hrb, "E_cs": E, "W_cs": W, "hrb": hrb, "hand": hb, "pole": pole}


def body_at(S, t):
    p = pose(S, t)
    return {"pb": p["pb"], "tb": p["tb"], "po": p["po"], "co": p["co"]}


def wrist_ext_deg(x, body):
    """the hand's extension as the rig's own measure sees it (anim_check._wrist): approximated by the param ext here"""
    return x[5]


def residual(x, body, tgt):
    s = arm_state(x, body)
    res = []
    if "grip" in tgt:
        res += list((s["grip"] - tgt["grip"]) / 0.03)
    if "tip" in tgt:
        res += list((s["tip"] - tgt["tip"]) / 0.04)
    if "blade" in tgt:
        res += list((unit(s["tip"] - s["grip"]) - unit(tgt["blade"])) / 0.12)
    if "flat_y2" in tgt:   # |flat.y|^2 target (1: flats up/down, an edge-leading horizontal cut; 0: edge up/down)
        res.append((s["flat"][1] ** 2 - tgt["flat_y2"]) / 0.15)
    if "flat_y" in tgt:    # signed: keeps the hand rolled the same way through a blow (no turn about the blade between two keys)
        res.append((s["flat"][1] - tgt["flat_y"]) / 0.2)
    if "flat_dir" in tgt:  # the flat normal along a given axis (either sign)
        res.append((1 - abs(np.dot(s["flat"], unit(tgt["flat_dir"])))) / 0.2)
    if "elbow" in tgt:
        res += list((s["elbow"] - tgt["elbow"]) / 0.05)
    # elbow stays out of the torso (chest space distance from the spine line)
    E = s["E_cs"]
    d = np.hypot(E[0], E[2] * 1.0)
    res.append(max(0.30 - d, 0.0) / 0.03)
    # the arm keeps clear of the torso (the checker's capsules, in chest space; the upper arm 0.072, the forearm 0.064)
    S0 = SHOULDER_CS
    cl = 9.0
    for q in (0.5, 0.7, 0.9):
        cl = min(cl, torso_clear(S0 + (E - S0) * q) - 0.070)
    Wc = s["W_cs"]
    for q in (0.167, 0.5, 0.833):
        cl = min(cl, torso_clear(E + (Wc - E) * q) - 0.065)
    res.append(max(CLEAR_MARGIN - cl, 0.0) / 0.01 if CLEAR_ON else 0.0)
    # limits (always present, zero inside)
    for k, v in zip(NAMES, x):
        lo, hi = LIM[k]
        res.append(max(lo - v, 0.0) / 3.0)
        res.append(max(v - hi, 0.0) / 3.0)
    # preferences for single joints: (index, value, sigma) pull a joint towards a value (the swivel of the elbow is free)
    for (jj, val, sg) in tgt.get("pref", []):
        res.append((x[jj] - val) / sg)
    # priors keep it near the nominal / the previous key
    pri = tgt.get("prior")
    if pri is not None:
        w = tgt.get("prior_w", 0.15)
        res += list((np.asarray(x) - np.asarray(pri)) / 30.0 * w)
        win = tgt.get("win")
        if win is not None:   # hard window around the previous key (the wrist cannot jump)
            for xj, pj, wj in zip(x, pri, win):
                res.append(max(abs(xj - pj) - wj, 0.0) / 2.0)
        else:
            res += [0.0] * 7
    return np.array(res)


def solve(body, tgt, x0, iters=60):
    x = np.array(x0, float)
    lam = 1e-2
    r = residual(x, body, tgt)
    c = r @ r
    for it in range(iters):
        J = np.zeros((len(r), len(x)))
        for j in range(len(x)):
            h = 0.5
            xp = x.copy()
            xp[j] += h
            J[:, j] = (residual(xp, body, tgt) - r) / h
        A = J.T @ J + lam * np.eye(len(x))
        g = J.T @ r
        try:
            dx = -np.linalg.solve(A, g)
        except np.linalg.LinAlgError:
            break
        dx = np.clip(dx, -25, 25)
        xn = x + dx
        rn = residual(xn, body, tgt)
        cn = rn @ rn
        if cn < c:
            x, r, c = xn, rn, cn
            lam = max(lam * 0.4, 1e-5)
            if np.max(np.abs(dx)) < 0.02:
                break
        else:
            lam *= 4
            if lam > 1e6:
                break
    return x, c


def solve_multi(body, tgt, x0s, iters=60):
    best = None
    for x0 in x0s:
        x, c = solve(body, tgt, x0, iters)
        if best is None or c < best[1]:
            best = (x, c)
    return best


def rand_starts(n, rng, base=None):
    out = []
    if base is not None:
        out.append(np.array(base, float))
    for _ in range(n):
        out.append(np.array([rng.uniform(-150, 100), rng.uniform(20, 140), rng.uniform(-20, 80), rng.uniform(25, 110),
                             rng.uniform(25, 60), rng.uniform(-20, 40), rng.uniform(-90, 90)]))
    return out
