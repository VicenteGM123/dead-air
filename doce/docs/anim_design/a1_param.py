"""attack1 built from joint transitions: every joint goes from its coil value to its impact value over [ta, tb], then to the
follow-through, then to the neutral (all smooth). The key poses are solved once (solve.py) and stored."""
import sys, json
sys.path.insert(0, ".")
from ev import *
from solve import *

def polar(az, r, h):
    a = az * D
    return np.array([r * np.sin(a), h, -r * np.cos(a)])

def bdir(az, el):
    a, e = az * D, el * D
    return np.array([np.cos(e) * np.sin(a), np.sin(e), -np.cos(e) * np.cos(a)])

NAMES = ["az", "e", "r", "el", "uln", "ext", "tw"]

def trans(vals_times):
    """[(t_start, v_start), (t_end, v_end), ...] -> keys with a hold before each transition"""
    out = []
    for (t, v) in vals_times:
        out += [round(t, 4), round(float(v), 2)]
    return out

def solve_keys(body, specs, prev, rng, win=None):
    sol = []
    for (t, g, bd, fy2, el) in specs:
        b = body_at(body, t)
        tgt = {"grip": polar(*g), "blade": bdir(*bd), "prior": prev, "prior_w": 0.35}
        if isinstance(fy2, tuple):      # (signed flat_y target,)
            tgt["flat_y"] = fy2[0]
        else:
            tgt["flat_y2"] = fy2
        if win is not None:
            tgt["win"] = win
        if el is not None:
            tgt["elbow"] = polar(*el)
        best = solve_multi(b, tgt, [np.array(prev, float)] + rand_starts(12, rng, prev), iters=90)
        print("cost %6.2f " % best[1], end="")
        show(body, t, best[0])
        sol.append((t, best[0]))
        prev = best[0]
    return sol
