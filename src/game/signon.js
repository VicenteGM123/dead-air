// DEAD AIR — Sign-On (GDD §10.1): the Master Control power lever and the station coming ON THE AIR.
//
// Builds (init, into the master_control area, unless a room already placed them): the 'sign_on_lever' prop at the
// sign_on_lever anchor (knife switch under a hinged red hood + ON AIR lamp; light anchor 'signon_lamp'), the console
// island at mc_console (audio + switcher + monitor segments with the scr_preview monitor, walnut end cheeks), the
// 4x4 bc_monitor_wall at prop_monitor_wall when the room has none (its corner CRTs registered as ss_mc_w / ss_mc_e)
// and an ON AIR box over D5 on the MC side (the studio doors D4 / D6 / D7 carry theirs, level.js lights them).
// Before power the ON AIR lamp pulses every 2 s and the lever's prompt is key-only [E] (interactable
// 'machine_sign_on'). trigger() plays the whole sequence (real time; t = seconds since the lever):
//   0.00  the hood flips up, the lever winds up and SLAMS (0.24: thunk, arc sparks, dust, squash, shake, hit-stop)
//         while the hero yanks it with the left arm and a little lunge (animator.override chained after the weapons
//         pose), the 60 Hz hum swells, the 16 MC-wall CRTs black out. Emits machine:sign_on {}.
//   0.30-1.80  the wall CRTs warm up one by one in snake order: dot -> line -> picture, settling on colour bars
//         (a crt_ping each; screens.warmUp).
//   1.80  every TV in the station opens on colour bars (screens.override priority 0 + blink), the 1 kHz bars tone
//         through the nearest TV speakers.
//   2.60  POWER: machines.powerOn = true, emits power:on {}; every TV cuts to the WZTV 13 station ID (1.6 s, then the
//         powered defaults: live feeds, the MC wall mix, Hootie's show); bells G4-C5-E5-G5 + the 8-bar funk
//         Sign-On theme; confetti from the ON AIR lamp; THE COLOUR WAVE starts at the lever [29, 1, -7.6]:
//         mats.uniforms uWaveOrigin / uWaveRadius grow at 15 m/s to 45 m (3 s: t 2.6-5.6) — the toon shader restores
//         saturation inside it and draws the scrolling colour-bar band at its front — then races on to 160 m and
//         the global grade is switched (uSatEnv 1, uAmber 0, uWaveRadius -1). Everything keyed to the wave
//         (level lights + door ON AIR boxes, feed-camera tallies, the MC ON AIR box, other agents' tally lights,
//         neon, Telly...) uses waveReached(pos) or lever distance / 15 s after power:on.
//   3.20  emits machine:sign_on_look { seconds: 1.5, origin } (zombies may stop and turn their heads to a TV).
//   6.00  DY buzzes and swings open (level.openDoor('dy_mc_yard')) with a gust of night wind; the tower beacons
//         start blinking (level.js / the yard's tower_beacons follow level.beacons 3.4 s after power:on).
//  10.60  emits machine:sign_on_done {}; state 'on'.
// The console plays along: the audio board's VU needles rest before power, pin at 0 VU on the 1 kHz tone and bounce
// to the theme / programme audio; the switcher's T-bar is "taken" to air at 2.6 s.
// power=1 / debug.power(true) / machines.setPower(true) (power:on from elsewhere) jump straight to the powered
// state; debug.power(false) and newGame() put the lever back up.
//
// API (game.signon)
//   state 'off' | 'sequence' | 'on', done (bool: the lever was thrown or power is on), t (sequence seconds)
//   trigger() -> bool                       starts the sequence (false if already powered / running)
//   waveReached(pos:Vector3|[x,y,z]) -> bool   true once power is on and the colour wave has passed pos
//   waveTime(pos) -> seconds until the wave reaches pos (0 once reached, Infinity before power)
//   waveRadius (m, -1 = no wave), origin (Vector3), lever (prop Group), wall (the fallback monitor wall or null),
//   WAVE { speed, radius }, timeScale (debug/tests: 0 holds the sequence on one frame)
// Events (GDD §18.15 + these machine:* extras): machine:sign_on {} (t 0), power:on {} (t 2.6),
//   machine:sign_on_look { seconds, origin } (t 3.2), machine:sign_on_done {} (t 10.6).

