"""Música de PHAROS: composición escrita como datos (acordes, arpegios, melodías) + mezcla.

Pistas en bucle (render circular: lo que suena tras el final del bucle se pliega sobre el
principio y la reverb es convolución circular, así que el bucle es perfecto, sin clic):
  * day    – Re dórico, 84 BPM, 4/4, 24 compases. Lira arpegiada, pad de cuerdas/coro,
             latido de pandero suave, bajo de lira; melodía de lira en la sección B.
  * night  – Re frigio, 100 BPM, 4/4, 24 compases. Tímpano 3+3+2, bordón grave, ostinato
             de lira apagada, pad oscuro, frases de aulós con respuesta de lira.
  * boss   – Re frigio, 110 BPM, 4/4, 22 compases (48 s). Tambores a semicorcheas, metales graves
             en swell, coro, ostinato, aulós agudo en la sección final.
  * title  – Re menor (eólico/dórico), 70 BPM, 3/4, 24 compases. Lira, coro y campana lejana.
Stingers (no bucle): stinger_dawn, stinger_victory, stinger_defeat.
"""
from __future__ import annotations

import itertools

import numpy as np

from dsp import (SR, add_at, convolve, fades, filt, limiter, make_ir, normalize_rms,
                 note, pan as pan_mono, ramp_up, rng_for, secs, todb, undb)
from instruments import (LYRE_BODY, aulos_phrase, bell, brass_note, cymbal_swell, drone,
                         frame_drum, lyre_pluck, pad_note)

# ---------------------------------------------------------------------------
# Utilidades de armonía
# ---------------------------------------------------------------------------


def pcs(names: str) -> list[int]:
    """'D F A E' -> clases de altura."""
    return [note(x + "4") % 12 for x in names.split()]


def voice_lead(prev, pc_list, nv: int, lo: int, hi: int):
    """Elige nv notas en [lo, hi] con las clases pc_list, moviéndose lo mínimo desde prev."""
    cands = [m for m in range(lo, hi + 1) if m % 12 in pc_list]
    need = min(nv, len(pc_list))
    best, best_cost = None, 1e18
    center = 0.5 * (lo + hi)
    for combo in itertools.combinations(cands, nv):
        got = {m % 12 for m in combo}
        if len(got) < need or pc_list[0] not in got:
            continue
        if combo[-1] - combo[0] > 17:
            continue
        gaps = np.diff(combo)
        cost = 6.0 * np.sum(gaps == 1) + 1.5 * np.sum(gaps == 2) * (nv > 3)
        if prev is not None:
            cost += sum(abs(a - b) for a, b in zip(combo, prev))
        else:
            cost += abs(np.mean(combo) - center)
        if cost < best_cost:
            best, best_cost = combo, cost
    if best is None:
        raise ValueError(f"sin voicing para {pc_list}")
    return list(best)


def active_rms_db(x: np.ndarray) -> float:
    m = x if x.ndim == 1 else np.sqrt(np.mean(x ** 2, axis=1))
    w = int(0.05 * SR)
    k = len(m) // w
    if k == 0:
        return float(todb(np.sqrt(np.mean(m ** 2))))
    r = np.sqrt(np.mean(m[: k * w].reshape(k, w) ** 2, axis=1))
    act = r[r > r.max() * undb(-30)]
    return float(todb(np.sqrt(np.mean(act ** 2)) + 1e-12))


# ---------------------------------------------------------------------------
# Motor de canción
# ---------------------------------------------------------------------------


class Song:
    def __init__(self, key: str, bpm: float, bpb: int, bars: int | None = None, length: float | None = None,
                 pre: float = 1.5, tail: float = 7.0):
        self.key = key
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.bpb = bpb
        self.loop = length is None
        self.L = int(round(bars * bpb * self.spb * SR)) if self.loop else secs(length)
        self.pre = secs(pre)
        self.n = self.pre + self.L + (secs(tail) if self.loop else secs(1.0))
        self.buses: dict[str, np.ndarray] = {}
        self.rng = rng_for("music", key)
        self._cache: dict = {}
        self._count = 0

    # tiempo ---------------------------------------------------------------
    def T(self, bar: float, beat: float = 0.0) -> float:
        return ((bar - 1) * self.bpb + beat) * self.spb

    def hum(self, t: float, sd: float = 0.006) -> float:
        return t + float(np.clip(self.rng.normal(0.0, sd), -2.5 * sd, 2.5 * sd))

    def hv(self, v: float, sd: float = 0.05) -> float:
        return float(np.clip(v * (1.0 + self.rng.normal(0.0, sd)), 0.05, 1.0))

    def sub_rng(self, *tag):
        self._count += 1
        return rng_for("music", self.key, self._count, *tag)

    # colocación -------------------------------------------------------------
    def add(self, bus: str, sig: np.ndarray, t: float, gain: float = 1.0, pan: float = 0.0) -> None:
        buf = self.buses.setdefault(bus, np.zeros((self.n, 2)))
        if sig.ndim == 1:
            sig = pan_mono(sig, pan)
        elif pan:
            g = np.array([np.sqrt(1 - max(pan, 0)), np.sqrt(1 + min(pan, 0))])
            sig = sig * g[None, :]
        add_at(buf, sig, self.pre + secs(t), gain)

    def lyre(self, bus: str, midi: int, t: float, vel: float, dur: float | None = None, pan: float | None = None,
             muted: bool = False, bright: float = 0.55, t60: float | None = None, release: float = 0.12) -> None:
        vb = 0 if vel < 0.6 else (1 if vel < 0.8 else 2)
        vref = (0.5, 0.7, 0.9)[vb]
        var = int(self.rng.integers(3))
        key = ("lyre", int(midi), muted, round(bright, 2), t60, vb, var)
        if key not in self._cache:
            self._cache[key] = lyre_pluck(midi, rng_for(self.key, *key), vel=vref, bright=bright, muted=muted,
                                          t60=t60)
        x = self._cache[key] * (vel / vref)
        if dur is not None:
            g0 = secs(dur)
            r = secs(release)
            if g0 + r < len(x):
                x = x[: g0 + r].copy()
                x[g0:] *= ramp_up(r)[::-1]
        if pan is None:
            pan = float(np.clip((midi - 62) / 30.0, -0.45, 0.45))
        self.add(bus, x, t, 1.0, pan)

    def drum(self, bus: str, kind: str, t: float, vel: float, pan: float = 0.0, size: float = 1.0) -> None:
        var = int(self.rng.integers(4))
        key = ("drum", kind, var, size)
        if key not in self._cache:
            self._cache[key] = frame_drum(kind, rng_for(self.key, *key), vel=1.0, size=size)
        x = self._cache[key]
        # la dinámica también oscurece el golpe (filtro de un polo sobre la copia)
        if vel < 0.6:
            x = filt(x, [("lp1", 1500 + 4000 * vel)])
        self.add(bus, x, t, vel, pan)

    def pad(self, bus: str, midi: int, t: float, dur: float, **kw) -> None:
        x = pad_note(midi, dur, self.sub_rng("pad", midi), **kw)
        self.add(bus, x, t, 1.0)

    def aulos(self, bus: str, phrase, gain: float = 1.0, pan: float = 0.08, **kw) -> None:
        """phrase = [(compás, tiempo, duración_en_tiempos, 'nota', vel, ligada), ...]"""
        ev = [(self.T(b, bt), d * self.spb, note(nm), v, lg) for b, bt, d, nm, v, lg in phrase]
        x, t0 = aulos_phrase(ev, self.sub_rng("aulos"), **kw)
        self.add(bus, x, t0, gain, pan)

    # mezcla -----------------------------------------------------------------
    def folded(self, name: str) -> np.ndarray:
        buf = self.buses[name]
        if not self.loop:
            return buf[self.pre:self.pre + self.L].copy()
        L, p = self.L, self.pre
        x = buf[p:p + L].copy()
        x[L - p:] += buf[:p]
        tail = buf[p + L:]
        k = min(len(tail), L)
        x[:k] += tail[:k]
        return x

    def mix(self, cfg: dict, ir: np.ndarray, rms_db: float = -20.0, ceiling_db: float = -1.0,
            fade_out: float = 0.0) -> np.ndarray:
        dry = np.zeros((self.L, 2))
        send = np.zeros((self.L, 2))
        for name in self.buses:
            c = cfg.get(name, {})
            x = self.folded(name)
            if c.get("eq"):
                x = filt(x, c["eq"], circular=self.loop)
            if "width" in c:
                m = 0.5 * (x[:, 0] + x[:, 1])
                s = 0.5 * (x[:, 0] - x[:, 1]) * c["width"]
                x = np.stack([m + s, m - s], axis=1)
            lvl = active_rms_db(x)
            x = x * undb(c.get("level", -24.0) - lvl)
            dry += x
            send += c.get("send", 0.2) * x
        wet = convolve(send, ir, circular=self.loop)[: self.L]
        out = dry + wet
        out = filt(out, [("hp", 30, 0.7071), ("hs", 9000, 0.7, -2.0)], circular=self.loop)
        if fade_out > 0:
            out = fades(out, 0.0, fade_out)
        out = normalize_rms(out, rms_db) if self.loop else out * undb(rms_db - active_rms_db(out))
        out = limiter(out, ceiling_db, circular=self.loop)
        if not self.loop:
            out = fades(out, 0.002, min(fade_out, 0.5) if fade_out else 0.05)
        return out


