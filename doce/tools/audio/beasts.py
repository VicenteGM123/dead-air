"""DOCE beasts (mono): wolves, boars, the Nemean Lion and the wrestle.

Voices are additive (glottal series through moving formants, with subharmonic roughness for growls and roars;
clean harmonic series with vibrato for howls, yelps and squeals) layered with breath, body impacts and a little
room. Nothing is sampled.
"""
from __future__ import annotations

import numpy as np

from common import (body_fall, burst, creak, debris, finish, grain_cloud, growl_voice, hoof, link_clink, metal,
                    paw, place, pts, rumble, snort_burst, thump, tonal_voice, unit, wet, whoosh, PLATE)
from dsp import SR, TAU, damped_modes, env_perc, env_points, filt, lp4, rng_for, secs, smooth_random, tvec

# ---------------------------------------------------------------------------
# Wolves
# ---------------------------------------------------------------------------


def wolf_growl() -> np.ndarray:
    """A low snarl from the pack while it circles: rough, close, menacing."""
    rng = rng_for("doce-wolf-growl")
    dur = 1.4
    n = secs(dur)
    v = growl_voice(n, rng, [(0, 92), (0.3, 104), (0.8, 98), (1.3, 86)],
                    [(0, 420, 1050, 2400), (0.4, 520, 1250, 2600), (1.0, 480, 1150, 2500), (1.3, 400, 1000, 2400)],
                    rough=0.75, jitter=0.035, breath=0.45, lp=3200, vowel_bw=1.2)
    env = env_points(n, [(0, 0), (0.12, 0.7), (0.3, 1.0), (0.6, 0.8), (0.9, 1.0), (1.3, 0.0)])
    # the growl pulses with the breath
    t = tvec(n)
    pulse = 0.75 + 0.25 * np.sin(TAU * 3.2 * t + 1.0)
    y = unit(v) * env * pulse
    y = wet(y, "small", 0.12)
    return finish(y, dur, -3.0, fade_in=0.01, fade_out=0.12, lp=5000)


def wolf_howl() -> np.ndarray:
    """A long howl from far up the forest: rises, holds with a slow vibrato, sinks away."""
    rng = rng_for("doce-wolf-howl")
    dur = 3.4
    n = secs(dur)
    f0 = [(0, 360), (0.35, 520), (0.7, 600), (1.6, 610), (2.2, 585), (2.6, 520), (2.95, 430)]
    harm = [1.0, 0.32, 0.12, 0.05, 0.02]
    v = tonal_voice(n, rng, f0, harm, form_pts=[(0, 500, 900), (0.6, 750, 1250), (2.0, 700, 1150), (2.9, 450, 800)],
                    vib_rate=5.2, vib_cents=[(0, 0), (0.8, 6), (1.6, 18), (2.6, 12), (2.95, 4)], jitter=0.003,
                    breath=0.06, lp=4500, breath_band=1500)
    env = env_points(n, [(0, 0), (0.25, 0.55), (0.6, 1.0), (2.2, 0.9), (2.75, 0.45), (3.0, 0.0)])
    y = v * env
    # a second wolf answering a third above, further away
    v2 = tonal_voice(n, rng, [(0, 430), (0.5, 640), (1.1, 720), (1.8, 700), (2.4, 560)], harm,
                     vib_rate=4.8, vib_cents=[(0, 0), (1.0, 14), (2.4, 8)], jitter=0.003, breath=0.08, lp=3500)
    env2 = env_points(n, [(0, 0), (0.9, 0), (1.3, 0.5), (2.2, 0.45), (2.7, 0.0)])
    y = y + 0.38 * filt(v2 * env2, [("lp", 2500, 0.7)])
    y = wet(unit(y), "big", 0.6)
    return finish(y, dur, -5.0, fade_in=0.02, fade_out=0.5, lp=6000)


