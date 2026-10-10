# DOCE · Combat (CORE)

How Heracles fights and moves with the chain spear, every number, and the contracts the ENCOUNTERS stream builds
the wolves, the boars and the Nemean Lion on. Code: `scripts/player/` (hero.gd, hero_melee.gd, hero_input.gd,
chain_spear.gd), `scripts/combat/` (combat.gd, blade_trail.gd), `scripts/camera/camera_rig.gd`,
`scripts/enemies/enemy.gd`, `scripts/gfx/rig_heracles.gd`; test bed `tools/arena*`. Contracts not repeated here
are in `docs/ARCHITECTURE.md` (section 5). Units: metres, seconds, m/s; angles in degrees unless noted.

---

## 1. Controls and how the buttons are read

| Action | Keyboard / mouse | Pad | Notes |
|---|---|---|---|
| Light blow (combo of 3) | left click | X | starts at once on the press, at full speed, however long the button stays down |
| Heavy blow | hold left click | hold X | the light blow plays first; still held 0.28 s after the press once its active frames are over, the heavy blow coils out of its follow-through (CHARGE, the Zelda spin attack); 0.24 s of coil: charged (glint + ring + sound); release charged: the spin slash. Released before: the coil relaxes (the next press goes on with the combo). Held through a recoil or a roll: it coils from the stance |
| Guard / parry | right click hold | LT | a press opens a 0.18 s parry window, counted from the press (also when the shield only comes up a moment later, out of a blow's recovery or the end of a roll) |
| Roll / backstep | Shift tap | B tap | in a fight (locked on, or foes within 11 m) the roll starts on the press; elsewhere on the release of a tap shorter than 0.15 s. With a direction: roll; without: backstep |
| Sprint | Shift hold (>= 0.15 s; in a fight held on through the roll) | B hold, L3 click | |
| Chain spear | Q | RT | press: throw (or call the spear back when it is out; pressed while it flies home it snaps back and the new throw goes at once); hold: keep hauling a boulder |
| Lock on | Tab / middle click | R3 | flick the right stick, or the mouse sideways (80 px of quick motion: only frames faster than 500 px/s count, the sum leaks 6/s, so a slow drift never switches), to switch target |
| Interact / grapple | E | Y | a stunned beast within 3 m is wrestled before any other interactable |

`HeroInput` samples every button once per physics tick (held, pressed / released this tick, hold time, time since
the last press). A press and its release inside one tick still count. The click that captured the mouse never
attacks. Tests drive the same path through `hero.inp.bot[&"attack"] = true` and `hero.debug_move`.

Buffers: attack 0.30 s (consumed when a combo window opens, a recovery can be cancelled or a state ends), roll
0.25 s, chain 0.25 s, jump 0.14 s. They run down only while the hero is free (MOVE); while a blow, a charge, a roll,
a throw, the chain or a stagger runs out on its own they wait, up to 0.6 s after the press (the roll 0.45 s), so a
press made during a long recovery is never lost (measured: a press 0.10 s after the finisher's or the heavy's
contact, during a yank, or while the spear flies home, is kept every time).

---

## 2. The hero's state machine (`Hero.state`, `Hero.state_name()`, signal `state_changed`)

| State | Entered by | Leaves to | Notes |
|---|---|---|---|
| MOVE | default | everything | ground / air / swim locomotion; guard while held on the ground; sprint; jump; interact |
| ATTACK | attack (MOVE, combo window, the finisher's / heavy's `rearm` key, end of a roll, arrival of a chain pull, a yanked foe in the air) | ATTACK (next blow), CHARGE (held on), MOVE (the end; or a stick push past 0.6 from the blow's `move` key), DODGE / THROW / MOVE+guard (recovery only), STAGGER (deflect) | HeroMelee |
| CHARGE | attack held 0.28 s after the press once the light blow's active frames are over (out of its follow-through), or held on in MOVE | HEAVY (released charged), MOVE (released early: the coil relaxes), DODGE | slow walk 1.5 m/s, turns to the input / lock target |
| HEAVY | release when charged | MOVE, ATTACK (`rearm`), DODGE / THROW (recovery) | the spin slash, 22 stamina |
| DODGE | roll press / tap on the ground with >= 11 stamina | MOVE, ATTACK, DODGE or MOVE+guard (last 28 %) | i-frames; the body faces the roll at once |
| STAGGER | hits, guard break, deflected blade (recoil), end of a wrestle | MOVE | no control; knockback decays at 18 m/s^2 |
| THROW | chain press (ground, air, hanging) | MOVE (0.12 s after release), CHAIN (the spear bites) | the hero keeps hanging if thrown from a ring |
| CHAIN | the spear bit an anchor | MOVE, HANG, ATTACK (a buffered blow on arriving at a heavy target, or once a yanked foe is in the air), DODGE (a yanked foe in the air) | modes zip, to, climb, hop, yank, beast, haul (`Hero.chain_mode`) |
| HANG | zip arrived at a ring with no ledge to climb | THROW (next ring), MOVE (jump / roll / 6 s) | gravity off, the spear stays in the ring |
| GRAPPLE | interact by a stunned beast (`can_grapple`) | STAGGER (grapple_end or thrown off) | the target drives the rhythm |
| DEAD | hp 0 | (revive) | Game.hero_died |

Any hit (`_hurt`) cancels attacks, charges, throws, the chain and the wrestle.

---

## 3. Numbers

### 3.1 Movement (first pass from the skeleton, unchanged unless noted)

| | Value |
|---|---|
| Walk / run / sprint | 2.2 / 6.2 / 9.0 m/s (stick under 55 % walks) |
| Locked-on run, guarding, charging, hauling | 5.0 / 2.6 / 1.5 / 2.0 m/s |
| Exhausted | run at 80 %, no sprint, roll or heavy blow |
| Acceleration / deceleration / in the air | 40 / 48 / 11 m/s^2 |
| Turning | 13 rad/s (x1.6 standing, x0.6 sprinting, x0.5 in the air); locked on 16.9 rad/s towards the target; guarding 12 rad/s towards the foe that threatens him or the one he fights, else 10 rad/s towards the camera's forward |
| Jump | 8 m/s (about 1.3 m), coyote 0.12 s, buffer 0.14 s, early release x0.45, fall x1.55, terminal 45 m/s |
| Slopes, steps | 46 degrees, step-ups 0.42 m, floor snap 0.45 m |
| Hard landing | above 13 m/s: 0.3 s at quarter speed and a shake |

### 3.2 The sword (HeroMelee.LIGHT / HEAVY)

Times are the rig's authored seconds (`RigHeracles` keys); `speed` scales them (real time = authored / speed).

| Blow | speed | active | combo opens | cancel from | move from | rearm | length (real) | first contact* | damage | knockback | stagger | hit-stop | shake | nudge |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| attack1 forehand | 1.05 | 0.125-0.29 | 0.29 | 0.30 | 0.38 | - | 0.53 s | 0.17 s | 10 | 3.8 | 0.35 | 0.07 | 0.35 | 0.18 |
| attack2 backhand | 1.05 | 0.115-0.28 | 0.28 | 0.29 | 0.37 | - | 0.53 s | 0.13 s | 10 | 3.8 | 0.35 | 0.07 | 0.35 | 0.18 |
| attack3 overhead (finisher) | 1.00 | 0.262-0.42 | - | 0.50 | 0.58 | 0.55 | 0.80 s | 0.33 s | 18 | 8.5 | 0.75 | 0.11 | 0.47 | 0.40 |
| heavy spin (charged) | 1.00 | 0.37-0.68 (360 degrees) | - | 0.80 | 0.88 | 0.85 | 0.70 s after release | ~0.13 s after release | 30, guard_break | 11 | 1.1 | 0.16 | 0.62 | 0.36 |

`move from`: a push of the stick past 0.6 ends the recovery into the
run (0.12 s blend). `rearm`: a press (or a buffered one) starts a new combo from here (the finisher and the heavy have
no combo window). \* measured on a post 2.2 m away, the lunge ending 0.82 m from its centre. Knockback is the
initial shove in m/s (decays at 18 m/s^2: 3.8 m/s moves a foe 0.40 m, 8.5 about 2.0 m, 11 about 3.4 m before
`knockback_resist`; the arena's straw soldier, resist 0.6: 0.08 m for one light blow, 0.50 m for the combo, 0.66 m
for the heavy; the sack, resist 0.35: 0.19 / 1.27 / 1.88 m).

Measured at 60 fps (probe runs in the arena, section 8.1): press to contact 0.167 s for any press up to 0.35 s long
(the button's hold never delays the blow); a fast combo lands at 0.167 / 0.418 / 0.869 s; with a stick push the hero
is running again 0.20 s after a light blow's contact, 0.29 s after the finisher's, 0.47 s after the heavy's (without
it: 0.37 / 0.49 / 0.57 s, the end of the follow-through); a roll pressed at a contact starts 0.135-0.186 s later
(the `cancel from` key). Hit-stop frames: 4 / 4 / 7 / 10 at 60 fps and 2 / 2 / 3 / 5 at 30 fps (attack1 / attack2 /
finisher / heavy). Peak screen motion of the shake plus the nudge at 1280x720 with the hero 6 m away: about 3 px for
a light blow, 9-10 px for the finisher (its trauma adds to the combo's) and 12 px for the heavy at 60 fps; 3 / 7 /
9 px at 30 fps, where fewer frames catch the jolt's peaks.

- **Combo**: a press during a blow is buffered (section 1) and fires the next blow the moment the window opens (end
  of the follow-through). After a blow ends, a press within 0.25 s of game time still continues the combo. attack3
  ends it; a press from its `rearm` key starts a new one.
- **Tap or hold**: a press always starts the light blow at once, at full speed. If the button is still down 0.28 s
  after the press (`HeroMelee.CHARGE_HOLD`) once the blow's active frames are over, the heavy blow coils out of the
  follow-through (its wind-up from 0.1 s in, no pass through the stance; needs 11 stamina and not exhausted); held
  in MOVE (through a recoil, a roll, a landing) it coils from the stance. The charge tremble (`RigHeracles.charge`)
  grows; after 0.24 s of coil (`CHARGE_TIME`): charged (glint at the blade tip, a ring at the feet, `charge_ready`
  if that sound exists, else `parry` pitched up and quiet). Let go before: the coil relaxes into the stance (0.18 s)
  and the combo goes on from the last light blow. A firm tap (0.15-0.4 s) is just a light blow, never a delayed
  one, and no wind-up is shown twice.
- **Cancels**: the recovery (from `cancel from`) can become a roll, a throw or the guard; a stick push ends it from
  `move from`; never the wind-up or the active frames. The last 28 % of a roll can become a blow, another roll or the
  guard.
- **Magnetism**: at the start of a blow the hero turns to (26 rad/s through the wind-up) and lunges towards the
  best foe in a 35-degree half-angle cone round the input direction (or his facing) within 2.5 m of its surface;
  locked on: the lock target within 4.5 m, with 0.5 m more lunge. The lunge stops 0.5 m from the foe's surface
  (the xiphos reaches 0.85 m straight ahead, 1.2-1.4 m at the ends of its arcs), up to 1.4 m (attack1/2), 1.5 m
  (attack3), 0.6 m (heavy); it runs from 0.02 s to the first active frame (+0.04 s) along a displacement curve
  (a sine ease-out: quick out of the blocks, peak speed 1.57 x the mean, planted at the end) that the hero follows
  exactly, so it never overshoots into the foe; then the feet plant (45 m/s^2). No foe: a 0.3 m step into the blow;
  out of a run (faster than 3 m/s) at nothing, the run carries on into the blow and slows at 13 m/s^2 (1.5 m from
  6.2 m/s) instead of stopping dead. The body turns with the wind-up at 40/s (18/s otherwise), so a blow at a foe
  behind him lands square.
- **Hits**: the blade (`RigHeracles.blade_segment()`: root 0.1 m to tip 0.64 m from the grip, plus 0.12 m of
  gameplay reach past the tip) is sampled each time the rig poses a new frame; between two samples four points along
  its length each travel an arc round the hero's (moving) centre, in sub-steps of 12 degrees, and the part of that
  move inside the active window is tested exactly (a frame that straddles the window's start or end is clipped), so
  the same swing hits the same things at 24 fps and at 144 fps. The test is top-down against every foe's hurt
  volumes (`Combat.hurt_volumes`) with a radius of volume + 0.12 m, inside a vertical band from 0.9 m under the
  blade to 0.35 m over it (a chest-high cut still finds a wolf). Each foe is hit at most once per blow (the reach and
  the radius are tight enough that the freeze frame shows the blade on the body, not air before it). The contact
  point is on the volume's surface at the blade's height. (The bot's combo, heavy and every other test pass at both
  60 and 24 fps.)
- **When it lands** (`take_hit` returned true): `Fx.impact` (white star flash, radial streaks, sparks; power 0.7 /
  1.1 / 1.6), dust at the foe's feet for the finisher and the heavy, `hit_1/2/3` or `hit_heavy` at the contact
  (pitch 0.92-1.08), one hit-stop per blow, `Game.shake`, `CameraRig.nudge` along the blow, signal
  `Hero.blow_landed(target, hit)`. The foe flashes (`Rig.FLASH_LIGHT` 0.4, `FLASH_HEAVY` 0.6 for stagger >= 0.5:
  white for its first frame, then fading 13/s of real time through the freeze, so the frozen frames show the blow's
  pose and the body's reaction, not a white silhouette) and, when the blow beats its `poise`, flinches (6.3). The
  knockback direction is away from the hero, bent 45 % along the blade's motion (radial for the spin). Swing sounds
  `swing_1/2/3` / `swing_heavy` play as the blade starts to move.
- **The trail**: `BladeTrail`, a crescent over the last 0.2 s of the blade, drawn after the rig has posed (process
  priority 20): a white leading edge at the tip, a cool sky-blue core down the blade (0.66, 0.86, 1.0: it stands out
  against the warm golden-hour palette, the sand and the red cape; gold (1.0, 0.8, 0.36) for the charged spin) from
  0.1 of the blade, narrowing with age. It is drawn 1.3 m nearer the camera in depth
  (`fx.gdshader` `view_pull`, render priority 10): the same place on screen, but it shows over the hero's own body
  and the foe it cuts (from behind him the backhand's blade is behind his back), while walls further away still
  hide it.

### 3.3 Defence

| | Value |
|---|---|
| Guard | held in MOVE on the ground; covers +-70 degrees round the facing; blocks blows unless `unblockable`. Not locked on, the raised shield turns him (12 rad/s) to the foe winding up a blow at him in view (`Hero.threat()`), else to the foe he fights (the sword's focus), else to the camera's forward. The shield is held forward-left of the chest (its rim shows past his left side from behind) and the camera keeps no right-shoulder offset while he guards (section 5) |
| Block cost | 6 + 0.9 x damage stamina (x1.4 for blows with stagger >= 0.5); 60 % of the knockback (a short shove back); shield jolt (`guard_impact`), sparks at the shield, `shield_block`, hit-stop 0.04, shake 0.12 |
| Guard break | stamina short of the cost, or `hit.guard_break`: stamina 0 (exhausted), half the damage, `hit_heavy` stagger, signal `guard_broken` |
| Parry | the hit lands within 0.18 s of a guard press, counted from the press even when the shield only comes up a moment later (out of a blow's recovery or the end of a roll; a new window only 0.4 s after the last). Measured: parried with the press 0.03-0.19 s before the hit from MOVE, and 0.10 s before it from attack1's recovery: no damage, +8 stamina, the shield punches (`parry`, upper body), `parry` sound, impact burst + ring at the shield, hit-stop 0.10, slow motion x0.25 for 0.22 s, shake 0.2, `attacker.on_parried(hero)`, signal `parried`; not for `parryable: false` or `unblockable` blows |
| Roll | 0.55 s, 4.0 m along the input (camera / lock relative), i-frames 0.05-0.35 s, 22 stamina, needs 11. In a fight it starts on the press (0 s), elsewhere on the release of a tap. The body faces the roll at once (no sideways skate) and the distance goes with the tumble (`Hero.ROLL_PATH` against the rig's dodge time: 6 % in the crouch by 0.08, an even 10 m/s through the 360 degrees to 90 % at 0.45, eased to 4.0 m at 0.55): 22 % of the roll is covered when the tumble passes 90 degrees |
| Backstep (no input) | 0.42 s, 2.2 m back, i-frames 0.03-0.24 s, 22 stamina |
| Perfect dodge | the first blow that meets the i-frames: slow motion x0.3 for 0.28 s, a ring and a glint, `dodge` pitched up, signal `perfect_dodge` |

### 3.4 Stamina and health

| | Value |
|---|---|
| Max | 100 stamina, 100 hp |
| Costs | sprint 16/s, roll 22, heavy 22, block 6 + 0.9 x damage |
| Regeneration | 34/s after 0.7 s without spending; none while guarding, charging or wrestling |
| Exhausted | at 0: until back to 35 % (field `exhausted`, read by the UI's stamina ring): no sprint, roll or heavy blow, run at 80 %, `RigHeracles.tired` (heavier breathing, the head drops) |
| Taking a hit | invulnerable for max(0.35, the stagger + 0.1) s (light 0.37 s, heavy 0.64 s: a pack cannot hit him again before he can act); flash 0.4 (light) / 0.6 (heavy); light (`stagger` < 0.5 and damage < 25): `hit`, 0.27 s without control, shake 0.25, hit-stop 0.05; heavy: `hit_heavy`, 0.53 s, shake 0.45, hit-stop 0.08; knockback from `hit.dir` x `hit.knockback`, decaying at 18 m/s^2 and kept apart from his own run speed (3.5 m/s moves him 0.34 m, 7 m/s 1.4 m); red screen flash (`Fx.flash_screen` -> the UI's `screen_flash`); `hero_hurt` |
| Lion's pelt | `Hero.don_lion_skin()`: blades do 60 % |
| Shove | a push-only hit (`amount` 0, `knockback` > 0: the lion's roar wave): knocked back and off balance for the light flinch (no damage, no hurt sound, no red flash; `hit["shoved"]`); on the raised shield only 40 % of the push and a jolt. `take_hit` returns false |
| Death | `hero_down`, rig `death`, `Game.hero_died` (main.gd respawns at the last altar after 3 s); the felling blow weighs: hit-stop 0.12 s, then slow motion x0.35 for 0.6 s, shake 0.5 |

### 3.5 Feel helpers

`Game.hitstop(s)` and `Game.slowmo(scale, s)` run on an unscaled frame clock (the wall clock in play, frame time in
`--fixed-fps` / movie runs). **Real-time code must use `Game.real_delta(delta)`**, never
`delta / Engine.time_scale`: the engine reads the time scale once per frame, so in the frame where a hit-stop
starts the current `Engine.time_scale` is 50 times smaller than the one that frame's delta was made with.
(`scripts/ui/style.gd` and `scripts/core/audio.gd` still divide by `Engine.time_scale`, clamped to 0.1 s: a
0.1 s jump on the first frame of each hit-stop. Their owners should switch.) A hit-stop asked for during a frame
only starts with the next frame, so `Game.hitstop` counts its deadline from the end of the current frame (the last
frame's length is the estimate, half a frame off): the frozen frames are the asked seconds x the frame rate,
rounded.

`Game.shake(trauma)` (0..1, added up): the camera's h/v offsets swing up to 0.35 m x trauma^2 and roll up to
0.05 rad x trauma^2, decaying 1.7/s; the direction comes from a 0.6-frequency simplex noise (a ~15 Hz jolt, not
per-frame jitter) and its size is kept at 60-100 % of the full swing (noise alone often sits near 0 for a few
frames: the same blow would shake 1 px one time and 5 px the next). `CameraRig.nudge(dir, k)`: a spring (k 160,
damping 18) kicked 9 x k along the blow. The hit flash (`Rig.hit_flash`, lowpoly `flash`) reads pale at 0.1 and
white from about 0.3 on a sunlit body; it shows at full strength for its first frame and then fades at
`Rig.FLASH_DECAY` (13) per second of real time.

---

## 4. The chain spear (`ChainSpear`, `Hero` CHAIN / HANG)

| | Value |
|---|---|
| Range | 22 m from the hero's shoulder; let go beyond 26 m |
| Aim assist | the best `chain_anchor` (alive, 1.2-22 m away, in front of the camera) inside 12 degrees of the camera's forward, + up to 25 degrees for close targets (fades from 3 to 14 m); score = angle / cone + 0.3 x distance / range; the four best are checked for line of sight on the world and movable layers (the anchor itself does not block); refreshed 20 times a second; `Hero.chain_candidate` + signal `chain_candidate_changed(target)`; a subtle bronze glint marks it (not on a foe within 3.2 m, not while swinging) |
| No target | the spear flies to what the camera centre looks at (first surface within range) or to the end of the range; a wall or the ground sends it back with a clink |
| Throw | rig `throw` at x1.75 (upper body when moving or airborne): the left hand draws the spear from the back and lets it go at the `release` event, 0.27 s after the press; `chain_throw`. The flying spear starts with its butt ring in the fist and its head 1.37 m ahead (never back through his head; a wall closer than that: the head starts at the wall). A ring 12 m away bites 0.45 s after the press (it was 0.57) |
| Flight | 50 m/s, homing on the target's `chain_point()`; the first anchor it touches on the way is the one it bites (`chain_stick`, sparks, a little shake, `on_chain_attach(hero)`) |
| Return | butt first into the left fist, 10 -> 40 m/s (110 m/s^2), going round whatever the chain is bent over (below); `chain_rattle`. The catch: the fist closes on it (`chain_rattle` -2 dB, a spark, shake 0.05) and, free in MOVE, the upper body plays `catch` (0.46 s: the shaft swung up over the shoulder and strapped on the back at 0.24 s) |
| The chain | dark bronze links (one MultiMesh, up to 260 links, 0.095 m apart, 0.12 x 0.07 m) from the left fist to the spear's butt ring; one face of each link's wire is self-lit (vertex alpha 0.5, `LINK_GLINT` (0.75, 0.55, 0.25): a bright bronze glint) so the chain reads in shadow and against dark rock; links are drawn 1.4-3.0 x thicker with the distance from the view (0.16 x distance) so the chain stays a line at range; while taut a thin warm line (1.6 px on screen, (1.0, 0.82, 0.48)) runs along it; slack: sags (0.06 x length + 0.1 m, never below the ground under its middle) and whips after the throw; taut (`ChainSpear.taut`, set by the hero): straight with a tension tremble. Never through the world: when the straight line from the fist to the butt meets the world (a pillar between the hero and a slammed beast, the lip of a ledge he climbed), the chain is drawn as two lengths meeting at a bend point just clear of it (the first spot clear of both, stepping out from the contact along the surface's normal, then up, then to either side; kept while it stays clear), and the spear flies home by that point |

What the bite does, by `chain_kind()`:

| Kind | Hero | Target | Numbers |
|---|---|---|---|
| `&"ring"` | 0.05 s of tension, then zips along a gentle arc to hang 0.5 m out and 2.3 m under the ring (left arm up on the chain, `RigHeracles.HANG_GRIP` = `Hero.HANG_HAND`, the shield upright beside the head) (`set_motion_state(&"zip")`, `chain_taut`, `chain_zip`, FOV +9, the camera arm 18 % shorter); over the last 1.6 m the body comes upright (`RigHeracles.zip_upright`). A walkable, roomy top 0.9 m under to 1.9 m over the ring just behind it (a ledge): the zip comes in low (no higher than hanging from the ring) and swoops up the wall over its last ~2 m, to end with his feet 1.15 m under the lip and his body 0.45 m out from the wall; as his hand comes level with the ring (feet 1.5 m under it) he lets go of the chain (the spear jerks out and flies home, round the lip when the chain is bent over it; it is driven into the ring up to its butt first, so the shaft never stands out of the wall into his legs) and is flung up the last ~0.25 s in the reach pose, then climbs (chain_mode `climb`, rig `climb`, 0.5 s: both hands on the lip at 0.12 s and held there (`RigHeracles.climb_lip`) while the body rises, the press with the chest over the edge at 0.3 s, a knee up, standing on the top at 0.5 s; the body follows `Hero.MANTLE_RISE` up the wall and goes over the edge from 0.36 s). None, but walkable ground at most 1.9 m under where he would hang (`Hero.ZIP_LAND_DROP`: a ring on a standing stone, like the three of Nemea's passage): the zip sets him down on that ground at the foot of the stone (a short landing, dust). Neither: HANG (the next ring can be thrown at from there; the hero keeps his grip until the new throw bites; jump or roll drops him; 6 s max) | `on_chain_attach` (the ring glints) | zip: accelerates at 70 m/s^2 to 20 m/s, eases out in the last ~3 m (to a hang: down to 2.5 m/s on arrival, no dead stop and no swing; to a ledge or a heavy anchor never under 6 m/s); blocked for 4 ticks: lets go |
| `&"heavy"` | pulled to it the same way, landing 1.05 m from its surface facing it; a blow buffered on the way becomes attack3 on arrival | stays put | arc 0.5 m higher |
| `&"light"` | rig `pull` (x1.15); at its `pull` event (0.21 s): `target.on_chain_pull(hero, dir)` (dir: target -> hero); released when it lands within 2.6 m or after 0.9 s; once the foe is in the air (or 0.12 s after the pull) a blow or a roll ends the pull pose at once: meet it with the sword | Enemy base: hops to land 1.2 m + its radius + 0.36 m in front of the hero (0.25-0.65 s, an arc 0.45 m + 5 % of the distance), staggered `yank_stagger` (1.1 s) after landing: a set-up for the combo | |
| `&"beast"` | braces, rig `pull` (x0.9), at the `pull` event (0.27 s): `on_chain_pull(hero, dir)`, shake 0.35, hit-stop 0.05, jerked 2.5 m/s towards it; lets go 0.5 s later | Enemy base: slides `chain_slide` m (3.5) along dir, bent up to 25 degrees towards a pillar, rock or the boulder in reach (slam magnetism); slamming into the world or a movable on the way stuns it (section 6.5) | slide speed sqrt(2 x 16 x chain_slide) (10.6 m/s for 3.5 m), 16 m/s^2 |
| `&"boulder"` | haul while the button is held (if it was let go before the bite: 1 s to press it again): faces the boulder, back-pedals at 2 m/s; the chain is as long as the distance at the bite and reels in at 0.9 m/s while held (down to 2.8 m); taut: `on_chain_pull(hero, dir)` every tick, and the hero is held back | Boulder: dragged at 2.4 m/s (accel 7, friction 11), rolls and scrapes (`boulder_drag` loop, dust), jams in a narrower doorway (`boulder_thud`) | let go: release the button, or beyond 26 m |

Press the chain button again while the spear is out to call it back; pressed while it flies home, it snaps back
and the new throw goes at once. A light target's or a beast's death releases it.

---

## 5. Lock-on and the camera (`CameraRig`)

| | Value |
|---|---|
| Lock-on | press: the `lockable` nearest the screen centre (score: normalised screen distance + 0.35 x distance / 25 m) within 25 m of the hero, on screen, in sight (world layer); `Game.lock_changed(target)` (null on release) |
| Switch | a flick of the right stick past 75 % (after resting under 30 %), or of the mouse: each frame's sideways motion counts only when faster than 500 px/s, the sum leaks 6/s, past 80 px it switches (90 px over 3 frames switches; a drift of 2 or 6 px a frame never does): the nearest lockable on that side of the current one |
| Release | press again; the target dies or leaves the groups; beyond 30 m; out of sight for 2 s |
| Framing | yaw turns to look past the hero at the target (6/s, at most 220 degrees/s) from 18 degrees round to his right (`LOCK_YAW_OFFSET`: the target shows past his left shoulder, never behind him), pitch -15 - 2.5 x (height difference - 1) - 0.15 x separation (between -34 and -4), arm 5.2-8.5 m with the separation, focus 15-35 % towards the midpoint, shoulder offset 0.8 m |
| Wrestle | a centred two-shot of the struggle (no shoulder offset, focus on the middle of the two heads, 4.8 m, pitch -14): every 0.4 s the angle round them (+-16 / 32 / 48 / 66 / 85 / 110 degrees) with the clearest arm, room round the lens (no world within 1.1 m), both heads in sight and the hold itself (the head in his arms) not hidden behind his back, preferring 48 degrees and the current one. No side scores 1.5 (pillars all round a beast stunned against one): a crane shot from over them (pitch -40, 5.5 m, 35-120 degrees round) when it scores better. Props in group `camera_cut` between the lens and the struggle are cut away (below) |
| Interest | not locked on, `Hero.camera_interest()` (the foe being wrestled, the boulder on the chain, a foe or beast being yanked, the foe the sword is busy with, a foe winding up a blow in view) is framed the same way while the player leaves the camera alone (0.4 s; for 0.6 s after a blow is aimed at a foe or lands, `HeroMelee.engaged_until`, at once: the first blows of a fight are framed too): 32 degrees round (14 while guarding, so the shield side shows; the wrestle: see Wrestle), turning at 6/s but never faster than 120 degrees/s (a foe behind him is brought round in a smooth pan, never a whip-pan), 4/s wrestling, pitch -22, arm at least 6.2 m, focus 10-30 % towards it, shoulder offset 0.8 m; it does not turn the view while the hero rolls nor for 0.4 s after (a roll away from a foe must not swing the camera round) |
| Locked movement | the hero faces the target and strafes / circles it (the rig steps sideways and back-pedals); sprinting runs free |
| Arm | 5.5 m from a pivot 1.55 m over the hero; a sphere of 0.3 m cast on the world layer every frame from the hero's head (inside his capsule, so the cast never starts inside a wall or a pillar) out to the wanted camera point (Jolt: a cast that starts inside one shape of a body skips that whole body - the island's terrain, all the arena's props - so the start is checked once a frame with a sphere query, and when the head itself is pressed into the world by a move without collision the arm is a ray to the first surface, less 0.3 m): comes in at once, eases back out (2.6/s, up to 11.6/s while shorter than 1.7 m); walls close on both sides (rays of 2.4 m from the head) shorten it to 68 % |
| Obstacles | the arm cut under `need` = max(2.6 m, 60 % of the arm) with the look input idle 0.3 s (or for 0.6 s whatever the input, or squeezed under 1 m): swings round by the nearest clear angle of +-20 / 40 / 65 / 95 degrees (180 degrees/s, 360 under 1.7 m); squeezed under 1 m all at once (the hero brushing past a pillar at speed): jumps by the nearest clear angle up to 65 degrees that very frame rather than show the inside of his helmet; nowhere clear: pitches down towards -48 degrees (over the obstacle); looking round by hand cancels the swing. Cut under 1.7 m beside the hero, a thin sphere (0.13 m, still covering the near plane) may find the line clear, grazing the obstacle. Whiskers: arms 16 degrees either side; while the look input is idle the view drifts (up to 70 degrees/s) away from a side cut under `need`, so a pillar coming past is avoided before the arm is cut. The bot's camera watch: never inside the world, never within 1.2 m of the hero's head for 0.35 s (at 60 fps the arena run keeps it over 4 m) |
| Follow | XZ 14/s, Y 7/s (never more than 3 m behind), lead 7 % of the hero's velocity |
| Recentring | after 1.4 s without look input, behind a hero moving faster than 2.5 m/s (rate 0.7 x clamp(speed / 6, 0.4, 1.4) per s, x0.25 at full combat weight); never while dodging (`Hero.is_dodging()`: a roll sideways does not swing the view) |
| Chain | not locked on and nothing else framed, while the spear is thrown, flying, zipping, climbing or hanging (`Hero.chain_focus()`): the view turns 25 degrees round to the chain arm's side (the left) and 1.2 m over that shoulder (eased 6/s, at most 120 degrees/s; the right side when the left is blocked), so the chain crosses the screen on a diagonal instead of running away down the view axis behind his back. Measured (`probe=chainscreen`): at least 4 links of chain on screen (not behind his body or the world) in 93 % of the frames from the release to the arrival of a ledge zip thrown at what the camera looks at, 96 % for the ring on the sea stack (about 0 % before this view) |
| Guarding | not locked on: no shoulder offset to the right (the shield on his left arm shows past his body) |
| Foes in the way | foes are not on the camera's layer (the view never swings round a wolf), so one that comes within 0.4 m of the line from the lens to the hero's head, or within 1.5 m of the lens, fades to a 55 % screen door (`Rig.set_fade`, lowpoly `fade`, eased 8/s) and back; never the beast being wrestled |
| Cut-out | world props in group `camera_cut` (GeometryInstance3Ds with the lowpoly material: the arena's pillars and sea stack; WORLD should add the lion cave's pillars) are cut by a screen door (lowpoly `cut_*`, 80 %) where they stand between the lens and the subject (within 0.8 m of the line from the lens to the hero's chest, 1.2 m to the middle of a wrestle, and at least 0.7 m nearer the lens than it) or within 2.6 m of the lens; never in shadow maps |
| Framing side | the shoulder side flips only while framing a target hidden from the current side and visible from the other (the camera's own sphere cast for the arm: under 60 % clear) |
| Combat | foes within 11 m (counted every 0.3 s): combat weight rises 1.6/s, falls 0.6/s; arm +0.9 m, shoulder offset 0.7 m (eased 3/s), pitch eases to -24 degrees after 1 s without look input |
| Feel | FOV 60, +5 sprinting, +9 zipping (and the arm 18 % shorter, so the hero does not shrink to a dot); shake: trauma squared, offsets up to 0.35 m and 0.05 rad of roll, a ~15 Hz jolt kept at 60-100 % of the swing, decays 1.7/s (Settings `shake` off disables shake and nudges); nudge: a spring (k 160, damping 18) pushed 9 x amount along the blow (section 3.5) |
| Look | mouse 0.14 degrees/px x `mouse_sens`; pad 185 degrees/s x `pad_sens` with a squared response, vertical x0.75; `invert_x` / `invert_y` |

---

## 6. Contracts for ENCOUNTERS

### 6.1 The hit dictionary

`Combat.make_hit(amount, kind, dir, knockback, stagger, source, extra)` builds it. Keys
(ARCHITECTURE 5.1 plus additions, all optional):

| Key | Who sets it | Meaning |
|---|---|---|
| `point: Vector3` | attacker | where the blow touched (sparks, deflect sparks) |
| `attack: StringName` | attacker | `&"attack1"` `&"attack2"` `&"attack3"` `&"heavy"` or the enemy's own name (`&"bite"`, `&"gore"`...) |
| `guard_break: bool` | the hero's heavy blow | breaks shields and guards |
| `unblockable: bool` | enemy blows | the hero's shield neither blocks nor parries it (the lion's roar wave) |
| `parryable: bool` | enemy blows, default true | false: can be blocked but not parried |
| `deflected: bool` | **the target** inside take_hit | immune to this blow (the lion vs blades); return false |
| `blocked: bool` | the target | stopped on a shield or guard |
| `parried: bool` | the hero | a perfect parry; the hero calls `attacker.on_parried(hero)` |
| `dodged: bool` | the hero | it met a roll's i-frames |
| `sound_done: bool` | the target | it already played the contact sound (`blade_bounce`, `shield_block`): the attacker does not |
| `shoved: bool` | the hero | a push-only hit (`amount` 0, `knockback` > 0: the roar wave) moved him without damage (`take_hit` returns false). With `unblockable` the raised shield does not brace it (full push); without, a frontal guard takes 40 % of it |

The attacker reads the verdict keys after `take_hit` returns (`Enemy.attack_check` copies them back for you).

### 6.2 Blade-immune targets (the Nemean Lion)

Set `deflected` and return no damage; the hero recoils (rig `recoil`, 0.39 s for light blows, 0.6 s for the
finisher and the heavy), sparks and an impact burst fly at `hit.point`, `blade_bounce` plays (unless
`sound_done`), hit-stop 0.07, shake 0.22. With `Enemy` that is just:

```gdscript
func _modify_damage(hit: Dictionary, amount: float) -> float:
	if hit.get("kind", &"") == &"blade":
		hit["deflected"] = true
		# optional: play the lion's own spark animation / blade_bounce here and set hit["sound_done"] = true
		return 0.0          # Enemy.take_hit then calls _on_blocked(hit) and returns false
	return amount           # grapple, chain, blunt... hurt
```
(`tools/arena_beast.gd` does exactly this.)

### 6.3 The Enemy base (scripts/enemies/enemy.gd)

Everything of ARCHITECTURE 5.10 is unchanged; added:

| Member | Use |
|---|---|
| `telegraph(seconds, cue_point := INF, sound := "", strength := 1.0)` | starts a readable wind-up: a gold glint at `cue_point` (default over the lock point), a flash on the rig, `sound`. `telegraph_t` / `telegraph_left()` count down; `_on_telegraph_done()` fires at the end (strike there). A blow whose `stagger` reaches the foe's `poise`, a chain bite, a parry or a stun cancel it |
| `poise` | a blow staggers the foe (and breaks its wind-up) only when its `stagger` reaches this: wolf 0.3 (the default: every blow), boar 0.8 (only the finisher, the heavy blow or a parry), lion 99 (never: the chain and the pillars do it). Below it the body only flashes and is pushed (`knockback_resist` still applies), so mashing does not interrupt every attack |
| `_flinch(hit)` | called by `take_hit` for a blow that beats `poise` (and does not kill): plays the rig's `stagger` (stagger >= 0.6) or `hit` action when the rig defines it (`actions` / `ACTIONS` table or `action_length()`), after `set_hit_dir(dir)` when the rig has it; never while stunned, yanked or sliding. Override for your own reaction (call `super` or not). The hit flash is `Rig.FLASH_LIGHT` 0.4 / `FLASH_HEAVY` 0.6 (stagger >= 0.5) |
| `slam_normal` | the face it last slammed into on the chain (horizontal, from the pillar towards the beast; `Vector3.ZERO` before any slam): put a wrestle anchor on this side of its head (6.6) |
| `attack_check(reach, half_angle, hit, origin := INF, fwd := ZERO) -> int` | strikes every damageable of another team inside the cone (reach measured to their surface, +-2 m in height); fills `dir` (towards the target) and `source`; returns how many it hurt and copies `parried` / `blocked` / `dodged` / `deflected` back into `hit` |
| `on_parried(hero)` | called by the hero on a parry: cancels the telegraph, stagger `parry_stagger` (1.2 s), a 3 m/s shove away, rig `stagger` (or `hit`); hook `_on_parried(hero)` |
| `stun_for(seconds)`, `is_stunned()`, `stun` | dazed: no `_think`, no attacks, stars over the head (`Fx.daze`), rig `stunned` when it has one; hook `_on_stunned(seconds)` |
| `steer_to(goal, speed, arrive := 1.0) -> Vector3` | seek (easing in within `arrive` m) + separation from other enemies + two feelers round obstacles; returns the velocity for `_think` |
| `separation(r)`, `face_towards(p, delta, rate)`, `forward()` | helpers |
| `hurt_volumes() -> Array` | capsules `[a, b, r]` (world) the hero's blade tests; default one vertical capsule from `radius` / `height`. The lion should return two or three along its body |
| `chain_weight` | `&"light"` (yank), `&"heavy"` (the hero comes), `&"beast"` (slide + slam) |
| `parry_stagger`, `yank_stagger`, `chain_slide`, `stun_on_slam` | tuning (1.2 s, 1.1 s, 3.5 m, 3 s) |
| `is_yanked()`, `is_sliding()` | while the chain moves it (no `_think`) |
| death | `die()` as before; the rig dissolves over the last 0.8 s of `corpse_time` |
| rest | 8 ticks at rest on the floor (no wanted velocity, knockback, yank or slide), the body stops calling `move_and_slide` until it moves again (waiting pack members cost nothing). Move enemies with `teleport(p, yaw)`, never by setting `global_position`: it also wakes the body |

`_think` is not called while staggered, stunned, yanked or sliding.

### 6.4 How to telegraph (the readability rules)

- Every attack the hero must answer gets a wind-up of **at least 0.45 s** (wolves' bites 0.45-0.6, the boar's
  charge 0.8-1.2 with `boar_charge`, the lion's swipe 0.6, its pounce 0.8). Start it with `telegraph()`; strike in
  `_on_telegraph_done()` and resolve hits with `attack_check()` **at the moment the attack visibly connects** (the
  sparring post waits 0.09 s after the wind-up for its club to reach the front).
- The rig must hold a clear anticipation pose for most of the wind-up (pulled back, crouched) and move fast at the
  end; the glint goes where the danger is (the jaws, the tusks, the paw).
- Parry window: the hero's 0.18 s before the hit lands. Make the strike frame land at the end of the telegraph so a
  player who reacts to the glint can parry.
- Big unblockable moves (`unblockable: true`) need a different cue: a bigger glint (`strength` 1.5) and a sound.
- Pack rule (GDD): one wolf attacks while the others circle; give each attack its own telegraph.

### 6.5 Beasts and the pillar stun (the lion's chain rule)

`chain_weight = &"beast"`. The hero's yank calls `on_chain_pull(hero, dir)` once (dir: horizontal, from the beast
to the hero). The base slides the beast `chain_slide` m along `dir` (initial speed sqrt(2 x 16 x chain_slide),
decelerating at 16 m/s^2) with `move_and_slide`; a collision with the world (layer 1) or a movable (layer 4, the
boulder) whose normal faces back against the slide (dot > 0.45) while still faster than 2.5 m/s is a **slam**:
`_on_slam(collider, speed)`, which by default stuns for `stun_on_slam` s (stars, dust, an impact burst, shake,
`boulder_thud`). The lion overrides `_on_slam` to play `lion_thud` and its `stunned` action, and keeps
`super._on_slam()` (or calls `stun_for` itself).

Slam magnetism: at the pull the base bends the slide up to 25 degrees (5-degree steps, the nearest first) towards a
face of the world (layer 1: a pillar, a rock, a wall) or a movable (the boulder) that a ray along that direction
from the beast's middle meets within `chain_slide` + radius + 0.2 m and that takes the beast square on (not the
ground; its normal back against the ray by more than 0.6). So the pull need not graze the pillar exactly.

Level recipe: the throw needs a clear line, the beast's body does not. Put pillars so that, seen from the beast, a
pillar's face is within about 25 degrees of the line to the hero and within `chain_slide` (3.5 m) + its radius: the
spear flies by it, the beast is drawn into it. (Arena: beast at (-12, 19), pillar at (-12, 15), hero at (-9.8, 9.5).)
The chain is drawn bent round the pillar while the beast lies behind it (section 4).

### 6.6 The grapple protocol (the wrestle)

The target drives the rhythm; the hero answers. Group `"grapplable"` plus these methods (duck-typed):

| Direction | Call | When |
|---|---|---|
| hero -> target | `can_grapple(hero) -> bool` | every tick while the hero looks for something to use (true: interact starts the wrestle, the UI shows `interact_info()` if the target has it) |
| hero -> target | `grapple_anchor(hero) -> Transform3D` | at the start and every tick of the wrestle: where the hero's origin goes, its basis -Z the way he faces. `RigHeracles.GRAPPLE_HOLD` (0, 1.17, -0.43) is where his arms lock: put the beast's neck / head there. The hero eases onto it sliding round the world (`move_and_collide`, the beast itself off his mask), so he never enters a pillar, but a spot that is not free leaves him short of it with his arms off the head: pick a free spot (a beast stunned against a pillar: not between its head and the pillar, and preferably on the side away from it, `slam_normal`, so the hero and the camera have room; the straw bull tries its front and 22.5-90 degrees round either side of its head with a capsule query, once per wrestle, scoring the free ones by closeness to the front and to `slam_normal`, else the side with the most room) |
| hero -> target | `grapple_begin(hero)` | once, when it starts (the hero eases onto the anchor, stops colliding with enemies, plays `grapple_start` then `grapple_loop`) |
| target -> hero | `hero.grapple_cue(window)` | a squeeze beat: a window of `window` s (the hero shows a glint on the hold) |
| hero -> target | `grapple_input(hero, timing_ok)` | every press of attack or interact; `timing_ok` = inside an open window (a press consumes it) |
| target -> hero | `hero.grapple_thrash(cost)` | the beast throws its weight about: `cost` stamina, a fifth of it if the hero holds guard; out of stamina the hero is thrown off (knockback 6 m/s, `hit_heavy`) |
| target -> hero | `hero.grapple_release(won)` | the target ends it: `won` = the beast is beaten |
| hero -> target | `grapple_end(hero, won)` | **always**, once, whatever ended it (released, thrown off, the hero hurt by someone else, dead); must be idempotent |

The hero lays his sword and shield on the ground beside him when the wrestle starts (bare hands, as Heracles with
the lion; the shield would cut into the beast's head: `RigHeracles.set_weapons_aside(true)` + two props at his
right side) and takes them back when it ends. So the beast's head and neck may fill the space in front of his chest
freely. The target does the damage itself (`kind: &"grapple"` on a good squeeze) and the sounds (`wrestle_strain` every
beat, `wrestle_squeeze` on a good press, `lion_thrash`, `lion_pain`). The hero regenerates no stamina while
wrestling. Warn before a thrash (`telegraph`, 0.45 s) so the player can raise the guard.

Reference implementation: `tools/arena_beast.gd` (the straw bull): stunned by a pillar it is grapplable; as the
wrestle starts it is hauled 1.3 m off the pillar along `slam_normal` (a knockback of sqrt(2 x 18 x 1.3) m/s, the
hero's layer off its mask meanwhile), so the struggle has room and the camera a view of the hold - the lion should
do the same; beats every 1.25 s with a 0.5 s window, a thrash every 2.4 s (24 stamina, warned 0.45 s before); 3
good squeezes win, 3 bad presses or 14 s lose; beaten, it topples for 3 s.

### 6.7 The parry, from the attacker's side

Do nothing special: strike with `attack_check` (or `hero.take_hit`). If the hero parries, `take_hit` returns false
with `hit["parried"]`, and the hero has already called your `on_parried(hero)`. Override `_on_parried` for the
reaction (the wolf yelps and stumbles back, the boar's charge breaks).

---

## 7. RigHeracles additions (CORE)

`play_at(action, speed, upper)` (upper: the legs and hips keep the locomotion - throwing on the run, the charge
walk), `action_hold` (hold the current action at a key), `stop_action(blend)`, `charge` (0..1 tremble), `tired`
(0..1 winded idle), `guard_impact(k)` (shield jolt), `blade_segment()` (the sword's root and tip in world space),
motion state `&"hang"`, a strafing / back-pedalling gait (the stride follows the direction of travel in rig space),
actions `recoil` (0.52 s), `backstep` (0.5 s), `climb` (0.58 s: up and over a ledge from 1.15 m under its lip, the
hands given in rig space so they stay on the lip while the hero moves the body) and `catch` (0.46 s, upper body: the
returning spear caught in the left fist and strapped on the back at `CATCH_STOW` 0.24 s), `zip_upright` (0..1, set by
the hero near the end of a zip: the body comes upright), the shield kept forward-left in the light blows and in the
guard (its rim shows past his left side from behind), the sword arm a little further out in attack1 / attack2 (the
fist no longer sinks into the cuirass), the spear's chain coil in bronze, `spear_meshes(false)` (the bare spear in
flight), `HANG_GRIP` (the left fist on the chain when hanging; the body swings about it), `reset_cloth()` (the cape and the crest restart at rest; called by
`Hero.teleport` and by the rig itself when it jumps more than 3 m in a frame), foot IK: `set_ground(dy_r, dy_l,
normal, on)` with the ground under each foot (the hero casts two rays a tick, `Hero._probe_feet`): the pelvis drops to
the lower foot, each foot is raised to its ground and its sole tilted to the slope (up to 35 degrees, smoothed 14/s),
weighted by `_gnd_k` (only on the ground, eased out while airborne, swimming, hanging or rolling). Clip check:
`tools/clip_check_heracles.tscn` (adds strafe, back-pedal, guard-strafe and hang states; hidden weapons are skipped):
2602 samples (`catch` and `climb` included), 847-900 contacts deeper than 8 mm (the count varies from run to run
with the cape cloth; it was 1059-1124 before step 3): the sword arm against the cuirass in attack1 / attack2 is down
to 3.4 cm (was 5.8 cm); the deepest left are all the cape: against the left arm and the shield in the heavy's spin
and in the strafe (4.5-5.7 cm for a frame or two, the cloth between two particles straddling a thin part; 31 log
lines of 4 cm or more). The catch: 2.8 cm (the shaft against the shield on its first frame).
The base `Rig` (CORE) adds `set_fade(v)` / `get_fade()` (lowpoly `fade`: an ordered-dither screen door, the camera's
fade of foes in the way) and the flash constants `FLASH_LIGHT` 0.4, `FLASH_HEAVY` 0.6, `FLASH_DECAY` 13 (per second of
real time; a fresh flash shows at full strength for one frame).
`set_weapons_aside(on)` hides the sword and the shield (the wrestle; `Hero._lay_weapons` lays two props on the
ground); `don_skin` hides them by itself while the hands are busy with the pelt (`Hero.don_lion_skin` lays them
down too). Cost: `RigHeracles.advance()` 0.9-1.3 ms a frame on desktop (`tools/perf_probe.gd`; the cape is ~80 % of
it: 72 particles, 398 constraints x 5 passes, collisions after passes 3 and 5 against packed capsules with a
bounding-sphere early-out; it was 3.3-4.0 ms before). The cape also stays in front of a wall or rock behind him
(two rays back from his chest and hips, one down behind his heels: a plane it is pushed out of, and the rising
ground the hem rests on; `cape_world = false` for tools without a world). Preview:
`tools/preview.tscn -- script=res://tools/preview_heracles.gd fns=sheet rows=views:hang` (rows also take `hang`).

---

## 8. The arena and its bot

`tools/arena.tscn` (or `scene=arena`): a stone platform by the sea with three straw posts (heavy), a sparring post
(swings a club after a telegraph: block / parry / roll practice), two straw sacks on sleds (light chain targets),
the straw bull (beast), a ring under a cliff lip (zip and climb), a sea gap with a ring on a sea stack and one under
the far cliff (ring to ring), a wall with a doorway narrower than the boulder (haul it in to seal it), a row of
pillars, ramps of 15 / 30 / 45 / 58 degrees.

```sh
# every test, faster than real time (prints one line per test and a summary)
timeout 900 godot --headless --path doce/game res://tools/arena.tscn --fixed-fps 60 --quit-after 8000 -- autotest=1 quit=1 | grep ARENA
# some tests
... -- bot=combo,heavy,parry quit=1
# a movie of a test from the gameplay camera, then strips (one row per move)
xvfb-run -a -s "-screen 0 1600x900x24" godot --path doce/game --rendering-driver opengl3 --resolution 1280x720 \
  --write-movie /abs/frames/combo/f.png --fixed-fps 30 --quit-after 100 res://tools/arena.tscn -- bot=combo noui=1
python3 doce/game/tools/arena_strips.py strips.png --row "combo:/abs/frames/combo:16:8:3"   # frame from "ARENA mark"
```

Tests (`tools/arena_bot.gd`): lockon (acquire, stick flick to the next, strafe facing, release), combo (attack1,
attack2, attack3 in order), heavy (charge, charged, 30 damage with guard_break), kill (a locked straw soldier cut down
by the combo: slow motion on the killing blow, the lock lets go, he topples, dissolves and is freed, a new one stands
up), guard (a block costs stamina, no damage), parry (guard 0.09 s before the club lands: parried, the post reels), dodge (roll through the club), hurt
(no guard: health lost, the hit reaction, knocked back),
light (a sack 12 m away lands in front of the hero), ledge (zip to the ring under the west cliff and climb on),
rings (ring A on the sea stack, hang, ring B, climb onto the far cliff), beast (yank the bull into a pillar, stunned,
walk up, wrestle: squeeze in the windows, brace on the thrashes, win), boulder (haul it into the east doorway),
ramps (foot IK: standing across and then up the 30-degree ramp, each ankle within 7 cm of its sole height over the
slope; a walk up the 15-degree ramp onto the terrace), death (health to nothing: `Game.hero_died`, the DEAD phase,
the death action, back at the start with full health after main.gd's 3 s), and throughout, camera (the view never
inside the world and never within 1.2 m of the hero's head for 0.35 s). 16/16 pass at `--fixed-fps 60` and at `--fixed-fps 24` (step-3
code; also inside the live project with CORE's files overlaid).
Debug args: `meleedebug=1` (blade sweep distances, "MELEE HIT <blow> blow_t= rig_t= dist="), `camdebug=1` (camera per
frame), `feeldebug=1` (hit-stops).

### 8.1 Measured feel (probe runs)

The numbers quoted in sections 1-5 come from a probe scene that drives the same bot buttons in the arena and prints
per-frame traces (`tools/critic_probe.gd` + `critic_arena.gd` + `critic.tscn`, kept in CORE's work copy: test-only,
not part of the project; `-- probe=long,recovery,inputs,parrycancel,hitstop,shakepx,melee,moveout,flashtrace,mash,
knock,dodge,hurt,zip,chainbody,chainvis,chainscreen,spear,occl,dodgelat,lockon,flick,camera,parrywin quit=1`).

| Measure (60 fps unless noted) | Result |
|---|---|
| Press to contact, button held 0.06-0.35 s | 0.167 s every time (a 0.30 s hold then coils the heavy out of the follow-through; no wind-up twice) |
| Fast combo contacts / back to MOVE | 0.167 / 0.418 / 0.869 s / 1.37 s |
| Presses kept | 0.10-0.40 s after the finisher's or the heavy's contact; 0.12-0.62 s into a yank; chain pressed while the spear flies home (3/3) |
| Parry | from MOVE with the press 0.03-0.19 s before the hit; out of attack1's recovery 0.10 s before |
| Hit-stop frames | 4 / 4 / 7 / 10 (2 / 2 / 3 / 5 at 30 fps) |
| Shake + nudge peak (1280x720, 6 m) | 3 / 9-10 / 12 px (3 / 7 / 9 px at 30 fps) |
| Hit flash of the target | light 0.40, 0.18, 0 (frames); heavy 0.60, 0.38, 0.17, 0 (at 30 fps: 0.40, 0 and 0.60, 0.17, 0) |
| Back in the run after contact (stick) | 0.20 / 0.29 / 0.47 s (attack1 / finisher / heavy) |
| Knockback (straw soldier / sack) | attack1 0.08 / 0.19 m, combo 0.50 / 1.27 m, heavy 0.66 / 1.88 m |
| Roll | 4.0 m, facing the travel from its first frame, 22 % covered when the tumble passes 90 degrees, peak 10 m/s; 0 s from the press in a fight |
| Hurt | light: 0.27 s without control, pushed 0.37 m; heavy: 0.54 s, 1.42 m; a blocked heavy slides 0.52 m |
| Chain | a ring 12 m away bites 0.45 s after the press; on screen 93 % / 96 % of a zip; the ring zip ends at 2.6 m/s; links inside the world: none, but for 1-2 links where his fist meets the stone at the end of a zip to a ring on a rock face |
| Lock-on | yaw jerk at most 0.14 degrees a frame, no reversals; mouse drifts of 2 and 6 px a frame never switch, a 90 px flick over 3 frames does |
| Camera walks (pillar gap, brushing pillars, doorway, cliff, circling locked between pillars) | never inside the world, the hero never hidden; closest to his head 1.23 m (the doorway) |
| The backhand from behind | its contact point is behind his body from every camera behind him (ray to his axis 0.04-0.21 m): the trail drawn over the body and the foe's flash, flinch and knockback carry it |

### 8.2 On the island: `corebot` (tools/nemea_bot.gd)

The same hero on the real Nemea World (`main.gd` loads the bot with the arg):

```sh
timeout 900 godot --headless --path doce/game --fixed-fps 60 --quit-after 12000 -- play=1 corebot=1 quit=1 | grep NEMEA
# some tests: corebot=passage,cave   (botdebug=1: the boulder haul traced every 0.5 s)
```

Tests: start (on the pier, on the floor, the view behind him), passage (south rim -> the ring on the sea stack: the
zip lands him at the foot of its stone -> round the stone until the north ring is in sight -> the north rim), boulder
(mouth B, see below), cave (in through mouth A, to the arena centre, round two pillars), swim (off the end of the
pier), and the camera watch (the hero's head always in sight from the camera - a ray on the world layer: a point
query cannot tell "inside" on the island's trimesh terrain and cave -, never within 1.2 m of his head for 0.35 s,
never under the sea). `corebot=boulder_search` tries 20 pull spots round mouth B and prints where the boulder ends.

Status (2026-10-10, live world of that day, again with the world of commit 330989b and with the step-3 code on the
live project of commit cb141ba): start, passage, cave, swim and the camera watch PASS. **boulder FAILS
because of the layout**: from its spot beside mouth B the boulder is wedged between the cliff foot (the cave mesh,
normal (0.12, 0.42, 0.90)) and a 28-degree rise of the terrain 4.5 m from the mouth point whatever the hero does
(20 pull spots, best 4.47 m), and the hero cannot walk past ~0.6 m on the far side of the opening. The World's
"clear run" checks the ground under the path, not the boulder's 1.3 m sphere against the cave mesh. For WORLD: put
the boulder on the mouth's axis (e.g. `entrance_b + dir_b * 5`, flat ground, nothing of the cave mesh within 1.4 m
of the line to the arch), or check the run with a sphere cast of radius 1.3 on layer 1; the haul itself works (arena
test `boulder`).