import * as THREE from 'three';
import { PAL } from '../core/config.js';
import { mergeByMaterial } from '../core/geo.js';
import { placeProp } from '../props/index.js';
import { OVERRIDE_GROUPS, PRIORITY } from './screens.js';

export const WAVE = { speed: 15, radius: 45, far: 160, farSpeed: 60 };
const TL = { impact: 0.24, bars: 1.8, power: 2.6, look: 3.2, idEnd: 4.2, dy: 6.0, done: 10.6 };
const FLICKER = [[0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]];
const CHIMES = ['ee_chime_red', 'ee_chime_yellow', 'ee_chime_green', 'ee_chime_blue']; // G4 C5 E5 G5
const CONSOLE = [
  // dx along the console's local x (rotY pi: local +x = world west): audio west, switcher centre, monitors east
  { id: 'bc_console_audio', dx: 1.2, opts: { vinyl: '#8A3A22' } },
  { id: 'bc_console_switcher', dx: 0, opts: { tbar: 0.35 } },
  { id: 'bc_console_monitor', dx: -1.2, opts: { group: 'scr_decor', id: 'mc_program' } },
];
const D5_ONAIR = { pos: [23.225, 2.92, -4.0], rotY: -Math.PI / 2 };

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler();
const smooth = (a, b, x) => { const u = clamp01((x - a) / (b - a)); return u * u * (3 - 2 * u); };
// The hero's lever yank (left arm; the gun arm keeps the weapons pose): reach up 0-0.1 s, slam 0.1-0.24 s with a
// forward lean, hold, let go by 0.75 s. Keys: [t, shoulderL x, shoulderL z, elbowL x, spine x].
const PULL = [[0, 0.3, 0.1, 0.3, 0], [0.1, 2.05, 0.02, 0.55, -0.05], [0.24, 0.8, 0.05, 0.12, 0.26], [0.45, 0.85, 0.06, 0.2, 0.18], [0.75, 0.3, 0.1, 0.3, 0]];
const UP_V = new THREE.Vector3(0, 1, 0);
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const easeOutBack = (x, s = 1.8) => 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2;

export class SignOn {
  constructor(game) {
    this.game = game;
    this.state = 'off';
    this.done = false;
    this.t = 0;
    this.waveRadius = -1;
    this.origin = new THREE.Vector3(29, 1, -7.6);
    this.lever = null;
    this.wall = null;
    this.WAVE = WAVE;
    this._clock = 0;
    this._next = 0;
    this._waveDone = false;
    this._emitting = false;
    this._switches = [];
    this._ov = [];
    this._whiteout = 0;
    this.timeScale = 1;         // debug / tests: 0 holds the sequence on a frame (freeze-frame screenshots)
  }

  // ------------------------------------------------------------------------------------------------ build
  init() {
    const g = this.game;
    const lv = g.level;
    const a = lv && lv.anchors && lv.anchors.sign_on_lever;
    if (a) this.origin.set(a.pos.x, 1, a.pos.z);
    this._timeline = [
      [0, () => this._beatStart()],
      [TL.impact, () => this._beatImpact()],
      [TL.bars, () => this._beatBars()],
      [TL.power, () => this._beatPower()],
      [TL.look, () => g.events.emit('machine:sign_on_look', { seconds: 1.5, origin: this.origin.clone() })],
      [TL.idEnd, () => this._beatWall()],
      [TL.dy, () => this._beatDoor()],
      [TL.done, () => { this.state = 'on'; g.events.emit('machine:sign_on_done', {}); }],
    ];
    try {
      this._build();
    } catch (err) {
      console.error('[signon] build failed', err);
    }
    g.events.on('power:on', () => { if (!this._emitting) this._instantOn(); });
    this._toOff();
  }

