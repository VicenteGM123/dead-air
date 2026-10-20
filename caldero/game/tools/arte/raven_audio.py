"""Sonidos de Krápido (ronda 4, lane RAVEN): el graznido de Graznido, la campanita de la bola de cristal cuando llega
un pedido y el aleteo. Usa las funciones de audio.py. Salida: ./salida/audio/{kraa,ball_chime,wings}.ogg
Uso:  python3 raven_audio.py [carpeta_assets/audio]
"""
import os, sys, shutil
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from scipy.signal import lfilter, butter
from audio import SR, OUT, write, note_hz, bell, reverb

rng = np.random.default_rng(47)


def t(d):
    return np.arange(int(d * SR)) / SR


def _bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], 'band')
    return lfilter(b, a, x)


def caw(dur=0.36, f0=410.0, f1=300.0):
    """Un graznido: tren de pulsos ásperos que baja de tono, con formantes de 'a' (kraa) y un poco de ruido."""
    tt = t(dur)
    f = f0 + (f1 - f0) * (tt / dur) ** 0.7
    f *= 1.0 + 0.06 * np.sin(2 * np.pi * 34 * tt)                 # aspereza (vibrato rápido)
    ph = np.cumsum(f) / SR
    saw = 2.0 * (ph % 1.0) - 1.0
    pulse = np.sign(np.sin(2 * np.pi * ph)) * 0.6 + saw * 0.7      # rico en armónicos
    pulse *= 1.0 + 0.5 * np.sin(2 * np.pi * 68 * tt)              # 'rr' (modulación de amplitud)
    voice = _bp(pulse, 700, 1100) * 1.0 + _bp(pulse, 1300, 1900) * 0.8 + _bp(pulse, 2400, 3200) * 0.35
    nz = _bp(rng.normal(0, 1, len(tt)), 1200, 4200) * 0.25
    env = np.minimum(1.0, tt / 0.018) * np.exp(-((tt - 0.06) / (dur * 0.7)) ** 2 * 1.4)
    env *= np.where(tt > dur - 0.05, (dur - tt) / 0.05, 1.0).clip(0, 1)
    k_burst = np.exp(-tt / 0.012) * _bp(rng.normal(0, 1, len(tt)), 1800, 5000) * 0.8   # la 'k' del principio
    return (voice + nz) * env + k_burst


def kraa():
    """¡Kraa!: un graznido fuerte y otro más corto (el juego cambia un poco el tono cada vez)."""
    a = caw(0.34, 420, 310)
    b = caw(0.24, 380, 290)
    gap = np.zeros(int(0.07 * SR))
    buf = np.concatenate([a, gap, b * 0.8])
    write('kraa', reverb(buf, mix=0.18, room=0.6), norm=0.8)


def ball_chime():
    """La bola de cristal recibe un pedido: campanitas suaves y un brillo que sube."""
    dur = 1.8
    buf = np.zeros(int(dur * SR))
    for k, (nn, g) in enumerate([('E6', 0.55), ('B6', 0.4), ('E7', 0.25), ('G#7', 0.15)]):
        s = bell(note_hz(nn), 1.4, bright=0.5) * g
        i = int(k * 0.07 * SR)
        buf[i:i + len(s)] += s[:len(buf) - i]
    tt = t(dur)
    shimmer = _bp(rng.normal(0, 1, len(tt)), 5000, 9000) * np.exp(-((tt - 0.25) ** 2) / 0.04) * 0.08
    write('ball_chime', reverb(buf + shimmer, mix=0.45, room=0.85), norm=0.55)


def wings():
    """Aleteo: tres golpes de aire."""
    dur = 0.75
    tt = t(dur)
    nz = rng.normal(0, 1, len(tt))
    low = _bp(nz, 180, 1400)
    env = np.zeros(len(tt))
    for t0 in (0.02, 0.24, 0.46):
        x = (tt - t0) / 0.13
        env += np.where((x > 0) & (x < 1), np.sin(np.pi * x) ** 1.6, 0.0)
    thump = np.sin(2 * np.pi * 70 * tt) * env * 0.3
    write('wings', low * env + thump, norm=0.6)


if __name__ == '__main__':
    kraa()
    ball_chime()
    wings()
    print('raven audio ok')
    if len(sys.argv) > 1:
        for f in ('kraa', 'ball_chime', 'wings'):
            shutil.copy(f'{OUT}/{f}.ogg', sys.argv[1])
        print('copiado a', sys.argv[1])
