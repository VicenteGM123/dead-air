"""DOCE sound effects (mono): Heracles' combat, the chain spear, footsteps, the world and the interface.
The beasts (wolves, boars, the Nemean Lion, the wrestle) live in beasts.py.

Every recipe is layered: a transient (very short filtered noise), a body (modes or a sine with a pitch drop) and a
tail (filtered noise, a short reverb). Everything is low-passed so nothing is shrill on laptop speakers.
"""
from __future__ import annotations

import numpy as np

from common import (BAR, BLADE, PLATE, body_fall, bubbles, burst, chain_train, creak, debris, finish,
                    grain_cloud, link_clink, metal, pad_to, paw, place, pts, rumble, thump, unit, wet, whoosh)
from dsp import (SR, TAU, damped_modes, env_perc, env_points, filt, lp4, mag_band, mag_hp, mag_lp, mag_reso,
                 note, normalize_peak, rng_for, secs, smooth_random, spectral_noise, tvec)
from instruments import LYRE_BODY, bell, chime, frame_drum, lyre_pluck, pad_note

# ---------------------------------------------------------------------------
# Heracles: sword, shield, body
# ---------------------------------------------------------------------------


def swing(variant: int) -> np.ndarray:
    """Bronze sword through the air. 1 and 2: the quick cuts of the combo; 3: the wide closing arc."""
    rng = rng_for("doce-swing", variant)
    if variant == 1:
        dur, peak_t = 0.30, 0.10
        cen = [(0.0, 520), (peak_t, 1650), (0.30, 640)]
    elif variant == 2:
        dur, peak_t = 0.29, 0.09
        cen = [(0.0, 640), (peak_t, 1900), (0.29, 760)]
    else:
        dur, peak_t = 0.40, 0.15
        cen = [(0.0, 330), (peak_t, 1100), (0.40, 380)]
    n = secs(dur)
    gain = [(0.0, 0.0), (peak_t * 0.55, 0.45), (peak_t, 1.0), (peak_t + 0.06, 0.55), (dur, 0.0)]
    main = unit(whoosh(n, rng, cen, gain, width=0.34, hp=160))
    body = unit(whoosh(n, rng, [(p[0], p[1] * 0.45) for p in cen], gain, width=0.6, hp=90))
    air = unit(whoosh(n, rng, [(p[0], p[1] * 2.3) for p in cen], gain, width=0.4, lp=7000))
    # the thin edge whistles a little
    whistle = unit(whoosh(n, rng, [(p[0], p[1] * 2.0) for p in cen], gain, width=0.05, lp=7500))
    y = main + (0.3 if variant != 3 else 0.5) * body + 0.18 * air + 0.16 * whistle
    if variant == 3:
        t = tvec(n)
        woom = np.sin(TAU * np.cumsum(pts(t, [(0, 75), (peak_t, 100), (dur, 62)])) / SR) * env_points(n, gain)
        y = y + 0.28 * unit(woom)
    y *= env_points(n, gain) ** 0.3
    return finish(y, dur, -3.0, fade_in=0.004, fade_out=0.04)


def swing_heavy() -> np.ndarray:
    """The charged heavy blow: a long, low arc with the whole body behind it."""
    rng = rng_for("doce-swing-heavy")
    dur, peak_t = 0.62, 0.3
    n = secs(dur)
    cen = [(0.0, 200), (0.18, 420), (peak_t, 900), (dur, 260)]
    gain = [(0.0, 0.0), (0.16, 0.25), (peak_t, 1.0), (peak_t + 0.08, 0.6), (dur, 0.0)]
    main = unit(whoosh(n, rng, cen, gain, width=0.4, hp=110, nfft=1024))
    body = unit(whoosh(n, rng, [(p[0], p[1] * 0.5) for p in cen], gain, width=0.7, hp=60, nfft=1024))
    air = unit(whoosh(n, rng, [(p[0], p[1] * 2.6) for p in cen], gain, width=0.45, lp=6500))
    t = tvec(n)
    woom = np.sin(TAU * np.cumsum(pts(t, [(0, 55), (peak_t, 90), (dur, 50)])) / SR) * env_points(n, gain)
    # cloth and leather of the windup
    cloth = unit(whoosh(n, rng, [(0, 900), (0.2, 1300), (0.35, 700)], [(0, 0), (0.05, 0.6), (0.2, 0.3), (0.3, 0)],
                        width=0.9, lp=4500, hp=200))
    y = main + 0.55 * body + 0.15 * air + 0.38 * unit(woom) + 0.12 * cloth
    return finish(y, dur, -3.0, fade_in=0.006, fade_out=0.06)


def hit_flesh(variant: int) -> np.ndarray:
    """Blade into a wolf or a boar: a meaty smack, the cut through fur, the body taking it."""
    rng = rng_for("doce-hit", variant)
    n = secs(0.32)
    p = {1: (135, 62, 760, 0.028), 2: (155, 70, 880, 0.024), 3: (118, 55, 640, 0.034)}[variant]
    y = np.zeros(n)
    y += 1.0 * thump(n, p[0], p[1], 0.016, 0.05, attack=0.0012)
    y += 0.65 * unit(burst(n, rng, p[3], [("bp", p[2], 0.9), ("lp", 3000, 0.7)], attack=0.0008))
    y += 0.3 * unit(burst(n, rng, 0.045, [("lp", 420, 0.7)]))
    # the edge slicing through fur
    cut = whoosh(n, rng, [(0, 4200), (0.06, 2600), (0.2, 2000)], [(0, 0), (0.004, 1.0), (0.03, 0.4), (0.09, 0.0)],
                 width=0.5, lp=7000)
    y += 0.3 * unit(cut)
    times = np.sort(rng.uniform(0.002, 0.07, 14))
    fur = grain_cloud(n, rng, times, np.exp(-times / 0.03), 2200, 5500, 0.0005, 0.0018, q=0.9)
    y += 0.16 * unit(fur)
    # wet crunch
    y += 0.18 * unit(burst(n, rng, 0.006, [("bp", 1700, 1.3)]))
    y = wet(y, "small", 0.12)
    return finish(y, 0.28, -3.0, fade_out=0.05, lp=7500)


