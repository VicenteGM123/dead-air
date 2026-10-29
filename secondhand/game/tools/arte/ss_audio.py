"""Secondhand Stars · biblioteca de audio (lane AUDIO).

Síntesis original con numpy/scipy y salida OGG Vorbis con ffmpeg, con el mismo método que tools/arte/audio.py de
Midnight Cauldron, y tres cosas nuevas para un juego web que suena minutos seguidos:
  - render CIRCULAR (clase Pista): la pista tiene una duración exacta y todo lo que suena después del final (colas de
    las notas, reverb, ecos, filtros) vuelve al principio. El archivo es periódico: el loop no tiene costura ni fundido.
  - reverb por convolución con respuestas al impulso sintéticas (sala, muelle de amplificador), circular en los loops.
  - niveles medidos como en Midnight Cauldron (RMS) y sonoridad K (BS.1770) para igualar las músicas entre sí.
Instrumentos: cuerda pulsada Karplus-Strong (guitarra con 'twang', bajo, mandolina), lengüeta tipo armónica y silbido
(motor de frases con ligados, bends y vibrato), pad de sierras desafinadas, percusión de mano, tubos de campanilla.
"""
import os, math, subprocess
import numpy as np
from scipy.signal import lfilter, butter, sosfilt
from scipy.fft import rfft, irfft, rfftfreq, next_fast_len
from scipy.ndimage import minimum_filter1d, uniform_filter1d

SR = 44100
NYQ = SR / 2
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get('SS_AUDIO_OUT', os.path.join(HERE, 'salida', 'audio'))

_OFS = {'C': -9, 'C#': -8, 'Db': -8, 'D': -7, 'D#': -6, 'Eb': -6, 'E': -5, 'F': -4, 'F#': -3, 'Gb': -3, 'G': -2,
        'G#': -1, 'Ab': -1, 'A': 0, 'A#': 1, 'Bb': 1, 'B': 2}


# ------------------------------------------------------------------------------------------------ notas y tiempo
def hz(n):
    """'A4' -> 440.0 (también acepta un número en Hz)."""
    if isinstance(n, (int, float, np.floating)):
        return float(n)
    p, o = n[:-1], int(n[-1])
    return 440.0 * 2 ** ((_OFS[p] + (o - 4) * 12) / 12)


def midi(n):
    p, o = n[:-1], int(n[-1])
    return 69 + _OFS[p] + (o - 4) * 12


def taxis(d):
    return np.arange(int(round(d * SR))) / SR


def rng(seed):
    return np.random.default_rng(seed)


def t60env(t, t60):
    """Caída exponencial que llega a -60 dB en t60 segundos."""
    return np.exp(-6.907755 * np.maximum(t, 0) / max(t60, 1e-4))


def adsr(n, a, d, s, r, hold=None):
    """Envolvente lineal: ataque a, caída d hasta s, sostiene hasta 'hold' (s) y suelta en r. n en muestras."""
    A, D, R = max(1, int(a * SR)), max(1, int(d * SR)), max(1, int(r * SR))
    H = max(0, n - R) if hold is None else min(n, int(hold * SR))
    i = np.arange(n, dtype=float)
    e = np.where(i < A, i / A, np.where(i < A + D, 1 + (s - 1) * (i - A) / D, s))
    if H < n:
        lvl = e[H - 1] if H > 0 else 0.0
        e[H:] = np.maximum(0.0, lvl * (1 - (i[H:] - H) / R))
    return e


def fade(x, fin=0.002, fout=0.01):
    """Fundido corto de entrada y salida (para que los efectos no hagan 'clic')."""
    x = np.array(x, float)
    a, b = int(fin * SR), int(fout * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)[:, None] if x.ndim == 2 else np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)[:, None] if x.ndim == 2 else np.linspace(1, 0, b)
    return x


def pan2(sig, pan=0.0, gain=1.0):
    """Mono -> estéreo con paneo de igual potencia (como place() de Midnight Cauldron: centro = 0.707 por lado)."""
    sig = np.asarray(sig, float)
    if sig.ndim == 2:
        if pan == 0:
            return sig * gain
        l = math.cos((pan + 1) * math.pi / 4) / math.cos(math.pi / 4)
        r = math.sin((pan + 1) * math.pi / 4) / math.sin(math.pi / 4)
        return np.stack([sig[:, 0] * l, sig[:, 1] * r], 1) * gain
    l = math.cos((pan + 1) * math.pi / 4)
    r = math.sin((pan + 1) * math.pi / 4)
    return np.stack([sig * l, sig * r], 1) * gain