def wolf_bite() -> np.ndarray:
    """A lunge and a snap of jaws: short snarl, the clack of teeth, a heavy chomp."""
    rng = rng_for("doce-wolf-bite")
    dur = 0.45
    n = secs(dur)
    y = np.zeros(n)
    sn = growl_voice(secs(0.2), rng, [(0, 120), (0.15, 150)], [(0, 600, 1400, 2700), (0.15, 700, 1600, 2800)],
                     rough=0.8, jitter=0.04, breath=0.6, lp=3600)
    place(y, unit(sn) * env_points(secs(0.2), [(0, 0), (0.04, 1.0), (0.15, 0.8), (0.2, 0.0)]), 0.0, 0.6)
    clack = damped_modes(secs(0.1), [1850, 3100, 4300], [1.0, 0.6, 0.3], [0.012, 0.008, 0.005], attack=0.0003, rng=rng)
    clack += 0.6 * unit(burst(secs(0.1), rng, 0.002, [("hp", 1500, 0.7)], attack=0.0002))
    place(y, unit(clack), 0.15, 0.9)
    place(y, thump(secs(0.2), 160, 90, 0.008, 0.03), 0.152, 0.5)
    place(y, unit(burst(secs(0.15), rng, 0.02, [("bp", 900, 1.0)])), 0.16, 0.3)
    y = wet(y, "small", 0.1)
    return finish(y, dur, -3.0, fade_out=0.08, lp=8000)


def wolf_yelp() -> np.ndarray:
    """A wolf takes a blow: a short high yelp that breaks downwards."""
    rng = rng_for("doce-wolf-yelp")
    dur = 0.45
    n = secs(dur)
    v = tonal_voice(n, rng, [(0, 900), (0.035, 1320), (0.12, 1180), (0.3, 640)], [1.0, 0.55, 0.3, 0.16, 0.08, 0.04],
                    form_pts=[(0, 900, 1800), (0.1, 1100, 2100), (0.3, 700, 1400)], jitter=0.01, rough=0.25,
                    breath=0.12, lp=5000, breath_band=2200)
    env = env_points(n, [(0, 0), (0.012, 1.0), (0.1, 0.85), (0.3, 0.0)])
    y = v * env
    y = wet(y, "small", 0.15)
    return finish(y, dur, -4.0, fade_in=0.001, fade_out=0.08, lp=6500)


def wolf_die() -> np.ndarray:
    """A falling whimper and the body dropping into the grass."""
    rng = rng_for("doce-wolf-die")
    dur = 1.1
    n = secs(dur)
    y = np.zeros(n)
    v = tonal_voice(secs(0.7), rng, [(0, 820), (0.08, 980), (0.45, 520), (0.65, 380)], [1.0, 0.4, 0.18, 0.07],
                    form_pts=[(0, 800, 1600), (0.6, 600, 1100)], vib_rate=9.0, vib_cents=[(0, 10), (0.6, 30)],
                    jitter=0.012, rough=0.15, breath=0.25, lp=4500)
    place(y, v * env_points(secs(0.7), [(0, 0), (0.02, 1.0), (0.35, 0.6), (0.65, 0.0)]), 0.0, 0.7)
    place(y, body_fall(rng, 0.8, 0.6), 0.32, 0.9)
    y = wet(y, "small", 0.15)
    return finish(y, dur, -3.0, fade_out=0.15)


# ---------------------------------------------------------------------------
# Boars
# ---------------------------------------------------------------------------


def boar_snort() -> np.ndarray:
    """Two hard snorts through the snout and a low grunt: a boar in a clearing has seen you."""
    rng = rng_for("doce-boar-snort")
    dur = 0.8
    n = secs(dur)
    y = snort_burst(n, rng, 0.0, 0.16, 0.8) + snort_burst(n, rng, 0.24, 0.22, 1.0, 380, 1150)
    gr = growl_voice(secs(0.32), rng, [(0, 120), (0.15, 132), (0.3, 105)], [(0, 450, 900, 2200), (0.3, 380, 800, 2100)],
                     rough=0.7, jitter=0.04, breath=0.35, lp=2400)
    place(y, unit(gr) * env_points(secs(0.32), [(0, 0), (0.04, 1), (0.22, 0.7), (0.32, 0)]), 0.42, 0.55)
    y = wet(y, "small", 0.1)
    return finish(y, dur, -3.0, fade_in=0.002, fade_out=0.1, lp=6000)


