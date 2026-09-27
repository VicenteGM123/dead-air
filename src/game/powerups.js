// DEAD AIR — power-up drops (GDD §12, §18.11, §15 cues; ARCHITECTURE §4/§10). Owned by the uplink-powerups engineer.
//
// DROP RULES (GDD §12)
//   Every zombie:kill (except cause 'cancelled') spawns a drop at the body when the points earned since the last drop
//   reached the threshold (T.drops.threshold, x T.drops.thresholdMul after each drop), else with T.drops.chance (2 %).
//   At most T.drops.perRound drops per round and T.drops.minGap s between drops (guaranteed specials ignore both and
//   do not touch the threshold). Type = a shuffled bag of the 6, no repeats until it empties; CANCELLED is held back
//   in rounds 1-2 (it waits in the bag). A body outside the playable floor (queued at a window, in a screen) drops at
//   the nearest walkable spot inside.
// ON THE GROUND: the src/props/sponsors.js 'drop_<type>' prop (screen bubble + gold floor ring), 1.0 m up, bobbing and
//   spinning (animateDrop), switched on like a CRT (line -> picture), a pooled floor light + a soft pu_idle pad. It lives
//   T.drops.life s and flickers like bad reception for the last T.drops.blink s, then collapses into static. Touch
//   pickup within T.drops.pickupR: the bubble "tunes out", a coloured ring pulses at the hero's feet.
// EFFECTS
//   cancelled        every living non-boss zombie gets a red rubber-stamp X on its face and pops, nearest first,
//                    spread over 1.5 s (zombies.kill cause 'cancelled': no per-kill points, counts for the round;
//                    Big Shots lose 50 % of max HP instead), then +T.points.cancelled.
//   full_reel        weapons.refillAll() (mags + reserves, grenades 4, Tiny Teles 3 if owned).
//   one_take         T.drops.timed s: zombies read isActive('one_take') (one-hit kills, star eyes); a warm gold
//                    vignette on the main camera; each kill gets a tiny laugh-track blip.
//   sweeps_week      T.drops.timed s: economy.multiplier reads active.sweeps_week (written directly if economy has no
//                    getter); the HUD turns the digits gold, audio.js rings every gain.
//   gaffer_tape      every boarded window refilled (level.windows[*].repairBoard, cascading nearest first) with a
//                    silver gaffer-tape X over the boards (it tears off with the next board); +T.points.gaffer.
//   please_stand_by  T.drops.freeze s: zombies.freezeAll(true) (zombies.js greys them, screens.js shows stand_by,
//                    audio.js plays the bossa bed and "...and we're back!" on powerup:end).
// API (game.powerups)
//   active                 { type: seconds left } for the timed ones (HUD icons + blinking)
//   items                  live drops [{ type, pos, group, life, state, special }]
//   isActive(type) -> bool
//   drop(type|null, pos?) -> item          spawn now (null type = next from the bag; no pos = in front of the hero)
//   dropGuaranteed(type, pos) -> item      special drops (last Sock Hopper, first Big Shot, boss phases): ignore
//                                          the per-round cap and the gap, keep the threshold
//   grab(type) / debugGrab(type)           apply an effect now (no drop)     debugDrop(type, dist = 2.2) -> item
//   threshold, earned (points since the last natural drop), dropsThisRound, bag (next types), state() -> summary
//   warmup() -> samples of every drop prop + the effect meshes (Game.precompile hook)
// EVENTS  powerup:spawn {type, pos}  powerup:grab {type}  powerup:end {type}  (+ powerup:expire {type, pos})
// SOUNDS  audio.js voices pu_spawn (powerup:spawn), each pickup cue + announcer wah-wah + pu_sad_trombone +
//   pu_bossa_bed (powerup:grab) and sting_back (powerup:end please_stand_by). This file plays pu_idle (loop per drop),
//   pu_expire, the stamp clacks and the ONE TAKE laugh blips.
// TESTS  tools/scenarios/uplink-powerups_drops.cjs (params test=1&nozombies=1&god=1&power=1&doors=1).

import * as THREE from 'three';
import { T, PAL, LAYERS } from '../core/config.js';
import { buildProp } from '../props/index.js';
import { animateDrop } from '../props/sponsors.js';
import { WALL_T } from '../world/layout.js';

export const POWERUP_TYPES = ['cancelled', 'full_reel', 'one_take', 'sweeps_week', 'gaffer_tape', 'please_stand_by'];
const D = T.drops;
const DURATION = { one_take: D.timed, sweeps_week: D.timed, please_stand_by: D.freeze };
const GLOW = { cancelled: '#E3662B', full_reel: '#FFC23A', one_take: '#FF3B30', sweeps_week: '#FF4FA0', gaffer_tape: '#DDE3EA', please_stand_by: '#EDEDED' };
const SPAWN_T = 0.55;
const GRAB_T = 0.4;
const EXPIRE_T = 0.45;
const CANCEL = { lead: 0.3, spread: 1.5, stampHold: 0.16, fade: 0.55 };
const TAPE = { cascade: 0.55, unroll: 0.13, width: 0.13 };
const TAU = Math.PI * 2;

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _cam = new THREE.Vector3();
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const easeOutBack = (x, s = 2.2) => { x = clamp01(x); return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2; };
const easeOutCubic = (x) => 1 - (1 - clamp01(x)) ** 3;
const easeIn = (x) => clamp01(x) ** 2;

