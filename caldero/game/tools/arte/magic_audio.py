"""Sonidos del grimorio (lane MAGIC): la nota de cada punto de la runa, la runa completa, la pluma y el libro.
Usa las funciones de audio.py. Salida: ./salida/audio/{rune_node,rune_done,quill,grimoire}.ogg
Uso:  python3 magic_audio.py [carpeta_assets/audio]
"""
import os, sys, shutil
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from scipy.signal import lfilter, butter
from audio import SR, OUT, write, note_hz, bell, reverb

rng = np.random.default_rng(31)


def t(d):
    return np.arange(int(d * SR)) / SR


def rune_node():
    """Campanita de cristal suave (el juego la sube de tono en cada punto)."""
    buf = np.zeros(int(1.1 * SR))
    for nn, g, dt in [('E6', 0.7, 0.0), ('B6', 0.25, 0.0), ('E7', 0.12, 0.012)]:
        s = bell(note_hz(nn), 0.9, bright=0.7) * g
        i = int(dt * SR)
        buf[i:i + len(s)] += s[:len(buf) - i]
    write('rune_node', reverb(buf, mix=0.35, room=0.8), norm=0.6)


def rune_done():
    """La runa se enciende entera: arpegio de campanitas que sube y un soplo brillante."""
    dur = 2.4
    buf = np.zeros(int(dur * SR))
    for k, nn in enumerate(['C6', 'E6', 'G6', 'C7', 'E7', 'G7', 'C8']):
        s = bell(note_hz(nn), 1.5, bright=1.1) * (0.55 - k * 0.04)
        i = int(k * 0.055 * SR)
        buf[i:i + len(s)] += s[:len(buf) - i]
    tt = t(dur)
    nz = rng.normal(0, 1, len(tt))
    b, a = butter(2, [2500 / (SR / 2), 9000 / (SR / 2)], 'band')
    buf += lfilter(b, a, nz) * np.exp(-((tt - 0.35) ** 2) / 0.05) * 0.18
    write('rune_done', reverb(buf, mix=0.4), norm=0.75)


def quill():
    """Pluma que raspa el papel: tres trazos de ruido filtrado."""
    dur = 0.75
    tt = t(dur)
    nz = rng.normal(0, 1, len(tt))
    b, a = butter(2, [1800 / (SR / 2), 7000 / (SR / 2)], 'band')
    nz = lfilter(b, a, nz)
    env = np.zeros(len(tt))
    for t0, L in [(0.02, 0.16), (0.24, 0.2), (0.5, 0.18)]:
        m = (tt >= t0) & (tt < t0 + L)
        x = (tt[m] - t0) / L
        env[m] += np.sin(np.pi * x) ** 1.5 * (0.7 + 0.3 * np.sin(2 * np.pi * 55 * tt[m]))
    write('quill', nz * env, norm=0.5)


def grimoire():
    """Un libro grande que se abre: golpe sordo de tapa y un susurro de páginas."""
    dur = 0.9
    tt = t(dur)
    thump = np.sin(2 * np.pi * np.cumsum(90 * np.exp(-tt * 6) + 55) / SR) * np.exp(-tt * 14)
    nz = rng.normal(0, 1, len(tt))
    b, a = butter(2, [700 / (SR / 2), 5000 / (SR / 2)], 'band')
    pages = lfilter(b, a, nz) * np.exp(-((tt - 0.28) ** 2) / 0.012) * (0.6 + 0.4 * np.sin(2 * np.pi * 30 * tt))
    sparkle = np.zeros(len(tt))
    s = bell(note_hz('A6'), 0.6, bright=0.8) * 0.18
    i = int(0.3 * SR)
    sparkle[i:i + len(s)] += s[:len(sparkle) - i]
    write('grimoire', reverb(thump * 0.9 + pages * 0.5 + sparkle, mix=0.25), norm=0.7)


if __name__ == '__main__':
    rune_node(); rune_done(); quill(); grimoire()
    print('magic audio ok')
    if len(sys.argv) > 1:
        for f in ('rune_node', 'rune_done', 'quill', 'grimoire'):
            shutil.copy(f'{OUT}/{f}.ogg', sys.argv[1])
        print('copiado a', sys.argv[1])
