#!/usr/bin/env python3
"""The four blows of Heracles, defined once: the body curves (hips, chest, pelvis shift, head), the key poses of the sword arm
(refitted from the first design: where the grip and the blade must be, the joint angles are SOLVED for the body of that moment and
the limits of the wrist), the order and timing in which each joint group gets from one key to the next (the kinetic chain),
the shield arm, the head and the feet.
    python3 defs.py [report] [--resolve]      builds, reports the chain, writes ../strike_data.gd.txt (and keys_cache.json)
Angles in degrees, lengths in metres, times in the action's own seconds (the game plays attack1/2 at 1.05x).
"""
import sys, json, os, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import solve as SV
from smodel import *
from solve import solve_multi, arm_state, body_at
from export import export

HERE = os.path.dirname(os.path.abspath(__file__))
SOLVER_VER = 3                  # bump when solve.py's residual changes (the cache of solved keys)
ULN_MAX = 59.5                  # the blade is 90 - uln degrees from the forearm: never closer than 30 (the check wants 28)
SV.LIM["uln"] = (28, ULN_MAX)
SV.LIM["ext"] = (-45, 45)
NAMES = ["az", "e", "r", "el", "uln", "ext", "tw"]
GROUP = {"az": "sh", "e": "sh", "r": "sh", "el": "el", "uln": "wr", "ext": "wr", "tw": "wr"}
READY = [-30, 45, 40, 70, 45, 10, 120]       # the sword hand at the hip, the blade forward and down: where every blow ends


def polar(az, r, h):
    a = az * D
    return np.array([r * np.sin(a), h, -r * np.cos(a)])


def bdir(az, el):
    a, e = az * D, el * D
    return np.array([np.cos(e) * np.sin(a), np.sin(e), -np.cos(e) * np.cos(a)])


def rot_curve(wk, total=360.0, step=0.01):
    """angle keys of a whole-body spin whose angular speed (deg/s) is the polyline wk [(t, w), ...], scaled to `total` degrees"""
    ts = np.arange(wk[0][0], wk[-1][0] + 1e-9, step)
    w = np.interp(ts, [a for a, b in wk], [b for a, b in wk])
    ang = np.concatenate([[0.0], np.cumsum(0.5 * (w[1:] + w[:-1]) * step)])
    ang *= total / ang[-1]
    out = [0.0, 0.0]
    for t, a in zip(ts, ang):
        out += [round(float(t), 3), round(float(a), 2)]
    out += [1.0, total]
    return out


# =================================================================================================================================
# The first design (docs/ANIMATION.md 4.8, v4): its joint keys, evaluated where they were reached, are the targets the new keys
# refit (same blade, same hand, the wrist inside its limit); a "delta" moves a target (azimuth degrees, metres) on purpose.
OLD_KEYS = {
    "attack1": {"coil": ([-65, 71, 39, 108, 27, 33, 122], 0.05), "imp": ([-46, 86, 79, 41, 65, -36, 121], 0.235),
                "fol": ([-11, 71, 88, 30, 63, -35, 120], 0.30), "rec": ([7, 48, 38, 14, 62, 8, 120], 0.42)},
    "attack2": {"coil": ([-7, 84, 100, 59, 63, -35, 98], 0.04), "imp": ([5, 79, 51, 14, 48, 5, 120], 0.22),
                "fol": ([-15, 68, 54, 14, 46, 0, 120], 0.30), "rec": ([-20, 40, 40, 60, 44, 10, 115], 0.42)},
    "attack3": {"apex": ([-25, 106, 13, 89, 52, 12, 121], 0.19), "imp": ([29, 68, -60, 42, 63, -17, 120], 0.348),
                "fol": ([15, 60, -29, 25, 63, -34, 120], 0.43), "rec": ([-5, 45, 20, 55, 55, 0, 120], 0.55)},
    "heavy": {"coil": ([-71, 10, 39, 94, 27, 40, 100], 0.30), "spin": ([-124, 61, 100, 89, 53, -34, 120], 0.52),
              "slam": ([-13, 21, 47, 100, 33, -36, 124], 0.78), "hold": ([25, 58, -5, 21, 53, -35, 121], 0.85)},
}


def old_body(name):
    import a1_build as A1, a2_final as A2, a3_final as A3, h_final as H
    if name == "attack1":
        return A1.build(A1.P0)
    if name == "attack2":
        return A2.build(A2.P2)
    if name == "attack3":
        return A3.build({"py": (0.085, 0.265), "cy": (0.105, 0.29), "sh": (0.125, 0.325), "el": (0.19, 0.34), "wr": (0.265, 0.348), "tail": (0.43, 0.6, 0.8)}, apex_t=0.12)
    return H.build(wk=[(0.30, 0), (0.33, 1000), (0.56, 1000), (0.72, 0)])