  _build() {
    const g = this.game;
    const lv = g.level;
    const parent = lv.areaRoots && lv.areaRoots.master_control;
    if (!parent) return;
    let lever = null;
    let consoleFound = false;
    parent.traverse((o) => {
      const id = o.userData && o.userData.id;
      if (id === 'sign_on_lever' && !lever) lever = o;
      if (typeof id === 'string' && id.startsWith('bc_console_')) consoleFound = true;
    });
    const a = lv.anchors.sign_on_lever;
    if (!lever && a) {
      lever = placeProp(g, parent, 'sign_on_lever', {
        pos: [a.pos.x, 0, a.pos.z], rotY: a.rotY ?? Math.PI, area: 'master_control', tag: 'machine',
        opts: { anchorId: 'signon_lamp', lamp: 0.2 },
      });
      this._anchorId = 'signon_lamp';
    }
    const island = new THREE.Group();
    island.name = 'signon_island';
    parent.add(island);
    const c = lv.anchors.mc_console;
    if (c && !consoleFound) {
      const rot = c.rotY ?? Math.PI;
      const cos = Math.cos(rot);
      for (const s of CONSOLE) placeProp(g, island, s.id, { pos: [c.pos.x + s.dx * cos, 0, c.pos.z], rotY: rot, area: 'master_control', opts: s.opts, tag: 'machine' });
      for (const sx of [-1, 1]) placeProp(g, island, 'bc_console_end', { pos: [c.pos.x + sx * 1.825, 0, c.pos.z], rotY: rot, area: 'master_control', tag: 'machine' });
    }
    this._findConsoleParts(parent);
    this._buildWall(parent, island);
    const box = placeProp(g, island, 'bc_on_air', { pos: D5_ONAIR.pos, rotY: D5_ONAIR.rotY, area: 'master_control', opts: { lit: false }, colliders: false });
    const P = box.userData.parts || {};
    if (P.lamp && box.userData.lampMats) {
      const mats = box.userData.lampMats;
      box.getWorldPosition(_v);
      this._switches.push({ pos: _v.clone().setY(3.0), apply: (on) => { P.lamp.material = on ? mats.on : mats.off; }, sound: 'onair_clack', t: -1, done: false, sparks: true });
    }
    mergeByMaterial(island);
    if (lever) {
      this.lever = lever;
      this.parts = lever.userData.parts || {};
      this.rig = lever.userData.rig || { leverOff: 1.2, leverOn: 0, coverClosed: 0, coverOpen: 1.95 };
      this._lampMat = new THREE.MeshBasicMaterial({ map: g.cards.get('on_air', { lit: true }), color: 0xffffff });
      this._lampMat.name = 'signon:lamp';
      this._jewelMat = new THREE.MeshBasicMaterial({ color: '#FFB347' });
      this._jewelMat.name = 'signon:jewels';
      if (this.parts.lamp) this.parts.lamp.material = this._lampMat;
      if (this.parts.jewels) this.parts.jewels.material = this._jewelMat;
      const ip = lever.userData.interact ? lever.userData.interact.point : [0, 1.0, -0.5];
      lever.updateMatrixWorld(true);
      const pos = lever.localToWorld(new THREE.Vector3(ip[0], ip[1], ip[2]));
      g.interact.register({
        id: 'machine_sign_on', pos, radius: 1.7,
        enabled: () => this.state === 'off' && !this._powered(),
        prompt: () => ({}),
        use: () => this.trigger(),
      });
    }
  }

  // Console details that play along: the audio board's two VU needles (rest on the left stop before power, pinned
  // at 0 VU by the 1 kHz tone, then bouncing to the funk theme / programme audio) and the switcher's T-bar, which
  // the station "takes" to air at power (snaps from 0.35 to -0.35 rad with a bounce).
  _findConsoleParts(parent) {
    const C = { needles: [], lvl: [], tbar: null };
    parent.traverse((o) => {
      const id = o.userData && o.userData.id;
      const P = o.userData && o.userData.parts;
      if (!P) return;
      if (id === 'bc_console_audio') for (const n of [P.needleL, P.needleR]) if (n) { C.needles.push(n); C.lvl.push(0); }
      if (id === 'bc_console_switcher' && P.tbar && !C.tbar) C.tbar = P.tbar;
    });
    this._console = C;
  }

