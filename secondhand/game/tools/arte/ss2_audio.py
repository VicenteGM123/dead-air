"""Secondhand Stars · ronda 2 · el audio nuevo (línea R, SS2_DESIGN §7). Original, space-western; nada de fanfarrias,
timbales, coros, marchas en 4/4 con puntillo, ni pitidos de bot. Paleta: guitarra con twang, serrucho cantante (seno
con vibrato lento a 5 Hz, glissandos largos y el ruido del arco), botellas golpeadas, bajo de bidón, armónica,
percusión de mano, pads cálidos. Sale de la misma biblioteca que el audio de la ronda 1 (ss_audio.py).
  music_festival  'Moon Blues' (los Low Moons, Bronzemoon): 6/8 a 76 (negra con puntillo), blues del desierto en Mi
                  menor pentatónico sobre un bordón, AABA de 32 compases (50.5 s), BUCLE sin costura: bajo de bidón,
                  tambor de mano y shaker, serrucho que canta, botellas que contestan. (Nada de swing en 4/4, clarinete,
                  tonada de bar ni steel drums.)
  music_gala      'The Brass Comet' (la noche del cometa): el tema de la tienda (music_shop) en Sol, arreglado: el
                  serrucho canta la melodía, brillo de botellas, palmas, una armónica en contracanto, el pad que crece
                  cuando se enciende el cometa y la ÚLTIMA NOTA es el silbido de Kettle. ~58 s, NO en bucle.
  music_night     'Copper & Tin' (P1: el libro de cuentas, el tablero, después de hora): canción de cuna en La mayor,
                  3/4 a 60, AABA de 16 compases = 48 s, BUCLE sin costura: una caja de música (campanitas), la campana
                  grave "Copper" y la aguda "Tin" que se contestan, armónicos de guitarra, un pad suave. La melodía
                  empieza BAJANDO (nunca una cuarta lenta que sube y después una escala).
  amb_storm       la Scour (30 s, bucle): viento que raspa con ráfagas, arena contra el vidrio, lona que flamea, un
                  cartel que cruje.
  sfx_flap        una fila del cartel de persianas (8-12 clics secos)
  sfx_signal      la cortina del Drift Signal: barrido de sintonía, un lick de 3 notas con twang (SUBE: nunca el
                  Sol-Mi-Do que baja de una cortina registrada), cola de silbido (< 3 s)
  sfx_tape        la cinta de papel imprimiéndose (traqueteo de agujas, ~1.5 s)
  sfx_stamp       sello de goma: golpe + papel
  sfx_upgrade     un trinquete suave y una campanita (la mejora aparece)
  sfx_cheer       un festejo chico con un silbido de dedos (el Derby, la gala)
  sfx_rumble      Bigfall: retumbo largo, vidrios que tiemblan, un crujido lejano
  sfx_gust        una ráfaga de la Scour contra la puerta
  sfx_comet       brillo de vidrio sostenido y una ola grave (se enciende el cometa)
  sfx_rank_up     arpegio de guitarra de 3 notas que sube (quintas abiertas, nada de jingles famosos) + vapor
  sfx_rank_down   una nota que se desliza hacia abajo + un suspiro de vapor
Uso:  python3 ss2_audio.py [nombre ...] [--out carpeta]      (sin nombres: todos; make_audio.py --set=ss2 los copia)
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from ss_audio import (SR, Pista, hz, rng, ks, damp_tail, reed_phrase, pad_chord, shaker, hand_drum, edge_tap,
                      make_ir, make_spring_ir, convolve, echo, eq, lp, hp, bp, sat, master, write_ogg, report, t60env,
                      adsr, pan2, stage, resonators, bell_tone, chime_tube, vibrato, fade, pitch_drop, reverb,
                      _pitch_track, _amp_env, phase_of)
from music_audio import (Tempo, Strings, SHOP_TRAVIS, SHOP_PROG, SHOP_PAD, SHOP_BASS, SHOP_HARP, amp_twang,
                         body_acoustic, dusty, pad_bus, strum, report_buses, MUSIC_LUFS)
from amb_audio import smooth_random, shift, AMB_LUFS
from sfx_audio import buf, put, finish, steam_puff, whistle_tone, click_metal

# ================================================================================================ instrumentos nuevos


def singing_saw(notes, beat, seed=1, vib_cents=26, glide=0.22, tail=0.8, bow=0.05):
    """Serrucho cantante: casi un seno (un poco de 2º y 3er armónico), glissandos largos entre notas, vibrato lento de
    mano (5 Hz) que crece en las notas largas, ataque blando y el soplo del arco (ruido estrecho alrededor de la nota)."""
    r = rng(seed)
    # las notas casi pegadas se atan (el serrucho no corta el arco: se desliza a la siguiente)
    tied = [list(x) for x in sorted(notes, key=lambda x: x[1])]
    for p, q in zip(tied, tied[1:]):
        if 0 < q[1] - (p[1] + p[2]) <= 0.6:
            p[2] = q[1] - p[1]
    notes = [tuple(x) for x in tied]
    end = max(b0 + db for _, b0, db, *rest in notes)
    n = int((end * beat + tail) * SR)
    f, gate, starts = _pitch_track(notes, n, beat, legato_gap=0.03, glide=glide)
    vib = np.ones(n)
    for s, e, opt in starts:
        L = e - s
        if L > int(0.3 * SR):
            vib[s:e] = vibrato(L, rate=5.0 + r.uniform(-0.25, 0.25), cents=vib_cents, delay=0.18, ramp=0.6,
                               ph0=r.uniform(0, 6.28))
    ff = f * vib
    ph, _ = phase_of(ff, n)
    tone = np.sin(2 * np.pi * ph) + 0.12 * np.sin(4 * np.pi * ph) + 0.04 * np.sin(6 * np.pi * ph)
    amp = _amp_env(gate, starts, n, att=0.12, rel=0.35)
    # el arco: ruido que respira con la nota, y un raspón al empezar cada nota no ligada
    rasp = np.zeros(n)
    for s, e, opt in starts:
        L = min(n - s, int(0.12 * SR))
        rasp[s:s + L] += np.exp(-np.arange(L) / (0.04 * SR))
    nz = bp(r.normal(0, 1, n), 1800, 5200) * (bow + 0.2 * rasp)
    return (tone * 0.9 + nz) * amp


def bottle(f, seed=0, dur=1.4, g=1.0):
    """Botella golpeada con una cuchara: un seno claro, un parcial inarmónico que se va rápido, el clic del golpe."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * f * t) * t60env(t, dur * 0.85)
    y += 0.35 * np.sin(2 * np.pi * f * 2.42 * t + 0.4) * t60env(t, 0.25)
    y += 0.12 * np.sin(2 * np.pi * f * 3.97 * t + 1.1) * t60env(t, 0.1)
    y += 0.08 * np.sin(2 * np.pi * (f * 1.003) * t) * t60env(t, dur * 0.6)        # batido leve
    click = bp(r.normal(0, 1, n), 2500, 9000) * t60env(t, 0.004) * 0.3
    return (y + click) * g * np.minimum(1, t / 0.0006)


