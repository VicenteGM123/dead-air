"""Secondhand Stars · las tres músicas (lane AUDIO). Originales, space-western lento y cálido (nada de fanfarrias
ni temas de orquesta, nada de jazz de taberna): guitarra pulsada, pad de sintetizador suave, percusión de mano
polvorienta y una lengüeta tipo armónica.
  music_title   'Sunset over Saffra'   64 bpm, 16 compases (60.0 s). Re mayor con el iv menor (Sol menor) para la
                nostalgia: guitarra con trémolo y muelle, pad ancho, armónica que suspira, un silbido contesta.
  music_shop    'The Secondhand Star'  80 bpm con swing, 20 compases (60.0 s). Sol mixolidio: guitarra fingerpicking
                (pulgar alterno), contrabajo, shaker y tambor de mano, pad; armónica en la parte A y una guitarra
                twang grave con muelle en la B.
  music_market  'Starfall Market'      100 bpm, 24 compases (57.6 s). La melodía de la tienda en Re, versión de
                mañana: rasgueo ligero, mandolina, silbido, percusión suave y motores de naves a lo lejos.
Las tres se renderizan en círculo (Pista circular): las colas del final suenan dentro del principio, así que el
archivo es periódico y el loop no tiene costura. Sonoridad igual en las tres (-15 LUFS, como music_tienda de Midnight Cauldron: -15.2).
Uso:  python3 music_audio.py [title] [shop] [market] [--out carpeta]   (sin nombres: las tres)
"""
import os, sys, math, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from ss_audio import (SR, Pista, hz, rng, ks, damp_tail, reed_phrase, whistle_phrase, pad_chord, shaker, hand_drum,
                      edge_tap, make_ir, make_spring_ir, convolve, echo, tremolo, eq, lp, hp, bp, sat, master,
                      write_ogg, report, t60env, loop_lfo, adsr, osc_saw, pan2, active_rms_db, stage)

MUSIC_LUFS = -15.0


# ------------------------------------------------------------------------------------------------ tiempo
class Tempo:
    """Compás de 4/4 con swing opcional (la corchea a contratiempo cae en 'swing' del pulso)."""

    def __init__(self, bpm, swing=0.5, beats=4):
        self.beat = 60.0 / bpm
        self.bar = self.beat * beats
        self.swing = swing

    def sw(self, b):
        """Pulsos rectos -> pulsos con swing."""
        w = math.floor(b + 1e-9)
        f = b - w
        if f < 1e-9:
            return float(w)
        if f <= 0.5:
            return w + f / 0.5 * self.swing
        return w + self.swing + (f - 0.5) / 0.5 * (1 - self.swing)

    def t(self, bar, b):
        return bar * self.bar + self.sw(b) * self.beat

    def phrase(self, notes, bar0):
        """Notas [(nota, pulso, dur, opc)] con pulsos relativos a bar0 -> mismas notas con el swing aplicado."""
        out = []
        for nt in notes:
            b0, d = nt[1], nt[2]
            s, e = self.sw(b0), self.sw(b0 + d)
            out.append((nt[0], s, e - s) + tuple(nt[3:]))
        return out


# ------------------------------------------------------------------------------------------------ cuerdas con caché
STR_KINDS = {
    # pulgar con la palma apagando: grave, corto, blando
    'thumb': dict(dur=1.3, t60=1.1, bright=0.35, pick=0.22, S=0.5, exc_lp=10.0),
    # cuerdas agudas del fingerpicking (acero, cálidas)
    'treble': dict(dur=2.8, t60=2.6, bright=0.3, pick=0.14, S=0.5),
    # guitarra eléctrica limpia con pastilla de puente: el 'twang'
    'twang': dict(dur=3.4, t60=3.6, bright=0.8, pick=0.11, pickup=0.12, S=0.42, twang=16),
    'twangv': dict(dur=3.6, t60=3.8, bright=0.8, pick=0.11, pickup=0.12, S=0.42, twang=16, vib=14, vib_rate=5.2),
    # guitarra del título: twang suave, más larga
    'soft': dict(dur=4.0, t60=4.2, bright=0.6, pick=0.16, pickup=0.14, S=0.45, twang=8),
    # contrabajo
    'bass': dict(dur=2.6, t60=2.2, bright=0.0, pick=0.3, S=0.5, exc_lp=5.0),
    # mandolina (dos cuerdas por orden, un pelo desafinadas)
    'mando': dict(dur=1.4, t60=1.0, bright=0.65, pick=0.09, S=0.44),
    # cuerdas del rasgueo
    'strum': dict(dur=1.9, t60=1.8, bright=0.3, pick=0.16, S=0.5),
}


