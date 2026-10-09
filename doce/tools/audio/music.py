"""DOCE music: compositions written as data (chords, arpeggios, melodies) plus a bus mix.

Loops (rendered circularly: whatever rings past the end folds onto the start and the reverb is a circular
convolution, so every loop is seamless):
  * explore   – A Dorian, 6/8 (eighth = 162), 32 bars, 71.1 s. Lyre arpeggios, soft aulos, frame drums, strings
                and a choir "u". Also the title screen's music.
  * tension   – the ridge: same grid as explore (6/8, eighth = 162), 16 bars, 35.6 s. Drones, heartbeat drums, a
                low muted-lyre ostinato, tremolo strings, a low aulos. Uses only A C D E G, so it can crossfade from
                explore or play in sync on top of it.
  * boss_lion – the Nemean Lion: E Hitzaz, 7/8 (3+2+2, eighth = 264), 32 bars, 50.9 s. Great drums, pedal
                ostinato, brass swells, choir, a screaming aulos in the climax.
Stingers (one-shot): stinger_victory (C – D – E), stinger_death (Fmaj7 – Esus4 – Am, aulos lament).
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
# Shared helpers for DOCE
# ---------------------------------------------------------------------------


def arp_events(s: Song, prog, chords, patterns, bars_range, vel_fn, sd: float = 0.006):
    """Arpeggio events [(t, midi, vel)] for the bars in bars_range. patterns(bar) -> list of voicing indices or
    None (rest), one per subdivision (the song's beat unit)."""
    ev = []
    for b in bars_range:
        name = prog[b - 1]
        voicing = [note(x) for x in chords[name][1].split()]
        pat = patterns(b)
        for i, idx in enumerate(pat):
            if idx is None:
                continue
            ev.append((s.hum(s.T(b, i), sd), voicing[idx], s.hv(vel_fn(b, i))))
    return ev


def tremolo(x: np.ndarray, rate: float, depth: float) -> np.ndarray:
    t = np.arange(x.shape[0]) / SR
    m = 1.0 - depth * (0.5 + 0.5 * np.cos(2 * np.pi * rate * t))
    return x * (m[:, None] if x.ndim == 2 else m)


# ---------------------------------------------------------------------------
# EXPLORE — A Dorian, 6/8 (eighth = 162, dotted quarter = 54), 32 bars = 71.1 s
# Calm, sunlit, a little wistful: lyre arpeggios that move like the sea, a soft aulos, frame drums from bar 9.
# The title screen uses it too (the music simply carries on when the game starts).
# ---------------------------------------------------------------------------

EXPLORE_CHORDS = {
    # name: (bass, 6-note arpeggio voicing, pad pitch classes)
    "Am9": ("A2", "A3 E4 G4 B4 C5 E5", "A C E G B"),
    "D/A": ("A2", "A3 D4 F#4 A4 D5 F#5", "D F# A"),
    "Cmaj7": ("C3", "C4 E4 G4 B4 C5 E5", "C E G B"),
    "G/B": ("B2", "B3 D4 G4 B4 D5 G5", "G B D"),
    "G": ("G2", "G3 D4 G4 B4 D5 G5", "G B D"),
    "Am7": ("A2", "A3 E4 G4 A4 C5 E5", "A C E G"),
    "Esus4": ("E2", "E3 B3 E4 A4 B4 E5", "E A B"),
    "E": ("E2", "E3 B3 E4 G#4 B4 E5", "E G# B"),
    "D": ("D2", "D3 A3 D4 F#4 A4 D5", "D F# A"),
    "Bm7": ("B2", "B3 D4 F#4 A4 B4 D5", "B D F# A"),
}
EXPLORE_PROG = ["Am9", "Am9", "D/A", "D/A", "Cmaj7", "G/B", "Am7", "Esus4",
                "Am9", "Am9", "D/A", "D/A", "Cmaj7", "G/B", "Am7", "E",
                "Cmaj7", "G/B", "Am7", "D", "Cmaj7", "G", "Bm7", "E",
                "Am9", "Am9", "D/A", "D/A", "Cmaj7", "G/B", "Am7", "Esus4"]
EXPLORE_AULOS_1 = [  # (bar, eighth, length in eighths, note, vel, legato)
    (9, 0, 3, "E5", 0.70, False), (9, 3, 2, "D5", 0.64, True), (9, 5, 1, "C5", 0.62, True),
    (10, 0, 4, "B4", 0.68, True), (10, 4, 2, "A4", 0.6, True),
    (11, 0, 3, "F#4", 0.64, True), (11, 3, 3, "A4", 0.68, True),
    (12, 0, 5, "D5", 0.72, True),
    (13, 0, 2, "E5", 0.72, False), (13, 2, 1, "D5", 0.64, True), (13, 3, 3, "C5", 0.68, True),
    (14, 0, 3, "B4", 0.66, True), (14, 3, 2, "D5", 0.68, True), (14, 5, 1, "E5", 0.66, True),
    (15, 0, 4, "C5", 0.68, True), (15, 4, 2, "B4", 0.62, True),
    (16, 0, 5, "G#4", 0.64, True),
]
EXPLORE_AULOS_2 = [
    (25, 0, 3, "A5", 0.74, False), (25, 3, 2, "G5", 0.68, True), (25, 5, 1, "E5", 0.66, True),
    (26, 0, 6, "E5", 0.7, True),
    (27, 0, 2, "F#5", 0.72, False), (27, 2, 1, "E5", 0.66, True), (27, 3, 3, "D5", 0.68, True),
    (28, 0, 3, "A4", 0.64, True), (28, 3, 3, "D5", 0.68, True),
    (29, 0, 4, "E5", 0.72, True), (29, 4, 2, "G5", 0.7, True),
    (30, 0, 3, "F#5", 0.68, True), (30, 3, 3, "D5", 0.66, True),
    (31, 0, 3, "C5", 0.68, True), (31, 3, 2, "B4", 0.64, True), (31, 5, 1, "A4", 0.62, True),
    (32, 0, 6, "B4", 0.64, True),
    (33, 0, 4, "A4", 0.58, True),  # resolves over the start of the loop
]
EXPLORE_LYRE_MELODY = [  # (bar, eighth, length in eighths, note)
    (17, 0, 2, "A4"), (17, 2, 1, "B4"), (17, 3, 3, "C5"),
    (18, 0, 3, "D5"), (18, 3, 2, "B4"), (18, 5, 1, "G4"),
    (19, 0, 2, "A4"), (19, 2, 1, "C5"), (19, 3, 3, "E5"),
    (20, 0, 4, "F#5"), (20, 4, 2, "E5"),
    (21, 0, 2, "E5"), (21, 2, 1, "D5"), (21, 3, 3, "C5"),
    (22, 0, 3, "B4"), (22, 3, 3, "D5"),
    (23, 0, 2, "F#5"), (23, 2, 1, "E5"), (23, 3, 3, "D5"),
    (24, 0, 3, "B4"), (24, 3, 3, "G#4"),
]


def explore() -> np.ndarray:
    s = Song("explore", 162, 6, bars=len(EXPLORE_PROG))
    bars = len(EXPLORE_PROG)
    prog = EXPLORE_PROG
    change_times = [s.T(b + 1) for b in range(bars)] + [s.T(bars + 1)]
    chord_pcs = [pcs(EXPLORE_CHORDS[c][2]) for c in prog] + [pcs(EXPLORE_CHORDS[prog[0]][2])]

    def pattern(b):
        if 17 <= b <= 24:
            return [0, None, 2, 3, None, 2]  # thinner under the lyre melody
        if b in (8, 16, 32):
            return [0, 2, 3, 4, 5, None]
        return [0, 2, 4, 5, 4, 2] if b % 2 else [0, 1, 3, 4, 3, 1]

    def vel(b, i):
        v = 0.8 if i == 0 else (0.66 if i == 3 else 0.56)
        return v * (0.82 if 17 <= b <= 24 else 1.0) * (0.9 if b <= 4 else 1.0)

    ev = arp_events(s, prog, EXPLORE_CHORDS, pattern, range(1, bars + 1), vel, 0.007)
    for t, m, v, d in ring_ends(ev, change_times, chord_pcs, 2.8):
        s.lyre("arp", m, t, v, dur=d, bright=0.52)
    # lyre bass: root held through the bar (and the fifth on the second beat in B)
    for b, name in enumerate(prog, start=1):
        root = note(EXPLORE_CHORDS[name][0])
        s.lyre("bass", root, s.hum(s.T(b)), s.hv(0.8), dur=s.bpb * s.spb * (0.48 if 17 <= b <= 24 else 0.95),
               pan=-0.05, bright=0.42)
        if 17 <= b <= 24:
            s.lyre("bass", root + 7, s.hum(s.T(b, 3)), s.hv(0.6), dur=s.bpb * s.spb * 0.45, pan=-0.05, bright=0.4)
    # strings (soft, all along) and a choir "u" in the second half
    starts = [s.T(b) for b in range(1, bars + 1)]
    durs = [s.bpb * s.spb] * bars
    chord_track(s, "strings", [pcs(EXPLORE_CHORDS[c][2]) for c in prog], starts, durs, 4, 52, 70, overlap=0.5,
                kind="strings", attack=1.0, release=1.4, voices=4, detune=7, vib_depth=4, bright=0.8)
    chord_track(s, "choir", [pcs(EXPLORE_CHORDS[c][2]) for c in prog[16:]], starts[16:], durs[16:], 3, 57, 72,
                overlap=0.5, kind="choir", vowel="u", attack=1.3, release=1.7, voices=3, detune=9, vib_depth=7,
                breath=0.25, bright=0.8)
    # frame drums: a heartbeat in A', a lilting 6/8 in B and A''
    for b in range(9, bars + 1):
        if b <= 16:
            hits = [(0, "dum", 0.55), (3, "tek", 0.28)]
        elif b <= 24:
            hits = [(0, "dum", 0.66), (2, "tek", 0.22), (3, "dum", 0.4), (5, "tek", 0.28)]
        else:
            hits = [(0, "dum", 0.6), (3, "tek", 0.32), (5, "tek", 0.2)]
        if b == bars:
            hits = [(0, "dum", 0.6), (3, "tek", 0.3), (4, "tek", 0.36), (5, "tek", 0.44)]
        for st, kind, v in hits:
            s.drum("drum", kind, s.hum(s.T(b, st), 0.004), s.hv(v), pan=-0.15 if kind == "dum" else 0.12)
    # aulos (A' and A'')
    for ph in (EXPLORE_AULOS_1, EXPLORE_AULOS_2):
        s.aulos("aulos", ph, vib_depth=13, breath=0.05, mellow=0.75, pan=0.1)
    # lyre melody (B)
    mel = EXPLORE_LYRE_MELODY
    for i, (b, bt, d, nm) in enumerate(mel):
        t = s.hum(s.T(b, bt), 0.005)
        nxt = s.T(mel[i + 1][0], mel[i + 1][1]) if i + 1 < len(mel) else t + d * s.spb + 0.8
        s.lyre("melody", note(nm), t, s.hv(0.88 if bt == 0 else 0.74), dur=nxt - t + 0.25, pan=0.12, bright=0.62,
               t60=3.0)
    # a glint of bells at the two section starts
    for b, nm in ((1, "E6"), (17, "B5")):
        x = bell(note(nm), s.sub_rng("bell", b), dur=5.0, decay=2.0, bright=0.4, strike=0.12)
        s.add("bell", filt(x, [("lp", 3000, 0.7)]), s.T(b), 1.0, -0.25)
    ir = make_ir(2.6, 1.0, 3.2, predelay=0.024, rng=rng_for("ir", "explore"), lp=7500)
    cfg = {
        "arp": dict(level=-20.5, eq=LYRE_BODY, send=0.28),
        "bass": dict(level=-27.0, eq=LYRE_BODY + [("hp", 50, 0.7), ("lp", 2500, 0.7)], send=0.12),
        "strings": dict(level=-27.5, eq=[("hp", 140, 0.7), ("lp", 4200, 0.7)], send=0.4, width=1.3),
        "choir": dict(level=-30.0, eq=[("hp", 180, 0.7), ("lp", 5000, 0.7)], send=0.5, width=1.4),
        "drum": dict(level=-29.0, eq=[("lp", 3500, 0.7)], send=0.12),
        "aulos": dict(level=-20.5, eq=[("hp", 180, 0.7), ("lp", 5500, 0.7)], send=0.34),
        "melody": dict(level=-19.5, eq=LYRE_BODY, send=0.3),
        "bell": dict(level=-31.0, eq=[("hp", 300, 0.7)], send=0.7),
    }
    return s.mix(cfg, ir, rms_db=-20.5)


# ---------------------------------------------------------------------------
# TENSION — the ridge. Same grid as EXPLORE (6/8, eighth = 162, A), 16 bars = 35.6 s: it can replace the
# exploration theme (crossfade) or play in sync on top of it (only A C D E G: it never clashes with EXPLORE).
# ---------------------------------------------------------------------------

TENSION_AULOS = [
    (9, 0, 3, "E4", 0.62, False), (9, 3, 2, "D4", 0.58, True), (9, 5, 1, "C4", 0.56, True),
    (10, 0, 6, "A3", 0.6, True),
    (11, 0, 2, "C4", 0.6, False), (11, 2, 1, "D4", 0.58, True), (11, 3, 3, "E4", 0.64, True),
    (12, 0, 4, "G4", 0.66, True), (12, 4, 2, "E4", 0.6, True),
    (13, 0, 6, "D4", 0.6, True),
    (14, 0, 5, "E4", 0.58, True),
]


def tension() -> np.ndarray:
    s = Song("tension", 162, 6, bars=16)
    bars = 16
    # drones: A and E, long, overlapping
    for b in range(1, bars + 1, 4):
        st = s.T(b) - 0.8
        d = 4 * s.bpb * s.spb + 1.4
        s.add("drone", drone(note("A1"), d, s.sub_rng("dr", b), attack=2.0, release=2.0, cutoff=420), st, 1.0)
        s.add("drone", drone(note("E2"), d, s.sub_rng("dr5", b), attack=2.4, release=2.0, cutoff=400), st, 0.5)
    # heartbeat: lub-dub on every bar, a great drum every four bars
    for b in range(1, bars + 1):
        s.drum("drums", "dum", s.hum(s.T(b, 0), 0.003), s.hv(0.72), pan=-0.05, size=1.15)
        s.drum("drums", "dum", s.hum(s.T(b, 1), 0.003), s.hv(0.42), pan=-0.05, size=1.15)
        if b > 8:
            s.drum("drums", "tek", s.hum(s.T(b, 4), 0.003), s.hv(0.22), pan=0.2)
        if b % 4 == 1:
            s.drum("big", "big", s.hum(s.T(b), 0.003), s.hv(0.62))
    # muted lyre ostinato, low (A minor pentatonic only)
    ost = ["A2", "E3", "A3", "E3", "G3", "E3"]
    for b in range(1, bars + 1):
        for i, nm in enumerate(ost):
            if b <= 2 and i % 2:
                continue
            s.lyre("ost", note(nm), s.hum(s.T(b, i), 0.004), s.hv(0.62 if i == 0 else 0.46), muted=True, bright=0.4,
                   pan=-0.2 + 0.08 * i)
    # tremolo strings swelling in the second half of each phrase
    for b0 in (5, 13):
        for nm, g in (("A3", 1.0), ("E4", 0.8), ("A4", 0.5)):
            x = pad_note(note(nm), 4 * s.bpb * s.spb, s.sub_rng("tr", b0, nm), kind="strings", attack=2.4, release=1.6,
                         voices=4, detune=6, vib_depth=3, bright=0.7)
            s.add("trem", tremolo(x, 7.5, 0.55), s.T(b0), g)
    s.aulos("aulos", TENSION_AULOS, vib_depth=12, breath=0.07, mellow=0.8, pan=0.12)
    for b in (8, 16):
        s.add("cym", cymbal_swell(s.bpb * s.spb, s.sub_rng("cym", b), peak_at=1.0, tail=1.0), s.T(b), 1.0)
    ir = make_ir(3.0, 1.1, 3.4, predelay=0.03, rng=rng_for("ir", "tension"), lp=6500)
    cfg = {
        "drone": dict(level=-26.0, eq=[("lp", 1100, 0.7)], send=0.2, width=1.2),
        "drums": dict(level=-22.5, eq=[("lp", 3000, 0.7)], send=0.14),
        "big": dict(level=-25.0, eq=[("hp", 35, 0.7), ("lp", 1500, 0.7)], send=0.15),
        "ost": dict(level=-25.5, eq=LYRE_BODY + [("hp", 80, 0.7)], send=0.18),
        "trem": dict(level=-29.0, eq=[("hp", 150, 0.7), ("lp", 3200, 0.7)], send=0.4, width=1.3),
        "aulos": dict(level=-22.0, eq=[("hp", 150, 0.7), ("lp", 5000, 0.7)], send=0.38),
        "cym": dict(level=-33.0, eq=[("lp", 7000, 0.7), ("hp", 600, 0.7)], send=0.3, width=1.3),
    }
    return s.mix(cfg, ir, rms_db=-21.0)


# ---------------------------------------------------------------------------
# BOSS — the Nemean Lion. E Hitzaz (E F G# A B C D), 7/8 = 3+2+2, eighth = 264, 32 bars = 50.9 s.
# A great-drum kalamatianos, a pedal ostinato, brass swells, choir; the aulos screams in the climax.
# ---------------------------------------------------------------------------

LION_CHORDS = {"E": "E G# B", "F": "F A C", "Dm": "D F A", "Am": "A C E"}
LION_ROOT = {"E": "E2", "F": "F2", "Dm": "D2", "Am": "A1"}
LION_PROG = ["E", "E", "E", "E",                                   # intro: drums and brass
             "E", "E", "F", "E", "E", "E", "F", "E",               # A: the groove
             "E", "F", "E", "Dm", "Am", "Dm", "F", "E",            # B: + choir and aulos
             "Am", "F", "Dm", "E", "Am", "F", "F", "E",            # C: climax
             "E", "E", "F", "E"]                                    # D: breakdown back to the loop
LION_B, LION_C, LION_D = 13, 21, 29
LION_AULOS_B = [
    (13, 0, 3, "B4", 0.78, False), (13, 3, 2, "C5", 0.74, True), (13, 5, 2, "B4", 0.72, True),
    (14, 0, 2, "A4", 0.74, True), (14, 2, 1, "G#4", 0.7, True), (14, 3, 2, "A4", 0.72, True), (14, 5, 2, "C5", 0.76, True),
    (15, 0, 5, "B4", 0.78, True), (15, 5, 1, "A4", 0.7, True), (15, 6, 1, "G#4", 0.7, True),
    (16, 0, 3, "F4", 0.72, True), (16, 3, 2, "A4", 0.74, True), (16, 5, 2, "D5", 0.78, True),
    (17, 0, 3, "E5", 0.8, True), (17, 3, 2, "D5", 0.74, True), (17, 5, 2, "C5", 0.74, True),
    (18, 0, 2, "D5", 0.76, True), (18, 2, 1, "C5", 0.72, True), (18, 3, 2, "B4", 0.72, True), (18, 5, 2, "A4", 0.72, True),
    (19, 0, 3, "C5", 0.76, True), (19, 3, 2, "A4", 0.72, True), (19, 5, 1, "G#4", 0.7, True), (19, 6, 1, "F4", 0.7, True),
    (20, 0, 6, "E4", 0.74, True),
]
LION_AULOS_C = [
    (21, 0, 3, "E5", 0.82, False), (21, 3, 2, "F5", 0.8, True), (21, 5, 2, "E5", 0.78, True),
    (22, 0, 3, "F5", 0.82, True), (22, 3, 2, "A5", 0.86, True), (22, 5, 2, "F5", 0.8, True),
    (23, 0, 2, "D5", 0.78, True), (23, 2, 1, "E5", 0.78, True), (23, 3, 2, "F5", 0.8, True), (23, 5, 2, "A5", 0.86, True),
    (24, 0, 5, "G#5", 0.88, True), (24, 5, 2, "F5", 0.8, True),
    (25, 0, 3, "E5", 0.82, True), (25, 3, 2, "C5", 0.78, True), (25, 5, 2, "E5", 0.8, True),
    (26, 0, 3, "F5", 0.84, True), (26, 3, 2, "E5", 0.8, True), (26, 5, 1, "D5", 0.78, True), (26, 6, 1, "C5", 0.76, True),
    (27, 0, 3, "A4", 0.78, True), (27, 3, 2, "C5", 0.8, True), (27, 5, 2, "F5", 0.84, True),
    (28, 0, 4, "E5", 0.84, True), (28, 4, 3, "G#4", 0.78, True),
]


def boss_lion() -> np.ndarray:
    s = Song("boss_lion", 264, 7, bars=len(LION_PROG))
    bars = len(LION_PROG)
    sx = 0.5  # sixteenth (in eighths)
    fills = {4, 12, 20, 28, 32}
    # ---- percussion: the kalamatianos 3+2+2 on the great drums ----
    for b in range(1, bars + 1):
        climax = LION_C <= b < LION_D
        thin = b < 3
        big = [(0, 0.95), (3, 0.62), (5, 0.68)] + ([(6, 0.4)] if climax else [])
        dum = [(0, 0.86), (3, 0.66), (5, 0.7)]
        tek = [(1, 0.3), (2, 0.46), (4, 0.42), (6, 0.48)]
        if b in fills:
            tek = [(1, 0.3), (2, 0.46)] + [(3 + k * sx, 0.3 + 0.07 * k) for k in range(8)]
        for st, v in big:
            s.drum("big", "big", s.hum(s.T(b, st), 0.003), s.hv(v))
        if thin:
            continue
        for st, v in dum:
            s.drum("drums", "dum", s.hum(s.T(b, st), 0.003), s.hv(v), pan=-0.12)
        for st, v in tek:
            s.drum("drums", "tek", s.hum(s.T(b, st), 0.003), s.hv(v), pan=0.18)
        if climax and b not in fills:
            for st in (1.5, 4.5, 6.5):
                s.drum("drums", "tek", s.hum(s.T(b, st), 0.003), s.hv(0.2), pan=0.25)
    # ---- the pedal ostinato (muted lyre), following the root from section B ----
    riff = [0, -5, 0, 1, 0, 4, 1]           # E B E F E G# F (semitones from the root)
    acc = [0.86, 0.5, 0.62, 0.78, 0.55, 0.8, 0.6]
    for b in range(3, bars + 1):
        name = LION_PROG[b - 1]
        root = note("E3") if b < LION_B or b >= LION_D else note(LION_ROOT[name]) + 12
        r = riff if name == "E" or b < LION_B or b >= LION_D else [0, -5, 0, 2, 0, 3, 2]
        for i, (o, v) in enumerate(zip(r, acc)):
            s.lyre("ost", root + o, s.hum(s.T(b, i), 0.003), s.hv(v), muted=True, bright=0.5, pan=-0.22 + 0.12 * (o > 0))
    # ---- brass: low swells every two bars ----
    for b in range(1, bars + 1, 2):
        name = LION_PROG[b - 1]
        root = note(LION_ROOT[name])
        d = 2 * s.bpb * s.spb - 0.12
        parts = [(root, 1.0), (root + 7, 0.7)]
        if b >= LION_B:
            parts.append((root + 12, 0.5 if b < LION_C else 0.7))
        for m, g in parts:
            x = brass_note(m, d, s.sub_rng("brass", b, m), attack=0.9, release=0.7, low_cut=280, peak_cut=1500,
                           sustain=0.72, voices=3, detune=7)
            s.add("brass", x, s.T(b) - 0.04, g)
    # ---- choir (B and C) ----
    starts = [s.T(b) for b in range(LION_B, LION_D)]
    durs = [s.bpb * s.spb] * len(starts)
    chord_track(s, "choir", [pcs(LION_CHORDS[c]) for c in LION_PROG[LION_B - 1:LION_D - 1]], starts, durs, 4, 55, 74,
                overlap=0.25, kind="choir", vowel=("a", "o", 0.3), attack=0.35, release=0.8, voices=4, detune=10,
                vib_depth=9, breath=0.3, bright=0.95)
    # ---- drone on E ----
    for b in (1, 17):
        d = 16 * s.bpb * s.spb + 1.0
        s.add("drone", drone(note("E2"), d, s.sub_rng("drone", b), attack=1.2, release=1.2, cutoff=420), s.T(b) - 0.5)
    # ---- cymbal swells into each section and into the loop ----
    for b in (4, 12, 20, 28, 32):
        s.add("cym", cymbal_swell(s.bpb * s.spb, s.sub_rng("cym", b), peak_at=1.0, tail=1.2), s.T(b), 1.0)
    # ---- aulos ----
    s.aulos("aulos", LION_AULOS_B, vib_depth=20, breath=0.05, mellow=0.45, pan=0.06)
    s.aulos("aulos", LION_AULOS_C, vib_depth=22, breath=0.05, mellow=0.35, pan=0.06)
    ir = make_ir(2.2, 0.9, 2.8, predelay=0.022, rng=rng_for("ir", "boss_lion"), lp=7000)
    cfg = {
        "big": dict(level=-21.0, eq=[("hp", 35, 0.7), ("lp", 1800, 0.7)], send=0.12),
        "drums": dict(level=-22.5, eq=[("lp", 5000, 0.7)], send=0.12),
        "ost": dict(level=-24.0, eq=LYRE_BODY + [("hp", 120, 0.7)], send=0.12),
        "brass": dict(level=-23.5, eq=[("hp", 50, 0.7), ("lp", 3000, 0.7)], send=0.25, width=1.2),
        "choir": dict(level=-25.0, eq=[("hp", 160, 0.7), ("lp", 5500, 0.7)], send=0.38, width=1.4),
        "drone": dict(level=-31.0, eq=[("hp", 45, 0.7), ("lp", 900, 0.7)], send=0.15),
        "cym": dict(level=-31.0, eq=[("lp", 8000, 0.7), ("hp", 600, 0.7)], send=0.3, width=1.3),
        "aulos": dict(level=-20.0, eq=[("hp", 200, 0.7), ("lp", 6000, 0.7)], send=0.28),
    }
    return s.mix(cfg, ir, rms_db=-19.0)


# ---------------------------------------------------------------------------
# STINGERS
# ---------------------------------------------------------------------------

def stinger_victory() -> np.ndarray:
    """Labour done: a roll, then C – D – E (bVI – bVII – I) in brass and choir, a lyre run and bells."""
    s = Song("stinger_victory", 100, 4, length=7.0, pre=0.2)
    t, k = 0.0, 0
    while t < 1.0:
        v = 0.18 + 0.6 * (t / 1.0) ** 1.5
        s.drum("drums", "tek" if k % 2 else "dum", t, v, pan=0.1 if k % 2 else -0.1)
        t += 0.07
        k += 1
    s.add("cym", cymbal_swell(1.0, s.sub_rng("cym"), peak_at=1.0, tail=1.8), 0.05, 1.0)
    chords = [  # (t, dur, brass, choir, lead)
        (1.05, 0.6, ["C3", "G3"], ["C4", "E4", "G4", "C5"], "E5"),
        (1.65, 0.6, ["D3", "A3"], ["D4", "F#4", "A4", "D5"], "F#5"),
        (2.25, 2.8, ["E3", "B3", "E2"], ["E4", "G#4", "B4", "E5"], "G#5"),
    ]
    for i, (tt, d, br, ch, mel) in enumerate(chords):
        last = i == len(chords) - 1
        for m in br:
            x = brass_note(note(m), d, s.sub_rng("br", m, i), attack=0.06 if not last else 0.1,
                           release=0.5 if not last else 1.5, low_cut=380, peak_cut=1800, sustain=0.85, voices=3, detune=6)
            s.add("brass", x, tt, 0.8)
        for m in ch:
            x = pad_note(note(m), d, s.sub_rng("ch", m, i), kind="choir", vowel="a", attack=0.08,
                         release=0.6 if not last else 1.7, voices=3, detune=8, vib_depth=8, breath=0.25, bright=1.0)
            s.add("choir", x, tt, 0.8)
        x = brass_note(note(mel), d, s.sub_rng("mel", i), attack=0.05, release=0.5 if not last else 1.6, low_cut=600,
                       peak_cut=2600, sustain=0.9, voices=2, detune=4)
        s.add("lead", x, tt, 1.0, 0.05)
        s.drum("big", "big", tt, 0.95)
        s.drum("drums", "dum", tt, 0.85, pan=-0.1)
    for i, nm in enumerate(["E4", "G#4", "B4", "E5", "G#5", "B5", "E6"]):
        s.lyre("lyre", note(nm), 2.27 + 0.055 * i, 0.7 + 0.03 * i, bright=0.65)
    s.lyre("lyre", note("E2"), 2.25, 0.9, bright=0.45, pan=0.0)
    for nm, tt, g in (("E6", 2.35, 0.8), ("B5", 2.41, 0.6), ("G#6", 2.6, 0.35)):
        s.add("bells", bell(note(nm), s.sub_rng("vb", nm), dur=4.4, decay=1.8, bright=0.55), tt, g)
    s.add("cym", cymbal_swell(0.05, s.sub_rng("crash"), peak_at=1.0, tail=3.0), 2.23, 0.8)
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


def stinger_death() -> np.ndarray:
    """Heracles falls: a short lament. Fmaj7 – Esus4 – Am, the aulos sinking from E to A, a low bell."""
    s = Song("stinger_death", 60, 4, length=4.6, pre=0.2)
    s.add("drone", drone(note("A1"), 3.2, s.sub_rng("d"), attack=0.4, release=1.3, cutoff=420), 0.0, 1.0)
    s.drum("big", "big", 0.0, 0.7)
    chords = [(0.0, 1.1, ["F3", "A3", "C4", "E4"]), (1.05, 1.1, ["E3", "A3", "B3", "E4"]),
              (2.1, 1.6, ["A3", "C4", "E4", "A2"])]
    for i, (tt, d, ch) in enumerate(chords):
        for m in ch:
            x = pad_note(note(m), d, s.sub_rng("ch", m, i), kind="choir", vowel="u", attack=0.35, release=1.4,
                         voices=3, detune=8, vib_depth=6, breath=0.3, bright=0.75)
            s.add("choir", x, tt, 1.0)
            y = pad_note(note(m), d, s.sub_rng("st", m, i), kind="strings", attack=0.4, release=1.3, voices=3,
                         detune=6, vib_depth=3, bright=0.6)
            s.add("strings", y, tt, 1.0)
    phrase = [(1, 0.0, 0.5, "E4", 0.7, False), (1, 0.5, 0.5, "D4", 0.66, True), (1, 1.0, 0.5, "C4", 0.64, True),
              (1, 1.5, 0.7, "B3", 0.68, True), (1, 2.2, 1.6, "A3", 0.62, True)]
    s.aulos("aulos", phrase, vib_depth=14, breath=0.06, mellow=0.75, release=0.6)
    s.add("bell", bell(note("A3"), s.sub_rng("bell"), dur=2.6, decay=1.4, bright=0.4, strike=0.1), 2.15, 1.0, -0.2)
    ir = make_ir(3.0, 1.2, 3.5, predelay=0.03, rng=rng_for("ir", "death"), lp=6500)
    cfg = {
        "drone": dict(level=-27.0, eq=[("lp", 1000, 0.7)], send=0.2),
        "big": dict(level=-26.0, eq=[("lp", 1500, 0.7)], send=0.25),
        "choir": dict(level=-23.0, eq=[("hp", 120, 0.7), ("lp", 4500, 0.7)], send=0.45, width=1.3),
        "strings": dict(level=-27.0, eq=[("hp", 90, 0.7), ("lp", 3000, 0.7)], send=0.4, width=1.2),
        "aulos": dict(level=-20.0, eq=[("hp", 150, 0.7), ("lp", 5500, 0.7)], send=0.4),
        "bell": dict(level=-27.0, eq=[("lp", 3000, 0.7)], send=0.6),
    }
    return s.mix(cfg, ir, rms_db=-19.0, fade_out=1.1)


MUSIC = {
    "explore": explore,
    "tension": tension,
    "boss_lion": boss_lion,
    "stinger_victory": stinger_victory,
    "stinger_death": stinger_death,
}
LOOPS = {"explore", "tension", "boss_lion"}
