#!/usr/bin/env python3
"""The moveset of Heracles with the long sword (docs/ANIMATION.md 4.9). The blows, defined once:
    combo A  a1 diagonal forehand (high right -> low left, the left foot steps in), a2 rising backhand (low left -> high
             right, the hips turn back), a3 wide horizontal forehand at chest height (a pivot step), a4 the finisher: a
             stepping overhead chop that ends with the blade struck into the ground in front of him (P8)
    combo B  b1 rising diagonal out of the low carry (low right -> high left), b2 descending backhand (high left -> low
             right), b3 the finisher: a lunging thrust (a long step, the blade straight at the foe, the shield flung back)
    dash     a leaping overhead slash out of the sprint that lands with weight (P8)
    heavy    the charged spin: the coil of P5 (wide and low, the blade back at his left), one clean level circle
Each blow: the body (pelvis and chest turns, the pelvis' shift, the head), the shield arm, the feet, and THE PATH OF THE
BLADE: keys of where the grip is (rig space), where the blade points and which way its flat (the back of the hand) faces.
Inside a cut the keys lie on a PLANE: the blade turns about the plane's normal by an angle that is eased from key to key (the
cut sweeps one plane, the edge leads, the flat faces the normal: it never turns about its own axis); between planes the blade
and its flat are slerped (the wind-up and the recovery, where the hand turns over like a doorknob). The grip travels on an arc
round the shoulder. The sword arm's seven joint angles are SOLVED along that path (solve.py; every 1/120 s), each sample from
the one before (continuation: the hand never jumps), within the wrist's limits, the arm and the blade clear of the torso and
the thighs, the tip over the ground.
    python3 moveset.py [blow ...] [--resolve] [--report] [--view]
        builds the blows (the solved arm is cached in keys_cache_moveset.json by a hash of each blow's definition), prints a
        check line per blow and writes strike_data.gd.txt (all blows only); --view draws mview strips into ../../shots/py/
    python3 splice_strike.py    puts strike_block.gd.txt + strike_data.gd.txt into game/scripts/gfx/rig_heracles.gd
Angles in degrees, lengths in metres, rig space: x his right, y up, -z ahead (az: degrees from ahead, + to his right; el + up).
"""
import sys, os, json, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import solve as SV
from smodel import *
from solve import solve, arm_state, body_at, blade_clearance
from export import export
from defs import ankle_on, pin_of, rot_curve

# the wrist: the blade 30.5 (full ulnar deviation) to 88 degrees (radial) off the forearm's line; the fist's roll +-45
SV.LIM["uln"] = (2.0, 59.5)
SV.LIM["ext"] = (-60.0, 60.0)
SV.LIM["tw"] = (-110.0, 110.0)    # the forearm: pronation (-) and supination (+) from the thumb-up neutral
SV.LIM["r"] = (-95.0, 100.0)      # the upper arm's axial rotation (external - to internal +)
SV.LIM["el"] = (8.0, 140.0)
CACHE = os.path.join(HERE, "keys_cache_moveset.json")
VER = 7                          # bump when the sampling or the solving below changes
SHOTS = os.path.normpath(os.path.join(HERE, "..", "..", "shots", "py"))


def dirv(az, el):
    a, e = az * D, el * D
    return np.array([np.cos(e) * np.sin(a), np.sin(e), -np.cos(e) * np.cos(a)])


def az_el(v):
    v = unit(v)
    return float(np.degrees(np.arctan2(v[0], -v[2]))), float(np.degrees(np.arcsin(np.clip(v[1], -1, 1))))


def vec(x):
    """(az, el) -> unit vector; a 3-vector -> itself, normalised"""
    x = np.asarray(x, float)
    return dirv(x[0], x[1]) if x.shape == (2,) else unit(x)


def slerp(a, b, s):
    a, b = unit(a), unit(b)
    d = float(np.clip(np.dot(a, b), -1.0, 1.0))
    ang = np.arccos(d)
    if ang < 1e-6:
        return a
    if ang > np.pi - 1e-3:
        ax = unit(np.cross(a, np.array([0.0, 1.0, 0.0]))) if abs(a[1]) < 0.9 else unit(np.cross(a, np.array([1.0, 0.0, 0.0])))
        return Raxis(ax, ang * s) @ a
    return (np.sin((1 - s) * ang) * a + np.sin(s * ang) * b) / np.sin(ang)


def roll_ref(blade):
    """the reference across the blade the roll is measured from: "up" made perpendicular to it (the blade's side when it
    points nearly straight up or down)"""
    r = perp(np.array([0.0, 1.0, 0.0]), unit(blade))
    if np.linalg.norm(r) < 0.2:
        r = perp(np.array([0.0, 0.0, -1.0]), unit(blade))
    return unit(r)


def roll_of(flat, blade):
    b = unit(blade)
    r = roll_ref(b)
    f = unit(perp(flat, b))
    return float(np.arctan2(np.dot(np.cross(r, f), b), np.dot(r, f)))


def flat_of(psi, blade):
    b = unit(blade)
    return Raxis(b, psi) @ roll_ref(b)


def ease(kind, s):
    s = min(max(s, 0.0), 1.0)
    if kind == "lin":
        return s
    if kind == "in":            # slow out of the key before, fast into this one (an acceleration)
        return s * s
    if kind == "in3":
        return s * s * s
    if kind == "out":           # fast out of the key before, settling into this one
        return 1 - (1 - s) ** 2
    if kind == "out3":
        return 1 - (1 - s) ** 3
    if kind == "cut":           # a cut: accelerates hard, near full speed at the end (the hold that follows brakes it)
        return s ** 2.2 * (1.25 - 0.25 * s) if s < 1 else 1.0
    return s * s * (3 - 2 * s)  # "io"


class Plane:
    """The plane of a cut: `imp` the blade's direction at the impact, `side` roughly the direction a quarter turn before it
    (the blade turns from `side` to `imp`: positive angles). v(th) = the blade at angle th (degrees; 0 = side, 90 = imp).
    `back`: which way the back of the hand (the flat) faces: -1 the true edge leads while th grows (default), +1 the other."""

    def __init__(self, imp, side, back=-1.0):
        self.F = vec(imp)
        self.Dv = unit(perp(vec(side), self.F))
        self.n = unit(np.cross(self.Dv, self.F))
        self.back = back

    def v(self, th):
        a = th * D
        return np.cos(a) * self.Dv + np.sin(a) * self.F

    def flat(self):
        return self.n * self.back


class K:
    """A key of the blade's path at blow time t.
    grip: (x, y, z) rig space; or ("sh", az, el, reach): from the shoulder of that moment; or (plane, phi, rho): from the
          shoulder along the plane's direction phi (the arm swings in the plane round the moving shoulder)
    blade: (az, el), a vector, or (plane, th)
    flat: (az, el), a vector or None (on a plane: the plane's back of the hand; else free between the keys around it)
    ease: how the grip gets here from the key before; bease: the blade's own easing (a blade that lags the hand and whips
    through: "in3"); pole: the side the elbow bends towards (rig space, weak); tip_min: the lowest the tip may go."""

    def __init__(self, t, grip, blade, flat=None, ease="io", bease=None, pole=None, tip_min=0.05, fsig=0.15, fease="io", roll=0,
                 js=False, x=None):
        self.t = t
        self.fease = fease
        self.roll = roll
        self.js = js                # the segment into this key runs in joint space (a wind-up or a recovery: the arm turns over
        self.x = None if x is None else np.asarray(x, float)    # freely between two poses it can hold); x: this key's joints
        self.gplane = None
        self.gsh = None
        self.gabs = None
        if isinstance(grip, tuple) and len(grip) == 3 and isinstance(grip[0], Plane):
            self.gplane, self.phi, self.rho = grip
        elif isinstance(grip, tuple) and len(grip) == 4 and grip[0] == "sh":
            self.gsh = (dirv(grip[1], grip[2]), float(grip[3]))
        else:
            self.gabs = np.asarray(grip, float)
        self.plane = None
        self.th = None
        if isinstance(blade, tuple) and len(blade) == 2 and isinstance(blade[0], Plane):
            self.plane, self.th = blade
            self.bvec = self.plane.v(self.th)
        else:
            self.bvec = vec(blade)
        if flat is None and self.plane is not None:
            self.fvec = self.plane.flat()
        else:
            self.fvec = None if flat is None else vec(flat)
        self.ease = ease
        self.bease = bease
        self.pole = pole
        self.tip_min = tip_min
        self.fsig = fsig

    def arm(self, sh):
        """the grip's offset from the shoulder `sh` (rig space)"""
        if self.gplane is not None:
            return self.gplane.v(self.phi) * self.rho
        if self.gsh is not None:
            return self.gsh[0] * self.gsh[1]
        return self.gabs - sh


