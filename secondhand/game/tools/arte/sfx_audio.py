"""Secondhand Stars · efectos de sonido (lane AUDIO). Todos originales, sintetizados; niveles como Midnight Cauldron
(pico -1 dBFS, sonoridad parecida a su efecto equivalente).
  sfx_bell      campanilla de viento de la puerta (tubos pentatónicos que la puerta golpea)
  sfx_whistle   el silbato de vapor de Kettle, contento: dos notas que suben y un soplo de vapor
  sfx_blip1..3  pitidos de bot suaves y amables (graves, redondos, lentos: un '¿hm?', un '¡mm-hm!', un 'du-di-du';
                nada de trinos rápidos agudos)
  sfx_ratchet   llave de carraca: dos tirones
  sfx_sizzle    el soldador sobre el estaño (siseo con chisporroteo)
  sfx_coins     fichas de crédito que caen y suenan
  sfx_pod       una cápsula que se abre: cierre, presión que sale, tapa y piezas que suenan dentro
  sfx_good      acierto: guitarra twang que sube y una campanita
  sfx_bad       error: dos notas que bajan y un 'bonk' de madera, suave
  sfx_takeoff   una nave que despega a lo lejos
  sfx_tea       Kettle sirve té: el chorro (burbujas que suben de tono al llenarse la taza), gotas y la taza
Uso:  python3 sfx_audio.py [nombre ...] [--out carpeta]
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from ss_audio import (SR, hz, rng, ks, lp, hp, bp, eq, resonators, chime_tube, bell_tone, make_ir, reverb, master,
                      write_ogg, report, t60env, adsr, pan2, osc_saw, fade, pitch_drop, sat, damp_tail)

ROOM = None


def room_ir():
    """Sala pequeña de la tienda (madera, chapa, trastos): corta y algo oscura."""
    global ROOM
    if ROOM is None:
        ROOM = make_ir(0.7, predelay=0.006, hf=0.4, seed=900, early=0.35)
    return ROOM


def buf(d):
    return np.zeros(int(d * SR))


def put(b, sig, t, g=1.0):
    i = int(round(t * SR))
    if i < 0:
        sig, i = sig[-i:], 0
    if i >= len(b):
        return
    k = min(len(sig), len(b) - i)
    b[i:i + k] += sig[:k] * g


def trim(x, thr_db=-70.0, pad=0.02):
    """Corta el silencio final (deja 'pad' s) y hace un fundido corto al final."""
    a = np.abs(x).max(axis=1) if x.ndim == 2 else np.abs(x)
    thr = a.max() * 10 ** (thr_db / 20)
    idx = np.flatnonzero(a > thr)
    end = min(len(x), (idx[-1] if len(idx) else len(x) - 1) + int(pad * SR))
    return fade(x[:end], 0.0005, min(0.04, end / SR * 0.2))


def finish(name, x, lufs_target, ceiling=-1.0, out_dir=None, room=0.0, trim_db=-70.0):
    """Sala (opcional), recorte del final, nivel (sonoridad pedida, pico <= techo) y OGG."""
    x = np.asarray(x, float)
    if x.ndim == 1:
        x = pan2(x)
    if room > 0:
        x = reverb(x, room_ir(), wet=room, dry=1.0)
    x = trim(x, thr_db=trim_db)
    y = master(x, lufs_target=lufs_target, ceiling_db=ceiling, hp_hz=40.0)
    print(report(name, y))
    return write_ogg(name, y, q=5, out_dir=out_dir)


# ------------------------------------------------------------------------------------------------ puerta
def sfx_bell(out_dir=None):
    """La puerta empuja la campanilla de viento: un racimo de golpes y unos pocos más sueltos."""
    r = rng(1001)
    tubes = ['A5', 'B5', 'D6', 'E6', 'F#6']
    hits = [(0.0, 1.0), (0.05, 0.8), (0.12, 0.7), (0.21, 0.55), (0.34, 0.45), (0.52, 0.32), (0.83, 0.2)]
    out = np.zeros((int(3.2 * SR), 2))
    last = -1
    for k, (t0, v) in enumerate(hits):
        i = int(r.integers(0, len(tubes)))
        if i == last:
            i = (i + 2) % len(tubes)
        last = i
        s = chime_tube(hz(tubes[i]), 2.6, seed=1010 + k, bright=0.8, t60=2.0)
        pan = -0.5 + i * 0.25
        st = pan2(s * v, pan)
        j = int(t0 * SR)
        out[j:j + len(st)] += st[:len(out) - j]
    # el badajo de madera al primer golpe
    tk = np.arange(int(0.03 * SR)) / SR
    clack = bp(r.normal(0, 1, len(tk)), 900, 3500) * t60env(tk, 0.012) * 0.25
    out[:len(clack)] += pan2(clack)
    out = eq(out, 'high', 7000, -3.0)
    return finish('sfx_bell', out, -12.0, out_dir=out_dir, room=0.25)


# ------------------------------------------------------------------------------------------------ Kettle
def steam_puff(dur=0.4, seed=0):
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = bp(r.normal(0, 1, n), 1200, 7000)
    env = np.minimum(1, t / 0.012) * np.exp(-t / (dur * 0.33))
    return lp(nz * env, 5000)


def whistle_tone(f0, dur, glide_from=-3.0, glide_t=0.06, end_rise=0.0, seed=0):
    """Silbato de dos cámaras (tercera mayor) con aire, que entra subiendo de tono."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    semi = glide_from * np.exp(-t / glide_t)
    if end_rise:
        semi = semi + end_rise * np.clip((t - dur * 0.6) / (dur * 0.4), 0, 1) ** 2
    wob = 1 + 0.004 * np.sin(2 * np.pi * 6.5 * t) + 0.002 * lp(r.normal(0, 1, n), 30) * 20
    f = f0 * 2 ** (semi / 12) * wob
    ph1 = 2 * np.pi * np.cumsum(f) / SR
    ph2 = 2 * np.pi * np.cumsum(f * 1.26) / SR
    tone = np.sin(ph1) + 0.55 * np.sin(ph2) + 0.08 * np.sin(2 * ph1)
    air = bp(r.normal(0, 1, n), f0 * 0.8, f0 * 1.9) * 0.35
    env = adsr(n, 0.03, 0.05, 0.85, 0.07)
    return (tone + air) * env