def old_target(name, kid, delta):
    """the world target (grip, blade, flat, elbow) of the old key, moved by delta {"g": (daz, dr, dh), "b": (daz, del), "fy": value, "noelbow": 1}"""
    x, t = OLD_KEYS[name][kid]
    So = {k: v for k, v in old_body(name).items() if k != "rot"}
    b = body_at(So, t)
    s = arm_state(np.array(x, float), b)
    g = s["grip"]
    dg = delta.get("g", (0, 0, 0))
    gp = polar(az_of(g) + dg[0], np.hypot(g[0], g[2]) + dg[1], g[1] + dg[2])
    bl = unit(s["tip"] - s["grip"])
    db = delta.get("b", (0, 0))
    bd = bdir(az_of(bl) + db[0], np.degrees(np.arcsin(bl[1])) + db[1])
    tgt = {"grip": gp, "blade": bd}
    fy = s["flat"][1]
    tgt["flat_y"] = delta.get("fy", fy)
    if not delta.get("noelbow"):
        e = s["elbow"]
        tgt["elbow"] = polar(az_of(e) + dg[0], np.hypot(e[0], e[2]), e[1])
    return tgt, np.array(x, float), t


def solve_keys(name, S, deltas, force=False):
    """refit every key of the blow: the grip/blade/elbow/flat of the old key (moved by its delta) with the new body and limits"""
    cache_path = os.path.join(HERE, "keys_cache.json")
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    body_keys = ("py", "pp", "pr", "px", "pz", "pdy", "cy", "cp", "cr", "rot", "pivx", "pivz")
    sig = hashlib.md5(json.dumps([SOLVER_VER, name, {k: S[k] for k in body_keys if k in S}, deltas, ULN_MAX, SV.LIM["ext"], OLD_KEYS[name]], default=str).encode()).hexdigest()
    if not force and cache.get(name, {}).get("sig") == sig:
        return cache[name]["keys"]
    rng = np.random.default_rng(5)
    Bi = {k: v for k, v in S.items() if k != "rot"}
    sol = {}
    for kid in OLD_KEYS[name]:
        d = deltas.get(kid, {})
        tgt, x0, t_arr = old_target(name, kid, d)
        t_arr = d.get("t", t_arr)
        b = body_at(Bi, t_arr)
        tgt["prior"] = x0
        tgt["prior_w"] = 0.25
        if "pref" in d:
            tgt["pref"] = d["pref"]
        starts = [x0] + [x0 + rng.normal(0, 6.0, 7) for _ in range(6)]
        best = solve_multi(b, tgt, starts, iters=90)
        x = [round(float(v), 1) for v in best[0]]
        s = arm_state(np.array(x), b)
        bd = unit(s["tip"] - s["grip"])
        print(f"  {name:8s} {kid:5s} t={t_arr:.3f} cost {best[1]:6.2f} x={x}  was {list(map(int, x0))}  grip[az {az_of(s['grip']):6.1f} r {np.hypot(s['grip'][0], s['grip'][2]):.2f} h {s['grip'][1]:.2f}] "
              f"blade az {az_of(bd):6.1f} el {np.degrees(np.arcsin(bd[1])):5.1f} flat_y {s['flat'][1]:+.2f}")
        sol[kid] = x
    cache[name] = {"sig": sig, "keys": sol}
    json.dump(cache, open(cache_path, "w"), indent=1)
    return sol


def assemble(S, sol, arm, extra=None):
    sol = dict(sol)
    sol["rdy"] = READY
    if extra:
        sol.update(extra)
    for j, nm in enumerate(NAMES):
        seq = arm[GROUP[nm]]
        out = []
        for (t, kid) in seq:
            out += [t, sol[kid][j]]
        S[nm] = out
    return S



# ---- feet (rig space): ankles that keep their contact point still while the foot rolls --------------------------------------
FOOT_HEEL = np.array([0.0, -0.093, 0.075])
FOOT_TOE = np.array([0.0, -0.093, -0.22])


def _foot_off(kind, yaw_deg, pitch_deg):
    return Ry(yaw_deg * D) @ Rx(pitch_deg * D) @ (FOOT_HEEL if kind == 0 else FOOT_TOE)


def ankle_on(pin, kind, yaw_deg, pitch_deg):
    """the ankle (x, y, z) of a foot whose heel (kind 0) or toe (kind 1) touches the ground at pin (x, z)"""
    o = _foot_off(kind, yaw_deg, pitch_deg)
    return (pin[0] - o[0], -o[1], pin[1] - o[2])


