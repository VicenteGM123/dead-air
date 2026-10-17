#!/usr/bin/env python3
"""A quick stick-figure view of the blows (python only, a fraction of a second per strip): the torso, the hips and an
approximation of the legs from the blow's feet plan, the sword arm and the blade (0.98 m), the shield arm and the shield's disc,
the ground. Views as the preview tool's: game (the gameplay camera, behind and above), side (his right), top, front.
Only for designing: the real check is tools/strike_strips.sh (Godot)."""
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from smodel import *

LEN_TH = 0.425
LEN_SH = 0.4125
HIP = np.array([0.112, -0.06, 0.0])          # pelvis frame, from the pelvis bone
HOME = {0: np.array([0.15, 0.04]), 1: np.array([-0.15, -0.06])}

VIEWS = {
    "game": (np.array([0.0, 2.3, 5.0]), np.array([0.0, 1.35, 0.0]), 55.0),
    "side": (np.array([3.9, 1.55, 0.0]), np.array([0.0, 1.0, 0.0]), 38.0),
    "front": (np.array([1.334, 1.55, -3.665]), np.array([0.0, 1.0, 0.0]), 38.0),
    "top": (np.array([0.017, 4.6, 0.5]), np.array([0.0, 1.0, 0.0]), 40.0),
    "sidel": (np.array([-3.9, 1.55, 0.0]), np.array([0.0, 1.0, 0.0]), 38.0),
}


def project(P, view):
    C, L, fov = VIEWS[view]
    f = unit(L - C)
    r = unit(np.cross(f, np.array([0.0, 1.0, 0.0])))
    u = np.cross(r, f)
    d = P - C
    z = max(float(np.dot(d, f)), 0.05)
    k = 1.0 / np.tan(np.radians(fov) * 0.5)
    return np.array([np.dot(d, r) / z * k, np.dot(d, u) / z * k])


def feet_at(plan, t, start=None):
    """approximate ankle positions (rig space, x y z) of the two feet at blow time t from a feet plan (moves) or baked curves"""
    if plan is None:
        plan = {}
    pos = {i: (HOME[i].copy() if start is None else np.array(start[i], float)) for i in (0, 1)}
    lift = {0: 0.0, 1: 0.0}
    for mv in plan.get("moves", []):
        i = int(mv["f"])
        t0, t1 = float(mv["t0"]), float(mv["t1"])
        tgt = np.array([float(mv["x"]), float(mv["z"])])
        if t <= t0:
            continue
        if mv.get("near") is not None and np.linalg.norm(pos[i] - tgt) < float(mv["near"]):
            continue
        s = min((t - t0) / max(t1 - t0, 0.02), 1.0)
        e = s * s * (3 - 2 * s)
        if s >= 1.0:
            pos[i] = tgt
        else:
            pos[i] = pos[i] + (tgt - pos[i]) * e
            lift[i] = float(mv.get("apex", 0.08)) * np.sin(np.pi * s ** 0.8)
    return {i: np.array([pos[i][0], 0.093 + lift[i], pos[i][1]]) for i in (0, 1)}


def leg(hip, ank, fwd):
    d = ank - hip
    L = np.linalg.norm(d)
    L = min(L, LEN_TH + LEN_SH - 1e-4)
    a = (LEN_TH ** 2 - LEN_SH ** 2 + L ** 2) / (2 * L)
    h = np.sqrt(max(LEN_TH ** 2 - a ** 2, 0.0))
    dn = unit(d)
    pole = unit(perp(fwd, dn))
    return hip + dn * a + pole * h


def body_points(S, t, feet=None):
    p = pose(S, t)
    pb, tb, po, co = p["pb"], p["tb"], p["po"], p["co"]
    out = {}
    out["pelvis"] = po
    out["chest"] = co
    out["neck"] = co + tb @ np.array([0.0, 0.255, 0.015])
    out["head"] = co + tb @ np.array([0.0, 0.42, 0.0])
    out["sh_r"] = co + tb @ SHOULDER_CS
    out["sh_l"] = co + tb @ (SHOULDER_CS * np.array([-1, 1, 1]))
    out["elbow_r"] = p["elbow_pt"]
    out["wrist_r"] = p["wrist"]
    out["grip"] = p["grip"]
    out["root"] = p["root"]
    out["tip"] = p["tip"]
    hl = np.array([sv(S, "hlx", t, -0.335), sv(S, "hly", t, -0.366), sv(S, "hlz", t, -0.08)])
    hf = unit(np.array([sv(S, "hfx", t, -1.0), sv(S, "hfy", t, 0.0), sv(S, "hfz", t, -0.35)]))
    hp = unit(np.array([sv(S, "hpx", t, -0.5), sv(S, "hpy", t, -0.2), sv(S, "hpz", t, 1.0)]))
    wl = co + tb @ (hl + np.array([0.0, 0.0, 0.0]))
    shl = out["sh_l"]
    # the left elbow: two bones towards the pole
    d = wl - shl
    L = min(np.linalg.norm(d), LEN_UA + LEN_FA - 1e-4)
    a = (LEN_UA ** 2 - LEN_FA ** 2 + L ** 2) / (2 * L)
    h = np.sqrt(max(LEN_UA ** 2 - a ** 2, 0.0))
    dn = unit(d)
    pl = unit(perp(tb @ hp, dn))
    out["elbow_l"] = shl + dn * a + pl * h
    out["wrist_l"] = wl
    out["shield_c"] = 0.5 * (out["elbow_l"] + wl) + (tb @ hf) * 0.06
    out["shield_n"] = tb @ hf
    rot = sv(S, "rot", t) * D
    # legs
    fwd = pb @ np.array([0.0, 0.0, -1.0])
    if feet is None:
        feet = feet_at(S.get("feet"), t)
    for i, sx in ((0, 1.0), (1, -1.0)):
        hip = po + pb @ (HIP * np.array([sx, 1, 1]))
        ank = feet[i]
        if "f%dx" % i in S:
            ank = np.array([sv(S, "f%dx" % i, t), sv(S, "f%dy" % i, t), sv(S, "f%dz" % i, t)])
            if rot != 0.0:
                pv = np.array([S.get("pivx", 0.0), 0.0, S.get("pivz", 0.0)])
                ank = pv + Ry(rot) @ (ank - pv)
        out["hip%d" % i] = hip
        out["ank%d" % i] = ank
        out["knee%d" % i] = leg(hip, ank, fwd)
        out["toe%d" % i] = ank + np.array([0.0, -0.08, 0.0]) + fwd * 0.2
    return out