def ring_ends(events, change_times, chord_pcs, max_ring: float):
    """Duración natural de cada nota pulsada: hasta que se repite la cuerda o hasta el cambio de
    acorde si la nota no pertenece al siguiente acorde (el arpista apaga la cuerda)."""
    events = sorted(events, key=lambda e: e[0])
    out = []
    for i, (t, m, v) in enumerate(events):
        end = t + max_ring
        for t2, m2, _ in events[i + 1:]:
            if m2 == m:
                end = min(end, t2 + 0.01)
                break
        for tc, p in zip(change_times, chord_pcs):
            if tc > t + 0.05:
                if m % 12 not in p:
                    end = min(end, tc + 0.12)
                break
        out.append((t, m, v, max(end - t, 0.08)))
    return out


def chord_track(song: Song, bus: str, prog_pcs, starts, durs, nv: int, lo: int, hi: int, overlap: float = 0.25,
                gain: float = 1.0, first=None, **kw):
    """Pad con conducción de voces: notas comunes se sostienen sin reatacar."""
    voicings = []
    prev = first
    for p in prog_pcs:
        v = voice_lead(prev, p, nv, lo, hi)
        voicings.append(v)
        prev = v
    for vi in range(nv):
        i = 0
        while i < len(voicings):
            m = voicings[i][vi]
            j = i
            while j + 1 < len(voicings) and voicings[j + 1][vi] == m:
                j += 1
            st = starts[i]
            en = starts[j] + durs[j]
            x = pad_note(m, en - st + overlap, song.sub_rng("chord", bus, m), **kw)
            song.add(bus, x, st, gain)
            i = j + 1
    return voicings


# ---------------------------------------------------------------------------
# DÍA — Re dórico
# ---------------------------------------------------------------------------

DAY_CHORDS = {
    # nombre: (bajo, arpegio de 6 notas, clases del pad)
    "Dm9": ("D2", "D3 A3 D4 E4 F4 A4", "D F A E"),
    "G/D": ("D2", "D3 G3 B3 D4 G4 B4", "G B D"),
    "Fmaj7": ("F2", "F3 C4 E4 F4 A4 C5", "F A C E"),
    "C/E": ("E2", "E3 G3 C4 E4 G4 C5", "C E G"),
    "G": ("G2", "G3 B3 D4 G4 B4 D5", "G B D"),
    "Am7sus4": ("A2", "A3 D4 E4 G4 A4 D5", "A D E G"),
    "Am7": ("A2", "A3 C4 E4 G4 A4 C5", "A C E G"),
    "Asus4": ("A2", "A3 D4 E4 A4 D5 E5", "A D E"),
    "C": ("C3", "G3 C4 E4 G4 C5 E5", "C E G"),
    "G/B": ("B2", "G3 B3 D4 G4 B4 D5", "G B D"),
    "G6": ("G2", "G3 B3 D4 E4 G4 B4", "G B D E"),
}
DAY_PROG = ["Dm9", "G/D", "Dm9", "G/D", "Fmaj7", "C/E", "G", "Am7sus4",
            "Dm9", "G/D", "Dm9", "G/D", "Fmaj7", "G", "Am7", "Asus4",
            "C", "G/B", "Am7", "G", "Fmaj7", "C/E", "G6", "Asus4"]
DAY_MELODY = [  # (compás, tiempo, duración, nota)
    (17, 0, 1.5, "E5"), (17, 1.5, 0.5, "D5"), (17, 2, 1, "E5"), (17, 3, 1, "G5"),
    (18, 0, 3, "D5"), (18, 3, 1, "B4"),
    (19, 0, 1.5, "C5"), (19, 1.5, 0.5, "B4"), (19, 2, 1, "C5"), (19, 3, 1, "E5"),
    (20, 0, 2, "D5"), (20, 2, 1, "B4"), (20, 3, 1, "G4"),
    (21, 0, 1.5, "A4"), (21, 1.5, 0.5, "C5"), (21, 2, 1, "F5"), (21, 3, 1, "E5"),
    (22, 0, 2, "G5"), (22, 2, 1, "E5"), (22, 3, 1, "C5"),
    (23, 0, 1.5, "D5"), (23, 1.5, 0.5, "E5"), (23, 2, 1, "D5"), (23, 3, 1, "B4"),
    (24, 0, 3, "A4"),
]
# patrones de arpegio (índices en la voz de 6 notas; None = silencio)
PAT_A = [0, 2, 4, 5, 3, 4, 2, 1]
PAT_B = [0, 1, 3, 4, 5, 4, 3, 2]
PAT_C = [0, 2, 3, 5, 4, 3, 2, 3]
PAT_THIN = [0, None, 2, 3, None, 2, 1, None]


