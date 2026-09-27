// DEAD AIR — "THE SIGN-OFF" easter egg (GDD §13 steps 1–5 + the step-6 trigger, §18.13 ids, §18.15 events).
// Owner: easter-egg engineer. Step 6 (the Baron fight + ending) belongs to src/actors/boss.js / src/game/ending.js:
// this file opens the cage, runs the 2 s kill-switch hold and calls game.boss.start(round); the boss emits
// egg:step {step:6} / egg:complete (or calls egg.setStep(6), which emits both).
//
// STATE (ARCHITECTURE §10)  step (0..6 completed steps) · done · STEP_IDS · forceForecaster (bool, steps 3→4: rounds.js
//   reads it: ≥ 1 Forecaster per round + the 60 % rule) · storm (the Stray Storm object | null; storm.active) ·
//   stormActive · applause (step-3 kill count, persists across rounds) · hasTape · carried (puppet ids on the belt)
// PROGRESS WITHOUT UI (every completed step 1–5): sting_ee_correct ding, the Baron's laugh from the nearest TV (angrier
//   each time: faster, higher, louder), +T.points.eeStep (economy.add(..., 'egg')), egg:step {step} (the MC rundown board
//   pins card <step> with its gold star by itself), and a music-box phrase sting_ee_<step> from every TV.
// STEP 1 "STATION IDENTIFICATION": shootables ee_bar_red/yellow/green/blue (level.objects.ee_chime_rack.raycast per bar;
//   bullets + melee, grenades/splash ignored, at most one bar per frame = shot event). Before power a dull
//   ee_chime_tunk and nothing counts. After power ee_chime_<bar> + egg:chime {bar} (the lobby swings the bar) and a
//   buffer of the last 4 hits; complete when [red, yellow, green, blue] with every gap <= T.ee.chimeGap. Beats: station
//   ID on every TV 3 s + the round motif with its brass chord (sting_round_start); the lobby fixes the neon Z/T and
//   lights the booth ON AIR lamp on egg:step. Hook: the three ghost puppets start to exist + a giggle from the case.
// STEP 2 "THE PUPPET SEGMENT": Dudley (trophy case), Sockrates (anchor desk), Hootie (prize-wheel hub) are built here
//   (cute felt hand puppets), live on LAYERS.TV_ONLY in their area root (feeds only), and giggle every 12–20 s within
//   10 m. ON AIR (client pass: they were barely noticeable on the small CRTs) the ghosts are GHOST[key].scale x bigger
//   (Dudley 1.4 standing on the case's middle shelf, the others 1.45), turned toward their feed camera, perform (bob,
//   sway, big waves / wing flaps, jaw chatter, a squash-and-stretch hop every 2.4–5 s, sometimes with a twirl) and wear
//   an on-air look (GHOST_LOOK: a strong warm rim + softer shading, mats.variant of their felt); screens.js keeps each
//   one in the middle of its feed through the whole camera pan. Tuned in they shrink back to 1x and their normal felt
//   while tumbling down. Shootable spheres r = T.ee.puppetR around the scaled centre ('ee_puppet_<name>'): 0.4 s static
//   flicker -> layer 0,
//   ee_puppet_reveal, drop (Dudley: the case door pops open and he tumbles out). [E] (key only, 1.2 m) picks one up: it
//   hangs bobbing from the belt slot. [E] at the theater (ee_puppet_theater.interact, r 1.5) slots every carried puppet
//   (golden silhouette). All 3: curtain opens, the puppets hop up and sing ee_kazoo_song (6 s), every living Sock
//   Hopper freezes, turns toward Studio B and pops into confetti (kill cause 'egg', no points, counts for the round).
//   Hook: one echoing ee_clap_single from Studio A (30 m), the APPLAUSE sign flickers at 2–5 Hz, the tote twitches.
// STEP 3 "CUE THE APPLAUSE": while step == 2, a zombie:kill whose pos is inside T.ee.applauseZone while the player is
//   in studio_a counts (+1, persists): the sign lights solid 0.6 s, the applause (client pass: it was inaudible under the
//   kill's gunshot) = ee_applause_near (non-positional crowd + the gloves' claps on CLAP.beats) + ee_applause_burst at
//   both bleachers (rolloff to 45 m), the tote board flips +$1 (ee_tote_flip), and APPLAUSE HANDS: a pair of white
//   cartoon gloves pops in (squash and stretch, a confetti puff) above the zombie's body, claps on CLAP.beats (a star
//   burst at each contact), floats up and fades out (2.1 s; pooled, 2 instanced draw calls, keepColor toon, world
//   layer; only for counted kills). The first kill gets a huge crowd reaction. At 13: $13,000, thermometer-top confetti, two
//   confetti cannons (built here on the lighting grid) fire, ee_ovation (+ a long near layer), the sign locks lit. Hook (+2 s): ee_thunder_far
//   from the newsroom (map-wide), newsroom lights flicker, weather-map suns slide off, storm + bolt magnets slide onto
//   the tower and blink, ee_map_rumble every 20 s; forceForecaster = true (+ 'egg:need_forecaster' if none is alive).
// STEP 4 "THE WEATHER": while step == 3 the next 'zombie:forecaster_storm' {pos} (a Forecaster killed with his cloud
//   intact) leaves the Stray Storm (built here: 1.5x cloud, #5B4A7A, grumpy face, crackles, rain column, ee_storm_loop).
//   It follows the player's breadcrumb trail (a crumb every 0.25 s) at T.ee.storm.speed, 3 m above the floor (under the
//   ceiling), zaps 10 every 4 s within 2 m (visual rain only), evaporates after 90 s (fades from 75 s) or after 8 s
//   straight farther than 20 m of path (nav.dist). egg:storm {state:'spawn'|'lost'|'arrived'}. Complete when the player
//   is within 6 m (XZ) of the tower base and the storm within 8 m of the player: it races up the tower (1.5 s), a jagged
//   lightning bolt hits the top (whiteout pulse, ee_lightning_strike), the Baron flashes on every TV 0.5 s with a laugh.
//   The yard turns the beacons rainbow and Telly goes purple + arms the tape pull, both on egg:step {step:4}.
// STEP 5 "ROLL TAPE": Telly's forced pull hands out the reel (machine:telly_take {itemId:'ee_tape_reel'}, strapped to
//   the back by telly.js). Carrying it, [E] at VTR #2 (1.5 m) loads it (1.5 s, ee_tape_thread, ee_vtr2.loadTape): its
//   monitor (scr_vtr2, a private canvas texture) plays the Sign-Off film badly: vertical roll 0.5·d screens/s, tearing
//   d/6, snow d/6; audio: the hymn looping from the deck with a wobble ∝ d + ee_tracking_tones (setDistance(d)). The
//   TRACKING knob ([E] key only, 1.5 m; turns and clicks all game) goes +1 per press from a random s0 to a random kT != s0,
//   d = circular distance (0..6), egg:tracking {detent, distance}. Complete when d == 0 and no knob press for 3 s while
//   within 4 m of VTR #2 (leaving pauses the timer). Beats: VTR lamp green, the clean Sign-Off film on every TV (20 s)
//   + sting_signoff_hymn, ON AIR boxes flash, ee_baron_scream from every TV. Hook: the kill-switch cage springs open
//   (ee_cage_boing), the knife switch gets a rainbow outline + glow, ee_alarm_bell rings in the yard for 10 s.
// STEP 6 TRIGGER: [E] hold T.ee.switchHold s on the kill switch (step == 5): the switch is thrown (ee_switch_thunk)
//   and game.boss.start(round) is called (boss.start plays the THUNK after its audio.stopAll). If the fight does not
//   start, or the boss goes inactive without a defeat while playing, the switch re-arms (outline back, hold again).
//   egg:step {step:6} / egg:complete from anyone are mirrored into step/done.
// EVENTS  egg:step {step} · egg:complete {} · egg:chime {bar} · egg:puppet_reveal {id} · egg:puppet_slot {id} ·
//   egg:applause {count} · egg:storm {state} · egg:tracking {detent, distance} · egg:need_forecaster {}
// DEBUG  setStep(n) (= debug.egg(n): jumps, applying each skipped step's end state instantly and emitting egg:step
//   for each) · debugHit(id, {melee}) (ee_bar_*, ee_puppet_*) · debugUse(id) (runs an interactable: 'pickup:<puppet
//   id>', 'ee_puppet_theater', 'ee_vtr2', 'ee_tracking_knob', 'ee_kill_switch') · revealLayer2(bool) (the main camera
//   also renders LAYERS.TV_ONLY) · debugKill(x, z) (a synthetic zombie:kill at x, z: counts + applause hands when it
//   qualifies) · debugClap(x, z) (just the applause hands at x, z) · debugStorm(x, z) (spawns the Stray Storm) ·
//   debugGiveTape() · debugTrack(k) · debugState() -> JSON (claps = live applause-hand pairs).
// TESTS  tools/scenarios/egg_*.cjs (see tools/scenarios/egg_run.sh; egg_chain = every step via debug hooks + the boss
//   handoff), shots in _shots/egg/<name>/.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { T, PAL, LAYERS } from '../core/config.js';
import * as K from '../props/kit.js';
import { buildTapeReel } from './telly.js';

// Clone for warmup samples without deep-copying userData (Object3D.copy JSON-stringifies it; ours hold Object3D refs).
function cloneBare(o) {
  const saved = [];
  o.traverse((x) => { saved.push(x, x.userData); x.userData = {}; });
  try { return o.clone(); } finally { for (let i = 0; i < saved.length; i += 2) saved[i].userData = saved[i + 1]; }
}


export const STEP_IDS = ['ee_1_station_id', 'ee_2_puppets', 'ee_3_applause', 'ee_4_storm', 'ee_5_roll_tape', 'ee_6_sign_off'];

// ------------------------------------------------------------------------------------------------ constants
const E = T.ee;
const S = E.storm;
const TAU = Math.PI * 2;
const BARS = ['red', 'yellow', 'green', 'blue'];
const PRI = { signoff: 3, ee: 5 };
const ALL_TV = ['scr_decor', 'scr_mc_canned', 'scr_mc_feeds', 'scr_feed_*'];
const IGNORED_CAUSES = new Set(['grenade', 'explosion', 'splash']);
const PUPPETS = [
  { id: 'ee_puppet_dudley', key: 'dragon', area: 'lobby', home: [-6.75, 1.3, -2.0], rotY: -Math.PI / 2, drop: [-6.0, 0, -2.0], shift: 0.22 },
  { id: 'ee_puppet_sockrates', key: 'sock', area: 'newsroom', home: [20.2, 1.21, 0.0], rotY: Math.PI / 2, drop: [19.6, 0.4, 0.0], shift: 0 },
  { id: 'ee_puppet_hootie', key: 'owl', area: 'studio_a', home: [4.0, 2.35, -29.3], rotY: Math.PI, drop: [4.0, 0.6, -28.6], shift: 0.05 },
];
// belt hangers (belt-slot local; the slot sits at the front of the hips): left hip, right hip, back
const HANG = { dragon: [-0.21, -0.03, 0.13, 1.25], sock: [0.21, -0.03, 0.13, -1.25], owl: [0.0, -0.03, 0.3, Math.PI] };
const HANG_SCALE = 0.55;
const PUPPET_CENTER = 0.24;
// On-air ghosts (step 2, feeds only): size, idle bob + hop height (model units), squash amount. Dudley stands on the
// trophy case's middle glass shelf (DUDLEY_SHELF above the case base) so the 1.4x ghost fits under the crown.
const GHOST = {
  dragon: { scale: 1.4, bob: 0.02, hop: 0.015, sq: 0.5 },
  sock: { scale: 1.45, bob: 0.045, hop: 0.1, sq: 1 },
  owl: { scale: 1.45, bob: 0.045, hop: 0.1, sq: 1 },
};
const GHOST_HOP = { dur: 0.5, every: [2.4, 5.0], spin: 0.3 };
const DUDLEY_SHELF = 1.03;
// the on-air look: a strong warm rim + softer shading so the felt pops off the busy sets on small CRTs
const GHOST_LOOK = { rim: 0.78, rimColor: '#FFC477', rimPower: 1.55, wrap: 0.8 };
// Applause hands (step 3): clap beats (s after the kill; ee_applause_near gets the same list), life, pop-in time,
// fade start, rise, pool size, glove scale, palm gap open / touching (m), height above the body's floor.
const CLAP = { beats: [0.16, 0.36, 0.56, 0.76, 0.96, 1.16], life: 2.1, pop: 0.26, fade: 1.5, rise: 0.42, max: 6,
  scale: 1.5, open: 0.5, touch: 0.15, height: 1.7 };
const CLAP_STARS = ['#FFFFFF', '#FFE45C', '#FFD27A'];
const BAR_PUSH = 0.31;
const BAR_R = 0.1;
const STUDIO_B_C = new THREE.Vector3(21, 1, -21);
const STUDIO_A_CLAP = new THREE.Vector3(4, 4.5, -18);
const BLEACHERS = [new THREE.Vector3(-2.5, 1.6, -13.4), new THREE.Vector3(10.5, 1.6, -13.4)];
const CANNONS = [{ pos: [-1.6, 6.2, -17.2], aim: [2.0, 1.0, -16.6] }, { pos: [9.6, 6.2, -17.2], aim: [6.0, 1.0, -16.6] }];
const NEWSROOM_C = new THREE.Vector3(15, 3, -1);
const TOWER = new THREE.Vector3(45, 0, -12);
const TOWER_TOP = new THREE.Vector3(45, 29.5, -12);
const VTR_FALLBACK = new THREE.Vector3(26.75, 1.0, -2.6);
const KNOB_FALLBACK = new THREE.Vector3(26.75, 1.1, -3.15);
const TOTE_BASE = 12987;
const STORM_COLOR = '#5B4A7A';
const RAINBOW = ['#FF4A4A', '#FF9F2E', '#FFE45C', '#5CE07A', '#4AB8FF', '#9A6BFF'];

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _u = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _col = new THREE.Color();
const _m4 = new THREE.Matrix4();
const _qy = new THREE.Quaternion();
const _qr = new THREE.Quaternion();
const _qt = new THREE.Quaternion();
const _sc = new THREE.Vector3();
const _cp = new THREE.Vector3();
const AX_Y = new THREE.Vector3(0, 1, 0);
const AX_Z = new THREE.Vector3(0, 0, 1);

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const easeOutBack = (k) => 1 + 2.4 * (k - 1) ** 3 + 1.4 * (k - 1) ** 2;
const easeInOut = (k) => (k < 0.5 ? 2 * k * k : 1 - (-2 * k + 2) ** 2 / 2);
const v3 = (a) => (a && a.isVector3 ? a.clone() : new THREE.Vector3(a[0], a[1], a[2]));
const hueColor = (t, out) => out.setHSL(((t % 1) + 1) % 1, 0.95, 0.6);

// Ray (o, unit d) vs capsule (segment a-b, radius r): entry distance or -1.
const _ca = new THREE.Vector3(), _cb = new THREE.Vector3(), _cc = new THREE.Vector3();
function rayCapsule(o, d, a, b, r) {
  const seg = _ca.subVectors(b, a), w0 = _cb.subVectors(o, a);
  const B = d.dot(seg), C = seg.dot(seg), D = d.dot(w0), Ee = seg.dot(w0);
  const den = C - B * B;
  let s = den > 1e-8 ? (Ee - B * D) / den : 0;
  s = s < 0 ? 0 : s > 1 ? 1 : s;
  const t = Math.max(0, B * s - D);
  const pr = _cc.copy(o).addScaledVector(d, t);
  const px = a.x + seg.x * s - pr.x, py = a.y + seg.y * s - pr.y, pz = a.z + seg.z * s - pr.z;
  const dd = Math.sqrt(px * px + py * py + pz * pz);
  if (dd > r) return -1;
  return Math.max(0, t - Math.sqrt(Math.max(0, r * r - dd * dd)));
}

// ================================================================================================ art helpers
const tg = (geo, color) => K.tint(geo.clone(), color);
const tm = (geo, mat, color, o) => K.m(color ? tg(geo, color) : geo, mat, o);
const sph = (r, ws = 18, hs = 12) => new THREE.SphereGeometry(r, ws, hs);
const cone = (r, h, seg = 12) => K.lathe([[0, 0], [r, 0], [r * 0.35, h * 0.72], [0, h]], { seg, round: Math.min(r, h) * 0.18 });

// Googly eye: white ball + black pupil pushed toward `look` on its surface (+ a tiny catchlight).
function googly(g, plas, pos, r, look, { pupil = 0.5, white = '#FFFFFF', iris = null } = {}) {
  g.add(tm(sph(r, 16, 12), plas, white, { pos }));
  const d = new THREE.Vector3(...look).normalize();
  if (iris) g.add(tm(sph(r * 0.72, 14, 10), plas, iris, { pos: [pos[0] + d.x * r * 0.62, pos[1] + d.y * r * 0.62, pos[2] + d.z * r * 0.62], scale: [1, 1, 0.55] }));
  const pr = r * pupil;
  const pp = [pos[0] + d.x * (r - pr * 0.45), pos[1] + d.y * (r - pr * 0.45), pos[2] + d.z * (r - pr * 0.45)];
  const pm = tm(sph(pr, 14, 10), plas, '#15101C', { pos: pp, scale: [1, 1, 0.6] });
  pm.lookAt(pp[0] + d.x, pp[1] + d.y, pp[2] + d.z);
  g.add(pm);
  g.add(tm(sph(pr * 0.3, 8, 6), plas, '#FFFFFF', { pos: [pp[0] + pr * 0.35, pp[1] + pr * 0.4, pp[2] + d.z * pr * 0.55] }));
}