  _animConsole(dt) {
    const C = this._console;
    if (!C || (!C.needles.length && !C.tbar) || !this._nearPlayer(16)) return;
    const st = this.t, t = this._clock;
    const music = (x) => 0.36 + 0.42 * Math.exp(-((x % 0.5) / 0.11)) + 0.14 * Math.sin(x * 7.3) * Math.sin(x * 2.1);
    let target;
    if (this.state === 'off') target = 0.04 + 0.02 * Math.sin(t * 47);
    else if (this.state === 'sequence') {
      if (st < TL.bars) target = 0.1 + 0.3 * clamp01(st / TL.bars) * (0.6 + 0.4 * Math.sin(st * 31));
      else if (st < TL.power) target = 0.78 + 0.01 * Math.sin(st * 80);
      else target = music(st - TL.power);
    } else target = 0.2 + 0.55 * music(t) * (0.8 + 0.2 * Math.sin(t * 0.7));
    const k = Math.min(1, dt * 14);
    C.needles.forEach((n, i) => {
      const tg = Math.min(1.05, target * (i % 2 ? 0.93 : 1) + (i % 2 ? 0.02 * Math.sin(t * 13) : 0));
      C.lvl[i] += (tg - C.lvl[i]) * k;
      n.rotation.z = -0.72 + 1.3 * C.lvl[i];
    });
    if (C.tbar) {
      let x = 0.35;
      if (this.state === 'on') x = -0.35;
      else if (this.state === 'sequence' && st >= TL.power) x = 0.35 - 0.7 * easeOutBack(clamp01((st - TL.power) / 0.4), 2.2);
      C.tbar.rotation.x = x;
    }
  }

  // The 4x4 MC monitor wall is the Sign-On's stage (snake warm-up, pass B feeds). The master_control room owns it;
  // when the room has not built one (no scr_mc_* screen and no bc_monitor_wall prop), place it at the
  // prop_monitor_wall anchor so the sequence always plays. The two bottom-corner CRTs are re-registered with the
  // screen-spawn ids ss_mc_w / ss_mc_e (screens.telegraph finds them by id).
  _buildWall(parent, island) {
    const g = this.game;
    const lv = g.level;
    const s = g.screens;
    const wa = lv.anchors && lv.anchors.prop_monitor_wall;
    if (!s || !wa) return;
    if ((s.groups.scr_mc_feeds || []).length + (s.groups.scr_mc_canned || []).length > 0) return;
    let found = false;
    parent.traverse((o) => { if (o.userData && o.userData.id === 'bc_monitor_wall') found = true; });
    if (found) return;
    const rot = wa.rotY ?? Math.PI;
    const back = 0.25; // prop back face at local z = +0.25: stand it against the wall face
    const wall = placeProp(g, island, 'bc_monitor_wall', {
      pos: [wa.pos.x - Math.sin(rot) * back, 0, wa.pos.z - Math.cos(rot) * back], rotY: rot, area: 'master_control', tag: 'machine',
    });
    if (!wall) return;
    // local variant: the kit's brushed 'metal' preset (rough 0.42, metal 0.7) blows out into a big specular hot
    // spot on the wall's top bevels under MC's low ceiling; a satin finish reads as brushed aluminium without it.
    const satin = new Map();
    wall.traverse((o) => {
      const d = o.isMesh && o.material && o.material.userData && o.material.userData.daToon;
      if (!d || !d.params || !(d.params.metal >= 0.6) || !d.params.map) return;
      let v = satin.get(o.material);
      if (!v) satin.set(o.material, (v = g.mats.toon('#C3C8D0', { ...d.params, rough: 0.74, metal: 0.18, env: 0.14 })));
      o.material = v;
    });
    const screens = wall.userData.screens || [];
    const spawnIds = { mcwall_r3c0: 'ss_mc_w', mcwall_r3c3: 'ss_mc_e' };
    for (const sc of screens) {
      const ssId = spawnIds[sc.id || (sc.mesh.userData && sc.mesh.userData.screenId)];
      if (!ssId) continue;
      s.register(sc.mesh, 'scr_mc_canned', { id: ssId });
      if (lv.objects && !lv.objects[ssId]) lv.objects[ssId] = { group: wall, screen: sc.mesh };
    }
    this.wall = wall;
  }

  // ------------------------------------------------------------------------------------------------ lifecycle
  reset() {
    for (const h of this._ov) h.cancel();
    this._ov.length = 0;
    this._toOff();
  }