def sfx_whistle(out_dir=None):
    out = buf(1.3)
    put(out, whistle_tone(1050.0, 0.22, seed=1101), 0.0, 0.9)
    put(out, whistle_tone(1400.0, 0.42, glide_from=-2.0, end_rise=1.2, seed=1102), 0.25, 1.0)
    put(out, steam_puff(0.45, seed=1103), 0.62, 0.55)
    out = lp(out, 4500)
    return finish('sfx_whistle', out, -14.0, out_dir=out_dir, room=0.18)


# ------------------------------------------------------------------------------------------------ bots
def coo(f_track, seed=0, breath=0.03):
    """Voz de bot amable: casi un seno, redondo (ocarina pequeña), con una pizca de aire. f_track en Hz por muestra."""
    r = rng(seed)
    n = len(f_track)
    ph = 2 * np.pi * np.cumsum(f_track) / SR
    tone = np.sin(ph) + 0.16 * np.sin(2 * ph + 0.4) + 0.04 * np.sin(3 * ph)
    air = bp(r.normal(0, 1, n), 600, 2400) * breath
    return tone + air


def glide_notes(notes, gl=0.025):
    """notes = [(hz, dur)] -> curva de frecuencia con portamento corto entre notas."""
    f = np.concatenate([np.full(int(d * SR), fr) for fr, d in notes])
    k = int(gl * SR)
    if k > 1:
        f = np.convolve(np.pad(f, (k, k), mode='edge'), np.ones(k) / k, mode='same')[k:-k]
    return f