// ------------------------------------------------------------------------------------------------ textures
function canvasTex(w, h, draw) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// A red rubber-stamp X with ink speckle and a double border ring (CANCELLED).
function stampTexture() {
  return canvasTex(256, 256, (x, w, h) => {
    let s = 7;
    const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
    x.translate(w / 2, h / 2);
    x.rotate(-0.12);
    x.strokeStyle = '#E8262E';
    x.lineCap = 'round';
    x.lineWidth = 46;
    x.beginPath(); x.moveTo(-78, -78); x.lineTo(78, 78); x.stroke();
    x.beginPath(); x.moveTo(78, -80); x.lineTo(-76, 80); x.stroke();
    x.lineWidth = 9;
    x.beginPath(); x.arc(0, 0, 118, 0, TAU); x.stroke();
    x.lineWidth = 4;
    x.beginPath(); x.arc(0, 0, 105, 0, TAU); x.stroke();
    x.setTransform(1, 0, 0, 1, 0, 0);
    // dry-ink speckle: knock holes out of the ink
    x.globalCompositeOperation = 'destination-out';
    for (let i = 0; i < 260; i++) {
      x.globalAlpha = 0.25 + rnd() * 0.6;
      x.beginPath(); x.arc(rnd() * w, rnd() * h, 0.6 + rnd() * 2.6, 0, TAU); x.fill();
    }
    for (let i = 0; i < 18; i++) {
      x.globalAlpha = 0.35;
      x.fillRect(rnd() * w, rnd() * h, 18 + rnd() * 40, 2 + rnd() * 3);
    }
    x.globalCompositeOperation = 'source-over';
    x.globalAlpha = 1;
  });
}

// Silver cloth tape strip with torn ends (u along the strip).
function tapeTexture() {
  return canvasTex(256, 32, (x, w, h) => {
    const g = x.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, '#C8CED8'); g.addColorStop(0.45, '#F2F5F8'); g.addColorStop(1, '#AEB6C2');
    x.fillStyle = g; x.fillRect(0, 0, w, h);
    x.strokeStyle = 'rgba(90,98,112,0.22)'; x.lineWidth = 1;
    for (let i = 0; i < w; i += 3) { x.beginPath(); x.moveTo(i, 0); x.lineTo(i + 2, h); x.stroke(); }
    for (let j = 2; j < h; j += 4) { x.beginPath(); x.moveTo(0, j); x.lineTo(w, j); x.stroke(); }
    x.fillStyle = 'rgba(255,255,255,0.35)'; x.fillRect(0, h * 0.3, w, 2);
    // torn ends
    x.globalCompositeOperation = 'destination-out';
    for (const end of [0, w]) {
      x.beginPath();
      x.moveTo(end, 0);
      for (let j = 0; j <= h; j += 4) x.lineTo(end + (end ? -1 : 1) * (2 + ((j * 37) % 9)), j);
      x.lineTo(end, h);
      x.closePath();
      x.fill();
    }
    x.globalCompositeOperation = 'source-over';
  });
}

// Soft radial disc (pickup ring pulse).
function ringTexture() {
  return canvasTex(128, 128, (x, w, h) => {
    const g = x.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
    g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.72, 'rgba(255,255,255,0)');
    g.addColorStop(0.86, 'rgba(255,255,255,1)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    x.fillStyle = g; x.fillRect(0, 0, w, h);
  });
}