# ------------------------------------------------------------------------------------------------ la pista circular
class Pista:
    """Buffer estéreo de duración exacta. Con circular=True lo que pasa del final vuelve al principio."""

    def __init__(self, dur, circular=True):
        self.n = int(round(dur * SR))
        self.dur = self.n / SR
        self.circular = circular
        self.buf = np.zeros((self.n, 2))

    def add(self, sig, t, gain=1.0, pan=0.0):
        st = pan2(sig, pan, gain)
        i0 = int(round(t * SR))
        if self.circular:
            i0 %= self.n
            pos = 0
            while pos < len(st):
                j = (i0 + pos) % self.n
                k = min(len(st) - pos, self.n - j)
                self.buf[j:j + k] += st[pos:pos + k]
                pos += k
        else:
            if i0 >= self.n:
                return
            if i0 < 0:
                st = st[-i0:]
                i0 = 0
            k = min(len(st), self.n - i0)
            self.buf[i0:i0 + k] += st[:k]

    def mix(self, other, gain=1.0):
        self.buf += other.buf * gain if isinstance(other, Pista) else np.asarray(other) * gain


# ------------------------------------------------------------------------------------------------ filtros
def _sos_run(sos, x, circular=False, warm_s=1.5):
    """sosfilt; con circular=True el filtro arranca con el estado que deja el final del propio buffer."""
    x = np.asarray(x, float)
    if not circular:
        return sosfilt(sos, x, axis=0)
    m = min(len(x), int(warm_s * SR))
    zi = np.zeros((sos.shape[0], 2) + x.shape[1:])
    _, zf = sosfilt(sos, x[-m:], axis=0, zi=zi)
    y, _ = sosfilt(sos, x, axis=0, zi=zf)
    return y


def lp(x, fc, order=2, circular=False):
    return _sos_run(butter(order, min(fc, NYQ * 0.95) / NYQ, output='sos'), x, circular)


def hp(x, fc, order=2, circular=False):
    return _sos_run(butter(order, fc / NYQ, 'high', output='sos'), x, circular)


def bp(x, lo, hi, order=2, circular=False):
    return _sos_run(butter(order, [lo / NYQ, min(hi, NYQ * 0.95) / NYQ], 'band', output='sos'), x, circular)


def _biquad(kind, f0, q=0.707, gain_db=0.0):
    A = 10 ** (gain_db / 40)
    w = 2 * math.pi * min(f0, NYQ * 0.95) / SR
    cw, sw = math.cos(w), math.sin(w)
    al = sw / (2 * q)
    sA = math.sqrt(A)
    if kind == 'peak':
        b = [1 + al * A, -2 * cw, 1 - al * A]
        a = [1 + al / A, -2 * cw, 1 - al / A]
    elif kind == 'low':
        b = [A * ((A + 1) - (A - 1) * cw + 2 * sA * al), 2 * A * ((A - 1) - (A + 1) * cw),
             A * ((A + 1) - (A - 1) * cw - 2 * sA * al)]
        a = [(A + 1) + (A - 1) * cw + 2 * sA * al, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - 2 * sA * al]
    elif kind == 'high':
        b = [A * ((A + 1) + (A - 1) * cw + 2 * sA * al), -2 * A * ((A - 1) + (A + 1) * cw),
             A * ((A + 1) + (A - 1) * cw - 2 * sA * al)]
        a = [(A + 1) - (A - 1) * cw + 2 * sA * al, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - 2 * sA * al]
    elif kind == 'res':          # pasa-banda resonante con 0 dB en el pico
        b = [al, 0.0, -al]
        a = [1 + al, -2 * cw, 1 - al]
    else:
        raise ValueError(kind)
    return np.array([[b[0] / a[0], b[1] / a[0], b[2] / a[0], 1.0, a[1] / a[0], a[2] / a[0]]])


def eq(x, kind, f0, gain_db=0.0, q=0.707, circular=False):
    """EQ de un biquad (recetario RBJ): kind = 'peak' | 'low' (estante grave) | 'high' (estante agudo) | 'res'."""
    return _sos_run(_biquad(kind, f0, q, gain_db), x, circular)


def resonators(x, bands, circular=False):
    """Banco de resonancias en paralelo: bands = [(f, q, ganancia)] (formantes, cuerpo de instrumento)."""
    y = np.zeros_like(np.asarray(x, float))
    for f, q, g in bands:
        y += eq(x, 'res', f, q=q, circular=circular) * g
    return y


def sat(x, drive=1.5):
    """Saturación suave (cinta/válvula): misma ganancia en señal baja."""
    return np.tanh(x * drive) / drive


def onepole_lp(x, coef):
    return lfilter([1 - coef], [1, -coef], x, axis=0)


# ------------------------------------------------------------------------------------------------ osciladores
def phase_of(f, n, ph0=0.0):
    f = np.broadcast_to(np.asarray(f, float), (n,))
    inc = f / SR
    ph = (ph0 + np.concatenate([[0.0], np.cumsum(inc[:-1])])) % 1.0
    return ph, inc


