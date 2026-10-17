# ANIMATION: how Heracles moves (study, spec, metrics)

Client complaint this answers (summary of the Spanish original): the character animations are bad when striking and when
running; they are not natural; the arms and wrists look wrong when striking, "only the arm moves"; when running the
torso is too straight. "Study how to make natural animations."

Scope of the three steps that fix it:

| Step | What | State |
|---|---|---|
| 1 | Study, this spec, the objective metrics, and the **locomotion** (idle, walk, jog, sprint, strafe, back-pedal, start, stop, turn, landing) | done |
| 2 | The three-hit combo, the heavy blow, shield arm, footwork (section 4 is its spec, 4.8 says how it was built) | done: `anim_check mode=strike` and `mode=combo` are green |
| 3 | Consistency and transitions: every other action (parry, dodge, hit, death, jump, throw, pull, wrestle, ceremonies) against the same rules, every blend, and an automatic pop detector (section 8; 6.7 and 6.8 are its numbers) | done: `anim_check mode=pops` 268 of 268, loco / trans / strike / combo / swap green, `mode=ranges` 67 of 72 (the five that remain are listed in 8.8) |

Everything below is checked by `tools/anim_check.tscn` (numbers, no window), `tools/anim_strips.sh` and `tools/strike_strips.sh` (frame
strips to look at) and `tools/clip_check_heracles.tscn` (the rig's own sword/shield/body intersections). Section 6 has the commands
and the numbers, section 8 how the other actions and the transitions were built.

Honesty note (read it before trusting a number). The web research was 21 searches; the pages themselves could not be
opened (the fetch tool was blocked), so everything quoted from the literature is what the search summaries said, plus
craft knowledge. Numbers are marked **(lit.)** when they are a typical range from the biomechanics / animation
literature, **(design)** when we chose them for this rig, and **(measured)** when `anim_check` reports them. The hero is
not a human: his run is 22 km/h and his sprint 32 km/h on a leg 0.84 m long, so cadence and stride are bounded by what
his leg can reach (section 3.3), not copied from runners.

---

## 1. What the study says and what we took from it

### 1.1 The twelve principles, as rules for this rig

| Principle | Rule in the rig |
|---|---|
| Anticipation | Every blow has a wind-up of 3-5 frames (at 30 fps) that coils pelvis and chest away from the target before the arm moves; the sprint leans in before it pushes; a jump crouches first. |
| Follow-through, overlapping action | The blade lags the hand, the hand lags the elbow, the elbow lags the shoulder, the shoulder lags the chest, the chest lags the hips (the kinetic chain, 1.4). After the hit the chest overshoots 8-10 degrees and settles. Cape, crest and skirt are simulated and answer the motion. |
| Slow in, slow out | Every blend is eased (smoothstep, critically damped springs); swing feet follow smoothstep arcs; nothing starts or stops linearly. |
| Arcs | Feet, hands and the blade tip move on curved paths, never straight lines between two keys. |
| Timing | Cadence, stance share and strike phases are tables against speed or frames (3.3, 4.1); 30 fps frame counts are the unit. |
| Staging | The silhouette reads from the gameplay camera (behind and above): lean, free sword arm, shield rim and the blade stay outside the body line. |
| Secondary action | Arm swing, head stabilisation, breathing, cape and crest are secondary to the legs and torso and are driven by them. |
| Exaggeration | Lean and counter-rotation are above life at the top speed (the sprint leans 19 degrees; real top-speed sprinters lean 5-15) because the camera is far away; still inside joint limits. |
| Squash and stretch | Not literal (armour). Weight comes from the pelvis dropping into each stance ("down") and the stretch in the flight phase. |
| Solid drawing | No sword, shield, arm or cape through the body (clip check), joints inside human ranges (6.3). |
| Straight ahead / pose to pose | Poses are authored (key tables), the rest is procedural (feet planted in the world, springs). |
| Appeal | One clear read per gait: idle upright and calm, walk relaxed, jog driving, sprint committed. |

### 1.2 The run cycle in animators' terms (Williams, "Animator's Survival Kit"; Animation Mentor; mocap run references)

One step has four key poses; a cycle is two steps (left and right):

1. **Contact**: the lead foot reaches out and touches down (heel first at a jog, forefoot at a sprint), the other leg
   is behind and about to leave the ground. Arms are opposite to the legs.
2. **Down**: the body absorbs the landing and is at its **lowest**; the contact knee bends.
3. **Passing**: the rear leg, folded, passes beside the supporting leg; the body is rising.
4. **Up**: the push-off leg is extended and the body is at its **highest**, in the flight phase (running only; a walk
   has no flight and its highest point is at passing).

What makes it read as a run (in this order of importance): forward lean from the ankles (the whole line), a flight
phase, counter-rotation of pelvis and chest, bent elbows (about 90 degrees) with the arms swinging opposite to the legs,
a head that stays level while the body bobs, the vertical bob **twice per cycle**, the foot rolling heel to toe.

### 1.3 Biomechanics used as ranges (lit.)

* Walk: duty factor (one foot's contact share) about 60 %, no flight, vertical oscillation of the pelvis 3-5 cm, trunk
  almost upright, pelvis rotation +-3-5 degrees, arm swing 10-20 degrees, elbow flexed 20-30 degrees.
* Run: duty factor below 50 % and falling with speed (about 25 % at a sprint), flight 30-50 %, pelvis rotation +-5-8
  degrees and thorax counter-rotation larger than the pelvis's (ratio 1.2-2, in anti-phase), vertical oscillation 6-10
  cm for the centre of mass, elbow about 90 degrees with 70-110 degrees of range, shoulder swing +-30-50 degrees at a
  sprint, the arm swing matches the stride frequency and opposes the leg of the same side, knee flexion in the swing
  100-140 degrees (jog to sprint), head stabilised (small pitch, gaze level).
* Sprint acceleration leans far more than top speed (45 degrees falling to 5-15); we use a stylised 19 degrees.
* The head is a stabilised platform: neck and head counter-rotate against the trunk's pitch, yaw and roll
  (sicb head-stabilisation work), vertical head travel is smaller than the pelvis's.

### 1.4 Striking: the kinetic chain (lit.)

Baseball pitching, golf and tennis, the fencing lunge and kendo agree on one pattern: power travels ground, legs, hips,
trunk, shoulder, elbow, wrist, tool, and each link **peaks in angular speed after the one below it and faster than it**
(speed summation: roughly 450-700 deg/s at the pelvis, 700-1100 at the trunk, then 1500-4000 deg/s at the arm links).
The gap between consecutive peaks is 20-60 ms, so inside a 3-frame cut at 30 fps (100 ms) the peaks sit 0.5-1 frame
apart. A strike where the arm moves while the hips stay still, or where the wrist peaks before the hips, is read as "only
the arm moves": that is exactly the baseline (section 4.7).

Kendo specifics worth keeping: the cut is a big arc with the point travelling on a line (hasuji) and the foot step lands
**at the same instant** as the cut (ki-ken-tai-ichi); the wrist stays in line with the forearm until the last moment, then
the grip tightens in a short snap (tenouchi); there is no "broken wrist".

Game feel (GDC Ghost of Tsushima, God of War 2018 talks, frame-data writing, hit-stop articles): attacks are startup
(anticipation), active, recovery; heavier blows get longer anticipation and longer hit-stop; hit-stop of about 2-4 frames
(light) to 6-12 frames (heavy) at 60 fps sells weight; the pose is held on the contact frame; recovery is where the
player's control returns and it should look like a different path from the strike (no retracing).

### 1.5 Procedural techniques used (and why)

* **Feet planted in the world.** The heel, then the toe, stay pinned where they touched down; the swing is an arc in
  world space to the next landing spot. Nothing slides (the baseline's planted feet slid up to 54 cm at a walk).
* **Phase-driven cycle from speed tables** (cadence, stance share, stance pitch...), smoothstepped between anchor speeds.
* **Pelvis governor.** The pelvis is lowered where a leg would over-reach and rises no faster than 1.5 m/s.
* **Lean springs.** A critically damped spring adds lean into an acceleration and roll into a turn (Little Polygon,
  Forsyth "how to walk", "physics-driven lean" write-ups); head lead into turns filters at 9/s.
* **Head stabilisation**: neck and head take 55 % and 45 % of the trunk's pitch back.
* **Forward-kinematics arms** (shoulder swing + abduction + elbow flexion), phase tied to the opposite thigh.

### 1.6 Sources searched

gameanim (12 principles in games); animationmentor (12 principles, dynamic run cycles); monmouth (walk cycle); Edward
Boyle (Animator's Survival Kit notes); mocaponline (run cycle); PMC11929735 (active arm swing in running); Taylor and
Francis 14763141.2021.1873411 (running styles) and 23335432.2018.1454342 (fencing lunge kinetic chain); PMC6355803 and
ResearchGate 316669883 (thorax-pelvis rotation, sprint); biologists.com bio/3/8/689 (sprint acceleration); PMC9961938
(pelvic rotation, IMU); mytpi (linear kinematic sequence); PMC7919348 and rocklandpeakperformance (pitching sequence);
kendo hksapientia (kihon) and PMC9921416 (kendo strike phases); ssbwiki (hitlag), swordarcade and gamineai (hit-stop);
gamedeveloper.com (frame-specific attacks, God of War), gamesradar and playstation.blog (God of War 2018); critpoints
(frame data); GDC vault 1027194 (Ghost of Tsushima); docs.vulkan.org and blog.littlepolygon.com (locomotion, lean);
Forsyth "How to walk" (scribd); theorangeduck (spring roll call); ryanjuckett (damped springs); sicb.org and PMC7139831
(head stabilisation); runnersconnect (vertical oscillation); runbuzz (cadence); animationapprentice (successive
breaking of joints); physio-pedia (running biomechanics).

---

## 2. The rig, in the units the spec uses

`scripts/gfx/rig_heracles.gd` is a code rig: a 30-bone `Skeleton3D` plus a cape cloth, no AnimationPlayer. A pose is a
`PackedFloat32Array` of channels; `_solve` turns it into bones (two-bone IK for arms and legs, a sole rule that lifts the
ankle so the heel and toe never sink, a keep-out that pushes hands and elbows out of the body capsules).

* Space: the rig faces -Z, origin between the feet on the ground, +Y up, metres. Chest space: origin at the chest bone
  (0, 1.30, 0), the shoulders at (+-0.255, 0.175, 0.02) from it.
* Angles: `eul(v)` = yaw (Y), then pitch (X), then roll (Z). Pitch + leans **back**, yaw + turns **left** (the right
  side comes forward), roll + lifts the right side. Channels `pel` (pelvis offset), `pelr` (pelvis rotation), `spn`,
  `chs`, `nek`, `hed` are Euler triples; `hr`/`hrb`/`hrk`/`hrp` are the sword grip position, the blade direction, the
  back-of-hand direction and the elbow pole (chest space, or rig space with the `hrs` flag); `hl`/`hlf`/`hlp` the same for
  the shield hand (wrist, shield facing, pole); `fr`/`frr`/`frp` and `fl`/`flr`/`flp` the ankles (rig space), their
  Euler and the knee poles.
* The hand's zero is a **hammer grip** (blade across the forearm, out of the thumb side, back of the hand outward).
  "Ulnar deviation" below is the angle the blade is turned from that zero towards the forearm's own line; a pointing
  grip needs 50-65 degrees of it, which is why the wrist check (6.3) measures the blade-to-forearm angle too.
* Hero speeds (Hero): walk 2.2, run 6.2, sprint 9.0 m/s; acceleration 40, deceleration 48 m/s^2 (a start is 0 to 6.2 m/s
  in 0.15 s, which no body does; the gait has to hide it, 3.5).
* Frame rate: the strike spec counts in frames at 30 fps (1 frame = 33.3 ms); the metrics run at 60 or 120 Hz.

The ground gait lives in one block of `rig_heracles.gd` ("animation: the ground gait": tables, foot state machine,
`_ground_pose`). Hero feeds it only `set_locomotion(speed, RUN_SPEED)`, `set_motion_state`, `set_vertical_speed` and the
ground probe; the rig derives acceleration, turn rate and travel direction from its own motion (so a start, a turn or a
strafe lean the body with no new input from `hero.gd`).

---

## 3. Locomotion spec

### 3.1 The numbers per gait

Design = the table value the rig is driven by; measured = what `anim_check` reports for it (60 Hz, steady state).

| | idle | walk | jog (run) | sprint |
|---|---|---|---|---|
| ground speed m/s | 0 | 2.2 | 6.2 | 9.0 |
| cycle frequency Hz (one cycle = 2 steps) (design) | - | 1.28 | 2.10 | 2.45 |
| stride m per cycle (measured) | - | 1.71 | 2.96 | 3.68 |
| contact share of the cycle, one foot (measured) | - | 0.61 | 0.33 | 0.25 |
| flight share, no foot down (measured) | 0 | 0 | 0.34 | 0.50 |
| trunk lean, hip to neck line, degrees (measured) | -2.4 (chest out) | 2.5 | 9.2 | 19.5 |
| pelvis yaw amplitude +- deg (measured) | 0 | 4.0 | 6.5 | 8.5 |
| chest counter-rotation +- deg, ratio to pelvis (measured) | 0 | 4.9, 1.2 | 10.4, 1.6 | 16.3, 1.9 |
| pelvis list (roll) +- deg (measured) | 0.2 | 3.0 | 3.5 | 4.0 |
| pelvis bob peak to peak cm, twice per cycle (measured) | 0 | 2.8 | 4.5 | 4.5 |
| head pitch / yaw peak to peak deg (measured) | 2.7 / 0.8 | 0.4 / 1.6 | 0.9 / 4.0 | 1.5 / 6.5 |
| sword-arm shoulder swing +- deg (measured) | 0 | 17.7 | 31.0 | 36.7 |
| sword-arm elbow flexion mean deg (measured) | - | 40 | 95 | 93 |
| shield-arm swing +- deg (measured) | - | 6.2 | 9.9 | 12.8 |
| knee flexion peak in the swing deg (measured) | - | 78 | 113 | 129 |
| hip flexion max / extension max deg (measured) | 12.4 / 12.2 | 48.7 / -14.3 | 74.6 / -19.5 | 94.9 / -26.7 |
| foot pitch at touchdown / at toe-off deg (measured) | 0 / 0 | +15 / -51 | +3 / -55 | -8 / -63 |
| foot slide while planted cm (measured) | 0 | 1.0 | 0.4 | 0.1 |

(Foot pitch + = toe up. A negative touchdown pitch is a forefoot strike.)

### 3.2 Key poses (measured, by the right foot's phase)

Phase 0 is the right heel (or toe) touching down; the left foot is half a cycle later. So phases 0 / 0.125 / 0.25 / 0.375
are **contact / down / passing / up** of the right step and 0.5 / 0.625 / 0.75 / 0.875 the same four for the left step.
Angles in degrees: hip and knee flexion + = thigh forward / knee bent; shoulder flexion + = arm forward; trunk lean + =
forward; yaw as in section 2 (+ = turned left).

Walk, 2.2 m/s:

| phase | 0 | .125 | .25 | .375 | .5 | .625 | .75 | .875 |
|---|---|---|---|---|---|---|---|---|
| pelvis height m | 0.91 | 0.93 | 0.93 | 0.92 | 0.91 | 0.93 | 0.93 | 0.92 |
| trunk lean | 2.4 | 2.4 | 2.5 | 2.6 | 2.4 | 2.4 | 2.5 | 2.6 |
| pelvis yaw | 3.6 | 1.5 | -1.6 | -3.6 | -3.6 | -1.4 | 1.4 | 3.6 |
| chest yaw | -4.7 | -2.9 | 0.7 | 3.8 | 4.7 | 2.8 | -0.5 | -3.6 |
| right hip / knee | 37 / 38 | 25 / 42 | 7 / 36 | -1 / 47 | -11 / 48 | 12 / 69 | 43 / 70 | 43 / 34 |
| left hip / knee | -10 / 48 | 12 / 68 | 44 / 68 | 42 / 31 | 37 / 39 | 24 / 42 | 7 / 36 | -1 / 45 |
| right foot pitch | 6 | 0 | -2 | -22 | -46 | -36 | -5 | 14 |
| right / left shoulder | -11 / 9 | 2 / 5 | 13 / 1 | 15 / 0 | 8 / 2 | -4 / 7 | -15 / 11 | -19 / 12 |
| right / left elbow | 35 / 74 | 46 / 68 | 54 / 65 | 53 / 65 | 44 / 70 | 32 / 75 | 27 / 78 | 28 / 78 |

Jog, 6.2 m/s:

| phase | 0 | .125 | .25 | .375 | .5 | .625 | .75 | .875 |
|---|---|---|---|---|---|---|---|---|
| pelvis height m | 0.89 | 0.87 | 0.90 | 0.91 | 0.89 | 0.87 | 0.90 | 0.91 |
| trunk lean | 8.5 | 9.4 | 9.9 | 9.0 | 8.5 | 9.4 | 9.9 | 9.0 |
| pelvis yaw | 5.9 | 2.6 | -2.4 | -5.8 | -5.9 | -2.5 | 2.3 | 5.8 |
| chest yaw | -10.1 | -6.5 | 1.2 | 8.0 | 10.1 | 6.4 | -1.1 | -8.0 |
| right hip / knee | 38 / 50 | 20 / 65 | -10 / 46 | -9 / 60 | 26 / 98 | 66 / 105 | 68 / 65 | 46 / 24 |
| left hip / knee | 26 / 98 | 66 / 105 | 67 / 64 | 45 / 24 | 38 / 50 | 19 / 65 | -10 / 46 | -9 / 60 |
| right foot pitch | 1 | -16 | -43 | -48 | -36 | -17 | -1 | 3 |
| right / left shoulder | 9 / 18 | 25 / 13 | 22 / 14 | 3 / 20 | -19 / 28 | -33 / 32 | -31 / 31 | -13 / 26 |
| right / left elbow | 104 / 103 | 108 / 101 | 104 / 104 | 95 / 108 | 86 / 113 | 82 / 114 | 86 / 112 | 95 / 108 |
| head pitch | -0.3 | 0.1 | 0.5 | 0.2 | -0.3 | 0.1 | 0.5 | 0.2 |

Sprint, 9.0 m/s:

| phase | 0 | .125 | .25 | .375 | .5 | .625 | .75 | .875 |
|---|---|---|---|---|---|---|---|---|
| pelvis height m | 0.86 | 0.86 | 0.88 | 0.89 | 0.86 | 0.85 | 0.88 | 0.89 |
| trunk lean | 18.7 | 19.9 | 20.2 | 19.0 | 18.7 | 19.8 | 20.2 | 19.0 |
| pelvis yaw | 7.6 | 3.1 | -3.1 | -7.6 | -7.8 | -3.5 | 3.0 | 7.8 |
| chest yaw | -15.8 | -9.8 | 2.0 | 12.7 | 15.9 | 10.5 | -1.9 | -13.1 |
| right hip / knee | 42 / 63 | 13 / 64 | -22 / 36 | -5 / 73 | 39 / 117 | 87 / 117 | 84 / 70 | 64 / 45 |
| left hip / knee | 42 / 119 | 88 / 115 | 84 / 70 | 65 / 45 | 44 / 62 | 16 / 67 | -22 / 36 | -4 / 75 |
| right foot pitch | -3 | -32 | -48 | -49 | -40 | -26 | -14 | -11 |
| right / left shoulder | 17 / 13 | 30 / 9 | 21 / 12 | -4 / 21 | -28 / 30 | -41 / 34 | -33 / 31 | -8 / 22 |
| right / left elbow | 103 / 100 | 104 / 99 | 100 / 102 | 91 / 108 | 84 / 111 | 82 / 112 | 87 / 109 | 95 / 104 |
| head pitch | -2.4 | -1.7 | -1.0 | -1.8 | -2.4 | -1.8 | -1.1 | -1.8 |

Read the poses like this: at the jog's contact (phase 0) the chest is turned 10 degrees right while the pelvis is 6 to the
left (counter-rotation), the right leg reaches (hip 38, knee 50, foot nearly flat), the left leg is folded and driving
forward (knee 98), the left arm is forward and the right arm is starting to come forward, the elbows are at 104 degrees,
and the pelvis is 2 cm above its lowest point. At "down" (0.125) the pelvis is lowest and the contact knee is at 65.

### 3.3 How each quantity scales with speed (the tables in the code)

Tables are `[speed, value, speed, value, ...]`, smoothstepped between anchors, flat beyond the ends (`_pl` in the rig).

| Quantity | table (speed m/s: value) |
|---|---|
| cycle frequency (Hz) | 0.55: 0.62, 1.4: 1.0, 2.2: 1.28, 3.2: 1.55, 4.5: 1.9, 6.2: 2.1, 9.0: 2.45 |
| stance share of the cycle | 0.55: 0.78, 1.4: 0.6, 2.2: 0.52, 3.2: 0.42, 4.5: 0.32, 6.2: 0.26, 9.0: 0.2 |
| foot pitch at touchdown (rad, + toe up) | 2.2: 0.26, 3.2: 0.18, 4.5: 0.10, 6.2: 0.05, 9.0: -0.20 |
| foot pitch at toe-off (rad) | 2.2: 0.75, 6.2: 0.82, 9.0: 0.90; the heel rises from 55 % of the stance (walk) to 36 % (sprint) |
| swing apex above the line (m) | 0.55: 0.02, 2.2: 0.035, 4.5: 0.11, 6.2: 0.16, 9.0: 0.24 |
| trunk lean hip to neck (deg) | 0: 0, 2.2: 4, 4.5: 8, 6.2: 11, 9.0: 21.5 (the budget; it is shared 0.38 pelvis, 0.34 spine, the rest chest, after a factor of 1.29 so the chest leans most; the measured hip-to-neck line leans a little less: 2.5 / 9.2 / 19.5) |
| pelvis yaw amplitude (deg) | 2.2: 4, 4.5: 5.5, 6.2: 6.5, 9.0: 8.5 |
| chest counter-rotation ratio | 1.2 at a walk, 1.4 at 4.5, 1.5 at 6.2, 1.6 at 9.0 |
| pelvis list (deg) | 2.2: 3, 4.5: 3.5, 6.2: 3.5, 9.0: 4 |
| pelvis sway over the stance foot (m) | 2.2: 0.022, 4.5: 0.015, 6.2: 0.012, 9.0: 0.010 |
| bob (m, + high at mid-stance, - low) | 2.2: +0.016, 3.2: 0, 4.5: -0.02, 6.2: -0.03, 9.0: -0.032 (twice per cycle) |
| pelvis height offset (m) | 0: -0.035, 2.2: -0.06, 4.5: -0.08, 6.2: -0.09, 9.0: -0.11 (the bent knees) |
| pelvis forward with the lean (m) | 2.2: -0.01, 4.5: -0.03, 6.2: -0.05, 9.0: -0.09 |
| sword arm: swing centre / amplitude (deg) | centre 0 (walk, 4.5), -2 (jog), -4 (sprint: the arm goes back further than forward); amplitude 20 / 29 / 33 / 39 at 2.2 / 4.5 / 6.2 / 9.0 |
| sword arm: elbow mean +- swing (deg) | 38 +- 12 (walk), 86 +- 10 (4.5), 92 +- 10 (6.2), 90 +- 8 (9.0) |
| sword arm: abduction (deg) | 18 (walk), 16, 15, 15 (elbows out so the upper arm clears the cuirass) |
| arm phase (the arm is furthest forward at this share of the cycle) | 2.2: 0.41, 4.5: 0.30, 6.2: 0.23, 9.0: 0.20 (tuned so the forward peak coincides with the opposite thigh's) |
| shield arm: centre / amplitude / elbow / abduction (deg) | centre 9 (walk) 20 27 26 (sprint); amplitude 7 9 10 13; elbow 68 96 102 100; abduction 20 |
| sword hand: ulnar deviation (deg) | 48 (walk) 54 58 58, plus 0.4-0.5 times the arm's swing, clamped to 30-60 so the blade stays at least 30 degrees off the forearm line (28 measured); forearm twist 8 (walk) to 30 (sprint) turns the tip outward |
| knee pole (how far out the knee points per unit forward) | 2.2: 0.25, 4.5: 0.14, 6.2: 0.08, 9.0: 0.03 (a sprinter's knee goes straight ahead; wide knees put the blade and the shield through the thigh) |
| helmet gaze pitch (deg, + down) | 0: 0, 2.2: 1.5, 6.2: 0.5, 9.0: -1 |

Why cadence and stride are not a runner's: with `stance excursion E = speed * stance share / frequency` the foot lands
about 0.38 E in front of the pelvis and leaves 0.62 E behind; at the leg's reach (0.84 m, the pelvis never asks more than
99 % of it) E must stay near 0.8 m, which fixes the cadence at 2.1 Hz for 6.2 m/s. Lower cadence over-stretches the leg
(the baseline's legs were over-extended in 19-29 % of the frames).

### 3.4 Feet, step by step

* Each foot is a small state machine: **stand** (heel pinned, then the sole comes flat and the **toe** is pinned while the
  heel rises: the foot rolls over a world-fixed contact), **swing** (an arc from where it left to where the next step
  will land, the ankle height eased so the toe never drags) and **home** (a short step back to the idle stance when the body
  stops, or turns more than 0.62 rad away).
* Touchdown target: ahead of the pelvis by `0.38 * speed * stance share / frequency` (0.29 m at a jog) plus the speed over
  the rest of the swing; sideways travel crosses the legs (the right foot lands behind the left going right), backwards
  the foot lands flat; the step is 0.75 times as long going backwards and 0.62 times going sideways (the cadence rises to match).
* `step` events fire on **real touchdowns** (measured lag from the first contact frame: 0.00-0.02 s, spec 0.05).
* A planted foot the body has run away from lifts at once: 0.56 m behind the pelvis, 0.36 m while accelerating hard.
* The pelvis never asks more than 99 % of the leg's length: where a leg would over-reach, the pelvis drops (cap 12 cm,
  immediately) and it rises again at no more than 1.5 m/s.

### 3.5 Starts, stops, turns, landings (no pops)

* **Start.** Cadence and stance follow the speed the body is *about to have* (`speed + 0.1 * dA/dt`, from the speed that
  is fed, which rises 0 to 6.2 m/s in 0.15 s), so the first stance is short; the lean spring adds the push (clamped to
  0.12 rad); a foot that was stepping home when the run restarts becomes the first swing; the pelvis cycle terms (sway,
  turn, list, bob, arm swing) fade in over 0.12 s so a restart never jumps to the new phase; the arms leave their idle
  pose with a 9/s filter.
* **Stop.** The foot in the air comes down at home (0.16-0.30 s), the planted one stays; cycle terms fade out over 0.12 s;
  lean springs back.
* **Turn.** Roll into the turn (lean springs: up to 0.2 rad, `yaw rate * speed * 0.0046`), the head leads the turn (yaw
  rate filtered at 9/s, up to 0.35 rad), the chest follows with 3 % of the rate.
* **Landing at speed** (back from the air, a swim, a roll): the foot that touched down is planted where the stride puts it
  (0.29 m ahead of the pelvis at a jog) and the other is half a cycle behind it; the pose blend from the air pose does the
  rest. (Without this the first stance was left 0.5 m behind and the pelvis dipped about 15 cm.)
* **Wheat brush.** The additive "hand in the wheat" pose (`set_brush`) still works with the new gait: the shield arm opens by
  its **joints** (shoulder -26 degrees, abduction 58, elbow 64) as the brush weight rises (abduction first, over the first
  30 %), so the shield rim never sweeps through the chest or the pauldron, and the pelvis rises 5 cm while the hand is
  out (the hand's height is fixed by the ears; the shoulder has to be where the arm can reach it). `tools/wheat_walk.tscn`
  (walk and `run=1`) reports `shield_clip` 0.003 and 0.007 m (limit 0.01).

### 3.6 Torso, head, arms and hands in one paragraph each

**Torso.** Lean has three sources added together: the speed table (3.3), an acceleration spring (forward when the speed
rises, back when it falls) and a turn roll. The lean line is shared pelvis 0.38, spine 0.34, chest the rest, so the
pelvis and spine lean less than the chest and the shoulders lead. The pelvis yaws +-4 to 8.5 degrees with each step and
lists (rolls) 3-4 degrees with the stance leg; the chest counter-rotates with 1.2 to 1.9 times the pelvis's amplitude,
in anti-phase (correlation -0.96 in all three gaits), and a little behind it (0.25 rad); the spine takes 40 % of the
yaw and 40 % of the roll, the chest 60 %.

**Head.** Neck and head take 55 % and 45 % of the trunk's pitch back so the gaze stays level (head pitch peak to peak
under 1.6 degrees at every speed; the helmet looks 1.5 degrees down at a walk and 1 degree up at a sprint). Yaw
compensates 85 % of the chest's counter-rotation; roll 50 % and 40 % of the chest's; plus the lead into turns.

**Sword arm.** Forward kinematics: shoulder flexion `psi = centre + A * cos(th - phase)` (`th` is the cycle angle), the
elbow flexed with a small swing in step, the upper arm abducted 15-18 degrees. The forearm is turned in towards the
midline by `0.18 * run` radians. The **hand** is built from the forearm: the blade lies along the forearm's line turned up
by `90 - ulnar deviation` degrees (30 to 50 degrees), the wrist keeps the blade up at the back of the swing (deviation
follows the arm), the back of the hand faces out and the forearm twists 8-30 degrees so the tip points slightly out.
The blade therefore stays near horizontal at the back of the swing and rises at the front without ever pointing at the
thigh or the face (blade elevation measured -39..+16 degrees at a walk, -13..+49 at a jog, -26..+35 at a sprint).

**Shield arm.** Carried forward and bobbing: flexion 9-27 degrees with +-6-13 degrees of counter-swing, elbow 68-102,
abduction 16-20; never rigid (amplitude 6, 10, 13 degrees).

### 3.7 What the clip checker says about the new gait

`clip_check_heracles` over every locomotion state (idle, walk, run, sprint, guard walk, strafes, back-pedal, lion outfit,
air, swim, zip, hang; 962 samples): baseline **74** issues, worst 4.5 cm (cape through the shield at a strafing run); new
**0 to 3** issues over the locomotion states (it varies from run to run because the rig starts at a random time and the cloth follows: the 3 are a cape corner 8-10 mm into the spear on the back in the air pose, which this step did not touch; the shield rim that was 9 mm into the left thigh at a sprint is gone). All the actions (2602 samples): 863 issues before, 783 after; the blow, grapple and
cape-to-arm issues that remain are steps 2 and 3 (the lion outfit's heavy blow has the cape 1 cm deeper into the arms than
before, 7.1 against 6.7 cm: cloth sensitivity to the new idle stance, the pose of that blow is unchanged). Step 2 rebuilt the blows: 679-686 for all the actions (4.8).

---

## 4. Strike spec (what step 2 was built to; 4.8 says how and what came out)

(4.1-4.8 are the first rebuild of attack1-3 and the heavy. The blows the game plays now are the long blade's moveset, in 4.9.)

Keep the **event times** the game depends on (they are the hit windows): attack1 swing 0.13 s, impact 0.205 s (frame 6.2),
steps 0.2 and 0.53, length 0.56; attack2 swing 0.12, impact 0.20, length 0.56; attack3 swing 0.27, impact 0.345
(frame 10.4), length 0.80; heavy swing 0.36, impact 0.47 (frame 14.1), length 1.00. Change the **poses and their timing**
around them, not the events. (A pose in the table below is at `I + n` frames, `I` being the impact event.)

### 4.1 The phases of a blow (30 fps frames)

| Phase | Frames | Job |
|---|---|---|
| **Anticipation** (wind-up) | I-6 .. I-3 (attack1: 0-3) | Pelvis yaws away 12-18 degrees, chest 30-40 (X-factor 18-22), weight onto the rear leg (pelvis back 4-6 cm and down 4-7), chest leans back 4-6, head turns to the target, sword hand cocked back and high (wrist extension 20-35 degrees), elbow leading, shield arm swings forward-out as counterweight. The last frame is nearly still so the player can read it. 3-4 frames (light), 5-8 (attack3), 8-10 (heavy). |
| **Strike** (acceleration) | I-3 .. I | Hips lead: pelvis sweeps 30-45 degrees in these 3 frames, the chest follows at 1.5-2 times the pelvis's speed, then the shoulder, elbow and wrist in order (4.2). The front foot lands on I (+-1). Knees bend 15-25 degrees: the pelvis drops 7-12 cm and goes 10-14 cm forward over the front foot. |
| **Impact hold** | I .. I+2 | The pose is held (hit-stop belongs to gameplay: 3 frames light, 4-5 attack3, 6 heavy). The blade is 28-40 degrees off the forearm's line (a hand cannot point it closer, 6.3). Nothing else freezes: shield arm and cape keep moving. |
| **Follow-through** | I+2 .. I+8 | The blade carries on along its arc to the natural end (low across the body for the forehand, past the left hip), the chest overshoots the impact orientation by 8-10 degrees and settles, the head follows 1 frame later, the free arm swings the other way, the rear heel is up on the toe. |
| **Recovery** | I+8 .. end | An eased return to the ready stance along a **different** path than the strike (no retracing), 6-10 frames, feet planted until the last step, control returns here. |

### 4.2 The chain: when each link peaks (frames before the impact event, peak angular speed)

| Link | peak at | target peak speed (design) |
|---|---|---|
| pelvis (hips) | I - 3.5 | 6-14 rad/s (about 350-800 deg/s) |
| chest | I - 2.5 | 1.0-3.0 times the pelvis's, 9-20 rad/s |
| shoulder (upper arm relative to the chest) | I - 1.75 | faster than the chest, 15-30 rad/s |
| elbow | I - 1.0 | 15-25 rad/s |
| wrist | I - 0.5 | 15-30 rad/s, a short snap of 20-30 degrees |
| blade tip | I - 0.25 | 15-30 m/s, never above 30 |

Consecutive peaks 0.5-1 frame apart, hips first. `anim_check mode=strike` enforces the order (no violation beyond 1
frame), hips-to-wrist spread of 2-9 frames, pelvis peak 6-14 rad/s, chest/hips 1-3, tip speed <= 30 m/s.

### 4.3 Arcs, wrist and blade

* The hand travels on one smooth arc around the shoulder (an arc, not two straight keys): between keys that are more than
  45 degrees apart add a key, or interpolate the blade direction on the sphere. **Linearly interpolating `hrb` between two
  nearly opposite directions (the baseline's attack1 does it between `a1b` and `b1b`) passes through a near-zero vector and
  flips the blade in one frame**; that is the weird wrists.
* Wrist: flexion/extension -60..+70 degrees, deviation inside its limit (6.3). The blade lies along the forearm at impact
  (28-40 degrees between them: no closer than a hand can hold it, 6.3) and the **edge leads**: the blade's flat is perpendicular to the plane of the arc.
  The wrist is stiff until I-1, then snaps; the forearm twists through the swing (palm down in the wind-up, thumb up at the
  hit).
* Elbow: 0-150 degrees, extending through the strike (elbow peak after shoulder, before the wrist).

### 4.4 Shield arm

A counterweight and a guard. It moves **opposite** to the sword arm and the chest: while the sword arm goes back the
shield arm goes forward-out (shoulder +-15-25 degrees over the blow), the shield stays between the body and the target
within 30 degrees, the elbow flexes 70-110. It is never frozen: at least +-8 degrees of motion in every frame of every
blow. On a parry it keeps its own spring (`_jolt`).

### 4.5 Footwork

Step into every blow: front-foot lunge 0.30-0.45 m for the forehand, 0.20-0.30 for the backhand, 0.20 plus a stomp for the
overhead, 0.50 for the heavy; the foot lands on I (+-1 frame, `step` event); the rear foot pivots on its toe; the feet
are planted after landing (no slide above 2 cm); the knees bend 15-25 degrees at impact. When a blow starts in
motion the legs keep running (the gait is layered under the action: the `_layer_lower` path) and the step lands on the stride.

### 4.6 Head, neck, cape

The head leads the turn by 1-2 frames toward the target in the wind-up and faces it at impact, pitch within +-5 degrees
(the neck compensates the chest's lean); cape and crest are cloth: author nothing, but keep the arms out of the cloth
(clip checker, cape to arm and shield lines).

### 4.7 The baseline, so step 2 knows what it has to beat (measured on the live game, attack1 / attack2 / attack3 / heavy)

| metric | baseline | target |
|---|---|---|
| peak order (frames from impact): hips, chest, shoulder, elbow, wrist | attack1: -0.65, -0.65, -2.9, -0.15, -4.15 (the wrist peaks 3.5 frames **before** the hips) | hips first, wrist last |
| chain violations | 2 / 1 / 2 / 2 | 0 |
| hips-to-wrist spread (frames) | -3.5 / -2.75 / -1.5 / -3.0 | 2 to 9 |
| pelvis peak speed (rad/s) | 5.2 / 5.3 / 4.4 / 23.9 | 6 to 14 |
| chest peak over pelvis peak | 4.4 / 3.8 / 3.7 / 1.2 | 1 to 3 |
| blade-tip peak speed (m/s) | 105 / 51 / 122 / 104 | at most 30 |
| elbow maximum (deg) | 149 / 95 / 151 / 80 | at most 150 |
| wrist extension range (deg) | -68..+72 / -68..+85 / -108..+66 / -155..+127 | -60..+70 |
| blade-to-forearm angle, minimum (deg) | 12.9 / 16.9 / 16.4 / 3.9 (the blade runs along the forearm: the kinked wrist) | at least 28 |

(The 105 m/s of attack1 is at t = 0.067 s, the blend from the ready pose into the first key: the shoulder turns at 365
rad/s there. Around the impact the chest turns at 23 rad/s while the hips turn at 5: the torso whips against still hips.)

### 4.8 How the blows were built, and what came out (step 2, done)

**From hand keys to joint angles.** The baseline blows were keyed hand and blade positions (`hr`, `hrb`, `hrk`) blended
linearly and solved by IK every frame: the blade direction flipped between nearly opposite keys, the wrist had no limit and
the body hardly turned, so the arm moved alone (4.7). Each blow is now a set of **joint-angle curves in degrees over the
action's own seconds**: the pelvis and the chest turn in the world (yaw, pitch, roll) and the pelvis moves (x, y, z); the sword
arm is a shoulder (plane of elevation `az`, elevation `e`, axial rotation `r`), an elbow (`el`) and a wrist (ulnar deviation
`uln`, which puts the blade `90 - uln` degrees off the forearm; extension `ext`; forearm twist `tw`); the head has yaw and pitch;
the shield arm is keyed where its wrist is, which way its elbow bends and where the shield faces, in the chest's frame. The
curves are monotone cubic Hermite through their keys (no overshoot between two keys, zero slope at a turning point).
`_bake_strike` samples them at 120 Hz into the ordinary pose arrays, so `sample_action`, the entry and exit blends and the
events treat a blow like any other action. Only the feet are made while the blow plays (below): they depend on how far the
hero lunges.

**Where the numbers come from.** `docs/anim_design/` (README.txt there; python 3 with numpy) is the single source. `defs.py`
holds each blow's body, head, shield and feet curves and the **key poses of the sword arm** (coil or apex, impact,
follow-through, recovery, ready). A key is not typed as angles: its world targets (where the grip is, which way the blade
points, which way its flat faces, where the elbow is) are fixed, with a few small "deltas" where a strip asked for another
place, and the seven joint angles that reach them with this blow's body are **solved** by a least-squares fit (`solve.py`;
`smodel.py` is the python model of the rig's arm, within 1-2 cm of the Godot one) under the wrist's limits (`uln <= 59.5`: the
blade is never closer than 30.5 degrees to the forearm; `ext` -45..45), the elbow's, a clearance of the arm from the torso (the
clip checker's capsules) and a small pull towards the first design's angles. The timing is then given **per joint group**:
the shoulder, the elbow and the wrist each get their own window to travel from one key to the next, the shoulder first and the
wrist last (attack1: shoulder 0.10-0.20 s, elbow 0.115-0.215, wrist 0.145-0.23), so that the peaks of angular speed come in
the order of the chain without anyone animating "a delay". `splice_strike.py` puts the generated data and the runtime
(`strike_block.gd.txt`) into `rig_heracles.gd` between `# >>> STRIKES BEGIN` and `# <<< STRIKES END`: edit the generator, never
the block.

**The four blows** (the action's own seconds; the events are unchanged, see "Combat" below):

* **attack1**, a forehand slash right to left (0.56 s, played at 1.05x). 0-0.10 s the coil: weight on the rear leg, pelvis 15
  degrees and chest 36 degrees turned away from the target (X-factor 21), pelvis 6 cm back and lower, the sword arm cocked high
  behind the head (elbow 108, wrist cocked), the shield arm tucked in front. 0.10-0.205 the release: the pelvis sweeps to +24
  degrees (9 rad/s, 3 frames before the impact), the chest to +41 (1.7 times as fast), then the shoulder, the elbow and the
  wrist; the blade crosses from 60 degrees right (2.0 m high, still raised) through 16 degrees left at the impact (1.36 m, nearly
  flat) to 44 degrees left at the end of the active window (1.0 m). At the impact the pelvis is 17 cm forward and 14 cm lower,
  the front foot has stepped 0.42 m (0.03-0.20 s) and stands. 0.205-0.34 the follow-through: the chest overshoots to +52 and
  the pelvis to +31, the head (+17 degrees, peaking one frame after the impact) trails the chest. 0.38-0.53 the front foot
  steps back and the arm returns to the ready pose along a lower path.
* **attack2**, a backhand left to right, a little lower (0.56 s, 1.05x). It starts from the left-turned body that attack1's
  follow-through leaves (pelvis +22, chest +40) and the hips drive the other way: pelvis to -21 (10 rad/s), chest to -36 then
  -54; the blade goes from 30 degrees left (1.45 m) through 47 degrees right at the impact (1.18 m) to 85 degrees right
  (0.96 m). The rear (right) foot steps 0.30 m forward and lands on the impact (the left one gathers first when the blow
  follows attack1).
* **attack3**, the finisher (0.80 s): 0-0.265 the longest anticipation: the sword goes up over the head (apex at 0.125 s, blade
  1.8 m high), the chest leans back 18 degrees, the right foot gathers and the left one steps 0.58 m (0.10-0.345, lifted 16 cm,
  heel strike on the impact); 0.265-0.345 the cut, a diagonal from the upper right (32 degrees right, 1.8 m) down to the
  centre line (0.40 m high, the blade 53 degrees down) with the chest bent 30 degrees forward, the pelvis 24 cm forward and 24
  cm lower: a lunge; 0.345-0.50 the hold on the impact (the pose stays, the cape and the shield arm keep moving); then the
  recovery step (the front foot back, 0.58-0.77) and the arm comes up and back along another path.
* **heavy** (1.0 s): the charge cue is kept (the pose at 0.3 s is the coil, held while the button is; the hold and the
  tremble are the game's; the hero plays the charge with the legs on the locomotion, and the held coil is layered like a blow
  on the run so that the chest keeps the 62 degrees it was authored with: the base's `_layer_lower` had taken half of the
  pelvis' turn from the gait, 44 degrees, a weaker wind-up); the release is a **whole-body spin** (the `rot` channel: 360 degrees about the ball of the left
  foot between 0.30 and 0.72 s, fastest from 0.36 to 0.56, slowing into the step) with the sword arm out sweeping the circle
  through the active window 0.37-0.68, ending in the deep step (the right foot lands at 0.72 s, pelvis 26 cm lower and 24 cm
  forward, chest bent 26 degrees) and the diagonal slam, held 0.78-0.85 before the recovery step.

**The chain, measured** (`anim_check mode=strike`, 120 Hz, standing; frames at 30 fps from the impact event, negative is before):

| blow | hips | chest | shoulder | elbow | wrist | blade tip | spread hips to wrist |
|---|---|---|---|---|---|---|---|
| attack1 | -3.0 | -2.0 | -1.4 | -0.9 | -0.6 | -1.4 | 2.4 f |
| attack2 | -3.1 | -2.3 | -1.5 | -1.0 | -0.5 | -1.3 | 2.6 f |
| attack3 | -4.9 | -2.6 | -3.1 | -2.4 | -0.6 | -2.4 | 4.3 f |
| heavy | -3.4 | -3.4 | -1.1 | -0.9 | +0.2 | +0.2 | 3.5 f |

(Attack3's shoulder peaks half a frame before its chest, inside the frame the check allows; the heavy's hips and chest peak
together because the whole body spins as one.)

**Wrist and blade.** The authored poses keep the blade 30.5 degrees or more off the forearm (measured 29.5-29.6 by the bone
measure) with the wrist's extension inside -57..+8 degrees; the forearm twists through the cut so that the edge leads (each
key fixes where the blade's flat faces). A blend into a blow (from a run, the guard, the blow before) is a straight mix of two
poses and can dip under the limit for a frame or two, so while a blow plays and for 0.4 s after it (while it blends out)
`_solve` turns a hand that is closer than 29.5 degrees to the forearm's line away from it (`_wrist_limit`, a degree or two,
only in those frames).

**Shield arm.** Curves of the wrist's position, the elbow's side and the shield's facing, in the chest's frame, from the clean
keys of the first design: it swings out as the sword arm goes back and tucks in as the blade comes through, 33-43 degrees of
motion over a light blow and 120 over the heavy, never still (at most 1.2 % of the frames turn it by less than 0.06 rad/s;
the check allows 10 %). The first version aimed the shield in the world and its rim, which reaches 0.2 m behind the elbow,
swung into the belly (the clip checker found 568 items in the four blows): in the chest's frame it travels with the chest.

**Footwork** (`_strike_feet`, while a blow plays). Both feet are in the world (the gait's own foot state), so the pelvis
travels over feet that stay put. A blow's plan has `moves` (one foot swings from where it stands to a spot, in the rig's
frame, between two times: with an apex height and a landing pitch; a gather move whose spot the foot already stands on is
skipped, so a blow started from its own stance does not hop on the spot while one chained out of another gathers its feet),
the planted foot's pitch (heel up, toe down) and how much of the pelvis' yaw it turns with (it pivots), and a **recovery
step** at the end (the front foot back) so that the gait takes over with the feet where it wants them. After the pelvis is
placed (`_pelvis_limit`) every ankle is clamped to what its leg can reach: a lunge longer than the stance drags the foot on its
toe instead of over-extending the leg (the checker's `unreach_pct`). The heavy's feet are in its pose (`"mode": "baked"`): the
spin turns the whole body about the toe contact of the left foot (the ankle's height and pitch make the sole exact: -4.6 mm
at worst), the free foot is tucked and carried round (its ankle 19 cm above the standing height: a first version with 31 cm looked like a pirouette) and lands at 0.72 s.

**A blow on the run.** `HeroMelee._begin` tells the rig, right after it has aimed the blow, whether the run is carried on:
`rig.set_strike_run(_carry != Vector3.ZERO)`. With no foe in reach a run faster than 3 m/s goes on and slows at 13 m/s^2; the
blow is then **layered over the gait** (`_strike_layer`): the legs and the pelvis' translation come from the gait (the stride
goes on under the swing and stops the way a run stops), the chest, head and arms and 90 % of the pelvis' yaw are the blow's, and
the chest keeps the orientation the blow gave it in the world. With a foe in reach the hero stops dead and lunges (up to
15 m/s for 0.14 s, HeroMelee's sine ease-out): no gait can follow that (tried: both feet 30 cm in the air for a quarter of a
second and a quarter of the ankle targets out of reach), so the blow plants its own feet as from a standstill. Callers that do
not say (tools) get a guess from the speed in `play()` (faster than 2.5 m/s: layered).

**Combat.** Unchanged and checked: every action's length and its `swing`, `impact` and `step` event times (length / swing / impact
/ steps: attack1 0.56 / 0.13 / 0.205 / 0.2, 0.53; attack2 0.56 / 0.12 / 0.20 / 0.2, 0.52; attack3 0.80 / 0.27 / 0.345 / 0.345, 0.72;
heavy 1.00 / 0.36 / 0.47 / 0.4, 0.72; the `impact` event is within 0.04-0.15 frame of the authored time), the entry blends
(0.06-0.07 s; the heavy's is 0.06 now, 0.10 before: the release blended the held pose into the spin and doubled the pelvis' speed)
and the exits (0.22-0.25 s). `hero.gd` is untouched and `hero_melee.gd` has **one line added** (in `_begin`, the `set_strike_run` call
above); no combat number changed. The blade sweeps the same hit arc in the active windows as the first design: the same azimuth
bins as the live blows (tip + 0.12 m and the 60 % point, 0.75-1.9 m from the hero, which is what the hit test's band can
touch) are covered 100 % by attack1, attack3 and the heavy and 92 % by attack2 (12 of 13: the bin at 90 degrees right, the
hero's own side; its backhand now ends at 85). The arcs are not the old ones (attack1 sweeps from 60 degrees right to 44 left,
the old one only 50 to 0 left; attack3 comes down on the centre line), they cover them. **The heavy deviates from the brief in
one way: it is a 360-degree whirlwind that ends in the diagonal slam**, not a slam alone, because the live heavy's hit
window (0.37-0.68 s) strikes every direction around the hero (36 bins) and that is a combat fact the animation keeps.

**Before and after** (`anim_check mode=strike`, the same tool on the step-1 rig with the old blows and on this one, 68 checks
each: **35 failed before, 0 now**; `logs/anim_s2_strike_BEFORE.txt`, `logs/anim_s2_strike.txt`):

| metric | attack1 | attack2 | attack3 | heavy | target |
|---|---|---|---|---|---|
| chain violations | 2 to 0 | 1 to 0 | 2 to 0 | 1 to 0 | 0 |
| hips to wrist spread (frames) | -2.1 to +2.4 | 0.0 to +2.6 | -1.5 to +4.3 | -2.8 to +3.5 | 2-9 |
| pelvis peak (rad/s) | 5.5 to 9.1 | 5.5 to 10.4 | 4.4 to 7.2 | 23.9 to 25.3 | 6-14 (heavy 8-28) |
| chest over pelvis | 4.4 to 1.7 | 3.8 to 1.5 | 3.7 to 1.4 | 1.4 to 1.1 | 1-3 |
| blade-tip peak, from the entry blend on (m/s) | 52 to 29 | 38 to 25 | 85 to 28 | 104 to 37 | 30 (heavy 40) |
| elbow maximum (deg) | 151 to 129 | 95 to 95 | 150 to 91 | 80 to 104 | 150 |
| wrist extension (deg) | -75..+42 to -57..0 | -68..+85 to -49..-2 | -111..+66 to -46..-3 | -153..+127 to -52..+8 | -60..+70 |
| blade to forearm, minimum (deg) | 12.8 to 29.6 | 17.3 to 29.5 | 16.4 to 29.5 | 3.9 to 36.5 | 28 |
| planted-foot slide (cm) | 4.3 to 0.1 | 13.6 to 0.1 | 15.6 to 0.04 | 0.0 to 1.3 | 2 |
| shield arm still (% of frames) | 1.9 to 0 | 18.5 to 0 | 2.6 to 0 | 33.7 to 1.2 | 10 |
| hit-arc bins covered of the first design's (%) | 100 | 92 | 100 | 100 | 85 |

Also checked and passing: no sole under the ground (-4.6 mm at worst, the heavy), no unreachable ankle (0 %), no frame jerk in
the hand's, tip's and pelvis' paths (the old attack3 had one), with the lunge at 0.8, 1.4 and 2.0 m, on a carried run at 3.2 and 5.5
m/s, on a run into a lunge of 1.2 m, the three blows chained (`mode=combo`), played at 30 and 24 Hz (feet only), the arena bot
at 60 and 24 fps (16 of 16), `wheat_walk` (walk and run), a clip check of every action (863 items before, 679-686 now, it varies with the random start of the cloth; the
four blows 42 before: arm into torso in attack1/2/heavy, the shield's cloth; now only cloth is left, the heavy's cape against
its shield and arm, as in the baseline). `advance()` costs the same in a blow as standing (1.1-1.3 ms); the one-time compile of
the actions at the first rig takes 48 ms (3 ms before): the baking of the four blows.

**Known limits.** (1) The entry into a blow is a 0.06-0.07 s mix of whatever the hero was doing and the first pose (two frames at 30
fps; the blade tip crosses it at 40-52 m/s): the live blows' first active frame is at 0.115-0.125 s, so a wind-up cannot be
longer without moving the hit window. (2) A lunge (up to 2 m in 0.14-0.3 s) outruns any foot: the feet drag a few cm on their toes
(the check allows 10 cm); attack3 from a 6 m/s run into a 2 m lunge drags the rear foot 23 cm, the only case above it. (3) A stop
and lunge throws the cape over the shoulders (cloth, not authored). (4) The cape against the heavy's shield (4.5 cm) and arm
(3-6 cm) during the spin is the cloth's, as in the baseline; depending on the cloth's random start it also reaches 2-8 cm into the pelvis or the left thigh for a frame or two at the start of the spin. (5) Blows started in the air (the zip strike), the water or a roll
were probed for NaNs and wild steps only (none), not judged on strips. (6) attack2 misses one of the old 13 arc bins.

### 4.9 The moveset for the long blade (2026-10-17)

The blows of 4.8 were replaced by a moveset for the 0.98 m blade, built on the client's reference poses: combo A (a1
diagonal forehand, a2 rising backhand, a3 wide horizontal forehand, a4 a stepping overhead chop that ends with the blade
struck into the ground), combo B (b1 rising diagonal out of the low carry, b2 descending backhand, b3 a lunging thrust),
the dash attack (a leaping overhead slash out of a sprint, landing in the ground-strike pose) and the heavy (the charged
spin, rebuilt). Numbers, routing and feel are in docs/COMBAT.md 3.2. `attack1`/`attack2`/`attack3` remain as aliases of
a1/a2/a4 (`STRIKE_ALIAS`).

**What was taken from the references.** From the client's screenshots, two poses: P5 (low and wide, the blade held back:
the heavy's coil) and P8 (the blade struck into the ground at the end of a chop: the end of a4 and of the dash). From the
study notes: each blow in its own plane with the edge leading; the follow-through carrying the tip across and behind; the
leap-and-plant finisher (a4), the piercing thrust (b3), the leap out of the run (dash) and a low, level spin (heavy). The
timing is slow wind-up (the last frames nearly still), a fast cut of 3-4 frames, a short hold, then a slow settle; the
wind-up of a chained blow sits inside the previous follow-through.

**How they were made** (`docs/anim_design/moveset.py`, python + numpy; `mview.py` draws quick stick-figure strips):

* Each blow has a **cut plane**, a great circle round the moving right shoulder through two directions. The blade turns
  about the plane's normal and its flat is that normal, so the edge leads. The keys give the time, the grip's place on
  the plane (angle and reach from the shoulder) and the blade's angle on it.
* **Which edge leads** (`back`). With the true edge (-1), the back of the hand faces -n and the blade lags the forearm
  by 30-88 degrees. With the false edge (+1), the blade runs ahead of the forearm. A forehand turned over into a
  backhand in 3 frames would need about 240 degrees of forearm twist, and the forearm has 110 either way of thumb-up. So
  the second blow of each pair is the **pendulum** back along the same plane on the false edge: a2 after a1, b2 after
  b1, with no turnover of the hand. a3 is palm down: a palm-up horizontal forehand is out of reach with the wrist's
  30.5-degree limit. b3 is a thumb-up thrust with the blade 18 degrees up: a thrust in the forearm's line cannot be held
  at that limit.
* The flat is a **roll angle** about the blade, interpolated between the keys. A slerp of the flat vectors flipped by
  73 degrees in one sample.
* **Dense IK**: every 1/120 s the seven arm angles are solved by least squares, starting from and pulled towards the
  previous sample. The limits are `uln` <= 59.5, `tw` +-110, `ext` +-60, `el` 8-140 and `r` -95..100. The solve also
  keeps the blade clear of the torso and the thighs, and the tip at least 0.12 m over the ground (except the two chops
  into it). Where that continuation would jump to another branch (a3's wind-up, b3's thrust, the turnovers of the
  recoveries), the segment is **joint-space** (`js=True`): the angles go straight from one solved key to the next
  (`solve_key`, multi-start).
* **Chained blows start on the exact pose of the blow before at its `open` time** (`chain_from`), so a buffered press
  flows into the next blow with no blend jump. a1, b1 and the dash start from the armed **carry**, the pose (`X_CARRY`)
  that every blow's recovery returns to. Body, head and shield curves and the feet plans are authored per blow; the dash
  and the heavy have their feet baked into the pose (`"mode": "baked"`) and never run on the gait (`_strike_own_legs`).
* The heavy keeps its charge: the pose at 0.30 s is the coil, held while the button is. Standing, the held coil now keeps
  its own low, wide stance (`_strike_layer` with `own` legs); on the charge walk the legs blend to the gait. The release
  is a whole-body `rot` of 360 degrees about the right foot between 0.30 and 0.72 s, with the blade level and out at
  arm's length.
* Export: 60 Hz samples plus the keys into `strike_data.gd.txt`, then `splice_strike.py` puts it into the rig between the
  STRIKES markers. Edit the generator and splice; never edit the block.

**Checked**: the python check of every blow (lowest tip, blade-to-body clearance, the edge leading through the active
window, the flat's roll rate, joint steps); Godot strips of every blow alone and of the strings chained
(`tools/strike_strips.sh`; `preview_heracles.gd` row `chain:a1,a2,a3,a4[:speed]` plays each blow from the previous one's
`open`); the other armed actions for the long blade (dodge, pull, death, hit_heavy were re-keyed where the blade
touched the ground or the body); the arena bot at 60 fps (19/19).

**Known limits.** (1) b1 crosses his front high (tip 1.8 m up): a low beast in front is still hit (the hit band reaches
0.9 m under the blade), but against wolves the cut reads high. (2) The cuts are fast: the tip peaks at 90-145 m/s for 2-3
frames (the thrust 45, the spin 66). The 30 m/s ceiling of 4.2 and `anim_check mode=strike` was set for the old short
blows; the tool still measures attack1-3 by their old event times and was not re-based for the new blows. (3) The
recoveries go back to the carry along visible sweeps (a1 and a3 low across the front, b1 over the head). (4) A few holds
sit at a joint limit, so the follow-through stops short of the design (a1's blade ends 25 degrees down, not 35). (5) The
cape in the long lunges (b3, the dash) is cloth and not authored. (6) The armed carry and the draw are the STOW lane's.
The blows start and end on `X_CARRY`: grip at (0.346, 0.84, 0.081) in rig space, blade pointing back and down (azimuth
150, elevation -37), back of the hand towards the thigh. The carry and the draw must arrive at that pose.
(INTEGRATE dealt with (1), (3) for b1, part of (2) and (5), and (6): section 10.)

---

## 5. Looking at it (what to check on a strip)

`tools/anim_strips.sh <dir> [cols] [gaits...]` renders one PNG per gait: side, front and the gameplay camera, one cycle
across 8-12 columns. Look for, in this order: (1) the lean (the line from hip to neck, not the chest alone); (2) the flight
phase at a jog and a sprint, the contact foot reaching ahead; (3) the elbows at about 90 degrees and the opposition of
arms and legs; (4) the head level; (5) the blade never pointing at the thigh or the face and the wrist never kinked;
(6) the shield rim clear of the thigh; (7) in the gameplay row, that the legs and the free arm still read from behind.
The before/after sheets of this step: `shots/before/*`, `shots/after/*`, `shots/compare_side.png`.

For the blows: `tools/strike_strips.sh <dir> <action...>` renders one PNG per blow (env `COLS`, `T0`, `T1`, `VIEWS`, `TILE`,
`LUNGE` metres the hero lunges, `SPEED` m/s he runs when the blow starts); views `game`, `side`, `front`, `top`, `tq`, `close`,
`closeback` and `hand`, `handf`, `handb` (the camera follows the sword hand). Look for: (1) the legs: weight on the rear leg
in the coil, the front foot lands on the impact frame and stays, no skating; (2) the order: the pelvis has turned while the
arm is still back, the arm follows; (3) the hand's path is one arc, the blade never flips; (4) the wrist: the blade is
visibly off the forearm's line in every frame and the fingers wrap the grip; (5) the shield arm moves against the sword arm and
stays clear of the belly; (6) the head stays on the target; (7) the blows flow into each other (the end of one is the start
of the next). The sheets of this step are in `shots/s2/`: `compare/<blow>_before_after.png` (side, front and gameplay cameras, 12
frames, the step-1 rig above the new one), `f1` the four blows after, `before` the same before, `h2` and `h3` the sword hand,
`run5` and `run4` on a carried run and into a lunge, `arena2` and `arena3` the arena bot's combo and heavy (with its charge)
through the gameplay camera.

For every other action (step 3) the same script takes the action's name, `name:speed` and `loco:<m/s>` rows: `tools/strike_strips.sh <dir>
parry dodge hit throw loco:6.2` (or the `fns=sheet rows="parry@game;parry@side"` call of 8.6 for two rows). Look for, in this order:
(1) anticipation: the body prepares before the limb moves (the shield comes back and the chest winds before the parry's punch; the hips
drop before the roll; the head goes back a beat after the chest in a hit); (2) weight: the pelvis goes down into a landing, a stumble or a
pull and the knees take it; (3) the head is the last to arrive and the last to leave; (4) the first and the last frame are the gait's or
the guard's own pose (no frame where he is somewhere else), and the frames next to them move at the same speed as the ones inside the
action; (5) a held hand is on what it holds, the wrist straight, the shield out of his way. The sheets of this step are in
`shots/s3/final/` (`before/`, `after/` and `compare/<name>_before_after.png`: the live rig above, the new one below, gameplay camera
and side view, 12 frames each); `shots/s3/slack`, `shots/s3/zip` and `shots/s3/dodge` are close-ups of the throw's shield, the zip pose
and the roll.

---

## 6. Acceptance metrics (`tools/anim_check.tscn`)

```
godot --headless --path . res://tools/anim_check.tscn -- mode=loco|trans|strike|combo|ranges|pops|swap|perf|all [gaits=run,sprint] [fps=60]
      [csv=<abs dir>] [quiet=1] [popslog=1] [slidelog=1] [acts=attack1,heavy] [lunge=<m>] [carry=<m/s>] [strike_hz=120]
      [seq=<pops sequences>] [verbose=1] [calib=1] [dbg=<joint>,<t0>,<t1>]      (`all` is everything but perf)
```

It drives the rig the way the hero does (moves the node through the world, `set_locomotion`, `advance`), prints
`ANIM <group> <gait> <metric> <value> [lo .. hi] PASS|FAIL|info` per check and `ANIM summary checks=N fail=M`.
`tools/clip_check_heracles.tscn acts=<state,...> [verbose=1 dump=1]` is the intersection checker.

### 6.1 Steady gaits (`mode=loco`): the table the code checks

| metric | idle | walk | jog | sprint |
|---|---|---|---|---|
| `lean` trunk lean, hip to neck, deg | -3 .. 4 | 2 .. 7 | 8 .. 13 | 18 .. 25 |
| `bob_cm` pelvis peak to peak | 0 .. 2 | 1.5 .. 5 | 3 .. 9 | 3.5 .. 10 |
| `bob_harm` energy at 2x the cycle frequency over the cycle frequency | - | >= 1.5 | >= 1.5 | >= 1.5 |
| `pel_yaw_amp` pelvis yaw amplitude, deg | 0 .. 1.5 | 2.5 .. 6.5 | 5 .. 9.5 | 6.5 .. 11.5 |
| `chest_ratio` chest over pelvis yaw amplitude | - | 1 .. 3 | 1.1 .. 3 | 1.1 .. 3 |
| `chest_corr` correlation of pelvis and chest yaw | - | -1 .. -0.6 | -1 .. -0.6 | -1 .. -0.6 |
| `arm_amp` sword-arm shoulder swing +-, deg | - | 14 .. 32 | 28 .. 55 | 36 .. 65 |
| `arm_opp` correlation of the arm with its same-side leg | - | -1 .. -0.6 | -1 .. -0.6 | -1 .. -0.6 |
| `shield_amp` shield-arm swing +-, deg | - | 3 .. 16 | 5 .. 18 | 6 .. 20 |
| `elbow_mean` sword-arm elbow flexion, deg | - | 20 .. 60 | 80 .. 108 | 78 .. 105 |
| `knee_peak` swing-knee flexion, deg | - | 45 .. 80 | 85 .. 125 | 105 .. 140 |
| `head_pitch_p2p` head pitch peak to peak, deg | 0 .. 3 | 0 .. 3.5 | 0 .. 4 | 0 .. 5 |
| `head_yaw_p2p` head yaw peak to peak, deg | - | 0 .. 5 | 0 .. 6 | 0 .. 7 |
| `slide_cm` planted foot (heel or toe) travel while it is on the ground | 0 .. 1 | 0 .. 2 | 0 .. 2 | 0 .. 2 |
| `unreach_pct` frames whose ankle target the leg cannot reach (12 mm) | - | 0 .. 3 | 0 .. 3 | 0 .. 3 |
| `step_lag` `step` event to the real touchdown, s | - | 0 .. 0.05 | 0 .. 0.05 | 0 .. 0.05 |

Also checked in every gait: `sole_min_mm` (no heel or toe below the ground, -10 mm), `pops` (no frame jerk in the pelvis,
head, ankles, trunk angles, arm and leg joints, 0 allowed), `blade_up_max` (blade at most 52 degrees up), `blade_dn_max`
(at most 60 down), `blade_forearm_min` (the blade at least 28 degrees off the forearm's line, 6.3). The bone measure of the
wrist deviation is printed as info. Speeds between the gaits (1.0, 1.6, 3.5, 4.5, 5.2, 7.5 m/s): slide, sole, pops,
unreachable ankles. Extras (strafe right and left at 2.2, back-pedal at 1.8, guard walk at 2.6, a locked-on run at 5.0):
slide <= 2 cm, sole, no pops, feet at least 10 cm apart (a strafing foot never crosses the other leg).

### 6.2 Transitions (`mode=trans`)

| case | checked |
|---|---|
| start (idle to 6.2 m/s) | slide <= 5 cm, pops <= 2 (0 measured), the first step within 0.45 s (0.15-0.20 measured), lean overshoot 1-14 degrees, steady lean 8-13 |
| stop (6.2 to 0 m/s) | slide <= 5 cm, no pops, lean back to -4..5, both feet on the ground, side by side |
| turn 90 degrees in 0.25 s, turn 180 degrees in 0.4 s at 6.2 m/s | slide <= 6 cm, pops <= 1 (<= 2), roll into the turn 1.5-14 degrees (head lead is reported) |
| gait change (2.2 to 6.2 to 9.0 to 2.2 to 6.2) | slide <= 6 cm, pops <= 2, no foot more than 4 cm short of its target |
| stutter (six short stops and starts) | slide <= 6 cm, pops <= 6, no foot more than 6 cm short |
| jump while running (and from standing) | pops <= 3, foot at most 4 cm short of its target after landing, slide <= 6 cm |

The start is 0 to 6.2 m/s in 0.15 s and the 180 is 7.8 rad/s at full speed: not what a body does, so up to two
single-frame events (a foot's toe-off pitch, a 3 cm pelvis dip) are let through there; steady gaits allow none.

### 6.3 Joint ranges (every pose of every action, `mode=ranges` and in the gaits)

Elbow 0-150 degrees. Wrist extension (hand rotation about the blade axis, measured from the forearm bone in the rest
frame) -60..+70. Wrist deviation is **reported**, not failed: the rest-frame measure carries a fixed 12-degree bias and a
swing-dependent term from the forearm's own twist, so the physical rule for the sword hand is "the blade is at least 28
degrees away from the forearm's line" (an oblique grip gives 25 degrees for free and ulnar deviation 35, so a hand cannot
point the tool closer than 90 - 60 = 30). The gait clamps it (ulnar 30-60 degrees, 28 degrees measured); the same angle is checked in the strikes
and reported for every action.

State after step 3 (`mode=ranges`, 72 checks: three per action): **all elbow checks pass** (the solver folds the elbow softly towards 150
degrees, 8.2) and 67 of 72 pass; the five that fail are the sword hand's wrist extension in `dodge` (2), `don_skin` (2) and `pull` (8.8).
The step-2 state was 22 failing (18 wrist, 4 elbow). The blade-to-forearm angle of the other actions is reported only (8.8). The
tool plays the wrestle's start into its strain loop (`grapple_start` is never left to the gait in the game: its own out-blend, in
which the hand flies from the beast's neck to the side in 0.15 s, was being measured as if it were).

### 6.4 Strikes (`mode=strike` and `mode=combo`: green; spec in section 4, built as in 4.8)

Each blow is played the way HeroMelee plays it (the hero's lunge as a sine ease-out from 0.02 s to the first active frame,
`set_locomotion` fed every step, the heavy charged and held at 0.3 s and then released) and sampled at 120 Hz:

* the chain: the peak of angular speed of hips, chest, shoulder, elbow and wrist in the window from 0.2 s before the impact
  (not before the entry blend is over; the heavy: from the release) to 0.05 s after it: `chain_violations` 0 (a link may peak at
  most 1 frame before the one under it), `chain_spread_f` 2-9 frames, `hips_peak_rads` 6-14 (heavy 8-28), `chest_over_hips`
  1-3, `tip_peak_ms` 0-30 (heavy 40; the blade's own speed, the hero's travel taken out);
* the hand: `elbow_max` 0-150, wrist extension -60..+70, `blade_forearm_min` >= 28 degrees, `path_pops` 0 (no frame jerk in the
  tip's, hand's and pelvis' paths), `impact_event_err_f` <= 1 (the `impact` event within a frame of the authored time);
* the hit arc: `arc_covered_of_old_pct` >= 85 (azimuth bins of 10 degrees swept by the tip + 0.12 m and the 60 % point of the
  blade in the active window, 0.75-1.9 m from the hero, against the live blows': `OLD_COVER`);
* the feet: `sole_min_mm` >= -10, `slide_cm` <= 2 (<= 10 in a lunge) for a planted heel or toe, `unreach_pct` <= 3 (ankle targets
  the leg cannot reach, 15 mm);
* the shield arm: `shield_range_deg` >= 16 (the upper arm's direction in the chest's frame) and `shield_still_pct` <= 10.

`lunge=<m>` moves the hero along HeroMelee's lunge (0.8 and 1.4 are usual, 2.0 the most, locked on); `carry=<m/s>` runs him up to that
speed first and plays the blow on the run (no foe: the run carries on and slows at 13 m/s^2; together with `lunge`: a foe in
reach, the run is cut and the lunge takes over); `strike_hz=60|30|24` plays the blow at a game frame rate (the chain and arc
metrics are made for 120: look at the feet then); `acts=`; `csv=` dumps the series. `mode=combo` chains attack1, attack2 and
attack3 the way HeroMelee does (the next blow starts in the follow-through at its `open` time): no pops in the paths, no sole
under the ground, no unreachable ankle, slide <= 2 cm (<= 8 with `lunge=0.4`). The baseline is `logs/anim_s2_strike_BEFORE.txt`.

### 6.5 Before and after (measured with this tool on the live copy and on the new rig)

| metric | before | after | target |
|---|---|---|---|
| run lean (deg) | 0.1 | 9.2 | 8-13 |
| sprint lean (deg) | 7.2 | 19.5 | 18-25 |
| walk lean (deg) | -2.1 | 2.5 | 2-7 |
| walk / jog / sprint chest counter-rotation ratio | 0.60 / 0.60 / 0.62 | 1.2 / 1.6 / 1.9 | 1.0-3.0 |
| foot slide, walk / jog / sprint (cm per planted foot) | 54 / 9.0 / 2.5 | 1.0 / 0.4 / 0.1 | <= 2 |
| strafe / back-pedal / guard walk / locked run slide (cm) | 29 / 179 / 39 / 13 | <= 1.6 | <= 2 |
| unreachable ankle targets, walk / jog / sprint | 25 / 19 / 29 % | 0 / 0 / 0 % | <= 3 % |
| `step` event lag at a walk (s) | 0.15 | 0.00 | <= 0.05 |
| shield-arm swing at a jog / sprint (deg) | 19 / 31 | 9.9 / 12.8 | 5-18 / 6-20 |
| loco checks failing | 27 of 123 | **0 of 143** (the speeds between the gaits are in; step 1's text said 147, the tool has always printed 143) | 0 |
| transition checks failing | 15 of 27 | **0 of 27** | 0 |
| locomotion clip issues (962 samples) | 74 (worst 4.5 cm) | 0-3 (worst 1.0 cm, cape in the air pose) | baseline or better |
| strike checks failing (`mode=strike`, 68 per run; 4.8 has the table) | 35 of 68 | **0 of 68** (and 0 with a lunge of 0.8 / 1.4 / 2.0, on a run of 3.2 / 5.5 m/s, on a run into a lunge) | 0 |
| clip issues, all actions (2602 samples; the four blows) | 863 (42) | 679-686 (0-1 outside the heavy's cloth) | baseline or better |
| `advance()` cost (idle / walk / jog / sprint, us; two passes each on a shared 4-core machine) | 1390 / 1190 / 1600 / 1300 and 1290 / 1300 / 1300 / 1270 | 1420 / 1260 / 1330 / 1390 and 1280 / 1240 / 1380 / 1440 | no worse (it is noise: 1.2-1.6 ms either way, the cloth dominates) |

### 6.6 The spear's swap and what `advance()` costs (`mode=swap`, `mode=perf`)

`mode=swap` (12 checks) holds the throw at its grab (`THROW_GRAB`) and the catch at its stow (`CATCH_STOW`), in both outfits, and
compares the spear in the fist with the one on the back at that frame. The two are two models that change places there, so
they must be the same spear: the fist on the shaft's place (<= 2 cm), the same axis (<= 3 degrees) and the same roll about it
(<= 6 degrees: the leaf head's broad side). Measured (helmet / lion): 0.4 / 0.6 cm, 1.5 / 0.7 degrees, 0.1 / 0.7 degrees. The
roll that makes it exact is baked into the back spear's frame (`SPEAR_ROLL`, `SPEAR_ROLL_LION`), not into a blend.

`mode=perf` prints the mean and the worst cost of one `advance(1/60)` (headless: the rig's own solve and cloth, no drawing)
standing, jogging, sprinting, in a blow, a throw, a roll, a hit and in the air. It is there to see orders of magnitude on a shared
4-core machine, not decimals: the mean is 1.03-1.39 ms in every one of those states (two passes), the worst frame 2-5 ms (the first time an action is compiled in a process costs one frame of about 40 ms). The rig as it was before the inertialized blends measured 1.01-1.27 ms: no measurable change.

### 6.7 Pops: every state change, joint by joint (`mode=pops`)

The gaits and the blows were measured by their own rules (6.1-6.4). What nothing measured was what happens *between*
motions: the frame in which a roll starts, a hit that lands in the middle of a blow, the guard going up out of a recovery,
a jump landing into a run. `mode=pops` plays 67 scripted sequences with the calls the hero makes (`play`, `play_at(.., upper)`,
`stop_action`, `set_guard`, `set_motion_state`, `set_locomotion` every tick, the roll's displacement curve, the knock-back of a
hit) and records every frame of every joint:

* idle, walk, run and sprint into and out of each other, a turn, strafing with the guard up;
* a blow from a run and a sprint (stuck to, and left), from a lunge, the combo (`combo123_idle`, `combo12_run`), a blow into the guard
  (`strike_guard`, `strike3_guard`), the heavy's charge and release;
* guard, parry (into the guard and into a walk), a blow met on the shield;
* the roll from a jog, a sprint, standing, twice in a row, into a blow, into the guard; the back step;
* a jump from standing, a jog, a sprint; a hard fall; a jump into a roll; a fall into a run;
* a light and a heavy hit while standing, running, sprinting, guarding, in a blow, in the air, at the end of a roll;
* the throw (standing, running, with the catch, with the pull), the pull, the recoil;
* the wrestle, interact (standing and walking), pet, don_skin, victory, death (standing, running, in a blow);
* the brush (walking, guarding), swimming in and out, the zip into the hang and the drop, the zip into the climb.

Per sequence there are four checks, each a *ratio to a limit*:

| metric | what is compared with its limit |
|---|---|
| `joint_rate_ratio` | the fastest any of 17 joints turns relative to its parent (rad/s). The whole-body spin of a roll is a joint of its own (`body`), so a roll is not "a fast shoulder" |
| `joint_snap_ratio` | the sharpest change of a joint's rate from one frame to the next (rad/s^2): a joint that goes from rest to its limit in a few frames |
| `point_speed_ratio` | the fastest of 6 tracked points (the two hands, the two feet, the blade tip, the head; in the rig's own frame, so the hero's travel and a roll's spin are out) |
| `point_snap_ratio` | the same for their acceleration |

The limits (`PJ` and `PP` in the tool) are what the known-good motion does: `calib=1` plays the four steady gaits and the four
authored blows and prints the fastest and the sharpest every joint and point is in them, and a limit is never below 1.3 times that
for the legs and the left arm. The trunk, the neck and the head, which those clips hardly move, are given the speed a hit may whip
them at (15-25 rad/s). The sword arm is held to what a blow does to it, and the interior of a blow (from 0.08 s into attack1/2/3
and the heavy to its end) is not judged here (`mode=strike` does: the chain, the arcs, the tip speed); its entry and its exit are.

| joint | rate limit rad/s | snap limit rad/s^2 | joint | rate | snap |
|---|---|---|---|---|---|
| pelvis | 32 | 1900 | hip (each) | 40 | 1500 |
| spine | 15 | 600 | knee (each) | 45 | 2100 |
| chest | 20 | 600 | ankle (each) | 45 | 1500 |
| neck | 20 | 600 | shoulder, right / left | 40 / 35 | 1800 |
| head | 25 | 900 | elbow, right / left | 40 / 35 | 1700 / 1500 |
| wrist (each) | 40 | 1400 | whole body (`body`) | 26 | 1500 |

Points: hand r / l 30 / 25 m/s (1500 / 1200 m/s^2), foot 20 (900), blade tip 45 (2700), head 12 (900).

A ratio up to **1.0** is no faster than the good motion. Between 1.0 and `POP_CEIL` (**1.5**) it is an authored explosive motion
(a throw's whip, a roll's first frames, a hit's snap back, the entry of a blow from another pose): it passes, is printed as a
`POPS` line with the joint and the time, and is explained below. Above 1.5 it is a **pop** and fails (1.5 times a limit is twice
what the gaits and blows do). `seq=<names>` runs some sequences, `verbose=1` prints every joint, `dbg=<joint>,<t0>,<t1>` the frames
of one joint, `calib=1` the calibration, `csv=<dir>` the series.

What the first run found, on the rig as step 2 left it (the 174 failing checks of 268 below): the shield forearm turned half a
turn in one frame whenever the arm crossed its pole (attack1 at 0.33 s, the dodge, the jump, the hits); every change of motion froze
the joints that were moving (the old blend mixed a snapshot of the old pose into the new one: a snap in all of them at the start of
every action); the sword turned over in the roll's first frames; a hit that landed in a run or a blow started with a snap in every joint; the guard arrived on a ramp and
stopped dead. 6.8 and section 8
are the fixes.

**Result: 0 of 268 failing.** 33 sequences are within 1.0 on all four metrics; 34 sequences have 64 metrics between 1.0 and 1.5. By
cause (worst ratio):

| cause | sequences | worst |
|---|---|---|
| the throw's draw and whip: the left wrist goes from the shield grip to the spear on his back in 0.20 s (rate, t = 0.15 s) and opens at the release (0.58 s) | `throw_idle`, `throw_run`, `throw_catch_run`, `throw_idle_then_pull` | wrist_l rate 1.50, snap 1.39 |
| the first 0.08 s of a blow: the coil of the authored blow is more violent than the steady limits, and it starts from a run or a guard | `sprint_attack1_*`, `run_attack1_*`, `strike3_guard`, `idle_attack1_lunge`, `combo123_idle`, `strike_guard`, `hit_in_attack`, `hit_heavy_in_attack`, `recoil`, `death_in_attack` | shoulder_r rate 1.39, elbow_r snap 1.40 |
| the end of a roll: the foot lands and the run's stride takes over at its own speed | `sprint_roll_sprint`, `jump_roll` | foot_r snap 1.43, ankle_r snap 1.36 |
| the roll's tumble and start (head whipped as the body dives; the sword hand in mid-tumble) | `idle_roll_idle`, `run_roll_run`, `jump_roll`, ... | head speed 1.24, wrist_r rate 1.03 |
| zip into climb: the sword hand turns blade-up in 0.07 s | `zip_climb_idle` | wrist_r rate 1.35 |
| the pelt swung over the shoulders (the left elbow whips as it goes on) | `don_skin` | elbow_l snap 1.33 |
| the wrestle's shove (the hands let go) | `grapple` | wrist_r snap 1.27 |
| the blade flung up and back by design | `recoil` | tip speed 1.26 |
| a hit at the end of a roll, the landing's give | `hit_in_roll_end`, `jump_sprint`, `fall_hard_land*` | knee_r / ankle_r snap 1.24 |
| a hit's head whip and arms | `hit_*`, `hit_heavy_*` | head speed 1.17, elbow_l snap 1.19 |
| the sprint's own stride | `idle_sprint_idle` and everything that starts from a sprint | knee_l snap 1.09 |

### 6.8 Inertialized transitions

A change of source (an action starts or ends, the motion state changes, a blow hands over to the guard) used to mix a frozen
snapshot of the old pose into the new one over the blend time. Every joint that was moving stopped dead on the first frame of the
blend (a snap in all of them) and the new pose arrived with no memory of the old motion. That is the largest single cause of the
174 failing checks. Now the old motion goes on (inertialization, Bollinger, GDC 2018): on the first frame of the new source the
difference between where the old pose was heading and the new source's pose, and the difference of their velocities, are kept as
an offset per channel, and the offset dies away along a cubic Hermite curve (zero value and zero slope at the end of the
blend). The pose and its velocity are continuous through every transition, however fast the joints were moving
(`_blend_out`, `_src_before`, `_io_*` in `rig_heracles.gd`).

* **Lanes.** Everything above the hips dies away over the blend's own length (the action's `in` / `out`). The hands' numbers, the
  weights that say which space they are in (`hls`, `hrs`) and every *direction* (the blade, the back of the hand, the elbow poles,
  the shield's facing: `IO_DIRS`) take a slower lane: a direction can be half a turn off the new pose's, and it takes longer to come
  round than a position to arrive (its length is 1.5 times the angle it has to turn over `DIR_RATE` 22 rad/s, but at least 1.8 blends
  and 0.09 s, and at most 0.32 s). An action can say `"dlen": s` for a longer minimum (the roll's first frames turn the sword over: 0.26 s) or `"fast":
  true` for the quick lane (the throw's grab: the hand must be on the spear on time).
* **Directions are rotated, not subtracted.** The offset of a direction is the rotation from where the old one was to the new
  one, taken the short way round (`IO_DIRS`, `_dir_rot`). A vector difference between two nearly opposite directions (the blade up,
  the blade down) passes through nothing, and the hand turned over in one frame. The sampler of a keyed action does the same
  between two keys more than 69 degrees apart (a great circle).
* **Weights stay weights.** Flags (`IO_FLAGS`: open hand, spear in hand, hood, the held-hand weights) are clamped to 0..1 after an
  offset is added; the whole-body rotation keeps a rotation-vector mix (rotation vectors do not add up).
* **Where the new source has no velocity.** The sampled action has none for the legs and hips a blow drives at run time or the
  layers take from the gait (`_io_rt`, `_src_before`), and a new motion state's previous frame says nothing about its velocity
  (`_io_src_new`): those take the velocity of the thing they are really driven by.
* **Hand-over before the end.** An action that ends into the gait (the parry, the dodge, the hit, the land) says `"ho": s`: from
  that second the trunk, the head and the arms mix into the live gait (`_handover`), the legs, the pelvis' translation and the
  whole-body rotation stay the action's. The action's end is then not a pose the gait has to be reached from but one it has
  already reached.
* **Upper-body layers.** The parry, the throw, the catch and the pull are played on the upper body while he moves (`play_at(..,
  upper)`); the hit and the heavy hit, the recoil, the death, the parry, the catch and the pull keep the air pose's legs when they
  are played in the air (`AIR_LAYERED`).

`mode=trans` and `mode=loco` still pass unchanged (27 and 143), as does every blow (`mode=strike`, `mode=combo`).

### 6.9 Before and after, step 3

| metric | before (the rig as step 2 left it) | after |
|---|---|---|
| pops, checks failing (`mode=pops`: 67 sequences, 268 checks) | 174 of 268 (the first run, on the rig as step 2 left it, with the first limits and a ceiling of 1.0; snap ratios up to 12.5. With the final limits and ceiling 1.5, 55 of 268 were still above after the first fix, the limb frames, and before the inertialized blends) | **0 of 268** (33 sequences within 1.0, 34 in the fast tier, none above 1.5) |
| joint ranges failing (`mode=ranges`, 72 checks) | 22 (elbow 4, wrist extension 18) | **5** (the sword hand's wrist extension in dodge 2, don_skin 2, pull 1; elbow 0) |
| clip issues, all actions (2602 samples; cloth makes them vary by a few between runs) | 683 | **354** (863 in the live game) |
| loco / trans / strike / combo checks failing | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 (143 / 27 / 68 / 8 checks; strike also passes at lunge 0.8 / 1.4 / 2.0, carry 3.2 / 5.5, 120 and 60 Hz; at 30 Hz one check is 84.6 % against 85 %, at 24 Hz ten fail, 8.8) |
| spear swap (`mode=swap`) | not measured | 12 of 12: 0.4-0.6 cm, 0.7-1.5 degrees, 0.1-0.7 degrees |
| arena autotest at 60 / 24 fps | 16 of 16 / 16 of 16 | 16 of 16 / 16 of 16 |
| encounter bots (`encbot=all`), lion bot (`units`, `fight_sealed`) | PASS | 12 of 12, 12 of 12, PASS |
| headless `play=1`, wheat walk (walk and run) | clean, PASS | clean, PASS |
| `advance()` cost | 1.01-1.27 ms mean per state (idle, jog, sprint, blow, throw, roll, hit, air) | 1.03-1.39 ms (the same states, two passes; worst frame 2-5 ms) |

---

## 7. Where the code is, and what is not done

* `scripts/gfx/rig_heracles.gd`: the block "animation: the ground gait" (constants and tables, `_pl`, the ankle/pin
  helpers, `_arm_fk`, `_sword_hand`, the foot state machine `_feet_update` with `_gait_start`, `_gait_stop`, `_liftoff`,
  `_land`, `_plant_landing`, `_pelvis_limit`, `_ground_pose`). Outside it: `_track_motion` keeps the instantaneous yaw
  rate, `advance` counts frames (`_adv_n`, a gap above 1 means the ground pose was not running and the feet are planted
  afresh), `reset_cloth` clears the planted feet, `preview_pose` starts the gait at a given phase and heading.
* `scripts/gfx/rig_heracles.gd`, the block between `# >>> STRIKES BEGIN` and `# <<< STRIKES END` (generated and spliced by
  `docs/anim_design/`, see 4.8): `_kc` (the curves), `_arm_q` and `_sword_hand2` (the arm from joint angles), `_strike_pose`,
  `_bake_strike`, `_strike_raw` (the data), `_strike_begin` / `_strike_end`, `_strike_move` / `_strike_feet` (the footwork),
  `_strike_layer` and `set_strike_run` (a blow on the run), `_wrist_limit`. Outside the block: `_compile_actions` (the names in
  `STRIKE_NAMES` replace keyed definitions, which are gone from `_action_defs`), `play()` (`_sk_init`, `_sk_run`), `_animate()`
  (the `sk` / `skl` / `skc` split, `_wlim`, the wrist limit's tail), `_solve` (the limit; the upright test uses `_reduce_rot`, a spin of
  360 degrees is upright) and `preview_pose(..., heading, lunge)`.
* `scripts/gfx/rig_heracles.gd`, step 3 (section 8): the solver's limb frames and trackers (`_bend_normal`, `_pole_eff`, `_limit_arm_dir`,
  `_soft_reach`, `_tw_fa` / `_twist_step`, `_prelim_fa_dir` / `_free_hand`, the held-hand block of `_solve`, `_sh_slack` / `_slack_xf` /
  `shield_skin`), the inertialized blends (`_blend_out`, `_src_before`, `_io_*`, `IO_FLAGS`, `IO_DIRS`), `compile_action` /
  `sample_action` (Hermite keys, partial keys, `ho`, `dlen`, `fast`), `_handover`, `_layer_lower`, `AIR_LAYERED`, the guard spring (`GUARD_W/Z`,
  `set_guard`, `GUARD_CUT`), the landing (`_land_impact`, `LAND_W/Z`), `_hit_dir_apply`, `_air_pose`, the keyed actions (`_action_defs`,
  `_throw_def`, `_catch_def`, `_more_actions`) and the channels `hls`, `hrs`, `hlr`, `hrr`.
* `scripts/player/hero.gd`: unchanged. `_feed_rig` already gives the rig what it needs; the rig works out acceleration,
  turn rate and direction of travel itself. `scripts/player/hero_melee.gd`: one line in `_begin` (`rig.set_strike_run`).
* `tools/anim_check.gd/.tscn` (modes `strike` and `combo`), `tools/anim_strips.sh`, `tools/strike_strips.sh`, `tools/preview_heracles.gd`
  (strafe / back / guard rows; action rows take `:speed`, a `lunge=` argument, the views `hand`, `handf`, `handb`), the `dump=1` option
  and the action list (`act_names()`) of `tools/clip_check_heracles.gd`. Step 3 added the modes `pops`, `swap` and `perf` to
  `tools/anim_check.gd` (the pops code is the block under "pops: every state transition"), and `rig.shield_skin()` to the clip checker (the
  shield with its strap's slip).
* Frame rate: the thresholds are for 60 Hz. At 120 Hz the walk slides 2.2 cm and the guard walk 2.5 cm (limit 2). At 30 fps
  one frame per step has the trailing foot 1.5-2 cm short of its target (5.8 % of the jog's frames, 8.2 % of the
  sprint's; invisible), the per-frame jerk thresholds of `pops` are exceeded in a sprint, and the hardest transitions
  (a gait change, a stutter) leave a foot up to 9-11 cm short for a frame. `anim_check fps=30|120` shows it.
* Not done: swim, zip and hang are as they were (the zip and the hang only gained the shield's strap, 8.4; the air pose is new, 8.3).
  Section 8.8 lists what step 3 leaves open. The strike numbers of section 4 are design values; what the built blows measure is in 4.8.
  The cadence/stride at the jog is above a runner's (3.3); the sprint lean is stylised (1.1). The wrist deviation is judged
  by the blade-to-forearm angle, not by the bone measure (6.3). `anim_check` once showed one failing check in a first run (the idle lean, 0.03 degrees outside its limit): `scripts/gfx/rig.gd` starts every rig at a random time, so the idle's breathing differed from run to run. The tool now sets `rig.t = 0` and its numbers are the same in every run; `clip_check_heracles` still builds rigs at a random time, so its cloth-related counts vary by a few issues.

---

## 8. Step 3: consistency and transitions (how the other actions were built, and what came out)

The client's rule for this step: the rest of the character has to be consistent with the new run and the new blows (anticipation,
weight, arcs, overlap, the torso and the head taking part) and nothing may pop or snap in a transition (a run into a blow into a run,
idle into a sprint, a sprint into a roll into a sprint, a blow into the next, a blow into the guard, anything into a hit). The
durations and the events of every action are the ones of `docs/COMBAT.md` (3.2 and 7): the hero code, the chain spear, the
camera and the sounds are tuned to them, and none of them moved (`len`, `ev`; only the blend lengths `in` / `out` and the new
`ho` / `dlen` / `fast` are the rig's own). Everything below is in `scripts/gfx/rig_heracles.gd`; the checks are 6.7-6.9.

### 8.1 The method: a detector first, then the fixes it asked for

1. **`mode=pops`** (6.7) was written before anything was changed, run on the rig as step 2 left it and kept as the judge of every
   edit. Its first run failed 174 of 268 checks, with snaps up to twelve times the limit in almost every sequence (the
   same cause in all of them: see 8.2, the shield forearm that turned half a turn in one frame).
2. The infrastructure under the actions was fixed in the order the numbers asked for it: limb frames and twist (8.2), inertialized
   blends (6.8), the held hand (8.4), the pose of each action (8.3), the guard, the landing, the hit direction (8.5).
3. After every change the whole regression set ran (loco, trans, strike with its variants, combo, ranges, swap, pops) so that the
   blows and the gaits of steps 1 and 2 stayed exactly as they were: they are the references the limits were calibrated on.
4. Every image was looked at: strips of the gameplay camera and the side view for each action, before and after (5), and close-ups
   where a number said something was wrong (the throw's shield, the zip pose, the roll).

### 8.2 The solver underneath

All of these are in `_solve` and its helpers; none changes a pose that was already good (loco / strike / combo / trans are
unchanged), they remove what made a good pose flip:

* **Limb frames from the bend plane** (`_bend_normal`), not from the limb's axis and a pole: where the axis crossed the pole the frame
  flipped half a turn in one frame and took the shield forearm, the knee or the elbow with it. The forearm's twist about its axis
  is a tracked angle (`_tw_fa`, `TWIST_RATE` 20 rad/s, 36 when the hand is free): it follows the vector it is defined by in
  proportion to how well defined that is, else it keeps what it was, and it always takes the short way round.
* **Pole tracking** (`_pole_eff`, `POLE_RATE` 32 rad/s): the direction a knee or an elbow bends towards is kept continuous where the pole
  lies along the limb's line. Not applied to the sword arm of a blow, whose elbow goes where the blow was built to put it.
* **The hand goes round the shoulder, never through it** (`_limit_arm_dir`, `ARM_DIR_RATE` 30 rad/s): a hand sent from one side of the
  shoulder to the other along a straight line passes close to it and its direction swings half a turn in a few frames.
* **Soft reach** (`_soft_reach`): the reach eases towards 98.5 % of the arm's length from 93 % (an arm is never locked straight: the
  elbow's angle changes ever faster near full length) and the elbow folds to 150 degrees with soft stops at 128 / 144 (all elbow
  range checks pass now).
* **The elbow keep-out push is continuous** (a fixed push switched on at the first millimetre of penetration flipped the elbow from
  one side of the arm to the other).
* **Keyed actions** are Hermite splines per channel (`compile_action`, `_key_tangents`, `_hermite_sample`): zero tangent at the ends and
  at keys marked `"ease"` (anticipation holds, settles), keys inherit the previous value, **partial keys** (`"partial": true`) set
  only the channels they name (the throw's sword arm comes up at 0.265 without touching the left arm's grab), directions are
  interpolated on great circles when two keys are more than 69 degrees apart.

### 8.3 The actions, one by one

All durations and events are unchanged. "Handover" is the `ho` second of 6.8.

| action | length, events | what it does now |
|---|---|---|
| `parry` | 0.5 s, impact 0.15 | on the upper body over the guard gait. Anticipation (0.06 s): the shield comes back to the chest and the chest winds away. The punch turns the spine and the chest into it, shoulders leading, impact at 0.15; the arm carries a few centimetres past the contact (follow-through, in the slow motion of the hit), the head holds the target; the arm comes back to the guard along a lower path (handover from 0.3 s). The guard itself arrives on a spring (`GUARD_W` 24, `GUARD_Z` 0.62: it goes a little past the pose and settles) |
| `dodge` (roll) | 0.62 s, steps 0.06 / 0.46 | the dive drops the hips and folds the spine over the thighs (the blade swung down along the leg so it never leads the tumble); one even turn of the whole body about a pivot under the chest (0.75 m up, so that the plume and the spear on his back clear the ground at the bottom); the landing is a deep crouch with the arms out for balance; the rise leans into the next stride (handover from 0.55 s); the hands stay in the chest's frame all through, the sword points out along the axis the body turns about |
| `hit` | 0.38 s | the pelvis and the trunk take the blow first, the head is thrown back a beat later (the neck's peak at 0.09 s comes after the chest's), the arms fly out for balance, the body comes back past upright and settles. Turned to the direction the blow pushed (below); on the move it is the upper body's only |
| `hit_heavy` | 0.85 s, steps 0.22 / 0.70 | the whole body takes it: chest and head thrown back (the head a beat after), arms wide, the left foot lifts and comes down behind him (the stumble at 0.22 s) as the pelvis is driven back and down, the trunk folds forward catching the balance (0.34 s), the right foot slides back (0.7 s), he straightens with the shield coming up |
| `death` | 1.8 s, step 0.48, thud 1.28 | the blow (head and chest recoil), the legs give, the sword hand opens and goes slack, down on the knees, the trunk slumps over them, the head drops last, he topples onto his right side (thud at 1.28 s, a small bounce), the arms flop; the last pose holds |
| `jump`, `land` | 0.28 s, 0.36 s | the jump leaves with the push of the toes (pointed, trailing), the arms swing up and forward, the lead knee comes up and the other leg trails: it ends in the rising air pose (below). The landing has two parts: a damped spring on the pelvis' height kicked by the speed the ground was met at (`_land_impact`, `LAND_W` 21, `LAND_Z` 0.48), and the crouch he stays in (arms out, head bows then lifts, the rise overshoots upright a little) |
| `throw` | 0.95 s, grab 0.20, swing 0.38, release 0.47 | reach over the left shoulder (the hand and the forearm come round to the grip over the whole reach, from 0.10 s), the grab at 0.20 s (the spear in the fist and the one on the back are the same spear there: 6.6), the sword arm comes up to point at the target (0.265 s, partial key), cocked at 0.335 s (the torso wound to the left, the spear over the shoulder pointing at the target, the forearm upright, the shield edge-on beside the head), the whip (hips and chest unwind, the elbow leads forward past the head, 0.395 s), the release, the follow-through |
| `catch` | 0.46 s | the fist closes on the shaft in front of the chest in the roll the guard hand already has, swings it up over the shoulder and straps it on his back (`CATCH_STOW` 0.24 s); the empty hand comes out to the side before it drops, never back down through the shoulder and the chest |
| `pull` | 0.8 s, pull 0.24 | both fists on the chain, a big haul leaning back (pelvis down and back, spine and chest after it), a braced hold, recover |
| `grapple_start / _loop / _end` | 0.5 s, 1.6 s loop, 0.7 s | the lunge in and the arms locked round the neck (`GRAPPLE_HOLD`), the strain in a loop, the shove; both hands in rig space (`hrs`, `hls`) so they stay on the beast while the body moves |
| `interact`, `pet`, `don_skin`, `victory` | 0.7, 1.6, 2.4, 2.2 s | lightly touched: their poses are as they were authored (reach and press; kneel and stroke twice; crouch, swing the pelt, hood over the helmet, knot the paws; anticipation, the sword to the sky, hold, settle). What changed is under them: the limb frames, the held-hand roll (`hrr` 0 for the sword hand), the inertialized blends and the handover. Their wrist-extension numbers are among the five in 8.8 |
| `recoil`, `backstep`, `climb` | 0.52, 0.5, 0.58 s | recoil: the blade bounces off something it cannot cut, the arm flung up and back, a step back, the guard comes back (keys retimed: 0.1 / 0.22). backstep: the dodge without a direction. climb: the hands are given in rig space so they stay on the lip while the body rises; the sword stands up out of the fist (`hrr` 0) |

**The air pose** (`_air_pose`): not a seated tuck any more. The right leg leads (the knee comes up and forward on the rise, the foot reaches
down and ahead on the way down) and the left trails behind (extended back on the rise, coming under him for the landing); the faster he
came, the longer the stride between them (a leap out of a sprint is a stride, a jump from standing a hop); the arms go up and forward
for the lift and out for the way down, the trunk and the head follow the vertical speed. The jump's last key is the rising pose, so the
action and the state meet without a seam.

**Hit direction** (`_hit_dir_apply`): the lean of the torso and the push of the pelvis are turned by the direction in which the rig's own
velocity changed in the first 0.05 s of the action (the knock-back the hero code already gives him; under 1.2 m/s there is no direction and
the hit is straight back). The rig works the direction out itself, so `hero.gd` needs no change (it could pass the direction of the blow
explicitly, which would be better for a hit on a standing hero: nothing moves him then).

**Blow into guard** (`set_guard`, `GUARD_CUT`): when the hero cancels the recovery of a blow into the guard (`HeroMelee`'s `cancel`, from
0.30 / 0.29 / 0.50 / 0.80 s for attack1 / 2 / 3 / heavy) the rig stops the recovery too (0.14 s) instead of finishing a recovery he has left.

### 8.4 Held hands: the spear, the chain, the wheat

A hand that holds something has to be where it is, in a roll that the wrist can do. The left hand has three ways of being given:
the wrist in chest space (`hl`) with the shield's facing (`hlf`) and an elbow pole (`hlp`); an explicit hand frame (`hlb` the shaft, `hlk`
the back of the hand, weight `hlx`: the spear, the chain, the zip and the ring); and hand-space weights `hls` / `hrs` (1: the numbers
are in rig space, before the body's rotation, so a hand stays on a lip or a beast while the body moves).

* **Roll authority** (`hlr`, `hrr`): 1, the hand's roll about the shaft is as authored; 0, the hand turns about the shaft to the roll
  that keeps the wrist straight to the forearm (`_free_hand`, `_prelim_fa_dir`), the fist staying where it was put. The throw uses the authored roll
  through the reach and the grab (so that the spear in the hand and the one on the back coincide) and a free roll from the draw on; the
  catch meets the spear in a free roll and ends in the authored one at the stow (the same coincidence); the sword hand is free (`hrr` 0) in the actions where the blade is only carried (the wrestle, the pet,
  the climb, the victory), where a blow's blade direction is not the point.
* **The forearm turns with the grip**: the left forearm's twist is a mix of the shield's facing and the grip (`TW_SHIELD` 0.5 of the
  shield stays, the grip's share is kept within `TW_HAND_MAX` 1.2 rad), so the wrist is not asked for the whole turn; what is beyond
  goes to the wrist. The hand blend itself is a swing and a twist about the forearm axis (`_wr_tw`): a plain slerp between two frames
  half a turn apart changes the way round it goes in one frame, a snap of the wrist.
* **The shield's strap slips** (`_sh_slack`, `SH_SLACK_MAX` 1.2 rad, 20 rad/s): what the forearm could not give of the shield's facing
  because it turned with the hand, the shield takes: it turns about the forearm's axis on its strap while the hand draws the spear from
  his back, and stays out beside the head and the chest. Only when a hand is held (`hlx`): in blows, the guard and the brush the shield is
  on the forearm as before. Without it the shield was 5-11 cm in his chest and 5 cm in the helmet through the draw and the cock of
  the throw (13 cm in the lion's hood); with it the clip checker finds none of that (what is left is the spear in the fist against the shield's edge, 2-3 cm for about 0.15 s: the cocked
  shield faces out and a little back, away from the spear that points forward past it, so the throw's keys ask for a facing the
  forearm alone would not give).
* **The spear changes hands without a seam** (6.6): the back spear's own roll is baked from the hand frame at the grab / stow.

### 8.5 What the numbers do not say: looking at it

Strips of every action in the gameplay camera and the side view, before (the live rig) above and after below, are in
`shots/s3/final/compare/<action>_before_after.png`: the run at 2.2, 6.2 and 9.0 m/s, the three blows and the heavy, the parry, the
roll, the hit and the heavy hit, the throw; the originals are in `shots/s3/final/before/` and `.../after/`. The other actions (jump, land,
death, victory, interact, pet, don_skin, the three grapple parts, climb, recoil, backstep, pull, catch, zip, hang, the air pose) are one strip
each in `shots/s3/final/after2/`, four at a time in `shots/s3/final/compare/others_<n>_after.png` (the after only: the sheet the client
asked for is the list above). Close-ups of the throw's draw and cock (`shots/s3/slack/close/`), the zip and hang poses as step 2 left them (`*_s2`) and
after the first held-hand work, before the shield's strap (`*_cur`: the plume and the spear through the shield; `shots/s3/zip/`; the
final ones are `final/after2/strip_zip.png` and `strip_hang.png`), the roll (`shots/s3/dodge/`) and the pelt (`shots/s3/don/`) are next to
them. (`shots/s3/slack/strip_*.png` were rendered before the throw's last facing change, `shots/s3/intermediate/` holds renders of
earlier states of the rig, neither is the final.) What to look for, beyond 5: the weight shifts before a limb moves (the hips and chest go first,
the arm follows); every action starts and ends in the pose the gait or the guard is in (no frame where he is somewhere else); the head
is the last thing to arrive and the last to leave (the hit, the parry, the whip); the shield never goes through him.

### 8.6 How to run the checks

```
godot --headless --path . res://tools/anim_check.tscn -- mode=pops            # 67 sequences, 268 checks, about 25 s
godot --headless --path . res://tools/anim_check.tscn -- mode=pops seq=throw_run,hit_in_attack verbose=1
godot --headless --path . res://tools/anim_check.tscn -- mode=pops seq=throw_idle dbg=wrist_l,0.6,1.0   # every frame of one joint
godot --headless --path . res://tools/anim_check.tscn -- mode=pops calib=1    # the fastest / sharpest of every joint in the gaits and blows
godot --headless --path . res://tools/anim_check.tscn -- mode=swap            # 12 checks
godot --headless --path . res://tools/anim_check.tscn -- mode=perf
godot --headless --path . res://tools/anim_check.tscn -- mode=ranges acts=dodge verbose=1   # where a wrist leaves its range
godot --headless --path . res://tools/anim_check.tscn -- mode=strike strike_hz=60|30|24 lunge=0.8 carry=5.5   # the variants
godot --headless --path . res://tools/clip_check_heracles.tscn -- acts=throw,catch,pull,zip,hang,dodge [verbose=1]
godot --headless --path . res://tools/arena.tscn --fixed-fps 60 --quit-after 40000 -- autotest=1 quit=1       # also 24
godot --headless --path . res://tools/encounters.tscn --fixed-fps 60 --quit-after 60000 -- encbot=all quit=1
godot --headless --path . --fixed-fps 60 --quit-after 30000 -- play=1 lionbot=units quit=1                   # and lionbot=fight_sealed
godot --headless --path . res://tools/wheat_walk.tscn --fixed-fps 30 --quit-after 3000 -- noui=1 [run=1]
timeout 600 godot --headless --path . --quit-after 1500 -- play=1 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR"
xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/preview.tscn -- script=res://tools/preview_heracles.gd fns=sheet rows="parry@game;parry@side" cols=12 tile=240x280 out=strip.png
tools/strike_strips.sh <dir> throw catch pull loco:6.2 attack1:5.5 ...   # rows game / side / front (COLS, T0, T1, VIEWS, TILE)
```

(The only engine line the headless `play=1` check prints is `ERROR: 12 resources still in use at exit`; it is on the unmodified game too.)

### 8.7 Numbers

See 6.9 for the table. In short: pops 0 of 268 failing; loco 143, trans 27, strike 68 (and its variants), combo 8, swap 12 all pass;
ranges 67 of 72; the arena, encounter and lion bots pass; the wheat walk passes; clip issues **354** (863 in the live game).

### 8.8 Known limits, honestly

* **Five wrist checks fail** (`mode=ranges`), all of the *sword* hand: `dodge` (extension -169 .. +176 degrees mid-tumble, the hand's
  twist about the forearm reaches 170 degrees at 0.18 s and 0.35 s while the body is upside down), `don_skin` (-148 .. +120, the hand
  that pulls the hood over the helmet and knots the paws) and `pull` (-142). They are authored hand frames of poses in which the blade
  has to point somewhere particular while the arm folds. Two cures were tried and taken out again, both made the roll, the pull and
  the pelt flip in a frame (the sequences went to 3 times the pop limit): a clamp on the wrist, and the free roll about the blade
  (`hrr` 0, which does bring the roll and the pull to -62 and -62 degrees, two degrees outside) in those three actions: the roll
  about the blade axis is a slerp between two orientations that can be half a turn apart. A tracked roll angle, as the twist has (`_tw_fa`,
  `_wr_tw`), would be the way. They were looked at instead: the roll reads as a tucked somersault with the sword carried in the fist
  (`shots/s3/dodge`), the pelt as a pelt (`shots/s3/don`). The wrist deviation is reported only (6.3). The other 67 pass, the elbow all.
* **The blade-to-forearm angle** (28 degrees in the gaits and blows, enforced by the limiter that only a blow arms) is reported, not
  enforced, in the other actions: minimum throw 13.6, land 15.0, jump 18.3, hit_heavy 19.1, recoil 20.8, don_skin 22.1, dodge 22.4,
  death 23.5, climb 25.0, pet 25.8, pull 26.0, victory 26.1 degrees. A limiter that is not armed only in a blow has to be continuous where
  the blade crosses the forearm's line; that was not built.
* **The fast tier** (6.7): 34 of 67 sequences have a metric between 1.0 and 1.5 of its limit, the worst the throw's left wrist at 1.50 (rate)
  and 1.39 (snap) at the draw and the follow-through. Nothing is above 1.5.
* **The throw's hand** is twisted about 85-130 degrees relative to the forearm bone through the cock and the whip (the forearm bone
  itself carries up to 69 degrees more): more than a forearm turns; the shield is kept out of the way by its strap and the hand is
  behind the head from the gameplay camera, but a close-up from the front shows it. A pole chosen for the least twist would be the proper cure.
* **Clip**: 354 issues in 2602 samples (863 in the live game, 683 after step 2; the cloth makes the count vary by a few between runs).
  What is left is cloth (the cape against the shield or an arm in the heavy, 3-7 cm, and the heavy hit's pelvis, 3 cm: as in the live
  game), the lion hood against the right forearm in the wrestle loop (20 samples, 4.5 cm), the hood against the shield in the lion's
  throw (4 cm for a few samples) and the left hand against the hood in its draw (5.3 cm, one sample), the spear in the left fist against
  the shield's edge in the throw (3 cm for 0.15 s) and the catch (3 cm, 0.1 s), the backstep's left arm against the torso (2.5 cm, as in
  the live game), the fist against the paws in don_skin and the lion's pull (2.8 cm), and the roll's left foot (2.6 cm, 0.07 s). The
  zip and the hang, which clipped after the first held-hand work (the shield 2-4 cm in the plume and the spear on his back through the
  whole zip), are at 0 now, and so are the shield and his chest or head in the throw and the catch (the strap, 8.4).
* **Frame rate**: the limits are for 60 Hz. `mode=strike strike_hz=60` and `120` pass 68 of 68; `strike_hz=30` has one check at 84.6 %
  against 85 % (`attack2`'s arc coverage, a quantization of the 30 Hz sampling: 11 of 13 bins; the same on the step-2 rig);
  `strike_hz=24` has 10 failing: eight are chain and arc metrics that are made for 120 Hz (hips' peak rate, chest over hips, chain
  spread in frames, arc coverage: at 24 Hz a link of the chain lasts one frame), the heavy's impact event is 1.15 frames from where it
  was authored (limit 1) and 2 of its 19 frames (10.5 %) have an ankle more than 1.5 cm short of its target (a foot that is not
  visibly off: the leg is fully stretched in a spin of 55 degrees per frame). The arena bot passes at 24 fps (16 of 16).
* The roll's left foot dips 2.6 cm under the ground in two samples (0.07 s) at the landing crouch; the roll's plume and spear no longer do.
* Changes outside the owned files: none in this step (step 2's one line in `scripts/player/hero_melee.gd`, `rig.set_strike_run`, stays).

---

## 9. Carrying the weapons (lane STOW)

Two states. **ARMED**: the sword in the right fist, the shield on the left forearm. **STOWED**: the sword in a scabbard at his left
hip, the shield on his back with the chain spear strapped over it. The game starts STOWED (`Hero._ready` and the respawn at the altar
call `rig.set_armed(false, true)`); a bare `RigHeracles.new()` (previews, the clip checker, the anim tools) starts ARMED as before.

**Rig API.** `set_armed(on, instant := false)` plays the draw or the sheathe of whatever is not where it should be (`instant`: put
there now); `is_armed()` (a draw playing counts as armed, a sheathe as not); `sword_in_hand()`, `sword_free()` (in the hand and its
tip out of the throat), `shield_in_hand()`, `stow_busy()`, `stow_action_for(on, sword, shield)` (the action name, "" if nothing to do),
`scabbard_segment()` (throat and end, world space, for tools), `alert` (0..1, set by Hero: the armed idle's ready stance).
`weapons_aside` (the wrestle) is unchanged. **Hero API.** `weapons_ready()` (= `rig.sword_free()`), `request_arms(sword, shield)`,
`STOW_AFTER := 4.0`, `ARMS_FOE_DRAW := 8.0`, `ARMS_FOE_CALM := 12.0`, `ARMS_WADE := 0.75`.

**The actions** (upper body: `play_at(a, 1.0, true)`, the legs keep the locomotion; their moments are `STOW_EV`):

| action | length | moments (s) |
|---|---|---|
| `draw` | 0.55 | fist on the grip 0.12, the tip out of the throat 0.27; fist on the rim 0.15, forearm into the band 0.40; handover 0.44 |
| `draw_sword` | 0.24 | grip 0.06, tip out 0.15 (a blow waiting for it starts here); ends cocked over the right shoulder |
| `draw_shield` | 0.26 | rim 0.07, forearm in 0.18 (handover 0.18); ends at his side, or up in front as `draw_shield_guard` (`_variant()` picks it while the guard is held) |
| `sheathe` | 0.80 | rim 0.12, the tip finds the throat 0.38, shield hung 0.50, sword home 0.56; handover 0.62 |
| `sheathe_sword` | 0.62 | tip in 0.26, home 0.42 |
| `sheathe_shield` | 0.55 | rim 0.08, hung 0.36 |

Sounds through the Sfx autoload at -6 dB: `sword_draw` (grip), `sword_sheathe` (the tip in the throat), `shield_draw` (forearm in),
`shield_stow` (hung); silent until the FX lane's files are in.

**No pops.** No node changes parent: after the solve `_stow_frame` works out every prop's frame from what holds it (`AT_SHEATH`,
`AT_HAND`, `AT_BACK`, `AT_RIM`: the left fist on the rim between the back and the arm, `AT_ARM`) and `_place_weapons` puts it there. A
hand-off keeps where the prop was as an offset in its new holder's frame that dies away (smoothstep, 5-16/s). `_stow_pose` (after the
blend) puts the fists exactly on the grip in the scabbard, along the slide and on the rim on his back, and keeps the free blade a
hand's breadth over the ground and outside the right leg (`_blade_clear`, as in the carry: the lowest tip in a draw on the run is
0.22 m at 6.2 m/s, 0.21 m at 9.0). The arms' carry weights (`_carry_sw`, `_carry_sh`) blend the relaxed and the armed locomotion
(about 0.25 s). Tip heights in the carry: standing 0.27 m, walk 0.34-0.56, run 0.54-1.0, sprint 0.82-1.37.

**The scabbard.** Dark leather (`SHEATH` #3B2216, darker than the belt, lighter seams), bronze throat, band and chape; 0.96 m (grip
space -0.15 to -1.11). It hangs by a short strap from the belt at his left hip (`SCAB_HINGE`), the throat at `SCAB_T`, pointing back,
down and a little out (`SCAB_D`, 57 degrees from the vertical), and swings on the strap as a damped pendulum driven by the pelvis'
acceleration and tilt (`SCAB_K` 140, `SCAB_C` 13, at most 1.3 rad), the chape kept 7 cm over the ground and the sheath outside the left
thigh. A draw turns it to follow the blade out (`SCAB_D_DRAW`), a sheathe turns it up to meet the tip (`SCAB_D_SHEATHE`); while the
blade slides the scabbard lies along it. The cape drapes over it (a cape collider). The diagonal back scabbard was not needed.

**The shield on his back.** On the spine between the shoulder blades (`SHB_C`; 3 cm further out over the lion's pelt), face out and a
little up, hanging from its top, in the frame of the spear on the back (it follows the upper back); the cape stays under it (`_cape_step`).
The spear lies over it (`spear_over_xf`: 0.135 m further out at the head, 0.19 at the butt), so the throw and the catch have `_over`
variants (`throw_over`, `catch_over`, and `_lion`), picked by `_variant()`. The shield is drawn round his left side.

**Locomotion** (`_ground_arms`, `_ground_pose`, `_air_pose`). Relaxed: loose fists swinging against the legs (`T_RX_A` 24 degrees at
the walk, 50 at the run, 58 at the sprint, more forward than back, the elbows bending with speed); the run leans in (P2: `T_LEAN`
13.5 degrees at 6.2 m/s, 27 at 9.0). Idle P1: the weight on one leg, changing every 6-11 s; standing on with the weapons away, the left
hand rests on the pommel a few seconds in eleven (`_pommel_rest`). Armed: the sword low in the right fist, the blade trailing back and
down (`T_AC_EV` -34 degrees at the walk to -24 at the sprint), kept 26 cm over the ground and outside the right leg (`_blade_clear`);
idle P9 (the blade hanging steeply by his right foot), with `alert` the ready stance (lower, the shield up in front of his left side).
Guard P7: crouched behind the shield, looking over its rim, the sword arm back low (the guard walk too). Air P6: arms spread, knee up;
armed, the sword arm out to the side with the blade back. Jump and land keys trail the blade.

**The rules** (`Hero._tick_arms`, every tick; the foes scanned every 0.2 s). Both come out for the lock-on, a hostile foe within 8 m
(`is_fighting()`, a telegraph, or a brain past idle and not walking home; dummies count) and after a hit (once the reaction is over).
A blow pressed with the sword away plays `draw_sword` and the blow starts when the tip is out (kept 0.7 s; from stowed the hit lands
about 0.32 s after the press); the heavy's charge the same; the guard plays `draw_shield` first, but the guard and its parry window
are up from the press. Both go away after `STOW_AFTER` s of calm (no hostile foe within 12 m, no lock, no guard, no blow, charge or
stagger), in water deeper than 0.75 m and swimming. Nothing starts until he is free (`_arms_free`: MOVE, not rolling, zipping or
hanging, the rig idle or in an action that may be cut). The zip to a ring sheathes the sword on the way (the left fist holds the
chain); the wrestle lays down only what is in his hands.

**Preview.** `armed=0|1` (draw rows start stowed, sheathe rows armed), `ready=<0..1>`, the row `idlelong:<s>`, the views `hipl`,
`hipb`, `backc`, `gamec`, `tqlc`.

**Outside the STOW blocks** (`# >>> STOW BEGIN` .. `# <<< STOW END` in rig_heracles.gd; the STOW sections of hero.gd): one-line hooks
in `_build`, `_action_defs`, `_animate` (x3), `_apply_bones`; `_variant` (the `_over` and `draw_shield_guard` variants);
`_throw_def` / `_catch_def` (an `over` argument); `NEUTRAL`'s sword hand (trailing back, was forward and down); `T_LEAN`; the arms of
`_ground_pose` (now `_ground_arms`), its guard block (P7) and the idle's weight shift; `_air_pose` arms and the jump / land keys;
`_cape_colliders` (the whole blade, the scabbard) and `_cape_step` (the shield on the back); `preview_pose(..., armed, ready_k)`.

**Not done / for the other lanes.** The other actions (hit, recoil, dodge, backstep, climb, pet, pull, victory, death) were authored
for the old blade and are untouched; `NEUTRAL`'s new sword hand changes what they inherit where a key leaves the sword hand out. The
clip checker's `shield_skin()` does not know the shield can be on his back. Petting a cat and donning the pelt do not sheathe first
(the pelt hides the stowed weapons with the others). The hang and the ledge climb (P3) are as they were.

## 10. The lanes wired together (INTEGRATE, 2026-10-17)

STOW (the weapons carried), MOVESET (the blows) and FX (the feel tools) merged with LOOK's hero into one rig. The rig's own
INTEGRATE code sits between `# >>> INTEGRATE BEGIN` and `# <<< INTEGRATE END` at the end of rig_heracles.gd; the changes
elsewhere are marked `INTEGRATE` in their comments. The blows themselves changed only through the generator
(`docs/anim_design/moveset.py`, then `splice_strike.py`).

**Drawing into the blow.** A press with the sword sheathed plays a variant of `draw_sword` that leads into the blow the
routing rule picked at the press (`draw_into` = a1, b1 or dash; `DRAW_INTO` {go 0.245 s, skip 0.06 / 0.05 / 0.05};
`_variant` answers `draw_sword_<blow>`; built by `_draw_into_actions` from STOW's draw keys). Keys at 0, 0.05, 0.15,
0.185, 0.215, go, go + 0.08: STOW's reach to the grip and the pull, then the free blade swung down in front of him (`dip`)
and round his right side (`side`) into the blow's own pose `skip` s in (arm, chest, neck and head from `_strike_pose`), the
trunk turning with it. Hero hands over at `draw_go()`: `HeroMelee.start_entry(route, draw_skip())` starts the blow with
`rig.action_t = skip`. The sheet row `entry:<blow>[:speed]` (et0 / et1) shows the press to the blow's end.

**Out of a blow.** When a blow ends or is cut, the inertialized blend carried the sword hand's speed on; the recovery's
last sweep carried the fist 16 cm into his hip (b1, a1, a3, the heavy). `IO_STRIKE_V` caps the carried speed of the sword
hand's channels at 1.2 m/s for a blend out of a strike or the throw (`_io_from_strike`, set in `advance()` and
`stop_action()`). Fist and blade against the pelvis at the blows' ends: 16.5 cm -> 4 cm; at the throw's end 4.6 -> 3.6 cm
(the rest is the path from the throw's end pose to the carry, not carried speed).

**The other armed actions** were keyed for the old short blade held forward; with the long trailing blade they swung it
through the ground or the legs. Re-keyed (strips: merged/shots/acts): `ready` (recoil, the climb's end) = the trailing
carry; hit 0.09; hit_heavy 0.36; dodge 0.15 / 0.25 / 0.45 / 0.56; victory (a partial key at 0.14, a shallower 0.3);
pull (the hand out at his side); death 0.08 / 0.24; climb (partial keys 0.44 / 0.52 and its own end hand); throw (partial
keys 0.12 / 0.8: the blade round his right side); parry (the sword cocks back over the right shoulder instead of pointing
ahead, so the guard's blade no longer snaps round); the air pose's blade further out; `T_AB_L` wider at speed (the shield
met the left thigh in the sprint); the guard's sword fist out from the hip.

**MOVESET's open points**, through the generator: b1's plane lowered (`B_PLANE`, shared with b2: it meets the foe 0.94 m
up and crosses his front 1.0 m up, a wolf's height); b1's recovery low across his front like A's (its cost 354 -> 92);
the cuts of a2, a3, b1, b2 spread over a frame or two more, the snap kept (peaks 79-136 m/s); a1's follow-through over
3 frames and then the recovery at once, no slow settle; b2's wind-up cocked further forward (on the lowered plane the
forearm went through his head); b3's shield flung back wide over the lunging left thigh; the heavy's held coil with the
fist at the left hip (the blade lay across the shield). Impact events: a4 0.28 s, b1 0.155 s. Frame counts (wind-up /
cut / hold): a1 9/3/9, a2 5/3/0, a3 6/4/1, a4 13/3/11, b1 7/4/3, b2 5/3/2, b3 10/3/11, dash 14/4/12, heavy 1/20/13.

**The spear on his back** (`SPEAR_BACK_TIP` / `SPEAR_BACK_BUTT`, shared by `spear_back_xf` and `spear_over_xf`): tip
(-0.47, 1.8, 0.24), butt (0.26, 0.72, 0.31), 34 degrees from the vertical. From the front its head is a spear behind his
left shoulder, not a horn or an ear over his head.

**The cloak** (`_cape_step`): in b3's lunge (0.12-0.6 s) the drape is held like in the dodge (shape 30), and whenever the
sword arm reaches ahead of the chest the cloth lying on the upper arm slides round it to its back, a quarter of the way
each collision pass, so the cloak hangs behind the outstretched arm instead of over it like a sleeve.

**Clip check** (`tools/clip_check_heracles.tscn`, the blows and every armed action): what is left is grazes of 2-6 cm for
a few frames: the blade against the spear's butt and chain coil behind his right hip as a1, a3 and b1 blend into the idle
(5 cm), the raised shield against the spearhead in the dash (4.7 cm), the heavy's blade against the shield at the
release (4.6 cm, one frame), the spear hand against the shield in the throw and the catch (4 cm), the fist against the
hip as the throw ends (3.6 cm), the cloak against the left upper arm late in b3's hold (5 cm, one frame), and the cloth's
usual few cm. Older than this round and left as they were: in the lion outfit the shield passes 9 cm into the hood in the
throw (0.43 s, two frames). b2's first frames when played on its own from the idle
(it always follows b1 in play) and the stow actions played on an armed rig are the checker's artefacts.

