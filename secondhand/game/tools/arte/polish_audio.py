"""Secondhand Stars · ronda de pulido (--- POLISH FIX F9): los efectos que faltaban. Originales, sintetizados, como el
resto (ss_audio / sfx_audio): niveles parecidos a los efectos chicos que ya hay.
  sfx_step1..3  los pasos de Nell: un golpecito blando (arena apisonada / tablón) con un poco de grano; muy cortos
                (0.08-0.15 s) y suaves; tres variantes para que no suenen a máquina
  sfx_squeak    el mástil de Dolly que levanta una mejora: un crujido corto de madera y metal (~0.3 s)
Uso:  python3 polish_audio.py [nombre ...] [--out carpeta]     (o make_audio.py --set=polish)
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from ss_audio import SR, rng, lp, hp, bp, t60env, fade
from sfx_audio import buf, put, finish


def _step(seed, f_body, grain, dur):
    """Un paso: el golpe grave del talón (seno que cae de tono) + el roce de la arena (ruido de banda, corto)."""
    r = rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f_body * (1.0 + 0.6 * np.exp(-t / 0.008))                    # cae de tono en los primeros ms
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * t60env(t, 0.045) * 0.9
    knock = bp(r.normal(0, 1, n), 380, 1400) * t60env(t, 0.018) * 0.55
    sand = bp(r.normal(0, 1, n), 1600, 5200) * t60env(t, 0.03 + 0.02 * r.uniform()) * grain
    # un segundo grano, un pelín después (la punta del pie)
    sand2 = np.zeros(n)
    k = int(r.uniform(0.018, 0.03) * SR)
    m = n - k
    sand2[k:] = bp(r.normal(0, 1, m), 1800, 6000) * t60env(np.arange(m) / SR, 0.02) * grain * 0.5
    x = body + knock + sand + sand2
    return fade(lp(x, 7000), 0.0008, 0.02)


def sfx_step(i, out_dir=None):
    spec = {1: (701, 118.0, 0.30, 0.11), 2: (702, 132.0, 0.36, 0.10), 3: (703, 109.0, 0.26, 0.12)}[i]
    out = buf(spec[3] + 0.03)
    put(out, _step(spec[0], spec[1], spec[2], spec[3]), 0.0)
    return finish('sfx_step%d' % i, out, -22.5, out_dir=out_dir, room=0.0, trim_db=-60.0)


def sfx_step1(out_dir=None):
    return sfx_step(1, out_dir)


def sfx_step2(out_dir=None):
    return sfx_step(2, out_dir)


def sfx_step3(out_dir=None):
    return sfx_step(3, out_dir)


def sfx_squeak(out_dir=None):
    """Un crujido de mástil: fricción a saltitos (stick-slip) que sube de tono y se apaga, con cuerpo de madera."""
    r = rng(811)
    dur = 0.34
    out = buf(dur + 0.08)
    n = int(dur * SR)
    t = np.arange(n) / SR
    # la frecuencia del roce sube y tiembla (la fricción no es pareja)
    f = 520.0 + 380.0 * (t / dur) ** 0.7 + 40.0 * np.sin(2 * np.pi * 23.0 * t) + r.normal(0, 12.0, n).cumsum() * 0.002
    ph = 2 * np.pi * np.cumsum(f) / SR
    # pulsos (stick-slip): una diente de sierra recortada suena a crujido, no a silbido
    saw = 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    pulses = np.tanh(3.0 * saw)
    env = np.minimum(1.0, t / 0.03) * np.exp(-((t - 0.16) / 0.16) ** 2) * (0.75 + 0.25 * np.sin(2 * np.pi * 9.0 * t))
    sq = bp(pulses, 700, 3200) * env
    # el cuerpo de madera (dos resonancias graves) y un 'toc' de metal al final
    wood = bp(r.normal(0, 1, n), 180, 520) * env * 0.35
    put(out, sq + wood, 0.0)
    m = int(0.05 * SR)
    tm = np.arange(m) / SR
    tick = (np.sin(2 * np.pi * 1900 * tm) * 0.4 + bp(r.normal(0, 1, m), 2500, 8000)) * t60env(tm, 0.012) * 0.35
    put(out, tick, dur - 0.04)
    return finish('sfx_squeak', out, -20.5, out_dir=out_dir, room=0.12, trim_db=-60.0)


ALL = ['sfx_step1', 'sfx_step2', 'sfx_step3', 'sfx_squeak']


def build(names=None, out_dir=None):
    return [globals()[nm](out_dir) for nm in (names or ALL)]


if __name__ == '__main__':
    args = sys.argv[1:]
    out_dir = None
    if '--out' in args:
        out_dir = args[args.index('--out') + 1]
        args = [a for a in args if a not in ('--out', out_dir)]
    build([a for a in args if not a.startswith('-')] or None, out_dir)
