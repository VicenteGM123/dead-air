"""Mira los .ogg en una imagen: espectrograma (frecuencia logarítmica) con el nivel RMS cada 50 ms encima; con --seam
añade a la derecha la costura del loop (los últimos 1.5 s seguidos de los primeros 1.5 s, línea roja = vuelta).
Uso:  python3 ver.py salida.png a.ogg b.ogg ... [--seam] [--fmax 16000]
"""
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from scipy.signal import stft
from levels import decode, SR


def spec_img(ax, x, t0=0.0, fmax=16000, title=None, seam_at=None):
    m = x.mean(axis=1)
    f, t, Z = stft(m, fs=SR, nperseg=2048, noverlap=1536)
    S = 20 * np.log10(np.abs(Z) * 4 + 1e-9)
    keep = (f >= 30) & (f <= fmax)
    ax.pcolormesh(t + t0, f[keep], S[keep], shading='auto', cmap='magma', vmin=-110, vmax=-20)
    ax.set_yscale('log')
    ax.set_ylim(30, fmax)
    ax.set_yticks([50, 100, 200, 500, 1000, 2000, 5000, 10000])
    ax.set_yticklabels(['50', '100', '200', '500', '1k', '2k', '5k', '10k'], fontsize=7)
    ax.tick_params(axis='x', labelsize=7)
    # nivel RMS (50 ms) en dB sobre un segundo eje
    w = int(0.05 * SR)
    k = len(m) // w
    if k > 0:
        r = np.sqrt(np.mean(x[:k * w].reshape(k, w, 2) ** 2, axis=(1, 2)))
        ax2 = ax.twinx()
        ax2.plot(t0 + (np.arange(k) + 0.5) * w / SR, 20 * np.log10(r + 1e-9), color='cyan', lw=0.8)
        ax2.set_ylim(-60, 0)
        ax2.tick_params(axis='y', labelsize=7, colors='cyan')
    if seam_at is not None:
        ax.axvline(seam_at, color='red', lw=1.2)
    if title:
        ax.set_title(title, fontsize=9, loc='left')


def main():
    args = [a for a in sys.argv[1:]]
    seam = '--seam' in args
    fmax = 16000
    if '--fmax' in args:
        i = args.index('--fmax')
        fmax = float(args[i + 1])
        del args[i:i + 2]
    args = [a for a in args if a != '--seam']
    out, files = args[0], args[1:]
    rows = len(files)
    cols = 2 if seam else 1
    fig, axes = plt.subplots(rows, cols, figsize=(16 if seam else 13, 2.3 * rows + 0.4), squeeze=False,
                             gridspec_kw={'width_ratios': [4, 1.3] if seam else [1]})
    for i, p in enumerate(files):
        x = decode(p)
        rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
        pk = 20 * np.log10(np.abs(x).max() + 1e-12)
        name = p.split('/')[-1]
        spec_img(axes[i, 0], x, fmax=fmax, title=f'{name}  {len(x) / SR:.2f} s  RMS {rms:.1f}  peak {pk:.1f} dBFS')
        if seam:
            h = int(1.5 * SR)
            j = np.concatenate([x[-h:], x[:h]])
            spec_img(axes[i, 1], j, t0=-1.5, fmax=fmax, title='seam (end -> start)', seam_at=0.0)
    fig.tight_layout()
    fig.savefig(out, dpi=72)
    print('ok', out)


if __name__ == '__main__':
    main()