def drum_bass(name, dur=1.4, seed=0):
    """Bajo de bidón (Mo, de los Low Moons): una cuerda grave sobre un tambor de lata: retumbo hueco y un anillo
    metálico corto."""
    y = ks(hz(name), dur, t60=1.4, bright=0.05, pick=0.3, S=0.5, seed=seed, exc_lp=4.0)
    y = lp(y, 700, 2)
    body = resonators(y, [(88.0, 3.0, 1.0), (176.0, 5.0, 0.4), (410.0, 9.0, 0.22)])
    return y * 0.7 + body * 0.5


def claps(seed=0, n_people=3, accent=1.0):
    """Palmas de unas pocas personas (no exactamente juntas)."""
    r = rng(seed)
    n = int(0.16 * SR)
    out = np.zeros(n)
    for k in range(n_people):
        d = int(r.uniform(0, 0.018) * SR)
        L = n - d
        t = np.arange(L) / SR
        nz = bp(r.normal(0, 1, L), 900 + 300 * k, 3200 + 400 * k)
        env = t60env(t, 0.05) * (1 + 0.6 * t60env(t - 0.006, 0.004) * (t > 0.006))
        out[d:] += nz * env * r.uniform(0.7, 1.0)
    return out * accent / n_people ** 0.5


# ================================================================================================ music_festival
# 6/8: corcheas como unidad (6 por compás). Negra con puntillo = 76 -> corchea = 60 / (76 x 3).
FEST_E8 = 60.0 / (76 * 3)
FEST_BAR = 6 * FEST_E8
# AABA: A en Mi menor (bordón de Mi), B pasa por La, Do, Re y Si
FEST_ROOTS = (['E'] * 8) + (['E'] * 8) + ['A', 'A', 'C', 'C', 'D', 'D', 'B', 'B'] + (['E'] * 8)
FEST_LOW = {'E': ('E2', 'B2', ['G3', 'B3'], 'E4'), 'A': ('A2', 'E3', ['A3', 'C4'], 'E4'),
            'C': ('C3', 'G2', ['G3', 'C4'], 'E4'), 'D': ('D3', 'A2', ['F#3', 'A3'], 'D4'),
            'B': ('B2', 'F#2', ['F#3', 'A3'], 'D#4')}
FEST_BASS = {'E': ('E2', 'B1'), 'A': ('A1', 'E2'), 'C': ('C2', 'G1'), 'D': ('D2', 'A1'), 'B': ('B1', 'F#1')}
# el serrucho (corcheas desde el compás 0 de cada sección): frases propias, pentatónica de Mi menor
SAW_A1 = [('B4', 2, 7), ('D5', 9, 3), ('B4', 12, 6), ('A4', 18, 3), ('G4', 21, 3), ('E4', 24, 10),
          ('G4', 37, 2), ('A4', 39, 3), ('B4', 42, 5)]
SAW_A2 = [('E5', 0, 6), ('D5', 6, 3), ('B4', 9, 3), ('D5', 12, 8), ('B4', 21, 3), ('A4', 24, 6), ('G4', 30, 3),
          ('A4', 33, 3), ('E4', 36, 10)]
SAW_B = [('A4', 0, 6), ('C5', 6, 6), ('E5', 12, 9), ('D5', 21, 3), ('C5', 24, 6), ('D5', 30, 5),
         ('F#5', 36, 6), ('D#5', 42, 5)]
SAW_A3 = [('B4', 2, 7), ('D5', 9, 3), ('E5', 12, 6), ('D5', 18, 3), ('B4', 21, 3), ('A4', 24, 9),
          ('G4', 33, 3), ('E4', 36, 11)]
# las botellas contestan en los huecos del serrucho: (sección, corchea, nota)
BOTTLES = [(0, 34, 'E6'), (0, 35, 'G6'), (0, 47, 'B5'), (1, 20, 'D6'), (1, 46, 'E6'), (1, 47, 'G6'),
           (2, 33, 'A6'), (2, 34, 'E6'), (2, 47, 'F#6'), (3, 33, 'E6'), (3, 34, 'G6'), (3, 35, 'B6'), (3, 47, 'D6')]