def pin_of(ank, kind, yaw_deg, pitch_deg):
    o = _foot_off(kind, yaw_deg, pitch_deg)
    return (ank[0] + o[0], ank[2] + o[2])


def foot_step_back(t_lift, t_roll, t_apex, t_land, t_flat, a0, yaw0, yaw1, home, lift_pitch=-25.0, apex_y=0.20, land_pitch=8.0, apex_pitch=-10.0):
    """Keys (x, y, z, pitch, yaw arrays) of a foot that stands flat at ankle a0 (x, y, z, yaw0) from before t_lift, rolls onto its toe
    (the toe stays where it is) until t_roll, swings to land on its heel at t_land (the heel's spot is the one that puts the
    flat foot at `home` at t_flat) and settles flat by t_flat."""
    toe = pin_of(a0, 1, yaw0, 0.0)
    keys = []
    kx, ky, kz, kp, kw = [], [], [], [], []

    def add(t, a, p, w):
        kx.extend([t, a[0]]); ky.extend([t, a[1]]); kz.extend([t, a[2]]); kp.extend([t, p]); kw.extend([t, w])
    add(t_lift, a0, 0.0, yaw0)
    for u in (0.5, 1.0):
        pr = lift_pitch * u
        add(t_lift + (t_roll - t_lift) * u, ankle_on(toe, 1, yaw0 + (yaw1 - yaw0) * 0.1 * u, pr), pr, yaw0 + (yaw1 - yaw0) * 0.1 * u)
    heel = pin_of((home[0], 0.093, home[1]), 0, yaw1, 0.0)
    aland = ankle_on(heel, 0, yaw1, land_pitch)
    aroll = ankle_on(toe, 1, yaw0, lift_pitch)
    amid = (0.5 * (aroll[0] + aland[0]), apex_y, 0.5 * (aroll[2] + aland[2]))
    add(t_apex, amid, apex_pitch, 0.5 * (yaw0 + yaw1))
    add(t_land, aland, land_pitch, yaw1)
    add(t_flat, (home[0], 0.093, home[1]), 0.0, yaw1)
    return kx, ky, kz, kp, kw


# the shield arm (chest space): [(t, wrist, elbow pole, facing)] -> hlx.. hpx.. hfx.. curves (the old, clip-free keys of the first
# blows, moved a little so that the arm is never still)
SH_READY = ((-0.335, -0.366, -0.08), (-0.5, -0.2, 1.0), (-1.0, 0.0, -0.35))


def shield(S, keys):
    for ai, nm in enumerate(("hl", "hp", "hf")):
        for ci, c in enumerate("xyz"):
            S[nm[:2] + c if nm != "hl" else "hl" + c] = []
    for (t, w, p, f) in keys:
        for ci, c in enumerate("xyz"):
            S["hl" + c] += [t, w[ci]]
            S["hp" + c] += [t, p[ci]]
            S["hf" + c] += [t, f[ci]]
    return S


