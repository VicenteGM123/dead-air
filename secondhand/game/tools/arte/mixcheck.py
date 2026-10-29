"""Comprueba la mezcla: espectro medio a largo plazo (tercios de octava, dB relativos a la sonoridad) de un .ogg
frente a una referencia (por defecto la música de la tienda de Midnight Cauldron), y un espectrograma ampliado.
Uso:  python3 mixcheck.py a.ogg [--ref ref.ogg] [--zoom t0 t1 salida.png]
"""
import sys
import numpy as np
from scipy.signal import welch
from levels import decode, SR

REF = '/home/user/dead-air/caldero/game/assets/audio/music_tienda.ogg'
BANDS = [40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000]


def ltas(x):
    m = x.mean(axis=1)
    f, P = welch(m, fs=SR, nperseg=8192)
    out = []
    for c in BANDS:
        lo, hi = c / 2 ** (1 / 3), c * 2 ** (1 / 3)      # banda de 2/3 de octava centrada (más estable)
        k = (f >= lo) & (f < hi)
        out.append(10 * np.log10(np.sum(P[k]) + 1e-20))
    out = np.array(out)
    return out - 10 * np.log10(np.sum(10 ** (out / 10)))   # relativo al total


def main():
    a = sys.argv[1:]
    ref = REF
    if '--ref' in a:
        i = a.index('--ref')
        ref = a[i + 1]
        del a[i:i + 2]
    zoom = None
    if '--zoom' in a:
        i = a.index('--zoom')
        zoom = (float(a[i + 1]), float(a[i + 2]), a[i + 3])
        del a[i:i + 4]
    x = decode(a[0])
    r = decode(ref)
    la, lr = ltas(x), ltas(r)
    print('band Hz   ' + ' '.join(f'{b:>6}' for b in BANDS))
    print('this      ' + ' '.join(f'{v:6.1f}' for v in la))
    print('ref       ' + ' '.join(f'{v:6.1f}' for v in lr))
    print('diff      ' + ' '.join(f'{v:+6.1f}' for v in la - lr))
    if zoom:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        from ver import spec_img
        t0, t1, out = zoom
        seg = x[int(t0 * SR):int(t1 * SR)]
        fig, ax = plt.subplots(1, 1, figsize=(16, 5))
        spec_img(ax, seg, t0=t0, fmax=12000, title=f'{a[0].split("/")[-1]} {t0}-{t1} s')
        fig.tight_layout()
        fig.savefig(out, dpi=80)
        print('zoom', out)


if __name__ == '__main__':
    main()