def day() -> np.ndarray:
    s = Song("day", 84, 4, bars=24)
    bars = len(DAY_PROG)
    change_times = [s.T(b + 1) for b in range(bars)] + [s.T(bars + 1)]
    chord_pcs = [pcs(DAY_CHORDS[c][2]) for c in DAY_PROG] + [pcs(DAY_CHORDS[DAY_PROG[0]][2])]
    # ---- arpegios de lira ----
    ev = []
    for b, name in enumerate(DAY_PROG, start=1):
        voicing = [note(x) for x in DAY_CHORDS[name][1].split()]
        if b <= 16:
            pat = PAT_A if b % 2 else PAT_B
            if b in (8, 16):
                pat = PAT_C
        else:
            pat = PAT_THIN
        for i, idx in enumerate(pat):
            if idx is None:
                continue
            accent = 0.86 if i == 0 else (0.74 if i == 4 else 0.62)
            if b > 16:
                accent *= 0.85
            ev.append((s.hum(s.T(b, i * 0.5)), voicing[idx], s.hv(accent)))
    # pequeño adorno en semicorcheas al final de las frases A
    for b in (8, 16):
        voicing = [note(x) for x in DAY_CHORDS[DAY_PROG[b - 1]][1].split()]
        ev.append((s.hum(s.T(b, 3.75)), voicing[5], s.hv(0.5)))
    for t, m, v, d in ring_ends(ev, change_times, chord_pcs, 2.6):
        s.lyre("arp", m, t, v, dur=d)
    # ---- bajo de lira ----
    for b, name in enumerate(DAY_PROG, start=1):
        root = note(DAY_CHORDS[name][0])
        s.lyre("bass", root, s.hum(s.T(b)), s.hv(0.85), dur=s.bpb * s.spb * (0.5 if b > 8 else 0.95), pan=-0.05,
               bright=0.45)
        if b > 8:
            fifth = root + 7 if name not in ("C/E",) else root + 3
            s.lyre("bass", fifth, s.hum(s.T(b, 2)), s.hv(0.62), dur=s.bpb * s.spb * 0.45, pan=-0.05, bright=0.4)
    # ---- pad de cuerdas (todo) + coro suave (A' y B) ----
    starts = [s.T(b) for b in range(1, bars + 1)]
    durs = [s.bpb * s.spb] * bars
    chord_track(s, "strings", [pcs(DAY_CHORDS[c][2]) for c in DAY_PROG], starts, durs, 4, 53, 71,
                overlap=0.5, kind="strings", attack=0.9, release=1.3, voices=4, detune=7, vib_depth=4,
                bright=0.85)
    chord_track(s, "choir", [pcs(DAY_CHORDS[c][2]) for c in DAY_PROG[8:]], starts[8:], durs[8:], 3, 57, 72,
                overlap=0.5, kind="choir", vowel="u", attack=1.2, release=1.6, voices=3, detune=9, vib_depth=7,
                breath=0.25, bright=0.8)
    # ---- latido de pandero (A' y B) ----
    for b in range(9, bars + 1):
        s.drum("drum", "dum", s.hum(s.T(b, 0), 0.004), s.hv(0.75), pan=-0.15)
        s.drum("drum", "dum", s.hum(s.T(b, 0.5), 0.004), s.hv(0.42), pan=-0.15)
        if b > 16:
            s.drum("drum", "tek", s.hum(s.T(b, 2.0), 0.004), s.hv(0.28), pan=0.1)
            s.drum("drum", "tek", s.hum(s.T(b, 3.5), 0.004), s.hv(0.22), pan=0.1)
    # ---- melodía (B) ----
    mel = sorted(DAY_MELODY)
    for i, (b, bt, d, nm) in enumerate(mel):
        t = s.hum(s.T(b, bt), 0.005)
        if i + 1 < len(mel):
            nxt = s.T(mel[i + 1][0], mel[i + 1][1])
            ring = nxt - t + 0.25
        else:
            ring = d * s.spb + 1.0
        v = 0.9 if bt == 0 else (0.8 if d >= 1 else 0.7)
        s.lyre("melody", note(nm), t, s.hv(v), dur=ring, pan=0.12, bright=0.62, t60=3.2)
    ir = make_ir(2.4, 1.0, 3.0, predelay=0.022, rng=rng_for("ir", "day"), lp=7500)
    cfg = {
        "arp": dict(level=-20.0, eq=LYRE_BODY, send=0.26),
        "bass": dict(level=-27.0, eq=LYRE_BODY + [("hp", 50, 0.7), ("lp", 2500, 0.7)], send=0.12),
        "strings": dict(level=-26.5, eq=[("hp", 140, 0.7), ("lp", 4500, 0.7)], send=0.38, width=1.3),
        "choir": dict(level=-30.0, eq=[("hp", 180, 0.7), ("lp", 5000, 0.7)], send=0.5, width=1.4),
        "drum": dict(level=-30.0, eq=[("lp", 3500, 0.7)], send=0.12),
        "melody": dict(level=-19.0, eq=LYRE_BODY, send=0.3),
    }
    return s.mix(cfg, ir, rms_db=-20.0)


# ---------------------------------------------------------------------------
# NOCHE — Re frigio
# ---------------------------------------------------------------------------

NIGHT_CHORDS = {  # nombre: (raíz del ostinato, clases, nota de color del ostinato)
    "Dm": ("D3", "D F A", 13),  # Mib (b2) por encima de la octava
    "Eb": ("Eb3", "Eb G Bb", 16),
    "Bb": ("Bb2", "Bb D F", 16),
    "Cm": ("C3", "C Eb G", 15),
    "Gm": ("G2", "G Bb D", 15),
}
NIGHT_PROG = ["Dm", "Dm", "Eb", "Dm", "Dm", "Dm", "Eb", "Dm",
              "Bb", "Cm", "Eb", "Dm", "Bb", "Cm", "Eb", "Eb",
              "Gm", "Gm", "Eb", "Dm", "Gm", "Cm", "Eb", "Eb"]
