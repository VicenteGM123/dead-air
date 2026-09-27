// DEAD AIR — sponsor spots: the 5 sponsor sets and THE COMMERCIAL (GDD §10.3, §11, §14, §15, §18.9/§18.10).
// Owned by the sponsors agent (with src/game/perks.js and src/ui/commercial.js).
//
// SETS  sponsor_set_<perkId> prefabs (src/props/sponsors.js: riser, painted flat, neon sign, turntable + giant
//   product, softboxes, gaffer-tape X, speaker, brand dressing) at the set_* anchors (layout.js: mark X, pedestal,
//   camera), each with its own tally camera prop (pedestal camera; Replay-Ade: the ENG camera on a tripod) at the
//   anchor's camera spot, aimed at the X. A set that would poke through a wall, a platform or a door/window lane
//   slides toward its camera (and turns a little) until it fits: `sets[perkId].fit` reports the shift.
//   Before power a set is dark and its tally is off (Replay-Ade is lit from the start); the colour wave
//   (signon.waveReached) wakes it with a 3-flash flicker. After power the product plays its 1 s teaser (sound + a
//   hop and spin) when the player comes within 5 m, at most every 8 s. The camera head follows the player on the mark.
// INTERACTION  within T.perks.markRadius (1.0 m) of the X, no facing needed: [E] cost; unpowered [E] + plug
//   (Replay-Ade works unpowered); no prompt when owned, sold out, or at the perk limit — at the limit, stepping onto
//   the X makes the camera shake its head (pans left-right twice), blink its tally and "bzzt" (at most every 3 s).
// THE COMMERCIAL (4.2 s, real time; world frozen: time.scale 0, player invulnerable, no control). GDD §10.3 says 3.2 s;
//   player feedback: the logo card was gone before its product name could be read, so the card holds 1 s longer.
//   0.00  ka-ching + one-frame white flash, hard cut: render.setCameraOverride(sponsor camera, {aspect: 4/3}) +
//         render.post.crt, the wood-grain bezel (commercial.js), zombies invisible (the sponsor camera renders layer
//         0 only), world audio ducked by audio.js on machine:commercial_start, round music cut, sponsor jingle.
//   0.00–2.20  YOUR hero's pantomime of the perk with temporary gag props (animator.override): Replay-Ade drink ->
//         banana-peel back-flip -> freeze + VHS rewind -> lands, thumbs up; Wobble-Up spoonful -> boxing glove on an
//         accordion spring from frame left -> gelatin jiggle -> thumbs up; Jump Cut sip from a steaming pot -> three
//         tape-snip jump cuts (arms crossed / finger guns with a prop revolver that reloads itself / wink); Roller
//         Boogie blurs out frame left, skates back in from the right spinning with a sparkle trail, disco point;
//         Double Vision brushes, grins with a star glint "ting", splits into cyan + magenta duplicates striking poses.
//   2.20–3.80  logo card (cards.js sponsor_logo_<perkId>) slides in on its starburst: commercial_ding + announcer_wahwah;
//         it then holds (slow push-in + one sheen sweep, commercial.js) while the jingle tails off, and at 3.20 the
//         product's own teaser motif plays once on the music bus as the ad's button-up sting.
//   3.80–4.20  STAR WIPE out of the product back to the gameplay camera; the costume pops onto its hero slot
//         (perks.attachCostume) with sparkles + costume_pop.
//   4.20  world resumes; zombies within 3 m shoved 2 m back by a flash of the studio lights; perk:gain; commercial_end.
//   The world-audio duck audio.js starts on machine:commercial_start (3.2 s) is re-issued here for the full 4.2 s.
//   Replay-Ade: at most 3 purchases per game; after the 3rd commercial the ENG camera tips over with a thud and the
//   gaffer-tape X covers the bottle (sold out, no prompt ever again).
// API (game.sponsors)
//   inCommercial (bool) · sets { perkId -> set runtime } · replayBought (0..3)
//   buy(perkId) -> bool       spend T.perks[perkId] and play the commercial (false: owned / limit / sold out / broke)
//   playCommercial(perkId, { free = true }) -> bool   debug / scripted (no cost; still needs a free slot)
//   debugCommercial(perkId) (alias), debugSkip() (jumps a running commercial to its end), setPowered(perkId, on)
//   warmup() -> samples (gag props, ghost duplicates) for Game.precompile
// EVENTS  machine:commercial_start {perkId}, machine:commercial_end {perkId}; perk:gain comes from perks.js.
// SOUNDS  sponsor_teaser_<id>, sponsor_jingle_<id>, commercial_cut, commercial_ding, announcer_wahwah, star_wipe,
//   costume_pop, sponsor_denied, studio_flash, replay_rewind, jumpcut_snip, smile_ting, jelly_bwoing, skate_push, light_thunk.

import * as THREE from 'three';
import { T, PAL } from '../core/config.js';
import { AREAS, PLATFORMS, DOORS, WINDOWS } from '../world/layout.js';
import { placeProp, buildProp } from '../props/index.js';
import { setSponsorSetPower, setTally, animateProduct } from '../props/sponsors.js';
import { POSES } from '../core/rig.js';
import { mergeByMaterial } from '../core/geo.js';
import { getOverlay } from '../ui/commercial.js';
import { PERK_IDS, cloneHero, copyPose } from './perks.js';

const TP = T.perks;
// T.perks.adLength (config.js, 3.2 s) is the GDD length; the logo card holds CARD_HOLD longer so the product name reads
// (config.js is not the sponsors agent's file, so the extra second lives here).
const CARD_HOLD = 1.0;
const AD = TP.adLength + CARD_HOLD;  // 4.2 s
const T_CARD = 2.2, T_CLEAN = 2.46, T_WIPE = 2.8 + CARD_HOLD;
const T_SETTLE = T_CARD + 0.24;      // the card has slid in; it holds from here to T_WIPE
const T_BUTTON = T_CARD + 1.0;       // 3.2 s: the jingles end ~2.9-3.4 s -> the product's teaser motif buttons up the ad
const DUCK = { db: -18, lowpass: 800 };   // same world-audio duck as audio.js's machine:commercial_start hook
const FLICKER = [[0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]];
const TAU = Math.PI * 2;
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const smooth = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const lerp = (a, b, k) => a + (b - a) * k;
const easeOut = (x) => 1 - (1 - clamp01(x)) ** 3;
const easeIn = (x) => clamp01(x) ** 3;
const easeOutBack = (x, k = 1.8) => { x = clamp01(x); return 1 + (k + 1) * (x - 1) ** 3 + k * (x - 1) ** 2; };
const yawTo = (fx, fz, tx, tz) => Math.atan2(-(tx - fx), -(tz - fz));
// Disco point to the sky (right arm up and out), left hand on the hip.
const DISCO = { shoulderR: [2.72, 0, 0.28], elbowR: [0.12, 0, 0], shoulderL: [-0.2, 0, -0.55], elbowL: [1.75, 0, 0], hips: [0, 0, 0.1], spine: [0, 0, -0.08], head: [0.25, 0, 0.12] };
// Commercial-shot cheats per set (see _makeCamera): orbit (rad) around the mark, max lens distance.
const SHOT = { wobble_up: { orbit: -0.42, maxD: 2.8 } };
const WAH = { replay_ade: [1.1, 0.95, 1.05, 0.85], wobble_up: [0.9, 1.05, 0.8], jump_cut: [1.15, 1, 1.1, 0.9], roller_boogie: [1, 1.2, 0.95, 1.1, 0.85], double_vision: [1.05, 1.15, 0.9] };

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _u = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _e = new THREE.Euler();
const _m = new THREE.Matrix4();

// ------------------------------------------------------------------------------------------ placement fitting
// Rotated rectangle (center c, half extents hx/hz along axes X/Z) vs axis-aligned rect: separating axis test.
function obbHitsRect(cx, cz, X, Z, hx, hz0, hz1, r) {
  const corners = [];
  for (const lx of [-hx, hx]) for (const lz of [hz0, hz1]) corners.push([cx + X[0] * lx + Z[0] * lz, cz + X[1] * lx + Z[1] * lz]);
  const axes = [[1, 0], [0, 1], X, Z];
  const rc = [[r[0], r[1]], [r[2], r[1]], [r[0], r[3]], [r[2], r[3]]];
  for (const ax of axes) {
    let a0 = Infinity, a1 = -Infinity, b0 = Infinity, b1 = -Infinity;
    for (const p of corners) { const d = p[0] * ax[0] + p[1] * ax[1]; a0 = Math.min(a0, d); a1 = Math.max(a1, d); }
    for (const p of rc) { const d = p[0] * ax[0] + p[1] * ax[1]; b0 = Math.min(b0, d); b1 = Math.max(b1, d); }
    if (a1 <= b0 || b1 <= a0) return false;
  }
  return true;
}

