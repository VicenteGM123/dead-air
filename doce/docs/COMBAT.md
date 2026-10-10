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
| Light blow (combo of 3) | left click (tap) | X | starts at once on the press |
| Heavy blow | hold left click | hold X | held 0.16 s: the wind-up starts (CHARGE); held 0.40 s: charged (glint + ring + sound); release charged: the spin slash. Released earlier: the light blow after all |
| Guard / parry | right click hold | LT | a fresh press opens a 0.18 s parry window |
| Roll / backstep | Shift tap (< 0.2 s) | B tap | with a direction: roll; without: backstep |
| Sprint | Shift hold (>= 0.2 s) | B hold, L3 click | |
| Chain spear | Q | RT | press: throw (or call the spear back when it is out); hold: keep hauling a boulder |
| Lock on | Tab / middle click | R3 | flick the right stick or the mouse sideways to switch target |
| Interact / grapple | E | Y | a stunned beast within 3 m is wrestled before any other interactable |

`HeroInput` samples every button once per physics tick (held, pressed / released this tick, hold time, time since
the last press). A press and its release inside one tick still count. The click that captured the mouse never
attacks. Tests drive the same path through `hero.inp.bot[&"attack"] = true` and `hero.debug_move`.

Buffers: attack 0.30 s (only consumed when a combo window opens or a state ends), roll 0.25 s, chain 0.25 s,
jump 0.14 s.

---

## 2. The hero's state machine (`Hero.state`, `Hero.state_name()`, signal `state_changed`)

| State | Entered by | Leaves to | Notes |
|---|---|---|---|
| MOVE | default | everything | ground / air / swim locomotion; guard while held on the ground; sprint; jump; interact |
| ATTACK | attack (MOVE, combo window, end of a roll, arrival of a chain pull) | ATTACK (next blow), CHARGE, MOVE, DODGE / THROW / MOVE+guard (recovery only), STAGGER (deflect) | HeroMelee |
| CHARGE | attack held 0.16 s during a light blow's wind-up | HEAVY (released charged), ATTACK (released early), DODGE | slow walk 1.5 m/s, turns to the input / lock target |
| HEAVY | release when charged | MOVE, DODGE / THROW (recovery) | the spin slash, 22 stamina |
| DODGE | roll tap on the ground with >= 11 stamina | MOVE, ATTACK (last 28 %), DODGE (last 28 %) | i-frames |
| STAGGER | hits, guard break, deflected blade (recoil), end of a wrestle | MOVE | no control; knockback decays at 18 m/s^2 |
| THROW | chain press (ground, air, hanging) | MOVE (0.12 s after release), CHAIN (the spear bites) | the hero keeps hanging if thrown from a ring |
| CHAIN | the spear bit an anchor | MOVE, HANG, ATTACK (a buffered blow on arriving at a heavy target) | modes zip, to, hop, yank, beast, haul (`Hero.chain_mode`) |
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
| Turning | 13 rad/s (x1.6 standing, x0.6 sprinting, x0.5 in the air); locked on 16.9 rad/s towards the target; guarding 10 rad/s towards the camera's forward |
| Jump | 8 m/s (about 1.3 m), coyote 0.12 s, buffer 0.14 s, early release x0.45, fall x1.55, terminal 45 m/s |
| Slopes, steps | 46 degrees, step-ups 0.42 m, floor snap 0.45 m |
| Hard landing | above 13 m/s: 0.3 s at quarter speed and a shake |

### 3.2 The sword (HeroMelee.LIGHT / HEAVY)

Times are the rig's authored seconds (`RigHeracles` keys); `speed` scales them (real time = authored / speed).

| Blow | speed | hold key | active | combo opens | cancel from | length (real) | first contact* | damage | knockback | stagger | hit-stop | shake | nudge |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| attack1 forehand | 1.05 | 0.11 | 0.125-0.29 | 0.29 | 0.30 | 0.53 s | ~0.16 s | 10 | 2.6 | 0.35 | 0.05 | 0.14 | 0.05 |
| attack2 backhand | 1.05 | 0.10 | 0.115-0.28 | 0.28 | 0.29 | 0.53 s | ~0.15 s | 10 | 2.6 | 0.35 | 0.05 | 0.14 | 0.05 |
| attack3 overhead (finisher) | 1.00 | 0.22 | 0.262-0.42 | - | 0.50 | 0.80 s | ~0.30 s | 18 | 7.5 | 0.75 | 0.09 | 0.30 | 0.10 |
| heavy spin (charged) | 1.00 | 0.30 | 0.37-0.68 (360 degrees) | - | 0.80 | 0.70 s after release | ~0.12 s after release | 30, guard_break | 10 | 1.1 | 0.12 | 0.45 | 0.14 |