def env_notes(notes, att=0.012, rel=0.04, gap=0.0):
    parts = []
    for fr, d in notes:
        n = int(d * SR)
        parts.append(adsr(n, att, 0.03, 0.85, min(rel, d * 0.5)) if gap else np.ones(n))
    e = np.concatenate(parts)
    if not gap:
        e = adsr(len(e), att, 0.03, 0.9, rel)
    return e


def sfx_blips(out_dir=None):
    paths = []
    # 1: '¿hm?' una nota que pregunta (sube una cuarta al final)
    n = int(0.24 * SR)
    t = np.arange(n) / SR
    f = 510 * 2 ** (5 / 12 * np.clip((t - 0.1) / 0.12, 0, 1) ** 2)
    y = coo(f, seed=1201) * adsr(n, 0.018, 0.04, 0.85, 0.05)
    paths.append(finish('sfx_blip1', lp(y, 2600), -16.0, out_dir=out_dir, room=0.12, trim_db=-48.0))
    # 2: '¡mm-hm!' dos notas, la segunda más grave (sí, de acuerdo)
    notes = [(620.0, 0.1), (465.0, 0.16)]
    f = glide_notes(notes, 0.02)
    e = env_notes(notes, gap=1)
    y = coo(f, seed=1202) * e
    paths.append(finish('sfx_blip2', lp(y, 2600), -16.0, out_dir=out_dir, room=0.12, trim_db=-48.0))
    # 3: 'du-di-du' tres notas que suben (contento), la última con un vibrato pequeño
    notes = [(440.0, 0.075), (554.4, 0.075), (659.3, 0.2)]
    f = glide_notes(notes, 0.015)
    tt = np.arange(len(f)) / SR
    f = f * (1 + 0.012 * np.sin(2 * np.pi * 7 * tt) * np.clip((tt - 0.17) / 0.06, 0, 1))
    e = env_notes(notes, att=0.008, rel=0.06, gap=1)
    y = coo(f, seed=1203) * e
    paths.append(finish('sfx_blip3', lp(y, 2600), -16.0, out_dir=out_dir, room=0.12, trim_db=-48.0))
    return paths


# ------------------------------------------------------------------------------------------------ banco de trabajo
def click_metal(seed, f=None, g=1.0):
    r = rng(seed)
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    f = f or r.uniform(3200, 4200)
    ring = sum(a * np.sin(2 * np.pi * f * m * t + r.uniform(0, 6)) * t60env(t, d)
               for m, a, d in ((1.0, 1.0, 0.03), (1.47, 0.6, 0.02), (2.13, 0.35, 0.012)))
    tick = bp(r.normal(0, 1, n), 2500, 9000) * t60env(t, 0.004) * 1.4
    return (ring * 0.5 + tick) * g


def sfx_ratchet(out_dir=None):
    r = rng(1301)
    out = buf(1.1)
    t0 = 0.0
    for stroke, (k, span) in enumerate(((9, 0.34), (6, 0.22))):
        for i in range(k):
            u = i / (k - 1)
            tt = t0 + span * (u + 0.12 * math.sin(math.pi * u)) / 1.0
            put(out, click_metal(1310 + stroke * 20 + i, f=3700 + r.uniform(-120, 120)), tt, 0.85 * (1 - 0.25 * u))
        # el mango vuelve: un roce corto
        n = int(0.05 * SR)
        put(out, bp(r.normal(0, 1, n), 800, 3000) * t60env(np.arange(n) / SR, 0.02) * 0.2, t0 + span + 0.02)
        t0 += span + 0.2
    out = lp(out, 9000)
    return finish('sfx_ratchet', out, -15.0, out_dir=out_dir, room=0.15)