def _blep(ph, dt):
    out = np.zeros_like(ph)
    m = ph < dt
    x = ph[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m = ph > 1.0 - dt
    x = (ph[m] - 1.0) / dt[m]
    out[m] = x * x + x + x + 1.0
    return out


def osc_saw(f, n, ph0=0.0):
    ph, dt = phase_of(f, n, ph0)
    return 2 * ph - 1 - _blep(ph, dt)


def osc_pulse(f, n, width=0.5, ph0=0.0):
    ph, dt = phase_of(f, n, ph0)
    s1 = 2 * ph - 1 - _blep(ph, dt)
    ph2 = (ph + 1.0 - width) % 1.0
    s2 = 2 * ph2 - 1 - _blep(ph2, dt)
    p = s1 - s2
    return p - p.mean()


def osc_sine(f, n, ph0=0.0):
    ph, _ = phase_of(f, n, ph0)
    return np.sin(2 * np.pi * ph)


def vibrato(n, rate=5.2, cents=10.0, delay=0.25, ramp=0.35, ph0=0.0):
    """Factor de frecuencia con vibrato que entra despacio (después de 'delay' s)."""
    t = np.arange(n) / SR
    depth = np.clip((t - delay) / max(ramp, 1e-3), 0, 1) * cents
    return 2 ** (depth * np.sin(2 * np.pi * rate * t + ph0) / 1200)


# ------------------------------------------------------------------------------------------------ cuerdas pulsadas
def ks(f, dur, t60=2.0, bright=0.6, pick=0.15, pickup=0.0, S=0.45, seed=0, twang=0.0, twang_tau=0.05,
       exc_len=1.0, exc=None, exc_lp=0.0, vib=0.0, vib_rate=5.5, vib_delay=0.35):
    """Karplus-Strong afinado (allpass fraccional) resuelto con lfilter.
    t60: s hasta -60 dB del fundamental; bright 0..1: brillo del ataque; pick: posición de la púa (0..0.5, cerca del
    puente = más nasal); pickup: posición de la pastilla (filtro peine a la salida, 'twang' eléctrico); S: pérdida de
    agudos en el lazo (0.5 = la más oscura); twang: cents de afinación alta al principio (la cuerda se estira)."""
    r = rng(seed)
    n = int(dur * SR)
    P = SR / f
    N = int(P - S - 0.1)
    d = P - S - N
    c = (1 - d) / (1 + d)
    g = 10 ** (-3.0 / (t60 * f))
    L = max(2, int(N * exc_len))
    e = r.uniform(-1, 1, L) if exc is None else np.asarray(exc, float)[:L]
    coef = (1 - bright) * 0.92
    e = lfilter([1 - coef], [1, -coef], e)
    if exc_lp > 0:                                  # ataque blando (bajo, pulgar): excitación muy filtrada
        e = lp(np.concatenate([e, np.zeros(L)]), min(exc_lp * f, NYQ * 0.9), 2)
        L = len(e)
    if pick > 0:
        k = max(1, int(round(pick * N)))
        e2 = e.copy()
        e2[k:] -= e[:-k]
        e = e2
    e -= e.mean()
    e /= np.abs(e).max() + 1e-9
    x = np.zeros(n)
    x[:min(n, len(e))] = e[:n]
    a = np.zeros(N + 3)
    a[0] = 1.0
    a[1] = c
    a[N] -= g * (1 - S) * c
    a[N + 1] -= g * ((1 - S) + S * c)
    a[N + 2] -= g * S
    y = lfilter([1.0, c], a, x)
    if pickup > 0:
        q = max(1, int(round(pickup * N)))
        y2 = y.copy()
        y2[q:] -= y[:-q]
        y = y2 * 0.7
    if twang or vib:
        t = np.arange(n) / SR
        cents = twang * np.exp(-t / twang_tau)
        if vib:                                     # vibrato de palanca que entra despacio
            cents = cents + vib * np.clip((t - vib_delay) / 0.4, 0, 1) * np.sin(2 * np.pi * vib_rate * t)
        y = pitch_warp(y, cents)
    att = min(n, int(0.0015 * SR))
    y[:att] *= np.linspace(0, 1, att)
    return y


def pitch_warp(y, cents):
    """Cambia la afinación muestra a muestra (cents: array): lectura más rápida = más agudo."""
    n = len(y)
    ratio = 2 ** (np.asarray(cents, float) / 1200)
    pos = np.cumsum(ratio) - ratio[0]
    return np.interp(pos, np.arange(n), y, right=0.0)


def pitch_drop(y, cents0, tau):
    """La nota empieza 'cents0' alta y baja a su afinación en ~tau s (la cuerda recién pulsada se estira)."""
    t = np.arange(len(y)) / SR
    return pitch_warp(y, cents0 * np.exp(-t / tau))


def damp_tail(y, at_s, release=0.08):
    """Apaga la cuerda (mano que la toca) a los at_s segundos."""
    n = len(y)
    i = int(at_s * SR)
    if i >= n:
        return y
    r = max(1, int(release * SR))
    e = np.ones(n)
    k = min(r, n - i)
    e[i:i + k] = np.linspace(1, 0, r)[:k]
    e[i + k:] = 0
    return y * e


# ------------------------------------------------------------------------------------------------ frases (armónica, silbido)
def _pitch_track(notes, n, beat, legato_gap=0.03, glide=0.035, bend_s=0.12):
    """Curva de frecuencia y de 'gate' para una frase: notes = [(nota, inicio_beats, dur_beats, opciones)]."""
    f = np.zeros(n)
    gate = np.zeros(n)
    starts = []
    for idx, nt in enumerate(notes):
        name, b0, db = nt[0], nt[1], nt[2]
        opt = nt[3] if len(nt) > 3 else ''
        s = int(b0 * beat * SR)
        e = min(n, int((b0 + db) * beat * SR))
        if s >= n:
            continue
        fr = hz(name)
        seg = np.full(e - s, fr)
        # bend: entra desde un semitono (o dos con '~~') por debajo
        if '~' in opt:
            semi = 2.0 if '~~' in opt else 1.0
            k = min(len(seg), int(bend_s * (1.6 if semi > 1 else 1.0) * SR))
            x = np.linspace(0, 1, k)
            seg[:k] = fr * 2 ** (-semi * (1 - x) ** 2 / 12)
        if 'v' in opt:   # caída al final (fall-off)
            k = min(len(seg), int(0.18 * SR))
            x = np.linspace(0, 1, k)
            seg[-k:] = seg[-k:] * 2 ** (-1.5 * x ** 2 / 12)
        f[s:e] = seg
        gate[s:e] = 1.0
        starts.append((s, e, opt))
    # ligados: la frecuencia viaja suave entre notas pegadas
    for (s0, e0, _), (s1, e1, o1) in zip(starts, starts[1:]):
        if s1 - e0 <= legato_gap * beat * SR and '~' not in o1:
            k = int(glide * SR)
            a, b = max(s0, s1 - k // 2), min(e1, s1 + k // 2)
            if b > a:
                f0, f1 = f[a - 1] if a > 0 else f[a], f[b] if b < n else f[b - 1]
                x = np.linspace(0, 1, b - a)
                f[a:b] = f0 * (f1 / f0) ** (0.5 - 0.5 * np.cos(np.pi * x))
            gate[e0:s1] = 1.0
    # huecos: mantener la última frecuencia (el oscilador no salta)
    last = f[f > 0][0] if np.any(f > 0) else 440.0
    for i in np.flatnonzero(f == 0):
        f[i] = last if i == 0 else f[i - 1]
    return f, gate, starts


def _amp_env(gate, starts, n, att=0.035, rel=0.12, accent=None):
    """Envolvente de amplitud: rampas de ataque al empezar cada nota no ligada y de suelta al acabar el gate."""
    a = lfilter([1 - math.exp(-1 / (att * SR))], [1, -math.exp(-1 / (att * SR))], gate)
    # suelta más lenta que el ataque
    rel_c = math.exp(-1 / (rel * SR))
    out = np.empty(n)
    out[:] = a
    # cola de suelta: donde el gate cae, se deja decaer con rel
    fall = np.flatnonzero(np.diff(np.concatenate([[0], gate])) < 0)
    for i in fall:
        L = min(n - i, int(rel * 6 * SR))
        if L > 0:
            out[i:i + L] = np.maximum(out[i:i + L], out[i - 1] * rel_c ** np.arange(1, L + 1))
    return out


def reed_phrase(notes, beat, tail=0.6, seed=1, vib_cents=14, breath=0.07, bright=1.0, wah=0.0):
    """Lengüeta libre tipo armónica: pulso + sierra por formantes nasales, aliento, bends ('~'), vibrato de mano."""
    r = rng(seed)
    end = max(b0 + db for _, b0, db, *rest in notes)
    n = int((end * beat + tail) * SR)
    f, gate, starts = _pitch_track(notes, n, beat)
    vib = np.ones(n)
    for s, e, opt in starts:
        L = e - s
        if L > int(0.45 * SR):
            v = vibrato(L, rate=5.0 + r.uniform(-0.3, 0.3), cents=vib_cents, delay=0.28, ramp=0.4,
                        ph0=r.uniform(0, 6.28))
            vib[s:e] = v
    drift = 2 ** (lp(r.normal(0, 1, n), 3.0) * 60 / 1200)    # muy poca deriva de afinación
    ff = f * vib * drift
    src = 0.62 * osc_pulse(ff, n, width=0.36) + 0.38 * osc_saw(ff, n)
    amp = _amp_env(gate, starts, n, att=0.03, rel=0.11)
    # el soplido: un poco más fuerte al empezar cada nota
    puff = np.zeros(n)
    for s, e, opt in starts:
        L = min(n - s, int(0.09 * SR))
        puff[s:s + L] += np.exp(-np.arange(L) / (0.025 * SR))
    tone = resonators(src, [(950, 2.2, 1.0), (1750, 3.0, 0.7 * bright), (2650, 4.0, 0.22 * bright)]) + src * 0.15
    tone = lp(tone, 2600 + 900 * bright)
    nz = bp(r.normal(0, 1, n), 900, 3200) * (breath + 0.25 * puff)
    out = tone * amp + nz * amp
    if wah > 0:   # mano que abre y cierra (wah de armónica) en notas largas: filtro que respira
        w = 0.5 + 0.5 * np.sin(2 * np.pi * 4.2 * np.arange(n) / SR)
        out = out * (1 - wah * 0.5) + lp(out, 1400) * wah * 0.5 * (1 - w) + out * wah * 0.25 * w
    return hp(out, 180)


def whistle_phrase(notes, beat, tail=0.5, seed=2, vib_cents=18, breath=0.05):
    """Silbido humano: casi un seno, con aire y vibrato; ligados con portamento."""
    r = rng(seed)
    end = max(b0 + db for _, b0, db, *rest in notes)
    n = int((end * beat + tail) * SR)
    f, gate, starts = _pitch_track(notes, n, beat, glide=0.06)
    vib = np.ones(n)
    for s, e, opt in starts:
        L = e - s
        if L > int(0.35 * SR):
            vib[s:e] = vibrato(L, rate=5.6 + r.uniform(-0.4, 0.4), cents=vib_cents, delay=0.2, ramp=0.3,
                               ph0=r.uniform(0, 6.28))
    ff = f * vib
    ph, _ = phase_of(ff, n)
    tone = np.sin(2 * np.pi * ph) + 0.06 * np.sin(4 * np.pi * ph)
    amp = _amp_env(gate, starts, n, att=0.045, rel=0.09)
    # aire: ruido de banda estrecha que sigue la nota (aprox: banda ancha alrededor del registro)
    nz = bp(r.normal(0, 1, n), 1200, 5200) * breath
    return (tone + nz) * amp


# ------------------------------------------------------------------------------------------------ pad
def pad_chord(freqs, dur, attack=1.4, release=1.8, cutoff=1500.0, detune=7.0, voices=3, seed=0, level=1.0,
              lfo_rate=0.11, lfo_depth=0.25):
    """Pad cálido: sierras desafinadas por nota, paso-bajo que respira despacio, ataque y suelta lentos."""
    r = rng(seed)
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for fr in freqs:
        for v in range(voices):
            det = (v - (voices - 1) / 2) * detune * 2 / max(1, voices - 1) if voices > 1 else 0.0
            drift = 1 + 0.0009 * np.sin(2 * np.pi * r.uniform(0.07, 0.19) * t + r.uniform(0, 6.28))
            out += osc_saw(fr * 2 ** (det / 1200) * drift, n, ph0=r.uniform(0, 1)) * (0.75 if det else 1.0)
    out /= max(1, len(freqs) * voices) ** 0.5
    # filtro que respira (en bloques: cortes distintos, mezcla suave)
    lfo = 1 + lfo_depth * np.sin(2 * np.pi * lfo_rate * t + r.uniform(0, 6.28))
    lo = lp(out, cutoff * 0.6, 2)
    hi = lp(out, cutoff * 1.4, 2)
    w = np.clip((lfo - (1 - lfo_depth)) / (2 * lfo_depth + 1e-9), 0, 1)
    out = lo * (1 - w) + hi * w
    env = adsr(n, attack, 0.6, 0.85, release, hold=dur)
    return out * env * level


# ------------------------------------------------------------------------------------------------ percusión de mano
def shaker(seed=0, accent=1.0, length=0.11, bright=1.0):
    r = rng(seed)
    n = int(length * SR)
    t = np.arange(n) / SR
    nz = bp(r.normal(0, 1, n), 3200 * (0.85 + 0.15 * bright), 11000)
    env = np.minimum(1, t / 0.010) * np.exp(-np.maximum(0, t - 0.010) / 0.038)
    grains = 1 + 0.6 * (r.random(n) < 0.02) * r.uniform(0.5, 1.5, n)
    return nz * env * grains * accent


def hand_drum(f0=95.0, seed=0, accent=1.0, slap=0.5, decay=0.32):
    """Tambor de mano / de marco: golpe grave con caída de tono, segundo modo y la palma."""
    r = rng(seed)
    n = int((decay * 1.6 + 0.05) * SR)
    t = np.arange(n) / SR
    fr = f0 * (1 + 0.55 * np.exp(-t / 0.018))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    body = np.sin(ph) * t60env(t, decay) + 0.35 * np.sin(1.59 * ph + 0.3) * t60env(t, decay * 0.45)
    palm = bp(r.normal(0, 1, n), 250, 1600) * t60env(t, 0.05) * slap
    y = (body + palm) * np.minimum(1, t / 0.0015)
    return y * accent


def edge_tap(seed=0, accent=1.0, tone=780.0):
    """Golpe de borde / madera (el 'tak' del tambor de mano)."""
    r = rng(seed)
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    knock = np.sin(2 * np.pi * tone * t) * t60env(t, 0.05) + 0.4 * np.sin(2 * np.pi * tone * 2.31 * t) * t60env(t, 0.03)
    click = bp(r.normal(0, 1, n), 1500, 6000) * t60env(t, 0.018) * 0.6
    return (knock + click) * accent * np.minimum(1, t / 0.0008)


# ------------------------------------------------------------------------------------------------ metal: tubos y campanas
def chime_tube(f, dur=3.5, seed=0, bright=1.0, t60=3.2):
    """Tubo de campanilla de viento: parciales de barra libre-libre (1, 2.76, 5.40, 8.93), batido leve, golpe."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for ratio, amp, dec in [(1.0, 1.0, 1.0), (2.756, 0.55 * bright, 0.55), (5.404, 0.28 * bright, 0.3),
                            (8.933, 0.12 * bright, 0.17)]:
        fr = f * ratio
        if fr > NYQ * 0.9:
            continue
        beat = r.uniform(0.3, 1.2)
        ph = r.uniform(0, 6.28)
        y += amp * (np.sin(2 * np.pi * fr * t + ph) + 0.35 * np.sin(2 * np.pi * (fr + beat) * t + ph * 1.7)) \
            * t60env(t, t60 * dec)
    strike = bp(r.normal(0, 1, n), min(f * 2, 8000), min(f * 8, 16000)) * t60env(t, 0.006) * 0.4
    return (y / 1.35 + strike) * np.minimum(1, t / 0.0005)


def bell_tone(f, dur=2.0, bright=1.0, seed=0):
    """Campanita pequeña (parciales de campana)."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for ratio, amp, dec in [(1, 1.0, 1.0), (2.0, 0.4, 0.6), (2.76, 0.25 * bright, 0.4), (4.07, 0.15 * bright, 0.25),
                            (5.4, 0.08 * bright, 0.15)]:
        if f * ratio < NYQ * 0.9:
            y += amp * np.sin(2 * np.pi * f * ratio * t) * t60env(t, dur * 0.8 * dec)
    return y * np.minimum(1, t / 0.0008)


# ------------------------------------------------------------------------------------------------ reverb y ecos
def make_ir(t60=1.8, predelay=0.012, hf=0.35, lf=1.15, width=1.0, seed=7, early=0.3, length=None):
    """Respuesta al impulso sintética estéreo: ruido por bandas con T60 por banda (graves largos, agudos cortos)
    y reflexiones tempranas. Energía normalizada (1 por canal)."""
    r = rng(seed)
    L = int(((length or t60 * 1.1) + predelay) * SR)
    t = np.arange(L) / SR
    nz = r.normal(0, 1, (L, 2))
    F = rfft(nz, axis=0)
    fr = rfftfreq(L, 1 / SR)
    lf2 = np.log2(np.maximum(fr, 1.0))
    centers = np.log2(np.array([63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]))
    t60s = np.interp(centers, np.log2([125, 1000, 8000]), [t60 * lf, t60, t60 * hf])
    ir = np.zeros((L, 2))
    tt = np.maximum(0, t - predelay)
    onset = np.clip((t - predelay) / 0.008, 0, 1)
    for i, c in enumerate(centers):
        # máscara coseno en octavas: las bandas suman 1
        dist = np.abs(lf2 - c)
        m = np.where(dist < 1, np.cos(np.pi / 2 * dist) ** 2, 0.0)
        if i == 0:
            m[lf2 < c] = 1.0
        if i == len(centers) - 1:
            m[lf2 > c] = 1.0
        band = irfft(F * m[:, None], L, axis=0)
        ir += band * (np.exp(-6.907755 * tt / t60s[i]) * onset)[:, None]
    # reflexiones tempranas
    if early > 0:
        for k in range(7):
            dt = predelay + r.uniform(0.004, 0.04)
            i = int(dt * SR)
            g = early * r.uniform(0.4, 1.0) * (1 - k / 9)
            ir[i, 0] += g * r.choice([-1, 1]) * 3
            ir[i + r.integers(1, 40), 1] += g * r.choice([-1, 1]) * 3
    m_, s_ = (ir[:, 0] + ir[:, 1]) / 2, (ir[:, 0] - ir[:, 1]) / 2 * width
    ir = np.stack([m_ + s_, m_ - s_], 1)
    ir /= np.sqrt(np.mean(np.sum(ir ** 2, axis=0)))
    return ir


def make_spring_ir(length=2.4, period=0.031, t60=2.0, seed=9):
    """Muelle de amplificador: cada ida y vuelta es un pulso disperso (un 'chirp' que baja), cada vez más largo."""
    r = rng(seed)
    L = int(length * SR)
    ir = np.zeros((L, 2))
    for ch, per in enumerate((period, period * 1.13)):
        k = 0
        while True:
            t0 = 0.004 + k * per
            if t0 > length - 0.1:
                break
            g = 10 ** (-3 * t0 / t60)
            dl = 0.012 + 0.006 * k ** 0.8          # la dispersión crece en cada vuelta
            n = int(dl * SR)
            tt = np.arange(n) / SR
            f0, f1 = 4200 / (1 + 0.25 * k), 420.0
            fr = f0 * (f1 / f0) ** (tt / dl)
            ph = 2 * np.pi * np.cumsum(fr) / SR
            chirp = np.sin(ph) * np.sin(np.pi * tt / dl) ** 2 * (-1) ** k
            i = int(t0 * SR)
            ir[i:i + n, ch] += chirp[:max(0, min(n, L - i))] * g
            k += 1
        diffuse = lp(r.normal(0, 1, L), 3500) * t60env(np.arange(L) / SR, t60 * 0.9) * 0.25
        ir[:, ch] += diffuse
    ir = hp(ir, 260, 2)
    ir /= np.sqrt(np.mean(np.sum(ir ** 2, axis=0)))
    return ir


def convolve(x, ir, circular=False, tail=True):
    """Convolución por FFT (mono o estéreo de entrada; la IR estéreo da la salida estéreo).
    circular=True: convolución circular del largo de x (el loop recibe su propia cola)."""
    x = np.asarray(x, float)
    xm = x if x.ndim == 1 else (x[:, 0] + x[:, 1]) * 0.5
    if circular:
        N = len(xm)
        X = rfft(xm, N)
        out = np.stack([irfft(X * rfft(ir[:min(len(ir), N), c], N), N) for c in range(2)], 1)
        return out
    N = len(xm) + (len(ir) - 1 if tail else 0)
    M = next_fast_len(len(xm) + len(ir) - 1)
    X = rfft(xm, M)
    out = np.stack([irfft(X * rfft(ir[:, c], M), M)[:N] for c in range(2)], 1)
    return out


def reverb(x, ir, wet=0.25, dry=1.0, circular=False, pre_hp=0.0):
    """Mezcla seco + húmedo. Sin circular la salida incluye la cola (más larga que x)."""
    x = np.asarray(x, float)
    xs = pan2(x) if x.ndim == 1 else x
    src = hp(xs, pre_hp, circular=circular) if pre_hp else xs
    w = convolve(src, ir, circular=circular)
    if not circular:
        d = np.zeros_like(w)
        d[:len(xs)] = xs
        return d * dry + w * wet
    return xs * dry + w * wet


def echo(x, time_s, fb=0.35, repeats=5, lp_hz=3200.0, pingpong=True, circular=False, dry=True):
    """Eco de cinta: repeticiones cada vez más oscuras, alternando lados (dry=False: solo las repeticiones)."""
    x = np.asarray(x, float)
    xs = pan2(x) if x.ndim == 1 else x
    D = int(time_s * SR)
    n = len(xs) if circular else len(xs) + D * repeats
    out = np.zeros((n, 2))
    if dry:
        out[:len(xs)] += xs
    s = xs
    for k in range(1, repeats + 1):
        s = lp(s, lp_hz, 1, circular=circular)
        g = fb ** k
        sk = s[:, ::-1] if (pingpong and k % 2 == 1) else s
        if circular:
            out += np.roll(sk, k * D, axis=0) * g
        else:
            out[k * D:k * D + len(sk)] += sk * g
    return out


def tremolo(x, rate, depth, circular_len=None, ph0=0.0):
    """Trémolo de amplificador. Con circular_len (s) la frecuencia se ajusta para cerrar el ciclo en el loop."""
    x = np.asarray(x, float)
    n = len(x)
    if circular_len:
        rate = max(1, round(rate * circular_len)) / circular_len
    t = np.arange(n) / SR
    m = 1 - depth * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t + ph0))
    return x * (m[:, None] if x.ndim == 2 else m)