  update() {
    const g = this.game;
    const dt = (g.time.realDt || 0) * this.timeScale;
    this._clock += dt;
    if (this.state === 'off') {
      if (this._powered()) this._instantOn();
      else this._lamp(0.1 + 0.9 * Math.sin(Math.PI * ((this._clock % 2) / 2)) ** 3);
    } else if (this.state === 'sequence') {
      this._tick(dt);
    } else {
      if (!this._powered()) this._toOff();
      else this._lamp(0.94 + 0.06 * Math.sin(this._clock * 377) * Math.sin(this._clock * 1.3));
    }
    this._updateSwitches(dt);
    this._animConsole(dt);
    if (this._pullFn && (this.state !== 'sequence' || this.t >= PULL[PULL.length - 1][0])) this._heroPull(false);
  }

  // ------------------------------------------------------------------------------------------------ API
  trigger() {
    if (this.state !== 'off' || this._powered()) return false;
    this._heroPull(true);
    this.state = 'sequence';
    this.done = true;
    this.t = 0;
    this._next = 0;
    this._waveDone = false;
    this.waveRadius = -1;
    this._tick(0);
    return true;
  }

  waveReached(pos) {
    if (!this._powered()) return false;
    if (this._waveDone || this.waveRadius < 0 && this.state !== 'sequence') return true;
    if (this.waveRadius < 0) return false;
    const p = pos && pos.isVector3 ? pos : _w.set(pos[0], pos[1] ?? 1, pos[2]);
    return p.distanceTo(this.origin) <= this.waveRadius;
  }

  waveTime(pos) {
    if (!this._powered() && this.state !== 'sequence') return Infinity;
    if (this.waveReached(pos)) return 0;
    const p = pos && pos.isVector3 ? pos : _w.set(pos[0], pos[1] ?? 1, pos[2]);
    const r = this.waveRadius < 0 ? -(TL.power - this.t) * WAVE.speed : this.waveRadius;
    return Math.max(0, (p.distanceTo(this.origin) - r) / WAVE.speed);
  }

  // ------------------------------------------------------------------------------------------------ sequence
  _tick(dt) {
    this.t += dt;
    const t = this.t;
    while (this._next < this._timeline.length && t >= this._timeline[this._next][0]) {
      const fn = this._timeline[this._next][1];
      this._next++;
      try { fn(); } catch (err) { console.error('[signon] beat failed', err); }
    }
    this._pose(t);
    // ON AIR lamp: strobe while the lever travels, a low hum that swells with the transformer, then a hard flash
    if (t < TL.impact) this._lamp(Math.floor(t * 30) % 2 ? 1 : 0.15);
    else if (t < TL.power) this._lamp(0.22 + 0.3 * ((t - TL.impact) / (TL.power - TL.impact)) + 0.05 * Math.sin(t * 377));
    else this._lamp(1 + 1.1 * Math.exp(-(t - TL.power) * 5));
    // the colour wave
    if (t >= TL.power && !this._waveDone) {
      const k = t - TL.power;
      const r0 = WAVE.radius / WAVE.speed;
      this.waveRadius = k < r0 ? k * WAVE.speed : WAVE.radius + (k - r0) * WAVE.farSpeed;
      const U = this.game.mats.uniforms;
      if (this.waveRadius >= WAVE.far) this._finishWave();
      else { U.uWaveOrigin.value.copy(this.origin); U.uWaveRadius.value = this.waveRadius; }
    }
    // power-surge flash on the frame
    const post = this.game.render.post;
    if (t >= TL.power && t < TL.power + 0.45) {
      this._whiteout = 0.012 * Math.exp(-(t - TL.power) * 12);
      post.whiteout = this._whiteout;
    } else if (this._whiteout > 0) {
      this._whiteout = 0;
      post.whiteout = 0;
    }
  }

