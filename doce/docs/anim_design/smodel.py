#!/usr/bin/env python3
"""Python mirror of the rig's strike kinematics (strike_block.gd.txt): the same curve evaluator, the same joint-angle
forward kinematics for the arms, the same hand model, the same chest/pelvis placement. Used to design the blows and to
get the chain metrics in milliseconds; verified against the Godot dump (tools/zz_dump.gd)."""
import numpy as np

D = np.pi / 180.0

# ---- rig constants (rig_heracles.gd) ------------------------------------------------------------------------------
P_PELVIS = np.array([0.0, 0.99, 0.0])
P_SPINE = np.array([0.0, 1.11, 0.01])
P_CHEST = np.array([0.0, 1.30, 0.0])
P_SHOULDER = np.array([0.255, 1.475, 0.02])
P_ELBOW = np.array([0.295, 1.17, 0.035])
P_WRIST = np.array([0.315, 0.90, 0.005])
SHOULDER_CS = np.array([0.255, 0.175, 0.02])
LEN_UA = float(np.linalg.norm(P_SHOULDER - P_ELBOW))
LEN_FA = float(np.linalg.norm(P_ELBOW - P_WRIST))
GRIP = np.array([0.0, -0.104, 0.0])
# the blade (rig_heracles.gd SWORD_ROOT / SWORD_TIP, grip space): 0.095 .. 1.075 m from the fist (0.64 before the long sword)
BLADE_ROOT = 0.095
BLADE_TIP = 1.075
NEUTRAL_PEL_Y = -0.035