def draw(ax, P, view, col_blade="#c02020", alpha=1.0):
    def seg(a, b, c, w):
        pa, pb_ = project(P[a] if isinstance(a, str) else a, view), project(P[b] if isinstance(b, str) else b, view)
        ax.plot([pa[0], pb_[0]], [pa[1], pb_[1]], color=c, lw=w, solid_capstyle="round", alpha=alpha)
    # ground grid
    for gx in np.arange(-2.0, 2.01, 0.5):
        a, b = project(np.array([gx, 0, -2.5]), view), project(np.array([gx, 0, 2.5]), view)
        ax.plot([a[0], b[0]], [a[1], b[1]], color="#d8d8c0", lw=0.5, zorder=0)
    for gz in np.arange(-2.5, 2.51, 0.5):
        a, b = project(np.array([-2.0, 0, gz]), view), project(np.array([2.0, 0, gz]), view)
        ax.plot([a[0], b[0]], [a[1], b[1]], color="#d8d8c0" if abs(gz) > 0.01 else "#a0a080", lw=0.5, zorder=0)
    skin = "#b07848"
    seg("pelvis", "chest", "#704020", 7)
    seg("chest", "neck", "#704020", 6)
    seg("sh_l", "sh_r", "#704020", 6)
    seg("hip0", "hip1", "#704020", 6)
    hd = project(P["head"], view)
    ax.add_patch(plt.Circle(hd, 0.035 / max(0.3, 1.0), color=skin, alpha=alpha))
    for i in (0, 1):
        c = "#406080" if i == 0 else "#80a0c0"
        seg("hip%d" % i, "knee%d" % i, c, 5)
        seg("knee%d" % i, "ank%d" % i, c, 4)
        seg("ank%d" % i, "toe%d" % i, c, 3)
    seg("sh_r", "elbow_r", skin, 4)
    seg("elbow_r", "wrist_r", skin, 4)
    seg("wrist_r", "grip", skin, 3)
    seg("sh_l", "elbow_l", "#8a6a4a", 4)
    seg("elbow_l", "wrist_l", "#8a6a4a", 4)
    # shield disc: an ellipse from 16 rim points
    n = unit(P["shield_n"])
    a1 = unit(perp(np.array([0.0, 1.0, 0.0]), n)) if abs(n[1]) < 0.95 else unit(perp(np.array([1.0, 0, 0]), n))
    a2 = np.cross(n, a1)
    rim = [project(P["shield_c"] + (a1 * np.cos(u) + a2 * np.sin(u)) * 0.39, view) for u in np.linspace(0, 2 * np.pi, 25)]
    rim = np.array(rim)
    ax.plot(rim[:, 0], rim[:, 1], color="#a08030", lw=1.2, alpha=alpha)
    # sword: grip, guard, blade
    seg("grip", "root", "#333333", 3)
    seg("root", "tip", col_blade, 2.5)


def strip(S, times, views=("game", "side", "top"), out="strip.png", title="", feet_fn=None, tile=2.0):
    n = len(times)
    fig, axs = plt.subplots(len(views), n, figsize=(tile * n * 0.62, tile * len(views)), squeeze=False)
    for j, t in enumerate(times):
        feet = feet_fn(t) if feet_fn else None
        P = body_points(S, t, feet)
        for i, v in enumerate(views):
            ax = axs[i][j]
            draw(ax, P, v)
            lim = {"game": (0.55, 0.5, 0.05), "side": (0.75, 0.7, -0.05), "front": (0.75, 0.7, -0.05), "top": (0.9, 0.9, 0.0), "sidel": (0.75, 0.7, -0.05)}[v]
            ax.set_xlim(-lim[0], lim[0])
            ax.set_ylim(-lim[1] + lim[2], lim[1] + lim[2])
            ax.set_aspect("equal")
            ax.axis("off")
            if i == 0:
                ax.set_title(f"{t:.3f}", fontsize=7)
    if title:
        fig.suptitle(title, fontsize=9)
    plt.subplots_adjust(left=0.01, right=0.99, top=0.93, bottom=0.01, wspace=0.02, hspace=0.02)
    fig.savefig(out, dpi=95)
    plt.close(fig)
    return out
