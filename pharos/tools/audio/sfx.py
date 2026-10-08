"""Efectos de sonido (mono) de PHAROS. Cada función devuelve un array mono float64.

Recetas por capas: transitorio (ruido filtrado muy corto) + cuerpo (modos/seno con caída
de tono) + cola (ruido filtrado, reverb corta). Todo filtrado para que suene redondo.
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, TAU, damped_modes, env_perc, env_points, fades, filt, lp4,
                 make_ir, mag_band, mag_hp, mag_lp, mag_reso, midi_hz, normalize_peak, note,
                 ramp_up, reverb, rng_for, secs, smooth_random, spectral_noise, tvec)
from instruments import LYRE_BODY, bell, chime, lyre_pluck, pad_note

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

_IRS: dict[str, np.ndarray] = {}


def ir(kind: str) -> np.ndarray:
    if kind not in _IRS:
        r = rng_for("sfx-ir", kind)
        if kind == "small":
            _IRS[kind] = make_ir(0.55, 0.25, 0.7, predelay=0.006, rng=r, stereo=False, lp=7000)
        elif kind == "med":
            _IRS[kind] = make_ir(1.3, 0.55, 1.5, predelay=0.012, rng=r, stereo=False, lp=6500)
        elif kind == "big":
            _IRS[kind] = make_ir(2.6, 1.0, 3.0, predelay=0.02, rng=r, stereo=False, lp=5500)
        else:
            raise ValueError(kind)
    return _IRS[kind]


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
    e = min(s + len(x), len(buf))
    if e > s:
        buf[s:e] += gain * x[: e - s]


def thump(n: int, f_hi: float, f_lo: float, tau_p: float, decay: float, attack: float = 0.002) -> np.ndarray:
    t = tvec(n)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / tau_p)
    return np.sin(TAU * np.cumsum(f) / SR) * env_perc(n, attack, decay)


def burst(n: int, rng, decay: float, specs, attack: float = 0.0006, curve: float = 1.0) -> np.ndarray:
    return filt(rng.standard_normal(n) * env_perc(n, attack, decay, curve=curve), specs)


def whoosh(n: int, rng, center, gain, width: float = 0.6, nfft: int = 512, lp: float = 9000.0,
           hp: float = 60.0) -> np.ndarray:
    """Ruido de banda (campana log-gaussiana) cuyo centro y ganancia siguen curvas (t, v)."""
    def mag(t, f):
        fc = pts(t, center, log=True)
        g = pts(t, gain)
        return g * mag_band(f, fc, width) * mag_lp(f, lp, 2.0) * mag_hp(f, hp, 1.0)
    return spectral_noise(n, mag, rng, nfft=nfft)


def grain_cloud(n: int, rng, times, amp, f_lo: float, f_hi: float, d_lo: float = 0.001,
                d_hi: float = 0.004, q: float = 1.2) -> np.ndarray:
    """Nube de granos de ruido resonante (gravilla, crepitar, escombros)."""
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
    """Burbujas (resonancia de Minnaert con chirp ascendente)."""
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


def finish(x: np.ndarray, dur: float, peak_db: float = -3.0, fade_in: float = 0.0008,
           fade_out: float = 0.03, lp: float | None = 11000.0) -> np.ndarray:
    n = secs(dur)
    y = np.zeros(n)
    m = min(n, len(x))
    y[:m] = x[:m]
    specs = [("hp", 22, 0.7071)]
    if lp:
        specs.append(("lp", lp, 0.7071))
    y = filt(y, specs)
    y = fades(y, fade_in, fade_out)
    return normalize_peak(y, peak_db)


def wet(x: np.ndarray, kind: str, amount: float) -> np.ndarray:
    return reverb(x, ir(kind), amount)


def growl_voice(n: int, rng, f0_pts, form_pts, rough: float = 0.4, jitter: float = 0.025,
                breath: float = 0.25, lp: float = 2800.0, vowel_bw: float = 1.0) -> np.ndarray:
    """Voz monstruosa: fuente glotal aditiva con subarmónicos (gruñido) + formantes móviles.

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
    # gruñido: modulación a f0/2 (subarmónico) + rugosidad aleatoria
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


# ---------------------------------------------------------------------------
# Combate del héroe
# ---------------------------------------------------------------------------

def swing(variant: int) -> np.ndarray:
    rng = rng_for("swing", variant)
    if variant == 1:
        dur, peak_t = 0.30, 0.11
        cen = [(0.0, 420), (peak_t, 1250), (0.30, 520)]
    elif variant == 2:
        dur, peak_t = 0.29, 0.09
        cen = [(0.0, 520), (peak_t, 1500), (0.29, 650)]
    else:
        dur, peak_t = 0.40, 0.16
        cen = [(0.0, 260), (peak_t, 820), (0.40, 300)]
    n = secs(dur)
    gain = [(0.0, 0.0), (peak_t * 0.55, 0.45), (peak_t, 1.0), (peak_t + 0.06, 0.55), (dur, 0.0)]
    main = unit(whoosh(n, rng, cen, gain, width=0.36, hp=140))
    body = unit(whoosh(n, rng, [(p[0], p[1] * 0.45) for p in cen], gain, width=0.6, hp=90))
    air = unit(whoosh(n, rng, [(p[0], p[1] * 2.4) for p in cen], gain, width=0.4, lp=6500))
    y = main + (0.3 if variant != 3 else 0.5) * body + 0.16 * air
    if variant == 3:
        t = tvec(n)
        woom = np.sin(TAU * np.cumsum(pts(t, [(0, 70), (peak_t, 95), (dur, 60)])) / SR)
        woom *= env_points(n, gain)
        y = y + 0.32 * unit(woom) + 0.25 * body
    else:
        # silbido muy tenue de la punta
        whistle = unit(whoosh(n, rng, [(p[0], p[1] * 1.9) for p in cen], gain, width=0.06, lp=7000))
        y = y + 0.12 * whistle
    y *= env_points(n, gain) ** 0.3
    return finish(y, dur, -3.0, fade_in=0.004, fade_out=0.04)


