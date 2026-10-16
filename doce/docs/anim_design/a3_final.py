import sys, json
sys.path.insert(0, ".")
from a3_build import *
from export import export

COIL = [-15, 68, 54, 14, 46, 0, 120]     # the follow-through of the backhand (where this blow starts from)
APEX = [-25, 106, 13, 89, 52, 12, 121]
IMP = [29, 68, -60, 42, 63, -17, 120]
FOL = [15, 60, -29, 25, 63, -34, 120]
REC = [-5, 45, 20, 55, 55, 0, 120]
RDY = [-30, 45, 40, 70, 45, 10, 120]

def build(P=P3, apex_t=0.20):
    S = body_a3(P)
    names = ["az", "e", "r", "el", "uln", "ext", "tw"]
    grp = {"az": "sh", "e": "sh", "r": "sh", "el": "el", "uln": "wr", "ext": "wr", "tw": "wr"}
    tf, tr, tn = P["tail"]
    for j, nm in enumerate(names):
        ta, tb = P[grp[nm]]
        S[nm] = [0.0, COIL[j], apex_t - 0.03 + (0.02 if grp[nm] != "sh" else 0.0), APEX[j], ta, APEX[j], tb, IMP[j], tf, FOL[j], tr, REC[j], tn, RDY[j]]
    S["feet"] = {"moves": [{"f": 1, "t0": 0.10, "t1": 0.345, "x": -0.19, "z": -0.66, "yaw": 8.0, "apex": 0.16, "th": 4.0}],
                 "pitch0": [0.0, 0.0, 0.25, 0.0, 0.40, -28.0, 0.6, -28.0],
                 "follow0": [0.0, 0.0, 0.20, 0.0, 0.32, 0.6, 0.5, 0.6]}
    return S

P3b = {"py": (0.15, 0.295), "cy": (0.175, 0.32), "sh": (0.215, 0.335), "el": (0.235, 0.345), "wr": (0.26, 0.352), "tail": (0.43, 0.6, 0.8)}

if __name__ == "__main__":
    S = build(P3b)
    report(S, 0.345, every=4)