def sfx_sizzle(out_dir=None):
    r = rng(1401)
    dur = 0.95
    n = int(dur * SR)
    t = np.arange(n) / SR
    hiss = bp(r.normal(0, 1, n), 2500, 9500)
    flick = 0.75 + 0.25 * lp(r.normal(0, 1, n), 25) * 12
    env = np.minimum(1, t / 0.015) * (0.55 + 0.45 * np.exp(-t / 0.12)) * np.clip((dur - t) / 0.35, 0, 1)
    crack = np.zeros(n)
    k = int(dur * 70)
    pos = r.integers(0, n - 400, k)
    for p in pos:
        L = int(r.integers(30, 160))
        crack[p:p + L] += r.normal(0, 1, L) * np.exp(-np.arange(L) / (L / 4)) * r.uniform(0.4, 1.2)
    crack = hp(crack, 1500)
    y = hiss * flick * env * 0.6 + crack * env * 0.7
    # un 'tss' inicial cuando la punta toca
    put(y, bp(r.normal(0, 1, int(0.05 * SR)), 3000, 10000) * t60env(np.arange(int(0.05 * SR)) / SR, 0.02), 0.0, 0.8)
    y = lp(y, 9000)
    return finish('sfx_sizzle', y, -18.0, out_dir=out_dir, room=0.08)


def chip_clack(seed, g=1.0):
    """Ficha de crédito (cerámica con canto de metal) que choca con otra."""
    r = rng(seed)
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    f = r.uniform(2400, 3200)
    body = sum(a * np.sin(2 * np.pi * f * m * t + r.uniform(0, 6)) * t60env(t, d)
               for m, a, d in ((1.0, 1.0, 0.05), (1.73, 0.5, 0.035), (2.61, 0.3, 0.02)))
    knock = bp(r.normal(0, 1, n), 1200, 6000) * t60env(t, 0.006) * 1.2
    return (body * 0.45 + knock) * g


def sfx_coins(out_dir=None):
    r = rng(1501)
    out = buf(1.2)
    times = [0.0, 0.045, 0.085, 0.16, 0.21, 0.30, 0.38]
    for i, tt in enumerate(times):
        put(out, chip_clack(1510 + i), tt + r.uniform(-0.005, 0.005), 1.0 - 0.1 * i)
    # brillo: dos campanitas suaves (crédito recibido)
    put(out, bell_tone(hz('G6'), 0.9, bright=0.5), 0.02, 0.22)
    put(out, bell_tone(hz('D7'), 0.8, bright=0.4), 0.11, 0.16)
    out = eq(out, 'high', 8000, -3.0)
    return finish('sfx_coins', out, -12.0, out_dir=out_dir, room=0.12)


def sfx_pod(out_dir=None):
    r = rng(1601)
    out = buf(2.2)
    # 1. el cierre salta
    put(out, click_metal(1602, f=2300, g=1.0), 0.0)
    n = int(0.05 * SR)
    put(out, lp(r.normal(0, 1, n), 600) * t60env(np.arange(n) / SR, 0.02) * 1.2, 0.0)
    # 2. presión que sale (pssshh) con el filtro que baja
    dur = 0.75
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = r.normal(0, 1, n)
    hissy = np.zeros(n)
    blk = 2048
    for i in range(0, n, blk):
        u = (i + blk / 2) / n
        fc = 5200 * (1 - 0.6 * u)
        seg = bp(nz[max(0, i - 4096):i + blk], fc * 0.45, min(fc * 1.8, 18000))
        hissy[i:i + blk] = seg[-len(nz[i:i + blk]):]
    put(out, hissy * np.minimum(1, t / 0.01) * np.exp(-t / 0.22), 0.04, 0.6)
    # 3. la tapa gira (crujido metálico corto) y topa
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    fr = 260 + 120 * t / 0.22
    creak = bp(osc_saw(fr * (1 + 0.15 * np.sin(2 * np.pi * 31 * t)), n), 600, 2600) * np.sin(np.pi * t / 0.22) * 0.18
    put(out, creak, 0.3)
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    clunk = np.sin(2 * np.pi * np.cumsum(180 * np.exp(-t * 8) + 90) / SR) * t60env(t, 0.12)
    put(out, clunk + bp(r.normal(0, 1, n), 300, 1500) * t60env(t, 0.02) * 0.5, 0.52, 0.7)
    # 4. las piezas de dentro se acomodan
    for i, tt in enumerate((0.6, 0.66, 0.75, 0.83, 0.97)):
        put(out, click_metal(1620 + i, f=r.uniform(1800, 3200), g=0.35 - 0.04 * i), tt)
    # 5. un brillo pequeño: ¡algo bueno dentro!
    for i, (nn, tt) in enumerate((('D6', 0.62), ('A6', 0.7), ('D7', 0.78))):
        put(out, bell_tone(hz(nn), 0.9, bright=0.5), tt, 0.1)
    return finish('sfx_pod', out, -13.0, out_dir=out_dir, room=0.15)