def music_festival(out_dir=None):
    nb = len(FEST_ROOTS)
    dur = nb * FEST_BAR
    r = rng(2401)
    S = Strings(24)
    gtr, saw, bass, perc, glass, pad = (Pista(dur) for _ in range(6))
    tb = lambda bar, e8: bar * FEST_BAR + e8 * FEST_E8
    # --- la guitarra del bordón: pulgar en 1 y 4, díada liviana en 3 y 6, un adorno al final de cada 4 compases
    for bi, rt in enumerate(FEST_ROOTS):
        root, fifth, dy, hi = FEST_LOW[rt]
        pat = [(0, root, 'thumb', 0.62), (2, dy[0], 'treble', 0.3), (2, dy[1], 'treble', 0.26), (3, fifth, 'thumb', 0.5),
               (5, hi, 'treble', 0.28)]
        if bi % 4 == 3 and rt == 'E':     # martilleo Mi-Sol-La
            pat += [(4, 'G3', 'treble', 0.3), (4.5, 'A3', 'treble', 0.28)]
        for e8, note, kind, g in pat:
            t0 = tb(bi, e8) + r.normal(0, 0.007)
            y = S.get(note, kind, var=int(r.integers(0, 3)))
            y = damp_tail(y, FEST_E8 * (2.6 if kind == 'thumb' else 2.0), 0.08)
            gtr.add(y, t0, g * r.uniform(0.9, 1.05), -0.25 if kind == 'thumb' else -0.4)
    # --- el bajo de bidón: 1 y la corchea 5 (el empujón del blues del desierto)
    for bi, rt in enumerate(FEST_ROOTS):
        b1, b2 = FEST_BASS[rt]
        bass.add(drum_bass(b1, 1.2, seed=bi), tb(bi, 0) + 0.004, 0.95, 0.05)
        bass.add(drum_bass(b2, 0.9, seed=100 + bi), tb(bi, 4) + 0.004, 0.62, 0.05)
    # --- percusión: tambor de mano (dum en 1 y 4, tak en 6, fantasmas) y shaker en las 6 corcheas
    shk = [shaker(seed=k, accent=1.0) for k in range(6)]
    for bi in range(nb):
        for e8 in range(6):
            a = (1.0 if e8 in (0, 3) else 0.6) * r.uniform(0.85, 1.1)
            perc.add(shk[int(r.integers(0, 6))], tb(bi, e8) + r.normal(0, 0.004), 0.2 * a, 0.45)
        hits = [(0, 'dum', 1.0), (3, 'dum', 0.7), (5, 'tak', 0.55)]
        if bi % 2 == 1:
            hits.append((2, 'tak', 0.3))
        for e8, kind, a in hits:
            t0 = tb(bi, e8) + r.normal(0, 0.005)
            if kind == 'dum':
                perc.add(hand_drum(88, seed=int(r.integers(0, 50)), accent=a), t0, 0.55, -0.15)
            else:
                perc.add(edge_tap(seed=int(r.integers(0, 50)), accent=a, tone=700), t0, 0.22, -0.3)
    # --- el serrucho canta (AABA)
    for sec, ph in enumerate((SAW_A1, SAW_A2, SAW_B, SAW_A3)):
        y = singing_saw(ph, FEST_E8, seed=2410 + sec, vib_cents=24)
        saw.add(y, tb(sec * 8, 0), 0.55, 0.15)
    # --- las botellas contestan
    for sec, e8, note in BOTTLES:
        glass.add(bottle(hz(note), seed=e8 + sec * 50), tb(sec * 8, e8) + r.normal(0, 0.006), 0.4, r.uniform(0.2, 0.6))
    # --- un pad bajo y cálido (casi un bordón)
    chords = {'E': ['E3', 'B3', 'G4'], 'A': ['A3', 'C4', 'E4'], 'C': ['G3', 'C4', 'E4'], 'D': ['F#3', 'A3', 'D4'],
              'B': ['F#3', 'B3', 'D#4']}
    for bi, rt in enumerate(FEST_ROOTS):
        if bi % 2 == 0:
            for side, pn in ((0, -0.7), (1, 0.7)):
                pad.add(pad_chord([hz(x) for x in chords[rt]], FEST_BAR * 2 + 0.1, attack=1.0, release=1.4, cutoff=1100,
                                  detune=8, seed=2450 + bi + side, level=0.5), tb(bi, 0) - 0.05, 1.0, pn)
    report_buses('festival', dict(gtr=gtr, saw=saw, bass=bass, perc=perc, glass=glass, pad=pad))
    tw = amp_twang(gtr.buf)
    spring = make_spring_ir(2.0, seed=24)
    tw = tw + convolve(tw, spring, circular=True) * 0.3
    b = stage(dict(gtr=tw, saw=eq(saw.buf, 'peak', 1400, 1.0, q=0.8, circular=True), bass=bass.buf,
                   perc=dusty(perc.buf), glass=glass.buf, pad=lp(pad.buf, 2000, 2, circular=True)),
              dict(gtr=-1.0, saw=2.5, bass=-1.5, perc=-8.0, glass=-6.0, pad=-14.0))
    mix = sum(b.values())
    room = make_ir(1.6, predelay=0.016, hf=0.3, seed=2460)
    send = b['saw'] * 0.4 + b['glass'] * 0.45 + b['gtr'] * 0.15 + b['perc'] * 0.12 + b['pad'] * 0.2
    mix = mix + convolve(send, room, circular=True) * 0.55
    mix = eq(mix, 'high', 4200, -3.5, circular=True)
    out = master(mix, lufs_target=MUSIC_LUFS, ceiling_db=-1.5, circular=True, hp_hz=36.0)
    print(report('music_festival', out))
    return write_ogg('music_festival', out, q=3, out_dir=out_dir)


# ================================================================================================ music_gala
GALA_PROG = ['G', 'G'] + SHOP_PROG[4:12] + SHOP_PROG[12:18] + ['F', 'D7', 'G']   # 19 compases
# contracanto de armónica en B (pulsos desde el compás 10): notas largas, terceras y sextas
GALA_HARP = [('G4', 0.0, 2.0), ('B4', 2.0, 2.0), ('E5', 4.0, 3.0), ('D5', 7.0, 1.0), ('C5', 8.0, 2.0), ('E5', 10.0, 2.0),
             ('D5', 12.0, 4.0, 'v'), ('B4', 16.0, 2.0), ('D5', 18.0, 2.0), ('G5', 20.0, 3.0, '~'), ('E5', 23.0, 1.0)]
# el serrucho en B: una línea larga que sube
GALA_SAW_B = [('E5', 0.0, 6.0), ('G5', 6.0, 2.0), ('D5', 8.0, 4.0), ('B4', 12.0, 4.0), ('E5', 16.0, 4.0), ('C5', 20.0, 4.0)]
# el cometa: el serrucho sube a Re y se queda en Sol
GALA_SAW_END = [('A4', 0.0, 2.0), ('C5', 2.0, 2.0), ('D5', 4.0, 3.0), ('G5', 7.0, 6.0)]


