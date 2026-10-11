# DOCE · Audio

All of DOCE's audio is synthesised by code (numpy, no samples): `doce/tools/audio/` (see its README).
Regenerate everything with `python3 doce/tools/audio/render_all.py` (about 1 min; `--only name …` for a few,
`--png DIR` for spectrograms). Output: `doce/game/assets/audio/{sfx,music,amb}/*.ogg`.

- **78 files, 3.4 MiB in total** (music 1.8 MiB, ambience 1.0 MiB, 68 effects 0.6 MiB). Effects and most ambience are
  mono; music, the sea and the day bed are stereo. Vorbis quality: sfx 4, music 3, amb 2.
- Levels: effects peak at −3 dBFS (footsteps −8/−10, UI −4…−10, distant gull −10); loops RMS ≈ −19…−21 dBFS;
  ambience RMS ≈ −26…−28 dBFS. Every loop is rendered circularly and joins seamlessly.
- Played through the `Sfx` autoload (`scripts/core/audio.gd`, owned by UI+AUDIO): `Sfx.play(name, pos, vol_db,
  pitch)` for one-shots (pass the world position: it is attenuated with distance from the hero), `Sfx.music(name)`
  to crossfade the music, `Sfx.loop(name, node, vol_db)` for a looping 3D emitter (files in `amb/`). Names starting
  with `stinger_` are played by `Sfx.play()` on the music stinger player.
- **The ambience and the music run by themselves** (see the last sections): nobody needs to call
  `Sfx.set_ambience()`, and `Sfx.music()` only for something special.

## Old PHAROS names