\* for a foe straight ahead at the lunge's stop distance. Knockback is the initial shove in m/s (decays at 18 m/s^2:
2.6 m/s moves a foe 0.19 m, 7.5 about 1.6 m, 10 about 2.8 m before `knockback_resist`).

- **Combo**: a press during a blow is buffered for 0.3 s and fires the next blow the moment the window opens
  (end of the follow-through). After a blow ends, a press within 0.25 s still continues the combo. attack3 ends it.
  Cadence with good timing: impacts at about 0.16, 0.43 and 0.83 s.
- **Tap or hold**: a blow started with the button still down waits on its anticipation key (`hold key`) until the
  button comes up (a quick tap never waits). Held 0.16 s it becomes the heavy blow's wind-up (needs 11 stamina and
  not exhausted). The charge tremble (`RigHeracles.charge`) grows; at 0.40 s held: charged (glint at the blade tip,
  a ring at the feet, `charge_ready` if that sound exists, else `parry` pitched up and quiet).
- **Cancels**: the recovery (from `cancel from`) can become a roll, a throw or the guard; never the wind-up or the
  active frames. The last 28 % of a roll can become a blow or another roll.
- **Magnetism**: at the start of a blow the hero turns to (26 rad/s through the wind-up) and lunges towards the
  best foe in a 35-degree half-angle cone round the input direction (or his facing) within 2.5 m of its surface;
  locked on: the lock target within 4.5 m, with 0.5 m more lunge. The lunge stops 0.55 m from the foe's surface
  (the xiphos reaches 0.85 m straight ahead, 1.2-1.4 m at the ends of its arcs), up to 1.1 m (attack1/2), 1.3 m
  (attack3), 0.6 m (heavy); it runs from 0.02 s to the first active frame. No foe: a 0.3 m step into the blow.
- **Hits**: between consecutive physics ticks of the active frames the blade (`RigHeracles.blade_segment()`: root
  0.1 m to tip 0.64 m from the grip, plus 0.22 m of gameplay reach past the tip) is swept at four points along its
  length and tested top-down against every foe's hurt volumes (`Combat.hurt_volumes`) with a radius of
  volume + 0.14 m, inside a vertical band from 0.9 m under the blade to 0.35 m over it (a chest-high cut still finds
  a wolf). Each foe is hit at most once per blow. The contact point is on the volume's surface at the blade's height.
- **When it lands** (`take_hit` returned true): `Fx.impact` (white star flash, radial streaks, sparks; power 0.7 /
  1.1 / 1.6), dust at the foe's feet for the finisher and the heavy, `hit_1/2/3` or `hit_heavy` at the contact
  (pitch 0.92-1.08), one hit-stop per blow, `Game.shake`, `CameraRig.nudge` along the blow, signal
  `Hero.blow_landed(target, hit)`. The knockback direction is away from the hero, bent 45 % along the blade's motion
  (radial for the spin). Swing sounds `swing_1/2/3` / `swing_heavy` play as the blade starts to move.
- **The trail**: `BladeTrail`, a white crescent over the last 0.16 s of the blade (bluish for the spin), drawn after
  the rig has posed (process priority 20).

### 3.3 Defence

| | Value |
|---|---|
| Guard | held in MOVE on the ground; covers +-70 degrees round the facing; blocks blows unless `unblockable` |
| Block cost | 6 + 0.9 x damage stamina (x1.4 for blows with stagger >= 0.5); 40 % of the knockback; shield jolt (`guard_impact`), sparks at the shield, `shield_block`, hit-stop 0.04, shake 0.12 |
| Guard break | stamina short of the cost, or `hit.guard_break`: stamina 0 (exhausted), half the damage, `hit_heavy` stagger, signal `guard_broken` |
| Parry | the hit lands within 0.18 s of a fresh guard press (a new window only 0.4 s after the last): no damage, +8 stamina, the shield punches (`parry`, upper body), `parry` sound, impact burst + ring at the shield, hit-stop 0.10, slow motion x0.25 for 0.22 s, shake 0.2, `attacker.on_parried(hero)`, signal `parried`; not for `parryable: false` or `unblockable` blows |
| Roll | 0.55 s, 4.0 m along the input (camera / lock relative), i-frames 0.05-0.35 s, 22 stamina, needs 11; displacement 1-(1-u)^2.2 over the first 86 % |
| Backstep (no input) | 0.42 s, 2.2 m back, i-frames 0.03-0.24 s, 22 stamina |
| Perfect dodge | the first blow that meets the i-frames: slow motion x0.3 for 0.28 s, a ring and a glint, `dodge` pitched up, signal `perfect_dodge` |

