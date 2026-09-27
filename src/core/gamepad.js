// Xbox controller device layer (Gamepad API, "standard" mapping) + gamepad-only aim assist. Input (src/core/input.js)
// owns the action mapping; this file only reads the hardware, shapes the sticks and drives the rumble motors.
//
// Gamepad (input.pad)
//   poll(dt)      every frame: navigator.getGamepads() is read fresh each call (never cached: the headless test
//                 overrides it), the first connected 'standard' pad is used (the one in use is kept while it stays
//                 connected). gamepadconnected / gamepaddisconnected only flag a rescan.
//   connected, id, index, justConnected, justDisconnected (this frame)
//   ls = { x, y, m }   left stick after a RADIAL deadzone (0.15) rescaled to 0..1 (x right, y forward/up, m magnitude)
//   rs = { x, y, m }   right stick, radial deadzone 0.12 (same shaping; the look curve lives in Input)
//   btn[i] = { down, pressed, released, value }   i = BTN.*; triggers use value hysteresis (0.30 on / 0.18 off)
//   active        true when this frame had deliberate pad input (a press, a stick past 0.35, a trigger past 0.3)
//   rumble(weak, strong, ms)   queues a dual-rumble effect. The mixer plays the max of the active effects in short
//                 chunks (<= 90 ms, re-issued while anything is active), so overlapping cues never cancel each other.
//                 Every actuator call is guarded: no vibrationActuator / playEffect / a rejected promise = silence.
//   stopRumble()  drops every queued effect (pause, game over).
// AimAssist (input.assist) — used only while the pad drives the look:
//   friction()    look-rate multiplier: 0.58 (0.5 in ADS) while the crosshair is on a zombie's hitbox (weapons.aimHit,
//                 the boss screen counts), easing from 0.8 to 1 in a small bubble around a zombie, else 1.
//   snap()        on the LT press: the living zombie whose chest is nearest the crosshair inside an 8 degree cone
//                 (<= 28 m, in line of sight) -> { yaw, pitch } = 55 % of the way there (Input spreads it over
//                 0.12 s), else null. Subtle on purpose.

import * as THREE from 'three';

export const BTN = { A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, LT: 6, RT: 7, VIEW: 8, MENU: 9, L3: 10, R3: 11, UP: 12, DOWN: 13, LEFT: 14, RIGHT: 15, HOME: 16 };
export const BTN_NAME = ['a', 'b', 'x', 'y', 'lb', 'rb', 'lt', 'rt', 'back', 'start', 'l3', 'r3', 'up', 'down', 'left', 'right', 'home'];
const NBTN = 17;
const DZ_MOVE = 0.15;
const DZ_LOOK = 0.12;
const DZ_OUTER = 0.05;      // full deflection reads 1 even on worn sticks / diagonals
const TRIG_ON = 0.3;
const TRIG_OFF = 0.18;
const ACTIVE_STICK = 0.35;
const CHUNK = 0.09;         // s per rumble chunk

// Radial deadzone with rescaling: direction kept, magnitude remapped from [dz, 1 - outer] to [0, 1].
function radial(x, y, dz, out) {
  const m = Math.hypot(x, y);
  if (!(m > dz)) { out.x = 0; out.y = 0; out.m = 0; return out; }
  const r = Math.min(1, (m - dz) / (1 - dz - DZ_OUTER));
  out.x = (x / m) * r;
  out.y = (y / m) * r;
  out.m = r;
  return out;
}

const num = (v) => (Number.isFinite(v) ? v : 0);

export class Gamepad {
  constructor() {
    this.connected = false;
    this.id = '';
    this.index = -1;
    this.justConnected = false;
    this.justDisconnected = false;
    this.active = false;
    this.ls = { x: 0, y: 0, m: 0 };
    this.rs = { x: 0, y: 0, m: 0 };
    this.btn = Array.from({ length: NBTN }, () => ({ down: false, pressed: false, released: false, value: 0 }));
    this._gp = null;
    this._rescan = true;
    this._fx = [];          // queued rumble effects { w, s, end } (seconds, performance clock)
    this._rum = { w: 0, s: 0, end: 0 };
    this.rumbleCount = 0;   // effects actually sent to the actuator (tests)
  }

  init() {
    const flag = () => { this._rescan = true; };
    addEventListener('gamepadconnected', flag);
    addEventListener('gamepaddisconnected', flag);
  }

  _list() {
    try {
      const nav = typeof navigator !== 'undefined' ? navigator : null;
      return nav && typeof nav.getGamepads === 'function' ? nav.getGamepads() || [] : [];
    } catch { return []; } // blocked by a permissions policy
  }

