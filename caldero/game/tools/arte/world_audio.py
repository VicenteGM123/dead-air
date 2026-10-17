"""Sonidos del mercado (lane WORLD): ambiente de calle (gente, pájaros, la fuente) y una música alegre de laúd.
Usa las funciones de audio.py. Salida: ./salida/audio/market_loop.ogg y music_mercado.ogg
Uso:  python3 world_audio.py [carpeta_assets/audio]
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from scipy.signal import lfilter, butter
from audio import SR, OUT, write, note_hz, env_adsr, pluck_fast, flute, bell, reverb, place

rng = np.random.default_rng(23)


def _loop_crossfade(buf, fade_s=1.5):
    """Devuelve buf[fade:] con el final mezclado en el principio: sin salto al repetirse."""
    f = int(fade_s * SR)
    out = buf[f:].copy()
    ramp = np.linspace(0, 1, f)[:, None] if buf.ndim == 2 else np.linspace(0, 1, f)
    out[-f:] = out[-f:] * (1 - ramp) + buf[:f] * ramp
    return out


def market_loop():
    dur = 16.0
    n = int((dur + 1.5) * SR)
    buf = np.zeros((n, 2))
    t = np.arange(n) / SR
    # murmullo: muchas "voces" de ruido filtrado con sílabas
    for v in range(22):
        f0 = rng.uniform(380, 1300)
        b, a = butter(2, [f0 / (SR / 2), min(0.99, f0 * 2.2 / (SR / 2))], 'band')
        nz = lfilter(b, a, rng.normal(0, 1, n))
        rate = rng.uniform(3.5, 6.0)
        syl = (np.sin(2 * np.pi * rate * t + rng.uniform(0, 6)) * 0.5 + 0.5) ** 2
        # frases: habla un rato y calla
        phr = np.zeros(n)
        tt = rng.uniform(0, 2)
        while tt < dur + 1.5:
            L = rng.uniform(1.0, 3.2)
            i0, i1 = int(tt * SR), min(n, int((tt + L) * SR))
            seg = np.ones(i1 - i0)
            k = min(len(seg) // 4, int(0.15 * SR))
            if k > 0:
                seg[:k] = np.linspace(0, 1, k)
                seg[-k:] = np.linspace(1, 0, k)
            phr[i0:i1] = seg
            tt += L + rng.uniform(0.6, 3.0)
        voice = nz * syl * phr * rng.uniform(0.25, 0.6)
        pan = rng.uniform(-0.8, 0.8)
        buf[:, 0] += voice * math.cos((pan + 1) * math.pi / 4)
        buf[:, 1] += voice * math.sin((pan + 1) * math.pi / 4)
    # fondo grave de la plaza
    b, a = butter(2, 260 / (SR / 2))
    rumble = lfilter(b, a, rng.normal(0, 1, n)) * 0.5
    buf += rumble[:, None] * 0.4
    # la fuente: agua constante, suave
    b, a = butter(2, [1800 / (SR / 2), 7000 / (SR / 2)], 'band')
    water = lfilter(b, a, rng.normal(0, 1, n))
    water *= 0.55 + 0.25 * np.sin(2 * np.pi * 0.31 * t) + 0.15 * np.sin(2 * np.pi * 1.7 * t)
    buf[:, 0] += water * 0.11
    buf[:, 1] += water * 0.14
    # pájaros: trinos cortos
    for _ in range(26):
        t0 = rng.uniform(0, dur)
        f1 = rng.uniform(2600, 4200)
        notes = rng.integers(2, 6)
        pan = rng.uniform(-0.9, 0.9)
        g = rng.uniform(0.06, 0.16)
        for k in range(notes):
            L = rng.uniform(0.05, 0.11)
            tt = np.arange(int(L * SR)) / SR
            sweep = f1 * (1 + rng.uniform(-0.25, 0.35) * tt / L)
            ph = 2 * np.pi * np.cumsum(sweep) / SR
            chirp = np.sin(ph + 0.6 * np.sin(2 * np.pi * 40 * tt)) * np.sin(np.pi * tt / L) ** 2
            place(buf, chirp, t0 + k * (L + rng.uniform(0.02, 0.06)), g, pan)
    # alguna risa y un "¡pan recién horneado!" lejano (solo el tono, sin palabras)
    for _ in range(4):
        t0 = rng.uniform(0.5, dur - 1)
        f0 = rng.uniform(220, 340)
        L = rng.uniform(0.6, 1.0)
        tt = np.arange(int(L * SR)) / SR
        call = np.sin(2 * np.pi * f0 * (1 + 0.15 * np.sin(2 * np.pi * 1.2 * tt)) * tt)
        call += 0.4 * np.sin(4 * np.pi * f0 * tt)
        b, a = butter(2, [500 / (SR / 2), 2500 / (SR / 2)], 'band')
        call = lfilter(b, a, call) * env_adsr(len(tt), 0.08, 0.2, 0.7, 0.3)
        place(buf, call, t0, 0.05, rng.uniform(-0.7, 0.7))
    for c in range(2):
        buf[:, c] = reverb(buf[:, c], mix=0.18, room=0.7)
    loop = _loop_crossfade(buf, 1.5)
    write('market_loop', loop, q=3, norm=0.7)


def music_mercado():
    """Laúd y flauta en Sol mayor, 104 bpm: alegre pero tranquila, para comprar sin prisa."""
    bpm = 104
    beat = 60 / bpm
    bar = beat * 4
    chords = {
        'G': ['G2', 'B2', 'D3', 'G3'], 'D': ['D2', 'F#2', 'A2', 'D3'], 'Em': ['E2', 'G2', 'B2', 'E3'],
        'C': ['C3', 'E3', 'G3', 'C4'], 'Am': ['A2', 'C3', 'E3', 'A3'], 'Bm': ['B2', 'D3', 'F#3', 'B3'],
    }
    prog = ['G', 'D', 'Em', 'C', 'G', 'Am', 'D', 'G', 'C', 'G', 'Am', 'D', 'Em', 'C', 'D', 'G']
    melody = {
        0: [('B4', 0, 1), ('D5', 1, 1), ('G5', 2, 1.5), ('F#5', 3.5, .5)],
        1: [('E5', 0, 1), ('D5', 1, 1), ('A4', 2, 2)],
        2: [('B4', 0, .5), ('C5', .5, .5), ('D5', 1, 1), ('E5', 2, 1), ('G5', 3, 1)],
        3: [('E5', 0, 1.5), ('D5', 1.5, .5), ('C5', 2, 2)],
        4: [('D5', 0, 1), ('B4', 1, 1), ('G4', 2, 1), ('B4', 3, 1)],
        5: [('C5', 0, 1), ('E5', 1, 1), ('A5', 2, 1.5), ('G5', 3.5, .5)],
        6: [('F#5', 0, 1), ('E5', 1, .5), ('D5', 1.5, .5), ('A4', 2, 2)],
        7: [('G4', 0, 3)],
        8: [('E5', 0, 1), ('G5', 1, 1), ('C6', 2, 1.5), ('B5', 3.5, .5)],
        9: [('A5', 0, 1), ('G5', 1, 1), ('D5', 2, 2)],
        10: [('C5', 0, .5), ('D5', .5, .5), ('E5', 1, 1), ('A5', 2, 1), ('G5', 3, 1)],
        11: [('F#5', 0, 2), ('D5', 2, 2)],
        12: [('G5', 0, 1), ('E5', 1, 1), ('B4', 2, 2)],
        13: [('C5', 0, 1), ('E5', 1, 1), ('G5', 2, 2)],
        14: [('F#5', 0, 1), ('A5', 1, 1), ('D6', 2, 1), ('C6', 3, 1)],
        15: [('B5', 0, 2), ('G5', 2, 1.5)],
    }
    length = bar * len(prog)
    total = length * 2 + 3
    buf = np.zeros((int(total * SR), 2))
    for rep in range(2):
        base = rep * length
        for bi, ch in enumerate(prog):
            t0 = base + bi * bar
            tones = chords[ch]
            # bajo de laúd en 1 y 3
            for k, b in enumerate((0, 2)):
                place(buf, pluck_fast(note_hz(tones[0 if k == 0 else 2]), 1.6), t0 + b * beat, 0.22, -0.15)
            # rasgueo en corcheas con acento
            pat = [1, 2, 3, 2, 1, 2, 3, 2]
            for k, idx in enumerate(pat):
                nn = tones[idx]
                nn = nn[:-1] + str(int(nn[-1]) + 1)
                g = 0.16 if k % 2 == 0 else 0.1
                place(buf, pluck_fast(note_hz(nn), 1.2), t0 + k * beat / 2 + rng.uniform(0, 0.01), g, 0.3 if k % 2 else -0.3)
            # pandereta suave en 2 y 4
            for b in (1, 3):
                L = int(0.12 * SR)
                bb, aa = butter(2, 6000 / (SR / 2), 'high')
                hit = lfilter(bb, aa, rng.normal(0, 1, L)) * np.exp(-np.linspace(0, 9, L))
                place(buf, hit, t0 + b * beat, 0.05, 0.4)
            # melodía (flauta la primera vuelta, campanitas la segunda)
            for (nn, b, d) in melody.get(bi, []):
                if rep == 0:
                    place(buf, flute(note_hz(nn), d * beat + 0.1), t0 + b * beat, 0.14, 0.1)
                else:
                    place(buf, pluck_fast(note_hz(nn), d * beat + 0.6), t0 + b * beat, 0.2, 0.1)
                    place(buf, bell(note_hz(nn) * 2, 1.2, bright=0.6), t0 + b * beat, 0.04, -0.2)
    for c in range(2):
        buf[:, c] = reverb(buf[:, c], mix=0.22, room=0.78)
    a, b = int(length * SR), int(length * 2 * SR)
    write('music_mercado', buf[a:b], q=5, norm=0.74)


if __name__ == '__main__':
    market_loop(); print('market_loop ok')
    music_mercado(); print('music_mercado ok')
    if len(sys.argv) > 1:
        import shutil
        for f in ('market_loop.ogg', 'music_mercado.ogg'):
            shutil.copy(f'{OUT}/{f}', sys.argv[1])
        print('copiado a', sys.argv[1])