def hit_heavy() -> np.ndarray:
    """The heavy blow landing: deeper thump, crunch, a cloud of grit."""
    rng = rng_for("doce-hit-heavy")
    n = secs(0.6)
    y = np.zeros(n)
    y += 1.0 * thump(n, 120, 42, 0.022, 0.12, attack=0.0015)
    y += 0.7 * unit(burst(n, rng, 0.03, [("bp", 650, 0.8), ("lp", 2600, 0.7)]))
    y += 0.5 * unit(burst(n, rng, 0.08, [("lp", 300, 0.7)]))
    cut = whoosh(n, rng, [(0, 3600), (0.1, 1800)], [(0, 0), (0.005, 1.0), (0.05, 0.4), (0.14, 0.0)], width=0.6, lp=6500)
    y += 0.25 * unit(cut)
    y += 0.22 * unit(debris(n, rng, 0.01, 18, 0.05, 700, 2600, 0.12))
    y = wet(y, "small", 0.16)
    return finish(y, 0.55, -3.0, fade_out=0.1, lp=7000)


def blade_bounce() -> np.ndarray:
    """The sword skids off the Lion's hide: a dull knock, the blade ringing, a shower of sparks. Unmistakable."""
    rng = rng_for("doce-blade-bounce")
    n = secs(0.9)
    y = np.zeros(n)
    # dull knock of the hide (it gives nothing back)
    y += 0.55 * thump(n, 210, 120, 0.01, 0.035, attack=0.0008)
    # the blade rings: a high clang and a lower "tang"
    ring = metal(n, rng, 1180.0, BLADE, [1.0, 0.7, 0.55, 0.42, 0.3, 0.18, 0.1],
                 [0.42, 0.33, 0.26, 0.2, 0.15, 0.11, 0.08], beat=3.0, lp=7000, hp=400)
    tang = metal(n, rng, 640.0, BAR, [1.0, 0.45, 0.15, 0.05], [0.5, 0.2, 0.08, 0.04], beat=1.5, lp=5000, hp=250)
    place(y, ring, 0.002, 0.8)
    place(y, tang, 0.002, 0.45)
    # sparks: a hiss and tiny crackles
    hiss = whoosh(n, rng, [(0, 5200), (0.25, 4200)], [(0, 0), (0.004, 1.0), (0.06, 0.35), (0.22, 0.0)], width=0.35,
                  lp=8500)
    y += 0.14 * unit(hiss)
    times = np.sort(rng.exponential(0.05, 30))
    times = times[times < 0.3]
    crackle = grain_cloud(n, rng, times, np.exp(-times / 0.08), 3200, 6500, 0.0003, 0.001, q=1.4)
    y += 0.2 * unit(filt(crackle, lp4(8000)))
    # the blade scraping off the fur
    scrape = whoosh(n, rng, [(0, 2600), (0.12, 1500)], [(0, 0), (0.01, 0.8), (0.08, 0.5), (0.14, 0.0)], width=0.5,
                    lp=5000)
    y += 0.18 * unit(scrape)
    y = wet(y, "small", 0.2)
    return finish(y, 0.85, -3.0, fade_out=0.25, lp=9000)


def shield_block() -> np.ndarray:
    """A blow taken on the bronze-faced shield: deep wooden bonk with a bronze rim ring."""
    rng = rng_for("doce-shield-block")
    n = secs(0.6)
    y = np.zeros(n)
    y += 1.0 * thump(n, 160, 68, 0.02, 0.085)
    wood = damped_modes(n, [190, 430, 780, 1240], [1.0, 0.6, 0.35, 0.18], [0.07, 0.045, 0.03, 0.02], attack=0.001,
                        rng=rng)
    y += 0.55 * unit(wood)
    y += 0.5 * unit(burst(n, rng, 0.02, [("lp", 1200, 0.7)]))
    rim = metal(n, rng, 360.0, PLATE, [1.0, 0.75, 0.6, 0.42, 0.3, 0.2, 0.1], [0.24, 0.2, 0.15, 0.12, 0.1, 0.08, 0.06],
                beat=2.5, lp=5000, hp=240)
    place(y, rim, 0.003, 0.32)
    y = wet(y, "small", 0.15)
    return finish(y, 0.5, -3.0, fade_out=0.1)


def parry() -> np.ndarray:
    """Perfect parry: bronze meets bronze at the right instant, a bright ring that hangs in the air."""
    rng = rng_for("doce-parry")
    n = secs(1.3)
    y = np.zeros(n)
    y += 0.5 * thump(n, 190, 95, 0.01, 0.04, attack=0.0008)
    y += 0.35 * unit(burst(n, rng, 0.004, [("bp", 3000, 0.9)]))
    ring = metal(n, rng, 1320.0, (1.0, 2.01, 2.76, 3.9, 5.4), [1.0, 0.55, 0.35, 0.2, 0.1], [0.75, 0.5, 0.32, 0.2, 0.12],
                 beat=1.6, lp=8000, hp=500)
    place(y, ring, 0.001, 0.75)
    # a fifth above, a breath later: the "reward"
    c = chime(note("B6"), rng, dur=1.0, decay=0.45)
    place(y, c, 0.012, 0.22)
    sh = whoosh(n, rng, [(0, 3000), (0.5, 5200)], [(0, 0), (0.02, 0.6), (0.2, 0.25), (0.6, 0.0)], width=0.35, lp=8500)
    y += 0.06 * unit(sh)
    y = wet(y, "med", 0.28)
    return finish(y, 1.2, -3.0, fade_out=0.3, lp=9500)