class Blow:
    def __init__(self, name, length, tin, tout, ev, act):
        self.name = name
        self.S = {"len": length, "in": tin, "out": tout, "ev": ev}
        self.keys = []
        self.act = act
        self.start_guess = [-20, 15, 40, 40, 30, 0, 60]
        self.chained = False
        self.prev = None

    def c(self, nm, *kv):
        self.S[nm] = [float(x) for x in kv]

    def k(self, *a, **kw):
        self.keys.append(K(*a, **kw))

    def body(self):
        """the body curves the arm is solved against (a whole-body spin, `rot`, turns everything rigidly about the pivot: the
        joints do not change with it, so it is left out and the targets are given in the unturned frame)"""
        return {k: v for k, v in self.S.items() if k not in ("feet", "rot", "pivx", "pivz")}

    # ---- the path ---------------------------------------------------------------------------------------------------
    def seg(self, t):
        ks = self.keys
        if t <= ks[0].t:
            return ks[0], ks[0], 1.0
        if t >= ks[-1].t:
            return ks[-1], ks[-1], 1.0
        i = 0
        while t > ks[i + 1].t:
            i += 1
        A, B = ks[i], ks[i + 1]
        return A, B, (t - A.t) / max(B.t - A.t, 1e-9)

    def flat_span(self, t):
        """the keys with a flat on either side of t (None where there is none)"""
        before = [k for k in self.keys if k.fvec is not None and k.t <= t + 1e-9]
        after = [k for k in self.keys if k.fvec is not None and k.t > t + 1e-9]
        fa = before[-1] if before else None
        fb = after[0] if after else None
        if fa is not None and fb is None and abs(fa.t - t) < 1e-9:
            return fa, fa
        return fa, fb

    def shoulder(self, Bd, t):
        b = body_at(Bd, t)
        return b["co"] + b["tb"] @ SHOULDER_CS, b

    def targets(self, Bd, t):
        A, B, s = self.seg(t)
        e = ease(B.ease, s)
        eb = ease(B.bease or B.ease, s)
        sh, body = self.shoulder(Bd, t)
        if A.gplane is not None and A.gplane is B.gplane:
            grip = sh + A.gplane.v((1 - e) * A.phi + e * B.phi) * ((1 - e) * A.rho + e * B.rho)
        else:
            sha, _ = self.shoulder(Bd, A.t)
            shb, _ = self.shoulder(Bd, B.t)
            ra, rb = A.arm(sha), B.arm(shb)
            grip = sh + slerp(ra, rb, e) * ((1 - e) * np.linalg.norm(ra) + e * np.linalg.norm(rb))
        sig = None
        if A.plane is not None and A.plane is B.plane:
            th = (1 - eb) * A.th + eb * B.th
            blade = A.plane.v(th)
            flat = A.plane.flat()
            sig = min(A.fsig, B.fsig)
        else:
            blade = slerp(A.bvec, B.bvec, eb)
            # the flat is its own channel: keyed on the keys that have one, slerped across the keys without (the hand turns
            # over through a whole wind-up, not in the last frames of one segment)
            fa, fb = self.flat_span(t)
            if fa is not None and fb is not None:
                ka, kb = fa, fb
                u = (t - ka.t) / max(kb.t - ka.t, 1e-9)
                ef = ease(kb.fease, u)
                # the hand rolls about the blade: the roll angle of each key's flat (from "up" across the blade at that key)
                # is interpolated, not the vectors (a slerp of two flats can pass along the blade and flip)
                pa = roll_of(ka.fvec, ka.bvec)
                pb = roll_of(kb.fvec, kb.bvec)
                d = (pb - pa + np.pi) % (2 * np.pi) - np.pi
                if kb.roll:
                    d = d % (2 * np.pi) if kb.roll > 0 else -((-d) % (2 * np.pi))
                flat = flat_of(pa + d * ef, blade)
                sig = (1 - ef) * ka.fsig + ef * kb.fsig
            elif fa is not None or fb is not None:
                kk = fa if fa is not None else fb
                flat = kk.fvec
                sig = kk.fsig + 1.5
            else:
                flat = None
        if flat is not None:
            flat = perp(flat, blade)
            flat = unit(flat) if np.linalg.norm(flat) > 0.25 else None
        pole = B.pole if B.pole is not None else A.pole
        tip_min = min(A.tip_min, B.tip_min)
        return {"grip": grip, "blade": blade, "flat": flat, "sig": sig, "pole": pole, "tip_min": tip_min}, body

    def times(self):
        L = self.S["len"]
        ts = set(round(float(x), 5) for x in np.arange(0.0, L + 1e-9, 1 / 120))
        ts |= set(round(k.t, 5) for k in self.keys if 0 <= k.t <= L)
        ts.add(round(L, 5))
        return sorted(ts)

    def sig(self):
        def enc(v):
            if isinstance(v, np.ndarray):
                return [round(float(x), 5) for x in v]
            if isinstance(v, Plane):
                return [enc(v.F), enc(v.Dv), v.back]
            return v
        ks = [{k: enc(v) for k, v in vars(kk).items()} for kk in self.keys]
        return hashlib.md5(json.dumps([VER, ks, self.body(), SV.LIM, self.start_guess], default=str, sort_keys=True).encode()).hexdigest()

    # ---- solving ----------------------------------------------------------------------------------------------------
    def tgt_of(self, T):
        tgt = {"grip": T["grip"], "blade": T["blade"], "tip_min": T["tip_min"], "blade_clear": 0.025}
        if T["flat"] is not None:
            tgt["flat_vec"] = T["flat"]
            tgt["flat_sig"] = T["sig"]
        if T["pole"] is not None:
            tgt["pole"] = np.asarray(T["pole"], float)
        return tgt

    def solve(self, cache, force=False):
        sg = self.sig()
        if not force and cache.get(self.name, {}).get("sig") == sg:
            self._assign(cache[self.name]["sol"])
            return
        Bd = self.body()
        rng = np.random.default_rng(11)
        ts = self.times()
        sol = []
        prev = None
        self.costs = []
        xkey = {}
        xat = {}
        for t in ts:
            T, body = self.targets(Bd, t)
            tgt = self.tgt_of(T)
            A, Bk, s = self.seg(t)
            if prev is not None and Bk.js and Bk is not A:
                # a joint-space segment: the joints ease from the key before to this key's own solved pose
                if id(Bk) not in xkey:
                    xkey[id(Bk)] = Bk.x if Bk.x is not None else self.solve_key(Bk, xat[round(A.t, 5)], Bd, rng)
                xa = xat[round(A.t, 5)]
                x = xa + (xkey[id(Bk)] - xa) * ease(Bk.ease, s)
                tg = {k: v for k, v in tgt.items()}
                c = float(SV.residual(x, body, tg) @ SV.residual(x, body, tg))
                self.costs.append((t, c))
                prev = np.array(x, float)
                xat[round(t, 5)] = prev
                sol.append([round(float(t), 5)] + [round(float(v), 2) for v in x])
                continue
            if prev is None:
                x0 = np.array(self.start_guess, float)
                best = None
                if self.chained:
                    # the blow starts where the one before it is when it chains (the same joints: no pop)
                    best = solve(body, dict(tgt, prior=x0, prior_w=2.0), x0, iters=150)
                else:
                    for st in [x0] + [x0 + rng.normal(0, 25.0, 7) for _ in range(40)]:
                        x, c = solve(body, dict(tgt, prior=x0, prior_w=0.05), st, iters=150)
                        if best is None or c < best[1]:
                            best = (x, c)
                x = best[0]
            else:
                tgt["prior"] = prev
                tgt["prior_w"] = 0.6
                tgt["win"] = [20, 20, 25, 20, 15, 15, 25]
                best = None
                for st in (prev, prev + rng.normal(0, 3.0, 7)):
                    xx, c = solve(body, tgt, st, iters=60)
                    if best is None or c < best[1]:
                        best = (xx, c)
                x = best[0]
            c = float(SV.residual(x, body, {k: v for k, v in tgt.items() if k not in ("prior", "prior_w", "win")}) @
                      SV.residual(x, body, {k: v for k, v in tgt.items() if k not in ("prior", "prior_w", "win")}))
            self.costs.append((t, c))
            prev = np.array(x, float)
            xat[round(t, 5)] = prev
            sol.append([round(float(t), 5)] + [round(float(v), 2) for v in x])
        cache[self.name] = {"sig": sg, "sol": sol, "costs": [[round(a, 4), round(b, 2)] for a, b in self.costs]}
        worst = max(self.costs, key=lambda a: a[1])
        print(f"  solved {self.name}: {len(ts)} samples, worst cost {worst[1]:.2f} at {worst[0]:.3f}")
        self._assign(sol)

    def solve_key(self, K, x_ref, Bd, rng):
        """the joints of key K: the lowest-cost pose (many starts), among the near-best the one closest to x_ref"""
        T, body = self.targets(Bd, K.t)
        tgt = self.tgt_of(T)
        cands = []
        x, _ = solve(body, dict(tgt, prior=x_ref, prior_w=0.3), x_ref, iters=150)
        cands.append(x)
        for st in SV.rand_starts(30, rng, x_ref):
            x, _ = solve(body, tgt, st, iters=120)
            cands.append(x)
        scored = []
        for x in cands:
            r = SV.residual(x, body, tgt)
            scored.append((float(r @ r), float(np.linalg.norm((np.asarray(x) - x_ref) / np.array([60, 60, 60, 60, 30, 40, 60]))), x))
        best = min(a[0] for a in scored)
        near = [a for a in scored if a[0] <= best + 0.6]
        near.sort(key=lambda a: a[1])
        return np.asarray(near[0][2], float)

    def _assign(self, sol):
        NAMES = ["az", "e", "r", "el", "uln", "ext", "tw"]
        # the runtime samples the curves at 120 Hz: export at 60 Hz plus the keys (the monotone cubic in between is smooth)
        keep = set(round(k.t, 5) for k in self.keys)
        rows = [r for r in sol if abs(r[0] * 60 - round(r[0] * 60)) < 1e-3 or round(r[0], 5) in keep or r is sol[-1]]
        for j, nm in enumerate(NAMES):
            out = []
            for row in rows:
                out += [row[0], row[1 + j]]
            self.S[nm] = out
        self.sol = sol