### 3.4 Stamina and health

| | Value |
|---|---|
| Max | 100 stamina, 100 hp |
| Costs | sprint 16/s, roll 22, heavy 22, block 6 + 0.9 x damage |
| Regeneration | 34/s after 0.7 s without spending; none while guarding, charging or wrestling |
| Exhausted | at 0: until back to 35 % (field `exhausted`, read by the UI's stamina ring): no sprint, roll or heavy blow, run at 80 %, `RigHeracles.tired` (heavier breathing, the head drops) |
| Taking a hit | 0.35 s of invulnerability; light (`stagger` < 0.5 and damage < 25): `hit`, 0.27 s without control, shake 0.25, hit-stop 0.05; heavy: `hit_heavy`, 0.53 s, shake 0.45, hit-stop 0.08; knockback from `hit.dir` x `hit.knockback`; red screen flash (`Fx.flash_screen` -> the UI's `screen_flash`); `hero_hurt` |
| Lion's pelt | `Hero.don_lion_skin()`: blades do 60 % |
| Death | `hero_down`, rig `death`, `Game.hero_died` (main.gd respawns at the last altar after 3 s) |

### 3.5 Feel helpers

`Game.hitstop(s)` and `Game.slowmo(scale, s)` run on an unscaled frame clock (the wall clock in play, frame time in
`--fixed-fps` / movie runs). **Real-time code must use `Game.real_delta(delta)`**, never
`delta / Engine.time_scale`: the engine reads the time scale once per frame, so in the frame where a hit-stop
starts the current `Engine.time_scale` is 50 times smaller than the one that frame's delta was made with.
(`scripts/ui/style.gd` and `scripts/core/audio.gd` still divide by `Engine.time_scale`, clamped to 0.1 s: a
0.1 s jump on the first frame of each hit-stop. Their owners should switch.)

---

## 4. The chain spear (`ChainSpear`, `Hero` CHAIN / HANG)

| | Value |
|---|---|
| Range | 22 m from the hero's shoulder; let go beyond 26 m |
| Aim assist | the best `chain_anchor` (alive, 1.2-22 m away, in front of the camera) inside 12 degrees of the camera's forward, + up to 25 degrees for close targets (fades from 3 to 14 m); score = angle / cone + 0.3 x distance / range; the four best are checked for line of sight on the world and movable layers (the anchor itself does not block); refreshed 20 times a second; `Hero.chain_candidate` + signal `chain_candidate_changed(target)`; a subtle bronze glint marks it (not on a foe within 3.2 m, not while swinging) |
| No target | the spear flies to what the camera centre looks at (first surface within range) or to the end of the range; a wall or the ground sends it back with a clink |
| Throw | rig `throw` at x1.3 (upper body when moving or airborne): the left hand draws the spear from the back and lets it go at the `release` event, 0.36 s after the press; `chain_throw` |
| Flight | 50 m/s, homing on the target's `chain_point()`; the first anchor it touches on the way is the one it bites (`chain_stick`, sparks, a little shake, `on_chain_attach(hero)`) |
| Return | butt first to the left hand, 10 -> 40 m/s (110 m/s^2); `chain_rattle`; then back on the back |
| The chain | bronze links (one MultiMesh, up to 260 links, 0.095 m apart, 0.12 x 0.07 m) from the left fist to the spear's butt ring; slack: sags (0.06 x length + 0.1 m, never below the ground under its middle) and whips after the throw; taut (`ChainSpear.taut`, set by the hero): straight with a tension tremble |

What the bite does, by `chain_kind()`:

| Kind | Hero | Target | Numbers |
|---|---|---|---|
| `&"ring"` | 0.07 s of tension, then zips along a gentle arc to hang 0.5 m out and 2.3 m under the ring (`set_motion_state(&"zip")`, `chain_taut`, `chain_zip`, FOV +13). A walkable, roomy top 0.9 m under to 1.9 m over the ring just behind it (a ledge): he climbs straight up and over onto it. None: HANG (the next ring can be thrown at from there; the hero keeps his grip until the new throw bites; jump or roll drops him; 6 s max) | `on_chain_attach` (the ring glints) | zip: accelerates at 70 m/s^2 to 20 m/s, eases out in the last ~3 m (never under 6 m/s); blocked for 4 ticks: lets go; climb 7.5 m/s |
| `&"heavy"` | pulled to it the same way, landing 1.05 m from its surface facing it; a blow buffered on the way becomes attack3 on arrival | stays put | arc 0.5 m higher |
| `&"light"` | rig `pull` (x1.15); at its `pull` event (0.21 s): `target.on_chain_pull(hero, dir)` (dir: target -> hero); released when it lands within 2.6 m or after 0.9 s | Enemy base: hops to land 1.2 m + its radius + 0.36 m in front of the hero (0.25-0.65 s, an arc 0.45 m + 5 % of the distance), staggered `yank_stagger` (1.1 s) after landing: a set-up for the combo | |
| `&"beast"` | braces, rig `pull` (x0.9), at the `pull` event (0.27 s): `on_chain_pull(hero, dir)`, shake 0.35, hit-stop 0.05, jerked 2.5 m/s towards it; lets go 0.5 s later | Enemy base: slides `chain_slide` m (3.5) along dir; slamming into the world or a movable on the way stuns it (section 6.5) | slide speed sqrt(2 x 16 x chain_slide) (10.6 m/s for 3.5 m), 16 m/s^2 |
| `&"boulder"` | haul while the button is held (if it was let go before the bite: 1 s to press it again): faces the boulder, back-pedals at 2 m/s; the chain is as long as the distance at the bite and reels in at 0.9 m/s while held (down to 2.8 m); taut: `on_chain_pull(hero, dir)` every tick, and the hero is held back | Boulder: dragged at 2.4 m/s (accel 7, friction 11), rolls and scrapes (`boulder_drag` loop, dust), jams in a narrower doorway (`boulder_thud`) | let go: release the button, or beyond 26 m |

Press the chain button again while the spear is out to call it back. A light target's or a beast's death releases it.

---

## 5. Lock-on and the camera (`CameraRig`)

| | Value |
|---|---|
| Lock-on | press: the `lockable` nearest the screen centre (score: normalised screen distance + 0.35 x distance / 25 m) within 25 m of the hero, on screen, in sight (world layer); `Game.lock_changed(target)` (null on release) |
| Switch | a flick of the right stick past 75 % (after resting under 30 %) or 90 px of sideways mouse within 0.25 s: the nearest lockable on that side of the current one |
| Release | press again; the target dies or leaves the groups; beyond 30 m; out of sight for 2 s |
| Framing | yaw turns to look from behind the hero at the target (6/s), pitch -15 - 2.5 x (height difference - 1) - 0.15 x separation (between -34 and -4), arm 5.2-8.5 m with the separation, focus 15-35 % towards the midpoint, shoulder offset 0.8 m |
| Locked movement | the hero faces the target and strafes / circles it (the rig steps sideways and back-pedals); sprinting runs free |
| Arm | 5.5 m from a pivot 1.55 m over the hero, a sphere of 0.3 m cast on the world layer every frame: comes in at once, eases back out (2.6/s); walls close on both sides (rays of 2.4 m) shorten it to 68 % |
| Follow | XZ 14/s, Y 7/s (never more than 3 m behind), lead 7 % of the hero's velocity |
| Recentring | after 1.4 s without look input, behind a hero moving faster than 2.5 m/s |
| Combat | foes within 11 m: arm +0.9 m, shoulder offset 0.55 m (eased), pitch eases to -20 degrees while the player leaves the camera alone |
| Feel | FOV 60, +5 sprinting, +13 zipping; shake: trauma squared, offsets up to 0.35 m and 0.05 rad of roll, decays 1.7/s (Settings `shake` off disables shake and nudges); nudge: a spring (k 160, damping 18) pushed 9 x amount along the blow |
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
| `telegraph(seconds, cue_point := INF, sound := "", strength := 1.0)` | starts a readable wind-up: a gold glint at `cue_point` (default over the lock point), a flash on the rig, `sound`. `telegraph_t` / `telegraph_left()` count down; `_on_telegraph_done()` fires at the end (strike there). A blow with stagger >= 0.3, a chain bite, a parry or a stun cancel it |
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

Level recipe: the throw needs a clear line, the beast's body does not. Put pillars so that the line from the hero
to the beast passes 0.9-1.4 m beside a pillar (closer than the beast's radius + the pillar's): the spear flies by
it, the beast's flank slams into it. With `chain_slide` 3.5 m the beast must be within about 3 m of the pillar on
its way. (Arena: beast at (-12, 19), pillar at (-12, 15), hero at (-9.8, 9.5).)

### 6.6 The grapple protocol (the wrestle)

The target drives the rhythm; the hero answers. Group `"grapplable"` plus these methods (duck-typed):

| Direction | Call | When |
|---|---|---|
| hero -> target | `can_grapple(hero) -> bool` | every tick while the hero looks for something to use (true: interact starts the wrestle, the UI shows `interact_info()` if the target has it) |
| hero -> target | `grapple_anchor(hero) -> Transform3D` | at the start and every tick of the wrestle: where the hero's origin goes, its basis -Z the way he faces. `RigHeracles.GRAPPLE_HOLD` (0, 1.17, -0.43) is where his arms lock: put the beast's neck / head there |
| hero -> target | `grapple_begin(hero)` | once, when it starts (the hero snaps to the anchor, stops colliding with enemies, plays `grapple_start` then `grapple_loop`) |
| target -> hero | `hero.grapple_cue(window)` | a squeeze beat: a window of `window` s (the hero shows a glint on the hold) |
| hero -> target | `grapple_input(hero, timing_ok)` | every press of attack or interact; `timing_ok` = inside an open window (a press consumes it) |
| target -> hero | `hero.grapple_thrash(cost)` | the beast throws its weight about: `cost` stamina, a fifth of it if the hero holds guard; out of stamina the hero is thrown off (knockback 6 m/s, `hit_heavy`) |
| target -> hero | `hero.grapple_release(won)` | the target ends it: `won` = the beast is beaten |
| hero -> target | `grapple_end(hero, won)` | **always**, once, whatever ended it (released, thrown off, the hero hurt by someone else, dead); must be idempotent |

The target does the damage itself (`kind: &"grapple"` on a good squeeze) and the sounds (`wrestle_strain` every
beat, `wrestle_squeeze` on a good press, `lion_thrash`, `lion_pain`). The hero regenerates no stamina while
wrestling. Warn before a thrash (`telegraph`, 0.45 s) so the player can raise the guard.

Reference implementation: `tools/arena_beast.gd` (the straw bull): stunned by a pillar it is grapplable; beats
every 1.25 s with a 0.5 s window, a thrash every 2.4 s (24 stamina, warned 0.45 s before); 3 good squeezes win,
3 bad presses or 14 s lose; beaten, it topples for 3 s.

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
actions `recoil` (0.52 s) and `backstep` (0.5 s), the shield kept forward-left in the light blows, the spear's chain
coil in bronze, `spear_meshes(false)` (the bare spear in flight). Clip check: `tools/clip_check_heracles.tscn` (adds
strafe, back-pedal, guard-strafe and hang states).

---

## 8. The arena and its bot

`tools/arena.tscn` (or `scene=arena`): a stone platform by the sea with three straw posts (heavy), a sparring post
(swings a club after a telegraph: block / parry / roll practice), two straw sacks on sleds (light chain targets),
the straw bull (beast), a ring under a cliff lip (zip and climb), a sea gap with a ring on a sea stack and one under
the far cliff (ring to ring), a wall with a doorway narrower than the boulder (haul it in to seal it), a row of
pillars, ramps of 15 / 30 / 45 / 58 degrees.

```sh
# every test, faster than real time (prints one line per test and a summary)
timeout 900 godot --headless --path doce/game res://tools/arena.tscn --fixed-fps 60 --quit-after 6000 -- autotest=1 quit=1 | grep ARENA
# some tests
... -- bot=combo,heavy,parry quit=1
# a movie of a test from the gameplay camera, then strips (one row per move)
xvfb-run -a -s "-screen 0 1600x900x24" godot --path doce/game --rendering-driver opengl3 --resolution 1280x720 \
  --write-movie /abs/frames/combo/f.png --fixed-fps 30 --quit-after 100 res://tools/arena.tscn -- bot=combo noui=1
python3 doce/game/tools/arena_strips.py strips.png --row "combo:/abs/frames/combo:16:8:3"   # frame from "ARENA mark"
```

Tests (`tools/arena_bot.gd`): lockon (acquire, stick flick to the next, strafe facing, release), combo (attack1,
attack2, attack3 in order), heavy (charge, charged, 30 damage with guard_break), guard (a block costs stamina, no
damage), parry (guard 0.09 s before the club lands: parried, the post reels), dodge (roll through the club),
light (a sack 12 m away lands in front of the hero), ledge (zip to the ring under the west cliff and climb on),
rings (ring A on the sea stack, hang, ring B, climb onto the far cliff), beast (yank the bull into a pillar, stunned,
walk up, wrestle: squeeze in the windows, brace on the thrashes, win), boulder (haul it into the east doorway).
Debug args: `meleedebug=1` (blade sweep distances), `camdebug=1` (camera per frame), `feeldebug=1` (hit-stops).