def dodge_roll() -> np.ndarray:
    """Dodge roll: cloth through the air, the shoulder meeting the ground, a roll over grit."""
    rng = rng_for("doce-dodge-roll")
    n = secs(0.6)
    gain = [(0.0, 0.0), (0.04, 0.7), (0.08, 1.0), (0.15, 0.4), (0.3, 0.0)]
    cloth = unit(whoosh(n, rng, [(0, 750), (0.08, 1350), (0.3, 600)], gain, width=0.8, lp=4800, hp=150))
    t = tvec(n)
    cloth *= 1.0 + 0.18 * np.sin(TAU * 34 * t)
    y = cloth.copy()
    k = thump(secs(0.3), 105, 55, 0.015, 0.05) + 0.5 * unit(burst(secs(0.3), rng, 0.03, [("lp", 500, 0.7)]))
    place(y, unit(k), 0.13, 0.75)
    roll = rumble(n, rng, [(0, 0), (0.13, 0), (0.18, 1.0), (0.38, 0.6), (0.5, 0.0)], 150, 90)
    y += 0.45 * unit(roll)
    times = np.sort(rng.uniform(0.14, 0.45, 34))
    grit = grain_cloud(n, rng, times, np.exp(-(times - 0.14) / 0.12), 1200, 3600, 0.0008, 0.0025)
    y += 0.24 * unit(filt(grit, lp4(4500)))
    # bronze greave clink
    place(y, link_clink(rng, 2900.0, 0.08), 0.15, 0.08)
    y = wet(y, "small", 0.1)
    return finish(y, 0.55, -3.0, fade_in=0.003, fade_out=0.06)


def hero_hurt() -> np.ndarray:
    rng = rng_for("doce-hero-hurt")
    n = secs(0.35)
    y = np.zeros(n)
    y += 0.9 * thump(n, 95, 58, 0.02, 0.07)
    y += 0.7 * unit(burst(n, rng, 0.04, [("lp", 420, 0.7)]))
    y += 0.18 * unit(burst(n, rng, 0.03, [("bp", 1400, 0.8)]))
    clink = damped_modes(secs(0.25), [1650, 2480, 3410, 4300], [1.0, 0.6, 0.35, 0.18], [0.09, 0.07, 0.05, 0.035],
                         attack=0.001, rng=rng, beat=3.0)
    place(y, unit(filt(clink, [("lp", 6000, 0.7)])), 0.009, 0.28)
    y = wet(y, "small", 0.12)
    return finish(y, 0.3, -3.0, fade_out=0.05)


def hero_death() -> np.ndarray:
    """Heracles falls: a heavy body, the helmet and the shield clattering on stone."""
    rng = rng_for("doce-hero-death")
    n = secs(1.2)
    y = np.zeros(n)
    place(y, body_fall(rng, 1.4, 0.8), 0.0, 1.0)
    impacts = [0.24, 0.37, 0.46, 0.53, 0.58, 0.615, 0.643, 0.664, 0.68, 0.692]
    for i, ti in enumerate(impacts):
        a = 0.85 * (0.78 ** i)
        m = metal(secs(0.45), rng, 330.0, PLATE[:6], [1.0, 0.7, 0.55, 0.35, 0.25, 0.12], [0.2, 0.16, 0.12, 0.1, 0.08, 0.06],
                  beat=2.0, lp=4800, hp=200)
        place(y, m * 0.5 + 0.1 * unit(burst(secs(0.45), rng, 0.006, [("bp", 1600, 1.0), ("lp", 4500, 0.7)])), ti, a * 0.5)
    y = wet(y, "small", 0.2)
    return finish(y, 1.1, -3.0, fade_out=0.15)


def jump() -> np.ndarray:
    """Push-off: a scuff of grit and a short rush of cloth upwards."""
    rng = rng_for("doce-jump")
    n = secs(0.3)
    y = np.zeros(n)
    times = np.sort(rng.uniform(0.0, 0.05, 14))
    y += 0.5 * unit(grain_cloud(n, rng, times, np.exp(-times / 0.03), 1100, 3500, 0.0008, 0.0025))
    y += 0.35 * unit(burst(n, rng, 0.02, [("lp", 500, 0.7)], attack=0.002))
    up = whoosh(n, rng, [(0, 600), (0.12, 1400), (0.28, 900)], [(0, 0), (0.03, 0.6), (0.09, 1.0), (0.26, 0.0)],
                width=0.8, lp=5000, hp=200)
    y += 0.6 * unit(up)
    return finish(y, 0.28, -6.0, fade_in=0.002, fade_out=0.05)


def land() -> np.ndarray:
    """Landing from a jump: both feet, bronze armour settling, a puff of dust."""
    rng = rng_for("doce-land")
    n = secs(0.45)
    y = np.zeros(n)
    place(y, paw(rng, 1.6, 0.3), 0.0, 1.0)
    place(y, paw(rng, 1.3, 0.3), 0.028, 0.6)
    place(y, link_clink(rng, 2600.0, 0.1), 0.012, 0.12)
    place(y, link_clink(rng, 3300.0, 0.08), 0.035, 0.07)
    dust = whoosh(n, rng, [(0, 1100), (0.4, 700)], [(0, 0), (0.02, 1), (0.25, 0)], width=1.1, lp=3000)
    y += 0.15 * unit(dust)
    y = wet(y, "small", 0.08)
    return finish(y, 0.4, -4.0, fade_out=0.06)