BODY_DEFAULT = {"pp": 1.1, "cp": 4.0, "hlx": -0.335, "hly": -0.366, "hlz": -0.08, "hpx": -0.5, "hpy": -0.2, "hpz": 1.0,
                "hfx": -1.0, "hfy": 0.0, "hfz": -0.35}


def joints_at(prev, t):
    """the solved joint angles of blow `prev` at its time t (linear between the samples)"""
    T = np.array([r[0] for r in prev.sol])
    X = np.array([r[1:] for r in prev.sol])
    return [float(np.interp(t, T, X[:, j])) for j in range(7)]


def chain_from(B, prev, t0):
    """blow B starts where `prev` is at its time t0 (the combo window): returns (grip, blade, flat) of that pose for B's first
    key and sets B's start guess to prev's joints there; B.at(nm) gives prev's body curves there for B's first keys"""
    B.chained = True
    B.prev = (prev, t0)
    B.start_guess = joints_at(prev, t0)
    p = pose(prev.S, t0)
    return p["grip"], unit(p["tip"] - p["grip"]), p["flat"]


def at(prev_t, nm):
    prev, t0 = prev_t
    return round(float(sv(prev.S, nm, t0, BODY_DEFAULT.get(nm, 0.0))), 4)


def shield_at(prev_t):
    return (tuple(at(prev_t, "hl" + c) for c in "xyz"), tuple(at(prev_t, "hp" + c) for c in "xyz"), tuple(at(prev_t, "hf" + c) for c in "xyz"))


# =================================================================================================================================
# The shield arm (chest space): [(t, wrist, elbow pole, facing)] -> hl*, hp*, hf* curves
SH_READY = ((-0.335, -0.366, -0.08), (-0.5, -0.2, 1.0), (-1.0, 0.0, -0.35))
SH_TUCK = ((-0.20, -0.20, -0.30), (-0.8, -0.5, 0.5), (-0.45, 0.10, -0.90))      # tucked to the chest, the shield facing ahead
SH_OUT = ((-0.42, -0.14, -0.10), (-0.6, -0.6, 0.5), (-0.85, 0.10, -0.50))       # swung out (a counterweight)
SH_BACK = ((-0.46, -0.30, 0.16), (-0.4, -0.5, 1.0), (-0.95, 0.0, 0.25))         # flung back (the big blows)


def shield(S, keys):
    for nm in ("hl", "hp", "hf"):
        for c in "xyz":
            S[nm + c] = []
    for (t, w, p, f) in keys:
        for ci, c in enumerate("xyz"):
            S["hl" + c] += [float(t), float(w[ci])]
            S["hp" + c] += [float(t), float(p[ci])]
            S["hf" + c] += [float(t), float(f[ci])]


# The carry the blows start from and end in (the reference: the sword arm relaxed and low, the fist at the hip, the long blade
# trailing back and down, the tip a hand over the ground behind him, the flat facing out). STOW owns the carry itself; this is
# the pose the blows meet it in.
# (the joints of that carry, solved once: the arm hangs, turned out so the palm faces out and the thumb back; every blow that
# starts from the carry starts on these joints, every blow ends on them)
X_CARRY = [-82.0, 18.0, -95.0, 22.0, 59.5, 60.0, -20.0]
CARRY_GRIP = (0.346, 0.84, 0.081)
CARRY_BLADE = (150.0, -37.3)
CARRY_FLAT = (-151.6, 34.5)       # the back of the hand towards the thigh: the palm out, the thumb back (the blade trails)


def carry_key(B, t, **kw):
    """the blow's last key: back to the carry, in joint space"""
    B.k(t, CARRY_GRIP, CARRY_BLADE, CARRY_FLAT, js=True, x=X_CARRY, fsig=0.4, **kw)


def carry_start(B):
    """the blow's first key: the carry (its joints are the start)"""
    B.start_guess = list(X_CARRY)
    B.chained = True
    B.k(0.0, CARRY_GRIP, CARRY_BLADE, CARRY_FLAT, fsig=0.4)


# =================================================================================================================================
def a1():
    """A1: the diagonal forehand, high right to low left, the left foot steps in (the first blow of combo A)."""
    B = Blow("a1", 0.60, 0.07, 0.22, {"swing": 0.13, "impact": 0.175, "step": [0.17, 0.56]}, (0.135, 0.25))
    # the body: coil right (pelvis -16, chest -42: the X-factor 26), then the hips lead the turn left, the chest follows
    B.c("py", 0.0, 0, 0.11, -16, 0.13, -17, 0.165, 10, 0.20, 24, 0.30, 32, 0.42, 20, 0.60, 0)
    B.c("cy", 0.0, 0, 0.11, -40, 0.135, -42, 0.18, 22, 0.21, 42, 0.30, 58, 0.42, 34, 0.60, 0)
    B.c("pp", 0.0, 1.1, 0.12, 4, 0.18, -6, 0.30, -6, 0.45, -1, 0.60, 1.1)
    B.c("cp", 0.0, 4, 0.11, 10, 0.135, 10, 0.19, -14, 0.30, -20, 0.42, -10, 0.60, 4)
    B.c("cr", 0.0, 0, 0.11, 7, 0.135, 7, 0.19, -6, 0.32, -9, 0.45, -3, 0.60, 0)
    B.c("pr", 0.0, 0, 0.12, 3, 0.19, -4, 0.32, -4, 0.60, 0)
    B.c("px", 0.0, 0, 0.12, 0.04, 0.19, -0.04, 0.32, -0.06, 0.46, -0.02, 0.60, 0)
    B.c("pz", 0.0, 0, 0.12, 0.05, 0.135, 0.05, 0.19, -0.14, 0.32, -0.18, 0.46, -0.07, 0.60, 0)
    B.c("pdy", 0.0, 0, 0.12, -0.04, 0.135, -0.05, 0.19, -0.12, 0.32, -0.15, 0.46, -0.05, 0.60, 0)
    B.c("hy", 0.0, 0, 0.12, -6, 0.17, -2, 0.21, 6, 0.32, 14, 0.46, 6, 0.60, 0)
    B.c("hp", 0.0, 0, 0.12, 2, 0.21, -6, 0.32, -8, 0.60, 0)
    shield(B.S, [(0.0,) + SH_READY,
                 (0.12,) + SH_OUT,
                 (0.14,) + SH_OUT,
                 (0.21,) + SH_TUCK,
                 (0.34,) + SH_TUCK,
                 (0.50,) + SH_READY,
                 (0.60,) + SH_READY])
    P = Plane((0, -8), (70, 45))
    carry_start(B)
    B.k(0.06, (0.66, 1.18, 0.15), (162, -6), None, ease="io", js=True)
    B.k(0.125, (P, 0, 0.40), (P, -80), ease="out", pole=(1, -0.3, 0.4), js=True)
    B.k(0.14, (P, 5, 0.40), (P, -75), ease="out", pole=(1, -0.3, 0.4))
    B.k(0.18, (P, 130, 0.56), (P, 90), ease="in", bease="in", pole=(0.6, -1, 0))
    # (INTEGRATE: the follow-through over 3 frames, not 1-2: the cut reads; a 2-3 frame hold, then the recovery at once: the old
    # 11 frames of slow settle are gone)
    B.k(0.21, (P, 160, 0.55), (P, 125), ease="out", pole=(0.3, -1, 0))
    B.k(0.235, (P, 165, 0.54), (P, 132), ease="out", pole=(0.3, -1, 0))
    B.k(0.31, (-0.16, 0.86, -0.44), (-75, -36), None, ease="io", pole=(0.2, -1, 0.3), tip_min=0.15)
    B.k(0.42, (0.05, 0.92, -0.38), (0, -40), None, ease="io", tip_min=0.15, js=True)
    B.k(0.51, (0.30, 0.88, -0.15), (95, -38), None, ease="io", tip_min=0.15, js=True)
    carry_key(B, 0.60)
    B.S["feet"] = {"moves": [{"f": 1, "t0": 0.04, "t1": 0.17, "x": -0.18, "z": -0.44, "yaw": 8.0, "apex": 0.10, "th": 12.0},
                             {"f": 1, "t0": 0.44, "t1": 0.58, "x": -0.15, "z": -0.08, "yaw": 4.0, "apex": 0.07, "th": 6.0}],
                   "pitch0": [0.0, 0.0, 0.13, 0.0, 0.24, -32.0, 0.36, -32.0, 0.52, -4.0],
                   "follow0": [0.0, 0.0, 0.12, 0.0, 0.25, 0.7, 0.4, 0.7]}
    return B


A1_OPEN = 0.28


