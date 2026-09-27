// DEAD AIR — Telly, the living console TV (the mystery box, 950): GDD §10.2 entirely, §6.7 (lamp language), §18.10,
// §18.15. Owner: telly engineer. Builds Telly + its four homes, runs the pull, the glove, the sign-off relocation,
// percussive maintenance and the EE hooks.
//
// HOMES  telly_home_green (T1), telly_home_newsroom (T2), telly_home_studio_a (T3), telly_home_studio_b (T4)
//   Each home (layout anchor: Telly pos/rotY + couch + lamp) gets couch_avocado, telly_rug (dust footprint),
//   telly_lamp (light anchor `telly_lamp_<homeId>`) and telly_cord (src/props/machines.js), parented to its area
//   root (portal culled). The lamp is lit only where Telly lives (dim amber before power, full after, flickering
//   purple in the EE mood; a glowing shade + warm fx.lightPool on the floor, an unlit one looks dead); empty homes
//   show the clean dust rectangle and the unplugged cord. A 60 Hz hum loop (telly_hum, 12 m) follows Telly. Start
//   home: T1 or T2 (game.rand). The CRT spill (light anchor 'telly_screen' + floor pool) takes the colour of the
//   channel on screen.
// DRAW CALLS  ~38 for Telly + one home (legs/cord merged at rest, flat rug/cord cast no shadow, thin rods neither);
//   +12 while the glove presents (display model merged per material + one outline hull).
// SIZE  Telly stands SCALE (1.1x) bigger than the prop's modelling size (player feedback: its screen and cards must
//   read from gameplay distance). The root is scaled about its floor origin, so everything in prop space follows
//   (cabinet, legs, dial, antennas, glove reach + presentation point, the item diorama, screen, Zzz, local fx points);
//   the world-space parts are scaled by hand: collider, interact radius, melee reach test, bullet ray, CRT spill,
//   refund coin, relocation dot/line, waddle footprint, the dust footprint decal. Lamps that would now touch the
//   cabinet are eased sideways (see _buildHomes).
//
// PUBLIC API (game.telly)
//   homeId            current home anchor id (null while it is between homes)
//   state             'idle' | 'spinning' | 'offer' | 'moving'      phase: finer ('asleep','spin','land','bulge',
//                     'offer','take','timeout','signoff','bad', ...)   pulls (this game), pullsHere, pity
//   awake             true once the colour wave woke it (sleeps before power: prompt [E] 🔌)
//   pull({free}) -> bool   the 950 pull (what E does): spends, rolls the result FIRST, then choreographs the dial
//   take() -> bool          takes the presented item (what E does during the offer)
//   forceTapePull()         arms the EE step-5 tape pull: the next pull lands on the blank notch "0" and the glove
//                           pushes out the 2-inch quad reel (no timeout, no bump, no sign-off). egg:step {step:4}
//                           arms it automatically and sets the purple mood.
//   setMood('purple'|'normal')  EE step-4 hook: purple flickering lamp, constant shiver, Baron-face glitches.
//   onHit(info)             shootable handler: info.melee -> percussive maintenance / smack rules, bullets -> tink
//   tapeReel                the reel Object3D once taken (strapped to player.hero.slots.back); the egg may
//                           re-parent it (VTR #2). buildTapeReel(game) is exported for reuse.
//   canMove()               another home lies in an opened area (sign-offs need it)
// Interactable 'machine_telly' (interact.register): prompt {plug:true} asleep, {cost:950} idle, {} while the glove
//   offers (key only), null otherwise. Shootable 'machine_telly' via weapons.registerShootable (melee + bullets);
//   while weapons has no registerShootable, weapon:melee / weapon:fire are hit-tested here instead.
//
// EVENTS (GDD §18.15)
//   machine:telly_spin {homeId}                  machine:telly_result {result, channel}   result = item id |
//   machine:telly_bump {fromChannel, toChannel}     'signoff' | 'tape' | 'bad_reception' (bumped into snow, no move)
//   machine:telly_take {itemId}  (itemId 'ee_tape_reel' for the EE reel)   machine:telly_move {from, to}
//   weapon:acquire {source:'telly'} comes from weapons.give(id, {source:'telly'}).
//
// DEBUG  debugPull(outcome?, {free}) outcome = item id | 'signoff' | 'bad' | 'tape' (charges 950 when affordable)
//        debugBump() (melee smack now) · debugHit({melee}) · debugTake() · debugMove(homeId) · debugWake()
//        debugFreezeAt(t) (sets game.time.scale = 0 when the pull timeline reaches t; scale = 1 resumes)
//        debugState() -> JSON snapshot
// TESTS  node tools/scenarios/telly_build.mjs (private bundle) then sh tools/scenarios/telly_run.sh <name> "<params>":
//   pull     test=1&nozombies=1&god=1&doors=1&power=1&points=20000   E press, spin, land, bulge, glove, take, timeout
//   signoff  same                                                   relocation beat by beat, refund, lamps, event
//   bump     test=1&nozombies=1&god=1&power=1&points=40000          percussive maintenance rules, bop, tink, real V
//   ee       test=1&nozombies=1&god=1&doors=1&points=20000          plug prompt, real Sign-On wake, shiver, purple, tape
//   live     test=1&god=1&power=1&doors=1&points=30000&round=3      repeated pulls with live zombies
//   look / hull / perf / smoke                                      art review angles, outline, draw calls + timings

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { T, PAL } from '../core/config.js';
import { placeProp, buildProp } from '../props/index.js';
import * as K from '../props/kit.js';
import { setTellyLegs, setTellyGlove, updateTellyArm } from '../props/machines.js';
import { buildWeapon } from '../props/weapons.js';

export const TELLY_HOMES = ['telly_home_green', 'telly_home_newsroom', 'telly_home_studio_a', 'telly_home_studio_b'];

// ------------------------------------------------------------------------------------------------ constants
const TT = T.telly;
const COST = TT.cost;
const TAU = Math.PI * 2;
const CH_ITEM = Object.fromEntries(Object.entries(TT.channels).map(([ch, id]) => [Number(ch), id]));
const ITEM_CH = Object.fromEntries(Object.entries(CH_ITEM).map(([ch, id]) => [id, ch]));
const ITEMS = Object.keys(TT.weights);
const WONDER = new Set(['zapper', 'boom_mic', 'chroma_key']);
const SNOW = new Set(TT.snow);
const CYCLE = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
const CYCLE_EE = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0];
const DIAL_ORDER = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0];
const TAPE_ID = 'ee_tape_reel';

// Pull timeline (GDD §10.2 table). Detent intervals ease 0.07 -> 0.50 s over ~20 detents, first at 0.30, last at 4.30.
const SPIN = { t0: 0.30, dur: TT.spinTime - 0.30, iMin: 0.07, iMax: 0.50, pow: 2.6, want: 20, snowFlash: 0.06, zip: 0.15 };
const WINDOW = [TT.spinTime - TT.bumpWindow, TT.spinTime];          // percussive maintenance [3.30, 4.30)
const LAND = { jingle: 0.35, bulge: 0.60, bulgeDur: 0.40 };          // relative to the landing (4.30)
const OFFER = { out: 0.34, drum: 6, wag: 8, window: TT.window, tapeDrum: 4 };
// Sign-off beats relative to the landing. The GDD packs stand + shake + turn + a 2 s waddle + turn + wave into
// 2.5 s; here each beat keeps its own duration (power-off lands ~1.1 s later than 10.40).
const SO = { card: 0.6, gloveOut: 0.95, flick: 1.45, coin: 0.5, gloveIn: 2.05, stand: 3.25, shake: 3.6, turn: 4.0,
  walk: 4.3, walkDur: 2.0, turnBack: 6.3, wave: 6.55, off: 7.15, squash: 7.45, gone: 7.85, arrive: 9.15,
  unfold: 9.45, done: 10.3 };
const BAD = { gloveOut: 0.6, shrug: 0.9, flick: 1.75, coin: 0.5, gloveIn: 2.35, done: 2.9 };
const NEAR_WAKE = 6, NEAR_DOZE = 7.2, ZOMBIE_NEAR = 3;
const SCALE = 1.1;                                  // Telly's size vs the prop (uniform, applied on this.root)
const PIV = new THREE.Vector3(0.12, 0.9, -0.3);    // screen centre in prop space (collapse / unfold pivot)
const BOX = { x: 0.72, y0: 0, y1: 1.42, z: 0.38 }; // cabinet hit box (prop space)
// lamp shade vs cabinet (prop space: body half width with the pillowy bulge + lid overhang, half depth + lid)
const LAMP_CLEAR = { hw: 0.69, hd: 0.34, top: 1.44, shadeR: 0.37, shadeY0: 1.29, gap: 0.05 };
const GLOW_CRT = '#9FD8FF';
// CRT light spill per show (the room takes the colour of the channel on screen)
const CH_GLOW = { 2: '#8AA2FF', 4: '#FFB06A', 5: '#F48CFF', 7: '#86E08E', 8: '#FFC45C', 9: '#FFE26A', 11: '#B49CFF',
  12: '#FF7CD6', 13: '#7FE3FF' };
const KIND_GLOW = { face: GLOW_CRT, snow: '#D6E6FF', baron: '#C47BFF', test: '#EDEAFF', black: GLOW_CRT };
const ITEM_LIFT = 0.075;                            // presented item above the glove's hold point (m)