# =================================================================================================================================
def attack1():
    S = {"len": 0.56, "in": 0.07, "out": 0.22, "ev": {"swing": 0.13, "impact": 0.205, "step": [0.2, 0.53]}}
    S["py"] = [0.0, -15, 0.04, -15, 0.155, 24, 0.25, 31, 0.34, 25, 0.45, 8, 0.56, 0]
    S["pp"] = [0.0, 4, 0.05, 6, 0.13, 0, 0.205, -7, 0.3, -5, 0.45, -1, 0.56, 1.1]
    S["pr"] = [0.0, 3, 0.05, 4, 0.13, 0, 0.205, -5, 0.3, -4, 0.45, -1, 0.56, 0]
    S["px"] = [0.0, 0.03, 0.05, 0.04, 0.13, 0.0, 0.205, -0.05, 0.3, -0.04, 0.45, -0.01, 0.56, 0]
    S["pz"] = [0.0, 0.04, 0.05, 0.06, 0.1, 0.0, 0.205, -0.17, 0.3, -0.16, 0.45, -0.06, 0.56, 0]
    S["pdy"] = [0.0, -0.04, 0.05, -0.05, 0.13, -0.08, 0.205, -0.14, 0.3, -0.13, 0.45, -0.05, 0.56, 0]
    S["cy"] = [0.0, -36, 0.06, -36, 0.19, 41, 0.26, 52, 0.34, 44, 0.45, 14, 0.56, 0]
    S["cp"] = [0.0, 8, 0.05, 9, 0.13, 0, 0.205, -16, 0.3, -12, 0.45, -2, 0.56, 4]
    S["cr"] = [0.0, -3, 0.05, -4, 0.13, 0, 0.205, 6, 0.3, 5, 0.45, 1, 0.56, 0]
    S["hy"] = [0.0, -10, 0.05, -13, 0.1, -10, 0.15, 0, 0.19, 10, 0.23, 17, 0.3, 15, 0.4, 8, 0.5, 2, 0.56, 0]
    S["hp"] = [0.0, 2, 0.1, 2, 0.205, -5, 0.3, -4, 0.45, -1, 0.56, 0]
    shield(S, [(0.0,) + SH_READY,
               (0.05, (-0.34, -0.22, -0.18), (-0.55, -0.3, 0.9), (-0.8, 0.1, -0.6)),
               (0.12, (-0.38, -0.20, -0.20), (-0.6, -0.4, 0.8), (-0.75, 0.15, -0.65)),
               (0.205, (-0.42, -0.14, -0.12), (-0.6, -0.7, 0.5), (-0.75, 0.12, -0.6)),
               (0.29, (-0.42, -0.06, -0.08), (-0.6, -0.7, 0.5), (-0.8, 0.1, -0.5)),
               (0.47, (-0.35, -0.33, -0.08), (-0.5, -0.2, 1.0), (-1.0, 0.0, -0.2)),
               (0.56,) + SH_READY])
    deltas = {"fol": {"g": (0, 0, 0), "b": (-10, 0)}, "rec": {"noelbow": 1}}
    # joint group -> [(time, key)]: the value is held until the second-to-last time of a pair, then eased to the next key
    arm = {"sh": [(0.0, "coil"), (0.10, "coil"), (0.20, "imp"), (0.30, "fol"), (0.42, "rec"), (0.56, "rdy")],
           "el": [(0.0, "coil"), (0.115, "coil"), (0.215, "imp"), (0.30, "fol"), (0.42, "rec"), (0.56, "rdy")],
           "wr": [(0.0, "coil"), (0.145, "coil"), (0.23, "imp"), (0.30, "fol"), (0.42, "rec"), (0.56, "rdy")]}
    # the front (left) foot steps into the blow; at the end it steps back while the heel of the rear foot comes down
    S["feet"] = {"moves": [{"f": 1, "t0": 0.03, "t1": 0.20, "x": -0.18, "z": -0.42, "yaw": 8.0, "apex": 0.10, "th": 12.0},
                           {"f": 1, "t0": 0.38, "t1": 0.53, "x": -0.15, "z": -0.08, "yaw": 4.0, "apex": 0.07, "th": 6.0}],
                 "pitch0": [0.0, 0.0, 0.12, 0.0, 0.26, -32.0, 0.36, -32.0, 0.50, -4.0],
                 "follow0": [0.0, 0.0, 0.10, 0.0, 0.25, 0.7, 0.4, 0.7]}
    return S, deltas, arm, None


