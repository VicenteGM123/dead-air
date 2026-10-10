# DOCE procedural audio

Every sound in DOCE (effects, music, ambience) is **synthesised by code**: pure numpy, no samples, no downloads,
no sound banks. Original work of the project (clean licence). Rendering is **deterministic**: seeds come from each
sound's name (crc32) and ffmpeg encodes in `bitexact` mode, so a re-run produces the same bytes (with the same
numpy / ffmpeg / libvorbis versions). Started from the PHAROS generators (`pharos/tools/audio`) and extended.

## Regenerate

From the repository root:

```bash
python3 doce/tools/audio/render_all.py
```

About a minute with 2 processes; writes `doce/game/assets/audio/{sfx,music,amb}/*.ogg`. Options:

| Option | Use |
|---|---|
| `--only parry explore amb/cave` | only those names |
| `--png DIR` | spectrogram + waveform + mean spectrum of every file (quality control) |
| `--wav DIR` | a WAV copy of every render |
| `--out DIR` | another `assets/audio` folder (default `../../game/assets/audio`) |
| `--jobs N` | parallel processes (default 2) |
| `--list` | list the files it generates |

Requirements: Python ≥ 3.10, **numpy**, **ffmpeg with libvorbis**; Pillow only for `--png`. After rendering,
run `godot --headless --path doce/game --import` so Godot picks the new files up.

## Modules

| File | Contents |
|---|---|
| `dsp.py` | core: envelopes, RBJ biquads applied by FFT, time-varying spectral noise, convolution reverb with a synthetic IR, panning, limiter (from PHAROS) |
| `instruments.py` | lyre (Karplus–Strong), aulos (additive, vibrato, portamento, breath), string/choir pads (formants), frame drums, bells, brass, drone, cymbal (from PHAROS) |
| `common.py` | building blocks for the effects: impacts, band-noise whooshes, grit, debris, bronze and blade modes, chain links, leather creaks, cave reverb, growling voices (formants + subharmonics), clean animal voices (howls, yelps, squeals), snorts, paws, hooves, body falls |
| `sfx.py` | Heracles (sword, shield, parry, roll, jump, footsteps on grass / stone / sand), the chain spear, the world (altar, boulder, water, cats, goats, gulls) and the UI |
| `beasts.py` | wolves, boars, the Nemean Lion and the wrestle |
| `music.py` | compositions written as data (chords, arpeggios, melodies) and a bus mix: `explore`, `tension`, `boss_lion`, two stingers |
| `ambience.py` | sea (PHAROS), wind in the grass, day (birds and cicadas), the cave, the boulder-drag loop |
| `analyze.py` | statistics (peak, RMS, DC, energy above 4/8 kHz, jump at the loop point) and PNGs |
| `render_all.py` | runs everything and encodes to OGG Vorbis (quality: sfx 4, music 3, amb 2) |

To change a sound: edit its recipe and run `--only name --png /tmp/png` to check it.

## Levels

- **Effects**: peak −3 dBFS. On purpose quieter: footsteps −8/−10, `ui_select`/`ui_back` −4, `ui_move` −6,
  `ui_lock` −7, `ui_toast` −9, `ui_unlock` −10, `jump` −6, `land` −4, `swim` −8, `gull` −10, `goat_bleat` −6, `wolf_howl` −5.
- **Loops**: RMS ≈ −20.5 (`explore`), −21 (`tension`), −19 dBFS (`boss_lion`), peaks ≤ −1 dBFS.
  **Stingers**: active RMS ≈ −18/−19 dBFS.
- **Ambience**: RMS ≈ −26…−28 dBFS (`boulder_drag` −20: it is an emitter, attenuated by distance).
- Energy above 8 kHz kept low everywhere (nothing shrill on laptop speakers).

## Loops

Music and ambience are rendered **circularly**: note and reverb tails past the end fold onto the start, noise is
periodic and the reverb is a circular convolution, so every loop joins seamlessly (`loopjump` in the stats).
The audio manager sets `loop = true` on music and `amb/` streams when it loads them.

## Files

### `sfx/` (mono)