def boar_charge() -> np.ndarray:
    """The charge: a shrill squeal, then hooves drumming the ground, coming hard."""
    rng = rng_for("doce-boar-charge")
    dur = 1.8
    n = secs(dur)
    y = np.zeros(n)
    sq = tonal_voice(secs(0.6), rng, [(0, 1050), (0.08, 1450), (0.3, 1380), (0.55, 980)],
                     [1.0, 0.8, 0.55, 0.4, 0.25, 0.15, 0.08], form_pts=[(0, 1400, 2600), (0.4, 1200, 2300)],
                     vib_rate=11.0, vib_cents=[(0, 20), (0.5, 35)], jitter=0.02, rough=0.55, breath=0.2, lp=5000)
    place(y, unit(sq) * env_points(secs(0.6), [(0, 0), (0.03, 1.0), (0.35, 0.8), (0.58, 0.0)]), 0.0, 0.55)
    # gallop: four hooves per stride, strides speeding up
    t, stride = 0.32, 0.36
    while t < dur - 0.15:
        for k, off in enumerate((0.0, 0.05, 0.13, 0.17)):
            tt = t + off * stride / 0.36
            if tt < dur - 0.1:
                g = (0.55 + 0.45 * min(1.0, (t - 0.3) / 0.8)) * (1.0 if k % 2 == 0 else 0.75) * rng.uniform(0.8, 1.0)
                place(y, hoof(rng), tt, g)
        t += stride
        stride = max(0.24, stride * 0.93)
    y += 0.35 * unit(rumble(n, rng, [(0, 0), (0.35, 0.3), (1.6, 1.0), (1.8, 0.6)], 120, 80))
    for tt in (0.6, 1.1, 1.45):
        gr = growl_voice(secs(0.18), rng, [(0, 140), (0.16, 120)], [(0, 500, 1000, 2300), (0.16, 450, 900, 2200)],
                         rough=0.8, breath=0.5, lp=2500)
        place(y, unit(gr) * env_points(secs(0.18), [(0, 0), (0.02, 1), (0.16, 0)]), tt, 0.25)
    y = wet(y, "small", 0.1)
    return finish(y, dur, -3.0, fade_in=0.002, fade_out=0.15, lp=7000)


def boar_gore() -> np.ndarray:
    """The tusks connect: a heavy thump, a grunt of effort, a flesh smack."""
    rng = rng_for("doce-boar-gore")
    dur = 0.6
    n = secs(dur)
    y = np.zeros(n)
    y += 1.0 * thump(n, 120, 50, 0.02, 0.09)
    y += 0.6 * unit(burst(n, rng, 0.03, [("bp", 700, 0.9), ("lp", 2500, 0.7)]))
    gr = growl_voice(secs(0.35), rng, [(0, 150), (0.1, 165), (0.3, 120)], [(0, 520, 1050, 2300), (0.3, 420, 900, 2200)],
                     rough=0.8, jitter=0.04, breath=0.45, lp=2600)
    place(y, unit(gr) * env_points(secs(0.35), [(0, 0), (0.02, 1), (0.2, 0.7), (0.35, 0)]), 0.0, 0.6)
    y = wet(y, "small", 0.12)
    return finish(y, dur, -3.0, fade_out=0.1)


def boar_crash() -> np.ndarray:
    """A charging boar meets a rock: the crack of skull on stone, grit, a dazed grunt."""
    rng = rng_for("doce-boar-crash")
    dur = 1.1
    n = secs(dur)
    y = np.zeros(n)
    y += 1.0 * thump(n, 110, 45, 0.02, 0.12)
    for tt in np.sort(rng.uniform(0.0, 0.03, 5)):
        place(y, unit(burst(secs(0.06), rng, rng.uniform(0.003, 0.008), [("bp", rng.uniform(800, 2200), 1.2)])), tt, 0.4)
    y += 0.3 * unit(debris(n, rng, 0.03, 26, 0.12, 500, 2600, 0.25))
    daze = growl_voice(secs(0.6), rng, [(0, 130), (0.3, 105), (0.55, 85)], [(0, 450, 900, 2200), (0.5, 380, 750, 2100)],
                       rough=0.6, breath=0.45, lp=2200)
    place(y, unit(daze) * env_points(secs(0.6), [(0, 0), (0.05, 0.8), (0.4, 0.5), (0.6, 0)]), 0.35, 0.4)
    y = wet(y, "med", 0.15)
    return finish(y, dur, -3.0, fade_out=0.15)