class Strings:
    def __init__(self, seed=1):
        self.cache = {}
        self.seed = seed

    def get(self, name, kind, var=0):
        key = (name, kind, var)
        if key not in self.cache:
            k = dict(STR_KINDS[kind])
            dur = k.pop('dur')
            f = hz(name)
            sd = zlib.crc32(f'{name}|{kind}|{var}|{self.seed}'.encode()) & 0xFFFF
            y = ks(f, dur, seed=sd, **k)
            if kind == 'mando':     # segunda cuerda del orden
                y = y + ks(f * 2 ** (3.5 / 1200), dur, seed=sd + 1, **k) * 0.8
            if kind == 'bass':
                y = lp(y, 900, 2)
            self.cache[key] = y
        return self.cache[key]


# ------------------------------------------------------------------------------------------------ cadenas de efecto
def amp_twang(x, circ=True):
    """Ampli limpio: menos graves, presencia en 2.6 kHz, altavoz que corta en 5.5 kHz, saturación leve."""
    x = hp(x, 95, 2, circular=circ)
    x = eq(x, 'peak', 2200, 2.5, q=0.9, circular=circ)
    x = eq(x, 'peak', 480, -2.0, q=0.8, circular=circ)
    x = lp(x, 4000, 2, circular=circ)
    return sat(x, 1.25)


def body_acoustic(x, circ=True):
    """Caja de guitarra acústica: resonancias graves, brillo medido."""
    x = hp(x, 70, 2, circular=circ)
    x = eq(x, 'peak', 105, 3.0, q=1.4, circular=circ)
    x = eq(x, 'peak', 230, 1.5, q=1.2, circular=circ)
    x = eq(x, 'peak', 3000, 1.0, q=0.9, circular=circ)
    x = eq(x, 'high', 3800, -6.0, circular=circ)
    return lp(x, 6000, 2, circular=circ)


def dusty(x, circ=True):
    """Percusión 'con polvo': agudos recortados y un poco de saturación."""
    x = lp(x, 5000, 2, circular=circ)
    x = eq(x, 'peak', 200, 1.5, q=1.0, circular=circ)
    return sat(x, 1.6)


def pad_bus(p, chords, tempo, bar0, nbars, cutoff=1300, level=1.0, seed=5, attack=1.2, release=1.6, octave=0):
    """Un acorde de pad por compás (chords: lista de listas de notas), ancho (dos renders a izquierda y derecha)."""
    for i in range(nbars):
        notes = chords[i % len(chords)]
        fr = [hz(n) * 2 ** octave for n in notes]
        for side, pan in ((0, -0.7), (1, 0.7)):
            s = pad_chord(fr, tempo.bar + 0.15, attack=attack, release=release, cutoff=cutoff, detune=8,
                          seed=seed + i * 7 + side, level=level)
            p.add(s, (bar0 + i) * tempo.bar - 0.05, 1.0, pan)


def report_buses(name, buses):
    print(f'  [{name}] ' + '  '.join(f'{k} {20 * np.log10(np.sqrt(np.mean(v.buf ** 2)) + 1e-12):.1f}'
                                       for k, v in buses.items()))


# ================================================================================================ music_shop
SHOP_TRAVIS = {   # (raíz, bajo alterno, agudos de grave a agudo)
    'G': ('G2', 'D3', ['B3', 'D4', 'G4']),
    'C': ('C3', 'G2', ['G3', 'C4', 'E4']),
    'D': ('D3', 'A2', ['A3', 'D4', 'F#4']),
    'Dsus4': ('D3', 'A2', ['A3', 'D4', 'G4']),
    'D7': ('D3', 'A2', ['A3', 'C4', 'F#4']),
    'F': ('F2', 'C3', ['A3', 'C4', 'F4']),
    'Em': ('E2', 'B2', ['G3', 'B3', 'E4']),
}
SHOP_PROG = ['G', 'C', 'G', 'Dsus4',                       # porche (intro): solo guitarra, pad y shaker
             'G', 'G', 'C', 'G', 'F', 'C', 'G', 'D',      # A: armónica
             'Em', 'C', 'G', 'D', 'Em', 'C', 'F', 'D7']   # B: guitarra twang grave
SHOP_PAD = {'G': ['G3', 'B3', 'D4'], 'C': ['G3', 'C4', 'E4'], 'D': ['F#3', 'A3', 'D4'], 'Dsus4': ['G3', 'A3', 'D4'],
            'D7': ['F#3', 'C4', 'D4'], 'F': ['F3', 'A3', 'C4'], 'Em': ['G3', 'B3', 'E4']}
SHOP_BASS = {'G': ('G2', 'D2'), 'C': ('C2', 'G2'), 'D': ('D2', 'A2'), 'Dsus4': ('D2', 'A2'), 'D7': ('D2', 'A2'),
             'F': ('F2', 'C2'), 'Em': ('E2', 'B2')}