// felt with a gentler rim than the kit preset (the preset's velvet halo washes small saturated puppets out)
const puppetFelt = (game) => K.mat(game, 'felt', '#ffffff', { keepColor: true, rim: 0.22, rimPower: 2.6, wrap: 0.6 });

// Lathe with v = height / vSpan (even stripes whatever the profile's point spacing)
function latheV(profile, opts, vSpan) {
  const g = K.lathe(profile, opts).clone();
  const p = g.attributes.position, uv = g.attributes.uv;
  for (let i = 0; i < p.count; i++) uv.setY(i, p.getY(i) / vSpan);
  uv.needsUpdate = true;
  return g;
}

function partGroup(g, name, pos) {
  const p = new THREE.Group();
  p.name = name;
  p.position.set(pos[0], pos[1], pos[2]);
  p.userData.noMerge = true;
  g.add(p);
  g.userData.parts[name] = p;
  return p;
}

function finishPuppet(game, g) {
  K.finish(game, g, { ao: { res: 40, strength: 0.7 } });
  for (const p of Object.values(g.userData.parts)) if (p) K.merge(p);
  g.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = true; } });
  return g;
}

// Dudley: purple felt dragon, googly eyes, yellow belly (GDD §13 step 2). ~0.5 m, base at y 0, front -z.
function buildDudley(game) {
  const g = K.prop('ee_puppet_dudley');
  const felt = puppetFelt(game);
  const plas = K.mat(game, 'plastic', '#ffffff', { keepColor: true });
  const P = '#9B57F2', PD = '#7340CC', BELLY = '#FFD24A', GREEN = '#46D467', CREAM = '#FFF1D6';
  g.add(tm(K.lathe([[0, 0], [0.132, 0], [0.15, 0.035], [0.152, 0.11], [0.136, 0.2], [0.11, 0.27], [0, 0.3]], { round: 0.025, seg: 24 }), felt, P));
  g.add(tm(new THREE.TorusGeometry(0.138, 0.02, 8, 26).rotateX(Math.PI / 2), felt, PD, { pos: [0, 0.022, 0] }));
  const belly = K.tint(sph(0.1, 20, 16), (x, y) => (Math.floor((y + 0.1) / 0.05) % 2 ? new THREE.Color('#FFD84A') : new THREE.Color('#F5B528')));
  g.add(K.m(belly, felt, { pos: [0, 0.15, -0.098], scale: [0.98, 1.25, 0.52] }));
  for (const s of [-1, 1]) g.add(tm(sph(0.028, 10, 8), felt, '#FF7FAA', { pos: [s * 0.095, 0.385, -0.15], scale: [1, 0.7, 0.4] }));
  // head: cranium + long snout
  g.add(tm(sph(0.118), felt, P, { pos: [0, 0.43, 0.03] }));
  g.add(tm(sph(0.12), felt, P, { pos: [0, 0.385, -0.075], scale: [1.05, 0.7, 1.35] }));
  for (const s of [-1, 1]) g.add(tm(sph(0.014, 8, 6), felt, PD, { pos: [s * 0.036, 0.41, -0.228] }));
  for (const s of [-1, 1]) g.add(tm(cone(0.014, 0.04, 8).rotateX(Math.PI), plas, '#FFFFFF', { pos: [s * 0.05, 0.36, -0.19] }));
  googly(g, plas, [-0.058, 0.505, -0.03], 0.056, [0.3, -0.35, -1]);
  googly(g, plas, [0.058, 0.51, -0.025], 0.056, [-0.1, -0.1, -1]);
  for (const s of [-1, 1]) g.add(tm(cone(0.022, 0.075, 10), felt, CREAM, { pos: [s * 0.068, 0.53, 0.07], rot: [-0.55, 0, s * 0.35] }));
  [[0.54, 0.06, 0.034], [0.49, 0.13, 0.042], [0.4, 0.165, 0.048], [0.3, 0.16, 0.046], [0.2, 0.155, 0.04]].forEach(([y, z, r]) =>
    g.add(tm(cone(r, r * 1.5, 10), felt, GREEN, { pos: [0, y, z], rot: [-1.2 + y * 0.8, 0, 0] })));
  for (const s of [-1, 1]) g.add(tm(cone(0.05, 0.12, 3), felt, GREEN, { pos: [s * 0.08, 0.25, 0.12], rot: [-1.0, s * 0.5, s * 0.9], scale: [1, 1, 0.35] }));
  // jaw (lower snout + red mouth + tongue)
  const jaw = partGroup(g, 'jaw', [0, 0.35, 0.03]);
  jaw.rotation.x = -0.16;
  jaw.add(tm(sph(0.105), felt, P, { pos: [0, -0.03, -0.095], scale: [1, 0.42, 1.3] }));
  jaw.add(tm(sph(0.09), felt, '#C42F4C', { pos: [0, 0.0, -0.1], scale: [0.9, 0.3, 1.12] }));
  jaw.add(tm(sph(0.036), felt, '#FF86A8', { pos: [0, 0.012, -0.15], scale: [1, 0.4, 1.4] }));
  // stubby arms with mitten hands
  for (const [s, name] of [[-1, 'armL'], [1, 'armR']]) {
    const a = partGroup(g, name, [s * 0.13, 0.225, -0.02]);
    a.add(tm(K.lathe([[0, 0], [0.032, 0.004], [0.03, -0.075], [0.0, -0.085]], { round: 0.014, seg: 12 }), felt, P, { rot: [0.35, 0, s * 0.3] }));
    a.add(tm(sph(0.037, 12, 9), felt, P, { pos: [s * 0.025, -0.085, -0.03] }));
    a.add(tm(sph(0.016, 8, 6), felt, CREAM, { pos: [s * 0.035, -0.07, -0.062] }));
  }
  return finishPuppet(game, g);
}

// Sockrates: striped sock puppet with tiny spectacles, a toga sash, a laurel wreath and a felt beard.
function buildSockrates(game) {
  const g = K.prop('ee_puppet_sockrates');
  const felt = puppetFelt(game);
  const plas = K.mat(game, 'plastic', '#ffffff', { keepColor: true });
  const stripeTex = K.tex.canvas('egg.sock_stripes.v2', 64, 128, (ctx, w, h) => {
    const cols = ['#F2363A', '#FFF9EE', '#2F66F2', '#FFF9EE'];
    for (let i = 0; i < 8; i++) { ctx.fillStyle = cols[i % 4]; ctx.fillRect(0, (i * h) / 8, w, h / 8 + 1); }
    ctx.fillStyle = 'rgba(0,0,0,0.06)';
    for (let x = 0; x < w; x += 4) ctx.fillRect(x, 0, 1, h);
  });
  const sock = K.mat(game, 'fabric', '#ffffff', { map: stripeTex, keepColor: true, rim: 0.4 });
  const RED = '#EC3340';
  g.add(K.m(latheV([[0, 0], [0.122, 0], [0.132, 0.03], [0.128, 0.13], [0.118, 0.23], [0.1, 0.295], [0, 0.32]], { round: 0.02, seg: 24 }, 0.3), sock));
  g.add(tm(new THREE.TorusGeometry(0.128, 0.022, 8, 26).rotateX(Math.PI / 2), felt, '#F4F1E8', { pos: [0, 0.02, 0] }));
  // toe = upper jaw (solid red toe patch)
  g.add(tm(sph(0.118), felt, RED, { pos: [0, 0.37, -0.06], scale: [1, 0.72, 1.3] }));
  g.add(tm(sph(0.1), felt, RED, { pos: [0, 0.395, 0.03] }));
  // button eyes + spectacles
  for (const s of [-1, 1]) {
    g.add(tm(sph(0.027, 12, 9), plas, '#18121E', { pos: [s * 0.045, 0.44, -0.108] }));
    g.add(tm(sph(0.007, 6, 5), plas, '#FFFFFF', { pos: [s * 0.045 + 0.009, 0.449, -0.131] }));
    g.add(tm(new THREE.TorusGeometry(0.033, 0.0055, 6, 18), plas, '#D9AE48', { pos: [s * 0.046, 0.438, -0.128], rot: [0.12, 0, 0] }));
    g.add(tm(K.tube([[s * 0.079, 0.44, -0.125], [s * 0.1, 0.445, -0.07], [s * 0.105, 0.43, -0.01]], 0.004, { seg: 6, radial: 4 }), plas, '#D9AE48'));
  }
  g.add(tm(K.tube([[-0.014, 0.442, -0.134], [0, 0.45, -0.138], [0.014, 0.442, -0.134]], 0.004, { seg: 6, radial: 4 }), plas, '#D9AE48'));
  // laurel wreath
  const lg = sph(0.024, 10, 7);
  for (let i = 0; i < 14; i++) {
    const a = (i / 14) * TAU;
    const l = tm(lg, felt, i % 2 ? '#5DAA3E' : '#7BC650', { pos: [Math.sin(a) * 0.092, 0.462 + (i % 2) * 0.012, 0.03 + Math.cos(a) * 0.092], scale: [1, 0.42, 0.55] });
    l.rotation.set(0, a, (i % 2 ? 0.5 : -0.5));
    g.add(l);
  }
  g.add(tm(sph(0.012, 8, 6), felt, '#E8A92E', { pos: [0, 0.47, -0.065] }));
  // toga sash (over the right shoulder, across the chest) + gold brooch
  const sash = K.lathe([[0.126, -0.04], [0.14, -0.036], [0.146, 0], [0.14, 0.036], [0.126, 0.04]], { seg: 28, round: 0.006 }).clone();
  K.tint(sash, (x, y) => (y < -0.028 ? new THREE.Color('#E8A92E') : new THREE.Color('#FFF6E6')));
  g.add(K.m(sash, felt, { pos: [0, 0.165, 0], rot: [0.1, 0, 0.6] }));
  g.add(tm(K.lathe([[0, 0], [0.05, 0.01], [0.04, 0.09], [0, 0.1]], { seg: 10, round: 0.01 }), felt, '#FFF6E6', { pos: [0.1, 0.2, 0.045], rot: [0.2, 0, -0.35] }));
  g.add(tm(sph(0.02, 10, 8), plas, '#E8A92E', { pos: [0.098, 0.25, -0.075] }));
  // jaw: lower toe + mouth + tongue + beard
  const jaw = partGroup(g, 'jaw', [0, 0.335, 0.02]);
  jaw.rotation.x = -0.18;
  jaw.add(tm(sph(0.1), felt, RED, { pos: [0, -0.028, -0.09], scale: [0.96, 0.4, 1.26] }));
  jaw.add(tm(sph(0.085), felt, '#6E1A34', { pos: [0, 0.0, -0.095], scale: [0.88, 0.3, 1.1] }));
  jaw.add(tm(sph(0.03), felt, '#FF86A8', { pos: [0.02, 0.012, -0.15], scale: [1, 0.4, 1.4] }));
  for (const [x, y, z, r] of [[0, -0.055, -0.15, 0.045], [-0.045, -0.045, -0.13, 0.036], [0.045, -0.045, -0.13, 0.036], [-0.02, -0.095, -0.145, 0.034], [0.02, -0.095, -0.145, 0.034], [0, -0.13, -0.14, 0.026]]) jaw.add(tm(sph(r, 12, 9), felt, '#F7F4EE', { pos: [x, y, z] }));
  g.userData.parts.armL = g.userData.parts.armR = null;
  return finishPuppet(game, g);
}

// Hootie: brown felt owl host with huge round eyes, ear tufts, a red bow tie.
function buildHootie(game) {
  const g = K.prop('ee_puppet_hootie');
  const felt = puppetFelt(game);
  const plas = K.mat(game, 'plastic', '#ffffff', { keepColor: true });
  const BR = '#A1612E', BRD = '#7B4520', TAN = '#F5D09A', ORANGE = '#FF8A1C';
  g.add(tm(K.lathe([[0, 0], [0.125, 0], [0.155, 0.06], [0.165, 0.17], [0.155, 0.28], [0.125, 0.37], [0.07, 0.43], [0, 0.445]], { round: 0.02, seg: 24 }), felt, BR));
  g.add(tm(sph(0.13, 22, 16), felt, TAN, { pos: [0, 0.16, -0.105], scale: [0.84, 1.02, 0.54] }));
  const scallop = new THREE.SphereGeometry(0.021, 12, 6, 0, TAU, 0, Math.PI / 2).rotateX(-Math.PI / 2);
  [[0.215, [-0.036, 0, 0.036]], [0.175, [-0.054, -0.018, 0.018, 0.054]], [0.135, [-0.036, 0, 0.036]], [0.095, [-0.018, 0.018]]].forEach(([y, xs]) => xs.forEach((x) => {
    const q = 1 - (x / 0.109) ** 2 - ((y - 0.16) / 0.133) ** 2;
    const z = -0.105 - 0.07 * Math.sqrt(Math.max(0, q)) + 0.004;
    g.add(tm(scallop, felt, '#D69A5A', { pos: [x, y, z], scale: [1, 0.8, 0.45] }));
  }));
  for (const s of [-1, 1]) {
    g.add(tm(sph(0.088), felt, '#FFF0CF', { pos: [s * 0.068, 0.325, -0.108], scale: [1, 1, 0.35] }));
    g.add(tm(K.lathe([[0, 0], [0.018, 0.002], [0.004, 0.05]], { seg: 8, round: 0.004 }), felt, BRD, { pos: [s * 0.075, 0.405, -0.1], rot: [-0.3, 0, -s * 1.15] }));
    g.add(tm(cone(0.036, 0.1, 10), felt, BRD, { pos: [s * 0.095, 0.425, 0.0], rot: [0, 0, -s * 0.45] }));
  }
  googly(g, plas, [-0.068, 0.328, -0.125], 0.056, [0.05, 0.02, -1], { pupil: 0.62, iris: '#FFB52E', white: '#FFF6DA' });
  googly(g, plas, [0.068, 0.328, -0.125], 0.056, [-0.05, 0.02, -1], { pupil: 0.62, iris: '#FFB52E', white: '#FFF6DA' });
  g.add(tm(cone(0.028, 0.07, 10), plas, ORANGE, { pos: [0, 0.29, -0.15], rot: [-2.1, 0, 0] }));
  // red bow tie
  for (const s of [-1, 1]) g.add(tm(cone(0.042, 0.075, 12), plas, '#E23B3B', { pos: [s * 0.078, 0.232, -0.15], rot: [0, 0, s * Math.PI / 2], scale: [1, 1, 0.5] }));
  g.add(tm(sph(0.02, 12, 9), plas, '#C22A2A', { pos: [0, 0.232, -0.158] }));
  for (const s of [-1, 1]) g.add(tm(sph(0.009, 6, 5), plas, '#FFFFFF', { pos: [s * 0.05, 0.245, -0.168] }));
  // feet
  for (const s of [-1, 1]) for (let k = -1; k <= 1; k++) g.add(tm(sph(0.02, 8, 6), plas, ORANGE, { pos: [s * 0.06 + k * 0.022, 0.012, -0.12 - Math.abs(k) * -0.01], scale: [1, 0.6, 1.4] }));
  const jaw = partGroup(g, 'jaw', [0, 0.26, -0.14]);
  jaw.add(tm(cone(0.02, 0.035, 8), plas, '#D8741E', { pos: [0, 0, -0.01], rot: [-2.5, 0, 0] }));
  for (const [s, name] of [[-1, 'armL'], [1, 'armR']]) {
    const w = partGroup(g, name, [s * 0.148, 0.31, 0.01]);
    w.add(tm(sph(0.1), felt, '#86502A', { pos: [s * 0.012, -0.1, 0], scale: [0.32, 1, 0.72] }));
    w.add(tm(sph(0.06, 12, 8), felt, BRD, { pos: [s * 0.018, -0.17, 0.01], scale: [0.3, 0.8, 0.6] }));
  }
  return finishPuppet(game, g);
}