# ---------------------------------------------------------------------------
# Footsteps (grass, stone, sand): three takes each, quiet by design
# ---------------------------------------------------------------------------

def step(surface: str, variant: int) -> np.ndarray:
    rng = rng_for("doce-step", surface, variant)
    n = secs(0.22)
    y = np.zeros(n)
    w = 1.0 + 0.12 * (variant - 2)
    if surface == "grass":
        y += 0.55 * thump(n, 85 * w, 55, 0.012, 0.03, attack=0.003)
        swish = whoosh(n, rng, [(0, 1900 * w), (0.12, 2700)], [(0, 0), (0.008, 1.0), (0.05, 0.5), (0.13, 0.0)],
                       width=0.7, lp=5000, hp=500)
        y += 0.5 * unit(swish)
        times = np.sort(rng.uniform(0.003, 0.08, 10))
        y += 0.22 * unit(grain_cloud(n, rng, times, np.exp(-times / 0.04), 1500, 4000, 0.0006, 0.002, q=0.8))
        peak, lp = -10.0, 5500
    elif surface == "stone":
        y += 0.55 * thump(n, 120 * w, 70, 0.008, 0.022, attack=0.001)
        y += 0.45 * unit(burst(n, rng, 0.003, [("bp", 2100 * w, 1.0), ("lp", 5000, 0.7)], attack=0.0004))
        knock = damped_modes(n, [rng.uniform(850, 1050) * w, rng.uniform(1700, 2000) * w], [0.6, 0.25], [0.012, 0.007],
                             attack=0.0005, rng=rng)
        y += 0.3 * unit(knock)
        times = np.sort(rng.uniform(0.004, 0.05, 7))
        y += 0.18 * unit(grain_cloud(n, rng, times, np.exp(-times / 0.03), 1500, 4500, 0.0005, 0.0015))
        y = wet(y, "small", 0.12)
        peak, lp = -9.0, 7500
    elif surface == "earth":
        y += 0.6 * thump(n, 90 * w, 58, 0.012, 0.028, attack=0.002)
        y += 0.35 * unit(burst(n, rng, 0.02, [("lp", 700, 0.7)], attack=0.002))
        times = np.sort(rng.uniform(0.004, 0.07, 14))
        y += 0.28 * unit(filt(grain_cloud(n, rng, times, np.exp(-times / 0.04), 1200, 3800, 0.0008, 0.0025), [("lp", 5000, 0.7)]))
        peak, lp = -8.0, 6500
    else:  # sand
        y += 0.5 * thump(n, 75 * w, 48, 0.014, 0.035, attack=0.004)
        shff = whoosh(n, rng, [(0, 900 * w), (0.15, 1500)], [(0, 0), (0.012, 1.0), (0.06, 0.6), (0.17, 0.0)],
                      width=1.0, lp=3200, hp=150)
        y += 0.65 * unit(shff)
        times = np.sort(rng.uniform(0.005, 0.11, 30))
        y += 0.12 * unit(grain_cloud(n, rng, times, np.exp(-times / 0.05), 2500, 6000, 0.0003, 0.0009, q=0.7))
        peak, lp = -10.0, 5000
    return finish(y, 0.2, peak, fade_in=0.002, fade_out=0.05, lp=lp)


# ---------------------------------------------------------------------------
# The chain spear
# ---------------------------------------------------------------------------

def chain_throw() -> np.ndarray:
    """The spear leaves the hand and the chain pays out behind it, fast, then thinner as it flies away."""
    rng = rng_for("doce-chain-throw")
    dur = 0.8
    n = secs(dur)
    y = np.zeros(n)
    wh = whoosh(n, rng, [(0, 500), (0.07, 2400), (0.4, 1200)], [(0, 0), (0.03, 0.7), (0.07, 1.0), (0.18, 0.35), (0.5, 0)],
                width=0.45, lp=7500, hp=200)
    y += 0.8 * unit(wh)
    # links unspooling: the interval starts at ~11 ms and slowly widens, pitch drifting down (Doppler)
    times, t = [], 0.03
    while t < 0.62:
        times.append(t)
        t += 0.011 + 0.03 * (t / 0.62) ** 1.6 + rng.uniform(-0.002, 0.003)
    times = np.array(times)
    amps = np.clip(1.0 - (times - 0.03) / 0.6, 0.08, 1.0) ** 1.3
    y += 0.55 * unit(chain_train(n, rng, times, amps, 2000, 4000, pitch=lambda tt: 1.0 - 0.18 * tt / 0.6))
    # the arm's effort: a low push
    y += 0.25 * unit(burst(n, rng, 0.03, [("lp", 300, 0.7)], attack=0.004))
    y = wet(y, "small", 0.12)
    return finish(y, dur, -3.0, fade_in=0.003, fade_out=0.12, lp=9000)


def chain_stick() -> np.ndarray:
    """The spearhead bites into wood or rock: a hard thunk, a ring of bronze, the shaft quivering."""
    rng = rng_for("doce-chain-stick")
    n = secs(0.7)
    y = np.zeros(n)
    y += 0.9 * thump(n, 210, 90, 0.008, 0.035, attack=0.0006)
    wood = damped_modes(n, [330, 720, 1210, 1900], [1.0, 0.6, 0.3, 0.15], [0.05, 0.035, 0.022, 0.015], attack=0.0006,
                        rng=rng)
    y += 0.6 * unit(wood)
    y += 0.5 * unit(burst(n, rng, 0.004, [("bp", 2400, 1.0)], attack=0.0003))
    tip = metal(n, rng, 2100.0, BAR, [1.0, 0.4, 0.12, 0.04], [0.16, 0.08, 0.04, 0.02], beat=2.0, lp=7500, hp=600)
    place(y, tip, 0.001, 0.3)
    # quiver of the shaft: a low tone wobbling fast and dying
    t = tvec(n)
    quiver = np.sin(TAU * 150 * t + 0.4 * np.sin(TAU * 19 * t)) * (0.55 + 0.45 * np.sin(TAU * 19 * t)) * env_perc(n, 0.004, 0.16)
    y += 0.3 * unit(filt(quiver, [("lp", 900, 0.7)]))
    times = 0.06 + np.sort(rng.exponential(0.05, 9))
    y += 0.14 * unit(chain_train(n, rng, times, np.exp(-(times - 0.06) / 0.1)))
    y = wet(y, "small", 0.14)
    return finish(y, 0.65, -3.0, fade_out=0.12)


