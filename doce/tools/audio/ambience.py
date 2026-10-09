"""DOCE ambience loops (circular synthesis: the end joins the start exactly).

  * sea          – waves breaking on the beach over a sea bed (30 s, stereo) — from PHAROS
  * wind         – wind in the grass: gusts, a hiss of stems, a thin whistle in the strongest gusts (24 s, mono)
  * day          – birds in the trees (songbirds, a fluty warbler, a far dove), cicadas, leaves (30 s, stereo)
  * cave         – the Lion's cave: still air, a low moan from its two mouths, drips with a long echo (24 s, mono)
  * boulder_drag – stone grinding over rock while the chain drags it (4 s, mono; play it on the boulder)

Everything that varies in time is periodic in the loop length: circular spectral noise, random curves made of
sines with a whole number of cycles, and events placed "wrapping" around the end.
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, TAU, add_wrapped, colored_noise, convolve, env_perc, filt, lp4, make_ir, mag_band, mag_hp,
                 mag_lp, normalize_rms, rng_for, secs, smooth_random, soft_clip, spectral_noise, tvec)

NFFT = 1764  # hop = 441 muestras (10 ms): divide exactamente 30 s y 8 s


def _wrap_t(t: np.ndarray, start: float, L: float) -> np.ndarray:
    return np.mod(t - start, L)


def _periodic_curve(n: int, rng, rate: float, lo: float = 0.0, hi: float = 1.0) -> np.ndarray:
    c = smooth_random(n, rng, rate, circular=True)
    c = (c - c.min()) / (np.ptp(c) + 1e-12)
    return lo + (hi - lo) * c


def _finish(x: np.ndarray, rms_db: float, ceiling_db: float = -6.0) -> np.ndarray:
    x = filt(x, [("hp", 25, 0.7071)], circular=True)
    x = normalize_rms(x, rms_db)
    # picos raros: rodilla suave sin memoria (no rompe la periodicidad del bucle)
    return soft_clip(x, ceiling_db - 3.0, ceiling_db)


# ---------------------------------------------------------------------------
# Mar
# ---------------------------------------------------------------------------

def sea() -> np.ndarray:
    rng = rng_for("amb", "sea")
    Ls = 30.0
    n = secs(Ls)
    # olas: (inicio, duración, intensidad, paneo)
    starts = np.array([0.4, 6.5, 12.3, 18.9, 24.6]) + rng.uniform(-0.3, 0.3, 5)
    waves = [(st, rng.uniform(6.8, 8.0), rng.uniform(0.75, 1.0), rng.uniform(-0.45, 0.45)) for st in starts]

    def wave_shape(tau, dur):
        """Amplitud y frecuencia de corte de una ola en su tiempo local tau."""
        approach, brk = 1.9, 2.7
        a = np.where(tau < approach, (tau / approach) ** 2 * 0.55,
                     np.where(tau < brk, 0.55 + 0.45 * np.sin(0.5 * np.pi * (tau - approach) / (brk - approach)),
                              np.exp(-(tau - brk) / 1.5)))
        a = a * np.clip((dur - tau) / 0.8, 0, 1) * (tau < dur)
        fc = np.where(tau < approach, 260 + 500 * (tau / approach),
                      np.where(tau < brk, 760 + 1600 * (tau - approach) / (brk - approach),
                               2360 * np.exp(-(tau - brk) / 2.2) + 500))
        return a, fc

    def wash_mag(chan):
        def mag(t, f):
            tot = np.zeros(np.broadcast_shapes(t.shape, f.shape))
            for st, dur, inten, p in waves:
                tau = _wrap_t(t, st, Ls)
                a, fc = wave_shape(tau, dur)
                drift = p + 0.25 * np.clip((tau - 2.0) / 4.0, 0, 1) * np.sign(p + 1e-3)
                th = (np.clip(drift, -1, 1) + 1) * np.pi / 4
                g = np.cos(th) if chan == 0 else np.sin(th)
                shape = mag_lp(f, fc, 1.6) * mag_hp(f, 70, 1.0) / np.sqrt(np.maximum(f, 60) / 60.0)
                tot = tot + (inten * a * g * 1.41) ** 2 * shape ** 2
            return np.sqrt(tot)
        return mag

    def fizz_mag(chan):
        def mag(t, f):
            tot = np.zeros(np.broadcast_shapes(t.shape, f.shape))
            for st, dur, inten, p in waves:
                tau = _wrap_t(t, st, Ls)
                a = np.where((tau > 2.5) & (tau < dur), np.exp(-(tau - 2.5) / 1.8) * np.clip((tau - 2.5) / 0.4, 0, 1), 0)
                a = a * np.clip((dur - tau) / 0.8, 0, 1)
                th = (np.clip(p, -1, 1) + 1) * np.pi / 4
                g = np.cos(th) if chan == 0 else np.sin(th)
                tot = tot + (inten * a * g) ** 2
            return np.sqrt(tot) * mag_band(f, 3300, 0.55) * mag_lp(f, 6500, 2)
        return mag

    out = np.zeros((n, 2))
    for c in range(2):
        wash = spectral_noise(n, wash_mag(c), rng, nfft=NFFT, circular=True)
        fizz = spectral_noise(n, fizz_mag(c), rng, nfft=NFFT, circular=True)
        bed = colored_noise(n, rng, lambda f: mag_lp(f, 320, 2) * mag_hp(f, 35, 2) / np.sqrt(np.maximum(f, 40) / 40))
        bed = bed / (np.std(bed) + 1e-12)
        bed *= _periodic_curve(n, rng, 0.12, 0.6, 1.0)
        out[:, c] = wash / (np.std(wash) + 1e-12) + 0.07 * fizz / (np.std(fizz) + 1e-12) + 0.32 * bed
    # burbujas de espuma (granos muy suaves) durante la resaca
    for st, dur, inten, p in waves:
        times = st + 2.6 + rng.exponential(1.2, 70)
        times = times[times < st + dur]
        for tt in times:
            k = secs(0.02)
            tau = rng.uniform(0.002, 0.006)
            f0 = rng.uniform(1800, 4200)
            tt_ = tvec(k)
            b = np.sin(TAU * f0 * (1 + 0.8 * tt_ / 0.02) * tt_) * env_perc(k, 0.0008, tau)
            g = 0.012 * inten * np.exp(-(tt - st - 2.6) / 1.6) * rng.uniform(0.3, 1.0)
            pp = np.clip(p + rng.normal(0, 0.3), -1, 1)
            th = (pp + 1) * np.pi / 4
            add_wrapped(out, np.stack([b * np.cos(th), b * np.sin(th)], axis=1), secs(tt % Ls), g)
    out = filt(out, lp4(7000), circular=True)
    ir = make_ir(1.2, 0.5, 1.5, predelay=0.01, rng=rng_for("amb-ir", "sea"), lp=6000)
    out = out + 0.15 * convolve(out, ir, circular=True)
    return _finish(out, -26.0)


# ---------------------------------------------------------------------------
# Día: cigarras + brisa
# ---------------------------------------------------------------------------

def _breeze(n: int, rng, Ls: float, base: float, span: float, rate: float, dark: float = 1.0):
    gust = _periodic_curve(n, rng, rate, 0.15, 1.0)
    gt = gust[:: NFFT // 4]  # una muestra por frame

    def mag(t, f):
        idx = np.clip((t * SR / (NFFT // 4)).astype(int), 0, len(gt) - 1)
        g = gt[idx]
        fc = (base + span * g) * dark
        return g * mag_lp(f, fc, 1.5) * mag_hp(f, 40, 1.0) / np.sqrt(np.maximum(f, 50) / 50.0)
    out = np.zeros((n, 2))
    for c in range(2):
        x = spectral_noise(n, mag, rng, nfft=NFFT, circular=True)
        out[:, c] = x / (np.std(x) + 1e-12)
    return out, gust


def _cicada(n: int, rng, Ls: float, fc: float, pulse_hz: float, phrases, pan: float, dist: float):
    """Cigarra: banda estrecha de ruido modulada por pulsos suaves y frases de varios segundos."""
    t = tvec(n)
    carrier = colored_noise(n, rng, lambda f: mag_band(f, fc, 0.13) + 0.3 * mag_band(f, fc * 1.5, 0.1))
    carrier /= np.std(carrier) + 1e-12
    am = 0.5 + 0.5 * (0.5 + 0.5 * np.cos(TAU * pulse_hz * t)) ** 2.0
    env = np.zeros(n)
    for st, rise, hold, fall in phrases:
        tau = _wrap_t(t, st, Ls)
        tot = rise + hold + fall
        e = np.where(tau < rise, (tau / rise) ** 1.5,
                     np.where(tau < rise + hold, 1.0, np.clip(1 - (tau - rise - hold) / fall, 0, 1) ** 1.3))
        env = np.maximum(env, e * (tau < tot))
    x = carrier * am * env
    if dist > 0:
        x = filt(x, [("lp", 6500 - 2500 * dist, 0.7)], circular=True)
    th = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(th), x * np.sin(th)], axis=1) * (1.0 - 0.6 * dist)




# ---------------------------------------------------------------------------
# Wind in the grass (meadows, the ridge): gusts, a hiss of stems, now and then a thin whistle
# ---------------------------------------------------------------------------

def wind() -> np.ndarray:
    rng = rng_for("amb", "doce-wind")
    Ls = 24.0
    n = secs(Ls)
    breeze, gust = _breeze(n, rng, Ls, 220.0, 700.0, 0.11)
    breeze = breeze.mean(axis=1)
    # grass: a dry hiss that follows the gusts, roughened by the stems brushing each other
    g = gust ** 1.6
    x = colored_noise(n, rng, lambda f: mag_band(f, 3400, 0.6) * mag_lp(f, 6000, 2) + 0.4 * mag_band(f, 1500, 0.5))
    x /= np.std(x) + 1e-12
    rough = _periodic_curve(n, rng, 14.0, 0.25, 1.0)
    grass = x * rough * g
    # a thin whistle that comes up only in the strongest gusts
    wf = _periodic_curve(n, rng, 0.06, 560.0, 820.0)[:: NFFT // 4]

    def wmag(t, f):
        idx = np.clip((t * SR / (NFFT // 4)).astype(int), 0, len(wf) - 1)
        return mag_band(f, wf[idx], 0.05)
    wh = spectral_noise(n, wmag, rng, nfft=NFFT, circular=True)
    wh = wh / (np.std(wh) + 1e-12) * np.clip(gust - 0.55, 0, None) ** 2 * 4.0
    out = 0.7 * breeze + 0.16 * grass + 0.035 * wh
    out = filt(out, lp4(7000), circular=True)
    return _finish(out, -27.0)


# ---------------------------------------------------------------------------
# Day: birds in the trees, cicadas in the heat, leaves
# ---------------------------------------------------------------------------

def _chirp(rng, f0: float, f1: float, dur: float, harm2: float = 0.15, curve: float = 1.0) -> np.ndarray:
    k = secs(dur)
    tt = tvec(k)
    u = (tt / dur) ** curve
    f = f0 * (f1 / f0) ** u
    ph = TAU * np.cumsum(f) / SR
    env = np.sin(np.pi * np.clip(tt / dur, 0, 1)) ** 1.5
    return (np.sin(ph) + harm2 * np.sin(2 * ph)) * env


def _songbird(n: int, rng, Ls: float, phrases: int, f_lo: float, f_hi: float, pan: float, dist: float) -> np.ndarray:
    """A small bird: phrases of quick notes (tsip, tsee-oo, trills) at random times, wrapped around the loop."""
    out = np.zeros((n, 2))
    th = (pan + 1) * np.pi / 4
    starts = np.sort(rng.uniform(0, Ls, phrases))
    for st in starts:
        kind = rng.integers(3)
        t = st
        if kind == 0:  # repeated tsips
            base = rng.uniform(f_lo, f_hi)
            for i in range(int(rng.integers(3, 7))):
                s = _chirp(rng, base * 1.15, base * 0.85, rng.uniform(0.035, 0.05))
                add_wrapped(out, np.stack([s * np.cos(th), s * np.sin(th)], axis=1), secs(t), rng.uniform(0.6, 1.0))
                t += rng.uniform(0.09, 0.14)
        elif kind == 1:  # a rising "tsee" and a falling "oo"
            base = rng.uniform(f_lo, f_hi)
            s = _chirp(rng, base * 0.8, base * 1.25, 0.12, curve=0.7)
            add_wrapped(out, np.stack([s * np.cos(th), s * np.sin(th)], axis=1), secs(t), 0.9)
            s = _chirp(rng, base * 1.1, base * 0.6, 0.18, curve=1.4)
            add_wrapped(out, np.stack([s * np.cos(th), s * np.sin(th)], axis=1), secs(t + 0.15), 0.8)
        else:  # a short trill
            base = rng.uniform(f_lo, f_hi) * 1.1
            for i in range(int(rng.integers(6, 12))):
                s = _chirp(rng, base * 1.08, base * 0.92, 0.022, harm2=0.05)
                add_wrapped(out, np.stack([s * np.cos(th), s * np.sin(th)], axis=1), secs(t), 0.7)
                t += 0.035
    if dist > 0:
        out = filt(out, [("lp", 7000 - 3500 * dist, 0.7)], circular=True)
    return out * (1.0 - 0.6 * dist)


def _blackbird(n: int, rng, Ls: float, phrases: int, pan: float, dist: float) -> np.ndarray:
    """A fluty, melodic warbler lower down (1.4–3 kHz): a few slurred notes per phrase."""
    out = np.zeros((n, 2))
    th = (pan + 1) * np.pi / 4
    scale = [1.0, 9 / 8, 5 / 4, 4 / 3, 3 / 2, 5 / 3, 2.0]
    for st in np.sort(rng.uniform(0, Ls, phrases)):
        base = rng.uniform(1400, 1900)
        t = st
        for i in range(int(rng.integers(4, 7))):
            a = base * scale[int(rng.integers(len(scale)))]
            b = a * rng.uniform(0.85, 1.2)
            d = rng.uniform(0.08, 0.22)
            s = _chirp(rng, a, b, d, harm2=0.08, curve=rng.uniform(0.6, 1.6))
            add_wrapped(out, np.stack([s * np.cos(th), s * np.sin(th)], axis=1), secs(t), rng.uniform(0.6, 1.0))
            t += d + rng.uniform(0.02, 0.07)
    if dist > 0:
        out = filt(out, [("lp", 6500 - 3000 * dist, 0.7)], circular=True)
    return out * (1.0 - 0.6 * dist)


def _dove(n: int, rng, Ls: float, times, pan: float) -> np.ndarray:
    """A turtle dove far off: soft purring coos around 550 Hz."""
    out = np.zeros((n, 2))
    th = (pan + 1) * np.pi / 4
    for st in times:
        t = st
        for i in range(3):
            k = secs(0.42)
            tt = tvec(k)
            f = 560 * (1 - 0.06 * tt / 0.42)
            s = np.sin(TAU * np.cumsum(f) / SR) * np.sin(np.pi * tt / 0.42) ** 2 * (0.6 + 0.4 * np.sin(TAU * 26 * tt))
            add_wrapped(out, np.stack([s * np.cos(th), s * np.sin(th)], axis=1), secs(t), 1.0)
            t += 0.55
    return filt(out, [("lp", 1500, 0.7)], circular=True)


def day() -> np.ndarray:
    rng = rng_for("amb", "doce-day")
    Ls = 30.0
    n = secs(Ls)
    breeze, gust = _breeze(n, rng, Ls, 300.0, 600.0, 0.12)
    leaves = np.zeros((n, 2))
    for c in range(2):
        x = colored_noise(n, rng, lambda f: mag_band(f, 2300, 0.7) * mag_lp(f, 5000, 2))
        x /= np.std(x) + 1e-12
        rough = _periodic_curve(n, rng, 9.0, 0.2, 1.0)
        leaves[:, c] = x * rough * gust ** 2
    birds = np.zeros((n, 2))
    birds += _songbird(n, rng, Ls, 9, 3200, 4600, -0.5, 0.15)
    birds += _songbird(n, rng, Ls, 7, 2600, 3800, 0.55, 0.4)
    birds += _songbird(n, rng, Ls, 5, 3600, 5000, 0.1, 0.7)
    birds += 0.8 * _blackbird(n, rng, Ls, 4, -0.2, 0.35)
    birds += 0.25 * _dove(n, rng, Ls, [4.0, 19.5], 0.7)
    cic = np.zeros((n, 2))
    cic += _cicada(n, rng, Ls, 4300.0, 1110 / Ls, [(2.0, 3.0, 8.0, 3.0), (20.0, 2.5, 5.0, 3.0)], 0.45, 0.25)
    cic += _cicada(n, rng, Ls, 4700.0, 1230 / Ls, [(9.0, 4.0, 9.0, 4.0)], -0.35, 0.55)
    out = 0.3 * breeze + 0.08 * leaves + 0.75 * birds / (np.std(birds) * 6 + 1e-12) + 0.16 * cic
    ir = make_ir(1.1, 0.45, 1.4, predelay=0.014, rng=rng_for("amb-ir", "doce-day"), lp=6500)
    out = out + 0.2 * convolve(out, ir, circular=True)
    out = filt(out, lp4(7500), circular=True)
    return _finish(out, -27.0)


# ---------------------------------------------------------------------------
# The Lion's cave: still air, a low moan from the two mouths, water dripping into pools, a long echo
# ---------------------------------------------------------------------------

def cave() -> np.ndarray:
    rng = rng_for("amb", "doce-cave")
    Ls = 24.0
    n = secs(Ls)
    tone = colored_noise(n, rng, lambda f: mag_lp(f, 140, 2) * mag_hp(f, 28, 2))
    tone = tone / (np.std(tone) + 1e-12) * _periodic_curve(n, rng, 0.1, 0.6, 1.0)
    mf = _periodic_curve(n, rng, 0.05, 260.0, 420.0)[:: NFFT // 4]
    mg = _periodic_curve(n, rng, 0.08, 0.1, 1.0)[:: NFFT // 4]

    def mmag(t, f):
        idx = np.clip((t * SR / (NFFT // 4)).astype(int), 0, len(mf) - 1)
        return mg[idx] * mag_band(f, mf[idx], 0.25)
    moan = spectral_noise(n, mmag, rng, nfft=NFFT, circular=True)
    moan /= np.std(moan) + 1e-12
    drips = np.zeros(n)
    t = 0.3
    while t < Ls:
        f0 = rng.uniform(900, 2400)
        dur = rng.uniform(0.02, 0.05)
        k = secs(dur * 4)
        tt = tvec(k)
        f = f0 * (1.0 + 1.6 * tt / (dur * 4))
        d = np.sin(TAU * np.cumsum(f) / SR) * env_perc(k, 0.0008, dur)
        k2 = secs(0.004)
        d[:k2] += 0.3 * rng.standard_normal(k2) * np.exp(-tvec(k2) / 0.001)
        g = rng.uniform(0.25, 1.0) * (0.5 if rng.uniform() < 0.4 else 1.0)
        add_wrapped(drips, d, secs(t), g)
        if rng.uniform() < 0.35:  # a second drop from the same place
            add_wrapped(drips, d * 0.6, secs(t + rng.uniform(0.25, 0.6)), g * 0.6)
        t += rng.exponential(1.4) + 0.35
    drips = filt(drips, [("lp", 5500, 0.7), ("hp", 300, 0.7)], circular=True)
    ir = make_ir(3.6, 1.2, 4.0, predelay=0.03, rng=rng_for("amb-ir", "doce-cave"), stereo=False, lp=4500, early=9)
    drips = 1.0 * drips + 0.55 * convolve(drips, ir, circular=True)
    out = 0.5 * tone + 0.16 * moan + 0.75 * drips / (np.std(drips) * 4 + 1e-12)
    return _finish(out, -28.0, ceiling_db=-5.0)


# ---------------------------------------------------------------------------
# The boulder dragged by the chain (4 s loop): stone grinding over rock and earth, gravel crushing
# ---------------------------------------------------------------------------

def boulder_drag() -> np.ndarray:
    rng = rng_for("amb", "doce-boulder-drag")
    Ls = 4.0
    n = secs(Ls)
    grind = colored_noise(n, rng, lambda f: mag_lp(f, 260, 2) * mag_hp(f, 35, 2) / np.sqrt(np.maximum(f, 40) / 40))
    grind /= np.std(grind) + 1e-12
    slip = _periodic_curve(n, rng, 9.0, 0.35, 1.0) * _periodic_curve(n, rng, 1.5, 0.6, 1.0)
    grind *= slip
    scrape = colored_noise(n, rng, lambda f: mag_band(f, 900, 0.6) + 0.4 * mag_band(f, 2200, 0.4))
    scrape = scrape / (np.std(scrape) + 1e-12) * _periodic_curve(n, rng, 13.0, 0.0, 1.0) ** 2
    crush = np.zeros(n)
    t = 0.0
    while t < Ls:
        t += rng.exponential(1.0 / 45.0)
        if t >= Ls:
            break
        k = secs(0.02)
        dec = rng.uniform(0.0008, 0.004)
        g = rng.standard_normal(k) * env_perc(k, 0.0003, dec)
        g = filt(g, [("bp", np.exp(rng.uniform(np.log(700), np.log(3200))), 1.4)], pad=0.02)
        add_wrapped(crush, g / (np.max(np.abs(g)) + 1e-12), secs(t), np.exp(rng.normal(-1.0, 0.6)))
    knocks = np.zeros(n)
    for tt in rng.uniform(0, Ls, 5):
        k = secs(0.15)
        tv = tvec(k)
        kk = np.sin(TAU * np.cumsum(110 - 40 * (1 - np.exp(-tv / 0.02))) / SR) * env_perc(k, 0.002, 0.03)
        add_wrapped(knocks, kk, secs(tt), rng.uniform(0.4, 1.0))
    out = 1.0 * grind + 0.18 * scrape + 0.22 * filt(crush, lp4(5000), circular=True) + 0.5 * knocks
    return _finish(out, -20.0, ceiling_db=-3.0)


AMB = {"sea": sea, "wind": wind, "day": day, "cave": cave, "boulder_drag": boulder_drag}
STEREO = {"sea", "day"}