function fitSet(anchor) {
  const mark = anchor.mark, cam = anchor.camera;
  const area = AREAS.find((a) => a.id === anchor.area);
  const [x0, z0, x1, z1] = area.rect;
  const inset = 0.14;
  const hard = [];                                     // stage / risers / bleachers
  const soft = [];                                     // door and window lanes (kept clear when possible)
  for (const p of PLATFORMS) if (p.area === anchor.area) hard.push(p.rect);
  for (const d of DOORS) if (d.areas && d.areas.includes(anchor.area)) {
    const r = d.rect, alongX = (r[2] - r[0]) > (r[3] - r[1]);
    soft.push(alongX ? [r[0] - 0.3, r[1] - 1.5, r[2] + 0.3, r[3] + 1.5] : [r[0] - 1.5, r[1] - 0.3, r[2] + 1.5, r[3] + 0.3]);
  }
  for (const w of WINDOWS) if (w.area === anchor.area && w.inside && w.line) {
    const half = (w.width || 1.6) / 2 + 0.2, [ax, c] = w.line, dIn = w.inside[ax === 'z' ? 2 : 0];
    const lo = Math.min(c, dIn + Math.sign(dIn - c) * 0.8), hi = Math.max(c, dIn + Math.sign(dIn - c) * 0.8);
    soft.push(ax === 'z' ? [w.inside[0] - half, lo, w.inside[0] + half, hi] : [lo, w.inside[2] - half, hi, w.inside[2] + half]);
  }
  const dx = cam[0] - mark[0], dz = cam[2] - mark[2];
  const rot0 = Math.atan2(-dx, -dz);
  // local footprint: riser 3x3 (+ bumper), backdrop to z 1.46
  const HX = 1.56, HZ0 = -1.56, HZ1 = 1.47;
  let best = null;
  for (const dr of [0, 0.07, -0.07, 0.14, -0.14, 0.22, -0.22, 0.32, -0.32, 0.45, -0.45]) {
    const th = rot0 + dr;
    const Z = [Math.sin(th), Math.cos(th)], X = [Math.cos(th), -Math.sin(th)];
    for (let s = 0; s <= 2.0; s += 0.05) {
      for (const l of [0, 0.15, -0.15, 0.3, -0.3, 0.45, -0.45]) {
        let cost = s + Math.abs(l) * 1.4 + Math.abs(dr) * 2.6;
        if (best && cost >= best.cost) continue;
        const mx = mark[0] - Z[0] * s + X[0] * l, mz = mark[2] - Z[1] * s + X[1] * l;
        const ox = mx + Z[0] * 0.75, oz = mz + Z[1] * 0.75;
        let ok = true;
        for (const lx of [-HX, HX]) for (const lz of [HZ0, HZ1]) {
          const px = ox + X[0] * lx + Z[0] * lz, pz = oz + X[1] * lx + Z[1] * lz;
          if (px < x0 + inset || px > x1 - inset || pz < z0 + inset || pz > z1 - inset) ok = false;
        }
        if (ok) for (const r of hard) if (obbHitsRect(ox, oz, X, Z, HX, HZ0, HZ1, r)) { ok = false; break; }
        if (ok) for (const r of soft) if (obbHitsRect(ox, oz, X, Z, HX, HZ0, HZ1, r)) cost += 2.5;
        if (ok && (!best || cost < best.cost)) best = { cost, rotY: th, origin: [ox, oz], mark: [mx, mz], shift: s, lateral: l, turn: dr };
      }
    }
  }
  if (!best) best = { cost: 99, rotY: rot0, origin: [mark[0] + Math.sin(rot0) * 0.75, mark[2] + Math.cos(rot0) * 0.75], mark: [mark[0], mark[2]], shift: 0, lateral: 0, turn: 0 };
  // tally camera: the anchor spot (just clear of the riser), kept inside the room
  const cx = cam[0], cz = cam[2];
  let ddx = cx - best.mark[0], ddz = cz - best.mark[1];
  let L = Math.hypot(ddx, ddz) || 1;
  ddx /= L; ddz /= L;
  if (L < 1.4) L = 1.4;
  let px = best.mark[0] + ddx * L, pz = best.mark[1] + ddz * L;
  px = THREE.MathUtils.clamp(px, x0 + 0.55, x1 - 0.55);
  pz = THREE.MathUtils.clamp(pz, z0 + 0.55, z1 - 0.55);
  best.camera = [px, pz];
  best.bounds = [x0, z0, x1, z1];
  return best;
}

// ------------------------------------------------------------------------------------------ gag props
function toon(g, color, o = {}) { return g.mats.toon(color, { keepColor: true, rough: 0.4, ...o }); }

function buildPeel(g) {
  const grp = new THREE.Group();
  const yel = toon(g, '#F6D23A', { rough: 0.45 }), inner = toon(g, '#FFF3C4', { rough: 0.6 }), tip = toon(g, '#6B4A22');
  const base = new THREE.Mesh(new THREE.SphereGeometry(0.045, 14, 10), yel);
  base.scale.set(1, 0.75, 1); base.position.y = 0.03;
  grp.add(base);
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * TAU + 0.4;
    const petal = new THREE.Group();
    const skin = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 8, 0, TAU, 0, Math.PI / 2), yel);
    skin.scale.set(0.042, 0.018, 0.13); skin.position.set(0, 0.0, 0.1); skin.rotation.x = -0.18;
    const lining = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 8, 0, TAU, 0, Math.PI / 2), inner);
    lining.scale.set(0.034, 0.012, 0.11); lining.position.set(0, 0.006, 0.1); lining.rotation.x = -0.18;
    petal.add(skin, lining);
    petal.rotation.y = a;
    petal.position.y = 0.02;
    grp.add(petal);
  }
  const t = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.018, 0.06, 8), tip);
  t.position.y = 0.075; t.rotation.z = 0.3;
  grp.add(t);
  return grp;
}

function buildSpoon(g) {
  const grp = new THREE.Group();
  const chrome = toon(g, '#C8D0DA', { metal: 1, rough: 0.2 });
  const handle = new THREE.Mesh(new THREE.CylinderGeometry(0.008, 0.012, 0.2, 8), chrome);
  handle.position.y = -0.08;
  const bowl = new THREE.Mesh(new THREE.SphereGeometry(0.035, 14, 8, 0, TAU, Math.PI / 2, Math.PI / 2), chrome);
  bowl.scale.set(1, 0.45, 1.35); bowl.position.y = 0.035;
  const jelly = new THREE.Mesh(new THREE.BoxGeometry(0.045, 0.04, 0.045), toon(g, '#18B54E', { transparent: true, opacity: 0.85, rough: 0.1, emissive: '#0A6A2A', emissiveIntensity: 0.6 }));
  jelly.position.y = 0.05; jelly.rotation.y = 0.5;
  grp.add(handle, bowl, jelly);
  grp.userData.jellyRef = jelly.uuid;
  return { grp, jelly };
}

function buildGlove(g) {
  const grp = new THREE.Group();
  const red = toon(g, '#E23B3B', { rough: 0.3 }), white = toon(g, '#F4F1E8', { rough: 0.5 }), wood = toon(g, '#B07A45', { rough: 0.6 });
  const glove = new THREE.Group();
  const fist = new THREE.Mesh(new THREE.SphereGeometry(0.13, 18, 14), red);
  fist.scale.set(1.15, 0.95, 1);
  const thumb = new THREE.Mesh(new THREE.SphereGeometry(0.055, 12, 10), red);
  thumb.position.set(-0.02, 0.075, 0.07); thumb.scale.set(1.2, 0.8, 0.9);
  const cuff = new THREE.Mesh(new THREE.CylinderGeometry(0.085, 0.095, 0.1, 16).rotateZ(Math.PI / 2), white);
  cuff.position.x = 0.15;
  const lace = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.012, 0.02), white);
  lace.position.set(0.1, 0.06, 0.08);
  glove.add(fist, thumb, cuff, lace);
  grp.add(glove);
  // scissor lattice (the accordion): pairs of crossing slats, laid out by setExtend()
  const slatGeo = new THREE.BoxGeometry(1, 0.018, 0.025);
  const slats = [];
  for (let i = 0; i < 14; i++) { const s = new THREE.Mesh(slatGeo, wood); grp.add(s); slats.push(s); }
  const box = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.26, 0.22), toon(g, '#2F5BD3', { rough: 0.45 }));
  grp.add(box);
  return { grp, glove, slats, box };
}

// Lays the accordion out along +x from the box (x = 0) to the glove at `len` metres.
function setExtend(G, len) {
  const n = G.slats.length / 2, cell = Math.max(0.03, (len - 0.2) / n), rod = 0.36;
  const dy = Math.sqrt(Math.max(0.0004, rod * rod - cell * cell)) * 0.5;
  const ang = Math.atan2(dy * 2, cell);
  for (let i = 0; i < n; i++) {
    const x = 0.11 + cell * (i + 0.5);
    const a = G.slats[i * 2], b = G.slats[i * 2 + 1];
    a.position.set(x, 0, 0.012); b.position.set(x, 0, -0.012);
    a.rotation.set(0, 0, ang); b.rotation.set(0, 0, -ang);
    const L = Math.hypot(cell, dy * 2) + 0.01;
    a.scale.x = L; b.scale.x = L;
  }
  G.glove.position.set(0.11 + cell * n + 0.2, 0, 0);
  G.box.position.set(0, 0, 0);
}

function buildPot(g) {
  const grp = new THREE.Group();
  const glass = g.mats.glass ? g.mats.glass('#FFE8C8', { opacity: 0.35 }) : toon(g, '#FFE8C8', { transparent: true, opacity: 0.35 });
  const coffee = toon(g, '#4A2410', { rough: 0.2 });
  const orange = toon(g, '#E3662B', { rough: 0.35 }), black = toon(g, '#2A2230', { rough: 0.4 });
  const prof = [[0, 0], [0.07, 0.005], [0.085, 0.04], [0.085, 0.08], [0.06, 0.13], [0.045, 0.15], [0.05, 0.17]];
  const body = new THREE.Mesh(new THREE.LatheGeometry(prof.map(([x, y]) => new THREE.Vector2(x, y)), 20), glass);
  const fill = new THREE.Mesh(new THREE.LatheGeometry([[0, 0.004], [0.066, 0.008], [0.08, 0.04], [0.08, 0.075], [0, 0.075]].map(([x, y]) => new THREE.Vector2(x, y)), 18), coffee);
  const collar = new THREE.Mesh(new THREE.TorusGeometry(0.052, 0.014, 8, 18).rotateX(Math.PI / 2), orange);
  collar.position.y = 0.155;
  const lid = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.05, 0.03, 16), orange);
  lid.position.y = 0.185;
  const knob = new THREE.Mesh(new THREE.SphereGeometry(0.014, 8, 6), black);
  knob.position.y = 0.205;
  const handle = new THREE.Mesh(new THREE.TorusGeometry(0.045, 0.012, 8, 14, Math.PI * 1.2), black);
  handle.position.set(0.085, 0.11, 0); handle.rotation.z = -Math.PI * 0.6;
  grp.add(body, fill, collar, lid, knob, handle);
  return grp;
}