  // Poses the hero's left arm on the lever for the slam (animator.override, chained after the weapons pose so the
  // gun arm keeps its hold), with a squash on impact. Only when the hero stands at the lever.
  _heroPull(on) {
    const p = this.game.player;
    const a = p && p.animator;
    if (!a) return;
    if (!on) {
      if (this._pullFn && a.override === this._pullFn) a.override = this._pullPrev || null;
      this._pullFn = null;
      if (p.rig && p.rig.root) { p.rig.root.scale.set(1, 1, 1); if (this._pullRoot) p.rig.root.position.copy(this._pullRoot); }
      this._pullRoot = null;
      return;
    }
    if (a.override || !this._nearPlayer(2.4)) return;
    const w = this.game.weapons;
    this._pullPrev = a.override;
    this._pullRoot = p.rig && p.rig.root ? p.rig.root.position.clone() : null;
    this._pullFn = (rig, dt) => {
      if (typeof w?._poseFn === 'function') { try { w._poseFn(rig, dt); } catch (err) { /* weapons pose is theirs */ } }
      const t = this.t, J = rig.joints || {};
      if (this.state !== 'sequence' || t >= PULL[PULL.length - 1][0]) return; // update() removes the override
      let i = 0;
      while (i < PULL.length - 2 && t > PULL[i + 1][0]) i++;
      const A = PULL[i], B = PULL[i + 1], u = smooth(A[0], B[0], t);
      const k = (n) => A[n] + (B[n] - A[n]) * u;
      const wt = smooth(0, 0.06, t) * (1 - smooth(0.5, 0.75, t));
      const set = (j, x, y, z) => { if (!j) return; _q.setFromEuler(_e.set(x, y, z)); j.quaternion.slerp(_q, wt); };
      set(J.shoulderL, k(1), 0, k(2));
      set(J.elbowL, k(3), 0, 0);
      if (J.spine) J.spine.quaternion.multiply(_q.setFromEuler(_e.set(k(4) * wt, 0, 0)));
      const sq = t > TL.impact ? 0.07 * Math.exp(-(t - TL.impact) * 10) * Math.cos((t - TL.impact) * 28) : 0;
      if (rig.root) {
        rig.root.scale.set(1 + sq * 0.5, 1 - sq, 1 + sq * 0.5);
        // a little lunge toward the switch (model only; the player does not move)
        if (this._pullRoot) rig.root.position.set(this._pullRoot.x, this._pullRoot.y, this._pullRoot.z - 0.32 * smooth(0.02, 0.2, t) * (1 - smooth(0.4, 0.75, t)));
      }
    };
    a.override = this._pullFn;
  }

  _beatStart() {
    const g = this.game;
    g.events.emit('machine:sign_on', {});
    if (g.audio) g.audio.play('signon_hum', { pos: this.origin });
  }

  _beatImpact() {
    const g = this.game;
    const P = this.parts || {};
    if (g.audio) g.audio.play('signon_thunk', { pos: this.origin });
    if (P.lever) {
      P.lever.rotation.x = 0;
      P.lever.updateWorldMatrix(true, false);
      P.lever.localToWorld(_v.set(0, 0.24, 0.02));
      g.fx.burst(_v, { shape: 'spark', count: 26, speed: 6.5, size: 0.045, life: 0.5, colors: ['#FFFFFF', '#BFE8FF', '#FFE8A0', PAL.crtCyan], dir: UP_V, cone: 1.3 });
      g.fx.burst(_v, { shape: 'star', count: 4, speed: 2.2, size: 0.09, life: 0.5, colors: ['#FFF3B0', PAL.crtCyan] });
      g.fx.flashLight(_v, '#BFE8FF', 7, 0.14);
    }
    g.fx.burst(_w.set(this.origin.x, 0.12, this.origin.z), { shape: 'puff', count: 9, speed: 1.4, size: 0.2, life: 0.7, colors: ['#D8D0C4', '#BFB6AA'] });
    if (this._nearPlayer(9)) {
      g.cam.shake?.(0.22, 0.32);
      g.hitStop(0.05);
    }
    // MC wall: black out, then the snake warm-up (0.30 .. 1.80)
    g.screens?.warmUp?.(null, { start: 0.3 - TL.impact, end: TL.bars - TL.impact, settle: 'color_bars' });
  }