// The Stray Storm: a 1.5x Forecaster cloud in #5B4A7A with a grumpy face, an inner crackle glow and a rain column.
function buildStorm(game) {
  const root = new THREE.Group();
  root.name = 'stray_storm';
  const body = new THREE.Group();
  root.add(body);
  const puffs = [[0, 0, 0, 0.62], [0.58, 0.02, 0.05, 0.5], [-0.58, 0.0, 0.03, 0.52], [0.26, 0.34, 0.08, 0.46], [-0.3, 0.3, 0.02, 0.45],
    [0.98, -0.14, 0, 0.34], [-1.0, -0.12, 0.05, 0.36], [0, -0.24, 0.18, 0.42], [0.36, -0.22, -0.22, 0.36], [-0.36, -0.2, -0.2, 0.38],
    [0, 0.12, 0.38, 0.5], [0.05, 0.5, 0.12, 0.34]];
  const geos = puffs.map(([x, y, z, r]) => {
    const s = new THREE.SphereGeometry(r, 16, 11);
    const p = s.attributes.position;
    for (let i = 0; i < p.count; i++) if (p.getY(i) < -r * 0.45) p.setY(i, -r * 0.45 + (p.getY(i) + r * 0.45) * 0.35);
    s.computeVertexNormals();
    s.translate(x, y, z);
    return s;
  });
  const cloudGeo = mergeGeometries(geos, false);
  const mat = game.mats.toon(STORM_COLOR, { rough: 0.95, rim: 0.32, rimColor: '#B9A4F0', rimPower: 2.4, wrap: 0.7, keepColor: true, emissive: '#1C1430', emissiveIntensity: 0.6 });
  const cloud = new THREE.Mesh(cloudGeo, mat);
  cloud.castShadow = true;
  body.add(cloud);
  // grumpy face: angry brows, squinting eyes with little pupils, a wobbly frown
  const faceTex = K.tex.canvas('egg.storm_face', 256, 128, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    ctx.lineCap = 'round';
    for (const s of [-1, 1]) {
      const cx = w / 2 + s * 52, cy = 58;
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath(); ctx.ellipse(cx, cy, 24, 17, 0, 0, TAU); ctx.fill();
      ctx.fillStyle = '#1E1530';
      ctx.beginPath(); ctx.arc(cx - s * 4, cy + 4, 9, 0, TAU); ctx.fill();
      // heavy lid slanting down toward the nose + an angry brow (inner end low)
      ctx.fillStyle = STORM_COLOR;
      ctx.beginPath(); ctx.moveTo(cx - 32, cy - 32); ctx.lineTo(cx + 32, cy - 32);
      ctx.lineTo(cx + 32, s < 0 ? cy + 1 : cy - 15); ctx.lineTo(cx - 32, s < 0 ? cy - 15 : cy + 1); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = '#1E1530'; ctx.lineWidth = 11;
      ctx.beginPath(); ctx.moveTo(cx - s * 30, cy - 4); ctx.lineTo(cx + s * 28, cy - 24); ctx.stroke();
    }
    // grumbling mouth: a lopsided frown with a zig-zag
    ctx.strokeStyle = '#1E1530'; ctx.lineWidth = 8; ctx.lineJoin = 'round';
    ctx.beginPath(); ctx.moveTo(w / 2 - 36, 110); ctx.lineTo(w / 2 - 22, 98); ctx.lineTo(w / 2 - 10, 106); ctx.lineTo(w / 2 + 2, 96); ctx.lineTo(w / 2 + 14, 104); ctx.lineTo(w / 2 + 26, 96); ctx.lineTo(w / 2 + 36, 108); ctx.stroke();
  }, { repeat: false });
  const faceMat = new THREE.MeshBasicMaterial({ map: faceTex, transparent: true, alphaTest: 0.3, depthWrite: false, toneMapped: false });
  const face = new THREE.Mesh(new THREE.PlaneGeometry(0.95, 0.475), faceMat);
  face.position.set(0, 0.05, -0.66);
  face.rotation.y = Math.PI;
  face.renderOrder = 2;
  body.add(face);
  // crackle glow (inner)
  const glowMat = new THREE.MeshBasicMaterial({ color: new THREE.Color('#C9A8FF').multiplyScalar(2.2), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
  const glow = new THREE.Mesh(new THREE.SphereGeometry(0.8, 14, 10), glowMat);
  glow.scale.set(1.35, 0.7, 0.9);
  body.add(glow);
  // rain column: additive streaks scrolling down
  const rainTex = K.tex.canvas('egg.storm_rain', 64, 128, (ctx, w, h, rand) => {
    ctx.clearRect(0, 0, w, h);
    for (let i = 0; i < 38; i++) {
      const x = rand() * w, y = rand() * h, l = 10 + rand() * 18;
      const gr = ctx.createLinearGradient(x, y, x, y + l);
      gr.addColorStop(0, 'rgba(200,215,255,0)'); gr.addColorStop(1, 'rgba(210,225,255,0.95)');
      ctx.strokeStyle = gr; ctx.lineWidth = 1.4;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - 1, y + l); ctx.stroke();
    }
  }).clone();
  rainTex.wrapS = rainTex.wrapT = THREE.RepeatWrapping;
  rainTex.repeat.set(4, 1);
  rainTex.needsUpdate = true;
  const rainMat = new THREE.MeshBasicMaterial({ map: rainTex, color: '#AFC4FF', transparent: true, opacity: 0.7, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide });
  const rainGeo = new THREE.CylinderGeometry(0.8, 0.95, 1, 14, 1, true);
  rainGeo.translate(0, -0.5, 0);
  const rain = new THREE.Mesh(rainGeo, rainMat);
  rain.castShadow = false;
  root.add(rain);
  root.scale.setScalar(0.92);
  return { root, body, cloud, face, faceMat, glow, glowMat, rain, rainMat, rainTex };
}

// Jagged lightning: segments of thin cylinders along a jittered polyline (+ branches), merged, additive.
function boltGeometry(from, to, { jag = 0.18, segs = 12, width = 0.05, branches = 2, rand = Math.random } = {}) {
  const pts = [];
  const dir = _u.subVectors(to, from);
  const len = dir.length();
  const side = new THREE.Vector3(-dir.z, 0, dir.x).normalize();
  if (side.lengthSq() < 0.5) side.set(1, 0, 0);
  const side2 = new THREE.Vector3().crossVectors(dir, side).normalize();
  for (let i = 0; i <= segs; i++) {
    const k = i / segs;
    const p = from.clone().lerp(to, k);
    if (i > 0 && i < segs) p.addScaledVector(side, (rand() - 0.5) * 2 * jag * len / segs * 2.2).addScaledVector(side2, (rand() - 0.5) * 2 * jag * len / segs * 2.2);
    pts.push(p);
  }
  const geos = [];
  const seg = (a, b, w) => {
    const l = a.distanceTo(b);
    const c = new THREE.CylinderGeometry(w, w, l, 5, 1, true);
    c.translate(0, l / 2, 0);
    _q.setFromUnitVectors(new THREE.Vector3(0, 1, 0), _w.subVectors(b, a).normalize());
    c.applyQuaternion(_q);
    c.translate(a.x, a.y, a.z);
    geos.push(c);
  };
  for (let i = 0; i < pts.length - 1; i++) seg(pts[i], pts[i + 1], width * (1 - (i / pts.length) * 0.3));
  for (let b = 0; b < branches; b++) {
    const i0 = 2 + Math.floor(rand() * (segs - 4));
    let a = pts[i0];
    for (let k = 0; k < 3; k++) {
      const n = a.clone().addScaledVector(dir, (0.06 + rand() * 0.04)).addScaledVector(side, (rand() - 0.3) * len * 0.08).addScaledVector(side2, (rand() - 0.5) * len * 0.05);
      seg(a, n, width * 0.45);
      a = n;
    }
  }
  const g = mergeGeometries(geos, false);
  geos.forEach((x) => x.dispose());
  return g;
}

// Confetti cannon for the lighting grid (step 3): a striped barrel with a flared gold muzzle on a clamp post.
// Pivot at the origin; the post rises to the grid (+y); parts.barrel points along aimDir (its local +y).
function buildCannon(game, aimDir) {
  const g = K.prop('ee_confetti_cannon');
  const lac = K.mat(game, 'lacquer', '#ffffff', { keepColor: true });
  const metal = K.mat(game, 'metal', '#ffffff');
  const barrel = partGroup(g, 'barrel', [0, 0, 0]);
  const stripes = (y) => (Math.floor((y + 0.05) / 0.07) % 2 ? new THREE.Color('#E23B3B') : new THREE.Color('#F4F1E8'));
  const body = K.lathe([[0, -0.08], [0.1, -0.08], [0.11, -0.03], [0.1, 0.34], [0.13, 0.4], [0.155, 0.45], [0.11, 0.46], [0, 0.44]], { round: 0.012, seg: 18 }).clone();
  K.tint(body, (x, y) => (y > 0.35 ? new THREE.Color('#E8A92E') : stripes(y)));
  barrel.add(K.m(body, lac));
  barrel.add(tm(new THREE.TorusGeometry(0.105, 0.018, 6, 18).rotateX(Math.PI / 2), lac, '#E8A92E', { pos: [0, 0.06, 0] }));
  g.add(tm(sph(0.055, 12, 9), metal, '#3A3440', { pos: [0, 0, 0] }));
  g.add(tm(K.box(0.05, 0.34, 0.05, 0.012), metal, '#3A3440', { pos: [0, 0.2, 0] }));
  g.add(tm(K.box(0.16, 0.05, 0.1, 0.015), metal, '#3A3440', { pos: [0, 0.37, 0] }));
  K.finish(game, g, { ao: false });
  K.merge(barrel);
  barrel.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), aimDir);
  g.traverse((o) => { if (o.isMesh) o.castShadow = false; });
  return g;
}

// Applause hands (step 3): a lightweight white cartoon glove after props/machines.js buildGlove. Origin = wrist (top
// of the cuff), fingers +Y, palm -Z, thumb +X, three seams on the back (+Z). One non-indexed geometry with position,
// normal and colour; mirror = the other hand (x flipped, winding restored).
function gloveGeometry(mirror = false) {
  const W = '#FFFDF6', SEAM = '#C4B59B', CUFF = '#F3ECDD';
  const parts = [];
  const put = (geo, color, m) => {
    const g = geo.index ? geo.toNonIndexed() : geo.clone();
    if (m) g.applyMatrix4(m);
    for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal') g.deleteAttribute(k);
    K.tint(g, color);
    parts.push(g);
  };
  const at = (x, y, z, rx = 0, ry = 0, rz = 0) => new THREE.Matrix4().compose(new THREE.Vector3(x, y, z),
    new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz)), new THREE.Vector3(1, 1, 1));
  const ring = (r, n, y) => { const pts = []; for (let i = 0; i < n; i++) { const a = (i / n) * TAU; pts.push([Math.cos(a) * r, y, Math.sin(a) * r]); } return pts; };
  // cuff: flared bell, rolled lip, wrist band
  put(K.lathe([[0.058, 0.0], [0.062, -0.03], [0.073, -0.062], [0.085, -0.088]], { seg: 16 }), CUFF);
  put(K.tube(ring(0.084, 14, -0.088), 0.012, { seg: 16, radial: 5, closed: true }), W);
  put(K.tube(ring(0.059, 12, 0.0), 0.01, { seg: 14, radial: 4, closed: true }), W);
  // puffy palm + the three stitch lines on its back
  const palm = new THREE.SphereGeometry(1, 13, 9);
  palm.scale(0.088, 0.098, 0.056);
  palm.translate(0, 0.088, 0);
  put(palm, W);
  for (const x of [-0.034, 0, 0.034]) {
    const pts = [];
    for (let i = 0; i <= 6; i++) {
      const y = 0.035 + i * 0.017, nx = x / 0.088, ny = (y - 0.088) / 0.098;
      pts.push([x, y, 0.056 * Math.sqrt(Math.max(0.02, 1 - nx * nx - ny * ny)) + 0.002]);
    }
    put(K.tube(pts, 0.0045, { seg: 5, radial: 3 }), SEAM);
  }
  // fat sausage fingers from the knuckles (a little curled) + the thumb
  for (const [x, len, fan] of [[0.05, 0.078, -0.16], [0.0, 0.088, 0.0], [-0.05, 0.07, 0.17]]) {
    const cap = new THREE.CapsuleGeometry(0.031, len, 3, 9);
    cap.translate(0, len / 2 + 0.012, 0);
    const p = cap.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const k = 1 + 0.1 * Math.sin(clamp01(p.getY(i) / (len + 0.04)) * Math.PI);
      p.setX(i, p.getX(i) * k);
      p.setZ(i, p.getZ(i) * k);
    }
    cap.computeVertexNormals();
    put(cap, W, at(x, 0.155, 0, -0.12, 0, fan));
  }
  const th = new THREE.CapsuleGeometry(0.033, 0.058, 3, 9);
  th.translate(0, 0.045, 0);
  put(th, W, at(0.07, 0.07, -0.018, -0.35, 0.2, -0.95));
  const g = mergeGeometries(parts, false);
  parts.forEach((x) => x.dispose());
  if (mirror) {
    g.scale(-1, 1, 1);
    for (const a of Object.values(g.attributes)) {
      const n = a.itemSize, arr = a.array;
      for (let i = 0; i + 2 < a.count; i += 3) {
        for (let c = 0; c < n; c++) { const j = (i + 1) * n + c, k = (i + 2) * n + c, v = arr[j]; arr[j] = arr[k]; arr[k] = v; }
      }
    }
  }
  g.computeBoundingSphere();
  return g;
}

// Private CRT picture for VTR #2: the Sign-Off film with vertical roll, tearing and snow (GDD §13 step 5 part C).
class TrackingPicture {
  constructor(game) {
    this.game = game;
    const mk = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };
    this.W = 256; this.H = 192;
    this.film = mk(this.W, this.H);
    this.roll = mk(this.W, this.H);
    this.out = mk(this.W, this.H);
    this.snow = mk(this.W, this.H * 2);
    this.fctx = this.film.getContext('2d');
    this.rctx = this.roll.getContext('2d');
    this.octx = this.out.getContext('2d');
    const sctx = this.snow.getContext('2d');
    const img = sctx.createImageData(this.W, this.H * 2);
    for (let i = 0; i < img.data.length; i += 4) {
      const v = Math.random() < 0.5 ? 0 : 150 + Math.random() * 105;
      img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
      img.data[i + 3] = 255;
    }
    sctx.putImageData(img, 0, 0);
    this.texture = new THREE.CanvasTexture(this.out);
    this.texture.colorSpace = THREE.SRGBColorSpace;
    this.texture.name = 'egg.vtr2_picture';
    this.phase = 0;
    this.t = 0;
    this.acc = 1;
    this.filmT = 0;
    this.d = 6;
  }

  update(dt, d, visible) {
    this.t += dt;
    this.filmT += dt;
    this.d = d;
    this.phase = (this.phase + dt * 0.5 * d) % 1;
    this.acc += dt;
    if (!visible || this.acc < 1 / 15) return;
    this.acc = 0;
    const { W, H } = this;
    const cards = this.game.cards;
    try { cards?.drawTo?.(this.fctx, 'signoff_film', W, H, this.filmT % 20); } catch { this.fctx.fillStyle = '#223'; this.fctx.fillRect(0, 0, W, H); }
    const k = d / 6;
    // vertical roll: the frame slides up with the black blanking bar between two copies
    const bar = Math.round(H * 0.09);
    const off = Math.round(this.phase * (H + bar));
    const r = this.rctx;
    r.fillStyle = '#050308';
    r.fillRect(0, 0, W, H);
    r.drawImage(this.film, 0, -off);
    r.drawImage(this.film, 0, H + bar - off);
    // tearing: horizontal bands shifted by a wobbling sine (amplitude d/6)
    const o = this.octx;
    o.fillStyle = '#050308';
    o.fillRect(0, 0, W, H);
    const bands = 24, bh = H / bands;
    for (let i = 0; i < bands; i++) {
      const y = i * bh;
      const tear = k * (Math.sin(y * 0.071 + this.t * 7.3) * 0.11 + Math.sin(y * 0.23 + this.t * 17.0) * 0.05 + (Math.random() < 0.08 * k ? (Math.random() - 0.5) * 0.4 : 0));
      o.drawImage(this.roll, 0, y, W, bh + 1, tear * W, y, W, bh + 1);
    }
    // snow + a dimming/chroma wash
    if (k > 0.001) {
      o.globalAlpha = Math.min(0.85, k * 0.9);
      o.globalCompositeOperation = 'lighter';
      o.drawImage(this.snow, 0, -Math.floor(Math.random() * H));
      o.globalCompositeOperation = 'source-over';
      o.globalAlpha = k * 0.25;
      o.fillStyle = '#20183A';
      o.fillRect(0, 0, W, H);
      o.globalAlpha = 1;
    }
    this.texture.needsUpdate = true;
  }
}

// ============================================================================================== the easter egg
export class EasterEgg {
  constructor(game) {
    this.game = game;
    this.step = 0;
    this.done = false;
    this.forceForecaster = false;
    this.storm = null;
    this.applause = 0;
    this.hasTape = false;
    this.carried = [];
    this.puppets = {};
    this._jobs = [];
    this._handles = [];
    this._magFall = [];
    this._cannons = [];
    this._built = false;
    this._emitting = false;
    this._bars = [];
    this._barFrame = -1;
    this._crumbs = [];
    this._crumbT = 0;
    this._laughs = 0;
    this._claps = [];          // live applause-hand pairs (step 3)
    this._clapPool = [];
    this._hands = null;        // { mat, l, r } the two glove InstancedMeshes
  }

  get stormActive() { return !!(this.storm && this.storm.active); }

  // ------------------------------------------------------------------------------------------ lifecycle
  init() {
    const g = this.game;
    try { this._build(); } catch (err) { console.warn('[egg] build', err); }
    const ev = g.events;
    ev.on('zombie:kill', (e) => this._onKill(e));
    ev.on('zombie:forecaster_storm', (e) => this._onForecasterStorm(e));
    ev.on('machine:telly_take', (e) => this._onTellyTake(e));
    ev.on('egg:step', (e) => { if (!this._emitting && e && e.step > this.step) this._mirror(e.step | 0); });
    ev.on('egg:complete', () => { if (!this._emitting && !this.done) { this.step = STEP_IDS.length; this.done = true; } });
    this._registerAll();
  }

  reset() {
    this._jobs.length = 0;
    this.step = 0;
    this.done = false;
    this.forceForecaster = false;
    this.applause = 0;
    this.hasTape = false;
    this.carried = [];
    this._bars.length = 0;
    this._barFrame = -1;
    this._crumbs.length = 0;
    this._laughs = 0;
    this._killSwitchUsed = false;
    this._signMode = 'off';
    this._signSolidT = 0;
    this._toteTwitchT = 3;
    this._toteTwitchBack = -1;
    this._mapBlink = false;
    this._rumbleT = 20;
    this._onAirT = -1;
    this._whiteT = -1;
    this._cageT = -1;
    this._switchT = -1;
    this._song = null;
    this._socks = [];
    this._storm2 = null;
    this._removeStorm(true);
    this._stopTracking();
    this._track = null;
    this._removeOutline();
    this._magFall.length = 0;
    this._clearClaps();
    this._handles?.forEach((h) => { try { h?.cancel?.(); } catch { /* ignore */ } });
    this._handles = [];
    try { this._alarm?.stop?.(0.1); } catch { /* ignore */ }
    this._alarm = null;
    if (!this._built) return;
    for (const p of Object.values(this.puppets)) this._resetPuppet(p);
    this._restoreMap();
    for (const c of this._cannons) { c.kick = -1; c.parts.barrel.position.set(0, 0, 0); }
    try { this.game.screens?.setSource?.('scr_vtr2', null); } catch { /* ignore */ }
    this._registerAll();
  }