# ------------------------------------------------------------------------------------------------ resultados
def twang_note(name, dur=1.6, seed=0):
    y = ks(hz(name), dur, t60=2.2, bright=0.7, pick=0.12, pickup=0.12, S=0.42, seed=seed, twang=14)
    return y


def sfx_good(out_dir=None):
    out = buf(1.9)
    for i, (nn, tt, g) in enumerate((('G4', 0.0, 0.8), ('B4', 0.0, 0.6), ('D5', 0.09, 0.8), ('G5', 0.18, 0.95))):
        put(out, twang_note(nn, seed=1700 + i), tt, g)
    put(out, bell_tone(hz('G6'), 1.3, bright=0.5), 0.2, 0.18)
    put(out, bell_tone(hz('D7'), 1.1, bright=0.4), 0.27, 0.1)
    out = eq(lp(out, 5500), 'peak', 2400, 2.0, q=0.9)
    return finish('sfx_good', out, -13.0, out_dir=out_dir, room=0.22)


def sfx_bad(out_dir=None):
    out = buf(1.3)
    a = ks(hz('A3'), 1.0, t60=0.9, bright=0.45, pick=0.15, S=0.47, seed=1801)
    b = pitch_drop(ks(hz('F3'), 1.2, t60=1.1, bright=0.4, pick=0.15, S=0.48, seed=1802), -25.0, 0.6)
    put(out, a, 0.0, 0.8)
    put(out, b, 0.16, 0.85)
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    bonk = np.sin(2 * np.pi * np.cumsum(240 * np.exp(-t * 10) + 150) / SR) * t60env(t, 0.09)
    put(out, bonk, 0.16, 0.6)
    out = lp(out, 4000)
    return finish('sfx_bad', out, -14.0, out_dir=out_dir, room=0.18)


# ------------------------------------------------------------------------------------------------ puerto
def sfx_takeoff(out_dir=None):
    """Una nave despega lejos: el motor se enciende, ruge un momento y se va subiendo (se apaga a lo lejos)."""
    r = rng(1901)
    dur = 7.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    # nivel: sube, máximo hacia 2.6 s, se va
    lvl = np.clip(t / 2.2, 0, 1) ** 1.6 * np.exp(-np.maximum(0, t - 2.6) / 1.5)
    # retumbo grave
    rum = lp(r.normal(0, 1, n), 120, 2) * 3.0
    # rugido: ruido que se abre y luego se cierra (distancia que crece)
    nz = r.normal(0, 1, n)
    roar = np.zeros(n)
    blk = 4096
    for i in range(0, n, blk):
        tc = (i + blk / 2) / SR
        fc = 300 + 1500 * np.clip(tc / 2.4, 0, 1) - 1200 * np.clip((tc - 2.6) / 4.0, 0, 1)
        seg = bp(nz[max(0, i - 4096):i + blk], max(120, fc * 0.4), fc * 1.6)
        roar[i:i + blk] = seg[-len(nz[i:i + blk]):]
    # turbina: tono que sube al encenderse y baja al alejarse (Doppler)
    ft = 220 + 380 * np.clip(t / 2.0, 0, 1) ** 0.7 - 120 * np.clip((t - 2.8) / 4, 0, 1)
    ph = 2 * np.pi * np.cumsum(ft) / SR
    turb = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * np.sin(3.02 * ph)) * 0.25
    hum = np.sin(2 * np.pi * np.cumsum(52 + 20 * np.clip(t / 2, 0, 1)) / SR) * 0.25
    y = (rum * 0.7 + roar * 1.0 + turb * 0.6 + hum) * lvl
    y = hp(lp(y, 2600), 45)
    y *= np.clip((dur - t) / 1.8, 0, 1) ** 1.5          # se apaga del todo antes del final (sin corte)
    st = np.stack([y, y], 1)
    # se mueve de izquierda a derecha, arriba
    p = np.clip(-0.4 + 0.9 * u, -1, 1)
    st[:, 0] *= np.cos((p + 1) * np.pi / 4)
    st[:, 1] *= np.sin((p + 1) * np.pi / 4)
    far = make_ir(2.4, predelay=0.06, hf=0.2, seed=1902, early=0.05)
    st = reverb(st, far, wet=0.5, dry=0.8)
    return finish('sfx_takeoff', fade(st, 0.05, 0.6), -16.0, out_dir=out_dir)


