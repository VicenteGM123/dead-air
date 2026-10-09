"""Núcleo DSP de PHAROS (solo numpy).

Todo el audio del juego se sintetiza a partir de este módulo: envolventes,
filtros (biquads RBJ aplicados en el dominio de la frecuencia), ruido
espectral variable en el tiempo, reverb por convolución con una respuesta
al impulso sintética, paneo, mezcla y normalización.

Convenciones:
  * Señales mono = arrays (n,), estéreo = arrays (n, 2), float64 en [-1, 1].
  * Los tiempos se expresan en segundos salvo que el nombre diga "n" (muestras).
  * Todo es determinista: el azar sale siempre de ``rng_for(clave)``.
"""
from __future__ import annotations

import zlib

import numpy as np

SR = 44100
TAU = 2.0 * np.pi


# ---------------------------------------------------------------------------
# Utilidades básicas
# ---------------------------------------------------------------------------

def rng_for(*parts) -> np.random.Generator:
    """RNG determinista a partir de una clave estable (crc32, no hash())."""
    key = "/".join(str(p) for p in parts).encode("utf-8")
    return np.random.default_rng(zlib.crc32(key))


def secs(t: float) -> int:
    return int(round(float(t) * SR))


def tvec(n: int) -> np.ndarray:
    return np.arange(int(n), dtype=np.float64) / SR


def undb(d):
    return 10.0 ** (np.asarray(d, dtype=np.float64) / 20.0)


def todb(a):
    return 20.0 * np.log10(np.maximum(np.abs(a), 1e-12))


def next_pow2(n: int) -> int:
    return 1 << int(np.ceil(np.log2(max(int(n), 2))))


def midi_hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=np.float64) - 69.0) / 12.0)


_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note(name: str) -> int:
    """'D4' -> 62, 'Eb3' -> 51, 'F#5' -> 78 (MIDI)."""
    name = name.strip()
    letter = name[0].upper()
    i, acc = 1, 0
    while i < len(name) and name[i] in "#b":
        acc += 1 if name[i] == "#" else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + _PC[letter] + acc


# ---------------------------------------------------------------------------
# Envolventes
# ---------------------------------------------------------------------------

def ramp_up(n: int) -> np.ndarray:
    """Rampa de coseno alzado 0 -> 1 de n muestras (sin clics)."""
    if n <= 0:
        return np.zeros(0)
    return 0.5 - 0.5 * np.cos(np.pi * (np.arange(n) + 0.5) / n)


def _bshape(env: np.ndarray, ndim: int) -> np.ndarray:
    return env if ndim == 1 else env[:, None]


def fades(x: np.ndarray, fin: float = 0.002, fout: float = 0.01) -> np.ndarray:
    """Fundidos de entrada/salida en coseno (evitan clics en los extremos)."""
    y = np.array(x, dtype=np.float64, copy=True)
    a, b = min(secs(fin), len(y)), min(secs(fout), len(y))
    if a > 0:
        y[:a] *= _bshape(ramp_up(a), y.ndim)
    if b > 0:
        y[-b:] *= _bshape(ramp_up(b)[::-1], y.ndim)
    return y


def env_points(n: int, pts, shape: str = "smooth") -> np.ndarray:
    """Envolvente por tramos a partir de [(t, valor), ...].

    shape: "smooth" (smoothstep, derivada continua), "linear", o "exp"
    (interpola en logaritmo; útil para barridos de frecuencia).
    """
    t = tvec(n)
    times = np.array([p[0] for p in pts], dtype=np.float64)
    vals = np.array([p[1] for p in pts], dtype=np.float64)
    if shape == "exp":
        vals = np.log(np.maximum(vals, 1e-9))
    if len(times) == 1:
        out = np.full(n, vals[0])
    else:
        idx = np.clip(np.searchsorted(times, t, side="right") - 1, 0, len(times) - 2)
        t0, t1 = times[idx], times[idx + 1]
        v0, v1 = vals[idx], vals[idx + 1]
        u = np.clip((t - t0) / np.maximum(t1 - t0, 1e-9), 0.0, 1.0)
        if shape in ("smooth", "exp"):
            u = u * u * (3.0 - 2.0 * u)
        out = v0 + (v1 - v0) * u
        out[t < times[0]] = vals[0]
        out[t >= times[-1]] = vals[-1]
    return np.exp(out) if shape == "exp" else out


