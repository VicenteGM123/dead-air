// Keyboard / mouse / pointer lock / Xbox controller -> actions (GDD §16; rebindable).
// Per action: down(a), pressed(a) (went down this frame), released(a). Taps shorter than a frame are latched.
// Mouse: `mouse.dx/dy` (pixels this frame), `mouse.wheel` (notches this frame), lookDelta() -> radians with
// sensitivity / invertY applied (plus the pad's look, see below). options.holdToggle.{aim,sprint} = 'hold' | 'toggle'.
// move(out) -> { x: strafe right, y: forward } in -1..1: the keyboard's digital axes, else the left stick's analog ones.
// Pointer lock: clicking the canvas while playing locks it (never required with test=1 or while playing with the
// pad). Losing the lock while playing, or Esc when unlocked, pauses the game; Esc while paused (unlocked) resumes.
//
// GAMEPAD (src/core/gamepad.js reads the hardware: first connected 'standard' pad, radial deadzones 0.15 / 0.12).
// It drives the SAME actions, so every system works unchanged (CoD Zombies layout):
//   LS move (analog speed) · L3 sprint (toggle while moving forward; ends when the stick leaves forward, on LT, RT or
//   when out of stamina) · RS look · LT aim (follows the hold/toggle option) · RT fire · A jump ·
//   X interact / buy (tap) and hold X for the hold interactions; X with no prompt = reload (a hold that started as a
//   reload turns into an interact hold when a prompt appears, so hold X keeps repairing windows) · B melee ·
//   Y next weapon (action 'weaponNext') · RB tube grenade (hold to cook) · LB Tiny Tele · D-pad left/right slots 1/2 ·
//   D-pad down swap shoulder · Menu / View pause.
//   Look: exponent curve (magnitude^1.9), yaw 3.3 / pitch 2.1 rad/s at options.padSensitivity 1, +55 % yaw boost
//   ramping in after 0.12 s held at the edge; invertY is shared with the mouse. Aim assist (options.aimAssist, pad
//   look only): friction on / near zombies and a gentle snap on the LT press (AimAssist in gamepad.js), passed to the
//   player as lookDelta().snapYaw / snapPitch (not scaled by the ADS factor).
//   UI: while a menu shows (game.menu.mode) the pad drives menu.padButton(name) instead of the actions (D-pad and left
//   stick = directions with auto-repeat); game.ending.padButton(name) gets first pick while the ending runs. A button
//   used by a menu is ignored by gameplay until released. Start / View in play pause; losing the active pad while
//   playing with it pauses.
// device: 'kbm' | 'pad' = where the last deliberate input came from (emits input:device {device}); glyph() -> 'E' | 'X'
//   for the interact prompt. rumble(weak, strong, ms) (only while the pad is the device and options.rumble), wired to
//   weapon:fire (heavy guns: def.shake >= 0.1), player:hurt, weapon:grenade, big camera shakes (cam.shake >= 0.18
//   calls shakeRumble) and the boss beam (boss.js). options.{padSensitivity, aimAssist, rumble} come from the menu.

import { Gamepad, AimAssist, BTN, BTN_NAME } from './gamepad.js';
import { WEAPON_DEFS } from '../game/weaponDefs.js';

const BINDINGS = {
  forward: ['KeyW', 'ArrowUp'],
  back: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  sprint: ['ShiftLeft', 'ShiftRight'],
  jump: ['Space'],
  aim: ['Mouse2'],
  fire: ['Mouse0'],
  reload: ['KeyR'],
  interact: ['KeyE'],
  melee: ['KeyV', 'Mouse3'],
  grenade: ['KeyG'],
  tactical: ['KeyQ'],
  weapon1: ['Digit1'],
  weapon2: ['Digit2'],
  weaponNext: [],
  shoulder: ['KeyC'],
  pause: ['Escape'],
};

