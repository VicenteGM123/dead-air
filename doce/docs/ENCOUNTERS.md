# DOCE · Encounters

The beasts of Nemea as they fight: behaviours, every number, where they live on the island, the tests and how to run
them, and the whole slice played from the title to the boat. Two lanes built them in parallel and were merged on
2026-10-11: **Part 1**, lane P, the wolf packs and the boars; **Part 2**, lane L, the Nemean Lion (labour I, the boss);
**Part 3**, the merge and the playthrough bot. Contracts used here (hit dictionary, telegraphs, poise, the chain kinds,
the grapple protocol, the parry from the attacker's side) are in `docs/COMBAT.md` section 6; the hero's numbers (roll,
guard, parry window, stamina) in `docs/COMBAT.md` sections 3-4; how the game is put together in
`docs/ARCHITECTURE.md`. Units: metres, seconds, m/s. Spanish in-game text is quoted as it appears.

---

## Part 1 · Wolves and boars (lane P)

### 1.1 Files

| File | What |
|---|---|
| `scripts/enemies/pack.gd` | `BeastPack` (Node): the shared brain of a wolf pack or a boar herd: alert, hunt, attack tokens, ring slots, leash, reset when the hero falls, one-shot hints |
| `scripts/enemies/pack_nav.gd` | `PackNav` (RefCounted): steering for the beasts (seek, separation, feelers, a clearance round the feet, never into the sea, unstuck detours) and the ground under their feet (the terrain, or the top of a low rock) |
| `scripts/enemies/wolf.gd` | `Wolf extends Enemy` |
| `scripts/enemies/boar.gd` | `Boar extends Enemy` |
| `scripts/gfx/rig_wolf.gd` | (BESTIARY's rig, small additions) `hold_t` (hold the current action at a time: the lunge's crouch as the readable part of the wind-up, with a growling tremble), `glow_cap` (caps the eyes' flare: a feint must not glint like a wind-up), action `evade` (a hop back out of a sword's reach) |
| `scripts/gfx/rig_boar.gd` | (small additions) `hold_t` (the gore's head-down anticipation), action `stagger` (thrown back on its haunches: a parried charge, the finisher, the heavy blow) |
| `scripts/world/nemea_layout.gd` | `SPAWNS`: the second wolf pack has 5 wolves (was 4) |
| `tools/encounters.tscn` / `.gd` | the real game on Nemea straight into play (extends `scripts/main.gd`), plus the encounter bot with `encbot=` |
| `tools/encounter_bot.gd` | the tests (1.8) and the render scenarios |

`main.spawn_encounters()` creates one `Wolf` / `Boar` per member of each `World.spawn_groups()` entry and teleports
it; the first teleport joins the beast to the `BeastPack` of its group (members spawned within 18 m of a pack's home
join it; groups are tens of metres apart). Nothing else is needed: no scene, no autoload, no change to main.gd.

### 1.2 Where they are (the slice's flow)

| Group (`SPAWNS`) | Place | Role |
|---|---|---|
| 3 wolves at (-24, 14) | on the main road in the forest, between the north gate and the west ramp (GDD step 2: "Camino al bosque: primera manada") | the first fight: teaches the roll and the combo; one attacker at a time, a little more time between attacks than a big pack |
| 5 wolves at (6, -30) | the forest trail that follows the lion's paw prints north (a side way, off the critical path) | the hard pack: two attackers at once late in a fight, flank attacks on a hero who swings at the others |
| 1 boar at (-104, -47) | the thumb, the first clearing past the broken passage (GDD step 4: "Claros con jabalíes") | teaches the dodge and the crash: four standing rocks round it |
| 2 boars at (-78, -72) | the thumb path towards the ridge meadow | two charges to read, rocks round them |
| 1 boar at (60, 34) | the east hill's olive terraces (an optional detour from the village) | |

WORLD rings each boar clearing with standing rocks (`nemea_props.gd`: four `cliff_rock`s 1-3 m beyond the group's
radius) to charge the boars into. Killed beasts stay dead for the run; a pack with no member left is `cleared` and
stops thinking.

### 1.3 The pack brain (`BeastPack`)

| State | Entered | What happens |
|---|---|---|
| IDLE | spawn, back home | every member wanders round its own home spot (1-4 m, walking); far (more than 110 m from the hero) it does not think at all, beyond 95 m from the camera its rig stops animating; a resting wolf pack howls now and then while the hero is 32-80 m away (every 24-40 s: the forest warns him) |
| ALERT | the hero within 15 m of a member (and within 35 m of home), or a member hurt or hooked by the chain | the alpha (the biggest) howls once per pack (`wolf_howl`; not the one that was hit), the others run to the ring; HUNT after 0.9 s |
| HUNT | | the ring round the hero, the attack tokens (below) |
| RETURN | the hero more than 35 m from home for 0.8 s (the leash), or the hero fell | every member trots home healing (wolves 12 hp/s, boars 15 hp/s; full health at home); a hero coming back within 26 m of home and 12 m of a member alerts them again (no ping-pong at the leash's edge); a beast still on its way after 14 s (wolves) / 18 s (boars) and out of the camera's view is put home |

**Attack tokens.** Only a member holding a token attacks. After an attack (bit, missed, parried, blocked, broken)
the token goes back with a pause: `1.15 s x k x random(0.8, 1.3)`, k = 0.6 with 4 or more alive, 1.2 for a pack of
3 (the first pack), 1.35 for the last one alone. Packs of 4 or more may have a second attacker: 65 % of the time,
once the first has struck. **Flank rule**: in a pack of 4 or more, while the hero swings (a blow or the heavy spin)
the pack rolls every 1.2 s (75 %) to send a ready wolf behind him (within 6.5 m) at once: button mashing gets
punished, and the growl and the glint still announce it. Wolves in front of the camera are preferred for a token (an
attack from behind is still telegraphed by sound, but the view should show most of them). Boars share the same token
for their charges.

**Ring.** Each wolf gets a slot round the hero (the members keep their order round him, evenly spaced, re-assigned
5 times a second), led 0.45 rad round in the drift direction so the ring turns; the drift reverses every 5-9 s.
Each wolf keeps its own radius, 4.4-5.8 m (plus a slow 0.45 m wobble); a badly hurt one (under 34 % health) keeps
7.6 m and attacks only when no healthier wolf is left. Slots on water or more than 2.2 m above / below him are pulled
in towards him.

**When the hero dies** every surviving member is reset at his respawn: teleported to its home spot, full health,
idle; the pack is idle again (and does not howl again at the next alert). The alpha howls over the fallen hero first.

**Hints** (one-shot toasts through `Game.say`, once per run, only while playing, `nohints=1` turns them off): the
first wolf wind-up "Rueda con {dodge} o cúbrete con {guard}" / "El lobo se agazapa y gruñe antes de saltar"; the
first lunge that misses "¡Ahora! Golpea con {attack}" / "Tras un salto fallido, el lobo queda expuesto"; the first
boar charge "Esquiva la embestida con {dodge}" / "Si choca contra una roca, quedará aturdido".

### 1.4 Wolves (`Wolf`)

Fast, in packs of 3 to 5; they circle, one attacks while the others wait (GDD). Three coats from BESTIARY's rig: the
first member of a pack is the alpha (dark, bigger), then grey and pale ones alternate.

| Coat | Health | Bite |
|---|---|---|
| alpha | 46 | 19 |
| grey | 36 | 17 |
| pale | 30 | 15 |

The hero's combo (10 + 10 + 18) kills a grey or a pale wolf; the alpha takes a little more.

| State | Behaviour |
|---|---|
| IDLE | wanders round its home spot, sniffing (looks about while it stands) |
| HOWL | the alpha's howl (rig `howl`, `wolf_howl`), facing the hero; 1.75 s, then the ring |
| CIRCLE | its ring slot, facing the hero, strafing; a growl now and then (`wolf_growl` -11 dB); now and then a FEINT: a snap forward and back without a telegraph (rig `bite` with its eye flare capped, no glint, no flash: only a glint means a bite); never while another wolf winds up or leaps |
| APPROACH | holds a token: closes to 3 m, facing him (runs when more than 5 m away). A trunk or a rock between them: it circles round him for a clear line (the line test ignores the ground between them: a hero on a rise is still reachable) |
| WINDUP | the telegraph (COMBAT.md 6.4): the rig's lunge crouch (0.3 s) held 0.08-0.26 s (random: watch it, do not count it) with a growling tremble, the eyes flaring, `wolf_growl`, a gold glint at the jaws; the crouch lets go and the jaws meet him 0.35 s later. Telegraph 0.73-0.91 s in all; the bite lands exactly as `telegraph_left()` reaches 0 |
| LUNGE | the leap (0.45 s of flight): committed along the line to where the hero was at take-off plus 0.18 s of his motion, planned so the jaws are 1.3 m from his centre at the bite (77 % of the flight). The bite: 1.5 m reach to his surface, +-40 degrees, knockback 4.5, stagger 0.3 (the hero's light hit reaction), `wolf_bite`. Hurt him: it drops where it bit and springs back out of reach (no punish). Blocked: bounced off the shield (stagger 0.45 s). Parried: `on_parried` (below). Dodged or missed: it flies on and lands past him |
| RECOVER | after a miss: 0.62-0.78 s standing open (the opening to punish); 0.3 s after a bite or a block |
| BACKOFF | trots back to the ring facing him |
| EVADE | the hero starts a blow with it in front of him within 3.4 m: it may hop back ~2 m out of the swing (rig `evade`): 75 % circling, 70 % backing off, 50 % feinting, 40 % approaching, never while winding up, leaping or recovering; one roll per blow, 1.1 s cooldown each |
| RETURN | trots home healing |

- **Poise**: 0.3 (every blow staggers it and breaks what it does) except while committed to a bite (the wind-up and
  the leap until the jaws close): 0.55, so a light blow only flashes and pushes it and the bite still comes (answer it
  with the guard, a parry or a roll; the finisher or the heavy blow break it).
- **Hit reactions**: the base flinch (rig `hit`, `stagger` for blows of 0.6 or more: the finisher and the heavy knock
  it back), `wolf_yelp` on every hurt; knockback in full (resist 0).
- **Parried**: stagger 1.2 s, a 3 m/s shove away, rig `stagger`, a yelp, sparks at the muzzle; its next attack is 1.25x
  later. **Chain** (kind `&"light"`): yanked through the air to land 1.2 m + its radius in front of the hero, facing
  him, staggered 1.1 s (the Enemy base): a set-up for the combo; the bite of the chain alerts the pack.
- **Death**: rig `death` (falls on its side, dust at the `fall`), `wolf_die`, the body dissolves after 5 s.
- Each wolf waits 1.6 s after its own attack before it can take a token again.

**Collision**: two capsules: a vertical one at the feet (r 0.24, h 0.82) and one lying along the body from the nose
(1.0 m ahead of the origin) to the rump (r 0.21), turned with the body every tick, so the head never pokes into the
hero, a trunk or another wolf. The leap is moved with `move_and_slide` (a wolf never flies through the hero or a rock);
a packmate's body right in front of the leap (within 0.42 m of its hurt capsule, 0.85 m ahead) ends it short: the wolf
drops there (dust, the miss's opening) instead of landing its paws in the other's back.

### 1.5 Boars (`Boar`)

Charge in a straight line after a warning; dodge them or stop them with the shield at the right moment; into a rock
they are stunned (GDD).

| State | Behaviour |
|---|---|
| IDLE | roots about its home spot (the snout to the ground), snorting now and then |
| NOTICE | the herd noticed the hero: it turns to him, bristles up, a loud `boar_snort`, a puff of dust (0.75 s) |
| READY | faces him (a heavy beast: it turns at 2.4 rad/s), keeps 4.7-17 m (backs off a little when closer, to its run-up, trots in when further); with the herd's token: a charge (merge fix: it used to stop backing off at 4.0 m while a charge needs 4.5 m, so a boar 4.0-4.5 m in front of a hero who stood still never attacked again) |
| REPOSITION | a rock between it and the hero: it shuffles sideways for a clear line, up to 2.2 s (then it charges anyway: into the rock) |
| WINDUP | the telegraph: rig `charge_windup` (1.3 s: head down, paws the ground twice with dust, rocks back, tail up, the eyes flaring), `boar_charge` (the squeal, then hooves), a big gold glint at the tusks; it tracks the hero for the first 75 % and then the line is set |
| CHARGE | straight along that line (only 0.5 rad/s of steering in its first 0.3 s), 30 m/s^2 up to 10.5 m/s, dust flying; a second glint at the tusks ~0.38 s before they reach him (the parry cue). See the outcomes below |
| SKID | past him by 3.5 m, 2.6 s or 24 m of running, a drop of more than 1.4 m or the sea 2 m ahead: it skids to a stop (15 m/s^2) and turns round: an opening (0.7-1.0 s) |
| GORE | the hero within 2.5 m in front of its tusks: the tusk toss, telegraphed (the gore's head-down anticipation held 0.12-0.22 s, a glint, a snort; 0.53-0.63 s in all), a short lunge into it; 18 damage, knockback 7, stagger 0.6, reach 1.3 m +-55 degrees; blockable, parryable; 2.2 s between gores |
| RECOVER | after a charge or a gore: the opening |
| RETURN | walks home healing |

Charge outcomes:

| The hero... | Result |
|---|---|
| does nothing | 28 damage, knockback 10, stagger 0.7 (the hero's heavy reaction), `boar_gore`, the tusk toss |
| guards (shield up, facing it) | blocked: 6 + 0.9 x 28 x 1.4 = 41 stamina and a 6 m/s shove back; the boar is stopped (stagger 0.55 s); with too little stamina the guard breaks (half the damage, staggered) |
| parries (guard pressed within 0.18 s of contact) | the charge breaks: stagger 1.8 s, sparks at the tusks, a squeal, rig `stagger`; no damage |
| rolls through it (i-frames) or aside | it runs on: a perfect dodge when the i-frames meet it |
| stands in front of a rock and rolls aside | **CRASH**: faster than 4 m/s into the world (layer 1: rock, trunk, wall, pillar) or the boulder (layer 4), a face that takes it square on: stunned 3 s (stars, `boar_crash`, shake 0.3-0.55, hit-stop 0.07, an impact burst, dust and smoke), every blow does 1.25x while it is dazed |
| another beast in the way | both stop (no stun) |

- **Health** 150, knockback resist 0.65, **poise 0.7**: light blows only flash and push it; the finisher (0.75),
  the heavy blow (1.1), a parry, a crash or the chain stagger it and break a wind-up (COMBAT.md 6.3). One stun is
  worth ~50-95 damage with the combo and the heavy blow: two or three charges per boar. **No juggling** (merge fix):
  each combo's finisher re-staggered it before it recovered, so a parried boar was cut down in ~4 s without ever
  getting up; now a boar helpless (staggered, not stunned) for 2.6 s in a row shrugs blows off (poise 99) until it has
  charged or gored again, or for 2 s (`Boar.HELPLESS_MAX`, `ARMOR_T`).
- **Chain** (kind `&"beast"`): the yank slides it 2.2 m towards the hero (bent up to 25 degrees towards a rock in
  reach: the lion's pillar rule; slammed into one it is stunned 3 s), breaks a wind-up or a charge, and turns it to
  face him.
- **Death**: rig `death` (topples away from the blow), `boar_die`, a shake, dust and `body_fall` as it hits the
  ground; the body dissolves after 6 s.
- **Collision**: a vertical capsule (r 0.3, h 0.86) and one along the body from the snout (1.0 m ahead) to the rump
  (r 0.3), turned with the body.

### 1.6 Moving without passing through anything

`PackNav` (one per beast; no allocation per tick):

- **Steering**: seek the goal at a speed (easing in), separation from the other beasts (1.8 m wolves, 1.9 m boars),
  two feelers 0.45 rad either side every third tick on the world layer (their push loses its backward part, so a
  trunk dead ahead is walked round, not shuffled at), never a step towards the sea (0.9 m ahead), and a detour when
  stuck: making less than a third of the wanted progress towards the goal for 0.45 s turns the seek ~69 degrees to
  the side with more room (two rays) for 1.1 s.
- **Clearance round the feet**: a paw striding sideways (a wolf circling while it faces the hero) or at the end of a
  trot stride reaches 0.6 m from the origin, outside the body capsules. Every second tick a cylinder of radius 1.05 m,
  8-58 cm above the feet, is checked against the world layer (not the terrain); the nearest point of each trunk,
  rock or wall it touches is kept, and `steer()` never moves the body closer than 0.65 m to one (the part of the
  velocity towards it is removed) and pushes it out (up to 4 m/s) when it is closer. Only what goes through
  `steer()` is constrained: the boar's charge still runs straight into its rock.
- **Feet on rocks**: the rigs' `ground_fn` is `PackNav.ground_y`: the terrain height, or, for a point within reach of a
  rock found round the body (a sphere query every second tick), a ray down onto it: a paw next to a low rock stands
  on it instead of sinking into its flank (up to 0.4 m above the terrain; taller faces are kept away by the
  clearance). The rays are only cast for points over a scanned rock: 0-1 per frame per beast in a meadow fight, ~13
  for a boar standing among rocks.
- **Bodies**: `CharacterBody3D`s on the enemies layer colliding with the world, the hero, each other and the boulder
  (Enemy base: gravity, floor snap 0.4 m, slopes up to 50 degrees); the rigs' feet are planted on the ground above
  (BESTIARY's quadruped kit: two-bone legs, the body clamped above the ground).
- **Cost**: a beast at rest stops sweeping its capsule (Enemy base), an idle pack far from the hero does not think, an
  idle rig far from the camera does not animate and does not scan.

### 1.7 Feel

Sounds (docs/AUDIO.md): `wolf_howl` (the alert, far howls), `wolf_growl` (circling, every wind-up), `wolf_bite` (the
bite: -1 dB when it hurts, -6 dB when it snaps on air), `wolf_yelp` (hurt, parried, yanked), `wolf_die`; `boar_snort`
(notice, idle, the gore's wind-up, squeals when hurt or parried, back on its feet after a stun), `boar_charge` (the
wind-up), `boar_gore` (the tusks connect), `boar_crash`, `boar_die`, `body_fall`, footsteps (`step_*`) for the boar's
pawing and skid. Hit-stop and shake: the hero's blows (HeroMelee), the hero hurt (Hero: 0.05 / 0.08 s), the boar's
crash (0.07 s, shake up to 0.55), the parry (Hero: 0.10 s + slow motion). Sparks on parries (`Fx.hit_spark` at the
muzzle / tusks), an impact burst and a camera nudge on a bite, dust on the boar's pawing, along its charge, at its skid
and crash, at a wolf's landing and fall. The camera frames a beast winding up in view (CORE's soft framing).

### 1.8 Tests

```sh
cd doce/game
# all the tests (about 3 minutes on the shared machine): prints "ENC test <name> PASS|FAIL ..." and a summary
timeout 1800 godot --headless --path . res://tools/encounters.tscn --fixed-fps 60 --quit-after 500000 -- encbot=all quit=1 | grep ENC
# some of them
... -- encbot=yank,parry,boar_crash quit=1
# the balance with more runs, or other fights (c careless, g guard, s skilled; 3 or 5 wolves)
... -- encbot=balance balance_n=6 balance_set=c5,s5,c3,g5,g3 quit=1
```

The bot plays the real hero on the real island through the hero's input path (`HeroInput.bot` buttons,
`Hero.debug_move`, the camera aiming the chain spear, the lock-on).

| Test | Checks |
|---|---|
| yank | the forest pack circling him; the chain spear hooks a wolf of the ring 4-9 m away: it is yanked, lands within 2.9 m in front of him, staggered |
| parry | a wolf's lunge parried (guard pressed as its telegraph runs out): no damage, the wolf staggered with rig `stagger` |
| leash | the pack hunting him; he sprints away down the road: past 35 m from home the pack gives up, trots home and heals (a wolf hurt 14 hp is back to full), idle again |
| death | the hero felled with the pack round him (one wolf at half health): at his respawn every wolf is at its home spot, full health, idle |
| pack3 | the forest pack of 3 beaten with the roll and the combo (rolls as a wind-up runs out, punishes the recovery): all three dead, the hero alive |
| boar_parry | a boar's charge parried as the tusks arrive: the charge broken, the boar staggered (rig `stagger`), no damage |
| boar_block | the shield held up early (not a timed parry) against a boar's charge: no damage, 30 or more stamina gone, the hero shoved back 0.4 m or more, the charge stopped |
| boar_yank | a boar winding up its charge hooked by the chain spear: the wind-up broken (no charge follows), the boar dragged more than 1.2 m towards him and turned to face him |
| boar_crash | in front of a rock: the boar winds up and charges, he rolls aside at the last moment, the boar slams into the rock (stunned) and is cut down (as many charges as it takes) |
| clip | every physics frame of a fight with a pack of 3, the 5-wolf pack hunting him, and a boar crashed into a rock and cut down: no beast part (muzzle, head, chest, hips, paws, tusks) inside the hero's capsule (more than 12 cm), another beast's body (15 cm), the ground (12 cm), or a rock, a trunk or a wall (the colliders are a little bigger than what is drawn: a paw may graze one by 6 cm, another part by 3 cm, in 0.2 % of the samples at most; the depth is measured). Also prints the feet's rays per frame |
| clip_trunk | the same checks with the 5-wolf pack hunting him 5 m from a big trunk (r 0.62 m): the ring runs through it, the wolves strafe round it (the clearance round the feet, 1.6) |
| balance | fresh packs on a meadow (default 4 runs): a careless hero against 5 (runs at them mashing the attack, never guards or rolls) must lose at least half the runs (it loses about 6 in 7: a stricter rule would make the test fail on the odd lucky run); a skilled one against 5 (rolls the lunges, punishes the openings) must win every run with 40 hp or more in 2 runs in 3 |

Latest results (2026-10-11, `encbot=all`, after the last change): 12/12 PASS in 3 min 4 s.

Balance, every run since the last change to the wolves (five suites and a 6-run balance; 15 to 21 runs per fight):

| Hero vs pack | Won | Health left (won) | Bitten (avg) |
|---|---|---|---|
| careless vs 5 | 3 of 21 | 23-30 | 6.0 |
| skilled vs 5 | 21 of 21 | 49-100 (avg ~80) | 1.2 |
| careless vs 3 (the first pack) | 3 of 15 | 21-100 | 5.3 |

Earlier 4-run measurements of the guard policy (mashes, raises the shield when a wolf winds up at him): against 3,
won 3 of 4 with 81-100 health; against 5, won 2 of 4 with 2-19 health.

So: a player who never defends usually dies even to the first pack (the hint toasts teach the roll and the guard);
one who only raises the shield beats the first pack and has a hard time against five; one who rolls and punishes wins
comfortably.

Render scenarios (no pass / fail; "ENC mark <tag> frame=<n>" lines name the movie frames, one mark per state change
of the beasts involved, and "ENC track" lines give the hero's and each beast's position on screen every 3rd frame,
for crops): `encbot=r_wolf` (a pack of 3: a wind-up, the lunge, the roll, the punish; on an open meadow, or the forest
pack on its road with `render_at=road`), `r_ring` (the 5-wolf pack circling him, its tokens held back), `r_boar` (the
wind-up, the charge, the roll aside, the crash into a rock, the stun, the blows), `r_road` (the first pack round him
on the forest road: a fixed camera up the road, then the gameplay camera) and `r_clearing` (a boar of the herd on the
thumb path noticing him and winding up, from a fixed camera). With `fastpre=1` the set-up runs at 4x until the mark;
`render_s=` sets the length.

```sh
xvfb-run -a -s "-screen 0 1600x900x24" godot --path doce/game --rendering-driver opengl3 --resolution 1280x720 \
  --write-movie /abs/frames/rw/f.png --fixed-fps 30 --quit-after 420 res://tools/encounters.tscn -- \
  encbot=r_wolf noui=1 fastpre=1 nohints=1 render_s=6.5 quit=1
```

### 1.9 Debug arguments

| Arg | Effect |
|---|---|
| `enemies=0` | no wolves or boars on the island |
| `enemies=1` | keep them with CORE's island bot (`corebot=`: its traversal tests and the slice walk do not fight, so it runs without them by default) |
| `encbot=<tests>` | (tools/encounters.tscn) the encounter bot: `all` or a list |
| `botdebug=1` | the bot's fights traced every 0.5 s (the hero's state, each beast's state, distance, health) |
| `wolfdebug=1` | a line for every wolf attack that is broken off (and why an approach gave up) |
| `balance_n`, `balance_set`, `balance_only=skilled` | the balance test's runs (default 4) and fights |
| `render_s`, `fastpre=1` | render scenarios: length; set-up at 4x |

### 1.10 Changes outside lane P's files

- `scripts/gfx/rig_wolf.gd` (BESTIARY): `var hold_t := -1.0` and two lines in `_animate()` that hold
  `action_t` at it; `var glow_cap := -1.0` and two lines after `q.run_actions()` that cap the GLOW channel; a growling
  tremble on the held lunge crouch (in `_proc`); the `evade` action (doc line in the header).
- `scripts/gfx/rig_boar.gd` (BESTIARY): `var hold_t := -1.0` and the same two lines in `_animate()`; the `stagger`
  action (and its per-frame shake in `_animate()`); header doc line.
- `scripts/world/nemea_layout.gd` (WORLD): `SPAWNS` second wolf pack `count` 4 -> 5.
- No change to enemy.gd, hero.gd, game.gd, main.gd or the UI. `enemies=0` and CORE's island bot (`corebot=`) remove
  the beasts from inside wolf.gd / boar.gd (`BeastPack.enabled()`): the beast stops ticking and frees itself in its
  own `_ready()`.

### 1.11 Open points

- No health comes back between the first wolf pack and the first altar beyond the passage (the hero has no
  regeneration and there is no altar on the forest road): a hero who barely survives the wolves meets the first
  boar hurt. A dead hero respawns at the last altar or at the pier.
- A player who never guards or rolls usually loses to the first pack of three (4 runs in 5; by design it teaches the
  roll, and the hint toasts say how). If that proves too harsh, the first pack's attack pause (`BeastPack._next_cd`,
  k 1.2) is the knob.
- The balance test is statistical (random packs): it is written to pass on the odd lucky run (1.8), but a run of
  bad luck can still fail it (estimated ~3 % of suites).
- The telegraph's flash (Enemy base `telegraph()`: `hit_flash(0.4)`, CORE) turns a wolf or a boar almost white for a
  frame or two at the start of every wind-up (visible in the strips). The glint, the crouch and the growl already
  read; CORE may want a softer flash.
- CORE's camera: in the forest it looks through tree crowns (no foliage handling), so the gameplay strips were
  rendered on an open meadow; its threat framing can hide a wolf winding up close behind the hero for ~0.3 s.
- The rendered strips and island shots were made before the last changes (feet on rocks, the clearance round the
  feet, the leap that drops short in front of a packmate): those change where a paw stands next to a rock and how
  close a wolf comes to a trunk, nothing else that shows.
- A beast keeps 0.65 m between its origin and any trunk, rock or wall at paw height: between two obstacles closer
  than ~1.3 m (plus their radii) it goes round. The boar's charge is not constrained (it must crash).


---

## Part 2 · Trabajo I · El León de Nemea (lane L)

The boss of the first slice (GDD "Trabajo I"). The rule: **no blade cuts it**. It is hurt only in a wrestle, and it
can only be wrestled while it is dazed, after it has slammed into stone. Built on the ENCOUNTERS contracts of
docs/COMBAT.md 6 (the hit dictionary, the blade deflect, the Enemy base, the telegraph rules, the beast's chain slide
and pillar stun, the grapple protocol, the parry).

### 2.1 Files

| File | What |
|---|---|
| `scripts/enemies/lion.gd` | `class_name Lion extends Enemy`: the body (three capsules along it and a sphere for the head), the damage rule, the moves, the phases, the brain, the wrestle (target side), the escape and the ambush |
| `scripts/encounters/lion_encounter.gd` | `class_name LionEncounter`: puts the lion in its den, wakes it, starts / resets / ends the fight (boss bar, music), says the rule once, the hints, the victory sequence |
| `scripts/world/nemea_cave.gd` | (lane L section at the end) the arena dressed: rock columns with strata and cracks that grow where the lion hits them, four rock perches (tors) by the walls, claw marks, bones and a goat skull, a dead hunter's shield and spear, rubble, stalagmites at the walls, a shaft of light on the den rock; `perches()`, `crack_at()` |
| `scripts/world/nemea_boat.gd` | the ship to Lerna: after the labour, "Zarpar" ends the slice (labour II's card, then the title) |
| `tools/lion_bot.gd` | the test bot (loaded by the encounter with `lionbot=`) |
| shared (additive) | `main.gd` (`spawn_boss()`, the VICTORY -> PLAY free roam), `hero.gd` (`PELT_BLADE` 0.5; `_end_grapple` empties the attack buffer: presses meant for the wrestle no longer swing the sword at the beast that has just thrown him off), `rig_lion.gd` (`action_speed`, `enrage`, the `downed` action), `camera_rig.gd` (`_frame_score` asks the held beast's `wrestle_view_block()`), `ui.gd` (`screen_flash` sets its colour at once) |

### 2.2 The flow

1. **The den.** The lion keeps watch on its rock at the back of the cave (the north tor, in a shaft of light over
   the bones).
2. **Waking.** The hero walks into the arena (14.5 m from its centre, inside the cave) or hits / hooks the lion:
   it rises, growls, bounds down and stalks him at 7-10 m without attacking. `Game.labor_card(1, "El León de Nemea")`
   is emitted once; the UI shows each labour's card once per run (it may already be up: it shows by itself on
   entering the arena), and the encounter waits for it to roll up (at least 2.2 s, at most 9 s).
3. **The fight.** The intro roar (no shove), `Game.boss_started("El León de Nemea", lion)`: the boss bar (notches at
   66 % and 33 %) and the `boss_lion` music.
4. **The rule, once.** The first blade that bounces off it in the run: the warning banner "Su piel no la corta el
   bronce" / "Hazlo chocar contra las columnas". Every bounce: sparks, `blade_bounce`, the hero recoils (COMBAT.md
   6.2), the lion's head flinches (`spark`) when it is not mid-attack.
5. **The hero falls.** 1.4 s later the lion is back on its den rock at full health, `Game.boss_ended(false)`; main.gd
   brings him back at his last altar (the Altar de la Sierra if he prayed there); the boulder stays where it is; the
   rule and the hints are not said again; walking back in starts the fight again (no card).
6. **The hero leaves.** Beyond 31 m from the arena's centre for 3 s (60 m while the lion is away), once the lion is
   out of his sight (or he is 45 m away): the fight ends, the lion goes back to its den healed to the start of its
   phase (it never pops back onto its rock in view). Meanwhile it does not follow him out (its lair, below).
7. **Victory** (below), then free roam in the pelt, and the boat.

### 2.3 How it is hurt

| Way | What happens | Numbers |
|---|---|---|
| Its pounce dodged into stone | the leap is committed: it flies on (and skids on landing) into a column, a tor, a stalagmite or the wall behind the hero | a slam needs >= 4 m/s and a face that takes it square on (normal against the flight by > 0.45); the skid carries ~3.5 m from 13.5 m/s at 26 m/s^2, so stone up to ~5 m behind him (the head is 1.7 m ahead of the body's centre) catches it |
| The chain yank (kind `&"beast"`) | the Enemy base slide (3.6 m along the pull, bent up to 25 degrees towards a face in reach) into a column / tor / wall / the boulder | COMBAT.md 6.5's recipe: a column beside the lion within ~25 degrees of the line to the hero, its face within ~4 m; the spear needs a clear line |
| Yanked off its perch | from a tor's top (perched, or crouched to pounce from it) it falls 2.3 m and lands hard | a fall >= 1.4 m stuns (80 % of the phase's stun) |
| **Dazed** | stars over its head (a proxy node, so they end at once when the wrestle starts), the `stunned` loop; **E** within 3 m: the wrestle | stun 4.2 / 3.8 / 3.4 s by phase |
| **The wrestle** (COMBAT.md 6.6) | the hero takes the side of its neck (42 degrees round from its nose, beside its head; the side away from the stone it hit, else his side and the camera's; chosen once with capsule queries among 14 angles: there the gameplay camera keeps him in view, see the tests), it is hauled 1.3 m off the stone; squeeze windows (`hero.grapple_cue`), thrashes warned by a growl and a glint 0.5 s before (`hero.grapple_thrash`: guard held = a fifth of the cost) | beat 1.3 / 1.2 / 1.1 s, window 0.5 / 0.46 / 0.42 s, thrash every 2.6 / 2.3 / 2.0 s for 24 / 26 / 28 stamina; **3 good squeezes win** (13.5 damage each, kind `&"grapple"`), 3 presses out of a window or 14 s lose; `grapple_progress()` = squeezes / 3 for the UI's ring |
| Won | thrown onto its side (`downed`, 1.9 s), then it hunts again | |
| Lost | it bucks him off: 8 damage, unblockable, 7.5 m/s shove away from its neck | its body lets him through for 0.45 s after any wrestle (he stood inside its reach) |

Health 300: 23 squeezes, about **3 wrestles per phase** (a squeeze that crosses 66 % or 33 % ends the wrestle with
that phase's roar), 9 in all; never a sponge.

Blades (and everything but the wrestle's squeeze) are deflected: `_modify_damage` sets `hit.deflected` and returns
0; `poise` 99 (no blow staggers it). A perfect parry of a swipe or a bite throws it open (0.75 s).

### 2.4 Its moves (every one telegraphed: `Enemy.telegraph`, a glint where the danger is, a flash, a growl)

| Move | Wind-up | Then | Hit | Answer |
|---|---|---|---|---|
| Swipe | 0.6 s at phase speed, never under 0.46 s (paw raised high, ears back) | the paw sweeps across, a short lunge | 14, blade, 5.5 m/s, cone 70 degrees, 2 m past its chest | roll back or aside, guard (block), parry |
| Bite | 0.55 s (head drawn back) | lunges ~0.8 m | 18, blade, 4.5 m/s, close | roll, guard, parry |
| Pounce | 1.0 / 0.9 / 0.82 s crouch: tail lashing, eyes flaring, a growl, the big glint; it turns to track him until 0.15 s before it leaves the ground | a long committed leap at where he stood (13.5 / 14 / 15 m/s), then a skid | 22, blunt, 9 m/s, not parryable (a raised shield takes it at a heavy stamina cost) | roll aside as it leaves the ground: **into stone behind him, it is stunned** |
| Short spring | 0.62-0.72 s crouch | a low 3-5 m leap (11 m/s) at a hero who keeps just out of reach | as the pounce | as the pounce |
| Roar (from 66 %) | 0.75 s inhale (head down, chest swelling, the biggest glint, a growl) | the `roar_wave`: rings, dust, a big shake | push only (`amount` 0), unblockable, 15 m/s at the lion falling to half at 9.5 m: the hero is shoved 3+ m off balance; then it springs at him if he landed at pouncing range | roll through it (i-frames) or keep away |
| Perch (from 66 %) | runs to a tor, crouches 0.38 s, bounds onto its top; from there now and then a long bound to another tor straight across the arena | the pounce from above (wind-up x1.05): a real ballistic arc down | as the pounce | dodge into stone as below; or yank it off the rock |
| Enraged chain (under 33 %) | swipe, swipe (0.46 s), a bound back | then the pounce | | |

Phases: **100-66 %** swipe, bite, pounce, short spring; **66 %**: a roar, then roars (every 14 s at most) and the
perches; **33 %**: the roar and it is **enraged**: faster (x1.25), shorter cooldowns (0.7-1.2 s), swipe-swipe-pounce
chains, roars every 9 s at most, the eyes blaze, the ears pin, the mane bristles and the tail lashes (`RigLion.enrage`).

Its brain (`_st_prowl`): an attack every cooldown (1.5-2.3 / 1.2-1.9 / 0.7-1.2 s); within 3.6 m it strikes;
3.4-5 m away it springs; 5-13.5 m away it pounces when the lane is clear (three rays at chest height), else it
circles round the column in the way at ~7.5 m; it runs in from afar. A hero who stays under its nose between attacks
is swatted after 0.9 s. **Its lair**: it moves within 15.5 m of the arena's centre and never follows the hero out
(beyond 19.5 m - deep in a tunnel, outside - it guards the arena on his side, growling).

### 2.5 The boulder and the escape

`encounter.mouth_b_open()` = not `cave().boulder.is_blocking(cave().seal_b, 1.2)`. With mouth B open, the squeeze that
takes it under **50 %** makes it tear free and bolt for the crack (a warning banner: "¡Huye por la grieta!" / "Con la
roca en la grieta no habría podido escapar", the sub only the first time): through tunnel B (round the boulder when it
waits on the apron), and it is gone once out of the camera's view (or 22 m away). Out on the ridge it heals 10 % (up
to 66 %); after 4 s, once the hero is in the arena (or after 30 s), it comes back in **through mouth A, behind him**
(through B if he waits by A): a growl from the tunnel (the only warning), a run, the pounce. Once per fight; a stun on
the way out (or 14 s without getting out) ends the escape for good. With the boulder in the crack it cannot flee.

### 2.6 Victory

The last squeeze: the lion dies (`die()`: the `death` fall, onto its side away from him, played at x2.4 so that the
collapse happens inside the slow motion), hit-stop 0.16 s, slow motion x0.3 for 1.6 s, `lion_death`, an impact
burst; the hero's input is held. +1.8 s `Game.boss_ended(true)` (the bar goes, the music falls silent); once the
body lies still and he stands free (or after 6 s whatever he is doing), Heracles faces the body and `hero.don_lion_skin()`: the rig plays `don_skin` and switches to the
lion outfit (`RigHeracles.set_outfit(&"lion")`: the head as a hood, the pelt as a cape) at `DON_SWAP`, when the body
starts to dissolve (gold motes; freed at the end). **The pelt: blades do 50 % damage to him** (`Hero.PELT_BLADE`).
+2.5 s `main.victory()`: VICTORY phase, `stinger_victory`, the rig's `victory`, the UI's victory card ("Trabajo I
completado · La piel del León", 1.6 s in). After 9.5 s main.gd goes back to PLAY: free roam in the pelt.

**The boat** (`world/nemea_boat.gd`, on the pier): before the labour "Mirar" ("Zarpará cuando el León de Nemea
caiga"); after it, **"Zarpar"**: the hero stands still, the camera pulls out round the ship over the golden sea,
labour II's card ("Trabajo II · La Hidra de Lerna", "Lerna · próximamente", the UI's frieze with the hydra), then a
fade to black and back to the title (the UI's `to_title()`). Chosen over "keep roaming" because the card reads as a
proper ending and the title is where a new run starts.

### 2.7 Hints (one-shot per run, toasts; tokens drawn as the device's keys)

- the first stun before any wrestle: "¡Aturdido! Agárralo con {interact}" / "Aprieta en el destello · el escudo aguanta sus sacudidas" (key tokens only in the first line: the toasts draw them there);
- 40 s of fight without a stun: "Que choque contra la piedra" / "Esquiva su salto junto a una columna, o tira de él con la cadena";
- the escape (above). The rule is the warning banner of the first blade bounce.

### 2.8 The arena (lane L dressing, `nemea_cave.gd`)

Nothing moves the columns, the floor or `World.cave()`'s keys. The columns keep their places and profiles (the
profile comes from the same random numbers): their surface is flowstone with five shallow flutes and lumps, broad
horizontal strata in three tones, a damp foot, two or three old cracks; collision steps follow the flared foot (0.5 m
cylinders to 3 m). **Cracks grow where the lion slams** (`crack_at(point, normal, power)`: a star of cracks, four
stages per column, chips at its foot; dust and smoke elsewhere). Four tors (2.3 m, flat tops of 1.75 m radius,
convex-hull collision) by the walls: the perches; the north one is the den, in a shaft of light (a spot light and a
glowing crack in the ceiling), with bones and a goat skull before it, claw marks raked down the two columns nearest it
and gouged in the floor. An old bronze shield on its back (green patina) and a broken spear (a hunter who came first), rubble that blocks
nothing, small stalagmites at the walls (solid). The tunnels' openings and the middle of the floor stay clear; the
columns, the tors and the claw marks are in `camera_cut` (cut away between the lens and the hero).

### 2.9 Tests (`tools/lion_bot.gd`)

```sh
# the units (60 fps, headless): 12 tests; careless (balance) runs on its own (the victory test frees the lion)
godot --headless --path doce/game --fixed-fps 60 --quit-after 60000 -- play=1 lionbot=units quit=1 | grep "LION test\|LION autotest"
godot --headless --path doce/game --fixed-fps 60 --quit-after 60000 -- play=1 lionbot=careless quit=1 | grep "LION test"
# the whole fight, mouth B sealed / open (PASS/FAIL per phase)
godot --headless --path doce/game --fixed-fps 60 --quit-after 60000 -- play=1 lionbot=fight_sealed quit=1 | grep "LION fight\|LION test"
godot --headless --path doce/game --fixed-fps 60 --quit-after 60000 -- play=1 lionbot=fight_open quit=1 | grep "LION fight\|LION test"
```

Args: `lionbot=<tests>` (`units` = bounce, strike, pounce, yank, wrestle_win, wrestle_fail, roar, perch, escape, lair,
death_reset, victory; `careless`, `fight_sealed`, `fight_open`, `probe`, `watch`), `quit=1`, `botdebug=1` (traces), `liondebug=1`
(the lion's state changes), `nocard=1` (labour I's card counts as shown: renders), `lion=0` (no lion), `fight_t=`
(the fight's time limit). The bot plays the real hero through the real input path (`HeroInput.bot`, `debug_move`, the
camera aiming the chain) and reads the lion's telegraphs like a player.

Args: `linger=<s>` keeps the game running that long after the last test (movies: the victory card).

### 2.10 Results (2026-10-11, headless, 60 fps, this lane's copy of the merged game)

| Run | Result |
|---|---|
| `units` | **12/12 PASS**. bounce: 2 bounces, no damage, the hero recoiled twice, the rule said once. strike: -14 hp, pushed 0.9 m; the parry threw it open. pounce: a column 2.4 m behind him, slammed, stunned, the column's cracks 0 -> 1. yank: slammed, stunned. wrestle_win: 3 squeezes, 300 -> 259.5, downed; the hero hidden 0 % of the wrestle's frames. wrestle_fail: thrown off 1.4 m, -8 hp, then back on his feet (no buffered swing at it). roar: shoved back 3.2 m, no damage. perch: yanked off its rock, fell, stunned. escape: out of sight in 3.7 s, healed 135 -> 165, back in through mouth A 3.7 s later with a pounce. lair: the hero 28.8 m out in tunnel A, the lion never beyond 9.1 m of the centre. death_reset: the lion in its den at full health, `boss_ended(false)`, the hero at the Altar de la Sierra, the boulder unmoved. victory: dead, pelt (outfit lion), VICTORY, back to PLAY, the boat ready, "Zarpar", labour II's card, the slice ended |
| `careless` | PASS: killed after 20 s (5 swipes, 2 bites), 23 blades bounced, the lion back in its den |
| plain starts | the title and `play=1` for 1500 frames: no script error, no warning |
| `fight_sealed` x4 | **PASS** all: won in 98 / 98 / 83 / 103 s, 9 wrestles (3 per phase), none lost; slams: pounce 7-9, falls off a perch 0-2; no escape; the bot never hit |
| `fight_open` x5 | **PASS** all: won in 108 / 117 / 113 / 122 / 103 s (the last one is the movie's run); it fled at 46 % (46-55 s in) and ambushed him from mouth A 10-11 s later; 10 wrestles; slams: pounce 5-8, yank 0-3, falls 1-4; the bot never hit |
| the wrestle's view in those fights | the hero fully hidden behind the lion's head in 0-12 % of the wrestle frames (partly 1-9 %) |
| the dressed cave against CORE's and WORLD's checks | `corebot=1` 6/6 PASS (the cave test: all 6 pillar legs, the boulder into mouth B), `corebot=walk` PASS (8 steps, pier to the sealed crack), `tools/world_check.tscn` 0 fails (cave keys, pillars in the arena, the lion's spawn clear, both mouths reachable) |

### 2.11 Renders (the gameplay camera, `--write-movie`, lane L's work dir `shots/`)

Strips of each key moment, one row per moment, frames labelled: `strip_A_bounce_strike_pounce` (the blade bounce
and the rule said once; a swipe on a still hero and a parry; the pounce dodged into a column, stunned),
`strip_B_yank_wrestle` (the yank into a column; a won wrestle, the lion thrown down), `strip_C_perch` (it bounds
onto a tor, is yanked off, falls stunned), `strip_D_escape_ambush` (mouth B open: it flees, comes back through mouth
A behind him), `strip_E_death_reset` (the hero falls, back at the Altar de la Sierra), `strip_H_wrestle42` (the
hold beside its head), `strip_I_wrestle_fail` (thrown off), `strip_J_roar` (the inhale, the wave, the shove),
`strip_K_victory` (the last squeeze, the collapse in slow motion, the pelt, the victory card), `strip_L_boat`
("Zarpar": labour II's card, the ship, the fade). The whole fight with mouth B open, from the gameplay camera:
`lion_fight_open.mp4` (640x360, 10 fps, 2 min, with the game's sound; the bot's run, intro card to victory card),
`strip_M_movie_overview` and a few of its frames (`movie_*.png`).

### 2.12 Open points

- **The wrestle's camera** (CORE, `CameraRig._pick_grapple_offset`) frames round the beast's origin, the middle of
  its body, and tests only the world for what hides the hold; the lion's hold is at its neck, 1.2 m ahead, so some
  angles look at the hero past the lion's head and mane. Measured by the bot (the gameplay camera, the head and ruff
  as a ball): with the hold at 90 degrees round from the nose the hero was fully hidden 18-25 % of a wrestle's
  frames, at 65 degrees 4-8 % alone but 8-23 % in real fights. Now: the hold at 42 degrees on the camera's side,
  plus an additive hook in `camera_rig.gd` (`_frame_score` lowers the score of a view through the held beast's
  `wrestle_view_block()`, the lion's head as a 0.7 m ball): 0 % in the unit test, 0-12 % in the fights (partly
  1-9 %). The UI's wrestle prompt stays readable meanwhile. A cleaner CORE fix: frame round `Hero.grapple_point()`
  and add the enemies layer to `_frame_score`'s sight rays.
- The chain yank pulls the lion into the column between them: at the slam the column stands between the camera and
  the lion (seen through the camera's cut-away screen door). The pounce slam reads much better.
- A lion perched on a tor is often off the follow camera's view (high and to the side): the lock-on finds it; CORE
  could count a perched or leaping beast as camera interest.
- The lion keeps watch standing on its den rock: RigLion has no lying pose.
- Balance is tuned with bots only: the fight bot (perfect reads) wins without being hit; a careless hero (hacking,
  no roll, guard or chain) dies in ~20 s. A human playtest should check the wrestle windows (0.5 / 0.46 / 0.42 s)
  and the last phase's pace.
- The toasts draw key tokens only in their first line (UI): the hints keep tokens there.
- `Fx._step_dazes` (CORE) casts the daze node before checking `is_instance_valid`: a freed node raises "Trying to
  cast a freed object" every frame. The lion works round it (its stars circle a proxy node it takes out of the tree);
  fx.gd should check validity before the cast.
- The tors' tops are irregular (an angular outline round a flat top of at least ~1.6 m radius); the lion's ground
  (its paws' IK) takes a 1.75 m circle, so a paw at the very edge of a narrow side can stand a few cm over air.

---

## Part 3 · The merge and the playthrough

### 3.1 How the lanes were merged (2026-10-11)

Both lanes worked in copies of commit 180177b, and the live project had not changed since. No file was changed by both
lanes, so the merged game is their union: lane P's 16 files (the beasts, `pack.gd`, `pack_nav.gd`, the rig additions,
`nemea_layout.gd`, the encounter bot and its scene) and lane L's 13 (the lion, its encounter, its bot, the cave's
dressing, the boat, and its additive changes in `main.gd`, `hero.gd`, `rig_lion.gd`, `camera_rig.gd`, `ui.gd`). No
three-way merge was needed for the game; the two halves of this file were joined (Part 1, Part 2) and Part 3 added.

Every suite passed on the merged tree before anything else changed: the arena bot 16/16, CORE's island bot 6/6 and
its slice walk, the encounter bot 12/12 (with the lion present in its cave), the lion's 12 units, the careless
hero, the whole fight with mouth B sealed and open.

### 3.2 Fixes made at the merge (`scripts/enemies/boar.gd`)

The playthrough found two problems with the boars that no lane test covered (the lane tests set each boar fight up
by hand):

- **A boar that never attacked again.** In READY a boar backed off from a hero closer than `CHARGE_MIN - 0.5` (4.0 m)
  but its charge needs `CHARGE_MIN` (4.5 m, `member_ready()`), and the gore needs 2.5 m: a boar standing 4.0-4.5 m in
  front of a hero who stood still did nothing, forever (seen with the herd of two: 140 s frozen). It now backs off to
  `CHARGE_MIN + 0.2`.
- **Juggling.** Each combo's finisher (stagger 0.75 >= the boar's poise 0.7) re-staggered it before it recovered, so a
  parried boar was cut down in ~4 s without ever getting up (150 -> 0 hp, seen in the trace). Now a boar that has
  been helpless (staggered, not stunned) for `HELPLESS_MAX` 2.6 s in a row shrugs blows off (poise 99) until it has
  charged or gored again, or for `ARMOR_T` 2 s. A crash's stun (3 s, blows x1.25) is not counted: the rock is still
  the best answer. After the fix the herd of two took 4-6 parries in three playthroughs (two or three per boar, as
  Part 1 intends) instead of one each.

The boar tests were re-run after the fixes (`encbot=boar_parry,boar_block,boar_yank,boar_crash,clip`: 5/5 PASS) and the
whole encounter bot in the live project (3.4).

### 3.3 The playthrough (`tools/playthrough.tscn`, `tools/playthrough_bot.gd`)

The whole slice in one run of the real game, as a player would play it, through the hero's real input path (the
bot's virtual buttons, the stick, the camera aiming the chain): it never teleports the hero, heals him or touches a
beast. It starts at the title menu ("Comenzar" through the UI's `begin_game()`) and ends back at the title after the
boat's teaser (the scene reloads; the bot lives under the tree's root so it sees the title come back).

| Step | What happens | How the bot plays it |
|---|---|---|
| title | the title menu, "Comenzar": PLAY on the pier | |
| village | down the pier and up the main road into the village | CORE's waypoint follower (steps aside round trunks and stones) |
| cat | a cat petted: it purrs, the hero plays `pet` | E held beside the nearest cat |
| wolves | the first pack (3) notices him on the forest road | lane P's skilled policy (`EncounterBot._fight`: rolls a wind-up as it runs out, punishes the opening) |
| wheat | on west along the road through the fields (where the wheat field is planned; it is not in this build) to the passage's south rim | |
| passage | the ring on the sea stack, then the north rim | CORE's walk moves (aim, throw, zip) |
| boars | the boar of the first clearing, then the herd of two on the thumb path | its own boar policy: waits in front of a standing rock of the clearing (a charge met there is rolled aside: it runs into the rock), parries every other charge and gore, punishes a staggered, stunned or recovering boar |
| altar | the Altar de la Sierra: prays (healed, the checkpoint) | |
| boulder | the meadow path to mouth B, the boulder hauled into the crack from inside it | CORE's boulder routine, walking to its throw spot instead of teleporting |
| cave | through the crack's tunnel into the arena: the lion wakes, labour I's card, the boss bar | |
| lion | the fight to the end | lane L's fight brain (`LionBot._bot_tick`: baits pounces into the columns, yanks it into them, wrestles in the windows); a fall would bring him back from the altar through mouth A |
| pelt | the pelt (outfit lion), the victory card, back to free roam, the boat ready | |
| return | out through mouth A, over the meadow, off the escarpment (10 m, no fall damage), south through the forest west of the second pack, the road through the village to the pier | sprinting on the road |
| boat | "Zarpar": labour II's card, the fade, the title again | |

```sh
cd doce/game
timeout 2400 godot --headless --path . res://tools/playthrough.tscn --fixed-fps 60 --quit-after 300000 -- ptbot=1 quit=1 | grep "PT step\|PT playthrough"
# with a PNG at each step and at the fights' key moments (the gameplay camera; rendering is switched off in between,
# RenderingServer.render_loop_enabled, so the run costs ~15 min instead of hours of movie frames)
timeout 5400 xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 \
  --fixed-fps 30 --quit-after 150000 res://tools/playthrough.tscn -- ptbot=1 ptshots=/abs/dir quit=1
```
Lines: `PT step <name> PASS|FAIL <details>`, `PT fight ...` (each fight: time, health, hurts, rolls, parries, crashes),
`PT message [kind] text / sub` (every toast), `PT labour card`, `PT boss_started / boss_ended`, `PT mark <tag>` (the
shots), `PT camera` (CORE's camera watch, for information), and `PT playthrough passed=N/M result=PASS|FAIL deaths=D
time=<s>`. `botdebug=1` traces the fights.

### 3.4 Results (2026-10-11)

| Run | Result |
|---|---|
| playthrough, headless, merged copy | **14/14 PASS**, 273 s of game time, no death; wolves 10.1 s (3 rolls, all perfect dodges, never bitten); the clearing boar crashed into its rock and was cut down in 7.1 s; the herd 14.7 s (4 parries); the lion 77 s (9 wrestles won, none lost; 8 dodged pounces into stone, 1 fall off a perch); the hero never hurt |
| playthrough with shots, merged copy | **14/14 PASS**, 288 s, no death; the herd hurt him once (18, gore); the lion 88 s (9 wrestles, 7 pounce slams, 2 falls); 68 PNGs |
| playthrough, headless, the live project after the copy | **14/14 PASS**, 303 s, no death, never hurt; wolves 10.1 s (3 perfect dodges); the clearing boar 6.9 s (1 parry), the herd 22.9 s (6 parries); the lion 102 s (9 wrestles won, none lost; 7 pounce slams, 1 yank into a column, 1 fall off a perch) |

Every other suite ran on the merged tree and again in the live project after the copy (docs/ARCHITECTURE.md 10.2).
The encounter bot: 12/12 on the merged tree and in one live run; the other live run failed `clip` on a graze (a
boar's muzzle 2.2 cm into a rock's convex hull, under the 3 cm limit, in 56 of 9495 samples where 0.2 % are allowed,
while it lay stunned against the rock it had crashed into: the graze depends on which rock it crashes into).

The fight numbers come from a bot that reads every telegraph perfectly; they show the slice can be finished and every
mechanic works on the real island, not how hard it is for a person.

### 3.5 Open points (merge)

- The thumb's golden grass is about as tall as a boar: in the shots a winding-up boar is half hidden in it, and it
  flashes almost white for a frame as the telegraph starts (CORE's `Enemy.telegraph()` `hit_flash`). Lane P's
  report already notes the flash.
- The wheat field (the grass lane) is not in this build: the "wheat" step walks the fields where it is planned.
- The `clip` test of the encounter bot can fail on grazes depending on which boar and rock it picks (1 of 2 live
  runs: 0.6 % of samples where 0.2 % are allowed, 2.2 cm deep); the boar's dazed head-down pose against a rock's hull.
- No healing between the wolf pack and the Altar de la Sierra (two boar fights in between): a hurt player meets the
  boars hurt (Part 1, 1.11).
- Camera (CORE): in the forest fights a tree crown can fill a third of the view; walking into the crack's tunnel
  after sealing it, the camera stays in front of the hero (looking back at the boulder) until he is out of the
  tunnel; aiming the chain at the lion on a tor, the over-the-shoulder aim view is filled by the hero's helmet; the
  cat being petted is hidden behind the hero.
- After the death fall the lion's mane lies against the hero's legs and his sword hand (the shots `pt_56`, `pt_57`):
  possibly a few centimetres of overlap; not measured (lane L listed it).
