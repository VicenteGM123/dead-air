import sys
sys.path.insert(0, ".")
from smodel import *
from solve import arm_state, body_at

def pol(p):
    return f"az{az_of(p):7.1f} r{np.hypot(p[0], p[2]):5.2f} h{p[1]:5.2f}"

def show(body, t, x, label=""):
    b = body_at(body, t)
    s = arm_state(x, b)
    bl = unit(s["tip"] - s["grip"])
    bel = np.degrees(np.arcsin(bl[1]))
    f = unit(s["f"])
    print(f"{label}t={t:.3f} x={np.round(x,0)}  grip[{pol(s['grip'])}] tip[{pol(s['tip'])}] elbow[{pol(s['elbow'])}] blade az{az_of(bl):6.1f} el{bel:5.1f} flat_y{s['flat'][1]:+.2f} fore az{az_of(f):6.1f} el{np.degrees(np.arcsin(f[1])):5.1f} bl_fa{np.degrees(np.arccos(np.clip(np.dot(bl,f),-1,1))):5.1f}")