// plain one-button pad actions (aim, sprint and X are handled on their own)
const PAD_SIMPLE = [
  ['jump', BTN.A], ['melee', BTN.B], ['weaponNext', BTN.Y], ['grenade', BTN.RB], ['tactical', BTN.LB],
  ['fire', BTN.RT], ['weapon1', BTN.LEFT], ['weapon2', BTN.RIGHT], ['shoulder', BTN.DOWN],
];
const NAV_DIRS = ['up', 'down', 'left', 'right'];
const NAV_DELAY = 0.38;     // s before a held direction repeats in menus
const NAV_REPEAT = 0.11;    // s between repeats
const LOOK_EXP = 1.9;
const LOOK_YAW = 3.3;       // rad/s at full deflection, padSensitivity 1
const LOOK_PITCH = 2.1;
const EDGE = 0.97;          // stick magnitude that counts as "at the edge"
const EDGE_DELAY = 0.12;
const EDGE_RAMP = 0.35;
const EDGE_BOOST = 0.55;
const SNAP_TIME = 0.12;
const SPRINT_FWD = 0.35;

const BASE_SENS = 0.0022; // radians per pixel at sensitivity 1
const PREVENT = new Set(['Space', 'Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight']);
const WORLD = new Set(['playing', 'down']);

export class Input {
  constructor(game) {
    this.game = game;
    this.bindings = {};
    for (const a in BINDINGS) this.bindings[a] = BINDINGS[a].slice();
    this.options = { sensitivity: 1, invertY: false, holdToggle: { aim: 'hold', sprint: 'hold' },
      padSensitivity: 1, aimAssist: true, rumble: true };
    this.mouse = { dx: 0, dy: 0, wheel: 0, x: 0, y: 0 };
    this.locked = false;
    this.device = 'kbm';
    this.pad = new Gamepad();
    this.assist = new AimAssist(game);
    this._codes = new Set();
    this._tapLatch = new Set();
    this._relLatch = new Set();
    this._state = {};
    for (const a in this.bindings) this._state[a] = { down: false, pressed: false, released: false, toggled: false };
    this._acc = { dx: 0, dy: 0, wheel: 0 };
    this._codeToActions = new Map();
    // pad -> action state (rebuilt every frame)
    this._padHeld = {};
    this._padPress = new Set();
    this._padRel = new Set();
    this._padMove = { x: 0, y: 0 };
    this._padLook = { yaw: 0, pitch: 0, snapYaw: 0, snapPitch: 0 };
    this._swallow = new Set();  // pad buttons a menu used: ignored by gameplay until released
    this._xMode = null;         // 'interact' | 'reload' while X is held
    this._sprintLatch = false;
    this._aimLatch = false;
    this._edgeT = 0;
    this._snap = { yaw: 0, pitch: 0, t: 0 };
    this._nav = { up: -1, down: -1, left: -1, right: -1 };
    this._stickDir = { up: false, down: false, left: false, right: false };
    this._cursorHidden = false;
    this._rebuild();
  }

  init() {
    const canvas = this.game.renderer.domElement;
    this._canvas = canvas;
    addEventListener('keydown', (e) => this._onKey(e, true));
    addEventListener('keyup', (e) => this._onKey(e, false));
    addEventListener('blur', () => this.clear());
    canvas.addEventListener('mousedown', (e) => this._onMouseDown(e));
    addEventListener('mouseup', (e) => this._onButton(`Mouse${e.button}`, false));
    addEventListener('mousemove', (e) => this._onMove(e));
    addEventListener('wheel', (e) => { this._acc.wheel += Math.sign(e.deltaY); this._setDevice('kbm'); }, { passive: true });
    addEventListener('contextmenu', (e) => e.preventDefault());
    document.addEventListener('pointerlockchange', () => this._onLockChange());
    this.pad.init();
    const ev = this.game.events;
    if (ev) {
      ev.on('state', (p) => { if (p && !WORLD.has(p.to)) { this.pad.stopRumble(); this._snap.t = 0; } });
      ev.on('weapon:fire', (e) => this._fireRumble(e));
      ev.on('player:hurt', (e) => {
        const d = Math.max(0, +(e && e.dmg) || 0);
        this.rumble(Math.min(0.75, 0.3 + d / 300), Math.min(0.7, 0.2 + d / 220), 170);
      });
      ev.on('weapon:grenade', (e) => {
        const p = this.game.player;
        if (!e || !e.pos || !p) return;
        const k = Math.max(0, 1 - p.pos.distanceTo(e.pos) / 18);
        if (k > 0) this.rumble(0.55 * k, 0.6 * k, 300);
      });
    }
  }