# ------------------------------------------------------------------------------------------------ té
def bubble(f0, tau, rise=0.15):
    """Burbuja (modelo de Minnaert / van den Doel): seno que decae y sube un poco de tono."""
    n = int(tau * 6 * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + rise * t / tau)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau)


def sfx_tea(out_dir=None):
    r = rng(2001)
    out = buf(2.8)
    pour = 1.9
    n = int(pour * SR)
    t = np.arange(n) / SR
    fill = t / pour
    # chorro: ruido con la cavidad de la taza que sube de tono al llenarse
    nz = r.normal(0, 1, n)
    stream = np.zeros(n)
    blk = 2048
    for i in range(0, n, blk):
        u = (i + blk / 2) / n
        fc = 520 + 1100 * u
        seg = bp(nz[max(0, i - 4096):i + blk], fc * 0.75, fc * 1.35)
        stream[i:i + blk] = seg[-len(nz[i:i + blk]):]
    env = np.minimum(1, t / 0.08) * np.clip((pour - t) / 0.15, 0, 1)
    glug = 0.7 + 0.3 * np.sin(2 * np.pi * 7.0 * t + 0.6 * np.sin(2 * np.pi * 1.3 * t))   # el pico de la tetera
    put(out, stream * env * glug * 0.3, 0.05)
    # burbujas: muchas, pequeñas, su tono medio sube con el nivel del té
    k = int(pour * 220)
    for i in range(k):
        tt = r.uniform(0.02, pour - 0.05)
        u = tt / pour
        f0 = r.uniform(700, 1500) * (1 + 0.9 * u)
        tau = r.uniform(0.004, 0.012)
        put(out, bubble(f0, tau, rise=r.uniform(0.1, 0.3)), 0.05 + tt, r.uniform(0.08, 0.33))
    # últimas gotas y la taza
    for i, tt in enumerate((pour + 0.12, pour + 0.3, pour + 0.52)):
        put(out, bubble(r.uniform(1400, 1900), 0.012, 0.4), tt, 0.35 - 0.08 * i)
    put(out, bell_tone(hz('E6') * 1.03, 0.6, bright=0.6), pour + 0.62, 0.12)
    out = lp(out, 7000)
    return finish('sfx_tea', out, -16.0, out_dir=out_dir, room=0.15)


ALL = ['bell', 'whistle', 'blips', 'ratchet', 'sizzle', 'coins', 'pod', 'good', 'bad', 'takeoff', 'tea']

if __name__ == '__main__':
    args = sys.argv[1:]
    out_dir = None
    if '--out' in args:
        i = args.index('--out')
        out_dir = args[i + 1]
        del args[i:i + 2]
    for w in (args or ALL):
        print(globals()[f'sfx_{w}'](out_dir))