function buildBrush(g) {
  const grp = new THREE.Group();
  const cols = ['#E23B3B', '#F7F3EA', '#2F5BD3'];
  for (let i = 0; i < 6; i++) {
    const seg = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.035, 0.014), toon(g, cols[i % 3], { rough: 0.3 }));
    seg.position.y = -0.1 + i * 0.035;
    grp.add(seg);
  }
  const head = new THREE.Mesh(new THREE.BoxGeometry(0.022, 0.06, 0.012), toon(g, '#F7F3EA', { rough: 0.3 }));
  head.position.y = 0.13;
  const bristles = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.05, 0.022), toon(g, '#7FE7FF', { rough: 0.5 }));
  bristles.position.set(0, 0.13, 0.016);
  const paste = new THREE.Mesh(new THREE.CapsuleGeometry(0.008, 0.035, 4, 8).rotateX(Math.PI / 2), toon(g, '#FFFFFF', { rough: 0.3 }));
  paste.rotation.x = Math.PI / 2; paste.position.set(0, 0.13, 0.03);
  grp.add(head, bristles, paste);
  return grp;
}

function fallbackGun(g) {
  const grp = new THREE.Group();
  const steel = toon(g, '#5A6068', { metal: 0.8, rough: 0.3 }), wood = toon(g, '#7A4A2A');
  const barrel = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.035, 0.2), steel); barrel.position.set(0, 0.03, -0.1);
  const grip = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.1, 0.045), wood); grip.position.set(0, -0.03, 0.01); grip.rotation.x = 0.3;
  grp.add(barrel, grip);
  return grp;
}

// ------------------------------------------------------------------------------------------ keyframes
// k(t, keys) with keys = [[t0, v0], [t1, v1], ...] (numbers or arrays): smoothstep between neighbours.
function key(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1] = keys[i];
    if (t <= t1) {
      const [t0, v0] = keys[i - 1];
      const s = smooth(t0, t1, t);
      if (Array.isArray(v0)) return v0.map((a, j) => a + (v1[j] - a) * s);
      return v0 + (v1 - v0) * s;
    }
  }
  return keys[keys.length - 1][1];
}

// ============================================================================================ Sponsors
export class Sponsors {
  constructor(game) {
    this.game = game;
    this.inCommercial = false;
    this.sets = {};
    this.replayBought = 0;
    this._ad = null;
    this._t = 0;
    this._gags = null;
    this._dups = null;
    this._dupHero = null;
    this._built = false;
    this._unsubPre = null;
    this.debugHoldAt = null;
  }

  init() {
    const g = this.game;
    try { this._buildSets(); } catch (err) { console.error('[sponsors] set placement failed', err); }
    g.events.on('power:on', () => { for (const S of Object.values(this.sets)) if (!S.powered && S.waveT < 0) S.pendingPower = true; });
    // leaving play mid-commercial (quit to the title, game over, victory): restore the camera and drop the overlay
    g.events.on('state', (e) => { if (e && (e.to === 'menu' || e.to === 'gameover' || e.to === 'victory')) this._abortCommercial(); });
    // During a commercial nothing may dither the hero (the main camera still runs behind the scenes).
    this._unsubPre = g.render.addPrePass?.(() => {
      if (!this._ad || !g.render.cameraOverride) return;
      g.mats.uniforms.uHeroFade.value = 1;
      const m = g.player?.model;
      if (m && g.player._hidden) m.traverse((o) => { if (o.userData.daHideOnFade) o.visible = true; });
    });
  }

  reset() {
    this._abortCommercial();
    this.replayBought = 0;
    for (const S of Object.values(this.sets)) {
      S.soldOut = false;
      if (S.root.userData.parts?.soldOut) S.root.userData.parts.soldOut.visible = false;
      S.tip = null;
      S.camProp.rotation.set(0, S.camYaw, 0);
      S.camProp.position.set(S.camPos.x, S.camPos.y, S.camPos.z);
      S.shakeT = -1; S.teaseT = -1; S.limitT = 0; S.teaserCd = 0; S.near = false; S.onMark = false;
      this._power(S, S.id === 'replay_ade', true);
    }
  }

  // ------------------------------------------------------------------------------------------ building
  _buildSets() {
    const g = this.game, lv = g.level;
    if (!lv?.anchors) return;
    for (const perkId of PERK_IDS) {
      const a = lv.anchors[`set_${perkId}`];
      if (!a) continue;
      const src = { mark: a.mark || [a.pos.x, 0, a.pos.z], camera: a.camera, area: a.area };
      const fit = fitSet(src);
      const parent = lv.areaRoots?.[a.area] || g.scene;
      const root = placeProp(g, parent, `sponsor_set_${perkId}`, {
        pos: [fit.origin[0], 0, fit.origin[1]], rotY: fit.rotY, area: a.area, opts: { camera: false }, tag: 'sponsor_set',
      });
      root.name = `set_${perkId}`;
      const camId = perkId === 'replay_ade' ? 'sponsor_camera_eng' : 'sponsor_camera_pedestal';
      const camYaw = yawTo(fit.camera[0], fit.camera[1], fit.mark[0], fit.mark[1]);
      const camProp = placeProp(g, parent, camId, { pos: [fit.camera[0], 0, fit.camera[1]], rotY: camYaw, area: a.area, tag: 'sponsor_cam', colliders: false });
      // slim collider (the tripod / pedestal core, not its whole footprint: the lobby and green-room lanes stay open)
      const cr = perkId === 'replay_ade' ? 0.28 : 0.34;
      g.level.col.addBox([fit.camera[0] - cr, 0, fit.camera[1] - cr], [fit.camera[0] + cr, 1.8, fit.camera[1] + cr], { tag: 'sponsor_cam' });
      camProp.name = `set_${perkId}_camera`;
      const u = root.userData;
      const markLocal = u.anchors?.mark || [0, 0.2, -0.75];
      root.updateMatrixWorld(true);
      const mark = new THREE.Vector3(...markLocal).applyMatrix4(root.matrixWorld);
      mark.y = g.level.col.floorAt(mark.x, mark.z, 3);
      if (!Number.isFinite(mark.y)) mark.y = 0.2;
      const fwd = new THREE.Vector3(fit.camera[0] - mark.x, 0, fit.camera[1] - mark.z).normalize();   // mark -> camera
      const right = new THREE.Vector3(fwd.z, 0, -fwd.x);                                             // the viewer's right
      const turntable = u.parts?.turntable || null;
      const product = new THREE.Vector3();
      if (turntable) { turntable.updateWorldMatrix(true, false); turntable.getWorldPosition(product); product.y += 0.75; }
      else product.copy(mark).addScaledVector(fwd, -1.2).setY(1.2);
      const S = {
        id: perkId, area: a.area, root, camProp, camHead: camProp.userData.parts?.head || null, camYaw,
        camPos: camProp.position.clone(), fit, mark, fwd, right, product,
        powered: false, waveT: -1, pendingPower: false, teaseT: -1, teaserCd: 0, near: false, onMark: false,
        limitT: 0, shakeT: -1, soldOut: false, tip: null, lights: (u.lightAnchors || []).map((l) => ({ id: l.id, intensity: l.intensity })),
        headYaw: 0,
      };
      S.cam = this._makeCamera(S);
      S.item = g.interact.register({
        id: `set_${perkId}`, pos: mark.clone(), radius: TP.markRadius, height: 1.6,
        enabled: () => !this._ad && !g.perks?.replayActive && g.state === 'playing',
        prompt: () => this._prompt(S),
        use: () => this._use(S),
      });
      if (g.level.objects) g.level.objects[`set_${perkId}`] = { group: root, parts: u.parts, camera: camProp, set: S };
      this._optimize(S);
      this.sets[perkId] = S;
      this._power(S, perkId === 'replay_ade', true);
    }
    if (g.nav?.built) g.nav.build();
    this._built = true;
  }

  // Draw-call diet (each set was ~90 draws with its camera): the two softbox stands join the static merge, and only
  // the product (on the turntable) and the camera body cast into the key shadow map; the AO bake grounds the rest.
  _optimize(S) {
    const u = S.root.userData, parts = u.parts || {};
    const keep = new Set();
    if (parts.turntable) parts.turntable.traverse((o) => keep.add(o));
    S.root.traverse((o) => { if (o.isMesh && !keep.has(o)) o.castShadow = false; });
    for (const k of ['softL', 'softR']) if (parts[k]) parts[k].userData.noMerge = false;
    try { mergeByMaterial(S.root); } catch (err) { console.warn('[sponsors] merge', err); }
    S.camProp.traverse((o) => {
      if (!o.isMesh) return;
      if (!o.geometry.boundingSphere) o.geometry.computeBoundingSphere();
      o.castShadow = o.geometry.boundingSphere.radius > 0.3;
      o.receiveShadow = false;
    });
  }