  bind(action, codes) {
    this.bindings[action] = codes.slice();
    if (!this._state[action]) this._state[action] = { down: false, pressed: false, released: false, toggled: false };
    this._rebuild();
  }

  _rebuild() {
    this._codeToActions.clear();
    for (const a in this.bindings) {
      for (const c of this.bindings[a]) {
        if (!this._codeToActions.has(c)) this._codeToActions.set(c, []);
        this._codeToActions.get(c).push(a);
      }
    }
  }

  down(a) { const s = this._state[a]; return !!s && s.down; }
  pressed(a) { const s = this._state[a]; return !!s && s.pressed; }
  released(a) { const s = this._state[a]; return !!s && s.released; }
  key(code) { return this._codes.has(code); }

  // Clears this frame's pressed flag (a system that used the press can stop others from reacting to it).
  consume(a) { const s = this._state[a]; if (s) s.pressed = false; }

  // Movement axes: keyboard (digital) when any move key is held, else the left stick (analog, magnitude <= 1).
  move(out = { x: 0, y: 0 }) {
    const kx = (this.down('right') ? 1 : 0) - (this.down('left') ? 1 : 0);
    const ky = (this.down('forward') ? 1 : 0) - (this.down('back') ? 1 : 0);
    if (kx || ky) { out.x = kx; out.y = ky; return out; }
    out.x = this._padMove.x;
    out.y = this._padMove.y;
    return out;
  }

  // Look delta in radians for this frame: { yaw, pitch } (positive yaw = turn left, positive pitch = look up).
  // snapYaw / snapPitch: the pad aim-assist snap (applied as is, outside the ADS look scale).
  lookDelta(out = { yaw: 0, pitch: 0 }) {
    const k = BASE_SENS * this.options.sensitivity;
    const L = this._padLook;
    out.yaw = -this.mouse.dx * k + L.yaw;
    out.pitch = -this.mouse.dy * k * (this.options.invertY ? -1 : 1) + L.pitch;
    out.snapYaw = L.snapYaw;
    out.snapPitch = L.snapPitch;
    return out;
  }

  // Interact prompt key for the HUD.
  glyph() { return this.device === 'pad' ? 'X' : 'E'; }

  // Synthetic mouse movement (debug.mouseDelta / harness).
  injectMouse(dx, dy) {
    this._acc.dx += dx;
    this._acc.dy += dy;
  }

  requestLock() {
    if (this.game.params.test || this.locked || !this._canvas || this.device === 'pad') return;
    try {
      const p = this._canvas.requestPointerLock();
      if (p && p.catch) p.catch(() => {});
    } catch { /* lock refused (e.g. no user gesture): stay unlocked */ }
  }

  exitLock() {
    if (document.pointerLockElement) document.exitPointerLock();
  }

  clear() {
    this._codes.clear();
    for (const a in this._state) {
      const s = this._state[a];
      if (s.down) this._relLatch.add(a);
      s.toggled = false;
    }
    this._acc.dx = this._acc.dy = this._acc.wheel = 0;
  }

  // ---------------------------------------------------------------------------------------------- rumble
  rumble(weak, strong, ms) {
    if (!this.options.rumble || this.device !== 'pad' || !this.pad.connected) return;
    this.pad.rumble(weak, strong, ms);
  }

  // cam.shake(amount, duration) hook: only big moments (explosions, stomps, boss hits) rumble.
  shakeRumble(amount, duration) {
    if (!(amount >= 0.18)) return;
    const a = Math.min(0.8, amount);
    this.rumble(a * 0.6, a * 0.7, Math.min(0.4, Math.max(0.1, duration || 0.2)) * 1000);
  }

  _fireRumble(e) {
    if (!e || this.device !== 'pad') return;
    const def = WEAPON_DEFS[e.weaponId];
    const sh = def && def.shake;
    if (!(sh >= 0.1)) return; // light guns (MP7, M16, Zapper) stay silent
    this.rumble(0.15 + sh * 0.9, sh * 1.1, 60 + sh * 280);
  }

