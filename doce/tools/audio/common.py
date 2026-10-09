"""Shared building blocks for the DOCE sound effects (mono, float64, numpy only).

Most helpers come from the PHAROS recipes (thump, burst, whoosh, grain clouds, growl voice); DOCE adds the
primitives its world needs: bronze and blade modes, chain links, leather creaks, a cave reverb, tonal animal
voices (howls, squeals, yelps) and hoof/paw impacts.
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, TAU, damped_modes, env_perc, env_points, fades, filt, lp4, make_ir, mag_band, mag_hp,
                 mag_lp, mag_reso, normalize_peak, ramp_up, reverb, secs, smooth_random,
                 spectral_noise, tvec)

# ---------------------------------------------------------------------------
# Reverbs
# ---------------------------------------------------------------------------

_IRS: dict[str, np.ndarray] = {}


def ir(kind: str) -> np.ndarray:
    from dsp import rng_for
    if kind not in _IRS:
        r = rng_for("sfx-ir", kind)
        if kind == "small":
            _IRS[kind] = make_ir(0.55, 0.25, 0.7, predelay=0.006, rng=r, stereo=False, lp=7000)
        elif kind == "med":
            _IRS[kind] = make_ir(1.3, 0.55, 1.5, predelay=0.012, rng=r, stereo=False, lp=6500)
        elif kind == "big":
            _IRS[kind] = make_ir(2.6, 1.0, 3.0, predelay=0.02, rng=r, stereo=False, lp=5500)
        elif kind == "cave":
            # a rocky chamber: long low end, dark top, a few strong early reflections
            _IRS[kind] = make_ir(3.4, 1.1, 3.8, predelay=0.028, rng=r, stereo=False, lp=4200, early=9)
        elif kind == "open":
            # outdoors: a short slap from the hillside and little else
            _IRS[kind] = make_ir(0.9, 0.35, 1.1, predelay=0.04, rng=r, stereo=False, lp=5000, early=3)
        else:
            raise ValueError(kind)
    return _IRS[kind]


def wet(x: np.ndarray, kind: str, amount: float) -> np.ndarray:
    return reverb(x, ir(kind), amount)


# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

def pts(t, p, log: bool = False):
    times = np.array([q[0] for q in p], dtype=np.float64)
    vals = np.array([q[1] for q in p], dtype=np.float64)
    if log:
        return np.exp(np.interp(t, times, np.log(vals)))
    return np.interp(t, times, vals)


def unit(x: np.ndarray) -> np.ndarray:
    return x / (np.max(np.abs(x)) + 1e-12)


def place(buf: np.ndarray, x: np.ndarray, t: float, gain: float = 1.0) -> None:
    s = secs(t)
    if s < 0:
        x = x[-s:]
        s = 0
    e = min(s + len(x), len(buf))
    if e > s:
        buf[s:e] += gain * x[: e - s]


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def finish(x: np.ndarray, dur: float, peak_db: float = -3.0, fade_in: float = 0.0008,
           fade_out: float = 0.03, lp: float | None = 11000.0, hp: float = 22.0) -> np.ndarray:
    n = secs(dur)
    y = pad_to(np.asarray(x, dtype=np.float64), n)
    specs = [("hp", hp, 0.7071)]
    if lp:
        specs.append(("lp", lp, 0.7071))
    y = filt(y, specs)
    y = fades(y, fade_in, fade_out)
    return normalize_peak(y, peak_db)


# ---------------------------------------------------------------------------
# Impacts and noise
# ---------------------------------------------------------------------------

def thump(n: int, f_hi: float, f_lo: float, tau_p: float, decay: float, attack: float = 0.002) -> np.ndarray:
    """Sine with a falling pitch and a percussive envelope: the body of every impact."""
    t = tvec(n)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / tau_p)
    return np.sin(TAU * np.cumsum(f) / SR) * env_perc(n, attack, decay)


def burst(n: int, rng, decay: float, specs, attack: float = 0.0006, curve: float = 1.0) -> np.ndarray:
    return filt(rng.standard_normal(n) * env_perc(n, attack, decay, curve=curve), specs)


def whoosh(n: int, rng, center, gain, width: float = 0.6, nfft: int = 512, lp: float = 9000.0,
           hp: float = 60.0) -> np.ndarray:
    """Band noise (log-gaussian bell) whose centre and gain follow (t, v) curves."""
    def mag(t, f):
        fc = pts(t, center, log=True)
        g = pts(t, gain)
        return g * mag_band(f, fc, width) * mag_lp(f, lp, 2.0) * mag_hp(f, hp, 1.0)
    return spectral_noise(n, mag, rng, nfft=nfft)


def grain_cloud(n: int, rng, times, amp, f_lo: float, f_hi: float, d_lo: float = 0.001,
                d_hi: float = 0.004, q: float = 1.2) -> np.ndarray:
    """Cloud of resonant noise grains (gravel, crackle, debris, sand)."""
    out = np.zeros(n)
    for i, tt in enumerate(times):
        d = rng.uniform(d_lo, d_hi)
        k = max(secs(d * 3), 16)
        g = rng.standard_normal(k) * np.exp(-tvec(k) / d)
        g[: min(8, k)] *= ramp_up(min(8, k))
        fc = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        g = filt(g, [("bp", fc, q)], pad=0.02)
        a = amp[i] if hasattr(amp, "__len__") else amp
        place(out, g, tt, a * rng.uniform(0.3, 1.0))
    return out


def bubbles(n: int, rng, times, f_lo: float, f_hi: float, tau_lo: float = 0.006, tau_hi: float = 0.03,
            rise: float = 1.2, amp=1.0) -> np.ndarray:
    """Bubbles (Minnaert resonance with a rising chirp)."""
    out = np.zeros(n)
    for i, tt in enumerate(times):
        tau = rng.uniform(tau_lo, tau_hi)
        f0 = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        k = secs(tau * 5)
        t = tvec(k)
        f = f0 * (1.0 + rise * t / (tau * 5))
        b = np.sin(TAU * np.cumsum(f) / SR) * env_perc(k, 0.0015, tau)
        a = amp[i] if hasattr(amp, "__len__") else amp
        place(out, b, tt, a * rng.uniform(0.4, 1.0))
    return out


def debris(n: int, rng, t0: float, count: int, spread: float, f_lo: float = 300.0, f_hi: float = 2600.0,
           tau: float = 0.3) -> np.ndarray:
    """Stones and grit falling after a big impact: bandpassed bursts with a little ring, decaying density."""
    times = t0 + np.sort(rng.exponential(spread, count))
    amps = np.exp(-(times - t0) / tau)
    out = np.zeros(n)
    for tt, a in zip(times, amps):
        k = secs(0.06)
        fc = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        s = burst(k, rng, rng.uniform(0.003, 0.012), [("bp", fc, 1.4)])
        s += 0.4 * damped_modes(k, [fc * 1.0, fc * 1.7], [1, 0.5], [0.012, 0.008], attack=0.0006, rng=rng)
        place(out, unit(s), tt, a * rng.uniform(0.3, 1.0))
    return out


def rumble(n: int, rng, gain, f0: float = 90.0, f1: float = 60.0) -> np.ndarray:
    """Low rumble that follows a gain curve (rock, ground, big bodies)."""
    dur = n / SR
    return whoosh(n, rng, [(0, f0), (dur, f1)], gain, width=1.0, nfft=2048, hp=25)


# ---------------------------------------------------------------------------
# Metal: bronze, blades, chains
# ---------------------------------------------------------------------------

PLATE = (1.0, 1.51, 2.31, 2.87, 3.73, 4.45, 5.6)      # bronze shield / plate (PHAROS bash)
BAR = (1.0, 2.756, 5.404, 8.933)                      # free bar (blade, chime)
BLADE = (1.0, 1.47, 2.09, 2.56, 3.18, 3.9, 4.73)      # thin blade ringing


def metal(n: int, rng, f0: float, ratios, amps, decays, beat: float = 2.0, lp: float = 6500.0,
          hp: float = 200.0, attack: float = 0.0008) -> np.ndarray:
    m = damped_modes(n, [f0 * r for r in ratios], amps, decays, attack=attack, rng=rng, beat=beat)
    return unit(filt(m, [("lp", lp, 0.7), ("hp", hp, 0.7)]))


def link_clink(rng, f0: float | None = None, dur: float = 0.06, bright: float = 1.0) -> np.ndarray:
    """One chain link touching another: a tiny inharmonic ring with a click."""
    n = secs(dur)
    f0 = f0 if f0 is not None else np.exp(rng.uniform(np.log(2300), np.log(4600)))
    r = (1.0, rng.uniform(1.38, 1.52), rng.uniform(2.1, 2.5), rng.uniform(2.9, 3.4))
    d = rng.uniform(0.008, 0.022)
    m = damped_modes(n, [f0 * x for x in r], [1.0, 0.6, 0.35 * bright, 0.18 * bright], [d, d * 0.8, d * 0.6, d * 0.45],
                     attack=0.0003, rng=rng)
    k = min(secs(0.003), n)
    click = np.zeros(n)
    click[:k] = rng.standard_normal(k) * np.exp(-tvec(k) / 0.0007)
    click = filt(click, [("hp", 2000, 0.7)], pad=0.01)
    return unit(m) + 0.35 * unit(click)


def chain_train(n: int, rng, times, amp, f_lo: float = 1900.0, f_hi: float = 3900.0, pitch=None) -> np.ndarray:
    """Many links: clinks at the given times (amp per clink or scalar). `pitch(t)` scales the link frequency."""
    out = np.zeros(n)
    for i, tt in enumerate(times):
        f0 = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        if pitch is not None:
            f0 *= pitch(tt)
        c = link_clink(rng, f0, dur=0.05, bright=rng.uniform(0.6, 1.0))
        a = amp[i] if hasattr(amp, "__len__") else amp
        place(out, c, tt, a * rng.uniform(0.45, 1.0))
    return filt(out, lp4(6500))


def creak(n: int, rng, f_res, rate_pts, gain_pts, q: float = 9.0, rough: float = 0.5) -> np.ndarray:
    """Stick-slip friction (leather, wood, stretched links): a pulse train at a varying rate exciting a resonance."""
    t = tvec(n)
    rate = pts(t, rate_pts) * (1.0 + 0.15 * smooth_random(n, rng, 9.0))
    ph = np.cumsum(rate) / SR
    k = np.floor(ph)
    pulse = np.zeros(n)
    idx = np.nonzero(np.diff(k, prepend=k[0]) > 0)[0]
    pulse[idx] = rng.uniform(0.4, 1.0, len(idx))
    exc = filt(pulse + rough * 0.05 * rng.standard_normal(n), [("hp", 300, 0.7)])
    out = np.zeros(n)
    for fr, g in zip(f_res if hasattr(f_res, "__len__") else [f_res], (1.0, 0.6, 0.35)):
        out += g * filt(exc, [("bp", fr, q)])
    return unit(out) * pts(t, gain_pts)


# ---------------------------------------------------------------------------
# Voices (no mouths are ever shown, but beasts must be heard)
# ---------------------------------------------------------------------------

def growl_voice(n: int, rng, f0_pts, form_pts, rough: float = 0.4, jitter: float = 0.025,
                breath: float = 0.25, lp: float = 2800.0, vowel_bw: float = 1.0) -> np.ndarray:
    """Beast voice: additive glottal source with subharmonics (growl) and moving formants.

    form_pts: [(t, F1, F2, F3), ...]
    """
    t = tvec(n)
    f0 = pts(t, f0_pts, log=True)
    f0 = f0 * (1.0 + jitter * smooth_random(n, rng, 22.0)) * (1.0 + 0.6 * jitter * smooth_random(n, rng, 2.5))
    ph = TAU * np.cumsum(f0) / SR
    F1 = pts(t, [(p[0], p[1]) for p in form_pts])
    F2 = pts(t, [(p[0], p[2]) for p in form_pts])
    F3 = pts(t, [(p[0], p[3]) for p in form_pts])
    out = np.zeros(n)
    K = int(min(lp * 1.6 / max(np.min(f0), 20.0), 90))
    for k in range(1, K + 1):
        fk = k * f0
        a = (1.0 / k ** 0.85) * (mag_reso(fk, F1, 130 * vowel_bw) + 0.55 * mag_reso(fk, F2, 170 * vowel_bw)
                                 + 0.2 * mag_reso(fk, F3, 260 * vowel_bw)) * mag_lp(fk, lp, 2.0)
        out += a * np.sin(k * ph + rng.uniform(0, TAU))
    am = 1.0 + rough * (0.65 * np.sin(ph / 2.0 + rng.uniform(0, TAU)) + 0.35 * smooth_random(n, rng, 35.0))
    out *= np.clip(am, 0.0, None)
    out = unit(out)
    if breath > 0:
        def mag(tt, f):
            a1 = pts(tt, [(p[0], p[1]) for p in form_pts])
            a2 = pts(tt, [(p[0], p[2]) for p in form_pts])
            return (mag_reso(f, a1, 260) + 0.6 * mag_reso(f, a2, 320) + 0.15) * mag_lp(f, lp * 1.2, 2.0) * mag_hp(f, 120, 1)
        nz = unit(spectral_noise(n, mag, rng, nfft=1024))
        out = out + breath * nz
    return out


def tonal_voice(n: int, rng, f0_pts, harm, form_pts=None, vib_rate: float = 5.0, vib_cents=None,
                jitter: float = 0.004, rough: float = 0.0, breath: float = 0.1, lp: float = 5000.0,
                breath_band: float = 1800.0) -> np.ndarray:
    """Clean animal voice (howl, yelp, squeal, whimper): harmonic series `harm` (relative amplitudes),
    pitch curve f0_pts (Hz), optional formant curve [(t, F1, F2)], vibrato and roughness."""
    t = tvec(n)
    f0 = pts(t, f0_pts, log=True)
    if vib_cents is not None:
        vc = pts(t, vib_cents)
        f0 = f0 * 2.0 ** (vc * np.sin(TAU * vib_rate * t + rng.uniform(0, TAU)) / 1200.0)
    f0 = f0 * (1.0 + jitter * smooth_random(n, rng, 18.0))
    ph = TAU * np.cumsum(f0) / SR
    out = np.zeros(n)
    for k, a in enumerate(harm, start=1):
        fk = k * f0
        g = a * mag_lp(fk, lp, 2.0)
        if form_pts is not None:
            F1 = pts(t, [(p[0], p[1]) for p in form_pts])
            F2 = pts(t, [(p[0], p[2]) for p in form_pts])
            g = g * (0.35 + mag_reso(fk, F1, 260.0) + 0.6 * mag_reso(fk, F2, 380.0))
        g = np.where(fk < 0.45 * SR, g, 0.0)
        out += g * np.sin(k * ph + rng.uniform(0, TAU))
    if rough > 0:
        am = 1.0 + rough * (0.6 * np.sin(ph * 0.5 + rng.uniform(0, TAU)) + 0.4 * smooth_random(n, rng, 40.0))
        out *= np.clip(am, 0.0, None)
    out = unit(out)
    if breath > 0:
        nz = whoosh(n, rng, [(0, breath_band), (n / SR, breath_band)], [(0, 1), (n / SR, 1)], width=0.8, lp=lp)
        out = out + breath * unit(nz)
    return out


def snort_burst(n: int, rng, t0: float, dur: float, gain: float = 1.0, f1: float = 420.0, f2: float = 1300.0) -> np.ndarray:
    """A nasal blast of air (boar snorts, the lion's huff): noise through nasal resonances with a fluttery onset."""
    out = np.zeros(n)
    k = secs(dur)
    tt = tvec(k)
    env = env_points(k, [(0, 0), (dur * 0.12, 1.0), (dur * 0.45, 0.6), (dur, 0.0)])
    flutter = 1.0 + 0.55 * np.sin(TAU * rng.uniform(26, 38) * tt) * np.exp(-tt / (dur * 0.5))
    nz = rng.standard_normal(k)
    x = (filt(nz, [("bp", f1, 2.2)]) + 0.7 * filt(nz, [("bp", f2, 2.5)]) + 0.25 * filt(nz, [("bp", 2600, 1.5)]))
    place(out, unit(x) * env * flutter, t0, gain)
    return out


# ---------------------------------------------------------------------------
# Feet, paws, hooves
# ---------------------------------------------------------------------------

def paw(rng, weight: float = 1.0, dur: float = 0.25) -> np.ndarray:
    """A padded paw (or a bare foot) landing: soft low thump, dull smack, a little grit."""
    n = secs(dur)
    y = thump(n, 110 / weight ** 0.3, 55 / weight ** 0.3, 0.015, 0.04 * weight ** 0.5, attack=0.002)
    y += 0.5 * unit(burst(n, rng, 0.02 * weight ** 0.4, [("lp", 600, 0.7)], attack=0.002))
    times = np.sort(rng.uniform(0.004, 0.05, 8))
    y += 0.12 * unit(grain_cloud(n, rng, times, 1.0, 1500, 4000, 0.0006, 0.002))
    return unit(y)


def hoof(rng, dur: float = 0.18) -> np.ndarray:
    """A hard cloven hoof on dry ground: click + knock + dust."""
    n = secs(dur)
    y = 0.8 * thump(n, 170, 85, 0.008, 0.03, attack=0.0008)
    y += damped_modes(n, [rng.uniform(600, 800), rng.uniform(1300, 1600)], [0.6, 0.3], [0.018, 0.01], attack=0.0005,
                      rng=rng)
    y += 0.5 * unit(burst(n, rng, 0.004, [("bp", 2200, 1.0)]))
    times = np.sort(rng.uniform(0.005, 0.06, 6))
    y += 0.15 * unit(grain_cloud(n, rng, times, 1.0, 1200, 3500, 0.0006, 0.002))
    return unit(y)


def body_fall(rng, weight: float = 1.0, dur: float = 0.7) -> np.ndarray:
    """A body hitting the ground: two thumps (shoulder, hip) and dust."""
    n = secs(dur)
    y = np.zeros(n)
    k1 = thump(secs(0.4), 95 / weight ** 0.3, 50 / weight ** 0.3, 0.02, 0.07 * weight ** 0.5)
    k1 += 0.6 * unit(burst(secs(0.4), rng, 0.035, [("lp", 380, 0.7)]))
    place(y, k1, 0.0, 0.7)
    k2 = thump(secs(0.5), 80 / weight ** 0.3, 42 / weight ** 0.3, 0.03, 0.1 * weight ** 0.5)
    k2 += 0.8 * unit(burst(secs(0.5), rng, 0.05, [("lp", 320, 0.7)]))
    place(y, k2, 0.07 + 0.05 * weight, 1.0)
    dust = whoosh(n, rng, [(0, 900), (dur, 600)], [(0, 0), (0.08, 0), (0.18, 1), (dur * 0.8, 0)], width=1.2, lp=2200)
    y += 0.12 * unit(dust)
    return unit(y)


__all__ = [n for n in dir() if not n.startswith("_")]