  // The commercial camera: along the tally camera's axis, pulled back to frame the whole pantomime (the prop hides
  // during the shot), a little to the viewer's right so the product shows beside the hero.
  _makeCamera(S) {
    const cam = new THREE.PerspectiveCamera(44, 4 / 3, 0.05, 90);
    const [x0, z0, x1, z1] = S.fit.bounds;
    const col = this.game.level?.col;
    S.spot = S.mark.clone().addScaledVector(S.right, 0.32);                        // the hero performs right of the X
    const look = S.mark.clone().addScaledVector(S.right, -0.1).addScaledVector(S.fwd, -0.35);
    look.y = S.mark.y + 1.12;
    // per-set cheat (a big prop with no collider right beside a lens): orbit the shot around the mark / cap its distance
    const cheat = SHOT[S.id] || {};
    const ca = Math.cos(cheat.orbit || 0), sa = Math.sin(cheat.orbit || 0);
    const dir = new THREE.Vector3(S.fwd.x * ca + S.fwd.z * sa, 0, -S.fwd.x * sa + S.fwd.z * ca);
    const side = new THREE.Vector3(dir.z, 0, -dir.x);
    const at = (d) => { const b = S.mark.clone().addScaledVector(dir, d).addScaledVector(side, -0.28); b.y = S.mark.y + 1.3; return b; };
    const within = (p) => p.x > x0 + 0.25 && p.x < x1 - 0.25 && p.z > z0 + 0.25 && p.z < z1 - 0.25;
    // occlusion: rays from the lens to the subject (feet, belly, head, both frame sides, the product)
    const targets = [[0, 0.35, 0], [0, 1.2, 0], [0, 2.05, 0], [1.25, 1.2, 0], [-1.35, 1.2, 0], [-0.3, 1.7, -1.2],
      [1.8, 0.5, 0], [1.8, 1.9, 0], [-1.9, 0.5, 0], [-1.9, 1.9, 0], [1.5, 1.2, 0.8], [-1.6, 1.2, 0.8]];
    const blocked = (b) => {
      if (!col) return 0;
      let n = 0;
      for (const [r, y, f] of targets) {
        _u.copy(S.spot).addScaledVector(S.right, r).addScaledVector(S.fwd, f); _u.y = S.mark.y + y;
        _w.subVectors(b, _u);                     // subject -> lens (a lens inside a prop box is caught too)
        const L = _w.length();
        _w.divideScalar(L);
        const hit = col.raycast(_u, _w, Math.max(0.1, L - 0.25), { ignoreTags: ['sponsor_set', 'sponsor_cam'] });
        if (hit) n++;
      }
      return n;
    };
    let D = 3.0, bestN = Infinity;
    for (let d = Math.min(3.1, cheat.maxD || 3.1); d >= 1.85; d -= 0.1) {
      const b = at(d);
      if (!within(b)) continue;
      const n = blocked(b);
      if (n < bestN) { bestN = n; D = d; }
      if (n === 0) break;
    }
    const base = at(D);
    S.occluded = bestN;
    S.camBase = base; S.camLook = look; S.camD = D;
    cam.fov = THREE.MathUtils.radToDeg(2 * Math.atan(1.36 / D));
    cam.position.copy(base);
    cam.lookAt(look);
    cam.updateProjectionMatrix();
    cam.updateMatrixWorld(true);
    return cam;
  }

  // ------------------------------------------------------------------------------------------ power & tally
  _power(S, on, instant = false) {
    const g = this.game;
    try { setSponsorSetPower(S.root, on); } catch (err) { /* prop without power data */ }
    try { setTally(S.camProp, on && !S.soldOut); } catch (err) { /* ignore */ }
    for (const l of S.lights) g.lights?.setAnchor?.(l.id, { intensity: on ? l.intensity : 0 });
    if (instant) { S.powered = on; S.waveT = -1; S.pendingPower = false; }
  }

  _updatePower(S, rdt) {
    const g = this.game;
    if (S.pendingPower && !S.powered && S.waveT < 0) {
      const reached = g.signon?.waveReached ? g.signon.waveReached(S.mark) : true;
      if (reached || !g.machines?.powerOn) { S.waveT = 0; S.pendingPower = false; S._fi = -1; g.audio?.play?.('light_thunk', { pos: S.product }); }
    }
    if (S.waveT < 0) return;
    S.waveT += rdt;
    let idx = -1;
    for (let i = 0; i < FLICKER.length; i++) if (S.waveT >= FLICKER[i][0]) idx = i;
    if (idx !== S._fi) { S._fi = idx; this._power(S, FLICKER[idx][1]); }
    if (S.waveT > 0.35) { S.waveT = -1; S.powered = true; this._power(S, true, true); }
  }

  setPowered(perkId, on) {
    const S = this.sets[perkId];
    if (S) this._power(S, !!on, true);
  }

  _live(S) { return S.powered || S.id === 'replay_ade'; }

  // ------------------------------------------------------------------------------------------ interaction
  _prompt(S) {
    const g = this.game, P = g.perks;
    if (!P || S.soldOut || P.has(S.id) || this._ad) return null;
    if (P.list.length >= P.max) return null;
    if (!this._live(S)) return { plug: true };
    return { cost: TP[S.id] };
  }

  _use(S) {
    const g = this.game;
    if (!this._live(S)) { g.audio?.play?.('ui_denied'); return; }
    this.buy(S.id);
  }

  buy(perkId) {
    const g = this.game, P = g.perks, S = this.sets[perkId];
    if (!P || this._ad || P.has(perkId) || P.list.length >= P.max) return false;
    if (S && (S.soldOut || !this._live(S))) return false;
    if (perkId === 'replay_ade' && this.replayBought >= TP.replayMax) return false;
    const cost = TP[perkId];
    if (typeof cost !== 'number' || !g.economy?.spend?.(cost, 'perk')) return false;
    if (perkId === 'replay_ade') this.replayBought++;
    if (!S) return P.give(perkId);
    this._startCommercial(S);
    return true;
  }

  playCommercial(perkId, { free = true } = {}) {
    if (!free) return this.buy(perkId);
    const P = this.game.perks, S = this.sets[perkId];
    if (!S || !P || this._ad || P.has(perkId) || P.list.length >= P.max) return false;
    this._startCommercial(S);
    return true;
  }

  debugCommercial(perkId) { return this.playCommercial(perkId, { free: true }); }

  debugSkip() { this.debugHoldAt = null; if (this._ad) this._ad.t = Math.max(this._ad.t, AD - 0.01); }
  // Tests: the running (or next) commercial will not advance past t seconds (null releases it).
  debugHold(t) { this.debugHoldAt = t; return this._ad ? this._ad.t : null; }

  // ------------------------------------------------------------------------------------------ the commercial
  _startCommercial(S) {
    const g = this.game, p = g.player, r = g.render;
    this._ensureGags();
    const ad = {
      S, id: S.id, t: 0, fired: new Set(), cleaned: false, wiped: false,
      scale: g.time.scale, invul: p.invulnerable, music: g.audio?._musicState || null,
      // chroma restores to 0, never a snapshot: at purchase time it usually holds the HUD's hurt pulse, and writing
      // that back makes the HUD's knob mixer keep it forever (a permanent colour fringe after the commercial).
      post: { crt: r.post.crt, saturation: r.post.saturation, vignette: r.post.vignette, grain: r.post.grain, chroma: 0 },
      faceYaw: yawTo(S.spot.x, S.spot.z, S.camBase.x, S.camBase.z),
      starAt: null, props: [], lastCut: -1,
    };
    this._ad = ad;
    this.inCommercial = true;
    g.time.scale = 0;
    p.invulnerable = true;
    p.controlLocked = true;
    p.vel.set(0, 0, 0);
    p.sprinting = false;
    p.ads = false;
    p.teleport(S.spot.x, S.spot.z);
    if (p.weaponModel) { ad.weaponVis = p.weaponModel.visible; p.weaponModel.visible = false; }
    S.camProp.visible = false;
    S.cam.position.copy(S.camBase);
    S.cam.lookAt(S.camLook);
    S.cam.fov = THREE.MathUtils.radToDeg(2 * Math.atan(1.36 / S.camD));
    S.cam.updateProjectionMatrix();
    r.setCameraOverride(S.cam, { aspect: 4 / 3 });
    r.post.crt = 1;
    r.post.saturation = Math.max(r.post.saturation, 1.12);
    r.post.grain = 0.06;
    // key light up for the shoot
    for (const l of S.lights) g.lights?.setAnchor?.(l.id, { intensity: l.intensity * 2.2, enabled: true });
    this._setupPantomime(ad);
    if (p.animator) p.animator.override = (rig, dt) => this._pose(rig, dt);
    g.audio?.music?.('silence');
    g.audio?.play?.('commercial_cut');
    g.audio?.play?.(`sponsor_jingle_${S.id}`, { delay: 0.05 });
    g.events.emit('machine:commercial_start', { perkId: S.id });
    // audio.js ducks the world for 3.2 s on that event; keep it ducked for the whole (longer) commercial
    g.audio?.duck?.(DUCK.db, DUCK.lowpass, AD);
  }

  _abortCommercial() {
    const ad = this._ad;
    if (!ad) return;
    this._cleanupPantomime(ad);
    this._finishRender(ad);
    this._ad = null;
    this.inCommercial = false;
    getOverlay().clear();
  }

  _finishRender(ad) {
    const g = this.game, r = g.render;
    if (r.cameraOverride) r.setCameraOverride(null);
    r.post.crt = ad.post.crt;
    r.post.saturation = ad.post.saturation;
    r.post.grain = ad.post.grain;
    r.post.chroma = ad.post.chroma;
  }