NIGHT_AULOS = [
    [(5, 1.0, 1.5, "A4", 0.75, False), (5, 2.5, 0.5, "Bb4", 0.7, True), (5, 3.0, 1.0, "A4", 0.75, True),
     (6, 0.0, 0.5, "G4", 0.7, True), (6, 0.5, 0.5, "F4", 0.7, True), (6, 1.0, 1.5, "Eb4", 0.8, True),
     (6, 2.5, 1.5, "D4", 0.7, True)],
    [(8, 2.5, 0.5, "D4", 0.62, False), (8, 3.0, 0.5, "F4", 0.68, True), (8, 3.5, 0.5, "G4", 0.72, True),
     (9, 0.0, 2.0, "Bb4", 0.8, True), (9, 2.0, 0.5, "A4", 0.7, True), (9, 2.5, 0.5, "G4", 0.7, True),
     (9, 3.0, 1.0, "F4", 0.72, True),
     (10, 0.0, 1.5, "G4", 0.75, True), (10, 1.5, 0.5, "Bb4", 0.72, True), (10, 2.0, 2.0, "C5", 0.8, True),
     (11, 0.0, 1.0, "Bb4", 0.75, True), (11, 1.0, 1.0, "G4", 0.72, True), (11, 2.0, 2.0, "Eb5", 0.85, False),
     (12, 0.0, 3.0, "D5", 0.8, True)],
    [(13, 0.0, 2.0, "F5", 0.82, False), (13, 2.0, 1.0, "D5", 0.76, True), (13, 3.0, 1.0, "Bb4", 0.74, True),
     (14, 0.0, 0.5, "C5", 0.74, True), (14, 0.5, 0.5, "D5", 0.76, True), (14, 1.0, 2.0, "Eb5", 0.84, True),
     (14, 3.0, 1.0, "C5", 0.74, True),
     (15, 0.0, 1.5, "Bb4", 0.76, True), (15, 1.5, 0.5, "C5", 0.72, True), (15, 2.0, 1.0, "Bb4", 0.72, True),
     (15, 3.0, 1.0, "G4", 0.7, True),
     (16, 0.0, 2.5, "Bb4", 0.74, True)],
    [(21, 1.0, 1.0, "D5", 0.74, False), (21, 2.0, 0.5, "C5", 0.7, True), (21, 2.5, 0.5, "Bb4", 0.7, True),
     (21, 3.0, 1.0, "A4", 0.72, True),
     (22, 0.0, 2.0, "G4", 0.75, True), (22, 2.0, 1.0, "F4", 0.7, True), (22, 3.0, 1.0, "G4", 0.7, True),
     (23, 0.0, 2.0, "G4", 0.74, True), (23, 2.0, 1.0, "F4", 0.7, True), (23, 3.0, 1.0, "Eb4", 0.72, True),
     (24, 0.0, 2.0, "F4", 0.7, True), (24, 2.0, 2.0, "Eb4", 0.74, True),
     (25, 0.0, 2.5, "D4", 0.7, True)],  # resuelve sobre el inicio del bucle
]
NIGHT_LYRE_ANSWER = [(17, 0, 1, "D5"), (17, 1, 1, "Bb4"), (17, 2, 2, "G4"),
                     (18, 0, 1, "A4"), (18, 1, 1, "Bb4"), (18, 2, 2, "D5"),
                     (19, 0, 1, "Eb5"), (19, 1, 1, "D5"), (19, 2, 1, "Bb4"), (19, 3, 1, "G4"),
                     (20, 0, 3, "A4")]


def _ostinato_bar(root: int, color: int, sixteenth: bool = False):
    """Ostinato 8 corcheas: r 5 8 5 r 5 color 5."""
    seq = [0, 7, 12, 7, 0, 7, color, 7]
    vel = [0.82, 0.55, 0.62, 0.5, 0.7, 0.52, 0.66, 0.5]
    return [(i * 0.5, root + o, v) for i, (o, v) in enumerate(zip(seq, vel))]


def night() -> np.ndarray:
    s = Song("night", 100, 4, bars=24)
    bars = len(NIGHT_PROG)
    # ---- ostinato de lira apagada ----
    for b, name in enumerate(NIGHT_PROG, start=1):
        root = note(NIGHT_CHORDS[name][0])
        for bt, m, v in _ostinato_bar(root, NIGHT_CHORDS[name][2]):
            s.lyre("ost", m, s.hum(s.T(b, bt), 0.005), s.hv(v), muted=True, bright=0.45, pan=-0.2 + 0.1 * (m > root))
    # ---- tambores 3+3+2 ----
    for b in range(1, bars + 1):
        fill = (b % 4 == 0 and b > 8) or b == bars
        if fill:
            hits = [(0, "dum", 0.85), (1, "tek", 0.35), (2, "tek", 0.5), (3, "dum", 0.6), (4, "tek", 0.45),
                    (5, "tek", 0.55), (6, "tek", 0.65), (7, "tek", 0.75)]
        elif b > 8:
            hits = [(0, "dum", 0.88), (3, "tek", 0.52), (4, "dum", 0.5), (6, "tek", 0.6), (7, "tek", 0.3)]
        else:
            hits = [(0, "dum", 0.85), (3, "tek", 0.5), (6, "tek", 0.55), (7, "tek", 0.22)]
        for step, kind, v in hits:
            s.drum("drums", kind, s.hum(s.T(b, step * 0.5), 0.004), s.hv(v), pan=-0.1 if kind == "dum" else 0.15)
        if b > 16:
            s.drum("drums", "big", s.hum(s.T(b, 0), 0.003), s.hv(0.55), pan=0.0)
    # ---- bordón grave (Re y La), notas largas que se encadenan ----
    for b in range(1, bars + 1, 4):
        st = s.T(b) - 0.8
        d = 4 * s.bpb * s.spb + 1.2
        s.add("drone", drone(note("D2"), d, s.sub_rng("drone"), attack=2.0, release=2.0, cutoff=520), st, 1.0)
        s.add("drone", drone(note("A2"), d, s.sub_rng("drone5"), attack=2.5, release=2.0, cutoff=480), st, 0.45)
    # ---- pad oscuro ----
    starts = [s.T(b) for b in range(1, bars + 1)]
    durs = [s.bpb * s.spb] * bars
    chord_track(s, "pad", [pcs(NIGHT_CHORDS[c][1]) for c in NIGHT_PROG], starts, durs, 3, 50, 65, overlap=0.4,
                kind="strings", attack=1.1, release=1.5, voices=4, detune=8, vib_depth=3, bright=0.6)
    chord_track(s, "choir", [pcs(NIGHT_CHORDS[c][1]) for c in NIGHT_PROG[8:]], starts[8:], durs[8:], 3, 52, 67,
                overlap=0.4, kind="choir", vowel="u", attack=1.4, release=1.8, voices=3, detune=10,
                vib_depth=6, breath=0.3, bright=0.7)
    # ---- aulós ----
    for ph in NIGHT_AULOS:
        s.aulos("aulos", ph, vib_depth=17, breath=0.055, mellow=0.55, drone_midi=note("D4"), drone_gain=0.16)
    # ---- respuesta de lira ----
    for i, (b, bt, d, nm) in enumerate(NIGHT_LYRE_ANSWER):
        s.lyre("answer", note(nm), s.hum(s.T(b, bt), 0.005), s.hv(0.85 if bt == 0 else 0.72),
               dur=d * s.spb + 0.6, pan=0.2, bright=0.6, t60=2.6)
    ir = make_ir(2.8, 1.1, 3.3, predelay=0.03, rng=rng_for("ir", "night"), lp=7000)
    cfg = {
        "ost": dict(level=-24.5, eq=LYRE_BODY + [("hp", 110, 0.7)], send=0.18),
        "drums": dict(level=-21.5, eq=[("lp", 4500, 0.7)], send=0.16),
        "drone": dict(level=-28.0, eq=[("lp", 1200, 0.7)], send=0.2, width=1.2),
        "pad": dict(level=-29.0, eq=[("hp", 120, 0.7), ("lp", 3000, 0.7)], send=0.4, width=1.3),
        "choir": dict(level=-31.0, eq=[("hp", 150, 0.7), ("lp", 4000, 0.7)], send=0.55, width=1.4),
        "aulos": dict(level=-19.0, eq=[("hp", 150, 0.7), ("lp", 6000, 0.7)], send=0.32),
        "answer": dict(level=-21.0, eq=LYRE_BODY, send=0.32),
    }
    return s.mix(cfg, ir, rms_db=-20.0)