# armónica (parte A, compases 4-11): (nota, pulso, duración, opciones '~' bend, 'v' caída)
SHOP_HARP = [
    ('B4', 1.0, 0.5), ('D5', 1.5, 0.5, '~'), ('E5', 2.0, 0.5), ('D5', 2.5, 1.5),
    ('B4', 4.5, 0.5), ('A4', 5.0, 0.5), ('G4', 5.5, 2.0),
    ('E5', 8.0, 0.5, '~'), ('G5', 8.5, 1.0), ('E5', 9.5, 0.5), ('D5', 10.0, 0.5), ('C5', 10.5, 1.0),
    ('D5', 12.0, 2.5),
    ('C5', 16.5, 0.5), ('D5', 17.0, 0.5), ('F5', 17.5, 1.0, '~'), ('D5', 18.5, 0.5), ('C5', 19.0, 0.5),
    ('C5', 20.0, 1.0), ('A4', 21.0, 0.5), ('G4', 21.5, 1.5),
    ('B4', 24.5, 0.5), ('D5', 25.0, 0.5), ('G5', 25.5, 1.0, '~'), ('F5', 26.5, 0.5), ('D5', 27.0, 0.5),
    ('E5', 28.0, 0.5), ('D5', 28.5, 0.5), ('A4', 29.0, 2.0, 'v'),
]
# guitarra twang grave (parte B, compases 12-19)
SHOP_TWANG = [
    ('B2', 0.0, 1.0), ('E3', 1.0, 0.5), ('G3', 1.5, 1.5), ('F#3', 3.0, 1.0),
    ('E3', 4.0, 2.0, 'v'), ('C3', 6.0, 1.0), ('E3', 7.0, 1.0),
    ('D3', 8.0, 1.0), ('G3', 9.0, 0.5), ('B3', 9.5, 1.5), ('A3', 11.0, 1.0),
    ('F#3', 12.0, 3.0, 'v'), ('A2', 15.0, 1.0),
    ('B2', 16.0, 1.0), ('E3', 17.0, 0.5), ('B3', 17.5, 1.5), ('A3', 19.0, 1.0),
    ('G3', 20.0, 2.0, 'v'), ('E3', 22.0, 1.0), ('C3', 23.0, 1.0),
    ('A2', 24.0, 1.0), ('C3', 25.0, 1.0), ('F3', 26.0, 1.5, 'v'), ('E3', 27.5, 0.5),
    ('D3', 28.0, 2.0, 'v'), ('C3', 30.0, 0.5), ('A2', 30.5, 0.5), ('F#2', 31.0, 1.0),
]