def music_gala(out_dir=None):
    T = Tempo(80, swing=0.62)
    nb = len(GALA_PROG)
    tail = 3.2
    dur = nb * T.bar + tail
    r = rng(2501)
    S = Strings(25)
    gtr, saw, harp, bass, perc, glass, pad, whis = (Pista(dur, circular=False) for _ in range(8))
    travis = dict(SHOP_TRAVIS)
    travis['F'] = ('F2', 'C3', ['A3', 'C4', 'F4'])
    travis['D7'] = ('D3', 'A2', ['A3', 'C4', 'F#4'])
    padc = dict(SHOP_PAD)
    bassn = dict(SHOP_BASS)
    # --- guitarra: introducción con acordes rasgueados suaves; A y B en fingerpicking; el final rasgueado
    for bi, ch in enumerate(GALA_PROG):
        root, alt, tr = travis[ch]
        if bi < 2 or bi >= nb - 3:
            notes = [root, alt] + tr
            y = strum(S, notes, down=True, vel=0.8 if bi < 2 else 1.0, spread=0.02)
            gtr.add(damp_tail(y, T.bar * (2.4 if bi == nb - 1 else 0.95), 0.2), T.t(bi, 0), 0.5, -0.3)
            if bi >= nb - 3 and bi < nb - 1:
                y2 = strum(S, notes, down=False, vel=0.6, spread=0.015, var=1)
                gtr.add(damp_tail(y2, T.bar * 0.45, 0.15), T.t(bi, 2.5), 0.45, -0.3)
            continue
        pat = [(0, root, 'thumb'), (0, tr[2], 'treble'), (1, tr[1], 'treble'), (2, alt, 'thumb'), (3, tr[0], 'treble'),
               (4, root, 'thumb'), (5, tr[2], 'treble'), (6, alt, 'thumb'), (7, tr[1], 'treble')]
        for e8, note, kind in pat:
            t0 = T.t(bi, e8 * 0.5) + r.normal(0, 0.006)
            y = S.get(note, kind, var=int(r.integers(0, 3)))
            if kind == 'thumb':
                y = damp_tail(y, T.beat * 0.75, 0.06)
                g, pn = 0.55, -0.15
            else:
                y = damp_tail(y, max(0.2, (bi + 1) * T.bar - t0 + 0.05), 0.12)
                g, pn = 0.45, -0.35
            gtr.add(y, t0, g * r.uniform(0.9, 1.05), pn)
    # --- contrabajo en 1 y 3 (desde A; el final: notas largas)
    for bi, ch in enumerate(GALA_PROG):
        if bi < 2:
            continue
        b1, b3 = bassn.get(ch, ('G2', 'D2'))
        last = bi == nb - 1
        y = damp_tail(S.get(b1, 'bass', bi % 2), T.beat * (5.0 if last else 1.7), 0.15)
        bass.add(y, T.t(bi, 0) + 0.004, 0.8, 0.0)
        if not last and bi < nb - 3:
            bass.add(damp_tail(S.get(b3, 'bass', bi % 2), T.beat * 1.7, 0.1), T.t(bi, 2) + 0.004, 0.65, 0.0)
    # --- palmas en 2 y 4 (con swing, sin redoble ni marcha) y shaker, de A hasta antes del cometa
    shk = [shaker(seed=k, accent=1.0) for k in range(6)]
    for bi in range(2, nb - 3):
        for b in (1.0, 3.0):
            perc.add(claps(seed=bi * 10 + int(b), n_people=4), T.t(bi, b) + r.normal(0, 0.006), 0.55, 0.1)
        for e8 in range(8):
            a = (1.0 if e8 % 2 else 0.55) * r.uniform(0.85, 1.1)
            perc.add(shk[int(r.integers(0, 6))], T.t(bi, e8 * 0.5) + r.normal(0, 0.004), 0.2 * a, 0.45)
        perc.add(hand_drum(92, seed=bi, accent=0.8), T.t(bi, 0), 0.45, -0.2)
        perc.add(hand_drum(92, seed=bi + 50, accent=0.55), T.t(bi, 2.5), 0.45, -0.2)
    # --- el serrucho: la melodía de la tienda en A (compases 2-9), una línea larga en B (10-15), el cometa (16-18)
    sa = singing_saw(T.phrase(SHOP_HARP, 4), T.beat, seed=2510, vib_cents=22)
    saw.add(sa, T.t(2, 0), 0.6, 0.15)
    sb = singing_saw(T.phrase(GALA_SAW_B, 0), T.beat, seed=2511, vib_cents=26)
    saw.add(sb, T.t(10, 0), 0.5, 0.2)
    se = singing_saw(GALA_SAW_END, T.beat, seed=2512, vib_cents=30, tail=1.6)
    saw.add(se, T.t(16, 0), 0.62, 0.1)
    # --- la armónica contesta en B
    hp_ = reed_phrase(T.phrase(GALA_HARP, 0), T.beat, seed=2513, vib_cents=14, breath=0.06)
    harp.add(hp_, T.t(10, 0), 0.42, -0.35)
    # --- el brillo de botellas: más y más hacia el cometa
    bnotes = ['G6', 'B6', 'D7', 'A6', 'E6', 'D6']
    for bi in range(nb):
        k = 1 if bi < 10 else (2 if bi < 16 else 4)
        if bi < 2:
            k = 2
        for j in range(k):
            t0 = T.t(bi, r.uniform(0, 4)) if bi < nb - 1 else T.t(bi, j * 0.5)
            glass.add(bottle(hz(bnotes[int(r.integers(0, len(bnotes)))]), seed=bi * 7 + j, dur=1.6), t0,
                      0.32 if bi < 16 else 0.45, r.uniform(-0.6, 0.6))
    # --- el pad: suave en la introducción, ancho después, y la ola grande del cometa (compases 16-18)
    for bi, ch in enumerate(GALA_PROG):
        lvl = 0.55 if bi < 2 else (0.4 if bi < 16 else 0.9)
        cut = 1300 if bi < 16 else 2200
        for side, pn in ((0, -0.7), (1, 0.7)):
            s = pad_chord([hz(x) for x in padc.get(ch, padc['G'])], T.bar + (2.6 if bi == nb - 1 else 0.15),
                          attack=1.2 if bi < 16 else 2.0, release=2.4 if bi == nb - 1 else 1.4, cutoff=cut, detune=8,
                          seed=2520 + bi * 3 + side, level=lvl)
            pad.add(s, T.t(bi, 0) - 0.05, 1.0, pn)
    # --- la última nota: el silbido de Kettle (sube a Sol y se queda), un soplo de vapor
    t_wh = T.t(nb - 1, 2.0)
    whis.add(whistle_tone(hz('D6'), 0.28, seed=2530), t_wh, 0.55, 0.25)
    whis.add(whistle_tone(hz('G6'), 1.3, glide_from=-2.0, end_rise=0.0, seed=2531), t_wh + 0.32, 0.7, 0.25)
    whis.add(steam_puff(0.6, seed=2532), t_wh + 1.45, 0.4, 0.3)
    report_buses('gala', dict(gtr=gtr, saw=saw, harp=harp, bass=bass, perc=perc, glass=glass, pad=pad, whistle=whis))
    b = stage(dict(gtr=body_acoustic(gtr.buf, circ=False), saw=eq(saw.buf, 'peak', 1400, 1.0, q=0.8),
                   harp=eq(harp.buf, 'peak', 1200, 1.5, q=0.8), bass=eq(bass.buf, 'peak', 110, 2.0, q=1.0),
                   perc=dusty(perc.buf, circ=False), glass=glass.buf, pad=lp(pad.buf, 2600, 2), whistle=whis.buf),
              dict(gtr=-1.0, saw=3.0, harp=0.0, bass=-2.0, perc=-8.0, glass=-5.0, pad=-9.0, whistle=-1.0))
    mix = sum(b.values())
    room = make_ir(2.0, predelay=0.02, hf=0.3, seed=2540)
    send = b['saw'] * 0.4 + b['harp'] * 0.35 + b['glass'] * 0.5 + b['gtr'] * 0.18 + b['pad'] * 0.3 + b['whistle'] * 0.3
    mix = mix + convolve(send, room, circular=False)[:len(mix)] * 0.55
    mix = eq(mix, 'high', 4200, -3.5)
    mix = fade(mix, 0.02, 1.2)
    out = master(mix, lufs_target=MUSIC_LUFS, ceiling_db=-1.5, circular=False, hp_hz=36.0)
    print(report('music_gala', out))
    return write_ogg('music_gala', out, q=2.5, out_dir=out_dir)