  // ---------------------------------------------------------------------------------------------- per frame
  // Called first every frame: latch events into per-frame action state.
  update(dt = 0) {
    this._pollPad(dt);
    const PH = this._padHeld, PP = this._padPress, PR = this._padRel;
    for (const a in this._state) {
      const s = this._state[a];
      const mode = this.options.holdToggle[a];
      const tapped = this._tapLatch.has(a);
      const padHeld = !!PH[a];
      if (mode === 'toggle') {
        if (tapped) s.toggled = !s.toggled;
        s.pressed = tapped || PP.has(a);
        const was = s.down;
        s.down = s.toggled || padHeld; // the pad keeps its own toggle latches (aim option, L3 sprint)
        s.released = was && !s.down;
      } else {
        const held = this._held(a) || padHeld;
        s.pressed = tapped || PP.has(a);
        s.released = (this._relLatch.has(a) || PR.has(a)) && !held;
        s.down = held || tapped;
      }
    }
    this._tapLatch.clear();
    this._relLatch.clear();
    this.mouse.dx = this._acc.dx;
    this.mouse.dy = this._acc.dy;
    this.mouse.wheel = this._acc.wheel;
    this._acc.dx = this._acc.dy = this._acc.wheel = 0;
    this.pad.updateRumble();
    this._updateCursor();
  }

  _held(a) {
    for (const c of this.bindings[a]) if (this._codes.has(c)) return true;
    return false;
  }

  _setDevice(d) {
    if (this.device === d) return;
    this.device = d;
    if (d !== 'pad') this.pad.stopRumble();
    this.game.events?.emit?.('input:device', { device: d });
  }

  // Hide the mouse cursor over the game while playing with the pad unlocked.
  _updateCursor() {
    const hide = this.device === 'pad' && WORLD.has(this.game.state) && !this.locked;
    if (hide === this._cursorHidden || !this._canvas) return;
    this._cursorHidden = hide;
    this._canvas.style.cursor = hide ? 'none' : '';
  }

  _resetPadActions() {
    const H = this._padHeld;
    for (const a in H) H[a] = false;
    this._padMove.x = this._padMove.y = 0;
    const L = this._padLook;
    L.yaw = L.pitch = L.snapYaw = L.snapPitch = 0;
  }

  // Releases every pad-held action (menus took over, pad lost).
  _dropPadLatches() {
    for (const a in this._padHeld) if (this._padHeld[a]) this._padRel.add(a);
    this._sprintLatch = false;
    this._aimLatch = false;
    this._xMode = null;
    this._edgeT = 0;
    this._snap.t = 0;
  }

  _pollPad(dt) {
    const pad = this.pad, g = this.game;
    this._padPress.clear();
    this._padRel.clear();
    pad.poll();
    if (pad.justDisconnected) {
      this._dropPadLatches();
      this._swallow.clear();
      if (this.device === 'pad' && WORLD.has(g.state)) g.pause();
    }
    if (!pad.connected) { this._resetPadActions(); return; }
    if (pad.active) this._setDevice('pad');
    const sw = this._swallow;
    for (const i of sw) if (!pad.btn[i].down) sw.delete(i);

    // UI surfaces first (the ending, then menus)
    if (this._padUi(dt)) {
      this._dropPadLatches();
      for (let i = 0; i < pad.btn.length; i++) if (pad.btn[i].down) sw.add(i);
      this._resetPadActions();
      return;
    }
    const st = g.state;
    if ((this._pr(BTN.MENU) || this._pr(BTN.VIEW)) && WORLD.has(st)) {
      for (let i = 0; i < pad.btn.length; i++) if (pad.btn[i].down) sw.add(i);
      this._dropPadLatches();
      this._resetPadActions();
      g.pause();
      return;
    }
    this._padActions(dt);
  }

  _dn(i) { return this.pad.btn[i].down && !this._swallow.has(i); }
  _pr(i) { return this.pad.btn[i].pressed && !this._swallow.has(i); }
  _rl(i) { return this.pad.btn[i].released; }