def music_shop(out_dir=None):
    T = Tempo(80, swing=0.62)
    nb = len(SHOP_PROG)
    dur = nb * T.bar
    r = rng(301)
    S = Strings(3)
    gtr, lead, twang, bass, perc, pad = (Pista(dur) for _ in range(6))
    # --- guitarra fingerpicking (pulgar alterno + agudos a contratiempo, pinza en el 1)
    for bi, ch in enumerate(SHOP_PROG):
        root, alt, tr = SHOP_TRAVIS[ch]
        intro = bi < 4
        vel = 0.85 if intro else 1.0
        pat = [(0, root, 'thumb'), (0, tr[2], 'treble'), (1, tr[1], 'treble'), (2, alt, 'thumb'), (3, tr[0], 'treble'),
               (4, root, 'thumb'), (5, tr[2], 'treble'), (6, alt, 'thumb'), (7, tr[1], 'treble')]
        if bi % 4 == 3:          # último compás de cada frase: un adorno con el agudo más alto
            pat[-1] = (7, tr[2], 'treble')
        for e8, note, kind in pat:
            t0 = T.t(bi, e8 * 0.5) + r.normal(0, 0.006)
            y = S.get(note, kind, var=int(r.integers(0, 3)))
            if kind == 'thumb':
                y = damp_tail(y, T.beat * 0.75, 0.06)
                g, pan = 0.55 * vel * r.uniform(0.9, 1.05), -0.15
            else:
                end_bar = (bi + 1) * T.bar - t0       # se apaga al cambiar de acorde
                y = damp_tail(y, max(0.2, end_bar + 0.05), 0.12)
                g = (0.42 if e8 % 2 else 0.5) * vel * r.uniform(0.85, 1.05)
                pan = -0.35
            gtr.add(y, t0, g, pan)
    # --- contrabajo: 1 y 3 (en el porche solo el 1)
    for bi, ch in enumerate(SHOP_PROG):
        b1, b3 = SHOP_BASS[ch]
        y = damp_tail(S.get(b1, 'bass', bi % 2), T.beat * 1.7, 0.1)
        bass.add(y, T.t(bi, 0) + 0.004, 0.8 if bi >= 4 else 0.55, 0.0)
        if bi >= 4:
            y = damp_tail(S.get(b3, 'bass', bi % 2), T.beat * 1.7, 0.1)
            bass.add(y, T.t(bi, 2) + 0.004, 0.65, 0.0)
    # --- armónica (A)
    harp = reed_phrase(T.phrase(SHOP_HARP, 4), T.beat, seed=11, vib_cents=14, breath=0.06)
    lead.add(harp, T.t(4, 0), 0.55, 0.22)
    # --- twang (B): notas largas con vibrato de palanca
    for nt in SHOP_TWANG:
        name, b0, d = nt[0], nt[1], nt[2]
        kind = 'twangv' if d >= 1.5 else 'twang'
        y = S.get(name, kind, 0)
        y = damp_tail(y, T.sw(b0 + d) * T.beat - T.sw(b0) * T.beat + (0.25 if 'v' in nt[3:] else 0.05), 0.12)
        twang.add(y, T.t(12, b0) + r.normal(0, 0.004), 0.62, 0.08)
    # --- percusión: shaker en corcheas (acento a contratiempo), tambor de mano dum-tak
    shk = [shaker(seed=k, accent=1.0) for k in range(6)]
    for bi in range(nb):
        intro = bi < 4
        for e8 in range(8):
            a = (1.0 if e8 % 2 else 0.55) * (0.6 if intro else 1.0) * r.uniform(0.85, 1.1)
            perc.add(shk[int(r.integers(0, 6))], T.t(bi, e8 * 0.5) + r.normal(0, 0.004), 0.22 * a, 0.45)
        if intro and bi < 3:
            continue
        if intro:     # el compás 3 anuncia la entrada con un golpe a contratiempo
            perc.add(hand_drum(92, seed=bi, accent=0.6), T.t(bi, 3.5), 0.5, -0.2)
            continue
        hits = [(0.0, 'dum', 1.0), (1.0, 'tak', 0.5), (2.5, 'dum', 0.7), (3.0, 'tak', 0.6)]
        if bi >= 12:
            hits.append((2.0, 'dum', 0.45))
        for b, kind, a in hits:
            t0 = T.t(bi, b) + r.normal(0, 0.005)
            if kind == 'dum':
                perc.add(hand_drum(92, seed=int(r.integers(0, 50)), accent=a), t0, 0.5, -0.2)
            else:
                perc.add(edge_tap(seed=int(r.integers(0, 50)), accent=a, tone=740), t0, 0.22, -0.3)
    # --- pad
    pad_bus(pad, [SHOP_PAD[c] for c in SHOP_PROG], T, 0, nb, cutoff=1250, level=0.5, seed=21)
    report_buses('shop', dict(gtr=gtr, bass=bass, harp=lead, twang=twang, perc=perc, pad=pad))
    # --- efectos y mezcla (todo circular)
    tw = amp_twang(twang.buf)
    spring = make_spring_ir(2.2, seed=12)
    tw = tw + convolve(tw, spring, circular=True) * 0.42
    tw = echo(tw, 0.28, fb=0.22, repeats=3, lp_hz=2500, circular=True)
    b = stage(dict(gtr=body_acoustic(gtr.buf),
                   harp=eq(lead.buf, 'peak', 1200, 1.5, q=0.8, circular=True),
                   twang=tw,
                   bass=eq(bass.buf, 'peak', 110, 2.0, q=1.0, circular=True),
                   perc=dusty(perc.buf),
                   pad=lp(pad.buf, 2200, 2, circular=True)),
              dict(gtr=0.0, harp=3.0, twang=2.0, bass=-2.0, perc=-9.0, pad=-12.0))
    mix = sum(b.values())
    room = make_ir(1.5, predelay=0.014, hf=0.32, seed=31)
    send = b['gtr'] * 0.20 + b['twang'] * 0.18 + b['harp'] * 0.32 + b['perc'] * 0.12 + b['pad'] * 0.25 + b['bass'] * 0.04
    mix = mix + convolve(send, room, circular=True) * 0.55
    mix = eq(mix, 'high', 4000, -4.0, circular=True)
    out = master(mix, lufs_target=MUSIC_LUFS, ceiling_db=-1.5, circular=True, hp_hz=38.0)
    print(report('music_shop', out))
    return write_ogg('music_shop', out, q=5, out_dir=out_dir)



# ------------------------------------------------------------------------------------------------ piezas comunes
def bowed_bass(name, dur, attack=0.35, release=0.7, seed=0):
    """Bajo largo y blando (arco suave): fundamental + dos armónicos, ataque lento."""
    r = rng(seed)
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    f = hz(name) * (1 + 0.0015 * np.sin(2 * np.pi * 4.8 * t + r.uniform(0, 6)) * np.clip((t - 0.4) / 0.5, 0, 1))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
    return y * adsr(n, attack, 0.3, 0.85, release, hold=dur)


