import sys, json
sys.path.insert(0, ".")
from a1_param import *
from export import export

def joint_curves(keys, windows, tail):
    """keys: {joint: [(coil), (impact), (follow), (recovery), (ready)]} ; windows: {joint: (ta, tb)} ; tail: times of follow / recovery / ready"""
    pass

def curve(vals, ta, tb, tf, tr, tn, hold0=0.0):
    """coil value held to ta, impact value reached at tb, follow-through at tf, recovery at tr, ready at tn"""
    c, i, f, r, n = vals
    return [0.0, c, ta, c, tb, i, tf, f, tr, r, tn, n]

# key joint poses (az, e, r, el, uln, ext, tw)
import os
COIL = [float(x) for x in os.environ.get('COIL', '-65,71,39,108,27,33,122').split(',')]
IMP = [-46, 86, 79, 41, 65, -36, 121]
FOL = [-11, 71, 88, 30, 63, -35, 120]
REC = [7, 48, 38, 14, 62, 8, 120]
RDY = [-30, 45, 40, 70, 45, 10, 120]

def build(P):
    S = {"len": 0.56, "in": 0.07, "out": 0.22, "ev": {"swing": 0.13, "impact": 0.205, "step": [0.2, 0.53]}}
    # body
    S["py"] = [0.0, -15, P["py"][0], -15, P["py"][1], 24, 0.25, 30, 0.34, 24, 0.45, 8, 0.56, 0]
    S["pp"] = [0.0, 4, 0.05, 6, 0.13, 0, 0.205, -7, 0.3, -5, 0.45, -1, 0.56, 1.1]
    S["pr"] = [0.0, 3, 0.05, 4, 0.13, 0, 0.205, -5, 0.3, -4, 0.45, -1, 0.56, 0]
    S["px"] = [0.0, 0.03, 0.05, 0.04, 0.13, 0.0, 0.205, -0.05, 0.3, -0.04, 0.45, -0.01, 0.56, 0]
    S["pz"] = [0.0, 0.04, 0.05, 0.06, 0.1, 0.0, 0.205, -0.14, 0.3, -0.12, 0.45, -0.04, 0.56, 0]
    S["pdy"] = [0.0, -0.04, 0.05, -0.05, 0.13, -0.08, 0.205, -0.12, 0.3, -0.10, 0.45, -0.04, 0.56, 0]
    S["cy"] = [0.0, -36, P["cy"][0], -36, P["cy"][1], 40, 0.26, 48, 0.34, 40, 0.45, 14, 0.56, 0]
    S["cp"] = [0.0, 8, 0.05, 9, 0.13, 0, 0.205, -16, 0.3, -12, 0.45, -2, 0.56, 4]
    S["cr"] = [0.0, -3, 0.05, -4, 0.13, 0, 0.205, 6, 0.3, 5, 0.45, 1, 0.56, 0]
    # arm
    tf, tr, tn = P["tail"]
    names = ["az", "e", "r", "el", "uln", "ext", "tw"]
    grp = {"az": "sh", "e": "sh", "r": "sh", "el": "el", "uln": "wr", "ext": "wr", "tw": "wr"}
    for j, nm in enumerate(names):
        ta, tb = P[grp[nm]]
        S[nm] = curve([COIL[j], IMP[j], FOL[j], REC[j], RDY[j]], ta, tb, tf, tr, tn)
    S["feet"] = {"moves": [{"f": 1, "t0": 0.03, "t1": 0.20, "x": -0.18, "z": -0.44, "yaw": 8.0, "apex": 0.10, "th": 12.0},
                           {"f": 0, "t0": 0.40, "t1": 0.53, "x": 0.16, "z": -0.04, "yaw": -8.0, "apex": 0.07, "th": 8.0}],
                 "pitch0": [0.0, 0.0, 0.12, 0.0, 0.26, -32.0, 0.39, -32.0],
                 "follow0": [0.0, 0.0, 0.10, 0.0, 0.25, 0.7, 0.4, 0.7]}
    return S

P0 = {"py": (0.04, 0.155), "cy": (0.06, 0.19), "sh": (0.10, 0.215), "el": (0.115, 0.225), "wr": (0.145, 0.235), "tail": (0.30, 0.42, 0.56)}
if __name__ == "__main__":
    S = build(P0)
    report(S, 0.205, every=3)

    from export import export
    export({"attack1": S})