def chain_rattle() -> np.ndarray:
    """The slack chain shaken or reeled in: a loose metallic jingle."""
    rng = rng_for("doce-chain-rattle")
    dur = 0.7
    n = secs(dur)
    times = np.sort(np.concatenate([rng.uniform(0.0, 0.5, 34), rng.uniform(0.05, 0.25, 18)]))
    env = np.interp(times, [0, 0.06, 0.25, 0.55], [0.4, 1.0, 0.7, 0.1])
    y = unit(chain_train(n, rng, times, env, 1800, 3800))
    y += 0.1 * unit(whoosh(n, rng, [(0, 1800), (0.5, 1400)], [(0, 0), (0.06, 1.0), (0.5, 0)], width=0.7, lp=6000))
    y = wet(y, "small", 0.12)
    return finish(y, dur, -4.0, fade_in=0.002, fade_out=0.12, lp=9000)


def chain_taut() -> np.ndarray:
    """The chain snaps tight (pulling something heavy, or being pulled): links aligning, a clank, a strained creak."""
    rng = rng_for("doce-chain-taut")
    dur = 0.65
    n = secs(dur)
    y = np.zeros(n)
    times = np.linspace(0.0, 0.035, 7) + rng.uniform(0, 0.002, 7)
    y += 0.6 * unit(chain_train(n, rng, times, np.linspace(0.4, 1.0, 7), 2100, 3900))
    clank = metal(n, rng, 820.0, PLATE, [1.0, 0.7, 0.5, 0.3, 0.2, 0.12, 0.06], [0.14, 0.11, 0.08, 0.06, 0.05, 0.04, 0.03],
                  beat=3.0, lp=6000, hp=300)
    place(y, clank, 0.038, 0.75)
    place(y, thump(secs(0.3), 140, 70, 0.012, 0.05), 0.038, 0.5)
    t = tvec(n)
    twang = np.sin(TAU * np.cumsum(pts(t, [(0, 95), (0.05, 82), (0.6, 78)])) / SR) * env_perc(n, 0.002, 0.2)
    place(y, filt(twang, [("lp", 600, 0.7)]), 0.04, 0.35)
    strain = creak(n, rng, [1350.0, 2300.0, 3400.0], [(0, 40), (0.6, 22)], [(0, 0), (0.05, 0), (0.08, 1.0), (0.45, 0.4),
                                                                              (0.6, 0.0)], q=10.0)
    y += 0.22 * strain
    y = wet(y, "small", 0.14)
    return finish(y, dur, -3.0, fade_out=0.12)


def chain_zip() -> np.ndarray:
    """Heracles yanked along his chain to a bronze ring: a rising rush of wind and a whirring chain."""
    rng = rng_for("doce-chain-zip")
    dur = 1.0
    n = secs(dur)
    y = np.zeros(n)
    rush = whoosh(n, rng, [(0, 260), (0.55, 1500), (0.85, 2200), (1.0, 1200)],
                  [(0, 0), (0.08, 0.35), (0.55, 0.85), (0.82, 1.0), (1.0, 0.0)], width=0.6, lp=7000, hp=80, nfft=1024)
    y += 1.0 * unit(rush)
    body = whoosh(n, rng, [(0, 120), (0.85, 420)], [(0, 0), (0.1, 0.6), (0.8, 1.0), (1.0, 0)], width=0.9, nfft=2048, hp=40)
    y += 0.4 * unit(body)
    times, t = [], 0.02
    while t < 0.9:
        times.append(t)
        t += 0.026 * (1.0 - 0.75 * t / 0.9) + rng.uniform(0, 0.003)
    times = np.array(times)
    amps = np.clip(0.3 + 0.7 * times / 0.85, 0.0, 1.0)
    y += 0.4 * unit(chain_train(n, rng, times, amps, 1900, 3600, pitch=lambda tt: 1.0 + 0.25 * tt))
    y = wet(y, "small", 0.1)
    return finish(y, dur, -3.0, fade_in=0.02, fade_out=0.08, lp=9000)


# ---------------------------------------------------------------------------
# The world
# ---------------------------------------------------------------------------

def boulder_thud() -> np.ndarray:
    """The great boulder comes to rest in the cave mouth: the ground answers, grit rains down."""
    rng = rng_for("doce-boulder-thud")
    dur = 2.0
    n = secs(dur)
    y = np.zeros(n)
    y += 1.0 * thump(n, 70, 30, 0.04, 0.32, attack=0.004)
    y += 0.7 * unit(burst(n, rng, 0.09, [("lp", 260, 0.7)], attack=0.003))
    for tt in np.sort(rng.uniform(0.0, 0.05, 6)):
        place(y, unit(burst(secs(0.08), rng, rng.uniform(0.004, 0.012), [("bp", rng.uniform(500, 1600), 1.2)])), tt,
              rng.uniform(0.2, 0.4))
    y += 0.55 * unit(rumble(n, rng, [(0, 0), (0.02, 1.0), (0.4, 0.6), (1.4, 0.0)], 90, 55))
    y += 0.35 * unit(debris(n, rng, 0.08, 46, 0.25, 400, 2400, 0.5))
    dust = whoosh(n, rng, [(0, 900), (1.5, 600)], [(0, 0), (0.1, 1), (1.4, 0)], width=1.2, lp=2500)
    y += 0.1 * unit(dust)
    y = wet(y, "cave", 0.3)
    return finish(y, dur, -3.0, fade_out=0.4, lp=7000)