def engine_hum(dur, f0, seed=0, bright=500.0):
    """Motor de nave a lo lejos: zumbido grave con armónicos que deriva un poco, retumbo, todo filtrado (distancia)."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    drift = 1 + 0.012 * lp(r.normal(0, 1, n), 0.6, 1) * 30 + 0.006 * np.sin(2 * np.pi * 0.13 * t)
    ph = 2 * np.pi * np.cumsum(f0 * drift) / SR
    tone = sum(np.sin(k * ph + r.uniform(0, 6)) / k ** 1.1 for k in range(1, 9))
    rumble = lp(r.normal(0, 1, n), 160, 2) * 3.0
    y = lp(tone * 0.5 + rumble, bright, 2)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    return y * env


def whoosh_far(dur=5.0, seed=0, f_lo=250.0, f_hi=1400.0):
    """Una nave que pasa muy lejos: ruido que sube y baja de tono y de nivel."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    nz = r.normal(0, 1, n)
    blk = 2048
    for i in range(0, n, blk):
        u = (i + blk / 2) / n
        fc = f_lo + (f_hi - f_lo) * np.sin(np.pi * u) ** 2
        x[i:i + blk] = bp(nz[max(0, i - 4096):i + blk], fc * 0.6, fc * 1.6)[-len(nz[i:i + blk]):]
    env = np.sin(np.pi * t / dur) ** 3
    return x * env


def strum(S, notes, down=True, vel=1.0, spread=0.012, var=0, kind='strum'):
    """Rasgueo: las cuerdas suenan una tras otra (abajo: de grave a agudo; arriba: solo las agudas, al revés)."""
    seq = list(notes) if down else list(notes)[::-1][:4]
    L = int(STR_KINDS[kind]['dur'] * SR) + int(spread * SR * len(seq)) + 10
    y = np.zeros(L)
    for k, nn in enumerate(seq):
        s = S.get(nn, kind, var=(var + k) % 3)
        i = int(k * spread * SR)
        g = vel * (1.0 - 0.06 * k) * (1.0 if down else 0.65)
        y[i:i + len(s)] += s[:L - i] * g
    return y


# ================================================================================================ music_title
TITLE_PROG = ['Dmaj7', 'Gmaj7/D', 'Dmaj7', 'Gm6/D', 'Bm7', 'Gmaj7', 'Em7', 'A7sus4',
              'Dmaj7', 'F#m7', 'Gmaj7', 'Gm6', 'Bm7', 'Em9', 'Gmaj7', 'A7sus4']
TITLE_ARP = {
    'Dmaj7': ['D3', 'A3', 'C#4', 'F#4'], 'Gmaj7/D': ['D3', 'G3', 'B3', 'F#4'], 'Gm6/D': ['D3', 'G3', 'A#3', 'E4'],
    'Bm7': ['B2', 'F#3', 'A3', 'D4'], 'Gmaj7': ['G2', 'D3', 'F#3', 'B3'], 'Em7': ['E3', 'G3', 'B3', 'D4'],
    'A7sus4': ['A2', 'E3', 'G3', 'D4'], 'F#m7': ['F#3', 'A3', 'C#4', 'E4'], 'Gm6': ['G2', 'D3', 'A#3', 'E4'],
    'Em9': ['E3', 'G3', 'D4', 'F#4'],
}
TITLE_PAD = {
    'Dmaj7': ['F#3', 'A3', 'C#4'], 'Gmaj7/D': ['F#3', 'G3', 'B3'], 'Gm6/D': ['E3', 'G3', 'A#3'],
    'Bm7': ['F#3', 'A3', 'D4'], 'Gmaj7': ['F#3', 'B3', 'D4'], 'Em7': ['G3', 'B3', 'D4'], 'A7sus4': ['G3', 'A3', 'D4'],
    'F#m7': ['E3', 'A3', 'C#4'], 'Gm6': ['E3', 'G3', 'A#3'], 'Em9': ['F#3', 'G3', 'B3'],
}
TITLE_BASS = ['D2', 'D2', 'D2', 'D2', 'B1', 'G2', 'E2', 'A2', 'D2', 'F#2', 'G2', 'G2', 'B1', 'E2', 'G2', 'A2']
# armónica (compases 2-9 y la cola 14-15) y silbido (10-13): pulsos relativos al compás de entrada
TITLE_HARP = [
    ('A4', 0, 1.5), ('F#4', 1.5, 0.5), ('E4', 2, 1), ('F#4', 3, 1),
    ('G4', 4, 1.5, '~'), ('A#4', 5.5, 0.5), ('A4', 6, 2),
    ('F#4', 8, 1), ('D4', 9, 1), ('E4', 10, 1.5), ('F#4', 11.5, 0.5),
    ('B4', 12, 3, 'v'),
    ('G4', 16, 1), ('B4', 17, 1), ('D5', 18, 1.5), ('C#5', 19.5, 0.5),
    ('B4', 20, 1), ('A4', 21, 1), ('E4', 22, 2),
    ('F#4', 24, 1.5), ('A4', 25.5, 0.5), ('C#5', 26, 2),
    ('A4', 28, 3, 'v'),
]
TITLE_WHISTLE = [
    ('D6', 0, 1), ('B5', 1, 0.5), ('A5', 1.5, 0.5), ('B5', 2, 2),
    ('A#5', 4, 1), ('A5', 5, 1), ('G5', 6, 2),
    ('F#5', 8, 1.5), ('A5', 9.5, 0.5), ('D6', 10, 2),
    ('E6', 12, 2), ('D6', 14, 1), ('B5', 15, 1),
]
TITLE_TAIL = [('A4', 0, 1), ('F#4', 1, 1), ('E4', 2, 2), ('D4', 4, 1.5), ('E4', 5.5, 2.0, 'v')]