def loop_lfo(n, rate, dur, ph0=0.0):
    """Seno lento que cierra exactamente en un loop de 'dur' segundos."""
    k = max(1, round(rate * dur))
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * k / dur * t + ph0)


# ------------------------------------------------------------------------------------------------ medición y master
def _kw(x):
    """Filtro K de BS.1770 (estante agudo + pasa-altos RLB) para cualquier frecuencia de muestreo."""
    fs = SR
    G, f0, Q = 3.999843853973347, 1681.974450955533, 0.7071752369554196
    K = math.tan(math.pi * f0 / fs)
    Vh = 10 ** (G / 20)
    Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / fs)
    a2 = [1, 2 * (K * K - 1) / (1 + K / Q + K * K), (1 - K / Q + K * K) / (1 + K / Q + K * K)]
    b2 = [1, -2, 1]
    return lfilter(b2, a2, lfilter(b1, a1, x, axis=0), axis=0)


def lufs(x):
    """Sonoridad integrada BS.1770 (con compuertas absoluta y relativa)."""
    x = np.asarray(x, float)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    y = _kw(x)
    blk, hop = int(0.4 * SR), int(0.1 * SR)
    if len(y) < blk:
        ms = np.mean(np.sum(y ** 2, axis=1))
        return -0.691 + 10 * np.log10(ms + 1e-12)
    cs = np.concatenate([[0.0], np.cumsum(np.sum(y ** 2, axis=1))])
    starts = np.arange(0, len(y) - blk + 1, hop)
    z = (cs[starts + blk] - cs[starts]) / blk
    l = -0.691 + 10 * np.log10(z + 1e-12)
    z = z[l > -70]
    if len(z) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(z)) - 10
    z2 = z[(-0.691 + 10 * np.log10(z)) > rel]
    return -0.691 + 10 * np.log10(np.mean(z2) + 1e-12)


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(np.asarray(x) ** 2)) + 1e-12)