`audio.gd` still maps the old PHAROS names to their DOCE sounds before loading anything (`RENAMES`: `title` / `day`
-> `explore`, `blessing` -> `altar`, `orb_hit` / `structure_hit` -> `chain_stick`), but since the merge of CORE no
code calls them any more: `main.gd` plays `explore`, the altar `altar`, the chain spear `chain_stick` when it bites,
the boulder `boulder_drag` (loop) and `boulder_thud`. Every name the code plays (`Sfx.play` / `music` / `loop` and
the UI's `Style.sfx`, the combo's table in `hero_melee.gd`, the footsteps' `step_<surface>_<n>`) exists in
`assets/audio`; the only optional one is `charge_ready` (not generated: the charged heavy blow plays `parry` pitched
up and quieter instead).

Kept with the same name: `swing_1..3`, `hit_1..3`, `dodge`, `footstep`, `hero_hurt`, `hero_down`, `splash`,
`stinger_victory`, `cat_purr`, `cat_meow`, `gull`, `ui_move`, `ui_select`, `ui_back`.

## CORE: hero, combat, chain spear, world props

| Sound | Play it when | Notes |
|---|---|---|
| `swing_1`, `swing_2`, `swing_3` | each blow of the 3-hit combo, as the blade starts to move | `swing_3` is the wide closing arc |
| `swing_heavy` | the charged heavy blow is released | |
| `hit_1`, `hit_2`, `hit_3` | the blade connects with a wolf or a boar (`take_hit` returned true) | at the victim; vary pitch 0.92–1.08 |
| `hit_heavy` | the heavy blow connects | pair with hit-stop and shake |
| `blade_bounce` | the blade hits the Lion and does nothing (clang + sparks) | at the contact point, every time; ENCOUNTERS may play it from `lion.take_hit` instead |
| `shield_block` | a hit is taken on the raised shield | |
| `parry` | a perfect parry (guard pressed in the window) | bright ring; hit-stop ~0.1 s |
| `dodge` | a dodge roll starts | already in `hero.gd` |
| `jump` | jump take-off | −6 dB |
| `land` | landing from a jump or a fall (louder and lower pitch for big falls) | |
| `footstep` | the rig's `step` event in shallow water (with a splash) | `hero.gd` (−14 dB) |
| `step_grass_1..3`, `step_stone_1..3`, `step_sand_1..3` | the rig's `step` event by surface: `World.surface_at(pos)` says sand on the beaches, stone in the cave, on paths, paving, steep rock and anything built (the pier), grass elsewhere | a random take of the three; −12 dB, pitch 0.92–1.08 |
| `swim` | each swimming stroke (rig `step` while swimming) | |
| `splash` | entering the water | already used |
| `hero_hurt` | the hero takes damage | already used |
| `hero_down` | the hero falls | already used; the UI adds `stinger_death` with the "Has caído" screen |
| `chain_throw` | the spear leaves the hand (rig event `release`) | |
| `chain_stick` | the spearhead bites an anchor, a rock, wood or a beast | at `chain_point()` |
| `chain_taut` | the chain snaps tight (a pull on something heavy starts, or a zip starts) | |
| `chain_rattle` | the chain is released or reeled in | |
| `chain_zip` | Heracles is yanked towards a bronze ring (`&"ring"`) | 2D, follows the hero |
| `boulder_drag` (amb, loop) | while the boulder moves: `Sfx.loop("boulder_drag", boulder, -4.0)`; free the returned player (or fade it) when it stops | 4 s seamless loop |
| `boulder_thud` | the boulder comes to rest in the cave mouth | |
| `altar` | praying at an altar (heal + checkpoint) | fire catching, lyre chord, choir, bell |
| `cat_purr` / `cat_meow` | petting a cat (re-trigger the 2 s purr while the hold lasts) / when petting starts or ends | |
| `gull` | now and then over the coast (every 8–20 s, far) | WORLD / ambient |
| `goat_bleat` | now and then from a grazing goat (one look-up in ten) | WORLD / ambient (`ambient_goat.gd`, −8 dB, pitch 0.9–1.05, kids 1.15–1.35); added at integration |
| `body_fall` | a beast's body hits the ground | |

## ENCOUNTERS: wolves, boars, the Nemean Lion

| Sound | Play it when |
|---|---|
| `wolf_howl` | the pack notices the hero (once per pack), or from far away in the forest |
| `wolf_growl` | a wolf circles / telegraphs before attacking |
| `wolf_bite` | the lunge's bite (rig `impact`) |
| `wolf_yelp` | a wolf is hit |
| `wolf_die` | a wolf dies (includes the body falling) |
| `boar_snort` | a boar notices the hero, or idles |
| `boar_charge` | the charge wind-up starts (squeal, then hooves for ~1.5 s) |
| `boar_gore` | the tusks connect |
| `boar_crash` | a charging boar hits a rock and is stunned |
| `boar_die` | a boar dies |
| `lion_growl` | the Lion stalks, or before a telegraphed attack |
| `lion_roar` | the roar (`roar_wave` event): the intro and the 66 % phase; add `Game.shake` |
| `lion_swipe` | a swipe |
| `lion_land` | the pounce lands (event `land`) |
| `lion_thud` | the Lion slams into a pillar or a wall and is stunned |
| `lion_bite` | a bite |
| `blade_bounce` | a blade hits the Lion (clang and sparks; the GDD wants this to be unmistakable) |
| `wrestle_strain` | every struggle beat while Heracles holds the Lion (about every 1.5 s) |
| `wrestle_squeeze` | a well-timed squeeze lands |
| `lion_pain` | the Lion takes damage in the wrestle (with the squeeze) |
| `lion_thrash` | the Lion throws its weight about in the wrestle |
| `lion_death` | the Lion is defeated (long groan, the body settling) |

## Music: the director in `audio.gd`

While `Sfx.auto_music` is true (default) the music follows the game; the director only moves between its own
tracks, so a track someone picks with `Sfx.music()` stays until they hand it back (`Sfx.music("explore")`).

| Track | When | Notes |
|---|---|---|
| `explore` | the title and the island | A Dorian, 6/8, 71 s loop: lyre, aulos, frame drums, strings, choir |
| `tension` | within 55 m of a cave mouth (`World.cave()` entrances; leaves at 70 m) and inside the cave before the fight | same grid as `explore` (6/8, eighth = 162 BPM, 16 bars = 35.6 s, `explore` = 2 × `tension`), only A C D E G: the 3 s crossfades sit well |
| `boss_lion` | from `Game.boss_started` to `Game.boss_ended` | E Hitzaz, 7/8 (3+2+2), 51 s loop, great drums |
| (silence) | 9 s after `boss_ended(true)` (or entering VICTORY during a fight) | `main.victory()` plays `stinger_victory` alone; then `explore` / `tension` again |
| ducked to −16 dB | while the phase is DEAD | the UI plays `stinger_death` with "Has caído" |

`Sfx.auto_music = false` hands the music to whoever wants to drive it; `Sfx.current_music()` says what is playing.
ENCOUNTERS: emit `Game.boss_ended(false)` when a fight resets (the hero fell and respawns at an altar), or the boss
music keeps playing until the next `boss_ended`.

## Ambience: the beds in `audio.gd`

Measured from the hero four times a second and smoothed (real time, so hit-stop does not freeze them):

| Bed | Level | Driven by |
|---|---|---|
| `sea` | −14 dB at the shore → −26 dB inland | `World.coast_distance(x, z)` when the world has it, else `is_water()` probes around the hero |
| `wind` | −30 dB low → −16 dB 50 m above the sea | the hero's height |
| `day` (birds, cicadas) | −18 dB (→ −50 dB at night) | `TimeOfDay.night_amount()` |
| `cave` (drips, echo) | −80 → −12 dB inside the cave; the other beds drop to −40 dB | `World.cave_amount(pos) -> 0..1` when the world has it (WORLD: add it once the real cave exists), else the distance to `World.cave().arena_center` (full inside 16 m, gone at 28 m); `Sfx.cave_override` forces it |

Debug: `audiodebug=1` prints the mix every 2 s (music, coast/height/cave, bed levels).

## UI (played by `scripts/ui`; nobody else needs to)

`ui_move`, `ui_select`, `ui_back` (menus), `ui_lock` / `ui_unlock` (lock-on, on `Game.lock_changed`), `ui_toast`
(messages and warnings), `ui_card` (the labour frieze on `Game.labor_card`), `stinger_death` (the death screen
on `Game.hero_died`).