def a2(built):
    """A2: the rising backhand, low left to high right, the hips turning back (out of A1's follow-through)."""
    B = Blow("a2", 0.52, 0.06, 0.22, {"swing": 0.075, "impact": 0.115, "step": [0.12, 0.50]}, (0.075, 0.19))
    g0, b0, f0 = chain_from(B, built["a1"], A1_OPEN)
    pt = B.prev
    # the body: a little more coil to the left, then the hips drive right, the chest follows and overshoots
    B.c("py", 0.0, at(pt, "py"), 0.06, 36, 0.085, 30, 0.13, -14, 0.18, -24, 0.28, -18, 0.40, -6, 0.52, 0)
    B.c("cy", 0.0, at(pt, "cy"), 0.06, 66, 0.09, 60, 0.14, -30, 0.19, -50, 0.28, -40, 0.40, -12, 0.52, 0)
    B.c("pp", 0.0, at(pt, "pp"), 0.07, -4, 0.14, -6, 0.28, -3, 0.52, 1.1)
    B.c("cp", 0.0, at(pt, "cp"), 0.07, -12, 0.14, -14, 0.22, -10, 0.36, -2, 0.52, 4)
    B.c("cr", 0.0, at(pt, "cr"), 0.07, -10, 0.14, 6, 0.24, 8, 0.40, 2, 0.52, 0)
    B.c("pr", 0.0, at(pt, "pr"), 0.08, -4, 0.14, 4, 0.30, 3, 0.52, 0)
    B.c("px", 0.0, at(pt, "px"), 0.08, -0.06, 0.14, 0.04, 0.30, 0.05, 0.44, 0.01, 0.52, 0)
    B.c("pz", 0.0, at(pt, "pz"), 0.08, -0.17, 0.14, -0.20, 0.30, -0.16, 0.44, -0.05, 0.52, 0)
    B.c("pdy", 0.0, at(pt, "pdy"), 0.08, -0.14, 0.14, -0.12, 0.30, -0.11, 0.44, -0.04, 0.52, 0)
    B.c("hy", 0.0, at(pt, "hy"), 0.06, 16, 0.10, 4, 0.14, -8, 0.24, -14, 0.40, -4, 0.52, 0)
    B.c("hp", 0.0, at(pt, "hp"), 0.10, -6, 0.20, -2, 0.40, 0, 0.52, 0)
    shield(B.S, [(0.0,) + shield_at(pt),
                 (0.07, (-0.30, -0.30, -0.24), (-0.8, -0.5, 0.4), (-0.6, 0.0, -0.8)),
                 (0.14,) + SH_OUT,
                 (0.26,) + SH_OUT,
                 (0.42,) + SH_READY,
                 (0.52,) + SH_READY])
    # the false edge leads (the pendulum: the arm swings back up the way A1 came down, the hand does not turn over; the
    # blade leads the forearm)
    P = Plane((0, -2), (-90, -40), back=1.0)
    B.k(0.0, g0, b0, f0, fsig=0.3)
    B.k(0.07, (P, -5, 0.50), (P, 35), ease="io")
    B.k(0.078, (P, -2, 0.50), (P, 38), ease="out")
    B.k(0.115, (P, 70, 0.56), (P, 108), ease="in", bease="in")
    B.k(0.145, (P, 112, 0.56), (P, 150), ease="out")
    B.k(0.18, (P, 120, 0.55), (P, 160), ease="out")
    B.k(0.27, (0.48, 1.58, -0.05), (125, 55), None, ease="out")
    carry_key(B, 0.52)
    B.S["feet"] = {"moves": [{"f": 0, "t0": 0.03, "t1": 0.12, "x": 0.20, "z": -0.30, "yaw": -8.0, "apex": 0.09, "th": 10.0},
                             {"f": 1, "t0": 0.30, "t1": 0.44, "x": -0.15, "z": -0.06, "yaw": 4.0, "apex": 0.07, "th": 6.0, "near": 0.12},
                             {"f": 0, "t0": 0.36, "t1": 0.50, "x": 0.15, "z": 0.04, "yaw": -4.0, "apex": 0.07, "th": 6.0}],
                   "pitch1": [0.0, 0.0, 0.10, 0.0, 0.18, -26.0, 0.28, -26.0, 0.34, 0.0],
                   "follow1": [0.0, 0.0, 0.08, 0.0, 0.20, 0.6, 0.3, 0.6]}
    return B


A2_OPEN = 0.19


def a3(built):
    """A3: the wide horizontal forehand at chest height, a pivot step (out of A2's follow-through)."""
    B = Blow("a3", 0.60, 0.06, 0.22, {"swing": 0.10, "impact": 0.14, "step": [0.15, 0.58]}, (0.10, 0.22))
    g0, b0, f0 = chain_from(B, built["a2"], A2_OPEN)
    pt = B.prev
    # the coil to the right, then the hips pivot left (the right foot steps round), the chest follows past 70
    B.c("py", 0.0, at(pt, "py"), 0.08, -28, 0.10, -30, 0.14, 8, 0.18, 32, 0.28, 40, 0.42, 22, 0.60, 0)
    B.c("cy", 0.0, at(pt, "cy"), 0.08, -58, 0.105, -62, 0.15, 20, 0.19, 58, 0.28, 72, 0.42, 36, 0.60, 0)
    B.c("pp", 0.0, at(pt, "pp"), 0.09, 2, 0.15, -6, 0.30, -5, 0.60, 1.1)
    B.c("cp", 0.0, at(pt, "cp"), 0.09, 2, 0.15, -10, 0.30, -12, 0.45, -4, 0.60, 4)
    B.c("cr", 0.0, at(pt, "cr"), 0.09, 4, 0.15, -4, 0.30, -6, 0.60, 0)
    B.c("pr", 0.0, at(pt, "pr"), 0.09, 3, 0.15, -3, 0.30, -3, 0.60, 0)
    B.c("px", 0.0, at(pt, "px"), 0.09, 0.06, 0.15, -0.02, 0.30, -0.06, 0.46, -0.02, 0.60, 0)
    B.c("pz", 0.0, at(pt, "pz"), 0.09, -0.10, 0.15, -0.16, 0.30, -0.18, 0.46, -0.06, 0.60, 0)
    B.c("pdy", 0.0, at(pt, "pdy"), 0.09, -0.12, 0.15, -0.15, 0.30, -0.14, 0.46, -0.05, 0.60, 0)
    B.c("hy", 0.0, at(pt, "hy"), 0.08, -12, 0.12, -4, 0.16, 8, 0.28, 16, 0.46, 6, 0.60, 0)
    B.c("hp", 0.0, at(pt, "hp"), 0.10, -2, 0.20, -4, 0.45, 0, 0.60, 0)
    shield(B.S, [(0.0,) + shield_at(pt),
                 (0.09,) + SH_TUCK,
                 (0.16,) + SH_OUT,
                 (0.30,) + SH_OUT,
                 (0.48,) + SH_READY,
                 (0.60,) + SH_READY])
    # a level plane: the blade sweeps right to left round him; the palm down, the blade leading the forearm (a palm-up forehand at
    # this height is out of the wrist's reach)
    P = Plane((0, -6), (90, -6), back=1.0)
    B.k(0.0, g0, b0, f0, fsig=0.3)
    B.k(0.09, (P, -60, 0.60), (P, -10), ease="io", js=True)
    B.k(0.097, (P, -58, 0.60), (P, -8), ease="out")
    B.k(0.14, (P, 40, 0.60), (P, 90), ease="in", bease="in")
    B.k(0.172, (P, 95, 0.60), (P, 145), ease="out")
    B.k(0.21, (P, 102, 0.58), (P, 152), ease="out")
    B.k(0.30, (-0.30, 1.05, -0.40), (-110, -16), None, ease="out")
    B.k(0.40, (-0.10, 0.90, -0.45), (-40, -40), None, ease="io", tip_min=0.12, js=True)
    B.k(0.50, (0.25, 0.88, -0.30), (60, -40), None, ease="io", tip_min=0.12, js=True)
    carry_key(B, 0.60)
    B.S["feet"] = {"moves": [{"f": 0, "t0": 0.07, "t1": 0.16, "x": 0.02, "z": -0.30, "yaw": -30.0, "apex": 0.08, "th": 6.0},
                             {"f": 1, "t0": 0.40, "t1": 0.52, "x": -0.15, "z": -0.06, "yaw": 4.0, "apex": 0.07, "th": 6.0, "near": 0.12},
                             {"f": 0, "t0": 0.44, "t1": 0.58, "x": 0.15, "z": 0.04, "yaw": -4.0, "apex": 0.07, "th": 6.0}],
                   "pitch1": [0.0, 0.0, 0.10, 0.0, 0.17, -28.0, 0.36, -28.0, 0.42, 0.0],
                   "follow1": [0.0, 0.0, 0.08, 0.0, 0.20, 0.8, 0.36, 0.8]}
    return B


A3_OPEN = 0.22