  _updateCommercial(rdt) {
    const g = this.game, ad = this._ad, S = ad.S, p = g.player;
    ad.t += rdt;
    if (this.debugHoldAt != null && ad.t > this.debugHoldAt) ad.t = this.debugHoldAt;
    const t = ad.t;
    const once = (key, at, fn) => { if (t >= at && !ad.fired.has(key)) { ad.fired.add(key); try { fn(); } catch (err) { console.warn('[sponsors] beat', key, err); } } };
    const ov = getOverlay();
    const st = { mode: 'commercial', t, perkId: S.id, flash: 0, cut: clamp01(t / 0.3), osd: null, tracking: 0, splice: 0, card: -1, star: null };
    if (t < 0.07) st.flash = 1 - t / 0.07;
    if (!ad.cleaned) this._beats(ad, t, st, once);
    // logo card
    if (t >= T_CARD) {
      st.card = clamp01((t - T_CARD) / (T_SETTLE - T_CARD));
      st.cardHold = clamp01((t - T_SETTLE) / (T_WIPE - T_SETTLE));   // 0..1 across the held card (commercial.js)
      once('ding', T_CARD, () => g.audio?.play?.('commercial_ding'));
      once('wah', T_CARD + 0.14, () => g.audio?.play?.('announcer_wahwah', { rhythm: WAH[S.id] }));
      once('starAt', T_CARD, () => { ad.starAt = this._project(S.product, S.cam); });
      // button-up sting: the product's 1 s teaser motif (same key as its jingle), unducked on the music bus
      once('button', T_BUTTON, () => g.audio?.play?.(`sponsor_teaser_${S.id}`, { bus: 'music', vol: 0.85 }));
    }
    if (t >= T_CLEAN && !ad.cleaned) { ad.cleaned = true; this._cleanupPantomime(ad); }
    // star wipe back to the game + costume pop
    if (t >= T_WIPE) {
      if (!ad.wiped) {
        ad.wiped = true;
        this._finishRender(ad);
        S.camProp.visible = true;
        g.audio?.play?.('star_wipe');
        g.perks?.attachCostume?.(S.id, { pop: true });
        g.audio?.play?.('costume_pop', { delay: 0.06 });
        for (const l of S.lights) g.lights?.setAnchor?.(l.id, { intensity: l.intensity });
      }
      const k = clamp01((t - T_WIPE) / (AD - T_WIPE));
      const at = ad.starAt || { x: innerWidth / 2, y: innerHeight / 2 };
      const far = Math.max(Math.hypot(at.x, at.y), Math.hypot(innerWidth - at.x, at.y), Math.hypot(at.x, innerHeight - at.y), Math.hypot(innerWidth - at.x, innerHeight - at.y));
      st.star = { x: at.x, y: at.y, r: (far / 0.4 + 60) * (0.03 + 0.97 * k ** 2.1), rot: k * 0.9 };
    }
    if (t >= AD) { this._endCommercial(); return; }
    ov.draw(st);
  }

  _endCommercial() {
    const g = this.game, ad = this._ad, S = ad.S, p = g.player;
    if (!ad.cleaned) this._cleanupPantomime(ad);
    if (!ad.wiped) { this._finishRender(ad); S.camProp.visible = true; g.perks?.attachCostume?.(S.id, { pop: false }); }
    getOverlay().clear();
    this._ad = null;
    this.inCommercial = false;
    g.time.scale = ad.scale > 0 ? ad.scale : 1;
    p.controlLocked = false;
    p.invulnerable = !!g.perks?.replayActive || (g.perks?._invulnT > 0);
    if (ad.music) g.audio?.music?.(ad.music);
    // the studio lights flash and shove the zombies within 3 m back 2 m
    const zs = g.zombies?.inRadius ? g.zombies.inRadius(p.pos, 3, []) : [];
    for (const z of zs) {
      _v.subVectors(z.pos, p.pos).setY(0);
      if (_v.lengthSq() < 1e-4) _v.set(Math.random() - 0.5, 0, Math.random() - 0.5);
      g.zombies.knockback?.(z, _v.normalize().multiplyScalar(2));
    }
    _v.copy(S.product).addScaledVector(S.fwd, 1.2);
    g.lights?.flash?.(_v, '#FFF2D8', 10, 0.3, 10);
    g.hud?.whiteout?.(0.45, 0.28);
    g.audio?.play?.('studio_flash');
    // the perk itself
    const ok = g.perks?.give?.(S.id, { costume: false, pop: false, emit: true });
    if (!ok && g.perks && !g.perks.has(S.id)) g.perks.detachCostume?.(S.id, { poof: false });
    if (S.id === 'replay_ade' && this.replayBought >= TP.replayMax) this._soldOut(S);
    g.events.emit('machine:commercial_end', { perkId: S.id });
  }

  _project(pos, cam) {
    cam.updateMatrixWorld(true);
    _v.copy(pos).project(cam);
    const vp = getOverlay().viewport(4 / 3);
    return { x: vp.x + (_v.x * 0.5 + 0.5) * vp.w, y: vp.y + (1 - (_v.y * 0.5 + 0.5)) * vp.h };
  }

  // ------------------------------------------------------------------------------------------ sold out (Replay-Ade)
  _soldOut(S) {
    S.soldOut = true;
    S.tip = { t: -0.35, a: 0, v: 0, bounced: 0 };
    try { setTally(S.camProp, false); } catch (err) { /* ignore */ }
  }

  _updateTip(S, rdt) {
    const tip = S.tip;
    if (!tip) return;
    tip.t += rdt;
    if (tip.t < 0) { S.camProp.rotation.z = Math.sin(tip.t * 60) * 0.02; return; }
    const g = this.game;
    if (!tip.done) {
      tip.v += (4 + Math.sin(tip.a) * 14) * rdt;
      tip.a += tip.v * rdt;
      if (tip.a >= 1.42) {
        tip.a = 1.42;
        if (tip.bounced < 2) {
          tip.v = -tip.v * (tip.bounced ? 0.2 : 0.32);
          tip.bounced++;
          g.audio?.play?.('land', { pos: S.camPos, rate: 0.55, vol: 1 });
          if (tip.bounced === 1) {
            g.fx?.burst?.(_v.copy(S.camPos).addScaledVector(S.fwd, -0.9).setY(0.1), { shape: 'puff', count: 10, speed: 1.6, size: 0.25, life: 0.8 });
            const parts = S.root.userData.parts;
            if (parts?.soldOut) { parts.soldOut.visible = true; parts.soldOut.scale.setScalar(0.01); tip.tape = 0; }
          }
        } else { tip.v = 0; tip.done = true; }
      }
    }
    // tip toward the mark (around the base's front edge)
    S.camProp.rotation.set(-tip.a, S.camYaw, 0, 'YXZ');
    S.camProp.position.set(S.camPos.x, S.camPos.y + Math.sin(tip.a) * 0.22, S.camPos.z);
    if (tip.tape !== undefined && tip.tape < 1) {
      tip.tape = Math.min(1, tip.tape + rdt / 0.3);
      S.root.userData.parts.soldOut.scale.setScalar(Math.max(0.01, easeOutBack(tip.tape, 2.4)));
    }
  }

  // ------------------------------------------------------------------------------------------ per frame
  update(dt) {
    const g = this.game;
    const rdt = g.time.realDt || 0;
    this._t += rdt;
    if (this._ad) {
      try { this._updateCommercial(rdt); } catch (err) { console.error('[sponsors] commercial', err); this._abortCommercial(); }
    }
    const p = g.player, P = g.perks;
    if (!p) return;
    for (const S of Object.values(this.sets)) {
      this._updatePower(S, rdt);
      this._updateTip(S, rdt);
      const dx = p.pos.x - S.mark.x, dz = p.pos.z - S.mark.z;
      const d = Math.hypot(dx, dz);
      // [E] anywhere within the mark radius, no facing requirement: the item rides along with the player
      if (d <= TP.markRadius && !this._ad) S.item.pos.copy(p.pos); else S.item.pos.copy(S.mark);
      const visible = S.root.parent ? S.root.parent.visible !== false : true;
      if (visible) { try { animateProduct(S.root, this._t); } catch (err) { /* ignore */ } }
      this._updateTeaser(S, d, dt, rdt);
      // perk limit: the camera shakes its head when you step onto the X
      const onMark = d <= TP.markRadius;
      S.limitT = Math.max(0, S.limitT - rdt);
      if (onMark && !S.onMark && P && !this._ad && !S.soldOut && !P.has(S.id) && P.list.length >= P.max && this._live(S) && S.limitT <= 0) {
        S.limitT = 3;
        S.shakeT = 0;
        g.audio?.play?.('sponsor_denied', { pos: S.camPos });
      }
      S.onMark = onMark;
      this._updateCameraHead(S, d, rdt);
    }
  }

  _updateTeaser(S, d, dt, rdt) {
    const g = this.game;
    S.teaserCd = Math.max(0, S.teaserCd - rdt);
    const near = d <= 5;
    if (near && !S.near && S.teaserCd <= 0 && this._live(S) && !S.soldOut && !this._ad && dt > 0) {
      S.teaserCd = 8;
      S.teaseT = 0;
      g.audio?.play?.(`sponsor_teaser_${S.id}`, { pos: S.product });
    }
    S.near = near;
    const tt = S.root.userData.parts?.turntable;
    if (S.teaseT >= 0) {
      S.teaseT += rdt;
      const k = S.teaseT;
      const prod = S.root.userData.parts?.product;
      if (prod) {
        const hop = Math.max(0, Math.sin(Math.min(1, k / 0.45) * Math.PI)) * 0.14 + Math.max(0, Math.sin(clamp01((k - 0.45) / 0.3) * Math.PI)) * 0.05;
        prod.position.y = 0.045 + hop;
        const sq = 1 + Math.sin(k * 26) * 0.06 * Math.max(0, 1 - k);
        prod.scale.set(1 / Math.sqrt(sq), sq, 1 / Math.sqrt(sq));
      }
      if (tt) tt.rotation.y += rdt * 7 * Math.max(0, 1 - k);
      if (k > 1.05) { S.teaseT = -1; if (prod) { prod.position.y = 0.045; prod.scale.set(1, 1, 1); } }
    }
  }