def altar() -> np.ndarray:
    """An altar wakes: the brazier catches with a soft roar, a warm lyre chord, a choir breath, a bell."""
    rng = rng_for("doce-altar")
    dur = 2.4
    n = secs(dur)
    y = np.zeros(n)
    # fire catching: a rising "fwoomp" and a few crackles
    def mag(t, f):
        fc = pts(t, [(0, 260), (0.18, 1500), (0.6, 700), (1.5, 500)], log=True)
        g = pts(t, [(0, 0), (0.05, 0.6), (0.18, 1.0), (0.6, 0.35), (1.6, 0.0)])
        return g * mag_lp(f, fc, 1.6) * mag_hp(f, 60, 1.0) / np.sqrt(np.maximum(f, 60) / 60.0)
    y += 0.55 * unit(spectral_noise(n, mag, rng, nfft=1024))
    times = 0.15 + np.sort(rng.exponential(0.25, 22))
    y += 0.12 * unit(grain_cloud(n, rng, times, np.exp(-(times - 0.15) / 0.5), 1500, 4500, 0.0005, 0.002, q=1.6))
    # the chord (A major add9, the island's home key brightened)
    seq = [("A3", 0.16, 0.7), ("E4", 0.21, 0.72), ("A4", 0.26, 0.76), ("C#5", 0.31, 0.8), ("E5", 0.36, 0.78),
           ("B5", 0.43, 0.6)]
    ly = np.zeros(n)
    for nm, tt, vel in seq:
        place(ly, lyre_pluck(note(nm), rng, vel=vel, bright=0.55), tt, 1.0)
    y += 1.1 * unit(filt(ly, LYRE_BODY))
    ch = np.zeros(n)
    for nm, g in (("A3", 0.7), ("E4", 0.8), ("A4", 0.7), ("C#5", 0.55)):
        v = pad_note(note(nm), 1.0, rng, kind="choir", vowel=("a", "o", 0.4), voices=3, detune=8, vib_depth=8,
                     attack=0.5, release=0.9, breath=0.3).mean(axis=1)
        place(ch, v, 0.25, g)
    y += 0.4 * unit(ch)
    b = bell(note("A5"), rng, dur=2.0, decay=1.0, bright=0.5)
    place(y, unit(b), 0.42, 0.3)
    y = wet(y, "med", 0.35)
    return finish(y, dur, -3.0, fade_in=0.005, fade_out=0.45, lp=9000)


def body_fall_sfx() -> np.ndarray:
    rng = rng_for("doce-body-fall")
    y = body_fall(rng, 1.0, 0.7)
    y = wet(y, "small", 0.12)
    return finish(y, 0.65, -4.0, fade_out=0.12)


def splash() -> np.ndarray:
    rng = rng_for("splash")
    n = secs(0.9)
    y = np.zeros(n)
    k = secs(0.12)
    t = tvec(k)
    plop = np.sin(TAU * np.cumsum(260 + 700 * (1 - np.exp(-t / 0.012))) / SR) * env_perc(k, 0.0015, 0.028)
    place(y, plop, 0.0, 0.55)

    def mag(t, f):
        fc = pts(t, [(0, 900), (0.4, 1700)], log=True)
        g = pts(t, [(0, 0), (0.008, 1.0), (0.05, 0.75), (0.2, 0.35), (0.6, 0.06), (0.8, 0)])
        return g * mag_band(f, fc, 1.0) * mag_lp(f, 4200, 2) * mag_hp(f, 150, 1)
    body = unit(spectral_noise(n, mag, rng, nfft=512))
    y += 0.8 * body
    times = np.sort(np.concatenate([rng.uniform(0.04, 0.25, 18), rng.uniform(0.15, 0.65, 16)]))
    drops = bubbles(n, rng, times, 600, 2200, 0.003, 0.012, 1.5, amp=np.exp(-(times - 0.04) / 0.3))
    y += 0.4 * unit(drops)
    y += 0.4 * unit(burst(n, rng, 0.06, [("lp", 320, 0.7)], attack=0.002))
    y = wet(y, "small", 0.15)
    return finish(y, 0.8, -3.0, fade_in=0.001, fade_out=0.15, lp=6500)


def swim() -> np.ndarray:
    """One swimming stroke: an arm through the water."""
    rng = rng_for("doce-swim")
    n = secs(0.7)
    def mag(t, f):
        fc = pts(t, [(0, 600), (0.25, 1300), (0.6, 800)], log=True)
        g = pts(t, [(0, 0), (0.08, 0.7), (0.22, 1.0), (0.5, 0.2), (0.65, 0)])
        return g * mag_band(f, fc, 0.9) * mag_lp(f, 4000, 2) * mag_hp(f, 120, 1)
    y = unit(spectral_noise(n, mag, rng, nfft=512))
    times = np.sort(rng.uniform(0.15, 0.55, 14))
    y += 0.3 * unit(bubbles(n, rng, times, 500, 1600, 0.004, 0.015, 1.2))
    y = wet(y, "small", 0.12)
    return finish(y, 0.65, -8.0, fade_in=0.01, fade_out=0.12, lp=6000)