  _beatBars() {
    const s = this.game.screens;
    if (!s) return;
    this._ov.push(s.override('color_bars', OVERRIDE_GROUPS, TL.power - TL.bars + 0.05, PRIORITY.sequence));
    s.blink(null, { spread: 0.25, from: this.origin, except: s.wallOrder() });
    s.speaker('tone_1khz', { near: 2, dur: TL.power - TL.bars, vol: 0.9 });
  }

  _beatPower() {
    const g = this.game;
    const s = g.screens;
    // the single power flag, then everyone else (level lights, sponsors, Telly, feeds...) hears power:on
    this._emitting = true;
    try {
      g.machines.powerOn = true;
      g.events.emit('power:on', {});
    } finally {
      this._emitting = false;
    }
    const U = g.mats.uniforms;
    U.uWaveOrigin.value.copy(this.origin);
    U.uWaveRadius.value = 0;
    this.waveRadius = 0;
    if (s) {
      for (const h of this._ov) h.cancel();
      this._ov.length = 0;
      this._ov.push(s.override('station_id', OVERRIDE_GROUPS, TL.idEnd - TL.power, PRIORITY.sequence));
      s.blink(null, { spread: 0.08, dur: 0.14 });
    }
    if (g.audio) {
      g.audio.play('sting_sign_on_theme');
      CHIMES.forEach((id, i) => g.audio.play(id, { delay: i * 0.14, vol: 0.75 }));
    }
    const P = this.parts || {};
    if (P.lamp) {
      P.lamp.getWorldPosition(_v);
      g.fx.burst(_v, { shape: 'confetti', count: 44, speed: 5.5, life: 1.9, gravity: 6, colors: PAL.BARS, dir: UP_V, cone: 1.0 });
      g.fx.burst(_v, { shape: 'star', count: 9, speed: 3.2, size: 0.13, life: 1.1, colors: [PAL.marqueeGold, '#FFF3B0', PAL.onAirRed] });
      g.fx.flashLight(_v, PAL.onAirRed, 9, 0.3);
    }
    if (this._nearPlayer(14)) g.cam.shake?.(0.14, 0.5);
  }

  _beatWall() {
    const s = this.game.screens;
    if (s) s.blink(s.wallOrder(), { spread: 0.35 });
  }

  _beatDoor() {
    const g = this.game;
    const lv = g.level;
    const d = lv.doors && lv.doors.dy_mc_yard;
    if (!d || d.open) return;
    lv.openDoor('dy_mc_yard');
    const pos = d.pos ? _v.copy(d.pos) : _v.set(35, 0, -8);
    const inside = d.approach && d.approach.master_control;
    const dir = inside ? _w.subVectors(inside, pos).setY(0).normalize() : _w.set(-1, 0, 0);
    dir.y = 0.12;
    pos.y = 1.1;
    g.fx.burst(pos, { shape: 'puff', count: 14, speed: 2.8, size: 0.24, life: 1.2, gravity: -0.3, drag: 1.5, colors: ['#9FB6FF', '#C8D2F0', '#E6E9F5'], dir, cone: 0.55 });
    g.fx.burst(pos, { shape: 'confetti', count: 12, speed: 3.6, size: 0.06, life: 2.4, gravity: 2.2, colors: [PAL.avocado, PAL.mustard, PAL.burntOrange], dir, cone: 0.7 });
    if (g.audio) g.audio.play('world_desert', { pos: pos.clone(), vol: 0.8 });
  }

  _finishWave() {
    const U = this.game.mats.uniforms;
    this._waveDone = true;
    this.waveRadius = -1;
    U.uSatEnv.value = 1;
    U.uAmber.value = 0;
    U.uWaveRadius.value = -1;
  }

  // Lever + hood animation (anticipation, slam, bounce) and the cabinet's squash & stretch.
  _pose(t) {
    const P = this.parts;
    if (!P || !this.lever) return;
    const R = this.rig;
    if (P.cover) P.cover.rotation.x = R.coverOpen * easeOutBack(clamp01(t / 0.2), 1.6);
    if (P.lever) {
      let x;
      if (t < 0.1) x = R.leverOff + 0.16 * Math.sin((t / 0.1) * (Math.PI / 2));
      else if (t < TL.impact) { const u = (t - 0.1) / (TL.impact - 0.1); x = (R.leverOff + 0.16) * (1 - u * u * u); }
      else { const k = t - TL.impact; x = 0.18 * Math.abs(Math.sin(k * 15)) * Math.exp(-k * 8); }
      P.lever.rotation.x = x;
    }
    const k = t - TL.impact;
    if (k >= 0 && k < 0.8) {
      const s = 0.075 * Math.exp(-k * 9) * Math.cos(k * 30);
      this.lever.scale.set(1 + s * 0.5, 1 - s, 1 + s * 0.5);
    } else if (k >= 0.8) this.lever.scale.set(1, 1, 1);
  }