def boar_die() -> np.ndarray:
    rng = rng_for("doce-boar-die")
    dur = 1.3
    n = secs(dur)
    y = np.zeros(n)
    sq = tonal_voice(secs(0.8), rng, [(0, 1250), (0.1, 1350), (0.5, 760), (0.75, 520)],
                     [1.0, 0.75, 0.5, 0.32, 0.2, 0.1], form_pts=[(0, 1300, 2500), (0.7, 900, 1800)],
                     vib_rate=12.0, vib_cents=[(0, 25), (0.7, 45)], jitter=0.025, rough=0.5, breath=0.25, lp=4800)
    place(y, unit(sq) * env_points(secs(0.8), [(0, 0), (0.02, 1.0), (0.4, 0.6), (0.78, 0.0)]), 0.0, 0.6)
    place(y, body_fall(rng, 1.3, 0.7), 0.45, 1.0)
    y = wet(y, "small", 0.12)
    return finish(y, dur, -3.0, fade_out=0.2)


# ---------------------------------------------------------------------------
# The Nemean Lion
# ---------------------------------------------------------------------------


def lion_growl() -> np.ndarray:
    """The Lion's low growl in the dark of the cave: you feel it before you hear it."""
    rng = rng_for("doce-lion-growl")
    dur = 2.0
    n = secs(dur)
    v = growl_voice(n, rng, [(0, 58), (0.5, 70), (1.2, 66), (1.8, 54)],
                    [(0, 300, 700, 2000), (0.6, 420, 860, 2100), (1.4, 380, 800, 2000), (1.9, 300, 680, 1900)],
                    rough=0.7, jitter=0.03, breath=0.4, lp=2200, vowel_bw=1.3)
    env = env_points(n, [(0, 0), (0.25, 0.6), (0.6, 1.0), (1.3, 0.85), (1.85, 0.0)])
    t = tvec(n)
    sub = np.sin(TAU * np.cumsum(pts(t, [(0, 32), (0.6, 36), (1.8, 29)])) / SR) * env
    y = unit(v) * env + 0.35 * sub
    y = wet(unit(y), "cave", 0.3)
    return finish(y, dur, -3.0, fade_in=0.02, fade_out=0.25, lp=4500)


def lion_roar() -> np.ndarray:
    """The great roar (and its shock wave): a rising bellow, a huge rough sustain, two sobbing falls, the cave answering."""
    rng = rng_for("doce-lion-roar")
    dur = 3.4
    n = secs(dur)
    y = np.zeros(n)
    f0 = [(0, 85), (0.25, 150), (0.55, 185), (1.2, 175), (1.7, 140), (2.1, 105), (2.5, 80)]
    form = [(0, 450, 900, 2200), (0.4, 700, 1200, 2500), (1.2, 760, 1250, 2600), (1.9, 600, 1050, 2300),
            (2.5, 420, 800, 2100)]
    main = growl_voice(n, rng, f0, form, rough=0.55, jitter=0.03, breath=0.45, lp=3000, vowel_bw=1.4)
    env = env_points(n, [(0, 0), (0.18, 0.55), (0.45, 1.0), (1.4, 0.9), (1.75, 0.65), (2.1, 0.5), (2.6, 0.0)])
    y += unit(main) * env
    low = growl_voice(n, rng, [(t, f * 0.5) for t, f in f0], [(p[0], p[1] * 0.75, p[2] * 0.8, p[3]) for p in form],
                      rough=0.75, jitter=0.03, breath=0.2, lp=1800, vowel_bw=1.5)
    y += 0.4 * unit(low) * env
    t = tvec(n)
    sub = np.sin(TAU * np.cumsum(pts(t, [(0, 42), (0.5, 50), (2.5, 38)])) / SR) * env
    y += 0.12 * sub
    # the shock wave: a low push of air at the peak
    y += 0.15 * unit(rumble(n, rng, [(0, 0), (0.35, 0.0), (0.55, 1.0), (1.6, 0.4), (2.6, 0.0)], 80, 55))
    # presence: lift the formant region so the roar reads on small speakers
    y = filt(y, [("hp", 45, 0.7), ("peak", 900, 0.8, 4.0), ("peak", 2200, 1.0, 2.0)])
    y = wet(unit(y), "cave", 0.45)
    return finish(y, dur, -2.5, fade_in=0.02, fade_out=0.6, lp=5000)