def peak_db(x):
    return 20 * np.log10(np.abs(x).max() + 1e-12)


def limiter(x, ceiling_db=-1.0, win_ms=12.0, circular=False):
    """Limitador de pico con anticipación (mínimo + promedio del mismo ancho: nunca deja pasar un pico)."""
    x = np.asarray(x, float)
    c = 10 ** (ceiling_db / 20)
    pk = np.abs(x).max(axis=1) if x.ndim == 2 else np.abs(x)
    need = np.minimum(1.0, c / np.maximum(pk, 1e-12))
    if need.min() >= 1.0:
        return x
    w = max(3, int(win_ms * SR / 1000) | 1)
    mode = 'wrap' if circular else 'nearest'
    g = minimum_filter1d(need, w, mode=mode)
    g = uniform_filter1d(g, w, mode=mode)
    g = np.minimum(g, need)
    return x * (g[:, None] if x.ndim == 2 else g)


def master(x, lufs_target=None, rms_target=None, peak_target=None, ceiling_db=-1.0, circular=False, hp_hz=28.0):
    """Quita sub-graves, lleva al nivel pedido (sonoridad, RMS o pico) y limita los picos al techo."""
    x = np.asarray(x, float)
    if x.ndim == 1:
        x = pan2(x)
    if hp_hz:
        x = hp(x, hp_hz, 2, circular=circular)
    if lufs_target is not None:
        x = x * 10 ** ((lufs_target - lufs(x)) / 20)
    elif rms_target is not None:
        x = x * 10 ** ((rms_target - rms_db(x)) / 20)
    elif peak_target is not None:
        x = x * 10 ** ((peak_target - peak_db(x)) / 20)
    x = limiter(x, ceiling_db, circular=circular)
    return x