def gull() -> np.ndarray:
    rng = rng_for("gull")
    n = secs(0.7)
    t = tvec(n)
    f0 = pts(t, [(0, 820), (0.07, 1180), (0.16, 1120), (0.36, 720), (0.42, 660)], log=True)
    f0 *= 1 + 0.008 * smooth_random(n, rng, 20)
    ph = TAU * np.cumsum(f0) / SR
    out = np.zeros(n)
    for k, a in enumerate((1.0, 0.9, 0.45, 0.25, 0.12, 0.06), start=1):
        fk = k * f0
        out += a * mag_band(fk, 2100, 1.0) * np.sin(k * ph + rng.uniform(0, TAU))
    rough = 1 + 0.25 * np.sin(TAU * 78 * t)
    env = env_points(n, [(0, 0), (0.03, 0.8), (0.08, 1.0), (0.3, 0.75), (0.42, 0.0)])
    y = unit(out) * rough * env
    y += 0.08 * unit(whoosh(n, rng, [(0, 2000), (0.4, 1500)], [(0, 0), (0.05, 1), (0.4, 0)], width=0.7, lp=5000))
    y = filt(y, [("lp", 3600, 0.7), ("hp", 350, 0.7)])
    y = wet(y, "med", 0.45)
    return finish(y, 0.6, -10.0, fade_in=0.004, fade_out=0.12, lp=6000)


def cat_purr() -> np.ndarray:
    """Purr, 2.0 s, perfect loop (50 pulses at 25 Hz, periodic breathing)."""
    rng = rng_for("cat_purr")
    n = secs(2.0)
    t = tvec(n)
    period = n // 50
    k = np.arange(n) % period
    w = int(period * 0.45)
    pulse = np.where(k < w, np.sin(np.pi * k / w) ** 2, 0.0)
    nz = rng.standard_normal(n)
    src = pulse * (0.55 + 0.45 * nz) + 0.15 * nz
    body = filt(src, [("peak", 190, 1.8, 9.0), ("peak", 440, 2.0, 5.0), ("lp", 900, 0.7), ("hp", 45, 0.7)],
                circular=True)
    u = t / 2.0
    breath_env = np.where(u < 0.4, 0.62 * np.clip(np.sin(np.pi * u / 0.4), 0, None) ** 0.7,
                          np.clip(np.sin(np.pi * (u - 0.4) / 0.6), 0, None) ** 0.6)
    breath_env = 0.12 + 0.88 * breath_env
    air = filt(rng.standard_normal(n), [("lp", 1600, 0.7), ("hp", 200, 0.7)], circular=True)
    y = unit(body) * breath_env + 0.06 * unit(air) * breath_env
    y = filt(y, [("hp", 30, 0.7), ("lp", 2500, 0.7)], circular=True)
    return normalize_peak(y, -3.0)


def cat_meow() -> np.ndarray:
    """Closed-mouth "mrrp": a rising chirp with a rolled trill."""
    rng = rng_for("cat_meow")
    n = secs(0.45)
    t = tvec(n)
    f0 = pts(t, [(0, 500), (0.1, 560), (0.24, 760), (0.31, 720), (0.36, 690)], log=True)
    f0 *= 1 + 0.006 * smooth_random(n, rng, 14)
    ph = TAU * np.cumsum(f0) / SR
    open_ = env_points(n, [(0, 0.0), (0.16, 0.1), (0.27, 1.0), (0.32, 0.6), (0.36, 0.0)])
    F1 = 450 + 550 * open_
    out = np.zeros(n)
    for k in range(1, 9):
        fk = k * f0
        a = (0.42 ** (k - 1)) * (0.35 + 0.65 * mag_reso(fk, F1, 260)) * (1 + 0.6 * open_ * (k > 1))
        out += a * np.sin(k * ph + rng.uniform(0, TAU))
    trill_depth = env_points(n, [(0, 0.8), (0.17, 0.75), (0.25, 0.0)])
    trill = 1.0 - trill_depth * (0.5 + 0.5 * np.sin(TAU * 27 * t))
    env = env_points(n, [(0, 0), (0.025, 0.55), (0.12, 0.8), (0.27, 1.0), (0.335, 0.7), (0.36, 0.0)])
    y = unit(out) * trill * env
    breath = whoosh(n, rng, [(0, 1300), (0.36, 1700)], [(0, 0), (0.03, 0.6), (0.27, 1), (0.36, 0)], width=0.7, lp=4500)
    y += 0.05 * unit(breath)
    y = filt(y, [("hp", 200, 0.7), ("lp", 5000, 0.7)])
    y = wet(y, "small", 0.1)
    return finish(y, 0.4, -3.0, fade_in=0.003, fade_out=0.04, lp=6000)


# ---------------------------------------------------------------------------
# Interface (tuned to A, the island's key)
# ---------------------------------------------------------------------------

def ui_move() -> np.ndarray:
    rng = rng_for("ui_move")
    n = secs(0.1)
    y = damped_modes(n, [1180, 2650, 620], [1.0, 0.3, 0.45], [0.012, 0.006, 0.01], attack=0.0008, rng=rng)
    y = filt(y, [("lp", 4500, 0.7)])
    return finish(y, 0.08, -6.0, fade_in=0.0005, fade_out=0.02)


def ui_select() -> np.ndarray:
    rng = rng_for("doce-ui-select")
    n = secs(0.35)
    y = np.zeros(n)
    place(y, lyre_pluck(note("E5"), rng, vel=0.85, t60=0.55, bright=0.5), 0.0, 1.0)
    place(y, lyre_pluck(note("A5"), rng, vel=0.6, t60=0.45, bright=0.45), 0.018, 0.45)
    y = filt(y, LYRE_BODY)
    y = wet(unit(y), "small", 0.15)
    return finish(y, 0.25, -4.0, fade_in=0.0005, fade_out=0.08)