def attack2():
    S = {"len": 0.56, "in": 0.06, "out": 0.22, "ev": {"swing": 0.12, "impact": 0.20, "step": [0.2, 0.52]}}
    S["py"] = [0.0, 22, 0.03, 22, 0.14, -21, 0.25, -27, 0.34, -21, 0.45, -6, 0.56, 0]
    S["pp"] = [0.0, 1, 0.05, 3, 0.13, 0, 0.2, -6, 0.3, -4, 0.45, -1, 0.56, 1.1]
    S["pr"] = [0.0, -4, 0.05, -4, 0.14, 1, 0.2, 4, 0.3, 3, 0.45, 1, 0.56, 0]
    S["px"] = [0.0, -0.05, 0.05, -0.05, 0.14, 0.02, 0.2, 0.05, 0.3, 0.04, 0.45, 0.01, 0.56, 0]
    S["pz"] = [0.0, -0.12, 0.05, -0.10, 0.1, -0.12, 0.2, -0.17, 0.3, -0.14, 0.45, -0.05, 0.56, 0]
    S["pdy"] = [0.0, -0.09, 0.05, -0.10, 0.14, -0.10, 0.2, -0.11, 0.3, -0.10, 0.45, -0.04, 0.56, 0]
    S["cy"] = [0.0, 40, 0.05, 40, 0.175, -36, 0.26, -54, 0.34, -44, 0.45, -12, 0.56, 0]
    S["cp"] = [0.0, 3, 0.05, 5, 0.13, 0, 0.2, -12, 0.3, -9, 0.45, -1, 0.56, 4]
    S["cr"] = [0.0, 4, 0.05, 5, 0.14, 0, 0.2, -6, 0.3, -5, 0.45, -1, 0.56, 0]
    S["hy"] = [0.0, 12, 0.05, 14, 0.1, 10, 0.14, 0, 0.18, -9, 0.22, -14, 0.3, -12, 0.4, -6, 0.5, -1, 0.56, 0]
    S["hp"] = [0.0, -3, 0.1, -3, 0.2, -5, 0.3, -4, 0.45, -1, 0.56, 0]
    shield(S, [(0.0, (-0.45, -0.10, -0.15), (-0.8, -0.5, 0.4), (-0.7, 0.0, -0.7)),
               (0.11, (-0.46, -0.08, -0.14), (-0.8, -0.5, 0.4), (-0.7, 0.0, -0.7)),
               (0.20, (-0.41, -0.25, -0.10), (-0.8, -0.5, 0.4), (-0.85, 0.0, -0.35)),
               (0.31, (-0.40, -0.30, -0.08), (-0.6, -0.4, 0.7), (-0.95, 0.0, -0.3)),
               (0.47, (-0.35, -0.33, -0.08), (-0.5, -0.2, 1.0), (-1.0, 0.0, -0.2)),
               (0.56,) + SH_READY])
    deltas = {"fol": {"g": (16, 0, 0), "b": (18, 0)}, "imp": {"noelbow": 1}}
    arm = {"sh": [(0.0, "coil"), (0.085, "coil"), (0.20, "imp"), (0.30, "fol"), (0.42, "rec"), (0.56, "rdy")],
           "el": [(0.0, "coil"), (0.10, "coil"), (0.21, "imp"), (0.30, "fol"), (0.42, "rec"), (0.56, "rdy")],
           "wr": [(0.0, "coil"), (0.13, "coil"), (0.22, "imp"), (0.30, "fol"), (0.42, "rec"), (0.56, "rdy")]}
    S["feet"] = {"moves": [{"f": 1, "t0": 0.0, "t1": 0.13, "x": -0.15, "z": 0.0, "yaw": 6.0, "apex": 0.06, "th": 4.0, "near": 0.14},
                           {"f": 0, "t0": 0.04, "t1": 0.20, "x": 0.18, "z": -0.30, "yaw": -8.0, "apex": 0.09, "th": 12.0},
                           {"f": 0, "t0": 0.38, "t1": 0.53, "x": 0.15, "z": 0.0, "yaw": -4.0, "apex": 0.07, "th": 6.0}],
                 "pitch1": [0.0, 0.0, 0.14, 0.0, 0.28, -30.0, 0.36, -30.0, 0.50, -4.0],
                 "follow1": [0.0, 0.0, 0.10, 0.0, 0.25, 0.7, 0.4, 0.7]}
    return S, deltas, arm, None