def bash() -> np.ndarray:
    rng = rng_for("bash")
    n = secs(0.6)
    y = np.zeros(n)
    y += 1.0 * thump(n, 150, 60, 0.025, 0.09)
    y += 0.55 * unit(burst(n, rng, 0.022, [("lp", 900, 0.7)]))
    f = 405.0
    clang = damped_modes(n, [f * r for r in (1.0, 1.51, 2.31, 2.87, 3.73, 4.45, 5.6)],
                         [1.0, 0.75, 0.6, 0.42, 0.3, 0.2, 0.1], [0.26, 0.21, 0.16, 0.13, 0.1, 0.08, 0.06],
                         attack=0.0015, rng=rng, beat=2.5)
    clang = filt(clang, [("lp", 5200, 0.7), ("hp", 250, 0.7)])
    place(y, unit(clang), 0.004, 0.42)
    place(y, unit(burst(secs(0.05), rng, 0.004, [("bp", 2600, 1.0)])), 0.003, 0.12)
    y = wet(y, "small", 0.18)
    return finish(y, 0.5, -3.0, fade_out=0.08)


def dodge() -> np.ndarray:
    rng = rng_for("dodge")
    n = secs(0.4)
    gain = [(0.0, 0.0), (0.045, 0.7), (0.085, 1.0), (0.16, 0.45), (0.32, 0.0)]
    cloth = unit(whoosh(n, rng, [(0, 750), (0.085, 1350), (0.3, 600)], gain, width=0.8, lp=4800, hp=150))
    t = tvec(n)
    cloth *= 1.0 + 0.18 * np.sin(TAU * 34 * t)  # aleteo de tela
    scrape = unit(whoosh(n, rng, [(0, 900), (0.3, 700)], [(0, 0), (0.11, 0), (0.15, 1.0), (0.3, 0.0)], width=1.0,
                         lp=3500))
    times = np.sort(rng.uniform(0.12, 0.3, 28))
    grit = grain_cloud(n, rng, times, np.exp(-(times - 0.12) / 0.08), 1200, 3600, 0.0008, 0.0025)
    grit = filt(grit, lp4(4500))
    y = cloth + 0.35 * scrape + 0.24 * unit(grit)
    y = wet(y, "small", 0.12)
    return finish(y, 0.35, -3.0, fade_in=0.003, fade_out=0.05)


def hit(variant: int) -> np.ndarray:
    rng = rng_for("hit", variant)
    n = secs(0.3)
    p = {1: (130, 68, 2000, 1200, 0.075), 2: (150, 80, 2300, 1400, 0.065), 3: (115, 58, 1800, 1050, 0.1)}[variant]
    y = np.zeros(n)
    y += 1.0 * thump(n, p[0], p[1], 0.018, 0.05, attack=0.0015)
    y += 0.4 * unit(burst(n, rng, 0.012, [("bp", 1000, 0.9), ("lp", 3500, 0.7)]))
    y += 0.35 * unit(burst(n, rng, 0.03, [("lp", 500, 0.7)]))
    hiss = whoosh(n, rng, [(0, p[2]), (0.25, p[3])], [(0, 0), (0.008, 1.0), (0.04, 0.6), (0.25, 0.0)], width=0.6,
                  lp=5000)
    hiss = unit(hiss) * env_perc(n, 0.006, p[4])
    y += 0.32 * hiss
    # oscuridad: resonancia grave breve (la criatura de sombra se deshace)
    dark = whoosh(n, rng, [(0, 330), (0.2, 220)], [(0, 0), (0.01, 1), (0.15, 0)], width=0.35)
    y += 0.25 * unit(dark)
    y = wet(y, "small", 0.15)
    return finish(y, 0.25, -3.0, fade_out=0.05, lp=7000)


def hero_hurt() -> np.ndarray:
    rng = rng_for("hero_hurt")
    n = secs(0.35)
    y = np.zeros(n)
    y += 0.9 * thump(n, 95, 58, 0.02, 0.07)
    y += 0.7 * unit(burst(n, rng, 0.04, [("lp", 420, 0.7)]))
    y += 0.18 * unit(burst(n, rng, 0.03, [("bp", 1400, 0.8)]))
    clink = damped_modes(secs(0.25), [1650, 2480, 3410, 4300], [1.0, 0.6, 0.35, 0.18], [0.09, 0.07, 0.05, 0.035],
                         attack=0.001, rng=rng, beat=3.0)
    place(y, unit(filt(clink, [("lp", 6000, 0.7)])), 0.009, 0.28)
    y = wet(y, "small", 0.12)
    return finish(y, 0.3, -3.0, fade_out=0.05)


def hero_down() -> np.ndarray:
    rng = rng_for("hero_down")
    n = secs(1.1)
    y = np.zeros(n)
    k1 = thump(secs(0.4), 85, 55, 0.02, 0.07) + 0.6 * unit(burst(secs(0.4), rng, 0.035, [("lp", 380, 0.7)]))
    place(y, k1, 0.0, 0.55)
    k2 = thump(secs(0.6), 72, 44, 0.03, 0.12) + 0.8 * unit(burst(secs(0.6), rng, 0.05, [("lp", 320, 0.7)]))
    place(y, k2, 0.14, 1.0)
    # escudo de bronce que cae y "baila" sobre el borde
    impacts = [0.21, 0.34, 0.43, 0.5, 0.551, 0.588, 0.616, 0.637, 0.653, 0.666]
    f = 330.0
    for i, ti in enumerate(impacts):
        a = 0.85 * (0.78 ** i)
        m = damped_modes(secs(0.45), [f * r for r in (1.0, 1.51, 2.31, 2.87, 3.73, 4.45)],
                         [1.0, 0.7, 0.55, 0.35, 0.25, 0.12], [0.2, 0.16, 0.12, 0.1, 0.08, 0.06], attack=0.001,
                         rng=rng, beat=2.0)
        m = filt(m, [("lp", 4800, 0.7), ("hp", 200, 0.7)])
        place(y, unit(m) * 0.5 + 0.1 * unit(burst(secs(0.45), rng, 0.006, [("bp", 1600, 1.0), ("lp", 4500, 0.7)])),
              ti, a * 0.5)
    dust = whoosh(n, rng, [(0, 900), (1.0, 600)], [(0, 0), (0.16, 0), (0.25, 1), (0.9, 0)], width=1.2, lp=2000)
    y += 0.12 * unit(dust)
    y = wet(y, "small", 0.2)
    return finish(y, 1.0, -3.0, fade_out=0.12)