def a4(built):
    """A4, the finisher: the sword swung up over his head out of A3's follow-through (P5's coiled attitude: wide and low),
    a long step and the overhead chop that strikes the ground in front of him (P8: a wide crouch, the blade planted)."""
    B = Blow("a4", 0.82, 0.07, 0.25, {"swing": 0.21, "impact": 0.28, "step": [0.26, 0.78]}, (0.20, 0.31))
    g0, b0, f0 = chain_from(B, built["a3"], A3_OPEN)
    pt = B.prev
    B.c("py", 0.0, at(pt, "py"), 0.10, 10, 0.19, -8, 0.24, 6, 0.30, 12, 0.44, 10, 0.62, 4, 0.82, 0)
    B.c("cy", 0.0, at(pt, "cy"), 0.10, 20, 0.19, -18, 0.25, 4, 0.30, 10, 0.44, 8, 0.62, 2, 0.82, 0)
    B.c("pp", 0.0, at(pt, "pp"), 0.10, 4, 0.19, 8, 0.27, -14, 0.44, -14, 0.62, -4, 0.82, 1.1)
    B.c("cp", 0.0, at(pt, "cp"), 0.10, 10, 0.19, 22, 0.24, 0, 0.28, -32, 0.44, -30, 0.62, -8, 0.82, 4)
    B.c("cr", 0.0, at(pt, "cr"), 0.10, 4, 0.19, -4, 0.28, 3, 0.44, 3, 0.82, 0)
    B.c("pr", 0.0, at(pt, "pr"), 0.10, 2, 0.19, -3, 0.28, 2, 0.82, 0)
    B.c("px", 0.0, at(pt, "px"), 0.10, 0.02, 0.19, 0.04, 0.28, -0.02, 0.44, -0.02, 0.62, -0.01, 0.82, 0)
    B.c("pz", 0.0, at(pt, "pz"), 0.10, -0.06, 0.19, -0.04, 0.27, -0.30, 0.44, -0.28, 0.62, -0.10, 0.82, 0)
    B.c("pdy", 0.0, at(pt, "pdy"), 0.10, -0.08, 0.19, 0.0, 0.24, -0.06, 0.28, -0.30, 0.44, -0.28, 0.62, -0.12, 0.82, 0)
    B.c("hy", 0.0, at(pt, "hy"), 0.10, 4, 0.19, 0, 0.28, 2, 0.44, 2, 0.82, 0)
    B.c("hp", 0.0, at(pt, "hp"), 0.10, 4, 0.19, 10, 0.27, -12, 0.44, -16, 0.62, -4, 0.82, 0)
    shield(B.S, [(0.0,) + shield_at(pt),
                 (0.10,) + SH_TUCK,
                 (0.19, (-0.36, 0.02, -0.30), (-0.8, -0.4, 0.4), (-0.6, 0.2, -0.8)),
                 (0.27,) + SH_BACK,
                 (0.44,) + SH_BACK,
                 (0.64,) + SH_READY,
                 (0.82,) + SH_READY])
    # the chop: a vertical plane through his right shoulder, a little across towards his middle
    P = Plane((14, -40), (16, 88))
    B.k(0.0, g0, b0, f0, fsig=0.3)
    B.k(0.09, (-0.05, 1.70, -0.30), (-60, 75), None, ease="io", js=True)
    B.k(0.185, (P, -32, 0.42), (P, -118), ease="out", js=True)
    B.k(0.205, (P, -30, 0.42), (P, -114), ease="out")
    B.k(0.255, (P, 92, 0.56), (P, 50), ease="in", bease="in")
    B.k(0.285, (P, 118, 0.56), (P, 88), ease="out", tip_min=0.02)
    B.k(0.44, (P, 120, 0.55), (P, 92), ease="out", tip_min=0.02)
    B.k(0.58, (0.32, 0.88, -0.20), (90, -40), None, ease="io", tip_min=0.08, js=True)
    carry_key(B, 0.82)
    B.S["feet"] = {"moves": [{"f": 0, "t0": 0.02, "t1": 0.12, "x": 0.16, "z": 0.06, "yaw": -6.0, "apex": 0.06, "th": 4.0, "near": 0.14},
                             {"f": 1, "t0": 0.12, "t1": 0.27, "x": -0.22, "z": -0.62, "yaw": 10.0, "apex": 0.16, "th": 8.0},
                             {"f": 1, "t0": 0.60, "t1": 0.78, "x": -0.15, "z": -0.10, "yaw": 4.0, "apex": 0.08, "th": 5.0}],
                   "pitch0": [0.0, 0.0, 0.20, 0.0, 0.30, -30.0, 0.56, -30.0, 0.74, -4.0],
                   "follow0": [0.0, 0.0, 0.20, 0.0, 0.32, 0.6, 0.5, 0.6]}
    return B


# =================================================================================================================================
def b1():
    """B1: the rising diagonal out of the low carry, low right to high left (the first blow of combo B, the one out of a run)."""
    B = Blow("b1", 0.58, 0.07, 0.22, {"swing": 0.11, "impact": 0.155, "step": [0.145, 0.56]}, (0.105, 0.225))
    B.c("py", 0.0, 0, 0.105, -14, 0.115, -15, 0.155, 12, 0.195, 26, 0.29, 30, 0.43, 14, 0.58, 0)
    B.c("cy", 0.0, 0, 0.105, -30, 0.12, -32, 0.165, 30, 0.205, 50, 0.29, 56, 0.43, 26, 0.58, 0)
    B.c("pp", 0.0, 1.1, 0.115, 6, 0.175, -2, 0.31, -3, 0.58, 1.1)
    B.c("cp", 0.0, 4, 0.105, 12, 0.12, 12, 0.175, -8, 0.25, -12, 0.41, -4, 0.58, 4)
    B.c("cr", 0.0, 0, 0.105, -6, 0.175, 10, 0.29, 12, 0.43, 4, 0.58, 0)
    B.c("pr", 0.0, 0, 0.115, -3, 0.175, 4, 0.31, 4, 0.58, 0)
    B.c("px", 0.0, 0, 0.115, 0.04, 0.175, -0.04, 0.31, -0.05, 0.47, -0.02, 0.58, 0)
    B.c("pz", 0.0, 0, 0.115, 0.04, 0.175, -0.12, 0.31, -0.14, 0.47, -0.05, 0.58, 0)
    B.c("pdy", 0.0, 0, 0.115, -0.10, 0.175, -0.06, 0.31, -0.08, 0.47, -0.03, 0.58, 0)
    B.c("hy", 0.0, 0, 0.105, -8, 0.145, 0, 0.195, 10, 0.31, 14, 0.47, 4, 0.58, 0)
    B.c("hp", 0.0, 0, 0.115, -4, 0.195, 4, 0.31, 2, 0.58, 0)
    shield(B.S, [(0.0,) + SH_READY,
                 (0.105,) + SH_TUCK,
                 (0.175,) + SH_OUT,
                 (0.31,) + SH_OUT,
                 (0.47,) + SH_READY,
                 (0.58,) + SH_READY])
    P = Plane(*B_PLANE)
    carry_start(B)
    B.k(0.105, (P, 25, 0.56), (P, -35), ease="io", js=True)
    B.k(0.115, (P, 27, 0.56), (P, -32), ease="out")
    B.k(0.155, (P, 105, 0.58), (P, 90), ease="in", bease="in")
    B.k(0.185, (P, 145, 0.57), (P, 127), ease="out")
    B.k(0.215, (P, 154, 0.56), (P, 137), ease="out")
    B.k(0.24, (P, 156, 0.55), (P, 139), ease="out")
    # the recovery (INTEGRATE: low across his front, like A's, instead of the loop over his head that missed its marks): the hand
    # comes down at his left, the blade lowered ahead of him and swung round his right side into the carry
    B.k(0.32, (-0.18, 1.0, -0.45), (-70, -30), None, ease="io", tip_min=0.15, js=True)
    B.k(0.42, (0.05, 0.92, -0.40), (0, -38), None, ease="io", tip_min=0.15, js=True)
    B.k(0.51, (0.30, 0.88, -0.15), (95, -38), None, ease="io", tip_min=0.15, js=True)
    carry_key(B, 0.58)
    B.S["feet"] = {"moves": [{"f": 1, "t0": 0.04, "t1": 0.145, "x": -0.17, "z": -0.36, "yaw": 6.0, "apex": 0.09, "th": 10.0},
                             {"f": 1, "t0": 0.42, "t1": 0.56, "x": -0.15, "z": -0.08, "yaw": 4.0, "apex": 0.07, "th": 6.0}],
                   "pitch0": [0.0, 0.0, 0.125, 0.0, 0.215, -28.0, 0.35, -28.0, 0.50, -4.0],
                   "follow0": [0.0, 0.0, 0.115, 0.0, 0.235, 0.7, 0.41, 0.7]}
    return B


B1_OPEN = 0.215
# (INTEGRATE) combo B's plane: b1 rises in it, b2 comes back down it
B_PLANE = ((-8, -22), (95, -35))