def attack3():
    S = {"len": 0.80, "in": 0.07, "out": 0.25, "ev": {"swing": 0.27, "impact": 0.345, "step": [0.345, 0.72]}}
    S["py"] = [0.0, -18, 0.085, -24, 0.265, 26, 0.45, 28, 0.55, 14, 0.68, 4, 0.8, 0]
    S["pp"] = [0.0, 2, 0.12, 6, 0.2, 7, 0.345, -10, 0.45, -9, 0.6, -3, 0.8, 1.1]
    S["pr"] = [0.0, 3, 0.2, 4, 0.345, -6, 0.5, -5, 0.8, 0]
    S["px"] = [0.0, 0.05, 0.2, 0.05, 0.345, -0.05, 0.5, -0.05, 0.62, -0.02, 0.8, 0]
    S["pz"] = [0.0, 0.0, 0.2, 0.10, 0.28, 0.03, 0.345, -0.24, 0.5, -0.22, 0.65, -0.10, 0.8, 0]
    S["pdy"] = [0.0, -0.06, 0.12, 0.0, 0.2, 0.01, 0.345, -0.24, 0.5, -0.22, 0.65, -0.12, 0.8, 0]
    S["cy"] = [0.0, -42, 0.105, -46, 0.29, 18, 0.45, 24, 0.55, 14, 0.68, 4, 0.8, 0]
    S["cp"] = [0.0, 6, 0.12, 14, 0.2, 18, 0.345, -30, 0.45, -28, 0.6, -8, 0.8, 4]
    S["cr"] = [0.0, -4, 0.2, -6, 0.345, 6, 0.5, 5, 0.8, 0]
    S["hy"] = [0.0, -8, 0.2, -14, 0.3, -4, 0.345, 4, 0.5, 4, 0.8, 0]
    S["hp"] = [0.0, 0, 0.2, 8, 0.3, 4, 0.345, -14, 0.5, -14, 0.65, -4, 0.8, 0]
    shield(S, [(0.0, (-0.41, -0.25, -0.10), (-0.8, -0.5, 0.4), (-0.85, 0.0, -0.35)),
               (0.12, (-0.30, -0.06, -0.24), (-0.8, -0.5, 0.5), (-0.55, 0.15, -0.8)),
               (0.24, (-0.25, 0.0, -0.30), (-0.8, -0.5, 0.5), (-0.5, 0.2, -0.85)),
               (0.345, (-0.42, -0.38, -0.12), (-0.8, -0.5, 0.5), (-0.8, -0.2, -0.5)),
               (0.50, (-0.40, -0.36, -0.10), (-0.6, -0.4, 0.7), (-0.9, 0.0, -0.4)),
               (0.62, (-0.35, -0.33, -0.08), (-0.5, -0.2, 1.0), (-1.0, 0.0, -0.25)),
               (0.80,) + SH_READY])
    deltas = {"apex": {"g": (-14, 0.05, 0), "b": (-20, 0)}, "imp": {"g": (-8, 0, 0), "b": (-12, 0), "noelbow": 1},
              "fol": {"g": (-8, 0, 0), "b": (-12, 0), "noelbow": 1}, "rec": {"noelbow": 1}}
    arm = {"sh": [(0.0, "start"), (0.11, "apex"), (0.125, "apex"), (0.355, "imp"), (0.45, "fol"), (0.60, "rec"), (0.80, "rdy")],
           "el": [(0.0, "start"), (0.13, "apex"), (0.19, "apex"), (0.37, "imp"), (0.45, "fol"), (0.60, "rec"), (0.80, "rdy")],
           "wr": [(0.0, "start"), (0.14, "apex"), (0.265, "apex"), (0.378, "imp"), (0.45, "fol"), (0.60, "rec"), (0.80, "rdy")]}
    S["feet"] = {"moves": [{"f": 0, "t0": 0.0, "t1": 0.16, "x": 0.15, "z": 0.06, "yaw": -6.0, "apex": 0.06, "th": 4.0, "near": 0.14},
                           {"f": 1, "t0": 0.10, "t1": 0.345, "x": -0.19, "z": -0.58, "yaw": 8.0, "apex": 0.16, "th": 4.0},
                           {"f": 1, "t0": 0.58, "t1": 0.77, "x": -0.14, "z": -0.14, "yaw": 3.0, "apex": 0.08, "th": 5.0}],
                 "pitch0": [0.0, 0.0, 0.25, 0.0, 0.40, -28.0, 0.6, -28.0, 0.77, -6.0],
                 "follow0": [0.0, 0.0, 0.20, 0.0, 0.32, 0.6, 0.5, 0.6]}
    return S, deltas, arm, {"start": [-15, 68, 54, 14, 46, 0, 120]}