def lightning() -> np.ndarray:
    rng = rng_for("lightning")
    n = secs(2.2)
    crack = np.zeros(n)
    c0 = burst(secs(0.3), rng, 0.014, [("lp", 6000, 0.7), ("peak", 1600, 0.8, 4.0), ("hp", 250, 0.7)],
               attack=0.0005)
    place(crack, unit(c0), 0.0, 0.9)
    for tt in rng.uniform(0.004, 0.08, 7):
        c = burst(secs(0.05), rng, rng.uniform(0.002, 0.006), [("bp", rng.uniform(1000, 3200), 1.2), ("lp", 5000, 0.7)])
        place(crack, unit(c), tt, rng.uniform(0.25, 0.5))
    rip = whoosh(secs(0.5), rng, [(0, 2600), (0.3, 400)], [(0, 1), (0.05, 0.8), (0.3, 0)], width=0.8, lp=5000)
    place(crack, unit(rip), 0.005, 0.45)
    crack = wet(crack, "med", 0.25)
    # trueno que rueda: ruido marrón, corte descendente y "baches" de intensidad
    bumps = np.clip(0.35 + 0.8 * smooth_random(n, rng, 3.2), 0.12, 1.8)

    def mag(t, f):
        fc = pts(t, [(0, 700), (0.35, 320), (1.0, 180), (2.2, 110)], log=True)
        g = pts(t, [(0, 0), (0.06, 0.3), (0.3, 1.0), (0.7, 0.8), (1.3, 0.4), (2.1, 0.0)])
        return g * mag_lp(f, fc, 2.5) / np.sqrt(np.maximum(f, 25) / 25.0) * mag_hp(f, 28, 2.0)
    thunder = unit(spectral_noise(n, mag, rng, nfft=2048)) * bumps
    thunder = wet(unit(thunder), "big", 0.3)
    y = 0.85 * unit(crack) + 1.0 * unit(thunder)
    return finish(y, 2.0, -3.0, fade_in=0.0005, fade_out=0.35, lp=8000)


def favor_ready() -> np.ndarray:
    rng = rng_for("favor_ready")
    n = secs(1.0)
    y = np.zeros(n)
    seq = [("D5", 0.0), ("F#5", 0.065), ("A5", 0.13), ("D6", 0.195), ("F#6", 0.26)]
    for i, (nm, tt) in enumerate(seq):
        c = chime(note(nm), rng, dur=0.8, decay=0.42)
        place(y, c, tt, 0.55 + 0.1 * i)
    rise = whoosh(n, rng, [(0, 900), (0.35, 3200)], [(0, 0), (0.25, 1.0), (0.45, 0.0)], width=0.6, lp=7000)
    y += 0.12 * unit(rise)
    sparkle = whoosh(n, rng, [(0, 4500), (0.6, 6000)], [(0, 0), (0.25, 1.0), (0.7, 0)], width=0.3, lp=7500)
    y += 0.05 * unit(sparkle)
    y = wet(y, "med", 0.35)
    return finish(y, 0.8, -3.0, fade_in=0.002, fade_out=0.2, lp=9000)


# ---------------------------------------------------------------------------
# Criaturas de Nyx
# ---------------------------------------------------------------------------