  warmup() {
    if (!this._built) return null;
    const out = [];
    for (const p of Object.values(this.puppets)) { const c = cloneBare(p.model); c.traverse((o) => o.layers.set(0)); out.push(c); }
    const st = buildStorm(this.game);
    out.push(st.root);
    const b = new THREE.Mesh(boltGeometry(new THREE.Vector3(0, 3, 0), new THREE.Vector3(0, 0, 0)), this._boltMat());
    out.push(b);
    // the applause gloves' program (instanced + the per-instance fade): same geometry, a 1-instance sample
    if (this._hands) {
      const s = new THREE.InstancedMesh(this._hands.l.geometry, this._hands.mat, 1);
      s.setMatrixAt(0, _m4.identity());
      s.frustumCulled = false;
      out.push(s);
    }
    return out;
  }

  update(dt) {
    if (!this._built) return;
    const g = this.game;
    const rdt = g.time.realDt || dt;
    // scheduled beats (world time: they hold during commercials / time.scale 0)
    if (this._jobs.length && dt > 0) {
      for (let i = this._jobs.length - 1; i >= 0; i--) {
        const j = this._jobs[i];
        j.t -= dt;
        if (j.t <= 0) { this._jobs.splice(i, 1); try { j.fn(); } catch (err) { console.warn('[egg] job', err); } }
      }
    }
    this._updatePuppets(dt);
    this._updateSong(dt);
    this._updateSocks(dt);
    this._updateApplauseProps(dt);
    this._updateMap(dt);
    this._updateStorm(dt);
    this._updateTracking(dt);
    this._updateYard(dt, rdt);
    this._updatePost(rdt);
    this._updateClaps(rdt);
  }

  // ------------------------------------------------------------------------------------------ helpers
  get O() { return this.game.level?.objects || {}; }
  get powered() { return !!this.game.machines?.powerOn; }
  _later(t, fn) { this._jobs.push({ t, fn }); }
  _play(id, o = {}) { try { return this.game.audio?.play?.(id, o) || null; } catch { return null; } }
  _areaRoot(area) { return this.game.level?.areaRoots?.[area] || this.game.scene; }
  _emit(name, payload) {
    this._emitting = true;
    try { this.game.events.emit(name, payload); } finally { this._emitting = false; }
  }

  _override(source, groups, seconds, priority) {
    try {
      const h = this.game.screens?.override?.(source, groups, seconds, priority);
      if (h) this._handles.push(h);
      return h;
    } catch (err) { console.warn('[egg] override', err); return null; }
  }

  _tvSound(id, o = {}) {
    const s = this.game.screens;
    try { if (s?.speaker) return s.speaker(id, o); } catch { /* ignore */ }
    return this._play(id, o);
  }

  _baronLaugh() {
    const n = ++this._laughs;
    this._tvSound('baron_laugh', { near: 2, rate: 1 + 0.07 * n, detune: 40 * n, vol: 0.85 + 0.1 * n });
  }

  // Common completion beats of steps 1–5 (GDD §13 "Every completed step also triggers").
  _celebrate(n, { laugh = 1.6, box = 3.0 } = {}) {
    const g = this.game;
    this._play('sting_ee_correct');
    try { g.economy?.add?.(T.points.eeStep, 'egg'); } catch (err) { console.warn('[egg] points', err); }
    if (laugh >= 0) this._later(laugh, () => this._baronLaugh());
    if (box >= 0) this._later(box, () => this._play(`sting_ee_${n}`));
  }

  // step n completed (n = 1..5): the state change + egg:step (MC card, neon, beacons, Telly react to it)
  _complete(n) {
    if (this.step !== n - 1) return false;
    this.step = n;
    this._emit('egg:step', { step: n });
    return true;
  }

  // someone else (the boss) advanced the egg: keep our state in sync
  _mirror(n) {
    const tgt = Math.min(STEP_IDS.length, n);
    while (this.step < tgt) { this.step++; this._applyInstant(this.step); }
    if (this.step >= STEP_IDS.length && !this.done) this.done = true;
  }

  // ------------------------------------------------------------------------------------------ debug jumps
  setStep(n) {
    const target = Math.max(0, Math.min(STEP_IDS.length, Math.floor(n)));
    if (target < this.step) {
      // backwards: rebuild the world from scratch, then replay forward silently
      const keep = this.game.economy?.points;
      this.reset();
      if (keep !== undefined && this.game.economy) this.game.economy.points = keep;
    }
    while (this.step < target) {
      this.step++;
      this._applyInstant(this.step);
      this._emit('egg:step', { step: this.step });
      this._applyHook(this.step);
    }
    this.step = target;
    if (target === STEP_IDS.length && !this.done) {
      this.done = true;
      this._emit('egg:complete', {});
    }
    return this.step;
  }

  // the end state of step k, applied instantly (debug jumps and mirrored steps)
  _applyInstant(k) {
    const O = this.O;
    if (k === 1) {
      O.neon_logo?.setState?.('lit');
      O.booth_on_air?.set?.(true);
    } else if (k === 2) {
      for (const p of Object.values(this.puppets)) this._placeOnStage(p);
      O.ee_puppet_theater?.setOpen?.(1, 0);
    } else if (k === 3) {
      this.applause = E.applauseKills;
      O.ee_tote_board?.setValue?.(TOTE_BASE + E.applauseKills);
      this._signMode = 'locked';
      O.ee_applause_sign?.setLit?.(true);
      this._moveMagnets(0);
    } else if (k === 4) {
      this.forceForecaster = false;
      this._removeStorm(true);
      this._mapBlink = false;
      this._restoreMapTower();
    } else if (k === 5) {
      const vtr = O.ee_vtr2;
      if (vtr && !vtr.loaded) vtr.loadTape?.(0.2);
      vtr?.setLamp?.('green', false);
      this.hasTape = false;
      this._stopTracking();
      try { this.game.screens?.setSource?.('scr_vtr2', 'signoff_film'); } catch { /* ignore */ }
      this._openCage(true);
    }
  }

  // the hook toward step k+1 that a debug jump should leave running
  _applyHook(k) {
    if (k === 1) for (const p of Object.values(this.puppets)) if (p.state === 'dormant') this._ghost(p);
    if (k === 2) this._signMode = 'flicker';
    if (k === 3) { this.forceForecaster = true; this._mapBlink = true; this._rumbleT = 20; }
  }

  // ================================================================================================ build
  _build() {
    const g = this.game;
    this._tmpBox = new THREE.Box3();
    // puppets
    const builders = { dragon: buildDudley, sock: buildSockrates, owl: buildHootie };
    for (const def of PUPPETS) {
      const model = builders[def.key](g);
      const root = new THREE.Group();
      root.name = def.id;
      const pivot = new THREE.Group();
      root.add(pivot);
      pivot.add(model);
      const p = { ...def, model, root, pivot, parts: model.userData.parts, state: 'dormant', t: 0, giggleT: 14, home: v3(def.home),
        drop: v3(def.drop), pos: new THREE.Vector3(), blob: null, from: new THREE.Vector3(), to: new THREE.Vector3(),
        fromQ: new THREE.Quaternion(), toQ: new THREE.Quaternion(), fromS: 1, toS: 1, dur: 0, hanger: null, phase: Math.random() * TAU,
        gs: GHOST[def.key].scale, face: 0, looks: [], look: null, hopT: 2, hopK: -1, hopSpin: false };
      // on-air look: every toon mesh gets a warm-rim variant of its felt/plastic (same programs, uniforms only)
      model.traverse((o) => { if (o.isMesh && o.material?.userData?.daToon) p.looks.push(o, o.material, g.mats.variant(o.material, GHOST_LOOK)); });
      this.puppets[def.id] = p;
    }
    this._resolveHomes();
    for (const p of Object.values(this.puppets)) p.face = this._faceYaw(p);
    try { this._buildHands(); } catch (err) { console.warn('[egg] applause hands', err); this._hands = null; }
    // confetti cannons on the Studio A lighting grid (visible from the start, dormant)
    this._cannons = [];
    for (const c of CANNONS) {
      const dir = new THREE.Vector3(...c.aim).sub(new THREE.Vector3(...c.pos)).normalize();
      const m = buildCannon(g, dir);
      m.position.set(...c.pos);
      this._areaRoot('studio_a').add(m);
      m.updateMatrixWorld(true);
      this._cannons.push({ group: m, parts: m.userData.parts, kick: -1, dir });
    }
    // weather-map magnet rest poses (restored on a new game)
    this._mapRest = null;
    const map = this.O.ee_weather_map;
    if (map?.parts) {
      this._mapRest = {};
      for (const [k, m] of Object.entries(map.parts)) if (m) this._mapRest[k] = { p: m.position.clone(), r: m.rotation.clone(), v: m.visible };
    }
    // VTR #2 picture
    this._picture = new TrackingPicture(g);
    this._built = true;
    for (const p of Object.values(this.puppets)) this._resetPuppet(p);
  }

  _resolveHomes() {
    const O = this.O, A = this.game.level?.anchors || {};
    const P = this.puppets;
    const tc = O.ee_trophy_case;
    if (tc?.dudley) P.ee_puppet_dudley.home.copy(tc.dudley);
    else if (A.ee_puppet_dudley?.pos) P.ee_puppet_dudley.home.copy(A.ee_puppet_dudley.pos);
    // the bigger on-air Dudley stands on the case's middle glass shelf (he fits under the lit crown)
    P.ee_puppet_dudley.home.y = (tc?.group ? tc.group.getWorldPosition(_w).y : 0) + DUDLEY_SHELF;
    if (A.ee_puppet_dudley?.drop) P.ee_puppet_dudley.drop.set(...A.ee_puppet_dudley.drop);
    const desk = O.ee_anchor_desk;
    if (desk?.top) P.ee_puppet_sockrates.home.set(...desk.top);
    if (desk?.drop) P.ee_puppet_sockrates.drop.set(...desk.drop);
    const wheel = O.ee_prize_wheel;
    if (wheel?.puppetSeat) P.ee_puppet_hootie.home.copy(wheel.puppetSeat);
    if (A.ee_puppet_hootie?.drop) P.ee_puppet_hootie.drop.set(...A.ee_puppet_hootie.drop);
    // drops land on the real floor
    const col = this.game.level?.col;
    for (const p of Object.values(P)) {
      const y = col?.floorAt?.(p.drop.x, p.drop.z, p.drop.y + 0.8);
      if (Number.isFinite(y)) p.drop.y = y;
    }
  }

  // ================================================================================================ interactables
  _registerAll() {
    const g = this.game;
    if (!this._built) return;
    const W = g.weapons, I = g.interact;
    // step 1: the four chime bars
    for (const c of BARS) {
      W?.registerShootable?.({
        id: `ee_bar_${c}`,
        raycast: (o, d, max) => this._barRay(c, o, d, max),
        onHit: (info) => this._onBarHit(c, info),
      });
    }
    // step 2: the ghost puppets
    for (const p of Object.values(this.puppets)) {
      W?.registerShootable?.({ id: p.id, raycast: (o, d, max) => this._puppetRay(p, o, d, max), onHit: (info) => this._onPuppetHit(p, info) });
      I?.register?.({
        id: `ee_pickup_${p.key}`, pos: p.drop, radius: 1.2, height: 2.2,
        enabled: () => p.state === 'ground', prompt: () => (p.state === 'ground' ? {} : null), use: () => this._pickup(p),
      });
    }
    const th = this.O.ee_puppet_theater;
    I?.register?.({
      id: 'ee_puppet_theater', pos: th?.interact || new THREE.Vector3(17.75, 0, -24.9), radius: th?.interactR ?? 1.5, height: 2.5,
      enabled: () => this.carried.length > 0, prompt: () => (this.carried.length > 0 ? {} : null), use: () => this._slotAll(),
    });
    // step 5: VTR #2 load + the TRACKING knob
    const vtr = this.O.ee_vtr2;
    const vtrPos = vtr?.group ? vtr.group.getWorldPosition(new THREE.Vector3()).setY(1.0) : VTR_FALLBACK.clone();
    this._vtrPos = vtrPos;
    I?.register?.({
      id: 'ee_vtr2', pos: vtrPos, radius: 1.5, height: 2.4,
      enabled: () => this.hasTape && this.step === 4 && !this._track, prompt: () => (this.hasTape && this.step === 4 && !this._track ? {} : null),
      use: () => this._loadTape(),
    });
    const knob = this.O.ee_tracking_knob;
    const knobPos = knob?.pos ? knob.pos.clone() : KNOB_FALLBACK.clone();
    this._knobPos = knobPos;
    I?.register?.({
      id: 'ee_tracking_knob', pos: knobPos, radius: 1.5, height: 2.4,
      enabled: () => this.powered && !(this.hasTape && this.step === 4 && !this._track), prompt: () => (this.powered ? {} : null),
      use: () => this._turnKnob(),
    });
    // step 6 trigger: the kill switch (key-only hold)
    const ks = this.O.ee_kill_switch;
    const ksPos = ks?.interact ? ks.interact.clone() : new THREE.Vector3(45, 1.2, -9.0);
    I?.register?.({
      id: 'ee_kill_switch', pos: ksPos, radius: 1.5, height: 2.6, hold: E.switchHold,
      enabled: () => this.step === 5 && !this._killSwitchUsed, prompt: () => (this.step === 5 && !this._killSwitchUsed ? { hold: E.switchHold } : null),
      use: () => this._throwSwitch(),
    });
  }

  // ================================================================================================ STEP 1: chimes
  // The chime_rack prop's collider box sits ~0.3 m in front of the bars and stops bullets. A ray that (extended) hits
  // the real bar capsule (radius BAR_R, a little fat so the muzzle ray, which diverges from the crosshair ray, still
  // agrees) is reported where it reaches the plane BAR_PUSH in front of the bars: in front of the collider, so the
  // crosshair point and the bullet from the muzzle (aimed at that point) both land on the bar the player aimed at.
  _barRay(color, o, d, max) {
    const rack = this.O.ee_chime_rack;
    const b = rack?.bars?.[color];
    if (!b) return null;
    if (!this._rackFront) {
      const q = rack.group?.getWorldQuaternion?.(new THREE.Quaternion());
      this._rackFront = new THREE.Vector3(0, 0, -1).applyQuaternion(q || new THREE.Quaternion());
    }
    const top = b.top(), bot = b.bottom();
    let t = rayCapsule(o, d, top, bot, BAR_R);
    if (t < 0) return null;
    const f = this._rackFront, dn = d.dot(f);
    if (dn < -1e-4) {
      const tp = (top.x + f.x * BAR_PUSH - o.x) * f.x + (top.y + f.y * BAR_PUSH - o.y) * f.y + (top.z + f.z * BAR_PUSH - o.z) * f.z;
      const tf = tp / dn;
      if (tf > 0 && tf < t) t = Math.max(0.01, tf - 0.02);
    }
    return t <= max ? { dist: t, point: o.clone().addScaledVector(d, t) } : null;
  }

  _onBarHit(color, info = {}) {
    const g = this.game;
    if (IGNORED_CAUSES.has(info.cause)) return;
    if (this._barFrame === g.time.frame) return;          // at most one bar per shot event
    this._barFrame = g.time.frame;
    const bar = this.O.ee_chime_rack?.bars?.[color];
    const pos = bar ? bar.top().lerp(bar.bottom(), 0.6) : new THREE.Vector3(-6.6, 1.6, -4.5);
    if (!this.powered) {
      this._play('ee_chime_tunk', { pos });
      this.O.ee_chime_rack?.swing?.(color, 0.35, info.dir || null);
      return;
    }
    this._play(`ee_chime_${color}`, { pos });
    this._emit('egg:chime', { bar: color });
    const now = g.time.now;
    this._bars.push({ bar: color, t: now });
    if (this._bars.length > 4) this._bars.shift();
    if (this.step !== 0 || this._bars.length < 4) return;
    for (let i = 0; i < 4; i++) {
      if (this._bars[i].bar !== E.chimeOrder[i]) return;
      if (i > 0 && this._bars[i].t - this._bars[i - 1].t > E.chimeGap) return;
    }
    this._bars.length = 0;
    this._completeStation();
  }

  _completeStation() {
    if (!this._complete(1)) return;
    this._override('station_id', ALL_TV, 3, PRI.ee);
    this._play('sting_round_start', { delay: 0.25 });
    this.O.neon_logo?.fix?.();
    this.O.booth_on_air?.set?.(true);
    this._celebrate(1, { laugh: 2.2, box: 3.6 });
    // hook: the ghost puppets start to exist; Dudley giggles from the "empty" case
    this._later(3.1, () => { for (const p of Object.values(this.puppets)) if (p.state === 'dormant') this._ghost(p); });
    this._later(3.2, () => this.game.screens?.zoomFeed?.('lobby', 9, { zoom: 5 }));      // the booth monitor: Dudley, big
    this._later(4.4, () => this._giggle(this.puppets.ee_puppet_dudley, true));
  }