def lion_swipe() -> np.ndarray:
    """A paw the size of a shield sweeps past: deep whoosh and three claws raking the air."""
    rng = rng_for("doce-lion-swipe")
    dur = 0.6
    n = secs(dur)
    gain = [(0, 0), (0.08, 0.4), (0.18, 1.0), (0.26, 0.5), (0.5, 0)]
    y = unit(whoosh(n, rng, [(0, 220), (0.18, 700), (0.5, 240)], gain, width=0.6, hp=60, nfft=1024))
    y += 0.4 * unit(whoosh(n, rng, [(0, 900), (0.18, 2200), (0.5, 900)], gain, width=0.4, lp=6000))
    t = tvec(n)
    y += 0.25 * unit(np.sin(TAU * np.cumsum(pts(t, [(0, 55), (0.18, 80), (0.5, 50)])) / SR) * env_points(n, gain))
    for k in range(3):
        tt = 0.15 + 0.022 * k
        cl = whoosh(secs(0.08), rng, [(0, 4200), (0.08, 3000)], [(0, 0), (0.005, 1), (0.05, 0.3), (0.08, 0)], width=0.25,
                    lp=8000)
        place(y, unit(cl), tt, 0.22)
    gr = growl_voice(secs(0.35), rng, [(0, 95), (0.3, 80)], [(0, 500, 950, 2300), (0.3, 420, 820, 2200)], rough=0.8,
                     breath=0.5, lp=2400)
    place(y, unit(gr) * env_points(secs(0.35), [(0, 0), (0.05, 1), (0.3, 0)]), 0.05, 0.3)
    y = wet(y, "cave", 0.12)
    return finish(y, dur, -3.0, fade_in=0.004, fade_out=0.08)


def lion_land() -> np.ndarray:
    """The pounce lands: front paws, then the hind, a body of stone-heavy weight, dust."""
    rng = rng_for("doce-lion-land")
    dur = 1.0
    n = secs(dur)
    y = np.zeros(n)
    place(y, paw(rng, 3.5, 0.5), 0.0, 1.0)
    place(y, paw(rng, 3.0, 0.5), 0.07, 0.85)
    y += 0.6 * thump(n, 75, 35, 0.03, 0.18, attack=0.003)
    y += 0.4 * unit(rumble(n, rng, [(0, 0), (0.02, 1.0), (0.5, 0.3), (0.9, 0.0)], 100, 60))
    y += 0.18 * unit(debris(n, rng, 0.03, 26, 0.12, 900, 3200, 0.2))
    dust = whoosh(n, rng, [(0, 1200), (0.9, 700)], [(0, 0), (0.03, 1), (0.6, 0)], width=1.2, lp=3000)
    y += 0.15 * unit(dust)
    y = wet(y, "cave", 0.22)
    return finish(y, dur, -3.0, fade_out=0.2, lp=7000)


def lion_thud() -> np.ndarray:
    """The Lion slams into a pillar and is stunned: the stone groans, grit rains, a dazed rumble."""
    rng = rng_for("doce-lion-thud")
    dur = 1.8
    n = secs(dur)
    y = np.zeros(n)
    y += 1.0 * thump(n, 85, 32, 0.03, 0.26, attack=0.003)
    y += 0.6 * unit(burst(n, rng, 0.06, [("lp", 300, 0.7)]))
    for tt in np.sort(rng.uniform(0.0, 0.04, 8)):
        place(y, unit(burst(secs(0.08), rng, rng.uniform(0.004, 0.012), [("bp", rng.uniform(600, 1800), 1.2)])), tt, 0.35)
    stone = damped_modes(n, [150, 255, 410, 620], [1.0, 0.6, 0.35, 0.2], [0.35, 0.22, 0.14, 0.09], attack=0.002, rng=rng,
                         beat=0.8)
    y += 0.35 * unit(filt(stone, [("lp", 1500, 0.7)]))
    y += 0.4 * unit(debris(n, rng, 0.06, 40, 0.3, 400, 2600, 0.6))
    daze = growl_voice(secs(0.9), rng, [(0, 75), (0.4, 62), (0.8, 50)], [(0, 380, 760, 2000), (0.8, 300, 650, 1900)],
                       rough=0.6, breath=0.5, lp=1800)
    place(y, unit(daze) * env_points(secs(0.9), [(0, 0), (0.1, 0.7), (0.5, 0.5), (0.9, 0)]), 0.55, 0.4)
    y = wet(y, "cave", 0.35)
    return finish(y, dur, -3.0, fade_out=0.35, lp=6500)


