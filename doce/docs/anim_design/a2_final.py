import sys, json
sys.path.insert(0, ".")
from a2_build import *
from export import export

COIL = [-7, 84, 100, 59, 63, -35, 98]
IMP = [5, 79, 51, 14, 48, 5, 120]
FOL = [-15, 68, 54, 14, 46, 0, 120]
REC = [-20, 40, 40, 60, 44, 10, 115]
RDY = [-30, 45, 40, 70, 45, 10, 120]

def curve(vals, ta, tb, tf, tr, tn):
    c, i, f, r, n = vals
    return [0.0, c, ta, c, tb, i, tf, f, tr, r, tn, n]

def build(P=P2):
    S = body_a2(P)
    tf, tr, tn = P["tail"]
    names = ["az", "e", "r", "el", "uln", "ext", "tw"]
    grp = {"az": "sh", "e": "sh", "r": "sh", "el": "el", "uln": "wr", "ext": "wr", "tw": "wr"}
    for j, nm in enumerate(names):
        ta, tb = P[grp[nm]]
        S[nm] = curve([COIL[j], IMP[j], FOL[j], REC[j], RDY[j]], ta, tb, tf, tr, tn)
    S["feet"] = {"moves": [{"f": 0, "t0": 0.04, "t1": 0.20, "x": 0.18, "z": -0.30, "yaw": -8.0, "apex": 0.09, "th": 12.0},
                           {"f": 1, "t0": 0.40, "t1": 0.53, "x": -0.15, "z": -0.10, "yaw": 8.0, "apex": 0.07, "th": 8.0}],
                 "pitch1": [0.0, 0.0, 0.14, 0.0, 0.28, -30.0, 0.39, -30.0],
                 "follow1": [0.0, 0.0, 0.10, 0.0, 0.25, 0.7, 0.4, 0.7]}
    return S

if __name__ == "__main__":
    S = build()
    report(S, 0.20, every=3)