# ================================================================================================ amb_storm
def amb_storm(out_dir=None):
    dur = 30.0
    n = int(round(dur * SR))
    r = rng(2600)
    g0 = smooth_random(n, dur, 2601, kmax=16, slope=0.7)              # ráfagas más nerviosas que amb_wind
    g0 = 0.35 + 0.65 * g0
    gL, gR = g0, shift(g0, 0.3)
    body, rum, grit = (np.zeros((n, 2)) for _ in range(3))
    centers = [240, 450, 800, 1400, 2400, 4000]
    base = [0.6, 0.85, 1.0, 0.95, 0.7, 0.45]
    sens = [0.5, 0.8, 1.2, 1.6, 2.1, 2.6]
    for ch, g in ((0, gL), (1, gR)):
        nz = r.normal(0, 1, n)
        for c, b, s in zip(centers, base, sens):
            body[:, ch] += bp(nz, c / 1.4, c * 1.4, 2, circular=True) * b * g ** s
        rum[:, ch] = lp(r.normal(0, 1, n), 120, 2, circular=True) * (0.35 + 0.65 * g)
        # arena contra el vidrio: granos agudos y muchos, con un 'tic' resonante
        k = int(dur * 900)
        pos = r.integers(0, n, k)
        keep = r.random(k) < g[pos] ** 1.5
        grains = np.zeros(n)
        grains[pos[keep]] = r.uniform(-1, 1, keep.sum())
        tick = resonators(grains, [(5200.0, 18.0, 1.0), (7400.0, 22.0, 0.6)], circular=True)
        grit[:, ch] = bp(grains, 2500, 11000, 2, circular=True) * 1.2 + tick * 0.6
        grit[:, ch] += hp(r.normal(0, 1, n), 5000, 2, circular=True) * g ** 2.5 * 0.4
    # la lona que flamea en las ráfagas fuertes (golpeteo de 9-13 Hz)
    P = Pista(dur)
    t = np.arange(n) / SR
    flap_rate = 11 + 2 * np.sin(2 * np.pi * t * 2 / dur)
    flap_ph = 2 * np.pi * np.cumsum(flap_rate) / SR
    flap = np.clip(np.sin(flap_ph), 0, 1) ** 6
    strong = np.clip((g0 - 0.62) / 0.38, 0, 1) ** 1.5
    canvas = bp(r.normal(0, 1, n), 180, 1100, 2, circular=True) * flap * strong
    P.add(canvas, 0.0, 1.0, -0.35)
    # el cartel que cruje: tres quejidos lentos (sierra filtrada con roce), en lugares fijos del loop
    for (t0, f0, d, pn) in ((4.0, 340, 1.4, 0.5), (14.5, 290, 1.8, 0.45), (23.0, 380, 1.1, 0.55)):
        m = int(d * SR)
        tt = np.arange(m) / SR
        f = f0 * (1 + 0.12 * np.sin(np.pi * tt / d) + 0.02 * lp(r.normal(0, 1, m), 20) * 40)
        ph = 2 * np.pi * np.cumsum(f) / SR
        saw_ = 2 * ((ph / (2 * np.pi)) % 1) - 1
        fric = (1 + 0.8 * np.clip(lp(r.normal(0, 1, m), 60) * 25, -1, 1))
        creak = bp(saw_ * fric, 300, 2400) * np.sin(np.pi * tt / d) ** 1.5
        P.add(creak, t0, 0.5, pn)
    b = stage(dict(body=body, rumble=rum, grit=grit, canvas=P.buf),
              dict(body=0.0, rumble=-8.0, grit=-12.0, canvas=-9.0), ref_db=-22.0)
    out = sum(b.values())
    out = lp(out, 10000, 2, circular=True)
    y = master(out, lufs_target=AMB_LUFS, ceiling_db=-2.0, circular=True, hp_hz=40.0)
    print(report('amb_storm', y))
    return write_ogg('amb_storm', y, q=3, out_dir=out_dir)


# ================================================================================================ efectos
def click_dry(seed, g=1.0, f=None):
    """Un clic seco de persiana (plástico y lata): golpe agudo con un 'tac' de cuerpo."""
    r = rng(seed)
    n = int(0.045 * SR)
    t = np.arange(n) / SR
    fr = f if f else r.uniform(1800, 2600)
    knock = np.sin(2 * np.pi * fr * t) * t60env(t, 0.012) + 0.4 * np.sin(2 * np.pi * fr * 0.37 * t) * t60env(t, 0.02)
    nz = bp(r.normal(0, 1, n), 2500, 9000) * t60env(t, 0.006)
    return (knock * 0.5 + nz) * g


def sfx_flap(out_dir=None):
    r = rng(3001)
    out = buf(0.6)
    t0 = 0.0
    k = 11
    for i in range(k):
        put(out, click_dry(3010 + i, g=r.uniform(0.6, 0.9)), t0)
        t0 += 0.028 + 0.004 * i + r.uniform(-0.004, 0.004)       # se va frenando
    put(out, click_dry(3099, g=1.2, f=1500), t0 + 0.02)            # la última cae y se asienta
    return finish('sfx_flap', out, -17.0, out_dir=out_dir, room=0.12)


