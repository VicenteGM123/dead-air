"""Secondhand Stars · ambientes en loop (lane AUDIO). Render circular: el loop no tiene costura.
  amb_wind  (24 s) viento del desierto: ráfagas lentas (un banco de filtros cuyas bandas altas suben con la ráfaga),
            un retumbo grave, silbidos muy suaves en las ráfagas fuertes y la arena que raspa.
  amb_port  (36 s) el puerto de Rustwater a lo lejos: dos naves al ralentí, dos que pasan muy lejos, gente que
            charla (sin palabras), un altavoz lejano que anuncia algo (un murmullo con eco, sin palabras),
            golpes de metal y un soplido hidráulico de vez en cuando.
Uso:  python3 amb_audio.py [wind] [port] [--out carpeta]
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from ss_audio import (SR, Pista, rng, lp, hp, bp, eq, resonators, osc_saw, make_ir, convolve, echo, master, sat,
                      write_ogg, report, t60env, adsr, pan2, stage)

AMB_LUFS = -15.0


def smooth_random(n, dur, seed, kmax=9, slope=1.0):
    """Curva lenta aleatoria y PERIÓDICA (suma de senos de período dur/k), normalizada a 0..1."""
    r = rng(seed)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for k in range(1, kmax + 1):
        y += r.normal(0, 1) / k ** slope * np.sin(2 * np.pi * k * t / dur + r.uniform(0, 6.283))
    y -= y.min()
    return y / (y.max() + 1e-12)


def shift(x, s):
    """Desplaza una curva periódica s segundos (circular)."""
    return np.roll(x, int(s * SR))


# ================================================================================================ amb_wind
def amb_wind(out_dir=None):
    dur = 24.0
    n = int(round(dur * SR))
    r = rng(500)
    g0 = smooth_random(n, dur, 501, kmax=10, slope=0.9)          # la ráfaga
    gL, gR = g0, shift(g0, 0.45)                                  # llega antes a la izquierda
    body, rum, sand = (np.zeros((n, 2)) for _ in range(3))
    centers = [170, 320, 560, 1000, 1750, 3100]
    base = [0.55, 0.75, 0.85, 0.75, 0.5, 0.28]
    sens = [0.6, 0.9, 1.3, 1.8, 2.4, 3.0]                         # las bandas altas dependen más de la ráfaga
    for ch, g in ((0, gL), (1, gR)):
        nz = r.normal(0, 1, n)
        for c, b, s in zip(centers, base, sens):
            band = bp(nz, c / 1.45, c * 1.45, 2, circular=True)
            body[:, ch] += band * b * (0.12 + g) ** s
        rum[:, ch] = lp(r.normal(0, 1, n), 110, 2, circular=True) * (0.25 + 0.75 * g)
        # arena: siseo agudo y granos sueltos cuando sopla fuerte
        sand[:, ch] = hp(r.normal(0, 1, n), 4200, 2, circular=True) * g ** 2.2
        k = int(dur * 90)
        pos = r.integers(0, n, k)
        keep = r.random(k) < g[pos] ** 2
        grains = np.zeros(n)
        grains[pos[keep]] = r.uniform(-1, 1, keep.sum())
        sand[:, ch] += bp(grains, 2500, 8000, 2, circular=True) * 3.0
    # silbidos: resonancias estrechas de ruido que aparecen en las ráfagas fuertes
    W = Pista(dur)
    nzw = r.normal(0, 1, n)
    for f, thr, pn, g in ((610, 0.62, -0.4, 1.0), (905, 0.72, 0.5, 0.7), (1340, 0.82, 0.1, 0.4)):
        tone = resonators(nzw, [(f, 45.0, 1.0)], circular=True)
        w = np.clip((g0 - thr) / (1 - thr), 0, 1) ** 2
        W.add(tone * w * g, 0.0, 1.0, pn)
    b = stage(dict(body=body, rumble=rum, sand=sand, whistle=W.buf),
              dict(body=0.0, rumble=-9.0, sand=-14.0, whistle=-15.0), ref_db=-22.0)
    out = sum(b.values())
    out = eq(out, 'high', 6000, -3.0, circular=True)
    out = lp(out, 9000, 2, circular=True)
    y = master(out, lufs_target=AMB_LUFS, ceiling_db=-2.0, circular=True, hp_hz=40.0)
    print(report('amb_wind', y))
    return write_ogg('amb_wind', y, q=4, out_dir=out_dir)


# ================================================================================================ amb_port
def ship_idle(dur, f0, seed):
    """Nave al ralentí, lejos: zumbido con armónicos y una turbina aguda muy filtrada; respira despacio."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    wob = 1 + 0.004 * np.sin(2 * np.pi * (2 / dur) * t + r.uniform(0, 6)) + 0.002 * np.sin(2 * np.pi * (5 / dur) * t)
    ph = 2 * np.pi * np.cumsum(f0 * wob) / SR
    hum = sum(np.sin(k * ph + r.uniform(0, 6)) / k for k in range(1, 7))
    turb = np.sin(2 * np.pi * np.cumsum(f0 * 23.7 * wob) / SR) * 0.08
    rum = lp(r.normal(0, 1, n), 140, 2, circular=True) * 2.5
    y = lp(hum * 0.6 + turb + rum, 700, 2, circular=True)
    return y