def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def Rx(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def Rz(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def Raxis(axis, ang):
    a = unit(np.asarray(axis, float))
    K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + np.sin(ang) * K + (1 - np.cos(ang)) * (K @ K)


def eul(pitch, yaw, roll):
    """Godot: Basis(UP, yaw) * Basis(RIGHT, pitch) * Basis(BACK, roll)."""
    return Ry(yaw) @ Rx(pitch) @ Rz(roll)


def perp(v, a):
    return v - a * np.dot(v, a)


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def quat_of(R):
    # rotation matrix -> quaternion (w, x, y, z)
    tr = np.trace(R)
    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2
        return np.array([0.25 * s, (R[2, 1] - R[1, 2]) / s, (R[0, 2] - R[2, 0]) / s, (R[1, 0] - R[0, 1]) / s])
    i = np.argmax(np.diag(R))
    if i == 0:
        s = np.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2
        return np.array([(R[2, 1] - R[1, 2]) / s, 0.25 * s, (R[0, 1] + R[1, 0]) / s, (R[0, 2] + R[2, 0]) / s])
    if i == 1:
        s = np.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2
        return np.array([(R[0, 2] - R[2, 0]) / s, (R[0, 1] + R[1, 0]) / s, 0.25 * s, (R[1, 2] + R[2, 1]) / s])
    s = np.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2
    return np.array([(R[1, 0] - R[0, 1]) / s, (R[0, 2] + R[2, 0]) / s, (R[1, 2] + R[2, 1]) / s, 0.25 * s])


def mat_of(q):
    w, x, y, z = q / np.linalg.norm(q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def rot_angle(Ra, Rb):
    """angle (0..pi) of Rb Ra^T"""
    R = Rb @ Ra.T
    c = (np.trace(R) - 1) / 2
    return float(np.arccos(min(1.0, max(-1.0, c))))


def slerp_share(R, k):
    """the rotation R scaled to share k (quaternion slerp from identity)"""
    q = quat_of(R)
    if q[0] < 0:
        q = -q
    ang = 2 * np.arccos(min(1.0, q[0]))
    if ang < 1e-9:
        return np.eye(3)
    axis = q[1:] / np.sin(ang / 2)
    return Raxis(axis, ang * k)


# ---- curves (the monotone cubic Hermite of _kc) ---------------------------------------------------------------------
def kc_slope(k, j, n):
    if j <= 0 or j >= n - 1:
        return 0.0
    h0 = k[2 * j] - k[2 * j - 2]
    h1 = k[2 * j + 2] - k[2 * j]
    d0 = (k[2 * j + 1] - k[2 * j - 1]) / h0
    d1 = (k[2 * j + 3] - k[2 * j + 1]) / h1
    if d0 * d1 <= 0.0:
        return 0.0
    w1 = 2.0 * h1 + h0
    w2 = h1 + 2.0 * h0
    return (w1 + w2) / (w1 / d0 + w2 / d1)


def kc(k, t):
    n = len(k) // 2
    if t <= k[0]:
        return k[1]
    if t >= k[2 * n - 2]:
        return k[2 * n - 1]
    i = 0
    while i < n - 2 and t >= k[2 * i + 2]:
        i += 1
    t0, t1, v0, v1 = k[2 * i], k[2 * i + 2], k[2 * i + 1], k[2 * i + 3]
    h = t1 - t0
    m0, m1 = kc_slope(k, i, n), kc_slope(k, i + 1, n)
    u = (t - t0) / h
    u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * h * m0 + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * h * m1


def sv(S, key, t, d=0.0):
    return kc(S[key], t) if key in S else d


# ---- arm and hand ---------------------------------------------------------------------------------------------------
def arm_q(side, az, e, r, el):
    rb = Ry(az) @ Rx(e) @ Ry(r)
    u = rb @ np.array([0.0, -1.0, 0.0])
    f = rb @ np.array([0.0, -np.cos(el), -np.sin(el)])
    s0 = SHOULDER_CS.copy()
    E = s0 + u * LEN_UA
    W = E + f * LEN_FA
    pole = perp(E - s0, unit(W - s0))
    if np.dot(pole, pole) < 4e-4:
        pole = rb @ np.array([0.0, 0.0, 1.0])
    pole = unit(pole)
    xl = rb @ np.array([1.0, 0.0, 0.0])
    if side < 0:
        m = np.array([-1.0, 1.0, 1.0])
        return W * m, pole * m, f * m, E * m, xl * m
    return W, pole, f, E, xl


def hand_basis(blade, back, s=1.0):
    z = -unit(blade)
    x = unit(perp(back, z)) * s
    y = np.cross(z, x)
    return np.column_stack([x, y, z])


def sword_hand2(f, xl, uln, ext, tw):
    fn = unit(f)
    x_n = unit(perp(xl, fn))
    y_n = -fn
    z_n = np.cross(x_n, y_n)
    rot = Raxis(fn, tw) @ Raxis(x_n, -uln) @ Raxis(z_n, ext)
    h = rot @ np.column_stack([x_n, y_n, z_n])
    return -h[:, 2], h[:, 0]


def yxz_euler(R):
    """Godot Basis.get_euler(EULER_ORDER_YXZ) -> (pitch x, yaw y, roll z)"""
    # R = Ry(yaw) Rx(pitch) Rz(roll)
    sx = -R[1, 2]
    pitch = np.arcsin(max(-1.0, min(1.0, -R[1, 2])))
    if abs(R[1, 2]) < 0.9999999:
        yaw = np.arctan2(R[0, 2], R[2, 2])
        roll = np.arctan2(R[1, 0], R[1, 1])
    else:
        yaw = np.arctan2(-R[2, 0], R[0, 0])
        roll = 0.0
    return pitch, yaw, roll


# ---- one pose ---------------------------------------------------------------------------------------------------------
def pose(S, t):
    """Everything the chain metrics and the blade path need at time t."""
    P = {}
    pb = eul(sv(S, "pp", t, 1.1) * D, sv(S, "py", t) * D, sv(S, "pr", t) * D)
    pel = np.array([sv(S, "px", t), NEUTRAL_PEL_Y + sv(S, "pdy", t), sv(S, "pz", t)])
    tb = eul(sv(S, "cp", t, 4.0) * D, sv(S, "cy", t) * D, sv(S, "cr", t) * D)
    q_rel = pb.T @ tb
    Rs = slerp_share(q_rel, 0.4)
    sb = pb @ Rs
    po = P_PELVIS + pel
    so = po + pb @ (P_SPINE - P_PELVIS)
    co = so + sb @ (P_CHEST - P_SPINE)
    ra = arm_q(1.0, sv(S, "az", t) * D, sv(S, "e", t, 10.0) * D, sv(S, "r", t) * D, sv(S, "el", t, 40.0) * D)
    W, pole, f, E, xl = ra
    hrb, hrk = sword_hand2(f, xl, sv(S, "uln", t, 48.0) * D, sv(S, "ext", t, 8.0) * D, sv(S, "tw", t) * D)
    hb = hand_basis(hrb, hrk, 1.0)
    grip_cs = W + hb @ GRIP
    tip_cs = grip_cs + BLADE_TIP * hrb
    root_cs = grip_cs + BLADE_ROOT * hrb
    rot = sv(S, "rot", t) * D
    if rot != 0.0:
        Rr = Ry(rot)
        pv = np.array([S.get("pivx", 0.0), 0.0, S.get("pivz", 0.0)])
        def rp(p):
            return pv + Rr @ (p - pv)
        pb, tb = Rr @ pb, Rr @ tb
        po, co = rp(po), rp(co)
    P["pb"], P["tb"], P["po"], P["co"] = pb, tb, po, co
    P["tip"] = co + tb @ tip_cs
    P["root"] = co + tb @ root_cs
    P["grip"] = co + tb @ grip_cs
    P["wrist"] = co + tb @ W
    P["elbow_pt"] = co + tb @ E
    P["blade"] = tb @ hrb
    P["flat"] = tb @ hb[:, 0]
    P["f"] = tb @ f
    # the upper-arm frame the solver builds (y = upper arm, z = against the pole, x = y x z), in chest space
    S0 = SHOULDER_CS
    y1 = unit(E - S0)
    z1 = -unit(perp(pole, y1))
    x1 = np.cross(y1, z1)
    P["ua"] = np.column_stack([x1, y1, z1])
    y1f = unit(W - E)
    f1f = np.column_stack([x1, y1f, np.cross(x1, y1f)])
    hx = perp(hb[:, 0], y1f)
    tw_b = 0.0
    if np.linalg.norm(hx) > 0.2:
        a = unit(hx)
        # signed angle from x1 to a about y1f
        tw_b = np.arctan2(np.dot(np.cross(x1, a), y1f), np.dot(x1, a)) * 0.5
    fa = Raxis(y1f, tw_b) @ f1f
    P["fa"] = fa
    P["hand"] = hb
    P["elb"] = sv(S, "el", t, 40.0) * D
    P["bl_fa"] = float(np.arccos(np.clip(np.dot(unit(hrb), unit(W - E)), -1, 1)))
    # the wrist as the rig's own measure sees it: hand relative to the forearm bone (angle)
    P["wrist_rel"] = fa.T @ hb
    return P


def series(S, t0, t1, dt=1 / 120):
    ts = np.arange(t0, t1 + 1e-9, dt)
    out = [pose(S, t) for t in ts]
    return ts, out


def chain(S, t0=0.0, t1=None, dt=1 / 120):
    """peak angular speeds (rad/s) and their times for hips, chest, shoulder, elbow, wrist, tip speed (m/s)"""
    t1 = S["len"] if t1 is None else t1
    ts, ps = series(S, t0, t1, dt)
    n = len(ts)
    hips = np.zeros(n)
    chest = np.zeros(n)
    sh = np.zeros(n)
    el = np.zeros(n)
    wr = np.zeros(n)
    tip = np.zeros(n)
    for i in range(1, n):
        hips[i] = rot_angle(ps[i - 1]["pb"], ps[i]["pb"]) / dt
        chest[i] = rot_angle(ps[i - 1]["tb"], ps[i]["tb"]) / dt
        sh[i] = rot_angle(ps[i - 1]["ua"], ps[i]["ua"]) / dt
        el[i] = abs(ps[i]["elb"] - ps[i - 1]["elb"]) / dt
        wr[i] = rot_angle(ps[i - 1]["wrist_rel"], ps[i]["wrist_rel"]) / dt
        tip[i] = np.linalg.norm(ps[i]["tip"] - ps[i - 1]["tip"]) / dt
    return ts, {"hips": hips, "chest": chest, "shoulder": sh, "elbow": el, "wrist": wr, "tip": tip}, ps


def az_of(v):
    return np.degrees(np.arctan2(v[0], -v[2]))


def report(S, imp, win=(0.0, None), every=2, lo=None):
    ts, ch, ps = chain(S)
    print("   t    tip_az  rad    h  | bl_fa flat.v | hips chest shldr elbow wrist tip")
    azs = np.degrees(np.unwrap(np.radians([az_of(p["tip"]) for p in ps])))
    for i in range(0, len(ts), every):
        t = ts[i]
        p = ps[i]
        tip = p["tip"]
        v = (ps[min(i + 1, len(ts) - 1)]["tip"] - ps[max(i - 1, 0)]["tip"]) / (2 / 120)
        bl = unit(p["tip"] - p["root"])
        vperp = v - bl * np.dot(v, bl)
        fv = abs(np.dot(p["flat"], unit(vperp))) if np.linalg.norm(vperp) > 1.0 else -1
        print(f" {t:5.3f} {azs[i]:7.1f} {np.hypot(tip[0], tip[2]):5.2f} {tip[1]:5.2f} | {np.degrees(p['bl_fa']):5.1f} {fv:5.2f} | "
              f"{ch['hips'][i]:4.1f} {ch['chest'][i]:5.1f} {ch['shoulder'][i]:5.1f} {ch['elbow'][i]:5.1f} {ch['wrist'][i]:5.1f} {ch['tip'][i]:5.1f}")
    fps = 30.0
    t_in = S.get("in", 0.07)
    w0 = max(imp - 0.2, t_in)
    w1 = imp + 0.05
    sel = (ts >= w0) & (ts <= w1)
    print(f" chain window {w0:.3f}..{w1:.3f}; peaks (frames from impact at 30 fps):")
    names = ["hips", "chest", "shoulder", "elbow", "wrist", "tip"]
    peaks = {}
    for k in names:
        a = np.where(sel, ch[k], -1)
        i = int(np.argmax(a))
        peaks[k] = ts[i]
        print(f"   {k:9s} peak {a[i]:6.1f} at {ts[i]:.3f}  ({(ts[i] - imp) * fps:+.2f} f)")
    viol = 0
    order = names[:5]
    for i in range(1, 5):
        if (peaks[order[i]] - peaks[order[i - 1]]) * fps < -1.0:
            viol += 1
    print(f"   chain violations {viol}, spread hips->wrist {(peaks['wrist'] - peaks['hips']) * fps:.2f} f, chest/hips {np.max(np.where(sel, ch['chest'], -1)) / max(np.max(np.where(sel, ch['hips'], -1)), 1e-6):.2f}")
    return ts, ch, ps


def gd_array(arr, nd=3):
    return "[" + ", ".join(f"{x:.{nd}f}".rstrip("0").rstrip(".") if isinstance(x, float) else str(x) for x in arr) + "]"


def gd_raw(S, indent="\t\t\t\t"):
    lines = []
    lines.append(f'{indent}return {{"len": {S["len"]}, "in": {S["in"]}, "out": {S["out"]}, "ev": {gd_ev(S["ev"])},')
    keys = [k for k in S if k not in ("len", "in", "out", "ev", "feet")]
    for j, k in enumerate(keys):
        tail = "," if j < len(keys) - 1 else "}"
        lines.append(f'{indent}\t"{k}": {gd_array([float(x) for x in S[k]])}{tail}')
    return "\n".join(lines)


def gd_ev(ev):
    parts = []
    for k, v in ev.items():
        if isinstance(v, (list, tuple)):
            parts.append(f'"{k}": [{", ".join(str(x) for x in v)}]')
        else:
            parts.append(f'"{k}": {v}')
    return "{" + ", ".join(parts) + "}"
