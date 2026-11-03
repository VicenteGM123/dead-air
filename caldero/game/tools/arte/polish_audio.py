"""Ronda de pulido: la fanfarria de los momentos grandes (medalla de un evento, subida de renombre, el puesto 1).
Usa las mismas piezas que la música de la tienda (audio.py: pluck_fast, bell, flute, pad, reverb, write), en Re mayor
como music_tienda. Sale a ./salida/audio/fanfare.ogg (se copia a mano a assets/audio/).
Uso (desde una carpeta de trabajo): python3 <ruta>/polish_audio.py"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from audio import SR, note_hz, pluck_fast, bell, flute, pad, reverb, place, write, env_adsr

BPM = 116
BEAT = 60 / BPM


def fanfare():
    total = 6.6
    buf = np.zeros((int(total * SR), 2))
    b = BEAT
    # 1) el arranque: un arpegio de arpa que sube (Re mayor) y un destello de campanitas
    for k, nn in enumerate(['D4', 'F#4', 'A4', 'D5', 'F#5', 'A5']):
        place(buf, pluck_fast(note_hz(nn), 1.8), k * b / 4, 0.20 - k * 0.012, -0.35 + k * 0.14)
    for k, nn in enumerate(['A6', 'D7', 'F#7']):
        place(buf, bell(note_hz(nn), 1.6, bright=0.6), 0.05 + k * b / 4, 0.05, 0.4)
    # 2) el tema: La-Re-Fa# ... Mi-Fa#-La (flauta, con la campana una octava arriba en las notas largas)
    t0 = 1.5 * b
    theme = [('A4', 0.0, 0.5), ('D5', 0.5, 0.5), ('F#5', 1.0, 1.0), ('E5', 2.0, 0.5), ('F#5', 2.5, 0.5), ('A5', 3.0, 2.6)]
    for nn, at, dur in theme:
        place(buf, flute(note_hz(nn), dur * b + 0.12), t0 + at * b, 0.20, 0.1)
        place(buf, pluck_fast(note_hz(nn), 1.4), t0 + at * b, 0.12, -0.15)
        if dur >= 1.0:
            hi = nn[:-1] + str(int(nn[-1]) + 1)
            place(buf, bell(note_hz(hi), 2.6, bright=0.8), t0 + at * b, 0.07, 0.3)
    # 3) los acordes de abajo: Re · Sol · La · Re (pad suave y bajo)
    chords = [(0.0, ['D3', 'F#3', 'A3'], 'D2'), (1.0, ['G3', 'B3', 'D4'], 'G2'), (2.0, ['A3', 'C#4', 'E4'], 'A2'),
              (3.0, ['D3', 'F#3', 'A3', 'D4'], 'D2')]
    for at, tones, bass in chords:
        dur = (1.0 if at < 3.0 else 4.0) * b + 0.9
        place(buf, pad([note_hz(n) for n in tones], dur), t0 + at * b, 0.012, 0.0)
        n = int(dur * SR)
        tt = np.arange(n) / SR
        bf = note_hz(bass)
        bs = np.sin(2 * np.pi * bf * tt) * env_adsr(n, 0.02, 0.4, 0.6, 0.5) + 0.2 * np.sin(4 * np.pi * bf * tt) * np.exp(-3 * tt)
        place(buf, bs, t0 + at * b, 0.14, -0.1)
    # 4) el final: el acorde de Re en arpa y una lluvia de campanitas que baja
    tf = t0 + 3.0 * b
    for k, nn in enumerate(['D4', 'A4', 'D5', 'F#5', 'A5', 'D6']):
        place(buf, pluck_fast(note_hz(nn), 2.6), tf + k * 0.035, 0.11, -0.3 + k * 0.12)
    for k, nn in enumerate(['D7', 'A6', 'F#6', 'D6', 'A5']):
        place(buf, bell(note_hz(nn), 2.0, bright=0.5), tf + 0.35 + k * 0.11, 0.045, 0.35 - k * 0.15)
    for c in range(2):
        buf[:, c] = reverb(buf[:, c], mix=0.28, room=0.84)
    # cola: que se apague sin corte
    fade = int(0.6 * SR)
    buf[-fade:] *= np.linspace(1, 0, fade)[:, None]
    write('fanfare', buf, q=4, norm=0.66)   # pico ~ -3.6 dBFS


if __name__ == '__main__':
    fanfare()
    print('fanfare ok')
