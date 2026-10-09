# DOCE · Audio

All of DOCE's audio is synthesised by code (numpy, no samples): `doce/tools/audio/` (see its README).
Regenerate everything with `python3 doce/tools/audio/render_all.py` (about 1 min; `--only name …` for a few,
`--png DIR` for spectrograms). Output: `doce/game/assets/audio/{sfx,music,amb}/*.ogg`.

- **77 files, 3.4 MiB in total** (music 1.8 MiB, ambience 1.0 MiB, 67 effects 0.6 MiB). Effects and most ambience are
  mono; music, the sea and the day bed are stereo. Vorbis quality: sfx 4, music 3, amb 2.
- Levels: effects peak at −3 dBFS (footsteps −8/−10, UI −4…−10, distant gull −10); loops RMS ≈ −19…−21 dBFS;
  ambience RMS ≈ −26…−28 dBFS. Every loop is rendered circularly and joins seamlessly.
- Played through the `Sfx` autoload (`scripts/core/audio.gd`): `Sfx.play(name, pos, vol_db, pitch)` for one-shots
  (pass the world position: it is attenuated with distance from the hero), `Sfx.music(name)` to crossfade the
  music, `Sfx.loop(name, node, vol_db)` for a looping 3D emitter (files in `amb/`), and the ambience beds in
  `Sfx.set_ambience()`. Names starting with `stinger_` are played by `Sfx.play()` on the music stinger player.

## Names already used in the code that changed

| Old (PHAROS) name in the live code | Use instead | Where |
|---|---|---|
| `Sfx.music("title")`, `Sfx.music("day")` | `Sfx.music("explore")` in both (it carries on from the title into the game) | `main.gd` |
| `blessing` | `altar` | `props/altar.gd` |
| `orb_hit` | `chain_stick` | `props/chain_ring.gd` (the spear biting the ring) |
| `structure_hit` | `chain_stick` when the spear hooks it; `boulder_thud` when it settles; `boulder_drag` loop while it moves | `props/boulder.gd` |
| `music/boss`, `amb/night`, `amb/fire`, `stinger_dawn`, `stinger_defeat` | `music/boss_lion`, `amb/wind`, `amb/cave`, —, `stinger_death` | `core/audio.gd` (`_web_preload`, ambience list) |

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
| `footstep` | the rig's `step` event when the ground type is unknown | already in `hero.gd` (−14 dB) |
| `step_grass_1..3`, `step_stone_1..3`, `step_sand_1..3` | the rig's `step` event by surface: sand on beaches (near sea level), stone on rock, paths, paving and in the cave, grass elsewhere | rotate the three takes; −10…−14 dB |
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

## Music (`Sfx.music`)

| Track | Where | Notes |
|---|---|---|
| `explore` | the title and the whole island | A Dorian, 6/8, 71 s loop: lyre, aulos, frame drums, strings, choir |
| `tension` | the ridge and the approach to the cave | same grid as `explore` (6/8, eighth = 162 BPM, 16 bars = 35.6 s, `explore` = 2 × `tension`); only A C D E G, so it can crossfade from `explore` (`Sfx.music("tension")` on entering the zone, `Sfx.music("explore")` on leaving) or play in sync on top of it as a layer |
| `boss_lion` | `Game.boss_started` | E Hitzaz, 7/8 (3+2+2), 51 s loop, great drums |
| `stinger_victory` | `main.victory()` (already there) | call `Sfx.music("")` just before it; back to `explore` after ~8 s |
| `stinger_death` | played by the UI when "Has caído" appears | |

## Ambience beds (`amb/`, loops)

| Bed | Level | Where |
|---|---|---|
| `sea` | −14 dB at the shore → −26 dB inland | everywhere outside the cave (distance to the coast) |
| `wind` | −30 dB in the lowlands → −16 dB on the ridge and high places | open ground; scale with altitude |
| `day` | −18 dB | forest, meadows, village (birds and cicadas) |
| `cave` | −12 dB | inside the Lion's cave; the other beds drop to −40 dB |

Drop-in for `scripts/core/audio.gd` (replaces the PHAROS night/fire beds and preload lists):

```gdscript
# _ready(): the beds
for n in ["sea", "wind", "day", "cave"]:
	var p := _new_player("Amb")
	p.volume_db = -80.0
	_amb[n] = p

# _web_preload(): what the title and the island need first
for key in ["music/explore", "amb/sea", "amb/wind", "amb/day"]:
	_register_sample(key)
...
_sample_queue.append_array(["amb/cave", "music/tension", "music/stinger_victory", "music/stinger_death"])
Game.boss_started.connect(func(_n: String, _b: Node): _register_sample("music/boss_lion"))

# set_ambience(): coast 0..1 (1 at the shore), height 0..1 (1 on the ridge), cave 0..1
func set_beds(coast: float, height: float, cave: float, active: bool = true) -> void:
	var targets := {
		"sea": lerpf(-26.0, -14.0, coast),
		"wind": lerpf(-30.0, -16.0, height),
		"day": -18.0,
		"cave": -12.0,
	}
	for n in _amb:
		var p: AudioStreamPlayer = _amb[n]
		if p.stream == null:
			p.stream = _stream("amb", n, true)
			if p.stream:
				p.play()
		var t: float = targets[n] if n == "cave" else lerpf(targets[n], -40.0, cave)
		if n == "cave":
			t = lerpf(-80.0, t, cave)
		p.volume_db = lerpf(p.volume_db, t if active else -80.0, 0.05)
```

## UI (played by `scripts/ui`; nobody else needs to)

`ui_move`, `ui_select`, `ui_back` (menus), `ui_lock` / `ui_unlock` (lock-on, on `Game.lock_changed`), `ui_toast`
(messages and warnings), `ui_card` (the labour frieze on `Game.labor_card`), `stinger_death` (the death screen
on `Game.hero_died`).