def b2(built):
    """B2: the descending backhand, high left to low right (B1's plane back down: the false edge leads, the hand does not turn)."""
    B = Blow("b2", 0.50, 0.06, 0.22, {"swing": 0.07, "impact": 0.11, "step": [0.11, 0.48]}, (0.07, 0.18))
    g0, b0, f0 = chain_from(B, built["b1"], B1_OPEN)
    pt = B.prev
    B.c("py", 0.0, at(pt, "py"), 0.06, 32, 0.075, 30, 0.12, -10, 0.16, -22, 0.26, -24, 0.40, -8, 0.50, 0)
    B.c("cy", 0.0, at(pt, "cy"), 0.06, 60, 0.08, 56, 0.13, -24, 0.17, -46, 0.26, -48, 0.40, -14, 0.50, 0)
    B.c("pp", 0.0, at(pt, "pp"), 0.07, -2, 0.13, -6, 0.26, -4, 0.50, 1.1)
    B.c("cp", 0.0, at(pt, "cp"), 0.07, -8, 0.13, -14, 0.24, -14, 0.40, -4, 0.50, 4)
    B.c("cr", 0.0, at(pt, "cr"), 0.07, 8, 0.13, -6, 0.26, -8, 0.40, -2, 0.50, 0)
    B.c("pr", 0.0, at(pt, "pr"), 0.07, 3, 0.13, -4, 0.26, -4, 0.50, 0)
    B.c("px", 0.0, at(pt, "px"), 0.07, -0.05, 0.13, 0.04, 0.26, 0.05, 0.42, 0.01, 0.50, 0)
    B.c("pz", 0.0, at(pt, "pz"), 0.07, -0.14, 0.13, -0.18, 0.26, -0.16, 0.42, -0.05, 0.50, 0)
    B.c("pdy", 0.0, at(pt, "pdy"), 0.07, -0.08, 0.13, -0.14, 0.26, -0.13, 0.42, -0.04, 0.50, 0)
    B.c("hy", 0.0, at(pt, "hy"), 0.06, 12, 0.10, 2, 0.14, -8, 0.26, -12, 0.42, -4, 0.50, 0)
    B.c("hp", 0.0, at(pt, "hp"), 0.10, -6, 0.20, -6, 0.40, -1, 0.50, 0)
    shield(B.S, [(0.0,) + shield_at(pt),
                 (0.07,) + SH_TUCK,
                 (0.14,) + SH_OUT,
                 (0.26,) + SH_OUT,
                 (0.42,) + SH_READY,
                 (0.50,) + SH_READY])
    # B1's plane swept back down (th falls): the hand keeps B1's side, so the false edge leads (no turnover)
    P = Plane(*B_PLANE)
    B.k(0.0, g0, b0, f0, fsig=0.3)
    # (INTEGRATE: on the lowered plane 222/220 put the fist back over his brow and the forearm through his head: cocked
    # further forward, the fist up at his left temple and the blade back over his left shoulder)
    B.k(0.062, (P, 206, 0.52), (P, 190), ease="io")
    B.k(0.07, (P, 204, 0.52), (P, 188), ease="out")
    B.k(0.11, (P, 120, 0.56), (P, 90), ease="in", bease="in")
    B.k(0.14, (P, 80, 0.56), (P, 40), ease="out")
    B.k(0.18, (P, 74, 0.55), (P, 30), ease="out")
    B.k(0.26, (0.36, 0.92, -0.18), (125, -36), None, ease="out", tip_min=0.12)
    carry_key(B, 0.50)
    B.S["feet"] = {"moves": [{"f": 0, "t0": 0.02, "t1": 0.11, "x": 0.20, "z": -0.26, "yaw": -8.0, "apex": 0.08, "th": 10.0},
                             {"f": 1, "t0": 0.30, "t1": 0.42, "x": -0.15, "z": -0.06, "yaw": 4.0, "apex": 0.07, "th": 6.0, "near": 0.12},
                             {"f": 0, "t0": 0.34, "t1": 0.48, "x": 0.15, "z": 0.04, "yaw": -4.0, "apex": 0.07, "th": 6.0}],
                   "pitch1": [0.0, 0.0, 0.08, 0.0, 0.16, -24.0, 0.28, -24.0, 0.34, 0.0],
                   "follow1": [0.0, 0.0, 0.07, 0.0, 0.18, 0.6, 0.3, 0.6]}
    return B


B2_OPEN = 0.19


def b3(built):
    """B3, the finisher: the lunging thrust. Drawn back low and coiled (P5), a long step of the left foot, the body extended,
    the blade straight at the foe, the shield flung back; a long hold."""
    B = Blow("b3", 0.74, 0.07, 0.25, {"swing": 0.17, "impact": 0.215, "step": [0.215, 0.70]}, (0.17, 0.27))
    g0, b0, f0 = chain_from(B, built["b2"], B2_OPEN)
    pt = B.prev
    B.c("py", 0.0, at(pt, "py"), 0.10, -26, 0.165, -28, 0.21, 10, 0.26, 18, 0.40, 16, 0.56, 6, 0.74, 0)
    B.c("cy", 0.0, at(pt, "cy"), 0.10, -46, 0.165, -48, 0.215, 18, 0.26, 26, 0.40, 22, 0.56, 8, 0.74, 0)
    B.c("pp", 0.0, at(pt, "pp"), 0.10, 4, 0.165, 6, 0.215, -10, 0.40, -10, 0.56, -3, 0.74, 1.1)
    B.c("cp", 0.0, at(pt, "cp"), 0.10, 6, 0.165, 8, 0.215, -18, 0.40, -18, 0.56, -6, 0.74, 4)
    B.c("cr", 0.0, at(pt, "cr"), 0.10, -4, 0.165, -4, 0.215, 4, 0.40, 4, 0.74, 0)
    B.c("pr", 0.0, at(pt, "pr"), 0.10, 2, 0.215, -3, 0.40, -3, 0.74, 0)
    B.c("px", 0.0, at(pt, "px"), 0.10, 0.04, 0.165, 0.05, 0.215, -0.02, 0.40, -0.02, 0.74, 0)
    B.c("pz", 0.0, at(pt, "pz"), 0.10, 0.06, 0.165, 0.08, 0.215, -0.32, 0.40, -0.30, 0.56, -0.10, 0.74, 0)
    B.c("pdy", 0.0, at(pt, "pdy"), 0.10, -0.12, 0.165, -0.14, 0.215, -0.22, 0.40, -0.21, 0.56, -0.08, 0.74, 0)
    B.c("hy", 0.0, at(pt, "hy"), 0.10, 4, 0.165, 6, 0.215, 2, 0.40, 2, 0.74, 0)
    B.c("hp", 0.0, at(pt, "hp"), 0.10, -2, 0.215, -8, 0.40, -8, 0.74, 0)
    shield(B.S, [(0.0,) + shield_at(pt),
                 (0.10, (-0.10, -0.12, -0.42), (-1.0, -0.5, 0.3), (-0.2, 0.05, -1.0)),
                 (0.165, (-0.10, -0.12, -0.42), (-1.0, -0.5, 0.3), (-0.2, 0.05, -1.0)),
                 # (INTEGRATE: flung back wide and high over the lunging left thigh, not through it)
                 (0.19, (-0.40, -0.08, -0.12), (-0.7, -0.5, 0.6), (-0.7, 0.05, -0.35)),
                 (0.215, (-0.52, -0.22, 0.14), (-0.4, -0.5, 1.0), (-0.95, 0.0, 0.25)),
                 (0.40, (-0.52, -0.22, 0.14), (-0.4, -0.5, 1.0), (-0.95, 0.0, 0.25)),
                 (0.58,) + SH_READY,
                 (0.74,) + SH_READY])
    B.k(0.0, g0, b0, f0, fsig=0.3)
    # the thrust with the thumb up: drawn back to the hip, the point raised at the foe; driven out with the arm straight and the
    # blade rising a little off it (a hand cannot hold the blade in the forearm's line: 30 degrees off at the least)
    B.k(0.10, ("sh", 60, -40, 0.38), (10, 35), (90, 0), ease="io", js=True)
    B.k(0.165, ("sh", 62, -40, 0.38), (10, 34), (90, 0), ease="out")
    B.k(0.215, ("sh", 2, -20, 0.62), (0, 18), (90, 0), ease="in", js=True)
    B.k(0.40, ("sh", 2, -22, 0.61), (0, 15), (90, 0), ease="out")
    B.k(0.56, (0.32, 0.92, -0.18), (95, -38), None, ease="io", tip_min=0.1, js=True)
    carry_key(B, 0.74)
    B.S["feet"] = {"moves": [{"f": 1, "t0": 0.02, "t1": 0.10, "x": -0.20, "z": -0.10, "yaw": 6.0, "apex": 0.06, "th": 4.0, "near": 0.14},
                             {"f": 1, "t0": 0.12, "t1": 0.215, "x": -0.20, "z": -0.72, "yaw": 8.0, "apex": 0.12, "th": 10.0},
                             {"f": 1, "t0": 0.52, "t1": 0.70, "x": -0.15, "z": -0.10, "yaw": 4.0, "apex": 0.08, "th": 5.0}],
                   "pitch0": [0.0, 0.0, 0.18, 0.0, 0.26, -34.0, 0.48, -34.0, 0.66, -4.0],
                   "follow0": [0.0, 0.0, 0.16, 0.0, 0.26, 0.5, 0.4, 0.5]}
    return B