  _lamp(level) {
    if (this._lampMat) this._lampMat.color.setScalar(0.1 + 1.75 * level);
    if (this._jewelMat) this._jewelMat.color.set('#FFB347').multiplyScalar(0.12 + 2.2 * Math.min(level, 1.2));
    if (this._anchorId && this.game.lights) this.game.lights.setAnchor(this._anchorId, { intensity: 2.4 * (0.08 + 0.92 * Math.min(level, 1.3)) });
  }

  // ------------------------------------------------------------------------------------------------ states
  _instantOn() {
    const g = this.game;
    this._heroPull(false);
    for (const h of this._ov) h.cancel();
    this._ov.length = 0;
    if (this.state === 'sequence' && this._whiteout > 0) { g.render.post.whiteout = 0; this._whiteout = 0; }
    this.state = 'on';
    this.done = true;
    this.t = TL.done;
    this._next = this._timeline ? this._timeline.length : 0;
    this._waveDone = true;
    this.waveRadius = -1;
    const U = g.mats.uniforms;
    if (U.uWaveRadius.value >= 0 || U.uSatEnv.value < 1) { U.uSatEnv.value = 1; U.uAmber.value = 0; U.uWaveRadius.value = -1; }
    const P = this.parts;
    if (P) {
      if (P.lever) P.lever.rotation.x = this.rig.leverOn ?? 0;
      if (P.cover) P.cover.rotation.x = this.rig.coverOpen;
      if (this.lever) this.lever.scale.set(1, 1, 1);
    }
    this._lamp(1);
    for (const sw of this._switches) { sw.apply(true); sw.done = true; sw.t = 1; }
  }

  _toOff() {
    this._heroPull(false);
    this.state = 'off';
    this.done = false;
    this.t = 0;
    this._next = 0;
    this._waveDone = false;
    this.waveRadius = -1;
    if (this._whiteout > 0) { this.game.render.post.whiteout = 0; this._whiteout = 0; }
    const P = this.parts;
    if (P) {
      if (P.lever) P.lever.rotation.x = this.rig.leverOff;
      if (P.cover) P.cover.rotation.x = this.rig.coverClosed ?? 0;
      if (this.lever) this.lever.scale.set(1, 1, 1);
    }
    for (const sw of this._switches) { sw.apply(false); sw.done = false; sw.t = -1; }
  }

  // Things this file lights when the wave passes them: relay clack + 3-flash flicker + a few red sparks.
  _updateSwitches(dt) {
    if (this.state === 'off') return;
    for (const sw of this._switches) {
      if (sw.done) continue;
      if (sw.t < 0) {
        if (!this.waveReached(sw.pos)) continue;
        sw.t = 0;
        sw.state = null;
        if (sw.sound && this.game.audio) this.game.audio.play(sw.sound, { pos: sw.pos });
        if (sw.sparks) this.game.fx.burst(sw.pos, { shape: 'spark', count: 10, speed: 3, size: 0.03, life: 0.35, colors: [PAL.onAirRed, '#FFD0C0', '#FFFFFF'] });
      }
      sw.t += dt;
      let on = true;
      for (const [t0, v] of FLICKER) if (sw.t >= t0) on = v;
      if (on !== sw.state) { sw.apply(on); sw.state = on; }
      if (sw.t >= FLICKER[FLICKER.length - 1][0]) sw.done = true;
    }
  }

  _powered() {
    return !!(this.game.machines && this.game.machines.powerOn);
  }

  _nearPlayer(r) {
    const p = this.game.player;
    return !!(p && p.pos && Math.hypot(p.pos.x - this.origin.x, p.pos.z - this.origin.z) < r);
  }
}