| File | s | Description |
|---|---|---|
| `swing_1`, `swing_2` | 0.30 | quick sword cuts (band noise with Doppler, a thin whistle of the edge) |
| `swing_3` | 0.40 | the wide closing arc of the combo, a low "woom" |
| `swing_heavy` | 0.62 | the charged blow: long low arc, cloth of the wind-up |
| `hit_1..3` | 0.28 | blade into flesh and fur: meaty smack, the cut, fur grit |
| `hit_heavy` | 0.55 | heavy blow landing: deep thump, crunch, grit |
| `blade_bounce` | 0.85 | blade skidding off the Lion: dull knock, ringing blade, sparks, scrape |
| `shield_block` | 0.50 | bronze-faced shield: wooden bonk and a bronze rim |
| `parry` | 1.20 | perfect parry: bright bronze ring and a fifth above |
| `dodge` | 0.55 | roll: cloth, shoulder on the ground, grit |
| `hero_hurt`, `hero_down` | 0.30 / 1.10 | hit taken; the fall with helmet and shield clattering |
| `jump`, `land` | 0.28 / 0.40 | push-off scuff and rush of cloth; both feet, armour settling, dust |
| `footstep` | 0.20 | generic step on earth |
| `step_grass_1..3`, `step_stone_1..3`, `step_sand_1..3` | 0.20 | footsteps by surface |
| `swim`, `splash` | 0.65 / 0.80 | a stroke; entering the water |
| `chain_throw` | 0.80 | spear throw, the chain paying out behind it |
| `chain_stick` | 0.65 | spearhead biting wood or rock, the shaft quivering |
| `chain_rattle` | 0.70 | loose chain jingle |
| `chain_taut` | 0.65 | links snapping into line, clank, strained creak |
| `chain_zip` | 1.00 | yanked along the chain: rising rush and a whirring chain |
| `boulder_thud` | 2.00 | the boulder settles: ground thump, rumble, grit rain, cave echo |
| `altar` | 2.40 | brazier catching fire, A-major lyre chord, choir, bell |
| `body_fall` | 0.65 | a body hitting the ground |
| `cat_purr`, `cat_meow` | 2.00 / 0.40 | purr (seamless 2 s), "mrrp" |
| `gull` | 0.60 | a far gull |
| `goat_bleat` | 0.80 | a goat's "meh-eh-eh": nasal voice with the bleat's quaver (the ambient goats) |
| `ui_move`, `ui_select`, `ui_back` | 0.08 / 0.25 / 0.20 | soft tick, lyre pluck (E5 + A5), lower pluck |
| `ui_lock`, `ui_unlock` | 0.22 / 0.14 | two small bronze ticks closing; one lower tick |
| `ui_toast` | 0.55 | a soft lyre harmonic |
| `ui_card` | 3.20 | the labour frieze: great frame drum, E-Phrygian strum, cymbal shimmer, choir |
| `wolf_growl`, `wolf_howl` | 1.40 / 3.40 | rough snarl; a howl (and a second wolf answering far away) |
| `wolf_bite`, `wolf_yelp`, `wolf_die` | 0.45 / 0.45 / 1.10 | snarl + teeth clack; hurt yelp; falling whimper + body |
| `boar_snort`, `boar_charge` | 0.80 / 1.80 | two snorts and a grunt; squeal then galloping hooves |
| `boar_gore`, `boar_crash`, `boar_die` | 0.60 / 1.10 / 1.30 | tusk impact; skull on stone, dazed grunt; squeal and fall |
| `lion_growl`, `lion_roar` | 2.00 / 3.40 | the growl in the dark; the great roar with the cave answering |
| `lion_swipe`, `lion_land`, `lion_bite` | 0.60 / 1.00 / 0.60 | paw sweep and claws; pounce landing; heavy snap |
| `lion_thud` | 1.80 | slammed into a pillar: stone groans, grit rains, dazed rumble |
| `lion_pain`, `lion_thrash`, `lion_death` | 1.10 / 1.00 / 3.40 | pained roar; thrashing; the last groan and the fall |
| `wrestle_strain`, `wrestle_squeeze` | 1.60 / 1.10 | leather creaking, bronze, feet grinding, a growl; the squeeze landing |

### `music/` (stereo)

| File | s | Key / tempo | Arrangement |
|---|---|---|---|
| `explore` | 71.1 (loop) | A Dorian, 6/8, eighth = 162, 32 bars | A: Am9 – D/A – Cmaj7 – G/B – Am7 – Esus4 with flowing lyre arpeggios and strings; A′: + aulos melody and a frame-drum heartbeat; B: Cmaj7 – G/B – Am7 – D – Cmaj7 – G – Bm7 – E with a lyre melody, lilting 6/8 drums and a choir "u"; A″: the aulos higher, resolving into the loop |
| `tension` | 35.6 (loop) | A, 6/8, same grid as `explore`, 16 bars | drones on A and E, lub-dub frame drums and a great drum every 4 bars, low muted-lyre ostinato (A minor pentatonic), tremolo strings, a low aulos |
| `boss_lion` | 50.9 (loop) | E Hitzaz, 7/8 (3+2+2), eighth = 264, 32 bars | intro (great drums, brass), A (pedal ostinato groove), B (+ choir E – F – Dm – Am, aulos), C (climax: aulos high, rolls), D (breakdown into the loop); cymbal swells into each section |
| `stinger_victory` | 7.0 | E major | roll and cymbal, then C – D – E (♭VI – ♭VII – I) in brass and choir, lyre run, bells |
| `stinger_death` | 4.6 | A minor | great drum, Fmaj7 – Esus4 – Am in choir and strings over a drone, the aulos sinking E – D – C – B – A, a low bell |

### `amb/` (loops)

| File | s | Description |
|---|---|---|
| `sea` | 30 (stereo) | five gentle waves breaking and withdrawing with foam, over a sea bed (PHAROS) |
| `wind` | 24 (mono) | gusts, a hiss of grass stems, a thin whistle in the strongest gusts |
| `day` | 30 (stereo) | songbirds (tsips, trills, rising-falling calls), a fluty warbler, a far dove, cicadas, leaves |
| `cave` | 24 (mono) | still air, a low moan from the cave mouths, drips with a long rocky echo |
| `boulder_drag` | 4 (mono) | stone grinding on rock, gravel crushing, knocks (an emitter on the boulder) |