# =================================================================================================================================
def dash():
    """The dash attack (attack while sprinting): the sword swung up out of the run's carry, a leap (the knees tucked, the chest
    arched back, the blade hung over his head at the top), then the slash down through the landing into P8: a wide, deep crouch,
    the blade struck into the ground in front of him. The legs are the blow's own (baked): he leaves the ground."""
    B = Blow("dash", 0.86, 0.05, 0.25, {"swing": 0.235, "impact": 0.30, "step": [0.30, 0.80]}, (0.22, 0.36))
    B.c("py", 0.0, 0, 0.12, -10, 0.22, -14, 0.30, 12, 0.45, 10, 0.65, 3, 0.86, 0)
    B.c("cy", 0.0, 0, 0.12, -24, 0.22, -30, 0.30, 16, 0.45, 12, 0.65, 3, 0.86, 0)
    B.c("pp", 0.0, 4, 0.08, 8, 0.16, 6, 0.22, 10, 0.31, -14, 0.46, -14, 0.65, -4, 0.86, 1.1)
    B.c("cp", 0.0, 8, 0.10, 14, 0.22, 22, 0.25, 12, 0.31, -30, 0.46, -32, 0.65, -8, 0.86, 4)
    B.c("cr", 0.0, 0, 0.12, -4, 0.22, -6, 0.31, 4, 0.46, 4, 0.86, 0)
    B.c("pr", 0.0, 0, 0.12, -2, 0.31, 3, 0.46, 3, 0.86, 0)
    B.c("px", 0.0, 0, 0.12, 0.02, 0.31, -0.03, 0.46, -0.03, 0.70, 0, 0.86, 0)
    B.c("pz", 0.0, 0, 0.06, 0.04, 0.22, -0.04, 0.31, -0.24, 0.46, -0.22, 0.66, -0.06, 0.86, 0)
    B.c("pdy", 0.0, -0.06, 0.06, -0.10, 0.14, 0.14, 0.22, 0.22, 0.27, 0.12, 0.315, -0.30, 0.46, -0.29, 0.64, -0.12, 0.86, 0)
    B.c("hy", 0.0, 0, 0.12, -4, 0.31, 2, 0.86, 0)
    B.c("hp", 0.0, 0, 0.14, -4, 0.22, -8, 0.31, -14, 0.46, -16, 0.66, -4, 0.86, 0)
    shield(B.S, [(0.0,) + SH_READY,
                 (0.10, (-0.44, -0.10, -0.02), (-0.5, -0.6, 0.6), (-0.9, 0.2, -0.3)),
                 (0.22, (-0.52, 0.02, 0.06), (-0.4, -0.6, 0.7), (-0.95, 0.3, -0.1)),
                 (0.31,) + SH_BACK,
                 (0.46,) + SH_BACK,
                 (0.66,) + SH_READY,
                 (0.86,) + SH_READY])
    P = Plane((14, -40), (22, 86))
    carry_start(B)
    B.k(0.10, (0.66, 1.18, 0.15), (162, -6), None, ease="io", js=True)
    B.k(0.20, (P, -32, 0.42), (P, -118), ease="out", js=True)
    B.k(0.225, (P, -30, 0.42), (P, -114), ease="out")
    B.k(0.285, (P, 92, 0.56), (P, 50), ease="in", bease="in")
    B.k(0.31, (P, 118, 0.56), (P, 88), ease="out", tip_min=0.02)
    B.k(0.48, (P, 120, 0.55), (P, 92), ease="out", tip_min=0.02)
    B.k(0.64, (0.32, 0.88, -0.20), (90, -40), None, ease="io", tip_min=0.08, js=True)
    carry_key(B, 0.86)
    # the legs (rig space): push off, the right knee up and the left leg trailing in the air (P6), the landing in a wide stance,
    # the left foot in front (P8), the recovery step back to the stance
    def kk(*a):
        return [float(x) for x in a]
    B.S["f0x"] = kk(0.0, 0.15, 0.08, 0.15, 0.20, 0.14, 0.30, 0.22, 0.64, 0.22, 0.78, 0.15, 0.86, 0.15)
    B.S["f0y"] = kk(0.0, 0.093, 0.04, 0.10, 0.10, 0.20, 0.20, 0.42, 0.27, 0.22, 0.31, 0.093, 0.64, 0.093, 0.71, 0.16, 0.78, 0.093, 0.86, 0.093)
    B.S["f0z"] = kk(0.0, 0.04, 0.08, 0.10, 0.20, -0.22, 0.30, 0.26, 0.64, 0.26, 0.78, 0.04, 0.86, 0.04)
    B.S["f0p"] = kk(0.0, 0.0, 0.06, -30.0, 0.12, -40.0, 0.22, 10.0, 0.30, 0.0, 0.31, -10.0, 0.64, -10.0, 0.70, -20.0, 0.78, 6.0, 0.86, 0.0)
    B.S["f0w"] = kk(0.0, -10.0, 0.30, -14.0, 0.64, -14.0, 0.86, -10.0)
    B.S["f1x"] = kk(0.0, -0.15, 0.20, -0.14, 0.30, -0.24, 0.64, -0.24, 0.78, -0.15, 0.86, -0.15)
    B.S["f1y"] = kk(0.0, 0.093, 0.06, 0.12, 0.14, 0.30, 0.22, 0.34, 0.27, 0.20, 0.30, 0.093, 0.64, 0.093, 0.71, 0.15, 0.78, 0.093, 0.86, 0.093)
    B.S["f1z"] = kk(0.0, -0.06, 0.14, 0.18, 0.22, 0.20, 0.30, -0.56, 0.64, -0.56, 0.78, -0.08, 0.86, -0.06)
    B.S["f1p"] = kk(0.0, 0.0, 0.10, -20.0, 0.22, -30.0, 0.28, 10.0, 0.31, 0.0, 0.64, 0.0, 0.70, -10.0, 0.78, 4.0, 0.86, 0.0)
    B.S["f1w"] = kk(0.0, 10.0, 0.30, 12.0, 0.64, 12.0, 0.86, 10.0)
    B.S["feet"] = {"mode": "baked"}
    return B


def heavy():
    """The heavy blow (attack held): the coil of P5 (very wide and low, the chest twisted to his left, the blade drawn back low
    at his left, the eyes on the foe), held while charging; released: one clean turn to his right on the ball of his right foot,
    the arm out and the blade level and wide at his waist, the body low; the turn ends with the blade out at his right."""
    B = Blow("heavy", 1.0, 0.06, 0.25, {"swing": 0.34, "impact": 0.47, "step": [0.40, 0.72]}, (0.37, 0.68))
    B.S["pivx"] = 0.26
    B.S["pivz"] = -0.02
    B.S["rot"] = [-x if i % 2 else x for i, x in enumerate(rot_curve([(0.30, 0), (0.36, 1000), (0.56, 1000), (0.72, 0)]))]
    B.c("py", 0.0, 0, 0.16, 16, 0.30, 24, 0.36, 18, 0.46, -6, 0.60, -10, 0.72, -14, 0.85, -10, 1.0, 0)
    B.c("cy", 0.0, 0, 0.16, 40, 0.30, 62, 0.36, 50, 0.46, -2, 0.60, -20, 0.72, -28, 0.85, -20, 1.0, 0)
    B.c("pp", 0.0, 1.1, 0.30, 6, 0.40, -4, 0.72, -8, 0.85, -6, 1.0, 1.1)
    B.c("cp", 0.0, 4, 0.30, 14, 0.40, 6, 0.60, 0, 0.72, -10, 0.85, -8, 1.0, 4)
    B.c("cr", 0.0, 0, 0.30, 8, 0.45, -6, 0.72, -8, 1.0, 0)
    B.c("pr", 0.0, 0, 0.30, 4, 0.45, -4, 0.72, -4, 1.0, 0)
    B.c("px", 0.0, 0, 0.20, 0.02, 0.30, 0.04, 0.38, 0.10, 0.66, 0.10, 0.74, 0.04, 0.90, 0.01, 1.0, 0)
    B.c("pz", 0.0, 0, 0.20, 0.02, 0.30, 0.0, 0.38, -0.02, 0.66, -0.02, 0.74, -0.06, 0.90, -0.02, 1.0, 0)
    B.c("pdy", 0.0, 0, 0.16, -0.12, 0.30, -0.17, 0.38, -0.12, 0.66, -0.12, 0.74, -0.19, 0.85, -0.18, 0.95, -0.05, 1.0, 0)
    B.c("hy", 0.0, 0, 0.16, 8, 0.30, 12, 0.40, -10, 0.72, -16, 0.85, -10, 1.0, 0)
    B.c("hp", 0.0, 0, 0.30, -6, 0.50, -4, 0.72, -8, 1.0, 0)
    shield(B.S, [(0.0,) + SH_READY,
                 (0.16, (-0.12, -0.16, -0.52), (-1.0, -0.5, 0.3), (-0.1, 0.0, -1.0)),
                 (0.30, (-0.08, -0.17, -0.55), (-1.0, -0.5, 0.3), (0.05, 0.0, -1.0)),
                 (0.40,) + SH_OUT,
                 (0.66,) + SH_BACK,
                 (0.85,) + SH_OUT,
                 (1.0,) + SH_READY])
    # the sweep: a level plane (in the unturned frame) the blade turns about to his right; the back of the hand up
    P = Plane((60, -10), (-30, -12))
    carry_start(B)
    B.k(0.16, (-0.10, 0.88, -0.36), (-140, -24), None, ease="io", js=True)
    # (INTEGRATE: the fist low at his left hip and the blade back and down past it, under the shield arm: on the plane, at his chest,
    # the coiled blade lay across his left forearm and in the shield's bowl)
    B.k(0.30, (-0.30, 1.0, -0.22), (-150, -30), None, ease="out", js=True)
    B.k(0.36, (P, 0, 0.60), (P, -60), ease="in")
    B.k(0.46, (P, 110, 0.60), (P, 70), ease="lin")
    B.k(0.72, (P, 152, 0.60), (P, 112), ease="out")
    B.k(0.85, (P, 156, 0.60), (P, 116), ease="out")
    carry_key(B, 1.0)
    def kk(*a):
        return [float(x) for x in a]
    # the right foot: a step back-right into the wide stance, up on its ball for the turn (the toe at the pivot), down at the end
    a0 = ankle_on((0.26, -0.02), 1, 0.0, -32.0)
    B.S["f0x"] = kk(0.0, 0.15, 0.16, 0.26, 0.30, 0.26, 0.34, a0[0], 0.72, a0[0], 0.78, 0.26, 0.92, 0.26, 1.0, 0.15)
    B.S["f0y"] = kk(0.0, 0.093, 0.08, 0.16, 0.16, 0.093, 0.30, 0.093, 0.34, a0[1], 0.72, a0[1], 0.78, 0.093, 0.92, 0.093, 0.96, 0.13, 1.0, 0.093)
    B.S["f0z"] = kk(0.0, 0.04, 0.16, 0.20, 0.30, 0.20, 0.34, a0[2], 0.72, a0[2], 0.78, 0.20, 0.92, 0.20, 1.0, 0.04)
    B.S["f0p"] = kk(0.0, 0.0, 0.16, 0.0, 0.30, 0.0, 0.34, -32.0, 0.72, -32.0, 0.78, 0.0, 1.0, 0.0)
    B.S["f0w"] = kk(0.0, -10.0, 0.16, -14.0, 0.72, -14.0, 1.0, -10.0)
    # the left foot: a long step forward-left, then tucked and carried round the turn, set down on its spot again
    B.S["f1x"] = kk(0.0, -0.15, 0.16, -0.26, 0.30, -0.26, 0.40, -0.12, 0.64, -0.12, 0.72, -0.26, 0.90, -0.26, 1.0, -0.15)
    B.S["f1y"] = kk(0.0, 0.093, 0.08, 0.17, 0.16, 0.093, 0.30, 0.093, 0.40, 0.26, 0.64, 0.26, 0.72, 0.093, 0.90, 0.093, 0.95, 0.14, 1.0, 0.093)
    B.S["f1z"] = kk(0.0, -0.06, 0.16, -0.36, 0.30, -0.36, 0.40, -0.10, 0.64, -0.10, 0.72, -0.36, 0.90, -0.36, 1.0, -0.06)
    B.S["f1p"] = kk(0.0, 0.0, 0.30, 0.0, 0.40, -40.0, 0.64, -40.0, 0.70, 8.0, 0.74, 0.0, 1.0, 0.0)
    B.S["f1w"] = kk(0.0, 10.0, 0.16, 16.0, 0.72, 16.0, 1.0, 10.0)
    B.S["feet"] = {"mode": "baked"}
    return B


