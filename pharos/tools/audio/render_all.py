#!/usr/bin/env python3
"""Regenera TODO el audio de PHAROS de forma procedural y determinista.

Uso (desde la raíz del repositorio):
    python3 pharos/tools/audio/render_all.py                # todo
    python3 pharos/tools/audio/render_all.py --only coin day # solo algunos (por nombre)
    python3 pharos/tools/audio/render_all.py --png /tmp/png  # + espectrogramas de control
    python3 pharos/tools/audio/render_all.py --list          # lista de ficheros

Requisitos: Python 3.10+, numpy, ffmpeg con libvorbis.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np

sys.dont_write_bytecode = True  # no dejar __pycache__ dentro del repositorio
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from dsp import SR  # noqa: E402

PHAROS = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_ROOT = os.path.join(PHAROS, "game", "assets", "audio")
QUALITY = 5


def _jobs():
    import ambience
    import music
    import sfx
    jobs = []
    for name in sfx.SFX:
        jobs.append(("sfx", name, name in sfx.LOOPING_SFX))
    for name in music.MUSIC:
        jobs.append(("music", name, name in music.LOOPS))
    for name in ambience.AMB:
        jobs.append(("amb", name, True))
    return jobs


def _render(category: str, name: str) -> np.ndarray:
    if category == "sfx":
        import sfx
        return sfx.SFX[name]()
    if category == "music":
        import music
        return music.MUSIC[name]()
    import ambience
    return ambience.AMB[name]()


def encode_ogg(x: np.ndarray, path: str, quality: int = QUALITY) -> None:
    x = np.ascontiguousarray(np.clip(np.asarray(x, dtype=np.float64), -1.0, 1.0).astype(np.float32))
    ch = 1 if x.ndim == 1 else x.shape[1]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "pipe:0",
           "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
           "-c:a", "libvorbis", "-q:a", str(quality), path]
    subprocess.run(cmd, input=x.tobytes(), check=True)


def write_wav(x: np.ndarray, path: str) -> None:
    import wave
    x = np.clip(np.asarray(x), -1, 1)
    ch = 1 if x.ndim == 1 else x.shape[1]
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def run_job(args):
    category, name, loop, png_dir, wav_dir = args
    from analyze import fmt_stats, render_png, stats
    t0 = time.time()
    x = _render(category, name)
    if not np.all(np.isfinite(x)):
        raise RuntimeError(f"{name}: valores no finitos")
    path = os.path.join(OUT_ROOT, category, f"{name}.ogg")
    encode_ogg(x, path)
    st = stats(x, loop=loop)
    label = f"{category}/{name}.ogg"
    if png_dir:
        render_png(x, os.path.join(png_dir, f"{category}_{name}.png"), label + "  " + fmt_stats("", st))
    if wav_dir:
        os.makedirs(wav_dir, exist_ok=True)
        write_wav(x, os.path.join(wav_dir, f"{category}_{name}.wav"))
    return label, st, os.path.getsize(path), time.time() - t0, x.ndim


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*", help="nombres a regenerar (p. ej. coin day sea)")
    ap.add_argument("--png", help="directorio para espectrogramas PNG de control")
    ap.add_argument("--wav", help="directorio para copias WAV (depuración)")
    ap.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    jobs = _jobs()
    if a.list:
        for c, nme, lp in jobs:
            print(f"{c}/{nme}.ogg{'  (bucle)' if lp else ''}")
        return 0
    if a.only:
        wanted = set(a.only)
        jobs = [j for j in jobs if j[1] in wanted or f"{j[0]}/{j[1]}" in wanted]
        if not jobs:
            print("Nada que hacer: nombres desconocidos", file=sys.stderr)
            return 1
    t0 = time.time()
    work = [(c, nme, lp, a.png, a.wav) for c, nme, lp in jobs]
    # primero los trabajos largos (música) para repartir mejor la carga
    work.sort(key=lambda w: {"music": 0, "amb": 1, "sfx": 2}[w[0]])
    results = []
    if a.jobs > 1 and len(work) > 1:
        with ProcessPoolExecutor(max_workers=a.jobs) as ex:
            for res in ex.map(run_job, work):
                results.append(res)
                print(f"  ok  {res[0]:<32} {res[3]:5.1f}s", flush=True)
    else:
        for w in work:
            res = run_job(w)
            results.append(res)
            print(f"  ok  {res[0]:<32} {res[3]:5.1f}s", flush=True)
    from analyze import fmt_stats
    print()
    total = 0
    for label, st, size, dt, nd in sorted(results):
        total += size
        print(f"{fmt_stats(label, st)}  {'st' if nd == 2 else 'mo'}  {size / 1024:7.1f} KB")
    print(f"\n{len(results)} ficheros, {total / 1024 / 1024:.2f} MB en total, {time.time() - t0:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