def sfx_signal(out_dir=None):
    """La cortina del Drift Signal: barrido de sintonía, un lick de 3 notas que SUBE (Si-Re-Mi, twang con deslizado),
    y una cola de silbido. Menos de 3 s."""
    r = rng(3101)
    out = buf(2.9)
    # sintonía: estática filtrada que barre y un tono que se acerca a la emisora
    n = int(0.75 * SR)
    t = np.arange(n) / SR
    fc = 600 + 2600 * (t / 0.75) ** 0.6
    stat = np.zeros(n)
    nz = r.normal(0, 1, n)
    blk = 1024
    for i in range(0, n, blk):
        c = fc[min(n - 1, i + blk // 2)]
        stat[i:i + blk] = bp(nz[max(0, i - 2048):i + blk], c * 0.7, c * 1.3)[-len(nz[i:i + blk]):]
    whine = np.sin(2 * np.pi * np.cumsum(1400 + 900 * np.sin(2 * np.pi * 2.2 * t) * (1 - t / 0.75)) / SR)
    env = np.minimum(1, t / 0.05) * (1 - (t / 0.75) ** 3)
    put(out, (stat * 0.6 + whine * 0.12) * env, 0.0, 0.7)
    # el lick con twang (sube) y su eco de muelle
    lick = [('B3', 0.72, 0.9), ('D4', 0.9, 0.85), ('E4', 1.06, 1.0)]
    for i, (nn, tt, g) in enumerate(lick):
        y = ks(hz(nn), 1.6, t60=1.8, bright=0.75, pick=0.11, pickup=0.12, S=0.42, seed=3110 + i, twang=18)
        if i == 2:
            y = pitch_drop(y, -60.0, 0.05)           # el Mi entra deslizándose desde abajo
        put(out, damp_tail(y, 1.4 if i == 2 else 0.2, 0.1), tt, g)
    # la cola: un silbido corto que sube
    put(out, whistle_tone(hz('E6'), 0.5, glide_from=-4.0, glide_t=0.12, seed=3120) * 0.5, 1.55, 0.6)
    x = amp_twang(out, circ=False)
    x = pan2(x) + echo(x, 0.19, fb=0.25, repeats=3, lp_hz=2600, circular=False, dry=False)[:len(x)] * 0.35
    return finish('sfx_signal', x, -15.0, out_dir=out_dir, room=0.15)


def sfx_tape(out_dir=None):
    """La cinta imprimiéndose: ráfagas de agujas (un zumbido áspero de ~70 golpes por segundo) y el papel que avanza."""
    r = rng(3201)
    out = buf(1.7)
    t0 = 0.02
    for line in range(4):
        L = r.uniform(0.18, 0.28)
        k = int(L * 72)
        for i in range(k):
            put(out, click_dry(3210 + line * 40 + i, g=r.uniform(0.25, 0.4), f=r.uniform(3200, 4200)), t0 + i / 72.0)
        t0 += L
        # el papel avanza: un roce corto y el motorcito
        m = int(0.09 * SR)
        tt = np.arange(m) / SR
        feed = bp(r.normal(0, 1, m), 600, 2400) * np.sin(np.pi * tt / 0.09) * 0.3
        motor = np.sin(2 * np.pi * 180 * tt) * np.sin(np.pi * tt / 0.09) * 0.08
        put(out, feed + motor, t0, 1.0)
        t0 += 0.12
    return finish('sfx_tape', out, -18.0, out_dir=out_dir, room=0.1)


def sfx_stamp(out_dir=None):
    """Sello de goma: el golpe sordo (madera y goma sobre la mesa) y el papel que se mueve."""
    r = rng(3301)
    out = buf(0.7)
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    thud = np.sin(2 * np.pi * np.cumsum(140 * (1 + 0.6 * np.exp(-t / 0.01))) / SR) * t60env(t, 0.12)
    thud += lp(r.normal(0, 1, n), 900) * t60env(t, 0.03) * 0.8
    put(out, thud, 0.0, 1.0)
    put(out, bp(r.normal(0, 1, int(0.06 * SR)), 1500, 4000) * 0.2, 0.0, 1.0)      # la goma que se despega
    m = int(0.16 * SR)
    tt = np.arange(m) / SR
    flick = bp(r.normal(0, 1, m), 1800, 7000) * np.sin(np.pi * tt / 0.16) ** 2 * 0.35
    put(out, flick, 0.2, 1.0)
    return finish('sfx_stamp', out, -15.0, out_dir=out_dir, room=0.15)


def sfx_upgrade(out_dir=None):
    """La mejora aparece: un trinquete suave (tres clics) y una campanita."""
    out = buf(1.6)
    for i, tt in enumerate((0.0, 0.07, 0.14)):
        put(out, click_metal(3400 + i, g=0.6), tt)
    put(out, bell_tone(hz('E6'), 1.2, bright=0.6), 0.22, 0.35)
    put(out, bell_tone(hz('B6'), 1.0, bright=0.5), 0.3, 0.22)
    return finish('sfx_upgrade', lp(out, 7000), -15.0, out_dir=out_dir, room=0.2)


def voice(f0, dur, seed, vowel=(780, 1180)):
    """Un 'yeah!' sin palabras: sierra con la vocal, sube y baja."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.25 * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7) * (1 + 0.01 * np.sin(2 * np.pi * 6 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    src = 2 * ((ph / (2 * np.pi)) % 1) - 1
    y = resonators(src, [(vowel[0], 6.0, 1.0), (vowel[1], 8.0, 0.6), (2600, 10.0, 0.25)])
    return y * adsr(n, 0.05, 0.1, 0.8, dur * 0.4)


def sfx_cheer(out_dir=None):
    """Un festejo chico: una docena de voces sin palabras, palmas y un silbido de dedos."""
    r = rng(3501)
    out = np.zeros((int(2.4 * SR), 2))
    for i in range(14):
        f0 = r.uniform(170, 330) if i % 3 else r.uniform(260, 420)
        d = r.uniform(0.6, 1.3)
        v = voice(f0, d, 3510 + i, vowel=(r.uniform(650, 880), r.uniform(1050, 1300)))
        st = pan2(v, r.uniform(-0.8, 0.8), r.uniform(0.3, 0.6))
        i0 = int(r.uniform(0.0, 0.35) * SR)
        k = min(len(st), len(out) - i0)
        out[i0:i0 + k] += st[:k]
    for j in range(16):
        c = pan2(claps(seed=3550 + j, n_people=2), r.uniform(-0.7, 0.7), 0.5)
        i0 = int((0.2 + j * 0.085 + r.uniform(-0.02, 0.02)) * SR)
        k = min(len(c), len(out) - i0)
        out[i0:i0 + k] += c[:k]
    # silbido de dedos: sube, se queda, baja un poco
    n = int(0.75 * SR)
    t = np.arange(n) / SR
    f = 2100 + 900 * np.minimum(1, t / 0.12) - 400 * np.clip((t - 0.5) / 0.25, 0, 1)
    wh = np.sin(2 * np.pi * np.cumsum(f) / SR) * adsr(n, 0.02, 0.05, 0.9, 0.12) * 0.35
    wh += bp(r.normal(0, 1, n), 1800, 4500) * 0.03
    s = pan2(wh, 0.35)
    i0 = int(0.25 * SR)
    out[i0:i0 + n] += s
    return finish('sfx_cheer', lp(out, 7000), -15.0, out_dir=out_dir, room=0.3)


def sfx_rumble(out_dir=None):
    """Bigfall: un retumbo largo que crece y se va, los vidrios que tiemblan y un crujido lejano."""
    r = rng(3601)
    dur = 4.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.minimum(1, t / 0.9) ** 1.5 * np.exp(-np.maximum(0, t - 1.4) / 1.3)
    rum = lp(r.normal(0, 1, n), 90, 2) * 6.0 + lp(r.normal(0, 1, n), 220, 2) * 1.5
    rum *= env * (1 + 0.3 * np.sin(2 * np.pi * 7 * t))
    out = pan2(rum)
    # vidrios: tics agudos con resonancia, densos en el pico
    grains = np.zeros(n)
    k = 260
    pos = r.integers(int(0.4 * SR), int(3.2 * SR), k)
    grains[pos] = r.uniform(-1, 1, k) * env[pos]
    glass = resonators(grains, [(3100, 30.0, 1.0), (4700, 35.0, 0.7), (6300, 40.0, 0.4)])
    out += pan2(glass, 0.3, 0.25)
    # el crujido lejano (con eco del valle)
    m = int(0.4 * SR)
    tt = np.arange(m) / SR
    crack = bp(r.normal(0, 1, m), 300, 3000) * t60env(tt, 0.08) + lp(r.normal(0, 1, m), 200) * t60env(tt, 0.2) * 2
    c = np.zeros(n)
    i0 = int(0.55 * SR)
    c[i0:i0 + m] += crack
    c = pan2(c, -0.4) + echo(c, 0.33, fb=0.35, repeats=4, lp_hz=1500, circular=False, dry=False)[:n] * 0.6
    out += c * 0.6
    return finish('sfx_rumble', out, -14.0, out_dir=out_dir, room=0.25, trim_db=-60.0)


def sfx_gust(out_dir=None):
    """Una ráfaga de la Scour contra la puerta: el viento que sube y baja, la puerta que golpea, arena."""
    r = rng(3701)
    dur = 1.8
    n = int(dur * SR)
    t = np.arange(n) / SR
    g = np.sin(np.pi * np.clip(t / 1.6, 0, 1)) ** 1.6
    wind = np.zeros(n)
    nz = r.normal(0, 1, n)
    for c, b in ((300, 0.8), (700, 1.0), (1400, 0.8), (2800, 0.5)):
        wind += bp(nz, c / 1.4, c * 1.4) * b * g ** (1 + c / 1500)
    out = pan2(wind, -0.2)
    # la puerta: un golpe de madera en el pico y dos traqueteos
    for (tt, gg, f) in ((0.62, 1.0, 120), (0.74, 0.5, 150), (0.83, 0.35, 140)):
        m = int(0.18 * SR)
        x = np.arange(m) / SR
        knock = np.sin(2 * np.pi * f * x) * t60env(x, 0.06) + bp(r.normal(0, 1, m), 400, 2500) * t60env(x, 0.02) * 0.5
        i0 = int(tt * SR)
        out[i0:i0 + m] += pan2(knock, 0.1, gg * 0.7)
    sand = hp(r.normal(0, 1, n), 5000) * g ** 2.5 * 0.3
    out += pan2(sand, 0.3)
    return finish('sfx_gust', out, -15.0, out_dir=out_dir, room=0.12)


def sfx_comet(out_dir=None):
    """El cometa se enciende: un brillo de vidrio sostenido (Sol, Si, Re agudos que titilan) y una ola grave."""
    r = rng(3801)
    dur = 4.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.minimum(1, t / 0.6) * np.exp(-np.maximum(0, t - 2.0) / 1.0)
    shim = np.zeros((n, 2))
    for i, nn in enumerate(['G6', 'B6', 'D7', 'G7', 'D6']):
        f = hz(nn)
        for side in (0, 1):
            trem = 1 + 0.35 * np.sin(2 * np.pi * r.uniform(5, 9) * t + r.uniform(0, 6))
            shim[:, side] += np.sin(2 * np.pi * f * (1 + 0.0007 * (side - 0.5)) * t + r.uniform(0, 6)) * trem * 0.2
    shim *= env[:, None]
    swell = np.zeros(n)
    for f in (hz('G2'), hz('D3'), hz('G3')):
        swell += np.sin(2 * np.pi * f * t + r.uniform(0, 6))
    swell = lp(swell, 600) * (np.minimum(1, t / 1.4) ** 2 * np.exp(-np.maximum(0, t - 2.2) / 1.0)) * 0.5
    out = shim + pan2(swell)
    for k, nn in enumerate(['D7', 'G7', 'B6']):
        b = bottle(hz(nn), seed=3810 + k, dur=1.8, g=0.35)
        i0 = int((0.05 + 0.12 * k) * SR)
        out[i0:i0 + len(b)] += pan2(b, -0.5 + 0.5 * k)[: n - i0]
    return finish('sfx_comet', out, -15.0, out_dir=out_dir, room=0.35, trim_db=-55.0)


def sfx_rank_up(out_dir=None):
    """Sube en el tablero: La-Mi-La con twang (quintas abiertas, no un jingle conocido) y un soplo de vapor."""
    out = buf(1.6)
    for i, (nn, tt, g) in enumerate((('A3', 0.0, 0.8), ('E4', 0.09, 0.85), ('A4', 0.18, 1.0))):
        y = ks(hz(nn), 1.3, t60=1.6, bright=0.7, pick=0.12, pickup=0.12, S=0.42, seed=3900 + i, twang=14)
        put(out, y, tt, g)
    put(out, steam_puff(0.35, seed=3910), 0.4, 0.4)
    out = eq(lp(out, 5500), 'peak', 2400, 2.0, q=0.9)
    return finish('sfx_rank_up', out, -15.0, out_dir=out_dir, room=0.2)


def sfx_rank_down(out_dir=None):
    """Baja en el tablero: una nota que se desliza hacia abajo y un suspiro de vapor."""
    out = buf(1.6)
    y = ks(hz('E4'), 1.4, t60=1.4, bright=0.55, pick=0.14, pickup=0.1, S=0.45, seed=3950)
    t = np.arange(len(y)) / SR
    y = pitch_drop(y, 0.0, 1.0)
    from ss_audio import pitch_warp
    y = pitch_warp(y, -420.0 * np.clip((t - 0.12) / 0.6, 0, 1) ** 1.2)
    put(out, y, 0.0, 0.9)
    puff = steam_puff(0.6, seed=3951)
    put(out, lp(puff, 2500), 0.45, 0.45)
    return finish('sfx_rank_down', lp(out, 4500), -16.0, out_dir=out_dir, room=0.2)


# ================================================================================================ music_night (P1)
NIGHT_BAR = 3.0   # 3/4 a 60: un pulso = 1 s
NIGHT_PROG = ['A', 'F#m', 'D', 'E', 'A', 'F#m', 'Bm7', 'E', 'D', 'A/C#', 'Bm', 'E', 'A', 'F#m', 'DE', 'A']
NIGHT_CHORDS = {'A': ['A3', 'C#4', 'E4'], 'F#m': ['F#3', 'A3', 'C#4'], 'D': ['F#3', 'A3', 'D4'], 'E': ['E3', 'G#3', 'B3'],
                'Bm7': ['F#3', 'A3', 'D4'], 'A/C#': ['C#4', 'E4', 'A4'], 'Bm': ['F#3', 'B3', 'D4'], 'DE': ['F#3', 'A3', 'D4']}
NIGHT_ROOT = {'A': 'A2', 'F#m': 'F#2', 'D': 'D3', 'E': 'E2', 'Bm7': 'B2', 'A/C#': 'C#3', 'Bm': 'B2', 'DE': 'D3'}
# la caja de música: (nota, pulso desde el principio, duración en pulsos); empieza bajando: Do#-Si-La
NIGHT_MEL = [('C#6', 0, 1.5), ('B5', 1.5, 0.5), ('A5', 2, 1), ('F#5', 3, 1), ('A5', 4, 1), ('C#6', 5, 1),
             ('D6', 6, 1.5), ('C#6', 7.5, 0.5), ('B5', 8, 1), ('B5', 9, 1), ('G#5', 10, 1), ('E5', 11, 1),
             ('C#6', 12, 1.5), ('B5', 13.5, 0.5), ('A5', 14, 1), ('A5', 15, 1), ('C#6', 16, 1), ('F#6', 17, 1),
             ('E6', 18, 1.5), ('D6', 19.5, 0.5), ('B5', 20, 1), ('G#5', 21, 1.5), ('B5', 22.5, 0.5), ('A5', 23, 1),
             ('F#6', 24, 2), ('E6', 26, 1), ('C#6', 27, 2), ('E6', 29, 1), ('D6', 30, 1.5), ('C#6', 31.5, 0.5),
             ('B5', 32, 1), ('G#5', 33, 2), ('B5', 35, 1),
             ('C#6', 36, 1.5), ('B5', 37.5, 0.5), ('A5', 38, 1), ('F#5', 39, 1), ('A5', 40, 1), ('C#6', 41, 1),
             ('B5', 42, 1.5), ('A5', 43.5, 0.5), ('G#5', 44, 1), ('A5', 45, 2.5)]


def harmonic(f, dur=1.6, seed=0):
    """Armónico de guitarra (casi un seno: el parcial 1 y un poco del 2, ataque de uña, se apaga solo)."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = r.uniform(0, 6.28)
    y = np.sin(2 * np.pi * f * t + ph) + 0.18 * np.sin(4 * np.pi * f * t + ph * 1.3)
    tick = bp(r.normal(0, 1, n), 2500, 6000) * t60env(t, 0.004) * 0.05
    return (y * t60env(t, dur * 0.55) + tick) * np.minimum(1, t / 0.006)


def soft_attack(y, ms):
    """Un ataque más blando (la caja de música de cuna no pica)."""
    t = np.arange(len(y)) / SR
    return y * np.minimum(1, t / (ms / 1000.0))


def music_night(out_dir=None):
    nb = len(NIGHT_PROG)
    dur = nb * NIGHT_BAR
    r = rng(2601)
    box, harm, copper, tin, pad, low = (Pista(dur) for _ in range(6))
    beat = 1.0
    # --- la caja de música (campanitas cortas, un poco de desafinación de peine)
    for i, (note, b0, ln) in enumerate(NIGHT_MEL):
        f = hz(note) * 2 ** (r.normal(0, 3) / 1200)
        y = soft_attack(bell_tone(f, dur=min(2.6, 1.0 + ln * 0.9), bright=0.45, seed=i), 4.0)
        box.add(y, b0 * beat + r.normal(0, 0.006), 0.5 * r.uniform(0.85, 1.0), r.uniform(-0.15, 0.15))
    # --- armónicos de guitarra en los pulsos 2 y 3 (notas del acorde, una octava arriba)
    for bi, ch in enumerate(NIGHT_PROG):
        notes = NIGHT_CHORDS[ch]
        for k, bt in enumerate((1, 2)):
            nt = notes[(bi + k) % 3]
            f = hz(nt) * 4
            harm.add(harmonic(f, 1.7, seed=bi * 3 + k), bi * NIGHT_BAR + bt * beat + r.normal(0, 0.008),
                     0.28 * r.uniform(0.85, 1.05), 0.45 if k else -0.35)
    # --- Copper (grave) en el 1 de los compases impares; Tin (aguda) le contesta en el 3 de los pares
    for bi, ch in enumerate(NIGHT_PROG):
        if bi % 2 == 0:
            copper.add(chime_tube(hz(NIGHT_ROOT[ch]) * 2, dur=5.5, seed=2610 + bi, bright=0.55, t60=4.2),
                       bi * NIGHT_BAR + 0.002, 0.6, -0.3)
        else:
            top = NIGHT_CHORDS[ch][2]
            tin.add(soft_attack(bell_tone(hz(top) * 4, dur=3.0, bright=0.6, seed=2620 + bi), 5.0), bi * NIGHT_BAR + 2 * beat,
                    0.32, 0.4)
    # --- el bajo: una nota larga y suave por compás (guitarra grave apagada)
    for bi, ch in enumerate(NIGHT_PROG):
        y = ks(hz(NIGHT_ROOT[ch]), 3.2, t60=2.4, bright=0.25, pick=0.3, seed=2630 + bi)
        low.add(damp_tail(y, 2.9, 0.12), bi * NIGHT_BAR + 0.004, 0.55, 0.0)
    # --- el pad (dos compases por acorde, muy bajo)
    for bi, ch in enumerate(NIGHT_PROG):
        for side, pn in ((0, -0.6), (1, 0.6)):
            pad.add(pad_chord([hz(x) for x in NIGHT_CHORDS[ch]], NIGHT_BAR + 0.1, attack=0.9, release=1.2, cutoff=900,
                              detune=6, seed=2640 + bi * 2 + side, level=0.45), bi * NIGHT_BAR - 0.05, 1.0, pn)
    report_buses('night', dict(box=box, harm=harm, copper=copper, tin=tin, pad=pad, low=low))
    b = stage(dict(box=lp(eq(box.buf, 'high', 4500, -4.0, circular=True), 7000, 2, circular=True), harm=harm.buf, copper=copper.buf, tin=tin.buf,
                   pad=lp(pad.buf, 1600, 2, circular=True), low=lp(low.buf, 900, 2, circular=True)),
              dict(box=-1.0, harm=-9.0, copper=-6.0, tin=-9.5, pad=-13.0, low=-8.0))
    mix = sum(b.values())
    room = make_ir(2.4, predelay=0.02, hf=0.28, seed=2650)
    send = b['box'] * 0.5 + b['harm'] * 0.45 + b['copper'] * 0.35 + b['tin'] * 0.5 + b['pad'] * 0.2
    mix = mix + convolve(send, room, circular=True) * 0.6
    out = master(mix, lufs_target=MUSIC_LUFS - 1.0, ceiling_db=-1.5, circular=True, hp_hz=40.0)
    print(report('music_night', out))
    return write_ogg('music_night', out, q=2, out_dir=out_dir)


ALL = ['music_festival', 'music_gala', 'music_night', 'amb_storm', 'sfx_flap', 'sfx_signal', 'sfx_tape', 'sfx_stamp', 'sfx_upgrade',
       'sfx_cheer', 'sfx_rumble', 'sfx_gust', 'sfx_comet', 'sfx_rank_up', 'sfx_rank_down']
LOOPS = ['music_festival', 'music_night', 'amb_storm']


def build(names=None, out_dir=None):
    out = []
    for nm in (names or ALL):
        out.append(globals()[nm](out_dir))
    return out


if __name__ == '__main__':
    args = sys.argv[1:]
    out_dir = None
    if '--out' in args:
        out_dir = args[args.index('--out') + 1]
        args = [a for a in args if a not in ('--out', out_dir)]
    build([a for a in args if not a.startswith('-')] or None, out_dir)