BLOWS = [a1, a2, a3, a4, b1, b2, b3, dash, heavy]


# =================================================================================================================================
def check(B, quiet=False):
    """the blade's path at 120 Hz: lowest tip, the blade's clearance from the torso and the thighs, the edge leading in the
    active window (|cos| of the flat to the tip's motion: 0 the edge leads, 1 the flat), the roll of the flat about the blade
    (deg/s), the tip's speed, the biggest joint step between two samples"""
    S = B.S
    ts = np.arange(0.0, S["len"] + 1e-9, 1 / 120)
    P = [pose(S, t) for t in ts]
    tip_y = [p["tip"][1] for p in P]
    i_lo = int(np.argmin(tip_y))
    clear = []
    for p in P:
        body = {"pb": p["pb"], "tb": p["tb"], "po": p["po"], "co": p["co"]}
        clear.append(blade_clearance({"grip": p["grip"], "tip": p["tip"]}, body))
    i_cl = int(np.argmin(clear))
    a0, a1_ = B.act
    fl, roll = [], []
    for i in range(1, len(ts) - 1):
        bl = unit(P[i]["tip"] - P[i]["grip"])
        f0 = unit(perp(P[i - 1]["flat"], bl))
        f1 = unit(perp(P[i + 1]["flat"], bl))
        r = abs(np.degrees(np.arctan2(np.dot(np.cross(f0, f1), bl), np.dot(f0, f1)))) / (2 / 120)
        if a0 <= ts[i] <= a1_:
            v = (P[i + 1]["tip"] - P[i - 1]["tip"]) / (2 / 120)
            vp = perp(v, bl)
            if np.linalg.norm(vp) > 2.0:
                fl.append(abs(np.dot(unit(P[i]["flat"]), unit(vp))))
            roll.append(r)
    tipv = [np.linalg.norm(P[i + 1]["tip"] - P[i]["tip"]) * 120 for i in range(len(ts) - 1)]
    jump = 0.0
    if hasattr(B, "sol"):
        X = np.array([r[1:] for r in B.sol])
        T = np.array([r[0] for r in B.sol])
        dX = np.abs(np.diff(X, axis=0)) / np.maximum(np.diff(T), 1e-4)[:, None]
        jump = float(np.max(dX))
        jj = np.unravel_index(int(np.argmax(dX)), dX.shape)
        jump_at = (float(T[jj[0]]), ["az", "e", "r", "el", "uln", "ext", "tw"][jj[1]])
    worst = max(getattr(B, "costs", [(0.0, 0.0)]), key=lambda a: a[1])
    if not quiet:
        print(f"   {B.name:6s} tip_min {tip_y[i_lo]:5.2f} m at {ts[i_lo]:.3f} | blade-body {clear[i_cl]:+.3f} m at {ts[i_cl]:.3f} | "
              f"edge |cos| mean {np.mean(fl) if fl else -1:.2f} max {np.max(fl) if fl else -1:.2f} | roll(act) max {np.max(roll) if roll else 0:4.0f} deg/s | "
              f"tip max {np.max(tipv):4.1f} m/s | joint max {jump:5.0f} deg/s{(' (%s at %.3f)' % (jump_at[1], jump_at[0])) if jump else ''} | cost max {worst[1]:.2f} at {worst[0]:.3f}")
    return ts, P


def report(B, every=4):
    ts, P = check(B)
    print("     t     grip(x y z)          blade az/el   tip(x y z)          flat az/el   joints")
    sol = {round(r[0], 4): r[1:] for r in getattr(B, "sol", [])}
    costs = {round(a, 4): b for a, b in getattr(B, "costs", [])}
    for i in range(0, len(ts), every):
        p = P[i]
        g, tp = p["grip"], p["tip"]
        ba, be = az_el(tp - g)
        fa, fe = az_el(p["flat"])
        j = sol.get(round(ts[i], 4))
        js = " ".join(f"{v:6.1f}" for v in j) if j else ""
        print(f"   {ts[i]:.3f}  ({g[0]:+.2f} {g[1]:.2f} {g[2]:+.2f})  {ba:7.1f} {be:6.1f}  ({tp[0]:+.2f} {tp[1]:5.2f} {tp[2]:+.2f})  {fa:7.1f} {fe:6.1f}  {js}  c={costs.get(round(ts[i], 4), 0):.2f}")


def trace(B, t0=0.0, t1=9.0, every=1):
    Bd = B.body()
    costs = {round(a, 4): b for a, b in getattr(B, "costs", [])}
    for row in B.sol[::every]:
        t = row[0]
        if not (t0 - 1e-9 <= t <= t1 + 1e-9):
            continue
        T, body = B.targets(Bd, t)
        s = arm_state(np.array(row[1:]), body)
        tf = az_el(T["flat"]) if T["flat"] is not None else (0, 0)
        print(f"{t:.4f} tgt b {az_el(T['blade'])[0]:6.0f} {az_el(T['blade'])[1]:4.0f} f {tf[0]:5.0f} {tf[1]:4.0f} | got b {az_el(s['blade'])[0]:6.0f} {az_el(s['blade'])[1]:4.0f} "
              f"f {az_el(s['flat'])[0]:5.0f} {az_el(s['flat'])[1]:4.0f} gerr {np.linalg.norm(s['grip'] - T['grip']):.3f} | x {' '.join('%5.0f' % v for v in row[1:])} c={costs.get(round(t, 4), 0):.2f}")


def view(B, n=12, t0=0.0, t1=None, tag=""):
    import mview
    os.makedirs(SHOTS, exist_ok=True)
    t1 = B.S["len"] if t1 is None else t1
    ts = list(np.linspace(t0, t1, n))
    out = os.path.join(SHOTS, f"{B.name}{tag}.png")
    mview.strip(B.S, ts, out=out, title=f"{B.name} {t0:.2f}-{t1:.2f}s")
    print("   view", out)


def build(names=None, force=False):
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    out = {}
    built = {}
    for f in BLOWS:
        B = f(built) if f.__code__.co_argcount else f()
        B.solve(cache, force and (names is None or B.name in names))
        built[B.name] = B
        if names and B.name not in names:
            continue
        if not hasattr(B, "costs"):
            B.costs = [tuple(x) for x in cache[B.name].get("costs", [])]
        out[B.name] = B
    json.dump(cache, open(CACHE, "w"), indent=0)
    return out


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--resolve" in sys.argv
    blows = build(args or None, force)
    for nm, B in blows.items():
        if "--trace" in sys.argv:
            check(B)
            trace(B)
        elif "--report" in sys.argv:
            report(B)
        else:
            check(B)
        if "--view" in sys.argv:
            view(B)
    if not args:
        out = {nm: B.S for nm, B in blows.items()}
        if "heavy" not in out:
            # (until the new heavy is written: the old one, from defs.py)
            import defs
            out["heavy"] = defs.build("heavy")
        export(out)