  // The pad in use while it stays connected, else the first connected 'standard' pad.
  _pick(list) {
    const cur = this.index >= 0 ? list[this.index] : null;
    if (cur && cur.connected && cur.mapping === 'standard') return cur;
    for (let i = 0; i < list.length; i++) {
      const p = list[i];
      if (p && p.connected && p.mapping === 'standard') return p;
    }
    return null;
  }

  poll() {
    const gp = this._pick(this._list());
    const was = this.connected;
    this.connected = !!gp;
    this.justConnected = !was && this.connected;
    this.justDisconnected = was && !this.connected;
    this._rescan = false;
    this._gp = gp;
    this.active = false;
    if (!gp) {
      this.index = -1;
      this.ls.x = this.ls.y = this.ls.m = 0;
      this.rs.x = this.rs.y = this.rs.m = 0;
      for (const b of this.btn) { b.released = b.down; b.down = b.pressed = false; b.value = 0; }
      return;
    }
    this.index = gp.index;
    this.id = gp.id || 'gamepad';
    const ax = gp.axes || [];
    // standard mapping: axes 0/1 left stick, 2/3 right stick, +y = down -> flip to up-positive
    radial(num(ax[0]), -num(ax[1]), DZ_MOVE, this.ls);
    radial(num(ax[2]), -num(ax[3]), DZ_LOOK, this.rs);
    const bs = gp.buttons || [];
    let active = this.ls.m > ACTIVE_STICK || this.rs.m > ACTIVE_STICK;
    for (let i = 0; i < NBTN; i++) {
      const b = this.btn[i];
      const raw = bs[i];
      let value = 0, down = false;
      if (raw !== undefined && raw !== null) {
        if (typeof raw === 'object') { value = num(raw.value); down = !!raw.pressed; } else { value = num(raw); down = value > 0.5; }
      }
      if (i === BTN.LT || i === BTN.RT) down = value > TRIG_ON || (b.down && value > TRIG_OFF) || (down && value === 0);
      b.pressed = down && !b.down;
      b.released = !down && b.down;
      b.down = down;
      b.value = value;
      if (b.pressed && i !== BTN.HOME) active = true;
    }
    this.active = active;
  }

  down(i) { return this.btn[i].down; }
  pressed(i) { return this.btn[i].pressed; }
  released(i) { return this.btn[i].released; }

  // ------------------------------------------------------------------------------------------------ rumble
  rumble(weak, strong, ms) {
    if (!(ms > 0)) return;
    const now = performance.now() / 1000;
    const fx = this._fx;
    for (let i = fx.length - 1; i >= 0; i--) if (fx[i].end <= now) fx.splice(i, 1);
    if (fx.length >= 12) fx.shift();
    fx.push({ w: Math.min(1, Math.max(0, weak)), s: Math.min(1, Math.max(0, strong)), end: now + Math.min(5, ms / 1000) });
  }

  stopRumble() {
    this._fx.length = 0;
    this._rum.end = 0;
    this._rum.w = this._rum.s = 0;
    const act = this._actuator();
    if (act && typeof act.reset === 'function') {
      try { const p = act.reset(); if (p && typeof p.catch === 'function') p.catch(() => {}); } catch { /* unsupported */ }
    }
  }

  _actuator() {
    const gp = this._gp;
    const act = gp && gp.vibrationActuator;
    return act && typeof act.playEffect === 'function' ? act : null;
  }

  // Mixer: called once per frame by Input (after poll).
  updateRumble() {
    const fx = this._fx;
    if (!fx.length) return;
    const now = performance.now() / 1000;
    let w = 0, s = 0, end = 0;
    for (let i = fx.length - 1; i >= 0; i--) {
      const e = fx[i];
      if (e.end <= now) { fx.splice(i, 1); continue; }
      if (e.w > w) w = e.w;
      if (e.s > s) s = e.s;
      if (e.end > end) end = e.end;
    }
    if (!fx.length) return;
    const R = this._rum;
    const due = now >= R.end - 0.015 || Math.abs(w - R.w) > 0.04 || Math.abs(s - R.s) > 0.04;
    if (!due) return;
    const act = this._actuator();
    const dur = Math.min(CHUNK, end - now);
    R.w = w; R.s = s; R.end = now + dur;
    if (!act || dur <= 0.005) return;
    try {
      const p = act.playEffect('dual-rumble', { startDelay: 0, duration: Math.round(dur * 1000), weakMagnitude: w, strongMagnitude: s });
      if (p && typeof p.catch === 'function') p.catch(() => {});
      this.rumbleCount++;
    } catch { /* 'dual-rumble' unsupported on this pad */ }
  }
}

