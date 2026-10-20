"""R4 PACE: sonidos del reloj y de la fila. Usa las funciones de audio.py. Salida: ./salida/audio/pace_*.ogg
  pace_bell   la campana de cerrar (las 18:00): tres toques de campanilla de mano
  pace_chime  la última hora (las 17:00): una campanada suave del reloj de pared
  pace_sigh   un suspiro (la fila está llena, o se van a casa al cerrar)
  pace_huff   un «¡hmpf!» de quien se cansó de esperar
  pace_stamp  el sello sobre el libro de cuentas
  pace_tick   el tic del reloj en la última media hora
Uso:  python3 pace_audio.py [carpeta_assets/audio]   (sin argumento deja los .ogg en ./salida/audio)
"""
import os, sys, shutil
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from scipy.signal import lfilter, butter
from audio import SR, OUT, write, note_hz, bell, reverb

rng = np.random.default_rng(404)


def t(d):
    return np.arange(int(d * SR)) / SR


def bpf(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], 'band')
    return lfilter(b, a, x)


def lpf(x, hi, order=2):
    b, a = butter(order, hi / (SR / 2))
    return lfilter(b, a, x)


def pace_bell():
    """Campanilla de mano, tres toques (cerramos)."""
    buf = np.zeros(int(2.8 * SR))
    for k, dt in enumerate((0.0, 0.32, 0.64)):
        tt = t(1.9)
        f = 1046.5 * (1.0 if k != 1 else 0.997)
        sig = np.zeros(len(tt))
        for ratio, amp, dec in [(1, 1.0, 2.6), (2.0, 0.42, 3.8), (2.76, 0.3, 5.0), (4.07, 0.18, 7.0), (5.4, 0.1, 9.0)]:
            sig += amp * np.sin(2 * np.pi * f * ratio * tt) * np.exp(-dec * tt)
        clang = bpf(rng.normal(0, 1, len(tt)), 2500, 7000) * np.exp(-tt * 60) * 0.15
        i = int(dt * SR)
        buf[i:i + len(sig)] += (sig + clang)[:len(buf) - i] * (1.0 - 0.12 * k)
    write('pace_bell', reverb(buf, mix=0.28))


def pace_chime():
    """Una campanada grave y suave del reloj de pared (la última hora)."""
    buf = np.zeros(int(2.6 * SR))
    low = bell(note_hz('G4'), 2.4) * 0.8
    high = bell(note_hz('G5'), 1.6) * 0.18
    buf[:len(low)] += low
    buf[:len(high)] += high
    write('pace_chime', reverb(buf, mix=0.32))


def pace_sigh():
    """Un suspiro: aire que sale por la boca, con dos formantes que bajan."""
    dur = 1.05
    tt = t(dur)
    nz = rng.normal(0, 1, len(tt))
    f1 = 900 - 380 * (tt / dur)
    f2 = 2300 - 700 * (tt / dur)
    out = np.zeros(len(tt))
    # formantes que se mueven: bloques cortos con su propio filtro
    blk = 1024
    for i in range(0, len(tt), blk):
        seg = nz[i:i + blk]
        c1 = f1[min(i, len(f1) - 1)]
        c2 = f2[min(i, len(f2) - 1)]
        out[i:i + blk] = bpf(seg, c1 * 0.75, c1 * 1.3) * 1.0 + bpf(seg, c2 * 0.85, c2 * 1.15) * 0.45
    out = lpf(out, 3000)
    env = np.minimum(1.0, tt / 0.12) * np.exp(-np.maximum(0, tt - 0.12) * 3.2)
    # un poquito de voz al principio ("ahh")
    voice = np.sin(2 * np.pi * np.cumsum(170 - 40 * tt / dur) / SR) * np.exp(-tt * 9) * 0.12
    write('pace_sigh', np.concatenate([(out * 0.9 + voice) * env, np.zeros(2000)]))


def pace_huff():
    """«¡Hmpf!»: un zumbido nasal corto con la boca cerrada y un soplido por la nariz."""
    dur = 0.42
    tt = t(dur)
    f0 = 165 - 55 * (tt / dur)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    buzz = np.zeros(len(tt))
    for k in range(1, 9):
        buzz += np.sin(k * ph) / k
    buzz = lpf(buzz, 900) + 0.35 * bpf(buzz, 2200, 2900)
    env = np.minimum(1.0, tt / 0.015) * np.exp(-tt * 7.5)
    puff = bpf(rng.normal(0, 1, len(tt)), 600, 3500) * np.exp(-tt * 14) * 0.5
    write('pace_huff', np.concatenate([buzz * env * 0.8 + puff, np.zeros(3000)]))


def pace_stamp():
    """El sello de goma sobre el papel: un golpe sordo y el papel."""
    tt = t(0.4)
    thud = np.sin(2 * np.pi * np.cumsum(95 * np.exp(-tt * 6) + 55) / SR) * np.exp(-tt * 16)
    paper = lpf(rng.normal(0, 1, len(tt)), 2500) * np.exp(-tt * 40) * 0.7
    knock = bpf(rng.normal(0, 1, len(tt)), 300, 1200) * np.exp(-tt * 55) * 0.6
    write('pace_stamp', np.concatenate([thud + paper + knock, np.zeros(2000)]))


def pace_tick():
    """Tic del reloj de pared (madera y metal, muy corto)."""
    tt = t(0.06)
    s = np.sin(2 * np.pi * 2600 * tt) * np.exp(-tt * 180) * 0.6 + np.sin(2 * np.pi * 900 * tt) * np.exp(-tt * 120)
    s += bpf(rng.normal(0, 1, len(tt)), 1500, 6000) * np.exp(-tt * 250) * 0.3
    write('pace_tick', np.concatenate([s, np.zeros(1200)]))


if __name__ == '__main__':
    pace_bell()
    pace_chime()
    pace_sigh()
    pace_huff()
    pace_stamp()
    pace_tick()
    if len(sys.argv) > 1:
        for n in ('pace_bell', 'pace_chime', 'pace_sigh', 'pace_huff', 'pace_stamp', 'pace_tick'):
            shutil.copy(f'{OUT}/{n}.ogg', os.path.join(sys.argv[1], f'{n}.ogg'))
    print('ok')