def heavy():
    S = {"len": 1.0, "in": 0.06, "out": 0.25, "ev": {"swing": 0.36, "impact": 0.47, "step": [0.4, 0.72]}}
    S["pivx"] = -0.075      # the contact of the standing foot's toe (the ankle at x -0.075, z 0.17, pitched 30 degrees: toe at z 0.026)
    S["pivz"] = 0.026
    S["rot"] = rot_curve([(0.30, 0), (0.36, 1000), (0.56, 1000), (0.72, 0)])
    S["py"] = [0.0, 0, 0.15, -20, 0.30, -35, 0.42, -18, 0.54, 0, 0.66, 8, 0.72, 17, 0.80, 14, 0.9, 6, 1.0, 0]
    S["cy"] = [0.0, 0, 0.15, -34, 0.30, -62, 0.42, -32, 0.56, -2, 0.66, 14, 0.72, 28, 0.80, 24, 0.9, 10, 1.0, 0]
    S["pp"] = [0.0, 1.1, 0.30, 6, 0.4, -4, 0.5, -8, 0.66, -8, 0.72, -14, 0.9, -4, 1.0, 1.1]
    S["cp"] = [0.0, 4, 0.30, 8, 0.4, -4, 0.5, -10, 0.66, -10, 0.72, -26, 0.82, -22, 1.0, 4]
    S["pr"] = [0.0, 0, 0.3, 4, 0.5, -4, 0.72, -6, 1.0, 0]
    S["cr"] = [0.0, 0, 0.3, -4, 0.5, 4, 0.72, 6, 1.0, 0]
    S["pdy"] = [0.0, 0, 0.30, -0.10, 0.4, -0.12, 0.66, -0.10, 0.72, -0.26, 0.82, -0.24, 0.90, -0.16, 0.97, -0.03, 1.0, 0]
    S["px"] = [0.0, 0, 0.30, 0.05, 0.38, 0.04, 0.66, 0.04, 0.72, 0.02, 0.8, 0.0, 1.0, 0]
    S["pz"] = [0.0, 0, 0.30, 0.05, 0.38, 0.06, 0.66, 0.04, 0.72, -0.24, 0.82, -0.22, 0.97, -0.02, 1.0, 0]
    shield(S, [(0.0,) + SH_READY,
               (0.3, (-0.08, -0.05, -0.46), (-1.0, -0.6, 0.3), (0.2, 0.0, -1.0)),
               (0.4, (-0.30, -0.18, 0.05), (-0.4, -0.5, 1.0), (-1.0, 0.0, 0.3)),
               (0.56, (-0.36, -0.10, 0.10), (-0.4, -0.5, 1.0), (-1.0, 0.1, 0.3)),
               (0.72, (-0.42, -0.20, -0.10), (-0.8, -0.5, 0.4), (-0.85, 0.0, -0.4)),
               (0.85, (-0.40, -0.26, -0.10), (-0.7, -0.4, 0.6), (-0.9, 0.0, -0.35)),
               (1.0,) + SH_READY])
    S["hy"] = [0.0, 0, 0.3, -30, 0.4, -10, 0.5, 0, 0.72, 10, 1.0, 0]
    S["hp"] = [0.0, 0, 0.5, -4, 0.72, -14, 0.85, -12, 1.0, 0]
    # the feet (rig space, before the spin turns them): right = the free foot, tucked behind and carried round, then the deep step
    # the free foot: tucked behind and carried round, the deep step (heel strike at 0.72), then the recovery: it rolls onto its toe,
    # steps back and lands on its heel at home
    bk = foot_step_back(0.81, 0.855, 0.90, 0.955, 0.995, (0.20, 0.093, -0.48), 8.0, -4.0, (0.15, 0.04))
    S["f0x"] = [0.0, 0.15, 0.34, 0.15, 0.40, 0.20, 0.62, 0.20, 0.72, 0.20] + bk[0]
    S["f0y"] = [0.0, 0.093, 0.34, 0.093, 0.40, 0.28, 0.62, 0.28, 0.72, 0.1046, 0.78, 0.093] + bk[1]
    S["f0z"] = [0.0, 0.04, 0.34, 0.04, 0.40, 0.22, 0.62, 0.22, 0.72, -0.48] + bk[2]
    S["f0p"] = [0.0, 0, 0.34, 0, 0.40, -50, 0.62, -50, 0.70, 10, 0.78, 0] + bk[3]
    S["f0w"] = [0.0, -10, 0.30, -10, 0.40, -20, 0.62, -20, 0.72, 8] + bk[4]
    S["f1x"] = [0.0, -0.15, 0.30, -0.15, 0.36, -0.075, 0.72, -0.075, 0.9, -0.10, 1.0, -0.10]
    S["f1y"] = [0.0, 0.093, 0.30, 0.093, 0.36, 0.1905, 0.72, 0.1905, 0.78, 0.1367, 0.9, 0.093, 1.0, 0.093]
    S["f1z"] = [0.0, -0.06, 0.30, -0.06, 0.36, 0.17, 0.72, 0.17, 0.78, 0.14, 0.9, 0.12, 1.0, 0.12]
    S["f1p"] = [0.0, 0, 0.30, 0, 0.36, -30, 0.72, -30, 0.78, -12, 0.9, 0, 1.0, 0]
    S["f1w"] = [0.0, 10, 0.30, 10, 0.36, 0, 0.72, 0, 1.0, 0]
    S["feet"] = {"mode": "baked"}
    deltas = {"slam": {"noelbow": 1, "g": (5.0, 0.04, 0.0)}, "hold": {"noelbow": 1}}
    arm = {"sh": [(0.0, "rdy"), (0.2, "coil"), (0.30, "coil"), (0.38, "coil"), (0.47, "spin"), (0.56, "spin"), (0.72, "slam"), (0.85, "hold"), (1.0, "rdy")],
           "el": [(0.0, "rdy"), (0.2, "coil"), (0.30, "coil"), (0.40, "coil"), (0.49, "spin"), (0.60, "spin"), (0.74, "slam"), (0.85, "hold"), (1.0, "rdy")],
           "wr": [(0.0, "rdy"), (0.2, "coil"), (0.30, "coil"), (0.43, "coil"), (0.51, "spin"), (0.64, "spin"), (0.78, "slam"), (0.85, "hold"), (1.0, "rdy")]}
    return S, deltas, arm, None