def env_perc(n: int, attack: float = 0.002, decay: float = 0.2, hold: float = 0.0,
             curve: float = 1.0) -> np.ndarray:
    """Ataque en coseno + caída exponencial (constante de tiempo ``decay``)."""
    t = tvec(n)
    attack = max(attack, 1.0 / SR)
    env = np.exp(-(np.maximum(t - attack - hold, 0.0) / decay) ** curve)
    m = t < attack
    env[m] = 0.5 - 0.5 * np.cos(np.pi * t[m] / attack)
    return env


def env_note(n: int, gate: float, attack: float, decay: float, sustain: float,
             release: float) -> np.ndarray:
    """ADSR suave: ataque coseno, caída exponencial a sustain, release coseno tras gate."""
    t = tvec(n)
    attack = max(attack, 1.0 / SR)
    env = sustain + (1.0 - sustain) * np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-4))
    m = t < attack
    env[m] *= 0.5 - 0.5 * np.cos(np.pi * t[m] / attack)
    rel = np.clip((t - gate) / max(release, 1e-4), 0.0, 1.0)
    env *= 0.5 + 0.5 * np.cos(np.pi * rel)
    return env


def smooth_random(n: int, rng: np.random.Generator, rate: float, circular: bool = False) -> np.ndarray:
    """Curva aleatoria suave (~N(0,1)) con variaciones a ~``rate`` Hz."""
    if circular:
        # espectro aleatorio con número entero de ciclos por periodo -> periódica en n
        k = max(int(round(n / SR * rate)), 1)
        K = min(2 * k, n // 2 - 1)
        h = np.arange(1, K + 1)
        spec = np.zeros(n // 2 + 1, dtype=complex)
        spec[1:K + 1] = (1.0 / (1.0 + (h / k) ** 2)) * np.exp(1j * rng.uniform(0, TAU, K))
        out = np.fft.irfft(spec, n)
        return out / (np.std(out) + 1e-12)
    m = max(int(np.ceil(n / SR * rate)) + 4, 4)
    knots = rng.standard_normal(m)
    x = np.linspace(0, m - 3, n)
    i = np.floor(x).astype(int)
    u = x - i
    # interpolación de Catmull-Rom
    p0, p1, p2, p3 = knots[i], knots[i + 1], knots[i + 2], knots[np.minimum(i + 3, m - 1)]
    out = 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u ** 2
                 + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3)
    return out / (np.std(out) + 1e-12)


# ---------------------------------------------------------------------------
# Filtros (respuestas RBJ evaluadas sobre la rejilla de la FFT)
# ---------------------------------------------------------------------------

def _rbj(kind: str, f0: float, q: float = 0.7071, gain_db: float = 0.0):
    f0 = float(min(max(f0, 5.0), 0.49 * SR))
    A = 10.0 ** (gain_db / 40.0)
    w0 = TAU * f0 / SR
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2.0 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "notch":
        b = [1.0, -2 * cw, 1.0]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "ls":
        s = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + s), 2 * A * ((A - 1) - (A + 1) * cw),
             A * ((A + 1) - (A - 1) * cw - s)]
        a = [(A + 1) + (A - 1) * cw + s, -2 * ((A - 1) + (A + 1) * cw),
             (A + 1) + (A - 1) * cw - s]
    elif kind == "hs":
        s = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + s), -2 * A * ((A - 1) + (A + 1) * cw),
             A * ((A + 1) + (A - 1) * cw - s)]
        a = [(A + 1) - (A - 1) * cw + s, 2 * ((A - 1) - (A + 1) * cw),
             (A + 1) - (A - 1) * cw - s]
    else:
        raise ValueError(kind)
    b = np.array(b, dtype=np.float64)
    a = np.array(a, dtype=np.float64)
    return b / a[0], a / a[0]