# ---------------------------------------------------------------------------
# JEFE — Re frigio, más empuje
# ---------------------------------------------------------------------------

BOSS_PROG = ["Dm", "Dm", "Eb", "Dm", "Eb", "Eb",                     # A: introducción (6)
             "Dm", "Eb", "Cm", "Dm", "Bb", "Cm", "Eb", "Dm",         # B: + coro (8)
             "Bb", "Cm", "Dm", "Dm", "Bb", "Cm", "Eb", "Eb"]         # C: + aulós (8)
BOSS_SECTION_B, BOSS_SECTION_C = 7, 15


def _shift(phrase, d: int):
    """Desplaza una frase d compases."""
    return [(e[0] + d,) + tuple(e[1:]) for e in phrase]


BOSS_AULOS = _shift([
    (17, 0.0, 1.5, "D5", 0.8, False), (17, 1.5, 0.5, "C5", 0.72, True), (17, 2.0, 1.0, "D5", 0.78, True),
    (17, 3.0, 1.0, "F5", 0.82, True),
    (18, 0.0, 3.0, "Eb5", 0.86, True), (18, 3.0, 0.5, "D5", 0.74, True), (18, 3.5, 0.5, "C5", 0.72, True),
    (19, 0.0, 2.0, "D5", 0.8, True), (19, 2.0, 2.0, "A4", 0.74, True),
    (20, 2.0, 0.5, "D5", 0.74, False), (20, 2.5, 0.5, "Eb5", 0.78, True), (20, 3.0, 1.0, "F5", 0.82, True),
    (21, 0.0, 2.0, "F5", 0.85, True), (21, 2.0, 1.0, "D5", 0.76, True), (21, 3.0, 1.0, "Bb4", 0.74, True),
    (22, 0.0, 1.0, "C5", 0.76, True), (22, 1.0, 1.0, "Eb5", 0.8, True), (22, 2.0, 2.0, "G5", 0.86, True),
    (23, 0.0, 1.5, "G5", 0.84, True), (23, 1.5, 0.5, "F5", 0.76, True), (23, 2.0, 2.0, "Eb5", 0.8, True),
    (24, 0.0, 3.0, "F5", 0.8, True), (24, 3.0, 1.0, "Eb5", 0.78, True),
    (25, 0.0, 2.0, "D5", 0.78, True),  # resuelve sobre el inicio del bucle
], BOSS_SECTION_C - 17)