  // ================================================================================================ STEP 2: puppets
  _resetPuppet(p) {
    this._setPuppetLayer(p, LAYERS.TV_ONLY);
    p.state = 'dormant';
    p.t = 0;
    p.root.visible = false;
    p.blob?.remove?.();
    p.blob = null;
    p.hanger = null;
    p.model.scale.setScalar(1);
    p.model.rotation.set(0, p.face, 0);
    p.pivot.position.set(0, 0, 0);
    p.pivot.rotation.set(0, 0, 0);
    p.hopK = -1;
    p.hopT = 1.2 + Math.random() * 2.5;
    const root = this._areaRoot(p.area);
    root.add(p.root);
    this._setWorld(p.root, p.home, p.rotY, p.gs);
    this._setLook(p, true);
    this._poseParts(p, 0, 0, 0);
  }

  // on-air (ghost) look on / off: the warm-rim material variants built in _build
  _setLook(p, on) {
    if (p.look === on) return;
    p.look = on;
    const L = p.looks;
    for (let i = 0; i < L.length; i += 3) L[i].material = on ? L[i + 2] : L[i + 1];
  }

  // model yaw (relative to the puppet's rotY) that turns an on-air ghost toward its feed camera
  _faceYaw(p) {
    const a = this.game.level?.anchors?.[`feed_cam_${p.area}`];
    if (!a?.pos) return 0;
    const yaw = Math.atan2(-(a.pos.x - p.home.x), -(a.pos.z - p.home.z));
    return Math.atan2(Math.sin(yaw - p.rotY), Math.cos(yaw - p.rotY));
  }

  _setWorld(obj, pos, rotY, scale) {
    const parent = obj.parent;
    obj.position.copy(pos);
    if (parent) { parent.updateMatrixWorld(true); _w.copy(pos); parent.worldToLocal(obj.position.copy(_w)); }
    obj.rotation.set(0, rotY, 0);
    obj.scale.setScalar(scale);
  }

  _setPuppetLayer(p, layer) {
    if (p.layer === layer) return;
    p.layer = layer;
    p.root.traverse((o) => o.layers.set(layer));
  }

  _poseParts(p, jaw, armL, armR) {
    const P = p.parts;
    if (P.jaw) P.jaw.rotation.x = -jaw;
    if (P.armL) P.armL.rotation.z = -armL;
    if (P.armR) P.armR.rotation.z = armR;
  }

  _ghost(p) {
    this._resetPuppet(p);
    p.state = 'ghost';
    p.root.visible = true;
    p.giggleT = 6 + Math.random() * 8;
  }

  _giggle(p, force = false) {
    if (!p) return;
    const pl = this.game.player;
    _v.copy(p.home).y += PUPPET_CENTER * p.gs;
    if (!force && pl && pl.pos.distanceTo(_v) > 10) return;
    this._play('ee_puppet_giggle', { pos: _v.clone(), range: 12 });
  }

  _puppetRay(p, o, d, max) {
    if (p.state !== 'ghost') return null;
    // hit sphere r = T.ee.puppetR around the puppet, nudged along its facing (Dudley: out through the case glass,
    // whose collider would otherwise stop oblique shots before they reach the sphere)
    const c = _v.set(-Math.sin(p.rotY), 0, -Math.cos(p.rotY)).multiplyScalar(p.shift || 0).add(p.home);
    c.y += PUPPET_CENTER * p.gs;
    const r = E.puppetR;
    const oc = _w.subVectors(o, c);
    const b = oc.dot(d);
    const cc = oc.lengthSq() - r * r;
    const disc = b * b - cc;
    if (disc < 0) return null;
    let t = -b - Math.sqrt(disc);
    if (t < 0) t = -b + Math.sqrt(disc);
    if (t < 0) return null;
    if (t > max) return null;
    return { dist: t, point: o.clone().addScaledVector(d, t) };
  }

  _onPuppetHit(p, info = {}) {
    if (p.state !== 'ghost' || IGNORED_CAUSES.has(info.cause)) return;
    p.state = 'tuning';
    p.t = 0;
    _v.copy(p.home).y += PUPPET_CENTER * p.gs;
    this.game.fx?.burst?.(_v, { shape: 'static', count: 26, speed: 1.6, size: 0.07, life: 0.45, gravity: 0 });
    this._play('zmb_death_static', { pos: _v.clone(), vol: 0.6 });
  }

  _pickup(p) {
    if (p.state !== 'ground') return;
    const pl = this.game.player;
    const belt = pl?.hero?.slots?.belt;
    p.blob?.remove?.();
    p.blob = null;
    p.state = 'carried';
    if (!this.carried.includes(p.id)) this.carried.push(p.id);
    if (belt) {
      const [x, y, z, ry] = HANG[p.key];
      const hanger = new THREE.Group();
      hanger.name = `hang_${p.key}`;
      hanger.position.set(x, y, z);
      belt.add(hanger);
      p.hanger = hanger;
      hanger.add(p.root);
      p.root.position.set(0, -0.25 * HANG_SCALE, 0);
      p.root.rotation.set(0, ry, 0);
      p.root.scale.setScalar(HANG_SCALE);
      this._setPuppetLayer(p, 0);
    } else {
      p.root.visible = false;
    }
    this._play('costume_pop', { pos: pl ? pl.pos.clone() : undefined, vol: 0.7 });
    this._play('ee_puppet_giggle', { pos: pl ? pl.pos.clone() : undefined, vol: 0.5, delay: 0.15 });
  }

  _slotAll() {
    const th = this.O.ee_puppet_theater;
    if (!th || !this.carried.length) return;
    const ids = this.carried.slice();
    this.carried.length = 0;
    const root = this._areaRoot('studio_b');
    ids.forEach((id, i) => {
      const p = this.puppets[id];
      if (!p) return;
      p.root.updateMatrixWorld(true);
      p.root.getWorldPosition(p.from);
      p.root.getWorldQuaternion(p.fromQ);
      p.fromS = HANG_SCALE;
      root.attach(p.root);
      p.hanger?.removeFromParent();
      p.hanger = null;
      p.root.visible = true;
      p.to.copy(th.slots?.[p.key] || th.interact);
      p.toQ.setFromEuler(new THREE.Euler(0, Math.PI, 0));
      p.toS = 1;
      p.dur = 0.55;
      p.t = -i * 0.18;
      p.state = 'flying';
    });
    this._play('telly_thwip', { pos: th.interact, vol: 0.6 });
  }

  _landSlot(p) {
    const th = this.O.ee_puppet_theater;
    p.state = 'slotted';
    p.t = 0;
    th?.setSlot?.(p.key, true);
    this._play('costume_pop', { pos: p.to, vol: 0.8 });
    this._emit('egg:puppet_slot', { id: p.id });
    const all = Object.values(this.puppets).every((q) => q.state === 'slotted');
    if (all && this.step === 1) this._completePuppets();
  }

  _placeOnStage(p) {
    const th = this.O.ee_puppet_theater;
    p.blob?.remove?.();
    p.blob = null;
    p.hanger?.removeFromParent();
    p.hanger = null;
    const root = this._areaRoot('studio_b');
    root.add(p.root);
    this._setPuppetLayer(p, 0);
    this._setLook(p, false);
    p.model.scale.setScalar(1);
    p.model.rotation.set(0, 0, 0);
    p.root.visible = true;
    th?.setSlot?.(p.key, true);
    const pos = th?.stage?.[p.key] || th?.slots?.[p.key] || STUDIO_B_C;
    this._setWorld(p.root, pos, Math.PI, 1);
    p.state = 'stage';
    this.carried = this.carried.filter((id) => id !== p.id);
  }

  _completePuppets() {
    if (!this._complete(2)) return;
    const th = this.O.ee_puppet_theater;
    this._celebrate(2, { laugh: 7.6, box: 8.6 });
    th?.setOpen?.(1, 0.8);
    this._song = { t: 0, clapped: false };
    // every puppet hops up behind the playboard
    Object.values(this.puppets).forEach((p, i) => {
      p.root.getWorldPosition(p.from);
      p.to.copy(th?.stage?.[p.key] || p.from);
      p.dur = 0.45;
      p.t = -0.35 - i * 0.12;
      p.state = 'hop';
    });
    this._later(0.55, () => this._play('ee_kazoo_song', { pos: th?.interact || STUDIO_B_C, range: 45 }));
    this._later(0.7, () => this._popSocks());
  }

  _popSocks() {
    const Z = this.game.zombies;
    if (!Z?.alive) return;
    this._socks = [];
    let i = 0;
    for (const z of Z.alive) {
      if (z.type !== 'sock_hopper' || z.dead) continue;
      try { Z.stun?.(z, 2.5); } catch { /* ignore */ }
      this._socks.push({ z, t: -0.25 - i * 0.12 - Math.random() * 0.2 });
      i++;
    }
  }

  _updateSocks(dt) {
    if (!this._socks.length) return;
    const Z = this.game.zombies;
    for (let i = this._socks.length - 1; i >= 0; i--) {
      const s = this._socks[i];
      const z = s.z;
      if (!z || z.dead || z.removed) { this._socks.splice(i, 1); continue; }
      s.t += dt;
      // freeze + turn toward Studio B
      const yaw = Math.atan2(-(STUDIO_B_C.x - z.pos.x), -(STUDIO_B_C.z - z.pos.z));
      z.yaw += Math.atan2(Math.sin(yaw - z.yaw), Math.cos(yaw - z.yaw)) * Math.min(1, dt * 8);
      if (z.group) z.group.rotation.y = z.yaw;
      if (z.vel) z.vel.set(0, 0, 0);
      if (s.t >= 0.9) {
        _v.copy(z.pos); _v.y += (z.height || 1) * 0.5;
        this.game.fx?.burst?.(_v, { shape: 'confetti', count: 40, speed: 4.5, size: 0.08, life: 1.3, gravity: 5, colors: RAINBOW });
        this.game.fx?.burst?.(_v, { shape: 'star', count: 8, speed: 2.5, size: 0.1, life: 0.6 });
        this._play('sock_boing', { pos: _v.clone(), rate: 1.3 });
        try { Z.kill?.(z, { cause: 'egg', points: false, corpse: false }); } catch (err) { console.warn('[egg] sock pop', err); }
        this._socks.splice(i, 1);
      }
    }
  }

  _updateSong(dt) {
    const s = this._song;
    if (!s) return;
    s.t += dt;
    if (!s.clapped && s.t >= 6.9) {
      s.clapped = true;
      this._play('ee_clap_single', { pos: STUDIO_A_CLAP, range: 30, wet: 0.8 });
      this._signMode = 'flicker';
      this._toteTwitchT = 1.2;
    }
    if (s.t > 7.6) this._song = null;
  }

  _updatePuppets(dt) {
    const t = this.game.time.now;
    for (const p of Object.values(this.puppets)) {
      switch (p.state) {
        case 'ghost': {
          // on-air performance (feeds only): bob + sway, a big wave (Sockrates: head bobs), jaw chatter, and every
          // 2.4-5 s a squash-and-stretch hop with the arms up (30 %: a twirl)
          const ph = t + p.phase;
          const G = GHOST[p.key];
          let hop = 0, sq = 0, spin = 0, up = 0;
          if (p.hopK < 0) {
            p.hopT -= dt;
            if (p.hopT <= 0) { p.hopK = 0; p.hopSpin = Math.random() < GHOST_HOP.spin; }
          }
          if (p.hopK >= 0) {
            p.hopK += dt / GHOST_HOP.dur;
            const k = Math.min(1, p.hopK);
            if (k < 0.2) sq = -0.16 * Math.sin((k / 0.2) * Math.PI);                     // crouch
            else if (k < 0.8) {                                                          // up: stretch, arms up
              const u = (k - 0.2) / 0.6;
              hop = Math.sin(u * Math.PI) * G.hop;
              sq = 0.12 * Math.sin(u * Math.PI);
              up = Math.sin(u * Math.PI);
              if (p.hopSpin) spin = TAU * easeInOut(u);
            } else sq = -0.13 * Math.sin(((k - 0.8) / 0.2) * Math.PI);                  // land
            if (p.hopK >= 1) { p.hopK = -1; p.hopT = GHOST_HOP.every[0] + Math.random() * (GHOST_HOP.every[1] - GHOST_HOP.every[0]); }
          }
          sq *= G.sq;
          p.pivot.position.y = Math.abs(Math.sin(ph * 3.4)) * G.bob + hop;
          p.pivot.rotation.z = Math.sin(ph * 1.9) * (p.key === 'sock' ? 0.2 : 0.14);
          p.pivot.rotation.x = Math.sin(ph * 2.3) * 0.06;
          p.model.rotation.y = p.face + Math.sin(ph * 0.8) * 0.18 + spin;
          p.model.scale.set(1 - sq * 0.5, 1 + sq, 1 - sq * 0.5);
          const jaw = 0.1 + Math.max(0, Math.sin(ph * 6.3)) * 0.34 + up * 0.2;
          this._poseParts(p, jaw, 0.55 + Math.sin(ph * 2.2) * 0.35 + up * 1.7, 1.85 + Math.sin(ph * 10.5) * 0.7 + up * 0.5);
          p.giggleT -= dt;
          if (p.giggleT <= 0) { p.giggleT = 12 + Math.random() * 8; this._giggle(p); }
          break;
        }
        case 'tuning': {
          p.t += dt;
          const on = Math.floor(p.t / 0.05) % 2 === 0;
          this._setPuppetLayer(p, on ? 0 : LAYERS.TV_ONLY);
          p.pivot.position.x = (Math.random() - 0.5) * 0.04;
          p.model.scale.set(1 + (Math.random() - 0.5) * 0.12, 1 + (Math.random() - 0.5) * 0.12, 1);
          if (p.t >= 0.4) this._revealPuppet(p);
          break;
        }
        case 'falling': {
          p.t += dt;
          const k = clamp01(p.t / p.dur);
          _v.lerpVectors(p.from, p.to, k);
          _v.y += Math.sin(k * Math.PI) * 0.45;
          // tumbling out of the feed and into the room: back to 1x and facing its drop direction
          const e = easeInOut(k);
          this._setWorld(p.root, _v, p.rotY, 1 + (p.gs - 1) * (1 - e));
          p.model.rotation.y = p.face * (1 - e);
          p.pivot.rotation.x = (p.key === 'dragon' ? -TAU : -Math.PI * 0.5) * easeInOut(k) * (k < 1 ? 1 : 0);
          p.pivot.rotation.z = Math.sin(k * Math.PI) * 0.4;
          if (k >= 1) {
            p.model.rotation.y = 0;
            p.pivot.rotation.set(0, 0, 0);
            p.state = 'landing';
            p.t = 0;
            this.game.fx?.burst?.(p.to, { shape: 'puff', count: 6, speed: 0.8, size: 0.12, life: 0.5, color: '#E8DCCB' });
            p.blob = this.game.fx?.blob?.(p.root, 0.22) || null;
          }
          break;
        }
        case 'landing': {
          p.t += dt;
          const k = clamp01(p.t / 0.5);
          const sq = Math.sin(k * Math.PI * 2.5) * (1 - k) * 0.25;
          p.model.scale.set(1 + sq, 1 - sq, 1 + sq);
          p.pivot.position.set(0, Math.abs(Math.sin(k * Math.PI * 2)) * 0.12 * (1 - k), 0);
          if (k >= 1) { p.model.scale.setScalar(1); p.pivot.position.set(0, 0, 0); p.state = 'ground'; }
          break;
        }
        case 'ground': {
          const ph = t + p.phase;
          p.pivot.rotation.z = Math.sin(ph * 1.3) * 0.04;
          this._poseParts(p, 0.05 + Math.max(0, Math.sin(ph * 2)) * 0.08, 0.25, 0.25 + Math.max(0, Math.sin(ph * 1.1)) * 0.5);
          break;
        }
        case 'carried': {
          const pl = this.game.player;
          const sp = pl?.vel ? Math.hypot(pl.vel.x, pl.vel.z) : 0;
          const ph = t * (4 + sp * 1.4) + p.phase;
          if (p.hanger) {
            p.hanger.rotation.x = Math.sin(ph) * (0.08 + sp * 0.05);
            p.hanger.rotation.z = Math.sin(ph * 0.5 + 1) * (0.06 + sp * 0.03);
          }
          p.pivot.position.y = Math.abs(Math.sin(ph)) * 0.02;
          this._poseParts(p, 0.1 + Math.max(0, Math.sin(ph * 1.3)) * 0.1, 0.5 + Math.sin(ph) * 0.3, 0.5 - Math.sin(ph) * 0.3);
          break;
        }
        case 'flying': {
          p.t += dt;
          if (p.t < 0) break;
          const k = clamp01(p.t / p.dur);
          const e = easeInOut(k);
          _v.lerpVectors(p.from, p.to, e);
          _v.y += Math.sin(k * Math.PI) * 0.6;
          const parent = p.root.parent;
          p.root.position.copy(_v);
          if (parent) parent.worldToLocal(p.root.position);
          p.root.quaternion.slerpQuaternions(p.fromQ, p.toQ, e);
          p.root.scale.setScalar(p.fromS + (p.toS - p.fromS) * e);
          p.pivot.rotation.x = -Math.sin(k * Math.PI) * 0.5;
          if (k >= 1) { p.pivot.rotation.set(0, 0, 0); this._landSlot(p); }
          break;
        }
        case 'slotted': {
          p.t += dt;
          const k = clamp01(p.t / 0.4);
          const sq = Math.sin(k * Math.PI * 2) * (1 - k) * 0.2;
          p.model.scale.set(1 + sq, 1 - sq, 1 + sq);
          const ph = t + p.phase;
          this._poseParts(p, 0.06 + Math.max(0, Math.sin(ph * 2.4)) * 0.1, 0.3, 0.3 + Math.max(0, Math.sin(ph * 1.7)) * 0.5);
          break;
        }
        case 'hop': {
          p.t += dt;
          if (p.t < 0) break;
          const k = clamp01(p.t / p.dur);
          _v.lerpVectors(p.from, p.to, easeInOut(k));
          _v.y += Math.sin(k * Math.PI) * 0.35;
          this._setWorld(p.root, _v, Math.PI, 1);
          p.model.scale.setScalar(1);
          if (k >= 1) { p.state = 'stage'; p.t = 0; }
          break;
        }
        case 'stage': {
          p.t += dt;
          const s = this._song;
          const beat = 0.5 * 60 / 132;
          if (s && s.t > 0.55 && s.t < 6.6) {
            const u = (s.t - 0.55) / beat;
            const off = { dragon: 0, sock: 0.33, owl: 0.66 }[p.key];
            const b = Math.abs(Math.sin((u + off) * Math.PI));
            p.pivot.position.y = b * 0.07;
            p.pivot.rotation.z = Math.sin((u + off) * Math.PI * 0.5) * 0.18;
            this._poseParts(p, 0.15 + b * 0.35, 1.2 + Math.sin(u * 1.3) * 0.6, 1.2 + Math.cos(u * 1.3) * 0.6);
          } else if (s && s.t >= 6.6) {
            const k = clamp01((s.t - 6.6) / 0.5);
            p.pivot.rotation.x = -Math.sin(k * Math.PI) * 0.6;          // the bow
            p.pivot.position.y = 0;
            this._poseParts(p, 0.1, 0.4, 0.4);
          } else {
            const ph = this.game.time.now + p.phase;
            p.pivot.position.y = Math.abs(Math.sin(ph * 1.6)) * 0.015;
            p.pivot.rotation.set(0, 0, Math.sin(ph * 0.9) * 0.05);
            this._poseParts(p, 0.06 + Math.max(0, Math.sin(ph * 1.9)) * 0.08, 0.35, 0.35 + Math.max(0, Math.sin(ph * 0.8)) * 0.6);
          }
          break;
        }
        default: break;
      }
    }
  }