def response(specs, freqs: np.ndarray) -> np.ndarray:
    """Respuesta compleja de una cascada de filtros.

    specs: lista de tuplas. ('lp'|'hp'|'bp'|'notch', f, q), ('peak'|'ls'|'hs', f, q, dB),
    ('lp1'|'hp1', f) de un polo, ('gain', dB).
    """
    z1 = np.exp(-1j * TAU * np.asarray(freqs) / SR)
    H = np.ones_like(z1)
    for sp in specs:
        kind = sp[0]
        if kind == "gain":
            H = H * 10.0 ** (sp[1] / 20.0)
        elif kind == "lp1":
            p = np.exp(-TAU * sp[1] / SR)
            H = H * (1 - p) / (1 - p * z1)
        elif kind == "hp1":
            p = np.exp(-TAU * sp[1] / SR)
            H = H * ((1 + p) / 2) * (1 - z1) / (1 - p * z1)
        else:
            b, a = _rbj(*sp)
            H = H * (b[0] + b[1] * z1 + b[2] * z1 * z1) / (a[0] + a[1] * z1 + a[2] * z1 * z1)
    return H


def lp4(fc: float):
    """Paso bajo Butterworth de 4º orden (dos biquads)."""
    return [("lp", fc, 0.5412), ("lp", fc, 1.3066)]


def filt(x: np.ndarray, specs, circular: bool = False, pad: float = 0.6) -> np.ndarray:
    """Aplica filtros causales por FFT. ``circular=True`` -> filtrado periódico (bucles)."""
    x = np.asarray(x, dtype=np.float64)
    if not specs:
        return x.copy()
    n = x.shape[0]
    N = n if circular else next_pow2(n + secs(pad))
    X = np.fft.rfft(x, N, axis=0)
    H = response(specs, np.fft.rfftfreq(N, 1.0 / SR))
    if x.ndim == 2:
        H = H[:, None]
    return np.fft.irfft(X * H, N, axis=0)[:n]


def shape_spectrum(x: np.ndarray, mag_fn, circular: bool = True) -> np.ndarray:
    """Multiplica el espectro por una magnitud real (fase cero). Útil para ruido estacionario."""
    n = x.shape[0]
    N = n if circular else next_pow2(n * 2)
    X = np.fft.rfft(x, N, axis=0)
    f = np.fft.rfftfreq(N, 1.0 / SR)
    M = mag_fn(f)
    if x.ndim == 2:
        M = M[:, None]
    return np.fft.irfft(X * M, N, axis=0)[:n]


# --- formas espectrales útiles para ruido -----------------------------------

def mag_lp(f, fc, order: float = 2.0):
    return 1.0 / np.sqrt(1.0 + (np.asarray(f) / fc) ** (2 * order))


def mag_hp(f, fc, order: float = 2.0):
    f = np.maximum(np.asarray(f), 1e-3)
    return 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))


def mag_band(f, fc, width_oct: float = 1.0):
    """Campana gaussiana en octavas centrada en fc (anchura = sigma en octavas)."""
    f = np.maximum(np.asarray(f), 1.0)
    return np.exp(-0.5 * (np.log2(f / fc) / width_oct) ** 2)


def mag_reso(f, fc, bw):
    """Resonancia tipo lorentziana (pico 1 en fc, anchura bw Hz)."""
    return 1.0 / np.sqrt(1.0 + ((np.asarray(f) - fc) / (0.5 * bw)) ** 2)


# ---------------------------------------------------------------------------
# Ruido
# ---------------------------------------------------------------------------


def colored_noise(n: int, rng: np.random.Generator, mag_fn) -> np.ndarray:
    """Ruido estacionario con espectro |H(f)| (periódico en n: válido para bucles)."""
    x = rng.standard_normal(int(n))
    y = shape_spectrum(x, mag_fn, circular=True)
    return y