def boss() -> np.ndarray:
    s = Song("boss", 110, 4, bars=len(BOSS_PROG))  # 22 compases = 48,0 s exactos
    bars = len(BOSS_PROG)
    sx = 0.25  # semicorchea
    ends = {BOSS_SECTION_B - 1, BOSS_SECTION_C - 1, bars}  # compases con redoble
    # ---- ostinato en semicorcheas ----
    for b, name in enumerate(BOSS_PROG, start=1):
        root = note(NIGHT_CHORDS[name][0])
        color = NIGHT_CHORDS[name][2]
        seq = [0, 0, 7, 0, 12, 0, 7, 0, 0, 0, 7, 0, color, 0, 7, 12]
        acc = [0.85, 0.45, 0.6, 0.72, 0.6, 0.45, 0.72, 0.48, 0.8, 0.45, 0.6, 0.72, 0.68, 0.45, 0.72, 0.6]
        for i, (o, v) in enumerate(zip(seq, acc)):
            s.lyre("ost", root + o, s.hum(s.T(b, i * sx), 0.004), s.hv(v), muted=True, bright=0.5,
                   pan=-0.25 + 0.15 * (o > 0))
    # ---- percusión ----
    for b in range(1, bars + 1):
        big = [0, 6, 8, 14] + ([10, 12] if b >= BOSS_SECTION_C else [])
        dum = [0, 3, 6, 8, 11, 14]
        tek = [2, 4, 5, 7, 10, 12, 13, 15]
        fill = b in ends
        for st in big:
            s.drum("big", "big", s.hum(s.T(b, st * sx), 0.003), s.hv(0.9 if st in (0, 8) else 0.7))
        for st in dum:
            s.drum("drums", "dum", s.hum(s.T(b, st * sx), 0.003), s.hv(0.85 if st in (0, 8) else 0.62), pan=-0.12)
        for st in tek:
            if fill and st >= 12:
                continue
            s.drum("drums", "tek", s.hum(s.T(b, st * sx), 0.003), s.hv(0.3 + 0.12 * (st % 4 == 2)), pan=0.18)
        if fill:
            for k, st in enumerate((12, 12.5, 13, 13.5, 14, 14.5, 15, 15.5)):
                s.drum("drums", "tek", s.hum(s.T(b, st * sx), 0.003), 0.35 + 0.07 * k, pan=0.18)
    # ---- metales graves en swell (cada 2 compases) ----
    for b in range(1, bars + 1, 2):
        name = BOSS_PROG[b - 1]
        root = note(NIGHT_CHORDS[name][0]) - 12
        d = 2 * s.bpb * s.spb - 0.15
        for m, g in ((root, 1.0), (root + 7, 0.7), (root + 12, 0.45 if b >= BOSS_SECTION_B else 0.0)):
            if g <= 0:
                continue
            x = brass_note(m, d, s.sub_rng("brass", b, m), attack=1.1, release=0.8, low_cut=260, peak_cut=1300,
                           sustain=0.7, voices=3, detune=7)
            s.add("brass", x, s.T(b) - 0.05, g)
    # ---- coro (secciones B y C) ----
    starts = [s.T(b) for b in range(BOSS_SECTION_B, bars + 1)]
    durs = [s.bpb * s.spb] * len(starts)
    chord_track(s, "choir", [pcs(NIGHT_CHORDS[c][1]) for c in BOSS_PROG[BOSS_SECTION_B - 1:]], starts, durs, 4, 55,
                74, overlap=0.3, kind="choir", vowel=("a", "o", 0.3), attack=0.5, release=0.9, voices=4, detune=10,
                vib_depth=9, breath=0.3, bright=0.95)
    # ---- bordón ----
    half = bars // 2
    for b in (1, half + 1):
        d = half * s.bpb * s.spb + 1.0
        s.add("drone", drone(note("D2"), d, s.sub_rng("bdrone", b), attack=1.5, release=1.5, cutoff=420),
              s.T(b) - 0.5)
    # ---- platillos en crescendo hacia cada sección (y hacia el inicio del bucle) ----
    for b in sorted(ends):
        x = cymbal_swell(s.bpb * s.spb, s.sub_rng("cym", b), peak_at=1.0, tail=1.2)
        s.add("cym", x, s.T(b), 1.0)
    # ---- aulós (sección C) ----
    s.aulos("aulos", BOSS_AULOS, vib_depth=18, breath=0.05, mellow=0.6)
    ir = make_ir(2.4, 1.0, 3.0, predelay=0.025, rng=rng_for("ir", "boss"), lp=7000)
    cfg = {
        "ost": dict(level=-24.0, eq=LYRE_BODY + [("hp", 150, 0.7)], send=0.12),
        "big": dict(level=-22.0, eq=[("hp", 35, 0.7), ("lp", 1800, 0.7)], send=0.12),
        "drums": dict(level=-23.0, eq=[("lp", 5000, 0.7)], send=0.14),
        "brass": dict(level=-23.5, eq=[("hp", 50, 0.7), ("lp", 3000, 0.7)], send=0.25, width=1.2),
        "choir": dict(level=-25.0, eq=[("hp", 160, 0.7), ("lp", 5500, 0.7)], send=0.4, width=1.4),
        "drone": dict(level=-32.0, eq=[("hp", 45, 0.7), ("lp", 900, 0.7)], send=0.15),
        "cym": dict(level=-31.0, eq=[("lp", 8000, 0.7), ("hp", 600, 0.7)], send=0.3, width=1.3),
        "aulos": dict(level=-20.0, eq=[("hp", 180, 0.7), ("lp", 6000, 0.7)], send=0.3),
    }
    return s.mix(cfg, ir, rms_db=-19.0)


# ---------------------------------------------------------------------------
# TÍTULO — Re menor, 3/4, etéreo y noble
# ---------------------------------------------------------------------------

TITLE_CHORDS = {
    "Dm9": ("D2", "D3 A3 E4 F4 A4 D5", "D F A E"),
    "Bbmaj7": ("Bb2", "F3 Bb3 D4 F4 A4 D5", "Bb D F A"),
    "Fadd9": ("F2", "F3 C4 F4 G4 A4 C5", "F A C G"),
    "Cadd9": ("C2", "C3 G3 C4 D4 E4 G4", "C E G D"),
    "Dm": ("D2", "D3 A3 D4 F4 A4 D5", "D F A"),
    "Gm7": ("G2", "G3 Bb3 D4 F4 G4 Bb4", "G Bb D F"),
    "Asus4": ("A2", "A3 D4 E4 A4 D5 E5", "A D E"),
    "A": ("A2", "A3 C#4 E4 A4 C#5 E5", "A C# E"),
    "F/A": ("A2", "A3 C4 F4 A4 C5 F5", "F A C"),
}
TITLE_PROG = ["Dm9", "Dm9", "Bbmaj7", "Bbmaj7", "Fadd9", "Fadd9", "Cadd9", "Cadd9",
              "Dm", "Dm", "Bbmaj7", "Bbmaj7", "Gm7", "Gm7", "Asus4", "A",
              "Bbmaj7", "Bbmaj7", "F/A", "F/A", "Gm7", "Gm7", "Asus4", "A"]
TITLE_MELODY = [(9, 0, 3, "A4"), (10, 0, 3, "D5"), (11, 0, 2, "F5"), (11, 2, 1, "E5"), (12, 0, 3, "D5"),
                (13, 0, 3, "Bb4"), (14, 0, 3, "D5"), (15, 0, 3, "D5"), (16, 0, 3, "C#5"),
                (17, 0, 3, "D5"), (18, 0, 3, "F5"), (19, 0, 3, "C5"), (20, 0, 3, "A4"),
                (21, 0, 3, "D5"), (22, 0, 3, "Bb4"), (23, 0, 3, "D5"), (24, 0, 3, "C#5")]