  _revealPuppet(p) {
    this._setPuppetLayer(p, 0);
    this._setLook(p, false);
    p.pivot.position.set(0, 0, 0);
    p.pivot.rotation.set(0, 0, 0);
    p.model.scale.setScalar(1);
    _v.copy(p.home).y += PUPPET_CENTER * p.gs;
    this._play('ee_puppet_reveal', { pos: _v.clone() });
    this.game.fx?.burst?.(_v, { shape: 'star', count: 10, speed: 2.2, size: 0.08, life: 0.6, colors: ['#FFE45C', '#FFFFFF', '#C9A8FF'] });
    this._emit('egg:puppet_reveal', { id: p.id });
    if (p.key === 'dragon') this.O.ee_trophy_case?.setOpen?.(true);
    p.from.copy(p.home);
    p.to.copy(p.drop);
    p.dur = p.key === 'owl' ? 0.8 : 0.7;
    p.t = p.key === 'dragon' ? -0.25 : 0;         // the case door swings first (k stays 0 while t < 0)
    p.state = 'falling';
  }

  // ================================================================================================ STEP 3: applause
  _onKill(e) {
    if (!e || this.step !== 2) return;
    const pos = e.pos || e.z?.pos;
    if (!pos) return;
    const [x0, z0, x1, z1] = E.applauseZone;
    if (pos.x < x0 || pos.x > x1 || pos.z < z0 || pos.z > z1) return;
    if (this.game.player?.area !== 'studio_a') return;
    this._countApplause(pos, e.z || null);
  }

  // One counted kill at `pos` (the zombie `z`, if any, for the hands to follow its body's slide).
  _countApplause(pos = null, z = null) {
    this.applause++;
    const n = this.applause;
    const O = this.O;
    this._signSolidT = 0.6;
    O.ee_applause_sign?.setLit?.(true);
    // the applause: the close crowd + the gloves' claps (non-positional, sfx bus) and both bleachers (positional,
    // linear rolloff to 45 m), a hair after the kill's own shot
    this._play('ee_applause_near', { claps: CLAP.beats });
    for (const b of BLEACHERS) this._play('ee_applause_burst', { pos: b, delay: 0.04 });
    if (pos) this._spawnClap(pos, z);
    O.ee_tote_board?.setValue?.(TOTE_BASE + Math.min(n, E.applauseKills));
    this._toteTwitchBack = -1;
    const tpos = O.ee_tote_board?.group ? O.ee_tote_board.group.getWorldPosition(new THREE.Vector3()).setY(2.8) : new THREE.Vector3(4, 2.8, -21);
    this._play('ee_tote_flip', { pos: tpos });
    if (n === 1) {
      this._play('crowd_ooh', { pos: BLEACHERS[0], delay: 0.15, range: 45 });
      this._play('crowd_applause', { pos: BLEACHERS[1], dur: 2.2, delay: 0.5, range: 45 });
      for (const b of BLEACHERS) this.game.fx?.burst?.(_v.copy(b).setY(2.2), { shape: 'confetti', count: 30, speed: 3.5, size: 0.08, life: 1.4, gravity: 4, colors: RAINBOW });
    }
    this._emit('egg:applause', { count: n });
    if (n >= E.applauseKills) this._completeApplause();
  }

  _completeApplause() {
    if (!this._complete(3)) return;
    const O = this.O, g = this.game;
    O.ee_tote_board?.setValue?.(TOTE_BASE + E.applauseKills);
    this._signMode = 'locked';
    O.ee_applause_sign?.setLit?.(true);
    // thermometer top confetti + the grid cannons + a standing ovation
    const top = O.ee_tote_board?.parts?.topper;
    const tp = top ? top.getWorldPosition(new THREE.Vector3()) : new THREE.Vector3(4, 3.4, -21);
    g.fx?.burst?.(tp, { shape: 'confetti', count: 70, speed: 5.5, size: 0.09, life: 1.8, gravity: 4, dir: new THREE.Vector3(0, 1, 0), cone: 0.9, colors: RAINBOW });
    g.fx?.burst?.(tp, { shape: 'star', count: 14, speed: 3, size: 0.12, life: 0.9 });
    g.fx?.flashLight?.(tp, '#FFD27A', 5, 0.4);
    this._cannons.forEach((c, i) => this._later(0.15 + i * 0.22, () => this._fireCannon(c)));
    for (const b of BLEACHERS) this._play('ee_ovation', { pos: b, delay: 0.2 });
    // + the ovation's close layer (a job, so the audio engine does not merge it with this kill's own near layer)
    this._later(0.3, () => this._play('ee_applause_near', { dur: 3.8, claps: [], vol: 0.8 }));
    this._celebrate(3, { laugh: 4.6, box: 6.2 });
    // hook (+2 s): thunder over the newsroom + the weather map
    this._later(2.0, () => this._thunderHook());
  }

  _fireCannon(c) {
    const g = this.game;
    c.kick = 0;
    c.group.updateMatrixWorld(true);
    const muzzle = c.parts.barrel.localToWorld(new THREE.Vector3(0, 0.5, 0));
    g.fx?.burst?.(muzzle, { shape: 'confetti', count: 90, speed: 7, size: 0.1, life: 2.4, gravity: 3.2, drag: 1.2, dir: c.dir, cone: 0.45, colors: RAINBOW });
    g.fx?.burst?.(muzzle, { shape: 'puff', count: 6, speed: 1.5, size: 0.2, life: 0.6, color: '#FFFFFF' });
    this._play('ee_confetti_cannon', { pos: muzzle });
  }

  _updateApplauseProps(dt) {
    const O = this.O;
    const sign = O.ee_applause_sign;
    if (this._signSolidT > 0) {
      this._signSolidT -= dt;
      if (this._signSolidT <= 0 && this._signMode !== 'locked') sign?.setLit?.(false);
    } else if (this._signMode === 'flicker' && sign && dt > 0) {
      this._flickT = (this._flickT ?? 0) - dt;
      if (this._flickT <= 0) {
        this._flickT = 1 / (2 * (2 + Math.random() * 3));            // random 2–5 Hz
        sign.setLit(!sign.lit);
      }
    }
    // tote digits twitch (step 2 hook) and the per-kill flip pop
    const tote = O.ee_tote_board;
    if (tote && this._signMode === 'flicker' && this.step === 2 && dt > 0) {
      if (this._toteTwitchBack >= 0) {
        this._toteTwitchBack -= dt;
        if (this._toteTwitchBack < 0) tote.setValue(TOTE_BASE + this.applause);
      } else {
        this._toteTwitchT -= dt;
        if (this._toteTwitchT <= 0) {
          this._toteTwitchT = 1.5 + Math.random() * 3;
          this._toteTwitchBack = 0.09 + Math.random() * 0.08;
          tote.setValue(TOTE_BASE + this.applause + (Math.random() < 0.5 ? 1 : -1));
          if (this.game.player?.area === 'studio_a') this._play('ee_tote_flip', { pos: tote.group?.getWorldPosition?.(new THREE.Vector3()) || undefined, vol: 0.25 });
        }
      }
    }
    // cannon recoil
    for (const c of this._cannons) {
      if (c.kick < 0) continue;
      c.kick += dt;
      const k = clamp01(c.kick / 0.6);
      c.parts.barrel.position.copy(c.dir).multiplyScalar(-Math.sin(Math.min(1, k * 3) * Math.PI * 0.5) * 0.14 * (1 - k));
      if (k >= 1) { c.kick = -1; c.parts.barrel.position.set(0, 0, 0); }
    }
  }

  // ================================================================================================ STEP 3: applause hands
  // Two InstancedMeshes (left / right glove, CLAP.max instances each) in the scene root, world layer, never culled
  // (instances move), hidden while no pair is alive: 2 draw calls for any number of live pairs.
  _buildHands() {
    const g = this.game;
    const mat = this._clapMaterial();
    const make = (mirror) => {
      const geo = gloveGeometry(mirror);
      const fade = new THREE.InstancedBufferAttribute(new Float32Array(CLAP.max).fill(1), 1);
      fade.setUsage(THREE.DynamicDrawUsage);
      geo.setAttribute('aFade', fade);
      const m = new THREE.InstancedMesh(geo, mat, CLAP.max);
      m.name = mirror ? 'ee_applause_glove_r' : 'ee_applause_glove_l';
      m.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      m.count = 0;
      m.visible = false;
      m.frustumCulled = false;
      m.castShadow = false;
      m.receiveShadow = false;
      m.userData.noMerge = true;
      g.scene.add(m);
      return m;
    };
    this._hands = { mat, l: make(false), r: make(true) };
  }

  // White glove: a keepColor toon (vertex colours, soft wrap, cream rim) cloned with a per-instance alpha (aFade) so
  // each pair fades on its own; its own program key (the toon patch plus two lines).
  _clapMaterial() {
    const base = this.game.mats.toon('#ffffff', { keepColor: true, vertexColors: true, rough: 0.55, rim: 0.5, rimColor: '#FFF1D8', rimPower: 2.0, wrap: 0.7, transparent: true });
    const ud = base.userData;
    base.userData = {};
    let mat;
    try { mat = base.clone(); } finally { base.userData = ud; }
    const pre = base.onBeforeCompile;
    const key = typeof base.customProgramCacheKey === 'function' ? base.customProgramCacheKey() : '';
    mat.onBeforeCompile = (shader, renderer) => {
      pre.call(base, shader, renderer);
      shader.vertexShader = shader.vertexShader.replace('void main() {', 'attribute float aFade;\nvarying float vEggFade;\nvoid main() {\n\tvEggFade = aFade;');
      shader.fragmentShader = shader.fragmentShader
        .replace('void main() {', 'varying float vEggFade;\nvoid main() {')
        .replace('#include <color_fragment>', '#include <color_fragment>\n\tdiffuseColor.a *= vEggFade;');
    };
    mat.customProgramCacheKey = () => `${key}|egg_clap`;
    mat.name = 'egg:applause_glove';
    return mat;
  }

  // A pair of applause hands over a counted kill at `pos` (following zombie `z`'s body while it slides).
  _spawnClap(pos, z = null) {
    if (!this._hands || !pos) return null;
    if (this._claps.length >= CLAP.max) this._clapPool.push(this._claps.shift());
    const c = this._clapPool.pop() || { x: 0, y: 0, z: 0, t: 0, beat: 0, zombie: null };
    c.x = pos.x;
    c.z = pos.z;
    const fy = this._floorY(pos.x, pos.z, (pos.y || 0) + 0.6);
    c.y = Number.isFinite(fy) ? Math.max(fy, (pos.y || 0) - 0.5) : pos.y || 0;
    c.t = 0;
    c.beat = 0;
    c.zombie = z;
    this._claps.push(c);
    _v.set(c.x, c.y + CLAP.height, c.z);
    this.game.fx?.burst?.(_v, { shape: 'confetti', count: 16, speed: 2.4, size: 0.06, life: 1.1, gravity: 3.5, colors: RAINBOW });
    return c;
  }

  _clearClaps() {
    while (this._claps.length) { const c = this._claps.pop(); c.zombie = null; this._clapPool.push(c); }
    const H = this._hands;
    if (H) { H.l.count = H.r.count = 0; H.l.visible = H.r.visible = false; }
  }

  // Poses every live pair: pop in with squash and stretch, clap on CLAP.beats (palms meet, squash, a star burst),
  // jazz-hands wiggle after the last clap, float up CLAP.rise and fade out; the pair turns to face the camera.
  _updateClaps(rdt) {
    const H = this._hands, list = this._claps;
    if (!H) return;
    if (!list.length) {
      if (H.l.visible) { H.l.visible = H.r.visible = false; H.l.count = H.r.count = 0; }
      return;
    }
    for (let i = list.length - 1; i >= 0; i--) {
      const c = list[i];
      c.t += rdt;
      if (c.t >= CLAP.life) { c.zombie = null; this._clapPool.push(c); list.splice(i, 1); }
    }
    const g = this.game;
    const cam = g.render?.cameraOverride || g.camera;
    _cp.setFromMatrixPosition(cam.matrixWorld);
    const B = CLAP.beats, last = B[B.length - 1];
    const fl = H.l.geometry.attributes.aFade, fr = H.r.geometry.attributes.aFade;
    let n = 0;
    for (const c of list) {
      const u = c.t;
      const zb = c.zombie;
      if (zb && !zb.removed && zb.pos && u < 0.5) { c.x = zb.pos.x; c.z = zb.pos.z; }
      // timeline
      const kp = clamp01(u / CLAP.pop);
      const pop = kp < 1 ? easeOutBack(kp) : 1;
      const stretch = Math.sin(kp * Math.PI) * 0.35 * (1 - 0.4 * kp);
      const kf = clamp01((u - CLAP.fade) / (CLAP.life - CLAP.fade));
      const alpha = 1 - kf * kf * (3 - 2 * kf);
      let dmin = 9;
      for (let i = 0; i < B.length; i++) dmin = Math.min(dmin, Math.abs(u - B[i]));
      const touch = Math.max(0, 1 - dmin / 0.04);
      let open;
      if (u < B[0]) open = Math.sin((0.5 + 0.5 * (u / B[0])) * Math.PI);
      else if (u < last) {
        let i = 0;
        while (i < B.length - 2 && u >= B[i + 1]) i++;
        open = Math.sin(((u - B[i]) / (B[i + 1] - B[i])) * Math.PI);
      } else open = 0.85 * (1 - (1 - clamp01((u - last) / 0.2)) ** 2);
      const sep = CLAP.touch + (CLAP.open - CLAP.touch) * Math.pow(Math.max(0, open), 0.7);
      const jazz = u > last ? Math.sin(u * 19) * 0.14 * clamp01((u - last) / 0.2) : 0;
      const bump = 0.035 * touch;
      // star burst where the palms meet (once per beat)
      while (c.beat < B.length && u >= B[c.beat]) {
        c.beat++;
        const ay0 = c.y + CLAP.height + 0.04;
        _v.set(c.x, ay0, c.z);
        g.fx?.burst?.(_v, { shape: 'star', count: 3, speed: 1.5, size: 0.06, life: 0.35, gravity: 0, colors: CLAP_STARS });
      }
      // pair frame: yaw toward the camera, rising
      const rise = CLAP.rise * easeInOut(clamp01((u - 0.9) / (CLAP.life - 0.9)));
      const ay = c.y + CLAP.height + rise + Math.sin(u * 5.2) * 0.02;
      _qy.setFromAxisAngle(AX_Y, Math.atan2(_cp.x - c.x, _cp.z - c.z));
      const S = CLAP.scale * pop * (1 - 0.15 * kf);
      _sc.set(S * (1 - stretch * 0.5) * (1 + 0.08 * touch), S * (1 + stretch) * (1 + 0.06 * touch), S * (1 - stretch * 0.5) * (1 - 0.22 * touch));
      for (let side = -1; side <= 1; side += 2) {
        // wrist below the pair's centre, palms facing each other, backs a little toward the camera, fingers fanned
        _w.set(side * sep * 0.5, -0.1 * S + bump, 0).applyQuaternion(_qy);
        _u.set(c.x + _w.x, ay + _w.y, c.z + _w.z);
        _qr.setFromAxisAngle(AX_Z, -side * (0.04 + 0.42 * open + jazz));
        _qt.setFromAxisAngle(AX_Y, side * (1.45 - 0.5 * open));
        _q.copy(_qy).multiply(_qr).multiply(_qt);
        _m4.compose(_u, _q, _sc);
        if (side < 0) { H.l.setMatrixAt(n, _m4); fl.array[n] = alpha; } else { H.r.setMatrixAt(n, _m4); fr.array[n] = alpha; }
      }
      n++;
    }
    H.l.count = H.r.count = n;
    H.l.visible = H.r.visible = n > 0;
    H.l.instanceMatrix.needsUpdate = H.r.instanceMatrix.needsUpdate = true;
    fl.needsUpdate = fr.needsUpdate = true;
  }