  _padActions(dt) {
    const pad = this.pad, g = this.game, H = this._padHeld, PP = this._padPress, PR = this._padRel;
    for (const a in H) H[a] = false;
    for (const [a, i] of PAD_SIMPLE) {
      H[a] = this._dn(i);
      if (this._pr(i)) PP.add(a);
      if (this._rl(i)) PR.add(a);
    }
    const p = g.player;

    // LT aim: hold, or its own latch when the aim option is 'toggle'
    if (this.options.holdToggle.aim === 'toggle') {
      if (this._pr(BTN.LT)) { this._aimLatch = !this._aimLatch; PP.add('aim'); if (!this._aimLatch) PR.add('aim'); }
      H.aim = this._aimLatch;
    } else {
      this._aimLatch = false;
      H.aim = this._dn(BTN.LT);
      if (this._pr(BTN.LT)) PP.add('aim');
      if (this._rl(BTN.LT)) PR.add('aim');
    }

    // left stick (analog move)
    const ls = pad.ls;
    this._padMove.x = ls.x;
    this._padMove.y = ls.y;

    // L3 sprint: CoD toggle while moving forward
    if (this._pr(BTN.L3)) {
      this._sprintLatch = !this._sprintLatch || ls.y > SPRINT_FWD;
      if (this._sprintLatch) PP.add('sprint');
    }
    if (this._sprintLatch && (ls.m < 0.2 || ls.y < 0.2 || H.aim || PP.has('fire') || (p && p._exhausted))) {
      this._sprintLatch = false;
      PR.add('sprint');
    }
    H.sprint = this._sprintLatch;

    // X: interact / buy when something is focused (last frame's focus), else reload
    const focus = !!(g.interact && g.interact.current);
    if (this._pr(BTN.X)) {
      this._xMode = focus ? 'interact' : 'reload';
      PP.add(this._xMode);
    }
    if (this._dn(BTN.X) && this._xMode) {
      if (this._xMode === 'reload' && focus) { PR.add('reload'); this._xMode = 'interact'; } // hold X keeps repairing
      H[this._xMode] = true;
    }
    if (this._rl(BTN.X) && this._xMode) { PR.add(this._xMode); this._xMode = null; }

    this._padLookUpdate(dt, PP.has('aim') && H.aim);
  }

  _padLookUpdate(dt, aimPressed) {
    const g = this.game, o = this.options, rs = this.pad.rs, L = this._padLook;
    L.yaw = L.pitch = L.snapYaw = L.snapPitch = 0;
    const world = WORLD.has(g.state);
    if (rs.m > 0 && world) {
      this._edgeT = rs.m >= EDGE ? this._edgeT + dt : 0;
      const e = Math.min(1, Math.max(0, (this._edgeT - EDGE_DELAY) / EDGE_RAMP));
      const boost = 1 + EDGE_BOOST * e * e * (3 - 2 * e);
      const curve = Math.pow(rs.m, LOOK_EXP) / rs.m; // scales the direction vector by m^exp
      const sens = Math.min(3, Math.max(0.1, +o.padSensitivity || 1));
      const fr = o.aimAssist ? this.assist.friction() : 1;
      L.yaw = -rs.x * curve * LOOK_YAW * sens * boost * fr * dt;
      L.pitch = rs.y * curve * LOOK_PITCH * sens * fr * dt * (o.invertY ? -1 : 1);
    } else {
      this._edgeT = 0;
    }
    // gentle snap on the LT press (only when ADS starts: in toggle mode the press that ends ADS does not snap)
    const S = this._snap;
    if (aimPressed && world && o.aimAssist && g.player && !g.player.ads) {
      const s = this.assist.snap();
      if (s) { S.yaw = s.yaw; S.pitch = s.pitch; S.t = SNAP_TIME; }
    }
    if (S.t > 0 && dt > 0) {
      const f = Math.min(1, dt / S.t);
      L.snapYaw = S.yaw * f;
      L.snapPitch = S.pitch * f;
      S.yaw -= L.snapYaw;
      S.pitch -= L.snapPitch;
      S.t -= dt;
    }
  }