def music_title(out_dir=None):
    T = Tempo(64, swing=0.5)
    nb = len(TITLE_PROG)
    dur = nb * T.bar
    r = rng(101)
    S = Strings(7)
    gtr, lead, wh, bass, pad, air = (Pista(dur) for _ in range(6))
    # --- guitarra con trémolo: arpegio lento, deja sonar
    for bi, ch in enumerate(TITLE_PROG):
        a = TITLE_ARP[ch]
        seq = [(0, a[0]), (1, a[1]), (2, a[2]), (3, a[3]), (4, a[2]), (5, a[1])]
        if bi in (1, 7, 9, 13, 15):
            seq += [(6, a[3]), (7, a[2])]
        for e8, nn in seq:
            t0 = T.t(bi, e8 * 0.5) + r.normal(0, 0.008)
            y = S.get(nn, 'soft', var=int(r.integers(0, 3)))
            y = damp_tail(y, (bi + 1) * T.bar - t0 + 0.35, 0.4)
            gtr.add(y, t0, (0.55 if e8 == 0 else 0.42) * r.uniform(0.9, 1.05), -0.1 + 0.08 * (e8 % 3))
    # --- bajo largo
    for bi, nn in enumerate(TITLE_BASS):
        bass.add(bowed_bass(nn, T.bar - 0.1, seed=bi), T.t(bi, 0), 0.7, 0.0)
    # --- pad ancho y lento
    pad_bus(pad, [TITLE_PAD[c] for c in TITLE_PROG], T, 0, nb, cutoff=1100, level=0.5, seed=41, attack=1.8,
            release=2.4)
    # --- armónica, silbido, la cola
    lead.add(reed_phrase(TITLE_HARP, T.beat, seed=12, vib_cents=16, breath=0.08, bright=0.85), T.t(2, 0), 0.55, 0.15)
    lead.add(reed_phrase(TITLE_TAIL, T.beat, seed=13, vib_cents=16, breath=0.08, bright=0.85), T.t(14, 0), 0.5,
             0.15)
    wh.add(whistle_phrase(TITLE_WHISTLE, T.beat, seed=14, vib_cents=16, breath=0.05), T.t(10, 0), 0.5, -0.2)
    # --- aire del atardecer: viento suave que respira (LFO cerrado en el loop) y dos estrellitas
    n = air.n
    nz = r.normal(0, 1, (n, 2))
    wind = bp(nz, 300, 1500, 2, circular=True)
    sw = 0.55 + 0.45 * loop_lfo(n, 0.05, dur, 1.0)
    air.buf += wind * sw[:, None] * 0.5
    for t0, nn in ((T.t(8, 2.5), 'B6'), (T.t(9, 1.0), 'F#6'), (T.t(13, 3.0), 'E6')):
        from ss_audio import bell_tone
        air.add(bell_tone(hz(nn), 2.5, bright=0.4), t0, 0.06, 0.5)
    report_buses('title', dict(gtr=gtr, bass=bass, harp=lead, whistle=wh, pad=pad, air=air))
    # --- efectos: trémolo de ampli + muelle en la guitarra, sala grande para todo
    g = amp_twang(gtr.buf)
    g = tremolo(g, 4.27, 0.38, circular_len=dur)
    g = g + convolve(g, make_spring_ir(2.6, seed=15), circular=True) * 0.5
    b = stage(dict(gtr=g,
                   harp=eq(lead.buf, 'peak', 1100, 1.0, q=0.8, circular=True),
                   whistle=lp(wh.buf, 3500, 2, circular=True),
                   bass=bass.buf,
                   pad=lp(pad.buf, 2000, 2, circular=True),
                   air=air.buf),
              dict(gtr=0.0, harp=3.0, whistle=0.0, bass=-6.0, pad=-9.0, air=-17.0))
    mix = sum(b.values())
    hall = make_ir(2.9, predelay=0.03, hf=0.3, seed=33)
    send = b['gtr'] * 0.3 + b['harp'] * 0.45 + b['whistle'] * 0.5 + b['pad'] * 0.35 + b['air'] * 0.3
    mix = mix + convolve(send, hall, circular=True) * 0.6
    mix = eq(mix, 'high', 4000, -4.0, circular=True)
    out = master(mix, lufs_target=MUSIC_LUFS, ceiling_db=-1.5, circular=True, hp_hz=38.0)
    print(report('music_title', out))
    return write_ogg('music_title', out, q=5, out_dir=out_dir)