def ui_back() -> np.ndarray:
    rng = rng_for("doce-ui-back")
    n = secs(0.3)
    y = pad_to(lyre_pluck(note("A4"), rng, vel=0.8, t60=0.45, bright=0.35), n)
    y = filt(y, LYRE_BODY)
    y = wet(unit(y), "small", 0.12)
    return finish(y, 0.2, -4.0, fade_in=0.0005, fade_out=0.07)


def ui_lock() -> np.ndarray:
    """Lock-on: two small bronze ticks closing on the target."""
    rng = rng_for("doce-ui-lock")
    n = secs(0.25)
    y = np.zeros(n)
    place(y, metal(secs(0.12), rng, 1980.0, BAR, [1.0, 0.22, 0.0, 0.0], [0.03, 0.015, 0.008, 0.005], beat=1.0, lp=5500,
                   hp=600), 0.0, 0.6)
    place(y, metal(secs(0.2), rng, 2640.0, BAR, [1.0, 0.18, 0.0, 0.0], [0.06, 0.025, 0.01, 0.005], beat=1.0, lp=6000,
                   hp=600), 0.055, 1.0)
    y = wet(y, "small", 0.1)
    return finish(y, 0.22, -7.0, fade_out=0.05)


def ui_unlock() -> np.ndarray:
    rng = rng_for("doce-ui-unlock")
    n = secs(0.16)
    y = metal(n, rng, 1760.0, BAR, [1.0, 0.2, 0.0, 0.0], [0.035, 0.015, 0.008, 0.004], beat=1.0, lp=5000, hp=500)
    return finish(y, 0.14, -10.0, fade_out=0.04)


def ui_toast() -> np.ndarray:
    """A message appears: one soft lyre harmonic."""
    rng = rng_for("doce-ui-toast")
    n = secs(0.6)
    y = pad_to(lyre_pluck(note("E6"), rng, vel=0.6, t60=0.9, bright=0.3), n)
    y += 0.3 * pad_to(lyre_pluck(note("B6"), rng, vel=0.4, t60=0.6, bright=0.25), n)
    y = filt(y, LYRE_BODY + [("hp", 600, 0.7)])
    y = wet(unit(y), "small", 0.25)
    return finish(y, 0.55, -9.0, fade_in=0.001, fade_out=0.2)


def ui_card() -> np.ndarray:
    """The labour card unrolls: a great frame drum, a low strum in E Phrygian, a shimmer of cymbal."""
    rng = rng_for("doce-ui-card")
    dur = 3.2
    n = secs(dur)
    y = np.zeros(n)
    drum = frame_drum("big", rng, vel=1.0, size=1.1)
    place(y, drum, 0.0, 1.0)
    place(y, frame_drum("dum", rng, vel=0.7), 0.0, 0.5)
    ly = np.zeros(n)
    for i, nm in enumerate(["E2", "B2", "E3", "F3", "B3", "E4"]):
        place(ly, lyre_pluck(note(nm), rng, vel=0.75 + 0.03 * i, bright=0.5), 0.05 + 0.045 * i, 1.0)
    for i, nm in enumerate(["G#4", "B4", "E5"]):
        place(ly, lyre_pluck(note(nm), rng, vel=0.6, bright=0.55), 0.62 + 0.07 * i, 0.7)
    y += 1.0 * unit(filt(ly, LYRE_BODY)) * 0.8
    def mag(t, f):
        g = pts(t, [(0, 0), (0.6, 0.15), (1.1, 1.0), (2.4, 0.0)])
        return g * (0.6 * mag_band(f, 4200, 0.6) + 0.4 * mag_band(f, 6500, 0.4)) * mag_lp(f, 8500, 3)
    y += 0.07 * unit(spectral_noise(n, mag, rng, nfft=1024))
    v = pad_note(note("E3"), 1.6, rng, kind="choir", vowel="o", voices=3, detune=8, vib_depth=6, attack=0.6, release=1.2,
                 breath=0.3).mean(axis=1)
    place(y, unit(v), 0.3, 0.22)
    y = wet(y, "big", 0.3)
    return finish(y, dur, -3.0, fade_in=0.002, fade_out=0.6, lp=8500)


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

SFX = {
    "swing_1": lambda: swing(1),
    "swing_2": lambda: swing(2),
    "swing_3": lambda: swing(3),
    "swing_heavy": swing_heavy,
    "hit_1": lambda: hit_flesh(1),
    "hit_2": lambda: hit_flesh(2),
    "hit_3": lambda: hit_flesh(3),
    "hit_heavy": hit_heavy,
    "blade_bounce": blade_bounce,
    "shield_block": shield_block,
    "parry": parry,
    "dodge": dodge_roll,
    "hero_hurt": hero_hurt,
    "hero_down": hero_death,
    "jump": jump,
    "land": land,
    "chain_throw": chain_throw,
    "chain_stick": chain_stick,
    "chain_rattle": chain_rattle,
    "chain_taut": chain_taut,
    "chain_zip": chain_zip,
    "boulder_thud": boulder_thud,
    "altar": altar,
    "body_fall": body_fall_sfx,
    "splash": splash,
    "swim": swim,
    "gull": gull,
    "cat_purr": cat_purr,
    "cat_meow": cat_meow,
    "ui_move": ui_move,
    "ui_select": ui_select,
    "ui_back": ui_back,
    "ui_lock": ui_lock,
    "ui_unlock": ui_unlock,
    "ui_toast": ui_toast,
    "ui_card": ui_card,
}
SFX["footstep"] = lambda: step("earth", 2)
for _s in ("grass", "stone", "sand"):
    for _v in (1, 2, 3):
        SFX[f"step_{_s}_{_v}"] = (lambda s=_s, v=_v: step(s, v))

LOOPING_SFX = {"cat_purr"}
