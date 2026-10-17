"""Procedural music + SFX for Caldero Nocturno. Output: OGG Vorbis via ffmpeg."""
import numpy as np, os, subprocess, math, random
from scipy.signal import lfilter, butter

SR = 44100
OUT = './salida/audio'
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)

def write(name, data, q=5, norm=0.89):
    data = np.asarray(data, np.float32)
    if data.ndim == 1:
        data = np.stack([data, data], 1)
    peak = np.max(np.abs(data)) + 1e-9
    data = data / peak * norm
    raw = (data * 32767).astype('<i2').tobytes()
    tmp = f'{OUT}/{name}.raw'
    open(tmp, 'wb').write(raw)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', tmp,
                    '-c:a', 'libvorbis', '-q:a', str(q), f'{OUT}/{name}.ogg'], check=True)
    os.remove(tmp)

def note_hz(n):
    names = {'C': -9, 'C#': -8, 'Db': -8, 'D': -7, 'D#': -6, 'Eb': -6, 'E': -5, 'F': -4, 'F#': -3, 'Gb': -3, 'G': -2, 'G#': -1, 'Ab': -1, 'A': 0, 'A#': 1, 'Bb': 1, 'B': 2}
    p, o = n[:-1], int(n[-1])
    return 440.0 * 2 ** ((names[p] + (o - 4) * 12) / 12)

def env_adsr(n, a, d, s, r, sr=SR):
    a, d, r = int(a * sr), int(d * sr), int(r * sr)
    e = np.ones(n) * s
    e[:a] = np.linspace(0, 1, a, endpoint=False) if a > 0 else e[:a]
    if d > 0:
        e[a:a + d] = np.linspace(1, s, min(d, max(0, n - a)), endpoint=False)[:len(e[a:a + d])]
    if r > 0 and n > r:
        e[-r:] *= np.linspace(1, 0, r)
    return e

def pluck(f, dur, bright=0.5, sr=SR):
    """Karplus-Strong harp/guitar."""
    n = int(dur * sr)
    p = max(2, int(sr / f))
    buf = rng.uniform(-1, 1, p)
    # soften the excitation
    buf = lfilter([1 - bright], [1, -bright], buf)
    out = np.zeros(n)
    idx = 0
    b = buf.copy()
    decay = 0.996
    for i in range(n):
        v = b[idx]
        nxt = b[(idx + 1) % p]
        b[idx] = decay * 0.5 * (v + nxt)
        out[i] = v
        idx = (idx + 1) % p
    out *= np.exp(-np.linspace(0, dur * 1.6, n))
    return out