  // ================================================================================================ STEP 3 hook: weather map
  _thunderHook() {
    const g = this.game;
    this._play('ee_thunder_far', { pos: NEWSROOM_C, range: 220, vol: 1.2 });
    g.cam?.shake?.(0.15, 0.6);
    const L = g.lights;
    if (L?.anchors) for (const [id, a] of L.anchors) if (a.area === 'newsroom' && !a.flash) L.flicker(id, 0.95, 1.4);
    const map = this.O.ee_weather_map;
    map?.flash?.(true);
    this._later(1.4, () => map?.flash?.(false));
    this._moveMagnets(1.6);
    this._later(1.8, () => { this._mapBlink = true; });
    this._rumbleT = 20;
    this.forceForecaster = true;
    if (!(g.zombies?.count?.('forecaster') > 0)) this._emit('egg:need_forecaster', {});
  }

  _moveMagnets(seconds) {
    const map = this.O.ee_weather_map;
    if (!map?.parts) return;
    const icon = map.anchors?.tower_icon;
    const face = map.anchors?.face;
    const tx = icon ? icon[0] : 0.6, ty = icon ? icon[1] : 1.5;
    const W = face?.w ?? 2.2;
    const go = (name, x, y) => {
      if (!map.parts[`magnet_${name}`]) return;
      if (seconds > 0 && map.slide) map.slide(name, [x, y], seconds);
      else map.showMagnet?.(name, [x, y]);
    };
    // the suns slide to the edges of the map and drop off it, storm + bolt slide onto the tower icon
    go('sun_a', W / 2 - 0.2, (map.parts.magnet_sun_a?.position.y ?? 1.6) + 0.05);
    go('sun_b', -W / 2 + 0.2, (map.parts.magnet_sun_b?.position.y ?? 1.6) - 0.05);
    go('storm', tx + 0.02, ty + 0.2);
    go('bolt', tx - 0.02, ty - 0.02);
    const suns = ['sun_a', 'sun_b'].map((n) => map.parts[`magnet_${n}`]).filter(Boolean);
    if (seconds > 0) this._later(seconds + 0.05, () => { for (const m of suns) this._magFall.push({ m, t: 0, y0: m.position.y, s: m === suns[0] ? 1 : -1 }); });
    else for (const m of suns) m.visible = false;
  }

  _restoreMapTower() {
    const map = this.O.ee_weather_map;
    if (!map?.parts) return;
    for (const n of ['storm', 'bolt']) { const m = map.parts[`magnet_${n}`]; if (m) m.visible = true; }
  }

  _restoreMap() {
    const map = this.O.ee_weather_map;
    if (!map?.parts || !this._mapRest) return;
    for (const [k, r] of Object.entries(this._mapRest)) {
      const m = map.parts[k];
      if (!m) continue;
      m.position.copy(r.p); m.rotation.copy(r.r); m.visible = r.v;
    }
    map.flash?.(false);
  }

  _updateMap(dt) {
    for (let i = this._magFall.length - 1; i >= 0; i--) {
      const f = this._magFall[i];
      f.t += dt;
      const k = clamp01(f.t / 0.45);
      f.m.position.y = f.y0 - k * k * 0.9;
      f.m.rotation.z = f.s * k * 2.2;
      if (k >= 1) { f.m.visible = false; this._magFall.splice(i, 1); }
    }
    if (!this._mapBlink || this.step !== 3) return;
    const map = this.O.ee_weather_map;
    if (map?.parts) {
      const on = (this.game.time.now % 0.8) < 0.5;
      for (const n of ['storm', 'bolt']) { const m = map.parts[`magnet_${n}`]; if (m) m.visible = on; }
    }
    this._rumbleT -= dt;
    if (this._rumbleT <= 0) {
      this._rumbleT = 20;
      const p = map?.towerIcon || NEWSROOM_C;
      this._play('ee_map_rumble', { pos: p, range: 26 });
      map?.flash?.(true);
      this._later(0.25, () => map?.flash?.(false));
    }
  }

  // ================================================================================================ STEP 4: the Stray Storm
  _onForecasterStorm(e) {
    if (this.step !== 3 || this.stormActive || !e?.pos) return;
    this._spawnStorm(e.pos);
  }

  _spawnStorm(pos) {
    const g = this.game;
    this._removeStorm(true);
    const art = buildStorm(g);
    g.scene.add(art.root);
    const floor = this._floorY(pos.x, pos.z, pos.y);
    art.root.position.set(pos.x, Math.max(pos.y, floor + 1.5), pos.z);
    const st = {
      active: true, art, age: 0, lostT: 0, zapCd: 1.5, crackleT: 0.5, bolt: null, boltT: 0, state: 'follow',
      pos: art.root.position, vel: new THREE.Vector3(), fade: 1, loop: null, raceT: 0, raceFrom: new THREE.Vector3(),
    };
    try { st.loop = g.audio?.loop?.('ee_storm_loop', { pos: st.pos.clone(), vol: 0.8 }) || null; } catch { st.loop = null; }
    this.storm = st;
    this._crumbs.length = 0;
    this._crumbT = 0;
    const pl = g.player;
    if (pl) this._crumbs.push(pl.pos.clone());
    g.fx?.burst?.(st.pos, { shape: 'puff', count: 14, speed: 2, size: 0.35, life: 0.8, color: STORM_COLOR });
    this._play('ee_thunder_far', { pos: st.pos.clone(), vol: 0.6 });
    this._emit('egg:storm', { state: 'spawn' });
    return st;
  }

  _removeStorm(instant = false) {
    const st = this.storm;
    if (!st) return;
    try { st.loop?.stop?.(instant ? 0.05 : 0.6); } catch { /* ignore */ }
    st.active = false;
    if (st.bolt) { st.bolt.removeFromParent(); st.bolt.geometry.dispose(); st.bolt = null; }
    st.art.root.removeFromParent();
    st.art.rainTex.dispose();
    for (const m of [st.art.faceMat, st.art.glowMat, st.art.rainMat]) m.dispose();
    st.art.cloud.geometry.dispose();
    st.art.rain.geometry.dispose();
    this.storm = null;
  }

  _floorY(x, z, yFrom = 50) {
    const col = this.game.level?.col;
    const y = col?.floorAt?.(x, z, yFrom);
    if (Number.isFinite(y)) return y;
    const n = this.game.nav?.heightAt?.(x, z);
    return Number.isFinite(n) ? n : 0;
  }

  _ceilAt(x, z) {
    const lv = this.game.level;
    const id = lv?.areaAt?.(x, z);
    const a = id ? lv.areas?.[id] : null;
    if (!a || id === 'yard') return Infinity;
    return a.ceilY ?? a.ceil ?? Infinity;
  }

  _updateStorm(dt) {
    const g = this.game, pl = g.player;
    // breadcrumbs (a position every 0.25 s while a storm lives)
    const st = this.storm;
    if (!st || !pl) return;
    if (dt <= 0) return;
    st.age += dt;
    const art = st.art;
    if (st.state === 'race') return this._updateRace(st, dt);
    if (st.state === 'evaporate') {
      st.fade -= dt / 0.9;
      art.root.scale.setScalar(0.92 * Math.max(0.01, st.fade));
      art.root.position.y += dt * 0.6;
      if (st.fade <= 0) this._removeStorm();
      return;
    }
    this._crumbT += dt;
    const p = st.pos;
    if (this._crumbT >= 0.25) {
      this._crumbT = 0;
      const last = this._crumbs[this._crumbs.length - 1];
      if (last && last.distanceToSquared(pl.pos) > 16) {
        // the trail broke (a teleport): the storm is stranded until the player is back in sight within 6 m
        this._crumbs.length = 0;
        st.stranded = true;
      }
      if (st.stranded) {
        _w.copy(p).y -= 1;
        _u.copy(pl.pos).y += 1.4;
        if (p.distanceTo(pl.pos) < 6 && (this.game.level?.col?.lineOfSight?.(_w, _u) ?? true)) st.stranded = false;
      }
      const lc = this._crumbs[this._crumbs.length - 1];
      if (!st.stranded && (!lc || lc.distanceToSquared(pl.pos) > 0.04)) this._crumbs.push(pl.pos.clone());
      if (this._crumbs.length > 600) this._crumbs.shift();
    }
    // follow the trail
    let target = null;
    while (this._crumbs.length) {
      const c = this._crumbs[0];
      const dx = c.x - p.x, dz = c.z - p.z;
      if (dx * dx + dz * dz < 0.35 * 0.35 && this._crumbs.length > 1) { this._crumbs.shift(); continue; }
      target = c;
      break;
    }
    const dxp = pl.pos.x - p.x, dzp = pl.pos.z - p.z;
    const hDist = Math.hypot(dxp, dzp);
    if (st.stranded) target = p;
    else if (!target || this._crumbs.length <= 1) target = pl.pos;
    const tx = target.x - p.x, tz = target.z - p.z;
    const tl = Math.hypot(tx, tz);
    const speed = S.speed * (hDist < 1.2 && target === pl.pos ? Math.max(0, (hDist - 0.3) / 0.9) : 1);
    if (tl > 1e-3) {
      const step = Math.min(tl, speed * dt);
      p.x += (tx / tl) * step;
      p.z += (tz / tl) * step;
      const yaw = Math.atan2(-dxp, -dzp);
      art.root.rotation.y += Math.atan2(Math.sin(yaw - art.root.rotation.y), Math.cos(yaw - art.root.rotation.y)) * Math.min(1, dt * 3);
    }
    const floor = Math.min(this._floorY(p.x, p.z, p.y), target.y + 0.5);
    const hy = Math.min(floor + S.height, this._ceilAt(p.x, p.z) - 0.6);
    p.y += (hy - p.y) * Math.min(1, dt * 2.5);
    // wobble + face + rain
    const t = g.time.now;
    art.body.position.set(Math.sin(t * 1.3) * 0.06, Math.sin(t * 2.1) * 0.08, 0);
    art.body.rotation.z = Math.sin(t * 0.9) * 0.05;
    const rainH = Math.max(0.3, p.y - this._floorY(p.x, p.z, p.y) - 0.35);
    art.rain.scale.set(1, rainH / art.root.scale.y, 1);
    art.rain.position.y = -0.3;
    art.rainTex.offset.y = (art.rainTex.offset.y + dt * 2.6) % 1;
    art.rainTex.repeat.y = rainH / 1.6;
    if (Math.random() < dt * 6) {
      _v.set(p.x + (Math.random() - 0.5) * 1.4, this._floorY(p.x, p.z, p.y) + 0.03, p.z + (Math.random() - 0.5) * 1.4);
      g.fx?.burst?.(_v, { shape: 'spark', count: 2, speed: 1.2, size: 0.02, life: 0.25, color: '#BFD2FF', dir: new THREE.Vector3(0, 1, 0), cone: 0.8, gravity: 6 });
    }
    // crackles
    st.crackleT -= dt;
    if (st.crackleT <= 0) {
      st.crackleT = 0.5 + Math.random() * 1.1;
      st.flash = 0.18;
      g.fx?.burst?.(_v.copy(p).add(_w.set((Math.random() - 0.5) * 1.2, (Math.random() - 0.3) * 0.5, (Math.random() - 0.5) * 0.8)), { shape: 'spark', count: 6, speed: 2.5, size: 0.025, life: 0.2, color: '#E7D8FF' });
    }
    if (st.flash > 0) st.flash -= dt;
    art.glowMat.opacity = st.flash > 0 ? 0.55 * (st.flash / 0.18) : 0;
    // zap: 10 every 4 s within 2 m (horizontal)
    st.zapCd -= dt;
    if (hDist <= 2 && st.zapCd <= 0) this._zap(st);
    if (st.bolt) {
      st.boltT -= dt;
      st.bolt.material.opacity = Math.max(0, st.boltT / 0.2) * (Math.random() < 0.7 ? 1 : 0.3);
      if (st.boltT <= 0) { st.bolt.removeFromParent(); st.bolt.geometry.dispose(); st.bolt = null; }
    }
    try { st.loop?.setPos?.(p); } catch { /* ignore */ }
    // evaporation: 90 s life (fades from 75 s) or > 20 m of path for 8 s straight
    if (st.age >= S.life - 15) {
      const k = clamp01((st.age - (S.life - 15)) / 15);
      art.root.scale.setScalar(0.92 * (1 - k * 0.55));
      art.cloud.material.opacity = 1;
    }
    let pd = g.nav?.dist?.(p.x, p.z);
    if (!Number.isFinite(pd)) pd = Math.hypot(dxp, dzp) * 1.3;
    st.lostT = pd > S.lostDist ? st.lostT + dt : 0;
    if (st.age >= S.life || st.lostT >= S.lostTime) { this._evaporate(st); return; }
    // arrival at the tower
    _v.set(pl.pos.x - TOWER.x, 0, pl.pos.z - TOWER.z);
    if (_v.length() <= E.towerR && p.distanceTo(pl.pos) <= E.stormNear && this.step === 3) this._arrive(st);
  }

  _zap(st) {
    const g = this.game, pl = g.player;
    st.zapCd = S.zapEvery;
    st.zaps = (st.zaps || 0) + 1;
    _v.copy(pl.pos).y += 1.2;
    const from = st.pos.clone().add(_w.set(0, -0.45, 0));
    const geo = boltGeometry(from, _v, { jag: 0.2, segs: 8, width: 0.035, branches: 1 });
    if (st.bolt) { st.bolt.removeFromParent(); st.bolt.geometry.dispose(); }
    const mat = this._boltMat().clone();
    st.bolt = new THREE.Mesh(geo, mat);
    st.bolt.frustumCulled = false;
    g.scene.add(st.bolt);
    st.boltT = 0.2;
    st.flash = 0.2;
    try { pl.hurt?.(S.zap, st.pos.clone()); } catch (err) { console.warn('[egg] zap', err); }
    this._play('ee_storm_zap', { pos: st.pos.clone() });
    g.fx?.burst?.(_v, { shape: 'spark', count: 12, speed: 3, size: 0.03, life: 0.25, color: '#E0D0FF' });
    g.fx?.flashLight?.(_v, '#C9A8FF', 4, 0.2);
    g.cam?.shake?.(0.12, 0.2);
  }

  _evaporate(st) {
    if (st.state === 'evaporate') return;
    st.state = 'evaporate';
    st.fade = 1;
    try { st.loop?.stop?.(0.8); } catch { /* ignore */ }
    this.game.fx?.burst?.(st.pos, { shape: 'puff', count: 12, speed: 1.5, size: 0.3, life: 0.9, color: '#8A7AA8' });
    this._play('fc_cloud_pop', { pos: st.pos.clone(), rate: 0.7 });
    st.active = false;
    this._emit('egg:storm', { state: 'lost' });
  }

  _arrive(st) {
    st.state = 'race';
    st.raceT = 0;
    st.raceFrom.copy(st.pos);
    this._emit('egg:storm', { state: 'arrived' });
    this._play('fc_rumble', { pos: st.pos.clone(), vol: 1.2 });
  }

  _updateRace(st, dt) {
    const g = this.game;
    st.raceT += dt;
    const k = clamp01(st.raceT / 1.5);
    const e = k * k;
    const a = st.art;
    // spiral up the tower
    const ang = k * TAU * 1.5;
    const r = (1 - e) * 2.5 + 0.6;
    const bx = st.raceFrom.x + (TOWER.x - st.raceFrom.x) * Math.min(1, k * 2.2);
    const bz = st.raceFrom.z + (TOWER.z - st.raceFrom.z) * Math.min(1, k * 2.2);
    st.pos.set(bx + Math.cos(ang) * r * Math.min(1, k * 3), st.raceFrom.y + (TOWER_TOP.y + 2 - st.raceFrom.y) * e, bz + Math.sin(ang) * r * Math.min(1, k * 3));
    a.rain.visible = false;
    a.glowMat.opacity = 0.3 + Math.random() * 0.4;
    a.body.rotation.z = Math.sin(st.raceT * 20) * 0.1;
    try { st.loop?.setPos?.(st.pos); } catch { /* ignore */ }
    if (Math.random() < dt * 12) g.fx?.burst?.(st.pos, { shape: 'spark', count: 4, speed: 3, size: 0.03, life: 0.2, color: '#E7D8FF' });
    if (k >= 1) this._strike(st);
  }

  _strike(st) {
    const g = this.game;
    const top = TOWER_TOP.clone();
    const sky = top.clone().add(new THREE.Vector3(1.5, 34, -2));
    const geo = boltGeometry(sky, top, { jag: 0.16, segs: 20, width: 0.55, branches: 5 });
    const mat = this._boltMat().clone();
    const bolt = new THREE.Mesh(geo, mat);
    bolt.frustumCulled = false;
    g.scene.add(bolt);
    const down = new THREE.Mesh(boltGeometry(top, top.clone().setY(3), { jag: 0.05, segs: 16, width: 0.12, branches: 0 }), mat);
    down.frustumCulled = false;
    g.scene.add(down);
    this._strikeFx = { bolt, down, t: 0 };
    this._whiteT = 0;
    this._play('ee_lightning_strike', { pos: top, range: 400, vol: 1.2 });
    this._play('ee_thunder_far', { delay: 0.35, vol: 0.9 });
    g.fx?.flashLight?.(top, '#E8DDFF', 14, 0.5);
    g.fx?.burst?.(top, { shape: 'spark', count: 40, speed: 9, size: 0.06, life: 0.6, color: '#F0E8FF' });
    g.fx?.burst?.(st.pos, { shape: 'puff', count: 16, speed: 3, size: 0.45, life: 1.0, color: STORM_COLOR });
    g.cam?.shake?.(0.55, 0.7);
    this._removeStorm();
    if (!this._complete(4)) return;
    this.forceForecaster = false;
    this._mapBlink = false;
    this._restoreMapTower();
    this.O.tower_beacons?.setMode?.('rainbow');
    // Baron on "Channel 0" on every TV for 0.5 s, with the (angrier) laugh
    this._override('baron', ALL_TV, 0.5, PRI.ee);
    this._celebrate(4, { laugh: 0.05, box: 3.2 });
  }