BLOWS = {"attack1": attack1, "attack2": attack2, "attack3": attack3, "heavy": heavy}
IMP = {"attack1": 0.205, "attack2": 0.20, "attack3": 0.345, "heavy": 0.47}
ACT = {"attack1": (0.125, 0.29), "attack2": (0.115, 0.28), "attack3": (0.262, 0.42), "heavy": (0.37, 0.68)}
COVER_Y = 1.9      # a blade point above this hits nothing a foe stands on (hero_melee's band reaches 0.9 m under a point)
OLD_COVER = {"attack1": [-180, -50, -40, -30, -20, -10], "attack2": [-30, -20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 90],
             "attack3": [-20, -10, 0, 10, 20, 140, 150], "heavy": list(range(-180, 180, 10))}


def build(name, force=False):
    S, deltas, arm, extra = BLOWS[name]()
    sol = solve_keys(name, S, deltas, force)
    return assemble(S, sol, arm, extra)


def build_all(force=False):
    return {n: build(n, force) for n in BLOWS}


# =================================================================================================================================
def coverage(S, name):
    """the azimuth bins (10 degrees from -180) the blade sweeps in its active window, as anim_check measures them (tip + 0.12 and the 60 % point)"""
    a0, a1 = ACT[name]
    ts = np.arange(a0, a1 + 1e-9, 1 / 120)
    ps = [pose(S, t) for t in ts]
    bins = set()
    for i in range(1, len(ts)):
        for s in range(17):
            u = s / 16
            tp = ps[i - 1]["tip"] * (1 - u) + ps[i]["tip"] * u
            rt = ps[i - 1]["root"] * (1 - u) + ps[i]["root"] * u
            d = unit(tp - rt)
            ext = tp + d * 0.12
            for p in (ext, rt + (ext - rt) * 0.6):
                if np.hypot(p[0], p[2]) >= 0.75 and p[1] <= COVER_Y:
                    bins.add(int(np.floor((az_of(p) + 180) / 10)) % 36)
    return sorted(b * 10 - 180 for b in bins)


def summary(S, name, verbose=True):
    imp = IMP[name]
    ts, ch, ps = chain(S)
    t_in = S.get("in", 0.07)
    w0 = max(imp - 0.2, (t_in + 0.02) if name != "heavy" else 0.3)
    w1 = imp + 0.05
    sel = (ts >= w0) & (ts <= w1)
    names = ["hips", "chest", "shoulder", "elbow", "wrist"]
    pk, pv = {}, {}
    for k in names + ["tip"]:
        a = np.where(sel, ch[k], -1)
        i = int(np.argmax(a))
        pk[k] = ts[i]
        pv[k] = a[i]
    viol = sum(1 for i in range(1, 5) if (pk[names[i]] - pk[names[i - 1]]) * 30 < -1.0)
    spread = (pk["wrist"] - pk["hips"]) * 30
    tipmax = float(np.max(np.where(ts >= w0, ch["tip"], 0)))
    blfa = min(np.degrees(p["bl_fa"]) for p in ps)
    elmax = max(np.degrees(p["elb"]) for p in ps)
    cov = coverage(S, name)
    old = [b for b in OLD_COVER[name] if name == "heavy" or abs(b + 5) <= 100]
    have = sum(1 for b in old if b in cov)
    pct = 100.0 * have / max(len(old), 1)
    rows = {"hips": pv["hips"], "chest/hips": pv["chest"] / max(pv["hips"], 1e-6), "viol": viol, "spread_f": spread, "tip": tipmax, "bl_fa": blfa, "elbow": elmax, "cover%": pct}
    if verbose:
        pf = " ".join(f"{k}{(pk[k] - imp) * 30:+.1f}" for k in names + ["tip"])
        print(f"   {name:8s} hips {pv['hips']:5.1f}  chest/hips {rows['chest/hips']:4.2f}  viol {viol}  spread {spread:+.2f} f  tip {tipmax:5.1f} m/s  bl_fa_min {blfa:5.1f}  elbow_max {elmax:5.1f}  cover {pct:5.1f}% ({have}/{len(old)})  peaks[f from impact]: {pf}")
        miss = [b for b in old if b not in cov]
        if miss:
            print(f"            missing old bins {miss}; new bins {cov}")
    return rows


if __name__ == "__main__":
    # (legacy since 2026-10-17: the blows the rig plays are moveset.py's; exporting these would put the old four back)
    force = "--resolve" in sys.argv
    allS = build_all(force)
    for k, S in allS.items():
        if "report" in sys.argv:
            print("=====", k)
            report(S, IMP[k], every=99)
        summary(S, k)
    if "--export-legacy" in sys.argv:
        export(allS)
    else:
        print("(not exported: the rig's blows come from moveset.py; --export-legacy writes the old four to strike_data.gd.txt)")