def ship_pass(dur, f0, seed):
    """Una nave que pasa a lo lejos: sube, cruza (el tono baja un poco: Doppler) y se va."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    dop = 1 + 0.05 * np.tanh((0.5 - u) * 6)
    ph = 2 * np.pi * np.cumsum(f0 * dop) / SR
    tone = sum(np.sin(k * ph + r.uniform(0, 6)) / k ** 0.9 for k in range(1, 10))
    nz = r.normal(0, 1, n)
    air = np.zeros(n)
    blk = 4096
    for i in range(0, n, blk):
        uc = (i + blk / 2) / n
        fc = 300 + 1600 * np.exp(-((uc - 0.5) / 0.22) ** 2)
        seg = bp(nz[max(0, i - 4096):i + blk], fc * 0.6, fc * 1.7)
        air[i:i + blk] = seg[-len(nz[i:i + blk]):]
    env = np.exp(-((u - 0.5) / 0.2) ** 2)
    env *= np.clip(u / 0.15, 0, 1) * np.clip((1 - u) / 0.15, 0, 1)
    y = lp(tone * 0.5, 900, 2) + air * 0.8
    return y * env


def murmur(n, dur, seed, voices=14):
    """Gente charlando lejos: voces de ruido con formantes y sílabas, frases y silencios (sin palabras)."""
    r = rng(seed)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for v in range(voices):
        f0 = r.uniform(110, 240)
        ph = 2 * np.pi * np.cumsum(f0 * (1 + 0.06 * np.sin(2 * np.pi * r.uniform(0.6, 1.4) * t))) / SR
        src = sum(np.sin(k * ph) / k for k in range(1, 12)) * 0.6 + r.normal(0, 1, n) * 0.25
        fa, fb = r.uniform(450, 800), r.uniform(1100, 2100)
        voice = resonators(src, [(fa, 3.0, 1.0), (fb, 4.0, 0.6)], circular=True)
        rate = r.uniform(3.6, 5.6)
        syl = (0.5 + 0.5 * np.sin(2 * np.pi * rate * t + r.uniform(0, 6))) ** 2
        phr = np.zeros(n)
        tt = r.uniform(0, dur)
        total = 0.0
        while total < dur:
            L = r.uniform(0.9, 2.8)
            seg = adsr(int(L * SR), 0.12, 0.1, 1.0, 0.25)
            i0 = int(tt * SR) % n
            idx = (np.arange(len(seg)) + i0) % n
            phr[idx] = np.maximum(phr[idx], seg)
            gap = r.uniform(0.8, 4.5)
            tt += L + gap
            total += L + gap
        g = r.uniform(0.25, 0.6)
        pan = r.uniform(-0.85, 0.85)
        out += pan2(voice * syl * phr * g, pan)
    return out


def pa_babble(seed, syllables=14):
    """Altavoz lejano: una voz de pulsos con vocales que cambian (sin palabras), por una bocina barata."""
    r = rng(seed)
    vowels = [(730, 1100), (530, 1850), (300, 2200), (520, 920), (360, 820), (650, 1700)]
    pieces = []
    f0 = 165.0
    for k in range(syllables):
        L = r.uniform(0.13, 0.27) if k % 5 != 4 else r.uniform(0.32, 0.45)
        n = int(L * SR)
        t = np.arange(n) / SR
        fk = f0 * (1 - 0.15 * k / syllables) * (1 + 0.05 * np.sin(np.pi * t / L))
        src = osc_saw(fk, n)
        F1, F2 = vowels[int(r.integers(0, len(vowels)))]
        v = resonators(src, [(F1, 5.0, 1.0), (F2, 7.0, 0.7), (2600, 8.0, 0.3)])
        env = np.sin(np.pi * np.clip(t / L, 0, 1)) ** 0.7
        cons = bp(r.normal(0, 1, n), 2000, 6000) * np.exp(-t / 0.02) * 0.4 if r.random() < 0.6 else 0
        pieces.append((v + cons) * env)
        if k % 5 == 4:
            pieces.append(np.zeros(int(r.uniform(0.18, 0.3) * SR)))
    y = np.concatenate(pieces)
    y = bp(y, 450, 3400, 2)
    y = sat(y * 2.5, 1.0) * 0.5
    y = lp(y, 2600, 2)
    return y


def clank(seed, f=None):
    """Golpe de metal lejano (una placa, una llave que cae)."""
    r = rng(seed)
    f = f or r.uniform(300, 700)
    dur = 1.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for ratio, a, d in ((1.0, 1.0, 0.5), (2.32, 0.6, 0.35), (3.71, 0.4, 0.2), (5.1, 0.25, 0.12)):
        y += a * np.sin(2 * np.pi * f * ratio * t + r.uniform(0, 6)) * t60env(t, d)
    y += bp(r.normal(0, 1, n), 1500, 6000) * t60env(t, 0.03) * 0.8
    return lp(y, 3000, 2)


def hiss(seed, dur=1.6):
    """Soplido hidráulico (válvula que suelta presión), lejano."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = bp(r.normal(0, 1, n), 1800, 6500, 2)
    env = np.minimum(1, t / 0.03) * np.exp(-t / (dur * 0.35))
    return lp(y * env, 4000, 2)