def title() -> np.ndarray:
    s = Song("title", 70, 3, bars=24)
    bars = len(TITLE_PROG)
    change_times, chord_list = [], []
    for b in range(1, bars + 1):
        if b == 1 or TITLE_PROG[b - 1] != TITLE_PROG[b - 2]:
            change_times.append(s.T(b))
            chord_list.append(pcs(TITLE_CHORDS[TITLE_PROG[b - 1]][2]))
    change_times.append(s.T(bars + 1))
    chord_list.append(pcs(TITLE_CHORDS[TITLE_PROG[0]][2]))
    # ---- lira: subida en el primer compás de cada acorde, respiración en el segundo ----
    ev = []
    for b, name in enumerate(TITLE_PROG, start=1):
        voicing = [note(x) for x in TITLE_CHORDS[name][1].split()]
        first = b == 1 or TITLE_PROG[b - 2] != name
        pat = [0, 1, 2, 3, 4, 5] if first else [4, None, 3, None, 2, 1]
        if name == "A":
            pat = [0, 1, 2, 3, 4, 5]
        for i, idx in enumerate(pat):
            if idx is None:
                continue
            v = (0.8 if i == 0 else 0.6 - 0.03 * i) * (0.9 if not first else 1.0)
            ev.append((s.hum(s.T(b, i * 0.5), 0.008), voicing[idx], s.hv(v)))
    for t, m, v, d in ring_ends(ev, change_times, chord_list, 3.4):
        s.lyre("lyre", m, t, v, dur=d, bright=0.5, t60=None)
    # ---- bajo: suena hasta el siguiente cambio de acorde ----
    bass_bars = [b for b in range(1, bars + 1) if b == 1 or TITLE_PROG[b - 2] != TITLE_PROG[b - 1]]
    for i, b in enumerate(bass_bars):
        nb = bass_bars[i + 1] if i + 1 < len(bass_bars) else bars + 1
        s.lyre("bass", note(TITLE_CHORDS[TITLE_PROG[b - 1]][0]), s.hum(s.T(b)), s.hv(0.8),
               dur=s.T(nb) - s.T(b) - 0.1, pan=0.0, bright=0.4)
    # ---- coro (pad) ----
    starts = [s.T(b) for b in range(1, bars + 1)]
    durs = [s.bpb * s.spb] * bars
    chord_track(s, "choir", [pcs(TITLE_CHORDS[c][2]) for c in TITLE_PROG], starts, durs, 4, 50, 70, overlap=0.8,
                kind="choir", vowel=("o", "a", 0.35), attack=1.6, release=2.2, voices=4, detune=9, vib_depth=7,
                breath=0.3, bright=0.8)
    chord_track(s, "strings", [pcs(TITLE_CHORDS[c][2]) for c in TITLE_PROG], starts, durs, 3, 45, 60, overlap=0.8,
                kind="strings", attack=1.8, release=2.0, voices=4, detune=6, vib_depth=3, bright=0.6)
    # ---- melodía de soprano (coro "a"), compases 9–24 ----
    for b, bt, d, nm in TITLE_MELODY:
        x = pad_note(note(nm), d * s.spb + 0.25, s.sub_rng("sop", b, bt), kind="choir", vowel=("a", "o", 0.25),
                     voices=3, detune=6, vib_depth=11, vib_rate=5.2, attack=0.45, release=1.0, breath=0.35,
                     spread=0.35, bright=0.9)
        s.add("melody", x, s.T(b, bt) - 0.08, 1.0, 0.05)
    # ---- campana lejana ----
    for b, nm in ((1, "D5"), (5, "A4"), (9, "D5"), (13, "D5"), (17, "F5"), (21, "D5")):
        x = bell(note(nm), s.sub_rng("bell", b), dur=6.0, decay=2.4, bright=0.45, strike=0.15)
        x = filt(x, [("lp", 2600, 0.7)])
        s.add("bell", x, s.hum(s.T(b)), 1.0, -0.25)
    ir = make_ir(3.6, 1.4, 4.2, predelay=0.035, rng=rng_for("ir", "title"), lp=7000)
    cfg = {
        "lyre": dict(level=-20.5, eq=LYRE_BODY, send=0.34),
        "bass": dict(level=-26.0, eq=LYRE_BODY + [("lp", 2000, 0.7)], send=0.2),
        "choir": dict(level=-24.5, eq=[("hp", 110, 0.7), ("lp", 5000, 0.7)], send=0.5, width=1.4),
        "strings": dict(level=-29.0, eq=[("hp", 80, 0.7), ("lp", 2500, 0.7)], send=0.4, width=1.3),
        "melody": dict(level=-22.0, eq=[("hp", 200, 0.7), ("lp", 6000, 0.7)], send=0.5),
        "bell": dict(level=-27.0, eq=[("hp", 150, 0.7)], send=0.75),
    }
    return s.mix(cfg, ir, rms_db=-20.5)


# ---------------------------------------------------------------------------
# STINGERS
# ---------------------------------------------------------------------------

def stinger_dawn() -> np.ndarray:
    s = Song("stinger_dawn", 90, 4, length=4.0, pre=0.2)
    s.lyre("lyre", note("D2"), 0.0, 0.85, pan=0.0, bright=0.45)
    for m, g in (("D3", 0.7), ("A3", 0.8), ("D4", 0.9), ("F#4", 0.8), ("A4", 0.7), ("E5", 0.45)):
        x = pad_note(note(m), 1.9, s.sub_rng("p", m), kind="strings", attack=0.35, release=1.4, voices=4,
                     detune=8, vib_depth=4, bright=0.95)
        s.add("pad", x, 0.0, g)
        x = pad_note(note(m), 1.9, s.sub_rng("c", m), kind="choir", vowel="a", attack=0.5, release=1.5, voices=3,
                     detune=9, vib_depth=8, breath=0.25)
        s.add("choir", x, 0.05, g)
    gl = ["D4", "E4", "F#4", "A4", "B4", "D5", "E5", "F#5", "A5", "B5", "D6"]
    t = 0.04
    for i, nm in enumerate(gl):
        s.lyre("gliss", note(nm), t, 0.55 + 0.035 * i, bright=0.65)
        t += 0.062 - 0.0025 * i
    for nm, tt, g in (("A5", 0.66, 0.9), ("D6", 0.74, 0.75), ("F#6", 0.84, 0.4)):
        s.add("bells", bell(note(nm), s.sub_rng("b", nm), dur=3.2, decay=1.4, bright=0.55, strike=0.2), tt, g,
              0.2 if nm != "D6" else -0.2)
    ir = make_ir(2.4, 1.0, 3.0, predelay=0.02, rng=rng_for("ir", "dawn"), lp=8000)
    cfg = {
        "lyre": dict(level=-22.0, eq=LYRE_BODY, send=0.2),
        "pad": dict(level=-25.0, eq=[("hp", 100, 0.7), ("lp", 5000, 0.7)], send=0.35, width=1.3),
        "choir": dict(level=-27.0, eq=[("hp", 150, 0.7), ("lp", 6000, 0.7)], send=0.45, width=1.4),
        "gliss": dict(level=-18.5, eq=LYRE_BODY, send=0.35),
        "bells": dict(level=-21.0, eq=[("lp", 7000, 0.7)], send=0.5, width=1.2),
    }
    return s.mix(cfg, ir, rms_db=-18.0, fade_out=0.9)


