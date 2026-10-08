"""Ambientes en bucle de PHAROS (síntesis circular: el final enlaza exactamente con el principio).

  * sea   – olas suaves que rompen en la playa, mar de fondo (30 s, estéreo)
  * day   – cigarras suaves + brisa con hojas (30 s, estéreo)
  * night – grillos + viento suave (30 s, estéreo)
  * fire  – crepitar de hoguera (8 s, mono)

Todo lo que varía en el tiempo es periódico en la longitud del bucle: ruido espectral
circular, curvas aleatorias hechas de senos con un número entero de ciclos y eventos
colocados "envolviendo" el final.
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


def day() -> np.ndarray:
    rng = rng_for("amb", "day")
    Ls = 30.0
    n = secs(Ls)
    breeze, gust = _breeze(n, rng, Ls, 300.0, 650.0, 0.12)
    # hojas: banda media con rugosidad, siguiendo las rachas
    leaves = np.zeros((n, 2))
    for c in range(2):
        x = colored_noise(n, rng, lambda f: mag_band(f, 2300, 0.7) * mag_lp(f, 5000, 2))
        x /= np.std(x) + 1e-12
        rough = _periodic_curve(n, rng, 9.0, 0.2, 1.0)
        leaves[:, c] = x * rough * gust ** 2
    cic = np.zeros((n, 2))
    cic += _cicada(n, rng, Ls, 4300.0, 1110 / Ls, [(1.0, 3.0, 9.0, 3.0), (18.5, 2.5, 6.0, 3.5)], -0.45, 0.0)
    cic += _cicada(n, rng, Ls, 4800.0, 1230 / Ls, [(6.0, 4.0, 11.0, 4.0), (27.0, 2.0, 2.5, 2.0)], 0.35, 0.4)
    cic += _cicada(n, rng, Ls, 4000.0, 990 / Ls, [(12.0, 5.0, 12.0, 5.0), (3.0, 3.0, 2.0, 3.0)], 0.75, 0.65)
    # coro lejano y continuo, muy bajo
    far = np.zeros((n, 2))
    for c in range(2):
        x = colored_noise(n, rng, lambda f: mag_band(f, 4600, 0.18) * mag_lp(f, 6000, 2))
        far[:, c] = x / (np.std(x) + 1e-12) * _periodic_curve(n, rng, 0.08, 0.4, 1.0)
    out = 0.6 * breeze + 0.1 * leaves + 0.28 * cic + 0.03 * far
    ir = make_ir(1.0, 0.45, 1.3, predelay=0.012, rng=rng_for("amb-ir", "day"), lp=6500)
    out = out + 0.18 * convolve(out, ir, circular=True)
    out = filt(out, lp4(7500), circular=True)
    return _finish(out, -26.0)


# ---------------------------------------------------------------------------
# Noche: grillos + viento suave
# ---------------------------------------------------------------------------

def _cricket(n: int, rng, Ls: float, fc: float, chirp_period: float, pulses: int, bouts, pan: float,
             dist: float) -> np.ndarray:
    pulse_len = 0.016
    pulse_gap = 0.034
    k = secs(pulse_len)
    w = np.sin(np.pi * np.arange(k) / k) ** 2
    tt = tvec(k)
    out = np.zeros((n, 2))
    th = (pan + 1) * np.pi / 4
    t = 0.0
    while t < Ls:
        sing = any(((t - st) % Ls) < du for st, du in bouts)
        if sing:
            for p in range(pulses):
                a = (0.75 + 0.25 * np.sin(np.pi * (p + 0.5) / pulses)) * rng.uniform(0.85, 1.0)
                f = fc * (1.0 - 0.015 * tt / pulse_len) * (1 + rng.normal(0, 0.002))
                s = np.sin(TAU * np.cumsum(f) / SR + rng.uniform(0, TAU)) * w * a
                s = s + 0.08 * np.sin(2 * TAU * np.cumsum(f) / SR) * w * a
                add_wrapped(out, np.stack([s * np.cos(th), s * np.sin(th)], axis=1), secs(t + p * pulse_gap), 1.0)
        t += chirp_period * rng.uniform(0.94, 1.06)
    if dist > 0:
        out = filt(out, [("lp", 7000 - 3500 * dist, 0.7)], circular=True)
    return out * (1.0 - 0.7 * dist)


def night() -> np.ndarray:
    rng = rng_for("amb", "night")
    Ls = 30.0
    n = secs(Ls)
    wind, gust = _breeze(n, rng, Ls, 180.0, 420.0, 0.07)
    # silbido muy tenue del viento (resonancia estrecha que deriva)
    whistle = np.zeros((n, 2))
    wf = _periodic_curve(n, rng, 0.05, 620.0, 900.0)[:: NFFT // 4]

    def wmag(t, f):
        idx = np.clip((t * SR / (NFFT // 4)).astype(int), 0, len(wf) - 1)
        return mag_band(f, wf[idx], 0.06)
    for c in range(2):
        x = spectral_noise(n, wmag, rng, nfft=NFFT, circular=True)
        whistle[:, c] = x / (np.std(x) + 1e-12) * gust ** 3
    cr = np.zeros((n, 2))
    cr += _cricket(n, rng, Ls, 4480.0, 0.42, 4, [(0.0, 13.0), (16.0, 12.0)], -0.5, 0.0)
    cr += _cricket(n, rng, Ls, 4150.0, 0.55, 3, [(4.0, 20.0)], 0.4, 0.35)
    cr += _cricket(n, rng, Ls, 4820.0, 0.37, 4, [(9.0, 9.0), (21.0, 7.0)], 0.7, 0.55)
    cr += _cricket(n, rng, Ls, 3900.0, 0.48, 3, [(0.0, 30.0)], -0.15, 0.85)
    # grillo arborícola lejano: trino continuo suave
    t = tvec(n)
    trill_f = 2820.0
    tr = np.sin(TAU * trill_f * t) * (0.5 + 0.5 * np.cos(TAU * (1350 / Ls) * t)) ** 3
    tr *= _periodic_curve(n, rng, 0.06, 0.3, 1.0)
    trill = np.stack([tr * 0.8, tr * 0.6], axis=1)
    out = 0.5 * wind + 0.03 * whistle + 0.85 * cr + 0.05 * trill
    ir = make_ir(1.6, 0.6, 2.0, predelay=0.015, rng=rng_for("amb-ir", "night"), lp=5500)
    out = out + 0.22 * convolve(out, ir, circular=True)
    out = filt(out, lp4(7500), circular=True)
    return _finish(out, -27.0)


# ---------------------------------------------------------------------------
# Fuego
# ---------------------------------------------------------------------------

def fire() -> np.ndarray:
    rng = rng_for("amb", "fire")
    Ls = 8.0
    n = secs(Ls)
    roar = colored_noise(n, rng, lambda f: mag_lp(f, 480, 1.5) * mag_hp(f, 55, 1.5) / np.sqrt(np.maximum(f, 60) / 60))
    roar /= np.std(roar) + 1e-12
    flick = _periodic_curve(n, rng, 3.5, 0.55, 1.0) * _periodic_curve(n, rng, 0.4, 0.75, 1.0)
    roar *= flick
    hiss = colored_noise(n, rng, lambda f: mag_band(f, 3200, 0.6) * mag_lp(f, 6000, 2))
    hiss = hiss / (np.std(hiss) + 1e-12) * _periodic_curve(n, rng, 1.5, 0.2, 1.0) ** 2
    cr = np.zeros(n)
    # crepitar: Poisson ~16/s, amplitudes log-normales (muchos pequeños, pocos grandes)
    t = 0.0
    while t < Ls:
        t += rng.exponential(1.0 / 16.0)
        if t >= Ls:
            break
        k = secs(0.03)
        dec = rng.uniform(0.0006, 0.0035)
        g = rng.standard_normal(k) * env_perc(k, 0.0003, dec)
        fc = np.exp(rng.uniform(np.log(1200), np.log(4800)))
        g = filt(g, [("bp", fc, rng.uniform(1.2, 2.5))], pad=0.02)
        amp = min(np.exp(rng.normal(-1.0, 0.7)), 1.5)
        add_wrapped(cr, g / (np.max(np.abs(g)) + 1e-12), secs(t), amp)
        # a veces un pequeño racimo de chispas tras el chasquido
        if rng.uniform() < 0.25:
            for j in range(int(rng.integers(2, 5))):
                k2 = secs(0.015)
                g2 = rng.standard_normal(k2) * env_perc(k2, 0.0002, rng.uniform(0.0004, 0.0015))
                g2 = filt(g2, [("bp", fc * rng.uniform(0.8, 1.6), 2.0)], pad=0.02)
                add_wrapped(cr, g2 / (np.max(np.abs(g2)) + 1e-12), secs(t + 0.006 + j * rng.uniform(0.008, 0.02)),
                            amp * rng.uniform(0.15, 0.4))
    # estallidos de resina: más graves, con resonancia corta
    pops = np.zeros(n)
    for tt in rng.uniform(0, Ls, 7):
        k = secs(0.06)
        f0 = rng.uniform(600, 1400)
        tv = tvec(k)
        p = rng.standard_normal(k) * env_perc(k, 0.0004, 0.004) + 0.6 * np.sin(TAU * f0 * tv) * env_perc(k, 0.0006, 0.009)
        p = filt(p, [("lp", 4000, 0.7)], pad=0.02)
        add_wrapped(pops, p / (np.max(np.abs(p)) + 1e-12), secs(tt), rng.uniform(0.5, 1.0))
    cr = filt(cr, lp4(6500), circular=True)
    out = 0.55 * roar + 0.05 * hiss + 0.7 * cr + 0.55 * pops
    ir = make_ir(0.5, 0.25, 0.6, predelay=0.004, rng=rng_for("amb-ir", "fire"), stereo=False, lp=6000)
    out = out + 0.12 * convolve(out, ir, circular=True)
    return _finish(out, -24.0, ceiling_db=-4.0)


AMB = {"sea": sea, "day": day, "night": night, "fire": fire}