def spectral_noise(n: int, mag_fn, rng: np.random.Generator, nfft: int = 1024,
                   circular: bool = False) -> np.ndarray:
    """Ruido de espectro variable en el tiempo (síntesis por STFT con fase aleatoria).

    mag_fn(t, f) recibe t (frames, 1) en segundos y f (1, bins) en Hz y devuelve
    la magnitud deseada (frames, bins). Con mag = 1 el resultado es ruido blanco de
    varianza 1. Con ``circular=True`` el resultado es periódico en n (n % hop == 0).
    """
    hop = nfft // 4
    win = 0.5 - 0.5 * np.cos(TAU * np.arange(nfft) / nfft)  # Hann periódica
    if circular:
        if n % hop:
            raise ValueError("n debe ser múltiplo de nfft/4 para ruido circular")
        nfr = n // hop
    else:
        nfr = int(np.ceil(n / hop)) + 4
    # el frame m empieza en m*hop - nfft/2, su centro está en m*hop
    centers = (np.arange(nfr) * hop) / SR
    freqs = np.fft.rfftfreq(nfft, 1.0 / SR)
    M = np.broadcast_to(mag_fn(centers[:, None], freqs[None, :]), (nfr, len(freqs))).astype(np.float64)
    M = M.copy()
    M[:, 0] = 0.0
    ph = rng.uniform(0.0, TAU, M.shape)
    frames = np.fft.irfft(M * np.exp(1j * ph), nfft, axis=1)
    frames *= win[None, :] * np.sqrt(nfft / 1.5)
    q = frames.reshape(nfr, 4, hop)
    if circular:
        out = np.zeros((nfr, hop))
        for k in range(4):
            out += np.roll(q[:, k, :], k, axis=0)
        out = out.reshape(-1)
        return np.roll(out, -2 * hop)
    out = np.zeros((nfr + 3, hop))
    for k in range(4):
        out[k:k + nfr] += q[:, k, :]
    out = out.reshape(-1)
    return out[2 * hop: 2 * hop + n]


# ---------------------------------------------------------------------------
# Osciladores
# ---------------------------------------------------------------------------

def phase_from_freq(freq: np.ndarray, phase0: float = 0.0) -> np.ndarray:
    """Fase acumulada (en ciclos) a partir de una frecuencia instantánea."""
    return phase0 + np.cumsum(np.asarray(freq, dtype=np.float64)) / SR