def lion_bite() -> np.ndarray:
    rng = rng_for("doce-lion-bite")
    dur = 0.6
    n = secs(dur)
    y = np.zeros(n)
    sn = growl_voice(secs(0.25), rng, [(0, 90), (0.2, 120)], [(0, 520, 1000, 2400), (0.2, 650, 1200, 2500)],
                     rough=0.8, jitter=0.04, breath=0.55, lp=2800)
    place(y, unit(sn) * env_points(secs(0.25), [(0, 0), (0.05, 1.0), (0.2, 0.9), (0.25, 0)]), 0.0, 0.7)
    clack = damped_modes(secs(0.12), [1150, 1950, 2900], [1.0, 0.6, 0.3], [0.018, 0.012, 0.008], attack=0.0004, rng=rng)
    clack += 0.5 * unit(burst(secs(0.12), rng, 0.003, [("hp", 1000, 0.7)], attack=0.0003))
    place(y, unit(clack), 0.2, 0.8)
    place(y, thump(secs(0.3), 120, 55, 0.012, 0.06), 0.2, 0.7)
    y = wet(y, "cave", 0.15)
    return finish(y, dur, -3.0, fade_out=0.1)


def lion_pain() -> np.ndarray:
    """Squeezed in the wrestle: a short pained roar that breaks."""
    rng = rng_for("doce-lion-pain")
    dur = 1.1
    n = secs(dur)
    v = growl_voice(n, rng, [(0, 120), (0.12, 175), (0.4, 160), (0.8, 95)],
                    [(0, 600, 1100, 2400), (0.3, 800, 1300, 2600), (0.8, 500, 950, 2300)], rough=0.6, jitter=0.035,
                    breath=0.5, lp=3000, vowel_bw=1.3)
    env = env_points(n, [(0, 0), (0.05, 0.9), (0.2, 1.0), (0.55, 0.6), (0.9, 0.0)])
    y = unit(v) * env
    y = wet(y, "cave", 0.3)
    return finish(y, dur, -3.0, fade_in=0.004, fade_out=0.2, lp=5000)


def lion_thrash() -> np.ndarray:
    """In the wrestle the Lion throws its weight about: heavy rushes of air and a snarl."""
    rng = rng_for("doce-lion-thrash")
    dur = 1.0
    n = secs(dur)
    y = np.zeros(n)
    for k, tt in enumerate((0.0, 0.28, 0.52)):
        m = secs(0.35)
        w = whoosh(m, rng, [(0, 180), (0.15, 520), (0.35, 200)], [(0, 0), (0.12, 1.0), (0.33, 0)], width=0.7, hp=50)
        place(y, unit(w), tt, 0.8 - 0.15 * k)
    gr = growl_voice(n, rng, [(0, 85), (0.4, 105), (0.9, 80)], [(0, 480, 950, 2300), (0.5, 600, 1100, 2400),
                                                              (0.9, 450, 900, 2200)], rough=0.85, breath=0.5, lp=2600)
    y += 0.55 * unit(gr) * env_points(n, [(0, 0), (0.08, 1.0), (0.7, 0.8), (0.95, 0.0)])
    y += 0.2 * unit(grain_cloud(n, rng, np.sort(rng.uniform(0.05, 0.8, 30)), 1.0, 900, 3000, 0.001, 0.003))
    y = wet(y, "cave", 0.2)
    return finish(y, dur, -3.0, fade_in=0.004, fade_out=0.15)


def lion_death() -> np.ndarray:
    """The Lion's last breath: a long groan that sinks, the great body settling on the cave floor."""
    rng = rng_for("doce-lion-death")
    dur = 3.4
    n = secs(dur)
    y = np.zeros(n)
    v = growl_voice(secs(2.4), rng, [(0, 110), (0.3, 130), (1.2, 85), (2.2, 48)],
                    [(0, 600, 1100, 2400), (0.6, 520, 950, 2300), (2.2, 300, 650, 1900)], rough=0.55, jitter=0.03,
                    breath=0.55, lp=2600, vowel_bw=1.3)
    place(y, unit(v) * env_points(secs(2.4), [(0, 0), (0.15, 0.9), (0.5, 1.0), (1.5, 0.5), (2.3, 0.0)]), 0.0, 0.8)
    place(y, body_fall(rng, 3.2, 1.2), 1.35, 1.0)
    y += 0.25 * unit(rumble(n, rng, [(0, 0), (1.35, 0.0), (1.45, 1.0), (2.6, 0.0)], 80, 50))
    exhale = whoosh(n, rng, [(0, 700), (3.2, 500)], [(0, 0), (2.4, 0), (2.6, 1.0), (3.3, 0)], width=1.0, lp=2500)
    y += 0.12 * unit(exhale)
    y = wet(y, "cave", 0.4)
    return finish(y, dur, -3.0, fade_in=0.01, fade_out=0.6, lp=5000)


