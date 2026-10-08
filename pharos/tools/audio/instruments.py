"""Instrumentos sintetizados para PHAROS.

  * lyre_pluck   – lira pulsada (Karplus–Strong vectorizado por bloques, afinación fraccional)
  * aulos_phrase – aulós de doble caña (aditivo con armónicos impares, vibrato tardío,
                   portamento, aliento y "chiff" en los ataques)
  * pad_note     – pad de cuerdas o coro (ensemble de voces desafinadas, formantes vocales)
  * frame_drum   – tímpano / pandero (síntesis modal de membrana + golpe de piel)
  * bell         – campana (parciales inarmónicos con batido)
  * brass_note   – metal grave en "swell" (tablas que se abren con la dinámica)
  * drone        – bordón grave
  * cymbal_swell – platillo suave en crescendo
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, TAU, damped_modes, env_note, env_points, filt, mag_band, mag_lp, mag_reso,
                 midi_hz, phase_from_freq, ramp_up, secs, smooth_random, spectral_noise,
                 table_osc, tvec, wavetable, mag_hp)

# ---------------------------------------------------------------------------
# Lira (Karplus–Strong)
# ---------------------------------------------------------------------------

LYRE_BODY = [("hp", 65, 0.7), ("peak", 210, 1.0, 2.5), ("peak", 1050, 1.1, 1.2),
             ("peak", 3300, 0.9, -3.0), ("lp", 7200, 0.7)]


def ks_string(freq: float, n: int, rng: np.random.Generator, t60: float, damp: float = 0.12,
              pos: float = 0.18, exc_cut: float = 3000.0, noise_mix: float = 0.3) -> np.ndarray:
    """Cuerda Karplus–Strong con filtro de lazo [b, 1-2b, b] * interpolación lineal fraccional.

    El lazo y[n] = e[n] + rho * sum_k c_k y[n-N-k] solo mira >= N muestras atrás,
    así que se calcula por bloques de N muestras con numpy (rápido y exacto).
    """
    P = SR / freq
    N = int(np.floor(P)) - 1
    frac = P - 1.0 - N
    taps = np.convolve([damp, 1.0 - 2.0 * damp, damp], [1.0 - frac, frac])
    w0 = TAU * freq / SR
    H0 = abs(np.sum(taps * np.exp(-1j * w0 * np.arange(4))))
    rho = min(10.0 ** (-3.0 / (t60 * freq)) / H0, 0.99997)
    c = taps * rho
    # excitación: forma triangular (punto de pulsación) + ruido, paso bajo circular
    L = int(np.ceil(P))
    x = (np.arange(L) + 0.5) / L
    tri = np.where(x < pos, x / pos, (1.0 - x) / (1.0 - pos))
    tri = (tri - tri.mean()) / (np.ptp(tri) + 1e-9)
    nz = rng.standard_normal(L)
    nz = (nz - nz.mean()) / (4.0 * np.std(nz) + 1e-9)
    exc = (1.0 - noise_mix) * tri + noise_mix * nz
    E = np.fft.rfft(exc)
    fq = np.fft.rfftfreq(L, 1.0 / SR)
    E *= mag_lp(fq, exc_cut, 1.5)
    exc = np.fft.irfft(E, L)
    y = np.zeros(n + 3)
    y[3:3 + min(L, n)] += exc[: min(L, n)]
    for s in range(N, n, N):
        e = min(s + N, n)
        y[s + 3:e + 3] += (c[0] * y[s + 3 - N:e + 3 - N] + c[1] * y[s + 2 - N:e + 2 - N]
                           + c[2] * y[s + 1 - N:e + 1 - N] + c[3] * y[s - N:e - N])
    return y[3:]


def lyre_pluck(midi: float, rng: np.random.Generator, vel: float = 0.8, dur: float | None = None,
               t60: float | None = None, bright: float = 0.55, muted: bool = False,
               release: float = 0.12, damp: float | None = None) -> np.ndarray:
    """Nota de lira. dur = tiempo hasta apagar la cuerda (None = resonancia natural)."""
    f = float(midi_hz(midi))
    if t60 is None:
        t60 = 3.3 * (196.0 / f) ** 0.5
        if muted:
            t60 = 0.45 * (196.0 / f) ** 0.3
    ring = t60 * 1.05 if dur is None else min(dur + release, t60 * 1.05)
    n = secs(ring) + 64
    exc_cut = (900.0 + 4200.0 * bright * vel) * (0.7 if muted else 1.0)
    pos = rng.uniform(0.13, 0.23)
    d = damp if damp is not None else (0.2 if muted else 0.11)
    y = ks_string(f, n, rng, t60, damp=d, pos=pos, exc_cut=exc_cut)
    # roce del dedo: ruido corto y suave
    k = secs(0.004)
    fn = rng.standard_normal(k) * np.hanning(k) * 0.05 * vel
    y[:k] += filt(fn, [("bp", 2200, 0.8)], pad=0.02)
    a = secs(0.0025)
    y[:a] *= ramp_up(a)
    if dur is not None and dur + release < ring:
        g0 = secs(dur)
        r = secs(release)
        y[g0:g0 + r] *= ramp_up(r)[::-1]
        y = y[: g0 + r]
    else:
        r = secs(0.08)
        y[-r:] *= ramp_up(r)[::-1]
    return y * vel


# ---------------------------------------------------------------------------
# Formantes vocales (tablas de Csound, ensanchadas para un coro suave)
# ---------------------------------------------------------------------------

FORMANTS = {
    ("soprano", "a"): ([800, 1150, 2900, 3900, 4950], [0, -6, -32, -20, -50], [80, 90, 120, 130, 140]),
    ("soprano", "o"): ([450, 800, 2830, 3800, 4950], [0, -11, -22, -22, -50], [70, 80, 100, 130, 135]),
    ("soprano", "u"): ([325, 700, 2700, 3800, 4950], [0, -16, -35, -40, -60], [50, 60, 170, 180, 200]),
    ("alto", "a"): ([800, 1150, 2800, 3500, 4950], [0, -4, -20, -36, -60], [80, 90, 120, 130, 140]),
    ("alto", "o"): ([450, 800, 2830, 3500, 4950], [0, -9, -16, -28, -55], [70, 80, 100, 130, 135]),
    ("alto", "u"): ([325, 700, 2530, 3500, 4950], [0, -12, -30, -40, -64], [50, 60, 170, 180, 200]),
    ("tenor", "a"): ([650, 1080, 2650, 2900, 3250], [0, -6, -7, -8, -22], [80, 90, 120, 130, 140]),
    ("tenor", "o"): ([400, 800, 2600, 2800, 3000], [0, -10, -12, -12, -26], [70, 80, 100, 130, 135]),
    ("tenor", "u"): ([350, 600, 2700, 2900, 3300], [0, -20, -17, -14, -26], [40, 60, 100, 120, 120]),
    ("bass", "a"): ([600, 1040, 2250, 2450, 2750], [0, -7, -9, -9, -20], [60, 70, 110, 120, 130]),
    ("bass", "o"): ([400, 750, 2400, 2600, 2900], [0, -11, -21, -20, -40], [40, 80, 100, 120, 120]),
    ("bass", "u"): ([350, 600, 2400, 2675, 2950], [0, -20, -32, -28, -36], [40, 80, 100, 120, 120]),
}


def voice_for(midi: float) -> str:
    if midi < 52:
        return "bass"
    if midi < 59:
        return "tenor"
    if midi < 67:
        return "alto"
    return "soprano"


def formant_env(f, voice: str, vowel: str, widen: float = 1.8, high_cut_db: float = -8.0):
    """Envolvente espectral de vocal: suma de resonancias (formantes altos atenuados)."""
    if isinstance(vowel, tuple):  # mezcla (vocal1, vocal2, peso2)
        v1, v2, w = vowel
        return (1 - w) * formant_env(f, voice, v1, widen, high_cut_db) + w * formant_env(f, voice, v2, widen,
                                                                                         high_cut_db)
    F, A, B = FORMANTS[(voice, vowel)]
    out = np.zeros_like(np.asarray(f, dtype=np.float64))
    for i, (fc, a, bw) in enumerate(zip(F, A, B)):
        g = 10 ** ((a + (high_cut_db if i >= 2 else 0.0)) / 20.0)
        out = out + g * mag_reso(f, fc, bw * widen)
    return out


# ---------------------------------------------------------------------------
# Pads: cuerdas / coro (ensemble de voces con tabla de ondas)
# ---------------------------------------------------------------------------

def _harm_amps(f0: float, kind: str, vowel, bright: float, voice: str | None = None) -> np.ndarray:
    K = int(min(9500.0 / f0, 80))
    k = np.arange(1, K + 1)
    fk = k * f0
    if kind == "strings":
        a = (1.0 / k) * mag_lp(fk, 1700.0 * bright, 2.0) * (1.0 + 0.8 * mag_band(fk, 420.0, 0.7))
        a *= 1.0 + 0.4 * mag_band(fk, 1300.0, 0.5)
    elif kind == "choir":
        v = voice or voice_for(12 * np.log2(f0 / 440.0) + 69)
        a = (1.0 / k ** 0.75) * formant_env(fk, v, vowel) * mag_lp(fk, 3800.0 * bright, 2.0)
    elif kind == "organ":  # bordón suave / flauta grave
        a = (1.0 / k ** 1.6) * mag_lp(fk, 900.0 * bright, 2.0)
    else:
        raise ValueError(kind)
    return a / (np.max(a) + 1e-12)


def pad_note(midi: float, dur: float, rng: np.random.Generator, kind: str = "strings", vowel="o",
             voices: int = 4, detune: float = 7.0, vib_rate: float = 5.0, vib_depth: float = 5.0,
             attack: float = 0.7, release: float = 1.4, bright: float = 1.0, spread: float = 0.7,
             breath: float = 0.0, sustain: float = 0.9, drift: float = 3.0) -> np.ndarray:
    """Nota de pad estéreo. ``dur`` = duración de la nota (gate) en segundos."""
    f0 = float(midi_hz(midi))
    n = secs(dur + release) + 32
    t = tvec(n)
    amps = _harm_amps(f0, kind, vowel, bright)
    out = np.zeros((n, 2))
    for v in range(voices):
        ph = rng.uniform(0, TAU, len(amps))
        tab = wavetable(amps, ph)
        tab /= np.max(np.abs(tab)) + 1e-12
        cents = (detune * (2.0 * v / max(voices - 1, 1) - 1.0) if voices > 1 else 0.0) + rng.normal(0, 1.2)
        rate = vib_rate * rng.uniform(0.9, 1.1)
        depth = vib_depth * rng.uniform(0.7, 1.2)
        vib = depth * np.sin(TAU * rate * t + rng.uniform(0, TAU))
        vib *= np.clip(t / 0.6, 0, 1)  # el vibrato entra poco a poco
        if drift > 0:
            vib += drift * smooth_random(n, rng, 0.35)
        freq = f0 * 2.0 ** ((cents + vib) / 1200.0)
        sig = table_osc(tab, phase_from_freq(freq, rng.uniform()))
        am = 1.0 + 0.08 * smooth_random(n, rng, 0.5)
        sig *= am
        p = spread * (2.0 * v / max(voices - 1, 1) - 1.0) if voices > 1 else 0.0
        th = (p + 1.0) * np.pi / 4.0
        out[:, 0] += sig * np.cos(th)
        out[:, 1] += sig * np.sin(th)
    out /= np.sqrt(voices)
    env = env_note(n, dur, attack, 1.5, sustain, release)
    out *= env[:, None]
    if breath > 0:
        v = voice_for(midi)

        def mag(tt, f):
            return (formant_env(f, v, vowel if not isinstance(vowel, tuple) else vowel[0], widen=2.5)
                    * mag_lp(f, 5000.0, 2.0) * mag_hp(f, 380.0, 2.0) + 0.0 * tt)
        for c in range(2):
            nz = spectral_noise(n, mag, rng, nfft=1024)
            out[:, c] += breath * nz * env * 0.35
    return out


# ---------------------------------------------------------------------------
# Aulós (doble caña): frase monofónica con legato, portamento y vibrato
# ---------------------------------------------------------------------------

AULOS_BASE = np.array([1.0, 0.30, 0.52, 0.16, 0.30, 0.08, 0.15, 0.045, 0.075, 0.025, 0.035,
                       0.012, 0.015, 0.006])


def aulos_phrase(events, rng: np.random.Generator, vib_depth: float = 16.0, vib_rate: float = 5.3,
                 breath: float = 0.05, mellow: float = 0.5, glide: float = 0.045,
                 drone_midi: float | None = None, drone_gain: float = 0.25,
                 release: float = 0.22) -> tuple[np.ndarray, float]:
    """Sintetiza una frase. events = [(t_inicio_s, dur_s, midi, vel, legato_bool), ...].

    Devuelve (señal mono, t0) donde t0 es el tiempo (s) que corresponde a la muestra 0.
    """
    events = sorted(events, key=lambda e: e[0])
    t0 = events[0][0] - 0.06
    t_end = max(e[0] + e[1] for e in events) + release + 0.1
    n = secs(t_end - t0)
    t = tvec(n) + t0
    # ---- curva de tono (log2 f) con portamento y "scoop" en notas atacadas ----
    lf = np.zeros(n)
    vibdepth = np.zeros(n)
    cur = float(np.log2(midi_hz(events[0][2])))
    groups: list[list[int]] = []
    for i, ev in enumerate(events):
        st, du, m, vel = ev[:4]
        leg = bool(ev[4]) if len(ev) > 4 else False
        if i == 0 or not leg:
            groups.append([i])
        else:
            groups[-1].append(i)
        target = float(np.log2(midi_hz(m)))
        s0 = secs(st - t0)
        s1 = secs(events[i + 1][0] - t0) if i + 1 < len(events) else n
        seg_t = tvec(max(s1 - s0, 0))
        start_val = cur if (leg and i > 0) else target - 0.4 / 12.0
        tau = glide if (leg and i > 0) else 0.035
        lf[s0:s1] = target + (start_val - target) * np.exp(-seg_t / tau)
        cur = target
        if du > 0.3:  # vibrato tardío en notas largas
            vd = np.clip((seg_t - 0.16) / 0.35, 0, 1) * vib_depth * min(1.0, (du - 0.2) / 0.6)
            vibdepth[s0:s1] = vd[: s1 - s0]
    lf[: secs(events[0][0] - t0)] = lf[secs(events[0][0] - t0)]
    # ---- amplitud: cada ligadura es un soplo continuo con pequeñas articulaciones ----
    amp = np.zeros(n)
    onsets = []
    for g in groups:
        gs = events[g[0]][0]
        ge = events[g[-1]][0] + events[g[-1]][1]
        pts = []
        for j in g:
            st, du, m, vel = events[j][:4]
            pts += [(st - t0, vel), (st - t0 + 0.03, vel)]
        level = env_points(n, pts, "smooth")
        a0 = secs(gs - t0)
        att = rng.uniform(0.05, 0.075)
        gate = ge - gs
        nn = n - a0
        e = env_note(nn, gate, att, 0.5, 0.88, release)
        tt = tvec(n)
        shape = np.ones(n)
        for j in g[1:]:  # bajada breve al cambiar de nota ligada
            st = events[j][0] - t0
            shape *= 1.0 - 0.17 * np.exp(-((tt - st - 0.01) / 0.016) ** 2)
        for j in g:  # messa di voce en notas largas
            st, du = events[j][0] - t0, events[j][1]
            if du > 0.75:
                u = np.clip((tt - st) / du, 0, 1)
                shape *= 1.0 + 0.13 * np.sin(np.pi * u) * ((tt >= st) & (tt <= st + du))
        full = np.zeros(n)
        full[a0:] = e
        amp = np.maximum(amp, full * level * shape)
        onsets.append((a0, events[g[0]][3]))
    # micro-desafinación lenta + vibrato
    rate = vib_rate + 0.25 * smooth_random(n, rng, 0.3)
    vph = TAU * np.cumsum(rate) / SR
    cents = vibdepth * np.sin(vph) + 4.0 * smooth_random(n, rng, 1.2)
    freq = 2.0 ** lf * 2.0 ** (cents / 1200.0)
    phase = TAU * np.cumsum(freq) / SR
    # ---- timbre aditivo dependiente de la dinámica ----
    amax = max(np.max(amp), 1e-9)
    dyn = amp / amax
    out = np.zeros(n)
    K = len(AULOS_BASE)
    for k in range(1, K + 1):
        fk = k * freq
        a = AULOS_BASE[k - 1] * (0.55 + 0.45 * mag_band(fk, 1150.0, 1.0)) * mag_lp(fk, 2600.0 + 1400 * (1 - mellow), 2.0)
        a = a * (0.35 + 0.65 * dyn) ** (0.6 * (k - 1))
        a = np.where(fk < 0.45 * SR, a, 0.0)
        out += a * np.sin(k * phase + rng.uniform(0, TAU))
    out *= amp
    # bordón (segundo tubo)
    if drone_midi is not None:
        fd = float(midi_hz(drone_midi)) * 2.0 ** (3.0 * smooth_random(n, rng, 0.5) / 1200.0)
        phd = TAU * np.cumsum(fd) / SR
        dr = np.zeros(n)
        for k in range(1, 9):
            a = AULOS_BASE[k - 1] * mag_lp(k * fd, 2200.0, 2.0)
            dr += a * np.sin(k * phd + rng.uniform(0, TAU))
        denv = filt(np.minimum(amp / amax, 1.0), [("lp1", 3.0)]) if n > 10 else amp
        out += drone_gain * dr * np.clip(denv, 0, None) * amax
    # aliento
    nz = spectral_noise(n, lambda tt, f: mag_band(f, 1700.0, 0.9) * mag_lp(f, 4500, 2) + 0 * tt, rng, nfft=512)
    out += breath * nz * amp * 0.9
    for s0, vel in onsets:
        k = secs(0.035)
        ch = rng.standard_normal(k) * np.hanning(k) * 0.07 * vel
        seg = filt(ch, [("bp", 2400, 0.7)], pad=0.02)
        e = min(s0 + k, n)
        out[s0:e] += seg[: e - s0]
    out[: secs(0.004)] *= ramp_up(secs(0.004))
    return out, t0


# ---------------------------------------------------------------------------
# Percusión
# ---------------------------------------------------------------------------

MEMBRANE = [1.0, 1.593, 2.136, 2.296, 2.653, 2.918, 3.156, 3.501]


def frame_drum(kind: str, rng: np.random.Generator, vel: float = 0.8, size: float = 1.0) -> np.ndarray:
    """Tímpano/pandero. kind: 'dum' (centro, grave), 'tek' (borde), 'big' (gran tambor)."""
    if kind == "big":
        n = secs(1.6)
        t = tvec(n)
        f0 = 52.0 / size
        pe = 1.0 + 0.22 * np.exp(-t / 0.04)
        modes = damped_modes(n, [f0 * r for r in MEMBRANE[:6]], [1.0, 0.45, 0.3, 0.2, 0.12, 0.08],
                             [0.36, 0.2, 0.14, 0.11, 0.09, 0.08], attack=0.002, rng=rng, pitch_env=pe)
        sub = np.sin(TAU * np.cumsum(f0 * 0.82 * pe) / SR) * np.exp(-t / 0.17)
        k = secs(0.05)
        hit = filt(rng.standard_normal(k) * np.exp(-tvec(k) / 0.012), [("lp", 900, 0.7)], pad=0.05)
        y = modes + 0.6 * sub
        y[:k] += 0.5 * hit
        y = filt(y, [("lp", 2500, 0.7)])
    elif kind == "dum":
        n = secs(0.9)
        t = tvec(n)
        f0 = 88.0 / size * rng.uniform(0.985, 1.015)
        pe = 1.0 + 0.14 * np.exp(-t / 0.028)
        br = 0.6 + 0.4 * vel
        modes = damped_modes(n, [f0 * r for r in MEMBRANE[:7]],
                             [1.0, 0.5 * br, 0.34 * br, 0.24 * br, 0.15 * br, 0.1 * br, 0.07 * br],
                             [0.30, 0.17, 0.12, 0.1, 0.08, 0.07, 0.06], attack=0.0015, rng=rng, pitch_env=pe)
        sub = np.sin(TAU * np.cumsum(f0 * 0.75 * pe) / SR) * np.exp(-t / 0.11)
        k = secs(0.04)
        skin = filt(rng.standard_normal(k) * np.exp(-tvec(k) / 0.008), [("lp", 1600, 0.7)], pad=0.05)
        y = modes + 0.35 * sub
        y[:k] += 0.22 * br * skin
        y = filt(y, [("lp", 3200, 0.7)])
    elif kind == "tek":
        n = secs(0.35)
        t = tvec(n)
        f0 = 265.0 / size * rng.uniform(0.97, 1.03)
        modes = damped_modes(n, [f0 * r for r in MEMBRANE[:6]], [0.6, 0.55, 0.45, 0.4, 0.3, 0.2],
                             [0.07, 0.05, 0.045, 0.04, 0.035, 0.03], attack=0.0008, rng=rng)
        k = secs(0.05)
        slap = filt(rng.standard_normal(k) * np.exp(-tvec(k) / 0.009), [("bp", 2300, 0.9), ("lp", 5000, 0.7)],
                    pad=0.05)
        y = modes
        y[:k] += 1.1 * slap
        y = filt(y, [("lp", 5200, 0.7), ("hp", 120, 0.7)])
        y *= 0.75
    else:
        raise ValueError(kind)
    y = y / (np.max(np.abs(y)) + 1e-12)
    r = secs(0.03)
    y[-r:] *= ramp_up(r)[::-1]
    return y * vel


# ---------------------------------------------------------------------------
# Campanas y metales
# ---------------------------------------------------------------------------

BELL_RATIOS = [0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166, 5.433]
BELL_AMPS = [0.28, 1.0, 0.5, 0.3, 0.55, 0.22, 0.12, 0.16, 0.08, 0.04]
BELL_DECAY = [1.7, 1.0, 0.8, 0.55, 0.5, 0.36, 0.3, 0.26, 0.18, 0.12]


def bell(midi: float, rng: np.random.Generator, dur: float = 4.0, decay: float = 2.2,
         bright: float = 0.6, strike: float = 0.25) -> np.ndarray:
    """Campana suave: parciales inarmónicos con caídas distintas y batido lento."""
    f = float(midi_hz(midi))
    n = secs(dur)
    amps = [a * (bright ** max(i - 2, 0) if i > 2 else 1.0) for i, a in enumerate(BELL_AMPS)]
    y = damped_modes(n, [f * r for r in BELL_RATIOS], amps, [decay * d for d in BELL_DECAY],
                     attack=0.0025, rng=rng, beat=0.9)
    k = secs(0.012)
    st = rng.standard_normal(k) * np.exp(-tvec(k) / 0.003)
    y[:k] += strike * filt(st, [("bp", min(3.0 * f, 6000), 1.0)], pad=0.02)
    y = filt(y, [("lp", 7500, 0.7)])
    r = secs(0.2)
    y[-r:] *= ramp_up(r)[::-1]
    return y / (np.max(np.abs(y)) + 1e-12)


def chime(midi: float, rng: np.random.Generator, dur: float = 1.6, decay: float = 0.7) -> np.ndarray:
    """Campanilla cristalina (barra libre: 1, 2.76, 5.40), muy pura."""
    f = float(midi_hz(midi))
    n = secs(dur)
    y = damped_modes(n, [f, f * 2.756, f * 5.404, f * 2.0], [1.0, 0.22, 0.05, 0.08],
                     [decay, decay * 0.35, decay * 0.15, decay * 0.5], attack=0.002, rng=rng, beat=0.6)
    y = filt(y, [("lp", 8000, 0.7)])
    r = secs(0.1)
    y[-r:] *= ramp_up(r)[::-1]
    return y / (np.max(np.abs(y)) + 1e-12)


# ---------------------------------------------------------------------------
# Metal grave en swell, bordón y platillo
# ---------------------------------------------------------------------------

def brass_note(midi: float, dur: float, rng: np.random.Generator, attack: float = 0.45,
               release: float = 0.7, low_cut: float = 300.0, peak_cut: float = 1500.0,
               voices: int = 3, detune: float = 6.0, sustain: float = 0.75, spread: float = 0.35,
               growl: float = 0.0) -> np.ndarray:
    """Metal cálido (tipo trompa/trombón suave) que se abre al crecer la dinámica."""
    f0 = float(midi_hz(midi))
    n = secs(dur + release) + 32
    t = tvec(n)
    env = env_note(n, dur, attack, 0.8, sustain, release)
    K = int(min(5000.0 / f0, 60))
    k = np.arange(1, K + 1)
    cuts = [low_cut, 0.5 * (low_cut + peak_cut), peak_cut]
    out = np.zeros((n, 2))
    morph = np.clip(env, 0, 1) ** 1.3 * 2.0  # 0..2
    for v in range(voices):
        ph = rng.uniform(0, TAU, K)
        tabs = []
        for fc in cuts:
            a = (1.0 / k) * mag_lp(k * f0, fc, 2.5) * (1.0 + 0.5 * mag_band(k * f0, 1100.0, 0.6))
            tb = wavetable(a, ph)
            tabs.append(tb)
        norm = np.max(np.abs(tabs[-1])) + 1e-12
        cents = detune * (2.0 * v / max(voices - 1, 1) - 1.0) + rng.normal(0, 1.0)
        vib = 3.0 * np.sin(TAU * rng.uniform(4.5, 5.5) * t + rng.uniform(0, TAU)) * np.clip((t - 0.5) / 1.0, 0, 1)
        vib += 2.0 * smooth_random(n, rng, 0.6)
        if growl > 0:
            vib += growl * smooth_random(n, rng, 18.0)
        freq = f0 * 2.0 ** ((cents + vib) / 1200.0)
        phs = phase_from_freq(freq, rng.uniform())
        s0, s1, s2 = (table_osc(tb, phs) / norm for tb in tabs)
        w01 = np.clip(morph, 0, 1)
        w12 = np.clip(morph - 1, 0, 1)
        sig = np.where(morph < 1, s0 * (1 - w01) + s1 * w01, s1 * (1 - w12) + s2 * w12)
        p = spread * (2.0 * v / max(voices - 1, 1) - 1.0) if voices > 1 else 0.0
        th = (p + 1.0) * np.pi / 4.0
        out[:, 0] += sig * np.cos(th)
        out[:, 1] += sig * np.sin(th)
    out *= (env / np.sqrt(voices))[:, None]
    # aliento suave
    nz = spectral_noise(n, lambda tt, f: mag_band(f, 900.0, 0.8) + 0 * tt, rng, nfft=1024)
    out += (0.025 * nz * env)[:, None]
    return out


def drone(midi: float, dur: float, rng: np.random.Generator, attack: float = 2.5, release: float = 2.5,
          cutoff: float = 600.0, voices: int = 3, detune: float = 4.0) -> np.ndarray:
    """Bordón grave tipo cuerda frotada / órgano de caña, muy filtrado."""
    f0 = float(midi_hz(midi))
    n = secs(dur + release) + 32
    t = tvec(n)
    K = int(min(4000.0 / f0, 60))
    k = np.arange(1, K + 1)
    a = (1.0 / k ** 1.1) * mag_lp(k * f0, cutoff, 2.0)
    out = np.zeros((n, 2))
    for v in range(voices):
        tab = wavetable(a, rng.uniform(0, TAU, K))
        tab /= np.max(np.abs(tab)) + 1e-12
        cents = detune * (2.0 * v / max(voices - 1, 1) - 1.0) + 2.0 * smooth_random(n, rng, 0.2)
        sig = table_osc(tab, phase_from_freq(f0 * 2.0 ** (cents / 1200.0), rng.uniform()))
        sig *= 1.0 + 0.15 * smooth_random(n, rng, 0.25)
        p = 0.6 * (2.0 * v / max(voices - 1, 1) - 1.0) if voices > 1 else 0.0
        th = (p + 1.0) * np.pi / 4.0
        out[:, 0] += sig * np.cos(th)
        out[:, 1] += sig * np.sin(th)
    env = env_note(n, dur, attack, 1.0, 1.0, release)
    return out * (env / np.sqrt(voices))[:, None]


def cymbal_swell(dur: float, rng: np.random.Generator, peak_at: float = 0.85, tail: float = 1.2) -> np.ndarray:
    """Platillo suave que crece (rodillo con baqueta blanda) y se apaga."""
    n = secs(dur + tail)
    tp = dur * peak_at

    def mag(t, f):
        grow = np.where(t < tp, (np.clip(t / tp, 0, 1)) ** 2.2, np.exp(-(t - tp) / (0.35 * tail)))
        sh = (0.6 * mag_band(f, 3800, 0.6) + 0.5 * mag_band(f, 6200, 0.4) + 0.25 * mag_band(f, 1400, 0.7))
        return grow * sh * mag_lp(f, 8500, 3)
    out = np.stack([spectral_noise(n, mag, rng, nfft=1024) for _ in range(2)], axis=1)
    return out / (np.max(np.abs(out)) + 1e-12)
