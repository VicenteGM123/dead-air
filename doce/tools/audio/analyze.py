"""Análisis de control de calidad: estadísticas numéricas y espectrogramas PNG (PIL).

Uso independiente:  python3 analyze.py fichero.ogg [...] --png DIR
(decodifica con ffmpeg). render_all.py lo usa con --png para revisar cada sonido.
"""
from __future__ import annotations

import os
import subprocess
import sys

import numpy as np

from dsp import SR, todb


def stats(x: np.ndarray, loop: bool = False) -> dict:
    x = np.asarray(x, dtype=np.float64)
    mono = x if x.ndim == 1 else x.mean(axis=1)
    n = len(mono)
    out = {
        "dur": n / SR,
        "peak_db": float(todb(np.max(np.abs(x)))),
        "rms_db": float(todb(np.sqrt(np.mean(x ** 2)))),
        "dc": float(np.max(np.abs(np.mean(x, axis=0)))),
    }
    # reparto espectral (energía por encima de 8 kHz y de 4 kHz, centroide)
    N = 1 << int(np.ceil(np.log2(max(n, 2))))
    X = np.abs(np.fft.rfft(mono, N)) ** 2
    f = np.fft.rfftfreq(N, 1.0 / SR)
    tot = X.sum() + 1e-20
    out["hf8_db"] = float(10 * np.log10(X[f > 8000].sum() / tot + 1e-20))
    out["hf4_db"] = float(10 * np.log10(X[f > 4000].sum() / tot + 1e-20))
    out["centroid"] = float((f * X).sum() / tot)
    # actividad (RMS de la parte con señal, ventanas de 50 ms por encima de -50 dB del pico)
    w = int(0.05 * SR)
    if n >= w:
        pw = x ** 2 if x.ndim == 1 else np.mean(x ** 2, axis=1)
        r = np.sqrt(np.mean(pw[: n // w * w].reshape(-1, w), axis=1))
        act = r[r > np.max(r) * 10 ** (-40 / 20)]
        out["active_rms_db"] = float(todb(np.sqrt(np.mean(act ** 2)))) if len(act) else -120.0
    else:
        out["active_rms_db"] = out["rms_db"]
    d = np.abs(np.diff(x, axis=0))
    typical = float(np.median(d) + 1e-9)
    out["max_step"] = float(np.max(d))
    out["edge_start"] = float(np.max(np.abs(x[:1])))
    out["edge_end"] = float(np.max(np.abs(x[-1:])))
    if loop:
        jump = np.abs(x[0] - x[-1])
        out["loop_jump"] = float(np.max(jump))
        out["loop_jump_rel"] = float(np.max(jump) / (np.percentile(d, 99) + 1e-12))
    return out


def fmt_stats(name: str, s: dict) -> str:
    txt = (f"{name:<28} {s['dur']:6.2f}s  peak {s['peak_db']:6.1f}  rms {s['rms_db']:6.1f}"
           f"  act {s['active_rms_db']:6.1f}  >4k {s['hf4_db']:6.1f}  >8k {s['hf8_db']:6.1f}"
           f"  cen {s['centroid']:6.0f}  dc {s['dc']:.1e}")
    if "loop_jump_rel" in s:
        txt += f"  loopjump {s['loop_jump_rel']:.2f}"
    return txt


# ---------------------------------------------------------------------------
# PNG
# ---------------------------------------------------------------------------

_ANCHORS = np.array([
    [0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99],
    [212, 72, 66], [245, 125, 21], [250, 193, 39], [252, 255, 164],
], dtype=np.float64)


def _cmap(v: np.ndarray) -> np.ndarray:
    v = np.clip(v, 0, 1) * (len(_ANCHORS) - 1)
    i = np.minimum(v.astype(int), len(_ANCHORS) - 2)
    fr = (v - i)[..., None]
    return (_ANCHORS[i] * (1 - fr) + _ANCHORS[i + 1] * fr).astype(np.uint8)


def render_png(x: np.ndarray, path: str, title: str = "", width: int = 1200,
               fmin: float = 30.0, fmax: float = 20000.0) -> None:
    from PIL import Image, ImageDraw

    x = np.asarray(x, dtype=np.float64)
    chans = [x] if x.ndim == 1 else [x[:, 0], x[:, 1]]
    mono = x if x.ndim == 1 else x.mean(axis=1)
    n = len(mono)
    wave_h, spec_h, spec2_h, top = 140, 360, 150, 22
    H = top + wave_h + spec_h + spec2_h + 10
    img = Image.new("RGB", (width, H), (18, 18, 24))
    dr = ImageDraw.Draw(img)
    dr.text((6, 4), title, fill=(230, 230, 230))
    # forma de onda (min/max por columna)
    per = max(n // width, 1)
    for ci, ch in enumerate(chans):
        hh = wave_h // len(chans)
        y0 = top + ci * hh
        mid = y0 + hh // 2
        m = ch[: per * (n // per)].reshape(-1, per) if n >= per else ch[None, :]
        mx, mn = m.max(axis=1), m.min(axis=1)
        cols = np.linspace(0, len(mx) - 1, width).astype(int)
        for xp in range(width):
            a, b = mx[cols[xp]], mn[cols[xp]]
            dr.line([(xp, mid - a * hh / 2), (xp, mid - b * hh / 2)], fill=(120, 200, 255))
        dr.line([(0, mid), (width, mid)], fill=(60, 60, 70))
        for lvl in (0.5, -0.5):
            yy = mid - lvl * hh / 2
            dr.line([(0, yy), (6, yy)], fill=(200, 80, 80))
    # espectrograma (eje de frecuencia logarítmico)
    nfft = 2048 if n > SR * 3 else 1024 if n > SR * 0.5 else 512
    hop = max(n // width, 32)
    win = np.hanning(nfft)
    padded = np.concatenate([np.zeros(nfft // 2), mono, np.zeros(nfft)])
    nfr = max((len(padded) - nfft) // hop, 1)
    idx = np.arange(nfft)[None, :] + hop * np.arange(nfr)[:, None]
    S = np.abs(np.fft.rfft(padded[idx] * win, axis=1))
    Sdb = 20 * np.log10(S + 1e-9)
    Sdb -= Sdb.max()
    freqs = np.fft.rfftfreq(nfft, 1.0 / SR)
    rows = fmin * (fmax / fmin) ** (np.arange(spec_h)[::-1] / (spec_h - 1))
    bins = np.clip(np.searchsorted(freqs, rows), 0, len(freqs) - 1)
    cols = np.linspace(0, nfr - 1, width).astype(int)
    M = Sdb[cols][:, bins].T  # (spec_h, width)
    rgb = _cmap((M + 90.0) / 90.0)
    y_spec = top + wave_h
    img.paste(Image.fromarray(rgb), (0, y_spec))
    for fl, col in ((100, (90, 90, 90)), (1000, (90, 90, 90)), (4000, (120, 120, 60)), (8000, (255, 90, 90))):
        yy = y_spec + (spec_h - 1) * (1 - np.log(fl / fmin) / np.log(fmax / fmin))
        dr.line([(0, yy), (width, yy)], fill=col)
        dr.text((4, yy - 11), f"{fl}", fill=col)
    # espectro medio (dB vs log f)
    y2 = y_spec + spec_h + 5
    avg = 10 * np.log10(np.mean(S ** 2, axis=0) + 1e-18)
    avg -= avg.max()
    xs = np.log(np.maximum(freqs[1:], 1) / fmin) / np.log(fmax / fmin) * width
    ys = y2 + (-np.clip(avg[1:], -90, 0) / 90.0) * spec2_h
    pts = [(float(a), float(b)) for a, b in zip(xs, ys) if 0 <= a <= width]
    if len(pts) > 1:
        dr.line(pts, fill=(140, 230, 140))
    for fl in (100, 1000, 4000, 8000):
        xx = np.log(fl / fmin) / np.log(fmax / fmin) * width
        dr.line([(xx, y2), (xx, y2 + spec2_h)], fill=(255, 90, 90) if fl == 8000 else (80, 80, 80))
    for dbl in (-30, -60):
        yy = y2 + (-dbl / 90.0) * spec2_h
        dr.line([(0, yy), (width, yy)], fill=(60, 60, 60))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    img.save(path)


def decode(path: str) -> np.ndarray:
    """Decodifica cualquier fichero de audio con ffmpeg a float64 (n, canales)."""
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                            "stream=channels", "-of", "csv=p=0", path], capture_output=True, text=True)
    ch = int(probe.stdout.strip() or 1)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-ar",
                          str(SR), "pipe:1"], capture_output=True, check=True).stdout
    a = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return a if ch == 1 else a.reshape(-1, ch)


if __name__ == "__main__":
    args = sys.argv[1:]
    outdir = None
    if "--png" in args:
        i = args.index("--png")
        outdir = args[i + 1]
        args = args[:i] + args[i + 2:]
    for p in args:
        a = decode(p)
        s = stats(a, loop=True)
        print(fmt_stats(os.path.basename(p), s))
        if outdir:
            render_png(a, os.path.join(outdir, os.path.basename(p) + ".png"), os.path.basename(p))