# ================================================================================================ music_market
MARKET_PROG = ['D', 'G', 'D', 'A',                            # entrada: rasgueo, motores lejos
               'D', 'D', 'G', 'D', 'C', 'G', 'D', 'A',        # A: la melodía de la tienda (mandolina)
               'Bm', 'G', 'D', 'A', 'Bm', 'G', 'C', 'A',      # B: silbido
               'G', 'D', 'G', 'A']                            # cola
MARKET_STRUM = {'D': ['A2', 'D3', 'A3', 'D4', 'F#4'], 'G': ['G2', 'B2', 'D3', 'G3', 'B3', 'G4'],
                'A': ['A2', 'E3', 'A3', 'C#4', 'E4'], 'C': ['C3', 'E3', 'G3', 'C4', 'E4'],
                'Bm': ['B2', 'F#3', 'B3', 'D4', 'F#4']}
MARKET_BASS = {'D': ('D2', 'A2'), 'G': ('G2', 'D2'), 'A': ('A2', 'E2'), 'C': ('C2', 'G2'), 'Bm': ('B2', 'F#2')}
MARKET_PAD = {'D': ['F#3', 'A3', 'D4'], 'G': ['G3', 'B3', 'D4'], 'A': ['E3', 'A3', 'C#4'], 'C': ['E3', 'G3', 'C4'],
              'Bm': ['F#3', 'B3', 'D4']}
MARKET_WHISTLE = [
    ('F#5', 0, 1.5), ('D5', 1.5, 0.5), ('B4', 2, 2),
    ('D5', 4, 1), ('E5', 5, 1), ('G5', 6, 1.5), ('F#5', 7.5, 0.5),
    ('E5', 8, 1), ('D5', 9, 1), ('A4', 10, 2),
    ('C#5', 12, 1), ('E5', 13, 1), ('A5', 14, 2),
    ('F#5', 16, 1.5), ('D5', 17.5, 0.5), ('B4', 18, 1), ('D5', 19, 1),
    ('G5', 20, 2), ('F#5', 22, 1), ('E5', 23, 1),
    ('E5', 24, 1.5), ('D5', 25.5, 0.5), ('C5', 26, 2),
    ('C#5', 28, 1), ('E5', 29, 1), ('A4', 30, 2),
]


def _transpose(name, k):
    from ss_audio import midi
    m = midi(name) + k
    names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    return f'{names[m % 12]}{m // 12 - 1}'