  _updateCameraHead(S, d, rdt) {
    const H = S.camHead;
    if (!H) return;
    const g = this.game, p = g.player;
    let yaw = 0;
    if (S.shakeT >= 0) {
      S.shakeT += rdt;
      const k = S.shakeT / 1.2;
      yaw = Math.sin(k * TAU * 2) * 0.5 * (1 - k * 0.5);
      const blink = Math.floor(S.shakeT / 0.1) % 2 === 0;
      try { setTally(S.camProp, blink && this._live(S) && !S.soldOut); } catch (err) { /* ignore */ }
      if (k >= 1) { S.shakeT = -1; try { setTally(S.camProp, this._live(S) && !S.soldOut); } catch (err) { /* ignore */ } }
    } else if (d < 3.5 && this._live(S) && !S.soldOut && !this._ad) {
      // follow the player around the mark
      const want = Math.atan2(-(p.pos.x - S.camPos.x), -(p.pos.z - S.camPos.z)) - S.camYaw;
      yaw = THREE.MathUtils.clamp(Math.atan2(Math.sin(want), Math.cos(want)), -0.6, 0.6);
    } else {
      yaw = Math.sin(this._t * 0.35 + S.id.length) * 0.06;
    }
    if (S.tip) yaw = 0;
    S.headYaw += (yaw - S.headYaw) * (S.shakeT >= 0 ? 1 : 1 - Math.exp(-rdt * 4));
    H.rotation.y = S.headYaw;
  }