def wavetable(amps, phases=None, size: int = 4096) -> np.ndarray:
    """Tabla de un ciclo a partir de amplitudes armónicas (armónico k = amps[k-1])."""
    amps = np.asarray(amps, dtype=np.float64)
    K = len(amps)
    spec = np.zeros(size // 2 + 1, dtype=complex)
    ph = np.zeros(K) if phases is None else np.asarray(phases)
    spec[1:K + 1] = amps * np.exp(1j * ph)
    tab = np.fft.irfft(spec, size) * (size / 2)
    return np.append(tab, tab[0])


def table_osc(tab: np.ndarray, phase_cycles: np.ndarray) -> np.ndarray:
    size = len(tab) - 1
    pos = (phase_cycles % 1.0) * size
    i = pos.astype(np.int64)
    fr = pos - i
    return tab[i] * (1.0 - fr) + tab[i + 1] * fr


def damped_modes(n: int, freqs, amps, decays, attack: float = 0.0015,
                 rng: np.random.Generator | None = None, beat: float = 0.0,
                 pitch_env: np.ndarray | None = None) -> np.ndarray:
    """Suma de modos amortiguados (síntesis modal para impactos, campanas, metales).

    beat > 0 duplica cada modo con un gemelo desafinado +-beat Hz (brillo/shimmer).
    pitch_env multiplica la frecuencia en el tiempo (p. ej. caída de tono de un tambor).
    """
    t = tvec(n)
    out = np.zeros(n)
    for i, (f, a, d) in enumerate(zip(freqs, amps, decays)):
        if f >= 0.45 * SR or a == 0:
            continue
        ph0 = 0.0 if rng is None else rng.uniform(0, TAU)
        env = np.exp(-t / d)
        if pitch_env is not None:
            ph = TAU * np.cumsum(f * pitch_env) / SR
        else:
            ph = TAU * f * t
        if beat > 0:
            db_ = beat * (0.5 + (rng.uniform() if rng is not None else 0.5))
            s = (np.sin(ph + ph0) + 0.35 * np.sin(ph * (1 + db_ / f) + ph0 * 1.7)) / 1.35
        else:
            s = np.sin(ph + ph0)
        out += a * env * s
    if attack > 0:
        a_n = min(secs(attack), n)
        out[:a_n] *= ramp_up(a_n)
    return out


# ---------------------------------------------------------------------------
# Reverb por convolución con respuesta al impulso sintética
# ---------------------------------------------------------------------------

def make_ir(rt60_low: float = 2.2, rt60_high: float = 0.9, length: float | None = None,
            predelay: float = 0.012, rng: np.random.Generator | None = None, stereo: bool = True,
            lp: float = 8000.0, hp: float = 60.0, early: int = 6, fade_in: float = 0.006,
            density_ms: float = 0.0) -> np.ndarray:
    """IR sintética: ruido con caída exponencial dependiente de la frecuencia.

    RT60 interpola (en log-frecuencia) entre ``rt60_low`` (<=250 Hz) y ``rt60_high``
    (>=8 kHz). Incluye reflexiones tempranas suaves y entrada en coseno. Energía unitaria.
    """
    rng = rng if rng is not None else rng_for("ir", rt60_low, rt60_high)
    length = length if length is not None else 1.15 * max(rt60_low, rt60_high)
    n = secs(length)

    def mag(t, f):
        u = np.clip(np.log2(np.maximum(f, 1.0) / 250.0) / np.log2(8000.0 / 250.0), 0.0, 1.0)
        rt = rt60_low * (rt60_high / rt60_low) ** u
        m = 10.0 ** (-3.0 * t / rt)
        return m * mag_lp(f, lp, 1.5) * mag_hp(f, hp, 1.0)

    chans = []
    for c in range(2 if stereo else 1):
        x = spectral_noise(n, mag, rng, nfft=1024)
        # reflexiones tempranas (filtradas, decrecientes)
        if early:
            er = np.zeros(n)
            times = np.sort(rng.uniform(0.004, 0.045, early))
            for k, tt in enumerate(times):
                i = secs(tt)
                if i < n:
                    er[i] += (0.9 - 0.6 * k / early) * rng.choice([-1, 1]) * 2.2
            er = filt(er, [("lp", 5000, 0.7)])
            x = x * 1.0 + er * np.std(x[: secs(0.08)])
        env = np.ones(n)
        fi = secs(fade_in)
        env[:fi] = ramp_up(fi)
        x *= env
        d = secs(predelay)
        x = np.concatenate([np.zeros(d), x])[:n]
        chans.append(x)
    ir = np.stack(chans, axis=1) if stereo else chans[0]
    e = np.sqrt(np.sum(ir ** 2) / (2 if stereo else 1))
    return ir / (e + 1e-12)


def convolve(x: np.ndarray, ir: np.ndarray, circular: bool = False) -> np.ndarray:
    """Convolución por FFT. x mono/estéreo, ir mono/estéreo (se emparejan por canal).

    Lineal: devuelve len(x) + len(ir) - 1. Circular: devuelve len(x) (periódica).
    """
    x = np.asarray(x, dtype=np.float64)
    ir = np.asarray(ir, dtype=np.float64)
    n, m = x.shape[0], ir.shape[0]
    if circular:
        if m > n:
            # pliega la IR sobre el periodo (equivalente para convolución circular)
            reps = int(np.ceil(m / n))
            pad = np.zeros((reps * n,) + ir.shape[1:])
            pad[:m] = ir
            ir = pad.reshape((reps, n) + ir.shape[1:]).sum(axis=0)
        N = n
    else:
        N = next_pow2(n + m - 1)
    X = np.fft.rfft(x, N, axis=0)
    R = np.fft.rfft(ir, N, axis=0)
    if X.ndim == 1 and R.ndim == 2:
        X = X[:, None]
    if X.ndim == 2 and R.ndim == 1:
        R = R[:, None]
    y = np.fft.irfft(X * R, N, axis=0)
    return y[:n] if circular else y[: n + m - 1]


def reverb(x: np.ndarray, ir: np.ndarray, wet: float, dry: float = 1.0,
           circular: bool = False) -> np.ndarray:
    """Mezcla seco + húmedo. Mantiene la longitud de x (no circular: x debe traer cola)."""
    w = convolve(x, ir, circular=circular)[: x.shape[0]]
    if x.ndim == 1 and w.ndim == 2:
        x = np.stack([x, x], axis=1)
    return dry * x + wet * w


# ---------------------------------------------------------------------------
# Estéreo, mezcla y niveles
# ---------------------------------------------------------------------------

def pan(x: np.ndarray, p: float) -> np.ndarray:
    """Paneo de potencia constante: p en [-1 (izq), 1 (der)]. Devuelve (n, 2)."""
    th = (float(np.clip(p, -1, 1)) + 1.0) * np.pi / 4.0
    return np.stack([x * np.cos(th), x * np.sin(th)], axis=1) * np.sqrt(2.0)


def add_at(buf: np.ndarray, sig: np.ndarray, start: int, gain: float = 1.0) -> None:
    """Suma sig en buf a partir de la muestra start (recortando a los límites)."""
    if sig.ndim == 1 and buf.ndim == 2:
        sig = np.stack([sig, sig], axis=1) * np.sqrt(0.5)
    n = sig.shape[0]
    s0, s1 = max(start, 0), min(start + n, buf.shape[0])
    if s1 > s0:
        buf[s0:s1] += gain * sig[s0 - start: s1 - start]


def add_wrapped(buf: np.ndarray, sig: np.ndarray, start: int, gain: float = 1.0) -> None:
    """Como add_at pero envolviendo módulo len(buf) (para bucles)."""
    L = buf.shape[0]
    if sig.ndim == 1 and buf.ndim == 2:
        sig = np.stack([sig, sig], axis=1) * np.sqrt(0.5)
    pos = 0
    start %= L
    n = sig.shape[0]
    while pos < n:
        s = (start + pos) % L
        k = min(L - s, n - pos)
        buf[s:s + k] += gain * sig[pos:pos + k]
        pos += k


def rms_db(x: np.ndarray) -> float:
    return float(todb(np.sqrt(np.mean(np.asarray(x) ** 2)) + 1e-12))


def peak_db(x: np.ndarray) -> float:
    return float(todb(np.max(np.abs(x)) + 1e-12))


def normalize_peak(x: np.ndarray, target_db: float = -3.0) -> np.ndarray:
    p = np.max(np.abs(x))
    return x * (undb(target_db) / p) if p > 0 else x


def normalize_rms(x: np.ndarray, target_db: float) -> np.ndarray:
    r = np.sqrt(np.mean(x ** 2))
    return x * (undb(target_db) / r) if r > 0 else x


def soft_clip(x: np.ndarray, threshold_db: float = -6.0, ceiling_db: float = -1.0) -> np.ndarray:
    """Limitador suave sin memoria: lineal bajo el umbral, rodilla tanh hasta el techo."""
    t, c = undb(threshold_db), undb(ceiling_db)
    a = np.abs(x)
    over = a > t
    y = np.array(x, copy=True)
    y[over] = np.sign(x[over]) * (t + (c - t) * np.tanh((a[over] - t) / (c - t)))
    return y


def limiter(x: np.ndarray, ceiling_db: float = -1.0, lookahead: float = 0.003,
            release_db_s: float = 30.0, circular: bool = False) -> np.ndarray:
    """Limitador con anticipación y liberación lineal en dB (sin distorsión audible).

    La reducción necesaria (dB) pasa por un máximo deslizante hacia delante, una
    liberación de ``release_db_s`` dB/s (truco de cummax, vectorizado) y un suavizado
    causal; el resultado nunca supera el techo.
    """
    a = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    gr = np.maximum(0.0, todb(a) - ceiling_db)
    if gr.max() <= 0.0:
        return x.copy()
    n = len(gr)
    work = np.concatenate([gr, gr]) if circular else gr
    m = len(work)
    w = max(secs(lookahead), 1)
    padded = np.concatenate([work, work[:w] if circular else np.zeros(w)])
    A = padded[:m].copy()
    for k in range(1, w + 1):
        np.maximum(A, padded[k:k + m], out=A)
    idx = np.arange(m, dtype=np.float64)
    rate = release_db_s / SR
    R = np.maximum.accumulate(A + idx * rate) - idx * rate
    h = np.hanning(w + 2)[1:-1]
    h /= h.sum()
    S = np.convolve(R, h)[:m]
    S = np.maximum(S, work)  # seguridad
    S = S[n:] if circular else S
    g = undb(-S)
    return x * (g if x.ndim == 1 else g[:, None])