def music_market(out_dir=None):
    T = Tempo(100, swing=0.54)
    nb = len(MARKET_PROG)
    dur = nb * T.bar
    r = rng(202)
    S = Strings(11)
    gtr, lead, wh, bass, perc, pad, eng = (Pista(dur) for _ in range(7))
    # --- rasgueo: D . D U . U D U  (las cuerdas se apagan en el golpe siguiente)
    pat = [(0, True, 1.0), (2, True, 0.8), (3, False, 0.6), (5, False, 0.65), (6, True, 0.8), (7, False, 0.55)]
    for bi, ch in enumerate(MARKET_PROG):
        vel = 0.75 if bi < 4 else 1.0
        for j, (e8, down, v) in enumerate(pat):
            t0 = T.t(bi, e8 * 0.5) + r.normal(0, 0.005)
            nxt = pat[j + 1][0] if j + 1 < len(pat) else 8
            y = strum(S, MARKET_STRUM[ch], down, v * vel, spread=0.011 if down else 0.008, var=int(r.integers(0, 3)))
            y = damp_tail(y, (nxt - e8) * 0.5 * T.beat + 0.03, 0.05)
            gtr.add(y, t0, 0.5, -0.3)
    # --- bajo: 1 y 3, notas cortas
    for bi, ch in enumerate(MARKET_PROG):
        b1, b3 = MARKET_BASS[ch]
        for b, nn, g in ((0, b1, 0.85), (2, b3, 0.7)):
            y = damp_tail(S.get(nn, 'bass', bi % 2), T.beat * 0.9, 0.08)
            bass.add(y, T.t(bi, b) + 0.004, g * (0.7 if bi < 4 else 1.0), 0.0)
    # --- mandolina: la melodía A de la tienda, cinco semitonos abajo (Sol -> Re), recta y sin swing
    for nt in SHOP_HARP:
        name, b0, d = _transpose(nt[0], -5), nt[1], nt[2]
        t0 = T.t(4, b0)
        if d >= 1.5:          # nota larga: trémolo de púa que se apaga
            k = int(d * T.beat * 9)
            for i in range(k):
                y = damp_tail(S.get(name, 'mando', i % 3), 1.0 / 9 + 0.02, 0.02)
                lead.add(y, t0 + i / 9, 0.42 * (1 - 0.5 * i / k) * (1.0 if i == 0 else 0.7), 0.25)
        else:
            y = damp_tail(S.get(name, 'mando', int(r.integers(0, 3))), d * T.beat + 0.08, 0.05)
            lead.add(y, t0 + r.normal(0, 0.004), 0.5, 0.25)
    # cola: dos frases de la melodía otra vez, más suave
    for nt in SHOP_HARP[:7]:
        name, b0, d = _transpose(nt[0], -5), nt[1], nt[2]
        y = damp_tail(S.get(name, 'mando', 1), min(d, 1.0) * T.beat + 0.1, 0.05)
        lead.add(y, T.t(20, b0), 0.36, 0.25)
    # --- silbido (B)
    wh.add(whistle_phrase(T.phrase(MARKET_WHISTLE, 12), T.beat, seed=21, vib_cents=14, breath=0.05), T.t(12, 0),
           0.5, -0.15)
    # --- percusión ligera: shaker en semicorcheas, dum en 1 y 3, sonaja en 2 y 4
    shk = [shaker(seed=40 + k, length=0.08) for k in range(6)]
    for bi in range(nb):
        for e16 in range(16):
            a = (1.0 if e16 % 4 == 2 else 0.7 if e16 % 2 == 0 else 0.45) * (0.6 if bi < 4 else 1.0)
            perc.add(shk[int(r.integers(0, 6))], T.t(bi, e16 * 0.25) + r.normal(0, 0.003), 0.17 * a, 0.4)
        if bi < 2:
            continue
        for b in (0, 2):
            perc.add(hand_drum(105, seed=int(r.integers(0, 40)), accent=0.8, slap=0.35, decay=0.25),
                     T.t(bi, b), 0.42, -0.15)
        for b in (1, 3):
            jn = bp(r.normal(0, 1, int(0.16 * SR)), 4500, 9000) * t60env(np.arange(int(0.16 * SR)) / SR, 0.1)
            perc.add(jn, T.t(bi, b) + 0.004, 0.15, 0.35)
    # --- pad aireado
    pad_bus(pad, [MARKET_PAD[c] for c in MARKET_PROG], T, 0, nb, cutoff=1700, level=0.5, seed=61, attack=1.0,
            release=1.4)
    # --- motores de naves a lo lejos (y una que pasa)
    for t0, d, f0, pn, g in ((2.0, 16.0, 58.0, -0.6, 1.0), (21.0, 19.0, 73.0, 0.5, 0.8), (40.0, 15.0, 49.0, -0.2, 0.9)):
        eng.add(engine_hum(d, f0, seed=int(f0)), t0, g, pn)
    eng.add(whoosh_far(6.0, seed=3), 30.0, 0.35, 0.7)
    report_buses('market', dict(gtr=gtr, bass=bass, mando=lead, whistle=wh, perc=perc, pad=pad, eng=eng))
    b = stage(dict(gtr=body_acoustic(gtr.buf),
                   mando=lp(eq(lead.buf, 'high', 3500, -5.0, circular=True), 5000, 2, circular=True),
                   whistle=lp(wh.buf, 3500, 2, circular=True),
                   bass=eq(bass.buf, 'peak', 110, 2.0, q=1.0, circular=True),
                   perc=dusty(perc.buf),
                   pad=lp(pad.buf, 2500, 2, circular=True),
                   eng=eng.buf),
              dict(gtr=-1.0, mando=3.0, whistle=2.0, bass=-3.0, perc=-11.0, pad=-12.0, eng=-13.0))
    mix = sum(b.values())
    yard = make_ir(1.2, predelay=0.02, hf=0.35, seed=35)
    send = b['gtr'] * 0.15 + b['mando'] * 0.25 + b['whistle'] * 0.35 + b['perc'] * 0.1 + b['pad'] * 0.25
    mix = mix + convolve(send, yard, circular=True) * 0.5
    mix = mix + echo(b['mando'], 0.36, fb=0.3, repeats=3, lp_hz=2200, circular=True, dry=False) * 0.12
    mix = eq(mix, 'high', 3000, -7.0, circular=True)
    mix = lp(mix, 9000, 2, circular=True)
    out = master(mix, lufs_target=MUSIC_LUFS, ceiling_db=-1.5, circular=True, hp_hz=38.0)
    print(report('music_market', out))
    return write_ogg('music_market', out, q=5, out_dir=out_dir)

if __name__ == '__main__':
    args = sys.argv[1:]
    out_dir = None
    if '--out' in args:
        i = args.index('--out')
        out_dir = args[i + 1]
        del args[i:i + 2]
    which = args or ['title', 'shop', 'market']
    for w in which:
        print(globals()[f'music_{w}'](out_dir))
