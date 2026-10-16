import sys
sys.path.insert(0, ".")
import numpy as np
import defs as DF
from smodel import *
name = sys.argv[1]
t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
t1 = float(sys.argv[3]) if len(sys.argv) > 3 else 0.4
step = float(sys.argv[4]) if len(sys.argv) > 4 else 0.02
S = DF.build(name)
ts, ch, ps = chain(S)
print("   t   | joint values az  e   r   el  uln ext  tw | rates deg/s az e r el uln ext tw | chain hips chest sh el wr tip | tip az/r/h  bl az/el")
for t in np.arange(t0, t1 + 1e-9, step):
    x = [sv(S, k, t) for k in DF.NAMES]
    v = [(sv(S, k, t + 0.005) - sv(S, k, t - 0.005)) / 0.01 for k in DF.NAMES]
    i = int(round(t * 120))
    p = ps[i]
    tip = p["tip"]
    bl = unit(p["tip"] - p["root"])
    print(f"{t:5.3f} | " + " ".join(f"{a:5.0f}" for a in x) + " | " + " ".join(f"{a:5.0f}" for a in v) + " | " +
          " ".join(f"{ch[k][i]:4.1f}" for k in ["hips", "chest", "shoulder", "elbow", "wrist", "tip"]) +
          f" | {az_of(tip):6.1f} {np.hypot(tip[0], tip[2]):4.2f} {tip[1]:4.2f} | {az_of(bl):6.1f} {np.degrees(np.arcsin(bl[1])):5.1f}")