  _boltMat() {
    if (!this._boltM) this._boltM = new THREE.MeshBasicMaterial({ color: new THREE.Color('#EDE4FF').multiplyScalar(3), transparent: true, opacity: 1, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false });
    return this._boltM;
  }

  // ================================================================================================ STEP 5: tape + tracking
  _onTellyTake(e) {
    if (!e || e.itemId !== 'ee_tape_reel') return;
    this.hasTape = true;
    this._reel = this.game.telly?.tapeReel || null;
  }

  _loadTape() {
    if (!this.hasTape || this._track || this.step !== 4) return;
    const g = this.game;
    const vtr = this.O.ee_vtr2;
    this.hasTape = false;
    const reel = this._reel || g.telly?.tapeReel || null;
    if (reel) {
      reel.updateMatrixWorld(true);
      const from = reel.getWorldPosition(new THREE.Vector3());
      g.scene.attach(reel);
      this._reelFly = { reel, from, to: (vtr?.group ? vtr.group.localToWorld(new THREE.Vector3(0, 1.3, -0.55)) : this._vtrPos.clone().setY(1.3)), t: 0 };
    }
    vtr?.loadTape?.(1.5);
    this._play('ee_tape_thread', { pos: this._vtrPos });
    const n = E.tracking.detents;
    const s0 = Math.floor(g.rand() * n);
    let kT = Math.floor(g.rand() * (n - 1));
    if (kT >= s0) kT++;
    this._track = { s0, kT, k: s0, quietT: 0, started: false, t: 0 };
    this.O.ee_tracking_knob?.set?.(s0, true);
    this._later(1.5, () => this._startPlayback());
  }

  _startPlayback() {
    const g = this.game, tr = this._track;
    if (!tr || this.step !== 4) return;
    tr.started = true;
    const d = this._trackDist();
    try { g.screens?.setSource?.('scr_vtr2', this._picture.texture); } catch (err) { console.warn('[egg] vtr source', err); }
    try {
      this._tones = g.audio?.loop?.('ee_tracking_tones', { pos: this._vtrPos.clone(), vol: 0.55, d }) || null;
      this._tones?.setDistance?.(d);
      this._hymn = g.audio?.loop?.('sting_signoff_hymn', { pos: this._vtrPos.clone(), vol: 0.5, tv: true }) || null;
    } catch { /* ignore */ }
  }

  _stopTracking() {
    try { this._tones?.stop?.(0.2); } catch { /* ignore */ }
    try { this._hymn?.stop?.(0.3); } catch { /* ignore */ }
    this._tones = this._hymn = null;
    if (this._reelFly) { this._reelFly.reel.removeFromParent(); this._reelFly = null; }
  }

  _trackDist() {
    const tr = this._track;
    if (!tr) return 6;
    const n = E.tracking.detents;
    const a = Math.abs(tr.k - tr.kT);
    return Math.min(a, n - a);
  }

  _turnKnob() {
    const g = this.game;
    const knob = this.O.ee_tracking_knob;
    const n = E.tracking.detents;
    let k;
    if (knob?.turn) k = knob.turn(1);
    else k = ((this._track?.k ?? 3) + 1) % n;
    this._play('ee_tracking_click', { pos: this._knobPos });
    const tr = this._track;
    if (!tr || this.step !== 4) return;
    tr.k = k;
    tr.quietT = 0;
    const d = this._trackDist();
    try { this._tones?.setDistance?.(d); } catch { /* ignore */ }
    this._emit('egg:tracking', { detent: k, distance: d });
    void g;
  }

  _updateTracking(dt) {
    const g = this.game;
    const fly = this._reelFly;
    if (fly) {
      fly.t += dt;
      const k = clamp01(fly.t / 0.45);
      fly.reel.position.lerpVectors(fly.from, fly.to, easeInOut(k));
      fly.reel.position.y += Math.sin(k * Math.PI) * 0.4;
      fly.reel.rotation.z += dt * 12;
      if (k >= 1) { fly.reel.removeFromParent(); this._reelFly = null; }
    }
    const tr = this._track;
    if (!tr || !tr.started || this.step !== 4) return;
    const d = this._trackDist();
    const pl = g.player;
    const near = pl ? Math.hypot(pl.pos.x - this._vtrPos.x, pl.pos.z - this._vtrPos.z) <= E.tracking.radius : false;
    const vis = pl?.area === 'master_control' || (pl && pl.pos.distanceTo(this._vtrPos) < 14);
    this._picture.update(dt, d, vis);
    tr.t += dt;
    // the hymn wobbles with the mistracking (a slow wow flutter on the level)
    if (this._hymn?.setVol) {
      tr.wob = (tr.wob ?? 0) + dt;
      if (tr.wob > 0.05) { tr.wob = 0; try { this._hymn.setVol(0.5 * (1 - (d / 6) * 0.45 * (0.5 + 0.5 * Math.sin(tr.t * (3 + d)))), 0.05); } catch { /* ignore */ } }
    }
    if (d === 0) {
      if (near) tr.quietT += dt;
      if (tr.quietT >= E.tracking.hold) this._completeTape();
    } else tr.quietT = 0;
  }

  _completeTape() {
    const g = this.game;
    if (!this._complete(5)) return;
    const O = this.O;
    this._stopTracking();
    this._track = null;
    O.ee_vtr2?.setLamp?.('green', false);
    try { g.screens?.setSource?.('scr_vtr2', 'signoff_film'); } catch { /* ignore */ }
    this._override('signoff_film', undefined, 20, PRI.signoff);
    this._play('sting_signoff_hymn');
    this._onAirT = 0;
    this._later(0.5, () => this._tvSound('ee_baron_scream', { near: 3, vol: 1.1 }));
    this._celebrate(5, { laugh: 3.4, box: 5.2 });
    this._later(1.0, () => this._openCage(false));
  }

  // ================================================================================================ STEP 5 hook + STEP 6 trigger
  _openCage(instant) {
    const ks = this.O.ee_kill_switch;
    if (!ks) return;
    if (instant) { if (ks.parts?.door) ks.parts.door.rotation.y = -1.7; this._cageT = -1; }
    else {
      this._cageT = 0;
      this._play('ee_cage_boing', { pos: ks.pos });
      try { this._alarm?.stop?.(0.1); } catch { /* ignore */ }
      this._alarm = this._play('ee_alarm_bell', { pos: ks.pos.clone().setY(2.2), dur: 10, range: 70, vol: 1 });
      this.game.fx?.burst?.(ks.handle || ks.pos, { shape: 'star', count: 14, speed: 2.5, size: 0.1, life: 0.8, colors: RAINBOW });
    }
    this._addOutline();
  }

  _addOutline() {
    const ks = this.O.ee_kill_switch;
    const sw = ks?.parts?.switch;
    if (!sw || this._outline) return;
    const mat = new THREE.MeshBasicMaterial({ color: '#FF4A4A', side: THREE.BackSide, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false });
    const group = new THREE.Group();
    group.name = 'ee_switch_outline';
    sw.updateMatrixWorld(true);
    sw.children.forEach((m) => {
      if (!m.isMesh) return;
      const gg = m.geometry.clone();
      if (!gg.attributes.normal) gg.computeVertexNormals();
      const p = gg.attributes.position, n = gg.attributes.normal;
      for (let i = 0; i < p.count; i++) p.setXYZ(i, p.getX(i) + n.getX(i) * 0.032, p.getY(i) + n.getY(i) * 0.032, p.getZ(i) + n.getZ(i) * 0.032);
      const o = new THREE.Mesh(gg, mat);
      o.position.copy(m.position); o.quaternion.copy(m.quaternion); o.scale.copy(m.scale);
      o.castShadow = false;
      group.add(o);
    });
    sw.add(group);
    const L = this.game.lights;
    const hp = ks.handle || ks.pos;
    try { L?.addAnchor?.({ id: 'ee_switch_glow', pos: [hp.x, hp.y + 0.2, hp.z - 0.6], color: '#FF4A4A', intensity: 2.2, distance: 4, area: 'yard' }); } catch { /* ignore */ }
    this._outline = { group, mat };
  }

  _removeOutline() {
    if (!this._outline) return;
    this._outline.group.removeFromParent();
    this._outline.group.traverse((o) => o.geometry?.dispose?.());
    this._outline.mat.dispose();
    this._outline = null;
    try { this.game.lights?.removeAnchor?.('ee_switch_glow'); } catch { /* ignore */ }
  }

  _throwSwitch() {
    if (this.step !== 5 || this._killSwitchUsed) return;
    const g = this.game;
    this._killSwitchUsed = true;
    this._switchThrownAt = g.time.realNow;
    const ks = this.O.ee_kill_switch;
    this._switchT = 0;
    try { this._alarm?.stop?.(0.2); } catch { /* ignore */ }
    this._alarm = null;
    g.cam?.shake?.(0.25, 0.3);
    this._later(0.3, () => { if (this._killSwitchUsed) this._removeOutline(); });
    // boss.start plays the THUNK itself (after audio.stopAll, the dead air); play it here only without a boss
    let ok = false;
    try { ok = g.boss?.start ? g.boss.start(g.rounds?.round || 1) !== false || !!g.boss.active : false; } catch (err) { console.warn('[egg] boss.start', err); }
    if (!g.boss?.start) this._play('ee_switch_thunk', { pos: ks?.handle || ks?.pos });
    else if (!ok) this._rearmSwitch();
  }

  // the fight never started (or ended without a defeat, e.g. an aborted boss): the switch can be thrown again
  _rearmSwitch() {
    if (this.step !== 5 || this.done) return;
    this._killSwitchUsed = false;
    this._switchT = -1;
    const sw = this.O.ee_kill_switch?.parts?.switch;
    if (sw) sw.rotation.x = 0;
    this._addOutline();
  }

  _updateYard(dt, rdt) {
    const ks = this.O.ee_kill_switch;
    if (this._cageT >= 0 && ks?.parts?.door) {
      this._cageT += dt;
      const k = clamp01(this._cageT / 0.55);
      ks.parts.door.rotation.y = -1.7 * easeOutBack(k);
      if (k >= 1) this._cageT = -1;
    }
    if (this._killSwitchUsed && this.step === 5 && !this.done && this.game.boss && !this.game.boss.active
      && this.game.state === 'playing' && this.game.time.realNow - (this._switchThrownAt ?? 0) > 4) this._rearmSwitch();
    if (this._switchT >= 0 && ks?.parts?.switch) {
      this._switchT += dt;
      const k = clamp01(this._switchT / 0.28);
      ks.parts.switch.rotation.x = 1.9 * (k < 1 ? k * k : 1);
      if (k >= 1) this._switchT = -1;
    }
    if (this._outline) {
      hueColor(this.game.time.realNow * 0.35, _col);
      this._outline.mat.color.copy(_col).multiplyScalar(2.2 + Math.sin(this.game.time.realNow * 6) * 0.6);
      this._outline.t = (this._outline.t ?? 0) + rdt;
      if (this._outline.t > 0.1) {
        this._outline.t = 0;
        try { this.game.lights?.setAnchor?.('ee_switch_glow', { color: '#' + _col.getHexString(), intensity: 2 + Math.sin(this.game.time.realNow * 5) * 0.6 }); } catch { /* ignore */ }
      }
    }
    // ON AIR boxes flash after the tape (2 s), then stay as the power says
    if (this._onAirT >= 0) {
      this._onAirT += rdt;
      const lv = this.game.level;
      const on = Math.floor(this._onAirT * 6) % 2 === 0;
      if (this._onAirT >= 2.2) { this._onAirT = -1; try { lv?.setOnAir?.(!!lv.powered); } catch { /* ignore */ } }
      else if (on !== this._onAirOn) { this._onAirOn = on; try { lv?.setOnAir?.(on); } catch { /* ignore */ } }
    }
  }

  _updatePost(rdt) {
    const post = this.game.render?.post;
    if (this._whiteT >= 0 && post) {
      this._whiteT += rdt;
      const k = this._whiteT;
      post.whiteout = k < 0.05 ? 0.5 : Math.max(0, 0.5 * (1 - (k - 0.05) / 0.45));
      if (k > 0.65) { post.whiteout = 0; this._whiteT = -1; }
    }
    const fx = this._strikeFx;
    if (fx) {
      fx.t += rdt;
      const k = fx.t;
      const o = k < 0.45 ? (Math.random() < 0.75 ? 1 : 0.25) : Math.max(0, 1 - (k - 0.45) / 0.25);
      fx.bolt.material.opacity = o;
      if (k > 0.72) {
        for (const m of [fx.bolt, fx.down]) { m.removeFromParent(); m.geometry.dispose(); }
        fx.bolt.material.dispose();
        this._strikeFx = null;
      }
    }
  }

  // ================================================================================================ debug
  revealLayer2(on = true) {
    const c = this.game.camera;
    if (on) c.layers.enable(LAYERS.TV_ONLY); else c.layers.disable(LAYERS.TV_ONLY);
    return !!on;
  }

  debugHit(id, { melee = false } = {}) {
    const info = { id, melee, cause: melee ? 'melee' : 'bullet', weaponId: melee ? 'melee' : 'revolver_38', damage: 50, dir: new THREE.Vector3(-1, 0, 0) };
    const c = String(id).replace('ee_bar_', '');
    if (BARS.includes(c)) { this._barFrame = -1; this._onBarHit(c, info); return true; }
    const p = this.puppets[id];
    if (p) { this._onPuppetHit(p, info); return p.state === 'tuning'; }
    return false;
  }

  debugUse(id) {
    if (String(id).startsWith('pickup:')) { const p = this.puppets[id.slice(7)]; if (p) this._pickup(p); return !!p; }
    const it = this.game.interact?.items?.get?.(id);
    if (!it) return false;
    if (it.enabled && !it.enabled()) return false;
    it.use();
    return true;
  }

  // a qualifying kill at (x, z) without a zombie (the handler only, no zombie:kill broadcast)
  debugKill(x, z) {
    this._onKill({ z: null, pos: new THREE.Vector3(x, 0, z), cause: 'debug' });
    return this.applause;
  }

  // just the applause hands at (x, z) (no count, no sound)
  debugClap(x, z) {
    return !!this._spawnClap(new THREE.Vector3(x, this._floorY(x, z, 2), z), null);
  }

  debugStorm(x, z) {
    const pl = this.game.player;
    const px = x ?? pl.pos.x + 6, pz = z ?? pl.pos.z;
    return !!this._spawnStorm(new THREE.Vector3(px, this._floorY(px, pz) + 2.5, pz));
  }

  debugGiveTape() {
    const g = this.game;
    const back = g.player?.hero?.slots?.back;
    let reel = g.telly?.tapeReel || null;
    if (!reel) {
      try { reel = buildTapeReel(g); } catch (err) { console.warn('[egg] tape reel', err); reel = new THREE.Group(); }
      if (back) { back.add(reel); reel.position.set(0, 0.05, 0.09); reel.rotation.set(0, 0, 0.15); reel.scale.setScalar(0.9); }
      if (g.telly) g.telly.tapeReel = reel;
    }
    this._reel = reel;
    this.hasTape = true;
    return true;
  }

  debugTrack(k) {
    const tr = this._track;
    const knob = this.O.ee_tracking_knob;
    knob?.set?.(k, true);
    if (tr) { tr.k = ((k % 13) + 13) % 13; tr.quietT = 0; try { this._tones?.setDistance?.(this._trackDist()); } catch { /* ignore */ } }
    return this._trackDist();
  }

  debugState() {
    const tr = this._track;
    return JSON.parse(JSON.stringify({
      step: this.step, done: this.done, power: this.powered, forceForecaster: this.forceForecaster, applause: this.applause,
      hasTape: this.hasTape, carried: this.carried, bars: this._bars.map((b) => b.bar), barT: this._bars.map((b) => +b.t.toFixed(2)), sign: this._signMode,
      puppets: Object.fromEntries(Object.values(this.puppets).map((p) => [p.key, { state: p.state, layer: p.layer, home: p.home.toArray().map((v) => +v.toFixed(2)), drop: p.drop.toArray().map((v) => +v.toFixed(2)) }])),
      storm: this.storm ? { state: this.storm.state, age: +this.storm.age.toFixed(2), pos: this.storm.pos.toArray().map((v) => +v.toFixed(2)), lostT: +this.storm.lostT.toFixed(2), crumbs: this._crumbs.length, zaps: this.storm.zaps || 0 } : null,
      track: tr ? { s0: tr.s0, kT: tr.kT, k: tr.k, d: this._trackDist(), quietT: +tr.quietT.toFixed(2), started: tr.started } : null,
      killSwitchUsed: !!this._killSwitchUsed, outline: !!this._outline, jobs: this._jobs.length,
      claps: this._claps.length, clapDraws: this._hands ? (this._hands.l.visible ? 2 : 0) : -1,
    }));
  }
}