# ---------------------------------------------------------------------------
# The wrestle
# ---------------------------------------------------------------------------


def wrestle_strain() -> np.ndarray:
    """Heracles holds on: leather creaking under strain, bronze shifting, feet grinding the floor, the Lion's
    growl pressed against him. Play it on every struggle beat (and loop it softly if wanted)."""
    rng = rng_for("doce-wrestle-strain")
    dur = 1.6
    n = secs(dur)
    y = np.zeros(n)
    y += 0.5 * creak(n, rng, [520.0, 980.0, 1700.0], [(0, 18), (0.5, 32), (1.0, 24), (1.5, 14)],
                     [(0, 0), (0.15, 0.8), (0.7, 1.0), (1.2, 0.7), (1.5, 0.0)], q=8.0)
    y += 0.3 * creak(n, rng, [760.0, 1400.0], [(0, 26), (1.5, 40)], [(0, 0), (0.4, 0.6), (1.0, 0.8), (1.5, 0.0)], q=7.0)
    scrape = whoosh(n, rng, [(0, 600), (1.5, 450)], [(0, 0), (0.2, 0.6), (0.6, 1.0), (1.1, 0.5), (1.5, 0)], width=1.0,
                    lp=2200, hp=80)
    y += 0.3 * unit(scrape)
    for tt in (0.3, 0.75, 1.15):
        place(y, link_clink(rng, rng.uniform(2200, 3000), 0.08), tt, 0.1)
    gr = growl_voice(n, rng, [(0, 70), (0.6, 82), (1.4, 72)], [(0, 380, 780, 2000), (0.7, 460, 880, 2100),
                                                             (1.4, 380, 760, 2000)], rough=0.8, breath=0.4, lp=2000)
    y += 0.55 * unit(gr) * env_points(n, [(0, 0), (0.2, 0.7), (0.8, 1.0), (1.5, 0.0)])
    y = wet(y, "cave", 0.18)
    return finish(y, dur, -3.0, fade_in=0.01, fade_out=0.2, lp=6000)


def wrestle_squeeze() -> np.ndarray:
    """A well-timed squeeze lands: a tight crunch of muscle and hide, and the Lion's cry."""
    rng = rng_for("doce-wrestle-squeeze")
    dur = 1.1
    n = secs(dur)
    y = np.zeros(n)
    y += 0.9 * thump(n, 100, 48, 0.02, 0.1)
    crunch = creak(secs(0.25), rng, [900.0, 1600.0, 2600.0], [(0, 90), (0.2, 50)], [(0, 1.0), (0.2, 0.0)], q=6.0,
                   rough=1.0)
    place(y, crunch, 0.0, 0.5)
    y += 0.35 * unit(burst(n, rng, 0.03, [("bp", 600, 0.8)]))
    pain = growl_voice(secs(0.8), rng, [(0, 140), (0.1, 190), (0.5, 120)], [(0, 700, 1200, 2500), (0.5, 520, 980, 2300)],
                       rough=0.55, jitter=0.03, breath=0.5, lp=3000)
    place(y, unit(pain) * env_points(secs(0.8), [(0, 0), (0.04, 1.0), (0.3, 0.7), (0.75, 0.0)]), 0.05, 0.7)
    y = wet(y, "cave", 0.25)
    return finish(y, dur, -3.0, fade_out=0.2)


BEASTS = {
    "wolf_growl": wolf_growl,
    "wolf_howl": wolf_howl,
    "wolf_bite": wolf_bite,
    "wolf_yelp": wolf_yelp,
    "wolf_die": wolf_die,
    "boar_snort": boar_snort,
    "boar_charge": boar_charge,
    "boar_gore": boar_gore,
    "boar_crash": boar_crash,
    "boar_die": boar_die,
    "lion_growl": lion_growl,
    "lion_roar": lion_roar,
    "lion_swipe": lion_swipe,
    "lion_land": lion_land,
    "lion_thud": lion_thud,
    "lion_bite": lion_bite,
    "lion_pain": lion_pain,
    "lion_thrash": lion_thrash,
    "lion_death": lion_death,
    "wrestle_strain": wrestle_strain,
    "wrestle_squeeze": wrestle_squeeze,
}