// ------------------------------------------------------------------------------------------------ ONE TAKE vignette
// Full-screen clip-space quad drawn last in the main scene pass, only for the main camera (feed, sponsor and insert
// cameras see nothing: the uniform gate is set in onBeforeRender). Additive warm gold at the frame edges with a slow
// shimmer of film-strip sparkles.
const VIG_VERT = /* glsl */`
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;
const VIG_FRAG = /* glsl */`
uniform float uOn, uAmt, uTime, uAspect;
varying vec2 vUv;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void main() {
  // distance to the nearest screen edge in screen heights: a warm frame of even thickness, fuller in the corners
  float dx = min(vUv.x, 1.0 - vUv.x) * uAspect;
  float dy = min(vUv.y, 1.0 - vUv.y);
  float d = min(dx, dy);
  float corner = length(max(vec2(0.16) - vec2(dx, dy), 0.0));
  float shimmer = 0.9 + 0.1 * sin(uTime * 2.7 + vUv.x * 6.0 + vUv.y * 4.0);
  float glow = exp(-d * 11.0) * 0.36 * shimmer + smoothstep(0.0, 0.16, corner) * 0.16;
  // sparse twinkling four-point sparkles hugging the frame
  vec2 gridUv = vUv * vec2(64.0 * uAspect / 1.7778, 36.0);
  vec2 cell = floor(gridUv);
  vec2 f = fract(gridUv) - 0.5;
  float on = step(0.985, hash(cell + floor(uTime * 4.0 + hash(cell) * 3.0)));
  float star = max(0.0, 1.0 - length(f) * 5.0) + max(0.0, 1.0 - abs(f.x) * 14.0) * max(0.0, 1.0 - abs(f.y) * 3.0) * 0.6
             + max(0.0, 1.0 - abs(f.y) * 14.0) * max(0.0, 1.0 - abs(f.x) * 3.0) * 0.6;
  float tw = on * star * exp(-d * 28.0);
  vec3 gold = vec3(1.0, 0.68, 0.2);
  vec3 col = gold * glow + vec3(1.0, 0.92, 0.6) * tw * 0.9;
  gl_FragColor = vec4(col * uAmt * uOn, 1.0);
}`;

export class PowerUps {
  constructor(game) {
    this.game = game;
    this.active = {};
    this.items = [];
    this.bag = [];
    this.threshold = D.threshold;
    this.earned = 0;
    this.dropsThisRound = 0;
    this.lastDropAt = -Infinity;
    this.round = 1;
    this._n = 0;
    this._cancel = null;
    this._stamps = [];
    this._tapes = new Map();
    this._tapeQueue = [];
    this._pulses = [];
    this._laughAt = -1;
    this._frozeZombies = false;
    this._samples = null;
    this._vig = null;
    this._vigAmt = 0;
    this._mats = null;
  }

  // ------------------------------------------------------------------------------------------------ lifecycle
  init() {
    const g = this.game, ev = g.events;
    this._buildShared();
    ev.on('zombie:kill', (p) => this._onKill(p || {}));
    ev.on('points:change', (p) => { if (p && p.delta > 0) this.earned += p.delta; });
    ev.on('round:start', (p) => { this.dropsThisRound = 0; this.round = (p && p.round) || this.round; });
    ev.on('barricade:break', (p) => this._tearTape(p && p.id));
  }

  reset() {
    for (const it of this.items) this._dispose(it);
    this.items.length = 0;
    for (const type in this.active) this._end(type, true);
    this.active = {};
    this.bag = [];
    this.threshold = D.threshold;
    this.earned = 0;
    this.dropsThisRound = 0;
    this.lastDropAt = -Infinity;
    this.round = 1;
    this._cancel = null;
    for (const s of this._stamps) s.mesh.removeFromParent();
    this._stamps.length = 0;
    for (const id of [...this._tapes.keys()]) this._removeTape(id, false);
    this._tapeQueue.length = 0;
    for (const p of this._pulses) p.mesh.visible = false;
    this._vigAmt = 0;
    if (this._vig) this._vig.visible = false;
    if (this._frozeZombies) { this._frozeZombies = false; this.game.zombies?.freezeAll?.(false); }
  }

  warmup() {
    if (this._samples) return this._samples;
    const out = [];
    for (const type of POWERUP_TYPES) {
      try { out.push(buildProp(`drop_${type}`, this.game)); } catch (err) { /* prop library is someone else's */ }
    }
    const m = this._mats;
    if (m) {
      out.push(new THREE.Mesh(this._stampGeo, m.stamp));
      out.push(new THREE.Mesh(this._tapeGeo, m.tape));
      out.push(new THREE.Mesh(this._ringGeo, m.ring));
    }
    this._samples = out;
    return out;
  }

  // ------------------------------------------------------------------------------------------------ API
  isActive(type) { return this.active[type] > 0; }

  drop(type = null, pos = null, opts = {}) {
    const g = this.game;
    if (type == null) type = this._nextType();
    if (!POWERUP_TYPES.includes(type)) return null;
    if (!pos) {
      const p = g.player;
      p.forward?.(_v) || _v.set(-Math.sin(p.yaw), 0, -Math.cos(p.yaw));
      pos = _w.copy(p.pos).addScaledVector(_v.setY(0).normalize(), 2.2);
    }
    const at = this._placeFor(pos, opts.z || null);
    let group;
    try {
      group = buildProp(`drop_${type}`, g);
    } catch (err) {
      console.warn('[powerups] drop prop failed', err);
      return null;
    }
    group.position.copy(at);
    const P = group.userData.parts || {};
    g.scene.add(group);
    const id = `pu_drop_${++this._n}`;
    const item = { id, type, pos: at.clone(), group, parts: P, age: 0, life: D.life, state: 'in', t: 0, special: !!opts.special, anchor: null, idle: null, glitch: 0 };
    try {
      item.anchor = g.lights?.addAnchor?.({ pos: [at.x, at.y + 0.2, at.z], color: GLOW[type], intensity: 1.0, distance: 2.4, area: g.level?.areaAt?.(at.x, at.z) ?? null, id }) ? id : null;
    } catch (err) { item.anchor = null; }
    try { item.idle = g.audio?.loop?.('pu_idle', { pos: _v.copy(at).setY(at.y + 1), vol: 0.7 }) || null; } catch (err) { item.idle = null; }
    this.items.push(item);
    this._setScale(item, 0.05, 0.02, 0);
    _v.copy(at).setY(at.y + 1);
    g.fx?.burst?.(_v, { shape: 'star', count: 7, colors: [GLOW[type], PAL.marqueeGold || '#FFD23A', '#FFFFFF'], speed: 2.6, life: 0.7, size: 0.1 });
    g.fx?.burst?.(_v, { shape: 'static', count: 10, speed: 1.6, size: 0.07, life: 0.5 });
    g.events.emit('powerup:spawn', { type, pos: item.pos.clone() });
    return item;
  }

  dropGuaranteed(type, pos) {
    return this.drop(type || null, pos, { special: true });
  }

  grab(type) {
    if (!POWERUP_TYPES.includes(type)) return false;
    this._apply(type, null);
    return true;
  }

  debugGrab(type) { return this.grab(type); }

  debugDrop(type = null, dist = 2.2) {
    const p = this.game.player;
    _v.set(-Math.sin(p.yaw), 0, -Math.cos(p.yaw));
    return this.drop(type, _w.copy(p.pos).addScaledVector(_v, dist));
  }

  state() {
    return {
      active: { ...this.active }, items: this.items.map((i) => ({ type: i.type, life: +i.life.toFixed(2), state: i.state, pos: i.pos.toArray().map((v) => +v.toFixed(2)) })),
      threshold: Math.round(this.threshold), earned: this.earned, dropsThisRound: this.dropsThisRound, bag: [...this.bag],
      cancelling: !!this._cancel, tapes: this._tapes.size, vignette: +this._vigAmt.toFixed(2),
    };
  }

  // ------------------------------------------------------------------------------------------------ drop rules
  _onKill(p) {
    if (p.cause === 'cancelled') return;
    const g = this.game;
    if (this.active.one_take > 0 && g.time.realNow - this._laughAt > 0.18) {
      this._laughAt = g.time.realNow;
      g.audio?.play?.('crowd_laugh', { pos: p.pos, dur: 0.45, vol: 0.32, rate: 1.15 + Math.random() * 0.25 });
    }
    const due = this.earned >= this.threshold;
    if (!due && !(g.rand() < D.chance)) return;
    const now = g.time.now;
    if (this.dropsThisRound >= D.perRound || now - this.lastDropAt < D.minGap) return;
    const pos = p.pos || (p.z && p.z.pos);
    if (!pos) return;
    const item = this.drop(null, pos, { z: p.z || null });
    if (!item) return;
    this.earned = 0;
    this.threshold *= D.thresholdMul;
    this.dropsThisRound++;
    this.lastDropAt = now;
  }

  _nextType() {
    const g = this.game;
    const round = g.rounds?.round ?? this.round;
    const allowed = (t) => !(t === 'cancelled' && round <= 2);
    let i = this.bag.findIndex(allowed);
    if (i < 0) {
      const add = POWERUP_TYPES.filter((t) => !this.bag.includes(t));
      for (let k = add.length - 1; k > 0; k--) { const j = Math.floor(g.rand() * (k + 1)); [add[k], add[j]] = [add[j], add[k]]; }
      this.bag.push(...add);
      i = this.bag.findIndex(allowed);
    }
    return i < 0 ? 'full_reel' : this.bag.splice(i, 1)[0];
  }

  // A reachable floor spot for a drop: the body if it lies on the walkable floor, else its window's inside point,
  // else the nearest walkable cell within 4 m. Also keeps 0.9 m from other drops.
  _placeFor(pos, z) {
    const g = this.game, nav = g.nav, col = g.level?.col;
    const out = new THREE.Vector3(pos.x, pos.y ?? 0, pos.z);
    const ok = (x, zz) => { try { return nav ? nav.walkable(x, zz) : true; } catch (err) { return true; } };
    if (!ok(out.x, out.z)) {
      const win = z && z.entry && z.entry.id && g.level?.windows?.[z.entry.id];
      if (win && win.inside) out.set(win.inside[0], win.inside[1], win.inside[2]);
      if (!ok(out.x, out.z)) {
        let best = null, bd = Infinity;
        for (let r = 0.5; r <= 4 && !best; r += 0.5) {
          for (let k = 0; k < 16; k++) {
            const a = (k / 16) * TAU, x = out.x + Math.cos(a) * r, zz = out.z + Math.sin(a) * r;
            if (!ok(x, zz)) continue;
            const d = g.player ? Math.hypot(x - g.player.pos.x, zz - g.player.pos.z) : r;
            if (d < bd) { bd = d; best = [x, zz]; }
          }
        }
        if (best) out.set(best[0], out.y, best[1]);
      }
    }
    for (const it of this.items) {
      const dx = out.x - it.pos.x, dz = out.z - it.pos.z, d = Math.hypot(dx, dz);
      if (d < 0.9) {
        const a = d > 1e-3 ? Math.atan2(dz, dx) : g.rand() * TAU;
        const nx = it.pos.x + Math.cos(a) * 0.95, nz = it.pos.z + Math.sin(a) * 0.95;
        if (ok(nx, nz)) out.set(nx, out.y, nz);
      }
    }
    let y = -Infinity;
    try { y = nav ? nav.heightAt(out.x, out.z) : -Infinity; } catch (err) { y = -Infinity; }
    if (!(y > -Infinity) && col) y = col.floorAt(out.x, out.z, (pos.y ?? 0) + 1);
    out.y = y > -Infinity ? y : (pos.y ?? 0);
    return out;
  }

  // ------------------------------------------------------------------------------------------------ per frame
  update(dt) {
    const g = this.game;
    const p = g.player;
    const canGrab = p && p.alive !== false && !p.downed;
    for (let i = this.items.length - 1; i >= 0; i--) {
      const it = this.items[i];
      it.age += dt;
      it.t += dt;
      if (it.state === 'in') {
        this._animIdle(it);
        const k = it.t / SPAWN_T;
        const sx = 0.08 + 0.92 * easeOutBack(clamp01(k / 0.45), 1.4);
        const sy = k < 0.3 ? 0.03 : 0.03 + 0.97 * easeOutBack((k - 0.3) / 0.7, 2.6);
        this._setScale(it, sx, sy, easeOutBack(k, 1.8));
        if (it.t >= SPAWN_T) { it.state = 'idle'; it.t = 0; this._setScale(it, 1, 1, 1); }
      } else if (it.state === 'idle') {
        it.life -= dt;
        this._animIdle(it);
        this._reception(it, dt);
        if (it.life <= 0) this._expire(it);
      } else if (it.state === 'grab') {
        const k = it.t / GRAB_T;
        this._animIdle(it);
        const sy = k < 0.3 ? 1 + 0.3 * Math.sin((k / 0.3) * Math.PI) : Math.max(0.02, 1 - easeIn((k - 0.3) / 0.25));
        const sx = k < 0.5 ? 1 + 0.25 * easeOutCubic(k / 0.5) : Math.max(0, 1.25 * (1 - easeIn((k - 0.5) / 0.5)));
        this._setScale(it, sx, sy, Math.max(0, 1 - easeIn(k)));
        if (it.t >= GRAB_T) { this._dispose(it); this.items.splice(i, 1); }
        continue;
      } else if (it.state === 'expire') {
        const k = it.t / EXPIRE_T;
        this._animIdle(it);
        const sy = Math.max(0.02, 1 - easeIn(k / 0.45));
        const sx = k < 0.45 ? 1 : Math.max(0, 1 - easeIn((k - 0.45) / 0.55));
        this._setScale(it, sx, sy, Math.max(0, 1 - k));
        if (it.t >= EXPIRE_T) { this._dispose(it); this.items.splice(i, 1); }
        continue;
      }
      if (canGrab && (it.state === 'idle' || (it.state === 'in' && it.t > 0.15))) {
        const dx = p.pos.x - it.pos.x, dz = p.pos.z - it.pos.z, dy = p.pos.y - it.pos.y;
        if (dx * dx + dz * dz <= D.pickupR * D.pickupR && dy > -1.2 && dy < 2.2) this._pickup(it);
      }
    }
    for (const type in this.active) {
      if (!(dt > 0)) break;
      this.active[type] -= dt;
      if (this.active[type] <= 0) this._end(type);
    }
    if (this._cancel) this._updateCancel(dt);
    this._updateStamps(dt);
    this._updateTapes(dt);
    this._updatePulses(dt);
    this._updateVignette(g.time.realDt || dt);
    if (this.active.please_stand_by > 0 && g.zombies && !g.zombies.frozen) { g.zombies.freezeAll?.(true); this._frozeZombies = true; }
  }

  _animIdle(it) {
    try { animateDrop(it.group, it.age); } catch (err) {
      const P = it.parts;
      if (P.float) { P.float.position.y = 1.0 + Math.sin(it.age * TAU) * 0.05; P.float.rotation.y = it.age * Math.PI / 2; }
    }
  }

  _setScale(it, sx, sy, ring) {
    const P = it.parts;
    if (P.float) P.float.scale.set(sx, sy, sx);
    if (P.ring) P.ring.scale.setScalar(Math.max(0.001, ring));
  }

  // Bad reception during the last T.drops.blink seconds: drop-outs that get longer, sideways tearing, squashes.
  _reception(it, dt) {
    const P = it.parts;
    if (!P.float) return;
    if (it.life > D.blink) {
      P.float.visible = true;
      P.float.position.x = 0;
      return;
    }
    const f = 1 - it.life / D.blink;
    it.glitch -= dt;
    if (it.glitch <= 0) {
      const off = Math.random() < 0.28 + 0.45 * f;
      it.glitchOff = off;
      it.glitch = off ? 0.04 + Math.random() * (0.05 + 0.12 * f) : 0.06 + Math.random() * (0.35 - 0.25 * f);
      it.jx = (Math.random() - 0.5) * 0.14 * (0.4 + f);
      it.sq = 1 - Math.random() * 0.35 * f;
      if (off && Math.random() < 0.3) {
        _v.copy(it.pos).setY(it.pos.y + 1);
        this.game.fx?.burst?.(_v, { shape: 'static', count: 3, speed: 1.2, size: 0.05, life: 0.3 });
      }
    }
    P.float.visible = !it.glitchOff;
    P.float.position.x = it.glitchOff ? 0 : it.jx;
    P.float.scale.y = it.sq;
  }

  _pickup(it) {
    const g = this.game;
    it.state = 'grab';
    it.t = 0;
    if (it.parts.float) { it.parts.float.visible = true; it.parts.float.position.x = 0; }
    this._stopIdle(it);
    _v.copy(it.pos).setY(it.pos.y + 1);
    const c = GLOW[it.type];
    g.fx?.burst?.(_v, { shape: 'confetti', count: 18, colors: [c, '#FFFFFF', PAL.marqueeGold || '#FFD23A'], speed: 4, life: 1.1 });
    g.fx?.burst?.(_v, { shape: 'star', count: 8, colors: [c, '#FFFFFF'], speed: 3.2, life: 0.6, size: 0.12 });
    g.fx?.flashLight?.(_v, c, 6, 0.2);
    this._pulse(g.player.pos, c);
    this._apply(it.type, it);
  }

  _expire(it) {
    const g = this.game;
    it.state = 'expire';
    it.t = 0;
    if (it.parts.float) { it.parts.float.visible = true; it.parts.float.position.x = 0; }
    this._stopIdle(it);
    _v.copy(it.pos).setY(it.pos.y + 1);
    g.fx?.burst?.(_v, { shape: 'static', count: 18, speed: 2, size: 0.08, life: 0.6 });
    g.audio?.play?.('pu_expire', { pos: _v });
    g.events.emit('powerup:expire', { type: it.type, pos: it.pos.clone() });
  }

  _stopIdle(it) {
    try { it.idle?.stop?.(0.25); } catch (err) { /* audio is someone else's */ }
    it.idle = null;
    if (it.anchor) { try { this.game.lights?.removeAnchor?.(it.anchor); } catch (err) { /* ignore */ } it.anchor = null; }
  }

  _dispose(it) {
    this._stopIdle(it);
    it.group.removeFromParent();
  }

  // ------------------------------------------------------------------------------------------------ effects
  _apply(type, item) {
    const g = this.game;
    g.events.emit('powerup:grab', { type });
    if (type === 'cancelled') this._startCancel();
    else if (type === 'full_reel') {
      try { g.weapons?.refillAll?.(); } catch (err) { console.warn('[powerups] refillAll failed', err); }
      _v.copy(g.player.pos).setY(g.player.pos.y + 1.1);
      g.fx?.burst?.(_v, { shape: 'star', count: 10, colors: ['#FFC23A', '#FFF3B0', '#FFFFFF'], speed: 3, life: 0.8, size: 0.12 });
    } else if (type === 'gaffer_tape') this._gaffer();
    if (!DURATION[type]) return;
    this.active[type] = DURATION[type];
    if (type === 'sweeps_week') this._setMultiplier(2);
    else if (type === 'please_stand_by') { g.zombies?.freezeAll?.(true); this._frozeZombies = true; }
  }

  _end(type, silent = false) {
    const g = this.game;
    delete this.active[type];
    if (type === 'sweeps_week') this._setMultiplier(1);
    else if (type === 'please_stand_by' && this._frozeZombies) { this._frozeZombies = false; g.zombies?.freezeAll?.(false); }
    if (!silent) g.events.emit('powerup:end', { type });
  }

  // economy.js reads active.sweeps_week through its multiplier getter; a plain-field economy gets it written.
  _setMultiplier(v) {
    const e = this.game.economy;
    if (!e) return;
    let o = e, desc = null;
    while (o && !desc) { desc = Object.getOwnPropertyDescriptor(o, 'multiplier'); o = Object.getPrototypeOf(o); }
    if (!desc || !desc.get) e.multiplier = v;
  }

  // Coloured ring expanding at the hero's feet (pickup feedback).
  _pulse(pos, color) {
    let p = this._pulses.find((q) => !q.mesh.visible);
    if (!p) {
      if (this._pulses.length >= 3) p = this._pulses[0];
      else {
        const mesh = new THREE.Mesh(this._ringGeo, this._mats.ring.clone());
        mesh.frustumCulled = false;
        mesh.renderOrder = 3;
        this.game.scene.add(mesh);
        p = { mesh, t: 0 };
        this._pulses.push(p);
      }
    }
    p.t = 0;
    p.mesh.material.color.set(color).multiplyScalar(1.6);
    p.mesh.position.set(pos.x, (pos.y ?? 0) + 0.06, pos.z);
    p.mesh.visible = true;
  }

  _updatePulses(dt) {
    const rdt = this.game.time.realDt || dt;
    for (const p of this._pulses) {
      if (!p.mesh.visible) continue;
      p.t += rdt;
      const k = p.t / 0.55;
      const s = 0.4 + 2.6 * easeOutCubic(k);
      p.mesh.scale.set(s, s, s);
      p.mesh.material.opacity = Math.max(0, 1 - k);
      if (k >= 1) p.mesh.visible = false;
    }
  }

  // --- CANCELLED
  _startCancel() {
    const g = this.game, Z = g.zombies;
    const list = (Z?.alive || []).filter((z) => z && !z.dead && !z.removed && z.type !== 'boss_baron');
    const pp = g.player.pos;
    list.sort((a, b) => a.pos.distanceToSquared(pp) - b.pos.distanceToSquared(pp));
    const n = list.length;
    this._cancel = {
      t: 0, bonus: false,
      list: list.map((z, i) => ({ z, at: CANCEL.lead + (n > 1 ? CANCEL.spread * (i / (n - 1)) ** 0.85 : 0.2), stamped: false, done: false })),
    };
  }

  _updateCancel(dt) {
    const c = this._cancel, g = this.game, Z = g.zombies;
    c.t += dt;
    let pending = false;
    for (const e of c.list) {
      if (e.done) continue;
      pending = true;
      const z = e.z;
      if (!z || z.dead || z.removed) { e.done = true; continue; }
      if (!e.stamped && c.t >= e.at) {
        e.stamped = true;
        this._stamp(z);
        g.audio?.play?.('telly_clack', { pos: z.pos, rate: 0.7 + Math.random() * 0.2, vol: 0.9 });
      }
      if (e.stamped && c.t >= e.at + CANCEL.stampHold) {
        e.done = true;
        _v.copy(z.pos).setY(z.pos.y + (z.height || 1.7) * 0.8);
        g.fx?.burst?.(_v, { shape: 'confetti', count: 12, colors: ['#E8262E', '#FFFFFF', '#FFD23A'], speed: 4, life: 1 });
        g.fx?.burst?.(_v, { shape: 'static', count: 8, speed: 2.2, size: 0.08, life: 0.5 });
        try {
          if (z.type === 'big_shot') {
            // exactly half his max HP (no front armour, no ONE TAKE): straight off the health, or the pop if that kills
            const half = (z.maxHp || z.hp) * 0.5;
            if (z.hp - half > 0) {
              z.hp -= half;
              if (z.anim) z.anim.hurt = 1;
              if (z.animator && z.animator.kick) z.animator.kick(1);
            } else Z?.kill?.(z, { cause: 'cancelled' });
          }
          else if (Z?.kill) Z.kill(z, { cause: 'cancelled' });
          else Z?.damage?.(z, z.hp + 1, { cause: 'cancelled', points: false, hitmarker: false });
        } catch (err) { console.warn('[powerups] cancel pop failed', err); }
      }
    }
    if (!c.bonus && c.t >= CANCEL.lead + CANCEL.spread + 0.2) {
      c.bonus = true;
      g.economy?.add?.(T.points.cancelled, 'cancelled');
    }
    if (!pending && c.bonus) this._cancel = null;
  }

  _stamp(z) {
    const mesh = new THREE.Mesh(this._stampGeo, this._mats.stamp.clone());
    mesh.renderOrder = 5;
    mesh.layers.set(LAYERS.ZOMBIES);
    this.game.scene.add(mesh);
    const s = { mesh, z, t: 0, popped: false, rot: (Math.random() - 0.5) * 0.5, pos: new THREE.Vector3(), size: Math.max(0.42, (z.headR || 0.22) * 2.6) };
    this._headPos(z, s.pos);
    this._stamps.push(s);
  }

  _headPos(z, out) {
    if (z.head && z.head.getWorldPosition && !z.removed) {
      z.head.getWorldPosition(out);
      if (!Number.isFinite(out.y) || out.distanceToSquared(z.pos) > 16) out.copy(z.pos).setY(z.pos.y + (z.height || 1.7) * 0.85);
    } else out.copy(z.pos).setY(z.pos.y + (z.height || 1.7) * 0.85);
    return out;
  }

  _updateStamps(dt) {
    if (!this._stamps.length) return;
    const cam = this.game.camera;
    cam.getWorldPosition(_cam);
    const rdt = dt > 0 ? dt : 0;
    for (let i = this._stamps.length - 1; i >= 0; i--) {
      const s = this._stamps[i], z = s.z;
      s.t += rdt;
      if (!z.removed && !(z.dead && s.t > CANCEL.stampHold + 0.25)) this._headPos(z, s.pos);
      _v.subVectors(_cam, s.pos).normalize();
      s.mesh.position.copy(s.pos).addScaledVector(_v, (z.headR || 0.22) + 0.06);
      s.mesh.quaternion.copy(cam.quaternion);
      s.mesh.rotateZ(s.rot);
      const slam = s.t < 0.09 ? 2.4 - 1.5 * (s.t / 0.09) : 0.9 + 0.1 * easeOutBack((s.t - 0.09) / 0.12, 3);
      s.mesh.scale.setScalar(s.size * slam);
      const fadeT = s.t - CANCEL.stampHold - 0.2;
      s.mesh.material.opacity = fadeT > 0 ? Math.max(0, 1 - fadeT / CANCEL.fade) : 1;
      s.mesh.material.color.setScalar(s.t < 0.12 ? 1.6 : 1.0);
      if (fadeT >= CANCEL.fade) { s.mesh.removeFromParent(); s.mesh.material.dispose(); this._stamps.splice(i, 1); }
    }
  }

  // --- GAFFER TAPE
  _gaffer() {
    const g = this.game, L = g.level;
    const wins = Object.values(L?.windows || {}).filter((w) => w && w.type === 'boarded');
    const pp = g.player.pos;
    wins.sort((a, b) => Math.hypot(a.pos.x - pp.x, a.pos.z - pp.z) - Math.hypot(b.pos.x - pp.x, b.pos.z - pp.z));
    const n = wins.length;
    wins.forEach((w, i) => this._tapeQueue.push({ w, at: n > 1 ? TAPE.cascade * (i / (n - 1)) : 0, t: 0 }));
    g.economy?.add?.(T.points.gaffer, 'gaffer');
  }

  _updateTapes(dt) {
    const rdt = this.game.time.realDt || dt;
    for (let i = this._tapeQueue.length - 1; i >= 0; i--) {
      const q = this._tapeQueue[i];
      q.t += rdt;
      if (q.t < q.at) continue;
      this._tapeQueue.splice(i, 1);
      const w = q.w;
      try {
        let guard = 8;
        while (w.boards < 6 && guard-- > 0 && w.repairBoard()) { /* refill */ }
      } catch (err) { console.warn('[powerups] repairBoard failed', err); }
      this._addTape(w);
    }
    for (const tp of this._tapes.values()) {
      if (tp.t >= 1) continue;
      tp.t = Math.min(1, tp.t + rdt / (TAPE.unroll * 2 + 0.25));
      const k = tp.t * (TAPE.unroll * 2 + 0.25);
      tp.a.scale.x = Math.max(0.001, easeOutCubic((k - 0.25) / TAPE.unroll));
      tp.b.scale.x = Math.max(0.001, easeOutCubic((k - 0.25 - TAPE.unroll) / TAPE.unroll));
    }
  }

  _addTape(w) {
    const g = this.game;
    if (!w.pivot || !Number.isFinite(w.top) || !Number.isFinite(w.sill)) return;
    this._removeTape(w.id, false);
    const parent = g.level?.areaRoots?.[w.area] || g.scene;
    const grp = new THREE.Group();
    grp.name = `gaffer_x:${w.id}`;
    w.pivot.updateMatrixWorld(true);
    grp.position.copy(w.pivot.position);
    grp.quaternion.copy(w.pivot.quaternion);
    const W = (w.width || 1.6) * 0.96, H = (w.top - w.sill) * 0.92;
    const yc = w.sill + (w.top - w.sill) / 2, zc = WALL_T / 2 + 0.06 + 6 * 0.012 + 0.035;
    const len = Math.hypot(W, H), ang = Math.atan2(H, W);
    const mk = (a, zOff) => {
      const pivot = new THREE.Group();
      pivot.position.set(-Math.cos(a) * len / 2, yc - Math.sin(a) * len / 2, zc + zOff);
      pivot.rotation.z = a;
      const m = new THREE.Mesh(this._tapeGeo, this._mats.tape);
      m.scale.set(len, 1, 1);
      m.castShadow = false;
      m.receiveShadow = true;
      pivot.add(m);
      pivot.scale.x = 0.001;
      grp.add(pivot);
      return pivot;
    };
    const a = mk(ang, 0);
    const b = mk(Math.PI - ang, 0.006);
    b.position.set(Math.cos(ang) * len / 2, yc - Math.sin(ang) * len / 2, zc + 0.006);
    parent.add(grp);
    this._tapes.set(w.id, { group: grp, a, b, t: 0 });
    _v.set(0, yc, zc).applyMatrix4(w.pivot.matrixWorld);
    g.fx?.burst?.(_v, { shape: 'confetti', count: 6, colors: ['#DDE3EA', '#FFFFFF', '#AEB6C2'], speed: 2, life: 0.7, size: 0.05 });
  }

  _tearTape(id) {
    if (!id || !this._tapes.has(id)) return;
    this._removeTape(id, true);
  }

  _removeTape(id, fx) {
    const tp = this._tapes.get(id);
    if (!tp) return;
    if (fx) {
      tp.group.getWorldPosition(_v);
      _v.y += 1.2;
      this.game.fx?.burst?.(_v, { shape: 'confetti', count: 8, colors: ['#DDE3EA', '#AEB6C2'], speed: 3, life: 0.9, size: 0.06 });
    }
    tp.group.removeFromParent();
    this._tapes.delete(id);
  }

  // --- ONE TAKE
  _updateVignette(rdt) {
    const g = this.game;
    const left = this.active.one_take || 0;
    const want = left > 0 ? Math.min(1, left / 1.2) : 0;
    this._vigAmt += (want - this._vigAmt) * Math.min(1, rdt * (want > this._vigAmt ? 5 : 4));
    if (this._vigAmt < 0.003) this._vigAmt = 0;
    if (!this._vig) return;
    this._vig.visible = this._vigAmt > 0;
    const u = this._vig.material.uniforms;
    u.uAmt.value = this._vigAmt;
    u.uTime.value = g.time.realNow || 0;
  }

  // ------------------------------------------------------------------------------------------------ shared
  _buildShared() {
    const g = this.game;
    this._stampGeo = new THREE.PlaneGeometry(1, 1);
    this._tapeGeo = new THREE.PlaneGeometry(1, TAPE.width).translate(0.5, 0, 0);
    this._ringGeo = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
    const stampTex = stampTexture(), tapeTex = tapeTexture(), ringTex = ringTexture();
    this._mats = {
      stamp: new THREE.MeshBasicMaterial({ map: stampTex, transparent: true, depthWrite: false, fog: false, side: THREE.DoubleSide }),
      tape: g.mats.toon('#FFFFFF', { map: tapeTex, rough: 0.5, metal: 0.25, transparent: true, alphaTest: 0.35, keepColor: true, side: THREE.DoubleSide }),
      ring: new THREE.MeshBasicMaterial({ map: ringTex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }),
    };
    this._mats.stamp.name = 'powerups:stamp';
    this._mats.ring.name = 'powerups:ring';
    // ONE TAKE gold vignette (main camera only)
    const mat = new THREE.ShaderMaterial({
      uniforms: { uOn: { value: 0 }, uAmt: { value: 0 }, uTime: { value: 0 }, uAspect: { value: 16 / 9 } },
      vertexShader: VIG_VERT, fragmentShader: VIG_FRAG,
      transparent: true, depthTest: false, depthWrite: false, blending: THREE.AdditiveBlending, fog: false,
    });
    mat.name = 'powerups:one_take_vignette';
    const vig = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat);
    vig.name = 'one_take_vignette';
    vig.frustumCulled = false;
    vig.renderOrder = 10000;
    vig.visible = false;
    vig.onBeforeRender = (renderer, scene, camera) => {
      const main = camera === g.camera;
      mat.uniforms.uOn.value = main ? 1 : 0;
      if (main) mat.uniforms.uAspect.value = camera.aspect || 16 / 9;
    };
    g.scene.add(vig);
    this._vig = vig;
  }
}