  // ------------------------------------------------------------------------------------------ gag props
  _ensureGags() {
    const g = this.game;
    if (!this._gags) {
      const G = {};
      const safe = (name, fn) => { try { G[name] = fn(); } catch (err) { console.warn('[sponsors] gag', name, err); } };
      safe('bottle', () => { const b = buildProp('product_replay_ade', g, {}); b.scale.setScalar(0.19); return b; });
      safe('peel', () => buildPeel(g));
      safe('spoon', () => buildSpoon(g));
      safe('glove', () => buildGlove(g));
      safe('pot', () => buildPot(g));
      safe('brush', () => { const b = buildBrush(g); b.scale.setScalar(1.7); return b; });
      safe('gun', () => { const m = g.weapons?.buildModel?.('revolver_38', false); return m || fallbackGun(g); });
      safe('skates', () => buildProp('costume_skates', g, {}));
      for (const o of Object.values(G)) {
        const root = o.grp || o;
        root.traverse?.((m) => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = false; } });
      }
      this._gags = G;
    }
    const hero = g.player?.hero;
    if (hero && this._dupHero !== hero) {
      if (this._dups) for (const d of this._dups) d.holder.parent?.remove(d.holder);
      this._dups = [];
      this._dupHero = hero;
      for (const col of [PAL.gelCyan, PAL.gelMagenta]) {
        const c = cloneHero(hero, [g.player.weaponModel]);
        const c3 = new THREE.Color(col);
        // flat tinted Lambert (no vertex colours: the baked body's RGBA colours + colour morphs break Lambert's morph path)
        const mat = new THREE.MeshLambertMaterial({ color: c3, emissive: c3.clone().multiplyScalar(0.5), transparent: true, opacity: 0.8, depthWrite: true, fog: false });
        for (const m of c.meshes) {
          m.material = mat;
          if (!m.geometry.boundingSphere) m.geometry.computeBoundingSphere();
          if (!m.isSkinnedMesh && m.geometry.boundingSphere.radius < 0.025) m.visible = false;
        }
        const holder = new THREE.Group();
        holder.add(c.group);
        this._dups.push({ ...c, holder, color: col });
      }
    }
  }

  warmup() {
    const out = [];
    try {
      this._ensureGags();
      for (const o of Object.values(this._gags || {})) out.push(o.grp || o);
      for (const d of this._dups || []) out.push(d.holder);
    } catch (err) {
      console.warn('[sponsors] warmup', err);
    }
    return out;
  }

  // ------------------------------------------------------------------------------------------ pantomimes
  _setupPantomime(ad) {
    const g = this.game, p = g.player, G = this._gags || {}, hero = p.hero;
    const add = (name, obj) => { if (!obj) return null; const root = obj.grp || obj; p.model.add(root); root.visible = true; ad.props.push(root); return obj; };
    ad.face = hero?.art?.face || null;
    switch (ad.id) {
      case 'replay_ade': add('bottle', G.bottle); add('peel', G.peel); break;
      case 'wobble_up': add('spoon', G.spoon); if (G.spoon) G.spoon.jelly.visible = true; if (G.glove) { add('glove', G.glove); setExtend(G.glove, 0.2); } break;
      case 'jump_cut': add('pot', G.pot); if (G.gun) { add('gun', G.gun); G.gun.visible = false; } break;
      case 'roller_boogie': {
        const sk = G.skates, parts = sk?.userData?.parts;
        if (parts && hero?.slots) {
          ad.skates = [];
          for (const side of ['footL', 'footR']) {
            const part = parts[side];
            if (!part || !hero.slots[side]) continue;
            part.position.set(0, 0, 0); part.rotation.set(0, 0, 0);
            hero.slots[side].add(part);
            ad.skates.push(part);
          }
        }
        break;
      }
      case 'double_vision': add('brush', G.brush); break;
      default: break;
    }
  }

  _cleanupPantomime(ad) {
    const g = this.game, p = g.player;
    if (p?.animator && p.animator.override) p.animator.override = null;
    for (const o of ad.props) o.parent?.remove(o);
    ad.props.length = 0;
    if (ad.skates) {
      const parts = this._gags?.skates?.userData?.parts;
      for (const part of ad.skates) { part.parent?.remove(part); }
      ad.skates = null;
      void parts;
    }
    if (this._dups) for (const d of this._dups) d.holder.parent?.remove(d.holder);
    if (p?.weaponModel) p.weaponModel.visible = ad.weaponVis ?? true;
    if (p?.model) p.model.visible = true;
    try { ad.face?.setExpression?.('neutral', 1); } catch (err) { /* ignore */ }
    const S = ad.S;
    S.camProp.visible = !g.render.cameraOverride;
    const r = g.render;
    r.post.chroma = ad.post.chroma;
  }

  // Camera beats, overlay FX, particles and sounds of each pantomime (sponsors.update, real time).
  _beats(ad, t, st, once) {
    const g = this.game, S = ad.S, cam = S.cam, sp = g.perks?.sparkles, p = g.player;
    const worldOf = (obj, out = _v) => { obj.updateWorldMatrix(true, false); return obj.getWorldPosition(out); };
    // default framing (jump cut changes it)
    const frame = (dIn = 0, side = 0, up = 0, fovMul = 1, lookUp = 0) => {
      cam.position.copy(S.camBase).addScaledVector(S.fwd, -dIn).addScaledVector(S.right, side);
      cam.position.y += up;
      _w.copy(S.camLook); _w.y += lookUp;
      cam.lookAt(_w);
      const f = THREE.MathUtils.radToDeg(2 * Math.atan(1.36 / S.camD)) * fovMul;
      if (Math.abs(cam.fov - f) > 1e-3) { cam.fov = f; cam.updateProjectionMatrix(); }
    };
    switch (ad.id) {
      case 'replay_ade': {
        frame(0, 0, 0, 1);
        if (t >= 1.25 && t < 1.4) { st.osd = 'pause'; st.tracking = 0.25; }
        if (t >= 1.4 && t < 1.86) { st.osd = 'rew'; st.tracking = 0.9; g.render.post.chroma = 3; }
        else g.render.post.chroma = ad.post.chroma;
        once('glug', 0.3, () => { if (sp && ad.props[0]) sp.emit(worldOf(ad.props[0]), { count: 6, colors: ['#FFE14D', '#7FB8FF'], speed: 0.8, size: 0.05, life: 0.4, gravity: 3 }); });
        once('slip', 0.86, () => { g.audio?.play?.('telly_boing', { vol: 0.8 }); if (sp) sp.emit(_w.copy(S.spot).setY(S.mark.y + 0.15), { kind: 'puff', count: 5, speed: 1.2, size: 0.12, life: 0.4, gravity: -0.4 }); });
        once('freeze', 1.25, () => g.audio?.play?.('commercial_cut', { vol: 0.6 }));
        once('rew', 1.4, () => g.audio?.play?.('replay_rewind'));
        once('land', 1.86, () => { g.audio?.play?.('land', { vol: 0.8 }); });
        once('thumb', 1.98, () => { if (sp && p.hero) sp.emit(worldOf(p.hero.slots.handR), { count: 1, color: '#FFFFFF', speed: 0.01, size: 0.34, life: 0.5, gravity: 0, spin: 4 }); g.audio?.play?.('smile_ting', { vol: 0.6 }); });
        break;
      }
      case 'wobble_up': {
        const shake = t > 0.72 && t < 1.0 ? Math.sin(t * 90) * 0.03 * (1 - (t - 0.72) / 0.28) : 0;
        frame(0, shake, 0, 1);
        once('gulp', 0.45, () => { if (this._gags.spoon) this._gags.spoon.jelly.visible = false; });
        once('pow', 0.72, () => {
          g.audio?.play?.('melee_hit_skip', { vol: 0.9 });
          g.audio?.play?.('jelly_bwoing', { delay: 0.05 });
          if (sp && p.hero) sp.emit(worldOf(p.hero.parts.head), { count: 12, colors: ['#FFE27A', '#FFFFFF', '#52E04A'], speed: 3, size: 0.12, life: 0.55, gravity: 0.5 });
        });
        once('thumb', 1.85, () => { if (sp && p.hero) sp.emit(worldOf(p.hero.slots.handR), { count: 1, color: '#FFFFFF', speed: 0.01, size: 0.34, life: 0.5, gravity: 0, spin: 4 }); g.audio?.play?.('smile_ting', { vol: 0.6 }); });
        break;
      }
      case 'jump_cut': {
        const cuts = [0.7, 1.2, 1.7];
        let c = -1;
        for (let i = 0; i < 3; i++) if (t >= cuts[i]) c = i;
        if (c === -1) frame(0, 0, 0, 1);
        else if (c === 0) frame(0.55, -0.35, -0.05, 0.86, 0.08);
        else if (c === 1) frame(-0.2, 0.45, 0.1, 1.04, 0);
        else frame(1.05, 0.12, 0.18, 0.72, 0.42);
        for (let i = 0; i < 3; i++) {
          const dtc = t - cuts[i];
          if (dtc >= 0 && dtc < 0.06) st.splice = 1 - dtc / 0.06;
          once('cut' + i, cuts[i], () => { g.audio?.play?.('commercial_cut'); g.audio?.play?.('jumpcut_snip', { delay: 0.02 }); });
        }
        if (t < 0.7 && sp && this._gags.pot && Math.random() < rdtChance(g, 22)) sp.emit(worldOf(this._gags.pot, _w).add(_u.set(0, 0.22, 0)), { kind: 'puff', count: 1, colors: ['#FFFFFF', '#F2EEE6'], speed: 0.3, size: 0.045, life: 0.9, gravity: -0.35, dir: _u.set(0, 1, 0), cone: 0.35, grow: 2.6 });
        once('reload', 1.45, () => {
          g.audio?.play?.('reload_speedloader', { vol: 0.8 });
          if (sp && this._gags.gun) sp.emit(worldOf(this._gags.gun), { count: 8, colors: ['#FFE27A', '#FFFFFF'], speed: 1.6, size: 0.08, life: 0.4, gravity: 0 });
        });
        once('wink', 1.8, () => { if (sp && p.hero) sp.emit(worldOf(p.hero.parts.head, _w).add(_u.set(0, 0.05, 0)).addScaledVector(S.fwd, 0.2), { count: 1, color: '#FFFFFF', speed: 0.01, size: 0.3, life: 0.45, gravity: 0, spin: 5 }); g.audio?.play?.('smile_ting', { vol: 0.55 }); });
        break;
      }
      case 'roller_boogie': {
        frame(0, 0, 0, 1);
        once('whoosh', 0.14, () => g.audio?.play?.('melee_whoosh', { rate: 0.6, vol: 0.9 }));
        once('push1', 0.64, () => g.audio?.play?.('skate_push'));
        once('push2', 0.92, () => g.audio?.play?.('skate_push'));
        once('disco', 1.52, () => { if (sp && p.hero) sp.emit(worldOf(p.hero.slots.handR), { count: 16, colors: ['#FF9EDB', '#7FE7FF', '#FFE27A', '#FFFFFF'], speed: 2.6, size: 0.1, life: 0.7, gravity: 0.3 }); g.audio?.play?.('smile_ting', { vol: 0.5 }); });
        if (sp && p.hero && ((t > 0.12 && t < 0.4) || (t > 0.62 && t < 1.35)) && Math.random() < rdtChance(g, 70)) {
          for (const side of ['footL', 'footR']) sp.emit(worldOf(p.hero.slots[side]), { count: 1, colors: ['#FF9EDB', '#7FE7FF', '#FFE27A'], speed: 0.3, size: 0.07, life: 0.5, gravity: -0.2 });
        }
        break;
      }
      case 'double_vision': {
        frame(0, 0, 0, 1);
        if (t < 0.8 && sp && p.hero && Math.random() < rdtChance(g, 16)) sp.emit(worldOf(p.hero.parts.head, _w).addScaledVector(S.fwd, 0.22).add(_u.set(0, -0.08, 0)), { kind: 'puff', count: 1, colors: ['#FFFFFF', '#DFF8FF'], speed: 0.4, size: 0.045, life: 0.5, gravity: 0.6, grow: 1.5 });
        once('ting', 0.95, () => {
          g.audio?.play?.('smile_ting');
          if (sp && p.hero) sp.emit(worldOf(p.hero.parts.head, _w).addScaledVector(S.fwd, 0.24).add(_u.set(0.03, -0.06, 0)), { count: 1, color: '#FFFFFF', speed: 0.01, size: 0.46, life: 0.55, gravity: 0, spin: 6 });
        });
        once('split', 1.2, () => {
          for (const d of this._dups || []) { p.model.parent?.add(d.holder); }
          g.audio?.play?.('commercial_cut', { vol: 0.5 });
        });
        if (t >= 1.2) g.render.post.chroma = 2 + 5 * Math.max(0, 1 - (t - 1.2) / 0.5);
        break;
      }
      default: frame();
    }
  }

  // animator.override: the pantomime pose (real dt), after the procedural pose. Also places the hero and gag props.
  _pose(rig, dt) {
    const ad = this._ad;
    if (!ad) return;
    const g = this.game, p = g.player, J = rig.joints, t = ad.t, S = ad.S, m = p.model, G = this._gags || {};
    const W = smooth(0, 0.1, t);
    const setJ = (name, e, w = 1) => { const j = J[name]; if (!j || !e) return; _q.setFromEuler(_e.set(e[0], e[1], e[2])); j.quaternion.slerp(_q, w * W); };
    const pose = (P, w = 1) => { for (const n in P) setJ(n, P[n], w); };
    m.position.copy(S.spot);
    m.rotation.y = ad.faceYaw;
    const face = ad.face;
    const expr = (name, w = 1) => { try { if (face && ad._expr !== name) { face.setExpression(name, w); ad._expr = name; } } catch (err) { /* ignore */ } };
    const REST = { shoulderL: [0.05, 0, 0.1], shoulderR: [0.05, 0, -0.1], elbowL: [0.25, 0, 0], elbowR: [0.25, 0, 0], spine: [0, 0, 0], head: [0, 0, 0] };
    const ID = hero(p);
    switch (ad.id) {
      case 'replay_ade': {
        // logical time: play -> freeze at 1.25 -> rewind back to 0.65 by 1.86 -> land
        let tau = t;
        if (t >= 1.25 && t < 1.4) tau = 1.25;
        else if (t >= 1.4 && t < 1.86) tau = 1.25 - ((t - 1.4) / 0.46) * 0.6;
        else if (t >= 1.86) tau = 0.65;
        const drink = key(tau, [[0, 0], [0.18, 1], [0.58, 1], [0.72, 0]]);
        const step = key(tau, [[0.62, 0], [0.84, 1]]);
        const slip = smooth(0.84, 1.25, tau);
        pose(REST);
        setJ('shoulderR', [lerp(0.2, 1.25, drink), 0, lerp(-0.1, -0.45, drink)]);
        setJ('elbowR', [lerp(0.4, 2.15, drink), 0, 0]);
        setJ('head', [0.42 * drink * smooth(0.2, 0.35, tau), 0, 0]);
        setJ('spine', [0.1 * drink, 0, 0]);
        setJ('shoulderL', [0.1, 0, 0.1 + 0.25 * drink]);
        // step onto the peel
        setJ('hipR', [0.45 * step * (1 - slip), 0, 0]);
        setJ('kneeR', [-0.5 * step * (1 - step), 0, 0]);
        // slip: legs fly up, body goes over backward, arms flail
        if (slip > 0) {
          const a = slip * 1.6, h = rig.dims?.hipsY || 0.9;
          rig.root.rotation.x = a;
          rig.root.position.set(0, h - h * Math.cos(a) + Math.sin(Math.min(1, slip * 1.15) * Math.PI * 0.5) * 0.7, -h * Math.sin(a) * 0.4);
          setJ('hipL', [1.2 * slip, 0, 0]); setJ('hipR', [1.5 * slip, 0, 0]);
          setJ('kneeL', [-0.6 * slip, 0, 0]); setJ('kneeR', [-0.3 * slip, 0, 0]);
          setJ('shoulderL', [2.6 * slip, 0, 0.7 * slip]); setJ('shoulderR', [2.4 * slip + 0.4, 0, -0.8 * slip]);
          setJ('elbowL', [0.3, 0, 0]); setJ('elbowR', [0.4, 0, 0]);
          setJ('head', [-0.4 * slip, 0, 0]);
          expr('o_mouth');
        } else expr(drink > 0.5 ? 'smile' : 'neutral');
        m.position.addScaledVector(S.fwd, 0.22 * step);
        if (t >= 1.86) {
          const k = smooth(1.86, 2.02, t);
          const land = Math.max(0, Math.sin(clamp01((t - 1.86) / 0.22) * Math.PI));
          rig.root.scale.set(1 + land * 0.07, 1 - land * 0.12, 1 + land * 0.07);
          setJ('shoulderR', [1.05, 0, -0.2], k); setJ('elbowR', [1.4, 0, 0], k);
          setJ('shoulderL', [0.85, 0, 0.35], k); setJ('elbowL', [1.25, 0, 0], k);
          setJ('head', [0.12, 0, 0.14], k);
          expr('wink');
        }
        // the bottle rides the right hand; the peel lies ahead and shoots away on the slip (and back on rewind)
        if (t < 1.86) this._propAtHand(G.bottle, p, 'handR', m, [0, 0.02, -0.03], [-(0.2 + 1.75 * drink * smooth(0.18, 0.4, tau)), 0, 0], 1);
        else this._propAtHand(G.bottle, p, 'handL', m, [0, 0.03, -0.03], [0.15, 0, 0.25], 1);
        if (G.peel) {
          G.peel.position.set(-0.05, 0.004, -0.36 - slip * 1.4);
          G.peel.position.y = Math.sin(slip * Math.PI) * 0.4;
          G.peel.rotation.set(slip * 5, slip * 3, 0);
        }
        break;
      }
      case 'wobble_up': {
        const eat = key(t, [[0, 0], [0.16, 1], [0.48, 1], [0.62, 0]]);
        const hit = smooth(0.66, 0.72, t) * (1 - smooth(0.95, 1.2, t));
        pose(REST);
        setJ('shoulderR', [lerp(0.25, 1.2, eat), 0, lerp(-0.1, -0.42, eat)]);
        setJ('elbowR', [lerp(0.5, 2.2, eat), 0, 0]);
        setJ('shoulderL', [0.1, 0, 0.1]);
        setJ('head', [0.1 * eat - 0.05 * hit, -0.55 * hit, -0.45 * hit]);
        setJ('spine', [0, -0.25 * hit, -0.28 * hit]);
        expr(t < 0.5 ? (eat > 0.5 ? 'o_mouth' : 'neutral') : t < 0.72 ? 'smile' : t < 1.6 ? 'o_mouth' : 'smile');
        // gelatin jiggle after the punch
        if (t > 0.72) {
          const tt = t - 0.72, amp = 0.42 * Math.exp(-2.1 * tt);
          const y = 1 + amp * Math.sin(tt * 21), xz = 1 / Math.sqrt(Math.max(0.4, y));
          rig.root.scale.set(xz * (1 + amp * 0.25 * Math.sin(tt * 17)), y, xz);
          const sway = amp * Math.sin(tt * 18 + 1) * 0.8;
          setJ('spine', [0, 0, sway], 1);
          setJ('chest', [0, 0, -sway * 0.7], 1);
          setJ('head', [0, 0, sway * 1.2], 1);
        }
        if (t > 1.72) pose(POSES.thumbsup, smooth(1.72, 1.9, t));
        this._propAtHand(G.spoon, p, 'handR', m, [0, 0.0, -0.02], [-(0.3 + 1.1 * eat), 0, 0], 1);
        if (G.glove) {
          const out = key(t, [[0.5, 0], [0.72, 1], [0.86, 1], [1.2, 0]]);
          const len = lerp(0.18, 2.3, easeOut(out));
          setExtend(G.glove, len);
          // box sits off frame (the hero's right = frame left), the glove punches toward the cheek
          const headY = (rig.dims?.height || 1.75) * 0.87;
          G.glove.grp.position.set(2.75, headY - 0.06, -0.1);
          G.glove.grp.rotation.set(0, Math.PI, 0);
          G.glove.grp.visible = t > 0.45 && t < 1.25;
        }
        break;
      }
      case 'jump_cut': {
        const cuts = [0.7, 1.2, 1.7];
        pose(REST);
        if (t < cuts[0]) {
          const sip = key(t, [[0, 0], [0.18, 1], [0.55, 1], [0.7, 0.8]]);
          setJ('shoulderR', [lerp(0.3, 1.15, sip), 0, lerp(-0.1, -0.4, sip)]);
          setJ('elbowR', [lerp(0.6, 2.05, sip), 0, 0]);
          setJ('head', [0.18 * sip, 0, 0]);
          setJ('shoulderL', [0.2, 0, 0.12]);
          expr(sip > 0.6 && t > 0.35 ? 'o_mouth' : 'smile');
          this._propAtHand(G.pot, p, 'handR', m, [0, -0.06, -0.02], [-(0.15 + 0.6 * sip * smooth(0.2, 0.4, t)), 0, 0], 1);
          if (G.gun) G.gun.visible = false;
        } else if (t < cuts[1]) {
          // arms crossed, chin up
          if (G.pot) G.pot.visible = false;
          // upper arms down, forearms folded across the chest (the shoulder's y twist aims the elbow bend inward)
          setJ('shoulderL', [0.42, -1.0, 0.12]); setJ('elbowL', [1.95, 0, 0]);
          setJ('shoulderR', [0.34, 1.0, -0.12]); setJ('elbowR', [1.85, 0, 0]);
          setJ('head', [0.18, 0.2, 0.08]);
          setJ('spine', [0.08, 0, 0]);
          expr('smile');
        } else if (t < cuts[2]) {
          // finger guns (the prop revolver in the right hand reloads itself)
          pose(POSES.fingerguns);
          setJ('head', [0.05, 0.15, -0.12]);
          expr('smile');
          if (G.gun) {
            G.gun.visible = true;
            const spin = smooth(1.42, 1.56, t);
            this._propAtHand(G.gun, p, 'handR', m, [0, -0.02, -0.04], [0, 0, 0], 1, spin * TAU);
          }
        } else {
          // wink + point at the viewer
          if (G.gun) G.gun.visible = false;
          setJ('shoulderR', [1.45, 0, -0.15]); setJ('elbowR', [0.15, 0, 0]);
          setJ('shoulderL', [0.1, 0, 0.1]);
          setJ('head', [0.1, 0, 0.22]);
          setJ('spine', [0, 0.12, 0]);
          expr('wink');
        }
        break;
      }
      case 'roller_boogie': {
        const lift = 0.118;
        const outK = easeIn(clamp01((t - 0.12) / 0.28));
        const inK = easeOut(clamp01((t - 0.62) / 0.68));
        let x = 0, spin = 0, smear = 0;
        if (t < 0.12) { x = 0; }
        else if (t < 0.4) { x = 3.8 * outK; smear = outK; }
        else if (t < 0.62) { x = 99; }
        else { x = -3.8 * (1 - inK); spin = (1 - inK) * TAU * 2.2; smear = (1 - inK) * 0.7; }
        m.position.addScaledVector(S.right, -x);           // model +x (hero's right) = the viewer's left
        m.rotation.y = ad.faceYaw + spin;
        m.visible = x !== 99;
        rig.root.position.y += lift;
        const crouch = t < 0.12 ? smooth(0, 0.12, t) : t < 1.35 ? 1 : 1 - smooth(1.35, 1.55, t);
        setJ('kneeL', [-0.7 * crouch, 0, 0]); setJ('kneeR', [-0.35 * crouch, 0, 0]);
        setJ('hipL', [0.45 * crouch, 0, -0.1]); setJ('hipR', [-0.2 * crouch, 0, 0.18 * crouch]);
        setJ('spine', [-0.3 * crouch, 0, 0]);
        setJ('shoulderL', [0.4, 0, -0.9 * crouch]); setJ('shoulderR', [0.2, 0, 0.9 * crouch]);
        setJ('elbowL', [0.3, 0, 0]); setJ('elbowR', [0.3, 0, 0]);
        if (smear > 0) {
          const k = smear;
          rig.root.scale.set(1 + 1.4 * k, 1 - 0.18 * k, 1 - 0.2 * k);
        }
        if (t > 1.5) {
          const k = smooth(1.5, 1.66, t);
          pose(DISCO, k);
          setJ('hipL', [0, 0, -0.12 * k]);
          const pop = Math.sin(clamp01((t - 1.5) / 0.3) * Math.PI) * 0.06;
          rig.root.position.x += pop;
        }
        expr(t > 1.45 ? 'smile' : 'neutral');
        break;
      }
      case 'double_vision': {
        const brush = key(t, [[0, 0], [0.12, 1], [0.78, 1], [0.92, 0]]);
        pose(REST);
        const scrub = Math.sin(t * 52) * 0.12 * brush;
        setJ('shoulderR', [lerp(0.25, 1.3, brush), 0, lerp(-0.1, -0.5, brush) + scrub]);
        setJ('elbowR', [lerp(0.5, 2.25, brush), 0, 0]);
        setJ('shoulderL', [0.1, 0, 0.1]);
        setJ('head', [0.05 * brush, Math.sin(t * 26) * 0.03 * brush, 0]);
        expr(t < 0.8 ? 'o_mouth' : 'smile');
        this._propAtHand(G.brush, p, 'handR', m, [-0.1, -0.05, -0.06], [0, 0, 1.5708 + Math.sin(t * 52) * 0.1 * brush], brush > 0.05 ? 1 : 0);
        if (G.brush) G.brush.visible = t < 0.92;
        if (t >= 0.92) {
          const k = smooth(0.92, 1.05, t);
          pose(POSES[`commercial_${ID}`] || POSES.thumbsup, k);
          setJ('head', [0.12, 0, 0.1], k);
        }
        // the duplicates drift apart striking their own poses
        if (t >= 1.2 && this._dups) {
          const k = easeOut(clamp01((t - 1.2) / 0.35));
          const poses = [DISCO, POSES.fingerguns];
          this._dups.forEach((d, i) => {
            copyPose(p.hero, d);
            const DJ = d.joints;
            for (const n in poses[i]) { const e = poses[i][n]; if (DJ[n]) DJ[n].quaternion.setFromEuler(_e.set(e[0], e[1], e[2])); }
            d.holder.position.copy(m.position).addScaledVector(S.right, (i ? 1 : -1) * 0.34 * k).addScaledVector(S.fwd, -0.05);
            d.holder.position.y += Math.sin((t - 1.2) * 9 + i * 2) * 0.02;
            d.holder.rotation.set(0, ad.faceYaw + (i ? -0.25 : 0.25) * k, 0);
            d.holder.visible = true;
          });
        }
        break;
      }
      default: break;
    }
  }

  // Places a gag prop at a hand slot (model space), oriented upright in the model frame then tilted by `tilt` (euler).
  _propAtHand(obj, p, slot, m, offset, tilt, vis = 1, roll = 0) {
    if (!obj) return;
    const root = obj.grp || obj;
    const s = p.hero?.slots?.[slot];
    if (!s) return;
    root.visible = vis > 0;
    m.updateMatrixWorld(true);
    s.getWorldPosition(_v);
    m.worldToLocal(_v);
    root.position.set(_v.x + offset[0], _v.y + offset[1], _v.z + offset[2]);
    root.rotation.set(tilt[0], tilt[1], tilt[2] + roll);
  }
}

// probability helper for per-frame emission at `rate` per second
function rdtChance(g, rate) { return Math.min(1, (g.time.realDt || 0.016) * rate); }
function hero(p) { return p.heroId || 'duke'; }