# ------------------------------------------------------------------------------------------------ etapas de mezcla
def active_rms_db(x, win=0.5, floor_db=25.0):
    """RMS (dBFS) solo de los trozos donde el bus suena (ventanas a menos de floor_db del máximo)."""
    x = np.asarray(x)
    w = int(win * SR)
    k = len(x) // w
    if k == 0:
        return -120.0
    e = np.mean(x[:k * w].reshape(k, w, -1) ** 2, axis=(1, 2))
    if e.max() <= 0:
        return -120.0
    on = e > e.max() * 10 ** (-floor_db / 10)
    return 10 * np.log10(np.mean(e[on]) + 1e-20)


def stage(buses, targets, ref_db=-24.0):
    """Lleva cada bus a su nivel activo pedido (dB relativos a la guitarra/base = ref_db). Devuelve copias."""
    out = {}
    for k, x in buses.items():
        a = active_rms_db(x)
        g = 10 ** ((ref_db + targets[k] - a) / 20)
        out[k] = x * g
        print(f'    {k:7s} active {a:6.1f} dB -> {ref_db + targets[k]:6.1f}  (x{g:.3f})')
    return out



# ------------------------------------------------------------------------------------------------ salida
def write_ogg(name, x, q=5, out_dir=None):
    """Escribe OGG Vorbis estéreo 44.1 kHz con ffmpeg (entrada float32, sin cuantizar antes)."""
    out_dir = out_dir or OUT
    os.makedirs(out_dir, exist_ok=True)
    top = os.path.join(HERE, 'salida')
    if os.path.abspath(out_dir).startswith(top):
        # dentro de game/tools/arte: que el editor de Godot no importe los .ogg intermedios
        open(os.path.join(top, '.gdignore'), 'a').close()
    x = np.asarray(x, np.float64)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    if not np.all(np.isfinite(x)):
        raise ValueError(f'{name}: NaN/Inf en la señal')
    x = np.clip(x, -1.0, 1.0).astype('<f4')
    path = os.path.join(out_dir, f'{name}.ogg')
    # bitexact: número de serie Ogg y etiquetas fijos -> el mismo archivo byte a byte en cada ejecución
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', 'pipe:0',
                    '-c:a', 'libvorbis', '-q:a', str(q), '-fflags', '+bitexact', '-flags:a', '+bitexact', path],
                   input=x.tobytes(), check=True)
    return path


def report(name, x):
    return f'{name:16s} {len(x) / SR:6.2f} s  RMS {rms_db(x):6.1f}  peak {peak_db(x):6.1f}  LUFS {lufs(x):6.1f}'