  // Menus / the ending own the pad. Returns true when a menu surface shows (gameplay gets nothing this frame).
  _padUi(dt) {
    const g = this.game, pad = this.pad;
    const end = g.ending && g.ending.active && typeof g.ending.padButton === 'function' ? g.ending : null;
    const menu = g.menu && g.menu.mode && typeof g.menu.padButton === 'function' ? g.menu : null;
    if (!end && !menu) { this._nav.up = this._nav.down = this._nav.left = this._nav.right = -1; return false; }
    const send = (name, i) => {
      let used = false;
      if (end) used = !!end.padButton(name);
      if (!used && menu) used = menu.padButton(name) !== false;
      if (used && i >= 0) this._swallow.add(i);
      return used;
    };
    // face / shoulder / system buttons (edges)
    for (let i = 0; i < pad.btn.length; i++) {
      if (i >= BTN.UP && i <= BTN.RIGHT) continue;
      if (i === BTN.HOME || !this._pr(i)) continue;
      if (!send(BTN_NAME[i], i) && !menu && (i === BTN.MENU || i === BTN.VIEW) && WORLD.has(g.state)) {
        this._swallow.add(i);
        g.pause();
        return true;
      }
    }
    if (!menu) { this._nav.up = this._nav.down = this._nav.left = this._nav.right = -1; return false; }
    // directions: D-pad or the left stick (dominant axis, hysteresis), auto-repeat while held
    const ls = pad.ls, SD = this._stickDir;
    const ax = Math.abs(ls.x), ay = Math.abs(ls.y);
    const on = (dir, v, other) => (SD[dir] ? v > 0.35 : v > 0.55 && v > other);
    SD.up = on('up', ls.y, ax); SD.down = on('down', -ls.y, ax);
    SD.left = on('left', -ls.x, ay); SD.right = on('right', ls.x, ay);
    const dpad = { up: BTN.UP, down: BTN.DOWN, left: BTN.LEFT, right: BTN.RIGHT };
    for (const dir of NAV_DIRS) {
      const held = this._dn(dpad[dir]) || SD[dir];
      const N = this._nav;
      if (!held) { N[dir] = -1; continue; }
      if (N[dir] < 0) { N[dir] = 0; send(dir, -1); continue; }
      const before = N[dir];
      N[dir] += dt;
      if (N[dir] >= NAV_DELAY) {
        const k0 = Math.floor((before - NAV_DELAY) / NAV_REPEAT), k1 = Math.floor((N[dir] - NAV_DELAY) / NAV_REPEAT);
        if (before < NAV_DELAY || k1 > k0) send(dir, -1);
      }
    }
    return true;
  }

  // ---------------------------------------------------------------------------------------------- keyboard / mouse
  _onKey(e, isDown) {
    if (PREVENT.has(e.code)) e.preventDefault();
    if (isDown && e.repeat) return;
    if (isDown) this._setDevice('kbm');
    if (e.code === 'Escape' && isDown) this._onEscape();
    this._onButton(e.code, isDown);
  }

  _onButton(code, isDown) {
    const acts = this._codeToActions.get(code);
    if (isDown) this._codes.add(code); else this._codes.delete(code);
    if (!acts) return;
    for (const a of acts) (isDown ? this._tapLatch : this._relLatch).add(a);
  }

  _onMouseDown(e) {
    this._canvas.focus();
    this._setDevice('kbm');
    const st = this.game.state;
    if ((st === 'playing' || st === 'down') && !this.locked && !this.game.params.test) {
      this.requestLock();
      return; // the locking click is not a shot
    }
    this._onButton(`Mouse${e.button}`, true);
  }

  _onMove(e) {
    this.mouse.x = e.clientX;
    this.mouse.y = e.clientY;
    if (Math.abs(e.movementX || 0) + Math.abs(e.movementY || 0) > 3) this._setDevice('kbm');
    // Look only while locked; unlocked test sessions can drag-look with the right button.
    if (this.locked || (this.game.params.test && (e.buttons & 2))) {
      this._acc.dx += e.movementX || 0;
      this._acc.dy += e.movementY || 0;
    }
  }

  _onLockChange() {
    const was = this.locked;
    this.locked = document.pointerLockElement === this._canvas;
    if (was && !this.locked) {
      this.clear();
      const st = this.game.state;
      if (st === 'playing' || st === 'down') this.game.pause();
    }
  }

  _onEscape() {
    if (this.locked) return; // the browser releases the lock; _onLockChange pauses
    const st = this.game.state;
    if (st === 'playing' || st === 'down') this.game.pause();
    else if (st === 'paused') this.game.resume();
  }
}