def pluck_fast(f, dur, sr=SR):
    """Vectorized plucked tone (additive w/ decaying partials) - much faster than KS."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for k, amp in enumerate([1.0, 0.55, 0.33, 0.2, 0.12, 0.07], start=1):
        dec = 2.2 + k * 1.6
        out += amp * np.sin(2 * np.pi * f * k * t * (1 + 0.0007 * k)) * np.exp(-dec * t)
    att = np.minimum(1, t / 0.004)
    return out * att

def bell(f, dur, sr=SR, bright=1.0):
    n = int(dur * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for ratio, amp, dec in [(1, 1.0, 2.2), (2.0, 0.35, 3.5), (3.0, 0.18, 5.0), (4.16, 0.15 * bright, 7.0), (5.43, 0.08 * bright, 9.0)]:
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-dec * t)
    att = np.minimum(1, t / 0.002)
    return out * att

def flute(f, dur, sr=SR):
    n = int(dur * sr)
    t = np.arange(n) / sr
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.minimum(1, t / 0.4)
    ph = 2 * np.pi * f * np.cumsum(vib) / sr
    s = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
    breath = rng.normal(0, 1, n)
    b, a = butter(2, [min(0.99, f * 1.5 / (sr / 2)), min(0.995, f * 4 / (sr / 2))], 'band')
    s += 0.06 * lfilter(b, a, breath)
    e = env_adsr(n, 0.09, 0.2, 0.8, min(0.25, dur * 0.4))
    return s * e

def pad(freqs, dur, sr=SR):
    n = int(dur * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.12, 0.0, 0.13):
            ff = f * 2 ** (det / 12)
            # band-limited-ish saw via a few harmonics
            for k in range(1, 7):
                out += (1 / k) * np.sin(2 * np.pi * ff * k * t + rng.uniform(0, 6.28)) * (0.6 if det else 1.0)
    b, a = butter(2, 1800 / (sr / 2))
    out = lfilter(b, a, out)
    out *= env_adsr(n, 1.2, 0.5, 0.85, 1.2)
    return out

def reverb(x, sr=SR, mix=0.3, room=0.84):
    combs = [1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116]
    allp = [225, 556, 441, 341]
    out = np.zeros_like(x)
    for d in combs:
        dd = int(d * sr / 44100)
        a = np.zeros(dd + 1); a[0] = 1; a[dd] = -room
        y = lfilter([1], a, x)
        # damping
        y = lfilter([0.6], [1, -0.4], y)
        out += y
    out /= len(combs)
    for d in allp:
        g = 0.5
        b = np.zeros(d + 1); b[0] = -g; b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        out = lfilter(b, a, out)
    return x * (1 - mix) + out * mix

def place(buf, sig, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= len(buf):
        return
    s = sig[:len(buf) - i] * gain
    l = math.cos((pan + 1) * math.pi / 4)
    r = math.sin((pan + 1) * math.pi / 4)
    buf[i:i + len(s), 0] += s * l
    buf[i:i + len(s), 1] += s * r

# ------------------------------------------------------------------ music
CHORDS = {
    'Dmaj7': ['D3', 'F#3', 'A3', 'C#4'], 'Bm7': ['B2', 'D3', 'F#3', 'A3'], 'Gmaj7': ['G2', 'B2', 'D3', 'F#3'],
    'A': ['A2', 'C#3', 'E3', 'A3'], 'Asus4': ['A2', 'D3', 'E3', 'A3'], 'F#m7': ['F#2', 'A2', 'C#3', 'E3'],
    'Em7': ['E2', 'G2', 'B2', 'D3'], 'A7': ['A2', 'C#3', 'E3', 'G3'],
}
PROG = ['Dmaj7', 'Bm7', 'Gmaj7', 'Asus4', 'Dmaj7', 'F#m7', 'Gmaj7', 'A7',
        'Bm7', 'Gmaj7', 'Dmaj7', 'A', 'Gmaj7', 'F#m7', 'Em7', 'Asus4']
BPM = 68
BEAT = 60 / BPM
BAR = BEAT * 4

MELODY = {  # bar: [(note, beat, dur)]
    4: [('A4', 0, 1.5), ('D5', 1.5, .5), ('E5', 2, 1), ('F#5', 3, 1)],
    5: [('E5', 0, 1.5), ('C#5', 1.5, .5), ('A4', 2, 2)],
    6: [('B4', 0, 1), ('D5', 1, 1), ('G5', 2, 1.5), ('F#5', 3.5, .5)],
    7: [('E5', 0, 2), ('C#5', 2, 1), ('E5', 3, 1)],
    12: [('F#5', 0, 1.5), ('E5', 1.5, .5), ('D5', 2, 1), ('B4', 3, 1)],
    13: [('C#5', 0, 1), ('E5', 1, 1), ('A5', 2, 2)],
    14: [('G5', 0, 1), ('F#5', 1, .5), ('E5', 1.5, .5), ('D5', 2, 1), ('B4', 3, 1)],
    15: [('A4', 0, 2.5), ('C#5', 3, 1)],
}
MUSICBOX = {
    0: [('F#6', 0), ('A5', 1), ('C#6', 2), ('D6', 3)],
    1: [('D6', 0), ('B5', 1), ('F#5', 2.5)],
    2: [('B5', 0), ('D6', 1), ('F#6', 2)],
    3: [('E6', 0), ('D6', 1), ('A5', 2.5)],
    8: [('F#6', 0), ('D6', 1), ('B5', 2)],
    9: [('B5', 0), ('G5', 1), ('D6', 2), ('F#6', 3)],
    10: [('A5', 0), ('F#6', 1.5), ('E6', 2.5)],
    11: [('C#6', 0), ('E6', 1), ('A6', 2.5)],
}

def make_music():
    length = BAR * len(PROG)
    total = length * 2 + 4
    buf = np.zeros((int(total * SR), 2))
    for rep in range(2):
        base = rep * length
        for bi, ch in enumerate(PROG):
            t0 = base + bi * BAR
            tones = CHORDS[ch]
            # pad
            p = pad([note_hz(n) * 2 for n in tones[1:]], BAR + 1.4)
            place(buf, p, t0, 0.010, 0.0)
            # bass (soft sine)
            bf = note_hz(tones[0])
            n = int((BAR + 0.5) * SR)
            tt = np.arange(n) / SR
            bass = np.sin(2 * np.pi * bf * tt) * env_adsr(n, 0.05, 0.6, 0.55, 0.8) + 0.2 * np.sin(4 * np.pi * bf * tt) * np.exp(-3 * tt)
            place(buf, bass, t0, 0.11, -0.1)
            # harp arpeggio, 8th notes
            arp = [tones[0], tones[1], tones[2], tones[3], tones[2], tones[1], tones[2], tones[3]]
            arp = [a[:-1] + str(int(a[-1]) + 1) for a in arp]
            for k, nn in enumerate(arp):
                if rep == 0 and bi < 1 and k < 2:
                    pass
                g = 0.20 if k % 2 == 0 else 0.14
                place(buf, pluck_fast(note_hz(nn), 2.2), t0 + k * BEAT / 2 + rng.uniform(0, 0.012), g, 0.25 if k % 2 else -0.25)
            # melody
            for (nn, b, d) in MELODY.get(bi, []):
                place(buf, flute(note_hz(nn), d * BEAT + 0.15), t0 + b * BEAT, 0.16, 0.15)
            for (nn, b) in MUSICBOX.get(bi, []):
                place(buf, bell(note_hz(nn), 2.5), t0 + b * BEAT, 0.10, -0.3 + 0.2 * (b / 3))
    # reverb on both channels
    for c in range(2):
        buf[:, c] = reverb(buf[:, c], mix=0.32, room=0.86)
    # take the second loop so the reverb tail of the end feeds the start
    a, b = int(length * SR), int(length * 2 * SR)
    loop = buf[a:b]
    write('music_tienda', loop, q=5, norm=0.78)

# ------------------------------------------------------------------ sfx
def sfx():
    t = lambda d: np.arange(int(d * SR)) / SR
    # bubble pops (3)
    for i, (f0, f1) in enumerate([(280, 900), (340, 1100), (240, 780)]):
        tt = t(0.09)
        f = f0 + (f1 - f0) * (tt / tt[-1]) ** 0.6
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 38)
        write(f'bubble_{i}', np.concatenate([s, np.zeros(2000)]))
    # plop
    tt = t(0.32)
    f = 520 * np.exp(-tt * 9) + 130
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 10)
    nz = rng.normal(0, 1, len(tt)); b, a = butter(2, 1200 / (SR / 2)); nz = lfilter(b, a, nz) * np.exp(-tt * 25) * 0.6
    write('plop', reverb(s + nz, mix=0.2))
    # brew magic shimmer
    buf = np.zeros(int(2.6 * SR))
    for k, nn in enumerate(['D5', 'F#5', 'A5', 'D6', 'F#6', 'A6', 'D7']):
        sig = bell(note_hz(nn), 1.6)
        i = int(k * 0.07 * SR)
        buf[i:i + len(sig)] += sig[:len(buf) - i] * (0.6 - k * 0.04)
    tt = t(2.6)
    sw = rng.normal(0, 1, len(tt)); b, a = butter(2, [3000 / (SR / 2), 9000 / (SR / 2)], 'band')
    buf += lfilter(b, a, sw) * np.exp(-((tt - 0.4) ** 2) / 0.08) * 0.25
    write('brew', reverb(buf, mix=0.35))
    # coin
    buf = np.zeros(int(0.9 * SR))
    for k, (nn, dt) in enumerate([('E6', 0), ('B6', 0.07)]):
        sig = bell(note_hz(nn), 0.8, bright=1.6)
        i = int(dt * SR)
        buf[i:i + len(sig)] += sig[:len(buf) - i]
    write('coin', reverb(buf, mix=0.15))
    # shop door bell (two rings)
    buf = np.zeros(int(2.2 * SR))
    for dt in (0.0, 0.16):
        tt2 = t(1.9)
        sig = np.zeros(len(tt2))
        for ratio, amp, dec in [(1, 1, 2.0), (2.43, 0.5, 3.0), (3.9, 0.3, 4.0), (5.4, 0.2, 6.0), (6.9, 0.12, 8.0)]:
            sig += amp * np.sin(2 * np.pi * 1320 * ratio * tt2) * np.exp(-dec * tt2)
        i = int(dt * SR)
        buf[i:i + len(sig)] += sig[:len(buf) - i] * (1 if dt == 0 else 0.7)
    write('doorbell', reverb(buf, mix=0.25))
    # cat purr
    tt = t(1.4)
    nz = rng.normal(0, 1, len(tt)); b, a = butter(2, 260 / (SR / 2)); nz = lfilter(b, a, nz)
    am = (0.5 + 0.5 * np.sin(2 * np.pi * 24 * tt)) ** 2
    breath = 0.6 + 0.4 * np.sin(2 * np.pi * 0.9 * tt)
    write('purr', nz * am * breath * env_adsr(len(tt), 0.15, 0.1, 1, 0.4))
    # sparkle
    buf = np.zeros(int(1.4 * SR))
    for k, nn in enumerate(['A6', 'C#7', 'E7', 'A7']):
        sig = bell(note_hz(nn), 1.0, bright=1.4)
        i = int(k * 0.05 * SR)
        buf[i:i + len(sig)] += sig[:len(buf) - i] * 0.5
    write('sparkle', reverb(buf, mix=0.3))
    # page flip
    tt = t(0.35)
    nz = rng.normal(0, 1, len(tt)); b, a = butter(2, [800 / (SR / 2), 6000 / (SR / 2)], 'band'); nz = lfilter(b, a, nz)
    e = np.exp(-((tt - 0.12) ** 2) / 0.004) * (0.7 + 0.3 * np.sin(2 * np.pi * 40 * tt))
    write('page', nz * e)
    # ui click (wood)
    tt = t(0.08)
    s = np.sin(2 * np.pi * 1100 * tt) * np.exp(-tt * 90) + 0.4 * np.sin(2 * np.pi * 2300 * tt) * np.exp(-tt * 140)
    write('click', np.concatenate([s, np.zeros(1000)]))
    # soft hover tick
    tt = t(0.05)
    s = np.sin(2 * np.pi * 1800 * tt) * np.exp(-tt * 160)
    write('hover', np.concatenate([s, np.zeros(800)]))
    # level up jingle
    buf = np.zeros(int(2.4 * SR))
    for k, nn in enumerate(['D5', 'F#5', 'A5', 'D6']):
        sig = bell(note_hz(nn), 1.6) * 0.5 + pluck_fast(note_hz(nn), 1.6) * 0.5
        i = int(k * 0.12 * SR)
        buf[i:i + len(sig)] += sig[:len(buf) - i]
    sig = bell(note_hz('A6'), 1.8)
    i = int(0.55 * SR); buf[i:i + len(sig)] += sig[:len(buf) - i] * 0.4
    write('levelup', reverb(buf, mix=0.3))
    # sad little tone (wrong potion)
    buf = np.zeros(int(1.2 * SR))
    for k, nn in enumerate(['A4', 'F4']):
        sig = pluck_fast(note_hz(nn), 1.0)
        i = int(k * 0.18 * SR)
        buf[i:i + len(sig)] += sig[:len(buf) - i]
    write('sad', reverb(buf, mix=0.25))
    # footsteps on wood (3 variants)
    for k in range(3):
        tt = t(0.14)
        nz = rng.normal(0, 1, len(tt)); b, a = butter(2, (380 + k * 60) / (SR / 2)); nz = lfilter(b, a, nz)
        s = nz * np.exp(-tt * 45) + 0.5 * np.sin(2 * np.pi * (95 + k * 8) * tt) * np.exp(-tt * 40)
        write(f'step_{k}', np.concatenate([s, np.zeros(1500)]))
    # door (soft wooden thunk + creak)
    tt = t(0.7)
    f = 180 + 40 * np.sin(2 * np.pi * 7 * tt) + 60 * tt
    saw = 2 * ((np.cumsum(f) / SR) % 1) - 1
    b, a = butter(2, [400 / (SR / 2), 1600 / (SR / 2)], 'band')
    creak = lfilter(b, a, saw) * np.exp(-((tt - 0.25) ** 2) / 0.02) * 0.4
    nz = rng.normal(0, 1, len(tt)); b, a = butter(2, 200 / (SR / 2)); thunk = lfilter(b, a, nz) * np.exp(-np.maximum(0, tt - 0.55) * 30) * (tt > 0.55)
    write('door', reverb(creak + thunk * 1.4, mix=0.15))
    # stir whoosh
    tt = t(0.6)
    nz = rng.normal(0, 1, len(tt)); b, a = butter(2, [300 / (SR / 2), 1800 / (SR / 2)], 'band'); nz = lfilter(b, a, nz)
    write('stir', nz * np.sin(np.pi * tt / 0.6) ** 2 * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * tt)))
    # fire crackle loop (8s)
    dur = 8.0
    tt = t(dur)
    nz = rng.normal(0, 1, len(tt)); b, a = butter(2, 500 / (SR / 2)); rumble = lfilter(b, a, nz) * 0.35
    crk = np.zeros(len(tt))
    for _ in range(140):
        i = rng.integers(0, len(tt) - 3000)
        L = rng.integers(200, 1400)
        burst = rng.normal(0, 1, L) * np.exp(-np.linspace(0, 8, L)) * rng.uniform(0.3, 1.0)
        crk[i:i + L] += burst
    b, a = butter(2, 1500 / (SR / 2), 'high'); crk = lfilter(b, a, crk)
    fire = rumble + crk * 0.5
    fade = int(0.3 * SR)
    fire[:fade] *= np.linspace(0, 1, fade); fire[-fade:] *= np.linspace(1, 0, fade)
    # crossfade loop seam
    seam = fire.copy()
    seam[:fade] += fire[-fade:][::-1] * 0
    write('fire_loop', fire, q=3)
    # crickets night loop (10s)
    dur = 10.0
    tt = t(dur)
    buf = np.zeros(len(tt))
    for c in range(3):
        f0 = 4200 + c * 450
        rate = 1.7 + c * 0.35
        chirp = np.sin(2 * np.pi * f0 * tt) * (np.sin(2 * np.pi * 32 * tt) > 0.2)
        gate = (np.sin(2 * np.pi * rate * tt + c) > 0.6).astype(float)
        b, a = butter(1, 30 / (SR / 2)); gate = lfilter(b, a, gate)
        buf += chirp * gate * (0.3 - c * 0.07)
    write('crickets_loop', buf * 0.6, q=3)

if __name__ == '__main__':
    import sys
    if 'sfx' in sys.argv or len(sys.argv) == 1:
        sfx(); print('sfx ok')
    if 'music' in sys.argv or len(sys.argv) == 1:
        make_music(); print('music ok')