def stinger_victory() -> np.ndarray:
    s = Song("stinger_victory", 100, 4, length=7.0, pre=0.2)
    # redoble creciente
    t, k = 0.0, 0
    while t < 1.15:
        v = 0.18 + 0.6 * (t / 1.15) ** 1.5
        s.drum("drums", "tek" if k % 2 else "dum", t, v, pan=0.1 if k % 2 else -0.1)
        t += 0.072
        k += 1
    s.add("cym", cymbal_swell(1.1, s.sub_rng("cym"), peak_at=1.0, tail=1.8), 0.1, 1.0)
    chords = [  # (t, dur, metales, coro, melodía)
        (1.2, 0.62, ["Bb2", "F3"], ["Bb3", "D4", "F4", "Bb4"], "D5"),
        (1.8, 0.62, ["C3", "G3"], ["C4", "E4", "G4", "C5"], "E5"),
        (2.4, 2.6, ["D3", "A3", "D2"], ["D4", "F#4", "A4", "D5"], "F#5"),
    ]
    for i, (tt, d, br, ch, mel) in enumerate(chords):
        for m in br:
            x = brass_note(note(m), d, s.sub_rng("br", m, i), attack=0.06 if i < 2 else 0.1, release=0.5 if i < 2 else 1.4,
                           low_cut=380, peak_cut=1800, sustain=0.85, voices=3, detune=6)
            s.add("brass", x, tt, 0.8)
        for m in ch:
            x = pad_note(note(m), d, s.sub_rng("ch", m, i), kind="choir", vowel="a", attack=0.08, release=0.6 if i < 2 else 1.6,
                         voices=3, detune=8, vib_depth=8, breath=0.25, bright=1.0)
            s.add("choir", x, tt, 0.8)
        x = brass_note(note(mel), d, s.sub_rng("mel", i), attack=0.05, release=0.5 if i < 2 else 1.5, low_cut=600,
                       peak_cut=2600, sustain=0.9, voices=2, detune=4)
        s.add("lead", x, tt, 1.0, 0.05)
        s.drum("big", "big", tt, 0.95)
        s.drum("drums", "dum", tt, 0.85, pan=-0.1)
    # arpegio final de lira y campanas
    for i, nm in enumerate(["D4", "F#4", "A4", "D5", "F#5", "A5", "D6"]):
        s.lyre("lyre", note(nm), 2.42 + 0.055 * i, 0.7 + 0.03 * i, bright=0.65)
    s.lyre("lyre", note("D2"), 2.4, 0.9, bright=0.45, pan=0.0)
    for nm, tt, g in (("D6", 2.5, 0.8), ("A5", 2.56, 0.6), ("F#6", 2.75, 0.35)):
        s.add("bells", bell(note(nm), s.sub_rng("vb", nm), dur=4.4, decay=1.8, bright=0.55), tt, g)
    s.add("cym", cymbal_swell(0.05, s.sub_rng("crash"), peak_at=1.0, tail=3.0), 2.38, 0.8)
    ir = make_ir(2.6, 1.1, 3.2, predelay=0.02, rng=rng_for("ir", "victory"), lp=7500)
    cfg = {
        "drums": dict(level=-24.0, eq=[("lp", 5000, 0.7)], send=0.15),
        "big": dict(level=-22.0, eq=[("lp", 1800, 0.7)], send=0.15),
        "cym": dict(level=-34.0, eq=[("lp", 6500, 0.7), ("hp", 500, 0.7)], send=0.3, width=1.3),
        "brass": dict(level=-22.0, eq=[("hp", 60, 0.7), ("lp", 3500, 0.7)], send=0.3, width=1.2),
        "choir": dict(level=-23.0, eq=[("hp", 150, 0.7), ("lp", 6000, 0.7)], send=0.4, width=1.4),
        "lead": dict(level=-21.0, eq=[("hp", 200, 0.7), ("lp", 5000, 0.7)], send=0.3),
        "lyre": dict(level=-23.0, eq=LYRE_BODY, send=0.3),
        "bells": dict(level=-24.0, eq=[("lp", 7000, 0.7)], send=0.5, width=1.2),
    }
    return s.mix(cfg, ir, rms_db=-18.0, fade_out=1.6)


def stinger_defeat() -> np.ndarray:
    s = Song("stinger_defeat", 60, 4, length=5.0, pre=0.2)
    s.add("drone", drone(note("D2"), 3.6, s.sub_rng("d"), attack=0.6, release=1.4, cutoff=450), 0.0, 1.0)
    chords = [(0.0, 1.35, ["G3", "Bb3", "D4", "Bb2"]), (1.3, 1.35, ["A3", "D4", "E4", "A2"]),
              (2.6, 1.6, ["A3", "D4", "F4", "D3"])]
    for i, (tt, d, ch) in enumerate(chords):
        for m in ch:
            x = pad_note(note(m), d, s.sub_rng("ch", m, i), kind="choir", vowel="u", attack=0.45, release=1.5,
                         voices=3, detune=8, vib_depth=6, breath=0.3, bright=0.75)
            s.add("choir", x, tt, 1.0)
            y = pad_note(note(m), d, s.sub_rng("st", m, i), kind="strings", attack=0.5, release=1.4, voices=3,
                         detune=6, vib_depth=3, bright=0.6)
            s.add("strings", y, tt, 1.0)
    # suspensión que resuelve: A sus4 -> A (do#) dentro del segundo acorde
    x = pad_note(note("C#4"), 0.6, s.sub_rng("res"), kind="choir", vowel="u", attack=0.3, release=0.9, voices=3)
    s.add("choir", x, 2.0, 0.8)
    phrase = [(1, 0.0, 0.6, "A4", 0.7, False), (1, 0.6, 0.6, "G4", 0.66, True), (1, 1.2, 0.5, "F4", 0.64, True),
              (1, 1.7, 0.9, "E4", 0.68, True), (1, 2.6, 1.7, "D4", 0.62, True)]
    s.aulos("aulos", phrase, vib_depth=14, breath=0.06, mellow=0.7, release=0.6)
    s.add("bell", bell(note("D4"), s.sub_rng("bell"), dur=3.0, decay=1.6, bright=0.4, strike=0.1), 2.62, 1.0, -0.2)
    ir = make_ir(3.0, 1.2, 3.5, predelay=0.03, rng=rng_for("ir", "defeat"), lp=6500)
    cfg = {
        "drone": dict(level=-27.0, eq=[("lp", 1000, 0.7)], send=0.2),
        "choir": dict(level=-23.0, eq=[("hp", 120, 0.7), ("lp", 4500, 0.7)], send=0.45, width=1.3),
        "strings": dict(level=-27.0, eq=[("hp", 90, 0.7), ("lp", 3000, 0.7)], send=0.4, width=1.2),
        "aulos": dict(level=-20.0, eq=[("hp", 150, 0.7), ("lp", 5500, 0.7)], send=0.4),
        "bell": dict(level=-27.0, eq=[("lp", 3000, 0.7)], send=0.6),
    }
    return s.mix(cfg, ir, rms_db=-19.0, fade_out=1.2)


MUSIC = {
    "day": day,
    "night": night,
    "boss": boss,
    "title": title,
    "stinger_dawn": stinger_dawn,
    "stinger_victory": stinger_victory,
    "stinger_defeat": stinger_defeat,
}
LOOPS = {"day", "night", "boss", "title"}