def amb_port(out_dir=None):
    dur = 36.0
    idle, passes, chat, pa_b, metal = (Pista(dur) for _ in range(5))
    n = idle.n
    r = rng(600)
    # naves al ralentí (todo el loop, periódicas): un colchón grave muy bajo
    for f0, pan, g, sd in ((52.0, -0.5, 1.0, 601), (78.0, 0.6, 0.7, 602)):
        hum = ship_idle(dur, f0, sd)
        breath = 0.6 + 0.4 * smooth_random(n, dur, sd + 10, kmax=4)
        idle.add(hum * breath, 0.0, g, pan)
    # dos naves que pasan
    passes.add(ship_pass(9.0, 72.0, 611), 3.0, 1.0, -0.3)
    passes.add(ship_pass(11.0, 58.0, 612), 20.5, 0.8, 0.4)
    # gente: lo principal del ambiente
    chat.buf += murmur(n, dur, 620, voices=18)
    # altavoz lejano (una vez por vuelta), con su eco de plaza
    pa = pa_babble(630)
    pa = echo(pa, 0.24, fb=0.45, repeats=4, lp_hz=1800, pingpong=False)
    pa_b.add(pa, 13.0, 1.0, 0.25)
    # metal y vapor
    for t0, sd, g, pn in ((6.4, 641, 1.0, 0.7), (17.9, 642, 0.75, -0.6), (29.3, 643, 0.85, 0.2)):
        metal.add(clank(sd), t0, g, pn)
    for t0, sd, g, pn in ((10.2, 651, 0.9, -0.7), (25.6, 652, 0.75, 0.6)):
        metal.add(hiss(sd), t0, g, pn)
    air = bp(r.normal(0, 1, (n, 2)), 200, 1200, 2, circular=True)
    b = stage(dict(chat=chat.buf, idle=idle.buf, passes=passes.buf, pa=pa_b.buf, metal=metal.buf, air=air),
              dict(chat=0.0, idle=-16.0, passes=-3.0, pa=-6.0, metal=-5.0, air=-20.0), ref_db=-24.0)
    dry = sum(b.values())
    # distancia: sala abierta grande y oscura
    far = make_ir(2.2, predelay=0.05, hf=0.22, lf=1.1, seed=660, early=0.1)
    wet = convolve(dry, far, circular=True)
    y = dry * 0.6 + wet * 0.55
    y = lp(y, 5000, 2, circular=True)
    y = master(y, lufs_target=AMB_LUFS, ceiling_db=-2.0, circular=True, hp_hz=35.0)
    print(report('amb_port', y))
    return write_ogg('amb_port', y, q=4, out_dir=out_dir)


if __name__ == '__main__':
    args = sys.argv[1:]
    out_dir = None
    if '--out' in args:
        i = args.index('--out')
        out_dir = args[i + 1]
        del args[i:i + 2]
    for w in (args or ['wind', 'port']):
        print(globals()[f'amb_{w}'](out_dir))
