import sys, json
sys.path.insert(0, ".")
from h_build import *

NEU = [-30, 45, 40, 70, 45, 10, 120]
COILH = [-71, 10, 39, 94, 27, 40, 100]
SPINH = [-124, 61, 100, 89, 53, -34, 120]
SLAMH = [-13, 21, 47, 100, 33, -36, 124]
HOLDH = [25, 58, -5, 21, 53, -35, 121]
RDYH = [-30, 45, 40, 70, 45, 10, 120]

def rot_curve(wk, total=360.0, step=0.01):
    """angle keys [t, deg] of a whole-body spin whose angular speed (deg/s) is the polyline wk [(t, w), ...], scaled to `total` degrees"""
    ts = np.arange(wk[0][0], wk[-1][0] + 1e-9, step)
    w = np.interp(ts, [a for a, b in wk], [b for a, b in wk])
    ang = np.concatenate([[0.0], np.cumsum(0.5 * (w[1:] + w[:-1]) * step)])
    ang *= total / ang[-1]
    out = [0.0, 0.0]
    for t, a in zip(ts, ang):
        out += [round(float(t), 3), round(float(a), 2)]
    out += [1.0, total]
    return out

WK = [(0.33, 0), (0.37, 900), (0.42, 1450), (0.50, 1300), (0.58, 1000), (0.65, 600), (0.72, 0)]

def build(W=None, wk=WK):
    W = W or {"sh1": (0.34, 0.44), "el1": (0.36, 0.46), "wr1": (0.39, 0.48), "sh2": (0.56, 0.72), "el2": (0.60, 0.74), "wr2": (0.64, 0.78)}
    S = body_h()
    S["rot"] = rot_curve(wk)
    S["pivx"] = -0.075
    S["pivz"] = 0.0
    names = ["az", "e", "r", "el", "uln", "ext", "tw"]
    grp = {"az": "sh", "e": "sh", "r": "sh", "el": "el", "uln": "wr", "ext": "wr", "tw": "wr"}
    for j, nm in enumerate(names):
        g = grp[nm]
        a1, b1 = W[g + "1"]
        a2, b2 = W[g + "2"]
        S[nm] = [0.0, NEU[j], 0.2, COILH[j], 0.30, COILH[j], a1, COILH[j], b1, SPINH[j], a2, SPINH[j], b2, SLAMH[j], 0.85, HOLDH[j], 1.0, RDYH[j]]
    S["laz"] = [0.0, -30, 0.3, -30, 0.4, -12, 0.66, -14, 0.72, -22, 1.0, -30]
    S["le"] = [0.0, 30, 0.3, 40, 0.4, 50, 0.66, 52, 0.72, 40, 1.0, 30]
    S["lel"] = [0.0, 85, 0.3, 88, 0.4, 112, 0.66, 112, 0.72, 100, 1.0, 85]
    S["lr"] = [0.0, 0, 1.0, 0]
    S["lfy"] = [0.0, 15, 0.3, 0, 0.5, 30, 0.72, 15, 1.0, 15]
    S["hy"] = [0.0, 0, 0.3, -30, 0.4, -10, 0.5, 0, 0.72, 10, 1.0, 0]
    S["hp"] = [0.0, 0, 0.5, -4, 0.72, -14, 0.85, -12, 1.0, 0]
    # the body over the standing foot (the ball of the left foot is the centre of the spin), then the deep step
    S["px"] = [0.0, 0, 0.30, 0.05, 0.38, 0.04, 0.66, 0.04, 0.72, 0.02, 0.8, 0.0, 1.0, 0]
    S["pz"] = [0.0, 0, 0.30, 0.05, 0.38, 0.06, 0.66, 0.04, 0.72, -0.24, 0.82, -0.22, 1.0, 0]
    # the feet (rig space, before the spin turns them): right = the free foot, tucked behind and carried round, then the deep step
    S["f0x"] = [0.0, 0.15, 0.34, 0.15, 0.40, 0.20, 0.62, 0.20, 0.72, 0.20, 1.0, 0.20]
    S["f0y"] = [0.0, 0.093, 0.34, 0.093, 0.40, 0.40, 0.62, 0.40, 0.72, 0.093, 1.0, 0.093]
    S["f0z"] = [0.0, 0.04, 0.34, 0.04, 0.40, 0.22, 0.62, 0.22, 0.72, -0.48, 1.0, -0.48]
    S["f0p"] = [0.0, 0, 0.34, 0, 0.40, -50, 0.62, -50, 0.70, 10, 0.78, 0, 1.0, 0]
    S["f0w"] = [0.0, -10, 0.30, -10, 0.40, -20, 0.62, -20, 0.72, 8, 1.0, 8]
    S["f1x"] = [0.0, -0.15, 0.30, -0.15, 0.36, -0.075, 0.72, -0.075, 0.9, -0.10, 1.0, -0.10]
    S["f1y"] = [0.0, 0.093, 0.30, 0.093, 0.36, 0.187, 0.72, 0.187, 0.78, 0.12, 0.9, 0.093, 1.0, 0.093]
    S["f1z"] = [0.0, -0.06, 0.30, -0.06, 0.36, 0.17, 0.72, 0.17, 0.78, 0.14, 0.9, 0.12, 1.0, 0.12]
    S["f1p"] = [0.0, 0, 0.30, 0, 0.36, -30, 0.72, -30, 0.78, -12, 0.9, 0, 1.0, 0]
    S["f1w"] = [0.0, 10, 0.30, 10, 0.36, 0, 0.72, 0, 1.0, 0]
    S["feet"] = {"mode": "baked"}
    return S

if __name__ == "__main__":
    S = build()
    ts, ch, ps = report(S, 0.47, every=2)
