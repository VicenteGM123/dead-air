"""Mide los .ogg: duración, RMS y pico (dBFS), RMS por ventanas (estabilidad), y en los loops el salto de la costura
(el último bloque contra el primero). Decodifica con ffmpeg a float32.
Uso:  python3 levels.py archivo.ogg [...]      (o una carpeta: mide todos los .ogg)
"""
import os, sys, subprocess
import numpy as np

SR = 44100


def decode(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)


def db(x):
    return 20 * np.log10(max(x, 1e-12))


def seam(x, n=2048):
    """Cuánto 'salta' la señal al volver del final al principio, comparado con un salto normal dentro del archivo."""
    joint = np.concatenate([x[-n:], x[:n]])
    d = np.abs(np.diff(joint, axis=0)).max(axis=1)
    jump = d[n - 1]                                   # el paso exacto final -> inicio
    typical = np.percentile(np.abs(np.diff(x, axis=0)).max(axis=1), 99.9)
    # RMS a cada lado de la costura (200 ms): un loop bueno no cambia de nivel al dar la vuelta
    w = int(0.2 * SR)
    a = np.sqrt(np.mean(x[-w:] ** 2)) + 1e-12
    b = np.sqrt(np.mean(x[:w] ** 2)) + 1e-12
    return jump, typical, db(b) - db(a)


def measure(path, loop=None):
    x = decode(path)
    dur = len(x) / SR
    rms = np.sqrt(np.mean(x ** 2))
    peak = np.abs(x).max()
    # RMS en ventanas de 1 s (solo la parte con sonido) -> rango
    w = SR
    wins = [np.sqrt(np.mean(x[i:i + w] ** 2)) for i in range(0, max(1, len(x) - w + 1), w)]
    wins = [db(v) for v in wins if v > 1e-6]
    line = f'{os.path.basename(path):24s} {dur:7.2f} s  RMS {db(rms):6.1f}  peak {db(peak):6.1f} dBFS'
    if wins:
        line += f'  1s-RMS {min(wins):6.1f}..{max(wins):6.1f}'
    if loop is None:
        loop = dur > 6
    if loop:
        jump, typ, dlev = seam(x)
        line += f'  seam jump {jump:.4f} (p99.9 step {typ:.4f})  level change {dlev:+.1f} dB'
    return line


if __name__ == '__main__':
    paths = []
    for a in sys.argv[1:]:
        if os.path.isdir(a):
            paths += sorted(os.path.join(a, f) for f in os.listdir(a) if f.endswith('.ogg'))
        else:
            paths.append(a)
    for p in paths:
        print(measure(p))