// ------------------------------------------------------------------------------------------------ aim assist
const SNAP_CONE = THREE.MathUtils.degToRad(8);
const SNAP_RANGE = 28;
const SNAP_AMOUNT = 0.55;
const FRICTION_ON = 0.58;
const FRICTION_ON_ADS = 0.5;
const FRICTION_NEAR = 0.8;
const BUBBLE_RANGE = 32;
const _o = new THREE.Vector3();
const _v = new THREE.Vector3();
const _d = new THREE.Vector3();
const _t = new THREE.Vector3();
const SNAP_HEIGHTS = [0.66, 0.8]; // fractions of the zombie's height tried for line of sight (chest, upper chest)

export class AimAssist {
  constructor(game) {
    this.game = game;
  }

  _onTarget(hit) {
    if (!hit) return false;
    if (hit.kind === 'zombie') return !!hit.z && !hit.z.dead;
    return hit.kind === 'shootable' && !!hit.entry && hit.entry.id === 'boss_baron';
  }

  friction() {
    const g = this.game, W = g.weapons, p = g.player, Z = g.zombies;
    if (!W || !p || !W.aimDir) return 1;
    if (this._onTarget(W.aimHit) && W.aimDist < BUBBLE_RANGE + 8) return p.ads ? FRICTION_ON_ADS : FRICTION_ON;
    const list = Z && Z.alive;
    if (!list || !list.length || !W.aimOrigin) return 1;
    const o = W.aimOrigin, d = W.aimDir;
    let best = 1;
    for (let i = 0; i < list.length; i++) {
      const z = list[i];
      if (!z || z.dead || !z.pos) continue;
      const sc = z.scale || 1;
      const lo = z.pos.y + 0.2, hi = z.pos.y + (z.height || 1.6) * sc;
      const cy = (lo + hi) * 0.5;
      const t = (z.pos.x - o.x) * d.x + (cy - o.y) * d.y + (z.pos.z - o.z) * d.z;
      if (t < 1 || t > BUBBLE_RANGE) continue;
      const px = o.x + d.x * t, py = o.y + d.y * t, pz = o.z + d.z * t;
      const hd = Math.max(0, Math.hypot(px - z.pos.x, pz - z.pos.z) - (z.radius || 0.36) * sc);
      const vd = py < lo ? lo - py : py > hi ? py - hi : 0;
      const dist = Math.hypot(hd, vd);
      const bubble = 0.4 + t * 0.012;
      if (dist < bubble) best = Math.min(best, FRICTION_NEAR + (1 - FRICTION_NEAR) * (dist / bubble));
    }
    return best;
  }

  snap() {
    const g = this.game, W = g.weapons, p = g.player, Z = g.zombies;
    const list = Z && Z.alive;
    if (!W || !p || !list || !list.length || !g.camera) return null;
    g.camera.getWorldPosition(_o);
    const yaw = p.yaw, pitch = p.pitch;
    _d.set(-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch));
    let best = null, bestAng = SNAP_CONE, bestDist = 0;
    for (let i = 0; i < list.length; i++) {
      const z = list[i];
      if (!z || z.dead || !z.pos) continue;
      const sc = z.scale || 1;
      _v.set(z.pos.x, z.pos.y + (z.height || 1.6) * sc * 0.66, z.pos.z).sub(_o);
      const dist = _v.length();
      if (dist < 1.5 || dist > SNAP_RANGE) continue;
      const ang = Math.acos(Math.min(1, Math.max(-1, _v.dot(_d) / dist)));
      if (ang < bestAng) { bestAng = ang; best = z; bestDist = dist; }
    }
    if (!best) return null;
    // line of sight to the chest, else the upper chest (a zombie behind a counter): the first thing along the ray
    // must be that zombie
    const sc = best.scale || 1;
    let ok = false, dist = bestDist;
    for (const k of SNAP_HEIGHTS) {
      _v.set(best.pos.x, best.pos.y + (best.height || 1.6) * sc * k, best.pos.z).sub(_o);
      dist = _v.length();
      if (typeof W.traceRay !== 'function') { ok = true; break; }
      let hit = null;
      try { hit = W.traceRay(_o, _t.copy(_v).divideScalar(dist), dist + 0.6, { zombies: true, shootables: false, level: true, blockingOnly: true }); } catch { hit = null; }
      if (hit && hit.kind === 'zombie' && hit.z === best) { ok = true; break; }
    }
    if (!ok) return null;
    const ty = Math.atan2(-_v.x, -_v.z);
    const tp = Math.asin(Math.min(1, Math.max(-1, _v.y / dist)));
    const dy = Math.atan2(Math.sin(ty - yaw), Math.cos(ty - yaw));
    const dp = tp - pitch;
    if (Math.abs(dy) + Math.abs(dp) < 0.008) return null;
    return { yaw: dy * SNAP_AMOUNT, pitch: dp * SNAP_AMOUNT, z: best };
  }
}