// ------------------------------------------------------------------------------------------------ helpers
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const lerp = (a, b, t) => a + (b - a) * t;
const easeOutCubic = (x) => 1 - Math.pow(1 - clamp01(x), 3);
const easeInCubic = (x) => clamp01(x) ** 3;
const easeInOut = (x) => { x = clamp01(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
const easeOutBack = (x, s = 1.9) => { x = clamp01(x) - 1; return 1 + (s + 1) * x * x * x + s * x * x; };
const easeInBack = (x, s = 1.7) => { x = clamp01(x); return (s + 1) * x * x * x - s * x * x; };
const easeOutElastic = (x) => { x = clamp01(x); return x === 0 || x === 1 ? x : Math.pow(2, -9 * x) * Math.sin((x * 8 - 0.75) * (TAU / 3)) + 1; };
const smooth = (x) => { x = clamp01(x); return x * x * (3 - 2 * x); };
const wrapPi = (a) => Math.atan2(Math.sin(a), Math.cos(a));

const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _v3 = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _m = new THREE.Matrix4();
const _o = new THREE.Vector3();
const _d = new THREE.Vector3();
const _zAxis = new THREE.Vector3(0, 0, 1);
const _c = new THREE.Color();
const _yAxis = new THREE.Vector3(0, 1, 0);

// Damped spring toward a target (sub-stepped: dt may be 1/20 s).
class Spring {
  constructor(k = 260, c = 15, x = 0) { this.k = k; this.c = c; this.x = x; this.v = 0; }
  kick(v) { this.v += v; }
  update(dt, target = 0) {
    const n = Math.max(1, Math.ceil(dt / (1 / 90)));
    const h = dt / n;
    for (let i = 0; i < n; i++) {
      this.v += (-this.k * (this.x - target) - this.c * this.v) * h;
      this.x += this.v * h;
    }
    return this.x;
  }
}

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
}

// ------------------------------------------------------------------------------------------------ screen
// Telly's own CRT compositor (384x288 canvas): face / show cards / snow / Baron / test card plus the effects the
// engine CRT shader has no knobs for (zipper wipe, vertical roll, zoom, CRT collapse to a line and a dot, the
// degauss unfold). Redraws only when its source redraws or an effect runs (<= 30 fps).
const SW = 384, SH = 288;
class TellyScreen {
  constructor(game) {
    this.game = game;
    this.canvas = canvas(SW, SH);
    this.ctx = this.canvas.getContext('2d');
    this.texture = new THREE.CanvasTexture(this.canvas);
    this.texture.colorSpace = THREE.SRGBColorSpace;
    this.texture.generateMipmaps = false;
    this.texture.minFilter = THREE.LinearFilter;
    this.prev = canvas(SW, SH);
    const cards = game.cards;
    this.face = cards.animated('telly_face', { owner: 'telly', expr: 'zzz', look: [0, 0] });
    this.snow = cards.animated('snow', { owner: 'telly' });
    this.baron = cards.animated('baron', { owner: 'telly' });
    this.noise = [0, 1, 2].map(() => {
      const c = canvas(96, 72), x = c.getContext('2d'), img = x.createImageData(96, 72);
      for (let i = 0; i < img.data.length; i += 4) {
        const v = Math.random() < 0.5 ? 20 + Math.random() * 60 : 150 + Math.random() * 105;
        img.data[i] = v; img.data[i + 1] = v; img.data[i + 2] = v + 8; img.data[i + 3] = 255;
      }
      x.putImageData(img, 0, 0);
      return c;
    });
    this.kind = 'face';
    this.ch = null;
    this.expr = 'zzz';
    this.look = [0, 0];
    this._lookT = 0;
    this.fx = { zip: -1, roll: -1, zoom: 1, collapse: -1, unfold: -1, flash: 0, noise: 0, dot: 0 };
    this.dirty = true;
    this._last = -1;
    this._srcCanvas = null;
  }

  // kind: 'face' | 'card' (ch) | 'snow' (ch?) | 'baron' | 'test' | 'black'
  show(kind, ch = null) {
    if (kind === this.kind && ch === this.ch) return;
    this.kind = kind;
    this.ch = ch;
    if (kind === 'snow') this.snow.set({ channel: ch ?? undefined });
    this.dirty = true;
  }

  setFace(expr, look, t) {
    let patch = null;
    if (expr !== this.expr) { this.expr = expr; patch = { expr }; }
    if (look && t - this._lookT > 1 / 12 && (Math.abs(look[0] - this.look[0]) > 0.04 || Math.abs(look[1] - this.look[1]) > 0.04)) {
      this.look = [Math.round(look[0] * 50) / 50, Math.round(look[1] * 50) / 50];
      this._lookT = t;
      patch = { ...(patch || {}), look: this.look };
    }
    if (patch) this.face.set(patch);
  }

  snapshot() {
    const x = this.prev.getContext('2d');
    x.clearRect(0, 0, SW, SH);
    x.drawImage(this.canvas, 0, 0);
  }

  _source(t) {
    const cards = this.game.cards;
    switch (this.kind) {
      case 'face': return [this.face.canvas, this.face.tick(t)];
      case 'snow': return [this.snow.canvas, this.snow.tick(t)];
      case 'baron': return [this.baron.canvas, this.baron.tick(t)];
      case 'card': return [cards.get(`show_${this.ch}`).image, false];
      case 'test': return [cards.get('test_card', { variant: 'sleepy' }).image, false];
      default: return [null, false];
    }
  }

  render(t) {
    const f = this.fx;
    const [src, redrew] = this._source(t);
    let dirty = this.dirty || redrew || src !== this._srcCanvas;
    const active = f.zip >= 0 || f.roll >= 0 || f.collapse >= 0 || f.unfold >= 0 || f.flash > 0.01 || f.noise > 0.01
      || Math.abs(f.zoom - 1) > 1e-3 || f.dot > 0.01;
    if (active && (t - this._last >= 1 / 30 || t < this._last)) dirty = true;
    if (!dirty) return false;
    this._last = t;
    this.dirty = false;
    this._srcCanvas = src;
    const ctx = this.ctx;
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#04060a';
    ctx.fillRect(0, 0, SW, SH);
    if (f.collapse >= 0) this._collapse(src, f.collapse);
    else if (f.unfold >= 0) this._unfold(src, f.unfold, t);
    else if (f.dot > 0.01) this._dot(f.dot, 1);
    else if (src) {
      this._draw(src, f.zoom, f.roll);
      if (f.zip >= 0) this._zip(f.zip);
      if (f.noise > 0.01) this._noise(f.noise);
      if (f.flash > 0.01) { ctx.globalAlpha = f.flash; ctx.fillStyle = '#F4FBFF'; ctx.fillRect(0, 0, SW, SH); ctx.globalAlpha = 1; }
    }
    this.texture.needsUpdate = true;
    return true;
  }

  _draw(src, zoom = 1, roll = -1) {
    const ctx = this.ctx;
    if (roll >= 0) {
      const off = Math.round((roll % 1) * SH);
      ctx.drawImage(src, 0, off, SW, SH);
      ctx.drawImage(src, 0, off - SH, SW, SH);
      ctx.fillStyle = '#020305';
      ctx.fillRect(0, off - 9, SW, 14);
      return;
    }
    const w = SW * zoom, h = SH * zoom;
    ctx.drawImage(src, (SW - w) / 2, (SH - h) / 2, w, h);
  }

  _noise(a) {
    const ctx = this.ctx;
    ctx.globalAlpha = Math.min(1, a);
    ctx.drawImage(this.noise[(Math.random() * 3) | 0], -Math.random() * 20, -Math.random() * 20, SW + 24, SH + 24);
    ctx.globalAlpha = 1;
  }

  _zip(z) {
    // the static band sweeps down: new content above it, the old picture below
    const ctx = this.ctx, y = Math.round(z * (SH + 30)) - 15;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, y, SW, SH - y);
    ctx.clip();
    ctx.drawImage(this.prev, 0, 0);
    ctx.restore();
    ctx.drawImage(this.noise[(Math.random() * 3) | 0], 0, 0, 96, 12, 0, y - 16, SW, 32);
    ctx.fillStyle = 'rgba(240,252,255,0.9)';
    ctx.fillRect(0, y + 14, SW, 3);
  }

  _dot(a, r = 1) {
    const ctx = this.ctx;
    ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createRadialGradient(SW / 2, SH / 2, 0, SW / 2, SH / 2, 26 * r);
    g.addColorStop(0, `rgba(255,255,255,${a})`);
    g.addColorStop(0.25, `rgba(200,245,255,${a * 0.8})`);
    g.addColorStop(1, 'rgba(120,220,255,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, SW, SH);
    ctx.globalCompositeOperation = 'source-over';
  }

  // CRT power-off: the picture squashes into a bright horizontal line, the line shrinks into a dot.
  _collapse(src, c) {
    const ctx = this.ctx;
    if (c < 0.5) {
      const u = c / 0.5, sy = lerp(1, 0.012, easeInCubic(u));
      if (src) ctx.drawImage(src, 0, (SH - SH * sy) / 2, SW, SH * sy);
      ctx.globalCompositeOperation = 'lighter';
      ctx.globalAlpha = u * 0.85;
      ctx.fillStyle = '#E8FAFF';
      ctx.fillRect(0, (SH - SH * sy) / 2, SW, SH * sy);
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = 'source-over';
    } else {
      const u = (c - 0.5) / 0.5, lw = (SW - 8) * (1 - easeInCubic(u)) + 8;
      ctx.save();
      ctx.shadowColor = '#7FE7FF';
      ctx.shadowBlur = 16;
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect((SW - lw) / 2, SH / 2 - 2.5, lw, 5);
      ctx.restore();
      if (u > 0.7) this._dot((u - 0.7) / 0.3, 0.8);
    }
  }

  // Degauss unfold: dot -> line -> picture, with rainbow fringes and a wobble that settles.
  _unfold(src, u, t) {
    const ctx = this.ctx;
    if (u < 0.2) { this._dot(u / 0.2, 0.3 + u * 3); return; }
    if (u < 0.42) {
      const w = SW * easeOutCubic((u - 0.2) / 0.22);
      ctx.save();
      ctx.shadowColor = '#7FE7FF';
      ctx.shadowBlur = 14;
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect((SW - w) / 2, SH / 2 - 2.5, w, 5);
      ctx.restore();
      return;
    }
    const k = (u - 0.42) / 0.58, sy = Math.max(0.02, easeOutBack(k, 1.4));
    const h = SH * Math.min(sy, 1.12);
    if (src) {
      const bands = 12, bh = SH / bands;
      for (let i = 0; i < bands; i++) {
        const wob = Math.sin(t * 40 + i * 1.3) * 16 * (1 - k);
        ctx.drawImage(src, 0, i * bh, SW, bh, wob, (SH - h) / 2 + (i * h) / bands, SW, h / bands + 1);
      }
    }
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.55 * (1 - k);
    const gr = ctx.createLinearGradient(0, 0, SW, SH);
    ['#FF3B30', '#F4E03A', '#52D24A', '#3FD6E0', '#3A58E4', '#D64FD6'].forEach((c, i) => gr.addColorStop(((i / 5) + t * 0.8) % 1, c));
    ctx.fillStyle = gr;
    ctx.fillRect(0, 0, SW, SH);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    if (k < 0.3) this._dot(1 - k / 0.3, 1.2);
  }
}

// ------------------------------------------------------------------------------------------------ materials
const HUE_GLSL = /* glsl */`vec3 hue(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }`;

// Soap-bubble membrane: the screen glass bulging outward into a wobbling dome (GDD §10.2, 4.90–5.30).
function bubbleMaterial(game, w, h) {
  return new THREE.ShaderMaterial({
    uniforms: {
      uBulge: { value: 0 }, uWobble: { value: 0 }, uAlpha: { value: 1 }, uTime: game.mats.uniforms.uTime,
      uSize: { value: new THREE.Vector2(w, h) },
    },
    vertexShader: /* glsl */`
      uniform float uBulge; uniform float uWobble; uniform float uTime; uniform vec2 uSize;
      varying vec3 vN; varying vec3 vView; varying vec2 vUv;
      void main() {
        vUv = uv;
        vec2 c = uv * 2.0 - 1.0;
        float wob = 1.0 + uWobble * 0.35 * sin(uTime * 23.0 + c.x * 6.0) * sin(uTime * 17.0 - c.y * 5.0);
        float amp = uBulge * wob;
        float w = max((1.0 - c.x * c.x) * (1.0 - c.y * c.y), 0.0);
        vec3 p = position;
        p.z += amp * pow(w, 0.6);
        float dw = 0.6 * pow(max(w, 2e-3), -0.4);
        float dx = amp * dw * (-2.0 * c.x) * (1.0 - c.y * c.y) * 2.0 / max(uSize.x, 1e-3);
        float dy = amp * dw * (-2.0 * c.y) * (1.0 - c.x * c.x) * 2.0 / max(uSize.y, 1e-3);
        vN = normalize(normalMatrix * normalize(vec3(-dx, -dy, 1.0)));
        vec4 mv = modelViewMatrix * vec4(p, 1.0);
        vView = -mv.xyz;
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: /* glsl */`
      uniform float uTime; uniform float uAlpha;
      varying vec3 vN; varying vec3 vView; varying vec2 vUv;
      ${HUE_GLSL}
      void main() {
        vec3 n = normalize(vN); vec3 v = normalize(vView);
        if (!gl_FrontFacing) n = -n;
        float ndv = clamp(abs(dot(n, v)), 0.0, 1.0);
        float fr = pow(1.0 - ndv, 1.6);
        vec2 c = vUv * 2.0 - 1.0;
        // thin-film interference: swirling colour bands that drift like a real soap film
        float swirl = 0.22 * sin(c.x * 5.0 + uTime * 1.7) * cos(c.y * 4.0 - uTime * 1.3) + 0.12 * sin((c.x + c.y) * 9.0 - uTime * 2.4);
        vec3 film = mix(vec3(1.0), hue(fr * 1.3 + swirl + length(c) * 0.45 - uTime * 0.2), 0.85);
        vec3 r = reflect(-v, n);
        // a soft window highlight (the studio key light) + a small hot glint + a rim sheen
        float s1 = pow(max(dot(r, normalize(vec3(-0.45, 0.7, 0.55))), 0.0), 60.0);
        float s2 = pow(max(dot(r, normalize(vec3(0.55, 0.4, 0.75))), 0.0), 14.0) * 0.35;
        float bands = 0.5 + 0.5 * sin((fr * 7.0 + swirl * 6.0) * 3.14159);
        float edge = smoothstep(1.0, 0.86, max(abs(c.x), abs(c.y)));
        vec3 col = film * (0.35 + fr * 1.6 + bands * 0.25) + vec3(s1 * 3.0 + s2);
        float a = clamp((0.14 + fr * 0.9 + bands * 0.08 + s1 + s2) * uAlpha, 0.0, 1.0);
        gl_FragColor = vec4(col, a * mix(0.4, 1.0, edge));
      }`,
    transparent: true, depthWrite: false, side: THREE.DoubleSide,
  });
}

// Inverted-hull outline for the presented item: warm white, or a rainbow shimmer for wonder weapons.
function hullMaterial(game) {
  return new THREE.ShaderMaterial({
    uniforms: {
      uThick: { value: 0.01 }, uColor: { value: new THREE.Color('#FFE7B8') }, uRainbow: { value: 0 },
      uGlow: { value: 1.15 }, uTime: game.mats.uniforms.uTime,
    },
    vertexShader: /* glsl */`
      uniform float uThick; varying vec3 vW;
      void main() {
        vec3 p = position + normalize(normal) * uThick;
        vec4 w = modelMatrix * vec4(p, 1.0);
        vW = w.xyz;
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: /* glsl */`
      uniform vec3 uColor; uniform float uRainbow; uniform float uGlow; uniform float uTime; varying vec3 vW;
      ${HUE_GLSL}
      void main() {
        vec3 rb = hue(fract(uTime * 0.55 + vW.y * 2.2 + (vW.x + vW.z) * 1.4)) * 1.15 + 0.12;
        vec3 c = mix(uColor, rb, uRainbow);
        float pulse = 0.82 + 0.18 * sin(uTime * 7.0 + vW.y * 9.0);
        gl_FragColor = vec4(c * uGlow * pulse, 1.0);
      }`,
    side: THREE.BackSide,
  });
}

function spriteTexture(draw, w = 64, h = 64) {
  const c = canvas(w, h);
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const zzzTexture = () => spriteTexture((x, W) => {
  x.lineJoin = 'round';
  x.lineCap = 'round';
  x.shadowColor = '#7FE7FF';
  x.shadowBlur = 8;
  x.strokeStyle = '#E6FDFF';
  x.lineWidth = 10;
  x.beginPath();
  x.moveTo(15, 15); x.lineTo(49, 15); x.lineTo(15, 49); x.lineTo(49, 49);
  x.stroke();
  x.shadowBlur = 0;
  x.globalCompositeOperation = 'destination-out';
  for (let i = 0; i < 160; i++) { x.fillStyle = `rgba(0,0,0,${0.25 + Math.random() * 0.6})`; x.fillRect(Math.random() * W, Math.random() * W, 2, 2); }
});
const dotTexture = () => spriteTexture((x, W) => {
  const g = x.createRadialGradient(W / 2, W / 2, 0, W / 2, W / 2, W / 2);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.18, 'rgba(235,252,255,1)');
  g.addColorStop(0.4, 'rgba(127,231,255,0.45)');
  g.addColorStop(1, 'rgba(127,231,255,0)');
  x.fillStyle = g;
  x.fillRect(0, 0, W, W);
});

// ------------------------------------------------------------------------------------------------ tape reel
// The EE 2-inch quad videotape reel: 0.36 m aluminium reel, gold tape pack, white label with a marker "13".
// Faces -z, centred at the origin (hub axis = z).
export function buildTapeReel(game) {
  const g = K.prop(TAPE_ID);
  const kc = { keepColor: true };
  const alu = K.mat(game, 'chrome', '#C9D1DB', kc);
  const tape = K.mat(game, 'plastic', '#C99532', { rough: 0.32, ...kc });
  const dark = K.mat(game, 'plastic', '#3A2C3E', kc);
  const label = K.mat(game, 'plastic', '#ffffff', { map: K.tex.canvas('ee_reel_label_v1', 256, 256, (ctx, W, H) => {
    ctx.fillStyle = '#F7F4EA';
    ctx.beginPath(); ctx.arc(W / 2, H / 2, W / 2, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#D9D2C0'; ctx.lineWidth = 6; ctx.stroke();
    ctx.strokeStyle = 'rgba(40,60,160,0.35)'; ctx.lineWidth = 2;
    for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.moveTo(40, 78 + i * 34); ctx.lineTo(216, 78 + i * 34); ctx.stroke(); }
    ctx.fillStyle = '#1B2A8A';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = 'bold 120px "Permanent Marker", "Comic Sans MS", "Titan One", sans-serif';
    ctx.save(); ctx.translate(W / 2, H / 2 + 6); ctx.rotate(-0.12); ctx.fillText('13', 0, 0); ctx.restore();
    ctx.font = '22px "Titan One", sans-serif';
    ctx.fillStyle = '#B5472A';
    ctx.fillText('SIGN-OFF', W / 2, 46);
  }, { repeat: false, fonts: true }), ...kc });
  const R = 0.18, gap = 0.056;
  const flange = new THREE.Shape();
  flange.absarc(0, 0, R, 0, TAU, false);
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * TAU + 0.3, hole = new THREE.Path();
    hole.absarc(Math.cos(a) * 0.105, Math.sin(a) * 0.105, 0.045, 0, TAU, true);
    flange.holes.push(hole);
  }
  for (const z of [-gap / 2, gap / 2]) g.add(K.m(K.extrude(flange, 0.007, { bevel: 0.002, curveSeg: 24 }), alu, { pos: [0, 0, z] }));
  g.add(K.m(K.cyl(0.15, 0.15, gap - 0.004, { bevel: 0.003, seg: 32 }), tape, { rot: [Math.PI / 2, 0, 0], pos: [0, 0, -(gap - 0.004) / 2] }));
  g.add(K.m(K.cyl(0.042, 0.042, gap + 0.03, { bevel: 0.006, seg: 20 }), alu, { rot: [Math.PI / 2, 0, 0], pos: [0, 0, -(gap + 0.03) / 2] }));
  g.add(K.m(K.cyl(0.016, 0.016, gap + 0.034, { bevel: 0.002, seg: 12 }), dark, { rot: [Math.PI / 2, 0, 0], pos: [0, 0, -(gap + 0.034) / 2] }));
  const lg = new THREE.CircleGeometry(0.068, 28).rotateY(Math.PI);
  g.add(K.m(lg, label, { pos: [0.1, -0.02, -gap / 2 - 0.0045], rot: [0, 0, 0] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0, strength: 0.6, res: 40 } });
}

// ------------------------------------------------------------------------------------------------ static bake
// Merges the visible meshes under `nodes` into one mesh per (material, castShadow), in `space`'s local frame, and
// adds them to `space` inside a group. Used for Telly's legs + cord at rest (16 draws -> 3); the originals stay
// for the animations (the caller toggles visibility). Returns the group (null when nothing merged).
function bakeStatic(nodes, space, name, { hide = false } = {}) {
  space.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(space.matrixWorld).invert();
  const lists = new Map();
  for (const n of nodes) {
    n.updateMatrixWorld(true);
    n.traverseVisible((o) => {
      if (!o.isMesh || o.isInstancedMesh || o.isSkinnedMesh || Array.isArray(o.material) || !o.geometry?.attributes?.position) return;
      const key = `${o.material.uuid}|${o.castShadow}`;
      if (!lists.has(key)) lists.set(key, []);
      lists.get(key).push(o);
    });
  }
  const grp = new THREE.Group();
  grp.name = name;
  const m4 = new THREE.Matrix4();
  for (const list of lists.values()) {
    try {
      const geos = list.map((o) => {
        const src = o.geometry;
        const g = new THREE.BufferGeometry();
        const n = src.attributes.position.count;
        const copy = (attr, size, fill) => {
          const out = new Float32Array(n * size);
          if (attr) for (let i = 0; i < n; i++) for (let k = 0; k < size; k++) out[i * size + k] = k < attr.itemSize ? attr.getComponent(i, k) : fill;
          else out.fill(fill);
          return new THREE.BufferAttribute(out, size);
        };
        g.setAttribute('position', copy(src.attributes.position, 3, 0));
        g.setAttribute('normal', copy(src.attributes.normal, 3, 0));
        g.setAttribute('uv', copy(src.attributes.uv, 2, 0));
        g.setAttribute('color', copy(src.attributes.color, 3, 1));
        g.setIndex(src.index ? Array.from(src.index.array) : Array.from({ length: n }, (_, i) => i));
        if (!src.attributes.normal) g.computeVertexNormals();
        g.applyMatrix4(m4.multiplyMatrices(inv, o.matrixWorld));
        return g;
      });
      const merged = mergeGeometries(geos, false);
      geos.forEach((x) => x.dispose());
      if (!merged) continue;
      merged.computeBoundingSphere();
      const mesh = new THREE.Mesh(merged, list[0].material);
      mesh.name = `baked:${list[0].material.name || 'mat'}`;
      mesh.castShadow = list[0].castShadow;
      mesh.receiveShadow = list[0].receiveShadow;
      mesh.userData.noOcclude = true;
      grp.add(mesh);
      if (hide) for (const o of list) o.visible = false;
    } catch (err) {
      console.warn('[telly] static bake skipped a material', err);
    }
  }
  if (!grp.children.length) return null;
  space.add(grp);
  return grp;
}

// One position+normal geometry of every mesh in `meshes`, in `space`'s frame (the inverted-hull outline of a whole
// display model in a single draw).
function mergedHullGeometry(meshes, space) {
  if (!meshes.length) return null;
  space.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(space.matrixWorld).invert();
  const m4 = new THREE.Matrix4();
  try {
    const geos = meshes.map((o) => {
      o.updateMatrixWorld(true);
      const src = o.geometry, n = src.attributes.position.count;
      const g = new THREE.BufferGeometry();
      const pos = new Float32Array(n * 3), nor = new Float32Array(n * 3);
      for (let i = 0; i < n; i++) {
        for (let k = 0; k < 3; k++) { pos[i * 3 + k] = src.attributes.position.getComponent(i, k); nor[i * 3 + k] = src.attributes.normal.getComponent(i, k); }
      }
      g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      g.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
      g.setIndex(src.index ? Array.from(src.index.array) : Array.from({ length: n }, (_, i) => i));
      g.applyMatrix4(m4.multiplyMatrices(inv, o.matrixWorld));
      return g;
    });
    const out = mergeGeometries(geos, false);
    geos.forEach((x) => x.dispose());
    if (out) out.computeBoundingSphere();
    return out;
  } catch (err) {
    console.warn('[telly] hull merge failed', err);
    return null;
  }
}

// ------------------------------------------------------------------------------------------------ Telly
export class Telly {
  constructor(game) {
    this.game = game;
    this.homeId = null;
    this.state = 'idle';
    this.phase = 'none';
    this.pulls = 0;
    this.pullsHere = 0;
    this.pity = 0;
    this.mood = 'normal';
    this.awake = false;
    this.homes = {};
    this.items = {};
    this.seq = null;
    this.tapeReel = null;
    this.built = false;
    this._tapeArmed = false;
    this._clock = 0;
    this._shootable = false;
    this._freezeAt = null;
    this._powerAt = -1;
  }

  // ============================================================================================ build
  init() {
    const g = this.game;
    if (!g.level || !g.level.anchors || !TELLY_HOMES.some((id) => g.level.anchors[id])) return;
    this._shootable = typeof g.weapons?.registerShootable === 'function';
    this._buildHomes();
    this._buildTelly();
    this._buildItems();
    this._register();
    this._listen();
    this.built = true;
    if (g.level.objects) g.level.objects.machine_telly = { group: this.root, parts: this.P, telly: this };
  }

  _buildHomes() {
    const g = this.game, lv = g.level;
    for (const id of TELLY_HOMES) {
      const a = lv.anchors[id];
      if (!a) continue;
      const area = a.area;
      const parent = lv.areaRoots?.[area] || g.scene;
      const grp = new THREE.Group();
      grp.name = `telly_home:${id}`;
      parent.add(grp);
      const rotY = a.rotY || 0;
      const fwd = new THREE.Vector3(-Math.sin(rotY), 0, -Math.cos(rotY));
      const fit = this._fitHome(a.pos.clone(), rotY, a.lamp?.pos || [a.pos.x + fwd.z * 1.2, 0, a.pos.z - fwd.x * 1.2]);
      const pos = fit.pos;
      if (a.couch) placeProp(g, grp, 'couch_avocado', { pos: a.couch.pos, rotY: a.couch.rotY ?? rotY + Math.PI, area });
      const rug = placeProp(g, grp, 'telly_rug', { pos: [pos.x, pos.y, pos.z], rotY, area, colliders: false });
      const lampId = `telly_lamp_${id}`;
      const lp = fit.lamp;
      const lamp = placeProp(g, grp, 'telly_lamp', { pos: lp, rotY: rotY + 0.5, area, opts: { anchorId: lampId, level: 1 } });
      // warm pool of light on the floor under the lit lamp (off = intensity 0)
      const pool = g.fx?.lightPool?.(new THREE.Vector3(lamp.position.x, 0.02, lamp.position.z), 1.7, '#FFD08A', 0) || null;
      // the unplugged cord runs from the wall outlet behind Telly into the room, beside the footprint
      const back = fwd.clone().negate();
      const hit = lv.col?.raycast(_o.set(pos.x, 0.3, pos.z), back, 3);
      const wallD = hit ? hit.dist : 0.75;
      const side = new THREE.Vector3(-fwd.z, 0, fwd.x);
      const cp = pos.clone().addScaledVector(back, wallD - 0.01).addScaledVector(side, 0.55);
      const cord = placeProp(g, grp, 'telly_cord', { pos: [cp.x, 0, cp.z], rotY, area, colliders: false });
      // flat floor dressing casts no shadow (saves the shadow-pass draws)
      for (const flat of [rug, cord]) flat.traverse((o) => { if (o.isMesh) o.castShadow = false; });
      // the clean footprint left in the dust matches the (scaled) cabinet's feet
      const dust = rug.userData.parts?.dust;
      if (dust) dust.scale.set(SCALE, 1, SCALE);
      // Telly's collision box at this home (enabled only where it lives)
      const colId = `telly_col_${id}`;
      const bb = new THREE.Box3();
      for (let i = 0; i < 8; i++) {
        _v.set(i & 1 ? BOX.x : -BOX.x, i & 2 ? BOX.y1 : BOX.y0, i & 4 ? BOX.z : -BOX.z).multiplyScalar(SCALE).applyAxisAngle(_yAxis, rotY).add(pos);
        bb.expandByPoint(_v);
      }
      lv.col?.addBox(bb.min.toArray(), bb.max.toArray(), { tag: 'telly', id: colId, walkable: false, shots: !this._shootable });
      lv.col?.setEnabled(colId, false);
      this.homes[id] = {
        id, area, group: grp, pos, rotY, fwd, rug, dust, lamp, lampId, cord, colId, pool,
        lampMode: 'off', lampShown: -1, flick: 0,
      };
    }
  }

  // The lamp stands beside Telly; its bell shade (y 1.29-1.72) hangs at the height of the cabinet's lid, which is taller
  // and wider once Telly is SCALE bigger. When the shade would touch the cabinet, first ease the lamp straight out
  // sideways (along Telly's width) just enough; if a wall leaves no room for that (a lamp tucked in a corner), Telly's
  // spot (and its rug, cord and collider with it) slides the other way instead. Returns { pos, lamp }.
  _fitHome(pos, rotY, lp) {
    const C = LAMP_CLEAR, col = this.game.level?.col;
    const out = { pos, lamp: lp };
    if (C.shadeY0 >= C.top * SCALE) return out;
    const rx = Math.cos(rotY), rz = -Math.sin(rotY);          // Telly's +x (width) in world
    const bx = Math.sin(rotY), bz = Math.cos(rotY);           // Telly's +z (back) in world
    const dx = lp[0] - pos.x, dz = lp[2] - pos.z;
    const lat = dx * rx + dz * rz, dep = dx * bx + dz * bz;
    const hw = C.hw * SCALE, hd = C.hd * SCALE, need = C.shadeR + C.gap;
    const gapDep = Math.max(0, Math.abs(dep) - hd);
    if (gapDep >= need) return out;
    const push = hw + Math.sqrt(need * need - gapDep * gapDep) - Math.abs(lat);
    if (push <= 0) return out;
    const s = Math.sign(lat) || 1;
    const room = (x, z, dirSign, reach) => {                   // free distance from (x, z) along ±width, 0.3-1.5 m up
      if (!col) return Infinity;
      let free = Infinity;
      for (const y of [0.3, 1.5]) {
        const hit = col.raycast(_o.set(x, y, z), _d.set(rx * dirSign, 0, rz * dirSign), reach + 0.3, { ignoreTags: ['telly'] });
        if (hit) free = Math.min(free, hit.dist);
      }
      return free;
    };
    const moved = [lp[0] + rx * s * push, lp[1] || 0, lp[2] + rz * s * push];
    if (room(moved[0], moved[2], s, C.shadeR) >= C.shadeR + 0.02) { out.lamp = moved; return out; }
    // no room for the lamp: slide Telly away from it, if the other side has the room
    if (room(pos.x, pos.z, -s, hw + push) >= hw + push + 0.05) out.pos = pos.clone().addScaledVector(_v.set(rx, 0, rz), -s * push);
    return out;
  }

  _buildTelly() {
    const g = this.game;
    const t = buildProp('telly', g, { card: 'telly_face', expr: 'zzz', channel: 13, pose: 'hidden' });
    this.g = t;
    this.P = t.userData.parts;
    this.rig = t.userData.rig;
    const P = this.P;
    this.root = new THREE.Group();
    this.root.name = 'machine_telly';
    this.root.scale.setScalar(SCALE);            // about the floor origin: the feet stay on the floor
    this.pivot = new THREE.Group();
    this.pivot.position.copy(PIV);
    this.root.add(this.pivot);
    this.pivot.add(t);
    t.position.copy(PIV).negate();
    g.scene.add(this.root);

    // screen: registered with the ScreenManager (scr_telly is never overridden) but composited here
    this.screen = new TellyScreen(g);
    const mat = P.screen.material;
    this.scrMat = mat;
    mat.uniforms.tScreen.value = this.screen.texture;
    mat.uniforms.uTexel.value.set(1 / SW, 1 / SH);
    const tex = this.screen.texture;
    Object.defineProperty(mat, 'map', { get: () => tex, set: () => {}, configurable: true });
    this.brightBase = mat.uniforms.uBright.value;
    g.screens?.register?.(P.screen, 'scr_telly', { id: 'telly' });

    // soap-bubble membrane in front of the glass
    const bw = this.rig.screen.w + 0.02, bh = this.rig.screen.h + 0.02;
    this.bubble = new THREE.Mesh(g.mats.screenGeometry(bw, bh), bubbleMaterial(g, bw, bh));
    this.bubble.rotation.y = Math.PI;
    this.bubble.position.set(this.rig.screen.center[0], this.rig.screen.center[1], P.glass.position.z - 0.004);
    this.bubble.visible = false;
    this.bubble.renderOrder = 3;
    this.bubble.frustumCulled = false;
    P.body.add(this.bubble);

    // glove poses (captured from the prop's preview poses) + custom ones
    const F = P.gloveFingers;
    const cap = () => ({
      pos: P.glove.position.clone(), quat: P.glove.quaternion.clone(), ctrl: P.armCtrl.position.clone(),
      f: [F.index.rotation.x, F.middle.rotation.x, F.pinky.rotation.x, F.thumb.rotation.x],
    });
    const poses = {};
    for (const name of ['present', 'fingerguns', 'wag']) {
      setTellyGlove(t, name);
      if (name === 'present') this._aimPresent(t);
      poses[name] = cap();
    }
    setTellyGlove(t, 'hidden');
    poses.hidden = { ...cap(), f: poses.present.f.slice() };
    const basis = (x, y, z) => new THREE.Quaternion().setFromRotationMatrix(_m.makeBasis(new THREE.Vector3(...x), new THREE.Vector3(...y), new THREE.Vector3(...z)));
    const P0 = poses.present;
    poses.reach = { pos: new THREE.Vector3(0.0, -0.05, -0.34), quat: P0.quat.clone(), ctrl: new THREE.Vector3(0, -0.06, -0.16), f: P0.f.slice() };
    poses.wave = { pos: new THREE.Vector3(0.02, 0.1, -0.46), quat: new THREE.Quaternion(), ctrl: new THREE.Vector3(0.02, -0.12, -0.22), f: [0.08, 0.08, 0.08, -0.25] };
    poses.shrug = { pos: new THREE.Vector3(0.0, 0.02, -0.5), quat: P0.quat.clone(), ctrl: new THREE.Vector3(0.04, -0.14, -0.25), f: [0.05, 0.05, 0.05, -0.1] };
    poses.coin = { pos: new THREE.Vector3(0.04, -0.02, -0.5), quat: P0.quat.clone(), ctrl: new THREE.Vector3(0.04, -0.14, -0.25), f: [-1.0, -1.1, -1.2, -0.2] };
    poses.bop = { pos: new THREE.Vector3(0.0, -0.08, -1.3), quat: basis([1, 0, 0], [0, 0, -1], [0, 1, 0]), ctrl: new THREE.Vector3(0.0, 0.1, -0.6), f: [-1.9, -2.0, -2.0, -1.3] };
    poses.catch = { pos: new THREE.Vector3(0.0, 0.0, -0.8), quat: new THREE.Quaternion(), ctrl: new THREE.Vector3(0.0, -0.1, -0.4), f: [-1.2, -1.3, -1.3, -0.9] };
    this.poses = poses;
    this.glove = { from: poses.hidden, to: poses.hidden, t: 1, dur: 0.3, ease: easeOutBack, on: false,
      wave: 0, wag: 0, drum: -1, shake: 0, flick: -1, hold: null };
    this._showGlove(false);

    // animated rest values
    // draw calls: legs (at rest) + cord merged into 3 meshes; thin antenna rods cast no shadow
    this.bakedLegs = bakeStatic([...P.legs, P.cord], P.body, 'telly_static_legs');
    if (this.bakedLegs) { for (const leg of P.legs) leg.visible = false; P.cord.visible = false; }
    this._legsBaked = !!this.bakedLegs;
    for (const ear of [P.earL, P.earR]) ear.traverse((o) => { if (o.isMesh) o.castShadow = false; });
    this.earRest = { L: P.earL.rotation.clone(), R: P.earR.rotation.clone() };
    this.ears = { L: new Spring(180, 7), R: new Spring(180, 7), droop: 0, droopT: 0 };
    this.squash = new Spring(320, 13, 1);
    this.hopY = 0;
    this.hop = null;
    this.prop = { spin: 0, angle: 0, settle: null };
    this.dial = { idx: DIAL_ORDER.indexOf(13), angle: P.dial.rotation.z, from: P.dial.rotation.z, to: P.dial.rotation.z, t: 1 };

    // Zzz particles, afterglow dot, refund coin
    const zmat = new THREE.SpriteMaterial({ map: zzzTexture(), transparent: true, depthWrite: false, color: '#DFFBFF' });
    this.zzz = [0, 1, 2].map(() => {
      const s = new THREE.Sprite(zmat);
      s.visible = false;
      s.userData.life = -1;
      this.root.add(s);
      return s;
    });
    this._zzzT = 0;
    this.dotSprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: dotTexture(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, color: '#ffffff' }));
    this.dotSprite.visible = false;
    this.dotSprite.renderOrder = 5;
    g.scene.add(this.dotSprite);
    const coinMat = g.mats.toon('#E8B84A', { rough: 0.25, metal: 0.85, keepColor: true, emissive: '#6A4A10', emissiveIntensity: 0.4 });
    this.coin = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.012, 20).rotateX(Math.PI / 2), coinMat);
    this.coin.scale.setScalar(SCALE);            // world-space prop held by the (scaled) glove
    this.coin.visible = false;
    g.scene.add(this.coin);
    this.coinFly = null;

    // CRT glow: pooled light anchor in front of the screen + a floor light pool
    this.glowAnchor = g.lights?.addAnchor?.({ pos: [0, -50, 0], color: GLOW_CRT, intensity: 0, distance: 3.2 * SCALE, id: 'telly_screen' }) || null;
    this.pool = g.fx?.lightPool?.(new THREE.Vector3(0, -50, 0), 1.2 * SCALE, GLOW_CRT, 0) || null;
    this._glowLevel = 0;

    // positional hum
    this.hum = g.audio?.loop?.('telly_hum', { pos: new THREE.Vector3(0, -50, 0), vol: 0 }) || null;
    this._audioPos = new THREE.Vector3();
  }

  // Moves the 'present' glove pose so the presented item floats exactly where GDD §10.2 puts it: 0.8 m in front of the
  // screen at 1.2 m height (rig.glove.presentWorld, prop space, legs at rest). The item rides ITEM_LIFT above the
  // glove's hold point. The arm control point follows so the tube keeps its curve.
  _aimPresent(t) {
    const P = this.P;
    const want = this.rig.glove?.presentWorld || [this.rig.screen.center[0], 1.2, -1.1];
    t.updateMatrixWorld(true);
    const hold = P.gloveHold.getWorldPosition(new THREE.Vector3());
    const target = new THREE.Vector3(want[0], want[1] - ITEM_LIFT, want[2]);
    t.localToWorld(target);
    const d = P.armRig.worldToLocal(target.clone()).sub(P.armRig.worldToLocal(hold.clone()));
    P.glove.position.add(d);
    P.armCtrl.position.addScaledVector(d, 0.5);
    updateTellyArm(t);
  }

  // Display models of every item (buildWeapon 'wall' pose: right side toward -z, barrel toward -x) + the EE reel.
  _buildItems() {
    const g = this.game;
    this.hullMats = { normal: hullMaterial(g), wonder: hullMaterial(g) };
    this.hullMats.wonder.uniforms.uRainbow.value = 1;
    this.hullMats.wonder.uniforms.uGlow.value = 1.45;
    for (const id of [...ITEMS, TAPE_ID]) {
      let model = null;
      try {
        model = id === TAPE_ID ? buildTapeReel(g) : buildWeapon(id, { pose: 'wall' }, g);
      } catch (err) {
        console.warn(`[telly] item model ${id} failed`, err);
        continue;
      }
      this.items[id] = this._wrapItem(id, model);
    }
  }

  _wrapItem(id, model) {
    const wrap = new THREE.Group();
    wrap.name = `telly_item:${id}`;
    const inner = new THREE.Group();
    wrap.add(inner);
    inner.add(model);
    model.updateMatrixWorld(true);
    const bb = new THREE.Box3().setFromObject(model);
    const size = bb.getSize(new THREE.Vector3());
    const c = bb.getCenter(new THREE.Vector3());
    model.position.sub(c);
    const sIn = Math.min(0.6 / size.x, 0.34 / size.y, 0.17 / Math.max(size.z, 1e-3), 1.7);
    // the EE reel is presented at its real 0.36 m size (GDD §13 step 5: undo Telly's SCALE); weapons are blown up to
    // read at 2 m (and grow with Telly)
    const sOut = id === TAPE_ID ? 1.0 / SCALE : Math.min(0.82 / size.x, 0.5 / size.y, 1.5);
    const wonder = WONDER.has(id) || id === TAPE_ID;
    // collect first, then add: adding the hull meshes inside traverse() would recurse into them forever
    const targets = [];
    model.traverse((o) => {
      if (!o.isMesh) return;
      o.castShadow = false;
      if (o.isInstancedMesh || o.isSkinnedMesh || !o.geometry?.attributes?.normal || o.material?.transparent) return;
      targets.push(o);
    });
    // draw calls: the display model merged per material (its parts never move) and ONE outline hull for all of it
    bakeStatic([model], inner, `telly_item_baked:${id}`, { hide: true });
    const hulls = [];
    const hullGeo = mergedHullGeometry(targets, inner);
    if (hullGeo) {
      const h = new THREE.Mesh(hullGeo, wonder ? this.hullMats.wonder : this.hullMats.normal);
      h.visible = false;
      h.frustumCulled = false;
      h.castShadow = false;
      h.userData.hull = true;
      inner.add(h);
      hulls.push(h);
    }
    wrap.visible = false;
    this.P.weaponSlot.add(wrap);
    return { id, wrap, inner, model, size, sIn, sOut, wonder, hulls };
  }

  _register() {
    const g = this.game;
    this.act = g.interact?.register?.({
      id: 'machine_telly', pos: [0, 0.9, 0], radius: 1.7 * SCALE,
      enabled: () => this.built && !!this.homeId && this.root.visible,
      prompt: () => this._prompt(),
      use: () => this._use(),
    }) || null;
    this._registerShootable();
  }

  _registerShootable() {
    const w = this.game.weapons;
    if (typeof w?.registerShootable !== 'function') { this._shootable = false; return; }
    w.unregisterShootable?.('machine_telly');
    w.registerShootable({
      id: 'machine_telly', blocksBullet: true, melee: true, bullets: true,
      raycast: (o, d, max) => this._raycast(o, d, max),
      onHit: (info) => this.onHit(info || {}),
    });
    this._shootable = true;
  }

  _listen() {
    const ev = this.game.events;
    ev.on('power:on', () => { this._powerAt = this._clock; });
    ev.on('egg:step', (e) => { if (e && e.step === 4) { this.setMood('purple'); this.forceTapePull(); } });
    // fallback hit tests while the weapons system has no shootables
    ev.on('weapon:melee', () => { if (!this._shootable && this._meleeReaches()) this.onHit({ melee: true }); });
    ev.on('weapon:fire', () => { if (!this._shootable) this._fallbackBullet(); });
  }

  // Throw-away samples compiled by game.precompile (materials only assigned later: the purple lamp).
  warmup() {
    if (!this.built) return null;
    const g = this.game, out = [];
    const geo = new THREE.BoxGeometry(0.1, 0.1, 0.1);
    for (const m of this._purpleMats(1)) out.push(new THREE.Mesh(geo, m));
    return out;
  }

  // ============================================================================================ lifecycle
  reset() {
    if (!this.built) return;
    const g = this.game;
    this._registerShootable();
    this._endSeq(true);
    this.pulls = 0;
    this.pullsHere = 0;
    this.pity = 0;
    this._tapeArmed = false;
    this._freezeAt = null;
    this.mood = 'normal';
    this.awake = false;
    this._wakeHop = false;
    this._powerAt = -1;
    this._near = false;
    this._nearT = 0;
    this._exprTemp = null;
    this._exprT = 0;
    this._zombieNear = false;
    this._zT = 0;
    this._smackT = 0;
    this._tinkT = 0;
    this._glitchT = 3;
    this._twitchT = 2;
    if (this.tapeReel) { this.tapeReel.removeFromParent(); this.tapeReel = null; }
    if (!this.items[TAPE_ID]) {
      try { this.items[TAPE_ID] = this._wrapItem(TAPE_ID, buildTapeReel(g)); } catch (err) { console.warn('[telly] tape reel', err); }
    }
    const start = g.rand() < 0.5 ? 'telly_home_green' : 'telly_home_newsroom';
    this._placeAt(this.homes[start] ? start : Object.keys(this.homes)[0]);
    for (const h of Object.values(this.homes)) h.lampMode = h.id === this.homeId ? 'dim' : 'off';
    this._applyLamps(true);
    this.phase = 'asleep';
    this.state = 'idle';
    if (g.nav?.built) g.nav.build();
  }

  update(dt) {
    if (!this.built) return;
    const g = this.game;
    this._clock += dt;
    const t = this._clock;
    this._updatePower(dt);
    this._updateProximity(dt);
    if (this.seq) this._updateSeq(dt);
    else this._updateIdle(dt);
    this._animate(dt, t);
    this._updateGlove(dt);
    this._updateItem(dt, t);
    this._updateScreen(dt, t);
    this._updateZzz(dt, t);
    this._updateLamps(dt, t);
    this._updateCoin(dt);
    this._updateAnchors(dt);
    this.state = !this.seq ? 'idle' : this.seq.phase === 'spin' || this.seq.phase === 'land' || this.seq.phase === 'bulge' ? 'spinning'
      : this.seq.phase === 'offer' || this.seq.phase === 'take' || this.seq.phase === 'timeout' ? 'offer' : this.seq.phase === 'bad' ? 'spinning' : 'moving';
  }

  // ============================================================================================ power / wake
  _updatePower() {
    const g = this.game;
    const on = !!g.machines?.powerOn;
    if (!on) {
      if (this.awake && !this.seq) { this.awake = false; this.phase = 'asleep'; this._lampModeHome('dim'); }
      return;
    }
    if (this.awake || !this.homeId) return;
    if (this._waveReached()) {
      this.awake = true;
      this.phase = 'idle';
      this._lampModeHome(this.mood === 'purple' ? 'purple' : 'full', true);
      this._hopNow(0.16);
      this._play('telly_wake', { vol: 1.1 });
      this._tempExpr('happy', 1.1);
      this._near = true;
      this._nearT = 0;
    }
  }

  _waveReached() {
    const g = this.game, pos = this.homes[this.homeId].pos;
    if (typeof g.signon?.waveReached === 'function') {
      try { return !!g.signon.waveReached(pos); } catch { /* fall through */ }
    }
    const u = g.mats.uniforms;
    if (u.uWaveRadius.value >= 0) return pos.distanceTo(u.uWaveOrigin.value) <= u.uWaveRadius.value;
    if (this._powerAt < 0) return true;                     // power already on (power=1, debug)
    const lever = g.level.anchors.sign_on_lever?.pos;
    return !lever || this._clock - this._powerAt >= pos.distanceTo(lever) / 15 - 0.05 || this._clock - this._powerAt > 3.5;
  }

  _updateProximity(dt) {
    const g = this.game, p = g.player;
    if (!this.homeId || !p) { this._pd = Infinity; return; }
    this._pd = Math.hypot(p.pos.x - this.root.position.x, p.pos.z - this.root.position.z);
    this._zT -= dt;
    if (this._zT <= 0) {
      this._zT = 0.25;
      let near = false;
      try { near = (g.zombies?.inRadius?.(this.root.position, ZOMBIE_NEAR, this._zList || (this._zList = [])) || []).length > 0; } catch { near = false; }
      if (this._zList) this._zList.length = 0;
      this._zombieNear = near;
    }
  }

  // idle life: doze / wake hops, antenna twitches, purple glitches
  _updateIdle(dt) {
    if (!this.homeId) return;
    this._twitchT -= dt;
    if (this._twitchT <= 0) {
      this._twitchT = 3 + Math.random() * 3;
      const s = Math.random() < 0.5 ? this.ears.L : this.ears.R;
      s.kick((Math.random() < 0.5 ? -1 : 1) * (this.awake ? 5 : 2.5));
    }
    if (!this.awake) return;
    const near = this._pd < (this._near ? NEAR_DOZE : NEAR_WAKE);
    if (near) {
      this._nearT = 0;
      if (!this._near) {
        this._near = true;
        this._hopNow(0.12);
        this._play('telly_wake');
        this._tempExpr('happy', 0.7);
      }
    } else if (this._near) {
      this._nearT += dt;
      if (this._nearT > 1.5) { this._near = false; this._tempExpr('sleepy', 1.8); }
    }
    if (this.mood === 'purple') {
      this._glitchT -= dt;
      if (this._glitchT <= 0) { this._glitchT = 4 + Math.random() * 2; this._tempExpr('baron_glitch', 0.3); }
    }
  }

  // ============================================================================================ interaction
  _prompt() {
    if (!this.homeId || !this.root.visible) return null;
    const s = this.seq;
    if (!s) {
      if (!this.game.machines?.powerOn || !this.awake) return { plug: true };
      return { cost: COST };
    }
    if (s.phase === 'offer' && s.u > OFFER.out * 0.6) return {};
    return null;
  }

  _use() {
    const s = this.seq;
    if (s) { if (s.phase === 'offer') this.take(); return; }
    if (!this.game.machines?.powerOn || !this.awake) {
      // asleep: a mumble and a wriggle, nothing else
      this._play('telly_nuh_uh', { vol: 0.55, rate: 0.8 });
      this.squash.kick(-1.2);
      return;
    }
    this.pull();
  }

  canPull() {
    return this.built && !!this.homeId && !this.seq && this.awake && !!this.game.machines?.powerOn && this.root.visible;
  }

  pull({ free = false, forced = null } = {}) {
    if (!this.canPull()) return false;
    const g = this.game;
    if (!free) {
      const eco = g.economy;
      if (!eco || !eco.spend(COST, 'telly')) {
        this.squash.kick(-2);
        this._tempExpr('pout', 0.8);
        return false;
      }
    }
    this.pulls++;
    this.pullsHere++;
    const r = this._roll(forced);
    const cycle = r.outcome === 'tape' ? CYCLE_EE : CYCLE;
    const start = this._dialCh();
    const L = cycle.length;
    let startPos = cycle.indexOf(start);
    if (startPos < 0) startPos = cycle.indexOf(13);
    const targetPos = cycle.indexOf(r.ch);
    const off = (((targetPos - startPos) % L) + L) % L;
    const N = [off + L, off + 2 * L].reduce((a, b) => (Math.abs(b - SPIN.want) < Math.abs(a - SPIN.want) ? b : a));
    const iv = [];
    let sum = 0;
    for (let j = 0; j < N - 1; j++) {
      const i = SPIN.iMin + (SPIN.iMax - SPIN.iMin) * Math.pow(j / Math.max(1, N - 2), SPIN.pow);
      iv.push(i);
      sum += i;
    }
    const times = [SPIN.t0];
    for (let j = 0; j < N - 1; j++) times.push(times[j] + (iv[j] * SPIN.dur) / sum);
    const seq = {
      phase: 'spin', t: 0, prev: -1, u: -1e-6, pu: -1,
      outcome: r.outcome, item: r.item, ch: r.ch, orig: { ...r },
      cost: free ? 0 : COST, cycle, startPos, N, times, passed: 0, shift: 0, landT: times[times.length - 1],
      bumped: false, cameo: r.outcome !== 'tape' && Math.random() < TT.cameo ? 6 + Math.floor(Math.random() * Math.max(1, N - 12)) : -1,
      shownCh: start, detT: -1, offerT: -1, took: false, drum: false, wag: false, refunded: false, dest: null,
      walk: null, arp: null, lastDetentCh: start,
    };
    this.seq = seq;
    this.phase = 'spin';
    g.events.emit('machine:telly_spin', { homeId: this.homeId });
    return true;
  }

  // Result first (GDD §10.2): tape > sign-off > weighted item (exclusions, pity).
  _roll(forced) {
    const g = this.game;
    if (this._tapeArmed || forced === 'tape') { this._tapeArmed = false; return { outcome: 'tape', item: TAPE_ID, ch: 0 }; }
    const snowCh = () => TT.snow[Math.floor(g.rand() * TT.snow.length) % TT.snow.length];
    if (forced === 'signoff' && this.canMove()) return { outcome: 'signoff', item: null, ch: snowCh() };
    if (forced === 'bad') return { outcome: 'bad', item: null, ch: snowCh() };
    if (forced && ITEM_CH[forced] !== undefined) return { outcome: 'item', item: forced, ch: Number(ITEM_CH[forced]) };
    const n = this.pullsHere;
    if (!forced && n > TT.moveSafe && this.canMove()) {
      const p = Math.min(TT.moveBase + TT.moveStep * (n - (TT.moveSafe + 1)), TT.moveCap);
      if (g.rand() < p) return { outcome: 'signoff', item: null, ch: snowCh() };
    }
    const pity = this.pity >= TT.pity;
    let total = 0;
    const pool = [];
    for (const id of ITEMS) {
      if (this._excluded(id)) continue;
      const w = TT.weights[id] * (pity && WONDER.has(id) ? TT.pityMul : 1);
      pool.push([id, w]);
      total += w;
    }
    let x = g.rand() * total, pick = pool.length ? pool[pool.length - 1][0] : 'revolver_38';
    for (const [id, w] of pool) { if ((x -= w) < 0) { pick = id; break; } }
    return { outcome: 'item', item: pick, ch: Number(ITEM_CH[pick]) };
  }

  _excluded(id) {
    const w = this.game.weapons;
    if (!w || !id) return false;
    if (id === 'tiny_tele') return (w.teles ?? 0) >= T.player.teleMax;
    if (typeof w.has === 'function' && w.has(id)) return true;
    return Array.isArray(w.slots) && w.slots.some((s) => s && s.id === id);
  }

  canMove() {
    return !!this._pickDestination(true);
  }

  _areaOpen(areaId) {
    const lv = this.game.level;
    if (areaId === 'lobby' || this.game.player?.area === areaId) return true;
    const a = lv.areas?.[areaId];
    return !!a?.doors?.some((d) => lv.doors?.[d]?.open);
  }

  _pickDestination(check = false) {
    const opts = Object.keys(this.homes).filter((id) => id !== this.homeId && this._areaOpen(this.homes[id].area));
    if (check) return opts.length > 0;
    if (!opts.length) return null;
    return opts[Math.floor(this.game.rand() * opts.length) % opts.length];
  }

  // ============================================================================================ smacks & bullets
  onHit(info = {}) {
    if (!this.built || !this.homeId || !this.root.visible) return;
    const g = this.game;
    const s = this.seq;
    if (!info.melee) {
      // bullets: "tink" and a glare
      if (this._clock - this._tinkT > 0.07) {
        this._tinkT = this._clock;
        this._play('smile_ting', { vol: 0.7, rate: 1.5 + Math.random() * 0.3, at: info.point });
        if (info.point) g.fx?.burst?.(info.point, { shape: 'spark', count: 5, speed: 3, size: 0.03, life: 0.2 });
      }
      if (!s || s.phase === 'spin' || s.phase === 'land') this._tempExpr('glare', 1.2);
      this.squash.kick(-0.4);
      return;
    }
    if (this._clock - this._smackT < 0.35) return;
    this._smackT = this._clock;
    if (s && s.phase === 'spin' && s.outcome === 'tape') return this._catchHand();
    if (s && s.phase === 'offer') return s.outcome === 'tape' ? this._catchHand() : this._bopBack();
    if (s && s.phase === 'spin' && !s.bumped && s.t >= WINDOW[0] && s.t < WINDOW[1]) return this._bump(s);
    if (!s || s.phase === 'spin' || s.phase === 'land') {
      this._play('telly_hey');
      this._tempExpr('glare', 1.4);
      this.squash.kick(-2.2);
      this._jolt(0.05);
      g.cam?.shake?.(0.08, 0.15);
    }
  }

  // Percussive maintenance (GDD §10.2 rules 1-6): one detent forward now, then resolve the landing.
  _bump(s) {
    const g = this.game;
    s.bumped = true;
    const fromCh = s.ch;            // the channel the dial was going to land on (GDD: "a 12 bumps to a 13")
    s.shift += 1;
    const L = s.cycle.length;
    let pos = s.startPos + s.N + s.shift;
    let ch = s.cycle[pos % L];
    let extra = 0;
    const toItem = () => {
      while (SNOW.has(ch) || this._excluded(CH_ITEM[ch])) { pos++; extra++; ch = s.cycle[pos % L]; }
    };
    if (s.outcome === 'signoff') { toItem(); s.outcome = 'item'; }               // rule 5: bumping cancels a sign-off
    else if (SNOW.has(ch)) s.outcome = this.canMove() ? 'signoff' : 'bad';      // rule 4
    else { toItem(); s.outcome = 'item'; }                                      // rule 3
    s.ch = ch;
    s.item = s.outcome === 'item' ? CH_ITEM[ch] : null;
    const last = s.times[s.times.length - 1];
    for (let i = 1; i <= extra; i++) s.times.push(last + 0.2 * i);
    s.landT = s.times[s.times.length - 1];
    // the jump itself: an extra-loud clack, "ow!", a vertical roll
    const nowCh = s.cycle[(s.startPos + s.passed + s.shift) % L];
    this._showDetent(s, nowCh, true);
    this._play('telly_clack', { vol: 1.9, rate: 0.8 });
    this._play('telly_clack_final', { vol: 0.9 });
    this._play('telly_ow', { vol: 1.1 });
    this.screen.fx.roll = 0;
    this._rollT = 0.3;
    this._tempExpr('glare', 0.3);
    this.squash.kick(-3.5);
    this._jolt(0.09);
    this.ears.L.kick(-7); this.ears.R.kick(7);
    g.cam?.shake?.(0.12, 0.2);
    g.fx?.burst?.(this._worldPoint(_v.set(0, 1.25, -0.1)), { shape: 'star', count: 6, speed: 2.6, size: 0.1, life: 0.6 });
    g.events.emit('machine:telly_bump', { fromChannel: fromCh, toChannel: ch });
  }

  _bopBack() {
    const g = this.game, s = this.seq, p = g.player;
    this._play('telly_nuh_uh', { vol: 1.1 });
    this._gloveTo('bop', 0.12, easeOutCubic);
    s.bopT = 0.32;
    if (p) {
      _v.set(p.pos.x - this.root.position.x, 0, p.pos.z - this.root.position.z).normalize().multiplyScalar(6).setY(2);
      p.knockback?.(_v);
    }
    g.cam?.shake?.(0.14, 0.22);
  }

  _catchHand() {
    const s = this.seq;
    this._play('telly_nuh_uh', { vol: 1.0 });
    if (s.phase === 'offer') { s.catchT = 1.1; this._gloveTo('catch', 0.12, easeOutCubic); }
    else this._tempExpr('glare', 0.8);
  }

  _meleeReaches() {
    const p = this.game.player;
    if (!p || !this.homeId || !this.root.visible) return false;
    p.forward?.(_d);
    _v.copy(p.pos);
    this.root.worldToLocal(_v);
    const dx = Math.max(Math.abs(_v.x) - BOX.x, 0), dz = Math.max(Math.abs(_v.z) - BOX.z, 0);
    const dist = Math.hypot(dx, dz) * SCALE;       // prop space -> metres (the player's reach does not grow)
    _v2.set(this.root.position.x - p.pos.x, 0, this.root.position.z - p.pos.z).normalize();
    return dist < 1.25 && _d.x * _v2.x + _d.z * _v2.z > 0.35;
  }

  _fallbackBullet() {
    const g = this.game, p = g.player;
    if (!p?.aimRay || !this.homeId || !this.root.visible) return;
    p.aimRay(_o, _d);
    const hit = this._raycast(_o, _d, 80);
    if (!hit) return;
    const wall = g.level.col.raycast(_o, _d, 80, { ignoreTags: ['telly'] });
    if (wall && wall.dist < hit.dist - 0.05) return;
    this.onHit({ melee: false, point: hit.point });
  }

  // ray vs the cabinet box (Telly local = prop space; the root is scaled by SCALE). The local direction is NOT
  // normalised, so the slab distances stay in world metres along `d`.
  _raycast(o, d, max = Infinity) {
    if (!this.built || !this.homeId || !this.root.visible || this.seq?.phase === 'gap') return null;
    this.root.updateMatrixWorld();
    _m.copy(this.root.matrixWorld).invert();
    const lo = _v3.copy(o).applyMatrix4(_m);
    const ld = _v2.copy(o).add(d).applyMatrix4(_m).sub(lo);
    const y1 = BOX.y1 + (this._legs || 0) * 0.4;
    let tmin = 0, tmax = max;
    for (const [oo, dd, a, b] of [[lo.x, ld.x, -BOX.x, BOX.x], [lo.y, ld.y, BOX.y0, y1], [lo.z, ld.z, -BOX.z, BOX.z]]) {
      if (Math.abs(dd) < 1e-8) { if (oo < a || oo > b) return null; continue; }
      let t1 = (a - oo) / dd, t2 = (b - oo) / dd;
      if (t1 > t2) [t1, t2] = [t2, t1];
      tmin = Math.max(tmin, t1);
      tmax = Math.min(tmax, t2);
      if (tmin > tmax) return null;
    }
    return { dist: tmin, point: new THREE.Vector3().copy(o).addScaledVector(d, tmin) };
  }

  // ============================================================================================ the pull sequence
  _phase(s, name) {
    s.phase = name;
    s.u = -1e-6;
    s.pu = -2e-6;
    this.phase = name;
  }

  _updateSeq(dt) {
    const s = this.seq, g = this.game;
    s.prev = s.t;
    s.t += dt;
    s.pu = s.u;
    s.u += dt;
    if (this._freezeAt !== null && s.prev < this._freezeAt && s.t >= this._freezeAt) {
      const back = s.t - this._freezeAt;
      s.t -= back;
      s.u = Math.max(0, s.u - back);
      g.time.scale = 0;
      this._freezeAt = null;
    }
    const hit = (x) => s.pu < x && s.u >= x;
    switch (s.phase) {
      case 'spin': this._seqSpin(s, hit); break;
      case 'land': this._seqLand(s, hit); break;
      case 'bulge': this._seqBulge(s, hit); break;
      case 'offer': this._seqOffer(s, hit); break;
      case 'take': this._seqTake(s, hit); break;
      case 'timeout': this._seqTimeout(s, hit); break;
      case 'signoff': this._seqSignoff(s, hit); break;
      case 'bad': this._seqBad(s, hit); break;
      default: break;
    }
  }

  _seqSpin(s, hit) {
    const u = s.u;
    if (hit(0)) {
      this._play('telly_ooh', { vol: 1.1 });
      this._hopNow(0.13, true);
      this._tempExpr('o_mouth', 0.5);
      this.screen.show('face');
    }
    if (hit(SPIN.zip)) {
      this.screen.snapshot();
      this.screen.fx.zip = 0;
      this._play('telly_zip');
    }
    if (u >= SPIN.zip) this.screen.fx.zip = u < SPIN.zip + 0.15 ? (u - SPIN.zip) / 0.15 : -1;
    if (hit(SPIN.t0)) {
      s.arp = this.game.audio?.play?.('telly_surf_arp', { pos: this._audio(), vol: 0.9 }) || null;
      this.prop.spin = 1;
      this.prop.settle = null;
    }
    while (s.passed < s.times.length && u >= s.times[s.passed]) {
      s.passed++;
      const ch = s.cycle[(s.startPos + s.passed + s.shift) % s.cycle.length];
      const final = s.passed === s.times.length;
      this._showDetent(s, ch, false, final);
    }
    // propellers slow in the last second
    if (u >= SPIN.t0) this.prop.spin = u < s.landT - 0.8 ? 1 : lerp(1, 0.25, (u - (s.landT - 0.8)) / 0.8);
    if (u >= s.landT && s.passed >= s.times.length) this._land(s);
  }

  // One detent: the dial clacks forward, 60 ms of snow, then the channel's card + its 3D item inside the cabinet.
  _showDetent(s, ch, bumped = false, final = false) {
    s.shownCh = ch;
    s.detT = s.u;
    s.detIdx = (s.detIdx || 0) + 1;
    s.cameoNow = s.passed === s.cameo;
    this._dialTo(ch, final ? 0.11 : 0.06);
    if (!final && !bumped) {
      this._play('telly_clack', { vol: 0.8 + Math.random() * 0.25, rate: 0.95 + Math.random() * 0.1 });
      s.arp?.step?.();
    }
    this.squash.kick(-0.9);
    if (s.cameoNow) this._play('baron_laugh', { vol: 0.45, rate: 1.45 });
    this._showItem(s.outcome === 'tape' || s.cameoNow ? null : CH_ITEM[ch] || null, 'pop');
  }

  _land(s) {
    const g = this.game;
    this._phase(s, s.outcome === 'signoff' ? 'signoff' : s.outcome === 'bad' ? 'bad' : 'land');
    s.arp?.stop?.(0.06);
    s.arp = null;
    this._play('telly_clack_final', { vol: 1.3 });
    this._play('telly_boing', { vol: 0.9 });
    this.prop.spin = 0;
    this.prop.settle = { from: this.P.antennas.rotation.y, to: Math.round(this.P.antennas.rotation.y / Math.PI) * Math.PI, t: 0 };
    this.ears.droop = 1;
    this.ears.droopT = 1.6;
    this.squash.kick(-4);
    s.shownCh = s.ch;
    if (s.outcome === 'item') { if (s.item && WONDER.has(s.item)) this.pity = 0; else this.pity++; }
    const result = s.outcome === 'bad' ? 'bad_reception' : s.outcome === 'item' ? s.item : s.outcome;
    g.events.emit('machine:telly_result', { result, channel: s.ch });
    if (s.outcome === 'tape') this._play('baron_laugh', { vol: 1.0 });
    if (s.outcome === 'signoff' || s.outcome === 'bad') {
      this._showItem(null);
      this._play('pu_expire', { vol: 0.9 });
      this._play('telly_zip', { vol: 1.2, rate: 0.55 });
    } else {
      this._showItem(s.item, 'pop');
    }
  }

  _seqLand(s, hit) {
    const g = this.game;
    this.screen.fx.zoom = 1 + 0.06 * smooth(s.u / LAND.jingle);
    if (hit(LAND.jingle) && s.outcome === 'item') {
      this._play(`jingle_${s.item}`, { vol: 1.1 });
      const it = this.items[s.item];
      if (it) it.pop = 1;
      const scr = this._worldPoint(_v.set(0.12, 0.9, -0.36));
      g.fx?.burst?.(scr, { shape: 'star', count: 10, speed: 2.8, size: 0.12, life: 0.9, dir: this._fwd(_v2), cone: 0.9 });
      if (WONDER.has(s.item)) {
        this._play('telly_wonder_tada', { vol: 1.1 });
        this._play('crowd_ooh', { vol: 0.8, delay: 0.15 });
        const grille = this._worldPoint(_v.set(-0.43, 0.35 + 0.335, -0.36));
        g.fx?.burst?.(grille, { shape: 'confetti', count: 36, speed: 4.2, size: 0.07, life: 1.6, dir: this._fwd(_v2).add(_v3.set(0, 1.1, 0)).normalize(), cone: 0.55 });
        g.fx?.burst?.(grille, { shape: 'star', count: 6, speed: 2.4, size: 0.12, life: 1 });
        this._tempExpr('happy', 0.1);
      }
    }
    if (hit(LAND.jingle) && s.outcome === 'tape') this.items[TAPE_ID] && (this.items[TAPE_ID].pop = 1);
    if (s.u >= LAND.bulge) {
      this.screen.fx.zoom = 1.06;
      this._phase(s, 'bulge');
      this._play('telly_bulge', { vol: 1.1 });
      this.P.glass.visible = false;
      this.bubble.visible = true;
      this.bubble.material.uniforms.uAlpha.value = 1;
    }
  }

  _seqBulge(s) {
    const k = s.u / LAND.bulgeDur;
    const U = this.bubble.material.uniforms;
    U.uBulge.value = 0.35 * easeOutBack(Math.min(1, k * 1.15), 2.4);
    U.uWobble.value = 0.6 + 0.4 * Math.sin(s.u * 30);
    if (s.outcome === 'tape') U.uWobble.value += 0.5;
    this.screen.fx.zoom = 1.06 - 0.06 * smooth(k);
    if (s.u >= LAND.bulgeDur) this._ploop(s);
  }

  _ploop(s) {
    const g = this.game;
    this._phase(s, 'offer');
    s.offerT = 0;
    this.bubble.visible = false;
    this.bubble.material.uniforms.uBulge.value = 0;
    this._play('telly_ploop', { vol: 1.2 });
    const tip = this._worldPoint(_v.set(0.12, 0.9, -0.32 - 0.35));
    g.fx?.burst?.(tip, { shape: 'spark', count: 16, speed: 3.6, size: 0.04, life: 0.3, colors: ['#FFFFFF', '#CFF6FF', '#FFD9F4'] });
    g.fx?.burst?.(tip, { shape: 'puff', count: 5, speed: 1.2, size: 0.12, life: 0.4, colors: ['#F4FBFF'] });
    g.fx?.burst?.(tip, { shape: 'star', count: 5, speed: 1.8, size: 0.09, life: 0.7 });
    this._showGlove(true);
    this._gloveTo('present', OFFER.out, easeOutBack);
    const it = this.items[s.item];
    if (it) {
      this.P.gloveHold.quaternion.copy(this.P.glove.quaternion).invert();
      this.P.gloveHold.updateMatrixWorld(true);
      this.P.gloveHold.attach(it.wrap);
      it.rot0 = it.wrap.rotation.y;
      it.mode = 'hold';
      it.holdFrom = it.wrap.position.clone();
      it.holdT = 0;
      for (const h of it.hulls) h.visible = true;
    }
    this.squash.kick(2.5);
  }

  _seqOffer(s, hit) {
    const tape = s.outcome === 'tape';
    if (s.bopT > 0) { s.bopT -= this.game.time.dt; if (s.bopT <= 0) this._gloveTo('present', 0.25, easeOutBack); }
    if (s.catchT > 0) {
      s.catchT -= this.game.time.dt;
      this.glove.wag = s.catchT < 0.8 ? 1 : 0;
      if (s.catchT <= 0) { this.glove.wag = 0; this._gloveTo('present', 0.25, easeOutBack); }
    }
    if (tape) {
      this.glove.shake = 1;
      const k = Math.floor(s.u / OFFER.tapeDrum);
      if (k >= 1 && k !== s.drumK) { s.drumK = k; this.glove.drum = 0; this._play('telly_drum'); }
      return;
    }
    if (hit(OFFER.drum)) { this.glove.drum = 0; this._play('telly_drum'); this._tempExpr('idle', 0.1); }
    if (hit(OFFER.drum + 0.5)) this._play('telly_drum', { rate: 1.05 });
    if (hit(OFFER.wag)) { this._gloveTo('wag', 0.25, easeOutBack); this.glove.wag = 1; this._play('telly_nuh_uh'); }
    if (hit(OFFER.wag + 1.3)) { this.glove.wag = 0; this._gloveTo('present', 0.3, easeOutBack); }
    if (s.u >= OFFER.window) {
      this._phase(s, 'timeout');
      this._gloveTo('reach', 0.3, easeInOut);
      this._play('telly_slurp');
    }
  }

  take() {
    const s = this.seq;
    if (!s || s.phase !== 'offer' || s.u < OFFER.out * 0.6) return false;
    const g = this.game;
    const it = this.items[s.item];
    if (s.outcome === 'tape') {
      this._giveTape(it);
    } else {
      const w = g.weapons;
      if (typeof w?.give === 'function') w.give(s.item, { source: 'telly' });
      else g.events.emit('weapon:acquire', { weaponId: s.item, upgraded: false, source: 'telly' });
      if (it) {
        for (const h of it.hulls) h.visible = false;
        const parent = this.root.parent || g.scene;
        parent.attach(it.wrap);
        it.mode = 'fly';
        it.flyT = 0;
        it.flyFrom = it.wrap.position.clone();
        it.flyScale = it.wrap.scale.x;
      }
    }
    g.events.emit('machine:telly_take', { itemId: s.item });
    s.took = true;
    this._phase(s, 'take');
    this._gloveTo('fingerguns', 0.18, easeOutBack);
    this.glove.drum = -1;
    this.glove.wag = 0;
    this.glove.shake = 0;
    this._play('costume_pop', { vol: 0.6 });
    return true;
  }

  _giveTape(it) {
    const g = this.game, p = g.player;
    if (!it) return;
    for (const h of it.hulls) h.visible = false;
    const back = p?.hero?.slots?.back;
    it.mode = 'gone';
    it.wrap.removeFromParent();
    const reel = it.wrap;
    this.items[TAPE_ID] = null;
    if (back) {
      back.add(reel);
      reel.position.set(0, 0.05, 0.09);
      reel.rotation.set(0, 0, 0.15);
      reel.scale.setScalar(0.9);
    } else {
      (this.root.parent || g.scene).add(reel);
      reel.visible = false;
    }
    reel.visible = true;
    reel.name = TAPE_ID;
    this.tapeReel = reel;
    this.setMood('normal');
  }

  _seqTake(s, hit) {
    const g = this.game;
    if (hit(0.02)) { this._play('telly_giggle', { delay: 0.25 }); this._tempExpr('wink', 1.6); this.rippleT = 0.9; }
    if (hit(0.55)) { this._gloveTo('hidden', 0.28, easeInBack); this._play('telly_slurp'); }
    if (hit(0.85)) this._showGlove(false);
    if (s.u >= 1.25) this._endSeq();
  }

  _seqTimeout(s, hit) {
    const it = this.items[s.item];
    if (hit(0.3)) this._gloveTo('hidden', 0.3, easeInBack);
    if (hit(0.62)) {
      this._showGlove(false);
      if (it) this._stowItem(it);
      this._tempExpr('pout', 2.2);
      this._play('telly_aww');
      this.rippleT = 0.6;
      this.squash.kick(-1.5);
    }
    if (s.u >= 1.4) this._endSeq();
  }

  // Sign-off: roaring snow, test card + lullaby + refund coin, stand up, waddle, CRT power-off, unfold elsewhere.
  _seqSignoff(s, hit) {
    const g = this.game, u = s.u;
    if (hit(SO.card)) {
      this._play('telly_lullaby', { vol: 1.1 });
      s.yawnT = 0;
    }
    if (hit(SO.gloveOut)) { this._showGlove(true); this._gloveTo('coin', 0.3, easeOutBack); this._coinInHand(true); }
    if (hit(SO.flick)) this._flickCoin(s);
    if (hit(SO.gloveIn)) this._gloveTo('hidden', 0.3, easeInBack);
    if (hit(SO.gloveIn + 0.32)) this._showGlove(false);
    if (hit(SO.stand)) this._play('telly_boing', { vol: 0.8, rate: 1.3 });
    if (u >= SO.stand && u < SO.stand + 0.5) this._legs = easeOutBack((u - SO.stand) / 0.32, 2.6);
    if (hit(SO.shake)) {
      this._play('jelly_bwoing', { vol: 0.5, rate: 1.4 });
      g.fx?.burst?.(this._worldPoint(_v.set(0, 1.3, 0)), { shape: 'puff', count: 6, speed: 1.6, size: 0.16, life: 0.6, colors: ['#E8DCCB', '#CFC3B0'] });
    }
    this._shake = u >= SO.shake && u < SO.turn ? 1 - (u - SO.shake) / (SO.turn - SO.shake) : 0;
    if (hit(SO.turn)) {
      const h = this.homes[this.homeId];
      if (h) {
        if (h.dust) h.dust.visible = true;
        g.level.col?.setEnabled?.(h.colId, false);
      }
      s.walk = this._walkPlan();
      s.walk.yaw0 = this.root.rotation.y;
    }
    if (s.walk && u >= SO.turn && u < SO.walk) this.root.rotation.y = s.walk.yaw0 + wrapPi(s.walk.yaw - s.walk.yaw0) * easeInOut((u - SO.turn) / (SO.walk - SO.turn));
    if (s.walk && u >= SO.walk && u < SO.walk + SO.walkDur) this._waddle(s, g.time.dt, u - SO.walk);
    if (s.walk && u >= SO.walk + SO.walkDur && !s.walkDone) { s.walkDone = true; this._waddleEnd(); }
    if (hit(SO.turnBack) && s.walk) s.walk.yaw1 = this.root.rotation.y;
    if (s.walk && u >= SO.turnBack && u < SO.wave) {
      const p = g.player, faceYaw = p ? Math.atan2(-(p.pos.x - this.root.position.x), -(p.pos.z - this.root.position.z)) : s.walk.yaw0;
      this.root.rotation.y = s.walk.yaw1 + wrapPi(faceYaw - s.walk.yaw1) * easeInOut((u - SO.turnBack) / (SO.wave - SO.turnBack));
    }
    if (hit(SO.wave)) { this._showGlove(true); this._gloveTo('wave', 0.2, easeOutBack); this.glove.wave = 1; this._play('telly_giggle', { rate: 0.9 }); }
    if (hit(SO.off - 0.15)) { this.glove.wave = 0; this._gloveTo('hidden', 0.14, easeInBack); }
    if (hit(SO.off)) {
      this._showGlove(false);
      s.dest = this._pickDestination() || this.homeId;
      g.events.emit('machine:telly_move', { from: this.homeId, to: s.dest });
      this._play('crt_power_off', { vol: 1.1 });
      this.screen.fx.collapse = 0;
    }
    if (u >= SO.off && u < SO.squash) this.screen.fx.collapse = Math.min(1, (u - SO.off) / (SO.squash - SO.off));
    if (hit(SO.squash)) {
      this.screen.fx.collapse = -1;
      this.screen.fx.dot = 1;
      this._play('telly_thwip', { vol: 1.1 });
      this._dotAt(this._worldPoint(_v.set(PIV.x, PIV.y, PIV.z - 0.08)));
    }
    if (u >= SO.squash && u < SO.gone) {
      const k = (u - SO.squash) / (SO.gone - SO.squash);
      const sx = Math.max(0.001, 1 - easeInBack(k, 1.4)), sy = Math.max(0.001, 1 - easeInBack(Math.min(1, k * 1.5), 1.2));
      this.pivot.scale.set(sx, sy, Math.max(0.001, sx));
      this.dotSprite.scale.setScalar((0.15 + 0.35 * k) * SCALE);
      this.dotSprite.material.opacity = 0.4 + 0.6 * k;
    }
    if (hit(SO.gone)) {
      const from = this.homes[this.homeId];
      this.root.visible = false;
      this._humVol(0);
      if (from) { from.lampMode = 'off'; from.flick = 0.15; if (from.cord) from.cord.visible = true; }
      this._play('light_thunk', { vol: 0.5, at: from ? _v.fromArray(from.lamp.position.toArray()).setY(1.5) : null });
      g.fx?.flashLight?.(this.dotSprite.position, '#CFF6FF', 3, 0.25);
      this.homeId = null;
    }
    if (u >= SO.gone && u < SO.arrive) {
      const k = (u - SO.gone) / (SO.arrive - SO.gone);
      this.dotSprite.material.opacity = Math.max(0, 1 - k * k);
      this.dotSprite.scale.setScalar(0.5 * SCALE * (1 - 0.6 * k) * (0.9 + 0.1 * Math.sin(u * 40)));
    }
    if (hit(SO.arrive)) {
      const to = this.homes[s.dest] ? s.dest : Object.keys(this.homes)[0];
      this._placeAt(to, { hidden: true });
      const h = this.homes[to];
      h.lampMode = this.mood === 'purple' ? 'purple' : 'full';
      h.flick = 0.6;
      this._play('onair_clack', { vol: 0.8, at: _v.copy(h.lamp.position).setY(1.5) });
      this._dotAt(this._worldPoint(_v.set(PIV.x, PIV.y, PIV.z - 0.08)));
      this.dotSprite.material.opacity = 0;
      this.pullsHere = 0;
    }
    if (u >= SO.arrive && u < SO.unfold) {
      const k = (u - SO.arrive) / (SO.unfold - SO.arrive);
      this.dotSprite.material.opacity = Math.min(1, k * 3);
      const w = k < 0.5 ? 0.12 + k * 0.4 : 0.32 + easeOutCubic((k - 0.5) / 0.5) * 0.9;
      this.dotSprite.scale.set(w * SCALE, (k < 0.5 ? 0.12 + k * 0.4 : Math.max(0.05, 0.32 - (k - 0.5) * 0.6)) * SCALE, 1);
    }
    if (hit(SO.unfold)) {
      this.root.visible = true;
      this.dotSprite.visible = false;
      this.pivot.scale.set(1, 0.01, 1);
      this.screen.fx.dot = 0;
      this.screen.fx.unfold = 0;
      this.screen.show('face');
      this._play('telly_bwong', { vol: 1.2 });
      this._humVol(1);
      g.fx?.flashLight?.(this._worldPoint(_v.set(PIV.x, PIV.y, PIV.z - 0.3)), '#BFF1FF', 4, 0.3);
      g.fx?.burst?.(this._worldPoint(_v.set(PIV.x, PIV.y, PIV.z - 0.2)), { shape: 'static', count: 14, speed: 2.2, size: 0.07, life: 0.6 });
    }
    if (u >= SO.unfold && u < SO.done) {
      const k = (u - SO.unfold) / 0.5;
      const sx = Math.min(1.25, easeOutElastic(Math.min(1, k * 1.6))), sy = Math.max(0.01, easeOutElastic(Math.max(0, k - 0.12) / 0.88));
      this.pivot.scale.set(k >= 1 ? 1 : sx, k >= 1 ? 1 : sy, k >= 1 ? 1 : sx);
      this.screen.fx.unfold = Math.min(1, (u - SO.unfold) / 0.65);
      if (this.screen.fx.unfold >= 1) this.screen.fx.unfold = -1;
    }
    if (hit(SO.unfold + 0.55)) { this._tempExpr('sleepy', 1.6); this._yawnT = 0; this._play('telly_aww', { vol: 0.5, rate: 0.75 }); }
    if (u >= SO.done) {
      this.pivot.scale.set(1, 1, 1);
      this.screen.fx.unfold = -1;
      g.level.col?.setEnabled?.(this.homes[this.homeId].colId, true);
      if (g.nav?.built) g.nav.build();
      this._near = false;
      this._endSeq();
    }
  }

  // "Bad reception": bumped into snow and nowhere to go. The glove comes out empty, shrugs, refunds 950.
  _seqBad(s, hit) {
    if (hit(BAD.gloveOut)) { this._showGlove(true); this._gloveTo('shrug', 0.3, easeOutBack); this._play('telly_nuh_uh', { rate: 0.85 }); this._tempExpr('o_mouth', 1.2); }
    this.glove.shrug = s.u >= BAD.shrug && s.u < BAD.flick - 0.15 ? 1 : 0;
    if (hit(BAD.flick - 0.15)) { this._gloveTo('coin', 0.15, easeOutCubic); this._coinInHand(true); }
    if (hit(BAD.flick)) this._flickCoin(s);
    if (hit(BAD.gloveIn)) this._gloveTo('hidden', 0.3, easeInBack);
    if (hit(BAD.gloveIn + 0.32)) this._showGlove(false);
    if (s.u >= BAD.done) this._endSeq();
  }

  _endSeq(hard = false) {
    const s = this.seq;
    if (s) s.arp?.stop?.(0.05);
    this.seq = null;
    this.phase = this.awake ? 'idle' : 'asleep';
    this._showGlove(false);
    this.glove.drum = -1; this.glove.wag = 0; this.glove.wave = 0; this.glove.shake = 0; this.glove.shrug = 0;
    this.bubble.visible = false;
    this.P.glass.visible = true;
    for (const it of Object.values(this.items)) if (it && it.mode !== 'gone') this._stowItem(it);
    this.screen.fx.zoom = 1;
    this.screen.fx.zip = -1;
    this.screen.fx.roll = -1;
    this.screen.fx.collapse = -1;
    this.screen.fx.unfold = -1;
    this.screen.fx.dot = 0;
    this.prop.spin = 0;
    this._legs = 0;
    this._shake = 0;
    if (hard) {
      this.pivot.scale.set(1, 1, 1);
      this.dotSprite.visible = false;
      this.coin.visible = false;
      this.coinFly = null;
      this.root.visible = true;
      this.ears.droop = 0;
    }
  }

  // ============================================================================================ coin, walk, dot
  _coinInHand(on) {
    this.coin.visible = on;
    this.coinFly = on ? { mode: 'hand' } : null;
  }

  _flickCoin(s) {
    const g = this.game;
    this.glove.flick = 0;
    this._play('telly_ploop', { vol: 0.4, rate: 1.8 });
    this.P.gloveHold.getWorldPosition(_v);
    this.coinFly = { mode: 'fly', t: 0, dur: 0.5, from: _v.clone(), refund: s.cost, s };
  }

  _updateCoin(dt) {
    const c = this.coinFly;
    if (!c) return;
    const g = this.game;
    if (c.mode === 'hand') {
      this.P.gloveHold.getWorldPosition(this.coin.position);
      this.coin.position.y += 0.06;
      this.coin.rotation.y += dt * 3;
      return;
    }
    c.t += dt;
    const k = clamp01(c.t / c.dur);
    const p = g.player;
    _v.copy(p ? p.pos : c.from).setY((p ? p.pos.y : 0) + 1.25);
    this.coin.position.lerpVectors(c.from, _v, k);
    this.coin.position.y += Math.sin(k * Math.PI) * 0.9;
    this.coin.rotation.x += dt * 24;
    this.coin.rotation.y += dt * 5;
    if (k >= 1) {
      this.coin.visible = false;
      this.coinFly = null;
      const eco = g.economy;
      if (c.refund > 0 && eco && !c.s.refunded) {
        c.s.refunded = true;
        const mul = eco.multiplier || 1;
        const got = eco.add(c.refund / mul, 'telly_refund');
        if (typeof eco.earned === 'number' && got > 0) eco.earned -= got;   // a refund is not earned points
      }
      this._play('telly_coin', { vol: 1.1, at: _v });
      g.fx?.burst?.(_v, { shape: 'star', count: 6, speed: 2, size: 0.08, life: 0.6, colors: [PAL.marqueeGold, '#FFF3B0'] });
    }
  }

  _walkPlan() {
    const g = this.game, lv = g.level;
    const h = this.homes[this.homeId];
    const area = lv.areas?.[h?.area];
    let best = null, bd = Infinity;
    for (const id of area?.doors || []) {
      const d = lv.doors?.[id];
      if (!d?.pos) continue;
      const dist = Math.hypot(d.pos.x - this.root.position.x, d.pos.z - this.root.position.z);
      if (dist < bd) { bd = dist; best = d.pos; }
    }
    const dir = best ? new THREE.Vector3(best.x - this.root.position.x, 0, best.z - this.root.position.z).normalize() : h.fwd.clone();
    return { dir, yaw: Math.atan2(-dir.x, -dir.z), max: best ? Math.max(0, bd - 1.2 * SCALE) : 2.4, moved: 0, pos: this.root.position.clone(), step: 0 };
  }

  _waddle(s, dt, w) {
    const walk = s.walk;
    const g = this.game;
    this.root.rotation.y = walk.yaw;
    // same gait at the bigger size: stride speed and footprint scale with Telly
    const speed = 1.2 * SCALE * smooth(w / 0.2) * (1 - smooth((w - SO.walkDur + 0.2) / 0.2));
    const step = Math.min(speed * dt, Math.max(0, walk.max - walk.moved));
    if (step > 0 && dt > 0) {
      _d.copy(walk.dir).multiplyScalar(step);
      const before = walk.pos.clone();
      if (g.level.col?.moveCircle) g.level.col.moveCircle(walk.pos, _d, 0.5 * SCALE, 1.4 * SCALE, 0.1);
      else walk.pos.add(_d);
      walk.pos.y = 0;
      walk.moved += before.distanceTo(walk.pos);
      this.root.position.x = walk.pos.x;
      this.root.position.z = walk.pos.z;
    }
    const ph = w * 2.6 * TAU / 2;
    this._waddlePh = ph;
    const k = Math.floor(w * 5.2);
    if (k !== walk.step) { walk.step = k; this._play('telly_clonk', { vol: 0.9, rate: k & 1 ? 1.08 : 0.94 }); }
  }

  _waddleEnd() {
    this._waddlePh = null;
  }

  _dotAt(p) {
    this.dotSprite.position.copy(p);
    this.dotSprite.visible = true;
    this.dotSprite.scale.setScalar(0.15 * SCALE);
    this.dotSprite.material.opacity = 1;
  }

  // ============================================================================================ placement
  _placeAt(homeId, { hidden = false } = {}) {
    const g = this.game, h = this.homes[homeId];
    if (!h) return;
    const parent = g.level.areaRoots?.[h.area] || g.scene;
    if (this.root.parent !== parent) parent.add(this.root);
    this.root.position.copy(h.pos);
    this.root.rotation.set(0, h.rotY, 0);
    this.root.visible = !hidden;
    this.pivot.scale.set(1, 1, 1);
    this.homeId = homeId;
    this._legs = 0;
    setTellyLegs(this.g, 0);
    for (const o of Object.values(this.homes)) {
      const here = o.id === homeId;
      if (o.dust) o.dust.visible = !here;
      if (o.cord) o.cord.visible = !here;
      g.level.col?.setEnabled?.(o.colId, here && !hidden);
    }
    this.root.updateMatrixWorld(true);
    this._humVol(hidden ? 0 : 1);
    if (this.act) this.act.pos.copy(this._worldPoint(_v.set(0.12, 0.9, -0.55)));
  }

  _humVol(v) {
    if (!this.hum) return;
    this.hum.setPos?.(this.root.position);
    this.hum.setVol?.(v * (this.awake ? 0.9 : 0.5), 0.4);
  }

  // ============================================================================================ animation
  _hopNow(height = 0.12, big = false) {
    this.hop = { t: 0, h: height, big };
    this.squash.kick(big ? -5 : -3);
  }

  _jolt(a) { this._joltT = 0.25; this._joltA = a; }

  _tempExpr(expr, sec) { this._exprTemp = expr; this._exprT = sec; }

  _dialTo(ch, dur) {
    const D = this.dial;
    const bi = DIAL_ORDER.indexOf(ch);
    if (bi < 0) return;
    const steps = (((bi - D.idx) % 13) + 13) % 13;
    D.idx = bi;
    D.from = this.P.dial.rotation.z;
    D.to = D.angle = D.angle + steps * (TAU / 13);
    D.t = 0;
    D.dur = dur;
  }

  _dialCh() { return DIAL_ORDER[this.dial.idx]; }

  _animate(dt, t) {
    const P = this.P;
    const s = this.seq;
    // hop (anticipation squash, stretch in the air, land squash)
    let hy = 0;
    if (this.hop) {
      const H = this.hop;
      H.t += dt;
      const pre = 0.08, air = H.big ? 0.36 : 0.3;
      if (H.t < pre) this.squash.x = lerp(this.squash.x, 0.86, 0.5);
      else if (H.t < pre + air) {
        const k = (H.t - pre) / air;
        hy = 4 * H.h * k * (1 - k);
        if (k < 0.5) this.squash.x = lerp(this.squash.x, 1.1, 0.35);
      } else {
        this.squash.kick(-3);
        this.hop = null;
      }
    }
    const sq = this.squash.update(dt, 1);
    const breathe = this.seq ? 0 : 0.01 * (1 + Math.sin(t * TAU * 0.4));
    const sy = Math.max(0.5, sq) * (1 + breathe);
    const sxz = 1 / Math.sqrt(Math.max(0.5, sq));
    this.g.scale.set(sxz, sy, sxz);
    this.g.position.y = -PIV.y + hy;
    // shiver (zombies near, purple mood) / jolt / wet-dog shake / waddle
    const shiver = !s && this.awake && (this._zombieNear || this.mood === 'purple') ? 1 : 0;
    let rz = 0, rx = 0, px = 0;
    if (shiver) { px += Math.sin(t * 57) * 0.007; rz += Math.sin(t * 43) * 0.012; }
    if (this._joltT > 0) { this._joltT -= dt; rz += Math.sin(this._joltT * 60) * this._joltA * (this._joltT / 0.25); }
    if (this._shake > 0) { rz += Math.sin(t * 58) * 0.16 * this._shake; px += Math.sin(t * 47) * 0.02 * this._shake; }
    if (this._waddlePh != null) { rz += Math.sin(this._waddlePh) * 0.11; rx += 0.05; hy += Math.abs(Math.sin(this._waddlePh)) * 0.035; this.g.position.y += Math.abs(Math.sin(this._waddlePh)) * 0.035; }
    this.g.rotation.set(rx, 0, rz);
    this.g.position.x = -PIV.x + px;
    // yawn: slow stretch up
    if (this._yawnT != null || (s && s.yawnT != null)) {
      const yt = s && s.yawnT != null ? (s.yawnT += dt) : (this._yawnT += dt);
      if (yt < 1.4) this.g.scale.y *= 1 + 0.07 * Math.sin(Math.min(1, yt / 1.4) * Math.PI);
      else if (s && s.yawnT != null) s.yawnT = null; else this._yawnT = null;
    }
    // legs telescope (sign-off) + waddle feet
    const legT = this._legs || 0;
    setTellyLegs(this.g, Math.min(1.15, legT));
    if (this._legsBaked) {
      const rest = legT <= 0.001 && this._waddlePh == null;
      if (this.bakedLegs.visible !== rest) {
        this.bakedLegs.visible = rest;
        for (const leg of P.legs) leg.visible = !rest;
        P.cord.visible = !rest;
      }
    }
    if (this._waddlePh != null) {
      P.legs.forEach((leg, i) => {
        const foot = leg.getObjectByName(leg.userData.footName);
        if (foot) foot.position.y += Math.max(0, Math.sin(this._waddlePh + (i % 2) * Math.PI)) * 0.05;
      });
    }
    // dial snap with overshoot
    const D = this.dial;
    if (D.t < 1) {
      D.t = Math.min(1, D.t + dt / Math.max(0.02, D.dur || 0.06));
      P.dial.rotation.z = D.from + (D.to - D.from) * easeOutBack(D.t, 2.2);
    }
    // antennas: propellers during the spin, droop at the landing, twitches
    const pr = this.prop;
    if (pr.spin > 0) P.antennas.rotation.y += dt * TAU * 2 * pr.spin;
    else if (pr.settle) {
      pr.settle.t += dt / 0.45;
      P.antennas.rotation.y = pr.settle.from + (pr.settle.to - pr.settle.from) * easeOutBack(pr.settle.t, 2);
      if (pr.settle.t >= 1) pr.settle = null;
    }
    const E = this.ears;
    if (E.droopT > 0) { E.droopT -= dt; if (E.droopT <= 0) E.droop = 0; }
    E.dCur = lerp(E.dCur || 0, E.droop, 1 - Math.exp(-dt * (E.droop ? 14 : 3)));
    const eL = E.L.update(dt, 0), eR = E.R.update(dt, 0);
    const spinSplay = pr.spin > 0 ? 0.35 * pr.spin : 0;
    P.earL.rotation.set(this.earRest.L.x + E.dCur * 0.35 + eL * 0.04, 0, this.earRest.L.z - E.dCur * 0.85 - spinSplay + eL * 0.06);
    P.earR.rotation.set(this.earRest.R.x + E.dCur * 0.35 + eR * 0.04, 0, this.earRest.R.z + E.dCur * 0.85 + spinSplay + eR * 0.06);
    if (this._waddlePh != null) { P.earL.rotation.z += Math.sin(this._waddlePh) * 0.2; P.earR.rotation.z += Math.sin(this._waddlePh) * 0.2; }
    // screen ripple after a take / timeout
    const U = this.scrMat.uniforms;
    if (this.rippleT > 0) {
      this.rippleT -= dt;
      U.uWobble.value = clamp01(this.rippleT / 0.6);
      U.uBulge.value = 0.03 + 0.05 * clamp01(this.rippleT / 0.6);
    } else { U.uWobble.value = 0; U.uBulge.value = 0.03; }
  }

  // Glove: pose blending + procedural layers (wave, wag, drum, shake, shrug, thumb flick). Arm tube rebuilt each frame.
  _showGlove(on) {
    const P = this.P;
    this.glove.on = on;
    P.glove.visible = on;
    P.arm.visible = on;
    P.glass.visible = !on && !this.bubble?.visible;
    if (!on) {
      const hp = this.poses?.hidden;
      if (hp) { P.glove.position.copy(hp.pos); P.glove.quaternion.copy(hp.quat); P.armCtrl.position.copy(hp.ctrl); }
      this.glove.to = this.glove.from = this.poses?.hidden || this.glove.to;
      this.glove.t = 1;
    }
  }

  _gloveTo(name, dur = 0.3, ease = easeOutBack) {
    const G = this.glove;
    const P = this.P, F = P.gloveFingers;
    G.from = {
      pos: P.glove.position.clone(), quat: P.glove.quaternion.clone(), ctrl: P.armCtrl.position.clone(),
      f: [F.index.rotation.x, F.middle.rotation.x, F.pinky.rotation.x, F.thumb.rotation.x],
    };
    G.to = this.poses[name] || this.poses.present;
    G.t = 0;
    G.dur = dur;
    G.ease = ease;
    G.name = name;
  }

  _updateGlove(dt) {
    const G = this.glove;
    if (!G.on) return;
    const P = this.P, F = P.gloveFingers;
    G.t = Math.min(1, G.t + dt / Math.max(0.01, G.dur));
    const k = G.ease(G.t);
    const kq = clamp01(k);
    P.glove.position.lerpVectors(G.from.pos, G.to.pos, k);
    P.glove.quaternion.slerpQuaternions(G.from.quat, G.to.quat, kq);
    P.armCtrl.position.lerpVectors(G.from.ctrl, G.to.ctrl, k);
    const fl = [0, 1, 2, 3].map((i) => lerp(G.from.f[i], G.to.f[i], kq));
    const t = this._clock;
    // procedural layers
    if (G.wave) { _q.setFromAxisAngle(_zAxis, Math.sin(t * 16) * 0.45); P.glove.quaternion.premultiply(_q); }
    if (G.wag) { _q.setFromAxisAngle(_zAxis, Math.sin(t * 22) * 0.35); P.glove.quaternion.premultiply(_q); }
    if (G.shrug) {
      _q.setFromAxisAngle(_zAxis, Math.sin(t * 7) * 0.3);
      P.glove.quaternion.premultiply(_q);
      P.glove.position.y += Math.abs(Math.sin(t * 7)) * 0.04;
    }
    if (G.shake) { P.glove.position.x += (Math.random() - 0.5) * 0.012; P.glove.position.y += (Math.random() - 0.5) * 0.012; }
    if (G.drum >= 0) {
      G.drum += dt;
      const d = G.drum;
      for (let i = 0; i < 3; i++) fl[i] += -0.9 * Math.max(0, Math.sin((d * 9 - i * 0.7) * Math.PI)) * (d < 1.4 ? 1 : 0);
      if (d > 1.5) G.drum = -1;
    }
    if (G.flick >= 0) {
      G.flick += dt;
      fl[3] += -1.2 * Math.sin(Math.min(1, G.flick / 0.25) * Math.PI);
      if (G.flick > 0.3) G.flick = -1;
    }
    if (!this.seq || this.seq.phase === 'offer') {
      P.glove.position.y += Math.sin(t * 2.4) * 0.012;
    }
    F.index.rotation.x = fl[0];
    F.middle.rotation.x = fl[1];
    F.pinky.rotation.x = fl[2];
    F.thumb.rotation.x = fl[3];
    P.gloveHold.quaternion.copy(P.glove.quaternion).invert();
    updateTellyArm(this.g);
  }

  // The item: floats inside the cabinet, pushes into the bubble, rides the glove, flies to the player.
  _showItem(id, fx = null) {
    for (const it of Object.values(this.items)) {
      if (!it || it.mode === 'gone') continue;
      const on = it.id === id;
      if (it.mode === 'hold' || it.mode === 'fly') continue;
      it.wrap.visible = on;
      if (on && fx === 'pop') it.pop = Math.max(it.pop || 0, 0.6);
    }
    this._shownItem = id;
  }

  _stowItem(it) {
    for (const h of it.hulls) h.visible = false;
    if (it.wrap.parent !== this.P.weaponSlot) this.P.weaponSlot.add(it.wrap);
    it.wrap.position.set(0, 0, 0);
    it.wrap.quaternion.identity();
    it.wrap.scale.setScalar(it.sIn);
    it.wrap.visible = false;
    it.mode = 'in';
    it.pop = 0;
  }

  _updateItem(dt, t) {
    const s = this.seq;
    const glScale = this.P.glove.scale.x || 1;
    for (const it of Object.values(this.items)) {
      if (!it || it.mode === 'gone') continue;
      const w = it.wrap;
      if (it.mode === 'hold') {
        it.holdT += dt;
        const k = easeOutCubic(it.holdT / 0.3);
        w.position.lerpVectors(it.holdFrom, _v.set(0, ITEM_LIFT / glScale, -0.02 / glScale), k);
        const sc = lerp(it.sIn * 1.08, it.sOut, k) / glScale;
        w.scale.setScalar(sc);
        w.rotation.set(0, (it.rot0 || 0) + it.holdT * TAU, 0);
        if (it.hulls.length) {
          const mat = it.hulls[0].material;
          mat.uniforms.uThick.value = (it.wonder ? 0.0085 : 0.0065) / Math.max(0.2, sc * glScale);
        }
        if (s && s.phase === 'timeout' && s.u > 0.3) {
          w.scale.multiplyScalar(Math.max(0.05, 1 - (s.u - 0.3) / 0.32));
        }
        continue;
      }
      if (it.mode === 'fly') {
        it.flyT += dt;
        const k = clamp01(it.flyT / 0.22);
        const p = this.game.player;
        _v.copy(p ? p.pos : it.flyFrom).setY((p ? p.pos.y : 0) + 1.1);
        w.position.lerpVectors(it.flyFrom, _v, easeInCubic(k));
        w.scale.setScalar(it.flyScale * (1 - 0.8 * k));
        w.rotation.y += dt * 12;
        if (k >= 1) {
          this.game.fx?.burst?.(_v, { shape: 'star', count: 7, speed: 2.2, size: 0.09, life: 0.5 });
          this._play('smile_ting', { vol: 0.6, rate: 1.2, at: _v });
          this._stowItem(it);
        }
        continue;
      }
      if (!w.visible) continue;
      // inside the cabinet
      it.pop = Math.max(0, (it.pop || 0) - dt * 4);
      const bob = Math.sin(t * 2.2 + it.id.length) * 0.012;
      let z = 0, sc = it.sIn * (1 + 0.18 * it.pop * it.pop);
      if (s && s.phase === 'bulge') {
        const k = easeOutCubic(s.u / LAND.bulgeDur);
        z = -0.36 * k;
        sc *= 1 + 0.08 * k;
      }
      // each detent opens with 60 ms of snow: the item pops in only once the card is up
      const flash = s && s.phase === 'spin' && s.u >= SPIN.t0 && s.u - s.detT < SPIN.snowFlash;
      w.position.set(0, bob, z);
      w.scale.setScalar(flash ? 1e-4 : sc);
      const spinning = s && s.phase === 'spin';
      w.rotation.set(0, spinning ? Math.sin(t * 3) * 0.25 : Math.sin(t * 0.9) * 0.45, Math.sin(t * 1.3) * 0.04);
    }
  }

  // ============================================================================================ screen
  _updateScreen(dt, t) {
    const S = this.screen, s = this.seq;
    const U = this.scrMat.uniforms;
    if (this._rollT > 0) { this._rollT -= dt; S.fx.roll = 1 - clamp01(this._rollT / 0.3); if (this._rollT <= 0) S.fx.roll = -1; }
    if (this._exprT > 0) { this._exprT -= dt; if (this._exprT <= 0) this._exprTemp = null; }
    let bright = this.brightBase;
    let noise = 0;
    if (!s) {
      let expr;
      if (!this.awake) { expr = 'zzz'; bright *= 0.55; }
      else if (this._exprTemp) expr = this._exprTemp;
      else if (this._zombieNear || this.mood === 'purple') expr = 'shiver';
      else expr = this._near ? 'idle' : 'zzz';
      if (this._exprTemp === 'baron_glitch') noise = 0.25;
      S.show('face');
      S.setFace(expr, expr === 'idle' ? this._gaze(dt) : null, t);
    } else {
      switch (s.phase) {
        case 'spin': {
          if (s.u < SPIN.zip) { S.show('face'); S.setFace('o_mouth', null, t); }
          else if (s.u < SPIN.t0) S.show('snow');
          else if (s.outcome === 'tape' || s.cameoNow) S.show(s.u - s.detT < SPIN.snowFlash ? 'snow' : 'baron');
          else if (s.u - s.detT < SPIN.snowFlash) S.show('snow', s.shownCh);
          else if (SNOW.has(s.shownCh)) S.show('snow', s.shownCh);
          else S.show('card', s.shownCh);
          if (s.u >= SPIN.t0) bright *= 1 + 0.25 * Math.max(0, 1 - (s.u - s.detT) / 0.12);
          break;
        }
        case 'land': case 'bulge': case 'offer':
          S.show(s.outcome === 'tape' ? 'baron' : 'card', s.ch);
          if (s.phase === 'land' && s.u < 0.12) bright *= 1.35;
          break;
        case 'take': case 'timeout':
          if (s.phase === 'take' ? s.u < 0.05 : s.u < 0.62) S.show(s.outcome === 'tape' ? 'baron' : 'card', s.ch);
          else { S.show('face'); S.setFace(this._exprTemp || 'idle', this._gaze(dt), t); }
          break;
        case 'signoff': {
          if (s.u < SO.card) { S.show('snow', s.ch); noise = 0.55 * (1 - s.u / SO.card); bright *= 1.2; }
          else if (s.u < SO.unfold) S.show('test');
          else { S.show('face'); S.setFace(this._exprTemp || 'sleepy', null, t); }
          break;
        }
        case 'bad':
          if (s.u < BAD.gloveOut) { S.show('snow', s.ch); noise = 0.5 * (1 - s.u / BAD.gloveOut); }
          else { S.show('face'); S.setFace(this._exprTemp || 'pout', null, t); }
          break;
        default: break;
      }
    }
    S.fx.noise = noise;
    if (this.mood === 'purple' && !s && Math.random() < 0.01) bright *= 0.6;
    U.uBright.value = lerp(U.uBright.value, bright, 1 - Math.exp(-dt * 25));
    // redraw only when someone can see it (area rendered, within 40 m)
    const areaVis = this.root.parent?.visible !== false;
    if (this.root.visible && areaVis && this._pd < 40) S.render(t);
  }

  _gaze(dt) {
    const p = this.game.player;
    if (!p) return [0, 0];
    _v.copy(p.pos).setY(p.pos.y + 1.55);
    this.root.worldToLocal(_v);
    const dx = _v.x - PIV.x, dy = _v.y - PIV.y, dz = _v.z - PIV.z;
    const fwd = Math.max(0.5, -dz);
    const tx = THREE.MathUtils.clamp(-dx / fwd, -1, 1);
    const ty = THREE.MathUtils.clamp(-dy / Math.hypot(fwd, dx) * 1.4, -1, 1);
    const L = this._look || (this._look = [0, 0]);
    const a = 1 - Math.exp(-dt * 8);
    L[0] = lerp(L[0], tx, a);
    L[1] = lerp(L[1], ty, a);
    return L;
  }

  _updateZzz(dt, t) {
    const dozing = !this.seq && this.root.visible && (!this.awake || (!this._near && !this._exprTemp && !this._zombieNear && this.mood !== 'purple'));
    this._zzzT -= dt;
    if (dozing && this._zzzT <= 0 && this._pd < 25) {
      this._zzzT = 1.1;
      const z = this.zzz.find((s) => s.userData.life < 0);
      if (z) { z.userData.life = 0; z.userData.x = (Math.random() - 0.5) * 0.08; z.visible = true; }
    }
    for (const z of this.zzz) {
      if (z.userData.life < 0) continue;
      z.userData.life += dt / 2.4;
      const k = z.userData.life;
      if (k >= 1) { z.userData.life = -1; z.visible = false; continue; }
      z.position.set(-0.32 + z.userData.x + Math.sin(k * 7) * 0.05 - k * 0.12, 1.36 + k * 0.55, -0.05);
      const sc = 0.07 + 0.1 * k;
      z.scale.set(sc, sc, 1);
      z.material.opacity = Math.min(1, k * 5) * (1 - k);
      z.material.rotation = Math.sin(k * 5) * 0.3;
    }
  }

  // ============================================================================================ lamps & lights
  _lampModeHome(mode, flick = false) {
    const h = this.homes[this.homeId];
    if (!h) return;
    h.lampMode = mode;
    if (flick) h.flick = 0.5;
  }

  setMood(mood = 'normal') {
    this.mood = mood === 'purple' ? 'purple' : 'normal';
    const h = this.homes[this.homeId];
    if (h && this.awake) h.lampMode = this.mood === 'purple' ? 'purple' : 'full';
    if (h && this.mood === 'purple') h.flick = 0.4;
    this._glitchT = 2;
  }

  forceTapePull() {
    this._tapeArmed = true;
    return true;
  }

  _purpleMats(level) {
    const g = this.game;
    const q = Math.round(clamp01(level) * 4) / 4;
    return [
      K.glow(g, '#B45CFF', 0.8 + 3 * q),
      K.glow(g, '#E3AEFF', 0.25 + 0.9 * q),
      K.mat(g, 'fabric', '#ffffff', { map: K.tex.weave('#9A5AD0', { pattern: 'plain', scale: 3 }), side: THREE.DoubleSide, emissive: '#B040FF', emissiveIntensity: 0.55 * q }),
    ];
  }

  // Warm lamp (lamp language, GDD §6.7): a lit shade must read from across the room (glowing parchment + bloom), an
  // unlit one must look dead (dull, darker fabric, grey bulb). Quantised levels keep the material count tiny.
  _warmMats(level) {
    const g = this.game;
    const q = Math.round(clamp01(level) * 20) / 20;
    if (q <= 0) {
      return [
        K.mat(g, 'ceramic', '#CFC6B4'),
        K.mat(g, 'fabric', '#6E5530'),
        K.mat(g, 'fabric', '#ffffff', { map: K.tex.weave('#BE9442', { pattern: 'plain', scale: 3 }), side: THREE.DoubleSide }),
      ];
    }
    const warm = q < 0.6 ? PAL.gelAmber : PAL.tungsten;
    return [
      K.glow(g, warm, 1.2 + 4 * q),
      K.glow(g, '#FFD9A0', 0.35 + 1.25 * q),
      K.mat(g, 'fabric', '#ffffff', { map: K.tex.weave('#F2C45A', { pattern: 'plain', scale: 3 }), side: THREE.DoubleSide, emissive: q < 0.6 ? '#FF8A30' : '#FFA850', emissiveIntensity: 0.95 * q }),
    ];
  }

  _applyLamps(force = false) {
    for (const h of Object.values(this.homes)) this._applyLamp(h, force);
  }

  _applyLamp(h, force = false, level = null) {
    const g = this.game;
    const target = level ?? (h.lampMode === 'full' || h.lampMode === 'purple' ? 1 : h.lampMode === 'dim' ? 0.35 : 0);
    const key = `${h.lampMode}:${Math.round(target * 20)}`;
    if (!force && key === h.lampShown) return;
    h.lampShown = key;
    const purple = h.lampMode === 'purple';
    const [bulb, lining, shade] = purple ? this._purpleMats(target) : this._warmMats(target);
    const P = h.lamp.userData.parts || {};
    if (P.bulb) P.bulb.material = bulb;
    if (P.lining) P.lining.material = lining;
    if (P.shade) P.shade.material = shade;
    h.lamp.userData.lampLevel = target;
    if (purple) g.lights?.setAnchor?.(h.lampId, { color: '#A54CFF', intensity: 2.2 * target, flicker: 0.5 });
    else g.lights?.setAnchor?.(h.lampId, { color: target < 0.6 ? PAL.gelAmber : PAL.tungsten, intensity: 2.0 * target, flicker: 0 });
    h.pool?.set?.({ color: purple ? '#B45CFF' : target < 0.6 ? '#FFB060' : '#FFD08A', intensity: (purple ? 0.34 : 0.3) * target });
  }

  _updateLamps(dt, t) {
    for (const h of Object.values(this.homes)) {
      if (h.flick > 0) {
        h.flick -= dt;
        const on = Math.sin(h.flick * 70) > -0.2 || h.flick < 0.05;
        const base = h.lampMode === 'off' ? 0 : h.lampMode === 'dim' ? 0.35 : 1;
        this._applyLamp(h, false, h.lampMode === 'off' ? (on ? 0.5 : 0) : on ? base : base * 0.15);
        if (h.flick <= 0) this._applyLamp(h, true);
      } else if (h.lampMode === 'purple') {
        const k = 0.55 + 0.45 * (Math.sin(t * 13) * Math.sin(t * 7.3) > 0.1 ? 1 : 0.4);
        this._applyLamp(h, false, Math.round(k * 4) / 4);
      } else this._applyLamp(h);
    }
  }

  _updateAnchors(dt) {
    const g = this.game;
    const s = this.seq;
    const vis = this.root.visible && !!this.homeId;
    let level = 0;
    if (vis) {
      level = this.awake ? 0.7 : 0.18;
      if (s && s.phase === 'spin' && s.u >= SPIN.t0) level = 1.2 + 0.6 * Math.max(0, 1 - (s.u - s.detT) / 0.15);
      else if (s && (s.phase === 'land' || s.phase === 'bulge' || s.phase === 'offer')) level = 1.3;
      else if (s && s.phase === 'signoff' && s.u >= SO.off) level = 0;
    }
    this._glowLevel = lerp(this._glowLevel, level, 1 - Math.exp(-dt * 12));
    // spill colour follows what is on screen (snappy on detents, soft otherwise)
    const S = this.screen;
    const want = S.kind === 'card' ? CH_GLOW[S.ch] || GLOW_CRT : KIND_GLOW[S.kind] || GLOW_CRT;
    const gc = this._glowCol || (this._glowCol = new THREE.Color(GLOW_CRT));
    gc.lerp(_c.set(want), 1 - Math.exp(-dt * (s && s.phase === 'spin' ? 30 : 8)));
    this._worldPoint(_v.set(0.12, 0.9, -0.85));
    if (this.glowAnchor) {
      this.glowAnchor.pos.copy(_v);
      if (this.glowAnchor.area !== undefined) this.glowAnchor.area = this.homes[this.homeId]?.area ?? this.glowAnchor.area;
      g.lights.setAnchor('telly_screen', { intensity: this._glowLevel * 1.1, color: gc });
    }
    if (this.pool) this.pool.set({ pos: _v2.set(_v.x, 0.02, _v.z), intensity: this._glowLevel * 0.22, color: gc });
    if (this.act && vis && !s) this.act.pos.copy(this._worldPoint(_v.set(0.12, 0.9, -0.55)));
    if (this.hum && vis) this.hum.setPos?.(this.root.position);
  }

  // ============================================================================================ utils
  _worldPoint(local) {
    this.root.updateMatrixWorld();
    return local.applyMatrix4(this.root.matrixWorld);
  }

  _fwd(out) {
    const y = this.root.rotation.y;
    return out.set(-Math.sin(y), 0, -Math.cos(y));
  }

  _audio() {
    return this._worldPoint(this._audioPos.set(0.12, 0.9, -0.3)).clone();
  }

  _play(id, o = {}) {
    const a = this.game.audio;
    if (!a?.play) return null;
    const { at, ...rest } = o;
    try { return a.play(id, { pos: at ? at.clone() : this._audio(), ...rest }); } catch { return null; }
  }

  // ============================================================================================ debug
  debugPull(outcome = null, { free = false } = {}) {
    if (!this.built) return false;
    if (!this.awake && this.game.machines?.powerOn) this.debugWake();
    const pay = !free && (this.game.economy?.points ?? 0) >= COST;
    return this.pull({ free: !pay, forced: outcome });
  }

  debugBump() { this._smackT = -1; this.onHit({ melee: true }); return this.seq ? { bumped: this.seq.bumped, outcome: this.seq.outcome, item: this.seq.item, ch: this.seq.ch } : null; }

  debugHit(info = { melee: true }) { this._smackT = -1; this.onHit(info); return true; }

  debugTake() { return this.take(); }

  debugWake() {
    if (!this.homeId) return false;
    this._powerAt = -1;
    if (!this.awake) {
      this.awake = true;
      this.phase = 'idle';
      this._lampModeHome(this.mood === 'purple' ? 'purple' : 'full', true);
      this._hopNow(0.16);
      this._play('telly_wake');
      this._tempExpr('happy', 1);
    }
    return true;
  }

  debugMove(homeId) {
    if (!this.homes[homeId] || this.seq) return false;
    const from = this.homes[this.homeId];
    if (from) from.lampMode = 'off';
    this._placeAt(homeId);
    this.homes[homeId].lampMode = this.awake ? (this.mood === 'purple' ? 'purple' : 'full') : 'dim';
    this.pullsHere = 0;
    this._applyLamps(true);
    if (this.game.nav?.built) this.game.nav.build();
    return true;
  }

  debugFreezeAt(t) { this._freezeAt = t == null ? null : Number(t); return this._freezeAt; }

  debugState() {
    const s = this.seq;
    return {
      homeId: this.homeId, state: this.state, phase: this.phase, awake: this.awake, mood: this.mood, pulls: this.pulls,
      pullsHere: this.pullsHere, pity: this.pity, tapeArmed: this._tapeArmed, dial: this._dialCh(), near: this._near,
      seq: s ? { t: +s.t.toFixed(3), u: +s.u.toFixed(3), phase: s.phase, outcome: s.outcome, item: s.item, ch: s.ch,
        shown: s.shownCh, landT: +s.landT.toFixed(3), bumped: s.bumped, N: s.N, passed: s.passed, dest: s.dest } : null,
      lamps: Object.fromEntries(Object.values(this.homes).map((h) => [h.id, h.lampMode])),
    };
  }
}