def enemy_spawn() -> np.ndarray:
    rng = rng_for("enemy_spawn")
    n = secs(1.4)
    # oleaje oscuro que sube (agua)
    swell = whoosh(n, rng, [(0, 220), (0.75, 700), (1.2, 500)], [(0, 0), (0.55, 0.8), (0.8, 1.0), (1.15, 0)],
                   width=0.8, lp=2500, nfft=1024)
    # borboteo: burbujas cada vez más densas
    times = np.sort(np.concatenate([rng.uniform(0.1, 0.95, 26), rng.uniform(0.45, 0.9, 14)]))
    bub = bubbles(n, rng, times, 240, 900, 0.01, 0.04, 0.9, amp=np.clip((times - 0.05) / 0.7, 0.25, 1.0))
    # silbido fantasmal que asciende
    ghost = whoosh(n, rng, [(0.3, 300), (1.05, 1600)], [(0, 0), (0.35, 0), (0.85, 1.0), (1.12, 0)], width=0.22,
                   lp=4500, nfft=1024)
    t = tvec(n)
    f = pts(t, [(0, 196), (0.4, 208), (1.05, 440)], log=True) * (1 + 0.01 * np.sin(TAU * 5.5 * t))
    ph = TAU * np.cumsum(f) / SR
    tone = (np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * env_points(n, [(0, 0), (0.4, 0), (0.92, 1),
                                                                                         (1.15, 0)])
    y = 0.6 * unit(swell) + 0.55 * unit(bub) + 0.7 * unit(ghost) + 0.16 * unit(tone)
    y = wet(y, "med", 0.3)
    return finish(y, 1.2, -3.0, fade_in=0.01, fade_out=0.12, lp=7000)


def enemy_die() -> np.ndarray:
    rng = rng_for("enemy_die")
    n = secs(0.7)
    smoke = whoosh(n, rng, [(0, 2200), (0.5, 330)], [(0, 0), (0.03, 1.0), (0.18, 0.7), (0.55, 0)], width=0.7,
                   lp=6000)
    puff = burst(n, rng, 0.05, [("lp", 700, 0.7)], attack=0.004)
    t = tvec(n)
    f = pts(t, [(0, 560), (0.5, 170)], log=True) * (1 + 0.015 * np.sin(TAU * 6 * t))
    ph = TAU * np.cumsum(f) / SR
    sigh = (np.sin(ph) + 0.3 * np.sin(2 * ph)) * env_points(n, [(0, 0), (0.04, 1), (0.45, 0)])
    y = unit(smoke) + 0.4 * unit(puff) + 0.13 * unit(sigh)
    y = wet(y, "med", 0.3)
    return finish(y, 0.6, -3.0, fade_in=0.002, fade_out=0.12)


def ker_screech() -> np.ndarray:
    rng = rng_for("ker_screech")
    n = secs(0.6)
    t = tvec(n)
    out = np.zeros(n)
    for v, (det, g) in enumerate(((0.0, 1.0), (32.0, 0.55))):
        f = pts(t, [(0, 1050), (0.13, 1480), (0.45, 1180)], log=True) * 2 ** (det / 1200)
        f *= 1 + 0.022 * np.sin(TAU * 7.2 * t + v)
        ph = TAU * np.cumsum(f) / SR
        out += g * (np.sin(ph) + 0.18 * np.sin(2 * ph))
    env = env_points(n, [(0, 0), (0.05, 0.75), (0.14, 1.0), (0.3, 0.6), (0.48, 0)])
    tone = unit(out) * env
    air = whoosh(n, rng, [(0, 1700), (0.13, 2400), (0.45, 1900)],
                 [(0, 0), (0.05, 0.75), (0.14, 1.0), (0.3, 0.6), (0.48, 0)], width=0.45, lp=5500)
    hiss = whoosh(n, rng, [(0, 3500), (0.45, 3000)], [(0, 0), (0.06, 1), (0.4, 0)], width=0.6, lp=6000)
    y = 0.45 * tone + 0.8 * unit(air) + 0.2 * unit(hiss)
    y = wet(y, "med", 0.35)
    return finish(y, 0.5, -3.0, fade_in=0.004, fade_out=0.08, lp=7000)


def cyclops_stomp() -> np.ndarray:
    rng = rng_for("cyclops_stomp")
    n = secs(0.9)
    y = np.zeros(n)
    y += 1.0 * thump(n, 95, 42, 0.035, 0.18, attack=0.003)
    y += 0.5 * unit(burst(n, rng, 0.05, [("lp", 300, 0.7)]))
    rum = whoosh(n, rng, [(0, 120), (0.8, 80)], [(0, 0), (0.02, 1), (0.25, 0.6), (0.8, 0)], width=1.0, nfft=2048,
                 hp=25)
    y += 0.45 * unit(rum)
    times = np.sort(rng.uniform(0.04, 0.5, 30))
    deb = grain_cloud(n, rng, times, np.exp(-(times - 0.04) / 0.15), 500, 2800, 0.001, 0.004)
    y += 0.12 * unit(filt(deb, [("lp", 3000, 0.7)]))
    y = wet(y, "med", 0.15)
    return finish(y, 0.8, -3.0, fade_out=0.15)


def cyclops_roar() -> np.ndarray:
    rng = rng_for("cyclops_roar")
    n = secs(1.6)
    v = growl_voice(n, rng, [(0, 66), (0.35, 84), (0.9, 78), (1.5, 58)],
                    [(0, 380, 800, 2300), (0.3, 560, 950, 2400), (1.0, 600, 1000, 2400), (1.5, 420, 800, 2300)],
                    rough=0.55, breath=0.22, lp=2600)
    env = env_points(n, [(0, 0), (0.12, 0.6), (0.35, 1.0), (1.0, 0.85), (1.45, 0.0)])
    y = v * env
    t = tvec(n)
    sub = np.sin(TAU * np.cumsum(pts(t, [(0, 40), (0.4, 48), (1.5, 36)])) / SR) * env
    y = unit(y) + 0.25 * sub
    y = wet(y, "med", 0.25)
    return finish(y, 1.5, -3.0, fade_in=0.01, fade_out=0.15, lp=5000)


def hydra_roar() -> np.ndarray:
    rng = rng_for("hydra_roar")
    n = secs(2.7)
    y = np.zeros(n)
    heads = [
        (0.0, [(0, 52), (0.5, 64), (1.4, 60), (2.1, 44)], [(0, 350, 700, 2200), (0.6, 520, 900, 2300), (2.1, 380, 720, 2200)], 1.0),
        (0.12, [(0, 78), (0.45, 96), (1.2, 88), (1.9, 66)], [(0, 420, 900, 2400), (0.5, 650, 1100, 2500), (1.9, 450, 850, 2300)], 0.7),
        (0.26, [(0, 112), (0.4, 136), (1.1, 124), (1.7, 92)], [(0, 500, 1100, 2600), (0.45, 720, 1250, 2600), (1.7, 520, 1000, 2500)], 0.5),
    ]
    for off, f0p, fp, g in heads:
        m = n - secs(off)
        dur = f0p[-1][0] + 0.25
        v = growl_voice(m, rng, f0p, fp, rough=0.6, breath=0.4, lp=2600)
        env = env_points(m, [(0, 0), (0.15, 0.55), (0.45, 1.0), (dur * 0.65, 0.8), (dur, 0.0)])
        place(y, unit(v * env), off, g)
    hiss = whoosh(n, rng, [(0, 3600), (2.2, 3000)], [(0, 0), (0.3, 0.5), (0.7, 1.0), (1.6, 0.5), (2.3, 0)],
                  width=0.5, lp=6500)
    y += 0.1 * unit(hiss)
    rum = whoosh(n, rng, [(0, 90), (2.3, 70)], [(0, 0), (0.3, 1.0), (1.6, 0.7), (2.4, 0)], width=0.9, nfft=2048,
                 hp=25)
    y += 0.35 * unit(rum)
    y = wet(unit(y), "big", 0.35)
    return finish(y, 2.5, -3.0, fade_in=0.01, fade_out=0.3, lp=6000)


def hydra_spit() -> np.ndarray:
    rng = rng_for("hydra_spit")
    n = secs(0.6)
    sp = burst(n, rng, 0.03, [("lp", 1200, 0.7), ("peak", 420, 1.5, 6.0)], attack=0.002)
    bub = bubbles(n, rng, np.sort(rng.uniform(0.0, 0.08, 9)), 420, 1500, 0.004, 0.012, 1.5)
    wh = whoosh(n, rng, [(0, 600), (0.11, 1800), (0.45, 800)], [(0, 0), (0.04, 0.6), (0.11, 1.0), (0.45, 0)],
                width=0.6, lp=6000)
    t = tvec(n)
    slosh = whoosh(n, rng, [(0, 450), (0.3, 320)], [(0, 1), (0.25, 0)], width=0.5) * (
        0.6 + 0.4 * np.sin(TAU * 12 * t))
    y = 0.6 * unit(sp) + 0.35 * unit(bub) + 0.9 * unit(wh) + 0.3 * unit(slosh)
    y = wet(y, "small", 0.15)
    return finish(y, 0.5, -3.0, fade_in=0.002, fade_out=0.08)


def orb_hit() -> np.ndarray:
    rng = rng_for("orb_hit")
    n = secs(0.6)
    y = np.zeros(n)
    y += 0.9 * thump(n, 110, 52, 0.03, 0.12)

    def mag(t, f):
        fc = pts(t, [(0, 2200), (0.12, 260), (0.5, 150)], log=True)
        g = pts(t, [(0, 0), (0.006, 1.0), (0.3, 0.2), (0.5, 0)])
        return g * mag_lp(f, fc, 2.0) * (1.0 + 2.5 * mag_reso(f, fc, fc * 0.3)) * mag_hp(f, 60, 1)
    whomp = unit(spectral_noise(n, mag, rng, nfft=512))
    y += 0.6 * whomp
    t = tvec(n)
    dark = np.zeros(n)
    for fr, a in ((146.8, 1.0), (155.6, 0.7), (220.0, 0.5), (293.7, 0.3)):
        fm = 1.0 + 0.004 * np.sin(TAU * 7.0 * t)
        dark += a * np.sin(TAU * np.cumsum(fr * fm) / SR + rng.uniform(0, TAU))
    dark *= env_perc(n, 0.004, 0.16)
    y += 0.3 * unit(dark)
    tail = whoosh(n, rng, [(0, 900), (0.5, 400)], [(0, 0), (0.02, 1), (0.45, 0)], width=0.9, lp=2500)
    y += 0.25 * unit(tail)
    y = wet(y, "med", 0.25)
    return finish(y, 0.5, -3.0, fade_out=0.1)


# ---------------------------------------------------------------------------
# Torres, edificios, soldados
# ---------------------------------------------------------------------------

def arrow_shoot() -> np.ndarray:
    rng = rng_for("arrow_shoot")
    n = secs(0.35)
    t = tvec(n)
    f = 118.0 * (1 + 0.07 * np.exp(-t / 0.03))
    ph = TAU * np.cumsum(f) / SR
    tw = sum((1.0 / k ** 1.7) * np.sin(k * ph + rng.uniform(0, TAU)) * np.exp(-t / (0.045 / k ** 0.4))
             for k in range(1, 12))
    tw[: secs(0.002)] *= ramp_up(secs(0.002))
    tw = filt(tw, [("lp", 3000, 0.7), ("peak", 600, 1.0, 3.0)])
    snap = unit(burst(n, rng, 0.006, [("bp", 1500, 0.9)]))
    wh = whoosh(n, rng, [(0, 1800), (0.06, 3000), (0.28, 1500)], [(0, 0), (0.02, 0.5), (0.06, 1.0), (0.28, 0)],
                width=0.5, lp=7000)
    flutter = 1 + 0.25 * np.sin(TAU * 58 * t)
    y = 0.9 * unit(tw) + 0.3 * snap + 0.55 * unit(wh) * flutter
    y = wet(y, "small", 0.12)
    return finish(y, 0.3, -3.0, fade_out=0.06)


def arrow_hit() -> np.ndarray:
    rng = rng_for("arrow_hit")
    n = secs(0.25)
    y = np.zeros(n)
    y += damped_modes(n, [520, 1180, 1960, 2750], [1.0, 0.5, 0.25, 0.12], [0.045, 0.03, 0.02, 0.015],
                      attack=0.0008, rng=rng)
    y += 0.8 * thump(n, 170, 95, 0.012, 0.035)
    y += 0.35 * unit(burst(n, rng, 0.005, [("bp", 1300, 1.0)]))
    t = tvec(n)
    quiver = whoosh(n, rng, [(0, 700), (0.2, 650)], [(0, 0), (0.01, 1), (0.18, 0)], width=0.25) * (
        0.5 + 0.5 * np.sin(TAU * 46 * t))
    y += 0.18 * unit(quiver)
    y = wet(unit(y), "small", 0.12)
    return finish(y, 0.2, -3.0, fade_out=0.05, lp=8000)


def zap() -> np.ndarray:
    rng = rng_for("zap")
    n = secs(0.45)
    t = tvec(n)
    f = pts(t, [(0, 1350), (0.25, 260), (0.45, 200)], log=True)
    f = f * (1 + 0.05 * smooth_random(n, rng, 180.0))
    ph = TAU * np.cumsum(f) / SR
    core = (np.sin(ph) + 0.22 * np.sin(3 * ph) + 0.1 * np.sin(2 * ph)) * env_points(n, [(0, 0), (0.008, 1), (0.08, 0.7),
                                                                                       (0.3, 0.0)])
    buzz_f = 110.0
    bph = TAU * buzz_f * t
    buzz = sum(np.sin(k * bph) / k for k in range(1, 18))
    buzz = filt(buzz, [("lp", 2200, 0.7)]) * env_points(n, [(0, 0), (0.01, 1), (0.16, 0)]) * (
        0.6 + 0.4 * np.abs(smooth_random(n, rng, 60.0)))
    times = np.sort(rng.exponential(0.06, 26))
    times = times[times < 0.3]
    crackle = filt(grain_cloud(n, rng, times, np.exp(-times / 0.1), 1500, 3800, 0.0006, 0.002, q=1.0), lp4(5000))
    y = 0.8 * unit(core) + 0.35 * unit(buzz) + 0.38 * unit(crackle)
    y = wet(y, "small", 0.15)
    return finish(y, 0.4, -3.0, fade_in=0.002, fade_out=0.08, lp=6500)


def structure_hit() -> np.ndarray:
    rng = rng_for("structure_hit")
    n = secs(0.3)
    y = np.zeros(n)
    y += damped_modes(n, [210, 480, 870, 1350, 2050], [1.0, 0.7, 0.4, 0.25, 0.12], [0.08, 0.05, 0.035, 0.025, 0.018],
                      attack=0.001, rng=rng)
    y += 0.8 * thump(n, 115, 70, 0.015, 0.05)
    y += 0.4 * unit(burst(n, rng, 0.008, [("lp", 2500, 0.7)]))
    times = np.sort(rng.uniform(0.01, 0.12, 10))
    y += 0.12 * unit(grain_cloud(n, rng, times, 1.0, 800, 3000, 0.001, 0.003))
    y = wet(unit(y), "small", 0.15)
    return finish(y, 0.25, -3.0, fade_out=0.06, lp=7000)


def structure_break() -> np.ndarray:
    rng = rng_for("structure_break")
    n = secs(1.35)
    y = np.zeros(n)
    for tt in np.sort(rng.uniform(0.0, 0.1, 9)):
        c = burst(secs(0.06), rng, rng.uniform(0.002, 0.008), [("bp", rng.uniform(900, 2600), 1.1)])
        place(y, unit(c), tt, rng.uniform(0.3, 0.6))
    wood = damped_modes(secs(0.5), [180, 410, 760, 1150], [1.0, 0.6, 0.35, 0.2], [0.12, 0.08, 0.05, 0.035],
                        attack=0.001, rng=rng)
    place(y, unit(wood), 0.02, 0.5)
    for tt, g in ((0.12, 1.0), (0.46, 0.7)):
        th = thump(secs(0.6), 80, 45, 0.03, 0.12) + 0.8 * unit(burst(secs(0.6), rng, 0.05, [("lp", 420, 0.7)]))
        place(y, th, tt, g)
    times = np.sort(np.concatenate([rng.uniform(0.1, 1.0, 40), rng.uniform(0.12, 0.5, 25)]))
    amps = np.exp(-(times - 0.1) / 0.35)
    deb = np.zeros(n)
    for tt, a in zip(times, amps):
        k = secs(0.06)
        fc = np.exp(rng.uniform(np.log(300), np.log(2400)))
        s = burst(k, rng, rng.uniform(0.003, 0.012), [("bp", fc, 1.4)])
        s += 0.4 * damped_modes(k, [fc * 1.0, fc * 1.7], [1, 0.5], [0.012, 0.008], attack=0.0006, rng=rng)
        place(deb, unit(s), tt, a * rng.uniform(0.3, 1.0))
    y += 0.55 * unit(deb)
    rum = whoosh(n, rng, [(0, 200), (1.2, 120)], [(0, 0), (0.12, 1), (0.6, 0.5), (1.2, 0)], width=1.0, nfft=2048,
                 hp=30)
    y += 0.4 * unit(rum)
    dust = whoosh(n, rng, [(0, 1200), (1.2, 800)], [(0, 0), (0.3, 1), (1.2, 0)], width=1.2, lp=3000)
    y += 0.12 * unit(dust)
    y = wet(unit(y), "med", 0.2)
    return finish(y, 1.2, -3.0, fade_out=0.2, lp=8000)


def soldier_hit() -> np.ndarray:
    rng = rng_for("soldier_hit")
    n = secs(0.25)
    y = np.zeros(n)
    y += damped_modes(n, [890, 1420, 2130, 2960, 3870], [1.0, 0.7, 0.45, 0.28, 0.15], [0.1, 0.08, 0.06, 0.045, 0.035],
                      attack=0.0008, rng=rng, beat=3.0)
    y = filt(y, [("lp", 5500, 0.7)])
    y = unit(y) * 0.7 + 0.8 * thump(n, 140, 90, 0.012, 0.03)
    y += 0.15 * unit(burst(n, rng, 0.004, [("bp", 2500, 1.0)]))
    y = wet(unit(y), "small", 0.12)
    return finish(y, 0.2, -3.0, fade_out=0.05, lp=8000)


# ---------------------------------------------------------------------------
# Economía y construcción
# ---------------------------------------------------------------------------

def coin_tone(rng, f1: float = 2100.0, decay: float = 0.11) -> np.ndarray:
    n = secs(0.3)
    y = damped_modes(n, [f1, f1 * 1.52, f1 * 2.33, f1 * 0.5], [1.0, 0.42, 0.14, 0.05],
                     [decay, decay * 0.55, decay * 0.32, decay * 0.4], attack=0.0008, rng=rng, beat=2.0)
    y += 0.1 * unit(burst(n, rng, 0.0015, [("bp", 3800, 1.4), ("lp", 6000, 0.7)]))
    return filt(y, lp4(7500))


def coin() -> np.ndarray:
    rng = rng_for("coin")
    y = coin_tone(rng)
    y = wet(unit(y), "small", 0.1)
    return finish(y, 0.25, -3.0, fade_in=0.0005, fade_out=0.06, lp=9000)


def income() -> np.ndarray:
    rng = rng_for("income")
    n = secs(1.3)
    y = np.zeros(n)
    k = 17
    u = np.linspace(0, 1, k)
    times = 0.06 + 0.82 * (u ** 1.35)  # cascada: más densa al principio
    times += rng.normal(0, 0.008, k)
    for i, tt in enumerate(np.sort(times)):
        c = coin_tone(rng, f1=rng.uniform(1850, 2750), decay=rng.uniform(0.08, 0.13))
        place(y, unit(c), max(tt, 0), (0.95 - 0.45 * i / k) * rng.uniform(0.6, 1.0))
    pouch = thump(secs(0.3), 120, 80, 0.02, 0.05) + 0.6 * unit(burst(secs(0.3), rng, 0.03, [("lp", 600, 0.7)]))
    place(y, pouch, 0.0, 0.3)
    y = wet(y, "small", 0.14)
    return finish(y, 1.2, -3.0, fade_out=0.15, lp=9000)


def _lyre_chord(rng, seq, bright: float = 0.6, length: float = 1.1) -> np.ndarray:
    n = secs(length)
    y = np.zeros(n)
    for nm, tt, vel in seq:
        p = lyre_pluck(note(nm), rng, vel=vel, bright=bright)
        place(y, p, tt, 1.0)
    return filt(y, LYRE_BODY)


def build_done() -> np.ndarray:
    rng = rng_for("build_done")
    n = secs(1.1)
    y = np.zeros(n)
    wood = damped_modes(secs(0.4), [175, 400, 760], [1.0, 0.55, 0.25], [0.08, 0.05, 0.03], attack=0.0012, rng=rng)
    thud = 0.8 * thump(secs(0.4), 120, 75, 0.02, 0.06) + 0.5 * unit(wood)
    place(y, thud, 0.0, 0.85)
    ch = _lyre_chord(rng, [("D4", 0.03, 0.75), ("A4", 0.095, 0.78), ("D5", 0.16, 0.82), ("F#5", 0.225, 0.86)], 0.55)
    y += 1.1 * unit(ch)
    y = wet(y, "small", 0.22)
    return finish(y, 1.0, -3.0, fade_out=0.3, lp=9000)


def upgrade() -> np.ndarray:
    rng = rng_for("upgrade")
    n = secs(1.1)
    y = np.zeros(n)
    wood = damped_modes(secs(0.4), [220, 500, 940], [1.0, 0.5, 0.25], [0.06, 0.04, 0.025], attack=0.001, rng=rng)
    place(y, 0.6 * thump(secs(0.4), 140, 90, 0.015, 0.045) + 0.4 * unit(wood), 0.0, 0.6)
    ch = _lyre_chord(rng, [("A4", 0.02, 0.72), ("D5", 0.075, 0.76), ("F#5", 0.13, 0.8), ("A5", 0.185, 0.84),
                           ("D6", 0.24, 0.86)], 0.75)
    y += 1.0 * unit(ch)
    c = chime(note("D6"), rng, dur=0.85, decay=0.4)
    place(y, c, 0.27, 0.22)
    c2 = chime(note("A6"), rng, dur=0.7, decay=0.3)
    place(y, c2, 0.33, 0.1)
    y = wet(y, "small", 0.25)
    return finish(y, 1.0, -3.0, fade_out=0.3, lp=9500)


# ---------------------------------------------------------------------------
# Interfaz
# ---------------------------------------------------------------------------

def ui_move() -> np.ndarray:
    rng = rng_for("ui_move")
    n = secs(0.1)
    y = damped_modes(n, [1180, 2650, 620], [1.0, 0.3, 0.45], [0.012, 0.006, 0.01], attack=0.0008, rng=rng)
    y = filt(y, [("lp", 4500, 0.7)])
    return finish(y, 0.08, -6.0, fade_in=0.0005, fade_out=0.02)


def ui_select() -> np.ndarray:
    rng = rng_for("ui_select")
    n = secs(0.35)
    y = np.zeros(n)
    place(y, lyre_pluck(note("D5"), rng, vel=0.85, t60=0.55, bright=0.5), 0.0, 1.0)
    place(y, lyre_pluck(note("A5"), rng, vel=0.6, t60=0.45, bright=0.45), 0.018, 0.45)
    y = filt(y, LYRE_BODY)
    y = wet(unit(y), "small", 0.15)
    return finish(y, 0.25, -4.0, fade_in=0.0005, fade_out=0.08)


def ui_back() -> np.ndarray:
    rng = rng_for("ui_back")
    n = secs(0.3)
    y = lyre_pluck(note("A4"), rng, vel=0.8, t60=0.45, bright=0.35)
    y = np.concatenate([y, np.zeros(max(0, n - len(y)))])[:n]
    y = filt(y, LYRE_BODY)
    y = wet(unit(y), "small", 0.12)
    return finish(y, 0.2, -4.0, fade_in=0.0005, fade_out=0.07)


def blessing() -> np.ndarray:
    rng = rng_for("blessing")
    n = secs(2.2)
    y = np.zeros((n, 2))
    for nm, g in (("A3", 0.6), ("D4", 0.9), ("F#4", 0.75), ("A4", 0.8), ("D5", 0.6)):
        v = pad_note(note(nm), 1.15, rng, kind="choir", vowel=("a", "o", 0.35), voices=4, detune=8,
                     vib_depth=9, attack=0.55, release=0.75, breath=0.3)
        m = min(len(v), n)
        y[:m] += g * v[:m]
    y = y.mean(axis=1)
    b = bell(note("D6"), rng, dur=1.8, decay=0.9, bright=0.5)
    place(y, unit(b) * np.max(np.abs(y)), 0.42, 0.45)
    c = chime(note("A6"), rng, dur=1.2, decay=0.5)
    place(y, unit(c) * np.max(np.abs(y)), 0.5, 0.12)
    y = wet(y, "med", 0.4)
    return finish(y, 2.0, -3.0, fade_in=0.005, fade_out=0.35, lp=9000)


# ---------------------------------------------------------------------------
# Mundo vivo
# ---------------------------------------------------------------------------

def cat_purr() -> np.ndarray:
    """Ronroneo de 2,0 s en bucle perfecto (50 pulsos a 25 Hz, respiración periódica)."""
    rng = rng_for("cat_purr")
    n = secs(2.0)
    t = tvec(n)
    period = n // 50  # 1764 muestras = 25 Hz exactos
    # pulso glotal: tren periódico de impulsos suaves
    k = np.arange(n) % period
    w = int(period * 0.45)
    pulse = np.where(k < w, np.sin(np.pi * k / w) ** 2, 0.0)
    nz = rng.standard_normal(n)
    src = pulse * (0.55 + 0.45 * nz) + 0.15 * nz
    body = filt(src, [("peak", 190, 1.8, 9.0), ("peak", 440, 2.0, 5.0), ("lp", 900, 0.7), ("hp", 45, 0.7)],
                circular=True)
    # respiración: inspiración breve (0-0.8 s), espiración más larga (0.8-2.0 s), periódica
    u = t / 2.0
    breath_env = np.where(u < 0.4, 0.62 * np.sin(np.pi * u / 0.4) ** 0.7,
                          np.sin(np.pi * (u - 0.4) / 0.6) ** 0.6)
    breath_env = 0.12 + 0.88 * breath_env
    air = filt(rng.standard_normal(n), [("lp", 1600, 0.7), ("hp", 200, 0.7)], circular=True)
    y = unit(body) * breath_env + 0.06 * unit(air) * breath_env
    y = filt(y, [("hp", 30, 0.7), ("lp", 2500, 0.7)], circular=True)
    return normalize_peak(y, -3.0)


def cat_meow() -> np.ndarray:
    """"Mrrp" de boca cerrada: chirrido ascendente con trino (vibración rodada) y cierre rápido."""
    rng = rng_for("cat_meow")
    n = secs(0.45)
    t = tvec(n)
    f0 = pts(t, [(0, 500), (0.1, 560), (0.24, 760), (0.31, 720), (0.36, 690)], log=True)
    f0 *= 1 + 0.006 * smooth_random(n, rng, 14)
    ph = TAU * np.cumsum(f0) / SR
    open_ = env_points(n, [(0, 0.0), (0.16, 0.1), (0.27, 1.0), (0.32, 0.6), (0.36, 0.0)])  # la boca se abre al final
    F1 = 450 + 550 * open_
    out = np.zeros(n)
    for k in range(1, 9):
        fk = k * f0
        a = (0.42 ** (k - 1)) * (0.35 + 0.65 * mag_reso(fk, F1, 260)) * (1 + 0.6 * open_ * (k > 1))
        out += a * np.sin(k * ph + rng.uniform(0, TAU))
    trill_depth = env_points(n, [(0, 0.8), (0.17, 0.75), (0.25, 0.0)])
    trill = 1.0 - trill_depth * (0.5 + 0.5 * np.sin(TAU * 27 * t))
    env = env_points(n, [(0, 0), (0.025, 0.55), (0.12, 0.8), (0.27, 1.0), (0.335, 0.7), (0.36, 0.0)])
    y = unit(out) * trill * env
    breath = whoosh(n, rng, [(0, 1300), (0.36, 1700)], [(0, 0), (0.03, 0.6), (0.27, 1), (0.36, 0)], width=0.7,
                    lp=4500)
    y += 0.05 * unit(breath)
    y = filt(y, [("hp", 200, 0.7), ("lp", 5000, 0.7)])
    y = wet(y, "small", 0.1)
    return finish(y, 0.4, -3.0, fade_in=0.003, fade_out=0.04, lp=6000)


def splash() -> np.ndarray:
    rng = rng_for("splash")
    n = secs(0.9)
    y = np.zeros(n)
    k = secs(0.12)
    t = tvec(k)
    plop = np.sin(TAU * np.cumsum(260 + 700 * (1 - np.exp(-t / 0.012))) / SR) * env_perc(k, 0.0015, 0.028)
    place(y, plop, 0.0, 0.55)

    def mag(t, f):
        fc = pts(t, [(0, 900), (0.4, 1700)], log=True)
        g = pts(t, [(0, 0), (0.008, 1.0), (0.05, 0.75), (0.2, 0.35), (0.6, 0.06), (0.8, 0)])
        return g * mag_band(f, fc, 1.0) * mag_lp(f, 4200, 2) * mag_hp(f, 150, 1)
    body = unit(spectral_noise(n, mag, rng, nfft=512))
    y += 0.8 * body
    times = np.sort(np.concatenate([rng.uniform(0.04, 0.25, 18), rng.uniform(0.15, 0.65, 16)]))
    drops = bubbles(n, rng, times, 600, 2200, 0.003, 0.012, 1.5, amp=np.exp(-(times - 0.04) / 0.3))
    y += 0.4 * unit(drops)
    y += 0.4 * unit(burst(n, rng, 0.06, [("lp", 320, 0.7)], attack=0.002))
    y = wet(y, "small", 0.15)
    return finish(y, 0.8, -3.0, fade_in=0.001, fade_out=0.15, lp=6500)


def gull() -> np.ndarray:
    rng = rng_for("gull")
    n = secs(0.7)
    t = tvec(n)
    f0 = pts(t, [(0, 820), (0.07, 1180), (0.16, 1120), (0.36, 720), (0.42, 660)], log=True)
    f0 *= 1 + 0.008 * smooth_random(n, rng, 20)
    ph = TAU * np.cumsum(f0) / SR
    out = np.zeros(n)
    for k, a in enumerate((1.0, 0.9, 0.45, 0.25, 0.12, 0.06), start=1):
        fk = k * f0
        out += a * mag_band(fk, 2100, 1.0) * np.sin(k * ph + rng.uniform(0, TAU))
    rough = 1 + 0.25 * np.sin(TAU * 78 * t)
    env = env_points(n, [(0, 0), (0.03, 0.8), (0.08, 1.0), (0.3, 0.75), (0.42, 0.0)])
    y = unit(out) * rough * env
    y += 0.08 * unit(whoosh(n, rng, [(0, 2000), (0.4, 1500)], [(0, 0), (0.05, 1), (0.4, 0)], width=0.7, lp=5000))
    y = filt(y, [("lp", 3600, 0.7), ("hp", 350, 0.7)])  # lejana: apagada
    y = wet(y, "med", 0.45)
    return finish(y, 0.6, -10.0, fade_in=0.004, fade_out=0.12, lp=6000)


def night_horn() -> np.ndarray:
    """Llamada de caracola/salpinx: D3 -> A3 ligado, con caída de labio al final."""
    rng = rng_for("night_horn")
    n = secs(2.9)
    t = tvec(n)
    seg = [(0.0, 50 - 2.0), (0.18, 50.0), (0.6, 50.0), (0.7, 57.0), (1.75, 57.0), (2.05, 55.6)]
    m = pts(t, seg)
    vib = (6.0 * np.sin(TAU * 4.3 * t) * np.clip((t - 0.9) / 0.5, 0, 1)) / 100.0
    f0 = midi_hz(m + vib) * (1 + 0.002 * smooth_random(n, rng, 3))
    env = env_points(n, [(0, 0), (0.12, 0.55), (0.45, 0.8), (0.62, 0.65), (0.8, 0.9), (1.5, 1.0), (1.85, 0.8),
                         (2.1, 0.0)])
    ph = TAU * np.cumsum(f0) / SR
    out = np.zeros(n)
    bright = env ** 1.4
    for k in range(1, 16):
        fk = k * f0
        base = 1.0 / k ** 1.25
        a = base * (0.25 + 0.75 * bright) ** (0.8 * (k - 1)) * (0.6 + 0.6 * mag_band(fk, 950, 0.8)) * mag_lp(fk, 2400, 2)
        out += a * np.sin(k * ph + rng.uniform(0, TAU))
    out *= env
    br = whoosh(n, rng, [(0, 900), (2.0, 900)], [(0, 0), (0.1, 1), (2.0, 1), (2.1, 0)], width=0.9, lp=4000)
    y = unit(out) + 0.05 * unit(br) * env
    # segunda caracola, una octava abajo y más lejana
    y2 = np.zeros(n)
    ph2 = TAU * np.cumsum(f0 * 0.5 * 2 ** (4 / 1200)) / SR
    for k in range(1, 10):
        y2 += (1.0 / k ** 1.4) * mag_lp(k * f0 * 0.5, 1500, 2) * np.sin(k * ph2 + rng.uniform(0, TAU))
    y = y + 0.35 * unit(y2) * env_points(n, [(0, 0), (0.25, 0), (0.7, 0.8), (1.6, 1.0), (2.05, 0)])
    y = wet(unit(y), "big", 0.4)
    return finish(y, 2.5, -3.0, fade_in=0.01, fade_out=0.35, lp=7000)


def footstep() -> np.ndarray:
    rng = rng_for("footstep")
    n = secs(0.15)
    y = 0.6 * thump(n, 90, 60, 0.012, 0.025, attack=0.002)
    y += 0.35 * unit(burst(n, rng, 0.02, [("lp", 700, 0.7)], attack=0.002))
    times = np.sort(rng.uniform(0.004, 0.07, 16))
    crunch = grain_cloud(n, rng, times, np.exp(-times / 0.04), 1200, 4000, 0.0008, 0.0025)
    y += 0.3 * unit(filt(crunch, [("lp", 5000, 0.7)]))
    return finish(y, 0.12, -8.0, fade_in=0.001, fade_out=0.03, lp=7000)


# ---------------------------------------------------------------------------
# Registro
# ---------------------------------------------------------------------------

SFX = {
    "swing_1": lambda: swing(1),
    "swing_2": lambda: swing(2),
    "swing_3": lambda: swing(3),
    "bash": bash,
    "dodge": dodge,
    "hit_1": lambda: hit(1),
    "hit_2": lambda: hit(2),
    "hit_3": lambda: hit(3),
    "hero_hurt": hero_hurt,
    "hero_down": hero_down,
    "lightning": lightning,
    "favor_ready": favor_ready,
    "enemy_spawn": enemy_spawn,
    "enemy_die": enemy_die,
    "ker_screech": ker_screech,
    "cyclops_stomp": cyclops_stomp,
    "cyclops_roar": cyclops_roar,
    "hydra_roar": hydra_roar,
    "hydra_spit": hydra_spit,
    "orb_hit": orb_hit,
    "arrow_shoot": arrow_shoot,
    "arrow_hit": arrow_hit,
    "zap": zap,
    "structure_hit": structure_hit,
    "structure_break": structure_break,
    "soldier_hit": soldier_hit,
    "coin": coin,
    "build_done": build_done,
    "upgrade": upgrade,
    "income": income,
    "ui_move": ui_move,
    "ui_select": ui_select,
    "ui_back": ui_back,
    "blessing": blessing,
    "cat_purr": cat_purr,
    "cat_meow": cat_meow,
    "splash": splash,
    "gull": gull,
    "night_horn": night_horn,
    "footstep": footstep,
}

LOOPING_SFX = {"cat_purr"}
